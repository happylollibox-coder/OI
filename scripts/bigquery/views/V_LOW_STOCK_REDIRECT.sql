-- =============================================
-- V_LOW_STOCK_REDIRECT — the doorway re-aim rows (2026-08-17, engine-finalization Task 4.6).
-- Ori: "if one variation is out of stock we should change the target of the out of stock target
-- to the best high demand variation we have in stock."
--
-- One row per (SP ad group that advertised the binding variation in the last 30d) of a family in
-- REDIRECT MODE. The mode and the hero are computed ONCE, inside V_LOW_STOCK_ADS (fam_agg/rmode,
-- v27.73) and read here off its FAMILY rows — this view adds only the ad-group fan-out from the
-- advertised-product report (which carries ad_id, so the pause half is a real bulksheet row).
-- The play per row: PAUSE the out ASIN's product ad (by ad_id) + CREATE the hero's product ad in
-- the same ad group (ADD_PRODUCT_AD, resolved by SKU). Bids and budgets untouched — that is the
-- point. SB rows are NOT emitted (creative ASINs are fixed in the creative; SB stays on the
-- brake arms). Exported redirects land in DE_AD_REDIRECTS; already-ACTIVE ones are excluded so
-- the offer disappears once taken. PLANNER: one scan of the ceiling view (FAMILY rows only), the
-- snapshot-SP precedent.
--
-- v27.80 (Ori 2026-08-17, verbatim: "BALL-SP/AUTO (Mint) is auto per product. auto we have for each
-- product - so no need to change / only reduce ads by reducing the bid") — DEDICATED CAMPAIGNS ARE
-- NO LONGER OFFERED A REDIRECT. A campaign that advertises exactly ONE of our own products has
-- nowhere to re-aim: this account runs one auto campaign per variation, so BALL-SP/AUTO (Pink)
-- ALREADY EXISTS and already does precisely the job that swapping Mint to Pink inside
-- BALL-SP/AUTO (Mint) would do. Offering that swap proposes building a duplicate of a live
-- campaign. The correct action for a campaign dedicated to the dry variation is the ORDINARY BRAKE
-- — reduce the bid — which V_LOW_STOCK_ADS v27.80 restores via serves_only_binding.
-- Dropped today: BALL-SP/AUTO (Mint) (1 own ASIN, $417/30d). Remaining: the shared doorways, which
-- is the whole population this view was ever about — BALLS- BROAD (5 own ASINs),
-- BUNNY-SP/BROAD (3), BUNNY- BROAD (9), BUNNY - COMPETITORS (11).
-- The scope is computed HERE, off the report this view already scans — no new dependency — over the
-- same 30 COMPLETE days ending watermark-1 that V_CAMPAIGN_PRODUCT_SCOPE uses, so the two objects
-- can never disagree about which campaigns are dedicated. "Own" = DIM_PRODUCT.parent_name IS NOT
-- NULL: a campaign advertising one of ours against forty competitor ASINs is still DEDICATED
-- (fact_oi_dim_product_holds_competitor_asins).
-- NOTE ON THE TWO WINDOWS: the doorway scan (`adv`) keeps its CURRENT_DATE-30 window unchanged, so
-- the row list itself does not move; only the dedicated-campaign exclusion is new. The scope scan
-- (`scope`) uses the complete-day window because that is the definition T_CAMPAIGN_PRODUCT_SCOPE
-- publishes and the two must agree. Both read the same table.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_LOW_STOCK_REDIRECT` AS
WITH fam AS (
  SELECT family, asin AS out_asin, binding_product AS out_product,
         hero_asin, hero_product, hero_rate, hero_cover, risk_state
  FROM `onyga-482313.OI.V_LOW_STOCK_ADS`
  WHERE row_kind = 'FAMILY' AND redirect_mode
),
-- the ad groups whose doorway is the out ASIN: served impressions in the last 30d, SP report
adv AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id, CAST(a.ad_group_id AS STRING) AS ad_group_id,
         a.advertised_asin, CAST(a.ad_id AS STRING) AS ad_id,
         SUM(a.impressions) AS impressions_30d, ROUND(SUM(a.spend), 2) AS spend_30d
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product` a
  WHERE a.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 30 DAY)
  GROUP BY 1, 2, 3, 4
  HAVING impressions_30d > 0
),
-- v27.80: HOW MANY OF OUR OWN PRODUCTS DOES THIS CAMPAIGN SELL? Same definition and same window as
-- V_CAMPAIGN_PRODUCT_SCOPE. n_own_asins = 1 means DEDICATED — nowhere to re-aim.
scope_wm AS (
  SELECT MAX(date) AS adv_wm FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
),
own_asin AS (
  SELECT DISTINCT asin FROM `onyga-482313.OI.DIM_PRODUCT`
  WHERE parent_name IS NOT NULL AND asin IS NOT NULL
),
scope_adv AS (
  SELECT DISTINCT CAST(a.campaign_id AS STRING) AS campaign_id, a.advertised_asin AS asin
  FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product` a
  CROSS JOIN scope_wm w
  WHERE a.date BETWEEN DATE_SUB(w.adv_wm, INTERVAL 30 DAY) AND DATE_SUB(w.adv_wm, INTERVAL 1 DAY)
    AND a.campaign_id IS NOT NULL AND a.advertised_asin IS NOT NULL
    AND a.impressions > 0
),
scope AS (
  SELECT v.campaign_id, CAST(COUNTIF(o.asin IS NOT NULL) AS INT64) AS n_own_asins
  FROM scope_adv v LEFT JOIN own_asin o ON o.asin = v.asin
  GROUP BY 1
),
sku AS (SELECT asin, ANY_VALUE(sku) AS sku FROM `onyga-482313.OI.DIM_PRODUCT` WHERE sku IS NOT NULL GROUP BY 1)
SELECT
  CONCAT(v.campaign_id, '|', v.ad_group_id, '|', f.out_asin) AS id,
  f.family, v.campaign_id, dc.campaign_name, v.ad_group_id,
  f.out_asin, f.out_product, v.ad_id AS out_ad_id,
  f.hero_asin, f.hero_product, sk.sku AS hero_sku,
  ROUND(f.hero_rate, 2) AS hero_rate, CAST(ROUND(f.hero_cover) AS INT64) AS hero_cover_days,
  v.impressions_30d, v.spend_30d, f.risk_state,
  -- v27.80: published so the panel can show the re-aim is legitimate (>1 own product in scope)
  sc.n_own_asins,
  -- the 5-second why (reason grammar: TRIGGER — EVIDENCE ⇒ MOVE)
  CONCAT(f.out_product, ' low stock — ', f.hero_product, ' sells as fast with ',
         CAST(CAST(ROUND(f.hero_cover) AS INT64) AS STRING),
         'd of stock ⇒ advertise it here instead') AS reason_short
FROM fam f
JOIN adv v ON v.advertised_asin = f.out_asin
LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
  ON CAST(dc.campaign_id AS STRING) = v.campaign_id
LEFT JOIN sku sk ON sk.asin = f.hero_asin
LEFT JOIN scope sc ON sc.campaign_id = v.campaign_id
-- SB campaigns are excluded (fixed creatives); the advertised-product report is SP-only, and the
-- DIM join is name-only — but belt it anyway on the campaign type when the DIM knows it
WHERE COALESCE(dc.campaign_type, 'SP') NOT LIKE 'SPONSORED_BRANDS%'
  -- v27.80: a DEDICATED campaign (exactly one own product) has nowhere to re-aim — its per-variation
  -- sibling campaign already exists. It brakes instead (V_LOW_STOCK_ADS.serves_only_binding).
  -- An UNKNOWN scope (no row) is NOT treated as dedicated: keep the offer rather than lose it.
  AND COALESCE(sc.n_own_asins, 2) > 1
  AND NOT EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DE_AD_REDIRECTS` r
    WHERE r.campaign_id = v.campaign_id AND r.ad_group_id = v.ad_group_id
      AND r.out_asin = f.out_asin AND r.status = 'ACTIVE');
