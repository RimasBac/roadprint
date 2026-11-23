import React from 'react';
import {Img, continueRender, delayRender, staticFile} from 'remotion';
import {expoOut, progress} from './motion';
import type {ScreenShot, TitleShot} from './types';

export const AMBER = '#FFB547'; // the app's route and accent colour
export const INK = '#F0EFEC'; // the app's text colour
const FONT = 'Barlow Condensed'; // the app's display face, from App/Resources/Fonts
export const MARGIN = 72;

const loading = delayRender(FONT);
new FontFace(FONT, `url(${staticFile('BarlowCondensed-700.ttf')})`, {weight: '700'})
  .load()
  .then((font) => { document.fonts.add(font); continueRender(loading); });

/** One line revealed through a mask: it slides up into its own slot. No fade. */
const Line: React.FC<{text: string; size: number; color: string; local: number; at: number}> = ({text, size, color, local, at}) => {
  const p = progress(local, at, 22, expoOut);
  return (
    <div style={{overflow: 'hidden', height: size * 1.0, lineHeight: 1}}>
      <div style={{fontFamily: FONT, fontWeight: 700, fontSize: size, lineHeight: 1, color, whiteSpace: 'nowrap',
        transform: `translateY(${(1 - p) * 105}%)`}}>{text}</div>
    </div>
  );
};

/** Big words on the stage, one line on each beat. */
export const Title: React.FC<{shot: TitleShot; local: number}> = ({shot, local}) => {
  const size = 196;
  const top = (1920 - shot.lines.length * size * 1.04) / 2 - 40;
  return (
    <div style={{position: 'absolute', left: MARGIN, top, display: 'flex', flexDirection: 'column', gap: size * 0.04}}>
      {shot.lines.map((line, i) => (
        <Line key={i} text={line} size={size} color={shot.accent.includes(i) ? AMBER : INK} local={local} at={Math.round(i * shot.beat) + 2} />
      ))}
    </div>
  );
};

/** The headline band above the phone: a shot number, then two lines, the second in amber. */
export const Headline: React.FC<{shot: ScreenShot; index: number; local: number}> = ({shot, index, local}) => (
  <div style={{position: 'absolute', left: MARGIN, top: 118, display: 'flex', flexDirection: 'column', gap: 4}}>
    <Line text={String(index).padStart(2, '0')} size={36} color={AMBER} local={local} at={2} />
    <div style={{height: 18}} />
    <Line text={shot.headline[0]} size={100} color={INK} local={local} at={4} />
    <Line text={shot.headline[1]} size={100} color={AMBER} local={local} at={10} />
  </div>
);

/** The closing title; the App Store badge only when Apple's official SVG was passed with --badge. */
export const End: React.FC<{shot: TitleShot; local: number; badge: boolean}> = ({shot, local, badge}) => (
  <div style={{position: 'absolute', left: MARGIN, top: 700, display: 'flex', flexDirection: 'column', gap: 26}}>
    <Line text={shot.lines[0]} size={210} color={shot.accent.includes(0) ? AMBER : INK} local={local} at={Math.round(shot.beat)} />
    <Line text={shot.lines[1]} size={84} color={shot.accent.includes(1) ? AMBER : INK} local={local} at={Math.round(2 * shot.beat)} />
    {badge ? (
      <Img src={staticFile('app-store-badge.svg')} style={{height: 96, marginTop: 40, width: 'auto', alignSelf: 'flex-start',
        clipPath: `inset(0 ${(1 - progress(local, Math.round(3 * shot.beat), 24)) * 100}% 0 0)`}} />
    ) : null}
  </div>
);
