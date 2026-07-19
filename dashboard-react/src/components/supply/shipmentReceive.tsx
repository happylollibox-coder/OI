/**
 * shipmentReceive — shared logic for user-confirmed shipment arrival.
 *
 * Arrival is now MANUAL only: a shipment counts as arrived when its status is one
 * of RECEIVED / INSPECTED / PUT_AWAY, set explicitly by a user. This module holds:
 *   - the received-status predicate + a "due to receive" classifier (pure, testable)
 *   - useShipmentsDueToReceive(): shipments whose ETA is within 3 days (or past) and
 *     not yet received — surfaced in the Home brief
 *   - useMarkReceived(): one-click "Mark received" write with optimistic UI + undo toast
 *   - <MarkReceivedButton>: the shared button
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { CheckCircle2, PackageCheck } from 'lucide-react';
import { cubeLoad } from '../../hooks/useCubeData';
import { dataEntry } from '../../utils/dataEntry';

export const RECEIVED_STATUSES = new Set(['RECEIVED', 'INSPECTED', 'PUT_AWAY']);
export const isReceived = (status: string): boolean => RECEIVED_STATUSES.has((status || '').toUpperCase());

const DAY_MS = 86_400_000;
const iso = (d: Date): string => d.toISOString().split('T')[0];
export const todayISO = (): string => iso(new Date());

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** Format a YYYY-MM-DD (or full ISO timestamp) as "Mon DD" — e.g. "Jul 09". */
export function fmtMonDay(d: string | null | undefined): string {
  const [y, m, day] = (d || '').split('T')[0].split('-');
  const mi = Number(m) - 1;
  if (!y || !day || mi < 0 || mi > 11) return d || '—';
  return `${MONTHS[mi]} ${day.padStart(2, '0')}`;
}

/** Days-ahead cutoff at which we start nudging to receive a shipment. */
export const RECEIVE_WINDOW_DAYS = 3;

/** True when a shipment should be nudged to receive: not yet received AND its ETA is
 *  within `withinDays` days ahead, or already in the past. */
export function isDueToReceive(
  status: string,
  eta: string | null | undefined,
  todayStr: string,
  withinDays = RECEIVE_WINDOW_DAYS,
): boolean {
  if (!eta || isReceived(status)) return false;
  const etaDay = eta.split('T')[0];
  const horizon = iso(new Date(new Date(`${todayStr}T00:00:00Z`).getTime() + withinDays * DAY_MS));
  return etaDay <= horizon;
}

export interface DueShipment {
  shipment_id: string;
  products: string;
  qty: number;
  eta: string;          // YYYY-MM-DD
  status: string;
  overdue: boolean;     // eta < today
  ship_date: string;    // YYYY-MM-DD
  type: string;         // shipment_type (SLOW_SEA / FAST_SEA / AIR …)
  warehouse_id: string; // tracking_number
}

interface RawShipment {
  shipment_id: string; products: string; qty: number; eta: string; status: string;
  ship_date: string; type: string; warehouse_id: string;
}

/** Pure: filter+shape shipments that are due to receive, soonest ETA first. */
export function classifyDueShipments(rows: RawShipment[], todayStr: string, withinDays = RECEIVE_WINDOW_DAYS): DueShipment[] {
  return rows
    .filter(r => r.shipment_id && isDueToReceive(r.status, r.eta, todayStr, withinDays))
    .map(r => ({
      shipment_id: r.shipment_id,
      products: r.products,
      qty: r.qty,
      eta: r.eta.split('T')[0],
      status: r.status,
      overdue: r.eta.split('T')[0] < todayStr,
      ship_date: (r.ship_date || '').split('T')[0],
      type: r.type,
      warehouse_id: r.warehouse_id,
    }))
    .sort((a, b) => a.eta.localeCompare(b.eta));
}

