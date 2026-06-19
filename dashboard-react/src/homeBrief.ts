/**
 * homeBrief — pure logic for the Home page Brief.
 *
 * Turns slices of DashboardData into a BriefModel: a per-family, plain-language
 * read of "what moved" plus cross-cutting "needs attention" items, for one of four
 * day-windows (Today·Ads / Yesterday / 7 days / 30 days).
 *
 * No React, no formatting of layout — only human-readable sentences and numbers.
 * See docs/superpowers/specs/2026-06-19-home-brief-design.md.
 *
 * v1 approximations (backend hardens later):
 *  - "Today > 20h updated" → proxy = ads_max_date === today (tab disabled otherwise).
 *  - Per-product movement is ads-derived only (daily_trends is family-grain).
 *  - Organic % ≈ (orders − ads_orders) / orders.
 *  - Peak baseline is best-effort (LY same dates if LY daily rows exist, else prior window).
 */
import type { DashboardData, DailyTrendByAsinRow, Ads7dRow, SupplyChainRow, ProductRow, ActionRow, PeakRow } from './types';
import { addDays, fM, fP, fR, experimentMatchesFamily } from './utils';

export type DateMode = 'today' | 'yday' | '7d' | '30d';
export type Health = 'risk' | 'warn' | 'good' | 'flat';

export interface BriefThresholds {
  /** Min |Δ%| for an additive ($/count) metric to count as "moved". */
  pctMove: number;
  /** Min |Δ| in ROAS multiples to count as moved. */
  roasAbs: number;
  /** Min |Δ| in organic percentage-points to count as moved. */
  orgPt: number;
  /** Days-of-coverage at or below which a product is OOS-risk. */
  oosDays: number;
}

export const BRIEF_THRESHOLDS: BriefThresholds = { pctMove: 7, roasAbs: 0.2, orgPt: 2, oosDays: 7 };

export interface MetricDelta {
  key: string;
  label: string;
  cur: number;
  base: number;
  deltaPct: number;
  /** Absolute diff — meaningful for ROAS (x) and organic (pt). */
  deltaAbs: number;
  dir: 'up' | 'dn' | 'flat';
  moved: boolean;
  kind: 'money' | 'ratio' | 'pct' | 'int';
}

export interface ProductMove {
  name: string;
  text: string;
}

export interface AttentionItem {
  level: 'risk' | 'warn' | 'watch';
  text: string;
}

export interface FamilyView {
  family: string;
  health: Health;
  steady: boolean;
  adsOnly: boolean;
  approxNote?: string;
  read: string;
  kpis: MetricDelta[];
  products: ProductMove[];
  attention: AttentionItem[];
}

export interface OverviewView {
  headline: string;
  attention: AttentionItem[];
}

export interface BriefModel {
  dateMode: DateMode;
  periodLabel: string;
  todayEnabled: boolean;
  todayDisabledReason?: string;
  overview: OverviewView;
  families: FamilyView[];
}

/* ── Aggregation primitives ──────────────────────────────────────────────── */

interface Agg {
  sales: number; ad_cost: number; cogs: number; net_profit: number;
  orders: number; units: number; organic_units: number; clicks: number; sessions: number;
  ads_spend: number; ads_sales: number; ads_orders: number;
  rows: number;
}
const emptyAgg = (): Agg => ({ sales: 0, ad_cost: 0, cogs: 0, net_profit: 0, orders: 0, units: 0, organic_units: 0, clicks: 0, sessions: 0, ads_spend: 0, ads_sales: 0, ads_orders: 0, rows: 0 });

const inRange = (d: string, start: string, end: string) => !!d && d >= start && d <= end;

