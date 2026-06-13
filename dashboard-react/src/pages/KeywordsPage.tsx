import React, { useState, useMemo } from 'react';
import type { DashboardData } from '../types';
import { Badge, RoasBadge, ActionBadge } from '../components/Badge';
import { PageHeader } from '../components/PageHeader';
import { Empty } from '../components/Empty';
import { Th, SortTh, useSort } from '../components/Tooltip';
import { fM, fP, fOrd, fClk, fCpc, fMktV, famFromType } from '../utils';
import { useFilters } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { FilterInfoIcon } from '../components/FilterInfoIcon';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';
import { usePageSummary } from '../components/PageSummaryBar';
const KEYWORDS_TABLE_COLUMNS: MeasureDef[] = [
  { id: 'search_term', label: 'Keyword', group: 'Info' },
  { id: 'product_short_name', label: 'Product', group: 'Info' },
  { id: 'hero_asin', label: 'Hero', group: 'Info' },
  { id: 'is_hero_match', label: 'Match?', group: 'Info' },
  { id: 'experiment_id', label: 'Experiment', group: 'Info', defaultVisible: false },
  { id: 'spend_60d', label: 'Ads Spend', group: 'Ads' },
  { id: 'orders_60d', label: 'Ads Orders', group: 'Ads' },
  { id: 'clicks_60d', label: 'Ads Clicks', group: 'Ads', defaultVisible: false },
  { id: 'impressions_60d', label: 'Ads Impr', group: 'Ads', defaultVisible: false },
  { id: 'cpc_60d', label: 'Ads CPC', group: 'Ads', defaultVisible: false },
  { id: 'conv_rate_60d', label: 'Ads Conv%', group: 'Ads' },
  { id: 'net_roas_60d', label: 'Ads ROAS', group: 'Ads' },
  { id: 'impression_share', label: 'Ads Imp Share', group: 'Ads' },
  { id: 'market_volume', label: 'SQP Mkt Vol', group: 'SQP' },
  { id: 'action', label: 'Action', group: 'Info' },
];

