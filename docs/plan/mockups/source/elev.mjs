import fs from 'fs';
const R = JSON.parse(fs.readFileSync('routes.json'));
const c = R['SLC-SAC'].coords;
const near = c.filter(([x,y])=>Math.abs(x+120.33)<0.1 && Math.abs(y-39.32)<0.1).length;
console.log('points near Donner Summit:', near);
// sample 100 points evenly by distance
const hav=(a,b)=>{const r=Math.PI/180,dl=(b[1]-a[1])*r,dn=(b[0]-a[0])*r;const h=Math.sin(dl/2)**2+Math.cos(a[1]*r)*Math.cos(b[1]*r)*Math.sin(dn/2)**2;return 3958.8*2*Math.asin(Math.sqrt(h));};
let cum=[0];for(let i=1;i<c.length;i++)cum.push(cum[i-1]+hav(c[i-1],c[i]));
const total=cum.at(-1), N=100, samples=[];let j=0;
for(let k=0;k<N;k++){const d=total*k/(N-1);while(j<c.length-1&&cum[j]<d)j++;samples.push({d,lon:c[j][0],lat:c[j][1]});}
const url=`https://api.open-meteo.com/v1/elevation?latitude=${samples.map(s=>s.lat.toFixed(4)).join(',')}&longitude=${samples.map(s=>s.lon.toFixed(4)).join(',')}`;
const r=await fetch(url); const j2=await r.json();
if(!j2.elevation){console.log('elev fail',JSON.stringify(j2).slice(0,200));process.exit();}
samples.forEach((s,i)=>s.ft=j2.elevation[i]*3.28084);
fs.writeFileSync('elev.json',JSON.stringify(samples));
const mx=samples.reduce((a,b)=>b.ft>a.ft?b:a);
console.log('total mi',total.toFixed(0),'max ft',mx.ft.toFixed(0),'at',mx.lat.toFixed(3),mx.lon.toFixed(3),'mile',mx.d.toFixed(0));
