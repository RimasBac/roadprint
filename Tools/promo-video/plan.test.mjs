import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {plan, PlanError, SHOTS, SHOT_ASPECT} from './plan.mjs';

const config = JSON.parse(readFileSync(new URL('./promo.json', import.meta.url), 'utf8'));
const sizes = Object.fromEntries(SHOTS.map((name) => [name, [1320, 2868]]));
const copy = () => structuredClone(config);

test('promo.json makes a 1080×1920 promo of 10 to 60 s from real screenshots', () => {
  const props = plan(config, sizes);
  assert.equal(props.screenAspect, SHOT_ASPECT);
  assert.equal(props.frames, props.scenes.reduce((sum, s) => sum + s.length, 0));
  assert.ok(props.frames >= 300 && props.frames <= 1800);
  for (const scene of props.scenes) assert.ok(SHOTS.includes(scene.shot));
});

test('scenes follow each other, and a pop-out is a rect of its own scene\'s screenshot, in frames', () => {
  const props = plan(config, sizes);
  props.scenes.forEach((scene, i) => {
    if (i) {
      assert.equal(scene.start, props.scenes[i - 1].start + props.scenes[i - 1].length);
      assert.deepEqual(scene.from, props.scenes[i - 1].to);
    }
  });
  const summary = props.scenes.find((s) => s.id === 'summary');
  assert.deepEqual(summary.pops[0].rect, config.rects.tripMap.rect);
  assert.equal(summary.pops[0].at, 21);
});

test('dropping a scene keeps the timeline whole, and the next scene opens from its own pose.from', () => {
  const props = plan(config, sizes, ['map']);
  assert.equal(props.scenes[0].id, 'drive');
  assert.equal(props.scenes[0].start, 0);
  assert.deepEqual(props.scenes[0].from, config.scenes[1].pose.from);
  assert.throws(() => plan(config, sizes, ['nope']), /no scene "nope"/);
  const {'03-my-map': _, ...withoutMap} = sizes;
  assert.throws(() => plan(config, withoutMap), /no 03-my-map.png/);
  assert.doesNotThrow(() => plan(config, withoutMap, ['map']));
});

test('a plan cannot bring in any image but the named screenshots', () => {
  const image = copy(); image.scenes[0].image = 'mockup.png';
  assert.throws(() => plan(image, sizes), /unknown key "image"/);
  const src = copy(); src.rects.tripMap.src = 'art.png';
  assert.throws(() => plan(src, sizes), /unknown key "src"/);
  const other = copy(); other.scenes[0].shot = 'heatmap-mockup';
  assert.throws(() => plan(other, sizes), /unknown screenshot/);
});

test('pop-outs must be on the scene\'s screenshot, fully on screen and inside the scene', () => {
  const wrongShot = copy(); wrongShot.scenes[1].pops[0].rect = 'shareCard';
  assert.throws(() => plan(wrongShot, sizes), /is on 02-night-highway, not 04-drive/);
  const offScreen = copy(); offScreen.rects.tripMap.rect = [0.1, 0.145, 1, 0.37];
  assert.throws(() => plan(offScreen, sizes), /all on it/);
  const late = copy(); late.scenes[1].pops[0].at = 4;
  assert.throws(() => plan(late, sizes), /inside the scene/);
});

test('screenshots must have the 6.9-inch capture shape; same-aspect crops are fine', () => {
  assert.doesNotThrow(() => plan(config, {...sizes, '04-drive': [992, 2155]}));
  assert.throws(() => plan(config, {...sizes, '04-drive': [1080, 1920]}), /not the shape of a 6.9-inch capture/);
  const long = copy(); long.scenes[1].headline = ['A HEADLINE FAR TOO LONG FOR ONE LINE', 'X'];
  assert.throws(() => plan(long, sizes), PlanError);
});
