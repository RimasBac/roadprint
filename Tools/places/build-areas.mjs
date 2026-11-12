#!/usr/bin/env node
// Builds RoadPrintCore/Sources/RoadPrintCore/Resources/areas.rppl (populated places) from Natural Earth.
// Format: see FORMAT.md ("areas.rppl"). Deterministic: the same input zip gives a byte-identical file.
//
//   cd Tools/places && npm install --include=dev && node build-areas.mjs

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, 'out');
const target = resolve(here, '../../RoadPrintCore/Sources/RoadPrintCore/Resources/areas.rppl');

/** Natural Earth 5.1.x 1:10m populated places (public domain). The hash pins the exact input. */
const INPUT = {
  file: 'ne_10m_populated_places.zip',
  sha256: 'cd149186f03d2603e0410da399b980a4357d0ac32d3a2305a49ed3dffcc41d7b',
};
const BASE_URL = 'https://naciscdn.org/naturalearth/10m/cultural/';
const MIN_POPULATION = 50000;
const SCALE = 1e4; // 1e-4 degrees, about 11 m
const MAX_BYTES = 400 * 1024;

mkdirSync(outDir, { recursive: true });
const zip = join(outDir, INPUT.file);
if (!existsSync(zip)) {
  console.log(`downloading ${INPUT.file}`);
  const res = await fetch(BASE_URL + INPUT.file);
  if (!res.ok) throw new Error(`download failed: ${res.status}`);
  writeFileSync(zip, Buffer.from(await res.arrayBuffer()));
}
const sha = createHash('sha256').update(readFileSync(zip)).digest('hex');
if (sha !== INPUT.sha256) throw new Error(`${INPUT.file}: SHA-256 ${sha} does not match the pinned ${INPUT.sha256}`);

const dir = join(outDir, 'pp');
const json = join(dir, 'pp.json');
execFileSync('unzip', ['-o', '-q', zip, '-d', dir]);
execFileSync(join(here, 'node_modules/.bin/mapshaper'), [
  join(dir, 'ne_10m_populated_places.shp'), '-filter', `POP_MAX>=${MIN_POPULATION}`,
  '-filter-fields', 'NAME,NAME_EN,ADM0_A3,ISO_A2,POP_MAX,LATITUDE,LONGITUDE',
  '-o', json, 'format=json', 'force',
], { stdio: ['ignore', 'ignore', 'inherit'] });

const places = JSON.parse(readFileSync(json, 'utf8')).map((p) => {
  let country = p.ISO_A2;
  if (!country || country === '-99') country = p.ADM0_A3;
  return {
    name: (p.NAME_EN || p.NAME).normalize('NFC'),
    lat: Math.round(p.LATITUDE * SCALE), lon: Math.round(p.LONGITUDE * SCALE),
    pop: Math.round(p.POP_MAX), country,
  };
});
const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
places.sort((a, b) => b.pop - a.pop || cmp(a.name, b.name) || a.lat - b.lat || a.lon - b.lon);

const countries = [...new Set(places.map((p) => p.country))].sort();
const countryIndex = new Map(countries.map((c, i) => [c, i]));
const bytes = [];
const u8 = (v) => bytes.push(v);
const varint = (v) => { while (v >= 0x80) { bytes.push((v % 0x80) | 0x80); v = Math.floor(v / 0x80); } bytes.push(v); };
const svarint = (v) => varint(v < 0 ? -2 * v - 1 : 2 * v);
const str = (s) => { const b = Buffer.from(s, 'utf8'); varint(b.length); for (const x of b) u8(x); };

for (const c of 'RPPL') u8(c.charCodeAt(0));
u8(1);
varint(countries.length);
for (const c of countries) str(c);
varint(places.length);
for (const p of places) { str(p.name); svarint(p.lat); svarint(p.lon); varint(p.pop); varint(countryIndex.get(p.country)); }

const data = Buffer.from(bytes);
if (data.length > MAX_BYTES) throw new Error(`output is ${data.length} bytes, over the ${MAX_BYTES} limit`);
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, data);
console.log(`wrote ${target}\n${data.length} bytes, ${places.length} places with POP_MAX >= ${MIN_POPULATION}`);
console.log(`sha256 ${createHash('sha256').update(data).digest('hex')}`);
