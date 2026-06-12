// ─── Ads-Coacher in-component logic, extracted pure + TDD'd ──────────────────
// Mirrors the planTypes.ts standard. These were inline memos in ActionsPage.tsx;
// extracted so Phase 2B can extend the ROAS window (7d ad-only / 4w / peak) and
// inject live thresholds without touching the component.

export interface FamilyActual { dailyCost: number; cpc: number; roas: number }

// Minimal structural shapes (avoid importing the heavy DashboardData types here).
export interface DailyTrendLike { date: string; product_type: string; ad_cost?: number; clicks?: number }
export interface ActLike { product_short_name?: string | null; spend?: number; net_roas?: number }
export interface ModeRowLike { product_short_name?: string | null; coach_mode?: string | null }

// Per-family last-week actuals vs the (daily) plan guidelines:
//   • dailyCost + cpc = last 7 distinct trend dates from daily_trends (ad-only), non-overlapping.
//   • roas = last 4w ad-only, spend-weighted over the family's coach term rows (acts) — the only
//     ad-only ROAS currently available (a daily_trends ROAS would be blended/halo).
// Keyed by getFamily(product_short_name) so it matches the family panel's bucket keys exactly.
export function familyActuals(
  acts: ActLike[],
  dailyTrends: DailyTrendLike[],
  getFamily: (name?: string | null) => string | null,
): Map<string, FamilyActual> {
  const dates = [...new Set(dailyTrends.map(r => r.date))].sort();
  // TODO(phase-2b): nDays is a single global window shared across families; a family with sparse
  // coverage in the window gets divided by 7 not its own active-day count. Faithful to the original
  // memo — revisit when adding the multi-window (7d/4w/peak) ROAS.
  const recentDates = new Set(dates.slice(-7)); // last week
  const nDays = recentDates.size || 1;

  const sp = new Map<string, { cost: number; clicks: number }>();
  for (const r of dailyTrends) {
    if (!recentDates.has(r.date)) continue;
    const e = sp.get(r.product_type) ?? { cost: 0, clicks: 0 };
    e.cost += r.ad_cost || 0;
    e.clicks += r.clicks || 0;
    sp.set(r.product_type, e);
  }

  const ro = new Map<string, { spend: number; roasW: number }>();
  for (const a of acts) {
    const fam = getFamily(a.product_short_name);
    if (!fam) continue;
    const s = a.spend || 0;
    const e = ro.get(fam) ?? { spend: 0, roasW: 0 };
    e.spend += s;
    e.roasW += (a.net_roas || 0) * s;
    ro.set(fam, e);
  }

  const out = new Map<string, FamilyActual>();
  for (const fam of new Set([...sp.keys(), ...ro.keys()])) {
    const s = sp.get(fam);
    const r = ro.get(fam);
    out.set(fam, {
      dailyCost: s ? s.cost / nDays : 0,
      cpc: s && s.clicks > 0 ? s.cost / s.clicks : 0,
      roas: r && r.spend > 0 ? r.roasW / r.spend : 0,
    });
  }
  return out;
}

// Most frequent coach_mode across rows; first-seen wins on a tie; GUARDIAN when there are none.
export function dominantMode(rows: { coach_mode?: string | null }[]): string {
  const counts: Record<string, number> = {};
  for (const r of rows) if (r.coach_mode) counts[r.coach_mode] = (counts[r.coach_mode] || 0) + 1;
  return Object.entries(counts).sort((a, b) => b[1] - a[1])[0]?.[0] || 'GUARDIAN';
}

// Per-family dominant coach mode, keyed by getFamily(product_short_name) so it lines up with the
// family panel's bucket keys. Replaces the previous global-mode-for-every-family behaviour.
export function familyModes(
  rows: ModeRowLike[],
  getFamily: (name?: string | null) => string | null,
): Map<string, string> {
  const byFam = new Map<string, { coach_mode?: string | null }[]>();
  for (const r of rows) {
    const fam = getFamily(r.product_short_name);
    if (!fam || !r.coach_mode) continue;
    const arr = byFam.get(fam);
    if (arr) arr.push(r); else byFam.set(fam, [r]);
  }
  const out = new Map<string, string>();
  for (const [family, frows] of byFam) out.set(family, dominantMode(frows));
  return out;
}

// Best peak evidence for a row: the stronger of last-year-peak and Q4-peak ROAS,
// with its MATCHING orders. null when neither window has a positive ROAS.
export interface PeakLike { ly_net_roas?: number | null; ly_orders?: number | null; q4_peak_net_roas?: number | null; q4_peak_orders?: number | null }
export function selectPeak(r: PeakLike): { roas: number; orders: number | null } | null {
  const ly = r.ly_net_roas ?? 0, q4 = r.q4_peak_net_roas ?? 0;
  const roas = Math.max(ly, q4);
  if (roas <= 0) return null;
  return { roas, orders: ly >= q4 ? (r.ly_orders ?? null) : (r.q4_peak_orders ?? null) };
}

// ─── Stage-1 clear-case selector (spec §7 confidence gate, client-side) ──────
// Decides whether an action is a CLEAR case (surface as a decision card) or parked
// ("needs judgment"). Facts only — uses the engine's own 4w fields. Direct net ROAS
// carries NO organic/repeat halo, so: zero-conversion negates are the cleanest cut;
// negates on terms WITH orders are parked (halo risk); promotes need a margin above
// the mode's display bar (GUARDIAN 1.30 / BLITZ 1.15 / COOLDOWN never).
// Migrates into V_ADS_COACH_DECISION at Stage 3 — keep it dumb and tunable.
export interface GateInput {
  action: string; spend: number; clicks: number; orders: number;
  netRoas: number; mode: string; confidence: string;
  roas1w?: number | null; orders1w?: number | null;
  peakRoas?: number | null; peakOrders?: number | null;
}
export interface GateVerdict { clear: boolean; reason: string }

