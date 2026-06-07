import { useState, useMemo, useEffect, useCallback, Fragment } from 'react';

import { Calculator, AlertTriangle, RotateCcw, ChevronDown, ChevronRight, Package, TrendingUp, BarChart3, ShoppingCart, ClipboardCopy, FileText, Save, Check, Trash2, CheckCircle, Plus, ArrowLeftRight, Lock, SlidersHorizontal, RefreshCw, Download } from 'lucide-react';
import type { DashboardData, ShipmentPlanRow } from '../types';
import { useShipmentPlan, useScheduledShipments, useShipmentHistory, ReplenishmentFlowSection, ShipmentCardSection } from '../components/ShipmentEngine';
import { PlanWizard } from '../components/PlanWizard';
import type { MonthDef } from '../planTypes';
import { composeMonthlyPlan, aggregateAdsTargetSpend, buildEffectiveProjs, monthFractions, sumOverPeriod, netProfitPlan, latestCompleteWeekRange, blendedNetRoas, MONTH_ABBR, weightedRunRate } from '../planTypes';
import { Tip } from '../components/Tooltip';
import { fM, fK, fP, fmt } from '../utils';
import { useFilters, famFromType } from '../hooks/useFilters';

export const renderDeltaNode = (base: number, cmp: number, mode: 'currency' | 'number' | 'multiplier' = 'currency', inverseGood: boolean = false, className: string = '') => {
  if (base === 0 && cmp === 0) return null;
  const diff = base - cmp;
  if (Math.abs(diff) < 0.01) return null;
  const isGood = inverseGood ? diff <= 0 : diff >= 0;
  const color = isGood ? 'text-emerald-400 bg-emerald-500/10' : 'text-red-400 bg-red-500/10';
  const sign = diff > 0 ? '+' : '';
  let txt = '';
  if (mode === 'currency') txt = `$${fK(Math.abs(diff)).replace('$', '')}`;
  else if (mode === 'multiplier') txt = `${Math.abs(diff).toFixed(2)}×`;
  else txt = fK(Math.abs(diff));
  
  return <span className={`inline-flex items-center px-1.5 py-0.5 rounded text-[9px] font-bold leading-none ${color} ${className}`}>
    {sign}{diff < 0 ? '-' : ''}{txt}
  </span>;
};

// ... (rest of imports untouched, wait I need to check the exact lines)

/** Format as units (not "ord") for inventory/stock context */
const fU = (n: number) => fmt(n) + ' units';
import { Section } from '../components/Section';


// ─── Constants ────────────────────────────────────────────
const CUBE_API = import.meta.env.VITE_CUBE_API_URL || (import.meta.env.DEV ? 'http://localhost:4000' : '');
const todayStatic = new Date();
const currentMonthIdxStatic = todayStatic.getMonth() + 1; // 1-12
const currentYearStatic = todayStatic.getFullYear();

// Order placed now must cover demand through here; this window IS the buffer. Bump each cycle.
const PLAN_END_YEAR = 2027;
const PLAN_END_MONTH = 2; // February

function getMonthsList() {
  const list = [];
  const monthLabels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  let y = currentYearStatic;
  let m = currentMonthIdxStatic;
  // Anchored to a fixed end (not rolling) so the horizon shrinks as the cycle advances.
  while (y < PLAN_END_YEAR || (y === PLAN_END_YEAR && m <= PLAN_END_MONTH)) {
    const days = new Date(y, m, 0).getDate();
    list.push({
      key: `${monthLabels[m-1].toLowerCase()}${y.toString().slice(2)}`,
      label: monthLabels[m-1],
      days,
      year: y,
      month: m
    });
    m++;
    if (m > 12) {
      m = 1;
      y++;
    }
  }
  // Never return empty (MONTHS[0] is consumed widely) if the end date has already passed.
  if (list.length === 0) {
    list.push({
      key: `${monthLabels[currentMonthIdxStatic-1].toLowerCase()}${currentYearStatic.toString().slice(2)}`,
      label: monthLabels[currentMonthIdxStatic-1],
      days: new Date(currentYearStatic, currentMonthIdxStatic, 0).getDate(),
      year: currentYearStatic, month: currentMonthIdxStatic,
    });
  }
  return list;
}

const MONTHS = getMonthsList();
// Colors loaded dynamically from DE_COLOR_MAP via ProductColorMap Cube
// No hardcoded colors — new products get colors automatically from BigQuery
let FAMILY_COLORS: Record<string, string> = {};
let PROD_COLORS: Record<string, string> = {};
const YOY: Record<string, number> = {
  'White Lollibox': 1.14, 'Purple Lollibox': 0.83, 'Pink Lollibox': 0.94, 'Blue Lollibox': 0.82,
  'Mint LolliME': 1.20, 'Pink LolliME': 1.20, 'Purple LolliME': 1.20,
  'Fresh in Pink': 1.34, 'Fresh in Beige': 1.34, 'Truth Or Dare': 1.20,
};
const MFR: Record<string, number> = {
  'White Lollibox': 12.53, 'Purple Lollibox': 11.94, 'Pink Lollibox': 11.28, 'Blue Lollibox': 12.96,
  'Mint LolliME': 7.14, 'Pink LolliME': 7.14, 'Purple LolliME': 7.14,
  'Fresh in Pink': 10.81, 'Fresh in Beige': 10.47, 'Fresh in Blue': 10.81, 'Fresh in Purple': 10.81,
  'Truth Or Dare': 5.21,
};
const SHIP: Record<string, number> = {
  'White Lollibox': 2.51, 'Purple Lollibox': 1.90, 'Pink Lollibox': 1.89, 'Blue Lollibox': 2.14,
  'Mint LolliME': 1.90, 'Pink LolliME': 1.90, 'Purple LolliME': 1.90,
  'Fresh in Pink': 2.85, 'Fresh in Beige': 2.90, 'Fresh in Blue': 2.85, 'Fresh in Purple': 2.85,
  'Truth Or Dare': 0.82,
};
// ─── Dynamic Forecast ROAS ────────────────────────────────────
// Source: V_FORECAST_ROAS via Cube (ForecastRoas)
// Method: Event-anchored weekly mapping from DIM_US_HOLIDAYS
//         + √(clamped 8-week YoY lift)
// Updates automatically as new data flows in — no hardcoded constants.
// Map: family → month(1-12) → { roas, adSpend }
interface ForecastMonthData { roas: number; adSpend: number }
type ForecastRoasMap = Record<string, Record<number, ForecastMonthData>>;
// Map: product → yearMonth(yyyyMM) → forecast_units (from V_FORECAST_DEMAND)
type ForecastDemandMap = Record<string, Record<number, number>>;
// Per-product metadata from V_FORECAST_DEMAND
interface ForecastProductMeta { isNew: boolean; isDraft: boolean; share: number; family: string; forecastPhase?: string; modelProduct?: string }
type ForecastMetaMap = Record<string, ForecastProductMeta>;
// Per-family × month peak/offseason info
interface MonthSeasonInfo { peakDays: number; offseasonDays: number; holidays: string | null }
type MonthSeasonMap = Record<string, Record<number, MonthSeasonInfo>>; // family → yearMonth → info
// Ads efficiency model data: family → month → metrics (from V_ADS_EFFICIENCY_PROFILE)
interface AdsEfficiencyMonth { cpc: number; unitCvrPct: number; adsSharePct: number; netRoas: number; forecastUnits: number; suggestedSpend: number; currentSpend: number; currentForecastUnits: number; currentDailySpend: number; currentCpc: number; currentNetProfit: number; targetNetProfit: number }
type AdsEfficiencyMap = Record<string, Record<number, AdsEfficiencyMonth>>; // family → forecastMonth(1-12) → metrics
const ML = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

// ─── Strategy System ───────────────────────────────────────
type PlanStrategy = 'OPTIMIZED' | 'HISTORIC' | 'HISTORIC_PLUS' | 'SEASONAL' | 'CONSERVATIVE' | 'AGGRESSIVE';
// Strategy presets (STRATEGY_ORDER / STRATEGY_TARGETS / computeStrategyMults) were removed —
// the wizard is now the only forecast lever; per-month mults are loaded from the saved plan and
// drive only the runSim fallback for unplanned families. STRATEGY_LABELS is kept for the
// read-only Strategy label on the expanded row.

// ─── Types ─────────────────────────────────────────────────
interface InvRow { product: string; sourceType: string; units: number }
interface VarBaseline {
  name: string; asin: string; family: string; splitPct: number;
  dailySpend: number; dailyOrders: number; adsShare: number;
  asp: number; costPerUnit: number; mfrCost: number; shipCost: number;
  inventory: number; inventoryBySource: Record<string, number>;
  yoyGrowth: number; cartonQty: number;
  mfrDays: number; shipDays: number;
}
interface FamilyBaseline {
  family: string; dailySpend: number; dailyOrders: number; adsShare: number;
  asp: number; costPerUnit: number; inventory: number;
  inventoryBySource: Record<string, number>; seasonalityIndex: number[];
  variations: VarBaseline[];
}
interface MonthProj {
  month: string; key: string; days: number;
  families: Record<string, { demand: number; revenue: number; cogs: number; adSpend: number; netProfit: number; invEnd: number; isOos: boolean;
    vars: Record<string, { demand: number; revenue: number; cogs: number; adSpend: number; netProfit: number; invEnd: number; isOos: boolean }>;
  }>;
  totalDemand: number; totalRevenue: number; totalCogs: number; totalAdSpend: number; totalNetProfit: number;
}
interface PlanMeta {
  plan_id: string; plan_name: string; plan_year: number; plan_version: number;
  status: 'DRAFT' | 'APPROVED'; updated_at?: string;
}

// ─── Helpers ──────────────────────────────────────────────
// Colors are loaded dynamically from DE_COLOR_MAP — no famFromType needed
function useProductColors() {
  useEffect(() => {
    (async () => {
      try {
        const rows = await cubeLoad({
          dimensions: ['ProductColorMap.family', 'ProductColorMap.productShortName', 'ProductColorMap.familyColorHex', 'ProductColorMap.productColorHex'],
        });
        const fc: Record<string, string> = {};
        const pc: Record<string, string> = {};
        for (const r of rows as Record<string, unknown>[]) {
          const fam = String(r['ProductColorMap.family'] ?? '');
          const prod = String(r['ProductColorMap.productShortName'] ?? '');
          const famHex = String(r['ProductColorMap.familyColorHex'] ?? '#666');
          const prodHex = String(r['ProductColorMap.productColorHex'] ?? '#666');
          if (fam && !fc[fam]) fc[fam] = famHex;
          if (prod) pc[prod] = prodHex;
        }
        FAMILY_COLORS = fc;
        PROD_COLORS = pc;
      } catch (e) { console.warn('[PlanPage] color map load failed', e); }
    })();
  }, []);
}

async function cubeLoad(query: object): Promise<unknown[]> {
  if (!CUBE_API) return [];
  try {
    let retries = 0;
    while (retries < 10) {
      const token = localStorage.getItem('dashboard_token');
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const res = await fetch(`${CUBE_API}/cubejs-api/v1/load`, { method: 'POST', headers, body: JSON.stringify({ query }) });
      if (!res.ok) return [];
      const json = await res.json();
      if (json.error === 'Continue wait') { retries++; await new Promise(r => setTimeout(r, 2000)); continue; }
      if (json.error) return [];
      return json.data ?? [];
    }
    return [];
  } catch { return []; }
}

function useInventoryData() {
  const [inv, setInv] = useState<InvRow[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    (async () => {
      try {
        // First get the latest snapshot date
        const dateRows = await cubeLoad({ measures: ['InventorySnapshot.latestSnapshotDate'] });
        const latestDate = (dateRows as Record<string, unknown>[])[0]?.['InventorySnapshot.latestSnapshotDate'];
        if (!latestDate) { setLoading(false); return; }
        // Then load inventory filtered to latest date only
        const rows = await cubeLoad({
          measures: ['InventorySnapshot.totalUnits'],
          dimensions: ['InventorySnapshot.productShortName', 'InventorySnapshot.sourceType'],
          filters: [{ member: 'InventorySnapshot.date', operator: 'equals', values: [String(latestDate)] }],
        });
        setInv((rows as Record<string, unknown>[]).map(r => ({
          product: String(r['InventorySnapshot.productShortName'] ?? ''), sourceType: String(r['InventorySnapshot.sourceType'] ?? ''), units: Number(r['InventorySnapshot.totalUnits'] ?? 0),
        })).filter(r => r.product && r.units > 0));
      } catch (e) { console.warn('[PlanPage] inv load failed', e); }
      setLoading(false);
    })();
  }, []);
  return { inv, loading };
}



// ─── Fetch dynamic forecast ROAS + mapped ad spend from Cube (V_FORECAST_ROAS) ──
function useForecastRoas() {
  const [forecastMap, setForecastMap] = useState<ForecastRoasMap>({});
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    (async () => {
      try {
        const rows = await cubeLoad({
          dimensions: ['ForecastRoas.family', 'ForecastRoas.forecastYear', 'ForecastRoas.forecastMonth'],
          measures: ['ForecastRoas.forecastRoas', 'ForecastRoas.mappedAdSpend'],
        });
        const map: ForecastRoasMap = {};
        for (const r of rows as Record<string, unknown>[]) {
          const fam = String(r['ForecastRoas.family'] ?? '');
          const mo = Number(r['ForecastRoas.forecastMonth'] ?? 0);
          const roas = Number(r['ForecastRoas.forecastRoas'] ?? 0);
          const adSpend = Number(r['ForecastRoas.mappedAdSpend'] ?? 0);
          if (!fam || !mo) continue;
          if (!map[fam]) map[fam] = {};
          map[fam][mo] = { roas, adSpend };
        }
        console.log('[PlanPage] forecast ROAS loaded:', Object.keys(map).length, 'families');
        setForecastMap(map);
      } catch (e) { console.warn('[PlanPage] forecast ROAS load failed', e); }
      setLoading(false);
    })();
  }, []);
  return { forecastMap, loading };
}

// ─── Fetch ads efficiency profile from Cube (V_ADS_EFFICIENCY_PROFILE) ──
// 3-parameter model: Forecast = Spend / CPC × Unit_CVR / Ads_Share
function useAdsEfficiency() {
  const [adsEfficiency, setAdsEfficiency] = useState<AdsEfficiencyMap>({});
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    (async () => {
      try {
        const rows = await cubeLoad({
          dimensions: [
            'AdsEfficiencyProfile.family', 'AdsEfficiencyProfile.forecastYear',
            'AdsEfficiencyProfile.forecastMonth', 'AdsEfficiencyProfile.cpc',
            'AdsEfficiencyProfile.unitCvrPct', 'AdsEfficiencyProfile.adsSharePct',
            'AdsEfficiencyProfile.netRoas', 'AdsEfficiencyProfile.forecastUnits',
            'AdsEfficiencyProfile.suggestedSpend',
            'AdsEfficiencyProfile.currentSpend', 'AdsEfficiencyProfile.currentForecastUnits',
            'AdsEfficiencyProfile.currentDailySpend', 'AdsEfficiencyProfile.currentCpc',
            'AdsEfficiencyProfile.currentNetProfit', 'AdsEfficiencyProfile.targetNetProfit',
          ],
        });
        const map: AdsEfficiencyMap = {};
        for (const r of rows as Record<string, unknown>[]) {
          const fam = String(r['AdsEfficiencyProfile.family'] ?? '');
          const mo = Number(r['AdsEfficiencyProfile.forecastMonth'] ?? 0);
          if (!fam || !mo) continue;
          if (!map[fam]) map[fam] = {};
          map[fam][mo] = {
            cpc: Number(r['AdsEfficiencyProfile.cpc'] ?? 0),
            unitCvrPct: Number(r['AdsEfficiencyProfile.unitCvrPct'] ?? 0),
            adsSharePct: Number(r['AdsEfficiencyProfile.adsSharePct'] ?? 0),
            netRoas: Number(r['AdsEfficiencyProfile.netRoas'] ?? 0),
            forecastUnits: Number(r['AdsEfficiencyProfile.forecastUnits'] ?? 0),
            suggestedSpend: Number(r['AdsEfficiencyProfile.suggestedSpend'] ?? 0),
            currentSpend: Number(r['AdsEfficiencyProfile.currentSpend'] ?? 0),
            currentForecastUnits: Number(r['AdsEfficiencyProfile.currentForecastUnits'] ?? 0),
            currentDailySpend: Number(r['AdsEfficiencyProfile.currentDailySpend'] ?? 0),
            currentCpc: Number(r['AdsEfficiencyProfile.currentCpc'] ?? 0),
            currentNetProfit: Number(r['AdsEfficiencyProfile.currentNetProfit'] ?? 0),
            targetNetProfit: Number(r['AdsEfficiencyProfile.targetNetProfit'] ?? 0),
          };
        }
        console.log('[PlanPage] ads efficiency loaded:', Object.keys(map).length, 'families');
        setAdsEfficiency(map);
      } catch (e) { console.warn('[PlanPage] ads efficiency load failed', e); }
      setLoading(false);
    })();
  }, []);
  return { adsEfficiency, loading };
}

// ─── Fetch per-product demand forecast from Cube (V_FORECAST_DEMAND) ──
// Family-level daily-ramp forecast with product share split + cannibalization
function useForecastDemand() {
  const [demandMap, setDemandMap] = useState<ForecastDemandMap>({});
  const [metaMap, setMetaMap] = useState<ForecastMetaMap>({});
  const [seasonMap, setSeasonMap] = useState<MonthSeasonMap>({});
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    (async () => {
      try {
        const rows = await cubeLoad({
          dimensions: [
            'ForecastDemand.product', 'ForecastDemand.family',
            'ForecastDemand.forecastYear', 'ForecastDemand.forecastMonth',
            'ForecastDemand.productShare', 'ForecastDemand.isNewProduct',
            'ForecastDemand.isDraft', 'ForecastDemand.peakHolidays',
            'ForecastDemand.forecastPhase', 'ForecastDemand.modelProduct',
          ],
          measures: ['ForecastDemand.forecastUnits', 'ForecastDemand.peakDays', 'ForecastDemand.offseasonDays'],
        });
        const dMap: ForecastDemandMap = {};
        const mMap: ForecastMetaMap = {};
        const sMap: MonthSeasonMap = {};
        for (const r of rows as Record<string, unknown>[]) {
          const prod = String(r['ForecastDemand.product'] ?? '');
          const fam = String(r['ForecastDemand.family'] ?? '');
          const yr = Number(r['ForecastDemand.forecastYear'] ?? 0);
          const mo = Number(r['ForecastDemand.forecastMonth'] ?? 0);
          const units = Number(r['ForecastDemand.forecastUnits'] ?? 0);
          const share = Number(r['ForecastDemand.productShare'] ?? 0);
          const isNew = String(r['ForecastDemand.isNewProduct'] ?? 'false') === 'true';
          const isDraft = String(r['ForecastDemand.isDraft'] ?? 'false') === 'true';
          const forecastPhase = r['ForecastDemand.forecastPhase'] ? String(r['ForecastDemand.forecastPhase']) : undefined;
          const modelProduct = r['ForecastDemand.modelProduct'] ? String(r['ForecastDemand.modelProduct']) : undefined;
          const peakDays = Number(r['ForecastDemand.peakDays'] ?? 0);
          const offDays = Number(r['ForecastDemand.offseasonDays'] ?? 0);
          const holidays = r['ForecastDemand.peakHolidays'] ? String(r['ForecastDemand.peakHolidays']) : null;
          if (!prod || !yr || !mo) continue;
          if (!dMap[prod]) dMap[prod] = {};
          const key = yr * 100 + mo;
          dMap[prod][key] = units;
          // Product meta (take first occurrence)
          if (!mMap[prod]) mMap[prod] = { isNew, isDraft, share, family: fam, forecastPhase, modelProduct };
          // Season info per family × month
          if (fam) {
            if (!sMap[fam]) sMap[fam] = {};
            if (!sMap[fam][key]) sMap[fam][key] = { peakDays, offseasonDays: offDays, holidays };
          }
        }
        console.log('[PlanPage] forecast demand loaded:', Object.keys(dMap).length, 'products,', Object.keys(mMap).filter(k => mMap[k].isNew).length, 'new');
        setDemandMap(dMap);
        setMetaMap(mMap);
        setSeasonMap(sMap);
      } catch (e) { console.warn('[PlanPage] forecast demand load failed', e); }
      setLoading(false);
    })();
  }, []);
  return { demandMap, metaMap, seasonMap, loading };
}

function computeSeasonality(family: string, monthlyTrends: DashboardData['monthly_trends']): number[] {
  const rows = monthlyTrends.filter(r => r.month_start?.startsWith('2025') && r.product_type === family);
  if (!rows.length) return Array(12).fill(1);
  const mo = Array(12).fill(0);
  for (const r of rows) mo[new Date(r.month_start!).getMonth()] += r.orders ?? 0;
  // Only average across months that had actual data (non-zero)
  // Products launched mid-year should not get 0 for pre-launch months
  const activeMonths = mo.filter(v => v > 0);
  const avg = activeMonths.length > 0 ? activeMonths.reduce((a, b) => a + b, 0) / activeMonths.length : 1;
  // For months with no data (pre-launch), use 1.0 (flat = current velocity)
  return mo.map(v => v > 0 ? v / avg : 1.0);
}

// ─── Build family baselines with variation splits ─────────
function buildFamilyBaselines(data: DashboardData, inv: InvRow[], metaMap?: ForecastMetaMap): FamilyBaseline[] {
  // Compute per-product 6-month share from weekly_trends_by_asin
  const allWeeks = [...new Set(data.weekly_trends_by_asin.map(r => r.week_start ?? '').filter(Boolean))].sort();
  const last26 = allWeeks.slice(-26); // ~6 months
  const prodOrders6m = new Map<string, number>();
  const prodSales6m = new Map<string, number>();
  const prodMeta = new Map<string, { asin: string; family: string }>();
  for (const r of data.weekly_trends_by_asin) {
    if (!last26.includes(r.week_start ?? '')) continue;
    const n = r.product_short_name;
    if (!n) continue;
    prodOrders6m.set(n, (prodOrders6m.get(n) ?? 0) + (r.orders ?? 0));
    prodSales6m.set(n, (prodSales6m.get(n) ?? 0) + (r.sales ?? 0));
    if (!prodMeta.has(n)) prodMeta.set(n, { asin: r.asin ?? '', family: r.product_type });
  }

  // Group by family
  const famMap = new Map<string, { products: Map<string, { orders6m: number; asin: string }> }>();
  for (const [name, meta] of prodMeta) {
    if (!famMap.has(meta.family)) famMap.set(meta.family, { products: new Map() });
    famMap.get(meta.family)!.products.set(name, { orders6m: prodOrders6m.get(name) ?? 0, asin: meta.asin });
  }

  // Get latest-week data per product
  const latestWeek = allWeeks[allWeeks.length - 1] ?? '';
  const latestByProd = new Map<string, { orders: number; adCost: number; sales: number; cogs: number; organicPct: number }>();
  for (const r of data.weekly_trends_by_asin.filter(r => r.week_start === latestWeek)) {
    if (r.product_short_name) latestByProd.set(r.product_short_name, {
      orders: r.orders ?? 0, adCost: r.ad_cost ?? 0, sales: r.sales ?? 0, cogs: r.cogs ?? 0, organicPct: r.organic_pct ?? 0,
    });
  }

  // Product cost lookup
  const costMap = new Map<string, number>();
  const cartonMap = new Map<string, number>();
  const mfrDaysMap = new Map<string, number>();
  const shipDaysMap = new Map<string, number>();
  for (const p of data.products) {
    costMap.set(p.product_short_name, p.total_cost_per_unit);
    if (p.package_quantity) cartonMap.set(p.product_short_name, p.package_quantity);
    if (p.manufacture_day) mfrDaysMap.set(p.product_short_name, p.manufacture_day);
    if (p.shipment_days) shipDaysMap.set(p.product_short_name, p.shipment_days);
  }

  const families: FamilyBaseline[] = [];
  const allFamilies = new Set(famMap.keys());
  
  if (metaMap) {
    for (const meta of Object.values(metaMap)) {
      if (meta.family) allFamilies.add(meta.family);
    }
  }
  
  // Dynamic sort: alphabetical for now, re-sorted by YTD sales after baselines are built
  const famOrder = Array.from(allFamilies).sort();

  for (const famName of famOrder) {
    const entry = famMap.get(famName) ?? { products: new Map() };
    const prods = [...entry.products.entries()];
    const totalOrders6m = prods.reduce((s, [, v]) => s + v.orders6m, 0);

    const vars: VarBaseline[] = prods.map(([name, { orders6m, asin }]) => {
      const split = totalOrders6m > 0 ? orders6m / totalOrders6m : 1 / prods.length;
      const lw = latestByProd.get(name);
      const orders7d = lw?.orders ?? 0;
      const adCost7d = lw?.adCost ?? 0;
      const sales7d = lw?.sales ?? 0;
      const orgPct = lw?.organicPct ?? 0;
      const adOrders = Math.round(orders7d * (1 - orgPct / 100));
      const adsShare = orders7d > 0 ? adOrders / orders7d : 0.5;
      let cpu = costMap.get(name) ?? 0;
      if (cpu === 0 && (lw?.cogs ?? 0) > 0 && orders7d > 0) cpu = lw!.cogs / orders7d;
      const pInv = inv.filter(i => i.product === name);
      const invBySource: Record<string, number> = {};
      for (const i of pInv) invBySource[i.sourceType] = (invBySource[i.sourceType] ?? 0) + i.units;
      return {
        name, asin, family: famName, splitPct: split,
        dailySpend: adCost7d / 7, dailyOrders: orders7d / 7, adsShare,
        asp: orders7d > 0 ? sales7d / orders7d : ((prodOrders6m.get(name) ?? 0) > 0 ? (prodSales6m.get(name) ?? 0) / (prodOrders6m.get(name) ?? 1) : 0), costPerUnit: cpu,
        mfrCost: MFR[name] ?? 0, shipCost: SHIP[name] ?? 0,
        inventory: pInv.reduce((s, i) => s + i.units, 0), inventoryBySource: invBySource,
        yoyGrowth: YOY[name] ?? 1.0, cartonQty: cartonMap.get(name) ?? 1,
        mfrDays: mfrDaysMap.get(name) ?? 30, shipDays: shipDaysMap.get(name) ?? 30,
      };
    }).sort((a, b) => b.dailyOrders - a.dailyOrders);

    // ── Inject new products (no sales history) from forecast metaMap ──
    // These need to be part of variations so they react to strategy,
    // show in forecast simulation, and appear in PO plan.
    if (metaMap) {
      const existingNames = new Set(vars.map(v => v.name));
      for (const [name, meta] of Object.entries(metaMap)) {
        if (meta.family !== famName || !meta.isNew || existingNames.has(name)) continue;
        // Inherit family-average ASP, cost, and adsShare from existing vars
        const existingWithOrders = vars.filter(v => v.dailyOrders > 0);
        const avgAsp = existingWithOrders.length > 0
          ? existingWithOrders.reduce((s, v) => s + v.asp * v.dailyOrders, 0) / existingWithOrders.reduce((s, v) => s + v.dailyOrders, 0)
          : 0;
        const avgCpu = existingWithOrders.length > 0
          ? existingWithOrders.reduce((s, v) => s + v.costPerUnit * v.dailyOrders, 0) / existingWithOrders.reduce((s, v) => s + v.dailyOrders, 0)
          : 0;
        const avgAdsShare = existingWithOrders.length > 0
          ? existingWithOrders.reduce((s, v) => s + v.adsShare * v.dailyOrders, 0) / existingWithOrders.reduce((s, v) => s + v.dailyOrders, 0)
          : 0.5;
        const pInv = inv.filter(i => i.product === name);
        const invBySource: Record<string, number> = {};
        for (const i of pInv) invBySource[i.sourceType] = (invBySource[i.sourceType] ?? 0) + i.units;
        vars.push({
          name, asin: '', family: famName, splitPct: meta.share,
          dailySpend: 0, dailyOrders: 0, adsShare: avgAdsShare,
          asp: avgAsp, costPerUnit: avgCpu,
          mfrCost: MFR[name] ?? 0, shipCost: SHIP[name] ?? 0,
          inventory: pInv.reduce((s, i) => s + i.units, 0), inventoryBySource: invBySource,
          yoyGrowth: YOY[name] ?? 1.0, cartonQty: cartonMap.get(name) ?? 1,
          mfrDays: mfrDaysMap.get(name) ?? 30, shipDays: shipDaysMap.get(name) ?? 30,
        });
      }
    }

    const famDailySpend = vars.reduce((s, v) => s + v.dailySpend, 0);
    const famDailyOrders = vars.reduce((s, v) => s + v.dailyOrders, 0);
    const famInv = vars.reduce((s, v) => s + v.inventory, 0);
    const famInvSrc: Record<string, number> = {};
    for (const v of vars) for (const [k, q] of Object.entries(v.inventoryBySource)) famInvSrc[k] = (famInvSrc[k] ?? 0) + q;
    const wAvgAsp = famDailyOrders > 0 ? vars.reduce((s, v) => s + v.asp * v.dailyOrders, 0) / famDailyOrders : 0;
    const wAvgCpu = famDailyOrders > 0 ? vars.reduce((s, v) => s + v.costPerUnit * v.dailyOrders, 0) / famDailyOrders : 0;
    const wAvgAds = famDailyOrders > 0 ? vars.reduce((s, v) => s + v.adsShare * v.dailyOrders, 0) / famDailyOrders : 0.5;

    families.push({
      family: famName, dailySpend: famDailySpend, dailyOrders: famDailyOrders, adsShare: wAvgAds,
      asp: wAvgAsp, costPerUnit: wAvgCpu,
      inventory: famInv, inventoryBySource: famInvSrc,
      seasonalityIndex: computeSeasonality(famName, data.monthly_trends), variations: vars,
    });
  }
  return families;
}

