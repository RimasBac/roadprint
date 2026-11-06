// Maps a Natural Earth 1:10m `roads` record to a sign network and a short ref.
// Table-driven: the first rule whose `when` matches wins. Tested by normalise.test.mjs.
//
// NE fields used (all strings, may be empty): name (the route number, "80"), label ("E40"),
// label2, local ("A10", "M6"), prefix ("I", "US", "E"), level ("Interstate", "Federal",
// "State", "E"), routeraw ("E3 E401 A84", "_untitled_12" for junk), plus `country` (ISO
// 3166-1 alpha-2) which build.mjs derives from the admin-0 outlines (NE's own sov_a3 is empty
// outside North America).

/** Byte codes written to roads.rpgeo. The order of RANK, lowest to highest, breaks ties. */
export const NETWORKS = {
  generic: 0,
  usInterstate: 1,
  usHighway: 2,
  canadaHighway: 3,
  eRoad: 4,
  ukMotorway: 5,
  ukARoad: 6,
  australia: 7,
};

const clean = (s) => String(s ?? '').trim().toUpperCase().replace(/\s+/g, ' ');
const usable = (s) => /^[A-Z0-9][A-Z0-9()\-]{0,7}$/.test(s) && !s.startsWith('_');
const firstToken = (s) => clean(s).split(' ').find(usable) ?? '';
const digits = (s) => (clean(s).match(/^(\d{1,3}[A-Z]?)$/) ?? [])[1] ?? '';

/** "E40" from label, label2, routeraw tokens, or prefix "E" + name. */
function eRoadRef(r) {
  for (const field of [r.label, r.label2]) {
    const m = clean(field).match(/^E ?(\d{1,3})$/);
    if (m) return `E${m[1]}`;
  }
  for (const token of clean(r.routeraw).split(' ')) {
    const m = token.match(/^E(\d{1,3})$/);
    if (m) return `E${m[1]}`;
  }
  if (clean(r.prefix) === 'E') {
    const n = digits(r.name);
    if (n) return `E${n}`;
  }
  return '';
}

const RULES = [
  // United States: the shield is given by prefix or by level.
  { network: 'usInterstate', ref: (r) => (clean(r.prefix) === 'I' || clean(r.level) === 'Interstate'.toUpperCase()) && digits(r.name) },
  { network: 'usHighway', ref: (r) => (clean(r.prefix) === 'US' || (r.country === 'US' && clean(r.level) === 'FEDERAL')) && digits(r.name) },
  // United Kingdom: national signs come first (A1(M) is a motorway).
  { network: 'ukMotorway', ref: (r) => r.country === 'GB' && /^(M\d{1,3}|A\d{1,4}\(M\))$/.test(firstToken(r.local)) && firstToken(r.local) },
  { network: 'ukARoad', ref: (r) => r.country === 'GB' && /^A\d{1,4}$/.test(firstToken(r.local)) && firstToken(r.local) },
  // Canada: federal and provincial numbered highways share one shield.
  { network: 'canadaHighway', ref: (r) => r.country === 'CA' && ['FEDERAL', 'STATE'].includes(clean(r.level)) && digits(r.name) },
  // Australia has no refs in NE 5.0.0; the rule stays so a later NE release works unchanged.
  { network: 'australia', ref: (r) => r.country === 'AU' && /^(A|M|B|C)\d{1,3}$/.test(firstToken(r.local || r.label)) && firstToken(r.local || r.label) },
  // International E-roads, Europe and beyond.
  { network: 'eRoad', ref: eRoadRef },
  // Anything else with a plain number or code.
  { network: 'generic', ref: (r) => firstToken(r.local) || firstToken(r.label) || digits(r.name) || firstToken(r.name) },
];

/** @returns {{network: keyof typeof NETWORKS, ref: string} | null} null when the road has no usable ref. */
export function normalise(record) {
  for (const rule of RULES) {
    const ref = rule.ref(record);
    if (ref) return { network: rule.network, ref };
  }
  return null;
}
