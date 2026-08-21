-- =============================================
-- SP_SNAPSHOT_FAMILY_BAR — materializes V_FAMILY_BAR into T_FAMILY_BAR (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §4.
--
-- WHY A SNAPSHOT AND NOT A VIEW READ: the bid engines (V_KEYWORD_LIFT, V_OOB_KEYWORD) are each at
-- BigQuery's planning ceiling. On 2026-08-17 V_PANEL_OWNERSHIP stopped planning outright because it
-- inlined V_LOW_STOCK_ADS, and the repair was exactly this pattern. So this table is built so the
-- engines CAN LEFT JOIN it — a table, never the view.
--
-- READ BY A BID ENGINE SINCE v27.100 (2026-08-21, Task 8) — AND BY ONE ENGINE, NOT TWO.
-- V_KEYWORD_LIFT LEFT JOINs T_FAMILY_BAR on CAST(campaign_id AS STRING) and its CUT_TO_BREAKEVEN
-- arm compares the window net ROAS against COALESCE(keyword_bar, 1.0) instead of a flat 1.0, with
-- bar_exempt families skipped. V_OOB_KEYWORD was deliberately NOT wired: it carries no flat
-- breakeven arm, only the dark brake and the seat trim, which judge on budget darkness and on
-- capacity and which Task 8's non-goal protects on an Invest family. V_CAMPAIGN_MONEY_PLACEMENT
-- remains a REPORTING read and changes no bid. DO NOT TAKE ANY OF THAT FROM THIS COMMENT — IT IS
-- THE KIND OF SENTENCE THAT GOES STALE SILENTLY, AND IT HAS ALREADY DONE SO TWICE.
-- Re-verify it in three seconds:
--   SELECT 'VIEW' AS kind, table_name AS name
--   FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`   WHERE view_definition LIKE '%T_FAMILY_BAR%'
--   UNION ALL
--   SELECT 'ROUTINE', routine_name
--   FROM `onyga-482313.OI`.INFORMATION_SCHEMA.ROUTINES WHERE ddl            LIKE '%T_FAMILY_BAR%';
-- THE PASS CONDITION IS A PROPERTY, NOT A COUNT SOMEBODY ONCE SAW (Standing Rule 0; this comment
-- carried an "as of" run result until 2026-08-20, and stamping a measurement with a date was the
-- practice that round 4 abolished — a date makes a stale number look verified). THE PROPERTY, AS
-- REWRITTEN ON 2026-08-21 WHEN THE ENGINE JOIN SHIPPED: the only ROUTINES that may mention this
-- table are the WRITER (this procedure) and its CALLER (SP_ORCHESTRATE_DAILY_REFRESH); the VIEWS
-- that may mention it are the reporting read V_CAMPAIGN_MONEY_PLACEMENT and the bid engine
-- V_KEYWORD_LIFT. Anything else in that output — and in particular V_OOB_KEYWORD or V_ADS_COACH —
-- means a SECOND bid engine was wired and this whole comment is out of date. Run it; do not read a
-- count off this page.
-- ORDER IS THE CONTRACT, AND IT IS THE HALF MOST LIKELY TO BREAK QUIETLY: this procedure is
-- orchestrator task 20.5g-1 and must stay AHEAD of every reader of V_KEYWORD_LIFT, so the engine
-- compiles against the bars of the run it is part of. Move it later and the engine silently prices
-- yesterday's halo — no error, no alarm, just an older bar.
--
-- Fully derived and idempotent: CREATE OR REPLACE TABLE from the view. Safe to run repeatedly.
-- Runs EARLY in the orchestrator, before the engine T_ builds, so the engines compile against the
-- bars of the run they are part of.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_FAMILY_BAR`()
OPTIONS (
  description = "Materializes V_FAMILY_BAR into T_FAMILY_BAR (2026-08-19), exploded to CAMPAIGN grain: one row per ENABLED campaign that V_CAMPAIGN_FAMILY_MAP resolves to a real family, carrying that family's measured halo factor and the keyword bar the bid engines judge ads-attributed GP-ROAS against. Campaigns in the map's 'Unknown' bucket have no family and therefore no bar: they are deliberately ABSENT, and the engines' LEFT JOIN + COALESCE(keyword_bar, 1.0) leaves them at today's behaviour. Exists because the engines are at BigQuery's planning ceiling and must join a table, never inline the view. READ BY A BID ENGINE SINCE v27.100 (2026-08-21, Task 8), AND BY ONE ENGINE ONLY: V_KEYWORD_LIFT LEFT JOINs this table and its breakeven cut arm judges against COALESCE(keyword_bar, 1.0) instead of a flat 1.0, skipping bar_exempt families. V_OOB_KEYWORD was deliberately NOT wired — it has no flat breakeven arm, only pacing and capacity levers. V_CAMPAIGN_MONEY_PLACEMENT remains a reporting read that changes no bid. The pass condition is a PROPERTY to re-verify against INFORMATION_SCHEMA, never a count read off this description: the only routines that may mention the table are this procedure, which writes it, and SP_ORCHESTRATE_DAILY_REFRESH, which calls it; the only views that may mention it are V_CAMPAIGN_MONEY_PLACEMENT and V_KEYWORD_LIFT. A second bid engine in that output means this sentence is stale. Idempotent. Orchestrator task 20.5g-1, ahead of task 20.5g SP_SNAPSHOT_PANEL_OWNERSHIP and before the engine T_ builds. Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md."
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
