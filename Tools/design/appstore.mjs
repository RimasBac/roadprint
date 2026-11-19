#!/usr/bin/env node
// App Store screenshot frames (ROA-96). Builds Design/appstore/frame.svg (the template) and renders the
// five framed screenshots at exactly 1320×2868, RGB without alpha (App Store Connect rejects alpha).
//
//   node appstore.mjs --in dir   # dir holds the 5 raw 1320×2868 PNGs (sorted by name = screenshot order)
//                                # → Design/appstore/out/01.png … 05.png + contact-sheet.png
//   node appstore.mjs            # no raw screenshots yet: mockup crops as stand-ins
//                                # → Design/appstore/previews/01.png … 05.png + contact-sheet.png
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';
import { renderSvg } from './render.mjs';
import { loadFont } from './ttf.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '../..');
const tokens = JSON.parse(readFileSync(join(root, 'Design/tokens.json'), 'utf8'));
const C = Object.fromEntries(['background', 'land', 'border', 'route', 'text', 'textSecondary'].map(k => [k, tokens.color[k].$value]));
const FONT = loadFont(join(here, 'fonts/BarlowCondensed-700.ttf'));

export const CAPTIONS = [
  ['Your drive,', 'drawn in light'],
  ['Send a postcard', 'from the road'],
  ['All your roads,', 'one map'],
  ['One tap', 'before you go'],
  ['Watch your route', 'draw itself'],
];

// Layout (px). The screenshot keeps the raw 1320:2868 aspect.
const W = 1320, H = 2868;
const CAP = { size: 172, maxWidth: 1160, base1: 286, base2: 456, tracking: 0.01 };
const SHOT = { w: 1000, x: 160, y: 600, r: 92 };
SHOT.h = Math.round(SHOT.w * H / W); // 2173 → bottom margin 95

function captionPaths(lines) {
  const upper = lines.map(l => l.toUpperCase());
  const trU = CAP.tracking * FONT.unitsPerEm;
  const widths = upper.map(l => FONT.measure(l, trU) / FONT.unitsPerEm);
  const size = Math.min(CAP.size, ...widths.map(w => CAP.maxWidth / w)); // shrink to fit, never grow
  return upper.map((l, i) => {
    const w = widths[i] * size;
    return `<path id="caption-line-${i + 1}" fill="${i ? C.route : C.text}" d="${FONT.pathData(l, (W - w) / 2, i ? CAP.base2 : CAP.base1, size, trU, 1)}"/>`;
  }).join('');
}

/** The frame. `caption` is either outlined paths or the template's text placeholders; `shot` fills the screen. */
function frame(caption, shot) {
  const { x, y, w, h, r } = SHOT;
  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
<defs>
<linearGradient id="night-sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0b0c10"/><stop offset=".55" stop-color="${C.background}"/><stop offset="1" stop-color="#0b0c10"/></linearGradient>
<radialGradient id="route-glow" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="${C.route}" stop-opacity=".22"/><stop offset="1" stop-color="${C.route}" stop-opacity="0"/></radialGradient>
<filter id="soft-shadow" x="-20%" y="-10%" width="140%" height="125%"><feDropShadow dx="0" dy="28" stdDeviation="40" flood-color="#000" flood-opacity=".7"/></filter>
<clipPath id="screen-clip"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}"/></clipPath>
</defs>
<rect id="background" width="${W}" height="${H}" fill="url(#night-sky)"/>
<ellipse id="glow" cx="${W / 2}" cy="${y + 260}" rx="760" ry="620" fill="url(#route-glow)"/>
${caption}
<rect id="screen-shadow" x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${C.background}" filter="url(#soft-shadow)"/>
<g id="screen" clip-path="url(#screen-clip)">${shot}</g>
<rect id="screen-edge" x="${x + 1.5}" y="${y + 1.5}" width="${w - 3}" height="${h - 3}" rx="${r - 1.5}" fill="none" stroke="${C.border}" stroke-width="3"/>
</svg>
`;
}

const templateCaption = `<text id="caption-line-1" x="${W / 2}" y="${CAP.base1}" text-anchor="middle" font-family="Barlow Condensed" font-weight="700" font-stretch="condensed" font-size="${CAP.size}" fill="${C.text}">CAPTION LINE 1</text>
<text id="caption-line-2" x="${W / 2}" y="${CAP.base2}" text-anchor="middle" font-family="Barlow Condensed" font-weight="700" font-stretch="condensed" font-size="${CAP.size}" fill="${C.route}">CAPTION LINE 2</text>`;
const templateShot = `<rect id="screenshot-placeholder" x="${SHOT.x}" y="${SHOT.y}" width="${SHOT.w}" height="${SHOT.h}" fill="${C.land}"/>`;

const png64 = path => 'data:image/png;base64,' + readFileSync(path).toString('base64');
const rawShot = path => `<image x="${SHOT.x}" y="${SHOT.y}" width="${SHOT.w}" height="${SHOT.h}" preserveAspectRatio="xMidYMid slice" xlink:href="${png64(path)}"/>`;

// Stand-ins until the real screenshots arrive: crops of docs/plan/mockups (source px), or a labelled panel.
const MOCK = join(root, 'docs/plan/mockups');
const STANDINS = [
  { file: '1-trip-summary.png', crop: [101, 257, 783, 1689], fit: 'slice' },
  { file: '2-share-cards.png', crop: [81, 231, 660, 1173], fit: 'meet' },
  { file: '3-heatmap-free-vs-pro.png', crop: [994, 255, 780, 1687], fit: 'slice' },
  { label: 'Drive screen' },
  { file: '2-share-cards.png', crop: [81, 231, 660, 1173], fit: 'meet', video: true },
];
// Stand-in only: a play button over the card, for the trip-card Video state.
function videoBadge() {
  const cx = SHOT.x + SHOT.w / 2, cy = SHOT.y + SHOT.h / 2;
  return `<g id="video-standin"><circle cx="${cx}" cy="${cy}" r="110" fill="#0b0c10" fill-opacity=".72" stroke="${C.route}" stroke-width="6"/><path d="M${cx - 34} ${cy - 56}L${cx + 62} ${cy}L${cx - 34} ${cy + 56}Z" fill="${C.route}"/></g>`;
}
function standIn(s, i) {
  const { x, y, w, h } = SHOT;
  const bg = `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#0b0c10"/>`;
  if (s.label) return bg + `<text x="${x + w / 2}" y="${y + h / 2}" text-anchor="middle" font-family="Inter" font-weight="600" font-size="44" fill="${C.textSecondary}">Screenshot 0${i + 1}</text><text x="${x + w / 2}" y="${y + h / 2 + 64}" text-anchor="middle" font-family="Inter" font-size="36" fill="${C.textSecondary}">${s.label}</text>`;
  const [cx, cy, cw, ch] = s.crop, b = readFileSync(join(MOCK, s.file)), iw = b.readUInt32BE(16), ih = b.readUInt32BE(20);
  return bg + `<svg x="${x}" y="${y}" width="${w}" height="${h}" viewBox="${cx} ${cy} ${cw} ${ch}" preserveAspectRatio="xMidYMid ${s.fit}"><clipPath id="crop-${i + 1}"><rect x="${cx}" y="${cy}" width="${cw}" height="${ch}" rx="${s.fit === 'meet' ? 40 : 0}"/></clipPath><image clip-path="url(#crop-${i + 1})" width="${iw}" height="${ih}" xlink:href="${png64(join(MOCK, s.file))}"/></svg>` + (s.video ? videoBadge() : '');
}

