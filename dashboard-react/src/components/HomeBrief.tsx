/**
 * HomeBrief — the high-level, plain-language Home page brief.
 *
 * Family is the main toggle (segmented control); the date window lives inside the
 * selected family's card. Left = "what moved" (read + KPI deltas + per-product),
 * right = "needs attention". Pure display — all logic is in ../homeBrief.
 */
import { useMemo, useState } from 'react';
import type { DashboardData, FamilyName } from '../types';
import {
  buildBriefModel, formatMetric, formatDelta,
  type DateMode, type Health, type MetricDelta, type AttentionItem,
} from '../homeBrief';

const DATE_MODES: { key: DateMode; label: string }[] = [
  { key: 'today', label: 'Today · Ads' },
  { key: 'yday', label: 'Yesterday' },
  { key: '7d', label: '7 days' },
  { key: '30d', label: '30 days' },
];

const DOT: Record<Health, string> = {
  risk: 'bg-red-500', warn: 'bg-amber-500', good: 'bg-emerald-500', flat: 'bg-zinc-600',
};
// Ad spend / CPC moving isn't inherently good or bad — show those deltas in a neutral colour.
const NEUTRAL_KEYS = new Set(['ad_cost', 'cpc', 'ads_spend', 'ads_cpc']);
const metricColor = (m: MetricDelta) =>
  NEUTRAL_KEYS.has(m.key) ? 'text-muted'
  : m.dir === 'up' ? 'text-emerald-400' : m.dir === 'dn' ? 'text-red-400' : 'text-faint';
const arrowFor = (m: MetricDelta) => m.dir === 'up' ? '▲' : m.dir === 'dn' ? '▼' : '■';
const ATT_ICON: Record<AttentionItem['level'], string> = { risk: '🔴', warn: '🟠', watch: '🟡' };

const persist = (k: string, v: string) => { try { localStorage.setItem(k, v); } catch { /* ignore */ } };
const recall = (k: string, d: string) => { try { return localStorage.getItem(k) ?? d; } catch { return d; } };

// Multi-day windows are sums; a per-day toggle divides additive metrics by this many days.
const WINDOW_DAYS: Partial<Record<DateMode, number>> = { '7d': 7, '30d': 30 };

// Display-only: drop the "Lolli" prefix from family names (LolliBall → Ball, LolliME → ME).
// The underlying family key is unchanged — this only affects what's shown.
const stripLolli = (name: string) => name.replace(/^lolli/i, '') || name;

