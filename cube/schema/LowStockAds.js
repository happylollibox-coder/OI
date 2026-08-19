// Cube: LowStockAds — Weekly Run criteria 1 (LOW STOCK), from V_LOW_STOCK_ADS (live read).
// Spec: architecture/LOW_STOCK_CRITERIA.md. Panel: dashboard-react/src/pages/LowStockPhase.tsx.
//
// Four grains in one view, switched on rowKind:
//   FAMILY    one per family — the verdict, the pipeline totals, the rolled-up ads numbers
//   ASIN      one per variation — the diagnosis (which variation binds, and why)
//   CAMPAIGN  one per campaign inside a WATCH/THROTTLE/CRITICAL family — the BUDGET lever, and the
//             capped PAIRING (suggestedValue = the paired budget cut, already summed over that
//             campaign's proposed target cuts)
//   TARGET    one per campaign x target inside such a family — the money, ranked
//
// EVERY verdict, threshold, dollar and days-bought figure is decided in the VIEW and must stay
// there (feedback_all_logic_in_backend). This cube is a passthrough: no CASE, no arithmetic, no
// derived measures beyond count. Do not rebuild V_LOW_STOCK_ADS here and do not add a threshold.
//
// v27.58 (Ori 2026-08-13): CRITICAL families now escalate below-breakeven converting targets to a
// real action (paired with a budget cut on capped campaigns) instead of marking everything
// STOCK_PROTECT. `daysBoughtMax` is GONE — it was measured on the family's aggregate cover while the
// panel header showed the binding variation's, two clocks in one row. It is replaced by `daysBought`
// (what THIS row's proposed action buys) and `daysBoughtIfPaused` (the option price on a protected
// winner), both measured on the binding variation.
//
// v27.59 (Ori 2026-08-13), TWO changes:
//   1. THE GRADE RUNS ON ACTUAL RECENT SALES, not the forecast. velocityActual = the fastest of the
//      7/14/30-day trailing rates; it drives daysOfCover*, riskState and everything downstream. The
//      forecast reading is published ALONGSIDE (velocityForecast, daysOfCover*Forecast,
//      coverBasisForecast, riskStateForecast) so the divergence is visible, never resolved silently.
//      The SEASON signal (seasonGapUnits / seasonDemandUnits) keeps its forecast basis and stays a
//      separate, differently-labelled question: "will I have enough for Q4", not "am I about to go
//      dark at the rate I am selling now".
//   2. THE CRITICAL ACTION IS A 50% BID CUT ON THE SHORT WINDOW. Not profitable on the LAST DAY and
//      not profitable on the w-day window (wDays from V_PEAK_WINDOW_RULE — 7, or 3 in peak) → halve
//      the bid, floored per format. Either window profitable → protected. `breakevenBid` and
//      `bidCutViable` are GONE with the ladder they served; `halveViable`, `profit1d`, `profitW` and
//      the d1_*/w_* window columns replace them.
cube(`LowStockAds`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_LOW_STOCK_ADS\``,

  // LIVE-VIEW cube (KeywordLift / OobBudget / ParkReverdict convention): the inventory snapshot
  // reloads daily and the settled ads windows roll every day, and view fixes do not move the
  // orchestration stamp — 15-min TTL.
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },

  dimensions: {
    rowId: {
      sql: `CONCAT(row_kind, '|', family, '|', COALESCE(asin, ''), '|',
                   COALESCE(campaign_id, ''), '|', COALESCE(keyword_id, ''))`,
      type: `string`, primaryKey: true,
    },
    rowKind:      { sql: `row_kind`,      type: `string` },   // FAMILY | ASIN | CAMPAIGN | TARGET
    family:       { sql: `family`,        type: `string` },
    riskState:    { sql: `risk_state`,    type: `string` },   // OK | WATCH | THROTTLE | CRITICAL
    riskRank:     { sql: `risk_rank`,     type: `number` },   // 1..4 — sort key, from the view
    riskReason:   { sql: `risk_reason`,   type: `string` },   // plain-English, from the view
    // v27.62 — the SAME verdict in ONE clause (~6-10 words) for the visible `why` column; the long
    // form above becomes that cell's tooltip. NULL on FAMILY rows, whose header is prose, not a cell.
    riskReasonShort: { sql: `risk_reason_short`, type: `string` },
    snapshotDate: { sql: `CAST(snapshot_date AS STRING)`, type: `string` },

    // ── inventory (FAMILY + ASIN rows) ──────────────────────────────────────────────────────
    asin:              { sql: `asin`,                 type: `string` },
    product:           { sql: `product`,              type: `string` },
    fbaQty:            { sql: `fba_qty`,              type: `number` },
    awdQty:            { sql: `awd_qty`,              type: `number` },
    sellableQty:       { sql: `sellable_qty`,         type: `number` },   // FBA + AWD — sellable today
    inTransitQty:      { sql: `in_transit_qty`,       type: `number` },   // Amazon-registered inbound
    inTransitAwdQty:   { sql: `in_transit_awd_qty`,   type: `number` },   // pending shipments bound for AWD
    mfrReadyQty:       { sql: `mfr_ready_qty`,        type: `number` },   // finished, at the factory
    inProductionQty:   { sql: `in_production_qty`,    type: `number` },
    upstreamQty:       { sql: `upstream_qty`,         type: `number` },
    totalPipelineQty:  { sql: `total_pipeline_qty`,   type: `number` },   // all six stages
    // ── velocity: the GRADE runs on actual, the forecast is published beside it (v27.59) ────
    velocityForecast:  { sql: `velocity_forecast`,    type: `number` },   // V_SUPPLY_CHAIN_SUMMARY
    velocity30d:       { sql: `velocity_30d`,         type: `number` },   // first-party trailing actual
    velocity14d:       { sql: `velocity_14d`,         type: `number` },
    velocity7d:        { sql: `velocity_7d`,          type: `number` },
    // THE GRADING RATE: fastest of the 7/14/30d trailing actuals. 7d alone goes to zero on a quiet
    // week (infinite cover); 30d alone lags an accelerating launch family by a month. The max of the
    // three is the conservative choice among them and says which window bound it.
    velocityActual:     { sql: `velocity_actual`,       type: `number` },
    velocityActualBasis:{ sql: `velocity_actual_basis`, type: `string` }, // 7D | 14D | 30D | NONE
    velocityUsed:      { sql: `velocity_used`,        type: `number` },   // = velocityActual (v27.59)
    docWalkDays:       { sql: `doc_walk_days`,        type: `number` },   // forecast walk (may be NULL)
    docFlatDays:       { sql: `doc_flat_days`,        type: `number` },   // sellable / velocityActual
    docFlatForecastDays:{ sql: `doc_flat_forecast_days`, type: `number` },// sellable / forecast rate
    daysOfCover:       { sql: `days_of_cover`,        type: `number` },   // ACTUAL, strict (sellable)
    daysOfCoverAvail:  { sql: `days_of_cover_avail`,  type: `number` },   // + Amazon-registered inbound
    coverBasis:        { sql: `cover_basis`,          type: `string` },   // ACTUAL_7D|_14D|_30D|NO_DEMAND
    // the same numbers on the FORECAST leg — published so "trailing actual says WATCH, the seasonal
    // forecast says CRITICAL" is a thing the panel can show rather than a thing that silently picks one
    daysOfCoverForecast:      { sql: `days_of_cover_forecast`,       type: `number` },
    daysOfCoverAvailForecast: { sql: `days_of_cover_avail_forecast`, type: `number` },
    coverBasisForecast:       { sql: `cover_basis_forecast`,         type: `string` },
    riskStateForecast:        { sql: `risk_state_forecast`,          type: `string` },
    bridgeGapDaysForecast:    { sql: `bridge_gap_days_forecast`,     type: `number` },
    bindingCoverForecastDays: { sql: `binding_cover_forecast_days`,  type: `number` },
    atRiskUnitsSharePctForecast: { sql: `at_risk_units_share_pct_forecast`, type: `number` },
    stockoutDate:      { sql: `CAST(stockout_date AS STRING)`, type: `string` },
    poDeadline:        { sql: `CAST(po_deadline AS STRING)`,   type: `string` },
    tooLateToReplenish:{ sql: `too_late_to_replenish`, type: `boolean` },
    fullLeadDays:      { sql: `full_lead_days`,       type: `number` },   // manufacture + shipment
    bridgeGapDays:     { sql: `bridge_gap_days`,      type: `number` },   // cover − days to arrival
    nextArrivalDate:   { sql: `CAST(next_arrival_date AS STRING)`, type: `string` },
    daysToArrival:     { sql: `days_to_arrival`,      type: `number` },
    nextArrivalQty:    { sql: `next_arrival_qty`,     type: `number` },
    seasonDemandUnits: { sql: `season_demand_units`,  type: `number` },   // rest of year
    seasonGapUnits:    { sql: `season_gap_units`,     type: `number` },   // demand − whole pipeline
    overduePendingQty: { sql: `overdue_pending_qty`,  type: `number` },   // ETA passed, not marked received
    overduePendingOldestEta: { sql: `CAST(overdue_pending_oldest_eta AS STRING)`, type: `string` },
    units90d:            { sql: `units_90d`,               type: `number` },
    familyUnitsSharePct: { sql: `family_units_share_pct`,  type: `number` },
    bindingAsin:         { sql: `binding_asin`,            type: `string` },
    bindingProduct:      { sql: `binding_product`,         type: `string` },
    atRiskUnitsSharePct: { sql: `at_risk_units_share_pct`, type: `number` },
    // the binding variation's own booked arrival, from the once-a-day inventory snapshot
    bindingNextArrivalDate:  { sql: `CAST(binding_next_arrival_date AS STRING)`, type: `string` },
    // ⚠️ TRUE = the binding variation has a live PENDING shipment its stamped arrival does not know
    // about, so the verdict may be one snapshot load out of date. The view does NOT correct it.
    arrivalFreshnessConflict:{ sql: `arrival_freshness_conflict`, type: `boolean` },
    arrivalConflictNote:     { sql: `arrival_conflict_note`,      type: `string` },
    // the clock every daysBought figure is measured on — the binding variation's cover
    bindingCoverDays:    { sql: `binding_cover_days`,      type: `number` },
    familyFlatCoverDays: { sql: `family_flat_cover_days`,  type: `number` },
    familySellableQty:   { sql: `family_sellable_qty`,     type: `number` },
    familyVelocity:      { sql: `family_velocity`,         type: `number` },
    firstSaleDate:       { sql: `CAST(first_sale_date AS STRING)`, type: `string` },
    familyAgeMonths:     { sql: `family_age_months`,       type: `number` },

    // ── family-level ads roll-up (FAMILY rows) ──────────────────────────────────────────────
    campaigns:                { sql: `campaigns`,                    type: `number` },
    cappedCampaigns:          { sql: `capped_campaigns`,             type: `number` },
    nonconvTargets:           { sql: `nonconv_targets`,              type: `number` },
    nonconvSpendPerDay:       { sql: `nonconv_spend_per_day`,        type: `number` },
    nonconvTargetsCapped:     { sql: `nonconv_targets_capped`,       type: `number` },
    nonconvSpendPerDayCapped: { sql: `nonconv_spend_per_day_capped`, type: `number` },
    stalledTargets:           { sql: `stalled_targets`,              type: `number` },
    stalledSpendPerDay:       { sql: `stalled_spend_per_day`,        type: `number` },
    convTargets:              { sql: `conv_targets`,                 type: `number` },
    convSpendPerDay:          { sql: `conv_spend_per_day`,           type: `number` },
    // days of cover pausing EVERY converting target at once would buy — the joint figure, never
    // the sum of the rows. Upper bound: zero organic recapture assumed.
    convDaysBoughtMax:        { sql: `conv_days_bought_max`,         type: `number` },
    // v27.58 — what the CRITICAL escalation actually asks for
    escalatedTargets:         { sql: `escalated_targets`,            type: `number` },
    escalatedSpendPerDay:     { sql: `escalated_spend_per_day`,      type: `number` },
    parkTargets:              { sql: `park_targets`,                 type: `number` },  // waste parks
    bidCutTargets:            { sql: `bid_cut_targets`,              type: `number` },  // 50% halves
    // promoted by the halve rule but with nothing executable left (bid already at the floor, or no
    // bid on the target at all) — counted so "20 escalated, 18 moves" is explainable
    notExecutableTargets:     { sql: `not_executable_targets`,       type: `number` },
    proposalTargets:          { sql: `proposal_targets`,             type: `number` },
    proposalFreedPerDay:      { sql: `proposal_freed_per_day`,       type: `number` },
    proposalDaysBought:       { sql: `proposal_days_bought`,         type: `number` },
    protectedTargets:         { sql: `protected_targets`,            type: `number` },
    protectedSpendPerDay:     { sql: `protected_spend_per_day`,      type: `number` },
    budgetCutCampaigns:       { sql: `budget_cut_campaigns`,         type: `number` },
    budgetCutPerDay:          { sql: `budget_cut_per_day`,           type: `number` },

    // ── ads (CAMPAIGN + TARGET rows) ────────────────────────────────────────────────────────
    campaignId:     { sql: `campaign_id`,     type: `string` },
    campaignName:   { sql: `campaign_name`,   type: `string` },
    channel:        { sql: `channel`,         type: `string` },   // SP | SB — settle horizon differs
    campaignBudget: { sql: `campaign_budget`, type: `number` },
    isDefense:      { sql: `is_defense`,      type: `boolean` },
    isSeasonal:     { sql: `is_seasonal`,     type: `boolean` },
    isAutoCampaign: { sql: `is_auto_campaign`, type: `boolean` },
    isCapped:       { sql: `is_capped`,       type: `boolean` },  // V_CAMPAIGN_CAP_STATE.is_oob_owned
    daysCapped7d:   { sql: `days_capped_7d`,  type: `number` },
    util7d:         { sql: `util_7d`,         type: `number` },
    // DISPLAY ONLY — the launch exemption blocks ROAS-driven campaign budget cuts in V_ADS_COACH.
    // It is deliberately NOT a gate here: a stock action is not a ROAS verdict. See the view header.
    launchExemptActive:  { sql: `launch_exempt_active`, type: `boolean` },
    launchExemptUntil:   { sql: `CAST(launch_exempt_until AS STRING)`, type: `string` },
    launchEnvelopeState: { sql: `launch_envelope_state`, type: `string` },
    keywordId:      { sql: `keyword_id`,      type: `string` },
    // v27.63 (Task 1.10): the upload key — the view emits it on every row now, populated on TARGET
    // rows; NULL on FAMILY/ASIN/CAMPAIGN by design (campaign budget rows key on Campaign ID alone)
    adGroupId:      { sql: `ad_group_id`,     type: `string` },
    targetText:     { sql: `target_text`,     type: `string` },
    matchType:      { sql: `match_type`,      type: `string` },
    keywordState:   { sql: `keyword_state`,   type: `string` },
    currentBid:     { sql: `current_bid`,     type: `number` },
    isAuto:         { sql: `is_auto`,         type: `boolean` },
    isPt:           { sql: `is_pt`,           type: `boolean` },
    // SB creative type from DIM_AD_GROUP — it is what splits the SB bid floor $0.25 vs $0.10
    creativeType:   { sql: `creative_type`,   type: `string` },
    settledThrough: { sql: `CAST(settled_through AS STRING)`, type: `string` },
    settleDays:     { sql: `settle_days`,     type: `number` },   // 7 SP / 14 SB
    s28Clicks:      { sql: `s28_clicks`,      type: `number` },
    s28Spend:       { sql: `s28_spend`,       type: `number` },
    s28Orders:      { sql: `s28_orders`,      type: `number` },
    s28Units:       { sql: `s28_units`,       type: `number` },
    s28Gp:          { sql: `s28_gp`,          type: `number` },
    s28GpRoas:      { sql: `s28_gp_roas`,     type: `number` },
    s90Clicks:      { sql: `s90_clicks`,      type: `number` },
    s90Spend:       { sql: `s90_spend`,       type: `number` },
    s90Orders:      { sql: `s90_orders`,      type: `number` },
    s90Gp:          { sql: `s90_gp`,          type: `number` },
    s90GpRoas:      { sql: `s90_gp_roas`,     type: `number` },
    // ── the SHORT windows (v27.59) — what the CRITICAL halve rule actually judges ────────────
    // lastAdsDay = LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP()), the same "last day" every
    // Weekly Run panel uses. wDays = V_PEAK_WINDOW_RULE (7 off peak, 3 in peak unless 7 is proven).
    // ⚠️ Both windows are UNSETTLED — SP accrues to D+7, SB to D+14. Requiring BOTH to fail is the
    // guard; the settled 28d/90d columns above stay published so the slow read is one glance away.
    lastAdsDay:     { sql: `CAST(last_ads_day AS STRING)`, type: `string` },
    wDays:          { sql: `w_days`,          type: `number` },
    inPeak:         { sql: `in_peak`,         type: `boolean` },
    wDaysReason:    { sql: `w_days_reason`,   type: `string` },
    d1Clicks:       { sql: `d1_clicks`,       type: `number` },
    d1Spend:        { sql: `d1_spend`,        type: `number` },
    d1Orders:       { sql: `d1_orders`,       type: `number` },
    d1Units:        { sql: `d1_units`,        type: `number` },
    d1Gp:           { sql: `d1_gp`,           type: `number` },
    d1GpRoas:       { sql: `d1_gp_roas`,      type: `number` },
    wClicks:        { sql: `w_clicks`,        type: `number` },
    wSpend:         { sql: `w_spend`,         type: `number` },
    wOrders:        { sql: `w_orders`,        type: `number` },
    wUnits:         { sql: `w_units`,         type: `number` },
    wGp:            { sql: `w_gp`,            type: `number` },
    wGpRoas:        { sql: `w_gp_roas`,       type: `number` },
    // YES | NO | NO_SPEND — a window with no spend is neither profitable nor a failure, and the
    // rule treats the two cases differently. Published so which one happened is visible on the row.
    profit1d:       { sql: `profit_1d`,       type: `string` },
    profitW:        { sql: `profit_w`,        type: `string` },
    spendPerDay:    { sql: `spend_per_day`,   type: `number` },   // settled 28d rate
    unitsPerDay:    { sql: `units_per_day`,   type: `number` },   // settled 28d rate
    // the SHORT-window rates — the halve is decided on the short window, so it is also SIZED on it
    wSpendPerDay:   { sql: `w_spend_per_day`, type: `number` },
    wUnitsPerDay:   { sql: `w_units_per_day`, type: `number` },
    pctOfFamilyVelocity: { sql: `pct_of_family_velocity`, type: `number` },
    // NON_CONVERTING | STALLED | CONVERTING | DEFENSE | THIN | ALREADY_OFF
    targetClass:    { sql: `target_class`,    type: `string` },
    // v27.59 — the escalation trail, published so a wrong promotion is debuggable from the panel
    escalated:      { sql: `escalated`,       type: `boolean` },  // both short windows failed
    halveViable:    { sql: `halve_viable`,    type: `boolean` },  // there is room above the floor
    // $0.20 SP house · $0.25 SB video/brand (platform minBid) · $0.10 SB PRODUCT_COLLECTION /
    // STORE_SPOTLIGHT. No trim may land below it.
    bidFloor:       { sql: `bid_floor`,       type: `number` },
    // v27.60: the view owns the clamp verdict; the panel used to recompute it in TypeScript
    bidClampedToFloor: { sql: `bid_clamped_to_floor`, type: `boolean` },
    suggestedBid:   { sql: `suggested_bid`,   type: `number` },   // TARGET rows — bid x 0.5, floored
    suggestedBudget:{ sql: `suggested_budget`,type: `number` },   // CAMPAIGN rows (the paired cut)
    // grain-agnostic money pair: bid on a TARGET row, daily budget on a CAMPAIGN row. The panel
    // renders these directly so it never has to know which grain it is on.
    nowValue:       { sql: `now_value`,       type: `number` },
    suggestedValue: { sql: `suggested_value`, type: `number` },
    dollarsFreedPerDay:  { sql: `dollars_freed_per_day`,  type: `number` },
    unitsRemovedPerDay:  { sql: `units_removed_per_day`,  type: `number` },
    // days of cover THIS action buys, on the binding variation's clock. Upper bound: assumes the
    // stopped ad loses 100% of its units with zero organic recapture.
    daysBought:          { sql: `days_bought`,            type: `number` },
    // what a FULL pause would buy — the option price on a protected winner, never a proposal
    daysBoughtIfPaused:  { sql: `days_bought_if_paused`,  type: `number` },
    isProposal:          { sql: `is_proposal`,            type: `boolean` },
    dollarRank:          { sql: `dollar_rank`,            type: `number` },
    // Ori's ranking: dollars freed first, days of cover bought second (family-wide, 1 = act first)
    proposalRank:        { sql: `proposal_rank`,          type: `number` },
    // TARGET rows: STOCK_BID_HALVE | STOCK_BID_HALVE_AND_BUDGET | STOCK_AT_FLOOR | STOCK_NO_BID
    // | STOCK_CUT_WASTE | STOCK_CUT_WASTE_AND_BUDGET | STOCK_TRIM_STALLED | STOCK_PROTECT
    // | STOCK_WATCH | STOCK_NONE
    // CAMPAIGN rows: STOCK_BUDGET_CUT | STOCK_BUDGET_HOLD | STOCK_NONE
    // — decided in the view, never here
    action:       { sql: `action`,        type: `string` },
    // The FULL verdict — a paragraph. It is the `why` cell's title= TOOLTIP, never the visible text.
    actionReason: { sql: `action_reason`, type: `string` },
    // v27.62 (Ori 2026-08-13: "there should be actions and the why must be short and readable") —
    // the same verdict as ONE clause of ~6-10 words, branch-for-branch identical to actionReason so
    // the two can never disagree. This is what the visible `why` column prints. The panel must never
    // truncate actionReason itself: shortening is a wording decision and wording lives in the view.
    actionReasonShort: { sql: `action_reason_short`, type: `string` },
  },
});

// cache-bust 2026-08-13d: v27.62 — short one-clause reason strings (action_reason_short /
// risk_reason_short) beside the long forms, for the OobBudgetPhase-shaped Low stock table
