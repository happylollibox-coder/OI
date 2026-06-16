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
// with its MATCHING orders/spend/clicks/cpc. null when neither window has a positive ROAS.
// Q4 has NO clicks/cpc columns (only spend) — when Q4 wins, clicks/cpc stay null honestly.
export interface PeakLike { ly_net_roas?: number | null; ly_orders?: number | null; ly_spend?: number | null; ly_clicks?: number | null; ly_cpc?: number | null; q4_peak_net_roas?: number | null; q4_peak_orders?: number | null; q4_peak_spend?: number | null }
export function selectPeak(r: PeakLike): { roas: number; orders: number | null; spend: number | null; clicks: number | null; cpc: number | null } | null {
  const ly = r.ly_net_roas ?? 0, q4 = r.q4_peak_net_roas ?? 0;
  const roas = Math.max(ly, q4);
  if (roas <= 0) return null;
  return ly >= q4
    ? { roas, orders: r.ly_orders ?? null, spend: r.ly_spend ?? null, clicks: r.ly_clicks ?? null, cpc: r.ly_cpc ?? null }
    : { roas, orders: r.q4_peak_orders ?? null, spend: r.q4_peak_spend ?? null, clicks: null, cpc: null }; // Q4 has no clicks/cpc
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
  sellableQty?: number | null; // current sellable stock of the advertised ASIN (null = unknown)
  oosDays4w?: number | null;   // OOS days during the 4w measurement window (null = unknown)
}
export interface GateVerdict { clear: boolean; reason: string }

export const GATE = Object.freeze({
  minSpend: 5, minClicks: 10, grayLow: 0.9, grayHigh: 1.1, promoteMinOrders: 2,
  scaleClear: Object.freeze({ GUARDIAN: 1.3, BLITZ: 1.15 }) as Record<string, number>,
  peakGreat: 1.3, peakMinOrders: 3, recovering1w: 1.1,
  oosWindowMax: 7, // OOS days in the 4w measurement window that poisons the data
  negateMinClicks: 20, // §5/§8c: at ~3% CVR, 10 clicks → ~0.3 expected orders; 0 orders isn't signal until ~20 clicks
});

// Act-now actions the cards can represent (keyword/term-level changes in Amazon).
// DELIBERATELY EXCLUDED from cards v1 (different Amazon semantics — not keyword-level):
//   budget actions (GUARDIAN/BLITZ_BUDGET_*), hero swaps (FIX_HERO/SWITCH_HERO),
//   experiment starts (START/START_TERM), placement (REDUCE_TOS), phrase-level
//   (NEGATE_PHRASE handled by the phrase panel, PROMOTE_TO_PEAK_PHRASE seasonal flow).
export const CUT_ACTIONS = new Set(['NEGATE', 'NEGATE_TERM', 'NEGATE_ROAS_THRESHOLD', 'NEGATE_SPEND_THRESHOLD', 'NEGATE_BOOST_SIMILAR_EXACT', 'STOP', 'STOP_TERM', 'STOP_TARGET', 'STOP_SEASONAL']);
export const REDUCE_ACTIONS = new Set(['REDUCE_BID', 'REDUCE_BID_ROAS', 'REDUCE_BID_SPEND', 'REDUCE_TO_BASELINE']);

// Grain of the Amazon entity an action operates on. Cut/negate acts on the shopper
// SEARCH TERM; bid actions act on the KEYWORD/target (an ASIN target = product target).
// Always label this so a "keyword" you bid on is never confused with a "search term" you negate.
export type TermGrain = 'search term' | 'keyword' | 'product target';
export function termGrain(a: { action: string; search_term?: string | null; targeting?: string | null; match_type?: string | null }): TermGrain {
  const isCut = CUT_ACTIONS.has(a.action);
  const usedSearchTerm = isCut ? !!a.search_term : !a.targeting;
  if (usedSearchTerm) return 'search term';
  const mt = (a.match_type || '').toUpperCase();
  const tgt = (a.targeting || '').trim();
  if (mt === 'PRODUCT_TARGETING' || mt.startsWith('ASIN') || /^asin=/i.test(tgt) || /^b0[a-z0-9]{8,}$/i.test(tgt)) return 'product target';
  return 'keyword';
}
// Compact tag for dense rows.
export const termGrainShort = (g: TermGrain): string => g === 'search term' ? 'ST' : g === 'product target' ? 'PT' : 'KW';
const PROMOTE_ACTIONS = new Set(['INCREASE_BID', 'PROMOTE_TO_EXACT', 'SCALE', 'SCALE_UP', 'SCALE_UP_ROAS', 'BOOST']);

