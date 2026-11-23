// Render the promo video from real App Store screenshots of the app.
//
//   node render.mjs --shots DIR --out DIR [--drop SCENE ...] [--stills-only]
//                   [--plan promo.json] [--music licensed-track.m4a] [--badge app-store-badge.svg]
//
// DIR holds the captures by their CI names (01-trip-summary.png … 05-trip-card-video.png): the
// `appstore-screenshots` artifact, or framed-shots.mjs output. Review stills of every scene and
// pop-out are written first, then the video and provenance.json.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFileSync, createReadStream, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {basename, dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {plan, pngSize, PlanError} from './plan.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const VIDEO = 'roadprint-promo-1080x1920.mp4';

// The project's own Remotion CLI, run by this Node: npx would need a shell on Windows.
function remotion(args) {
  execFileSync(process.execPath, [join(here, 'node_modules/@remotion/cli/remotion-cli.js'), ...args,
    `--concurrency=${process.env.PROMO_CONCURRENCY ?? '1'}`], {cwd: here, stdio: 'inherit'});
}

function sha256(path) {
  return new Promise((ok, fail) => {
    const hash = createHash('sha256');
    createReadStream(path).on('data', (d) => hash.update(d)).on('end', () => ok(hash.digest('hex'))).on('error', fail);
  });
}

async function main() {
  const {values: args} = parseArgs({options: {
    shots: {type: 'string'}, out: {type: 'string'}, plan: {type: 'string'}, drop: {type: 'string', multiple: true},
    music: {type: 'string'}, badge: {type: 'string'}, 'stills-only': {type: 'boolean'},
  }});
  if (!args.shots || !args.out) throw new PlanError('--shots and --out are required');
  if (args.badge && !args.badge.endsWith('.svg')) throw new PlanError('--badge must be Apple\'s official App Store badge SVG');
  const shots = resolve(args.shots), out = resolve(args.out);
  const planFile = resolve(args.plan ?? join(here, 'promo.json'));
  const config = JSON.parse(readFileSync(planFile, 'utf8'));
  const sizes = {};
  for (const scene of config.scenes ?? []) {
    const file = join(shots, `${scene.shot}.png`);
    if (existsSync(file)) sizes[scene.shot] = pngSize(file);
  }
  const timeline = plan(config, sizes, args.drop ?? []);
  const used = [...new Set(timeline.scenes.map((s) => s.shot))];
  const props = {...timeline, music: Boolean(args.music), badge: Boolean(args.badge)};

  // The composition reads only public/: the screenshots it uses, the app's font, and the extras asked for.
  const pub = join(here, 'public');
  rmSync(pub, {recursive: true, force: true});
  mkdirSync(join(pub, 'shots'), {recursive: true});
  for (const name of used) copyFileSync(join(shots, `${name}.png`), join(pub, 'shots', `${name}.png`));
  copyFileSync(join(here, '../../App/Resources/Fonts/BarlowCondensed/BarlowCondensed-700.ttf'), join(pub, 'BarlowCondensed-700.ttf'));
  if (args.music) copyFileSync(resolve(args.music), join(pub, 'music.m4a'));
  if (args.badge) copyFileSync(resolve(args.badge), join(pub, 'app-store-badge.svg'));

  mkdirSync(join(out, 'stills'), {recursive: true});
  const propsFile = join(out, 'props.json');
  writeFileSync(propsFile, JSON.stringify(props, null, 2) + '\n');
  for (const scene of props.scenes) {
    const stills = [[scene.id, scene.start + Math.round(scene.length / 2)],
      ...scene.pops.map((p, i) => [`${scene.id}-pop${i + 1}`, scene.start + p.at + Math.min(p.hold, 30)])];
    for (const [name, frame] of stills) {
      remotion(['still', 'src/index.ts', 'Promo', join(out, 'stills', `${name}.png`), `--frame=${frame}`, `--props=${propsFile}`]);
    }
  }
  if (args['stills-only']) return;

  const video = join(out, VIDEO);
  remotion(['render', 'src/index.ts', 'Promo', video, `--props=${propsFile}`, '--codec=h264', '--crf=16']);
  const source = join(shots, 'shots-source.json');
  writeFileSync(join(out, 'provenance.json'), JSON.stringify({
    rule: 'Every app pixel is one of the screenshots below. Added: phone body, background, light, headlines' +
      (args.badge ? ', the official App Store badge' : '') + (args.music ? ', licensed music' : '') + '.',
    screenshots: Object.fromEntries(await Promise.all(used.map(async (name) =>
      [name, {size: sizes[name], sha256: await sha256(join(shots, `${name}.png`))}]))),
    screenshotsFrom: existsSync(source) ? JSON.parse(readFileSync(source, 'utf8')) : 'the appstore-screenshots CI artifact',
    plan: {file: basename(planFile), sha256: await sha256(planFile), dropped: args.drop ?? []},
    music: args.music ? {file: basename(args.music), sha256: await sha256(resolve(args.music))} : null,
    commit: process.env.GITHUB_SHA ?? null,
    scenes: props.scenes.map(({id, shot, start, length}) => ({id, shot, start, frames: length})),
  }, null, 2) + '\n');
  console.log(video);
}

main().catch((error) => {
  console.error(`promo video: ${error.message}`);
  process.exit(1);
});
