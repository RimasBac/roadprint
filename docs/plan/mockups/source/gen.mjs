import fs from 'fs';
import {geoPath, geoAlbers, geoMercator, geoContains} from 'd3-geo';
import {feature, mesh} from 'topojson-client';
const FONT = p => `file://${process.cwd()}/node_modules/@fontsource/${p}`;
const fontCSS = `
@font-face{font-family:Inter;font-weight:400;src:url(${FONT('inter/files/inter-latin-400-normal.woff2')})}
@font-face{font-family:Inter;font-weight:600;src:url(${FONT('inter/files/inter-latin-600-normal.woff2')})}
@font-face{font-family:Inter;font-weight:700;src:url(${FONT('inter/files/inter-latin-700-normal.woff2')})}
@font-face{font-family:Inter;font-weight:800;src:url(${FONT('inter/files/inter-latin-800-normal.woff2')})}
@font-face{font-family:Barlow;font-weight:600;src:url(${FONT('barlow-condensed/files/barlow-condensed-latin-600-normal.woff2')})}
@font-face{font-family:Barlow;font-weight:700;src:url(${FONT('barlow-condensed/files/barlow-condensed-latin-700-normal.woff2')})}
@font-face{font-family:Barlow;font-weight:800;src:url(${FONT('barlow-condensed/files/barlow-condensed-latin-800-normal.woff2')})}`;
const us = JSON.parse(fs.readFileSync('node_modules/us-atlas/states-10m.json'));
const R = JSON.parse(fs.readFileSync('routes.json'));
const ELEV = JSON.parse(fs.readFileSync('elev.json'));
const lower48 = {type:'FeatureCollection', features: feature(us, us.objects.states).features.filter(f=>!['02','15','72','60','66','69','78'].includes(f.id))};
const borders = mesh(us, {type:'GeometryCollection', geometries: us.objects.states.geometries.filter(g=>!['02','15','72','60','66','69','78'].includes(g.id))}, (a,b)=>a!==b);
const outline = mesh(us, {type:'GeometryCollection', geometries: us.objects.states.geometries.filter(g=>!['02','15','72','60','66','69','78'].includes(g.id))}, (a,b)=>a===b);
const hav=(a,b)=>{const r=Math.PI/180,dl=(b[1]-a[1])*r,dn=(b[0]-a[0])*r;const h=Math.sin(dl/2)**2+Math.cos(a[1]*r)*Math.cos(b[1]*r)*Math.sin(dn/2)**2;return 3958.8*2*Math.asin(Math.sqrt(h));};
const thin = (c,k=3)=>c.filter((_,i)=>i%k===0||i===c.length-1);

// ---------- TRIP ----------
const trip = R['SLC-SAC'].coords;
let cum=[0]; for(let i=1;i<trip.length;i++) cum.push(cum[i-1]+hav(trip[i-1],trip[i]));
const TOTAL = cum.at(-1);
const kept = trip.filter((_,i)=>cum[i]>5 && cum[i]<TOTAL-5);   // privacy trim 5 mi each end
const tripGeo = {type:'LineString', coordinates: thin(kept,3)};
const summit = [-120.319, 39.342];
const shield = (n,s=1)=>`<svg width="${34*s}" height="${36*s}" viewBox="0 0 34 36"><defs><clipPath id="sh${n}${s}"><path d="M2 1H32Q34 9 32 15Q29 29 17 35Q5 29 2 15Q0 9 2 1Z"/></clipPath></defs><g clip-path="url(#sh${n}${s})"><rect width="34" height="36" fill="#1f4fa3"/><rect width="34" height="10" fill="#c8202f"/></g><path d="M2 1H32Q34 9 32 15Q29 29 17 35Q5 29 2 15Q0 9 2 1Z" fill="none" stroke="#fff" stroke-width="1.6"/><text x="17" y="8" font-family="Inter" font-weight="700" font-size="4.6" fill="#fff" text-anchor="middle">INTERSTATE</text><text x="17" y="26" font-family="Barlow" font-weight="800" font-size="15" fill="#fff" text-anchor="middle">${n}</text></svg>`;
const mountain = (c='#ffb547',s=1)=>`<svg width="${44*s}" height="${48*s}" viewBox="0 0 44 48"><path d="M22 2L41 13V35L22 46L3 35V13Z" fill="none" stroke="${c}" stroke-width="2.2"/><path d="M10 33L18 21L22 26L27 18L34 33Z" fill="${c}"/><path d="M27 18L24.5 22L27 21L29.5 22Z" fill="#fff" opacity=".9"/></svg>`;

