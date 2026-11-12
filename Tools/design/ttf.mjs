// Minimal TrueType reader: glyph outlines (as SVG path data) and advance widths.
// Enough for outlining short labels ("INTERSTATE") and measuring numbers. No kerning, no composites
// beyond simple offsets. Used only by the design preview scripts.
import { readFileSync } from 'node:fs';

export function loadFont(path) {
  const b = readFileSync(path);
  const u16 = o => b.readUInt16BE(o), i16 = o => b.readInt16BE(o), u32 = o => b.readUInt32BE(o);
  const tables = {};
  const n = u16(4);
  for (let i = 0; i < n; i++) {
    const r = 12 + i * 16;
    tables[b.toString('latin1', r, r + 4)] = u32(r + 8);
  }
  const head = tables.head, unitsPerEm = u16(head + 18), locFormat = i16(head + 50);
  const numGlyphs = u16(tables.maxp + 4);
  const numHMetrics = u16(tables.hhea + 34);
  const os2 = tables['OS/2'];
  const capHeight = os2 && u16(os2) >= 2 ? i16(os2 + 88) : 0.7 * unitsPerEm;

  // cmap format 4 (BMP)
  const cmap = tables.cmap;
  let sub = 0;
  for (let i = 0; i < u16(cmap + 2); i++) {
    const r = cmap + 4 + i * 8;
    const off = cmap + u32(r + 4);
    if (u16(off) === 4 && (u16(r) === 3 || u16(r) === 0)) { sub = off; break; }
  }
  const segX2 = u16(sub + 6);
  const ends = sub + 14, starts = ends + segX2 + 2, deltas = starts + segX2, ranges = deltas + segX2;
  function glyphId(cp) {
    for (let s = 0; s < segX2; s += 2) {
      if (cp > u16(ends + s)) continue;
      if (cp < u16(starts + s)) return 0;
      const ro = u16(ranges + s);
      if (!ro) return (cp + i16(deltas + s)) & 0xffff;
      const g = u16(ranges + s + ro + (cp - u16(starts + s)) * 2);
      return g ? (g + i16(deltas + s)) & 0xffff : 0;
    }
    return 0;
  }
  const advance = g => u16(tables.hmtx + 4 * Math.min(g, numHMetrics - 1));
  const loca = g => locFormat ? u32(tables.loca + 4 * g) : u16(tables.loca + 2 * g) * 2;

  // Returns contours: arrays of {x, y, on}
  function contours(g) {
    const start = tables.glyf + loca(g), end = tables.glyf + loca(g + 1);
    if (end <= start) return [];
    const nc = i16(start);
    if (nc < 0) { // composite: offsets only
      let p = start + 10, out = [], flags;
      do {
        flags = u16(p); const gi = u16(p + 2); p += 4;
        let dx, dy;
        if (flags & 1) { dx = i16(p); dy = i16(p + 2); p += 4; } else { dx = b.readInt8(p); dy = b.readInt8(p + 1); p += 2; }
        if (flags & 8) p += 2; else if (flags & 0x40) p += 4; else if (flags & 0x80) p += 8;
        for (const c of contours(gi)) out.push(c.map(pt => ({ ...pt, x: pt.x + dx, y: pt.y + dy })));
      } while (flags & 0x20);
      return out;
    }
    const endPts = []; for (let i = 0; i < nc; i++) endPts.push(u16(start + 10 + 2 * i));
    const np = endPts[nc - 1] + 1;
    let p = start + 10 + 2 * nc; p += 2 + u16(p);
    const fl = [];
    while (fl.length < np) { const f = b[p++]; fl.push(f); if (f & 8) { let r = b[p++]; while (r--) fl.push(f); } }
    const xs = [], ys = [];
    let v = 0;
    for (const f of fl) { if (f & 2) { v += (f & 16) ? b[p] : -b[p]; p++; } else if (!(f & 16)) { v += i16(p); p += 2; } xs.push(v); }
    v = 0;
    for (const f of fl) { if (f & 4) { v += (f & 32) ? b[p] : -b[p]; p++; } else if (!(f & 32)) { v += i16(p); p += 2; } ys.push(v); }
    const out = []; let s = 0;
    for (const e of endPts) { const c = []; for (let i = s; i <= e; i++) c.push({ x: xs[i], y: ys[i], on: !!(fl[i] & 1) }); out.push(c); s = e + 1; }
    return out;
  }

  /** Width of a string in font units (sum of advances, plus tracking per gap in font units). */
  function measure(str, tracking = 0) {
    let w = 0; for (const ch of str) w += advance(glyphId(ch.codePointAt(0)));
    return w + tracking * Math.max(0, [...str].length - 1);
  }

  /** SVG path data for str, with the baseline at y, starting at x, at size. Relative commands with
   *  `precision` decimals keep outlined labels small. */
  function pathData(str, x, y, size, tracking = 0, precision = 2) {
    const k = size / unitsPerEm, m10 = 10 ** precision, R = v => Math.round(v * m10) / m10;
    const f = v => { const s = (Math.round(v * m10) / m10).toString(); return s.replace(/^(-?)0\./, '$1.'); };
    let d = '', pen = x, cx = 0, cy = 0;
    const num = (a, b) => { const s = f(a) + (b < 0 ? '' : ' ') + f(b); return s; };
    const rel = (px, py) => { const X = R(px), Y = R(py), o = num(X - cx, Y - cy); cx = X; cy = Y; return o; };
    for (const ch of str) {
      const g = glyphId(ch.codePointAt(0));
      for (const c of contours(g)) {
        const P = c.map(pt => ({ x: pen + pt.x * k, y: y - pt.y * k, on: pt.on }));
        let i0 = P.findIndex(q => q.on), first;
        if (i0 < 0) { first = { x: (P[0].x + P[1].x) / 2, y: (P[0].y + P[1].y) / 2 }; i0 = 0; } else first = P[i0];
        d += (d ? 'm' : 'M') + (d ? rel(first.x, first.y) : (() => { cx = R(first.x); cy = R(first.y); return num(cx, cy); })());
        const m = P.length;
        for (let j = 1; j <= m; j++) {
          const q = P[(i0 + j) % m];
          if (q.on) { d += 'l' + rel(q.x, q.y); continue; }
          const nx = P[(i0 + j + 1) % m];
          const end = nx.on ? nx : { x: (q.x + nx.x) / 2, y: (q.y + nx.y) / 2 };
          const sx = cx, sy = cy;
          d += 'q' + num(R(q.x) - sx, R(q.y) - sy) + ' ' + rel(end.x, end.y);
          if (nx.on) j++;
        }
        d += 'z';
        // after z the current point returns to the contour start
        cx = R(first.x); cy = R(first.y);
      }
      pen += advance(g) * k + tracking * k;
    }
    return d.replace(/l0 0/g, '');
  }
  return { unitsPerEm, capHeight, measure, pathData, glyphId };
}