export function HomeBrief({ data, onNav, simple = false }: { data: DashboardData; onNav: (p: string, f?: FamilyName) => void; simple?: boolean }) {
  const [mode, setMode] = useState<DateMode>(() => recall('oi_brief_mode', 'yday') as DateMode);
  const [famKey, setFamKey] = useState<string>(() => recall('oi_brief_family', 'All'));
  const [perDay, setPerDay] = useState<boolean>(() => recall('oi_brief_perday', '0') === '1');

  const fresh = data._meta?.data_freshness;
  const adsMax = fresh?.ads_max_date || '';
  const perfMax = fresh?.performance_max_date || '';
  // Today is ready when ads data is a day ahead of orders (an ads-only day before orders catch up).
  const todayEnabled = !!adsMax && !!perfMax && adsMax > perfMax;
  const effMode: DateMode = mode === 'today' && !todayEnabled ? 'yday' : mode;

  const model = useMemo(() => buildBriefModel(data, effMode), [data, effMode]);

  const setModeP = (m: DateMode) => { setMode(m); persist('oi_brief_mode', m); };
  const setFamP = (f: string) => { setFamKey(f); persist('oi_brief_family', f); };
  const setPerDayP = (v: boolean) => { setPerDay(v); persist('oi_brief_perday', v ? '1' : '0'); };

  const fam = famKey === 'All' ? null : model.families.find(f => f.family === famKey) || null;

  // Per-day averaging only applies to multi-day windows; single-day modes are already daily.
  const windowDays = WINDOW_DAYS[effMode] ?? 0;
  const divisor = windowDays && perDay ? windowDays : 1;

  // Comparison caption for the card trends — reuse the "vs …" clause from the period label.
  const compareLabel = model.periodLabel.split('·').map(s => s.trim()).find(s => s.toLowerCase().startsWith('vs')) || 'vs prior period';
  // Today mode: the card's net profit is ads net profit compared against yesterday's,
  // not the 7-day average the rest of the card uses.
  const npCaption = effMode === 'today' ? 'Ads net profit · vs yesterday' : undefined;

  return (
    <div className="mb-3 bg-card border border-border rounded-lg overflow-hidden backdrop-blur-xl">
      {/* HEADER: date window (inside) + total/per-day toggle (multi-day windows only) — above the cards */}
      <div className="flex items-center gap-3 px-4 py-2.5 flex-wrap border-b border-border-faint">
        <span className="text-[15px] font-semibold text-text">{fam ? stripLolli(fam.family) : 'All families'}</span>
        <DateToggle mode={mode} todayEnabled={todayEnabled} reason={model.todayDisabledReason} onPick={setModeP} />
        <span className="text-[11px] font-mono text-faint">{model.periodLabel}</span>
        {windowDays > 0 && <PerDayToggle perDay={perDay} onPick={setPerDayP} />}
      </div>

      {/* MAIN TOGGLE: All summary on its own first row, then a card per family */}
      <div className="p-4 border-b border-border bg-white/[.015]">
        <AllCard label="All" netProfit={model.allNetProfit} unitsSold={model.allUnitsSold} convRate={model.allConvRate}
          divisor={divisor} compareLabel={compareLabel} npCaption={npCaption} active={famKey === 'All'} onClick={() => setFamP('All')} />
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4 mt-4">
          {model.families.map(f => (
            <FamilyCard key={f.family} label={stripLolli(f.family)} dot={f.health} steady={f.steady}
              netProfit={f.netProfit} unitsSold={f.unitsSold} convRate={f.convRate} divisor={divisor} compareLabel={compareLabel}
              npCaption={npCaption} active={famKey === f.family} onClick={() => setFamP(f.family)} />
          ))}
        </div>
      </div>

      {/* Simple view shows just the family cards — the What-moved / Needs-attention detail is hidden. */}
      {!simple && (fam ? <FamilyPanel view={fam} divisor={divisor} onNav={onNav} />
        : <OverviewPanel model={model} divisor={divisor} onNav={onNav} onPickFamily={setFamP} />)}
    </div>
  );
}

// Trend arrow for the family cards: ▲ above 0%, ▼ below, ■ flat.
const trendArrow = (m: MetricDelta) => m.deltaPct > 0 ? '▲' : m.deltaPct < 0 ? '▼' : '■';
// Card background tint from both measures (net profit + units trend): stronger when
// they agree (both green / both red), lighter base tint when they're mixed.
const dualTint = (npGood: boolean, uGood: boolean) =>
  npGood && uGood ? 'bg-emerald-500/[.22]'
  : !npGood && !uGood ? 'bg-red-500/[.22]'
  : npGood ? 'bg-emerald-500/[.09]' : 'bg-red-500/[.09]';
const txt = (good: boolean) => good ? 'text-emerald-500' : 'text-red-500';

type CardProps = { label: string; dot?: Health; netProfit: MetricDelta; unitsSold: MetricDelta; convRate: MetricDelta; divisor?: number; compareLabel: string; npCaption?: string; active: boolean; steady?: boolean; onClick: () => void };