export const GATE = Object.freeze({
  minSpend: 5, minClicks: 10, grayLow: 0.9, grayHigh: 1.1, promoteMinOrders: 2,
  scaleClear: Object.freeze({ GUARDIAN: 1.3, BLITZ: 1.15 }) as Record<string, number>,
  peakGreat: 1.3, peakMinOrders: 3, recovering1w: 1.1,
});

// Act-now actions the cards can represent (keyword/term-level changes in Amazon).
// DELIBERATELY EXCLUDED from cards v1 (different Amazon semantics — not keyword-level):
//   budget actions (GUARDIAN/BLITZ_BUDGET_*), hero swaps (FIX_HERO/SWITCH_HERO),
//   experiment starts (START/START_TERM), placement (REDUCE_TOS), phrase-level
//   (NEGATE_PHRASE handled by the phrase panel, PROMOTE_TO_PEAK_PHRASE seasonal flow).
export const CUT_ACTIONS = new Set(['NEGATE', 'NEGATE_TERM', 'NEGATE_ROAS_THRESHOLD', 'NEGATE_SPEND_THRESHOLD', 'NEGATE_BOOST_SIMILAR_EXACT', 'STOP', 'STOP_TERM', 'STOP_TARGET', 'STOP_SEASONAL']);
export const REDUCE_ACTIONS = new Set(['REDUCE_BID', 'REDUCE_BID_ROAS', 'REDUCE_BID_SPEND', 'REDUCE_TO_BASELINE']);
const PROMOTE_ACTIONS = new Set(['INCREASE_BID', 'PROMOTE_TO_EXACT', 'SCALE', 'SCALE_UP', 'SCALE_UP_ROAS', 'BOOST']);

export function clearCase(g: GateInput): GateVerdict {
  const isCut = CUT_ACTIONS.has(g.action);
  const isReduce = REDUCE_ACTIONS.has(g.action);
  const isPromote = PROMOTE_ACTIONS.has(g.action);
  if (!isCut && !isReduce && !isPromote) return { clear: false, reason: 'not an act-now action' };
  if (g.confidence !== 'HIGH') return { clear: false, reason: `${g.confidence} confidence — needs more data to act automatically` };
  if (g.spend < GATE.minSpend) return { clear: false, reason: `spend $${g.spend.toFixed(0)} < $${GATE.minSpend} floor` };
  if (g.clicks < GATE.minClicks) return { clear: false, reason: `${g.clicks} clicks < ${GATE.minClicks} floor` };
  // Owner three-window rule: applied before CUT and REDUCE verdicts fire.
  // peakGreat: weak now but GREAT last peak → seasonal, boost before peak — never cut.
  // recovering1w: this week already good → recovering, too early to cut.
  const peakGreat = (g.peakRoas ?? 0) >= GATE.peakGreat && (g.peakOrders ?? 0) >= GATE.peakMinOrders;
  const week = g.roas1w;
  const weekGood = week != null && week >= GATE.recovering1w && (g.orders1w ?? 0) > 0;
  if (isCut) {
    if (peakGreat) return { clear: false, reason: `weak now but last peak ROAS ${g.peakRoas!.toFixed(2)} (${g.peakOrders} orders) — seasonal: BOOST before next peak, don't cut` };
    if (weekGood) return { clear: false, reason: `this week ROAS ${week!.toFixed(2)} with ${g.orders1w} order(s) — recovering, too early to cut` };
    if (g.orders === 0) return { clear: true, reason: 'real spend, zero orders — nothing to lose' };
    return { clear: false, reason: `${g.orders} order(s) — halo risk, judge manually` };
  }
  if (isReduce) {
    if (peakGreat) return { clear: false, reason: `weak now but last peak ROAS ${g.peakRoas!.toFixed(2)} (${g.peakOrders} orders) — seasonal: BOOST before next peak, don't cut` };
    if (weekGood) return { clear: false, reason: `this week ROAS ${week!.toFixed(2)} with ${g.orders1w} order(s) — recovering, too early to cut` };
    if (g.netRoas < GATE.grayLow) return { clear: true, reason: `ROAS ${g.netRoas.toFixed(2)} decisively below breakeven` };
    if (g.netRoas > GATE.grayHigh) return { clear: false, reason: `ROAS ${g.netRoas.toFixed(2)} above breakeven — conflicts with a bid cut, judge manually` };
    return { clear: false, reason: `ROAS ${g.netRoas.toFixed(2)} inside gray band (${GATE.grayLow}–${GATE.grayHigh}) — too close to call` };
  }
  // promote
  const bar = GATE.scaleClear[g.mode];
  if (bar == null) return { clear: false, reason: `${g.mode} mode never promotes` };
  if (g.orders < GATE.promoteMinOrders) return { clear: false, reason: `${g.orders} order(s) < ${GATE.promoteMinOrders} — winner not proven` };
  if (g.netRoas >= bar) return { clear: true, reason: `ROAS ${g.netRoas.toFixed(2)} clears the ${g.mode} bar (${bar})` };
  return { clear: false, reason: `ROAS ${g.netRoas.toFixed(2)} below the ${g.mode} promote bar (${bar})` };
}
