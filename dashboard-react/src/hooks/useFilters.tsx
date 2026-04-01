import { createContext, useContext, useState, useCallback, useMemo } from 'react';
import type { FamilyName, DashboardData } from '../types';
import { FAMILIES } from '../types';
import { experimentMatchesFamily, getCurrentWeekStart } from '../utils';
import type { AdsSeasonality } from '../seasonality';
import type { PeriodMode } from '../utils';

export type { PeriodMode };
/** Period Trend: 1-36, used only for trend charts. Non-trend always uses single period. */
export const PERIOD_TREND_DEFAULT = 4;

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
  periodType: 'regular',
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

/** Derive filter options from data, respecting cascading dependencies */
export function useFilterOptions(data: DashboardData, filters: GlobalFilters) {
  return useMemo(() => {
    const fam = filters.family;

    const families: FamilyName[] = Object.keys(FAMILIES) as FamilyName[];

    const famFromType = (pt: string) => {
      const l = (pt || '').toLowerCase();
      if (l.includes('lollibox') || l.includes('box')) return 'Lollibox';
      if (l.includes('lollime') || l.includes('mint') || l === 'me') return 'LolliME';
      if (l.includes('bottle') || l.includes('truth')) return 'Bottle';
      if (l.includes('fresh')) return 'Fresh';
      return null;
    };

    const products = (() => {
      const sqp = data.sqp_weekly || [];
      const byAsin: Record<string, { asin: string; name: string; orders: number }> = {};
      sqp.forEach(r => {
        if (fam && famFromType(r.product_type) !== fam) return;
        if (!byAsin[r.asin]) byAsin[r.asin] = { asin: r.asin, name: r.product_short_name || r.asin, orders: 0 };
        byAsin[r.asin].orders += r.orders || 0;
      });
      // Fallback: include products from DIM_PRODUCT when SQP data is sparse
      for (const p of (data.products || [])) {
        if (fam && famFromType(p.product_type || '') !== fam) continue;
        if (!byAsin[p.asin]) byAsin[p.asin] = { asin: p.asin, name: p.product_short_name || p.asin, orders: 0 };
      }
      return Object.values(byAsin).sort((a, b) => b.orders - a.orders);
    })();

    /** Data only starts Dec 24 2024 — hide incomplete periods before Jan 2025 */
    const DATA_START_DATE = '2025-01-01';

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

    const periods = filters.periodMode === 'weeks' ? weeks : filters.periodMode === 'month' ? months : years;

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
        if (fam && famFromType(r.product_type) !== fam) return;
        if (filters.product && r.asin !== filters.product) return;
        termOrders[r.search_term] = (termOrders[r.search_term] || 0) + (r.orders || 0);
      });
      return Object.entries(termOrders)
        .sort(([, a], [, b]) => b - a)
        .slice(0, 200)
        .map(([term, orders]) => ({ term, orders }));
    })();

    return { families, products, periods, weeks, months, years, experiments, keywords };
  }, [data, filters.family, filters.product, filters.periodMode]);
}
