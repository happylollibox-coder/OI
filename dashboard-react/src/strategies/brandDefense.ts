import { Shield } from 'lucide-react';
import type { StrategyMeta } from './types';

export const BRAND_DEFENSE: StrategyMeta = {
  id: 'BRAND_DEFENSE',
  label: 'Brand Defense',
  icon: Shield,
  color: '#a855f7',
  goal: 'Protect brand keywords from competitor conquest. Ensure when shoppers search for our brand, they find us first.',
  expectedOutcome: 'Maintain >80% impression share on brand terms. Keep CPC low. Prevent competitor ads from appearing above our listings.',
  keyMetrics: ['Brand Impression Share', 'CPC on brand terms', 'Competitor presence', 'Organic rank on brand'],
  chartMeasureIds: ['organic_pct', 'net_roas', 'spend', 'conv_rate'],
  kpiColumns: ['spend', 'orders', 'conv_rate', 'cpc', 'net_roas'],
  learningQuestions: [
    { text: 'Are competitors bidding on our brand terms?', dataCheck: 'has_spend_data' },
    { text: 'What is the cost of defending brand terms?', dataCheck: 'has_cpc_data' },
    { text: 'Does brand defense increase organic brand visibility?', dataCheck: 'has_organic_data' },
    { text: 'Which brand term variations need defense?', dataCheck: 'has_search_terms' },
  ],
};
