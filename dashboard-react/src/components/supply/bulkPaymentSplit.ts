/**
 * Pure amount-allocation helpers for BulkPaymentModal (PO mode).
 * No React — kept separate so the split logic is unit-testable.
 */

/** Payment-level allocation mode for POs. */
export type PoPayMode = 'full' | 'partial';

/**
 * Split `total` equally across `ids`, returned as 2-decimal strings.
 * Leftover cents are distributed to the first ids so the parts sum exactly
 * to `total`. Non-positive / NaN totals yield empty strings (nothing to pay).
 */
export function splitEqually(total: number, ids: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  const n = ids.length;
  if (n === 0) return out;
  if (!isFinite(total) || total <= 0) {
    for (const id of ids) out[id] = '';
    return out;
  }
  const totalCents = Math.round(total * 100);
  const base = Math.floor(totalCents / n);
  let remainder = totalCents - base * n;
  for (const id of ids) {
    const cents = base + (remainder > 0 ? 1 : 0);
    if (remainder > 0) remainder -= 1;
    out[id] = (cents / 100).toFixed(2);
  }
  return out;
}

/**
 * Prefill each id with its remaining balance as a 2-decimal string.
 * Missing or non-positive balances become '0.00'.
 */
export function buildFullPrefill(
  ids: string[],
  balanceById: Record<string, number>,
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const id of ids) {
    const bal = balanceById[id] ?? 0;
    out[id] = bal > 0 ? bal.toFixed(2) : '0.00';
  }
  return out;
}
