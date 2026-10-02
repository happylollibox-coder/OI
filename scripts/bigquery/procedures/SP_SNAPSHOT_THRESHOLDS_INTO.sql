-- =============================================================================================
-- SP_SNAPSHOT_THRESHOLDS_INTO(coach_table, plan_table, history_table) — v27.155 (2026-10-01).
-- The logic of the rule-table history (FACT_THRESHOLD_HISTORY): compare every row of the coach
-- thresholds and of the plan config with its key's LAST event in the history and append, in ONE
-- INSERT, a row for each key that is new (SEEDED / ADDED), changed (CHANGED) or gone (REMOVED).
-- Keys, compared values and kinds are defined in scripts/bigquery/tables/FACT_THRESHOLD_HISTORY.sql.
--
-- WHY IT TAKES TABLE NAMES. The nightly caller is SP_SNAPSHOT_THRESHOLDS(), which passes the three
-- live tables. The acceptance (THRESHOLD_HISTORY_acceptance.sql) passes TMP_ copies, so the code
-- that runs at night is the code the acceptance runs — on a changed value, a retire-then-insert, a
-- removed row — without touching a live table. Names are checked before anything runs: each must
-- be its live table or a TMP_ table in onyga-482313.OI, and nothing else is spliced into the SQL.
--
-- IDEMPOTENT: a second call with no change in between writes nothing (acceptance C02). One
-- snapshot_at per call (CURRENT_TIMESTAMP is fixed within the INSERT statement).
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`(
  coach_table STRING, plan_table STRING, history_table STRING)
OPTIONS (description = "v27.155 (2026-10-01): the logic of FACT_THRESHOLD_HISTORY. Compares every row of coach_table (DE_COACH_THRESHOLDS shape) and plan_table (DE_PLAN_CONFIG shape) with its key's last event in history_table and appends, in one INSERT with one snapshot_at, SEEDED (first snapshot of a source), ADDED (new key or back after REMOVED), CHANGED (compared values differ) or REMOVED (gone; values NULL) rows; writes nothing when nothing differs. Each name must be the live table (onyga-482313.OI.DE_COACH_THRESHOLDS / DE_PLAN_CONFIG / FACT_THRESHOLD_HISTORY) or a TMP_ table in onyga-482313.OI, checked before anything runs, so the acceptance runs the nightly code on TMP_ copies. Called nightly by SP_SNAPSHOT_THRESHOLDS with the live names.")
BEGIN
  DECLARE stmt STRING;

  IF NOT (REGEXP_CONTAINS(COALESCE(coach_table, ''),   r'^onyga-482313\.OI\.(DE_COACH_THRESHOLDS|TMP_[A-Za-z0-9_]+)$')
          AND REGEXP_CONTAINS(COALESCE(plan_table, ''),    r'^onyga-482313\.OI\.(DE_PLAN_CONFIG|TMP_[A-Za-z0-9_]+)$')
          AND REGEXP_CONTAINS(COALESCE(history_table, ''), r'^onyga-482313\.OI\.(FACT_THRESHOLD_HISTORY|TMP_[A-Za-z0-9_]+)$')) THEN
    RAISE USING MESSAGE = FORMAT(
      'SP_SNAPSHOT_THRESHOLDS_INTO: each table must be its live table or a TMP_ table in onyga-482313.OI; got coach=%s plan=%s history=%s',
      IFNULL(coach_table, 'NULL'), IFNULL(plan_table, 'NULL'), IFNULL(history_table, 'NULL'));
  END IF;

  SET stmt = REPLACE(REPLACE(REPLACE("""
INSERT INTO `{HIST}`
  (history_id, snapshot_at, source_table, row_key, key_ordinal, change_kind, row_fingerprint,
   threshold_key, strategy_id, coach_mode, product_family,
   threshold_value, peak_multiplier, boost_peak_multiplier, suggested_value,
   suggested_at, suggestion_reason, threshold_source,
   calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders,
   strong_day_mult, strong_day_min_orders, is_active, change_reason,
   description, source_updated_at, source_updated_by)
WITH coach AS (
  SELECT 'DE_COACH_THRESHOLDS' AS source_table,
         TO_JSON_STRING(STRUCT(threshold_key, strategy_id, coach_mode, product_family)) AS row_key,
         TO_HEX(MD5(TO_JSON_STRING(STRUCT(threshold_value, peak_multiplier, boost_peak_multiplier,
                                          suggested_value)))) AS row_fingerprint,
         threshold_key, strategy_id, coach_mode, product_family,
         threshold_value, peak_multiplier, boost_peak_multiplier, suggested_value,
         suggested_at, suggestion_reason, source AS threshold_source,
         CAST(NULL AS STRING) AS calendar_state, CAST(NULL AS INT64) AS window_days,
         CAST(NULL AS FLOAT64) AS allowance_share, CAST(NULL AS STRING) AS live_plan,
         CAST(NULL AS INT64) AS ramp_steps, CAST(NULL AS INT64) AS min_orders,
         CAST(NULL AS FLOAT64) AS strong_day_mult, CAST(NULL AS INT64) AS strong_day_min_orders,
         CAST(NULL AS BOOL) AS is_active, CAST(NULL AS STRING) AS change_reason,
         description,
         TIMESTAMP(updated_at) AS source_updated_at,   -- a DATETIME written in UTC
         updated_by AS source_updated_by
  FROM `{COACH}`
),
plan AS (
  SELECT 'DE_PLAN_CONFIG' AS source_table,
         TO_JSON_STRING(STRUCT(calendar_state, updated_by, updated_at)) AS row_key,
         TO_HEX(MD5(TO_JSON_STRING(STRUCT(window_days, allowance_share, live_plan, ramp_steps,
                                          min_orders, strong_day_mult, strong_day_min_orders,
                                          is_active)))) AS row_fingerprint,
         CAST(NULL AS STRING) AS threshold_key, CAST(NULL AS STRING) AS strategy_id,
         CAST(NULL AS STRING) AS coach_mode, CAST(NULL AS STRING) AS product_family,
         CAST(NULL AS FLOAT64) AS threshold_value, CAST(NULL AS FLOAT64) AS peak_multiplier,
         CAST(NULL AS FLOAT64) AS boost_peak_multiplier, CAST(NULL AS FLOAT64) AS suggested_value,
         CAST(NULL AS DATETIME) AS suggested_at, CAST(NULL AS STRING) AS suggestion_reason,
         CAST(NULL AS STRING) AS threshold_source,
         calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders,
         strong_day_mult, strong_day_min_orders, is_active, change_reason,
         description,
         updated_at AS source_updated_at,
         updated_by AS source_updated_by
  FROM `{PLAN}`
),
cur AS (
  SELECT u.*,
         ROW_NUMBER() OVER (PARTITION BY u.source_table, u.row_key ORDER BY u.row_fingerprint) AS key_ordinal
  FROM (SELECT * FROM coach UNION ALL SELECT * FROM plan) u
),
last_event AS (
  SELECT source_table, row_key, key_ordinal, change_kind, row_fingerprint,
         threshold_key, strategy_id, coach_mode, product_family, calendar_state
  FROM `{HIST}`
  WHERE source_table IN ('DE_COACH_THRESHOLDS', 'DE_PLAN_CONFIG')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY source_table, row_key, key_ordinal
                             ORDER BY snapshot_at DESC, history_id DESC) = 1
),
seen AS (
  SELECT DISTINCT source_table FROM `{HIST}`
),
upserts AS (
  SELECT c.*,
         CASE
           WHEN l.row_key IS NULL AND s.source_table IS NULL THEN 'SEEDED'
           WHEN l.row_key IS NULL OR l.change_kind = 'REMOVED' THEN 'ADDED'
           ELSE 'CHANGED'
         END AS change_kind
  FROM cur c
  LEFT JOIN last_event l
    ON l.source_table = c.source_table AND l.row_key = c.row_key AND l.key_ordinal = c.key_ordinal
  LEFT JOIN seen s
    ON s.source_table = c.source_table
  WHERE l.row_key IS NULL
     OR l.change_kind = 'REMOVED'
     OR l.row_fingerprint IS DISTINCT FROM c.row_fingerprint
),
removals AS (
  SELECT l.*
  FROM last_event l
  LEFT JOIN cur c
    ON c.source_table = l.source_table AND c.row_key = l.row_key AND c.key_ordinal = l.key_ordinal
  WHERE c.row_key IS NULL
    AND l.change_kind != 'REMOVED'
)
SELECT GENERATE_UUID(), CURRENT_TIMESTAMP(), source_table, row_key, key_ordinal, change_kind,
       row_fingerprint,
       threshold_key, strategy_id, coach_mode, product_family,
       threshold_value, peak_multiplier, boost_peak_multiplier, suggested_value,
       suggested_at, suggestion_reason, threshold_source,
       calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders,
       strong_day_mult, strong_day_min_orders, is_active, change_reason,
       description, source_updated_at, source_updated_by
FROM upserts
UNION ALL
SELECT GENERATE_UUID(), CURRENT_TIMESTAMP(), source_table, row_key, key_ordinal, 'REMOVED',
       CAST(NULL AS STRING),
       threshold_key, strategy_id, coach_mode, product_family,
       NULL, NULL, NULL, NULL,
       NULL, NULL, NULL,
       calendar_state, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL,
       NULL, NULL, NULL
FROM removals
""", '{COACH}', coach_table), '{PLAN}', plan_table), '{HIST}', history_table);

  EXECUTE IMMEDIATE stmt;
END;
