/** Display helpers for the research-fit badge on DecisionCards (pure, testable). */

/** Tailwind text-color class for a 0–100 research rank; '' when null (caller hides the badge). */
export function fitBadgeClass(rank: number | null | undefined): string {
  if (rank == null) return '';
  if (rank >= 75) return 'text-emerald-400';
  if (rank >= 40) return 'text-amber-400';
  return 'text-faint';
}

/** "Fit NN" (rounded); '' when null. */
export function fitBadgeLabel(rank: number | null | undefined): string {
  if (rank == null) return '';
  return `Fit ${Math.round(rank)}`;
}
