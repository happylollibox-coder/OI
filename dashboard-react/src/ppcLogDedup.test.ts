import { describe, it, expect } from 'vitest';
import { changeLogKey, dedupNewEntries, ChangeLogKeyable } from './ppcLogDedup';

// ─── helpers ────────────────────────────────────────────────────────────────

function entry(overrides: Partial<ChangeLogKeyable> = {}): ChangeLogKeyable {
  return {
    campaign_id: 'C1',
    action: 'Update Bid',
    keyword_id: 'KW1',
    targeting: undefined,
    search_term: undefined,
    new_bid: 1.5,
    new_budget: null,
    applied_at: '2026-06-14T12:00:00.000Z',
    ...overrides,
  };
}

// ─── changeLogKey ────────────────────────────────────────────────────────────

describe('changeLogKey', () => {
  it('same logical change with different applied_at TIME but same DAY → same key', () => {
    const a = entry({ applied_at: '2026-06-14T08:00:00.000Z' });
    const b = entry({ applied_at: '2026-06-14T23:59:59.999Z' });
    expect(changeLogKey(a)).toBe(changeLogKey(b));
  });

  it('different day → different key', () => {
    const a = entry({ applied_at: '2026-06-14T12:00:00.000Z' });
    const b = entry({ applied_at: '2026-06-15T12:00:00.000Z' });
    expect(changeLogKey(a)).not.toBe(changeLogKey(b));
  });

  it('different new_bid → different key', () => {
    const a = entry({ new_bid: 1.5 });
    const b = entry({ new_bid: 2.0 });
    expect(changeLogKey(a)).not.toBe(changeLogKey(b));
  });

  it('different campaign_id → different key', () => {
    const a = entry({ campaign_id: 'C1' });
    const b = entry({ campaign_id: 'C2' });
    expect(changeLogKey(a)).not.toBe(changeLogKey(b));
  });

  it('different action → different key', () => {
    const a = entry({ action: 'Update Bid' });
    const b = entry({ action: 'Negate' });
    expect(changeLogKey(a)).not.toBe(changeLogKey(b));
  });

  it('keyword_id preferred over targeting: same keyword_id, different targeting → same key', () => {
    const a = entry({ keyword_id: 'KW1', targeting: 'truth or dare' });
    const b = entry({ keyword_id: 'KW1', targeting: 'something else' });
    expect(changeLogKey(a)).toBe(changeLogKey(b));
  });

  it('targeting preferred over search_term when keyword_id absent', () => {
    const a = entry({ keyword_id: '', targeting: 'target-A', search_term: 'st-A' });
    const b = entry({ keyword_id: '', targeting: 'target-A', search_term: 'st-B' });
    const c = entry({ keyword_id: '', targeting: 'target-B', search_term: 'st-A' });
    expect(changeLogKey(a)).toBe(changeLogKey(b));
    expect(changeLogKey(a)).not.toBe(changeLogKey(c));
  });

  it('falls back to search_term when both keyword_id and targeting are absent/empty', () => {
    const a = entry({ keyword_id: '', targeting: '', search_term: 'st-X' });
    const b = entry({ keyword_id: '', targeting: '', search_term: 'st-X' });
    const c = entry({ keyword_id: '', targeting: '', search_term: 'st-Y' });
    expect(changeLogKey(a)).toBe(changeLogKey(b));
    expect(changeLogKey(a)).not.toBe(changeLogKey(c));
  });

  it('null new_bid and undefined new_bid both produce empty string segment → same key', () => {
    const a = entry({ new_bid: null });
    const b = entry({ new_bid: undefined });
    expect(changeLogKey(a)).toBe(changeLogKey(b));
  });

  it('different new_budget → different key', () => {
    const a = entry({ new_bid: null, new_budget: 50 });
    const b = entry({ new_bid: null, new_budget: 100 });
    expect(changeLogKey(a)).not.toBe(changeLogKey(b));
  });
});

// ─── dedupNewEntries ─────────────────────────────────────────────────────────

describe('dedupNewEntries', () => {
  it('collapses 3 identical entries to 1', () => {
    const e = entry();
    const result = dedupNewEntries([e, { ...e }, { ...e }], new Set());
    expect(result).toHaveLength(1);
    expect(result[0]).toBe(e); // first occurrence preserved
  });

  it('drops entries whose key is already in alreadySent', () => {
    const e = entry();
    const sent = new Set([changeLogKey(e)]);
    const result = dedupNewEntries([e], sent);
    expect(result).toHaveLength(0);
  });

  it('drops across-list duplicates AND alreadySent in one pass', () => {
    const e1 = entry({ keyword_id: 'KW1' });
    const e2 = entry({ keyword_id: 'KW2' });
    const e3 = entry({ keyword_id: 'KW1' }); // dup of e1
    const sent = new Set([changeLogKey(e2)]); // e2 already sent
    const result = dedupNewEntries([e1, e2, e3], sent);
    expect(result).toHaveLength(1);
    expect(result[0]).toBe(e1);
  });

  it('preserves order of first occurrences', () => {
    const e1 = entry({ keyword_id: 'KW1' });
    const e2 = entry({ keyword_id: 'KW2' });
    const e3 = entry({ keyword_id: 'KW3' });
    const result = dedupNewEntries([e1, e2, e3], new Set());
    expect(result.map(r => r.keyword_id)).toEqual(['KW1', 'KW2', 'KW3']);
  });

  it('two genuinely different changes are both kept', () => {
    const e1 = entry({ keyword_id: 'KW1', new_bid: 1.0 });
    const e2 = entry({ keyword_id: 'KW2', new_bid: 2.0 });
    const result = dedupNewEntries([e1, e2], new Set());
    expect(result).toHaveLength(2);
  });

  it('empty input returns empty array', () => {
    expect(dedupNewEntries([], new Set())).toEqual([]);
  });

  it('does not mutate alreadySent', () => {
    const e = entry();
    const sent = new Set<string>();
    dedupNewEntries([e, { ...e }], sent);
    expect(sent.size).toBe(0);
  });
});
