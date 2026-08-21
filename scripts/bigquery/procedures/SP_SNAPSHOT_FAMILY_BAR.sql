-- =============================================
-- SP_SNAPSHOT_FAMILY_BAR — materializes V_FAMILY_BAR into T_FAMILY_BAR (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §4.
--
-- WHY A SNAPSHOT AND NOT A VIEW READ: the bid engines (V_KEYWORD_LIFT, V_OOB_KEYWORD) are each at
-- BigQuery's planning ceiling. On 2026-08-17 V_PANEL_OWNERSHIP stopped planning outright because it
-- inlined V_LOW_STOCK_ADS, and the repair was exactly this pattern. So this table is built so the
-- engines CAN LEFT JOIN it — a table, never the view.
--
-- READ BY A REPORT, NOT BY AN ENGINE — AND THAT DISTINCTION IS THE WHOLE POINT OF THIS PARAGRAPH.
-- T_FAMILY_BAR now has its first consumer: V_CAMPAIGN_MONEY_PLACEMENT, which joins the bars to
-- report where the advertising money sits. It is a REPORTING read. NO BID ENGINE READS
-- T_FAMILY_BAR, and the bars therefore still change no bid. DO NOT TAKE EITHER HALF OF THAT FROM
-- THIS COMMENT — IT IS THE KIND OF SENTENCE THAT GOES STALE SILENTLY, AND IT HAS ALREADY DONE SO
-- TWICE. Re-verify it in three seconds:
--   SELECT 'VIEW' AS kind, table_name AS name
--   FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`   WHERE view_definition LIKE '%T_FAMILY_BAR%'
--   UNION ALL
--   SELECT 'ROUTINE', routine_name
--   FROM `onyga-482313.OI`.INFORMATION_SCHEMA.ROUTINES WHERE ddl            LIKE '%T_FAMILY_BAR%';
-- THE PASS CONDITION IS A PROPERTY, NOT A COUNT SOMEBODY ONCE SAW (Standing Rule 0; this comment
-- carried an "as of" run result until 2026-08-20, and stamping a measurement with a date was the
-- practice that round 4 abolished — a date makes a stale number look verified). THE PROPERTY, AS
-- REWRITTEN ON 2026-08-21 WHEN THE FIRST READER SHIPPED: the only ROUTINES that may mention this
-- table are the WRITER (this procedure) and its CALLER (SP_ORCHESTRATE_DAILY_REFRESH); the only
-- VIEW that may mention it is V_CAMPAIGN_MONEY_PLACEMENT. Anything else in that output — and in
-- particular V_KEYWORD_LIFT, V_OOB_KEYWORD, V_ADS_COACH or any other bid-setting object — means a
-- bar is now moving a bid and this whole comment is out of date. Run it; do not read a count off
-- this page. The engine join is Task 8 of docs/superpowers/plans/2026-08-19-two-book-pnl.md and
-- Task 8 is unbuilt and on hold.
-- WHEN TASK 8 SHIPS, FLIP THE ENGINE SENTENCE TO THE PRESENT TENSE IN THE SAME COMMIT: this
-- comment and the OPTIONS description below (and the matching clauses in config.yaml under
-- T_FAMILY_BAR, SP_SNAPSHOT_FAMILY_BAR and V_FAMILY_BAR). A doc that says "the engines join it"
-- while nothing does is how a reader concludes the halo is already priced into bids when it is
-- not — and a reporting consumer must never be mistaken for that wiring.
--
-- Fully derived and idempotent: CREATE OR REPLACE TABLE from the view. Safe to run repeatedly.
-- Runs EARLY in the orchestrator, before the engine T_ builds, so the engines compile against the
-- bars of the run they are part of.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_FAMILY_BAR`()
OPTIONS (
  description = "Materializes V_FAMILY_BAR into T_FAMILY_BAR (2026-08-19), exploded to CAMPAIGN grain: one row per ENABLED campaign that V_CAMPAIGN_FAMILY_MAP resolves to a real family, carrying that family's measured halo factor and the keyword bar the bid engines judge ads-attributed GP-ROAS against. Campaigns in the map's 'Unknown' bucket have no family and therefore no bar: they are deliberately ABSENT, and the engines' LEFT JOIN + COALESCE(keyword_bar, 1.0) leaves them at today's behaviour. Exists because the engines are at BigQuery's planning ceiling and must join a table, never inline the view. READ BY A REPORT, NOT BY AN ENGINE: V_CAMPAIGN_MONEY_PLACEMENT joins the bars to report where the advertising money sits, and that is the table's only consumer. NO BID ENGINE READS T_FAMILY_BAR — the engine join is Task 8 of the two-book plan, it is unbuilt and on hold, and the bars therefore still change no bid. The pass condition is a PROPERTY to re-verify against INFORMATION_SCHEMA, never a count read off this description: the only routines that may mention the table are this procedure, which writes it, and SP_ORCHESTRATE_DAILY_REFRESH, which calls it; the only view that may mention it is V_CAMPAIGN_MONEY_PLACEMENT. Any bid-setting object in that output means a bar is moving a bid and this sentence is stale. The engine half flips to the present tense as part of the Task 8 commit, alongside the matching clauses in the file header and in config.yaml. Idempotent. Orchestrator task 20.5g-1, ahead of task 20.5g SP_SNAPSHOT_PANEL_OWNERSHIP and before the engine T_ builds. Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md."
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
