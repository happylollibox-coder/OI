import { useEffect, useState } from 'react';
import { apiFetch } from '../../utils/apiFetch';
import { fShort, fM, fR } from '../../utils';

interface IntentTerm {
  term: string;
  rank: number | null;          // effective_rank (ungated — seasonal terms are rank 0 otherwise)
  fit: number | null;
  demand: number | null;
  term_spend: number | null;
  term_clicks: number | null;
  term_net_roas: number | null;
}
interface Intent {
  intent_key: string;
  label: string;
  intent_type: 'GENERIC' | 'TIME_BASED';
  cross_family: boolean;
  family_best_rank: number | null;
  holiday_name: string | null;
  season_start: string | null;
  season_end: string | null;
  terms: IntentTerm[];
  ads_spend: number | null;
  ads_clicks: number | null;
  ads_orders: number | null;
  ads_net_roas: number | null;
  ads_window_start: string | null;
  ads_window_end: string | null;
  ads_used_fallback: boolean | null;
  ads_sp_spend: number | null;  ads_sp_net_roas: number | null;
  ads_sbv_spend: number | null; ads_sbv_net_roas: number | null;
  ads_sbc_spend: number | null; ads_sbc_net_roas: number | null;
}

/** Per-family intent themes + their top-10 keywords (architecture/INTENT_CAMPAIGN_MODEL.md §B.1).
 *  Relevance gate + ranking live in V_INTENT_KEYWORDS (BigQuery); this only renders. */
