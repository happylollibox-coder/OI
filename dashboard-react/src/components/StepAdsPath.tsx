/**
 * Step 3: Ads Path — Profit-optimization decision tool.
 *
 * FLAT 3-TIER MODEL: CPC and CVR are seasonal constants computed from
 * historical data per family. No power-law exponents — the data doesn't
 * support them. Tiers match DIM_US_HOLIDAYS: OFF (no holiday activity),
 * BOOST (pre-peak ramp), PEAK (hot window). Months classified by
 * dominant tier — October is BOOST (not PEAK).
 *
 * The model accounts for the ORGANIC HALO effect: increasing ad spend
 * drives direct ad units AND additional organic units (better BSR,
 * more reviews, more visibility). The adsShare ratio tells us what
 * fraction of total sales come from ads — the rest is organic uplift.
 *
 * Profit = totalUnits × margin − adSpend
 * where totalUnits = adUnits / adsShare  (includes organic contribution)
 */
import { useMemo, useEffect } from 'react';
import { fK, fmt } from '../utils';
import type { AdsEfficiencyMonth, MonthDef } from '../planTypes';
import { unitsAtSpend, profitMaxSpend, scaleHorizonPlan } from '../planTypes';

type AdsChannelMonth = {
  family: string; yr: number; mo: number; searchType: string;
  spend: number; clicks: number; units: number; orders: number;
  cpc: number; unitCvrPct: number; netRoas: number;
  currentDailySpend: number; currentCpc: number;
};

// ── Season classification matching DIM_US_HOLIDAYS 3-tier system ──
// OFF = no holiday activity, BOOST = pre-peak ramp, PEAK = hot window
type SeasonType = 'OFF' | 'BOOST' | 'PEAK';

/**
 * Known gift-season windows from DIM_US_HOLIDAYS (per family is same dates).
 * Each holiday has: boost_start → peak_start-1 = BOOST, peak_start → holiday_date-1 = PEAK.
 * Months are classified by DOMINANT tier (whichever has most days).
 */
const HOLIDAY_WINDOWS: { boost_start: string; peak_start: string; holiday_date: string }[] = [
  // Valentine's 2025
  { boost_start: '2025-01-27', peak_start: '2025-02-03', holiday_date: '2025-02-14' },
  // Easter 2025
  { boost_start: '2025-03-03', peak_start: '2025-03-31', holiday_date: '2025-04-20' },
  // Black Friday 2025
  { boost_start: '2025-10-17', peak_start: '2025-10-17', holiday_date: '2025-11-28' },
  // Christmas 2025
  { boost_start: '2025-10-01', peak_start: '2025-11-03', holiday_date: '2025-12-25' },
  // Valentine's 2026
  { boost_start: '2026-01-27', peak_start: '2026-02-03', holiday_date: '2026-02-14' },
  // Easter 2026
  { boost_start: '2026-02-16', peak_start: '2026-03-16', holiday_date: '2026-04-05' },
  // Black Friday 2026
  { boost_start: '2026-10-16', peak_start: '2026-10-16', holiday_date: '2026-11-27' },
  // Christmas 2026
  { boost_start: '2026-10-01', peak_start: '2026-11-03', holiday_date: '2026-12-25' },
];

/** Classify a month by its dominant tier using day-level holiday windows */
function getSeasonType(mo: number, yr: number): SeasonType {
  const daysInMonth = new Date(yr, mo, 0).getDate();
  let peakDays = 0, boostDays = 0;

  for (let day = 1; day <= daysInMonth; day++) {
    const d = new Date(yr, mo - 1, day);
    const ds = d.toISOString().slice(0, 10);
    let isPeak = false, isBoost = false;
    for (const hw of HOLIDAY_WINDOWS) {
      const peakEnd = new Date(hw.holiday_date);
      peakEnd.setDate(peakEnd.getDate() - 1);
      const boostEnd = new Date(hw.peak_start);
      boostEnd.setDate(boostEnd.getDate() - 1);
      if (ds >= hw.peak_start && ds <= peakEnd.toISOString().slice(0, 10)) isPeak = true;
      else if (ds >= hw.boost_start && ds <= boostEnd.toISOString().slice(0, 10)) isBoost = true;
    }
    if (isPeak) peakDays++;
    else if (isBoost) boostDays++;
  }

  if (peakDays > boostDays && peakDays > daysInMonth - peakDays - boostDays) return 'PEAK';
  if (boostDays > 0 && boostDays >= peakDays) return 'BOOST';
  if (peakDays + boostDays > daysInMonth / 2) return 'BOOST';
  return 'OFF';
}

interface ChannelBase {
  dailySpend: number;
  cpc: number;
  cvr: number; // as fraction (e.g. 0.025)
}

interface CurvePoint {
  k: number; daily: number; annual: number;
  adUnitsYear: number; totalUnitsYear: number;
  profitYear: number; roas: number;
}

// Diminishing returns for non-brand scaling, calibrated from same-day demand-controlled
// ads data (campaign×day): non-brand units scale ~k^(1 − CPC_EXP − cvrExp). Without this,
// units scaled linearly with spend and Q4 forecasts ballooned ~2x.
const CPC_EXP = 0.10; // CPC rises k^0.10 with scale (observed 0.07–0.13 across seasons)
const CVR_EXP_BY_SEASON: Record<SeasonType, number> = { PEAK: 0.25, OFF: 0.32, BOOST: 0.39 };
// Profitable-CPC ceiling per season (baked from 2025 account-wide ROAS-by-CPC-bucket analysis,
// 2026-05-21): PEAK pays through ~$1.50 CPC, BOOST to ~$0.60, OFF barely pays at any CPC (~$0.45).
// Used as the coach bid cap and the Step-3 "profitable CPC ceiling" guidance.
const SEASON_MAX_CPC: Record<SeasonType, number> = { PEAK: 1.50, BOOST: 0.60, OFF: 0.45 };
// Unit elasticity per season = 1 − CPC_EXP − cvrExp (PEAK 0.65, OFF 0.58, BOOST 0.51).
const SEASON_E: Record<SeasonType, number> = {
  PEAK: 1 - CPC_EXP - CVR_EXP_BY_SEASON.PEAK,
  OFF: 1 - CPC_EXP - CVR_EXP_BY_SEASON.OFF,
  BOOST: 1 - CPC_EXP - CVR_EXP_BY_SEASON.BOOST,
};
// → unit elasticity e = 1 − 0.10 − cvrExp: PEAK 0.65, OFF 0.58, BOOST 0.51.

