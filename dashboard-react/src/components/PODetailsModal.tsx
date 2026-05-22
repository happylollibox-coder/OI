/**
 * PO Details Modal — Compact redesign
 * Addresses: compact shipments, smart Ready logic, inline financials,
 * per-product breakdown for multi-product POs, visual pipeline bar
 */
import { useMemo } from 'react';
import { Package, CreditCard, Truck, X } from 'lucide-react';
import type { SupplyPORow, SupplyPaymentRow, SupplyShipmentRow } from '../types';

/* ── helpers ── */
const fmtDate = (d: string | null | undefined) => {
  if (!d) return '—';
  const dt = new Date(d + 'T00:00:00');
  return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
};
const fmtFull$ = (n: number) =>
  n.toLocaleString('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 });

function ShipmentStatusBadge({ status }: { status: string }) {
  const s = (status || '').toLowerCase();
  const cls = s.includes('receiv') || s.includes('arrived')
    ? 'bg-emerald-500/15 text-emerald-400'
    : s.includes('transit') || s.includes('ship')
    ? 'bg-blue-500/15 text-blue-400'
    : s.includes('ready')
    ? 'bg-purple-500/15 text-purple-400'
    : 'bg-white/10 text-muted';
  return (
    <span className={`inline-flex px-1.5 py-0.5 rounded-full text-[9px] font-semibold uppercase tracking-wider ${cls}`}>
      {status || '—'}
    </span>
  );
}

function StatusBadge({ status }: { status: string }) {
  const s = (status || '').toLowerCase();
  const cls = s === 'paid' ? 'bg-emerald-500/15 text-emerald-400'
    : s === 'partial' ? 'bg-amber-500/15 text-amber-400'
    : 'bg-red-500/15 text-red-400';
  return <span className={`inline-flex px-1.5 py-0.5 rounded-full text-[9px] font-semibold uppercase tracking-wider ${cls}`}>{status || '—'}</span>;
}

/* ════════════════════════════════════════════════════════════════
 * MAIN COMPONENT
 * ════════════════════════════════════════════════════════════════ */
export default function PODetailsModal({ po, allPORows, payments, shipments, onClose }: {
  po: SupplyPORow;
  allPORows: SupplyPORow[];
  payments: SupplyPaymentRow[];
  shipments: SupplyShipmentRow[];
  onClose: () => void;
}) {
  // Gather all rows for this PO (multi-product support)
  const poLines = useMemo(() =>
    allPORows.filter(r => r.purchase_order_id === po.purchase_order_id),
  [allPORows, po.purchase_order_id]);

  // Aggregated totals across all product lines
  const agg = useMemo(() => {
    let qty = 0, shipped = 0, ready = 0, remaining = 0;
    let cost = 0, paid = 0, unpaidMfr = 0;
    let shipCost = 0, shipPaid = 0, shipUnpaid = 0;
    for (const r of poLines) {
      qty += r.quantity;
      shipped += r.total_quantity_shipped || 0;
      ready += r.ready_quantity || 0;
      remaining += r.remaining_to_ship;
      cost += r.total_amount;
      paid += r.total_paid;
      unpaidMfr += Math.max(r.unpaid_manufacturer, 0);
      shipCost += r.total_shipment_cost;
      shipPaid += r.paid_shipment_cost;
      shipUnpaid += Math.max(r.unpaid_shipment, 0);
    }
    return { qty, shipped, ready, remaining, cost, paid, unpaidMfr, shipCost, shipPaid, shipUnpaid };
  }, [poLines]);

  const poPayments = useMemo(() =>
    payments.filter(p => p.purchase_order_id === po.purchase_order_id),
  [payments, po.purchase_order_id]);

  const poShipments = useMemo(() => {
    const names = poLines.map(r => r.product_name?.toLowerCase()).filter(Boolean);
    const asins = poLines.map(r => r.product_asin?.toLowerCase()).filter(Boolean);
    return shipments.filter(s => {
      const list = (s.products_list || '').toLowerCase();
      return names.some(n => list.includes(n)) || asins.some(a => list.includes(a));
    });
  }, [shipments, poLines]);

  const paidPct = agg.cost > 0 ? Math.min((agg.paid / agg.cost) * 100, 100) : 0;

  // Pipeline: Ordered → In Production → Ready → Shipped
  // "In Production" = ordered - ready - shipped (units still being made)
  const inProduction = Math.max(0, agg.qty - agg.ready - agg.shipped);
  // Only show "Ready" segment if there are actually units ready but not yet shipped
  const showReady = agg.ready > 0 && agg.shipped < agg.qty;
  const pipeTotal = agg.qty || 1;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      onClick={onClose}
      style={{ background: 'rgba(0,0,0,.6)', backdropFilter: 'blur(6px)' }}
    >
      <div
        className="relative w-full max-w-[680px] max-h-[85vh] rounded-2xl border border-border bg-card shadow-2xl overflow-hidden flex flex-col"
        onClick={e => e.stopPropagation()}
      >
        {/* ─── Header ─── */}
        <div className="flex items-center justify-between px-5 py-3 border-b border-border bg-surface/50">
          <div className="flex items-center gap-2.5 min-w-0">
            <div className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0" style={{ background: '#3b82f620' }}>
              <Package size={16} className="text-blue-400" />
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <h2 className="text-sm font-bold text-heading truncate" title={po.purchase_order_id}>{po.purchase_order_id}</h2>
                <StatusBadge status={po.payment_status} />
                {po.is_open
                  ? <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-blue-500/10 text-blue-400 font-semibold">Open</span>
                  : <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-gray-500/10 text-gray-400 font-semibold">Closed</span>
                }
              </div>
              <div className="flex items-center gap-3 text-[10px] text-muted mt-0.5">
                <span>{po.manufacturer_name}</span>
                <span>·</span>
                <span>{fmtDate(po.order_date)}</span>
                {po.expected_ready_date && <>
                  <span>·</span>
                  <span>Ready {fmtDate(po.expected_ready_date)}</span>
                </>}
                {po.currency && po.currency !== 'USD' && <>
                  <span>·</span>
                  <span>{po.currency}</span>
                </>}
              </div>
            </div>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-white/5 transition-colors text-muted hover:text-heading">
            <X size={16} />
          </button>
        </div>

        {/* ─── Scrollable content ─── */}
        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4" style={{ scrollbarWidth: 'thin', scrollbarColor: 'var(--color-border) transparent' }}>

          {/* ── Products table (multi-product breakdown) ── */}
          <div>
            <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
              <Package size={11} /> Products ({poLines.length})
            </div>
            <div className="rounded-lg border border-border overflow-hidden">
              <table className="w-full text-xs">
                <thead>
                  <tr className="bg-surface/50 border-b border-border">
                    <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Product</th>
                    <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">ASIN</th>
                    <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Ordered</th>
                    <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Shipped</th>
                    <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Remaining</th>
                  </tr>
                </thead>
                <tbody>
                  {poLines.map((r, i) => (
                    <tr key={`${r.product_id}_${i}`} className="border-b border-border/30 hover:bg-white/[.02]">
                      <td className="px-3 py-1.5 text-heading font-medium truncate max-w-[200px]" title={r.product_name}>{r.product_name}</td>
                      <td className="px-3 py-1.5 text-muted font-mono text-[10px]">{r.product_asin || '—'}</td>
                      <td className="px-3 py-1.5 text-right font-mono font-semibold text-heading">{r.quantity.toLocaleString()}</td>
                      <td className="px-3 py-1.5 text-right font-mono text-emerald-400">{(r.total_quantity_shipped || 0).toLocaleString()}</td>
                      <td className="px-3 py-1.5 text-right font-mono">
                        <span className={r.remaining_to_ship > 0 ? 'text-amber-400' : 'text-emerald-400'}>{r.remaining_to_ship.toLocaleString()}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
                {poLines.length > 1 && (
                  <tfoot>
                    <tr className="border-t border-border bg-surface/30">
                      <td colSpan={2} className="px-3 py-1.5 text-[10px] font-semibold text-faint uppercase">Total</td>
                      <td className="px-3 py-1.5 text-right font-mono font-bold text-heading text-[11px]">{agg.qty.toLocaleString()}</td>
                      <td className="px-3 py-1.5 text-right font-mono font-bold text-emerald-400 text-[11px]">{agg.shipped.toLocaleString()}</td>
                      <td className="px-3 py-1.5 text-right font-mono font-bold text-[11px]">
                        <span className={agg.remaining > 0 ? 'text-amber-400' : 'text-emerald-400'}>{agg.remaining.toLocaleString()}</span>
                      </td>
                    </tr>
                  </tfoot>
                )}
              </table>
            </div>
          </div>

          {/* ── Fulfillment Pipeline ── */}
          <div>
            <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
              <Truck size={11} /> Fulfillment Pipeline
            </div>
            <div className="rounded-lg border border-border bg-surface/30 p-3">
              {/* Segmented bar */}
              <div className="flex h-5 rounded-full overflow-hidden bg-white/[.04]">
                {agg.shipped > 0 && (
                  <div
                    className="bg-emerald-500/70 flex items-center justify-center text-[8px] font-bold text-white/90 transition-all"
                    style={{ width: `${(agg.shipped / pipeTotal) * 100}%`, minWidth: agg.shipped > 0 ? '24px' : 0 }}
                    title={`Shipped: ${agg.shipped.toLocaleString()}`}
                  >{agg.shipped > 0 ? agg.shipped.toLocaleString() : ''}</div>
                )}
                {showReady && (
                  <div
                    className="bg-purple-500/60 flex items-center justify-center text-[8px] font-bold text-white/90 transition-all"
                    style={{ width: `${(agg.ready / pipeTotal) * 100}%`, minWidth: agg.ready > 0 ? '24px' : 0 }}
                    title={`Ready to Ship: ${agg.ready.toLocaleString()}`}
                  >{agg.ready.toLocaleString()}</div>
                )}
                {inProduction > 0 && (
                  <div
                    className="bg-amber-500/40 flex items-center justify-center text-[8px] font-bold text-white/60 transition-all"
                    style={{ width: `${(inProduction / pipeTotal) * 100}%`, minWidth: '24px' }}
                    title={`In Production: ${inProduction.toLocaleString()}`}
                  >{inProduction.toLocaleString()}</div>
                )}
              </div>
              {/* Legend */}
              <div className="flex items-center gap-4 mt-2 text-[10px]">
                <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-emerald-500/70" />Shipped ({agg.shipped.toLocaleString()})</span>
                {showReady && <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-purple-500/60" />Ready ({agg.ready.toLocaleString()})</span>}
                {inProduction > 0 && <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-amber-500/40" />In Production ({inProduction.toLocaleString()})</span>}
                <span className="ml-auto text-muted font-mono font-semibold">{((agg.shipped / pipeTotal) * 100).toFixed(0)}% fulfilled</span>
              </div>
            </div>
          </div>

          {/* ── Financial Summary (compact inline) ── */}
          <div>
            <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
              <CreditCard size={11} /> Financials
            </div>
            <div className="rounded-lg border border-border bg-surface/30 px-3 py-2.5">
              {/* MFR Cost row */}
              <div className="flex items-center justify-between text-xs mb-1.5">
                <span className="text-muted">Manufacturer</span>
                <div className="flex items-center gap-4 font-mono text-[11px]">
                  <span className="text-heading font-semibold">{fmtFull$(agg.cost)}</span>
                  <span className="text-emerald-400">{fmtFull$(agg.paid)}</span>
                  <span className={agg.unpaidMfr > 0.01 ? 'text-red-400 font-semibold' : 'text-emerald-400'}>
                    {agg.unpaidMfr > 0.01 ? `-${fmtFull$(agg.unpaidMfr)}` : '✓'}
                  </span>
                </div>
              </div>
              {/* Payment progress */}
              <div className="flex items-center gap-2 mb-2">
                <div className="flex-1 h-1.5 rounded-full bg-white/[.06] overflow-hidden">
                  <div
                    className={`h-full rounded-full transition-all ${paidPct >= 100 ? 'bg-emerald-400' : paidPct >= 50 ? 'bg-blue-400' : 'bg-amber-400'}`}
                    style={{ width: `${paidPct}%` }}
                  />
                </div>
                <span className="text-[9px] font-mono text-muted shrink-0">{paidPct.toFixed(0)}%</span>
              </div>
              {/* Shipment cost row */}
              {agg.shipCost > 0 && (
                <div className="flex items-center justify-between text-xs border-t border-border/30 pt-1.5">
                  <span className="text-muted">Shipping</span>
                  <div className="flex items-center gap-4 font-mono text-[11px]">
                    <span className="text-heading font-semibold">{fmtFull$(agg.shipCost)}</span>
                    <span className="text-emerald-400">{fmtFull$(agg.shipPaid)}</span>
                    <span className={agg.shipUnpaid > 0.01 ? 'text-orange-400' : 'text-emerald-400'}>
                      {agg.shipUnpaid > 0.01 ? `-${fmtFull$(agg.shipUnpaid)}` : '✓'}
                    </span>
                  </div>
                </div>
              )}
            </div>
            {/* Labels under the numbers */}
            <div className="flex justify-end gap-4 mt-0.5 text-[8px] text-faint uppercase tracking-widest pr-3">
              <span>Cost</span><span>Paid</span><span>Unpaid</span>
            </div>
          </div>

          {/* ── Linked Shipments (compact table) ── */}
          {poShipments.length > 0 && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <Truck size={11} /> Shipments ({poShipments.length})
              </div>
              <div className="rounded-lg border border-border overflow-hidden">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="bg-surface/50 border-b border-border">
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">ID</th>
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Ship</th>
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Arrival</th>
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Type</th>
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Qty</th>
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {poShipments.map(s => (
                      <tr key={s.shipment_id} className="border-b border-border/30 hover:bg-white/[.02]">
                        <td className="px-3 py-1.5 font-mono text-heading text-[10px] truncate max-w-[140px]" title={s.shipment_id}>{s.shipment_id}</td>
                        <td className="px-3 py-1.5 text-muted whitespace-nowrap">{fmtDate(s.shipment_date)}</td>
                        <td className="px-3 py-1.5 text-muted whitespace-nowrap">{s.estimated_arrival_date ? fmtDate(s.estimated_arrival_date) : '—'}</td>
                        <td className="px-3 py-1.5 text-muted">{s.shipment_type || '—'}</td>
                        <td className="px-3 py-1.5 text-right font-mono font-semibold text-heading">{s.total_quantity_shipped.toLocaleString()}</td>
                        <td className="px-3 py-1.5"><ShipmentStatusBadge status={s.shipment_status} /></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* ── Payment History ── */}
          <div>
            <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
              <CreditCard size={11} /> Payments ({poPayments.length})
            </div>
            {poPayments.length === 0 ? (
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
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Fee</th>
                      <th className="text-right px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Total</th>
                      <th className="text-left px-3 py-1.5 text-[10px] font-semibold text-faint uppercase tracking-wider">Method</th>
                    </tr>
                  </thead>
                  <tbody>
                    {poPayments.map((p, i) => (
                      <tr key={`${p.payment_id}_${i}`} className="border-b border-border/30 hover:bg-white/[.02]">
                        <td className="px-3 py-1.5 text-muted whitespace-nowrap">{fmtDate(p.payment_date)}</td>
                        <td className="px-3 py-1.5 text-subtle">{p.vendor_name}</td>
                        <td className="px-3 py-1.5 text-right font-mono font-semibold text-heading">{fmtFull$(p.payment_amount)}</td>
                        <td className="px-3 py-1.5 text-right font-mono text-amber-400">{p.bank_fee > 0 ? fmtFull$(p.bank_fee) : '—'}</td>
                        <td className="px-3 py-1.5 text-right font-mono font-semibold text-blue-400">{fmtFull$(p.total_amount)}</td>
                        <td className="px-3 py-1.5 text-muted">{p.payment_method || '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                  {poPayments.length > 1 && (
                    <tfoot>
                      <tr className="border-t border-border bg-surface/30">
                        <td colSpan={2} className="px-3 py-1.5 text-[10px] font-semibold text-faint uppercase">{poPayments.length} payments</td>
                        <td className="px-3 py-1.5 text-right font-mono font-semibold text-heading">{fmtFull$(poPayments.reduce((s, p) => s + p.payment_amount, 0))}</td>
                        <td className="px-3 py-1.5 text-right font-mono text-amber-400">{fmtFull$(poPayments.reduce((s, p) => s + p.bank_fee, 0))}</td>
                        <td className="px-3 py-1.5 text-right font-mono font-semibold text-blue-400">{fmtFull$(poPayments.reduce((s, p) => s + p.total_amount, 0))}</td>
                        <td></td>
                      </tr>
                    </tfoot>
                  )}
                </table>
              </div>
            )}
          </div>

          {/* ── Notes ── */}
          {po.notes && (
            <div className="text-xs text-subtle bg-surface/30 border border-border rounded-lg px-3 py-2">
              <span className="text-[9px] text-faint uppercase tracking-wider font-semibold mr-2">Notes:</span>
              {po.notes}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
