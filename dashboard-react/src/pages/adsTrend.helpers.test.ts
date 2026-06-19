import { describe, it, expect } from 'vitest';
import { withWindow } from './adsTrend.helpers';

describe('withWindow', () => {
  it('appends the window label to a count string', () => {
    expect(withWindow('82 active', 'week of Jun 8–14')).toBe('82 active · week of Jun 8–14');
  });
  it('returns the count unchanged when window is empty', () => {
    expect(withWindow('30 terms', '')).toBe('30 terms');
  });
});