// ─── Cross-family average fallback ROAS ──────────────────
// Used when a family has no forecast data from V_FORECAST_ROAS
function computeCrossFamilyAvg(forecastMap: ForecastRoasMap, month: number): ForecastMonthData | null {
  let sumR = 0, sumA = 0, cnt = 0;
  for (const famData of Object.values(forecastMap)) {
    const d = famData[month];
    if (d != null) { sumR += d.roas; sumA += d.adSpend; cnt++; }
  }
  return cnt > 0 ? { roas: sumR / cnt, adSpend: sumA / cnt } : null;
}

// ─── Simulation (family + per-variation) ──────────────────
function runSim(families: FamilyBaseline[], mults: Record<string, Record<string, number>>, forecastMap: ForecastRoasMap, demandMap: ForecastDemandMap, growthOverrides: Record<string, number>): MonthProj[] {
  const projs: MonthProj[] = [];
  const curInv: Record<string, number> = {};
  const roundCarry: Record<string, number> = {}; // Tracks fractional rounding errors across months for exact precision
  for (const f of families) for (const v of f.variations) curInv[v.name] = v.inventory;
  
  const today = new Date();
  const remDays = Math.max(1, MONTHS[0].days - today.getDate() + 1);

  for (let mi = 0; mi < MONTHS.length; mi++) {
    const m = MONTHS[mi];
    const days = mi === 0 ? remDays : m.days;
    const familiesData: MonthProj['families'] = {};
    let tD = 0, tR = 0, tC = 0, tA = 0, tN = 0;

    for (const f of families) {
      const mult = mults[f.family]?.[m.key] ?? 1;
      const si = f.seasonalityIndex[m.month - 1] ?? 1;
      let fDemand = 0, fRev = 0, fCogs = 0, fAd = 0, fNp = 0, fInvEnd = 0;
      const varData: Record<string, { demand: number; revenue: number; cogs: number; adSpend: number; netProfit: number; invEnd: number; isOos: boolean }> = {};

      // ── Event-Anchored ROAS + Ad Spend from V_FORECAST_ROAS ──
      // Family-level forecast: maps holiday-relative weeks + √(clamped YoY lift)
      // Uses mapped_ad (actual ad spend pattern) scaled by product share
      // Fallback: cross-family avg → flat formula
      const famForecast = forecastMap[f.family];
      const famData = famForecast?.[m.month] ?? computeCrossFamilyAvg(forecastMap, m.month);

      for (const v of f.variations) {
        // Holiday-driven demand from V_FORECAST_DEMAND (per product × year+month)
        // Adjust by multiplier: forecast × ((1 - adsShare) + adsShare × mult)
        const demandKey = m.year * 100 + m.month; // e.g. 202604
        const mapVal = demandMap[v.name]?.[demandKey];
        let rawDemand = 0;
        if (mapVal != null && mapVal > 0) {
          rawDemand = mi === 0 ? mapVal * (days / m.days) : mapVal;
        } else {
          rawDemand = Math.round(v.dailyOrders * si * days);
        }
        const baseDemand = rawDemand * (growthOverrides[v.name] ?? 1.0);
        const adjFactor = (1 - v.adsShare) + v.adsShare * mult;
        
        // Apply error diffusion to ensure sum of integers matches exact float target
        const exactDemand = baseDemand * adjFactor + (roundCarry[v.name] ?? 0);
        const demand = Math.round(exactDemand);
        roundCarry[v.name] = exactDemand - demand;

        // For new products with no sales (ASP=0), inherit family averages
        const asp = v.asp > 0 ? v.asp : f.asp;
        const cpu = v.costPerUnit > 0 ? v.costPerUnit : f.costPerUnit;
        const rev = demand * asp;
        const cog = demand * cpu;

        let ad: number;
        if (famData != null && famData.roas > 0) {
          // Use family-level blended ROAS from V_FORECAST_ROAS
          // Apply √(mult) diminishing returns: higher spend = lower ROAS efficiency
          // mult > 1 → higher bids → win more auctions but pay more per click → ROAS drops
          // mult < 1 → lower bids → fewer auctions but cheaper clicks → ROAS improves
          const effectiveRoas = famData.roas / Math.sqrt(mult);
          const grossProfit = rev - cog;
          ad = grossProfit > 0 ? grossProfit / effectiveRoas : 0;
        } else {
          // No forecast data — fall back to flat formula
          ad = v.dailySpend * si * mult * days;
        }

        const np = rev - cog - ad;
        const prev = curInv[v.name] ?? 0;
        const ie = Math.max(0, prev - demand);
        curInv[v.name] = ie;
        varData[v.name] = { demand, revenue: rev, cogs: cog, adSpend: ad, netProfit: np, invEnd: ie, isOos: prev - demand <= 0 };
        fDemand += demand; fRev += rev; fCogs += cog; fAd += ad; fNp += np; fInvEnd += ie;
      }
      familiesData[f.family] = { demand: fDemand, revenue: fRev, cogs: fCogs, adSpend: fAd, netProfit: fNp, invEnd: fInvEnd, isOos: fInvEnd <= 0, vars: varData };
      tD += fDemand; tR += fRev; tC += fCogs; tA += fAd; tN += fNp;
    }
    projs.push({ month: m.label, key: m.key, days, families: familiesData, totalDemand: tD, totalRevenue: tR, totalCogs: tC, totalAdSpend: tA, totalNetProfit: tN });
  }
  return projs;
}

function getOos(projs: MonthProj[], key: string, isVar: boolean): string | null {
  for (const p of projs) {
    if (isVar) { for (const f of Object.values(p.families)) if (f.vars[key]?.isOos) return p.month; }
    else { if (p.families[key]?.isOos) return p.month; }
  }
  return null;
}

/** Compute OOS month accounting for extra inventory (from prior shipments in the same plan) */
function getOosWithExtra(projs: MonthProj[], key: string, extraUnits: number): string | null {
  // Find current inventory from first projection's invEnd + demand (to get start of period)
  let startInv = 0;
  let found = false;
  for (const p of projs) {
    for (const f of Object.values(p.families)) {
      const v = f.vars[key];
      if (v) { startInv = v.invEnd + v.demand; found = true; break; } // invEnd = prev - demand, so prev = invEnd + demand
    }
    if (found) break;
  }
  // Replay with extra units added
  let rem = startInv + extraUnits;
  for (const p of projs) {
    const demand = Object.values(p.families).reduce((s, f) => s + (f.vars[key]?.demand ?? 0), 0);
    rem -= demand;
    if (rem <= 0) return p.month;
  }
  return null; // no OOS within projection window — stock is sufficient
}

function getWos(inv: number, projs: MonthProj[], key: string, isVar: boolean): number {
  let rem = inv, td = 0;
  for (const p of projs) {
    const d = isVar
      ? Object.values(p.families).reduce((s, f) => s + (f.vars[key]?.demand ?? 0), 0)
      : (p.families[key]?.demand ?? 0);
    if (rem <= 0) break;
    if (rem >= d) { rem -= d; td += p.days; } else { td += Math.round(p.days * (d > 0 ? rem / d : 0)); rem = 0; }
  }
  return Math.round(td / 7);
}

function waveLabel(oos: string | null): { label: string; color: string } {
  if (!oos) return { label: 'OK', color: 'emerald' };
  if (oos === 'Apr' || oos === 'May') return { label: '🔴 W1', color: 'red' };
  if (oos === 'Jun' || oos === 'Jul' || oos === 'Aug') return { label: '🟡 W2', color: 'amber' };
  return { label: '🟢 W3', color: 'emerald' };
}

// ─── Main Component ──────────────────────────────────────
// ─── New: Wrapper for SP-backed Replenishment Flow + Card UI ──────
function ReplenishmentFlowWrapper({ orderOverrides, salesSummary, demandMap, seasonMap, metaMap, growthOverrides, products, projs, unconstrainedForecastMap }: {
  orderOverrides: Record<string, number>;
  salesSummary: {asin: string; product_name: string; sold: number}[];
  demandMap: ForecastDemandMap;
  seasonMap: MonthSeasonMap;
  metaMap: ForecastMetaMap;
  growthOverrides: Record<string, number>;
  products: any[];
  projs: MonthProj[];
  unconstrainedForecastMap: Record<string, number>;
}) {
  const { suggestions, loading: sugLoading, reload: reloadSugg } = useShipmentPlan();
  const { scheduled, loading: schLoading, reload: reloadSched } = useScheduledShipments();
  const { arrived, inTransit, loading: histLoading } = useShipmentHistory();
  const { activePOs, loading: poLoading, reloadPOs, updatePoEtaOptimistic } = useActivePurchaseOrders();

  // Load stock map, MFR Ready, and MFR In Prod per product from InventorySnapshot
  const [stockMap, setStockMap] = useState<Record<string, number>>({});
  const [fbaMap, setFbaMap] = useState<Record<string, number>>({});
  const [awdMap, setAwdMap] = useState<Record<string, number>>({});
  const [mfrReadyMap, setMfrReadyMap] = useState<Record<string, number>>({});
  const [mfrInProdMap, setMfrInProdMap] = useState<Record<string, number>>({});
  const [stockLoading, setStockLoading] = useState(true);
  useEffect(() => {
    (async () => {
      try {
        // First get latest snapshot date to avoid summing across ALL historical dates
        const dateRows = await cubeLoad({ measures: ['InventorySnapshot.latestSnapshotDate'] });
        const latestDate = (dateRows as Record<string, unknown>[])[0]?.['InventorySnapshot.latestSnapshotDate'];
        if (!latestDate) { setStockLoading(false); return; }

        const rows = await cubeLoad({
          measures: ['InventorySnapshot.totalUnits'],
          dimensions: ['InventorySnapshot.productShortName', 'InventorySnapshot.sourceType'],
          filters: [{ member: 'InventorySnapshot.date', operator: 'equals', values: [String(latestDate)] }],
        });
        const map: Record<string, number> = {};
        const fba: Record<string, number> = {};
        const awd: Record<string, number> = {};
        const readyMap: Record<string, number> = {};
        const inProdMap: Record<string, number> = {};
        for (const r of rows as Record<string, unknown>[]) {
          const product = String(r['InventorySnapshot.productShortName'] ?? '');
          const source = String(r['InventorySnapshot.sourceType'] ?? '');
          const units = Number(r['InventorySnapshot.totalUnits'] ?? 0);
          if (!product) continue;
          if (source === 'FBA') {
            map[product] = (map[product] || 0) + units;
            fba[product] = (fba[product] || 0) + units;
          }
          if (source === 'AWD') {
            map[product] = (map[product] || 0) + units;
            awd[product] = (awd[product] || 0) + units;
          }
          if (source === 'MFR Ready') {
            readyMap[product] = (readyMap[product] || 0) + units;
          }
          if (source === 'In Production') {
            inProdMap[product] = (inProdMap[product] || 0) + units;
          }
        }
        setStockMap(map);
        setFbaMap(fba);
        setAwdMap(awd);
        setMfrReadyMap(readyMap);
        setMfrInProdMap(inProdMap);
      } catch (e) { console.warn('[ReplenishmentFlow] stock load failed', e); }
      setStockLoading(false);
    })();
  }, []);


  const fullYearlyPlanMap = useMemo(() => {
    const map: Record<string, number> = {};
    for (const p of products) {
      const vName = p.product_short_name || p.product;
      const cartonQty = p.package_quantity ?? 1;
      let forecast = 0;
      for (const proj of projs) {
        for (const famKey of Object.keys(proj.families)) {
          if (proj.families[famKey].vars[vName]) {
            forecast += proj.families[famKey].vars[vName].demand;
          }
        }
      }
      const sold = salesSummary.find(s => s.product_name === vName || s.asin === p.asin)?.sold ?? 0;
      const yearlyNeed = sold + forecast;
      const raw = orderOverrides[vName] ?? yearlyNeed;
      const stock = stockMap[vName] || 0;
      const rawGap = raw - sold - stock;
      if (rawGap <= 0 || cartonQty <= 1) {
        map[vName] = raw;
      } else {
        const snappedGap = Math.ceil(rawGap / cartonQty) * cartonQty;
        map[vName] = sold + stock + snappedGap;
      }
    }
    return map;
  }, [products, projs, orderOverrides, salesSummary, stockMap]);

  const loading = sugLoading || schLoading || histLoading || stockLoading || poLoading;

  const handleAction = useCallback(() => {
    // Small delay to allow BigQuery streaming buffer to settle
    setTimeout(() => { reloadSugg(); reloadSched(); reloadPOs(); }, 1500);
  }, [reloadSugg, reloadSched, reloadPOs]);

  if (loading) return (
    <Section title="Replenishment Flow">
      <div className="text-center text-muted text-sm py-6">Loading shipment engine data...</div>
    </Section>
  );

  return (
    <>
      <ReplenishmentFlowSection
        yearlyPlanMap={fullYearlyPlanMap}
        unconstrainedForecastMap={unconstrainedForecastMap}
        salesSummary={salesSummary}
        stockMap={stockMap}
        fbaMap={fbaMap}
        awdMap={awdMap}
        mfrReadyMap={mfrReadyMap}
        mfrInProdMap={mfrInProdMap}
        suggestions={suggestions}
        scheduled={scheduled}
        inTransitShipments={inTransit}
        arrivedShipments={arrived}
        onAction={handleAction}
        demandMap={demandMap}
        seasonMap={seasonMap}
        metaMap={metaMap}
        growthOverrides={growthOverrides}
        activePOs={activePOs}
        productMeta={products}
        onUpdateEtaOptimistic={updatePoEtaOptimistic}
      />
      <ShipmentCardSection
        suggestions={suggestions}
        scheduled={scheduled}
        activePOs={activePOs}
        productMeta={products}
        inTransitShipments={inTransit}
        stockMap={stockMap}
        mfrReadyMap={mfrReadyMap}
        mfrInProdMap={mfrInProdMap}
        yearlyPlanMap={orderOverrides}
        salesSummary={salesSummary}
        onAction={handleAction}
        onUpdateEtaOptimistic={updatePoEtaOptimistic}
      />
    </>
  );
}

export interface ActivePORow {
  po_id: string;
  product: string;
  asin: string;
  order_date: string;
  qty: number;
  estimated_arrival_date: string | null;
}

export function useActivePurchaseOrders() {
  const [rows, setRows] = useState<ActivePORow[]>([]);
  const [loading, setLoading] = useState(true);

  const updatePoEtaOptimistic = useCallback((poId: string, eta: string) => {
    setRows(prev => prev.map(r => r.po_id === poId ? { ...r, estimated_arrival_date: eta } : r));
  }, []);

  const fetchPOs = useCallback(async () => {
    try {
      const baseDims = [
        'PurchaseOrdersDashboard.purchaseOrderId',
        'PurchaseOrdersDashboard.productName',
        'PurchaseOrdersDashboard.productAsin',
        'PurchaseOrdersDashboard.orderDate',
        'PurchaseOrdersDashboard.isOpen',
        'PurchaseOrdersDashboard.quantity',
        'PurchaseOrdersDashboard.totalQuantityShipped',
      ];
      const etaDim = 'PurchaseOrdersDashboard.estimatedArrivalDate';
      const filters = [{ member: 'PurchaseOrdersDashboard.isOpen', operator: 'equals' as const, values: ['true'] }];

      // Try with ETA dimension first, fall back without it if Cube schema is stale
      let data: Record<string, unknown>[];
      let hasEta = true;
      try {
        data = await cubeLoad({ measures: [], dimensions: [...baseDims, etaDim], filters, renewQuery: true }) as Record<string, unknown>[];
      } catch {
        hasEta = false;
        data = await cubeLoad({ measures: [], dimensions: baseDims, filters, renewQuery: true }) as Record<string, unknown>[];
      }

      const mapped: ActivePORow[] = data.map(r => {
        const rawEta = hasEta ? r[etaDim] : null;
        const eta = rawEta ? String(rawEta).split('T')[0] : null;
        const totalShipped = Number(r['PurchaseOrdersDashboard.totalQuantityShipped'] ?? 0);
        const qty = Number(r['PurchaseOrdersDashboard.quantity'] ?? 0);
        return {
          po_id: String(r['PurchaseOrdersDashboard.purchaseOrderId'] ?? ''),
          product: String(r['PurchaseOrdersDashboard.productName'] ?? ''),
          asin: String(r['PurchaseOrdersDashboard.productAsin'] ?? ''),
          order_date: String(r['PurchaseOrdersDashboard.orderDate'] ?? ''),
          qty: Math.max(0, qty - totalShipped), // Remaining qty at manufacturer
          estimated_arrival_date: eta,
        };
      }).filter(r => r.qty > 0); // Exclude fully-shipped POs
      setRows(mapped);
    } catch (e) {
      console.warn('Failed to load active POs', e);
    }
    setLoading(false);
  }, []);

  useEffect(() => { fetchPOs(); }, [fetchPOs]);

  return { activePOs: rows, loading, reloadPOs: fetchPOs, updatePoEtaOptimistic };
}

