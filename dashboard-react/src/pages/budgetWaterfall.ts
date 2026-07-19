// Pure budget-waterfall helpers for the Weekly Run Step-1 panel. Mirrors the SQL in
// V_FAMILY_BUDGET_ALLOCATION / V_BUDGET_TOTAL_SUGGESTION so the panel can recompute the split live as
// Ori changes the total or the proven% dial — no backend round-trip per keystroke.

export type FamilyWeight = { parentName: string; weight: number; netProfit: number | null };
export type FamilyAlloc = { parentName: string; allocated: number };

// Total daily budget → per-family daily budget: floor + winners-take-the-rest by weight.
// If no family has positive weight, the pot splits equally (matches the SQL divide-by-zero guard).
export function splitFamilies(families: FamilyWeight[], total: number, floor: number): FamilyAlloc[] {
  const n = families.length;
  if (n === 0) return [];
  const pot = total - floor * n;
  const totW = families.reduce((s, f) => s + Math.max(f.weight, 0), 0);
  return families.map(f => {
    const share = totW > 0 ? Math.max(f.weight, 0) / totW : 1 / n;
    return { parentName: f.parentName, allocated: Math.round((floor + pot * share) * 100) / 100 };
  });
}

// Profit-shaped suggested total: proven (margin-or-winning) spend is `provenPct`% of the budget, so the
// total is sized as marginSpend / (provenPct/100). Higher proven% → smaller total (concentrate on winners).
export function suggestedTotal(marginDailySpend: number, provenPct: number): number {
  if (provenPct <= 0) return 0;
  return Math.round(marginDailySpend / (provenPct / 100));
}

// A manual per-family override (a DAILY number) replaces the waterfall value and re-flags the source.
export type FamilyRow = { parentName: string; allocated: number; source: 'WATERFALL' | 'MANUAL' };
export function applyOverrides(rows: FamilyRow[], overrides: Record<string, number>): FamilyRow[] {
  return rows.map(r => overrides[r.parentName] != null
    ? { ...r, allocated: overrides[r.parentName], source: 'MANUAL' }
    : r);
}

export function splitSummary(rows: { allocated: number }[], cap: number) {
  const total = Math.round(rows.reduce((s, r) => s + r.allocated, 0));
  return { total, families: rows.length, overCap: total > cap + 1 };
}
