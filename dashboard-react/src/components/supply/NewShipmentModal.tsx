/**
 * NewShipmentModal — Create a new manufacturer shipment.
 * Field parity with data-entry-app/templates/shipment_form.html.
 *
 * Fields:
 *   Header: shipment_date (req), deliverer (req, SUPPLIER LOV filtered attr1_value=Deliverer),
 *           shipment_type (SHIPMENT_TYPE LOV), shipment_status (SHIPMENT_STATUS LOV),
 *           tracking_number (optional), cost_shipped (optional), amazon_commission (default 0),
 *           kg_price (optional), notes (optional), is_paid (checkbox → paid_date)
 *   Lines:  PO-line allocation table (getOpenPOs); qty ≤ remaining_quantity, optional cartons.
 *
 * Server computes ETA, cost allocation, total_quantity — NOT done client-side.
 */
import { useCallback, useEffect, useId, useRef, useState } from 'react';
import { X, Truck, Search } from 'lucide-react';
import {
  dataEntry,
  type CreateShipmentInput,
  type LovItem,
} from '../../utils/dataEntry';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface OpenPOLine {
  purchase_order_id: string;
  product_id: number;
  product_name: string | null;
  product_asin: string | null;
  manufacturer_name: string | null;
  remaining_quantity: number;
  order_quantity: number;
  total_shipped: number;
  package_quantity: number | null;
  package_cubic_feet: number | null;
  total_amount: number | null;
}

interface AllocationRow extends OpenPOLine {
  /** units to ship — user input, capped at remaining_quantity */
  qtyToShip: number;
  /** cartons — optional user input */
  cartons: string;
}

