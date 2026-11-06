#!/usr/bin/env node
// Builds RoadPrintCore/Sources/RoadPrintCore/Resources/places.rpgeo from Natural Earth.
// Format: see FORMAT.md. Deterministic: the same input zips give a byte-identical file.
//
//   cd Tools/places && npm install --include=dev && node build.mjs

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, 'out');
const target = resolve(here, '../../RoadPrintCore/Sources/RoadPrintCore/Resources/places.rpgeo');

/** Natural Earth 5.1.1 (public domain). The hashes pin the exact input. */
const INPUTS = [
  {
    key: 'countries',
    file: 'ne_10m_admin_0_countries.zip',
    sha256: 'ce1ac7036499a0edd641fbc093cd209a98f96a49d2eca8480aaacad35138a7f6',
  },
  {
    key: 'regions',
    file: 'ne_10m_admin_1_states_provinces.zip',
    sha256: 'efc59726337323058f9446210adc96673179cd344e053666ee3d28cb58ba2b05',
  },
];
const BASE_URL = 'https://naciscdn.org/naturalearth/10m/cultural/';
const SIMPLIFY_METERS = Number(process.env.SIMPLIFY_METERS ?? 700);
const FORMAT_VERSION = 1;
const SCALE = 1e5; // 1e-5 degrees
/** Rings smaller than this in both directions (about 1 km) are dropped, unless a feature would have none. */
const MIN_RING_SPAN = 1000;
const MAX_BYTES = Number(process.env.MAX_BYTES ?? 4 * 1024 * 1024);

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

function simplified(zip, key) {
  const out = join(outDir, `${key}.geojson`);
  const dir = join(outDir, key);
  execFileSync('unzip', ['-o', '-q', zip, '-d', dir]);
  execFileSync(mapshaper, [
    '-i', join(dir, `${basename(zip, '.zip')}.shp`), '-filter-fields', key === 'countries' ? 'ISO_A2_EH,ADM0_A3,NAME_EN,NAME' : 'iso_3166_2,adm0_a3,name_en,name',
    '-simplify', 'visvalingam', `interval=${SIMPLIFY_METERS}`, 'keep-shapes',
    '-o', out, 'format=geojson', 'force',
  ], { stdio: ['ignore', 'ignore', 'inherit'] });
  return JSON.parse(readFileSync(out, 'utf8')).features;
}

/** Polygon or MultiPolygon → list of rings (even-odd, so holes need no marker). */
function ringsOf(geometry) {
  if (!geometry) return [];
  const polys = geometry.type === 'Polygon' ? [geometry.coordinates]
    : geometry.type === 'MultiPolygon' ? geometry.coordinates : [];
  return polys.flat();
}

/** Quantise, drop the closing vertex and repeated vertices. Returns [] for degenerate rings. */
function quantise(ring) {
  const pts = [];
  for (const [lon, lat] of ring) {
    const p = [Math.round(lon * SCALE), Math.round(lat * SCALE)];
    const q = pts[pts.length - 1];
    if (!q || q[0] !== p[0] || q[1] !== p[1]) pts.push(p);
  }
  while (pts.length > 1 && pts[0][0] === pts[pts.length - 1][0] && pts[0][1] === pts[pts.length - 1][1]) pts.pop();
  return pts.length >= 3 ? pts : [];
}

function span(ring) {
  const xs = ring.map((p) => p[0]), ys = ring.map((p) => p[1]);
  return Math.max(Math.max(...xs) - Math.min(...xs), Math.max(Math.max(...ys) - Math.min(...ys)));
}

/** Quantised rings of a geometry without specks. */
function cleanRings(geometry) {
  const rings = ringsOf(geometry).map(quantise).filter((r) => r.length);
  const kept = rings.filter((r) => span(r) >= MIN_RING_SPAN);
  if (kept.length || !rings.length) return kept;
  return [rings.reduce((a, b) => (span(b) > span(a) ? b : a))];
}

