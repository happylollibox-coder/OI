// ─── Shared Plan Page types ─────────────────────────────────
// Extracted so PlanWizard and PlanPage can share them.

export interface ForecastMonthData { roas: number; adSpend: number }
export type ForecastRoasMap = Record<string, Record<number, ForecastMonthData>>;

export type ForecastDemandMap = Record<string, Record<number, number>>;

export interface ForecastProductMeta { isNew: boolean; isDraft: boolean; share: number; family: string; forecastPhase?: string; modelProduct?: string }
export type ForecastMetaMap = Record<string, ForecastProductMeta>;

export interface MonthSeasonInfo { peakDays: number; offseasonDays: number; holidays: string | null }
export type MonthSeasonMap = Record<string, Record<number, MonthSeasonInfo>>; // family → yearMonth → info

export interface AdsEfficiencyMonth {
  cpc: number; unitCvrPct: number; adsSharePct: number; netRoas: number;
  forecastUnits: number; suggestedSpend: number;
  currentSpend: number; currentForecastUnits: number; currentDailySpend: number;
  currentCpc: number; currentNetProfit: number; targetNetProfit: number;
}
export type AdsEfficiencyMap = Record<string, Record<number, AdsEfficiencyMonth>>;

export interface VarBaseline {
  name: string; asin: string; family: string; splitPct: number;
  dailySpend: number; dailyOrders: number; adsShare: number;
  asp: number; costPerUnit: number; mfrCost: number; shipCost: number;
  inventory: number; inventoryBySource: Record<string, number>;
  yoyGrowth: number; cartonQty: number;
  mfrDays: number; shipDays: number;
}

export interface FamilyBaseline {
  family: string; dailySpend: number; dailyOrders: number; adsShare: number;
  asp: number; costPerUnit: number; inventory: number;
  inventoryBySource: Record<string, number>; seasonalityIndex: number[];
  variations: VarBaseline[];
}

export interface MonthProj {
  month: string; key: string; days: number;
  families: Record<string, { demand: number; revenue: number; cogs: number; adSpend: number; netProfit: number; invEnd: number; isOos: boolean;
    vars: Record<string, { demand: number; revenue: number; cogs: number; adSpend: number; netProfit: number; invEnd: number; isOos: boolean }>;
  }>;
  totalDemand: number; totalRevenue: number; totalCogs: number; totalAdSpend: number; totalNetProfit: number;
}

export interface MonthDef {
  key: string; label: string; days: number; year: number; month: number;
}

// MFR / SHIP cost maps (per product name)
export const MFR: Record<string, number> = {
  'White Lollibox': 12.53, 'Purple Lollibox': 11.94, 'Pink Lollibox': 11.28, 'Blue Lollibox': 12.96,
  'Mint LolliME': 7.14, 'Pink LolliME': 7.14, 'Purple LolliME': 7.14,
  'Fresh in Pink': 10.81, 'Fresh in Beige': 10.47, 'Fresh in Blue': 10.81, 'Fresh in Purple': 10.81,
  'Truth Or Dare': 5.21,
};
export const SHIP: Record<string, number> = {
  'White Lollibox': 2.51, 'Purple Lollibox': 1.90, 'Pink Lollibox': 1.89, 'Blue Lollibox': 2.14,
  'Mint LolliME': 1.90, 'Pink LolliME': 1.90, 'Purple LolliME': 1.90,
  'Fresh in Pink': 2.85, 'Fresh in Beige': 2.90, 'Fresh in Blue': 2.85, 'Fresh in Purple': 2.85,
  'Truth Or Dare': 0.82,
};

// ─── Monthly plan helpers ───────────────────────────────────
export const MONTH_ABBR = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

// Snapshot/MonthDef key for a calendar month, e.g. monthKey(5, 2026) === "may26".
export function monthKey(mo: number, yr: number): string {
  return `${MONTH_ABBR[mo - 1]}${String(yr).slice(2)}`;
}