/** Sum family P&L from daily_trends_by_asin (rolled up to family) over [start,end]. */
function sumByAsin(rows: DailyTrendByAsinRow[], family: string | null, start: string, end: string): Agg {
  const a = emptyAgg();
  for (const r of rows) {
    if (family && r.product_type !== family) continue;
    if (!inRange(r.date, start, end)) continue;
    a.sales += r.sales || 0;
    a.ad_cost += r.ad_cost || 0;
    a.cogs += r.cogs || 0;
    a.net_profit += r.net_profit || 0;
    a.orders += r.orders || 0;
    a.units += r.units || 0;
    a.organic_units += r.organic_units || 0;
    a.ads_orders += r.ad_orders || 0;
    a.clicks += r.clicks || 0;
    a.sessions += r.sessions || 0;
    a.rows += 1;
  }
  return a;
}

/** Add ads metrics (spend/sales/orders) from ads_7d into the family agg (Today mode). */
function addAds(a: Agg, adsRows: Ads7dRow[], productToFamily: Record<string, string>, family: string | null, start: string, end: string): void {
  for (const r of adsRows) {
    const d = r.date || '';
    if (!inRange(d, start, end)) continue;
    const fam = resolveAdsFamily(r, productToFamily);
    if (family && fam !== family) continue;
    a.ads_spend += r.spend || 0;
    a.ads_sales += r.sales || 0;
    a.ads_orders += r.orders || 0;
  }
}

function resolveAdsFamily(r: Ads7dRow, productToFamily: Record<string, string>): string | null {
  if (r.parent_name && productToFamily[r.parent_name] === undefined && isFamilyName(r.parent_name)) return r.parent_name;
  if (r.product_short_name && productToFamily[r.product_short_name]) return productToFamily[r.product_short_name];
  if (r.parent_name) return r.parent_name;
  const camp = String(r.campaign_name || '');
  for (const fam of KNOWN_FAMILIES) if (experimentMatchesFamily(camp, fam as never)) return fam;
  return null;
}

// Families recognised by the ads campaign-name matcher fallback.
const KNOWN_FAMILIES = ['Lollibox', 'LolliME', 'Bottle', 'Fresh'];
const isFamilyName = (s: string) => KNOWN_FAMILIES.includes(s);

/* ── Window resolution ───────────────────────────────────────────────────── */

export interface ResolvedWindow {
  curStart: string; curEnd: string;
  baseStart: string; baseEnd: string;
  /** Multiply base sums by this to compare against current (1/7 for avg modes). */
  baseScale: number;
  adsOnly: boolean;
  peak: boolean;
  label: string;
}

