import { useCallback, useEffect, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { fM } from '../utils';
import { dataEntry, type CoachEscalationRow } from '../utils/dataEntry';

type PlanRow = {
  parent: string; purposes: string; cells: number; scaleCells: number;
  spend: number; fwdNet: number | null; probeClicks: number; weekStart: string;
};
type BenchRow = {
  parent: string;
  lastPeakNet: number | null; lastPeakSpend: number | null; lastPeakWeek: string;
  peakAvgNet: number | null; peakAvgSpend: number | null; peakWeeksN: number; peakAvgFrom: string;
  lastOffNet: number | null; lastOffSpend: number | null; lastOffWeek: string;
  offAvgNet: number | null; offAvgSpend: number | null; offWeeksN: number; offAvgFrom: string;
};

const npClass = (n: number | null) =>
  n == null ? 'text-zinc-500' : n > 0 ? 'text-emerald-400' : n < 0 ? 'text-red-400' : 'text-zinc-500';
const sevClass = (s: string) =>
  s === 'ESCALATE' ? 'text-red-400' : s === 'WATCH' ? 'text-amber-400' : 'text-zinc-500';
const sevBorder = (s: string) =>
  s === 'ESCALATE' ? 'border-l-red-500' : s === 'WATCH' ? 'border-l-amber-500' : 'border-l-zinc-500';
const trg = (t: string) => t.replace(/_/g, ' ').toLowerCase();

// "Jun 22" from a YYYY-MM-DD string, parsed as a local date to avoid TZ drift.
const fmtDay = (ds: string) => {
  const [y, m, d] = (ds || '').slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return ds || '';
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
};
const weekRange = (ds: string) => {
  const [y, m, d] = (ds || '').slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return '';
  const end = new Date(y, m - 1, d + 6);
  return `${fmtDay(ds)} – ${end.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`;
};
// Tooltip naming the actual week(s) a benchmark value is computed from.
const weekTip = (n: number, from: string, to: string, label: string) =>
  n <= 0 ? `no ${label} weeks recorded yet`
    : from && to && from !== to ? `${n} ${label} weeks: ${fmtDay(from)} – ${fmtDay(to)}`
    : `week of ${fmtDay(to || from)}`;

// "$1.2k net · $3.4k sp" cell — net headline (sign-colored) over a muted spend line.
const NetSpend = ({ net, spend, title }: { net: number | null; spend: number | null; title?: string }) => (
  net == null ? <span className="text-faint" title={title}>—</span> : (
    <span title={title}>
      <span className={npClass(net)}>{fM(net)}</span>
      {spend != null && <span className="text-faint"> · {fM(spend)} sp</span>}
    </span>
  )
);

export function ThisWeekPage() {
  const [esc, setEsc] = useState<CoachEscalationRow[]>([]);
  const [plan, setPlan] = useState<PlanRow[]>([]);
  const [bench, setBench] = useState<BenchRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [busyKey, setBusyKey] = useState<string | null>(null);
  const [showHandled, setShowHandled] = useState(false);

  // Escalations come from Flask (fresh) so an Ack/Snooze reflects immediately on re-fetch.
  const loadEscalations = useCallback(async () => {
    try { setEsc(await dataEntry.getCoachEscalations()); }
    catch { /* leave as-is; surface stays usable */ }
  }, []);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const [p, b] = await Promise.all([
          cubeLoad({
            dimensions: ['CoachWeeklyPlanProduct.parentName', 'CoachWeeklyPlanProduct.purposes',
              'CoachWeeklyPlanProduct.cells', 'CoachWeeklyPlanProduct.scaleCells',
              'CoachWeeklyPlanProduct.plannedSpend', 'CoachWeeklyPlanProduct.forwardAdsNet',
              'CoachWeeklyPlanProduct.probeMapClicks', 'CoachWeeklyPlanProduct.weekStart'],
            filters: [{ member: 'CoachWeeklyPlanProduct.horizon', operator: 'equals', values: ['CURRENT'] }],
          }),
          cubeLoad({
            dimensions: ['CoachWeeklyBenchmark.parentName',
              'CoachWeeklyBenchmark.lastPeakNet', 'CoachWeeklyBenchmark.lastPeakSpend', 'CoachWeeklyBenchmark.lastPeakWeek',
              'CoachWeeklyBenchmark.peakAvg4Net', 'CoachWeeklyBenchmark.peakAvg4Spend', 'CoachWeeklyBenchmark.peakWeeksN', 'CoachWeeklyBenchmark.peakAvgFromWeek',
              'CoachWeeklyBenchmark.lastOffNet', 'CoachWeeklyBenchmark.lastOffSpend', 'CoachWeeklyBenchmark.lastOffWeek',
              'CoachWeeklyBenchmark.offAvg4Net', 'CoachWeeklyBenchmark.offAvg4Spend', 'CoachWeeklyBenchmark.offWeeksN', 'CoachWeeklyBenchmark.offAvgFromWeek'],
          }),
        ]);
        if (!alive) return;
        const num = (v: unknown) => (v != null ? Number(v) : null);
        setPlan((p as Record<string, unknown>[]).map(r => ({
          parent: String(r['CoachWeeklyPlanProduct.parentName'] ?? ''),
          purposes: String(r['CoachWeeklyPlanProduct.purposes'] ?? ''),
          cells: Number(r['CoachWeeklyPlanProduct.cells'] ?? 0),
          scaleCells: Number(r['CoachWeeklyPlanProduct.scaleCells'] ?? 0),
          spend: Number(r['CoachWeeklyPlanProduct.plannedSpend'] ?? 0),
          fwdNet: num(r['CoachWeeklyPlanProduct.forwardAdsNet']),
          probeClicks: Number(r['CoachWeeklyPlanProduct.probeMapClicks'] ?? 0),
          weekStart: String(r['CoachWeeklyPlanProduct.weekStart'] ?? ''),
        })).filter(r => r.parent).sort((a, b) => a.parent.localeCompare(b.parent)));
        setBench((b as Record<string, unknown>[]).map(r => ({
          parent: String(r['CoachWeeklyBenchmark.parentName'] ?? ''),
          lastPeakNet: num(r['CoachWeeklyBenchmark.lastPeakNet']), lastPeakSpend: num(r['CoachWeeklyBenchmark.lastPeakSpend']),
          lastPeakWeek: String(r['CoachWeeklyBenchmark.lastPeakWeek'] ?? ''),
          peakAvgNet: num(r['CoachWeeklyBenchmark.peakAvg4Net']), peakAvgSpend: num(r['CoachWeeklyBenchmark.peakAvg4Spend']),
          peakWeeksN: Number(r['CoachWeeklyBenchmark.peakWeeksN'] ?? 0), peakAvgFrom: String(r['CoachWeeklyBenchmark.peakAvgFromWeek'] ?? ''),
          lastOffNet: num(r['CoachWeeklyBenchmark.lastOffNet']), lastOffSpend: num(r['CoachWeeklyBenchmark.lastOffSpend']),
          lastOffWeek: String(r['CoachWeeklyBenchmark.lastOffWeek'] ?? ''),
          offAvgNet: num(r['CoachWeeklyBenchmark.offAvg4Net']), offAvgSpend: num(r['CoachWeeklyBenchmark.offAvg4Spend']),
          offWeeksN: Number(r['CoachWeeklyBenchmark.offWeeksN'] ?? 0), offAvgFrom: String(r['CoachWeeklyBenchmark.offAvgFromWeek'] ?? ''),
        })).filter(r => r.parent).sort((a, b) => a.parent.localeCompare(b.parent)));
        await loadEscalations();
        setLoading(false);
      } catch (ex) {
        if (alive) { setErr(String(ex)); setLoading(false); }
      }
    })();
    return () => { alive = false; };
  }, [loadEscalations]);

  const act = async (e: CoachEscalationRow, action: 'ACK' | 'SNOOZE') => {
    setBusyKey(e.escalation_key);
    try {
      await dataEntry.postEscalationAction({
        escalation_key: e.escalation_key, parent_name: e.parent_name, trigger: e.trigger,
        action, severity: e.severity, note: notes[e.escalation_key] || undefined,
        snooze_days: action === 'SNOOZE' ? 7 : undefined,
      });
      await loadEscalations();
    } catch { /* keep card; user can retry */ }
    finally { setBusyKey(null); }
  };

  const active = esc.filter(e => !e.is_handled);
  const handled = esc.filter(e => e.is_handled);
  const range = plan.find(p => p.weekStart)?.weekStart;

  return (
    <div className="max-w-4xl mx-auto px-4 py-6 text-text">
      <div className="flex items-baseline justify-between mb-4">
        <h1 className="text-title font-medium">
          This week{range ? <span className="text-muted font-normal"> · {weekRange(range)}</span> : ''}
        </h1>
        <span className="text-label text-muted">coacher · ads-attributed net</span>
      </div>

      {loading && <div className="text-body text-muted">Loading…</div>}
      {err && <div className="text-body text-red-400">Couldn't load coacher data: {err}</div>}

      {!loading && !err && (
        <>
          <div className="text-label font-medium text-muted mb-2">Needs your attention</div>
          {active.length === 0 && <div className="text-body text-muted mb-4">Nothing escalated — on plan.</div>}
          <div className="flex flex-col gap-2 mb-4">
            {active.map((e) => (
              <div key={e.escalation_key} className={`bg-card border border-border border-l-4 ${sevBorder(e.severity)} rounded-r-xl px-4 py-3`}>
                <div className="flex items-center gap-3">
                  <span className={`text-label font-medium uppercase tracking-wide ${sevClass(e.severity)}`}>{e.severity.toLowerCase()}</span>
                  <div className="flex-1 text-body"><span className="font-medium">{e.parent_name}</span> <span className="text-muted">· {trg(e.trigger)}</span></div>
                  <div className={`font-mono font-medium w-16 text-right ${npClass(e.actual_net)}`}>{fM(e.actual_net)}</div>
                  <div className="text-muted text-label w-56">{e.recommended_action}</div>
                </div>
                <div className="flex items-center gap-2 mt-2 pl-[3.25rem]">
                  <input
                    value={notes[e.escalation_key] ?? ''}
                    onChange={(ev) => setNotes(n => ({ ...n, [e.escalation_key]: ev.target.value }))}
                    placeholder="note (optional)"
                    className="flex-1 text-label bg-surface/40 border border-border rounded-md px-2 py-1 focus:outline-none focus:ring-1 focus:ring-blue-500/40"
                  />
                  <button disabled={busyKey === e.escalation_key} onClick={() => act(e, 'ACK')}
                    className="shrink-0 text-label px-2.5 py-1 rounded-md border border-emerald-500/40 text-emerald-400 hover:bg-emerald-500/10 disabled:opacity-50">Acknowledge</button>
                  <button disabled={busyKey === e.escalation_key} onClick={() => act(e, 'SNOOZE')}
                    className="shrink-0 text-label px-2.5 py-1 rounded-md border border-border text-muted hover:bg-white/5 disabled:opacity-50">Snooze 7d</button>
                </div>
              </div>
            ))}
          </div>

          {handled.length > 0 && (
            <div className="mb-8">
              <button onClick={() => setShowHandled(v => !v)} className="text-label text-faint hover:text-muted">
                {showHandled ? '▾' : '▸'} Handled ({handled.length})
              </button>
              {showHandled && (
                <div className="flex flex-col gap-1 mt-2">
                  {handled.map((e) => (
                    <div key={e.escalation_key} className="flex items-center gap-3 text-label text-faint px-2 py-1.5 border-l-2 border-border">
                      <span className="font-medium text-muted">{e.parent_name}</span>
                      <span>· {trg(e.trigger)}</span>
                      <span className="ml-auto">
                        {e.last_action === 'SNOOZE' && e.snooze_until ? `snoozed → ${fmtDay(e.snooze_until)}` : 'acknowledged'}
                        {e.handled_note ? ` · "${e.handled_note}"` : ''}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          <div className="text-label font-medium text-muted mb-2">This week's plan</div>
          <table className="w-full text-body border-collapse mb-8">
            <thead>
              <tr className="text-muted text-label text-left">
                <th className="font-normal px-2 py-1">product</th>
                <th className="font-normal px-2 py-1">purposes</th>
                <th className="font-normal px-2 py-1 text-right">cells</th>
                <th className="font-normal px-2 py-1 text-right">planned spend</th>
                <th className="font-normal px-2 py-1 text-right" title="Forward ads-direct net $ from profit-scaling cells (excludes organic). MAP/PROBE cells aim for clicks, not $.">fwd net (scale)</th>
              </tr>
            </thead>
            <tbody>
              {plan.map((p, i) => (
                <tr key={i} className="border-t border-border">
                  <td className="px-2 py-2 font-medium">{p.parent}</td>
                  <td className="px-2 py-2 text-muted">{p.purposes}</td>
                  <td className="px-2 py-2 text-right font-mono">{p.cells}</td>
                  <td className="px-2 py-2 text-right font-mono">{fM(p.spend)}</td>
                  <td className="px-2 py-2 text-right font-mono">
                    {p.scaleCells > 0
                      ? <span className={npClass(p.fwdNet)}>{fM(p.fwdNet)}</span>
                      : p.probeClicks > 0
                      ? <span className="text-muted">{p.probeClicks} clicks</span>
                      : <span className="text-subtle">cut only</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          <div className="text-label font-medium text-muted mb-2">Previous results — peak vs offseason (net · spend)</div>
          <table className="w-full text-body border-collapse">
            <thead>
              <tr className="text-muted text-label text-left">
                <th className="font-normal px-2 py-1">product</th>
                <th className="font-normal px-2 py-1 text-right" title="Each product's most recent completed PEAK week — hover a value for its date">last peak wk</th>
                <th className="font-normal px-2 py-1 text-right" title="Mean of each product's last up-to-4 PEAK weeks — hover a value for the week range">peak avg (4wk)</th>
                <th className="font-normal px-2 py-1 text-right" title="Each product's most recent completed OFF-season week — hover a value for its date">last off wk</th>
                <th className="font-normal px-2 py-1 text-right" title="Mean of each product's last up-to-4 OFF-season weeks — hover a value for the week range">off avg (4wk)</th>
              </tr>
            </thead>
            <tbody>
              {bench.map((b, i) => (
                <tr key={i} className="border-t border-border">
                  <td className="px-2 py-2 font-medium">{b.parent}</td>
                  <td className="px-2 py-2 text-right font-mono text-label"><NetSpend net={b.lastPeakNet} spend={b.lastPeakSpend} title={b.lastPeakWeek ? `week of ${fmtDay(b.lastPeakWeek)}` : 'no peak weeks recorded yet'} /></td>
                  <td className="px-2 py-2 text-right font-mono text-label"><NetSpend net={b.peakAvgNet} spend={b.peakAvgSpend} title={weekTip(b.peakWeeksN, b.peakAvgFrom, b.lastPeakWeek, 'peak')} /></td>
                  <td className="px-2 py-2 text-right font-mono text-label"><NetSpend net={b.lastOffNet} spend={b.lastOffSpend} title={b.lastOffWeek ? `week of ${fmtDay(b.lastOffWeek)}` : 'no offseason weeks recorded yet'} /></td>
                  <td className="px-2 py-2 text-right font-mono text-label"><NetSpend net={b.offAvgNet} spend={b.offAvgSpend} title={weekTip(b.offWeeksN, b.offAvgFrom, b.lastOffWeek, 'offseason')} /></td>
                </tr>
              ))}
            </tbody>
          </table>

          <div className="text-label text-subtle mt-3">
            Fwd net = forward ads-direct $ from profit-scaling cells (excludes organic halo). Benchmarks are completed-week ads net + spend.
            Source: V_PLAN_ESCALATION_SURFACE + V_WEEKLY_PLAN_PRODUCT + V_WEEKLY_PRODUCT_BENCHMARK. Updates when the coacher loop runs.
          </div>
        </>
      )}
    </div>
  );
}

export default ThisWeekPage;
