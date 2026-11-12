#!/usr/bin/env node
// One I-80 preview beside the original map crop, both at 2 image pixels/point.
import { readFileSync, writeFileSync } from 'node:fs';
import { renderSvg } from './render.mjs';
const [preview, output] = process.argv.slice(2);
if (!preview || !output) throw new Error('usage: scene-comparison.mjs i80-390x460-night@2x.png output.png');
const reference = readFileSync(new URL('../../docs/plan/mockups/1-trip-summary.png',import.meta.url));
const png = readFileSync(preview);
if (png.readUInt32BE(16) !== 780 || png.readUInt32BE(20) !== 920) throw new Error('Expected 390x460 at 2x');
// Coordinates from source/gen.mjs and shoot.cjs: first phone starts at
// (51,127) CSS px, its map at y=97, with 390x300 dimensions; deviceScale=2.
// Keep that 300 pt height; pad it to 460 instead of distorting the reference.
const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="804" height="496" viewBox="0 0 804 496"><rect width="804" height="496" fill="#14161c"/><g font-family="Inter" font-size="12" fill="#f0efec"><text x="16" y="24">Core scene · 390 × 460 pt</text><text x="430" y="24">Mockup 1 map · 390 × 300 pt</text></g><image x="0" y="36" width="390" height="460" href="data:image/png;base64,${png.toString('base64')}"/><svg x="414" y="116" width="390" height="300" viewBox="102 448 780 600"><image width="2600" height="2056" href="data:image/png;base64,${reference.toString('base64')}"/></svg></svg>`;
writeFileSync(output,renderSvg(svg,1608).png);
console.log(output);
