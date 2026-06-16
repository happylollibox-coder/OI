/**
 * ShipmentDetailDrawer — editable shipment detail panel backed by the Flask JSON API.
 *
 * Mirrors PODetailDrawer (Phase 1). Fetches the authoritative detail via
 * dataEntry.getShipment and supports inline edits:
 *   - per-line quantity_shipped / allocated_cost  (updateShipmentLine)
 *   - add line via open-PO allocation picker        (addShipmentLine)
 *   - delete line                                   (deleteShipmentLine)
 *   - header edit (deliverer, dates, type, status, tracking, costs, paid)  (updateShipmentHeader)
 *   - delete shipment (in-component confirm)        (deleteShipment)
 *
 * After every successful write it re-fetches and calls onChanged(freshDetail)
 * so the parent table overlay reflects the change. onChanged(null) signals the
 * shipment was deleted.
 *
 * Never sends client-computed ids/ETA/cost/totals — only raw field values.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Truck, CreditCard, X, Pencil, Save, Plus, Trash2, AlertCircle, Loader2, Search } from 'lucide-react';
import type { SupplyShipmentRow } from '../../types';
import { dataEntry, type ShipmentDetail } from '../../utils/dataEntry';

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

function StatusBadge({ status }: { status: string }) {
  const s = (status || '').toUpperCase();
  let cls = 'bg-gray-500/15 text-gray-400';
  if (s === 'PUT_AWAY' || s === 'RECEIVED') cls = 'bg-emerald-500/15 text-emerald-400';
  else if (s === 'IN_TRANSIT' || s === 'SHIPPED') cls = 'bg-blue-500/15 text-blue-400';
  else if (s === 'INSPECTED') cls = 'bg-purple-500/15 text-purple-400';
  else if (s === 'PREPARING' || s === 'PENDING') cls = 'bg-amber-500/15 text-amber-400';
  return <span className={`inline-flex px-1.5 py-0.5 rounded-full text-[9px] font-semibold uppercase tracking-wider ${cls}`}>{status || '—'}</span>;
}

const inputCls = 'w-full rounded-lg border border-border bg-surface px-2.5 py-1.5 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50';
const numInputCls = 'w-20 rounded border border-border bg-black/40 px-1.5 py-0.5 text-xs text-right text-heading font-mono focus:outline-none focus:border-blue-500';

type LineField = 'quantity_shipped' | 'allocated_cost';

/** Open-PO line shape returned by /api/open-pos (mirrors NewShipmentModal). */
interface OpenPOLine {
  purchase_order_id: string;
  product_id: number;
  product_name: string | null;
  product_asin: string | null;
  manufacturer_name: string | null;
  remaining_quantity: number;
  order_quantity: number;
}

interface ShipmentDetailDrawerProps {
  shipment: SupplyShipmentRow;
  onClose: () => void;
  onChanged: (detail: ShipmentDetail | null) => void;
}

