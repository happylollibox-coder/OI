import { ArrowRightLeft, Plus } from 'lucide-react';
import type { CoachCrossSellRow } from '../../types';
import { fM } from '../../utils';

const CONFIDENCE_CLS: Record<string, string> = {
  HIGH: 'text-emerald-400',
  MEDIUM: 'text-amber-400',
  LOW: 'text-faint',
};

// One cross-sell opportunity as a 10-second-readable card:
//   CLAIM      advertise product B on product A's own listing
//   EVIDENCE   proven 30d co-purchase volume + sales that justify the pairing
// Queue button hands the page a pre-built ADD_CROSS_SELL_TARGET item (page owns
// the side-effect + inQueue, mirroring DecisionCard).
export function CrossSellCard({ row, inQueue, onQueue }: {
  row: CoachCrossSellRow; inQueue: boolean; onQueue: () => void;
}) {
  const advertiseLabel = row.advertise_name || row.advertise_asin;
  const targetLabel = row.target_name || row.target_asin;
  const claim = `Advertise "${advertiseLabel}" on "${targetLabel}"'s listing`;
  const evidence = `${row.cross_orders_30d} shopper${row.cross_orders_30d === 1 ? '' : 's'} bought it after engaging ads for ${targetLabel} (30d) · ${fM(row.cross_sales_30d)}`;
  return (
    <div className="border border-border rounded-xl bg-card p-3 flex flex-col gap-1.5">
      <div className="flex items-center gap-2">
        <ArrowRightLeft size={13} className="text-blue-400" />
        <span className="text-[12px] font-semibold">{claim}</span>
        <button
          onClick={onQueue}
          disabled={inQueue}
          className={`ml-auto shrink-0 text-[10px] px-2 py-1 rounded-md border ${inQueue ? 'border-border text-faint' : 'border-blue-500/40 text-blue-400 hover:bg-blue-500/10'}`}
        >
          {inQueue ? 'Queued ✓' : <span className="flex items-center gap-1"><Plus size={10} /> Queue</span>}
        </button>
      </div>
      <div className="text-[10px] text-subtle">{evidence}</div>
      <div className="text-[10px] tabular-nums font-mono">
        <span className={CONFIDENCE_CLS[row.confidence] ?? 'text-faint'}>{row.confidence} confidence</span>
        <span className="text-faint"> · creates a PRODUCT_DEFENSE product-targeting row</span>
      </div>
    </div>
  );
}
