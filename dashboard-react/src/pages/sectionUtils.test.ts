import { describe, it, expect } from 'vitest';
import { isBudgetRow, budgetTrimPerDay, launchToBaseAction, summarizeSection } from './sectionUtils';

describe('isBudgetRow', () => {
  it('is true for BUDGET action_type that is not BUDGET_OK', () => {
    expect(isBudgetRow({ action_type: 'BUDGET', action: 'GUARDIAN_BUDGET_DECREASE' })).toBe(true);
  });
  it('is false for BUDGET_OK (no-op)', () => {
    expect(isBudgetRow({ action_type: 'BUDGET', action: 'BUDGET_OK' })).toBe(false);
  });
  it('is false for non-budget rows', () => {
    expect(isBudgetRow({ action_type: 'TERM', action: 'NEGATE_TERM' })).toBe(false);
  });
});

describe('budgetTrimPerDay', () => {
  it('returns positive $ trimmed for a decrease', () => {
    expect(budgetTrimPerDay({ current_budget: 20, recommended_budget: 17 })).toBe(3);
  });
  it('returns 0 when budgets missing', () => {
    expect(budgetTrimPerDay({ current_budget: null, recommended_budget: null })).toBe(0);
  });
  it('returns 0 for an increase (clamped)', () => {
    expect(budgetTrimPerDay({ current_budget: 10, recommended_budget: 12 })).toBe(0);
  });
});

describe('launchToBaseAction', () => {
  it('maps LAUNCH_REDUCE_BID to REDUCE_BID with the launch bid', () => {
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_REDUCE_BID', launch_recommended_bid: 0.45, match_type: 'SEARCH_TERM' }))
      .toEqual({ action: 'REDUCE_BID', recommended_bid: 0.45 });
  });
  it('maps LAUNCH_NEGATE on a search term to NEGATE_TERM', () => {
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_NEGATE', match_type: 'SEARCH_TERM' }))
      .toEqual({ action: 'NEGATE_TERM', recommended_bid: null });
  });
  it('maps LAUNCH_NEGATE on an Automatic auto-clause to STOP_TARGET', () => {
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_NEGATE', match_type: 'Automatic', targeting: 'loose-match' }))
      .toEqual({ action: 'STOP_TARGET', recommended_bid: null });
  });
  it('maps LAUNCH_NEGATE on a product (asin=) target to STOP_TARGET', () => {
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_NEGATE', match_type: 'SEARCH_TERM', targeting: 'asin="B0123"' }))
      .toEqual({ action: 'STOP_TARGET', recommended_bid: null });
  });
  it('returns null for HOLD and GRADUATE (no-op)', () => {
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_HOLD' })).toBeNull();
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_GRADUATE' })).toBeNull();
  });
});

describe('summarizeSection', () => {
  it('counts actionable rows and sums the dollars', () => {
    const rows = [{ _dollars: 10 }, { _dollars: 5 }, { _dollars: 0 }];
    const s = summarizeSection(rows, r => r._dollars, () => true, () => false);
    expect(s).toEqual({ count: 3, dollars: 15, queueable: 3, queued: 0 });
  });
  it('separates queued from queueable', () => {
    const rows = [{ id: 'a' }, { id: 'b' }];
    const s = summarizeSection(rows, () => 0, () => true, r => r.id === 'a');
    expect(s).toEqual({ count: 2, dollars: 0, queueable: 1, queued: 1 });
  });
});
