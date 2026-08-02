import { Fragment, useEffect, useMemo, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { useDoQueue } from '../hooks/useDoQueue';

// "Out of budget" technical phase — sits directly below the Coach-logic flowchart on Weekly Run.
// Goal (Ori 2026-07-30): campaigns should never be out of budget, but use almost all their budget.
// v2: campaign → keywords → search terms hierarchy + one apply-all (budgets, bids, negations → DO queue).
// Pure presentation: every number, action and reason comes from V_OOB_BUDGET_PHASE / V_OOB_KEYWORD /
// V_OOB_SEARCH_TERM via the OobBudget / OobKeyword / OobSearchTerm cubes.
// Spec: architecture/OOB_BUDGET_PHASE.md.

type Row = {
  id: string; name: string; channel: string; engine: string; isDefense: boolean; isLowTier: boolean; budget: number; spend: number;
  util: number | null; dark: number; roas1: number | null; roasPrev2: number | null;
  daysSince: number | null; action: string; suggested: number | null; reason: string;
};
type Kw = {
  campaignId: string; keywordId: string; adGroupId: string; text: string; matchType: string;
  isAuto: boolean; isPt: boolean; bid: number | null; clicks1: number; spend1: number; cpc1: number | null;
  units1: number; roas1: number | null; clicks2: number; roas2: number | null;
  targetCpc: number | null; targetCpcSrc: string;
  suggestedBid: number | null; action: string; reason: string;
};
type Term = {
  campaignId: string; targetText: string; term: string; kind: string;
  clicks: number; orders: number; spend: number; spend1d: number; netRoas: number | null;
  clicks90d: number; spend90d: number; termClicks90d: number; marketPurchases90d: number; isBig: boolean; isWinner: boolean; isNegate: boolean;
};

const num = (v: unknown): number | null => (v == null || v === '' ? null : Number(v));
const bool = (v: unknown): boolean => v === true || v === 'true';

const ACTION_CLS: Record<string, string> = {
  RAISE_STRONG: 'text-emerald-400',
  RAISE_WEAK: 'text-emerald-400',
  CUT: 'text-red-400',
  HOLD: 'text-muted',
  WATCH: 'text-faint',
};
const KW_CLS: Record<string, string> = {
  PROBE: 'text-emerald-400', SLOW: 'text-amber-400', DARK_BRAKE: 'text-amber-400', PARK: 'text-red-400', TRIM_BID: 'text-amber-400', FIT_CPC: 'text-amber-400',
  PARK_WAIT: 'text-sky-300', ACTIVATE: 'text-emerald-400', DEFER_OOB: 'text-faint',
  RAISE_STRONG: 'text-emerald-400', RAISE_WEAK: 'text-emerald-400',
  HOLD: 'text-muted', NO_BID: 'text-faint',
};

export function OobBudgetPhase({ tier }: { tier: 'LOW' | 'HIGH' }) {
  const doQueue = useDoQueue();
  const [open, setOpen] = useState(false);
  const [openCamps, setOpenCamps] = useState<Record<string, boolean>>({});
  const [rows, setRows] = useState<Row[] | null>(null);
  const [kws, setKws] = useState<Kw[]>([]);
  const [terms, setTerms] = useState<Term[]>([]);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let alive = true;
    Promise.all([
      cubeLoad({
        dimensions: [
          'OobBudget.campaignId', 'OobBudget.campaignName', 'OobBudget.channel', 'OobBudget.engine', 'OobBudget.isDefense', 'OobBudget.isLowTier',
          'OobBudget.currentBudget', 'OobBudget.spend1d', 'OobBudget.utilization',
          'OobBudget.pctDark', 'OobBudget.roas1d', 'OobBudget.roasPrev2',
          'OobBudget.daysSinceBudgetChange', 'OobBudget.action',
          'OobBudget.suggestedBudget', 'OobBudget.reason',
        ],
      }),
      cubeLoad({
        dimensions: [
          'OobKeyword.campaignId', 'OobKeyword.keywordId', 'OobKeyword.adGroupId', 'OobKeyword.targetText',
          'OobKeyword.matchType', 'OobKeyword.isAuto', 'OobKeyword.isPt', 'OobKeyword.currentBid',
          'OobKeyword.clicks1d', 'OobKeyword.spend1d', 'OobKeyword.cpc1d', 'OobKeyword.units1d', 'OobKeyword.roas1d',
          'OobKeyword.clicksPrev2', 'OobKeyword.roasPrev2',
          'OobKeyword.targetCpc', 'OobKeyword.targetCpcSource',
          'OobKeyword.suggestedBid', 'OobKeyword.bidAction', 'OobKeyword.bidReason',
        ],
      }),
      cubeLoad({
        dimensions: [
          'OobSearchTerm.campaignId', 'OobSearchTerm.targetText', 'OobSearchTerm.searchTerm',
          'OobSearchTerm.kind', 'OobSearchTerm.clicks', 'OobSearchTerm.orders', 'OobSearchTerm.spend', 'OobSearchTerm.spend1d',
          'OobSearchTerm.netRoas', 'OobSearchTerm.clicks90d', 'OobSearchTerm.spend90d',
          'OobSearchTerm.termClicks90d', 'OobSearchTerm.marketPurchases90d', 'OobSearchTerm.isBig', 'OobSearchTerm.isWinner', 'OobSearchTerm.isNegate',
        ],
        filters: [{ member: 'OobSearchTerm.clicks90d', operator: 'gte', values: ['3'] },
                  { member: 'OobSearchTerm.engine', operator: 'equals', values: ['OOB'] }],
      }),
    ]).then(([bs, ks, ts]) => {
      if (!alive) return;
      const mapped = (bs as Record<string, unknown>[]).map(r => ({
        id: String(r['OobBudget.campaignId'] ?? ''),
        name: String(r['OobBudget.campaignName'] ?? ''),
        channel: String(r['OobBudget.channel'] ?? ''),
        engine: String(r['OobBudget.engine'] ?? ''),
        isDefense: r['OobBudget.isDefense'] === true || r['OobBudget.isDefense'] === 'true',
        isLowTier: r['OobBudget.isLowTier'] === true || r['OobBudget.isLowTier'] === 'true',
        budget: num(r['OobBudget.currentBudget']) ?? 0,
        spend: num(r['OobBudget.spend1d']) ?? 0,
        util: num(r['OobBudget.utilization']),
        dark: num(r['OobBudget.pctDark']) ?? 0,
        roas1: num(r['OobBudget.roas1d']),
        roasPrev2: num(r['OobBudget.roasPrev2']),
        daysSince: num(r['OobBudget.daysSinceBudgetChange']),
        action: String(r['OobBudget.action'] ?? ''),
        suggested: num(r['OobBudget.suggestedBudget']),
        reason: String(r['OobBudget.reason'] ?? ''),
      }));
      mapped.sort((a, b) => b.dark - a.dark);
      // SINGLE-HOME rule (Ori 2026-08-01: "each campaign should be shown once"): this section OWNS
      // campaigns that are capping (dark > 10%) — the seat model manages their bids here. Campaigns
      // at dark ≤ 10% (WATCH) stay in their engine home (Portfolio 80/20 / launch cards) instead of
      // appearing twice.
      // defense campaigns live in their own section (Ori 2026-08-01)
      setRows(mapped.filter(r => r.dark > 10 && !r.isDefense && (tier === 'LOW' ? r.isLowTier : !r.isLowTier)));
      setKws((ks as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['OobKeyword.campaignId'] ?? ''),
        keywordId: String(r['OobKeyword.keywordId'] ?? ''),
        adGroupId: String(r['OobKeyword.adGroupId'] ?? ''),
        text: String(r['OobKeyword.targetText'] ?? ''),
        matchType: String(r['OobKeyword.matchType'] ?? ''),
        isAuto: bool(r['OobKeyword.isAuto']),
        isPt: bool(r['OobKeyword.isPt']),
        bid: num(r['OobKeyword.currentBid']),
        clicks1: num(r['OobKeyword.clicks1d']) ?? 0,
        spend1: num(r['OobKeyword.spend1d']) ?? 0,
        cpc1: num(r['OobKeyword.cpc1d']),
        units1: num(r['OobKeyword.units1d']) ?? 0,
        roas1: num(r['OobKeyword.roas1d']),
        clicks2: num(r['OobKeyword.clicksPrev2']) ?? 0,
        roas2: num(r['OobKeyword.roasPrev2']),
        targetCpc: num(r['OobKeyword.targetCpc']),
        targetCpcSrc: String(r['OobKeyword.targetCpcSource'] ?? ''),
        suggestedBid: num(r['OobKeyword.suggestedBid']),
        action: String(r['OobKeyword.bidAction'] ?? 'HOLD'),
        reason: String(r['OobKeyword.bidReason'] ?? ''),
      })));
      setTerms((ts as Record<string, unknown>[]).map(r => ({
        campaignId: String(r['OobSearchTerm.campaignId'] ?? ''),
        targetText: String(r['OobSearchTerm.targetText'] ?? ''),
        term: String(r['OobSearchTerm.searchTerm'] ?? ''),
        kind: String(r['OobSearchTerm.kind'] ?? ''),
        clicks: num(r['OobSearchTerm.clicks']) ?? 0,
        orders: num(r['OobSearchTerm.orders']) ?? 0,
        spend: num(r['OobSearchTerm.spend']) ?? 0,
        spend1d: num(r['OobSearchTerm.spend1d']) ?? 0,
        netRoas: num(r['OobSearchTerm.netRoas']),
        clicks90d: num(r['OobSearchTerm.clicks90d']) ?? 0,
        spend90d: num(r['OobSearchTerm.spend90d']) ?? 0,
        termClicks90d: num(r['OobSearchTerm.termClicks90d']) ?? 0,
        marketPurchases90d: num(r['OobSearchTerm.marketPurchases90d']) ?? 0,
        isBig: bool(r['OobSearchTerm.isBig']),
        isWinner: bool(r['OobSearchTerm.isWinner']),
        isNegate: bool(r['OobSearchTerm.isNegate']),
      })));
    }).catch(() => { if (alive) setFailed(true); });
    return () => { alive = false; };
  }, []);

  const kwByCamp = useMemo(() => {
    const m = new Map<string, Kw[]>();
    for (const k of kws) { const a = m.get(k.campaignId) ?? []; a.push(k); m.set(k.campaignId, a); }
    for (const a of m.values()) a.sort((x, y) => y.spend1 - x.spend1);
    return m;
  }, [kws]);
  const termsByKw = useMemo(() => {
    const m = new Map<string, Term[]>();
    for (const t of terms) { const key = `${t.campaignId}|${t.targetText}`; const a = m.get(key) ?? []; a.push(t); m.set(key, a); }
    for (const a of m.values()) a.sort((x, y) => y.clicks - x.clicks);
    return m;
  }, [terms]);

  // ── DO-queue wiring (same item shapes as the launch cards) ──
  const budgetSug = (r: Row) => r.suggested != null && Math.abs(r.suggested - r.budget) > 0.01;
  const bidSug = (k: Kw) => k.suggestedBid != null && k.keywordId !== '' && !['HOLD', 'NO_BID'].includes(k.action);
  const campNegs = (id: string) => (kwByCamp.get(id) ?? []).flatMap(k =>
    (termsByKw.get(`${id}|${k.text}`) ?? []).filter(t => t.isNegate));
  const budgetItem = (r: Row) => doQueue.items.find(i => i.action === 'BUDGET_CHANGE' && i.campaign_id === r.id);
  const bidItem = (k: Kw) => doQueue.items.find(i => i.keyword_id === k.keywordId && ['INCREASE_BID', 'REDUCE_BID'].includes(i.action));
  const negItem = (t: Term) => doQueue.items.find(i => i.action === 'NEGATE_TERM' && i.campaign_id === t.campaignId && i.search_term === t.term);
  const queueBudget = (r: Row) => doQueue.addItem({
    search_term: `__budget__${r.id}`, action: 'BUDGET_CHANGE', campaign: r.name, campaign_id: r.id,
    ad_group_id: '', targeting: '', keyword_id: '', match_type: '', target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
    current_bid: null, recommended_bid: null,
    campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: '',
    spend: 0, orders: 0, cpc: 0, conv_rate: 0, current_budget: r.budget, recommended_budget: r.suggested, source: 'COACH',
  });
  const queueKwBid = (r: Row, k: Kw) => doQueue.addItem({
    campaign: r.name, campaign_id: r.id, ad_group_id: k.adGroupId, targeting: k.text, search_term: k.text,
    keyword_id: k.keywordId, match_type: k.isAuto ? 'Automatic' : (k.matchType || '').toUpperCase(),
    target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: 0,
    campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS',
    product: k.isAuto || k.isPt ? 'Product Targeting' : 'Keyword', spend: 0, orders: 0, cpc: 0, conv_rate: 0,
    action: (k.suggestedBid ?? 0) >= (k.bid ?? 0) ? 'INCREASE_BID' : 'REDUCE_BID',
    current_bid: k.bid, recommended_bid: k.suggestedBid, source: 'COACH',
  });
  const queueNeg = (r: Row, t: Term) => doQueue.addItem({
    search_term: t.term, action: 'NEGATE_TERM', campaign: r.name, campaign_id: r.id, ad_group_id: '',
    targeting: t.term, keyword_id: '', match_type: 'NEGATIVE_EXACT', target_spend_8w: 0, target_orders_8w: 0,
    target_net_roas_8w: 0, current_bid: null, recommended_bid: null,
    campaign_type: r.channel === 'SB' ? 'SPONSORED_BRANDS' : 'SPONSORED_PRODUCTS', product: 'Keyword',
    spend: 0, orders: 0, cpc: 0, conv_rate: 0, source: 'COACH',
  });

  const allSuggestions = useMemo(() => {
    if (!rows) return { budgets: [] as Row[], bids: [] as { r: Row; k: Kw }[], negs: [] as { r: Row; t: Term }[] };
    const budgets = rows.filter(budgetSug);
    const bids = rows.flatMap(r => (kwByCamp.get(r.id) ?? []).filter(bidSug).map(k => ({ r, k })));
    const negs = rows.flatMap(r => campNegs(r.id).map(t => ({ r, t })));
    return { budgets, bids, negs };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rows, kwByCamp, termsByKw]);
  const nSug = allSuggestions.budgets.length + allSuggestions.bids.length + allSuggestions.negs.length;
  const allApplied = nSug > 0
    && allSuggestions.budgets.every(r => !!budgetItem(r))
    && allSuggestions.bids.every(({ k }) => !!bidItem(k))
    && allSuggestions.negs.every(({ t }) => !!negItem(t));
  const applyAll = () => {
    if (allApplied) {
      allSuggestions.budgets.forEach(r => { const it = budgetItem(r); if (it) doQueue.removeItem(it.id); });
      allSuggestions.bids.forEach(({ k }) => { const it = bidItem(k); if (it) doQueue.removeItem(it.id); });
      allSuggestions.negs.forEach(({ t }) => { const it = negItem(t); if (it) doQueue.removeItem(it.id); });
    } else {
      allSuggestions.budgets.forEach(r => { if (!budgetItem(r)) queueBudget(r); });
      allSuggestions.bids.forEach(({ r, k }) => { if (!bidItem(k)) queueKwBid(r, k); });
      allSuggestions.negs.forEach(({ r, t }) => { if (!negItem(t)) queueNeg(r, t); });
    }
  };

  const n = rows?.length ?? 0;
  const nMoves = rows?.filter(r => r.action.startsWith('RAISE') || r.action === 'CUT').length ?? 0;

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <div className="flex items-center gap-1">
        <button className="text-label flex items-center gap-1 flex-1 min-w-0" onClick={() => setOpen(o => !o)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-rose-300">{tier === 'LOW' ? 'Low budget — out of budget' : 'Portfolio 80/20 — out of budget'}</span>
          <span className="text-faint truncate">
            {failed ? '— unavailable' : rows
              ? `— ${n} dark yesterday · ${nMoves} budget moves · ${allSuggestions.bids.length} bids · ${allSuggestions.negs.length} negates`
              : '— loading…'}
            {' '}· goal: never out of budget, spend ~all of it
          </span>
        </button>
        {rows && nSug > 0 && (
          <button onClick={applyAll}
            title={allApplied ? 'unapply all suggestions in this phase' : 'queue every budget, bid and negation suggestion'}
            className={`text-label px-2 py-0.5 rounded border shrink-0 ${allApplied ? 'border-emerald-500/40 text-emerald-300' : 'border-rose-500/40 text-rose-300 hover:bg-rose-500/10'}`}>
            {allApplied ? `✓ applied ${nSug}` : `apply all ${nSug}`}
          </button>
        )}
      </div>
      {open && rows && (
        <div className="mt-2 overflow-x-auto">
          <table className="text-label font-mono border-collapse">
            <thead>
              <tr className="text-faint text-right">
                <th className="font-normal text-left px-2 py-0.5">item — campaign ▸ keyword ▸ term</th>
                <th className="font-normal px-2" title="share of the day Amazon reported CAMPAIGN_OUT_OF_BUDGET (campaign level)">dark</th>
                <th className="font-normal px-2" title="the current money setting at this level: campaign daily budget (bud) or keyword bid (bid)">now $</th>
                <th className="font-normal px-2" title="last complete day — campaign: net ROAS · keyword: clicks + net ROAS">last day</th>
                <th className="font-normal px-2" title="the 2 days before — same format as last day">prev-2d</th>
                <th className="font-normal px-2" title="keyword CPC yesterday vs target CPC (ʸ = same 28 days last year · ᵇ = coacher band)">CPC/target</th>
                <th className="font-normal px-2 text-left">action</th>
                <th className="font-normal px-2" title="suggested new value for the money setting in 'now $'">→ $</th>
                <th className="font-normal px-2"></th>
                <th className="font-normal px-2 text-left">why</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => {
                const camKws = kwByCamp.get(r.id) ?? [];
                const expanded = !!openCamps[r.id];
                const bItem = budgetItem(r);
                return (
                <Fragment key={r.id}>
                <tr className="text-right border-t border-border/40">
                  <td className="text-left px-2 py-0.5 text-body whitespace-nowrap">
                    {camKws.length > 0
                      ? <button className="text-faint pr-1" onClick={() => setOpenCamps(o => ({ ...o, [r.id]: !o[r.id] }))}>{expanded ? '▾' : '▸'}</button>
                      : <span className="pr-3" />}
                    {r.name}
                    <span className="text-faint text-label"> {r.channel}{r.engine === 'LAUNCH' ? ' · launch' : ''} · spent ${r.spend.toFixed(2)}{r.util != null ? <span className={r.util > 1.2 ? 'text-amber-400' : ''} title="spend ÷ budget. SB can exceed 100% — Amazon overdelivers SB up to 2× its daily budget"> · {Math.round(r.util * 100)}%</span> : null}</span>
                  </td>
                  <td className={`px-2 ${r.dark > 10 ? 'text-amber-400' : 'text-muted'}`}>{r.dark.toFixed(0)}%</td>
                  <td className="px-2 text-muted whitespace-nowrap">${r.budget.toFixed(0)} <span className="text-faint">bud</span> <span className="text-faint" title="spent yesterday">· ${r.spend.toFixed(2)}</span></td>
                  <td className="px-2 text-muted">{r.roas1 != null ? `${r.roas1.toFixed(2)}×` : '—'}</td>
                  <td className="px-2 text-muted">{r.roasPrev2 != null ? `${r.roasPrev2.toFixed(2)}×` : '—'}</td>
                  <td className="px-2" />
                  <td className={`px-2 text-left whitespace-nowrap ${ACTION_CLS[r.action] ?? 'text-muted'}`}>{r.action.toLowerCase().replace('_', ' ')}</td>
                  <td className="px-2">{r.suggested != null ? `$${r.suggested.toFixed(2)}` : '—'}</td>
                  <td className="px-2">
                    {budgetSug(r) && (
                      <button onClick={() => { const it = budgetItem(r); if (it) doQueue.removeItem(it.id); else queueBudget(r); }}
                        className={`px-1.5 py-0 rounded border ${bItem ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                        {bItem ? '✓' : 'budget'}
                      </button>
                    )}
                  </td>
                  <td className="px-2 text-left text-faint whitespace-nowrap">
                    {r.reason}
                    {r.daysSince != null && r.daysSince <= 3 ? ` · budget changed ${r.daysSince}d ago` : ''}
                  </td>
                </tr>
                {expanded && camKws.map(k => {
                  const kTerms = termsByKw.get(`${r.id}|${k.text}`) ?? [];
                  const negs = kTerms.filter(t => t.isNegate);
                  const winners = kTerms.filter(t => t.isWinner).length;
                  const kItem = bidItem(k);
                  return (
                  <Fragment key={`${r.id}|${k.keywordId || k.text}`}>
                  <tr className="text-right border-t border-border/20 bg-surface/40">
                    <td className="text-left pl-8 pr-2 py-0.5 text-muted whitespace-nowrap">{k.text}
                      <span className="text-faint"> ({k.isAuto ? 'auto' : k.isPt ? 'PT' : (k.matchType || '').toLowerCase()}){winners > 0 ? ` · ${winners} winner${winners > 1 ? 's' : ''}` : ''} · spent ${k.spend1.toFixed(2)}</span></td>
                    <td className="px-2" />
                    <td className="px-2 text-muted whitespace-nowrap" title="current bid">{k.bid != null ? <>${k.bid.toFixed(2)} <span className="text-faint">bid</span></> : '—'}<span className="text-faint" title="spent yesterday"> · ${k.spend1.toFixed(2)}</span></td>
                    <td className="px-2 text-muted whitespace-nowrap" title="last day clicks · net ROAS">{k.clicks1}c{k.roas1 != null ? ` ${k.roas1.toFixed(2)}×` : ' —'}</td>
                    <td className="px-2 text-muted whitespace-nowrap" title="prev-2d clicks · net ROAS">{k.clicks2}c{k.roas2 != null ? ` ${k.roas2.toFixed(2)}×` : ' —'}</td>
                    <td className="px-2 whitespace-nowrap" title={k.targetCpc != null
                        ? `CPC yesterday vs target CPC (${k.targetCpcSrc === 'LY' ? 'same 28 days last year' : 'coacher band: product × season × match'})`
                        : 'CPC yesterday — no target: no last-year data for this keyword and no conclusive band'}>
                      <span className={k.cpc1 != null && k.targetCpc != null ? (k.cpc1 > k.targetCpc ? 'text-amber-400' : 'text-emerald-400') : 'text-muted'}>
                        {k.cpc1 != null ? `$${k.cpc1.toFixed(2)}` : '—'}</span>
                      <span className="text-faint">{k.targetCpc != null ? ` /$${k.targetCpc.toFixed(2)}${k.targetCpcSrc === 'LY' ? 'ʸ' : 'ᵇ'}` : ''}</span>
                    </td>
                    <td className={`px-2 text-left whitespace-nowrap ${KW_CLS[k.action] ?? 'text-muted'}`}>{k.action.toLowerCase().replace('_', ' ')}</td>
                    <td className="px-2">{k.suggestedBid != null ? `$${k.suggestedBid.toFixed(2)}` : '—'}</td>
                    <td className="px-2">
                      {bidSug(k) && (
                        <button onClick={() => { const it = bidItem(k); if (it) doQueue.removeItem(it.id); else queueKwBid(r, k); }}
                          className={`px-1.5 py-0 rounded border ${kItem ? 'border-emerald-500/40 text-emerald-300' : 'border-border text-muted hover:bg-surface'}`}>
                          {kItem ? '✓' : 'bid'}
                        </button>
                      )}
                    </td>
                    <td className="px-2 text-left text-faint whitespace-nowrap">{k.reason}</td>
                  </tr>
                  {negs.map(t => {
                    const nItem = negItem(t);
                    return (
                    <tr key={`${r.id}|${k.keywordId || k.text}|${t.term}`} className="text-right border-t border-border/10">
                      <td className="text-left pl-14 pr-2 py-0.5 text-faint whitespace-nowrap">“{t.term}” <span>({t.kind.toLowerCase()})</span></td>
                      <td className="px-2" />
                      <td className="px-2 text-faint whitespace-nowrap" title="spent yesterday">{t.spend1d > 0 ? `$${t.spend1d.toFixed(2)}` : '—'}</td>
                      <td className="px-2 text-faint whitespace-nowrap" colSpan={2}>{t.isBig
                        ? `${t.marketPurchases90d.toLocaleString()} mkt purchases/90d · ${t.clicks90d}c here · 0 orders`
                        : `${t.clicks}c · $${t.spend.toFixed(2)} · 0 orders · 28d`}</td>
                      <td className="px-2" />
                      <td className="px-2 text-left text-red-400">negate</td>
                      <td className="px-2 text-faint">—</td>
                      <td className="px-2">
                        <button onClick={() => { const it = negItem(t); if (it) doQueue.removeItem(it.id); else queueNeg(r, t); }}
                          className={`px-1.5 py-0 rounded border ${nItem ? 'border-emerald-500/40 text-emerald-300' : 'border-red-500/30 text-red-400 hover:bg-red-500/10'}`}>
                          {nItem ? '✓' : 'negate'}
                        </button>
                      </td>
                      <td className="px-2 text-left text-faint whitespace-nowrap">{t.isBig
                          ? 'big word — 90 real days · 25+ clicks here · 0 orders anywhere'
                          : '≥10 clicks · 0 orders · 28d'}{['MANUAL', 'SB'].includes(t.kind) ? ' · not the keyword' : ''}</td>
                    </tr>
                  ); })}
                  </Fragment>
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
