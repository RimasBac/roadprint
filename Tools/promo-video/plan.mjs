// promo.json → the composition's props. Pure, so plan.test.mjs can check every rule.
//
// The rule this enforces: every app pixel in the promo is a real screenshot of the app. A plan
// names screenshots by their CI capture names and lifts rectangles out of them; it has no way to
// bring in any other image, and unknown keys are refused.
import {closeSync, openSync, readSync} from 'node:fs';

/** The App Store captures, by the names the `appstore-screenshots` CI artifact uses. */
export const SHOTS = ['01-trip-summary', '02-night-highway', '03-my-map', '04-drive', '05-trip-card-video'];
/** The 6.9-inch capture is 1320×2868; same-aspect crops of it (framed-shots.mjs) are accepted. */
export const SHOT_ASPECT = 1320 / 2868;
export const FPS = 30;

export class PlanError extends Error {}

function only(value, required, optional, where) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new PlanError(`${where}: expected an object`);
  for (const key of Object.keys(value)) {
    if (!required.includes(key) && !optional.includes(key)) throw new PlanError(`${where}: unknown key "${key}"`);
  }
  for (const key of required) if (!(key in value)) throw new PlanError(`${where}: missing "${key}"`);
}

function pose(value, where) {
  only(value, ['rx', 'ry', 'z', 'y'], [], where);
  for (const [k, v] of Object.entries(value)) if (!Number.isFinite(v)) throw new PlanError(`${where}.${k} must be a number`);
  return value;
}

const frames = (seconds) => Math.round(seconds * FPS);

/**
 * @param config  promo.json
 * @param sizes   screenshot name → [width, height] of the files on hand
 * @param drop    scene ids to leave out (a screenshot not captured yet)
 */
export function plan(config, sizes, drop = []) {
  only(config, ['output', 'rects', 'scenes'], [], 'promo.json');
  const {width, height, fps} = config.output ?? {};
  if (width !== 1080 || height !== 1920 || fps !== FPS) throw new PlanError('output must be 1080×1920 at 30 fps');

  for (const [name, entry] of Object.entries(config.rects)) {
    const where = `rect "${name}"`;
    only(entry, ['shot', 'rect'], [], where);
    if (!SHOTS.includes(entry.shot)) throw new PlanError(`${where}: unknown screenshot "${entry.shot}"`);
    const r = entry.rect;
    const valid = Array.isArray(r) && r.length === 4 && r.every((v) => Number.isFinite(v) && v >= 0)
      && r[2] > 0 && r[3] > 0 && r[0] + r[2] <= 1.0001 && r[1] + r[3] <= 1.0001;
    if (!valid) throw new PlanError(`${where}: rect must be [x, y, width, height] in fractions of the screen, all on it`);
  }

  for (const id of drop) if (!config.scenes.some((s) => s.id === id)) throw new PlanError(`--drop: no scene "${id}"`);
  let previous = null;
  let start = 0;
  const scenes = [];
  for (const [i, scene] of config.scenes.entries()) {
    const where = `scene ${scene.id ?? i}`;
    only(scene, ['id', 'shot', 'seconds', 'headline', 'pose', 'pops'], ['endCard'], where);
    // `from` is where the camera starts when this scene opens the promo; a later scene always
    // continues from where the one before it ended, so dropping a scene never makes the phone jump.
    only(scene.pose, ['to'], ['from'], `${where}.pose`);
    const opening = scene.pose.from ? pose(scene.pose.from, `${where}.pose.from`) : null;
    const to = pose(scene.pose.to, `${where}.pose.to`);
    if (drop.includes(scene.id)) continue;
    const from = previous ?? opening;
    if (!from) throw new PlanError(`${where}: the opening scene needs pose.from`);
    previous = to;

    if (!SHOTS.includes(scene.shot)) throw new PlanError(`${where}: unknown screenshot "${scene.shot}"`);
    const size = sizes[scene.shot];
    if (!size) throw new PlanError(`${where}: no ${scene.shot}.png`);
    if (Math.abs(size[0] / size[1] / SHOT_ASPECT - 1) > 0.005) {
      throw new PlanError(`${where}: ${scene.shot}.png is ${size[0]}×${size[1]}, not the shape of a 6.9-inch capture`);
    }
    if (!(scene.seconds >= 1)) throw new PlanError(`${where}: seconds must be at least 1`);
    const valid = Array.isArray(scene.headline) && scene.headline.length === 2
      && scene.headline.every((line) => typeof line === 'string' && line.length > 0 && line.length <= 26);
    if (!valid) throw new PlanError(`${where}: headline must be two lines of 1 to 26 characters`);

    const pops = scene.pops.map((pop, j) => {
      only(pop, ['rect', 'at', 'hold'], ['face'], `${where}.pops[${j}]`);
      const entry = config.rects[pop.rect];
      if (!entry) throw new PlanError(`${where}: no rect "${pop.rect}"`);
      if (entry.shot !== scene.shot) throw new PlanError(`${where}: rect "${pop.rect}" is on ${entry.shot}, not ${scene.shot}`);
      if (!(pop.at >= 0 && pop.hold > 0 && pop.at + pop.hold <= scene.seconds)) {
        throw new PlanError(`${where}: pop "${pop.rect}" must start and settle inside the scene`);
      }
      return {rect: entry.rect, at: frames(pop.at), hold: frames(pop.hold), face: pop.face === true};
    });
    scenes.push({id: scene.id, shot: scene.shot, start, length: frames(scene.seconds), headline: scene.headline,
      from, to, pops, endCard: scene.endCard === true});
    start += frames(scene.seconds);
  }
  if (!scenes.length) throw new PlanError('no scenes left');
  const seconds = start / FPS;
  if (seconds < 10 || seconds > 60) throw new PlanError(`the scenes add up to ${seconds} s; keep the promo between 10 and 60 s`);
  return {scenes, frames: start, screenAspect: SHOT_ASPECT};
}

/** [width, height] from a PNG's header. */
export function pngSize(path) {
  const header = Buffer.alloc(24);
  const fd = openSync(path, 'r');
  try { readSync(fd, header, 0, 24, 0); } finally { closeSync(fd); }
  if (header.toString('latin1', 1, 4) !== 'PNG' || header.toString('latin1', 12, 16) !== 'IHDR') throw new PlanError(`${path}: not a PNG`);
  return [header.readUInt32BE(16), header.readUInt32BE(20)];
}