const zigzag = (n) => (n < 0 ? -2 * n - 1 : 2 * n);

class Writer {
  bytes = [];
  u8(v) { this.bytes.push(v); }
  varint(v) {
    if (v < 0 || !Number.isInteger(v)) throw new Error(`bad varint ${v}`);
    while (v >= 0x80) { this.bytes.push((v % 0x80) | 0x80); v = Math.floor(v / 0x80); }
    this.bytes.push(v);
  }
  svarint(v) { this.varint(zigzag(v)); }
}

const zips = {};
for (const input of INPUTS) zips[input.key] = await fetchInput(input);

const features = [];
const countryFeatures = simplified(zips.countries, 'countries');
const byA3 = new Map();
const skipped = [];
for (const f of countryFeatures) {
  const p = f.properties;
  let code = p.ISO_A2_EH;
  if (!code || code === '-99') code = p.ADM0_A3; // Somaliland, Northern Cyprus, ...
  const rings = cleanRings(f.geometry);
  if (!code || !rings.length) { skipped.push(`country ${p.NAME}`); continue; }
  const feature = { kind: 0, code, name: p.NAME_EN || p.NAME, parent: code, rings };
  byA3.set(p.ADM0_A3, feature);
  features.push(feature);
}
for (const f of simplified(zips.regions, 'regions')) {
  const p = f.properties;
  const code = p.iso_3166_2;
  const parent = byA3.get(p.adm0_a3);
  const rings = cleanRings(f.geometry);
  if (!code || code.includes('-99') || !/^[A-Z0-9]{2,3}-[A-Z0-9]{1,4}$/.test(code) || !parent || !rings.length) {
    skipped.push(`region ${p.name} (${code}, ${p.adm0_a3})`);
    continue;
  }
  features.push({ kind: 1, code, name: p.name_en || p.name, parent: parent.code, rings });
}
features.sort((a, b) => a.kind - b.kind || (a.code < b.code ? -1 : a.code > b.code ? 1 : 0)
  || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));

// String table: sorted unique strings.
const strings = [...new Set(features.flatMap((f) => [f.code, f.name, f.parent]))].sort();
const stringIndex = new Map(strings.map((s, i) => [s, i]));

const w = new Writer();
for (const c of 'RPGE') w.u8(c.charCodeAt(0));
w.u8(FORMAT_VERSION);
w.varint(strings.length);
for (const s of strings) {
  const b = Buffer.from(s, 'utf8');
  w.varint(b.length);
  for (const x of b) w.u8(x);
}
w.varint(features.length);
for (const f of features) {
  w.u8(f.kind);
  w.varint(stringIndex.get(f.code));
  w.varint(stringIndex.get(f.name));
  w.varint(stringIndex.get(f.parent));
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const ring of f.rings) for (const [x, y] of ring) {
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (y < minY) minY = y; if (y > maxY) maxY = y;
  }
  w.svarint(minX); w.svarint(minY);
  w.varint(maxX - minX); w.varint(maxY - minY);
  w.varint(f.rings.length);
  for (const ring of f.rings) {
    w.varint(ring.length);
    let px = 0, py = 0;
    for (const [x, y] of ring) { w.svarint(x - px); w.svarint(y - py); px = x; py = y; }
  }
}

const data = Buffer.from(w.bytes);
if (data.length > MAX_BYTES) throw new Error(`output is ${data.length} bytes, over the ${MAX_BYTES} limit`);
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, data);

const countries = features.filter((f) => f.kind === 0).length;
console.log(`wrote ${target}`);
console.log(`${data.length} bytes (${(data.length / 1048576).toFixed(2)} MiB), ${countries} countries, ${features.length - countries} regions`);
console.log(`sha256 ${createHash('sha256').update(data).digest('hex')}`);
if (skipped.length) console.log(`skipped ${skipped.length} regions without an ISO 3166-2 code (NE placeholders such as XK-X01~), e.g. ${skipped.slice(0, 5).join("; ")}`);
