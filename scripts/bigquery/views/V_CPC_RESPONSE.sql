CREATE OR REPLACE VIEW `onyga-482313.OI.V_CPC_RESPONSE`
OPTIONS (description = "THE PRICE-TO-CLICKS LINK of the Catalog's forecast chain (step 1; spec docs/superpowers/specs/2026-08-25-catalog-forecast-chain-design.md). Answers the first half of the Brain's question -- 'if the CPC is X over this window, how many clicks?' -- and answers it as a CURVE, not a point, so the Catalog can search for the best price rather than be handed one. That is the house ruling that the Catalog, not the Brain, chooses the CPC. CONTRACT: clicks_per_day(cpc) = baseline_clicks_per_day * POW(cpc / baseline_cpc, elasticity). The columns at 0.75x/1.00x/1.25x/1.50x are that formula already applied, published so the shape can be eyeballed without re-deriving it. ELASTICITY IS PER CHANNEL, NEVER PER KEYWORD, and that is a finding rather than a shortcut. Per-keyword slopes were fitted, and then shrunk toward the channel by two different estimators, before being abandoned: the median keyword slope carries a standard error near 1.2, which cannot distinguish an elasticity of 0.3 from one of 2.5, and only a handful of keywords in the account are measured tightly enough to speak for themselves. Fitted raw, roughly half of them pinned against the safety clamp -- meaning the clamp, not the data, was setting the price response. The keywords that ARE well measured turn out to average almost exactly the pooled value, so the per-keyword layer bought precision that did not exist and information that was not there. Do not rebuild it without first showing the standard errors have come down. BASELINE is the recent SETTLED window only, with the settle lag declared per channel because SB reports slower than SP; an unsettled baseline undercounts clicks and makes every candidate price look worse than it is. A keyword with no settled clicks gets basis NO_BASELINE and NULL predictions rather than a fabricated zero -- that is the honest signal that it needs a customer purchase flow to answer for it, which is the chain's job and not this view's. WHAT THIS DOES NOT DO: it holds conversion, price and margin fixed, so it says what a CPC buys in CLICKS, never whether those clicks are worth buying. Read by the forecast chain.")
AS
WITH k AS (
  SELECT 28  AS baseline_days,
         365 AS lookback_days
),
-- SETTLE LAG IS DECLARED, NOT INLINED. SB reports slower than SP, and a baseline drawn from
-- unsettled days undercounts clicks, which makes every candidate price look worse than it is.
settle_lag AS (SELECT 'SP' AS channel, 7 AS days UNION ALL SELECT 'SB', 14),
-- ONE NORMALIZER FOR BOTH VOCABULARIES. DIM_CAMPAIGN writes 'SB'/'SP'; the change log writes
-- 'SPONSORED_BRANDS'. Testing for either spelling alone silently folds one channel into the other,
-- and SB is the larger channel by clicks -- so that mistake would hide the whole asymmetry.
ct AS (
  SELECT CAST(campaign_id AS STRING) AS cid,
         CASE WHEN UPPER(ANY_VALUE(campaign_type)) = 'SB'
                OR CONTAINS_SUBSTR(UPPER(ANY_VALUE(campaign_type)), 'BRAND') THEN 'SB'
              ELSE 'SP' END AS channel,
         ANY_VALUE(campaign_name) AS campaign_name
  FROM `onyga-482313.OI.DIM_CAMPAIGN` GROUP BY 1
),
asof AS (
  SELECT ct.cid, ct.channel, ct.campaign_name,
         DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL sl.days DAY) AS settled_through,
         -- Resolved HERE, not in the join predicate below: BigQuery rejects a scalar subquery
         -- inside a JOIN condition ("should depend on one of join sides").
         DATE_SUB(DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL sl.days DAY),
                  INTERVAL k.baseline_days DAY) AS window_start
  FROM ct JOIN settle_lag sl USING (channel), k
),
-- THE UNIVERSE IS EVERY KEYWORD THAT RAN THIS YEAR, not only those with clicks in the settled
-- window. Built as an inner join to the fact table, this view silently OMITS a keyword that has
-- gone quiet -- and "no row" reads as "nothing to say" when the truth is "I cannot answer this
-- one, ask a flow". The LEFT JOIN below is what makes the NO_BASELINE basis reachable at all.
universe AS (
  SELECT DISTINCT CAST(f.campaign_id AS STRING) AS cid, LOWER(TRIM(f.targeting)) AS targeting
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f, k
  WHERE f.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL k.lookback_days DAY)
    AND f.targeting IS NOT NULL
),
settled AS (
  SELECT a.cid, LOWER(TRIM(f.targeting)) AS targeting,
         SUM(f.Ads_clicks) AS clicks, SUM(f.Ads_cost) AS cost,
         COUNT(DISTINCT f.date) AS days_observed
  FROM asof a
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON CAST(f.campaign_id AS STRING) = a.cid
   AND f.date <= a.settled_through
   AND f.date >  a.window_start
  WHERE f.targeting IS NOT NULL
  GROUP BY 1, 2
),
chan AS (SELECT channel, elasticity, elasticity_holdout FROM `onyga-482313.OI.V_CPC_ELASTICITY`
         WHERE is_usable),
