-- =============================================
-- OI Database Project - DE_COACH_THRESHOLDS Table
-- =============================================
--
-- Purpose: User-editable thresholds for the Ads Coach decision engine.
--          Controls when keywords are NEGATED, REDUCED, SCALED, etc.
--          Values can be overridden per strategy template and per product family.
--
-- Resolution order (highest priority first):
--   1. strategy_id + product_family match
--   2. strategy_id match (product_family IS NULL)
--   3. strategy_id = 'GLOBAL' (default fallback)
--   4. Hardcoded fallback in V_ADS_COACH_DECISION SQL
--
-- Method: Manual INSERT / UPDATE via Flask API
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_COACH_THRESHOLDS` (
  -- Composite key
  threshold_key     STRING NOT NULL,          -- e.g. 'WASTED_SPEND_THRESHOLD'
  strategy_id       STRING NOT NULL,          -- e.g. 'EXACT_BOOST' or 'GLOBAL'
  product_family    STRING,                   -- NULL = all families, or 'Lollibox', 'LolliME', etc.

  -- Current active value
  threshold_value   FLOAT64 NOT NULL,         -- the numeric threshold value
  description       STRING,                   -- human-readable explanation of what this threshold does

  -- Auto-suggestion fields (system writes, user approves)
  suggested_value   FLOAT64,                  -- system-suggested new value
  suggested_at      DATETIME,                 -- when the suggestion was generated
  suggestion_reason STRING,                   -- why the system suggests this change

  -- Seasonal multipliers
  peak_multiplier   FLOAT64 DEFAULT 1.0,      -- multiplier applied during PEAK season phase
  boost_peak_multiplier FLOAT64 DEFAULT 1.0,  -- multiplier applied during BOOST_PEAK (pre-season ramp)

  -- Source tracking
  source            STRING DEFAULT 'MANUAL',  -- 'MANUAL', 'AUTO_SUGGESTED', 'SEED'

  -- Metadata
  updated_at        DATETIME DEFAULT CURRENT_DATETIME(),
  updated_by        STRING
);

-- =============================================
-- SEED DATA: Global defaults + per-strategy overrides
-- =============================================
DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` WHERE TRUE;

INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, product_family, threshold_value, description, peak_multiplier, boost_peak_multiplier, source)
VALUES

-- ═══════════════════════════════════════════════
-- GLOBAL defaults (used when no strategy match)
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'GLOBAL', NULL, 15, 'Skip keyword if fewer than this many clicks in 4 weeks', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'GLOBAL', NULL, 15, 'Flag as wasted if spend exceeds this with 0 orders', 1.0, 1.0, 'SEED'),
('NEGATE_ROAS_THRESHOLD', 'GLOBAL', NULL, 0.5, 'Negate keyword if Net ROAS is below this', 1.0, 1.0, 'SEED'),
('NEGATE_SPEND_THRESHOLD', 'GLOBAL', NULL, 20, 'Only negate if spend exceeds this amount', 1.0, 1.0, 'SEED'),
('REDUCE_BID_ROAS', 'GLOBAL', NULL, 0.7, 'Reduce bid if Net ROAS is below this', 1.0, 1.0, 'SEED'),
('REDUCE_BID_SPEND', 'GLOBAL', NULL, 10, 'Only reduce bid if spend exceeds this', 1.0, 1.0, 'SEED'),
('SCALE_UP_ROAS', 'GLOBAL', NULL, 2.0, 'Scale up if Net ROAS exceeds this', 1.0, 1.0, 'SEED'),
('SCALE_UP_SPEND_CAP', 'GLOBAL', NULL, 50, 'Only scale up if spend is below this cap', 1.0, 1.0, 'SEED'),
('PROFITABLE_ROAS', 'GLOBAL', NULL, 1.0, 'Keyword is profitable (KEEP) at this Net ROAS or above', 1.0, 1.0, 'SEED'),
('HALO_ROAS', 'GLOBAL', NULL, 0.5, 'Keep keyword if organic halo detected and Net ROAS >= this', 1.0, 1.0, 'SEED'),
('CONFIDENCE_DAYS_HIGH', 'GLOBAL', NULL, 14, 'HIGH confidence requires this many days of data', 1.0, 1.0, 'SEED'),
('CONFIDENCE_CLICKS_HIGH', 'GLOBAL', NULL, 50, 'HIGH confidence requires this many clicks', 1.0, 1.0, 'SEED'),
('CONFIDENCE_DAYS_MEDIUM', 'GLOBAL', NULL, 7, 'MEDIUM confidence requires this many days', 1.0, 1.0, 'SEED'),
('CONFIDENCE_CLICKS_MEDIUM', 'GLOBAL', NULL, 20, 'MEDIUM confidence requires this many clicks', 1.0, 1.0, 'SEED'),