// Weekly dollars at stake for a clear case — the owner's "opportunity" and the
// one-week TARGET the receipt loop verifies after upload (FACT_PPC_CHANGE_LOG).
// Facts-anchored (current 4w run rates / 4), not a forecast:
//   cut    (0-order term)        → save = its weekly burn  (spend4w / 4)
//   reduce (losing money)        → save = the weekly loss being stopped (−netProfit4w / 4)
//   promote (winner)             → earn = current weekly profit at stake (netProfit4w / 4) — "scale to beat"
export interface OpportunityInput { action: string; spend4w: number; netProfit4w: number | null; netRoas4w: number | null }
export function opportunityPerWeek(o: OpportunityInput): { kind: 'save' | 'earn'; dollars: number } {
  if (CUT_ACTIONS.has(o.action)) return { kind: 'save', dollars: Math.max(0, o.spend4w) / 4 };
  if (REDUCE_ACTIONS.has(o.action)) {
    const loss = o.netProfit4w != null
      ? Math.max(0, -o.netProfit4w)
      : Math.max(0, o.spend4w * (1 - Math.min(o.netRoas4w ?? 1, 1)));
    return { kind: 'save', dollars: loss / 4 };
  }
  return { kind: 'earn', dollars: Math.max(0, o.netProfit4w ?? 0) / 4 };
}

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
  // OOS guard (owner case 2026-06-12: hero was out of stock → windows showed 0 orders → a wrongly
  // surfaced bid-down). CURRENT stock only — null = unknown = no guard. Reversibility principle:
  //   negate/stop  + OOS → park (the 0-order window may be the empty shelf, and a negative is permanent)
  //   promote      + OOS → park (never scale an empty shelf)
  //   reduce       + OOS → allowed (cutting spend on an empty shelf is right) with a restore-after-restock note
  const oos = g.sellableQty != null && g.sellableQty <= 0;
  // OOS-history guard: product restocked now but was OOS during the 4w measurement window.
  // oosDays4w >= oosWindowMax means the 0-order window is shelf data, not demand data.
  // Reversibility principle mirrors current-OOS guard:
  //   negate/stop  → park (permanent action on poisoned data)
  //   promote      → park (data understates performance; won't scale on incomplete signal)
  //   reduce       → allowed (reversible), but append an OOS note to the clear reason
  const windowPoisoned = (g.oosDays4w ?? 0) >= GATE.oosWindowMax;
  if (isCut) {
    if (oos) return { clear: false, reason: 'product out of stock — the 0-order window may be the empty shelf, not the term; judge after restock' };
    if (windowPoisoned) return { clear: false, reason: `window includes ${g.oosDays4w} out-of-stock days — shelf data, not demand; judge after clean weeks` };
    if (peakGreat) return { clear: false, reason: `weak now but last peak ROAS ${g.peakRoas!.toFixed(2)} (${g.peakOrders} orders) — seasonal: BOOST before next peak, don't cut` };
    if (weekGood) return { clear: false, reason: `this week ROAS ${week!.toFixed(2)} with ${g.orders1w} order(s) — recovering, too early to cut` };
    if (g.orders === 0) {
      if (g.clicks < GATE.negateMinClicks)
        return { clear: false, reason: `only ${g.clicks} clicks — 0 orders isn't conclusive yet (need ~${GATE.negateMinClicks} at ~3% CVR)` };
      return { clear: true, reason: 'real spend, zero orders — nothing to lose' };
    }
    return { clear: false, reason: `${g.orders} order(s) — halo risk, judge manually` };
  }
  if (isReduce) {
    // Owner workflow (2026-06-12): a bid-down is REVERSIBLE — a great peak doesn't block it.
    // Lower now, boost back in the BOOST phase before the next peak. Only negates stay parked.
    const oosNote = oos ? ' (product OOS — restore bid after restock)' : '';
    const windowOosNote = windowPoisoned ? ` (window had ${g.oosDays4w} OOS days)` : '';
    if (weekGood) return { clear: false, reason: `this week ROAS ${week!.toFixed(2)} with ${g.orders1w} order(s) — recovering, too early to cut` };
    if (g.netRoas < GATE.grayLow) {
      if (peakGreat) return { clear: true, reason: `ROAS ${g.netRoas.toFixed(2)} now, but peak ROAS ${g.peakRoas!.toFixed(2)} (${g.peakOrders} orders) — lower now, BOOST back before next peak${oosNote}${windowOosNote}` };
      return { clear: true, reason: `ROAS ${g.netRoas.toFixed(2)} decisively below breakeven${oosNote}${windowOosNote}` };
    }
    if (g.netRoas > GATE.grayHigh) return { clear: false, reason: `ROAS ${g.netRoas.toFixed(2)} above breakeven — conflicts with a bid cut, judge manually` };
    return { clear: false, reason: `ROAS ${g.netRoas.toFixed(2)} inside gray band (${GATE.grayLow}–${GATE.grayHigh}) — too close to call` };
  }
  // promote
  if (oos) return { clear: false, reason: 'product out of stock — don\'t scale an empty shelf; revisit after restock' };
  if (windowPoisoned) return { clear: false, reason: `window includes ${g.oosDays4w} OOS days — performance understated; revisit with clean data` };
  const bar = GATE.scaleClear[g.mode];
  if (bar == null) return { clear: false, reason: `${g.mode} mode never promotes` };
  if (g.orders < GATE.promoteMinOrders) return { clear: false, reason: `${g.orders} order(s) < ${GATE.promoteMinOrders} — winner not proven` };
  if (g.netRoas >= bar) return { clear: true, reason: `ROAS ${g.netRoas.toFixed(2)} clears the ${g.mode} bar (${bar})` };
  return { clear: false, reason: `ROAS ${g.netRoas.toFixed(2)} below the ${g.mode} promote bar (${bar})` };
}
