import React from 'react';
import {Img, continueRender, delayRender, interpolate, staticFile} from 'remotion';
import {rise} from './motion';
import type {Scene} from './types';

const AMBER = '#FFB540';
const FONT = 'Barlow Condensed'; // the app's display face, from App/Resources/Fonts

const loading = delayRender(FONT);
new FontFace(FONT, `url(${staticFile('BarlowCondensed-700.ttf')})`, {weight: '700'})
  .load()
  .then((font) => { document.fonts.add(font); continueRender(loading); });

/** Two lines over the phone: white, then amber. */
export const Headline: React.FC<{scene: Scene; local: number}> = ({scene, local}) => {
  const out = interpolate(local, [scene.length - 10, scene.length], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div style={{position: 'absolute', top: 120, left: 60, right: 60, textAlign: 'center', fontFamily: FONT, fontWeight: 700,
      fontSize: 104, lineHeight: 1, opacity: out}}>
      {scene.headline.map((line, i) => (
        <div key={i} style={{color: i ? AMBER : '#FFFFFF', ...rise(local - 4 - i * 6)}}>{line}</div>
      ))}
    </div>
  );
};

/** The closing title; the App Store badge only when Apple's official SVG was passed with --badge. */
export const EndCard: React.FC<{scene: Scene; local: number; badge: boolean}> = ({scene, local, badge}) => (
  <div style={{position: 'absolute', top: 210, left: 0, right: 0, textAlign: 'center', fontFamily: FONT, fontWeight: 700}}>
    <div style={{color: '#FFFFFF', fontSize: 150, letterSpacing: 14, ...rise(local - 6)}}>{scene.headline[0]}</div>
    <div style={{color: AMBER, fontSize: 70, letterSpacing: 4, marginTop: 10, ...rise(local - 14)}}>{scene.headline[1]}</div>
    {badge ? <Img src={staticFile('app-store-badge.svg')} style={{height: 96, marginTop: 50, ...rise(local - 24)}} /> : null}
  </div>
);
