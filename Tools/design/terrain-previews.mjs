#!/usr/bin/env node
// Terrain card (style 5) composition previews and templates. Not production code, not a dataset check.
//
// The relief layer comes from terrain_relief.py: a full-screen perspective heightfield from real
// elevation (AWS Terrain Tiles, Terrarium) at the zoom that matches the mesh, golden-hour light and
// Natural Earth land cover. That detail needs the elevation source in docs/adr/0006 (tiles for the
// trip's area), not the 2′ bundle of ADR 0001. Routes: I-80 uses the mockup route and elevation
// profile; Brenner and Nullarbor use OSRM (OSM) road geometry.
// This file adds scrims, the ribbon, the summit label, the type and the chips. Every visual value
// comes from Design/tokens.json `terrain.*`.
// Output: Design/cards/terrain/previews/*.png (1080×1920) and the editable templates
// Design/cards/terrain/terrain-card.svg and terrain-card-hide-route.svg (relief as a slot).
//
// Usage: node terrain-previews.mjs [variant ...] [--reuse]   (python3 with numpy, scipy, pillow on PATH)
//   --reuse  keep build/<variant>.relief.* from an earlier run (type and overlay changes only)
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { Resvg } from '@resvg/resvg-js';
import { renderSvg, fontOptions } from './render.mjs';

const ROOT = new URL('../../', import.meta.url);
const T = JSON.parse(readFileSync(new URL('Design/tokens.json', ROOT)));
const CARD_DIR = new URL('Design/cards/terrain/', ROOT), OUT = new URL('previews/', CARD_DIR);
mkdirSync(OUT, { recursive: true });

// ---------- token helpers ----------
const C = T.color, TT = T.terrain, L = TT.layout;
const v = o => o.$value;
const W = v(TT.export.width), H = v(TT.export.height);
const BG = C.background.$value, SIDE = v(TT.safeArea.side);
const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const ref = s => (typeof s === 'string' && s.startsWith('{') ? s.slice(1, -1).split('.').reduce((o, k) => o[k], T).$value : s);
const typeStyle = k => { const t = v(TT.type[k]); return { ...t, color: ref(t.color) }; };
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));

// ---------- text ----------
function textAttrs(k, extra = '') {
  const s = typeStyle(k);
  const stretch = s.family.includes('Condensed') ? ' font-stretch="condensed"' : '';
  return `font-family="${s.family}"${stretch} font-weight="${s.weight}" font-size="${s.size}" letter-spacing="${s.tracking}" fill="${s.color}" ${extra}`;
}
const cased = (k, str) => (typeStyle(k).case === 'upper' ? str.toLocaleUpperCase('de') : str);
// Barlow Condensed lacks the arrow and resvg falls back for a whole <text> when one glyph is missing,
// so the arrow gets its own element in Inter.
function textEl(k, str, x, y, extra = '') {
  const s = cased(k, str);
  if (!s.includes('→') || !typeStyle(k).family.includes('Condensed')) return `<text x="${x}" y="${y}" ${textAttrs(k, extra)}>${esc(s)}</text>`;
  let cx = Number(x), out = `<g ${extra}>`;
  for (const p of s.split(/(→)/)) {
    if (!p) continue;
    if (p === '→') { const sz = typeStyle(k).size; out += `<text x="${cx.toFixed(1)}" y="${y}" font-family="Inter" font-weight="500" font-size="${sz * 0.8}" fill="${typeStyle(k).color}">→</text>`; cx += sz * 0.8 * 0.95; }
    else { out += `<text x="${cx.toFixed(1)}" y="${y}" ${textAttrs(k)} xml:space="preserve">${esc(p)}</text>`; cx += advance(k, p); }
  }
  return out + '</g>';
}
function inkWidth(svgText) {
  const bb = new Resvg(`<svg xmlns="http://www.w3.org/2000/svg" width="3000" height="400">${svgText}</svg>`, { font: fontOptions() }).getBBox();
  return bb ? bb.width : 0;
}
// advance incl. spaces: ink("|s|") − ink("||")
function advance(k, s) { return inkWidth(`<text x="0" y="300" ${textAttrs(k)} xml:space="preserve">|${esc(s)}|</text>`) - inkWidth(`<text x="0" y="300" ${textAttrs(k)}>||</text>`); }
function measure(k, str) { return inkWidth(textEl(k, str, 0, 300)); }

