-- V_CAMPAIGN_MAPPING_STATUS — campaign → family/strategy mapping state for the cockpit's
-- Configure modal (GET /api/admin/campaign-mapping).
--
-- One row per ENABLED campaign with spend in the last 60 days: its CURRENT assignment, a
-- deterministic family/strategy SUGGESTION parsed from the campaign name (mirrors
-- SP_AUTO_ASSIGN_CAMPAIGNS), a confidence, and a source tag.
--
-- DEDUP (Ori 2026-07-23): experiments are retired — only the strategy is live — but
-- DIM_EXPERIMENT_CAMPAIGN still holds legacy multi-experiment rows per campaign. The
-- camp_map CTE collapses them to one row so this view returns exactly one row per campaign.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_MAPPING_STATUS` AS
WITH

-- Canonical product families (for fuzzy fallback)
families AS (
  SELECT DISTINCT parent_name AS family
  FROM `onyga-482313.OI.DIM_PRODUCT`
  WHERE parent_name IS NOT NULL AND parent_name != '' AND parent_name != 'UNKNOWN'
),

-- ENABLED campaigns with spend in the last 60 days
base AS (
  SELECT
    c.campaign_id,
    c.campaign_name,
    SUM(f.Ads_cost) AS spend_60d
  FROM `onyga-482313.OI.DIM_CAMPAIGN` c
  JOIN (
    SELECT campaign_id, Ads_cost
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
  ) f ON c.campaign_id = f.campaign_id
  WHERE c.is_current = TRUE AND c.state = 'ENABLED'
  GROUP BY c.campaign_id, c.campaign_name
),

-- Fuzzy fallback: longest family name that appears anywhere in the campaign name
fuzzy AS (
  SELECT campaign_id, family FROM (
    SELECT
      b.campaign_id,
      fa.family,
      ROW_NUMBER() OVER (PARTITION BY b.campaign_id ORDER BY LENGTH(fa.family) DESC) AS rn
    FROM base b
    CROSS JOIN families fa
    WHERE STRPOS(UPPER(b.campaign_name), UPPER(fa.family)) > 0
  )
  WHERE rn = 1
),

-- ONE mapping row per campaign (dedup). DIM_EXPERIMENT_CAMPAIGN can still hold several
-- legacy experiment rows for the same campaign — experiments are retired, only the STRATEGY
-- is live (Ori 2026-07-23) — and joining it raw fanned this view out (60 rows / 54 campaigns),
-- which triplicated rows in the cockpit's Configure modal. Collapse to a single row per
-- campaign: prefer a row carrying a real strategy_id, then a manual assignment, then stable
-- by experiment_id. Every duplicated campaign resolves to ONE strategy, so nothing is lost.
camp_map AS (
  SELECT campaign_id, experiment_id, notes, strategy_id, experiment_name, description
  FROM (
    SELECT
      ec.campaign_id,
      ec.experiment_id,
      ec.notes,
      e.strategy_id,
      e.experiment_name,
      e.description,
      ROW_NUMBER() OVER (
        PARTITION BY ec.campaign_id
        ORDER BY
          IF(e.strategy_id IN ('AUTO','BROAD_SP','BROAD_VIDEO','BROAD_SPOTLIGHT','PHRASE','EXACT','COMPETITOR','BRAND_DEFENSE','PRODUCT_DEFENSE'), 0, 1),
          IF(STARTS_WITH(COALESCE(ec.notes, ''), 'manual:'), 0, 1),
          ec.experiment_id
      ) AS rn
    FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
    LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  )
  WHERE rn = 1
),

enriched AS (
  SELECT
    b.campaign_id,
    b.campaign_name,
    ROUND(b.spend_60d, 2) AS spend_60d,

    -- ─── current assignment ───
    ec.experiment_id AS current_experiment_id,
    ec.experiment_name AS current_experiment_name,
    ec.strategy_id AS current_strategy_id,
    ec.notes AS current_notes,
    ec.description AS current_exp_description,

    -- ─── deterministic STRATEGY suggestion (mirrors SP_AUTO_ASSIGN_CAMPAIGNS) ───
    CASE
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'BRAND.?DEF') THEN 'BRAND_DEFENSE'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'PRODUCT.?DEF') THEN 'PRODUCT_DEFENSE'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'\bBOOST\b') THEN 'EXACT'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'/EXACT\b|[- ]EXACT\b') THEN 'EXACT'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'CONQUEST|COPYCAT') THEN 'COMPETITOR'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'SP/AUTO\b|AUTO.*DISCOVERY|DISCOVERY') THEN 'AUTO'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'BROAD|PHRASE|HUNTER|STORE') THEN 'BROAD_SP'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'/PT\b') THEN 'COMPETITOR'
      ELSE 'BROAD_SP'
    END AS suggested_strategy,

    -- did the name match an EXPLICIT strategy (i.e. not the ELSE default)?
    REGEXP_CONTAINS(UPPER(b.campaign_name),
      r'BRAND.?DEF|PRODUCT.?DEF|\bBOOST\b|/EXACT\b|[- ]EXACT\b|CONQUEST|COPYCAT|SP/AUTO\b|AUTO.*DISCOVERY|DISCOVERY|BROAD|PHRASE|HUNTER|STORE|/PT\b'
    ) AS name_explicit_strategy,

    -- ─── deterministic FAMILY suggestion: prefix rules → canonical name ───
    CASE
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'^FRESH') THEN 'Fresh'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'^ME[- /]|^LOLLIME') THEN 'LolliME'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'^BOX[- /]|^LOLLIBOX|^WHITE|^PINK|^PURPLE|^BLUE') THEN 'Lollibox'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'^BOTTLE|^TRUTH') THEN 'Bottle'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'^BUNNY') THEN 'Bunny'
      WHEN REGEXP_CONTAINS(UPPER(b.campaign_name), r'^BALL|^LOLLIBALL') THEN 'LolliBall'
      ELSE NULL
    END AS prefix_family,

    -- fuzzy fallback: a family name appears anywhere in the campaign name
    fz.family AS fuzzy_family,

    -- keyword theme for experiment_id (same extraction as SP)
    REGEXP_EXTRACT(b.campaign_name, r'\((?:Boost, ?)?(.+?)\)') AS keyword_theme

  FROM base b
  LEFT JOIN fuzzy fz ON b.campaign_id = fz.campaign_id
  LEFT JOIN camp_map ec ON b.campaign_id = ec.campaign_id
)

SELECT
  campaign_id,
  campaign_name,
  spend_60d,
  current_experiment_id,
  current_experiment_name,
  current_strategy_id,

  -- family of the CURRENT experiment — experiment_name follows the "<Family> - <label>"
  -- convention (assign endpoint + SP_AUTO_ASSIGN_CAMPAIGNS). Without this the UI can only
  -- prefill from the SUGGESTION, so a manual mapping to a family the suggester wouldn't
  -- pick (e.g. Store) looks like it never saved.
  NULLIF(TRIM(SPLIT(COALESCE(current_experiment_name, ''), ' - ')[SAFE_OFFSET(0)]), '') AS current_family,

  -- resolved family suggestion
  COALESCE(prefix_family, fuzzy_family, 'UNKNOWN') AS suggested_family,
  suggested_strategy,

  -- experiment_id the assign endpoint will target / create (mirrors the SP)
  UPPER(CONCAT(
    REGEXP_REPLACE(UPPER(COALESCE(prefix_family, fuzzy_family, 'UNKNOWN')), r'[^A-Z0-9]', ''),
    '_', suggested_strategy, '_',
    REGEXP_REPLACE(UPPER(COALESCE(keyword_theme, 'GENERAL')), r'[^A-Z0-9]', '_')
  )) AS suggested_experiment_id,

  -- confidence of the suggestion
  CASE
    WHEN prefix_family IS NOT NULL AND name_explicit_strategy THEN 'high'
    WHEN COALESCE(prefix_family, fuzzy_family) IS NOT NULL THEN 'medium'
    ELSE 'low'
  END AS confidence,

  -- source tag (precedence: unmapped > manual > default > auto)
  CASE
    WHEN current_experiment_id IS NULL THEN 'unmapped'
    WHEN STARTS_WITH(COALESCE(current_notes, ''), 'manual:') THEN 'manual'
    WHEN NOT name_explicit_strategy OR COALESCE(prefix_family, fuzzy_family) IS NULL THEN 'default'
    ELSE 'auto'
  END AS source
FROM enriched
