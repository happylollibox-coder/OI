/**
 * NewPOModal — Create a new Purchase Order.
 * Field parity with data-entry-app/templates/order_form.html.
 *
 * Fields:
 *   Header: order_date (req), manufacturer_name (req, default "SYLVIA"),
 *           currency (LOV, preselect is_default), payment_status (PENDING/PAID),
 *           notes (optional)
 *   Lines:  product (ProductSelect, req), quantity (min 1, default 1),
 *           amount (step 0.01, min 0, req) — mapped to total_amount on submit
 *
 * Live: PO Total + Total Quantity update as user types.
 * Errors: inline red banner (no global toast system exists).
 */
import { useCallback, useEffect, useId, useRef, useState } from 'react';
import { X, Plus, Trash2, ShoppingCart } from 'lucide-react';
import { dataEntry, type CreatePOInput, type LovItem } from '../../utils/dataEntry';
import { ProductSelect } from './ProductSelect';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ProductLine {
  id: number;
  product_id: number | null;
  quantity: number;
  amount: string; // string so input is controlled without rounding issues
}

interface NewPOModalProps {
  onClose: () => void;
  onSaved: (poId: string) => void;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

let _lineKey = 0;
function nextKey(): number {
  return ++_lineKey;
}

function makeEmptyLine(): ProductLine {
  return { id: nextKey(), product_id: null, quantity: 1, amount: '' };
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function NewPOModal({ onClose, onSaved }: NewPOModalProps) {
  const formId = useId();

  // ── Header state ──
  const [orderDate, setOrderDate] = useState('');
  const [manufacturerName, setManufacturerName] = useState('SYLVIA');
  const [currency, setCurrency] = useState('');
  const [paymentStatus, setPaymentStatus] = useState('PENDING');
  const [notes, setNotes] = useState('');

  // ── LOVs ──
  const [currencies, setCurrencies] = useState<LovItem[]>([]);

  // ── Product lines ──
  const [lines, setLines] = useState<ProductLine[]>(() => [makeEmptyLine()]);

  // ── Submission ──
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // ── Focus date on mount ──
  const dateRef = useRef<HTMLInputElement>(null);
  useEffect(() => {
    dateRef.current?.focus();
  }, []);

  // ── Load LOVs ──
  useEffect(() => {
    let cancelled = false;
    dataEntry.getLovs().then((lovs) => {
      if (cancelled) return;
      const curr = lovs['CURRENCY'] ?? [];
      setCurrencies(curr);
      const def = curr.find((c) => c.is_default);
      if (def) setCurrency(def.value_id);
    }).catch(() => {
      // Non-fatal: currency will stay empty string, user can leave blank
    });
    return () => { cancelled = true; };
  }, []);

  // ── Live totals ──
  const poTotal = lines.reduce((sum, l) => sum + (parseFloat(l.amount) || 0), 0);
  const totalQty = lines.reduce((sum, l) => sum + (l.quantity || 0), 0);

  // ── Line helpers ──
  const updateLine = useCallback(<K extends keyof ProductLine>(id: number, key: K, value: ProductLine[K]) => {
    setLines((prev) => prev.map((l) => l.id === id ? { ...l, [key]: value } : l));
  }, []);

  const addLine = useCallback(() => {
    setLines((prev) => [...prev, makeEmptyLine()]);
  }, []);

  const removeLine = useCallback((id: number) => {
    setLines((prev) => {
      if (prev.length <= 1) return prev;
      return prev.filter((l) => l.id !== id);
    });
  }, []);

  // ── Submit ──
  const handleSubmit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const validLines = lines.filter(
      (l) => l.product_id !== null && l.quantity > 0,
    );

    if (validLines.length === 0) {
      setError('Add at least one product line with a product and quantity.');
      return;
    }

    const input: CreatePOInput = {
      order_date: orderDate,
      manufacturer_name: manufacturerName,
      currency: currency || undefined,
      payment_status: paymentStatus,
      notes: notes || undefined,
      product_lines: validLines.map((l) => ({
        product_id: l.product_id as number,
        quantity: l.quantity,
        total_amount: parseFloat(l.amount) || 0,
      })),
    };

    setSubmitting(true);
    try {
      const result = await dataEntry.createPO(input);
      onSaved(result.po_id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
      setSubmitting(false);
    }
  }, [lines, orderDate, manufacturerName, currency, paymentStatus, notes, onSaved]);

  // ── Backdrop click ──
  const handleBackdrop = useCallback((e: React.MouseEvent) => {
    if (e.target === e.currentTarget) onClose();
  }, [onClose]);

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
        className="relative w-full max-w-[720px] max-h-[90vh] rounded-2xl border border-border bg-card shadow-2xl overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* ─── Header ─── */}
        <div className="flex items-center justify-between px-5 py-3 border-b border-border bg-surface/50 shrink-0">
          <div className="flex items-center gap-2.5">
            <div
              className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0"
              style={{ background: '#3b82f620' }}
            >
              <ShoppingCart size={16} className="text-blue-400" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-heading">New Purchase Order</h2>
              <p className="text-[10px] text-muted mt-0.5">Fill in the details below</p>
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
          style={{ scrollbarWidth: 'thin', scrollbarColor: 'var(--color-border) transparent' }}
        >
          {/* Error banner */}
          {error && (
            <div className="rounded-lg border border-[var(--color-negative)]/40 bg-[var(--color-negative)]/10 px-3 py-2.5 text-xs text-negative">
              {error}
            </div>
          )}

          {/* ── Header fields ── */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            {/* Order Date */}
            <div className="flex flex-col gap-1">
              <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
                Order Date <span className="text-negative">*</span>
              </label>
              <input
                ref={dateRef}
                type="date"
                required
                value={orderDate}
                onChange={(e) => setOrderDate(e.target.value)}
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              />
            </div>

            {/* Manufacturer Name */}
            <div className="flex flex-col gap-1">
              <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
                Manufacturer <span className="text-negative">*</span>
              </label>
              <input
                type="text"
                required
                value={manufacturerName}
                onChange={(e) => setManufacturerName(e.target.value)}
                placeholder="SYLVIA"
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              />
            </div>

            {/* Currency */}
            <div className="flex flex-col gap-1">
              <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
                Currency
              </label>
              <select
                value={currency}
                onChange={(e) => setCurrency(e.target.value)}
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              >
                {currencies.length === 0 && (
                  <option value="">Loading…</option>
                )}
                {currencies.map((c) => (
                  <option key={c.value_id} value={c.value_id}>
                    {c.value_caption}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Payment Status */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="flex flex-col gap-1">
              <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
                Payment Status
              </label>
              <select
                value={paymentStatus}
                onChange={(e) => setPaymentStatus(e.target.value)}
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              >
                <option value="PENDING">Pending</option>
                <option value="PAID">Paid</option>
              </select>
            </div>
          </div>

          {/* Notes */}
          <div className="flex flex-col gap-1">
            <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
              Notes
            </label>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={2}
              placeholder="Any additional information…"
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading resize-none focus:outline-none focus:ring-1 focus:ring-blue-500/50"
            />
          </div>

          {/* ── Product Lines ── */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <span className="text-[10px] text-faint uppercase tracking-wider font-semibold">
                Product Lines
              </span>
              <button
                type="button"
                onClick={addLine}
                className="flex items-center gap-1 text-[11px] font-medium text-blue-400 hover:text-blue-300 transition-colors"
              >
                <Plus size={13} /> Add Product
              </button>
            </div>

            <div className="space-y-2">
              {lines.map((line) => (
                <div
                  key={line.id}
                  className="rounded-lg border border-border bg-surface/40 px-3 py-2.5"
                >
                  <div className="grid grid-cols-[1fr_80px_120px_auto] gap-3 items-end">
                    {/* Product */}
                    <div className="flex flex-col gap-1">
                      <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
                        Product <span className="text-negative">*</span>
                      </label>
                      <ProductSelect
                        value={line.product_id}
                        onChange={(id) => updateLine(line.id, 'product_id', id)}
                        required
                      />
                    </div>

                    {/* Quantity */}
                    <div className="flex flex-col gap-1">
                      <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
                        Qty <span className="text-negative">*</span>
                      </label>
                      <input
                        type="number"
                        min={1}
                        required
                        value={line.quantity}
                        onChange={(e) =>
                          updateLine(line.id, 'quantity', Math.max(1, parseInt(e.target.value, 10) || 1))
                        }
                        className="w-full rounded-lg border border-border bg-surface px-2 py-2 text-xs text-heading font-mono text-center focus:outline-none focus:ring-1 focus:ring-blue-500/50"
                      />
                    </div>

                    {/* Amount */}
                    <div className="flex flex-col gap-1">
                      <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
                        Amount <span className="text-negative">*</span>
                      </label>
                      <input
                        type="number"
                        step="0.01"
                        min="0"
                        required
                        value={line.amount}
                        onChange={(e) => updateLine(line.id, 'amount', e.target.value)}
                        placeholder="0.00"
                        className="w-full rounded-lg border border-border bg-surface px-2 py-2 text-xs text-heading font-mono text-right focus:outline-none focus:ring-1 focus:ring-blue-500/50"
                      />
                    </div>

                    {/* Remove */}
                    <div className="flex items-end pb-0.5">
                      <button
                        type="button"
                        onClick={() => removeLine(line.id)}
                        disabled={lines.length <= 1}
                        className="p-1.5 rounded-lg transition-colors text-muted hover:text-negative hover:bg-[var(--color-negative)]/10 disabled:opacity-20 disabled:cursor-not-allowed"
                        title="Remove line"
                      >
                        <Trash2 size={13} />
                      </button>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            {/* Live totals */}
            <div className="mt-3 flex justify-end">
              <div className="rounded-lg border border-border bg-surface/30 px-4 py-2.5 min-w-[200px]">
                <div className="flex items-center justify-between gap-8">
                  <span className="text-xs font-semibold text-heading">PO Total:</span>
                  <span className="text-sm font-bold font-mono text-blue-400">
                    {poTotal.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                  </span>
                </div>
                <div className="flex items-center justify-between gap-8 mt-0.5">
                  <span className="text-[10px] text-muted">Total Quantity:</span>
                  <span className="text-[10px] font-mono text-muted">{totalQty.toLocaleString()}</span>
                </div>
              </div>
            </div>
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
            className="px-4 py-2 rounded-lg text-xs font-semibold bg-blue-600 hover:bg-blue-500 text-white transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {submitting ? 'Saving…' : 'Save Purchase Order'}
          </button>
        </div>
      </div>
    </div>
  );
}
