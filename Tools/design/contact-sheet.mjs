// Contact sheet of the Terrain previews (3×2 at 1/3 scale) for quick review on a phone.
import { readFileSync, writeFileSync } from 'node:fs';
import { renderSvg } from './render.mjs';
const dir = new URL('../../Design/cards/terrain/previews/', import.meta.url);
const names = ['i80-terrain', 'brenner-terrain', 'brenner-terrain-long-labels', 'nullarbor-flat', 'i80-altitude-unavailable', 'i80-hide-route'];
const w = 360, h = 640, gap = 24, lab = 44;
const W = 3 * w + 4 * gap, H = 2 * (h + lab) + 3 * gap;
let svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}"><rect width="${W}" height="${H}" fill="#0b0c10"/>`;
names.forEach((n, i) => {
  const x = gap + (i % 3) * (w + gap), y = gap + Math.floor(i / 3) * (h + lab + gap);
  const b64 = readFileSync(new URL(n + '.png', dir)).toString('base64');
  svg += `<image x="${x}" y="${y}" width="${w}" height="${h}" href="data:image/png;base64,${b64}"/>`;
  svg += `<text x="${x + w / 2}" y="${y + h + 30}" text-anchor="middle" font-family="Inter" font-weight="600" font-size="20" fill="#f0efec">${n}</text>`;
});
svg += '</svg>';
writeFileSync(new URL('contact-sheet.png', dir), renderSvg(svg).png);
console.log('contact-sheet.png', W, H);