export function PlanPage({ data }: { data: DashboardData }) {
  const { inv, loading } = useInventoryData();
  const { forecastMap, loading: fcLoading } = useForecastRoas();
  const { demandMap, metaMap, seasonMap, loading: dmLoading } = useForecastDemand();
  const { adsEfficiency } = useAdsEfficiency();
  useProductColors(); // Load family/product colors from DE_COLOR_MAP

  // Fetch monthly actuals from Cube using DAILY grain (not weekly) to avoid
  // cross-month week boundary misattribution (e.g., week_start Mar 29 → includes Apr 1-4)
  interface ActualMonth { units: number; revenue: number; cogs: number; adCost: number }
  interface WeekActual { units: number; revenue: number; cogs: number; adCost: number; clicks: number }
  const [actuals2026Full, setActuals2026] = useState<Map<string, Map<number, ActualMonth>>>(new Map());
  const [actuals2025Full, setActuals2025] = useState<Map<string, Map<number, ActualMonth>>>(new Map());
  useEffect(() => {
    const fetchActuals = async (year: number, setter: (m: Map<string, Map<number, ActualMonth>>) => void) => {
      try {
        const endDate = year === new Date().getFullYear()
          ? `${year}-${String(new Date().getMonth() + 1).padStart(2, '0')}-${String(new Date().getDate()).padStart(2, '0')}`
          : `${year}-12-31`;
        const rows = await cubeLoad({
          dimensions: ['UnifiedPerformance.productShortName', 'UnifiedPerformance.monthStart'],
          measures: ['UnifiedPerformance.units', 'UnifiedPerformance.sales', 'UnifiedPerformance.cogs', 'UnifiedPerformance.adCost'],
          timeDimensions: [{ dimension: 'UnifiedPerformance.date', dateRange: [`${year}-01-01`, endDate] }],
        });
        const map = new Map<string, Map<number, ActualMonth>>();
        for (const r of rows as Record<string, unknown>[]) {
          const name = String(r['UnifiedPerformance.productShortName'] ?? '');
          const msRaw = String(r['UnifiedPerformance.monthStart'] ?? '');
          if (!name || !msRaw) continue;
          const mo = new Date(msRaw).getMonth(); // 0-based
          if (!map.has(name)) map.set(name, new Map());
          const pm = map.get(name)!;
          pm.set(mo, {
            units: Number(r['UnifiedPerformance.units'] ?? 0),
            revenue: Number(r['UnifiedPerformance.sales'] ?? 0),
            cogs: Number(r['UnifiedPerformance.cogs'] ?? 0),
            adCost: Number(r['UnifiedPerformance.adCost'] ?? 0),
          });
        }
        console.log(`[PlanPage] ${year} daily actuals loaded:`, map.size, 'products');
        setter(map);
      } catch (e) { console.warn(`[PlanPage] ${year} actuals load failed`, e); }
    };
    fetchActuals(2026, setActuals2026);
    fetchActuals(2025, setActuals2025);
  }, []);

  // Real latest data date for orders/units (FACT_AMAZON_PERFORMANCE_DAILY) — drives the
  // current-month proration cutoff in the wizard instead of a wall-clock lag guess.
  const [latestDataDate, setLatestDataDate] = useState<Date | null>(null);
  useEffect(() => {
    (async () => {
      try {
        const rows = await cubeLoad({
          dimensions: ['DataFreshness.source', 'DataFreshness.maxDate'],
          filters: [{ member: 'DataFreshness.source', operator: 'equals', values: ['FACT_AMAZON_PERFORMANCE_DAILY'] }],
        });
        const raw = (rows as Record<string, unknown>[])[0]?.['DataFreshness.maxDate'];
        if (raw) {
          const d = new Date(String(raw).slice(0, 10) + 'T00:00:00');
          if (!isNaN(d.getTime())) { setLatestDataDate(d); console.log('[PlanPage] perf data through:', d.toISOString().slice(0, 10)); }
        }
      } catch (e) { console.warn('[PlanPage] data-freshness load failed', e); }
    })();
  }, []);

  // Weekly actuals (incl. clicks, for the tracking scorecard's Week tab + CPC actual).
  // Map<productShortName, Map<weekStartISO, WeekActual>>.
  const [actualsWeekly, setActualsWeekly] = useState<Map<string, Map<string, WeekActual>>>(new Map());
  useEffect(() => {
    (async () => {
      try {
        const now = new Date();
        const endDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
        const rows = await cubeLoad({
          dimensions: ['UnifiedPerformance.productShortName', 'UnifiedPerformance.weekStart'],
          measures: ['UnifiedPerformance.units', 'UnifiedPerformance.sales', 'UnifiedPerformance.cogs', 'UnifiedPerformance.adCost', 'UnifiedPerformance.clicks'],
          timeDimensions: [{ dimension: 'UnifiedPerformance.date', dateRange: ['2026-01-01', endDate] }],
        });
        const map = new Map<string, Map<string, WeekActual>>();
        for (const r of rows as Record<string, unknown>[]) {
          const name = String(r['UnifiedPerformance.productShortName'] ?? '');
          const wkRaw = String(r['UnifiedPerformance.weekStart'] ?? '');
          if (!name || !wkRaw) continue;
          const wk = wkRaw.slice(0, 10);
          if (!map.has(name)) map.set(name, new Map());
          map.get(name)!.set(wk, {
            units: Number(r['UnifiedPerformance.units'] ?? 0),
            revenue: Number(r['UnifiedPerformance.sales'] ?? 0),
            cogs: Number(r['UnifiedPerformance.cogs'] ?? 0),
            adCost: Number(r['UnifiedPerformance.adCost'] ?? 0),
            clicks: Number(r['UnifiedPerformance.clicks'] ?? 0),
          });
        }
        console.log('[PlanPage] weekly actuals loaded:', map.size, 'products');
        setActualsWeekly(map);
      } catch (e) { console.warn('[PlanPage] weekly actuals load failed', e); }
    })();
  }, []);

  // Branded search monthly data (per-family: branded + total channels)
  // Uses same DIM_BRAND_PHRASES logic as Brand page
  type BrandedSearchMonth = {
    yr: number; mo: number; family: string;
    purchases: number; impressions: number; clicks: number;
    adsUnits: number; adsSpend: number;
    totalSqpPurchases: number; totalAdsUnits: number; totalAdsSpend: number;
  };
  const [brandedSearch, setBrandedSearch] = useState<BrandedSearchMonth[]>([]);
  useEffect(() => {
    const dims = ['BrandSearchMonthly.year', 'BrandSearchMonthly.month', 'BrandSearchMonthly.family'];
    const brandedMeasures = [
      'BrandSearchMonthly.brandedPurchases', 'BrandSearchMonthly.brandedImpressions',
      'BrandSearchMonthly.brandedClicks', 'BrandSearchMonthly.adsUnits', 'BrandSearchMonthly.adsSpend',
    ];
    const totalMeasures = [
      'BrandSearchMonthly.totalSqpPurchases', 'BrandSearchMonthly.totalAdsUnits', 'BrandSearchMonthly.totalAdsSpend',
    ];
    async function tryLoad(measures: string[]): Promise<Record<string, unknown>[]> {
      const query = { dimensions: dims, measures };
      const rows = await cubeLoad(query);
      return rows as Record<string, unknown>[];
    }
    (async () => {
      try {
        // Try full query (branded + total) first
        let rows = await tryLoad([...brandedMeasures, ...totalMeasures]);
        let hasTotal = true;
        if (rows.length === 0) {
          // Fallback: production Cube may not have total measures yet
          console.warn('[PlanPage] Full branded search query returned 0 rows — trying branded-only fallback');
          rows = await tryLoad(brandedMeasures);
          hasTotal = false;
        }
        const data: BrandedSearchMonth[] = rows.map(r => ({
          yr: Number(r['BrandSearchMonthly.year'] ?? 0),
          mo: Number(r['BrandSearchMonthly.month'] ?? 0),
          family: String(r['BrandSearchMonthly.family'] ?? 'Unknown'),
          purchases: Number(r['BrandSearchMonthly.brandedPurchases'] ?? 0),
          impressions: Number(r['BrandSearchMonthly.brandedImpressions'] ?? 0),
          clicks: Number(r['BrandSearchMonthly.brandedClicks'] ?? 0),
          adsUnits: Number(r['BrandSearchMonthly.adsUnits'] ?? 0),
          adsSpend: Number(r['BrandSearchMonthly.adsSpend'] ?? 0),
          totalSqpPurchases: hasTotal ? Number(r['BrandSearchMonthly.totalSqpPurchases'] ?? 0) : 0,
          totalAdsUnits: hasTotal ? Number(r['BrandSearchMonthly.totalAdsUnits'] ?? 0) : 0,
          totalAdsSpend: hasTotal ? Number(r['BrandSearchMonthly.totalAdsSpend'] ?? 0) : 0,
        }));
        console.log('[PlanPage] Branded search loaded:', data.length, 'rows, hasTotal:', hasTotal);
        setBrandedSearch(data);
      } catch (e) { console.warn('[PlanPage] Branded search load failed', e); }
    })();
  }, []);

  // ── Ads channel efficiency (brand vs non-brand CPC/CVR/ROAS) ──
  type AdsChannelMonth = {
    family: string; yr: number; mo: number; searchType: string;
    spend: number; clicks: number; units: number; orders: number;
    cpc: number; unitCvrPct: number; netRoas: number;
    currentDailySpend: number; currentCpc: number;
  };
  const [channelEfficiency, setChannelEfficiency] = useState<AdsChannelMonth[]>([]);
  useEffect(() => {
    (async () => {
      try {
        // V_ADS_CHANNEL_EFFICIENCY has one row per grain (family×yr×mo×searchType).
        // Including per-row metric dimensions (cpc, netRoas) alongside SUM measures
        // is safe because the grain is already unique — no fragmentation occurs.
        const rows = await cubeLoad({
          dimensions: [
            'AdsChannelEfficiency.family', 'AdsChannelEfficiency.year', 'AdsChannelEfficiency.month',
            'AdsChannelEfficiency.searchType', 'AdsChannelEfficiency.cpc', 'AdsChannelEfficiency.unitCvrPct',
            'AdsChannelEfficiency.netRoas', 'AdsChannelEfficiency.currentDailySpend', 'AdsChannelEfficiency.currentCpc',
          ],
          measures: [
            'AdsChannelEfficiency.totalSpend', 'AdsChannelEfficiency.totalClicks',
            'AdsChannelEfficiency.totalUnits', 'AdsChannelEfficiency.totalOrders',
          ],
          limit: 5000,
        }) as Record<string, unknown>[];
        const data: AdsChannelMonth[] = rows.map(r => ({
          family: String(r['AdsChannelEfficiency.family'] ?? ''),
          yr: Number(r['AdsChannelEfficiency.year'] ?? 0),
          mo: Number(r['AdsChannelEfficiency.month'] ?? 0),
          searchType: String(r['AdsChannelEfficiency.searchType'] ?? ''),
          spend: Number(r['AdsChannelEfficiency.totalSpend'] ?? 0),
          clicks: Number(r['AdsChannelEfficiency.totalClicks'] ?? 0),
          units: Number(r['AdsChannelEfficiency.totalUnits'] ?? 0),
          orders: Number(r['AdsChannelEfficiency.totalOrders'] ?? 0),
          cpc: Number(r['AdsChannelEfficiency.cpc'] ?? 0),
          unitCvrPct: Number(r['AdsChannelEfficiency.unitCvrPct'] ?? 0),
          netRoas: Number(r['AdsChannelEfficiency.netRoas'] ?? 0),
          currentDailySpend: Number(r['AdsChannelEfficiency.currentDailySpend'] ?? 0),
          currentCpc: Number(r['AdsChannelEfficiency.currentCpc'] ?? 0),
        }));
        setChannelEfficiency(data);
      } catch (e) { console.warn('[PlanPage] Channel efficiency load failed', e); }
    })();
  }, []);

  const [mults, setMults] = useState<Record<string, Record<string, number>>>({});
  const [strategies, setStrategies] = useState<Record<string, PlanStrategy>>({});
  const [wizardFamily, setWizardFamily] = useState<string | null>(null);
  const [planDirty, setPlanDirty] = useState(false);
  const [planSaved, setPlanSaved] = useState(false);
  const [planSaving, setPlanSaving] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [orderOverrides, setOrderOverrides] = useState<Record<string, number>>({});
  const [plannedMonthlyOverrides, setPlannedMonthlyOverrides] = useState<Record<string, Record<string, number>>>({});
  const [activeSnapshot, setActiveSnapshot] = useState<Record<string, Record<string, number>> | null>(null);
  const [growthOverrides, setGrowthOverrides] = useState<Record<string, number>>({});
  const [originalOverrides, setOriginalOverrides] = useState<Record<string, number> | null>(null);


  // ─── YTD Sales Summary (parent-level for growth derivation) ─────
  const [salesSummary, setSalesSummary] = useState<{asin: string; product_name: string; sold: number}[]>([]);
  useEffect(() => {
    fetch('/api/sales-summary/2026')
      .then(r => r.ok ? r.json() : [])
      .then(d => { if (Array.isArray(d)) setSalesSummary(d); })
      .catch(e => console.error('[PlanPage] sales-summary load failed', e));
  }, []);
  const parentGetSold = useCallback((asin: string, name: string) => {
    const row = salesSummary.find(p => p.asin === asin) || salesSummary.find(p => p.product_name === name);
    return row?.sold ?? 0;
  }, [salesSummary]);

  const isLoading = loading || fcLoading || dmLoading;
  const families = useMemo(() => isLoading ? [] : buildFamilyBaselines(data, inv, metaMap), [data, inv, metaMap, isLoading]);

  // Per-product weighted run-rate (units/day, ad-spend/day) from the last 4 COMPLETE weeks of
  // actualsWeekly. Recency-weighted 40/30/20/10. Drives the new forecast anchor.
  const runRateMap = useMemo(() => {
    const m = new Map<string, { unitsPerDay: number; spendPerDay: number }>();
    if (!latestDataDate) return m;
    for (const [prod, weeks] of actualsWeekly) {
      const complete = Array.from(weeks.entries())
        .filter(([ws]) => { const end = new Date(ws + 'T00:00:00'); end.setDate(end.getDate() + 6); return end <= latestDataDate; })
        .sort((a, b) => b[0].localeCompare(a[0]))   // most recent week first
        .slice(0, 4);
      m.set(prod, {
        unitsPerDay: weightedRunRate(complete.map(([, w]) => w.units)),
        spendPerDay: weightedRunRate(complete.map(([, w]) => w.adCost)),
      });
    }
    return m;
  }, [actualsWeekly, latestDataDate]);

  // Per-family 2025 monthly total units (index 0 = Jan) — the own/reference inputs for the shape.
  const familyMonthly2025 = useMemo(() => {
    const out: Record<string, number[]> = {};
    for (const fam of families) {
      const arr = Array(12).fill(0) as number[];
      for (const v of fam.variations) {
        const pm = actuals2025Full.get(v.name);
        if (!pm) continue;
        for (let mo = 0; mo < 12; mo++) arr[mo] += pm.get(mo)?.units ?? 0;
      }
      out[fam.family] = arr;
    }
    return out;
  }, [families, actuals2025Full]);

  // Per-family 2025 monthly AD SPEND (index 0 = Jan) — own/reference inputs for the SPEND shape.
  // Ad spend is flatter than demand at the peak (organic carries the holidays), so the spend
  // forecast rides this shape, not the demand shape — avoids overstating Q4 ad spend.
  const familyMonthlySpend2025 = useMemo(() => {
    const out: Record<string, number[]> = {};
    for (const fam of families) {
      const arr = Array(12).fill(0) as number[];
      for (const v of fam.variations) {
        const pm = actuals2025Full.get(v.name);
        if (!pm) continue;
        for (let mo = 0; mo < 12; mo++) arr[mo] += pm.get(mo)?.adCost ?? 0;
      }
      out[fam.family] = arr;
    }
    return out;
  }, [families, actuals2025Full]);

  // ─── Per-family ROAS reference (LY 2025 / CY 2026) ───
  // blended (organic-incl) per family-year from total actuals; ad-only per family-year-channel as a
  // spend-weighted avg of the view's per-month netRoas (AdsChannelEfficiency). Frozen onto ads targets at save.
  const familyRoas = useMemo(() => {
    const out: Record<string, {
      blended: { 2025: number | null; 2026: number | null };
      adOnly: Record<string, { 2025: number | null; 2026: number | null }>;
    }> = {};
    for (const f of families) {
      const blendedFor = (yr: 2025 | 2026) => {
        const src = yr === 2025 ? actuals2025Full : actuals2026Full;
        const rows: { sales: number; cogs: number; adCost: number }[] = [];
        for (const v of f.variations) { const mm = src.get(v.name); if (!mm) continue; for (const a of mm.values()) rows.push({ sales: a.revenue, cogs: a.cogs, adCost: a.adCost }); }
        return blendedNetRoas(rows);
      };
      const adOnly: Record<string, { 2025: number | null; 2026: number | null }> = { BRAND: { 2025: null, 2026: null }, NON_BRAND: { 2025: null, 2026: null } };
      for (const ch of ['BRAND', 'NON_BRAND']) {
        for (const yr of [2025, 2026] as const) {
          let num = 0, den = 0;
          for (const r of channelEfficiency) {
            if (r.family !== f.family || r.searchType !== ch || r.yr !== yr) continue;
            if (r.spend > 0) { num += r.netRoas * r.spend; den += r.spend; }
          }
          adOnly[ch][yr] = den > 0 ? num / den : null;
        }
      }
      out[f.family] = { blended: { 2025: blendedFor(2025), 2026: blendedFor(2026) }, adOnly };
    }
    return out;
  }, [families, channelEfficiency, actuals2025Full, actuals2026Full]);

  // ─── Plan versioning state ────────────────────────────
  const [planList, setPlanList] = useState<PlanMeta[]>([]);
  const [activePlan, setActivePlan] = useState<PlanMeta | null>(null);
  const [showPlanMenu, setShowPlanMenu] = useState(false);
  const [compareMode, setCompareMode] = useState(false);
  const [baseCompareId, setBaseCompareId] = useState<string | null>('CURRENT');
  const [baseCompareData, setBaseCompareData] = useState<Record<string, Record<string, number>> | null>(null);
  const [baseCompareGrowth, setBaseCompareGrowth] = useState<Record<string, number>>({});
  const [baseCompareSnapshot, setBaseCompareSnapshot] = useState<Record<string, Record<string, number>> | null>(null);
  const [comparePlanId, setComparePlanId] = useState<string | null>('ACTUALS');
  const [comparePlanData, setComparePlanData] = useState<Record<string, Record<string, number>> | null>(null);
  const [comparePlanGrowth, setComparePlanGrowth] = useState<Record<string, number>>({});
  const [comparePlanSnapshot, setComparePlanSnapshot] = useState<Record<string, Record<string, number>> | null>(null);

  // ─── Derive effective growth from orderOverrides ────────────────
  // When a user sets "Yearly Planned" (orderOverrides), we back-calculate
  // the growth multiplier using EXACTLY the same math as runSim.
  // This guarantees the Forecast row always matches the Yearly Planned.
  const effectiveGrowth = useMemo(() => {
    const result = { ...growthOverrides };
    if (Object.keys(orderOverrides).length === 0 || families.length === 0) return result;
    const today = new Date();
    const remDays = Math.max(1, MONTHS[0].days - today.getDate() + 1);
    for (const [name, qty] of Object.entries(orderOverrides)) {
      const fam = families.find(f => f.variations.some(v => v.name === name));
      const v = fam?.variations.find(vv => vv.name === name);
      if (!fam || !v) continue;
      let totalDemandBase = 0;
      for (let mi = 0; mi < MONTHS.length; mi++) {
        const m = MONTHS[mi];
        const days = mi === 0 ? remDays : m.days;
        const si = fam.seasonalityIndex[m.month - 1] ?? 1;
        const mult = mults[fam.family]?.[m.key] ?? 1;
        const demandKey = m.year * 100 + m.month;
        const mapVal = demandMap[v.name]?.[demandKey];
        let rawDemand = 0;
        if (mapVal != null && mapVal > 0) {
          rawDemand = mi === 0 ? mapVal * (days / m.days) : mapVal;
        } else {
          rawDemand = Math.round(v.dailyOrders * si * days);
        }
        const adjFactor = (1 - v.adsShare) + v.adsShare * mult;
        totalDemandBase += rawDemand * adjFactor;
      }
      if (totalDemandBase > 0) {
        const sold = parentGetSold(v.asin, v.name);
        const targetForecast = Math.max(0, qty - sold);
        result[name] = targetForecast / totalDemandBase;
      }
    }
    return result;
  }, [growthOverrides, orderOverrides, families, demandMap, mults, parentGetSold]);

  // Build payload rows from current sim state
  // IMPORTANT: iterate ALL families, not just those with mults entries,
  // so growth_json is always saved (even when only orderOverrides changed).
  const buildPayloadRows = useCallback((currentProjs: MonthProj[]) => {
    const rows: Array<{ family: string; strategy: string; forecast_year: number; forecast_month: number; multiplier: number; target_roas: number | null; base_roas: number | null; growth_rate: number; growth_json: string | null }> = [];
    // Collect all family names from mults + families
    const allFamilyNames = new Set(Object.keys(mults));
    for (const f of families) allFamilyNames.add(f.family);
    // Build per-product growth JSON (shared across all families)
    const famGrowth: Record<string, number> = {};
    for (const [prod, rate] of Object.entries(growthOverrides)) {
      if (rate !== 1.0) famGrowth[prod] = rate;
    }
    const growthJson = Object.keys(famGrowth).length > 0 ? JSON.stringify(famGrowth) : null;
    for (const fam of allFamilyNames) {
      const fmMults = mults[fam] ?? {};
      const strat = strategies[fam] ?? 'SEASONAL';
      for (const m of MONTHS) {
        const mult = fmMults[m.key] ?? 1;
        const baseRoas = forecastMap[fam]?.[m.month]?.roas ?? null;
        const targetRoas = baseRoas && mult > 0 ? baseRoas / Math.sqrt(mult) : null;
        rows.push({ family: fam, strategy: strat, forecast_year: m.year, forecast_month: m.month, multiplier: mult, target_roas: targetRoas, base_roas: baseRoas, growth_rate: 1.0, growth_json: growthJson });
      }
    }
    // Freeze simulation projections: { product: { "monthYY": units } }
    // Includes PAST months (Jan → current-1) from demandMap + growth + adjFactor
    // and FUTURE months (current → Mar next year) from runSim projections
    const snapshotMap: Record<string, Record<string, number>> = {};
    const monthLabels = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

    // 1. Past months: compute from demandMap × effectiveGrowth × adjFactor
    for (const f of families) {
      for (const v of f.variations) {
        if (!snapshotMap[v.name]) snapshotMap[v.name] = {};
        const growth = effectiveGrowth[v.name] ?? 1.0;
        for (let mo = 1; mo < currentMonthIdxStatic; mo++) {
          const demandKey = 2026 * 100 + mo;
          const rawDemand = demandMap[v.name]?.[demandKey] ?? 0;
          if (rawDemand <= 0) continue;
          const mult = mults[f.family]?.[`${monthLabels[mo - 1]}26`] ?? 1;
          const adjFactor = (1 - v.adsShare) + v.adsShare * mult;
          const demand = Math.round(rawDemand * growth * adjFactor);
          snapshotMap[v.name][`${monthLabels[mo - 1]}26`] = demand;
        }
      }
    }

    // 2. Future months (current → end): from runSim projections
    for (let mi = 0; mi < currentProjs.length; mi++) {
      const p = currentProjs[mi];
      const mKey = p.key; // e.g. "may26"
      for (const [fam, fd] of Object.entries(p.families)) {
        for (const [prod, vd] of Object.entries(fd.vars)) {
          if (!snapshotMap[prod]) snapshotMap[prod] = {};
          let demand = vd.demand;
          if (mi === 0) {
             const currentMonthIdx = MONTHS[0].year === 2026 ? MONTHS[0].month - 1 : MONTHS[0].month + 11;
             const mtdActuals = currentMonthIdx <= 11 ? (actuals2026Full.get(prod)?.get(currentMonthIdx)?.units ?? 0) : (actuals2025Full.get(prod)?.get(currentMonthIdx - 12)?.units ?? 0);
             demand += mtdActuals;
          }
          snapshotMap[prod][mKey] = demand;
        }
      }
    }
    // Override wizard-sourced products: per-product per-month = actual (elapsed + MTD) + forecast.
    if (Object.keys(plannedMonthlyOverrides).length > 0) {
      const allCalKeys: string[] = [];
      for (let mo = 1; mo <= 12; mo++) allCalKeys.push(`${monthLabels[mo - 1]}26`); // jan26..dec26
      for (const m of MONTHS) if (m.year === 2027) allCalKeys.push(m.key);           // jan27, feb27
      for (const [prod, forecastByMonth] of Object.entries(plannedMonthlyOverrides)) {
        const actualByMonth: Record<string, number> = {};
        const am = actuals2026Full.get(prod);
        if (am) for (const [mi, v] of am.entries()) actualByMonth[`${monthLabels[mi]}26`] = v.units;
        snapshotMap[prod] = composeMonthlyPlan(allCalKeys, actualByMonth, forecastByMonth).byMonth;
      }
    }
    return {
      rows,
      order_overrides_json: JSON.stringify(orderOverrides),
      snapshot_units_json: JSON.stringify(snapshotMap),
    };
  }, [families, mults, strategies, forecastMap, growthOverrides, effectiveGrowth, demandMap, orderOverrides, actuals2026Full, actuals2025Full, plannedMonthlyOverrides]);

  // Bumped whenever a plan is loaded, to force the [families]-keyed plannedSpend loader to refetch
  // ads-targets for the newly-loaded plan (otherwise switching plans keeps the prior plan's spend).
  const [plannedSpendNonce, setPlannedSpendNonce] = useState(0);

  // Load a plan's data into the sim
  const loadPlanData = useCallback((rows: Array<Record<string, unknown>>) => {
    const loadedMults: Record<string, Record<string, number>> = {};
    const loadedStrategies: Record<string, PlanStrategy> = {};
    const loadedGrowth: Record<string, number> = {};
    let growthParsed = false;
    let overridesParsed = false;
    let loadedOverrides: Record<string, number> = {};
    let loadedOriginal: Record<string, number> | null = null;
    let loadedSnapshot: Record<string, Record<string, number>> | null = null;
    for (const r of rows) {
      const fam = String(r.family ?? '');
      const strat = String(r.strategy ?? 'SEASONAL') as PlanStrategy;
      const yr = Number(r.forecast_year ?? 0);
      const mo = Number(r.forecast_month ?? 0);
      const mult = Number(r.multiplier ?? 1);
      if (!fam || !yr || !mo) continue;
      const mKey = MONTHS.find(m => m.year === yr && m.month === mo)?.key;
      if (!mKey) continue;
      if (!loadedMults[fam]) loadedMults[fam] = {};
      loadedMults[fam][mKey] = mult;
      if (!loadedStrategies[fam]) loadedStrategies[fam] = strat;
      // Parse per-product growth from JSON (only need to do once)
      if (!growthParsed && r.growth_json) {
        try {
          const parsed = JSON.parse(String(r.growth_json));
          for (const [prod, rate] of Object.entries(parsed)) {
            if (typeof rate === 'number' && rate !== 1.0) loadedGrowth[prod] = rate;
          }
        } catch { /* ignore parse errors */ }
        growthParsed = true;
      }
      // Parse order overrides JSON (only need to do once)
      if (!overridesParsed) {
        if (r.order_overrides_json) {
          try { loadedOverrides = JSON.parse(String(r.order_overrides_json)); } catch { /* ignore */ }
        }
        if (r.original_overrides_json) {
          try { loadedOriginal = JSON.parse(String(r.original_overrides_json)); } catch { /* ignore */ }
        }
        if (r.snapshot_units_json) {
          try { loadedSnapshot = JSON.parse(String(r.snapshot_units_json)); } catch { /* ignore */ }
        }
        overridesParsed = true;
      }
    }
    if (Object.keys(loadedMults).length > 0) {
      setMults(loadedMults);
      setStrategies(loadedStrategies);
      setGrowthOverrides(loadedGrowth);
      setOrderOverrides(loadedOverrides);
      setOriginalOverrides(loadedOriginal);
      setActiveSnapshot(loadedSnapshot);
      setPlanDirty(false);
      setPlanSaved(true);
    }
    // Refresh ads-targets-derived spend for the loaded plan so `isPlanned` reflects it (the
    // plannedSpend loader is keyed on [families], which doesn't change on a plan switch).
    setPlannedSpendNonce(n => n + 1);
  }, []);

  // Fetch plan list + auto-load latest
  const refreshPlanList = useCallback(async () => {
    try {
      const res = await fetch('/api/plans');
      if (!res.ok) return;
      const plans: PlanMeta[] = await res.json();
      setPlanList(plans);
      return plans;
    } catch { return []; }
  }, []);

  // Load saved plan on mount (latest plan)
  useEffect(() => {
    (async () => {
      try {
        const plans = await refreshPlanList();
        if (!plans || plans.length === 0) return;
        // Auto-load the latest plan (first in list, sorted by version DESC)
        const latest = plans[0];
        const res = await fetch(`/api/plans/${latest.plan_id}`);
        if (!res.ok) return;
        const data = await res.json();
        setActivePlan(latest);
        loadPlanData(data.rows);
        console.log('[PlanPage] loaded plan:', latest.plan_name);
      } catch (e) { console.warn('[PlanPage] plan load failed', e); }
    })();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps



  // ── Wizard-sourced forecast inputs ──
  // Per-product per-month FORECAST units. Current month = remainder only (strip MTD actuals) so it
  // matches projs/NEED semantics and doesn't double-count YTD sold. In-session wizard saves
  // (plannedMonthlyOverrides, already MTD-excluded) override the loaded snapshot.
  const plannedUnits = useMemo(() => {
    const out: Record<string, Record<string, number>> = {};
    const curKey = MONTHS[0]?.key;
    const curIdx = MONTHS[0] ? (MONTHS[0].year === 2026 ? MONTHS[0].month - 1 : MONTHS[0].month + 11) : -1;
    if (activeSnapshot) {
      for (const [prod, byMonth] of Object.entries(activeSnapshot)) {
        out[prod] = { ...byMonth };
        if (curKey && out[prod][curKey] != null && curIdx >= 0 && curIdx <= 11) {
          const mtd = actuals2026Full.get(prod)?.get(curIdx)?.units ?? 0;
          out[prod][curKey] = Math.max(0, out[prod][curKey] - mtd);
        }
      }
    }
    for (const [prod, byMonth] of Object.entries(plannedMonthlyOverrides)) out[prod] = { ...byMonth };
    return out;
  }, [activeSnapshot, plannedMonthlyOverrides, actuals2026Full]);

  // Planned ad spend per family-month from saved coach targets (Σ daily_spend × days).
  const [plannedSpend, setPlannedSpend] = useState<Record<string, Record<string, number>>>({});
  const [plannedCpc, setPlannedCpc] = useState<Record<string, Record<string, number>>>({}); // spend-weighted cpc_target per family-month
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const out: Record<string, Record<string, number>> = {};
      const outCpc: Record<string, Record<string, number>> = {};
      await Promise.all(families.map(async f => {
        try {
          const r = await fetch(`/api/plans/ads-targets/${encodeURIComponent(f.family)}`);
          const tRows: { yr: number; mo: number; daily_spend_target: number; cpc_target?: number }[] = r.ok ? await r.json() : [];
          const { spendByMonth, cpcByMonth } = aggregateAdsTargetSpend(tRows);
          if (Object.keys(spendByMonth).length > 0) out[f.family] = spendByMonth;
          if (Object.keys(cpcByMonth).length > 0) outCpc[f.family] = cpcByMonth;
        } catch { /* ignore */ }
      }));
      if (!cancelled) { setPlannedSpend(out); setPlannedCpc(outCpc); }
    })();
    return () => { cancelled = true; };
  }, [families, plannedSpendNonce]);

  // A family is "planned" once BOTH its snapshot units AND saved spend exist — the spend gate
  // doubles as a loading guard (no spend-less P&L is shown as final; falls back to runSim until ready).
  const isPlanned = useCallback((fam: string) => {
    const f = families.find(ff => ff.family === fam);
    if (!f) return false;
    const hasUnits = f.variations.some(v => plannedUnits[v.name] && Object.keys(plannedUnits[v.name]).length > 0);
    return hasUnits && !!plannedSpend[fam] && Object.keys(plannedSpend[fam]).length > 0;
  }, [families, plannedUnits, plannedSpend]);

  // runSim is the fallback; the wizard's saved plan is substituted in for planned families.
  const rawProjs = useMemo(() => runSim(families, mults, forecastMap, demandMap, effectiveGrowth), [families, mults, forecastMap, demandMap, effectiveGrowth]);
  const projs = useMemo(() => buildEffectiveProjs(rawProjs, plannedUnits, plannedSpend, families, isPlanned), [rawProjs, plannedUnits, plannedSpend, families, isPlanned]);

  const unconstrainedProjs = useMemo(() => runSim(families, mults, forecastMap, demandMap, growthOverrides), [families, mults, forecastMap, demandMap, growthOverrides]);

  const unconstrainedForecastMap = useMemo(() => {
    const map: Record<string, number> = {};
    for (const p of data.products) {
      const vName = p.product_short_name || p.product;
      let forecast = 0;
      for (const proj of unconstrainedProjs) {
        for (const famKey of Object.keys(proj.families)) {
          if (proj.families[famKey].vars[vName]) {
            forecast += proj.families[famKey].vars[vName].demand;
          }
        }
      }
      const sold = parentGetSold(p.asin, vName);
      map[vName] = sold + forecast;
    }
    return map;
  }, [data.products, unconstrainedProjs, parentGetSold]);

  const totals = useMemo(() => {
    let r = 0, c = 0, a = 0, n = 0, d = 0;
    for (const p of projs) { r += p.totalRevenue; c += p.totalCogs; a += p.totalAdSpend; n += p.totalNetProfit; d += p.totalDemand; }
    return { revenue: r, cogs: c, adSpend: a, netProfit: n, demand: d, netRoas: a > 0 ? (r - c) / a : 0 };
  }, [projs]);

  // YTD Net Profit per family from 2026 actuals
  const ytdProfit = useMemo(() => {
    const map = new Map<string, { sales: number; cogs: number; adCost: number }>();
    let total = { sales: 0, cogs: 0, adCost: 0 };
    for (const r of data.weekly_trends_by_asin) {
      if (!(r.week_start ?? '').startsWith('2026')) continue;
      const fam = r.product_type ?? null;
      if (!fam) continue;
      const f = typeof fam === 'string' ? fam : fam;
      if (!map.has(f)) map.set(f, { sales: 0, cogs: 0, adCost: 0 });
      const d = map.get(f)!;
      d.sales += r.sales ?? 0; d.cogs += r.cogs ?? 0; d.adCost += r.ad_cost ?? 0;
      total.sales += r.sales ?? 0; total.cogs += r.cogs ?? 0; total.adCost += r.ad_cost ?? 0;
    }
    // Net profit = sales - cogs - ad_cost
    const byFamily: Record<string, number> = {};
    for (const [fam, d] of map) byFamily[fam] = d.sales - d.cogs - d.adCost;
    const totalNp = total.sales - total.cogs - total.adCost;
    return { byFamily, total: totalNp };
  }, [data.weekly_trends_by_asin]);



  const computeCompareStats = useCallback((id: string | null, planData: Record<string, Record<string, number>> | null, planGrowth: Record<string, number>, snapshot: Record<string, Record<string, number>> | null) => {
    const familyByProduct = new Map<string, string>();
    for (const f of families) for (const v of f.variations) familyByProduct.set(v.name, f.family);

    if (id === 'ACTUALS_PREV') {
      let ytdRev = 0, ytdCogs = 0, ytdAds = 0;
      let restRev = 0, restCogs = 0, restAds = 0;
      const byFamily: Record<string, { ytdNp: number; totals: { revenue: number, cogs: number, adSpend: number, netProfit: number, demand: number, netRoas: number } }> = {};
      for (const f of families) byFamily[f.family] = { ytdNp: 0, totals: { revenue: 0, cogs: 0, adSpend: 0, netProfit: 0, demand: 0, netRoas: 0 } };

      for (const [prod, map] of actuals2025Full.entries()) {
        const fam = familyByProduct.get(prod);
        if (!fam || !byFamily[fam]) continue;
        for (const [mo, m] of map.entries()) {
          if (mo < 3) {
            ytdRev += m.revenue; ytdCogs += m.cogs; ytdAds += m.adCost;
            byFamily[fam].ytdNp += (m.revenue - m.cogs - m.adCost);
          } else {
            restRev += m.revenue; restCogs += m.cogs; restAds += m.adCost;
            byFamily[fam].totals.revenue += m.revenue;
            byFamily[fam].totals.cogs += m.cogs;
            byFamily[fam].totals.adSpend += m.adCost;
            byFamily[fam].totals.netProfit += (m.revenue - m.cogs - m.adCost);
          }
        }
      }
      for (const f in byFamily) byFamily[f].totals.netRoas = byFamily[f].totals.adSpend > 0 ? (byFamily[f].totals.revenue - byFamily[f].totals.cogs) / byFamily[f].totals.adSpend : 0;
      return {
        ytdNp: ytdRev - ytdCogs - ytdAds,
        totals: { revenue: restRev, cogs: restCogs, adSpend: restAds, netProfit: restRev - restCogs - restAds, demand: 0, netRoas: restAds > 0 ? (restRev - restCogs) / restAds : 0 },
        byFamily,
        type: 'ACTUALS_PREV',
        projs: null
      };
    }
    if (id === 'ACTUALS') {
      let ytdRev = 0, ytdCogs = 0, ytdAds = 0;
      const byFamily: Record<string, { ytdNp: number; totals: { revenue: number, cogs: number, adSpend: number, netProfit: number, demand: number, netRoas: number } }> = {};
      for (const f of families) byFamily[f.family] = { ytdNp: 0, totals: { revenue: 0, cogs: 0, adSpend: 0, netProfit: 0, demand: 0, netRoas: 0 } };
      for (const [prod, map] of actuals2026Full.entries()) {
        const fam = familyByProduct.get(prod);
        if (!fam || !byFamily[fam]) continue;
        for (const m of map.values()) {
          ytdRev += m.revenue; ytdCogs += m.cogs; ytdAds += m.adCost;
          byFamily[fam].ytdNp += (m.revenue - m.cogs - m.adCost);
        }
      }
      return {
        ytdNp: ytdRev - ytdCogs - ytdAds,
        totals: { revenue: 0, cogs: 0, adSpend: 0, netProfit: 0, demand: 0, netRoas: 0 },
        byFamily,
        type: 'ACTUALS',
        projs: null
      };
    }

    // CURRENT or PLAN
    const byFamily: Record<string, { ytdNp: number; totals: { revenue: number, cogs: number, adSpend: number, netProfit: number, demand: number, netRoas: number } }> = {};
    const theProjs = id === 'CURRENT' ? projs : runSim(families, planData || {}, forecastMap, demandMap, Object.keys(planGrowth).length > 0 ? planGrowth : effectiveGrowth);
    
    // If saved plan has a frozen snapshot, use those demand numbers
    const useFrozenDemand = id !== 'CURRENT' && snapshot && Object.keys(snapshot).length > 0;
    
    let tr = 0, tc = 0, ta = 0, tn = 0, td = 0;
    for (const f of families) {
      const ytd = ytdProfit.byFamily[f.family] || 0;
      let pRev = 0, pCogs = 0, pAds = 0, pNp = 0, pDem = 0;
      for (const p of theProjs) {
        const fd = p.families[f.family];
        if (fd) {
          pRev += fd.revenue; pCogs += fd.cogs; pAds += fd.adSpend; pNp += fd.netProfit;
          if (useFrozenDemand) {
            // Sum frozen demand from snapshot for this family's products in this month
            for (const [prod, monthMap] of Object.entries(snapshot!)) {
              if (familyByProduct.get(prod) === f.family && monthMap[p.key] != null) {
                pDem += monthMap[p.key];
              }
            }
          } else {
            pDem += fd.demand;
          }
        }
      }
      byFamily[f.family] = {
        ytdNp: ytd,
        totals: { revenue: pRev, cogs: pCogs, adSpend: pAds, netProfit: pNp, demand: pDem, netRoas: pAds > 0 ? (pRev - pCogs) / pAds : 0 }
      };
      tr += pRev; tc += pCogs; ta += pAds; tn += pNp; td += pDem;
    }
    
    if (id === 'CURRENT') {
      return { ytdNp: ytdProfit.total, totals, byFamily, type: 'CURRENT' as const, projs: theProjs, snapshot: null };
    }
    return {
      ytdNp: ytdProfit.total,
      totals: { revenue: tr, cogs: tc, adSpend: ta, netProfit: tn, demand: td, netRoas: ta > 0 ? (tr - tc) / ta : 0 },
      byFamily,
      type: 'PLAN' as const,
      projs: theProjs,
      snapshot: snapshot || null
    };
  }, [ytdProfit, totals, actuals2025Full, actuals2026Full, families, forecastMap, demandMap, effectiveGrowth, projs]);

  const baseStats = useMemo(() => computeCompareStats(baseCompareId, baseCompareData, baseCompareGrowth, baseCompareSnapshot), [computeCompareStats, baseCompareId, baseCompareData, baseCompareGrowth, baseCompareSnapshot]);
  const cmpStats = useMemo(() => computeCompareStats(comparePlanId, comparePlanData, comparePlanGrowth, comparePlanSnapshot), [computeCompareStats, comparePlanId, comparePlanData, comparePlanGrowth, comparePlanSnapshot]);

  // ─── Header Filter Support ──────────────────────────────
  // Read global family/product filter from header.
  // Filter display data only — plan save/load always uses full `families`.
  const { filters } = useFilters();

  const filteredFamilies = useMemo(() => {
    let ff = families;
    if (filters.family) {
      ff = ff.filter(f => famFromType(f.family) === filters.family);
    }
    if (filters.product) {
      // Product filter stores an ASIN — find the family containing it
      ff = ff.filter(f => f.variations.some(v => v.asin === filters.product));
      // Also narrow variations within the matching family and recompute inventory totals
      ff = ff.map(f => {
        const filteredVars = f.variations.filter(v => v.asin === filters.product);
        const filteredInv = filteredVars.reduce((s, v) => s + v.inventory, 0);
        const filteredInvSrc: Record<string, number> = {};
        for (const v of filteredVars) for (const [k, q] of Object.entries(v.inventoryBySource)) filteredInvSrc[k] = (filteredInvSrc[k] ?? 0) + q;
        return {
          ...f,
          variations: filteredVars,
          inventory: filteredInv,
          inventoryBySource: filteredInvSrc,
        };
      });
    }
    return ff;
  }, [families, filters.family, filters.product]);

  const filteredFamilyNames = useMemo(() => new Set(filteredFamilies.map(f => f.family)), [filteredFamilies]);

  // Filtered totals for KPIs
  const filteredTotals = useMemo(() => {
    let r = 0, c = 0, a = 0, n = 0, d = 0;
    for (const p of projs) {
      for (const [fam, fd] of Object.entries(p.families)) {
        if (!filteredFamilyNames.has(fam)) continue;
        r += fd.revenue; c += fd.cogs; a += fd.adSpend; n += fd.netProfit; d += fd.demand;
      }
    }
    return { revenue: r, cogs: c, adSpend: a, netProfit: n, demand: d, netRoas: a > 0 ? (r - c) / a : 0 };
  }, [projs, filteredFamilyNames]);

  // Filtered YTD profit
  const filteredYtdProfit = useMemo(() => {
    let total = 0;
    const byFamily: Record<string, number> = {};
    for (const [fam, np] of Object.entries(ytdProfit.byFamily)) {
      if (!filteredFamilyNames.has(fam)) continue;
      byFamily[fam] = np;
      total += np;
    }
    return { byFamily, total };
  }, [ytdProfit, filteredFamilyNames]);

  const isFiltered = filters.family != null || filters.product != null;

  // Filtered product ASINs for ReplenishmentFlowWrapper
  const filteredAsins = useMemo(() => {
    if (!isFiltered) return null; // null = no filter, use all
    const set = new Set<string>();
    for (const f of filteredFamilies) for (const v of f.variations) if (v.asin) set.add(v.asin);
    return set;
  }, [filteredFamilies, isFiltered]);

  const filteredProducts = useMemo(() => {
    if (!filteredAsins) return data.products;
    return data.products.filter(p => filteredAsins.has(p.asin));
  }, [data.products, filteredAsins]);

  const curDaily = filteredFamilies.reduce((s, f) => s + f.dailySpend, 0);
  const simDaily = filteredFamilies.reduce((s, f) => {
    const famMults = mults[f.family];
    if (!famMults) return s + f.dailySpend;
    const avg = Object.values(famMults).reduce((a, v) => a + v, 0) / Math.max(1, Object.values(famMults).length);
    return s + f.dailySpend * avg;
  }, 0);

  if (isLoading) return <div className="flex items-center justify-center h-64 text-muted"><div className="animate-spin mr-3">⏳</div>Loading…</div>;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Calculator className="text-blue-400" size={22} />
          <div>
            <h1 className="text-xl font-bold text-heading">Plan — Ads & Inventory Simulator</h1>
            <p className="text-xs text-muted mt-0.5">Adjust spend per family → click to see variation breakdown & buy plan through Feb 2027</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {/* Plan selector */}
          <div className="relative">
            <button onClick={() => setShowPlanMenu(!showPlanMenu)}
              className="text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-border hover:bg-white/5 text-heading font-medium">
              <FileText size={12} />
              {activePlan ? (
                <><span>{activePlan.plan_name}</span>
                  <span className={`text-[9px] px-1.5 py-0.5 rounded-full font-semibold ${
                    activePlan.status === 'APPROVED' ? 'bg-emerald-500/20 text-emerald-300' : 'bg-amber-500/20 text-amber-300'
                  }`}>{activePlan.status === 'APPROVED' ? '✓ Approved' : 'Draft'}</span>
                </>
              ) : 'No Plan'}
              <ChevronDown size={10} className="text-faint" />
            </button>
            {showPlanMenu && (
              <div className="absolute top-full left-0 mt-1 bg-[#1c1c2e] border border-border rounded-lg shadow-xl z-50 min-w-[220px] py-1">
                {planList.map(p => (
                  <button key={p.plan_id} onClick={async () => {
                    setShowPlanMenu(false);
                    try {
                      const res = await fetch(`/api/plans/${p.plan_id}`);
                      if (!res.ok) return;
                      const d = await res.json();
                      setActivePlan(p);
                      loadPlanData(d.rows);
                    } catch (e) { console.error('Load plan failed', e); }
                  }}
                    className={`w-full text-left px-3 py-2 text-xs hover:bg-white/5 flex items-center justify-between ${
                      activePlan?.plan_id === p.plan_id ? 'text-blue-300 bg-blue-500/10' : 'text-muted'
                    }`}>
                    <span className="flex items-center gap-2">
                      {p.status === 'APPROVED' ? <Lock size={10} className="text-emerald-400" /> : <FileText size={10} />}
                      {p.plan_name}
                    </span>
                    <span className={`text-[9px] px-1.5 py-0.5 rounded-full ${
                      p.status === 'APPROVED' ? 'bg-emerald-500/15 text-emerald-300' : 'bg-amber-500/15 text-amber-300'
                    }`}>{p.status === 'APPROVED' ? 'Approved' : 'Draft'}</span>
                  </button>
                ))}
                <div className="border-t border-border mt-1 pt-1">
                  <button onClick={async () => {
                    setShowPlanMenu(false);
                    if (Object.keys(mults).length === 0) return;
                    setPlanSaving(true);
                    try {
                      const _payload = buildPayloadRows(projs);
                      const res = await fetch('/api/plans', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ rows: _payload.rows, order_overrides_json: _payload.order_overrides_json, snapshot_units_json: _payload.snapshot_units_json, plan_year: 2026 }),
                      });
                      if (res.ok) {
                        const d = await res.json();
                        const plans = await refreshPlanList();
                        const newPlan = plans?.find((p: PlanMeta) => p.plan_id === d.plan_id);
                        if (newPlan) setActivePlan(newPlan);
                        setPlanDirty(false); setPlanSaved(true); setTimeout(() => setPlanSaved(false), 4000);
                      } else {
                        const err = await res.json();
                        alert(err.error || 'Create failed');
                      }
                    } catch (e) { console.error('Create plan failed', e); }
                    finally { setPlanSaving(false); }
                  }} className="w-full text-left px-3 py-2 text-xs hover:bg-white/5 text-blue-300 flex items-center gap-2">
                    <Plus size={10} /> New Plan
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Reset */}
          <button onClick={() => { setMults({}); setStrategies({}); setGrowthOverrides({}); setPlanDirty(true); setPlanSaved(false); }}
            className="btn-ghost text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-border hover:bg-white/5 text-muted">
            <RotateCcw size={12} /> Reset
          </button>

          {/* Save (create or update) */}
          <button
            disabled={planSaving || !planDirty}
            onClick={async () => {
              setPlanSaving(true);
              try {
                const payload = buildPayloadRows(projs);
                console.log('[PlanPage] saving plan, growthOverrides:', growthOverrides, 'sample row growth_json:', payload.rows[0]?.growth_json);
                let res: Response;
                if (activePlan) {
                  // Update existing plan
                  res = await fetch(`/api/plans/${activePlan.plan_id}`, {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ rows: payload.rows, order_overrides_json: payload.order_overrides_json, snapshot_units_json: payload.snapshot_units_json }),
                  });
                } else {
                  // Create new plan
                  res = await fetch('/api/plans', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ rows: payload.rows, order_overrides_json: payload.order_overrides_json, snapshot_units_json: payload.snapshot_units_json, plan_year: 2026 }),
                  });
                }
                if (res.ok) {
                  const d = await res.json();
                  const plans = await refreshPlanList();
                  if (!activePlan && d.plan_id) {
                    const newPlan = plans?.find((p: PlanMeta) => p.plan_id === d.plan_id);
                    if (newPlan) setActivePlan(newPlan);
                  }
                  setPlanDirty(false); setPlanSaved(true); setTimeout(() => setPlanSaved(false), 4000);
                } else {
                  const err = await res.json().catch(() => ({ error: 'Save failed' }));
                  alert(err.error || 'Save failed');
                }
              } catch (e) { console.error('Save error', e); }
              finally { setPlanSaving(false); }
            }}
            className={`text-xs flex items-center gap-1.5 px-4 py-1.5 rounded-lg font-medium transition-all ${
              planSaved ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/40' :
              planDirty ? 'bg-blue-500/20 text-blue-300 border border-blue-500/40 hover:bg-blue-500/30' :
              'bg-white/5 text-muted border border-border cursor-not-allowed'
            }`}>
            {planSaving ? <span className="animate-spin">⏳</span> : planSaved ? <Check size={12} /> : <Save size={12} />}
            {planSaving ? 'Saving…' : planSaved ? 'Saved ✓' : 'Save'}
          </button>

          {/* Approve / Unapprove */}
          {activePlan && (
            activePlan.status === 'DRAFT' ? (
              <button onClick={async () => {
                if (!confirm(`Approve "${activePlan.plan_name}"?\n\nApproving means you will open a PR to manufacturer based on this plan.`)) return;
                try {
                  const res = await fetch(`/api/plans/${activePlan.plan_id}/approve`, { method: 'POST' });
                  if (res.ok) {
                    const plans = await refreshPlanList();
                    const updated = plans?.find((p: PlanMeta) => p.plan_id === activePlan.plan_id);
                    if (updated) setActivePlan(updated);
                  } else { const err = await res.json(); alert(err.error); }
                } catch (e) { console.error(e); }
              }} className="text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-emerald-500/40 text-emerald-300 hover:bg-emerald-500/10 font-medium">
                <CheckCircle size={12} /> Approve
              </button>
            ) : (
              <button onClick={async () => {
                try {
                  const res = await fetch(`/api/plans/${activePlan.plan_id}/unapprove`, { method: 'POST' });
                  if (res.ok) {
                    const plans = await refreshPlanList();
                    const updated = plans?.find((p: PlanMeta) => p.plan_id === activePlan.plan_id);
                    if (updated) setActivePlan(updated);
                  } else { const err = await res.json(); alert(err.error); }
                } catch (e) { console.error(e); }
              }} className="text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-amber-500/40 text-amber-300 hover:bg-amber-500/10 font-medium">
                <Lock size={12} /> Unapprove
              </button>
            )
          )}

          {/* Delete */}
          {activePlan && activePlan.status === 'DRAFT' && (
            <button onClick={async () => {
              if (!confirm(`Delete "${activePlan.plan_name}"? This cannot be undone.`)) return;
              try {
                const res = await fetch(`/api/plans/${activePlan.plan_id}`, { method: 'DELETE' });
                if (res.ok) {
                  setActivePlan(null); setMults({}); setStrategies({});
                  setPlanDirty(false); setPlanSaved(false);
                  await refreshPlanList();
                } else { const err = await res.json(); alert(err.error); }
              } catch (e) { console.error(e); }
            }} className="text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-red-500/30 text-red-400 hover:bg-red-500/10">
              <Trash2 size={12} /> Delete
            </button>
          )}

          {/* Compare toggle */}
          <button onClick={() => setCompareMode(!compareMode)}
            className={`text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg border font-medium transition-all ${
              compareMode ? 'bg-purple-500/20 text-purple-300 border-purple-500/40' : 'border-border text-muted hover:bg-white/5'
            }`}>
            <ArrowLeftRight size={12} /> Compare
          </button>
        </div>
      </div>

      {/* Compare bar */}
      {compareMode && (
        <div className="flex items-center gap-3 px-4 py-2 rounded-lg border border-purple-500/20 bg-purple-500/5">
          <span className="text-xs text-purple-300 font-medium">Compare:</span>
          <select value={baseCompareId ?? 'CURRENT'} onChange={async (e) => {
            const val = e.target.value;
            setBaseCompareId(val);
            if (val === 'CURRENT' || val === 'ACTUALS' || val === 'ACTUALS_PREV') {
              setBaseCompareData(null);
              setBaseCompareGrowth({});
              setBaseCompareSnapshot(null);
              return;
            }
            try {
              const res = await fetch(`/api/plans/${val}`);
              if (!res.ok) return;
              const d = await res.json();
              const loaded: Record<string, Record<string, number>> = {};
              const loadedGrowth: Record<string, number> = {};
              let growthParsed = false;
              for (const r of d.rows as Array<Record<string, unknown>>) {
                const fam = String(r.family ?? '');
                const yr = Number(r.forecast_year ?? 0);
                const mo = Number(r.forecast_month ?? 0);
                const mult = Number(r.multiplier ?? 1);
                const mKey = MONTHS.find(m => m.year === yr && m.month === mo)?.key;
                if (!fam || !mKey) continue;
                if (!loaded[fam]) loaded[fam] = {};
                loaded[fam][mKey] = mult;
                if (!growthParsed && r.growth_json) {
                  try {
                    const parsed = JSON.parse(String(r.growth_json));
                    for (const [prod, rate] of Object.entries(parsed)) {
                      if (typeof rate === 'number' && rate !== 1.0) loadedGrowth[prod] = rate;
                    }
                  } catch { /* ignore */ }
                  growthParsed = true;
                }
              }
              setBaseCompareData(loaded);
              setBaseCompareGrowth(loadedGrowth);
              // Parse frozen snapshot
              let snap: Record<string, Record<string, number>> | null = null;
              const firstRow = (d.rows as Array<Record<string, unknown>>)[0];
              if (firstRow?.snapshot_units_json) {
                try { snap = JSON.parse(String(firstRow.snapshot_units_json)); } catch { /* ignore */ }
              }
              setBaseCompareSnapshot(snap);
            } catch { setBaseCompareData(null); setBaseCompareGrowth({}); setBaseCompareSnapshot(null); }
          }} className="bg-surface border border-border rounded px-2 py-1 text-xs text-heading max-w-[200px] truncate">
            <option value="CURRENT">Current Sim</option>
            <option value="ACTUALS">Actuals (YTD)</option>
            <option value="ACTUALS_PREV">Actuals (Prev Year)</option>
            {planList.map(p => (
              <option key={p.plan_id} value={p.plan_id}>{p.plan_name} ({p.status})</option>
            ))}
          </select>
          <span className="text-xs text-faint">vs</span>
          <select value={comparePlanId ?? 'ACTUALS'} onChange={async (e) => {
            const val = e.target.value;
            setComparePlanId(val);
            if (val === 'CURRENT' || val === 'ACTUALS' || val === 'ACTUALS_PREV') {
              setComparePlanData(null);
              setComparePlanGrowth({});
              setComparePlanSnapshot(null);
              return;
            }
            try {
              const res = await fetch(`/api/plans/${val}`);
              if (!res.ok) return;
              const d = await res.json();
              const loaded: Record<string, Record<string, number>> = {};
              const loadedGrowth: Record<string, number> = {};
              let growthParsed = false;
              for (const r of d.rows as Array<Record<string, unknown>>) {
                const fam = String(r.family ?? '');
                const yr = Number(r.forecast_year ?? 0);
                const mo = Number(r.forecast_month ?? 0);
                const mult = Number(r.multiplier ?? 1);
                const mKey = MONTHS.find(m => m.year === yr && m.month === mo)?.key;
                if (!fam || !mKey) continue;
                if (!loaded[fam]) loaded[fam] = {};
                loaded[fam][mKey] = mult;
                if (!growthParsed && r.growth_json) {
                  try {
                    const parsed = JSON.parse(String(r.growth_json));
                    for (const [prod, rate] of Object.entries(parsed)) {
                      if (typeof rate === 'number' && rate !== 1.0) loadedGrowth[prod] = rate;
                    }
                  } catch { /* ignore */ }
                  growthParsed = true;
                }
              }
              setComparePlanData(loaded);
              setComparePlanGrowth(loadedGrowth);
              // Parse frozen snapshot
              let snap: Record<string, Record<string, number>> | null = null;
              const firstRow = (d.rows as Array<Record<string, unknown>>)[0];
              if (firstRow?.snapshot_units_json) {
                try { snap = JSON.parse(String(firstRow.snapshot_units_json)); } catch { /* ignore */ }
              }
              setComparePlanSnapshot(snap);
            } catch { setComparePlanData(null); setComparePlanGrowth({}); setComparePlanSnapshot(null); }
          }} className="bg-surface border border-border rounded px-2 py-1 text-xs text-heading max-w-[200px] truncate">
            <option value="CURRENT">Current Sim</option>
            <option value="ACTUALS">Actuals (YTD)</option>
            <option value="ACTUALS_PREV">Actuals (Prev Year)</option>
            {planList.map(p => (
              <option key={p.plan_id} value={p.plan_id}>{p.plan_name} ({p.status})</option>
            ))}
          </select>
        </div>
      )}

      {/* KPIs */}
      {(() => {
        const renderDelta = (base: number, cmp: number, isCurrency: boolean = true, inverseGood: boolean = false) => {
          if (base === 0 && cmp === 0) return null;
          const diff = base - cmp;
          if (Math.abs(diff) < 0.01) return null; // Too small
          const isGood = inverseGood ? diff <= 0 : diff >= 0;
          const color = isGood ? 'text-emerald-400 bg-emerald-500/10' : 'text-red-400 bg-red-500/10';
          const sign = diff > 0 ? '+' : '';
          const txt = isCurrency ? `$${fK(Math.abs(diff)).replace('$', '')}` : `${Math.abs(diff).toFixed(2)}×`;
          return <span className={`inline-flex items-center px-1.5 py-0.5 rounded text-[9px] font-bold ${color}`}>
            {sign}{diff < 0 ? '-' : ''}{txt}
          </span>;
        };
        const useCompare = compareMode && comparePlanId;
        const b = compareMode ? baseStats : { ytdNp: filteredYtdProfit.total, totals: filteredTotals };
        const c = cmpStats;

        return (
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3">
            <Kpi 
              label="YTD Net Profit" 
              tip="Sales − COGS − Ad Spend\nJan–Mar actuals" 
              value={fK(b.ytdNp)} 
              sub="Jan–Mar actuals" 
              color={b.ytdNp >= 0 ? 'emerald' : 'red'} 
              deltaNode={useCompare ? renderDelta(b.ytdNp, c.ytdNp) : null}
            />
            <Kpi 
              label="Forecast Profit" 
              tip="Σ (Revenue − COGS − Ad Spend)\nSimulated forecast" 
              value={fK(b.totals.netProfit)} 
              sub="Apr–Feb sim" 
              color={b.totals.netProfit >= 0 ? 'emerald' : 'red'} 
              deltaNode={useCompare ? renderDelta(b.totals.netProfit, c.totals.netProfit) : null}
            />
            <Kpi 
              label="Est. EOY Profit" 
              tip="YTD Net Profit + Forecast Profit\nFull-year outlook" 
              value={fK(b.ytdNp + b.totals.netProfit)} 
              sub="YTD + Forecast" 
              color={(b.ytdNp + b.totals.netProfit) >= 0 ? 'emerald' : 'red'} 
              hl 
              deltaNode={useCompare ? renderDelta(b.ytdNp + b.totals.netProfit, c.ytdNp + c.totals.netProfit) : null}
            />
            <Kpi 
              label="Projected Revenue" 
              tip="Σ (demand × ASP) per variation" 
              value={fK(b.totals.revenue)} 
              sub={`${fmt(b.totals.demand)} units`} 
              deltaNode={useCompare ? renderDelta(b.totals.revenue, c.totals.revenue) : null}
            />
            <Kpi 
              label="Ad Spend" 
              tip="Σ (dailySpend × SI × mult × days)" 
              value={fK(b.totals.adSpend)} 
              sub={`${fM(simDaily)}/day${simDaily !== curDaily ? ` (was ${fM(curDaily)})` : ''}`} 
              hl={simDaily !== curDaily} 
              deltaNode={useCompare ? renderDelta(b.totals.adSpend, c.totals.adSpend, true, true) : null}
            />
            <Kpi 
              label="COGS" 
              tip="Σ (demand × costPerUnit)" 
              value={fK(b.totals.cogs)} 
              deltaNode={useCompare ? renderDelta(b.totals.cogs, c.totals.cogs, true, true) : null}
            />
            <Kpi 
              label="Net ROAS" 
              tip="(Revenue − COGS) ÷ Ad Spend\n≥1× means ads are profitable" 
              value={`${b.totals.netRoas.toFixed(2)}×`} 
              color={b.totals.netRoas >= 1 ? 'emerald' : 'amber'} 
              deltaNode={useCompare ? renderDelta(b.totals.netRoas, c.totals.netRoas, false) : null}
            />
          </div>
        );
      })()}

      {/* Family strategies */}
      <Section title="Strategy & Spend Plan — Select strategy per family. Click ✨ to launch planning wizard.">
        <table className="w-full text-xs">
          <thead><tr className="text-muted border-b border-border">
            <th className="text-left py-2 px-2 w-40">Family</th>
            <th className="text-right py-2 px-2 w-20"><Tip text="Current daily ad spend across all campaigns">$/day <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-right py-2 px-2 w-20"><Tip text="Current inventory (FBA + Manufacturer)\nWeeks of stock in parentheses">Stock <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-right py-2 px-2 w-20"><Tip text={`Plan units over the horizon (forecast; current month = remaining)\n${MONTHS[0].label} – ${MONTHS[MONTHS.length - 1].label}`}>Plan Units <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-right py-2 px-2 w-20"><Tip text="Plan net profit = units×margin − ad spend (horizon)">Plan Profit <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-right py-2 px-2 w-20"><Tip text="Total simulated ad spend\nApr ’26 – Feb ’27">Ad Spend <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-right py-2 px-2 w-16"><Tip text="(Revenue − COGS) ÷ Ad Spend\nSimulated gross profit per ad dollar">ROAS <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-right py-2 px-2 w-20"><Tip text="Year-to-date Net Profit\nJan–Mar 2026 actuals">YTD NP <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-right py-2 px-2 w-20"><Tip text="Estimated end-of-year Net Profit\nYTD actuals + simulation forecast">EOY NP <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-center py-2 px-2 w-16"><Tip text="First month stock runs out\nBased on simulated demand">OOS <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-right py-2 px-2 w-16"><Tip text="Gap units to order from manufacturer\nNo safety margin applied">PR Qty <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
            <th className="text-right py-2 px-2 w-20"><Tip text="MFR + SHIP\nTotal landed cost for this purchase request">Landed $ <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          </tr></thead>
          <tbody>
            {filteredFamilies.map(f => {
              const oos = getOos(projs, f.family, false);
              const wks = getWos(f.inventory, projs, f.family, false);
              const isExp = expanded === f.family;
              // Compute per-family sim aggregates
              let fDemand = 0, fRev = 0, fCogs = 0, fAd = 0;
              for (const p of projs) { const fd = p.families[f.family]; if (fd) { fDemand += fd.demand; fRev += fd.revenue; fCogs += fd.cogs; fAd += fd.adSpend; } }
              const fGap = fDemand - f.inventory;
              const fNetRoas = fAd > 0 ? (fRev - fCogs) / fAd : 0;
              const fNp = fRev - fCogs - fAd; // plan net profit over the horizon
              // PR (purchase request) costs per family
              const prQty = fGap > 0 ? Math.ceil(fGap) : 0;
              let fMfrCost = 0, fShipCost = 0;
              if (prQty > 0) {
                // Weighted avg mfr/ship cost across variations
                const totalDailyOrd = f.variations.reduce((s, v) => s + v.dailyOrders, 0) || 1;
                for (const v of f.variations) {
                  const w = v.dailyOrders / totalDailyOrd;
                  fMfrCost += (MFR[v.name] ?? 0) * w;
                  fShipCost += (SHIP[v.name] ?? 0) * w;
                }
              }
              const fMfrTotal = prQty * fMfrCost;
              const fShipTotal = prQty * fShipCost;
              const fLanded = fMfrTotal + fShipTotal;
              return (<FamilyRow key={f.family} f={f} oos={oos} wks={wks} isExp={isExp} projs={projs}
                simUnits={fDemand} simNetProfit={fNp}
                simAdSpend={fAd} simNetRoas={fNetRoas}
                prQty={prQty} prLanded={fLanded}
                actuals2026Full={actuals2026Full}
                actuals2025Full={actuals2025Full}
                forecastMap={forecastMap}
                adsEfficiency={adsEfficiency}
                metaMap={metaMap}
                seasonMap={seasonMap}
                demandMap={demandMap}
                ytdNp={ytdProfit.byFamily[f.family] ?? 0}
                growthOverrides={effectiveGrowth}
                planned={isPlanned(f.family)}
                onToggle={() => setExpanded(isExp ? null : f.family)}
                baseCmp={baseStats?.byFamily?.[f.family]}
                baseCmpType={baseStats?.type}
                baseCmpProjs={baseStats?.projs}
                baseCmpSnapshot={baseStats?.snapshot}
                tgtCmp={cmpStats?.byFamily?.[f.family]}
                tgtCmpType={cmpStats?.type}
                tgtCmpProjs={cmpStats?.projs}
                tgtCmpSnapshot={cmpStats?.snapshot}
                useCompare={compareMode && !!comparePlanId}
                onWizard={() => setWizardFamily(f.family)} />);
            })}
            <tr className="border-t-2 border-border font-bold">
              <td className="py-2 px-2 text-heading">{isFiltered ? 'FILTERED TOTAL' : 'TOTAL'}</td>
              <td className="text-right py-2 px-2 tabular-nums text-muted">{fM(curDaily)}</td>
              <td className="text-right py-2 px-2 tabular-nums text-muted">{fU(filteredFamilies.reduce((s, f) => s + f.inventory, 0))}</td>
              <td className="text-right py-2 px-2 tabular-nums text-heading">{fU(filteredTotals.demand)}</td>
              <td className={`text-right py-2 px-2 tabular-nums font-bold ${filteredTotals.netProfit >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fK(filteredTotals.netProfit)}</td>
              <td className="text-right py-2 px-2 tabular-nums text-heading">{fK(filteredTotals.adSpend)}</td>
              <td className={`text-right py-2 px-2 tabular-nums ${filteredTotals.netRoas >= 1 ? 'text-emerald-400' : 'text-amber-400'}`}>{filteredTotals.netRoas.toFixed(2)}×</td>
              <td className={`text-right py-2 px-2 tabular-nums font-bold ${filteredYtdProfit.total >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fK(filteredYtdProfit.total)}</td>
              <td className={`text-right py-2 px-2 tabular-nums font-bold ${(filteredYtdProfit.total + filteredTotals.netProfit) >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fK(filteredYtdProfit.total + filteredTotals.netProfit)}</td>
              <td></td>
              {(() => {
                // Compute PR totals across all families
                let tPr = 0, tMfr = 0, tShip = 0;
                for (const f of filteredFamilies) {
                  let fd2 = 0; for (const p of projs) { const d = p.families[f.family]; if (d) fd2 += d.demand; }
                  const g = fd2 - f.inventory;
                  const q = g > 0 ? Math.ceil(g) : 0;
                  if (q > 0) {
                    const tdo = f.variations.reduce((s, v) => s + v.dailyOrders, 0) || 1;
                    let wMfr = 0, wShip = 0;
                    for (const v of f.variations) { const w = v.dailyOrders / tdo; wMfr += (MFR[v.name] ?? 0) * w; wShip += (SHIP[v.name] ?? 0) * w; }
                    tPr += q; tMfr += q * wMfr; tShip += q * wShip;
                  }
                }
                return <>
                  <td className="text-right py-2 px-2 tabular-nums text-heading font-bold">{tPr > 0 ? fmt(tPr) : '—'}</td>
                  <td className="text-right py-2 px-2 tabular-nums text-heading font-bold">{(tMfr + tShip) > 0 ? fK(tMfr + tShip) : '—'}</td>
                </>;
              })()}
            </tr>
          </tbody>
        </table>
      </Section>

      {/* Planning Wizard modal */}
      {wizardFamily && (() => {
        const wf = filteredFamilies.find(ff => ff.family === wizardFamily);
        if (!wf) return null;
        return <PlanWizard
          family={wf}
          months={MONTHS as MonthDef[]}
          demandMap={demandMap}
          metaMap={metaMap}
          seasonMap={seasonMap}
          adsEfficiency={adsEfficiency}
          projs={projs}
          growthOverrides={effectiveGrowth}
          actuals2025={actuals2025Full}
          actuals2026={actuals2026Full}
          brandedSearch={brandedSearch}
          channelEfficiency={channelEfficiency}
          roas={familyRoas[wf.family] ?? null}
          latestDataDate={latestDataDate}
          runRateMap={runRateMap}
          familyMonthly2025={familyMonthly2025}
          familyMonthlySpend2025={familyMonthlySpend2025}
          onClose={() => setWizardFamily(null)}
          onSave={async (result) => {
            // Fix #5: Apply brand growth to all products in this family (always, to clear stale overrides)
            const fam = filteredFamilies.find(ff => ff.family === result.family);
            if (fam) {
              setGrowthOverrides(prev => {
                const next = { ...prev };
                for (const v of fam.variations) {
                  next[v.name] = result.brandGrowth;
                }
                return next;
              });
            }
            // Store the wizard's per-product per-month forecast (feeds the frozen snapshot)
            // and set orderOverrides to the YEARLY PLANNED TOTAL (sold YTD + forecast) so the
            // PR table's "Gap from Plan" = planned − sold − stock = forecast − stock.
            if (result.plannedMonthly && Object.keys(result.plannedMonthly).length > 0) {
              setPlannedMonthlyOverrides(prev => ({ ...prev, ...result.plannedMonthly }));
              const famVars = filteredFamilies.find(ff => ff.family === result.family)?.variations ?? [];
              setOrderOverrides(p => {
                const next = { ...p };
                if (result.orderMode === 'manual' && result.orderByProduct) {
                  // Manual buy quantities → override = sold + stock + qty, so PR "Gap from Plan" = your qty.
                  for (const [name, qty] of Object.entries(result.orderByProduct)) {
                    const sold = parentGetSold('', name);
                    const stock = famVars.find(v => v.name === name)?.inventory ?? 0;
                    next[name] = Math.round(sold + stock + qty);
                  }
                } else {
                  // Auto → override = yearly planned total (sold + forecast); Gap from Plan = forecast − stock.
                  for (const [name, byMonth] of Object.entries(result.plannedMonthly)) {
                    const forecast = Object.values(byMonth).reduce((a, b) => a + b, 0);
                    const sold = parentGetSold('', name); // resolves by product name
                    next[name] = Math.round(sold + forecast);
                  }
                }
                return next;
              });
            }
            // Fix #7: Await ads targets save and surface errors
            if (result.adsTargets && result.adsTargets.length > 0) {
              try {
                // Freeze LY/CY ROAS reference onto each target row (ad-only by channel; blended on all).
                const fr = familyRoas[result.family];
                const enriched = result.adsTargets.map(t => ({
                  ...t,
                  ly_ad_net_roas: fr?.adOnly[t.channel]?.[2025] ?? null,
                  cy_ad_net_roas: fr?.adOnly[t.channel]?.[2026] ?? null,
                  ly_net_roas: fr?.blended[2025] ?? null,
                  cy_net_roas: fr?.blended[2026] ?? null,
                }));
                const resp = await fetch('/api/plans/ads-targets', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ family: result.family, targets: enriched }),
                });
                const d = await resp.json();
                if (d.success) {
                  console.log(`[AdsTargets] Saved ${d.targets_saved} targets for ${result.family}`);
                  // Optimistically refresh plannedSpend/plannedCpc for this family so `isPlanned`
                  // flips true immediately — the [families]-keyed loader won't re-run on save, so
                  // without this the main page stays on the runSim estimate until a page reload.
                  const { spendByMonth, cpcByMonth } = aggregateAdsTargetSpend(result.adsTargets);
                  setPlannedSpend(prev => ({ ...prev, [result.family]: spendByMonth }));
                  setPlannedCpc(prev => ({ ...prev, [result.family]: cpcByMonth }));
                } else {
                  console.error('[AdsTargets] Save failed:', d.error);
                  alert(`⚠️ Ads targets failed to save: ${d.error || 'Unknown error'}. Local plan was saved but targets were not persisted.`);
                }
              } catch (e) {
                console.error('[AdsTargets] Save error:', e);
                alert(`⚠️ Ads targets failed to save: ${e instanceof Error ? e.message : 'Network error'}. Local plan was saved but targets were not persisted.`);
              }
            }
            setPlanDirty(true); setPlanSaved(false);
            setWizardFamily(null);
          }}
        />;
      })()}

      {/* ─── Plan Summary Section ─── */}
      <PurchaseRequestSection families={filteredFamilies} projs={projs} orderOverrides={orderOverrides}
        planId={activePlan?.plan_id ?? null}
        planStatus={activePlan?.status ?? null}
        originalOverrides={originalOverrides}
        onOverride={(name, qty) => {
          // Just set the order override — effectiveGrowth useMemo auto-derives
          // the correct growth multiplier from qty using the same math as runSim.
          setOrderOverrides(p => ({ ...p, [name]: qty }));
          setPlanDirty(true); setPlanSaved(false);
        }}
        onResetOverrides={() => setOrderOverrides({})} />

      {/* ─── New: Replenishment Flow + Shipment Cards (SP-backed) ─── */}
      <ReplenishmentFlowWrapper orderOverrides={orderOverrides} salesSummary={salesSummary} demandMap={demandMap} seasonMap={seasonMap} metaMap={metaMap} growthOverrides={effectiveGrowth} products={filteredProducts} projs={projs} unconstrainedForecastMap={unconstrainedForecastMap} />

      {activePlan?.status === 'APPROVED' && (
        <PlanVsRealityPanel families={filteredFamilies} snapshot={activeSnapshot} actuals2026Full={actuals2026Full}
          plannedSpend={plannedSpend} plannedCpc={plannedCpc} actualsWeekly={actualsWeekly} planUpdatedAt={activePlan?.updated_at ?? null} />
      )}

      <CashflowSection projs={projs} families={filteredFamilies} planId={activePlan?.plan_id ?? null} />
    </div>
  );
}

function FamilyRow({ f, oos, wks, isExp, projs, simUnits, simNetProfit, simAdSpend, simNetRoas, prQty, prLanded, actuals2026Full, actuals2025Full, forecastMap, adsEfficiency, metaMap, seasonMap, demandMap, ytdNp, growthOverrides, planned, onToggle, onWizard, baseCmp, baseCmpType, baseCmpProjs, baseCmpSnapshot, tgtCmp, tgtCmpType, tgtCmpProjs, tgtCmpSnapshot, useCompare }: {
  f: FamilyBaseline; oos: string | null; wks: number; isExp: boolean; projs: MonthProj[];
  simUnits: number; simNetProfit: number; simAdSpend: number; simNetRoas: number;
  prQty: number; prLanded: number;
  actuals2026Full: Map<string, Map<number, { units: number; revenue: number; cogs: number; adCost: number }>>;
  actuals2025Full: Map<string, Map<number, { units: number; revenue: number; cogs: number; adCost: number }>>;
  adsEfficiency: AdsEfficiencyMap;
  metaMap: ForecastMetaMap;
  seasonMap: MonthSeasonMap;
  demandMap: ForecastDemandMap;
  ytdNp: number;
  growthOverrides: Record<string, number>;
  planned: boolean;
  forecastMap: ForecastRoasMap;
  onToggle: () => void; onWizard: () => void;
  baseCmp?: { ytdNp: number; totals: { revenue: number, cogs: number, adSpend: number, netProfit: number, demand: number, netRoas: number } };
  baseCmpType?: string;
  baseCmpProjs?: MonthProj[] | null;
  baseCmpSnapshot?: Record<string, Record<string, number>> | null;
  tgtCmp?: { ytdNp: number; totals: { revenue: number, cogs: number, adSpend: number, netProfit: number, demand: number, netRoas: number } };
  tgtCmpType?: string;
  tgtCmpProjs?: MonthProj[] | null;
  tgtCmpSnapshot?: Record<string, Record<string, number>> | null;
  useCompare?: boolean;
}) {
  const [tab, setTab] = useState<'units'|'revenue'|'adSpend'|'netProfit'|'netRoas'|'lastYear'|'cmpUnits'>('units');
  // Simulated forecast profit for this family
  const simNp = useMemo(() => {
    let np = 0;
    for (const p of projs) { const fd = p.families[f.family]; if (fd) np += fd.netProfit; }
    return np;
  }, [projs, f.family]);
  return (<>
    <tr className={`border-b border-border/30 hover:bg-white/[.02] cursor-pointer ${isExp ? 'bg-white/[.03]' : ''}`} onClick={onToggle}>
      <td className="py-2.5 px-2 font-medium text-heading">
        <span className="inline-flex items-center gap-2">
          {isExp ? <ChevronDown size={12} className="text-faint" /> : <ChevronRight size={12} className="text-faint" />}
          <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: FAMILY_COLORS[f.family] ?? '#666' }} />
          {f.family}
          <span className="text-[9px] text-faint">({f.variations.length})</span>
          {!planned && <span className="text-[8px] px-1 py-0.5 rounded bg-amber-500/15 text-amber-400 font-medium" title="Not planned in the wizard — showing a runSim estimate">est · not planned</span>}
          <button onClick={e => { e.stopPropagation(); onWizard(); }} className="ml-1 px-1.5 py-0.5 rounded text-[9px] bg-blue-500/15 text-blue-400 hover:bg-blue-500/25 transition-colors" title="Open planning wizard">✨</button>
        </span>
      </td>
      <td className="text-right py-2 px-2 text-muted tabular-nums">{fM(f.dailySpend)}</td>
      <td className="text-right py-2 px-2 tabular-nums text-muted">{fU(f.inventory)} <span className="text-faint text-[9px]">({wks}w)</span></td>
      <td className="text-right py-2 px-2 tabular-nums text-heading">{fU(simUnits)}</td>
      <td className={`text-right py-2 px-2 tabular-nums font-bold ${simNetProfit >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fK(simNetProfit)}</td>
      <td className="text-right py-2 px-2 tabular-nums text-heading">
        <div>{fK(simAdSpend)}</div>
        {useCompare && baseCmp && tgtCmp && renderDeltaNode(baseCmp.totals.adSpend, tgtCmp.totals.adSpend, 'currency', true, 'ml-auto mt-0.5 block w-fit')}
      </td>
      <td className={`text-right py-2 px-2 tabular-nums ${simNetRoas >= 1 ? 'text-emerald-400' : 'text-amber-400'}`}>
        <div>{simNetRoas.toFixed(2)}×</div>
        {useCompare && baseCmp && tgtCmp && renderDeltaNode(baseCmp.totals.netRoas, tgtCmp.totals.netRoas, 'multiplier', false, 'ml-auto mt-0.5 block w-fit')}
      </td>
      <td className={`text-right py-2 px-2 tabular-nums ${ytdNp >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
        <div>{fK(ytdNp)}</div>
        {useCompare && baseCmp && tgtCmp && renderDeltaNode(baseCmp.ytdNp, tgtCmp.ytdNp, 'currency', false, 'ml-auto mt-0.5 block w-fit')}
      </td>
      <td className={`text-right py-2 px-2 tabular-nums font-bold ${(ytdNp + simNp) >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
        <div>{fK(ytdNp + simNp)}</div>
        {useCompare && baseCmp && tgtCmp && renderDeltaNode(baseCmp.ytdNp + baseCmp.totals.netProfit, tgtCmp.ytdNp + tgtCmp.totals.netProfit, 'currency', false, 'ml-auto mt-0.5 block w-fit')}
      </td>
      <td className="text-center py-2 px-2">{oos
        ? <span className="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full bg-red-500/15 text-red-400"><AlertTriangle size={10} />{oos}</span>
        : <span className="text-[10px] text-emerald-400 font-medium">OK</span>}</td>
      <td className="text-right py-2 px-2 tabular-nums text-heading font-medium">{prQty > 0 ? fmt(prQty) : '—'}</td>
      <td className="text-right py-2 px-2 tabular-nums text-heading font-bold">{prLanded > 0 ? fK(prLanded) : '—'}</td>
    </tr>
    {isExp && <tr><td colSpan={12} className="p-0">
      <div className="bg-surface/50 border-y border-border/50 px-4 py-3 space-y-3">

        {/* Variation rows */}
        <table className="w-full text-[11px]">
          <thead><tr className="text-muted text-[9px] uppercase tracking-wide border-b border-border/30">
            <th className="text-left py-1.5 px-2 w-40">Variant</th>
            <th className="text-right py-1.5 px-2"><Tip text="Share of family's total sales\nBased on 6-month historical avg">Split <span className="text-faint text-[8px]">ⓘ</span></Tip></th>
            <th className="text-right py-1.5 px-2"><Tip text="Current daily ad spend">$/day <span className="text-faint text-[8px]">ⓘ</span></Tip></th>
            <th className="text-right py-1.5 px-2"><Tip text="Current inventory\n(FBA + Manufacturer + AWD)\nWeeks of stock in parentheses">Stock <span className="text-faint text-[8px]">ⓘ</span></Tip></th>
            <th className="text-right py-1.5 px-2"><Tip text="Total simulated demand\nApr '26 – Feb '27">Need <span className="text-faint text-[8px]">ⓘ</span></Tip></th>
            <th className="text-right py-1.5 px-2"><Tip text="Need − Stock\nPositive = shortfall\nNegative = surplus">Gap <span className="text-faint text-[8px]">ⓘ</span></Tip></th>
            <th className="text-right py-1.5 px-2"><Tip text="Order to place = Gap rounded UP to whole cartons\nMatches the Buy Plan Summary\n0 if stock covers demand">Order <span className="text-faint text-[8px]">ⓘ</span></Tip></th>
            <th className="text-right py-1.5 px-2"><Tip text="Order × (mfr cost + shipping)\nTotal landed cost for this PO">Landed $ <span className="text-faint text-[8px]">ⓘ</span></Tip></th>
            <th className="text-center py-1.5 px-2"><Tip text="First month stock runs out">OOS <span className="text-faint text-[8px]">ⓘ</span></Tip></th>
            <th className="text-center py-1.5 px-2"><Tip text="Urgency wave for restocking\nW1 🔴 Apr–May: Critical\nW2 🟡 Jun–Aug: Plan now\nW3 🟢 Sep+: Not urgent">Wave <span className="text-faint text-[8px]">ⓘ</span></Tip></th>
          </tr></thead>
          <tbody>
            {f.variations.map(v => {
              const vOos = getOos(projs, v.name, true);
              const vWks = getWos(v.inventory, projs, v.name, true);
              const wave = waveLabel(vOos);
              let totalNeed = 0;
              for (const p of projs) for (const fd of Object.values(p.families)) totalNeed += fd.vars[v.name]?.demand ?? 0;
              const gap = totalNeed - v.inventory;
              // Carton-rounded buy — matches the Buy Plan Summary card (ceil to whole cartons).
              const orderQty = gap > 0 ? Math.ceil(gap / v.cartonQty) * v.cartonQty : 0;
              const meta = metaMap[v.name];
              return (<tr key={v.name} className="border-b border-border/20 hover:bg-white/[.01]">
                <td className="py-1.5 px-2 font-medium">
                  <span className="inline-flex items-center gap-1.5">
                    <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: PROD_COLORS[v.name] ?? '#666' }} />
                    {v.name}
                    {meta?.isNew && <span className="text-[7px] px-1 py-0.5 rounded bg-blue-500/20 text-blue-300 font-bold">NEW</span>}
                    {meta?.forecastPhase === 'PHASE_1' && <Tip content={`Model: ${meta.modelProduct ?? '—'}`}><span className="text-[7px] px-1 py-0.5 rounded bg-amber-500/20 text-amber-300 font-bold">MODEL</span></Tip>}
                    {meta?.forecastPhase === 'PHASE_2' && <Tip content={`Hybrid: own base × ${meta.modelProduct ?? '—'} seasonality`}><span className="text-[7px] px-1 py-0.5 rounded bg-cyan-500/20 text-cyan-300 font-bold">HYBRID</span></Tip>}
                    {meta?.isDraft && !meta?.forecastPhase?.startsWith('PHASE_') && <span className="text-[7px] px-1 py-0.5 rounded bg-amber-500/20 text-amber-300 font-bold">DRAFT</span>}
                  </span>
                </td>
                <td className="text-right py-1.5 px-2 tabular-nums text-muted">{meta ? fP(meta.share * 100) : fP(v.splitPct * 100)}</td>
                <td className="text-right py-1.5 px-2 tabular-nums">{fM(v.dailySpend)}</td>
                <td className="text-right py-1.5 px-2 tabular-nums">{fU(v.inventory)} <span className="text-faint text-[8px]">({vWks}w)</span></td>
                <td className="text-right py-1.5 px-2 tabular-nums">{fU(totalNeed)}</td>
                <td className={`text-right py-1.5 px-2 tabular-nums font-bold ${gap > 0 ? 'text-red-400' : 'text-emerald-400'}`}>{gap > 0 ? `+${fU(gap)}` : fU(gap)}</td>
                <td className="text-right py-1.5 px-2 tabular-nums font-bold">{orderQty > 0 ? <>{fU(orderQty)} <span className="text-faint text-[8px] font-normal">({Math.round(orderQty / v.cartonQty)} ct)</span></> : '—'}</td>
                <td className="text-right py-1.5 px-2 tabular-nums">{orderQty > 0 ? fK(orderQty * (v.mfrCost + v.shipCost)) : '—'}</td>
                <td className="text-center py-1.5 px-2">{vOos
                  ? <span className="text-[9px] font-bold text-red-400">{vOos}</span>
                  : <span className="text-[9px] text-emerald-400">OK</span>}</td>
                <td className="text-center py-1.5 px-2"><span className={`text-[9px] font-bold ${wave.color === 'red' ? 'text-red-400' : wave.color === 'amber' ? 'text-amber-400' : 'text-emerald-400'}`}>{wave.label}</span></td>
              </tr>);
            })}
            {/* New products (from forecast, not yet in sales data) — only show if NOT already in variations */}
            {Object.entries(metaMap).filter(([name, meta]) => meta.isNew && meta.family === f.family && !f.variations.some(v => v.name === name)).map(([name, meta]) => {
              // Sum forecast demand for all months
              let totalNeed = 0;
              if (demandMap[name]) for (const units of Object.values(demandMap[name])) totalNeed += units;
              const mfrCost = MFR[name] ?? 0;
              const shipCost = SHIP[name] ?? 0;
              const orderQty = totalNeed > 0 ? Math.ceil(totalNeed) : 0;
              return (<tr key={name} className="border-b border-border/20 hover:bg-white/[.01] bg-blue-500/5">
                <td className="py-1.5 px-2 font-medium">
                  <span className="inline-flex items-center gap-1.5">
                    <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: PROD_COLORS[name] ?? '#666' }} />
                    {name}
                    <span className="text-[7px] px-1 py-0.5 rounded bg-blue-500/20 text-blue-300 font-bold">NEW</span>
                    {meta.forecastPhase === 'PHASE_1' && <Tip content={`Model: ${meta.modelProduct ?? '—'}`}><span className="text-[7px] px-1 py-0.5 rounded bg-amber-500/20 text-amber-300 font-bold">MODEL</span></Tip>}
                    {meta.forecastPhase === 'PHASE_2' && <Tip content={`Hybrid: own base × ${meta.modelProduct ?? '—'} seasonality`}><span className="text-[7px] px-1 py-0.5 rounded bg-cyan-500/20 text-cyan-300 font-bold">HYBRID</span></Tip>}
                    {!meta.forecastPhase?.startsWith('PHASE_') && meta.isDraft && <span className="text-[7px] px-1 py-0.5 rounded bg-amber-500/20 text-amber-300 font-bold">DRAFT</span>}
                  </span>
                </td>
                <td className="text-right py-1.5 px-2 tabular-nums text-blue-300">{fP(meta.share * 100)}</td>
                <td className="text-right py-1.5 px-2 tabular-nums text-faint">—</td>
                <td className="text-right py-1.5 px-2 tabular-nums text-faint">0 units</td>
                <td className="text-right py-1.5 px-2 tabular-nums">{fU(totalNeed)}</td>
                <td className={`text-right py-1.5 px-2 tabular-nums font-bold ${totalNeed > 0 ? 'text-red-400' : 'text-emerald-400'}`}>{totalNeed > 0 ? `+${fU(totalNeed)}` : '—'}</td>
                <td className="text-right py-1.5 px-2 tabular-nums font-bold">{orderQty > 0 ? fU(orderQty) : '—'}</td>
                <td className="text-right py-1.5 px-2 tabular-nums">{orderQty > 0 ? fK(orderQty * (mfrCost + shipCost)) : '—'}</td>
                <td className="text-center py-1.5 px-2"><span className="text-[9px] text-faint">N/A</span></td>
                <td className="text-center py-1.5 px-2"><span className="text-[9px] text-faint">—</span></td>
              </tr>);
            })}
          </tbody>
        </table>

        {/* 4-card detail grid */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
          <DCard icon={<Package size={13} />} title="Inventory Pipeline">
            {f.variations.map(v => <div key={v.name} className="flex justify-between text-[10px] py-0.5">
              <span className="text-muted">{v.name}</span>
              <span className="tabular-nums">{Object.entries(v.inventoryBySource).map(([s, q]) => `${s}: ${fU(q)}`).join(', ')}</span>
            </div>)}
            <div className="flex justify-between border-t border-border/40 pt-1 mt-1 text-[10px] font-bold">
              <span>Total</span><span className="tabular-nums">{fU(f.inventory)}</span>
            </div>
          </DCard>
          <DCard icon={<TrendingUp size={13} />} title="Growth & Velocity">
            {f.variations.map(v => {
              const gr = growthOverrides[v.name] ?? 1.0;
              const grPct = Number(((gr - 1) * 100).toFixed(1));
              return <div key={v.name} className="flex items-center justify-between text-[10px] py-0.5 gap-2">
                <span className="text-muted truncate">{v.name}</span>
                <span className="flex items-center gap-1.5 tabular-nums flex-shrink-0">
                  <span className={v.yoyGrowth >= 1 ? 'text-emerald-400' : 'text-red-400'}>{v.yoyGrowth.toFixed(2)}×</span>
                  <span className="text-faint">·</span>
                  {v.dailyOrders.toFixed(1)}/d
                  <span className="text-faint">·</span>
                  <Tip text={`Demand growth for ${v.name} (set in the wizard)\n0% = forecast as-is\n+10% = 10% more demand`}>
                    <span className="inline-flex items-center gap-0.5">
                      <span className={`text-[9px] tabular-nums ${gr !== 1.0 ? 'text-amber-300' : 'text-heading'}`}>{grPct}</span>
                      <span className="text-[8px] text-faint">%</span>
                    </span>
                  </Tip>
                </span>
              </div>;
            })}
          </DCard>
          <DCard icon={<BarChart3 size={13} />} title="Simulated P&L (Apr–Feb)">
            <table className="w-full text-[10px]">
              <thead><tr className="text-muted text-[8px] uppercase tracking-wide">
                <th className="text-left py-0.5"></th><th className="text-right py-0.5">Revenue</th>
                <th className="text-right py-0.5">COGS</th><th className="text-right py-0.5">Ad Spend</th>
                <th className="text-right py-0.5">Net Profit</th>
              </tr></thead>
              <tbody>
                {f.variations.map(v => {
                  let tr = 0, tc = 0, ta = 0;
                  for (const p of projs) for (const fd of Object.values(p.families)) { const d = fd.vars[v.name]; if (d) { tr += d.revenue; tc += d.cogs; ta += d.adSpend; } }
                  const np = tr - tc - ta;
                  return <tr key={v.name} className="border-b border-border/10">
                    <td className="py-0.5 text-muted">{v.name}</td>
                    <td className="text-right py-0.5 tabular-nums">{fK(tr)}</td>
                    <td className="text-right py-0.5 tabular-nums text-muted">{fK(tc)}</td>
                    <td className="text-right py-0.5 tabular-nums text-muted">{fK(ta)}</td>
                    <td className={`text-right py-0.5 tabular-nums font-bold ${np >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fK(np)}</td>
                  </tr>;
                })}
                {(() => {
                  let tr = 0, tc = 0, ta = 0;
                  for (const v of f.variations) for (const p of projs) for (const fd of Object.values(p.families)) { const d = fd.vars[v.name]; if (d) { tr += d.revenue; tc += d.cogs; ta += d.adSpend; } }
                  const np = tr - tc - ta;
                  return <tr className="border-t border-border/40 font-bold">
                    <td className="py-0.5">Total</td>
                    <td className="text-right py-0.5 tabular-nums">{fK(tr)}</td>
                    <td className="text-right py-0.5 tabular-nums text-muted">{fK(tc)}</td>
                    <td className="text-right py-0.5 tabular-nums text-muted">{fK(ta)}</td>
                    <td className={`text-right py-0.5 tabular-nums ${np >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fK(np)}</td>
                  </tr>;
                })()}
              </tbody>
            </table>
          </DCard>
          <DCard icon={<ShoppingCart size={13} />} title="Buy Plan Summary">
            {f.variations.map(v => {
              let need = 0;
              for (const p of projs) for (const fd of Object.values(p.families)) need += fd.vars[v.name]?.demand ?? 0;
              const gap = need - v.inventory;
              const qty = gap > 0 ? Math.ceil(gap / v.cartonQty) * v.cartonQty : 0;
              const cartons = qty > 0 ? Math.round(qty / v.cartonQty) : 0;
              return <div key={v.name} className="flex justify-between text-[10px] py-0.5">
                <span className="text-muted">{v.name}</span>
                <span className="tabular-nums">{qty > 0 ? `${fU(qty)} (${cartons} ct) · ${fK(qty * (v.mfrCost + v.shipCost))}` : '—'}</span>
              </div>;
            })}
            {(() => { let tq = 0, tc = 0, tct = 0; for (const v of f.variations) { let need = 0; for (const p of projs) for (const fd of Object.values(p.families)) need += fd.vars[v.name]?.demand ?? 0; const g = need - v.inventory; const q = g > 0 ? Math.ceil(g / v.cartonQty) * v.cartonQty : 0; tq += q; tct += q > 0 ? Math.round(q / v.cartonQty) : 0; tc += q * (v.mfrCost + v.shipCost); } return tq > 0 ? <div className="flex justify-between border-t border-border/40 pt-1 mt-1 text-[10px] font-bold"><span>Total</span><span className="tabular-nums">{fU(tq)} ({tct} ct) · {fK(tc)}</span></div> : null; })()}
          </DCard>
          {/* Ads Efficiency Model — 3-parameter identity diagnostics */}
          {(() => {
            const famEff = adsEfficiency[f.family];
            if (!famEff || Object.keys(famEff).length === 0) return null;
            // Compute weighted averages across months
            let wCpc = 0, wCvr = 0, wShare = 0, wRoas = 0, wTotal = 0;
            let tUnits = 0, tSpend = 0, tProfit = 0, cUnits = 0, cSpend = 0, cProfit = 0;
            let cDaily = 0, cCount = 0, cCpcSum = 0, cCpcN = 0;
            for (const [, d] of Object.entries(famEff)) {
              const w = d.suggestedSpend || 1;
              wCpc += d.cpc * w; wCvr += d.unitCvrPct * w; wShare += d.adsSharePct * w; wRoas += d.netRoas * w;
              wTotal += w; tUnits += d.forecastUnits; tSpend += d.suggestedSpend; tProfit += d.targetNetProfit;
              cUnits += d.currentForecastUnits; cSpend += d.currentSpend; cProfit += d.currentNetProfit;
              if (d.currentDailySpend > 0) { cDaily += d.currentDailySpend; cCount++; }
              if (d.currentCpc > 0) { cCpcSum += d.currentCpc; cCpcN++; }
            }
            if (wTotal === 0) return null;
            const avgCpc = wCpc / wTotal;
            const avgCvr = wCvr / wTotal;
            const avgShare = wShare / wTotal;
            const avgRoas = wRoas / wTotal;
            const avgDaily = cCount > 0 ? cDaily / cCount : 0;
            const currCpc = cCpcN > 0 ? cCpcSum / cCpcN : 0;
            const gapPct = cSpend > 0 ? Math.round(((tSpend - cSpend) / cSpend) * 100) : 0;
            return (
              <DCard icon={<Calculator size={13} />} title="Ads Model (3-Param)">
                <div className="space-y-1">
                  <div className="flex justify-between text-[10px]"><span className="text-muted">CPC</span><span className="tabular-nums font-medium"><span className={currCpc > avgCpc ? 'text-red-400' : 'text-emerald-400'}>${currCpc.toFixed(3)}</span> <span className="text-faint">→</span> <span className="text-violet-300">${avgCpc.toFixed(3)}</span></span></div>
                  <div className="flex justify-between text-[10px]"><span className="text-muted">Unit CVR</span><span className="tabular-nums font-medium">{avgCvr.toFixed(2)}%</span></div>
                  <div className="flex justify-between text-[10px]"><span className="text-muted">Ads Share</span><span className="tabular-nums font-medium">{avgShare.toFixed(0)}%</span></div>
                  <div className="flex justify-between text-[10px]"><span className="text-muted">Net ROAS</span><span className={`tabular-nums font-bold ${avgRoas >= 1 ? 'text-emerald-400' : 'text-red-400'}`}>{avgRoas.toFixed(2)}×</span></div>
                  <div className="border-t border-border/40 pt-1 mt-1 space-y-0.5">
                    <div className="flex justify-between text-[10px]"><span className="text-cyan-300">Current</span><span className="tabular-nums font-bold text-cyan-300">{fmt(Math.round(cUnits))} u · {fK(cSpend)} · {fK(cProfit)} profit</span></div>
                    <div className="flex justify-between text-[10px]"><span className="text-violet-300">Target</span><span className="tabular-nums font-bold text-violet-300">{fmt(Math.round(tUnits))} u · {fK(tSpend)} · {fK(tProfit)} profit</span></div>
                    {gapPct > 0 && <div className="flex justify-between text-[10px]"><span className="text-muted">Gap</span><span className="tabular-nums font-medium text-amber-400">+{gapPct}% spend needed</span></div>}
                    {avgDaily > 0 && <div className="flex justify-between text-[10px]"><span className="text-muted">Run rate</span><span className="tabular-nums text-faint">${Math.round(avgDaily)}/day</span></div>}
                  </div>
                  <div className="text-[8px] text-faint mt-1">Spend ÷ CPC × CVR ÷ AdsShare</div>
                </div>
              </DCard>
            );
          })()}
        </div>

        {/* Tabbed monthly breakdown: actual vs forecast */}
        <div>
          <div className="flex items-center gap-1 mb-2">
            {((useCompare ? ['units','revenue','adSpend','netProfit','netRoas','lastYear','cmpUnits'] : ['units','revenue','adSpend','netProfit','netRoas','lastYear']) as const).map(t => {
              const labels: Record<string, string> = { units: 'Units', revenue: 'Revenue', adSpend: 'Ad Spend', netProfit: 'Net Profit', netRoas: 'Net ROAS', lastYear: '2025 Units', cmpUnits: 'Compare Units' };
              const tips: Record<string, string> = {
                units: 'Simulated demand = dailyOrders × SI × demandMult × days',
                revenue: 'demand × ASP (average selling price)',
                adSpend: 'dailySpend × SI × mult × days',
                netProfit: 'Revenue − COGS − Ad Spend',
                netRoas: '(Revenue − COGS) ÷ Ad Spend',
                lastYear: '2025 actual units sold per month (reference)',
                cmpUnits: 'Base vs Target comparison variance per month'
              };
              return <Tip key={t} text={tips[t]}>
                <button onClick={() => setTab(t)}
                  className={`text-[9px] px-2.5 py-1 rounded-full font-medium transition-colors ${tab === t ? (t === 'lastYear' ? 'bg-purple-500/20 text-purple-300 border border-purple-500/40' : t === 'cmpUnits' ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/40' : 'bg-blue-500/20 text-blue-300 border border-blue-500/40') : 'text-muted hover:text-heading border border-transparent hover:border-border/50'}`}>
                  {labels[t]} <span className="text-faint text-[8px]">ⓘ</span>
                </button>
              </Tip>;
            })}
          </div>
          {tab !== 'cmpUnits' && tab !== 'lastYear' && (
            <div className="text-[9px] text-faint mb-1 flex flex-wrap gap-x-3 gap-y-0.5">
              <span><span className="text-amber-400 font-semibold">Actual</span> = 2026 YTD</span>
              <span><span className="text-cyan-400 font-semibold">Forecast</span> = your plan</span>
              <span><span className="text-purple-400 font-semibold">2025</span> = last year</span>
            </div>
          )}
          <div className="overflow-x-auto"><table className="w-full text-[9px]">
            <thead><tr className="text-muted border-b border-border/30">
              <th className="text-left py-1 px-1.5 w-32">Variant</th>
              <th className="text-left py-1 px-1.5 w-14">Type</th>
              {ML.map((m, mi) => {
                const key = 2026 * 100 + (mi + 1);
                const si = seasonMap[f.family]?.[key];
                const hasPeak = si && si.peakDays > 0;
                const tipText = si ? `P: ${si.peakDays}d / O: ${si.offseasonDays}d${si.holidays ? '\n' + si.holidays : ''}` : 'Offseason';
                return <th key={m} className="text-right py-1 px-1.5 w-12">
                  <Tip text={tipText}>
                    <span className="inline-flex flex-col items-end gap-0">
                      <span>{m}</span>
                      {hasPeak && <span className="text-[6px] text-amber-400 leading-none">🔥{si.peakDays}d</span>}
                    </span>
                  </Tip>
                </th>;
              })}
              {[{yr: 2027, mo: 1, label: "Jan'27"}, {yr: 2027, mo: 2, label: "Feb'27"}].map(({yr, mo, label}) => {
                const key = yr * 100 + mo;
                const si = seasonMap[f.family]?.[key];
                const hasPeak = si && si.peakDays > 0;
                const tipText = si ? `P: ${si.peakDays}d / O: ${si.offseasonDays}d${si.holidays ? '\n' + si.holidays : ''}` : 'Offseason';
                return <th key={label} className="text-right py-1 px-1.5 w-12 text-blue-300/60">
                  <Tip text={tipText}>
                    <span className="inline-flex flex-col items-end gap-0">
                      <span>{label}</span>
                      {hasPeak && <span className="text-[6px] text-amber-400 leading-none">🔥{si!.peakDays}d</span>}
                    </span>
                  </Tip>
                </th>;
              })}
              <th className="text-right py-1 px-1.5 font-bold w-16">Total</th>
            </tr></thead>
            <tbody>{(() => {
              const currentMonth = new Date().getMonth();
              const getVal = (d: { units: number; revenue: number; cogs: number; adCost?: number; adSpend?: number } | undefined, type: typeof tab): number | null => {
                if (!d) return null;
                const ad = (d as any).adCost ?? (d as any).adSpend ?? 0;
                switch (type) {
                  case 'units': case 'lastYear': return d.units;
                  case 'revenue': return d.revenue;
                  case 'adSpend': return ad;
                  case 'netProfit': return d.revenue - d.cogs - ad;
                  case 'netRoas': return ad > 0 ? (d.revenue - d.cogs) / ad : null;
                }
              };
              const fmtVal = (v: number | null): string => {
                if (v === null) return '—';
                if (tab === 'netRoas') return v > 50 ? '∞' : `${v.toFixed(1)}×`;
                if (tab === 'units' || tab === 'lastYear' || tab === 'cmpUnits') return fmt(Math.round(v));
                return fK(v);
              };
              const colorVal = (v: number | null, dimmed: boolean): string => {
                if (dimmed) return 'text-faint/30';
                if (v === null) return 'text-faint/50';
                if (tab === 'netRoas') return v >= 1 ? 'text-emerald-400' : 'text-red-400';
                if (tab === 'netProfit') return v >= 0 ? 'text-emerald-400' : 'text-red-400';
                return '';
              };
              const allMonthIdx = Array.from({ length: 14 }, (_, i) => i);

              // ── Sorted by variant: Actual → Forecast → Last Year per variant ──
              const sortedVariants = [...f.variations].sort((a, b) => a.name.localeCompare(b.name));
              const allRows = sortedVariants.flatMap(v => {
                const rows: React.ReactElement[] = [];

                if (tab === 'cmpUnits' && useCompare && baseCmp && tgtCmp && baseCmpType && tgtCmpType) {
                  const getMonthlyUnits = (type: string, cmpprojs: MonthProj[] | null | undefined, snapshot: Record<string, Record<string, number>> | null | undefined): (number | null)[] => {
                    if (type === 'ACTUALS') {
                      const map = actuals2026Full.get(v.name);
                      return allMonthIdx.map(i => i < 12 ? (map?.get(i)?.units ?? null) : null);
                    }
                    if (type === 'ACTUALS_PREV') {
                      const map = actuals2025Full.get(v.name);
                      return allMonthIdx.map(i => i < 12 ? (map?.get(i)?.units ?? null) : null);
                    }
                    // If this is a saved plan with frozen snapshot → use it
                    if (snapshot && snapshot[v.name]) {
                      const frozenProd = snapshot[v.name];
                      return allMonthIdx.map(i => {
                        const mi = MONTHS.find(mm => (mm.year === 2026 ? mm.month - 1 : mm.month + 11) === i);
                        if (!mi) {
                          // Past month — use actuals
                          const currentMonthIdx = MONTHS[0].year === 2026 ? MONTHS[0].month - 1 : MONTHS[0].month + 11;
                          if (i < currentMonthIdx) {
                            if (i <= 11) return actuals2026Full.get(v.name)?.get(i)?.units ?? null;
                            return actuals2025Full.get(v.name)?.get(i - 12)?.units ?? null;
                          }
                          return null;
                        }
                        return frozenProd[mi.key] ?? null;
                      });
                    }
                    if (!cmpprojs) return allMonthIdx.map(() => null);
                    return allMonthIdx.map(i => {
                      const p = cmpprojs.find(x => {
                        const mi = MONTHS.find(mm => mm.key === x.key);
                        if (!mi) return false;
                        return (mi.year === 2026 ? mi.month - 1 : mi.month + 11) === i;
                      });
                      const currentMonthIdx = MONTHS[0].year === 2026 ? MONTHS[0].month - 1 : MONTHS[0].month + 11;
                      if (!p) {
                        if (i < currentMonthIdx) {
                           if (i <= 11) return actuals2026Full.get(v.name)?.get(i)?.units ?? null;
                           return actuals2025Full.get(v.name)?.get(i - 12)?.units ?? null;
                        }
                        return null;
                      }
                      let demand = p.families[f.family]?.vars[v.name]?.demand ?? null;
                      if (i === currentMonthIdx && demand !== null) {
                        const mtdActuals = i <= 11 ? (actuals2026Full.get(v.name)?.get(i)?.units ?? 0) : (actuals2025Full.get(v.name)?.get(i - 12)?.units ?? 0);
                        demand += mtdActuals;
                      }
                      return demand;
                    });
                  };

                  const baseArr = getMonthlyUnits(baseCmpType, baseCmpProjs, baseCmpSnapshot);
                  const tgtArr = getMonthlyUnits(tgtCmpType, tgtCmpProjs, tgtCmpSnapshot);
                  let bTot = 0, tTot = 0, varTot = 0;

                  // Render Base Row
                  rows.push(
                    <tr key={v.name + '-base'} className="border-b border-border/10">
                      <td className="py-1 px-1.5 font-medium"><span className="inline-flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full" style={{ background: PROD_COLORS[v.name] ?? '#666' }} />{v.name}</span></td>
                      <td className="py-1 px-1.5 text-blue-400 font-medium">{baseCmpType === 'CURRENT' ? 'Current Sim' : baseCmpType === 'ACTUALS_PREV' ? '2025 Act' : baseCmpType === 'ACTUALS' ? '2026 Act' : 'Base Plan'}</td>
                      {allMonthIdx.map(i => {
                        const val = baseArr[i];
                        if (val !== null) bTot += val;
                        return <td key={i} className="text-right py-1 px-1.5 tabular-nums">{fmtVal(val)}</td>;
                      })}
                      <td className="text-right py-1 px-1.5 tabular-nums font-bold text-blue-300">{fmt(Math.round(bTot))}</td>
                    </tr>
                  );

                  // Render Target Row
                  rows.push(
                    <tr key={v.name + '-tgt'} className="border-b border-amber-500/10 bg-amber-500/5">
                      <td className="py-1 px-1.5 font-medium text-amber-300/80"><span className="inline-flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full" style={{ background: PROD_COLORS[v.name] ?? '#666' }} />{v.name}</span></td>
                      <td className="py-1 px-1.5 text-amber-400 font-medium">{tgtCmpType === 'CURRENT' ? 'Current Sim' : tgtCmpType === 'ACTUALS_PREV' ? '2025 Act' : tgtCmpType === 'ACTUALS' ? '2026 Act' : 'Target Plan'}</td>
                      {allMonthIdx.map(i => {
                        const val = tgtArr[i];
                        if (val !== null) tTot += val;
                        return <td key={i} className="text-right py-1 px-1.5 tabular-nums text-amber-400/80">{fmtVal(val)}</td>;
                      })}
                      <td className="text-right py-1 px-1.5 tabular-nums font-bold text-amber-300/80">{fmt(Math.round(tTot))}</td>
                    </tr>
                  );

                  // Render Variance Row (Base - Target)
                  rows.push(
                    <tr key={v.name + '-var'} className="border-b border-border/40">
                      <td colSpan={2} className="py-1 px-1.5 text-right font-medium text-faint">Variance</td>
                      {allMonthIdx.map(i => {
                        const bv = baseArr[i];
                        const tv = tgtArr[i];
                        if (bv === null || tv === null) return <td key={i} className="text-right py-1 px-1.5 tabular-nums text-faint/50">—</td>;
                        const diff = bv - tv;
                        varTot += diff;
                        return <td key={i} className={`text-right py-1 px-1.5 tabular-nums font-bold ${diff > 0 ? 'text-emerald-400' : diff < 0 ? 'text-red-400' : 'text-faint'}`}>
                          {diff > 0 ? '+' : ''}{fmt(Math.round(diff))}
                        </td>;
                      })}
                      <td className={`text-right py-1 px-1.5 tabular-nums font-bold ${varTot > 0 ? 'text-emerald-400' : varTot < 0 ? 'text-red-400' : 'text-faint'}`}>
                        {varTot > 0 ? '+' : ''}{fmt(Math.round(varTot))}
                      </td>
                    </tr>
                  );

                  return rows;
                }

                // ACTUAL row (2026)
                if (tab !== 'lastYear' && tab !== 'cmpUnits') {
                  const actualData = actuals2026Full.get(v.name);
                  let actualTotal = 0;
                  rows.push(
                    <tr key={v.name + '-actual'} className="border-b border-border/10">
                      <td className="py-1 px-1.5 font-medium">
                        <span className="inline-flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full" style={{ background: PROD_COLORS[v.name] ?? '#666' }} />{v.name}</span>
                      </td>
                      <td className="py-1 px-1.5 text-blue-400 font-medium">Actual</td>
                      {allMonthIdx.map(i => {
                        const d = i < 12 ? actualData?.get(i) : undefined;
                        const val = d ? getVal(d, tab) : null;
                        const isFuture = i < 12 ? i > currentMonth : true;
                        if (val !== null && tab !== 'netRoas') actualTotal += val;
                        return <td key={i} className={`text-right py-1 px-1.5 tabular-nums ${colorVal(val, isFuture)}`}>
                          {isFuture ? '·' : fmtVal(val)}
                        </td>;
                      })}
                      <td className="text-right py-1 px-1.5 tabular-nums font-bold text-blue-300">
                        {tab === 'netRoas' ? '—' : tab === 'units' ? fmt(Math.round(actualTotal)) : fK(actualTotal)}
                      </td>
                    </tr>
                  );
                }

                // FORECAST row
                if (tab !== 'lastYear' && tab !== 'cmpUnits') {
                  const varFcByMonth: Map<number, { units: number; revenue: number; cogs: number; adSpend: number }> = new Map();
                  const currentMonthIdx = MONTHS[0].year === 2026 ? MONTHS[0].month - 1 : MONTHS[0].month + 11;
                  for (let i = 0; i < currentMonthIdx; i++) {
                    const yr = i <= 11 ? 2026 : 2027;
                    const mo = i <= 11 ? i + 1 : i - 11;
                    const units = demandMap[v.name]?.[yr * 100 + mo] ?? 0;
                    if (units > 0) {
                      const rev = units * v.price;
                      const cogs = units * v.cogs;
                      const baseRoas = forecastMap[f.family]?.[mo]?.roas ?? 2.0;
                      const adSpend = baseRoas > 0 ? rev / baseRoas : 0;
                      varFcByMonth.set(i, { units, revenue: rev, cogs, adSpend });
                    }
                  }

                  for (const p of projs) {
                    const fd = p.families[f.family];
                    if (!fd) continue;
                    const vd = fd.vars[v.name];
                    if (!vd) continue;
                    const mi = MONTHS.find(mm => mm.key === p.key);
                    if (mi) varFcByMonth.set(mi.year === 2026 ? mi.month - 1 : mi.month + 11, { units: vd.demand, revenue: vd.revenue, cogs: vd.cogs, adSpend: vd.adSpend });
                  }

                  let varFcTotal = 0;
                  rows.push(
                    <tr key={v.name + '-forecast'} className="border-b border-amber-500/10 bg-amber-500/5">
                      <td className="py-1 px-1.5 font-medium text-amber-300/80">
                        <span className="inline-flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full" style={{ background: PROD_COLORS[v.name] ?? '#666' }} />{v.name}</span>
                      </td>
                      <td className="py-1 px-1.5 text-amber-400 font-medium">Target Plan</td>
                      {allMonthIdx.map(i => {
                        if (tab === 'netRoas') {
                          const fd = varFcByMonth.get(i);
                          const isPast = i < currentMonthIdx;
                          const roas = fd && fd.adSpend > 0 ? (fd.revenue - fd.cogs) / fd.adSpend : null;
                          return <td key={i} className={`text-right py-1 px-1.5 tabular-nums font-medium ${colorVal(roas, isPast)}`}>
                            {roas !== null ? fmtVal(roas) : '—'}
                          </td>;
                        }
                        const fd = varFcByMonth.get(i);
                        const val = fd ? getVal(fd, tab) : null;
                        const isPast = i < currentMonthIdx;
                        if (val !== null) varFcTotal += val;
                        return <td key={i} className={`text-right py-1 px-1.5 tabular-nums font-medium ${colorVal(val, isPast)}`}>
                          {val !== null ? fmtVal(val) : '—'}
                        </td>;
                      })}
                      <td className="text-right py-1 px-1.5 tabular-nums font-medium text-amber-300/80">
                        {tab === 'netRoas' ? '—' : tab === 'units' ? fmt(Math.round(varFcTotal)) : fK(varFcTotal)}
                      </td>
                    </tr>
                  );
                }

                // LAST YEAR row (2025 actuals — respects current tab)
                {
                  const lyData = actuals2025Full.get(v.name);
                  let lyTotal = 0;
                  rows.push(
                    <tr key={v.name + '-lastyear'} className={`border-b ${tab === 'lastYear' ? 'border-border/10' : 'border-purple-500/10 bg-purple-500/5'}`}>
                      <td className="py-1 px-1.5 font-medium text-purple-300/80">
                        <span className="inline-flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full" style={{ background: PROD_COLORS[v.name] ?? '#666' }} />{v.name}</span>
                      </td>
                      <td className="py-1 px-1.5 text-purple-400 font-medium">2025</td>
                      {allMonthIdx.map(i => {
                        const d = i < 12 ? lyData?.get(i) : undefined;
                        const activeTab = tab === 'lastYear' ? 'units' : tab;
                        const val = d ? getVal(d, activeTab as typeof tab) : null;
                        if (val !== null && activeTab !== 'netRoas') lyTotal += val;
                        return <td key={i} className={`text-right py-1 px-1.5 tabular-nums ${val === null ? 'text-faint/30' : 'text-purple-300/70'}`}>
                          {val !== null ? fmtVal(val) : '—'}
                        </td>;
                      })}
                      <td className="text-right py-1 px-1.5 tabular-nums font-bold text-purple-300">
                        {tab === 'netRoas' ? '—' : (tab === 'units' || tab === 'lastYear') ? fmt(Math.round(lyTotal)) : fK(lyTotal)}
                      </td>
                    </tr>
                  );
                }

                return rows;
              });

              // ── New products (forecast-only, no actuals/last year) — only if not already in variations ──
              const variationNames = new Set(f.variations.map(v => v.name));
              const newProductRows = Object.entries(metaMap)
                .filter(([name, meta]) => meta.isNew && meta.family === f.family && !variationNames.has(name))
                .sort(([a], [b]) => a.localeCompare(b))
                .flatMap(([name]) => {
                  if (tab === 'lastYear') return []; // no 2025 data for new products
                  const rows: React.ReactElement[] = [];
                  // Forecast row from demandMap (units only, since no simulation runs for new products)
                  let fcTotal = 0;
                  rows.push(
                    <tr key={name + '-new-forecast'} className="border-b border-blue-500/10 bg-blue-500/5">
                      <td className="py-1 px-1.5 font-medium text-blue-300/80">
                        <span className="inline-flex items-center gap-1">
                          <span className="w-1.5 h-1.5 rounded-full" style={{ background: PROD_COLORS[name] ?? '#666' }} />
                          {name}
                          <span className="text-[6px] px-1 py-0.5 rounded bg-blue-500/20 text-blue-300 font-bold">NEW</span>
                        </span>
                      </td>
                      <td className="py-1 px-1.5 text-blue-400 font-medium">Forecast</td>
                      {allMonthIdx.map(i => {
                        const yr = i < 12 ? 2026 : 2027;
                        const mo = i < 12 ? i + 1 : i - 11;
                        const key = yr * 100 + mo;
                        const val = demandMap[name]?.[key] ?? 0;
                        const currentMonthIdx = MONTHS[0].year === 2026 ? MONTHS[0].month - 1 : MONTHS[0].month + 11;
                        const isPast = i < currentMonthIdx;
                        if (!isPast) fcTotal += val;
                        return <td key={i} className={`text-right py-1 px-1.5 tabular-nums font-medium ${isPast ? 'text-faint/30' : val > 0 ? 'text-blue-300' : 'text-faint/50'}`}>
                          {val > 0 ? fmt(val) : '—'}
                        </td>;
                      })}
                      <td className="text-right py-1 px-1.5 tabular-nums font-medium text-blue-300">
                        {tab === 'units' ? fmt(Math.round(fcTotal)) : '—'}
                      </td>
                    </tr>
                  );
                  return rows;
                });

              // ── TOTAL rows (sum across all variants per month) ──
              const allVariantNames = sortedVariants.map(v => v.name);

              const totalRows: React.ReactElement[] = [];

              // Helper: compute Net ROAS from accumulated rev/cogs/ad
              const computeRoas = (rev: number, cogs: number, ad: number): number | null =>
                ad > 0 ? (rev - cogs) / ad : null;

              // Total Actual
              if (tab !== 'lastYear') {
                let gRev = 0, gCogs = 0, gAd = 0, gSum = 0;
                const monthVals: { val: number | null; isFuture: boolean; hasData: boolean }[] = [];
                for (const i of allMonthIdx) {
                  const isFuture = i >= currentMonth && i < 12;
                  let sumRev = 0, sumCogs = 0, sumAd = 0, sum = 0;
                  let hasData = false;
                  for (const vn of allVariantNames) {
                    const d = i < 12 ? actuals2026Full.get(vn)?.get(i) : undefined;
                    if (d) {
                      hasData = true;
                      sumRev += d.revenue; sumCogs += d.cogs;
                      sumAd += (d as any).adCost ?? (d as any).adSpend ?? 0;
                      if (tab !== 'netRoas') { const v = getVal(d, tab); if (v !== null) sum += v; }
                    }
                  }
                  if (tab === 'netRoas') {
                    monthVals.push({ val: hasData ? computeRoas(sumRev, sumCogs, sumAd) : null, isFuture, hasData });
                  } else {
                    monthVals.push({ val: hasData ? sum : null, isFuture, hasData });
                    if (hasData && !isFuture) gSum += sum;
                  }
                  if (hasData && !isFuture) { gRev += sumRev; gCogs += sumCogs; gAd += sumAd; }
                }
                totalRows.push(
                  <tr key="total-actual" className="border-t-2 border-amber-500/30 bg-amber-500/5 font-bold">
                    <td className="py-1.5 px-1.5 text-amber-300">Total</td>
                    <td className="py-1.5 px-1.5 text-amber-400">Actual</td>
                    {monthVals.map((mv, i) => (
                      <td key={i} className={`text-right py-1.5 px-1.5 tabular-nums ${!mv.hasData || mv.isFuture ? 'text-faint/30' : colorVal(mv.val, false) || 'text-amber-300'}`}>
                        {mv.isFuture ? '·' : mv.val !== null ? fmtVal(mv.val) : '—'}
                      </td>
                    ))}
                    <td className="text-right py-1.5 px-1.5 tabular-nums text-amber-300">
                      {tab === 'netRoas' ? fmtVal(computeRoas(gRev, gCogs, gAd)) : fmtVal(gSum)}
                    </td>
                  </tr>
                );
              }

              // Total Forecast
              if (tab !== 'lastYear') {
                let gRev = 0, gCogs = 0, gAd = 0, gSum = 0;
                const monthVals: { val: number | null; isPast: boolean; hasData: boolean }[] = [];
                const currentMonthIdx = MONTHS[0].year === 2026 ? MONTHS[0].month - 1 : MONTHS[0].month + 11;
                for (const i of allMonthIdx) {
                  const isPast = i < currentMonthIdx;
                  let hasData = false;
                  let val: number | null = null;
                  
                  if (isPast) {
                    const yr = i <= 11 ? 2026 : 2027;
                    const mo = i <= 11 ? i + 1 : i - 11;
                    let pastUnits = 0;
                    for (const v of sortedVariants) pastUnits += (demandMap[v.name]?.[yr * 100 + mo] ?? 0);
                    if (pastUnits > 0) {
                      hasData = true;
                      if (tab === 'units') val = pastUnits;
                      else {
                        let pastRev = 0, pastCogs = 0;
                        for (const v of sortedVariants) {
                          const u = demandMap[v.name]?.[yr * 100 + mo] ?? 0;
                          pastRev += u * v.price;
                          pastCogs += u * v.cogs;
                        }
                        const baseRoas = forecastMap[f.family]?.[mo]?.roas ?? 2.0;
                        const pastAdSpend = baseRoas > 0 ? pastRev / baseRoas : 0;
                        if (tab === 'revenue') val = pastRev;
                        else if (tab === 'adSpend') val = pastAdSpend;
                        else if (tab === 'netProfit') val = pastRev - pastCogs - pastAdSpend;
                        else if (tab === 'netRoas') val = computeRoas(pastRev, pastCogs, pastAdSpend);
                      }
                    }
                  } else {
                    const mIdx = i - currentMonthIdx;
                    const mp = mIdx >= 0 && mIdx < projs.length ? projs[mIdx] : null;
                    const famProj = mp?.families[f.family];
                    if (famProj) {
                      hasData = true;
                      if (tab === 'netRoas') {
                        val = computeRoas(famProj.revenue, famProj.cogs, famProj.adSpend);
                      } else {
                        val = tab === 'units' ? famProj.demand
                          : tab === 'revenue' ? famProj.revenue
                          : tab === 'adSpend' ? famProj.adSpend
                          : tab === 'netProfit' ? famProj.netProfit
                          : famProj.demand;
                      }
                      gRev += famProj.revenue; gCogs += famProj.cogs; gAd += famProj.adSpend;
                      if (tab !== 'netRoas' && val !== null) gSum += val;
                    }
                  }
                  monthVals.push({ val, isPast, hasData });
                }
                totalRows.push(
                  <tr key="total-forecast" className="border-b border-cyan-500/10 bg-cyan-500/5 font-bold">
                    <td className="py-1.5 px-1.5 text-cyan-300">Total</td>
                    <td className="py-1.5 px-1.5 text-cyan-400">Forecast</td>
                    {monthVals.map((mv, i) => (
                      <td key={i} className={`text-right py-1.5 px-1.5 tabular-nums ${mv.isPast ? 'text-faint/30' : !mv.hasData ? 'text-faint/50' : colorVal(mv.val, false) || 'text-cyan-300'}`}>
                        {mv.val !== null ? fmtVal(mv.val) : '—'}
                      </td>
                    ))}
                    <td className="text-right py-1.5 px-1.5 tabular-nums text-cyan-300">
                      {tab === 'netRoas' ? fmtVal(computeRoas(gRev, gCogs, gAd)) : fmtVal(gSum)}
                    </td>
                  </tr>
                );
              }

              // (Legacy "Current path" / "Target path" famEff scenario rows removed —
              //  the spend-scenario decision now lives in the wizard's Ads Path. Totals
              //  shown are Actual = 2026 YTD · Forecast = your plan · 2025 = last year.)

              // Total 2025
              {
                const activeTab = tab === 'lastYear' ? 'units' : tab;
                let gRev = 0, gCogs = 0, gAd = 0, gSum = 0;
                const monthVals: { val: number | null; hasData: boolean }[] = [];
                for (const i of allMonthIdx) {
                  let sumRev = 0, sumCogs = 0, sumAd = 0, sum = 0;
                  let hasData = false;
                  for (const vn of allVariantNames) {
                    const d = i < 12 ? actuals2025Full.get(vn)?.get(i) : undefined;
                    if (d) {
                      hasData = true;
                      sumRev += d.revenue; sumCogs += d.cogs;
                      sumAd += (d as any).adCost ?? (d as any).adSpend ?? 0;
                      if (activeTab !== 'netRoas') { const v = getVal(d, activeTab as typeof tab); if (v !== null) sum += v; }
                    }
                  }
                  if (activeTab === 'netRoas') {
                    monthVals.push({ val: hasData ? computeRoas(sumRev, sumCogs, sumAd) : null, hasData });
                  } else {
                    monthVals.push({ val: hasData ? sum : null, hasData });
                    if (hasData) gSum += sum;
                  }
                  if (hasData) { gRev += sumRev; gCogs += sumCogs; gAd += sumAd; }
                }
                totalRows.push(
                  <tr key="total-2025" className="border-b border-purple-500/10 bg-purple-500/5 font-bold">
                    <td className="py-1.5 px-1.5 text-purple-300">Total</td>
                    <td className="py-1.5 px-1.5 text-purple-400">2025</td>
                    {monthVals.map((mv, i) => (
                      <td key={i} className={`text-right py-1.5 px-1.5 tabular-nums ${!mv.hasData ? 'text-faint/30' : colorVal(mv.val, false) || 'text-purple-300'}`}>
                        {mv.val !== null ? fmtVal(mv.val) : '—'}
                      </td>
                    ))}
                    <td className="text-right py-1.5 px-1.5 tabular-nums text-purple-300">
                      {activeTab === 'netRoas' ? fmtVal(computeRoas(gRev, gCogs, gAd)) : (activeTab === 'units' ? fmt(Math.round(gSum)) : fK(gSum))}
                    </td>
                  </tr>
                );
              }

              return <>{allRows}{newProductRows}{totalRows}</>;
            })()}</tbody>
          </table></div>
        </div>
      </div>
    </td></tr>}
  </>);
}

