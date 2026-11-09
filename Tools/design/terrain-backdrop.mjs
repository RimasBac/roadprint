#!/usr/bin/env node
// Generic hide-route backdrop for the Terrain card (ROA-11): layered ridges with lit crests,
// hazier with distance, fading into the background.
// Deterministic (fixed seed) and identical for every trip: it encodes no route, place or summit.
// Writes Design/cards/terrain/terrain-backdrop.svg (1080×900).
import { readFileSync, writeFileSync } from 'node:fs';

const ROOT = new URL('../../', import.meta.url);
const T = JSON.parse(readFileSync(new URL('Design/tokens.json', ROOT)));
const C = T.color, BG = C.background.$value;
const Wd = 1080, Ht = 900;

let seed = 20261109;
const rnd = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296);

// Midpoint displacement ridge, n = 2^p + 1 points across the full width.
function ridge(p, base, amp, rough) {
  const n = 2 ** p + 1, y = new Array(n).fill(0);
  y[0] = base + (rnd() - 0.5) * amp; y[n - 1] = base + (rnd() - 0.5) * amp;
  for (let step = n - 1, a = amp; step > 1; step /= 2, a *= rough)
    for (let i = step / 2; i < n; i += step) y[i] = (y[i - step / 2] + y[i + step / 2]) / 2 + (rnd() - 0.5) * a;
  return y.map((v, i) => [i / (n - 1) * Wd, v]);
}
const f = n => Math.round(n * 10) / 10;
const line = pts => pts.map(([x, y], i) => `${i ? 'L' : 'M'}${f(x)} ${f(y)}`).join('');

// far → near: [baseline, amplitude, roughness, crest colour, crest opacity]
const LAYERS = [
  [360, 260, 0.56, '#a6aab4', 0.30, 0.20],
  [450, 230, 0.54, '#6b6f79', 0.30, 0.22],
  [540, 190, 0.52, '#6b6f79', 0.24, 0.20],
  [630, 150, 0.50, '#30353f', 0.30, 0.18],
  [720, 110, 0.48, '#30353f', 0.22, 0.14],
];
const defs = [], body = [];
// Faint sky glow behind the far ridges (night haze).
defs.push(`<radialGradient id="backdrop-sky" cx="0.5" cy="0.42" r="0.6"><stop offset="0" stop-color="${C.border.$value}" stop-opacity="0.45"/><stop offset="1" stop-color="${BG}" stop-opacity="0"/></radialGradient>`);
body.push(`<rect id="backdrop-sky-glow" width="${Wd}" height="${Ht}" fill="url(#backdrop-sky)"/>`);
LAYERS.forEach(([base, amp, rough, crest, crestA], k) => {
  const pts = ridge(6, base, amp, rough);
  const top = Math.min(...pts.map(p => p[1]));
  const id = `backdrop-ridge-${k + 1}`;
  // Body: land tone near the crest, dissolving to background further down.
  const bodyTop = k < 2 ? C.border.$value : C.land.$value;
  defs.push(`<linearGradient id="${id}-fill" gradientUnits="userSpaceOnUse" x1="0" y1="${f(top)}" x2="0" y2="${f(Math.min(Ht, base + 260))}"><stop offset="0" stop-color="${bodyTop}"/><stop offset="1" stop-color="${BG}"/></linearGradient>`);
  body.push(`<path id="${id}" d="${line(pts)}L${Wd} ${Ht}L0 ${Ht}Z" fill="url(#${id}-fill)"/>`);
  body.push(`<path id="${id}-crest" d="${line(pts)}" fill="none" stroke="${crest}" stroke-opacity="${crestA}" stroke-width="1.5" stroke-linejoin="round"/>`);
  // Haze between layers: the next (nearer) layer sits in front of a veil of background.
  if (k < LAYERS.length - 1) body.push(`<rect width="${Wd}" height="${Ht}" fill="${BG}" fill-opacity="0.18"/>`);
});
// Dissolve the bottom and the sides into the card background (no hard edge).
defs.push(`<linearGradient id="backdrop-fade-bottom" x1="0" y1="0" x2="0" y2="1"><stop offset="0.62" stop-color="${BG}" stop-opacity="0"/><stop offset="1" stop-color="${BG}"/></linearGradient>`);
defs.push(`<linearGradient id="backdrop-fade-sides" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="${BG}"/><stop offset="0.12" stop-color="${BG}" stop-opacity="0"/><stop offset="0.88" stop-color="${BG}" stop-opacity="0"/><stop offset="1" stop-color="${BG}"/></linearGradient>`);
body.push(`<rect id="backdrop-fade-bottom-rect" width="${Wd}" height="${Ht}" fill="url(#backdrop-fade-bottom)"/>`);
body.push(`<rect id="backdrop-fade-sides-rect" width="${Wd}" height="${Ht}" fill="url(#backdrop-fade-sides)"/>`);

const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${Wd} ${Ht}" id="terrain-backdrop">
<title>Terrain card generic backdrop (hide-route). Identical for every trip; encodes no route or place.</title>
<defs>${defs.join('')}</defs>
${body.join('\n')}
</svg>
`;
writeFileSync(new URL('Design/cards/terrain/terrain-backdrop.svg', ROOT), svg);
console.log(`terrain-backdrop.svg ${(svg.length / 1024).toFixed(1)} KB`);
