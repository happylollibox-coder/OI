import { fShort } from '../../utils';
import type { RecommendationsByType, RecommendationRow } from './types';

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

function metricFor(row: RecommendationRow): string {
  switch (row.rec_type) {
    case 'BROAD':  return `${fShort(row.market_sales ?? 0)} cluster sales` + (row.cluster_size ? ` · ${row.cluster_size} terms` : '');
    case 'PHRASE': return `rank ${row.rank ?? '—'}` + (row.coverage_count ? ` · covers ${row.coverage_count}` : '');
    case 'BRAND':  return `${fShort(row.market_volume ?? 0)} vol`;
    default:       return `rank ${row.rank ?? '—'}`;
  }
}

export function RecommendationsCard({ recs, selectedProduct }: RecommendationsCardProps) {
  if (!recs) return null;
  const order: (keyof RecommendationsByType)[] = ['EXACT', 'PHRASE', 'BROAD', 'BRAND'];
  const total = order.reduce((s, k) => s + recs[k].length, 0);
  if (total === 0) return null;

  return (
    <div className="mb-4 border border-border/30 rounded-lg overflow-hidden bg-white/[0.01]">
      <div className="px-4 py-2.5 bg-white/[0.02] border-b border-border/20 flex items-center gap-2">
        <span className="text-sm font-bold text-heading">💡 Keyword Recommendations</span>
        <span className="text-[10px] text-muted">{selectedProduct} · {total} this week · shared with Coach</span>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-px bg-border/20">
        {order.map(type => {
          const rows = recs[type];
          const meta = TYPE_META[type];
          return (
            <div key={type} className="bg-surface px-4 py-3">
              <div className="flex items-center gap-2 mb-2">
                <span className={`px-1.5 py-0.5 rounded text-[9px] font-bold ${meta.badge}`}>{meta.label}</span>
                <span className="text-[9px] text-muted">{meta.hint}</span>
                <span className="ml-auto text-[9px] text-faint tabular-nums">{rows.length}</span>
              </div>
              {rows.length === 0 ? (
                <div className="text-[10px] text-faint italic">No new recommendations</div>
              ) : (
                <div className="flex flex-col gap-1">
                  {rows.map(r => (
                    <div key={r.keyword} className={`flex items-center gap-2 text-[10px] ${r.status === 'ADVERTISED' ? 'opacity-50' : ''}`}>
                      <span className="text-heading font-medium truncate max-w-[200px]" title={r.keyword}>{r.keyword}</span>
                      <span className="ml-auto text-[9px] text-muted tabular-nums whitespace-nowrap">{metricFor(r)}</span>
                      {r.status === 'ADVERTISED' && <span className="text-[8px] text-emerald-400" title="Now being advertised">✓ live</span>}
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
