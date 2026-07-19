import { createContext, useContext, useState, useEffect, useMemo, type ReactNode, type Dispatch, type SetStateAction } from 'react';
import { resolveDateRange, type DateRangePreset } from './adsKpiPanel.helpers';

export interface AdsRangeState {
  preset: DateRangePreset;
  customStart: string;
  customEnd: string;
}

const STORAGE_KEY = 'ads_kpi_range';

function loadRange(): AdsRangeState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw) as AdsRangeState;
  } catch { /* ignore */ }
  return { preset: '7d', customStart: '', customEnd: '' };
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

/** Shared date window for the Ads-page KPI cards + campaign drill-down. */
export function AdsWindowProvider({ children }: { children: ReactNode }) {
  const [range, setRange] = useState<AdsRangeState>(loadRange);
  useEffect(() => {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(range)); } catch { /* ignore */ }
  }, [range]);

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
