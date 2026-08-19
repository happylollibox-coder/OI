import { describe, it, expect } from 'vitest';
import {
  paymentFinancials,
  buildPaymentHeaderBody,
  isMultiAllocation,
  paymentLineCount,
  type PaymentHeaderFields,
} from './paymentHeader';

/* PAY_20260608_ANNA_5P_MAY_2026 as the backend actually returns it:
   12 allocation rows, row 0 = PO_20260226_ANNA_SAMPLING @ $51.73,
   allocations summing to $7,629.63 with $69.29 of bank fees. */
const multiSummary = {
  payment_id: 'PAY_20260608_ANNA_5P_MAY_2026',
  purchase_order_id: 'PO_20260226_ANNA_SAMPLING',
  payment_amount: 51.73,
  bank_fee: null,
  total_payment_amount: 7629.63,
  total_bank_fee: 69.29,
  line_count: 12,
};
const multiLines = Array.from({ length: 12 }, (_, i) => ({ line_id: i }));

const singleSummary = {
  payment_id: 'PAY_20260705_SYLVIA_1P_JUL_2026',
  payment_amount: 3855.32,
  bank_fee: 35.06,
  total_payment_amount: 3855.32,
  total_bank_fee: 35.06,
  line_count: 1,
};

const fallback = { payment_amount: 7629.63, bank_fee: 69.29 };

const fields = (o: Partial<PaymentHeaderFields> = {}): PaymentHeaderFields => ({
  payment_date: '2026-06-08',
  payment_method: 'Account Payoneer',
  vendor_name: 'ANNA',
  currency: 'USD',
  notes: 'PAID TO SYLIVA THROW ANNAS ACCOUNT',
  payment_amount: '51.73',
  bank_fee: '',
  ...o,
});

describe('paymentLineCount / isMultiAllocation', () => {
  it('uses the backend line_count', () => {
    expect(paymentLineCount(multiSummary, undefined)).toBe(12);
    expect(isMultiAllocation(multiSummary, undefined)).toBe(true);
  });

  it('falls back to the lines array when line_count is absent', () => {
    expect(paymentLineCount({ payment_amount: 1 }, multiLines)).toBe(12);
  });

  it('treats a one-line payment as single-allocation', () => {
    expect(isMultiAllocation(singleSummary, [{}])).toBe(false);
  });
});

describe('paymentFinancials', () => {
  it('shows the payment total, not the first allocation', () => {
    const f = paymentFinancials(multiSummary, multiLines, fallback);
    expect(f.amount).toBe(7629.63);
    expect(f.bankFee).toBe(69.29);
    expect(f.total).toBeCloseTo(7698.92, 2);
  });

  it('never reports the row-0 amount for a multi-allocation payment', () => {
    expect(paymentFinancials(multiSummary, multiLines, fallback).amount).not.toBe(51.73);
  });

  it('is unchanged for a single-allocation payment', () => {
    const f = paymentFinancials(singleSummary, [{}], { payment_amount: 0, bank_fee: 0 });
    expect(f.amount).toBe(3855.32);
    expect(f.total).toBeCloseTo(3890.38, 2);
  });

  it('falls back to the table row before the detail fetch lands', () => {
    const f = paymentFinancials(undefined, undefined, fallback);
    expect(f.total).toBeCloseTo(7698.92, 2);
  });

  it('coerces string-typed numerics from BigQuery', () => {
    const f = paymentFinancials(
      { total_payment_amount: '7629.63', total_bank_fee: '69.29', line_count: 12 },
      multiLines,
      fallback,
    );
    expect(f.amount).toBe(7629.63);
  });
});

describe('buildPaymentHeaderBody', () => {
  it('omits payment_amount and bank_fee on a multi-allocation payment', () => {
    const body = buildPaymentHeaderBody(fields(), true);
    expect(body).not.toHaveProperty('payment_amount');
    expect(body).not.toHaveProperty('bank_fee');
    expect(body.notes).toBe('PAID TO SYLIVA THROW ANNAS ACCOUNT');
    expect(body.vendor_name).toBe('ANNA');
  });

  it('still sends the amount for a single-allocation payment', () => {
    const body = buildPaymentHeaderBody(fields({ payment_amount: '3855.32', bank_fee: '35.06' }), false);
    expect(body.payment_amount).toBe(3855.32);
    expect(body.bank_fee).toBe(35.06);
  });

  it('omits blank amount fields', () => {
    const body = buildPaymentHeaderBody(fields({ payment_amount: '', bank_fee: '' }), false);
    expect(body).not.toHaveProperty('payment_amount');
    expect(body).not.toHaveProperty('bank_fee');
  });
});