/**
 * Brand stays at k=1 (defensive). Non-brand scales with k, with season-specific
 * diminishing returns: CPC rises (k^CPC_EXP), CVR decays (k^−cvrExp). At k=1 both
 * factors are 1, so current spend is unchanged. totalUnits = adUnits / adsShare (organic halo).
 */
// eslint-disable-next-line react-refresh/only-export-components -- exported for unit tests (StepAdsPath.test.ts); move to a util module if more non-component exports accrue
export function atK(k: number, brand: ChannelBase, nb: ChannelBase,
  margin: number, adsShare: number, season: SeasonType) {
  const kk = Math.max(k, 0.01);
  // Brand: stays at k=1 (defensive, doesn't scale)
  const bDaily = brand.dailySpend;
  const bAdUnits = bDaily > 0 ? (bDaily / brand.cpc) * brand.cvr : 0;

  // Non-brand: spend scales with k; CPC rises and CVR decays (diminishing returns)
  const nbDaily = nb.dailySpend * k;
  const effCpc = nb.cpc * Math.pow(kk, CPC_EXP);
  const effCvr = nb.cvr * Math.pow(kk, -CVR_EXP_BY_SEASON[season]);
  const nbAdUnits = nbDaily > 0 ? (nbDaily / effCpc) * effCvr : 0;

  const totalDaily = bDaily + nbDaily;
  const adUnits = bAdUnits + nbAdUnits;
  // As k grows, a higher fraction of sales become ad-attributed
  const effectiveAdsShare = Math.min(adsShare * Math.pow(kk, 0.08), 0.85);
  const totalUnits = adUnits / effectiveAdsShare;
  const profit = totalUnits * margin - totalDaily;
  const roas = totalDaily > 0 ? (totalUnits * margin) / totalDaily : 0;
  return { daily: totalDaily, adUnits, totalUnits, profit, roas };
}

const MAX_MONTHLY_RAMP = 1.5; // max 50% spend increase per month (used for BOOST/PEAK)
const MONTH_LABELS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const DAYS_IN_MONTH = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

export type TrajMonth = {
  idx: number; label: string; yr: number; mo: number;
  kEffective: number; seasonFactor: number;
  days: number;
  spend: number; baselineSpend: number;
  totalUnits: number; adUnits: number; organicUnits: number;
  profit: number; cumProfit: number; cumUnits: number;
  isActual?: boolean;
};

export type AdsTarget = {
  yr: number; mo: number; channel: string;
  daily_spend_target: number; cpc_target: number;
  predicted_cvr: number; predicted_roas: number;
  predicted_units: number; predicted_net_profit: number;
  cpc_exponent: number; cvr_exponent: number;
  ads_share: number; season_type: string; multiplier_k: number;
  max_cpc: number; // season profitable-CPC ceiling — coach bid cap (bid above this and clicks lose money)
};

// Per-family ROAS reference (LY 2025 / CY 2026): blended (organic-incl) at family grain,
// ad-only per channel. Surfaced for planning context; the gap (blended − ad-only) ≈ halo.
export interface FamilyRoasRef {
  blended: { 2025: number | null; 2026: number | null };
  adOnly: Record<string, { 2025: number | null; 2026: number | null }>;
}

