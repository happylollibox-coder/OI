// Cube: RunSummary — the Weekly Run front page (V_RUN_SUMMARY live read). Phase 6 Task 2.
// Spec: architecture/WEEKLY_RUN_UX.md. Three sections (CHANGES / HELD / UNCHANGED), one row per
// cell. PASSTHROUGH ONLY — every label, count and $/day is the view's; $/day exists on BUDGET
// moves only (bid-level $/day would be invented precision — the view refuses to fake it and so
// does this cube). Small-table query: the strip must render in seconds.
cube(`RunSummary`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_RUN_SUMMARY\``,
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },
  dimensions: {
    rowId:        { sql: `CONCAT(section, '|', label)`, type: `string`, primaryKey: true },
    section:      { sql: `section`,         type: `string` },   // CHANGES | HELD | UNCHANGED
    label:        { sql: `label`,           type: `string` },
    n:            { sql: `n`,               type: `number` },
    dollarsPerDay:{ sql: `dollars_per_day`, type: `number` },
    detail:       { sql: `detail`,          type: `string` },
  },
});
// cache-bust 2026-08-16: new cube — Weekly Run summary strip
// cache-bust 2026-08-22 (v27.103): bar/SE ladder — UNCHANGED strip now carries AT_BAR / REPRICE /
// LOSER / LAUNCH_CONTAINED labels from V_RUN_SUMMARY (passthrough — no column changes needed)
// cache-bust 2026-08-22b (v27.104): + FLOOR_PROBATION label; LOSER = probation at the floor elapsed
