import type React from 'react';
import {Easing, interpolate, spring} from 'remotion';
import type {Pop, Pose, Scene} from './types';

/** Frames the screen takes to dip to black, and back, when the screenshot changes. */
export const DIP = 5;

const mix = (a: number, b: number, t: number) => a + (b - a) * t;

/** The camera on the phone: an eased move from the scene's start pose to its end pose, plus a slow float. */
export function cameraPose(scene: Scene, local: number, frame: number): Pose {
  const t = interpolate(local, [0, scene.length], [0, 1], {easing: Easing.inOut(Easing.cubic), extrapolateRight: 'clamp'});
  return {
    rx: mix(scene.from.rx, scene.to.rx, t) + Math.sin(frame / 45) * 1.2,
    ry: mix(scene.from.ry, scene.to.ry, t),
    z: mix(scene.from.z, scene.to.z, t),
    y: mix(scene.from.y, scene.to.y, t) + Math.sin(frame / 38) * 8,
  };
}

/** 0 to 1: how far a pop-out has lifted. Springs up at `at`, settles back after `hold`. */
export function lift(pop: Pop, local: number, fps: number): number {
  const end = pop.at + pop.hold;
  if (local < pop.at - 1 || local > end + 18) return 0;
  const up = spring({frame: local - pop.at, fps, config: {damping: 14, mass: 0.8}});
  const down = spring({frame: local - end, fps, config: {damping: 18}});
  return Math.max(0, up - down);
}

/** 1 at a cut to a different screenshot, falling to 0 within DIP frames on either side. */
export function dip(scenes: Scene[], index: number, local: number): number {
  const scene = scenes[index];
  const into = index > 0 && scenes[index - 1].shot !== scene.shot ? 1 - local / DIP : 0;
  const out = index < scenes.length - 1 && scenes[index + 1].shot !== scene.shot ? 1 - (scene.length - local) / DIP : 0;
  return Math.max(0, into, out);
}

/** Text rising into place, `frame` frames after it starts. */
export function rise(frame: number): React.CSSProperties {
  const p = interpolate(frame, [0, 14], [0, 1], {easing: Easing.out(Easing.cubic), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return {opacity: p, transform: `translateY(${(1 - p) * 50}px)`};
}
