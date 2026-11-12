import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sceneSVG, layers } from './scene-preview.mjs';
const scene = {
  width:390,height:460,drawOrder:layers,
  routes:[{kind:'recorded',points:[{x:28,y:36},{x:200,y:200}]},{kind:'gap',points:[{x:200,y:200},{x:362,y:424}]}],
  outlines:[{kind:'country',rings:[[{x:0,y:0},{x:390,y:0},{x:390,y:460},{x:0,y:460}]]}],
  regionLabels:[{text:'NV',bounds:{x:150,y:70,width:18,height:13}}],
  startArea:{center:{x:28,y:36},radius:8,label:{text:'A<&"',bounds:{x:60,y:40,width:40,height:12}}},
  summit:{position:{x:220,y:220},altitudeMeters:2206,labelBounds:{x:230,y:230,width:100,height:28}},
};
test('draws ordered layers, supplied coordinates, privacy circles and dotted gap',()=>{
  const svg = sceneSVG(scene);
  let previous = -1;
  for (const layer of layers) {
    const at = svg.indexOf(`data-layer="${layer}"`); assert.ok(at>previous); previous=at;
  }
  assert.ok(svg.includes('M28,36L200,200'));
  assert.ok(svg.includes('stroke-dasharray="2 5"'));
  assert.ok(svg.includes('cx="28" cy="36" r="8"'));
  assert.ok(svg.includes('A&lt;&amp;&quot;'));
  assert.ok(svg.includes('#ffb547'));
  assert.ok(!svg.includes('undefined'));
});
test('day uses paper palette and casing instead of route glow',()=>{
  const svg=sceneSVG(scene,'day');
  assert.ok(svg.includes('#f5f3ee'));
  assert.ok(svg.includes('#9c4e00'));
  assert.ok(!svg.includes('filter="url(#glow)"'));
  assert.ok(!svg.includes('undefined'));
});
test('rejects unsupported layer order and theme',()=>{
  assert.throws(()=>sceneSVG({...scene,drawOrder:[...layers].reverse()}),/draw order/);
  assert.throws(()=>sceneSVG(scene,'other'),/theme/);
});
