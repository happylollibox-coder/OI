import { Shield } from 'lucide-react';
import type { StrategyMeta } from './types';

export const PRODUCT_DEFENSE: StrategyMeta = {
  id: 'PRODUCT_DEFENSE',
  label: 'Product Defense',
  icon: Shield,
  color: '#ec4899',
  goal: 'Protect individual product listings by targeting product-specific keywords and sponsored display.',
  expectedOutcome: 'Reduce competitor ad presence on our product pages. Maintain conversion rate. Protect cross-sell opportunities.',
  keyMetrics: ['Product page impression share', 'Competitor ad frequency', 'Defense cost', 'Conv rate maintenance'],
  chartMeasureIds: ['spend', 'conv_rate', 'net_roas', 'organic_pct'],
  kpiColumns: ['spend', 'orders', 'conv_rate', 'net_roas', 'sales'],
  learningQuestions: [
    { text: 'Are we maintaining impression share on core terms?', dataCheck: 'has_organic_data' },
    { text: 'Is competitor share growing or shrinking?', dataCheck: 'has_spend_data' },
    { text: 'What is the cost-benefit of product defense?', dataCheck: 'has_roas_data' },
    { text: 'Does defense improve organic product metrics?', dataCheck: 'has_completed' },
  ],
};
