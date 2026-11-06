import fs from 'fs';
const C = {
 SLC:[-111.89,40.76], SAC:[-121.49,38.58], CHI:[-87.63,41.88], DAL:[-96.80,32.78], LA:[-118.24,34.05],
 ONT:[-117.65,34.06], PHX:[-112.07,33.45], ELP:[-106.49,31.76], SAT:[-98.49,29.42], HOU:[-95.37,29.76],
 ATL:[-84.39,33.75], JAX:[-81.66,30.33], MEM:[-90.05,35.15], NSH:[-86.78,36.16], KNX:[-83.92,35.96],
 COL:[-82.99,39.96], NYC:[-74.17,40.73], MSP:[-93.27,44.98], SEA:[-122.33,47.61], POR:[-122.68,45.52],
 DEN:[-104.99,39.74], KC:[-94.58,39.10], OKC:[-97.52,35.47], ABQ:[-106.65,35.08], LRD:[-99.51,27.53],
 BAL:[-76.61,39.29], CLT:[-80.84,35.23], IND:[-86.16,39.77], STL:[-90.20,38.63], RNO:[-119.81,39.53],
 BOI:[-116.20,43.62], OMA:[-95.94,41.26], FLG:[-111.65,35.20], BAK:[-119.02,35.37]
};
// lanes: [from,to, timesDrivenAllTime, inLast30Days]
const lanes = [
 ['SLC','SAC',14,2],['SAC','POR',6,1],['POR','SEA',6,0],['CHI','DAL',9,1],['DAL','OKC',8,1],['OKC','ABQ',11,2],
 ['ABQ','FLG',11,2],['FLG','BAK',7,1],['BAK','SAC',5,1],['ONT','PHX',9,0],['PHX','ELP',6,0],['ELP','SAT',5,0],
 ['SAT','HOU',4,0],['HOU','ATL',3,0],['ATL','JAX',3,0],['DAL','MEM',7,0],['MEM','NSH',6,0],['NSH','KNX',4,0],
 ['CHI','COL',5,0],['COL','NYC',4,0],['CHI','MSP',5,0],['MSP','SEA',2,0],['SLC','DEN',8,1],['DEN','KC',6,1],
 ['KC','STL',5,0],['STL','IND',5,0],['IND','CHI',6,1],['LRD','SAT',3,0],['SAT','DAL',4,0],['BAL','CLT',2,0],
 ['CLT','ATL',3,0],['SLC','BOI',3,0],['BOI','POR',3,0],['OMA','DEN',4,0],['CHI','OMA',4,0],['RNO','SLC',2,0]
];
const out = {};
const sleep = ms => new Promise(r=>setTimeout(r,ms));
for (const [a,b,n,m] of lanes) {
  const url = `https://router.project-osrm.org/route/v1/driving/${C[a].join(',')};${C[b].join(',')}?overview=full&geometries=geojson`;
  const r = await fetch(url); const j = await r.json();
  if (!j.routes) { console.log('fail',a,b,j.code); continue; }
  out[`${a}-${b}`] = {coords:j.routes[0].geometry.coordinates, miles:j.routes[0].distance/1609.34, secs:j.routes[0].duration, all:n, recent:m};
  console.log(a,b,Math.round(j.routes[0].distance/1609.34),'mi', j.routes[0].geometry.coordinates.length,'pts');
  await sleep(1100);
}
fs.writeFileSync('routes.json', JSON.stringify(out));
