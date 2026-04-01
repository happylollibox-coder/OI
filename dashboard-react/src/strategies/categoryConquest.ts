import { Crosshair } from 'lucide-react';
import type { StrategyMeta } from './types';

export const CATEGORY_CONQUEST: StrategyMeta = {
  id: 'CATEGORY_CONQUEST',
  label: 'Category Conquest',
  icon: Crosshair,
  color: '#f59e0b',
  goal: 'Capture market share in category keywords where we can compete. Find new customer segments.',
  expectedOutcome: 'Discover profitable category terms. Build impression share on top 10-20 category keywords. Positive ROAS within 6-8 weeks.',
  keyMetrics: ['New keywords discovered', 'Category impression share', 'Discovery → Conversion rate', 'CPC trend'],
  chartMeasureIds: ['orders', 'conv_rate', 'net_roas', 'organic_pct'],
  kpiColumns: ['spend', 'orders', 'conv_rate', 'net_roas', 'search_terms'],
  learningQuestions: [
    { text: 'Which category terms have high volume and low competition?', dataCheck: 'has_search_terms' },
    { text: 'What is the typical path from discovery to profitability?', dataCheck: 'has_roas_data' },
    { text: 'Which product variations win in category searches?', dataCheck: 'has_orders_data' },
    { text: 'How does seasonality affect category performance?', dataCheck: 'has_completed' },
  ],
};
