#!/usr/bin/env node
// Reference implementation of the main-road guess in plain JS (brute force), to cross-check
// roads.rpgeo and the Swift MainRoadGuesser.   node check.mjs <route.gpx|route.json> | --road E40 BE
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { NETWORKS } from './normalise.mjs';

const file = resolve(dirname(fileURLToPath(import.meta.url)), '../../RoadPrintCore/Sources/RoadPrintCore/Resources/roads.rpgeo');
const b = readFileSync(file);
let pos = 5;
const varint = () => { let r = 0, m = 1, c; do { c = b[pos++]; r += (c & 0x7f) * m; m *= 128; } while (c >= 0x80); return r; };
const svarint = () => { const v = varint(); return v % 2 === 0 ? v / 2 : -(v + 1) / 2; };
const strings = Array.from({ length: varint() }, () => { const n = varint(); const s = b.toString('utf8', pos, pos + n); pos += n; return s; });
const names = Object.fromEntries(Object.entries(NETWORKS).map(([k, v]) => [v, k]));
const roads = Array.from({ length: varint() }, () => {
  const network = names[b[pos++]], ref = strings[varint()], country = strings[varint()];
  const parts = Array.from({ length: varint() }, () => {
    let x = 0, y = 0;
    return Array.from({ length: varint() }, () => { x += svarint(); y += svarint(); return [x / 1e5, y / 1e5]; });
  });
  return { network, ref, country, parts };
});

const arg = process.argv[2];
if (arg === '--road') {
  const [ref, country] = process.argv.slice(3);
  const r = roads.find((x) => x.ref === ref && x.country === country);
  console.log(JSON.stringify(r.parts[0].slice(0, 8).map(([x, y]) => [y, x])));
  process.exit();
}
let pts;
if (arg.endsWith('.json')) pts = JSON.parse(readFileSync(arg, 'utf8'));
else pts = [...readFileSync(arg, 'utf8').matchAll(/lat="([-\d.]+)" lon="([-\d.]+)"/g)].map((m) => [+m[1], +m[2]]);
const M = 111195;
const dist = (a, c) => Math.hypot((a[0] - c[0]) * M, (a[1] - c[1]) * M * Math.cos((a[0] * Math.PI) / 180));
// resample at 250 m
const samples = [pts[0]];
let carry = 0;
for (let i = 1; i < pts.length; i++) {
  let a = pts[i - 1]; const c = pts[i]; let d = dist(a, c);
  while (carry + d >= 250) { const t = (250 - carry) / d; a = [a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t]; samples.push(a); d = dist(a, c); carry = 0; }
  carry += d;
}
function nearest(p) {
  let best = Infinity, who;
  for (const r of roads) for (const part of r.parts) for (let i = 1; i < part.length; i++) {
    const k = Math.cos((p[0] * Math.PI) / 180);
    const ax = (part[i - 1][0] - p[1]) * M * k, ay = (part[i - 1][1] - p[0]) * M, bx = (part[i][0] - p[1]) * M * k, by = (part[i][1] - p[0]) * M;
    if (Math.min(ax, bx) > 150 || Math.max(ax, bx) < -150 || Math.min(ay, by) > 150 || Math.max(ay, by) < -150) continue;
    const dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
    const t = l2 ? Math.max(0, Math.min(1, -(ax * dx + ay * dy) / l2)) : 0;
    const d = Math.hypot(ax + t * dx, ay + t * dy);
    if (d < best) { best = d; who = r; }
  }
  return best <= 150 ? who : null;
}
const tally = new Map();
for (const s of samples) { const r = nearest(s); if (r) tally.set(`${r.network} ${r.ref} ${r.country}`, (tally.get(`${r.network} ${r.ref} ${r.country}`) ?? 0) + 1); }
console.log(samples.length, 'samples', [...tally].sort((a, c) => c[1] - a[1]).slice(0, 5));
