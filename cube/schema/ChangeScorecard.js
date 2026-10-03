// Cube: ChangeScorecard — the settled OUTCOME half of the change loop, from V_CHANGE_SCORECARD
// (live read). One row per applied change that is OLD ENOUGH TO GRADE: a change made on day T is
// graded on [T+1, T+7] (SB [T+1, T+14]) and may not be read before T+14 (SB T+21). Rows younger
// than their read gate are absent from the view by construction — "no rows" means "nothing has
// settled yet", never "no changes were made". Spec: architecture/PPC_CLOSE_THE_LOOP.md.
//
// Every verdict, reason sentence, remedy and remedy value is decided in the VIEW. The dashboard
// panel only displays them — do not add thresholds or derived verdicts here.
//
// READER: dashboard-react/src/pages/ChangeScorecardPanel.tsx — the Weekly Run panel "How did last
// week's changes do?", the page where Ori starts changes.
//
// HAND CHANGES ARE SHOWN, LABELLED AS ORI'S (2026-10-03, his ruling of 2026-10-02). Since
// 2026-10-01 the view also grades source = 'OBSERVED': changes seen on Amazon through the DIM SCD2
// trail that OI never logged, which are mostly Ori's own edits in the console. From 2026-10-01 to
// 2026-10-03 this cube held them out with WHERE source != 'OBSERVED', as the morning brief still
// does. Ori ruled they are evidence: the cube now reads every row, the panel's OBSERVED chip says
// the change was his, and a REVERSED hand change shows its pre-change value to put back like any
// other row. Do not add a source filter here without a new ruling.
// Check: scripts/bigquery/tests/check_change_scorecard_cube.py (evaluates this file in node, runs
// its SQL in BigQuery next to the bare view, and fails if any row of the view is missing).
cube(`ChangeScorecard`, {
  sql: `SELECT change_id, CAST(change_date AS STRING) change_date, source, action, action_group,
               scope_grain, channel, campaign_id, campaign_name, family,
               targeting, search_term, match_type,
               value_kind, old_value, new_value, pct_change,
               CAST(window_start AS STRING) window_start, CAST(window_end AS STRING) window_end,
               window_used, win_days,
               win_clicks, win_spend, win_orders, win_gp_roas, win_cpc, win_net_profit,
               prior_clicks, prior_spend, prior_gp_roas, prior_available,
               superseded_in_window, n_later_changes,
               verdict, verdict_reason, remedy, remedy_value
        FROM \`onyga-482313.OI.V_CHANGE_SCORECARD\``,

  // LIVE-VIEW cube (same convention as KeywordLift / OobBudget / PausedHistory): the view's read
  // gate advances with CURRENT_DATE and the underlying FACT restates daily, while view fixes don't
  // move the orchestration stamp — a 15-min TTL bounds staleness.
  // COST: each read runs the whole scorecard, which since 2026-10-01 reads
  // V_PPC_CHANGE_LOG_LANDED and costs about half again what it did. The source filter this cube
  // carried 2026-10-01 → 10-03 did not make it cheaper: the same bytes were read with and without
  // it. Measurements in the run log of scripts/bigquery/tests/OBSERVED_CHANGES_acceptance.sql
  // (2026-10-01 entries).
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },

  dimensions: {
    changeId:      { sql: `change_id`,      type: `string`, primaryKey: true },
    changeDate:    { sql: `change_date`,    type: `string` },
    source:        { sql: `source`,         type: `string` },   // 'COACH' | 'MANUAL' | 'OBSERVED' (hand changes seen on Amazon) | the weekly book's 'BRAIN:*' / 'CATALOG:*' / 'PACING:*'
    action:        { sql: `action`,         type: `string` },
    actionGroup:   { sql: `action_group`,   type: `string` },   // BID_UP | BID_DOWN | BUDGET_* | NEGATE | ...
    scopeGrain:    { sql: `scope_grain`,    type: `string` },   // TARGET | CAMPAIGN | TERM
    channel:       { sql: `channel`,        type: `string` },   // 'SP' | 'SB' — drives the 7d/14d window
    campaignId:    { sql: `campaign_id`,    type: `string` },
    campaignName:  { sql: `campaign_name`,  type: `string` },
    family:        { sql: `family`,         type: `string` },
    targeting:     { sql: `targeting`,      type: `string` },
    searchTerm:    { sql: `search_term`,    type: `string` },
    matchType:     { sql: `match_type`,     type: `string` },
    valueKind:     { sql: `value_kind`,     type: `string` },   // BID | BUDGET | (null for negates)
    oldValue:      { sql: `old_value`,      type: `number` },   // REVERSED restores THIS
    newValue:      { sql: `new_value`,      type: `number` },
    pctChange:     { sql: `pct_change`,     type: `number` },
    windowStart:   { sql: `window_start`,   type: `string` },
    windowEnd:     { sql: `window_end`,     type: `string` },
    windowUsed:    { sql: `window_used`,    type: `string` },   // PRIMARY | EXTENDED (thin evidence → T+21)
    winDays:       { sql: `win_days`,       type: `number` },
    winClicks:     { sql: `win_clicks`,     type: `number` },
    winSpend:      { sql: `win_spend`,      type: `number` },
    winOrders:     { sql: `win_orders`,     type: `number` },
    winGpRoas:     { sql: `win_gp_roas`,    type: `number` },
    winCpc:        { sql: `win_cpc`,        type: `number` },
    winNetProfit:  { sql: `win_net_profit`, type: `number` },
    priorClicks:   { sql: `prior_clicks`,   type: `number` },
    priorSpend:    { sql: `prior_spend`,    type: `number` },
    priorGpRoas:   { sql: `prior_gp_roas`,  type: `number` },
    priorAvailable:{ sql: `prior_available`, type: `boolean` }, // FALSE → judged absolute-only
    supersededInWindow: { sql: `superseded_in_window`, type: `boolean` },
    nLaterChanges: { sql: `n_later_changes`, type: `number` },
    verdict:       { sql: `verdict`,        type: `string` },   // CONFIRMED | NEUTRAL | REVERSED | INSUFFICIENT
    verdictReason: { sql: `verdict_reason`, type: `string` },   // plain-English, from the view
    remedy:        { sql: `remedy`,         type: `string` },   // RESTORE_BID | RESTORE_BUDGET | RE_APPLY_NEGATIVE | REVIEW
    remedyValue:   { sql: `remedy_value`,   type: `number` },   // the value to put back
  },
});

// cache-bust 2026-08-12: new cube — settled change scorecard on Weekly Run
// cache-bust 2026-10-01: OBSERVED rows (hand changes seen on Amazon) held out of the panel until Ori decides
// cache-bust 2026-10-03: OBSERVED rows back in the panel, labelled as Ori's (ruling 2026-10-02)
