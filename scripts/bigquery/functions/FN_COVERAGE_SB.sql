-- FN_COVERAGE_SB(win_start, win_end, peak_only) — Sponsored Brands rows for the coverage cockpit.
--
-- WHY THIS EXISTS: every other coverage function derives the asin<->campaign link from
-- V_SRC_AmazonAds_advertised_product, which is the Sponsored PRODUCTS advertised-product report.
-- Sponsored Brands campaigns do not report per-advertised-ASIN there, so before this function the
-- entire SB portfolio (16 enabled campaigns, ~$27.5k/90d) was invisible to every cell, count and
-- P&L rollup — Ori 2026-07-23 ("where are my boost exacts campaigns").
--
-- Emits rows shaped like FN_COVERAGE_CAMPAIGN's `live_base` source (parent_name, asin,
-- gp_per_unit, campaign_id, impressions, clicks, cost, units) so callers can UNION it in and apply
-- their own cell_key logic. One row per (campaign_id, asin) in the window.
--
-- SOURCES (SB splits its metrics across two reports):
--   units/sales -> fivetran-hl.amazon_ads.sb_purchased_product — the ONLY SB table Fivetran actually
--     populates with units (units_sold_14_d is present-but-NULL on sb_campaign_report / ad_group /
--     keyword / ad / placement, and all-zero on target_report). It carries campaign_id +
--     purchased_asin + date, giving REAL per-ASIN attribution — no family-average approximation.
--     attribution_type='Promoted' only: 'Brand Halo' is sales of OTHER products the ad pulled in
--     (99 units all-time) and would double-count against the promoted product.
--     NOTE: purchased_asin is the ASIN actually BOUGHT, not the one advertised (SB brand/video ads
--     have no single advertised ASIN). For profit this is the meaningful link — margin is earned on
--     what sold — but it is a different basis than the SP side's "what was advertised".
--   cost/clicks/impressions -> fivetran-hl.amazon_ads.sb_campaign_report, which is CAMPAIGN-grain
--     only (no ASIN split exists for SB spend). Allocated across the window's purchased ASINs
--     PRO-RATA BY UNITS so Σ(allocated cost) == campaign cost exactly.
--
-- FAMILY ATTRIBUTION (Ori 2026-07-26): a campaign BELONGS to the family of the product it
-- ADVERTISES (sb_ad_report.advertised_asin, clicks-weighted majority over 365d) — "FRESH -
-- SB\BROAD" is Fresh even in a week when its clicks bought mostly Bunny keychains. The
-- purchased-ASIN split stays untouched for PROFIT (margin is earned where it is earned);
-- only the coverage-belonging flag and the no-conversion fallback use the advertised family.
-- Campaigns with no advertised ASIN (store-spotlight ads land on subpages) keep the old
-- purchased-dominance rule.
--
-- NO-CONVERSION FALLBACK: a campaign can spend in the window without converting (common on short
-- windows like today/yesterday/7d). Pro-rata would divide by zero units and the spend would vanish —
-- the exact bug this function fixes. Those campaigns emit ONE row carrying the full cost with
-- units=0 and the family resolved from DE_CAMPAIGN_FAMILY (the curated campaign->family override for
-- ASIN-blind SB/video/store campaigns), falling back to its dominant purchased family over 12 months.
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_COVERAGE_SB`(win_start DATE, win_end DATE, peak_only BOOL) AS (
WITH
peak_dates AS (
  SELECT DISTINCT d AS date
  FROM `onyga-482313`.OI.DIM_US_HOLIDAYS h, UNNEST(GENERATE_DATE_ARRAY(h.boost_start, h.cooldown_end)) d
  WHERE h.category = 'gift_season'
),
-- ── Own sellable products + per-ASIN gross profit per unit (same basis as the SP path) ──
prod AS (
  SELECT dp.asin, dp.parent_name,
    ROUND(lc.price - COALESCE(ch.TOTAL_COST_PER_UNIT, 0), 2) AS gp_per_unit
  FROM `onyga-482313`.OI.DIM_PRODUCT dp
  LEFT JOIN (
    SELECT asin1, price FROM `onyga-482313`.OI.V_DIM_LISTING_CURRENT
    QUALIFY ROW_NUMBER() OVER (PARTITION BY asin1 ORDER BY price DESC) = 1
  ) lc ON lc.asin1 = dp.asin
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT FROM `onyga-482313`.OI.DIM_COSTS_HISTORY
    WHERE end_date IS NULL OR end_date >= CURRENT_DATE()
    QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
  ) ch ON ch.asin = dp.asin
  WHERE dp.parent_name IS NOT NULL AND dp.parent_name != 'UNKNOWN' AND dp.is_active = true
),
-- ── SB spend/traffic per campaign over the window (campaign grain — no ASIN split exists) ──
-- (wrapped: `SUM(cost) AS cost` shadows the raw column, so a HAVING on it would be read as
--  SUM(SUM(cost)) — "aggregations of aggregations". Filter in an outer SELECT instead.)
sb_cost AS (
  SELECT campaign_id, impressions, clicks, cost, last_seen
  FROM (
    SELECT CAST(campaign_id AS STRING) AS campaign_id,
      CAST(SUM(impressions) AS INT64) AS impressions,
      CAST(SUM(clicks) AS INT64) AS clicks,
      SUM(cost) AS cost,
      MAX(report_date) AS last_seen
    FROM `fivetran-hl.amazon_ads.sb_campaign_report`
    WHERE report_date BETWEEN win_start AND win_end
      AND (NOT peak_only OR report_date IN (SELECT date FROM peak_dates))
    GROUP BY 1
  )
  WHERE cost > 0
),
-- ── SB units per (campaign, purchased ASIN) over the window, own products only ──
sb_units AS (
  SELECT CAST(pp.campaign_id AS STRING) AS campaign_id,
    pp.purchased_asin AS asin,
    p.parent_name, p.gp_per_unit,
    CAST(SUM(pp.units_sold_14_d) AS INT64) AS units
  FROM `fivetran-hl.amazon_ads.sb_purchased_product` pp
  JOIN prod p ON p.asin = pp.purchased_asin
  WHERE pp.date BETWEEN win_start AND win_end
    AND (NOT peak_only OR pp.date IN (SELECT date FROM peak_dates))
    AND pp.attribution_type = 'Promoted'
  GROUP BY 1, 2, 3, 4
  HAVING SUM(pp.units_sold_14_d) > 0
),
unit_tot AS (
  SELECT campaign_id, SUM(units) AS total_units FROM sb_units GROUP BY 1
),
-- ── Advertised family per campaign: what the ad SHOWS, clicks-weighted, stable 365d ──
adv_fam AS (
  SELECT campaign_id, parent_name, asin FROM (
    SELECT CAST(ar.campaign_id AS STRING) AS campaign_id, p.parent_name, p.asin,
      ROW_NUMBER() OVER (PARTITION BY CAST(ar.campaign_id AS STRING)
                         ORDER BY SUM(ar.clicks) DESC) AS rn
    FROM `onyga-482313`.OI.V_SRC_AmazonAds_sb_ad_report ar
    JOIN prod p ON p.asin = ar.advertised_asin
    WHERE ar.report_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    GROUP BY 1, 2, 3
  ) WHERE rn = 1
),
-- ── Campaign -> family fallback for spend that converted nothing in the window ──
fam_fallback AS (
  -- Dominant PURCHASED family wins over DE_CAMPAIGN_FAMILY: the latter can say 'Store' (a virtual
  -- family with no products, hence no coverage cell), which would drop the spend again. Real
  -- product families always have a cell, so prefer what the campaign actually sells.
  SELECT c.campaign_id,
    COALESCE(af.parent_name, dom.parent_name, dcf.parent_name) AS parent_name
  FROM sb_cost c
  LEFT JOIN adv_fam af ON af.campaign_id = c.campaign_id
  LEFT JOIN `onyga-482313`.OI.DE_CAMPAIGN_FAMILY dcf
    ON CAST(dcf.campaign_id AS STRING) = c.campaign_id
  LEFT JOIN (
    SELECT campaign_id, parent_name FROM (
      SELECT campaign_id, parent_name,
        ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY fam_units DESC) AS rn
      FROM (
        SELECT CAST(pp.campaign_id AS STRING) AS campaign_id, p.parent_name,
          SUM(pp.units_sold_14_d) AS fam_units
        FROM `fivetran-hl.amazon_ads.sb_purchased_product` pp
        JOIN prod p ON p.asin = pp.purchased_asin
        WHERE pp.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
          AND pp.attribution_type = 'Promoted'
        GROUP BY 1, 2
      )
    ) WHERE rn = 1
  ) dom ON dom.campaign_id = c.campaign_id
)
-- ── Converted: cost/clicks/impressions split across purchased ASINs pro-rata by units ──
SELECT
  u.parent_name,
  u.asin,
  u.gp_per_unit,
  u.campaign_id,
  CAST(ROUND(c.impressions * SAFE_DIVIDE(u.units, t.total_units)) AS INT64) AS impressions,
  CAST(ROUND(c.clicks      * SAFE_DIVIDE(u.units, t.total_units)) AS INT64) AS clicks,
  c.cost * SAFE_DIVIDE(u.units, t.total_units) AS cost,
  u.units,
  c.last_seen,
  -- is_primary_family: does this campaign meaningfully BELONG to the family, or did it merely sell
  -- a stray unit into it? Purchased-ASIN splitting is right for PROFIT (margin is earned where it
  -- is earned) but wrong for COVERAGE — 1 Bottle unit out of 92 made FRESH - SB\\BROAD look like
  -- Bottle's Broad Spotlight campaign (Ori 2026-07-23). Dominant family, or >=20% of the
  -- campaign's units, counts as belonging. FN_COVERAGE_CAMPAIGN/_DETAIL filter on this;
  -- FN_COVERAGE_CAMPAIGN_PROFIT ignores it so no spend goes missing from the P&L.
  CASE WHEN af.parent_name IS NOT NULL THEN u.parent_name = af.parent_name
       ELSE (SAFE_DIVIDE(u.units, t.total_units) >= 0.20
             OR u.units = MAX(u.units) OVER (PARTITION BY u.campaign_id))
  END AS is_primary_family
FROM sb_units u
JOIN unit_tot t ON t.campaign_id = u.campaign_id
JOIN sb_cost  c ON c.campaign_id = u.campaign_id
LEFT JOIN adv_fam af ON af.campaign_id = u.campaign_id

UNION ALL

-- ── Spent-but-no-conversions: keep the whole spend visible against its home family ──
SELECT
  f.parent_name,
  CAST(NULL AS STRING) AS asin,
  0.0 AS gp_per_unit,
  c.campaign_id,
  c.impressions,
  c.clicks,
  c.cost,
  0 AS units,
  c.last_seen,
  TRUE AS is_primary_family   -- no conversions in-window: the home family IS the only attribution
FROM sb_cost c
JOIN fam_fallback f ON f.campaign_id = c.campaign_id
WHERE c.campaign_id NOT IN (SELECT campaign_id FROM unit_tot)
  AND f.parent_name IS NOT NULL

UNION ALL

-- ── Advertised-family visibility row: the campaign converted in-window, but nothing in the
-- family it advertises. Without this row the campaign vanishes from its own family's cell
-- while its stray sales sit flagged non-primary. Zero cost/units — cost is already fully
-- allocated to the purchased rows, so the P&L stays exact.
SELECT
  af.parent_name,
  af.asin,
  0.0 AS gp_per_unit,
  c.campaign_id,
  0 AS impressions,
  0 AS clicks,
  0.0 AS cost,
  0 AS units,
  c.last_seen,
  TRUE AS is_primary_family
FROM sb_cost c
JOIN adv_fam af ON af.campaign_id = c.campaign_id
WHERE c.campaign_id IN (SELECT campaign_id FROM unit_tot)
  AND NOT EXISTS (
    SELECT 1 FROM sb_units u
    WHERE u.campaign_id = c.campaign_id AND u.parent_name = af.parent_name)
);
