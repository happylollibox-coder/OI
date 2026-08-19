// Cube: LaunchBidLadder — the launch exemption's gentle bid search, from V_LAUNCH_BID_LADDER
// (live read). Feeds the bid-ladder table inside the Weekly Run "Launch exemption" panel.
// Spec: architecture/LAUNCH_EXEMPTION.md §8
//
// EVERY verdict here is decided in the VIEW: the judged window (V_PEAK_WINDOW_RULE — 7 days off
// peak, 3 in peak), the GP-ROAS band, the trim factor, the anchor, the per-format bid floor, the
// proposed bid and the reason sentence. The panel PRINTS them. Do not rebuild any of it here or in
// TypeScript — no thresholds, no arithmetic, no verdicts, no prose.
//
// LIVE-VIEW cube (LaunchExemption / OobBudget convention): the ladder re-reads the last 3–7 days of
// FACT_AMAZON_ADS every day and view fixes don't move the orchestration stamp — 15-min TTL.
cube(`LaunchBidLadder`, {
  sql: `SELECT
          CONCAT(campaign_id, '|', keyword_id) AS row_key,
          family, campaign_id, campaign_name, campaign_type, ad_group_id, keyword_id,
          targeting, match_type,
          CAST(last_day AS STRING)     AS last_day,
          CAST(window_start AS STRING) AS window_start,
          CAST(window_end AS STRING)   AS window_end,
          judged_window_days, in_peak, occurrence_type, w_days_reason,
          d1_spend, d1_gp, d1_gp_roas, d1_clicks, d1_orders,
          w_spend, w_gp, w_gp_roas, w_clicks, w_orders, evidence_grade,
          campaign_settled_gp_roas, campaign_settled_clicks, campaign_protected_winner,
          gp_roas_band, band_trim_pct,
          current_bid, launch_bid, launch_bid_source, anchor_bid, anchor_source,
          bid_floor, bid_floor_source, proposed_bid,
          above_launch_bid, runs_to_launch_bid, ceiling_step_bid, floor_binding,
          bid_change_pct, bid_cut_dollars,
          ladder_action, is_proposal,
          launch_phase, launch_decision, coach_target_action, coach_recommended_bid,
          conflicts_with_coach,
          CAST(exempt_until AS STRING) AS exempt_until,
          ladder_reason
        FROM \`onyga-482313.OI.V_LAUNCH_BID_LADDER\``,

  refreshKey: { every: '15 minutes' },

  measures: {
    count:        { type: `count` },
    proposals:    { sql: `IF(is_proposal, 1, 0)`, type: `sum` },
    bidCutTotal:  { sql: `bid_cut_dollars`, type: `sum` },
  },

  // NOTE: `sql` above is wrapped as a subquery by Cube, so dimensions reference the OUTPUT column
  // names — no table aliases, they are not visible outside the subquery.
  dimensions: {
    rowKey:       { sql: `row_key`, type: `string`, primaryKey: true },
    family:       { sql: `family`, type: `string` },
    campaignId:   { sql: `campaign_id`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    adGroupId:    { sql: `ad_group_id`, type: `string` },
    keywordId:    { sql: `keyword_id`, type: `string` },
    targeting:    { sql: `targeting`, type: `string` },
    matchType:    { sql: `match_type`, type: `string` },

    // the judged window — decided in V_PEAK_WINDOW_RULE
    lastDay:          { sql: `last_day`, type: `string` },
    windowStart:      { sql: `window_start`, type: `string` },
    windowEnd:        { sql: `window_end`, type: `string` },
    judgedWindowDays: { sql: `judged_window_days`, type: `number` },
    inPeak:           { sql: `in_peak`, type: `boolean` },
    occurrenceType:   { sql: `occurrence_type`, type: `string` },
    wDaysReason:      { sql: `w_days_reason`, type: `string` },

    // evidence: last day, then the window the band is taken on
    d1Spend:  { sql: `d1_spend`, type: `number` },
    d1Gp:     { sql: `d1_gp`, type: `number` },
    d1GpRoas: { sql: `d1_gp_roas`, type: `number` },
    d1Clicks: { sql: `d1_clicks`, type: `number` },
    d1Orders: { sql: `d1_orders`, type: `number` },
    wSpend:   { sql: `w_spend`, type: `number` },
    wGp:      { sql: `w_gp`, type: `number` },
    wGpRoas:  { sql: `w_gp_roas`, type: `number` },
    wClicks:  { sql: `w_clicks`, type: `number` },
    wOrders:  { sql: `w_orders`, type: `number` },
    evidenceGrade: { sql: `evidence_grade`, type: `string` },

    campaignSettledGpRoas:    { sql: `campaign_settled_gp_roas`, type: `number` },
    campaignSettledClicks:    { sql: `campaign_settled_clicks`, type: `number` },
    campaignProtectedWinner:  { sql: `campaign_protected_winner`, type: `boolean` },

    // the ladder
    gpRoasBand:      { sql: `gp_roas_band`, type: `string` },
    bandTrimPct:     { sql: `band_trim_pct`, type: `number` },
    currentBid:      { sql: `current_bid`, type: `number` },
    launchBid:       { sql: `launch_bid`, type: `number` },
    launchBidSource: { sql: `launch_bid_source`, type: `string` },
    anchorBid:       { sql: `anchor_bid`, type: `number` },
    anchorSource:    { sql: `anchor_source`, type: `string` },
    bidFloor:        { sql: `bid_floor`, type: `number` },
    bidFloorSource:  { sql: `bid_floor_source`, type: `string` },
    proposedBid:     { sql: `proposed_bid`, type: `number` },
    aboveLaunchBid:  { sql: `above_launch_bid`, type: `boolean` },
    runsToLaunchBid: { sql: `runs_to_launch_bid`, type: `number` },
    ceilingStepBid:  { sql: `ceiling_step_bid`, type: `number` },
    floorBinding:    { sql: `floor_binding`, type: `boolean` },
    bidChangePct:    { sql: `bid_change_pct`, type: `number` },
    bidCutDollars:   { sql: `bid_cut_dollars`, type: `number` },
    ladderAction:    { sql: `ladder_action`, type: `string` },
    isProposal:      { sql: `is_proposal`, type: `boolean` },

    // the coach's own standing bid decision — published, never overridden
    launchPhase:         { sql: `launch_phase`, type: `string` },
    launchDecision:      { sql: `launch_decision`, type: `string` },
    coachTargetAction:   { sql: `coach_target_action`, type: `string` },
    coachRecommendedBid: { sql: `coach_recommended_bid`, type: `number` },
    conflictsWithCoach:  { sql: `conflicts_with_coach`, type: `boolean` },

    exemptUntil:  { sql: `exempt_until`, type: `string` },
    ladderReason: { sql: `ladder_reason`, type: `string` },
  },
});
