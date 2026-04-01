import { useState, useMemo } from 'react';
import type { DashboardData, BusinessConclusion, ExperimentTemplateRow } from '../types';
import { useFilters } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { FilterInfoIcon } from '../components/FilterInfoIcon';
import { Card } from '../components/Card';
import { Badge, RoasBadge } from '../components/Badge';
import { PageHeader } from '../components/PageHeader';
import { Empty } from '../components/Empty';
import { fM, fOrd, fP, fR } from '../utils';
import { useConclusions } from '../hooks/useConclusions';
import { deriveInsights } from '../hooks/useGroundTruth';
import type { Observation, WeekInsight } from '../hooks/useGroundTruth';
import { usePageSummary } from '../components/PageSummaryBar';
import { useThresholds } from '../hooks/useThresholds';
import { ThresholdEditor } from '../components/ThresholdEditor';

const IMPACT_COLORS: Record<string, string> = { scale: 'green', reduce: 'red', adjust: 'amber', test: 'blue' };
const IMPACT_LABELS: Record<string, string> = { scale: 'Scale', reduce: 'Reduce', adjust: 'Adjust', test: 'Test' };

const STRATEGY_HYPOTHESES: [RegExp, string][] = [
  [/broad/i, 'Testing whether broad match keywords capture incremental demand and drive organic lift at an acceptable ROAS'],
  [/exact/i, 'Testing whether exact match targeting delivers higher conversion rate and better cost-efficiency'],
  [/bid|bidding/i, 'Testing whether bid adjustments (higher/lower) improve profitability or market share'],
  [/asin|product.?target/i, 'Testing whether ASIN / product targeting steals competitor share cost-effectively'],
  [/\bsb\b|brand|sponsor.*brand/i, 'Testing whether Sponsored Brands ads drive brand awareness and top-of-funnel lift'],
  [/video|sbv/i, 'Testing whether video ads improve engagement and conversion versus static placements'],
  [/defend|protect/i, 'Testing whether defensive campaigns protect branded search share from competitors'],
  [/launch|new/i, 'Testing launch strategy to establish initial velocity and organic ranking for a new product'],
  [/organic|halo/i, 'Measuring organic halo effect — do paid ads lift organic orders beyond the ad spend?'],
  [/scale|growth/i, 'Testing whether scaling spend maintains ROAS while growing total order volume'],
];

function deriveHypothesis(name: string, strategyId: string, template?: ExperimentTemplateRow): string {
  if (template?.description) return template.description;
  const combined = `${name} ${strategyId}`;
  for (const [re, hypothesis] of STRATEGY_HYPOTHESES) {
    if (re.test(combined)) return hypothesis;
  }
  return `Evaluating campaign strategy "${strategyId || name}" for performance and organic impact`;
}

interface ExperimentTakeaway {
  text: string;
  sentiment: 'positive' | 'negative' | 'neutral' | 'warning';
}

