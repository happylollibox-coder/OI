/**
 * NewPaymentModal — Create a new vendor payment.
 * Field parity with data-entry-app/templates/payment_form.html.
 *
 * Fields:
 *   vendor_name   (req) — segmented radio: SYLVIA | ANNA | JENNA
 *   payment_date  (req) — date input
 *   payment_amount (req) — number, must ≠ 0
 *   bank_fee      (opt) — number, min 0, default 0
 *   currency      (opt) — LOV CURRENCY, preselect is_default
 *   payment_method (req) — LOV PAYMENT_METHOD, preselect is_default
 *   purchase_order_id (opt) — searchable datalist from listOrders()
 *   shipment_id   (opt) — plain text input
 *   notes         (opt) — textarea
 *
 * Server generates payment_id — client sends raw input only.
 */
import { useCallback, useEffect, useId, useRef, useState } from 'react';
import { X, CreditCard } from 'lucide-react';
import {
  dataEntry,
  type CreatePaymentInput,
  type LovItem,
} from '../../utils/dataEntry';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const VENDORS = ['SYLVIA', 'ANNA', 'JENNA'] as const;
type VendorName = (typeof VENDORS)[number];

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface NewPaymentModalProps {
  onClose: () => void;
  onSaved: (paymentId: string) => void;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function NewPaymentModal({ onClose, onSaved }: NewPaymentModalProps) {
  const formId = useId();
  const datalistId = useId();

  // ── Field state ──
  const todayIso = new Date().toISOString().split('T')[0];
  const [vendorName, setVendorName] = useState<VendorName | ''>('');
  const [paymentDate, setPaymentDate] = useState(todayIso);
  const [paymentAmount, setPaymentAmount] = useState('');
  const [bankFee, setBankFee] = useState('0');
  const [currency, setCurrency] = useState('');
  const [paymentMethod, setPaymentMethod] = useState('');
  const [purchaseOrderId, setPurchaseOrderId] = useState('');
  const [shipmentId, setShipmentId] = useState('');
  const [notes, setNotes] = useState('');

  // ── LOVs ──
  const [currencies, setCurrencies] = useState<LovItem[]>([]);
  const [paymentMethods, setPaymentMethods] = useState<LovItem[]>([]);
  const [lovsLoading, setLovsLoading] = useState(true);

  // ── PO list (for datalist autocomplete) ──
  const [poIds, setPoIds] = useState<string[]>([]);

  // ── Submission ──
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const dateRef = useRef<HTMLInputElement>(null);

  // ── Focus date on mount ──
  useEffect(() => {
    dateRef.current?.focus();
  }, []);

  // ── Load LOVs ──
  useEffect(() => {
    let cancelled = false;
    dataEntry
      .getLovs()
      .then((lovs) => {
        if (cancelled) return;

        const curr: LovItem[] = lovs['CURRENCY'] ?? [];
        setCurrencies(curr);
        const defCurr = curr.find((c) => c.is_default);
        if (defCurr) setCurrency(defCurr.value_id);

        const methods: LovItem[] = lovs['PAYMENT_METHOD'] ?? [];
        setPaymentMethods(methods);
        const defMethod = methods.find((m) => m.is_default);
        if (defMethod) setPaymentMethod(defMethod.value_id);
      })
      .catch(() => {
        // Non-fatal — user can still manually select
      })
      .finally(() => {
        if (!cancelled) setLovsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // ── Load PO list for autocomplete ──
  useEffect(() => {
    let cancelled = false;
    dataEntry
      .listOrders()
      .then((orders) => {
        if (cancelled) return;
        const ids = orders
          .map((o) => o['purchase_order_id'] as string | undefined)
          .filter((id): id is string => Boolean(id));
        setPoIds(ids);
      })
      .catch(() => {
        // Non-fatal — datalist stays empty
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // ── Submit ──
  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      setError(null);

      if (!vendorName) {
        setError('Please select a vendor (SYLVIA, ANNA, or JENNA).');
        return;
      }
      if (!paymentDate) {
        setError('Payment date is required.');
        return;
      }
      const amount = parseFloat(paymentAmount);
      if (!paymentAmount || isNaN(amount) || amount === 0) {
        setError('Payment amount is required and must not be zero.');
        return;
      }
      if (!paymentMethod) {
        setError('Payment method (Paid From Account) is required.');
        return;
      }

      const input: CreatePaymentInput = {
        payment_date: paymentDate,
        payment_amount: amount,
        bank_fee: parseFloat(bankFee) || 0,
        currency: currency || undefined,
        payment_method: paymentMethod,
        vendor_name: vendorName,
        purchase_order_id: purchaseOrderId.trim() || undefined,
        shipment_id: shipmentId.trim() || undefined,
        notes: notes.trim() || undefined,
      };

      setSubmitting(true);
      try {
        const result = await dataEntry.createPayment(input);
        onSaved(result.payment_id);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unknown error');
        setSubmitting(false);
      }
    },
    [
      vendorName,
      paymentDate,
      paymentAmount,
      bankFee,
      currency,
      paymentMethod,
      purchaseOrderId,
      shipmentId,
      notes,
      onSaved,
    ],
  );

  // ── Backdrop click ──
  const handleBackdrop = useCallback(
    (e: React.MouseEvent) => {
      if (e.target === e.currentTarget) onClose();
    },
    [onClose],
  );

  // ── Shared class helpers ──
  const inputCls =
    'w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50';
  const labelCls =
    'text-[10px] text-faint uppercase tracking-wider font-semibold';

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: 'rgba(0,0,0,.6)', backdropFilter: 'blur(6px)' }}
      onClick={handleBackdrop}
    >
      <div
        className="relative w-full max-w-[640px] max-h-[90vh] rounded-2xl border border-border bg-card shadow-2xl overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* ─── Header ─── */}
        <div className="flex items-center justify-between px-5 py-3 border-b border-border bg-surface/50 shrink-0">
          <div className="flex items-center gap-2.5">
            <div
              className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0"
              style={{ background: '#10b98120' }}
            >
              <CreditCard size={16} className="text-emerald-400" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-heading">New Vendor Payment</h2>
              <p className="text-[10px] text-muted mt-0.5">
                Fill in payment details below
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg hover:bg-white/5 transition-colors text-muted hover:text-heading"
          >
            <X size={16} />
          </button>
        </div>

        {/* ─── Scrollable form body ─── */}
        <form
          id={formId}
          onSubmit={handleSubmit}
          className="flex-1 overflow-y-auto px-5 py-4 space-y-5"
          style={{
            scrollbarWidth: 'thin',
            scrollbarColor: 'var(--color-border) transparent',
          }}
        >
          {/* Error banner */}
          {error && (
            <div className="rounded-lg border border-[var(--color-negative)]/40 bg-[var(--color-negative)]/10 px-3 py-2.5 text-xs text-negative">
              {error}
            </div>
          )}

          {/* ── Vendor (segmented radio) ── */}
          <div className="flex flex-col gap-1.5">
            <span className={labelCls}>
              Vendor <span className="text-negative">*</span>
            </span>
            <div className="flex gap-2">
              {VENDORS.map((v) => {
                const selected = vendorName === v;
                return (
                  <button
                    key={v}
                    type="button"
                    onClick={() => setVendorName(v)}
                    className={`flex-1 rounded-lg border px-3 py-2 text-xs font-semibold transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50 ${
                      selected
                        ? 'border-emerald-500/60 bg-emerald-500/15 text-emerald-400'
                        : 'border-border bg-surface text-muted hover:text-heading hover:border-border-strong'
                    }`}
                  >
                    {v}
                  </button>
                );
              })}
            </div>
          </div>

          {/* ── Row: date + payment_method ── */}
          <div className="grid grid-cols-2 gap-4">
            {/* Payment Date */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>
                Payment Date <span className="text-negative">*</span>
              </label>
              <input
                ref={dateRef}
                type="date"
                required
                value={paymentDate}
                onChange={(e) => setPaymentDate(e.target.value)}
                className={inputCls}
              />
            </div>

            {/* Payment Method */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>
                Paid From Account <span className="text-negative">*</span>
              </label>
              <select
                required
                value={paymentMethod}
                onChange={(e) => setPaymentMethod(e.target.value)}
                className={inputCls}
                disabled={lovsLoading}
              >
                <option value="">
                  {lovsLoading ? 'Loading…' : '-- Select --'}
                </option>
                {paymentMethods.map((m) => (
                  <option key={m.value_id} value={m.value_id}>
                    {m.value_caption}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* ── Row: amount + bank_fee + currency ── */}
          <div className="grid grid-cols-3 gap-4">
            {/* Payment Amount */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>
                Amount <span className="text-negative">*</span>
              </label>
              <input
                type="number"
                step="any"
                required
                value={paymentAmount}
                onChange={(e) => setPaymentAmount(e.target.value)}
                placeholder="0.00"
                className={inputCls}
              />
            </div>

            {/* Bank Fee */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>Bank Fee</label>
              <input
                type="number"
                step="0.01"
                min="0"
                value={bankFee}
                onChange={(e) => setBankFee(e.target.value)}
                placeholder="0.00"
                className={inputCls}
              />
            </div>

            {/* Currency */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>Currency</label>
              <select
                value={currency}
                onChange={(e) => setCurrency(e.target.value)}
                className={inputCls}
                disabled={lovsLoading}
              >
                {lovsLoading ? (
                  <option value="">Loading…</option>
                ) : (
                  currencies.map((c) => (
                    <option key={c.value_id} value={c.value_id}>
                      {c.value_caption}
                    </option>
                  ))
                )}
              </select>
            </div>
          </div>

          {/* ── Optional links: PO + Shipment ── */}
          <div className="grid grid-cols-2 gap-4">
            {/* Purchase Order ID (searchable via datalist) */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>Purchase Order ID</label>
              <input
                type="text"
                list={datalistId}
                value={purchaseOrderId}
                onChange={(e) => setPurchaseOrderId(e.target.value)}
                placeholder="Optional — type or select"
                className={inputCls}
              />
              <datalist id={datalistId}>
                {poIds.map((id) => (
                  <option key={id} value={id} />
                ))}
              </datalist>
              <span className="text-[10px] text-faint">
                Links this payment to a PO
              </span>
            </div>

            {/* Shipment ID */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>Shipment ID</label>
              <input
                type="text"
                value={shipmentId}
                onChange={(e) => setShipmentId(e.target.value)}
                placeholder="Optional"
                className={inputCls}
              />
              <span className="text-[10px] text-faint">
                Links this payment to a shipment
              </span>
            </div>
          </div>

          {/* ── Notes ── */}
          <div className="flex flex-col gap-1">
            <label className={labelCls}>Notes</label>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={2}
              placeholder="Any additional information…"
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading resize-none focus:outline-none focus:ring-1 focus:ring-blue-500/50"
            />
          </div>
        </form>

        {/* ─── Footer actions ─── */}
        <div className="flex items-center justify-end gap-3 px-5 py-3 border-t border-border bg-surface/50 shrink-0">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 rounded-lg text-xs font-medium text-muted hover:text-heading border border-border hover:bg-white/5 transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            form={formId}
            disabled={submitting}
            className="px-4 py-2 rounded-lg text-xs font-semibold bg-emerald-600 hover:bg-emerald-500 text-white transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {submitting ? 'Saving…' : 'Save Payment'}
          </button>
        </div>
      </div>
    </div>
  );
}
