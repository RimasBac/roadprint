// Keep exceptions narrow: exact repository path + trimmed source line + written reason.
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { relative, join } from 'node:path';
const root = fileURLToPath(new URL('../../', import.meta.url));
const allow = JSON.parse(readFileSync(new URL('./literal-allowlist.json', import.meta.url)));
if (allow.some(e => !e.path || !e.line || !e.reason?.trim())) throw new Error('Every literal exception needs path, line and reason');
const used = new Set();
const patterns = [/#(?:[a-f0-9]{8}|[a-f0-9]{6}|[a-f0-9]{3})\b/i, /Color\s*\(\s*red\s*:/, /\.font\s*\(\s*\.system\s*\(\s*size\s*:/, /cornerRadius\s*:\s*\d/];
let failed = false;
function scan(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) { scan(path); continue; }
    if (!path.endsWith('.swift') || path.endsWith('.generated.swift')) continue;
    const repoPath = relative(root, path);
    const source = readFileSync(path, 'utf8');
    // Normalise whitespace, including line breaks, so splitting an initializer cannot bypass CI.
    const checks = [...patterns];
    if (!repoPath.startsWith('App/Design/')) checks.push(/colorScheme\s*==/, /\.preferredColorScheme\s*\(/);
    for (const pattern of checks) {
      const regex = new RegExp(pattern.source, pattern.flags + 'g');
      for (const match of source.matchAll(regex)) {
        const lineNo = source.slice(0, match.index).split('\n').length;
        const line = source.split('\n')[lineNo - 1].trim();
        const exception = allow.findIndex(e => e.path === repoPath && e.line === line);
        if (exception >= 0) { used.add(exception); continue; }
        console.error(`${repoPath}:${lineNo}: stray design literal: ${line}`);
        failed = true;
      }
    }
  }
}
scan(join(root, 'App'));
allow.forEach((e, i) => { if (!used.has(i)) { console.error(`Unused literal exception: ${e.path}: ${e.line}`); failed=true; } });
if (failed) process.exitCode=1;
else console.log('App design literal check passed');
