import { useEffect, useState } from 'react';
import { cubeLoad } from '../hooks/useCubeData';
import { fM } from '../utils';

type Esc = { parent: string; trigger: string; severity: string; actualNet: number | null; action: string };
type PlanRow = { parent: string; purposes: string; cells: number; spend: number; expNp: number | null };

const npClass = (n: number | null) =>
  n == null ? 'text-zinc-500' : n > 0 ? 'text-emerald-400' : n < 0 ? 'text-red-400' : 'text-zinc-500';
const sevClass = (s: string) =>
  s === 'ESCALATE' ? 'text-red-400' : s === 'WATCH' ? 'text-amber-400' : 'text-zinc-500';
const sevBorder = (s: string) =>
  s === 'ESCALATE' ? 'border-l-red-500' : s === 'WATCH' ? 'border-l-amber-500' : 'border-l-zinc-500';

export function ThisWeekPage() {
  const [esc, setEsc] = useState<Esc[]>([]);
  const [plan, setPlan] = useState<PlanRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const e = await cubeLoad({
          dimensions: ['CoachEscalation.parentName', 'CoachEscalation.trigger', 'CoachEscalation.severity',
            'CoachEscalation.actualNet', 'CoachEscalation.recommendedAction'],
        });
        const p = await cubeLoad({
          dimensions: ['CoachWeeklyPlan.parentName', 'CoachWeeklyPlan.purpose',
            'CoachWeeklyPlan.plannedSpendDim', 'CoachWeeklyPlan.expectedNetProfit'],
          filters: [{ member: 'CoachWeeklyPlan.horizon', operator: 'equals', values: ['CURRENT'] }],
        });
        if (!alive) return;
        const er = e as Record<string, unknown>[];
        setEsc(er.map(r => ({
          parent: String(r['CoachEscalation.parentName'] ?? ''),
          trigger: String(r['CoachEscalation.trigger'] ?? '').replace(/_/g, ' ').toLowerCase(),
          severity: String(r['CoachEscalation.severity'] ?? ''),
          actualNet: r['CoachEscalation.actualNet'] != null ? Number(r['CoachEscalation.actualNet']) : null,
          action: String(r['CoachEscalation.recommendedAction'] ?? ''),
        })).sort((a, b) => a.severity.localeCompare(b.severity) || a.parent.localeCompare(b.parent)));

        const byP: Record<string, PlanRow> = {};
        for (const r of p as Record<string, unknown>[]) {
          const k = String(r['CoachWeeklyPlan.parentName'] ?? '');
          if (!k) continue;
          (byP[k] ??= { parent: k, purposes: '', cells: 0, spend: 0, expNp: null });
          byP[k].cells++;
          byP[k].spend += Number(r['CoachWeeklyPlan.plannedSpendDim'] ?? 0);
          if (r['CoachWeeklyPlan.expectedNetProfit'] != null) byP[k].expNp = Number(r['CoachWeeklyPlan.expectedNetProfit']);
          const pu = String(r['CoachWeeklyPlan.purpose'] ?? '').toLowerCase();
          if (pu && !byP[k].purposes.includes(pu)) byP[k].purposes += (byP[k].purposes ? ' · ' : '') + pu;
        }
        setPlan(Object.values(byP).sort((a, b) => a.parent.localeCompare(b.parent)));
        setLoading(false);
      } catch (ex) {
        if (alive) { setErr(String(ex)); setLoading(false); }
      }
    })();
    return () => { alive = false; };
  }, []);

  return (
    <div className="max-w-4xl mx-auto px-4 py-6 text-text">
      <div className="flex items-baseline justify-between mb-4">
        <h1 className="text-title font-medium">This week</h1>
        <span className="text-label text-muted">coacher · ads-attributed net</span>
      </div>

      {loading && <div className="text-body text-muted">Loading…</div>}
      {err && <div className="text-body text-red-400">Couldn't load coacher data: {err}</div>}

      {!loading && !err && (
        <>
          <div className="text-label font-medium text-muted mb-2">Needs your attention</div>
          {esc.length === 0 && <div className="text-body text-muted mb-6">Nothing escalated — on plan.</div>}
          <div className="flex flex-col gap-2 mb-8">
            {esc.map((e, i) => (
              <div key={i} className={`flex items-center gap-3 bg-card border border-border border-l-4 ${sevBorder(e.severity)} rounded-r-xl px-4 py-3`}>
                <span className={`text-label font-medium uppercase tracking-wide ${sevClass(e.severity)}`}>{e.severity.toLowerCase()}</span>
                <div className="flex-1 text-body"><span className="font-medium">{e.parent}</span> <span className="text-muted">· {e.trigger}</span></div>
                <div className={`font-mono font-medium w-16 text-right ${npClass(e.actualNet)}`}>{fM(e.actualNet)}</div>
                <div className="text-muted text-label w-56">{e.action}</div>
              </div>
            ))}
          </div>

          <div className="text-label font-medium text-muted mb-2">This week's plan</div>
          <table className="w-full text-body border-collapse">
            <thead>
              <tr className="text-muted text-label text-left">
                <th className="font-normal px-2 py-1">product</th>
                <th className="font-normal px-2 py-1">purposes</th>
                <th className="font-normal px-2 py-1 text-right">cells</th>
                <th className="font-normal px-2 py-1 text-right">planned spend</th>
                <th className="font-normal px-2 py-1 text-right">expected net</th>
              </tr>
            </thead>
            <tbody>
              {plan.map((p, i) => (
                <tr key={i} className="border-t border-border">
                  <td className="px-2 py-2 font-medium">{p.parent}</td>
                  <td className="px-2 py-2 text-muted">{p.purposes}</td>
                  <td className="px-2 py-2 text-right font-mono">{p.cells}</td>
                  <td className="px-2 py-2 text-right font-mono">{fM(p.spend)}</td>
                  <td className={`px-2 py-2 text-right font-mono ${npClass(p.expNp)}`}>{fM(p.expNp)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <div className="text-label text-subtle mt-3">Source: V_PLAN_ESCALATION + DE_WEEKLY_PLAN. Updates when the coacher loop runs.</div>
        </>
      )}
    </div>
  );
}

export default ThisWeekPage;