function mapSVG({w,h,pad=24,geo,theme,routeW=3.2,glow=true,showStates=true,labels=true,markers=true,summitLabel=true}){
  const proj = geoMercator().fitExtent([[pad,pad],[w-pad,h-pad]], geo);
  const p = geoPath(proj);
  const st = theme;
  const [sx,sy] = proj(kept[0]), [ex,ey] = proj(kept.at(-1)), [mx,my]=proj(summit);
  const lab = (lon,lat,t)=>{const [x,y]=proj([lon,lat]);return `<text x="${x}" y="${y}" fill="${st.stateLabel}" font-family="Inter" font-weight="700" font-size="12" letter-spacing="1.5" text-anchor="middle">${t}</text>`};
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" style="display:block">
   <defs><filter id="glow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="5"/></filter></defs>
   ${showStates?`<path d="${p(lower48)}" fill="${st.land}"/><path d="${p(borders)}" fill="none" stroke="${st.border}" stroke-width="1"/>`:''}
   ${labels?lab(-113.0,40.15,'UT')+lab(-116.9,39.75,'NV')+lab(-121.25,40.45,'CA'):''}
   ${glow?`<path d="${p(tripGeo)}" fill="none" stroke="${st.route}" stroke-width="${routeW*4}" opacity=".35" filter="url(#glow)" stroke-linecap="round" stroke-linejoin="round"/>`:''}
   ${st.casing?`<path d="${p(tripGeo)}" fill="none" stroke="${st.casing}" stroke-width="${routeW+3}" stroke-linecap="round" stroke-linejoin="round"/>`:''}
   <path d="${p(tripGeo)}" fill="none" stroke="${st.route}" stroke-width="${routeW}" stroke-linecap="round" stroke-linejoin="round"/>
   ${markers?`
   <circle cx="${sx}" cy="${sy}" r="15" fill="${st.route}" opacity=".14"/><circle cx="${sx}" cy="${sy}" r="15" fill="none" stroke="${st.route}" stroke-dasharray="2 3" opacity=".8"/><circle cx="${sx}" cy="${sy}" r="4" fill="${st.bg}" stroke="${st.route}" stroke-width="2"/>
   <circle cx="${ex}" cy="${ey}" r="15" fill="${st.route}" opacity=".14"/><circle cx="${ex}" cy="${ey}" r="15" fill="none" stroke="${st.route}" stroke-dasharray="2 3" opacity=".8"/><circle cx="${ex}" cy="${ey}" r="4" fill="${st.route}"/>
   <text x="${sx-4}" y="${sy-22}" fill="${st.text2}" font-family="Inter" font-size="10.5" text-anchor="end">Salt Lake City area</text>
   <text x="${ex+4}" y="${ey+30}" fill="${st.text2}" font-family="Inter" font-size="10.5" text-anchor="start">Sacramento area</text>`:''}
   ${summitLabel?`<path d="M${mx} ${my+6}l-6 11h12z" fill="${st.text1}"/><text x="${mx+10}" y="${my+22}" fill="${st.text1}" font-family="Inter" font-weight="700" font-size="11">Donner Summit</text><text x="${mx+10}" y="${my+35}" fill="${st.text2}" font-family="Inter" font-size="10.5">7,139 ft</text>`:''}
  </svg>`;
}
function elevSVG({w,h,color,grid,text,fill=true,axes=true,annot=true}){
  const ml=axes?34:0, mb=axes?18:0, mt=annot?22:4;
  const X=d=>ml+(w-ml-4)*d/TOTAL, Y=ft=>mt+(h-mt-mb)*(1-ft/8000);
  const pts=ELEV.map(s=>[X(s.d*TOTAL/ELEV.at(-1).d),Y(Math.max(0,s.ft))]);
  const line='M'+pts.map(p=>p.map(v=>v.toFixed(1)).join(',')).join('L');
  const area=line+`L${pts.at(-1)[0]},${Y(0)}L${pts[0][0]},${Y(0)}Z`;
  const top=ELEV.reduce((a,b)=>b.ft>a.ft?b:a); const tx=X(top.d*TOTAL/ELEV.at(-1).d), ty=Y(top.ft);
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" style="display:block">
   <defs><linearGradient id="eg${color.slice(1)}" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="${color}" stop-opacity=".55"/><stop offset="1" stop-color="${color}" stop-opacity=".04"/></linearGradient></defs>
   ${axes?[0,4000,8000].map(v=>`<line x1="${ml}" x2="${w-4}" y1="${Y(v)}" y2="${Y(v)}" stroke="${grid}" stroke-width="1"/><text x="${ml-6}" y="${Y(v)+3.5}" fill="${text}" font-family="Inter" font-size="9.5" text-anchor="end">${v?v/1000+'k':'0'}</text>`).join(''):''}
   ${axes?[0,200,400,649].map(v=>`<text x="${X(v)}" y="${h-4}" fill="${text}" font-family="Inter" font-size="9.5" text-anchor="${v===0?'start':v===649?'end':'middle'}">${v} mi</text>`).join(''):''}
   ${fill?`<path d="${area}" fill="url(#eg${color.slice(1)})"/>`:''}
   <path d="${line}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round"/>
   ${annot?`<circle cx="${tx}" cy="${ty}" r="4" fill="${color}" stroke="${grid==='none'?'#000':'#14161c'}" stroke-width="2"/><text x="${tx-8}" y="${ty-9}" fill="${text}" font-family="Inter" font-weight="600" font-size="10" text-anchor="end">Donner Summit · 7,139 ft · mile ${Math.round(top.d*TOTAL/ELEV.at(-1).d)}</text>`:''}
  </svg>`;
}
const DARK={bg:'#14161c',land:'#1d2029',border:'#30353f',route:'#ffb547',text1:'#f0efec',text2:'#a6aab4',stateLabel:'#4a505c'};
const statusBar=(c='#f0efec')=>`<div style="display:flex;justify-content:space-between;padding:14px 26px 0;font:600 15px Inter;color:${c}"><span>9:41</span><svg width="62" height="12" viewBox="0 0 62 12"><g fill="${c}"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0.5" width="3" height="11.5" rx="1"/><text x="22" y="11" font-family="Inter" font-weight="700" font-size="11">5G</text><rect x="38.5" y="1" width="21" height="10" rx="3" fill="none" stroke="${c}" opacity=".5"/><rect x="40.5" y="3" width="14" height="6" rx="1.5"/><rect x="60.5" y="4" width="1.5" height="4" rx=".7"/></g></svg></div>`;
const phone=(inner,bg='#14161c')=>`<div class="phone" style="background:${bg}">${inner}</div>`;
const page=(title,sub,body)=>`<!doctype html><html><head><meta charset="utf-8"><style>${fontCSS}
*{box-sizing:border-box;margin:0}body{background:#0a0b0e;font-family:Inter;color:#f0efec;padding:36px 40px 44px}
h1{font:800 26px Inter;letter-spacing:-.3px}h1+p{color:#a6aab4;font:400 14px Inter;margin:6px 0 26px}
.row{display:flex;gap:34px;align-items:flex-start}.col{display:flex;flex-direction:column;gap:12px;align-items:center}
.cap{font:600 14px Inter;color:#f0efec}.cap small{display:block;font:400 12.5px Inter;color:#a6aab4;margin-top:3px;text-align:center}
.phone{width:390px;height:844px;border-radius:46px;overflow:hidden;position:relative;box-shadow:0 0 0 10px #22252c,0 0 0 11px #3a3e47,0 30px 60px rgba(0,0,0,.5);margin:11px}
.chip{display:inline-flex;align-items:center;gap:6px;padding:7px 12px;border-radius:999px;font:600 12.5px Inter;border:1px solid #30353f;color:#f0efec;background:#1d2029;white-space:nowrap}
.card{background:#1b1e26;border-radius:18px;padding:14px 16px}
.stat b{display:block;font:800 30px Barlow;letter-spacing:.3px;color:#f0efec}.stat span{font:400 11.5px Inter;color:#a6aab4}
.btn{display:flex;align-items:center;justify-content:center;height:50px;border-radius:14px;font:700 15.5px Inter}
</style></head><body><h1>${title}</h1><p>${sub}</p>${body}</body></html>`;

