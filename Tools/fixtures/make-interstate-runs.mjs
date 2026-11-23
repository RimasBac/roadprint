#!/usr/bin/env node
// Builds the trip history the App Store screenshots seed (AppStoreScreenshotHistory): a long-haul
// driver's runs on the US Interstate network, as day-sized legs between real junction cities.
//
// Every point is a vertex of the app's own road index (roads.rpgeo, from Natural Earth 1:10m), so
// the seeded trips lie on the roads the app knows: trip processing names their main road, and the
// lifetime map shows real Interstates that meet at junctions instead of lines ending in open country.
//
// No dependencies. Run: node Tools/fixtures/make-interstate-runs.mjs
// Output: RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures/us-interstate-runs.json
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const INDEX = join(root, 'RoadPrintCore/Sources/RoadPrintCore/Resources/roads.rpgeo');
const PLACES = join(root, 'RoadPrintCore/Sources/RoadPrintCore/Resources/places.rpgeo');
const OUT = join(root, 'RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures/us-interstate-runs.json');

const C = {
  sanDiego: [32.72, -117.16], losAngeles: [34.05, -118.25], ontario: [34.06, -117.65], barstow: [34.90, -117.02],
  sacramento: [38.58, -121.49], eugene: [44.05, -123.09], portland: [45.52, -122.68], seattle: [47.61, -122.33],
  sanFrancisco: [37.80, -122.27], reno: [39.53, -119.81], saltLakeCity: [40.76, -111.89], cheyenne: [41.14, -104.82],
  omaha: [41.26, -95.94], chicago: [41.53, -88.08], youngstown: [41.10, -80.65], newYork: [40.89, -74.01],
  spokane: [47.66, -117.43], billings: [45.78, -108.50], rapidCity: [44.08, -103.23], siouxFalls: [43.55, -96.73],
  madison: [43.07, -89.40], toledo: [41.65, -83.54], buffalo: [42.89, -78.88], boston: [42.36, -71.06],
  phoenix: [33.45, -112.07], elPaso: [31.76, -106.49], sanAntonio: [29.42, -98.49], batonRouge: [30.45, -91.15],
  tallahassee: [30.44, -84.28], jacksonville: [30.33, -81.66], lasVegas: [36.17, -115.14], butte: [46.00, -112.53],
  greatFalls: [47.50, -111.30], flagstaff: [35.20, -111.65], albuquerque: [35.08, -106.65], oklahomaCity: [35.47, -97.52],
  memphis: [35.15, -90.05], knoxville: [35.96, -83.92], wilmington: [34.23, -77.94], coveFort: [38.60, -112.59],
  denver: [39.74, -104.99], kansasCity: [39.10, -94.58], indianapolis: [39.77, -86.16], baltimore: [39.29, -76.61],
  miami: [25.77, -80.19], fayetteville: [35.05, -78.88], philadelphia: [39.95, -75.17], 
  dallas: [32.78, -96.80], wichita: [37.69, -97.34], desMoines: [41.59, -93.62], duluth: [46.79, -92.10],
  lasCruces: [32.32, -106.76], buffaloWY: [44.35, -106.70], tampa: [27.95, -82.46], atlanta: [33.75, -84.39],
  lexington: [38.04, -84.50], detroit: [42.33, -83.05], kent: [31.06, -104.20], jackson: [32.30, -90.18],
  florence: [34.20, -79.76], gary: [41.60, -87.34], nashville: [36.16, -86.78], mobile: [30.69, -88.04],
  newOrleans: [29.95, -90.07], fargo: [46.88, -96.79], minneapolis: [44.98, -93.27], boise: [43.62, -116.20],
  echo: [40.97, -111.44],
};

