import React from 'react';
import {Composition} from 'remotion';
import {Promo} from './Promo';
import type {PromoProps} from './types';

// render.mjs passes the real props (--props); the placeholder only lets the studio open without them.
const placeholder: PromoProps = {scenes: [], frames: 1, screenAspect: 1320 / 2868, music: false, badge: false};

export const Root: React.FC = () => (
  <Composition id="Promo" component={Promo} width={1080} height={1920} fps={30} durationInFrames={1}
    defaultProps={placeholder} calculateMetadata={({props}) => ({durationInFrames: Math.max(1, props.frames)})} />
);