export function KeywordsPage({ data }: { data: DashboardData }) {
  const { filters } = useFilters();
  const rows = data.keyword_product_map || [];
  const products = data.products || [];
  const [actFilter, setActFilter] = useState('all');
  const [heroFilter, setHeroFilter] = useState('all');

  const actions = useMemo(() => [...new Set(rows.map(r => r.action).filter(Boolean))].sort(), [rows]);

  const filtered = useMemo(() => {
    let f = rows;
    if (filters.family) f = f.filter(r => {
      const p = products.find(x => x.asin === r.hero_asin);
      return p ? famFromType(p.product_type) === filters.family : false;
    });
    if (filters.keyword) f = f.filter(r => r.search_term === filters.keyword);
    if (actFilter !== 'all') f = f.filter(r => r.action === actFilter);
    if (heroFilter === 'yes') f = f.filter(r => r.is_hero_match === true);
    if (heroFilter === 'no') f = f.filter(r => r.is_hero_match === false);
    return f.slice(0, 200);
  }, [rows, products, filters.family, filters.keyword, actFilter, heroFilter]);

  const s = useSort('spend_60d');
  const [kwCols, setKwCols] = useMeasureSelection('keywords', KEYWORDS_TABLE_COLUMNS);
  const visibleKwCols = useMemo(() => KEYWORDS_TABLE_COLUMNS.filter(c => kwCols.has(c.id)), [kwCols]);

  // Hooks must run unconditionally — keep above any early return (Rules of Hooks).
  usePageSummary({ title: 'Keywords', items: [{ label: 'Keyword Tracker', value: 'Active' }] });

  if (!rows.length) return <Empty icon="🔍" message="No keyword data" hint="Keyword data syncs from your Amazon Ads campaigns." />;

  const kwFilterItems = formatSectionFilters(filters, {
    ...(actFilter !== 'all' && { Action: actFilter }),
    ...(heroFilter !== 'all' && { Hero: heroFilter === 'yes' ? 'Match' : 'Mismatch' }),
  });

  return (
    <div className="animate-in">
      <div className="flex items-center gap-2 mb-5">
        <PageHeader title="Keyword\u2013Product Map" subtitle="Advertised vs. Purchased" />
        {kwFilterItems.length > 0 && <FilterInfoIcon items={kwFilterItems} />}
        <div className="ml-auto"><MeasureSelector tableId="keywords" measures={KEYWORDS_TABLE_COLUMNS} selected={kwCols} onSelectedChange={setKwCols} /></div>
      </div>

      <div className="flex gap-2 items-center flex-wrap p-2.5 bg-surface/50 backdrop-blur border border-border rounded-xl mb-3.5">
        <span className="text-[10px] text-subtle uppercase tracking-wider font-semibold">Family:</span>
        <span className="text-[11px] text-muted">{filters.family || 'All'}</span>
        <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold ml-2">Action</label>
        <select value={actFilter} onChange={e => setActFilter(e.target.value)} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
          <option value="all">All</option>
          {actions.map(a => <option key={a} value={a}>{a}</option>)}
        </select>
        <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold ml-2">Hero</label>
        <select value={heroFilter} onChange={e => setHeroFilter(e.target.value)} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
          <option value="all">All</option>
          <option value="yes">Match</option>
          <option value="no">Mismatch</option>
        </select>
      </div>

      <div className="border border-border rounded-xl bg-card overflow-x-auto" style={{ maxHeight: '62vh', overflowY: 'auto' }}>
        <table className="w-full border-collapse text-xs">
          <thead>
            <tr>
              {visibleKwCols.map(c => (
                ['experiment_id', 'action'].includes(c.id) ? (
                  <Th key={c.id}>{c.label}</Th>
                ) : (
                  <SortTh key={c.id} k={c.id} sort={s.sort} toggle={s.toggle} right={!['search_term', 'product_short_name', 'hero_asin', 'is_hero_match'].includes(c.id)} tip={c.tip}>{c.label}</SortTh>
                )
              ))}
            </tr>
          </thead>
          <tbody>
            {s.sorted(filtered).map((r, i) => {
              const cells: Record<string, React.ReactNode> = {
                search_term: <td key="search_term" className="px-3 py-2 font-semibold">{r.search_term || '--'}</td>,
                product_short_name: <td key="product_short_name" className="px-3 py-2">{r.product_short_name || '--'}</td>,
                hero_asin: <td key="hero_asin" className="px-3 py-2 font-mono text-[10px]">{r.hero_asin ? r.hero_asin.slice(-4) : '--'}</td>,
                is_hero_match: <td key="is_hero_match" className="px-3 py-2">{r.is_hero_match === true ? <Badge variant="green">YES</Badge> : r.is_hero_match === false ? <Badge variant="red">NO</Badge> : <Badge variant="muted">--</Badge>}</td>,
                experiment_id: <td key="experiment_id" className="px-3 py-2 text-[11px] text-subtle max-w-[140px] truncate" title={r.experiment_id}>{r.experiment_id || '--'}</td>,
                spend_60d: <td key="spend_60d" className="px-3 py-2 text-right font-mono text-[11px] font-medium">{fM(r.spend_60d)}</td>,
                orders_60d: <td key="orders_60d" className="px-3 py-2 text-right">{fOrd(r.orders_60d)}</td>,
                clicks_60d: <td key="clicks_60d" className="px-3 py-2 text-right font-mono text-[11px]">{r.clicks_60d != null ? fClk(r.clicks_60d) : '--'}</td>,
                impressions_60d: <td key="impressions_60d" className="px-3 py-2 text-right font-mono text-[11px]">{(r.impressions_60d ?? 0) > 0 ? (r.impressions_60d ?? 0).toLocaleString() : '--'}</td>,
                cpc_60d: <td key="cpc_60d" className="px-3 py-2 text-right font-mono text-[11px]">{r.cpc_60d != null ? fCpc(r.cpc_60d) : '--'}</td>,
                conv_rate_60d: <td key="conv_rate_60d" className="px-3 py-2 text-right">{fP(r.conv_rate_60d)}</td>,
                net_roas_60d: <td key="net_roas_60d" className="px-3 py-2 text-right"><RoasBadge value={r.net_roas_60d} /></td>,
                impression_share: <td key="impression_share" className="px-3 py-2 text-right">{fP(r.impression_share)}</td>,
                market_volume: <td key="market_volume" className="px-3 py-2 text-right">{r.market_volume ? fMktV(r.market_volume) : ''}</td>,
                action: <td key="action" className="px-3 py-2"><ActionBadge action={r.action} /></td>,
              };
              return (
                <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                  {visibleKwCols.map(c => cells[c.id])}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