export default function ShipmentDetailDrawer({ shipment, onClose, onChanged }: ShipmentDetailDrawerProps) {
  const shipmentId = shipment.shipment_id;

  const [detail, setDetail] = useState<ShipmentDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // ── Header edit state ──
  const [editingHeader, setEditingHeader] = useState(false);
  const [hDeliverer, setHDeliverer] = useState('');
  const [hShipmentDate, setHShipmentDate] = useState('');
  const [hEta, setHEta] = useState('');
  const [hType, setHType] = useState('');
  const [hStatus, setHStatus] = useState('');
  const [hTracking, setHTracking] = useState('');
  const [hCostShipped, setHCostShipped] = useState('');
  const [hAmazonCommission, setHAmazonCommission] = useState('');
  const [hKgPrice, setHKgPrice] = useState('');
  const [hIsPaid, setHIsPaid] = useState(false);
  const [hPaidDate, setHPaidDate] = useState('');
  const [hNotes, setHNotes] = useState('');

  // ── Add line state (open-PO picker) ──
  const [openPos, setOpenPos] = useState<OpenPOLine[]>([]);
  const [openPosLoading, setOpenPosLoading] = useState(false);
  const [pickerSearch, setPickerSearch] = useState('');
  const [pickKey, setPickKey] = useState('');   // `${po}_${product_id}`
  const [pickQty, setPickQty] = useState('');

  // ── Per-line draft values (keyed by line_id) ──
  const [lineDrafts, setLineDrafts] = useState<Record<string, { quantity_shipped: string; allocated_cost: string }>>({});

  // ── Delete-shipment confirm ──
  const [confirmDelete, setConfirmDelete] = useState(false);

  // ── In-flight write guard (ref so closure captures current value) ──
  const busyRef = useRef(false);

  const fetchDetail = useCallback(async () => {
    return dataEntry.getShipment(shipmentId);
  }, [shipmentId]);

  // Initial load
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setLoadError(null);
    fetchDetail()
      .then((d) => { if (!cancelled) { setDetail(d); } })
      .catch((e) => { if (!cancelled) setLoadError(e instanceof Error ? e.message : 'Failed to load shipment'); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [fetchDetail]);

  // Load open-PO lines once for the add-line picker
  useEffect(() => {
    let cancelled = false;
    setOpenPosLoading(true);
    dataEntry.getOpenPOs()
      .then((raw) => { if (!cancelled) setOpenPos(raw as unknown as OpenPOLine[]); })
      .catch(() => { /* non-fatal — picker shows empty */ })
      .finally(() => { if (!cancelled) setOpenPosLoading(false); });
    return () => { cancelled = true; };
  }, []);

  // Sync header edit fields + line drafts whenever detail changes
  useEffect(() => {
    if (!detail) return;
    setHDeliverer(str(detail.deliverer));
    setHShipmentDate(str(detail.shipment_date));
    setHEta(str(detail.estimated_arrival_date));
    setHType(str(detail.shipment_type));
    setHStatus(str(detail.shipment_status));
    setHTracking(str(detail.tracking_number));
    setHCostShipped(detail.cost_shipped == null ? '' : String(num(detail.cost_shipped)));
    setHAmazonCommission(detail.amazon_commission == null ? '' : String(num(detail.amazon_commission)));
    setHKgPrice(detail.kg_price == null ? '' : String(num(detail.kg_price)));
    setHIsPaid(Boolean(detail.is_paid));
    setHPaidDate(str(detail.paid_date));
    setHNotes(str(detail.notes));
    const drafts: Record<string, { quantity_shipped: string; allocated_cost: string }> = {};
    for (const l of detail.lines) {
      const lid = str(l.line_id);
      drafts[lid] = {
        quantity_shipped: String(num(l.quantity_shipped)),
        allocated_cost: String(num(l.allocated_cost)),
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
    const d = detail;
    return {
      deliverer: d ? str(d.deliverer) : '',
      shipment_date: d ? str(d.shipment_date) : shipment.shipment_date,
      estimated_arrival_date: d ? (d.estimated_arrival_date == null ? null : str(d.estimated_arrival_date)) : shipment.estimated_arrival_date,
      shipment_type: d ? str(d.shipment_type) : shipment.shipment_type,
      shipment_status: d ? str(d.shipment_status) : shipment.shipment_status,
      tracking_number: d ? (d.tracking_number == null ? null : str(d.tracking_number)) : shipment.tracking_number,
      cost_shipped: d ? num(d.cost_shipped) : shipment.cost_shipped,
      amazon_commission: d ? num(d.amazon_commission) : 0,
      kg_price: d ? num(d.kg_price) : 0,
      is_paid: d ? Boolean(d.is_paid) : shipment.is_paid,
      paid_date: d ? (d.paid_date == null ? null : str(d.paid_date)) : shipment.paid_date,
      notes: d ? (d.notes == null ? null : str(d.notes)) : shipment.notes,
    };
  }, [detail, shipment]);

  const lines = useMemo(() => detail?.lines ?? [], [detail]);

  // ── Aggregate totals from authoritative lines ──
  const agg = useMemo(() => {
    let qty = 0, cost = 0;
    for (const l of lines) {
      qty += num(l.quantity_shipped);
      cost += num(l.allocated_cost);
    }
    return { qty, cost };
  }, [lines]);

  // ── Add-line picker derived rows ──
  const filteredOpenPos = useMemo(() => {
    if (!pickerSearch.trim()) return openPos;
    const q = pickerSearch.toLowerCase();
    return openPos.filter((r) =>
      (r.product_name ?? '').toLowerCase().includes(q) ||
      (r.product_asin ?? '').toLowerCase().includes(q) ||
      r.purchase_order_id.toLowerCase().includes(q) ||
      (r.manufacturer_name ?? '').toLowerCase().includes(q),
    );
  }, [openPos, pickerSearch]);

  const pickedRow = useMemo(
    () => openPos.find((r) => `${r.purchase_order_id}_${r.product_id}` === pickKey) ?? null,
    [openPos, pickKey],
  );

  // ── Line write handlers ──
  const setDraft = (lid: string, field: LineField, value: string) => {
    setLineDrafts((prev) => ({ ...prev, [lid]: { ...prev[lid], [field]: value } }));
  };

  const saveLineField = (lid: string, field: LineField) => {
    const draft = lineDrafts[lid];
    if (!draft) return;
    const value = num(draft[field]);
    void runWrite(() => dataEntry.updateShipmentLine(shipmentId, lid, { [field]: value }));
  };

  const deleteLine = (lid: string) => {
    void runWrite(() => dataEntry.deleteShipmentLine(shipmentId, lid));
  };

  const addLine = () => {
    if (!pickedRow) { setActionError('Select an open PO line to add.'); return; }
    const cap = pickedRow.remaining_quantity;
    const qty = Math.min(Math.max(1, num(pickQty)), cap > 0 ? cap : num(pickQty));
    void runWrite(async () => {
      await dataEntry.addShipmentLine(shipmentId, {
        purchase_order_id: pickedRow.purchase_order_id,
        product_id: pickedRow.product_id,
        quantity_shipped: qty,
      });
      setPickKey('');
      setPickQty('');
      setPickerSearch('');
    });
  };

  const saveHeader = () => {
    const body: Record<string, unknown> = {
      deliverer: hDeliverer,
      shipment_date: hShipmentDate,
      shipment_type: hType,
      shipment_status: hStatus,
      tracking_number: hTracking,
      notes: hNotes,
      is_paid: hIsPaid,
    };
    if (hEta.trim() !== '') body.estimated_arrival_date = hEta;
    if (hCostShipped.trim() !== '') body.cost_shipped = num(hCostShipped);
    if (hAmazonCommission.trim() !== '') body.amazon_commission = num(hAmazonCommission);
    if (hKgPrice.trim() !== '') body.kg_price = num(hKgPrice);
    if (hIsPaid && hPaidDate.trim() !== '') body.paid_date = hPaidDate;
    void runWrite(async () => {
      await dataEntry.updateShipmentHeader(shipmentId, body);
      setEditingHeader(false);
    });
  };

  const doDeleteShipment = async () => {
    if (busyRef.current) return;
    busyRef.current = true;
    setActionError(null);
    setBusy(true);
    try {
      await dataEntry.deleteShipment(shipmentId);
      onChanged(null);
      onClose();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Failed to delete shipment');
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
            <div className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0 bg-amber-500/10">
              <Truck size={16} className="text-amber-400" />
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <h2 className="text-sm font-bold text-heading truncate" title={shipmentId}>{shipmentId}</h2>
                <StatusBadge status={headerView.shipment_status} />
                {headerView.is_paid
                  ? <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 font-semibold">Paid</span>
                  : <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-amber-500/10 text-amber-400 font-semibold">Unpaid</span>}
              </div>
              <div className="flex items-center gap-3 text-[10px] text-muted mt-0.5">
                {headerView.deliverer && <><span>{headerView.deliverer}</span><span>·</span></>}
                <span>{fmtDate(headerView.shipment_date)}</span>
                {headerView.estimated_arrival_date && <><span>·</span><span>ETA {fmtDate(headerView.estimated_arrival_date)}</span></>}
                {headerView.shipment_type && <><span>·</span><span>{headerView.shipment_type}</span></>}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-1.5 shrink-0">
            {!loading && !loadError && (
              <button
                onClick={() => setEditingHeader((v) => !v)}
                className="p-1.5 rounded-lg hover:bg-white/5 transition-colors text-muted hover:text-heading"
                title="Edit shipment header"
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
              <Loader2 size={16} className="animate-spin" /> Loading shipment details…
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
                <Pencil size={11} /> Edit Header
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Deliverer</label>
                  <input className={inputCls} value={hDeliverer} onChange={(e) => setHDeliverer(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Shipment Date</label>
                  <input type="date" className={inputCls} value={hShipmentDate ? hShipmentDate.slice(0, 10) : ''} onChange={(e) => setHShipmentDate(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Est. Arrival</label>
                  <input type="date" className={inputCls} value={hEta ? hEta.slice(0, 10) : ''} onChange={(e) => setHEta(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Type</label>
                  <input className={inputCls} value={hType} onChange={(e) => setHType(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Status</label>
                  <select className={inputCls} value={hStatus} onChange={(e) => setHStatus(e.target.value)}>
                    <option value="">—</option>
                    <option value="PREPARING">Preparing</option>
                    <option value="SHIPPED">Shipped</option>
                    <option value="IN_TRANSIT">In Transit</option>
                    <option value="RECEIVED">Received</option>
                    <option value="INSPECTED">Inspected</option>
                    <option value="PUT_AWAY">Put Away</option>
                  </select>
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Tracking</label>
                  <input className={inputCls} value={hTracking} onChange={(e) => setHTracking(e.target.value)} />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Cost Shipped</label>
                  <input type="number" step="0.01" className={inputCls} value={hCostShipped} onChange={(e) => setHCostShipped(e.target.value)} placeholder="0.00" />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Amazon Commission</label>
                  <input type="number" step="0.01" className={inputCls} value={hAmazonCommission} onChange={(e) => setHAmazonCommission(e.target.value)} placeholder="0.00" />
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">KG Price</label>
                  <input type="number" step="0.01" className={inputCls} value={hKgPrice} onChange={(e) => setHKgPrice(e.target.value)} placeholder="0.00" />
                </div>
              </div>
              <div className="flex items-center gap-4">
                <label className="flex items-center gap-2 cursor-pointer select-none">
                  <input type="checkbox" checked={hIsPaid} onChange={(e) => setHIsPaid(e.target.checked)} className="w-3.5 h-3.5 rounded accent-blue-500" />
                  <span className="text-xs text-heading font-medium">Paid</span>
                </label>
                {hIsPaid && (
                  <div className="flex flex-col gap-1">
                    <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Paid Date</label>
                    <input type="date" className={inputCls} value={hPaidDate ? hPaidDate.slice(0, 10) : ''} onChange={(e) => setHPaidDate(e.target.value)} />
                  </div>
                )}
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

          {/* ── Lines (editable) ── */}
          {!loading && !loadError && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <Truck size={11} /> Lines ({lines.length})
              </div>
              <div className="rounded-lg border border-border overflow-hidden">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="bg-surface/50 border-b border-border">
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Product</th>
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">PO</th>
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Qty Shipped</th>
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Allocated Cost</th>
                      <th className="px-2 py-1.5"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {lines.length === 0 && (
                      <tr><td colSpan={5} className="px-3 py-4 text-center text-muted">No lines on this shipment.</td></tr>
                    )}
                    {lines.map((l, i) => {
                      const lid = str(l.line_id);
                      const draft = lineDrafts[lid] ?? { quantity_shipped: '', allocated_cost: '' };
                      return (
                        <tr key={`${lid}_${i}`} className="border-b border-border/30 hover:bg-white/[.02]">
                          <td className="px-3 py-1.5 text-heading font-medium truncate max-w-[200px]" title={str(l.product_name)}>
                            {str(l.product_name) || '—'}
                            <span className="ml-1 text-faint font-mono text-[9px]">{str(l.product_asin)}</span>
                          </td>
                          <td className="px-3 py-1.5 text-muted font-mono text-[10px] truncate max-w-[140px]" title={str(l.purchase_order_id)}>{str(l.purchase_order_id) || '—'}</td>
                          <td className="px-3 py-1.5 text-right">
                            <div className="flex items-center justify-end gap-1">
                              <input
                                className={numInputCls + ' w-16'}
                                type="number"
                                value={draft.quantity_shipped}
                                onChange={(e) => setDraft(lid, 'quantity_shipped', e.target.value)}
                                disabled={busy}
                              />
                              {String(num(draft.quantity_shipped)) !== String(num(l.quantity_shipped)) && (
                                <button onClick={() => saveLineField(lid, 'quantity_shipped')} disabled={busy} className="text-emerald-400 hover:text-emerald-300 p-0.5" title="Save quantity"><Save size={12} /></button>
                              )}
                            </div>
                          </td>
                          <td className="px-3 py-1.5 text-right">
                            <div className="flex items-center justify-end gap-1">
                              <input
                                className={numInputCls}
                                type="number"
                                step="0.01"
                                value={draft.allocated_cost}
                                onChange={(e) => setDraft(lid, 'allocated_cost', e.target.value)}
                                disabled={busy}
                              />
                              {String(num(draft.allocated_cost)) !== String(num(l.allocated_cost)) && (
                                <button onClick={() => saveLineField(lid, 'allocated_cost')} disabled={busy} className="text-emerald-400 hover:text-emerald-300 p-0.5" title="Save cost"><Save size={12} /></button>
                              )}
                            </div>
                          </td>
                          <td className="px-2 py-1.5 text-right">
                            <button
                              onClick={() => deleteLine(lid)}
                              disabled={busy}
                              className="p-1 rounded text-muted hover:text-negative hover:bg-[var(--color-negative)]/10 transition-colors disabled:opacity-30"
                              title="Delete line"
                            >
                              <Trash2 size={12} />
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>

              {/* Add line — open-PO picker */}
              <div className="mt-2 rounded-lg border border-border bg-surface/40 px-3 py-2.5 space-y-2">
                <div className="text-[9px] text-faint uppercase tracking-wider font-semibold">Add Line from Open PO</div>
                <div className="relative">
                  <Search size={12} className="absolute left-3 top-1/2 -translate-y-1/2 text-faint pointer-events-none" />
                  <input
                    type="text"
                    value={pickerSearch}
                    onChange={(e) => setPickerSearch(e.target.value)}
                    placeholder="Search product, ASIN, PO ID, manufacturer…"
                    className="w-full rounded-lg border border-border bg-surface pl-8 pr-3 py-1.5 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50"
                  />
                </div>
                <div className="grid grid-cols-[1fr_80px_auto] gap-2 items-end">
                  <div className="flex flex-col gap-1">
                    <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">Open PO Line</label>
                    <select
                      className={inputCls}
                      value={pickKey}
                      onChange={(e) => { setPickKey(e.target.value); setPickQty(''); }}
                      disabled={openPosLoading}
                    >
                      <option value="">{openPosLoading ? 'Loading…' : '-- Select --'}</option>
                      {filteredOpenPos.map((r) => (
                        <option key={`${r.purchase_order_id}_${r.product_id}`} value={`${r.purchase_order_id}_${r.product_id}`}>
                          {(r.product_name ?? '—')} · {r.purchase_order_id} (rem {r.remaining_quantity.toLocaleString()})
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="flex flex-col gap-1">
                    <label className="text-[9px] text-faint uppercase tracking-wider font-semibold">
                      Qty{pickedRow ? ` ≤ ${pickedRow.remaining_quantity.toLocaleString()}` : ''}
                    </label>
                    <input
                      type="number"
                      min={1}
                      max={pickedRow ? pickedRow.remaining_quantity : undefined}
                      value={pickQty}
                      onChange={(e) => {
                        const v = parseInt(e.target.value, 10);
                        if (isNaN(v)) { setPickQty(''); return; }
                        const cap = pickedRow ? pickedRow.remaining_quantity : v;
                        setPickQty(String(Math.min(Math.max(0, v), cap > 0 ? cap : v)));
                      }}
                      placeholder="0"
                      className={inputCls + ' text-center font-mono'}
                    />
                  </div>
                  <button
                    onClick={addLine}
                    disabled={busy || !pickedRow || num(pickQty) < 1}
                    className="flex items-center gap-1 px-3 py-2 rounded-lg text-[11px] font-semibold bg-blue-600 hover:bg-blue-500 text-white transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    <Plus size={13} /> Add
                  </button>
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
              <div className="rounded-lg border border-border bg-surface/30 px-3 py-2.5 space-y-1.5 text-xs">
                <div className="flex items-center justify-between">
                  <span className="text-muted">Shipment Cost</span>
                  <span className="text-heading font-mono font-semibold">{fmtFull$(headerView.cost_shipped)}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted">Allocated to lines</span>
                  <span className="text-heading font-mono">{fmtFull$(agg.cost)}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-muted">Total units shipped</span>
                  <span className="text-heading font-mono">{agg.qty.toLocaleString()}</span>
                </div>
                {headerView.amazon_commission > 0 && (
                  <div className="flex items-center justify-between">
                    <span className="text-muted">Amazon commission</span>
                    <span className="text-heading font-mono">{fmtFull$(headerView.amazon_commission)}</span>
                  </div>
                )}
                <div className="flex items-center justify-between">
                  <span className="text-muted">Paid</span>
                  <span className={headerView.is_paid ? 'text-emerald-400 font-mono' : 'text-amber-400 font-mono'}>
                    {headerView.is_paid ? `Yes${headerView.paid_date ? ` · ${fmtDate(headerView.paid_date)}` : ''}` : 'No'}
                  </span>
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

        {/* ─── Footer: delete shipment ─── */}
        {!loading && !loadError && (
          <div className="flex items-center justify-between gap-3 px-5 py-3 border-t border-border bg-surface/50 shrink-0">
            {confirmDelete ? (
              <div className="flex items-center gap-3 w-full">
                <span className="text-xs text-negative flex items-center gap-1.5"><AlertCircle size={13} /> Delete this shipment and all its lines?</span>
                <div className="flex-1" />
                <button
                  onClick={() => setConfirmDelete(false)}
                  disabled={busy}
                  className="px-3 py-1.5 rounded-lg text-xs font-medium text-muted hover:text-heading border border-border hover:bg-white/5 transition-colors"
                >Cancel</button>
                <button
                  onClick={doDeleteShipment}
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
                  <Trash2 size={13} /> Delete Shipment
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
