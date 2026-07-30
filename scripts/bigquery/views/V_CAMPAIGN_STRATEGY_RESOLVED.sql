-- V_CAMPAIGN_STRATEGY_RESOLVED: one row per CURRENT campaign with a resolved strategy_id.
-- Precedence: manual override > Automatic targeting > experiment mapping (normalized) > inline name classifier > UNCLASSIFIED.
-- Grain: one row per campaign_id (is_current).
--
-- Fix history (2026-07-22): targeting now outranks the legacy experiment mapping (autos were folded into
-- INTENT by the mapping view); mapping-status join deduped (fixes fan-out/double-counted spend on renamed
-- campaigns); name classifier computed inline from DIM_CAMPAIGN.campaign_name so PAUSED-but-spending
-- campaigns (never enter the ENABLED-filtered mapping view) still classify; mapping strategy normalized
-- to the canonical 6-strategy enum (HUNTER/LOW_COST_DISCOVERY→INTENT, COMPETITOR_CONQUEST→COMPETITOR;
-- unrecognized→NULL so nothing stray leaks through).
--
-- Fix history (2026-07-23): the UNCLASSIFIED bucket was over-full (36 spending campaigns, $39.9k) and
-- Family showed '--' for 165 of 279 spending campaigns. Causes and fixes:
--   1. `COMPETE` never matched COMPETITOR / COMPETITORS / COMPETITION → widened to `COMPET`.
--   2. `PRODUCT.?DEF` never matched `BOX-SP/DEFENSE (Cross-sell ...)` → added CROSS-SELL / DEFENSE rules.
--   3. `\bAUTO\b` never matched "Automatic" / "AUTOM" / "AUTO1" / the "AUT0" typo → widened.
--   4. bare `DISCOVERY` forced AUTO, misfiling broad/store SB campaigns ("BRAND-STORE/BROAD (Discovery,
--      old one)") → DISCOVERY alone no longer implies AUTO; it must be qualified (AUTO…DISCOVERY).
--   5. Targeting evidence is now LIFETIME, not 120d (targeting_type is immutable per campaign in Amazon,
--      so a dormant campaign's history is still valid evidence), and the share denominator counts only
--      rows where targeting_type IS NOT NULL. Many SB/legacy rows carry a NULL targeting_type; folding
--      those into the denominator made a genuine auto campaign look manual and vetoed the name rule.
--      No known targeting rows ⇒ no evidence ⇒ the name classifier decides.
--   6. Known non-auto targeting now VETOES a name-derived AUTO (a broad-targeted campaign is not AUTO
--      however it is named), and SB is never AUTO — Sponsored Brands has no automatic targeting
--      (verified: 0 Automatic rows across 75,800 SB rows).
--   7. Family: the ASIN join was windowed to 120d, so dormant campaigns lost their family. Widened to
--      lifetime (+50 campaigns) and added a campaign-name fallback for the ~115 campaigns that carry no
--      own-ASIN in FACT at all (SB video/store campaigns mostly report no advertised ASIN).
--      `family_source` ('asin'|'name') keeps it auditable.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_STRATEGY_RESOLVED` AS
WITH
targeting AS (
  -- Lifetime targeting evidence. targeting_type is fixed at campaign creation in Amazon, so there is no
  -- recency requirement. Rows with a NULL targeting_type carry no evidence and are excluded entirely —
  -- a campaign absent here simply has no targeting evidence.
  SELECT
    campaign_id,
    COALESCE(
      SAFE_DIVIDE(SUM(IF(UPPER(targeting_type) = 'AUTOMATIC', Ads_cost, 0)), NULLIF(SUM(Ads_cost), 0)),
      -- impressions-only campaigns have no spend to weight by; fall back to row share
      SAFE_DIVIDE(COUNTIF(UPPER(targeting_type) = 'AUTOMATIC'), COUNT(*))
    ) AS auto_spend_share
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE targeting_type IS NOT NULL
  GROUP BY campaign_id
),
fam_asin AS (
  -- Lifetime; heaviest-spend own-product parent wins. 'UNKNOWN' is a real parent_name in DIM_PRODUCT and
  -- is no better than no answer, so it falls through to the name rule.
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC, p.parent_name) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.most_advertised_asin_impressions
    WHERE p.parent_name IS NOT NULL AND p.parent_name <> 'UNKNOWN'
    GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
map AS (  -- dedupe: V_CAMPAIGN_MAPPING_STATUS fans out on renamed campaigns
  SELECT campaign_id, current_strategy_id FROM (
    SELECT campaign_id, current_strategy_id,
      ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY spend_60d DESC) rn
    FROM `onyga-482313.OI.V_CAMPAIGN_MAPPING_STATUS`
  ) WHERE rn = 1
),
base AS (
  SELECT
    c.campaign_id, c.campaign_name, c.campaign_type,
    -- Campaign age. Same source (DIM_CAMPAIGN.creation_date), same NY-timezone DATE_DIFF and the same
    -- <=20 / <=90 / <=270 boundaries as V_BUDGET_STEP1_CAMPAIGN, so the Ads-page age filter and the
    -- Weekly Run "Budget by age" split always bucket a campaign identically. Keep them in sync.
    DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(c.creation_date), DAY) AS age_days,
    CASE
      WHEN c.creation_date IS NULL THEN 'UNKNOWN'
      WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(c.creation_date), DAY) <= 20  THEN 'NEW'
      WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(c.creation_date), DAY) <= 90  THEN '1-3MO'
      WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(c.creation_date), DAY) <= 270 THEN '4-9MO'
      ELSE '10MO+'
    END AS age_bucket,
    UPPER(c.campaign_name) AS nm,
    fam_asin.parent_name AS asin_family,
    t.auto_spend_share,
    CASE UPPER(map.current_strategy_id)
      WHEN 'AUTO' THEN 'AUTO'
      WHEN 'EXACT_BOOST' THEN 'EXACT'
      WHEN 'INTENT' THEN 'BROAD_SP'
      WHEN 'HUNTER' THEN 'BROAD_SP'
      WHEN 'LOW_COST_DISCOVERY' THEN 'BROAD_SP'
      WHEN 'COMPETITOR' THEN 'COMPETITOR'
      WHEN 'COMPETITOR_CONQUEST' THEN 'COMPETITOR'
      WHEN 'BRAND_DEFENSE' THEN 'BRAND_DEFENSE'
      WHEN 'PRODUCT_DEFENSE' THEN 'PRODUCT_DEFENSE'
      ELSE NULL
    END AS mapped_strategy,
    ovr.strategy_id AS override_strategy_id
  FROM `onyga-482313.OI.DIM_CAMPAIGN` c
  LEFT JOIN map USING (campaign_id)
  LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_STRATEGY` ovr USING (campaign_id)
  LEFT JOIN targeting t USING (campaign_id)
  LEFT JOIN fam_asin USING (campaign_id)
  WHERE c.is_current = TRUE
),
classified AS (
  SELECT
    *,
    -- Name rules that do NOT depend on targeting. Ordered most-specific first.
    CASE
      WHEN REGEXP_CONTAINS(nm, r'BRAND.?DEF') THEN 'BRAND_DEFENSE'
      WHEN REGEXP_CONTAINS(nm, r'PRODUCT.?DEF|CROSS.?SELL|\bDEFENSE\b') THEN 'PRODUCT_DEFENSE'
      WHEN REGEXP_CONTAINS(nm, r'COMPET|CONQUEST|COPYCAT|\bCOMP\b|/PT\b') THEN 'COMPETITOR'
      WHEN REGEXP_CONTAINS(nm, r'\bBOOST\b|/EXACT\b|[- ]EXACT\b|\bEXACT\b') THEN 'EXACT'
      ELSE NULL
    END AS name_strategy_specific,
    -- AUTO by name — gated below on targeting evidence and campaign type.
    -- DISCOVERY alone is NOT auto (it names a goal, not a targeting type); it must be qualified.
    REGEXP_CONTAINS(nm, r'AUTOMATIC|\bAUTOM|\bAUTO\d*\b|\bAUT0\b|AUTO.{0,4}DISCOVERY') AS name_says_auto,
    -- Weakest name rules, tried only after AUTO — deliberately, so that "AUTO LOLLIBOX - SP - Product
    -- Target" resolves AUTO rather than COMPETITOR. DISCOVERY lands on INTENT here (not AUTO), matching
    -- what SP_AUTO_ASSIGN_CAMPAIGNS already does with the token.
    CASE
      WHEN REGEXP_CONTAINS(nm, r'PRODUCT.?TARGET|\bPAT\b') THEN 'COMPETITOR'
      WHEN REGEXP_CONTAINS(nm, r'BROAD|PHRASE|HUNTER|STORE|DISCOVERY') THEN 'BROAD_SP'
      WHEN REGEXP_CONTAINS(nm, r'\bBRAND\b') THEN 'BRAND_DEFENSE'
      ELSE NULL
    END AS name_strategy_weak,
    CASE
      WHEN REGEXP_CONTAINS(nm, r'LOLLI.?ME|\bME-') THEN 'LolliME'
      WHEN REGEXP_CONTAINS(nm, r'LOLLI.?BALL|\bBALL\b') THEN 'LolliBall'
      WHEN REGEXP_CONTAINS(nm, r'\bFRESH\b') THEN 'Fresh'
      WHEN REGEXP_CONTAINS(nm, r'\bBUNN(Y|IES)\b') THEN 'Bunny'
      WHEN REGEXP_CONTAINS(nm, r'\bBOTTLE') THEN 'Bottle'
      WHEN REGEXP_CONTAINS(nm, r'LO+LLI.?BOX|LOOLIBOX|\bBOX\b') THEN 'Lollibox'  -- LOOLIBOX: recurring typo
      ELSE NULL
    END AS name_family
  FROM base
),
resolved AS (
  SELECT
    *,
    -- Known non-auto targeting outranks any AUTO-looking name.
    (auto_spend_share IS NOT NULL AND auto_spend_share < 0.5) AS non_auto_targeted,
    COALESCE(asin_family, name_family) AS parent_name,
    IF(asin_family IS NOT NULL, 'asin', IF(name_family IS NOT NULL, 'name', NULL)) AS family_source
  FROM classified
),
final AS (
  SELECT
    *,
    COALESCE(
      name_strategy_specific,
      IF(name_says_auto AND NOT non_auto_targeted AND campaign_type <> 'SB', 'AUTO', NULL),
      name_strategy_weak
    ) AS name_strategy
  FROM resolved
)
SELECT
  campaign_id, campaign_name, campaign_type, parent_name, family_source,
  age_days, age_bucket,
  auto_spend_share, mapped_strategy, name_strategy, override_strategy_id,
  COALESCE(
    override_strategy_id,
    IF(auto_spend_share >= 0.5, 'AUTO', NULL),
    mapped_strategy,
    name_strategy,
    'UNCLASSIFIED'
  ) AS strategy_id,
  CASE
    WHEN override_strategy_id IS NOT NULL THEN 'override'
    WHEN auto_spend_share >= 0.5 THEN 'targeting'
    WHEN mapped_strategy IS NOT NULL THEN 'mapping'
    WHEN name_strategy IS NOT NULL THEN 'name'
    ELSE 'unclassified'
  END AS strategy_source
FROM final;