// ─── Small components ────────────────────────────────────
function DCard({ icon, title, children }: { icon: React.ReactNode; title: string; children: React.ReactNode }) {
  return <div className="rounded-lg border border-border/50 bg-background/50 p-2.5">
    <div className="flex items-center gap-1.5 text-[9px] text-muted uppercase tracking-wide font-medium mb-1.5">{icon} {title}</div>
    {children}
  </div>;
}
function Kpi({ label, value, sub, color, hl, tip, deltaNode }: { label: string; value: string; sub?: string; color?: string; hl?: boolean; tip?: string; deltaNode?: React.ReactNode }) {
  return <div className={`rounded-xl border p-4 ${hl ? 'border-blue-500/40 bg-blue-500/5' : 'border-border bg-surface/50'} relative overflow-hidden`}>
    <div className="text-[10px] text-muted uppercase tracking-wide font-medium flex justify-between pr-8">
      {tip ? <Tip text={tip} multiline>{label} <span className="text-faint text-[9px]">ⓘ</span></Tip> : label}
    </div>
    <div className={`text-xl font-bold mt-1 tabular-nums ${color === 'emerald' ? 'text-emerald-400' : color === 'red' ? 'text-red-400' : color === 'amber' ? 'text-amber-400' : 'text-heading'}`}>{value}</div>
    {sub && <div className="text-[10px] text-faint mt-0.5">{sub}</div>}
    {deltaNode && <div className="absolute top-4 right-4">{deltaNode}</div>}
  </div>;
}

