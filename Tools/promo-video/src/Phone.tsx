import React from 'react';
import {Img, staticFile, useVideoConfig} from 'remotion';
import {lift} from './motion';
import type {Pop, Pose, Scene} from './types';

// The stage: a 1080×1920 frame seen with this perspective. Promo.tsx uses the same values.
export const FRAME = {w: 1080, h: 1920};
export const PERSPECTIVE = 2400;
export const ORIGIN = {x: FRAME.w / 2, y: FRAME.h * 0.45};

const SCREEN_W = 760;
const BEZEL = 20;
const SCREEN_RADIUS = 92;

/** Where a lifted element goes: flat to the camera, centred below the headline, as wide as fits. */
const FOCUS = {centreY: 1130, maxW: 940, maxH: 1180, z: 160};

type Vec = [number, number, number];
const rad = (d: number) => (d * Math.PI) / 180;
// CSS rotations, applied to [x, y, z] with y down and z toward the viewer.
const rotX = (a: number, [x, y, z]: Vec): Vec => [x, y * Math.cos(rad(a)) - z * Math.sin(rad(a)), y * Math.sin(rad(a)) + z * Math.cos(rad(a))];
const rotY = (a: number, [x, y, z]: Vec): Vec => [x * Math.cos(rad(a)) + z * Math.sin(rad(a)), y, -x * Math.sin(rad(a)) + z * Math.cos(rad(a))];

/** The screenshot, at the size of the phone screen. */
const Shot: React.FC<{shot: string; width: number; height: number; style?: React.CSSProperties}> = ({shot, width, height, style}) => (
  <Img src={staticFile(`shots/${shot}.png`)} style={{position: 'absolute', left: 0, top: 0, width, height, ...style}} />
);

/**
 * The phone in 3D: a generic body (no Apple artwork) with the scene's screenshot on its screen.
 * A new screenshot slides in over the last one (`slide` 0 → 1) as an iOS push does. While an
 * element is lifted out, the screen dims behind it: a focus effect, so the spot it left never
 * shows as a hole or a second copy.
 */
export const Phone: React.FC<{scene: Scene; previous: string | null; slide: number; local: number; pose: Pose; aspect: number}> = (
  {scene, previous, slide, local, pose, aspect},
) => {
  const {fps} = useVideoConfig();
  const height = SCREEN_W / aspect;
  const lifts = scene.pops.map((pop) => lift(pop, local, fps));
  const focus = Math.max(0, ...lifts);
  // The phone eases back a little while something is in focus, for depth.
  const at: Pose = {...pose, z: pose.z - 140 * focus};
  return (
    <div style={{
      position: 'absolute', left: '50%', top: '50%', width: SCREEN_W + BEZEL * 2, height: height + BEZEL * 2,
      marginLeft: -(SCREEN_W / 2 + BEZEL), marginTop: -(height / 2 + BEZEL), transformStyle: 'preserve-3d',
      transform: `translateY(${at.y}px) translateZ(${at.z}px) rotateX(${at.rx}deg) rotateY(${at.ry}deg)`,
    }}>
      <Body width={SCREEN_W} height={height} />
      <div style={{position: 'absolute', left: BEZEL, top: BEZEL, width: SCREEN_W, height, borderRadius: SCREEN_RADIUS,
        overflow: 'hidden', backgroundColor: '#000', transform: 'translateZ(1px)'}}>
        {previous && slide < 1 ? (
          <>
            <Shot shot={previous} width={SCREEN_W} height={height} style={{transform: `translateX(${-0.3 * SCREEN_W * slide}px)`}} />
            <div style={{position: 'absolute', inset: 0, backgroundColor: '#000', opacity: 0.35 * slide}} />
          </>
        ) : null}
        <Shot shot={scene.shot} width={SCREEN_W} height={height} style={previous && slide < 1 ? {
          transform: `translateX(${SCREEN_W * (1 - slide)}px)`, boxShadow: '-30px 0 60px rgba(0,0,0,0.5)'} : undefined} />
        <div style={{position: 'absolute', inset: 0, backgroundColor: '#000', opacity: 0.62 * focus}} />
        <div style={{position: 'absolute', top: 22, left: '50%', width: 210, height: 62, marginLeft: -105, borderRadius: 31,
          backgroundColor: '#000'}} />
      </div>
      {scene.pops.map((pop, i) => (
        <PopOut key={i} pop={pop} shot={scene.shot} p={lifts[i]} pose={at} width={SCREEN_W} height={height} />
      ))}
    </div>
  );
};

/**
 * A whole UI element of the screenshot coming forward: from its place on the screen (p = 0) to the
 * focus spot (p = 1), turning flat to the camera and growing to fill the frame's width.
 */
const PopOut: React.FC<{pop: Pop; shot: string; p: number; pose: Pose; width: number; height: number}> = ({pop, shot, p, pose, width, height}) => {
  if (p <= 0.001) return null;
  const [x, y, w, h] = pop.rect;
  const left = BEZEL + x * width, top = BEZEL + y * height, pw = w * width, ph = h * height;
  const phoneW = width + BEZEL * 2, phoneH = height + BEZEL * 2;
  // The element's centre in the phone's own space, from the phone's centre.
  const c: Vec = [left + pw / 2 - phoneW / 2, top + ph / 2 - phoneH / 2, 1];
  // Its focus spot in the stage's space: a point that projects to the focus centre at depth FOCUS.z.
  const depth = (PERSPECTIVE - FOCUS.z) / PERSPECTIVE;
  const target: Vec = [ORIGIN.x + (FRAME.w / 2 - ORIGIN.x) * depth, ORIGIN.y + (FOCUS.centreY - ORIGIN.y) * depth, FOCUS.z];
  // The phone's centre in the stage, then the move from the element's place, taken back into the phone's space.
  const phoneCentre: Vec = [FRAME.w / 2, FRAME.h / 2 + pose.y, pose.z];
  const worldMove: Vec = [target[0] - phoneCentre[0], target[1] - phoneCentre[1], target[2] - phoneCentre[2]];
  const local = rotY(-pose.ry, rotX(-pose.rx, worldMove)); // inverse of rotateX(rx) rotateY(ry): undo X, then Y
  const t: Vec = [local[0] - c[0], local[1] - c[1], local[2] - c[2]];
  const onScreenW = Math.min(FOCUS.maxW, (FOCUS.maxH * pw) / ph);
  const scale = (onScreenW * depth) / pw;
  const s = 1 + (scale - 1) * p;
  return (
    <div style={{
      position: 'absolute', left, top, width: pw, height: ph, borderRadius: 26 / s + 4 * p, overflow: 'hidden',
      transform: `translate3d(${t[0] * p}px, ${t[1] * p}px, ${t[2] * p}px) rotateY(${-pose.ry * p}deg) rotateX(${-pose.rx * p}deg) scale(${s})`,
      boxShadow: `0 ${50 * p}px ${110 * p}px rgba(0,0,0,${0.6 * p}), 0 0 ${70 * p}px rgba(255,181,64,${0.16 * p})`,
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
