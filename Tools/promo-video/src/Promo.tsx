import React from 'react';
import {
  AbsoluteFill, Audio, Easing, Img, OffthreadVideo, Sequence, continueRender, delayRender,
  interpolate, spring, staticFile, useCurrentFrame, useVideoConfig,
} from 'remotion';

// Every app pixel in this video is the simulator recording (public/raw.mov). The phone body,
// background, light and headlines are the only additions; pop-outs are crops of the same footage.

export type Pose = {rx: number; ry: number; z: number; y: number};
export type Pop = {rect: [number, number, number, number]; at: number; hold: number; face?: boolean};
export type Scene = {
  id: string; sourceStart: number; seconds: number; headline: [string, string];
  from: Pose; to: Pose; pops: Pop[]; endCard?: boolean;
};
export type PromoProps = {scenes: Scene[]; screenAspect: number; music: boolean; badge: boolean};

const AMBER = '#FFB540';
const SCREEN_W = 760;
const BEZEL = 20;
const FADE = 8; // frames of crossfade between scenes on the phone screen

const fontHandle = delayRender('Barlow Condensed');
new FontFace('Barlow Condensed', `url(${staticFile('BarlowCondensed-700.ttf')})`, {weight: '700'})
  .load()
  .then((font) => { document.fonts.add(font); continueRender(fontHandle); });

export const Promo: React.FC<PromoProps> = ({scenes, screenAspect, music, badge}) => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const starts = scenes.reduce<number[]>((acc, s, i) => [...acc, i ? acc[i - 1] + Math.round(scenes[i - 1].seconds * fps) : 0], []);
  const index = Math.max(0, starts.findIndex((start, i) => frame >= start && (i === scenes.length - 1 || frame < starts[i + 1])));
  const scene = scenes[index];
  const local = frame - starts[index];
  const length = Math.round(scene.seconds * fps);
  const t = interpolate(local, [0, length], [0, 1], {easing: Easing.inOut(Easing.cubic), extrapolateRight: 'clamp'});
  const pose: Pose = {
    rx: mix(scene.from.rx, scene.to.rx, t), ry: mix(scene.from.ry, scene.to.ry, t),
    z: mix(scene.from.z, scene.to.z, t), y: mix(scene.from.y, scene.to.y, t),
  };
  // A slow float so the phone never sits dead still.
  pose.rx += Math.sin(frame / 45) * 1.2;
  pose.y += Math.sin(frame / 38) * 8;
  const screenH = SCREEN_W / screenAspect;

  const screens = scenes.map((s, i) => (
    <Sequence key={s.id} from={starts[i] - (i ? FADE : 0)} durationInFrames={Math.round(s.seconds * fps) + (i ? FADE : 0)} layout="none">
      <SceneScreen scene={s} width={SCREEN_W} height={screenH} fadeIn={i ? FADE : 0} lead={i ? FADE : 0} />
    </Sequence>
  ));

  return (
    <AbsoluteFill style={{backgroundColor: '#07090C', overflow: 'hidden'}}>
      <Backdrop scenes={scenes} starts={starts} />
      <AbsoluteFill style={{perspective: 2400, perspectiveOrigin: '50% 45%'}}>
        <div style={{
          position: 'absolute', left: '50%', top: '50%', width: SCREEN_W + BEZEL * 2, height: screenH + BEZEL * 2,
          marginLeft: -(SCREEN_W / 2 + BEZEL), marginTop: -(screenH / 2 + BEZEL),
          transformStyle: 'preserve-3d',
          transform: `translateY(${pose.y}px) translateZ(${pose.z}px) rotateX(${pose.rx}deg) rotateY(${pose.ry}deg)`,
        }}>
          <PhoneBody width={SCREEN_W} height={screenH} />
          <div style={{position: 'absolute', left: BEZEL, top: BEZEL, width: SCREEN_W, height: screenH,
            borderRadius: 92, overflow: 'hidden', backgroundColor: '#000', transform: 'translateZ(1px)'}}>
            {screens}
            <div style={{position: 'absolute', top: 22, left: '50%', width: 210, height: 62, marginLeft: -105,
              borderRadius: 31, backgroundColor: '#000'}} />
          </div>
          {/* In the scene's own Sequence, so the pop-out's footage runs on the scene's clock. */}
          <Sequence from={starts[index]} durationInFrames={length} layout="none">
            {scene.pops.map((pop, i) => (
              <PopOut key={`${scene.id}-${i}`} pop={pop} scene={scene} local={local} pose={pose}
                width={SCREEN_W} height={screenH} />
            ))}
          </Sequence>
        </div>
      </AbsoluteFill>
      <Headline scene={scene} local={local} length={length} />
      {scene.endCard ? <EndCard local={local} badge={badge} /> : null}
      {music ? <Audio src={staticFile('music.m4a')} volume={(f) => interpolate(f, [0, 15, durationInFrames - 45, durationInFrames], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} /> : null}
    </AbsoluteFill>
  );
};

