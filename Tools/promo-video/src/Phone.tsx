import React from 'react';
import {Img, staticFile, useVideoConfig} from 'remotion';
import {lift} from './motion';
import type {Pop, Pose, Scene} from './types';

export const SCREEN_W = 760;
const BEZEL = 20;
const SCREEN_RADIUS = 92;

/** The screenshot, at the size of the phone screen. */
const Shot: React.FC<{shot: string; width: number; height: number}> = ({shot, width, height}) => (
  <Img src={staticFile(`shots/${shot}.png`)} style={{position: 'absolute', left: 0, top: 0, width, height}} />
);

/** Full-width regions have square edges, as in the app; cards keep rounded corners. */
const radius = (pop: Pop) => (pop.rect[2] > 0.99 ? 0 : 26);

/**
 * The phone in 3D: a generic body (no Apple artwork), the scene's screenshot on its screen, and the
 * pop-outs. Where a region has lifted out, the screen shows an empty slot, so it never appears twice.
 */
export const Phone: React.FC<{scene: Scene; local: number; pose: Pose; dark: number; aspect: number}> = ({scene, local, pose, dark, aspect}) => {
  const {fps} = useVideoConfig();
  const height = SCREEN_W / aspect;
  return (
    <div style={{
      position: 'absolute', left: '50%', top: '50%', width: SCREEN_W + BEZEL * 2, height: height + BEZEL * 2,
      marginLeft: -(SCREEN_W / 2 + BEZEL), marginTop: -(height / 2 + BEZEL), transformStyle: 'preserve-3d',
      transform: `translateY(${pose.y}px) translateZ(${pose.z}px) rotateX(${pose.rx}deg) rotateY(${pose.ry}deg)`,
    }}>
      <Body width={SCREEN_W} height={height} />
      <div style={{position: 'absolute', left: BEZEL, top: BEZEL, width: SCREEN_W, height, borderRadius: SCREEN_RADIUS,
        overflow: 'hidden', backgroundColor: '#000', transform: 'translateZ(1px)'}}>
        <Shot shot={scene.shot} width={SCREEN_W} height={height} />
        {scene.pops.map((pop, i) => {
          const p = lift(pop, local, fps);
          const [x, y, w, h] = pop.rect;
          return p > 0.01 ? (
            <div key={i} style={{position: 'absolute', left: x * SCREEN_W, top: y * height, width: w * SCREEN_W, height: h * height,
              borderRadius: radius(pop), backgroundColor: '#08090c', opacity: Math.min(1, p * 1.4),
              boxShadow: 'inset 0 10px 30px rgba(0,0,0,0.9)'}} />
          ) : null;
        })}
        <div style={{position: 'absolute', inset: 0, backgroundColor: '#000', opacity: dark}} />
        <div style={{position: 'absolute', top: 22, left: '50%', width: 210, height: 62, marginLeft: -105, borderRadius: 31,
          backgroundColor: '#000'}} />
      </div>
      {scene.pops.map((pop, i) => (
        <PopOut key={i} pop={pop} shot={scene.shot} p={lift(pop, local, fps)} pose={pose} width={SCREEN_W} height={height} />
      ))}
    </div>
  );
};

/** A whole UI element of the screenshot, lifted toward the camera; `face` also turns it to the camera and centres it. */
const PopOut: React.FC<{pop: Pop; shot: string; p: number; pose: Pose; width: number; height: number}> = ({pop, shot, p, pose, width, height}) => {
  if (p <= 0.01) return null;
  const [x, y, w, h] = pop.rect;
  const left = BEZEL + x * width, top = BEZEL + y * height, pw = w * width, ph = h * height;
  const face = pop.face ? p : 0;
  const centre = BEZEL + width / 2 - (left + pw / 2);
  return (
    <div style={{
      position: 'absolute', left, top, width: pw, height: ph, borderRadius: radius(pop), overflow: 'hidden',
      transform: `translateX(${centre * face}px) translateZ(${p * (pop.face ? 300 : 200)}px) ` +
        `rotateY(${-pose.ry * face}deg) rotateX(${-pose.rx * face}deg) scale(${1 + p * 0.04})`,
      boxShadow: `0 ${40 * p}px ${90 * p}px rgba(0,0,0,${0.55 * p}), 0 0 ${60 * p}px rgba(255,181,64,${0.18 * p})`,
    }}>
      <div style={{position: 'absolute', left: -x * width, top: -y * height, width, height}}>
        <Shot shot={shot} width={width} height={height} />
      </div>
    </div>
  );
};

/** Dark titanium: a rounded body, edge light, side buttons and a warm reflection below. */
const Body: React.FC<{width: number; height: number}> = ({width, height}) => (
  <>
    <div style={{
      position: 'absolute', inset: 0, borderRadius: SCREEN_RADIUS + BEZEL,
      background: 'linear-gradient(135deg, #4a4d52 0%, #1d1f23 18%, #0e0f12 50%, #24262b 82%, #55585e 100%)',
      boxShadow: '0 80px 160px rgba(0,0,0,0.65), inset 0 0 0 2px rgba(255,255,255,0.08), inset 0 0 0 9px #050506',
    }} />
    {[[-5, 300, 120], [-5, 450, 120], [width + BEZEL * 2 - 1, 380, 190]].map(([x, y, h], i) => (
      <div key={i} style={{position: 'absolute', left: x, top: y, width: 6, height: h, borderRadius: 3,
        background: 'linear-gradient(90deg, #2b2d31, #5b5e64)'}} />
    ))}
    <div style={{position: 'absolute', left: 0, top: height + BEZEL * 2 + 60, width: width + BEZEL * 2, height: 120, borderRadius: '50%',
      background: 'radial-gradient(ellipse at center, rgba(255,181,64,0.22), transparent 70%)', filter: 'blur(20px)',
      transform: 'rotateX(80deg)'}} />
  </>
);
