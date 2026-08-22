-- =============================================================================================
-- V_LAUNCH_BID_LADDER — the launch exemption's ONE downward lever: a gentle bid search on the
-- SHORT window. Target grain (one row per campaign × keyword/target), advisory, never auto-applied.
-- =============================================================================================
-- v27.59 (Ori 2026-08-13). HIS WORDS, VERBATIM:
--   "launch_bid ok between 0.5 and 0.7 trim keyword bid 5% and use launch_bid / improving between
--    0.7 and 0.9 do not do / profitable launch_bid ok <0.5 trim keyword bid 10%"
-- and, correcting the first build: the ladder judges on the SHORT window (last day + 7d, or 3d in
-- peak — the same w-window the engines already use), NOT the settled 90d/28d window.
--
-- ── THE READING THIS VIEW IMPLEMENTS (it is a reading; the sentence above is not a spec) ────────
-- The four numbers 0.5 / 0.7 / 0.9 are read as GP-ROAS BANDS — gross profit ÷ ad spend with tier
-- COGS already charged, so 1.0 is breakeven AFTER product cost. That reading is forced by the words
-- attached to them: 0.7–0.9 is called "improving" and >= 0.9 "profitable", which are ROAS words, and
-- 0.9 sitting just under 1.0 is exactly where a launch stops losing money. Nothing else in the
-- sentence is a ratio.
--
--   GP-ROAS < 0.5        -> LAUNCH_BID_TRIM_10   trim the bid 10%
--   GP-ROAS 0.5 .. 0.7   -> LAUNCH_BID_TRIM_5    trim the bid  5%, walking toward launch_bid
--   GP-ROAS 0.7 .. 0.9   -> LAUNCH_BID_HOLD_IMPROVING   no action ("improving — leave it alone")
--   GP-ROAS >= 0.9       -> LAUNCH_BID_HOLD_PROFITABLE  no action ("profitable, launch_bid ok")
-- Bands are half-open [lo, hi) so no GP-ROAS can land in two of them.
--
-- THIS IS A BID SEARCH, NOT A LOSS-CUT. The standing doctrine — "launch = FIND THE RIGHT BID, never
-- loss-cut; bleed via search-term negate" — is untouched. Everything V_LAUNCH_EXEMPTION blocks stays
-- blocked: campaign stops, GUARDIAN/BLITZ/COOLDOWN budget decreases, RESTORE_BUDGET_PRE_PEAK,
-- post-grace CONTAIN, and any downward budget NUMBER on an exempt campaign. This view emits no
-- budget column at all and no park/stop verb. Its whole vocabulary is "trim the bid a little" and
-- "leave it alone". The steepest thing it can say is -10%.
--
-- ── THE JUDGED WINDOW: SHORT, AND DELIBERATELY UNSETTLED ────────────────────────────────────────
-- w_days comes from V_PEAK_WINDOW_RULE — the one place the house decides how long "recent" is
-- (7 days off peak; 3 in peak unless 7 has been PROVEN better for that occurrence). Today: in peak
-- (BTS), w_days = 3. The window is the last w_days COMPLETE days, ending the day BEFORE the ads
-- watermark (MAX(date) in FACT_AMAZON_ADS) — v27.98; through v27.97 it ended ON the watermark and
-- so judged one day that was still arriving. Anchoring on the watermark rather than on "today − 1"
-- means that when the 07:40 load is late the whole ladder slides back a day by itself instead of
-- judging a half-loaded day. The watermark day itself is published as d1_* and may VETO; it may
-- never drive a move.
--
--   ⚠ SETTLE CAVEAT, stated once. A 3-day window is UNSETTLED. SP sales accrue to D+7 and SB to
--   D+14, so the last day understates GP-ROAS and the band is biased DOWNWARD — toward trimming.
--   That is accepted, not accidental: Ori asked for the short window explicitly, and the cost of
--   being wrong here is 5–10% of one bid for one day, which the ladder re-judges tomorrow. Compare
--   V_LAUNCH_EXEMPTION, whose settled 28d evidence gates a CAMPAIGN STOP — a decision you cannot
--   undo by re-running it, and which therefore may not be taken on unsettled clicks. Different
--   blast radius, different window. Both numbers are published side by side on every row
--   (w_gp_roas vs settled_gp_roas) so the disagreement is visible rather than argued about.
--
-- LAST DAY IS PUBLISHED, NOT JUDGED. Ori's table format is "last day + 7 days window", so d1_* is
-- carried on every row. The BAND is taken on the w-window alone. The "must fail BOTH windows" test
-- belongs to the low-stock −50% rule (V_LOW_STOCK_ADS), which is a different, far more aggressive
-- lever; importing its conjunction here would silently disable the ladder on every target that had
-- one good day, which is not what Ori asked for.
--
-- EVIDENCE GATE = spend > 0 ON THE WINDOW, and nothing more. GP-ROAS is GP ÷ spend; with no spend
-- there is no ratio to band, so those rows read LAUNCH_BID_HOLD_NO_EVIDENCE and propose nothing. No
-- minimum-click threshold was invented — Ori did not set one, and a 5–10% bid nudge is not a
-- decision that needs one. Instead the evidence is PUBLISHED: w_clicks / w_orders / w_spend on every
-- row, plus evidence_grade (THIN under 3 clicks) so a one-click verdict is legible as a one-click
-- verdict. evidence_grade changes no action.
--
-- ── HOW launch_bid ANCHORS THE TRIM: DESTINATION, NOT ONE-STEP CEILING ──────────────────────────
-- launch_bid is READ, never recomputed. It is V_ADS_COACH's own aggressive launch bid — anchor CPC
-- (research 30d/12m, else the target's own 8w CPC, else the strategy template max, else the flat
-- cold bid) × LAUNCH_BID_MULT, capped at LAUNCH_BID_CEILING — carried through
-- FACT_ADS_COACH_ACTIONS.launch_bid / launch_bid_source. This view multiplies it by nothing.
--
--   step_bid     = CEIL(current_bid × factor × 100) / 100      -- the band decides the STEP SIZE
--   proposed_bid = GREATEST(step_bid, bid_floor), capped at current_bid
--   CEIL to the cent, never ROUND: rounding a $0.36 bid down to $0.32 is a 11.1% cut on a 10% band.
--   Ceiling to the cent guarantees the realised trim is never DEEPER than the band says (measured
--   today: TRIM_10 spans -10.0%..-6.9%, TRIM_5 spans -4.8%..-4.7%).
--   THE CEIL IS DONE IN NUMERIC, NOT FLOAT64, and that is not fussiness. In binary floating point
--   0.40 × 0.95 × 100 evaluates to 38.000000000000006, which CEILs to 39 — a $0.40 bid would be
--   "trimmed 5%" to $0.39, a 2.5% move. Exact decimal arithmetic gives 38 and $0.38. Every bid this
--   view prices is a two-decimal money value, so NUMERIC is the correct type for the rounding step
--   (the house already learned this in V_KEYWORD_GUARD's determinism fix); the result is cast back
--   to FLOAT64 so the output schema is unchanged.
--   launch_bid   = the DESTINATION the ladder walks toward, published on every row
--
-- Three readings of "use launch_bid" were tested against today's 105 exempt target rows. Two are
-- dead on arrival and the third has to be bounded:
--   1. launch_bid as the TARGET (proposed = launch_bid × 0.95) would RAISE the bid on 92 of the 105
--      rows — current bids sit at $0.24–$0.25 against launch_bids up to $1.40. It answers the word
--      "trim" with a 4–5× increase. Rejected.
--   2. launch_bid as a FLOOR ("launch_bid is ok, don't go below it") blocks the trim outright on
--      those same 92 rows, and on BOTH rows in the 0.5–0.7 band — every trimmed bid is already far
--      under launch_bid, so the ladder would emit nothing at all in the very band Ori wrote the
--      instruction for. Rejected.
--   3. launch_bid as a CEILING on the anchor (anchor = LEAST(current_bid, launch_bid)) is the only
--      reading that both trims and uses the number. But applied in ONE step it stops being gentle:
--      "best friends personalized gifts girls" (bid $1.36, launch_bid $0.65) would be cut to $0.59
--      — −56.6% — on ONE click of unsettled evidence. A −57% move is a loss-cut wearing a trim's
--      name, and the launch doctrine's whole point is that a launch is never loss-cut.
--
-- SO THE CEILING IS KEPT AS A DESTINATION AND THE BAND KEEPS THE STEP. Ori's sentence carries two
-- constraints — "trim keyword bid 5%" (how far) and "use launch_bid" (where to) — and a bid SEARCH
-- honours both by WALKING: each run takes the band's step, and because the next run re-reads the
-- lowered bid, a bid above launch_bid converges on it at 5%/10% a run for as long as the short
-- window keeps saying the target is losing money. The $1.36 row above reaches $0.65 in 8 runs
-- instead of one, and stops the moment its GP-ROAS crosses 0.7. Nothing is given up but speed, and
-- speed is exactly what one click of unsettled evidence does not buy.
--   Published so this is auditable and reversible in one CASE:
--     above_launch_bid      TRUE where current_bid > launch_bid (the ceiling has something to do)
--     runs_to_launch_bid    how many runs at this band's step until the bid reaches launch_bid
--     ceiling_step_bid      what reading 3 applied in ONE step would have proposed
--   Today above_launch_bid is TRUE on exactly 1 of the 73 rows, so this choice moves ONE number —
--   but that number is the difference between a −10.3% trim and a −56.6% cut, and it will matter
--   more as bids drift.
--
-- WHERE THERE IS NO CURRENT BID, launch_bid IS THE BASE — COALESCE(current_bid, launch_bid), which
-- is V_ADS_COACH's own idiom for "use launch_bid" three lines away in launch_recommended_bid. That
-- arm is dormant today (0 of 105 exempt target rows have a NULL current_bid; those rows are excluded
-- from the population anyway, since a trim needs a bid to trim), and it is written down so the
-- meaning of the phrase is not re-litigated later.
--
-- Never a raise: proposed_bid is capped at current_bid, so on this view the arrow only ever points
-- down or nowhere.
--
-- ── FLOORS: NO TRIM MAY LAND BELOW THE ROW'S PLATFORM/HOUSE MINIMUM ─────────────────────────────
--   SP                                    $0.20  house floor (Amazon's own SP minimum is $0.02, but
--                                                a bid that low buys no placement worth having)
--   SB, video creative                    $0.25  Amazon's SB minBid — under it the row is rejected
--   SB, PRODUCT_COLLECTION/STORE_SPOTLIGHT $0.10 Amazon's minBid for those creatives
-- v27.104 (2026-08-22): the three numbers are DECLARED ONCE in FN_BID_FLOOR (channel, creative_type)
-- and this view calls it; the keyword state ladder reads the same function through V_BID_FLOOR. The
-- output is byte-identical to v27.98 (keyed diff, 72 rows @ 2026-08-22). When the
-- floor binds, floor_binding = TRUE and the realised trim is smaller than the band's nominal % — the
-- reason string says so rather than quietly reporting "-10%". If the floor leaves no room at all
-- (bid already at or under it) the row reads LAUNCH_BID_HOLD_AT_FLOOR and proposes nothing.
--
-- ── WHO IS IN, WHO IS OUT ───────────────────────────────────────────────────────────────────────
-- IN:  every TARGET-grain coach row whose campaign is in V_LAUNCH_EXEMPTION (i.e. its FAMILY is
--      inside its launch window — membership computed from the family's own first sale, expiring by
--      itself), campaign_state = 'ENABLED', keyword_id NOT NULL.
-- OUT: brand DEFENSE campaigns (V_CAMPAIGN_ROLE role/strategy_category LIKE '%DEFENSE%'). Defense is
--      never profit-judged under standing doctrine — it is a moat, not a ROAS bet. No exempt
--      campaign is defense today, so this excludes nothing; it is here so the rule is right the day
--      a launch family gets a defense campaign.
-- OUT: coach rows already marked TARGET_PAUSED — there is no live bid to trim.
--
-- GRAIN + DEDUP. V_ADS_COACH is search-term/ASIN grain, so one keyword arrives as several TARGET
-- rows with DIFFERENT launch_bid values (today 105 rows over 74 keywords; "gift for girls" alone
-- carries launch_bid 1.40 / 1.38 / 1.00). A bulksheet takes ONE bid per keyword, and two rows
-- proposing two bids for one keyword is the contradiction V_COACH_APPLY exists to prevent. This view
-- deduplicates to (campaign_id, keyword_id) with a single ARRAY_AGG(STRUCT(...) ORDER BY ... LIMIT 1)
-- — one struct, so current_bid / launch_bid / launch_bid_source / the coach's own action are read
-- from ONE row and cannot be cross-paired. Never two ANY_VALUE()s out of one GROUP BY. The order is
-- total (priority_score DESC, launch_bid DESC, asin, action_id) so the pick is deterministic.
--
-- RELATION TO THE COACH'S OWN BID ACTIONS. The exemption always allowed bid trims, and the coach
-- still emits its own REDUCE_BID/INCREASE_BID on these campaigns. This view does NOT override or
-- suppress them — it publishes coach_target_action / coach_recommended_bid next to its own proposal
-- and flags disagreement (conflicts_with_coach), so the two are reconciled by Ori looking at them,
-- not by one silently winning. Changing V_ADS_COACH's bid arm was outside what Ori asked for.
--
-- NOTHING AUTO-APPLIES. Advisory, like every Weekly Run panel. is_proposal marks the rows that carry
-- a real number; everything else is context.
--
-- Consumers: cube/schema/LaunchBidLadder.js -> the "Launch exemption" panel's bid-ladder table.
-- SOP: architecture/LAUNCH_EXEMPTION.md §8.
-- =============================================================================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_LAUNCH_BID_LADDER` AS

WITH k AS (
  SELECT
    0.50 AS band_trim10_hi,   -- GP-ROAS below this  -> -10%
    0.70 AS band_trim5_hi,    -- [0.50, 0.70)        -> -5%, anchored on launch_bid
    0.90 AS band_improve_hi,  -- [0.70, 0.90)        -> improving, no action; >= 0.90 profitable
    0.90 AS factor_trim10,    -- the -10% multiplier
    0.95 AS factor_trim5,     -- the -5%  multiplier
    -- v27.104: the three bid floors (SP $0.20 house / SB video $0.25 / SB collection $0.10) no
    -- longer live here — FN_BID_FLOOR is the ONE definition, called in `graded` below.
    3    AS thin_clicks,      -- under this many window clicks the evidence is LABELLED thin
    35   AS fact_scan_days    -- bounds the FACT scan; only the last w_days are ever read
),

-- ─── the judged window: ads watermark + the house's own w_days (7 off peak, 3 in peak) ───
win AS (
  SELECT
    (SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`) AS last_day,
    p.in_peak,
    p.w_days,
    p.occurrence_type,
    p.w_days_source,
    p.w_days_reason
  FROM `onyga-482313.OI.V_PEAK_WINDOW_RULE` p          -- exactly one row, by construction
),
winx AS (
  SELECT
    w.*,
    -- v27.98 (Ori 2026-08-21): COMPLETE DAYS. The judged window is the w_days days ending the day
    -- BEFORE the watermark, verbatim the shape its sibling V_LOW_STOCK_ADS has run since v27.74.
    -- It used to end ON the watermark, so a 3-day band was taken on two complete days plus one that
    -- is only ~62% loaded at the hour the ladder is read, while the sentence on the row said "the
    -- 3-day window" — the same words the other engines use for the COMPLETE-days span. Nothing on
    -- the row explained the difference, and the difference was not cosmetic: a keyword whose only
    -- converting day had not finished arriving read 0.00x and was trimmed. That is the expensive
    -- direction here, because a launch is never loss-cut — the ladder exists to FIND the right bid,
    -- so a trim that should not have fired spends real money walking a good bid down.
    -- The last day is NOT thrown away: it stays keyed separately as d1_* (see `ev`), published on
    -- every row, and may stand as a one-way veto — it may never DRIVE a move.
    DATE_SUB(w.last_day, INTERVAL w.w_days DAY) AS window_start,
    DATE_SUB(w.last_day, INTERVAL 1 DAY)        AS window_end
  FROM win w
),

