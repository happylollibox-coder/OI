import { describe, it, expect } from 'vitest';
import { splitOutcomes, type ScorecardSplitRow } from './decisionScorecard.helpers';

function row<T extends ScorecardSplitRow>(o: T): T { return o; }

const r = (verdict: string, applied_at: string | null, id: string) =>
  row({ verdict, applied_at, id });

describe('splitOutcomes', () => {
  it('puts TOO_EARLY in pending and everything else in settled', () => {
    const rows = [
      r('TOO_EARLY', '2026-06-18T00:00:00Z', 'a'),
      r('IMPROVED', '2026-06-10T00:00:00Z', 'b'),
      r('WORSE', '2026-06-11T00:00:00Z', 'c'),
      r('NO_DATA', '2026-06-12T00:00:00Z', 'd'),
    ];
    const { pending, settled } = splitOutcomes(rows);
    expect(pending.map(x => x.id)).toEqual(['a']);
    expect(settled.map(x => x.id).sort()).toEqual(['b', 'c', 'd']);
  });

  it('sorts pending by creation date ascending (oldest first)', () => {
    const rows = [
      r('TOO_EARLY', '2026-06-18T00:00:00Z', 'new'),
      r('TOO_EARLY', '2026-06-14T00:00:00Z', 'old'),
      r('TOO_EARLY', '2026-06-16T00:00:00Z', 'mid'),
    ];
    expect(splitOutcomes(rows).pending.map(x => x.id)).toEqual(['old', 'mid', 'new']);
  });

  it('sorts settled by creation date descending (newest first)', () => {
    const rows = [
      r('IMPROVED', '2026-06-10T00:00:00Z', 'old'),
      r('WORSE', '2026-06-17T00:00:00Z', 'new'),
      r('NO_DATA', '2026-06-13T00:00:00Z', 'mid'),
    ];
    expect(splitOutcomes(rows).settled.map(x => x.id)).toEqual(['new', 'mid', 'old']);
  });

  it('handles null applied_at without throwing', () => {
    const rows = [
      r('TOO_EARLY', null, 'p'),
      r('IMPROVED', null, 's'),
    ];
    const { pending, settled } = splitOutcomes(rows);
    expect(pending.map(x => x.id)).toEqual(['p']);
    expect(settled.map(x => x.id)).toEqual(['s']);
  });

  it('returns empty arrays for empty input', () => {
    expect(splitOutcomes([])).toEqual({ pending: [], settled: [] });
  });
});
