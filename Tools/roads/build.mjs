#!/usr/bin/env node
// Builds RoadPrintCore/Sources/RoadPrintCore/Resources/roads.rpgeo from Natural Earth 1:10m roads.
// Format: see FORMAT.md. Deterministic: the same input zips give a byte-identical file.
//
//   cd Tools/roads && npm install --include=dev && node build.mjs

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { NETWORKS, normalise } from './normalise.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, 'out');
const target = resolve(here, '../../RoadPrintCore/Sources/RoadPrintCore/Resources/roads.rpgeo');

/** Natural Earth (public domain). The hashes pin the exact input. */
const INPUTS = [
  { key: 'roads', file: 'ne_10m_roads.zip', sha256: '880b235383a1e1ccf33f4ea6f82b6755a2ffbce07e3974e412b43e88fe954ae9' }, // 5.0.0
  { key: 'countries', file: 'ne_10m_admin_0_countries.zip', sha256: 'ce1ac7036499a0edd641fbc093cd209a98f96a49d2eca8480aaacad35138a7f6' }, // 5.1.1
];
const BASE_URL = 'https://naciscdn.org/naturalearth/10m/cultural/';
const KEEP_TYPES = ['Major Highway', 'Secondary Highway', 'Beltway', 'Bypass'];
const SIMPLIFY_METERS = Number(process.env.SIMPLIFY_METERS ?? 40); // well inside the 150 m match radius
const COUNTRY_SIMPLIFY_METERS = 700;
const FORMAT_VERSION = 1;
const SCALE = 1e5; // 1e-5 degrees
const MAX_BYTES = Number(process.env.MAX_BYTES ?? 3 * 1024 * 1024);
const mapshaper = join(here, 'node_modules/.bin/mapshaper');

mkdirSync(outDir, { recursive: true });

async function fetchInput(input) {
  const path = join(outDir, input.file);
  if (!existsSync(path)) {
    console.log(`downloading ${input.file}`);
    const res = await fetch(BASE_URL + input.file);
    if (!res.ok) throw new Error(`download failed: ${res.status} ${input.file}`);
    writeFileSync(path, Buffer.from(await res.arrayBuffer()));
  }
  const sha = createHash('sha256').update(readFileSync(path)).digest('hex');
  if (sha !== input.sha256) {
    throw new Error(`${input.file}: SHA-256 ${sha} does not match the pinned ${input.sha256}. ` +
      'Natural Earth changed the file; review, then update INPUTS.');
  }
  return path;
}

function toGeoJSON(zip, key, args) {
  const dir = join(outDir, key);
  const out = join(outDir, `${key}.geojson`);
  execFileSync('unzip', ['-o', '-q', zip, '-d', dir]);
  const shp = join(dir, readdirSync(dir).find((n) => n.endsWith('.shp')));
  execFileSync(mapshaper, ['-i', shp, ...args, '-o', out, 'format=geojson', 'force'], { stdio: ['ignore', 'ignore', 'inherit'] });
  return JSON.parse(readFileSync(out, 'utf8')).features;
}

const zips = {};
for (const input of INPUTS) zips[input.key] = await fetchInput(input);

// Countries, for the road's country code (NE's own sov_a3 is empty outside North America).
const countries = toGeoJSON(zips.countries, 'countries', [
  '-filter-fields', 'ISO_A2_EH,ADM0_A3',
  '-simplify', 'visvalingam', `interval=${COUNTRY_SIMPLIFY_METERS}`, 'keep-shapes',
]).map((f) => {
  const code = f.properties.ISO_A2_EH && f.properties.ISO_A2_EH !== '-99' ? f.properties.ISO_A2_EH : f.properties.ADM0_A3;
  const polys = f.geometry?.type === 'Polygon' ? [f.geometry.coordinates] : f.geometry?.type === 'MultiPolygon' ? f.geometry.coordinates : [];
  const rings = polys.flat();
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const ring of rings) for (const [x, y] of ring) {
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (y < minY) minY = y; if (y > maxY) maxY = y;
  }
  return { code, rings, minX, maxX, minY, maxY };
}).filter((c) => c.rings.length);

