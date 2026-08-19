-- V_CAMPAIGN_MISPRICING_SPLIT  (SHADOW / advisory — not wired into Coach or Cube)
-- Splits each campaign's overspend above breakeven CPC into the ADJUSTMENT lever
-- and the BID/auction lever, so the operator knows which knob to turn.
--
-- Built 2026-08-11 to correct the 2026-08-10 pooled CPC = k * bid^0.686 model, which
-- blended placement bid adjustments (a lookup) into an "auction" exponent (a fit).
--
-- Identities:
--   breakeven_cpc = gross_profit / clicks   (= gp_per_order * CVR, algebraically)
--   gp_roas       = breakeven_cpc / actual_cpc
--   overspend     = MAX(0, cost - gross_profit)
--
-- Pass-through theta: a +X% nominal placement adjustment raises realised CPC at that
-- placement by (1 + theta*X), NOT by (1+X) — second-price auction, partial pass-through.
--   theta = 0.587, 95% CI [0.362, 0.823]  (SP top-of-search, 44 campaigns, 13,543 clicks,
--   click-weighted within-campaign regression vs the campaign's own unadjusted OTHER
--   placement, EXCLUDING one +500% brand-defense outlier with extreme leverage).
--   theta is NOT separately estimable for SB (max observed adjustment +30%, CI spans zero)
--   nor for SP detail-page at volume (only 314 adjusted clicks). The SP value is applied
--   to all channels; SB-derived rows are flagged theta_is_extrapolated = TRUE.
--
-- KNOWN LIMIT: fivetran campaign_placement_bidding / sb_campaign_bid_adjustments_by_placement
-- are CURRENT SNAPSHOTS, not history (SB synced first on 2026-08-11). Adjustments are assumed
-- constant across the measurement window. A missing (campaign, placement) row means NO
-- adjustment is set — Amazon's API omits zeros; it never emits percentage = 0 for SP.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_MISPRICING_SPLIT` AS
WITH params AS (
  SELECT 0.587 AS theta_mid, 0.362 AS theta_lo, 0.823 AS theta_hi,
         DATE '2026-04-29' AS d_from, DATE '2026-07-27' AS d_to
),
-- Intrinsic placement premium measured on UNADJUSTED campaigns only (adj = 0),
-- click-weighted geometric mean of cpc_placement / cpc_OTHER within the same campaign.
premium AS (
  SELECT * FROM UNNEST([
    STRUCT('TOP_OF_SEARCH' AS placement, 1.183 AS premium),  -- 27 camps / 4,557 clicks
    STRUCT('DETAIL_PAGE',   0.945),                          -- 43 camps / 12,760 clicks
    STRUCT('OTHER',         1.000),                          -- baseline, never adjustable in SP
    STRUCT('OFF_AMAZON',    0.418),                          -- 13 camps / 1,322 clicks
    STRUCT('HOMEPAGE',      1.000)                           -- SB only, no unadjusted control
  ])
),
-- Latest row per campaign+placement. The source view does NOT dedupe.
adj AS (
  SELECT campaign_id, campaign_source, placement, bid_adjustment_pct
  FROM (
    SELECT CAST(campaign_id AS STRING) AS campaign_id, campaign_source, placement,
           bid_adjustment_pct,
           ROW_NUMBER() OVER (PARTITION BY campaign_id, placement
                              ORDER BY _fivetran_synced DESC) AS rn
    FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_BIDDING`
  )
  WHERE rn = 1
),
placement_perf AS (
  SELECT r.campaign_id, r.campaign_source, r.placement,
         SUM(r.clicks) AS clicks, SUM(r.cost) AS cost
  FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT` r, params p
  WHERE r.report_date BETWEEN p.d_from AND p.d_to
  GROUP BY 1, 2, 3
  HAVING SUM(r.clicks) > 0
),
placement_agg AS (
  SELECT pp.campaign_id,
         SUM(pp.cost) AS cost_placement,
         -- dollars recoverable by setting every adjustment to 0, mix held fixed
         SUM(pp.cost * (1 - 1 / (1 + p.theta_mid * COALESCE(a.bid_adjustment_pct, 0) / 100))) AS adj_recoverable,
         SUM(pp.cost * (1 - 1 / (1 + p.theta_lo  * COALESCE(a.bid_adjustment_pct, 0) / 100))) AS adj_recoverable_lo,
         SUM(pp.cost * (1 - 1 / (1 + p.theta_hi  * COALESCE(a.bid_adjustment_pct, 0) / 100))) AS adj_recoverable_hi,
         -- click-share-weighted intrinsic premium: the placement-MIX lever
         SAFE_DIVIDE(SUM(pp.clicks * COALESCE(pr.premium, 1.0)), SUM(pp.clicks)) AS mix_multiplier,
         SAFE_DIVIDE(SUM(pp.clicks * COALESCE(a.bid_adjustment_pct, 0)), SUM(pp.clicks)) AS wtd_adjustment_pct,
         MAX(COALESCE(a.bid_adjustment_pct, 0)) AS max_adjustment_pct,
         LOGICAL_OR(pp.campaign_source = 'SB' AND COALESCE(a.bid_adjustment_pct, 0) > 0) AS theta_is_extrapolated
  FROM placement_perf pp
  CROSS JOIN params p
  LEFT JOIN adj a
    ON  a.campaign_id     = pp.campaign_id
    AND a.placement       = pp.placement
    AND a.campaign_source = pp.campaign_source
  LEFT JOIN premium pr ON pr.placement = pp.placement
  GROUP BY 1
),
camp AS (
  SELECT f.campaign_id,
         ANY_VALUE(f.campaign_name) AS campaign_name,
         ANY_VALUE(f.campaign_type) AS campaign_type,
         SUM(f.Ads_clicks) AS clicks, SUM(f.Ads_cost) AS cost,
         SUM(f.Ads_orders) AS orders, SUM(f.Ads_sales) AS sales,
         SUM(f.GROSS_PROFIT) AS gross_profit
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f, params p
  WHERE f.date BETWEEN p.d_from AND p.d_to
  GROUP BY 1
  HAVING SUM(f.Ads_clicks) > 0
)
SELECT
  c.campaign_id, c.campaign_name, c.campaign_type,
  -- Family resolved from campaign name. BUNNY / LOLLIBALL are matched FIRST and explicitly:
  -- SP_FACT_AMAZON_ADS.ASIN_BY_CAMPAIGN_NAME has no branch for either and falls through to
  -- ELSE 'B0C1VLXYBP' (White Lollibox). That defect is inert for GP here (tier-cost imputation
  -- keyed on realised sale price wins the COALESCE for 295/304 converting units) but it would
  -- bite if tier cost were ever unavailable.
  CASE
    WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'BUNNY') THEN 'Bunny'
    WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'LOLLIBALL|LOLLI.?BALL|BALLS|\bBALL\b|^BALL') THEN 'LolliBall'
    WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'FRESH') THEN 'Fresh'
    WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'BOTTLE|TRUTH|DARE') THEN 'Bottle'
    WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'LOLLIME|LOLLI.?ME|\bME[- /]|MINT') THEN 'LolliME'
    WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'LOLLIBOX|LOLLI.?BOX|\bBOX\b|^BOX|PILOT-WHITE') THEN 'Lollibox'
    WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'^BRAND|BRAND-STORE') THEN 'Brand(multi)'
    ELSE 'Unmapped'
  END AS family,
  -- M3: defense is strategic and must never be profit-judged. Its adjustments still surface.
  (REGEXP_CONTAINS(UPPER(c.campaign_name), r'DEFENSE')
   OR REGEXP_CONTAINS(UPPER(c.campaign_name), r'^BRAND|BRAND-STORE')) AS is_defense,
  c.clicks, c.cost, c.orders, c.sales, c.gross_profit,
  SAFE_DIVIDE(c.cost,         NULLIF(c.clicks, 0)) AS actual_cpc,
  SAFE_DIVIDE(c.gross_profit, NULLIF(c.clicks, 0)) AS breakeven_cpc,
  SAFE_DIVIDE(c.gross_profit, NULLIF(c.cost,   0)) AS gp_roas,
  GREATEST(0, c.cost - c.gross_profit) AS overspend,
  -- LEVER 1: placement adjustment
  COALESCE(pa.adj_recoverable,    0) AS adj_recoverable,
  COALESCE(pa.adj_recoverable_lo, 0) AS adj_recoverable_lo,
  COALESCE(pa.adj_recoverable_hi, 0) AS adj_recoverable_hi,
  -- LEVER 2: bid / auction — the residual that adjustments cannot reach
  GREATEST(0, GREATEST(0, c.cost - c.gross_profit) - COALESCE(pa.adj_recoverable, 0)) AS bid_recoverable,
  -- LEVER 3: placement mix (informational; overlaps LEVER 2, do not sum with it)
  c.cost * (1 - 1 / NULLIF(pa.mix_multiplier, 0)) AS mix_cost,
  pa.mix_multiplier, pa.wtd_adjustment_pct, pa.max_adjustment_pct,
  COALESCE(pa.theta_is_extrapolated, FALSE) AS theta_is_extrapolated,
  -- counterfactual: every adjustment set to 0
  SAFE_DIVIDE(c.cost - COALESCE(pa.adj_recoverable, 0), NULLIF(c.clicks, 0)) AS cpc_if_no_adjustment,
  SAFE_DIVIDE(c.gross_profit, NULLIF(c.cost - COALESCE(pa.adj_recoverable, 0), 0)) AS gp_roas_if_no_adjustment,
  CASE
    WHEN COALESCE(pa.adj_recoverable, 0) > GREATEST(0, c.cost - c.gross_profit) - COALESCE(pa.adj_recoverable, 0)
      THEN 'ADJUSTMENT'
    WHEN GREATEST(0, c.cost - c.gross_profit) > 0 THEN 'BID'
    ELSE 'NONE'
  END AS primary_lever
FROM camp c
LEFT JOIN placement_agg pa ON pa.campaign_id = c.campaign_id
