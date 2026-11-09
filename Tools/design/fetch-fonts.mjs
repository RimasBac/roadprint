// Download the plan §5.1 fonts (SIL OFL) as full static TTFs for preview rendering.
// Source: Google Fonts CSS API (a plain user agent gets un-subsetted TTFs, so → and umlauts work).
// Fonts are not committed; the iOS app bundles its own copies.
import { mkdirSync, existsSync, writeFileSync } from 'node:fs';
const dir = new URL('./fonts/', import.meta.url);
mkdirSync(dir, { recursive: true });
const css = await (await fetch('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Barlow+Condensed:wght@500;600;700')).text();
for (const block of css.split('}')) {
  const fam = block.match(/font-family:\s*'([^']+)'/)?.[1];
  const w = block.match(/font-weight:\s*(\d+)/)?.[1];
  const url = block.match(/url\((https:[^)]+\.ttf)\)/)?.[1];
  if (!fam || !w || !url) continue;
  const out = new URL(`${fam.replace(/\s+/g, '')}-${w}.ttf`, dir);
  if (existsSync(out)) continue;
  writeFileSync(out, Buffer.from(await (await fetch(url)).arrayBuffer()));
  console.log('fetched', out.pathname.split('/').pop());
}
