import { Sparkles } from 'lucide-react';
import type { StrategyMeta } from './types';

// AUTO — Amazon auto-targeting campaigns (SP/AUTO). The cheap discovery tier: let Amazon
// match placements/terms, then harvest converting terms into Intent/Exact. Resolved
// campaign-first via targeting_type='Automatic' (see V_CAMPAIGN_STRATEGY_RESOLVED), so it no
// longer hides inside INTENT discovery experiments.
export const AUTO: StrategyMeta = {
  id: 'AUTO',
  label: 'Auto',
  icon: Sparkles,
  color: '#eab308',
  goal: 'Amazon auto-targeting campaigns — discover converting placements and search terms cheaply, then harvest winners into Intent and Exact Boost.',
  expectedOutcome: 'Steady low-CPC discovery. Convert profitable auto terms into exact/broad targets; negate the money-bleeders.',
  keyMetrics: ['Discovery CPC', 'Converting terms harvested', 'Auto ROAS', 'Spend efficiency'],
  chartMeasureIds: ['spend', 'orders', 'net_roas', 'conv_rate'],
  kpiColumns: ['spend', 'orders', 'conv_rate', 'cpc', 'net_roas'],
  learningQuestions: [],
};
