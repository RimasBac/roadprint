import React from 'react';
import {AbsoluteFill, Audio, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {cameraPose, dip} from './motion';
import {Phone} from './Phone';
import {EndCard, Headline} from './Type';
import type {PromoProps} from './types';

// Every app pixel in this video is a real screenshot of the app (public/shots). The phone body,
// stage light and headlines are the only additions; pop-outs and the backdrop are the same screenshot.

export const Promo: React.FC<PromoProps> = ({scenes, screenAspect, music, badge}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const index = Math.max(0, scenes.findLastIndex((s) => frame >= s.start));
  const scene = scenes[index];
  const local = frame - scene.start;
  return (
    <AbsoluteFill style={{backgroundColor: '#07090C', overflow: 'hidden'}}>
      <Backdrop shot={scene.shot} />
      <AbsoluteFill style={{perspective: 2400, perspectiveOrigin: '50% 45%'}}>
        <Phone scene={scene} local={local} pose={cameraPose(scene, local, frame)} dark={dip(scenes, index, local)} aspect={screenAspect} />
      </AbsoluteFill>
      {scene.endCard ? <EndCard scene={scene} local={local} badge={badge} /> : <Headline scene={scene} local={local} />}
      {music ? (
        <Audio src={staticFile('music.m4a')} volume={(f) => interpolate(f, [0, 15, durationInFrames - 45, durationInFrames], [0, 1, 1, 0],
          {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
      ) : null}
    </AbsoluteFill>
  );
};

/** The stage: the same screenshot, blurred and dimmed, a warm glow behind the phone and a vignette. */
const Backdrop: React.FC<{shot: string}> = ({shot}) => (
  <AbsoluteFill>
    {/* Blurred anyway, so drawn at a quarter size and scaled up: far less memory per frame. */}
    <div style={{position: 'absolute', left: '-10%', top: '-10%', width: '30%', height: '30%', transform: 'scale(4)',
      transformOrigin: '0 0', filter: 'blur(14px) brightness(0.28) saturate(1.3)'}}>
      <Img src={staticFile(`shots/${shot}.png`)} style={{width: '100%', height: '100%', objectFit: 'cover'}} />
    </div>
    <AbsoluteFill style={{background: 'radial-gradient(circle at 50% 58%, rgba(255,181,64,0.16) 0%, rgba(7,9,12,0) 45%), ' +
      'radial-gradient(ellipse at center, rgba(0,0,0,0) 40%, rgba(0,0,0,0.75) 100%)'}} />
  </AbsoluteFill>
);
