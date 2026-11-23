// The props render.mjs writes (plan.mjs makes them from promo.json). Times are in frames.

type Base = {id: string; start: number; length: number; beat: number; wipe: boolean};

export type Zoom = {rect: [number, number, number, number]; at: number; length: number};

export type TitleShot = Base & {kind: 'title' | 'end'; lines: string[]; accent: number[]};

export type ScreenShot = Base & {
  kind: 'screen';
  /** The capture's CI name; the file is public/shots/<shot>.png. */
  shot: string;
  headline: [string, string];
  zooms: Zoom[];
  /** The phone rises into the window (the shot before had no phone). */
  rise: boolean;
};

export type Shot = TitleShot | ScreenShot;

export type PromoProps = {shots: Shot[]; frames: number; screenAspect: number; /** The soundtrack file in public/, or null for silence. */
  music: string | null; badge: boolean};