// Reduce saved Ads-Coach targets (per channel × year-month) into monthly ad spend and a
// spend-weighted CPC, both keyed by monthKey. Spend = daily_spend_target × days-in-month.
// Shared by the PlanPage loader (reads from the server) and the wizard's onSave optimistic
// update (writes the same shape locally), so the two can never drift apart.
export function aggregateAdsTargetSpend(
  targets: { yr: number; mo: number; daily_spend_target?: number; cpc_target?: number }[],
): { spendByMonth: Record<string, number>; cpcByMonth: Record<string, number> } {
  const spendByMonth: Record<string, number> = {};
  const cpcNum: Record<string, number> = {};
  const cpcDen: Record<string, number> = {};
  for (const t of targets) {
    const k = monthKey(t.mo, t.yr);
    const days = new Date(t.yr, t.mo, 0).getDate();
    const spend = (t.daily_spend_target || 0) * days;
    spendByMonth[k] = (spendByMonth[k] ?? 0) + spend;
    const cpc = t.cpc_target ?? 0;
    if (cpc > 0 && spend > 0) { cpcNum[k] = (cpcNum[k] ?? 0) + cpc * spend; cpcDen[k] = (cpcDen[k] ?? 0) + spend; }
  }
  const cpcByMonth: Record<string, number> = {};
  for (const k of Object.keys(cpcDen)) cpcByMonth[k] = cpcNum[k] / cpcDen[k];
  return { spendByMonth, cpcByMonth };
}

// Fraction of each calendar month covered by the inclusive date range [startISO, endISO].
// Keyed by monthKey (e.g. "may26"). Used to prorate a monthly plan over an arbitrary period.
export function monthFractions(startISO: string, endISO: string): Record<string, number> {
  const start = new Date(startISO + 'T00:00:00');
  const end = new Date(endISO + 'T00:00:00');
  const out: Record<string, number> = {};
  const cur = new Date(start.getFullYear(), start.getMonth(), 1);
  while (cur <= end) {
    const y = cur.getFullYear(), m = cur.getMonth();
    const daysInMonth = new Date(y, m + 1, 0).getDate();
    const mStart = new Date(y, m, 1), mEnd = new Date(y, m, daysInMonth);
    const lo = start > mStart ? start : mStart;
    const hi = end < mEnd ? end : mEnd;
    const days = Math.round((hi.getTime() - lo.getTime()) / 86400000) + 1;
    if (days > 0) out[monthKey(m + 1, y)] = days / daysInMonth;
    cur.setMonth(cur.getMonth() + 1);
  }
  return out;
}

// Σ monthlyMap[k] × fractions[k] — prorate a monthly series over a period.
export function sumOverPeriod(monthlyMap: Record<string, number>, fractions: Record<string, number>): number {
  let s = 0;
  for (const [k, frac] of Object.entries(fractions)) s += (monthlyMap[k] ?? 0) * frac;
  return s;
}

// Plan net profit for a period given prorated plan units, family margin, and prorated plan spend.
export function netProfitPlan(planUnits: number, margin: number, planSpend: number): number {
  return planUnits * margin - planSpend;
}

// Blended (organic-inclusive) Net ROAS over a set of {sales,cogs,adCost} rows.
// (Σsales − Σcogs) / ΣadCost; null when there's no ad spend.
export function blendedNetRoas(rows: { sales: number; cogs: number; adCost: number }[]): number | null {
  let s = 0, c = 0, a = 0;
  for (const r of rows) { s += r.sales; c += r.cogs; a += r.adCost; }
  return a > 0 ? (s - c) / a : null;
}

