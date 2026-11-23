// Render the Apple-style promo video from the real app screen recording.
//
//   node render.mjs --raw raw.mov --clock record-start.txt --markers MARKERS --out DIR
//                   [--plan promo.json] [--music track.m4a] [--badge app-store-badge.svg] [--stills-only]
//
// MARKERS is the preview-markers JSON from AppStorePreviewTests, or the xcresult attachment export
// that contains it. Every app pixel comes from --raw: the phone screen and the pop-outs show that
// recording at the moment the UI test marked. Stills of each scene are written before the video.
import {execFileSync} from 'node:child_process';
import {copyFileSync, mkdirSync, readFileSync, statSync, writeFileSync, createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '../..');
const VIDEO = 'roadprint-promo-1080x1920.mp4';

export class PlanError extends Error {}

function keys(value, required, optional, where) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new PlanError(`${where}: expected an object`);
  const allowed = new Set([...required, ...optional]);
  for (const key of Object.keys(value)) if (!allowed.has(key)) throw new PlanError(`${where}: unknown key "${key}"`);
  for (const key of required) if (!(key in value)) throw new PlanError(`${where}: missing "${key}"`);
}

function pose(value, where) {
  keys(value, ['rx', 'ry', 'z', 'y'], [], where);
  for (const [k, v] of Object.entries(value)) if (typeof v !== 'number') throw new PlanError(`${where}.${k} must be a number`);
  return value;
}

/** Turn promo.json and the UI test's markers into the composition's props. Pure; unit-tested. */
export function plan(config, markers, recordStart, rawSeconds) {
  keys(config, ['output', 'scenes'], [], 'promo.json');
  const {width, height, fps} = config.output;
  if (width !== 1080 || height !== 1920 || fps !== 30) throw new PlanError('output must be 1080x1920 at 30 fps');
  if (markers.clock !== 'unix') throw new PlanError('markers must use the unix clock');
  const [windowW, windowH] = markers.window ?? [];
  if (!(windowW > 0 && windowH > 0)) throw new PlanError('markers have no window size; re-record with the current UI test');
  let previous = null;
  const scenes = config.scenes.map((scene, i) => {
    const where = `scene ${scene.id ?? i}`;
    keys(scene, ['id', 'mark', 'offset', 'seconds', 'headline', 'pose', 'pops'], ['endCard'], where);
    if (!(scene.mark in markers.marks)) throw new PlanError(`${where}: the UI test set no mark "${scene.mark}"`);
    if (!(scene.seconds >= 1) || !(scene.offset >= 0)) throw new PlanError(`${where}: seconds must be ≥ 1 and offset ≥ 0`);
    if (!Array.isArray(scene.headline) || scene.headline.length !== 2 || scene.headline.some((l) => typeof l !== 'string' || l.length > 26)) {
      throw new PlanError(`${where}: headline must be two lines of at most 26 characters`);
    }
    keys(scene.pose, ['to'], ['from'], `${where}.pose`);
    const from = scene.pose.from ? pose(scene.pose.from, `${where}.pose.from`) : previous;
    if (!from) throw new PlanError(`${where}: the first scene needs pose.from`);
    const to = pose(scene.pose.to, `${where}.pose.to`);
    const sourceStart = markers.marks[scene.mark] - recordStart + scene.offset;
    if (sourceStart < 0 || sourceStart + scene.seconds > rawSeconds) {
      throw new PlanError(`${where}: ${sourceStart.toFixed(2)}–${(sourceStart + scene.seconds).toFixed(2)} s is outside the ${rawSeconds.toFixed(2)} s recording`);
    }
    const pops = scene.pops.map((pop, j) => {
      keys(pop, ['rect', 'at', 'hold'], ['face'], `${where}.pops[${j}]`);
      const r = markers.rects?.[pop.rect];
      if (!r) throw new PlanError(`${where}: the UI test recorded no frame for "${pop.rect}"`);
      if (pop.at < 0 || pop.at + pop.hold > scene.seconds) throw new PlanError(`${where}: pop "${pop.rect}" runs past the scene`);
      const rect = [r[0] / windowW, r[1] / windowH, r[2] / windowW, r[3] / windowH];
      if (rect.some((v) => v < 0) || rect[0] + rect[2] > 1.001 || rect[1] + rect[3] > 1.001) {
        throw new PlanError(`${where}: "${pop.rect}" is not fully on screen`);
      }
      return {rect, at: pop.at, hold: pop.hold, face: Boolean(pop.face)};
    });
    previous = to;
    return {id: scene.id, sourceStart: Math.round(sourceStart * 1000) / 1000, seconds: scene.seconds,
      headline: scene.headline, from, to, pops, endCard: Boolean(scene.endCard)};
  });
  const total = scenes.reduce((sum, s) => sum + s.seconds, 0);
  if (total < 10 || total > 60) throw new PlanError(`scenes add up to ${total} s; keep the promo between 10 and 60 s`);
  return {scenes, screenAspect: windowW / windowH};
}

