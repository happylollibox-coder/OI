import { ArrowDownRight, ArrowUpRight, Ban, Plus } from 'lucide-react';
import type { ActionRow } from '../../types';
import { fM } from '../../utils';
import { CUT_ACTIONS, REDUCE_ACTIONS, selectPeak, type GateVerdict } from '../../coachActuals';

// ActionRow uses ads_spend_4w / ads_clicks_4w / ads_orders_4w / ads_net_roas_4w as field names.
// ActionsPage re-maps them to spend/clicks/orders/net_roas when building the `acts` array.
// DecisionCard accepts either shape via this minimal intersection so tsc strict passes.
type ActionRowRuntime = ActionRow & {
  spend?: number;
  clicks?: number;
  orders?: number;
  net_roas?: number;
};

// One clear-case action as a 10-second-readable card:
//   CLAIM      what to do, for which family
//   EVIDENCE   the 3 facts that justify it (4w window — real past numbers, no forecasts)
//   CHANGE     exactly what will change in Amazon (campaign + object)
// Queue button adds to the Do queue exactly like the row UI does (handler passed in).
export function DecisionCard({ action: a, family, why, opp, inQueue, onQueue }: {
  action: ActionRowRuntime; family: string; why: GateVerdict; opp: { kind: 'save' | 'earn'; dollars: number }; inQueue: boolean; onQueue: () => void;
}) {
  const isCut = CUT_ACTIONS.has(a.action);
  const isReduce = REDUCE_ACTIONS.has(a.action);
  const icon = isCut ? <Ban size={13} className="text-red-400" />
    : isReduce ? <ArrowDownRight size={13} className="text-amber-400" />
    : <ArrowUpRight size={13} className="text-emerald-400" />;
  const claim = isCut
    ? `Stop "${a.search_term || a.targeting}" for ${family}`
    : isReduce
    ? `Lower the bid on "${a.targeting || a.search_term}" for ${family}`
    : `Bid up "${a.targeting || a.search_term}" for ${family}`;
  const bid = a.recommended_bid;
  const amazonChange = isCut
    ? `Add negative exact in: ${a.campaign_name}`
    : `${isReduce ? 'Reduce' : 'Raise'} keyword bid in: ${a.campaign_name}${bid != null ? ` → $${Number(bid).toFixed(2)}` : ''}`;

  // Prefer runtime-mapped fields (spend/clicks/orders/net_roas from ActionsPage's acts mapping),
  // fall back to the canonical 4w fields on ActionRow.
  const spend = a.spend ?? a.ads_spend_4w;
  const clicks = a.clicks ?? a.ads_clicks_4w;
  const orders = a.orders ?? a.ads_orders_4w;
  const netRoas = a.net_roas ?? a.ads_net_roas_4w;

  return (
    <div className="border border-border rounded-xl bg-card p-3 flex flex-col gap-1.5">
      <div className="flex items-center gap-2">
        {icon}
        <span className="text-[12px] font-semibold">{claim}</span>
        <button
          onClick={onQueue}
          disabled={inQueue}
          className={`ml-auto shrink-0 text-[10px] px-2 py-1 rounded-md border ${inQueue ? 'border-border text-faint' : 'border-blue-500/40 text-blue-400 hover:bg-blue-500/10'}`}
        >
          {inQueue ? 'Queued ✓' : <span className="flex items-center gap-1"><Plus size={10} /> Queue</span>}
        </button>
      </div>
      <div className="text-[10px] font-mono text-muted flex gap-3 tabular-nums flex-wrap">
        <span title="This week (1w, ad-only)">1w: {a.ads_net_roas_1w != null ? `ROAS ${Number(a.ads_net_roas_1w).toFixed(2)}× (${a.ads_orders_1w ?? 0} ord)` : '—'}</span>
        <span title="Last 4 weeks">4w: {fM(spend ?? 0)} · {clicks ?? 0} clicks · {orders ?? 0} ord{(orders ?? 0) > 0 && netRoas != null ? ` · ROAS ${Number(netRoas).toFixed(2)}×` : ''}</span>
        <span title="Best of last-year peak and Q4 peak">Peak: {(() => { const p = selectPeak(a); return p ? `ROAS ${p.roas.toFixed(2)}× (${p.orders != null ? p.orders : '—'} ord)` : '—'; })()}</span>
      </div>
      <div className="text-[10px] text-subtle">{why.reason}.</div>
      <div className="text-[10px] tabular-nums font-mono">
        {opp.kind === 'save'
          ? <span className="text-emerald-400">→ save ~{fM(opp.dollars)}/wk</span>
          : <span className="text-emerald-400">→ earning {fM(opp.dollars)}/wk — scale to beat</span>}
        <span className="text-faint"> · checked vs real results 1 week after upload</span>
      </div>
      <div className="text-[9px] text-faint">{amazonChange}</div>
    </div>
  );
}
