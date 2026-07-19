import { Sword } from 'lucide-react';
import type { StrategyMeta } from './types';

// COMPETITOR — renamed from COMPETITOR_CONQUEST on 2026-07-17, and absorbed CATEGORY_CONQUEST, whose
// campaigns were doing ASIN conquest rather than category targeting despite the name.
export const COMPETITOR: StrategyMeta = {
  id: 'COMPETITOR',
  label: 'Competitor',
  icon: Sword,
  color: '#ef4444',
  goal: 'Target competitor brand terms, product listings and categories to capture their traffic.',
  expectedOutcome: 'Win clicks from competitor searches. Expect lower conv rate than brand/exact (3-8%) but new customer acquisition.',
  keyMetrics: ['Clicks on competitor terms', 'Conv rate vs baseline', 'Cost per acquisition', 'ROAS'],
  chartMeasureIds: ['conv_rate', 'net_roas', 'orders', 'spend'],
  kpiColumns: ['spend', 'orders', 'conv_rate', 'cpc', 'net_roas'],
  learningQuestions: [
    { text: 'Which competitor terms convert for us?', dataCheck: 'has_conv_data' },
    { text: 'Is conquest profitable or only awareness-building?', dataCheck: 'has_roas_data' },
    { text: 'Do conquered customers have repeat purchase behavior?', dataCheck: 'has_completed' },
    { text: 'Which competitors are vulnerable to conquest?', dataCheck: 'has_search_terms' },
  ],
};
