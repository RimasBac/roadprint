#!/usr/bin/env node
// Print card editor concept (movable, removable blocks over the driver's photo): three phone screens.
// Writes Design/cards/print/editor-concept.png. A concept for the board, not an app spec: it uses the real
// generated card (Design/cards/print/print-card.svg, run print-card.mjs first) cut into its four blocks,
// over the public-domain night photo from fixtures/photos.
// Usage: node print-editor-concept.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { renderSvg } from './render.mjs';
const R = f => new URL(f, import.meta.url);
const card = renderSvg(readFileSync(R('../../Design/cards/print/print-card.svg'), 'utf8')).png.toString('base64');
const photo = readFileSync(R('fixtures/photos/night-moab-pd.jpg')).toString('base64');

// Blocks of the full layout (export px): [id, label, top, bottom]
const BLOCKS = { header: ['Title', 222, 442], route: ['Route', 452, 872], elevation: ['Elevation', 884, 1118], stats: ['Distance & stats', 1128, 1594] };

function screen({ title, place, selected, hidden = [], ink = 'Auto', layout = 'Custom', hint, arrow }) {
  const SW = 1080, SH = 2340, k = 0.86, cw = 1080 * k, ch = 1920 * k, cx = (SW - cw) / 2, cy = 196;
  const o = [`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 ${SW} ${SH}" width="${SW}" height="${SH}">`,
    `<rect width="${SW}" height="${SH}" rx="70" fill="#0b0c10"/>`,
    // top bar
    `<text x="64" y="128" font-family="Inter" font-weight="500" font-size="40" fill="#a6aab4">Cancel</text>`,
    `<text x="${SW / 2}" y="128" text-anchor="middle" font-family="Inter" font-weight="700" font-size="42" fill="#f0efec">${title}</text>`,
    `<rect x="${SW - 230}" y="78" width="168" height="72" rx="36" fill="#ffb547"/><text x="${SW - 146}" y="127" text-anchor="middle" font-family="Inter" font-weight="700" font-size="36" fill="#14161c">Share</text>`,
    `<defs><clipPath id="cv"><rect x="${cx}" y="${cy}" width="${cw}" height="${ch}" rx="28"/></clipPath></defs>`,
    `<g clip-path="url(#cv)"><image x="${cx}" y="${cy}" width="${cw}" height="${ch}" preserveAspectRatio="xMaxYMid slice" href="data:image/jpeg;base64,${photo}"/>`];
  // blocks
  for (const [id, [label, t, b]] of Object.entries(BLOCKS)) {
    if (hidden.includes(id)) continue;
    const y = place[id] ?? t, h = b - t;
    o.push(`<defs><clipPath id="c-${id}"><rect x="0" y="${t}" width="1080" height="${h}"/></clipPath></defs>`);
    o.push(`<g transform="translate(${cx} ${cy}) scale(${k}) translate(0 ${y - t})"><image width="1080" height="1920" clip-path="url(#c-${id})" href="data:image/png;base64,${card}"/></g>`);
    if (id === selected) {
      const sy = cy + y * k, sh = h * k;
      o.push(`<rect x="${cx + 40}" y="${sy}" width="${cw - 80}" height="${sh}" rx="22" fill="#ffb547" fill-opacity="0.06" stroke="#ffb547" stroke-width="4" stroke-dasharray="18 12"/>`);
      o.push(`<g transform="translate(${cx + cw - 40} ${sy + sh / 2})"><rect x="-26" y="-60" width="52" height="120" rx="26" fill="#ffb547"/>${[-22, 0, 22].map(d => `<rect x="-12" y="${d - 3}" width="24" height="6" rx="3" fill="#14161c"/>`).join('')}</g>`);
      o.push(`<g transform="translate(${cx + 40} ${sy})"><circle r="30" fill="#14161c" stroke="#ffb547" stroke-width="4"/><path d="M-10 -10 L10 10 M10 -10 L-10 10" stroke="#f0efec" stroke-width="5" stroke-linecap="round"/></g>`);
      if (arrow) o.push(`<g fill="none" stroke="#ffb547" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"><path d="M${cx + cw - 40} ${sy - 30} v-90 m-22 22 l22 -22 l22 22"/><path d="M${cx + cw - 40} ${sy + sh + 30} v90 m-22 -22 l22 22 l22 -22"/></g>`);
    }
  }
  o.push('</g>');
  // bottom panel
  const by = cy + ch + 40;
  const seg = (x, y, label, opts, on) => {
    o.push(`<text x="${x}" y="${y + 46}" font-family="Inter" font-weight="600" font-size="30" letter-spacing="3" fill="#a6aab4">${label}</text>`);
    let px = x + 190;
    for (const op of opts) {
      const w = 40 + op.length * 19;
      o.push(`<rect x="${px}" y="${y}" width="${w}" height="68" rx="34" fill="${op === on ? '#ffb547' : '#1d2029'}" stroke="#30353f" stroke-width="${op === on ? 0 : 2}"/><text x="${px + w / 2}" y="${y + 45}" text-anchor="middle" font-family="Inter" font-weight="600" font-size="30" fill="${op === on ? '#14161c' : '#f0efec'}">${op}</text>`);
      px += w + 14;
    }
  };
  seg(64, by, 'INK', ['Auto', 'Light', 'Dark'], ink);
  seg(64, by + 92, 'LAYOUT', ['Full', 'Sticker', 'Custom'], layout);
  o.push(`<text x="64" y="${by + 230}" font-family="Inter" font-weight="600" font-size="30" letter-spacing="3" fill="#a6aab4">HIDDEN</text>`);
  let hx = 254;
  for (const id of hidden) { const w = 70 + BLOCKS[id][0].length * 19; o.push(`<rect x="${hx}" y="${by + 184}" width="${w}" height="68" rx="34" fill="none" stroke="#a6aab4" stroke-width="2" stroke-dasharray="8 8"/><text x="${hx + 30}" y="${by + 230}" font-family="Inter" font-weight="600" font-size="30" fill="#f0efec">+ ${BLOCKS[id][0]}</text>`); hx += w + 14; }
  if (!hidden.length) o.push(`<text x="254" y="${by + 230}" font-family="Inter" font-weight="500" font-size="30" fill="#5d6470">Nothing hidden</text>`);
  o.push(`<text x="${SW / 2}" y="${SH - 40}" text-anchor="middle" font-family="Inter" font-weight="500" font-size="28" fill="#a6aab4">${hint}</text>`);
  o.push('</svg>');
  return o.join('');
}

