-- =============================================
-- V_DIM_CAMPAIGN_FAMILY — THE canonical campaign→family source.
-- =============================================
--
-- Purpose: one row per campaign_id (STRING) for ALL campaigns in V_DIM_CAMPAIGN_CURRENT
--          (ENABLED + PAUSED + ARCHIVED), carrying the family (parent_name) and where it
--          came from. Family rollups keyed on this view survive campaign renames, because
--          the id is the key and the manual override + behavioral ASIN beat name-parsing.
--
-- PRECEDENCE (decided 2026-08-01, Task D "canonical campaign->family source"):
--   1. 'manual'     — DE_CAMPAIGN_FAMILY (Admin "Campaign Mapping" panel / backend override).
--                     A deliberate human assignment ALWAYS wins. Measured on 2026-08-01:
--                     manual and the ASIN chain disagree on exactly 4 campaigns
--                     (BUNNY-VIDEO/BROAD (Hunter) → Bunny, 2× BRAND-STORE/BROAD → Store,
--                     Brand - Auto Collection → Store; the chain says Lollibox for all 4
--                     because their spend rows resolve to Lollibox ASINs). Those 4 are the
--                     ASIN-blind brand/video campaigns DE_CAMPAIGN_FAMILY was created for,
--                     so manual-wins is the correct precedence, not just a tie-break.
--   2. 'asin_chain' — dominant own-product family by LIFETIME ad spend. Per FACT row the
--                     family prefers most_advertised_asin_impressions (behavioral — survives
--                     renames) and falls back to name-parsed ASIN_BY_CAMPAIGN_NAME. The
--                     fallback is at FAMILY level, not ASIN level: video/SB rows carry the
--                     literal string 'Unknown' in most_advertised_asin_impressions, so the
--                     COALESCE-the-ASIN-strings pattern used elsewhere silently loses those
--                     campaigns (282 vs 294 campaigns covered, measured 2026-08-01).
--                     Only DIM_PRODUCT rows with parent_name IS NOT NULL count ("own"
--                     products; DIM_PRODUCT also holds competitor ASINs with NULL family).
--                     Ties broken by parent_name for determinism.
--   3. NULL         — neither source knows. NO 'Unknown' catch-all here (unlike
--                     V_CAMPAIGN_FAMILY_MAP, whose 'Unknown' exists only as the budget
--                     waterfall's coverage guarantee). Callers decide their own fallback.
--
-- Measured coverage (2026-08-01, 1113 campaigns in V_DIM_CAMPAIGN_CURRENT):
--   manual 12 · asin_chain 294 · NULL 807 (783 ARCHIVED + 19 PAUSED + 5 ENABLED;
--   the 5 ENABLED are brand-new Back-to-School campaigns with no delivery yet — they
--   resolve as soon as FACT_AMAZON_ADS has rows, or immediately via a DE row).
--
-- Debug columns: campaign_name + campaign_state (do NOT parse the name downstream),
--   asin_chain_parent_name (what the chain says even when manual wins — audit the 4
--   disagreements with: WHERE family_source='manual' AND parent_name != asin_chain_parent_name).
--
-- Grain: one row per campaign_id. Sources: V_DIM_CAMPAIGN_CURRENT (base, row count must
-- match), DE_CAMPAIGN_FAMILY, FACT_AMAZON_ADS + DIM_PRODUCT.
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_DIM_CAMPAIGN_FAMILY` AS
WITH fam_rows AS (
  -- Per FACT row: resolve each candidate ASIN to an OWN-product family, prefer the
  -- behavioral (impressions) ASIN, fall back to the name-parsed one at family level.
  SELECT
    a.campaign_id,
    COALESCE(pi.parent_name, pn.parent_name) AS fam,
    a.Ads_cost AS cost
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` pi
    ON pi.asin = a.most_advertised_asin_impressions AND pi.parent_name IS NOT NULL
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` pn
    ON pn.asin = a.ASIN_BY_CAMPAIGN_NAME AND pn.parent_name IS NOT NULL
  WHERE COALESCE(pi.parent_name, pn.parent_name) IS NOT NULL
),
asin_chain AS (
  -- Dominant family per campaign by lifetime spend; deterministic tie-break.
  SELECT campaign_id, fam AS parent_name
  FROM (
    SELECT campaign_id, fam,
      ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY SUM(cost) DESC, fam) AS rn
    FROM fam_rows
    GROUP BY campaign_id, fam
  )
  WHERE rn = 1
)
SELECT
  c.campaign_id,
  c.campaign_name,                                   -- debug only; never parse downstream
  c.campaign_state,                                  -- debug/filter convenience
  COALESCE(de.parent_name, ac.parent_name) AS parent_name,
  CASE
    WHEN de.parent_name IS NOT NULL THEN 'manual'
    WHEN ac.parent_name IS NOT NULL THEN 'asin_chain'
  END AS family_source,
  ac.parent_name AS asin_chain_parent_name           -- audit: chain opinion even when manual wins
FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c
LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_FAMILY` de ON de.campaign_id = c.campaign_id
LEFT JOIN asin_chain ac ON ac.campaign_id = c.campaign_id;