// Each road, as the cities its runs stop at. `repeat` marks a run hauled more than once.
const ROADS = [
  ['5', ['sanDiego', 'sacramento', 'eugene', 'seattle'], {'sacramento-eugene': 2}],
  ['10', ['losAngeles', 'phoenix', 'elPaso', 'sanAntonio', 'batonRouge', 'tallahassee', 'jacksonville'], {'elPaso-sanAntonio': 2}],
  ['15', ['ontario', 'lasVegas', 'saltLakeCity', 'butte', 'greatFalls'], {}],
  ['40', ['barstow', 'flagstaff', 'albuquerque', 'oklahomaCity', 'memphis', 'knoxville', 'wilmington'], {'oklahomaCity-memphis': 2}],
  ['70', ['coveFort', 'denver', 'kansasCity', 'indianapolis', 'baltimore'], {'denver-kansasCity': 2}],
  ['80', ['sanFrancisco', 'reno', 'saltLakeCity', 'cheyenne', 'omaha', 'chicago', 'youngstown', 'newYork'], {'omaha-chicago': 3, 'chicago-youngstown': 2}],
  ['90', ['seattle', 'spokane', 'billings', 'rapidCity', 'siouxFalls', 'madison', 'toledo', 'buffalo', 'boston'], {}],
  ['95', ['miami', 'jacksonville', 'fayetteville', 'philadelphia', 'boston'], {}],
  ['35', ['sanAntonio', 'dallas', 'wichita', 'desMoines', 'duluth'], {'sanAntonio-dallas': 3}],
  ['25', ['lasCruces', 'albuquerque', 'denver', 'buffaloWY'], {}],
  ['75', ['tampa', 'atlanta', 'lexington', 'detroit'], {}],
  ['20', ['kent', 'dallas', 'jackson', 'atlanta', 'florence'], {}],
  ['65', ['gary', 'nashville', 'mobile'], {}],
  ['55', ['chicago', 'memphis', 'newOrleans'], {}],
  ['94', ['billings', 'fargo', 'minneapolis', 'madison', 'detroit'], {}],
  ['84', ['portland', 'boise', 'echo'], {}],
];

const MAX_RUN_KM = 1000; // a run is one driving day or two; longer means the route went wrong
const BRIDGE_M = 30_000; // the longest hole in the data a run may jump (Natural Earth leaves out some stretches)
const OTHER_ROAD = 1.6; // cost factor on another Interstate: used only where the road's own number is missing (shared pavement)
const BRIDGE = 4; // cost factor across a hole

const R = 6371008.8;
const rad = (d) => (d * Math.PI) / 180;
const hav = (a, b) => {
  const h = Math.sin(rad(b[0] - a[0]) / 2) ** 2 + Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(rad(b[1] - a[1]) / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
};
const length = (points) => points.slice(1).reduce((sum, p, k) => sum + hav(points[k], p), 0);

/** The US Interstate polylines of roads.rpgeo (Tools/roads/FORMAT.md): [{ref, points: [[lat, lon], ...]}]. */
export function readInterstates(path = INDEX) {
  const buf = readFileSync(path);
  if (buf.toString('latin1', 0, 4) !== 'RPRD' || buf[4] !== 1) throw new Error(`${path}: not a version 1 road index`);
  let o = 5;
  const varint = () => { let r = 0, s = 0, b; do { b = buf[o++]; r += (b & 127) * 2 ** s; s += 7; } while (b & 128); return r; };
  const zigzag = () => { const n = varint(); return n % 2 ? -(n + 1) / 2 : n / 2; };
  const strings = [];
  for (let n = varint(); n--;) { const l = varint(); strings.push(buf.toString('utf8', o, o + l)); o += l; }
  const parts = [];
  for (let n = varint(); n--;) {
    const network = buf[o++], ref = strings[varint()], country = strings[varint()];
    for (let p = varint(); p--;) {
      let x = 0, y = 0; const points = [];
      for (let k = varint(); k--;) { x += zigzag(); y += zigzag(); points.push([y / 1e5, x / 1e5]); }
      if (network === 1 && country === 'US') parts.push({ref, points});
    }
  }
  return parts;
}

/** The outline rings of one country in places.rpgeo (Tools/places/FORMAT.md), as [[lon, lat], ...]. */
export function readCountry(code, path = PLACES) {
  const buf = readFileSync(path);
  if (buf.toString('latin1', 0, 4) !== 'RPGE' || buf[4] !== 1) throw new Error(`${path}: not a version 1 places index`);
  let o = 5;
  const varint = () => { let r = 0, s = 0, b; do { b = buf[o++]; r += (b & 127) * 2 ** s; s += 7; } while (b & 128); return r; };
  const zigzag = () => { const n = varint(); return n % 2 ? -(n + 1) / 2 : n / 2; };
  const strings = [];
  for (let n = varint(); n--;) { const l = varint(); strings.push(buf.toString('utf8', o, o + l)); o += l; }
  for (let n = varint(); n--;) {
    const kind = buf[o++], name = strings[varint()];
    varint(); varint(); zigzag(); zigzag(); varint(); varint(); // name, parent, bounding box
    const rings = [];
    for (let r = varint(); r--;) {
      let x = 0, y = 0; const ring = [];
      for (let k = varint(); k--;) { x += zigzag(); y += zigzag(); ring.push([x / 1e5, y / 1e5]); }
      rings.push(ring);
    }
    if (kind === 0 && name === code) return rings;
  }
  throw new Error(`${code} is not in ${path}`);
}

/** Even-odd point-in-polygon over all rings, as PlaceIndex does. Points are [lat, lon]. */
function inside(rings, [lat, lon]) {
  let odd = false;
  for (const ring of rings) {
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const [xi, yi] = ring[i], [xj, yj] = ring[j];
      if ((yi > lat) !== (yj > lat) && lon < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) odd = !odd;
    }
  }
  return odd;
}

