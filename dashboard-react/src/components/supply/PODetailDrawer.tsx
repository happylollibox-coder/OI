/**
 * PODetailDrawer — editable PO detail panel backed by the Flask JSON API.
 *
 * Layout/styling derived from the former read-only PO details modal. Fetches
 * the authoritative detail via dataEntry.getPO and supports inline edits:
 *   - per-line quantity / total_amount / ready_quantity
 *   - add line (ProductSelect + qty + amount)
 *   - delete line (guarded when only one line remains)
 *   - header edit (manufacturer, order_date, currency, payment_status, notes, adjustments)
 *   - delete PO (in-component confirm)
 *
 * After every successful write it re-fetches and calls onChanged(freshDetail)
 * so the parent table overlay reflects the change. onChanged(null) signals the
 * PO was deleted.
 *
 * Never sends client-computed ids/unit_price/totals — only raw field values.
 */
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Package, CreditCard, Truck, X, Pencil, Save, Plus, Trash2, AlertCircle, Loader2 } from 'lucide-react';
import type { SupplyPORow } from '../../types';
import { dataEntry, type PODetail } from '../../utils/dataEntry';
import { ProductSelect } from './ProductSelect';

/* ── helpers ── */
const fmtDate = (d: string | null | undefined) => {
  if (!d) return '—';
  const dt = new Date(String(d) + 'T00:00:00');
  return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
};
const fmtFull$ = (n: number) =>
  n.toLocaleString('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 });
const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const str = (v: unknown): string => (v == null ? '' : String(v));

function StatusBadge({ status }: { status: string }) {
  const s = (status || '').toLowerCase();
  const cls = s === 'paid' ? 'bg-emerald-500/15 text-emerald-400'
    : s === 'partial' ? 'bg-amber-500/15 text-amber-400'
    : 'bg-red-500/15 text-red-400';
  return <span className={`inline-flex px-1.5 py-0.5 rounded-full text-[9px] font-semibold uppercase tracking-wider ${cls}`}>{status || '—'}</span>;
}

const inputCls = 'w-full rounded-lg border border-border bg-surface px-2.5 py-1.5 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50';
const numInputCls = 'w-20 rounded border border-border bg-black/40 px-1.5 py-0.5 text-xs text-right text-heading font-mono focus:outline-none focus:border-blue-500';

type LineField = 'quantity' | 'total_amount' | 'ready_quantity';

interface PODetailDrawerProps {
  po: SupplyPORow;
  onClose: () => void;
  onChanged: (detail: PODetail | null) => void;
}

export default function PODetailDrawer({ po, onClose, onChanged }: PODetailDrawerProps) {
  const poId = po.purchase_order_id;

  const [detail, setDetail] = useState<PODetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // ── Header edit state ──
  const [editingHeader, setEditingHeader] = useState(false);
  const [hManufacturer, setHManufacturer] = useState('');
  const [hOrderDate, setHOrderDate] = useState('');
  const [hCurrency, setHCurrency] = useState('');
  const [hPaymentStatus, setHPaymentStatus] = useState('');
  const [hNotes, setHNotes] = useState('');
  const [hAdjustments, setHAdjustments] = useState('');

  // ── Add line state ──
  const [newProductId, setNewProductId] = useState<number | null>(null);
  const [newQty, setNewQty] = useState('1');
  const [newAmount, setNewAmount] = useState('');

  // ── Per-line draft values (keyed by product_id) ──
  const [lineDrafts, setLineDrafts] = useState<Record<string, { quantity: string; total_amount: string; ready_quantity: string }>>({});

  // ── Delete-PO confirm ──
  const [confirmDelete, setConfirmDelete] = useState(false);

  const fetchDetail = useCallback(async () => {
    return dataEntry.getPO(poId);
  }, [poId]);

  // Initial load
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setLoadError(null);
    fetchDetail()
      .then((d) => { if (!cancelled) { setDetail(d); } })
      .catch((e) => { if (!cancelled) setLoadError(e instanceof Error ? e.message : 'Failed to load PO'); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [fetchDetail]);

  // Sync header edit fields + line drafts whenever detail changes
  useEffect(() => {
    if (!detail) return;
    const p = detail.po;
    setHManufacturer(str(p.manufacturer_name));
    setHOrderDate(str(p.order_date));
    setHCurrency(str(p.currency) || 'USD');
    setHPaymentStatus(str(p.payment_status) || 'PENDING');
    setHNotes(str(p.notes));
    setHAdjustments(p.adjustments == null ? '' : String(p.adjustments));
    const drafts: Record<string, { quantity: string; total_amount: string; ready_quantity: string }> = {};
    for (const l of detail.product_lines) {
      const pid = str(l.product_id);
      drafts[pid] = {
        quantity: String(num(l.quantity)),
        total_amount: String(num(l.total_amount)),
        ready_quantity: String(num(l.ready_quantity)),
      };
    }
    setLineDrafts(drafts);
  }, [detail]);

  // Re-fetch after a write and propagate to parent.
  const refreshAndNotify = useCallback(async () => {
    const fresh = await fetchDetail();
    setDetail(fresh);
    onChanged(fresh);
  }, [fetchDetail, onChanged]);

  const runWrite = useCallback(async (fn: () => Promise<unknown>) => {
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
      setBusy(false);
    }
  }, [refreshAndNotify]);

  // ── Header (display-source) — prefer fetched detail, fall back to summary row ──
  const headerView = useMemo(() => {
    const p = detail?.po;
    return {
      manufacturer_name: p ? str(p.manufacturer_name) : po.manufacturer_name,
      order_date: p ? str(p.order_date) : po.order_date,
      currency: p ? (str(p.currency) || 'USD') : po.currency,
      payment_status: p ? (str(p.payment_status) || 'PENDING') : po.payment_status,
      expected_ready_date: p ? (p.expected_ready_date == null ? null : str(p.expected_ready_date)) : po.expected_ready_date,
      is_open: p ? !p.is_paid_in_full : po.is_open,
      notes: p ? (p.notes == null ? null : str(p.notes)) : po.notes,
    };
  }, [detail, po]);

  const lines = useMemo(() => detail?.product_lines ?? [], [detail]);
  const payments = detail?.payments ?? [];
  const shipments = detail?.shipments ?? [];

  // ── Aggregate totals from authoritative lines ──
  const agg = useMemo(() => {
    let qty = 0, shipped = 0, ready = 0, cost = 0;
    for (const l of lines) {
      qty += num(l.quantity);
      shipped += num(l.quantity_shipped);
      ready += num(l.ready_quantity);
      cost += num(l.total_amount);
    }
    return { qty, shipped, ready, cost };
  }, [lines]);

  const totalPaid = detail ? num(detail.po.total_paid) : po.total_paid;
  const paidPct = agg.cost > 0 ? Math.min((totalPaid / agg.cost) * 100, 100) : 0;
  const inProduction = Math.max(0, agg.qty - agg.ready - agg.shipped);
  const showReady = agg.ready > 0 && agg.shipped < agg.qty;
  const pipeTotal = agg.qty || 1;

  // ── Line write handlers ──
  const setDraft = (pid: string, field: LineField, value: string) => {
    setLineDrafts((prev) => ({ ...prev, [pid]: { ...prev[pid], [field]: value } }));
  };

  const saveLineField = (pid: string, field: LineField) => {
    const draft = lineDrafts[pid];
    if (!draft) return;
    const value = num(draft[field]);
    void runWrite(() => dataEntry.updatePOLine(poId, Number(pid), field, value));
  };

  const deleteLine = (pid: string) => {
    void runWrite(() => dataEntry.deletePOLine(poId, Number(pid)));
  };

  const addLine = () => {
    if (newProductId == null) { setActionError('Select a product to add.'); return; }
    void runWrite(async () => {
      await dataEntry.addPOLine(poId, {
        product_id: newProductId,
        quantity: Math.max(1, num(newQty)),
        total_amount: num(newAmount),
      });
      setNewProductId(null);
      setNewQty('1');
      setNewAmount('');
    });
  };

  const saveHeader = () => {
    const body: Record<string, unknown> = {
      manufacturer_name: hManufacturer,
      order_date: hOrderDate,
      currency: hCurrency,
      payment_status: hPaymentStatus,
      notes: hNotes,
    };
    if (hAdjustments.trim() !== '') body.adjustments = num(hAdjustments);
    void runWrite(async () => {
      await dataEntry.updatePOHeader(poId, body);
      setEditingHeader(false);
    });
  };

  const doDeletePO = async () => {
    setActionError(null);
    setBusy(true);
    try {
      await dataEntry.deletePO(poId);
      onChanged(null);
      onClose();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Failed to delete PO');
      setBusy(false);
      setConfirmDelete(false);
    }
  };

  const canDeleteLine = lines.length > 1;

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
            <div className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0" style={{ background: '#3b82f620' }}>
              <Package size={16} className="text-blue-400" />
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <h2 className="text-sm font-bold text-heading truncate" title={poId}>{poId}</h2>
                <StatusBadge status={headerView.payment_status} />
                {headerView.is_open
                  ? <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-blue-500/10 text-blue-400 font-semibold">Open</span>
                  : <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-gray-500/10 text-gray-400 font-semibold">Closed</span>}
              </div>
              <div className="flex items-center gap-3 text-[10px] text-muted mt-0.5">
                <span>{headerView.manufacturer_name}</span>
                <span>·</span>
                <span>{fmtDate(headerView.order_date)}</span>
                {headerView.expected_ready_date && <><span>·</span><span>Ready {fmtDate(headerView.expected_ready_date)}</span></>}
                {headerView.currency && headerView.currency !== 'USD' && <><span>·</span><span>{headerView.currency}</span></>}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-1.5 shrink-0">
            {!loading && !loadError && (
              <button
                onClick={() => setEditingHeader((v) => !v)}
                className="p-1.5 rounded-lg hover:bg-white/5 transition-colors text-muted hover:text-heading"
                title="Edit PO header"
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
              <Loader2 size={16} className="animate-spin" /> Loading PO details…
            </div>
          )}

          {loadError && (
            <div className="rounded-lg border border-[var(--color-negative)]/40 bg-[var(--color-negative)]/10 px-3 py-2.5 text-xs text-negative flex items-center gap-2">
              <AlertCircle size={14} className="shrink-0" />
              <span>Couldn't load full details ({loadError}). Showing summary only — edits are disabled.</span>
            </div>
          )}

          {/* Action error banner (always rendered when present) */}
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
                <Pencil size={11} /> Edit Header
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Manufacturer</label>
                  <input className={inputCls} value={hManufacturer} onChange={(e) => setHManufacturer(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Order Date</label>
                  <input type="date" className={inputCls} value={hOrderDate ? hOrderDate.slice(0, 10) : ''} onChange={(e) => setHOrderDate(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Currency</label>
                  <input className={inputCls} value={hCurrency} onChange={(e) => setHCurrency(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Payment Status</label>
                  <select className={inputCls} value={hPaymentStatus} onChange={(e) => setHPaymentStatus(e.target.value)}>
                    <option value="PENDING">Pending</option>
                    <option value="PARTIAL">Partial</option>
                    <option value="PAID">Paid</option>
                  </select>
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Adjustments</label>
                  <input type="number" step="0.01" className={inputCls} value={hAdjustments} onChange={(e) => setHAdjustments(e.target.value)} placeholder="0.00" />
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
                  <Save size={13} /> Save Header
                </button>
              </div>
            </div>
          )}

          {/* ── Products (editable) ── */}
          {!loading && !loadError && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <Package size={11} /> Products ({lines.length})
              </div>
              <div className="rounded-lg border border-border overflow-hidden">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="bg-surface/50 border-b border-border">
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Product</th>
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Qty</th>
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Amount</th>
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Ready</th>
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Shipped</th>
                      <th className="px-2 py-1.5"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {lines.map((l, i) => {
                      const pid = str(l.product_id);
                      const draft = lineDrafts[pid] ?? { quantity: '', total_amount: '', ready_quantity: '' };
                      return (
                        <tr key={`${pid}_${i}`} className="border-b border-border/30 hover:bg-white/[.02]">
                          <td className="px-3 py-1.5 text-heading font-medium truncate max-w-[200px]" title={str(l.product_name)}>
                            {str(l.product_name) || '—'}
                            <span className="ml-1 text-faint font-mono text-[9px]">{str(l.product_asin)}</span>
                          </td>
                          <td className="px-3 py-1.5 text-right">
                            <div className="flex items-center justify-end gap-1">
                              <input
                                className={numInputCls + ' w-16'}
                                type="number"
                                value={draft.quantity}
                                onChange={(e) => setDraft(pid, 'quantity', e.target.value)}
                                disabled={busy}
                              />
                              {String(num(draft.quantity)) !== String(num(l.quantity)) && (
                                <button onClick={() => saveLineField(pid, 'quantity')} disabled={busy} className="text-emerald-400 hover:text-emerald-300 p-0.5" title="Save quantity"><Save size={12} /></button>
                              )}
                            </div>
                          </td>
                          <td className="px-3 py-1.5 text-right">
                            <div className="flex items-center justify-end gap-1">
                              <input
                                className={numInputCls}
                                type="number"
                                step="0.01"
                                value={draft.total_amount}
                                onChange={(e) => setDraft(pid, 'total_amount', e.target.value)}
                                disabled={busy}
                              />
                              {String(num(draft.total_amount)) !== String(num(l.total_amount)) && (
                                <button onClick={() => saveLineField(pid, 'total_amount')} disabled={busy} className="text-emerald-400 hover:text-emerald-300 p-0.5" title="Save amount"><Save size={12} /></button>
                              )}
                            </div>
                          </td>
                          <td className="px-3 py-1.5 text-right">
                            <div className="flex items-center justify-end gap-1">
                              <input
                                className={numInputCls + ' w-16'}
                                type="number"
                                value={draft.ready_quantity}
                                onChange={(e) => setDraft(pid, 'ready_quantity', e.target.value)}
                                disabled={busy}
                              />
                              {String(num(draft.ready_quantity)) !== String(num(l.ready_quantity)) && (
                                <button onClick={() => saveLineField(pid, 'ready_quantity')} disabled={busy} className="text-emerald-400 hover:text-emerald-300 p-0.5" title="Save ready qty"><Save size={12} /></button>
                              )}
                            </div>
                          </td>
                          <td className="px-3 py-1.5 text-right font-mono text-emerald-400">{num(l.quantity_shipped).toLocaleString()}</td>
                          <td className="px-2 py-1.5 text-right">
                            {canDeleteLine && (
                              <button
                                onClick={() => deleteLine(pid)}
                                disabled={busy}
                                className="p-1 rounded text-muted hover:text-negative hover:bg-[var(--color-negative)]/10 transition-colors disabled:opacity-30"
                                title="Delete line"
                              >
                                <Trash2 size={12} />
                              </button>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>

              {/* Add line */}
              <div className="mt-2 rounded-lg border border-border bg-surface/40 px-3 py-2.5">
                <div className="grid grid-cols-[1fr_70px_100px_auto] gap-2 items-end">
                  <div className="flex flex-col gap-1">
                    <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Add Product</label>
                    <ProductSelect value={newProductId} onChange={setNewProductId} />
                  </div>
                  <div className="flex flex-col gap-1">
                    <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Qty</label>
                    <input type="number" min={1} value={newQty} onChange={(e) => setNewQty(e.target.value)} className={inputCls + ' text-center font-mono'} />
                  </div>
                  <div className="flex flex-col gap-1">
                    <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Amount</label>
                    <input type="number" step="0.01" min="0" value={newAmount} onChange={(e) => setNewAmount(e.target.value)} placeholder="0.00" className={inputCls + ' text-right font-mono'} />
                  </div>
                  <button
                    onClick={addLine}
                    disabled={busy || newProductId == null}
                    className="flex items-center gap-1 px-3 py-2 rounded-lg text-[11px] font-semibold bg-blue-600 hover:bg-blue-500 text-white transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    <Plus size={13} /> Add
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* ── Fulfillment Pipeline ── */}
          {!loading && !loadError && agg.qty > 0 && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <Truck size={11} /> Fulfillment Pipeline
              </div>
              <div className="rounded-lg border border-border bg-surface/30 p-3">
                <div className="flex h-5 rounded-full overflow-hidden bg-white/[.04]">
                  {agg.shipped > 0 && (
                    <div className="bg-emerald-500/70 flex items-center justify-center text-[8px] font-bold text-white/90" style={{ width: `${(agg.shipped / pipeTotal) * 100}%`, minWidth: '24px' }} title={`Shipped: ${agg.shipped}`}>{agg.shipped.toLocaleString()}</div>
                  )}
                  {showReady && (
                    <div className="bg-purple-500/60 flex items-center justify-center text-[8px] font-bold text-white/90" style={{ width: `${(agg.ready / pipeTotal) * 100}%`, minWidth: '24px' }} title={`Ready: ${agg.ready}`}>{agg.ready.toLocaleString()}</div>
                  )}
                  {inProduction > 0 && (
                    <div className="bg-amber-500/40 flex items-center justify-center text-[8px] font-bold text-white/60" style={{ width: `${(inProduction / pipeTotal) * 100}%`, minWidth: '24px' }} title={`In Production: ${inProduction}`}>{inProduction.toLocaleString()}</div>
                  )}
                </div>
                <div className="flex items-center gap-4 mt-2 text-[10px]">
                  <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-emerald-500/70" />Shipped ({agg.shipped.toLocaleString()})</span>
                  {showReady && <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-purple-500/60" />Ready ({agg.ready.toLocaleString()})</span>}
                  {inProduction > 0 && <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-amber-500/40" />In Production ({inProduction.toLocaleString()})</span>}
                  <span className="ml-auto text-muted font-mono font-semibold">{((agg.shipped / pipeTotal) * 100).toFixed(0)}% fulfilled</span>
                </div>
              </div>
            </div>
          )}

          {/* ── Financials ── */}
          {!loading && !loadError && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <CreditCard size={11} /> Financials
              </div>
              <div className="rounded-lg border border-border bg-surface/30 px-3 py-2.5">
                <div className="flex items-center justify-between text-xs mb-1.5">
                  <span className="text-muted">Manufacturer</span>
                  <div className="flex items-center gap-4 font-mono text-[11px]">
                    <span className="text-heading font-semibold">{fmtFull$(agg.cost)}</span>
                    <span className="text-emerald-400">{fmtFull$(totalPaid)}</span>
                    <span className={agg.cost - totalPaid > 0.01 ? 'text-red-400 font-semibold' : 'text-emerald-400'}>
                      {agg.cost - totalPaid > 0.01 ? `-${fmtFull$(agg.cost - totalPaid)}` : '✓'}
                    </span>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <div className="flex-1 h-1.5 rounded-full bg-white/[.06] overflow-hidden">
                    <div className={`h-full rounded-full ${paidPct >= 100 ? 'bg-emerald-400' : paidPct >= 50 ? 'bg-blue-400' : 'bg-amber-400'}`} style={{ width: `${paidPct}%` }} />
                  </div>
                  <span className="text-[9px] font-mono text-muted shrink-0">{paidPct.toFixed(0)}%</span>
                </div>
              </div>
              <div className="flex justify-end gap-4 mt-0.5 text-[8px] text-faint uppercase tracking-widest pr-3">
                <span>Cost</span><span>Paid</span><span>Unpaid</span>
              </div>
            </div>
          )}

          {/* ── Shipments ── */}
          {!loading && !loadError && shipments.length > 0 && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <Truck size={11} /> Shipments ({shipments.length})
              </div>
              <div className="rounded-lg border border-border overflow-hidden">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="bg-surface/50 border-b border-border">
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">ID</th>
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Ship</th>
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Qty</th>
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {shipments.map((s, i) => (
                      <tr key={`${str(s.shipment_id)}_${i}`} className="border-b border-border/30">
                        <td className="px-3 py-1.5 font-mono text-heading text-[10px] truncate max-w-[160px]" title={str(s.shipment_id)}>{str(s.shipment_id)}</td>
                        <td className="px-3 py-1.5 text-muted whitespace-nowrap">{fmtDate(str(s.shipment_date))}</td>
                        <td className="px-3 py-1.5 text-right font-mono font-semibold text-heading">{num(s.total_quantity_shipped).toLocaleString()}</td>
                        <td className="px-3 py-1.5 text-muted">{str(s.shipment_status) || '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* ── Payments ── */}
          {!loading && !loadError && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <CreditCard size={11} /> Payments ({payments.length})
              </div>
              {payments.length === 0 ? (
                <div className="rounded-lg border border-border bg-surface/30 px-3 py-2.5 text-center">
                  <p className="text-[11px] text-muted">No payments recorded</p>
                </div>
              ) : (
                <div className="rounded-lg border border-border overflow-hidden">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="bg-surface/50 border-b border-border">
                        <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Date</th>
                        <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Vendor</th>
                        <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Amount</th>
                        <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Method</th>
                      </tr>
                    </thead>
                    <tbody>
                      {payments.map((p, i) => (
                        <tr key={`${str(p.payment_id)}_${i}`} className="border-b border-border/30">
                          <td className="px-3 py-1.5 text-muted whitespace-nowrap">{fmtDate(str(p.payment_date))}</td>
                          <td className="px-3 py-1.5 text-subtle">{str(p.vendor_name)}</td>
                          <td className="px-3 py-1.5 text-right font-mono font-semibold text-heading">{fmtFull$(num(p.payment_amount))}</td>
                          <td className="px-3 py-1.5 text-muted">{str(p.payment_method) || '—'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
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

        {/* ─── Footer: delete PO ─── */}
        {!loading && !loadError && (
          <div className="flex items-center justify-between gap-3 px-5 py-3 border-t border-border bg-surface/50 shrink-0">
            {confirmDelete ? (
              <div className="flex items-center gap-3 w-full">
                <span className="text-xs text-negative flex items-center gap-1.5"><AlertCircle size={13} /> Delete this PO and all its lines?</span>
                <div className="flex-1" />
                <button
                  onClick={() => setConfirmDelete(false)}
                  disabled={busy}
                  className="px-3 py-1.5 rounded-lg text-xs font-medium text-muted hover:text-heading border border-border hover:bg-white/5 transition-colors"
                >Cancel</button>
                <button
                  onClick={doDeletePO}
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
                  <Trash2 size={13} /> Delete PO
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