// ---------- PAGE 1: trip summary ----------
const tripScreen = phone(`${statusBar()}
 <div style="padding:14px 20px 0;display:flex;justify-content:space-between;align-items:center">
  <div><div style="font:800 22px Inter">Trip complete</div><div style="font:400 13px Inter;color:#a6aab4;margin-top:3px">Wed, Nov 4 · Utah → Nevada → California</div></div>
  <div style="width:34px;height:34px;border-radius:50%;background:#1d2029;display:flex;align-items:center;justify-content:center;color:#a6aab4;font:700 16px Inter">✕</div></div>
 <div style="margin-top:6px">${mapSVG({w:390,h:300,pad:34,geo:tripGeo,theme:DARK})}</div>
 <div style="display:flex;justify-content:space-between;align-items:center;padding:4px 22px 12px">
  <div class="stat"><b>649</b><span>miles</span></div><div class="stat"><b>10:52</b><span>hours moving</span></div><div class="stat"><b>3</b><span>states</span></div>${shield(80,1.15)}</div>
 <div class="card" style="margin:0 14px"><div style="font:600 12px Inter;color:#a6aab4;margin-bottom:6px">ELEVATION</div>${elevSVG({w:330,h:110,color:'#ffb547',grid:'#2a2e38',text:'#a6aab4'})}</div>
 <div class="card" style="margin:10px 14px 0;display:flex;gap:12px;align-items:center;background:linear-gradient(90deg,#2a2112,#1b1e26)">
  ${mountain()}<div style="flex:1"><div style="font:600 11px Inter;color:#ffb547;letter-spacing:1px">NEW BADGE · LEGENDARY ROAD 7 OF 20</div><div style="font:800 17px Inter;margin-top:2px">Donner Pass conquered</div></div></div>
 <div style="margin:10px 14px 0;display:flex;justify-content:space-between;font:400 12.5px Inter;color:#a6aab4;padding:0 4px"><span>Career: <b style="color:#f0efec">1,284,961 mi</b> (+649)</span><span>715,039 to go</span></div>
 <div style="margin:8px 18px 0;height:6px;border-radius:3px;background:#2a2e38"><div style="width:64.2%;height:6px;border-radius:3px;background:#ffb547"></div></div>
 <div style="display:flex;gap:10px;margin:16px 14px 0"><div class="btn" style="flex:1;background:#ffb547;color:#1a1204">Share trip card</div><div class="btn" style="width:110px;background:#1d2029;color:#f0efec">Done</div></div>
`);
const privacyNote = `<div style="max-width:360px;font:400 13px/1.55 Inter;color:#a6aab4;margin-top:24px">
 <div class="cap" style="margin-bottom:8px">What this screen shows</div>
 <p style="margin-bottom:8px"><b style="color:#f0efec">Real route data:</b> I-80, 649 miles, with elevation sampled along the actual road. Donner Summit comes out at 7,139 ft.</p>
 <p style="margin-bottom:8px"><b style="color:#f0efec">Privacy trim:</b> the first and last 5 miles aren't stored. The dashed circles mark an approximate area, never the exact yard or dock.</p>
 <p style="margin-bottom:8px"><b style="color:#f0efec">Nothing appeared while driving.</b> The badge, stats and career counter show up only after the driver taps End Trip.</p>
 <p><b style="color:#f0efec">Two taps to share:</b> Share trip card → pick a style (next mockup).</p></div>`;
