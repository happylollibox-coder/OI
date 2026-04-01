import { createContext, useContext, useState, useEffect, type ReactNode } from 'react';
import { ChevronRight } from 'lucide-react';

/** A single metric pill in the summary bar */
export interface PageSummaryItem {
  label: string;
  value: string;
  color?: 'green' | 'red' | 'amber' | 'blue' | 'purple' | 'muted';
}

/** A breadcrumb segment */
export interface Breadcrumb {
  label: string;
  onClick?: () => void;
}

/** Config a page provides to describe its summary */
export interface PageSummaryConfig {
  title: string;
  items: PageSummaryItem[];
  breadcrumbs?: Breadcrumb[];
}

// ─── Context ────────────────────────────────────────────────────────────────
const PageSummaryCtx = createContext<{
  config: PageSummaryConfig | null;
  setConfig: (c: PageSummaryConfig) => void;
}>({ config: null, setConfig: () => {} });

export function PageSummaryProvider({ children }: { children: ReactNode }) {
  const [config, setConfig] = useState<PageSummaryConfig | null>(null);
  return (
    <PageSummaryCtx.Provider value={{ config, setConfig }}>
      {children}
    </PageSummaryCtx.Provider>
  );
}

/** Call from inside a page to push summary config to the bar */
export function usePageSummary(config: PageSummaryConfig) {
  const { setConfig } = useContext(PageSummaryCtx);
  const key = JSON.stringify(config);
  useEffect(() => { setConfig(config); }, [key]);
}

// ─── Color map ──────────────────────────────────────────────────────────────
const COLOR: Record<string, string> = {
  green: 'text-emerald-400',
  red: 'text-red-400',
  amber: 'text-amber-400',
  blue: 'text-blue-400',
  purple: 'text-purple-400',
  muted: 'text-muted',
};

// ─── Bar component ──────────────────────────────────────────────────────────
export function PageSummaryBar() {
  const { config } = useContext(PageSummaryCtx);
  if (!config || (!config.items.length && !config.breadcrumbs?.length)) return null;

  const crumbs = config.breadcrumbs || [{ label: config.title }];

  return (
    <div className="sticky top-[46px] z-[9] flex items-center gap-3 px-3 py-1.5 mb-3 rounded-lg bg-surface/80 border border-border-faint backdrop-blur-lg text-[11px]">
      {/* Breadcrumbs */}
      <div className="flex items-center gap-1 shrink-0">
        {crumbs.map((crumb, i) => (
          <span key={i} className="flex items-center gap-1">
            {i > 0 && <ChevronRight size={10} className="text-border-strong" />}
            {crumb.onClick ? (
              <button onClick={crumb.onClick} className="text-[9px] uppercase font-bold tracking-wider text-faint hover:text-blue-400 transition-colors">
                {crumb.label}
              </button>
            ) : (
              <span className="text-[9px] uppercase font-bold tracking-wider text-faint">
                {crumb.label}
              </span>
            )}
          </span>
        ))}
      </div>

      {/* KPI items */}
      {config.items.length > 0 && (
        <>
          <div className="w-px h-3.5 bg-border" />
          {config.items.map((item, i) => (
            <div key={i} className="flex items-center gap-1.5">
              <span className="text-subtle">{item.label}</span>
              <span className={`font-semibold font-mono ${item.color ? COLOR[item.color] || '' : 'text-text'}`}>
                {item.value}
              </span>
              {i < config.items.length - 1 && <span className="text-border-strong ml-1">·</span>}
            </div>
          ))}
        </>
      )}
    </div>
  );
}