// Wide "All" summary card — its own first row, laid out horizontally so it reads
// distinctly from the per-family cards below. Whole card tinted by the net-profit sign.
function AllCard({ label, netProfit, unitsSold, convRate, divisor = 1, compareLabel, npCaption, active, onClick }: CardProps) {
  return (
    <button onClick={onClick}
      className={`w-full flex items-center gap-x-8 gap-y-3 flex-wrap rounded-xl border px-5 py-4 text-left transition-all duration-200 ${dualTint(netProfit.cur > 0, unitsSold.deltaPct > 0)}
        ${active ? 'border-blue-500 shadow-md ring-1 ring-blue-500/20' : 'border-border hover:border-border-strong hover:shadow-sm'}`}>
      <div className="min-w-[110px]">
        <div className="text-[26px] font-bold uppercase tracking-wide text-text leading-none">{label}</div>
        <div className="text-[10px] uppercase tracking-wider text-faint mt-1.5">All families · {compareLabel}</div>
      </div>
      <div className="flex-1 flex items-center gap-x-8 gap-y-3 flex-wrap">
        <div>
          <div className="flex items-baseline gap-2">
            <span className={`text-[30px] font-bold font-mono leading-none tracking-tight ${txt(netProfit.cur > 0)}`}>{formatMetric(netProfit, divisor)}</span>
            <span className={`text-[14px] font-mono font-semibold ${txt(netProfit.deltaPct > 0)}`}>{trendArrow(netProfit)} {formatDelta(netProfit)}</span>
          </div>
          <div className="text-[10px] uppercase tracking-wider text-faint mt-1">{npCaption ?? 'Net profit'}</div>
        </div>
        <div className="w-px self-stretch bg-border/70 hidden sm:block" />
        <div>
          <div className="flex items-baseline gap-2">
            <span className="text-[24px] font-bold font-mono text-text leading-none tracking-tight">{formatMetric(unitsSold, divisor)}</span>
            <span className={`text-[13px] font-mono font-semibold ${txt(unitsSold.deltaPct > 0)}`}>{trendArrow(unitsSold)} {formatDelta(unitsSold)}</span>
          </div>
          <div className="text-[10px] uppercase tracking-wider text-faint mt-1">Units</div>
        </div>
        <div className="w-px self-stretch bg-border/70 hidden sm:block" />
        <div>
          <div className="flex items-baseline gap-2">
            <span className="text-[24px] font-bold font-mono text-text leading-none tracking-tight">{formatMetric(convRate)}</span>
            <span className={`text-[13px] font-mono font-semibold ${txt(convRate.deltaPct > 0)}`}>{trendArrow(convRate)} {formatDelta(convRate)}</span>
          </div>
          <div className="text-[10px] uppercase tracking-wider text-faint mt-1">Conv rate</div>
        </div>
      </div>
    </button>
  );
}

// Family card (Option 4 — colored hero band): a net-profit hero band tinted green/red
// by the profit value, with the family name + trend, over a neutral units footer.
function FamilyCard({ label, netProfit, unitsSold, convRate, divisor = 1, compareLabel, npCaption, active, onClick }: CardProps) {
  return (
    <button onClick={onClick}
      className={`flex flex-col rounded-xl border overflow-hidden text-left transition-all duration-200
        ${active
          ? 'border-blue-500 shadow-md ring-1 ring-blue-500/20'
          : 'border-border hover:border-border-strong hover:shadow-sm'}`}>
      {/* Hero band — net profit; tint intensifies when net profit + units trend agree */}
      <div className={`px-4 py-3 ${dualTint(netProfit.cur > 0, unitsSold.deltaPct > 0)}`}>
        <div className="flex items-start justify-between gap-2 mb-1.5">
          <span className="text-[14px] font-semibold uppercase tracking-wide text-text truncate">{label}</span>
          {/* Conversion rate — top-right of the hero band */}
          <span className="text-right shrink-0 leading-none" title="Conversion rate">
            <span className="block text-[13px] font-mono font-semibold text-text">{formatMetric(convRate)}</span>
            <span className="block text-[9px] uppercase tracking-wider text-faint mt-0.5">cvr</span>
          </span>
        </div>
        <div className="flex items-baseline gap-2 flex-wrap">
          <span className={`text-[26px] font-bold font-mono leading-none tracking-tight ${txt(netProfit.cur > 0)}`}>{formatMetric(netProfit, divisor)}</span>
          <span className={`text-[13px] font-mono font-semibold ${txt(netProfit.deltaPct > 0)}`}>{trendArrow(netProfit)} {formatDelta(netProfit)}</span>
        </div>
        <div className="text-[10px] uppercase tracking-wider text-faint mt-1.5">{npCaption ?? `Net profit · ${compareLabel}`}</div>
      </div>
      {/* Units footer — neutral, with its own coloured trend */}
      <div className="flex items-baseline justify-between px-4 py-2.5 border-t border-border bg-card">
        <span>
          <span className="text-[17px] font-bold font-mono text-text">{formatMetric(unitsSold, divisor)}</span>
          <span className="text-[10px] uppercase tracking-wider text-faint ml-1.5">units</span>
        </span>
        <span className={`text-[13px] font-mono font-semibold ${txt(unitsSold.deltaPct > 0)}`}>{trendArrow(unitsSold)} {formatDelta(unitsSold)}</span>
      </div>
    </button>
  );
}

