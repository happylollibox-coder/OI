import React, { useState, useMemo, useEffect, createElement } from 'react';
import type { DashboardData, StrategyCampaignRow, StrategyCampaignWeeklyRow } from '../types';
import { Card } from '../components/Card';
import { Empty } from '../components/Empty';
import { Th } from '../components/Tooltip';
import { RoasBadge } from '../components/Badge';
import { fM, fP, fR, fCpc, fClk, fOrd, experimentMatchesFamily, weekRangeLabelCapped, periodKey, getPeriodsToInclude } from '../utils';
import { useFilters, type PeriodMode } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { FilterInfoIcon } from '../components/FilterInfoIcon';
import { filterBySeasonality } from '../seasonality';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';
import { CHART_GRID, CHART_AXIS_TICK_LG, CHART_TOOLTIP_STYLE } from '../chartTheme';
import { type SeasonPhase, PHASE_META, ALL_PHASES, classifyPhase, filterByPhase } from '../phaseClassifier';
import { Target, TrendingUp, Sun, Flame, Zap } from 'lucide-react';
import { STRATEGY_META, DEFAULT_STRATEGY, CHART_MEASURE_META, type ChartMeasureId } from '../strategies';
import { usePageSummary } from '../components/PageSummaryBar';
import { groupByStrategy, type StrategyGroup } from './strategiesData';

const PHASE_ICONS: Record<SeasonPhase, typeof Sun> = { offseason: Sun, boost: Flame, peak: Zap };

// Trend measures this page can show (derived from the campaign×week rows).
const TREND_MEASURES: ChartMeasureId[] = ['spend', 'orders', 'sales', 'net_roas', 'cpc', 'conv_rate']
  .filter((m): m is ChartMeasureId => CHART_MEASURE_META[m as ChartMeasureId] != null);

type PeriodPoint = { label: string; spend: number; orders: number; sales: number; net_roas: number; cpc: number; conv_rate: number };

/** Aggregate a raw {spend,orders,clicks,sales} bucket into display metrics. */
function finishBucket(label: string, d: { spend: number; orders: number; clicks: number; sales: number }): PeriodPoint {
  return {
    label,
    spend: d.spend,
    orders: d.orders,
    sales: d.sales,
    net_roas: d.spend > 0 ? (d.sales - d.spend) / d.spend : 0,
    cpc: d.clicks > 0 ? d.spend / d.clicks : 0,
    conv_rate: d.clicks > 0 ? (d.orders * 100) / d.clicks : 0,
  };
}

