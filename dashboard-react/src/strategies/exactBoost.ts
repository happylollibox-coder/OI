import { Target } from 'lucide-react';
import type { StrategyMeta } from './types';

export const EXACT_BOOST: StrategyMeta = {
  id: 'EXACT_BOOST',
  label: 'Exact Boost',
  icon: Target,
  color: '#3b82f6',
  goal: 'Boost specific high-converting keywords with exact match bidding to maximize conversions and organic rank',
  expectedOutcome: 'Improve keyword rank on target terms. Increase impression share, conversion rate, and organic visibility over 4-8 weeks.',
  keyMetrics: ['Impression Share', 'Organic Rank', 'Conv Rate', 'ROAS', 'Orders per keyword'],
  chartMeasureIds: ['conv_rate', 'net_roas', 'organic_pct', 'orders', 'spend'],
  kpiColumns: ['spend', 'orders', 'conv_rate', 'net_roas', 'search_terms'],
  learningQuestions: [
    { text: 'Which exact keywords convert best for each product?', dataCheck: 'has_conv_data' },
    { text: 'How much spend is needed to move organic rank?', dataCheck: 'has_organic_data' },
    { text: 'Do boosted terms maintain rank after reducing spend?', dataCheck: 'has_completed' },
    { text: 'What is the optimal bid level for each keyword?', dataCheck: 'has_cpc_data' },
  ],
};
