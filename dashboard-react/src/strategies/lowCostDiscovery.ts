import { Eye } from 'lucide-react';
import type { StrategyMeta } from './types';

export const LOW_COST_DISCOVERY: StrategyMeta = {
  id: 'LOW_COST_DISCOVERY',
  label: 'Low Cost Discovery',
  icon: Eye,
  color: '#06b6d4',
  goal: 'Run ultra-low-bid campaigns to find cheap traffic and long-tail keywords that others miss.',
  expectedOutcome: 'Very low CPC (<$0.50). Low volume per term but high aggregate efficiency. Feed keyword pipeline cheaply.',
  keyMetrics: ['CPC', 'Terms per dollar', 'Long-tail finds', 'Aggregate ROAS'],
  chartMeasureIds: ['spend', 'net_roas', 'orders', 'conv_rate'],
  kpiColumns: ['spend', 'orders', 'cpc', 'net_roas', 'search_terms'],
  learningQuestions: [
    { text: 'What is the floor CPC to get impressions?', dataCheck: 'has_cpc_data' },
    { text: 'Which long-tail terms have surprising conversion rates?', dataCheck: 'has_conv_data' },
    { text: 'Is the volume sufficient to be meaningful?', dataCheck: 'has_orders_data' },
    { text: 'Do these terms overlap with higher-bid campaigns?', dataCheck: 'has_search_terms' },
  ],
};
