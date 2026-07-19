import { useEffect, useState } from 'react';
import { apiFetch } from '../../utils/apiFetch';
import { fShort, fM, fR } from '../../utils';

interface SpotTerm { term: string; rank: number | null; }
interface SpotProduct {
  product: string; family: string;
  spend: number | null; clicks: number | null; orders: number | null; net_roas: number | null;
}
interface SpotIntent {
  intent_key: string;
  label: string;
  intent_type: 'GENERIC' | 'TIME_BASED';
  cross_family: boolean;
  n_families: number;
  families: string[];
  best_rank: number | null;
  season_start: string | null;
  season_end: string | null;
  demand: number | null;
  top_terms: SpotTerm[];
  top_products: SpotProduct[] | null;   // top 3 profitable products to run in this intent
  // Brand-lane money — SB Video / SB Collection are their OWN campaigns (Ori 2026-07-16).
  // SP lives in the Intents panel and is judged there; this card is the brand lane.
  sbv_spend: number | null; sbv_clicks: number | null; sbv_net_roas: number | null;
  sbc_spend: number | null; sbc_clicks: number | null; sbc_net_roas: number | null;
}

/** Cross-family intent view — the suggestion feed for brand-store campaigns
 *  (architecture/INTENT_CAMPAIGN_MODEL.md §B.2). Intents shared by several families
 *  are the brand-store candidates. Aggregation lives in /api/research/brand-spotlight. */