-- ═══════════════════════════════════════════════
-- 🛡️ BRAND_DEFENSE — never negate, low spend tolerance
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'BRAND_DEFENSE', NULL, 10, 'Brand terms are cheap — 10 clicks is enough', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'BRAND_DEFENSE', NULL, 5, '$5 with 0 orders on brand = something is wrong', 1.0, 1.0, 'SEED'),
('NEGATE_ROAS_THRESHOLD', 'BRAND_DEFENSE', NULL, -999, 'Never negate brand terms — defend at any cost', 1.0, 1.0, 'SEED'),
('SCALE_UP_ROAS', 'BRAND_DEFENSE', NULL, 5.0, 'Brand terms should be 5x+ Net ROAS to scale TOS boost', 1.0, 1.0, 'SEED'),
('PROFITABLE_ROAS', 'BRAND_DEFENSE', NULL, 3.0, 'Below 3x on brand is underperforming', 1.0, 1.0, 'SEED'),
('CONFIDENCE_DAYS_HIGH', 'BRAND_DEFENSE', NULL, 7, 'Brand terms have high volume, 7 days is enough', 1.0, 1.0, 'SEED'),

-- ═══════════════════════════════════════════════
-- 🎯 EXACT_BOOST — higher spend tolerance, peak ramp
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'EXACT_BOOST', NULL, 20, 'Need enough clicks to measure CVR', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'EXACT_BOOST', NULL, 25, 'Proven keywords — short dry spells happen', 1.5, 1.5, 'SEED'),
('NEGATE_ROAS_THRESHOLD', 'EXACT_BOOST', NULL, 0.3, 'Only negate if deeply unprofitable', 0.7, 0.7, 'SEED'),
('NEGATE_SPEND_THRESHOLD', 'EXACT_BOOST', NULL, 40, 'Substantial evidence needed before negating a proven keyword', 1.5, 1.5, 'SEED'),
('REDUCE_BID_ROAS', 'EXACT_BOOST', NULL, 0.7, 'Reduce when losing money', 0.7, 0.7, 'SEED'),
('SCALE_UP_ROAS', 'EXACT_BOOST', NULL, 1.5, 'Lower bar — invest at 1.5x if organic rank improving', 0.7, 0.8, 'SEED'),
('PROFITABLE_ROAS', 'EXACT_BOOST', NULL, 1.0, 'Standard break-even', 0.7, 0.8, 'SEED'),
('SCALE_UP_SPEND_CAP', 'EXACT_BOOST', NULL, 100, 'Higher ceiling for important keywords', 1.5, 1.5, 'SEED'),

-- ═══════════════════════════════════════════════
-- 🔍 HUNTER — discovery, fast negate, graduate winners
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'HUNTER', NULL, 15, 'Standard discovery click count', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'HUNTER', NULL, 10, 'Discovery terms should prove themselves faster', 1.5, 1.0, 'SEED'),
('NEGATE_ROAS_THRESHOLD', 'HUNTER', NULL, 0.3, 'Lenient — discovery accepts low ROAS initially', 1.0, 1.0, 'SEED'),
('NEGATE_SPEND_THRESHOLD', 'HUNTER', NULL, 15, 'Quick negate — dont pour money into dead-end terms', 1.5, 1.0, 'SEED'),
('REDUCE_BID_ROAS', 'HUNTER', NULL, 0.5, 'Lower bar since discovery ROAS is naturally lower', 1.0, 1.0, 'SEED'),
('SCALE_UP_ROAS', 'HUNTER', NULL, 1.0, 'Hunter at 1.0x = winner → graduate to Exact Boost', 1.0, 1.0, 'SEED'),
('PROFITABLE_ROAS', 'HUNTER', NULL, 0.7, 'Profitable at 0.7x when accounting for organic halo', 1.0, 1.0, 'SEED'),
('SCALE_UP_SPEND_CAP', 'HUNTER', NULL, 30, 'Dont over-invest — graduate to Exact instead', 1.5, 1.0, 'SEED'),

-- ═══════════════════════════════════════════════
-- 💰 LOW_COST_DISCOVERY — ultra-cheap, fast kill
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'LOW_COST_DISCOVERY', NULL, 10, 'At low CPCs, 10 clicks = $1-3 spend', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'LOW_COST_DISCOVERY', NULL, 5, 'Very low tolerance — cheap discovery', 1.0, 1.0, 'SEED'),
('NEGATE_ROAS_THRESHOLD', 'LOW_COST_DISCOVERY', NULL, 0.5, 'Standard for discovery', 1.0, 1.0, 'SEED'),
('NEGATE_SPEND_THRESHOLD', 'LOW_COST_DISCOVERY', NULL, 8, 'Quick trigger — $8 with no value = negate', 1.0, 1.0, 'SEED'),
('SCALE_UP_ROAS', 'LOW_COST_DISCOVERY', NULL, 1.0, 'Any term at 1.0x → promote out of discovery', 1.0, 1.0, 'SEED'),
('PROFITABLE_ROAS', 'LOW_COST_DISCOVERY', NULL, 0.5, 'At these CPCs, even 0.5x may be worthwhile', 1.0, 1.0, 'SEED'),

