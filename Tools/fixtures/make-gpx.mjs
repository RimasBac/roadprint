#!/usr/bin/env node
// Builds GPX test fixtures from the I-80 SLC-SAC route in
// docs/plan/mockups/source/routes.json (OSRM routing on OpenStreetMap data, ODbL).
// No dependencies. Run: node Tools/fixtures/make-gpx.mjs
// Output: RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures/*.gpx and expected.json
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const outDir = join(root, 'RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures');
const routes = JSON.parse(readFileSync(join(root, 'docs/plan/mockups/source/routes.json'), 'utf8'));
const coords = routes['SLC-SAC'].coords; // [lon, lat]

// Thresholds. Keep in sync with RecordingHeuristics.default in the core.
const H = { movingMaxInterval: 120, longStopMinDuration: 7200, longStopMaxDisplacement: 1000, gapMinDisplacement: 2000 };
const R = 6371008.8;
const SPACING = 100; // m
const SPEED = 100 / 3.6; // m/s (100 km/h)
const START = Date.parse('2026-06-01T14:00:00Z') / 1000;

const rad = (d) => (d * Math.PI) / 180;
function hav(a, b) {
  const dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

// Resample the polyline to ~100 m spacing.
function resample() {
  const pts = coords.map(([lon, lat]) => ({ lat, lon }));
  const out = [pts[0]];
  let carry = 0; // distance since the last emitted point
  for (let i = 1; i < pts.length; i++) {
    let a = pts[i - 1];
    const b = pts[i];
    let seg = hav(a, b);
    while (carry + seg >= SPACING && seg > 0) {
      const f = (SPACING - carry) / seg;
      a = { lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f };
      out.push(a);
      seg = hav(a, b);
      carry = 0;
    }
    carry += seg;
  }
  return out;
}

// Deterministic PRNG so the output is reproducible.
function mulberry32(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const base = resample();
const round6 = (x) => Math.round(x * 1e6) / 1e6;

// segments: [{from, count}] of base points; extraDelay: seconds added before a segment.
function build(segments) {
  const rnd = mulberry32(42);
  const pts = [];
  let t = START;
  let prev = null;
  for (const seg of segments) {
    for (let k = 0; k < seg.count; k++) {
      const p = base[seg.from + k];
      const lat = round6(p.lat), lon = round6(p.lon);
      if (prev) t += hav(prev, { lat, lon }) / SPEED;
      if (k === 0 && seg.extraDelay) t += seg.extraDelay;
      const ele = Math.round((1288 + 20 * Math.sin((seg.from + k) / 80) + (rnd() * 10 - 5)) * 10) / 10;
      pts.push({ lat, lon, ele, time: Math.round(t) });
      prev = { lat, lon };
    }
  }
  return pts;
}

function analyze(pts) {
  let distance = 0, moving = 0;
  const gaps = [], stops = [];
  for (let i = 1; i < pts.length; i++) {
    const d = hav(pts[i - 1], pts[i]);
    const dt = pts[i].time - pts[i - 1].time;
    if (d >= H.gapMinDisplacement) gaps.push({ startIndex: i - 1, endIndex: i });
    else distance += d;
    if (dt >= 0 && dt <= H.movingMaxInterval) moving += dt;
    if (dt >= H.longStopMinDuration && d < H.longStopMaxDisplacement) {
      stops.push({ startIndex: i - 1, endIndex: i, durationSeconds: dt });
    }
  }
  return {
    pointCount: pts.length,
    distanceMeters: Math.round(distance * 10) / 10,
    movingTimeSeconds: moving,
    elapsedSeconds: pts.length ? pts[pts.length - 1].time - pts[0].time : 0,
    gapCount: gaps.length,
    longStopCount: stops.length,
    gaps,
    longStops: stops,
    expectedStatus: gaps.length > 0 ? 'partial' : 'completed',
  };
}

function gpx(name, pts) {
  const iso = (s) => new Date(s * 1000).toISOString().replace('.000Z', 'Z');
  const lines = pts.map((p) =>
    `      <trkpt lat="${p.lat.toFixed(6)}" lon="${p.lon.toFixed(6)}"><ele>${p.ele}</ele><time>${iso(p.time)}</time></trkpt>`);
  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RoadPrint make-gpx.mjs" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>${name}</name></metadata>
  <trk>
    <name>${name}</name>
    <trkseg>
${lines.join('\n')}
    </trkseg>
  </trk>
</gpx>
`;
}

const fixtures = {
  // ~30 km, small: the iOS UI test replays it too.
  'i80-ui-test': [{ from: 0, count: 300 }],
  // 15 km, 9 h parked in place (no points while parked), 15 km more.
  'i80-long-stop': [{ from: 0, count: 150 }, { from: 150, count: 150, extraDelay: 9 * 3600 }],
  // 15 km, 15 km of missing points, 15 km more. Time keeps running through the gap.
  'i80-gap': [{ from: 0, count: 150 }, { from: 300, count: 150 }],
};

mkdirSync(outDir, { recursive: true });
const expected = {};
for (const [name, segs] of Object.entries(fixtures)) {
  const pts = build(segs);
  writeFileSync(join(outDir, `${name}.gpx`), gpx(name, pts));
  expected[name] = analyze(pts);
}
writeFileSync(join(outDir, 'expected.json'), JSON.stringify(expected, null, 2) + '\n');
console.log(JSON.stringify(Object.fromEntries(Object.entries(expected).map(([k, v]) => [k, { ...v, gaps: v.gaps.length, longStops: v.longStops.length }])), null, 1));