export function BrandSpotlightCard() {
  const [intents, setIntents] = useState<SpotIntent[] | null>(null);
  const [open, setOpen] = useState<string | null>(null);

  useEffect(() => {
    const ctrl = new AbortController();
    apiFetch('/api/research/brand-spotlight', { signal: ctrl.signal })
      .then(r => (r.ok ? r.json() : null))
      .then(d => setIntents(d && !d.error ? d.intents : null))
      .catch(() => {});
    return () => ctrl.abort();
  }, []);

  if (!intents || intents.length === 0) return null;
  // This card is the BRAND LANE. SB Video and SB Collection are separate campaigns from the
  // SP intent campaigns (which live in the Intents panel and are judged on SP money there).
  const sbVideo = intents.filter(i => (i.sbv_spend ?? 0) > 0)
    .sort((a, b) => (b.sbv_net_roas ?? 0) - (a.sbv_net_roas ?? 0));
  const sbColl = intents.filter(i => (i.sbc_spend ?? 0) > 0)
    .sort((a, b) => (b.sbc_net_roas ?? 0) - (a.sbc_net_roas ?? 0));
  // Cross-family intents with no SB spend yet = brand-store candidates still untried.
  const candidates = intents.filter(i => i.n_families >= 2 && !(i.sbv_spend ?? 0) && !(i.sbc_spend ?? 0));

  const row = (i: SpotIntent, fmt?: 'sbv' | 'sbc') => {
    const isOpen = open === i.intent_key;
    const fSpend = fmt === 'sbv' ? i.sbv_spend : fmt === 'sbc' ? i.sbc_spend : null;
    const fRoas  = fmt === 'sbv' ? i.sbv_net_roas : fmt === 'sbc' ? i.sbc_net_roas : null;
    return (
      <div key={i.intent_key} className="border border-border/20 rounded bg-surface">
        <button
          onClick={() => setOpen(o => (o === i.intent_key ? null : i.intent_key))}
          className="w-full flex items-center gap-2 px-2 py-1.5 text-left hover:bg-white/[0.02]"
        >
          <span className={`transition-transform text-[8px] text-faint ${isOpen ? 'rotate-90' : ''}`}>▶</span>
          <span className="text-[11px] font-medium text-heading">{i.label}</span>
          {i.intent_type === 'TIME_BASED'
            ? <span className="px-1 py-0.5 rounded text-[8px] bg-amber-500/15 text-amber-400 whitespace-nowrap"
                    title="Seasonal — rank is zeroed off-season, so the season window decides when this runs">
                ⏱ {i.season_start ?? '?'} → {i.season_end ?? 'no pause date'}
              </span>
            : <span className="px-1 py-0.5 rounded text-[8px] bg-blue-500/15 text-blue-400">rank {i.best_rank}</span>}
          <span className={`px-1 py-0.5 rounded text-[8px] ${i.n_families >= 2 ? 'bg-emerald-500/15 text-emerald-400' : 'bg-white/5 text-faint'}`}>
            {i.n_families} {i.n_families === 1 ? 'family' : 'families'}
          </span>
          {i.top_products?.length ? (
            <span className="px-1 py-0.5 rounded text-[8px] bg-emerald-500/10 text-emerald-400"
                  title={`Suggested products (net ROAS >= 1): ${i.top_products.map(p => `${p.product} ${p.net_roas}x`).join(' · ')}`}>
              {i.top_products.length} product{i.top_products.length > 1 ? 's' : ''}
            </span>
          ) : (
            <span className="px-1 py-0.5 rounded text-[8px] bg-white/5 text-faint" title="No product clears breakeven on this intent's terms">no product ≥1x</span>
          )}
          <span className="ml-auto text-[9px] tabular-nums whitespace-nowrap">
            {fmt && fSpend != null ? (
              <>
                <span className="text-faint">{fM(fSpend)}</span>
                {fRoas != null && (
                  <span className={fRoas >= 1 ? ' text-emerald-400 font-semibold' : ' text-red-400 font-semibold'}>
                    {' '}{fR(fRoas)}
                  </span>
                )}
              </>
            ) : (
              <span className="text-faint">{fShort(i.demand ?? 0)} demand</span>
            )}
          </span>
        </button>
        {isOpen && (
          <div className="px-2 pb-2 pt-0.5 space-y-1">
            <div className="text-[9px] text-muted">{i.families.join(' · ')}</div>
            {/* Which products to actually advertise in this intent's campaign */}
            <div>
              <div className="text-[9px] text-faint uppercase tracking-wide">Suggested products — top net ROAS ≥ 1x</div>
              {i.top_products?.length ? (
                <div className="flex flex-col gap-0.5 mt-0.5">
                  {i.top_products.map(p => (
                    <div key={p.product} className="flex items-center gap-2 text-[10px]">
                      <span className="text-heading truncate max-w-[150px]" title={p.family}>{p.product}</span>
                      <span className="text-[8px] text-faint">{p.family}</span>
                      <span className="ml-auto text-[9px] tabular-nums text-faint">
                        {fM(p.spend ?? 0)} · {fShort(p.clicks ?? 0)} clk ·{' '}
                        <span className="text-emerald-400 font-semibold">{fR(p.net_roas ?? 0)}</span>
                      </span>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="text-[10px] text-faint italic mt-0.5">No product clears 1x net ROAS on these terms (≥20 clicks).</div>
              )}
            </div>
            <div className="flex flex-wrap gap-1">
              {i.top_terms?.map(t => (
                <span key={t.term} className="px-1 py-0.5 rounded bg-white/5 text-[9px] text-subtle" title={`rank ${t.rank}`}>
                  {t.term}
                </span>
              ))}
            </div>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="mb-4 border border-border/30 rounded-lg overflow-hidden bg-white/[0.01]">
      <div className="px-4 py-2.5 bg-white/[0.02] border-b border-border/20 flex items-center gap-2">
        <span className="text-sm font-bold text-heading">✨ Brand Spotlight</span>
        <span className="text-[10px] text-muted">
          the brand lane — SB Video + SB Collection are their own campaigns (SP lives in Intents)
        </span>
      </div>
      <div className="p-3 grid grid-cols-1 md:grid-cols-3 gap-3">
        <div>
          <div className="text-[9px] text-faint uppercase tracking-wide mb-1">
            🎬 SB Video ({sbVideo.length}) · by net ROAS
          </div>
          <div className="flex flex-col gap-1">{sbVideo.map(i => row(i, 'sbv'))}</div>
        </div>
        <div>
          <div className="text-[9px] text-faint uppercase tracking-wide mb-1">
            🏬 SB Collection ({sbColl.length}) · by net ROAS
          </div>
          <div className="flex flex-col gap-1">{sbColl.map(i => row(i, 'sbc'))}</div>
        </div>
        <div>
          <div className="text-[9px] text-faint uppercase tracking-wide mb-1">
            Brand-store candidates ({candidates.length}) · 2+ families, no SB spend yet
          </div>
          <div className="flex flex-col gap-1">{candidates.map(i => row(i))}</div>
        </div>
      </div>
    </div>
  );
}
