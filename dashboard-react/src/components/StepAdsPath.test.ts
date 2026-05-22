import { describe, it, expect } from 'vitest';
import { atK } from './StepAdsPath';

// Isolate non-brand: brand spend = 0 so adUnits == non-brand ad units.
const brand = { dailySpend: 0, cpc: 0.5, cvr: 0.03 };
const nb = { dailySpend: 100, cpc: 0.5, cvr: 0.025 };

describe('atK season-specific diminishing returns', () => {
  it('is anchored at k=1 (current spend unchanged)', () => {
    // nbAdUnits = (100/0.5) * 0.025 = 5
    for (const s of ['OFF', 'BOOST', 'PEAK'] as const) {
      expect(atK(1, brand, nb, 10, 0.7, s).adUnits).toBeCloseTo(5, 6);
    }
  });

  it('scales non-brand units by k^e with e = 1 - 0.10 - cvrExp per season', () => {
    const base = atK(1, brand, nb, 10, 0.7, 'PEAK').adUnits;
    expect(atK(4, brand, nb, 10, 0.7, 'PEAK').adUnits / base).toBeCloseTo(Math.pow(4, 0.65), 3);
    expect(atK(4, brand, nb, 10, 0.7, 'OFF').adUnits / base).toBeCloseTo(Math.pow(4, 0.58), 3);
    expect(atK(4, brand, nb, 10, 0.7, 'BOOST').adUnits / base).toBeCloseTo(Math.pow(4, 0.51), 3);
  });

  it('at 4x PEAK gives ~2.46x units, not the old linear 4x', () => {
    const base = atK(1, brand, nb, 10, 0.7, 'PEAK').adUnits;
    const ratio = atK(4, brand, nb, 10, 0.7, 'PEAK').adUnits / base;
    expect(ratio).toBeGreaterThan(2.3);
    expect(ratio).toBeLessThan(2.6);
  });
});
