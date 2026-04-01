/**
 * strategyRules.ts
 *
 * All decision logic lives in V_EXPERIMENT_TERM_RECOMMENDATIONS.sql.
 * The frontend only renders the backend-provided decision_trace — no re-simulation.
 * This file re-exports types and a helper to read the trace from an ActionRow.
 */
import type { ActionRow, DecisionStep } from '../types';

export type ActionType = 'KEEP' | 'STOP' | 'REDUCE_BID' | 'INCREASE_BID' | 'PROMOTE_TO_EXACT' | 'START' | 'MONITOR';

/**
 * Read the backend-provided decision trace from an ActionRow.
 * Returns null if the trace isn't available (e.g., older cached data).
 */
export function getTraceFromRow(row: ActionRow): DecisionStep[] | null {
  return row.decision_trace ?? null;
}