export function readMarkers(path) {
  if (statSync(path).isDirectory()) {
    const manifest = JSON.parse(readFileSync(join(path, 'manifest.json'), 'utf8'));
    const files = manifest.flatMap((test) => test.attachments)
      .filter((a) => a.suggestedHumanReadableName.startsWith('preview-markers'))
      .map((a) => join(path, a.exportedFileName));
    if (files.length !== 1) throw new PlanError(`expected one preview-markers attachment, found ${files.length}`);
    path = files[0];
  }
  return {file: path, markers: JSON.parse(readFileSync(path, 'utf8'))};
}

function remotion(args) {
  const limits = ['--concurrency=' + (process.env.PROMO_CONCURRENCY ?? '1'), '--offthreadvideo-cache-size-in-bytes=67108864'];
  execFileSync('npx', ['remotion', ...args, ...limits], {cwd: here, stdio: 'inherit'});
}

function sha256(path) {
  return new Promise((ok, fail) => {
    const hash = createHash('sha256');
    createReadStream(path).on('data', (d) => hash.update(d)).on('end', () => ok(hash.digest('hex'))).on('error', fail);
  });
}

async function main() {
  const {values: args} = parseArgs({options: {
    raw: {type: 'string'}, clock: {type: 'string'}, markers: {type: 'string'}, out: {type: 'string'},
    music: {type: 'string'}, badge: {type: 'string'}, plan: {type: 'string'}, 'stills-only': {type: 'boolean'},
  }});
  for (const name of ['raw', 'clock', 'markers', 'out']) if (!args[name]) throw new PlanError(`--${name} is required`);
  const out = resolve(args.out);
  const planFile = args.plan ? resolve(args.plan) : join(here, 'promo.json');
  const config = JSON.parse(readFileSync(planFile, 'utf8'));
  const {file: markersFile, markers} = readMarkers(resolve(args.markers));
  const recordStart = Number(readFileSync(resolve(args.clock), 'utf8').trim());
  const rawSeconds = Number(execFileSync('npx', ['remotion', 'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
    '-of', 'csv=p=0', resolve(args.raw)], {cwd: here, encoding: 'utf8'}).trim());
  const props = {...plan(config, markers, recordStart, rawSeconds), music: Boolean(args.music), badge: Boolean(args.badge)};
  if (args.badge && !args.badge.endsWith('.svg')) throw new PlanError('--badge must be Apple\'s official App Store badge SVG');

  // The composition reads only these files.
  const pub = join(here, 'public');
  mkdirSync(pub, {recursive: true});
  // The phone screen is 760 px wide, so an 800 px proxy loses nothing and decodes far faster.
  // Same pictures, same timing: scaled, and the simulator's variable frame rate (it only writes a
  // frame when the screen changes) made a steady 30 fps without B-frames, so seeking is exact.
  execFileSync('npx', ['remotion', 'ffmpeg', '-v', 'error', '-y', '-i', resolve(args.raw), '-an', '-vf', 'scale=800:-2',
    '-r', '30', '-fps_mode', 'cfr', '-bf', '0', '-g', '30',
    '-c:v', 'libx264', '-crf', '14', '-preset', 'veryfast', '-pix_fmt', 'yuv420p', join(pub, 'raw.mov')],
    {cwd: here, stdio: 'inherit'});
  copyFileSync(join(repo, 'App/Resources/Fonts/BarlowCondensed/BarlowCondensed-700.ttf'), join(pub, 'BarlowCondensed-700.ttf'));
  if (args.music) copyFileSync(resolve(args.music), join(pub, 'music.m4a'));
  if (args.badge) copyFileSync(resolve(args.badge), join(pub, 'app-store-badge.svg'));
  mkdirSync(join(out, 'stills'), {recursive: true});
  const propsFile = join(out, 'props.json');
  writeFileSync(propsFile, JSON.stringify(props, null, 2) + '\n');

  // Review stills first: the middle of each scene and the peak of each pop-out.
  let start = 0;
  for (const scene of props.scenes) {
    const frames = [[`${scene.id}`, start + Math.round(scene.seconds * 15)],
      ...scene.pops.map((p, i) => [`${scene.id}-pop${i + 1}`, start + Math.round((p.at + Math.min(p.hold, 1)) * 30)])];
    for (const [name, frame] of frames) {
      remotion(['still', 'src/index.ts', 'Promo', join(out, 'stills', `${name}.png`), `--frame=${frame}`, `--props=${propsFile}`]);
    }
    start += Math.round(scene.seconds * 30);
  }
  if (args['stills-only']) return;

  const video = join(out, VIDEO);
  remotion(['render', 'src/index.ts', 'Promo', video, `--props=${propsFile}`, '--codec=h264', '--crf=16']);
  writeFileSync(join(out, 'provenance.json'), JSON.stringify({
    rule: 'Every app pixel is the simulator recording below. Added: phone body, background, light, headlines' +
      (args.badge ? ', the official App Store badge' : '') + '.',
    recording: {file: args.raw.split('/').pop(), sha256: await sha256(resolve(args.raw))},
    markers_sha256: await sha256(markersFile),
    promo_sha256: await sha256(planFile),
    music: args.music ? {file: args.music.split('/').pop(), sha256: await sha256(resolve(args.music))} : null,
    commit: process.env.GITHUB_SHA ?? null,
    scenes: props.scenes.map(({id, sourceStart, seconds}) => ({id, sourceStart, seconds})),
  }, null, 2) + '\n');
  console.log(video);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(`promo video: ${error.message}`);
    process.exit(1);
  });
}
