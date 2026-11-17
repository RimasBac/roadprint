#!/usr/bin/env python3
"""RoadPrint durable CI notifications and reviewed, exact-commit integration.

No candidate code is executed on the control-plane server. Credentials stay in
the existing CLI stores. Run one instance under systemd/flock; SQLite is durable.
"""
import argparse
import hashlib
import hmac
import http.server
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import threading
import time
import urllib.error
import urllib.request

REPO = 'RimasBac/roadprint'
COMPANY = '875f9c51-9ff4-431e-a026-e41afd45e1a4'
CTO = 'd6533f42-235e-4c21-8bf1-ef7f2524e258'
PLATFORM = 'f7a973b0-ea52-4bd1-ad0c-869c842470a4'
API = 'http://127.0.0.1:3100/api'
ROOT = Path(os.environ.get('ROADPRINT_AUTOMATION_HOME', '/data/automation/roadprint'))
AUTH_STORE = Path('/data/operator-cli/auth.json')
SHA = re.compile(r'^[0-9a-f]{40}$')
ISSUE = re.compile(r'\bROA-\d+\b')


def token_in(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if isinstance(item, str) and re.search('token|access', key, re.I) and len(item) > 20:
                return item
            found = token_in(item)
            if found:
                return found
    return None


def board_token():
    token = token_in(json.loads(AUTH_STORE.read_text()))
    if not token:
        raise RuntimeError('Board credential unavailable')
    return token


def paperclip(path, method='GET', data=None, token=None):
    req = urllib.request.Request(API + path, method=method,
        headers={'Authorization': 'Bearer ' + (board_token() if token is None else token), 'Content-Type': 'application/json'},
        data=None if data is None else json.dumps(data).encode())
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def command(args, cwd=None, body=None):
    result = subprocess.run(args, cwd=cwd, input=body, text=True, capture_output=True,
                            timeout=120, env={**os.environ, 'GIT_TERMINAL_PROMPT': '0'})
    if result.returncode:
        # Remote output can contain credential URLs or third-party text; don't log it.
        raise RuntimeError(f'{args[0]} operation failed (exit {result.returncode})')
    return result.stdout.strip()


def github(path, method='GET', data=None):
    args = ['gh', 'api', '--method', method, f'repos/{REPO}/{path}']
    if data is not None:
        args += ['--input', '-']
    output = command(args, body=None if data is None else json.dumps(data))
    return json.loads(output) if output else None


def latest_runs(runs, sha):
    result = {}
    for run in runs:
        if run['head_sha'] != sha:
            continue
        name = run['name']
        if name not in result or (run['run_number'], run.get('run_attempt', 1)) > (
                result[name]['run_number'], result[name].get('run_attempt', 1)):
            result[name] = run
    return result


def checks_ready(runs, required):
    return all(name in runs and runs[name]['status'] == 'completed'
               and runs[name]['conclusion'] == 'success' for name in required)


def needs_ios(files):
    return any(p.startswith(('App/', 'RoadPrintCore/', 'RoadPrintTests/', 'RoadPrintUITests/',
                            'Tools/ci/', '.github/workflows/ios-build'))
               or p in ('project.yml', 'Design/tokens.json') for p in files)


def required_checks(files):
    checks = ['core-tests']
    if needs_ios(files):
        checks.append('ios-build')
    if any(p.startswith(('fastlane/', '.github/workflows/fastlane', '.github/workflows/testflight-status'))
           or p in ('Gemfile', 'Gemfile.lock') for p in files):
        checks.append('fastlane-checks')
    return checks


def approval_valid(approval, pr):
    return (not pr['draft'] and pr['state'] == 'open' and pr['base']['ref'] == 'main'
            and pr['head']['repo']['full_name'] == REPO
            and pr['head']['sha'] == approval['sha'])


class State:
    def __init__(self, filename):
        self.db = sqlite3.connect(filename, check_same_thread=False)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
        self.db.commit()

    def get(self, key, default=None):
        row = self.db.execute('SELECT value FROM state WHERE key=?', (key,)).fetchone()
        return json.loads(row[0]) if row else default

    def set(self, key, value):
        with self.db:
            self.db.execute('INSERT OR REPLACE INTO state VALUES (?,?)', (key, json.dumps(value)))


class Coordinator:
    def __init__(self, root=ROOT):
        self.root = root
        root.mkdir(parents=True, exist_ok=True)
        self.state = State(root / 'state.sqlite')
        self.lock = threading.RLock()
        self.last_ok = 0
        self.last_error = None
        self.state.set('started', self.state.get('started', time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())))

    def pr(self, number):
        if not isinstance(number, int) or number < 1:
            raise ValueError('Positive PR number required')
        return github(f'pulls/{number}')

    def files(self, number):
        files = []
        for page in range(1, 31):
            items = github(f'pulls/{number}/files?per_page=100&page={page}')
            files.extend(item['filename'] for item in items)
            if len(items) < 100:
                return files
        raise RuntimeError('PR exceeds supported file count')

    def wake(self, issue, agent, key, message):
        if self.state.get('event:' + key):
            return
        result = paperclip(f'/agents/{agent}/wakeup', 'POST', {
            'source': 'automation', 'triggerDetail': 'callback', 'reason': message,
            'idempotencyKey': 'roadprint:' + key,
            'payload': {'issueId': issue, 'reason': message, 'source': 'roadprint-coordinator'}})
        # A null response is a policy-skipped wake, not successful delivery.
        if result is None:
            raise RuntimeError('Paperclip did not accept wakeup')
        self.state.set('event:' + key, {'at': time.time(), 'agent': agent})

    def register(self, number, issue_key=None, submitter=None):
        pr = self.pr(number)
        if pr['base']['ref'] != 'main' or pr['head']['repo']['full_name'] != REPO:
            raise ValueError('Only same-repository PRs targeting main are eligible')
        match = ISSUE.search(issue_key or (pr['title'] + ' ' + (pr['body'] or '') + ' ' + pr['head']['ref']))
        if not match:
            raise ValueError('PR must identify its Paperclip issue')
        issue = paperclip('/issues/' + match.group())
        if issue['companyId'] != COMPANY:
            raise ValueError('Wrong company')
        watches = self.state.get('watches', {})
        author = watches.get(str(number), {}).get('author') or submitter or issue.get('assigneeAgentId') or PLATFORM
        watches[str(number)] = {'issue': issue['id'], 'identifier': issue['identifier'],
                                'author': author}
        self.state.set('watches', watches)
        return watches[str(number)]

    def approve(self, number, sha, reason, reviewer, operator=False):
        if not SHA.fullmatch(sha or '') or not reason.strip():
            raise ValueError('Exact SHA and a review reason are required')
        pr = self.pr(number)
        if not approval_valid({'sha': sha}, pr):
            raise ValueError('PR changed, is draft, or is not eligible')
        watch = self.register(number)
        if not operator and (reviewer != CTO or reviewer == watch['author']):
            raise ValueError('Independent CTO review or board approval required')
        approvals = self.state.get('approvals', {})
        approvals[str(number)] = {'sha': sha, 'reviewer': reviewer, 'reason': reason, 'at': time.time()}
        self.state.set('approvals', approvals)
        return {'approved': number, 'sha': sha}

    def runs(self, sha):
        return latest_runs(github(f'actions/runs?head_sha={sha}&per_page=100')['workflow_runs'], sha)

    def notifications(self):
        # Polling is the durable recovery path even when webhooks are enabled.
        for pr in github('pulls?state=open&base=main&per_page=100'):
            if pr['head']['ref'].startswith('integration/') or pr['updated_at'] < self.state.get('started'):
                continue
            if str(pr['number']) not in self.state.get('watches', {}):
                try:
                    self.register(pr['number'])
                except ValueError:
                    continue
        watches = self.state.get('watches', {})
        for number, watch in list(watches.items()):
            pr = self.pr(int(number))
            if pr['state'] != 'open':
                watches.pop(number)
                self.state.set('watches', watches)
                continue
            sha = pr['head']['sha']
            runs = self.runs(sha)
            required = required_checks(self.files(int(number)))
            for name in required:
                run = runs.get(name)
                if run and run['status'] == 'completed' and run['conclusion'] in ('failure', 'timed_out', 'action_required'):
                    self.wake(watch['issue'], watch['author'], f'fail:{run["id"]}:{run.get("run_attempt", 1)}',
                              f'PR #{number} {sha[:12]}: {name} failed. Read {run["html_url"]}; fix all observed failures together. Do not poll CI.')
            if checks_ready(runs, required) and not pr['draft']:
                self.wake(watch['issue'], CTO, f'review:{number}:{sha}',
                          f'PR #{number} {sha}: initial checks passed. Review this exact diff. If accepted, use Tools/automation/client.py approve {number} {sha} --reason "review findings". The coordinator runs full integration and merges. Do not wait or merge manually.')

    def candidate_runs(self, candidate):
        all_runs = github(f'actions/runs?head_sha={candidate["sha"]}&per_page=100')['workflow_runs']
        return latest_runs([r for r in all_runs if r['head_branch'] == candidate['branch']
                            and r['event'] == 'workflow_dispatch'], candidate['sha'])

    def integrate(self):
        if not self.state.get('enabled', False):
            return
        approvals = self.state.get('approvals', {})
        candidate = self.state.get('candidate')
        if candidate:
            # Every approval is bound to an exact head; edits or revocation invalidate the candidate.
            valid = all(n in approvals and approvals[n]['sha'] == sha
                        and approval_valid(approvals[n], self.pr(int(n))) for n, sha in candidate['heads'].items())
            main = github('git/ref/heads/main')['object']['sha']
            if main == candidate.get('sha'):
                self.finish(candidate)
                return
            if not valid or main != candidate['base']:
                self.state.set('candidate', None)
                return
            if not candidate.get('published'):
                self.publish(candidate)
                return
            runs = self.candidate_runs(candidate)
            for workflow in candidate['required']:
                if workflow not in runs:
                    # Persist dispatch time before issuing it; allow recovery after a lost response.
                    key = 'dispatch:' + candidate['branch'] + ':' + workflow
                    if time.time() - self.state.get(key, 0) > 300:
                        self.state.set(key, time.time())
                        inputs = {'evidence': 'regression'} if workflow == 'ios-build' else {}
                        github(f'actions/workflows/{workflow}.yml/dispatches', 'POST',
                               {'ref': candidate['branch'], 'inputs': inputs})
            failed = any(r['status'] == 'completed' and r['conclusion'] not in ('success',)
                         for name, r in runs.items() if name in candidate['required'])
            if failed:
                if len(candidate['heads']) > 1:
                    self.state.set('batch_limit', 1)
                else:
                    number = next(iter(candidate['heads']))
                    approvals.pop(number, None)
                    self.state.set('approvals', approvals)
                    watch = self.state.get('watches', {})[number]
                    self.wake(watch['issue'], watch['author'], 'integration-fail:' + candidate['sha'],
                              f'Integration of PR #{number} failed on {candidate["sha"]}. Inspect Actions on branch {candidate["branch"]}. Fix and obtain new review; no automatic retry.')
                self.state.set('candidate', None)
                return
            if checks_ready(runs, candidate['required']):
                # Final re-read, then atomic non-force ref update. A concurrent main change
                # not contained in this candidate makes GitHub reject the fast-forward.
                if github('git/ref/heads/main')['object']['sha'] != candidate['base']:
                    self.state.set('candidate', None)
                    return
                github('git/refs/heads/main', 'PATCH', {'sha': candidate['sha'], 'force': False})
                self.finish(candidate)
            return
        eligible = []
        for number, approval in list(approvals.items()):
            pr = self.pr(int(number))
            if not approval_valid(approval, pr):
                approvals.pop(number)
                self.state.set('approvals', approvals)
                continue
            if checks_ready(self.runs(approval['sha']), required_checks(self.files(int(number)))):
                eligible.append((number, approval))
        if not eligible:
            return
        heads = {n: a['sha'] for n, a in eligible[:self.state.get('batch_limit', 2)]}
        base = github('git/ref/heads/main')['object']['sha']
        digest = hashlib.sha256(json.dumps([base, heads], sort_keys=True).encode()).hexdigest()[:16]
        branch = 'integration/' + digest
        repo = self.root / 'integration-repo'
        if not (repo / '.git').exists():
            command(['git', 'clone', '--no-checkout', 'https://github.com/' + REPO + '.git', str(repo)])
            command(['git', 'config', 'user.name', 'RoadPrint Integration'], repo)
            command(['git', 'config', 'user.email', 'roadprint-integration@users.noreply.github.com'], repo)
        command(['git', 'fetch', 'origin', 'main'], repo)
        command(['git', 'checkout', '--detach', base], repo)
        for number, sha in heads.items():
            command(['git', 'fetch', 'origin', f'refs/pull/{number}/head'], repo)
            try:
                command(['git', 'merge', '--no-ff', '-m', f'integrate: PR #{number} ({sha[:12]})', sha], repo)
            except RuntimeError:
                command(['git', 'merge', '--abort'], repo)
                self.state.set('batch_limit', 1)
                approvals.pop(number, None)
                self.state.set('approvals', approvals)
                watch = self.state.get('watches', {})[number]
                self.wake(watch['issue'], watch['author'], 'conflict:' + number + ':' + sha + ':' + base,
                          f'PR #{number} conflicts during integration. Rebase on main, resolve the conflict, and request review again.')
                return
        sha = command(['git', 'rev-parse', 'HEAD'], repo)
        candidate = {'base': base, 'heads': heads, 'sha': sha, 'branch': branch,
                     'required': ['core-tests', 'ios-build', 'fastlane-checks'], 'published': False}
        self.state.set('candidate', candidate)
        self.publish(candidate)

    def publish(self, candidate):
        repo = self.root / 'integration-repo'
        command(['git', '-c', 'credential.helper=!gh auth git-credential', 'push', 'origin',
                 candidate['sha'] + ':refs/heads/' + candidate['branch']], repo)
        # An inspectable PR records the exact tested batch; original PR heads are ancestors.
        existing = github('pulls?state=open&head=RimasBac:' + candidate['branch'])
        if not existing:
            github('pulls', 'POST', {'title': 'Integration: ' + ', '.join('#' + n for n in candidate['heads']),
                'head': candidate['branch'], 'base': 'main',
                'body': 'Approved heads: ' + json.dumps(candidate['heads']) + '\n\nFull checks run on this exact commit before atomic fast-forward promotion. Independent reviews are recorded in the coordinator.'})
        candidate['published'] = True
        self.state.set('candidate', candidate)

    def finish(self, candidate):
        approvals = self.state.get('approvals', {})
        for number in candidate['heads']:
            approvals.pop(number, None)
            watch = self.state.get('watches', {}).get(number)
            if watch:
                self.wake(watch['issue'], CTO, 'merged:' + number + ':' + candidate['sha'],
                          f'PR #{number} integrated as {candidate["sha"]}; full core, iOS regression and fastlane checks passed on that exact commit. Update task disposition; release remains a separate milestone action.')
        self.state.set('approvals', approvals)
        self.state.set('last_integrated', candidate)
        self.state.set('candidate', None)
        self.state.set('batch_limit', 2)

    def tick(self):
        with self.lock:
            self.notifications()
            self.integrate()
            self.last_ok = time.time()
            self.last_error = None


