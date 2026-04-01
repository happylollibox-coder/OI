-- =============================================
-- Migration: Seasonal Strategy Templates + Experiment Lifecycle
-- =============================================
--
-- Part 1: Add peak/off-season modifiers to DIM_STRATEGY_TEMPLATE
--   - Each strategy gets seasonal bid/budget multipliers
--   - Season-specific guidance notes
--   - Peak_only / Offseason_inactive flags for strategies that only apply in certain seasons
--
-- Part 2: Extend DIM_EXPERIMENT with lifecycle stages
--   - ACTIVE → REVIEW → VALIDATED → GRADUATED (or FAILED/PAUSED)
--   - Graduation criteria columns
--   - When GRADUATED, campaign settings become permanent "rules"
--
-- Part 3: Create FACT_GRADUATED_RULES table
--   - Stores proven settings that graduated from experiments
--   - Links experiment → strategy → ASIN → keywords → settings
--
-- Part 4: Create V_STRATEGY_CURRENT_RECOMMENDATIONS
--   - Auto-applies seasonal multipliers based on current week's seasonal index
--
-- =============================================

-- =============================================
-- PART 1: DIM_STRATEGY_TEMPLATE seasonal modifiers
-- =============================================

-- Peak season: holidays with seasonal_index > 1.5 (Valentine's, Easter, Mother's Day, Black Friday, Christmas)
ALTER TABLE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
  ADD COLUMN IF NOT EXISTS peak_bid_multiplier FLOAT64,
  ADD COLUMN IF NOT EXISTS peak_budget_multiplier FLOAT64,
  ADD COLUMN IF NOT EXISTS peak_tos_add_pct INT64,
  ADD COLUMN IF NOT EXISTS peak_notes STRING;

-- Off season: low demand periods with seasonal_index < 0.5 (Jul-Sep, post-holiday Jan)
ALTER TABLE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
  ADD COLUMN IF NOT EXISTS offseason_bid_multiplier FLOAT64,
  ADD COLUMN IF NOT EXISTS offseason_budget_multiplier FLOAT64,
  ADD COLUMN IF NOT EXISTS offseason_tos_add_pct INT64,
  ADD COLUMN IF NOT EXISTS offseason_notes STRING;

-- Season applicability: some strategies are season-specific
ALTER TABLE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
  ADD COLUMN IF NOT EXISTS season_applicability STRING;
  -- ALL_SEASONS, PEAK_ONLY, OFF_SEASON_ONLY, PEAK_PREFERRED, OFF_SEASON_PREFERRED

-- Graduation criteria: how many experiments needed before this strategy's results are trusted
ALTER TABLE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
  ADD COLUMN IF NOT EXISTS min_experiments_to_graduate INT64,
  ADD COLUMN IF NOT EXISTS min_days_to_graduate INT64,
  ADD COLUMN IF NOT EXISTS min_seasonal_lift_to_graduate FLOAT64;


-- =============================================
-- Update each strategy with seasonal modifiers
-- =============================================
-- All multipliers are relative to the BASE settings in the template
-- peak_bid_multiplier = 2.0 means bids are 2x the base during peak
-- offseason_bid_multiplier = 0.5 means bids are 0.5x the base during off-season

-- BRAND_DEFENSE: Always-on, but increase aggressiveness during peak
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET
  peak_bid_multiplier = 2.0,
  peak_budget_multiplier = 2.5,
  peak_tos_add_pct = 200,
  peak_notes = 'Competitors bid harder on brand terms during peak. Double down to protect. Gift shoppers searching brand name = highest intent.',
  offseason_bid_multiplier = 0.7,
  offseason_budget_multiplier = 0.5,
  offseason_tos_add_pct = 0,
  offseason_notes = 'Reduce but keep running. Brand presence still matters even in low season. Lower competition means lower bids still win.',
  season_applicability = 'ALL_SEASONS',
  min_experiments_to_graduate = 2,
  min_days_to_graduate = 28,
  min_seasonal_lift_to_graduate = 0.0,
  updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'BRAND_DEFENSE';

-- HUNTER: More effective in peak when competitors are stretched thin
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET
  peak_bid_multiplier = 1.5,
  peak_budget_multiplier = 2.0,
  peak_tos_add_pct = 100,
  peak_notes = 'Competitors may run out of stock or budget during peak. Excellent time to steal share. Increase aggression.',
  offseason_bid_multiplier = 0.5,
  offseason_budget_multiplier = 0.4,
  offseason_tos_add_pct = -100,
  offseason_notes = 'Low volume means expensive conquests. Scale back significantly. Consider pausing if ROAS drops below 1.5.',
  season_applicability = 'PEAK_PREFERRED',
  min_experiments_to_graduate = 3,
  min_days_to_graduate = 42,
  min_seasonal_lift_to_graduate = 5.0,
  updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'HUNTER';