function DateToggle({ mode, todayEnabled, reason, onPick }: { mode: DateMode; todayEnabled: boolean; reason?: string; onPick: (m: DateMode) => void }) {
  return (
    <div className="inline-flex gap-0.5 bg-white/[.04] border border-border rounded-lg p-0.5">
      {DATE_MODES.map(d => {
        const disabled = d.key === 'today' && !todayEnabled;
        const active = (mode === d.key) || (mode === 'today' && !todayEnabled && d.key === 'yday');
        return (
          <button key={d.key} disabled={disabled} title={disabled ? reason : undefined}
            onClick={() => !disabled && onPick(d.key)}
            className={`text-[11px] font-mono px-2 py-1 rounded-md transition-all
              ${disabled ? 'text-faint/40 cursor-not-allowed' : active ? 'bg-blue-500/90 text-white' : 'text-muted hover:text-text'}`}>
            {d.label}
          </button>
        );
      })}
    </div>
  );
}

// Total vs Per-day toggle — shown only for multi-day windows (7d / 30d).
function PerDayToggle({ perDay, onPick }: { perDay: boolean; onPick: (v: boolean) => void }) {
  return (
    <div className="ml-auto inline-flex gap-0.5 bg-white/[.04] border border-border rounded-lg p-0.5">
      {([[false, 'Total'], [true, 'Per day']] as const).map(([v, label]) => (
        <button key={label} onClick={() => onPick(v)}
          className={`text-[11px] font-mono px-2 py-1 rounded-md transition-all
            ${perDay === v ? 'bg-blue-500/90 text-white' : 'text-muted hover:text-text'}`}>
          {label}
        </button>
      ))}
    </div>
  );
}

function KpiStrip({ kpis, divisor = 1 }: { kpis: MetricDelta[]; divisor?: number }) {
  return (
    <div className="flex gap-2 flex-wrap mb-3">
      {kpis.map(m => (
        <div key={m.key} className="flex-1 min-w-[92px] border border-border-faint rounded-lg px-2.5 py-1.5">
          <div className="text-[10px] uppercase tracking-wide text-subtle">{m.label}</div>
          <div className="text-[16px] font-bold font-mono text-text leading-tight">{formatMetric(m, divisor)}</div>
          <div className={`text-[11px] font-mono font-semibold ${metricColor(m)}`}>
            {arrowFor(m)} {m.moved ? formatDelta(m) : '~flat'}
          </div>
        </div>
      ))}
    </div>
  );
}

// One per-product metric: absolute value + trend (Sales / Units / Spend / CPC).
function ProductMetric({ m, divisor = 1 }: { m: MetricDelta; divisor?: number }) {
  return (
    <span className="whitespace-nowrap font-mono">
      <span className="text-subtle">{m.label}</span> <span className="text-text">{formatMetric(m, divisor)}</span>
      {m.moved && <span className={metricColor(m)}> {arrowFor(m)}{formatDelta(m)}</span>}
    </span>
  );
}

// Compact one-line family summary for the All tab: health dot + name + read + moved KPIs.
function FamilySummaryRow({ view, divisor = 1, onClick }: { view: import('../homeBrief').FamilyView; divisor?: number; onClick: () => void }) {
  const moved = view.kpis.filter(m => m.moved).slice(0, 3);
  return (
    <button onClick={onClick}
      className="w-full flex items-start gap-2 text-left text-[12px] py-1.5 border-t border-border-faint/50 first:border-t-0 hover:bg-white/[.02] transition-colors rounded">
      <span className={`w-1.5 h-1.5 rounded-full mt-1.5 shrink-0 ${DOT[view.health]}`} />
      <span className="text-text font-medium min-w-[92px] shrink-0">{stripLolli(view.family)}</span>
      <span className="flex-1 min-w-0">
        <span className="text-muted leading-snug">{view.read}</span>
        {moved.length > 0 && (
          <span className="flex flex-wrap gap-x-3 gap-y-0.5 mt-0.5">
            {moved.map(m => <ProductMetric key={m.key} m={m} divisor={divisor} />)}
          </span>
        )}
      </span>
    </button>
  );
}

