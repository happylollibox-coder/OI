import { Search } from 'lucide-react';
import type { StrategyMeta } from './types';

export const HUNTER: StrategyMeta = {
  id: 'HUNTER',
  label: 'Hunter',
  icon: Search,
  color: '#10b981',
  goal: 'Aggressively find new profitable keywords through broad/auto campaigns. Feed exact boost pipeline.',
  expectedOutcome: 'Discover 5-15 new converting keywords per week. Some will graduate to Exact Boost. Expect lower initial ROAS.',
  keyMetrics: ['New terms discovered', 'Terms graduated to Exact', 'Discovery ROAS', 'Unique search terms'],
  chartMeasureIds: ['orders', 'net_roas', 'spend', 'conv_rate'],
  kpiColumns: ['spend', 'orders', 'conv_rate', 'net_roas', 'search_terms'],
  learningQuestions: [
    { text: 'Are broad match keywords finding new converting terms?', dataCheck: 'has_search_terms' },
    { text: 'What is the discovery-to-graduation rate?', dataCheck: 'has_completed' },
    { text: 'How many weeks does a term need to prove itself?', dataCheck: 'has_conv_data' },
    { text: 'What is the incremental organic lift from broad discovery?', dataCheck: 'has_organic_data' },
    { text: 'What budget level optimizes discovery?', dataCheck: 'has_spend_data' },
  ],
};
