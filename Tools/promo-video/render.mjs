// Render the promo video from real App Store screenshots of the app.
//
//   node render.mjs --shots DIR --out DIR [--drop SCENE ...] [--stills-only]
//                   [--plan promo.json] [--music licensed-track.m4a|.wav] [--badge app-store-badge.svg]
//
// Without --music, soundtrack.mjs synthesises an original score from the timeline itself.
//
// DIR holds the captures by their CI names (01-trip-summary.png … 05-trip-card-video.png): the
// `appstore-screenshots` artifact, or framed-shots.mjs output. Review stills of every scene and
// pop-out are written first, then the video and provenance.json.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFileSync, createReadStream, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {basename, dirname, extname, join, resolve} from 'node:path';
import {cpus} from 'node:os';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {plan, pngSize, PlanError} from './plan.mjs';
import {synth, wav} from './soundtrack.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const VIDEO = 'roadprint-promo-1080x1920.mp4';

// The project's own Remotion CLI, run by this Node: npx would need a shell on Windows.
function remotion(args) {
  execFileSync(process.execPath, [join(here, 'node_modules/@remotion/cli/remotion-cli.js'), ...args,
    `--concurrency=${Math.min(Number(process.env.PROMO_CONCURRENCY ?? 1), cpus().length)}`], {cwd: here, stdio: 'inherit'});
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
  for (const shot of config.shots ?? []) {
    if (!shot.shot) continue;
    const file = join(shots, `${shot.shot}.png`);
    if (existsSync(file)) sizes[shot.shot] = pngSize(file);
  }
  const timeline = plan(config, sizes, args.drop ?? []);
  const used = [...new Set(timeline.shots.filter((s) => s.kind === 'screen').map((s) => s.shot))];
  const music = args.music ? `music${extname(args.music).toLowerCase()}` : 'music.wav';
  const props = {...timeline, music, badge: Boolean(args.badge)};

  // The composition reads only public/: the screenshots it uses, the app's font, and the extras asked for.
  const pub = join(here, 'public');
  rmSync(pub, {recursive: true, force: true});
  mkdirSync(join(pub, 'shots'), {recursive: true});
  for (const name of used) copyFileSync(join(shots, `${name}.png`), join(pub, 'shots', `${name}.png`));
  copyFileSync(join(here, '../../App/Resources/Fonts/BarlowCondensed/BarlowCondensed-700.ttf'), join(pub, 'BarlowCondensed-700.ttf'));
  if (args.music) copyFileSync(resolve(args.music), join(pub, music));
  else writeFileSync(join(pub, music), wav(synth(timeline)));
  if (args.badge) copyFileSync(resolve(args.badge), join(pub, 'app-store-badge.svg'));

  mkdirSync(join(out, 'stills'), {recursive: true});
  const propsFile = join(out, 'props.json');
  writeFileSync(propsFile, JSON.stringify(props, null, 2) + '\n');
  // A still at each shot's middle beat, and at the deepest point of every dive.
  for (const shot of props.shots) {
    const stills = [[shot.id, shot.start + Math.round(Math.floor(shot.length / shot.beat / 2) * shot.beat)],
      ...(shot.zooms ?? []).map((z, i) => [`${shot.id}-zoom${i + 1}`, shot.start + z.at + Math.round(z.length / 2)])];
    for (const [name, frame] of stills) {
      remotion(['still', 'src/index.ts', 'Promo', join(out, 'stills', `${name}.png`), `--frame=${frame}`, `--props=${propsFile}`]);
    }
  }
  if (args['stills-only']) return;

  const video = join(out, VIDEO);
  remotion(['render', 'src/index.ts', 'Promo', video, `--props=${propsFile}`, '--codec=h264', '--crf=16']);
  const source = join(shots, 'shots-source.json');
  writeFileSync(join(out, 'provenance.json'), JSON.stringify({
    rule: 'Every app pixel is one of the screenshots below. Added: a plain phone frame, the stage colour, type and an amber wipe' +
      (args.badge ? ', the official App Store badge' : '') + (args.music ? ', licensed music' : ', an original synthesised soundtrack') + '.',
    screenshots: Object.fromEntries(await Promise.all(used.map(async (name) =>
      [name, {size: sizes[name], sha256: await sha256(join(shots, `${name}.png`))}]))),
    screenshotsFrom: existsSync(source) ? JSON.parse(readFileSync(source, 'utf8')) : 'the appstore-screenshots CI artifact',
    plan: {file: basename(planFile), sha256: await sha256(planFile), dropped: args.drop ?? []},
    music: args.music ? {file: basename(args.music), sha256: await sha256(resolve(args.music))}
      : {synthesised: 'soundtrack.mjs', sha256: await sha256(join(pub, music))},
    commit: process.env.GITHUB_SHA ?? null,
    shots: props.shots.map(({id, kind, shot, start, length}) => ({id, kind, shot: shot ?? null, start, frames: length})),
  }, null, 2) + '\n');
  console.log(video);
}

main().catch((error) => {
  console.error(`promo video: ${error.message}`);
  process.exit(1);
});