-- ─── population: TARGET rows on ENABLED, launch-exempt, non-defense campaigns ───
defense AS (
  SELECT DISTINCT CAST(campaign_id AS STRING) AS campaign_id
  FROM `onyga-482313.OI.V_CAMPAIGN_ROLE`
  -- campaign_id IS NOT NULL matters: a NULL inside a NOT IN subquery makes the whole predicate
  -- NULL and would silently empty the population.
  WHERE campaign_id IS NOT NULL
    AND (UPPER(COALESCE(role, '')) LIKE '%DEFENSE%'
      OR UPPER(COALESCE(strategy_category, '')) LIKE '%DEFENSE%')
),

pop AS (
  SELECT
    CAST(a.campaign_id AS STRING) AS campaign_id,
    CAST(a.keyword_id   AS STRING) AS keyword_id,
    lx.family,
    a.campaign_name,
    a.campaign_type,
    lx.campaign_state,
    lx.exempt_until,
    lx.exempt_reason,
    lx.settled_gp_roas   AS campaign_settled_gp_roas,
    lx.settled_clicks    AS campaign_settled_clicks,
    lx.protected_winner  AS campaign_protected_winner,
    -- ONE struct = one source row. Never two ANY_VALUE()s from one GROUP BY.
    ARRAY_AGG(
      STRUCT(
        CAST(a.ad_group_id AS STRING) AS ad_group_id,
        a.targeting            AS targeting,
        a.match_type           AS match_type,
        a.current_bid          AS current_bid,
        a.launch_bid           AS launch_bid,
        a.launch_bid_source    AS launch_bid_source,
        a.launch_phase         AS launch_phase,
        a.launch_decision      AS launch_decision,
        a.action               AS coach_target_action,
        a.recommended_bid      AS coach_recommended_bid,
        a.priority_score       AS priority_score
      )
      ORDER BY a.priority_score DESC, a.launch_bid DESC, a.asin, a.action_id
      LIMIT 1
    )[OFFSET(0)] AS pick
  FROM `onyga-482313.OI.FACT_ADS_COACH_ACTIONS` a
  JOIN `onyga-482313.OI.V_LAUNCH_EXEMPTION` lx
    ON lx.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.action_type = 'TARGET'
    AND a.keyword_id IS NOT NULL
    AND a.current_bid IS NOT NULL
    AND lx.campaign_state = 'ENABLED'
    AND a.action <> 'TARGET_PAUSED'
    AND CAST(a.campaign_id AS STRING) NOT IN (SELECT campaign_id FROM defense)
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),

