// Cube: SbLaunchTarget — per-target drill + bid suggestion for Sponsored-Brands launch campaigns, from
// V_SB_LAUNCH_TARGET. Covers keyword-targeted AND product-targeted SB (one row per target, like SP's RunTarget).
// Bid suggestion runs the same launch-controller logic as V_LAUNCH_PHASE1 on SB-native signals. NO per-target
// impr/CTR (undercounted at keyword grain). The card renders these as an expandable list under the SB campaign.
cube(`SbLaunchTarget`, {
  sql: `SELECT campaign_id, target_id, ad_group_id, target_text, target_type, match_type, bid, suggested_bid, bid_action, bid_reason, days_since_suggestion,
               r2_clk, r2_spend, r2_cpc, r2_sales, r2_orders, r2_roas,
               r3_clk, r3_spend, r3_cpc, r3_sales, r3_orders, r3_roas
        FROM \`onyga-482313.OI.V_SB_LAUNCH_TARGET\``,

  // Refresh tied to the SP orchestration (Ori's decision — one trigger): invalidate the cache exactly when
  // SP_REFRESH_CUBE_TABLES completes, so the card reflects the state as of the last orchestration run (not a
  // blind timer). Note: this cube reads live views, so intra-day Fivetran syncs won't appear until the next run.
  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },
  measures: { count: { type: `count` } },

  dimensions: {
    targetId:    { sql: `target_id`,   type: `string`, primaryKey: true },
    campaignId:  { sql: `campaign_id`,  type: `string` },
    adGroupId:   { sql: `ad_group_id`,  type: `string` },
    targetText:  { sql: `target_text`,  type: `string` },
    targetType:  { sql: `target_type`,  type: `string` },
    matchType:   { sql: `match_type`,   type: `string` },
    bid:         { sql: `bid`,          type: `number` },
    suggestedBid:{ sql: `suggested_bid`,type: `number` },
    bidAction:   { sql: `bid_action`,   type: `string` },
    bidReason:   { sql: `bid_reason`,   type: `string` },
    daysSinceSuggestion: { sql: `days_since_suggestion`, type: `number` },
    r2Clk: { sql: `r2_clk`, type: `number` }, r2Spend: { sql: `r2_spend`, type: `number` }, r2Cpc: { sql: `r2_cpc`, type: `number` },
    r2Sales: { sql: `r2_sales`, type: `number` }, r2Orders: { sql: `r2_orders`, type: `number` }, r2Roas: { sql: `r2_roas`, type: `number` },
    r3Clk: { sql: `r3_clk`, type: `number` }, r3Spend: { sql: `r3_spend`, type: `number` }, r3Cpc: { sql: `r3_cpc`, type: `number` },
    r3Sales: { sql: `r3_sales`, type: `number` }, r3Orders: { sql: `r3_orders`, type: `number` }, r3Roas: { sql: `r3_roas`, type: `number` },
  },
});

// cache-bust v2: money-bleeder ladder (0-conversion targets trimmed by clicks, not raised by STARVE)

// cache-bust 2026-07-21: bleeder recency gate (BLEED_STALE)

// cache-bust 2026-07-30c: budget-constrained probing (PARK 90d-orders evidence fix, affordable-CPC trim, no probe while capped)
