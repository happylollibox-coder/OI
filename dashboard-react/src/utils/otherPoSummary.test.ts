import { describe, it, expect } from 'vitest';
import { summarizeConnectedOtherPos, type OtherPoLite } from './otherPoSummary';

const ALL: OtherPoLite[] = [
  { other_po_id: 'OPO_A', supplier_name: 'Freightco', service_type: 'Freight', total_amount: 100, currency: 'USD' },
  { other_po_id: 'OPO_B', supplier_name: 'CertLab', service_type: 'Certification', total_amount: 50.5, currency: 'USD' },
  { other_po_id: 'OPO_C', supplier_name: 'EuroShip', service_type: 'Customs', total_amount: 30, currency: 'EUR' },
];

describe('summarizeConnectedOtherPos', () => {
  it('returns zeros for an empty selection', () => {
    const s = summarizeConnectedOtherPos(ALL, []);
    expect(s).toEqual({ total: 0, count: 0, currencies: [], hasNonUsd: false });
  });

  it('sums selected USD amounts without flagging non-USD', () => {
    const s = summarizeConnectedOtherPos(ALL, ['OPO_A', 'OPO_B']);
    expect(s.total).toBeCloseTo(150.5);
    expect(s.count).toBe(2);
    expect(s.currencies).toEqual(['USD']);
    expect(s.hasNonUsd).toBe(false);
  });

  it('flags non-USD and lists distinct currencies', () => {
    const s = summarizeConnectedOtherPos(ALL, ['OPO_A', 'OPO_C']);
    expect(s.total).toBeCloseTo(130);
    expect(s.count).toBe(2);
    expect(s.currencies.sort()).toEqual(['EUR', 'USD']);
    expect(s.hasNonUsd).toBe(true);
  });

  it('ignores ids not present in the list and missing/zero amounts', () => {
    const withNull: OtherPoLite[] = [
      ...ALL,
      { other_po_id: 'OPO_D', supplier_name: null, service_type: null, total_amount: null, currency: null },
    ];
    const s = summarizeConnectedOtherPos(withNull, ['OPO_A', 'OPO_MISSING', 'OPO_D']);
    expect(s.total).toBeCloseTo(100);
    expect(s.count).toBe(2); // OPO_A + OPO_D matched; OPO_MISSING ignored
    expect(s.currencies).toEqual(['USD']); // OPO_D null currency defaults to USD
    expect(s.hasNonUsd).toBe(false);
  });
});
