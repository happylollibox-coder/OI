-- =============================================
-- OI Database Project - DE_COACH_THRESHOLDS Table
-- =============================================
--
-- Purpose: User-editable thresholds for the Ads Coach decision engine.
--          Controls when keywords are NEGATED, REDUCED, SCALED, bid-capped, etc.
--          Values resolve per strategy x coach_mode, with GLOBAL/GUARDIAN fallbacks.
--
-- Resolution order (highest priority first), see V_ADS_COACH.sql:
--   1. strategy_id + coach_mode
--   2. GLOBAL + coach_mode
--   3. strategy_id + GUARDIAN
--   4. GLOBAL + GUARDIAN
--   5. Hardcoded fallback in V_ADS_COACH SQL
--
-- NOTE: This seed is a FAITHFUL SNAPSHOT of the live table, regenerated 2026-06-16
--       (112 rows, coach_mode-aware), plus 9 LAUNCH_* keys added 2026-06-19 for the
--       new-campaign launch track (121 rows). The live table is edited via the Flask API
--       and direct DML; keep this file in sync after any live change so a re-seed is safe.
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_COACH_THRESHOLDS` (
  threshold_key     STRING NOT NULL,          -- e.g. 'PROFITABLE_ROAS'
  strategy_id       STRING NOT NULL,          -- e.g. 'EXACT_BOOST' or 'GLOBAL'
  product_family    STRING,                   -- NULL = all families
  threshold_value   FLOAT64 NOT NULL,         -- the numeric threshold value
  description       STRING,                   -- human-readable explanation
  suggested_value   FLOAT64,                  -- system-suggested new value
  suggested_at      DATETIME,                 -- when the suggestion was generated
  suggestion_reason STRING,                   -- why the system suggests this change
  peak_multiplier   FLOAT64 DEFAULT 1.0,      -- multiplier during PEAK phase
  boost_peak_multiplier FLOAT64 DEFAULT 1.0,  -- multiplier during BOOST_PEAK
  source            STRING DEFAULT 'MANUAL',  -- 'MANUAL', 'AUTO_SUGGESTED', 'SEED'
  updated_at        DATETIME DEFAULT CURRENT_DATETIME(),
  updated_by        STRING,
  coach_mode        STRING                    -- 'GUARDIAN' / 'BLITZ' / 'COOLDOWN'
);

-- =============================================
-- SEED DATA (snapshot of live, 112 rows)
-- =============================================
DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` WHERE TRUE;

INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, coach_mode, threshold_value, description, peak_multiplier, boost_peak_multiplier, source)
VALUES

  -- GUARDIAN x GLOBAL
  ('BID_CAP_SUGGESTION', 'GLOBAL', 'GUARDIAN', 2, 'Hard ceiling on any recommended bid ($)', 1, 1, 'MANUAL'),
  ('CONFIDENCE_CLICKS_HIGH', 'GLOBAL', 'GUARDIAN', 50, 'HIGH confidence requires this many clicks', 1, 1, 'SEED'),
  ('CONFIDENCE_CLICKS_MEDIUM', 'GLOBAL', 'GUARDIAN', 20, 'MEDIUM confidence requires this many clicks', 1, 1, 'SEED'),
  ('CONFIDENCE_DAYS_HIGH', 'GLOBAL', 'GUARDIAN', 14, 'HIGH confidence requires this many days of data', 1, 1, 'SEED'),
  ('CONFIDENCE_DAYS_MEDIUM', 'GLOBAL', 'GUARDIAN', 7, 'MEDIUM confidence requires this many days', 1, 1, 'SEED'),
  ('DEFENSE_DOMINATE_IS_PCT', 'GLOBAL', 'GUARDIAN', 50, 'BRAND_DEFENSE: stop bidding up once SQP impression share >= this %', 1, 1, 'MANUAL'),
  ('HALO_ROAS', 'GLOBAL', 'GUARDIAN', 0.5, 'Keep keyword if organic halo detected and Net ROAS >= this', 1, 1, 'SEED'),
  ('INSUFFICIENT_DATA_CLICKS', 'GLOBAL', 'GUARDIAN', 15, 'Skip keyword if fewer than this many clicks in 4 weeks', 1, 1, 'SEED'),
  ('NEGATE_ROAS_THRESHOLD', 'GLOBAL', 'GUARDIAN', 0.5, 'Negate keyword if Net ROAS is below this', 1, 1, 'SEED'),
  ('NEGATE_SPEND_THRESHOLD', 'GLOBAL', 'GUARDIAN', 20, 'Only negate if spend exceeds this amount', 1, 1, 'SEED'),
  ('PROFITABLE_ROAS', 'GLOBAL', 'GUARDIAN', 1.1, 'Keyword is profitable (KEEP) at this Net ROAS or above', 1, 1, 'SEED'),
  ('PROMOTE_MIN_ORDERS', 'GLOBAL', 'GUARDIAN', 4, 'Min 8w orders to promote a search term to EXACT_BOOST', 1, 1, 'manual'),
  ('PROMOTE_MIN_SQP_VOLUME', 'GLOBAL', 'GUARDIAN', 500, 'Min SQP weekly search volume to justify promoting to EXACT_BOOST', 1, 1, 'coach_v2'),
  ('REDUCE_BID_ROAS', 'GLOBAL', 'GUARDIAN', 0.7, 'Reduce bid if Net ROAS is below this', 1, 1, 'SEED'),
  ('SCALE_UP_ROAS', 'GLOBAL', 'GUARDIAN', 2, 'Scale up if Net ROAS exceeds this', 1, 1, 'SEED'),
  ('SCALE_UP_SPEND_CAP', 'GLOBAL', 'GUARDIAN', 50, 'Only scale up if spend is below this cap', 1, 1, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'GLOBAL', 'GUARDIAN', 15, 'Flag as wasted if spend exceeds this with 0 orders', 1, 1, 'SEED'),
  ('CROSS_SELL_MIN_ORDERS', 'GLOBAL', 'GUARDIAN', 3, 'Min A->B cross-purchase orders (30d) to recommend a self-cross-sell product target', 1, 1, 'MANUAL'),

  -- Launch track (new-campaign aggressive→reduce→decide lifecycle; keyed off campaign age, applies globally)
  ('LAUNCH_WINDOW_DAYS', 'GLOBAL', 'GUARDIAN', 30, 'Campaign age (days) under which a keyword is on the new-campaign launch track', 1, 1, 'SEED'),
  ('LAUNCH_BID_MULT', 'GLOBAL', 'GUARDIAN', 1.7, 'Aggressive launch bid = anchor CPC x this multiplier', 1, 1, 'SEED'),
  ('LAUNCH_BID_CEILING', 'GLOBAL', 'GUARDIAN', 1.4, 'Hard max ($) on any launch-track bid', 1, 1, 'SEED'),
  ('LAUNCH_COLD_BID', 'GLOBAL', 'GUARDIAN', 1.2, 'Flat launch bid ($) when no CPC anchor exists (never-advertised keyword)', 1, 1, 'SEED'),
  ('LAUNCH_STEP_DOWN_PCT', 'GLOBAL', 'GUARDIAN', 0.2, 'Bid reduction fraction per reduce checkpoint (0.2 = -20%)', 1, 1, 'SEED'),
  ('LAUNCH_CHECKPOINT_CLICKS', 'GLOBAL', 'GUARDIAN', 15, 'Clicks per launch-track decision checkpoint', 1, 1, 'SEED'),
  ('LAUNCH_NEGATE_CLICKS', 'GLOBAL', 'GUARDIAN', 45, 'Launch-track clicks with 0 orders that trigger negate', 1, 1, 'SEED'),
  ('LAUNCH_WINNER_ORDERS', 'GLOBAL', 'GUARDIAN', 2, 'Orders in the winner window to graduate off the launch track', 1, 1, 'SEED'),
  ('LAUNCH_WINNER_DAYS', 'GLOBAL', 'GUARDIAN', 3, 'Trailing days (ending at ads watermark) for the launch winner check', 1, 1, 'SEED'),

  -- Money-bleeder fit-gated rule (0-order bleeders: research-fit → reduce & keep, not-fit → negate)
  ('BLEEDER_FIT_RANK', 'GLOBAL', 'GUARDIAN', 50, 'Research rank at/above which a 0-order bleeder is REDUCED (kept) instead of negated', 1, 1, 'SEED'),
  ('BLEEDER_REDUCE_PCT', 'GLOBAL', 'GUARDIAN', 0.4, 'Aggressive bid cut fraction for a fit money-bleeder (0.4 = -40%)', 1, 1, 'SEED'),
  ('BLEEDER_MIN_CLICKS', 'GLOBAL', 'GUARDIAN', 20, 'Min 4w clicks for a 0-order term to count as an actionable money bleeder', 1, 1, 'SEED'),

  -- GUARDIAN x BRAND_DEFENSE
  ('BID_CAP_SUGGESTION', 'BRAND_DEFENSE', 'GUARDIAN', 2, 'Bid cap suggestion based on experiment CPC analysis', 1, 1, 'AUTO_SUGGEST'),
  ('CONFIDENCE_DAYS_HIGH', 'BRAND_DEFENSE', 'GUARDIAN', 7, 'Brand terms have high volume, 7 days is enough', 1, 1, 'SEED'),
  ('INSUFFICIENT_DATA_CLICKS', 'BRAND_DEFENSE', 'GUARDIAN', 10, 'Brand terms are cheap — 10 clicks is enough', 1, 1, 'SEED'),
  ('NEGATE_ROAS_THRESHOLD', 'BRAND_DEFENSE', 'GUARDIAN', -999, 'Never negate brand terms — defend at any cost', 1, 1, 'SEED'),
  ('PROFITABLE_ROAS', 'BRAND_DEFENSE', 'GUARDIAN', 3, 'Below 3x on brand is underperforming', 1, 1, 'SEED'),
  ('SCALE_UP_ROAS', 'BRAND_DEFENSE', 'GUARDIAN', 5, 'Brand terms should be 5x+ Net ROAS to scale TOS boost', 1, 1, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'BRAND_DEFENSE', 'GUARDIAN', 5, '$5 with 0 orders on brand = something is wrong', 1, 1, 'SEED'),

  -- GUARDIAN x CATEGORY_CONQUEST
  ('BID_CAP_SUGGESTION', 'CATEGORY_CONQUEST', 'GUARDIAN', 2, 'Bid cap suggestion based on experiment CPC analysis', 1, 1, 'AUTO_SUGGEST'),
  ('INSUFFICIENT_DATA_CLICKS', 'CATEGORY_CONQUEST', 'GUARDIAN', 15, 'Standard click count for category terms', 1, 1, 'SEED'),
  ('NEGATE_ROAS_THRESHOLD', 'CATEGORY_CONQUEST', 'GUARDIAN', 0.3, 'Lenient — new category terms start slow', 1, 1, 'SEED'),
  ('PROFITABLE_ROAS', 'CATEGORY_CONQUEST', 'GUARDIAN', 1.1, 'Accept lower ROAS if SQP share is growing', 1, 1, 'MANUAL'),
  ('SCALE_UP_ROAS', 'CATEGORY_CONQUEST', 'GUARDIAN', 1, 'If profitable on category term, invest more', 1, 1, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'CATEGORY_CONQUEST', 'GUARDIAN', 20, 'Category terms need more time to prove out', 1.5, 1, 'SEED'),

  -- GUARDIAN x COMPETITOR_CONQUEST
  ('BID_CAP_SUGGESTION', 'COMPETITOR_CONQUEST', 'GUARDIAN', 2, 'Bid cap suggestion based on experiment CPC analysis', 1, 1, 'AUTO_SUGGEST'),

  -- GUARDIAN x EXACT_BOOST
  ('BID_CAP_SUGGESTION', 'EXACT_BOOST', 'GUARDIAN', 2, 'Bid cap suggestion based on experiment CPC analysis', 1, 1, 'AUTO_SUGGEST'),
  ('INSUFFICIENT_DATA_CLICKS', 'EXACT_BOOST', 'GUARDIAN', 20, 'Need enough clicks to measure CVR', 1, 1, 'MANUAL'),
  ('NEGATE_ROAS_THRESHOLD', 'EXACT_BOOST', 'GUARDIAN', 0.3, 'Only negate if deeply unprofitable', 0.7, 0.7, 'SEED'),
  ('NEGATE_SPEND_THRESHOLD', 'EXACT_BOOST', 'GUARDIAN', 40, 'Substantial evidence needed before negating a proven keyword', 1.5, 1.5, 'SEED'),
  ('PROFITABLE_ROAS', 'EXACT_BOOST', 'GUARDIAN', 1.1, 'Standard break-even', 0.7, 0.8, 'MANUAL'),
  ('REDUCE_BID_ROAS', 'EXACT_BOOST', 'GUARDIAN', 0.7, 'Reduce when losing money', 0.7, 0.7, 'SEED'),
  ('SCALE_UP_ROAS', 'EXACT_BOOST', 'GUARDIAN', 1.5, 'Lower bar — invest at 1.5x if organic rank improving', 0.7, 0.8, 'SEED'),
  ('SCALE_UP_SPEND_CAP', 'EXACT_BOOST', 'GUARDIAN', 100, 'Higher ceiling for important keywords', 1.5, 1.5, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'EXACT_BOOST', 'GUARDIAN', 25, 'Proven keywords — short dry spells happen', 1.5, 1.5, 'SEED'),

  -- GUARDIAN x HUNTER
  ('BID_CAP_SUGGESTION', 'HUNTER', 'GUARDIAN', 2, 'Bid cap suggestion based on experiment CPC analysis', 1, 1, 'AUTO_SUGGEST'),
  ('INSUFFICIENT_DATA_CLICKS', 'HUNTER', 'GUARDIAN', 15, 'Standard discovery click count', 1, 1, 'SEED'),
  ('NEGATE_ROAS_THRESHOLD', 'HUNTER', 'GUARDIAN', 0.3, 'Lenient — discovery accepts low ROAS initially', 1, 1, 'SEED'),
  ('NEGATE_SPEND_THRESHOLD', 'HUNTER', 'GUARDIAN', 15, 'Quick negate — dont pour money into dead-end terms', 1.5, 1, 'SEED'),
  ('PROFITABLE_ROAS', 'HUNTER', 'GUARDIAN', 1.1, 'Profitable at 0.7x when accounting for organic halo', 1, 1, 'MANUAL'),
  ('PROMOTE_MIN_SQP_VOLUME', 'HUNTER', 'GUARDIAN', 500, 'Min SQP weekly search volume for HUNTER promote', 1, 1, 'coach_v2'),
  ('REDUCE_BID_ROAS', 'HUNTER', 'GUARDIAN', 0.5, 'Lower bar since discovery ROAS is naturally lower', 1, 1, 'SEED'),
  ('SCALE_UP_ROAS', 'HUNTER', 'GUARDIAN', 2, 'Hunter at 1.0x = winner → graduate to Exact Boost', 1, 1, 'MANUAL'),
  ('SCALE_UP_SPEND_CAP', 'HUNTER', 'GUARDIAN', 30, 'Dont over-invest — graduate to Exact instead', 1.5, 1, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'HUNTER', 'GUARDIAN', 10, 'Discovery terms should prove themselves faster', 1.5, 1, 'SEED'),

  -- GUARDIAN x LOW_COST_DISCOVERY
  ('BID_CAP_SUGGESTION', 'LOW_COST_DISCOVERY', 'GUARDIAN', 2, 'Bid cap suggestion based on experiment CPC analysis', 1, 1, 'AUTO_SUGGEST'),
  ('INSUFFICIENT_DATA_CLICKS', 'LOW_COST_DISCOVERY', 'GUARDIAN', 10, 'At low CPCs, 10 clicks = $1-3 spend', 1, 1, 'SEED'),
  ('NEGATE_ROAS_THRESHOLD', 'LOW_COST_DISCOVERY', 'GUARDIAN', 0.5, 'Standard for discovery', 1, 1, 'SEED'),
  ('NEGATE_SPEND_THRESHOLD', 'LOW_COST_DISCOVERY', 'GUARDIAN', 8, 'Quick trigger — $8 with no value = negate', 1, 1, 'SEED'),
  ('PROFITABLE_ROAS', 'LOW_COST_DISCOVERY', 'GUARDIAN', 1.1, 'At these CPCs, even 0.5x may be worthwhile', 1, 1, 'MANUAL'),
  ('PROMOTE_MIN_SQP_VOLUME', 'LOW_COST_DISCOVERY', 'GUARDIAN', 250, 'Lower bar for low-cost discovery keywords', 1, 1, 'coach_v2'),
  ('SCALE_UP_ROAS', 'LOW_COST_DISCOVERY', 'GUARDIAN', 1.5, 'Any term at 1.0x → promote out of discovery', 1, 1, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'LOW_COST_DISCOVERY', 'GUARDIAN', 5, 'Very low tolerance — cheap discovery', 1, 1, 'SEED'),

  -- GUARDIAN x NEW_LAUNCH
  ('INSUFFICIENT_DATA_CLICKS', 'NEW_LAUNCH', 'GUARDIAN', 15, 'Standard click count', 1, 1, 'SEED'),
  ('NEGATE_ROAS_THRESHOLD', 'NEW_LAUNCH', 'GUARDIAN', 0.2, 'Accept low ROAS in first 4-8 weeks', 1, 1, 'SEED'),
  ('PROFITABLE_ROAS', 'NEW_LAUNCH', 'GUARDIAN', 0.5, 'Early profitability is a bonus', 1, 1, 'SEED'),
  ('SCALE_UP_ROAS', 'NEW_LAUNCH', 'GUARDIAN', 0.8, 'Early 0.8x ROAS = product showing promise', 1, 1, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'NEW_LAUNCH', 'GUARDIAN', 30, 'New products need time', 1, 1, 'SEED'),

  -- GUARDIAN x PRODUCT_DEFENSE
  ('BID_CAP_SUGGESTION', 'PRODUCT_DEFENSE', 'GUARDIAN', 2, 'Bid cap suggestion based on experiment CPC analysis', 1, 1, 'AUTO_SUGGEST'),
  ('INSUFFICIENT_DATA_CLICKS', 'PRODUCT_DEFENSE', 'GUARDIAN', 10, 'Product page clicks are high-intent', 1, 1, 'SEED'),
  ('NEGATE_ROAS_THRESHOLD', 'PRODUCT_DEFENSE', 'GUARDIAN', -999, 'Never negate product defense — deter competitors', 1, 1, 'SEED'),
  ('PROFITABLE_ROAS', 'PRODUCT_DEFENSE', 'GUARDIAN', 2, 'High-intent clicks should convert well', 1, 1, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'PRODUCT_DEFENSE', 'GUARDIAN', 5, 'Defense shouldnt cost much', 1, 1, 'SEED'),

  -- GUARDIAN x RETARGETING
  ('INSUFFICIENT_DATA_CLICKS', 'RETARGETING', 'GUARDIAN', 15, 'Standard click count', 1, 1, 'SEED'),
  ('PROFITABLE_ROAS', 'RETARGETING', 'GUARDIAN', 1.1, 'Retargeting should be very profitable', 1, 1, 'MANUAL'),
  ('SCALE_UP_ROAS', 'RETARGETING', 'GUARDIAN', 2, 'High bar — warm audiences', 1, 1, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'RETARGETING', 'GUARDIAN', 10, 'Past visitors should convert', 1, 1, 'SEED'),

  -- GUARDIAN x SEASONAL_PUSH
  ('INSUFFICIENT_DATA_CLICKS', 'SEASONAL_PUSH', 'GUARDIAN', 15, 'Standard click count', 1, 1, 'SEED'),
  ('NEGATE_ROAS_THRESHOLD', 'SEASONAL_PUSH', 'GUARDIAN', 0.3, 'Lenient during ramp-up', 0.67, 1, 'SEED'),
  ('PROFITABLE_ROAS', 'SEASONAL_PUSH', 'GUARDIAN', 0.7, 'Accept losses during pre-peak', 0.71, 1, 'SEED'),
  ('SCALE_UP_ROAS', 'SEASONAL_PUSH', 'GUARDIAN', 1, 'If profitable during ramp, scale hard', 0.8, 1, 'SEED'),
  ('SCALE_UP_SPEND_CAP', 'SEASONAL_PUSH', 'GUARDIAN', 150, 'High ceiling during season', 1.33, 1, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'SEASONAL_PUSH', 'GUARDIAN', 30, 'Accept high spend during season', 1.67, 1, 'SEED'),

  -- GUARDIAN x TOS_DOMINATION
  ('INSUFFICIENT_DATA_CLICKS', 'TOS_DOMINATION', 'GUARDIAN', 20, 'Need enough data at high spend', 1, 1, 'SEED'),
  ('PROFITABLE_ROAS', 'TOS_DOMINATION', 'GUARDIAN', 1.1, 'Accept lower ROAS for visibility value', 1, 1, 'MANUAL'),
  ('SCALE_UP_ROAS', 'TOS_DOMINATION', 'GUARDIAN', 1.5, 'Only scale if profitable at high bids', 1, 1, 'SEED'),
  ('WASTED_SPEND_THRESHOLD', 'TOS_DOMINATION', 'GUARDIAN', 40, 'TOS is expensive by design', 1, 1, 'SEED'),

  -- BLITZ x GLOBAL
  ('CONFIDENCE_CLICKS_HIGH', 'GLOBAL', 'BLITZ', 30, 'Blitz: lower confidence threshold', 1, 1, 'MANUAL'),
  ('CONFIDENCE_CLICKS_MEDIUM', 'GLOBAL', 'BLITZ', 15, 'Blitz: lower confidence threshold', 1, 1, 'MANUAL'),
  ('CONFIDENCE_DAYS_HIGH', 'GLOBAL', 'BLITZ', 10, 'Blitz: faster confidence', 1, 1, 'MANUAL'),
  ('CONFIDENCE_DAYS_MEDIUM', 'GLOBAL', 'BLITZ', 5, 'Blitz: faster confidence', 1, 1, 'MANUAL'),
  ('HALO_ROAS', 'GLOBAL', 'BLITZ', 0.5, 'Blitz: same halo bar', 1, 1, 'MANUAL'),
  ('INSUFFICIENT_DATA_CLICKS', 'GLOBAL', 'BLITZ', 10, 'Blitz: decide faster with less clicks', 1, 1, 'MANUAL'),
  ('NEGATE_ROAS_THRESHOLD', 'GLOBAL', 'BLITZ', 0.5, 'Blitz: same negate bar as Guardian', 1, 1, 'MANUAL'),
  ('NEGATE_SPEND_THRESHOLD', 'GLOBAL', 'BLITZ', 35, 'Blitz: tolerate more spend before negate', 1, 1, 'MANUAL'),
  ('PROFITABLE_ROAS', 'GLOBAL', 'BLITZ', 1, 'Blitz: same profitability bar', 1, 1, 'MANUAL'),
  ('PROMOTE_MIN_ORDERS', 'GLOBAL', 'BLITZ', 2, 'Blitz: promote faster with fewer orders', 1, 1, 'MANUAL'),
  ('PROMOTE_MIN_SQP_VOLUME', 'GLOBAL', 'BLITZ', 300, 'Blitz: lower SQP bar for promotion', 1, 1, 'MANUAL'),
  ('REDUCE_BID_ROAS', 'GLOBAL', 'BLITZ', 0.7, 'Blitz: same reduce bar as Guardian', 1, 1, 'MANUAL'),
  ('SCALE_UP_ROAS', 'GLOBAL', 'BLITZ', 1.2, 'Blitz: lower bar to scale up during peak', 1, 1, 'MANUAL'),
  ('SCALE_UP_SPEND_CAP', 'GLOBAL', 'BLITZ', 100, 'Blitz: higher cap for scaling', 1, 1, 'MANUAL'),
  ('WASTED_SPEND_THRESHOLD', 'GLOBAL', 'BLITZ', 25, 'Blitz: higher spend tolerance before flagging waste', 1, 1, 'MANUAL'),

  -- COOLDOWN x GLOBAL
  ('CONFIDENCE_CLICKS_HIGH', 'GLOBAL', 'COOLDOWN', 50, 'Cooldown: standard confidence', 1, 1, 'MANUAL'),
  ('CONFIDENCE_CLICKS_MEDIUM', 'GLOBAL', 'COOLDOWN', 20, 'Cooldown: standard confidence', 1, 1, 'MANUAL'),
  ('CONFIDENCE_DAYS_HIGH', 'GLOBAL', 'COOLDOWN', 14, 'Cooldown: standard confidence', 1, 1, 'MANUAL'),
  ('CONFIDENCE_DAYS_MEDIUM', 'GLOBAL', 'COOLDOWN', 7, 'Cooldown: standard confidence', 1, 1, 'MANUAL'),
  ('HALO_ROAS', 'GLOBAL', 'COOLDOWN', 0.3, 'Cooldown: low halo tolerance', 1, 1, 'MANUAL'),
  ('INSUFFICIENT_DATA_CLICKS', 'GLOBAL', 'COOLDOWN', 15, 'Cooldown: standard data bar', 1, 1, 'MANUAL'),
  ('NEGATE_ROAS_THRESHOLD', 'GLOBAL', 'COOLDOWN', 0.5, 'Cooldown: same negate bar', 1, 1, 'MANUAL'),
  ('NEGATE_SPEND_THRESHOLD', 'GLOBAL', 'COOLDOWN', 10, 'Cooldown: tight spend tolerance', 1, 1, 'MANUAL'),
  ('PROFITABLE_ROAS', 'GLOBAL', 'COOLDOWN', 1.1, 'Cooldown: high bar for profitable', 1, 1, 'MANUAL'),
  ('PROMOTE_MIN_ORDERS', 'GLOBAL', 'COOLDOWN', 999999, 'Cooldown: DISABLED - no promoting during winddown', 1, 1, 'MANUAL'),
  ('PROMOTE_MIN_SQP_VOLUME', 'GLOBAL', 'COOLDOWN', 999999, 'Cooldown: DISABLED', 1, 1, 'MANUAL'),
  ('REDUCE_BID_ROAS', 'GLOBAL', 'COOLDOWN', 1, 'Cooldown: reduce anything below breakeven', 1, 1, 'MANUAL'),
  ('SCALE_UP_ROAS', 'GLOBAL', 'COOLDOWN', 999999, 'Cooldown: DISABLED - no scaling during winddown', 1, 1, 'MANUAL'),
  ('SCALE_UP_SPEND_CAP', 'GLOBAL', 'COOLDOWN', 0, 'Cooldown: DISABLED', 1, 1, 'MANUAL'),
  ('WASTED_SPEND_THRESHOLD', 'GLOBAL', 'COOLDOWN', 10, 'Cooldown: strict waste detection', 1, 1, 'MANUAL');
