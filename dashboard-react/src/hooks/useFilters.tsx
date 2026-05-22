import { createContext, useContext, useState, useCallback, useMemo } from 'react';
import type { FamilyName, DashboardData } from '../types';
import { FAMILIES } from '../types';
import { experimentMatchesFamily, getCurrentWeekStart, addDays } from '../utils';
import type { AdsSeasonality } from '../seasonality';
import type { PeriodMode } from '../utils';

export type { PeriodMode };
/** Period Trend: 1-36, used only for trend charts. Non-trend always uses single period. */
export const PERIOD_TREND_DEFAULT = 4;

export const famFromType = (pt: string | null) => {
  const l = (pt || '').toLowerCase();
  if (l.includes('lollibox') || l.includes('box') || l.includes('accessory')) return 'Lollibox';
  if (l.includes('lollime') || l.includes('mint') || l === 'me' || l.includes('art_craft')) return 'LolliME';
  if (l.includes('bottle') || l.includes('truth') || l.includes('tabletop')) return 'Bottle';
  if (l.includes('fresh') || l.includes('skin_care')) return 'Fresh';
  if (l.includes('ball') || l.includes('recreation')) return 'LolliBall';
  if (l.includes('bunny') || l.includes('keychain')) return 'Bunny';
  return null;
};

export type PeriodType = 'regular' | 'cumulative' | 'peak';

export interface GlobalFilters {
  family: FamilyName | null;
  product: string | null;
  periodMode: PeriodMode;
  /** 1-36. Used only for trend charts. Non-trend uses single period. */
  periodTrend: number;
  specificPeriod: string | null;
  periodType: PeriodType;
  experiment: string | null;
  keyword: string | null;
  seasonality: AdsSeasonality | null;
}

const DEFAULTS: GlobalFilters = {
  family: null,
  product: null,
  periodMode: 'weeks',
  periodTrend: PERIOD_TREND_DEFAULT,
  specificPeriod: null,
  periodType: 'current',
  experiment: null,
  keyword: null,
  seasonality: null,
};

interface FiltersContextValue {
  filters: GlobalFilters;
  setFilter: <K extends keyof GlobalFilters>(key: K, value: GlobalFilters[K]) => void;
  setFilters: (patch: Partial<GlobalFilters>) => void;
  resetFilters: () => void;
  activeCount: number;
}

const FiltersContext = createContext<FiltersContextValue>({
  filters: DEFAULTS,
  setFilter: () => {},
  setFilters: () => {},
  resetFilters: () => {},
  activeCount: 0,
});

export function FiltersProvider({ children }: { children: React.ReactNode }) {
  const [filters, _setFilters] = useState<GlobalFilters>(DEFAULTS);

  const setFilter = useCallback(<K extends keyof GlobalFilters>(key: K, value: GlobalFilters[K]) => {
    _setFilters(prev => {
      const next = { ...prev, [key]: value };
      if (key === 'family') {
        next.product = null;
      }
      if (key === 'periodMode') {
        next.specificPeriod = null;
      }
      return next;
    });
  }, []);

  const setFilters = useCallback((patch: Partial<GlobalFilters>) => {
    _setFilters(prev => ({ ...prev, ...patch }));
  }, []);

  const resetFilters = useCallback(() => _setFilters(DEFAULTS), []);

  const activeCount = useMemo(() => {
    let c = 0;
    if (filters.family) c++;
    if (filters.product) c++;
    if (filters.specificPeriod) c++;
    if (filters.experiment) c++;
    if (filters.keyword) c++;
    if (filters.seasonality) c++;
    return c;
  }, [filters]);

  return (
    <FiltersContext.Provider value={{ filters, setFilter, setFilters, resetFilters, activeCount }}>
      {children}
    </FiltersContext.Provider>
  );
}

export function useFilters() {
  return useContext(FiltersContext);
}

export type PeriodOption = { value: string; hasSqp: boolean; dataMaxDate?: string };