fs.writeFileSync('p1.html', page('After a trip: the summary screen','Salt Lake City area → Sacramento area on I-80, Nov 4. Mockup built from a real route.',`<div class="row">${tripScreen}${privacyNote}</div>`));

// ---------- PAGE 2: share cards ----------
const cardW=330, cardH=586;
const night = `<div style="width:${cardW}px;height:${cardH}px;border-radius:22px;overflow:hidden;background:radial-gradient(120% 80% at 50% 35%,#1f2230,#0c0d12);position:relative">
  <div style="position:absolute;top:22px;left:24px;font:700 11px Inter;letter-spacing:3px;color:#ffb547">ROADPRINT</div>
  <div style="position:absolute;top:44px;left:0">${mapSVG({w:cardW,h:300,pad:26,geo:tripGeo,theme:{...DARK,land:'#191b24',border:'#2b2f3b'},routeW:3.4,summitLabel:true,markers:false})}</div>
  <div style="position:absolute;top:326px;left:24px;right:24px">
   <div style="display:flex;align-items:baseline;gap:8px"><span style="font:800 96px/0.9 Barlow;color:#fff">649</span><span style="font:700 26px Barlow;color:#ffb547;letter-spacing:1px">MILES</span></div>
   <div style="font:600 15px Inter;color:#f0efec;margin-top:8px">Utah → California · Nov 4</div>
   <div style="display:flex;gap:8px;margin-top:14px;align-items:center">${shield(80,.9)}<span class="chip">10h 52m</span><span class="chip">3 states</span></div>
   <div style="display:flex;gap:10px;align-items:center;margin-top:16px">${mountain('#ffb547',.75)}<span style="font:700 14px Inter">Donner Pass conquered</span></div></div>
  <div style="position:absolute;bottom:16px;width:100%;text-align:center;font:600 10.5px Inter;color:#6b7080;letter-spacing:1px">MADE WITH ROADPRINT</div></div>`;
