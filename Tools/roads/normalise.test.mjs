import test from 'node:test';
import assert from 'node:assert/strict';
import { normalise } from './normalise.mjs';

const cases = [
  [{ country: 'US', name: '80', prefix: 'I', level: 'Interstate' }, 'usInterstate', '80'],
  [{ country: 'US', name: '95', level: 'Interstate' }, 'usInterstate', '95'],
  [{ country: 'US', name: '20', prefix: 'US', level: 'Federal' }, 'usHighway', '20'],
  [{ country: 'US', name: '169', level: 'Federal' }, 'usHighway', '169'],
  [{ country: 'US', name: '83', level: 'State' }, 'generic', '83'],
  [{ country: 'CA', name: '1', level: 'Federal' }, 'canadaHighway', '1'],
  [{ country: 'CA', name: '138', level: 'State' }, 'canadaHighway', '138'],
  [{ country: 'CA', name: 'ALT1', prefix: 'US', level: 'Federal' }, 'generic', 'ALT1'],
  [{ country: 'MX', name: '15D', level: 'Federal' }, 'generic', '15D'],
  [{ country: 'BE', name: '40', label: 'E40', local: 'A10', prefix: 'E', level: 'E', routeraw: 'E40 A10' }, 'eRoad', 'E40'],
  [{ country: 'DE', name: '31', label: 'E31', label2: 'A61', local: 'A61', prefix: 'E', level: 'E' }, 'eRoad', 'E31'],
  [{ country: 'LT', label: 'E85' }, 'eRoad', 'E85'],
  [{ country: 'TR', name: '881', label: 'E881', label2: '32', prefix: 'E', level: 'E' }, 'eRoad', 'E881'],
  [{ country: 'DE', label: 'A65', local: 'A65', routeraw: 'A65' }, 'generic', 'A65'],
  [{ country: 'FR', local: 'D13', routeraw: 'D13' }, 'generic', 'D13'],
  [{ country: 'GB', label: 'M6', local: 'M6' }, 'ukMotorway', 'M6'],
  [{ country: 'GB', local: 'A1(M)' }, 'ukMotorway', 'A1(M)'],
  [{ country: 'GB', label: 'A40', local: 'A40' }, 'ukARoad', 'A40'],
  [{ country: 'GB', name: '15', label: 'E15', label2: 'A1', local: 'A1', prefix: 'E', level: 'E' }, 'ukARoad', 'A1'],
  [{ country: 'GB', name: '30', label: 'E30', prefix: 'E', level: 'E' }, 'eRoad', 'E30'],
  [{ country: 'NZ', label: 'SH1', local: 'SH1' }, 'generic', 'SH1'],
  [{ country: 'DE', local: 'A4 A12' }, 'generic', 'A4'],
];

for (const [input, network, ref] of cases) {
  test(`${JSON.stringify(input)} → ${network} ${ref}`, () => {
    assert.deepEqual(normalise(input), { network, ref });
  });
}

test('junk and empty records have no ref', () => {
  assert.equal(normalise({ country: 'AU' }), null);
  assert.equal(normalise({ country: 'DE', routeraw: '_untitled_134' }), null);
  assert.equal(normalise({ country: 'FR', name: '_untitled_5' }), null);
});
