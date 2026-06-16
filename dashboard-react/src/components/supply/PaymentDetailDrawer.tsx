/**
 * PaymentDetailDrawer — editable payment detail panel backed by the Flask JSON API.
 *
 * Mirrors ShipmentDetailDrawer (Phase 2) / PODetailDrawer (Phase 1). Fetches the
 * authoritative detail via dataEntry.getPayment and supports inline edits:
 *   - header edit (date, amount, bank_fee, currency, method, vendor, notes)  (updatePayment)
 *   - delete payment (in-component confirm)                                  (deletePayment)
 *
 * After every successful write it re-fetches and calls onChanged(freshDetail)
 * so the parent table overlay reflects the change. onChanged(null) signals the
 * payment was deleted.
 *
 * Never sends client-computed ids/totals — only raw field values.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { CreditCard, X, Pencil, Save, Trash2, AlertCircle, Loader2, Package, Truck } from 'lucide-react';
import type { SupplyPaymentRow } from '../../types';
import { dataEntry, type PaymentDetail } from '../../utils/dataEntry';

/* ── helpers ── */
const fmtDate = (d: string | null | undefined) => {
  if (!d) return '—';
  const dt = new Date(String(d) + 'T00:00:00Z');
  return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
};
const fmtFull$ = (n: number) =>
  n.toLocaleString('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 });
const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const str = (v: unknown): string => (v == null ? '' : String(v));

const inputCls = 'w-full rounded-lg border border-border bg-surface px-2.5 py-1.5 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50';

interface PaymentDetailDrawerProps {
  payment: SupplyPaymentRow;
  onClose: () => void;
  onChanged: (detail: PaymentDetail | null) => void;
}

export default function PaymentDetailDrawer({ payment, onClose, onChanged }: PaymentDetailDrawerProps) {
  const paymentId = payment.payment_id;

  const [detail, setDetail] = useState<PaymentDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // ── Header edit state ──
  const [editingHeader, setEditingHeader] = useState(false);
  const [hPaymentDate, setHPaymentDate] = useState('');
  const [hPaymentAmount, setHPaymentAmount] = useState('');
  const [hBankFee, setHBankFee] = useState('');
  const [hCurrency, setHCurrency] = useState('');
  const [hPaymentMethod, setHPaymentMethod] = useState('');
  const [hVendorName, setHVendorName] = useState('');
  const [hNotes, setHNotes] = useState('');

  // ── Delete-payment confirm ──
  const [confirmDelete, setConfirmDelete] = useState(false);

  // ── In-flight write guard (ref so closure captures current value) ──
  const busyRef = useRef(false);

  const fetchDetail = useCallback(async () => {
    return dataEntry.getPayment(paymentId);
  }, [paymentId]);

  // Initial load
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setLoadError(null);
    fetchDetail()
      .then((d) => { if (!cancelled) { setDetail(d); } })
      .catch((e) => { if (!cancelled) setLoadError(e instanceof Error ? e.message : 'Failed to load payment'); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [fetchDetail]);

  // Sync header edit fields whenever detail changes
  useEffect(() => {
    if (!detail) return;
    const p = detail.payment;
    setHPaymentDate(str(p.payment_date));
    setHPaymentAmount(p.payment_amount == null ? '' : String(num(p.payment_amount)));
    setHBankFee(p.bank_fee == null ? '' : String(num(p.bank_fee)));
    setHCurrency(str(p.currency));
    setHPaymentMethod(str(p.payment_method));
    setHVendorName(str(p.vendor_name));
    setHNotes(str(p.notes));
  }, [detail]);

  // Re-fetch after a write and propagate to parent.
  const refreshAndNotify = useCallback(async () => {
    const fresh = await fetchDetail();
    setDetail(fresh);
    onChanged(fresh);
  }, [fetchDetail, onChanged]);

  const runWrite = useCallback(async (fn: () => Promise<unknown>) => {
    if (busyRef.current) return false;
    busyRef.current = true;
    setActionError(null);
    setBusy(true);
    try {
      await fn();
      await refreshAndNotify();
      return true;
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Write failed');
      return false;
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }, [refreshAndNotify]);

  // ── Header (display-source) — prefer fetched detail, fall back to summary row ──
  const headerView = useMemo(() => {
    const p = detail?.payment;
    return {
      payment_date: p ? str(p.payment_date) : payment.payment_date,
      payment_amount: p ? num(p.payment_amount) : payment.payment_amount,
      bank_fee: p ? num(p.bank_fee) : payment.bank_fee,
      currency: p ? str(p.currency) : payment.currency,
      payment_method: p ? str(p.payment_method) : payment.payment_method,
      vendor_name: p ? str(p.vendor_name) : payment.vendor_name,
      purchase_order_id: p ? (p.purchase_order_id == null ? null : str(p.purchase_order_id)) : payment.purchase_order_id,
      shipment_id: p ? (p.shipment_id == null ? null : str(p.shipment_id)) : payment.shipment_id,
      notes: p ? (p.notes == null ? null : str(p.notes)) : payment.notes,
    };
  }, [detail, payment]);

  const lines = useMemo(() => detail?.lines ?? [], [detail]);
  const totalAmount = headerView.payment_amount + headerView.bank_fee;

  const saveHeader = () => {
    const body: Record<string, unknown> = {
      payment_date: hPaymentDate,
      payment_method: hPaymentMethod,
      vendor_name: hVendorName,
      currency: hCurrency,
      notes: hNotes,
    };
    if (hPaymentAmount.trim() !== '') body.payment_amount = num(hPaymentAmount);
    if (hBankFee.trim() !== '') body.bank_fee = num(hBankFee);
    void runWrite(async () => {
      await dataEntry.updatePayment(paymentId, body);
      setEditingHeader(false);
    });
  };

  const doDeletePayment = async () => {
    if (busyRef.current) return;
    busyRef.current = true;
    setActionError(null);
    setBusy(true);
    try {
      await dataEntry.deletePayment(paymentId);
      onChanged(null);
      onClose();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Failed to delete payment');
      setConfirmDelete(false);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      onClick={onClose}
      style={{ background: 'rgba(0,0,0,.6)', backdropFilter: 'blur(6px)' }}
    >
      <div
        className="relative w-full max-w-[720px] max-h-[88vh] rounded-2xl border border-border bg-card shadow-2xl overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* ─── Header ─── */}
        <div className="flex items-center justify-between px-5 py-3 border-b border-border bg-surface/50 shrink-0">
          <div className="flex items-center gap-2.5 min-w-0">
            <div className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0 bg-emerald-500/10">
              <CreditCard size={16} className="text-emerald-400" />
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <h2 className="text-sm font-bold text-heading truncate" title={paymentId}>{paymentId}</h2>
                {headerView.vendor_name && (
                  <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 font-semibold uppercase tracking-wider">{headerView.vendor_name}</span>
                )}
              </div>
              <div className="flex items-center gap-3 text-[10px] text-muted mt-0.5">
                <span>{fmtDate(headerView.payment_date)}</span>
                <span>·</span>
                <span>{fmtFull$(headerView.payment_amount)}</span>
                {headerView.payment_method && <><span>·</span><span>{headerView.payment_method}</span></>}
                {headerView.currency && <><span>·</span><span>{headerView.currency}</span></>}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-1.5 shrink-0">
            {!loading && !loadError && (
              <button
                onClick={() => setEditingHeader((v) => !v)}
                className="p-1.5 rounded-lg hover:bg-white/5 transition-colors text-muted hover:text-heading"
                title="Edit payment"
              >
                <Pencil size={14} />
              </button>
            )}
            <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-white/5 transition-colors text-muted hover:text-heading">
              <X size={16} />
            </button>
          </div>
        </div>

        {/* ─── Scrollable content ─── */}
        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4" style={{ scrollbarWidth: 'thin', scrollbarColor: 'var(--color-border) transparent' }}>

          {loading && (
            <div className="flex items-center justify-center gap-2 py-12 text-muted text-sm">
              <Loader2 size={16} className="animate-spin" /> Loading payment details…
            </div>
          )}

          {loadError && (
            <div className="rounded-lg border border-[var(--color-negative)]/40 bg-[var(--color-negative)]/10 px-3 py-2.5 text-xs text-negative flex items-center gap-2">
              <AlertCircle size={14} className="shrink-0" />
              <span>Couldn't load full details ({loadError}). Showing summary only — edits are disabled.</span>
            </div>
          )}

          {/* Action error banner */}
          {actionError && (
            <div className="rounded-lg border border-[var(--color-negative)]/40 bg-[var(--color-negative)]/10 px-3 py-2.5 text-xs text-negative flex items-center gap-2">
              <AlertCircle size={14} className="shrink-0" />
              <span>{actionError}</span>
            </div>
          )}

          {/* ── Header edit form ── */}
          {!loading && !loadError && editingHeader && (
            <div className="rounded-lg border border-border bg-surface/30 p-3 space-y-3">
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold flex items-center gap-1.5">
                <Pencil size={11} /> Edit Payment
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Vendor</label>
                  <input className={inputCls} value={hVendorName} onChange={(e) => setHVendorName(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Payment Date</label>
                  <input type="date" className={inputCls} value={hPaymentDate ? hPaymentDate.slice(0, 10) : ''} onChange={(e) => setHPaymentDate(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Method</label>
                  <input className={inputCls} value={hPaymentMethod} onChange={(e) => setHPaymentMethod(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Amount</label>
                  <input type="number" step="0.01" className={inputCls} value={hPaymentAmount} onChange={(e) => setHPaymentAmount(e.target.value)} placeholder="0.00" />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Bank Fee</label>
                  <input type="number" step="0.01" className={inputCls} value={hBankFee} onChange={(e) => setHBankFee(e.target.value)} placeholder="0.00" />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Currency</label>
                  <input className={inputCls} value={hCurrency} onChange={(e) => setHCurrency(e.target.value)} />
                </div>
              </div>
              <div className="flex flex-col gap-1">
                <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Notes</label>
                <textarea rows={2} className={inputCls + ' resize-none'} value={hNotes} onChange={(e) => setHNotes(e.target.value)} />
              </div>
              <div className="flex items-center justify-end gap-2">
                <button
                  onClick={() => setEditingHeader(false)}
                  className="px-3 py-1.5 rounded-lg text-xs font-medium text-muted hover:text-heading border border-border hover:bg-white/5 transition-colors"
                >Cancel</button>
                <button
                  onClick={saveHeader}
                  disabled={busy}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-blue-600 hover:bg-blue-500 text-white transition-colors disabled:opacity-50"
                >
                  <Save size={13} /> Save Payment
                </button>
              </div>
            </div>
          )}

          {/* ── Links (PO / Shipment) ── */}
          {!loading && !loadError && (headerView.purchase_order_id || headerView.shipment_id) && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5">Linked To</div>
              <div className="rounded-lg border border-border bg-surface/30 px-3 py-2.5 space-y-1.5 text-xs">
                {headerView.purchase_order_id && (
                  <div className="flex items-center gap-2">
                    <Package size={12} className="text-muted shrink-0" />
                    <span className="text-faint text-[10px] uppercase tracking-wider">PO</span>
                    <span className="text-heading font-mono truncate" title={headerView.purchase_order_id}>{headerView.purchase_order_id}</span>
                  </div>
                )}
                {headerView.shipment_id && (
                  <div className="flex items-center gap-2">
                    <Truck size={12} className="text-muted shrink-0" />
                    <span className="text-faint text-[10px] uppercase tracking-wider">Shipment</span>
                    <span className="text-heading font-mono truncate" title={headerView.shipment_id}>{headerView.shipment_id}</span>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* ── Lines (read-only, only when present) ── */}
          {!loading && !loadError && lines.length > 1 && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <CreditCard size={11} /> Allocations ({lines.length})
              </div>
              <div className="rounded-lg border border-border overflow-hidden">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="bg-surface/50 border-b border-border">
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">PO</th>
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Shipment</th>
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Amount</th>
                    </tr>
                  </thead>
                  <tbody>
                    {lines.map((l, i) => (
                      <tr key={`${str(l.line_id)}_${i}`} className="border-b border-border/30 hover:bg-white/[.02]">
                        <td className="px-3 py-1.5 text-muted font-mono text-[10px] truncate max-w-[180px]" title={str(l.purchase_order_id)}>{str(l.purchase_order_id) || '—'}</td>
                        <td className="px-3 py-1.5 text-muted font-mono text-[10px] truncate max-w-[180px]" title={str(l.shipment_id)}>{str(l.shipment_id) || '—'}</td>
                        <td className="px-3 py-1.5 text-right text-heading font-mono">{fmtFull$(num(l.amount ?? l.allocated_amount ?? l.payment_amount))}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* ── Financials ── */}
          {!loading && !loadError && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <CreditCard size={11} /> Financials
              </div>
              <div className="rounded-lg border border-border bg-surface/30 px-3 py-2.5 space-y-1.5 text-xs">
                <div className="flex items-center justify-between">
                  <span className="text-muted">Payment Amount</span>
                  <span className="text-heading font-mono font-semibold">{fmtFull$(headerView.payment_amount)}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted">Bank Fee</span>
                  <span className="text-heading font-mono">{fmtFull$(headerView.bank_fee)}</span>
                </div>
                <div className="flex items-center justify-between border-t border-border/50 pt-1.5">
                  <span className="text-muted">Total</span>
                  <span className="text-blue-400 font-mono font-semibold">{fmtFull$(totalAmount)}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted">Currency</span>
                  <span className="text-heading font-mono">{headerView.currency || '—'}</span>
                </div>
              </div>
            </div>
          )}

          {/* ── Notes ── */}
          {!loading && !loadError && headerView.notes && (
            <div className="text-xs text-subtle bg-surface/30 border border-border rounded-lg px-3 py-2">
              <span className="text-[9px] text-faint uppercase tracking-wider font-semibold mr-2">Notes:</span>
              {headerView.notes}
            </div>
          )}
        </div>

        {/* ─── Footer: delete payment ─── */}
        {!loading && !loadError && (
          <div className="flex items-center justify-between gap-3 px-5 py-3 border-t border-border bg-surface/50 shrink-0">
            {confirmDelete ? (
              <div className="flex items-center gap-3 w-full">
                <span className="text-xs text-negative flex items-center gap-1.5"><AlertCircle size={13} /> Delete this payment?</span>
                <div className="flex-1" />
                <button
                  onClick={() => setConfirmDelete(false)}
                  disabled={busy}
                  className="px-3 py-1.5 rounded-lg text-xs font-medium text-muted hover:text-heading border border-border hover:bg-white/5 transition-colors"
                >Cancel</button>
                <button
                  onClick={doDeletePayment}
                  disabled={busy}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-red-600 hover:bg-red-500 text-white transition-colors disabled:opacity-50"
                >
                  <Trash2 size={13} /> Confirm Delete
                </button>
              </div>
            ) : (
              <>
                <button
                  onClick={() => setConfirmDelete(true)}
                  disabled={busy}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium text-negative border border-[var(--color-negative)]/40 hover:bg-[var(--color-negative)]/10 transition-colors disabled:opacity-50"
                >
                  <Trash2 size={13} /> Delete Payment
                </button>
                <div className="flex-1" />
                {busy && <span className="text-[11px] text-muted flex items-center gap-1.5"><Loader2 size={12} className="animate-spin" /> Saving…</span>}
                <button
                  onClick={onClose}
                  className="px-4 py-2 rounded-lg text-xs font-medium text-muted hover:text-heading border border-border hover:bg-white/5 transition-colors"
                >Close</button>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