const ATLAS={bg:'#f3ecdd',land:'#ebe2ce',border:'#c9b99a',route:'#c62d2d',casing:'#ffffff',text1:'#2b2620',text2:'#6e6556',stateLabel:'#a89a7e'};
const atlas = `<div style="width:${cardW}px;height:${cardH}px;border-radius:22px;overflow:hidden;background:#f3ecdd;position:relative;color:#2b2620">
  <div style="position:absolute;top:22px;left:24px;right:24px;display:flex;justify-content:space-between;align-items:flex-start">
   <div><div style="font:800 30px/1 Barlow;letter-spacing:.5px">UTAH → CALIFORNIA</div><div style="font:400 12.5px Inter;color:#6e6556;margin-top:5px">Wednesday, November 4, 2026</div></div>${shield(80,1)}</div>
  <div style="position:absolute;top:84px;left:0">${mapSVG({w:cardW,h:290,pad:22,geo:tripGeo,theme:ATLAS,routeW:3,glow:false,markers:false})}</div>
  <div style="position:absolute;top:388px;left:24px;right:24px;border-top:1.5px solid #2b2620;padding-top:12px;display:flex;justify-content:space-between">
   ${[['649','MILES'],['10:52','HOURS'],['3','STATES'],['7,139','FT SUMMIT']].map(([a,b])=>`<div><div style="font:800 28px Barlow">${a}</div><div style="font:700 9.5px Inter;letter-spacing:1.2px;color:#6e6556">${b}</div></div>`).join('')}</div>
  <div style="position:absolute;top:470px;left:18px">${elevSVG({w:294,h:70,color:'#c62d2d',grid:'none',text:'#6e6556',axes:false,annot:false})}</div>
  <div style="position:absolute;bottom:16px;width:100%;text-align:center;font:600 10.5px Inter;color:#a89a7e;letter-spacing:1px">MADE WITH ROADPRINT</div></div>`;