export function StrategiesPage({ data }: { data: DashboardData }) {
  const { filters } = useFilters();
  const perfMaxDate = data._meta?.data_freshness?.performance_max_date || '';
  const [selectedStrategy, setSelectedStrategy] = useState<string | null>(null);
  const [activePhase, setActivePhase] = useState<SeasonPhase | null>(null);
  const [selectedTrendMeasures, setSelectedTrendMeasures] = useState<Set<ChartMeasureId>>(new Set(['spend']));
  const holidays = data.holidays || [];
  const pk = data.peak?.[0] ?? null;

  const famOk = useMemo(() => {
    const fam = filters.family;
    return (name: string | null | undefined, parent: string | null | undefined) =>
      !fam || experimentMatchesFamily(name, fam) || experimentMatchesFamily(parent, fam);
  }, [filters.family]);

  // Campaign roster (lifetime perf) — powers the cards + the campaigns table.
  const campaigns = useMemo<StrategyCampaignRow[]>(() => {
    let rows = data.strategy_campaigns || [];
    rows = rows.filter(c => famOk(c.campaign_name, c.parent_name));
    return rows;
  }, [data.strategy_campaigns, famOk]);

  const groups = useMemo<StrategyGroup[]>(() => groupByStrategy(campaigns), [campaigns]);

  // Weekly rows (family + seasonality filtered) — powers phase breakdown + trend.
  const weekly = useMemo<StrategyCampaignWeeklyRow[]>(() => {
    let rows = data.strategy_campaign_weekly || [];
    rows = rows.filter(c => famOk(c.campaign_name, c.parent_name));
    rows = filterBySeasonality(rows, 'week_start', filters.seasonality, pk);
    return rows;
  }, [data.strategy_campaign_weekly, famOk, filters.seasonality, pk]);

  // Per-strategy, per-phase aggregates (all time) for the card mini-row + phase KPI cards.
  const phaseByStrategy = useMemo(() => {
    const out: Record<string, Record<SeasonPhase, { spend: number; sales: number; orders: number; roas: number; weeks: number }>> = {};
    const seen: Record<string, Record<SeasonPhase, Set<string>>> = {};
    const init = () => ({ spend: 0, sales: 0, orders: 0, roas: 0, weeks: 0 });
    weekly.forEach(r => {
      const s = r.strategy_id;
      if (!out[s]) { out[s] = { offseason: init(), boost: init(), peak: init() }; seen[s] = { offseason: new Set(), boost: new Set(), peak: new Set() }; }
      const phase = classifyPhase(r.week_start || '', holidays);
      out[s][phase].spend += r.spend || 0;
      out[s][phase].sales += r.sales || 0;
      out[s][phase].orders += r.orders || 0;
      seen[s][phase].add(r.week_start || '');
    });
    Object.keys(out).forEach(s => ALL_PHASES.forEach(p => {
      out[s][p].weeks = seen[s][p].size;
      out[s][p].roas = out[s][p].spend > 0 ? (out[s][p].sales - out[s][p].spend) / out[s][p].spend : 0;
    }));
    return out;
  }, [weekly, holidays]);

  const selected = groups.find(g => g.id === selectedStrategy) || null;
  const selectedMeta = selected ? (STRATEGY_META[selected.id] || { ...DEFAULT_STRATEGY, label: selected.id }) : null;

  const toggleTrendMeasure = (m: ChartMeasureId) => setSelectedTrendMeasures(prev => {
    const next = new Set(prev);
    if (next.has(m)) { if (next.size > 1) next.delete(m); } else next.add(m);
    return next;
  });
  const activeTrendMeasures = useMemo(() => [...selectedTrendMeasures], [selectedTrendMeasures]);

  useEffect(() => { setActivePhase(null); }, [selectedStrategy]);

  // Trend by period for the selected strategy (from weekly, honoring phase + period controls).
  const trendData = useMemo<PeriodPoint[]>(() => {
    if (!selected) return [];
    let rows = weekly.filter(r => r.strategy_id === selected.id);
    rows = filterByPhase(rows, 'week_start', activePhase, holidays);
    const mode: PeriodMode = filters.periodMode;
    const sp = filters.specificPeriod;
    const pt = filters.periodTrend;
    const bucket = () => ({ spend: 0, orders: 0, clicks: 0, sales: 0 });

    if (mode === 'weeks') {
      const allWeeks = [...new Set(rows.map(r => r.week_start || ''))].filter(Boolean).sort();
      const keep = new Set(getPeriodsToInclude(sp, mode, allWeeks, pt));
      const by: Record<string, ReturnType<typeof bucket>> = {};
      rows.filter(r => keep.has(r.week_start || '')).forEach(r => {
        const k = r.week_start || '';
        if (!by[k]) by[k] = bucket();
        by[k].spend += r.spend || 0; by[k].orders += r.orders || 0; by[k].clicks += r.clicks || 0; by[k].sales += r.sales || 0;
      });
      return Object.keys(by).sort().map(w => finishBucket(weekRangeLabelCapped(w, perfMaxDate), by[w]));
    }
    const by: Record<string, ReturnType<typeof bucket>> = {};
    rows.forEach(r => {
      const k = periodKey(r.week_start || '', mode);
      if (!by[k]) by[k] = bucket();
      by[k].spend += r.spend || 0; by[k].orders += r.orders || 0; by[k].clicks += r.clicks || 0; by[k].sales += r.sales || 0;
    });
    const keys = Object.keys(by).sort();
    const keep = new Set(getPeriodsToInclude(sp, mode, keys, pt));
    return keys.filter(k => keep.has(k)).map(k => finishBucket(k, by[k]));
  }, [selected, weekly, activePhase, holidays, filters.periodMode, filters.specificPeriod, filters.periodTrend, perfMaxDate]);

  const strategyFilterItems = formatSectionFilters(filters);
  usePageSummary({ title: 'Strategies', items: [{ label: 'Campaigns', value: String(campaigns.length) }] });

  const totalActive = useMemo(() => campaigns.filter(c => c.is_active).length, [campaigns]);

  return (
    <div className="animate-in">
      <div className="flex items-center gap-2 mb-1">
        <h1 className="text-[22px] font-extrabold tracking-tight">Advertising Strategies</h1>
        {strategyFilterItems.length > 0 && <FilterInfoIcon items={strategyFilterItems} />}
      </div>
      <p className="text-xs text-subtle mb-1">Every live campaign grouped by its strategy</p>
      <p className="text-[10px] text-faint font-mono mb-5">{campaigns.length} campaigns · {totalActive} active · lifetime spend</p>

      {/* Strategy Cards Grid */}
      <div className="grid grid-cols-4 gap-3 mb-6">
        {groups.map(g => {
          const meta = STRATEGY_META[g.id] || { ...DEFAULT_STRATEGY, label: g.id };
          return (
            <Card key={g.id}
              className={`!p-4 cursor-pointer transition-all hover:border-[#888]/30 ${selectedStrategy === g.id ? 'ring-1' : ''}`}
              style={selectedStrategy === g.id ? { borderColor: meta.color + '80' } : {}}
              onClick={() => setSelectedStrategy(selectedStrategy === g.id ? null : g.id)}>
              <div className="flex items-center gap-2 mb-2" style={{ color: meta.color }}>
                {meta.icon && createElement(meta.icon, { size: 16 })}
                <span className="font-bold text-sm">{meta.label}</span>
              </div>
              <div className="text-[10px] text-subtle leading-relaxed mb-3">{meta.goal.slice(0, 90)}{meta.goal.length > 90 ? '…' : ''}</div>
              <div className="grid grid-cols-3 gap-2 text-center">
                <div>
                  <div className="text-[9px] text-faint uppercase">Active</div>
                  <div className="font-mono font-bold text-sm" style={{ color: meta.color }}>{g.activeCount}</div>
                </div>
                <div>
                  <div className="text-[9px] text-faint uppercase">Ads Spend</div>
                  <div className="font-mono font-bold text-sm">{fM(g.totalSpend)}</div>
                </div>
                <div>
                  <div className="text-[9px] text-faint uppercase">Ads ROAS</div>
                  <div className={`font-mono font-bold text-sm ${g.avgRoas >= 1 ? 'text-emerald-400' : g.avgRoas >= 0 ? 'text-amber-400' : 'text-red-400'}`}>{fR(g.avgRoas)}</div>
                </div>
              </div>
              {phaseByStrategy[g.id] && (
                <div className="flex items-center gap-3 mt-2.5 pt-2.5 border-t border-border-faint">
                  {ALL_PHASES.map(p => {
                    const pm = phaseByStrategy[g.id][p];
                    const pmeta = PHASE_META[p];
                    return (
                      <div key={p} className="flex items-center gap-1 text-[9px]">
                        <span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: pm.weeks > 0 ? pmeta.color : '#3f3f46' }} />
                        <span className="text-faint">{pmeta.label.split(' ')[0]}</span>
                        <span className="font-mono font-semibold" style={{ color: pm.weeks > 0 ? pmeta.color : '#52525b' }}>{pm.weeks > 0 ? fR(pm.roas) : '—'}</span>
                      </div>
                    );
                  })}
                </div>
              )}
              <div className="text-[9px] text-faint mt-2 font-mono">{g.campaigns.length} campaigns</div>
            </Card>
          );
        })}
      </div>

      {/* Selected Strategy Detail */}
      {selected && selectedMeta && (
        <div className="mb-6 animate-in">
          <div className="flex items-start gap-4 mb-4">
            <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ backgroundColor: selectedMeta.color + '20', color: selectedMeta.color }}>
              {selectedMeta.icon && createElement(selectedMeta.icon, { size: 16 })}
            </div>
            <div className="flex-1">
              <h2 className="text-lg font-bold" style={{ color: selectedMeta.color }}>{selectedMeta.label}</h2>
              <p className="text-xs text-subtle mt-1">{selectedMeta.goal}</p>
            </div>
          </div>

          {/* Phase Tab Bar */}
          <div className="flex items-center gap-1.5 mb-4">
            <button onClick={() => setActivePhase(null)}
              className="px-3 py-1.5 rounded-lg text-[11px] font-semibold border transition-all"
              style={{ borderColor: !activePhase ? selectedMeta.color + '60' : 'rgba(63,63,70,.45)', background: !activePhase ? selectedMeta.color + '15' : 'transparent', color: !activePhase ? selectedMeta.color : '#71717a' }}>
              All Phases
            </button>
            {ALL_PHASES.map(p => {
              const pmeta = PHASE_META[p];
              const Icon = PHASE_ICONS[p];
              const isActive = activePhase === p;
              const phaseData = phaseByStrategy[selected.id]?.[p];
              return (
                <button key={p} onClick={() => setActivePhase(isActive ? null : p)}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[11px] font-semibold border transition-all"
                  style={{ borderColor: isActive ? pmeta.color + '60' : 'rgba(63,63,70,.45)', background: isActive ? pmeta.color + '15' : 'transparent', color: isActive ? pmeta.color : '#71717a' }}>
                  <Icon size={12} />
                  {pmeta.label}
                  {phaseData && phaseData.weeks > 0 && <span className="text-[9px] font-mono opacity-70">{phaseData.weeks}w</span>}
                </button>
              );
            })}
          </div>

          {/* Phase Summary KPI Row */}
          {phaseByStrategy[selected.id] && (
            <div className="grid grid-cols-3 gap-3 mb-4">
              {ALL_PHASES.map(p => {
                const pm = phaseByStrategy[selected.id][p];
                const pmeta = PHASE_META[p];
                const Icon = PHASE_ICONS[p];
                return (
                  <Card key={p} className={`!p-4 ${activePhase === p ? 'ring-1' : ''}`} style={activePhase === p ? { borderColor: pmeta.color + '40' } : {}}>
                    <div className="flex items-center gap-2 mb-3">
                      <div className="w-7 h-7 rounded-lg flex items-center justify-center" style={{ backgroundColor: pmeta.color + '20', color: pmeta.color }}>
                        <Icon size={14} />
                      </div>
                      <div>
                        <div className="text-xs font-bold" style={{ color: pmeta.color }}>{pmeta.label}</div>
                        <div className="text-[9px] text-faint font-mono">{pm.weeks} weeks data</div>
                      </div>
                    </div>
                    {pm.weeks > 0 ? (
                      <div className="grid grid-cols-3 gap-2 text-center">
                        <div><div className="text-[9px] text-faint uppercase">Ads Spend</div><div className="font-mono font-bold text-sm">{fM(pm.spend)}</div></div>
                        <div><div className="text-[9px] text-faint uppercase">Ads ROAS</div><div className={`font-mono font-bold text-sm ${pm.roas >= 1 ? 'text-emerald-400' : pm.roas >= 0 ? 'text-amber-400' : 'text-red-400'}`}>{fR(pm.roas)}</div></div>
                        <div><div className="text-[9px] text-faint uppercase">Ads Orders</div><div className="font-mono font-bold text-sm">{fOrd(pm.orders)}</div></div>
                      </div>
                    ) : <div className="text-[11px] text-faint italic text-center py-2">No data in this phase</div>}
                  </Card>
                );
              })}
            </div>
          )}

          {/* Expected Outcome + Key Metrics */}
          <div className="grid grid-cols-2 gap-3.5 mb-5">
            <Card className="!p-4">
              <div className="flex items-center gap-2 mb-2"><Target size={14} className="text-blue-400" /><span className="text-xs font-bold text-blue-400">Expected Outcome</span></div>
              <p className="text-[11px] text-subtle leading-relaxed">{selectedMeta.expectedOutcome}</p>
            </Card>
            <Card className="!p-4">
              <div className="flex items-center gap-2 mb-2"><TrendingUp size={14} className="text-emerald-400" /><span className="text-xs font-bold text-emerald-400">Key Metrics to Track</span></div>
              <div className="space-y-1.5">
                {selectedMeta.keyMetrics.map((m, i) => (
                  <div key={i} className="flex items-center gap-2 text-[11px] text-subtle">
                    <span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: selectedMeta.color }} />{m}
                  </div>
                ))}
              </div>
            </Card>
          </div>

          {/* Campaigns table + Trend */}
          <div className="grid grid-cols-1 lg:grid-cols-[1fr,320px] gap-4 mb-4">
            <Card className="!p-0 overflow-hidden">
              <div className="px-4 py-3 border-b border-border flex items-center">
                <span className="text-xs font-bold">{selected.campaigns.length} Campaigns</span>
                <span className="text-[10px] text-faint ml-2">{selected.activeCount} active · lifetime</span>
              </div>
              {selected.campaigns.length > 0 ? (
                <div className="overflow-x-auto">
                  <table className="w-full border-collapse text-xs">
                    <thead><tr>
                      <Th>Campaign</Th><Th>Type</Th><Th>Family</Th>
                      <Th right>Ads Spend</Th><Th right>Orders</Th><Th right>Clicks</Th>
                      <Th right>CPC</Th><Th right>Conv%</Th><Th>Ads ROAS</Th><Th>Live</Th>
                    </tr></thead>
                    <tbody>
                      {[...selected.campaigns].sort((a, b) => (b.spend || 0) - (a.spend || 0)).map(c => (
                        <tr key={c.campaign_id} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                          <td className="px-3 py-2 font-semibold max-w-[220px] truncate" title={c.campaign_name}>{c.campaign_name}</td>
                          <td className="px-3 py-2 text-faint">{c.campaign_type || '--'}</td>
                          <td className="px-3 py-2 text-faint truncate max-w-[120px]" title={c.parent_name || ''}>{c.parent_name || '--'}</td>
                          <td className="px-3 py-2 text-right font-mono font-semibold">{fM(c.spend)}</td>
                          <td className="px-3 py-2 text-right font-mono">{fOrd(c.orders)}</td>
                          <td className="px-3 py-2 text-right font-mono">{fClk(c.clicks)}</td>
                          <td className="px-3 py-2 text-right font-mono">{c.cpc != null && c.cpc > 0 ? fCpc(c.cpc) : '--'}</td>
                          <td className="px-3 py-2 text-right font-mono">{fP(c.conv_rate ?? 0)}</td>
                          <td className="px-3 py-2"><RoasBadge value={c.net_roas ?? 0} /></td>
                          <td className="px-3 py-2">{c.is_active ? <span className="w-1.5 h-1.5 rounded-full inline-block bg-emerald-400" title="Active (spent in last 30d)" /> : <span className="w-1.5 h-1.5 rounded-full inline-block bg-zinc-600" title="Dormant" />}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : <Empty message="No campaigns for this strategy" />}
            </Card>

            <Card className="!p-4">
              <div className="text-xs font-bold mb-2">Trend by Period</div>
              <div className="flex flex-wrap gap-1 mb-3">
                {TREND_MEASURES.map(m => {
                  const meta = CHART_MEASURE_META[m];
                  const active = selectedTrendMeasures.has(m);
                  return (
                    <button key={m} onClick={() => toggleTrendMeasure(m)}
                      className="px-2 py-0.5 rounded-lg text-[10px] font-semibold border transition-all"
                      style={{ borderColor: active ? meta.color : 'rgba(63,63,70,.45)', background: active ? meta.color + '20' : 'transparent', color: active ? meta.color : '#71717a' }}>
                      {meta.label}
                    </button>
                  );
                })}
              </div>
              {trendData.length > 0 ? (
                <ResponsiveContainer width="100%" height={200}>
                  <BarChart data={trendData} barCategoryGap="20%">
                    <CartesianGrid {...CHART_GRID} />
                    <XAxis dataKey="label" tick={CHART_AXIS_TICK_LG} tickLine={false} axisLine={false} />
                    <YAxis yAxisId="left" tick={CHART_AXIS_TICK_LG} tickLine={false} axisLine={false}
                      tickFormatter={v => { const meta = activeTrendMeasures[0] ? CHART_MEASURE_META[activeTrendMeasures[0]] : null; return meta ? (meta.fmtShort ?? meta.fmt)(v) : String(v); }} />
                    <Tooltip contentStyle={CHART_TOOLTIP_STYLE(10)}
                      formatter={(v: number | undefined, name?: string) => { const m = CHART_MEASURE_META[name as ChartMeasureId]; return [m ? m.fmt(v ?? 0) : String(v ?? 0), (m?.label || name) ?? '']; }} />
                    {activeTrendMeasures.map(m => { const meta = CHART_MEASURE_META[m]; return <Bar key={m} yAxisId="left" dataKey={m} radius={[4, 4, 0, 0]} fill={meta.color} />; })}
                  </BarChart>
                </ResponsiveContainer>
              ) : <Empty message="No weekly data for period" />}
            </Card>
          </div>
        </div>
      )}

      {!selectedStrategy && groups.length > 0 && (
        <Card className="!p-6 text-center">
          <Target size={24} className="mx-auto text-blue-400 mb-2" />
          <div className="text-sm font-bold mb-1">Select a strategy above to see its campaigns</div>
          <div className="text-xs text-subtle">Every live campaign is grouped by its resolved strategy. Unclassified campaigns can be assigned in Admin ▸ Campaign Strategy.</div>
        </Card>
      )}

      {groups.length === 0 && <Empty message="No campaign data" hint="Campaigns appear here once they have ad spend." />}
    </div>
  );
}