export function todayStr(now: Date = new Date()): string {
  const y = now.getFullYear(), m = String(now.getMonth() + 1).padStart(2, '0'), d = String(now.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** Does [start,end] overlap the peak window [pre_peak_start, peak_end]? */
export function isPeakWindow(start: string, end: string, pk: PeakRow | null): boolean {
  if (!pk?.pre_peak_start || !pk?.peak_end) return false;
  return start <= pk.peak_end && end >= pk.pre_peak_start;
}

const daysBetween = (a: string, b: string) =>
  Math.round((new Date(a + 'T00:00:00').getTime() - new Date(b + 'T00:00:00').getTime()) / 86400000);

/**
 * Days to shift the baseline back so it aligns to LAST year's peak anchor (not a flat 364).
 * Anchor = peak_start (fallback holiday_date). Finds the same holiday's prior-year occurrence
 * in `holidays`. Falls back to 364 if it can't resolve a sane (~1-year) shift.
 */
export function peakShiftDays(
  holidays: { holiday_name: string; holiday_date: string; peak_start?: string }[],
  pk: PeakRow | null,
): number {
  const DEFAULT = 364;
  if (!pk?.holiday_name) return DEFAULT;
  const thisAnchor = pk.peak_start || pk.holiday_date;
  if (!thisAnchor || !pk.holiday_date) return DEFAULT;
  const prior = (holidays || [])
    .filter(h => h.holiday_name === pk.holiday_name && h.holiday_date && h.holiday_date < pk.holiday_date)
    .sort((a, b) => b.holiday_date.localeCompare(a.holiday_date))[0];
  if (!prior) return DEFAULT;
  const shift = daysBetween(thisAnchor, prior.peak_start || prior.holiday_date);
  return shift >= 330 && shift <= 400 ? shift : DEFAULT; // sanity: ~1 year ± 5 weeks
}

export function resolveWindow(mode: DateMode, perfMax: string, _adsMax: string, pk: PeakRow | null, now: Date = new Date(), lyShiftDays = 364): ResolvedWindow {
  const today = todayStr(now);
  if (mode === 'today') {
    return {
      curStart: today, curEnd: today,
      baseStart: addDays(today, -7), baseEnd: addDays(today, -1),
      baseScale: 1 / 7, adsOnly: true, peak: false,
      label: 'Today so far · ads only · vs 7-day avg',
    };
  }
  if (mode === 'yday') {
    return {
      curStart: perfMax, curEnd: perfMax,
      baseStart: addDays(perfMax, -7), baseEnd: addDays(perfMax, -1),
      baseScale: 1 / 7, adsOnly: false, peak: false,
      label: `${perfMax} · vs 7-day avg`,
    };
  }
  const n = mode === '7d' ? 7 : 30;
  const curStart = addDays(perfMax, -(n - 1));
  const peak = isPeakWindow(curStart, perfMax, pk);
  let baseStart: string, baseEnd: string;
  if (peak) {
    // Peak-anchor-relative: shift back by the days between this year's and last year's
    // peak anchor (lyShiftDays), so we compare the same position-relative-to-peak.
    baseEnd = addDays(perfMax, -lyShiftDays);
    baseStart = addDays(baseEnd, -(n - 1));
  } else {
    baseEnd = addDays(curStart, -1);
    baseStart = addDays(baseEnd, -(n - 1));
  }
  return {
    curStart, curEnd: perfMax, baseStart, baseEnd,
    baseScale: 1, adsOnly: false, peak,
    label: `${curStart} – ${perfMax} · vs ${peak ? 'last-year peak' : `prior ${n} days`}`,
  };
}

/* ── Delta classification ────────────────────────────────────────────────── */

function pctDelta(cur: number, base: number): number {
  if (!base) return cur ? (cur > 0 ? 100 : -100) : 0;
  return ((cur - base) / Math.abs(base)) * 100;
}

export function classifyDelta(
  key: string, label: string, cur: number, base: number,
  kind: MetricDelta['kind'], th: BriefThresholds = BRIEF_THRESHOLDS,
): MetricDelta {
  const deltaPct = pctDelta(cur, base);
  const deltaAbs = cur - base;
  let moved: boolean;
  if (kind === 'ratio') moved = Math.abs(deltaAbs) >= th.roasAbs || Math.abs(deltaPct) >= th.pctMove;
  else if (kind === 'pct') moved = Math.abs(deltaAbs) >= th.orgPt;
  else moved = Math.abs(deltaPct) >= th.pctMove;
  const dir: MetricDelta['dir'] = !moved ? 'flat' : deltaAbs > 0 ? 'up' : 'dn';
  return { key, label, cur, base, deltaPct, deltaAbs, dir, moved, kind };
}

/* ── Derived ratios ──────────────────────────────────────────────────────── */

const netRoas = (a: Agg) => a.ad_cost ? (a.sales - a.cogs) / a.ad_cost : 0;
const adsRoas = (a: Agg) => a.ads_spend ? a.ads_sales / a.ads_spend : 0;
// True organic share from organic_units (UnifiedPerformance); falls back to the
// (orders − ad_orders)/orders proxy only if units are missing.
const organicPct = (a: Agg) =>
  a.units ? Math.max(0, (a.organic_units / a.units) * 100)
  : a.orders ? Math.max(0, ((a.orders - a.ads_orders) / a.orders) * 100) : 0;

/* ── Per-family KPI deltas ───────────────────────────────────────────────── */

function familyKpis(cur: Agg, base: Agg, scale: number, adsOnly: boolean, th: BriefThresholds): MetricDelta[] {
  if (adsOnly) {
    return [
      classifyDelta('ads_spend', 'Ads Spend', cur.ads_spend, base.ads_spend * scale, 'money', th),
      classifyDelta('ads_sales', 'Ads Sales', cur.ads_sales, base.ads_sales * scale, 'money', th),
      classifyDelta('ads_orders', 'Ads Orders', cur.ads_orders, base.ads_orders * scale, 'int', th),
      classifyDelta('ads_roas', 'Ads ROAS', adsRoas(cur), adsRoas(base), 'ratio', th),
    ];
  }
  return [
    classifyDelta('sales', 'Sales', cur.sales, base.sales * scale, 'money', th),
    classifyDelta('net_profit', 'Net Profit', cur.net_profit, base.net_profit * scale, 'money', th),
    classifyDelta('net_roas', 'Net ROAS', netRoas(cur), netRoas(base), 'ratio', th),
    classifyDelta('organic_pct', 'Organic', organicPct(cur), organicPct(base), 'pct', th),
  ];
}

/* ── OOS risk ────────────────────────────────────────────────────────────── */

export interface OosRisk { name: string; daysToOut: number; alreadyOos: boolean; }

export function familyOosRisks(
  supply: SupplyChainRow[], oosDays: { asin: string; oos_days_7d: number }[],
  asinToFamily: Map<string, string>, family: string, th: BriefThresholds = BRIEF_THRESHOLDS,
): OosRisk[] {
  const oosByAsin = new Map(oosDays.map(o => [o.asin, o.oos_days_7d]));
  const out: OosRisk[] = [];
  for (const sc of supply) {
    if (asinToFamily.get(sc.asin) !== family) continue;
    const cov = sc.days_of_coverage;
    const alreadyOos = (oosByAsin.get(sc.asin) || 0) > 0;
    if (cov == null) { if (alreadyOos) out.push({ name: sc.product_short_name, daysToOut: 0, alreadyOos: true }); continue; }
    const shipSooner = sc.days_to_next_shipment != null && sc.days_to_next_shipment <= cov;
    if (cov <= th.oosDays && !shipSooner) out.push({ name: sc.product_short_name, daysToOut: Math.round(cov), alreadyOos });
  }
  return out.sort((a, b) => a.daysToOut - b.daysToOut);
}

/* ── Per-product movement ────────────────────────────────────────────────── */

/** Full-P&L per-product movement from daily_trends_by_asin (Yesterday / 7d / 30d). */
function productMovesPnl(
  rows: DailyTrendByAsinRow[], family: string, w: ResolvedWindow, th: BriefThresholds,
): ProductMove[] {
  const cur: Record<string, Agg> = {};
  const base: Record<string, Agg> = {};
  const bump = (m: Record<string, Agg>, name: string, r: DailyTrendByAsinRow) => {
    const a = m[name] || (m[name] = emptyAgg());
    a.sales += r.sales || 0; a.net_profit += r.net_profit || 0; a.units += r.units || 0; a.ad_cost += r.ad_cost || 0;
  };
  for (const r of rows) {
    if (r.product_type !== family) continue;
    const name = r.product_short_name || r.asin || '';
    if (!name) continue;
    if (inRange(r.date, w.curStart, w.curEnd)) bump(cur, name, r);
    else if (inRange(r.date, w.baseStart, w.baseEnd)) bump(base, name, r);
  }
  const moves: (ProductMove & { mag: number })[] = [];
  for (const name of Object.keys(cur)) {
    const c = cur[name], b = base[name] || emptyAgg();
    const salesD = classifyDelta('sa', 'Sales', c.sales, b.sales * w.baseScale, 'money', th);
    const npD = classifyDelta('np', 'Profit', c.net_profit, b.net_profit * w.baseScale, 'money', th);
    if (!salesD.moved && !npD.moved) continue;
    moves.push({ name, text: pnlPhrase(salesD, npD), mag: Math.abs(salesD.deltaAbs) + Math.abs(npD.deltaAbs) });
  }
  return moves.sort((a, b) => b.mag - a.mag).slice(0, 5).map(({ name, text }) => ({ name, text }));
}

function pnlPhrase(sales: MetricDelta, np: MetricDelta): string {
  const parts: string[] = [];
  if (sales.moved) parts.push(`sales ${signPct(sales.deltaPct)}`);
  if (np.moved) parts.push(`profit ${signPct(np.deltaPct)}`);
  return parts.join(', ');
}

/** Ads-only per-product movement from ads_7d (Today mode — orders not in yet). */
function productMovesAds(
  adsRows: Ads7dRow[], productToFamily: Record<string, string>, family: string,
  w: ResolvedWindow, th: BriefThresholds,
): ProductMove[] {
  const cur: Record<string, Agg> = {};
  const base: Record<string, Agg> = {};
  const bump = (m: Record<string, Agg>, name: string, r: Ads7dRow) => {
    const a = m[name] || (m[name] = emptyAgg());
    a.ads_spend += r.spend || 0; a.ads_sales += r.sales || 0; a.ads_orders += r.orders || 0;
  };
  for (const r of adsRows) {
    const fam = resolveAdsFamily(r, productToFamily);
    if (fam !== family) continue;
    const name = r.product_short_name || '';
    if (!name) continue;
    const d = r.date || '';
    if (inRange(d, w.curStart, w.curEnd)) bump(cur, name, r);
    else if (inRange(d, w.baseStart, w.baseEnd)) bump(base, name, r);
  }
  const moves: (ProductMove & { mag: number })[] = [];
  for (const name of Object.keys(cur)) {
    const c = cur[name], b = base[name] || emptyAgg();
    const spendD = classifyDelta('s', 'Spend', c.ads_spend, b.ads_spend * w.baseScale, 'money', th);
    const salesD = classifyDelta('sa', 'Sales', c.ads_sales, b.ads_sales * w.baseScale, 'money', th);
    const roasD = classifyDelta('r', 'ROAS', adsRoas(c), adsRoas(b), 'ratio', th);
    if (!spendD.moved && !salesD.moved && !roasD.moved) continue;
    const mag = Math.abs(salesD.deltaAbs) + Math.abs(spendD.deltaAbs);
    moves.push({ name, text: productPhrase(spendD, salesD, roasD), mag });
  }
  // Biggest movers first (by absolute ads sales + spend delta); cap at 5.
  return moves.sort((a, b) => b.mag - a.mag).slice(0, 5).map(({ name, text }) => ({ name, text }));
}

function productPhrase(spend: MetricDelta, sales: MetricDelta, roas: MetricDelta): string {
  const parts: string[] = [];
  if (spend.moved) parts.push(`spend ${signPct(spend.deltaPct)}`);
  if (sales.moved) parts.push(`ads sales ${signPct(sales.deltaPct)}`);
  if (roas.moved) parts.push(`ROAS ${roas.deltaAbs >= 0 ? '+' : ''}${roas.deltaAbs.toFixed(1)}x`);
  if (spend.moved && spend.dir === 'up' && !sales.moved) parts.push('— spend up, sales flat');
  return parts.join(', ');
}

const signPct = (p: number) => `${p >= 0 ? '+' : ''}${p.toFixed(0)}%`;

/* ── Narrative builders ──────────────────────────────────────────────────── */

function familyRead(kpis: MetricDelta[], oos: OosRisk[], adsOnly: boolean): string {
  const get = (k: string) => kpis.find(m => m.key === k);
  if (oos.length) {
    const soon = oos[0];
    if (soon.alreadyOos) return 'Stock has run out on at least one product — sales constrained by supply.';
    return `Stock running thin — likely supply-driven, not demand. ${soon.name} runs out in ~${soon.daysToOut} days.`;
  }
  if (adsOnly) {
    const spend = get('ads_spend'), sales = get('ads_sales'), roas = get('ads_roas');
    if (sales?.dir === 'up' && roas?.dir !== 'dn') return 'Ads pulling well so far today — ads sales up.';
    if (spend?.dir === 'up' && sales?.dir !== 'up') return 'Spending more today without the sales to match yet.';
    if (roas?.dir === 'dn') return 'Ad efficiency softer so far today.';
    return 'Tracking close to the recent daily average.';
  }
  const sales = get('sales'), np = get('net_profit'), roas = get('net_roas'), org = get('organic_pct');
  if (sales?.dir === 'up' && np?.dir === 'up') return 'Strong stretch — sales up and profit up even faster.';
  if (sales?.dir !== 'up' && np?.dir === 'dn') return 'Margin slipping as ad spend climbs — sales not keeping pace.';
  if (sales?.dir === 'up' && np?.dir === 'dn') return 'Selling more but earning less per sale — margin under pressure.';
  if (roas?.dir === 'up') return 'Ads getting more efficient.';
  if (org?.dir === 'dn') return 'Leaning more on ads — organic share slipping.';
  if (sales?.dir === 'dn') return 'Sales easing versus the comparison window.';
  return 'No material change versus the comparison window.';
}

function familyAttention(
  kpis: MetricDelta[], oos: OosRisk[], coachCount: number, urgentCount: number,
): AttentionItem[] {
  const items: AttentionItem[] = [];
  for (const r of oos) {
    items.push({ level: 'risk', text: r.alreadyOos ? `${r.name} — out of stock now` : `${r.name} — out of stock in ~${r.daysToOut} days` });
  }
  // Lead with the actionable subset (reduce-bid / negate). The raw total is keyword-grain
  // and too noisy for a "what to notice" brief.
  if (urgentCount > 0) {
    items.push({ level: 'warn', text: `${urgentCount} urgent coach action${urgentCount > 1 ? 's' : ''} — reduce-bid / negate` });
  } else if (coachCount > 0) {
    items.push({ level: 'warn', text: `${coachCount} coach action${coachCount > 1 ? 's' : ''} pending` });
  }
  const org = kpis.find(m => m.key === 'organic_pct');
  if (org?.dir === 'dn') items.push({ level: 'watch', text: `Organic share −${Math.abs(org.deltaAbs).toFixed(0)}pt — getting more ads-dependent` });
  const np = kpis.find(m => m.key === 'net_profit'), sales = kpis.find(m => m.key === 'sales');
  if (np?.dir === 'dn' && sales?.dir !== 'dn') items.push({ level: 'watch', text: 'Margin softening — profit down without a sales drop' });
  return items;
}

function familyHealth(kpis: MetricDelta[], oos: OosRisk[], coachCount: number): Health {
  if (oos.length) return 'risk';
  const np = kpis.find(m => m.key === 'net_profit'), roas = kpis.find(m => m.key === 'net_roas' || m.key === 'ads_roas');
  const org = kpis.find(m => m.key === 'organic_pct');
  if ((np?.dir === 'dn') || (roas?.dir === 'dn') || (org?.dir === 'dn') || coachCount > 0) return 'warn';
  if (kpis.some(m => m.dir === 'up')) return 'good';
  return 'flat';
}

/* ── Build the model ─────────────────────────────────────────────────────── */

function buildProductToFamily(products: ProductRow[]): Record<string, string> {
  const map: Record<string, string> = {};
  for (const p of products) {
    const fam = p.parent_name || p.product_short_name || '';
    if (fam && p.product_short_name) map[p.product_short_name] = fam;
  }
  return map;
}

function buildAsinToFamily(products: ProductRow[]): Map<string, string> {
  const m = new Map<string, string>();
  for (const p of products) if (p.asin) m.set(p.asin, p.parent_name || p.product_short_name || '');
  return m;
}

function coachActionsForFamily(actions: ActionRow[], family: string): { count: number; urgent: number } {
  let count = 0, urgent = 0;
  for (const a of actions) {
    // Prefer the authoritative parent_name; fall back to fuzzy name matching only when
    // it's missing, so an action can't be counted against more than one family.
    const match = a.parent_name
      ? a.parent_name === family
      : experimentMatchesFamily(a.product_short_name || '', family as never)
        || experimentMatchesFamily(a.experiment_name || a.campaign_name || '', family as never);
    if (!match) continue;
    count += 1;
    if (a.action === 'REDUCE_BID' || a.action === 'NEGATE_TERM') urgent += 1;
  }
  return { count, urgent };
}

function maxDate(rows: { date?: string }[]): string {
  let mx = '';
  for (const r of rows) if (r.date && r.date > mx) mx = r.date;
  return mx;
}

export function buildBriefModel(data: DashboardData, mode: DateMode, now: Date = new Date(), th: BriefThresholds = BRIEF_THRESHOLDS): BriefModel {
  // Per-ASIN daily P&L is the canonical daily source (rolled up to family). ads_7d (daily,
  // with parent_name) is used only for Today mode, where orders/P&L aren't in yet.
  const byAsin = data.daily_trends_by_asin || [];
  const ads = data.ads_7d || [];
  const products = data.products || [];
  const fresh = data._meta?.data_freshness || {};
  const perfMax = fresh.performance_max_date || maxDate(byAsin);
  const adsMax = fresh.ads_max_date || maxDate(ads);
  const today = todayStr(now);
  const todayEnabled = !!adsMax && adsMax === today;

  const productToFamily = buildProductToFamily(products);
  const asinToFamily = buildAsinToFamily(products);
  const pk = data.peak?.[0] ?? null;

  // Family universe: by-asin families ∪ product parent_names.
  const famSet = new Set<string>();
  for (const r of byAsin) if (r.product_type) famSet.add(r.product_type);
  for (const p of products) if (p.parent_name) famSet.add(p.parent_name);
  const families = [...famSet].filter(Boolean);

  const lyShift = peakShiftDays(data.holidays || [], pk);
  const w = resolveWindow(mode, perfMax, adsMax, pk, now, lyShift);
  const approxNote = w.peak
    ? `Compared to last-year ${pk?.holiday_name || 'peak'} (aligned to peak date).`
    : undefined;

  const views: FamilyView[] = families.map(family => {
    // Today mode (ads-only): family agg from ads_7d. Otherwise: full P&L from by-asin.
    const aggFor = (cs: string, ce: string): Agg => {
      if (w.adsOnly) { const a = emptyAgg(); addAds(a, ads, productToFamily, family, cs, ce); return a; }
      return sumByAsin(byAsin, family, cs, ce);
    };
    const cur = aggFor(w.curStart, w.curEnd);
    let base = aggFor(w.baseStart, w.baseEnd);

    // Peak fallback: no LY rows for this family → revert to the prior-window baseline.
    let win = w;
    if (w.peak && base.rows === 0 && cur.rows > 0) {
      win = resolveWindow(mode, perfMax, adsMax, null, now);
      base = sumByAsin(byAsin, family, win.baseStart, win.baseEnd);
    }

    const kpis = familyKpis(cur, base, win.baseScale, win.adsOnly, th);
    const oos = familyOosRisks(data.supply_chain || [], data.asin_oos_days || [], asinToFamily, family, th);
    const coach = coachActionsForFamily(data.actions || [], family);
    const products_ = win.adsOnly
      ? productMovesAds(ads, productToFamily, family, win, th)
      : productMovesPnl(byAsin, family, win, th);
    const steady = !kpis.some(m => m.moved) && oos.length === 0 && coach.count === 0;

    return {
      family,
      health: familyHealth(kpis, oos, coach.count),
      steady,
      adsOnly: win.adsOnly,
      approxNote: win.peak ? approxNote : undefined,
      read: familyRead(kpis, oos, win.adsOnly),
      kpis,
      products: products_,
      attention: familyAttention(kpis, oos, coach.count, coach.urgent),
    };
  });

  // Movers first, steady last; within each, risk → warn → good.
  const order: Record<Health, number> = { risk: 0, warn: 1, good: 2, flat: 3 };
  views.sort((a, b) => (Number(a.steady) - Number(b.steady)) || (order[a.health] - order[b.health]) || a.family.localeCompare(b.family));

  return {
    dateMode: mode,
    periodLabel: w.label,
    todayEnabled,
    todayDisabledReason: todayEnabled ? undefined : "Today's ads data isn't in yet",
    overview: buildOverview(views, w.adsOnly),
    families: views,
  };
}

function buildOverview(views: FamilyView[], adsOnly: boolean): OverviewView {
  const oosFams = views.filter(v => v.health === 'risk');
  const driver = [...views].filter(v => !v.adsOnly).sort((a, b) => {
    const an = a.kpis.find(m => m.key === 'net_profit')?.deltaAbs ?? a.kpis.find(m => m.key === 'ads_sales')?.deltaAbs ?? 0;
    const bn = b.kpis.find(m => m.key === 'net_profit')?.deltaAbs ?? b.kpis.find(m => m.key === 'ads_sales')?.deltaAbs ?? 0;
    return bn - an;
  })[0];

  let headline: string;
  if (adsOnly) {
    headline = driver ? `Today (ads only): ${driver.family} leading so far.` : 'Today (ads only).';
  } else {
    const totNp = views.reduce((s, v) => s + (v.kpis.find(m => m.key === 'net_profit')?.deltaAbs ?? 0), 0);
    const totBaseNp = views.reduce((s, v) => s + (v.kpis.find(m => m.key === 'net_profit')?.base ?? 0), 0);
    const npPct = totBaseNp ? (totNp / Math.abs(totBaseNp)) * 100 : 0;
    headline = `Net profit ${npPct >= 0 ? 'up' : 'down'} ${Math.abs(npPct).toFixed(0)}% vs the window`;
    headline += (driver && driver.kpis.find(m => m.key === 'net_profit')?.dir === 'up') ? `, carried by ${driver.family}.` : '.';
  }
  if (oosFams.length) headline += ` ${oosFams.length} ${oosFams.length > 1 ? 'families face' : 'family faces'} out-of-stock risk.`;

  const attention: AttentionItem[] = [];
  for (const v of oosFams) for (const a of v.attention.filter(x => x.level === 'risk')) attention.push({ level: 'risk', text: `${v.family}: ${a.text}` });
  const coachTotal = views.reduce((s, v) => s + v.attention.filter(x => x.level === 'warn' && x.text.includes('coach')).length, 0);
  if (coachTotal) attention.push({ level: 'warn', text: `Coach actions pending across ${coachTotal} ${coachTotal > 1 ? 'families' : 'family'}` });
  for (const v of views) for (const a of v.attention.filter(x => x.level === 'watch')) attention.push({ level: 'watch', text: `${v.family}: ${a.text}` });

  return { headline, attention: attention.slice(0, 6) };
}

/* ── Display formatters (re-exported for the component) ──────────────────── */

export function formatMetric(m: MetricDelta): string {
  if (m.kind === 'money') return fM(m.cur);
  if (m.kind === 'ratio') return fR(m.cur);
  if (m.kind === 'pct') return fP(m.cur);
  return Math.round(m.cur).toLocaleString();
}

export function formatDelta(m: MetricDelta): string {
  if (m.kind === 'ratio') return `${m.deltaAbs >= 0 ? '+' : ''}${m.deltaAbs.toFixed(1)}x`;
  if (m.kind === 'pct') return `${m.deltaAbs >= 0 ? '+' : ''}${m.deltaAbs.toFixed(0)}pt`;
  return `${m.deltaPct >= 0 ? '+' : ''}${m.deltaPct.toFixed(0)}%`;
}