/** The recording at this scene's moment, filling the phone screen. */
const SceneScreen: React.FC<{scene: Scene; width: number; height: number; fadeIn: number; lead: number}> = ({scene, width, height, fadeIn, lead}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = fadeIn ? interpolate(frame, [0, fadeIn], [0, 1], {extrapolateRight: 'clamp'}) : 1;
  return (
    <div style={{position: 'absolute', inset: 0, opacity}}>
      <Footage scene={scene} width={width} height={height} lead={lead} fps={fps} />
    </div>
  );
};

const Footage: React.FC<{scene: Scene; width: number; height: number; lead: number; fps: number}> = ({scene, width, height, lead, fps}) => (
  <OffthreadVideo src={staticFile('raw.mov')} muted
    startFrom={Math.max(0, Math.round(scene.sourceStart * fps) - lead)}
    style={{position: 'absolute', left: 0, top: 0, width, height}} />
);

/** A real region of the screen lifts toward the camera, then settles back into place. */
const PopOut: React.FC<{pop: Pop; scene: Scene; local: number; pose: Pose; width: number; height: number}> = ({pop, scene, local, pose, width, height}) => {
  const {fps} = useVideoConfig();
  const start = Math.round(pop.at * fps);
  const end = start + Math.round(pop.hold * fps);
  if (local < start - 1 || local > end + 18) return null;
  const up = spring({frame: local - start, fps, config: {damping: 14, mass: 0.8}});
  const down = spring({frame: local - end, fps, config: {damping: 18}});
  const p = Math.max(0, up - down);
  const [x, y, w, h] = pop.rect;
  const left = BEZEL + x * width, top = BEZEL + y * height, pw = w * width, ph = h * height;
  // "face" turns the region toward the camera and brings it to the middle of the frame.
  const face = pop.face ? p : 0;
  const centre = (BEZEL + width / 2) - (left + pw / 2);
  return (
    <div style={{
      position: 'absolute', left, top, width: pw, height: ph, borderRadius: 26, overflow: 'hidden',
      transformOrigin: '50% 50%',
      transform: `translateX(${centre * face}px) translateZ(${p * (pop.face ? 520 : 240)}px) ` +
        `rotateY(${-pose.ry * face}deg) rotateX(${-pose.rx * face}deg) scale(${1 + p * (pop.face ? 0.12 : 0.06)})`,
      boxShadow: `0 ${40 * p}px ${90 * p}px rgba(0,0,0,${0.55 * p}), 0 0 ${60 * p}px rgba(255,181,64,${0.18 * p})`,
      opacity: p > 0.01 ? 1 : 0,
    }}>
      <div style={{position: 'absolute', left: -x * width, top: -y * height, width, height}}>
        <Footage scene={scene} width={width} height={height} lead={0} fps={fps} />
      </div>
    </div>
  );
};

