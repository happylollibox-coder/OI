-- =============================================
-- V_AD_REDIRECT_RECHECK — the return half of the doorway redirect (2026-08-17, Task 4.6).
-- Ori: "remember when it is back in inventory to recheck if we want to change it back or leave
-- it." NOT an automatic revert — a re-opened decision with the interim evidence on the table.
--
-- Watches DE_AD_REDIRECTS ACTIVE rows. A row RECHECKS when the out ASIN is back in stock with
-- >= 45 days of cover at its current selling rate AND the redirect is >= 14 days old (enough
-- doorway data to judge). Evidence: the hero doorway's units/CPC in THIS ad group since the
-- redirect (advertised-product report) beside the out ASIN's last-30d-before-redirect record.
-- The suggestion is advisory; Ori's click writes status RESTORED (re-enable out ad_id + pause
-- hero ad) or KEPT (do nothing). Small tables + one 90d report scan — no ceiling views.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_AD_REDIRECT_RECHECK` AS
WITH act AS (
  SELECT * FROM `onyga-482313.OI.DE_AD_REDIRECTS` WHERE status = 'ACTIVE'
),
snap AS (SELECT MAX(Date) AS d FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`),
stock AS (
  SELECT s.ASIN AS asin, SUM(IF(s.source_type = 'FBA', s.quantity_balance, 0)) AS fba_qty
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` s, snap WHERE s.Date = snap.d GROUP BY 1
),
rate AS (
  SELECT PURCHASED_ASIN AS asin,
         GREATEST(ROUND(SUM(IF(DATE >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), PURCHASED_UNITS, 0)) / 7, 3),
                  ROUND(SUM(PURCHASED_UNITS) / 30, 3)) AS units_day
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
  WHERE DATE >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY) GROUP BY 1
),
doorway AS (  -- each doorway's serve record in the redirect's own ad group, last 90d
  SELECT CAST(a.campaign_id AS STRING) cid, CAST(a.ad_group_id AS STRING) agid, a.advertised_asin,
         a.date, a.clicks, a.units_14d, a.spend
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product` a
  WHERE a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 90 DAY)
)
SELECT r.id, r.family, r.campaign_id, r.campaign_name, r.ad_group_id,
  r.out_asin, r.out_product, r.out_ad_id, r.hero_asin, r.hero_product, r.hero_sku,
  DATE(r.redirected_at, 'America/Los_Angeles') AS redirected_on,
  DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), DATE(r.redirected_at, 'America/Los_Angeles'), DAY) AS days_since,
  st.fba_qty AS out_fba_qty,
  CAST(ROUND(SAFE_DIVIDE(st.fba_qty, NULLIF(ra.units_day, 0))) AS INT64) AS out_cover_days,
  -- hero doorway since the redirect, in this ad group
  SUM(IF(d.advertised_asin = r.hero_asin AND d.date >= DATE(r.redirected_at, 'America/Los_Angeles'), d.units_14d, 0)) AS hero_units_since,
  SUM(IF(d.advertised_asin = r.hero_asin AND d.date >= DATE(r.redirected_at, 'America/Los_Angeles'), d.clicks, 0)) AS hero_clicks_since,
  -- the out doorway's last 30 days BEFORE the redirect — the record it must beat
  SUM(IF(d.advertised_asin = r.out_asin
         AND d.date BETWEEN DATE_SUB(DATE(r.redirected_at, 'America/Los_Angeles'), INTERVAL 30 DAY)
                        AND DATE(r.redirected_at, 'America/Los_Angeles'), d.units_14d, 0)) AS out_units_before30,
  SUM(IF(d.advertised_asin = r.out_asin
         AND d.date BETWEEN DATE_SUB(DATE(r.redirected_at, 'America/Los_Angeles'), INTERVAL 30 DAY)
                        AND DATE(r.redirected_at, 'America/Los_Angeles'), d.clicks, 0)) AS out_clicks_before30,
  CONCAT(r.out_product, ' is back (',
         CAST(CAST(ROUND(SAFE_DIVIDE(st.fba_qty, NULLIF(ra.units_day, 0))) AS INT64) AS STRING),
         'd cover) — hero doorway sold ',
         CAST(SUM(IF(d.advertised_asin = r.hero_asin AND d.date >= DATE(r.redirected_at, 'America/Los_Angeles'), d.units_14d, 0)) AS STRING),
         'u since ⇒ restore the old doorway, or keep the hero — your call') AS reason_short
FROM act r
LEFT JOIN stock st ON st.asin = r.out_asin
LEFT JOIN rate ra ON ra.asin = r.out_asin
LEFT JOIN doorway d ON d.cid = r.campaign_id AND d.agid = r.ad_group_id
WHERE SAFE_DIVIDE(st.fba_qty, NULLIF(ra.units_day, 0)) >= 45
  AND DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), DATE(r.redirected_at, 'America/Los_Angeles'), DAY) >= 14
GROUP BY r.id, r.family, r.campaign_id, r.campaign_name, r.ad_group_id, r.out_asin, r.out_product,
         r.out_ad_id, r.hero_asin, r.hero_product, r.hero_sku, r.redirected_at, st.fba_qty, ra.units_day;
