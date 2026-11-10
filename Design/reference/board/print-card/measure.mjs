// Measures text widths with the same renderer and fonts as the previews. Usage: node Design/reference/board/print-card/measure.mjs (after npm ci in Tools/design)
import { Resvg } from "../../../../Tools/design/node_modules/@resvg/resvg-js/index.js";
import { fontOptions } from "../../../../Tools/design/render.mjs";
const items = [["UTAH",96,"Barlow Condensed",700,1.5],["CALIFORNIA",96,"Barlow Condensed",700,1.5],["649",360,"Barlow Condensed",700,-2],["MILES",84,"Barlow Condensed",700,3],["10h 52m",66,"Barlow Condensed",600,0.5],["7,139 ft",66,"Barlow Condensed",600,0.5],["ROADPRINT",27,"Inter",700,11]];
for (const [s,size,fam,w,tr] of items) {
  const st = fam.startsWith("Barlow") ? " font-stretch=\"condensed\"" : "";
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="3000" height="800"><text x="100" y="500" font-family="${fam}" font-weight="${w}"${st} font-size="${size}" letter-spacing="${tr}">${s}</text></svg>`;
  const b = new Resvg(svg, { font: fontOptions() }).getBBox();
  console.log(s, size, "x", (b.x-100).toFixed(1), "w", b.width.toFixed(1), "top", (b.y-500).toFixed(1), "h", b.height.toFixed(1));
}