j AS (
  SELECT u.cid, a.channel, a.campaign_name, u.targeting, a.settled_through,
         s.clicks, s.cost, IFNULL(s.days_observed, 0) AS days_observed,
         c.elasticity AS chan_elasticity, c.elasticity_holdout,
         SAFE_DIVIDE(s.cost, NULLIF(s.clicks, 0)) AS baseline_cpc,
         -- DIVIDE BY THE WINDOW, NOT BY THE DAYS THE KEYWORD HAPPENED TO RUN. Measured: 446 of 502
         -- keywords ran fewer than 28 days, the median ran 12 and 98 ran three or fewer, so
         -- clicks/days_present overstates the sustainable daily rate by about 5.7x on average. A
         -- forecast for a full window that starts from an active-day rate is inflated before any
         -- price has moved. The active-day rate is still published beside it, because a keyword
         -- that runs 3 days in 28 is intermittent and the Brain must be able to see that rather
         -- than infer it from a silently different denominator.
         SAFE_DIVIDE(s.clicks, k2.baseline_days) AS baseline_clicks_per_day,
         SAFE_DIVIDE(s.clicks, NULLIF(s.days_observed, 0)) AS clicks_per_active_day,
         SAFE_DIVIDE(s.days_observed, k2.baseline_days) AS active_day_share
  FROM universe u
  JOIN asof a USING (cid)
  LEFT JOIN settled s ON s.cid = u.cid AND s.targeting = u.targeting
  LEFT JOIN chan c ON c.channel = a.channel
  CROSS JOIN k AS k2
),
e AS (
  SELECT j.*,
         IF(j.clicks IS NULL OR j.clicks = 0 OR j.cost IS NULL OR j.cost = 0,
            NULL, j.chan_elasticity) AS elasticity,
         CASE WHEN j.clicks IS NULL OR j.clicks = 0 OR j.cost IS NULL OR j.cost = 0
                THEN 'NO_BASELINE: no settled clicks in window - needs a customer purchase flow'
              ELSE CONCAT('DATA: ', j.channel, ' channel elasticity (holdout ',
                          CAST(j.elasticity_holdout AS STRING), ')')
         END AS elasticity_basis
  FROM j
)
SELECT
  cid AS campaign_id, campaign_name, targeting, channel,
  settled_through, days_observed,
  clicks AS baseline_clicks, ROUND(cost, 2) AS baseline_cost,
  ROUND(baseline_cpc, 4) AS baseline_cpc,
  ROUND(baseline_clicks_per_day, 3) AS baseline_clicks_per_day,
  ROUND(clicks_per_active_day, 3)   AS clicks_per_active_day,
  ROUND(active_day_share, 3)        AS active_day_share,
  ROUND(elasticity, 3) AS elasticity,
  elasticity_basis,
  ROUND(baseline_clicks_per_day * POW(0.75, elasticity), 3) AS clicks_per_day_at_075x,
  ROUND(baseline_clicks_per_day,                         3) AS clicks_per_day_at_100x,
  ROUND(baseline_clicks_per_day * POW(1.25, elasticity), 3) AS clicks_per_day_at_125x,
  ROUND(baseline_clicks_per_day * POW(1.50, elasticity), 3) AS clicks_per_day_at_150x
FROM e;
