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

function worstHealth(hs: Health[]): Health {
  if (hs.includes('risk')) return 'risk';
  if (hs.includes('warn')) return 'warn';
  if (hs.includes('good')) return 'good';
  return 'flat';
}

export function HomeBrief({ data, onNav }: { data: DashboardData; onNav: (p: string, f?: FamilyName) => void }) {
  const [mode, setMode] = useState<DateMode>(() => recall('oi_brief_mode', 'yday') as DateMode);
  const [famKey, setFamKey] = useState<string>(() => recall('oi_brief_family', 'All'));
  const [showNumbers, setShowNumbers] = useState<boolean>(() => recall('oi_brief_numbers', '0') === '1');

  const fresh = data._meta?.data_freshness;
  const adsMax = fresh?.ads_max_date || '';
  const perfMax = fresh?.performance_max_date || '';
  // Today is ready when ads data is a day ahead of orders (an ads-only day before orders catch up).
  const todayEnabled = !!adsMax && !!perfMax && adsMax > perfMax;
  const effMode: DateMode = mode === 'today' && !todayEnabled ? 'yday' : mode;

  const model = useMemo(() => buildBriefModel(data, effMode), [data, effMode]);

  const setModeP = (m: DateMode) => { setMode(m); persist('oi_brief_mode', m); };
  const setFamP = (f: string) => { setFamKey(f); persist('oi_brief_family', f); };
  const setNumP = (v: boolean) => { setShowNumbers(v); persist('oi_brief_numbers', v ? '1' : '0'); };

  const fam = famKey === 'All' ? null : model.families.find(f => f.family === famKey) || null;
  const overallHealth = worstHealth(model.families.map(f => f.health));

  return (
    <div className="mb-3 bg-card border border-border rounded-lg overflow-hidden backdrop-blur-xl">
      {/* MAIN TOGGLE: family */}
      <div className="flex gap-1 flex-wrap p-1.5 border-b border-border bg-white/[.015]">
        <FamilyTab label="All" dot={overallHealth} active={famKey === 'All'} onClick={() => setFamP('All')} />
        {model.families.map(f => (
          <FamilyTab key={f.family} label={f.family} dot={f.health} steady={f.steady}
            active={famKey === f.family} onClick={() => setFamP(f.family)} />
        ))}
      </div>

      {/* HEADER: date window (inside) + detail toggle */}
      <div className="flex items-center gap-3 px-4 py-2.5 flex-wrap border-b border-border-faint">
        <span className="text-[15px] font-semibold text-text">{fam ? fam.family : 'All families'}</span>
        <DateToggle mode={mode} todayEnabled={todayEnabled} reason={model.todayDisabledReason} onPick={setModeP} />
        <span className="text-[11px] font-mono text-faint">{model.periodLabel}</span>
        {fam && (
          <button onClick={() => setNumP(!showNumbers)}
            className="ml-auto text-[11px] text-muted hover:text-blue-400 transition-colors">
            plain · <span className={showNumbers ? 'text-blue-400 font-semibold' : ''}>numbers</span>
          </button>
        )}
      </div>

      {fam ? <FamilyPanel view={fam} showNumbers={showNumbers} onNav={onNav} />
        : <OverviewPanel model={model} onNav={onNav} />}
    </div>
  );
}

function FamilyTab({ label, dot, active, steady, onClick }: { label: string; dot: Health; active: boolean; steady?: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick}
      className={`flex-1 min-w-[88px] flex items-center justify-center gap-1.5 px-2 py-2 rounded-md text-[13px] font-semibold transition-all
        ${active ? 'bg-blue-500 text-white shadow-md' : steady ? 'text-faint hover:text-muted' : 'text-muted hover:text-text'}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${DOT[dot]} ${active ? 'ring-1 ring-white/40' : ''}`} />
      {label}
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

function KpiStrip({ kpis, showNumbers }: { kpis: MetricDelta[]; showNumbers: boolean }) {
  return (
    <div className="flex gap-2 flex-wrap mb-3">
      {kpis.map(m => (
        <div key={m.key} className="flex-1 min-w-[92px] border border-border-faint rounded-lg px-2.5 py-1.5">
          <div className="text-[10px] uppercase tracking-wide text-subtle">{m.label}</div>
          {showNumbers && <div className="text-[16px] font-bold font-mono text-text leading-tight">{formatMetric(m)}</div>}
          <div className={`text-[11px] font-mono font-semibold ${metricColor(m)}`}>
            {arrowFor(m)} {m.moved ? formatDelta(m) : '~flat'}
          </div>
        </div>
      ))}
    </div>
  );
}

// One per-product metric: absolute value + trend (Sales / Units / Spend / CPC).
function ProductMetric({ m }: { m: MetricDelta }) {
  return (
    <span className="whitespace-nowrap font-mono">
      <span className="text-subtle">{m.label}</span> <span className="text-text">{formatMetric(m)}</span>
      {m.moved && <span className={metricColor(m)}> {arrowFor(m)}{formatDelta(m)}</span>}
    </span>
  );
}

function FamilyPanel({ view, showNumbers, onNav }: { view: import('../homeBrief').FamilyView; showNumbers: boolean; onNav: (p: string, f?: FamilyName) => void }) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-[1fr_270px] gap-4 p-4">
      {/* What moved */}
      <div>
        <h4 className="text-[11px] uppercase tracking-wider text-subtle mb-2">What moved</h4>
        <p className="text-[13.5px] text-muted leading-relaxed mb-3">{view.read}</p>
        <KpiStrip kpis={view.kpis} showNumbers={showNumbers} />
        {view.approxNote && <p className="text-[10px] text-faint italic mb-2">{view.approxNote}</p>}
        {showNumbers && (
          view.products.length ? (
            <div className="border-t border-border-faint pt-2">
              {view.products.map((p, i) => (
                <div key={i} className="flex items-start gap-2 text-[12px] py-1.5 border-t border-border-faint/50 first:border-t-0">
                  <span className="text-text font-medium min-w-[104px] shrink-0">{p.name}</span>
                  <span className="flex flex-wrap gap-x-3 gap-y-0.5">
                    {p.metrics.map(m => <ProductMetric key={m.key} m={m} />)}
                  </span>
                </div>
              ))}
              {view.adsOnly && <p className="text-[10px] text-faint italic mt-1.5">Per-product is ads-derived (orders not in yet today).</p>}
            </div>
          ) : <p className="text-[12px] text-faint">All products steady — nothing moved.</p>
        )}
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

function OverviewPanel({ model, onNav }: { model: import('../homeBrief').BriefModel; onNav: (p: string, f?: FamilyName) => void }) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-[1fr_270px] gap-4 p-4">
      <div>
        <h4 className="text-[11px] uppercase tracking-wider text-subtle mb-2">The read</h4>
        <p className="text-[14px] text-muted leading-relaxed">{model.overview.headline}</p>
        <p className="text-[11px] text-faint mt-2">Pick a family above for the detail.</p>
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
