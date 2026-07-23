import { useEffect, useMemo, useState, Fragment, type ReactNode } from 'react';
import { ChevronRight, ChevronDown } from 'lucide-react';
import {
  loadCampaignStrategyMap,
  loadAdsCampaigns,
  loadAdsKeywords,
  loadAdsSearchTerms,
} from '../../hooks/useCubeData';
import { fM, fP, fR, fmt } from '../../utils';
import { useFilters } from '../../hooks/useFilters';
import { useAdsWindow } from './adsWindow';
import { STRATEGY_META } from '../../strategies';
import {
  deriveMetrics,
  groupByStrategy,
  type AdsRowBase,
  type CampaignRow,
  type KeywordRow,
  type SearchTermRow,
} from './adsCampaignTable.helpers';

const COLUMNS = ['Spend', 'Bid', 'CPC', 'Impr', 'Clicks', 'CTR', 'CVR', 'ACOS', 'Net ROAS'];

/** The metric <td>s shared by every grain. Net ROAS colored green ≥1 / red <1. */
function MetricCells({ base, bid }: { base: AdsRowBase; bid: number | null }) {
  const d = deriveMetrics(base);
  const roasColor = base.spend <= 0 ? 'text-subtle' : d.netRoas >= 1 ? 'text-emerald-400' : 'text-red-400';
  const cell = 'px-3 py-1.5 text-right font-mono tabular-nums';
  return (
    <>
      <td className={`${cell} text-text`}>{fM(base.spend)}</td>
      <td className={`${cell} text-subtle`}>{bid == null ? '—' : fM(bid)}</td>
      <td className={`${cell} text-subtle`}>{fM(d.cpc)}</td>
      <td className={`${cell} text-subtle`}>{fmt(base.impressions)}</td>
      <td className={`${cell} text-subtle`}>{fmt(base.clicks)}</td>
      <td className={`${cell} text-subtle`}>{fP(d.ctr)}</td>
      <td className={`${cell} text-subtle`}>{fP(d.cvr)}</td>
      <td className={`${cell} text-subtle`}>{fP(d.acos)}</td>
      <td className={`${cell} font-semibold ${roasColor}`}>{fR(d.netRoas)}</td>
    </>
  );
}

/** A tree row: chevron + indented label, then the metric cells. */
function TreeRow({
  depth, label, base, bid, expandable, expanded, loading, onToggle, tone,
}: {
  depth: number;
  label: ReactNode;
  base: AdsRowBase;
  bid: number | null;
  expandable: boolean;
  expanded?: boolean;
  loading?: boolean;
  onToggle?: () => void;
  tone?: 'campaign' | 'keyword' | 'term';
}) {
  const toneCls = tone === 'campaign' ? 'font-semibold text-text' : tone === 'keyword' ? 'text-text' : 'text-subtle';
  // Ad net ROAS shown inline by the name (the Net ROAS column scrolls off to the right). Green ≥1 / red <1.
  const nr = deriveMetrics(base).netRoas;
  const roasTone = base.spend <= 0 ? 'text-subtle' : nr >= 1 ? 'text-emerald-400' : 'text-red-400';
  const profitable = base.spend > 0 && nr >= 1;
  const borderCls = profitable ? 'border-l-2 border-l-emerald-500' : 'border-l-2 border-l-transparent';
  return (
    <tr className={`border-b border-border-faint hover:bg-surface/40 ${borderCls}`}>
      <td className="px-3 py-1.5">
        <button
          onClick={expandable ? onToggle : undefined}
          className={`flex items-center gap-1 min-w-0 ${expandable ? 'cursor-pointer hover:text-blue-400' : 'cursor-default'} ${toneCls}`}
          style={{ paddingLeft: depth * 16 }}
        >
          {expandable ? (
            expanded ? <ChevronDown size={12} className="shrink-0 text-faint" /> : <ChevronRight size={12} className="shrink-0 text-faint" />
          ) : (
            <span className="inline-block w-3 shrink-0" />
          )}
          <span className="truncate text-[12px]">{label}</span>
          <span className={`shrink-0 font-mono text-[11px] font-semibold ${roasTone}`} title="Ad net ROAS">{fR(nr)}</span>
          {loading && <span className="text-[10px] text-faint ml-1 shrink-0">…</span>}
        </button>
      </td>
      <MetricCells base={base} bid={bid} />
    </tr>
  );
}