-- ═══════════════════════════════════════════════
-- ⚔️ CATEGORY_CONQUEST — patience for category terms
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'CATEGORY_CONQUEST', NULL, 15, 'Standard click count for category terms', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'CATEGORY_CONQUEST', NULL, 20, 'Category terms need more time to prove out', 1.5, 1.0, 'SEED'),
('NEGATE_ROAS_THRESHOLD', 'CATEGORY_CONQUEST', NULL, 0.3, 'Lenient — new category terms start slow', 1.0, 1.0, 'SEED'),
('SCALE_UP_ROAS', 'CATEGORY_CONQUEST', NULL, 1.0, 'If profitable on category term, invest more', 1.0, 1.0, 'SEED'),
('PROFITABLE_ROAS', 'CATEGORY_CONQUEST', NULL, 0.7, 'Accept lower ROAS if SQP share is growing', 1.0, 1.0, 'SEED'),

-- ═══════════════════════════════════════════════
-- 🏰 PRODUCT_DEFENSE — never stop, deter competitors
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'PRODUCT_DEFENSE', NULL, 10, 'Product page clicks are high-intent', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'PRODUCT_DEFENSE', NULL, 5, 'Defense shouldnt cost much', 1.0, 1.0, 'SEED'),
('NEGATE_ROAS_THRESHOLD', 'PRODUCT_DEFENSE', NULL, -999, 'Never negate product defense — deter competitors', 1.0, 1.0, 'SEED'),
('PROFITABLE_ROAS', 'PRODUCT_DEFENSE', NULL, 2.0, 'High-intent clicks should convert well', 1.0, 1.0, 'SEED'),

-- ═══════════════════════════════════════════════
-- 🚀 SEASONAL_PUSH — two-phase: boost_peak + peak
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'SEASONAL_PUSH', NULL, 15, 'Standard click count', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'SEASONAL_PUSH', NULL, 30, 'Accept high spend during season', 1.67, 1.0, 'SEED'),
('NEGATE_ROAS_THRESHOLD', 'SEASONAL_PUSH', NULL, 0.3, 'Lenient during ramp-up', 0.67, 1.0, 'SEED'),
('SCALE_UP_ROAS', 'SEASONAL_PUSH', NULL, 1.0, 'If profitable during ramp, scale hard', 0.8, 1.0, 'SEED'),
('PROFITABLE_ROAS', 'SEASONAL_PUSH', NULL, 0.7, 'Accept losses during pre-peak', 0.71, 1.0, 'SEED'),
('SCALE_UP_SPEND_CAP', 'SEASONAL_PUSH', NULL, 150, 'High ceiling during season', 1.33, 1.0, 'SEED'),

-- ═══════════════════════════════════════════════
-- 🆕 NEW_LAUNCH — patient with new products
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'NEW_LAUNCH', NULL, 15, 'Standard click count', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'NEW_LAUNCH', NULL, 30, 'New products need time', 1.0, 1.0, 'SEED'),
('NEGATE_ROAS_THRESHOLD', 'NEW_LAUNCH', NULL, 0.2, 'Accept low ROAS in first 4-8 weeks', 1.0, 1.0, 'SEED'),
('SCALE_UP_ROAS', 'NEW_LAUNCH', NULL, 0.8, 'Early 0.8x ROAS = product showing promise', 1.0, 1.0, 'SEED'),
('PROFITABLE_ROAS', 'NEW_LAUNCH', NULL, 0.5, 'Early profitability is a bonus', 1.0, 1.0, 'SEED'),

-- ═══════════════════════════════════════════════
-- 🏆 TOS_DOMINATION — expensive by design
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'TOS_DOMINATION', NULL, 20, 'Need enough data at high spend', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'TOS_DOMINATION', NULL, 40, 'TOS is expensive by design', 1.0, 1.0, 'SEED'),
('SCALE_UP_ROAS', 'TOS_DOMINATION', NULL, 1.5, 'Only scale if profitable at high bids', 1.0, 1.0, 'SEED'),
('PROFITABLE_ROAS', 'TOS_DOMINATION', NULL, 0.8, 'Accept lower ROAS for visibility value', 1.0, 1.0, 'SEED'),

-- ═══════════════════════════════════════════════
-- ♻️ RETARGETING — warm audience, high standards
-- ═══════════════════════════════════════════════
('INSUFFICIENT_DATA_CLICKS', 'RETARGETING', NULL, 15, 'Standard click count', 1.0, 1.0, 'SEED'),
('WASTED_SPEND_THRESHOLD', 'RETARGETING', NULL, 10, 'Past visitors should convert', 1.0, 1.0, 'SEED'),
('SCALE_UP_ROAS', 'RETARGETING', NULL, 2.0, 'High bar — warm audiences', 1.0, 1.0, 'SEED'),
('PROFITABLE_ROAS', 'RETARGETING', NULL, 1.5, 'Retargeting should be very profitable', 1.0, 1.0, 'SEED');
