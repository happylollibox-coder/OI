-- =============================================
-- Seed data for DIM_STRATEGY_CAMPAIGN_TEMPLATE
-- Campaign recipes: which campaigns to open per strategy
-- =============================================

DELETE FROM `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE` WHERE TRUE;

INSERT INTO `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE`
  (strategy_id, campaign_seq, ad_format, match_type, bidding_strategy,
   bid_min, bid_max, daily_budget, top_of_search_pct, product_page_pct,
   purpose, naming_hint, is_required, notes)
VALUES
-- =============================================
-- BRAND_DEFENSE: Protect brand keywords from competitors
-- =============================================
('BRAND_DEFENSE', 1, 'SP', 'EXACT', 'DOWN_ONLY',
  0.30, 0.75, 25.0, 300, 0,
  'Core brand defense on search results',
  '{PRODUCT}-SP/EXACT (Brand Defense)',
  TRUE, 'Target brand + product name keywords. Low bids since brand terms are cheap.'),

('BRAND_DEFENSE', 2, 'SB_VIDEO', 'EXACT', 'DOWN_ONLY',
  0.25, 0.60, 15.0, 0, 0,
  'Brand video presence above organic results',
  '{PRODUCT}-VIDEO/EXACT (Brand)',
  FALSE, 'Optional: video reinforces brand when shoppers search your name.'),

-- =============================================
-- CATEGORY_CONQUEST: Steal share from competitor brand terms
-- =============================================
('CATEGORY_CONQUEST', 1, 'SP', 'AUTO', 'DOWN_ONLY',
  0.25, 0.75, 25.0, 0, 0,
  'Auto targeting competitor ASINs and close-match terms',
  '{PRODUCT}-SP/AUTO (Conquest)',
  TRUE, 'Let Amazon match to competitor pages and related searches.'),

('CATEGORY_CONQUEST', 2, 'SB_VIDEO', 'BROAD', 'DOWN_ONLY',
  0.30, 0.80, 20.0, 0, 0,
  'Video ads on competitor search terms',
  '{PRODUCT}-VIDEO/BROAD (Conquest)',
  FALSE, 'Optional: video stands out when shoppers search competitor brands.'),

-- =============================================
-- EXACT_BOOST: Heavy investment on proven keywords
-- =============================================
('EXACT_BOOST', 1, 'SP', 'EXACT', 'DOWN_ONLY',
  0.50, 2.00, 40.0, 500, 0,
  'SP exact match for top-of-search dominance on proven terms',
  '{PRODUCT}-SP/EXACT ({keywords summary})',
  TRUE, 'Core traffic driver. High TOS boost to win the top ad spot.'),

('EXACT_BOOST', 2, 'SB_VIDEO', 'EXACT', 'DOWN_ONLY',
  0.50, 1.50, 25.0, 0, 0,
  'SB Video for visual engagement on same proven terms',
  '{PRODUCT}-VIDEO/EXACT ({keywords summary})',
  TRUE, 'Video appears above organic results. Drives high CTR and conversion.'),

('EXACT_BOOST', 3, 'SB_STORE', 'EXACT', 'DOWN_ONLY',
  0.30, 1.00, 15.0, 0, 0,
  'SB Store spotlight for brand awareness on proven terms',
  '{PRODUCT}-STORE/EXACT ({keywords summary})',
  FALSE, 'Optional: drives traffic to brand store. Good for cross-sell.'),

-- =============================================
-- HUNTER: Discover new converting keywords via broad match
-- =============================================
('HUNTER', 1, 'SP', 'BROAD', 'UP_AND_DOWN',
  0.50, 1.50, 30.0, 200, 100,
  'SP broad match to discover new converting terms',
  '{PRODUCT}-SP/BROAD (Hunter)',
  TRUE, 'UP_AND_DOWN lets Amazon adjust bids for high-converting placements.'),

('HUNTER', 2, 'SB_VIDEO', 'BROAD', 'UP_AND_DOWN',
  0.40, 1.20, 20.0, 0, 0,
  'SB Video broad to test visual engagement on new terms',
  '{PRODUCT}-VIDEO/BROAD (Hunter)',
  FALSE, 'Optional: video may convert better than SP on broad discovery terms.'),

-- =============================================
-- LOW_COST_DISCOVERY: Cheap keyword discovery via auto
-- =============================================
('LOW_COST_DISCOVERY', 1, 'SP', 'AUTO', 'DOWN_ONLY',
  0.10, 0.35, 15.0, 0, 0,
  'SP Auto for ultra-low-cost keyword discovery',
  '{PRODUCT}-SP/AUTO (Discovery)',
  TRUE, 'Very low bids. Goal: find keywords to promote to EXACT_BOOST later.'),