def serve():
    coordinator = Coordinator()
    secret = (ROOT / 'webhook-secret').read_bytes().strip()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def reply(self, code, body):
            payload = json.dumps(body).encode()
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self):
            if self.path != '/health':
                return self.reply(404, {})
            return self.reply(200, {'ok': coordinator.last_error is None, 'last_ok': coordinator.last_ok,
                                   'error': coordinator.last_error,
                                   'integration_enabled': coordinator.state.get('enabled', False)})

        def do_POST(self):
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if length < 1 or length > 1024 * 1024:
                    return self.reply(413, {})
                raw = self.rfile.read(length)
                if self.path == '/hooks/roadprint':
                    expected = 'sha256=' + hmac.new(secret, raw, hashlib.sha256).hexdigest()
                    if not hmac.compare_digest(expected, self.headers.get('X-Hub-Signature-256', '')):
                        return self.reply(403, {})
                    data = json.loads(raw)
                    if data.get('repository', {}).get('full_name') != REPO:
                        return self.reply(403, {})
                    # Treat the event only as a hint; authoritative data is always re-read.
                    wake_event.set()
                    return self.reply(202, {'accepted': True})
                auth = self.headers.get('Authorization', '').removeprefix('Bearer ')
                if not auth:
                    return self.reply(401, {})
                operator = bool(auth) and hmac.compare_digest(auth, board_token())
                agent = {'id': 'board', 'companyId': COMPANY} if operator else paperclip('/agents/me', token=auth)
                if agent['companyId'] != COMPANY:
                    return self.reply(403, {})
                data = json.loads(raw)
                with coordinator.lock:
                    if self.path == '/watch':
                        result = coordinator.register(data['pr'], data.get('issue'), None if operator else agent['id'])
                    elif self.path == '/approve':
                        result = coordinator.approve(data['pr'], data['sha'], data['reason'], agent['id'], operator)
                    elif self.path == '/enable' and operator:
                        coordinator.state.set('enabled', bool(data['enabled']))
                        result = {'enabled': bool(data['enabled'])}
                    else:
                        return self.reply(403, {})
                wake_event.set()
                return self.reply(200, result)
            except (ValueError, KeyError):
                return self.reply(400, {'error': 'Invalid request or ineligible PR'})
            except urllib.error.HTTPError as error:
                return self.reply(403 if error.code in (401, 403) else 502, {'error': 'Paperclip request failed'})
            except Exception as error:
                return self.reply(503, {'error': type(error).__name__})

    wake_event = threading.Event()
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 3111), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    while True:
        try:
            coordinator.tick()
        except Exception as error:
            coordinator.last_error = type(error).__name__ + ': ' + (str(error) if isinstance(error, RuntimeError) else 'operation failed')
            print(json.dumps({'error': coordinator.last_error}), flush=True)
        wake_event.wait(60)
        wake_event.clear()


if __name__ == '__main__':
    serve()
