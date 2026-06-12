// Cube: PpcActionOutcomes - from V_PPC_ACTION_OUTCOMES
// ONE ROW PER LOGGED PPC CHANGE (FACT_PPC_CHANGE_LOG, last 180 days)
// Pre/post window outcome scoring — Decision Scorecard on the DO page.
// SOP: architecture/PPC_CLOSE_THE_LOOP.md
cube(`PpcActionOutcomes`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_PPC_ACTION_OUTCOMES\``,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: { type: `count`, description: `Number of logged changes` },
    improvedCount: {
      type: `count`,
      filters: [{ sql: `${CUBE}.verdict = 'IMPROVED'` }],
      description: `Changes scored IMPROVED`,
    },
    worseCount: {
      type: `count`,
      filters: [{ sql: `${CUBE}.verdict = 'WORSE'` }],
      description: `Changes scored WORSE`,
    },
    tooEarlyCount: {
      type: `count`,
      filters: [{ sql: `${CUBE}.verdict = 'TOO_EARLY'` }],
      description: `Changes still inside the post window`,
    },
    noDataCount: {
      type: `count`,
      filters: [{ sql: `${CUBE}.verdict = 'NO_DATA'` }],
      description: `Changes with no matching ads data`,
    },
    scoreableCount: {
      type: `count`,
      filters: [{ sql: `${CUBE}.verdict IN ('IMPROVED', 'WORSE')` }],
      description: `Changes with a final verdict`,
    },
    accuracyPct: {
      sql: `SAFE_DIVIDE(COUNTIF(${CUBE}.verdict = 'IMPROVED'), NULLIF(COUNTIF(${CUBE}.verdict IN ('IMPROVED', 'WORSE')), 0)) * 100`,
      type: `number`,
      description: `Coach accuracy: IMPROVED / (IMPROVED + WORSE), percent`,
    },
    totalWeeklySavings: {
      sql: `${CUBE}.weekly_savings`,
      type: `sum`,
      filters: [{ sql: `${CUBE}.action_group IN ('NEGATE', 'PAUSE_TARGET') AND ${CUBE}.verdict = 'IMPROVED'` }],
      description: `Sum of weekly spend saved by IMPROVED negates/pauses`,
    },
  },

  dimensions: {
    changeId: { sql: `change_id`, type: `string`, primaryKey: true, shown: true },
    batchId: { sql: `batch_id`, type: `string` },
    appliedAt: { sql: `applied_at`, type: `time`, description: `When the change was marked uploaded (UTC)` },
    changeDate: { sql: `CAST(change_date AS TIMESTAMP)`, type: `time`, description: `LA-local change date used for windows` },
    action: { sql: `action`, type: `string` },
    actionGroup: { sql: `action_group`, type: `string`, description: `NEGATE / PAUSE_TARGET / BID_DOWN / BID_UP / PROMOTE / BUDGET_UP / BUDGET_DOWN / OTHER` },
    verdict: { sql: `verdict`, type: `string`, description: `IMPROVED / WORSE / NO_DATA / TOO_EARLY` },
    searchTerm: { sql: `search_term`, type: `string` },
    targeting: { sql: `targeting`, type: `string` },
    keywordId: { sql: `keyword_id`, type: `string` },
    matchType: { sql: `match_type`, type: `string` },
    campaignId: { sql: `campaign_id`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    product: { sql: `product`, type: `string` },
    source: { sql: `source`, type: `string`, description: `COACH or MANUAL` },
    coachMode: { sql: `coach_mode`, type: `string`, description: `Coach mode at decision time` },

    // Old → new values
    oldBid: { sql: `old_bid`, type: `number` },
    newBid: { sql: `new_bid`, type: `number` },
    oldBudget: { sql: `old_budget`, type: `number` },
    newBudget: { sql: `new_budget`, type: `number` },

    // Coach snapshot at decision time
    targetSpend8w: { sql: `target_spend_8w`, type: `number` },
    targetOrders8w: { sql: `target_orders_8w`, type: `number` },
    targetNetRoas8w: { sql: `target_net_roas_8w`, type: `number` },

    // Pre/post window comparison
    postDaysElapsed: { sql: `post_days_elapsed`, type: `number`, description: `Complete post-window days available (max 14)` },
    preSpend: { sql: `pre_spend`, type: `number` },
    preOrders: { sql: `pre_orders`, type: `number` },
    preNetRoas: { sql: `pre_net_roas`, type: `number` },
    preNetProfit: { sql: `pre_net_profit`, type: `number` },
    preSpendPerDay: { sql: `pre_spend_per_day`, type: `number` },
    preOrdersPerDay: { sql: `pre_orders_per_day`, type: `number` },
    postSpend: { sql: `post_spend`, type: `number` },
    postOrders: { sql: `post_orders`, type: `number` },
    postNetRoas: { sql: `post_net_roas`, type: `number` },
    postNetProfit: { sql: `post_net_profit`, type: `number` },
    postSpendPerDay: { sql: `post_spend_per_day`, type: `number` },
    postOrdersPerDay: { sql: `post_orders_per_day`, type: `number` },
    netRoasDelta: { sql: `net_roas_delta`, type: `number` },
    weeklySavings: { sql: `weekly_savings`, type: `number`, description: `Pre-window weekly burn rate (negate savings estimate)` },

    // Decision-card target wiring (2026-06-12)
    expectedImpactWeekly: { sql: `expected_impact_weekly`, type: `number`, description: `Decision-card weekly $ target (save or earn)` },
    expectedImpactKind: { sql: `expected_impact_kind`, type: `string`, description: `'save' or 'earn' — which direction the target applies` },
    actualWeeklyImpact: { sql: `actual_weekly_impact`, type: `number`, description: `Realised $/wk (save=pre weekly burn; earn=post net-profit/wk)` },
    targetStatus: { sql: `target_status`, type: `string`, description: `NO_TARGET / TOO_EARLY / TARGET_MET / BELOW_TARGET` },
  },
});
