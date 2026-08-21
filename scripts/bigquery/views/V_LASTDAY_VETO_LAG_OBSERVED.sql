-- V_LASTDAY_VETO_LAG_OBSERVED — the one OBSERVED (not modelled) reading of attribution lag at
-- keyword grain, and the check on the assumption V_LASTDAY_VETO_PREMISE cannot check itself.
--
-- V_LASTDAY_VETO_PREMISE thins a settled day by an ACCOUNT accrual share and treats every order
-- in a day as equally likely to have landed by age 1. If instead lag were a property of the
-- KEYWORD — some search terms bought same-session, others slept on it — then the last-day veto
-- would not be uniformly wrong; it would be wrong on an identifiable subset, and the repair would
-- be an exemption rather than a retirement. This view is how that question is answered.
--
-- THE SOURCE: SRC_ACC_AmazonAds_purchased_product is the only table in the warehouse that carries
-- a keyword-day's conversions SPLIT BY ATTRIBUTION WINDOW — orders and dollars credited within
-- 1 / 7 / 14 / 30 days of the click, at (date, campaign, ad group, keyword, purchased ASIN). The
-- 1-day bucket is the closest thing the warehouse holds to "what this keyword-day had already
-- earned when the engine looked at it".
--
-- ══ FOUR LIMITS, ALL LOAD-BEARING ════════════════════════════════════════════════════════════
-- 1. THE 1-DAY BUCKET IS NOT AGE-1 VISIBILITY. It is conversions attributed within 24h of the
--    click; age-1 visibility is conversions both CONVERTED AND PROCESSED by the time the feed is
--    pulled. The gap between the two is reporting lag, which no keyword-grain table sees. Compare
--    this view's share_1d against V_ADS_SETTLE_CURVE's age-1 sales share to size that gap: the
--    bucket is the more OPTIMISTIC of the two, so every finding drawn from it is conservative in
--    the veto's favour.
-- 2. THE FEED DOES NOT RECONCILE TO FACT_AMAZON_ADS. Matched keyword-days carry fewer orders and
--    fewer dollars here than the ads reports show for the same keyword-day, and some keyword-days
--    with settled sales have no row here at all. fact_orders / fact_sales and orders_final /
--    rev_final are BOTH published on every row so the shortfall is measurable rather than
--    asserted, and capture_ratio lets any reader restrict to well-captured rows.
-- 3. SP ONLY. Streaming-brand keyword ids in this feed do not join the ads keyword-days, so the
--    channel with the longer attribution window — the one where lag should bite hardest — is not
--    observed here at all.
-- 4. SURVIVORSHIP: a row exists here only where a purchase eventually happened. A keyword-day
--    that ended with no sales has no row, which is correct (it read zero while filling and zero
--    when settled) but means this view can only measure lag among days that DID convert.
--
-- GRAIN: one row per (campaign_id, keyword_id, date), SP, settled days only.
-- THE QUESTION IT ANSWERS: reads_zero_at_1d = TRUE on a row with orders_final > 0 is a keyword-day
-- that ended with real sales and had NONE of them credited a day later — the exact shape the raise
-- arm cannot tell apart from a keyword that simply did not sell.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_LASTDAY_VETO_LAG_OBSERVED` AS
WITH
wm AS (SELECT MAX(date) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
kd AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id, a.keyword_id, a.date,
         ANY_VALUE(a.campaign_name) AS campaign_name,
         ANY_VALUE(a.targeting)     AS targeting,
         SUM(a.Ads_clicks) AS clicks_settled,
         SUM(a.Ads_cost)   AS spend_settled,
         SUM(a.Ads_orders) AS fact_orders,
         SUM(a.Ads_sales)  AS fact_sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.campaign_type = 'SP'
    AND a.keyword_id IS NOT NULL
    AND a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 30 DAY)
  GROUP BY 1, 2, 3
),
pp AS (
  SELECT CAST(p.campaign_id AS STRING) AS campaign_id, p.keyword_id, p.DATE AS date,
         SUM(p.PURCHASED_ORDERS_1d)      AS orders_1d,
         SUM(p.PURCHASED_ORDERS)         AS orders_final,
         SUM(p.PURCHASED_AMOUNT_USD_1d)  AS rev_1d,
         SUM(p.PURCHASED_AMOUNT_USD)     AS rev_final,
         MIN(DATE_DIFF(DATE(p.first_seen_at), p.DATE, DAY)) AS first_seen_age_days
  FROM `onyga-482313.OI.SRC_ACC_AmazonAds_purchased_product` p
  GROUP BY 1, 2, 3
)
SELECT
  kd.campaign_id, kd.campaign_name, kd.keyword_id, kd.targeting, kd.date,
  kd.clicks_settled, ROUND(kd.spend_settled, 2) AS spend_settled,
  kd.fact_orders, ROUND(kd.fact_sales, 2) AS fact_sales,
  pp.orders_1d, pp.orders_final,
  ROUND(pp.rev_1d, 2) AS rev_1d, ROUND(pp.rev_final, 2) AS rev_final,
  pp.first_seen_age_days,
  -- how much of this keyword-day's final credited revenue was already credited a day later
  ROUND(SAFE_DIVIDE(pp.rev_1d, NULLIF(pp.rev_final, 0)), 4) AS share_1d,
  ROUND(SAFE_DIVIDE(pp.orders_1d, NULLIF(pp.orders_final, 0)), 4) AS share_1d_orders,
  -- how much of the ads report's own settled total this feed captured for the same keyword-day
  ROUND(SAFE_DIVIDE(pp.rev_final, NULLIF(kd.fact_sales, 0)), 4) AS capture_ratio,
  COALESCE(pp.orders_1d, 0) = 0 AND COALESCE(pp.orders_final, 0) > 0 AS reads_zero_at_1d,
  pp.rev_final IS NULL AND kd.fact_sales > 0 AS settled_sales_not_captured
FROM kd
LEFT JOIN pp USING (campaign_id, keyword_id, date)
WHERE kd.clicks_settled > 0;