interface NewShipmentModalProps {
  onClose: () => void;
  onSaved: (shipmentId: string) => void;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function NewShipmentModal({ onClose, onSaved }: NewShipmentModalProps) {
  const formId = useId();

  // ── Header state ──
  const todayIso = new Date().toISOString().split('T')[0];
  const [shipmentDate, setShipmentDate] = useState(todayIso);
  const [deliverer, setDeliverer] = useState('');
  const [shipmentType, setShipmentType] = useState('');
  const [shipmentStatus, setShipmentStatus] = useState('');
  const [trackingNumber, setTrackingNumber] = useState('');
  const [costShipped, setCostShipped] = useState('');
  const [amazonCommission, setAmazonCommission] = useState('0');
  const [kgPrice, setKgPrice] = useState('');
  const [notes, setNotes] = useState('');
  const [isPaid, setIsPaid] = useState(false);
  const [paidDate, setPaidDate] = useState('');

  // ── LOVs ──
  const [deliverers, setDeliverers] = useState<LovItem[]>([]);
  const [shipmentTypes, setShipmentTypes] = useState<LovItem[]>([]);
  const [shipmentStatuses, setShipmentStatuses] = useState<LovItem[]>([]);
  const [lovsLoading, setLovsLoading] = useState(true);

  // ── PO allocation ──
  const [allRows, setAllRows] = useState<AllocationRow[]>([]);
  const [posLoading, setPosLoading] = useState(true);
  const [search, setSearch] = useState('');

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

        // Deliverer: SUPPLIER items where attr1_value === 'Deliverer'
        const suppliers: LovItem[] = lovs['SUPPLIER'] ?? [];
        const dels = suppliers.filter(
          (s) => (s as Record<string, unknown>)['attr1_value'] === 'Deliverer',
        );
        setDeliverers(dels);
        const defDel = dels.find((d) => d.is_default);
        if (defDel) setDeliverer(defDel.value_id);

        const types: LovItem[] = lovs['SHIPMENT_TYPE'] ?? [];
        setShipmentTypes(types);
        const defType = types.find((t) => t.is_default);
        if (defType) setShipmentType(defType.value_id);

        const statuses: LovItem[] = lovs['SHIPMENT_STATUS'] ?? [];
        setShipmentStatuses(statuses);
        const defStatus = statuses.find((s) => s.is_default);
        if (defStatus) setShipmentStatus(defStatus.value_id);
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

  // ── Load open PO lines ──
  useEffect(() => {
    let cancelled = false;
    dataEntry
      .getOpenPOs()
      .then((raw) => {
        if (cancelled) return;
        const rows: AllocationRow[] = (raw as OpenPOLine[]).map((po) => ({
          ...po,
          qtyToShip: 0,
          cartons: '',
        }));
        setAllRows(rows);
      })
      .catch(() => {
        // Leave empty — user sees empty list
      })
      .finally(() => {
        if (!cancelled) setPosLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // ── Derived: filtered rows for display ──
  const filteredRows = search.trim()
    ? allRows.filter((r) => {
        const q = search.toLowerCase();
        return (
          (r.product_name ?? '').toLowerCase().includes(q) ||
          (r.product_asin ?? '').toLowerCase().includes(q) ||
          r.purchase_order_id.toLowerCase().includes(q) ||
          (r.manufacturer_name ?? '').toLowerCase().includes(q)
        );
      })
    : allRows;

  // ── Derived: total allocated units ──
  const totalAllocated = allRows.reduce((s, r) => s + r.qtyToShip, 0);

  // ── Row update helpers ──
  const updateQty = useCallback(
    (poId: string, productId: number, rawValue: number) => {
      setAllRows((prev) =>
        prev.map((r) => {
          if (r.purchase_order_id !== poId || r.product_id !== productId)
            return r;
          const clamped = Math.min(
            Math.max(0, rawValue || 0),
            r.remaining_quantity,
          );
          return { ...r, qtyToShip: clamped };
        }),
      );
    },
    [],
  );

  const updateCartons = useCallback(
    (poId: string, productId: number, value: string) => {
      setAllRows((prev) =>
        prev.map((r) =>
          r.purchase_order_id === poId && r.product_id === productId
            ? { ...r, cartons: value }
            : r,
        ),
      );
    },
    [],
  );

  // ── Submit ──
  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      setError(null);

      const activeLines = allRows.filter((r) => r.qtyToShip > 0);

      if (!shipmentDate) {
        setError('Shipment date is required.');
        return;
      }
      if (!deliverer) {
        setError('Deliverer is required.');
        return;
      }
      if (activeLines.length === 0) {
        setError('Allocate at least one PO line with quantity > 0.');
        return;
      }

      const input: CreateShipmentInput = {
        shipment_date: shipmentDate,
        deliverer,
        shipment_type: shipmentType,
        shipment_status: shipmentStatus || undefined,
        tracking_number: trackingNumber || undefined,
        cost_shipped: parseFloat(costShipped) || 0,
        amazon_commission: parseFloat(amazonCommission) || 0,
        kg_price: kgPrice ? parseFloat(kgPrice) : undefined,
        notes: notes || undefined,
        is_paid: isPaid || undefined,
        paid_date: isPaid && paidDate ? paidDate : undefined,
        lines: activeLines.map((r) => ({
          purchase_order_id: r.purchase_order_id,
          product_id: r.product_id,
          quantity: r.qtyToShip,
          cartons: r.cartons ? parseInt(r.cartons, 10) : undefined,
        })),
      };

      setSubmitting(true);
      try {
        const result = await dataEntry.createShipment(input);
        onSaved(result.shipment_id);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unknown error');
        setSubmitting(false);
      }
    },
    [
      allRows,
      shipmentDate,
      deliverer,
      shipmentType,
      shipmentStatus,
      trackingNumber,
      costShipped,
      amazonCommission,
      kgPrice,
      notes,
      isPaid,
      paidDate,
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

  // ── Shared input class ──
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
        className="relative w-full max-w-[860px] max-h-[90vh] rounded-2xl border border-border bg-card shadow-2xl overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* ─── Header ─── */}
        <div className="flex items-center justify-between px-5 py-3 border-b border-border bg-surface/50 shrink-0">
          <div className="flex items-center gap-2.5">
            <div
              className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0"
              style={{ background: '#f59e0b20' }}
            >
              <Truck size={16} className="text-amber-400" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-heading">
                New Manufacturer Shipment
              </h2>
              <p className="text-[10px] text-muted mt-0.5">
                Fill in details and allocate PO lines
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

          {/* ── Row 1: date, deliverer, type, status ── */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            {/* Shipment Date */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>
                Shipment Date <span className="text-negative">*</span>
              </label>
              <input
                ref={dateRef}
                type="date"
                required
                value={shipmentDate}
                onChange={(e) => setShipmentDate(e.target.value)}
                className={inputCls}
              />
            </div>

            {/* Deliverer */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>
                Deliverer <span className="text-negative">*</span>
              </label>
              <select
                required
                value={deliverer}
                onChange={(e) => setDeliverer(e.target.value)}
                className={inputCls}
                disabled={lovsLoading}
              >
                <option value="">
                  {lovsLoading ? 'Loading…' : '-- Select --'}
                </option>
                {deliverers.map((d) => (
                  <option key={d.value_id} value={d.value_id}>
                    {d.value_caption}
                  </option>
                ))}
              </select>
            </div>

            {/* Shipment Type */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>Shipment Type</label>
              <select
                value={shipmentType}
                onChange={(e) => setShipmentType(e.target.value)}
                className={inputCls}
                disabled={lovsLoading}
              >
                <option value="">
                  {lovsLoading ? 'Loading…' : '-- Select --'}
                </option>
                {shipmentTypes.map((t) => (
                  <option key={t.value_id} value={t.value_id}>
                    {t.value_caption}
                  </option>
                ))}
              </select>
            </div>

            {/* Shipment Status */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>Status</label>
              <select
                value={shipmentStatus}
                onChange={(e) => setShipmentStatus(e.target.value)}
                className={inputCls}
                disabled={lovsLoading}
              >
                <option value="">
                  {lovsLoading ? 'Loading…' : '-- Select --'}
                </option>
                {shipmentStatuses.map((s) => (
                  <option key={s.value_id} value={s.value_id}>
                    {s.value_caption}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* ── Row 2: tracking, cost_shipped, amazon_commission, kg_price ── */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            {/* Tracking / Warehouse ID */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>Warehouse ID / Tracking</label>
              <input
                type="text"
                value={trackingNumber}
                onChange={(e) => setTrackingNumber(e.target.value)}
                placeholder="Optional"
                className={inputCls}
              />
            </div>

            {/* Cost Shipped */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>Shipment Cost</label>
              <input
                type="number"
                step="0.01"
                min="0"
                value={costShipped}
                onChange={(e) => setCostShipped(e.target.value)}
                placeholder="0.00"
                className={inputCls}
              />
            </div>

            {/* Amazon Commission */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>Amazon Commission</label>
              <input
                type="number"
                step="0.01"
                min="0"
                value={amazonCommission}
                onChange={(e) => setAmazonCommission(e.target.value)}
                placeholder="0.00"
                className={inputCls}
              />
            </div>

            {/* KG Price */}
            <div className="flex flex-col gap-1">
              <label className={labelCls}>KG Price</label>
              <input
                type="number"
                step="0.01"
                min="0"
                value={kgPrice}
                onChange={(e) => setKgPrice(e.target.value)}
                placeholder="0.00"
                className={inputCls}
              />
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

          {/* ── Paid checkbox + paid_date ── */}
          <div className="flex items-center gap-4">
            <label className="flex items-center gap-2 cursor-pointer select-none">
              <input
                type="checkbox"
                checked={isPaid}
                onChange={(e) => setIsPaid(e.target.checked)}
                className="w-3.5 h-3.5 rounded accent-blue-500"
              />
              <span className="text-xs text-heading font-medium">Paid</span>
            </label>
            {isPaid && (
              <div className="flex flex-col gap-1">
                <label className={labelCls}>Paid Date</label>
                <input
                  type="date"
                  value={paidDate}
                  onChange={(e) => setPaidDate(e.target.value)}
                  className="rounded-lg border border-border bg-surface px-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50"
                />
              </div>
            )}
          </div>

          {/* ── PO-line Allocation Picker ── */}
          <div>
            <div className="flex items-center justify-between mb-2 gap-3">
              <span className={labelCls}>
                PO Line Allocation{' '}
                <span className="text-negative normal-case">*</span>
              </span>
              {totalAllocated > 0 && (
                <span className="text-[11px] font-mono text-blue-400 font-semibold">
                  {totalAllocated.toLocaleString()} units allocated
                </span>
              )}
            </div>

            {/* Search */}
            <div className="relative mb-2">
              <Search
                size={12}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-faint pointer-events-none"
              />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search by product, ASIN, PO ID, manufacturer…"
                className="w-full rounded-lg border border-border bg-surface pl-8 pr-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              />
            </div>

            {/* Table */}
            <div
              className="rounded-lg border border-border overflow-hidden"
              style={{ maxHeight: 320, overflowY: 'auto', scrollbarWidth: 'thin', scrollbarColor: 'var(--color-border) transparent' }}
            >
              {posLoading ? (
                <div className="flex items-center justify-center py-8 text-xs text-muted">
                  Loading open PO lines…
                </div>
              ) : filteredRows.length === 0 ? (
                <div className="flex items-center justify-center py-8 text-xs text-muted">
                  {search ? 'No lines match your search.' : 'No open PO lines available.'}
                </div>
              ) : (
                <table className="w-full border-collapse text-xs">
                  <thead className="sticky top-0 bg-surface z-10">
                    <tr className="border-b border-border">
                      <th className="text-left px-3 py-2 text-[10px] text-faint uppercase tracking-wider font-semibold whitespace-nowrap">
                        Product
                      </th>
                      <th className="text-left px-3 py-2 text-[10px] text-faint uppercase tracking-wider font-semibold whitespace-nowrap">
                        Manufacturer
                      </th>
                      <th className="text-right px-3 py-2 text-[10px] text-faint uppercase tracking-wider font-semibold whitespace-nowrap">
                        Remaining
                      </th>
                      <th className="text-center px-3 py-2 text-[10px] text-faint uppercase tracking-wider font-semibold whitespace-nowrap">
                        Qty to Ship
                      </th>
                      <th className="text-center px-3 py-2 text-[10px] text-faint uppercase tracking-wider font-semibold whitespace-nowrap">
                        Cartons
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredRows.map((row) => {
                      const key = `${row.purchase_order_id}_${row.product_id}`;
                      const isActive = row.qtyToShip > 0;
                      return (
                        <tr
                          key={key}
                          className={`border-b border-border last:border-b-0 transition-colors ${
                            isActive
                              ? 'bg-blue-500/5'
                              : 'hover:bg-white/3'
                          }`}
                        >
                          {/* Product info */}
                          <td className="px-3 py-2">
                            <div className="font-medium text-heading leading-tight">
                              {row.product_name ?? '—'}
                            </div>
                            <div className="text-[10px] text-muted mt-0.5 font-mono">
                              {row.product_asin ?? ''}
                              {row.product_asin && row.purchase_order_id
                                ? ' · '
                                : ''}
                              {row.purchase_order_id}
                            </div>
                          </td>

                          {/* Manufacturer */}
                          <td className="px-3 py-2 text-muted whitespace-nowrap">
                            {row.manufacturer_name ?? '—'}
                          </td>

                          {/* Remaining */}
                          <td className="px-3 py-2 text-right">
                            <span
                              className={`font-mono font-semibold ${
                                row.remaining_quantity <= 0
                                  ? 'text-negative'
                                  : 'text-heading'
                              }`}
                            >
                              {row.remaining_quantity.toLocaleString()}
                            </span>
                            <div className="text-[10px] text-faint">
                              of {row.order_quantity.toLocaleString()}
                            </div>
                          </td>

                          {/* Qty to ship */}
                          <td className="px-3 py-2 text-center">
                            <input
                              type="number"
                              min={0}
                              max={row.remaining_quantity}
                              value={row.qtyToShip === 0 ? '' : row.qtyToShip}
                              placeholder="0"
                              onChange={(e) => {
                                const v = parseInt(e.target.value, 10);
                                updateQty(
                                  row.purchase_order_id,
                                  row.product_id,
                                  isNaN(v) ? 0 : v,
                                );
                              }}
                              onBlur={(e) => {
                                // Clamp on blur in case browser allows exceeding max
                                const v = parseInt(e.target.value, 10);
                                updateQty(
                                  row.purchase_order_id,
                                  row.product_id,
                                  isNaN(v) ? 0 : v,
                                );
                              }}
                              className="w-20 rounded border border-border bg-surface px-2 py-1 text-xs text-heading font-mono text-center focus:outline-none focus:ring-1 focus:ring-blue-500/50"
                            />
                          </td>

                          {/* Cartons */}
                          <td className="px-3 py-2 text-center">
                            <input
                              type="number"
                              min={0}
                              value={row.cartons}
                              placeholder="—"
                              onChange={(e) =>
                                updateCartons(
                                  row.purchase_order_id,
                                  row.product_id,
                                  e.target.value,
                                )
                              }
                              className="w-16 rounded border border-border bg-surface px-2 py-1 text-xs text-heading font-mono text-center focus:outline-none focus:ring-1 focus:ring-blue-500/50"
                            />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
            </div>

            {/* Active allocation summary */}
            {totalAllocated > 0 && (
              <div className="mt-2 flex justify-end">
                <div className="rounded-lg border border-border bg-surface/30 px-4 py-2.5 min-w-[200px]">
                  <div className="flex items-center justify-between gap-8">
                    <span className="text-xs font-semibold text-heading">
                      Lines:
                    </span>
                    <span className="text-xs font-mono text-heading">
                      {allRows.filter((r) => r.qtyToShip > 0).length}
                    </span>
                  </div>
                  <div className="flex items-center justify-between gap-8 mt-0.5">
                    <span className="text-[10px] text-muted">
                      Total units:
                    </span>
                    <span className="text-sm font-bold font-mono text-blue-400">
                      {totalAllocated.toLocaleString()}
                    </span>
                  </div>
                </div>
              </div>
            )}
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
            className="px-4 py-2 rounded-lg text-xs font-semibold bg-amber-600 hover:bg-amber-500 text-white transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {submitting ? 'Saving…' : 'Create Shipment'}
          </button>
        </div>
      </div>
    </div>
  );
}
