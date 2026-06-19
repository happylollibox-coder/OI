import React from 'react';
import type { ActionRow } from '../../types';
import { selectPeak } from '../../coachActuals';
import { fM } from '../../utils';

// Allow the runtime-mapped 4w fields (added by ActionsPage's acts mapping) to override the
// canonical ActionRow 4w fields, matching the decision card's behaviour.
type PerfRow = ActionRow & { spend?: number | null; orders?: number | null; clicks?: number | null; net_roas?: number | null };

/**
 * Three-window evidence grid (columns = 1w / 4w / Peak; rows = ROAS · Orders · CPC · Spend · Clicks).
 * Shared by the decision cards and the Budget Actions cards so both read identically.
 */
export function PerformanceGrid({ action: a }: { action: PerfRow }) {
  const peak = selectPeak(a);
  const windows = [
    { label: '1w', title: 'This week (ad-only)', roas: a.ads_net_roas_1w, orders: a.ads_orders_1w, cpc: a.ads_cpc_1w, spend: a.ads_spend_1w ?? null, clicks: a.ads_clicks_1w ?? null },
    { label: '4w', title: 'Last 4 weeks', roas: a.net_roas ?? a.ads_net_roas_4w, orders: a.orders ?? a.ads_orders_4w, cpc: a.ads_cpc_4w, spend: a.spend ?? a.ads_spend_4w, clicks: a.clicks ?? a.ads_clicks_4w },
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
}