// ─── Plan Summary Section ─────────────────────────────
interface PurchaseItem {
  product: string; asin: string; family: string; stock: number; need: number; gap: number;
  autoQty: number; mfrCost: number; shipCost: number; cartonQty: number; oosMonth: string | null; wave: { label: string; color: string };
}

type CompareMode = 'PLAN_VS_ACTUAL' | 'ORIGINAL_VS_CURRENT' | 'ORIGINAL_VS_ACTUAL';
const COMPARE_LABELS: Record<CompareMode, { label: string; left: string; right: string }> = {
  PLAN_VS_ACTUAL: { label: 'Plan vs Actual', left: 'Plan Qty', right: 'Actual Qty' },
  ORIGINAL_VS_CURRENT: { label: 'Original vs Current', left: 'Original Qty', right: 'Current Qty' },
  ORIGINAL_VS_ACTUAL: { label: 'Original vs Actual', left: 'Original Qty', right: 'Actual Qty' },
};

// Approved Plan vs Reality — per-product UNITS plan (frozen snapshot) vs live daily actuals.
// Columns: Jan'26 (idx 0) → Feb'27 (idx 13). Elapsed months: plan == actual by construction;
// future months: plan only until reality arrives.
// monthKey ("may26") → 0-based 2026 month index (0–11); 2027 → -1 (no monthly actuals yet).
function monthIdxFromKey(k: string): number {
  const m = MONTH_ABBR.indexOf(k.slice(0, 3));
  return k.slice(3) === '26' ? m : -1;
}

