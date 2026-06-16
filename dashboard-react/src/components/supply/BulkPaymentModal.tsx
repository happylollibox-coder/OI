/**
 * BulkPaymentModal — Pay multiple shipments or POs in one shared payment.
 *
 * Modes:
 *   shipments — candidate list from SupplyShipmentRow[], prefills unpaid_to_shipment
 *   pos       — candidate list from SupplyPORow[] + SupplyOtherPORow[], no prefill
 *
 * Shared header fields (mirrors NewPaymentModal):
 *   vendor_name (req) — segmented radio SYLVIA | ANNA | JENNA
 *   payment_date (req) — date input
 *   payment_method (req) — LOV PAYMENT_METHOD
 *   currency (opt) — LOV CURRENCY, is_default
 *   bank_fee (opt) — default 0
 *   notes (opt)
 *
 * Candidate grid: checkbox + amount input per row.
 * Submit: collect checked rows with amount > 0 → parallel arrays → bulk endpoint.
 * On success: onSaved(payment_id, created). Error inline banner, form kept open.
 */
import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react';
import { X, CreditCard, Package, Truck } from 'lucide-react';
import {
  dataEntry,
  type LovItem,
} from '../../utils/dataEntry';
import type { SupplyShipmentRow, SupplyPORow, SupplyOtherPORow } from '../../types';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const VENDORS = ['SYLVIA', 'ANNA', 'JENNA'] as const;
type VendorName = (typeof VENDORS)[number];
type Mode = 'shipments' | 'pos';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface BulkPaymentModalProps {
  mode?: Mode;
  shipments: SupplyShipmentRow[];
  pos: SupplyPORow[];
  otherPos?: SupplyOtherPORow[];
  onClose: () => void;
  onSaved: (paymentId: string, created: number) => void;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const fmtAmt = (v: number) =>
  `$${v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/** Compute the default prefill map for shipments mode. */
function buildShipmentPrefill(shipments: SupplyShipmentRow[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const s of shipments) {
    const v = s.unpaid_to_shipment > 0 ? s.unpaid_to_shipment : s.cost_shipped > 0 ? s.cost_shipped : 0;
    if (v > 0) out[s.shipment_id] = String(v);
  }
  return out;
}

/**
 * Deduplicate PO rows by purchase_order_id, summing unpaid_manufacturer.
 * Multiple product lines share the same PO.
 */
function dedupePos(pos: SupplyPORow[]): Array<{ purchase_order_id: string; manufacturer_name: string; unpaid_manufacturer: number }> {
  const seen = new Map<string, { purchase_order_id: string; manufacturer_name: string; unpaid_manufacturer: number }>();
  for (const p of pos) {
    const id = p.purchase_order_id;
    if (seen.has(id)) {
      seen.get(id)!.unpaid_manufacturer += Math.max(p.unpaid_manufacturer, 0);
    } else {
      seen.set(id, {
        purchase_order_id: id,
        manufacturer_name: p.manufacturer_name,
        unpaid_manufacturer: Math.max(p.unpaid_manufacturer, 0),
      });
    }
  }
  return Array.from(seen.values());
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function BulkPaymentModal({
  mode: initialMode = 'shipments',
  shipments,
  pos,
  otherPos = [],
  onClose,
  onSaved,
}: BulkPaymentModalProps) {
  const formId = useId();

  // ── Mode — reset selection on change via the click handler directly ──
  const [mode, setMode] = useState<Mode>(initialMode);

  // ── Header field state ──
  const todayIso = new Date().toISOString().split('T')[0];
  const [vendorName, setVendorName] = useState<VendorName | ''>('');
  const [paymentDate, setPaymentDate] = useState(todayIso);
  const [bankFee, setBankFee] = useState('0');
  const [currency, setCurrency] = useState('');
  const [paymentMethod, setPaymentMethod] = useState('');
  const [notes, setNotes] = useState('');

  // ── LOVs ──
  const [currencies, setCurrencies] = useState<LovItem[]>([]);
  const [paymentMethods, setPaymentMethods] = useState<LovItem[]>([]);
  const [lovsLoading, setLovsLoading] = useState(true);

  // ── Candidate grid: checked ids + amounts ──
  // Key: shipment_id or po_id
  const [checkedIds, setCheckedIds] = useState<Set<string>>(new Set());
  // Amounts start pre-seeded from the initial mode's prefill
  const [amounts, setAmounts] = useState<Record<string, string>>(() =>
    initialMode === 'shipments' ? buildShipmentPrefill(shipments) : {},
  );

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
        // Non-fatal
      })
      .finally(() => {
        if (!cancelled) setLovsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // ── Mode change handler: resets selection + re-seeds prefill ──
  // shipments prop is closed over; this is called in a click handler (not during render)
  // so the latest value is always captured correctly.
  const handleModeChange = useCallback((m: Mode) => {
    setMode(m);
    setCheckedIds(new Set());
    setAmounts(m === 'shipments' ? buildShipmentPrefill(shipments) : {});
  }, [shipments]);

  // ── Helpers ──
  const toggleCheck = useCallback((id: string) => {
    setCheckedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const setAmount = useCallback((id: string, val: string) => {
    setAmounts((prev) => ({ ...prev, [id]: val }));
  }, []);

  // ── Running total ──
  const runningTotal = Array.from(checkedIds).reduce((sum, id) => {
    const v = parseFloat(amounts[id] ?? '');
    return sum + (isNaN(v) ? 0 : v);
  }, 0);

  // ── Deduplicated POs (memoised) ──
  const uniquePos = useMemo(() => dedupePos(pos), [pos]);

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
      if (!paymentMethod) {
        setError('Payment method (Paid From Account) is required.');
        return;
      }

      // Collect checked rows with amount > 0
      const validIds = Array.from(checkedIds).filter((id) => {
        const v = parseFloat(amounts[id] ?? '');
        return !isNaN(v) && v > 0;
      });

      if (validIds.length === 0) {
        setError('Select at least one row with an amount greater than zero.');
        return;
      }

      const sharedFields = {
        payment_date: paymentDate,
        payment_method: paymentMethod,
        vendor_name: vendorName,
        currency: currency || undefined,
        bank_fee: parseFloat(bankFee) || 0,
        notes: notes.trim() || undefined,
      };

      setSubmitting(true);
      try {
        if (mode === 'shipments') {
          const amtsArr = validIds.map((id) => parseFloat(amounts[id]));
          const result = await dataEntry.bulkCreateShipmentPayments({
            shipment_ids: validIds,
            amounts: amtsArr,
            ...sharedFields,
          });
          onSaved(result.payment_id, result.created);
        } else {
          // POs mode — includes both standard po_ids and other_po_ids
          const amtsArr = validIds.map((id) => parseFloat(amounts[id]));
          const result = await dataEntry.bulkCreatePoPayments({
            po_ids: validIds,
            amounts: amtsArr,
            ...sharedFields,
          });
          onSaved(result.payment_id, result.created);
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unknown error');
        setSubmitting(false);
      }
    },
    [
      vendorName,
      paymentDate,
      paymentMethod,
      currency,
      bankFee,
      notes,
      mode,
      checkedIds,
      amounts,
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
        className="relative w-full max-w-[760px] max-h-[92vh] rounded-2xl border border-border bg-card shadow-2xl overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* ─── Header ─── */}
        <div className="flex items-center justify-between px-5 py-3 border-b border-border bg-surface/50 shrink-0">
          <div className="flex items-center gap-2.5">
            <div
              className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0"
              style={{ background: '#3b82f620' }}
            >
              <CreditCard size={16} className="text-blue-400" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-heading">Bulk Vendor Payment</h2>
              <p className="text-[10px] text-muted mt-0.5">
                Pay multiple shipments or POs in one transaction
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

          {/* ── Mode Toggle ── */}
          <div className="flex flex-col gap-1.5">
            <span className={labelCls}>Pay Against</span>
            <div className="flex gap-2">
              {(['shipments', 'pos'] as Mode[]).map((m) => {
                const selected = mode === m;
                return (
                  <button
                    key={m}
                    type="button"
                    onClick={() => handleModeChange(m)}
                    className={`flex items-center gap-2 flex-1 rounded-lg border px-3 py-2 text-xs font-semibold transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50 ${
                      selected
                        ? 'border-blue-500/60 bg-blue-500/15 text-blue-400'
                        : 'border-border bg-surface text-muted hover:text-heading hover:border-border-strong'
                    }`}
                  >
                    {m === 'shipments' ? (
                      <Truck size={13} className="shrink-0" />
                    ) : (
                      <Package size={13} className="shrink-0" />
                    )}
                    {m === 'shipments' ? 'Shipments' : 'Purchase Orders'}
                  </button>
                );
              })}
            </div>
          </div>

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

          {/* ── Row: bank_fee + currency ── */}
          <div className="grid grid-cols-2 gap-4">
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

          {/* ── Candidate Grid ── */}
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <span className={labelCls}>
                {mode === 'shipments' ? 'Shipments' : 'Purchase Orders'}{' '}
                <span className="text-negative">*</span>
              </span>
              {checkedIds.size > 0 && (
                <span className="text-[10px] text-blue-400 font-semibold">
                  {checkedIds.size} selected · Total:{' '}
                  <span className="font-mono">{fmtAmt(runningTotal)}</span>
                </span>
              )}
            </div>

            <div
              className="rounded-lg border border-border overflow-hidden"
              style={{
                maxHeight: '300px',
                overflowY: 'auto',
                scrollbarWidth: 'thin',
                scrollbarColor: 'var(--color-border) transparent',
              }}
            >
              {mode === 'shipments' ? (
                <ShipmentCandidateGrid
                  shipments={shipments}
                  checkedIds={checkedIds}
                  amounts={amounts}
                  onToggle={toggleCheck}
                  onAmount={setAmount}
                />
              ) : (
                <POCandidateGrid
                  uniquePos={uniquePos}
                  otherPos={otherPos}
                  checkedIds={checkedIds}
                  amounts={amounts}
                  onToggle={toggleCheck}
                  onAmount={setAmount}
                />
              )}
            </div>
          </div>
        </form>

        {/* ─── Footer actions ─── */}
        <div className="flex items-center justify-between gap-3 px-5 py-3 border-t border-border bg-surface/50 shrink-0">
          <div className="text-xs text-muted">
            {checkedIds.size > 0 ? (
              <span>
                <span className="text-heading font-semibold">{checkedIds.size}</span> selected ·{' '}
                <span className="font-mono text-heading font-semibold">{fmtAmt(runningTotal)}</span> total
              </span>
            ) : (
              <span className="text-faint">No rows selected</span>
            )}
          </div>
          <div className="flex items-center gap-3">
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
              {submitting
                ? 'Saving…'
                : `Pay ${checkedIds.size > 0 ? checkedIds.size : ''} ${mode === 'shipments' ? 'Shipment' : 'PO'}${checkedIds.size !== 1 ? 's' : ''}`}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Shipment Candidate Grid
// ---------------------------------------------------------------------------

function ShipmentCandidateGrid({
  shipments,
  checkedIds,
  amounts,
  onToggle,
  onAmount,
}: {
  shipments: SupplyShipmentRow[];
  checkedIds: Set<string>;
  amounts: Record<string, string>;
  onToggle: (id: string) => void;
  onAmount: (id: string, val: string) => void;
}) {
  if (shipments.length === 0) {
    return (
      <div className="p-6 text-center text-muted text-xs">No shipments available</div>
    );
  }
  return (
    <table className="w-full text-xs">
      <thead className="sticky top-0 z-10">
        <tr className="border-b border-border bg-surface">
          <th className="w-8 px-3 py-2" />
          <th className="text-left px-3 py-2 text-[10px] font-semibold text-faint uppercase tracking-wider">
            Shipment ID
          </th>
          <th className="text-left px-3 py-2 text-[10px] font-semibold text-faint uppercase tracking-wider">
            Products
          </th>
          <th className="text-right px-3 py-2 text-[10px] font-semibold text-faint uppercase tracking-wider">
            Unpaid
          </th>
          <th className="text-right px-3 py-2 text-[10px] font-semibold text-faint uppercase tracking-wider">
            Amount
          </th>
        </tr>
      </thead>
      <tbody>
        {shipments.map((s) => {
          const checked = checkedIds.has(s.shipment_id);
          const unpaid = Math.max(s.unpaid_to_shipment, 0);
          return (
            <tr
              key={s.shipment_id}
              className={`border-b border-border/50 transition-colors cursor-pointer ${
                checked ? 'bg-blue-500/5' : 'hover:bg-white/[.02]'
              }`}
              onClick={() => onToggle(s.shipment_id)}
            >
              <td className="px-3 py-2.5 text-center">
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={() => onToggle(s.shipment_id)}
                  onClick={(e) => e.stopPropagation()}
                  className="accent-blue-500 cursor-pointer"
                />
              </td>
              <td className="px-3 py-2.5">
                <span className="font-mono text-subtle font-medium">
                  {s.shipment_id}
                </span>
                {s.shipment_date && (
                  <span className="ml-2 text-faint text-[10px]">{s.shipment_date}</span>
                )}
              </td>
              <td className="px-3 py-2.5 text-muted max-w-[200px] truncate" title={s.products_list}>
                {s.products_list || '—'}
              </td>
              <td className="px-3 py-2.5 text-right font-mono">
                <span className={unpaid > 0.01 ? 'text-orange-400 font-semibold' : 'text-emerald-400'}>
                  {unpaid > 0 ? fmtAmt(unpaid) : '—'}
                </span>
              </td>
              <td className="px-3 py-2.5 text-right" onClick={(e) => e.stopPropagation()}>
                <input
                  type="number"
                  step="any"
                  min="0"
                  value={amounts[s.shipment_id] ?? ''}
                  onChange={(e) => {
                    if (!checkedIds.has(s.shipment_id)) onToggle(s.shipment_id);
                    onAmount(s.shipment_id, e.target.value);
                  }}
                  placeholder="0.00"
                  className="w-24 rounded border border-border bg-card px-2 py-1 text-xs text-right text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50 font-mono"
                />
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

// ---------------------------------------------------------------------------
// PO Candidate Grid (standard POs + other POs)
// ---------------------------------------------------------------------------

function POCandidateGrid({
  uniquePos,
  otherPos,
  checkedIds,
  amounts,
  onToggle,
  onAmount,
}: {
  uniquePos: Array<{ purchase_order_id: string; manufacturer_name: string; unpaid_manufacturer: number }>;
  otherPos: SupplyOtherPORow[];
  checkedIds: Set<string>;
  amounts: Record<string, string>;
  onToggle: (id: string) => void;
  onAmount: (id: string, val: string) => void;
}) {
  if (uniquePos.length === 0 && otherPos.length === 0) {
    return (
      <div className="p-6 text-center text-muted text-xs">No purchase orders available</div>
    );
  }
  return (
    <table className="w-full text-xs">
      <thead className="sticky top-0 z-10">
        <tr className="border-b border-border bg-surface">
          <th className="w-8 px-3 py-2" />
          <th className="text-left px-3 py-2 text-[10px] font-semibold text-faint uppercase tracking-wider">
            PO ID
          </th>
          <th className="text-left px-3 py-2 text-[10px] font-semibold text-faint uppercase tracking-wider">
            Manufacturer / Supplier
          </th>
          <th className="text-right px-3 py-2 text-[10px] font-semibold text-faint uppercase tracking-wider">
            Unpaid
          </th>
          <th className="text-right px-3 py-2 text-[10px] font-semibold text-faint uppercase tracking-wider">
            Amount
          </th>
        </tr>
      </thead>
      <tbody>
        {uniquePos.map((p) => {
          const id = p.purchase_order_id;
          const checked = checkedIds.has(id);
          return (
            <tr
              key={id}
              className={`border-b border-border/50 transition-colors cursor-pointer ${
                checked ? 'bg-blue-500/5' : 'hover:bg-white/[.02]'
              }`}
              onClick={() => onToggle(id)}
            >
              <td className="px-3 py-2.5 text-center">
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={() => onToggle(id)}
                  onClick={(e) => e.stopPropagation()}
                  className="accent-blue-500 cursor-pointer"
                />
              </td>
              <td className="px-3 py-2.5">
                <span className="font-mono text-subtle font-medium truncate max-w-[180px] block">
                  {id}
                </span>
              </td>
              <td className="px-3 py-2.5 text-muted truncate max-w-[160px]">
                {p.manufacturer_name || '—'}
              </td>
              <td className="px-3 py-2.5 text-right font-mono">
                <span className={p.unpaid_manufacturer > 0.01 ? 'text-red-400 font-semibold' : 'text-emerald-400'}>
                  {fmtAmt(p.unpaid_manufacturer)}
                </span>
              </td>
              <td className="px-3 py-2.5 text-right" onClick={(e) => e.stopPropagation()}>
                <input
                  type="number"
                  step="any"
                  min="0"
                  value={amounts[id] ?? ''}
                  onChange={(e) => {
                    if (!checkedIds.has(id)) onToggle(id);
                    onAmount(id, e.target.value);
                  }}
                  placeholder="0.00"
                  className="w-24 rounded border border-border bg-card px-2 py-1 text-xs text-right text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50 font-mono"
                />
              </td>
            </tr>
          );
        })}
        {otherPos.map((op) => {
          const id = op.other_po_id;
          const checked = checkedIds.has(id);
          const unpaid = op.payment_status !== 'PAID' ? op.total_amount : 0;
          return (
            <tr
              key={`other_${id}`}
              className={`border-b border-border/50 transition-colors cursor-pointer ${
                checked ? 'bg-blue-500/5' : 'hover:bg-white/[.02]'
              }`}
              onClick={() => onToggle(id)}
            >
              <td className="px-3 py-2.5 text-center">
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={() => onToggle(id)}
                  onClick={(e) => e.stopPropagation()}
                  className="accent-blue-500 cursor-pointer"
                />
              </td>
              <td className="px-3 py-2.5">
                <div className="font-mono text-subtle font-medium truncate max-w-[180px]">
                  {id}
                </div>
                <div className="text-[10px] text-faint">Other PO</div>
              </td>
              <td className="px-3 py-2.5 text-muted truncate max-w-[160px]">
                {op.supplier_name || op.service_type || '—'}
              </td>
              <td className="px-3 py-2.5 text-right font-mono">
                <span className={unpaid > 0.01 ? 'text-purple-400 font-semibold' : 'text-emerald-400'}>
                  {unpaid > 0 ? fmtAmt(unpaid) : '—'}
                </span>
              </td>
              <td className="px-3 py-2.5 text-right" onClick={(e) => e.stopPropagation()}>
                <input
                  type="number"
                  step="any"
                  min="0"
                  value={amounts[id] ?? ''}
                  onChange={(e) => {
                    if (!checkedIds.has(id)) onToggle(id);
                    onAmount(id, e.target.value);
                  }}
                  placeholder="0.00"
                  className="w-24 rounded border border-border bg-card px-2 py-1 text-xs text-right text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50 font-mono"
                />
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
