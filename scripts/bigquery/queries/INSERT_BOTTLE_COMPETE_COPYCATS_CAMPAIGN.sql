-- =============================================
-- Register new campaign "BOTTLE- COMPETE (Copycats)" in OI
-- =============================================
-- Run this AFTER creating the campaign in Amazon Advertising.
-- Option A: Use PENDING_ prefix — SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS will resolve
--           campaign_id by matching campaign_name when Fivetran syncs the campaign.
-- Option B: Replace PENDING_BOTTLE_COMPETE_COPYCATS with actual campaign_id from Amazon.
-- =============================================
-- Config: Daily budget 25 (or 20), Dynamic bids – down only, Product targeting (not keywords)
-- =============================================

INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` (
  experiment_id,
  campaign_id,
  campaign_name,
  notes
)
VALUES (
  'TRUTH_OR_DARE_CATEGORY_CONQUEST_GIFT_GENERAL',
  'PENDING_BOTTLE_COMPETE_COPYCATS',   -- Auto-resolved by SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS
  'BOTTLE- COMPETE (Copycats)',
  'SP product targeting on competitor ASINs (party games / truth or dare). Daily budget: $25 (or $20). Bidding: Dynamic bids – down only. Targeting: Product targeting (not keywords). Advertised ASIN: B0F4KCCSWN.'
);
