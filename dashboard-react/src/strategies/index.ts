import { Target } from 'lucide-react';
import type { StrategyMeta } from './types';
import { ALL_CHART_MEASURES } from './chartMeasures';
import { EXACT_BOOST } from './exactBoost';
import { BRAND_DEFENSE } from './brandDefense';
import { COMPETITOR } from './competitor';
import { INTENT } from './intent';
import { PRODUCT_DEFENSE } from './productDefense';

// Consolidated 2026-07-17 (MIGRATE_STRATEGY_CONSOLIDATION): HUNTER + LOW_COST_DISCOVERY → INTENT,
// COMPETITOR_CONQUEST → COMPETITOR, CATEGORY_CONQUEST removed (folded into COMPETITOR).
const STRATEGIES: StrategyMeta[] = [
  EXACT_BOOST,
  BRAND_DEFENSE,
  COMPETITOR,
  INTENT,
  PRODUCT_DEFENSE,
];

export const STRATEGY_META: Record<string, StrategyMeta> = Object.fromEntries(
  STRATEGIES.map(s => [s.id, s])
);

export const DEFAULT_STRATEGY: StrategyMeta = {
  id: 'UNKNOWN',
  label: 'Unknown',
  icon: Target,
  color: '#888',
  goal: '',
  expectedOutcome: '',
  keyMetrics: [],
  learningQuestions: [],
  chartMeasureIds: ALL_CHART_MEASURES,
  kpiColumns: ['spend', 'orders', 'sales', 'conv_rate', 'cpc', 'net_roas'],
};

export const DEFAULT_KPI_COLUMNS: import('./types').KpiColumnId[] = ['spend', 'orders', 'sales', 'conv_rate', 'cpc', 'net_roas'];

export { CHART_MEASURE_META, ALL_CHART_MEASURES } from './chartMeasures';
export type { ChartMeasureId, QuestionToAnswer, QuestionStatus, DataCheck, KpiColumnId } from './types';
