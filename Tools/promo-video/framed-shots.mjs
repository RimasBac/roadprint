// Recover the real App Store captures from the framed store screenshots in Design/appstore/out,
// for when the CI `appstore-screenshots` artifact (the unframed 1320×2868 PNGs) has expired.
//
//   node framed-shots.mjs --out DIR [--framed ../../Design/appstore/out]
//
// Design/appstore/appstore.mjs scales each capture to 1000×2173 at (160, 600) and draws a 3 px
// border over its edge. This crops 4 px inside that box at the capture's aspect ratio, so every
// pixel written is the capture: no border, background or caption. Only use it on `out/`, never on
// `previews/`, which holds design mock-ups.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {basename, dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {SHOTS} from './plan.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const CROP = [164, 604, 992, 2155]; // x, y, width, height; 992 / 2155 = 1320 / 2868 within 0.02 %

const {values: args} = parseArgs({options: {framed: {type: 'string'}, out: {type: 'string'}}});
if (!args.out) throw new Error('--out is required');
const framed = resolve(args.framed ?? join(here, '../../Design/appstore/out'));
if (basename(framed) === 'previews') throw new Error('Design/appstore/previews holds mock-ups, not captures');
const out = resolve(args.out);
mkdirSync(out, {recursive: true});
const [x, y, w, h] = CROP;
const sources = {};
SHOTS.forEach((name, i) => {
  const file = join(framed, `0${i + 1}.png`);
  execFileSync(process.execPath, [join(here, 'node_modules/@remotion/cli/remotion-cli.js'), 'ffmpeg', '-v', 'error', '-y',
    '-i', file, '-vf', `crop=${w}:${h}:${x}:${y}`, '-frames:v', '1', join(out, `${name}.png`)], {stdio: 'inherit'});
  sources[name] = {framed: `0${i + 1}.png`, sha256: createHash('sha256').update(readFileSync(file)).digest('hex')};
});
writeFileSync(join(out, 'shots-source.json'), JSON.stringify({
  note: 'Cropped from the framed App Store screenshots (Design/appstore/out): each is the real capture, scaled to 75.8 %.',
  crop: CROP, sources,
}, null, 2) + '\n');
console.log(out);