// ---------- shared filters ----------
// One soft ink shadow under all type and labels: grow, blur, fade (the Print card's recipe, one pass).
function textShadowDef() {
  const s = TT.textShadow, c = hex(v(s.color)).map(x => (x / 255).toFixed(3));
  return `<filter id="txt-shade" color-interpolation-filters="sRGB" x="-20%" y="-40%" width="140%" height="180%"><feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 ${c[0]}  0 0 0 0 ${c[1]}  0 0 0 0 ${c[2]}  0 0 0 1 0" result="a"/>` +
    `<feMorphology in="a" operator="dilate" radius="${v(s.spread)}" result="ad"/><feGaussianBlur in="ad" stdDeviation="${v(s.blur)}" result="b"/><feComponentTransfer in="b" result="o"><feFuncA type="linear" slope="${v(s.opacity)}"/></feComponentTransfer>` +
    `<feMerge><feMergeNode in="o"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`;
}
const SHADE = ' filter="url(#txt-shade)"';
// Scrims: the land runs under the type, so soft background-colour gradients hold the title and number.
function scrimSvg() {
  const sc = TT.scrim;
  return `<defs><linearGradient id="scrim-top-fill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${BG}" stop-opacity="${v(sc.top.opacity)}"/><stop offset="1" stop-color="${BG}" stop-opacity="0"/></linearGradient>` +
    `<linearGradient id="scrim-bottom-fill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${BG}" stop-opacity="0"/><stop offset="1" stop-color="${BG}" stop-opacity="${v(sc.bottom.opacity)}"/></linearGradient></defs>` +
    `<rect id="scrim-top" width="${W}" height="${v(sc.top.to)}" fill="url(#scrim-top-fill)"/><rect id="scrim-bottom" y="${v(sc.bottom.from)}" width="${W}" height="${H - v(sc.bottom.from)}" fill="url(#scrim-bottom-fill)"/>`;
}

// ---------- ribbon, ends, summit, places ----------
const RB = TT.ribbon, LIFT = v(RB.lift);
function ribbonSvg(pts) {
  const segs = { vis: [], hid: [], gap: [] };
  let cur = null, kind = null;
  const pt = p => `${p.sx.toFixed(1)},${p.sy.toFixed(1)}`;
  for (let i = 0; i < pts.length; i++) {
    const p = pts[i];
    if (p.gap) { if (cur) { segs[kind].push(cur); cur = null; } continue; } // gaps are linked below
    const k = p.hidden ? 'hid' : 'vis';
    if (i > 0 && pts[i - 1].gap) { const prev = pts.slice(0, i).reverse().find(q => !q.gap); if (prev) segs.gap.push([pt(prev), pt(p)]); }
    if (kind !== k && cur) { cur.push(pt(p)); segs[kind].push(cur); cur = null; }
    if (!cur) { cur = i > 0 && !pts[i - 1].gap ? [pt(pts[i - 1])] : []; kind = k; }
    cur.push(pt(p));
  }
  if (cur) segs[kind].push(cur);
  const d = list => list.filter(s => s.length > 1).map(s => 'M' + s.join('L')).join('');
  const glow = v(RB.glow), oc = RB.occluded, gp = RB.gap, sh = RB.shadow;
  // Occluded and gap segments stay on the ground; the visible ribbon floats LIFT px above its track,
  // which keeps a soft shadow: the 3D cue that shows where the road meets the land.
  return `
  <defs>${glow.map((g, i) => `<filter id="ribbon-glow-${i}" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="${g.radius}"/></filter>`).join('')}<filter id="ribbon-shadow-blur" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="${v(sh.blur)}"/></filter></defs>
  <g id="ribbon" fill="none" stroke-linejoin="round" stroke-linecap="round">
    <path id="ribbon-occluded" d="${d(segs.hid)}" stroke="${v(oc.color)}" stroke-opacity="${v(oc.opacity)}" stroke-width="${v(oc.width)}" stroke-dasharray="${v(oc.dash).dashArray.join(' ')}" stroke-linecap="${v(oc.dash).lineCap}"/>
    <path id="ribbon-gap" d="${d(segs.gap)}" stroke="${v(gp.color)}" stroke-opacity="${v(gp.opacity)}" stroke-width="${v(gp.width)}" stroke-dasharray="${v(gp.dash).dashArray.join(' ')}" stroke-linecap="${v(gp.dash).lineCap}"/>
    <path id="ribbon-shadow" d="${d(segs.vis)}" stroke="${v(sh.color)}" stroke-opacity="${v(sh.opacity)}" stroke-width="${v(sh.width)}" filter="url(#ribbon-shadow-blur)"/>
    <g id="ribbon-lifted" transform="translate(0 ${-LIFT})">
    ${glow.map((g, i) => `<path id="ribbon-glow-${i}-path" d="${d(segs.vis)}" stroke="${g.color}" stroke-opacity="${g.opacity}" stroke-width="${g.width}" filter="url(#ribbon-glow-${i})"/>`).join('')}
    <path id="ribbon-casing" d="${d(segs.vis)}" stroke="${v(RB.casing.color)}" stroke-opacity="${v(RB.casing.opacity)}" stroke-width="${v(RB.casing.width)}"/>
    <path id="ribbon-visible" d="${d(segs.vis)}" stroke="${v(RB.color)}" stroke-width="${v(RB.width)}"/>
    </g>
  </g>`;
}
function endpointsSvg(pts) {
  const e = RB.endpoint, valid = pts.filter(p => !p.gap);
  const c = p => `<circle cx="${p.sx.toFixed(1)}" cy="${(p.sy - LIFT).toFixed(1)}" r="${v(e.radius)}" fill="${v(e.color)}" fill-opacity="${v(e.fillOpacity)}" stroke="${v(e.color)}" stroke-width="${v(e.stroke)}"/>`;
  return `<g id="route-ends">${c(valid[0])}${c(valid[valid.length - 1])}</g>`;
}
/** Summit: marker on the lifted ribbon, a vertical leader and three plate-less lines with the text
 *  shadow. Placement: above/below × open side/other side, then longer leaders; the label stays near the
 *  route band (clear of the title and the number), inside the side safe area, and off the ribbon. */
