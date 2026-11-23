import React from 'react';
import {Composition} from 'remotion';
import {Promo, PromoProps} from './Promo';

// render.mjs writes the real props (scene timings from the UI test's marks); these only let the
// studio open without them.
const placeholder: PromoProps = {scenes: [], screenAspect: 440 / 956, music: false, badge: false};

export const Root: React.FC = () => (
  <Composition
    id="Promo"
    component={Promo}
    width={1080}
    height={1920}
    fps={30}
    durationInFrames={1}
    defaultProps={placeholder}
    calculateMetadata={({props}) => ({
      durationInFrames: Math.max(1, props.scenes.reduce((sum, s) => sum + Math.round(s.seconds * 30), 0)),
    })}
  />
);
