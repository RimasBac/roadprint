// An original soundtrack for the promo, synthesised from its own timeline, so every hit lands on
// the cut. No samples and no third-party music: nothing to license.
//
//   node soundtrack.mjs --props out/props.json --out out/soundtrack.wav
//
// render.mjs calls synth() itself when no --music is given. 120 BPM (the plan's bpm), A minor:
// four-on-the-floor kick, off-beat hats, a ducked eighth-note bass and a soft pluck arpeggio under
// the screens; an impact on each title line and amber wipe, a whoosh into every camera dive, a
// riser into the end title, and a last chord that rings out.
import {writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';

export const RATE = 48_000;
const TARGET_RMS_DB = -15; // about -14 LUFS for this kind of mix
const CEILING = 0.89; // -1 dBFS

// A minor: Am – F – C – G, one chord per bar.
const PROGRESSION = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]];
const hz = (midi) => 440 * 2 ** ((midi - 69) / 12);

/** A seeded noise source, so the same props always give the same file. */
function noise(seed) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return ((s >>> 0) / 4294967296) * 2 - 1; };
}

/** Biquad band-pass (RBJ), for whooshes and hats. */
function bandpass(f, q) {
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  return (x, freq = f) => {
    const w = (2 * Math.PI * freq) / RATE, a = Math.sin(w) / (2 * q), c = Math.cos(w);
    const b0 = a / (1 + a), b2 = -a / (1 + a), a1 = (-2 * c) / (1 + a), a2 = (1 - a) / (1 + a);
    const y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    return y;
  };
}

/**
 * @param props  the composition's props (plan.mjs): shots with start/length/beat in frames
 * @param fps    the video's frame rate
 * @returns Float32Array, mono, RATE Hz
 */
