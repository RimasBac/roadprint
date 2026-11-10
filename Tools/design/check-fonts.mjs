// Verify committed bytes and static font metadata without installing font tools.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const dir=new URL('../../App/Resources/Fonts/',import.meta.url);
const manifest=JSON.parse(readFileSync(new URL('manifest.json',dir)));
for (const item of manifest.files) {
  const b=readFileSync(new URL(item.file,dir));
  assert.equal(createHash('sha256').update(b).digest('hex'),item.sha256,item.file);
  const tables={};
  for (let i=0;i<b.readUInt16BE(4);i++) {
    const start=12+i*16;
    tables[b.toString('ascii',start,start+4)]=b.readUInt32BE(start+8);
  }
  assert.ok(!('fvar' in tables),`Variable font: ${item.file}`);
  const start=tables.name, count=b.readUInt16BE(start+2), strings=start+b.readUInt16BE(start+4);
  const names=[];
  for (let i=0;i<count;i++) {
    const p=start+6+i*12, platform=b.readUInt16BE(p), nameID=b.readUInt16BE(p+6);
    if (nameID!==6) continue;
    const length=b.readUInt16BE(p+8), offset=b.readUInt16BE(p+10);
    const bytes=Buffer.from(b.subarray(strings+offset,strings+offset+length));
    names.push(platform===0 || platform===3 ? bytes.swap16().toString('utf16le') : bytes.toString('latin1'));
  }
  assert.deepEqual([...new Set(names)],[item.postScriptName],item.file);
  console.log(`static TTF: ${item.postScriptName} (${item.sha256})`);
}
for (const family of ['Inter','BarlowCondensed']) {
  assert.match(readFileSync(new URL(`${family}/OFL.txt`,dir),'utf8'),/SIL OPEN FONT LICENSE Version 1.1/);
}
