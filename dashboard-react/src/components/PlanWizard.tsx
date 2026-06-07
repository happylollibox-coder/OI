import { useState, useMemo, useEffect, useRef, useCallback, Fragment } from 'react';
import { X, ChevronLeft, ChevronRight, Check, Loader2 } from 'lucide-react';
import { StepAdsPath, type AdsTarget, type TrajMonth, type FamilyRoasRef } from './StepAdsPath';
import { fM, fK, fmt } from '../utils';
import type {
  FamilyBaseline, AdsEfficiencyMap, ForecastDemandMap, ForecastMetaMap,
  MonthSeasonMap, MonthDef, MonthProj,
} from '../planTypes';
import { MFR, SHIP, allocateOrder, splitTrajectoryToProducts, monthKey, offSeasonTrend, dataCutoffDay, seasonalShape, detectLaunchMonth } from '../planTypes';

const STEPS = [
  { id: 1, label: 'Baseline' },
  { id: 2, label: 'Growth' },
  { id: 3, label: 'Ads Path' },
  { id: 4, label: 'Spend Plan' },
  { id: 5, label: 'Order' },
] as const;

export interface WizardResult {
  family: string;
  brandGrowth: number; // brand demand multiplier from Step 2 (e.g. 2.54)
  adsPath: 'current' | 'target' | 'custom';
  customDailySpend?: number;
  orderQty: number;
  orderByProduct: Record<string, number>; // per-product, carton/100-rounded — keyed by product name
  adsTargets?: AdsTarget[]; // monthly spend/CPC targets for Ad Coach
  // Per-product per-month FORECAST over the horizon (excludes elapsed actuals).
  // Keyed by product name → { "may26": units, ... }.
  plannedMonthly: Record<string, Record<string, number>>;
  // 'auto' = order derived from forecast; 'manual' = orderByProduct are user-set buy quantities.
  orderMode: 'auto' | 'manual';
}

type ActualsMap = Map<string, Map<number, { units: number; revenue: number; cogs: number; adCost: number }>>;

type BrandedSearchMonth = {
  yr: number; mo: number; family: string;
  purchases: number; impressions: number; clicks: number;
  adsUnits: number; adsSpend: number;
  totalSqpPurchases: number; totalAdsUnits: number; totalAdsSpend: number;
};

type AdsChannelMonth = {
  family: string; yr: number; mo: number; searchType: string;
  spend: number; clicks: number; units: number; orders: number;
  cpc: number; unitCvrPct: number; netRoas: number;
  currentDailySpend: number; currentCpc: number;
};

interface Props {
  family: FamilyBaseline;
  months: MonthDef[];
  demandMap: ForecastDemandMap;
  metaMap: ForecastMetaMap;
  seasonMap: MonthSeasonMap;
  adsEfficiency: AdsEfficiencyMap;
  projs: MonthProj[];
  growthOverrides: Record<string, number>;
  actuals2025: ActualsMap;
  actuals2026: ActualsMap;
  brandedSearch: BrandedSearchMonth[];
  channelEfficiency: AdsChannelMonth[];
  roas: FamilyRoasRef | null;
  latestDataDate?: Date | null;
  runRateMap: Map<string, { unitsPerDay: number; spendPerDay: number }>;
  familyMonthly2025: Record<string, number[]>;
  onSave: (result: WizardResult) => void | Promise<void>;
  onClose: () => void;
}

