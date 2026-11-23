// promo.json → the composition's props. Pure, so plan.test.mjs can check every rule.
//
// The promo is a shot list on a beat grid. Three kinds of shot:
//   title   big words on the stage, one line per beat
//   screen  a real App Store capture in a flat phone, with a headline; the camera can dive into a
//           named rectangle of the capture and come back out
//   end     the closing title
//
// The rule this enforces: every app pixel is a real screenshot of the app. A plan names captures by
// their CI names and rectangles of them; it cannot bring in any other image, and unknown keys are refused.
import {closeSync, openSync, readSync} from 'node:fs';

/** The App Store captures, by the names the `appstore-screenshots` CI artifact uses. */
export const SHOTS = ['01-trip-summary', '02-night-highway', '03-my-map', '04-drive', '05-trip-card-video',
  'promo-my-map']; // promo-my-map: My map as it opens, whole map in view; captured for the promo only
/** The 6.9-inch capture is 1320×2868; same-aspect crops of it (framed-shots.mjs) are accepted. */
export const SHOT_ASPECT = 1320 / 2868;
export const FPS = 60;
const TITLE_CHARS = 12; // a title line is set at 200 px and must fit the frame
const HEADLINE_CHARS = 22; // a headline line is set at 100 px

export class PlanError extends Error {}

function only(value, required, optional, where) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new PlanError(`${where}: expected an object`);
  for (const key of Object.keys(value)) {
    if (!required.includes(key) && !optional.includes(key)) throw new PlanError(`${where}: unknown key "${key}"`);
  }
  for (const key of required) if (!(key in value)) throw new PlanError(`${where}: missing "${key}"`);
}

function lines(value, count, max, where) {
  const ok = Array.isArray(value) && value.length >= count[0] && value.length <= count[1]
    && value.every((line) => typeof line === 'string' && line.length > 0 && line.length <= max);
  if (!ok) throw new PlanError(`${where}: ${count[0]}–${count[1]} lines of 1 to ${max} characters`);
  return value;
}

/**
 * @param config  promo.json
 * @param sizes   capture name → [width, height] of the files on hand
 * @param drop    shot ids to leave out (a capture not taken yet)
 */
