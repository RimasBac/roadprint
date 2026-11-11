"""Create the exact feel-standard devices; never silently substitute hardware."""
import json
import os
from pathlib import Path
import subprocess


def simctl(*args):
    return subprocess.check_output(['xcrun', 'simctl', *args], text=True)


inventory = json.loads(simctl('list', '--json'))
runtimes = [r for r in inventory['runtimes']
            if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
if not runtimes:
    raise SystemExit('No available iOS runtime: required evidence cannot be collected.')
runtime = max(runtimes, key=lambda r: tuple(int(x) for x in r['version'].split('.')))
required = [('SIM_UDID', 'iPhone 16', 'iPhone-16'),
            ('SIM_SE_UDID', 'iPhone SE (3rd generation)', 'iPhone-SE-3rd-generation'),
            ('SIM_MAX_UDID', 'iPhone 16 Pro Max', 'iPhone-16-Pro-Max')]
types = {d['identifier'] for d in inventory['devicetypes']}
report = {'runtime': runtime['name'], 'devices': [], 'unavailable': []}
env = []
for key, name, suffix in required:
    identifier = 'com.apple.CoreSimulator.SimDeviceType.' + suffix
    try:
        if identifier not in types:
            raise ValueError('Device type absent from Xcode inventory')
        udid = simctl('create', 'RoadPrint ' + name, identifier, runtime['identifier']).strip()
        report['devices'].append({'name': name, 'type': identifier, 'udid': udid})
        env.append(f'{key}={udid}\n')
    except (ValueError, subprocess.CalledProcessError) as error:
        report['unavailable'].append({'name': name, 'reason': str(error)})
Path('build').mkdir(exist_ok=True)
Path('build/device-evidence.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
if report['unavailable']:
    raise SystemExit('Required simulator unavailable. Explicit scope decision needed; no substitute used.')
with open(os.environ['GITHUB_ENV'], 'a') as output:
    output.writelines(env)
