// Cube: ParkReverdict — settled re-judgment of every parked / STOPped / recently-revived keyword,
// from V_PARK_REVERDICT (live read). Feeds the "Revivals" panel on Weekly Run.
// Spec: architecture/SEASON_CONTEXT_LEDGER.md §7 (doctrine + calibration) and §7.11 (this surface).
//
// reverdict: REVIVE (settled record overturns the park) | CONFIRM_PARK | PENDING_SETTLE
//            | INSUFFICIENT | NULL (row_kind = 'LIVE' — not parked, nothing to re-judge).
//
// V_PARK_REVERDICT is keyed on DIM_KEYWORD config and carries no campaign_name / family, so the two
// LABEL joins below fill them in — the same pair V_CHANGE_SCORECARD uses. Labels only: the reverdict,
// the revive bid and every guard flag are decided in the VIEW and must stay there. Do not rebuild
// V_PARK_REVERDICT and do not move any of its logic here.
cube(`ParkReverdict`, {
  sql: `SELECT r.campaign_id, r.keyword_id, r.ad_group_id, r.keyword_text, r.match_type, r.channel,
               r.is_pt, r.current_bid, r.pre_park_bid, r.season_relax_applied,
               CAST(r.park_date AS STRING) park_date, r.park_source, r.park_era, r.n_park_events,
               CAST(r.settle_due AS STRING) settle_due, CAST(r.settled_through AS STRING) settled_through,
               r.s90_clk, r.s90_sp, r.s90_ord, r.s90_gp, r.s90_gp_roas, r.s90_cpc,
               r.life_settled_clk, r.n_win, r.win_labels, r.context_label,
               r.stop_released, r.re_parked_this_occ, r.manual_parked_recent,
               r.revive_settling, r.engine_immune, r.immune_reason,
               r.revive_bid, r.reverdict, r.reverdict_reason,
               dc.campaign_name, fam.parent_name AS family
        FROM \`onyga-482313.OI.V_PARK_REVERDICT\` r
        LEFT JOIN \`onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT\` dc
          ON CAST(dc.campaign_id AS STRING) = CAST(r.campaign_id AS STRING)
        LEFT JOIN \`onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP\` fam
          ON CAST(fam.campaign_id AS STRING) = CAST(r.campaign_id AS STRING)`,

  // LIVE-VIEW cube (KeywordLift / OobBudget / PausedHistory convention): the reverdict re-reads the
  // settled record daily and view fixes don't move the orchestration stamp — 15-min TTL.
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },

  // NOTE: `sql` above is wrapped as a subquery by Cube, so dimensions must reference the OUTPUT
  // column names (no `r.` / `dc.` prefixes — those aliases are not visible outside the subquery).
  dimensions: {
    rowId:        { sql: `CONCAT(campaign_id, '|', keyword_id)`, type: `string`, primaryKey: true },
    campaignId:   { sql: `campaign_id`,     type: `string` },
    campaignName: { sql: `campaign_name`,   type: `string` },
    family:       { sql: `family`,          type: `string` },
    keywordId:    { sql: `keyword_id`,      type: `string` },
    // v27.63: the panel queues revivals now, and a bulksheet row without an ad group is rejected by
    // Amazon — 18 of today's 25 REVIVE rows are SB, the exact case useDoQueue documents. The view
    // has always emitted it; the cube simply never selected it. Pure passthrough.
    adGroupId:    { sql: `ad_group_id`,     type: `string` },
    keywordText:  { sql: `keyword_text`,    type: `string` },
    matchType:    { sql: `match_type`,      type: `string` },
    channel:      { sql: `channel`,         type: `string` },
    isPt:         { sql: `is_pt`,           type: `boolean` },
    currentBid:   { sql: `current_bid`,     type: `number` },
    preParkBid:   { sql: `pre_park_bid`,    type: `number` },
    parkDate:     { sql: `park_date`,       type: `string` },
    parkSource:   { sql: `park_source`,     type: `string` },   // COACH | MANUAL
    parkEra:      { sql: `park_era`,        type: `string` },   // LOGGED | UNKNOWN
    nParkEvents:  { sql: `n_park_events`,   type: `number` },
    settleDue:    { sql: `settle_due`,      type: `string` },   // when PENDING_SETTLE gets re-judged
    settledThrough: { sql: `settled_through`, type: `string` },
    // the settled 90-day record that earns (or denies) the revival
    s90Clk:       { sql: `s90_clk`,         type: `number` },
    s90Sp:        { sql: `s90_sp`,          type: `number` },
    s90Ord:       { sql: `s90_ord`,         type: `number` },
    s90Gp:        { sql: `s90_gp`,          type: `number` },
    s90GpRoas:    { sql: `s90_gp_roas`,     type: `number` },
    s90Cpc:       { sql: `s90_cpc`,         type: `number` },
    lifeSettledClk: { sql: `life_settled_clk`, type: `number` },
    nWin:         { sql: `n_win`,           type: `number` },   // season WIN verdicts for the text
    winLabels:    { sql: `win_labels`,      type: `string` },
    contextLabel: { sql: `context_label`,   type: `string` },
    // anti-churn guard state
    stopReleased: { sql: `stop_released`,   type: `boolean` },
    reParkedThisOcc: { sql: `re_parked_this_occ`, type: `boolean` },    // one revive per occurrence
    manualParkedRecent: { sql: `manual_parked_recent`, type: `boolean` },  // Ori's park — 14d hold
    reviveSettling: { sql: `revive_settling`, type: `boolean` },
    engineImmune: { sql: `engine_immune`,   type: `boolean` },
    immuneReason: { sql: `immune_reason`,   type: `string` },
    // v27.53's judgement-call flag, exposed in v27.63 because apply-all must not sweep these up.
    // TRUE when the row's OWN settled record loses money (GP-ROAS 0.80–1.00) and it clears the bar
    // only on a prior same-season mature WIN. The view calls it "Ori's read-this-first flag on the
    // panel: these are the revivals that are a judgement call" — so it stays hand-queued, never bulk.
    seasonRelaxApplied: { sql: `season_relax_applied`, type: `boolean` },
    reviveBid:    { sql: `revive_bid`,      type: `number` },   // calibrated, from the view
    reverdict:    { sql: `reverdict`,       type: `string` },
    reverdictReason: { sql: `reverdict_reason`, type: `string` },  // plain-English, from the view
  },
});

// cache-bust 2026-08-12: new cube — park reverdict / Revivals panel on Weekly Run
