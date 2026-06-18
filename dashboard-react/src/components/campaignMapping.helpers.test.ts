import { describe, it, expect } from 'vitest';
import {
  needsMapping,
  approveAllEligible,
  friendlyStrategy,
  type CampaignMappingRow,
} from './campaignMapping.helpers';

const base: CampaignMappingRow = {
  campaign_id: 'c1',
  campaign_name: 'Camp 1',
  spend_60d: 100,
  current_experiment_id: null,
  current_experiment_name: null,
  current_strategy_id: null,
  suggested_family: null,
  suggested_strategy: null,
  suggested_experiment_id: null,
  confidence: null,
  source: 'unmapped',
};

describe('needsMapping', () => {
  it('is true for unmapped and default sources', () => {
    expect(needsMapping({ ...base, source: 'unmapped' })).toBe(true);
    expect(needsMapping({ ...base, source: 'default' })).toBe(true);
  });
  it('is false for manual and auto sources', () => {
    expect(needsMapping({ ...base, source: 'manual' })).toBe(false);
    expect(needsMapping({ ...base, source: 'auto' })).toBe(false);
  });
});

describe('approveAllEligible', () => {
  it('includes only needs-mapping rows with a complete suggestion', () => {
    const rows: CampaignMappingRow[] = [
      { ...base, campaign_id: 'a', source: 'unmapped', suggested_family: 'Bottle', suggested_strategy: 'HUNTER' },
      { ...base, campaign_id: 'b', source: 'default', suggested_family: 'Fresh', suggested_strategy: null },
      { ...base, campaign_id: 'c', source: 'manual', suggested_family: 'Bottle', suggested_strategy: 'HUNTER' },
      { ...base, campaign_id: 'd', source: 'unmapped', suggested_family: null, suggested_strategy: 'HUNTER' },
    ];
    expect(approveAllEligible(rows).map(r => r.campaign_id)).toEqual(['a']);
  });
});

describe('friendlyStrategy', () => {
  it('maps known ids to labels', () => {
    expect(friendlyStrategy('EXACT_BOOST')).toBe('Exact Boost');
  });
  it('falls back to the raw id for unknown', () => {
    expect(friendlyStrategy('WEIRD_NEW_STRAT')).toBe('WEIRD_NEW_STRAT');
  });
  it('returns a dash for null/empty', () => {
    expect(friendlyStrategy(null)).toBe('—');
  });
});
