import React from 'react';
import {Img, continueRender, delayRender, staticFile, useVideoConfig} from 'remotion';
import {arrive, leave} from './motion';
import type {Scene} from './types';

const AMBER = '#FFB540';
const FONT = 'Barlow Condensed'; // the app's display face, from App/Resources/Fonts

const loading = delayRender(FONT);
new FontFace(FONT, `url(${staticFile('BarlowCondensed-700.ttf')})`, {weight: '700'})
  .load()
  .then((font) => { document.fonts.add(font); continueRender(loading); });

/** Two lines over the phone: white, then amber, each arriving a beat apart; both leave together. */
export const Headline: React.FC<{scene: Scene; local: number; last: boolean}> = ({scene, local, last}) => {
  const {fps} = useVideoConfig();
  return (
    <div style={{position: 'absolute', top: 110, left: 50, right: 50, textAlign: 'center', fontFamily: FONT, fontWeight: 700,
      fontSize: 104, lineHeight: 1, ...(last ? {} : leave(local, scene.length, fps))}}>
      {scene.headline.map((line, i) => (
        <div key={i} style={{color: i ? AMBER : '#FFFFFF', ...arrive(local, fps, 0.12 + i * 0.12)}}>{line}</div>
      ))}
    </div>
  );
};

/** The closing title; the App Store badge only when Apple's official SVG was passed with --badge. */
export const EndCard: React.FC<{scene: Scene; local: number; badge: boolean}> = ({scene, local, badge}) => {
  const {fps} = useVideoConfig();
  return (
    <div style={{position: 'absolute', top: 200, left: 0, right: 0, textAlign: 'center', fontFamily: FONT, fontWeight: 700}}>
      <div style={{color: '#FFFFFF', fontSize: 150, letterSpacing: 14, ...arrive(local, fps, 0.2)}}>{scene.headline[0]}</div>
      <div style={{color: AMBER, fontSize: 70, letterSpacing: 4, marginTop: 10, ...arrive(local, fps, 0.4)}}>{scene.headline[1]}</div>
      {badge ? <Img src={staticFile('app-store-badge.svg')} style={{height: 96, marginTop: 50, ...arrive(local, fps, 0.6)}} /> : null}
    </div>
  );
};
