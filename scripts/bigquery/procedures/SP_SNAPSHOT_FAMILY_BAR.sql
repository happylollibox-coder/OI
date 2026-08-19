-- =============================================
-- SP_SNAPSHOT_FAMILY_BAR — materializes V_FAMILY_BAR into T_FAMILY_BAR (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §4.
--
-- WHY A SNAPSHOT AND NOT A VIEW READ: the bid engines (V_KEYWORD_LIFT, V_OOB_KEYWORD) are each at
-- BigQuery's planning ceiling. On 2026-08-17 V_PANEL_OWNERSHIP stopped planning outright because it
-- inlined V_LOW_STOCK_ADS, and the repair was exactly this pattern. The engines LEFT JOIN this
-- TABLE and never the view.
--
-- Fully derived and idempotent: CREATE OR REPLACE TABLE from the view. Safe to run repeatedly.
-- Runs EARLY in the orchestrator, before the engine T_ builds, so the engines compile against the
-- bars of the run they are part of.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_FAMILY_BAR`()
OPTIONS (
  description = "Materializes V_FAMILY_BAR into T_FAMILY_BAR (2026-08-19), exploded to CAMPAIGN grain: one row per ENABLED campaign that V_CAMPAIGN_FAMILY_MAP resolves to a real family, carrying that family's measured halo factor and the keyword bar the bid engines judge ads-attributed GP-ROAS against. Campaigns in the map's 'Unknown' bucket have no family and therefore no bar: they are deliberately ABSENT, and the engines' LEFT JOIN + COALESCE(keyword_bar, 1.0) leaves them at today's behaviour. Exists because the engines are at BigQuery's planning ceiling and must join a table, never inline the view. Idempotent. Orchestrator task 20.4, before the engine T_ builds. Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md."
)
BEGIN
  -- CAMPAIGN GRAIN, deliberately. The bid engines publish campaign_id and NOT family (verified
  -- 2026-08-19: neither V_KEYWORD_LIFT nor V_OOB_KEYWORD has a family/parent column). Resolving
  -- family inside those views would mean joining V_CAMPAIGN_FAMILY_MAP inside a planner-ceiling
  -- view — exactly the move that broke V_PANEL_OWNERSHIP on 2026-08-17. So the explosion happens
  -- HERE, once, and the engines do a single LEFT JOIN on a key they already carry.
  --
  -- The join is an INNER JOIN on purpose. V_CAMPAIGN_FAMILY_MAP emits a literal 'Unknown' bucket
  -- for campaigns it cannot resolve; 'Unknown' is not a family in V_FAMILY_BAR, so those campaigns
  -- fall out here and get no bar. That is the intended behaviour — a campaign with no measured
  -- halo must not be handed one. Both sides are unique on their key (the map QUALIFYs to one row
  -- per campaign_id; the bar is one row per family), so this join neither drops a mapped campaign
  -- nor duplicates one.
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_FAMILY_BAR` AS
  SELECT
    CAST(m.campaign_id AS STRING) AS campaign_id,
    b.*
  FROM `onyga-482313.OI.V_FAMILY_BAR` b
  JOIN `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` m ON m.parent_name = b.family;
END;