-- ─── SB creative type decides the SB floor ($0.25 video vs $0.10 collection/spotlight) ───
ag AS (
  SELECT CAST(ad_group_id AS STRING) AS ad_group_id, ANY_VALUE(creative_type) AS creative_type
  FROM `onyga-482313.OI.DIM_AD_GROUP`
  WHERE is_current
  GROUP BY 1
),

-- ─── the evidence: last day + the w-window, at keyword grain, GP with tier COGS charged ───
ev AS (
  SELECT
    CAST(f.campaign_id AS STRING) AS campaign_id,
    CAST(f.keyword_id  AS STRING) AS keyword_id,
    ROUND(SUM(IF(f.date = w.last_day, f.Ads_cost,     0)), 2) AS d1_spend,
    ROUND(SUM(IF(f.date = w.last_day, f.GROSS_PROFIT, 0)), 2) AS d1_gp,
    CAST(SUM(IF(f.date = w.last_day, f.Ads_clicks, 0)) AS INT64) AS d1_clicks,
    CAST(SUM(IF(f.date = w.last_day, f.Ads_orders, 0)) AS INT64) AS d1_orders,
    ROUND(SUM(IF(f.date BETWEEN w.window_start AND w.window_end, f.Ads_cost,     0)), 2) AS w_spend,
    ROUND(SUM(IF(f.date BETWEEN w.window_start AND w.window_end, f.GROSS_PROFIT, 0)), 2) AS w_gp,
    CAST(SUM(IF(f.date BETWEEN w.window_start AND w.window_end, f.Ads_clicks, 0)) AS INT64) AS w_clicks,
    CAST(SUM(IF(f.date BETWEEN w.window_start AND w.window_end, f.Ads_orders, 0)) AS INT64) AS w_orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  CROSS JOIN winx w
  CROSS JOIN k
  WHERE f.keyword_id IS NOT NULL
    AND f.date >  DATE_SUB(w.last_day, INTERVAL k.fact_scan_days DAY)
    AND f.date <= w.last_day
  GROUP BY 1, 2
),