function summitSvg(pts, label) {
  const S = TT.summit, valid = pts.filter(p => !p.gap);
  const p = valid.reduce((a, b) => (b.elev > a.elev ? b : a));
  const mx = p.sx, my = p.sy - LIFT, lead = v(S.leader.length);
  const lab = S.label, gap = v(lab.gapToLeader), lg = v(lab.lineGap), pp = v(lab.platePadding), mr = v(S.marker.radius);
  const lines = [['summitKicker', label.kicker, typeStyle('summitKicker').size], ['summitValue', label.value, typeStyle('summitValue').size * 0.8]];
  if (label.name) lines.push(['summitName', label.name, typeStyle('summitName').size]);
  const bw = Math.max(...lines.map(([k, s]) => measure(k, s))), bh = lines.reduce((a, l) => a + l[2], 0) + lg * (lines.length - 1);
  const ribbon = valid.map(q => [q.sx, q.sy - LIFT]);
  const frameTop = v(L.routeBandTop) - 150, frameBot = v(L.routeBandBottom) + 40;
  const open = mx < W / 2 ? 1 : -1;
  let best = null;
  for (const mult of [1, 1.5, 2]) for (const dir of [-1, 1]) for (const sideSign of [open, -open]) {
    if (best) break;
    const ly = my + dir * lead * mult, tx = sideSign > 0 ? mx + gap : mx - gap - bw;
    const box = dir < 0 ? [tx - pp, ly - bh - pp, tx + bw + pp, ly + pp] : [tx - pp, ly - pp, tx + bw + pp, ly + bh + pp];
    if (box[0] < SIDE - pp || box[2] > W - SIDE + pp || box[1] < frameTop || box[3] > frameBot) continue;
    if (ribbon.some(([x, y]) => x > box[0] - 6 && x < box[2] + 6 && y > box[1] - 6 && y < box[3] + 6)) continue;
    best = { tx, ly, dir, box };
  }
  if (!best) { const ly = my - lead, tx = clamp(open > 0 ? mx + gap : mx - gap - bw, SIDE, W - SIDE - bw); best = { tx, ly, dir: -1, box: [tx - pp, ly - bh - pp, tx + bw + pp, ly + pp] }; }
  const { tx, dir, box, ly } = best;
  let y = box[1] + pp + lines[0][2];
  const out = [`<g id="summit"${SHADE}>`,
    `<line id="summit-leader" x1="${mx.toFixed(1)}" y1="${(my + dir * mr).toFixed(1)}" x2="${mx.toFixed(1)}" y2="${ly.toFixed(1)}" stroke="${v(S.leader.color)}" stroke-opacity="${v(S.leader.opacity)}" stroke-width="${v(S.leader.width)}"/>`,
    `<circle id="summit-marker" cx="${mx.toFixed(1)}" cy="${my.toFixed(1)}" r="${mr + v(S.marker.ring)}" fill="${BG}"/>`,
    `<circle cx="${mx.toFixed(1)}" cy="${my.toFixed(1)}" r="${mr}" fill="${v(S.marker.fill)}"/>`];
  lines.forEach(([k, s, hgt], i) => { if (i) y += hgt + lg; out.push(textEl(k, s, tx.toFixed(1), y.toFixed(1), `id="summit-${['kicker', 'value', 'name'][i]}"`)); });
  return out.join('') + '</g>';
}
// Hide-route: pins at the two named places' city centres (never trip points), names above them.
function placesSvg(pts, names) {
  const S = TT.summit, mr = v(S.marker.radius);
  return `<g id="places"${SHADE}>${pts.map((p, i) => {
    const w = measure('summitName', names[i]), x = clamp(p.sx - w / 2, SIDE, W - SIDE - w), y = p.sy - mr - 16;
    return `<g id="place-${i + 1}">${textEl('summitName', names[i], x.toFixed(1), y.toFixed(1), `id="place-${i + 1}-name"`)}` +
      `<circle cx="${p.sx.toFixed(1)}" cy="${p.sy.toFixed(1)}" r="${mr + v(S.marker.ring)}" fill="${BG}"/><circle cx="${p.sx.toFixed(1)}" cy="${p.sy.toFixed(1)}" r="${mr}" fill="${v(S.marker.fill)}"/></g>`;
  }).join('')}</g>`;
}

