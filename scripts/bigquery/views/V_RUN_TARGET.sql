-- V_RUN_TARGET — one row per (campaign, target) for the merged Weekly Run step-4 card. Unifies the two
-- worlds so the card reads ONE source: keywords AND auto groups (Close/Loose/Substitutes), NEW campaigns
-- AND mature. Each target carries two measure windows (row 2 = recent, row 3 = trend), and each window
-- carries the five measures the card shows: CPC · clicks · TOS% · units · net ROAS.
--
-- The two windows switch on campaign age (Ori 2026-07-18):
--   NEW (in V_LAUNCH_PHASE1, first 20 days):  row2 = last complete day · row3 = mean of the 2 days before
--   MATURE:                                    row2 = last 7 days      · row3 = last 28 days (+ peak)
-- These match the two signals the engines decide on (last-day / prior-2-day for launch; 7d / 28d for the
-- coacher), so the card and the decision agree.
--
-- Measures come from FACT_AMAZON_ADS (clicks/cost/units/gross profit/impressions); TOS% is impression-
-- weighted top_of_search_impression_share from V_TARGET_DAILY (FACT has no TOS). Bid suggestion/action is
-- joined from the right engine: T_LAUNCH_PHASE1 for new targets, T_WEEKLY_RUN_KEYWORD for mature keywords
-- (mature auto groups have no coacher verdict yet, so bid_action is NULL — they show measures only).
-- Grain: (campaign_id, keyword_id).
--
-- ############################################################################
-- # v27.62 — THE GP RULE: READ FACT_AMAZON_ADS.GROSS_PROFIT. NEVER RECOMPUTE. #
-- ############################################################################
-- (Ori 2026-08-13, found by checking the panel against Amazon.) This view used to carry TWO gross
-- profits: gp (FACT's stored GROSS_PROFIT) and gp_corr, a "corrected" one re-derived here as
--     Ads_sales - COALESCE(T_PRICE_COST_TIER.tier_cost, TOTAL_COST_PER_UNIT) * Ads_units
--   LEFT JOIN T_PRICE_COST_TIER pct ON Ads_units > 0
--     AND pct.unit_price = ROUND(SAFE_DIVIDE(Ads_sales, Ads_units), 2)
-- The "correction" WAS the corruption, and it is gone. The join looked the cost tier up by an
-- "implied unit price" of Ads_sales / Ads_units — which is NOT the product's price: Ads_sales
-- carries HALO sales of OTHER products (~79% purchased-vs-advertised divergence in this account)
-- while Ads_units does not correspond to them. PROVEN on VIDEO- BALL / 2026-08-12: implied $24.39
-- for a $13.99 product matched a ~$21.50 tier, overrode the real TOTAL_COST_PER_UNIT of $9.77, and
-- collapsed GP $229.16 -> $37.17 — a GP-ROAS of 3.69x read as 0.60x, on a campaign Amazon's own
-- console reports at $331.08 sales / $64.05 spend that day. FACT has charged tier COGS at LOAD time
-- since 2026-08-01, so re-deriving it here was redundant AND wrong. Consequence for this view:
-- r2_roas_corr / r3_roas_corr / pk_roas_corr now equal r2_roas / r3_roas / pk_roas on every row.
-- The columns stay (the cube selects them) but they no longer carry a second opinion.
-- Same fix, same day: V_LOW_STOCK_ADS (v27.61) and the other seven engine views.
--
-- ORDERING: reads the materialized T_WEEKLY_RUN_KEYWORD / T_LAUNCH_PHASE1, NOT their
-- V_ — all three are built earlier in SP_REFRESH_CUBE_TABLES, so inside the SP the data is identical.
-- Inlining V_WEEKLY_RUN_KEYWORD re-expands the whole V_ADS_COACH subtree here and blew query planning
-- ("too many subqueries", 2026-08-13) — the same failure mode T_LIFT_PROBES was created for; V_LAUNCH_PHASE1
-- was inlined TWICE (new_camp + the bid join), doubling that subtree too. Reading the T_s drops this view
-- from a plan BigQuery refused to build, to 11 leaf tables / ~148 MB.
-- Only Cube reads T_RUN_TARGET, so the T_ dependency never surfaces stale to a live consumer — and the
-- LaunchPhase1 cube + build_launch_phase1_bulksheet.py (which generates the actual uploads) keep reading
-- the live V_LAUNCH_PHASE1, unaffected.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_RUN_TARGET` AS
WITH wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
            FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
peak_dates AS (
  SELECT DISTINCT d AS date
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h, UNNEST(GENERATE_DATE_ARRAY(h.boost_start, h.cooldown_end)) d
  WHERE h.category = 'gift_season'
),
new_camp AS (SELECT DISTINCT campaign_id FROM `onyga-482313.OI.T_LAUNCH_PHASE1`),
-- current ad-group default bid — fallback ONLY when a target has no per-target bid override (e.g. auto
-- expressions running on the ad-group default). Real per-target bid always wins via COALESCE below.
ag AS (SELECT CAST(ad_group_id AS STRING) ad_group_id, ANY_VALUE(default_bid) default_bid
       FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current GROUP BY 1),
-- LAST-KNOWN bid/ad-group per target over the window — the anchor day alone misses targets whose campaign
-- paused or had a data gap on the anchor day (no V_TARGET_DAILY row → no bid, no ad_group to fall back on).
td_last AS (
  SELECT campaign_id, keyword_id,
    ARRAY_AGG(STRUCT(keyword_bid, ad_group_id, match_type) ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS l
  FROM `onyga-482313.OI.V_TARGET_DAILY`
  WHERE date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY)
  GROUP BY 1, 2
),
-- daily facts per target (last 28 days + any peak day), tagged new/mature so the window CASEs know which
-- rows to keep. tos joined per (campaign, keyword, day).
f AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id, CAST(a.keyword_id AS STRING) AS keyword_id,
    a.targeting AS target_text, UPPER(a.targeting_type) AS targeting_type, a.date,
    (nc.campaign_id IS NOT NULL) AS is_new,
    SUM(a.Ads_clicks) AS clk, SUM(a.Ads_cost) AS cost, SUM(a.Ads_units) AS units,
    -- THE GP RULE (v27.62): FACT's stored GROSS_PROFIT is the gross profit. There is no second one.
    SUM(a.GROSS_PROFIT) AS gp, SUM(a.Ads_sales) AS sales,
    -- TRUE impressions + TOS come from V_TARGET_DAILY (targeting report), NOT FACT: FACT is search-term grain
    -- and Amazon only reports impressions for terms with activity, so SUM(Ads_impressions) badly UNDERCOUNTS
    -- (e.g. 15 vs 855 → a fake 66% CTR). td is keyword-day grain (one row per group) → ANY_VALUE, not SUM.
    -- Fallback to FACT impressions when td is missing (SP data lag, or SB/video campaigns which aren't in the
    -- SP targeting report at all — those need the SB launch track for accurate impressions; FACT keeps CTR≠0).
    COALESCE(ANY_VALUE(td.impressions), SUM(a.Ads_impressions)) AS impr,
    -- gp_corr WAS a second, "corrected" gross profit that re-derived COGS here. v27.62 killed it: it
    -- is now the SAME number as gp, kept only so the *_roas_corr output columns (cube RunTarget.js
    -- r2RoasCorr / r3RoasCorr / pkRoasCorr, NewCampaignCards.tsx) keep their shape. Both roas and
    -- roas_corr therefore agree on every row now — see THE GP RULE in the header for why the
    -- "correction" was the corruption. Retire the _corr columns once the cube stops selecting them.
    SUM(a.GROSS_PROFIT) AS gp_corr,
    ANY_VALUE(COALESCE(td.tos_share,0) * td.impressions) AS tos_impr   -- TOS numerator on TRUE impressions
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN new_camp nc ON nc.campaign_id = CAST(a.campaign_id AS STRING)
  LEFT JOIN `onyga-482313.OI.V_TARGET_DAILY` td
    ON td.campaign_id = CAST(a.campaign_id AS STRING) AND td.keyword_id = CAST(a.keyword_id AS STRING) AND td.date = a.date
  WHERE a.keyword_id IS NOT NULL
    AND (a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY) OR a.date IN (SELECT date FROM peak_dates))
    AND a.date <= (SELECT d FROM wm)
  GROUP BY 1,2,3,4,5,6
),
-- window flags per daily row
w AS (
  SELECT *,
    (SELECT d FROM wm) AS anchor,
    (is_new AND date = (SELECT d FROM wm)) OR (NOT is_new AND date >= DATE_SUB((SELECT d FROM wm), INTERVAL 6 DAY))  AS in_row2,
    (is_new AND date < (SELECT d FROM wm) AND date >= DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY))
      OR (NOT is_new AND date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY)) AS in_row3,
    (date IN (SELECT date FROM peak_dates)) AS in_peak
  FROM f
),
agg AS (
  -- v27.64 (2026-08-15, found by the Phase-0 pull-twice determinism check): ANY_VALUE(target_text)
  -- coin-flipped on the keyword_id='-1' rows — the group collapses ALL of a campaign's product
  -- targets / auto clauses into ONE row, and ANY_VALUE picked a different member per pull (38 of
  -- 40 keyed mismatches between two --nouse_cache pulls; e.g. one campaign's '-1' row alternated
  -- between 'complements' and an asin=... expression, which also flips is_auto_group downstream).
  -- Same defect family as fact_oi_any_value_pairing_nondeterminism (v27.46). MIN() is the
  -- deterministic pick — for a real keyword the group has one text anyway; for the '-1' collapse
  -- any single member is equally (un)representative, so stability wins. Decision columns were
  -- byte-stable throughout (they never read target_text); this is display + is_auto_group only.
  SELECT campaign_id, keyword_id, MIN(target_text) target_text, MIN(targeting_type) targeting_type,
    ANY_VALUE(is_new) is_new, ANY_VALUE(anchor) anchor,
    -- row 2 (recent)
    SUM(IF(in_row2,clk,0)) r2_clk, SUM(IF(in_row2,cost,0)) r2_cost, SUM(IF(in_row2,units,0)) r2_units,
    SUM(IF(in_row2,gp,0)) r2_gp, SUM(IF(in_row2,gp_corr,0)) r2_gp_corr, SUM(IF(in_row2,sales,0)) r2_sales, SUM(IF(in_row2,impr,0)) r2_impr, SUM(IF(in_row2,tos_impr,0)) r2_tosimpr,
    -- row 3 (trend)
    SUM(IF(in_row3,clk,0)) r3_clk, SUM(IF(in_row3,cost,0)) r3_cost, SUM(IF(in_row3,units,0)) r3_units,
    SUM(IF(in_row3,gp,0)) r3_gp, SUM(IF(in_row3,gp_corr,0)) r3_gp_corr, SUM(IF(in_row3,sales,0)) r3_sales, SUM(IF(in_row3,impr,0)) r3_impr, SUM(IF(in_row3,tos_impr,0)) r3_tosimpr,
    -- peak (mature row 3 second value)
    SUM(IF(in_peak,clk,0)) pk_clk, SUM(IF(in_peak,cost,0)) pk_cost, SUM(IF(in_peak,units,0)) pk_units,
    SUM(IF(in_peak,gp,0)) pk_gp, SUM(IF(in_peak,gp_corr,0)) pk_gp_corr, SUM(IF(in_peak,sales,0)) pk_sales, SUM(IF(in_peak,impr,0)) pk_impr, SUM(IF(in_peak,tos_impr,0)) pk_tosimpr
  FROM w GROUP BY 1,2
),
-- 1-day launch cooldown: days since WE last uploaded a change for this target (FACT_PPC_CHANGE_LOG =
-- authoritative upload time). Mirrors V_WEEKLY_RUN_KEYWORD.last_change. A NEW target changed less than a
-- day ago is held (its suggestion suppressed) → at most one launch suggestion per target per day.
last_change AS (
  SELECT CAST(keyword_id AS STRING) AS keyword_id,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at, 'America/Los_Angeles')), DAY) AS days_since_suggestion
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE keyword_id IS NOT NULL AND CAST(keyword_id AS STRING) != ''
  GROUP BY 1
)
SELECT
  a.campaign_id, a.keyword_id, a.target_text, a.targeting_type,
  (LOWER(a.target_text) IN ('close-match','loose-match','substitutes','complements')) AS is_auto_group,
  a.is_new, a.anchor AS anchor_date,   -- the "last complete day" the measures/decisions are anchored on
  tl.l.match_type, tl.l.ad_group_id, COALESCE(tl.l.keyword_bid, ag.default_bid) AS current_bid,   -- override wins, else ad-group default
  -- unified bid suggestion + why: launch controller for NEW, coacher for MATURE keywords.
  -- (mature auto groups aren't in the coacher yet → NULL action, measures only.)
  -- 1-day launch cooldown: a NEW target changed <1 day ago is held (suggestion suppressed) so it gets at
  -- most one suggestion per day; mature keywords keep the coacher's own (3-day) cadence via mk.
  IF(a.is_new, IF(COALESCE(lc.days_since_suggestion, 99) < 1, NULL,   lp.suggested_bid), mk.recommended_bid) AS suggested_bid,
  IF(a.is_new, IF(COALESCE(lc.days_since_suggestion, 99) < 1, 'HOLD', lp.bid_action),    mk.action)          AS bid_action,
  IF(a.is_new, IF(COALESCE(lc.days_since_suggestion, 99) < 1, 'changed today — held (one launch suggestion per day)', NULL), mk.reason) AS bid_reason,
  -- days since we last uploaded a change for this target — drives the "Already applied" filter (applied = <1d, changed today)
  IF(a.is_new, lc.days_since_suggestion, mk.days_since_suggestion) AS days_since_suggestion,
  -- row 2 — spend · CPC · clicks · CTR · TOS · units · net ROAS · ACoS (ACoS = spend ÷ sales, like Amazon)
  ROUND(a.r2_cost,2) r2_spend, ROUND(SAFE_DIVIDE(a.r2_cost,NULLIF(a.r2_clk,0)),2) r2_cpc, a.r2_clk,
  ROUND(100*SAFE_DIVIDE(a.r2_clk,NULLIF(a.r2_impr,0)),1) r2_ctr,
  ROUND(100*SAFE_DIVIDE(a.r2_tosimpr,NULLIF(a.r2_impr,0)),0) r2_tos, a.r2_units,
  ROUND(SAFE_DIVIDE(a.r2_gp,NULLIF(a.r2_cost,0)),2) r2_roas,
  ROUND(SAFE_DIVIDE(a.r2_gp_corr,NULLIF(a.r2_cost,0)),2) r2_roas_corr,   -- COGS by product actually sold
  a.r2_impr,   -- raw true impressions (for exact campaign-level CTR/TOS aggregation)
  ROUND(100*SAFE_DIVIDE(a.r2_cost,NULLIF(a.r2_sales,0)),0) r2_acos,
  -- row 3
  ROUND(a.r3_cost,2) r3_spend, ROUND(SAFE_DIVIDE(a.r3_cost,NULLIF(a.r3_clk,0)),2) r3_cpc, a.r3_clk,
  ROUND(100*SAFE_DIVIDE(a.r3_clk,NULLIF(a.r3_impr,0)),1) r3_ctr,
  ROUND(100*SAFE_DIVIDE(a.r3_tosimpr,NULLIF(a.r3_impr,0)),0) r3_tos, a.r3_units,
  ROUND(SAFE_DIVIDE(a.r3_gp,NULLIF(a.r3_cost,0)),2) r3_roas,
  ROUND(SAFE_DIVIDE(a.r3_gp_corr,NULLIF(a.r3_cost,0)),2) r3_roas_corr,
  a.r3_impr,
  ROUND(100*SAFE_DIVIDE(a.r3_cost,NULLIF(a.r3_sales,0)),0) r3_acos,
  -- peak (mature only)
  ROUND(a.pk_cost,2) pk_spend, ROUND(SAFE_DIVIDE(a.pk_cost,NULLIF(a.pk_clk,0)),2) pk_cpc, a.pk_clk,
  ROUND(100*SAFE_DIVIDE(a.pk_clk,NULLIF(a.pk_impr,0)),1) pk_ctr,
  ROUND(100*SAFE_DIVIDE(a.pk_tosimpr,NULLIF(a.pk_impr,0)),0) pk_tos, a.pk_units,
  ROUND(SAFE_DIVIDE(a.pk_gp,NULLIF(a.pk_cost,0)),2) pk_roas,
  ROUND(SAFE_DIVIDE(a.pk_gp_corr,NULLIF(a.pk_cost,0)),2) pk_roas_corr,
  ROUND(100*SAFE_DIVIDE(a.pk_cost,NULLIF(a.pk_sales,0)),0) pk_acos
FROM agg a
LEFT JOIN td_last tl ON tl.campaign_id = a.campaign_id AND tl.keyword_id = a.keyword_id
LEFT JOIN ag ON ag.ad_group_id = tl.l.ad_group_id
LEFT JOIN `onyga-482313.OI.T_LAUNCH_PHASE1` lp
  ON lp.campaign_id = a.campaign_id AND lp.keyword_id = a.keyword_id
LEFT JOIN `onyga-482313.OI.T_WEEKLY_RUN_KEYWORD` mk   -- T_, not V_ — see ORDERING note in header
  ON mk.keyword_id = a.keyword_id
LEFT JOIN last_change lc
  ON lc.keyword_id = a.keyword_id;