/** A generic dark-titanium phone: rounded body, side light and buttons. No Apple artwork. */
const PhoneBody: React.FC<{width: number; height: number}> = ({width, height}) => (
  <>
    <div style={{
      position: 'absolute', inset: 0, borderRadius: 112,
      background: 'linear-gradient(135deg, #4a4d52 0%, #1d1f23 18%, #0e0f12 50%, #24262b 82%, #55585e 100%)',
      boxShadow: '0 80px 160px rgba(0,0,0,0.65), inset 0 0 0 2px rgba(255,255,255,0.08), inset 0 0 0 9px #050506',
    }} />
    {[[-5, 300, 120], [-5, 450, 120], [width + BEZEL * 2 - 1, 380, 190]].map(([x, y, h], i) => (
      <div key={i} style={{position: 'absolute', left: x, top: y, width: 6, height: h, borderRadius: 3,
        background: 'linear-gradient(90deg, #2b2d31, #5b5e64)'}} />
    ))}
    <div style={{position: 'absolute', left: 0, top: height + BEZEL * 2 + 60, width: width + BEZEL * 2, height: 120,
      borderRadius: '50%', background: 'radial-gradient(ellipse at center, rgba(255,181,64,0.22), transparent 70%)',
      filter: 'blur(20px)', transform: 'rotateX(80deg)'}} />
  </>
);

/** Dark stage: a blurred, dimmed copy of the same footage, plus a warm glow behind the phone. */
const Backdrop: React.FC<{scenes: Scene[]; starts: number[]}> = ({scenes, starts}) => {
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill>
      {scenes.map((s, i) => (
        <Sequence key={s.id} from={starts[i]} durationInFrames={Math.round(s.seconds * fps)} layout="none">
          {/* Blurred anyway, so draw it at a quarter size and scale up: far less memory per frame. */}
          <div style={{position: 'absolute', left: '-10%', top: '-10%', width: '30%', height: '30%',
            transform: 'scale(4)', transformOrigin: '0 0', filter: 'blur(14px) brightness(0.28) saturate(1.3)'}}>
            <OffthreadVideo src={staticFile('raw.mov')} muted startFrom={Math.round(s.sourceStart * fps)}
              style={{width: '100%', height: '100%', objectFit: 'cover'}} />
          </div>
        </Sequence>
      ))}
      <AbsoluteFill style={{background: 'radial-gradient(circle at 50% 58%, rgba(255,181,64,0.16) 0%, rgba(7,9,12,0) 45%), radial-gradient(ellipse at center, rgba(0,0,0,0) 40%, rgba(0,0,0,0.75) 100%)'}} />
    </AbsoluteFill>
  );
};

const Headline: React.FC<{scene: Scene; local: number; length: number}> = ({scene, local, length}) => {
  if (scene.endCard) return null;
  const out = interpolate(local, [length - 10, length], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div style={{position: 'absolute', top: 120, left: 60, right: 60, textAlign: 'center',
      fontFamily: 'Barlow Condensed', fontWeight: 700, fontSize: 104, lineHeight: 1.0, opacity: out}}>
      {scene.headline.map((line, i) => (
        <div key={i} style={{color: i ? AMBER : '#FFFFFF', ...rise(local - 4 - i * 6)}}>{line}</div>
      ))}
    </div>
  );
};

const EndCard: React.FC<{local: number; badge: boolean}> = ({local, badge}) => (
  <div style={{position: 'absolute', top: 210, left: 0, right: 0, textAlign: 'center', fontFamily: 'Barlow Condensed', fontWeight: 700}}>
    <div style={{color: '#FFFFFF', fontSize: 150, letterSpacing: 14, ...rise(local - 6)}}>ROADPRINT</div>
    <div style={{color: AMBER, fontSize: 70, letterSpacing: 4, marginTop: 10, ...rise(local - 14)}}>EVERY ROAD. ONE MAP.</div>
    {badge ? <Img src={staticFile('app-store-badge.svg')} style={{height: 96, marginTop: 50, ...rise(local - 24)}} /> : null}
  </div>
);

function rise(frame: number): React.CSSProperties {
  const p = interpolate(frame, [0, 14], [0, 1], {easing: Easing.out(Easing.cubic), extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return {opacity: p, transform: `translateY(${(1 - p) * 50}px)`};
}

function mix(a: number, b: number, t: number) {
  return a + (b - a) * t;
}
