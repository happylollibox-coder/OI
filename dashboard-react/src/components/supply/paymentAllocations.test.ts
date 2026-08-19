import { describe, it, expect } from 'vitest';
import {
  parseAllocationIds,
  resolvePaymentAllocations,
  countOrphans,
  suggestOrphanTarget,
} from './paymentAllocations';

const pos = [
  { purchase_order_id: 'PO_20260515_SYLVIA_MintLolliBall_420' },
  { purchase_order_id: 'PO_20260515_SYLVIA_WhiteLolliBall_420' },
  { purchase_order_id: 'PO_20260515_SYLVIA_PurpleLolliBall_420' },
  { purchase_order_id: 'PO_20260515_SYLVIA_BlueLolliBall_420' },
  { purchase_order_id: 'PO_20260515_SYLVIA_PinkLolliBall_420' },
];

const otherPos = [
  { other_po_id: 'PO_20260226_ANNA_SAMPLING' },
  { other_po_id: 'PO_20260608_ANNA_CERTIFICATIONS' },
  { other_po_id: 'PO_20260608_ANNA_PHOTOGRAPHY' },
];

describe('parseAllocationIds', () => {
  it('splits and trims the cube STRING_AGG', () => {
    expect(parseAllocationIds('A, B ,C')).toEqual(['A', 'B', 'C']);
  });

  it('returns empty for null/blank', () => {
    expect(parseAllocationIds(null)).toEqual([]);
    expect(parseAllocationIds('')).toEqual([]);
    expect(parseAllocationIds(' , , ')).toEqual([]);
  });

  it('de-duplicates repeated ids', () => {
    expect(parseAllocationIds('A, B, A')).toEqual(['A', 'B']);
  });
});

describe('resolvePaymentAllocations', () => {
  it('classifies POs, Other-POs and orphans without dropping any', () => {
    const joined = [
      'PO_20260226_ANNA_SAMPLING',
      'PO_20260515_SYLVIA_MintLolliBall_420',
      'PO_20260515_SYLVIA_PinkLolliBall_420_1',
      'PO_20260608_ANNA_PHOTOGRAPHY',
    ].join(', ');
    const out = resolvePaymentAllocations(joined, pos, otherPos, true);
    expect(out).toHaveLength(4);
    expect(out.map((a) => a.kind)).toEqual(['other_po', 'po', 'orphan', 'other_po']);
  });

  it('is the regression guard: an unmatched id is never silently dropped', () => {
    const out = resolvePaymentAllocations('PO_DOES_NOT_EXIST', pos, otherPos, true);
    expect(out).toHaveLength(1);
    expect(out[0].kind).toBe('orphan');
  });

  it('attaches the matched row so the UI can render its figures', () => {
    const out = resolvePaymentAllocations('PO_20260515_SYLVIA_MintLolliBall_420', pos, otherPos, true);
    expect(out[0].po?.purchase_order_id).toBe('PO_20260515_SYLVIA_MintLolliBall_420');
    expect(out[0].otherPo).toBeUndefined();
  });

  it('preserves input order', () => {
    const out = resolvePaymentAllocations('PO_20260608_ANNA_PHOTOGRAPHY, PO_20260515_SYLVIA_BlueLolliBall_420', pos, otherPos, true);
    expect(out.map((a) => a.id)).toEqual(['PO_20260608_ANNA_PHOTOGRAPHY', 'PO_20260515_SYLVIA_BlueLolliBall_420']);
  });

  it('handles empty ledgers', () => {
    expect(resolvePaymentAllocations('A, B', [], [], true).map((a) => a.kind)).toEqual(['orphan', 'orphan']);
  });

  it('never claims "orphan" when the Other-PO ledger did not load', () => {
    // Flask down → otherPos is [] for reasons that have nothing to do with
    // the data. Real Other-POs must not be reported as missing money.
    const out = resolvePaymentAllocations(
      'PO_20260226_ANNA_SAMPLING, PO_20260515_SYLVIA_MintLolliBall_420',
      pos,
      [],
      false,
    );
    expect(out.map((a) => a.kind)).toEqual(['unknown', 'po']);
    expect(countOrphans(out)).toBe(0);
  });

  it('still resolves POs while the Other-PO ledger is unavailable', () => {
    const out = resolvePaymentAllocations('PO_20260515_SYLVIA_PinkLolliBall_420', pos, [], false);
    expect(out[0].kind).toBe('po');
  });
});

describe('countOrphans', () => {
  it('counts only true orphans', () => {
    const out = resolvePaymentAllocations(
      'PO_20260226_ANNA_SAMPLING, PO_20260515_SYLVIA_PinkLolliBall_420_1, PO_NOPE',
      pos,
      otherPos,
      true,
    );
    expect(countOrphans(out)).toBe(2);
  });

  it('is zero when everything resolves', () => {
    expect(countOrphans(resolvePaymentAllocations('PO_20260515_SYLVIA_BlueLolliBall_420', pos, otherPos, true))).toBe(0);
  });
});

describe('suggestOrphanTarget', () => {
  it('strips the collision suffix when the base PO exists', () => {
    expect(suggestOrphanTarget('PO_20260515_SYLVIA_PinkLolliBall_420_1', pos))
      .toBe('PO_20260515_SYLVIA_PinkLolliBall_420');
  });

  it('returns null when there is no suffix to strip', () => {
    expect(suggestOrphanTarget('PO_20260101_ANNA_OTHER', pos)).toBeNull();
  });

  it('returns null when the stripped id does not exist either', () => {
    expect(suggestOrphanTarget('PO_UNKNOWN_999_1', pos)).toBeNull();
  });

  it('does not mistake a quantity-only id for a suffixed one', () => {
    // stripping '_420' yields an id that is not in the ledger → no suggestion
    expect(suggestOrphanTarget('PO_20260515_SYLVIA_GreenLolliBall_420', pos)).toBeNull();
  });
});
