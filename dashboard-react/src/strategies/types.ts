import type { LucideIcon } from 'lucide-react';

export type ChartMeasureId = 'spend' | 'sales' | 'orders' | 'conv_rate' | 'net_roas' | 'organic_pct';

export type DataCheck =
  | 'has_spend_data'
  | 'has_orders_data'
  | 'has_organic_data'
  | 'has_conv_data'
  | 'has_search_terms'
  | 'has_completed'
  | 'has_conclusions'
  | 'has_cpc_data'
  | 'has_roas_data';

export interface QuestionToAnswer {
  text: string;
  dataCheck: DataCheck;
}

export type QuestionStatus = 'answered' | 'has-data' | 'open';

export type KpiColumnId = 'spend' | 'orders' | 'sales' | 'conv_rate' | 'cpc' | 'net_roas' | 'search_terms' | 'organic_pct';

export interface StrategyMeta {
  id: string;
  label: string;
  icon: LucideIcon;
  color: string;
  goal: string;
  expectedOutcome: string;
  keyMetrics: string[];
  learningQuestions: QuestionToAnswer[];
  /** Ordered list of chart measures for this strategy. Drives trend charts. */
  chartMeasureIds?: ChartMeasureId[];
  /** Which KPI columns to show in the strategy performance table. Defaults to all. */
  kpiColumns?: KpiColumnId[];
}
