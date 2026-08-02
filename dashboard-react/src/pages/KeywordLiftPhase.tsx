import { Fragment, useEffect, useMemo, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { useDoQueue } from '../hooks/useDoQueue';

// "Portfolio 80/20" phase — working campaigns (budget > low-budget cap), below the Out-of-budget
// section on Weekly Run. Ori 2026-07-30: 80% of spend to winner keywords, 20% exploration; most
// losers parked at $0.25; 1–2 probes at a time lifted to min(1.5× target CPC, $2), verdict at
// 20 clicks. Pure presentation over V_KEYWORD_LIFT via the KeywordLift cube (same column grammar
// as the OOB panel). Spec: architecture/OOB_BUDGET_PHASE.md §"Lever 2B".

type Row = {
  campaignId: string; campaignName: string; channel: string; budget: number; wDays: number;
  spendW: number; loserShare: number | null; activeProbes: number;
  keywordId: string; adGroupId: string; text: string; matchType: string;
  isAuto: boolean; isPt: boolean; bid: number | null;
  clicksW: number; kwSpendW: number; ordersW: number; roasW: number | null;
  clicks7d: number; roas7d: number | null; clicks828: number; roas828: number | null;
  campClicks7d: number; campRoas7d: number | null; campClicks828: number; campRoas828: number | null;
  spend1d: number; campSpend1d: number;
  pctDark: number; slots: number; seatRank: number; isDefense: boolean;
  vSuggestedBudget: number | null; vBudgetReason: string;
  targetCpc: number | null; kwClass: string; probing: boolean;
  probeClicks: number; probeRoas: number | null;
  action: string; suggestedBid: number | null; reason: string;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));
const bool = (v: unknown): boolean => v === true || v === 'true';

const ACT_CLS: Record<string, string> = {
  KEEP: 'text-emerald-400', WINNER_FOUND: 'text-emerald-400', PROBE_START: 'text-emerald-400',
  PROBE_ADJUST: 'text-amber-400', PROBE_WAIT: 'text-muted', KEEP_TAIL: 'text-muted',
  PARK: 'text-red-400', IDLE: 'text-faint',
};
const CLASS_CLS: Record<string, string> = {
  WINNER: 'text-emerald-400', MARGINAL: 'text-amber-400', LOSER: 'text-red-400', IDLE: 'text-faint',
};

