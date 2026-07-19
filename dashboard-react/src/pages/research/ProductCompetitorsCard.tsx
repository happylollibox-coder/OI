import { useEffect, useState } from 'react';
import { apiFetch } from '../../utils/apiFetch';

interface PTRow {
  target_asin: string;
  own_parent: string | null;
  own_color: string | null;
  clicks: number;
  orders: number;
  spend: number;
  cvr_pct: number | null;
  net_roas: number | null;
}
interface PTData { BRAND: PTRow[]; NON_BRAND: PTRow[]; }

const SECTIONS = [
  { key: 'BRAND' as const,     label: '🛡️ Brand product targets',     badge: 'bg-cyan-500/15 text-cyan-400', hint: 'Your own ASINs · cross-sell / defense · high CVR' },
  { key: 'NON_BRAND' as const, label: '🎯 Non-brand product targets', badge: 'bg-rose-500/15 text-rose-400', hint: 'External competitor ASINs · high CVR' },
];

/** Product-targeting (ASIN targeting) opportunities: pages where our ads convert
 *  well, split by own-brand vs external competitor. Data + own/external logic live
 *  in /api/research/product-competitors (BigQuery); this only renders. */
export function ProductCompetitorsCard({ selectedProduct }: { selectedProduct: string }) {
  const [data, setData] = useState<PTData | null>(null);

  useEffect(() => {
    if (!selectedProduct) { setData(null); return; }
    const ctrl = new AbortController();
    apiFetch(`/api/research/product-competitors?parent=${encodeURIComponent(selectedProduct)}`, { signal: ctrl.signal })
      .then(r => (r.ok ? r.json() : null))
      .then(d => setData(d && !d.error ? d : null))
      .catch(() => {});
    return () => ctrl.abort();
  }, [selectedProduct]);

  if (!data) return null;
  const total = data.BRAND.length + data.NON_BRAND.length;
  if (total === 0) return null;

  return (
    <div className="mb-4 border border-border/30 rounded-lg overflow-hidden bg-white/[0.01]">
      <div className="px-4 py-2.5 bg-white/[0.02] border-b border-border/20 flex items-center gap-2">
        <span className="text-sm font-bold text-heading">🧲 Product-Targeting Opportunities</span>
        <span className="text-[10px] text-muted">{selectedProduct} · where ads on other product pages convert · ≥15 clicks</span>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-px bg-border/20">
        {SECTIONS.map(sec => {
          const rows = data[sec.key];
          return (
            <div key={sec.key} className="bg-surface px-4 py-3">
              <div className="flex items-center gap-2 mb-2">
                <span className={`px-1.5 py-0.5 rounded text-[9px] font-bold ${sec.badge}`}>{sec.label}</span>
                <span className="text-[9px] text-muted">{sec.hint}</span>
                <span className="ml-auto text-[9px] text-faint tabular-nums">{rows.length}</span>
              </div>
              {rows.length === 0 ? (
                <div className="text-[10px] text-faint italic">No qualifying targets</div>
              ) : (
                <div className="flex flex-col gap-1">
                  {rows.map(r => {
                    const label = r.own_parent
                      ? `${r.own_parent}${r.own_color ? ' · ' + r.own_color : ''}`
                      : r.target_asin;
                    return (
                      <div key={r.target_asin} className="flex items-center gap-2 text-[10px]">
                        <a
                          href={`https://www.amazon.com/dp/${r.target_asin}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-heading font-medium truncate max-w-[190px] hover:underline"
                          title={`${label} — ${r.target_asin}`}
                        >{label}</a>
                        <span className="ml-auto text-[9px] tabular-nums whitespace-nowrap">
                          <span className={r.cvr_pct != null && r.cvr_pct >= 8 ? 'text-emerald-400 font-semibold' : 'text-muted'}>{r.cvr_pct}% cvr</span>
                          <span className="text-faint"> · {r.orders} ord</span>
                          {r.net_roas != null && <span className={r.net_roas >= 1 ? 'text-emerald-400' : 'text-red-400'}> · {r.net_roas}x</span>}
                        </span>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