/** Points along the run every `step` metres or less, as the seed samples it. */
function along(points, step) {
  const out = [points[0]];
  for (let i = 1; i < points.length; i++) {
    const [a, b] = [points[i - 1], points[i]];
    const n = Math.max(1, Math.ceil(hav(a, b) / step));
    for (let k = 1; k <= n; k++) out.push([a[0] + ((b[0] - a[0]) * k) / n, a[1] + ((b[1] - a[1]) * k) / n]);
  }
  return out;
}

/**
 * The whole US Interstate network as one graph. Vertices along a part are joined in order; each
 * part's two ends are joined to the nearest vertex of every other part within BRIDGE_M, which
 * links junctions, the pieces Natural Earth split a road into, and the few holes in its data.
 */
export function network(parts) {
  const nodes = [], ref = [], edges = [];
  const cell = (p) => `${Math.floor(p[0] * 10)},${Math.floor(p[1] * 10)}`; // 0.1°: about 11 km north-south
  const grid = new Map();
  const ranges = parts.map((part) => {
    const first = nodes.length;
    for (const p of part.points) {
      grid.set(cell(p), [...(grid.get(cell(p)) ?? []), nodes.length]);
      nodes.push(p); ref.push(part.ref); edges.push([]);
    }
    return [first, nodes.length - 1];
  });
  const link = (a, b, road) => { const d = hav(nodes[a], nodes[b]); edges[a].push({to: b, d, road}); edges[b].push({to: a, d, road}); };
  const partOf = new Int32Array(nodes.length);
  ranges.forEach(([first, last], i) => { partOf.fill(i, first, last + 1); for (let k = first; k < last; k++) link(k, k + 1, ref[k]); });
  for (const [first, last] of ranges) {
    for (const end of [first, last]) {
      const best = new Map(); // other part → [node, distance]
      const [cy, cx] = [Math.floor(nodes[end][0] * 10), Math.floor(nodes[end][1] * 10)];
      for (let dy = -2; dy <= 2; dy++) for (let dx = -3; dx <= 3; dx++) {
        for (const k of grid.get(`${cy + dy},${cx + dx}`) ?? []) {
          if (partOf[k] === partOf[end]) continue;
          const d = hav(nodes[end], nodes[k]);
          if (d <= BRIDGE_M && d < (best.get(partOf[k])?.[1] ?? Infinity)) best.set(partOf[k], [k, d]);
        }
      }
      for (const [k] of best.values()) link(end, k, null);
    }
  }
  return {nodes, ref, edges};
}

/**
 * The vertex of road `road` nearest to `point`; where the data has that stretch only under another
 * number (shared pavement, such as I-80/I-90 from Chicago to Toledo), the nearest Interstate vertex.
 */
function nearest(net, road, point) {
  let own = -1, any = -1;
  net.nodes.forEach((node, i) => {
    const d = hav(node, point);
    if (net.ref[i] === road && (own < 0 || d < hav(net.nodes[own], point))) own = i;
    if (any < 0 || d < hav(net.nodes[any], point)) any = i;
  });
  return own >= 0 && hav(net.nodes[own], point) <= 25_000 ? own : any;
}