joined AS (
  SELECT
    p.campaign_id,
    p.keyword_id,
    p.family,
    p.campaign_name,
    p.campaign_type,
    p.campaign_state,
    p.exempt_until,
    p.exempt_reason,
    p.campaign_settled_gp_roas,
    p.campaign_settled_clicks,
    p.campaign_protected_winner,
    p.pick.ad_group_id,
    p.pick.targeting,
    p.pick.match_type,
    p.pick.current_bid,
    p.pick.launch_bid,
    p.pick.launch_bid_source,
    p.pick.launch_phase,
    p.pick.launch_decision,
    p.pick.coach_target_action,
    p.pick.coach_recommended_bid,
    p.pick.priority_score,
    g.creative_type,
    w.last_day, w.window_start, w.window_end, w.w_days, w.in_peak,
    w.occurrence_type, w.w_days_source, w.w_days_reason,
    COALESCE(e.d1_spend, 0)  AS d1_spend,
    COALESCE(e.d1_gp, 0)     AS d1_gp,
    COALESCE(e.d1_clicks, 0) AS d1_clicks,
    COALESCE(e.d1_orders, 0) AS d1_orders,
    COALESCE(e.w_spend, 0)   AS w_spend,
    COALESCE(e.w_gp, 0)      AS w_gp,
    COALESCE(e.w_clicks, 0)  AS w_clicks,
    COALESCE(e.w_orders, 0)  AS w_orders,
    -- two SUMs, never two ANY_VALUE()s
    ROUND(SAFE_DIVIDE(e.d1_gp, NULLIF(e.d1_spend, 0)), 3) AS d1_gp_roas,
    ROUND(SAFE_DIVIDE(e.w_gp,  NULLIF(e.w_spend,  0)), 3) AS w_gp_roas,
    kk.*
  FROM pop p
  CROSS JOIN winx w
  CROSS JOIN k kk
  LEFT JOIN ag g ON g.ad_group_id = p.pick.ad_group_id
  LEFT JOIN ev e ON e.campaign_id = p.campaign_id AND e.keyword_id = p.keyword_id
),