export function IntentsPanel({ selectedProduct }: { selectedProduct: string }) {
  const [intents, setIntents] = useState<Intent[] | null>(null);
  const [open, setOpen] = useState<string | null>(null);

  useEffect(() => {
    if (!selectedProduct) { setIntents(null); return; }
    const ctrl = new AbortController();
    apiFetch(`/api/research/intents?parent=${encodeURIComponent(selectedProduct)}`, { signal: ctrl.signal })
      .then(r => (r.ok ? r.json() : null))
      .then(d => setIntents(d && !d.error ? d.intents : null))
      .catch(() => {});
    return () => ctrl.abort();
  }, [selectedProduct]);

  if (!intents || intents.length === 0) return null;
  const generic = intents.filter(i => i.intent_type === 'GENERIC');
  const seasonal = intents.filter(i => i.intent_type === 'TIME_BASED');

  const row = (i: Intent) => {
    const isOpen = open === i.intent_key;
    return (
      <div key={i.intent_key} className="border border-border/20 rounded bg-surface">
        <button
          onClick={() => setOpen(o => (o === i.intent_key ? null : i.intent_key))}
          className="w-full flex items-center gap-2 px-2 py-1.5 text-left hover:bg-white/[0.02]"
        >
          <span className={`transition-transform text-[8px] text-faint ${isOpen ? 'rotate-90' : ''}`}>▶</span>
          <span className="text-[11px] font-medium text-heading">{i.label}</span>
          {i.intent_type === 'TIME_BASED' ? (
            <span className="px-1 py-0.5 rounded text-[8px] bg-amber-500/15 text-amber-400" title="Seasonal — the season window controls when it runs">
              ⏱ {i.season_start ?? '?'} → {i.season_end ?? 'no pause date'}
            </span>
          ) : (
            <span className="px-1 py-0.5 rounded text-[8px] bg-blue-500/15 text-blue-400">rank {i.family_best_rank}</span>
          )}
          {/* Money signal — rank is market FIT, this is profit. An intent can clear the
              rank gate and still lose money (e.g. LolliME/school: rank 63, 0.27 net ROAS). */}
          <span className="ml-auto text-[9px] tabular-nums whitespace-nowrap">
            {i.ads_spend ? (
              <>
                <span className="text-faint">{fM(i.ads_spend)}</span>
                {i.ads_net_roas != null && (
                  <span className={i.ads_net_roas >= 1 ? ' text-emerald-400 font-semibold' : ' text-red-400 font-semibold'}>
                    {' '}{fR(i.ads_net_roas)}
                  </span>
                )}
                {i.ads_net_roas != null && i.ads_net_roas < 1 && (i.ads_clicks ?? 0) >= 100 && (
                  <span className="text-red-400" title={`${i.ads_clicks} clicks → ${i.ads_orders} orders. Loses money despite clearing the rank gate.`}> ⚠</span>
                )}
              </>
            ) : (
              <span className="text-faint" title="No ad spend on this intent's terms yet — untested">untested</span>
            )}
          </span>
          <span className="text-[9px] text-faint tabular-nums w-[38px] text-right">{i.terms.length} kw</span>
        </button>
        {isOpen && (
          <div className="px-2 pb-2 pt-0.5 flex flex-col gap-0.5">
            {i.ads_spend != null && (
              <div className="text-[9px] text-muted pb-1 mb-1 border-b border-border-faint">
                Ads on this intent's terms ({i.intent_type === 'TIME_BASED'
                  ? `last ${i.label} season ${i.ads_window_start ?? '?'} → ${i.ads_window_end ?? '?'}`
                  : i.ads_used_fallback
                    ? `no 90d data → 12mo OFF-PEAK ${i.ads_window_start ?? '?'} → ${i.ads_window_end ?? '?'}`
                    : '90d'}): <span className="text-heading">{fM(i.ads_spend)}</span> spend ·{' '}
                {fShort(i.ads_clicks ?? 0)} clicks · {i.ads_orders ?? 0} orders ·{' '}
                <span className={(i.ads_net_roas ?? 0) >= 1 ? 'text-emerald-400' : 'text-red-400'}>
                  {i.ads_net_roas != null ? fR(i.ads_net_roas) : '—'} net ROAS
                </span>
                {(i.ads_orders ?? 0) > 0 && (
                  <span className="text-faint"> · {Math.round((i.ads_clicks ?? 0) / (i.ads_orders || 1))} clicks/sale</span>
                )}
                {/* Format split — the blended figure above can hide a profitable format inside a
                    losing intent (tween-christmas-gift: blended 0.94, but SB_VIDEO 1.25 / SP 0.40).
                    Placement (top-of-search vs rest) is NOT available at search-term grain. */}
                {(i.ads_sp_spend || i.ads_sbv_spend || i.ads_sbc_spend) ? (
                  <div className="mt-1 flex flex-wrap gap-x-3 gap-y-0.5">
                    {([
                      ['SP', i.ads_sp_spend, i.ads_sp_net_roas],
                      ['SB Video', i.ads_sbv_spend, i.ads_sbv_net_roas],
                      ['SB Collection', i.ads_sbc_spend, i.ads_sbc_net_roas],
                    ] as [string, number | null, number | null][])
                      .filter(([, sp]) => (sp ?? 0) > 0)
                      .map(([label, sp, ro]) => (
                        <span key={label} className="text-[9px] text-faint">
                          {label} <span className="text-muted">{fM(sp ?? 0)}</span>{' '}
                          {ro != null && (
                            <span className={ro >= 1 ? 'text-emerald-400 font-semibold' : 'text-red-400 font-semibold'}>{fR(ro)}</span>
                          )}
                        </span>
                      ))}
                  </div>
                ) : null}
              </div>
            )}
            {i.terms.map(t => (
              <div key={t.term} className="flex items-center gap-2 text-[10px]">
                <span className="text-subtle truncate max-w-[210px]" title={t.term}>{t.term}</span>
                <span className="ml-auto text-[9px] text-faint tabular-nums whitespace-nowrap">
                  rank {t.rank ?? '—'} · fit {t.fit ?? '—'} · {fShort(t.demand ?? 0)} demand
                  {t.term_spend ? (
                    <>
                      {' · '}<span className="text-muted">{fM(t.term_spend)}</span>
                      {(t.term_clicks ?? 0) > 0 && (
                        <span className="text-faint"> · {fM(t.term_spend / t.term_clicks!)} cpc</span>
                      )}
                      {t.term_net_roas != null && (
                        <span className={t.term_net_roas >= 1 ? 'text-emerald-400 font-semibold' : 'text-red-400 font-semibold'}>
                          {' '}{fR(t.term_net_roas)}
                        </span>
                      )}
                    </>
                  ) : <span className="text-faint"> · no ads</span>}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="mb-4 border border-border/30 rounded-lg overflow-hidden bg-white/[0.01]">
      <div className="px-4 py-2.5 bg-white/[0.02] border-b border-border/20 flex items-center gap-2">
        <span className="text-sm font-bold text-heading">🧭 Intents</span>
        <span className="text-[10px] text-muted">
          {selectedProduct} · {intents.length} relevant · ≤10 keywords each · one campaign per match-type × intent
        </span>
      </div>
      <div className="p-3 grid grid-cols-1 md:grid-cols-2 gap-3">
        <div>
          <div className="text-[9px] text-faint uppercase tracking-wide mb-1">Generic ({generic.length})</div>
          <div className="flex flex-col gap-1">{generic.map(row)}</div>
        </div>
        <div>
          <div className="text-[9px] text-faint uppercase tracking-wide mb-1">Seasonal ({seasonal.length})</div>
          <div className="flex flex-col gap-1">{seasonal.map(row)}</div>
        </div>
      </div>
    </div>
  );
}
