/**
 * Pure header/financials helpers for PaymentDetailDrawer.
 * No React — kept separate so the multi-allocation logic is unit-testable.
 *
 * A payment is stored in DE_VENDOR_PAYMENTS as ONE ROW PER ALLOCATION
 * (per PO / per shipment). `get_payment_details` returns row 0 as the
 * summary, so `payment.payment_amount` is the FIRST allocation's amount —
 * never the payment's amount. The payment-level figures are the
 * `total_payment_amount` / `total_bank_fee` sums the backend adds.
 */

/** Coerce a possibly-string/null numeric field to a number. */
function n(v: unknown): number {
  const x = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(x) ? x : 0;
}

/** How many allocation rows this payment spans. */
export function paymentLineCount(
  summary: Record<string, unknown> | undefined,
  lines: unknown[] | undefined,
): number {
  const declared = Number(summary?.line_count);
  if (Number.isFinite(declared) && declared > 0) return declared;
  return lines?.length ?? 0;
}

/** True when the payment covers more than one PO/shipment allocation. */
export function isMultiAllocation(
  summary: Record<string, unknown> | undefined,
  lines: unknown[] | undefined,
): boolean {
  return paymentLineCount(summary, lines) > 1;
}

/**
 * Payment-level money for the header + FINANCIALS block.
 *
 * Prefers the backend's `total_*` sums; falls back to the row-0 values only
 * for single-allocation payments (and finally to the table row we were
 * opened from, before the detail fetch lands).
 */
export function paymentFinancials(
  summary: Record<string, unknown> | undefined,
  lines: unknown[] | undefined,
  fallback: { payment_amount: number; bank_fee: number },
): { amount: number; bankFee: number; total: number } {
  if (!summary) {
    return {
      amount: fallback.payment_amount,
      bankFee: fallback.bank_fee,
      total: fallback.payment_amount + fallback.bank_fee,
    };
  }
  const hasTotals = summary.total_payment_amount != null;
  const amount = hasTotals ? n(summary.total_payment_amount) : n(summary.payment_amount);
  const bankFee = summary.total_bank_fee != null
    ? n(summary.total_bank_fee)
    : (isMultiAllocation(summary, lines) ? 0 : n(summary.bank_fee));
  return { amount, bankFee, total: amount + bankFee };
}

/** Header fields the drawer's edit form can send. */
export interface PaymentHeaderFields {
  payment_date: string;
  payment_method: string;
  vendor_name: string;
  currency: string;
  notes: string;
  payment_amount: string;
  bank_fee: string;
}

/**
 * Body for PUT /api/payment/<id>.
 *
 * `update_payment` runs `UPDATE ... WHERE payment_id = @payment_id` with no
 * line filter, so `payment_amount` / `bank_fee` would be stamped onto EVERY
 * allocation row. Those two are per-allocation, so they are only ever sent
 * for a single-allocation payment; edit the amounts line-by-line otherwise.
 */
export function buildPaymentHeaderBody(
  fields: PaymentHeaderFields,
  multiAllocation: boolean,
): Record<string, unknown> {
  const body: Record<string, unknown> = {
    payment_date: fields.payment_date,
    payment_method: fields.payment_method,
    vendor_name: fields.vendor_name,
    currency: fields.currency,
    notes: fields.notes,
  };
  if (multiAllocation) return body;
  if (fields.payment_amount.trim() !== '') body.payment_amount = n(fields.payment_amount);
  if (fields.bank_fee.trim() !== '') body.bank_fee = n(fields.bank_fee);
  return body;
}
