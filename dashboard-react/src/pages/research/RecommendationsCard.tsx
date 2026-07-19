import { useState } from 'react';
import { fShort } from '../../utils';
import { apiFetch } from '../../utils/apiFetch';
import type { RecommendationsByType, RecommendationRow } from './types';

interface ExplainMember { term: string; sales: number | null; fit: number | null; }
interface ExplainState { type: 'BROAD' | 'PHRASE'; keyword: string; loading: boolean; members: ExplainMember[]; }

interface RecommendationsCardProps {
  recs: RecommendationsByType | null;
  selectedProduct: string;
}

const TYPE_META: Record<keyof RecommendationsByType, { label: string; badge: string; hint: string }> = {
  EXACT:  { label: '🎯 Exact',  badge: 'bg-blue-500/15 text-blue-400',     hint: 'Not advertised · rank ≥ 75' },
  PHRASE: { label: '🔤 Phrase', badge: 'bg-purple-500/15 text-purple-400', hint: '≥3-word terms · rank ≥ 75 · phrase match' },
  BROAD:  { label: '🌐 Broad',  badge: 'bg-amber-500/15 text-amber-400',   hint: 'fit ≥ 90 cluster · >500 market sales' },
  BRAND:  { label: '🛡️ Brand',  badge: 'bg-cyan-500/15 text-cyan-400',      hint: 'Own-brand defense · phrase match' },
};

type StatusFilter = 'all' | 'new' | 'adv';
const FILTER_OPTS: { key: StatusFilter; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'new', label: 'Not adv' },
  { key: 'adv', label: 'Advertised' },
];

function metricFor(row: RecommendationRow): string {
  switch (row.rec_type) {
    case 'BROAD':  return `${fShort(row.market_sales ?? 0)} cluster sales` + (row.cluster_size ? ` · ${row.cluster_size} terms` : '');
    case 'PHRASE': return `fit ${row.rank ?? '—'}` + (row.coverage_count ? ` · covers ${row.coverage_count}` : '');
    case 'BRAND':  return `${fShort(row.market_volume ?? 0)} vol`;
    default:       return `rank ${row.rank ?? '—'}`;
  }
}

function matchesFilter(row: RecommendationRow, f: StatusFilter): boolean {
  if (f === 'adv') return row.status === 'ADVERTISED';
  if (f === 'new') return row.status !== 'ADVERTISED';
  return true;
}

