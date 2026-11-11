// RoadPrint's app design system. No npm dependencies; run from any directory.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export const sourceURL = new URL('../../Design/tokens.json', import.meta.url);
export const outputURL = new URL('../../App/Design/Tokens.generated.swift', import.meta.url);
const sorted = object => Object.entries(object).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
const knownTypes = new Set(['color', 'fontFamily', 'string', 'dimension', 'number', 'duration', 'typography', 'boolean', 'shadow', 'strokeStyle']);
const fail = message => { throw new Error(message); };
const swift = value => JSON.stringify(value);
export function flatten(group, prefix = '', inherited) {
  return sorted(group).flatMap(([key, node]) => {
    if (key.startsWith('$')) return [];
    const path = prefix ? `${prefix}.${key}` : key;
    if (!node || typeof node !== 'object') fail(`Invalid token ${path}`);
    const type = node.$type ?? inherited;
    if (type && !knownTypes.has(type)) fail(`Unknown token type ${type} at ${path}`);
    if ('$value' in node) return [[path, { type, value: node.$value }]];
    return flatten(node, path, type);
  });
}
export function assetOutputs(tokens) {
  const { night, day } = resolveDesign(tokens, () => {});
  return ['Background', 'Ink'].map(name => {
    const key = name === 'Background' ? 'background' : 'text';
    const color = (palette, dark = false) => ({
      idiom: 'universal',
      ...(dark ? { appearances: [{ appearance: 'luminosity', value: 'dark' }] } : {}),
      color: { 'color-space': 'srgb', components: {
        red: '0x' + palette[key].slice(1,3).toUpperCase(),
        green: '0x' + palette[key].slice(3,5).toUpperCase(),
        blue: '0x' + palette[key].slice(5,7).toUpperCase(), alpha: '1.000'
      } }
    });
    return [new URL(`../../App/Assets.xcassets/${name}.colorset/Contents.json`, import.meta.url),
      JSON.stringify({ colors: [color(day),color(night,true)], info: { author: 'xcode', version: 1 } }, null, 2) + '\n'];
  });
}
function resolveDesign(tokens, log = console.log) {
  // Terrain is not emitted (no app consumer yet), but its references and types are validated.
  const all = Object.fromEntries(flatten(Object.fromEntries(sorted(tokens).filter(([k]) => !k.startsWith('$') && k !== 'version'))));
  function resolveToken(path, seen = []) {
    if (!all[path]) fail(`Unresolved token ${path}`);
    if (seen.includes(path)) fail(`Cyclic reference ${[...seen, path].join(' -> ')}`);
    return resolveValue(all[path].value, [...seen, path]);
  }
  function resolveValue(value, seen) {
    if (typeof value === 'string') {
      const match = value.match(/^\{([^}]+)\}$/);
      return match ? resolveToken(match[1], seen) : value;
    }
    if (Array.isArray(value)) return value.map(v => resolveValue(v, seen));
    if (value && typeof value === 'object') return Object.fromEntries(sorted(value).map(([k,v]) => [k, resolveValue(v, seen)]));
    return value;
  }
  for (const [path, token] of sorted(all)) {
    resolveToken(path);
    if (!token.type && !path.startsWith('terrain.type.')) fail(`Missing token type at ${path}`);
    if (['number','duration','dimension'].includes(token.type)) {
      const values = path.startsWith('theme.draw.') ? Object.values(token.value) : [resolveToken(path)];
      if (values.some(v => typeof v !== 'number' || !Number.isFinite(v) || v < 0)) fail(`Invalid number ${path}`);
    }
  }
  for (const [path, token] of sorted(all).filter(([p]) => p.startsWith('theme.draw.'))) {
    if (!token.value || Object.keys(token.value).sort().join(',') !== 'day,night') fail(`Missing theme draw pair ${path}`);
    if (token.type === 'boolean' && Object.values(token.value).some(v => typeof v !== 'boolean')) fail(`Invalid boolean ${path}`);
  }
  const value = path => resolveToken(path);
  const group = name => sorted(all).filter(([path]) => path.startsWith(`${name}.`));
  const colors = name => Object.fromEntries(group(name).map(([path]) => [path.slice(name.length+1).replace('.', ''), value(path)]));
  const night = colors('color'), day = colors('colorDay');
  for (const key of Object.keys(night)) if (!(key in day)) fail(`Missing day color ${key}`);
  function rgb(hex) {
    if (!/^#[0-9a-f]{6}$/i.test(hex)) fail(`Invalid sRGB hex ${hex}`);
    return [1,3,5].map(i => parseInt(hex.slice(i,i+2),16)/255);
  }
  function luminance(hex) { return rgb(hex).map(c => c <= 0.04045 ? c/12.92 : ((c+0.055)/1.055)**2.4).reduce((s,c,i) => s+c*[0.2126,0.7152,0.0722][i],0); }
  for (const [theme,palette] of [['night',night],['day',day]]) {
    Object.values(palette).forEach(rgb);
    const pairs = ['text','textSecondary','accentText'].flatMap(fg => ['background','card','land'].map(bg => [fg,bg]));
    pairs.push(['buttonPrimaryLabel','buttonPrimary']);
    for (const [fg,bg] of pairs) {
      const a=luminance(palette[fg]), b=luminance(palette[bg]);
      const ratio=(Math.max(a,b)+0.05)/(Math.min(a,b)+0.05);
      log(`${theme} ${fg}/${bg}: ${ratio.toFixed(2)}:1`);
      if (ratio < 4.5) fail(`Contrast below 4.5:1: ${theme} ${fg}/${bg}`);
    }
  }
  return { value, group, night, day, rgb };
}
export function generate(tokens, log = console.log) {
  const { value, group, night, day, rgb } = resolveDesign(tokens, log);
  const lines = ['// Generated by Tools/design/gen-tokens.mjs. DO NOT EDIT.', '// Source: Design/tokens.json', 'import SwiftUI', 'import UIKit', '', 'extension Color {', '    enum RP {'];
  const uiColor = hex => `UIColor(red: ${rgb(hex)[0]}, green: ${rgb(hex)[1]}, blue: ${rgb(hex)[2]}, alpha: 1)`;
  for (const key of [...new Set([...Object.keys(night), ...Object.keys(day)])].sort()) lines.push(`        static let ${key} = Color(uiColor: UIColor { traits in`, `            traits.userInterfaceStyle == .dark ? ${uiColor(night[key] ?? night.route)} : ${uiColor(day[key])}`, '        })');
  for (const [theme,palette] of [['Night',night],['Day',day]]) {
    lines.push(`        enum ${theme} {`);
    for (const [key,hex] of sorted(palette)) lines.push(`            static let ${key} = Color(uiColor: ${uiColor(hex)})`);
    lines.push('        }');
  }
  lines.push('    }','}', '');
  for (const [name,enumName,type] of [['space','RPSpace','CGFloat'],['radius','RPRadius','CGFloat'],['size','RPSize','CGFloat'],['stroke','RPStroke','CGFloat'],['opacity','RPOpacity','Double'],['button','RPButton','Double']]) {
    lines.push(`enum ${enumName} {`);
    for (const [path,token] of group(name)) {
      const key=path.split('.').at(-1);
      if (path === 'radius.sheet') {
        if (token.value !== 'system') fail('radius.sheet must use system default');
        lines.push('    // sheet: use the system sheet radius.');
      } else if (path === 'size.hairline') {
        if (token.value !== '1/displayScale') fail('size.hairline must be 1/displayScale');
        lines.push('    static func hairline(displayScale: CGFloat) -> CGFloat { 1 / max(displayScale, 1) }');
      } else lines.push(`    static let ${key}: ${type} = ${value(path)}`);
    }
    lines.push('}', '');
  }
  lines.push('enum RPMotion {');
  for (const [path] of group('motion').filter(([p])=>!p.includes('.spring.'))) {
    const key=path.split('.').at(-1);
    lines.push(`    static let ${key}Duration: Double = ${value(path)}`,`    static let ${key} = Animation.easeInOut(duration: ${key}Duration)`);
  }
  lines.push(`    static let springDampingFraction: Double = ${value('motion.spring.dampingFraction')}`,`    static let springResponse: Double = ${value('motion.spring.response')}`, '    static let spring = Animation.spring(response: springResponse, dampingFraction: springDampingFraction)', '}', '');
  lines.push('enum RPTheme {','    struct Draw {');
  for (const [path,token] of group('theme.draw')) lines.push(`        let ${path.split('.').at(-1)}: ${token.type==='boolean'?'Bool':'CGFloat'}`);
  lines.push('    }','    static func draw(for scheme: ColorScheme) -> Draw {','        switch scheme {');
  for (const theme of ['night','day']) {
    lines.push(`        case .${theme==='night'?'dark':'light'}:`, '            Draw(');
    const entries=group('theme.draw');
    entries.forEach(([path],i)=>lines.push(`                ${path.split('.').at(-1)}: ${value(path)[theme]}${i===entries.length-1?'':','}`));
    lines.push('            )');
  }
  lines.push('        @unknown default: draw(for: .light)', '        }', '    }','}', '');
  const weights={400:'Regular',500:'Medium',600:'SemiBold',700:'Bold'};
  function ps(family,weight) {
    if (!['Inter','Barlow Condensed'].includes(family) || !weights[weight]) fail(`Unsupported font ${family} ${weight}`);
    if (family === 'Barlow Condensed' && ![600,700].includes(weight)) fail(`Unbundled font ${family} ${weight}`);
    return `${family.replaceAll(' ','')}-${weights[weight]}`;
  }
  const textFamily=value('font.text'), numberFamily=value('font.number');
  lines.push('enum RPFont {', `    static let textFamily = ${swift(textFamily)}`, `    static let numberFamily = ${swift(numberFamily)}`, `    static let text = ${swift(ps(textFamily,400))}`, `    static let number = ${swift(ps(numberFamily,700))}`,'    static func textName(weight: Font.Weight) -> String {',`        if weight == .bold { return ${swift(ps(textFamily,700))} }`,`        if weight == .semibold { return ${swift(ps(textFamily,600))} }`,`        if weight == .medium { return ${swift(ps(textFamily,500))} }`,'        return text','    }','}', '', 'extension Font {','    static func rpText(size: CGFloat, weight: Font.Weight = .regular, relativeTo: Font.TextStyle = .body) -> Font {','        .custom(RPFont.textName(weight: weight), size: size, relativeTo: relativeTo)','    }','    static func rpNumber(size: CGFloat, relativeTo: Font.TextStyle = .largeTitle) -> Font {','        .custom(RPFont.number, size: size, relativeTo: relativeTo).monospacedDigit()','    }','}', '', 'enum RPType {');
  const styles=group('type');
  for (const [path] of styles) {
    const key=path.split('.').at(-1), t=value(path), name=ps(t.family,t.weight);
    if (!Number.isFinite(t.size) || t.size <= 0 || !Number.isFinite(t.tracking) || !['upper','none'].includes(t.case)) fail(`Invalid typography ${path}`);
    if (!['title2','subheadline','largeTitle','footnote','caption','body','headline','caption2','fixed'].includes(t.relativeTo)) fail(`Unknown text style ${t.relativeTo}`);
    const custom=t.relativeTo==='fixed'?`.custom(${swift(name)}, fixedSize: ${t.size})`:`.custom(${swift(name)}, size: ${t.size}, relativeTo: .${t.relativeTo})`;
    lines.push(`    static let ${key}: Font = ${custom}${t.family===numberFamily?'.monospacedDigit()':''}`,`    static let ${key}Tracking: CGFloat = ${t.tracking}`,`    static let ${key}Case: Text.Case? = ${t.case==='upper'?'.uppercase':'nil'}`);
  }
  lines.push('    struct Sample: Sendable {','        let name: String','        let font: Font','        let postScriptName: String','        let size: CGFloat','        let tracking: CGFloat','        let textCase: Text.Case?','    }','    static let samples: [Sample] = [');
  for (const [path] of styles) {
    const key=path.split('.').at(-1),t=value(path);
    lines.push(`        Sample(name: ${swift(key)}, font: ${key}, postScriptName: ${swift(ps(t.family,t.weight))}, size: ${t.size}, tracking: ${key}Tracking, textCase: ${key}Case),`);
  }
  lines.push('    ]','}', '');
  return lines.join('\n');
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const tokens=JSON.parse(readFileSync(sourceURL,'utf8'));
  const output=generate(tokens);
  if (output !== generate(tokens,()=>{})) fail('Generator is not deterministic');
  for (const [url, content] of [[outputURL, output], ...assetOutputs(tokens)]) {
    if (process.argv.includes('--check')) {
      if (readFileSync(url,'utf8') !== content) fail(`Stale generated file ${url.pathname}: run node Tools/design/gen-tokens.mjs`);
    } else writeFileSync(url,content);
  }
}
