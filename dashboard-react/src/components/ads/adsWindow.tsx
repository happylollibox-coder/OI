import { createContext, useContext, useState, useEffect, useMemo, type ReactNode, type Dispatch, type SetStateAction } from 'react';
import { resolveDateRange, type DateRangePreset } from './adsKpiPanel.helpers';

export interface AdsRangeState {
  preset: DateRangePreset;
  customStart: string;
  customEnd: string;
}

const DEFAULT_STORAGE_KEY = 'ads_kpi_range';

function loadRange(storageKey: string, defaultPreset: DateRangePreset): AdsRangeState {
  try {
    const raw = localStorage.getItem(storageKey);
    if (raw) return JSON.parse(raw) as AdsRangeState;
  } catch { /* ignore */ }
  return { preset: defaultPreset, customStart: '', customEnd: '' };
}

interface AdsWindowCtx {
  range: AdsRangeState;
  setRange: Dispatch<SetStateAction<AdsRangeState>>;
  start: string;
  end: string;
  /** true while a custom range is incomplete — consumers should skip fetching. */
  incomplete: boolean;
}

const Ctx = createContext<AdsWindowCtx | null>(null);

/** Shared date window for the Ads-page KPI cards + campaign drill-down, and for the Strategy page.
 *
 * `storageKey` is per-page on purpose: each page persists its own window, so changing the window on
 * Ads does not silently re-scope Strategy behind the user's back. Pass the same key to share one. */
export function AdsWindowProvider({ children, storageKey = DEFAULT_STORAGE_KEY, defaultPreset = '7d' }: {
  children: ReactNode; storageKey?: string; defaultPreset?: DateRangePreset;
}) {
  const [range, setRange] = useState<AdsRangeState>(() => loadRange(storageKey, defaultPreset));
  useEffect(() => {
    try { localStorage.setItem(storageKey, JSON.stringify(range)); } catch { /* ignore */ }
  }, [range, storageKey]);

  const [start, end] = useMemo(
    () => resolveDateRange(range.preset, new Date(), range.customStart, range.customEnd),
    [range.preset, range.customStart, range.customEnd],
  );
  const incomplete = range.preset === 'custom' && (!range.customStart || !range.customEnd);

  const value = useMemo(() => ({ range, setRange, start, end, incomplete }), [range, start, end, incomplete]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAdsWindow(): AdsWindowCtx {
  const c = useContext(Ctx);
  if (!c) throw new Error('useAdsWindow must be used within AdsWindowProvider');
  return c;
}

const PRESET_LABEL: Record<DateRangePreset, string> = {
  lifetime: 'Lifetime', yesterday: 'Yesterday', '7d': '7 days', '30d': '30 days', custom: 'Custom',
};
/** What the Ads page offers. The Strategy page prepends 'lifetime'. */
export const ADS_PRESETS: DateRangePreset[] = ['yesterday', '7d', '30d', 'custom'];

/** The WINDOW preset row + custom date inputs. Extracted from AdsKpiPanel so the Ads and Strategy
 * pages render the identical control; `presets` varies only in which options are offered. */
export function AdsWindowControls({ presets = ADS_PRESETS, right }: {
  presets?: DateRangePreset[]; right?: ReactNode;
}) {
  const { range, setRange } = useAdsWindow();
  return (
    <div className="flex flex-wrap items-center gap-2 mb-2.5">
      <span className="text-[10px] uppercase font-bold tracking-wider text-faint mr-1">Window</span>
      {presets.map(p => (
        <button
          key={p}
          onClick={() => setRange(r => ({ ...r, preset: p }))}
          className={`px-2.5 py-1 rounded-lg text-[11px] font-semibold border transition-all ${
            range.preset === p
              ? 'bg-blue-500/15 text-blue-400 border-blue-500/30'
              : 'text-faint border-border hover:text-muted hover:border-border-strong'
          }`}
        >
          {PRESET_LABEL[p]}
        </button>
      ))}
      {range.preset === 'custom' && (
        <span className="flex items-center gap-1.5">
          <input
            type="date"
            value={range.customStart}
            max={range.customEnd || undefined}
            onChange={e => setRange(r => ({ ...r, customStart: e.target.value }))}
            className="px-2 py-1 rounded-lg text-[11px] font-mono bg-transparent border border-border text-subtle focus:outline-none focus:border-blue-500"
          />
          <span className="text-faint text-[11px]">→</span>
          <input
            type="date"
            value={range.customEnd}
            min={range.customStart || undefined}
            onChange={e => setRange(r => ({ ...r, customEnd: e.target.value }))}
            className="px-2 py-1 rounded-lg text-[11px] font-mono bg-transparent border border-border text-subtle focus:outline-none focus:border-blue-500"
          />
        </span>
      )}
      {right && <div className="ml-auto flex items-center gap-2">{right}</div>}
    </div>
  );
}