const kwKey = (campaignId: string, targeting: string) => `${campaignId}|${targeting}`;
const sumBase = (rows: AdsRowBase[]): AdsRowBase => rows.reduce(
  (s, r) => ({
    spend: s.spend + r.spend, orders: s.orders + r.orders, sales: s.sales + r.sales,
    clicks: s.clicks + r.clicks, impressions: s.impressions + r.impressions, grossProfit: s.grossProfit + r.grossProfit,
  }),
  { spend: 0, orders: 0, sales: 0, clicks: 0, impressions: 0, grossProfit: 0 },
);

/** `scopedCampaignIds` is the page's strategy/age scope: when non-null, only these campaigns are
 * shown (and strategy groups left empty by it disappear). Null means no scope. */
export function AdsCampaignTable({ scopedCampaignIds }: { scopedCampaignIds?: Set<string> | null } = {}) {
  const { start, end, incomplete } = useAdsWindow();
  const { filters } = useFilters();
  const family = filters.family;
  const product = filters.product;

  const [strategyMap, setStrategyMap] = useState<Record<string, string>>({});
  const [campaigns, setCampaigns] = useState<CampaignRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [expandedCampaigns, setExpandedCampaigns] = useState<Set<string>>(new Set());
  const [keywordsByCampaign, setKeywordsByCampaign] = useState<Map<string, KeywordRow[]>>(new Map());
  const [loadingCampaigns, setLoadingCampaigns] = useState<Set<string>>(new Set());

  const [expandedKeywords, setExpandedKeywords] = useState<Set<string>>(new Set());
  const [termsByKeyword, setTermsByKeyword] = useState<Map<string, SearchTermRow[]>>(new Map());
  const [loadingKeywords, setLoadingKeywords] = useState<Set<string>>(new Set());

  // Strategy mapping is window-independent — fetch once.
  useEffect(() => {
    let cancelled = false;
    loadCampaignStrategyMap().then(m => { if (!cancelled) setStrategyMap(m); }).catch(() => {});
    return () => { cancelled = true; };
  }, []);

  // Campaigns per window. Reset all child caches when the window changes.
  useEffect(() => {
    if (incomplete) return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    setExpandedCampaigns(new Set());
    setKeywordsByCampaign(new Map());
    setExpandedKeywords(new Set());
    setTermsByKeyword(new Map());
    loadAdsCampaigns(start, end, family, product)
      .then(c => { if (!cancelled) setCampaigns(c); })
      .catch(e => { if (!cancelled) setError(String(e?.message || e)); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [start, end, incomplete, family, product]);

  const groups = useMemo(() => {
    const scoped = scopedCampaignIds ? campaigns.filter(c => scopedCampaignIds.has(c.campaignId)) : campaigns;
    return groupByStrategy(scoped, strategyMap);
  }, [campaigns, strategyMap, scopedCampaignIds]);

  const toggleCampaign = (id: string) => {
    const willExpand = !expandedCampaigns.has(id);
    setExpandedCampaigns(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
    if (willExpand && !keywordsByCampaign.has(id)) {
      setLoadingCampaigns(p => new Set(p).add(id));
      loadAdsKeywords(id, start, end, family, product)
        .then(kw => setKeywordsByCampaign(m => new Map(m).set(id, kw)))
        .catch(() => setKeywordsByCampaign(m => new Map(m).set(id, [])))
        .finally(() => setLoadingCampaigns(p => { const n = new Set(p); n.delete(id); return n; }));
    }
  };

  const toggleKeyword = (campaignId: string, targeting: string) => {
    const key = kwKey(campaignId, targeting);
    const willExpand = !expandedKeywords.has(key);
    setExpandedKeywords(prev => {
      const next = new Set(prev);
      next.has(key) ? next.delete(key) : next.add(key);
      return next;
    });
    if (willExpand && !termsByKeyword.has(key)) {
      setLoadingKeywords(p => new Set(p).add(key));
      loadAdsSearchTerms(campaignId, targeting, start, end, family, product)
        .then(terms => setTermsByKeyword(m => new Map(m).set(key, terms)))
        .catch(() => setTermsByKeyword(m => new Map(m).set(key, [])))
        .finally(() => setLoadingKeywords(p => { const n = new Set(p); n.delete(key); return n; }));
    }
  };

  return (
    <div className="bg-card border border-border rounded-lg p-4 mb-5">
      <div className="flex items-center gap-2 mb-3">
        <h2 className="text-[15px] font-bold">Campaigns by strategy</h2>
        <span className="text-[10px] font-mono text-faint">{start} → {end}</span>
      </div>

      {error ? (
        <div className="text-[12px] text-red-400 px-3 py-2 rounded-lg bg-red-500/10 border border-red-500/20">
          Failed to load campaigns: {error}
        </div>
      ) : loading ? (
        <div className="text-[12px] text-faint px-3 py-6 text-center">Loading campaigns…</div>
      ) : groups.length === 0 ? (
        <div className="text-[12px] text-faint px-3 py-6 text-center">No campaign spend in this window.</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-[12px] border-collapse">
            <thead>
              <tr className="border-b border-border text-faint">
                <th className="px-3 py-1.5 text-left font-semibold uppercase tracking-wider text-[10px]">Strategy · Campaign · Keyword · Term</th>
                {COLUMNS.map(c => (
                  <th key={c} className="px-3 py-1.5 text-right font-semibold uppercase tracking-wider text-[10px]">{c}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {groups.map(group => {
                const gBase = sumBase(group.campaigns);
                return (
                  <Fragment key={`s-${group.strategy}`}>
                    {/* Strategy header */}
                    <tr className={`bg-surface/60 border-b border-border ${gBase.spend > 0 && deriveMetrics(gBase).netRoas >= 1 ? 'border-l-2 border-l-emerald-500' : 'border-l-2 border-l-transparent'}`}>
                      <td className="px-3 py-1.5">
                        <span className="text-[11px] font-bold uppercase tracking-wider text-blue-400/90">{STRATEGY_META[group.strategy]?.label ?? group.strategy}</span>
                        <span className="text-faint text-[10px] ml-2">{group.campaigns.length} campaigns</span>
                        <span className={`ml-2 font-mono text-[11px] font-semibold ${gBase.spend <= 0 ? 'text-subtle' : deriveMetrics(gBase).netRoas >= 1 ? 'text-emerald-400' : 'text-red-400'}`} title="Ad net ROAS">{fR(deriveMetrics(gBase).netRoas)}</span>
                      </td>
                      <MetricCells base={gBase} bid={null} />
                    </tr>

                    {/* Campaigns */}
                    {group.campaigns.map((c, ci) => {
                      const kws = keywordsByCampaign.get(c.campaignId);
                      const cExpanded = expandedCampaigns.has(c.campaignId);
                      return (
                        <Fragment key={`c-${group.strategy}-${ci}-${c.campaignId}`}>
                          <TreeRow
                            depth={1}
                            tone="campaign"
                            label={<>{c.campaignName}{c.campaignType ? <span className="text-faint text-[10px] ml-1.5">{c.campaignType}</span> : null}</>}
                            base={c}
                            bid={null}
                            expandable
                            expanded={cExpanded}
                            loading={loadingCampaigns.has(c.campaignId)}
                            onToggle={() => toggleCampaign(c.campaignId)}
                          />
                          {cExpanded && kws && kws.length === 0 && (
                            <tr key={`c-${c.campaignId}-empty`} className="border-b border-border-faint">
                              <td className="px-3 py-1.5 text-[11px] text-faint" style={{ paddingLeft: 2 * 16 + 12 }} colSpan={COLUMNS.length + 1}>No keyword-level data.</td>
                            </tr>
                          )}
                          {cExpanded && kws && kws.map(kw => {
                            const key = kwKey(c.campaignId, kw.targeting);
                            const kExpanded = expandedKeywords.has(key);
                            const terms = termsByKeyword.get(key);
                            const label = <>{kw.targeting}{kw.matchType ? <span className="text-faint text-[10px] ml-1.5">{kw.matchType}</span> : null}</>;
                            return (
                              <Fragment key={`k-${key}`}>
                                <TreeRow
                                  depth={2}
                                  tone="keyword"
                                  label={label}
                                  base={kw}
                                  bid={kw.bid}
                                  expandable={!!kw.targeting}
                                  expanded={kExpanded}
                                  loading={loadingKeywords.has(key)}
                                  onToggle={() => toggleKeyword(c.campaignId, kw.targeting)}
                                />
                                {kExpanded && terms && terms.length === 0 && (
                                  <tr key={`k-${key}-empty`} className="border-b border-border-faint">
                                    <td className="px-3 py-1.5 text-[11px] text-faint" style={{ paddingLeft: 3 * 16 + 12 }} colSpan={COLUMNS.length + 1}>No search-term data.</td>
                                  </tr>
                                )}
                                {kExpanded && terms && terms.map((t, i) => (
                                  <TreeRow
                                    key={`t-${key}-${i}`}
                                    depth={3}
                                    tone="term"
                                    label={t.searchTerm}
                                    base={t}
                                    bid={kw.bid}
                                    expandable={false}
                                  />
                                ))}
                              </Fragment>
                            );
                          })}
                        </Fragment>
                      );
                    })}
                  </Fragment>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
