import React from 'react';
import {Img, staticFile, useVideoConfig} from 'remotion';
import {expoInOut, expoOut, progress, WIPE_OUT} from './motion';
import type {ScreenShot} from './types';

// The picture window below the headline band, and the flat phone in it.
export const WINDOW = {top: 440, height: 1480};
const W = 1080;
const SCREEN_W = 600;
const BEZEL = 12;
const RADIUS = 98;
/** A dive fills this much of the window: as wide as the frame allows, or as tall. */
const DIVE = {w: 1000, h: 1400};

/**
 * A real App Store capture in a plain phone, straight on. The camera dives into a named rectangle
 * of the capture and back out, so a detail fills the window while every pixel stays where the app
 * put it: nothing is cut out, lifted or duplicated. A slow push keeps the frame alive between dives.
 */
export const Stage: React.FC<{shot: ScreenShot; local: number; aspect: number}> = ({shot, local, aspect}) => {
  const {fps} = useVideoConfig();
  const screenH = SCREEN_W / aspect;
  const centre = {x: W / 2, y: WINDOW.height / 2};
  const screen = {x: centre.x - SCREEN_W / 2, y: centre.y - screenH / 2};

  let scale = 1, tx = 0, ty = 0;
  for (const zoom of shot.zooms) {
    const into = progress(local, zoom.at, Math.round(0.7 * fps), expoInOut);
    const back = progress(local, zoom.at + zoom.length - Math.round(0.6 * fps), Math.round(0.6 * fps), expoInOut);
    const e = into - back;
    if (e <= 0) continue;
    const [x, y, w, h] = zoom.rect;
    const c = {x: screen.x + (x + w / 2) * SCREEN_W, y: screen.y + (y + h / 2) * screenH};
    const s = Math.min(DIVE.w / (w * SCREEN_W), DIVE.h / (h * screenH));
    // The rect's centre travels toward the window's centre as the scale grows; for a thin element
    // it stops short, so the zoomed phone still covers the window from top to bottom (no empty band).
    const phoneTop = screen.y - BEZEL, phoneBottom = screen.y + screenH + BEZEL;
    const highest = -s * phoneTop, lowest = WINDOW.height - s * phoneBottom;
    const aim = centre.y - s * c.y;
    scale += (s - 1) * e;
    tx += e * (centre.x - s * c.x);
    ty += e * (lowest <= highest ? Math.min(highest, Math.max(lowest, aim)) : aim);
  }
  const push = 1 + 0.035 * (local / shot.length);
  const rise = shot.rise ? 1 - progress(local, shot.wipe ? WIPE_OUT - 6 : 0, Math.round(0.9 * fps), expoOut) : 0;

  return (
    <div style={{position: 'absolute', left: 0, top: WINDOW.top, width: W, height: WINDOW.height, overflow: 'hidden'}}>
      <div style={{position: 'absolute', inset: 0, transform: `translateY(${rise * WINDOW.height}px) scale(${push})`,
        transformOrigin: `${centre.x}px ${centre.y}px`}}>
        <div style={{position: 'absolute', left: 0, top: 0, width: W, height: WINDOW.height, transformOrigin: '0 0',
          transform: `translate(${tx}px, ${ty}px) scale(${scale})`}}>
          <div style={{position: 'absolute', left: screen.x - BEZEL, top: screen.y - BEZEL, width: SCREEN_W + 2 * BEZEL,
            height: screenH + 2 * BEZEL, borderRadius: RADIUS, backgroundColor: '#000', boxShadow: 'inset 0 0 0 2px #2A2E36'}} />
          <div style={{position: 'absolute', left: screen.x, top: screen.y, width: SCREEN_W, height: screenH,
            borderRadius: RADIUS - BEZEL, overflow: 'hidden'}}>
            <Img src={staticFile(`shots/${shot.shot}.png`)} style={{width: SCREEN_W, height: screenH, display: 'block'}} />
            <div style={{position: 'absolute', top: 16, left: '50%', width: 168, height: 48, marginLeft: -84,
              borderRadius: 24, backgroundColor: '#000'}} />
          </div>
        </div>
      </div>
    </div>
  );
};