export function plan(config, sizes, drop = []) {
  only(config, ['output', 'bpm', 'rects', 'shots'], [], 'promo.json');
  const {width, height, fps} = config.output ?? {};
  if (width !== 1080 || height !== 1920 || fps !== FPS) throw new PlanError(`output must be 1080×1920 at ${FPS} fps`);
  if (!(config.bpm >= 60 && config.bpm <= 180)) throw new PlanError('bpm must be 60 to 180');
  const beat = (60 / config.bpm) * FPS; // frames per beat

  for (const [name, entry] of Object.entries(config.rects)) {
    const where = `rect "${name}"`;
    only(entry, ['shot', 'rect'], [], where);
    if (!SHOTS.includes(entry.shot)) throw new PlanError(`${where}: unknown capture "${entry.shot}"`);
    const r = entry.rect;
    const valid = Array.isArray(r) && r.length === 4 && r.every((v) => Number.isFinite(v) && v >= 0)
      && r[2] > 0 && r[3] > 0 && r[0] + r[2] <= 1.0001 && r[1] + r[3] <= 1.0001;
    if (!valid) throw new PlanError(`${where}: rect must be [x, y, width, height] in fractions of the screen, all on it`);
  }

  for (const id of drop) if (!config.shots.some((s) => s.id === id)) throw new PlanError(`--drop: no shot "${id}"`);
  const shots = [];
  let start = 0;
  for (const [i, shot] of config.shots.entries()) {
    const where = `shot ${shot.id ?? i}`;
    if (!Number.isInteger(shot.beats) || shot.beats < 2) throw new PlanError(`${where}: beats must be a whole number, at least 2`);
    const base = {id: shot.id, kind: shot.kind, start, length: Math.round(shot.beats * beat), beat};
    if (shot.kind === 'title' || shot.kind === 'end') {
      only(shot, ['id', 'kind', 'beats', 'lines'], ['accent', 'wipe'], where);
      const text = lines(shot.lines, shot.kind === 'title' ? [1, 4] : [2, 2], shot.kind === 'title' ? TITLE_CHARS : HEADLINE_CHARS, `${where}.lines`);
      const accent = shot.accent ?? [];
      if (!Array.isArray(accent) || accent.some((k) => !Number.isInteger(k) || k < 0 || k >= text.length)) {
        throw new PlanError(`${where}: accent must list line numbers`);
      }
      if (shot.kind === 'title' && text.length > shot.beats) throw new PlanError(`${where}: one line per beat needs ${text.length} beats`);
      if (drop.includes(shot.id)) continue;
      shots.push({...base, lines: text, accent, wipe: shot.wipe === true});
    } else if (shot.kind === 'screen') {
      only(shot, ['id', 'kind', 'shot', 'beats', 'headline', 'zooms'], ['wipe'], where);
      if (!SHOTS.includes(shot.shot)) throw new PlanError(`${where}: unknown capture "${shot.shot}"`);
      lines(shot.headline, [2, 2], HEADLINE_CHARS, `${where}.headline`);
      let free = 1; // the first beat belongs to the cut
      const zooms = shot.zooms.map((zoom, j) => {
        only(zoom, ['rect', 'at', 'beats'], [], `${where}.zooms[${j}]`);
        const entry = config.rects[zoom.rect];
        if (!entry) throw new PlanError(`${where}: no rect "${zoom.rect}"`);
        if (entry.shot !== shot.shot) throw new PlanError(`${where}: rect "${zoom.rect}" is on ${entry.shot}, not ${shot.shot}`);
        if (!Number.isInteger(zoom.at) || !Number.isInteger(zoom.beats) || zoom.beats < 2 || zoom.at < free || zoom.at + zoom.beats > shot.beats) {
          throw new PlanError(`${where}: zoom "${zoom.rect}" must start on a later beat than the last one ended, last 2+ beats and end by the shot's end`);
        }
        free = zoom.at + zoom.beats;
        return {rect: entry.rect, at: Math.round(zoom.at * beat), length: Math.round(zoom.beats * beat)};
      });
      if (drop.includes(shot.id)) continue;
      if (!sizes[shot.shot]) throw new PlanError(`${where}: no ${shot.shot}.png`);
      const [w, h] = sizes[shot.shot];
      if (Math.abs(w / h / SHOT_ASPECT - 1) > 0.005) throw new PlanError(`${where}: ${shot.shot}.png is ${w}×${h}, not the shape of a 6.9-inch capture`);
      // The phone rises into the window when the shot before had none.
      const rise = !shots.length || shots.at(-1).kind !== 'screen';
      shots.push({...base, shot: shot.shot, headline: shot.headline, zooms, rise, wipe: shot.wipe === true});
    } else {
      throw new PlanError(`${where}: kind must be title, screen or end`);
    }
    start += base.length;
  }
  if (!shots.length) throw new PlanError('no shots left');
  if (shots.at(-1).kind !== 'end') throw new PlanError('the last shot must be the end title');
  const seconds = start / FPS;
  if (seconds < 10 || seconds > 60) throw new PlanError(`the shots add up to ${seconds} s; keep the promo between 10 and 60 s`);
  return {shots, frames: start, screenAspect: SHOT_ASPECT};
}

/** [width, height] from a PNG's header. */
export function pngSize(path) {
  const header = Buffer.alloc(24);
  const fd = openSync(path, 'r');
  try { readSync(fd, header, 0, 24, 0); } finally { closeSync(fd); }
  if (header.toString('latin1', 1, 4) !== 'PNG' || header.toString('latin1', 12, 16) !== 'IHDR') throw new PlanError(`${path}: not a PNG`);
  return [header.readUInt32BE(16), header.readUInt32BE(20)];
}