-- EXACT_BOOST: Critical for ranking during peak; maintain minimum in off-season
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET
  peak_bid_multiplier = 2.5,
  peak_budget_multiplier = 3.0,
  peak_tos_add_pct = 200,
  peak_notes = 'Sales velocity during peak has outsized impact on organic ranking. Push hard - the organic ranking gains from peak carry into post-season.',
  offseason_bid_multiplier = 0.6,
  offseason_budget_multiplier = 0.5,
  offseason_tos_add_pct = -200,
  offseason_notes = 'Maintain presence to hold ranking gains from peak. Lower bids since competition is lighter. Focus on efficiency.',
  season_applicability = 'ALL_SEASONS',
  min_experiments_to_graduate = 2,
  min_days_to_graduate = 28,
  min_seasonal_lift_to_graduate = 5.0,
  updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'EXACT_BOOST';

-- CATEGORY_CONQUEST: Better discovery in off-season (cheaper clicks, less noise)
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET
  peak_bid_multiplier = 1.5,
  peak_budget_multiplier = 2.0,
  peak_tos_add_pct = 0,
  peak_notes = 'Higher volume means more data for discovery but also more noise. Increase budget to capture the volume but review frequently.',
  offseason_bid_multiplier = 1.0,
  offseason_budget_multiplier = 1.2,
  offseason_tos_add_pct = 0,
  offseason_notes = 'Off-season is ideal for discovery: cheaper clicks, cleaner data, less holiday noise. Great time to find new keywords.',
  season_applicability = 'OFF_SEASON_PREFERRED',
  min_experiments_to_graduate = 2,
  min_days_to_graduate = 28,
  min_seasonal_lift_to_graduate = 0.0,
  updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'CATEGORY_CONQUEST';

-- PRODUCT_DEFENSE: Scale with traffic
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET
  peak_bid_multiplier = 2.0,
  peak_budget_multiplier = 2.5,
  peak_tos_add_pct = 0,
  peak_notes = 'More page views during peak = more competitor ads on your pages. Increase defense spending proportionally.',
  offseason_bid_multiplier = 0.5,
  offseason_budget_multiplier = 0.4,
  offseason_tos_add_pct = 0,
  offseason_notes = 'Fewer page views, fewer competitors. Minimal defense needed. Consider pausing if no competitor activity detected.',
  season_applicability = 'ALL_SEASONS',
  min_experiments_to_graduate = 2,
  min_days_to_graduate = 28,
  min_seasonal_lift_to_graduate = 0.0,
  updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'PRODUCT_DEFENSE';

-- SEASONAL_PUSH: Peak ONLY strategy
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET
  peak_bid_multiplier = 1.0,
  peak_budget_multiplier = 1.0,
  peak_tos_add_pct = 0,
  peak_notes = 'This IS the peak strategy. Base settings are already aggressive. Start 3 weeks before holiday, ramp daily budget from 50% to 100% to 150%.',
  offseason_bid_multiplier = 0.0,
  offseason_budget_multiplier = 0.0,
  offseason_tos_add_pct = 0,
  offseason_notes = 'DO NOT RUN in off-season. This strategy is specifically for holiday periods. Use EXACT_BOOST or LOW_COST_DISCOVERY instead.',
  season_applicability = 'PEAK_ONLY',
  min_experiments_to_graduate = 2,
  min_days_to_graduate = 14,
  min_seasonal_lift_to_graduate = 0.0,
  updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'SEASONAL_PUSH';

-- NEW_LAUNCH: Season-independent (launches happen anytime)
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET
  peak_bid_multiplier = 1.5,
  peak_budget_multiplier = 1.5,
  peak_tos_add_pct = 100,
  peak_notes = 'Launching during peak = maximum initial velocity. Worth the premium. Sales velocity during peak creates lasting organic rank.',
  offseason_bid_multiplier = 0.8,
  offseason_budget_multiplier = 0.8,
  offseason_tos_add_pct = 0,
  offseason_notes = 'Launching in off-season is cheaper but slower. Extend the launch period to 8-12 weeks. Patience required.',
  season_applicability = 'ALL_SEASONS',
  min_experiments_to_graduate = 1,
  min_days_to_graduate = 42,
  min_seasonal_lift_to_graduate = 0.0,
  updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'NEW_LAUNCH';

-- LOW_COST_DISCOVERY: Best in off-season
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET
  peak_bid_multiplier = 1.5,
  peak_budget_multiplier = 2.0,
  peak_tos_add_pct = 0,
  peak_notes = 'Peak volume means more discovery data. Increase budget slightly but keep bids low - we want cheap conversions only.',
  offseason_bid_multiplier = 1.0,
  offseason_budget_multiplier = 1.0,
  offseason_tos_add_pct = 0,
  offseason_notes = 'Perfect off-season strategy. Low bids, low competition, clean long-tail keyword discovery. Always keep this running.',
  season_applicability = 'ALL_SEASONS',
  min_experiments_to_graduate = 2,
  min_days_to_graduate = 28,
  min_seasonal_lift_to_graduate = 0.0,
  updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'LOW_COST_DISCOVERY';

