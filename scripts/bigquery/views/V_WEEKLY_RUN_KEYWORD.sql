-- V_WEEKLY_RUN_KEYWORD — every coached keyword, deduped to one row per keyword_id, with its decision
-- AND a plain reason — including no-action keywords (KEEP/MONITOR), so the Weekly Run Step-3 tree can
-- explain "why an action / why no action" (Req3). Level 2 under each campaign.
-- Also carries per-window performance (this-wk / last-4w / peak) as DAILY AVERAGES + net ROAS, computed
-- straight from FACT per keyword so each action shows current vs recent vs seasonal at a glance.
-- Heavy (reads search-term-grain V_ADS_COACH + FACT) → materialized to T_WEEKLY_RUN_KEYWORD for the cube.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_RUN_KEYWORD` AS
WITH kw AS (
  SELECT
    keyword_id,
    ANY_VALUE(campaign_id)   AS campaign_id,
    ANY_VALUE(parent_name)   AS parent_name,
    ANY_VALUE(campaign_name) AS campaign_name,
    ANY_VALUE(campaign_type) AS campaign_type,  -- SP/SB — routes the bulksheet row to the right sheet
    ANY_VALUE(ad_group_id)   AS ad_group_id,
    ANY_VALUE(targeting)     AS targeting,
    ANY_VALUE(match_type)    AS match_type,
    ANY_VALUE(days_since_last_bid_change) AS days_since_change,
    ANY_VALUE(profile_cpc_target)         AS target_cpc,  -- plan-approved target CPC (the band) for this cell
    -- keyword-level (target-grain) aggregates — constant across the keyword's search-term slices —
    -- used to build a KEYWORD-level reason so the caption never quotes a single losing search term
    -- while the row's metrics (which are keyword totals) show the opposite.
    ANY_VALUE(target_orders_8w)   AS target_orders_8w,
    ANY_VALUE(target_clicks_8w)   AS target_clicks_8w,
    ANY_VALUE(target_roas)        AS target_roas,
    ANY_VALUE(th_profitable_roas) AS th_profitable_roas,
    ANY_VALUE(th_min_clicks)      AS th_min_clicks,
    ANY_VALUE(strategy_id)        AS strategy_id,
    -- one decision per keyword (keyword-grain logic repeats across search-term slices)
    ARRAY_AGG(STRUCT(target_action, recommended_bid, current_bid, bid_change_pct, reason)
              ORDER BY priority_score DESC, ABS(COALESCE(bid_change_pct, 0)) DESC LIMIT 1)[OFFSET(0)] AS pick,
    MAX(priority_score) AS priority_score
  FROM `onyga-482313.OI.V_ADS_COACH`
  WHERE keyword_id IS NOT NULL
  GROUP BY keyword_id
),
peak_dates AS (  -- gift-season peak windows
  SELECT DISTINCT d AS date
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h, UNNEST(GENERATE_DATE_ARRAY(h.boost_start, h.cooldown_end)) d
  WHERE h.category = 'gift_season'
),
fwin AS (  -- per keyword: this-wk (7d), last-4w (28d), peak — clicks, active-days, gross profit, spend
  SELECT
    keyword_id,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), Ads_clicks, 0))  AS w1_clk,
    COUNT(DISTINCT IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)  AND Ads_clicks > 0, date, NULL)) AS w1_days,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), GROSS_PROFIT, 0)) AS w1_gp,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), Ads_cost, 0))     AS w1_spend,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), Ads_units, 0))    AS w1_units,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY), Ads_clicks, 0)) AS w4_clk,
    COUNT(DISTINCT IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY) AND Ads_clicks > 0, date, NULL)) AS w4_days,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY), GROSS_PROFIT, 0)) AS w4_gp,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY), Ads_cost, 0))     AS w4_spend,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY), Ads_units, 0))    AS w4_units,
    SUM(IF(date IN (SELECT date FROM peak_dates), Ads_clicks, 0)) AS pk_clk,
    COUNT(DISTINCT IF(date IN (SELECT date FROM peak_dates) AND Ads_clicks > 0, date, NULL)) AS pk_days,
    SUM(IF(date IN (SELECT date FROM peak_dates), GROSS_PROFIT, 0)) AS pk_gp,
    SUM(IF(date IN (SELECT date FROM peak_dates), Ads_cost, 0))     AS pk_spend,
    SUM(IF(date IN (SELECT date FROM peak_dates), Ads_units, 0))    AS pk_units,
    SUM(IF(date IN (SELECT date FROM peak_dates), Ads_orders, 0))   AS pk_ord,  -- peak orders → seasonal "proven at peak" caption
    -- 8-week totals for the KEYWORD caption — a stable window (unlike the 1-week engine target_roas,
    -- which is noisy for low-volume keywords). Same FACT source as the row's other windows.
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY), Ads_clicks, 0))  AS w8_clk,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY), Ads_orders, 0))   AS w8_ord,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY), GROSS_PROFIT, 0)) AS w8_gp,
    SUM(IF(date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY), Ads_cost, 0))     AS w8_spend
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE keyword_id IS NOT NULL
    -- complete days only (exclude today's partial/unsettled attribution) — display windows must
    -- match the engine's decision windows, which end yesterday
    AND date < CURRENT_DATE('America/Los_Angeles')
    AND (date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY)
         OR date IN (SELECT date FROM peak_dates))
  GROUP BY keyword_id
),
-- Days since WE last uploaded a change for this keyword (FACT_PPC_CHANGE_LOG = authoritative
-- upload time; the SCD2-derived days_since_change lags ~1-2d behind our uploads). Drives the
-- "✓ applied Nd ago" badge + the row's days counter so a keyword changed today reads 0d, not 90d.
last_change AS (
  SELECT keyword_id,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at, 'America/Los_Angeles')), DAY) AS days_since_suggestion
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE keyword_id IS NOT NULL AND keyword_id != ''
  GROUP BY keyword_id
),
-- 12-month clicks per keyword TEXT — the data-sufficiency signal (mirrors V_ADS_COACH_DATA.target_12mo).
-- Lets the caption say "known (N clicks/12mo)" so a proven-but-quiet seasonal keyword is never called
-- "insufficient data" just because the trailing 8w is thin.
term12 AS (
  SELECT LOWER(targeting) AS tl, SUM(Ads_clicks) AS clk12
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 365 DAY) AND targeting IS NOT NULL AND targeting != ''
  GROUP BY 1
)
SELECT
  kw.keyword_id, kw.campaign_id, kw.parent_name, kw.campaign_name, kw.campaign_type, kw.ad_group_id, kw.targeting, kw.match_type,
  kw.days_since_change, lc.days_since_suggestion, ROUND(kw.target_cpc, 2) AS target_cpc,
  -- this week (daily avg clicks + CPC + net ROAS)
  ROUND(SAFE_DIVIDE(f.w1_clk, NULLIF(f.w1_days, 0)), 1) AS w1_clk_day,
  ROUND(SAFE_DIVIDE(f.w1_spend, NULLIF(f.w1_clk, 0)), 2) AS w1_cpc,
  ROUND(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 2) AS w1_roas,
  CAST(f.w1_units AS INT64)                             AS w1_units,   -- units sold in the window (total, not /day)
  -- last 4 weeks
  ROUND(SAFE_DIVIDE(f.w4_clk, NULLIF(f.w4_days, 0)), 1) AS w4_clk_day,
  ROUND(SAFE_DIVIDE(f.w4_spend, NULLIF(f.w4_clk, 0)), 2) AS w4_cpc,
  ROUND(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)), 2) AS w4_roas,
  CAST(f.w4_units AS INT64)                             AS w4_units,
  -- peak season
  ROUND(SAFE_DIVIDE(f.pk_clk, NULLIF(f.pk_days, 0)), 1) AS pk_clk_day,
  ROUND(SAFE_DIVIDE(f.pk_spend, NULLIF(f.pk_clk, 0)), 2) AS pk_cpc,
  ROUND(SAFE_DIVIDE(f.pk_gp, NULLIF(f.pk_spend, 0)), 2) AS pk_roas,
  CAST(f.pk_units AS INT64)                             AS pk_units,
  kw.pick.target_action               AS action,
  kw.pick.current_bid                 AS current_bid,
  ROUND(kw.pick.recommended_bid, 2)   AS recommended_bid,
  ROUND(kw.pick.bid_change_pct, 0)    AS bid_change_pct,
  -- KEYWORD-level caption: describes the keyword's own 8-week aggregate (matches the row's metrics),
  -- not a single search-term slice, and classifies profitability on the STABLE 8-week net ROAS
  -- (f.w8_gp / f.w8_spend) rather than the engine's noisy 1-week target_roas. Presentation of the
  -- engine's already-made target_action — no new decision logic. Falls back to the engine's picked
  -- reason only for actions we don't summarise here (e.g. PROBE, defense).
  CASE
    WHEN kw.strategy_id IS NULL
      THEN CONCAT('No strategy assigned to this campaign — assign one (Campaign Mapping) so the coach can manage it. (',
                  CAST(COALESCE(f.w8_clk, 0) AS STRING), ' clicks, ', CAST(COALESCE(f.w8_ord, 0) AS STRING), ' orders in 8w.)')
    -- STOP wins the caption first — incl. the PEAK-LOSER stop (ran at peak but lost money there AND
    -- dead now). Explains via peak for that case, else via the recent windows.
    WHEN kw.pick.target_action = 'STOP_TARGET'
      THEN CASE
        WHEN COALESCE(f.pk_ord, 0) > 0 AND SAFE_DIVIDE(f.pk_gp, NULLIF(f.pk_spend, 0)) < 1.0
          THEN CONCAT('Lost money even at peak (', CAST(f.pk_ord AS STRING), ' orders, ',
                      CAST(ROUND(SAFE_DIVIDE(f.pk_gp, NULLIF(f.pk_spend, 0)), 2) AS STRING),
                      '× net) and not converting now — not a seasonal winner → pausing this target.')
        ELSE CONCAT('Losing and not recovering — last 7 days ',
                    CAST(ROUND(COALESCE(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 0), 2) AS STRING),
                    '×, last 28 days ', CAST(ROUND(COALESCE(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)), 0), 2) AS STRING),
                    '× → pausing this target.')
      END
    -- SWITCH_HERO — the wrong product variant is being advertised for this term. Action-driven so the
    -- caption matches (was falling through to "not converting"). Try the right ASIN before killing it.
    WHEN kw.pick.target_action = 'SWITCH_HERO'
      THEN CONCAT('Wrong product variant is showing here (', CAST(COALESCE(f.w8_clk, 0) AS STRING),
                  ' clicks/8w, no orders) — switch to the better-converting hero ASIN (add it as a product ad), or negate if it cannot win.')
    -- Seasonal: dormant recently but a proven & PROFITABLE peak performer → hold for the season. Gated
    -- on peak net ROAS ≥ 1.0 (2026-07-03) so a peak money-LOSER is NOT called "proven" (it's stopped above).
    WHEN COALESCE(f.w8_ord, 0) = 0 AND COALESCE(f.pk_ord, 0) > 0
         AND SAFE_DIVIDE(f.pk_gp, NULLIF(f.pk_spend, 0)) >= 1.0
      THEN CONCAT('Seasonal — quiet off-season (', CAST(COALESCE(f.w8_clk, 0) AS STRING), ' clicks/8w), but proven at peak (',
                  CAST(f.pk_ord AS STRING), ' orders, ', CAST(ROUND(SAFE_DIVIDE(f.pk_gp, NULLIF(f.pk_spend, 0)), 2) AS STRING),
                  '× net). Holding for the season.')
    -- Data sufficiency uses 12-MONTH clicks (by term), NOT the trailing 8w — a proven keyword is never
    -- "insufficient" just because it's quiet now. Matches the engine's 12-month sufficiency gate.
    WHEN COALESCE(t12.clk12, f.w8_clk, 0) < 15
      THEN CONCAT(CAST(COALESCE(t12.clk12, f.w8_clk, 0) AS STRING), ' clicks(12mo) — need at least 15 to evaluate this keyword.')
    WHEN COALESCE(f.w8_ord, 0) = 0
      THEN CONCAT('No orders on ', CAST(COALESCE(f.w8_clk, 0) AS STRING), ' clicks (8w) — not converting. Consider negating or cutting the bid.')
    -- ═══ Profitability / bid explanation — reasons in the SAME windows the engine DECIDES on:
    -- 1-week sets direction, 4-week confirms, peak finalizes (the two-window model, 2026-07-03).
    -- NOT the stable 8-week, which the decision no longer keys on. Driven off the engine's actual
    -- target_action so the caption can never contradict the row's action. (r1 = this-week net ROAS,
    -- r4 = 4-week net ROAS — recomputed inline since select-aliases aren't referenceable here.)
    -- (STOP_TARGET is handled higher up, before the seasonal branch, so a peak-loser stop wins.) ═══
    -- RAISE — sweet-spot: bidding ABOVE the band (last-7-days ≥2×), or a normal step toward the band.
    WHEN kw.pick.target_action = 'INCREASE_BID'
         AND kw.pick.recommended_bid > COALESCE(kw.pick.current_bid, 0)
         AND kw.target_cpc IS NOT NULL AND kw.pick.recommended_bid > kw.target_cpc + 0.001
      THEN CONCAT('Strong at last 7 days ',
                  CAST(ROUND(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 2) AS STRING),
                  '× (≥2×) → bidding above the $', CAST(ROUND(kw.target_cpc, 2) AS STRING),
                  ' band toward the cap for more volume, down to the 1.5–2× sweet spot.')
    WHEN kw.pick.target_action = 'INCREASE_BID'
      THEN CONCAT('Last 7 days ', CAST(ROUND(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 2) AS STRING), '× ',
                  IF(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)) >= kw.th_profitable_roas,
                     CONCAT('confirmed by last 28 days ', CAST(ROUND(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)), 2) AS STRING), '×'),
                     'is strong enough to act on now'),
                  ' → raising the bid toward the band.')
    -- TRIM — sweet-spot pullback: bid is ABOVE the band and the last 7 days is still profitable but under
    -- the 1.5× sweet spot → ease back toward the band (NOT "losing"). Mirrors the engine's SWEET-SPOT PULLBACK.
    WHEN kw.pick.target_action = 'REDUCE_BID'
         AND kw.target_cpc IS NOT NULL
         AND COALESCE(kw.pick.current_bid, 0) > kw.target_cpc + 0.001
         AND SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)) >= kw.th_profitable_roas
         AND SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)) < 1.5
      THEN CONCAT('Above the $', CAST(ROUND(kw.target_cpc, 2) AS STRING), ' band at last 7 days ',
                  CAST(ROUND(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 2) AS STRING),
                  '× — profitable but under the 1.5× sweet spot → easing the bid back toward the band.')
    -- TRIM — genuine cut: say "Losing" only when the last 7 days is actually below break-even (<1.0×).
    WHEN kw.pick.target_action = 'REDUCE_BID'
      THEN CONCAT(IF(COALESCE(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 0) < 1.0, 'Losing', 'Underperforming'),
                  ' — last 7 days ', CAST(ROUND(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 2) AS STRING),
                  '× (last 28 days ', CAST(ROUND(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)), 2) AS STRING), '×) → trimming the bid.')
    -- HOLD (MONITOR/KEEP) — explain WHY it holds via the two windows:
    -- last 7 days profitable but last 28 days hasn't confirmed → unconfirmed spike, wait
    WHEN SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)) >= kw.th_profitable_roas
         AND COALESCE(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)), 0) < kw.th_profitable_roas
      THEN CONCAT('Last 7 days is profitable (', CAST(ROUND(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 2) AS STRING),
                  '×) but last 28 days (', CAST(ROUND(COALESCE(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)), 0), 2) AS STRING),
                  '×) has not confirmed it yet — holding until the recent trend agrees.')
    -- genuinely DOWN 7 days (below break-even, <1.0×) but the last 28 days is still a strong winner → the
    -- brake: don't cut on one bad week. (Uses absolute 1.0× break-even, NOT the strategy's
    -- profitable bar — a 2.68× week on a defense keyword with a 3× bar is strong, not "quiet".)
    WHEN SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)) < 1.0
         AND COALESCE(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)), 0) >= 1.5
      THEN CONCAT('Last 7 days dipped below break-even (', CAST(ROUND(COALESCE(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 0), 2) AS STRING),
                  '×) but last 28 days is still strong (', CAST(ROUND(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)), 2) AS STRING),
                  '×) — holding, not cutting on one week.')
    -- making money (>= break-even) → hold. Above/at its band for winners, or a defense keyword held
    -- below its own high bar (e.g. a 2.68× generic in a 3× brand-defense campaign) — still profitable.
    WHEN SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)) >= 1.0
      THEN CONCAT('Profitable — last 7 days ', CAST(ROUND(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 2) AS STRING),
                  '×, last 28 days ', CAST(ROUND(COALESCE(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)), 0), 2) AS STRING),
                  '× — holding.')
    ELSE CONCAT('Watching — last 7 days ', CAST(ROUND(COALESCE(SAFE_DIVIDE(f.w1_gp, NULLIF(f.w1_spend, 0)), 0), 2) AS STRING),
                '×, last 28 days ', CAST(ROUND(COALESCE(SAFE_DIVIDE(f.w4_gp, NULLIF(f.w4_spend, 0)), 0), 2) AS STRING),
                '× — below break-even, but too little to act on.')
  END                                 AS reason,
  kw.pick.target_action IN ('INCREASE_BID', 'REDUCE_BID', 'PROBE') AS is_action,
  kw.priority_score
FROM kw
LEFT JOIN fwin f USING (keyword_id)
LEFT JOIN last_change lc USING (keyword_id)
LEFT JOIN term12 t12 ON LOWER(kw.targeting) = t12.tl;