-- ─── the ladder: band -> factor -> anchor -> floor -> proposal ───
graded AS (
  SELECT
    j.*,
    -- the row's platform/house floor — FN_BID_FLOOR is the one definition (v27.104); the rule is
    -- unchanged: SP $0.20 house, SB collection/spotlight $0.10, SB video or unknown creative $0.25
    `onyga-482313.OI.FN_BID_FLOOR`(j.campaign_type, j.creative_type).bid_floor        AS bid_floor,
    `onyga-482313.OI.FN_BID_FLOOR`(j.campaign_type, j.creative_type).bid_floor_source AS bid_floor_source,
    -- the band, decided on the W-WINDOW (half-open, so no GP-ROAS lands in two)
    CASE
      WHEN j.w_spend <= 0            THEN 'NO_EVIDENCE'
      WHEN j.w_gp_roas <  j.band_trim10_hi  THEN 'LT_0.5'
      WHEN j.w_gp_roas <  j.band_trim5_hi   THEN '0.5_0.7'
      WHEN j.w_gp_roas <  j.band_improve_hi THEN '0.7_0.9'
      ELSE                                       'GE_0.9'
    END AS gp_roas_band,
    CASE
      WHEN j.w_spend <= 0                   THEN NULL
      WHEN j.w_gp_roas <  j.band_trim10_hi  THEN j.factor_trim10
      WHEN j.w_gp_roas <  j.band_trim5_hi   THEN j.factor_trim5
      ELSE NULL
    END AS trim_factor,
    -- the band sets the STEP; launch_bid is the DESTINATION, not a one-step ceiling (see header).
    COALESCE(j.current_bid, j.launch_bid) AS anchor_bid,
    CASE
      WHEN j.current_bid IS NULL                       THEN 'LAUNCH_BID (no current bid on the row — the coach idiom COALESCE(current_bid, launch_bid))'
      WHEN j.launch_bid IS NULL                        THEN 'CURRENT_BID (no launch_bid on the row)'
      WHEN j.current_bid > j.launch_bid                THEN 'CURRENT_BID, walking down to launch_bid (the bid is ABOVE the sanctioned launch bid; the band sets the step, launch_bid is the destination)'
      ELSE                                                  'CURRENT_BID (already at or under launch_bid — the destination is already met)'
    END AS anchor_source,
    COALESCE(j.launch_bid IS NOT NULL AND j.current_bid > j.launch_bid, FALSE) AS above_launch_bid,
    IF(j.w_clicks < j.thin_clicks, 'THIN', 'OK') AS evidence_grade
  FROM joined j
),

