-- =============================================================================================
-- FACT_KEYWORD_STATE_HISTORY — the Catalog's memory. v27.143 (2026-08-24).
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
-- bounded in time and because the write step replaces exactly one date's partition. Clustered by
-- keyword_id first: the doctrinal question §1.4 demands a caller be able to ask is "what did you
-- say about THIS SUBJECT on that date", and the subject is scoped by its keyword id (§2.2 — bare
-- target text is never a valid subject). campaign_id completes the grain, state and family carry
-- the population reads.
--
-- PROVENANCE. Every row says when it was written and where it came from, so a recovered row is
-- never mistaken for one the pipeline appended live:
--   captured_at    the moment the row was written into the history (NOT the moment the Catalog
--                  computed it — that is snapshot_date).
--   source         'ORCHESTRATOR' for a row appended by the nightly pass; 'BACKFILL_TIME_TRAVEL'
--                  for a row recovered from BigQuery's own 7-day table history.
--   source_detail  free text naming exactly what was read — for a backfill, the time-travel
--                  timestamp, which is the whole audit trail for that row.
--
-- Written by: SP_APPEND_KEYWORD_STATE_HISTORY (orchestrator Task 20.8a, immediately after 20.8).
-- Read by:    V_CATALOG_DWELL, and any caller asking the Catalog a historical question.
-- Acceptance: scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql
-- Spec:       architecture/THREE_LAYERS.md §1.4, §6, §6.2, §8 (violation 6), §10.4.
-- SOP:        architecture/KEYWORD_STATE.md §"The history".
--
-- CREATE TABLE IF NOT EXISTS — re-running this file can never drop a kept snapshot. There is no
-- CREATE OR REPLACE anywhere in this object's lifecycle, and that is the entire point of it.
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
(
  snapshot_date              DATE    NOT NULL,
  captured_at                TIMESTAMP NOT NULL,
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
OPTIONS (description = "The Catalog's memory (THREE_LAYERS.md §8 violation 6, closed 2026-08-24). Append-only history of FACT_KEYWORD_STATE, which is CREATE OR REPLACE'd nightly and holds exactly one snapshot — so before this table existed no caller could ask the ladder what it said on any day but today, and §6's Catalog scorecard ('was the valuation right?') was impossible to compute. One row per (snapshot_date, campaign_id, keyword_id): the WHOLE snapshot row — verdict, the settled record it was read off, the family bar, the noise band, the affordable price, the floor, the mix-drift guard's cleaned re-reading and the promised appointment — because a verdict without its evidence cannot be graded, only counted. Provenance on every row: captured_at (when it was written here, not when the Catalog computed it), source ORCHESTRATOR | BACKFILL_TIME_TRAVEL, and source_detail naming exactly what was read. Written by SP_APPEND_KEYWORD_STATE_HISTORY (orchestrator Task 20.8a) which replaces exactly the snapshot's own date partition, so a pass that runs twice leaves one copy and no earlier partition is ever touched; the writer reads the live column list from INFORMATION_SCHEMA and ADD COLUMN IF NOT EXISTS-es what it lacks, so the columns §2.7 (confidence), §2.8 (market volume) and §4 (seasonality) will add appear here the day they exist, with older partitions honestly NULL rather than backfilled. NO ENGINE, GENERATOR OR BOOK READS THIS TABLE — it records what was already recorded and can move no bid, budget or pause. Read by V_CATALOG_DWELL. Acceptance: scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql. Spec: architecture/THREE_LAYERS.md §1.4/§6/§8/§10.4. SOP: architecture/KEYWORD_STATE.md.");
