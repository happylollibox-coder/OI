import { describe, it, expect } from 'vitest';
import { planFlush, dropSent } from './ppcLogSync';
import { changeLogKey, ChangeLogKeyable } from './ppcLogDedup';

// ─── helpers ────────────────────────────────────────────────────────────────

function entry(overrides: Partial<ChangeLogKeyable> = {}): ChangeLogKeyable {
  return {
    campaign_id: 'C1',
    action: 'INCREASE_BID',
    keyword_id: 'KW1',
    targeting: undefined,
    search_term: undefined,
    new_bid: 1.5,
    new_budget: null,
    applied_at: '2026-06-18T12:00:00.000Z',
    ...overrides,
  };
}

// ─── planFlush ───────────────────────────────────────────────────────────────
// Decides what to POST: new uploads + previously-failed pending, minus anything
// already confirmed-sent, deduped.

describe('planFlush', () => {
  it('returns all new entries when nothing is pending or sent', () => {
    const a = entry({ keyword_id: 'KW1' });
    const b = entry({ keyword_id: 'KW2' });
    const result = planFlush([], [a, b], new Set());
    expect(result).toHaveLength(2);
  });

  it('merges leftover pending with new entries', () => {
    const stuck = entry({ keyword_id: 'KW1' });
    const fresh = entry({ keyword_id: 'KW2' });
    const result = planFlush([stuck], [fresh], new Set());
    expect(result.map(r => r.keyword_id)).toEqual(['KW1', 'KW2']);
  });

  it('drops entries already confirmed sent', () => {
    const already = entry({ keyword_id: 'KW1' });
    const sent = new Set([changeLogKey(already)]);
    const result = planFlush([], [already], sent);
    expect(result).toHaveLength(0);
  });

  it('dedups a new entry that duplicates a still-pending one', () => {
    const stuck = entry({ keyword_id: 'KW1' });
    const dupOfStuck = entry({ keyword_id: 'KW1' });
    const result = planFlush([stuck], [dupOfStuck], new Set());
    expect(result).toHaveLength(1);
  });

  it('retry (no new entries) re-sends the pending set', () => {
    const stuck = entry({ keyword_id: 'KW1' });
    const result = planFlush([stuck], [], new Set());
    expect(result).toHaveLength(1);
  });
});

// ─── dropSent ─────────────────────────────────────────────────────────────────
// After a successful POST, remove only the entries we actually sent — preserving
// anything queued meanwhile (so a concurrent upload can't be silently wiped).

describe('dropSent', () => {
  it('removes entries whose key was just sent', () => {
    const a = entry({ keyword_id: 'KW1' });
    const b = entry({ keyword_id: 'KW2' });
    const sentKeys = new Set([changeLogKey(a)]);
    const result = dropSent([a, b], sentKeys);
    expect(result.map(r => r.keyword_id)).toEqual(['KW2']);
  });

  it('keeps an entry that was queued after the in-flight batch was captured', () => {
    const sent = entry({ keyword_id: 'KW1' });
    const queuedMeanwhile = entry({ keyword_id: 'KW2' });
    const result = dropSent([sent, queuedMeanwhile], new Set([changeLogKey(sent)]));
    expect(result).toEqual([queuedMeanwhile]);
  });

  it('returns empty when everything pending was sent', () => {
    const a = entry({ keyword_id: 'KW1' });
    const b = entry({ keyword_id: 'KW2' });
    const result = dropSent([a, b], new Set([changeLogKey(a), changeLogKey(b)]));
    expect(result).toHaveLength(0);
  });
});
