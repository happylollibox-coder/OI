import type { GlobalFilters } from '../hooks/useFilters';
import { PERIOD_TREND_DEFAULT } from '../hooks/useFilters';
import { periodModeLabel, weekRangeLabel } from '../utils';
import { SEASONALITY_OPTIONS } from '../seasonality';

const MONTH_NAMES = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * Format global filters + section-specific overrides into human-readable labels for tooltips.
 * Only includes filters that have non-default values.
 */
export function formatSectionFilters(
  filters: GlobalFilters,
  sectionSpecific?: Record<string, string>
): string[] {
  const items: string[] = [];

  if (filters.family) items.push(`Family: ${filters.family}`);
  if (filters.product) items.push(`Product: ${filters.product}`);

  if (filters.specificPeriod) {
    const [y, m] = filters.specificPeriod.split('-');
    const monthStr = m ? MONTH_NAMES[parseInt(m, 10)] || m : '';
    const periodLabel =
      filters.periodMode === 'weeks'
        ? weekRangeLabel(filters.specificPeriod)
        : filters.periodMode === 'month'
          ? `${y}-${monthStr}`
          : y;
    items.push(`Period: ${periodLabel}`);
  } else {
    const modeLabel = filters.periodMode === 'weeks' ? 'Latest week with SQP' : `Latest ${periodModeLabel(filters.periodMode, 'lower')}`;
    items.push(`Period: ${modeLabel}`);
  }
  if (filters.periodTrend !== PERIOD_TREND_DEFAULT) {
    items.push(`Trend: ${filters.periodTrend} periods`);
  }

  if (filters.experiment) items.push(`Experiment: ${filters.experiment}`);
  if (filters.keyword) items.push(`Keyword: ${filters.keyword}`);

  if (filters.seasonality) {
    const label =
      SEASONALITY_OPTIONS.find(o => o.value === filters.seasonality)?.label ||
      filters.seasonality;
    items.push(`Seasonality: ${label}`);
  }

  if (sectionSpecific) {
    for (const [label, value] of Object.entries(sectionSpecific)) {
      if (value) items.push(`${label}: ${value}`);
    }
  }

  return items;
}