-- =============================================
-- NEW_LAUNCH: Full-funnel for new products (< 90 days)
-- =============================================
('NEW_LAUNCH', 1, 'SP', 'EXACT', 'DOWN_ONLY',
  0.75, 2.50, 45.0, 400, 200,
  'SP exact on core keywords to build early sales velocity',
  '{PRODUCT}-SP/EXACT (Launch)',
  TRUE, 'High aggression to build initial ranking. TOS + Product Page boost.'),

('NEW_LAUNCH', 2, 'SP', 'AUTO', 'UP_AND_DOWN',
  0.50, 1.50, 25.0, 0, 0,
  'SP Auto to discover which keywords convert for new product',
  '{PRODUCT}-SP/AUTO (Launch Discovery)',
  TRUE, 'Auto discovers keywords you did not anticipate.'),

('NEW_LAUNCH', 3, 'SB_VIDEO', 'BROAD', 'UP_AND_DOWN',
  0.60, 2.00, 30.0, 0, 0,
  'SB Video broad for brand awareness and video engagement',
  '{PRODUCT}-VIDEO/BROAD (Launch)',
  TRUE, 'Video is critical for new products to build recognition fast.'),

('NEW_LAUNCH', 4, 'SB_STORE', 'BROAD', 'DOWN_ONLY',
  0.40, 1.50, 15.0, 0, 0,
  'SB Store to drive store traffic and cross-sell',
  '{PRODUCT}-STORE/BROAD (Launch)',
  FALSE, 'Optional: brand store drives trust for unknown new products.'),

-- =============================================
-- PRODUCT_DEFENSE: Protect your product detail pages
-- =============================================
('PRODUCT_DEFENSE', 1, 'SP', 'PRODUCT_TARGETING', 'DOWN_ONLY',
  0.30, 0.75, 20.0, 0, 300,
  'SP product targeting to defend your own detail pages',
  '{PRODUCT}-SP/PT (Defense)',
  TRUE, 'High Product Page boost. Prevents competitors from poaching your shoppers.'),

-- =============================================
-- RETARGETING: Re-engage past visitors
-- =============================================
('RETARGETING', 1, 'SB_VIDEO', 'BROAD', 'DOWN_ONLY',
  0.30, 1.00, 20.0, 100, 100,
  'SB Video retargeting past visitors with engaging video',
  '{PRODUCT}-VIDEO/BROAD (Retarget)',
  TRUE, 'Video re-engages shoppers who viewed your product before.'),

('RETARGETING', 2, 'SB_STORE', 'BROAD', 'DOWN_ONLY',
  0.25, 0.75, 15.0, 0, 0,
  'SB Store retargeting to drive return visits to brand store',
  '{PRODUCT}-STORE/BROAD (Retarget)',
  FALSE, 'Optional: store visit reminds past visitors of full product range.'),

-- =============================================
-- SEASONAL_PUSH: Maximum visibility during peak season
-- =============================================
('SEASONAL_PUSH', 1, 'SP', 'EXACT', 'UP_AND_DOWN',
  0.75, 3.00, 50.0, 500, 200,
  'SP exact on seasonal keywords with maximum aggression',
  '{PRODUCT}-SP/EXACT (Season)',
  TRUE, 'UP_AND_DOWN + high TOS/PP. Seasonal demand justifies high bids.'),

('SEASONAL_PUSH', 2, 'SB_VIDEO', 'EXACT', 'UP_AND_DOWN',
  0.75, 2.50, 35.0, 0, 0,
  'SB Video with seasonal creative on exact seasonal terms',
  '{PRODUCT}-VIDEO/EXACT (Season)',
  TRUE, 'Seasonal video creative is critical. Update video before peak starts.'),

('SEASONAL_PUSH', 3, 'SB_STORE', 'BROAD', 'UP_AND_DOWN',
  0.50, 2.00, 15.0, 0, 0,
  'SB Store broad for seasonal brand store spotlight',
  '{PRODUCT}-STORE/BROAD (Season)',
  FALSE, 'Optional: seasonal store page drives impulse cross-sell.'),

-- =============================================
-- TOS_DOMINATION: Win the top ad spot on key terms
-- =============================================
('TOS_DOMINATION', 1, 'SP', 'EXACT', 'DOWN_ONLY',
  1.00, 3.00, 50.0, 900, 0,
  'SP exact with extreme TOS boost to lock top ad position',
  '{PRODUCT}-SP/EXACT (TOS)',
  TRUE, '900% TOS boost. All spend goes to position 1 on search results.'),

('TOS_DOMINATION', 2, 'SB_VIDEO', 'EXACT', 'DOWN_ONLY',
  0.75, 2.50, 25.0, 0, 0,
  'SB Video exact for the video slot above organic results',
  '{PRODUCT}-VIDEO/EXACT (TOS)',
  TRUE, 'SP wins the top ad row, SB Video wins the video slot. Double presence.');
