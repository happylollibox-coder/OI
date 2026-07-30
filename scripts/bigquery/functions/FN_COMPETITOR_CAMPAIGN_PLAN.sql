-- FN_COMPETITOR_CAMPAIGN_PLAN(win_start, win_end, peak_only) — competitor ASINs, grouped into
-- ready-to-create campaigns.
--
-- FN_COMPETITOR_CANDIDATE answers "which competitor ASINs deserve a deliberate target?". This
-- answers the next question: "what campaigns do I actually open, and at what bid?" It is the write
-- side of the same evidence — /api/competitor-campaign-plan and the DoPage bulksheet read it.
--
-- GRAIN: one row per (parent_name × winner_variation × tier_code × chunk_index × candidate_asin).
-- Every row carries its group's campaign fields, so a client can either list ASINs or GROUP BY
-- campaign_key without a second query.
--
-- ── WHY THIS GROUPING ────────────────────────────────────────────────────────────────────────
-- winner_variation × bid tier, capped at 10 ASINs per campaign.
--   • VARIATION, because a campaign advertises a product. The SB video / spotlight creative shows
--     one specific variation, and even on SP the ad that wins a competitor's page is the variation
--     that already converted there. winner_variation = the variation that actually SOLD on that
--     ASIN's placement (see FN_COMPETITOR_CANDIDATE.win_pick — deterministic, units-first).
--   • TIER, because a campaign shares ONE bid. Mixing an ASIN that breaks even at $0.31 with one
--     that breaks even at $2.90 makes every possible bid wrong for someone. Bands come from
--     DE_COMPETITOR_BID_TIER so they are tunable without a deploy.
--   • MAX 10 (DE_COACH_THRESHOLDS.COMPETITOR_MAX_ASINS_PER_CAMPAIGN), chunked by target_cpc DESC
--     so the highest-value ASINs land together and chunk membership is STABLE across refreshes.
--     Stability depends on a deterministic winner_variation — the ANY_VALUE that used to pick it
--     was not, and reshuffled the whole plan run to run. Fixed 2026-07-23 in FN_COMPETITOR_CANDIDATE.
--
-- ── DECISION: EXISTING WINNERS ARE **EXCLUDED** ──────────────────────────────────────────────
-- FN_COVERAGE_COMPETITOR_TARGET.is_winner ASINs (already targeted, net_roas >= 1) are NOT folded
-- into this plan. Reasons, in order of weight:
--   1. Opening a new campaign against an ASIN you already target makes your two campaigns bid
--      against each other on the same placement — you raise your own CPC and pay for it twice.
--   2. Rebalancing an existing target is a BID UPDATE, not a campaign create. That path already
--      exists end-to-end (V_ADS_COACH -> INCREASE_BID / REDUCE_BID -> Do queue -> bulksheet Update
--      rows), and its rows carry the keyword/target ids an Update needs — which this plan does not
--      have, because FN_COVERAGE_COMPETITOR_TARGET emits no campaign_id or target id.
--   3. FN_COMPETITOR_CANDIDATE already excludes already-targeted ASINs by design; re-admitting
--      them here would fight that exclusion rather than extend it.
-- Existing winners stay visible where they belong: the "Targeted now" list in CompetitorPanel,
-- which shows each one's current cpc against its target_cpc — exactly the rebalance signal.
-- If a proven winner ever needs MOVING into a properly-tiered campaign, that is a pause-then-create
-- pair, not a create; deliberately out of scope here.
--
-- ── DECISION: suggested_bid = group MIN(target_cpc) ──────────────────────────────────────────
-- target_cpc is the CPC at which an ASIN lands EXACTLY on the profit floor, so bidding above it
-- loses money on that ASIN. One bid covers the group, therefore the only bid at which EVERY member
-- still clears the floor is the group minimum. MEDIAN or AVG would by construction leave ~half the
-- campaign bidding above its own break-even — the group's weakest members bleed while the strongest
-- subsidise them, and the campaign's blended ROAS hides it. MIN forgoes some volume on the strongest
-- ASIN instead, which is the recoverable mistake; the tier + 10-ASIN chunking is what keeps that
-- forgone volume small (in-band spread is ~1.2-1.35x). group_med/avg/max_target_cpc are emitted
-- alongside so the trade-off is inspectable rather than asserted.
--
-- suggested_bid is then clamped into the COMPETITOR template's [bid_min, bid_max] (bid_max = 2.00,
-- matching the account's BID_CAP_SUGGESTION ceiling). suggested_bid_raw + bid_capped expose when
-- the clamp bound, so a $3.86-worth target reads as "capped", never as "worth $2".
--
-- ── PROJECTIONS ──────────────────────────────────────────────────────────────────────────────
-- proj_* answer "if these ASINs repeat their window behaviour at the new bid":
--   proj_spend  = suggested_bid × window clicks
--   proj_margin = SUM(net_roas × cost) — algebraically SUM(units) × family_gp, i.e. the SAME
--                 gross-profit basis as net_roas everywhere else, with no extra joins.
--   proj_net_roas = proj_margin / proj_spend.
-- Directional: click volume at a different bid is not guaranteed. Never treat as a forecast.
--
-- ── NAMING ───────────────────────────────────────────────────────────────────────────────────
-- Derived from REAL campaign names in V_SRC_AmazonAds_campaign_history, not invented. The live
-- convention is {PREFIX}-{FORMAT}/{TARGETING} (qualifiers) — e.g. ME-SP/AUTO (Mint),
-- BOX-SP/PT (Product Defense), ME-SP/PT (Competitors), BOX-VIDEO/COMPETE (Copycat, Blue).
-- Product targeting is /PT and the "Competitors" qualifier marks conquest (Ori 2026-07-23: name
-- it "Competitors", not "Conquest"), so:
--   SP : {PREFIX}-SP/PT (Competitors, {Variation}, {Tier}{n})     e.g. ME-SP/PT (Competitors, Mint, A1)
--   SB : {PREFIX}-VIDEO/PT (Competitors, {Variation}, {Tier}{n})
-- ('/' not '\' — one legacy campaign uses a backslash, every other one uses a slash.)
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_COMPETITOR_CAMPAIGN_PLAN`(win_start DATE, win_end DATE, peak_only BOOL) AS (
WITH
knob AS (
  SELECT COALESCE(
    MAX(IF(strategy_id = 'COMPETITOR', CAST(threshold_value AS INT64), NULL)),
    MAX(IF(strategy_id = 'GLOBAL',     CAST(threshold_value AS INT64), NULL)),
    10                                            -- last-resort default if the knob row is missing
  ) AS max_per_campaign
  FROM `onyga-482313`.OI.DE_COACH_THRESHOLDS
  WHERE threshold_key = 'COMPETITOR_MAX_ASINS_PER_CAMPAIGN'
),
tmpl AS (   -- COMPETITOR campaign defaults; no hardcoded budgets/bid bounds anywhere downstream
  SELECT
    MAX(IF(ad_format = 'SP', bid_min, NULL))      AS sp_bid_min,
    MAX(IF(ad_format = 'SP', bid_max, NULL))      AS sp_bid_max,
    MAX(IF(ad_format = 'SP', daily_budget, NULL)) AS sp_daily_budget,
    MAX(IF(ad_format = 'SP', product_page_pct, NULL)) AS sp_product_page_pct,
    MAX(IF(ad_format = 'SB_VIDEO', bid_min, NULL))      AS sb_bid_min,
    MAX(IF(ad_format = 'SB_VIDEO', bid_max, NULL))      AS sb_bid_max,
    MAX(IF(ad_format = 'SB_VIDEO', daily_budget, NULL)) AS sb_daily_budget
  FROM `onyga-482313`.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE
  WHERE strategy_id = 'COMPETITOR'
),
-- Promotion-worthy candidates only. target_cpc IS NOT NULL is implied by is_candidate's >=10-click
-- gate, but stated so a future change to either rule can't silently admit un-priceable rows —
-- a NULL target_cpc has no tier and no bid.
cand AS (
  SELECT parent_name, candidate_asin, found_in, winner_variation, winner_asin,
         clicks, cost, cpc, units, net_roas, target_cpc
  FROM `onyga-482313`.OI.FN_COMPETITOR_CANDIDATE(win_start, win_end, peak_only)
  WHERE is_candidate
    AND target_cpc IS NOT NULL
    AND winner_variation IS NOT NULL   -- ungrouped ASINs would land in a nameless campaign
),
-- Band assignment. Bounds: min inclusive, max EXCLUSIVE, NULL = open end.
tiered AS (
  SELECT c.*, t.tier_code, t.tier_label, t.sort_order AS tier_sort
  FROM cand c
  JOIN `onyga-482313`.OI.DE_COMPETITOR_BID_TIER t
    ON (t.min_target_cpc IS NULL OR c.target_cpc >= t.min_target_cpc)
   AND (t.max_target_cpc IS NULL OR c.target_cpc <  t.max_target_cpc)
),
-- Variation label, lifted ahead of chunking (grp_named recomputes the same expression for the
-- campaign name) so the plan can match a group to the campaigns that ALREADY carry its targets.
labelled AS (
  SELECT t.*,
    COALESCE(NULLIF(TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(t.winner_variation, r'(?i)\s*\b' || t.parent_name || r'\b\s*', ' '),
      r'(?i)^\s*(in|the)\b\s*|\s*\b(in|the)\s*$', '')), ''), t.winner_variation) AS var_label
  FROM tiered t
),
-- How many targets this (variation × tier) ALREADY holds across its live campaigns.
-- The ≤10 cap is per CAMPAIGN, and an existing campaign is usually part-full, so chunking from
-- zero silently pushes it over: A1 held 7 configured targets and the plan queued 5 more, i.e. 12
-- (Ori 2026-07-24 — "are you checking campaigns wont be greater than 10 keywords after adding the
-- new ones"). Counted from the CONFIG mirror, not FACT, so targets created minutes ago count;
-- ARCHIVED excluded because a retired target frees its slot.
-- Assumes campaigns are packed densely from chunk 1 upward, which is how this function creates them.
existing_slots AS (
  SELECT parent_name, var_label, tier_code, COUNT(*) AS n_existing
  FROM (
    SELECT nr.parent_name,
      REGEXP_EXTRACT(nr.campaign_name, r'\(Competitors, ([^,]+), [A-Z]\d+\)')  AS var_label,
      REGEXP_EXTRACT(nr.campaign_name, r'\(Competitors, [^,]+, ([A-Z])\d+\)')  AS tier_code,
      k.keyword_id
    FROM `onyga-482313`.OI.V_SRC_AmazonAds_keyword k
    JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE_BY_NAME nr
      ON nr.campaign_id = CAST(k.campaign_id AS STRING)
    WHERE nr.strategy_category = 'COMPETITOR'
      AND REGEXP_CONTAINS(LOWER(k.keyword_text), r'^asin')
      AND UPPER(COALESCE(k.state, '')) != 'ARCHIVED'
      AND REGEXP_CONTAINS(nr.campaign_name, r'\(Competitors, [^,]+, [A-Z]\d+\)')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY k.keyword_id ORDER BY k.date DESC) = 1
  )
  WHERE var_label IS NOT NULL AND tier_code IS NOT NULL
  GROUP BY 1, 2, 3
),
-- Deterministic chunking: richest ASINs first, fully-ordered tiebreak so membership is reproducible.
-- Offset by what the group already holds, so a new ASIN fills the remaining seats of the existing
-- campaign and only then spills into the next one.
chunked AS (
  SELECT l.*,
    DIV(ROW_NUMBER() OVER (
          PARTITION BY l.parent_name, l.winner_variation, l.tier_code
          ORDER BY l.target_cpc DESC, l.clicks DESC, l.candidate_asin
        ) - 1 + COALESCE(es.n_existing, 0), (SELECT max_per_campaign FROM knob)) AS chunk_index
  FROM labelled l
  LEFT JOIN existing_slots es
    ON  es.parent_name = l.parent_name
    AND es.var_label   = l.var_label
    AND es.tier_code   = l.tier_code
),
-- Group economics. Aggregated in its OWN subquery layer and joined back — never filtered by an
-- alias that shadows a raw column (SUM(cost) AS cost then HAVING cost > 0 reads as SUM(SUM(cost));
-- see the sb_cost CTE in FN_COVERAGE_SB).
grp AS (
  SELECT parent_name, winner_variation, tier_code, chunk_index,
    COUNT(*)                    AS n_asins,
    MIN(target_cpc)             AS g_min_tcpc,
    MAX(target_cpc)             AS g_max_tcpc,
    AVG(target_cpc)             AS g_avg_tcpc,
    APPROX_QUANTILES(target_cpc, 2)[OFFSET(1)] AS g_med_tcpc,
    SUM(clicks)                 AS g_clicks,
    SUM(cost)                   AS g_cost,
    SUM(units)                  AS g_units,
    SUM(net_roas * cost)        AS g_margin,     -- = SUM(units) x family_gp
    ANY_VALUE(winner_asin)      AS g_winner_asin -- constant within a variation
  FROM chunked
  GROUP BY 1, 2, 3, 4
),
-- Family -> campaign-name prefix. The live account uses short product codes, not family names
-- (BOX not "Lollibox"); this is the same map DoPage applies to PORTFOLIO_MAP, moved into SQL so
-- React never decides a campaign name.
grp_named AS (
  SELECT g.*,
    CASE g.parent_name
      WHEN 'Lollibox'  THEN 'BOX'
      WHEN 'LolliME'   THEN 'ME'
      WHEN 'LolliBall' THEN 'BALL'
      WHEN 'Bottle'    THEN 'BOTTLE'
      WHEN 'Fresh'     THEN 'FRESH'
      WHEN 'Bunny'     THEN 'BUNNY'
      ELSE UPPER(g.parent_name)
    END AS prefix,
    -- "Mint LolliME" -> "Mint"; "Fresh in Blue" -> "Blue"; "Truth Or Dare" -> unchanged.
    -- Strip the family token, then any orphaned leading/trailing "in"/"the"; fall back to the full
    -- short name when stripping leaves nothing (a variation named exactly like its family).
    COALESCE(NULLIF(TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(g.winner_variation, r'(?i)\s*\b' || g.parent_name || r'\b\s*', ' '),
      r'(?i)^\s*(in|the)\b\s*|\s*\b(in|the)\s*$', '')), ''), g.winner_variation) AS var_label
  FROM grp g
),
grp_final AS (
  SELECT n.*,
    CONCAT(n.tier_code, CAST(n.chunk_index + 1 AS STRING)) AS group_code,
    LEAST(COALESCE(t.sp_bid_max, n.g_min_tcpc),
          GREATEST(COALESCE(t.sp_bid_min, 0), n.g_min_tcpc)) AS sp_bid,
    LEAST(COALESCE(t.sb_bid_max, n.g_min_tcpc),
          GREATEST(COALESCE(t.sb_bid_min, 0), n.g_min_tcpc)) AS sb_bid,
    t.sp_daily_budget, t.sp_product_page_pct, t.sb_daily_budget
  FROM grp_named n CROSS JOIN tmpl t
)
SELECT
  c.parent_name,
  c.winner_variation,
  g.g_winner_asin                                     AS winner_asin,
  g.var_label                                         AS variation_label,
  c.tier_code,
  c.tier_label,
  c.tier_sort,
  c.chunk_index,
  g.group_code,
  -- Stable identity for a planned campaign. Survives refreshes as long as the inputs do, so the
  -- UI and the Do queue can dedupe on it.
  CONCAT('COMPETITOR|', c.parent_name, '|', c.winner_variation, '|', c.tier_code, '|',
         CAST(c.chunk_index AS STRING))               AS campaign_key,
  CONCAT(g.prefix, '-SP/PT (Competitors, ', g.var_label, ', ', g.group_code, ')')     AS campaign_name,
  CONCAT(g.prefix, '-VIDEO/PT (Competitors, ', g.var_label, ', ', g.group_code, ')')  AS sb_campaign_name,
  CONCAT(g.prefix, ' - Competitors ', g.var_label, ' ', g.group_code)                 AS ad_group_name,
  g.n_asins,
  ROUND(g.sp_bid, 2)                                  AS suggested_bid,
  ROUND(g.sb_bid, 2)                                  AS suggested_bid_sb,
  ROUND(g.g_min_tcpc, 2)                              AS suggested_bid_raw,
  (g.g_min_tcpc > g.sp_bid + 1e-9)                    AS bid_capped,
  ROUND(g.g_med_tcpc, 2)                              AS group_med_target_cpc,
  ROUND(g.g_avg_tcpc, 2)                              AS group_avg_target_cpc,
  ROUND(g.g_max_tcpc, 2)                              AS group_max_target_cpc,
  g.sp_daily_budget                                   AS daily_budget,
  g.sp_product_page_pct                               AS product_page_pct,
  g.sb_daily_budget                                   AS daily_budget_sb,
  g.g_clicks                                          AS group_clicks,
  ROUND(g.g_cost, 2)                                  AS group_window_cost,
  g.g_units                                           AS group_units,
  ROUND(g.sp_bid * g.g_clicks, 2)                     AS proj_spend,
  ROUND(g.g_margin, 2)                                AS proj_margin,
  ROUND(SAFE_DIVIDE(g.g_margin, NULLIF(g.sp_bid * g.g_clicks, 0)), 2) AS proj_net_roas,
  -- ── per-ASIN columns ──
  c.candidate_asin,
  c.found_in,
  c.clicks,
  c.cost,
  c.cpc,
  c.units,
  c.net_roas,
  c.target_cpc,
  ROW_NUMBER() OVER (PARTITION BY c.parent_name, c.winner_variation, c.tier_code, c.chunk_index
                     ORDER BY c.target_cpc DESC, c.clicks DESC, c.candidate_asin) AS asin_rank,
  CONCAT('COMPETITOR|', c.parent_name)                AS cell_key
FROM chunked c
JOIN grp_final g
  ON  g.parent_name      = c.parent_name
  AND g.winner_variation = c.winner_variation
  AND g.tier_code        = c.tier_code
  AND g.chunk_index      = c.chunk_index
);
