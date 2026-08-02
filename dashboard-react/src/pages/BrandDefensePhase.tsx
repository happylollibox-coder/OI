import { Fragment, useEffect, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { useDoQueue } from '../hooks/useDoQueue';

// "Brand defense" section — Weekly Run (Ori 2026-08-01: "move Brand Defense campaigns out of
// Portfolio 80/20 / Out of budget into a separate brand defense category").
// The moat is bought at whatever it costs: defense keywords are NEVER parked/probed by ROAS
// (the seat model skips them — action DEFENSE) and defense campaigns are excluded from the
// negate layer (brand terms are the point). The only actionable lever here is BUDGET —
// incl. the graduation rule (7d > 1x and budget < $30 → $31). Bids run on the coacher's
// defense mode (raise toward the $2 hard cap), not on this panel.
// Same grammar as the other sections: item | dark | now $ | last 7d | 8–28d | CPC/target | action | → $ | apply | why.

type Row = {
  campaignId: string; campaignName: string; channel: string; budget: number;
  keywordId: string; text: string; matchType: string; isPt: boolean; bid: number | null; slots: number; seatRank: number;
  spend1d: number; campSpend1d: number; pctDark: number;
  clicks7d: number; roas7d: number | null; clicks828: number; roas828: number | null;
  campClicks7d: number; campRoas7d: number | null; campClicks828: number; campRoas828: number | null;
  targetCpc: number | null; suggestedBudget: number | null; budgetReason: string;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));