function inRing(ring, x, y) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
function countryAt(x, y) {
  for (const c of countries) {
    if (x < c.minX || x > c.maxX || y < c.minY || y > c.maxY) continue;
    if (c.rings.reduce((n, r) => n + (inRing(r, x, y) ? 1 : 0), 0) % 2 === 1) return c.code;
  }
  return '';
}

const lines = (g) => (g?.type === 'LineString' ? [g.coordinates] : g?.type === 'MultiLineString' ? g.coordinates : []);

/** Country of a road: the first of a few sample vertices that falls in a country outline. */
function countryOf(parts) {
  const all = parts.flat();
  for (const t of [0.5, 0.25, 0.75, 0, 1]) {
    const [x, y] = all[Math.min(all.length - 1, Math.floor(t * (all.length - 1)))];
    const code = countryAt(x, y);
    if (code) return code;
  }
  return '';
}

const roadFeatures = toGeoJSON(zips.roads, 'roads', [
  '-filter', `${JSON.stringify(KEEP_TYPES)}.includes(type)`,
  '-filter-fields', 'type,name,label,label2,local,prefix,level,routeraw',
  '-simplify', 'visvalingam', `interval=${SIMPLIFY_METERS}`,
]);

function quantise(line) {
  const pts = [];
  for (const [lon, lat] of line) {
    const p = [Math.round(lon * SCALE), Math.round(lat * SCALE)];
    const q = pts[pts.length - 1];
    if (!q || q[0] !== p[0] || q[1] !== p[1]) pts.push(p);
  }
  return pts;
}

const roads = [];
const stats = {};
let noRef = 0;
for (const f of roadFeatures) {
  const parts = lines(f.geometry).filter((l) => l.length >= 2);
  if (!parts.length) continue;
  const country = countryOf(parts);
  const norm = normalise({ ...f.properties, country });
  if (!norm) { noRef++; continue; }
  const quant = parts.map(quantise).filter((l) => l.length >= 2);
  if (!quant.length) continue;
  roads.push({ network: NETWORKS[norm.network], ref: norm.ref, country, parts: quant });
  stats[norm.network] = (stats[norm.network] ?? 0) + 1;
}
const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
roads.sort((a, b) => a.network - b.network || cmp(a.ref, b.ref) || cmp(a.country, b.country)
  || a.parts[0][0][0] - b.parts[0][0][0] || a.parts[0][0][1] - b.parts[0][0][1]
  || a.parts[0].length - b.parts[0].length);

const strings = [...new Set(roads.flatMap((r) => [r.ref, r.country]))].sort();
const stringIndex = new Map(strings.map((s, i) => [s, i]));
const zigzag = (n) => (n < 0 ? -2 * n - 1 : 2 * n);

const bytes = [];
const varint = (v) => {
  if (v < 0 || !Number.isInteger(v)) throw new Error(`bad varint ${v}`);
  while (v >= 0x80) { bytes.push((v % 0x80) | 0x80); v = Math.floor(v / 0x80); }
  bytes.push(v);
};
for (const c of 'RPRD') bytes.push(c.charCodeAt(0));
bytes.push(FORMAT_VERSION);
varint(strings.length);
for (const s of strings) { const b = Buffer.from(s, 'utf8'); varint(b.length); for (const x of b) bytes.push(x); }
varint(roads.length);
let vertices = 0;
for (const r of roads) {
  bytes.push(r.network);
  varint(stringIndex.get(r.ref));
  varint(stringIndex.get(r.country));
  varint(r.parts.length);
  for (const part of r.parts) {
    varint(part.length);
    let px = 0, py = 0;
    for (const [x, y] of part) { varint(zigzag(x - px)); varint(zigzag(y - py)); px = x; py = y; vertices++; }
  }
}

const data = Buffer.from(bytes);
if (data.length > MAX_BYTES) throw new Error(`output is ${data.length} bytes, over the ${MAX_BYTES} limit`);
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, data);
console.log(`wrote ${target}`);
console.log(`${data.length} bytes (${(data.length / 1048576).toFixed(2)} MiB), ${roads.length} roads, ${vertices} vertices; ${noRef} without a usable ref dropped`);
console.log('roads per network', stats);
console.log(`sha256 ${createHash('sha256').update(data).digest('hex')}`);
