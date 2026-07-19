import { describe, it, expect } from 'vitest';
import { splitFamilies, suggestedTotal, applyOverrides, splitSummary, type FamilyRow } from './budgetWaterfall';

describe('splitFamilies', () => {
  it('floor + winners take the rest, and sums to the total', () => {
    const fams = [
      { parentName: 'Lollibox', weight: 139, netProfit: 139 },
      { parentName: 'LolliME', weight: 102, netProfit: 102 },
      { parentName: 'Fresh', weight: 0, netProfit: -31 },
      { parentName: 'Bottle', weight: 0, netProfit: -34 },
    ];
    const out = splitFamilies(fams, 700, 10);
    expect(Math.round(out.reduce((s, f) => s + f.allocated, 0))).toBe(700);
    expect(out.find(f => f.parentName === 'Fresh')!.allocated).toBe(10);
    const box = out.find(f => f.parentName === 'Lollibox')!.allocated;
    const me = out.find(f => f.parentName === 'LolliME')!.allocated;
    expect(box).toBeGreaterThan(me);
    expect(me).toBeGreaterThan(10);
  });

  it('all-zero weight splits the pot equally', () => {
    const out = splitFamilies([{ parentName: 'A', weight: 0, netProfit: -1 }, { parentName: 'B', weight: 0, netProfit: -2 }], 100, 10);
    expect(out[0].allocated).toBe(50);
    expect(out[1].allocated).toBe(50);
  });
});

describe('suggestedTotal', () => {
  it('margin spend / (proven% / 100)', () => {
    expect(suggestedTotal(375, 40)).toBe(938);   // current split ≈ current spend
    expect(suggestedTotal(375, 80)).toBe(469);   // 80/20 best practice → concentrate
    expect(suggestedTotal(375, 100)).toBe(375);  // winners only
  });
  it('guards against zero/negative proven%', () => {
    expect(suggestedTotal(375, 0)).toBe(0);
  });
});

describe('applyOverrides / splitSummary', () => {
  it('a manual override replaces the value and re-flags the source', () => {
    const rows: FamilyRow[] = [{ parentName: 'Lollibox', allocated: 400, source: 'WATERFALL' }];
    const out = applyOverrides(rows, { Lollibox: 250 });
    expect(out[0].allocated).toBe(250);
    expect(out[0].source).toBe('MANUAL');
  });
  it('splitSummary flags over-cap', () => {
    expect(splitSummary([{ allocated: 400 }, { allocated: 350 }], 700).overCap).toBe(true);
    expect(splitSummary([{ allocated: 400 }, { allocated: 300 }], 700).overCap).toBe(false);
  });
});
