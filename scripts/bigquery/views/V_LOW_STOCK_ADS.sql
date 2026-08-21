-- =============================================================================================
-- V_LOW_STOCK_ADS — Weekly Run criteria 1: LOW STOCK (highest priority, above Launch and Revivals).
-- =============================================================================================
-- Ori 2026-08-13: "add a new criteria - low stock (this gets prioritised) - meaning if a family is
-- going to be out of stock we need to reduce not-converting ad spend in order to reduce sales until
-- the new batch arrives."
--
-- ── THE INTERPRETATION THIS VIEW IMPLEMENTS (read this before trusting a number) ────────────────
-- The instruction has two halves that pull in opposite directions. Cutting NON-CONVERTING spend
-- saves money but does NOT slow sales — by definition those targets bought zero orders on the
-- settled window, so removing them removes zero units of demand. Only throttling CONVERTING
-- traffic actually stretches inventory. Both halves are honoured, in this order:
--
--   1. CUT THE WASTE FIRST — it is free. Non-converting targets inside an at-risk family are ranked
--      by dollars/day and emitted with action STOCK_CUT_WASTE. days_bought is reported as 0.0, not
--      hidden: this saves cash and stops paying to compete for a product you cannot supply, but it
--      does not buy a single day of cover. Anyone who claims otherwise is reading the wrong number.
--
--   2. …EXCEPT INSIDE A CAPPED CAMPAIGN, WHERE CUTTING WASTE SPEEDS THE STOCK-OUT UP. This is the
--      one place Ori's two halves actually reconcile. A campaign that is out of budget spends its
--      whole budget every day; removing a non-converting target does not return that money, it
--      re-routes it to the converting targets in the same campaign, which sells MORE units, sooner.
--      So for capped campaigns (V_CAMPAIGN_CAP_STATE.is_oob_owned) EVERY cut is PAIRED with a
--      budget cut of the same size — park the waste AND take the freed dollars out of the daily
--      budget. Un-paired, the cut is actively harmful to a family heading for a stock-out.
--
-- ── v27.58 — THE CRITICAL ESCALATION (Ori 2026-08-13, the change that produced this revision) ────
-- The first cut of this view marked EVERY converting target STOCK_PROTECT — priced, never proposed
-- — on the assumption that converting traffic is worth protecting. For a family that is going dry
-- that assumption is wrong twice over, and LolliBall on 2026-08-13 is the proof: 26 converting
-- targets, $101.81/day, and only 3 of them at or above 1.0× GP-ROAS. The other 23 LOSE MONEY on
-- settled evidence AND consume units that cannot be replaced for 44+ days (nothing booked, 26 days
-- of cover on the binding variation). Protecting those is not prudence, it is paying to run out.
--
--   3. IN A **CRITICAL** FAMILY, THE SHORT-WINDOW HALVE (v27.59 — Ori 2026-08-13, verbatim):
--      "table format of critical low stock use the last day, 7 days window format. If it wasn't
--       profitable in last day AND 7 days (or 3 days in peak) reduce bid by 50%."
--
--        last day       = LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP()) — the same anchor
--                         every other Weekly Run panel calls "last day".
--        the w-window   = the last w_days days, w_days from V_PEAK_WINDOW_RULE (7 off peak, 3 in
--                         peak unless last year proved 7 is better). 2026-08-13: in_peak, w_days = 3.
--        "profitable"   = GP-ROAS >= 1.0 on a window that actually SPENT (tier COGS charged).
--        BOTH must fail -> bid × 0.5, floored at the row's own bid floor.
--        EITHER profitable -> no action, and the reason says which window spared it.
--
--      It is DELIBERATELY BLUNT and that is the point: the family is running out of stock and the
--      objective is to SLOW SALES until the next batch lands, not to optimise ROAS. So there is no
--      click bar, no 90-day reprieve and no breakeven arithmetic. This REPLACED the v27.58
--      breakeven-bid ladder outright.
--
--      Floors are the ones the OOB seat model and FN_TARGET_BID_SHADOW already use, per format:
--      $0.20 SP (a HOUSE floor — Amazon's own SP minimum is $0.02, but a bid that low buys no
--      placement worth having) · $0.25 SB video/brand (the platform minBid) · $0.10 SB
--      PRODUCT_COLLECTION / STORE_SPOTLIGHT. No trim may land below the row's floor; when the bid is
--      already AT the floor the row says STOCK_AT_FLOOR and proposes nothing rather than inventing
--      an unexecutable move.
--
--      ⚠️ SETTLE CAVEAT, stated once. Both short windows are UNSETTLED — SP sales accrue to D+7, SB
--      to D+14 — so a fresh day understates GP-ROAS. Requiring BOTH windows to fail is the guard Ori
--      chose, and it is real but PARTIAL: the w-window contains the last day, so the two tests are
--      correlated, not independent. Settled windows were NOT substituted (the rule has to react at
--      the speed stock disappears); the settled 28d/90d columns stay published on every row.
--
--   4. STOCK_PROTECT SURVIVES, for the targets where cutting is genuinely Ori's call:
--        · profitable on either short window — a real winner. Cutting it to save stock is a
--          judgement only Ori makes, so it stays priced (days_bought_if_paused) and never proposed.
--        · brand defense — never profit-judged, never throttled (DEFENSE doctrine), any risk state.
--      And STOCK_WATCH for a target with no spend at all inside the w-window: nothing to slow.
--
--   5. ONLY **CRITICAL** HALVES. A THROTTLE or WATCH family keeps the original behaviour to the
--      letter: converting traffic stays STOCK_PROTECT, priced and unproposed, and the honest levers
--      are still the waste cut and the PO. The reason string on every such row says which state the
--      family is in and that this is why nothing was proposed.
--
-- ── HOW THIS INTERACTS WITH THE LAUNCH EXEMPTION (V_LAUNCH_EXEMPTION) ────────────────────────────
-- LolliBall IS a launch family — all 8 of its campaigns are exempt_active until 2026-11-30 — so the
-- two rules meet head-on and the answer has to be written down, not assumed.
--   WHAT THE EXEMPTION BLOCKS: campaign-level, ROAS-driven MONEY cuts inside V_ADS_COACH
--     (CAMPAIGN_STOP, GUARDIAN_BUDGET_DECREASE, BLITZ_BUDGET_DECREASE, COOLDOWN_BUDGET_REDUCE,
--     RESTORE_BUDGET_PRE_PEAK, post-grace GUARDIAN_BUDGET_CONTAIN). Its purpose is that a young
--     family is not loss-cut out of existence before it has found its bid.
--   WHAT IT DOES NOT BLOCK, AND MUST NOT: this. A stock-driven action is not a ROAS verdict on a
--     launch — it is a supply constraint. The exemption's own doctrine is "launch = FIND THE RIGHT
--     BID, never loss-cut"; a stock brake is neither a loss-cut nor a park, it is a temporary
--     throttle on delivery that is lifted the moment the boat lands. Nothing in this
--     view reads V_LAUNCH_EXEMPTION as a gate; it is joined for DISPLAY ONLY, so exempt campaigns
--     appear with their exemption stated next to a live proposal instead of silently disappearing.
--     launch_exempt_active is published on every TARGET and CAMPAIGN row, and the reason string on
--     an escalated row says the exemption was seen and deliberately not applied.
--   THE ONE PLACE TO BE CAREFUL: the PAIRED budget cut on a capped campaign IS a campaign-level
--     budget cut, which is the shape the exemption blocks elsewhere. It stands here because it is
--     the other half of a target cut — without it the target cut backfires — and because its size
--     is set by the freed dollars, not by a ROAS test. That is stated on the CAMPAIGN row itself.
--
-- ── DAYS OF COVER BOUGHT — MEASURED ON THE BINDING VARIATION (changed in v27.58) ─────────────────
-- The first cut measured days_bought against the FAMILY's aggregate flat cover (sellable ÷ velocity
-- = 58 days for LolliBall) while the panel header showed the BINDING variation's cover (26 days).
-- Two different clocks in one row. Fixed: days_bought is now measured on the binding variation's
-- days_of_cover_avail — the same number the verdict is taken on and the header prints —
--     days_bought = binding_cover × u / (V − u)
-- where u is the units/day this action removes and V is family velocity. The assumption is stated:
-- ad units are removed in proportion to each variation's share of family velocity, so cutting u off
-- the family slows every variation by the same factor V/(V−u) and multiplies every variation's
-- cover by it. A keyword's units cannot be attributed to one child ASIN, so a proportional model is
-- the most that can honestly be claimed.
--   u = units_per_day                  for a park
--   u = units_per_day × (1 − r)        for a bid cut to factor r  (clicks move with the bid, so
--                                      units move with it too — conservative: a bid cut sheds the
--                                      MARGINAL clicks first, so the real unit loss is smaller and
--                                      the real GP-ROAS gain is larger than modelled)
--   u = 0                              for every non-converting / thin / already-off row
--
-- days_bought and days_bought_if_paused are UPPER BOUNDS. They assume a paused ad loses 100% of its
-- units with zero organic recapture, which is false (fact_oi_net_roas_no_halo — ad-attributed is not
-- incremental). The real number is smaller. Never quote either as the expected gain.
--
-- Nothing in this view auto-applies — it is advisory, like every other Weekly Run panel.
--
-- ── INVENTORY SOURCES (existing; nothing reinvented) ────────────────────────────────────────────
-- FACT_INVENTORY_SNAPSHOT is the pipeline of record, loaded by SP_LOAD_FACT_INVENTORY_SNAPSHOT out
-- of V_UNIFIED_INVENTORY_SNAPSHOT, one row per (Date, ASIN, source_type) across the six stages Ori
-- reads on the Supply page:
--     FBA · AWD                       SELLABLE NOW  (FBA = fulfillable+reserved+fc_transfer−orders)
--     In Transit                      Amazon-registered inbound (afn_inbound_shipped/receiving)
--     In Transit AWD                  PENDING manufacturer shipments bound for AWD
--     MFR Ready · In Production       still at the factory — needs a shipment booked before it moves
-- V_SUPPLY_CHAIN_SUMMARY (the Supply page's own summary) supplies sellable_qty, daily_velocity, the
-- forecast-walk days_of_coverage and next_shipment_*; it reads V_PLAN_FORECAST for the seasonal
-- month-by-month depletion walk. This view reads that summary rather than re-deriving cover, so the
-- Low Stock panel and the Supply page can never disagree. The two stages the summary omits
-- (In Transit AWD, In Production) are read straight off FACT_INVENTORY_SNAPSHOT here, so
-- total_pipeline_qty counts the WHOLE pipeline — earlier numbers in this project were wrong
-- precisely because they counted part of it.
--
-- ⚠️ WHY COVER IS NOT SIMPLY V_SUPPLY_CHAIN_SUMMARY.days_of_coverage. That column is the forecast
-- WALK (V_PLAN_FORECAST.sellable_doc_walk), and it has two failure modes a stock-out criteria
-- cannot afford. (1) It returns 999 → NULL whenever cumulative forecast demand never crosses the
-- stock inside the horizon — 3 of 29 ASINs on 2026-08-13 (Birthday Bunny, Nope Bunny, Fresh in
-- Beige) have no walk answer at all, and it went blind for the whole LolliBall family earlier the
-- same day. (2) It is NON-DETERMINISTIC: see the `units` CTE below — the same view evaluated twice
-- in one statement returned walk 89 and 55 for Fresh in Pink.
-- So days_of_cover = LEAST(walk, flat), flat = sellable / velocity_used, velocity_used =
-- GREATEST(forecast rate, trailing-30d actual) — the more conservative of the two available
-- estimates on each side, and the flat leg is computed here from first-party numbers so it is
-- always available and always stable. It binds on 10 of 29 ASINs today. cover_basis says which one
-- won, so the choice is never hidden.
--
-- ── THREE INDEPENDENT WAYS A FAMILY GOES DARK, ALL THREE TESTED ─────────────────────────────────
--   A. THE BRIDGE — cover does not reach the next booked arrival.
--      days_of_cover_avail = days_of_cover + (Amazon-registered In Transit ÷ velocity_used): units
--      Amazon has already taken in check in within days, so excluding them over-alarms (Pink
--      Lollibox 2026-08-13: 29 days strict, 93 with its 588 in-transit units, arrival in 28 —
--      strict says "10 days dark", available says "fine"). The bridge is tested on _avail; the
--      strict number stays published so the harsh figure is never hidden.
--   B. NOTHING BOOKED — no PENDING shipment with a future ETA. Then the whole replacement lead has
--      to fit inside the cover, and the alarm is graded on cover alone.
--   C. THE SEASON — cover reaches the next arrival, but the family does not own enough units for
--      the rest of the year even counting every stage of the pipeline. season_gap_units =
--      GREATEST(rest-of-year FACT_FORECAST_DEMAND, velocity_used × days to 31-Dec) −
--      total_pipeline_qty. Fresh in Pink 2026-08-13 bridges its 26-Aug arrival comfortably and is
--      still ~900 units short of the season. A bridge-only criteria cannot see that, and Q4 is
--      exactly when a stock-out costs the most. A season gap raises WATCH; it only raises THROTTLE
--      once cover_avail drops inside full_lead_days + buffer, i.e. once the shortfall can no longer
--      be manufactured and shipped in time and ads are genuinely the only remaining lever. Until
--      then the honest action is a PO, not a bid — and the reason string says so.
--
-- ⚠️ OVERDUE PENDING SHIPMENTS. Arrival is user-confirmed in this system (project_shipment_manual_-
-- arrival), so a shipment whose ETA has passed and that has not been marked received stays PENDING
-- forever. Those units are neither sellable nor a future arrival, and next_shipment_arrival_date
-- (which filters eta >= today) correctly ignores them. They are surfaced as overdue_pending_qty so
-- a family is never called "nothing inbound" when the truth is "inbound, and someone has to press
-- Mark received". 2026-08-13 stock: 13,674 units across 6 families.
--
-- ── TIMEZONES (fact_oi_timezones) ───────────────────────────────────────────────────────────────
-- The inventory pipeline is UTC-dated (SP_LOAD_FACT_INVENTORY_SNAPSHOT uses CURRENT_DATE(), and
-- V_SUPPLY_CHAIN_SUMMARY measures days_to_next_shipment against it), so every inventory date here
-- is measured against CURRENT_DATE() too — mixing in an LA "today" would shift cover by a day for
-- eight hours out of twenty-four. Ads are America/Los_Angeles, so the settle cut is LA. The two
-- clocks are deliberately separate and each side uses its own.
--
-- ── SETTLED WINDOWS ─────────────────────────────────────────────────────────────────────────────
-- "Not converting" is judged on a SETTLED window or it condemns keywords whose orders simply have
-- not landed: SP sales accrue to D+7, SB to D+14. settle_cut = CURRENT_DATE(LA) − 7 for SP, − 14
-- for SB (channel-aware; V_PARK_REVERDICT's 7-day cut, extended for SB per the metric rule).
-- Action window = settled 28d; history window = settled 90d, reported alongside so a target that
-- converted two months ago is visibly different from one that never has.
-- GP = Ads_sales − COALESCE(T_PRICE_COST_TIER.tier_cost, TOTAL_COST_PER_UNIT) × Ads_units — the
-- house GP, tier COGS charged. GP-ROAS = GP / spend; 1.0 = breakeven AFTER product cost.
-- Brand defense is never profit-judged and never throttled (DEFENSE doctrine) — its targets are
-- emitted as STOCK_PROTECT with reason DEFENSE and never appear on the cut list.
--
-- ── GRAIN ───────────────────────────────────────────────────────────────────────────────────────
-- row_kind = 'FAMILY'   (one per family: the verdict + the rolled-up ads totals)
--          | 'ASIN'     (one per ASIN — the diagnosis: which variation is the binding constraint)
--          | 'CAMPAIGN' (one per campaign inside an at-risk family — the budget lever, and the
--                        PAIRING: on a capped campaign the freed dollars must come off the budget
--                        or the target cuts backfire. suggested_budget lives here and nowhere else,
--                        already summed over the campaign's proposed target cuts, so the panel adds
--                        nothing up.)
--          | 'TARGET'   (one per campaign×target inside an at-risk family — the money, ranked)
-- CAMPAIGN and TARGET rows exist only for families at WATCH/THROTTLE/CRITICAL, so the panel can say
-- "4 families OK" without dragging 800 keyword rows behind it.
--
-- now_value / suggested_value are the panel's two money columns, filled by the VIEW so the panel
-- never has to know which grain it is on: on a TARGET row they are the bid, on a CAMPAIGN row the
-- daily budget. suggested_value is NULL when there is nothing to change (a park has no new bid).
--
-- Determinism: no ANY_VALUE pairing anywhere (fact_oi_any_value_pairing_nondeterminism); every
-- single-row pick is a fully tie-broken ARRAY_AGG(STRUCT(...))[OFFSET(0)]. The one moving part is
-- the daily SP_LOAD_FACT_INVENTORY_SNAPSHOT reload (07:40 UTC), which replaces the day's rows —
-- pulls either side of it differ because the warehouse changed, not because this view wobbles.
-- Cube: LowStockAds. Consumer: LowStockPhase (Weekly Run step 4, above Launch and Revivals).
-- v27.74 (Task 4.7, Ori 2026-08-17): the trailing w-day short window is now the w_days COMPLETE days ending last_ads_day-1 (last-day read and settled s28/s90 windows untouched); overlap/"w-window contains the last day" notes above predate this and no longer hold.
-- v27.78 (Ori 2026-08-17, "fix arm b"): the CAMPAIGN branch now publishes the REAL redirect_mode
-- instead of CAST(NULL AS BOOL). Nothing else moved — no new join, no new CTE, no changed value:
-- the branch already LEFT JOINs rmode as `rmc` for the v27.73 is_proposal gate, so this reads a row
-- that was already in the plan. It exists because redirect mode makes this branch go QUIET (the
-- gate suppresses budget-cut proposals while a family re-aims doorways), and V_PANEL_OWNERSHIP's
-- arm B was reading that silence as "low stock has no opinion here" — the exact opposite of the
-- truth. Publishing the flag lets ownership see a re-aiming family for what it is: low stock acting.
--
-- v27.80 (Ori 2026-08-17, verbatim: "BALL-SP/AUTO (Mint) is auto per product. auto we have for each
-- product - so no need to change / only reduce ads by reducing the bid") — THE REDIRECT GATE NOW
-- ASKS WHOSE DOORWAY IT IS BRAKING. v27.73 suppressed bid AND budget cuts on EVERY campaign of a
-- redirect-mode family (only STOCK_CUT_WASTE% parks survived), on the theory that the family's play
-- is re-aiming, not braking. That is right for a SHARED doorway and wrong for a DEDICATED one, and
-- this account runs ONE AUTO CAMPAIGN PER VARIATION, so the wrong case is common. Measured
-- (advertised-product report, 30d): BALL-SP/AUTO (Mint) 1 own ASIN, BALL-SP/AUTO (Pink) 1,
-- BUNNY-SP/BROAD 3, BALLS- BROAD 5, BUNNY- BROAD 9, BUNNY - COMPETITORS 11.
--   shared doorway advertising the dry variation  → suppressed + redirect offered   CORRECT
--   dedicated campaign of an IN-STOCK sibling     → suppressed, no redirect          CORRECT
--       (braking BALL-SP/AUTO (Pink) would not save one unit of Mint and would lose Pink sales)
--   dedicated campaign of the DRY variation       → suppressed, no usable redirect   THE HOLE
--       BALL-SP/AUTO (Mint), $417/30d, neither braked nor sensibly re-aimed. Swapping its product
--       ad to Pink is meaningless — BALL-SP/AUTO (Pink) already exists and does exactly that job;
--       the swap would duplicate a live campaign. With nowhere to re-aim, the ORDINARY BRAKE is
--       the only lever, which is precisely what Ori asked for.
-- THE FIX, one clause on each of the two is_proposal gates:
--   suppress brakes  ⇔  redirect_mode AND NOT waste-park AND NOT serves_only_binding
-- serves_only_binding = the campaign advertises exactly ONE of our own products and that product IS
-- the family's binding (dry) variation. It comes from T_CAMPAIGN_PRODUCT_SCOPE — the MATERIALIZED
-- V_CAMPAIGN_PRODUCT_SCOPE, joined as a PHYSICAL TABLE. This view has no measured headroom (it
-- stopped planning outright on 2026-08-17 and cost the whole v27.77 repair), so a fourth view was
-- never an option: the scope object is built as orchestrator Task 20.5d3, before anything reads
-- this engine (fact_oi_cube_table_planner_blowup). rmode gained ONE column (binding_asin) rather
-- than a new CTE, and both branches join the table they already needed no other way.
-- KNOWN LIMIT, conservative on purpose: Amazon publishes no advertised-product report for Sponsored
-- Brands, so SB/video campaigns get no scope row, read serves_only_binding = FALSE, and keep the
-- v27.73 behaviour exactly. A dedicated SB campaign of a dry variation therefore stays suppressed.
--
-- v27.81 (2026-08-18, hygiene): the CAMPAIGN branch now PUBLISHES binding_asin instead of NULLing
-- it. serves_only_binding above is a comparison against that ASIN, so while it stayed internal a
-- panel could read the boolean but could not reproduce it or say which variation it referred to —
-- exactly the reproducibility rule v27.78 applied to redirect_mode. Additive, no new join, no new
-- CTE: rmc is already joined on that branch for the gate, and one more column off it is free.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_LOW_STOCK_ADS` AS
WITH k AS (
  SELECT
    14   AS watch_buffer_days,     -- slack demanded between running dry and the replenishment landing
    14   AS crit_dark_days,        -- dark this long before arrival = CRITICAL, not merely THROTTLE
    60   AS no_inbound_crit,       -- NOTHING booked and cover under this = CRITICAL (below any lead)
    120  AS no_inbound_throttle,   -- NOTHING booked and cover under this = THROTTLE (manufacture
                                   --   14-42d + sea ~30d + FC check-in ≈ 60-85d, plus the decision)
    180  AS no_inbound_watch,      -- NOTHING booked and cover under this = WATCH (book the boat)
    14   AS season_lead_buffer,    -- season shortfall turns from a PO problem into an ADS problem
                                   --   once cover_avail < full_lead_days + this
    10.0 AS min_family_share_pct,  -- an ASIN below this share of family units does not set the family
                                   --   verdict (a dead 0.5%-share variation must not throttle a family)
    25.0 AS at_risk_share_escalate,-- …but if THIS much of a family's units sit in at-risk ASINs, the
                                   --   family escalates even when no single ASIN clears the bar
    10   AS nonconv_min_clicks,    -- settled clicks needed before "zero orders" is evidence, not noise
    28   AS act_window_days,       -- settled action window (the money being spent right now)
    90   AS hist_window_days,      -- settled history window (context, never the trigger on its own)
    90   AS units_share_days,      -- trailing window for family unit shares / binding-ASIN choice
    0.80 AS max_throttle_share,    -- above this share of family velocity, pausing a target changes the
                                   --   demand model rather than the rate — days_bought is NOT modelled
    -- ── v27.59 CRITICAL SHORT-WINDOW HALVE (Ori 2026-08-13) ─────────────────────────────────────
    -- "table format of critical low stock use the last day, 7 days window format. If it wasn't
    --  profitable in last day AND 7 days (or 3 days in peak) reduce bid by 50%."
    -- This REPLACED the v27.58 breakeven-bid ladder outright. It is deliberately aggressive: the
    -- family is running out of stock and the objective is to SLOW SALES, not to optimise ROAS.
    1.00 AS breakeven_roas,        -- GP-ROAS 1.0 = "profitable" AFTER product cost (tier COGS
                                   --   charged). NOT a tuned threshold: it is the definition of
                                   --   paying for itself. Both windows are tested against it.
    0.50 AS halve_factor,          -- Ori's number, verbatim: "reduce bid by 50%".
    10   AS conv_evidence_clicks,  -- settled clicks before a converting target's GP-ROAS is evidence
                                   --   rather than noise. Used by the WATCH/THROTTLE classes only —
                                   --   the CRITICAL halve rule has NO click bar, on purpose (see the
                                   --   header): a click bar would spare the small bleeders that are
                                   --   exactly the units a dry family cannot replace.
    0.20 AS bid_floor_sp,          -- the floors V_OOB_KEYWORD and FN_TARGET_BID_SHADOW already use.
    0.25 AS bid_floor_sb,          --   $0.20 house SP · $0.25 SB platform minBid (video etc.) ·
    0.10 AS bid_floor_sb_spot,     --   $0.10 for SB PRODUCT_COLLECTION / STORE_SPOTLIGHT.
                                   --   No trim may land below the row's own floor.
    1.00 AS min_daily_budget       -- Amazon's daily-budget floor — a paired budget cut clamps here
),
inv_today AS (SELECT CURRENT_DATE() AS d),                            -- inventory clock (UTC — see header)
ads_today AS (SELECT CURRENT_DATE('America/Los_Angeles') AS d),       -- ads clock (LA)

-- ══ 1. INVENTORY ══════════════════════════════════════════════════════════════════════════════
snap AS (SELECT MAX(Date) AS d FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`),

-- the two pipeline stages V_SUPPLY_CHAIN_SUMMARY does not carry, straight off the fact table
stages AS (
  SELECT i.ASIN AS asin,
    CAST(SUM(IF(i.source_type = 'In Transit AWD', i.quantity_balance, 0)) AS INT64) AS in_transit_awd_qty,
    CAST(SUM(IF(i.source_type = 'In Production',  i.quantity_balance, 0)) AS INT64) AS in_production_qty,
    CAST(SUM(i.quantity_balance) AS INT64)                                          AS total_pipeline_qty
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` i
  CROSS JOIN snap s
  WHERE i.Date = s.d
  GROUP BY 1
),

-- PENDING manufacturer shipments whose ETA has already passed and that nobody has marked received
overdue AS (
  SELECT po.product_asin AS asin,
    CAST(SUM(sl.quantity_shipped) AS INT64) AS overdue_pending_qty,
    MIN(s.estimated_arrival_date)           AS overdue_pending_oldest_eta
  FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
  JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON s.shipment_id = sl.shipment_id
  JOIN `onyga-482313.OI.DE_PURCHASE_ORDERS` po      ON po.purchase_order_id = sl.purchase_order_id
  CROSS JOIN inv_today t
  WHERE s.shipment_status = 'PENDING'
    AND s.estimated_arrival_date IS NOT NULL
    AND s.estimated_arrival_date < t.d
    AND po.product_asin IS NOT NULL
  GROUP BY 1
),

-- FAMILY-level next arrival: the earliest FUTURE pending ETA and the units landing ON that date.
-- (Summing every ASIN's own next_shipment_qty would add units from three different dates together.)
fam_eta AS (
  SELECT p.parent_name AS family, s.estimated_arrival_date AS eta,
         CAST(SUM(sl.quantity_shipped) AS INT64) AS qty
  FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
  JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON s.shipment_id = sl.shipment_id
  JOIN `onyga-482313.OI.DE_PURCHASE_ORDERS` po      ON po.purchase_order_id = sl.purchase_order_id
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON p.asin = po.product_asin AND p.marketplace = 'ATVPDKIKX0DER'
  CROSS JOIN inv_today t
  WHERE s.shipment_status = 'PENDING'
    AND s.estimated_arrival_date >= t.d
    AND p.parent_name IS NOT NULL
  GROUP BY 1, 2
),
fam_arrival AS (
  SELECT family,
    ARRAY_AGG(STRUCT(eta, qty) ORDER BY eta, qty DESC LIMIT 1)[OFFSET(0)] AS nxt
  FROM fam_eta GROUP BY 1
),
-- LIVE per-ASIN next arrival, straight from the shipments tables. Used ONLY to detect the
-- freshness conflict published on the FAMILY row (see the note there): the per-ASIN arrival that
-- actually drives risk_state comes from the once-a-day inventory snapshot, and a shipment booked
-- after that load is invisible to it. Referenced exactly once, in the FAMILY output branch, so it
-- costs one inlining rather than one per path through asin_base.
asin_eta_raw AS (
  SELECT po.product_asin AS asin, s.estimated_arrival_date AS eta,
         CAST(SUM(sl.quantity_shipped) AS INT64) AS qty
  FROM `onyga-482313.OI.DE_SHIPMENT_LINES` sl
  JOIN `onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS` s ON s.shipment_id = sl.shipment_id
  JOIN `onyga-482313.OI.DE_PURCHASE_ORDERS` po      ON po.purchase_order_id = sl.purchase_order_id
  CROSS JOIN inv_today t
  WHERE s.shipment_status = 'PENDING'
    AND s.estimated_arrival_date >= t.d
    AND po.product_asin IS NOT NULL
  GROUP BY 1, 2
),
asin_eta_live AS (
  SELECT asin, ARRAY_AGG(STRUCT(eta, qty) ORDER BY eta, qty DESC LIMIT 1)[OFFSET(0)] AS nxt
  FROM asin_eta_raw GROUP BY 1
),

-- trailing units per ASIN — sets the family shares and picks the binding variation.
-- Cut at the ORDERS watermark (last complete Organic day with sessions > 0), never the calendar:
-- feedback_oi_orders_vs_ads_watermark / architecture/ORDERS_WATERMARK.md.
ord_wm AS (
  SELECT MAX(date) AS d FROM (
    SELECT date FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    WHERE Performance_TYPE = 'Organic'
    GROUP BY date HAVING SUM(ASIN_SESSIONS) > 0
  )
),
-- ══ THE GRADING VELOCITY (v27.59 — Ori's CORRECTION 2) ════════════════════════════════════════
-- Ori 2026-08-13: "CRITICAL means that by current sales qty (based on the last days) the family
-- will be OOS and we need to spend less ads spend."
--
-- Until v27.58 the grade ran on velocity_used = GREATEST(velocity_forecast, velocity_30d), and the
-- FORECAST won on ALL 29 ASINs — every cover number and every risk grade in this view was
-- forecast-driven, on a forecast that is 3.4x reality on the family carrying the most units:
--     Fresh in Pink     forecast 15.71/d vs 30d actual 4.57/d
--     Fresh in Blue     forecast  4.10/d vs 30d actual 1.73/d
-- The grade now runs on ACTUAL RECENT SALES. The forecast leg is not deleted — it is published
-- alongside on every row (velocity_forecast, doc_flat_forecast_days, days_of_cover_forecast,
-- days_of_cover_avail_forecast, cover_basis_forecast, risk_state_forecast) so the divergence is
-- visible instead of buried, and it still owns the SEASON test (see the season note below).
--
-- WHICH ACTUAL WINDOW — measured, not assumed (2026-08-13, all 29 own ASINs):
--   velocity_actual = GREATEST(units_7d/7, units_14d/14, units_30d/30)   -- the fastest rate the
--                                                                       -- product has ACTUALLY
--                                                                       -- sold at recently
--   A single window is wrong in both directions and the catalogue proves both failures on the same
--   day:
--     * 7d alone is too noisy on a low-volume variation. Nope Bunny sold 0 units in the last 7 days
--       and 2 in the last 30. A 7d-only rate is 0.0/day -> INFINITE cover -> "plenty of stock" on a
--       product with 95 units. A zero week must never be able to manufacture safety.
--     * 30d alone is too slow on an accelerating one. LolliBall is a launch family climbing hard —
--       Purple LolliBall runs 3.40/d (60d) -> 5.53/d (30d) -> 7.36/d (14d) -> 8.00/d (7d). The 30d
--       rate says 35 days of cover; the product is actually selling at 24 days of cover. Ori's own
--       worked example ("Purple LolliBall ... cover 26d becomes 35d") is the 30d reading, and it is
--       the optimistic one. On the LolliBall family the trailing-30d actual is BELOW the forecast
--       while the trailing-7d actual is ABOVE it.
--   Taking the MAX of the three is the conservative choice among actual windows (max rate = shortest
--   cover), it can never return an infinite cover unless the product genuinely sold nothing in 30
--   days, and it catches a real acceleration within a week instead of a month. It is biased slightly
--   high (E[max] > true rate), which for a stock-out grade is the correct direction of error, and
--   velocity_actual_basis publishes WHICH window bound each row so the bias is auditable.
--
-- ⚠️ SEASONALITY TENSION — stated here, surfaced on the row, never conflated into one number.
--   Trailing actual sales going INTO a season understate future demand: the forecast exists because
--   Q4 demand is far above August, and a pure trailing-actual grade will say "plenty of stock" right
--   before the season when it is not. The two questions are therefore kept apart:
--     risk_state (OK/WATCH/THROTTLE/CRITICAL) answers "am I about to go dark at the rate I am
--       selling NOW" — Ori's definition, and the right trigger for cutting ad spend TODAY. It runs
--       on velocity_actual.
--     season_gap_units / season_demand_units answers "will I have enough for Q4" — it keeps its
--       forecast basis (GREATEST(forecast rate, actual rate) x days to 31-Dec, vs FACT_FORECAST_DEMAND)
--       and is reported as its OWN labelled signal, in its own column, with its own reason string.
--   risk_state_forecast is published beside risk_state precisely so "the trailing rate says WATCH but
--   the seasonal forecast says CRITICAL" is a thing the panel can show rather than a thing that
--   silently picks one.
--
-- Why the actual legs are computed HERE rather than read through V_SUPPLY_CHAIN_SUMMARY.last_30d_sold:
-- V_PLAN_FORECAST is NON-DETERMINISTIC on its rate columns: evaluated twice inside ONE statement on
-- 2026-08-13 it returned proportional_daily_demand 6.41 and 15.71 for the same ASIN (Fresh in Pink),
-- 19.91 and 41.97 (Mint LolliME), 16.83 and 11.54 (White Lollibox), with sellable_doc_walk moving
-- 89 <-> 55 alongside. That instability is upstream of this view and of the Supply page. The trailing
-- actuals are the one velocity this view can guarantee, so they are derived first-party from the
-- sales/traffic source, cut at the ORDERS watermark. Since the GRADE now uses only those, a
-- V_PLAN_FORECAST wobble can no longer flip a family between OK and THROTTLE run to run — it can
-- only move the published forecast column and the season gap.
units AS (
  SELECT s.child_asin AS asin,
    CAST(SUM(s.SALES_QUANTITY) AS INT64) AS units_90d,
    CAST(SUM(IF(s.date > DATE_SUB(w.d, INTERVAL 30 DAY), s.SALES_QUANTITY, 0)) AS INT64) AS units_30d,
    CAST(SUM(IF(s.date > DATE_SUB(w.d, INTERVAL 14 DAY), s.SALES_QUANTITY, 0)) AS INT64) AS units_14d,
    CAST(SUM(IF(s.date > DATE_SUB(w.d, INTERVAL  7 DAY), s.SALES_QUANTITY, 0)) AS INT64) AS units_7d
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily` s
  CROSS JOIN ord_wm w CROSS JOIN k
  WHERE s.date BETWEEN DATE_SUB(w.d, INTERVAL k.units_share_days - 1 DAY) AND w.d
  GROUP BY 1
),
first_sale AS (
  SELECT p.parent_name AS family, MIN(s.date) AS first_sale_date
  FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily` s
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON p.asin = s.child_asin AND p.marketplace = 'ATVPDKIKX0DER'
  WHERE s.SALES_QUANTITY > 0 AND p.parent_name IS NOT NULL
  GROUP BY 1
),
-- rest-of-year forecast per product — the same FACT_FORECAST_DEMAND rows V_PLAN_FORECAST walks
season_fc AS (
  SELECT f.product, CAST(ROUND(SUM(f.forecast_units)) AS INT64) AS season_fc_units
  FROM `onyga-482313.OI.FACT_FORECAST_DEMAND` f
  CROSS JOIN inv_today t
  WHERE f.forecast_year = EXTRACT(YEAR FROM t.d)
    AND f.forecast_month >= EXTRACT(MONTH FROM t.d)
  GROUP BY 1
),

-- per-ASIN cover. Reads the Supply page's own summary for sellable / velocity / walk-DOC /
-- next-shipment; adds the flat fallback and the conservative velocity (see header).
asin_base AS (
  SELECT
    p.parent_name                                   AS family,
    sc.asin,
    sc.product_short_name                           AS product,
    CAST(COALESCE(p.manufacture_day, 30) + COALESCE(p.shipment_days, 30) AS INT64) AS full_lead_days,
    CAST(sc.fba_stock_qty AS INT64)                 AS fba_qty,
    CAST(sc.awd_stock_qty AS INT64)                 AS awd_qty,
    CAST(sc.sellable_qty AS INT64)                  AS sellable_qty,
    CAST(sc.in_transit_qty AS INT64)                AS in_transit_qty,
    COALESCE(st.in_transit_awd_qty, 0)              AS in_transit_awd_qty,
    CAST(sc.mfr_stock_qty AS INT64)                 AS mfr_ready_qty,
    COALESCE(st.in_production_qty, 0)               AS in_production_qty,
    COALESCE(st.total_pipeline_qty, 0)              AS total_pipeline_qty,
    ROUND(COALESCE(sc.daily_velocity, 0), 3)        AS velocity_forecast,
    ROUND(COALESCE(u.units_30d, 0) / 30.0, 3)       AS velocity_30d,   -- first-party, watermark-cut
    ROUND(COALESCE(u.units_14d, 0) / 14.0, 3)       AS velocity_14d,
    ROUND(COALESCE(u.units_7d,  0) /  7.0, 3)       AS velocity_7d,
    sc.days_of_coverage                             AS doc_walk_days,
    sc.next_shipment_date                           AS next_arrival_date,
    sc.days_to_next_shipment                        AS days_to_arrival,
    CAST(sc.next_shipment_qty AS INT64)             AS next_arrival_qty,
    COALESCE(ov.overdue_pending_qty, 0)             AS overdue_pending_qty,
    ov.overdue_pending_oldest_eta,
    COALESCE(u.units_90d, 0)                        AS units_90d,
    COALESCE(sf.season_fc_units, 0)                 AS season_fc_units
  FROM `onyga-482313.OI.V_SUPPLY_CHAIN_SUMMARY` sc
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON p.asin = sc.asin AND p.marketplace = 'ATVPDKIKX0DER'
  LEFT JOIN stages    st ON st.asin = sc.asin
  LEFT JOIN overdue   ov ON ov.asin = sc.asin
  LEFT JOIN units     u  ON u.asin  = sc.asin
  LEFT JOIN season_fc sf ON sf.product = sc.product_short_name
  WHERE p.parent_name IS NOT NULL      -- own catalogue only (fact_oi_dim_product_holds_competitor_asins)
),
-- v27.59: TWO cover legs, computed side by side and never merged.
--   ACTUAL   (velocity_actual = fastest of the 7d/14d/30d trailing rates) -> drives days_of_cover,
--            days_of_cover_avail, stockout_date, po_deadline, bridge_gap_days and RISK_STATE.
--   FORECAST (velocity_forecast_used = GREATEST(forecast rate, actual rate), plus the seasonal
--            walk-DOC from V_SUPPLY_CHAIN_SUMMARY) -> published as *_forecast, drives the SEASON
--            demand figure and risk_state_forecast, and nothing else.
-- The seasonal walk leg lives ONLY on the forecast side on purpose: doc_walk_days is
-- V_PLAN_FORECAST's own forecast-shaped depletion walk, so folding it into the grade would smuggle
-- the forecast straight back into the number Ori asked to be actual-driven.
asin_cover AS (
  SELECT b.*,
    -- the grade's rate (see the long note above `units`)
    GREATEST(b.velocity_7d, b.velocity_14d, b.velocity_30d) AS velocity_actual,
    CASE
      WHEN GREATEST(b.velocity_7d, b.velocity_14d, b.velocity_30d) <= 0 THEN 'NONE'
      WHEN b.velocity_7d  >= GREATEST(b.velocity_14d, b.velocity_30d)   THEN '7D'
      WHEN b.velocity_14d >= b.velocity_30d                             THEN '14D'
      ELSE '30D'
    END AS velocity_actual_basis,
    -- the forecast-inclusive rate: the season question and the published forecast cover only
    GREATEST(b.velocity_forecast, b.velocity_7d, b.velocity_14d, b.velocity_30d) AS velocity_forecast_used,
    CASE WHEN GREATEST(b.velocity_7d, b.velocity_14d, b.velocity_30d) > 0
         THEN ROUND(b.sellable_qty / GREATEST(b.velocity_7d, b.velocity_14d, b.velocity_30d), 1)
    END AS doc_flat_days,
    CASE WHEN GREATEST(b.velocity_forecast, b.velocity_7d, b.velocity_14d, b.velocity_30d) > 0
         THEN ROUND(b.sellable_qty
                    / GREATEST(b.velocity_forecast, b.velocity_7d, b.velocity_14d, b.velocity_30d), 1)
    END AS doc_flat_forecast_days,
    DATE_DIFF(DATE(EXTRACT(YEAR FROM t.d), 12, 31), t.d, DAY) + 1 AS days_to_year_end
  FROM asin_base b CROSS JOIN inv_today t
),
asin_risk AS (
  SELECT c.*,
    -- THE GRADE'S COVER — trailing actual only, no seasonal walk. NULL only when the product has
    -- sold nothing at all in 30 days (nothing to run out of).
    c.doc_flat_days AS days_of_cover,
    CASE WHEN c.doc_flat_days IS NULL THEN 'NO_DEMAND'
         ELSE CONCAT('ACTUAL_', c.velocity_actual_basis) END AS cover_basis,
    -- THE PUBLISHED FORECAST COVER — exactly what this view returned before v27.59: the more
    -- conservative of the seasonal walk and the forecast-rate flat walk.
    CASE
      WHEN c.doc_walk_days IS NULL AND c.doc_flat_forecast_days IS NULL THEN NULL
      WHEN c.doc_walk_days IS NULL THEN c.doc_flat_forecast_days
      WHEN c.doc_flat_forecast_days IS NULL THEN CAST(c.doc_walk_days AS FLOAT64)
      ELSE LEAST(CAST(c.doc_walk_days AS FLOAT64), c.doc_flat_forecast_days)
    END AS days_of_cover_forecast,
    CASE
      WHEN c.doc_walk_days IS NULL AND c.doc_flat_forecast_days IS NULL THEN 'NO_DEMAND'
      WHEN c.doc_walk_days IS NULL THEN 'FLAT'            -- walk blind (launch family / beyond horizon)
      WHEN c.doc_flat_forecast_days IS NULL THEN 'WALK'
      WHEN c.doc_flat_forecast_days <= CAST(c.doc_walk_days AS FLOAT64) THEN 'FLAT'
      ELSE 'WALK'                                         -- seasonal walk bites first (Q4 loading)
    END AS cover_basis_forecast,
    -- SEASON shortfall — its own question, its own (forecast) rate. Does the WHOLE pipeline cover
    -- the rest of the year? Never folded into the grade.
    GREATEST(c.season_fc_units,
             CAST(ROUND(c.velocity_forecast_used * c.days_to_year_end) AS INT64)) AS season_demand_units
  FROM asin_cover c
),
asin_state AS (
  SELECT r.*,
    r.velocity_actual AS velocity_used,   -- the grade's rate, under its historical column name
    r.season_demand_units - r.total_pipeline_qty AS season_gap_units,
    -- cover once Amazon-registered inbound checks in (the bridge is tested on this — see header)
    CASE WHEN r.days_of_cover IS NOT NULL AND r.velocity_actual > 0
         THEN ROUND(r.days_of_cover + r.in_transit_qty / r.velocity_actual, 1)
         ELSE r.days_of_cover END AS days_of_cover_avail,
    CASE WHEN r.days_of_cover_forecast IS NOT NULL AND r.velocity_forecast_used > 0
         THEN ROUND(r.days_of_cover_forecast + r.in_transit_qty / r.velocity_forecast_used, 1)
         ELSE r.days_of_cover_forecast END AS days_of_cover_avail_forecast,
    DATE_ADD(t.d, INTERVAL CAST(FLOOR(r.days_of_cover) AS INT64) DAY) AS stockout_date,
    -- last date a replacement batch can start and still land before the shelf empties
    DATE_SUB(DATE_ADD(t.d, INTERVAL CAST(FLOOR(r.days_of_cover) AS INT64) DAY),
             INTERVAL r.full_lead_days DAY) AS po_deadline
  FROM asin_risk r CROSS JOIN inv_today t
),
asin_verdict AS (
  SELECT a.*,
    CASE WHEN a.days_to_arrival IS NOT NULL AND a.days_of_cover_avail IS NOT NULL
         THEN ROUND(a.days_of_cover_avail - a.days_to_arrival, 1) END AS bridge_gap_days,
    CASE WHEN a.days_to_arrival IS NOT NULL AND a.days_of_cover_avail_forecast IS NOT NULL
         THEN ROUND(a.days_of_cover_avail_forecast - a.days_to_arrival, 1) END AS bridge_gap_days_forecast,
    (a.po_deadline < t.d) AS too_late_to_replenish
  FROM asin_state a CROSS JOIN inv_today t
),
-- The SAME three tests, run twice: once on the actual-sales cover (this is risk_state, the verdict
-- that drives everything downstream) and once on the forecast cover (risk_state_forecast, published
-- purely so the divergence is visible). The thresholds are identical — only the cover input differs.
asin_scored AS (
  SELECT v.*,
    CASE
      WHEN v.days_of_cover IS NULL THEN 'OK'                                     -- no demand, no risk
      -- B. nothing booked
      WHEN v.days_to_arrival IS NULL AND v.days_of_cover_avail < kk.no_inbound_crit     THEN 'CRITICAL'
      WHEN v.days_to_arrival IS NULL AND v.days_of_cover_avail < kk.no_inbound_throttle THEN 'THROTTLE'
      -- A. the bridge
      WHEN v.days_to_arrival IS NOT NULL
       AND v.days_of_cover_avail - v.days_to_arrival <= -kk.crit_dark_days        THEN 'CRITICAL'
      WHEN v.days_to_arrival IS NOT NULL
       AND v.days_of_cover_avail - v.days_to_arrival < 0                          THEN 'THROTTLE'
      -- C. THE SEASON BRANCHES WERE REMOVED HERE — v27.60 (verifier FAIL, 2026-08-13).
      -- Ori's definition: "CRITICAL means that by CURRENT SALES QTY (based on the last days) the
      -- family will be OOS and we need to spend less ads spend." season_gap_units is a FORECAST
      -- number, so grading on it manufactured a risk state out of a projection: Fresh in Pink
      -- graded WATCH on 3,010 forecast units against 745 at its actual rate, and Fresh in Purple
      -- the same — and Pink is the family's binding variation, so the whole Fresh family grade was
      -- forecast-driven. That is exactly the conflation this view must never make.
      -- risk_state now answers ONE question: at the rate I am selling now, am I about to go dark.
      -- The season shortfall keeps its own separate signals — season_gap_units, season_demand_units
      -- and risk_state_forecast below — because "will I have enough for Q4" is a PURCHASE ORDER
      -- decision, not a reason to cut a bid today.
      WHEN v.days_to_arrival IS NOT NULL
       AND v.days_of_cover_avail - v.days_to_arrival < kk.watch_buffer_days       THEN 'WATCH'
      WHEN v.days_to_arrival IS NULL AND v.days_of_cover_avail < kk.no_inbound_watch THEN 'WATCH'
      ELSE 'OK'
    END AS risk_state,
    CASE
      WHEN v.days_of_cover_forecast IS NULL THEN 'OK'
      WHEN v.days_to_arrival IS NULL AND v.days_of_cover_avail_forecast < kk.no_inbound_crit     THEN 'CRITICAL'
      WHEN v.days_to_arrival IS NULL AND v.days_of_cover_avail_forecast < kk.no_inbound_throttle THEN 'THROTTLE'
      WHEN v.days_to_arrival IS NOT NULL
       AND v.days_of_cover_avail_forecast - v.days_to_arrival <= -kk.crit_dark_days   THEN 'CRITICAL'
      WHEN v.days_to_arrival IS NOT NULL
       AND v.days_of_cover_avail_forecast - v.days_to_arrival < 0                     THEN 'THROTTLE'
      WHEN v.season_gap_units > 0
       AND v.days_of_cover_avail_forecast < v.full_lead_days + kk.season_lead_buffer  THEN 'THROTTLE'
      WHEN v.days_to_arrival IS NOT NULL
       AND v.days_of_cover_avail_forecast - v.days_to_arrival < kk.watch_buffer_days  THEN 'WATCH'
      WHEN v.days_to_arrival IS NULL AND v.days_of_cover_avail_forecast < kk.no_inbound_watch THEN 'WATCH'
      WHEN v.season_gap_units > 0                                                     THEN 'WATCH'
      ELSE 'OK'
    END AS risk_state_forecast
  FROM asin_verdict v CROSS JOIN k kk
),
asin_reason AS (
  SELECT s.*,
    -- ONE expression, not two CTE levels: this view is at BigQuery's query-planning ceiling and
    -- asin_reason is inlined through fam_agg/fam_state on every path. See the flatness note below.
    CONCAT(
    CASE
      WHEN s.days_of_cover IS NULL THEN 'no measured demand — nothing to run out of'
      WHEN s.days_to_arrival IS NULL AND s.days_of_cover_avail < kk.no_inbound_crit THEN
        CONCAT('NOTHING BOOKED and only ', CAST(CAST(ROUND(s.days_of_cover_avail) AS INT64) AS STRING),
               ' days of cover — no replacement batch can land in time (lead is ',
               CAST(s.full_lead_days AS STRING), ' days)',
               IF(s.mfr_ready_qty > 0, CONCAT('; ', CAST(s.mfr_ready_qty AS STRING),
                  ' units are sitting finished at the factory with no shipment booked'), ''))
      WHEN s.days_to_arrival IS NULL AND s.days_of_cover_avail < kk.no_inbound_throttle THEN
        CONCAT('nothing booked; ', CAST(CAST(ROUND(s.days_of_cover_avail) AS INT64) AS STRING),
               ' days of cover against a ', CAST(s.full_lead_days AS STRING),
               '-day lead — book the shipment now or this turns CRITICAL',
               IF(s.mfr_ready_qty > 0, CONCAT(' (', CAST(s.mfr_ready_qty AS STRING),
                  ' units finished at the factory, waiting on a boat)'), ''))
      WHEN s.days_to_arrival IS NOT NULL AND s.days_of_cover_avail - s.days_to_arrival <= -kk.crit_dark_days THEN
        CONCAT('goes dark ', CAST(CAST(ROUND(s.days_to_arrival - s.days_of_cover_avail) AS INT64) AS STRING),
               ' days before the ', CAST(s.next_arrival_date AS STRING), ' arrival (',
               CAST(s.next_arrival_qty AS STRING), ' units)')
      WHEN s.days_to_arrival IS NOT NULL AND s.days_of_cover_avail - s.days_to_arrival < 0 THEN
        CONCAT('runs out ', CAST(CAST(ROUND(s.days_to_arrival - s.days_of_cover_avail) AS INT64) AS STRING),
               ' days short of the ', CAST(s.next_arrival_date AS STRING), ' arrival')
      WHEN s.season_gap_units > 0 AND s.days_of_cover_avail < s.full_lead_days + kk.season_lead_buffer THEN
        CONCAT(CAST(s.season_gap_units AS STRING),
               ' units short for the rest of the year counting every stage of the pipeline, and only ',
               CAST(CAST(ROUND(s.days_of_cover_avail) AS INT64) AS STRING), ' days of cover against a ',
               CAST(s.full_lead_days AS STRING), '-day lead — too late to make them; ads are the lever now')
      WHEN s.days_to_arrival IS NOT NULL AND s.days_of_cover_avail - s.days_to_arrival < kk.watch_buffer_days THEN
        CONCAT('reaches the ', CAST(s.next_arrival_date AS STRING), ' arrival with only ',
               CAST(CAST(ROUND(s.days_of_cover_avail - s.days_to_arrival) AS INT64) AS STRING),
               ' days to spare — no buffer for a late boat')
      WHEN s.days_to_arrival IS NULL AND s.days_of_cover_avail < kk.no_inbound_watch THEN
        CONCAT('nothing booked, ', CAST(CAST(ROUND(s.days_of_cover_avail) AS INT64) AS STRING),
               ' days of cover — still time to manufacture and ship, but the clock started')
      WHEN s.season_gap_units > 0 THEN
        CONCAT(CAST(s.season_gap_units AS STRING),
               ' units short for the rest of the year, but ',
               CAST(CAST(ROUND(s.days_of_cover_avail) AS INT64) AS STRING),
               ' days of cover against a ', CAST(s.full_lead_days AS STRING),
               '-day lead — this is a PO decision today, not an ads decision')
      ELSE 'cover reaches the next arrival with buffer and the season is covered'
    END,
    -- v27.59: the rate the verdict was taken on, and the forecast reading beside it. Appended to
    -- every reason string so no cover number on this row can be read without knowing which clock it
    -- came off, and so a forecast/actual disagreement is stated rather than silently resolved.
    CONCAT(
      ' [graded on ACTUAL sales ', CAST(s.velocity_actual AS STRING), '/day (',
      CASE s.velocity_actual_basis WHEN '7D' THEN 'last 7 days' WHEN '14D' THEN 'last 14 days'
                                   WHEN '30D' THEN 'last 30 days' ELSE 'no sales in 30 days' END,
      ' — the fastest of the 7/14/30-day trailing rates)',
      IF(s.velocity_forecast > s.velocity_actual,
         CONCAT('; the FORECAST rate is ', CAST(s.velocity_forecast AS STRING), '/day (',
                CAST(ROUND(SAFE_DIVIDE(s.velocity_forecast, NULLIF(s.velocity_actual, 0)), 1) AS STRING),
                'x higher) and would read ',
                COALESCE(CAST(CAST(ROUND(s.days_of_cover_avail_forecast) AS INT64) AS STRING), '—'),
                ' days of cover -> ', s.risk_state_forecast),
         IF(s.velocity_actual > s.velocity_forecast,
            CONCAT('; this is ABOVE the forecast rate of ', CAST(s.velocity_forecast AS STRING),
                   '/day — the product is selling FASTER than planned, and the forecast reading (',
                   COALESCE(CAST(CAST(ROUND(s.days_of_cover_avail_forecast) AS INT64) AS STRING), '—'),
                   ' days -> ', s.risk_state_forecast, ') is the optimistic one'),
            '')),
      IF(s.risk_state_forecast <> s.risk_state,
         CONCAT('. ⚠️ ACTUAL says ', s.risk_state, ', FORECAST says ', s.risk_state_forecast,
                ' — the grade follows ACTUAL (Ori 2026-08-13); the season question is the separate ',
                'season-gap column below, not this one'), ''),
      ']')) AS risk_reason,
    -- v27.62 — the SHORT form of the same verdict, for the `why` column of the inventory-detail
    -- table. ~6-10 words, same branch order as the paragraph above; the paragraph (including the
    -- [graded on ACTUAL …] trailer) becomes that cell's tooltip. Backend owns both strings.
    CASE
      WHEN s.days_of_cover IS NULL THEN 'no measured demand — nothing to run out of'
      WHEN s.days_to_arrival IS NULL AND s.days_of_cover_avail < kk.no_inbound_crit THEN
        CONCAT(CAST(CAST(ROUND(s.days_of_cover_avail) AS INT64) AS STRING),
               'd cover, nothing booked, ', CAST(s.full_lead_days AS STRING), 'd lead')
      WHEN s.days_to_arrival IS NULL AND s.days_of_cover_avail < kk.no_inbound_throttle THEN
        CONCAT(CAST(CAST(ROUND(s.days_of_cover_avail) AS INT64) AS STRING),
               'd cover, nothing booked — book the boat now')
      WHEN s.days_to_arrival IS NOT NULL AND s.days_of_cover_avail - s.days_to_arrival <= -kk.crit_dark_days THEN
        CONCAT('dark ', CAST(CAST(ROUND(s.days_to_arrival - s.days_of_cover_avail) AS INT64) AS STRING),
               'd before the ', FORMAT_DATE('%m-%d', s.next_arrival_date), ' boat')
      WHEN s.days_to_arrival IS NOT NULL AND s.days_of_cover_avail - s.days_to_arrival < 0 THEN
        CONCAT('runs out ', CAST(CAST(ROUND(s.days_to_arrival - s.days_of_cover_avail) AS INT64) AS STRING),
               'd short of the ', FORMAT_DATE('%m-%d', s.next_arrival_date), ' boat')
      WHEN s.season_gap_units > 0 AND s.days_of_cover_avail < s.full_lead_days + kk.season_lead_buffer THEN
        CONCAT(CAST(s.season_gap_units AS STRING), 'u short for the year, ',
               CAST(CAST(ROUND(s.days_of_cover_avail) AS INT64) AS STRING),
               'd cover — too late to make')
      WHEN s.days_to_arrival IS NOT NULL AND s.days_of_cover_avail - s.days_to_arrival < kk.watch_buffer_days THEN
        CONCAT('reaches the ', FORMAT_DATE('%m-%d', s.next_arrival_date), ' boat with ',
               CAST(CAST(ROUND(s.days_of_cover_avail - s.days_to_arrival) AS INT64) AS STRING),
               'd to spare')
      WHEN s.days_to_arrival IS NULL AND s.days_of_cover_avail < kk.no_inbound_watch THEN
        CONCAT(CAST(CAST(ROUND(s.days_of_cover_avail) AS INT64) AS STRING),
               'd cover, nothing booked — the clock started')
      WHEN s.season_gap_units > 0 THEN
        CONCAT(CAST(s.season_gap_units AS STRING), 'u short for the year — a PO call, not ads')
      ELSE 'cover reaches the next arrival, season covered'
    END AS risk_reason_short
  FROM asin_scored s CROSS JOIN k kk
),
asin_shares AS (
  SELECT a.*,
    ROUND(100 * SAFE_DIVIDE(a.units_90d, NULLIF(SUM(a.units_90d) OVER (PARTITION BY a.family), 0)), 1)
      AS family_units_share_pct
  FROM asin_reason a
),

-- ══ 2. FAMILY VERDICT ═════════════════════════════════════════════════════════════════════════
-- Set by the family's MATERIAL variations (>= min_family_share_pct of family units), so one dead
-- keychain colour cannot throttle a family; but if a quarter of the family's units sit in at-risk
-- variations the family escalates anyway, so death by a thousand cuts is not invisible either.
fam_agg AS (
  SELECT s.family,
    CAST(SUM(s.fba_qty) AS INT64)             AS fba_qty,
    CAST(SUM(s.awd_qty) AS INT64)             AS awd_qty,
    CAST(SUM(s.sellable_qty) AS INT64)        AS sellable_qty,
    CAST(SUM(s.in_transit_qty) AS INT64)      AS in_transit_qty,
    CAST(SUM(s.in_transit_awd_qty) AS INT64)  AS in_transit_awd_qty,
    CAST(SUM(s.mfr_ready_qty) AS INT64)       AS mfr_ready_qty,
    CAST(SUM(s.in_production_qty) AS INT64)   AS in_production_qty,
    CAST(SUM(s.total_pipeline_qty) AS INT64)  AS total_pipeline_qty,
    CAST(SUM(s.overdue_pending_qty) AS INT64) AS overdue_pending_qty,
    MIN(s.overdue_pending_oldest_eta)         AS overdue_pending_oldest_eta,
    ROUND(SUM(s.velocity_forecast), 3)        AS velocity_forecast,
    ROUND(SUM(s.velocity_30d), 3)             AS velocity_30d,
    ROUND(SUM(s.velocity_14d), 3)             AS velocity_14d,
    ROUND(SUM(s.velocity_7d), 3)              AS velocity_7d,
    -- NOTE: this is Σ(per-variation max of 7/14/30d), not max(Σ7d, Σ14d, Σ30d). The two differ when
    -- variations peak in different weeks, and the sum-of-maxes is the LARGER (so the shorter cover)
    -- — the same conservative direction the per-ASIN max already takes. It is the family throughput
    -- rate that days_bought divides by, and it must be the same rate the ASIN rows were graded on or
    -- the two clocks diverge again.
    ROUND(SUM(s.velocity_actual), 3)          AS velocity_actual,
    ROUND(SUM(s.velocity_used), 3)            AS velocity_used,   -- = velocity_actual (v27.59)
    CAST(SUM(s.units_90d) AS INT64)           AS units_90d,
    CAST(SUM(s.season_demand_units) AS INT64) AS season_demand_units,
    CAST(SUM(s.season_gap_units) AS INT64)    AS season_gap_units,
    CAST(MAX(s.full_lead_days) AS INT64)      AS full_lead_days,
    -- The binding variation among the material ones. Ordered by RISK first, then by cover: the
    -- family's problem is its worst-off variation, not merely its shortest-cover one. Pink Lollibox
    -- 2026-08-13 has the family's shortest cover (29 days) and is fine — 588 units are already in
    -- Amazon's hands and a boat lands in 28; White Lollibox has 99 days, 43% of the family's units
    -- and NOTHING booked. Ordering on cover alone would have named the wrong variation and told the
    -- wrong story. Fully tie-broken, never ANY_VALUE.
    ARRAY_AGG(
      IF(s.family_units_share_pct >= (SELECT min_family_share_pct FROM k) AND s.days_of_cover IS NOT NULL,
         STRUCT(s.asin, s.product, s.days_of_cover, s.days_of_cover_avail, s.risk_state, s.risk_reason,
                s.cover_basis, s.stockout_date, s.po_deadline, s.too_late_to_replenish,
                s.bridge_gap_days, s.next_arrival_date,
                -- v27.59: the forecast reading for the SAME variation, carried so the FAMILY row can
                -- print "actual says X / forecast says Y" without re-joining anything.
                s.days_of_cover_forecast, s.days_of_cover_avail_forecast, s.risk_state_forecast,
                s.cover_basis_forecast, s.velocity_actual, s.velocity_actual_basis, s.velocity_forecast,
                CASE s.risk_state WHEN 'CRITICAL' THEN 1 WHEN 'THROTTLE' THEN 2
                                  WHEN 'WATCH' THEN 3 ELSE 4 END AS rk),
         NULL)
      IGNORE NULLS ORDER BY
        CASE s.risk_state WHEN 'CRITICAL' THEN 1 WHEN 'THROTTLE' THEN 2 WHEN 'WATCH' THEN 3 ELSE 4 END,
        s.days_of_cover_avail, s.days_of_cover, s.asin LIMIT 1
    )[SAFE_OFFSET(0)] AS binding,
    ROUND(100 * SAFE_DIVIDE(
      SUM(IF(s.risk_state IN ('THROTTLE', 'CRITICAL'), s.units_90d, 0)),
      NULLIF(SUM(s.units_90d), 0)), 1) AS at_risk_units_share_pct,
    -- the same share on the FORECAST grade, so risk_state_forecast is a like-for-like parallel
    -- verdict and not a half-computed one
    ROUND(100 * SAFE_DIVIDE(
      SUM(IF(s.risk_state_forecast IN ('THROTTLE', 'CRITICAL'), s.units_90d, 0)),
      NULLIF(SUM(s.units_90d), 0)), 1) AS at_risk_units_share_pct_forecast,
    -- the binding variation chosen on the FORECAST grade — it can legitimately be a different
    -- variation from the actual-graded one (Fresh 2026-08-13)
    ARRAY_AGG(
      IF(s.family_units_share_pct >= (SELECT min_family_share_pct FROM k)
         AND s.days_of_cover_forecast IS NOT NULL,
         STRUCT(s.asin, s.product, s.days_of_cover_avail_forecast, s.risk_state_forecast), NULL)
      IGNORE NULLS ORDER BY
        CASE s.risk_state_forecast WHEN 'CRITICAL' THEN 1 WHEN 'THROTTLE' THEN 2
                                   WHEN 'WATCH' THEN 3 ELSE 4 END,
        s.days_of_cover_avail_forecast, s.days_of_cover_forecast, s.asin LIMIT 1
    )[SAFE_OFFSET(0)] AS binding_fc,
    -- v27.73 (Ori 2026-08-17, Task 4.6): the REDIRECT destination — the best HIGH-DEMAND sibling
    -- that can absorb the family's ad traffic. In stock = actual-graded cover >= 60d; ranked by
    -- demand (7/14/30d max rate), fully tie-broken. May legitimately be NULL (nowhere to aim).
    ARRAY_AGG(
      IF(s.days_of_cover_avail >= 60 AND s.velocity_actual > 0,
         STRUCT(s.asin, s.product, s.velocity_actual, s.days_of_cover_avail), NULL)
      IGNORE NULLS ORDER BY s.velocity_actual DESC, s.days_of_cover_avail DESC, s.asin LIMIT 1
    )[SAFE_OFFSET(0)] AS hero
  FROM asin_shares s
  GROUP BY 1
),
-- v27.73: REDIRECT MODE, the family's ads posture (Ori 2026-08-17: "change the target of the out
-- of stock target to the best high demand variation we have in stock. we should cut budget if we
-- have only low demand variation or the entire family is out of stock"). TRUE = the binding
-- variation is THROTTLE/CRITICAL but a different in-stock sibling sells at >= 50% of its rate —
-- so the play is re-aiming doorways (V_LOW_STOCK_REDIRECT emits the rows), NOT braking: bid
-- halves and budget cuts are suppressed below; waste-parks (non-converting) stay allowed — they
-- free cash and cost no cover either way.
rmode AS (
  SELECT g.family, g.hero,
    -- v27.80: the binding (dry) variation's ASIN, carried here so the redirect gate below can ask
    -- "is THIS campaign's only product the dry one?" without a second read of fam_agg. One extra
    -- column on an existing CTE — no new CTE, no new join (the planner-ceiling rule, see header).
    g.binding.asin AS binding_asin,
    (g.binding IS NOT NULL AND g.binding.risk_state IN ('THROTTLE', 'CRITICAL')
     AND g.hero IS NOT NULL AND g.hero.asin != g.binding.asin
     AND g.hero.velocity_actual >= 0.5 * NULLIF(g.binding.velocity_actual, 0)) AS redirect_mode
  FROM fam_agg g
),
fam_state AS (
  SELECT f.*,
    fs.first_sale_date,
    CAST(DATE_DIFF(t.d, fs.first_sale_date, MONTH) AS INT64) AS family_age_months,
    fa.nxt.eta                                               AS next_arrival_date,
    DATE_DIFF(fa.nxt.eta, t.d, DAY)                          AS days_to_arrival,
    fa.nxt.qty                                               AS next_arrival_qty,
    CASE WHEN f.velocity_used > 0 THEN ROUND(f.sellable_qty / f.velocity_used, 1) END AS family_flat_cover_days,
    CASE
      WHEN f.binding.risk_state IS NOT NULL AND f.binding.risk_state <> 'OK' THEN f.binding.risk_state
      WHEN COALESCE(f.at_risk_units_share_pct, 0) >= kk.at_risk_share_escalate THEN 'THROTTLE'
      ELSE COALESCE(f.binding.risk_state, 'OK')
    END AS risk_state,
    CASE
      WHEN f.binding_fc.risk_state_forecast IS NOT NULL AND f.binding_fc.risk_state_forecast <> 'OK'
        THEN f.binding_fc.risk_state_forecast
      WHEN COALESCE(f.at_risk_units_share_pct_forecast, 0) >= kk.at_risk_share_escalate THEN 'THROTTLE'
      ELSE COALESCE(f.binding_fc.risk_state_forecast, 'OK')
    END AS risk_state_forecast,
    CASE
      WHEN f.binding.risk_state IS NOT NULL AND f.binding.risk_state <> 'OK' THEN
        CONCAT(f.binding.product, ' is the binding variation — ', f.binding.risk_reason)
      WHEN COALESCE(f.at_risk_units_share_pct, 0) >= kk.at_risk_share_escalate THEN
        CONCAT(CAST(f.at_risk_units_share_pct AS STRING),
               '% of this family\'s units sit in variations that run dry before their replenishment',
               ' at the rate they are ACTUALLY selling')
      ELSE 'every material variation reaches its next arrival with buffer at the rate it is ACTUALLY selling'
    END AS risk_reason
  FROM fam_agg f
  CROSS JOIN inv_today t CROSS JOIN k kk
  LEFT JOIN first_sale   fs ON fs.family = f.family
  LEFT JOIN fam_arrival  fa ON fa.family = f.family
),

-- ══ 3. ADS INSIDE THE AT-RISK FAMILIES ════════════════════════════════════════════════════════
--
-- ── THE SHORT WINDOW (v27.59) ─────────────────────────────────────────────────────────────────
-- Ori 2026-08-13: "table format of critical low stock use the last day, 7 days window format. If it
-- wasn't profitable in last day AND 7 days (or 3 days in peak) reduce bid by 50%."
--
-- last_ads_day is the SAME anchor V_OOB_KEYWORD / V_OOB_BUDGET_PHASE use —
-- LEAST(MAX(date), FN_ADS_ANCHOR_CAP()) — so "last day" means the same day on every Weekly Run panel.
-- w_days comes from V_PEAK_WINDOW_RULE, the one place that owns "7 off peak, 3 in peak unless last
-- year proved 7 is better". Today (2026-08-13) that view returns in_peak = TRUE, w_days = 3
-- (BTS_2026, verdict NOT_PROVEN), so the window below is the last 3 days.
--
-- ⚠️ SETTLE CAVEAT — stated once, here, and then implemented as specified. Both short windows are
-- UNSETTLED: SP sales accrue to D+7 and SB to D+14, so a fresh day understates GP-ROAS. Requiring
-- BOTH the last day and the w-day window to fail is the guard Ori chose, and it is a real but
-- PARTIAL one — v27.74: complete days (Task 4.7) — the w-window is now the w_days COMPLETE days
-- ending the day BEFORE last_ads_day, so the two reads are adjacent and disjoint rather than
-- overlapping (the correlation note recorded here through v27.73 no longer applies), but both
-- remain UNSETTLED. Settled windows were NOT substituted: the whole
-- point of the rule is to react at the speed stock disappears. The settled 28d/90d columns stay
-- published on every row so the slow read is always one glance away.
--
-- The `wnd` CTE is deliberately tiny and referenced EXACTLY ONCE (in `tgt`), then carried forward as
-- plain columns. V_PEAK_WINDOW_RULE's own SOP records that expanding it ~30 times made a query
-- unplannable; `tgt` is inlined 3 times through tgt_ranked, so this costs 3 expansions, not 30.
wnd AS (
  SELECT
    (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`())
     FROM `onyga-482313.OI.FACT_AMAZON_ADS`)                                    AS last_ads_day,
    (SELECT AS STRUCT w_days, in_peak, w_days_reason
     FROM `onyga-482313.OI.V_PEAK_WINDOW_RULE`)                                 AS pw
),
camp AS (
  SELECT
    CAST(c.campaign_id AS STRING) AS cid,
    c.campaign_name,
    IF(UPPER(COALESCE(c.campaign_type, 'SP')) = 'SB', 'SB', 'SP') AS channel,
    c.daily_budget                                     AS campaign_budget,
    fm.parent_name                                     AS family,
    LOWER(c.campaign_name) LIKE '%brand defense%'      AS is_defense,
    COALESCE(cs.is_seasonal, FALSE)                    AS is_seasonal,
    COALESCE(cs.is_auto_campaign, FALSE)               AS is_auto_campaign,
    COALESCE(cs.is_oob_owned, FALSE)                   AS is_capped,
    COALESCE(cs.days_capped_7d, 0)                     AS days_capped_7d,
    cs.util_7d,
    -- DISPLAY ONLY, never a gate. See the launch-exemption section of the header: the exemption
    -- blocks ROAS-driven campaign money cuts in V_ADS_COACH; it does not block a stock decision.
    -- Joined so an exempt campaign shows its exemption NEXT TO a live proposal rather than vanishing.
    COALESCE(le.exempt_active, FALSE)                  AS launch_exempt_active,
    le.exempt_until                                    AS launch_exempt_until,
    le.envelope_state                                  AS launch_envelope_state,
    IF(UPPER(COALESCE(c.campaign_type, 'SP')) = 'SB', 14, 7) AS settle_days,
    DATE_SUB(t.d, INTERVAL IF(UPPER(COALESCE(c.campaign_type, 'SP')) = 'SB', 14, 7) DAY) AS settle_cut,
    IF(UPPER(COALESCE(c.campaign_type, 'SP')) = 'SB', kk.bid_floor_sb, kk.bid_floor_sp) AS bid_floor
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c
  JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` fm
    ON CAST(fm.campaign_id AS STRING) = CAST(c.campaign_id AS STRING)
  LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` cs
    ON CAST(cs.campaign_id AS STRING) = CAST(c.campaign_id AS STRING)
  LEFT JOIN `onyga-482313.OI.V_LAUNCH_EXEMPTION` le
    ON CAST(le.campaign_id AS STRING) = CAST(c.campaign_id AS STRING)
  CROSS JOIN ads_today t CROSS JOIN k kk
  WHERE c.campaign_state = 'ENABLED'
-- NOTE (v27.58): the at-risk filter used to live HERE, as
--   AND fm.parent_name IN (SELECT family FROM fam_state WHERE risk_state IN ('WATCH','THROTTLE','CRITICAL'))
-- and it had to move to tgt_class. `camp` is inlined once per path that reaches tgt_class — the
-- TARGET branch, the family roll-up and the campaign roll-up — so that one subquery expanded the
-- whole inventory chain (fam_state → fam_agg → asin_shares → V_SUPPLY_CHAIN_SUMMARY →
-- V_PLAN_FORECAST) three extra times and the finished view failed with "Not enough resources for
-- query planning" and then with an out-of-memory. tgt_class already JOINs fam_state, so filtering
-- there is free. The cost is that `tgt` aggregates FACT_AMAZON_ADS across all ENABLED campaigns
-- instead of only the at-risk families — a wider scan, but scans are cheap here and stages are not.
),
-- settled measures per (campaign, target). FACT_AMAZON_ADS is single-sourced per
-- (campaign, keyword, date) — verified 2026-08-13, no key appears under two source_tables — so a
-- plain SUM at this grain does not double-count the keyword and search-term reports.
-- v27.59: the SAME scan now also carries the two UNSETTLED short windows. The date filter opens up
-- to last_ads_day (it used to stop at settle_cut) and every settled measure gained an explicit
-- `a.date <= c.settle_cut` guard so widening the range cannot leak fresh days into a settled number.
-- Folding the short windows in here rather than adding a second CTE keeps the stage count flat —
-- this view is at BigQuery's query-planning ceiling (see the flatness note in 3a).
tgt AS (
  SELECT c.cid, CAST(a.keyword_id AS STRING) AS kid,
    ARRAY_AGG(a.targeting ORDER BY a.Ads_clicks DESC, a.date DESC, a.targeting LIMIT 1)[OFFSET(0)] AS target_text,
    CAST(SUM(IF(a.date <= c.settle_cut AND a.date > DATE_SUB(c.settle_cut, INTERVAL kk.act_window_days DAY), a.Ads_clicks, 0)) AS INT64) AS s28_clicks,
    ROUND(SUM(IF(a.date <= c.settle_cut AND a.date > DATE_SUB(c.settle_cut, INTERVAL kk.act_window_days DAY), a.Ads_cost, 0)), 2)        AS s28_spend,
    CAST(SUM(IF(a.date <= c.settle_cut AND a.date > DATE_SUB(c.settle_cut, INTERVAL kk.act_window_days DAY), a.Ads_orders, 0)) AS INT64) AS s28_orders,
    CAST(SUM(IF(a.date <= c.settle_cut AND a.date > DATE_SUB(c.settle_cut, INTERVAL kk.act_window_days DAY), a.Ads_units, 0)) AS INT64)  AS s28_units,
    ROUND(SUM(IF(a.date <= c.settle_cut AND a.date > DATE_SUB(c.settle_cut, INTERVAL kk.act_window_days DAY),
                 a.GROSS_PROFIT, 0)), 2)          AS s28_gp,
    CAST(SUM(IF(a.date <= c.settle_cut, a.Ads_clicks, 0)) AS INT64) AS s90_clicks,
    ROUND(SUM(IF(a.date <= c.settle_cut, a.Ads_cost, 0)), 2)        AS s90_spend,
    CAST(SUM(IF(a.date <= c.settle_cut, a.Ads_orders, 0)) AS INT64) AS s90_orders,
    ROUND(SUM(IF(a.date <= c.settle_cut,
                 a.GROSS_PROFIT, 0)), 2) AS s90_gp,
    -- ── the SHORT windows: the last ads day standing alone, and the w_days COMPLETE days before it ─
    CAST(SUM(IF(a.date = w.last_ads_day, a.Ads_clicks, 0)) AS INT64) AS d1_clicks,
    ROUND(SUM(IF(a.date = w.last_ads_day, a.Ads_cost, 0)), 2)        AS d1_spend,
    CAST(SUM(IF(a.date = w.last_ads_day, a.Ads_orders, 0)) AS INT64) AS d1_orders,
    CAST(SUM(IF(a.date = w.last_ads_day, a.Ads_units, 0)) AS INT64)  AS d1_units,
    ROUND(SUM(IF(a.date = w.last_ads_day,
                 a.GROSS_PROFIT, 0)), 2) AS d1_gp,
    -- v27.74: complete days (Task 4.7) — ends wm-1 (all five w_* measures)
    CAST(SUM(IF(a.date BETWEEN DATE_SUB(w.last_ads_day, INTERVAL w.pw.w_days DAY)
                           AND DATE_SUB(w.last_ads_day, INTERVAL 1 DAY), a.Ads_clicks, 0)) AS INT64) AS w_clicks,
    ROUND(SUM(IF(a.date BETWEEN DATE_SUB(w.last_ads_day, INTERVAL w.pw.w_days DAY)
                           AND DATE_SUB(w.last_ads_day, INTERVAL 1 DAY), a.Ads_cost, 0)), 2)        AS w_spend,
    CAST(SUM(IF(a.date BETWEEN DATE_SUB(w.last_ads_day, INTERVAL w.pw.w_days DAY)
                           AND DATE_SUB(w.last_ads_day, INTERVAL 1 DAY), a.Ads_orders, 0)) AS INT64) AS w_orders,
    CAST(SUM(IF(a.date BETWEEN DATE_SUB(w.last_ads_day, INTERVAL w.pw.w_days DAY)
                           AND DATE_SUB(w.last_ads_day, INTERVAL 1 DAY), a.Ads_units, 0)) AS INT64)  AS w_units,
    ROUND(SUM(IF(a.date BETWEEN DATE_SUB(w.last_ads_day, INTERVAL w.pw.w_days DAY)
                           AND DATE_SUB(w.last_ads_day, INTERVAL 1 DAY),
                a.GROSS_PROFIT, 0)), 2) AS w_gp,
    MAX(w.last_ads_day)     AS last_ads_day,
    MAX(w.pw.w_days)        AS w_days,
    LOGICAL_OR(w.pw.in_peak) AS in_peak,
    MAX(w.pw.w_days_reason) AS w_days_reason
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camp c ON CAST(a.campaign_id AS STRING) = c.cid
  CROSS JOIN k kk CROSS JOIN wnd w
  -- v27.61 (Ori 2026-08-13, comparing the panel against Amazon): the T_PRICE_COST_TIER JOIN IS GONE
  -- and GP now reads FACT's own GROSS_PROFIT column. The recompute was corrupting the number:
  -- it looked the cost tier up by ROUND(Ads_sales / Ads_units), but Ads_sales includes HALO sales
  -- of other products while Ads_units does not correspond to them, so the "implied price" is not
  -- the product's price. On VIDEO- BALL / 2026-08-12 it read $24.39/unit for a $13.99 product,
  -- matched a ~$21.50 tier, and overrode the real TOTAL_COST_PER_UNIT of $9.77 --
  -- GP $229.16 -> $37.17, GP-ROAS 3.69x -> 0.60x. The panel was proposing to halve the bids of a
  -- campaign that returned 3.69x. Verified: 317.09 - 9.77 x 13 = 229.16 = the stored GROSS_PROFIT
  -- exactly, and Amazon's own console reports $331.08 sales on $64.05 for the same ad group.
  -- FACT has charged tier COGS at load time since 2026-08-01, so re-deriving it here was both
  -- redundant and wrong. Account-wide the two agree to ~3% over 30 days, which is why this hid --
  -- the damage is per-row, on exactly the rows a decision gets made about.
  WHERE a.keyword_id IS NOT NULL
    AND a.date <= w.last_ads_day
    AND a.date >  DATE_SUB(c.settle_cut, INTERVAL kk.hist_window_days DAY)
  GROUP BY 1, 2
),
-- creative_type rides along inside the SAME struct rather than getting its own CTE level: the SB
-- bid floor splits $0.25 (video / brand) vs $0.10 (PRODUCT_COLLECTION, STORE_SPOTLIGHT), the same
-- split V_OOB_KEYWORD and FN_TARGET_BID_SHADOW use, and a separate `agf` CTE would be inlined three
-- times through tgt_ranked.
kw AS (
  SELECT CAST(d.campaign_id AS STRING) AS cid, CAST(d.keyword_id AS STRING) AS kid,
    ARRAY_AGG(STRUCT(d.keyword_text, d.match_type, d.state, d.bid,
                     CAST(d.ad_group_id AS STRING) AS ad_group_id, ag.creative_type)
              ORDER BY d.effective_from DESC, d.keyword_text LIMIT 1)[OFFSET(0)] AS cfg
  FROM `onyga-482313.OI.DIM_KEYWORD` d
  LEFT JOIN `onyga-482313.OI.DIM_AD_GROUP` ag
    ON CAST(ag.ad_group_id AS STRING) = CAST(d.ad_group_id AS STRING) AND ag.is_current
  WHERE d.is_current
  GROUP BY 1, 2
),
tgt_class AS (
  SELECT
    c.cid, c.campaign_name, c.channel, c.campaign_budget, c.family,
    c.is_defense, c.is_seasonal, c.is_auto_campaign, c.is_capped, c.days_capped_7d, c.util_7d,
    c.launch_exempt_active, c.launch_exempt_until, c.launch_envelope_state,
    c.settle_days, c.settle_cut,
    -- PER-ROW BID FLOOR (v27.59). No trim may land below it. SP $0.20 (house floor, the one
    -- V_OOB_KEYWORD bids to) · SB $0.25 (Amazon's platform minBid for video/brand) · SB
    -- PRODUCT_COLLECTION / STORE_SPOTLIGHT $0.10 (accepted in upload rounds 32-33). Same rule as
    -- V_OOB_KEYWORD and FN_TARGET_BID_SHADOW — it is not re-derived here, it is re-used.
    CASE WHEN c.channel <> 'SB' THEN kk.bid_floor_sp
         WHEN kw.cfg.creative_type IN ('PRODUCT_COLLECTION', 'STORE_SPOTLIGHT') THEN kk.bid_floor_sb_spot
         ELSE kk.bid_floor_sb END AS bid_floor,
    kw.cfg.creative_type AS creative_type,
    kw.cfg.ad_group_id   AS ad_group_id,
    t.kid, COALESCE(kw.cfg.keyword_text, t.target_text) AS target_text,
    UPPER(COALESCE(kw.cfg.match_type, '')) AS match_type,
    kw.cfg.state AS keyword_state, kw.cfg.bid AS current_bid,
    LOWER(COALESCE(kw.cfg.keyword_text, '')) IN ('close-match','loose-match','substitutes','complements') AS is_auto,
    UPPER(COALESCE(kw.cfg.match_type, '')) IN ('TARGETING_EXPRESSION','ASIN','ASIN EXPANDED','PRODUCT')   AS is_pt,
    t.s28_clicks, t.s28_spend, t.s28_orders, t.s28_units, t.s28_gp,
    ROUND(SAFE_DIVIDE(t.s28_gp, NULLIF(t.s28_spend, 0)), 3) AS s28_gp_roas,
    t.s90_clicks, t.s90_spend, t.s90_orders, t.s90_gp,
    ROUND(SAFE_DIVIDE(t.s90_gp, NULLIF(t.s90_spend, 0)), 3) AS s90_gp_roas,
    -- ── the SHORT windows (v27.59) — the format Ori asked for and the rule's only inputs ─────────
    t.last_ads_day, t.w_days, t.in_peak, t.w_days_reason,
    t.d1_clicks, t.d1_spend, t.d1_orders, t.d1_units, t.d1_gp,
    ROUND(SAFE_DIVIDE(t.d1_gp, NULLIF(t.d1_spend, 0)), 3) AS d1_gp_roas,
    t.w_clicks, t.w_spend, t.w_orders, t.w_units, t.w_gp,
    ROUND(SAFE_DIVIDE(t.w_gp, NULLIF(t.w_spend, 0)), 3) AS w_gp_roas,
    ROUND(t.s28_spend / kk.act_window_days, 3) AS spend_per_day,
    ROUND(t.s28_units / kk.act_window_days, 3) AS units_per_day,
    -- The SHORT-window daily rates. The CRITICAL halve is DECIDED on the short window, so it is
    -- also SIZED on it — a settled-28d rate would price today's move off a month-old spend level,
    -- and on a launch family climbing hard (LolliBall runs 3.4/d at 60 days and 8.0/d at 7) that is
    -- materially wrong in both the dollars and the days-of-cover it claims. The settled rates stay
    -- published beside these so the two readings are always comparable.
    ROUND(SAFE_DIVIDE(t.w_spend, NULLIF(t.w_days, 0)), 3) AS w_spend_per_day,
    ROUND(SAFE_DIVIDE(t.w_units, NULLIF(t.w_days, 0)), 3) AS w_units_per_day,
    f.velocity_used   AS family_velocity,
    f.sellable_qty    AS family_sellable_qty,
    f.family_flat_cover_days,
    f.risk_state      AS risk_state,
    -- family context carried down to target grain so every reason string can name the constraint
    -- it is reacting to without the panel joining anything back up.
    f.binding.days_of_cover_avail AS binding_cover_days,   -- the days_bought clock (see header)
    f.binding.product             AS binding_product_name,
    f.binding.stockout_date       AS family_stockout_date,
    f.full_lead_days              AS family_full_lead_days,
    f.next_arrival_date           AS family_next_arrival_date,
    -- Five classes, and the two that look alike are deliberately separated:
    --   NON_CONVERTING  zero orders on the settled 28d AND zero on the settled 90d — clean waste.
    --   STALLED         zero on 28d but it HAS converted inside 90d. "girls gifts age 8-10"
    --                   (Lollibox, 2026-08-13) is 3,523 settled clicks / 72 orders / 1.04x over 90
    --                   days and simply blank for the last four weeks. Calling that free to cut is
    --                   how a proven keyword gets killed on a month of noise, so it gets its own
    --                   bucket and its own verb: a judgement, not a freebie.
    --   ALREADY_OFF     spent inside the window but the keyword is no longer ENABLED — nothing to do.
    CASE
      WHEN c.is_defense THEN 'DEFENSE'
      WHEN t.s28_orders > 0 THEN 'CONVERTING'
      WHEN UPPER(COALESCE(kw.cfg.state, 'ENABLED')) <> 'ENABLED' THEN 'ALREADY_OFF'
      WHEN t.s28_clicks < kk.nonconv_min_clicks THEN 'THIN'
      WHEN t.s90_orders > 0 THEN 'STALLED'
      ELSE 'NON_CONVERTING'
    END AS target_class
  FROM tgt t
  JOIN camp c ON c.cid = t.cid
  JOIN fam_state f ON f.family = c.family
  LEFT JOIN kw ON kw.cid = t.cid AND kw.kid = t.kid
  CROSS JOIN k kk
  WHERE (t.s28_clicks > 0 OR t.s28_spend > 0)
    -- the at-risk gate (moved here from `camp` — see the note there)
    AND f.risk_state IN ('WATCH', 'THROTTLE', 'CRITICAL')
),
-- ── 3a. THE CRITICAL SHORT-WINDOW HALVE (v27.59) ───────────────────────────────────────────────
-- Ori 2026-08-13, verbatim: "table format of critical low stock use the last day, 7 days window
-- format. If it wasn't profitable in last day AND 7 days (or 3 days in peak) reduce bid by 50%."
--
-- THE RULE, stated exactly:
--   family risk_state = 'CRITICAL'                       (WATCH/THROTTLE keep the old behaviour)
--   AND the target is not brand defense                  (defense is NEVER touched, in any state)
--   AND it spent money inside the w-day window           (no spend = no evidence and nothing to slow)
--   AND the w-day window did NOT clear 1.0x GP-ROAS
--   AND the last complete ads day did NOT clear 1.0x GP-ROAS
--   -> reduce the bid by 50%, floored at the row's own bid floor.
-- EITHER window profitable -> no action. Both must fail. That is the whole test.
--
-- WHY IT IS DELIBERATELY BLUNT. This is not a ROAS optimiser. The family is running out of stock and
-- the objective is to SLOW SALES until the next batch lands, so there is no click bar, no 90-day
-- reprieve and no breakeven arithmetic — all three of those exist to protect a keyword's long-run
-- value, and a keyword's long-run value is not the binding constraint when the units it sells cannot
-- be replaced this season. It REPLACED the v27.58 breakeven-bid ladder (breakeven_bid,
-- bid_cut_viable, keep_factor, the 10-click evidence gate and the proven-over-90d reprieve) outright.
--
-- WHAT "NOT PROFITABLE" MEANS, and the one judgement call in it. GP-ROAS < 1.0 on a window that
-- actually spent. A window with ZERO spend is published as 'NO_SPEND', not as a failure:
--   * the w-day window must have spend — with none there is no evidence and, more to the point,
--     nothing to slow down. The row gets STOCK_WATCH and says so.
--   * the LAST DAY having no spend does NOT veto the w-window verdict. The guard Ori asked for
--     exists because last-day data is unsettled and UNDERSTATES ROAS — clicks whose orders have not
--     landed. A day with no clicks at all cannot be understating anything, so it carries no settle
--     risk and cannot be the thing that spares a target. profit_1d publishes YES / NO / NO_SPEND so
--     which of the three happened is visible on the row rather than inferred.
--
-- ⚠️ v27.74: complete days (Task 4.7) — the w-window ends the day BEFORE the last ads day, so the
-- two windows no longer overlap; "both failed" is two adjacent, disjoint reads. Both are still
-- unsettled — see the settle caveat above `wnd`.
--
-- Each fact is published as its own column so the panel can show WHY a row was or was not promoted,
-- and so a wrong promotion is debuggable without re-reading this SQL.
--
-- ⚠️ THE CTE CHAIN BELOW IS DELIBERATELY FLAT. The first attempt used one CTE per step
-- (econ → verdict → plan → money → flow → action) and BigQuery refused the finished view with
-- "Not enough resources for query planning - too many subqueries or query is too complex":
-- CTEs are INLINED at every reference, and tgt_ranked is referenced three times (the TARGET
-- branch, the family roll-up and the campaign roll-up), so every extra level was paid for three
-- times on top of the already-deep inventory chain. Predicates are therefore repeated inline
-- rather than given their own level. Keep it flat; a "tidier" split will not compile.
tgt_econ AS (
  SELECT tc.*,
    kk.conv_evidence_clicks, kk.breakeven_roas, kk.halve_factor,
    kk.max_throttle_share, kk.min_daily_budget,
    (tc.risk_state = 'CRITICAL')                                     AS family_is_critical,
    (tc.s28_clicks >= kk.conv_evidence_clicks)                       AS has_settled_evidence,
    -- the STALLED reasoning in reverse — kept for the WATCH/THROTTLE reason strings only. It is NOT
    -- a gate on the CRITICAL halve: a keyword proven last quarter still sells units this family
    -- cannot replace this quarter.
    (tc.s90_gp_roas IS NOT NULL AND tc.s90_gp_roas >= kk.breakeven_roas
       AND tc.s90_clicks >= kk.conv_evidence_clicks)                 AS proven_over_90d,
    (tc.s28_gp_roas IS NOT NULL AND tc.s28_gp_roas < kk.breakeven_roas) AS below_breakeven_28d,
    -- ── the two short-window verdicts, three-state and published ────────────────────────────────
    CASE WHEN tc.d1_spend IS NULL OR tc.d1_spend <= 0 THEN 'NO_SPEND'
         WHEN tc.d1_gp_roas >= kk.breakeven_roas      THEN 'YES'
         ELSE 'NO' END                                               AS profit_1d,
    CASE WHEN tc.w_spend IS NULL OR tc.w_spend <= 0 THEN 'NO_SPEND'
         WHEN tc.w_gp_roas >= kk.breakeven_roas      THEN 'YES'
         ELSE 'NO' END                                               AS profit_w,
    -- PROMOTION. Both windows must fail. DEFENSE can never reach here (its own target_class);
    -- ALREADY_OFF is excluded because there is no live bid to change.
    (tc.risk_state = 'CRITICAL'
      AND tc.target_class NOT IN ('DEFENSE', 'ALREADY_OFF')
      AND tc.w_spend > 0
      AND NOT (tc.w_gp_roas IS NOT NULL AND tc.w_gp_roas >= kk.breakeven_roas)
      AND NOT (tc.d1_spend > 0 AND tc.d1_gp_roas IS NOT NULL
               AND tc.d1_gp_roas >= kk.breakeven_roas))              AS escalated
  FROM tgt_class tc CROSS JOIN k kk
),
tgt_plan AS (
  SELECT e.*,
    -- THE HALVE, and the floor clamp. bid x 0.5, never below the row's own floor. When the bid is
    -- ALREADY at or under the floor there is no executable cut left — the row is reported at the
    -- floor rather than pretending a move exists. halve_viable is that fact, published.
    (e.escalated AND e.current_bid IS NOT NULL AND e.current_bid > e.bid_floor + 0.005) AS halve_viable,
    CASE WHEN e.escalated AND e.current_bid IS NOT NULL AND e.current_bid > e.bid_floor + 0.005
         THEN GREATEST(ROUND(e.current_bid * e.halve_factor, 2), e.bid_floor) END AS suggested_bid,
    -- v27.60: publish the clamp as a FLAG. LowStockPhase.tsx:500 was recomputing
    -- `suggestedBid > currentBid * 0.5 + 0.001` in TypeScript to decide whether to show the
    -- "clamped up to the floor" tooltip — that hardcodes the halve factor in React and re-derives a
    -- verdict the view already knows. Backend owns the verdict (Ori's standing rule); the panel
    -- renders it.
    (e.escalated AND e.current_bid IS NOT NULL AND e.current_bid > e.bid_floor + 0.005
       AND ROUND(e.current_bid * e.halve_factor, 2) < e.bid_floor) AS bid_clamped_to_floor,
    -- the fraction of the bid that SURVIVES the cut — 0.5 unless the floor clamped it
    CASE WHEN e.escalated AND e.current_bid IS NOT NULL AND e.current_bid > e.bid_floor + 0.005
         THEN ROUND(GREATEST(ROUND(e.current_bid * e.halve_factor, 2), e.bid_floor) / e.current_bid, 4)
    END AS keep_factor,
    -- DOLLARS. First order: scaling the bid by r scales CPC (and so spend) by r at constant click
    -- volume, so a halved bid frees half the daily spend. Waste (in a non-CRITICAL family) is freed
    -- outright. A protected row frees nothing — its spend is the price of units you chose to keep
    -- buying. ⚠️ Inside a CAPPED campaign these dollars are NOT free: the budget is spent regardless
    -- and a LOWER bid buys MORE clicks for the same money, so they only leave when the paired budget
    -- cut on the CAMPAIGN row leaves with them. That pairing is where this number becomes true.
    CASE
      WHEN e.escalated AND e.current_bid IS NOT NULL AND e.current_bid > e.bid_floor + 0.005
        THEN ROUND(e.w_spend_per_day
                   * (1 - GREATEST(ROUND(e.current_bid * e.halve_factor, 2), e.bid_floor) / e.current_bid), 3)
      -- the waste park frees its settled daily spend — but ONLY when the waste park is actually the
      -- action. In a CRITICAL family a short-window winner is PROTECTED above this class (see the
      -- action CASE), and a protected row frees nothing.
      WHEN e.target_class = 'NON_CONVERTING' AND NOT e.escalated
           AND NOT (e.risk_state = 'CRITICAL' AND (e.profit_1d = 'YES' OR e.profit_w = 'YES'))
        THEN e.spend_per_day
      ELSE 0.0
    END AS dollars_freed_per_day,
    -- UNITS this action stops selling, same first-order model and the same short window. Zero for a
    -- non-converting waste park BY CONSTRUCTION — it bought no units, so parking it buys no days of
    -- cover either.
    CASE
      WHEN e.escalated AND e.current_bid IS NOT NULL AND e.current_bid > e.bid_floor + 0.005
        THEN ROUND(e.w_units_per_day
                   * (1 - GREATEST(ROUND(e.current_bid * e.halve_factor, 2), e.bid_floor) / e.current_bid), 4)
      ELSE 0.0
    END AS units_removed_per_day
  FROM tgt_econ e
),
tgt_action AS (
  SELECT f.*,
    -- DAYS OF COVER BOUGHT — on the BINDING variation's clock, proportional model (see header).
    CASE
      WHEN f.units_removed_per_day <= 0 THEN 0.0
      WHEN f.family_velocity IS NULL OR f.family_velocity <= 0 THEN NULL
      WHEN f.binding_cover_days IS NULL THEN NULL
      WHEN f.units_removed_per_day >= f.max_throttle_share * f.family_velocity THEN NULL
      ELSE ROUND(f.binding_cover_days * f.units_removed_per_day
                 / (f.family_velocity - f.units_removed_per_day), 1)
    END AS days_bought,
    -- what a FULL pause would buy — the option price on a protected winner, and the number that
    -- makes the size of the trade visible without proposing it.
    -- v27.59: measured on the SHORT window, because family_velocity is now a trailing-actual rate
    -- (fastest of 7/14/30d) and pricing ad units off a settled 28-day rate against a 7-day family
    -- rate would divide two different clocks.
    CASE
      WHEN f.w_units_per_day <= 0 THEN 0.0
      WHEN f.family_velocity IS NULL OR f.family_velocity <= 0 THEN NULL
      WHEN f.binding_cover_days IS NULL THEN NULL
      WHEN f.w_units_per_day >= f.max_throttle_share * f.family_velocity THEN NULL
      ELSE ROUND(f.binding_cover_days * f.w_units_per_day / (f.family_velocity - f.w_units_per_day), 1)
    END AS days_bought_if_paused,
    ROUND(100 * SAFE_DIVIDE(f.w_units_per_day, NULLIF(f.family_velocity, 0)), 1) AS pct_of_family_velocity,
    -- ACTION ORDER (v27.59). In a CRITICAL family the halve rule is evaluated FIRST and is the only
    -- rule that fires, for every non-defense target; the older class actions (waste park, stalled
    -- trim, thin watch) survive untouched for WATCH/THROTTLE families and for CRITICAL rows the
    -- halve rule did not reach.
    CASE
      WHEN f.target_class = 'DEFENSE'     THEN 'STOCK_PROTECT'
      WHEN f.target_class = 'ALREADY_OFF' THEN 'STOCK_NONE'
      -- ⚠️ IN A CRITICAL FAMILY THE SHORT WINDOW OUTRANKS THE SETTLED CLASS, in both directions.
      -- This branch sits ABOVE the waste park deliberately. "surprise balls for girls" (VIDEO- BALL,
      -- 2026-08-13) is classed NON_CONVERTING — zero orders on the settled 28d AND the settled 90d —
      -- yet it bought 5 orders at 5.52x GP-ROAS in the last 3 days. It is not waste, it is a fresh
      -- keyword whose orders have not settled, and parking it would kill a live winner on stale
      -- evidence. Ori: genuinely profitable targets are priced, not proposed.
      WHEN f.family_is_critical AND (f.profit_1d = 'YES' OR f.profit_w = 'YES') THEN 'STOCK_PROTECT'
      WHEN f.escalated AND f.halve_viable
        THEN IF(f.is_capped, 'STOCK_BID_HALVE_AND_BUDGET', 'STOCK_BID_HALVE')
      WHEN f.escalated AND f.current_bid IS NULL THEN 'STOCK_NO_BID'
      WHEN f.escalated                            THEN 'STOCK_AT_FLOOR'
      WHEN f.target_class = 'THIN'        THEN 'STOCK_WATCH'
      WHEN f.target_class = 'STALLED'     THEN 'STOCK_TRIM_STALLED'
      WHEN f.target_class = 'NON_CONVERTING'
        THEN IF(f.is_capped, 'STOCK_CUT_WASTE_AND_BUDGET', 'STOCK_CUT_WASTE')
      WHEN f.family_is_critical AND f.profit_w = 'NO_SPEND' THEN 'STOCK_WATCH'
      ELSE 'STOCK_PROTECT'
    END AS action,
    CASE
      WHEN f.target_class = 'DEFENSE' THEN
        'brand defense — never profit-judged, never throttled on ROAS, in any risk state; the moat stays bought'
      WHEN f.target_class = 'ALREADY_OFF' THEN
        CONCAT('already ', LOWER(COALESCE(f.keyword_state, 'off')), ' — the $',
               CAST(f.s28_spend AS STRING), ' is history, there is nothing left to cut')
      -- ── CRITICAL + profitable on a short window: PROTECTED, above every settled-class action ──
      WHEN f.family_is_critical AND f.profit_1d = 'YES' AND f.profit_w = 'YES' THEN
        CONCAT('PROFITABLE ON BOTH SHORT WINDOWS — last day (', CAST(f.last_ads_day AS STRING),
               ') ', CAST(f.d1_gp_roas AS STRING), 'x on $', CAST(f.d1_spend AS STRING),
               ', last ', CAST(f.w_days AS STRING), 'd ', CAST(f.w_gp_roas AS STRING), 'x on $',
               CAST(f.w_spend AS STRING),
               '. It pays for its own stock, so it stays PROTECTED even in a CRITICAL family: ',
               'cutting a real winner to save units is a judgement only you make. The throttle is ',
               'priced (days if paused), never proposed.',
               IF(f.target_class IN ('NON_CONVERTING', 'STALLED', 'THIN'),
                  CONCAT(' ⚠️ Its SETTLED class is ', f.target_class, ' (', CAST(f.s28_clicks AS STRING),
                         ' clicks / ', CAST(f.s28_orders AS STRING), ' orders on the settled 28d, ',
                         CAST(f.s90_orders AS STRING), ' on the settled 90d) — the settled windows ',
                         'have not caught up with it yet. The short window wins here: this is a live ',
                         'winner, not waste.'), ''))
      WHEN f.family_is_critical AND f.profit_w = 'YES' THEN
        CONCAT('PROFITABLE on the ', CAST(f.w_days AS STRING), '-day window (',
               CAST(f.w_gp_roas AS STRING), 'x GP-ROAS on $', CAST(f.w_spend AS STRING),
               ') — the rule needs BOTH windows to fail and this one cleared 1.0x, so no cut. Last ',
               'day was ', IF(f.profit_1d = 'NO_SPEND', 'quiet (no spend)',
                              CONCAT(CAST(f.d1_gp_roas AS STRING), 'x on $',
                                     CAST(f.d1_spend AS STRING))),
               '. PROTECTED.',
               IF(f.target_class IN ('NON_CONVERTING', 'STALLED', 'THIN'),
                  CONCAT(' ⚠️ Settled class ', f.target_class,
                         ' — the settled windows have not caught up; the short window wins.'), ''))
      WHEN f.family_is_critical AND f.profit_1d = 'YES' THEN
        CONCAT('PROFITABLE on the last day (', CAST(f.d1_gp_roas AS STRING), 'x GP-ROAS on $',
               CAST(f.d1_spend AS STRING), ') even though the ', CAST(f.w_days AS STRING),
               '-day window is ', COALESCE(CAST(f.w_gp_roas AS STRING), '—'),
               'x — the rule needs BOTH to fail, so no cut. PROTECTED.',
               IF(f.target_class IN ('NON_CONVERTING', 'STALLED', 'THIN'),
                  CONCAT(' ⚠️ Settled class ', f.target_class,
                         ' — the settled windows have not caught up; the short window wins.'), ''))
      -- ── the v27.59 CRITICAL halve, and the three ways it stops short of a move ────────────────
      -- v27.99 (audit C3): the sentence asserted 'Both under 1.0x' unconditionally, counting an
      -- empty or still-filling last day as one of two FAILED windows. THE GATE IS CORRECT and is
      -- untouched — `escalated` requires the week to have spend and to fail on its own, and the
      -- last day can only veto (it spares a target, it never condemns one), exactly per the rule.
      -- The view already publishes a three-state profit_1d carrying 'NO_SPEND'; the sentence threw
      -- it away. Use it: when the last day has no spend, say so and let the week be the verdict.
      WHEN f.escalated AND f.halve_viable THEN
        CONCAT('NOT PROFITABLE ON THE SETTLED WINDOW in a CRITICAL family. Last day (',
               CAST(f.last_ads_day AS STRING), '): ',
               IF(f.profit_1d = 'NO_SPEND', 'no spend — nothing ran, so there is nothing to judge there',
                  CONCAT(CAST(f.d1_clicks AS STRING), ' clicks, ',
                         CAST(f.d1_orders AS STRING), ' orders, $', CAST(f.d1_spend AS STRING), ', ',
                         COALESCE(CAST(f.d1_gp_roas AS STRING), '—'), 'x GP-ROAS')), '. Last ',
               CAST(f.w_days AS STRING), ' days', IF(f.in_peak, ' (peak window)', ''), ': ',
               CAST(f.w_clicks AS STRING), ' clicks, ', CAST(f.w_orders AS STRING), ' orders, $',
               CAST(f.w_spend AS STRING), ', ', COALESCE(CAST(f.w_gp_roas AS STRING), '—'),
               'x GP-ROAS. ',
               IF(f.profit_1d = 'NO_SPEND',
                  CONCAT('The ', CAST(f.w_days AS STRING), '-day window is under 1.0x and the last day has no volume to overturn it, so'),
                  'Both under 1.0x, so'),
               ' every unit it does sell is a unit ', f.family,
               ' cannot replace (', CAST(CAST(ROUND(f.binding_cover_days) AS INT64) AS STRING),
               ' days of cover on ', f.binding_product_name, ', ',
               IF(f.family_next_arrival_date IS NULL, 'NOTHING BOOKED',
                  CONCAT('next boat ', CAST(f.family_next_arrival_date AS STRING))),
               ', ', CAST(f.family_full_lead_days AS STRING), '-day lead). Halve the bid $',
               CAST(f.current_bid AS STRING), ' → $', CAST(f.suggested_bid AS STRING),
               IF(f.suggested_bid > ROUND(f.current_bid * f.halve_factor, 2),
                  CONCAT(' (a straight 50% would be $',
                         CAST(ROUND(f.current_bid * f.halve_factor, 2) AS STRING),
                         ' — clamped up to the $', CAST(f.bid_floor AS STRING), ' ', f.channel,
                         IF(f.creative_type IN ('PRODUCT_COLLECTION', 'STORE_SPOTLIGHT'),
                            ' spotlight', ''), ' floor)'), ''),
               '. This is a STOCK brake, not a ROAS verdict: the point is to SLOW SALES until the ',
               'next batch lands, so there is no click bar and no 90-day reprieve. Frees ~$',
               CAST(ROUND(f.dollars_freed_per_day, 2) AS STRING), '/day.',
               IF(f.launch_exempt_active,
                  CONCAT(' Launch-exempt until ', CAST(f.launch_exempt_until AS STRING),
                         ' — that exemption blocks ROAS-driven CAMPAIGN BUDGET cuts in the coach and is ',
                         'deliberately NOT applied here: this is a stock decision at target grain.'), ''),
               IF(f.is_capped,
                  CONCAT(' ⚠️ PAIRED: capped ', CAST(f.days_capped_7d AS STRING),
                         '/7 days — a lower bid on a capped campaign buys MORE clicks for the same ',
                         'budget and would sell the last stock FASTER. The budget must come down with ',
                         'it (campaign row); unpaired, this move is worse than doing nothing.'), ''))
      WHEN f.escalated AND f.current_bid IS NULL THEN
        CONCAT('not profitable on either short window in a CRITICAL family (last day ',
               COALESCE(CAST(f.d1_gp_roas AS STRING), 'no spend'), 'x · last ',
               CAST(f.w_days AS STRING), 'd ', COALESCE(CAST(f.w_gp_roas AS STRING), 'no spend'),
               'x) — but there is NO BID on this target to halve (SB product target / bid inherited ',
               'from the ad group). Nothing executable at target grain; the lever here is the ',
               'campaign budget.')
      WHEN f.escalated THEN
        CONCAT('not profitable on either short window in a CRITICAL family (last day ',
               COALESCE(CAST(f.d1_gp_roas AS STRING), 'no spend'), 'x · last ',
               CAST(f.w_days AS STRING), 'd ', COALESCE(CAST(f.w_gp_roas AS STRING), 'no spend'),
               'x) — but the bid is already at the $', CAST(f.bid_floor AS STRING), ' ', f.channel,
               IF(f.creative_type IN ('PRODUCT_COLLECTION', 'STORE_SPOTLIGHT'), ' spotlight', ''),
               ' floor ($', CAST(f.current_bid AS STRING),
               '). A 50% cut would land under the floor and is not executable, so nothing is ',
               'proposed on the bid.')
      WHEN f.target_class = 'THIN' THEN
        CONCAT('only ', CAST(f.s28_clicks AS STRING), ' settled clicks — too thin to call either way')
      WHEN f.target_class = 'STALLED' THEN
        CONCAT('blank for the settled 28 days (', CAST(f.s28_clicks AS STRING), ' clicks, 0 orders, $',
               CAST(f.s28_spend AS STRING), ') BUT it has converted inside 90: ',
               CAST(f.s90_clicks AS STRING), ' clicks, ', CAST(f.s90_orders AS STRING), ' orders, ',
               COALESCE(CAST(f.s90_gp_roas AS STRING), '—'),
               'x GP-ROAS. Trimming it is a judgement call, not free money — it may simply be between seasons.')
      WHEN f.target_class = 'NON_CONVERTING' AND f.is_capped THEN
        CONCAT('PAIRED. ', CAST(f.s28_clicks AS STRING), ' settled clicks, 0 orders, $',
               CAST(f.s28_spend AS STRING), ' — but this campaign was out of budget ',
               CAST(f.days_capped_7d AS STRING),
               ' of the last 7 days, so parking this target alone hands its budget to the converting ',
               'targets beside it and sells the remaining stock FASTER. Park it AND cut $',
               CAST(ROUND(f.spend_per_day, 2) AS STRING), '/day off the campaign budget.')
      WHEN f.target_class = 'NON_CONVERTING' THEN
        CONCAT(CAST(f.s28_clicks AS STRING), ' settled clicks, 0 orders, $', CAST(f.s28_spend AS STRING),
               ' — free to cut: it buys no units, so it buys no days of cover either. Saves $',
               CAST(ROUND(f.spend_per_day, 2) AS STRING), '/day.')
      -- ── CRITICAL, but there was nothing live to slow ─────────────────────────────────────────
      WHEN f.family_is_critical AND f.profit_w = 'NO_SPEND' THEN
        CONCAT('no spend in the last ', CAST(f.w_days AS STRING), ' days',
               IF(f.in_peak, ' (peak window)', ''),
               ' — the halve rule needs live spend to slow down, and there is none here. Its settled ',
               '28d is ', CAST(f.s28_clicks AS STRING), ' clicks / $', CAST(f.s28_spend AS STRING),
               ', so it was live recently but is quiet now. Watching, not cutting.')
      WHEN f.target_class = 'CONVERTING' AND f.s28_gp_roas IS NULL THEN
        'converting, but no settled GP figure to judge it on (no settled spend / no cost basis) — PROTECTED, not proposed'
      WHEN f.target_class = 'CONVERTING' AND NOT f.below_breakeven_28d THEN
        CONCAT('PROFITABLE — ', CAST(f.s28_gp_roas AS STRING), 'x GP-ROAS on the settled 28d (',
               CAST(f.s28_orders AS STRING), ' orders). Priced, not proposed.')
      ELSE
        CONCAT('converting on the settled window (', CAST(f.s28_orders AS STRING), ' orders, ',
               COALESCE(CAST(f.s28_gp_roas AS STRING), '—'), 'x GP-ROAS) — PROTECTED. ', f.family,
               ' is ', f.risk_state, ', not CRITICAL: only a CRITICAL family runs the short-window ',
               'halve, so here the honest levers are still the waste cut and the PO. The throttle ',
               'is priced (days if paused), not suggested.')
    END AS action_reason,
    -- ── THE SHORT WHY (v27.62 — Ori 2026-08-13: "there should be actions and the why must be
    -- short and readable") ────────────────────────────────────────────────────────────────────
    -- ONE clause, ~6-10 words. This is what the panel's visible `why` column prints; the paragraph
    -- above is the SAME verdict in full and moves into that cell's title= tooltip. Both strings are
    -- the VIEW's words — the panel never truncates, re-words, or composes prose in TypeScript
    -- (feedback_all_logic_in_backend). The branch order below is identical to action_reason above,
    -- line for line, so the short form can never say something the long form does not.
    -- Grammar, everywhere: <the evidence> — <the consequence>. Ori's shape: "23d cover, dry 09-08".
    CASE
      WHEN f.target_class = 'DEFENSE' THEN 'brand defense — never profit-judged'
      WHEN f.target_class = 'ALREADY_OFF' THEN
        CONCAT('already ', LOWER(COALESCE(f.keyword_state, 'off')), ' — nothing left to cut')
      WHEN f.family_is_critical AND f.profit_1d = 'YES' AND f.profit_w = 'YES' THEN
        CONCAT(FORMAT('%.2f', f.d1_gp_roas), 'x last day, ', FORMAT('%.2f', f.w_gp_roas), 'x ',
               CAST(f.w_days AS STRING), 'd — pays for its own stock')
      WHEN f.family_is_critical AND f.profit_w = 'YES' THEN
        CONCAT(FORMAT('%.2f', f.w_gp_roas), 'x on ', CAST(f.w_days AS STRING),
               'd — one window clear, no cut')
      WHEN f.family_is_critical AND f.profit_1d = 'YES' THEN
        CONCAT(FORMAT('%.2f', f.d1_gp_roas), 'x last day — one window clear, no cut')
      -- explanation audit 2026-08-16: evidence + move + WHY (slow sales), one line. The date
      -- leads when the row has one; else the cover-days clock; the bid move is spelled out.
      WHEN f.escalated AND f.halve_viable THEN
        CONCAT(CASE WHEN f.family_stockout_date IS NOT NULL
                    THEN CONCAT('stock out ~', FORMAT_DATE('%m-%d', f.family_stockout_date))
                    WHEN f.binding_cover_days IS NOT NULL
                    THEN CONCAT('runs dry in ~', CAST(CAST(ROUND(f.binding_cover_days) AS INT64) AS STRING), 'd')
                    ELSE 'stock running out' END,
               ' · ', CAST(f.w_days AS STRING), 'd ',
               -- the 'x' lives INSIDE the formatter, never after the COALESCE, or a window with no
               -- spend prints "no spendx"
               IF(f.w_gp_roas IS NULL, 'no spend', CONCAT(FORMAT('%.2f', f.w_gp_roas), 'x')),
               ' ⇒ halve bid $', FORMAT('%.2f', f.current_bid), '→$',
               FORMAT('%.2f', f.suggested_bid), ' to slow sales')
      -- v27.99 (audit C3): same three-state as the paragraph — a last day with no spend is not a
      -- second failed window, and these two shorts said it was.
      WHEN f.escalated AND f.current_bid IS NULL THEN
        CONCAT(IF(f.profit_1d = 'NO_SPEND',
                  CONCAT(CAST(f.w_days AS STRING), 'd under 1.0x, last day quiet'),
                  'both windows under 1.0x'), ' — no bid at target grain')
      WHEN f.escalated THEN
        CONCAT(IF(f.profit_1d = 'NO_SPEND',
                  CONCAT(CAST(f.w_days AS STRING), 'd under 1.0x, last day quiet'),
                  'both windows under 1.0x'),
               ' — already at the $', CAST(f.bid_floor AS STRING), ' floor')
      WHEN f.target_class = 'THIN' THEN
        CONCAT('only ', CAST(f.s28_clicks AS STRING), ' settled clicks — too thin to call')
      WHEN f.target_class = 'STALLED' THEN
        CONCAT('blank 28d but ', CAST(f.s90_orders AS STRING),
               ' orders inside 90d — a judgement call')
      WHEN f.target_class = 'NON_CONVERTING' AND f.is_capped THEN
        CONCAT(CAST(f.s28_clicks AS STRING), ' clicks, 0 orders — park AND cut $',
               CAST(ROUND(f.spend_per_day, 2) AS STRING), '/day (capped)')
      WHEN f.target_class = 'NON_CONVERTING' THEN
        CONCAT(CAST(f.s28_clicks AS STRING), ' clicks, 0 orders — frees $',
               CAST(ROUND(f.spend_per_day, 2) AS STRING), '/day, buys no cover')
      WHEN f.family_is_critical AND f.profit_w = 'NO_SPEND' THEN
        CONCAT('no spend in the last ', CAST(f.w_days AS STRING), 'd — nothing live to slow')
      WHEN f.target_class = 'CONVERTING' AND f.s28_gp_roas IS NULL THEN
        'converting, but no settled GP to judge it on'
      WHEN f.target_class = 'CONVERTING' AND NOT f.below_breakeven_28d THEN
        CONCAT(FORMAT('%.2f', f.s28_gp_roas), 'x settled 28d, ', CAST(f.s28_orders AS STRING),
               ' orders — priced, not proposed')
      ELSE
        CONCAT(CAST(f.s28_orders AS STRING), ' orders settled — ', f.family, ' is ', f.risk_state,
               ', not CRITICAL')
    END AS action_reason_short
  FROM tgt_plan f
),
tgt_ranked AS (
  SELECT a.*,
    -- ── v27.80: WHOSE DOORWAY IS THIS? (Ori 2026-08-17) ──────────────────────────────────────
    -- serves_only_binding = this campaign advertises exactly ONE of our products and that product
    -- IS the family's binding (dry) variation. Read off T_CAMPAIGN_PRODUCT_SCOPE, the materialized
    -- V_CAMPAIGN_PRODUCT_SCOPE — a PHYSICAL table, never the view: this query is at the planner
    -- ceiling and inlining one more view is what broke it on 2026-08-17.
    -- A missing scope row (SB/video — Amazon publishes no advertised-product report for Sponsored
    -- Brands) reads FALSE, i.e. the v27.73 behaviour is kept unchanged. Conservative on purpose.
    (sc.sole_asin IS NOT NULL AND sc.sole_asin = rmg.binding_asin) AS serves_only_binding,
    sc.n_own_asins AS n_own_asins,
    -- v27.73 redirect gate, v27.80 hole closed: in a redirect-mode family, bid halves are OFF (the
    -- play is re-aiming doorways, not starving in-stock siblings) — only pure waste-parks stay
    -- offered. Keyed on the MOVE (STOCK_CUT_WASTE%), not the class: an escalated non-converter can
    -- carry a halve, and a halve is a brake whatever class earned it (first-run leak, 2 LolliBall
    -- rows).
    -- THE v27.80 EXCEPTION — a campaign DEDICATED to the dry variation brakes NORMALLY. Ori:
    -- "BALL-SP/AUTO (Mint) is auto per product ... so no need to change / only reduce ads by
    -- reducing the bid." Re-aiming it is meaningless: BALL-SP/AUTO (Pink) already exists and does
    -- exactly that job, so the swap would duplicate a live campaign. With nowhere to re-aim, the
    -- ordinary brake is the ONLY lever left, and v27.73 was suppressing it — $417/30d of Mint ads
    -- that were neither braked nor sensibly re-aimed. Three cases, and only the third changes:
    --   shared doorway on the dry variation      → suppressed + redirect offered   (unchanged)
    --   dedicated campaign of an IN-STOCK sibling → suppressed, no redirect        (unchanged —
    --       braking BALL-SP/AUTO (Pink) saves not one unit of Mint and loses Pink sales)
    --   dedicated campaign of the DRY variation   → BRAKES NORMALLY                (the fix)
    (a.dollars_freed_per_day > 0
     AND (NOT COALESCE(rmg.redirect_mode, FALSE)
          OR a.action LIKE 'STOCK_CUT_WASTE%'
          OR (sc.sole_asin IS NOT NULL AND sc.sole_asin = rmg.binding_asin))) AS is_proposal,
    CAST(ROW_NUMBER() OVER (PARTITION BY a.family, a.target_class
                            ORDER BY a.s28_spend DESC, a.cid, a.kid) AS INT64) AS dollar_rank,
    -- Ori's ranking: dollars freed first, days of cover bought second. Non-proposal rows sort last
    -- and keep a rank so the panel never has to handle a NULL here.
    CAST(ROW_NUMBER() OVER (
      PARTITION BY a.family
      ORDER BY (a.dollars_freed_per_day > 0) DESC, a.dollars_freed_per_day DESC,
               COALESCE(a.days_bought, 0) DESC, a.s28_spend DESC, a.cid, a.kid) AS INT64) AS proposal_rank,
    -- campaign totals carried on every row as WINDOWS, so the family roll-up can compute the paired
    -- budget cut without a second GROUP BY over the campaign grain (one fewer inlining of this CTE
    -- — see the flatness note). camp_seq = 1 marks one arbitrary-but-deterministic row per campaign
    -- so a campaign-level figure can be summed at family grain without being counted once per target.
    SUM(a.dollars_freed_per_day) OVER (PARTITION BY a.cid) AS camp_freed_per_day,
    CAST(ROW_NUMBER() OVER (PARTITION BY a.cid ORDER BY a.kid) AS INT64) AS camp_seq
  FROM tgt_action a
  LEFT JOIN rmode rmg ON rmg.family = a.family
  -- v27.80: PHYSICAL table, rebuilt as orchestrator Task 20.5d3 before anything reads this view.
  LEFT JOIN `onyga-482313.OI.T_CAMPAIGN_PRODUCT_SCOPE` sc ON sc.campaign_id = a.cid
),

-- ══ 3b. CAMPAIGN GRAIN — the budget lever and the CAPPED PAIRING ═══════════════════════════════
-- Ori's rule, restated: in a capped campaign the budget is spent regardless, so removing a target
-- (by park OR by bid cut) does not return money — it re-routes it to the neighbours and sells the
-- remaining stock FASTER. The proposal is therefore PAIRED, and the pairing is expressed HERE, once
-- per campaign, already summed over that campaign's proposed target cuts. The panel adds nothing up.
--   capped + something proposed     → STOCK_BUDGET_CUT, suggested_budget = budget − freed (floor $1)
--   not capped + something proposed → STOCK_BUDGET_HOLD: the campaign under-spends its budget, so
--       the freed dollars genuinely leave when the target stops. No budget change is needed, and
--       saying so out loud is the point — a blanket budget cut here would just shrink a campaign
--       that was not spending its allowance anyway.
--   nothing proposed                → STOCK_NONE
-- The paired cut IS a campaign-level budget cut, which is the shape V_LAUNCH_EXEMPTION blocks in
-- V_ADS_COACH. It stands here because its size is set by the freed dollars, not by a ROAS test, and
-- because without it the target cut backfires. launch_exempt_active is published so that is visible.
camp_agg AS (
  SELECT r.family, r.cid, r.campaign_name, r.channel,
    MAX(r.campaign_budget)                                  AS campaign_budget,
    MAX(r.is_defense)                                       AS is_defense,
    MAX(r.is_seasonal)                                      AS is_seasonal,
    MAX(r.is_auto_campaign)                                 AS is_auto_campaign,
    MAX(r.is_capped)                                        AS is_capped,
    MAX(r.days_capped_7d)                                   AS days_capped_7d,
    MAX(r.util_7d)                                          AS util_7d,
    MAX(r.launch_exempt_active)                             AS launch_exempt_active,
    MAX(r.launch_exempt_until)                              AS launch_exempt_until,
    MAX(r.launch_envelope_state)                            AS launch_envelope_state,
    MAX(r.settle_cut)                                       AS settled_through,
    MAX(r.settle_days)                                      AS settle_days,
    MAX(r.risk_state)                                       AS risk_state,
    MAX(r.binding_cover_days)                               AS binding_cover_days,
    MAX(r.family_velocity)                                  AS family_velocity,
    MAX(r.family_sellable_qty)                              AS family_sellable_qty,
    MAX(r.family_flat_cover_days)                           AS family_flat_cover_days,
    CAST(SUM(r.s28_clicks) AS INT64)                        AS s28_clicks,
    ROUND(SUM(r.s28_spend), 2)                              AS s28_spend,
    CAST(SUM(r.s28_orders) AS INT64)                        AS s28_orders,
    CAST(SUM(r.s28_units) AS INT64)                         AS s28_units,
    ROUND(SUM(r.s28_gp), 2)                                 AS s28_gp,
    ROUND(SAFE_DIVIDE(SUM(r.s28_gp), NULLIF(SUM(r.s28_spend), 0)), 3) AS s28_gp_roas,
    CAST(SUM(r.s90_clicks) AS INT64)                        AS s90_clicks,
    ROUND(SUM(r.s90_spend), 2)                              AS s90_spend,
    CAST(SUM(r.s90_orders) AS INT64)                        AS s90_orders,
    ROUND(SUM(r.s90_gp), 2)                                 AS s90_gp,
    ROUND(SAFE_DIVIDE(SUM(r.s90_gp), NULLIF(SUM(r.s90_spend), 0)), 3) AS s90_gp_roas,
    -- v27.59: the same short windows at campaign grain, so the campaign header row prints the same
    -- two columns as its targets. Never two ANY_VALUE()s out of one GROUP BY — the ratio is built
    -- from SUM/SUM inside this aggregate.
    MAX(r.last_ads_day)                                     AS last_ads_day,
    MAX(r.w_days)                                           AS w_days,
    LOGICAL_OR(r.in_peak)                                   AS in_peak,
    MAX(r.w_days_reason)                                    AS w_days_reason,
    CAST(SUM(r.d1_clicks) AS INT64)                         AS d1_clicks,
    ROUND(SUM(r.d1_spend), 2)                               AS d1_spend,
    CAST(SUM(r.d1_orders) AS INT64)                         AS d1_orders,
    CAST(SUM(r.d1_units) AS INT64)                          AS d1_units,
    ROUND(SUM(r.d1_gp), 2)                                  AS d1_gp,
    ROUND(SAFE_DIVIDE(SUM(r.d1_gp), NULLIF(SUM(r.d1_spend), 0)), 3) AS d1_gp_roas,
    CAST(SUM(r.w_clicks) AS INT64)                          AS w_clicks,
    ROUND(SUM(r.w_spend), 2)                                AS w_spend,
    CAST(SUM(r.w_orders) AS INT64)                          AS w_orders,
    CAST(SUM(r.w_units) AS INT64)                           AS w_units,
    ROUND(SUM(r.w_gp), 2)                                   AS w_gp,
    ROUND(SAFE_DIVIDE(SUM(r.w_gp), NULLIF(SUM(r.w_spend), 0)), 3) AS w_gp_roas,
    ROUND(SUM(r.spend_per_day), 3)                          AS spend_per_day,
    ROUND(SUM(r.units_per_day), 3)                          AS units_per_day,
    ROUND(SUM(r.w_spend_per_day), 3)                        AS w_spend_per_day,
    ROUND(SUM(r.w_units_per_day), 3)                        AS w_units_per_day,
    -- v27.81 DETERMINISM (was ROUND(SUM(r.dollars_freed_per_day), 2)). SUM over FLOAT64 is
    -- order-dependent in its last bits, and every addend here is a 3-decimal number
    -- (dollars_freed_per_day is ROUND(...,3) or spend_per_day, itself ROUND(...,3)), so campaign
    -- sums land EXACTLY on half-cent ties. Measured 2026-08-18 on the live view: BUNNY-VIDEO/BROAD
    -- 2.375, BALL-SP/AUTO (Purple) 7.505, VIDEO- BALL 18.825 — three of fourteen campaigns sitting
    -- on the tie. ROUND(tie, 2) then flips with the summation order, which is why the narrative that
    -- interpolates this number alternated '$1.66' / '$1.67' across two identical pulls of the same
    -- Bunny campaign. NUMERIC addition is exact fixed-point, so it is order-independent and the cent
    -- is pinned; the CAST back keeps this column FLOAT64 for the UNION ALL BY NAME arms. No new
    -- source, no join, no CTE — one scalar cast inside an aggregate that was already here.
    CAST(ROUND(SUM(CAST(r.dollars_freed_per_day AS NUMERIC)), 2) AS FLOAT64)
                                                            AS dollars_freed_per_day,
    SUM(r.units_removed_per_day)                            AS units_removed_per_day,
    CAST(COUNTIF(r.is_proposal) AS INT64)                   AS proposal_targets,
    -- v27.59: park_targets counts the WASTE parks (the only park left); bid_cut_targets counts the
    -- CRITICAL 50% halves. STOCK_PARK / STOCK_BID_CUT no longer exist — the breakeven ladder is gone.
    CAST(COUNTIF(r.action IN ('STOCK_CUT_WASTE', 'STOCK_CUT_WASTE_AND_BUDGET')) AS INT64) AS park_targets,
    CAST(COUNTIF(r.action IN ('STOCK_BID_HALVE', 'STOCK_BID_HALVE_AND_BUDGET')) AS INT64) AS bid_cut_targets,
    CAST(COUNTIF(r.action IN ('STOCK_CUT_WASTE', 'STOCK_CUT_WASTE_AND_BUDGET')) AS INT64) AS waste_targets,
    CAST(COUNTIF(r.action = 'STOCK_PROTECT') AS INT64)      AS protected_targets,
    CAST(COUNT(*) AS INT64)                                 AS targets,
    -- joint days bought for everything proposed inside this campaign (never the sum of the rows)
    CASE
      WHEN SUM(r.units_removed_per_day) <= 0 THEN 0.0
      WHEN MAX(r.family_velocity) IS NULL OR MAX(r.family_velocity) <= 0 THEN NULL
      WHEN MAX(r.binding_cover_days) IS NULL THEN NULL
      WHEN SUM(r.units_removed_per_day) >= MAX(r.max_throttle_share) * MAX(r.family_velocity) THEN NULL
      ELSE ROUND(MAX(r.binding_cover_days) * SUM(r.units_removed_per_day)
                 / (MAX(r.family_velocity) - SUM(r.units_removed_per_day)), 1)
    END AS days_bought,
    IF(MAX(r.is_capped) AND SUM(r.dollars_freed_per_day) > 0,
       GREATEST(ROUND(MAX(r.campaign_budget) - SUM(r.dollars_freed_per_day), 2),
                MAX(r.min_daily_budget)),
       CAST(NULL AS FLOAT64)) AS suggested_budget,
    CASE
      WHEN SUM(r.dollars_freed_per_day) <= 0 THEN 'STOCK_NONE'
      WHEN MAX(r.is_capped)                  THEN 'STOCK_BUDGET_CUT'
      ELSE                                        'STOCK_BUDGET_HOLD'
    END AS action
  FROM tgt_ranked r
  GROUP BY 1, 2, 3, 4
),
camp_final AS (
  SELECT a.*,
    CASE
      WHEN a.action = 'STOCK_NONE' THEN
        CONCAT('nothing proposed inside this campaign — ', CAST(a.protected_targets AS STRING),
               ' of its ', CAST(a.targets AS STRING), ' targets are protected and the rest are ',
               'too thin or already off. Budget stays at $', CAST(a.campaign_budget AS STRING), '.')
      WHEN a.action = 'STOCK_BUDGET_CUT' THEN
        CONCAT('PAIRED BUDGET CUT — this is the other half of the target actions above, not a ',
               'separate opinion. This campaign was out of budget ', CAST(a.days_capped_7d AS STRING),
               ' of the last 7 days, so it spends its full $', CAST(a.campaign_budget AS STRING),
               '/day whatever you do to one target: park or bid-cut ', CAST(a.proposal_targets AS STRING),
               ' targets on their own and Amazon simply re-routes that money to the converting targets ',
               'beside them, which sells the last ', a.family, ' stock FASTER. Take the freed $',
               CAST(a.dollars_freed_per_day AS STRING), '/day off the daily budget in the same move: $',
               CAST(a.campaign_budget AS STRING), ' → $', CAST(a.suggested_budget AS STRING),
               '. Unpaired, the target cuts are worse than doing nothing.',
               IF(a.launch_exempt_active,
                  CONCAT(' Launch-exempt until ', CAST(a.launch_exempt_until AS STRING),
                         ' — the exemption blocks ROAS-DRIVEN campaign budget cuts in the coach. This ',
                         'one is not a ROAS verdict: its size is the freed dollars from a stock ',
                         'decision, and it exists only to stop those dollars re-routing. It stands.'), ''))
      ELSE
        CONCAT('NO BUDGET CHANGE NEEDED — this campaign is not capped (out of budget ',
               CAST(a.days_capped_7d AS STRING), '/7 days, utilisation ',
               COALESCE(CAST(CAST(ROUND(100 * a.util_7d) AS INT64) AS STRING), '—'),
               '%), so it does not spend its allowance anyway: the $',
               CAST(a.dollars_freed_per_day AS STRING),
               '/day from the ', CAST(a.proposal_targets AS STRING),
               ' target actions genuinely leaves when those targets stop. Cutting the budget on top ',
               'would shrink a campaign that was already under its cap, for no gain.')
    END AS action_reason,
    -- the same short-clause rule as the target grain (v27.62) — visible column, ~6-10 words; the
    -- paragraph above is the tooltip. Same branch order, so the two can never disagree.
    CASE
      WHEN a.action = 'STOCK_NONE' THEN
        CONCAT('nothing proposed here — budget stays $', CAST(a.campaign_budget AS STRING))
      -- explanation audit 2026-08-16: name the dollars, the budget move, and the proof it caps
      WHEN a.action = 'STOCK_BUDGET_CUT' THEN
        CONCAT('take freed $', FORMAT('%.2f', a.dollars_freed_per_day), '/day off: budget $',
               FORMAT('%.2f', a.campaign_budget), '→$', FORMAT('%.2f', a.suggested_budget),
               ' (hit cap ', CAST(a.days_capped_7d AS STRING), ' of 7 days)')
      ELSE
        CONCAT('not capped (', COALESCE(CAST(CAST(ROUND(100 * a.util_7d) AS INT64) AS STRING), '—'),
               '% used) — the dollars already leave')
    END AS action_reason_short
  FROM camp_agg a
),

fam_ads AS (
  SELECT family,
    MAX(last_ads_day)      AS last_ads_day,
    MAX(w_days)            AS w_days,
    LOGICAL_OR(in_peak)    AS in_peak,
    MAX(w_days_reason)     AS w_days_reason,
    CAST(COUNTIF(target_class = 'NON_CONVERTING') AS INT64) AS nonconv_targets,
    ROUND(SUM(IF(target_class = 'NON_CONVERTING', spend_per_day, 0)), 2) AS nonconv_spend_per_day,
    CAST(COUNTIF(target_class = 'NON_CONVERTING' AND is_capped) AS INT64) AS nonconv_targets_capped,
    ROUND(SUM(IF(target_class = 'NON_CONVERTING' AND is_capped, spend_per_day, 0)), 2) AS nonconv_spend_per_day_capped,
    CAST(COUNTIF(target_class = 'STALLED') AS INT64) AS stalled_targets,
    ROUND(SUM(IF(target_class = 'STALLED', spend_per_day, 0)), 2) AS stalled_spend_per_day,
    CAST(COUNTIF(target_class = 'CONVERTING') AS INT64) AS conv_targets,
    ROUND(SUM(IF(target_class = 'CONVERTING', spend_per_day, 0)), 2) AS conv_spend_per_day,
    -- v27.59 proposal roll-up: what the CRITICAL halve actually asks for, in one place.
    -- park_targets = waste parks · bid_cut_targets = 50% halves · escalated_targets = every row the
    -- halve rule promoted, INCLUDING the ones that stopped at STOCK_AT_FLOOR / STOCK_NO_BID.
    CAST(COUNTIF(action IN ('STOCK_CUT_WASTE', 'STOCK_CUT_WASTE_AND_BUDGET')) AS INT64) AS park_targets,
    CAST(COUNTIF(action IN ('STOCK_BID_HALVE', 'STOCK_BID_HALVE_AND_BUDGET')) AS INT64) AS bid_cut_targets,
    CAST(COUNTIF(action IN ('STOCK_AT_FLOOR', 'STOCK_NO_BID')) AS INT64)            AS not_executable_targets,
    CAST(COUNTIF(escalated) AS INT64)                                               AS escalated_targets,
    ROUND(SUM(IF(escalated, spend_per_day, 0)), 2)                                  AS escalated_spend_per_day,
    CAST(COUNTIF(is_proposal) AS INT64)                                             AS proposal_targets,
    ROUND(SUM(dollars_freed_per_day), 2)                                            AS proposal_freed_per_day,
    CAST(COUNTIF(action = 'STOCK_PROTECT') AS INT64)                                AS protected_targets,
    ROUND(SUM(IF(action = 'STOCK_PROTECT', spend_per_day, 0)), 2)                   AS protected_spend_per_day,
    -- the paired budget cuts, counted ONCE per campaign via camp_seq (see tgt_ranked)
    CAST(COUNTIF(camp_seq = 1 AND is_capped AND camp_freed_per_day > 0) AS INT64)   AS budget_cut_campaigns,
    ROUND(SUM(IF(camp_seq = 1 AND is_capped AND camp_freed_per_day > 0,
                 LEAST(camp_freed_per_day, GREATEST(campaign_budget - min_daily_budget, 0)), 0)), 2)
      AS budget_cut_per_day,
    CAST(COUNT(DISTINCT IF(is_capped, cid, NULL)) AS INT64) AS capped_campaigns,
    CAST(COUNT(DISTINCT cid) AS INT64) AS campaigns,
    -- Every family-level days-bought figure is the JOINT effect of doing all of it at once,
    -- binding_cover × Σu / (V − Σu) — NOT the sum of the per-row numbers. Each per-row figure is
    -- computed with the other targets still running, so adding them up double-counts the curvature
    -- and over-states the gain (Fresh 2026-08-13: 113.8 days summed vs 40.5 joint on the old
    -- family-cover model). Same upper-bound caveat as the row: zero organic recapture assumed, so
    -- the truth is smaller again.
    --
    -- family velocity and the binding variation's cover are read off tgt_ranked (which already
    -- carries them per row, constant within a family) rather than by joining fam_state again. That
    -- join cost one more full inlining of the inventory chain — V_SUPPLY_CHAIN_SUMMARY and
    -- V_PLAN_FORECAST included — and this view is at BigQuery's query-planning ceiling.
    CASE
      WHEN MAX(family_velocity) IS NULL OR MAX(family_velocity) <= 0 THEN NULL
      WHEN MAX(binding_cover_days) IS NULL THEN NULL
      WHEN SUM(IF(target_class = 'CONVERTING', w_units_per_day, 0))
             >= MAX(max_throttle_share) * MAX(family_velocity) THEN NULL
      ELSE ROUND(MAX(binding_cover_days) * SUM(IF(target_class = 'CONVERTING', w_units_per_day, 0))
                 / (MAX(family_velocity) - SUM(IF(target_class = 'CONVERTING', w_units_per_day, 0))), 1)
    END AS conv_days_bought_max,
    CASE
      WHEN SUM(units_removed_per_day) <= 0 THEN 0.0
      WHEN MAX(family_velocity) IS NULL OR MAX(family_velocity) <= 0 THEN NULL
      WHEN MAX(binding_cover_days) IS NULL THEN NULL
      WHEN SUM(units_removed_per_day) >= MAX(max_throttle_share) * MAX(family_velocity) THEN NULL
      ELSE ROUND(MAX(binding_cover_days) * SUM(units_removed_per_day)
                 / (MAX(family_velocity) - SUM(units_removed_per_day)), 1)
    END AS proposal_days_bought
  FROM tgt_ranked GROUP BY 1
)


-- ══ 4. OUTPUT ═════════════════════════════════════════════════════════════════════════════════
-- UNION ALL **BY NAME** (v27.58). The previous revision matched four dozen columns POSITIONALLY
-- across branches padded with CAST(NULL AS T) — one inserted column silently shifted every field
-- after it into the wrong slot, and adding the CAMPAIGN grain would have doubled that exposure.
-- BY NAME makes a mismatched or misspelled column a compile error instead of a wrong number.
SELECT
  'FAMILY' AS row_kind,
  f.family AS family,
  f.risk_state AS risk_state,
  CASE f.risk_state WHEN 'CRITICAL' THEN 1 WHEN 'THROTTLE' THEN 2 WHEN 'WATCH' THEN 3 ELSE 4 END AS risk_rank,
  f.risk_reason AS risk_reason,
  -- the FAMILY header is a full-width prose line, not a table cell, so it keeps the long form and
  -- has no short twin. The panel falls back to risk_reason when this is NULL.
  CAST(NULL AS STRING) AS risk_reason_short,
  (SELECT d FROM snap) AS snapshot_date,
  -- v27.73: the FAMILY row's asin IS its binding variation — V_LOW_STOCK_REDIRECT keys on it
  f.binding.asin AS asin,
  CAST(NULL AS STRING) AS product,
  f.fba_qty AS fba_qty,
  f.awd_qty AS awd_qty,
  f.sellable_qty AS sellable_qty,
  f.in_transit_qty AS in_transit_qty,
  f.in_transit_awd_qty AS in_transit_awd_qty,
  f.mfr_ready_qty AS mfr_ready_qty,
  f.in_production_qty AS in_production_qty,
  f.in_transit_qty + f.in_transit_awd_qty + f.mfr_ready_qty + f.in_production_qty AS upstream_qty,
  f.total_pipeline_qty AS total_pipeline_qty,
  f.velocity_forecast AS velocity_forecast,
  f.velocity_30d AS velocity_30d,
  f.velocity_14d AS velocity_14d,
  f.velocity_7d AS velocity_7d,
  f.velocity_actual AS velocity_actual,
  f.binding.velocity_actual_basis AS velocity_actual_basis,
  f.velocity_used AS velocity_used,
  CAST(NULL AS INT64) AS doc_walk_days,
  CAST(NULL AS FLOAT64) AS doc_flat_days,
  CAST(NULL AS FLOAT64) AS doc_flat_forecast_days,
  f.binding.days_of_cover AS days_of_cover,
  f.binding.days_of_cover_avail AS days_of_cover_avail,
  f.binding.cover_basis AS cover_basis,
  -- v27.59: the forecast reading for the binding variation, published alongside so the divergence
  -- is visible on the header line and nothing from the old (forecast-driven) verdict is lost.
  f.binding.days_of_cover_forecast AS days_of_cover_forecast,
  f.binding.days_of_cover_avail_forecast AS days_of_cover_avail_forecast,
  f.binding.cover_basis_forecast AS cover_basis_forecast,
  f.risk_state_forecast AS risk_state_forecast,
  f.binding.days_of_cover_avail_forecast AS binding_cover_forecast_days,
  f.at_risk_units_share_pct_forecast AS at_risk_units_share_pct_forecast,
  CAST(NULL AS FLOAT64) AS bridge_gap_days_forecast,
  f.binding.stockout_date AS stockout_date,
  f.binding.po_deadline AS po_deadline,
  f.binding.too_late_to_replenish AS too_late_to_replenish,
  f.full_lead_days AS full_lead_days,
  f.binding.bridge_gap_days AS bridge_gap_days,
  f.next_arrival_date AS next_arrival_date,
  f.days_to_arrival AS days_to_arrival,
  f.next_arrival_qty AS next_arrival_qty,
  f.season_demand_units AS season_demand_units,
  f.season_gap_units AS season_gap_units,
  f.overdue_pending_qty AS overdue_pending_qty,
  f.overdue_pending_oldest_eta AS overdue_pending_oldest_eta,
  f.units_90d AS units_90d,
  CAST(NULL AS FLOAT64) AS family_units_share_pct,
  f.binding.asin AS binding_asin,
  f.binding.product AS binding_product,
  f.at_risk_units_share_pct AS at_risk_units_share_pct,
  -- ⚠️ ARRIVAL FRESHNESS (v27.58). The two arrival numbers on this row come from different clocks
  -- and can legitimately disagree for up to a day:
  --   next_arrival_date (FAMILY)  — read LIVE from DE_MANUFACTURER_SHIPMENTS in fam_eta above.
  --   binding.next_arrival_date   — read from V_SUPPLY_CHAIN_SUMMARY, which reads
  --                                 FACT_INVENTORY_SNAPSHOT.next_shipment_arrival_date, a column
  --                                 SP_LOAD_FACT_INVENTORY_SNAPSHOT stamps ONCE A DAY at 07:40 UTC.
  -- A shipment booked after that load is live in the family number and invisible in the per-variation
  -- number — and the per-variation number is what sets risk_state. So a family can read CRITICAL
  -- "nothing booked" while a boat for its binding variation is already in the shipments table.
  -- This is surfaced, NOT silently corrected: overriding the stamped column here would change the
  -- verdict of the whole criteria on data that has not been through the loader, and today it would
  -- flip LolliBall out of CRITICAL and switch the entire escalation off. That is Ori's call.
  -- (Confirmed 2026-08-13 to be a timing lag, not a loader bug: SP_LOAD applies no shipment_type
  -- filter, and all seven other pending ETAs match the live table exactly.)
  --
  -- The test is deliberately narrow: the BINDING variation itself has a live pending shipment that
  -- its stamped arrival does not know about. A binding variation that simply has no boat while its
  -- siblings do is NOT a conflict — that is the designed behaviour (White Lollibox, 2026-08-13),
  -- and flagging it would cry wolf on the normal case.
  f.binding.next_arrival_date AS binding_next_arrival_date,
  (ael.nxt.eta IS NOT NULL AND f.binding.next_arrival_date IS NULL) AS arrival_freshness_conflict,
  CASE WHEN ael.nxt.eta IS NOT NULL AND f.binding.next_arrival_date IS NULL THEN
    CONCAT('⚠️ ARRIVAL FRESHNESS CONFLICT — ', f.binding.product,
           ' is the variation that SETS this verdict, and it reads "nothing booked" — but a PENDING ',
           'shipment carrying ', CAST(ael.nxt.qty AS STRING), ' units of it lands ',
           CAST(ael.nxt.eta AS STRING), ' according to the live shipments table. The per-variation ',
           'arrival comes from the inventory snapshot, which is stamped once a day at 07:40 UTC, so ',
           'a shipment booked after the last load is invisible to it. The verdict below was computed ',
           'on the stamped column and has NOT been overridden. Confirm the boat before acting on the ',
           'cuts, or re-read after the next snapshot load — but note the family verdict only lifts if ',
           'NO OTHER material variation is at risk on its own. Open Inventory detail and check the ',
           'siblings: a boat that carries two of five variations does not rescue the other three.')
    END AS arrival_conflict_note,
  f.binding.days_of_cover_avail AS binding_cover_days,
  f.family_flat_cover_days AS family_flat_cover_days,
  f.sellable_qty AS family_sellable_qty,
  f.velocity_used AS family_velocity,
  f.first_sale_date AS first_sale_date,
  f.family_age_months AS family_age_months,
  COALESCE(fa.campaigns, 0) AS campaigns,
  COALESCE(fa.capped_campaigns, 0) AS capped_campaigns,
  COALESCE(fa.nonconv_targets, 0) AS nonconv_targets,
  COALESCE(fa.nonconv_spend_per_day, 0) AS nonconv_spend_per_day,
  COALESCE(fa.nonconv_targets_capped, 0) AS nonconv_targets_capped,
  COALESCE(fa.nonconv_spend_per_day_capped, 0) AS nonconv_spend_per_day_capped,
  COALESCE(fa.stalled_targets, 0) AS stalled_targets,
  COALESCE(fa.stalled_spend_per_day, 0) AS stalled_spend_per_day,
  COALESCE(fa.conv_targets, 0) AS conv_targets,
  COALESCE(fa.conv_spend_per_day, 0) AS conv_spend_per_day,
  fa.conv_days_bought_max AS conv_days_bought_max,
  COALESCE(fa.escalated_targets, 0) AS escalated_targets,
  COALESCE(fa.escalated_spend_per_day, 0) AS escalated_spend_per_day,
  COALESCE(fa.park_targets, 0) AS park_targets,
  COALESCE(fa.bid_cut_targets, 0) AS bid_cut_targets,
  COALESCE(fa.not_executable_targets, 0) AS not_executable_targets,
  COALESCE(fa.proposal_targets, 0) AS proposal_targets,
  COALESCE(fa.proposal_freed_per_day, 0) AS proposal_freed_per_day,
  fa.proposal_days_bought AS proposal_days_bought,
  COALESCE(fa.protected_targets, 0) AS protected_targets,
  COALESCE(fa.protected_spend_per_day, 0) AS protected_spend_per_day,
  COALESCE(fa.budget_cut_campaigns, 0) AS budget_cut_campaigns,
  COALESCE(fa.budget_cut_per_day, 0) AS budget_cut_per_day,
  CAST(NULL AS STRING) AS campaign_id,
  CAST(NULL AS STRING) AS campaign_name,
  CAST(NULL AS STRING) AS channel,
  CAST(NULL AS FLOAT64) AS campaign_budget,
  CAST(NULL AS BOOL) AS is_defense,
  CAST(NULL AS BOOL) AS is_seasonal,
  CAST(NULL AS BOOL) AS is_auto_campaign,
  CAST(NULL AS BOOL) AS is_capped,
  CAST(NULL AS INT64) AS days_capped_7d,
  CAST(NULL AS FLOAT64) AS util_7d,
  CAST(NULL AS BOOL) AS launch_exempt_active,
  CAST(NULL AS DATE) AS launch_exempt_until,
  CAST(NULL AS STRING) AS launch_envelope_state,
  CAST(NULL AS STRING) AS keyword_id,
  CAST(NULL AS STRING) AS ad_group_id,
  CAST(NULL AS STRING) AS target_text,
  CAST(NULL AS STRING) AS match_type,
  CAST(NULL AS STRING) AS keyword_state,
  CAST(NULL AS FLOAT64) AS current_bid,
  CAST(NULL AS BOOL) AS is_auto,
  CAST(NULL AS BOOL) AS is_pt,
  CAST(NULL AS STRING) AS creative_type,
  CAST(NULL AS DATE) AS settled_through,
  CAST(NULL AS INT64) AS settle_days,
  CAST(NULL AS INT64) AS s28_clicks,
  CAST(NULL AS FLOAT64) AS s28_spend,
  CAST(NULL AS INT64) AS s28_orders,
  CAST(NULL AS INT64) AS s28_units,
  CAST(NULL AS FLOAT64) AS s28_gp,
  CAST(NULL AS FLOAT64) AS s28_gp_roas,
  CAST(NULL AS INT64) AS s90_clicks,
  CAST(NULL AS FLOAT64) AS s90_spend,
  CAST(NULL AS INT64) AS s90_orders,
  CAST(NULL AS FLOAT64) AS s90_gp,
  CAST(NULL AS FLOAT64) AS s90_gp_roas,
  -- the short-window anchor is published on the FAMILY row too, so the panel header can say which
  -- day and which window length the rule below it ran on without reading a target row
  fa.last_ads_day AS last_ads_day,
  fa.w_days AS w_days,
  fa.in_peak AS in_peak,
  fa.w_days_reason AS w_days_reason,
  CAST(NULL AS INT64) AS d1_clicks,
  CAST(NULL AS FLOAT64) AS d1_spend,
  CAST(NULL AS INT64) AS d1_orders,
  CAST(NULL AS INT64) AS d1_units,
  CAST(NULL AS FLOAT64) AS d1_gp,
  CAST(NULL AS FLOAT64) AS d1_gp_roas,
  CAST(NULL AS INT64) AS w_clicks,
  CAST(NULL AS FLOAT64) AS w_spend,
  CAST(NULL AS INT64) AS w_orders,
  CAST(NULL AS INT64) AS w_units,
  CAST(NULL AS FLOAT64) AS w_gp,
  CAST(NULL AS FLOAT64) AS w_gp_roas,
  CAST(NULL AS STRING) AS profit_1d,
  CAST(NULL AS STRING) AS profit_w,
  CAST(NULL AS FLOAT64) AS spend_per_day,
  CAST(NULL AS FLOAT64) AS units_per_day,
  CAST(NULL AS FLOAT64) AS w_spend_per_day,
  CAST(NULL AS FLOAT64) AS w_units_per_day,
  CAST(NULL AS FLOAT64) AS pct_of_family_velocity,
  CAST(NULL AS STRING) AS target_class,
  CAST(NULL AS BOOL) AS escalated,
  CAST(NULL AS BOOL) AS halve_viable,
  CAST(NULL AS FLOAT64) AS bid_floor,
  CAST(NULL AS FLOAT64) AS suggested_bid,
  CAST(NULL AS BOOL) AS bid_clamped_to_floor,
  CAST(NULL AS FLOAT64) AS suggested_budget,
  CAST(NULL AS FLOAT64) AS now_value,
  CAST(NULL AS FLOAT64) AS suggested_value,
  CAST(NULL AS FLOAT64) AS dollars_freed_per_day,
  CAST(NULL AS FLOAT64) AS units_removed_per_day,
  CAST(NULL AS FLOAT64) AS days_bought,
  CAST(NULL AS FLOAT64) AS days_bought_if_paused,
  CAST(NULL AS BOOL) AS is_proposal,
  CAST(NULL AS INT64) AS dollar_rank,
  CAST(NULL AS INT64) AS proposal_rank,
  CAST(NULL AS STRING) AS action,
  CAST(NULL AS STRING) AS action_reason,
  CAST(NULL AS STRING) AS action_reason_short,
  -- v27.73: the family's ads posture + the redirect destination, published where the panel
  -- headline reads them (real values on FAMILY rows only; V_LOW_STOCK_REDIRECT derives its rows
  -- from THESE fields — the hero is computed exactly once, in fam_agg)
  COALESCE(rmf.redirect_mode, FALSE) AS redirect_mode,
  rmf.hero.asin AS hero_asin,
  rmf.hero.product AS hero_product,
  rmf.hero.velocity_actual AS hero_rate,
  rmf.hero.days_of_cover_avail AS hero_cover,
  -- v27.80: campaign-scope columns are campaign-grain — meaningless on a FAMILY row
  CAST(NULL AS BOOL) AS serves_only_binding,
  CAST(NULL AS INT64) AS n_own_asins
FROM fam_state f
LEFT JOIN fam_ads fa ON fa.family = f.family
LEFT JOIN rmode rmf ON rmf.family = f.family
LEFT JOIN asin_eta_live ael ON ael.asin = f.binding.asin

UNION ALL BY NAME

SELECT
  'ASIN' AS row_kind,
  s.family AS family,
  s.risk_state AS risk_state,
  CASE s.risk_state WHEN 'CRITICAL' THEN 1 WHEN 'THROTTLE' THEN 2 WHEN 'WATCH' THEN 3 ELSE 4 END AS risk_rank,
  s.risk_reason AS risk_reason,
  s.risk_reason_short AS risk_reason_short,
  (SELECT d FROM snap) AS snapshot_date,
  s.asin AS asin,
  s.product AS product,
  s.fba_qty AS fba_qty,
  s.awd_qty AS awd_qty,
  s.sellable_qty AS sellable_qty,
  s.in_transit_qty AS in_transit_qty,
  s.in_transit_awd_qty AS in_transit_awd_qty,
  s.mfr_ready_qty AS mfr_ready_qty,
  s.in_production_qty AS in_production_qty,
  s.in_transit_qty + s.in_transit_awd_qty + s.mfr_ready_qty + s.in_production_qty AS upstream_qty,
  s.total_pipeline_qty AS total_pipeline_qty,
  s.velocity_forecast AS velocity_forecast,
  s.velocity_30d AS velocity_30d,
  s.velocity_14d AS velocity_14d,
  s.velocity_7d AS velocity_7d,
  s.velocity_actual AS velocity_actual,
  s.velocity_actual_basis AS velocity_actual_basis,
  s.velocity_used AS velocity_used,
  s.doc_walk_days AS doc_walk_days,
  s.doc_flat_days AS doc_flat_days,
  s.doc_flat_forecast_days AS doc_flat_forecast_days,
  s.days_of_cover AS days_of_cover,
  s.days_of_cover_avail AS days_of_cover_avail,
  s.cover_basis AS cover_basis,
  s.days_of_cover_forecast AS days_of_cover_forecast,
  s.days_of_cover_avail_forecast AS days_of_cover_avail_forecast,
  s.cover_basis_forecast AS cover_basis_forecast,
  s.risk_state_forecast AS risk_state_forecast,
  s.bridge_gap_days_forecast AS bridge_gap_days_forecast,
  CAST(NULL AS FLOAT64) AS binding_cover_forecast_days,
  CAST(NULL AS FLOAT64) AS at_risk_units_share_pct_forecast,
  s.stockout_date AS stockout_date,
  s.po_deadline AS po_deadline,
  s.too_late_to_replenish AS too_late_to_replenish,
  s.full_lead_days AS full_lead_days,
  s.bridge_gap_days AS bridge_gap_days,
  s.next_arrival_date AS next_arrival_date,
  s.days_to_arrival AS days_to_arrival,
  s.next_arrival_qty AS next_arrival_qty,
  s.season_demand_units AS season_demand_units,
  s.season_gap_units AS season_gap_units,
  s.overdue_pending_qty AS overdue_pending_qty,
  s.overdue_pending_oldest_eta AS overdue_pending_oldest_eta,
  s.units_90d AS units_90d,
  s.family_units_share_pct AS family_units_share_pct,
  CAST(NULL AS STRING) AS binding_asin,
  CAST(NULL AS STRING) AS binding_product,
  CAST(NULL AS FLOAT64) AS at_risk_units_share_pct,
  CAST(NULL AS DATE) AS binding_next_arrival_date,
  CAST(NULL AS BOOL) AS arrival_freshness_conflict,
  CAST(NULL AS STRING) AS arrival_conflict_note,
  CAST(NULL AS FLOAT64) AS binding_cover_days,
  CAST(NULL AS FLOAT64) AS family_flat_cover_days,
  CAST(NULL AS INT64) AS family_sellable_qty,
  CAST(NULL AS FLOAT64) AS family_velocity,
  CAST(NULL AS DATE) AS first_sale_date,
  CAST(NULL AS INT64) AS family_age_months,
  CAST(NULL AS INT64) AS campaigns,
  CAST(NULL AS INT64) AS capped_campaigns,
  CAST(NULL AS INT64) AS nonconv_targets,
  CAST(NULL AS FLOAT64) AS nonconv_spend_per_day,
  CAST(NULL AS INT64) AS nonconv_targets_capped,
  CAST(NULL AS FLOAT64) AS nonconv_spend_per_day_capped,
  CAST(NULL AS INT64) AS stalled_targets,
  CAST(NULL AS FLOAT64) AS stalled_spend_per_day,
  CAST(NULL AS INT64) AS conv_targets,
  CAST(NULL AS FLOAT64) AS conv_spend_per_day,
  CAST(NULL AS FLOAT64) AS conv_days_bought_max,
  CAST(NULL AS INT64) AS escalated_targets,
  CAST(NULL AS FLOAT64) AS escalated_spend_per_day,
  CAST(NULL AS INT64) AS park_targets,
  CAST(NULL AS INT64) AS bid_cut_targets,
  CAST(NULL AS INT64) AS not_executable_targets,
  CAST(NULL AS INT64) AS proposal_targets,
  CAST(NULL AS FLOAT64) AS proposal_freed_per_day,
  CAST(NULL AS FLOAT64) AS proposal_days_bought,
  CAST(NULL AS INT64) AS protected_targets,
  CAST(NULL AS FLOAT64) AS protected_spend_per_day,
  CAST(NULL AS INT64) AS budget_cut_campaigns,
  CAST(NULL AS FLOAT64) AS budget_cut_per_day,
  CAST(NULL AS STRING) AS campaign_id,
  CAST(NULL AS STRING) AS campaign_name,
  CAST(NULL AS STRING) AS channel,
  CAST(NULL AS FLOAT64) AS campaign_budget,
  CAST(NULL AS BOOL) AS is_defense,
  CAST(NULL AS BOOL) AS is_seasonal,
  CAST(NULL AS BOOL) AS is_auto_campaign,
  CAST(NULL AS BOOL) AS is_capped,
  CAST(NULL AS INT64) AS days_capped_7d,
  CAST(NULL AS FLOAT64) AS util_7d,
  CAST(NULL AS BOOL) AS launch_exempt_active,
  CAST(NULL AS DATE) AS launch_exempt_until,
  CAST(NULL AS STRING) AS launch_envelope_state,
  CAST(NULL AS STRING) AS keyword_id,
  CAST(NULL AS STRING) AS ad_group_id,
  CAST(NULL AS STRING) AS target_text,
  CAST(NULL AS STRING) AS match_type,
  CAST(NULL AS STRING) AS keyword_state,
  CAST(NULL AS FLOAT64) AS current_bid,
  CAST(NULL AS BOOL) AS is_auto,
  CAST(NULL AS BOOL) AS is_pt,
  CAST(NULL AS STRING) AS creative_type,
  CAST(NULL AS DATE) AS settled_through,
  CAST(NULL AS INT64) AS settle_days,
  CAST(NULL AS INT64) AS s28_clicks,
  CAST(NULL AS FLOAT64) AS s28_spend,
  CAST(NULL AS INT64) AS s28_orders,
  CAST(NULL AS INT64) AS s28_units,
  CAST(NULL AS FLOAT64) AS s28_gp,
  CAST(NULL AS FLOAT64) AS s28_gp_roas,
  CAST(NULL AS INT64) AS s90_clicks,
  CAST(NULL AS FLOAT64) AS s90_spend,
  CAST(NULL AS INT64) AS s90_orders,
  CAST(NULL AS FLOAT64) AS s90_gp,
  CAST(NULL AS FLOAT64) AS s90_gp_roas,
  CAST(NULL AS DATE) AS last_ads_day,
  CAST(NULL AS INT64) AS w_days,
  CAST(NULL AS BOOL) AS in_peak,
  CAST(NULL AS STRING) AS w_days_reason,
  CAST(NULL AS INT64) AS d1_clicks,
  CAST(NULL AS FLOAT64) AS d1_spend,
  CAST(NULL AS INT64) AS d1_orders,
  CAST(NULL AS INT64) AS d1_units,
  CAST(NULL AS FLOAT64) AS d1_gp,
  CAST(NULL AS FLOAT64) AS d1_gp_roas,
  CAST(NULL AS INT64) AS w_clicks,
  CAST(NULL AS FLOAT64) AS w_spend,
  CAST(NULL AS INT64) AS w_orders,
  CAST(NULL AS INT64) AS w_units,
  CAST(NULL AS FLOAT64) AS w_gp,
  CAST(NULL AS FLOAT64) AS w_gp_roas,
  CAST(NULL AS STRING) AS profit_1d,
  CAST(NULL AS STRING) AS profit_w,
  CAST(NULL AS FLOAT64) AS spend_per_day,
  CAST(NULL AS FLOAT64) AS units_per_day,
  CAST(NULL AS FLOAT64) AS w_spend_per_day,
  CAST(NULL AS FLOAT64) AS w_units_per_day,
  CAST(NULL AS FLOAT64) AS pct_of_family_velocity,
  CAST(NULL AS STRING) AS target_class,
  CAST(NULL AS BOOL) AS escalated,
  CAST(NULL AS BOOL) AS halve_viable,
  CAST(NULL AS FLOAT64) AS bid_floor,
  CAST(NULL AS FLOAT64) AS suggested_bid,
  CAST(NULL AS BOOL) AS bid_clamped_to_floor,
  CAST(NULL AS FLOAT64) AS suggested_budget,
  CAST(NULL AS FLOAT64) AS now_value,
  CAST(NULL AS FLOAT64) AS suggested_value,
  CAST(NULL AS FLOAT64) AS dollars_freed_per_day,
  CAST(NULL AS FLOAT64) AS units_removed_per_day,
  CAST(NULL AS FLOAT64) AS days_bought,
  CAST(NULL AS FLOAT64) AS days_bought_if_paused,
  CAST(NULL AS BOOL) AS is_proposal,
  CAST(NULL AS INT64) AS dollar_rank,
  CAST(NULL AS INT64) AS proposal_rank,
  CAST(NULL AS STRING) AS action,
  CAST(NULL AS STRING) AS action_reason,
  CAST(NULL AS STRING) AS action_reason_short,
  CAST(NULL AS BOOL) AS redirect_mode,
  CAST(NULL AS STRING) AS hero_asin,
  CAST(NULL AS STRING) AS hero_product,
  CAST(NULL AS FLOAT64) AS hero_rate,
  CAST(NULL AS FLOAT64) AS hero_cover,
  -- v27.80: campaign-scope columns are campaign-grain — meaningless on an ASIN row
  CAST(NULL AS BOOL) AS serves_only_binding,
  CAST(NULL AS INT64) AS n_own_asins
FROM asin_shares s

UNION ALL BY NAME

-- CAMPAIGN — the budget lever. now_value = the daily budget; suggested_value = the paired cut.
SELECT
  'CAMPAIGN' AS row_kind,
  c.family AS family,
  c.risk_state AS risk_state,
  CASE c.risk_state WHEN 'CRITICAL' THEN 1 WHEN 'THROTTLE' THEN 2 WHEN 'WATCH' THEN 3 ELSE 4 END AS risk_rank,
  -- v27.81 LEGIBILITY: a Sponsored Brands / video campaign in a redirect-mode family goes SILENT as
  -- a side effect of the family gate (the is_proposal expression far below drops it because it has
  -- no product scope row to prove it serves only the dry variation). That silence is CORRECT —
  -- measured 2026-08-17, 82-90% of what these campaigns sell is an IN-STOCK sibling (dry-variation
  -- share 18.0% / 14.3% / 10.5% over 60d), so braking them sacrifices the majority to slow a
  -- minority — but until now it was stated nowhere and read as an omission. Say it, in the columns
  -- that already exist. NULL n_own_asins = no scope row = SB/video (same convention the two scope
  -- columns at the bottom of this branch document), and redirect_mode + no scope row already
  -- implies is_proposal = FALSE, so this clause fires exactly on the silenced rows. NO NEW SOURCE
  -- AND NO NEW JOIN: rmc and scc are already joined below for the gate; this reads the same rows.
  CONCAT(c.action_reason,
         IF(COALESCE(rmc.redirect_mode, FALSE) AND scc.n_own_asins IS NULL,
            ' NOT BRAKED — family-level video ad: most of what it sells is an in-stock sibling, so '
            || 'braking it would sacrifice the majority to slow a minority.', '')) AS risk_reason,
  CONCAT(c.action_reason_short,
         IF(COALESCE(rmc.redirect_mode, FALSE) AND scc.n_own_asins IS NULL,
            ' · family-level video ad — most of what it sells is in stock ⇒ no brake',
            '')) AS risk_reason_short,
  (SELECT d FROM snap) AS snapshot_date,
  CAST(NULL AS STRING) AS asin,
  CAST(NULL AS STRING) AS product,
  CAST(NULL AS INT64) AS fba_qty,
  CAST(NULL AS INT64) AS awd_qty,
  CAST(NULL AS INT64) AS sellable_qty,
  CAST(NULL AS INT64) AS in_transit_qty,
  CAST(NULL AS INT64) AS in_transit_awd_qty,
  CAST(NULL AS INT64) AS mfr_ready_qty,
  CAST(NULL AS INT64) AS in_production_qty,
  CAST(NULL AS INT64) AS upstream_qty,
  CAST(NULL AS INT64) AS total_pipeline_qty,
  CAST(NULL AS FLOAT64) AS velocity_forecast,
  CAST(NULL AS FLOAT64) AS velocity_30d,
  CAST(NULL AS FLOAT64) AS velocity_14d,
  CAST(NULL AS FLOAT64) AS velocity_7d,
  CAST(NULL AS FLOAT64) AS velocity_actual,
  CAST(NULL AS STRING) AS velocity_actual_basis,
  CAST(NULL AS FLOAT64) AS velocity_used,
  CAST(NULL AS INT64) AS doc_walk_days,
  CAST(NULL AS FLOAT64) AS doc_flat_days,
  CAST(NULL AS FLOAT64) AS doc_flat_forecast_days,
  CAST(NULL AS FLOAT64) AS days_of_cover,
  CAST(NULL AS FLOAT64) AS days_of_cover_avail,
  CAST(NULL AS STRING) AS cover_basis,
  CAST(NULL AS FLOAT64) AS days_of_cover_forecast,
  CAST(NULL AS FLOAT64) AS days_of_cover_avail_forecast,
  CAST(NULL AS STRING) AS cover_basis_forecast,
  CAST(NULL AS STRING) AS risk_state_forecast,
  CAST(NULL AS FLOAT64) AS bridge_gap_days_forecast,
  CAST(NULL AS FLOAT64) AS binding_cover_forecast_days,
  CAST(NULL AS FLOAT64) AS at_risk_units_share_pct_forecast,
  CAST(NULL AS DATE) AS stockout_date,
  CAST(NULL AS DATE) AS po_deadline,
  CAST(NULL AS BOOL) AS too_late_to_replenish,
  CAST(NULL AS INT64) AS full_lead_days,
  CAST(NULL AS FLOAT64) AS bridge_gap_days,
  CAST(NULL AS DATE) AS next_arrival_date,
  CAST(NULL AS INT64) AS days_to_arrival,
  CAST(NULL AS INT64) AS next_arrival_qty,
  CAST(NULL AS INT64) AS season_demand_units,
  CAST(NULL AS INT64) AS season_gap_units,
  CAST(NULL AS INT64) AS overdue_pending_qty,
  CAST(NULL AS DATE) AS overdue_pending_oldest_eta,
  CAST(NULL AS INT64) AS units_90d,
  CAST(NULL AS FLOAT64) AS family_units_share_pct,
  -- v27.81, ADDITIVE OBSERVABILITY (was CAST(NULL AS STRING)): publish the binding (dry) ASIN on
  -- the CAMPAIGN branch. WHY: serves_only_binding two dozen lines below — and the is_proposal gate
  -- that depends on it — are both computed against rmc.binding_asin, which until now was INTERNAL.
  -- A panel could see the boolean but could not reproduce it from published columns, i.e. could not
  -- say WHICH variation "only serves the binding one" refers to. NO NEW JOIN AND NO NEW CTE: rmc is
  -- already joined below for the redirect gate and this reads the same row (the planner-ceiling
  -- rule, see header). Family-constant, so it is well defined at campaign grain.
  rmc.binding_asin AS binding_asin,
  CAST(NULL AS STRING) AS binding_product,
  CAST(NULL AS FLOAT64) AS at_risk_units_share_pct,
  CAST(NULL AS DATE) AS binding_next_arrival_date,
  CAST(NULL AS BOOL) AS arrival_freshness_conflict,
  CAST(NULL AS STRING) AS arrival_conflict_note,
  c.binding_cover_days AS binding_cover_days,
  c.family_flat_cover_days AS family_flat_cover_days,
  c.family_sellable_qty AS family_sellable_qty,
  c.family_velocity AS family_velocity,
  CAST(NULL AS DATE) AS first_sale_date,
  CAST(NULL AS INT64) AS family_age_months,
  CAST(NULL AS INT64) AS campaigns,
  CAST(NULL AS INT64) AS capped_campaigns,
  CAST(NULL AS INT64) AS nonconv_targets,
  CAST(NULL AS FLOAT64) AS nonconv_spend_per_day,
  CAST(NULL AS INT64) AS nonconv_targets_capped,
  CAST(NULL AS FLOAT64) AS nonconv_spend_per_day_capped,
  CAST(NULL AS INT64) AS stalled_targets,
  CAST(NULL AS FLOAT64) AS stalled_spend_per_day,
  CAST(NULL AS INT64) AS conv_targets,
  CAST(NULL AS FLOAT64) AS conv_spend_per_day,
  CAST(NULL AS FLOAT64) AS conv_days_bought_max,
  CAST(NULL AS INT64) AS escalated_targets,
  CAST(NULL AS FLOAT64) AS escalated_spend_per_day,
  c.park_targets AS park_targets,
  c.bid_cut_targets AS bid_cut_targets,
  CAST(NULL AS INT64) AS not_executable_targets,
  c.proposal_targets AS proposal_targets,
  c.dollars_freed_per_day AS proposal_freed_per_day,
  c.days_bought AS proposal_days_bought,
  c.protected_targets AS protected_targets,
  CAST(NULL AS FLOAT64) AS protected_spend_per_day,
  CAST(NULL AS INT64) AS budget_cut_campaigns,
  CAST(NULL AS FLOAT64) AS budget_cut_per_day,
  c.cid AS campaign_id,
  c.campaign_name AS campaign_name,
  c.channel AS channel,
  c.campaign_budget AS campaign_budget,
  c.is_defense AS is_defense,
  c.is_seasonal AS is_seasonal,
  c.is_auto_campaign AS is_auto_campaign,
  c.is_capped AS is_capped,
  c.days_capped_7d AS days_capped_7d,
  c.util_7d AS util_7d,
  c.launch_exempt_active AS launch_exempt_active,
  c.launch_exempt_until AS launch_exempt_until,
  c.launch_envelope_state AS launch_envelope_state,
  CAST(NULL AS STRING) AS keyword_id,
  CAST(NULL AS STRING) AS ad_group_id,
  CAST(NULL AS STRING) AS target_text,
  CAST(NULL AS STRING) AS match_type,
  CAST(NULL AS STRING) AS keyword_state,
  CAST(NULL AS FLOAT64) AS current_bid,
  CAST(NULL AS BOOL) AS is_auto,
  CAST(NULL AS BOOL) AS is_pt,
  CAST(NULL AS STRING) AS creative_type,
  c.settled_through AS settled_through,
  c.settle_days AS settle_days,
  c.s28_clicks AS s28_clicks,
  c.s28_spend AS s28_spend,
  c.s28_orders AS s28_orders,
  c.s28_units AS s28_units,
  c.s28_gp AS s28_gp,
  c.s28_gp_roas AS s28_gp_roas,
  c.s90_clicks AS s90_clicks,
  c.s90_spend AS s90_spend,
  c.s90_orders AS s90_orders,
  c.s90_gp AS s90_gp,
  c.s90_gp_roas AS s90_gp_roas,
  c.last_ads_day AS last_ads_day,
  c.w_days AS w_days,
  c.in_peak AS in_peak,
  c.w_days_reason AS w_days_reason,
  c.d1_clicks AS d1_clicks,
  c.d1_spend AS d1_spend,
  c.d1_orders AS d1_orders,
  c.d1_units AS d1_units,
  c.d1_gp AS d1_gp,
  c.d1_gp_roas AS d1_gp_roas,
  c.w_clicks AS w_clicks,
  c.w_spend AS w_spend,
  c.w_orders AS w_orders,
  c.w_units AS w_units,
  c.w_gp AS w_gp,
  c.w_gp_roas AS w_gp_roas,
  CAST(NULL AS STRING) AS profit_1d,
  CAST(NULL AS STRING) AS profit_w,
  c.spend_per_day AS spend_per_day,
  c.units_per_day AS units_per_day,
  c.w_spend_per_day AS w_spend_per_day,
  c.w_units_per_day AS w_units_per_day,
  CAST(NULL AS FLOAT64) AS pct_of_family_velocity,
  CAST(NULL AS STRING) AS target_class,
  CAST(NULL AS BOOL) AS escalated,
  CAST(NULL AS BOOL) AS halve_viable,
  CAST(NULL AS FLOAT64) AS bid_floor,
  CAST(NULL AS FLOAT64) AS suggested_bid,
  CAST(NULL AS BOOL) AS bid_clamped_to_floor,
  c.suggested_budget AS suggested_budget,
  c.campaign_budget AS now_value,
  c.suggested_budget AS suggested_value,
  c.dollars_freed_per_day AS dollars_freed_per_day,
  c.units_removed_per_day AS units_removed_per_day,
  c.days_bought AS days_bought,
  CAST(NULL AS FLOAT64) AS days_bought_if_paused,
  -- v27.73 redirect gate: budget cuts are the BRAKE arm — off while the family re-aims doorways.
  -- v27.80: unless this campaign is DEDICATED to the dry variation, in which case there is no
  -- doorway to re-aim and the brake is the only lever there is (see the tgt_ranked note).
  (c.suggested_budget IS NOT NULL
   AND (NOT COALESCE(rmc.redirect_mode, FALSE)
        OR (scc.sole_asin IS NOT NULL AND scc.sole_asin = rmc.binding_asin))) AS is_proposal,
  CAST(NULL AS INT64) AS dollar_rank,
  CAST(NULL AS INT64) AS proposal_rank,
  c.action AS action,
  -- v27.81: the SAME clause as risk_reason / risk_reason_short at the top of this branch, repeated
  -- rather than shared because camp_final cannot see rmc/scc (it is joined here, and giving that CTE
  -- its own join is exactly the planner-ceiling move this view forbids). Repeated it MUST be: the
  -- panel's campaign row renders action_reason_short with action_reason as its tooltip
  -- (LowStockPhase.tsx), while risk_reason is what the ASIN/family rows render — so a clause written
  -- only on the risk_* pair would be true and invisible. CAMPAIGN's risk_* IS its action_*; the two
  -- must not drift.
  CONCAT(c.action_reason,
         IF(COALESCE(rmc.redirect_mode, FALSE) AND scc.n_own_asins IS NULL,
            ' NOT BRAKED — family-level video ad: most of what it sells is an in-stock sibling, so '
            || 'braking it would sacrifice the majority to slow a minority.', '')) AS action_reason,
  CONCAT(c.action_reason_short,
         IF(COALESCE(rmc.redirect_mode, FALSE) AND scc.n_own_asins IS NULL,
            ' · family-level video ad — most of what it sells is in stock ⇒ no brake',
            '')) AS action_reason_short,
  -- v27.78: publish the REAL redirect flag on the CAMPAIGN branch (was CAST(NULL AS BOOL)).
  -- WHY: redirect mode SUPPRESSES this branch's own budget-cut proposals (the is_proposal gate two
  -- lines above), so on a re-aiming family the campaign row goes silent — no suggested budget, no
  -- proposal target. V_PANEL_OWNERSHIP's arm B reads exactly those two signals to decide "low stock
  -- has an opinion here", so it went blind on the very campaigns low stock was acting hardest on
  -- (10 of 14 campaigns lost their proposal targets to the v27.73 gate; 5 lost both signals). A
  -- family being RE-AIMED *is* low stock acting, and the panel must be able to see it. No new join
  -- and no new CTE: rmc is already joined below for the is_proposal gate — this reads the same row.
  COALESCE(rmc.redirect_mode, FALSE) AS redirect_mode,
  CAST(NULL AS STRING) AS hero_asin,
  CAST(NULL AS STRING) AS hero_product,
  CAST(NULL AS FLOAT64) AS hero_rate,
  CAST(NULL AS FLOAT64) AS hero_cover,
  -- v27.80: the two scope columns, published so a panel can say WHY a redirect-mode campaign is
  -- still being braked (or still is not). NULL n_own_asins = no scope row = SB/video.
  (scc.sole_asin IS NOT NULL AND scc.sole_asin = rmc.binding_asin) AS serves_only_binding,
  scc.n_own_asins AS n_own_asins
FROM camp_final c
LEFT JOIN rmode rmc ON rmc.family = c.family
-- v27.80: PHYSICAL table (planner ceiling — never inline V_CAMPAIGN_PRODUCT_SCOPE here)
LEFT JOIN `onyga-482313.OI.T_CAMPAIGN_PRODUCT_SCOPE` scc ON scc.campaign_id = c.cid

UNION ALL BY NAME

-- TARGET — the money, ranked. now_value = the bid; suggested_value = the bid cut (NULL on a park).
SELECT
  'TARGET' AS row_kind,
  r.family AS family,
  r.risk_state AS risk_state,
  CASE r.risk_state WHEN 'CRITICAL' THEN 1 WHEN 'THROTTLE' THEN 2 WHEN 'WATCH' THEN 3 ELSE 4 END AS risk_rank,
  r.action_reason AS risk_reason,
  r.action_reason_short AS risk_reason_short,
  (SELECT d FROM snap) AS snapshot_date,
  CAST(NULL AS STRING) AS asin,
  CAST(NULL AS STRING) AS product,
  CAST(NULL AS INT64) AS fba_qty,
  CAST(NULL AS INT64) AS awd_qty,
  CAST(NULL AS INT64) AS sellable_qty,
  CAST(NULL AS INT64) AS in_transit_qty,
  CAST(NULL AS INT64) AS in_transit_awd_qty,
  CAST(NULL AS INT64) AS mfr_ready_qty,
  CAST(NULL AS INT64) AS in_production_qty,
  CAST(NULL AS INT64) AS upstream_qty,
  CAST(NULL AS INT64) AS total_pipeline_qty,
  CAST(NULL AS FLOAT64) AS velocity_forecast,
  CAST(NULL AS FLOAT64) AS velocity_30d,
  CAST(NULL AS FLOAT64) AS velocity_14d,
  CAST(NULL AS FLOAT64) AS velocity_7d,
  CAST(NULL AS FLOAT64) AS velocity_actual,
  CAST(NULL AS STRING) AS velocity_actual_basis,
  CAST(NULL AS FLOAT64) AS velocity_used,
  CAST(NULL AS INT64) AS doc_walk_days,
  CAST(NULL AS FLOAT64) AS doc_flat_days,
  CAST(NULL AS FLOAT64) AS doc_flat_forecast_days,
  CAST(NULL AS FLOAT64) AS days_of_cover,
  CAST(NULL AS FLOAT64) AS days_of_cover_avail,
  CAST(NULL AS STRING) AS cover_basis,
  CAST(NULL AS FLOAT64) AS days_of_cover_forecast,
  CAST(NULL AS FLOAT64) AS days_of_cover_avail_forecast,
  CAST(NULL AS STRING) AS cover_basis_forecast,
  CAST(NULL AS STRING) AS risk_state_forecast,
  CAST(NULL AS FLOAT64) AS bridge_gap_days_forecast,
  CAST(NULL AS FLOAT64) AS binding_cover_forecast_days,
  CAST(NULL AS FLOAT64) AS at_risk_units_share_pct_forecast,
  r.family_stockout_date AS stockout_date,
  CAST(NULL AS DATE) AS po_deadline,
  CAST(NULL AS BOOL) AS too_late_to_replenish,
  r.family_full_lead_days AS full_lead_days,
  CAST(NULL AS FLOAT64) AS bridge_gap_days,
  r.family_next_arrival_date AS next_arrival_date,
  CAST(NULL AS INT64) AS days_to_arrival,
  CAST(NULL AS INT64) AS next_arrival_qty,
  CAST(NULL AS INT64) AS season_demand_units,
  CAST(NULL AS INT64) AS season_gap_units,
  CAST(NULL AS INT64) AS overdue_pending_qty,
  CAST(NULL AS DATE) AS overdue_pending_oldest_eta,
  CAST(NULL AS INT64) AS units_90d,
  CAST(NULL AS FLOAT64) AS family_units_share_pct,
  CAST(NULL AS STRING) AS binding_asin,
  r.binding_product_name AS binding_product,
  CAST(NULL AS FLOAT64) AS at_risk_units_share_pct,
  CAST(NULL AS DATE) AS binding_next_arrival_date,
  CAST(NULL AS BOOL) AS arrival_freshness_conflict,
  CAST(NULL AS STRING) AS arrival_conflict_note,
  r.binding_cover_days AS binding_cover_days,
  r.family_flat_cover_days AS family_flat_cover_days,
  r.family_sellable_qty AS family_sellable_qty,
  r.family_velocity AS family_velocity,
  CAST(NULL AS DATE) AS first_sale_date,
  CAST(NULL AS INT64) AS family_age_months,
  CAST(NULL AS INT64) AS campaigns,
  CAST(NULL AS INT64) AS capped_campaigns,
  CAST(NULL AS INT64) AS nonconv_targets,
  CAST(NULL AS FLOAT64) AS nonconv_spend_per_day,
  CAST(NULL AS INT64) AS nonconv_targets_capped,
  CAST(NULL AS FLOAT64) AS nonconv_spend_per_day_capped,
  CAST(NULL AS INT64) AS stalled_targets,
  CAST(NULL AS FLOAT64) AS stalled_spend_per_day,
  CAST(NULL AS INT64) AS conv_targets,
  CAST(NULL AS FLOAT64) AS conv_spend_per_day,
  CAST(NULL AS FLOAT64) AS conv_days_bought_max,
  CAST(NULL AS INT64) AS escalated_targets,
  CAST(NULL AS FLOAT64) AS escalated_spend_per_day,
  CAST(NULL AS INT64) AS park_targets,
  CAST(NULL AS INT64) AS bid_cut_targets,
  CAST(NULL AS INT64) AS not_executable_targets,
  CAST(NULL AS INT64) AS proposal_targets,
  CAST(NULL AS FLOAT64) AS proposal_freed_per_day,
  CAST(NULL AS FLOAT64) AS proposal_days_bought,
  CAST(NULL AS INT64) AS protected_targets,
  CAST(NULL AS FLOAT64) AS protected_spend_per_day,
  CAST(NULL AS INT64) AS budget_cut_campaigns,
  CAST(NULL AS FLOAT64) AS budget_cut_per_day,
  r.cid AS campaign_id,
  r.campaign_name AS campaign_name,
  r.channel AS channel,
  r.campaign_budget AS campaign_budget,
  r.is_defense AS is_defense,
  r.is_seasonal AS is_seasonal,
  r.is_auto_campaign AS is_auto_campaign,
  r.is_capped AS is_capped,
  r.days_capped_7d AS days_capped_7d,
  r.util_7d AS util_7d,
  r.launch_exempt_active AS launch_exempt_active,
  r.launch_exempt_until AS launch_exempt_until,
  r.launch_envelope_state AS launch_envelope_state,
  r.kid AS keyword_id,
  -- v27.63 (Task 1.10): the upload key that was always upstream (kw.cfg.ad_group_id, carried by
  -- the star-select chain) but never selected into the output — so the panel's bid cuts could not
  -- become bulksheet rows Amazon accepts. Same gap, same fix as ParkReverdict the same week.
  r.ad_group_id AS ad_group_id,
  r.target_text AS target_text,
  r.match_type AS match_type,
  r.keyword_state AS keyword_state,
  r.current_bid AS current_bid,
  r.is_auto AS is_auto,
  r.is_pt AS is_pt,
  r.creative_type AS creative_type,
  r.settle_cut AS settled_through,
  r.settle_days AS settle_days,
  r.s28_clicks AS s28_clicks,
  r.s28_spend AS s28_spend,
  r.s28_orders AS s28_orders,
  r.s28_units AS s28_units,
  r.s28_gp AS s28_gp,
  r.s28_gp_roas AS s28_gp_roas,
  r.s90_clicks AS s90_clicks,
  r.s90_spend AS s90_spend,
  r.s90_orders AS s90_orders,
  r.s90_gp AS s90_gp,
  r.s90_gp_roas AS s90_gp_roas,
  r.last_ads_day AS last_ads_day,
  r.w_days AS w_days,
  r.in_peak AS in_peak,
  r.w_days_reason AS w_days_reason,
  r.d1_clicks AS d1_clicks,
  r.d1_spend AS d1_spend,
  r.d1_orders AS d1_orders,
  r.d1_units AS d1_units,
  r.d1_gp AS d1_gp,
  r.d1_gp_roas AS d1_gp_roas,
  r.w_clicks AS w_clicks,
  r.w_spend AS w_spend,
  r.w_orders AS w_orders,
  r.w_units AS w_units,
  r.w_gp AS w_gp,
  r.w_gp_roas AS w_gp_roas,
  r.profit_1d AS profit_1d,
  r.profit_w AS profit_w,
  r.spend_per_day AS spend_per_day,
  r.units_per_day AS units_per_day,
  r.w_spend_per_day AS w_spend_per_day,
  r.w_units_per_day AS w_units_per_day,
  r.pct_of_family_velocity AS pct_of_family_velocity,
  r.target_class AS target_class,
  r.escalated AS escalated,
  r.halve_viable AS halve_viable,
  r.bid_floor AS bid_floor,
  r.suggested_bid AS suggested_bid,
  r.bid_clamped_to_floor AS bid_clamped_to_floor,
  CAST(NULL AS FLOAT64) AS suggested_budget,
  r.current_bid AS now_value,
  r.suggested_bid AS suggested_value,
  r.dollars_freed_per_day AS dollars_freed_per_day,
  r.units_removed_per_day AS units_removed_per_day,
  r.days_bought AS days_bought,
  r.days_bought_if_paused AS days_bought_if_paused,
  r.is_proposal AS is_proposal,
  r.dollar_rank AS dollar_rank,
  r.proposal_rank AS proposal_rank,
  r.action AS action,
  r.action_reason AS action_reason,
  r.action_reason_short AS action_reason_short,
  CAST(NULL AS BOOL) AS redirect_mode,
  CAST(NULL AS STRING) AS hero_asin,
  CAST(NULL AS STRING) AS hero_product,
  CAST(NULL AS FLOAT64) AS hero_rate,
  CAST(NULL AS FLOAT64) AS hero_cover,
  -- v27.80: the real scope verdict — this is the row whose is_proposal the exception restores
  r.serves_only_binding AS serves_only_binding,
  r.n_own_asins AS n_own_asins
FROM tgt_ranked r;