// ---------- type ----------
function roadSign(sign, x, y) {
  const z = v(L.roadSignSize);
  if (sign.kind === 'interstate') return `<g id="road-sign" transform="translate(${x},${y})">
    <path d="M6 6 Q${z / 2} 0 ${z - 6} 6 Q${z} ${z * 0.5} ${z / 2} ${z} Q0 ${z * 0.5} 6 6Z" fill="#1f4aa8" stroke="#f0efec" stroke-width="3"/>
    <path d="M6 6 Q${z / 2} 0 ${z - 6} 6 L${z - 3} ${z * 0.26} L3 ${z * 0.26}Z" fill="#c8202f"/>
    <text x="${z / 2}" y="${z * 0.72}" text-anchor="middle" font-family="Barlow Condensed" font-stretch="condensed" font-weight="700" font-size="34" fill="#ffffff">${sign.number}</text></g>`;
  if (sign.kind === 'e-road') return `<g id="road-sign" transform="translate(${x},${y + 12})">
    <rect width="${z + 16}" height="${z - 24}" rx="6" fill="#00843d" stroke="#ffffff" stroke-width="3"/>
    <text x="${(z + 16) / 2}" y="${z * 0.5}" text-anchor="middle" font-family="Barlow Condensed" font-stretch="condensed" font-weight="700" font-size="34" fill="#ffffff">${sign.number}</text></g>`;
  return `<g id="road-sign" transform="translate(${x},${y + 8})">
    <rect width="${z}" height="${z - 16}" rx="8" fill="none" stroke="${C.textSecondary.$value}" stroke-width="3"/>
    <text x="${z / 2}" y="${z * 0.53}" text-anchor="middle" font-family="Barlow Condensed" font-stretch="condensed" font-weight="700" font-size="34" fill="${C.text.$value}">${sign.number}</text></g>`;
}
function headerSvg(cd) {
  const out = [textEl('kicker', cd.date, SIDE, v(L.kickerBaseline), 'id="kicker-date"')];
  cd.title.slice(0, v(L.titleMaxLines)).forEach((line, i) => out.push(textEl('title', line, SIDE, v(L.titleBaseline) + i * v(L.titleLineHeight), `id="title-line-${i + 1}"`)));
  return out.join('');
}
// Number, unit, road sign and chips. "Elevation unavailable" is the last chip (style 3 floated it on
// the relief, where it could cover the route).
function statsSvg(cd) {
  const nb = v(L.numberBaseline), nw = measure('number', cd.number);
  const out = [textEl('number', cd.number, SIDE, nb, 'id="stat-number"'), textEl('unit', cd.unit, SIDE + nw + v(L.unitGap), nb, 'id="stat-unit"')];
  let x = SIDE; const y = v(L.chipTop), ch = v(L.chipHeight);
  if (cd.sign) { out.push(roadSign(cd.sign, x, y)); x += v(L.roadSignSize) + (cd.sign.kind === 'e-road' ? 16 : 0) + v(L.chipGap); }
  [...cd.chips, ...(cd.notice ? [cd.notice] : [])].forEach((c, i) => {
    const cw = measure('chip', c) + 2 * v(L.chipPaddingX);
    out.push(`<g id="stat-chip-${i + 1}"><rect x="${x}" y="${y}" width="${cw.toFixed(1)}" height="${ch}" rx="${v(L.chipRadius)}" fill="${v(TT.chip.fill)}" stroke="${v(TT.chip.stroke)}" stroke-width="${v(TT.chip.strokeWidth)}"/>`);
    out.push(textEl('chip', c, (x + v(L.chipPaddingX)).toFixed(1), y + ch / 2 + typeStyle('chip').size * 0.36) + '</g>');
    x += cw + v(L.chipGap);
  });
  return out.join('');
}