function deriveWeeklyTakeaways(insights: WeekInsight[]): ExperimentTakeaway[] {
  if (insights.length < 2) return [];
  const takeaways: ExperimentTakeaway[] = [];
  const recent = insights.slice(-3);
  const latest = recent[recent.length - 1];
  const prev = recent.length >= 2 ? recent[recent.length - 2] : null;

  if (prev && latest) {
    const roasDelta = prev.roas !== 0 ? ((latest.roas - prev.roas) / Math.abs(prev.roas)) * 100 : 0;
    if (roasDelta > 10) {
      takeaways.push({ text: `ROAS trending up ${Math.abs(roasDelta).toFixed(0)}% (${fR(prev.roas)} → ${fR(latest.roas)}) — consider scaling spend`, sentiment: 'positive' });
    } else if (roasDelta < -10) {
      takeaways.push({ text: `ROAS declining ${Math.abs(roasDelta).toFixed(0)}% (${fR(prev.roas)} → ${fR(latest.roas)}) — review keyword targeting`, sentiment: 'negative' });
    }

    const orgDelta = latest.orgP - prev.orgP;
    if (orgDelta > 3) {
      takeaways.push({ text: `Organic share rising (+${orgDelta.toFixed(0)}pp to ${fP(latest.orgP)}) — building organic traction`, sentiment: 'positive' });
    } else if (orgDelta < -5) {
      takeaways.push({ text: `Organic share dropping (${orgDelta.toFixed(0)}pp to ${fP(latest.orgP)}) — may be over-reliant on ads`, sentiment: 'warning' });
    }
  }

  if (latest && latest.spend > 20 && latest.orders < 3 && latest.roas < 0.5) {
    takeaways.push({ text: `High spend (${fM(latest.spend)}) but only ${latest.orders} orders — review targeting or pause`, sentiment: 'negative' });
  }

  if (latest && latest.roas >= 1.5) {
    takeaways.push({ text: `Profitable at ${fR(latest.roas)} net ROAS — proven winner, candidate to scale`, sentiment: 'positive' });
  } else if (latest && latest.roas < 0 && latest.spend > 10) {
    takeaways.push({ text: `Losing money (${fR(latest.roas)} net ROAS) — needs optimization or pause`, sentiment: 'negative' });
  }

  const roasValues = recent.map(w => w.roas);
  const allDeclining = roasValues.length >= 3 && roasValues.every((v, i) => i === 0 || v <= roasValues[i - 1]);
  if (allDeclining && roasValues[roasValues.length - 1] < 0.5) {
    takeaways.push({ text: 'ROAS declining for 3+ weeks — strong candidate to pause or restructure', sentiment: 'negative' });
  }

  return takeaways;
}

interface KeyLearning {
  text: string;
  sentiment: 'positive' | 'negative' | 'neutral' | 'warning';
}

function deriveKeyLearnings(
  byExp: Record<string, { experiment_id: string; experiment_name: string; strategy_id: string; week_start: string; ads_spend: number; ads_orders: number; sessions: number; sales: number; organic_units: number; total_orders: number }[]>,
  expIds: string[]
): KeyLearning[] {
  if (!expIds.length) return [];
  const learnings: KeyLearning[] = [];

  const expStats = expIds.map(eid => {
    const rows = byExp[eid];
    const insights = deriveInsights(rows);
    const name = rows[0]?.experiment_name || eid;
    const latestWeeks = insights.slice(-3);
    const latest = latestWeeks.length ? latestWeeks[latestWeeks.length - 1] : null;
    const avgRoas = latestWeeks.length ? latestWeeks.reduce((s, w) => s + w.roas, 0) / latestWeeks.length : 0;
    const avgOrgP = latestWeeks.length ? latestWeeks.reduce((s, w) => s + w.orgP, 0) / latestWeeks.length : 0;
    const totalSpend = insights.reduce((s, w) => s + w.spend, 0);
    const totalOrders = insights.reduce((s, w) => s + w.orders, 0);
    const roasTrend = latestWeeks.length >= 3
      ? latestWeeks.every((w, i) => i === 0 || w.roas <= latestWeeks[i - 1].roas) ? 'declining'
        : latestWeeks.every((w, i) => i === 0 || w.roas >= latestWeeks[i - 1].roas) ? 'improving'
        : 'mixed'
      : 'insufficient';
    return { eid, name, avgRoas, avgOrgP, totalSpend, totalOrders, latest, roasTrend, weeksCount: insights.length };
  });

  const sorted = [...expStats].sort((a, b) => b.avgRoas - a.avgRoas);
  const best = sorted[0];
  const worst = sorted[sorted.length - 1];

  if (best && worst && sorted.length >= 2 && best.eid !== worst.eid) {
    learnings.push({
      text: `Best performer: ${best.name} (avg ${fR(best.avgRoas)} ROAS). Worst: ${worst.name} (avg ${fR(worst.avgRoas)} ROAS)`,
      sentiment: 'neutral',
    });
  } else if (best) {
    learnings.push({
      text: `Top performer: ${best.name} with avg ${fR(best.avgRoas)} net ROAS`,
      sentiment: best.avgRoas >= 1 ? 'positive' : 'warning',
    });
  }

  const growingOrganic = expStats.filter(e => e.avgOrgP > 30).sort((a, b) => b.avgOrgP - a.avgOrgP);
  if (growingOrganic.length) {
    const top = growingOrganic[0];
    learnings.push({
      text: `${top.name} leads organic share at ${fP(top.avgOrgP)} — ads are driving halo effect`,
      sentiment: 'positive',
    });
  }

  const pauseCandidates = expStats.filter(e => e.roasTrend === 'declining' && e.avgRoas < 0.5 && e.weeksCount >= 3);
  if (pauseCandidates.length) {
    learnings.push({
      text: `Consider pausing: ${pauseCandidates.map(e => e.name).join(', ')} — declining ROAS below break-even for 3+ weeks`,
      sentiment: 'negative',
    });
  }

  const scaleCandidates = expStats.filter(e => e.avgRoas >= 1.5 && (e.roasTrend === 'improving' || e.roasTrend === 'mixed'));
  if (scaleCandidates.length) {
    learnings.push({
      text: `Scale candidates: ${scaleCandidates.map(e => e.name).join(', ')} — strong ROAS, room to increase spend`,
      sentiment: 'positive',
    });
  }

  const highSpendLowReturn = expStats.filter(e => e.totalSpend > 50 && e.avgRoas < 0);
  if (highSpendLowReturn.length) {
    learnings.push({
      text: `Money sink: ${highSpendLowReturn.map(e => `${e.name} (${fM(e.totalSpend)} spent, ${fR(e.avgRoas)} ROAS)`).join('; ')}`,
      sentiment: 'negative',
    });
  }

  return learnings.slice(0, 5);
}

