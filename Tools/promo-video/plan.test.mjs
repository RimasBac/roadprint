import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {FPS, plan, PlanError, SHOTS, SHOT_ASPECT} from './plan.mjs';

const config = JSON.parse(readFileSync(new URL('./promo.json', import.meta.url), 'utf8'));
const sizes = Object.fromEntries(SHOTS.map((name) => [name, [1320, 2868]]));
const copy = () => structuredClone(config);
const BEAT = (60 / config.bpm) * FPS;

test('promo.json makes a 1080×1920 promo of 10 to 60 s from real captures, ending on the end title', () => {
  const props = plan(config, sizes);
  assert.equal(props.screenAspect, SHOT_ASPECT);
  assert.equal(props.frames, props.shots.reduce((sum, s) => sum + s.length, 0));
  assert.ok(props.frames >= 10 * FPS && props.frames <= 60 * FPS);
  assert.equal(props.shots.at(-1).kind, 'end');
  for (const s of props.shots.filter((s) => s.kind === 'screen')) assert.ok(SHOTS.includes(s.shot));
});

test('shots sit on the beat grid, back to back', () => {
  const props = plan(config, sizes);
  props.shots.forEach((s, i) => {
    assert.equal(s.length % BEAT, 0);
    if (i) assert.equal(s.start, props.shots[i - 1].start + props.shots[i - 1].length);
  });
  const summary = props.shots.find((s) => s.id === 'summary');
  assert.deepEqual(summary.zooms[0], {rect: config.rects.tripMap.rect, at: 2 * BEAT, length: 5 * BEAT});
});

test('the phone rises in after a title and stays for the screens that follow', () => {
  const props = plan(config, sizes);
  assert.deepEqual(props.shots.filter((s) => s.kind === 'screen').map((s) => s.rise), [true, false, false, false]);
  const dropped = plan(config, sizes, ['map']);
  assert.equal(dropped.shots[1].id, 'drive');
  assert.equal(dropped.shots[1].rise, true);
  assert.equal(dropped.shots[1].start, dropped.shots[0].length);
  assert.throws(() => plan(config, sizes, ['nope']), /no shot "nope"/);
  const {'promo-my-map': _, ...withoutMap} = sizes;
  assert.throws(() => plan(config, withoutMap), /no promo-my-map.png/);
  assert.doesNotThrow(() => plan(config, withoutMap, ['map']));
});

test('a plan cannot bring in any image but the named captures', () => {
  const image = copy(); image.shots[1].image = 'mockup.png';
  assert.throws(() => plan(image, sizes), /unknown key "image"/);
  const src = copy(); src.rects.tripMap.src = 'art.png';
  assert.throws(() => plan(src, sizes), /unknown key "src"/);
  const other = copy(); other.shots[1].shot = 'heatmap-mockup';
  assert.throws(() => plan(other, sizes), /unknown capture/);
  const kind = copy(); kind.shots[0].kind = 'video';
  assert.throws(() => plan(kind, sizes), /kind must be/);
});

test('zooms: a rect of the same capture, on beats, one after another, inside the shot', () => {
  const wrong = copy(); wrong.shots[2].zooms[0].rect = 'shareCard';
  assert.throws(() => plan(wrong, sizes), /is on 02-night-highway, not 04-drive/);
  const overlap = copy(); overlap.shots[3].zooms[1].at = 5;
  assert.throws(() => plan(overlap, sizes), /later beat/);
  const late = copy(); late.shots[2].zooms[0].at = 6;
  assert.throws(() => plan(late, sizes), /end by the shot's end/);
  const offGrid = copy(); offGrid.shots[2].zooms[0].at = 2.5;
  assert.throws(() => plan(offGrid, sizes), PlanError);
});

test('type must fit: short title lines, one per beat; two-line headlines', () => {
  const long = copy(); long.shots[0].lines = ['A TITLE FAR TOO LONG'];
  assert.throws(() => plan(long, sizes), /1 to 12 characters/);
  const crowded = copy(); crowded.shots[0].beats = 2;
  assert.throws(() => plan(crowded, sizes), /one line per beat/);
  const oneLine = copy(); oneLine.shots[2].headline = ['ONE LINE'];
  assert.throws(() => plan(oneLine, sizes), /2–2 lines/);
  assert.throws(() => plan(config, {...sizes, '04-drive': [1080, 1920]}), /not the shape of a 6.9-inch capture/);
});
