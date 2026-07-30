-- V_CAMPAIGN_ROLE_BY_NAME — strategy + family derived from the CAMPAIGN NAME.
--
-- WHY THIS EXISTS: V_CAMPAIGN_ROLE classifies a campaign from its ad DATA (targeting type, SB
-- format) and is 90-day-activity-gated, so a campaign created today is absent from it — whether or
-- not it has started delivering. Every coverage surface inner-joined that role, so brand-new
-- campaigns vanished from the cockpit for 1-2 days, exactly when you want to confirm what you just
-- built, and a cell whose only campaign was new read "missing" — inviting a duplicate build
-- (Ori 2026-07-24: "show them as ENABLED (0 impressions) under the ENABLED campaigns").
--
-- Parsing names is safe HERE because the cockpit GENERATES these names itself — see
-- FN_COMPETITOR_CAMPAIGN_PLAN and DIM_STRATEGY_CAMPAIGN_TEMPLATE.naming_hint:
--   {PREFIX}-{FORMAT}/{TARGETING} (qualifiers)   e.g. ME-SP/PT (Competitors, Mint, A1)
--
-- CONTRACT: this is a FALLBACK, never an override. Callers must prefer V_CAMPAIGN_ROLE and consult
-- this only when the role is missing — the data-derived classification is always more truthful than
-- a name. Unrecognised names yield NULL strategy_category and are skipped, never guessed into a
-- cell: a wrong cell is worse than an absent one.
--
-- AUTO is intentionally NOT derived. The AUTO cell_key is per-ASIN (`AUTO|<asin>`) and a campaign
-- with no delivery has no ASIN to key on, so an AUTO guess could not be placed anyway.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_ROLE_BY_NAME` AS
WITH camp_state AS (
  -- 2026-07-30: consolidated source (V_DIM_CAMPAIGN_CURRENT / DIM_*) per prefer-DIM/FACT rule; was V_SRC_AmazonAds_campaign_history
  SELECT campaign_id,
    campaign_state AS state,
    campaign_name
  FROM `onyga-482313`.OI.V_DIM_CAMPAIGN_CURRENT
  WHERE campaign_name IS NOT NULL
)
SELECT
  cst.campaign_id,
  cst.campaign_name,
  cst.state,
  -- Family: the curated override wins; else the account's short product code prefix. Same map as
  -- FN_COMPETITOR_CAMPAIGN_PLAN.grp_named, inverted (the live account uses BOX, not "Lollibox").
  COALESCE(dcf.parent_name,
    CASE REGEXP_EXTRACT(cst.campaign_name, r'^([A-Z]+)-')
      WHEN 'BOX'    THEN 'Lollibox'
      WHEN 'ME'     THEN 'LolliME'
      WHEN 'BALL'   THEN 'LolliBall'
      WHEN 'BOTTLE' THEN 'Bottle'
      WHEN 'FRESH'  THEN 'Fresh'
      WHEN 'BUNNY'  THEN 'Bunny'
    END) AS parent_name,
  CASE
    WHEN REGEXP_CONTAINS(cst.campaign_name, r'(?i)/PT \((Competitors|Conquest)') THEN 'COMPETITOR'
    WHEN REGEXP_CONTAINS(cst.campaign_name, r'(?i)/PT \(Defense')                THEN 'PRODUCT_DEFENSE'
    WHEN REGEXP_CONTAINS(cst.campaign_name, r'(?i)Brand Defense')                THEN 'BRAND_DEFENSE'
    WHEN REGEXP_CONTAINS(cst.campaign_name, r'(?i)/BROAD') THEN
      CASE WHEN REGEXP_CONTAINS(cst.campaign_name, r'(?i)VIDEO')           THEN 'BROAD_VIDEO'
           WHEN REGEXP_CONTAINS(cst.campaign_name, r'(?i)STORE|SPOTLIGHT') THEN 'BROAD_SPOTLIGHT'
           ELSE 'BROAD_SP' END
    WHEN REGEXP_CONTAINS(cst.campaign_name, r'(?i)/PHRASE') THEN 'PHRASE'
    WHEN REGEXP_CONTAINS(cst.campaign_name, r'(?i)/EXACT')  THEN 'EXACT'
    ELSE NULL
  END AS strategy_category
FROM camp_state cst
LEFT JOIN `onyga-482313`.OI.DE_CAMPAIGN_FAMILY dcf
  ON CAST(dcf.campaign_id AS STRING) = cst.campaign_id;