// PNG writer: 8-bit RGB, colour type 2, no alpha channel.
const CRC = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc32 = b => { let c = ~0; for (const v of b) c = CRC[(c ^ v) & 255] ^ (c >>> 8); return ~c >>> 0; };
function chunk(type, data) {
  const t = Buffer.concat([Buffer.from(type, 'latin1'), data]), len = Buffer.alloc(4), crc = Buffer.alloc(4);
  len.writeUInt32BE(data.length); crc.writeUInt32BE(crc32(t));
  return Buffer.concat([len, t, crc]);
}
export function rgbPng(rgba, w, h) {
  const raw = Buffer.alloc(h * (1 + 3 * w));
  for (let yy = 0, o = 0; yy < h; yy++) {
    raw[o++] = 0;
    for (let xx = 0; xx < w; xx++) { const p = 4 * (yy * w + xx); raw[o++] = rgba[p]; raw[o++] = rgba[p + 1]; raw[o++] = rgba[p + 2]; }
  }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

// WCAG contrast of the caption colours against the darkest and lightest background stops.
const lum = hex => { const c = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255).map(v => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
const contrast = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), inDir = args.includes('--in') ? args[args.indexOf('--in') + 1] : null;
  const app = join(root, 'Design/appstore');
  writeFileSync(join(app, 'frame.svg'), frame(templateCaption, templateShot));
  let shots;
  if (inDir) {
    const files = readdirSync(inDir).filter(f => f.toLowerCase().endsWith('.png')).sort();
    if (files.length !== 5) throw new Error(`expected 5 PNGs in ${inDir}, found ${files.length}`);
    shots = files.map(f => rawShot(join(inDir, f)));
  } else shots = STANDINS.map(standIn);
  const outDir = join(app, inDir ? 'out' : 'previews');
  mkdirSync(outDir, { recursive: true });
  const thumbs = [];
  CAPTIONS.forEach((cap, i) => {
    const r = renderSvg(frame(captionPaths(cap), shots[i]));
    if (r.width !== W || r.height !== H) throw new Error(`size ${r.width}×${r.height}`);
    const png = rgbPng(r.pixels, r.width, r.height), name = `0${i + 1}.png`;
    writeFileSync(join(outDir, name), png);
    thumbs.push(png);
    console.log(join(outDir, name), `${W}×${H} RGB`, `"${cap.join(' ')}" (${cap.join(' ').length} chars)`);
  });
  // Contact sheet: all five at 300 px wide, the size of an App Store search-result thumbnail and smaller.
  const tw = 300, th = Math.round(tw * H / W), gap = 28, SW = 5 * tw + 6 * gap, SH = th + 2 * gap;
  let sheet = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 ${SW} ${SH}"><rect width="${SW}" height="${SH}" fill="#30353f"/>`;
  thumbs.forEach((p, i) => { sheet += `<image x="${gap + i * (tw + gap)}" y="${gap}" width="${tw}" height="${th}" xlink:href="data:image/png;base64,${p.toString('base64')}"/>`; });
  const s = renderSvg(sheet + '</svg>');
  writeFileSync(join(outDir, 'contact-sheet.png'), rgbPng(s.pixels, s.width, s.height));
  console.log(join(outDir, 'contact-sheet.png'), `${s.width}×${s.height}`);
  for (const [n, c] of [['text', C.text], ['route', C.route]]) for (const bg of ['#0b0c10', C.background])
    console.log(`contrast ${n} ${c} on ${bg}: ${contrast(c, bg).toFixed(1)}:1`);
}