export function synth(props, fps = 60) {
  const seconds = props.frames / fps;
  const out = new Float32Array(Math.ceil((seconds + 1.5) * RATE));
  const at = (frame) => Math.round((frame / fps) * RATE);
  const add = (i, v) => { if (i >= 0 && i < out.length) out[i] += v; };
  const beat = props.shots[0].beat; // frames
  const beatS = beat / fps;
  const rand = noise(0x5eed);

  // Where the music plays: from the first screen to the end title's last beat.
  const firstScreen = props.shots.find((s) => s.kind === 'screen');
  const end = props.shots.at(-1);
  const grooveFrom = firstScreen ? firstScreen.start : end.start;
  const grooveTo = end.start;
  const duck = new Float32Array(out.length).fill(1); // the kick's sidechain on bass and pluck

  // Kick: a sine drop from 140 to 45 Hz on every beat of the groove, and once on the end title's downbeat.
  const kick = (start, gain) => {
    const n = Math.round(0.42 * RATE);
    let phase = 0;
    for (let k = 0; k < n; k++) {
      const t = k / RATE;
      phase += (2 * Math.PI * (45 + 95 * Math.exp(-t * 28))) / RATE;
      add(start + k, gain * Math.sin(phase) * Math.exp(-t * 7.5));
      const d = 1 - 0.75 * Math.exp(-t * 9);
      if (start + k < duck.length) duck[start + k] = Math.min(duck[start + k], d);
    }
  };
  for (let f = grooveFrom; f < grooveTo; f += beat) kick(at(f), 0.9);
  kick(at(end.start), 1.0);

  // Hats: band-passed noise on the off-beats, a little quieter on the first bar.
  const hatFilter = bandpass(8000, 0.9);
  for (let f = grooveFrom + beat / 2; f < grooveTo; f += beat) {
    const start = at(f), n = Math.round(0.05 * RATE);
    const gain = f - grooveFrom < 4 * beat ? 0.12 : 0.2;
    for (let k = 0; k < n; k++) add(start + k, gain * hatFilter(rand()) * Math.exp(-(k / RATE) * 70));
  }

  // Bass and pluck, chord by chord.
  const bar = 4 * beat;
  for (let f = grooveFrom, b = 0; f < grooveTo; f += bar, b++) {
    const chord = PROGRESSION[b % PROGRESSION.length];
    // Bass: the root, two octaves down, on eighths; a soft square through a gentle low-pass.
    for (let e = 0; e < 8 && f + (e * beat) / 2 < grooveTo; e++) {
      const start = at(f + (e * beat) / 2), n = Math.round(beatS * 0.48 * RATE), freq = hz(chord[0] - 24);
      let lp = 0;
      for (let k = 0; k < n; k++) {
        const t = k / RATE;
        const sq = Math.sign(Math.sin(2 * Math.PI * freq * t)) * 0.6 + Math.sin(2 * Math.PI * freq * t) * 0.4;
        lp += 0.08 * (sq - lp);
        const i = start + k;
        add(i, 0.32 * lp * Math.min(1, t * 400) * Math.exp(-t * 3) * (i < duck.length ? duck[i] : 1));
      }
    }
    // Pluck: the triad, an octave up, as a sixteenth-note arpeggio from the second bar on.
    if (b === 0) continue;
    const pattern = [0, 1, 2, 1, 2, 0, 1, 2];
    for (let s = 0; s < 8 && f + (s * beat) / 2 < grooveTo; s++) {
      const start = at(f + (s * beat) / 2), freq = hz(chord[pattern[s]] + 12), n = Math.round(0.4 * RATE);
      for (let k = 0; k < n; k++) {
        const t = k / RATE;
        const v = Math.sin(2 * Math.PI * freq * t) + 0.3 * Math.sin(4 * Math.PI * freq * t);
        const i = start + k;
        add(i, 0.07 * v * Math.exp(-t * 9) * (i < duck.length ? 0.5 + 0.5 * duck[i] : 1));
      }
    }
  }

  // Impact: a low boom with a noise crack.
  const impact = (start, gain) => {
    const n = Math.round(0.9 * RATE), crack = bandpass(2500, 0.7);
    let phase = 0;
    for (let k = 0; k < n; k++) {
      const t = k / RATE;
      phase += (2 * Math.PI * (38 + 60 * Math.exp(-t * 18))) / RATE;
      add(start + k, gain * (0.9 * Math.sin(phase) * Math.exp(-t * 4) + 0.5 * crack(rand()) * Math.exp(-t * 30)));
    }
  };
  // Whoosh: noise through a band-pass sweeping up, swelling into `peak`.
  const whoosh = (peak, length, gain) => {
    const n = Math.round(length * RATE), filter = bandpass(400, 1.2), start = peak - n;
    for (let k = 0; k < n + Math.round(0.15 * RATE); k++) {
      const p = Math.min(1, k / n);
      const env = k < n ? p ** 2 : Math.exp(-((k - n) / RATE) * 25);
      add(start + k, gain * env * filter(rand(), 300 + 4200 * p ** 2));
    }
  };

  for (const shot of props.shots) {
    if (shot.kind === 'title') {
      shot.lines.forEach((_, i) => impact(at(shot.start + Math.round(i * shot.beat) + 2), i === shot.lines.length - 1 ? 0.75 : 0.5));
    }
    if (shot.wipe) { whoosh(at(shot.start), 0.35, 0.35); impact(at(shot.start), 0.6); }
    if (shot.kind === 'screen') {
      for (const zoom of shot.zooms) whoosh(at(shot.start + zoom.at + Math.round(0.35 * fps)), 0.45, 0.22);
    }
  }
  // A riser over the bar before the end title.
  whoosh(at(end.start), 4 * beatS, 0.28);

  // Before the groove: a low A drone swelling under the title, a riser into the first screen, and
  // an impact as the phone comes up, so the opening never drops to silence.
  if (grooveFrom > 0) {
    const n = at(grooveFrom) + Math.round(0.5 * RATE);
    for (let k = 0; k < n; k++) {
      const t = k / RATE, swell = Math.min(1, t / 1.2) * (k > at(grooveFrom) ? Math.exp(-(k - at(grooveFrom)) / RATE * 8) : 1);
      add(k, 0.16 * swell * (Math.sin(2 * Math.PI * hz(33) * t) + 0.5 * Math.sin(2 * Math.PI * hz(45) * t) + 0.25 * Math.sin(2 * Math.PI * hz(52) * t)));
    }
    whoosh(at(grooveFrom), Math.min(2 * beatS, grooveFrom / fps), 0.3);
    impact(at(grooveFrom), 0.55);
  }

  // The last chord, A minor, rings out over the end title.
  for (const note of PROGRESSION[0]) {
    const start = at(end.start), n = out.length - start;
    for (const midi of [note, note + 12]) {
      for (let k = 0; k < n; k++) {
        const t = k / RATE;
        add(start + k, 0.06 * Math.sin(2 * Math.PI * hz(midi) * t) * Math.min(1, t * 50) * Math.exp(-t * 0.55));
      }
    }
  }

  // Level: to the target loudness, then a soft limiter under -1 dBFS; fade the tail.
  let sum = 0;
  for (const v of out) sum += v * v;
  const rms = Math.sqrt(sum / out.length) || 1;
  const gain = 10 ** (TARGET_RMS_DB / 20) / rms;
  const fadeFrom = out.length - Math.round(1.2 * RATE);
  for (let i = 0; i < out.length; i++) {
    const fade = i > fadeFrom ? 1 - (i - fadeFrom) / (out.length - fadeFrom) : 1;
    out[i] = CEILING * Math.tanh((out[i] * gain) / CEILING) * fade;
  }
  return out.subarray(0, Math.ceil(seconds * RATE));
}

/** 16-bit PCM WAV, mono. */
export function wav(samples) {
  const data = Buffer.alloc(samples.length * 2);
  samples.forEach((v, i) => data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), i * 2));
  const head = Buffer.alloc(44);
  head.write('RIFF', 0); head.writeUInt32LE(36 + data.length, 4); head.write('WAVE', 8);
  head.write('fmt ', 12); head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20); head.writeUInt16LE(1, 22);
  head.writeUInt32LE(RATE, 24); head.writeUInt32LE(RATE * 2, 28); head.writeUInt16LE(2, 32); head.writeUInt16LE(16, 34);
  head.write('data', 36); head.writeUInt32LE(data.length, 40);
  return Buffer.concat([head, data]);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const {values: args} = parseArgs({options: {props: {type: 'string'}, out: {type: 'string'}}});
  if (!args.props || !args.out) throw new Error('--props and --out are required');
  const {readFileSync} = await import('node:fs');
  writeFileSync(resolve(args.out), wav(synth(JSON.parse(readFileSync(resolve(args.props), 'utf8')))));
  console.log(resolve(args.out));
}
