import React from 'react';
import { ArrowDownRight, ArrowUpRight, Ban, Plus } from 'lucide-react';
import type { ActionRow } from '../../types';
import { fM } from '../../utils';
import { CUT_ACTIONS, REDUCE_ACTIONS, selectPeak, termGrain, traceSummary, type GateVerdict } from '../../coachActuals';
import type { LastChange } from '../../hooks/useLastChange';
import { fitBadgeClass, fitBadgeLabel } from './fitBadge';

// "Jun 12" from a YYYY-MM-DD (or ISO) string, parsed as a local date to avoid TZ drift.
const fmtShortDate = (ds: string) => {
  const [y, m, d] = ds.slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return ds;
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
};
const daysAgo = (ds: string) => {
  const [y, m, d] = ds.slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return null;
  const then = new Date(y, m - 1, d);
  const today = new Date(); today.setHours(0, 0, 0, 0);
  return Math.round((today.getTime() - then.getTime()) / 86400000);
};

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
export function DecisionCard({ action: a, family, why, opp, inQueue, onQueue, lastChange, researchRank, sourceKeyword, sourceKeywordMatchType }: {
  action: ActionRowRuntime; family: string; why: GateVerdict; opp: { kind: 'save' | 'earn'; dollars: number }; inQueue: boolean; onQueue: () => void; lastChange?: LastChange | null;
  researchRank?: number | null; sourceKeyword?: string | null; sourceKeywordMatchType?: string | null;
}) {
  const isCut = CUT_ACTIONS.has(a.action);
  const isReduce = REDUCE_ACTIONS.has(a.action);
  const icon = isCut ? <Ban size={13} className="text-red-400" />
    : isReduce ? <ArrowDownRight size={13} className="text-amber-400" />
    : <ArrowUpRight size={13} className="text-emerald-400" />;
  // PROMOTE_TO_EXACT is NOT a bid edit — the bulksheet creates a whole new exact campaign
  // (campaign + ad group + ad + keyword). The card must never understate that (trust surface;
  // a real upload on 2026-06-12 created campaigns the owner didn't expect).
  const isExtract = a.action === 'PROMOTE_TO_EXACT';
  // Grain label: cut/negate acts on the shopper SEARCH TERM; bid actions act on the KEYWORD/target.
  // Always state which, so the action's grain is never ambiguous.
  const term = isCut ? (a.search_term || a.targeting) : (a.targeting || a.search_term);
  const termKind = termGrain(a);
  const claim = isCut
    ? `Stop ${termKind} "${term}" for ${family}`
    : isReduce
    ? `Lower the bid on ${termKind} "${term}" for ${family}`
    : isExtract
    ? `Extract ${termKind} "${term}" into its own EXACT campaign for ${family}`
    : `Bid up ${termKind} "${term}" for ${family}`;
  const bid = a.recommended_bid;
  const amazonChange = isCut
    ? `Add negative exact in: ${a.campaign_name}`
    : isExtract
    ? `Create NEW exact campaign ($20/d budget): campaign + ad group + ad + keyword${bid != null ? ` @ $${Number(bid).toFixed(2)}` : ''}`
    : `${isReduce ? 'Reduce' : 'Raise'} keyword bid in: ${a.campaign_name}${bid != null ? ` → $${Number(bid).toFixed(2)}` : ''}`;

  // Prefer runtime-mapped fields (spend/clicks/orders/net_roas from ActionsPage's acts mapping),
  // fall back to the canonical 4w fields on ActionRow.
  const spend = a.spend ?? a.ads_spend_4w;
  const clicks = a.clicks ?? a.ads_clicks_4w;
  const orders = a.orders ?? a.ads_orders_4w;
  const netRoas = a.net_roas ?? a.ads_net_roas_4w;

  // Peak winner: cut card on a term that performed in peak. Blitz's anticipatory gate
  // re-bids proven peak terms in boost, so cutting it now drops a term Blitz would revive.
  const peak = selectPeak(a);
  const isPeakWinner = isCut && peak != null && ((peak.orders ?? 0) >= 3 || peak.roas >= 1.3);

  return (
    <div className="border border-border rounded-xl bg-card p-3 flex flex-col gap-1.5">
      <div className="flex items-center gap-2">
        {icon}
        <span className="text-[12px] font-semibold">{claim}</span>
        {researchRank != null && (
          <span className={`shrink-0 text-[10px] font-mono ${fitBadgeClass(researchRank)}`} title="Research fit+purchase rank (0–100)">{fitBadgeLabel(researchRank)}</span>
        )}
        <button
          onClick={onQueue}
          disabled={inQueue}
          className={`ml-auto shrink-0 text-[10px] px-2 py-1 rounded-md border ${inQueue ? 'border-border text-faint' : 'border-blue-500/40 text-blue-400 hover:bg-blue-500/10'}`}
        >
          {inQueue ? 'Queued ✓' : <span className="flex items-center gap-1"><Plus size={10} /> Queue</span>}
        </button>
      </div>
      {(() => {
        // Three-window evidence as a compact comparison grid (windows = columns).
        const windows = [
          { label: '1w', title: 'This week (ad-only)', roas: a.ads_net_roas_1w, orders: a.ads_orders_1w, cpc: a.ads_cpc_1w, spend: a.ads_spend_1w ?? null, clicks: a.ads_clicks_1w ?? null },
          { label: '4w', title: 'Last 4 weeks', roas: netRoas ?? null, orders: orders ?? null, cpc: a.ads_cpc_4w, spend: spend ?? null, clicks: clicks ?? null },
          { label: 'Peak', title: 'Best of last-year peak and Q4 peak', roas: peak?.roas ?? null, orders: peak?.orders ?? null, cpc: peak?.cpc ?? null, spend: peak?.spend ?? null, clicks: peak?.clicks ?? null },
        ];
        const roasCls = (v: number | null | undefined) =>
          v == null ? 'text-faint' : v >= 1.1 ? 'text-emerald-400' : v < 0.9 ? 'text-red-400' : 'text-[var(--color-text)]';
        const cell = (v: number | null | undefined, f: (n: number) => string) => (v == null ? '—' : f(v));
        const rows: { name: string; render: (w: typeof windows[number]) => React.ReactNode }[] = [
          { name: 'ROAS', render: w => <span className={roasCls(w.roas)}>{cell(w.roas, n => `${n.toFixed(2)}×`)}</span> },
          { name: 'Orders', render: w => cell(w.orders, n => String(n)) },
          { name: 'CPC', render: w => cell(w.cpc, n => `$${n.toFixed(2)}`) },
          { name: 'Spend', render: w => cell(w.spend, n => fM(n)) },
          { name: 'Clicks', render: w => cell(w.clicks, n => n.toLocaleString()) },
        ];
        return (
          <div className="grid grid-cols-[auto_1fr_1fr_1fr] gap-x-4 gap-y-px text-[10px] tabular-nums font-mono text-muted items-baseline w-fit min-w-[60%]">
            <span />
            {windows.map(w => <span key={`h-${w.label}`} title={w.title} className="font-sans font-semibold text-[9px] uppercase tracking-wider text-subtle">{w.label}</span>)}
            {rows.map(rw => (
              <React.Fragment key={rw.name}>
                <span className="font-sans text-faint">{rw.name}</span>
                {windows.map(w => <span key={`${rw.name}-${w.label}`}>{rw.render(w)}</span>)}
              </React.Fragment>
            ))}
          </div>
        );
      })()}
      {(() => {
        // Surface the ENGINE's own rationale (whole-keyword grain, mode-aware ROAS) so the card's
        // stated reason matches what the engine actually decided on — not a displayed cell that may
        // be a per-action fragment (1w) or the raw (non-off-season) ROAS. Falls back to the dashboard
        // clear-case verdict when the trace carries no summary.
        const engine = traceSummary(a.decision_trace);
        return <div className="text-[10px] text-subtle">{engine ?? `${why.reason}.`}</div>;
      })()}
      {sourceKeyword && (
        <div className="text-[9px] text-faint">via {(sourceKeywordMatchType || 'TARGET').toUpperCase()}: {sourceKeyword}</div>
      )}
      {isPeakWinner && peak && (
        <div className="text-[10px] text-amber-400/90">
          ⚠ Peak winner: {peak.orders ?? 0} orders @ {peak.roas.toFixed(2)}× last peak — Blitz re-bids proven peak terms in boost; cutting now drops it for next peak.
        </div>
      )}
      <div className="text-[10px] tabular-nums font-mono">
        {opp.kind === 'save'
          ? <span className="text-emerald-400">→ save ~{fM(opp.dollars)}/wk</span>
          : <span className="text-emerald-400">→ earning {fM(opp.dollars)}/wk — scale to beat</span>}
        <span className="text-faint"> · checked vs real results 1 week after upload</span>
      </div>
      <div className="text-[9px] text-faint">{amazonChange}</div>
      {(() => {
        // Recency of this keyword-in-campaign: last bid/action WE uploaded, else when it was created.
        if (lastChange?.date) {
          const n = daysAgo(lastChange.date);
          const rel = n == null ? '' : n <= 0 ? 'today' : n === 1 ? 'yesterday' : `${n}d ago`;
          return (
            <div className="text-[9px] text-faint">
              Last changed {rel && `${rel} `}({fmtShortDate(lastChange.date)}){lastChange.action ? ` · ${lastChange.action}` : ''}
            </div>
          );
        }
        if (a.lt_first_seen) {
          return <div className="text-[9px] text-faint">Created {fmtShortDate(a.lt_first_seen)} · no prior change</div>;
        }
        return null;
      })()}
    </div>
  );
}
