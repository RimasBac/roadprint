// Rebuild with npm ci --prefix Tools/projections && node Tools/projections/generate.mjs.
import proj4 from 'proj4';
import {writeFileSync} from 'node:fs';
const R = 6371008.8, rad = Math.PI / 180;
const definitions = [
  {name: 'local', lat: 40, lon: -115, def: '+proj=laea +lat_0=40 +lon_0=-115',
   points: [[-115,40],[-111.89,40.76],[-121.49,38.58],[-110.2,42.3],[-120.7,35.1],[245,40]]},
  {name: 'albers', def: '+proj=aea +lat_1=29.5 +lat_2=45.5 +lat_0=23 +lon_0=-96',
   points: [[-96,23],[-74.006,40.7128],[-118.244,34.0522],[-122.33,47.61],[-80.19,25.76],[-100.3,39.8]]},
  {name: 'europe', lat: 52, lon: 10, def: '+proj=laea +lat_0=52 +lon_0=10',
   points: [[10,52],[23.9,54.9],[10.99,45.44],[-9.14,38.72],[24.94,60.17],[-0.12,51.51]]},
  {name: 'robinson', lon: 170, def: '+proj=robin +lon_0=170',
   points: [[170,0],[-171.8,-13.8],[178,-17.8],[-122.4,37.8],[139.7,35.7],[20,71.3],[40,-89.9]]}
];
const X = [1,.9986,.9954,.99,.9822,.973,.96,.9427,.9216,.8962,.8679,.835,.7986,.7597,.7186,.6732,.6213,.5722,.5322];
const Y = [0,.062,.124,.186,.248,.31,.372,.434,.4958,.5571,.6176,.6769,.7346,.7903,.8435,.8936,.9394,.9761,1];
const normalize = lon => { const r = lon % 360; return r < -180 ? r+360 : r >= 180 ? r-360 : r; };
function golden(d, lon, lat) {
  if (d.name !== 'robinson') return proj4('+proj=longlat +R='+R, d.def+' +R='+R+' +x_0=0 +y_0=0 +units=m', [lon,lat]);
  const row = Math.abs(lat)/5, i = Math.min(17,Math.floor(row)), t = row-i;
  return [.8487*R*normalize(normalize(lon)-d.lon)*rad*(X[i]+t*(X[i+1]-X[i])),
    1.3523*R*(Y[i]+t*(Y[i+1]-Y[i]))*(lat<0?-1:1)];
}
const reference = [], gold = [];
for (const d of definitions) for (const [lon,lat] of d.points) {
  const [x,y] = proj4('+proj=longlat +R='+R, d.def+' +R='+R+' +x_0=0 +y_0=0 +units=m', [lon,lat]);
  if (![x,y].every(Number.isFinite)) throw new Error(`Invalid reference: ${d.name}`);
  reference.push({projection:d.name,lat,lon,x,y});
  const g = golden(d,lon,lat);
  if (!g.every(Number.isFinite)) throw new Error(`Invalid golden: ${d.name}`);
  gold.push({projection:d.name,lat,lon,x:g[0].toFixed(6),y:g[1].toFixed(6)});
}
const root = new URL('../../RoadPrintCore/Tests/RoadPrintCoreTests/Fixtures/', import.meta.url);
writeFileSync(new URL('projection-reference.json',root),JSON.stringify(reference,null,2)+'\n');
writeFileSync(new URL('projection-golden.json',root),JSON.stringify(gold,null,2)+'\n');
console.log(`Wrote ${reference.length} reference and golden points (proj4 2.22.0).`);