export function RecommendationsCard({ recs, selectedProduct }: RecommendationsCardProps) {
  const [filters, setFilters] = useState<Record<string, StatusFilter>>({});
  const [copied, setCopied] = useState<string | null>(null);
  const [explain, setExplain] = useState<ExplainState | null>(null);

  const openExplain = (type: 'BROAD' | 'PHRASE', keyword: string) => {
    setExplain({ type, keyword, loading: true, members: [] });
    apiFetch(`/api/research/rec-explain?parent=${encodeURIComponent(selectedProduct)}&keyword=${encodeURIComponent(keyword)}&rec_type=${type}`)
      .then(r => (r.ok ? r.json() : null))
      .then(j => setExplain(e => (e && e.keyword === keyword ? { ...e, loading: false, members: j?.members || [] } : e)))
      .catch(() => setExplain(e => (e ? { ...e, loading: false } : e)));
  };

  if (!recs) return null;
  const order: (keyof RecommendationsByType)[] = ['EXACT', 'PHRASE', 'BROAD', 'BRAND'];
  const total = order.reduce((s, k) => s + recs[k].length, 0);
  if (total === 0) return null;

  const getFilter = (type: string): StatusFilter => filters[type] ?? 'all';

  const copyBucket = (type: string, rows: RecommendationRow[]) => {
    const text = rows.map(r => r.keyword).join('\n');
    navigator.clipboard?.writeText(text).then(() => {
      setCopied(type);
      setTimeout(() => setCopied(c => (c === type ? null : c)), 1200);
    }).catch(() => {});
  };

  return (
    <div className="mb-4 border border-border/30 rounded-lg overflow-hidden bg-white/[0.01]">
      <div className="px-4 py-2.5 bg-white/[0.02] border-b border-border/20 flex items-center gap-2">
        <span className="text-sm font-bold text-heading">💡 Keyword Recommendations</span>
        <span className="text-[10px] text-muted">{selectedProduct} · {total} this week · shared with Coach</span>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-px bg-border/20">
        {order.map(type => {
          const meta = TYPE_META[type];
          const f = getFilter(type);
          const rows = recs[type].filter(r => matchesFilter(r, f));
          return (
            <div key={type} className="bg-surface px-4 py-3">
              <div className="mb-2">
                <div className="flex items-center gap-1.5">
                  <span className={`px-1.5 py-0.5 rounded text-[9px] font-bold ${meta.badge}`}>{meta.label}</span>
                  <div className="ml-auto flex items-center gap-1">
                    <div className="flex items-center rounded overflow-hidden border border-border/30">
                      {FILTER_OPTS.map(o => (
                        <button
                          key={o.key}
                          onClick={() => setFilters(p => ({ ...p, [type]: o.key }))}
                          className={`px-1 py-0.5 text-[8px] transition-colors ${f === o.key ? 'bg-blue-500/20 text-blue-300 font-semibold' : 'text-muted hover:text-heading'}`}
                        >{o.label}</button>
                      ))}
                    </div>
                    <button
                      onClick={() => copyBucket(type, rows)}
                      disabled={rows.length === 0}
                      title="Copy the shown keywords (one per line)"
                      className="px-1 py-0.5 text-[8px] rounded border border-border/30 text-muted hover:text-heading disabled:opacity-40"
                    >{copied === type ? '✓ Copied' : '⧉ Copy'}</button>
                    <span className="text-[9px] text-faint tabular-nums w-5 text-right">{rows.length}</span>
                  </div>
                </div>
                <div className="text-[9px] text-muted mt-1">{meta.hint}</div>
              </div>
              {rows.length === 0 ? (
                <div className="text-[10px] text-faint italic">No {f === 'adv' ? 'advertised' : f === 'new' ? 'not-advertised' : ''} recommendations</div>
              ) : (
                <div className="flex flex-col gap-1">
                  {rows.map(r => (
                    <div key={r.keyword} className={`flex items-center gap-2 text-[10px] ${r.status === 'ADVERTISED' ? 'opacity-50' : ''}`}>
                      <span className="text-heading font-medium truncate max-w-[200px]" title={r.keyword}>{r.keyword}</span>
                      {(r.rec_type === 'BROAD' || r.rec_type === 'PHRASE') ? (
                        <button
                          onClick={() => openExplain(r.rec_type as 'BROAD' | 'PHRASE', r.keyword)}
                          className="ml-auto text-[9px] text-muted tabular-nums whitespace-nowrap hover:text-blue-300 hover:underline cursor-pointer"
                          title={r.rec_type === 'BROAD' ? 'Show the terms in this discovery cluster' : 'Show the terms this phrase covers'}
                        >{metricFor(r)}</button>
                      ) : (
                        <span className="ml-auto text-[9px] text-muted tabular-nums whitespace-nowrap">{metricFor(r)}</span>
                      )}
                      {r.status === 'ADVERTISED' && <span className="text-[8px] text-emerald-400" title="Now being advertised">✓ live</span>}
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {explain && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" onClick={() => setExplain(null)}>
          <div className="bg-card border border-border rounded-xl shadow-2xl max-w-[560px] w-[92%] max-h-[80vh] overflow-hidden flex flex-col" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between px-4 py-3 border-b border-border shrink-0">
              <div className="text-sm font-semibold">
                <span className="text-muted">{explain.type === 'BROAD' ? 'Broad cluster' : 'Phrase coverage'}:</span> {explain.keyword}
                <span className="text-faint text-xs ml-2 font-normal">
                  {explain.type === 'BROAD'
                    ? 'terms this broad match discovers (shoppers who searched the seed also bought under these)'
                    : 'search terms this phrase match also serves (they contain all its key words)'}
                </span>
              </div>
              <button onClick={() => setExplain(null)} className="text-faint hover:text-text text-xl leading-none px-1">×</button>
            </div>
            <div className="overflow-auto">
              {explain.loading ? (
                <div className="p-10 text-center text-muted text-sm">Loading…</div>
              ) : explain.members.length === 0 ? (
                <div className="p-10 text-center text-muted text-sm">No terms found.</div>
              ) : (
                <>
                  <div className="px-4 py-2 text-[10px] text-muted border-b border-border-faint">
                    {explain.members.length} terms · {fShort(explain.members.reduce((s, m) => s + (m.sales || 0), 0))} total market sales <span className="text-faint">(live)</span>
                  </div>
                  <table className="w-full text-xs">
                    <thead className="sticky top-0 bg-surface z-10">
                      <tr className="text-faint text-left border-b border-border">
                        <th className="px-3 py-2 font-semibold">Term</th>
                        <th className="px-3 py-2 text-right font-semibold">Market sales</th>
                        <th className="px-3 py-2 text-right font-semibold">Fit</th>
                      </tr>
                    </thead>
                    <tbody>
                      {explain.members.map(m => (
                        <tr key={m.term} className="border-b border-border-faint hover:bg-surface/40">
                          <td className="px-3 py-1.5 truncate max-w-[300px]" title={m.term}>
                            {m.term}
                            {m.term === explain.keyword.toLowerCase() && <span className="text-[9px] text-blue-400 ml-1">seed</span>}
                          </td>
                          <td className="px-3 py-1.5 text-right font-mono text-subtle">{fShort(m.sales || 0)}</td>
                          <td className="px-3 py-1.5 text-right font-mono text-subtle">{m.fit ?? '—'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
