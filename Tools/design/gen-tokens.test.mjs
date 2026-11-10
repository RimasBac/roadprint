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
