// Cube: HoldoutArm — the campaigns a holdout trial's HOLDOUT arm holds, from V_HOLDOUT_ARM (live read).
// Feeds the campaign-level hold in DoPage.exportBulksheet: every queued item on one of these campaigns
// is refused, whatever its action (architecture/HOLDOUT.md §6 #2; review of holdout-t2, 2026-10-04).
//
// V_HOLDOUT_ARM keeps a control from its assignment until its trial's gate_to (the view filters
// CURRENT_DATE('America/Los_Angeles') <= gate_to). This cube does NOT filter on gate_from: the export
// holds a control from the assignment on, because no hand change may reach it from the insert
// (plan 2026-10-03-holdout-restart.md Task 8), and a hold one day early costs nothing.
// The arm decides who is held; nothing may recompute it here or in React. Do not add logic to this cube.
cube(`HoldoutArm`, {
  sql: `SELECT campaign_id, trial_id, gate_from, gate_to FROM \`onyga-482313.OI.V_HOLDOUT_ARM\``,

  // LIVE-VIEW cube (EnginePreflight convention): read at export time; 15-min TTL.
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },

  dimensions: {
    campaignId: { sql: `campaign_id`, type: `string`, primaryKey: true },
    trialId:    { sql: `trial_id`,    type: `string` },
    gateFrom:   { sql: `CAST(gate_from AS STRING)`, type: `string` },
    gateTo:     { sql: `CAST(gate_to AS STRING)`,   type: `string` },
  },
});

// cache-bust 2026-10-04: new cube — the holdout arm's campaign-level export hold on the DO page
