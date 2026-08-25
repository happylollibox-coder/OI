CREATE OR REPLACE VIEW `onyga-482313.OI.V_CPC_ELASTICITY`
OPTIONS (description = "How CLICKS respond to PRICE, per channel. Forecast chain step 1; spec docs/superpowers/specs/2026-08-25-catalog-forecast-chain-design.md. Publishes an elasticity e such that clicks scale as (cpc ratio)^e. TWO EARLIER ESTIMATORS WERE BUILT AND DISCARDED, and the reasons are the point of this header. (1) Correlating daily CPC against daily clicks is confounded: busy days carry both a higher price and more clicks, so the curve measures demand, not price. (2) Treating the change log as an event study is confounded by MEAN REVERSION: the Brain changes a bid BECAUSE of recent performance, so treated keywords revert whatever we do. A placebo test proved it — the keywords that got large cuts were RISING sharply in the fortnight before the cut, and the ones that got large raises were falling, so the post-change move is mostly the spike unwinding. Matching controls on that pre-trend left cells of a dozen keywords and elasticities scattered over an order of magnitude; this account does not make enough discrete bid changes to identify a curve from events alone. WHAT THIS VIEW DOES INSTEAD: two-way fixed effects over every keyword-week in the lookback. log(clicks) and log(cpc) are demeaned within keyword (removing 'expensive keywords are popular keywords') AND within week (removing 'December is busy for everything'); the surviving question is whether THIS keyword, priced above its own norm in an otherwise ordinary week, drew more clicks. Reported per channel because the two behave differently, and split fit/holdout so the caller can see whether the estimate is stable out of sample rather than taking it on trust. Keywords need real price variation and enough weeks to carry a within-keyword slope, else they are excluded. CAVEATS THE CALLER MUST CARRY: cpc is cost/clicks, so clicks sit on both sides and measurement error biases the estimate DOWN, while any keyword-specific demand shock the week effect misses biases it UP; the two work against each other and neither is removed. Read by V_CPC_RESPONSE.")
AS
WITH k AS (
  SELECT 365 AS lookback_days,      -- one year of price variation, per the house ruling on this curve
         8    AS min_weeks,         -- fewer weeks than this and a within-keyword slope is meaningless
         0.05 AS min_log_price_sd,  -- a keyword whose price never moved cannot price-identify anything
         2    AS min_weekly_clicks,
         90   AS holdout_days,
         200  AS min_kw_weeks       -- below this a channel estimate is not published as usable
),
kwk AS (
  SELECT CAST(a.campaign_id AS STRING) AS cid,
         LOWER(TRIM(a.targeting)) AS t,
         DATE_TRUNC(a.date, WEEK(SUNDAY)) AS wk,
         SUM(a.Ads_clicks) AS clicks,
         SUM(a.Ads_cost)   AS cost
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, k
  WHERE a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL k.lookback_days DAY)
    AND a.targeting IS NOT NULL
  GROUP BY 1, 2, 3
  HAVING SUM(a.Ads_clicks) >= (SELECT min_weekly_clicks FROM k) AND SUM(a.Ads_cost) > 0
),
lg AS (SELECT *, LOG(clicks) AS lc, LOG(SAFE_DIVIDE(cost, clicks)) AS lp FROM kwk),
elig AS (
  SELECT cid, t FROM lg, k GROUP BY 1, 2
  HAVING COUNT(*) >= ANY_VALUE(k.min_weeks) AND STDDEV(lp) > ANY_VALUE(k.min_log_price_sd)
),
dd AS (
  SELECT l.*,
         l.lc - AVG(l.lc) OVER (PARTITION BY l.cid, l.t)
              - AVG(l.lc) OVER (PARTITION BY l.wk) + AVG(l.lc) OVER () AS lc_dd,
         l.lp - AVG(l.lp) OVER (PARTITION BY l.cid, l.t)
              - AVG(l.lp) OVER (PARTITION BY l.wk) + AVG(l.lp) OVER () AS lp_dd
  FROM lg l JOIN elig e USING (cid, t)
),
-- ONE NORMALIZER FOR BOTH VOCABULARIES. DIM_CAMPAIGN writes 'SB'/'SP'; the change log writes
-- 'SPONSORED_BRANDS'/'SPONSORED_PRODUCTS'. A test for either spelling alone silently folds one
-- whole channel into the other, and SB is the larger channel by clicks.
ct AS (
  SELECT CAST(campaign_id AS STRING) AS cid,
         CASE WHEN UPPER(ANY_VALUE(campaign_type)) = 'SB'
                OR CONTAINS_SUBSTR(UPPER(ANY_VALUE(campaign_type)), 'BRAND') THEN 'SB'
              ELSE 'SP' END AS channel
  FROM `onyga-482313.OI.DIM_CAMPAIGN` GROUP BY 1
),
seg AS (
  SELECT d.*, ct.channel,
         d.wk >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'),
                          INTERVAL (SELECT holdout_days FROM k) DAY) AS is_holdout
  FROM dd d JOIN ct USING (cid)
)
SELECT
  channel,
  COUNT(*)                                   AS keyword_weeks,
  COUNT(DISTINCT CONCAT(cid, '|', t))        AS keywords,
  COUNT(DISTINCT wk)                         AS weeks,
  ROUND(SAFE_DIVIDE(SUM(lc_dd * lp_dd), NULLIF(SUM(lp_dd * lp_dd), 0)), 3) AS elasticity,
  ROUND(CORR(lc_dd, lp_dd), 3)               AS correlation,
  ROUND(SAFE_DIVIDE(SUM(IF(NOT is_holdout, lc_dd * lp_dd, 0)),
                    NULLIF(SUM(IF(NOT is_holdout, lp_dd * lp_dd, 0)), 0)), 3) AS elasticity_fit,
  ROUND(SAFE_DIVIDE(SUM(IF(is_holdout, lc_dd * lp_dd, 0)),
                    NULLIF(SUM(IF(is_holdout, lp_dd * lp_dd, 0)), 0)), 3)     AS elasticity_holdout,
  COUNTIF(is_holdout)                        AS holdout_keyword_weeks,
  COUNT(*) >= (SELECT min_kw_weeks FROM k)   AS is_usable
FROM seg
GROUP BY channel
ORDER BY channel;
