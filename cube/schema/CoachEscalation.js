// Cube: CoachEscalation - from V_PLAN_ESCALATION (Coacher E net-profit guardrail)
// Per-product escalations the coacher raises to Ori (advisory). Read for the This Week page.
cube(`CoachEscalation`, {
  sql: `SELECT
          CONCAT(parent_name,'|',COALESCE(trigger,''),'|',COALESCE(match_type,''),'|',COALESCE(season,'')) AS id,
          parent_name, scope, season, match_type, intent_class, trigger, severity,
          actual_net, trend_net, spend_vs_cap, recommended_action, evidence
        FROM \`onyga-482313.OI.V_PLAN_ESCALATION\``,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: { type: `count` },
  },

  dimensions: {
    id: { sql: `id`, type: `string`, primaryKey: true },
    parentName: { sql: `parent_name`, type: `string` },
    scope: { sql: `scope`, type: `string` },
    season: { sql: `season`, type: `string` },
    matchType: { sql: `match_type`, type: `string` },
    intentClass: { sql: `intent_class`, type: `string` },
    trigger: { sql: `trigger`, type: `string` },
    severity: { sql: `severity`, type: `string` },
    actualNet: { sql: `actual_net`, type: `number` },
    trendNet: { sql: `trend_net`, type: `number` },
    spendVsCap: { sql: `spend_vs_cap`, type: `number` },
    recommendedAction: { sql: `recommended_action`, type: `string` },
    evidence: { sql: `evidence`, type: `string` },
  },
});
