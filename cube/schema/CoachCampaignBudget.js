// Cube: CoachCampaignBudget - from V_COACH_CAMPAIGN_BUDGET (Coacher F budget apply set, one row per campaign).
// The Weekly Run inline Budget phase reads these per family to review + queue campaign daily-budget changes.
cube(`CoachCampaignBudget`, {
  sql: `SELECT
          parent_name, campaign_id, campaign_name, campaign_type, budget_action,
          current_budget, recommended_budget, util_pct, is_change
        FROM \`onyga-482313.OI.T_COACH_CAMPAIGN_BUDGET\``,

  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },

  measures: {
    count: { type: `count` },
  },

  dimensions: {
    id: { sql: `campaign_id`, type: `string`, primaryKey: true },
    parentName: { sql: `parent_name`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    budgetAction: { sql: `budget_action`, type: `string` },
    currentBudget: { sql: `current_budget`, type: `number` },
    recommendedBudget: { sql: `recommended_budget`, type: `number` },
    utilPct: { sql: `util_pct`, type: `number` },
    isChange: { sql: `is_change`, type: `boolean` },
  },
});
