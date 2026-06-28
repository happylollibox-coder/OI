// Cube: CoachWeeklyPlanProduct - from V_WEEKLY_PLAN_PRODUCT (Coacher D per-product rollup).
// One row per product x week x horizon. The This Week page reads CURRENT-week rows directly;
// all aggregation lives in the view, so the surface does no math.
cube(`CoachWeeklyPlanProduct`, {
  sql: `SELECT
          CONCAT(week_start,'|',parent_name,'|',horizon) AS id,
          week_start, horizon, parent_name, cells, scale_cells,
          planned_spend, forward_ads_net, probe_map_clicks, purposes
        FROM \`onyga-482313.OI.V_WEEKLY_PLAN_PRODUCT\``,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: { type: `count` },
  },

  dimensions: {
    id: { sql: `id`, type: `string`, primaryKey: true },
    weekStart: { sql: `week_start`, type: `string` },
    horizon: { sql: `horizon`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    cells: { sql: `cells`, type: `number` },
    scaleCells: { sql: `scale_cells`, type: `number` },
    plannedSpend: { sql: `planned_spend`, type: `number` },
    forwardAdsNet: { sql: `forward_ads_net`, type: `number` },
    probeMapClicks: { sql: `probe_map_clicks`, type: `number` },
    purposes: { sql: `purposes`, type: `string` },
  },
});