export function PlanWizard({ family: f, months, demandMap, metaMap, seasonMap, adsEfficiency, projs, growthOverrides: initGrowth, actuals2025, actuals2026, brandedSearch, channelEfficiency, roas, latestDataDate, runRateMap, familyMonthly2025, onSave, onClose }: Props) {
  const [step, setStep] = useState(1);
  const [adsPath, setAdsPath] = useState<'current' | 'target' | 'custom'>('current');
  const [customDaily, setCustomDaily] = useState(0);
  const [orderQty, setOrderQty] = useState(0);
  const [orderQtyUserEdited, setOrderQtyUserEdited] = useState(false);
  const [brandGrowth, setBrandGrowth] = useState(1.0); // from StepGrowth
  const [adsTargets, setAdsTargets] = useState<AdsTarget[]>([]);
  const [trajectory, setTrajectory] = useState<TrajMonth[]>([]);
  const [friendlyRound, setFriendlyRound] = useState(false); // round per-product to next 100 instead of cartons
  const [applying, setApplying] = useState(false); // Apply in flight — disables the button + shows a spinner
  const [orderMode, setOrderMode] = useState<'auto' | 'manual'>('auto');
  const [manualByProduct, setManualByProduct] = useState<Record<string, number>>({}); // user-set per-product buy qty (manual mode)
  const modalRef = useRef<HTMLDivElement>(null);

  const famEff = adsEfficiency[f.family] ?? {};
  const products = f.variations;
  // Memoized so StepAdsPath gets a STABLE array ref — an inline .filter() here recreates the array
  // every render, which cascades through seasonBenchmarks → profitMaxPlan → adsTargets/trajectory
  // and makes StepAdsPath's onTargets/onTrajectory effects fire every render → setState → infinite loop.
  const channelData = useMemo(() => channelEfficiency.filter(c => c.family === f.family), [channelEfficiency, f.family]);

  // Demand from runSim (fallback before the ads path is built)
  const simDemand = useMemo(() => {
    let d = 0;
    for (const p of projs) { const fd = p.families[f.family]; if (fd) d += fd.demand; }
    return Math.round(d);
  }, [projs, f.family]);

  // Ads-path demand: total units the chosen spend path produces over the plan horizon.
  // This is the source of truth for the order once Step 3 has built the trajectory.
  const adsPathDemand = useMemo(() => {
    if (!trajectory || trajectory.length === 0) return null;
    let sum = 0;
    for (const t of trajectory) {
      if (months.some(m => m.month === t.mo && m.year === t.yr)) sum += t.totalUnits;
    }
    return Math.round(sum);
  }, [trajectory, months]);

  const forecastDemand = adsPathDemand ?? simDemand;

  // Prior-year (2025) per-calendar-month anchors for this family: total units + ad spend.
  // These anchor the profit-max Ads Path (units(S) = units₂₅ × (S/spend₂₅)^e).
  const monthlyUnits2025 = useMemo(() => {
    const arr = Array(12).fill(0);
    for (const v of f.variations) {
      const pm = actuals2025.get(v.name);
      if (!pm) continue;
      for (let mo = 0; mo < 12; mo++) arr[mo] += pm.get(mo)?.units ?? 0;
    }
    return arr;
  }, [actuals2025, f.variations]);
  const monthlySpend2025 = useMemo(() => {
    const arr = Array(12).fill(0);
    for (const v of f.variations) {
      const pm = actuals2025.get(v.name);
      if (!pm) continue;
      for (let mo = 0; mo < 12; mo++) arr[mo] += pm.get(mo)?.adCost ?? 0;
    }
    return arr;
  }, [actuals2025, f.variations]);

  // ── Run-rate × seasonal-shape anchor (replaces the stale 2025 anchor for the profit-max plan) ──
  const familyRun = useMemo(() => {
    let unitsPerDay = 0, spendPerDay = 0;
    for (const v of f.variations) {
      const rr = runRateMap.get(v.name);
      if (rr) { unitsPerDay += rr.unitsPerDay; spendPerDay += rr.spendPerDay; }
    }
    return { unitsPerDay, spendPerDay };
  }, [runRateMap, f.variations]);

  const shape = useMemo(() => {
    const own = familyMonthly2025[f.family] ?? Array(12).fill(0);
    const ref = familyMonthly2025['Lollibox'] ?? Array(12).fill(0);
    const cm = new Date().getMonth() + 1;
    return seasonalShape(own, ref, cm, detectLaunchMonth(own));
  }, [familyMonthly2025, f.family]);

  // anchorUnits[mo] = run-rate units/day × days-in-month × shape (shape[currentMonth] = 1).
  const anchorUnits = useMemo(
    () => Array.from({ length: 12 }, (_, i) => familyRun.unitsPerDay * new Date(2026, i + 1, 0).getDate() * shape[i]),
    [familyRun, shape]);
  const anchorSpend = useMemo(
    () => Array.from({ length: 12 }, (_, i) => familyRun.spendPerDay * new Date(2026, i + 1, 0).getDate() * shape[i]),
    [familyRun, shape]);

  // Per-product per-month forecast from the chosen Ads Path. The family month total (which carries
  // the spend decision + seasonality) is distributed by each product's per-month runSim demand
  // share — so seasonality is counted once, not compounded.
  const inHorizon = useCallback(
    (mo: number, yr: number) => months.some(m => m.month === mo && m.year === yr),
    [months],
  );
  const runSimUnits = useCallback(
    (name: string, mo: number, yr: number) =>
      projs.find(p => p.key === monthKey(mo, yr))?.families[f.family]?.vars[name]?.demand ?? 0,
    [projs, f.family],
  );
  const plannedMonthly = useMemo(
    () => splitTrajectoryToProducts(trajectory, f.variations, inHorizon, runSimUnits),
    [trajectory, f.variations, inHorizon, runSimUnits],
  );

  // Per-product forecast demand, velocity-shaped: each product's planned units summed across the
  // horizon (plannedMonthly is the ads-path trajectory split by per-month runSim demand share —
  // the SAME per-variation basis the main Plan page uses for NEED). Falls back to forecastDemand ×
  // static splitPct for products the trajectory doesn't cover (e.g. before Step 3 builds it).
  // This replaces the old splitPct-only allocation, which misordered variations whose forward
  // velocity differs from their historical sales share (e.g. ordering an overstocked colour).
  const forecastByProduct = useMemo(() => {
    const totalShare = f.variations.reduce((s, v) => s + (v.splitPct > 0 ? v.splitPct : 0), 0);
    const n = f.variations.length;
    const map: Record<string, number> = {};
    for (const v of f.variations) {
      const planned = plannedMonthly[v.name]
        ? Object.values(plannedMonthly[v.name]).reduce((a, b) => a + b, 0)
        : 0;
      map[v.name] = planned > 0
        ? planned
        : forecastDemand * (totalShare > 0 ? (v.splitPct > 0 ? v.splitPct : 0) : (n > 0 ? 1 / n : 0));
    }
    return map;
  }, [f.variations, plannedMonthly, forecastDemand]);

  // Family gap = sum of per-product gaps (own velocity forecast − own stock). Stock isn't fungible
  // across variations, so a colour overstocked on its own demand shouldn't be reordered.
  const gap = useMemo(
    () => Math.round(f.variations.reduce((sum, v) => sum + Math.max(0, (forecastByProduct[v.name] ?? 0) - v.inventory), 0)),
    [f.variations, forecastByProduct],
  );

  // Fix #1: Sync orderQty to gap until user manually edits it
  useEffect(() => {
    if (!orderQtyUserEdited) setOrderQty(gap);
  }, [gap, orderQtyUserEdited]);

  const handleQtyChange = useCallback((n: number) => {
    setOrderQtyUserEdited(true);
    setOrderQty(n);
  }, []);

  // Switch order mode; on first switch to manual, seed per-product quantities from the auto allocation.
  const handleOrderMode = useCallback((m: 'auto' | 'manual') => {
    if (m === 'manual' && Object.keys(manualByProduct).length === 0) {
      setManualByProduct({ ...allocateOrder(f.variations, orderQty, forecastDemand, friendlyRound, forecastByProduct).byProduct });
    }
    setOrderMode(m);
  }, [manualByProduct, f.variations, orderQty, forecastDemand, friendlyRound, forecastByProduct]);
  // Manual per-product order quantity (StepOrder rounds up to the carton/100 before calling).
  const handleManualQty = useCallback((name: string, qty: number) => {
    setManualByProduct(prev => ({ ...prev, [name]: Math.max(0, qty) }));
  }, []);

  // Fix #6: Escape-to-close
  useEffect(() => {
    const handleEsc = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [onClose]);

  // Fix #6: Focus trap — focus modal on mount
  useEffect(() => { modalRef.current?.focus(); }, []);

  // Ads path totals
  const pathTotals = useMemo(() => {
    let cSpend = 0, cUnits = 0, cProfit = 0, tSpend = 0, tUnits = 0, tProfit = 0;
    for (const d of Object.values(famEff)) {
      cSpend += d.currentSpend; cUnits += d.currentForecastUnits; cProfit += d.currentNetProfit;
      tSpend += d.suggestedSpend; tUnits += d.forecastUnits; tProfit += d.targetNetProfit;
    }
    return { cSpend, cUnits, cProfit, tSpend, tUnits, tProfit };
  }, [famEff]);

  // Fix #8: Step guards — require path chosen before Step 4, qty > 0 before save
  const canNext = step < 5 && (
    step !== 3 || adsPath !== 'current' || true // can always proceed from ads path (current is valid)
  );
  const canBack = step > 1;
  const canSave = orderQty > 0;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm" onClick={onClose}>
      <div ref={modalRef} tabIndex={-1} className="bg-card border border-border rounded-2xl shadow-2xl w-[900px] max-h-[85vh] flex flex-col outline-none" onClick={e => e.stopPropagation()}>
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-border">
          <div>
            <h2 className="text-lg font-bold text-heading">{f.family} — Planning Wizard</h2>
            <p className="text-xs text-muted">Step {step} of 5 · {STEPS[step - 1].label}</p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-border/30 text-muted"><X size={18} /></button>
        </div>

        {/* Step indicator */}
        <div className="flex items-center gap-1 px-6 py-3 border-b border-border/50">
          {STEPS.map((s, i) => (
            <div key={s.id} className="flex items-center gap-1">
              <button onClick={() => s.id <= step && setStep(s.id)}
                className={`w-7 h-7 rounded-full text-[10px] font-bold flex items-center justify-center transition-all
                  ${s.id === step ? 'bg-blue-500 text-white shadow-lg shadow-blue-500/30'
                    : s.id < step ? 'bg-emerald-500/20 text-emerald-400 cursor-pointer'
                    : 'bg-border/30 text-faint'}`}>
                {s.id < step ? <Check size={12} /> : s.id}
              </button>
              <span className={`text-[9px] font-medium ${s.id === step ? 'text-heading' : 'text-faint'}`}>{s.label}</span>
              {i < STEPS.length - 1 && <div className={`w-6 h-px ${s.id < step ? 'bg-emerald-500/40' : 'bg-border/40'}`} />}
            </div>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto px-6 py-4 space-y-4 text-xs">
          {step === 1 && <StepBaseline products={products} months={months} metaMap={metaMap} actuals2025={actuals2025} />}
          {step === 2 && <StepGrowth products={products} months={months} demandMap={demandMap} actuals2025={actuals2025} actuals2026={actuals2026} brandedSearch={brandedSearch} family={f.family} seasonMap={seasonMap} latestDataDate={latestDataDate} shape={shape} familyRunRate={familyRun.unitsPerDay} onGrowthChange={setBrandGrowth} />}
          {step === 3 && <StepAdsPath famEff={famEff} path={adsPath} onPath={setAdsPath} customDaily={customDaily} onCustom={setCustomDaily} totals={pathTotals} channelData={channelData} months={months} asp={f.asp} costPerUnit={f.costPerUnit} monthlyUnits={monthlyUnits2025} monthlySpend={monthlySpend2025} anchorUnits={anchorUnits} anchorSpend={anchorSpend} roas={roas} latestDataDate={latestDataDate} onTargets={setAdsTargets} onTrajectory={setTrajectory} />}
          {step === 4 && <StepSpendPlan months={months} famEff={famEff} path={adsPath} customDaily={customDaily} trajectory={trajectory} currentStock={f.inventory} />}
          {step === 5 && <StepOrder family={f} annualDemand={forecastDemand} forecastByProduct={forecastByProduct} gap={gap} orderQty={orderQty} onQty={handleQtyChange} friendly={friendlyRound} onFriendly={setFriendlyRound} mode={orderMode} onMode={handleOrderMode} manualByProduct={manualByProduct} onManualQty={handleManualQty} />}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-3 border-t border-border">
          <button onClick={() => canBack && setStep(s => s - 1)} disabled={!canBack}
            className={`flex items-center gap-1 px-4 py-2 rounded-lg text-xs font-medium transition-colors ${canBack ? 'text-heading hover:bg-border/30' : 'text-faint cursor-not-allowed'}`}>
            <ChevronLeft size={14} /> Back
          </button>
          {step < 5 ? (
            <button onClick={() => setStep(s => s + 1)}
              className="flex items-center gap-1 px-5 py-2 rounded-lg text-xs font-bold bg-blue-500 text-white hover:bg-blue-600 transition-colors shadow-lg shadow-blue-500/20">
              Next <ChevronRight size={14} />
            </button>
          ) : (
            <button onClick={async () => {
              if (!canSave || applying) return;
              setApplying(true);
              try {
              const alloc = allocateOrder(f.variations, orderQty, forecastDemand, friendlyRound, forecastByProduct);
              // Effective per-product order: manual mode = user quantities (carton-rounded); auto = allocation.
              const effectiveByProduct = orderMode === 'manual'
                ? Object.fromEntries(f.variations.map(v => {
                    const stepUnit = friendlyRound ? 100 : (v.cartonQty > 0 ? v.cartonQty : 1);
                    const raw = manualByProduct[v.name] ?? 0;
                    return [v.name, raw > 0 ? Math.ceil(raw / stepUnit) * stepUnit : 0];
                  }))
                : alloc.byProduct;
              const effectiveTotal = Object.values(effectiveByProduct).reduce((a, b) => a + b, 0);
              await onSave({ family: f.family, brandGrowth, adsPath, customDailySpend: adsPath === 'custom' ? customDaily : undefined, orderQty: effectiveTotal, orderByProduct: effectiveByProduct, adsTargets, plannedMonthly, orderMode });
              } finally {
                setApplying(false);
              }
            }}
              disabled={!canSave || applying}
              title={!canSave ? 'Set order quantity > 0 before saving' : applying ? 'Applying…' : undefined}
              className={`flex items-center gap-1 px-5 py-2 rounded-lg text-xs font-bold transition-colors shadow-lg ${
                applying ? 'bg-emerald-500/70 text-white cursor-wait shadow-none'
                  : canSave ? 'bg-emerald-500 text-white hover:bg-emerald-600 shadow-emerald-500/20'
                  : 'bg-border/30 text-faint cursor-not-allowed shadow-none'}`}>
              {applying ? <><Loader2 size={14} className="animate-spin" /> Applying…</> : <><Check size={14} /> Apply</>}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── Step 1: Baseline (2025 actuals only) ─────────────────
function StepBaseline({ products, months, metaMap, actuals2025 }: {
  products: FamilyBaseline['variations']; months: MonthDef[]; metaMap: ForecastMetaMap; actuals2025: ActualsMap;
}) {
  return (
    <div>
      <p className="text-muted mb-3">Your <span className="text-heading font-medium">2025 actual sales</span> — the starting point for all forecasts. New products show their model source.</p>
      <table className="w-full text-[10px]">
        <thead><tr className="text-muted border-b border-border">
          <th className="text-left py-1.5 px-1">Product</th>
          <th className="text-right py-1.5 px-1 w-12">Share</th>
          {months.slice(0, 8).map(m => <th key={m.key} className="text-right py-1.5 px-1 w-12">{m.label}</th>)}
          <th className="text-right py-1.5 px-1 w-14 font-bold">Annual</th>
        </tr></thead>
        <tbody>
          {products.map(v => {
            const meta = metaMap[v.name];
            const ly = actuals2025.get(v.name);
            const modelLy = meta?.modelProduct ? actuals2025.get(meta.modelProduct) : null;
            const refLy = ly ?? modelLy;
            let lyAnnual = 0;
            const lyCells = months.slice(0, 8).map(m => {
              const lyU = refLy?.get(m.month - 1)?.units ?? 0;
              lyAnnual += lyU;
              return <td key={m.key} className="text-right py-1.5 px-1 tabular-nums font-medium text-heading">{lyU > 0 ? fmt(Math.round(lyU)) : '—'}</td>;
            });
            for (const m of months.slice(8)) { lyAnnual += refLy?.get(m.month - 1)?.units ?? 0; }
            const sourceNote = meta?.isNew && meta.modelProduct ? `Based on ${meta.modelProduct}` : null;
            return (
              <tr key={v.name} className="border-b border-border/20">
                <td className="py-1.5 px-1 font-medium text-heading">
                  {v.name}
                  {sourceNote && <div className="text-[8px] text-amber-400 font-normal mt-0.5">{sourceNote}</div>}
                </td>
                <td className="text-right py-1.5 px-1 tabular-nums text-muted">{(v.splitPct * 100).toFixed(0)}%</td>
                {lyCells}
                <td className="text-right py-1.5 px-1 tabular-nums font-bold text-heading">{lyAnnual > 0 ? fmt(Math.round(lyAnnual)) : '—'}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

// ─── Step 2: Growth (Brand Demand Health) ──────────────
// Shows branded search purchases — units from customers who specifically
// searched for the brand. Uses same DIM_BRAND_PHRASES logic as Brand page.
// Brand-level (not per-family) because top searches span multiple families.
function StepGrowth({ products, months, demandMap, actuals2025, actuals2026, brandedSearch, family, seasonMap, latestDataDate, shape, familyRunRate, onGrowthChange }: {
  products: FamilyBaseline['variations']; months: MonthDef[];
  demandMap: ForecastDemandMap; actuals2025: ActualsMap; actuals2026: ActualsMap;
  brandedSearch: BrandedSearchMonth[]; family: string;
  seasonMap: Record<string, Record<number, { peakDays: number; offseasonDays: number }>>;
  latestDataDate?: Date | null;
  shape: number[];
  familyRunRate: number;
  onGrowthChange: (g: number) => void;
}) {
  const [perDay, setPerDay] = useState(false); // Monthly Demand table: monthly total vs daily average
  // Compare branded search purchases: YoY through data cutoff date
  // Prorates the current partial month in BOTH years for fair comparison
  const brandComparison = useMemo(() => {
    const familyData = brandedSearch.filter(b => b.family === family);
    const mo25 = new Map<number, BrandedSearchMonth>();
    const mo26 = new Map<number, BrandedSearchMonth>();
    for (const b of familyData) {
      if (b.yr === 2025) mo25.set(b.mo, b);
      if (b.yr === 2026) mo26.set(b.mo, b);
    }

    // Data cutoff = the REAL latest orders/units date (FACT_AMAZON_PERFORMANCE_DAILY's max,
    // passed in as latestDataDate), not a wall-clock lag guess. Falls back to today−2 (the
    // orders feed's typical lag) only if the freshness query hasn't loaded yet.
    const today = new Date();
    const currentMonth = today.getMonth() + 1; // 1-based
    const cutoffDay = dataCutoffDay(latestDataDate, today.getFullYear(), currentMonth, today.getDate() - 2);
    const daysInCurrentMonth = new Date(2026, currentMonth, 0).getDate();
    const prorateFactor = Math.max(cutoffDay / daysInCurrentMonth, 0.01); // never 0 or negative

    // Determine the last full month in 2026 (month BEFORE current)
    const lastFullMonth = currentMonth - 1; // e.g. April (4)

    // Overlap: months present in both years, up to AND including current (prorated)
    const overlapMonths: number[] = [];
    for (let m = 1; m <= currentMonth; m++) {
      if (mo25.has(m) && (m < currentMonth ? true : mo26.has(m))) overlapMonths.push(m);
    }
    overlapMonths.sort();

    // Helper: get month value with proration for current month
    const getVal = (mo: Map<number, BrandedSearchMonth>, m: number, field: 'purchases' | 'adsUnits' | 'adsSpend' | 'totalSqpPurchases' | 'totalAdsUnits' | 'totalAdsSpend') => {
      const raw = mo.get(m)?.[field] ?? 0;
      return m === currentMonth ? Math.round(raw * prorateFactor) : raw;
    };

    let brandSqp25 = 0, brandSqp26 = 0, brandAds25 = 0, brandAds26 = 0;
    let brandAdsSpend25 = 0, brandAdsSpend26 = 0;
    let allSqp25 = 0, allSqp26 = 0, allAds25 = 0, allAds26 = 0;
    let allAdsSpend25 = 0, allAdsSpend26 = 0;

    for (const m of overlapMonths) {
      brandSqp25 += getVal(mo25, m, 'purchases');  brandSqp26 += getVal(mo26, m, 'purchases');
      brandAds25 += getVal(mo25, m, 'adsUnits');    brandAds26 += getVal(mo26, m, 'adsUnits');
      brandAdsSpend25 += getVal(mo25, m, 'adsSpend'); brandAdsSpend26 += getVal(mo26, m, 'adsSpend');
      allSqp25 += getVal(mo25, m, 'totalSqpPurchases'); allSqp26 += getVal(mo26, m, 'totalSqpPurchases');
      allAds25 += getVal(mo25, m, 'totalAdsUnits');  allAds26 += getVal(mo26, m, 'totalAdsUnits');
      allAdsSpend25 += getVal(mo25, m, 'totalAdsSpend'); allAdsSpend26 += getVal(mo26, m, 'totalAdsSpend');
    }

    const brand25 = brandSqp25 + brandAds25;
    const brand26 = brandSqp26 + brandAds26;
    const brandGrowth = brand25 > 0 ? brand26 / brand25 : 1;
    const brandGrowthPct = (brandGrowth - 1) * 100;

    const nbSqp25 = allSqp25 - brandSqp25, nbSqp26 = allSqp26 - brandSqp26;
    const nbAds25 = allAds25 - brandAds25, nbAds26 = allAds26 - brandAds26;
    const nb25 = nbSqp25 + nbAds25, nb26 = nbSqp26 + nbAds26;
    const nbGrowth = nb25 > 0 ? nb26 / nb25 : 1;
    const nbGrowthPct = (nbGrowth - 1) * 100;
    const nbAdsSpend25 = allAdsSpend25 - brandAdsSpend25;
    const nbAdsSpend26 = allAdsSpend26 - brandAdsSpend26;

    const combined25 = allSqp25 + allAds25;
    const combined26 = allSqp26 + allAds26;
    const combinedGrowth = combined25 > 0 ? combined26 / combined25 : 1;
    const combinedGrowthPct = (combinedGrowth - 1) * 100;

    const monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const periodLabel = overlapMonths.length > 0
      ? `Jan 1–${monthNames[currentMonth-1]} ${cutoffDay}`
      : 'N/A';

    // ── New-product off-season fallback ──
    // When a month has no prior-year base (product launched mid-2025), YoY collapses to ~0.
    // Derive those off-season months from the family's OWN within-year off-season run-rate.
    const LY_MIN = 5; // units — "no usable prior-year base" threshold
    const seasonInfo = seasonMap[family] ?? {};
    const isOffSeason = (year: number, month: number) => {
      const info = seasonInfo[year * 100 + month] ?? seasonInfo[2026 * 100 + month] ?? seasonInfo[2025 * 100 + month];
      return info ? info.peakDays === 0 : true; // unknown → off-season (peak is the exception)
    };
    const brandHistory = familyData.map(b => ({ year: b.yr, month: b.mo, units: (b.purchases ?? 0) + (b.adsUnits ?? 0) }));
    const nbHistory = familyData.map(b => ({ year: b.yr, month: b.mo, units: (b.totalSqpPurchases ?? 0) + (b.totalAdsUnits ?? 0) - ((b.purchases ?? 0) + (b.adsUnits ?? 0)) }));
    const trendCutoff = { year: 2026, month: currentMonth, prorate: prorateFactor };
    const combinedHistory = familyData.map(b => ({ year: b.yr, month: b.mo, units: (b.totalSqpPurchases ?? 0) + (b.totalAdsUnits ?? 0) }));
    const brandTrend = offSeasonTrend(brandHistory, isOffSeason, null, trendCutoff);
    const nbTrend = offSeasonTrend(nbHistory, isOffSeason, null, trendCutoff);
    const combinedTrend = offSeasonTrend(combinedHistory, isOffSeason, null, trendCutoff);
    // Forecast level = the trailing 4-week weighted run-rate (40/30/20/10) — the SAME level the
    // order step uses — instead of offSeasonTrend's month-based "May + June-to-date". Split into
    // brand / non-brand by their current share; fall back to the trend rate if run-rate is missing.
    const trendTot = brandTrend.recentRate + nbTrend.recentRate;
    const brandShare = trendTot > 0 ? brandTrend.recentRate / trendTot : 0;
    const fcstRate = familyRunRate > 0 ? familyRunRate : trendTot;
    const brandRate = fcstRate * brandShare;
    const nbRate = fcstRate * (1 - brandShare);
    const daysRemaining = daysInCurrentMonth * (1 - prorateFactor);

    // Forecast: actual months + projected remaining months (using per-channel growth)
    // Brand forecast
    let brandForecast26 = 0, nbForecast26 = 0;
    let brandCurRemaining = 0, nbCurRemaining = 0; // current-month remaining forecast (for MayF render)
    // Per-month forecast maps for table display
    const brandFcstByMonth = new Map<number, number>();
    const nbFcstByMonth = new Map<number, number>();
    for (let m = 1; m <= 12; m++) {
      const d26 = mo26.get(m);
      if (m <= lastFullMonth) {
        // Full actual month
        const bv = (d26?.purchases ?? 0) + (d26?.adsUnits ?? 0);
        const nbv = (d26?.totalSqpPurchases ?? 0) + (d26?.totalAdsUnits ?? 0) - bv;
        brandForecast26 += bv; nbForecast26 += nbv;
        brandFcstByMonth.set(m, bv); nbFcstByMonth.set(m, nbv);
      } else if (m === currentMonth) {
        // Partial month: actual (prorated) + remaining (forecast)
        const bActual = (d26?.purchases ?? 0) + (d26?.adsUnits ?? 0);
        const nbActual = (d26?.totalSqpPurchases ?? 0) + (d26?.totalAdsUnits ?? 0) - bActual;
        // Remaining = weighted 4-week run-rate × remaining days (shape[currentMonth] = 1).
        const bRemaining = Math.round(brandRate * daysRemaining);
        const nbRemaining = Math.round(nbRate * daysRemaining);
        brandCurRemaining = bRemaining; nbCurRemaining = nbRemaining;
        brandForecast26 += bActual + bRemaining;
        nbForecast26 += nbActual + nbRemaining;
        brandFcstByMonth.set(m, bActual + bRemaining);
        nbFcstByMonth.set(m, nbActual + nbRemaining);
      } else {
        // Future month: weighted 4-week run-rate × days × the family seasonal shape (no LY×growth).
        const daysInM = new Date(2026, m, 0).getDate();
        const bProj = Math.round(brandRate * daysInM * (shape[m - 1] ?? 1));
        const nbProj = Math.round(nbRate * daysInM * (shape[m - 1] ?? 1));
        brandForecast26 += bProj;
        nbForecast26 += nbProj;
        brandFcstByMonth.set(m, bProj); nbFcstByMonth.set(m, nbProj);
      }
    }

    const forecast26 = brandForecast26 + nbForecast26;
    let fullYear25 = 0;
    for (let m = 1; m <= 12; m++) {
      const d = mo25.get(m);
      fullYear25 += (d?.totalSqpPurchases ?? 0) + (d?.totalAdsUnits ?? 0);
    }

    return {
      brand25, brand26, brandGrowth, brandGrowthPct, brandSqp25, brandSqp26, brandAds25, brandAds26, brandAdsSpend25, brandAdsSpend26,
      nb25, nb26, nbGrowth, nbGrowthPct, nbSqp25, nbSqp26, nbAds25, nbAds26, nbAdsSpend25, nbAdsSpend26,
      combined25, combined26, combinedGrowth, combinedGrowthPct,
      periodLabel, overlapMonths, mo25, mo26, forecast26, fullYear25,
      currentMonth, lastFullMonth, prorateFactor, cutoffDay, brandFcstByMonth, nbFcstByMonth,
      brandForecast26, nbForecast26,
      brandTrend, nbTrend, combinedTrend, isOffSeason, brandCurRemaining, nbCurRemaining, LY_MIN,
    };
  }, [brandedSearch, family, latestDataDate, shape, seasonMap, familyRunRate]);

  // Report combined growth to parent wizard state
  useEffect(() => { onGrowthChange(brandComparison.combinedGrowth); }, [brandComparison.combinedGrowth, onGrowthChange]);

  // Monthly branded search table (all 12 months both years)
  const monthLabels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const displayMonths = brandComparison.overlapMonths.length > 0;

  // For a new product (no usable prior-year base), the YoY % is meaningless ("X vs 0 → 0%").
  // Show the within-year off-season momentum instead. Combined uses the SAME method as Brand/Non-brand.
  const channelHeadline = (c25: number, trend: { usable: boolean; momentum: number; recentRate: number; priorRate: number }, growthPct: number) => {
    if (c25 <= brandComparison.LY_MIN && trend.usable) {
      const pct = (trend.momentum - 1) * 100;
      return { pct, isOffTrend: true, sub: `off-season trend · ${trend.recentRate.toFixed(1)}/d vs ${trend.priorRate.toFixed(1)}/d` };
    }
    return { pct: growthPct, isOffTrend: false, sub: null as string | null };
  };
  const brandHead = channelHeadline(brandComparison.brand25, brandComparison.brandTrend, brandComparison.brandGrowthPct);
  const nbHead = channelHeadline(brandComparison.nb25, brandComparison.nbTrend, brandComparison.nbGrowthPct);
  const combHead = channelHeadline(brandComparison.combined25, brandComparison.combinedTrend, brandComparison.combinedGrowthPct);

  // Card up/down border colors track the displayed headline % (off-season trend when YoY is unusable).
  const brandUp = brandHead.pct > 5, brandDown = brandHead.pct < -5;
  const nbUp = nbHead.pct > 5, nbDown = nbHead.pct < -5;
  const combUp = combHead.pct > 5, combDown = combHead.pct < -5;

  return (
    <div>
      <p className="text-muted mb-3">
        Demand split into <span className="text-heading font-medium">Brand</span> (customers searching your name) and{' '}
        <span className="text-heading font-medium">Non-brand</span> (generic/category searches). Combined growth drives the forecast.
      </p>

      {/* Hero: 3 channel cards */}
      <div className="grid grid-cols-3 gap-3 mb-4">
        {/* Brand */}
        <div className={`p-3 rounded-xl border text-center ${brandUp ? 'border-emerald-500/30 bg-emerald-500/5' : brandDown ? 'border-red-500/30 bg-red-500/5' : 'border-border/30 bg-border/5'}`}>
          <div className="text-[9px] text-faint mb-1">🛡 Brand ({brandComparison.periodLabel})</div>
          <div className={`text-2xl font-black tabular-nums ${brandUp ? 'text-emerald-400' : brandDown ? 'text-red-400' : 'text-heading'}`}>
            {brandHead.pct > 0 ? '+' : ''}{brandHead.pct.toFixed(0)}%
          </div>
          {brandHead.sub
            ? <div className="text-[8px] text-blue-400/80 mt-0.5">{brandHead.sub}</div>
            : <div className="text-[9px] text-muted mt-0.5">{fmt(brandComparison.brand26)} vs {fmt(brandComparison.brand25)}</div>}
          <div className="text-[8px] text-faint mt-0.5">SQP: {fmt(brandComparison.brandSqp26)} · Ads: {fmt(brandComparison.brandAds26)}</div>
          <div className="text-[8px] text-faint">Spend: ${fK(brandComparison.brandAdsSpend26)}</div>
          <div className="text-[8px] text-blue-400/70 italic">2026F: {fmt(brandComparison.brandForecast26)} units</div>
        </div>
        {/* Non-brand */}
        <div className={`p-3 rounded-xl border text-center ${nbUp ? 'border-emerald-500/30 bg-emerald-500/5' : nbDown ? 'border-red-500/30 bg-red-500/5' : 'border-border/30 bg-border/5'}`}>
          <div className="text-[9px] text-faint mb-1">🔍 Non-brand ({brandComparison.periodLabel})</div>
          <div className={`text-2xl font-black tabular-nums ${nbUp ? 'text-emerald-400' : nbDown ? 'text-red-400' : 'text-heading'}`}>
            {nbHead.pct > 0 ? '+' : ''}{nbHead.pct.toFixed(0)}%
          </div>
          {nbHead.sub
            ? <div className="text-[8px] text-blue-400/80 mt-0.5">{nbHead.sub}</div>
            : <div className="text-[9px] text-muted mt-0.5">{fmt(brandComparison.nb26)} vs {fmt(brandComparison.nb25)}</div>}
          <div className="text-[8px] text-faint mt-0.5">SQP: {fmt(brandComparison.nbSqp26)} · Ads: {fmt(brandComparison.nbAds26)}</div>
          <div className="text-[8px] text-faint">Spend: ${fK(brandComparison.nbAdsSpend26)}</div>
          <div className="text-[8px] text-blue-400/70 italic">2026F: {fmt(brandComparison.nbForecast26)} units</div>
        </div>
        {/* Combined */}
        <div className={`p-3 rounded-xl border-2 text-center ${combUp ? 'border-emerald-500/40 bg-emerald-500/5' : combDown ? 'border-red-500/40 bg-red-500/5' : 'border-border/40 bg-border/5'}`}>
          <div className="text-[9px] text-faint mb-1">📊 Combined ({brandComparison.periodLabel})</div>
          <div className={`text-2xl font-black tabular-nums ${combUp ? 'text-emerald-400' : combDown ? 'text-red-400' : 'text-heading'}`}>
            {combHead.pct > 0 ? '+' : ''}{combHead.pct.toFixed(0)}%
          </div>
          {combHead.sub
            ? <div className="text-[8px] text-blue-400/80 mt-0.5">{combHead.sub}</div>
            : <div className="text-[9px] text-muted mt-0.5">{fmt(brandComparison.combined26)} vs {fmt(brandComparison.combined25)}</div>}
          <div className="text-[8px] text-faint mt-0.5">Brand: {brandComparison.combined26 > 0 ? ((brandComparison.brand26 / brandComparison.combined26) * 100).toFixed(0) : 0}% · Non-brand: {brandComparison.combined26 > 0 ? ((brandComparison.nb26 / brandComparison.combined26) * 100).toFixed(0) : 0}%</div>
          <div className="text-[8px] text-faint">2026F: {fmt(brandComparison.forecast26)} units</div>
        </div>
      </div>

      {/* Channel summary table */}
      {displayMonths && (() => {
        const { currentMonth: cm, lastFullMonth: lfm, mo25, mo26, brandFcstByMonth, nbFcstByMonth, prorateFactor: pf, brandCurRemaining, nbCurRemaining } = brandComparison;
        // Helper: cell value for brand (units)
        const brandVal = (mo: Map<number, BrandedSearchMonth>, m: number) => (mo.get(m)?.purchases ?? 0) + (mo.get(m)?.adsUnits ?? 0);
        // Helper: brand spend
        const brandSpend = (mo: Map<number, BrandedSearchMonth>, m: number) => mo.get(m)?.adsSpend ?? 0;
        // Helper: cell value for non-brand (units)
        const nbVal = (mo: Map<number, BrandedSearchMonth>, m: number) => {
          const d = mo.get(m);
          return (d?.totalSqpPurchases ?? 0) + (d?.totalAdsUnits ?? 0) - (d?.purchases ?? 0) - (d?.adsUnits ?? 0);
        };
        // Helper: non-brand spend
        const nbSpend = (mo: Map<number, BrandedSearchMonth>, m: number) => {
          const d = mo.get(m);
          return (d?.totalAdsSpend ?? 0) - (d?.adsSpend ?? 0);
        };
        const combVal = (mo: Map<number, BrandedSearchMonth>, m: number) => {
          const d = mo.get(m);
          return (d?.totalSqpPurchases ?? 0) + (d?.totalAdsUnits ?? 0);
        };
        const combSpend = (mo: Map<number, BrandedSearchMonth>, m: number) => mo.get(m)?.totalAdsSpend ?? 0;

        // Net profit helper from actuals (revenue - cogs - adCost)
        // ActualsMap is keyed by product name, so we sum across all family variations
        const productNames = products.map(p => p.name);
        const getProfit = (yr: number, m: number) => {
          const aMap = yr === 2025 ? actuals2025 : actuals2026;
          let total = 0;
          for (const name of productNames) {
            const d = aMap.get(name)?.get(m - 1); // ActualsMap uses 0-based months
            if (d) total += d.revenue - d.cogs - d.adCost;
          }
          return total;
        };

        // Cell renderer: units + spend subtitle + optional profit. In per-day mode each value is
        // divided by the days it spans — full months by days-in-month; the split current-month
        // columns (key suffix 'a' = elapsed actual, 'f' = remaining forecast) by their slice days.
        const cell = (key: string, v: number, spend: number, cls: string, profit?: number) => {
          let dv = v, ds = spend, dp = profit;
          if (perDay) {
            const m = parseInt(key.replace(/\D/g, ''), 10) || cm;
            const dim = new Date(2026, m, 0).getDate();
            const elapsed = Math.max(1, Math.round(dim * pf));
            const days = key.endsWith('a') ? elapsed : key.endsWith('f') ? Math.max(1, dim - elapsed) : dim;
            dv = v / days; ds = spend / days; dp = profit !== undefined ? profit / days : undefined;
          }
          return (
            <td key={key} className={`text-right py-1 px-1 tabular-nums ${cls}`}>
              <div>{dv > 0 ? fmt(Math.round(dv)) : '—'}</div>
              {ds > 0 && <div className="text-[8px] text-faint font-normal not-italic">{fK(ds)}</div>}
              {dp !== undefined && Math.round(dp) !== 0 && <div className={`text-[8px] font-normal not-italic ${dp >= 0 ? 'text-emerald-400/70' : 'text-red-400/70'}`}>{fK(dp)}</div>}
            </td>
          );
        };

        // Columns: Jan..Apr (full actual), May Actual, May Fcst, Jun..Dec (forecast)
        type Col = { key: string; label: string; month: number; type: 'actual' | 'current_actual' | 'current_fcst' | 'forecast' };
        const cols: Col[] = [];
        for (let m = 1; m <= 12; m++) {
          if (m < cm) {
            cols.push({ key: `m${m}`, label: monthLabels[m-1], month: m, type: 'actual' });
          } else if (m === cm) {
            cols.push({ key: `m${m}a`, label: `${monthLabels[m-1]}`, month: m, type: 'current_actual' });
            cols.push({ key: `m${m}f`, label: `${monthLabels[m-1]}F`, month: m, type: 'current_fcst' });
          } else {
            cols.push({ key: `m${m}`, label: monthLabels[m-1], month: m, type: 'forecast' });
          }
        }

        // Row renderer for Brand/Non-brand
        const renderRow = (label: string, icon: string, yr: string, channel: 'brand' | 'nb', bgCls: string) => {
          const is25 = yr === '25';
          const valFn = channel === 'brand' ? brandVal : nbVal;
          const spendFn = channel === 'brand' ? brandSpend : nbSpend;
          const fcstMap = channel === 'brand' ? brandFcstByMonth : nbFcstByMonth;
          // Current channel ad-spend-per-unit (2026 elapsed actuals). Forecast spend tracks
          // forecast units at today's efficiency — no LY×growth (which exploded for young families).
          let su26 = 0, sv26 = 0;
          for (let mm = 1; mm <= cm; mm++) { sv26 += valFn(mo26, mm); su26 += spendFn(mo26, mm); }
          const spendPerUnit = sv26 > 0 ? su26 / sv26 : 0;
          let ytd = 0, ytdSpend = 0;
          let yearTotal = 0, yearSpend = 0;
          const cells = cols.map(c => {
            let v = 0, sp = 0;
            let isForecast = false;
            if (is25) {
              v = valFn(mo25, c.month);
              sp = spendFn(mo25, c.month);
              if (c.type !== 'current_fcst') {
                ytd += c.month <= cm ? (c.type === 'current_actual' ? Math.round(v * pf) : v) : 0;
                ytdSpend += c.month <= cm ? (c.type === 'current_actual' ? Math.round(sp * pf) : sp) : 0;
              }
              yearTotal += v; yearSpend += sp;
              if (c.type === 'current_fcst') return cell(c.key, Math.round(v * (1 - pf)), Math.round(sp * (1 - pf)), 'text-muted opacity-40');
              if (c.type === 'current_actual') { v = Math.round(v * pf); sp = Math.round(sp * pf); }
              return cell(c.key, v, sp, `text-muted ${c.month > cm ? 'opacity-40' : ''}`);
            }
            // 2026 row
            if (c.type === 'actual') {
              v = valFn(mo26, c.month); sp = spendFn(mo26, c.month);
              ytd += v; ytdSpend += sp; yearTotal += v; yearSpend += sp;
            } else if (c.type === 'current_actual') {
              v = valFn(mo26, c.month); sp = spendFn(mo26, c.month);
              ytd += v; ytdSpend += sp; yearTotal += v; yearSpend += sp;
            } else if (c.type === 'current_fcst') {
              // Units: stored remaining (current run-rate × remaining days); spend tracks it.
              v = channel === 'brand' ? brandCurRemaining : nbCurRemaining;
              sp = Math.round(v * spendPerUnit);
              isForecast = true;
              yearTotal += v; yearSpend += sp;
            } else {
              v = fcstMap.get(c.month) ?? 0;
              sp = Math.round(v * spendPerUnit);
              isForecast = true;
              yearTotal += v; yearSpend += sp;
            }
            const cls = isForecast ? 'text-blue-400 italic' : 'text-heading font-medium';
            return cell(c.key, v, sp, cls);
          });
          return (
            <tr key={`${channel}-${yr}`} className={`border-b border-border/10 ${bgCls}`}>
              <td className="py-1 px-1 text-faint whitespace-nowrap">{icon} {label} {yr}</td>
              {cells}
              <td className={`text-right py-1 px-1 tabular-nums font-bold ${is25 ? 'text-muted' : 'text-heading'}`}>
                <div>{fmt(ytd)}</div>
                {ytdSpend > 0 && <div className="text-[8px] text-faint font-normal">{fK(ytdSpend)}</div>}
              </td>
              <td className={`text-right py-1 px-1 tabular-nums font-bold ${is25 ? 'text-muted' : 'text-blue-400'}`}>
                <div>{fmt(yearTotal)}</div>
                {yearSpend > 0 && <div className="text-[8px] text-faint font-normal not-italic">{fK(yearSpend)}</div>}
              </td>
            </tr>
          );
        };

        // Combined row renderer
        const renderCombinedRow = (yr: string) => {
          const is25 = yr === '25';
          // Current combined ad-spend-per-unit (2026 elapsed actuals) — forecast spend tracks units.
          let suC = 0, svC = 0;
          for (let mm = 1; mm <= cm; mm++) { svC += combVal(mo26, mm); suC += combSpend(mo26, mm); }
          const combSpendPerUnit = svC > 0 ? suC / svC : 0;
          let ytd = 0, ytdSpend = 0, yearTotal = 0, yearSpend = 0;
          const cells = cols.map(c => {
            let v = 0, sp = 0;
            let isForecast = false;
            if (is25) {
              v = combVal(mo25, c.month); sp = combSpend(mo25, c.month);
              if (c.type !== 'current_fcst') {
                ytd += c.month <= cm ? (c.type === 'current_actual' ? Math.round(v * pf) : v) : 0;
                ytdSpend += c.month <= cm ? (c.type === 'current_actual' ? Math.round(sp * pf) : sp) : 0;
              }
              yearTotal += v; yearSpend += sp;
              if (c.type === 'current_fcst') return cell(c.key, Math.round(v * (1 - pf)), Math.round(sp * (1 - pf)), 'text-muted opacity-40', getProfit(2025, c.month));
              if (c.type === 'current_actual') { v = Math.round(v * pf); sp = Math.round(sp * pf); }
              return cell(c.key, v, sp, `text-muted ${c.month > cm ? 'opacity-40' : ''}`, getProfit(2025, c.month));
            }
            // 2026
            if (c.type === 'actual') {
              v = combVal(mo26, c.month); sp = combSpend(mo26, c.month);
              ytd += v; ytdSpend += sp; yearTotal += v; yearSpend += sp;
              return cell(c.key, v, sp, 'text-heading font-bold', getProfit(2026, c.month));
            } else if (c.type === 'current_actual') {
              v = combVal(mo26, c.month); sp = combSpend(mo26, c.month);
              ytd += v; ytdSpend += sp; yearTotal += v; yearSpend += sp;
              return cell(c.key, v, sp, 'text-heading font-bold', getProfit(2026, c.month));
            } else if (c.type === 'current_fcst') {
              v = brandCurRemaining + nbCurRemaining;
              sp = Math.round(v * combSpendPerUnit);
              isForecast = true;
              yearTotal += v; yearSpend += sp;
            } else {
              v = (brandFcstByMonth.get(c.month) ?? 0) + (nbFcstByMonth.get(c.month) ?? 0);
              sp = Math.round(v * combSpendPerUnit);
              isForecast = true;
              yearTotal += v; yearSpend += sp;
            }
            const cls = isForecast ? 'text-blue-400 italic' : 'text-heading font-bold';
            return cell(c.key, v, sp, cls);
          });
          return (
            <tr key={`comb-${yr}`} className={`border-b border-border/10 ${yr === '25' ? 'border-t-2 border-t-border/40' : ''}`}>
              <td className="py-1 px-1 text-faint font-bold whitespace-nowrap">Combined {yr}</td>
              {cells}
              <td className={`text-right py-1 px-1 tabular-nums font-bold ${is25 ? 'text-muted' : 'text-heading'}`}>
                <div>{fmt(ytd)}</div>
                {ytdSpend > 0 && <div className="text-[8px] text-faint font-normal">{fK(ytdSpend)}</div>}
              </td>
              <td className={`text-right py-1 px-1 tabular-nums font-bold ${is25 ? 'text-muted' : 'text-blue-400'}`}>
                <div>{fmt(yearTotal)}</div>
                {yearSpend > 0 && <div className="text-[8px] text-faint font-normal not-italic">{fK(yearSpend)}</div>}
              </td>
            </tr>
          );
        };

        return (
          <div className="mb-4">
            <div className="flex items-center justify-between mb-2">
              <div className="text-heading font-bold text-[11px]">Monthly Demand by Channel</div>
              <div className="flex gap-1">
                <button onClick={() => setPerDay(false)} className={`px-2 py-0.5 rounded text-[9px] font-medium transition-colors ${!perDay ? 'bg-blue-500 text-white' : 'bg-border/30 text-muted hover:bg-border/50'}`}>Monthly</button>
                <button onClick={() => setPerDay(true)} className={`px-2 py-0.5 rounded text-[9px] font-medium transition-colors ${perDay ? 'bg-blue-500 text-white' : 'bg-border/30 text-muted hover:bg-border/50'}`}>Daily avg</button>
              </div>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-[10px]">
                <thead><tr className="text-muted border-b border-border">
                  <th className="text-left py-1.5 px-1 w-24">Channel</th>
                  {cols.map(c => (
                    <th key={c.key} className={`text-right py-1.5 px-1 w-10 ${c.type === 'forecast' || c.type === 'current_fcst' ? 'text-blue-400/60 italic' : ''}`}>
                      {c.label}
                    </th>
                  ))}
                  <th className="text-right py-1.5 px-1 w-12 font-bold">YTD</th>
                  <th className="text-right py-1.5 px-1 w-12 font-bold text-blue-400/80">Year</th>
                </tr></thead>
                <tbody>
                  {renderRow('Brand', '🛡', '25', 'brand', '')}
                  {renderRow('Brand', '🛡', '26', 'brand', '')}
                  {renderRow('Non-brand', '🔍', '25', 'nb', 'bg-border/5')}
                  {renderRow('Non-brand', '🔍', '26', 'nb', 'bg-border/5')}
                  {renderCombinedRow('25')}
                  {renderCombinedRow('26')}
                </tbody>
              </table>
            </div>
            <div className="text-[9px] text-faint mt-1">
              {brandComparison.periodLabel} compared YoY (prorated). <span className="italic text-blue-400/70">Blue italic = forecast (recent run-rate × last-year seasonal shape)</span>
            </div>
          </div>
        );
      })()}
    </div>
  );
}



// ─── Step 4: Spend Plan ──────────────────────────────────
function StepSpendPlan({ months, famEff, path, customDaily, trajectory, currentStock }: {
  months: MonthDef[]; famEff: Record<number, AdsEfficiencyMonth>; path: 'current' | 'target' | 'custom'; customDaily: number;
  trajectory: TrajMonth[]; currentStock: number;
}) {
  // Aggregate trajectory by month (combine actual + forecast slices for current month)
  const trajByMonth = useMemo(() => {
    const map = new Map<number, { spend: number; units: number; profit: number; k: number }>();
    for (const t of trajectory) {
      const existing = map.get(t.mo);
      if (existing) {
        existing.spend += t.spend;
        existing.units += t.totalUnits;
        existing.profit += t.profit;
        // Use the non-actual k (the forecast portion)
        if (!t.isActual) existing.k = t.kEffective;
      } else {
        map.set(t.mo, { spend: t.spend, units: t.totalUnits, profit: t.profit, k: t.kEffective });
      }
    }
    return map;
  }, [trajectory]);

  return (
    <div>
      <p className="text-muted mb-3">Monthly breakdown based on your chosen path. Efficiency params (CPC/CVR/AdsShare) vary by season.</p>
      <table className="w-full text-[10px]">
        <thead><tr className="text-muted border-b border-border">
          <th className="text-left py-1.5 px-1">Month</th>
          <th className="text-right py-1.5 px-1">Scale</th>
          <th className="text-right py-1.5 px-1">Spend</th>
          <th className="text-right py-1.5 px-1">Spend/d</th>
          <th className="text-right py-1.5 px-1">Units</th>
          <th className="text-right py-1.5 px-1">Units/d</th>
          <th className="text-right py-1.5 px-1">Stock</th>
          <th className="text-right py-1.5 px-1">Profit</th>
          <th className="text-right py-1.5 px-1">CPC</th>
          <th className="text-right py-1.5 px-1">ROAS</th>
        </tr></thead>
        <tbody>
          {(() => { let runningStock = currentStock; return months.map(m => {
            const d = famEff[m.month];
            const tj = trajByMonth.get(m.month);

            // Use trajectory data if available, fallback to famEff
            let spend: number, units: number, profit: number, scale: number;
            if (tj) {
              spend = tj.spend;
              units = Math.round(tj.units);
              profit = Math.round(tj.profit);
              scale = tj.k;
            } else if (d) {
              spend = path === 'current' ? d.currentSpend : path === 'target' ? d.suggestedSpend : customDaily * m.days;
              units = path === 'current' ? d.currentForecastUnits : path === 'target' ? d.forecastUnits
                : Math.round((customDaily * m.days / (d.cpc || 1)) * (d.unitCvrPct / 100) / ((d.adsSharePct || 75) / 100));
              profit = path === 'current' ? d.currentNetProfit : path === 'target' ? d.targetNetProfit
                : Math.round(spend * Math.max(d.netRoas - 1, 0));
              scale = 1;
            } else {
              return <tr key={m.key}><td colSpan={10} className="text-faint py-1">—</td></tr>;
            }

            const cpc = d?.cpc ?? 0;
            const roas = spend > 0 ? (profit + spend) / spend : 0;
            // Forecasted end-of-month stock: current stock drawn down by cumulative units sold.
            runningStock -= units;
            const stock = Math.round(runningStock);

            return (
              <tr key={m.key} className="border-b border-border/20 hover:bg-border/10">
                <td className="py-1.5 px-1 font-medium text-heading">{m.label} '{String(m.year).slice(2)}</td>
                <td className="text-right py-1.5 px-1 tabular-nums text-muted">{scale.toFixed(2)}×</td>
                <td className="text-right py-1.5 px-1 tabular-nums">{fK(spend)}</td>
                <td className="text-right py-1.5 px-1 tabular-nums text-muted">{fK(Math.round(spend / m.days))}</td>
                <td className="text-right py-1.5 px-1 tabular-nums font-bold">{fmt(units)}</td>
                <td className="text-right py-1.5 px-1 tabular-nums text-muted">{fmt(Math.round(units / m.days))}</td>
                <td className={`text-right py-1.5 px-1 tabular-nums font-bold ${stock <= 0 ? 'text-red-400' : 'text-muted'}`}>{fmt(stock)}</td>
                <td className={`text-right py-1.5 px-1 tabular-nums font-bold ${profit > 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fK(profit)}</td>
                <td className="text-right py-1.5 px-1 tabular-nums text-muted">${cpc.toFixed(3)}</td>
                <td className="text-right py-1.5 px-1 tabular-nums text-muted">{roas.toFixed(2)}×</td>
              </tr>
            );
          }); })()}
        </tbody>
      </table>
    </div>
  );
}

// ─── Step 5: Order Summary ───────────────────────────────
function StepOrder({ family: f, annualDemand, forecastByProduct, gap, orderQty, onQty, friendly, onFriendly, mode, onMode, manualByProduct, onManualQty }: {
  family: FamilyBaseline; annualDemand: number; forecastByProduct: Record<string, number>; gap: number; orderQty: number; onQty: (n: number) => void;
  friendly: boolean; onFriendly: (b: boolean) => void;
  mode: 'auto' | 'manual'; onMode: (m: 'auto' | 'manual') => void;
  manualByProduct: Record<string, number>; onManualQty: (name: string, qty: number) => void;
}) {
  const alloc = useMemo(() => allocateOrder(f.variations, orderQty, annualDemand, friendly, forecastByProduct), [f.variations, orderQty, annualDemand, friendly, forecastByProduct]);
  // Effective per-product order: manual mode = user quantities; auto mode = gap-share allocation.
  const byProduct: Record<string, number> = mode === 'manual'
    ? Object.fromEntries(f.variations.map(v => [v.name, manualByProduct[v.name] ?? 0]))
    : alloc.byProduct;
  const orderTotal = f.variations.reduce((s, v) => s + (byProduct[v.name] ?? 0), 0);
  let mfrCost = 0, shipCost = 0;
  for (const v of f.variations) {
    const qty = byProduct[v.name] ?? 0;
    mfrCost += qty * (MFR[v.name] ?? 0);
    shipCost += qty * (SHIP[v.name] ?? 0);
  }
  const costs = { mfr: mfrCost, ship: shipCost };
  // Per-product forecast demand (velocity-shaped — same per-variation basis as the order allocation)
  const fcstByProduct = useMemo(() => {
    const map: Record<string, number> = {};
    for (const v of f.variations) map[v.name] = Math.round(forecastByProduct[v.name] ?? 0);
    return map;
  }, [f.variations, forecastByProduct]);

  return (
    <div>
      <p className="text-muted mb-4">Review your order requirements. Adjust the target — each product rounds up to whole {friendly ? 'hundreds' : 'cartons'}.</p>
      <div className="grid grid-cols-3 gap-3 mb-5">
        <div className="p-4 rounded-xl bg-border/10 border border-border/30">
          <div className="text-[10px] text-muted mb-1">Forecast Demand</div>
          <div className="text-xl font-bold text-heading tabular-nums">{fmt(annualDemand)}</div>
        </div>
        <div className="p-4 rounded-xl bg-border/10 border border-border/30">
          <div className="text-[10px] text-muted mb-1">Current Stock</div>
          <div className="text-xl font-bold text-heading tabular-nums">{fmt(f.inventory)}</div>
          <div className="text-[9px] text-faint mt-1">
            {Object.entries(f.inventoryBySource).filter(([,v]) => v > 0).map(([k,v]) => `${k}: ${fmt(v)}`).join(' · ')}
          </div>
        </div>
        <div className="p-4 rounded-xl bg-border/10 border border-border/30">
          <div className="text-[10px] text-muted mb-1">Gap to Order</div>
          <div className={`text-xl font-bold tabular-nums ${gap > 0 ? 'text-red-400' : 'text-emerald-400'}`}>{gap > 0 ? fmt(gap) : 'Surplus'}</div>
        </div>
      </div>

      {/* Mode toggle + editable target + rounding toggle */}
      <div className="p-4 rounded-xl border border-blue-500/30 bg-blue-500/5 mb-4">
        <div className="flex items-center gap-2 mb-3">
          <span className="text-[10px] text-muted">Order by:</span>
          <button onClick={() => onMode('auto')}
            className={`px-2.5 py-1 rounded-md text-[10px] font-medium transition-colors ${mode === 'auto' ? 'bg-blue-500 text-white' : 'bg-border/30 text-muted hover:bg-border/50'}`}>Auto (family target)</button>
          <button onClick={() => onMode('manual')}
            className={`px-2.5 py-1 rounded-md text-[10px] font-medium transition-colors ${mode === 'manual' ? 'bg-blue-500 text-white' : 'bg-border/30 text-muted hover:bg-border/50'}`}>Manual (per product)</button>
        </div>
        <div className="flex items-center justify-between">
          <div>
            <div className="text-[11px] font-bold text-heading">{mode === 'manual' ? 'Order (manual per product)' : 'Order Target'}</div>
            <div className="text-[9px] text-muted mt-0.5">{mode === 'manual' ? 'Set each product below — rounds up to ' : 'Products round up to '}{friendly ? 'the next 100' : 'full cartons'}</div>
          </div>
          {mode === 'manual'
            ? <div className="w-28 px-3 py-2 rounded-lg bg-black/20 border border-blue-500/20 text-blue-300/70 text-right tabular-nums text-lg font-bold">{fmt(orderTotal)}</div>
            : <input type="number" value={orderQty} onChange={e => onQty(Number(e.target.value))}
                className="w-28 px-3 py-2 rounded-lg bg-black/30 border border-blue-500/30 text-blue-300 text-right tabular-nums text-lg font-bold" />}
        </div>
        <div className="flex items-center gap-2 mt-3 pt-3 border-t border-blue-500/20">
          <span className="text-[10px] text-muted">Rounding:</span>
          <button onClick={() => onFriendly(false)}
            className={`px-2.5 py-1 rounded-md text-[10px] font-medium transition-colors ${!friendly ? 'bg-blue-500 text-white' : 'bg-border/30 text-muted hover:bg-border/50'}`}>Cartons</button>
          <button onClick={() => onFriendly(true)}
            className={`px-2.5 py-1 rounded-md text-[10px] font-medium transition-colors ${friendly ? 'bg-blue-500 text-white' : 'bg-border/30 text-muted hover:bg-border/50'}`}>Friendly (100s)</button>
          <span className="ml-auto text-[10px] text-muted">Order total: <span className="text-heading font-bold tabular-nums">{fmt(orderTotal)}</span> units</span>
        </div>
        {orderTotal > 0 && (
          <div className="flex items-center gap-4 mt-3 pt-3 border-t border-blue-500/20 text-[10px]">
            <span className="text-muted">MFR: <span className="text-heading font-bold">{fK(costs.mfr)}</span></span>
            <span className="text-muted">Ship: <span className="text-heading font-bold">{fK(costs.ship)}</span></span>
            <span className="text-muted">Landed: <span className="text-heading font-bold">{fK(costs.mfr + costs.ship)}</span></span>
          </div>
        )}
      </div>

      {/* Per-variation breakdown */}
      <div className="text-[10px]">
        <div className="flex items-center justify-between text-muted font-medium mb-1">
          <span>Per-Variation</span>
          <div className="flex items-center gap-4">
            <span className="text-faint">stock</span>
            <span className="text-faint">forecast → order</span>
          </div>
        </div>
        {f.variations.map(v => {
          const qty = byProduct[v.name] ?? 0;
          const mfr = MFR[v.name] ?? 0;
          const ship = SHIP[v.name] ?? 0;
          const lot = !friendly && v.cartonQty > 1 ? `${Math.round(qty / v.cartonQty)} ct @ ${v.cartonQty}/box · ` : '';
          const srcParts = Object.entries(v.inventoryBySource).filter(([,val]) => val > 0).map(([k,val]) => `${k}: ${fmt(val)}`).join(' · ');
          return (
            <div key={v.name} className="flex items-center justify-between py-1.5 border-b border-border/20">
              <div>
                <span className="text-heading">{v.name}</span>
                {srcParts && <div className="text-[8px] text-faint mt-0.5">{srcParts}</div>}
              </div>
              <div className="flex items-center gap-4">
                <span className="tabular-nums text-heading font-medium w-12 text-right">{fmt(v.inventory)}</span>
                <span className="tabular-nums text-muted inline-flex items-center gap-1">
                  <span className="text-faint">{fmt(fcstByProduct[v.name] ?? 0)} →</span>
                  {mode === 'manual'
                    ? <input type="number" value={manualByProduct[v.name] ?? 0}
                        onChange={e => onManualQty(v.name, Number(e.target.value) || 0)}
                        onBlur={e => { const s = friendly ? 100 : (v.cartonQty > 0 ? v.cartonQty : 1); const raw = Number(e.target.value) || 0; onManualQty(v.name, raw > 0 ? Math.ceil(raw / s) * s : 0); }}
                        className="w-20 px-2 py-1 rounded bg-black/30 border border-blue-500/30 text-blue-300 text-right tabular-nums font-bold" />
                    : <span>{fmt(qty)} units</span>}
                  <span>· {lot}{fK(qty * (mfr + ship))}</span>
                </span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
