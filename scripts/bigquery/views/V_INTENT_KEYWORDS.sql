-- =============================================
-- V_INTENT_KEYWORDS
-- Terms matched to intent themes, ranked within (family x intent), top-10 flagged,
-- with the ads money signal and the relevance decision for that (family x intent).
-- Grain: parent_name x intent_key x query_text  (research is family-grain, and campaigns
-- are family-grain too — only AUTO is per product. See architecture/INTENT_CAMPAIGN_MODEL.md).
--
-- Match rule (DE_INTENT_THEMES): a term matches when ALL non-null match_* fields match (AND).
-- match_keyword_regex is a REGEXP_CONTAINS over LOWER(query_text); the rest are equality
-- against the same-named FACT_RESEARCH_RANKED column.
--
-- SPECIFICITY ROUTING (Ori 2026-07-16) — one term belongs to exactly ONE intent.
-- Compounds are subsets by construction, so without this `gift` (a bare \bgifts?\b regex)
-- swallows everything: it shared 1201 terms with tween-gift, 738 with birthday, 680 with
-- gift-sets. The same keyword would then seed several campaigns that bid against each other.
--   specificity = number of non-null match_* conditions
--                 gift(1) < birthday-gift(2) < tween-birthday-gift(3)
--   For each (parent_name, query_text) the MOST SPECIFIC matching intent wins; ties break on
--   priority ASC then intent_key. "9 year old girl birthday gifts" -> birthday-gift, and it
--   leaves both `birthday` and `gift`. "birthday party decorations" (no gift) stays in
--   `birthday`; "gifts for girls" (no occasion) stays in `gift`.
-- Everything downstream (top-10, ads money, relevance) is computed on the PRIMARY assignment.
--
-- Ranking (Ori 2026-07-16): top 10 per (parent_name, intent_key) by EFFECTIVE_RANK.
-- V_RESEARCH_RANKED computes:  rank = 0 when (holiday IS NOT NULL AND NOT is_holiday_active),
--                              else ROUND(AVG(overall_fit, purchase_rank)).
-- So out of season EVERY holiday term is rank 0 and ordering by rank silently fell through to
-- the demand tie-break — LolliME/easter surfaced "easter candy" (143K demand, overall_fit 0)
-- at #1 while "easter gifts for girls" (fit 30, 2.1K demand) sat 10th. Ordering by overall_fit
-- alone over-corrected the other way (picking fit-100 terms with 1 weekly purchase).
-- effective_rank rebuilds the SAME formula minus the holiday gate, so a seasonal term gets the
-- rank it would have in season — blending fit AND demand, which is what rank means everywhere
-- else. GENERIC terms keep their native rank (identical formula, gate never fires).
-- TIME_BASED intents carry their season window from DIM_US_HOLIDAYS via holiday_name
-- (boost_start = campaign start, cooldown_end = pause; recurs yearly).
--
-- RELEVANCE (is_relevant) — first rule that applies wins:
--   1. MANUAL OVERRIDE  DE_FAMILY_INTENT_OVERRIDE.force_relevant, per (family x intent).
--      DE_INTENT_THEMES.is_active is global and can't say "school is wrong for LolliME but
--      fine for Lollibox" — this can.
--   (No TIME_BASED special case any more.) Seasonal used to be unconditionally relevant
--   because it could not be judged: rank was zeroed off-season and a 90d ads read was noise.
--   Both are fixed — effective_rank makes seasonal rankable, and the season window makes it
--   measurable — so seasonal now runs the SAME rules as everything else:
--     * profit rules apply (Bottle/christmas-gift = 0.0x on 249 clicks across a whole
--       Christmas -> provably dead; Lollibox/easter = 2.07x on $2,977 -> provably good);
--     * UNTESTED seasonal is NOT penalised for having no history — the profit gate only fires
--       at >= CONCLUSIVE_CLICKS, so it falls through to the fit gate and is judged on fit
--       alone (Ori 2026-07-16: "keep untested season on but use fit to determine if it may
--       fit"). That keeps Bunny/LolliBall's never-run christmas-gift (eff_rank 80) and drops
--       halloween (eff_rank 33, fit 10, 474 demand, and no pause date).
--   3. PROFIT GATE      drop when the intent is CONCLUSIVE and HOPELESS:
--                       ads_clicks >= CONCLUSIVE_CLICKS (100) AND ads_net_roas < HOPELESS_ROAS (0.5).
--                       Rank is a market-FIT signal, not a profit one — LolliME/school clears
--                       rank 63 yet returns 0.27x on $358 over 613 clicks (77 clicks/sale).
--                       The floor is 0.5, NOT breakeven 1.0 (Ori 2026-07-16): a flat <1.0 cut
--                       left Fresh with ZERO intents — its whole book is marginal (0.66-0.92),
--                       which is a bid/price/margin problem to FIX, not an intent to delete.
--                       0.5 kills only the genuinely dead (Bunny/keychain 0.13, LolliBall/
--                       birthday 0.16, LolliME/school 0.27) and matches the GUARDIAN floors,
--                       which are already context-dependent (1.1 / SEASONAL 0.7 / NEW_LAUNCH 0.5).
--                       Untested intents (< 100 clicks) are NOT dropped; they fall through to:
--   4. PROVEN RESCUE    keep when CONCLUSIVE and PROFITABLE: ads_clicks >= CONCLUSIVE_CLICKS
--                       (100) AND ads_net_roas >= PROVEN_ROAS (1.0) — even if the fit gate
--                       would fail it. Money beats fit in BOTH directions: rank is only a
--                       market-fit proxy, so a proven earner must not be dropped for a low
--                       score. Lollibox/tween-birthday-gift = rank 55 (fails fit) but
--                       $1,189 / 1,963 clicks / 1.48x — a money-maker the fit gate killed.
--   5. FIT GATE         family_best_effective_rank >= RANK_GATE (60). Uses EFFECTIVE rank so
--                       seasonal is judged on real fit+demand rather than a season-zeroed 0.
--                       (Identical to rank for everything else — same formula, gate never
--                       fires.) rank>=75 was too strict (Fresh cleared ZERO intents).
-- Thresholds are documented constants below — tune here.
--
-- ADS MEASUREMENT WINDOW (Ori 2026-07-16) — per intent, NOT a flat 90d:
--   GENERIC    -> last 90 days.
--   TIME_BASED -> that holiday's LAST STARTED season (DIM_US_HOLIDAYS boost_start ->
--                 cooldown_end of the most recent occurrence that has begun). A 90d window is
--                 meaningless for a seasonal intent out of season: in July, Easter's 90d
--                 lookback (Apr-Jul) caught $1.21 / 5 clicks / -5.21x, while the real Easter
--                 2026 season was 2026-02-16 -> 2026-04-10. You must judge a holiday on the
--                 last time that holiday actually happened.
--   ads_window_start/ads_window_end expose the window used.
--   OFF-PEAK FALLBACK (Ori 2026-07-16): a GENERIC intent with NO data in its 90d window falls
--   back to the last 12 MONTHS but only on OFF-PEAK dates — every DIM_US_HOLIDAYS
--   boost->cooldown range is excluded, so a Christmas/Easter spike can't inflate what is
--   supposed to be a non-peak baseline. ads_window_* + ads_used_fallback expose which ran.
-- ads_* are measured over ALL of the intent's matched terms for the family (not just top-10).
-- Per-TERM money (term_spend / term_clicks / term_net_roas) uses the same window.
--
-- AD FORMAT SPLIT (Ori 2026-07-16): blended net ROAS hides large gaps — SB video runs 3.55x at
-- top-of-search vs 1.80x elsewhere. ads_{sp,sbv,sbc}_* break the money out by SP / SB_VIDEO /
-- SB_COLLECTION (creative_type via the ad_group join, same derivation as V_WEEKLY_CELL_NET).
--
-- *** THE GATES JUDGE ON SP MONEY ONLY (Ori 2026-07-16). ***
-- An intent IS its SP campaign — Exact/Broad/Phrase/Competitor are Sponsored Products. SB Video
-- and SB Collection are a SEPARATE campaign in the brand lane (Brand Spotlight) and must be
-- judged there, not allowed to prop up or drag down an SP intent. Blending them was masking
-- both directions: LolliME/tween-christmas-gift blends to 0.94 (survives) while its SP side is
-- 0.40 (hopeless) and its SB Video is 1.25 (fine) — three different verdicts in one number.
-- ads_spend / ads_net_roas remain the BLENDED figures for reference; ads_sp_* drive relevance.
--   NOTE: `SB_STORE` is NOT a format — landing_page_type is STORE for ~all SB (video AND
--   collection). The real split is BRAND_VIDEO vs PRODUCT_COLLECTION (the store-spotlight style).
--   NOTE: PLACEMENT (top-of-search vs rest-of-page) is NOT available at search-term grain —
--   FACT_AMAZON_ADS.placement_type only has Search_Results / Product_Page. TOP_OF_SEARCH comes
--   from the placement report, whose grain is campaign x placement and carries no search_term.
--   So placement stays a per-campaign bid-adjustment lever (see Placement § in the SOP).
-- SOP: architecture/INTENT_CAMPAIGN_MODEL.md §A.2b / §A.3
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313`.OI.V_INTENT_KEYWORDS AS

WITH
-- Own-brand terms to drop before intents are built (see BRAND EXCLUSION note in `matched`).
-- Built as an INNER JOIN on a STRPOS predicate, then anti-joined by EQUALITY in `matched`:
-- a correlated NOT EXISTS on STRPOS is rejected by BigQuery ("ANTISEMI JOIN needs an equality").
brand_terms AS (
  SELECT DISTINCT LOWER(r.query_text) AS query_text
  FROM `onyga-482313.OI.FACT_RESEARCH_RANKED` r
  JOIN `onyga-482313.OI.DIM_BRAND_PHRASES` bp
    ON STRPOS(LOWER(r.query_text), LOWER(bp.phrase)) > 0
),
matched AS (
  SELECT
    r.parent_name,
    t.intent_key,
    t.label,
    t.intent_type,
    t.holiday_name,
    t.cross_family,
    t.priority,
    r.query_text,
    r.rank,
    r.overall_fit,
    r.purchase_rank,
    r.weekly_market_purchases,
    -- rank as it would be if the holiday gate never fired (same formula as V_RESEARCH_RANKED)
    ROUND(SAFE_DIVIDE(
      COALESCE(r.overall_fit, 0) + COALESCE(r.purchase_rank, 0),
      NULLIF(IF(r.overall_fit IS NOT NULL, 1, 0) + IF(r.purchase_rank IS NOT NULL, 1, 0), 0)
    )) AS effective_rank,
    -- how many conditions this intent pins down — more = more specific
    ( CASE WHEN t.match_occasion      IS NOT NULL THEN 1 ELSE 0 END
    + CASE WHEN t.match_holiday       IS NOT NULL THEN 1 ELSE 0 END
    + CASE WHEN t.match_product_type  IS NOT NULL THEN 1 ELSE 0 END
    + CASE WHEN t.match_age_group     IS NOT NULL THEN 1 ELSE 0 END
    + CASE WHEN t.match_keyword_regex IS NOT NULL THEN 1 ELSE 0 END ) AS specificity
  FROM `onyga-482313.OI.FACT_RESEARCH_RANKED` r
  JOIN `onyga-482313.OI.DE_INTENT_THEMES` t
    ON t.is_active
   AND (t.match_occasion     IS NULL OR r.occasion     = t.match_occasion)
   AND (t.match_holiday      IS NULL OR r.holiday      = t.match_holiday)
   AND (t.match_product_type IS NULL OR r.product_type = t.match_product_type)
   AND (t.match_age_group    IS NULL OR r.age_group    = t.match_age_group)
   AND (t.match_keyword_regex IS NULL
        OR REGEXP_CONTAINS(LOWER(r.query_text), t.match_keyword_regex))
  LEFT JOIN brand_terms bt ON bt.query_text = LOWER(r.query_text)
  WHERE r.query_text != 'OTHER'
    -- real demand only: rank on a term with no market purchases is inflated by seg_fit alone
    AND COALESCE(r.weekly_market_purchases, 0) > 0
    -- TERM FIT FLOOR (Ori 2026-07-16): overall_fit = 0 means the term is not relevant to this
    -- family at all — it must never enter a campaign. Without this, effective_rank averages
    -- fit with purchase_rank, so a fit-0 term rides in on pure volume: LolliME/easter pulled
    -- "easter candy" (fit 0, 143K demand -> effective_rank 50) into a journal-kit campaign.
    -- Removes 136/792 (17%) of keyword slots; starves no GENERIC intent.
    AND COALESCE(r.overall_fit, 0) > 0
    -- BRAND EXCLUSION (Ori 2026-07-21): own-brand searches belong to Brand Defense, NOT to
    -- generic/competitive intent campaigns — an intent is Exact/Broad/Phrase/Competitor SP, and
    -- bidding on your own name there just pays for organic traffic + fights Defense. Brand terms
    -- were leaking into themes (Gift Sets carried "purple lollibox", "white lollibox", "happy lolli
    -- care package 12 year old girl"). `brand_terms` (above) = every research term containing a
    -- DIM_BRAND_PHRASES phrase; those phrases all carry a brand root (lolli/lollime/lollibox/
    -- happy lolli, per SP_ACCUMULATE_BRAND_PHRASES) so the match is unambiguously own-brand and
    -- can't swallow a generic term. Anti-join is by equality (BigQuery rejects a STRPOS NOT EXISTS).
    AND bt.query_text IS NULL
),

-- One term -> one intent: keep only the most specific matching intent per (family, term).
primary_matched AS (
  SELECT * EXCEPT(pr) FROM (
    SELECT m.*,
      ROW_NUMBER() OVER (
        PARTITION BY m.parent_name, m.query_text
        ORDER BY m.specificity DESC, m.priority ASC, m.intent_key
      ) AS pr
    FROM matched m
  ) WHERE pr = 1
),

-- Season window for TIME_BASED intents: the CURRENT-or-NEXT occurrence of the holiday.
-- NOTE: some holidays have a NULL cooldown_end in the live curated DIM_US_HOLIDAYS
-- (Halloween, as of 2026-07) — COALESCE to holiday_date so a NULL can't drag the pick
-- back to a past occurrence. season_end stays NULL there: a real data gap, surfaced not faked.
season AS (
  SELECT holiday_name, boost_start, cooldown_end, peak_start
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY holiday_name
    ORDER BY
      IF(COALESCE(cooldown_end, holiday_date) >= CURRENT_DATE(), 0, 1),
      COALESCE(cooldown_end, holiday_date)
  ) = 1
),

-- The LAST STARTED occurrence of each holiday — the only fair window to judge a seasonal
-- intent on. COALESCE(cooldown_end, holiday_date) because Halloween has a NULL cooldown_end.
last_season AS (
  SELECT holiday_name, boost_start AS win_start,
         COALESCE(cooldown_end, holiday_date) AS win_end
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE boost_start <= CURRENT_DATE()
  QUALIFY ROW_NUMBER() OVER (PARTITION BY holiday_name ORDER BY boost_start DESC) = 1
),

-- Measurement window per intent: seasonal -> its last season; generic -> last 90d.
intent_window AS (
  SELECT t.intent_key,
    t.intent_type,
    IF(t.intent_type = 'TIME_BASED', ls.win_start, DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)) AS win_start,
    IF(t.intent_type = 'TIME_BASED', ls.win_end,   CURRENT_DATE()) AS win_end
  FROM `onyga-482313.OI.DE_INTENT_THEMES` t
  LEFT JOIN last_season ls ON ls.holiday_name = t.holiday_name
),

-- SB ad-group -> creative_type. Same derivation as V_WEEKLY_CELL_NET, including its campaign-name
-- fallback (some SB video campaigns don't populate creative_type, e.g. FRESH-VIDEO/EXACT).
ag_fmt AS (
  SELECT ad_group_id,
    COALESCE(
      MAX(creative_type),
      CASE WHEN UPPER(ANY_VALUE(campaign_name)) LIKE '%VIDEO%'      THEN 'BRAND_VIDEO'
           WHEN UPPER(ANY_VALUE(campaign_name)) LIKE '%COLLECTION%' THEN 'PRODUCT_COLLECTION' END
    ) AS creative_type
  FROM `onyga-482313.OI.V_SRC_AmazonAds_sb_ad_report`
  GROUP BY ad_group_id
),

-- Every holiday's peak range — used to EXCLUDE peaks from the off-peak fallback baseline.
peak_ranges AS (
  SELECT boost_start AS s, COALESCE(cooldown_end, holiday_date) AS e
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
),

-- Ads performance per (family, term, DAY) — kept at day grain so each intent can be measured
-- over its own window. 2y of history so last Christmas/Easter are reachable. NOTE the asin
-- link is the fuzzy COALESCE(most_advertised_asin_impressions, ASIN_BY_CAMPAIGN_NAME) — the
-- same pattern the rest of the Research page uses for family-level ads-by-search-term.
fam_ads_raw AS (
  SELECT
    p.parent_name,
    LOWER(a.search_term) AS term,
    a.date,
    CASE
      WHEN a.campaign_type = 'SB' AND f.creative_type IN ('BRAND_VIDEO', 'VIDEO') THEN 'SB_VIDEO'
      WHEN a.campaign_type = 'SB' AND f.creative_type = 'PRODUCT_COLLECTION'      THEN 'SB_COLLECTION'
      WHEN a.campaign_type = 'SB'                                                 THEN 'SB_OTHER'
      ELSE 'SP'
    END AS ad_format,
    SUM(a.Ads_cost)     AS cost,
    SUM(a.GROSS_PROFIT) AS gp,
    SUM(a.Ads_clicks)   AS clicks,
    SUM(a.Ads_orders)   AS orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME) = p.asin
  LEFT JOIN ag_fmt f ON f.ad_group_id = a.ad_group_id
  WHERE p.parent_name IS NOT NULL AND p.is_active = true
    AND a.Ads_clicks > 0
    AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 2 YEAR)
  GROUP BY 1, 2, 3, 4
),
fam_ads AS (
  SELECT r.*,
    NOT EXISTS (SELECT 1 FROM peak_ranges pr WHERE r.date BETWEEN pr.s AND pr.e) AS is_off_peak
  FROM fam_ads_raw r
),

-- Did the PRIMARY window find anything? (intent grain — keep every term on one window so the
-- numbers stay coherent and the window label stays true.)
intent_terms AS (
  SELECT DISTINCT parent_name, intent_key, LOWER(query_text) AS term FROM primary_matched
),
primary_probe AS (
  SELECT d.parent_name, d.intent_key, SUM(fa.clicks) AS clicks
  FROM intent_terms d
  JOIN intent_window w ON w.intent_key = d.intent_key
  LEFT JOIN fam_ads fa
    ON fa.parent_name = d.parent_name AND fa.term = d.term
   AND fa.date BETWEEN w.win_start AND w.win_end
  GROUP BY 1, 2
),
-- Chosen window: a GENERIC intent with NO data in 90d falls back to 12 months OFF-PEAK.
-- Seasonal never falls back — its season IS the only fair window.
chosen_window AS (
  SELECT p.parent_name, p.intent_key,
    (COALESCE(p.clicks, 0) = 0 AND w.intent_type = 'GENERIC') AS used_fallback,
    IF(COALESCE(p.clicks, 0) = 0 AND w.intent_type = 'GENERIC',
       DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY), w.win_start) AS win_start,
    IF(COALESCE(p.clicks, 0) = 0 AND w.intent_type = 'GENERIC',
       CURRENT_DATE(), w.win_end) AS win_end
  FROM primary_probe p
  JOIN intent_window w ON w.intent_key = p.intent_key
),

-- Money per (family, intent, TERM) inside that intent's chosen window, split by ad format.
term_ads AS (
  SELECT
    d.parent_name, d.intent_key, d.term,
    c.win_start, c.win_end, c.used_fallback,
    SUM(fa.cost)   AS cost,
    SUM(fa.gp)     AS gp,
    SUM(fa.clicks) AS clicks,
    SUM(fa.orders) AS orders,
    SUM(IF(fa.ad_format = 'SP',            fa.cost, 0))   AS sp_cost,
    SUM(IF(fa.ad_format = 'SP',            fa.gp,   0))   AS sp_gp,
    SUM(IF(fa.ad_format = 'SP',            fa.clicks, 0)) AS sp_clicks,
    SUM(IF(fa.ad_format = 'SB_VIDEO',      fa.cost, 0))   AS sbv_cost,
    SUM(IF(fa.ad_format = 'SB_VIDEO',      fa.gp,   0))   AS sbv_gp,
    SUM(IF(fa.ad_format = 'SB_VIDEO',      fa.clicks, 0)) AS sbv_clicks,
    SUM(IF(fa.ad_format = 'SB_COLLECTION', fa.cost, 0))   AS sbc_cost,
    SUM(IF(fa.ad_format = 'SB_COLLECTION', fa.gp,   0))   AS sbc_gp,
    SUM(IF(fa.ad_format = 'SB_COLLECTION', fa.clicks, 0)) AS sbc_clicks
  FROM intent_terms d
  JOIN chosen_window c ON c.parent_name = d.parent_name AND c.intent_key = d.intent_key
  LEFT JOIN fam_ads fa
    ON fa.parent_name = d.parent_name AND fa.term = d.term
   AND fa.date BETWEEN c.win_start AND c.win_end
   -- the 12-month fallback baseline must exclude every holiday peak
   AND (NOT c.used_fallback OR fa.is_off_peak)
  GROUP BY 1, 2, 3, 4, 5, 6
),

-- Money signal per (family, intent) over ALL the intent's matched terms
intent_ads AS (
  SELECT
    parent_name, intent_key,
    ANY_VALUE(win_start)     AS ads_window_start,
    ANY_VALUE(win_end)       AS ads_window_end,
    ANY_VALUE(used_fallback) AS ads_used_fallback,
    ROUND(SUM(cost), 2) AS ads_spend,
    SUM(clicks)         AS ads_clicks,
    SUM(orders)         AS ads_orders,
    ROUND(SAFE_DIVIDE(SUM(gp), NULLIF(SUM(cost), 0)), 2) AS ads_net_roas,
    -- per-format breakdown (diagnosis; the blended figure above drives the gates)
    ROUND(SUM(sp_cost), 2)  AS ads_sp_spend,  SUM(sp_clicks)  AS ads_sp_clicks,
    ROUND(SAFE_DIVIDE(SUM(sp_gp),  NULLIF(SUM(sp_cost), 0)), 2)  AS ads_sp_net_roas,
    ROUND(SUM(sbv_cost), 2) AS ads_sbv_spend, SUM(sbv_clicks) AS ads_sbv_clicks,
    ROUND(SAFE_DIVIDE(SUM(sbv_gp), NULLIF(SUM(sbv_cost), 0)), 2) AS ads_sbv_net_roas,
    ROUND(SUM(sbc_cost), 2) AS ads_sbc_spend, SUM(sbc_clicks) AS ads_sbc_clicks,
    ROUND(SAFE_DIVIDE(SUM(sbc_gp), NULLIF(SUM(sbc_cost), 0)), 2) AS ads_sbc_net_roas
  FROM term_ads
  GROUP BY 1, 2
),

ranked AS (
  SELECT
    m.*,
    s.boost_start  AS season_start,
    s.cooldown_end AS season_end,
    s.peak_start,
    MAX(m.rank) OVER (PARTITION BY m.parent_name, m.intent_key) AS family_best_rank,
    MAX(m.effective_rank) OVER (PARTITION BY m.parent_name, m.intent_key) AS family_best_effective_rank,
    MAX(m.overall_fit) OVER (PARTITION BY m.parent_name, m.intent_key) AS family_best_fit,
    ROW_NUMBER() OVER (
      PARTITION BY m.parent_name, m.intent_key
      ORDER BY m.effective_rank DESC, m.weekly_market_purchases DESC, m.query_text
    ) AS rn
  FROM primary_matched m
  LEFT JOIN season s ON s.holiday_name = m.holiday_name
)

SELECT
  r.parent_name,
  r.intent_key,
  r.label,
  r.intent_type,
  r.cross_family,
  r.priority,
  r.query_text,
  r.rank,
  r.overall_fit,
  r.weekly_market_purchases,
  r.holiday_name,
  r.season_start,
  r.season_end,
  r.peak_start,
  r.family_best_rank,
  r.family_best_effective_rank,
  r.family_best_fit,
  r.effective_rank,
  r.specificity,
  r.rn,
  r.rn <= 10 AS is_top10,
  ia.ads_window_start,
  ia.ads_window_end,
  ia.ads_used_fallback,
  ia.ads_sp_spend,  ia.ads_sp_clicks,  ia.ads_sp_net_roas,
  ia.ads_sbv_spend, ia.ads_sbv_clicks, ia.ads_sbv_net_roas,
  ia.ads_sbc_spend, ia.ads_sbc_clicks, ia.ads_sbc_net_roas,
  ia.ads_spend,
  ia.ads_clicks,
  ia.ads_orders,
  ia.ads_net_roas,
  -- per-KEYWORD money, same window as its intent
  ROUND(ta.cost, 2) AS term_spend,
  ta.clicks         AS term_clicks,
  ta.orders         AS term_orders,
  ROUND(SAFE_DIVIDE(ta.gp, NULLIF(ta.cost, 0)), 2) AS term_net_roas,
  o.force_relevant,
  -- decision trace: why this (family x intent) is or isn't relevant
  CASE
    WHEN o.force_relevant IS NOT NULL THEN CONCAT('OVERRIDE ', IF(o.force_relevant, 'ON', 'OFF'))
    WHEN COALESCE(ia.ads_sp_clicks, 0) >= 100 AND COALESCE(ia.ads_sp_net_roas, 0) < 0.5
      THEN CONCAT('HOPELESS on SP (', CAST(ia.ads_sp_clicks AS STRING), ' clicks, ',
                  CAST(ia.ads_sp_net_roas AS STRING), 'x SP net ROAS < 0.5)')
    WHEN COALESCE(ia.ads_sp_clicks, 0) >= 100 AND COALESCE(ia.ads_sp_net_roas, 0) >= 1.0
      THEN CONCAT('PROVEN on SP (', CAST(ia.ads_sp_clicks AS STRING), ' clicks, ',
                  CAST(ia.ads_sp_net_roas AS STRING), 'x SP net ROAS)')

    WHEN r.family_best_effective_rank >= 60
      THEN CONCAT('FIT (rank ', CAST(r.family_best_effective_rank AS STRING), ')',
                  IF(r.intent_type = 'TIME_BASED' AND COALESCE(ia.ads_clicks, 0) = 0,
                     ' — seasonal, untested', ''))
    ELSE CONCAT('LOW FIT (rank ', CAST(r.family_best_effective_rank AS STRING), ' < 60)')
  END AS relevance_reason,
  COALESCE(
    o.force_relevant,                                    -- 1. manual override wins
    CASE
      WHEN COALESCE(ia.ads_sp_clicks, 0) >= 100          -- 2. profit gate on SP money only —
           AND COALESCE(ia.ads_sp_net_roas, 0) < 0.5     --    the intent IS the SP campaign
        THEN FALSE                                       --    (applies to SEASONAL too)
      WHEN COALESCE(ia.ads_sp_clicks, 0) >= 100          -- 3. proven rescue: SP money beats fit
           AND COALESCE(ia.ads_sp_net_roas, 0) >= 1.0
        THEN TRUE
      ELSE r.family_best_effective_rank >= 60            -- 4. fit gate (RANK_GATE) — covers
                                                         --    untested seasonal too, on the
                                                         --    ungated effective rank
    END
  ) AS is_relevant
FROM ranked r
LEFT JOIN intent_ads ia
  ON ia.parent_name = r.parent_name AND ia.intent_key = r.intent_key
LEFT JOIN term_ads ta
  ON ta.parent_name = r.parent_name AND ta.intent_key = r.intent_key
 AND ta.term = LOWER(r.query_text)
LEFT JOIN `onyga-482313.OI.DE_FAMILY_INTENT_OVERRIDE` o
  ON o.parent_name = r.parent_name AND o.intent_key = r.intent_key
