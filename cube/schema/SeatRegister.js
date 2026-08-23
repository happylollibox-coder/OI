// Cube: SeatRegister — the family seat register on the dashboard (family seat register Task 4).
// Spec: architecture/FAMILY_SEAT_REGISTER.md. PASSTHROUGH ONLY: every category, side, sentence,
// move, seat number and dollar figure below is the register's own. This cube computes nothing,
// re-words nothing and judges nothing — a second place deciding what a keyword is would be a second
// place for it to drift, and the register's rulings (R-a … R-m) are asserted against the register.
//
// WHY IT READS A T_ AND NOT THE VIEW. V_FAMILY_SEAT_REGISTER is a live view whose full read is
// measured in tens of seconds, and it is a once-per-pass object anyway (FACT_KEYWORD_STATE holds
// exactly one snapshot). SP_REFRESH_CUBE_TABLES step 0c materialises it into
// T_FAMILY_SEAT_REGISTER, which the SEATS section of V_DAILY_BRIEF and the SEATS section of
// V_RUN_SUMMARY read too — three surfaces, one image, so they cannot quote different numbers at the
// same reader on the same morning. The refreshKey is the orchestration stamp, so the cache
// invalidates exactly when that rebuild finishes; a bare view edit is invisible here until the T_
// is rebuilt AND the stamp bumps (tools/trigger_refresh.py does both).
//
// ROW ID IS THE REGISTER'S TOTAL ORDERING. sort_key orders the whole register — family, row type,
// horizon, seat number — and is asserted unique by the register's own acceptance check B07 and
// again, on this table, by SEAT_SURFACE_acceptance.sql C07. That is exactly what a Cube primaryKey
// needs, and it means the front end can sort by rowId and get the register's reading order for free.
// The register mixes grains on purpose (a family row, a category row and a seat row are all rows),
// so no natural key — campaign, keyword, family — is unique across it.
//
// A DIMENSION FOR EVERY COLUMN A PERSON READS. Not a curated subset: if the register publishes it,
// the page can show it. scripts/bigquery/tests/check_seat_surface_labels.py fails the build if a
// column of T_FAMILY_SEAT_REGISTER has no dimension here, so a column added to the register cannot
// arrive on the page as a silent blank.
//
// MEASURES. `count` only, plus dollar sums that a person would otherwise add up by hand. The sums
// are honest only when the query filters to ONE row type and ONE horizon — a register that mixes a
// FAMILY row with its own CATEGORY rows double-counts by construction — so they are named for the
// filter they need rather than offered as a general total.
cube(`SeatRegister`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_FAMILY_SEAT_REGISTER\``,
  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },

  measures: {
    count: { type: `count` },
    // filter to one row_type + one horizon before reading either of these.
    costPerDay:      { sql: `cost_per_day`,      type: `sum`, format: `currency` },
    costDayOne:      { sql: `cost_day_one`,      type: `sum`, format: `currency` },
    costRejudged:    { sql: `cost_rejudged`,     type: `sum`, format: `currency` },
  },

  dimensions: {
    // ── identity and ordering
    rowId:   { sql: `sort_key`, type: `string`, primaryKey: true, shown: true },
    sortKey: { sql: `sort_key`, type: `string` },
    rowType: { sql: `row_type`, type: `string` },   // FAMILY | CATEGORY | SEAT | OPEN_SEAT | LEAK | GAP | NO_CLOCK | ABSORB | REFERENCE | UNMAPPED
    family:  { sql: `family`,   type: `string` },
    book:    { sql: `book`,     type: `string` },   // HARVEST (working) | INVEST (launch, reference only)
    horizon: { sql: `horizon`,  type: `string` },   // today | day one | re-judged

    // ── what this row is, in the register's own plain words
    seatNo:       { sql: `seat_no`,       type: `number` },
    category:     { sql: `category`,      type: `string` },
    side:         { sql: `side`,          type: `string` },   // 80 | 20 | UNMAPPED | (none, for $0 categories)
    occupantKind: { sql: `occupant_kind`, type: `string` },
    state:        { sql: `state`,         type: `string` },   // the verdict ladder's own state

    // ── the thing the row is about
    campaignId:   { sql: `campaign_id`,   type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    keywordId:    { sql: `keyword_id`,    type: `string` },
    targetText:   { sql: `target_text`,   type: `string` },
    matchType:    { sql: `match_type`,    type: `string` },

    // ── price and cost
    currentBid:   { sql: `current_bid`,   type: `number` },
    bidFloor:     { sql: `bid_floor`,     type: `number` },
    seatPrice:    { sql: `seat_price`,    type: `number` },
    costPerDayDim:   { sql: `cost_per_day`,   type: `number` },
    costDayOneDim:   { sql: `cost_day_one`,   type: `number` },
    costRejudgedDim: { sql: `cost_rejudged`,  type: `number` },

    // ── the book this row already rides on, if any
    bookBatchId: { sql: `book_batch_id`, type: `string` },
    bookAction:  { sql: `book_action`,   type: `string` },
    bookOldBid:  { sql: `book_old_bid`,  type: `number` },
    bookNewBid:  { sql: `book_new_bid`,  type: `number` },
    // what a sheet does with this row today (2026-08-23): PENDING_BOOK | NEXT_LEAK_BOOK |
    // NEXT_REPRICE_BOOK | REBUILD_LEAK_BOOK | BY_HAND | NO_SHEET_ROW | NONE — the brief's action
    sheetRow:    { sql: `sheet_row`,     type: `string` },

    // ── the standing raise behind a stalled probe (rulings R-b / R-c)
    raiseOldBid:      { sql: `raise_old_bid`,     type: `number` },
    raiseNewBid:      { sql: `raise_new_bid`,     type: `number` },
    raisedOn:         { sql: `raised_on`,         type: `time` },
    clicksSinceRaise: { sql: `clicks_since_raise`, type: `number` },
    daysSinceRaise:   { sql: `days_since_raise`,  type: `number` },

    // ── appointments and the holdout arm
    dueOn:               { sql: `due_on`,                 type: `time` },
    holdout:             { sql: `holdout`,                type: `boolean` },
    holdoutEligibleFrom: { sql: `holdout_eligible_from`,  type: `time` },
    holdoutNote:         { sql: `holdout_note`,           type: `string` },

    // ── the family read (FAMILY / REFERENCE rows)
    spendBasisPerDay:   { sql: `spend_basis_per_day`,   type: `number` },
    spendContextPerDay: { sql: `spend_context_per_day`, type: `number` },
    spendHorizonPerDay: { sql: `spend_horizon_per_day`, type: `number` },
    judgedPerDay:       { sql: `judged_per_day`,        type: `number` },
    defensePerDay:      { sql: `defense_per_day`,       type: `number` },
    goodSidePerDay:     { sql: `good_side_per_day`,     type: `number` },
    badSidePerDay:      { sql: `bad_side_per_day`,      type: `number` },
    goodShare:          { sql: `good_share`,            type: `number` },
    doctrineStatus:     { sql: `doctrine_status`,       type: `string` },   // IN | AT_LINE | OUT | NO_SPEND | REFERENCE | UNMAPPED
    allowancePerDay:    { sql: `allowance_per_day`,     type: `number` },
    seatsCostPerDay:    { sql: `seats_cost_per_day`,    type: `number` },
    leakPerDay:         { sql: `leak_per_day`,          type: `number` },
    gapPerDay:          { sql: `gap_per_day`,           type: `number` },
    openCapacityPerDay: { sql: `open_capacity_per_day`, type: `number` },
    overByPerDay:       { sql: `over_by_per_day`,       type: `number` },
    atLineBand:           { sql: `at_line_band`,            type: `number` },
    atLineBandDerivation: { sql: `at_line_band_derivation`, type: `string` },
    nKeywords:            { sql: `n_keywords`,              type: `number` },

    // ── the words. Every code in this register is rendered as a sentence wherever a person reads
    // it, so these are the columns a page shows, not a debug aid.
    horizonAssumption: { sql: `horizon_assumption`, type: `string` },
    move:              { sql: `move`,               type: `string` },
    sentence:          { sql: `sentence`,           type: `string` },

    // ── the clocks. Publish these next to any figure: they are how a reader tells whether this
    // image has seen what he did since the last pass.
    asOf:        { sql: `as_of`,          type: `time` },
    adsBasisTo:  { sql: `ads_basis_to`,   type: `time` },
    adsBasisFrom:{ sql: `ads_basis_from`, type: `time` },
  },
});
// cache-bust 2026-08-23 (v27.123): new cube — the family seat register's morning surface
