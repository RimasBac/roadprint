import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { generate, sourceURL, outputURL, assetOutputs } from './gen-tokens.mjs';
const source = () => JSON.parse(readFileSync(sourceURL, 'utf8'));
const render = t => generate(t, () => {});
test('committed output is current, deterministic, and independent of source key order', () => {
  const t=source(), output=render(t);
  assert.equal(output, readFileSync(outputURL,'utf8'));
  for (const [url, content] of assetOutputs(t)) assert.equal(content, readFileSync(url, 'utf8'));
  assert.equal(output,render(t));
  const reverse = v => Array.isArray(v) ? v.map(reverse) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).reverse().map(([k,x])=>[k,reverse(x)])) : v;
  assert.equal(output,render(reverse(t)));
});
for (const theme of ['color','colorDay']) {
  test(`${theme}: rejects low-contrast secondary text and button labels`, () => {
    for (const [fg,bg] of [['textSecondary','land'],['buttonPrimaryLabel','buttonPrimary']]) {
      const t=source();t[theme][fg].$value=t[theme][bg].$value;
      assert.throws(()=>render(t),/Contrast below/);
    }
  });
}
test('missing day pair fails', () => {
  const t=source();delete t.colorDay.card;
  assert.throws(()=>render(t),/Missing day color card/);
});
test('unknown types, unresolved references and cycles fail, even in skipped terrain', () => {
  let t=source();t.terrain.water.$type='unknown';
  assert.throws(()=>render(t),/Unknown token type/);
  t=source();t.terrain.type.title.$value.color='{color.missing}';
  assert.throws(()=>render(t),/Unresolved token/);
  t=source();t.color.text.$value='{color.textSecondary}';t.color.textSecondary.$value='{color.text}';
  assert.throws(()=>render(t),/Cyclic reference/);
});
test('valid aliases resolve before numeric validation and generation', () => {
  const t=source();t.space.l.$value='{space.m}';
  assert.match(render(t),/static let l: CGFloat = 12/);
});

test('launch assets resolve Background and Ink aliases through the same validated palettes as Swift', () => {
  const t = source();
  t.colorDay.background.$value = '{colorDay.land}';
  t.colorDay.text.$value = '{colorDay.buttonPrimaryLabel}';
  t.color.background.$value = '{color.land}';
  t.color.text.$value = '{terrain.snow.color}';
  const output = render(t);
  const assets = assetOutputs(t).map(([, content]) => JSON.parse(content));
  const components = hex => ({red: '0x' + hex.slice(1,3).toUpperCase(),
    green: '0x' + hex.slice(3,5).toUpperCase(), blue: '0x' + hex.slice(5,7).toUpperCase(), alpha: '1.000'});
  assert.deepEqual(assets[0].colors.map(c => c.color.components),
    [components(t.colorDay.land.$value), components(t.color.land.$value)]);
  assert.deepEqual(assets[1].colors.map(c => c.color.components),
    [components(t.colorDay.buttonPrimaryLabel.$value), components(t.terrain.snow.color.$value)]);
  assert.match(output, /enum Night/);
  const invalid = source(); invalid.colorDay.background.$value = '{colorDay.missing}';
  assert.throws(() => assetOutputs(invalid), /Unresolved token/);
  invalid.colorDay.background.$value = 'invalid';
  assert.throws(() => assetOutputs(invalid), /Invalid sRGB hex/);
});