function PlanVsRealityPanel({ families, snapshot, actuals2026Full, plannedSpend, plannedCpc, actualsWeekly, planUpdatedAt }: {
  families: FamilyBaseline[];
  snapshot: Record<string, Record<string, number>> | null;
  actuals2026Full: Map<string, Map<number, { units: number; revenue: number; cogs: number; adCost: number }>>;
  plannedSpend: Record<string, Record<string, number>>;
  plannedCpc: Record<string, Record<string, number>>;
  actualsWeekly: Map<string, Map<string, { units: number; revenue: number; cogs: number; adCost: number; clicks: number }>>;
  planUpdatedAt: string | null;
}) {
  const [period, setPeriod] = useState<'week' | 'month' | 'sinceApproval'>('week');
  const [weekBack, setWeekBack] = useState(0);
  const [monthIdx, setMonthIdx] = useState(() => { const n = new Date(); return n.getMonth() + (n.getFullYear() === 2026 ? 0 : 12); });
  const [showGrid, setShowGrid] = useState(false);
  const [gridMode, setGridMode] = useState<'units' | 'spend'>('units');

  const range = useMemo<[string, string]>(() => {
    const iso = (x: Date) => `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
    if (period === 'week') return latestCompleteWeekRange(new Date(), weekBack);
    if (period === 'sinceApproval') return [iso(planUpdatedAt ? new Date(planUpdatedAt) : new Date()), iso(new Date())];
    const y = monthIdx < 12 ? 2026 : 2027, m = (monthIdx % 12) + 1, last = new Date(y, m, 0).getDate();
    const p = (n: number) => String(n).padStart(2, '0');
    return [`${y}-${p(m)}-01`, `${y}-${p(m)}-${p(last)}`];
  }, [period, weekBack, monthIdx, planUpdatedAt]);
  const fractions = useMemo(() => monthFractions(range[0], range[1]), [range]);

  // Per-family plan (prorated over the period) vs actual (real period data), for the 4 measures.
  const scorecard = useMemo(() => families.map(fam => {
    const planUnits = fam.variations.reduce((s, v) => s + sumOverPeriod(snapshot?.[v.name] ?? {}, fractions), 0);
    const planSpend = sumOverPeriod(plannedSpend[fam.family] ?? {}, fractions);
    let cpcNum = 0, cpcDen = 0;
    for (const [k, frac] of Object.entries(fractions)) {
      const sp = (plannedSpend[fam.family]?.[k] ?? 0) * frac, c = plannedCpc[fam.family]?.[k] ?? 0;
      if (sp > 0 && c > 0) { cpcNum += c * sp; cpcDen += sp; }
    }
    const planCpc = cpcDen > 0 ? cpcNum / cpcDen : 0;
    const margin = fam.asp - fam.costPerUnit;
    let units = 0, revenue = 0, cogs = 0, adCost = 0, clicks = 0;
    if (period === 'week') {
      for (const v of fam.variations) { const wm = actualsWeekly.get(v.name); if (!wm) continue; for (const [wk, a] of wm.entries()) if (wk >= range[0] && wk <= range[1]) { units += a.units; revenue += a.revenue; cogs += a.cogs; adCost += a.adCost; clicks += a.clicks; } }
    } else {
      for (const v of fam.variations) { const mm = actuals2026Full.get(v.name); if (!mm) continue; for (const k of Object.keys(fractions)) { const idx = monthIdxFromKey(k); if (idx < 0) continue; const a = mm.get(idx); if (a) { units += a.units; revenue += a.revenue; cogs += a.cogs; adCost += a.adCost; } } }
    }
    return {
      family: fam.family, planned: !!plannedSpend[fam.family],
      adSpend: { plan: planSpend, actual: adCost },
      cpc: { plan: planCpc || null, actual: clicks > 0 ? adCost / clicks : null },
      units: { plan: planUnits, actual: units },
      netProfit: { plan: netProfitPlan(planUnits, margin, planSpend), actual: revenue - cogs - adCost },
    };
  }), [families, snapshot, fractions, plannedSpend, plannedCpc, period, range, actualsWeekly, actuals2026Full]);

  if (!snapshot) return null;

  const cell = (plan: number | null, actual: number | null, fmtFn: (n: number) => string, good: (p: number, a: number) => boolean) => {
    const d = (plan != null && actual != null && plan !== 0) ? (actual - plan) / plan : null;
    const tone = (plan == null || actual == null) ? 'text-muted' : good(plan, actual) ? 'text-emerald-400' : 'text-amber-400';
    return (
      <td className="text-right py-1 px-1.5 tabular-nums">
        <div className="text-faint text-[10px]">{plan == null ? '—' : fmtFn(plan)}</div>
        <div className={`font-semibold ${tone}`}>{actual == null ? '—' : fmtFn(actual)}{d != null && <span className="text-[9px] ml-1 text-faint">{d >= 0 ? '+' : ''}{Math.round(d * 100)}%</span>}</div>
      </td>
    );
  };
  const fmtUnits = (n: number) => fmt(Math.round(n), 0);
  const fmtCpc = (n: number) => '$' + n.toFixed(2);

  // ── by-month detail grid (collapsible) ──
  const monthIdxs = Array.from({ length: 14 }, (_, i) => i);
  const colLabel = (i: number) => i < 12 ? ML[i] + "'26" : ['Jan', 'Feb'][i - 12] + "'27";
  const keyForIdx = (i: number) => MONTHS.find(m => (m.year === 2026 ? m.month - 1 : m.month + 11) === i)?.key;
  const planUnitsGrid = (prod: string, i: number): number | null => { const k = keyForIdx(i); if (k && snapshot[prod]?.[k] != null) return snapshot[prod][k]; if (i <= 11) return actuals2026Full.get(prod)?.get(i)?.units ?? null; return null; };
  const actUnitsGrid = (prod: string, i: number): number | null => i <= 11 ? (actuals2026Full.get(prod)?.get(i)?.units ?? null) : null;
  const planSpendGrid = (fam: string, i: number): number | null => { const k = keyForIdx(i); return k ? (plannedSpend[fam]?.[k] ?? null) : null; };
  const actSpendGrid = (fam: FamilyBaseline, i: number): number | null => { if (i > 11) return null; let s = 0, any = false; for (const v of fam.variations) { const c = actuals2026Full.get(v.name)?.get(i)?.adCost; if (c != null) { s += c; any = true; } } return any ? s : null; };
  const prodRows = families.flatMap(f => [...f.variations].sort((a, b) => a.name.localeCompare(b.name)));

  return (
    <div className="mt-6">
      <div className="flex items-center gap-3 mb-2 flex-wrap">
        <h3 className="text-sm font-bold text-heading">Plan vs Actual</h3>
        <div className="flex gap-1">
          {(['week', 'month', 'sinceApproval'] as const).map(p => (
            <button key={p} onClick={() => setPeriod(p)} className={`px-2 py-0.5 rounded text-[11px] ${period === p ? 'bg-blue-500/20 text-blue-300' : 'text-muted'}`}>{p === 'week' ? 'Week' : p === 'month' ? 'Month' : 'Since approval'}</button>
          ))}
        </div>
        {period === 'week' && <span className="flex items-center gap-1 text-[11px] text-muted"><button onClick={() => setWeekBack(w => w + 1)} className="px-1">‹</button>{range[0]} – {range[1]}<button onClick={() => setWeekBack(w => Math.max(0, w - 1))} className="px-1" disabled={weekBack === 0}>›</button></span>}
        {period === 'month' && <span className="flex items-center gap-1 text-[11px] text-muted"><button onClick={() => setMonthIdx(i => Math.max(0, i - 1))} className="px-1">‹</button>{range[0].slice(0, 7)}<button onClick={() => setMonthIdx(i => Math.min(13, i + 1))} className="px-1">›</button></span>}
        {period === 'sinceApproval' && <span className="text-[11px] text-muted">{range[0]} → today</span>}
        {period !== 'week' && <span className="text-[10px] text-faint">CPC actual: Week tab only</span>}
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-[11px]">
          <thead>
            <tr className="text-muted border-b border-border text-[9px] uppercase tracking-wide">
              <th className="text-left py-1.5 px-1.5">Family</th>
              <th className="text-right py-1.5 px-1.5">Ad Spend</th>
              <th className="text-right py-1.5 px-1.5">CPC</th>
              <th className="text-right py-1.5 px-1.5">Units</th>
              <th className="text-right py-1.5 px-1.5">Net Profit</th>
            </tr>
            <tr className="text-faint text-[8px]"><td></td><td className="text-right px-1.5">plan / actual</td><td className="text-right px-1.5">plan / actual</td><td className="text-right px-1.5">plan / actual</td><td className="text-right px-1.5">plan / actual</td></tr>
          </thead>
          <tbody>
            {scorecard.map(r => (
              <tr key={r.family} className="border-b border-border/20">
                <td className="py-1 px-1.5 font-medium">{r.family}{!r.planned && <span className="ml-1 text-[8px] text-amber-300/80">not planned</span>}</td>
                {cell(r.adSpend.plan, r.adSpend.actual, fK, (p, a) => Math.abs(a - p) <= 0.1 * p)}
                {cell(r.cpc.plan, r.cpc.actual, fmtCpc, (p, a) => a <= p)}
                {cell(r.units.plan, r.units.actual, fmtUnits, (p, a) => a >= p * 0.9)}
                {cell(r.netProfit.plan, r.netProfit.actual, fK, (p, a) => a >= p)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <button onClick={() => setShowGrid(g => !g)} className="mt-3 text-[10px] text-muted hover:text-heading">{showGrid ? '▾' : '▸'} By-month detail</button>
      {showGrid && (
        <div className="mt-1">
          <div className="flex gap-1 mb-1">
            <button onClick={() => setGridMode('units')} className={`px-2 py-0.5 rounded text-[10px] ${gridMode === 'units' ? 'bg-blue-500/20 text-blue-300' : 'text-muted'}`}>Units (per product)</button>
            <button onClick={() => setGridMode('spend')} className={`px-2 py-0.5 rounded text-[10px] ${gridMode === 'spend' ? 'bg-blue-500/20 text-blue-300' : 'text-muted'}`}>Spend (per family)</button>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-[11px]">
              <thead><tr className="text-muted border-b border-border"><th className="text-left py-1.5 px-1.5">{gridMode === 'units' ? 'Product' : 'Family'}</th><th></th>{monthIdxs.map(i => <th key={i} className="text-right py-1.5 px-1.5">{colLabel(i)}</th>)}</tr></thead>
              <tbody>
                {gridMode === 'units' ? prodRows.map(v => {
                  const planRow = monthIdxs.map(i => planUnitsGrid(v.name, i));
                  const actRow = monthIdxs.map(i => actUnitsGrid(v.name, i));
                  return (<Fragment key={v.name}>
                    <tr className="border-b border-border/10"><td className="py-1 px-1.5 font-medium" rowSpan={2}><span className="inline-flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full" style={{ background: PROD_COLORS[v.name] ?? '#666' }} />{v.name}</span></td><td className="py-1 px-1.5 text-blue-400">Plan</td>{planRow.map((u, i) => <td key={i} className="text-right py-1 px-1.5 tabular-nums">{u == null ? '—' : Math.round(u)}</td>)}</tr>
                    <tr className="border-b border-border/20"><td className="py-1 px-1.5 text-emerald-400">Actual</td>{actRow.map((u, i) => { const p = planRow[i]; const cls = u == null || p == null ? '' : u >= p ? 'text-emerald-400' : 'text-red-400'; return <td key={i} className={`text-right py-1 px-1.5 tabular-nums ${cls}`}>{u == null ? '—' : Math.round(u)}</td>; })}</tr>
                  </Fragment>);
                }) : families.map(f => {
                  const planRow = monthIdxs.map(i => planSpendGrid(f.family, i));
                  const actRow = monthIdxs.map(i => actSpendGrid(f, i));
                  return (<Fragment key={f.family}>
                    <tr className="border-b border-border/10"><td className="py-1 px-1.5 font-medium" rowSpan={2}>{f.family}</td><td className="py-1 px-1.5 text-blue-400">Plan</td>{planRow.map((s, i) => <td key={i} className="text-right py-1 px-1.5 tabular-nums">{s == null ? '—' : fK(Math.round(s))}</td>)}</tr>
                    <tr className="border-b border-border/20"><td className="py-1 px-1.5 text-emerald-400">Actual</td>{actRow.map((s, i) => { const p = planRow[i]; const cls = s == null || p == null ? '' : s >= p ? 'text-emerald-400' : 'text-amber-400'; return <td key={i} className={`text-right py-1 px-1.5 tabular-nums ${cls}`}>{s == null ? '—' : fK(Math.round(s))}</td>; })}</tr>
                  </Fragment>);
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

function PurchaseRequestSection({ families, projs, orderOverrides, planId, planStatus, originalOverrides, onOverride, onResetOverrides }: {
  families: FamilyBaseline[]; projs: MonthProj[];
  orderOverrides: Record<string, number>;
  planId: string | null;
  planStatus: 'DRAFT' | 'APPROVED' | null;
  originalOverrides: Record<string, number> | null;
  onOverride: (name: string, qty: number) => void;
  onResetOverrides: () => void;
}) {
  const isApproved = planStatus === 'APPROVED';
  const [compareMode, setCompareMode] = useState<CompareMode>('PLAN_VS_ACTUAL');

  // Sales summary: units sold by ASIN for the year (YTD)
  interface SalesSummaryRow { asin: string; product_name: string; sold: number }
  const [salesSummary, setSalesSummary] = useState<SalesSummaryRow[]>([]);
  useEffect(() => {
    fetch('/api/sales-summary/2026')
      .then(r => r.ok ? r.json() : [])
      .then(d => { if (Array.isArray(d)) setSalesSummary(d); })
      .catch(e => console.error('Failed to load sales summary', e));
  }, []);
  const getSold = useCallback((asin: string, name: string) => {
    const row = salesSummary.find(p => p.asin === asin) || salesSummary.find(p => p.product_name === name);
    return row?.sold ?? 0;
  }, [salesSummary]);

  // Fulfillment data: PO quantities matched by ASIN (for approved plans)
  interface FulfillmentRow { product: string; asin: string; plan_qty: number; ordered_qty: number; remaining: number; pct_complete: number; po_count: number; first_po_date: string | null; last_po_date: string | null }
  const [fulfillment, setFulfillment] = useState<FulfillmentRow[]>([]);
  useEffect(() => {
    if (isApproved && planId) {
      fetch(`/api/plans/${planId}/fulfillment`)
        .then(r => r.ok ? r.json() : [])
        .then(d => { if (Array.isArray(d)) setFulfillment(d); })
        .catch(e => console.error('Failed to load fulfillment', e));
    }
  }, [isApproved, planId]);

  const items = useMemo<PurchaseItem[]>(() => {
    const result: PurchaseItem[] = [];
    for (const f of families) {
      for (const v of f.variations) {
        let forecast = 0;
        for (const p of projs) for (const fd of Object.values(p.families)) forecast += fd.vars[v.name]?.demand ?? 0;
        const sold = getSold(v.asin, v.name);
        const yearlyNeed = sold + forecast; // Actual YTD + Forecast remaining
        const gap = yearlyNeed - sold - v.inventory; // = forecast - stock
        const autoQty = gap > 0 ? Math.ceil(gap / v.cartonQty) * v.cartonQty : 0;
        const oos = getOos(projs, v.name, true);
        result.push({
          product: v.name, asin: v.asin, family: f.family, stock: v.inventory, need: yearlyNeed, gap,
          autoQty, mfrCost: v.mfrCost, shipCost: v.shipCost, cartonQty: v.cartonQty, oosMonth: oos, wave: waveLabel(oos),
        });
      }
    }
    // Sort by wave urgency: W1 first, then W2, then W3
    result.sort((a, b) => {
      const order = (w: string) => w.includes('W1') ? 0 : w.includes('W2') ? 1 : 2;
      return order(a.wave.label) - order(b.wave.label);
    });
    return result;
  }, [families, projs, getSold]);

  // Yearly Planned: snap so GAP FROM PLAN is always divisible by cartonQty (PO READY)
  const getPlanned = useCallback((name: string, item: PurchaseItem) => {
    const raw = orderOverrides[name] ?? item.need;
    const sold = getSold(item.asin, item.product);
    const rawGap = raw - sold - item.stock;
    if (rawGap <= 0 || item.cartonQty <= 1) return raw;
    const snappedGap = Math.ceil(rawGap / item.cartonQty) * item.cartonQty;
    return sold + item.stock + snappedGap;
  }, [orderOverrides, getSold]);
  // Gap from Plan = Planned - Sold - Stock (always divisible by cartonQty)
  const getGapFromPlan = useCallback((name: string, item: PurchaseItem) => {
    const planned = getPlanned(name, item);
    const sold = getSold(item.asin, item.product);
    return planned - sold - item.stock;
  }, [getPlanned, getSold]);
  // Gap from Current = Revised (item.need) - Sold - Stock = Forecast - Stock
  const getGapFromCurrent = useCallback((item: PurchaseItem) => {
    const sold = getSold(item.asin, item.product);
    return item.need - sold - item.stock;
  }, [getSold]);

  const totals = useMemo(() => {
    let totalPlanned = 0, totalRevised = 0, totalGapPlan = 0, totalGapCurrent = 0, totalSold = 0, totalPlanCost = 0;
    for (const item of items) {
      const planned = getPlanned(item.product, item);
      const sold = getSold(item.asin, item.product);
      totalPlanned += planned;
      totalRevised += item.need;
      totalSold += sold;
      totalGapPlan += planned - sold - item.stock;
      totalGapCurrent += item.need - sold - item.stock;
      totalPlanCost += planned * (item.mfrCost + item.shipCost);
    }
    return { totalPlanned, totalRevised, totalGapPlan, totalGapCurrent, totalSold, totalPlanCost };
  }, [items, getPlanned, getSold]);

  const copyToClipboard = useCallback(() => {
    const header = isApproved
      ? 'Product\tFamily\tStock\tPlan Qty\tOrdered\tActual Qty\tDelta\tStatus\tMfr $/u\tShip $/u\tLanded Total\tWave\tOOS'
      : 'Product\tFamily\tYearly Planned\tYearly Remaining\tStock\tYearly Sell Qty\tPO Gap from Plan\tYearly Need Revised\tPO Gap from Current';
    const rows = items.map(item => {
      const planned = getPlanned(item.product, item);
      const sold = getSold(item.asin, item.product);
      const gapPlan = planned - sold - item.stock;
      const gapCurrent = item.need - sold - item.stock;
      if (isApproved) {
        const actualQty = item.autoQty;
        const delta = actualQty - planned;
        const status = Math.abs(delta) > planned * 0.1 ? (delta > 0 ? 'Shortage' : 'Surplus') : 'OK';
        return `${item.product}\t${item.family}\t${item.stock}\t${planned}\t${sold}\t${actualQty}\t${delta > 0 ? '+' : ''}${delta}\t${status}\t$${item.mfrCost.toFixed(2)}\t$${item.shipCost.toFixed(2)}\t$${(planned * (item.mfrCost + item.shipCost)).toFixed(2)}\t${item.wave.label}\t${item.oosMonth ?? 'OK'}`;
      }
      return `${item.product}\t${item.family}\t${planned}\t${planned - sold}\t${item.stock}\t${sold}\t${gapPlan}\t${item.need}\t${gapCurrent}`;
    });
    navigator.clipboard.writeText([header, ...rows].join('\n'));
  }, [items, getPlanned, getSold, isApproved]);

  const downloadCsv = useCallback(() => {
    const header = isApproved
      ? 'Product,Family,Stock,Plan Qty,YTD Sold,Actual Qty,Delta,Status,Mfr $/u,Ship $/u,Landed Total,Wave,OOS'
      : 'Product,Family,Yearly Planned,Yearly Remaining,Stock,YTD Sold,PO Gap from Plan,Cartons,Yearly Need Revised,PO Gap from Current,Mfr $/u,Ship $/u,Landed $,OOS';
    const rows = items.map(item => {
      const planned = getPlanned(item.product, item);
      const sold = getSold(item.asin, item.product);
      const gapPlan = planned - sold - item.stock;
      const gapCurrent = item.need - sold - item.stock;
      if (isApproved) {
        const actualQty = item.autoQty;
        const delta = actualQty - planned;
        const status = Math.abs(delta) > planned * 0.1 ? (delta > 0 ? 'Shortage' : 'Surplus') : 'OK';
        return `${item.product},${item.family},${item.stock},${planned},${sold},${actualQty},${delta},${status},$${item.mfrCost.toFixed(2)},$${item.shipCost.toFixed(2)},$${(planned * (item.mfrCost + item.shipCost)).toFixed(2)},${item.wave.label},${item.oosMonth ?? 'OK'}`;
      }
      const cartons = gapPlan > 0 && item.cartonQty > 1 ? `${Math.ceil(gapPlan / item.cartonQty)} ct @ ${item.cartonQty}/box` : '';
      return `${item.product},${item.family},${planned},${planned - sold},${item.stock},${sold},${gapPlan > 0 ? gapPlan : 'OK'},${cartons},${item.need},${gapCurrent > 0 ? gapCurrent : 'OK'},$${item.mfrCost.toFixed(2)},$${item.shipCost.toFixed(2)},$${(gapCurrent > 0 ? gapCurrent * (item.mfrCost + item.shipCost) : 0).toFixed(0)},${item.oosMonth ?? 'OK'}`;
    });
    const csv = [header, ...rows].join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `OI_Plan_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }, [items, getPlanned, getSold, isApproved]);

  // Get left/right values based on comparison mode
  const getCompareValues = useCallback((product: string, autoQty: number): { left: number; right: number } => {
    const planQty = orderOverrides[product] ?? autoQty;
    const origQty = originalOverrides?.[product] ?? planQty;
    const actualQty = autoQty; // live-computed from simulation
    switch (compareMode) {
      case 'PLAN_VS_ACTUAL': return { left: planQty, right: actualQty };
      case 'ORIGINAL_VS_CURRENT': return { left: origQty, right: planQty };
      case 'ORIGINAL_VS_ACTUAL': return { left: origQty, right: actualQty };
    }
  }, [compareMode, orderOverrides, originalOverrides]);

  if (items.length === 0) {
    return (
      <Section title="Plan Summary">
        <div className="flex flex-col flex-1 items-center justify-center text-center p-8 border border-border/20 rounded bg-white/[0.02]">
          <CheckCircle className="text-emerald-500/50 mb-3" size={32} />
          <h3 className="text-sm font-medium text-emerald-400 mb-1">Stock Levels Healthy!</h3>
          <p className="text-[10px] text-muted max-w-xs">
            Based on your running simulation, current inventory exceeds projected demand and no new purchase orders are actively recommended.
          </p>
        </div>
      </Section>
    );
  }

  const cmLabels = COMPARE_LABELS[compareMode];

  return (
    <Section title="Plan Summary">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          {isApproved && (
            <span className="inline-flex items-center gap-1 text-[9px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-300 border border-emerald-500/30">
              <Lock size={9} /> Approved Plan
            </span>
          )}
          <p className="text-[10px] text-muted">
            {isApproved ? 'Monitoring mode — comparing approved plan to live data.' : 'Products below need restocking based on simulation. Edit to adjust.'}
          </p>
        </div>
        <div className="flex items-center gap-2">

          {!isApproved && (
            <button onClick={onResetOverrides} className="inline-flex items-center gap-1 text-[9px] text-muted hover:text-heading px-2 py-1 rounded border border-border/50 hover:border-border transition-colors">
              <RotateCcw size={10} /> Reset
            </button>
          )}
          <button onClick={copyToClipboard} className="inline-flex items-center gap-1 text-[9px] text-blue-400 hover:text-blue-300 px-2 py-1 rounded border border-blue-500/30 hover:border-blue-500/50 transition-colors">
            <ClipboardCopy size={10} /> Copy
          </button>
          <button onClick={downloadCsv} className="inline-flex items-center gap-1 text-[9px] text-blue-400 hover:text-blue-300 px-2 py-1 rounded border border-blue-500/30 hover:border-blue-500/50 transition-colors">
            <Download size={10} /> Export
          </button>
          {!isApproved && (
            <button className="inline-flex items-center gap-1 text-[9px] text-emerald-400 hover:text-emerald-300 px-2.5 py-1.5 rounded border border-emerald-500/30 hover:border-emerald-500/50 bg-emerald-500/10 transition-colors font-medium">
              <FileText size={10} /> Create PO
            </button>
          )}
        </div>
      </div>
      <table className="w-full text-[11px]">
        <thead><tr className="text-muted text-[9px] uppercase tracking-wide border-b border-border">
          <th className="text-left py-2 px-2"><Tip text="Product variant name from DIM_PRODUCT">Product <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          {/* Base planning columns — shared by both views */}
          <th className="text-right py-2 px-2 w-24"><Tip text="Total units planned for the year\n= Simulated demand across all months\nRounded up to exact multiples of carton qty (units per box)">{isApproved ? 'Yearly Planned' : 'Yearly Planned'} <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          <th className="text-right py-2 px-2 w-24"><Tip text="Remaining units to fulfill\n= Yearly Planned − YTD Sold">Yearly Remaining <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          <th className="text-right py-2 px-2 w-20"><Tip text="Current total inventory\n= FBA + AWD + In Transit + Manufacturer\nIncludes units currently in transit to Amazon">Stock <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          <th className="text-right py-2 px-2 w-24"><Tip text="Units already sold year-to-date\nSource: Amazon orders data">YTD Sell Qty <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          <th className="text-right py-2 px-2 w-24"><Tip text="Shortfall from yearly plan\n= Yearly Planned − Yearly Sell Qty − Stock\nPositive (red) = need to order\nNegative (green) = on track">PO Gap from Plan <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          <th className="text-right py-2 px-2 w-24"><Tip text="Total yearly demand estimate\n= YTD Sold + Remaining Forecast\nUpdated with latest sales and simulation">Yearly Need Revised <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          <th className="text-right py-2 px-2 w-24"><Tip text="Units to order after accounting for sold and stock\n= Yearly Need Revised − YTD Sold − Stock\n= Remaining Forecast − Stock\nPositive = must order, Negative = surplus">PO Gap from Current <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          {/* Approved-only: Ordered column */}
          {isApproved && (
            <th className="text-right py-2 px-2 w-16"><Tip text="Units already ordered via Purchase Orders\nSum of all PO quantities for this product">Ordered <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          )}
          {/* Common cost columns for both views */}
          <th className="text-right py-2 px-2 w-16"><Tip text="Manufacturer cost per unit\nFrom DIM_PRODUCT.manufacturer_cost">Mfr $/u <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          <th className="text-right py-2 px-2 w-16"><Tip text="Shipping cost per unit\nFrom DIM_PRODUCT.shipping_cost">Ship $/u <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          <th className="text-right py-2 px-2 w-20"><Tip text="Total landed cost\n= (Mfr $/u + Ship $/u) × Gap from Current\nCost to fulfill remaining gap">Landed $ <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
          <th className="text-center py-2 px-2 w-14"><Tip text="First month stock runs out\nBased on simulated demand vs current inventory\nRed = within 2 months, Amber = 3-5 months">OOS <span className="text-faint text-[9px]">ⓘ</span></Tip></th>
        </tr></thead>
        <tbody>
          {Object.entries(items.reduce((acc, item) => {
            if (!acc[item.family]) acc[item.family] = [];
            acc[item.family].push(item);
            return acc;
          }, {} as Record<string, typeof items>))
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([family, famItems]) => (
              <Fragment key={family}>
                <tr className="bg-surface border-y border-border/20">
                  <td colSpan={isApproved ? 13 : 13} className="py-2 px-2 uppercase text-[10px] tracking-wider text-muted font-bold">
                    {family}
                  </td>
                </tr>
                {famItems.map(item => {
                  const planned = getPlanned(item.product, item);
                  const sold = getSold(item.asin, item.product);
                  const gapFromPlan = planned - sold - item.stock;
                  const gapFromCurrent = item.need - sold - item.stock; // = forecast - stock

                  if (isApproved) {
                    const ff = fulfillment.find(f => f.product === item.product);
                    const ordered = ff?.ordered_qty ?? 0;
                    return (
                      <tr key={item.product} className="border-b border-border/20 hover:bg-white/[.02]">
                        <td className="py-2 px-2 font-medium">
                          <span className="inline-flex items-center gap-1.5">
                            <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: PROD_COLORS[item.product] ?? '#666' }} />
                            {item.product}
                          </span>
                        </td>
                        {/* Planning columns */}
                        <td className="text-right py-2 px-2 tabular-nums font-medium">{fmt(planned)}</td>
                        <td className="text-right py-2 px-2 tabular-nums font-medium" style={{ color: '#06b6d4' }}>{fmt(planned - sold)}</td>
                        <td className="text-right py-2 px-2 tabular-nums text-muted">{fmt(item.stock)}</td>
                        <td className="text-right py-2 px-2 tabular-nums text-muted">{sold > 0 ? fmt(sold) : '—'}</td>
                        <td className={`text-right py-2 px-2 tabular-nums font-bold ${gapFromPlan > 0 ? 'text-red-400' : 'text-emerald-400'}`}>
                          {gapFromPlan > 0 ? fmt(gapFromPlan) : '✓ OK'}
                        </td>
                        <td className="text-right py-2 px-2 tabular-nums text-muted">{fmt(item.need)}</td>
                        <td className={`text-right py-2 px-2 tabular-nums font-bold ${gapFromCurrent > 0 ? 'text-amber-400' : 'text-emerald-400'}`}>
                          {gapFromCurrent > 0 ? fmt(gapFromCurrent) : '✓ OK'}
                        </td>
                        {/* Ordered column */}
                        <td className="text-right py-2 px-2 tabular-nums text-muted">{fmt(ordered)}</td>
                        {/* Cost columns */}
                        <td className="text-right py-2 px-2 tabular-nums text-muted">${item.mfrCost.toFixed(2)}</td>
                        <td className="text-right py-2 px-2 tabular-nums text-muted">${item.shipCost.toFixed(2)}</td>
                        <td className="text-right py-2 px-2 tabular-nums font-bold">{fK(planned * (item.mfrCost + item.shipCost))}</td>
                        <td className="text-center py-2 px-2">
                          {item.oosMonth ? <span className="text-[9px] font-bold text-red-400">{item.oosMonth}</span> : <span className="text-[9px] text-emerald-400">OK</span>}
                        </td>
                      </tr>
                    );
                  }

                  // DRAFT / no plan: editable mode — Yearly Planned is editable
                  const isOverridden = item.product in orderOverrides;
                  return (
                    <tr key={item.product} className="border-b border-border/20 hover:bg-white/[.02]">
                      <td className="py-2 px-2 font-medium">
                        <span className="inline-flex items-center gap-1.5">
                          <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: PROD_COLORS[item.product] ?? '#666' }} />
                          {item.product}
                        </span>
                      </td>
                      <td className="text-right py-2 px-2">
                        <input
                          type="number"
                          value={planned}
                          min={0}
                          onChange={e => {
                            const val = e.target.value === '' ? 0 : parseInt(e.target.value) || 0;
                            onOverride(item.product, val);
                          }}
                          onBlur={e => {
                            const val = Math.max(0, parseInt(e.target.value) || 0);
                            onOverride(item.product, val);
                          }}
                          onKeyDown={e => { if (e.key === 'Enter') e.currentTarget.blur(); }}
                          className={`w-24 text-right tabular-nums bg-transparent border rounded px-1.5 py-0.5 text-[11px] font-mono focus:outline-none focus:ring-1 focus:ring-blue-500/50 ${isOverridden ? 'border-blue-500/50 text-blue-300' : 'border-border/50 text-heading'}`}
                        />
                      </td>
                      <td className="text-right py-2 px-2 tabular-nums font-medium" style={{ color: '#06b6d4' }}>{fmt(planned - sold)}</td>
                      <td className="text-right py-2 px-2 tabular-nums text-muted">{fmt(item.stock)}</td>
                      <td className="text-right py-2 px-2 tabular-nums text-muted">{sold > 0 ? fmt(sold) : '—'}</td>
                      <td className={`text-right py-2 px-2 tabular-nums font-bold ${gapFromPlan > 0 ? 'text-red-400' : 'text-emerald-400'}`}>
                        {gapFromPlan > 0 ? fmt(gapFromPlan) : '✓ OK'}
                        {gapFromPlan > 0 && item.cartonQty > 1 && <div className="text-[8px] text-muted font-normal mt-0.5 whitespace-nowrap">{Math.ceil(gapFromPlan / item.cartonQty)} ct @ {item.cartonQty}/box</div>}
                      </td>
                      <td className="text-right py-2 px-2 tabular-nums text-muted">{fmt(item.need)}</td>
                      <td className={`text-right py-2 px-2 tabular-nums font-bold ${gapFromCurrent > 0 ? 'text-amber-400' : 'text-emerald-400'}`}>
                        {gapFromCurrent > 0 ? fmt(gapFromCurrent) : '✓ OK'}
                      </td>
                      <td className="text-right py-2 px-2 tabular-nums text-muted">${item.mfrCost.toFixed(2)}</td>
                      <td className="text-right py-2 px-2 tabular-nums text-muted">${item.shipCost.toFixed(2)}</td>
                      <td className="text-right py-2 px-2 tabular-nums font-bold">{fK(planned * (item.mfrCost + item.shipCost))}</td>
                      <td className="text-center py-2 px-2">
                        {item.oosMonth ? <span className="text-[9px] font-bold text-red-400">{item.oosMonth}</span> : <span className="text-[9px] text-emerald-400">OK</span>}
                      </td>
                    </tr>
                  );
                })}
              </Fragment>
            ))
          }
        </tbody>
        <tfoot>
          <tr className="border-t-2 border-border font-bold">
            {isApproved ? (
              <>
                <td className="py-2.5 px-2 text-heading" colSpan={2}>TOTAL</td>
                {/* Base planning totals */}
                <td className="text-right py-2.5 px-2 tabular-nums text-heading">{fmt(totals.totalPlanned)}</td>
                <td></td>
                <td className="text-right py-2.5 px-2 tabular-nums text-muted">{fmt(totals.totalSold)}</td>
                <td className={`text-right py-2.5 px-2 tabular-nums font-bold ${totals.totalGapPlan > 0 ? 'text-red-400' : 'text-emerald-400'}`}>{totals.totalGapPlan > 0 ? fmt(totals.totalGapPlan) : '✓ OK'}</td>
                <td className="text-right py-2.5 px-2 tabular-nums text-muted">{fmt(totals.totalRevised)}</td>
                <td className={`text-right py-2.5 px-2 tabular-nums font-bold ${totals.totalGapCurrent > 0 ? 'text-amber-400' : 'text-emerald-400'}`}>{totals.totalGapCurrent > 0 ? fmt(totals.totalGapCurrent) : '✓ OK'}</td>
                {/* Ordered total */}
                <td className="text-right py-2.5 px-2 tabular-nums text-muted">{fmt(fulfillment.reduce((s, f) => s + f.ordered_qty, 0))}</td>
                {/* Cost totals */}
                <td colSpan={2}></td>
                <td className="text-right py-2.5 px-2 tabular-nums text-heading text-lg">{fK(totals.totalPlanCost)}</td>
                <td></td>
              </>
            ) : (
              <>
                <td className="py-2.5 px-2 text-heading" colSpan={2}>TOTAL</td>
                <td className="text-right py-2.5 px-2 tabular-nums text-heading">{fmt(totals.totalPlanned)}</td>
                <td></td>
                <td className="text-right py-2.5 px-2 tabular-nums text-muted">{fmt(totals.totalSold)}</td>
                <td className={`text-right py-2.5 px-2 tabular-nums font-bold ${totals.totalGapPlan > 0 ? 'text-red-400' : 'text-emerald-400'}`}>{totals.totalGapPlan > 0 ? fmt(totals.totalGapPlan) : '✓ OK'}</td>
                <td className="text-right py-2.5 px-2 tabular-nums text-muted">{fmt(totals.totalRevised)}</td>
                <td className={`text-right py-2.5 px-2 tabular-nums font-bold ${totals.totalGapCurrent > 0 ? 'text-amber-400' : 'text-emerald-400'}`}>{totals.totalGapCurrent > 0 ? fmt(totals.totalGapCurrent) : '✓ OK'}</td>
                <td colSpan={2}></td>
                <td className="text-right py-2.5 px-2 tabular-nums text-heading text-lg">{fK(totals.totalPlanCost)}</td>
                <td></td>
              </>
            )}
          </tr>
        </tfoot>
      </table>
    </Section>
  );
}

