import { useState, useRef, useEffect } from 'react';
import type { DashboardData, FamilyName, PageId } from '../types';
import { FAMILIES } from '../types';
import { useFilters, useFilterOptions, PERIOD_TREND_DEFAULT, type PeriodMode, type PeriodType, type PeriodOption } from '../hooks/useFilters';
import { weekRangeLabel, addDays, periodDateRange } from '../utils';
import { SEASONALITY_OPTIONS, type AdsSeasonality } from '../seasonality';
import { X, Filter, ChevronDown, Search } from 'lucide-react';

const PERIOD_LABELS: Record<PeriodMode, string> = { date: 'Day', weeks: 'Weeks', month: 'Month', quarter: 'Quarter', year: 'Year' };
const PERIOD_TYPE_LABELS: Record<PeriodType, string> = { regular: 'Regular', cumulative: 'Cumulative', peak: 'Peak' };
const FAMILY_LABELS: Record<FamilyName, string> = { Lollibox: 'Lollibox', LolliME: 'LolliME', Bottle: 'Bottle', Fresh: 'Fresh', Bunny: 'Bunny', LolliBall: 'LolliBall' };
const PERIOD_TREND_MAX = 36;

export function FilterBar({ data, page }: { data: DashboardData; page?: PageId }) {
  const { filters, setFilter, setFilters, resetFilters, activeCount } = useFilters();
  const performanceMaxDate = data._meta?.data_freshness?.performance_max_date || '';
  const options = useFilterOptions(data, filters, performanceMaxDate || undefined);
  const [showTier2, setShowTier2] = useState(false);

  // Count active Tier 2 filters (Experiment, Keyword, Seasonality)
  const tier2Count = [filters.experiment, filters.keyword, filters.seasonality].filter(Boolean).length;

  return (
    <div className="sticky top-0 z-50 mb-4 space-y-0">
      {/* ── Tier 1: Core filters (always visible) ── */}
      <div className="flex items-center gap-2.5 px-2 py-2 rounded-xl bg-overlay border border-border backdrop-blur-xl shadow-float">
        <div className="flex items-center gap-1 pl-2 text-faint">
          <Filter size={12} />
          <span className="text-[9px] uppercase font-semibold tracking-wider">Filters</span>
        </div>

        {/* Parent / Family */}
        <Dropdown
          label="Parent"
          value={filters.family ? FAMILY_LABELS[filters.family] : null}
          color={filters.family ? FAMILIES[filters.family].color : undefined}
          onClear={() => setFilter('family', null)}
        >
          {options.families.map(f => (
            <DropItem key={f} active={filters.family === f} onClick={() => setFilter('family', f)}>
              <span className="inline-block w-2 h-2 rounded-full mr-1.5" style={{ background: FAMILIES[f].color }} />
              {FAMILY_LABELS[f]}
            </DropItem>
          ))}
        </Dropdown>

        {/* Product / ASIN */}
        {(true) && (
          <Dropdown
            label="Product"
            value={filters.product ? options.products.find(p => p.asin === filters.product)?.name || filters.product.slice(0, 10) : null}
            onClear={() => setFilter('product', null)}
          >
            {options.products.map(p => (
              <DropItem key={p.asin} active={filters.product === p.asin} onClick={() => setFilter('product', p.asin)}>
                <span className="truncate">{p.name}</span>
                <span className="ml-auto text-[9px] text-faint font-mono pl-2">{p.orders} ord</span>
              </DropItem>
            ))}
          </Dropdown>
        )}

        <div className="w-px h-5 bg-border mx-0.5" />

        {/* Period Mode — Day only shown on Ads page */}
        <div className="flex items-center bg-inset rounded-lg border border-border">
          {(page === 'ads' ? ['date', 'weeks', 'month', 'quarter', 'year'] as PeriodMode[] : ['weeks', 'month', 'quarter', 'year'] as PeriodMode[]).map(m => (
            <button key={m} onClick={() => {
              setFilter('periodMode', m);
              setFilter('specificPeriod', null);
            }}
              className={`px-2.5 py-1 text-[10px] font-semibold rounded-lg transition-all ${
                filters.periodMode === m ? 'bg-blue-500/15 text-blue-400' : 'text-faint hover:text-muted'
              }`}>
              {PERIOD_LABELS[m]}
            </button>
          ))}
        </div>

        {/* Period Type — Regular / Cumulative / Peak */}
        <div className="flex items-center bg-inset rounded-lg border border-border">
          {(['regular', 'cumulative', 'peak'] as PeriodType[]).map(pt => (
            <button key={pt} onClick={() => setFilter('periodType', pt)}
              className={`px-2 py-1 text-[10px] font-semibold rounded-lg transition-all ${
                filters.periodType === pt ? 'bg-amber-500/15 text-amber-400' : 'text-faint hover:text-muted'
              }`}>
              {PERIOD_TYPE_LABELS[pt]}
            </button>
          ))}
        </div>

        {/* Period — Calendar input for Day mode, dropdown for others */}
        {filters.periodMode === 'date' ? (
          <div className="flex items-center bg-inset rounded-lg border border-border gap-1 px-2 py-0.5">
            <span className="text-[9px] text-faint uppercase tracking-wider">Day:</span>
            <input
              type="date"
              value={filters.specificPeriod || ''}
              onChange={e => setFilter('specificPeriod', e.target.value || null)}
              className="bg-transparent text-[10px] font-mono font-semibold text-subtle border-0 outline-none cursor-pointer appearance-none w-[105px] [color-scheme:dark]"
            />
            {filters.specificPeriod && (
              <button onClick={() => setFilter('specificPeriod', null)} className="text-faint hover:text-muted">
                <X size={10} />
              </button>
            )}
          </div>
        ) : (
          <PeriodDropdown filters={filters} options={options} setFilters={setFilters} periodType={filters.periodType} />
        )}

        {/* Trend count */}
        <div className="flex items-center bg-inset rounded-lg border border-border gap-1 px-2 py-0.5">
          <span className="text-[9px] text-faint uppercase tracking-wider">Trend:</span>
          <select
            value={filters.periodTrend}
            onChange={e => setFilter('periodTrend', parseInt(e.target.value, 10))}
            className="px-1.5 py-0.5 text-[10px] font-mono font-semibold rounded-md bg-transparent border border-border text-subtle hover:border-border-strong focus:outline-none focus:border-blue-500 appearance-none cursor-pointer"
          >
            {Array.from({ length: PERIOD_TREND_MAX }, (_, i) => i + 1).map(n => (
              <option key={n} value={n}>{n}{n === PERIOD_TREND_DEFAULT ? '*' : ''}</option>
            ))}
          </select>
        </div>

        <div className="flex-1" />

        {/* +More Filters toggle */}
        <button
          onClick={() => setShowTier2(!showTier2)}
          className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[10px] font-semibold border transition-all ${
            showTier2 || tier2Count > 0
              ? 'bg-violet-500/10 text-violet-400 border-violet-500/20'
              : 'text-faint border-border hover:text-muted hover:border-border'
          }`}
        >
          <Filter size={10} />
          {showTier2 ? 'Less' : '+More'}
          {tier2Count > 0 && (
            <span className="ml-0.5 px-1.5 py-0.5 rounded-full bg-violet-500/20 text-violet-300 text-[9px] font-bold leading-none">
              {tier2Count}
            </span>
          )}
        </button>

        {/* Active filter count + reset */}
        {activeCount > 0 && (
          <button onClick={resetFilters}
            className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-inset text-[10px] text-faint hover:text-muted transition-colors border border-border">
            <X size={10} />
            Clear {activeCount}
          </button>
        )}
      </div>

      {/* ── Tier 2: Advanced filters (collapsible) ── */}
      {showTier2 && (
        <div className="flex items-center gap-2.5 px-2 py-2 mt-1 rounded-xl bg-overlay border border-border backdrop-blur-xl shadow-float animate-in">


          {/* Seasonality — only when peak data exists */}
          {data.peak?.[0]?.peak_start && (
            <Dropdown
              label="Seasonality"
              value={filters.seasonality ? SEASONALITY_OPTIONS.find(o => o.value === filters.seasonality)?.label ?? filters.seasonality : null}
              onClear={() => setFilter('seasonality', null)}
            >
              {SEASONALITY_OPTIONS.map(o => (
                <DropItem key={o.value} active={filters.seasonality === o.value} onClick={() => setFilter('seasonality', o.value as AdsSeasonality)}>
                  {o.label}
                </DropItem>
              ))}
            </Dropdown>
          )}

          <div className="w-px h-5 bg-border mx-0.5" />

          {/* Experiment */}
          <Dropdown
            label="Experiment"
            value={filters.experiment ? options.experiments.find(e => e.id === filters.experiment)?.name || filters.experiment : null}
            onClear={() => setFilter('experiment', null)}
            searchable
          >
            {options.experiments.map(e => (
              <DropItem key={e.id} active={filters.experiment === e.id} onClick={() => setFilter('experiment', e.id)}>
                <span className="truncate">{e.name}</span>
                <span className={`ml-auto text-[9px] font-mono pl-2 ${e.status === 'ACTIVE' ? 'text-emerald-400' : 'text-faint'}`}>{e.status.toLowerCase()}</span>
              </DropItem>
            ))}
          </Dropdown>

          {/* Keyword */}
          <Dropdown
            label="Keyword"
            value={filters.keyword}
            onClear={() => setFilter('keyword', null)}
            searchable
          >
            {options.keywords.map(k => (
              <DropItem key={k.term} active={filters.keyword === k.term} onClick={() => setFilter('keyword', k.term)}>
                <span className="truncate">{k.term}</span>
                <span className="ml-auto text-[9px] text-faint font-mono pl-2">{k.orders} ord</span>
              </DropItem>
            ))}
          </Dropdown>
        </div>
      )}

      {/* ── Active Tier 2 chips (shown when Tier 2 is collapsed but filters are active) ── */}
      {!showTier2 && tier2Count > 0 && (
        <div className="flex items-center gap-1.5 px-2 pt-1.5">
          {filters.experiment && (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-violet-500/10 border border-violet-500/20 text-[10px] text-violet-400">
              Exp: {options.experiments.find(e => e.id === filters.experiment)?.name?.slice(0, 20) || filters.experiment.slice(0, 10)}
              <X size={10} className="cursor-pointer opacity-60 hover:opacity-100" onClick={() => setFilter('experiment', null)} />
            </span>
          )}
          {filters.keyword && (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-violet-500/10 border border-violet-500/20 text-[10px] text-violet-400">
              KW: {filters.keyword.slice(0, 20)}
              <X size={10} className="cursor-pointer opacity-60 hover:opacity-100" onClick={() => setFilter('keyword', null)} />
            </span>
          )}
          {filters.seasonality && (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-violet-500/10 border border-violet-500/20 text-[10px] text-violet-400">
              {SEASONALITY_OPTIONS.find(o => o.value === filters.seasonality)?.label ?? filters.seasonality}
              <X size={10} className="cursor-pointer opacity-60 hover:opacity-100" onClick={() => setFilter('seasonality', null)} />
            </span>
          )}
        </div>
      )}
    </div>
  );
}

/* ─── Period dropdown ─── */

/** Format a short date like "May 12" */
function fmtShort(iso: string): string {
  if (!iso) return '';
  return new Date(iso + 'T12:00:00Z').toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
}

/** Build the date-range string used by a period for filtering, shown on hover */
function periodFilterRange(periodValue: string, mode: PeriodMode, dataMaxDate?: string): string {
  const range = periodDateRange(periodValue, mode);
  if (!range) return '';
  // Guard against reversed range (data hasn't reached this period yet)
  if (dataMaxDate && dataMaxDate < range.start) return `${fmtShort(range.start)} – ${fmtShort(range.end)}`;
  const end = dataMaxDate && dataMaxDate < range.end ? dataMaxDate : range.end;
  return `${fmtShort(range.start)} – ${fmtShort(end)}`;
}

/** Build a current-period label that caps the end date at dataMaxDate */
function currentPeriodLabel(periodValue: string, mode: PeriodMode, dataMaxDate?: string): string {
  if (mode === 'weeks') {
    const weekEnd = addDays(periodValue, 6);
    // Guard against reversed range (data hasn't reached this period yet)
    if (dataMaxDate && dataMaxDate < periodValue) return `${fmtShort(periodValue)} – ${fmtShort(weekEnd)}`;
    const end = dataMaxDate && dataMaxDate < weekEnd ? dataMaxDate : weekEnd;
    return `${fmtShort(periodValue)} – ${fmtShort(end)}`;
  }
  if (mode === 'month') {
    // Show "2026-05 (May 1 – May 12)"
    const range = periodDateRange(periodValue + '-01' > periodValue ? periodValue : periodValue, mode);
    if (!range) return periodValue;
    const end = dataMaxDate && dataMaxDate < range.end ? dataMaxDate : range.end;
    return `${periodValue} (${fmtShort(range.start)} – ${fmtShort(end)})`;
  }
  return periodValue;
}

function PeriodDropdown({ filters, options, setFilters, periodType }: {
  filters: { specificPeriod: string | null; periodMode: PeriodMode };
  options: { periods: string[]; periodsEnriched: PeriodOption[]; currentPeriod: PeriodOption | null; weeks: string[]; months: string[]; years: string[] };
  setFilters: (patch: { specificPeriod?: string | null }) => void;
  periodType?: PeriodType;
}) {
  const isCumulative = periodType === 'cumulative' || periodType === 'peak';
  const latestPeriod = options.periods[0];

  // In cumulative mode (month/quarter/year), show months for year selection
  const periodsEnriched = isCumulative && filters.periodMode !== 'weeks'
    ? options.months.map(m => ({ value: m, hasSqp: true }))
    : options.periodsEnriched;

  const latestLabel = isCumulative && filters.periodMode !== 'weeks'
    ? (options.months[0] || '')
    : filters.periodMode === 'weeks'
      ? (latestPeriod ? weekRangeLabel(latestPeriod) : '')
      : (latestPeriod || '');

  // For the selected period chip, show data-capped range for current period
  const currentPeriod = options.currentPeriod;
  const isCurrentSelected = filters.specificPeriod && currentPeriod && filters.specificPeriod === currentPeriod.value;

  const value = filters.specificPeriod
    ? (isCurrentSelected && filters.periodMode === 'weeks' && !isCumulative
        ? currentPeriodLabel(filters.specificPeriod, 'weeks', currentPeriod?.dataMaxDate)
        : filters.periodMode === 'weeks' && !isCumulative
          ? weekRangeLabel(filters.specificPeriod)
          : filters.specificPeriod)
    : null;

  const clearPeriod = () => setFilters({ specificPeriod: null });

  /** Format a period label with optional (missing SQP) suffix and hover tooltip */
  const periodItemLabel = (p: PeriodOption, showRange: boolean) => {
    const label = showRange ? weekRangeLabel(p.value) : p.value;
    const tooltip = periodFilterRange(p.value, filters.periodMode);
    return (
      <span title={tooltip ? `Filter: ${tooltip}` : undefined}>
        {label}
        {!p.hasSqp && <span className="ml-1.5 text-[9px] text-zinc-500 font-normal">(missing SQP)</span>}
      </span>
    );
  };

  /** Current period label — capped at data max date */
  const currentLabel = currentPeriod
    ? currentPeriodLabel(currentPeriod.value, filters.periodMode, currentPeriod.dataMaxDate)
    : null;

  /** Tooltip for current period showing actual filter dates */
  const currentTooltip = currentPeriod
    ? periodFilterRange(currentPeriod.value, filters.periodMode, currentPeriod.dataMaxDate)
    : '';

  return (
    <Dropdown
      label={isCumulative ? 'Cumulative To' : 'Period'}
      value={value}
      placeholder={latestLabel || 'Period'}
      onClear={clearPeriod}
      tooltip={filters.specificPeriod
        ? `Filter: ${periodFilterRange(filters.specificPeriod, filters.periodMode, isCurrentSelected ? currentPeriod?.dataMaxDate : undefined)}`
        : undefined}
    >
      {currentPeriod && (
        <DropItem
          active={filters.specificPeriod === currentPeriod.value}
          onClick={() => setFilters({ specificPeriod: currentPeriod.value })}
        >
          <span className="flex items-center gap-1" title={currentTooltip ? `Filter: ${currentTooltip}` : undefined}>
            <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />
            Current – {currentLabel}
            <span className="text-[9px] text-amber-400/70 font-normal">(thru data)</span>
            {!currentPeriod.hasSqp && <span className="text-[9px] text-zinc-500 font-normal">(missing SQP)</span>}
          </span>
        </DropItem>
      )}
      {periodsEnriched.map(p => (
        <DropItem
          key={p.value}
          active={filters.specificPeriod === p.value}
          onClick={() => setFilters({ specificPeriod: p.value })}
        >
          {periodItemLabel(p, filters.periodMode === 'weeks' && !isCumulative)}
        </DropItem>
      ))}
    </Dropdown>
  );
}

/* ─── Dropdown primitives ─── */

function Dropdown({ label, value, placeholder, color, onClear, searchable, tooltip, children }: {
  label: string; value: string | null; placeholder?: string; color?: string;
  onClear: () => void; searchable?: boolean; tooltip?: string; children: React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  useEffect(() => { if (!open) setSearch(''); }, [open]);

  const filtered = searchable && search
    ? filterChildren(children, search)
    : children;

  return (
    <div ref={ref} className="relative">
      <button onClick={() => setOpen(!open)}
        title={tooltip || undefined}
        className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[10px] font-semibold border transition-all max-w-[220px] ${
          value ? 'bg-blue-500/10 text-blue-400 border-blue-500/20' : 'text-faint border-border hover:border-zinc-700 hover:text-muted'
        }`}>
        <span className="uppercase tracking-wider text-[9px] opacity-60 mr-0.5">{label}:</span>
        <span className="truncate" style={color ? { color } : undefined}>{value || placeholder || 'All'}</span>
        {value ? (
          <X size={10} className="shrink-0 opacity-60 hover:opacity-100" onClick={e => { e.stopPropagation(); onClear(); }} />
        ) : (
          <ChevronDown size={10} className="shrink-0 opacity-40" />
        )}
      </button>

      {open && (
        <div className="absolute top-full left-0 mt-1 z-[100] min-w-[220px] max-h-[320px] overflow-y-auto rounded-xl bg-card border border-border shadow-2xl py-1">
          {searchable && (
            <div className="px-2 py-1.5 border-b border-border">
              <div className="flex items-center gap-1.5 px-2 py-1 rounded-lg bg-inset border border-border">
                <Search size={10} className="text-faint shrink-0" />
                <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search..."
                  autoFocus
                  className="bg-transparent text-[11px] text-[var(--color-text)] outline-none w-full placeholder:text-zinc-600" />
              </div>
            </div>
          )}
          <div onClick={() => setOpen(false)}>
            {filtered}
          </div>
        </div>
      )}
    </div>
  );
}

function DropItem({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button onClick={onClick}
      className={`w-full flex items-center px-3 py-1.5 text-[11px] text-left transition-colors ${
        active ? 'bg-blue-500/10 text-blue-400' : 'text-zinc-300 hover:bg-white/[.04]'
      }`}>
      {children}
    </button>
  );
}

function filterChildren(children: React.ReactNode, search: string): React.ReactNode {
  const lc = search.toLowerCase();
  const arr = Array.isArray(children) ? children : [children];
  return arr.filter((child: any) => {
    if (!child?.props?.children) return true;
    const text = extractText(child.props.children);
    return text.toLowerCase().includes(lc);
  });
}

function extractText(node: React.ReactNode): string {
  if (typeof node === 'string') return node;
  if (typeof node === 'number') return String(node);
  if (Array.isArray(node)) return node.map(extractText).join('');
  if (node && typeof node === 'object' && 'props' in node) return extractText((node as any).props.children);
  return '';
}
