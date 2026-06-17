import { describe, it, expect } from 'vitest';
import { fitBadgeClass, fitBadgeLabel } from './fitBadge';

describe('fitBadgeClass', () => {
  it('green at/above 75 (promote-worthy)', () => {
    expect(fitBadgeClass(75)).toContain('emerald');
    expect(fitBadgeClass(90)).toContain('emerald');
  });
  it('amber in 40..74', () => {
    expect(fitBadgeClass(40)).toContain('amber');
    expect(fitBadgeClass(74)).toContain('amber');
  });
  it('faint below 40', () => {
    expect(fitBadgeClass(0)).toContain('faint');
    expect(fitBadgeClass(39)).toContain('faint');
  });
  it('null/undefined → empty (badge hidden by caller)', () => {
    expect(fitBadgeClass(null)).toBe('');
    expect(fitBadgeClass(undefined)).toBe('');
  });
});

describe('fitBadgeLabel', () => {
  it('formats rank as Fit NN (rounded)', () => {
    expect(fitBadgeLabel(82)).toBe('Fit 82');
    expect(fitBadgeLabel(81.6)).toBe('Fit 82');
  });
  it('null → empty', () => { expect(fitBadgeLabel(null)).toBe(''); });
});
