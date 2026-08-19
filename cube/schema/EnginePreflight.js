// Cube: EnginePreflight — the day's judged proposal snapshot, one row per live engine instruction,
// from V_ENGINE_PREFLIGHT (live read). Feeds the export-time gate in DoPage.exportBulksheet.
// Spec: architecture/ENGINE_PREFLIGHT.md (the checks, engine precedence, and the generator contract).
//
// verdict: GO | EXCLUDE (single-owner loser or no-op — never uploaded)
//          | REVIEW (settled-winner cut or >$2 bid — exports only after an explicit per-item confirm).
//
// The verdicts are SP_ENGINE_PREFLIGHT's, stamped at snapshot time — labels only. The generator
// LOOKS THEM UP by (campaign, keyword, lever); nothing may recompute one here or in React, or the
// gate and the judged snapshot drift apart. Do not add logic to this cube.
cube(`EnginePreflight`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_ENGINE_PREFLIGHT\``,

  // LIVE-VIEW cube (ParkReverdict / KeywordLift / OobBudget convention): the snapshot is re-judged
  // daily by the orchestrator, but the gate reads it AT EXPORT TIME and view fixes don't move the
  // orchestration stamp — 15-min TTL.
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },

  dimensions: {
    // (campaign, keyword, lever) is the SP's conflict domain; engine disambiguates the losers —
    // when several engines instruct the same (key, lever), each keeps its own judged row.
    // v27.72: target_text joins the key — NEGATE rows have no keyword_id, and without the term
    // every negate in a campaign collapses into ONE primary key (the cube silently dedupes).
    rowId:           { sql: `CONCAT(campaign_id, '|', COALESCE(keyword_id, ''), '|', COALESCE(target_text, ''), '|', lever, '|', engine)`, type: `string`, primaryKey: true },
    campaignId:      { sql: `campaign_id`,      type: `string` },
    campaignName:    { sql: `campaign_name`,    type: `string` },
    keywordId:       { sql: `keyword_id`,       type: `string` },   // NULL on budget rows
    targetText:      { sql: `target_text`,      type: `string` },
    lever:           { sql: `lever`,            type: `string` },   // BID | BUDGET
    grain:           { sql: `grain`,            type: `string` },   // BID | BUDGET | REVIVE
    engine:          { sql: `engine`,           type: `string` },
    ownerEngine:     { sql: `owner_engine`,     type: `string` },   // who kept the (key, lever) when this row lost
    action:          { sql: `action`,           type: `string` },
    matchType:       { sql: `match_type`,       type: `string` },
    channel:         { sql: `channel`,          type: `string` },   // SP | SB
    currentBid:      { sql: `current_bid`,      type: `number` },
    suggestedBid:    { sql: `suggested_bid`,    type: `number` },
    currentBudget:   { sql: `current_budget`,   type: `number` },
    suggestedBudget: { sql: `suggested_budget`, type: `number` },
    reason:          { sql: `reason`,           type: `string` },   // the engine's full why (view-authored)
    verdict:         { sql: `verdict`,          type: `string` },   // GO | EXCLUDE | REVIEW
    verdictReason:   { sql: `verdict_reason`,   type: `string` },   // plain-English, from the SP
    // Phase 6 Task 1: the upload key (the feed queues directly from the gate) + the 5-second why
    // (authored per-view, NULL until each view's Task-3 rollout — the feed falls back to reason)
    adGroupId:       { sql: `ad_group_id`,      type: `string` },
    reasonShort:     { sql: `reason_short`,     type: `string` },
    snapshotDate:    { sql: `CAST(snapshot_date AS STRING)`, type: `string` },
  },
});

// cache-bust 2026-08-16: new cube — engine preflight verdicts / export-time gate on the DO page
// cache-bust 2026-08-16b: Phase 6 feed passthroughs (grain, matchType, channel, currentBid,
// currentBudget, reason) — columns were already in V_ENGINE_PREFLIGHT, the cube just never exposed them