/** Load shipments due to be received (Cube ShipmentsDashboard — one row per shipment). */
export function useShipmentsDueToReceive() {
  const [rows, setRows] = useState<DueShipment[]>([]);
  const [loading, setLoading] = useState(true);
  const load = useCallback(async () => {
    try {
      const data = await cubeLoad({
        dimensions: [
          'ShipmentsDashboard.shipmentId',
          'ShipmentsDashboard.estimatedArrivalDate',
          'ShipmentsDashboard.shipmentStatus',
          'ShipmentsDashboard.productsList',
          'ShipmentsDashboard.totalQuantityShipped',
          'ShipmentsDashboard.shipmentDate',
          'ShipmentsDashboard.shipmentType',
          'ShipmentsDashboard.trackingNumber',
        ],
      });
      const raw: RawShipment[] = (data as Record<string, unknown>[]).map(r => ({
        shipment_id: String(r['ShipmentsDashboard.shipmentId'] ?? ''),
        eta: String(r['ShipmentsDashboard.estimatedArrivalDate'] ?? '').split('T')[0],
        status: String(r['ShipmentsDashboard.shipmentStatus'] ?? ''),
        products: String(r['ShipmentsDashboard.productsList'] ?? ''),
        qty: Number(r['ShipmentsDashboard.totalQuantityShipped'] ?? 0),
        ship_date: String(r['ShipmentsDashboard.shipmentDate'] ?? '').split('T')[0],
        type: String(r['ShipmentsDashboard.shipmentType'] ?? ''),
        warehouse_id: String(r['ShipmentsDashboard.trackingNumber'] ?? ''),
      }));
      setRows(classifyDueShipments(raw, todayISO()));
    } catch (e) {
      console.warn('[ShipmentsToReceive] load failed', e);
    }
    setLoading(false);
  }, []);
  useEffect(() => { void load(); }, [load]);
  return { rows, setRows, loading, reload: load };
}

interface MarkHooks { onOptimistic: () => void; onRevert: () => void; label?: string }

/** One-click "Mark received" with optimistic UI + an undo toast.
 *  Consumers supply onOptimistic (apply received locally) and onRevert (restore). */
export function useMarkReceived() {
  const [toast, setToast] = useState<{ label: string; onUndo: () => void } | null>(null);
  const timer = useRef<number | null>(null);
  const clearTimer = () => { if (timer.current) { window.clearTimeout(timer.current); timer.current = null; } };
  const showToast = useCallback((label: string, onUndo: () => void) => {
    clearTimer();
    setToast({ label, onUndo });
    timer.current = window.setTimeout(() => setToast(null), 6000);
  }, []);
  useEffect(() => clearTimer, []);

  const markReceived = useCallback(async (shipmentId: string, prevStatus: string, hooks: MarkHooks) => {
    hooks.onOptimistic();
    try {
      await dataEntry.updateShipmentHeader(shipmentId, { shipment_status: 'RECEIVED' });
      showToast(hooks.label ?? 'Marked received', async () => {
        clearTimer();
        setToast(null);
        hooks.onRevert();
        try {
          await dataEntry.updateShipmentHeader(shipmentId, { shipment_status: prevStatus || 'PENDING' });
        } catch (e) { console.warn('[MarkReceived] undo write failed', e); }
      });
    } catch (e) {
      hooks.onRevert();
      showToast('Could not mark received — is the data server running?', () => { clearTimer(); setToast(null); });
      console.warn('[MarkReceived] write failed', e);
    }
  }, [showToast]);

  const toastNode = toast ? (
    <div className="fixed bottom-4 right-4 z-[60] flex items-center gap-3 rounded-lg border border-border bg-card px-4 py-2.5 shadow-2xl">
      <PackageCheck size={16} className="text-emerald-400 shrink-0" />
      <span className="text-sm text-text">{toast.label}</span>
      <button onClick={toast.onUndo} className="text-sm font-semibold text-blue-400 hover:text-blue-300">Undo</button>
    </div>
  ) : null;

  return { markReceived, toastNode };
}

/** Shared "Mark received" button. Stops propagation so it works inside clickable rows. */
export function MarkReceivedButton({ onClick, small }: { onClick: () => void; small?: boolean }) {
  return (
    <button
      onClick={(e) => { e.stopPropagation(); onClick(); }}
      className={`inline-flex items-center gap-1 rounded-md border border-emerald-500/30 bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20 transition-colors whitespace-nowrap ${small ? 'px-1.5 py-0.5 text-[11px]' : 'px-2 py-1 text-xs'}`}
      title="Mark this shipment as received (arrived)"
    >
      <CheckCircle2 size={small ? 11 : 13} /> Mark received
    </button>
  );
}