export function BrandDefensePhase() {
  const doQueue = useDoQueue();
  const [open, setOpen] = useState(false);
  const [openCamps, setOpenCamps] = useState<Record<string, boolean>>({});
  const [rows, setRows] = useState<Row[] | null>(null);

  useEffect(() => {
    let alive = true;
    cubeLoad({
      dimensions: [
        'KeywordLift.campaignId', 'KeywordLift.campaignName', 'KeywordLift.channel', 'KeywordLift.budget',
        'KeywordLift.keywordId', 'KeywordLift.targetText', 'KeywordLift.matchType', 'KeywordLift.isPt',
        'KeywordLift.slots', 'KeywordLift.seatRank',
        'KeywordLift.currentBid', 'KeywordLift.spend1d', 'KeywordLift.campSpend1d', 'KeywordLift.pctDark',
        'KeywordLift.clicks7d', 'KeywordLift.roas7d', 'KeywordLift.clicks828', 'KeywordLift.roas828',
        'KeywordLift.campClicks7d', 'KeywordLift.campRoas7d', 'KeywordLift.campClicks828', 'KeywordLift.campRoas828',
        'KeywordLift.targetCpc', 'KeywordLift.suggestedBudget', 'KeywordLift.budgetReason',
      ],
      filters: [{ member: 'KeywordLift.isDefense', operator: 'equals', values: ['true'] }],
    }).then(rs => {
      if (!alive) return;
      setRows((rs as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['KeywordLift.campaignId'] ?? ''),
        campaignName: String(r['KeywordLift.campaignName'] ?? ''),
        channel: String(r['KeywordLift.channel'] ?? 'SP'),
        budget: num(r['KeywordLift.budget']) ?? 0,
        keywordId: String(r['KeywordLift.keywordId'] ?? ''),
        text: String(r['KeywordLift.targetText'] ?? ''),
        matchType: String(r['KeywordLift.matchType'] ?? ''),
        slots: num(r['KeywordLift.slots']) ?? 1,
        seatRank: num(r['KeywordLift.seatRank']) ?? 99,
        isPt: r['KeywordLift.isPt'] === true || r['KeywordLift.isPt'] === 'true',
        bid: num(r['KeywordLift.currentBid']),
        spend1d: num(r['KeywordLift.spend1d']) ?? 0,
        campSpend1d: num(r['KeywordLift.campSpend1d']) ?? 0,
        pctDark: num(r['KeywordLift.pctDark']) ?? 0,
        clicks7d: num(r['KeywordLift.clicks7d']) ?? 0,
        roas7d: num(r['KeywordLift.roas7d']),
        clicks828: num(r['KeywordLift.clicks828']) ?? 0,
        roas828: num(r['KeywordLift.roas828']),
        campClicks7d: num(r['KeywordLift.campClicks7d']) ?? 0,
        campRoas7d: num(r['KeywordLift.campRoas7d']),
        campClicks828: num(r['KeywordLift.campClicks828']) ?? 0,
        campRoas828: num(r['KeywordLift.campRoas828']),
        targetCpc: num(r['KeywordLift.targetCpc']),
        suggestedBudget: num(r['KeywordLift.suggestedBudget']),
        budgetReason: String(r['KeywordLift.budgetReason'] ?? ''),
      })));
    }).catch(() => { if (alive) setRows([]); });
    return () => { alive = false; };
  }, []);

  const byCamp = new Map<string, Row[]>();
  for (const r of rows ?? []) { const a = byCamp.get(r.campaignId) ?? []; a.push(r); byCamp.set(r.campaignId, a); }
  for (const a of byCamp.values()) a.sort((x, y) => y.spend1d - x.spend1d);
  const camps = [...byCamp.values()].sort((a, b) => b[0].campSpend1d - a[0].campSpend1d);

  const budgetItem = (id: string) => doQueue.items.find(i => i.action === 'BUDGET_CHANGE' && i.campaign_id === id);
  const budgetSug = (c: Row) => c.suggestedBudget != null && Math.abs(c.suggestedBudget - c.budget) > 0.01;
  const queueBudget = (c: Row) => doQueue.addItem({
    search_term: `__budget__${c.campaignId}`, action: 'BUDGET_CHANGE', campaign: c.campaignName, campaign_id: c.campaignId,
    ad_group_id: '', targeting: '', keyword_id: '', match_type: '', target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
    current_bid: null, recommended_bid: null,
    campaign_type: c.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: '',
    spend: 0, orders: 0, cpc: 0, conv_rate: 0, current_budget: c.budget, recommended_budget: c.suggestedBudget, source: 'COACH',
  });
  const budSugs = camps.map(g => g[0]).filter(budgetSug);
  const allApplied = budSugs.length > 0 && budSugs.every(c => !!budgetItem(c.campaignId));
  const applyAll = () => {
    if (allApplied) budSugs.forEach(c => { const it = budgetItem(c.campaignId); if (it) doQueue.removeItem(it.id); });
    else budSugs.forEach(c => { if (!budgetItem(c.campaignId)) queueBudget(c); });
  };

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <div className="flex items-center gap-1">
        <button className="text-label flex items-center gap-1 flex-1 min-w-0" onClick={() => setOpen(o => !o)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-violet-300">Brand defense</span>
          <span className="text-faint truncate">
            {rows ? `— ${camps.length} campaigns · the moat: never parked by ROAS, never negated · budget is the lever` : '— loading…'}
          </span>
        </button>
        {budSugs.length > 0 && (
          <button onClick={applyAll} title="queue every defense budget suggestion"
            className={`text-label px-2 py-0.5 rounded border shrink-0 ${allApplied ? 'border-emerald-500/40 text-emerald-300' : 'border-violet-500/40 text-violet-300 hover:bg-violet-500/10'}`}>
            {allApplied ? `✓ applied ${budSugs.length}` : `apply all ${budSugs.length}`}
          </button>
        )}
      </div>
      {open && rows && (
        <div className="mt-2 overflow-x-auto">
          <table className="text-label font-mono border-collapse">
            <thead>
              <tr className="text-faint text-right">
                <th className="font-normal text-left px-2 py-0.5">item — campaign ▸ keyword</th>
                <th className="font-normal px-2" title="share of the day out of budget">dark</th>
                <th className="font-normal px-2" title="budget/bid · spent yesterday">now $</th>
                <th className="font-normal px-2" title="last 7 complete days — clicks + net ROAS">last 7d</th>
                <th className="font-normal px-2" title="the 21 days before (day 8 till 28)">8–28d</th>
                <th className="font-normal px-2" title="target CPC (last-year / band)">CPC/target</th>
                <th className="font-normal px-2 text-left">action</th>
                <th className="font-normal px-2">→ $</th>
                <th className="font-normal px-2"></th>
                <th className="font-normal px-2 text-left">why</th>
              </tr>
            </thead>
            <tbody>
              {camps.map(kws => {
                const c = kws[0];
                const expanded = !!openCamps[c.campaignId];
                const sug = budgetSug(c);
                const it = budgetItem(c.campaignId);
                return (
                <Fragment key={c.campaignId}>
                <tr className="text-right border-t border-border/40">
                  <td className="text-left px-2 py-0.5 text-body whitespace-nowrap">
                    <button className="text-faint pr-1" onClick={() => setOpenCamps(o => ({ ...o, [c.campaignId]: !o[c.campaignId] }))}>{expanded ? '▾' : '▸'}</button>
                    {c.campaignName}
                    <span className="text-faint text-label"> {c.channel}</span>
                  </td>
                  <td className={`px-2 ${c.pctDark > 10 ? 'text-amber-400' : 'text-faint'}`}>{c.pctDark.toFixed(0)}%</td>
                  <td className="px-2 text-muted whitespace-nowrap">${c.budget.toFixed(0)} <span className="text-faint">bud</span> <span className="text-faint" title="spent yesterday">· ${c.campSpend1d.toFixed(2)}</span></td>
                  <td className="px-2 text-muted whitespace-nowrap">{c.campClicks7d}c{c.campRoas7d != null ? ` ${c.campRoas7d.toFixed(2)}×` : ' —'}</td>
                  <td className="px-2 text-muted whitespace-nowrap">{c.campClicks828}c{c.campRoas828 != null ? ` ${c.campRoas828.toFixed(2)}×` : ' —'}</td>
                  <td className="px-2" />
                  <td className={`px-2 text-left whitespace-nowrap ${sug ? 'text-emerald-400' : 'text-muted'}`}>{sug ? 'budget' : 'hold'}</td>
                  <td className="px-2">{sug ? `$${c.suggestedBudget!.toFixed(2)}` : '—'}</td>
                  <td className="px-2">
                    {sug && (
                      <button onClick={() => { const x = budgetItem(c.campaignId); if (x) doQueue.removeItem(x.id); else queueBudget(c); }}
                        className={`px-1.5 py-0 rounded border ${it ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                        {it ? '✓' : 'budget'}
                      </button>
                    )}
                  </td>
                  <td className="px-2 text-left text-faint whitespace-nowrap">{c.budgetReason || 'moat funded — hold; bids run on the coacher defense mode'}</td>
                </tr>
                {expanded && kws.map(k => (
                  <tr key={`${c.campaignId}|${k.keywordId || k.text}`} className="text-right border-t border-border/20 bg-surface/40">
                    <td className="text-left pl-8 pr-2 py-0.5 text-muted whitespace-nowrap">{k.text}
                      <span className="text-faint"> ({k.isPt ? 'PT' : (k.matchType || '').toLowerCase()}){k.seatRank <= k.slots ? <span className="text-sky-300"> · seat {k.seatRank}/{k.slots}</span> : <span className="text-faint"> · queue #{k.seatRank - k.slots}</span>}</span></td>
                    <td className="px-2" />
                    <td className="px-2 text-muted whitespace-nowrap">{k.bid != null ? <>${k.bid.toFixed(2)} <span className="text-faint">bid</span></> : '—'}<span className="text-faint" title="spent yesterday"> · ${k.spend1d.toFixed(2)}</span></td>
                    <td className="px-2 text-muted whitespace-nowrap">{k.clicks7d}c{k.roas7d != null ? ` ${k.roas7d.toFixed(2)}×` : ' —'}</td>
                    <td className="px-2 text-muted whitespace-nowrap">{k.clicks828}c{k.roas828 != null ? ` ${k.roas828.toFixed(2)}×` : ' —'}</td>
                    <td className="px-2 text-faint">{k.targetCpc != null ? `$${k.targetCpc.toFixed(2)}` : '—'}</td>
                    <td className="px-2 text-left text-violet-300">defense</td>
                    <td className="px-2">—</td>
                    <td className="px-2" />
                    <td className="px-2 text-left text-faint whitespace-nowrap">the moat is bought at whatever it costs — no ROAS parking, no negates</td>
                  </tr>
                ))}
                </Fragment>
              ); })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
