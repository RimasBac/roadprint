// The props render.mjs writes (plan.mjs makes them from promo.json). Times are in frames.

export type Pose = {rx: number; ry: number; z: number; y: number};

/** A real screenshot region, in fractions of the screen, lifted out of it. */
export type Pop = {rect: [number, number, number, number]; at: number; hold: number; face: boolean};

export type Scene = {
  id: string;
  /** The screenshot's CI capture name; the file is public/shots/<shot>.png. */
  shot: string;
  start: number;
  length: number;
  headline: [string, string];
  from: Pose;
  to: Pose;
  pops: Pop[];
  endCard: boolean;
};

export type PromoProps = {scenes: Scene[]; frames: number; screenAspect: number; music: boolean; badge: boolean};