const screens = [
  screen({ title: 'Edit card', place: {}, selected: null, layout: 'Full', hint: 'Start: the card as designed, on your photo' }),
  screen({ title: 'Edit card', place: { route: 452 }, selected: 'route', arrow: true, hint: 'Hold a block, then slide it up or down. It snaps clear of the others' }),
  screen({ title: 'Edit card', place: { header: 222, route: 700, stats: 1128 }, selected: 'route', hidden: ['elevation'], hint: 'Tap × to hide a block. Bring it back from Hidden' }),
];
// Board: three phone screens side by side
const PW = 1080, PH = 2340, gap = 80, head = 220;
const W = 3 * PW + 4 * gap, H = head + PH + gap;
const caps = ['1 · Your photo, the card on top', '2 · Slide the route down', '3 · Hide the elevation strip'];
const board = [`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}"><rect width="${W}" height="${H}" fill="#14161c"/>`,
  `<text x="${gap}" y="110" font-family="Inter" font-weight="700" font-size="76" fill="#f0efec">Print card editor · movable blocks (concept)</text>`,
  `<text x="${gap}" y="180" font-family="Inter" font-weight="500" font-size="40" fill="#a6aab4">Four blocks: title, route, elevation, distance &amp; stats. Vertical moves only, snapping inside the Story safe area. The wordmark stays on free cards.</text>`];
screens.forEach((s, i) => {
  const x = gap + i * (PW + gap);
  board.push(`<image x="${x}" y="${head}" width="${PW}" height="${PH}" href="data:image/png;base64,${renderSvg(s).png.toString('base64')}"/>`);
  board.push(`<text x="${x + PW / 2}" y="${head + PH + 60}" text-anchor="middle" font-family="Inter" font-weight="700" font-size="44" fill="#ffb547">${caps[i]}</text>`);
});
board.push('</svg>');
writeFileSync(R('../../Design/cards/print/editor-concept.png'), renderSvg(board.join(''), 2400).png);
console.log('Design/cards/print/editor-concept.png');
