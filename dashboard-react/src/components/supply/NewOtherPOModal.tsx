/**
 * NewOtherPOModal — Create a new Other PO (services/misc).
 * Field parity with data-entry-app/templates/other_po_form.html.
 *
 * Fields:
 *   order_date (req), service_type (req, text), supplier_name (req, text),
 *   product_asins (optional — add/remove tag list, sent as string[]),
 *   total_amount (number, step 0.01, default 0),
 *   currency (LOV, preselect is_default),
 *   notes (optional)
 *
 * Errors: inline red banner (no global toast system exists).
 */
import { useCallback, useEffect, useId, useRef, useState } from 'react';
import { X, Plus, Tag } from 'lucide-react';
import { dataEntry, type LovItem } from '../../utils/dataEntry';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface NewOtherPOModalProps {
  onClose: () => void;
  onSaved: (otherPoId: string) => void;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function NewOtherPOModal({ onClose, onSaved }: NewOtherPOModalProps) {
  const formId = useId();

  // ── Form state ──
  const [orderDate, setOrderDate] = useState('');
  const [serviceType, setServiceType] = useState('');
  const [supplierName, setSupplierName] = useState('');
  const [totalAmount, setTotalAmount] = useState('0');
  const [currency, setCurrency] = useState('');
  const [notes, setNotes] = useState('');

  // ── product_asins: add/remove tag list ──
  const [asins, setAsins] = useState<string[]>([]);
  const [asinInput, setAsinInput] = useState('');

  // ── LOVs ──
  const [currencies, setCurrencies] = useState<LovItem[]>([]);

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
      // Non-fatal: currency will stay empty, user can leave blank
    });
    return () => { cancelled = true; };
  }, []);

  // ── ASIN tag helpers ──
  const addAsin = useCallback(() => {
    const raw = asinInput.trim().toUpperCase();
    if (!raw) return;
    // Support comma-separated batch paste
    const tokens = raw.split(/[,\s]+/).map((t) => t.trim()).filter(Boolean);
    setAsins((prev) => {
      const next = [...prev];
      for (const t of tokens) {
        if (!next.includes(t)) next.push(t);
      }
      return next;
    });
    setAsinInput('');
  }, [asinInput]);

  const removeAsin = useCallback((asin: string) => {
    setAsins((prev) => prev.filter((a) => a !== asin));
  }, []);

  const handleAsinKeyDown = useCallback((e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' || e.key === ',') {
      e.preventDefault();
      addAsin();
    }
  }, [addAsin]);

  // ── Submit ──
  const handleSubmit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const body: Record<string, unknown> = {
      order_date: orderDate,
      service_type: serviceType,
      supplier_name: supplierName,
      product_asins: asins,
      total_amount: parseFloat(totalAmount) || 0,
      currency: currency || undefined,
      notes: notes || undefined,
    };

    setSubmitting(true);
    try {
      const result = await dataEntry.createOtherPO(body);
      onSaved(result.other_po_id);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
      setSubmitting(false);
    }
  }, [orderDate, serviceType, supplierName, asins, totalAmount, currency, notes, onSaved]);

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
        className="relative w-full max-w-[640px] max-h-[90vh] rounded-2xl border border-border bg-card shadow-2xl overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* ─── Header ─── */}
        <div className="flex items-center justify-between px-5 py-3 border-b border-border bg-surface/50 shrink-0">
          <div className="flex items-center gap-2.5">
            <div
              className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0"
              style={{ background: '#8b5cf620' }}
            >
              <Tag size={16} className="text-purple-400" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-heading">New Other PO (Services)</h2>
              <p className="text-[10px] text-muted mt-0.5">Service or miscellaneous purchase order</p>
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
          className="flex-1 overflow-y-auto px-5 py-4 space-y-4"
          style={{ scrollbarWidth: 'thin', scrollbarColor: 'var(--color-border) transparent' }}
        >
          {/* Error banner */}
          {error && (
            <div className="rounded-lg border border-[var(--color-negative)]/40 bg-[var(--color-negative)]/10 px-3 py-2.5 text-xs text-negative">
              {error}
            </div>
          )}

          {/* Row 1: Order Date + Service Type */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
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
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-purple-500/50"
              />
            </div>

            {/* Service Type */}
            <div className="flex flex-col gap-1">
              <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
                Service Type <span className="text-negative">*</span>
              </label>
              <input
                type="text"
                required
                value={serviceType}
                onChange={(e) => setServiceType(e.target.value)}
                placeholder="e.g. Freight, Photography…"
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-purple-500/50"
              />
            </div>
          </div>

          {/* Row 2: Supplier Name */}
          <div className="flex flex-col gap-1">
            <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
              Supplier Name <span className="text-negative">*</span>
            </label>
            <input
              type="text"
              required
              value={supplierName}
              onChange={(e) => setSupplierName(e.target.value)}
              placeholder="Supplier or vendor name"
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-purple-500/50"
            />
          </div>

          {/* Row 3: Related Products (ASINs) */}
          <div className="flex flex-col gap-1">
            <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
              Related Products (ASINs)
              <span className="ml-1 normal-case font-normal text-faint">(optional)</span>
            </label>

            {/* Tag list */}
            {asins.length > 0 && (
              <div className="flex flex-wrap gap-1.5 mb-1.5">
                {asins.map((asin) => (
                  <span
                    key={asin}
                    className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-purple-500/15 border border-purple-500/30 text-[10px] font-mono text-purple-300"
                  >
                    {asin}
                    <button
                      type="button"
                      onClick={() => removeAsin(asin)}
                      className="hover:text-white transition-colors ml-0.5"
                      title={`Remove ${asin}`}
                    >
                      <X size={9} />
                    </button>
                  </span>
                ))}
              </div>
            )}

            {/* Add input */}
            <div className="flex gap-2">
              <input
                type="text"
                value={asinInput}
                onChange={(e) => setAsinInput(e.target.value)}
                onKeyDown={handleAsinKeyDown}
                placeholder="Type ASIN or SKU, then press Enter or ,"
                className="flex-1 rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading font-mono focus:outline-none focus:ring-1 focus:ring-purple-500/50"
              />
              <button
                type="button"
                onClick={addAsin}
                disabled={!asinInput.trim()}
                className="flex items-center gap-1 px-3 py-2 rounded-lg border border-border text-[11px] font-medium text-muted hover:text-heading hover:bg-white/5 transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
              >
                <Plus size={12} /> Add
              </button>
            </div>
            <p className="text-[9px] text-faint">
              Comma-separated paste supported. Each ASIN/SKU will become a separate tag.
            </p>
          </div>

          {/* Row 4: Total Amount + Currency */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {/* Total Amount */}
            <div className="flex flex-col gap-1">
              <label className="text-[10px] text-faint uppercase tracking-wider font-semibold">
                Total Amount
              </label>
              <input
                type="number"
                step="0.01"
                min="0"
                value={totalAmount}
                onChange={(e) => setTotalAmount(e.target.value)}
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading font-mono focus:outline-none focus:ring-1 focus:ring-purple-500/50"
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
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-purple-500/50"
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
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading resize-none focus:outline-none focus:ring-1 focus:ring-purple-500/50"
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
            className="px-4 py-2 rounded-lg text-xs font-semibold bg-purple-600 hover:bg-purple-500 text-white transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {submitting ? 'Saving…' : 'Save Other PO'}
          </button>
        </div>
      </div>
    </div>
  );
}
