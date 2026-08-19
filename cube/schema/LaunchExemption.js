// Cube: LaunchExemption — the launch families' licence to lose money, from V_LAUNCH_EXEMPTION
// (live read). Feeds the "Launch exemption" criteria panel on Weekly Run, directly above Revivals.
// Spec: architecture/LAUNCH_EXEMPTION.md
//
// EVERY verdict here is decided in the VIEW: launch membership (family age from its own first sale),
// exempt_until (earlier of the 183-day age boundary and Ori's dated stop gate), envelope_state,
// protected_winner, envelope_trim_rank, and the blocks/allows text. The panel PRINTS them. Do not
// rebuild any of it here or in TypeScript.
//
// The LEFT JOIN adds the coach's STANDING budget decision for the campaign, straight from the
// materialized FACT_ADS_COACH_ACTIONS BUDGET row — so the panel can show "the coach wanted
// CAMPAIGN_STOP here" next to the exemption that blocked it. It reads the last coach run: rows
// still showing a cut mean the run predates the v27.56 gate; after the next
// SP_REFRESH_ADS_COACH_ACTIONS they read LAUNCH_EXEMPT_HOLD with the suppressed action named in
// the explanation.
cube(`LaunchExemption`, {
  sql: `SELECT x.campaign_id, x.campaign_name, x.campaign_type, x.campaign_state,
               x.family, x.current_budget,
               CAST(x.family_first_sale AS STRING) family_first_sale,
               x.family_age_days, x.family_age_months, x.launch_window_days,
               CAST(x.age_window_end AS STRING) age_window_end,
               CAST(x.exempt_until AS STRING) exempt_until,
               x.exempt_days_left, x.exempt_active, x.exempt_until_source,
               x.sanctioned_daily_investment, x.sanctioned_monthly_investment,
               CAST(x.sanctioned_stop_date AS STRING) sanctioned_stop_date,
               CAST(x.sanctioned_on AS STRING) sanctioned_on,
               x.sanctioned_note,
               x.family_daily_spend_7d, x.family_budget_total, x.family_campaigns,
               x.envelope_over_by_daily, x.envelope_state, x.escalate_to_ori,
               x.settled_spend, x.settled_gp, x.settled_gp_roas, x.settled_clicks, x.settled_orders,
               x.spend_7d, x.evidence_days, x.protected_winner, x.envelope_trim_rank,
               CAST(x.first_activity AS STRING) first_activity,
               x.in_grace_window, x.blocks_contain,
               x.blocks_enforced, x.blocks_pending, x.allows, x.exempt_reason,
               b.action AS coach_budget_action,
               b.action_explanation AS coach_budget_explanation
        FROM \`onyga-482313.OI.V_LAUNCH_EXEMPTION\` x
        LEFT JOIN (
          SELECT campaign_id, ANY_VALUE(action) action, ANY_VALUE(action_explanation) action_explanation
          FROM \`onyga-482313.OI.FACT_ADS_COACH_ACTIONS\`
          WHERE action_type = 'BUDGET'
          GROUP BY campaign_id
        ) b ON CAST(b.campaign_id AS STRING) = CAST(x.campaign_id AS STRING)`,

  // LIVE-VIEW cube (ParkReverdict / KeywordLift / OobBudget convention): the exemption re-reads the
  // family's own first sale and the settled record daily, and view fixes don't move the
  // orchestration stamp — 15-min TTL.
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },

  // NOTE: `sql` above is wrapped as a subquery by Cube, so dimensions must reference the OUTPUT
  // column names (no `x.` / `b.` prefixes — those aliases are not visible outside the subquery).
  dimensions: {
    campaignId:    { sql: `campaign_id`,   type: `string`, primaryKey: true },
    campaignName:  { sql: `campaign_name`, type: `string` },
    campaignType:  { sql: `campaign_type`, type: `string` },   // SP | SB (drives the settle window)
    campaignState: { sql: `campaign_state`, type: `string` },
    family:        { sql: `family`,        type: `string` },
    currentBudget: { sql: `current_budget`, type: `number` },

    // membership — derived from the family's own first sale, never a list
    familyFirstSale:  { sql: `family_first_sale`,  type: `string` },
    familyAgeDays:    { sql: `family_age_days`,    type: `number` },
    familyAgeMonths:  { sql: `family_age_months`,  type: `number` },
    launchWindowDays: { sql: `launch_window_days`, type: `number` },  // 183 — the boundary, auditable
    ageWindowEnd:     { sql: `age_window_end`,     type: `string` },
    exemptUntil:      { sql: `exempt_until`,       type: `string` },
    exemptDaysLeft:   { sql: `exempt_days_left`,   type: `number` },
    exemptActive:     { sql: `exempt_active`,      type: `boolean` },
    exemptUntilSource:{ sql: `exempt_until_source`, type: `string` },  // SANCTIONED_STOP_DATE | FAMILY_AGE_183D

    // the sanction on record (NULL = none; exemption then rests on age alone)
    sanctionedDaily:   { sql: `sanctioned_daily_investment`,   type: `number` },
    sanctionedMonthly: { sql: `sanctioned_monthly_investment`, type: `number` },
    sanctionedStopDate:{ sql: `sanctioned_stop_date`,          type: `string` },
    sanctionedOn:      { sql: `sanctioned_on`,                 type: `string` },
    sanctionedNote:    { sql: `sanctioned_note`,               type: `string` },

    // envelope — an exemption is not a blank cheque
    familyDailySpend7d:  { sql: `family_daily_spend_7d`,  type: `number` },
    familyBudgetTotal:   { sql: `family_budget_total`,    type: `number` },
    familyCampaigns:     { sql: `family_campaigns`,       type: `number` },
    envelopeOverByDaily: { sql: `envelope_over_by_daily`, type: `number` },
    envelopeState:       { sql: `envelope_state`,         type: `string` },   // WITHIN_ENVELOPE | OVER_ENVELOPE | NO_SANCTION
    escalateToOri:       { sql: `escalate_to_ori`,        type: `boolean` },

    // settled evidence (28 settled days, tier-COGS GP over spend — same currency as the engine)
    settledSpend:      { sql: `settled_spend`,       type: `number` },
    settledGp:         { sql: `settled_gp`,          type: `number` },
    settledGpRoas:     { sql: `settled_gp_roas`,     type: `number` },
    settledClicks:     { sql: `settled_clicks`,      type: `number` },
    settledOrders:     { sql: `settled_orders`,      type: `number` },
    spend7d:           { sql: `spend_7d`,            type: `number` },
    evidenceDays:      { sql: `evidence_days`,       type: `number` },
    protectedWinner:   { sql: `protected_winner`,    type: `boolean` },  // never pulled down
    envelopeTrimRank:  { sql: `envelope_trim_rank`,  type: `number` },   // if money must come out, here first

    // grace — the one containment that is not a loss-cut
    firstActivity:  { sql: `first_activity`,  type: `string` },
    inGraceWindow:  { sql: `in_grace_window`, type: `boolean` },
    blocksContain:  { sql: `blocks_contain`,  type: `boolean` },

    // the policy, in words, decided in the view
    blocksEnforced: { sql: `blocks_enforced`, type: `string` },
    blocksPending:  { sql: `blocks_pending`,  type: `string` },
    allows:         { sql: `allows`,          type: `string` },
    exemptReason:   { sql: `exempt_reason`,   type: `string` },

    // the coach's standing budget decision for this campaign (last coach run)
    coachBudgetAction:      { sql: `coach_budget_action`,      type: `string` },
    coachBudgetExplanation: { sql: `coach_budget_explanation`, type: `string` },
  },
});

// cache-bust 2026-08-13: new cube — launch exemption / Launch exemption criteria on Weekly Run