-- TOS_DOMINATION: Very expensive in peak, very effective
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET
  peak_bid_multiplier = 2.0,
  peak_budget_multiplier = 2.5,
  peak_tos_add_pct = 0,
  peak_notes = 'Extremely expensive during peak but maximum impact on ranking. Only for top 2-3 keywords. Monitor ACOS hourly during major holidays.',
  offseason_bid_multiplier = 0.5,
  offseason_budget_multiplier = 0.4,
  offseason_tos_add_pct = -300,
  offseason_notes = 'TOS domination in off-season is wasteful. Switch to EXACT_BOOST with moderate TOS. Save the big TOS push for peak.',
  season_applicability = 'PEAK_PREFERRED',
  min_experiments_to_graduate = 3,
  min_days_to_graduate = 28,
  min_seasonal_lift_to_graduate = 10.0,
  updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'TOS_DOMINATION';

-- RETARGETING: Scales with customer base
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET
  peak_bid_multiplier = 1.5,
  peak_budget_multiplier = 2.0,
  peak_tos_add_pct = 0,
  peak_notes = 'Peak season creates a large retargeting pool from holiday browsers. Capture the post-browse conversion window.',
  offseason_bid_multiplier = 0.8,
  offseason_budget_multiplier = 0.6,
  offseason_tos_add_pct = 0,
  offseason_notes = 'Smaller audience pool in off-season. Keep running but at reduced spend. Focus on cross-sell to existing customers.',
  season_applicability = 'ALL_SEASONS',
  min_experiments_to_graduate = 2,
  min_days_to_graduate = 28,
  min_seasonal_lift_to_graduate = 0.0,
  updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'RETARGETING';


-- =============================================
-- PART 2: DIM_EXPERIMENT lifecycle extensions
-- =============================================

-- Lifecycle stage tracks the experiment's progression toward becoming a rule
ALTER TABLE `onyga-482313.OI.DIM_EXPERIMENT`
  ADD COLUMN IF NOT EXISTS lifecycle_stage STRING;
  -- Values: HYPOTHESIS, ACTIVE, REVIEW, VALIDATED, GRADUATED, FAILED, PAUSED, INCONCLUSIVE

-- Graduation metadata
ALTER TABLE `onyga-482313.OI.DIM_EXPERIMENT`
  ADD COLUMN IF NOT EXISTS graduation_date DATE,
  ADD COLUMN IF NOT EXISTS graduation_confidence STRING,
  ADD COLUMN IF NOT EXISTS graduation_criteria_met STRING;
  -- confidence: LOW, MEDIUM, HIGH
  -- criteria_met: comma-separated list of passed criteria

-- Track which seasonal period the experiment ran in
ALTER TABLE `onyga-482313.OI.DIM_EXPERIMENT`
  ADD COLUMN IF NOT EXISTS season_context STRING;
  -- PEAK, OFF_SEASON, NORMAL, MIXED (spans multiple seasons)

-- Set existing experiments to default lifecycle stage
UPDATE `onyga-482313.OI.DIM_EXPERIMENT`
SET lifecycle_stage = status
WHERE lifecycle_stage IS NULL;


-- =============================================
-- PART 3: FACT_GRADUATED_RULES
-- When experiments graduate, their proven settings become "rules"
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_GRADUATED_RULES` (
  -- Primary Key
  rule_id STRING NOT NULL,

  -- Link to source experiment
  experiment_id STRING NOT NULL,
  strategy_id STRING,

  -- What this rule applies to
  asin STRING NOT NULL,
  keyword_pattern STRING,           -- specific keyword or keyword pattern
  keyword_match_type STRING,        -- EXACT, BROAD, PHRASE

  -- The proven settings (snapshot from the graduated experiment)
  campaign_type STRING,
  bidding_strategy STRING,
  bid_amount FLOAT64,               -- the actual bid that worked
  daily_budget FLOAT64,
  top_of_search_pct INT64,
  product_page_pct INT64,

  -- Performance at graduation (evidence)
  seasonal_organic_lift_pct FLOAT64,
  total_orders_lift_pct FLOAT64,
  roas FLOAT64,
  experiment_days INT64,
  seasonal_index_avg FLOAT64,       -- seasonal context when graduated

  -- Rule lifecycle
  rule_status STRING NOT NULL,       -- ACTIVE_RULE, SUSPENDED, RETIRED, SUPERSEDED
  graduated_at TIMESTAMP NOT NULL,
  suspended_at TIMESTAMP,
  retired_at TIMESTAMP,
  superseded_by STRING,              -- rule_id of the replacement rule

  -- Seasonal context: was this proven in peak, off-season, or both?
  proven_in_peak BOOL DEFAULT FALSE,
  proven_in_offseason BOOL DEFAULT FALSE,
  proven_in_normal BOOL DEFAULT FALSE,

  -- Re-validation tracking
  last_revalidation_date DATE,
  revalidation_count INT64 DEFAULT 0,
  consecutive_failures INT64 DEFAULT 0,  -- auto-suspend after 2 consecutive failures

  -- Metadata
  notes STRING,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),

  PRIMARY KEY (rule_id) NOT ENFORCED
)
OPTIONS (
  description = "Proven advertising rules graduated from successful experiments. Each rule is a validated set of campaign settings for a specific ASIN/keyword combination."
);
