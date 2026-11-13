#!/usr/bin/env node
// Fails when App/**/*.swift uses a privacy-sensitive API whose Info.plist key is missing in
// project.yml (targets.RoadPrint.info.properties). Build 4 crashed on Start Trip because
// CMAltimeter was used without NSMotionUsageDescription; the simulator can't catch that.
//
//   node Tools/ci/check-privacy-keys.mjs [project.yml] [App dir]
//
// No dependencies. One plain line per missing key: "<file>: <symbol> needs <key> in project.yml".

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/** `anyOf`: at least one of these keys must exist. */
export const RULES = [
  { symbols: /\b(CLLocationManager|import CoreLocation)\b/, anyOf: ['NSLocationWhenInUseUsageDescription'] },
  { symbols: /\ballowsBackgroundLocationUpdates\b/, background: 'location' },
  { symbols: /\b(CMAltimeter|CMMotionActivityManager|CMPedometer|CMSensorRecorder)\b/, anyOf: ['NSMotionUsageDescription'] },
  { symbols: /\b(PHPhotoLibrary|UIImageWriteToSavedPhotosAlbum)\b/, anyOf: ['NSPhotoLibraryAddUsageDescription', 'NSPhotoLibraryUsageDescription'] },
  { symbols: /\b(PHAsset|PHAssetCollection|PHFetchResult)\b/, anyOf: ['NSPhotoLibraryUsageDescription'] },
  { symbols: /\b(AVCaptureDevice|AVCaptureSession)\b/, anyOf: ['NSCameraUsageDescription'] },
  { symbols: /\b(CNContactStore|import Contacts)\b/, anyOf: ['NSContactsUsageDescription'] },
  // Known and needing no key: UNUserNotificationCenter (permission is requested at runtime).
];

/** Reads info.properties of the RoadPrint target without a YAML library: keys and list values. */
export function readProperties(yml, target = 'RoadPrint') {
  const lines = yml.split('\n');
  const indentOf = (l) => l.length - l.trimStart().length;
  const t = lines.findIndex((l) => l.trim() === `${target}:` && indentOf(l) === 2);
  if (t < 0) throw new Error(`target ${target} not found in project.yml`);
  let p = -1;
  for (let i = t + 1; i < lines.length; i++) {
    if (lines[i].trim() && indentOf(lines[i]) <= 2) break;
    if (lines[i].trim() === 'properties:') { p = i; break; }
  }
  if (p < 0) throw new Error(`${target}.info.properties not found in project.yml`);
  const base = indentOf(lines[p]);
  const props = {};
  let listKey = null;
  for (let i = p + 1; i < lines.length; i++) {
    const l = lines[i];
    if (!l.trim() || l.trim().startsWith('#')) continue;
    if (indentOf(l) <= base) break;
    const item = l.trim().match(/^- (.*)$/);
    if (item && listKey) { props[listKey].push(item[1].trim()); continue; }
    const kv = l.trim().match(/^([A-Za-z0-9_]+):\s*(.*)$/);
    if (!kv) continue;
    const [, k, v] = kv;
    if (v === '') { props[k] = []; listKey = k; }
    else if (v.startsWith('[')) { props[k] = v.slice(1, v.lastIndexOf(']')).split(',').map((s) => s.trim()).filter(Boolean); listKey = null; }
    else { props[k] = v; listKey = null; }
  }
  return props;
}

function stripComments(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' ')).replace(/\/\/.*$/gm, '');
}

/** Returns one message per missing key. `files` is [{ path, source }]. */
export function check(props, files) {
  const problems = [];
  for (const { path, source } of files) {
    const code = stripComments(source);
    for (const rule of RULES) {
      const m = code.match(rule.symbols);
      if (!m) continue;
      if (rule.anyOf && !rule.anyOf.some((k) => props[k] !== undefined && props[k] !== '')) {
        problems.push(`${path}: ${m[0]} needs ${rule.anyOf.join(' or ')} in project.yml`);
      }
      if (rule.background) {
        const modes = Array.isArray(props.UIBackgroundModes) ? props.UIBackgroundModes : [];
        if (!modes.includes(rule.background)) {
          problems.push(`${path}: ${m[0]} needs UIBackgroundModes: [${rule.background}] in project.yml`);
        }
      }
    }
  }
  return problems;
}

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((n) => {
    const p = join(dir, n);
    return statSync(p).isDirectory() ? swiftFiles(p) : p.endsWith('.swift') ? [p] : [];
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
  const yml = process.argv[2] ?? join(root, 'project.yml');
  const appDir = process.argv[3] ?? join(root, 'App');
  const files = swiftFiles(appDir).map((path) => ({ path, source: readFileSync(path, 'utf8') }));
  const problems = check(readProperties(readFileSync(yml, 'utf8')), files.map((f) => ({ ...f, path: f.path.replace(root + '/', '') })));
  for (const p of problems) console.error(p);
  if (problems.length) process.exit(1);
  console.log(`privacy keys ok (${files.length} Swift files checked)`);
}
