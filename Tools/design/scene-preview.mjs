#!/usr/bin/env node
// Draw a core MapScene verbatim; never fit routes or reposition labels here.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const tokens = JSON.parse(readFileSync(new URL('../../Design/tokens.json', import.meta.url), 'utf8'));
const esc = text => String(text).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const value = token => token.$value;
const path = points => points.length ? 'M' + points.map(p => `${p.x},${p.y}`).join('L') : '';
export const layers = ['landFill','regionBorders','countryBorders','routeGlow','route','areaCircles','summit','labels'];

export function sceneSVG(scene, theme = 'night') {
  if (!['night','day'].includes(theme)) throw new Error('theme must be night or day');
  if (JSON.stringify(scene.drawOrder) !== JSON.stringify(layers)) throw new Error('Unsupported scene draw order');
  const color = name => value((theme === 'day' ? tokens.colorDay : tokens.color)[name]);
  const draw = name => tokens.theme.draw[name].$value[theme];
  const stroke = name => value(tokens.stroke[name]);
  const opacity = name => value(tokens.opacity[name]);
  const recorded = scene.routes.filter(r => r.kind === 'recorded');
  const line = (route, width, ink, extra = '') => `<path d="${path(route.points)}" fill="none" stroke="${ink}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round" ${extra}/>`;
  const text = (content, box, style, ink) => {
    const type = value(tokens.type[style]);
    return `<text x="${box.x + box.width / 2}" y="${box.y + box.height / 2}" dominant-baseline="central" text-anchor="middle" font-family="${esc(type.family)}" font-size="${type.size}" font-weight="${type.weight}" letter-spacing="${type.tracking}" fill="${ink}" textLength="${box.width}" lengthAdjust="spacingAndGlyphs">${esc(content)}</text>`;
  };
  const parts = {
    landFill: `<rect width="${scene.width}" height="${scene.height}" fill="${color('background')}"/>` + scene.outlines.filter(o => o.kind === 'country').map(o => `<path d="${o.rings.map(r => path(r) + 'Z').join('')}" fill="${color('land')}" fill-rule="evenodd"/>`).join(''),
    regionBorders: scene.outlines.filter(o => o.kind === 'region').flatMap(o => o.rings.map(r => `<path d="${path(r)}" fill="none" stroke="${color('border')}" stroke-width="0.7"/>`)).join(''),
    countryBorders: scene.outlines.filter(o => o.kind === 'country').flatMap(o => o.rings.map(r => `<path d="${path(r)}" fill="none" stroke="${color('border')}" stroke-width="1.2"/>`)).join(''),
    routeGlow: recorded.map(r => draw('routeGlow')
      ? line(r, stroke('routeGlow'), color('route'), `opacity="${opacity('routeGlow')}" filter="url(#glow)"`)
      : line(r, stroke('route') + draw('routeEdgeExtra'), color('routeEdge'))).join(''),
    route: scene.routes.map(r => line(r, stroke('route'), color('route'), r.kind === 'gap' ? 'stroke-dasharray="2 5"' : '')).join(''),
    areaCircles: [scene.startArea,scene.endArea].filter(Boolean).map(a => `<circle cx="${a.center.x}" cy="${a.center.y}" r="${a.radius}" fill="${color('route')}" fill-opacity="${draw('areaFillOpacity')}" stroke="${color(theme === 'night' ? 'route' : 'routeEdge')}" stroke-width="${stroke('areaCircle')}" stroke-dasharray="4 4"/>`).join(''),
    summit: scene.summit ? `<path d="M${scene.summit.position.x},${scene.summit.position.y - 4}l4,8h-8Z" fill="${color('route')}"/>` : '',
    labels: scene.regionLabels.map(l => `<g opacity="${opacity('regionLabel')}">${text(l.text,l.bounds,'regionLabel',color('text'))}</g>`).join('')
      + [scene.startArea?.label,scene.endArea?.label].filter(Boolean).map(l => text(l.text,l.bounds,'mapLabel',color('textSecondary'))).join('')
      + (scene.summit?.labelBounds ? text(new Intl.NumberFormat('en-US', {maximumFractionDigits:0}).format(scene.summit.altitudeMeters) + ' m', scene.summit.labelBounds, 'mapLabel',color('text')) : ''),
  };
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${scene.width}" height="${scene.height}" viewBox="0 0 ${scene.width} ${scene.height}"><defs><filter id="glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="6"/></filter><clipPath id="viewport"><rect width="${scene.width}" height="${scene.height}"/></clipPath></defs><g clip-path="url(#viewport)">${scene.drawOrder.map(l => `<g data-layer="${l}">${parts[l]}</g>`).join('')}</g></svg>`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const input = args[0], out = args[1] ?? dirname(input ?? '.');
  const theme = args[2] ?? 'night';
  if (!input) throw new Error('usage: node scene-preview.mjs scene.json [output-directory] [night|day]');
  const scene = JSON.parse(readFileSync(input,'utf8'));
  const svg = sceneSVG(scene,theme);
  const { renderSvg } = await import('./render.mjs');
  mkdirSync(out,{recursive:true});
  const name = basename(input,'.json') + '-' + theme;
  writeFileSync(join(out,name + '.svg'),svg);
  writeFileSync(join(out,name + '@2x.png'), renderSvg(svg,scene.width * 2).png);
  console.log(join(out,name + '@2x.png'));
}