const poster = `<div style="width:${cardW}px;height:${cardH}px;border-radius:22px;overflow:hidden;background:#0d0d0d;position:relative">
  <div style="position:absolute;top:40px;left:0">${mapSVG({w:cardW,h:280,pad:30,geo:tripGeo,theme:{...DARK,route:'#ffffff'},routeW:4,glow:false,showStates:false,labels:false,markers:false,summitLabel:false})}</div>
  <div style="position:absolute;top:330px;left:26px;right:26px">
   <div style="font:800 54px/0.95 Barlow;color:#fff;letter-spacing:.5px">I-80 WEST</div>
   <div style="font:600 13px Inter;color:#9a9a9a;margin-top:10px;letter-spacing:1.5px">649 MI · 3 STATES · 11.04.2026</div></div>
  <div style="position:absolute;bottom:52px;left:0">${elevSVG({w:cardW,h:120,color:'#ffb547',grid:'none',text:'#9a9a9a',axes:false,annot:false})}</div>
  <div style="position:absolute;bottom:138px;right:62px;font:700 12px Inter;color:#ffb547;text-align:right">DONNER SUMMIT<br><span style="color:#fff">7,139 FT</span></div>
  <div style="position:absolute;bottom:16px;width:100%;text-align:center;font:600 10.5px Inter;color:#555;letter-spacing:1px">MADE WITH ROADPRINT</div></div>`;
fs.writeFileSync('p2.html', page('Share card styles (9:16 for TikTok and Instagram Stories)','The same trip in three styles. Free cards carry the watermark; Pro unlocks all styles in high resolution without it.',
 `<div class="row">${[[night,'Night Highway','Glowing route, badge, big number'],[atlas,'Road Atlas','Paper map, interstate shield, stats strip'],[poster,'Poster','Route shape plus elevation; minimal']].map(([c,t,s])=>`<div class="col">${c}<div class="cap" style="text-align:center">${t}<small>${s}</small></div></div>`).join('')}</div>`));

// ---------- PAGE 3: heatmaps ----------
const W=390, H=250;
const nproj = geoAlbers().parallels([29.5,45.5]).rotate([96,0]).fitExtent([[10,10],[W-10,H-10]], lower48);
const np = geoPath(nproj);
const RAMP=['#8a4a12','#c2650f','#f08c1a','#ffb547','#ffe1a0'];
const BINS=[1,3,6,10,15]; // lower bounds
const binOf=v=>{let i=0;for(let k=0;k<BINS.length;k++) if(v>=BINS[k]) i=k; return i;};
function heat(weightKey, filterFn){
  const cell=([x,y])=>`${Math.round(x/0.12)},${Math.round(y/0.12)}`;
  const cnt=new Map();
  for(const r of Object.values(R)){const w=r[weightKey]; if(!w) continue; const s=new Set(r.coords.map(cell)); for(const c of s) cnt.set(c,(cnt.get(c)||0)+w);}
  const segs=[];
  for(const r of Object.values(R)){ if(!r[weightKey]) continue; const c=thin(r.coords,4);
    for(let i=0;i<c.length-1;i+=4){const part=c.slice(i,i+5); const mid=part[Math.floor(part.length/2)]; const v=cnt.get(cell(mid))||r[weightKey];
      const inF = filterFn? filterFn(mid):true; segs.push({part,v,inF});}}
  segs.sort((a,b)=>a.v-b.v);
  return segs.map(s=>{const b=binOf(s.v); const d=np({type:'LineString',coordinates:s.part});
    if(!s.inF) return `<path d="${d}" fill="none" stroke="#3a3f4a" stroke-width="1.2" stroke-linecap="round"/>`;
    return (b>=3?`<path d="${d}" fill="none" stroke="${RAMP[b]}" stroke-width="${6+b}" opacity=".18" stroke-linecap="round" filter="url(#hg)"/>`:'')+
      `<path d="${d}" fill="none" stroke="${RAMP[b]}" stroke-width="${1.3+b*0.55}" stroke-linecap="round" stroke-linejoin="round"/>`;}).join('');
}
const baseMap = (inner,dimStates=null)=>`<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" style="display:block"><defs><filter id="hg"><feGaussianBlur stdDeviation="2.5"/></filter></defs>
  <path d="${np(lower48)}" fill="#1b1e26"/>${dimStates||''}<path d="${np(borders)}" fill="none" stroke="#2a2e38" stroke-width=".8"/><path d="${np(outline)}" fill="none" stroke="#353a45" stroke-width="1"/>${inner}</svg>`;
