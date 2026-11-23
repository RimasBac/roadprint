import type React from 'react';
import {Easing, interpolate} from 'remotion';
import type {Pop, Pose, Scene} from './types';

/** Seconds a new screen takes to slide in, as an iOS navigation push. */
export const PUSH_SECONDS = 0.5;
const LIFT_UP_SECONDS = 0.6;
const LIFT_DOWN_SECONDS = 0.5;

// Apple-like curves: a long, soft settle, no overshoot.
const settle = Easing.bezier(0.16, 1, 0.3, 1);
const glide = Easing.bezier(0.45, 0, 0.2, 1);
const ios = Easing.bezier(0.32, 0.72, 0, 1);

const KEYS = ['rx', 'ry', 'z', 'y'] as const;

/**
 * The camera on the phone, as one continuous path: a cubic spline through the pose at every scene
 * boundary, so the phone never stops between scenes. It starts and ends at rest. A slow float on top.
 */
export function cameraPose(scenes: Scene[], frame: number): Pose {
  const times = [0, ...scenes.map((s) => s.start + s.length)];
  const poses = [scenes[0].from, ...scenes.map((s) => s.to)];
  const last = times.length - 1;
  const f = Math.min(Math.max(frame, 0), times[last]);
  let i = 0;
  while (i < last - 1 && f > times[i + 1]) i++;
  const [t0, t1] = [times[i], times[i + 1]];
  const h = t1 - t0, u = h > 0 ? (f - t0) / h : 0;
  // Catmull-Rom tangents (per frame), zero at both ends so the move eases in and out.
  const slope = (k: number, key: (typeof KEYS)[number]) => (k === 0 || k === last ? 0
    : (poses[k + 1][key] - poses[k - 1][key]) / (times[k + 1] - times[k - 1]));
  const pose = {} as Pose;
  for (const key of KEYS) {
    const [p0, p1, m0, m1] = [poses[i][key], poses[i + 1][key], slope(i, key) * h, slope(i + 1, key) * h];
    const u2 = u * u, u3 = u2 * u;
    pose[key] = (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * m0 + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * m1;
  }
  const s = frame / 60; // seconds, so the float is the same at any frame rate
  pose.rx += Math.sin(s * 1.1) * 1.0;
  pose.y += Math.sin(s * 1.4) * 6;
  return pose;
}

/** 0 to 1: how far a pop-out has come forward. Settles in after `at`, glides back after `hold`. */
export function lift(pop: Pop, local: number, fps: number): number {
  const up = interpolate(local, [pop.at, pop.at + LIFT_UP_SECONDS * fps], [0, 1],
    {easing: settle, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const end = pop.at + pop.hold;
  const down = interpolate(local, [end, end + LIFT_DOWN_SECONDS * fps], [0, 1],
    {easing: glide, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return Math.max(0, up - down);
}

/** 0 to 1: the new screen's slide in; 1 when there is nothing to slide. */
export function push(scenes: Scene[], index: number, local: number, fps: number): number {
  if (index === 0 || scenes[index - 1].shot === scenes[index].shot) return 1;
  return interpolate(local, [0, PUSH_SECONDS * fps], [0, 1], {easing: ios, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
}

/** Text arriving: rises, sharpens and fades in over 0.45 s, `delay` seconds after the scene starts. */
export function arrive(local: number, fps: number, delay: number): React.CSSProperties {
  const p = interpolate(local, [delay * fps, (delay + 0.45) * fps], [0, 1],
    {easing: settle, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return {opacity: p, transform: `translateY(${(1 - p) * 40}px)`, filter: `blur(${(1 - p) * 10}px)`};
}

/** Text leaving over the scene's last 0.3 s: lifts, softens and fades. */
export function leave(local: number, length: number, fps: number): React.CSSProperties {
  const p = interpolate(local, [length - 0.3 * fps, length], [0, 1], {easing: glide, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return {opacity: 1 - p, transform: `translateY(${-p * 24}px)`, filter: `blur(${p * 8}px)`};
}