const TAKEAWAY_STYLES: Record<string, string> = {
  positive: 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20',
  negative: 'text-red-400 bg-red-500/10 border-red-500/20',
  warning: 'text-amber-400 bg-amber-500/10 border-amber-500/20',
  neutral: 'text-blue-400 bg-blue-500/10 border-blue-500/20',
};
const TAKEAWAY_ICONS: Record<string, string> = {
  positive: '↑', negative: '↓', warning: '⚠', neutral: '→',
};

export function LearnPage({ data }: { data: DashboardData }) {
  const { filters, setFilter } = useFilters();
  const { active, archived, add, remove, archive } = useConclusions();
  const [showForm, setShowForm] = useState(false);
  const [showArchived, setShowArchived] = useState(false);
  const { grouped, loading: thLoading, error: thError, saving, updateThreshold, approveSuggestion } = useThresholds();

  const expFilterEffective = filters.experiment || 'all';
  const learnFilterItems = useMemo(() => formatSectionFilters(filters), [filters]);

  const ew = data.experiment_weekly || [];
  const templates = data.experiment_templates || [];
  const templateMap = useMemo(() => {
    const m: Record<string, ExperimentTemplateRow> = {};
    templates.forEach(t => { m[t.experiment_id] = t; });
    return m;
  }, [templates]);

  const byExp = useMemo(() => {
    const m: Record<string, typeof ew> = {};
    ew.forEach(r => { const e = r.experiment_id || '?'; if (!m[e]) m[e] = []; m[e].push(r); });
    return m;
  }, [ew]);
  const expIds = useMemo(() => Object.keys(byExp).sort(), [byExp]);

  const keyLearnings = useMemo(() => deriveKeyLearnings(byExp, expIds), [byExp, expIds]);

  usePageSummary({ title: 'Learn', items: [{ label: 'Data Explorer', value: 'Active' }] });
  return (
    <div className="animate-in">
      <PageHeader title="Learnings" subtitle="What we're testing, what we learned, and what to do next" />

      {/* Key Learnings across all experiments */}
      {keyLearnings.length > 0 && (
        <div className="border border-blue-500/20 bg-blue-500/[.04] rounded-lg p-4 mb-5">
          <div className="flex items-center gap-2 mb-3">
            <span className="text-sm font-bold">Key Learnings</span>
            <span className="text-[11px] text-subtle font-normal">auto-generated across all experiments</span>
          </div>
          <div className="space-y-2">
            {keyLearnings.map((l, i) => (
              <div key={i} className={`flex items-start gap-2.5 px-3 py-2 rounded-lg border text-[12px] ${TAKEAWAY_STYLES[l.sentiment]}`}>
                <span className="font-bold text-[13px] mt-px leading-none">{TAKEAWAY_ICONS[l.sentiment]}</span>
                <span>{l.text}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Coach Thresholds Editor */}
      <div className="mb-6">
        <div className="flex items-center gap-2 text-sm font-bold mb-3">
          Coach Thresholds <span className="text-[11px] text-subtle font-normal">configurable decision engine rules per strategy</span>
          {learnFilterItems.length > 0 && <FilterInfoIcon items={learnFilterItems} />}
        </div>
        {thLoading ? (
          <div className="text-[11px] text-subtle py-8 text-center">Loading thresholds…</div>
        ) : thError ? (
          <div className="text-[11px] text-red-400 py-4 text-center">
            ⚠ Could not load thresholds: {thError}
            <div className="text-[10px] text-subtle mt-1">Thresholds are managed via the data-entry app. The coach view will use default values.</div>
          </div>
        ) : grouped.length === 0 ? (
          <Empty icon="⚙️" message="No thresholds configured" hint="Deploy DE_COACH_THRESHOLDS table and run the seed SQL to populate." />
        ) : (
          <ThresholdEditor
            grouped={grouped}
            saving={saving}
            onUpdate={updateThreshold}
            onApprove={approveSuggestion}
          />
        )}
      </div>

      {/* Active Business Conclusions */}
      <div className={`border rounded-lg p-4 mb-5 ${active.length ? 'border-emerald-500/25 bg-emerald-500/[.04]' : 'border-border bg-card'}`}>
        <div className="flex items-center gap-2 mb-3">
          <span className="text-sm font-bold">Approved Conclusions</span>
          {learnFilterItems.length > 0 && <FilterInfoIcon items={learnFilterItems} />}
          {active.length > 0 && <Badge variant="green">{active.length} active</Badge>}
          {archived.length > 0 && (
            <button onClick={() => setShowArchived(!showArchived)} className="text-[10px] text-subtle hover:text-muted ml-auto">
              {showArchived ? 'Hide' : 'Show'} {archived.length} archived
            </button>
          )}
          <button
            onClick={() => setShowForm(!showForm)}
            className="ml-auto px-3 py-1.5 rounded-lg text-xs font-semibold border border-blue-500/30 bg-blue-500/10 text-blue-400 hover:bg-blue-500/20 transition-all"
          >
            + New Conclusion
          </button>
        </div>

        {!active.length && !showForm && (
          <div className="text-[11px] text-subtle">
            No approved conclusions yet. Review the experiment data below, then add conclusions about what works and what doesn't.
            These will guide future campaign and experiment decisions.
          </div>
        )}

        {/* Conclusion cards */}
        {active.map(c => <ConclusionCard key={c.id} c={c} onArchive={archive} onRemove={remove} />)}
        {showArchived && archived.map(c => <ConclusionCard key={c.id} c={c} onArchive={archive} onRemove={remove} />)}

        {/* Add form */}
        {showForm && <ConclusionForm onAdd={(c) => { add(c); setShowForm(false); }} onCancel={() => setShowForm(false)} data={data} />}
      </div>

      {/* Data Evidence: Weekly Experiment Performance */}
      <div className="mb-6">
        <div className="flex items-center gap-2 text-sm font-bold mb-3">
          Experiment Evidence <span className="text-[11px] text-subtle font-normal font-mono">hypothesis → weekly data → takeaway</span>
          {learnFilterItems.length > 0 && <FilterInfoIcon items={learnFilterItems} />}
        </div>

        <div className="flex gap-2 items-center flex-wrap p-2.5 bg-surface/50 backdrop-blur border border-border rounded-xl mb-3.5">
          <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold">Experiment</label>
          <select value={expFilterEffective} onChange={e => setFilter('experiment', e.target.value === 'all' ? null : e.target.value)} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
            <option value="all">All</option>
            {expIds.map(e => <option key={e} value={e}>{e}</option>)}
          </select>
        </div>

        {!ew.length ? <Empty icon="📈" message="No weekly experiment data" hint="Experiment data will appear once campaigns start collecting performance metrics." /> : (
          <div>
            {(expFilterEffective === 'all' ? expIds : expIds.filter(e => e === expFilterEffective)).map(eid => {
              const rows = byExp[eid];
              const eName = rows[0]?.experiment_name || eid;
              const eSt = rows[0]?.strategy_id || '';
              const insights = deriveInsights(rows);
              const meaningful = insights.filter(ins => ins.obs.some(o => o.good !== null || o.t === 'stable'));
              if (!meaningful.length) return null;

              const hypothesis = deriveHypothesis(eName, eSt, templateMap[eid]);
              const takeaways = deriveWeeklyTakeaways(insights);

              return (
                <Card key={eid} className="mb-3.5">
                  <div className="flex items-center justify-between mb-1">
                    <div className="text-[15px] font-bold tracking-tight">
                      {eName} <span className="text-[11px] text-subtle font-normal">{eSt} · {meaningful.length} weeks</span>
                    </div>
                    <button
                      onClick={() => setShowForm(true)}
                      className="text-[10px] text-blue-400 hover:text-blue-300 font-semibold"
                    >
                      + Conclusion from this
                    </button>
                  </div>

                  {/* Hypothesis */}
                  <div className="flex items-start gap-2 px-3 py-2 mb-2.5 rounded-lg bg-violet-500/[.06] border border-violet-500/15 text-[11px]">
                    <span className="text-violet-400 font-bold text-[10px] uppercase tracking-wider shrink-0 mt-px">Hypothesis</span>
                    <span className="text-violet-300/90">{hypothesis}</span>
                  </div>

                  {/* Weekly Takeaways */}
                  {takeaways.length > 0 && (
                    <div className="space-y-1.5 mb-2.5">
                      <span className="text-[10px] text-subtle uppercase tracking-wider font-semibold">Takeaways</span>
                      {takeaways.map((t, i) => (
                        <div key={i} className={`flex items-start gap-2 px-3 py-1.5 rounded-lg border text-[11px] ${TAKEAWAY_STYLES[t.sentiment]}`}>
                          <span className="font-bold text-[12px] mt-px leading-none">{TAKEAWAY_ICONS[t.sentiment]}</span>
                          <span>{t.text}</span>
                        </div>
                      ))}
                    </div>
                  )}

                  {[...meaningful].reverse().map(ins => (
                    <InsightRow key={ins.week} ins={ins} />
                  ))}
                </Card>
              );
            })}
          </div>
        )}
      </div>

      {/* BigQuery Learnings */}
      {(data.learnings || []).length > 0 && (
        <div className="mb-6">
          <div className="flex items-center gap-2 text-sm font-bold mb-3">
            Aggregated Learnings (BigQuery)
            {learnFilterItems.length > 0 && <FilterInfoIcon items={learnFilterItems} />}
          </div>
          <LearningsTable rows={data.learnings || []} />
        </div>
      )}
    </div>
  );
}

function ConclusionCard({ c, onArchive, onRemove }: { c: BusinessConclusion; onArchive: (id: string) => void; onRemove: (id: string) => void }) {
  const isArchived = c.status === 'archived';
  return (
    <div className={`bg-card border rounded-xl p-3.5 mb-2 ${isArchived ? 'border-border opacity-60' : 'border-border hover:border-border-strong'} transition-colors`}>
      <div className="flex items-start gap-3">
        <div className="flex-1">
          <div className="flex items-center gap-2 mb-1.5">
            <Badge variant={IMPACT_COLORS[c.impact] || 'blue'}>{IMPACT_LABELS[c.impact] || c.impact}</Badge>
            {c.family && <Badge variant="muted">{c.family}</Badge>}
            {c.tags.map(t => <span key={t} className="text-[9px] text-faint bg-zinc-800 px-1.5 py-0.5 rounded">{t}</span>)}
            {isArchived && <Badge variant="muted">Archived</Badge>}
          </div>
          <div className="text-[13px] font-semibold mb-1">{c.conclusion}</div>
          <div className="text-[11px] text-subtle">{c.evidence}</div>
          <div className="text-[10px] text-faint mt-1 font-mono">
            {c.created_at}{c.experiment_id ? ` · ${c.experiment_id}` : ''}
          </div>
        </div>
        <div className="flex gap-1">
          <button onClick={() => onArchive(c.id)} className="text-[10px] text-subtle hover:text-muted px-2 py-1 border border-border rounded-md hover:border-border-strong transition-colors" title={isArchived ? 'Reactivate' : 'Archive'}>
            {isArchived ? '↩' : '📦'}
          </button>
          <button onClick={() => onRemove(c.id)} className="text-[10px] text-subtle hover:text-red-400 px-2 py-1 border border-border rounded-md hover:border-red-500/30 transition-colors" title="Delete">✕</button>
        </div>
      </div>
    </div>
  );
}

function ConclusionForm({ onAdd, onCancel, data }: {
  onAdd: (c: Omit<BusinessConclusion, 'id' | 'created_at' | 'status'>) => void;
  onCancel: () => void;
  data: DashboardData;
}) {
  const [conclusion, setConclusion] = useState('');
  const [evidence, setEvidence] = useState('');
  const [family, setFamily] = useState('');
  const [expId, setExpId] = useState('');
  const [impact, setImpact] = useState<'scale' | 'reduce' | 'adjust' | 'test'>('adjust');
  const [tagStr, setTagStr] = useState('');

  const expIds = useMemo(() => [...new Set((data.experiment_weekly || []).map(r => r.experiment_id))].sort(), [data.experiment_weekly]);

  const submit = () => {
    if (!conclusion.trim()) return;
    onAdd({
      conclusion: conclusion.trim(),
      evidence: evidence.trim(),
      family: family || undefined,
      experiment_id: expId || undefined,
      impact,
      tags: tagStr.split(',').map(t => t.trim()).filter(Boolean),
    });
  };

  return (
    <div className="bg-card border border-blue-500/20 rounded-xl p-4 mt-3">
      <div className="text-[13px] font-bold mb-3">New Business Conclusion</div>
      <div className="space-y-2.5">
        <div>
          <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold block mb-1">Conclusion *</label>
          <textarea
            value={conclusion}
            onChange={e => setConclusion(e.target.value)}
            placeholder="e.g. Broad match keywords on LolliME generate 2x more organic orders than exact match"
            className="w-full bg-[#09090b] border border-border text-white px-3 py-2 rounded-lg text-[12px] focus:outline-none focus:border-blue-500 resize-none"
            rows={2}
          />
        </div>
        <div>
          <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold block mb-1">Evidence (supporting data)</label>
          <textarea
            value={evidence}
            onChange={e => setEvidence(e.target.value)}
            placeholder="e.g. Over 4 weeks (Feb 1-27), broad match avg organic % was 35% vs exact match 18%, with Net ROAS 1.2x vs 0.8x"
            className="w-full bg-[#09090b] border border-border text-white px-3 py-2 rounded-lg text-[12px] focus:outline-none focus:border-blue-500 resize-none"
            rows={2}
          />
        </div>
        <div className="grid grid-cols-4 gap-2.5">
          <div>
            <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold block mb-1">Family</label>
            <select value={family} onChange={e => setFamily(e.target.value)} className="w-full bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
              <option value="">All</option>
              <option value="Lollibox">Lollibox</option>
              <option value="LolliME">LolliME</option>
              <option value="Bottle">Bottle</option>
              <option value="Fresh">Fresh</option>
            </select>
          </div>
          <div>
            <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold block mb-1">Experiment</label>
            <select value={expId} onChange={e => setExpId(e.target.value)} className="w-full bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
              <option value="">None</option>
              {expIds.map(e => <option key={e} value={e}>{e}</option>)}
            </select>
          </div>
          <div>
            <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold block mb-1">Action Impact</label>
            <select value={impact} onChange={e => setImpact(e.target.value as typeof impact)} className="w-full bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
              <option value="scale">Scale (do more)</option>
              <option value="reduce">Reduce (do less)</option>
              <option value="adjust">Adjust (change approach)</option>
              <option value="test">Test (needs validation)</option>
            </select>
          </div>
          <div>
            <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold block mb-1">Tags (comma-sep)</label>
            <input
              value={tagStr}
              onChange={e => setTagStr(e.target.value)}
              placeholder="keywords, bidding, listing"
              className="w-full bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500"
            />
          </div>
        </div>
        <div className="flex gap-2 pt-1">
          <button onClick={submit} disabled={!conclusion.trim()} className="px-4 py-2 rounded-lg text-xs font-semibold bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 hover:bg-emerald-500/30 transition-all disabled:opacity-30 disabled:cursor-not-allowed">
            Approve Conclusion ✓
          </button>
          <button onClick={onCancel} className="px-4 py-2 rounded-lg text-xs font-semibold text-subtle border border-border hover:border-border-strong transition-all">Cancel</button>
        </div>
      </div>
    </div>
  );
}

function InsightRow({ ins }: { ins: { week: string; spend: number; orders: number; sales: number; sessions: number; cvr: number; roas: number; orgP: number; obs: Observation[] } }) {
  return (
    <div className="bg-inset border border-border-faint rounded-lg p-3 mb-2">
      <div className="flex justify-between items-center mb-1.5">
        <div className="flex items-center gap-2">
          <span className="font-mono text-xs font-bold text-blue-400">{ins.week?.slice(5, 10) || '--'}</span>
          <RoasBadge value={ins.roas} />
          <span className="text-[11px] text-subtle">Spend: {fM(ins.spend)}</span>
          <span className="text-[11px] text-subtle">{fOrd(ins.orders)}</span>
        </div>
        <div className="flex gap-1.5 text-faint font-mono text-[10px]">
          <span>{ins.sessions?.toLocaleString()} sess</span>
          <span>CVR {fP(ins.cvr)}</span>
          <span>Org {fP(ins.orgP)}</span>
        </div>
      </div>
      {ins.obs.map((o, i) => (
        <div key={i} className="flex items-center gap-2 py-1 text-[11px]">
          <span>{o.good === true ? '🟢' : o.good === false ? '🔴' : '⚪'}</span>
          <span className="text-muted">{o.txt}</span>
        </div>
      ))}
    </div>
  );
}

function LearningsTable({ rows }: { rows: { learning_dimension: string; [k: string]: string | number }[] }) {
  const dims = useMemo(() => {
    const d: Record<string, typeof rows> = {};
    rows.forEach(r => { const k = r.learning_dimension || 'other'; if (!d[k]) d[k] = []; d[k].push(r); });
    return d;
  }, [rows]);

  return (
    <div>
      {Object.entries(dims).map(([dim, dr]) => {
        const keys = Object.keys(dr[0] || {}).filter(k => k !== 'learning_dimension');
        return (
          <Card key={dim} className="mb-3.5">
            <div className="text-[13px] font-bold mb-2 tracking-tight">{dim.replace(/_/g, ' ').toUpperCase()}</div>
            <div className="border border-border rounded-xl bg-card overflow-x-auto">
              <table className="w-full border-collapse text-xs">
                <thead>
                  <tr>{keys.map(k => <th key={k} className="bg-inset text-subtle text-left px-3 py-2 font-semibold text-[10px] uppercase tracking-wider border-b border-border whitespace-nowrap">{k.replace(/_/g, ' ')}</th>)}</tr>
                </thead>
                <tbody>
                  {dr.map((r, i) => (
                    <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                      {keys.map(k => <td key={k} className={`px-3 py-2 ${typeof r[k] === 'number' ? 'text-right font-mono text-[11px]' : ''}`}>{r[k] != null ? String(r[k]) : '--'}</td>)}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>
        );
      })}
    </div>
  );
}
