"""Create the exact feel-standard devices; never silently substitute hardware."""
import json
import os
from pathlib import Path
import re
import subprocess


def simctl(*args):
    return subprocess.check_output(['xcrun', 'simctl', *args], text=True)


runtime_prefix = 'com.apple.CoreSimulator.SimRuntime.iOS-'


def runtime_priority(runtime):
    version = tuple(int(part) for part in runtime['version'].split('.'))
    suffix = runtime['identifier'].removeprefix(runtime_prefix)
    generic = re.fullmatch(r'\d+(?:-\d+)*', suffix) is not None
    return version, generic, runtime['identifier']


required = [('SIM_UDID', 'iPhone 16', 'iPhone-16'),
            ('SIM_SE_UDID', 'iPhone SE (3rd generation)', 'iPhone-SE-3rd-generation'),
            ('SIM_MAX_UDID', 'iPhone 16 Pro Max', 'iPhone-16-Pro-Max')]
evidence = os.environ.get('EVIDENCE', 'routine')
if evidence == 'appstore':
    _, name, suffix = required[-1]
    required = [('SIM_UDID', name, suffix)]
elif evidence != 'full':
    required = required[:1]
required = [
    (key, name, 'com.apple.CoreSimulator.SimDeviceType.' + suffix)
    for key, name, suffix in required
]

inventory = json.loads(simctl('list', '--json'))
runtimes = [runtime for runtime in inventory['runtimes']
            if runtime.get('isAvailable') and runtime['identifier'].startswith(runtime_prefix)]
required_types = {identifier for _, _, identifier in required}
compatible_runtimes = [
    runtime for runtime in runtimes
    if required_types.issubset(
        device['identifier'] for device in runtime.get('supportedDeviceTypes', [])
    )
]
if not compatible_runtimes:
    device_names = ', '.join(name for _, name, _ in required)
    available = ', '.join(runtime['identifier'] for runtime in runtimes) or 'none'
    raise SystemExit(
        f'No available iOS runtime supports all required devices ({device_names}). '
        f'Available iOS runtimes: {available}. No substitute used.'
    )
runtime = max(compatible_runtimes, key=runtime_priority)
print(f"Selected iOS simulator runtime: {runtime['identifier']}", flush=True)

types = {d['identifier'] for d in inventory['devicetypes']}
report = {'runtime': runtime['name'], 'runtimeIdentifier': runtime['identifier'],
          'devices': [], 'unavailable': []}
env = []
for key, name, identifier in required:
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