const legend = (note)=>`<div style="padding:4px 20px 0"><div style="display:flex;justify-content:space-between;font:400 11px Inter;color:#a6aab4;margin-bottom:5px"><span>Times driven</span><span>${note||''}</span></div>
  <div style="display:flex;gap:2px">${RAMP.map(c=>`<div style="flex:1;height:8px;background:${c};border-radius:2px"></div>`).join('')}</div>
  <div style="display:flex;font:400 10.5px Inter;color:#a6aab4;margin-top:4px">${['1–2','3–5','6–9','10–14','15+'].map(t=>`<span style="flex:1;text-align:center">${t}</span>`).join('')}</div></div>`;
// stats
const stateHit=(weightKey,fn)=>{const hit=new Set();for(const r of Object.values(R)){if(!r[weightKey])continue;for(let i=0;i<r.coords.length;i+=60){const pt=r.coords[i];for(const f of lower48.features){if(!hit.has(f.id)&&geoContains(f,pt)){hit.add(f.id);break;}}}}return hit.size;};
const miles=k=>Math.round(Object.values(R).reduce((a,r)=>a+(r[k]||0)*r.miles,0));
const allMi=miles('all'), recMi=miles('recent'), allSt=stateHit('all'), recSt=stateHit('recent');
const CA = lower48.features.find(f=>f.id==='06');
const caMi = Math.round(Object.values(R).reduce((a,r)=>{let m=0;for(let i=1;i<r.coords.length;i+=10){const p=r.coords[i]; if(geoContains(CA,p)) m+=hav(r.coords[i-1>0?i-10:0]||r.coords[0],p);}return a+m*(r.all||0);},0));
const tripsAll=Object.values(R).reduce((a,r)=>a+(r.all||0),0), tripsRec=Object.values(R).reduce((a,r)=>a+(r.recent||0),0);
const caTrips=Object.values(R).reduce((a,r)=>a+(r.coords.some((p,i)=>i%40===0&&geoContains(CA,p))?(r.all||0):0),0);
const header=(t,s)=>`${statusBar()}<div style="padding:14px 20px 8px"><div style="font:800 22px Inter">${t}</div><div style="font:400 13px Inter;color:#a6aab4;margin-top:3px">${s}</div></div>`;
const tabs=(active)=>`<div style="display:flex;gap:4px;margin:4px 20px 10px;background:#1d2029;border-radius:12px;padding:4px">${['Last 30 days','All time'].map(t=>`<div style="flex:1;text-align:center;padding:8px 0;border-radius:9px;font:600 13px Inter;${t===active?'background:#2f3440;color:#fff':'color:#a6aab4'}">${t}${t==='All time'&&active==='Last 30 days'?' 🔒':''}</div>`).join('')}</div>`;
const statRow=(a)=>`<div style="display:flex;justify-content:space-between;padding:14px 22px 6px">${a.map(([v,l])=>`<div class="stat"><b style="font-size:26px">${v}</b><span>${l}</span></div>`).join('')}</div>`;
const free = phone(`${header('My map','Your last 30 days of trips')}${tabs('Last 30 days')}
 <div style="display:flex;gap:6px;padding:0 20px 8px;opacity:.45">${['Year ▾','State ▾','Highway ▾','Badges'].map(c=>`<span class="chip" style="padding:6px 9px;font-size:12px">🔒 ${c}</span>`).join('')}</div>
 ${baseMap(heat('recent'))}${legend()}
 ${statRow([[recMi.toLocaleString(),'miles'],[String(recSt),'states'],[String(tripsRec),'trips']])}
 <div class="card" style="margin:10px 14px 0;background:linear-gradient(135deg,#2a2112,#1b1e26);border:1px solid #4a3a1a">
  <div style="font:800 16px Inter">See every mile you've ever recorded</div>
  <div style="font:400 12.5px/1.5 Inter;color:#c9c5bb;margin-top:4px">All-time heatmap, filters by year, state and highway, and HD cards without the watermark.</div>
  <div class="btn" style="margin-top:12px;height:44px;background:#ffb547;color:#1a1204">Try Pro free for 7 days</div>
  <div style="text-align:center;font:400 11.5px Inter;color:#a6aab4;margin-top:8px">then $39.99/year or $4.99/month</div></div>`);
