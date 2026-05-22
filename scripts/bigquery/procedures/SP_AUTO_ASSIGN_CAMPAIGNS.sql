-- =============================================
-- OI Database Project - SP_AUTO_ASSIGN_CAMPAIGNS
-- =============================================
--
-- Purpose: Automatically assign campaigns without experiments to DIM_EXPERIMENT_CAMPAIGN.
--          Parses campaign names to infer strategy_id and product family,
--          then finds or creates the matching experiment.
--
-- Run frequency: Daily (in SP_ORCHESTRATE_DAILY_REFRESH)
--
-- Logic:
-- 1. Find ENABLED campaigns in campaign_history that have NO row in DIM_EXPERIMENT_CAMPAIGN
-- 2. Parse campaign_name to infer strategy_id and family
-- 3. Find an existing ACTIVE experiment with matching strategy_id + family prefix
-- 4. If no match: create a new experiment in DIM_EXPERIMENT
-- 5. Insert into DIM_EXPERIMENT_CAMPAIGN
--
-- Naming patterns (from campaign_name):
--   Strategy:  Boost → EXACT_BOOST, Broad/Phrase/Store → HUNTER,
--              Auto/Discovery → LOW_COST_DISCOVERY, Brand Def → BRAND_DEFENSE,
--              Product Def → PRODUCT_DEFENSE, Conquest/Copycat/PT → COMPETITOR_CONQUEST
--   Family:    FRESH- → fresh, ME- → LolliME, BOX-/BOX /WHITE/PINK/PURPLE/BLUE → lollibox,
--              BOTTLE-/TRUTH → Truth Or Dare, HAPPY/BRAND → Happy Lolli
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_AUTO_ASSIGN_CAMPAIGNS`()
OPTIONS (
  description = "Auto-assign unregistered campaigns to experiments based on campaign name patterns. Creates new experiments when needed."
)
BEGIN
  DECLARE records_inserted_exp INT64 DEFAULT 0;
  DECLARE records_inserted_ec INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- ─── Step 1: Find unassigned ENABLED campaigns ───
  CREATE TEMP TABLE _unassigned AS
  WITH
  -- Latest campaign info from DIM_CAMPAIGN
  all_campaigns AS (
    SELECT 
      campaign_id, 
      campaign_name, 
      state, 
      campaign_type as source
    FROM `onyga-482313.OI.DIM_CAMPAIGN`
    WHERE is_current = TRUE
  ),
  -- Only campaigns with recent activity (last 60 days)
  active_campaigns AS (
    SELECT DISTINCT campaign_id
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
  )
  SELECT
    ac.campaign_id,
    ac.campaign_name,
    ac.state,

    -- Infer strategy from campaign name
    CASE
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'BRAND.?DEF') THEN 'BRAND_DEFENSE'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'PRODUCT.?DEF') THEN 'PRODUCT_DEFENSE'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'\bBOOST\b') THEN 'EXACT_BOOST'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'/EXACT\b|[- ]EXACT\b') THEN 'EXACT_BOOST'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'CONQUEST|COPYCAT') THEN 'COMPETITOR_CONQUEST'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'SP/AUTO\b|AUTO.*DISCOVERY|DISCOVERY') THEN 'LOW_COST_DISCOVERY'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'BROAD|PHRASE|HUNTER|STORE') THEN 'HUNTER'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'/PT\b') THEN 'COMPETITOR_CONQUEST'
      ELSE 'HUNTER'  -- Default: broad discovery
    END as inferred_strategy,

    -- Infer family prefix from campaign name
    CASE
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'^FRESH') THEN 'FRESH'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'^ME[- /]|^LOLLIME') THEN 'LOLLIME'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'^BOX[- /]|^LOLLIBOX|^WHITE|^PINK|^PURPLE|^BLUE') THEN 'LOLLIBOX'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'^BOTTLE|^TRUTH') THEN 'BOTTLE'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'^HAPPY|^BRAND') THEN 'HAPPY_LOLLI'
      ELSE 'UNKNOWN'
    END as family_prefix,

    -- Infer campaign type
    CASE
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'VIDEO') THEN 'SB'
      WHEN REGEXP_CONTAINS(UPPER(ac.campaign_name), r'SP/|SP |-SP\b|SP-') THEN 'SP'
      ELSE ac.source
    END as inferred_type,

    -- Extract keyword theme from parentheses: e.g., "Boost, 13 year old girl" → "13 year old girl"
    REGEXP_EXTRACT(ac.campaign_name, r'\((?:Boost, ?)?(.+?)\)') as keyword_theme

  FROM all_campaigns ac
  JOIN active_campaigns act ON ac.campaign_id = act.campaign_id
  LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec ON ac.campaign_id = ec.campaign_id
  WHERE ec.campaign_id IS NULL  -- Not already assigned
    AND ac.state = 'ENABLED';   -- Only enabled campaigns

  -- ─── Step 2: Create missing experiments ───
  -- Generate experiment_id from family + strategy + keyword theme
  -- Only create if no matching ACTIVE experiment exists
  INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT` (
    experiment_id, experiment_name, description, start_date, baseline_days,
    status, strategy_id, lifecycle_stage, season_context, created_at, updated_at
  )
  SELECT DISTINCT
    -- Generate experiment_id: FAMILY_STRATEGY_KEYWORD
    UPPER(CONCAT(
      u.family_prefix, '_',
      u.inferred_strategy, '_',
      REGEXP_REPLACE(UPPER(COALESCE(u.keyword_theme, 'GENERAL')), r'[^A-Z0-9]', '_')
    )) as experiment_id,
    -- Human-readable name
    CONCAT(
      CASE u.family_prefix
        WHEN 'FRESH' THEN 'Fresh'
        WHEN 'LOLLIME' THEN 'LolliME'
        WHEN 'LOLLIBOX' THEN 'Lollibox'
        WHEN 'BOTTLE' THEN 'Truth Or Dare'
        WHEN 'HAPPY_LOLLI' THEN 'Happy Lolli'
        ELSE u.family_prefix
      END,
      ' - ',
      CASE u.inferred_strategy
        WHEN 'EXACT_BOOST' THEN 'Exact Boost'
        WHEN 'HUNTER' THEN 'Broad Hunter'
        WHEN 'LOW_COST_DISCOVERY' THEN 'Auto Discovery'
        WHEN 'BRAND_DEFENSE' THEN 'Brand Defense'
        WHEN 'PRODUCT_DEFENSE' THEN 'Product Defense'
        WHEN 'COMPETITOR_CONQUEST' THEN 'Competitor Conquest'
        ELSE u.inferred_strategy
      END,
      CASE WHEN u.keyword_theme IS NOT NULL
        THEN CONCAT(' (', u.keyword_theme, ')')
        ELSE ''
      END
    ) as experiment_name,
    CONCAT('Auto-created by SP_AUTO_ASSIGN_CAMPAIGNS on ', CAST(CURRENT_DATE() AS STRING)) as description,
    CURRENT_DATE() as start_date,
    14 as baseline_days,
    'ACTIVE' as status,
    u.inferred_strategy as strategy_id,
    'ACTIVE' as lifecycle_stage,
    'EVERGREEN' as season_context,
    CURRENT_TIMESTAMP() as created_at,
    CURRENT_TIMESTAMP() as updated_at
  FROM _unassigned u
  WHERE NOT EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT` e
    WHERE e.experiment_id = UPPER(CONCAT(
      u.family_prefix, '_',
      u.inferred_strategy, '_',
      REGEXP_REPLACE(UPPER(COALESCE(u.keyword_theme, 'GENERAL')), r'[^A-Z0-9]', '_')
    ))
  )
  AND u.family_prefix != 'UNKNOWN';

  SET records_inserted_exp = @@row_count;

  -- ─── Step 3: Assign campaigns to experiments ───
  INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` (
    experiment_id, campaign_id, campaign_name
  )
  SELECT
    UPPER(CONCAT(
      u.family_prefix, '_',
      u.inferred_strategy, '_',
      REGEXP_REPLACE(UPPER(COALESCE(u.keyword_theme, 'GENERAL')), r'[^A-Z0-9]', '_')
    )) as experiment_id,
    u.campaign_id,
    u.campaign_name
  FROM _unassigned u
  WHERE u.family_prefix != 'UNKNOWN';

  SET records_inserted_ec = @@row_count;

  DROP TABLE _unassigned;

  -- Log results
  SELECT FORMAT(
    'SP_AUTO_ASSIGN_CAMPAIGNS completed:\n' ||
    '  New experiments created: %d\n' ||
    '  Campaigns assigned: %d\n' ||
    '  Duration: %d seconds',
    records_inserted_exp,
    records_inserted_ec,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
