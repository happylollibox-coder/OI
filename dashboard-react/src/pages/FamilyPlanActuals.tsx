import { planDelta, adRoasSignal } from '../planTypes';
import type { FamilyActual } from '../coachActuals';

interface PlanTarget { dailyCost: number; cpc: number; roas: number }

// The per-family "Plan {mo}: $X/d · CPC $Y" + "Last 7d: …" block from the Actions family panel.
// Spend/CPC are last-7d levers (badged vs plan); ROAS is a measured RESULT → scale/hold/cut per the
// family's own coach mode (NOT vs plan). Returns null when the family has neither a plan nor actuals.
export function FamilyPlanActuals({
  planTarget, actual, mode, planMoLabel,
}: {
  planTarget?: PlanTarget;
  actual?: FamilyActual;
  mode: string;
  planMoLabel: string;
}) {
  const hasPlan = !!planTarget && planTarget.dailyCost > 0;
  const actualDaily = actual?.dailyCost ?? 0;
  const hasActual = actualDaily > 0 || (!!actual && actual.cpc > 0);
  if (!hasPlan && !hasActual) return null;

  // higherIsBetter=false for spend/CPC (over plan = bad/red); within ±10% = on-plan (faint).
  const badge = (av: number, plan: number, higherIsBetter: boolean) => {
    const d = planDelta(av, plan);
    if (d.pct === null) return null;
    const good = higherIsBetter ? d.status !== 'under' : d.status !== 'over';
    const cls = d.status === 'on' ? 'text-faint' : good ? 'text-emerald-400' : 'text-red-400';
    return <span className={cls}>({d.pct >= 0 ? '+' : ''}{Math.round(d.pct * 100)}%)</span>;
  };

  return (
    <>
      {hasPlan && planTarget && (
        <div className="text-[9px] tabular-nums text-faint mb-0.5" title={`Plan inputs for ${planMoLabel} — the levers the coacher steers (daily spend & CPC). ROAS is a measured result, not a plan target.`}>
          <span className="text-blue-400/80 font-semibold">Plan {planMoLabel}:</span>{' '}
          <span className="text-muted">${planTarget.dailyCost.toFixed(0)}</span>/d · CPC <span className="text-muted">${planTarget.cpc.toFixed(2)}</span>
        </div>
      )}
      {hasActual && (
        <div className="text-[9px] tabular-nums text-faint mb-1" title={`Spend/d & CPC = last 7 days (ad), vs the plan levers. ROAS = last 4 weeks ad-only, a RESULT (2-day lag) → coacher reacts per ${mode} mode (scale/hold/cut), not vs plan.`}>
          <span className="text-subtle font-semibold">Last 7d:</span>{' '}
          ${actualDaily.toFixed(0)}/d {hasPlan && planTarget && badge(actualDaily, planTarget.dailyCost, false)}
          {actual && actual.cpc > 0 && <> · CPC ${actual.cpc.toFixed(2)} {hasPlan && planTarget && badge(actual.cpc, planTarget.cpc, false)}</>}
          {actual && actual.roas > 0 && (() => {
            const sig = adRoasSignal(actual.roas, mode).action;
            const roasCls = sig === 'scale' ? 'text-emerald-400' : sig === 'cut' ? 'text-red-400' : 'text-muted';
            const hint = sig === 'scale' ? { t: ' ↑ scale budget', c: 'text-emerald-400/80' }
                       : sig === 'cut'   ? { t: ' ↓ cut spend',     c: 'text-red-400/80' }
                       :                   { t: ' · hold',          c: 'text-faint' };
            return <> · ROAS <span className={roasCls}>{actual.roas.toFixed(2)}×</span><span className={hint.c}>{hint.t}</span></>;
          })()}
          {!hasPlan && <span className="text-faint/60"> · no plan yet</span>}
        </div>
      )}
    </>
  );
}
