import { Search } from 'lucide-react';
import type { StrategyMeta } from './types';

// INTENT — the offense strategy of the intent-grouped campaign model
// (architecture/INTENT_CAMPAIGN_MODEL.md): one campaign per (family × match-type × intent theme),
// ≤10 keywords. Supersedes HUNTER (broad keyword hunting) and LOW_COST_DISCOVERY (cheap auto
// discovery), which merged into it on 2026-07-17 — INTENT runs on HUNTER's thresholds verbatim.
// Match type is an axis of the campaign grain, not a property of the strategy, so this one strategy
// spans auto, broad, exact and phrase campaigns alike.
export const INTENT: StrategyMeta = {
  id: 'BROAD_SP',
  label: 'Intent',
  icon: Search,
  color: '#10b981',
  goal: 'Group keywords by intent theme and find profitable demand — from cheap auto discovery through broad hunting. Feed the exact boost pipeline.',
  expectedOutcome: 'Discover 5-15 new converting keywords per week. Some graduate to Exact Boost. Expect lower initial ROAS while an intent theme is still being learned.',
  keyMetrics: ['New terms discovered', 'Terms graduated to Exact', 'Discovery ROAS', 'Unique search terms'],
  chartMeasureIds: ['orders', 'net_roas', 'spend', 'conv_rate'],
  kpiColumns: ['spend', 'orders', 'conv_rate', 'net_roas', 'search_terms'],
  learningQuestions: [
    { text: 'Are broad match keywords finding new converting terms?', dataCheck: 'has_search_terms' },
    { text: 'Which intent themes convert, and which only spend?', dataCheck: 'has_conv_data' },
    { text: 'What is the discovery-to-graduation rate?', dataCheck: 'has_completed' },
    { text: 'How many weeks does a term need to prove itself?', dataCheck: 'has_conv_data' },
    { text: 'What is the incremental organic lift from broad discovery?', dataCheck: 'has_organic_data' },
    { text: 'What budget level optimizes discovery?', dataCheck: 'has_spend_data' },
  ],
};