const pro = phone(`${header('My map','Every recorded trip since Jan 2025')}${tabs('All time')}
 <div style="display:flex;gap:6px;padding:0 20px 8px">${['All years ▾','All states ▾','All roads ▾','Badges'].map(c=>`<span class="chip">${c}</span>`).join('')}</div>
 ${baseMap(heat('all'))}${legend('Hottest: I-80 Salt Lake City → Reno')}
 ${statRow([[Math.round(allMi/1000)+'K','miles'],[String(allSt),'states'],[String(tripsAll),'trips'],['14','roads']])}
 <div class="card" style="margin:6px 14px 0;font:400 12.5px/1.6 Inter;color:#c9c5bb"><div style="font:600 11px Inter;color:#a6aab4;letter-spacing:1px;margin-bottom:4px">TOP LANES</div><div style="display:flex;justify-content:space-between"><span>I-80 · Salt Lake City → Reno</span><b style="color:#f0efec">16×</b></div><div style="display:flex;justify-content:space-between"><span>I-40 · Oklahoma City → Flagstaff</span><b style="color:#f0efec">11×</b></div><div style="display:flex;justify-content:space-between"><span>I-10 · Ontario → Phoenix</span><b style="color:#f0efec">9×</b></div></div><div style="padding:10px 22px;font:400 12px/1.5 Inter;color:#a6aab4">Brighter, thicker lines are lanes you've driven more often. Tap any highway to see how many times, and when.</div>`);
const inCA = p=>geoContains(CA,p);
const caDim = `<path d="${np(CA)}" fill="#262a35"/>`;
const filtered = phone(`${header('My map','Filtered: California · 2026')}${tabs('All time')}
 <div style="display:flex;gap:6px;padding:0 20px 8px"><span class="chip" style="background:#3a2c12;border-color:#ffb547;color:#ffb547">2026 ✕</span><span class="chip" style="background:#3a2c12;border-color:#ffb547;color:#ffb547">California ✕</span><span class="chip">All roads ▾</span></div>
 ${baseMap(heat('all',inCA),caDim)}${legend()}
 ${statRow([[Math.round(caMi/1000)+'K','miles in CA'],['5','highways'],[String(caTrips),'trips'],['2','roads']])}
 <div class="card" style="margin:6px 14px 0;font:400 12.5px/1.6 Inter;color:#c9c5bb"><div style="display:flex;justify-content:space-between"><span>I-80 · Donner Pass</span><b style="color:#f0efec">14×</b></div><div style="display:flex;justify-content:space-between"><span>I-10 · Ontario → Blythe</span><b style="color:#f0efec">9×</b></div><div style="display:flex;justify-content:space-between"><span>CA-58 · Tehachapi Pass</span><b style="color:#f0efec">7×</b></div></div>`);
fs.writeFileSync('p3.html', page('The heatmap: free vs Pro',"Free shows the last 30 days. Pro unlocks the all-time map and filters. Example data: one driver's lanes over about two years, using real routes.",
 `<div class="row">${[[free,'Free · last 30 days','Filters locked; upgrade card'],[pro,'Pro · all time','Every lane; brighter = driven more'],[filtered,'Pro · filtered','2026 + California; rest of the map dimmed']].map(([c,t,s])=>`<div class="col">${c}<div class="cap" style="text-align:center">${t}<small>${s}</small></div></div>`).join('')}</div>`));
console.log({tripsAll,tripsRec,caTrips,allMi,recMi,allSt,recSt,caMi});
