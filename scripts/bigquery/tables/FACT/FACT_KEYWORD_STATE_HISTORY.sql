-- =============================================================================================
-- FACT_KEYWORD_STATE_HISTORY — the Catalog's memory. v27.145 (2026-08-25).
--
-- WHY IT EXISTS. THREE_LAYERS.md §8 violation 6: `FACT_KEYWORD_STATE` is CREATE OR REPLACE'd on
-- every orchestrator pass and holds exactly one snapshot, so the Catalog cannot be asked a
-- historical question and cannot be graded on its own predictions (§6, §6.2: "a layer cannot be
-- graded on predictions it does not keep"). §1.4 requires every layer to hold "durable, queryable
-- state of its own" that a caller can read "directly AND HISTORICALLY". §10.4 names dwell time —
-- how long has this been stuck — as the single highest-value thing to fix first, because its
-- absence obstructs the measurement of every other violation.
--
-- This table is that memory. It is APPEND-ONLY and it is the ONLY object in the account that
-- knows what the ladder said on a day that is not today.
--
-- NOTHING HERE DECIDES ANYTHING. No engine, generator, book or bulksheet reads this table. It
-- records what was already recorded; it cannot move a bid, a budget or a pause. Adding a row here
-- changes nothing about what the account does.
--
-- WHAT IT KEEPS, AND WHY THE WHOLE ROW. The Catalog's scorecard (§6) asks "was the valuation
-- right?" — its own predictions against outcomes. A prediction is not the label alone. It is the
-- verdict TOGETHER WITH the evidence and the arithmetic that justified it: the settled record the
-- verdict was read off, the family bar it was judged against, the noise band that decided whether
-- the gap was real, the affordable price and the floor that made a move executable or not, the
-- mix-drift guard's cleaned re-reading, and the appointment the ladder promised to keep. A narrow
-- (date, subject, state) table would answer dwell and nothing else — it could never answer "you
-- said $0.51 was the price; was it?", which is the question §6 actually poses. So the history
-- keeps EVERY column of the snapshot, plus its own provenance. The cost of that decision is
-- roughly one snapshot's width per day at this account's subject count — small enough that
-- storage is not the constraint; the constraint is that a lost column can never be recovered,
-- because the source table is destroyed nightly.
--
-- SCHEMA EVOLUTION (§2.7 confidence, §2.8 market volume, §4 seasonality are all coming columns).
-- The history is written by SP_APPEND_KEYWORD_STATE_HISTORY, which reads the LIVE column list of
-- FACT_KEYWORD_STATE out of INFORMATION_SCHEMA on every run, ADD COLUMN IF NOT EXISTS-es anything
-- the history is missing, and inserts by explicit column NAME. Three consequences, all deliberate:
--   * a column the Catalog gains tomorrow appears in the history from the day it exists, with no
--     edit to this file and no change to the append step;
--   * partitions written before that day keep NULL for it, which is the honest reading — the
--     Catalog did not say it then, and a backfilled value would be a fabrication;
--   * a column the Catalog DROPS is never dropped here. It stays, holding what it held, and goes
--     NULL going forward. Append-only means the record of a retired field survives its field.
-- The same mechanism is what lets the 2026-08-17..21 backfill rows (a 22-column era of the
-- procedure) sit in the same table as the 65-column rows without either being distorted.
--
-- PARTITION / CLUSTER. Partitioned by snapshot_date because every question asked of this table is
-- bounded in time and because every write, repair and read the writer performs is scoped to a
-- date — the append, the duplicate-stamp prune and the dwell view alike. Clustered by
-- keyword_id first: the doctrinal question §1.4 demands a caller be able to ask is "what did you
-- say about THIS SUBJECT on that date", and the subject is scoped by its keyword id (§2.2 — bare
-- target text is never a valid subject). campaign_id completes the grain, state and family carry
-- the population reads.
--
-- PROVENANCE — THREE CLOCKS, AND THEY ANSWER DIFFERENT QUESTIONS. Every row says when it was
-- written, which build it was copied from, and where it came from, so a recovered row is never
-- mistaken for one the pipeline appended live:
--   snapshot_date      the day the Catalog was speaking ABOUT.
--   captured_at        the moment the row was written into the history.
--   snapshot_built_at  the moment the BUILD of FACT_KEYWORD_STATE that this row was copied from
--                      was made (the snapshot table's own last-modified clock). Added v27.145;
--                      NULL on every row written before then, which is the honest reading — those
--                      rows did not record it, and a backfilled value would be a fabrication.
--   source             'ORCHESTRATOR' for a row appended by the nightly pass; 'BACKFILL_TIME_TRAVEL'
--                      for a row recovered from BigQuery's own 7-day table history.
--   source_detail      free text naming exactly what was read — for a backfill, the time-travel
--                      timestamp, which is the whole audit trail for that row.
--
-- WHY THE THIRD CLOCK EARNS ITS COLUMN (v27.145). With only two clocks, two situations are
-- IDENTICAL in the data. (1) The pass ran, built a fresh snapshot and copied it. (2) The pass's
-- Task 20.8 FAILED — it has its own exception handler, so the append still runs — the previous
-- build was still standing, and copying it again moved captured_at while the build behind it
-- stood still. Case (2) is a falsified provenance record: the row now claims a read time at which
-- the Catalog said nothing new. The writer refuses it (GUARD 3), but a refusal that no check can
-- confirm is a promise, not a property. snapshot_built_at makes the difference visible after the
-- fact and is what acceptance check C14 tests.
--
-- Written by: SP_APPEND_KEYWORD_STATE_HISTORY (orchestrator Task 20.8a, immediately after 20.8).
-- Read by:    V_CATALOG_DWELL, and any caller asking the Catalog a historical question.
-- Acceptance: scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql
-- Spec:       architecture/THREE_LAYERS.md §1.4, §6, §6.2, §8 (violation 6), §10.4.
-- SOP:        architecture/KEYWORD_STATE.md §"The history".
--
-- CREATE TABLE IF NOT EXISTS — re-running this file can never drop a kept snapshot. There is no
-- CREATE OR REPLACE anywhere in this object's lifecycle, and that is the entire point of it.
--
-- THE PRICE OF THAT, AND THE TRAP IT SET ONCE (v27.145). Because this is IF NOT EXISTS, running
-- this file against a table that already exists changes NOTHING — not the columns, and not the
-- OPTIONS description. Editing the text below therefore does NOT update the deployed object, and
-- for one release it did not: the live description went on asserting that the writer "replaces
-- exactly the snapshot's own date partition, so ... no earlier partition is ever touched" after
-- v27.144 had made both halves false, while the registry entry for the same table said the
-- opposite. A person hunting for rows missing from an old partition would have read the live text,
-- ruled the writer out, and looked in the wrong place. ANY CHANGE TO THE SCHEMA OR THE DESCRIPTION
-- OF THIS TABLE MUST SHIP AS AN EXPLICIT ALTER IN scripts/bigquery/migrations/ AND BE MIRRORED
-- HERE — the file is the record, the ALTER is the deployment. The v27.145 pair is
-- scripts/bigquery/migrations/2026-08-25_keyword_state_history_build_clock.sql.
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
(
  snapshot_date              DATE    NOT NULL,
  captured_at                TIMESTAMP NOT NULL,
  -- v27.145. NULL on every row written before it existed. It is declared here beside the other
  -- two clocks because that is where it belongs to a reader; on the LIVE table it sits last,
  -- because it arrived by ALTER TABLE ADD COLUMN. The difference is cosmetic and stays that way:
  -- the writer inserts by explicit column NAME, so ordinal position is never load-bearing.
  snapshot_built_at          TIMESTAMP,
  source                     STRING  NOT NULL,
  source_detail              STRING,

  -- the snapshot's own columns, in the order SP_SNAPSHOT_KEYWORD_STATE publishes them
  campaign_id                STRING,
  keyword_id                 STRING,
  target_text                STRING,
  match_type                 STRING,
  channel                    STRING,
  is_auto                    BOOL,
  is_pt                      BOOL,
  campaign_name              STRING,
  family                     STRING,
  current_bid                FLOAT64,
  state                      STRING,
  owner_engine               STRING,
  state_since                DATE,
  settled_clk90              INT64,
  settled_ord90              INT64,
  settled_roas90             FLOAT64,
  settled_cpc90              FLOAT64,
  settled_gp90               FLOAT64,
  settled_sp90               FLOAT64,
  season_context             BOOL,
  next_check_date            DATE,
  next_check_what            STRING,
  state_reason               STRING,
  family_bar                 FLOAT64,
  bar_exempt                 BOOL,
  nf_orders                  INT64,
  se_eff                     FLOAT64,
  gp_per_click               FLOAT64,
  affordable_cpc             FLOAT64,
  ord_bar_expected           FLOAT64,
  click_collapse             BOOL,
  guard_prior_clk            INT64,
  guard_ns_share             FLOAT64,
  guard_bar_material         FLOAT64,
  guard_deferred             BOOL,
  guard_flip                 BOOL,
  clean_clk90                INT64,
  clean_ord90                INT64,
  clean_roas90               FLOAT64,
  clean_cpc90                FLOAT64,
  clean_affordable_cpc       FLOAT64,
  ns_zero_ord_terms          INT64,
  ns_zero_ord_clicks         INT64,
  ad_group_id                STRING,
  creative_type              STRING,
  bid_floor                  FLOAT64,
  bid_floor_source           STRING,
  m_effective                FLOAT64,
  is_brand_defense           BOOL,
  affordable_bid             FLOAT64,
  clean_affordable_bid       FLOAT64,
  at_floor                   BOOL,
  guard_scope                STRING,
  raw_state                  STRING,
  clean_state                STRING,
  settle_days_eff            INT64,
  floor_since                DATE,
  probation_clock_start      DATE,
  probation_clk_settled      INT64,
  probation_elapsed          BOOL,
  probation_due_date         DATE,
  probation_bid              FLOAT64,
  nf_collapse_forecast_date  DATE,
  prior_state                STRING
)
PARTITION BY snapshot_date
CLUSTER BY keyword_id, campaign_id, state, family
OPTIONS (description = "The Catalog's memory (THREE_LAYERS.md §8 violation 6, closed 2026-08-24). Append-only history of FACT_KEYWORD_STATE, which is CREATE OR REPLACE'd nightly and holds exactly one snapshot — so before this table existed no caller could ask the ladder what it said on any day but today, and §6's Catalog scorecard ('was the valuation right?') was impossible to compute. One row per (snapshot_date, campaign_id, keyword_id): the WHOLE snapshot row — verdict, the settled record it was read off, the family bar, the noise band, the affordable price, the floor, the mix-drift guard's cleaned re-reading and the promised appointment — because a verdict without its evidence cannot be graded, only counted. THREE CLOCKS, and they answer different questions: snapshot_date is the day the Catalog was speaking about, captured_at is when the row was written here, and snapshot_built_at is when the BUILD it was copied from was made (NULL before v27.145, which is the honest reading — those rows did not record it). Provenance is completed by source (ORCHESTRATOR | BACKFILL_TIME_TRAVEL) and source_detail naming exactly what was read. Written by SP_APPEND_KEYWORD_STATE_HISTORY (orchestrator Task 20.8a), which INSERTs the whole snapshot stamped with the run's captured_at and then PRUNEs any snapshot_date carrying more than one captured_at down to its newest stamp — append-first, so a crash between the two statements can only leave a duplicate, never a lost day, and two passes on one snapshot_date leave exactly one copy. THE WRITER CAN AND DOES REACH AN EARLIER PARTITION, deliberately: the prune is keyed on the history's OWN duplicate stamps rather than on the date the live snapshot happens to carry, and it runs before the append as well as after, so a strand left on any date is repaired by any later call including a manual one. What it may NOT do is restamp a build the history has already recorded — a pass whose Task 20.8 failed still reaches this step with the previous build standing, and re-copying it would move captured_at while the build behind it stood still, making the provenance claim a read time at which the Catalog said nothing. The writer refuses that copy by comparing the snapshot table's own last-modified clock against the stamp the history already holds for that date, which is a test of the BUILD and not of the calendar, so it holds for repeat passes inside one LA day as well as across days. The writer reads the live column list from INFORMATION_SCHEMA and ADD COLUMN IF NOT EXISTS-es what it lacks, so the columns §2.7 (confidence), §2.8 (market volume) and §4 (seasonality) will add appear here the day they exist, with older partitions honestly NULL rather than backfilled. NO ENGINE, GENERATOR OR BOOK READS THIS TABLE — it records what was already recorded and can move no bid, budget or pause. Read by V_CATALOG_DWELL. Acceptance: scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql. Spec: architecture/THREE_LAYERS.md §1.4/§6/§8/§10.4. SOP: architecture/KEYWORD_STATE.md.");
