import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import coordinator as c


def pr(sha='a' * 40):
    return {'number': 1, 'draft': False, 'state': 'open', 'base': {'ref': 'main'},
            'head': {'sha': sha, 'repo': {'full_name': c.REPO}}}


def run(name, sha='a' * 40, conclusion='success', attempt=1, number=1):
    return {'id': number, 'name': name, 'head_sha': sha, 'run_number': number,
            'run_attempt': attempt, 'status': 'completed', 'conclusion': conclusion}


class CoordinatorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.co = c.Coordinator(Path(self.temp.name))

    def tearDown(self):
        self.co.state.db.close()
        self.temp.cleanup()

    def test_only_current_commit_and_latest_attempt_count(self):
        runs = c.latest_runs([run('core-tests'), run('core-tests', attempt=2, conclusion='failure'),
                              run('ios-build', sha='b' * 40)], 'a' * 40)
        self.assertFalse(c.checks_ready(runs, ['core-tests']))
        self.assertNotIn('ios-build', runs)

    def test_missing_cancelled_or_skipped_checks_never_pass(self):
        self.assertFalse(c.checks_ready({}, ['core-tests']))
        for result in ('failure', 'cancelled', 'skipped', None):
            self.assertFalse(c.checks_ready({'core-tests': run('core-tests', conclusion=result)}, ['core-tests']))

    def test_custom_run_name_uses_stable_workflow_path(self):
        item = {**run('ios-quick 63/merge'), 'path': '.github/workflows/ios-build.yml'}
        self.assertIn('ios-build', c.latest_runs([item], 'a' * 40))

    def test_quick_dispatch_cannot_replace_full_integration_proof(self):
        item = {**run('ios-quick integration/test'), 'path': '.github/workflows/ios-build.yml',
                'event': 'workflow_dispatch', 'head_branch': 'integration/test',
                'display_title': 'ios-quick integration/test'}
        with patch.object(c, 'github', return_value={'workflow_runs': [item]}):
            self.assertEqual(self.co.candidate_runs({'sha': 'a' * 40, 'branch': 'integration/test'}), {})

    def test_approval_invalidated_by_new_commit_draft_or_wrong_base(self):
        approval = {'sha': 'a' * 40}
        self.assertTrue(c.approval_valid(approval, pr()))
        self.assertFalse(c.approval_valid(approval, pr('b' * 40)))
        p = pr(); p['draft'] = True
        self.assertFalse(c.approval_valid(approval, p))
        p = pr(); p['base']['ref'] = 'other'
        self.assertFalse(c.approval_valid(approval, p))

    def test_independent_review(self):
        with patch.object(self.co, 'pr', return_value=pr()), patch.object(self.co, 'register', return_value={'author': c.CTO, 'authorVerified': True}):
            with self.assertRaises(ValueError):
                self.co.approve(1, 'a' * 40, 'reviewed', c.CTO)
            self.co.approve(1, 'a' * 40, 'board reviewed', 'board', operator=True)

    def test_notification_durable_and_idempotent(self):
        with patch.object(c, 'paperclip', side_effect=lambda *args: {'assigneeAgentId': c.CTO} if len(args) == 1 else {'id': 'wake'}) as api:
            self.co.wake('issue', c.CTO, 'key', 'ready')
            reopened = c.Coordinator(Path(self.temp.name))
            reopened.wake('issue', c.CTO, 'key', 'ready')
            reopened.state.db.close()
            self.assertEqual(api.call_count, 2)
            self.assertEqual(api.call_args.args[2]['idempotencyKey'], 'roadprint:key')

    def test_failed_delivery_is_retried(self):
        with patch.object(c, 'paperclip', side_effect=RuntimeError('unavailable')):
            with self.assertRaises(RuntimeError):
                self.co.wake('issue', c.CTO, 'key', 'ready')
        self.assertIsNone(self.co.state.get('event:key'))

    def test_main_moving_invalidates_candidate_without_promoting(self):
        self.co.state.set('enabled', True)
        self.co.state.set('approvals', {'1': {'sha': 'a' * 40}})
        self.co.state.set('candidate', {'base': 'b' * 40, 'sha': 'c' * 40, 'heads': {'1': 'a' * 40}, 'branch': 'integration/' + 'a'*16 + '-' + 'b'*10})
        with patch.object(self.co, 'pr', return_value=pr()), patch.object(c, 'github', return_value={'object': {'sha': 'd' * 40}}) as gh:
            self.co.integrate()
            self.assertIsNone(self.co.state.get('candidate'))
            self.assertFalse(any(len(call.args) > 1 and call.args[1] == 'PATCH' for call in gh.call_args_list))

    def test_scopes_include_ios_integration_and_privacy_checks(self):
        self.assertEqual(c.required_checks(['docs/readme.md']), ['core-tests'])
        self.assertIn('ios-build', c.required_checks(['RoadPrintCore/Sources/Core.swift']))
        self.assertIn('ios-build', c.required_checks(['Tools/ci/check-privacy-keys.mjs']))
        self.assertIn('fastlane-checks', c.required_checks(['fastlane/Fastfile']))
        self.assertNotIn('fastlane-checks', c.required_checks(['.github/workflows/fastlane-unrelated.yml']))
        self.assertIn('fastlane-checks', c.required_checks(['.github/workflows/new-status.yml']))

    def test_unknown_implementer_cannot_be_approved_by_cto(self):
        with patch.object(self.co, 'pr', return_value=pr()), patch.object(self.co, 'register', return_value={'author': None, 'authorVerified': False}):
            with self.assertRaises(ValueError):
                self.co.approve(1, 'a' * 40, 'reviewed', c.CTO)

    def test_delivery_transfers_task_to_target_without_duplicate_wakeup(self):
        with patch.object(c, 'paperclip', side_effect=[{'assigneeAgentId': c.PLATFORM}, {'id': 'issue'}]) as api:
            self.co.wake('issue', c.CTO, 'review', 'ready')
            self.assertEqual(api.call_count, 2)
            self.assertEqual(api.call_args.args[1], 'PATCH')
            self.assertEqual(api.call_args.args[2]['assigneeAgentId'], c.CTO)

    def test_delivery_never_reopens_terminal_task(self):
        for status in ('done', 'cancelled'):
            with patch.object(c, 'paperclip', return_value={'status': status}) as api:
                self.co.wake('issue', c.CTO, status, 'ready')
                self.assertEqual(api.call_count, 1)

    def test_board_handoff_gets_idempotent_comment_without_reassignment(self):
        with patch.object(c, 'paperclip', side_effect=[{'assigneeUserId': 'board', 'status': 'in_review'}, {'id': 'comment'}]) as api:
            self.co.wake('issue', c.CTO, 'board-delivery', 'ready')
            self.assertEqual(api.call_args.args[0], '/issues/issue/comments')
            self.assertFalse(api.call_args.args[2]['reopen'])
            self.assertFalse(api.call_args.args[2]['resume'])
            self.assertIn('clientRequestId', api.call_args.args[2])

    def test_approved_head_does_not_request_another_review(self):
        self.co.state.set('watches', {'1': {'issue': 'issue', 'author': c.PLATFORM}})
        self.co.state.set('approvals', {'1': {'sha': 'a' * 40}})
        with patch.object(c, 'github', return_value=[]), patch.object(self.co, 'pr', return_value=pr()), patch.object(self.co, 'files', return_value=['docs/readme.md']), patch.object(self.co, 'runs', return_value={'core-tests': run('core-tests')}), patch.object(self.co, 'wake') as wake:
            self.co.notifications()
            wake.assert_not_called()

    def test_reapproval_of_unchanged_head_gets_new_branch(self):
        co = self.co
        co.state.set('enabled', True)
        co.state.set('approvals', {'1': {'sha': 'a' * 40}})
        with patch.object(co, 'pr', return_value=pr()), patch.object(co, 'files', return_value=['docs/readme.md']), patch.object(co, 'runs', return_value={'core-tests': run('core-tests')}), patch.object(co, 'publish'), patch.object(c, 'github', return_value={'object': {'sha': 'b' * 40}}), patch.object(c, 'command', return_value='c' * 40):
            co.integrate()
            first = co.state.get('candidate')
            co.retire(first)
            co.integrate()
            second = co.state.get('candidate')
        self.assertNotEqual(first['branch'], second['branch'])
        self.assertEqual(first['heads'], second['heads'])
        self.assertEqual(first['base'], second['base'])

    def test_cleanup_closes_batch_pr_and_deletes_only_owned_branch(self):
        branch = 'integration/' + 'a' * 16 + '-' + 'b' * 10
        self.co.state.set('retired', [{'branch': branch}])
        with patch.object(c, 'github', side_effect=[[{'number': 99}], {}, [{'ref': 'refs/heads/' + branch}], None]) as gh:
            self.co.cleanup()
        self.assertIn(unittest.mock.call('pulls/99', 'PATCH', {'state': 'closed'}), gh.call_args_list)
        self.assertIn(unittest.mock.call('git/refs/heads/' + branch, 'DELETE'), gh.call_args_list)
        self.assertEqual(self.co.state.get('retired'), [])

    def test_cleanup_rejects_unowned_branch(self):
        self.co.state.set('retired', [{'branch': 'main'}])
        with patch.object(c, 'github') as gh:
            with self.assertRaises(RuntimeError):
                self.co.cleanup()
            gh.assert_not_called()

    def test_success_promotes_exact_sha_without_force(self):
        co = self.co
        co.state.set('enabled', True)
        co.state.set('approvals', {'1': {'sha': 'a' * 40}})
        candidate = {'base': 'b' * 40, 'sha': 'c' * 40, 'heads': {'1': 'a' * 40},
                     'published': True, 'branch': 'integration/test', 'required': ['core-tests']}
        co.state.set('candidate', candidate)
        with patch.object(co, 'pr', return_value=pr()), patch.object(co, 'candidate_runs', return_value={'core-tests': run('core-tests', sha='c' * 40)}), patch.object(c, 'github', return_value={'object': {'sha': 'b' * 40}}) as gh:
            co.integrate()
            self.assertIn(unittest.mock.call('git/refs/heads/main', 'PATCH', {'sha': 'c' * 40, 'force': False}), gh.call_args_list)
            self.assertIsNone(co.state.get('candidate'))

    def test_failed_batch_splits_and_does_not_promote(self):
        co = self.co
        co.state.set('enabled', True)
        co.state.set('approvals', {'1': {'sha': 'a' * 40}, '2': {'sha': 'a' * 40}})
        co.state.set('candidate', {'base': 'b' * 40, 'sha': 'c' * 40, 'heads': {'1': 'a' * 40, '2': 'a' * 40},
                                  'published': True, 'branch': 'integration/test', 'required': ['core-tests']})
        with patch.object(co, 'pr', return_value=pr()), patch.object(co, 'candidate_runs', return_value={'core-tests': run('core-tests', conclusion='failure')}), patch.object(c, 'github', return_value={'object': {'sha': 'b' * 40}}):
            co.integrate()
        self.assertEqual(co.state.get('batch_limit'), 1)
        self.assertEqual(len(co.state.get('approvals')), 2)
        self.assertIsNone(co.state.get('candidate'))


if __name__ == '__main__':
    unittest.main()