/** Cheapest path from `from` to `to`, keeping to road `road` where it can (Dijkstra on a binary heap). */
function route(net, road, from, to) {
  const cost = (e) => e.d * (e.road === road ? 1 : e.road === null ? (e.d < 200 ? 1 : BRIDGE) : OTHER_ROAD);
  const dist = new Float64Array(net.nodes.length).fill(Infinity);
  const prev = new Int32Array(net.nodes.length).fill(-1);
  const via = new Array(net.nodes.length);
  const heap = [[0, from]];
  const push = (item) => { heap.push(item); let i = heap.length - 1; while (i > 0) { const p = (i - 1) >> 1; if (heap[p][0] <= heap[i][0]) break; [heap[p], heap[i]] = [heap[i], heap[p]]; i = p; } };
  const pop = () => { const top = heap[0], last = heap.pop(); if (heap.length) { heap[0] = last; let i = 0; for (;;) { const l = 2 * i + 1, r = l + 1; let m = i; if (l < heap.length && heap[l][0] < heap[m][0]) m = l; if (r < heap.length && heap[r][0] < heap[m][0]) m = r; if (m === i) break; [heap[m], heap[i]] = [heap[i], heap[m]]; i = m; } } return top; };
  dist[from] = 0;
  while (heap.length) {
    const [c, u] = pop();
    if (c > dist[u]) continue;
    if (u === to) break;
    for (const e of net.edges[u]) {
      const next = c + cost(e);
      if (next < dist[e.to]) { dist[e.to] = next; prev[e.to] = u; via[e.to] = e; push([next, e.to]); }
    }
  }
  if (prev[to] < 0) return null;
  const points = [], legs = [];
  for (let at = to; at >= 0; at = prev[at]) { points.unshift(net.nodes[at]); if (via[at]) legs.unshift(via[at]); }
  const own = legs.filter((e) => e.road === road).reduce((s, e) => s + e.d, 0);
  const bridges = legs.filter((e) => e.road === null).map((e) => e.d);
  return {points, km: length(points) / 1000, own: own / length(points), longestBridgeKm: Math.max(0, ...bridges) / 1000};
}

function main() {
  const net = network(readInterstates());
  // The neighbours: a fix inside one makes the app count a second country (water counts as none).
  const neighbours = ['CA', 'MX'].map((code) => [code, readCountry(code)]);
  const runs = [], report = [];
  for (const [road, stops, repeats] of ROADS) {
    for (let i = 1; i < stops.length; i++) {
      const [a, b] = [stops[i - 1], stops[i]];
      const [start, end] = [nearest(net, road, C[a]), nearest(net, road, C[b])];
      if (start < 0) throw new Error(`I-${road} is not in the road index`);
      for (const [name, at] of [[a, start], [b, end]]) {
        const off = hav(net.nodes[at], C[name]);
        if (off > 40_000) throw new Error(`I-${road}: ${name} is ${Math.round(off / 1000)} km from the road`);
      }
      const found = route(net, road, start, end);
      if (!found) throw new Error(`I-${road}: no route from ${a} to ${b}`);
      const crow = hav(C[a], C[b]) / 1000;
      if (found.km > MAX_RUN_KM || found.km > crow * 1.6) {
        throw new Error(`I-${road}: ${a} to ${b} is ${Math.round(found.km)} km (${Math.round(crow)} km direct)`);
      }
      // No fix the seed will make may fall in Canada or Mexico, or the screenshots count two countries.
      for (const p of along(found.points, 1_500)) {
        for (const [code, rings] of neighbours) {
          if (inside(rings, p)) throw new Error(`I-${road}: ${a} to ${b} enters ${code} at ${p.map((v) => v.toFixed(3)).join(', ')}`);
        }
      }
      const repeat = repeats[`${a}-${b}`] ?? 1;
      runs.push({road: `I-${road}`, from: a, to: b, repeat,
        points: found.points.map(([lat, lon]) => [+lat.toFixed(5), +lon.toFixed(5)])});
      report.push(`I-${road.padEnd(3)} ${(a + ' → ' + b).padEnd(30)} ${String(Math.round(found.km * 0.621371)).padStart(4)} mi` +
        `  ${Math.round(found.own * 100)}% on I-${road}  longest hole ${found.longestBridgeKm.toFixed(1)} km${repeat > 1 ? `  ×${repeat}` : ''}`);
    }
  }
  const miles = runs.reduce((sum, r) => sum + r.repeat * length(r.points), 0) / 1609.344;
  writeFileSync(OUT, JSON.stringify({
    note: 'Simulated long-haul runs for the App Store screenshots. Generated by Tools/fixtures/make-interstate-runs.mjs ' +
      'from roads.rpgeo (Natural Earth 1:10m roads, public domain); do not edit.',
    miles: Math.round(miles),
    runs,
  }) + '\n');
  console.log(report.join('\n'));
  console.log(`${runs.length} runs, ${runs.reduce((s, r) => s + r.repeat, 0)} trips, ${Math.round(miles)} mi → ${OUT}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();