// ---------- preview-only marks ----------
function stamp([a, b]) { // provenance stamp, never part of the card
  return `<g id="preview-stamp"><rect x="0" y="${H - 96}" width="${W}" height="96" fill="#000" fill-opacity="0.6"/>
  <text x="${W / 2}" y="${H - 56}" text-anchor="middle" font-family="Inter" font-weight="600" font-size="20" letter-spacing="2" fill="#a6aab4">${esc(a)}</text>
  <text x="${W / 2}" y="${H - 24}" text-anchor="middle" font-family="Inter" font-weight="400" font-size="20" fill="#a6aab4">${esc(b)}</text></g>`;
}
function guides() { // safe area (pink) and the route band (blue)
  const sa = TT.safeArea;
  return `<g id="guides" fill="none" stroke-width="2" stroke-dasharray="8 8" opacity="0.85"><rect x="${SIDE}" y="${v(sa.top)}" width="${W - 2 * SIDE}" height="${H - v(sa.top) - v(sa.bottom)}" stroke="#ff4d8d"/>` +
    `<rect x="${SIDE}" y="${v(L.routeBandTop)}" width="${W - 2 * SIDE}" height="${v(L.routeBandBottom) - v(L.routeBandTop)}" stroke="#4fd1ff"/></g>`;
}

// ---------- cards ----------
const CARDS = {
  'i80-terrain': { date: 'Wednesday, November 4, 2026', title: ['Salt Lake City', '→ Sacramento'], number: '649', unit: 'Miles', chips: ['10h 52m', '3 states'], sign: { kind: 'interstate', number: '80' }, summit: { kicker: 'Highest recorded point', value: '7,139 ft', name: 'Donner Summit' }, source: 'real I-80 track; 60-mi gap illustrative', template: 'terrain-card.svg' },
  'brenner-terrain': { date: 'Saturday, August 15, 2026', title: ['Innsbruck → Bolzano'], number: '118', unit: 'km', chips: ['1h 25m', '2 countries'], sign: { kind: 'e-road', number: 'E45' }, summit: { kicker: 'Highest recorded point', value: '1,372 m', name: 'Brenner Pass' }, source: 'A13/A22 via OSRM (© OSM)' },
  'brenner-terrain-long-labels': { relief: 'brenner-terrain', date: 'Samstag, 15. August 2026', title: ['Innsbruck → Bozen', 'Bolzano (Südtirol)'], number: '118', unit: 'km', chips: ['1 Std. 25 Min.', '2 Länder'], sign: { kind: 'e-road', number: 'E45' }, summit: { kicker: 'Höchster aufgezeichneter Punkt', value: '1.372 m', name: 'Brennerpass / Passo del Brennero' }, source: 'long/localized labels (German), safe area and route band', guides: true },
  'split-terrain': { date: 'Saturday, July 18, 2026', title: ['Split → Dubrovnik'], number: '236', unit: 'km', chips: ['3h 25m', '2 countries'], sign: { kind: 'e-road', number: 'E65' }, summit: { kicker: 'Highest recorded point', value: '630 m' }, source: 'sea texture (terrain.water), Adriatic coast road via OSRM (© OSM)' },
  'lithuania-terrain': { date: 'Sunday, November 15, 2026', title: ['Kaunas → Klaipėda'], number: '210', unit: 'km', chips: ['2h 19m', '4 regions'], sign: { kind: 'e-road', number: 'E85' }, summit: { kicker: 'Highest recorded point', value: '152 m' }, source: 'flat land (terrain.flatLand), A1/E85 via OSRM (© OSM)' },
  'nullarbor-flat': { date: 'Monday, March 2, 2026', title: ['Norseman → Ceduna'], number: '1,197', unit: 'km', chips: ['12h 40m', '2 states'], sign: { kind: 'generic', number: 'A1' }, summit: { kicker: 'Highest recorded point', value: '254 m' }, source: 'flat landscape, Eyre Hwy via OSRM (© OSM)' },
  'i80-altitude-unavailable': { date: 'Wednesday, November 4, 2026', title: ['Salt Lake City', '→ Sacramento'], number: '649', unit: 'Miles', chips: ['10h 52m', '3 states'], sign: { kind: 'interstate', number: '80' }, flat: true, notice: 'Elevation unavailable', source: 'no usable altitude: flat land, no summit' },
  'i80-hide-route': { hidden: true, places: ['Salt Lake City', 'Sacramento'], date: 'Wednesday, November 4, 2026', title: ['Salt Lake City', '→ Sacramento'], number: '649', unit: 'Miles', chips: ['10h 52m', '3 states', '7,139 ft high'], sign: { kind: 'interstate', number: '80' }, source: 'hide route: framed on city centres, no route', template: 'terrain-card-hide-route.svg' },
};

