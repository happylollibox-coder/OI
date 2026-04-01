-- =============================================
-- OI Database Project - V_CAMPAIGN_PLACEMENT_BIDDING View
-- =============================================
--
-- Purpose: Unified placement bid adjustment settings combining
--          Sponsored Products and Sponsored Brands bid adjustments.
--          Shows what % bid increase/decrease is set per placement per campaign.
--
-- Sources:
--   - fivetran-hl.amazon_ads.campaign_placement_bidding (SP: Sponsored Products)
--   - fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_by_placement (SB: Sponsored Brands / Video)
--
-- SP placement values:
--   PLACEMENT_TOP → TOP_OF_SEARCH
--   PLACEMENT_PRODUCT_PAGE → DETAIL_PAGE
--   SITE_AMAZON_BUSINESS → AMAZON_BUSINESS
--
-- SB placement values:
--   TOP_OF_SEARCH, DETAIL_PAGE, HOME, OTHER
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_BIDDING`
AS

-- Sponsored Products bid adjustments
SELECT
  sp.campaign_id,
  'SP' as campaign_source,
  -- Normalize placement names
  CASE sp.placement
    WHEN 'PLACEMENT_TOP' THEN 'TOP_OF_SEARCH'
    WHEN 'PLACEMENT_PRODUCT_PAGE' THEN 'DETAIL_PAGE'
    WHEN 'SITE_AMAZON_BUSINESS' THEN 'AMAZON_BUSINESS'
    ELSE sp.placement
  END as placement,
  sp.placement as placement_raw,
  sp.percentage as bid_adjustment_pct,
  sp._fivetran_synced
FROM `fivetran-hl`.amazon_ads.campaign_placement_bidding sp

UNION ALL

-- Sponsored Brands bid adjustments
SELECT
  sb.campaign_id,
  'SB' as campaign_source,
  -- Normalize placement names
  CASE sb.placement
    WHEN 'TOP_OF_SEARCH' THEN 'TOP_OF_SEARCH'
    WHEN 'DETAIL_PAGE' THEN 'DETAIL_PAGE'
    WHEN 'HOME' THEN 'HOMEPAGE'
    WHEN 'OTHER' THEN 'OTHER'
    ELSE sb.placement
  END as placement,
  sb.placement as placement_raw,
  sb.percentage as bid_adjustment_pct,
  sb._fivetran_synced
FROM `fivetran-hl`.amazon_ads.sb_campaign_bid_adjustments_by_placement sb;
