/** A budget row that should appear in the 💰 Budget section (excludes the BUDGET_OK no-op). */
export function isBudgetRow(r: { action_type?: string | null; action?: string | null }): boolean {
  return r.action_type === 'BUDGET' && r.action !== 'BUDGET_OK';
}

/** $/day trimmed by a budget decrease (current − recommended); 0 when unknown or an increase. */
export function budgetTrimPerDay(r: { current_budget?: number | null; recommended_budget?: number | null }): number {
  const cur = r.current_budget ?? null;
  const rec = r.recommended_budget ?? null;
  if (cur == null || rec == null) return 0;
  return Math.max(0, cur - rec);
}

export type BaseAction = { action: string; recommended_bid: number | null };

/**
 * Translate a launch decision into the base bulksheet operation queued for it.
 * HOLD / GRADUATE are no-ops (null = not queueable).
 * NEGATE routes by target type: SP-Auto clauses / product targets → STOP_TARGET; keywords → NEGATE_TERM.
 */
export function launchToBaseAction(r: {
  launch_decision?: string | null;
  launch_recommended_bid?: number | null;
  match_type?: string | null;
  targeting?: string | null;
}): BaseAction | null {
  switch (r.launch_decision) {
    case 'LAUNCH_REDUCE_BID':
      return { action: 'REDUCE_BID', recommended_bid: r.launch_recommended_bid ?? null };
    case 'LAUNCH_NEGATE': {
      const isAutoOrProduct =
        r.match_type === 'Automatic' || (r.targeting ?? '').toLowerCase().startsWith('asin=');
      return { action: isAutoOrProduct ? 'STOP_TARGET' : 'NEGATE_TERM', recommended_bid: null };
    }
    default:
      return null; // LAUNCH_HOLD, LAUNCH_GRADUATE, undefined
  }
}

export type SectionSummary = { count: number; dollars: number; queueable: number; queued: number };

/** Roll up a section's rows: total count, summed dollars, how many are queueable vs already queued. */
export function summarizeSection<T>(
  rows: T[],
  dollarsOf: (r: T) => number,
  isQueueable: (r: T) => boolean,
  isQueued: (r: T) => boolean,
): SectionSummary {
  let dollars = 0, queueable = 0, queued = 0;
  for (const r of rows) {
    dollars += dollarsOf(r) || 0;
    if (isQueued(r)) queued += 1;
    else if (isQueueable(r)) queueable += 1;
  }
  return { count: rows.length, dollars, queueable, queued };
}
