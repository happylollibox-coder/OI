import { useEffect, useMemo, useState } from 'react';
import { useFilters } from '../../hooks/useFilters';
import { loadAdsKpiByProduct, loadUnifiedKpiByProduct } from '../../hooks/useCubeData';
import { fM, fP, fR, fCpc, fOrd, fmt } from '../../utils';
import { useAdsWindow, AdsWindowControls } from './adsWindow';
import {
  computeKpis,
  daysInRange,
  applyDailyAverage,
  type AdsKpiProductRow,
  type UnifiedKpiProductRow,
} from './adsKpiPanel.helpers';

type ViewMode = 'total' | 'daily';
const MODE_KEY = 'ads_kpi_mode';

type Color = 'green' | 'red' | 'muted' | undefined;
type CardDef = { label: string; value: string; color?: Color };
const COLOR: Record<string, string> = {
  green: 'text-emerald-400',
  red: 'text-red-400',
  muted: 'text-subtle',
};

function Stat({ label, value, color }: { label: string; value: string; color?: Color }) {
  return (
    <div className="bg-card border border-border rounded-lg px-3 py-2.5 backdrop-blur-xl">
      <div className="text-[10px] font-medium text-subtle uppercase tracking-wider mb-1 truncate">{label}</div>
      <div className={`font-mono text-[18px] font-bold tracking-tight leading-none truncate ${color ? COLOR[color] : 'text-text'}`}>
        {value}
      </div>
    </div>
  );
}

export function AdsKpiPanel() {
  const { filters } = useFilters();
  const { start, end, incomplete } = useAdsWindow();
  const [mode, setMode] = useState<ViewMode>(() => {
    try { return localStorage.getItem(MODE_KEY) === 'daily' ? 'daily' : 'total'; } catch { return 'total'; }
  });
  const [ads, setAds] = useState<AdsKpiProductRow[]>([]);
  const [unified, setUnified] = useState<UnifiedKpiProductRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    try { localStorage.setItem(MODE_KEY, mode); } catch { /* ignore */ }
  }, [mode]);

  useEffect(() => {
    // Custom preset with an incomplete range: wait for both dates.
    if (incomplete) return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    Promise.all([loadAdsKpiByProduct(start, end), loadUnifiedKpiByProduct(start, end)])
      .then(([a, u]) => { if (!cancelled) { setAds(a); setUnified(u); } })
      .catch(e => { if (!cancelled) setError(String(e?.message || e)); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [start, end, incomplete]);

  const k = useMemo(() => {
    const base = computeKpis(ads, unified, { family: filters.family, product: filters.product });
    return mode === 'daily' ? applyDailyAverage(base, daysInRange(start, end)) : base;
  }, [ads, unified, filters.family, filters.product, mode, start, end]);

  // First section = business / total (non-Ads) KPIs. Second = ad-attributed KPIs
  // (the "Ads" prefix marks them, matching the app convention / trend-chart toggles).
  const businessCards: CardDef[] = [
    { label: 'Net Profit', value: fM(k.totalNetProfit), color: k.totalNetProfit >= 0 ? 'green' : 'red' },
    { label: 'Units', value: fmt(k.units) },
    { label: 'TACOS', value: fP(k.tacos) },
    { label: 'Profit / unit', value: fM(k.profitPerUnit), color: k.profitPerUnit >= 0 ? 'green' : 'red' },
    { label: 'PPC / unit', value: fM(k.ppcPerUnit) },
    { label: 'Best Child', value: k.bestChild ? `${k.bestChild.name} · ${fM(k.bestChild.netProfit)}` : '--', color: 'green' },
  ];

  const adsCards: CardDef[] = [
    { label: 'Ads Spend', value: fM(k.spend) },
    { label: 'Ads Sales', value: fM(k.sales) },
    { label: 'Ads Orders', value: fOrd(k.orders) },
    { label: 'Ads Impressions', value: fmt(k.impressions) },
    { label: 'Ads Clicks', value: fmt(k.clicks) },
    { label: 'Ads ROAS', value: fR(k.roas), color: k.roas >= 1 ? 'green' : 'red' },
    { label: 'ACOS', value: fP(k.acos) },
    { label: 'Ads CPC', value: fCpc(k.cpc) },
    { label: 'Ads CVR', value: fP(k.cvr) },
    { label: 'Ads CTR', value: fP(k.ctr) },
    { label: 'Ads Net Profit', value: fM(k.netProfit), color: k.netProfit >= 0 ? 'green' : 'red' },
    { label: 'Ads Net ROAS', value: fR(k.netRoas), color: k.netRoas >= 1 ? 'green' : 'red' },
    { label: 'Ads Spend Share', value: fP(k.spendSharePct) },
  ];

  return (
    <div className="mb-5">
      {/* Date-range selector — shared with the Strategy page (see AdsWindowControls) */}
      <AdsWindowControls
        right={
          <>
            {/* Total vs per-day average */}
            <div className="inline-flex rounded-lg border border-border overflow-hidden">
              {(['total', 'daily'] as ViewMode[]).map(m => (
                <button
                  key={m}
                  onClick={() => setMode(m)}
                  className={`px-2.5 py-1 text-[11px] font-semibold transition-all ${
                    mode === m ? 'bg-blue-500/15 text-blue-400' : 'text-faint hover:text-muted'
                  }`}
                >
                  {m === 'total' ? 'Total' : 'Daily avg'}
                </button>
              ))}
            </div>
            <span className="text-[10px] font-mono text-faint">
              {loading ? 'Loading…' : `${start} → ${end}`}
            </span>
          </>
        }
      />

      {error ? (
        <div className="text-[12px] text-red-400 px-3 py-2 rounded-lg bg-red-500/10 border border-red-500/20">
          Failed to load KPIs: {error}
        </div>
      ) : (
        <div className={`transition-opacity ${loading ? 'opacity-50' : 'opacity-100'}`}>
          <div className="text-[10px] uppercase font-bold tracking-wider text-faint mb-1.5">Business</div>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-2">
            {businessCards.map(c => (
              <Stat key={c.label} label={c.label} value={c.value} color={c.color} />
            ))}
          </div>
          <div className="text-[10px] uppercase font-bold tracking-wider text-faint mt-3 mb-1.5">Ads</div>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-2">
            {adsCards.map(c => (
              <Stat key={c.label} label={c.label} value={c.value} color={c.color} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
