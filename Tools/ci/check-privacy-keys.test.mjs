import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { check, readProperties } from './check-privacy-keys.mjs';

const yml = (props) => `targets:
  RoadPrint:
    type: application
    info:
      path: App/Info.plist
      properties:
${props.map((l) => '        ' + l).join('\n')}
    settings:
      base:
        X: 1
`;
const build4 = yml(['UIBackgroundModes: [location]', 'NSLocationWhenInUseUsageDescription: Route.']);
const fixed = yml(['UIBackgroundModes: [location]', 'NSLocationWhenInUseUsageDescription: Route.', 'NSMotionUsageDescription: Barometer.']);
const altimeter = [{ path: 'App/Location/CoreLocationSource.swift', source: 'import CoreMotion\nlet a = CMAltimeter()\n' }];

test('build 4 setup (altimeter, no motion key) fails with one plain line', () => {
  const problems = check(readProperties(build4), altimeter);
  assert.deepEqual(problems, ['App/Location/CoreLocationSource.swift: CMAltimeter needs NSMotionUsageDescription in project.yml']);
});

test('the fixed setup passes', () => {
  assert.deepEqual(check(readProperties(fixed), altimeter), []);
});

test('background location needs UIBackgroundModes', () => {
  const src = [{ path: 'App/L.swift', source: 'm.allowsBackgroundLocationUpdates = true' }];
  assert.equal(check(readProperties(yml(['NSLocationWhenInUseUsageDescription: x'])), src).length, 1);
  assert.deepEqual(check(readProperties(build4), src), []);
});

test('list-style UIBackgroundModes and comments are handled', () => {
  const props = readProperties(yml(['UIBackgroundModes:', '  - audio', '  - location']));
  assert.deepEqual(props.UIBackgroundModes, ['audio', 'location']);
  assert.deepEqual(check({}, [{ path: 'a.swift', source: '// CMAltimeter\n/* PHPhotoLibrary */' }]), []);
});

test('photos, camera and contacts', () => {
  const f = (s) => [{ path: 'App/X.swift', source: s }];
  assert.equal(check({}, f('PHPhotoLibrary.shared()')).length, 1);
  assert.deepEqual(check({ NSPhotoLibraryAddUsageDescription: 'x' }, f('PHPhotoLibrary.shared()')), []);
  assert.equal(check({ NSPhotoLibraryAddUsageDescription: 'x' }, f('PHAsset.fetchAssets')).length, 1);
  assert.equal(check({}, f('AVCaptureSession()')).length, 1);
  assert.equal(check({}, f('import Contacts')).length, 1);
  assert.deepEqual(check({}, f('UNUserNotificationCenter.current()')), []);
});

test('current main passes', () => {
  const out = execFileSync('node', [new URL('./check-privacy-keys.mjs', import.meta.url).pathname], { encoding: 'utf8' });
  assert.match(out, /privacy keys ok/);
});
