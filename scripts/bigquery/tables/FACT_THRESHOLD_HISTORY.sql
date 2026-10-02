-- =============================================================================================
-- FACT_THRESHOLD_HISTORY — v27.155 (2026-10-01): every value a rule table has held, with when it
-- was seen and who last wrote it. Learning-contract piece 0, Task D.
--
-- WHY IT EXISTS. Ori, 2026-10-01: "make sure the system is a learning system and it saves the
-- relevant data." A learning system changes its rules from graded evidence, and a rule change can
-- only be graded later if the record says which value was in force on which day. Neither rule
-- table could say that on its own:
--   * DE_COACH_THRESHOLDS holds only the current value. Its DDL re-seed is a wipe (DELETE WHERE
--     TRUE), there is no is_active column, and the one standing record of a threshold moving is
--     T_INTENT_REFIT_LOG, for one key (INTENT_CVR_CALIBRATION).
--   * DE_PLAN_CONFIG keeps superseded rows (retire-then-insert, is_active = FALSE), but a
--     retirement does not move updated_at and an UPDATE in place leaves no trace at all.
--
-- WHAT A ROW IS. One row per source row per change. SP_SNAPSHOT_THRESHOLDS (orchestrator Refresh
-- Task 10.1, right after SP_DATA_ENTRY_UPDATES, three passes a day) compares every row of both
-- tables with that row's LAST event here and appends only what differs:
--   SEEDED   the first snapshot of a source table: the value was in force at snapshot_at and for
--            an unknown time before it (source_updated_at is the best date there is for it)
--   ADDED    a key that was not here, or whose last event was REMOVED
--   CHANGED  a key whose values differ from its last event
--   REMOVED  a key whose last event was not REMOVED and which the source no longer holds; the
--            value columns are NULL and the key columns are copied from the last event
-- A pass that finds nothing different writes nothing, so the table grows by changes, not by
-- days. The CURRENT state of a key is its latest event; its state on day D is its latest event
-- with snapshot_at <= D.
--
-- THE KEY (row_key, key_ordinal):
--   DE_COACH_THRESHOLDS  TO_JSON_STRING(STRUCT(threshold_key, strategy_id, coach_mode,
--                        product_family)) — the resolution key of V_ADS_COACH.
--   DE_PLAN_CONFIG       TO_JSON_STRING(STRUCT(calendar_state, updated_by, updated_at)) — one key
--                        per row ever written: the seed rows keep their sentinel updated_at and
--                        a retire-then-insert writes a new row with its own clock, so the retired
--                        row is a CHANGED event (is_active TRUE -> FALSE) on its own key and the
--                        new row is ADDED on a new one.
--   key_ordinal is 1 unless the source holds two rows with the same key; then they are numbered
--   by row_fingerprint, so a duplicate is recorded rather than lost or allowed to make a second
--   pass write again.
--
-- WHAT COUNTS AS A CHANGE (row_fingerprint = MD5 hex of these, as TO_JSON_STRING):
--   DE_COACH_THRESHOLDS  threshold_value, peak_multiplier, boost_peak_multiplier, suggested_value
--                        (a proposal is part of the learning record; suggested_at and
--                        suggestion_reason are carried, not compared, so a re-worded reason or a
--                        re-stamped date alone writes nothing)
--   DE_PLAN_CONFIG       window_days, allowance_share, live_plan, ramp_steps, min_orders,
--                        strong_day_mult, strong_day_min_orders, is_active
-- description, change_reason, source and the source's updated_at / updated_by are carried on
-- every row as context for the change; a change to them alone writes nothing.
--
-- LIMITS, STATED. The history is the state SEEN AT EACH PASS: a value that lived between two
-- passes is not recorded, and snapshot_at is when the pass saw a change, not when it was made
-- (source_updated_at says that where the writer stamps it; SP_SCORE_INTENT_INDEXES runs after this
-- step in the same pass, so its refit is seen on the next one, and T_INTENT_REFIT_LOG keeps its
-- own record of every refit). DE_COACH_THRESHOLDS.updated_at is a DATETIME written in UTC and is
-- read here as a UTC TIMESTAMP.
--
-- ACCUMULATES. CREATE TABLE IF NOT EXISTS, never replaced, never updated, never deleted from.
-- Written by:  SP_SNAPSHOT_THRESHOLDS -> SP_SNAPSHOT_THRESHOLDS_INTO (the logic, which takes the
--              three table names so the acceptance runs it on TMP_ copies)
-- Read by:     acceptance THRESHOLD_HISTORY_acceptance.sql; the learning contract's apply step
--              (docs/superpowers/specs/2026-10-01-learning-contract-design.md §8) will cite
--              history_id; people
-- SOP:         architecture/NEXT_WEEK_MONEY.md §1 "The settings, and who may change them"
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_THRESHOLD_HISTORY` (
  history_id             STRING    NOT NULL,  -- GENERATE_UUID(), one per row
  snapshot_at            TIMESTAMP NOT NULL,  -- when the pass saw this state (UTC); one value per pass
  source_table           STRING    NOT NULL,  -- 'DE_COACH_THRESHOLDS' | 'DE_PLAN_CONFIG'
  row_key                STRING    NOT NULL,  -- see THE KEY above
  key_ordinal            INT64     NOT NULL,  -- 1 unless the source duplicates a key
  change_kind            STRING    NOT NULL,  -- SEEDED | ADDED | CHANGED | REMOVED
  row_fingerprint        STRING,              -- MD5 hex of the compared values; NULL on REMOVED
  -- DE_COACH_THRESHOLDS: the key
  threshold_key          STRING,
  strategy_id            STRING,
  coach_mode             STRING,
  product_family         STRING,
  -- DE_COACH_THRESHOLDS: the compared values
  threshold_value        FLOAT64,
  peak_multiplier        FLOAT64,
  boost_peak_multiplier  FLOAT64,
  suggested_value        FLOAT64,
  -- DE_COACH_THRESHOLDS: context
  suggested_at           DATETIME,
  suggestion_reason      STRING,
  threshold_source       STRING,              -- DE_COACH_THRESHOLDS.source (MANUAL, SEED, AUTO_REFIT, ...)
  -- DE_PLAN_CONFIG: the key (with updated_by / updated_at, carried below)
  calendar_state         STRING,
  -- DE_PLAN_CONFIG: the compared values
  window_days            INT64,
  allowance_share        FLOAT64,
  live_plan              STRING,
  ramp_steps             INT64,
  min_orders             INT64,
  strong_day_mult        FLOAT64,
  strong_day_min_orders  INT64,
  is_active              BOOL,
  -- DE_PLAN_CONFIG: context
  change_reason          STRING,
  -- both: context
  description            STRING,
  source_updated_at      TIMESTAMP,           -- the source row's updated_at (UTC)
  source_updated_by      STRING               -- the source row's updated_by
)
CLUSTER BY source_table, row_key
OPTIONS (description = "v27.155 (2026-10-01), learning-contract piece 0 Task D: append-on-change history of the rule tables DE_COACH_THRESHOLDS and DE_PLAN_CONFIG. One row per source row per change, written by SP_SNAPSHOT_THRESHOLDS (orchestrator Refresh Task 10.1, after SP_DATA_ENTRY_UPDATES): SEEDED on the first snapshot of a source, ADDED (new key, or back after REMOVED), CHANGED (the compared values differ from the key's last event), REMOVED (gone from the source; values NULL). Compared values: threshold_value, peak_multiplier, boost_peak_multiplier, suggested_value for DE_COACH_THRESHOLDS (key threshold_key x strategy_id x coach_mode x product_family); window_days, allowance_share, live_plan, ramp_steps, min_orders, strong_day_mult, strong_day_min_orders, is_active for DE_PLAN_CONFIG (key calendar_state x updated_by x updated_at, so a retirement is a CHANGED event and the replacement row an ADDED one). description, change_reason, suggestion_reason, source and the source's updated_at / updated_by are carried as context. A pass that finds nothing different writes nothing. The value in force on day D is the key's latest event with snapshot_at <= D; a value that lived between two passes is not recorded, and snapshot_at is when a pass saw the change (source_updated_at is when the writer stamped it). Never updated, never deleted from.");