// ─── Cashflow Section ─────────────────────────────────────
interface CashflowActuals {
  amazon: Record<string, { sales: number; units: number; ad_cost: number }>;
  manufacturer: Record<string, number>;
  deliverer: Record<string, number>;
  po_unpaid: Record<string, number>;
  ship_unpaid: Record<string, number>;
  po_detail?: Record<string, { po: string; product: string; mfr: number; ship: number; qty: number }[]>;
  amazon_by_product?: Record<string, { product: string; sales: number; units: number; ad_cost: number }[]>;
}

type CashflowViewMode = 'regular' | 'cumulative' | 'peak';

const CF_MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function CashflowSection({ projs, families, planId }: {
  projs: MonthProj[];
  families: FamilyBaseline[];
  planId: string | null;
}) {
  const [actuals, setActuals] = useState<CashflowActuals | null>(null);
  const [viewMode, setViewMode] = useState<CashflowViewMode>('regular');
  const { suggestions } = useShipmentPlan();
  const { scheduled } = useScheduledShipments();

  useEffect(() => {
    fetch('/api/cashflow-actuals/2026')
      .then(r => r.json()).then(d => setActuals(d)).catch(() => {});
  }, []);

  const currentMonth = new Date().getMonth() + 1;

  // Average FBA fee rate from families
  const avgFbaFeeRate = useMemo(() => {
    let tu = 0, tf = 0;
    for (const f of families) for (const v of f.variations) {
      const fba = v.costPerUnit - v.mfrCost - v.shipCost;
      if (fba > 0 && v.dailyOrders > 0) { tu += v.dailyOrders; tf += v.dailyOrders * fba; }
    }
    return tu > 0 ? tf / tu : 0;
  }, [families]);

  // Build rows
  const rows = useMemo(() => {
    if (!actuals) return [];

    // Group shipment plan costs by month
    const shipMfrByMonth: Record<number, number> = {};
    const shipDelivByMonth: Record<number, number> = {};
    const upfrontPct: Record<string, number> = {};
    const costMap: Record<string, { mfr: number; ship: number }> = {};
    
    for (const f of families) for (const v of f.variations) {
      upfrontPct[v.name] = v.name.toLowerCase().includes('lollime') ? 0.4 : 0.3;
      costMap[v.name] = { mfr: v.mfrCost, ship: v.shipCost };
    }

    const combinedShips = [...scheduled, ...suggestions];

    // Group shipment plan by month:
    // MFR cost (remaining after upfront) → paid on ship_date month
    // SHIP cost → paid month AFTER ship_date
    for (const s of combinedShips) {
      const shipDate = s.ship_wednesday || s.amazon_plan_date || new Date().toISOString().split('T')[0];
      const sm = new Date(shipDate).getMonth() + 1;
      const nm = sm === 12 ? 1 : sm + 1;
      const pct = upfrontPct[s.product] ?? 0.3;
      const mfrTot = (s.ship_qty || 0) * (costMap[s.product]?.mfr || 0);
      const shipTot = (s.ship_qty || 0) * (costMap[s.product]?.ship || 0);

      shipMfrByMonth[sm] = (shipMfrByMonth[sm] || 0) + mfrTot * (1 - pct);
      shipDelivByMonth[nm] = (shipDelivByMonth[nm] || 0) + shipTot;
    }

    const hasShipPlan = combinedShips.length > 0;



    const result = [];
    for (let m = 1; m <= 12; m++) {
      const isPast = m < currentMonth;
      const isCurr = m === currentMonth;
      const amz = actuals.amazon[String(m)] || { sales: 0, units: 0, ad_cost: 0 };
      const prevKey = m === 1 ? '0' : String(m - 1);
      const prev = actuals.amazon[prevKey] || { sales: 0, units: 0, ad_cost: 0 };

      const proj = projs.find(p => { const mi = MONTHS.findIndex(mm => mm.key === p.key); return mi >= 0 && MONTHS[mi].month === m && MONTHS[mi].year === 2026; });
      const prevProj = projs.find(p => { const mi = MONTHS.findIndex(mm => mm.key === p.key); return mi >= 0 && MONTHS[mi].month === (m === 1 ? 12 : m - 1) && MONTHS[mi].year === (m === 1 ? 2025 : 2026); });

      // (AWD→FBA handled by Amazon automatically — no fee tracking needed)

      // Amazon Payment — bi-weekly settlement model:
      // Amazon pays every ~2 weeks, so month M receives roughly:
      //   0.5 × net(M-1) + 0.5 × net(M)
      // where net = sales - amazon_fees - ad_cost
      const prevNetAct = prev.sales - prev.ad_cost - (prev.units * avgFbaFeeRate);
      const curNetAct = amz.sales - amz.ad_cost - (amz.units * avgFbaFeeRate);
      const actAmazon = (isPast || isCurr) ? 0.5 * prevNetAct + 0.5 * curNetAct : 0;

      const prevRevFcst = prevProj ? prevProj.totalRevenue : prev.sales;
      const prevDemFcst = prevProj ? prevProj.totalDemand : prev.units;
      const prevAdFcst = prevProj ? prevProj.totalAdSpend : prev.ad_cost;
      const curRevFcst = proj ? proj.totalRevenue : amz.sales;
      const curDemFcst = proj ? proj.totalDemand : amz.units;
      const curAdFcst = proj ? proj.totalAdSpend : amz.ad_cost;
      const prevNetFcst = prevRevFcst - prevAdFcst - (prevDemFcst * avgFbaFeeRate);
      const curNetFcst = curRevFcst - curAdFcst - (curDemFcst * avgFbaFeeRate);
      const fcstAmazon = (!isPast && !isCurr && proj)
        ? 0.5 * prevNetFcst + 0.5 * curNetFcst
        : 0;

      const actMfr = (isPast || isCurr) ? (actuals.manufacturer[String(m)] || 0) : 0;
      const actShip = (isPast || isCurr) ? (actuals.deliverer[String(m)] || 0) : 0;

      // Forecast outflow: split into Planned (real unpaid POs) vs Forecast (shipment plan or sim)
      let plannedMfr = 0, plannedShip = 0;
      let fcstMfr = 0, fcstShip = 0;
      let fcstSrc = 'none';
      if (!isPast) {
        // Planned: real unpaid PO/shipment amounts (known liabilities)
        const poUnpaid = actuals.po_unpaid?.[String(m)] || 0;
        const shipUnpaid = actuals.ship_unpaid?.[String(m)] || 0;
        if (poUnpaid > 0 || shipUnpaid > 0) {
          plannedMfr = poUnpaid;
          plannedShip = shipUnpaid;
        }
        // Forecast: from shipment plan (future orders with known ship dates)
        if (hasShipPlan) {
          const spMfr = shipMfrByMonth[m] || 0;
          const spShip = shipDelivByMonth[m] || 0;
          // Only add forecast if it exceeds planned (avoid double-counting)
          fcstMfr = Math.max(0, spMfr - plannedMfr);
          fcstShip = Math.max(0, spShip - plannedShip);
          if (fcstMfr > 0 || fcstShip > 0) fcstSrc = 'shipment plan';
        }
      }

      const actIn = actAmazon;
      const fcstIn = fcstAmazon;
      const totIn = actIn + fcstIn;
      const actOut = actMfr + actShip;
      const plannedOut = plannedMfr + plannedShip;
      const fcstOut = fcstMfr + fcstShip;
      const totOut = actOut + plannedOut + fcstOut;
      const net = totIn - totOut;

      result.push({
        month: m, label: CF_MONTH_LABELS[m - 1], isPast, isCurr,
        actIn, fcstIn, totIn,
        actOut, plannedOut, fcstOut, totOut, net,
        bd: {
          prevSales: isPast || isCurr ? prev.sales : prevRevFcst,
          curSales: isPast || isCurr ? amz.sales : curRevFcst,
          prevAdSpend: isPast || isCurr ? prev.ad_cost : prevAdFcst,
          curAdSpend: isPast || isCurr ? amz.ad_cost : curAdFcst,
          prevUnits: isPast || isCurr ? prev.units : prevDemFcst,
          curUnits: isPast || isCurr ? amz.units : curDemFcst,
          fbaRate: avgFbaFeeRate,
          amzFees: ((isPast || isCurr ? prev.units : prevDemFcst) + (isPast || isCurr ? amz.units : curDemFcst)) * 0.5 * avgFbaFeeRate,

          mfrAct: actuals.manufacturer[String(m)] || 0,
          mfrPlanned: plannedMfr,
          mfrFcst: fcstMfr,
          shipAct: actuals.deliverer[String(m)] || 0,
          shipPlanned: plannedShip,
          shipFcst: fcstShip,
          src: fcstSrc,
          // Granular detail for tooltips
          poLines: actuals.po_detail?.[String(m)] ?? [],
          shipLines: combinedShips.filter(s => {
            const shipDate = s.ship_wednesday || s.amazon_plan_date || new Date().toISOString().split('T')[0];
            const sm = new Date(shipDate).getMonth() + 1;
            const nm = sm === 12 ? 1 : sm + 1;
            return sm === m || nm === m; // ship cost shows in next month
          }).map(s => {
            const shipDate = s.ship_wednesday || s.amazon_plan_date || new Date().toISOString().split('T')[0];
            const sm = new Date(shipDate).getMonth() + 1;
            const pct = upfrontPct[s.product] ?? 0.3;
            const mfrC = costMap[s.product]?.mfr || 0;
            const shipC = costMap[s.product]?.ship || 0;
            const est_mfr_cost = (s.ship_qty || 0) * mfrC;
            const est_ship_cost = (s.ship_qty || 0) * shipC;
            const isSugg = !('status' in s) || s.status === 'SUGGESTED';
            return {
              product: s.product,
              qty: s.ship_qty,
              mfr: sm === m ? est_mfr_cost * (1 - pct) : 0,
              ship: (sm === 12 ? 1 : sm + 1) === m ? est_ship_cost : 0,
              route: s.route || 'SEA',
              date: shipDate,
              status: isSugg ? 'PO NEEDED' : s.status,
            };
          }).filter(s => s.mfr > 0 || s.ship > 0),
          salesByProduct: actuals.amazon_by_product?.[String(m)] ?? [],
          fcstByProduct: proj ? Object.entries(proj.families).flatMap(([, fam]) =>
            Object.entries(fam.vars).map(([name, v]) => ({
              product: name, units: Math.round(v.demand), sales: v.revenue, ad_cost: v.adSpend,
            }))
          ).filter(p => p.units > 0).sort((a, b) => b.sales - a.sales) : [],
        },
      });
    }
    return result;
  }, [actuals, projs, scheduled, suggestions, families, avgFbaFeeRate, currentMonth]);

  // Apply view mode
  const displayRows = useMemo(() => {
    if (viewMode === 'regular') return rows;
    if (viewMode === 'cumulative') {
      let sIn = 0, sOut = 0;
      return rows.map(r => { sIn += r.totIn; sOut += r.totOut; return { ...r, totIn: sIn, totOut: sOut, net: sIn - sOut }; });
    }
    const maxOut = Math.max(...rows.map(r => r.totOut));
    return rows.map(r => ({ ...r, isPeak: r.totOut === maxOut && maxOut > 0 }));
  }, [rows, viewMode]);

  const totals = useMemo(() => rows.reduce((a, r) => ({
    actIn: a.actIn + r.actIn, fcstIn: a.fcstIn + r.fcstIn, totIn: a.totIn + r.totIn,
    actOut: a.actOut + r.actOut, plannedOut: a.plannedOut + r.plannedOut, fcstOut: a.fcstOut + r.fcstOut, totOut: a.totOut + r.totOut,
    net: a.net + r.net,
  }), { actIn: 0, fcstIn: 0, totIn: 0, actOut: 0, plannedOut: 0, fcstOut: 0, totOut: 0, net: 0 }), [rows]);

  if (!actuals) return null;

  const tipIn = (r: typeof rows[0]) => {
    let tip = `Amazon Payment — Bi-weekly settlement\n` +
      `50% Prev Month: ${fK(0.5 * (r.bd.prevSales - r.bd.prevAdSpend - r.bd.prevUnits * r.bd.fbaRate))}\n` +
      `  Sales ${fK(r.bd.prevSales)} − Ads ${fK(r.bd.prevAdSpend)} − Fees ${fK(r.bd.prevUnits * r.bd.fbaRate)}\n` +
      `50% Cur Month: ${fK(0.5 * ((r.bd.curSales ?? 0) - r.bd.curAdSpend - (r.bd.curUnits ?? 0) * r.bd.fbaRate))}\n` +
      `  Sales ${fK(r.bd.curSales ?? 0)} − Ads ${fK(r.bd.curAdSpend)} − Fees ${fK((r.bd.curUnits ?? 0) * r.bd.fbaRate)}`;

    // Per-product breakdown: actuals for past months, forecast for future
    const products = r.bd.salesByProduct.length > 0 ? r.bd.salesByProduct : r.bd.fcstByProduct;
    const label = r.bd.salesByProduct.length > 0 ? 'Actual' : 'Forecast';
    if (products.length > 0) {
      tip += `\n───── Per Product (${label}) ─────`;
      for (const p of products) {
        const net = p.sales - p.ad_cost;
        tip += `\n${p.product}: ${p.units} units · Sales ${fK(p.sales)} · Ads ${fK(p.ad_cost)} · Net ${fK(net)}`;
      }
    }
    return tip;
  };

  const tipOutPlanned = (r: typeof rows[0]) => {
    let tip = `Planned Outflow — Unpaid POs (est. payment month)\nManufacturer: ${fK(r.bd.mfrPlanned)}\nShipping: ${fK(r.bd.shipPlanned)}`;
    if (r.bd.poLines.length > 0) {
      tip += '\n─────────────────────';
      for (const p of r.bd.poLines) {
        const label = p.product || p.po;
        tip += `\n${label}: ${p.qty} units`;
        if (p.mfr > 0) tip += ` · Mfr $${Math.round(p.mfr).toLocaleString()}`;
        if (p.ship > 0) tip += ` · Ship $${Math.round(p.ship).toLocaleString()}`;
      }
    }
    return tip;
  };

  const tipOutAct = (r: typeof rows[0]) =>
    `Actual Outflow (paid)\nManufacturer: ${fK(r.bd.mfrAct)}\nDeliverer: ${fK(r.bd.shipAct)}`;

  const tipOutFcst = (r: typeof rows[0]) => {
    let tip = `Forecast Outflow (${r.bd.src})\nManufacturer: ${fK(r.bd.mfrFcst)}\nShipping: ${fK(r.bd.shipFcst)}`;
    if (r.bd.shipLines.length > 0) {
      tip += '\n─────────────────────';
      for (const s of r.bd.shipLines) {
        tip += `\n${s.product} (${s.route}) · ${s.qty} units`;
        if (s.mfr > 0) tip += ` · Mfr $${Math.round(s.mfr).toLocaleString()}`;
        if (s.ship > 0) tip += ` · Ship $${Math.round(s.ship).toLocaleString()}`;
        tip += ` · ${s.date}`;
      }
    }
    return tip;
  };

  return (
    <Section title="Yearly Cashflow">
      <div className="flex items-center gap-2 mb-3">
        {(['regular', 'cumulative', 'peak'] as const).map(mode => (
          <button key={mode} onClick={() => setViewMode(mode)}
            className={`px-3 py-1 text-[10px] rounded-full border transition-all ${viewMode === mode ? 'bg-blue-500/20 border-blue-500/50 text-blue-300' : 'border-border/30 text-muted hover:text-heading hover:border-border/60'}`}>
            {mode.charAt(0).toUpperCase() + mode.slice(1)}
          </button>
        ))}
      </div>
      <table className="w-full text-[10px]">
        <thead>
          <tr className="text-muted border-b border-border">
            <th className="text-left py-2 px-2 w-14">Month</th>
            <th className="text-right py-2 px-2 text-emerald-400/80" colSpan={3}>↓ Inflow (Amazon Payment)</th>
            <th className="text-right py-2 px-2 text-red-400/80" colSpan={4}>↑ Outflow (Mfr + Shipping)</th>
            <th className="text-right py-2 px-2 w-24">Net</th>
          </tr>
          <tr className="text-muted/50 border-b border-border/30 text-[8px]">
            <th></th>
            <th className="text-right py-1 px-2">Actual</th>
            <th className="text-right py-1 px-2">Forecast</th>
            <th className="text-right py-1 px-2 border-r border-border/20">Total</th>
            <th className="text-right py-1 px-2">Actual</th>
            <th className="text-right py-1 px-2"><Tip text="Real unpaid POs and shipments">Planned <span className="text-faint">ⓘ</span></Tip></th>
            <th className="text-right py-1 px-2"><Tip text="From shipment plan simulation">Forecast <span className="text-faint">ⓘ</span></Tip></th>
            <th className="text-right py-1 px-2">Total</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {displayRows.map(r => (
            <tr key={r.month} className={`border-b border-border/20 hover:bg-white/[.02] ${r.isCurr ? 'bg-blue-500/[.04]' : ''} ${(r as any).isPeak ? 'bg-red-500/[.04]' : ''}`}>
              <td className={`py-1.5 px-2 font-medium ${r.isCurr ? 'text-blue-400' : r.isPast ? 'text-heading' : 'text-muted'}`}>
                {r.label}{r.isCurr ? ' ←' : ''}{(r as any).isPeak ? ' 🔺' : ''}
              </td>
              <td className="text-right py-1.5 px-2 tabular-nums text-emerald-400/70 cursor-help" title={tipIn(r)}>
                {r.actIn ? fK(r.actIn) : '—'}
              </td>
              <td className="text-right py-1.5 px-2 tabular-nums text-emerald-400/40 italic cursor-help" title={tipIn(r)}>
                {r.fcstIn ? fK(r.fcstIn) : '—'}
              </td>
              <td className="text-right py-1.5 px-2 tabular-nums text-emerald-400 font-medium border-r border-border/20 cursor-help" title={`Total Inflow\nActual: ${fK(r.actIn)}\nForecast: ${fK(r.fcstIn)}`}>
                {fK(r.totIn)}
              </td>
              <td className="text-right py-1.5 px-2 tabular-nums text-red-400/70 cursor-help" title={tipOutAct(r)}>
                {r.actOut ? fK(r.actOut) : '—'}
              </td>
              <td className="text-right py-1.5 px-2 tabular-nums text-orange-400/60 cursor-help" title={tipOutPlanned(r)}>
                {r.plannedOut ? fK(r.plannedOut) : '—'}
              </td>
              <td className="text-right py-1.5 px-2 tabular-nums text-red-400/40 italic cursor-help" title={tipOutFcst(r)}>
                {r.fcstOut ? fK(r.fcstOut) : '—'}
              </td>
              <td className="text-right py-1.5 px-2 tabular-nums text-red-400 font-medium cursor-help" title={`Total Outflow\nActual: ${fK(r.actOut)}\nPlanned: ${fK(r.plannedOut)}\nForecast: ${fK(r.fcstOut)}`}>
                {fK(r.totOut)}
              </td>
              <td className={`text-right py-1.5 px-2 tabular-nums font-bold ${r.net >= 0 ? 'text-emerald-400' : 'text-red-400'}`} title={`Net = ${fK(r.totIn)} inflow − ${fK(r.totOut)} outflow`}>
                {r.net >= 0 ? '+' : ''}{fK(r.net)}
              </td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr className="border-t-2 border-border font-bold">
            <td className="py-2.5 px-2 text-heading">TOTAL</td>
            <td className="text-right py-2.5 px-2 tabular-nums text-emerald-400/70">{fK(totals.actIn)}</td>
            <td className="text-right py-2.5 px-2 tabular-nums text-emerald-400/40">{fK(totals.fcstIn)}</td>
            <td className="text-right py-2.5 px-2 tabular-nums text-emerald-400 border-r border-border/20">{fK(totals.totIn)}</td>
            <td className="text-right py-2.5 px-2 tabular-nums text-red-400/70">{fK(totals.actOut)}</td>
            <td className="text-right py-2.5 px-2 tabular-nums text-orange-400/60">{fK(totals.plannedOut)}</td>
            <td className="text-right py-2.5 px-2 tabular-nums text-red-400/40">{fK(totals.fcstOut)}</td>
            <td className="text-right py-2.5 px-2 tabular-nums text-red-400">{fK(totals.totOut)}</td>
            <td className={`text-right py-2.5 px-2 tabular-nums text-lg font-bold ${totals.net >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
              {totals.net >= 0 ? '+' : ''}{fK(totals.net)}
            </td>
          </tr>
        </tfoot>
      </table>
    </Section>
  );
}

