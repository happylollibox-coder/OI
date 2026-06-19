// Split the Decision Scorecard into two sections:
//   pending — verdict still TOO_EARLY (the 7 post-change days haven't all settled
//             yet), sorted by creation date ASC (oldest first → closest to ready).
//   settled — every other verdict (IMPROVED / WORSE / NO_DATA: the post window is
//             done), sorted by creation date DESC (newest decision first).
// "Creation date" = applied_at (when the change was uploaded).

export interface ScorecardSplitRow {
  verdict: string;
  applied_at: string | null;
}

const createdTs = (r: ScorecardSplitRow): number =>
  r.applied_at ? Date.parse(r.applied_at) : 0;

export function splitOutcomes<T extends ScorecardSplitRow>(
  rows: T[],
): { pending: T[]; settled: T[] } {
  const pending = rows
    .filter(r => r.verdict === 'TOO_EARLY')
    .sort((a, b) => createdTs(a) - createdTs(b)); // creation asc
  const settled = rows
    .filter(r => r.verdict !== 'TOO_EARLY')
    .sort((a, b) => createdTs(b) - createdTs(a)); // creation desc
  return { pending, settled };
}