const want = process.argv.slice(2);
function card(name) {
  const cd = CARDS[name], key = cd.relief ?? name, build = new URL(`Tools/design/build/${key}.relief`, ROOT).pathname;
  if (!want.includes('--reuse') || !existsSync(build + '.json'))
    execFileSync('python3', [new URL('Tools/design/terrain_relief.py', ROOT).pathname, key, ...(cd.flat ? ['--flat'] : []), ...(cd.hidden ? ['--places'] : [])], { stdio: 'inherit' });
  const rel = JSON.parse(readFileSync(build + '.json'));
  const head = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">`;
  const relief = `<image id="relief" x="0" y="0" width="${W}" height="${H}" href="data:image/png;base64,${readFileSync(build + '.png').toString('base64')}"/>`;
  // Layer order (bottom to top): background, relief, scrims, ribbon or places, summit, type.
  const layers = [`<rect id="background" width="${W}" height="${H}" fill="${BG}"/>`, `<defs>${textShadowDef()}</defs>`, '%RELIEF%', scrimSvg(),
    cd.hidden ? placesSvg(rel.pts, cd.places) : ribbonSvg(rel.pts) + endpointsSvg(rel.pts),
    cd.summit && !cd.flat && !cd.hidden ? summitSvg(rel.pts, cd.summit) : '',
    `<g id="type"${SHADE}>${headerSvg(cd)}${statsSvg(cd)}</g>`].join('\n');
  const info = cd.hidden ? `place centres only · ${Math.round(rel.gwKm)}×${Math.round(rel.gdKm)} km` : cd.flat ? 'no relief' : `k=${rel.k.toFixed(1)}× · ${Math.round(rel.gwKm)}×${Math.round(rel.gdKm)} km`;
  const svg = head + layers.replace('%RELIEF%', relief) + (cd.guides ? guides() : '') +
    stamp([`STYLE PREVIEW · ELEVATION: TERRARIUM z${rel.zoom} (ADR 0006) · COLOUR: NATURAL EARTH`, `${cd.source} · ${info}`]) + '</svg>';
  const { png, width, height } = renderSvg(svg);
  writeFileSync(new URL(`${name}.png`, OUT), png);
  if (cd.template) { // editable template: the relief is a slot the app paints; text is live placeholder text
    const slot = `<rect id="relief-slot" width="${W}" height="${H}" fill="#2a2d36"><title>Relief: the app paints the core's draw list here, full bleed</title></rect>`;
    writeFileSync(new URL(cd.template, CARD_DIR), head + `<title>RoadPrint Terrain card, style 5${cd.hidden ? ', hide route' : ''}: layer order and slots. Text is placeholder text the app fills</title>` + layers.replace('%RELIEF%', slot) + guides() + '</svg>\n');
  }
  console.log(`${name}.png ${width}×${height}  z${rel.zoom} ${info}`);
}

const names = want.filter(n => !n.startsWith('--'));
for (const n of names.length ? names : Object.keys(CARDS)) card(n);
