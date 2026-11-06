#!/usr/bin/env node
// Writes the sparse I-80 SLC → Sacramento route used by the PlaceIndex tests:
// every 20th vertex of the SLC-SAC route as [lat, lon], 5-decimal precision.
// Source: docs/plan/mockups/source/routes.json (OSRM on OpenStreetMap data, © OpenStreetMap contributors, ODbL).
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const coords = JSON.parse(readFileSync(join(root, 'docs/plan/mockups/source/routes.json'), 'utf8'))['SLC-SAC'].coords;
const out = coords.filter((_, i) => i % 20 === 0 || i === coords.length - 1)
  .map(([lon, lat]) => [Number(lat.toFixed(5)), Number(lon.toFixed(5))]);
const path = join(root, 'RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures/i80-slc-sac-route.json');
writeFileSync(path, JSON.stringify(out) + '\n');
console.log(`${out.length} points → ${path}`);
