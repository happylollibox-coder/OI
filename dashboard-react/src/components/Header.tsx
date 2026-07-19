import { useMemo } from 'react';
import { Eye, EyeOff } from 'lucide-react';
import type { DashboardData } from '../types';
import { formatDateRange, weekRangeLabel, latestSqpWeek } from '../utils';
import { useViewMode } from '../hooks/useViewMode';

// onNav is kept in the prop type for call-site compatibility but is no longer used
// here (the action-bucket pills that linked to the Actions page were removed).
export function Header({ data }: { data: DashboardData; onNav?: (page: string) => void }) {
  const { isAdmin, toggle: toggleViewMode } = useViewMode();
  const meta = data._meta || {};
  const refreshed = meta.refreshed_at ? new Date(meta.refreshed_at) : null;
  const isCubeLive = meta.cube_source === 'live';
  const dr = data._meta?.date_ranges?.summary_7d;
  const rangeStr = formatDateRange(dr?.start, dr?.end);

  /* ─── Data freshness ──────────────────────────────────────── */
  const freshness = useMemo(() => {
    const sqpLast = latestSqpWeek(data.sqp_weekly || []);
    const df = meta.data_freshness;
    const fmtDate = (iso: string) => new Date(iso + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric' });

    let adsLabel: string | null = null;
    let perfLabel: string | null = null;

    if (df?.ads_max_date) {
      adsLabel = fmtDate(df.ads_max_date);
    } else {
      const wt = data.weekly_trends || [];
      const maxAds = wt.filter(r => (r.ad_cost || 0) > 0).map(r => r.week_start || '').filter(Boolean).sort().pop();
      if (maxAds) { const d = new Date(maxAds + 'T00:00:00'); d.setDate(d.getDate() + 6); adsLabel = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }); }
    }

    if (df?.performance_max_date) {
      perfLabel = fmtDate(df.performance_max_date);
    } else {
      const wt = data.weekly_trends || [];
      const maxPerf = wt.filter(r => (r.sales || 0) > 0).map(r => r.week_start || '').filter(Boolean).sort().pop();
      if (maxPerf) { const d = new Date(maxPerf + 'T00:00:00'); d.setDate(d.getDate() + 6); perfLabel = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }); }
    }

    return {
      sqp: sqpLast ? weekRangeLabel(sqpLast) : null,
      ads: adsLabel ? 'thru ' + adsLabel : null,
      perf: perfLabel ? 'thru ' + perfLabel : null,
    };
  }, [data.sqp_weekly, data.weekly_trends, meta]);

  return (
    <header className="fixed top-0 left-0 right-0 h-14 bg-overlay backdrop-blur-2xl border-b border-border flex items-center px-5 gap-4 z-50">
      <div className="flex items-center gap-2.5 font-bold text-sm tracking-tight whitespace-nowrap shrink-0">
        <div className="w-2.5 h-2.5 rounded-full bg-gradient-to-br from-purple-500 to-blue-500 shadow-[0_0_8px_rgba(147,51,234,0.3)]" />
        HAPPY LOLLI OI
      </div>

      {rangeStr && <span className="text-[10px] text-faint font-mono shrink-0">{rangeStr}</span>}

      <div className="flex-1" />

      <div className="flex items-center gap-2 text-[10px] text-faint font-mono whitespace-nowrap shrink-0">
        {freshness.sqp && <span>SQP: {freshness.sqp}</span>}
        {freshness.sqp && freshness.ads && <span className="text-border">|</span>}
        {freshness.ads && <span>Ads: {freshness.ads}</span>}
        {freshness.ads && freshness.perf && <span className="text-border">|</span>}
        {freshness.perf && <span>Orders: {freshness.perf}</span>}
        {(refreshed || isCubeLive) && (
          <>
            <span className="text-border">|</span>
            <span className="flex items-center gap-1">
              {isCubeLive && <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.4)]" />}
              {isCubeLive ? 'Live' : refreshed ? `Refreshed ${refreshed.toLocaleDateString()} ${refreshed.toLocaleTimeString()}` : ''}
            </span>
          </>
        )}
      </div>

      {/* View-mode toggle (moved here from the sidebar) — sits right of the Live indicator */}
      <button
        onClick={toggleViewMode}
        title={isAdmin ? 'Admin view: all pages & diagnostics. Click for simple view.' : 'Simple view: curated pages only. Click for admin view.'}
        className="flex items-center gap-1 shrink-0 text-[10px] font-semibold uppercase tracking-wider px-2 py-1 rounded-lg border border-border text-faint hover:text-muted hover:border-border-strong transition-all"
      >
        {isAdmin
          ? <Eye size={12} className="text-violet-400" />
          : <EyeOff size={12} className="text-faint" />
        }
        <span className="leading-none">{isAdmin ? 'ADMIN' : 'SIMPLE'}</span>
      </button>
    </header>
  );
}

