import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {plan, PlanError} from './render.mjs';

const config = JSON.parse(readFileSync(new URL('./promo.json', import.meta.url), 'utf8'));
const markers = {
  clock: 'unix', window: [440, 956],
  marks: {drive: 102, summary: 118, cardVideo: 125, myMap: 140, filters: 147, end: 160},
  rects: {heatMap: [16, 260, 408, 330], tripMap: [0, 110, 440, 300], elevationChart: [16, 520, 408, 150],
    shareCard: [40, 150, 360, 600]},
};

test('maps marks into the recording and rects into screen fractions', () => {
  const props = plan(config, markers, 100, 80);
  assert.equal(props.scenes[0].sourceStart, 40.2);
  assert.deepEqual(props.scenes[0].pops[0].rect, [16 / 440, 260 / 956, 408 / 440, 330 / 956]);
  assert.deepEqual(props.scenes[1].from, config.scenes[0].pose.to);
  assert.equal(props.screenAspect, 440 / 956);
});

test('rejects anything but timings, poses, headlines and recorded regions', () => {
  const withImage = structuredClone(config);
  withImage.scenes[0].image = 'mockup.png';
  assert.throws(() => plan(withImage, markers, 100, 80), /unknown key "image"/);
  const withOverlay = structuredClone(config);
  withOverlay.scenes[0].pops[0].src = 'art.png';
  assert.throws(() => plan(withOverlay, markers, 100, 80), /unknown key "src"/);
});

test('pop-outs must be regions the UI test measured, inside the scene', () => {
  const noRect = structuredClone(markers);
  delete noRect.rects.shareCard;
  assert.throws(() => plan(config, noRect, 100, 80), /no frame for "shareCard"/);
  const late = structuredClone(config);
  late.scenes[0].pops[0].at = 5;
  assert.throws(() => plan(late, markers, 100, 80), /runs past the scene/);
});

test('scenes must lie inside the recording', () => {
  assert.throws(() => plan(config, markers, 100, 50), PlanError);
  assert.throws(() => plan(config, {...markers, window: undefined}, 100, 80), /window size/);
});
