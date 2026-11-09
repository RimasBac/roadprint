#!/usr/bin/env node
// Render Design/ SVGs to PNG previews with resvg (no browser needed).
// Usage: node render.mjs file.svg [more.svg] [--width 1080] [--out dir]
//   Writes <name>.png (or <name>@<width>.png when --width is given) next to the SVG or into --out.
import { Resvg } from '@resvg/resvg-js';
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const fontDir = join(dirname(fileURLToPath(import.meta.url)), 'fonts');

export function fontOptions() {
  const fontFiles = existsSync(fontDir) ? readdirSync(fontDir).filter(f => f.endsWith('.ttf')).map(f => join(fontDir, f)) : [];
  if (!fontFiles.length) console.warn('render: no fonts in Tools/design/fonts, run `npm run fonts` first');
  return { fontFiles, loadSystemFonts: false, defaultFontFamily: 'Inter' };
}

/** Render an SVG string. Returns { png: Buffer, width, height, pixels: RGBA Buffer }. */
export function renderSvg(svg, width) {
  const r = new Resvg(svg, {
    font: fontOptions(),
    fitTo: width ? { mode: 'width', value: width } : { mode: 'original' },
    shapeRendering: 2, textRendering: 1, imageRendering: 0,
  });
  const img = r.render();
  return { png: img.asPng(), width: img.width, height: img.height, pixels: img.pixels };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  let width, out;
  const files = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--width') width = Number(args[++i]);
    else if (args[i] === '--out') out = args[++i];
    else files.push(args[i]);
  }
  if (!files.length) { console.error('usage: render.mjs file.svg [...] [--width N] [--out dir]'); process.exit(1); }
  for (const f of files) {
    const { png, width: w, height: h } = renderSvg(readFileSync(f, 'utf8'), width);
    const dir = out ?? dirname(f);
    mkdirSync(dir, { recursive: true });
    const name = basename(f, '.svg') + (width ? `@${width}` : '') + '.png';
    writeFileSync(join(dir, name), png);
    console.log(`${join(dir, name)}  ${w}×${h}`);
  }
}
