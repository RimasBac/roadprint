import {Easing, interpolate} from 'remotion';

// Expo curves only: fast off the mark, long precise settle. No springs, no overshoot.
export const expoOut = Easing.bezier(0.16, 1, 0.3, 1);
export const expoInOut = Easing.bezier(0.87, 0, 0.13, 1);
const expoIn = Easing.bezier(0.7, 0, 0.84, 0);

/** 0 → 1 over `length` frames from `start`, on `easing`; clamped. */
export function progress(frame: number, start: number, length: number, easing = expoOut): number {
  return interpolate(frame, [start, start + length], [0, 1], {easing, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
}

/** The amber wipe: rises over the frame in the outgoing shot's last frames, leaves upward in the next shot's first. */
export const WIPE_IN = 14;
export const WIPE_OUT = 18;
export function wipeIn(frame: number, end: number): number {
  return interpolate(frame, [end - WIPE_IN, end], [0, 1], {easing: expoIn, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
}
