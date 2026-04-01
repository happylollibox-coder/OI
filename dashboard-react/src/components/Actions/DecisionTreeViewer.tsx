import type { ActionRow, DecisionStep } from '../../types';
import { getTraceFromRow } from '../../utils/strategyRules';
import { CheckCircle2, XCircle, Shield } from 'lucide-react';

export function DecisionTreeViewer({ row }: { row: ActionRow }) {
  let steps = getTraceFromRow(row);

  // Deduplicate and filter profitability checks
  // The backend might evaluate Profitability, Heavy Loss, and Marginal Loss.
  // We only want to show the ONE that passed/triggered the action.
  if (steps && steps.length > 0) {
    const isLossCheck = (s: DecisionStep) => s.label.includes('Loss') || s.label.includes('Profitability');
    const lossSteps = steps.filter(isLossCheck);
    
    if (lossSteps.length > 1) {
      // Find the one that passed (or the first one if none passed)
      const passedLossStep = lossSteps.find(s => s.pass) || lossSteps[0];
      // Keep all non-loss steps, plus just the single passed loss step
      steps = steps.filter(s => !isLossCheck(s) || s.id === passedLossStep.id);
    }
  }

  // Fallback if no backend trace available (older cached data)
  if (!steps || steps.length === 0) {
    return (
      <div className="mt-2.5 mb-1 text-[10px] text-faint italic">
        Decision trace not available — refresh data.
      </div>
    );
  }

  return (
    <div className="mt-2.5 mb-1">
      <div className="text-[9px] uppercase tracking-wider text-faint font-bold mb-1.5 flex items-center gap-2">
        <span>Decision Trace</span>
        <span className="bg-surface px-1.5 py-px rounded text-[8px] border border-border-faint">
          {row.strategy_id || 'DEFAULT'}
        </span>
        {row.is_top_of_page_organic && (
          <span className="inline-flex items-center gap-0.5 px-1.5 py-px rounded text-[8px] border border-amber-500/30 bg-amber-500/10 text-amber-400">
            <Shield size={8} strokeWidth={2.5} /> TOP OF PAGE
          </span>
        )}
      </div>
      <div className="flex flex-wrap items-center gap-1">
        {steps.map((s: DecisionStep, i: number) => (
          <div key={s.id} className="flex items-center gap-1">
            {i > 0 && <span className="text-[8px] text-faint mx-0.5">→</span>}
            {(() => {
              // A check is "positive" if it passes AND it's not a negative condition (like 'Loss').
              // A "Heavy Loss" passing is a bad thing, so it should be red.
              const isNegativeCondition = s.label.includes('Loss') || s.label.includes('Wasted Spend');
              const isGood = s.pass && !isNegativeCondition;
              const isBad = (!s.pass && !isNegativeCondition) || (s.pass && isNegativeCondition);
              
              return (
                <div className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[9px] border ${
                  isGood
                    ? 'border-emerald-500/25 bg-emerald-500/5 text-emerald-400'
                    : isBad
                    ? 'border-rose-500/25 bg-rose-500/5 text-rose-400'
                    : 'border-amber-500/25 bg-amber-500/5 text-amber-400'
                }`}>
                  {isGood
                    ? <CheckCircle2 size={9} strokeWidth={2.5} />
                    : <XCircle size={9} strokeWidth={2.5} />}
                  <span className="font-medium">{s.label}</span>
                  <span className="font-mono text-[8px] opacity-70">{s.value}</span>
                </div>
              );
            })()}
          </div>
        ))}
        {/* Final action badge */}
        <span className="text-[8px] text-faint mx-0.5">→</span>
        <span className={`inline-flex items-center px-2 py-0.5 rounded text-[10px] font-bold tracking-wider border ${
          row.action === 'STOP' || row.action === 'REDUCE_BID'
            ? 'border-rose-500/30 bg-rose-500/10 text-rose-400'
            : row.action === 'KEEP' || row.action === 'MONITOR'
            ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-400'
            : 'border-blue-500/30 bg-blue-500/10 text-blue-400'
        }`}>
          {row.action}
        </span>
      </div>
    </div>
  );
}