priced AS (
  SELECT
    g.*,
    -- the proposal: one band-sized step off the anchor, rounded, floored, and capped at the anchor
    -- so the ladder can never point upward.
    CASE WHEN g.trim_factor IS NULL THEN NULL ELSE
      LEAST(g.anchor_bid,
            GREATEST(CAST(CEIL(CAST(g.anchor_bid AS NUMERIC) * CAST(g.trim_factor AS NUMERIC) * 100) / 100 AS FLOAT64),
                     g.bid_floor))
    END AS proposed_bid,
    -- what the ONE-STEP ceiling reading would have proposed — published so the harder reading is
    -- one CASE away and the difference is never hidden (see header, reading 3)
    CASE WHEN g.trim_factor IS NULL OR g.launch_bid IS NULL THEN NULL ELSE
      LEAST(g.anchor_bid,
            GREATEST(CAST(CEIL(CAST(LEAST(g.anchor_bid, g.launch_bid) AS NUMERIC)
                               * CAST(g.trim_factor AS NUMERIC) * 100) / 100 AS FLOAT64),
                     g.bid_floor))
    END AS ceiling_step_bid,
    -- runs at this band's step until the bid reaches launch_bid (NULL unless it is above it)
    CASE WHEN g.trim_factor IS NULL OR NOT g.above_launch_bid THEN NULL ELSE
      CAST(CEIL(SAFE_DIVIDE(LN(SAFE_DIVIDE(g.launch_bid, g.anchor_bid)), LN(g.trim_factor))) AS INT64)
    END AS runs_to_launch_bid,
    -- did the floor stop the trim reaching its nominal size?
    CASE WHEN g.trim_factor IS NULL THEN FALSE ELSE
      CAST(CEIL(CAST(g.anchor_bid AS NUMERIC) * CAST(g.trim_factor AS NUMERIC) * 100) / 100 AS FLOAT64)
        < g.bid_floor
    END AS floor_binding
  FROM graded g
),

