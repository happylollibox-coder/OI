import { describe, it, expect } from 'vitest';
import { splitEqually, buildFullPrefill, sortPos, type SortablePo } from './bulkPaymentSplit';

const po = (o: Partial<SortablePo>): SortablePo => ({
  order_date: '2025-01-01',
  products: '',
  units: 0,
  manufacturer_name: '',
  unpaid_manufacturer: 0,
  ...o,
});

describe('sortPos', () => {
  const rows = [
    po({ order_date: '2025-03-01', products: 'B', units: 30, manufacturer_name: 'SYLVIA', unpaid_manufacturer: 5 }),
    po({ order_date: '2025-01-01', products: 'A', units: 10, manufacturer_name: 'ANNA', unpaid_manufacturer: 50 }),
    po({ order_date: '2025-02-01', products: 'C', units: 20, manufacturer_name: 'JENNA', unpaid_manufacturer: 500 }),
  ];

  it('sorts by date ascending (default view)', () => {
    const out = sortPos(rows, { key: 'date', dir: 'asc' });
    expect(out.map((r) => r.order_date)).toEqual(['2025-01-01', '2025-02-01', '2025-03-01']);
  });

  it('sorts by date descending', () => {
    const out = sortPos(rows, { key: 'date', dir: 'desc' });
    expect(out.map((r) => r.order_date)).toEqual(['2025-03-01', '2025-02-01', '2025-01-01']);
  });

  it('sorts by units numerically, not lexically', () => {
    const out = sortPos(rows, { key: 'units', dir: 'asc' });
    expect(out.map((r) => r.units)).toEqual([10, 20, 30]);
  });

  it('sorts by unpaid balance descending (largest owed first)', () => {
    const out = sortPos(rows, { key: 'unpaid', dir: 'desc' });
    expect(out.map((r) => r.unpaid_manufacturer)).toEqual([500, 50, 5]);
  });

  it('does not mutate the input array', () => {
    const copy = [...rows];
    sortPos(rows, { key: 'product', dir: 'desc' });
    expect(rows).toEqual(copy);
  });
});

describe('splitEqually', () => {
  it('splits evenly into 2-decimal strings that sum exactly to the total', () => {
    const out = splitEqually(100, ['a', 'b', 'c', 'd']);
    expect(out).toEqual({ a: '25.00', b: '25.00', c: '25.00', d: '25.00' });
  });

  it('puts leftover cents on the first ids so the split sums exactly', () => {
    const out = splitEqually(100, ['a', 'b', 'c']);
    expect(out).toEqual({ a: '33.34', b: '33.33', c: '33.33' });
    const sum = Object.values(out).reduce((s, v) => s + parseFloat(v), 0);
    expect(sum).toBeCloseTo(100, 2);
  });

  it('assigns the whole amount to a single id', () => {
    expect(splitEqually(250.5, ['x'])).toEqual({ x: '250.50' });
  });

  it('returns empty strings for a non-positive or NaN total', () => {
    expect(splitEqually(0, ['a', 'b'])).toEqual({ a: '', b: '' });
    expect(splitEqually(NaN, ['a'])).toEqual({ a: '' });
  });

  it('returns an empty object for no ids', () => {
    expect(splitEqually(100, [])).toEqual({});
  });
});

describe('buildFullPrefill', () => {
  it('maps each id to its remaining balance as a 2-decimal string', () => {
    const out = buildFullPrefill(['a', 'b'], { a: 1200.5, b: 300 });
    expect(out).toEqual({ a: '1200.50', b: '300.00' });
  });

  it('uses 0.00 for missing or non-positive balances', () => {
    const out = buildFullPrefill(['a', 'b'], { a: -5 });
    expect(out).toEqual({ a: '0.00', b: '0.00' });
  });
});
