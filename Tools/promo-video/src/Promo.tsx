import React from 'react';
import {AbsoluteFill, Audio, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {progress, wipeIn, WIPE_OUT} from './motion';
import {Stage} from './Stage';
import {AMBER, End, Headline, Title} from './Type';
import type {PromoProps} from './types';

// A launch promo cut on a 120 BPM beat grid: one near-black stage, the app's amber as the only
// accent, Barlow Condensed as the only face. Every app pixel is a real App Store capture
// (public/shots). Banned on purpose: gradients, glows, blurs, particles, springs, pop-outs, 3D tilt.

const STAGE = '#0B0C10';

export const Promo: React.FC<PromoProps> = ({shots, screenAspect, music, badge}) => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const index = Math.max(0, shots.findLastIndex((s) => frame >= s.start));
  const shot = shots[index];
  const next = shots[index + 1];
  const local = frame - shot.start;
  const screenNumber = shots.slice(0, index + 1).filter((s) => s.kind === 'screen').length;

  // The amber wipe: covers the cut into a shot marked `wipe`, then leaves upward.
  const coverIn = next?.wipe ? wipeIn(local, shot.length) : 0;
  const coverOut = shot.wipe ? 1 - progress(local, 0, WIPE_OUT) : 0;
  const panel = coverIn > 0 ? {top: (1 - coverIn) * 100} : coverOut > 0 ? {top: -(1 - coverOut) * 100} : null;

  return (
    <AbsoluteFill style={{backgroundColor: STAGE, overflow: 'hidden'}}>
      {shot.kind === 'title' ? <Title shot={shot} local={local} /> : null}
      {shot.kind === 'screen' ? (
        <>
          <Stage shot={shot} local={local} aspect={screenAspect} />
          <Headline shot={shot} index={screenNumber} local={local} />
        </>
      ) : null}
      {shot.kind === 'end' ? <End shot={shot} local={local} badge={badge} /> : null}
      {panel ? <div style={{position: 'absolute', left: 0, right: 0, height: '100%', top: `${panel.top}%`, backgroundColor: AMBER}} /> : null}
      {music ? (
        <Audio src={staticFile(music)} volume={(f) => interpolate(f, [0, fps / 4, durationInFrames - fps, durationInFrames], [0, 1, 1, 0],
          {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
      ) : null}
    </AbsoluteFill>
  );
};
