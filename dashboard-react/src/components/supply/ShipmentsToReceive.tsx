/**
 * ShipmentsToReceive — Supply-page card nudging the user to confirm arrivals.
 *
 * Lists shipments due to be received (ETA within 3 days, or overdue) that no one has
 * marked received yet, each with a one-click "Mark received" button. Renders nothing
 * when there is nothing due, so it stays out of the way. Self-fetches from Cube and
 * writes through Flask via useMarkReceived.
 */
import { PackageCheck } from 'lucide-react';
import {
  useShipmentsDueToReceive, useMarkReceived, MarkReceivedButton, fmtMonDay, type DueShipment,
} from './shipmentReceive';

const TH = 'text-left px-2 py-1 text-[10px] font-semibold text-faint uppercase tracking-wider whitespace-nowrap';
const TD = 'px-2 py-1 text-xs whitespace-nowrap';

export function ShipmentsToReceive({ onNav }: { onNav?: (p: string) => void }) {
  const { rows, setRows, loading } = useShipmentsDueToReceive();
  const { markReceived, toastNode } = useMarkReceived();

  if (loading || rows.length === 0) return null;

  const onMark = (r: DueShipment) => {
    markReceived(r.shipment_id, r.status, {
      onOptimistic: () => setRows(prev => prev.filter(x => x.shipment_id !== r.shipment_id)),
      onRevert: () => setRows(prev => prev.some(x => x.shipment_id === r.shipment_id)
        ? prev
        : [...prev, r].sort((a, b) => a.eta.localeCompare(b.eta))),
      label: `Received: ${r.products || r.shipment_id}`,
    });
  };

  const overdue = rows.filter(r => r.overdue).length;

  return (
    <div className="rounded-xl border border-border bg-amber-500/[.05] px-4 py-3">
      <div className="flex items-center gap-2 mb-1.5">
        <PackageCheck size={14} className="text-amber-400 shrink-0" />
        <span className="text-[13px] font-semibold text-text">
          Shipments to receive
          <span className="ml-1.5 text-[11px] font-normal text-muted">
            {rows.length} due{overdue > 0 ? ` · ${overdue} overdue` : ''}
          </span>
        </span>
        {onNav && (
          <button
            onClick={() => onNav('supply')}
            className="ml-auto text-[11px] text-blue-400 hover:text-blue-300 hover:underline"
          >
            Open Supply →
          </button>
        )}
      </div>
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr className="border-b border-border/60">
              <th className={TH}></th>
              <th className={TH}>Ship Date</th>
              <th className={TH}>Products</th>
              <th className={TH}>Type</th>
              <th className={TH}>Warehouse ID</th>
              <th className={`${TH} text-right`}>Qty</th>
              <th className={TH}>ETA</th>
              <th className={TH}></th>
            </tr>
          </thead>
          <tbody>
            {rows.map(r => (
              <tr key={r.shipment_id} className="border-b border-border/30 last:border-0">
                <td className={TD}>
                  <span
                    className={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${
                      r.overdue ? 'bg-red-500/15 text-red-400' : 'bg-amber-500/15 text-amber-400'
                    }`}
                  >
                    {r.overdue ? 'Overdue' : 'Soon'}
                  </span>
                </td>
                <td className={`${TD} text-muted`}>{fmtMonDay(r.ship_date)}</td>
                <td className={`${TD} text-subtle font-medium max-w-[220px] truncate`} title={r.products}>
                  {r.products || r.shipment_id}
                </td>
                <td className={`${TD} text-muted`}>{r.type || '—'}</td>
                <td className={`${TD} text-muted font-mono`} title={r.warehouse_id}>{r.warehouse_id || '—'}</td>
                <td className={`${TD} text-right text-subtle font-mono`}>{r.qty.toLocaleString()}</td>
                <td className={`${TD} text-faint`}>{fmtMonDay(r.eta)}</td>
                <td className={`${TD} text-right`}>
                  <MarkReceivedButton small onClick={() => onMark(r)} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {toastNode}
    </div>
  );
}