// [Mon, Sun] ISO dates of the (stepsBack)-th most recent COMPLETE week before `today`.
// stepsBack=0 → the latest fully-elapsed Mon–Sun week; stepsBack=1 → the week before that.
export function latestCompleteWeekRange(today: Date, stepsBack: number): [string, string] {
  const d = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const dow = (d.getDay() + 6) % 7; // 0 = Monday
  const thisMonday = new Date(d); thisMonday.setDate(d.getDate() - dow);
  const sun = new Date(thisMonday); sun.setDate(thisMonday.getDate() - 1 - 7 * stepsBack); // last complete week's Sunday
  const mon = new Date(sun); mon.setDate(sun.getDate() - 6);
  const iso = (x: Date) => `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
  return [iso(mon), iso(sun)];
}

export interface MonthlyPlan { byMonth: Record<string, number>; total: number }

// Merge actual (elapsed + current-MTD) over forecast (current-remainder + future) across an
// ordered set of month keys. Additive: the current month's actual-MTD and forecast-remainder
// are disjoint slices, so summing is correct everywhere.
export function composeMonthlyPlan(
  orderedKeys: string[],
  actualByMonth: Record<string, number>,
  forecastByMonth: Record<string, number>,
): MonthlyPlan {
  const byMonth: Record<string, number> = {};
  let total = 0;
  for (const k of orderedKeys) {
    const u = (actualByMonth[k] ?? 0) + (forecastByMonth[k] ?? 0);
    byMonth[k] = u;
    total += u;
  }
  return { byMonth, total };
}

// Split a family's per-month trajectory into per-product per-month forecast.
// The family month total `t.totalUnits` (which carries the chosen ad-spend level AND seasonality)
// is distributed by each product's OWN runSim demand share for that month:
//   forecast[p][mo] = t.totalUnits × ( runSim[p][mo] / Σ runSim[·][mo] )
// Seasonality is counted ONCE — it lives in t.totalUnits; the per-product share is a dimensionless
// ratio (per-product seasonal share shifts are preserved, not multiplied in again). Falls back to
// the static splitPct (then equal split) when a month has no runSim demand. Excludes isActual
// slices (current-month MTD comes from real actuals downstream) and months outside the horizon.
export function splitTrajectoryToProducts(
  trajectory: { mo: number; yr: number; totalUnits: number; isActual?: boolean }[],
  variations: { name: string; splitPct: number }[],
  inHorizon: (mo: number, yr: number) => boolean,
  runSimUnits: (name: string, mo: number, yr: number) => number,
): Record<string, Record<string, number>> {
  const flatTotal = variations.reduce((s, v) => s + (v.splitPct > 0 ? v.splitPct : 0), 0);
  const n = variations.length;
  const out: Record<string, Record<string, number>> = {};
  for (const v of variations) out[v.name] = {};
  for (const t of trajectory) {
    if (t.isActual) continue;
    if (!inHorizon(t.mo, t.yr)) continue;
    const key = monthKey(t.mo, t.yr);
    const sim = variations.map(v => Math.max(0, runSimUnits(v.name, t.mo, t.yr)));
    const simTotal = sim.reduce((a, b) => a + b, 0);
    variations.forEach((v, i) => {
      const share = simTotal > 0
        ? sim[i] / simTotal                                              // per-month runSim share
        : flatTotal > 0 ? (v.splitPct > 0 ? v.splitPct : 0) / flatTotal  // fallback: static split
        : n > 0 ? 1 / n : 0;                                             // fallback: equal
      out[v.name][key] = (out[v.name][key] ?? 0) + t.totalUnits * share;
    });
  }
  return out;
}

// ─── Wizard-sourced forecast (effectiveProjs) ───────────────
// Substitute the wizard's saved plan into a runSim MonthProj[]: planned families get units from
// `plannedUnits` (per product × monthKey), revenue/cogs from units×asp/cost, family ad spend from
// `plannedSpend` (per family × monthKey), and P&L reconstructed. Unplanned families pass the runSim
// entry through unchanged. Inventory carries sequentially across months (planned products only).
// Per-product ad spend is a units-share allocation of the family spend — display-only, NOT a real
// per-variation signal. A planned product missing a given month falls back to that month's runSim demand.
type EffFamily = {
  family: string; asp: number; costPerUnit: number;
  variations: { name: string; asp: number; costPerUnit: number; inventory: number }[];
};
export function buildEffectiveProjs(
  projs: MonthProj[],
  plannedUnits: Record<string, Record<string, number>>,
  plannedSpend: Record<string, Record<string, number>>,
  families: EffFamily[],
  isPlanned: (family: string) => boolean,
): MonthProj[] {
  const famByName = new Map(families.map(f => [f.family, f]));
  const curInv: Record<string, number> = {};
  for (const f of families) for (const v of f.variations) curInv[v.name] = v.inventory;

  return projs.map(p => {
    const familiesData: MonthProj['families'] = {};
    let tD = 0, tR = 0, tC = 0, tA = 0, tN = 0;
    for (const [fam, fd] of Object.entries(p.families)) {
      const fb = famByName.get(fam);
      if (!fb || !isPlanned(fam)) {
        familiesData[fam] = fd; // runSim passthrough
        tD += fd.demand; tR += fd.revenue; tC += fd.cogs; tA += fd.adSpend; tN += fd.netProfit;
        continue;
      }
      const familyAd = plannedSpend[fam]?.[p.key] ?? 0;
      const unitsByV: Record<string, number> = {};
      let famUnits = 0;
      for (const v of fb.variations) {
        const u = plannedUnits[v.name]?.[p.key] ?? fd.vars[v.name]?.demand ?? 0;
        unitsByV[v.name] = u; famUnits += u;
      }
      const vars: MonthProj['families'][string]['vars'] = {};
      let fDemand = 0, fRev = 0, fCogs = 0, fAd = 0, fNp = 0, fInvEnd = 0;
      for (const v of fb.variations) {
        const u = unitsByV[v.name];
        const asp = v.asp > 0 ? v.asp : fb.asp;
        const cpu = v.costPerUnit > 0 ? v.costPerUnit : fb.costPerUnit;
        const rev = u * asp, cog = u * cpu;
        const ad = famUnits > 0 ? familyAd * (u / famUnits) : 0; // display-only allocation
        const np = rev - cog - ad;
        const prev = curInv[v.name] ?? 0;
        const ie = Math.max(0, prev - u);
        curInv[v.name] = ie;
        vars[v.name] = { demand: u, revenue: rev, cogs: cog, adSpend: ad, netProfit: np, invEnd: ie, isOos: prev - u <= 0 };
        fDemand += u; fRev += rev; fCogs += cog; fAd += ad; fNp += np; fInvEnd += ie;
      }
      familiesData[fam] = { demand: fDemand, revenue: fRev, cogs: fCogs, adSpend: fAd, netProfit: fNp, invEnd: fInvEnd, isOos: fInvEnd <= 0, vars };
      tD += fDemand; tR += fRev; tC += fCogs; tA += fAd; tN += fNp;
    }
    return { ...p, families: familiesData, totalDemand: tD, totalRevenue: tR, totalCogs: tC, totalAdSpend: tA, totalNetProfit: tN };
  });
}

// ─── Order allocation ───────────────────────────────────────
export interface OrderAllocation { byProduct: Record<string, number>; total: number; totalGap: number }

// Split a family order across products by each product's own GAP — its demand-share of the
// family forecast MINUS its own current stock — then round each UP to a whole buy-unit
// (carton, or next 100 in friendly mode). Splitting by gap (not raw demand share) respects
// uneven per-variation stock: a colour already overstocked orders ~0 even if it sells well.
// `target` scales the gaps (default = totalGap → order ≈ each product's exact gap).
export function allocateOrder(
  variations: Pick<VarBaseline, 'name' | 'splitPct' | 'cartonQty' | 'inventory'>[],
  target: number,
  forecastTotal: number,
  friendly: boolean,
  // Per-product forecast demand (velocity-shaped, e.g. from splitTrajectoryToProducts). When given,
  // each product's gap is forecastByProduct[name] − stock. Falls back to forecastTotal × splitPct
  // when omitted or missing a product — needed because static splitPct misallocates demand across
  // variations whose forward velocity differs from their historical sales share.
  forecastByProduct?: Record<string, number>,
): OrderAllocation {
  const n = variations.length;
  // Equal split only when NO product has share data; otherwise a genuine 0% stays 0%.
  const totalShare = variations.reduce((s, v) => s + (v.splitPct > 0 ? v.splitPct : 0), 0);
  const gaps = variations.map(v => {
    const fcst = forecastByProduct && forecastByProduct[v.name] != null
      ? forecastByProduct[v.name]
      : forecastTotal * (totalShare > 0 ? (v.splitPct > 0 ? v.splitPct : 0) : (n > 0 ? 1 / n : 0));
    return Math.max(0, fcst - (v.inventory ?? 0));
  });
  const totalGap = gaps.reduce((a, b) => a + b, 0);
  const byProduct: Record<string, number> = {};
  let total = 0;
  variations.forEach((v, i) => {
    const w = totalGap > 0 ? gaps[i] / totalGap : 0;
    const raw = target * w;
    const step = friendly ? 100 : (v.cartonQty > 0 ? v.cartonQty : 1);
    const qty = raw > 0 ? Math.ceil(raw / step) * step : 0;
    byProduct[v.name] = qty;
    total += qty;
  });
  return { byProduct, total, totalGap };
}

// ─── New-product off-season forecast ───────────────────────
// For products launched mid-prior-year, YoY (LY × growth) collapses to ~0 in months the
// product didn't yet exist. Instead derive demand from the product's OWN within-year
// off-season momentum: a recent off-season run-rate (units/day), trended by how it compares
// to the prior off-season window — never using the unsteady first-3-months launch period.
// Monthly grain: "recent" = most recent completed off-season month; "prior" = the 2 before it.
export interface OffSeasonTrendResult {
  usable: boolean;        // true when there's ≥1 post-warmup off-season month with data
  recentRate: number;     // off-season units/day, most recent window
  priorRate: number;      // off-season units/day, prior 2-month window (0 if none)
  momentum: number;       // clamp(recentRate/priorRate, 0.5, 1.8); 1 when no prior window
  launch: { year: number; month: number } | null; // detected launch month (warmup = launch..+2)
  forecastUnits: (year: number, month: number) => number; // units for a missing-LY off-season month
}

export function offSeasonTrend(
  history: { year: number; month: number; units: number }[],
  isOffSeason: (year: number, month: number) => boolean,
  launch: { year: number; month: number } | null,
  cutoff: { year: number; month: number; prorate: number },
): OffSeasonTrendResult {
  const ord = (y: number, m: number) => y * 12 + (m - 1);
  const daysInMonth = (y: number, m: number) => new Date(y, m, 0).getDate();
  const cutoffOrd = ord(cutoff.year, cutoff.month);

  // Launch month = explicit, else earliest month with any sales. Warmup = launch + next 2.
  let launchOrd = launch ? ord(launch.year, launch.month) : null;
  if (launchOrd == null) {
    const sold = history.filter(d => d.units > 0).map(d => ord(d.year, d.month));
    launchOrd = sold.length ? Math.min(...sold) : null;
  }
  const warmupEnd = launchOrd != null ? launchOrd + 2 : -Infinity;
  const launchOut = launchOrd != null ? { year: Math.floor(launchOrd / 12), month: (launchOrd % 12) + 1 } : null;

  // Post-warmup off-season months that have data (≤ cutoff), most recent first.
  // Post-warmup off-season months with data (≤ cutoff), chronological (ascending).
  const usable = history
    .filter(d => {
      const o = ord(d.year, d.month);
      return o > warmupEnd && o <= cutoffOrd && isOffSeason(d.year, d.month);
    })
    .map(d => {
      const o = ord(d.year, d.month);
      const days = daysInMonth(d.year, d.month) * (o === cutoffOrd ? cutoff.prorate : 1);
      return { o, units: d.units, days };
    })
    .filter(d => d.days > 0)
    .sort((a, b) => a.o - b.o);

  if (usable.length === 0) {
    return { usable: false, recentRate: 0, priorRate: 0, momentum: 1, launch: launchOut, forecastUnits: () => 0 };
  }

  // Split the usable off-season months into a first (earlier) and second (later) period.
  // momentum = 2nd-period daily rate / 1st-period daily rate. A single period → no trend.
  const mid = Math.floor(usable.length / 2);
  const first = usable.slice(0, mid);
  const second = usable.slice(mid);
  const rate = (arr: typeof usable) => {
    const d = arr.reduce((s, x) => s + x.days, 0);
    return d > 0 ? arr.reduce((s, x) => s + x.units, 0) / d : 0;
  };
  const midOrd = (arr: typeof usable) => arr.reduce((s, x) => s + x.o, 0) / arr.length;
  const secondRate = rate(second);
  const firstRate = first.length ? rate(first) : 0;
  const momentum = firstRate > 0 ? Math.min(1.8, Math.max(0.5, secondRate / firstRate)) : 1;
  // Spread the period-to-period momentum across the months between the period midpoints, so it's a
  // per-month growth rate (not re-compounded monthly) — avoids explosive extrapolation.
  const gap = first.length ? Math.max(1, midOrd(second) - midOrd(first)) : 1;
  const g = Math.pow(momentum, 1 / gap);
  const anchorOrd = usable[usable.length - 1].o; // most recent off-season month with data

  const forecastUnits = (year: number, month: number) => {
    if (!(secondRate > 0)) return 0;
    const k = Math.max(0, ord(year, month) - anchorOrd);
    return Math.round(secondRate * daysInMonth(year, month) * Math.pow(g, k));
  };

  return { usable: true, recentRate: secondRate, priorRate: firstRate, momentum, launch: launchOut, forecastUnits };
}

// ─── Ads Path: 2025-anchored profit-max spend ───────────────
// Units a month sells at ad spend `S`, anchored to prior-year (spend0, units0) with
// season elasticity e (<1): units(S) = units0 × (S/spend0)^e. Total units (incl. organic
// halo) scale with spend — at S = spend0 it returns exactly units0 (reproduces history).
export function unitsAtSpend(spend: number, units0: number, spend0: number, e: number): number {
  if (spend0 <= 0 || units0 <= 0 || spend <= 0) return 0;
  return units0 * Math.pow(spend / spend0, e);
}

// Profit-maximizing monthly ad spend — the point where the next dollar returns exactly $1
// of net profit (marginal ROAS = 1): margin · dUnits/dS = 1.
//   S* = ((units0 · margin · e) / spend0^e)^(1/(1-e)), clamped to [0, capMultiple × spend0].
// Returns null when there's no usable 2025 anchor (caller should fall back to the demand forecast).
export function profitMaxSpend(
  units0: number, spend0: number, margin: number, e: number, capMultiple = 3,
): number | null {
  if (spend0 <= 0 || units0 <= 0 || margin <= 0 || e <= 0 || e >= 1) return null;
  const sStar = Math.pow((units0 * margin * e) / Math.pow(spend0, e), 1 / (1 - e));
  return Math.max(0, Math.min(sStar, capMultiple * spend0));
}

// Per-month plan entry the Ads Path curve scales. mo is 1-based calendar month.
export interface HorizonPlanMonth { mo: number; spend: number; units: number; units0: number; spend0: number; anchored: boolean; e: number }

// Σ {spend, units} over the horizon `months` at scale k. The current calendar month (curMoIdx,
// 0-based; -1 = none) contributes only its remaining-days fraction remFrac (spend AND units),
// so totals are forecast-remaining for the current month. Anchored months re-derive units off
// the 2025 anchor via unitsAtSpend; unanchored scale linearly.
export function scaleHorizonPlan(
  plan: HorizonPlanMonth[],
  months: { month: number }[],
  k: number,
  curMoIdx: number,
  remFrac: number,
): { spend: number; units: number } {
  let spend = 0, units = 0;
  for (const m of months) {
    const p = plan.find(x => x.mo === m.month);
    if (!p) continue;
    const s = p.spend * k;
    const u = p.anchored && p.spend0 > 0 ? unitsAtSpend(s, p.units0, p.spend0, p.e) : p.units * k;
    const frac = (m.month - 1) === curMoIdx ? remFrac : 1;
    spend += s * frac;
    units += u * frac;
  }
  return { spend, units };
}

// Two-phase launch order for a just-launched family. Phase 1 = a 90-day launch buy at the early
// run-rate (placed now); Phase 2 = the rest-of-horizon restock (an estimate placed ~1 month later).
// `inventory` is the total pipeline (sellable + on-order), subtracted once — Phase 2 nets out Phase 1
// and stock so the two never double-count. Quantities round up to whole cartons (or next 100 when
// `friendly`). A product with rate 0 (< 3 selling days) gets Phase 1 = 0 (the manual seed PO covers it).
export function launchOrderPhases(
  variations: { name: string; inventory: number; cartonQty: number }[],
  runRatePerProduct: Record<string, number>,
  forecastByProduct: Record<string, number>,
  friendly: boolean,
): { phase1: Record<string, number>; phase2: Record<string, number>; phase1Total: number; phase2Total: number } {
  const ceilTo = (x: number, c: number) => {
    if (x <= 0) return 0;
    const step = friendly ? 100 : (c > 0 ? c : 1);
    return Math.ceil(x / step) * step;
  };
  const phase1: Record<string, number> = {};
  const phase2: Record<string, number> = {};
  let phase1Total = 0, phase2Total = 0;
  for (const v of variations) {
    const inv = v.inventory ?? 0;
    const rate = runRatePerProduct[v.name] ?? 0;
    const p1 = ceilTo(rate * 90 - inv, v.cartonQty);
    const restOfYear = forecastByProduct[v.name] ?? 0;
    const p2 = ceilTo(restOfYear - inv - p1, v.cartonQty);
    phase1[v.name] = p1; phase2[v.name] = p2;
    phase1Total += p1; phase2Total += p2;
  }
  return { phase1, phase2, phase1Total, phase2Total };
}

// Day-of-month through which we have *actual* current-month data — derived from the real latest
// data date (e.g. FACT_AMAZON_PERFORMANCE_DAILY's max date) instead of a wall-clock lag guess.
// This is the numerator of the current-month proration (cutoffDay / daysInMonth).
//   - latestDataDate in the current (year, month) → its day-of-month (e.g. Jun 4 → 4).
//   - latestDataDate in an earlier month (current month has no data yet) → 1 (never /0).
//   - missing/invalid latestDataDate → fallbackDay (caller passes today − lag, clamped ≥ 1).
// `month` is 1-based.
export function dataCutoffDay(
  latestDataDate: Date | null | undefined,
  year: number,
  month: number,
  fallbackDay: number,
): number {
  const fb = Math.max(1, fallbackDay);
  if (latestDataDate && !isNaN(latestDataDate.getTime())) {
    const ly = latestDataDate.getFullYear();
    const lm = latestDataDate.getMonth() + 1;
    if (ly === year && lm === month) return Math.max(1, latestDataDate.getDate());
    if (ly < year || (ly === year && lm < month)) return 1; // no current-month data yet
    return fb; // beyond current month (shouldn't happen) → fall back
  }
  return fb;
}

// Recency-weighted daily run-rate from the last N complete weekly totals.
// weeklyTotals[0] = most recent complete week's total, [1] = the week before, …
// Default weights bias the last 4 weeks 40/30/20/10. Each week is 7 days, so dividing
// every bucket by 7 yields a per-day rate; missing buckets contribute 0.
export function weightedRunRate(weeklyTotals: number[], weights: number[] = [0.4, 0.3, 0.2, 0.1]): number {
  let rate = 0;
  for (let i = 0; i < weights.length; i++) rate += weights[i] * ((weeklyTotals[i] ?? 0) / 7);
  return rate;
}

// Per-family planned ad targets for one month, blended across ad channels (Brand + Non-brand).
// dailyCost = Σ planned daily ad spend; cpc/roas = spend-weighted across channels. Lets the Ads
// Coacher see "what the plan says this month" (planned ad cost, CPC, ROAS) next to actuals.
export interface PlanAdsTargetLike {
  family: string; yr: number; mo: number;
  daily_spend_target: number; cpc_target: number; predicted_roas: number;
}
export function monthlyPlanTargets(
  rows: PlanAdsTargetLike[], year: number, month: number,
): Map<string, { dailyCost: number; cpc: number; roas: number }> {
  const acc = new Map<string, { dailyCost: number; cpcW: number; roasW: number }>();
  for (const r of rows) {
    if (r.yr !== year || r.mo !== month) continue;
    const a = acc.get(r.family) ?? { dailyCost: 0, cpcW: 0, roasW: 0 };
    const spend = r.daily_spend_target || 0;
    a.dailyCost += spend;
    a.cpcW += (r.cpc_target || 0) * spend;     // spend-weighted CPC numerator
    a.roasW += (r.predicted_roas || 0) * spend; // spend-weighted ROAS numerator
    acc.set(r.family, a);
  }
  const out = new Map<string, { dailyCost: number; cpc: number; roas: number }>();
  for (const [fam, a] of acc) {
    out.set(fam, {
      dailyCost: a.dailyCost,
      cpc: a.dailyCost > 0 ? a.cpcW / a.dailyCost : 0,
      roas: a.dailyCost > 0 ? a.roasW / a.dailyCost : 0,
    });
  }
  return out;
}

// Compare an actual value to its plan target. Returns the signed % difference and a status:
// 'over' (above plan beyond tolerance), 'under' (below), 'on' (within ±tol), 'none' (no plan).
// The caller decides colour per metric — for spend/CPC "over" is bad, for ROAS "over" is good.
export function planDelta(
  actual: number, plan: number, tol = 0.1,
): { pct: number | null; status: 'over' | 'under' | 'on' | 'none' } {
  if (!plan || plan <= 0) return { pct: null, status: 'none' };
  const pct = actual / plan - 1;
  const status = pct > tol ? 'over' : pct < -tol ? 'under' : 'on';
  return { pct, status };
}

// Stockout-corrected run-rate: like weightedRunRate, but it ignores weeks where the product was
// out of stock so the rate reflects true demand (what it sells when on the shelf), not the supply
// throttle. `weeks` is most-recent-first, each tagged with how many days that week the product was
// in stock. A week counts as "healthy" only if it was in stock at least `minInStockDays` days; the
// most-recent N healthy weeks are recency-weighted (weights renormalized to however many exist).
// A fully-in-stock product is unchanged (every recent week is healthy → identical to weightedRunRate);
// an OOS product reaches back to its last healthy weeks. If nothing is in stock anywhere in the
// window, it falls back to the raw recent weeks (un-corrected).
export function stockCorrectedRunRate(
  weeks: { units: number; inStockDays: number }[],
  weights: number[] = [0.4, 0.3, 0.2, 0.1],
  minInStockDays = 6,
): number {
  const healthy = weeks.filter(w => w.inStockDays >= minInStockDays).slice(0, weights.length);
  if (healthy.length === 0) {
    return weightedRunRate(weeks.slice(0, weights.length).map(w => w.units), weights);
  }
  const w = weights.slice(0, healthy.length);
  const wSum = w.reduce((s, x) => s + x, 0) || 1;
  let rate = 0;
  for (let i = 0; i < healthy.length; i++) rate += (w[i] / wSum) * (healthy[i].units / 7);
  return rate;
}

// The launch month (1-based) for a family's 2025 monthly-units array, or null when the
// family is mature / has no data. A family with January sales (first-sale month === 1) is
// treated as mature (no launch ramp) — this avoids mis-flagging a mature product whose data
// window merely starts in January. `own[i]` is month i+1's 2025 total units.
export function detectLaunchMonth(own: number[], floor = 5): number | null {
  let first: number | null = null;
  for (let i = 0; i < 12; i++) if ((own[i] ?? 0) > floor) { first = i + 1; break; }
  if (first == null || first === 1) return null;
  return first;
}

// 12-month seasonal multiplier `s` for a family, normalized so s[currentMonth-1] === 1.
// own/ref are 2025 monthly-units arrays (index 0 = January). A month is a "clean own month"
// when its own units exceed `floor` AND it is past the launch ramp (launchMonth+3); launchMonth
// null means mature (no ramp exclusion). The reference (most-mature full-year family) fills every
// non-clean month — including the current-month anchor — scaled to the family's level by
// a = mean(own/ref) over the clean overlap. Mature → pure own shape; brand-new → pure reference.
export function seasonalShape(
  own: number[],
  ref: number[],
  currentMonth: number,
  launchMonth: number | null,
  floor = 5,
): number[] {
  const clean = own.map((v, i) => v > floor && (launchMonth == null || (i + 1) >= launchMonth + 3));
  let aNum = 0, aCnt = 0;
  for (let i = 0; i < 12; i++) if (clean[i] && (ref[i] ?? 0) > 0) { aNum += own[i] / ref[i]; aCnt++; }
  const a = aCnt ? aNum / aCnt : 1;
  const u = own.map((v, i) => (clean[i] ? v : a * (ref[i] ?? 0)));
  const ucm = u[currentMonth - 1];
  return u.map((x, i) => (ucm > 0 ? x / ucm : (i === currentMonth - 1 ? 1 : 0)));
}
