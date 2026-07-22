import { HelpCircle } from 'lucide-react';
import type { StrategyMeta } from './types';

// UNCLASSIFIED — live campaigns that resolved to no strategy (no override, no experiment
// mapping, not Automatic-targeted, and no name-pattern match). A catch-all so nothing
// vanishes. Assign these in Admin ▸ Campaign Strategy to move them onto a real card.
export const UNCLASSIFIED: StrategyMeta = {
  id: 'UNCLASSIFIED',
  label: 'Unclassified',
  icon: HelpCircle,
  color: '#71717a',
  goal: 'Live campaigns not yet assigned a strategy. Assign them in Admin ▸ Campaign Strategy so they roll up to the right card.',
  expectedOutcome: 'This bucket should trend toward empty as campaigns get classified.',
  keyMetrics: ['Unassigned spend', 'Campaigns to classify'],
  chartMeasureIds: ['spend', 'orders', 'net_roas'],
  kpiColumns: ['spend', 'orders', 'conv_rate', 'cpc', 'net_roas'],
  learningQuestions: [],
};