function FamilyPanel({ view, divisor, onNav }: { view: import('../homeBrief').FamilyView; divisor: number; onNav: (p: string, f?: FamilyName) => void }) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-[1fr_270px] gap-4 p-4">
      {/* What moved */}
      <div>
        <h4 className="text-[11px] uppercase tracking-wider text-subtle mb-2">What moved</h4>
        <p className="text-[13.5px] text-muted leading-relaxed mb-3">{view.read}</p>
        <KpiStrip kpis={view.kpis} divisor={divisor} />
        {view.approxNote && <p className="text-[10px] text-faint italic mb-2">{view.approxNote}</p>}
        {view.products.length ? (
          <div className="border-t border-border-faint pt-2">
            {view.products.map((p, i) => (
              <div key={i} className="flex items-start gap-2 text-[12px] py-1.5 border-t border-border-faint/50 first:border-t-0">
                <span className="text-text font-medium min-w-[104px] shrink-0">{p.name}</span>
                <span className="flex flex-wrap gap-x-3 gap-y-0.5">
                  {p.metrics.map(m => <ProductMetric key={m.key} m={m} divisor={divisor} />)}
                </span>
              </div>
            ))}
            {view.adsOnly && <p className="text-[10px] text-faint italic mt-1.5">Per-product is ads-derived (orders not in yet today).</p>}
          </div>
        ) : <p className="text-[12px] text-faint">All products steady — nothing moved.</p>}
      </div>

      {/* Needs attention */}
      <div className="md:border-l md:border-border-faint md:pl-4">
        <h4 className="text-[11px] uppercase tracking-wider text-subtle mb-2">Needs attention</h4>
        {view.attention.length ? (
          <>
            {view.attention.map((a, i) => (
              <div key={i} className="flex gap-2 text-[12px] py-1.5 border-t border-border-faint first:border-t-0">
                <span>{ATT_ICON[a.level]}</span><span className="text-muted leading-snug">{a.text}</span>
              </div>
            ))}
            {view.attention.some(a => a.level === 'warn' && a.text.includes('coach')) && (
              <button onClick={() => onNav('actions')}
                className="mt-2.5 w-full text-center text-[11px] py-1.5 rounded-md border border-blue-500/60 text-blue-300 bg-blue-500/10 hover:bg-blue-500/20 transition-colors">
                Review actions →
              </button>
            )}
          </>
        ) : <p className="text-[12px] text-faint">Nothing flagged. ✓</p>}
      </div>
    </div>
  );
}

function OverviewPanel({ model, divisor, onNav, onPickFamily }:
  { model: import('../homeBrief').BriefModel; divisor: number; onNav: (p: string, f?: FamilyName) => void; onPickFamily: (f: string) => void }) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-[1fr_270px] gap-4 p-4">
      {/* What moved — whole book, then a per-family summary */}
      <div>
        <h4 className="text-[11px] uppercase tracking-wider text-subtle mb-2">What moved</h4>
        <p className="text-[13.5px] text-muted leading-relaxed mb-3">{model.overview.headline}</p>
        <KpiStrip kpis={model.allKpis} divisor={divisor} />
        <div className="border-t border-border-faint pt-2">
          {model.families.map(f => (
            <FamilySummaryRow key={f.family} view={f} divisor={divisor} onClick={() => onPickFamily(f.family)} />
          ))}
        </div>
        <p className="text-[10px] text-faint mt-2">Pick a family for the per-product detail.</p>
      </div>
      <div className="md:border-l md:border-border-faint md:pl-4">
        <h4 className="text-[11px] uppercase tracking-wider text-subtle mb-2">Needs attention</h4>
        {model.overview.attention.length ? (
          <>
            {model.overview.attention.map((a, i) => (
              <div key={i} className="flex gap-2 text-[12px] py-1.5 border-t border-border-faint first:border-t-0">
                <span>{ATT_ICON[a.level]}</span><span className="text-muted leading-snug">{a.text}</span>
              </div>
            ))}
            <button onClick={() => onNav('actions')}
              className="mt-2.5 w-full text-center text-[11px] py-1.5 rounded-md border border-blue-500/60 text-blue-300 bg-blue-500/10 hover:bg-blue-500/20 transition-colors">
              Review actions →
            </button>
          </>
        ) : <p className="text-[12px] text-faint">Nothing flagged. ✓</p>}
      </div>
    </div>
  );
}