export function KeywordLiftPhase({ tier }: { tier: 'LOW' | 'HIGH' }) {
  const doQueue = useDoQueue();
  const [open, setOpen] = useState(false);
  const [openCamps, setOpenCamps] = useState<Record<string, boolean>>({});
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);

  type Neg = { campaignId: string; targetText: string; term: string; kind: string; clicks90: number; marketPurchases90: number; isBig: boolean; spend1d: number };
  type Bud = { budget: number; suggested: number | null; reason: string };
  const [budMap, setBudMap] = useState<Map<string, Bud>>(new Map());
  const [negs, setNegs] = useState<Neg[]>([]);
  const [oobIds, setOobIds] = useState<Set<string>>(new Set());
  useEffect(() => {
    let alive = true;
    // SINGLE-HOME rule (Ori 2026-08-01): capping campaigns (dark > 10%) are owned by the
    // Out-of-budget section — hide them here; they return when darkness clears.
    cubeLoad({ dimensions: ['OobBudget.campaignId', 'OobBudget.pctDark'] }).then(rs => {
      if (!alive) return;
      const ids = new Set((rs as Record<string, unknown>[])
        .filter(r => (Number(r['OobBudget.pctDark']) || 0) > 10)
        .map(r => String(r['OobBudget.campaignId'] ?? '')));
      setOobIds(ids);
    }).catch(e => console.error('[lift] oob ownership fetch failed:', e));
    // campaign budget suggestions — the launch controller's budget ladder lives on (Ori 2026-08-01:
    // "the launch controller cards should be part of Portfolio 80/20"): its BUDGET engine feeds the
    // campaign rows here; its bid logic is superseded by the seat mechanism.
    Promise.all([
      cubeLoad({ dimensions: ['LaunchPhase1.campaignId', 'LaunchPhase1.currentBudget', 'LaunchPhase1.suggestedBudget', 'LaunchPhase1.budgetReason'] }).catch(() => []),
      cubeLoad({ dimensions: ['SbLaunchCampaign.campaignId', 'SbLaunchCampaign.currentBudget', 'SbLaunchCampaign.suggestedBudget', 'SbLaunchCampaign.budgetReason'] }).catch(() => []),
    ]).then(([sp, sb]) => {
      if (!alive) return;
      const m = new Map<string, Bud>();
      for (const [rows2, pre] of [[sp, 'LaunchPhase1'], [sb, 'SbLaunchCampaign']] as const) {
        for (const r of rows2 as Record<string, unknown>[]) {
          const id = String(r[`${pre}.campaignId`] ?? '');
          if (!id || m.has(id)) continue;
          m.set(id, { budget: num(r[`${pre}.currentBudget`]) ?? 0, suggested: num(r[`${pre}.suggestedBudget`]), reason: String(r[`${pre}.budgetReason`] ?? '') });
        }
      }
      setBudMap(m);
    });
    // negates layer (Ori 2026-08-01): the same two-window negate doctrine, for working campaigns —
    // kills the tier-list negate exception so each campaign truly shows once.
    cubeLoad({
      dimensions: ['OobSearchTerm.campaignId', 'OobSearchTerm.targetText', 'OobSearchTerm.searchTerm',
        'OobSearchTerm.kind', 'OobSearchTerm.clicks90d', 'OobSearchTerm.marketPurchases90d', 'OobSearchTerm.isBig', 'OobSearchTerm.spend1d'],
      filters: [{ member: 'OobSearchTerm.engine', operator: 'equals', values: ['LIFT'] },
                { member: 'OobSearchTerm.isNegate', operator: 'equals', values: ['true'] }],
    }).then(ts => {
      if (!alive) return;
      setNegs((ts as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['OobSearchTerm.campaignId'] ?? ''),
        targetText: String(r['OobSearchTerm.targetText'] ?? ''),
        term: String(r['OobSearchTerm.searchTerm'] ?? ''),
        kind: String(r['OobSearchTerm.kind'] ?? ''),
        clicks90: num(r['OobSearchTerm.clicks90d']) ?? 0,
        marketPurchases90: num(r['OobSearchTerm.marketPurchases90d']) ?? 0,
        isBig: r['OobSearchTerm.isBig'] === true || r['OobSearchTerm.isBig'] === 'true',
        spend1d: num(r['OobSearchTerm.spend1d']) ?? 0,
      })));
    }).catch(() => {});
    cubeLoad({
      dimensions: [
        'KeywordLift.campaignId', 'KeywordLift.campaignName', 'KeywordLift.channel', 'KeywordLift.budget', 'KeywordLift.wDays',
        'KeywordLift.campaignSpendW', 'KeywordLift.loserSharePct', 'KeywordLift.activeProbes',
        'KeywordLift.keywordId', 'KeywordLift.adGroupId', 'KeywordLift.targetText', 'KeywordLift.matchType',
        'KeywordLift.isAuto', 'KeywordLift.isPt', 'KeywordLift.currentBid',
        'KeywordLift.clicksW', 'KeywordLift.spendW', 'KeywordLift.ordersW', 'KeywordLift.roasW',
        'KeywordLift.targetCpc', 'KeywordLift.kwClass', 'KeywordLift.probing',
        'KeywordLift.probeClicks', 'KeywordLift.probeRoas',
        'KeywordLift.clicks7d', 'KeywordLift.roas7d', 'KeywordLift.clicks828', 'KeywordLift.roas828',
        'KeywordLift.campClicks7d', 'KeywordLift.campRoas7d', 'KeywordLift.campClicks828', 'KeywordLift.campRoas828',
        'KeywordLift.spend1d', 'KeywordLift.campSpend1d',
        'KeywordLift.pctDark', 'KeywordLift.slots', 'KeywordLift.seatRank',
        'KeywordLift.isDefense', 'KeywordLift.suggestedBudget', 'KeywordLift.budgetReason',
        'KeywordLift.action', 'KeywordLift.suggestedBid', 'KeywordLift.reason',
      ],
    }).then(rs => {
      if (!alive) return;
      setRows((rs as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['KeywordLift.campaignId'] ?? ''),
        campaignName: String(r['KeywordLift.campaignName'] ?? ''),
        channel: String(r['KeywordLift.channel'] ?? 'SP'),
        budget: num(r['KeywordLift.budget']) ?? 0,
        wDays: num(r['KeywordLift.wDays']) ?? 7,
        spendW: num(r['KeywordLift.campaignSpendW']) ?? 0,
        loserShare: num(r['KeywordLift.loserSharePct']),
        activeProbes: num(r['KeywordLift.activeProbes']) ?? 0,
        keywordId: String(r['KeywordLift.keywordId'] ?? ''),
        adGroupId: String(r['KeywordLift.adGroupId'] ?? ''),
        text: String(r['KeywordLift.targetText'] ?? ''),
        matchType: String(r['KeywordLift.matchType'] ?? ''),
        isAuto: bool(r['KeywordLift.isAuto']),
        isPt: bool(r['KeywordLift.isPt']),
        bid: num(r['KeywordLift.currentBid']),
        clicksW: num(r['KeywordLift.clicksW']) ?? 0,
        kwSpendW: num(r['KeywordLift.spendW']) ?? 0,
        ordersW: num(r['KeywordLift.ordersW']) ?? 0,
        roasW: num(r['KeywordLift.roasW']),
        targetCpc: num(r['KeywordLift.targetCpc']),
        kwClass: String(r['KeywordLift.kwClass'] ?? ''),
        probing: bool(r['KeywordLift.probing']),
        probeClicks: num(r['KeywordLift.probeClicks']) ?? 0,
        probeRoas: num(r['KeywordLift.probeRoas']),
        clicks7d: num(r['KeywordLift.clicks7d']) ?? 0,
        roas7d: num(r['KeywordLift.roas7d']),
        clicks828: num(r['KeywordLift.clicks828']) ?? 0,
        roas828: num(r['KeywordLift.roas828']),
        campClicks7d: num(r['KeywordLift.campClicks7d']) ?? 0,
        campRoas7d: num(r['KeywordLift.campRoas7d']),
        campClicks828: num(r['KeywordLift.campClicks828']) ?? 0,
        campRoas828: num(r['KeywordLift.campRoas828']),
        spend1d: num(r['KeywordLift.spend1d']) ?? 0,
        campSpend1d: num(r['KeywordLift.campSpend1d']) ?? 0,
        pctDark: num(r['KeywordLift.pctDark']) ?? 0,
        slots: num(r['KeywordLift.slots']) ?? 1,
        seatRank: num(r['KeywordLift.seatRank']) ?? 99,
        isDefense: r['KeywordLift.isDefense'] === true || r['KeywordLift.isDefense'] === 'true',
        vSuggestedBudget: num(r['KeywordLift.suggestedBudget']),
        vBudgetReason: String(r['KeywordLift.budgetReason'] ?? ''),
        action: String(r['KeywordLift.action'] ?? 'IDLE'),
        suggestedBid: num(r['KeywordLift.suggestedBid']),
        reason: String(r['KeywordLift.reason'] ?? ''),
      })));
    }).catch(() => { if (alive) setFailed(true); });
    return () => { alive = false; };
  }, []);

  const byCamp = useMemo(() => {
    const m = new Map<string, Row[]>();
    for (const r of rows ?? []) { const a = m.get(r.campaignId) ?? []; a.push(r); m.set(r.campaignId, a); }
    for (const a of m.values()) a.sort((x, y) => y.kwSpendW - x.kwSpendW);
    return m;
  }, [rows]);

  const actionable = (r: Row) => r.suggestedBid != null && r.keywordId !== '' && ['PARK', 'PARK_WAIT', 'PROBE_START', 'PROBE_ADJUST'].includes(r.action);
  const bidItem = (r: Row) => doQueue.items.find(i => i.keyword_id === r.keywordId && ['INCREASE_BID', 'REDUCE_BID'].includes(i.action));
  const queueBid = (r: Row) => doQueue.addItem({
    campaign: r.campaignName, campaign_id: r.campaignId, ad_group_id: r.adGroupId, targeting: r.text,
    search_term: r.text, keyword_id: r.keywordId,
    match_type: r.isAuto ? 'Automatic' : (r.matchType || '').toUpperCase(),
    target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
    campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS',
    product: r.isAuto || r.isPt ? 'Product Targeting' : 'Keyword', spend: 0, orders: 0, cpc: 0, conv_rate: 0,
    action: (r.suggestedBid ?? 0) >= (r.bid ?? 0) ? 'INCREASE_BID' : 'REDUCE_BID',
    current_bid: r.bid, recommended_bid: r.suggestedBid, source: 'COACH',
  });

  const lowCap = (rows ?? [])[0]?.wDays === 3 ? 30 : 20;   // peak cap $30, off-season $20
  const camps = [...byCamp.values()].filter(g => {
    const c = g[0];
    if (!c || oobIds.has(c.campaignId) || c.isDefense) return false;
    return tier === 'LOW' ? c.budget <= lowCap : c.budget > lowCap;
  });
  const campIds = new Set(camps.map(g => g[0].campaignId));
  const visNegs = negs.filter(n => campIds.has(n.campaignId));

  const budgetItem = (id: string) => doQueue.items.find(i => i.action === 'BUDGET_CHANGE' && i.campaign_id === id);
  const budgetSug = (c: Row): Bud | null => {
    // SINGLE SOURCE (Ori 2026-08-01 tuning, knob #5): healthy campaigns get ONE budget rule —
    // the view-computed loss cut (W AND today < 0.6x → −20%, seasonal floor). No launch fallback.
    if (c.vSuggestedBudget != null && Math.abs(c.vSuggestedBudget - c.budget) > 0.01)
      return { budget: c.budget, suggested: c.vSuggestedBudget, reason: c.vBudgetReason };
    return null;
  };
  const budSugs = useMemo(() => camps.map(g => g[0]).filter(c => budgetSug(c)), [camps, budMap]);

  const sugs = (rows ?? []).filter(r => actionable(r) && campIds.has(r.campaignId));
  const allApplied = sugs.length > 0 && sugs.every(r => !!bidItem(r));
  const applyAll = () => {
    if (allApplied) {
      sugs.forEach(r => { const it = bidItem(r); if (it) doQueue.removeItem(it.id); });
      visNegs.forEach(n => { const it = negItem(n); if (it) doQueue.removeItem(it.id); });
      budSugs.forEach(c => { const it = budgetItem(c.campaignId); if (it) doQueue.removeItem(it.id); });
    } else {
      sugs.forEach(r => { if (!bidItem(r)) queueBid(r); });
      visNegs.forEach(n => { if (!negItem(n)) queueNeg(n); });
      budSugs.forEach(c => { if (!budgetItem(c.campaignId)) queueBudget(c); });
    }
  };

  const queueBudget = (c: Row) => {
    const b = budMap.get(c.campaignId); if (!b || b.suggested == null) return;
    doQueue.addItem({
      search_term: `__budget__${c.campaignId}`, action: 'BUDGET_CHANGE', campaign: c.campaignName, campaign_id: c.campaignId,
      ad_group_id: '', targeting: '', keyword_id: '', match_type: '', target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
      current_bid: null, recommended_bid: null,
      campaign_type: c.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: '',
      spend: 0, orders: 0, cpc: 0, conv_rate: 0, current_budget: b.budget, recommended_budget: b.suggested, source: 'COACH',
    });
  };
  const negItem = (n: Neg) => doQueue.items.find(i => i.action === 'NEGATE_TERM' && i.campaign_id === n.campaignId && i.search_term === n.term);
  const queueNeg = (n: Neg) => {
    const c = (byCamp.get(n.campaignId) ?? [])[0];
    doQueue.addItem({
      search_term: n.term, action: 'NEGATE_TERM', campaign: c?.campaignName ?? '', campaign_id: n.campaignId, ad_group_id: '',
      targeting: n.term, keyword_id: '', match_type: 'NEGATIVE_EXACT', target_spend_8w: 0, target_orders_8w: 0,
      target_net_roas_8w: 0, current_bid: null, recommended_bid: null,
      campaign_type: c?.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: 'Keyword',
      spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH',
    });
  };
  const nParks = sugs.filter(r => r.action === 'PARK').length;
  const nProbes = sugs.filter(r => r.action.startsWith('PROBE')).length;
  const nFound = (rows ?? []).filter(r => r.action === 'WINNER_FOUND').length;

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <div className="flex items-center gap-1">
        <button className="text-label flex items-center gap-1 flex-1 min-w-0" onClick={() => setOpen(o => !o)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-sky-300">{tier === 'LOW' ? 'Low budget' : 'Portfolio 80/20'}</span>
          <span className="text-faint truncate">
            {failed ? '— unavailable' : rows
              ? `— ${camps.length} working campaigns · ${nParks} parks · ${nProbes} probes · ${nFound} winners found · ${visNegs.length} negates`
              : '— loading…'}
            {' '}· goal: 80% of spend on winners, 1–2 probes hunting the next one
          </span>
        </button>
        {rows && sugs.length > 0 && (
          <button onClick={applyAll}
            title={allApplied ? 'unapply all portfolio suggestions' : 'queue every park and probe bid'}
            className={`text-label px-2 py-0.5 rounded border shrink-0 ${allApplied ? 'border-emerald-500/40 text-emerald-300' : 'border-sky-500/40 text-sky-300 hover:bg-sky-500/10'}`}>
            {allApplied ? `✓ applied ${sugs.length + visNegs.length + budSugs.length}` : `apply all ${sugs.length + visNegs.length + budSugs.length}`}
          </button>
        )}
      </div>
      {open && rows && (
        <div className="mt-2 overflow-x-auto">
          <table className="text-label font-mono border-collapse">
            <thead>
              <tr className="text-faint text-right">
                <th className="font-normal text-left px-2 py-0.5">item — campaign ▸ keyword</th>
                <th className="font-normal px-2" title="share of the day out of budget (campaign) — Portfolio campaigns are ≤10% by ownership; losers % shown in the campaign meta">dark</th>
                <th className="font-normal px-2">now $</th>
                <th className="font-normal px-2" title="last 7 complete days — clicks + net ROAS">last 7d</th>
                <th className="font-normal px-2" title="the 21 days before (day 8 till 28) — same format">8–28d</th>
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
                return (
                <Fragment key={c.campaignId}>
                <tr className="text-right border-t border-border/40">
                  <td className="text-left px-2 py-0.5 text-body whitespace-nowrap">
                    <button className="text-faint pr-1" onClick={() => setOpenCamps(o => ({ ...o, [c.campaignId]: !o[c.campaignId] }))}>{expanded ? '▾' : '▸'}</button>
                    {c.campaignName}
                    <span className="text-faint text-label"> {c.channel} · {c.slots} seats · spent ${c.spendW.toFixed(2)}/{c.wDays}d · {c.activeProbes} probing · losers {c.loserShare != null ? `${c.loserShare.toFixed(0)}%` : '—'}</span>
                  </td>
                  <td className={`px-2 ${c.pctDark > 10 ? 'text-amber-400' : 'text-faint'}`}>{c.pctDark.toFixed(0)}%</td>
                  <td className="px-2 text-muted whitespace-nowrap">${c.budget.toFixed(0)} <span className="text-faint">bud</span> <span className="text-faint" title="spent yesterday">· ${c.campSpend1d.toFixed(2)}</span></td>
                  <td className="px-2 text-muted whitespace-nowrap">{c.campClicks7d}c{c.campRoas7d != null ? ` ${c.campRoas7d.toFixed(2)}×` : ' —'}</td>
                  <td className="px-2 text-muted whitespace-nowrap">{c.campClicks828}c{c.campRoas828 != null ? ` ${c.campRoas828.toFixed(2)}×` : ' —'}</td>
                  <td className="px-2" />
                  <td className={`px-2 text-left whitespace-nowrap ${budgetSug(c) ? 'text-emerald-400' : 'text-muted'}`}>{budgetSug(c) ? 'budget' : 'hold'}</td>
                  <td className="px-2">{budgetSug(c) ? `$${budgetSug(c)!.suggested!.toFixed(2)}` : '—'}</td>
                  <td className="px-2">
                    {budgetSug(c) && (
                      <button onClick={() => { const it = budgetItem(c.campaignId); if (it) doQueue.removeItem(it.id); else queueBudget(c); }}
                        className={`px-1.5 py-0 rounded border ${budgetItem(c.campaignId) ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                        {budgetItem(c.campaignId) ? '✓' : 'budget'}
                      </button>
                    )}
                  </td>
                  <td className="px-2 text-left text-faint whitespace-nowrap">{budMap.get(c.campaignId)?.reason || ((c.loserShare ?? 0) > 20 ? 'losers over the 20% budget — parking the worst' : 'split healthy')}</td>
                </tr>
                {expanded && kws.map(k => {
                  const it = bidItem(k);
                  return (
                  <tr key={`${c.campaignId}|${k.keywordId || k.text}`} className="text-right border-t border-border/20 bg-surface/40">
                    <td className="text-left pl-8 pr-2 py-0.5 text-muted whitespace-nowrap">{k.text}
                      <span className="text-faint"> ({k.isAuto ? 'auto' : k.isPt ? 'PT' : (k.matchType || '').toLowerCase()}) · <span className={CLASS_CLS[k.kwClass] ?? ''}>{k.kwClass.toLowerCase()}</span> · spent ${k.kwSpendW.toFixed(2)}</span></td>
                    <td className="px-2" />
                    <td className="px-2 text-muted whitespace-nowrap">{k.bid != null ? <>${k.bid.toFixed(2)} <span className="text-faint">bid</span></> : '—'}<span className="text-faint" title="spent yesterday"> · ${k.spend1d.toFixed(2)}</span></td>
                    <td className="px-2 text-muted whitespace-nowrap">{k.clicks7d}c{k.roas7d != null ? ` ${k.roas7d.toFixed(2)}×` : ' —'}</td>
                    <td className="px-2 text-muted whitespace-nowrap">{k.clicks828}c{k.roas828 != null ? ` ${k.roas828.toFixed(2)}×` : ' —'}</td>
                    <td className="px-2 text-faint">{k.targetCpc != null ? `$${k.targetCpc.toFixed(2)}` : '—'}</td>
                    <td className={`px-2 text-left whitespace-nowrap ${ACT_CLS[k.action] ?? 'text-muted'}`}>{k.action.toLowerCase().replace(/_/g, ' ')}</td>
                    <td className="px-2">{k.suggestedBid != null ? `$${k.suggestedBid.toFixed(2)}` : '—'}</td>
                    <td className="px-2">
                      {actionable(k) && (
                        <button onClick={() => { const x = bidItem(k); if (x) doQueue.removeItem(x.id); else queueBid(k); }}
                          className={`px-1.5 py-0 rounded border ${it ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                          {it ? '✓' : 'bid'}
                        </button>
                      )}
                    </td>
                    <td className="px-2 text-left text-faint whitespace-nowrap">{k.reason}</td>
                  </tr>
                ); })}
                {expanded && visNegs.filter(n => n.campaignId === c.campaignId).map(n => {
                  const it = negItem(n);
                  return (
                  <tr key={`${c.campaignId}|neg|${n.term}`} className="text-right border-t border-border/20 bg-surface/40">
                    <td className="text-left pl-12 pr-2 py-0.5 text-muted whitespace-nowrap">{n.term}
                      <span className="text-faint"> · term under "{n.targetText}" ({n.kind.toLowerCase()})</span></td>
                    <td className="px-2" />
                    <td className="px-2 text-faint whitespace-nowrap" title="spent yesterday">{n.spend1d > 0 ? `$${n.spend1d.toFixed(2)}` : '—'}</td>
                    <td className="px-2" colSpan={3} />
                    <td className="px-2 text-left text-red-400 whitespace-nowrap">negate</td>
                    <td className="px-2" />
                    <td className="px-2">
                      <button onClick={() => { const x = negItem(n); if (x) doQueue.removeItem(x.id); else queueNeg(n); }}
                        className={`px-1.5 py-0 rounded border ${it ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                        {it ? '✓' : 'neg'}
                      </button>
                    </td>
                    <td className="px-2 text-left text-faint whitespace-nowrap">
                      {n.isBig
                        ? `big word — ${n.marketPurchases90.toLocaleString()} Amazon purchases/90d (SQP), full 90d trial here, no sales`
                        : `small word — ${n.clicks90} clicks · 0 sales here`}
                    </td>
                  </tr>
                ); })}
                </Fragment>
              ); })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