export function StepAdsPath({ famEff, path, onPath, customDaily, onCustom, totals, channelData, months, asp, costPerUnit, monthlyUnits, monthlySpend, roas, onTargets, onTrajectory }: {
  famEff: Record<number, AdsEfficiencyMonth>;
  path: 'current' | 'target' | 'custom'; onPath: (p: 'current' | 'target' | 'custom') => void;
  customDaily: number; onCustom: (v: number) => void;
  totals: { cSpend: number; cUnits: number; cProfit: number; tSpend: number; tUnits: number; tProfit: number };
  channelData: AdsChannelMonth[]; months: MonthDef[];
  asp: number; costPerUnit: number;
  monthlyUnits?: number[]; // total units (organic+ad) per calendar month, prior year — true demand seasonality
  monthlySpend?: number[]; // prior-year ad spend per calendar month — anchors the profit-max curve
  roas?: FamilyRoasRef | null;
  onTargets?: (targets: AdsTarget[]) => void;
  onTrajectory?: (traj: TrajMonth[]) => void;
}) {
  const firstEff = Object.values(famEff)[0];
  const currDaily = firstEff?.currentDailySpend ?? 0;
  // Auto ramp-up: calculated from spend gap (no user choice)
  // rampMonths is derived, not a state variable


  // ── Channel summary (trailing 4 months) ──
  const channelSummary = useMemo(() => {
    const now = new Date();
    const curMo = now.getMonth() + 1;
    const curYr = now.getFullYear();
    const recent = channelData.filter(c => {
      const diff = (curYr - c.yr) * 12 + (curMo - c.mo);
      return diff >= 1 && diff <= 4;
    });
    const byType = (type: string) => {
      const rows = recent.filter(r => r.searchType === type);
      const spend = rows.reduce((s, r) => s + r.spend, 0);
      const clicks = rows.reduce((s, r) => s + r.clicks, 0);
      const units = rows.reduce((s, r) => s + r.units, 0);
      const cpc = clicks > 0 ? spend / clicks : 0;
      const cvr = clicks > 0 ? (units / clicks) * 100 : 0;
      const avgRoas = spend > 0
        ? rows.reduce((s, r) => s + r.netRoas * r.spend, 0) / spend : 0;
      const dailySpend = rows.length > 0 ? rows[0].currentDailySpend : 0;
      return { spend, clicks, units, cpc, cvr, avgRoas, dailySpend };
    };
    return { brand: byType('BRAND'), nonBrand: byType('NON_BRAND') };
  }, [channelData]);

  // ── Base parameters (per channel) ──
  const margin = asp - costPerUnit;
  const brandBase: ChannelBase = useMemo(() => ({
    dailySpend: channelSummary.brand.dailySpend || 0,
    cpc: channelSummary.brand.cpc || 0.50,
    cvr: (channelSummary.brand.cvr || 3.0) / 100,
  }), [channelSummary.brand]);

  const nbBase: ChannelBase = useMemo(() => ({
    dailySpend: channelSummary.nonBrand.dailySpend || currDaily || 1,
    cpc: channelSummary.nonBrand.cpc || firstEff?.currentCpc || 0.50,
    cvr: (channelSummary.nonBrand.cvr || firstEff?.unitCvrPct || 2.5) / 100,
  }), [channelSummary.nonBrand, currDaily, firstEff]);

  // Combined daily (for display and selectedDaily)
  const baseDailySpend = brandBase.dailySpend + nbBase.dailySpend;

  // Ads share — what fraction of total sales come from ads (rest is organic)
  const baseAdsShare = useMemo(() => {
    const vals = Object.values(famEff);
    if (vals.length === 0) return 0.55;
    const avg = vals.reduce((s, d) => s + (d.adsSharePct || 55), 0) / vals.length;
    return Math.max(0.1, Math.min(0.9, avg / 100));
  }, [famEff]);

  // ── Season-specific CPC/CVR/spend benchmarks (computed from data, per family) ──
  const seasonBenchmarks = useMemo(() => {
    const compute = (channel: string, season: SeasonType) => {
      const rows = channelData.filter(c =>
        c.searchType === channel && getSeasonType(c.mo, c.yr) === season
      );
      if (rows.length === 0) return null;
      const totalSpend = rows.reduce((s, r) => s + r.spend, 0);
      const totalClicks = rows.reduce((s, r) => s + r.clicks, 0);
      const totalUnits = rows.reduce((s, r) => s + r.units, 0);
      // Average daily spend across the season's months
      const totalDays = rows.reduce((s, r) => s + (DAYS_IN_MONTH[(r.mo - 1)] || 30), 0);
      return {
        cpc: totalClicks > 0 ? totalSpend / totalClicks : undefined,
        cvr: totalClicks > 0 ? totalUnits / totalClicks : undefined,
        dailySpend: totalDays > 0 ? totalSpend / totalDays : undefined,
      };
    };
    const seasons: SeasonType[] = ['OFF', 'BOOST', 'PEAK'];
    const result = {} as Record<SeasonType, { brand: ChannelBase; nb: ChannelBase }>;
    for (const season of seasons) {
      const bStats = compute('BRAND', season);
      const nbStats = compute('NON_BRAND', season);
      result[season] = {
        brand: {
          dailySpend: bStats?.dailySpend ?? brandBase.dailySpend,
          cpc: bStats?.cpc ?? brandBase.cpc,
          cvr: bStats?.cvr ?? brandBase.cvr,
        },
        nb: {
          dailySpend: nbStats?.dailySpend ?? nbBase.dailySpend,
          cpc: nbStats?.cpc ?? nbBase.cpc,
          cvr: nbStats?.cvr ?? nbBase.cvr,
        },
      };
    }
    return result;
  }, [channelData, brandBase, nbBase]);

  // ── Profit-max plan: per calendar month, the spend that maximizes net profit ──
  // Anchored to prior-year (units, spend); extrapolated with the season elasticity
  // e = 1 − CPC_EXP − cvrExp. At S = spend₂₅ it returns units₂₅ (reproduces history).
  const profitMaxPlan = useMemo(() => {
    const yr = new Date().getFullYear();
    return Array.from({ length: 12 }, (_, i) => {
      const mo = i + 1;
      const season = getSeasonType(mo, yr);
      const e = SEASON_E[season];
      const u0 = monthlyUnits?.[i] ?? 0;
      const s0 = monthlySpend?.[i] ?? 0;
      const sStar = profitMaxSpend(u0, s0, margin, e);
      if (sStar == null) {
        // No 2025 anchor (e.g. new family) — fall back to the season-benchmark daily run-rate.
        const b = seasonBenchmarks[season] ?? seasonBenchmarks['OFF'];
        const days = DAYS_IN_MONTH[i];
        const r = atK(1, b.brand, b.nb, margin, baseAdsShare, season);
        return { mo, season, e, units0: 0, spend0: 0, anchored: false,
          spend: (b.brand.dailySpend + b.nb.dailySpend) * days, units: r.totalUnits * days, profit: r.profit * days };
      }
      const units = unitsAtSpend(sStar, u0, s0, e);
      return { mo, season, e, units0: u0, spend0: s0, anchored: true,
        spend: sStar, units, profit: units * margin - sStar };
    });
  }, [monthlyUnits, monthlySpend, margin, seasonBenchmarks, baseAdsShare]);

  // ── Profit curve = the profit-max plan scaled by k (k = spendScale) ──
  // k=1 IS the plan, so the peak (max profit) lands at 1.0× and the explorer agrees with
  // Step 4 / the order by construction. Each point re-evaluates units off the 2025 anchor.
  // Sum over the PLAN HORIZON (the `months` window: current → Feb'27) so the curve, the 2025
  // baseline, and Step 4 / the order all cover the same months and totals agree exactly.
  const horizonDays = useMemo(() => months.reduce((s, m) => s + (DAYS_IN_MONTH[m.month - 1] || 30), 0), [months]);

  // ── Ramp-up trajectory (12+ months from now) ──
  // Derive the data cutoff day for the current month from channelData
  const dataActualDay = useMemo(() => {
    const now = new Date();
    const curMo = now.getMonth() + 1;
    const curYr = now.getFullYear();
    // Find current month's channel data — if spend/days ratio suggests partial month
    const curMonthRows = channelData.filter(c => c.yr === curYr && c.mo === curMo);
    if (curMonthRows.length > 0) {
      // Estimate actual days from spend: total spend / daily spend rate
      const totalSpend = curMonthRows.reduce((s, r) => s + r.spend, 0);
      const dailyRate = curMonthRows[0]?.currentDailySpend || 1;
      const estDays = Math.round(totalSpend / dailyRate);
      return Math.max(1, Math.min(estDays, now.getDate() - 2)); // data lags 2 days
    }
    return Math.max(1, now.getDate() - 2); // fallback: 2-day lag
  }, [channelData]);

  // Current calendar month (0-based) + remaining-days fraction — the current month counts only
  // its forward-remaining slice in every plan total (forecast-based; matches snapshot + coach).
  const curMoIdx0 = new Date().getMonth();
  const curRemFrac = Math.max(0, 1 - dataActualDay / (DAYS_IN_MONTH[curMoIdx0] || 30));

  // 2025 baseline (what actually happened) + the recommended-plan totals — for the curve
  // markers and the "2025 → recommended" improvement callout.
  const baseline2025 = useMemo(() => {
    let spend = 0, units = 0;
    for (const m of months) { spend += monthlySpend?.[m.month - 1] ?? 0; units += monthlyUnits?.[m.month - 1] ?? 0; }
    return { spend, units, profit: units * margin - spend };
  }, [months, monthlySpend, monthlyUnits, margin]);
  const planTotals = useMemo(() => {
    const t = scaleHorizonPlan(profitMaxPlan, months, 1, curMoIdx0, curRemFrac);
    return { spend: t.spend, units: t.units, profit: t.units * margin - t.spend };
  }, [profitMaxPlan, months, margin, curMoIdx0, curRemFrac]);
  // Marker positions on the ×-plan axis (over the horizon): 2025 actual (LY) and current spend (NOW).
  const lyK = planTotals.spend > 0 ? baseline2025.spend / planTotals.spend : 0;
  const nowK = planTotals.spend > 0 ? (baseDailySpend * horizonDays) / planTotals.spend : 0;

  // ── Profit curve = the profit-max plan scaled by k (k = spendScale) ──
  // Fine 0.1× steps zoomed to the useful zone: from ~current/last-year up to the peak
  // (1.0× = the recommended plan, where profit maxes) plus 2 steps where profit is already
  // declining — instead of a wide 0.5–5× span dominated by deep-loss rows.
  const multipliers = useMemo(() => {
    const refs = [nowK, lyK].filter(v => v > 0.05);
    const minRef = refs.length ? Math.min(...refs) : 0.5;
    const maxRef = refs.length ? Math.max(...refs) : 1.0;
    const lo = Math.max(0.3, Math.min(0.9, Math.floor(minRef * 10) / 10)); // ≤0.9 so the peak always shows
    const hi = Math.max(1.2, Math.ceil(maxRef * 10) / 10 + 0.1);           // ≥1.2 → 2 declining steps past the peak
    const out: number[] = [];
    for (let k = lo; k <= hi + 1e-9; k += 0.1) out.push(Math.round(k * 10) / 10);
    return out;
  }, [nowK, lyK]);
  const curve: CurvePoint[] = useMemo(() => {
    return multipliers.map(k => {
      const { spend, units } = scaleHorizonPlan(profitMaxPlan, months, k, curMoIdx0, curRemFrac);
      const profit = units * margin - spend;
      return {
        k, daily: horizonDays > 0 ? spend / horizonDays : 0, annual: spend,
        adUnitsYear: Math.round(units * baseAdsShare),
        totalUnitsYear: Math.round(units),
        profitYear: Math.round(profit),
        roas: spend > 0 ? (units * margin) / spend : 0,
      };
    });
  }, [multipliers, profitMaxPlan, months, margin, baseAdsShare, horizonDays, curMoIdx0, curRemFrac]);

  const peakIdx = curve.reduce((best, p, i) => p.profitYear > curve[best].profitYear ? i : best, 0);
  const maxProfit = Math.max(...curve.map(p => Math.abs(p.profitYear)), 1);

  // Selected daily
  const selectedDaily = path === 'current' ? baseDailySpend
    : path === 'target' ? (totals.tSpend / (Object.keys(famEff).length * 30 || 1))
    : customDaily;
  const selectedK = baseDailySpend > 0 ? selectedDaily / baseDailySpend : 1;
  // The curve row matching the selection — single source for the highlight AND the Target panel.
  // The curve/trajectory/coach all operate on the profit-max plan's spend, so the displayed daily
  // must be the row's plan-scale daily (p.daily), not selectedDaily (which is current-baseline scale).
  const selectedPoint = curve.length
    ? curve.reduce((best, p) => Math.abs(p.k - selectedK) < Math.abs(best.k - selectedK) ? p : best, curve[0])
    : null;

  // Auto ramp-up: geometric (50%/mo cap), 0 if already at target
  const rampMonths = useMemo(() => {
    if (selectedK <= 1.1) return 0; // already at or above target
    const months = Math.ceil(Math.log(selectedK) / Math.log(MAX_MONTHLY_RAMP));
    // Cap at months until October (peak season)
    const now = new Date();
    const curMo = now.getMonth(); // 0-indexed
    const monthsToPeak = curMo < 9 ? 9 - curMo : 12 - curMo + 9;
    return Math.min(months, monthsToPeak, 12);
  }, [selectedK]);

  // User dial on the profit-max plan: 1.0 = profit-max; >1 over-spends, <1 under-spends.
  const spendScale = selectedK;
  const trajectoryMonths = useMemo(() => {
    const result: TrajMonth[] = [];
    let cumProfit = 0, cumUnits = 0;

    for (let i = 0; i < months.length; i++) {
      const moIdx = months[i].month - 1;
      const yr = months[i].year;
      const fullDays = DAYS_IN_MONTH[moIdx];
      const plan = profitMaxPlan[moIdx];
      const spend = plan.spend * spendScale;
      // Re-evaluate units at the scaled spend off the 2025 anchor (diminishing returns);
      // unanchored months scale proportionally.
      const units = plan.anchored && plan.spend0 > 0
        ? unitsAtSpend(spend, plan.units0, plan.spend0, plan.e)
        : plan.units * spendScale;
      const profit = units * margin - spend;
      const adU = units * baseAdsShare;

      if (i === 0) {
        // Current month: split elapsed (actual) vs remaining (forecast) by day fraction.
        const fAct = Math.min(1, Math.max(0, dataActualDay / fullDays));
        const fFc = Math.max(0, 1 - fAct);
        cumProfit += profit * fAct; cumUnits += units * fAct;
        result.push({
          idx: -1, label: `${MONTH_LABELS[moIdx]}✓`, yr, mo: moIdx + 1,
          kEffective: spendScale, seasonFactor: 1,
          days: Math.max(1, fullDays * fAct),
          spend: spend * fAct, baselineSpend: plan.spend * fAct,
          totalUnits: units * fAct, adUnits: adU * fAct, organicUnits: (units - adU) * fAct,
          profit: profit * fAct, cumProfit, cumUnits: Math.round(cumUnits), isActual: true,
        });
        cumProfit += profit * fFc; cumUnits += units * fFc;
        result.push({
          idx: 0, label: `${MONTH_LABELS[moIdx]}→`, yr, mo: moIdx + 1,
          kEffective: spendScale, seasonFactor: 1,
          days: Math.max(1, fullDays * fFc),
          spend: spend * fFc, baselineSpend: plan.spend * fFc,
          totalUnits: units * fFc, adUnits: adU * fFc, organicUnits: (units - adU) * fFc,
          profit: profit * fFc, cumProfit, cumUnits: Math.round(cumUnits),
        });
      } else {
        cumProfit += profit; cumUnits += units;
        result.push({
          idx: i, label: MONTH_LABELS[moIdx], yr, mo: moIdx + 1,
          kEffective: spendScale, seasonFactor: 1,
          days: fullDays,
          spend, baselineSpend: plan.spend,
          totalUnits: units, adUnits: adU, organicUnits: units - adU,
          profit, cumProfit, cumUnits: Math.round(cumUnits),
        });
      }
    }
    return result;
  }, [profitMaxPlan, spendScale, margin, baseAdsShare, dataActualDay, months]);

  const maxTrajSpend = Math.max(...trajectoryMonths.map(t => t.spend), 1);
  const yr1Units = trajectoryMonths[trajectoryMonths.length - 1]?.cumUnits ?? 0;
  const yr1Profit = trajectoryMonths[trajectoryMonths.length - 1]?.cumProfit ?? 0;
  const yr1Spend = trajectoryMonths.reduce((s, t) => s + t.spend, 0);

  // ── Generate per-month/channel targets for DE_PLAN_ADS_TARGETS ──
  const adsTargets = useMemo(() => {
    const targets: AdsTarget[] = [];

    for (let i = 0; i < months.length; i++) {
      const moIdx = months[i].month - 1;
      const yr = months[i].year;
      const days = DAYS_IN_MONTH[moIdx];
      const seasonType = getSeasonType(moIdx + 1, yr);
      const seasonB = seasonBenchmarks[seasonType] ?? seasonBenchmarks['OFF'];
      const plan = profitMaxPlan[moIdx];
      // Current calendar month counts only its forward-remaining slice (forecast-based), so the
      // coach's predicted_units/profit tie to the snapshot. daily_spend_target stays a full-month
      // per-day rate; only the monthly TOTALS are prorated.
      const frac = moIdx === curMoIdx0 ? curRemFrac : 1;

      // Full-month family spend/units from the profit-max plan (× user dial) — same source as the
      // curve, Step 4, and the order. Channel split uses FULL spend so the per-day rate stays correct.
      const spend = plan.spend * spendScale;
      const units = plan.anchored && plan.spend0 > 0
        ? unitsAtSpend(spend, plan.units0, plan.spend0, plan.e)
        : plan.units * spendScale;

      const brandSpend = Math.min(seasonB.brand.dailySpend * days, spend);
      const nbSpend = Math.max(0, spend - brandSpend);
      const bRaw = brandSpend > 0 && seasonB.brand.cpc > 0 ? (brandSpend / seasonB.brand.cpc) * seasonB.brand.cvr : 0;
      const nRaw = nbSpend > 0 && seasonB.nb.cpc > 0 ? (nbSpend / seasonB.nb.cpc) * seasonB.nb.cvr : 0;
      const rawTot = bRaw + nRaw;

      // chSpendFull/chUnitsFull are full-month; the monthly totals applied to the row are × frac
      // (forecast-remaining for the current month), but the per-day rate divides full spend by full days.
      const mkRow = (channel: string, chSpendFull: number, chUnitsFull: number, cpc: number, cvr: number): AdsTarget => {
        const chSpend = chSpendFull * frac;
        const chUnits = chUnitsFull * frac;
        return {
          yr, mo: moIdx + 1, channel,
          daily_spend_target: Math.round((chSpendFull / days) * 100) / 100,
          cpc_target: Math.round(cpc * 1000) / 1000,
          predicted_cvr: cvr,
          predicted_roas: chSpend > 0 ? (chUnits * margin) / chSpend : 0,
          predicted_units: Math.round(chUnits),
          predicted_net_profit: Math.round(chUnits * margin - chSpend),
          cpc_exponent: 0, cvr_exponent: 0, // flat model — no exponents
          ads_share: baseAdsShare, season_type: seasonType,
          multiplier_k: Math.round(spendScale * 100) / 100, max_cpc: SEASON_MAX_CPC[seasonType],
        };
      };

      targets.push(mkRow('BRAND', brandSpend, rawTot > 0 ? units * (bRaw / rawTot) : 0, seasonB.brand.cpc, seasonB.brand.cvr));
      targets.push(mkRow('NON_BRAND', nbSpend, rawTot > 0 ? units * (nRaw / rawTot) : units, seasonB.nb.cpc, seasonB.nb.cvr));
    }
    return targets;
  }, [profitMaxPlan, spendScale, seasonBenchmarks, baseAdsShare, margin, months, curMoIdx0, curRemFrac]);

  // Expose targets to parent (PlanWizard) for saving
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { onTargets?.(adsTargets); }, [adsTargets]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { onTrajectory?.(trajectoryMonths); }, [trajectoryMonths]);

  const hasChannel = channelData.length > 0;

  return (
    <div className="space-y-3">
      <p className="text-muted text-[11px]">
        More ad spend → more <span className="text-heading font-medium">total units</span> (ads + organic halo).
        Ads share is ~{Math.round(baseAdsShare * 100)}%, so every ad unit drives ~{(1 / baseAdsShare - 1).toFixed(1)} organic units.
        Pick a target, then see the ramp-up below.
      </p>

      {/* ── Channel efficiency (compact) ── */}
      {hasChannel && (
        <div className="grid grid-cols-2 gap-2">
          {[
            { label: '🛡 Brand', d: channelSummary.brand, clr: 'emerald' },
            { label: '🔍 Non-brand', d: channelSummary.nonBrand, clr: 'blue' },
          ].map(ch => (
            <div key={ch.label} className={`px-3 py-1.5 rounded-lg border border-${ch.clr}-500/20 bg-${ch.clr}-500/5 text-[10px] flex items-center justify-between gap-2`}>
              <span className="text-muted font-semibold whitespace-nowrap">{ch.label}</span>
              <span className="tabular-nums text-heading">
                CPC <b>${ch.d.cpc.toFixed(2)}</b>
                {' · '}CVR <b>{ch.d.cvr.toFixed(1)}%</b>
                {' · '}ROAS <b className={ch.d.avgRoas >= 1 ? 'text-emerald-400' : 'text-red-400'}>{ch.d.avgRoas.toFixed(1)}×</b>
                {' · '}<b>${ch.d.dailySpend.toFixed(0)}</b>/d
              </span>
            </div>
          ))}
        </div>
      )}

      {/* ── Profitable-CPC ceiling by season (baked from 2025 ROAS-by-CPC analysis) ── */}
      <div className="px-3 py-1.5 rounded-lg border border-border/40 bg-border/5 text-[10px] flex items-center justify-between gap-2">
        <span className="text-muted font-semibold whitespace-nowrap">Profitable CPC ceiling</span>
        <span className="tabular-nums text-heading">
          PEAK <b>≤${SEASON_MAX_CPC.PEAK.toFixed(2)}</b>{' · '}BOOST <b>≤${SEASON_MAX_CPC.BOOST.toFixed(2)}</b>{' · '}OFF <b>≤${SEASON_MAX_CPC.OFF.toFixed(2)}</b>
          <span className="text-faint font-normal">{' '}— bid above and clicks lose money</span>
        </span>
      </div>

      {/* ── Net ROAS reference: LY → CY, blended (family) vs ad-only (per channel) ── */}
      {roas && (() => {
        const fr = (x: number | null) => x != null ? `${x.toFixed(2)}×` : '—';
        return (
          <div className="px-3 py-1.5 rounded-lg border border-border/40 bg-border/5 text-[10px] flex flex-wrap items-center gap-x-4 gap-y-0.5">
            <span className="text-muted font-semibold whitespace-nowrap">Net ROAS (LY → CY)</span>
            <span className="tabular-nums text-heading">Blended {fr(roas.blended[2025])} → {fr(roas.blended[2026])}</span>
            <span className="tabular-nums text-heading">Brand ad-only {fr(roas.adOnly.BRAND?.[2025] ?? null)} → {fr(roas.adOnly.BRAND?.[2026] ?? null)}</span>
            <span className="tabular-nums text-heading">Non-brand ad-only {fr(roas.adOnly.NON_BRAND?.[2025] ?? null)} → {fr(roas.adOnly.NON_BRAND?.[2026] ?? null)}</span>
            <span className="text-faint">blended − ad-only ≈ halo</span>
          </div>
        );
      })()}

      {/* ── Profit curve table ── */}
      <div>
        <div className="mb-1">
          <div className="text-[10px] text-muted font-semibold">
            Spend → Profit Curve
            <span className="text-faint font-normal ml-1">(margin ${margin.toFixed(2)}/u · ads share {Math.round(baseAdsShare * 100)}%)</span>
          </div>
          {(() => {
            const d = planTotals.profit - baseline2025.profit;
            const pct = baseline2025.profit > 0 ? Math.round((d / baseline2025.profit) * 100) : null;
            return (
              <div className="text-[9px] tabular-nums mt-0.5">
                <span className="text-faint">2025</span> <span className="text-muted">{fK(baseline2025.spend)} → {fK(baseline2025.profit)} profit</span>
                {'  →  '}
                <span className="text-emerald-400 font-semibold">recommended {fK(planTotals.spend)} → {fK(planTotals.profit)}</span>
                <span className="text-emerald-400 font-bold">{' '}({d >= 0 ? '+' : ''}{fK(d)}{pct !== null ? ` · ${pct >= 0 ? '+' : ''}${pct}%` : ''})</span>
              </div>
            );
          })()}
        </div>
        <div className="space-y-[2px]">
          {curve.map((p, i) => {
            const isPeakRow = i === peakIdx;
            const isSelected = p === selectedPoint;
            const isCurrent = nowK > 0 && curve.reduce((best, cp, ci) => Math.abs(cp.k - nowK) < Math.abs(curve[best].k - nowK) ? ci : best, 0) === i;
            const isLY = lyK > 0 && curve.reduce((best, cp, ci) => Math.abs(cp.k - lyK) < Math.abs(curve[best].k - lyK) ? ci : best, 0) === i;
            const barW = Math.abs(p.profitYear / maxProfit) * 100;
            const isLoss = p.profitYear < 0;

            return (
              <button key={p.k} onClick={() => { onCustom(Math.round(baseDailySpend * p.k)); onPath('custom'); }}
                title={`$${p.daily.toFixed(0)}/day → ${fmt(p.totalUnitsYear)} total units/yr (${fmt(p.adUnitsYear)} ads + ${fmt(p.totalUnitsYear - p.adUnitsYear)} organic)\nProfit: ${fK(p.profitYear)}/yr · ROAS ${p.roas.toFixed(2)}×`}
                className={`w-full flex items-center gap-2 px-2 py-1 rounded-md text-[10px] transition-all text-left
                  ${isSelected ? 'ring-2 ring-blue-500/60 bg-blue-500/10' : 'hover:bg-border/10'}
                  ${isPeakRow && !isSelected ? 'bg-emerald-500/5 border border-emerald-500/20' : 'border border-transparent'}`}>
                <span className="w-[34px] shrink-0 tabular-nums text-faint text-right">{p.k === 1 ? 'Plan' : `${p.k}×`}</span>
                <span className="w-[48px] shrink-0 tabular-nums text-heading font-medium text-right">${Math.round(p.daily)}<span className="text-faint text-[8px]">/d</span></span>
                <div className="flex-1 h-3.5 relative rounded-sm overflow-hidden bg-border/10">
                  {!isLoss ? (
                    <div className={`absolute left-0 top-0 h-full rounded-sm ${isPeakRow ? 'bg-emerald-500/60' : 'bg-emerald-500/30'}`}
                      style={{ width: `${Math.max(barW, 2)}%` }} />
                  ) : (
                    <div className="absolute right-0 top-0 h-full rounded-sm bg-red-500/40"
                      style={{ width: `${Math.min(barW, 100)}%` }} />
                  )}
                  <span className={`absolute inset-0 flex items-center px-1.5 text-[8px] tabular-nums font-semibold ${isLoss ? 'text-red-300 justify-end' : 'text-emerald-300'}`}>
                    {fK(p.profitYear)}/yr
                  </span>
                </div>
                <span className="w-[56px] shrink-0 tabular-nums font-bold text-heading text-right">{fmt(p.totalUnitsYear)}<span className="text-faint text-[8px] font-normal"> u</span></span>
                <span className="w-[42px] shrink-0 text-center">
                  {isPeakRow && <span className="text-[7px] px-1 py-0.5 rounded bg-emerald-500/20 text-emerald-400 font-bold">PEAK</span>}
                  {isCurrent && !isPeakRow && <span className="text-[7px] px-1 py-0.5 rounded bg-border/30 text-faint">NOW</span>}
                  {isLY && !isCurrent && !isPeakRow && <span className="text-[7px] px-1 py-0.5 rounded bg-amber-500/20 text-amber-400 font-bold">LY</span>}
                  {isLoss && !isPeakRow && !isCurrent && !isLY && <span className="text-[7px] px-1 py-0.5 rounded bg-red-500/20 text-red-400 font-bold">LOSS</span>}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {/* ── Selected + Auto Ramp ── */}
      <div className="flex items-center justify-between px-4 py-2.5 rounded-xl border border-blue-500/30 bg-blue-500/5">
        <div>
          <div className="text-[11px] font-bold text-heading">
            Target: <span className="text-blue-300">${Math.round(selectedPoint?.daily ?? selectedDaily)}/day</span>
            <span className="text-faint font-normal ml-1">({(selectedPoint?.k ?? selectedK).toFixed(1)}× plan)</span>
          </div>
          <div className="flex items-center gap-2 mt-1 text-[10px]">
            <span className="text-muted">Ramp-up:</span>
            {rampMonths === 0
              ? <span className="px-1.5 py-0.5 rounded text-[9px] font-medium bg-emerald-500/20 text-emerald-400">✓ Already at target</span>
              : <span className="px-1.5 py-0.5 rounded text-[9px] font-medium bg-blue-500/20 text-blue-300">{rampMonths}mo auto (+50%/mo max)</span>
            }
          </div>
        </div>
        <div className="text-right">
          <div className="text-base tabular-nums font-bold text-heading">{fmt(yr1Units)} <span className="text-[9px] text-muted font-normal">units</span></div>
          <div className={`text-[10px] tabular-nums font-bold ${yr1Profit >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
            {fK(Math.round(yr1Profit))} profit · {fK(Math.round(yr1Spend))} spend
          </div>
        </div>
      </div>

      {/* ── Ramp-up Trajectory (12 months) ── */}
      {hasChannel && (
        <div>
          <div className="text-[10px] text-muted font-semibold mb-1">
            12-Month Ramp-up Trajectory
            <span className="text-faint font-normal ml-1">(seasonal × gradual scale to {selectedK.toFixed(1)}×)</span>
          </div>

          {/* Bars */}
          <div className="grid gap-[3px] items-end mb-0.5" style={{ height: '72px', gridTemplateColumns: `repeat(${trajectoryMonths.length}, minmax(0, 1fr))` }}>
            {trajectoryMonths.map((t, i) => {
              const H = 72;
              const barH = Math.max(Math.round((t.spend / maxTrajSpend) * H), 2);
              const baseH = Math.max(Math.round((t.baselineSpend / maxTrajSpend) * H), 1);
              const isProfitable = t.profit >= 0;
              const atTarget = t.kEffective >= selectedK * 0.95;

              return (
                <div key={i}
                  title={`${t.label} '${String(t.yr).slice(2)}\n` +
                    `Scale: ${t.kEffective.toFixed(2)}× · Season: ${t.seasonFactor.toFixed(2)}×\n` +
                    `Spend: ${fK(Math.round(t.spend))} (baseline ${fK(Math.round(t.baselineSpend))})\n` +
                    `Total: ${fmt(Math.round(t.totalUnits))} units (${fmt(Math.round(t.adUnits))} ads + ${fmt(Math.round(t.organicUnits))} organic)\n` +
                    `Profit: ${fK(Math.round(t.profit))}\n` +
                    `Cumulative: ${fmt(t.cumUnits)} units · ${fK(Math.round(t.cumProfit))} profit`}
                  className="relative flex flex-col items-stretch justify-end cursor-help"
                  style={{ height: `${H}px` }}>
                  <div className={`w-full rounded-t-sm transition-colors ${
                    !isProfitable ? 'bg-red-500/50'
                    : t.isActual ? 'bg-emerald-500/40'
                    : atTarget ? 'bg-blue-500/50'
                    : 'bg-blue-500/30'
                  }`} style={{ height: `${barH}px` }} />
                  <div className="absolute w-full border-t border-dashed border-white/15"
                    style={{ bottom: `${baseH}px` }} />
                </div>
              );
            })}
          </div>

          {/* Month labels */}
          <div className="grid gap-[3px] text-[7px] text-faint text-center" style={{ gridTemplateColumns: `repeat(${trajectoryMonths.length}, minmax(0, 1fr))` }}>
            {trajectoryMonths.map((t, i) => <div key={i} className={t.isActual ? 'text-emerald-400' : ''}>{t.label}</div>)}
          </div>

          {/* Ramp k labels */}
          <div className="grid gap-[3px] text-[7px] text-center mt-0.5" style={{ gridTemplateColumns: `repeat(${trajectoryMonths.length}, minmax(0, 1fr))` }}>
            {trajectoryMonths.map((t, i) => (
              <div key={i} className={`tabular-nums ${t.isActual ? 'text-emerald-400' : t.kEffective >= selectedK * 0.95 ? 'text-blue-400 font-semibold' : 'text-faint'}`}>
                {t.isActual ? '1.0×' : `${t.kEffective.toFixed(1)}×`}
              </div>
            ))}
          </div>

          {/* Month detail table */}
          <div className="mt-2 max-h-[120px] overflow-y-auto">
            <table className="w-full text-[9px]">
              <thead><tr className="text-faint border-b border-border/30">
                <th className="text-left py-0.5 px-0.5 font-medium">Month</th>
                <th className="text-right py-0.5 px-0.5 font-medium">Scale</th>
                <th className="text-right py-0.5 px-0.5 font-medium">Spend</th>
                <th className="text-right py-0.5 px-0.5 font-medium">Spend/d</th>
                <th className="text-right py-0.5 px-0.5 font-medium">Ads Units</th>
                <th className="text-right py-0.5 px-0.5 font-medium">Total Units</th>
                <th className="text-right py-0.5 px-0.5 font-medium">Units/d</th>
                <th className="text-right py-0.5 px-0.5 font-medium">Profit</th>
                <th className="text-right py-0.5 px-0.5 font-medium">Cum. Profit</th>
              </tr></thead>
              <tbody>
                {trajectoryMonths.map((t, i) => (
                  <tr key={i} className={`border-b border-border/10 hover:bg-border/10 ${t.isActual ? 'bg-emerald-500/5' : ''}`}>
                    <td className="py-0.5 px-0.5 font-medium text-heading">{t.label} '{String(t.yr).slice(2)}</td>
                    <td className={`text-right py-0.5 px-0.5 tabular-nums ${t.kEffective >= selectedK * 0.95 ? 'text-blue-400 font-bold' : 'text-muted'}`}>
                      {t.kEffective.toFixed(2)}×
                    </td>
                    <td className="text-right py-0.5 px-0.5 tabular-nums text-muted">{fK(Math.round(t.spend))}</td>
                    <td className="text-right py-0.5 px-0.5 tabular-nums text-muted">{fK(Math.round(t.spend / t.days))}</td>
                    <td className="text-right py-0.5 px-0.5 tabular-nums text-faint">{fmt(Math.round(t.adUnits))}</td>
                    <td className="text-right py-0.5 px-0.5 tabular-nums font-bold text-heading">{fmt(Math.round(t.totalUnits))}</td>
                    <td className="text-right py-0.5 px-0.5 tabular-nums text-faint">{fmt(Math.round(t.totalUnits / t.days))}</td>
                    <td className={`text-right py-0.5 px-0.5 tabular-nums font-bold ${t.profit >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
                      {fK(Math.round(t.profit))}
                    </td>
                    <td className={`text-right py-0.5 px-0.5 tabular-nums ${t.cumProfit >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
                      {fK(Math.round(t.cumProfit))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Legend */}
          <div className="flex items-center gap-3 mt-1 text-[8px] text-faint">
            <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-sm bg-emerald-500/40 inline-block" /> Actual</span>
            <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-sm bg-blue-500/30 inline-block" /> Ramping</span>
            <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-sm bg-blue-500/50 inline-block" /> At target</span>
            <span className="flex items-center gap-1"><span className="w-4 h-0 border-t border-dashed border-white/15 inline-block" /> Baseline</span>
          </div>
        </div>
      )}
    </div>
  );
}