/** Derive filter options from data, respecting cascading dependencies */
export function useFilterOptions(data: DashboardData, filters: GlobalFilters, performanceMaxDate?: string) {
  return useMemo(() => {
    const fam = filters.family;

    const families: FamilyName[] = Object.keys(FAMILIES) as FamilyName[];



    const products = (() => {
      const sqp = data.sqp_weekly || [];
      const byAsin: Record<string, { asin: string; name: string; orders: number }> = {};
      sqp.forEach(r => {
        const f = r.family_name || famFromType(r.product_type);
        if (fam && f !== fam) return;
        if (!byAsin[r.asin]) byAsin[r.asin] = { asin: r.asin, name: r.product_short_name || r.asin, orders: 0 };
        byAsin[r.asin].orders += r.orders || 0;
      });
      // Fallback: include products from DIM_PRODUCT when SQP data is sparse
      for (const p of (data.products || [])) {
        const f = p.family_name || famFromType(p.product_type);
        if (fam && f !== fam) continue;
        if (!byAsin[p.asin]) byAsin[p.asin] = { asin: p.asin, name: p.product_short_name || p.asin, orders: 0 };
      }
      return Object.values(byAsin).sort((a, b) => b.orders - a.orders);
    })();

    /** Data only starts Dec 24 2024 — hide incomplete periods before Jan 2025 */
    const DATA_START_DATE = '2025-01-01';

    /** SQP coverage: set of week_starts that have SQP data */
    const sqpWeekSet = new Set((data.sqp_weekly || []).map(r => r.week_start).filter(Boolean));

    /** Check if a period has ANY SQP data based on period mode */
    const periodHasSqp = (periodValue: string, mode: typeof filters.periodMode): boolean => {
      if (sqpWeekSet.size === 0) return false;
      if (mode === 'date') {
        // Check if the date's week has SQP
        for (const ws of sqpWeekSet) {
          const weekEnd = addDays(ws, 6);
          if (periodValue >= ws && periodValue <= weekEnd) return true;
        }
        return false;
      }
      if (mode === 'weeks') return sqpWeekSet.has(periodValue);
      if (mode === 'month') {
        // YYYY-MM → check all sqp weeks in that month
        for (const ws of sqpWeekSet) {
          if (ws.slice(0, 7) === periodValue) return true;
        }
        return false;
      }
      if (mode === 'quarter') {
        // YYYY-QN → check sqp weeks in that quarter
        const y = parseInt(periodValue.slice(0, 4), 10);
        const q = parseInt(periodValue.slice(6, 7), 10);
        const startMonth = (q - 1) * 3 + 1;
        const endMonth = q * 3;
        for (const ws of sqpWeekSet) {
          const wsY = parseInt(ws.slice(0, 4), 10);
          const wsM = parseInt(ws.slice(5, 7), 10);
          if (wsY === y && wsM >= startMonth && wsM <= endMonth) return true;
        }
        return false;
      }
      // year
      for (const ws of sqpWeekSet) {
        if (ws.slice(0, 4) === periodValue) return true;
      }
      return false;
    };

    const weeks = (() => {
      const wt = data.weekly_trends || [];
      const ads = (data.ads_7d || []).map(r => (r as { week_start?: string }).week_start || '').filter(Boolean);
      const currentWeek = getCurrentWeekStart();
      return [...new Set([...wt.map(r => r.week_start || ''), ...ads])].filter(w => w >= DATA_START_DATE && w < currentWeek).sort().reverse();
    })();

    const months = (() => {
      const mt = data.monthly_trends || [];
      return [...new Set(mt.map(r => (r.month_start || '').slice(0, 7)))].filter(m => m >= DATA_START_DATE.slice(0, 7)).sort().reverse();
    })();

    const years = (() => {
      const mt = data.monthly_trends || [];
      const sqp = data.sqp_weekly || [];
      const fromMt = new Set(mt.map(r => (r.month_start || '').slice(0, 4)).filter(Boolean));
      const fromSqp = new Set(sqp.map(r => (r.week_start || '').slice(0, 4)).filter(Boolean));
      return [...new Set([...fromMt, ...fromSqp])].filter(y => y >= DATA_START_DATE.slice(0, 4)).sort().reverse();
    })();

    const quarters = (() => {
      const mt = data.monthly_trends || [];
      const qSet = new Set<string>();
      mt.forEach(r => {
        const ms = r.month_start || '';
        if (ms >= DATA_START_DATE) {
          const m = parseInt(ms.slice(5, 7), 10);
          const q = Math.ceil(m / 3);
          qSet.add(`${ms.slice(0, 4)}-Q${q}`);
        }
      });
      return [...qSet].sort().reverse();
    })();

    const dates = (() => {
      const ads = data.ads_7d || [];
      return [...new Set(ads.map(r => r.date || '').filter(Boolean))].filter(d => d >= DATA_START_DATE).sort().reverse();
    })();

    const periodsRaw = filters.periodMode === 'date' ? dates : filters.periodMode === 'weeks' ? weeks : filters.periodMode === 'month' ? months : filters.periodMode === 'quarter' ? quarters : years;

    /** Enriched periods with SQP coverage flag */
    const periodsEnriched: PeriodOption[] = periodsRaw.map(p => ({
      value: p,
      hasSqp: periodHasSqp(p, filters.periodMode),
    }));

    /** Flat period strings for backwards-compat (pages using periods as string[]) */
    const periods = periodsRaw;

    /** Current (in-progress) period — uses performanceMaxDate (Orders) as end boundary */
    const dataEnd = performanceMaxDate || '';
    const currentPeriod: PeriodOption | null = (() => {
      const now = new Date();
      const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
      if (filters.periodMode === 'date') {
        return { value: today, hasSqp: periodHasSqp(today, 'date'), dataMaxDate: dataEnd };
      }
      if (filters.periodMode === 'weeks') {
        const cw = getCurrentWeekStart();
        // Don't show current period if no data has reached this week yet
        if (dataEnd && dataEnd < cw) return null;
        // Only show if not already in the list (it shouldn't be, we filter it out above)
        if (!weeks.includes(cw)) return { value: cw, hasSqp: periodHasSqp(cw, 'weeks'), dataMaxDate: dataEnd };
        return null;
      }
      if (filters.periodMode === 'month') {
        const cm = today.slice(0, 7);
        if (!months.includes(cm)) return { value: cm, hasSqp: periodHasSqp(cm, 'month'), dataMaxDate: dataEnd };
        return null;
      }
      if (filters.periodMode === 'quarter') {
        const m = now.getMonth() + 1;
        const q = Math.ceil(m / 3);
        const cq = `${now.getFullYear()}-Q${q}`;
        if (!quarters.includes(cq)) return { value: cq, hasSqp: periodHasSqp(cq, 'quarter'), dataMaxDate: dataEnd };
        return null;
      }
      // year
      const cy = String(now.getFullYear());
      if (!years.includes(cy)) return { value: cy, hasSqp: periodHasSqp(cy, 'year'), dataMaxDate: dataEnd };
      return null;
    })();

    const experiments = (() => {
      const exps = data.experiments || [];
      return exps
        .filter(e => !fam || experimentMatchesFamily(e.experiment_name || e.experiment_id, fam))
        .map(e => ({ id: e.experiment_id, name: e.experiment_name, status: e.status }))
        .sort((a, b) => a.name.localeCompare(b.name));
    })();

    const keywords = (() => {
      const sqp = data.sqp_weekly || [];
      const termOrders: Record<string, number> = {};
      sqp.forEach(r => {
        if (fam && r.family_name !== fam) return;
        if (filters.product && r.asin !== filters.product) return;
        termOrders[r.search_term] = (termOrders[r.search_term] || 0) + (r.orders || 0);
      });
      return Object.entries(termOrders)
        .sort(([, a], [, b]) => b - a)
        .slice(0, 200)
        .map(([term, orders]) => ({ term, orders }));
    })();

    return { families, products, periods, periodsEnriched, currentPeriod, dates, weeks, months, quarters, years, experiments, keywords };
  }, [data, filters.family, filters.product, filters.periodMode, performanceMaxDate]);
}