final AS (
  SELECT
    p.*,
    CASE
      WHEN p.gp_roas_band = 'NO_EVIDENCE' THEN 'LAUNCH_BID_HOLD_NO_EVIDENCE'
      WHEN p.gp_roas_band = 'GE_0.9'      THEN 'LAUNCH_BID_HOLD_PROFITABLE'
      WHEN p.gp_roas_band = '0.7_0.9'     THEN 'LAUNCH_BID_HOLD_IMPROVING'
      -- a trim band with no room left under the floor is a HOLD, not a fake trim
      WHEN p.proposed_bid IS NULL OR p.proposed_bid >= p.anchor_bid THEN 'LAUNCH_BID_HOLD_AT_FLOOR'
      WHEN p.gp_roas_band = 'LT_0.5'      THEN 'LAUNCH_BID_TRIM_10'
      ELSE                                     'LAUNCH_BID_TRIM_5'
    END AS ladder_action
  FROM priced p
)

SELECT
  -- ═══ identity ═══
  family,
  campaign_id,
  campaign_name,
  campaign_type,                                  -- SP | SB (drives the floor)
  campaign_state,
  ad_group_id,
  keyword_id,
  targeting,
  match_type,
  creative_type,                                  -- SB only; NULL on SP

  -- ═══ the judged window (decided in V_PEAK_WINDOW_RULE, printed here) ═══
  last_day,
  window_start,
  window_end,
  w_days                                       AS judged_window_days,
  in_peak,
  occurrence_type,
  w_days_source,
  w_days_reason,

  -- ═══ evidence: last day, then the w-window the band is taken on ═══
  d1_spend, d1_gp, d1_gp_roas, d1_clicks, d1_orders,
  w_spend,  w_gp,  w_gp_roas,  w_clicks,  w_orders,
  evidence_grade,                                 -- THIN under 3 window clicks; changes no action
  -- the campaign's SETTLED record from V_LAUNCH_EXEMPTION, carried so the short window's verdict can
  -- be read against settled evidence instead of argued about
  campaign_settled_gp_roas,
  campaign_settled_clicks,
  campaign_protected_winner,

  -- ═══ the ladder ═══
  gp_roas_band,                                   -- LT_0.5 | 0.5_0.7 | 0.7_0.9 | GE_0.9 | NO_EVIDENCE
  trim_factor,                                    -- 0.90 | 0.95 | NULL
  CAST(ROUND((1 - COALESCE(trim_factor, 1)) * 100) AS INT64) AS band_trim_pct,   -- 10 | 5 | 0
  current_bid,
  launch_bid,
  launch_bid_source,                              -- cpc | market | template | cold (read, not recomputed)
  anchor_bid,
  anchor_source,
  bid_floor,
  bid_floor_source,
  proposed_bid,
  above_launch_bid,                               -- the bid sits ABOVE the sanctioned launch bid
  runs_to_launch_bid,                             -- runs at this band's step until it gets there
  ceiling_step_bid,                               -- what the one-step ceiling reading would have said
  floor_binding,
  ROUND(SAFE_DIVIDE(proposed_bid - current_bid, NULLIF(current_bid, 0)) * 100, 1) AS bid_change_pct,
  ROUND(current_bid - COALESCE(proposed_bid, current_bid), 2) AS bid_cut_dollars,
  ladder_action,
  (ladder_action IN ('LAUNCH_BID_TRIM_10', 'LAUNCH_BID_TRIM_5')) AS is_proposal,

  -- ═══ the coach's own standing bid decision — published, never overridden ═══
  launch_phase,
  launch_decision,
  coach_target_action,
  coach_recommended_bid,
  (coach_recommended_bid IS NOT NULL
     AND proposed_bid IS NOT NULL
     AND ABS(coach_recommended_bid - proposed_bid) >= 0.01) AS conflicts_with_coach,
  priority_score,

  -- ═══ the exemption this row sits inside ═══
  exempt_until,
  exempt_reason,

  -- ═══ the reason, written here so the panel only prints it ═══
  CONCAT(
    CASE gp_roas_band
      WHEN 'NO_EVIDENCE' THEN CONCAT('no spend in the last ', CAST(w_days AS STRING),
                                     ' days (window ', CAST(window_start AS STRING), '..',
                                     CAST(window_end AS STRING), ') — nothing to judge, bid unchanged')
      WHEN 'GE_0.9'      THEN CONCAT('profitable on the ', CAST(w_days AS STRING), '-day window (',
                                     FORMAT('%.2f', w_gp_roas), '× GP-ROAS) — launch_bid ok, no action')
      WHEN '0.7_0.9'     THEN CONCAT('improving on the ', CAST(w_days AS STRING), '-day window (',
                                     FORMAT('%.2f', w_gp_roas), '× GP-ROAS, the 0.7–0.9 band) — leave it alone')
      WHEN '0.5_0.7'     THEN CONCAT(FORMAT('%.2f', w_gp_roas), '× GP-ROAS on the ',
                                     CAST(w_days AS STRING), '-day window (0.5–0.7 band) — trim the bid 5%')
      ELSE                    CONCAT(FORMAT('%.2f', w_gp_roas), '× GP-ROAS on the ',
                                     CAST(w_days AS STRING), '-day window (under 0.5) — trim the bid 10%')
    END,
    CASE
      WHEN ladder_action = 'LAUNCH_BID_HOLD_AT_FLOOR'
        THEN CONCAT(', but $', FORMAT('%.2f', current_bid), ' is already at the ',
                    bid_floor_source, ' floor ($', FORMAT('%.2f', bid_floor),
                    ') — no room to trim. The lever here is negating the bad search terms, not the bid.')
      WHEN ladder_action IN ('LAUNCH_BID_TRIM_10', 'LAUNCH_BID_TRIM_5')
        THEN CONCAT(': $', FORMAT('%.2f', current_bid), ' → $', FORMAT('%.2f', proposed_bid),
                    ' (', FORMAT('%.1f', SAFE_DIVIDE(proposed_bid - current_bid, NULLIF(current_bid, 0)) * 100), '%',
                    CASE
                      WHEN above_launch_bid
                        THEN CONCAT('; this bid is ABOVE the sanctioned launch bid $',
                                    FORMAT('%.2f', launch_bid), ', so the ladder is walking it down — ',
                                    CAST(runs_to_launch_bid AS STRING), ' more run',
                                    IF(runs_to_launch_bid = 1, '', 's'),
                                    ' at this step to reach it, rather than one ',
                                    FORMAT('%.0f', (1 - SAFE_DIVIDE(ceiling_step_bid, current_bid)) * 100),
                                    '% jump')
                      ELSE ''
                    END,
                    CASE WHEN floor_binding
                         THEN CONCAT(', held up by the ', bid_floor_source, ' floor $',
                                     FORMAT('%.2f', bid_floor), ' — the realised trim is smaller than the band')
                         ELSE '' END,
                    '). ',
                    CASE WHEN evidence_grade = 'THIN'
                         THEN CONCAT('THIN evidence: ', CAST(w_clicks AS STRING), ' click',
                                     IF(w_clicks = 1, '', 's'), ' in the window. ')
                         ELSE '' END,
                    'A bid search, not a loss-cut — the exemption still blocks every budget cut, stop and park on this campaign.')
      ELSE '.'
    END
  ) AS ladder_reason

FROM final
ORDER BY family, campaign_name, is_proposal DESC, w_spend DESC, keyword_id;
