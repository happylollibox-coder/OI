-- =============================================
-- SP_RECORD_OBSERVED_CHANGES — every real change on Amazon gets a row, whether or not it came
-- from a bulksheet. (2026-10-01, learning-system Task B: decision -> ACTION -> outcome -> grade.)
-- SOP: architecture/PPC_CLOSE_THE_LOOP.md §Observed changes.
-- =============================================
--
-- WHY. FACT_PPC_CHANGE_LOG records what OI's own tooling put through: the DO page's "Uploaded to
-- Amazon" (source COACH / MANUAL) and the hand-built books (BRAIN:* / CATALOG:* / PACING:*, status
-- PENDING_UPLOAD until confirmed). Applied rows stop in late August 2026 (Q1); the last book,
-- of 2026-08-25, was never confirmed and none of its rows landed on Amazon (Q2). The changes made
-- since were made by hand in the console, and the only record of them is Fivetran's SCD2 trail on
-- DIM_KEYWORD / DIM_CAMPAIGN / DIM_AD_GROUP (Q3 counts them by action). A scorecard that only sees
-- the log grades proposals that were never applied and misses the changes that were.
-- This procedure writes one FACT_PPC_CHANGE_LOG row per attribute change in that trail. WHAT
-- counts as a change (and why a new entity's first version never does) is defined once, in
-- V_AMAZON_OBSERVED_CHANGES; this procedure only decides what is new, what it confirms, and writes.
--
-- STORAGE: INTO FACT_PPC_CHANGE_LOG, as the action record's own rows — not a second table.
-- The rows are labelled on every axis so no reader can mistake them:
--   source        = 'OBSERVED'               (the Flask writer emits only COACH / MANUAL, the books
--                                             their BRAIN:* / CATALOG:* / PACING:* tags)
--   upload_status = 'OBSERVED_ON_AMAZON'     (beside NULL / FAILED_UPLOAD / SUPERSEDED_NEVER_UPLOADED /
--                                             PENDING_UPLOAD; the column description lists all five)
--   coach_mode    = NULL                     (no coach decided this)
--   batch_id      = 'observed_<LA run date>'
--   change_id     = V_AMAZON_OBSERVED_CHANGES.change_id, 'obs|<DIM>|<id>|<attribute>|<effective_from>',
--                   deterministic — a re-run finds its own rows (NOT EXISTS) and inserts nothing twice.
--   applied_at    = TIMESTAMP(effective_from, 'UTC'): the instant of the new version. effective_from
--                   holds the UTC wall clock (measured, see the view), so this is the real moment,
--                   and every reader derives the Los Angeles day with DATE(applied_at,
--                   'America/Los_Angeles') exactly as for every other row. Converting to LA here as
--                   well would shift every window by seven or eight hours.
--   old_bid / new_bid, old_budget / new_budget from the two versions; a state change carries
--   neither, its old and new state are in upload_note. No column was added to the table: every
--   writer names its columns, but SELECT * readers (V_PPC_CHANGE_LOG_APPLIED and the Flask debug
--   endpoint) would change shape, and the before/after proof (the run log of
--   scripts/bigquery/tests/OBSERVED_CHANGES_acceptance.sql) rests on APPLIED being byte-identical.
-- WHY NOT A SECOND TABLE: with the rows in the log, the action record is one table — every action,
-- logged or observed, under one change_id key, one watermark, one partition scheme. Every reader
-- of the log was checked (scripts/bigquery views and procedures in INFORMATION_SCHEMA, tools/,
-- data-entry-app, cube, dashboard): the raw-table readers filter on batch-id prefixes or on
-- PENDING_UPLOAD / NULL status and never see these rows, except the Flask debug endpoint
-- GET /api/ppc-change-log, which lists every row and now lists these too; every other reader goes through
-- V_PPC_CHANGE_LOG_APPLIED, which now EXCLUDES 'OBSERVED_ON_AMAZON' explicitly, so all of them read
-- exactly the rows they read before (proved by fingerprint and per-consumer counts, see
-- scripts/bigquery/tests/OBSERVED_CHANGES_acceptance.sql). The grader reads them through
-- V_PPC_CHANGE_LOG_LANDED. Letting hand changes into APPLIED would move the engines — a hand cut to
-- the floor would start SP_SNAPSHOT_KEYWORD_STATE's probation clock (it starts on an applied bid at
-- the floor), a hand change would count as the keyword's last change for the coach's cooldown — and
-- that is a separate decision for Ori, not a side effect of recording.
--
-- RECONCILIATION, NOT DUPLICATION. A change OI uploaded appears twice: the log row, and the DIM
-- version that shows it landed. The observed row is still written — the landing is a fact in its
-- own right, and the log row may never be updated (house rule) — but its upload_note starts
-- 'CONFIRMS <change_id>' naming the log row, and V_PPC_CHANGE_LOG_LANDED reads that name back so
-- the grader counts the pair once. A match is:
--   bid           same keyword_id, a log row carrying new_bid within $0.005 of the observed one
--   budget        same campaign_id, a *BUDGET* log row carrying new_budget within $0.01
--   keyword state same keyword_id; observed KEYWORD_PAUSE <- logged KEYWORD_PAUSE / STOP_TARGET,
--                 observed KEYWORD_ENABLE <- logged KEYWORD_UNPAUSE_PARK / KEYWORD_ENABLE
--   campaign state same campaign_id and the same action name
-- and the observed instant within [log applied_at - 1 day, log applied_at + 3 days]. The day
-- BEFORE is not a typo: Ori uploads the sheet first and marks it uploaded after, so Amazon's
-- last_updated_date usually PRECEDES the log stamp, most often by under an hour (Q4 buckets every
-- applied log bid row by where its nearest matching DIM version landed). A window opening at the
-- stamp would miss every landing in the hour before it, and the grader would count each of those
-- changes twice.
-- Only log rows with upload_status NULL or PENDING_UPLOAD can be confirmed; NULL first, then the
-- nearest in time. Each log row confirms at most one observed row PER ATTRIBUTE (a logged unpause
-- at a park bid lands as a state version and a bid version; both are its landing) and each
-- observed row confirms at most one log row. A FAILED_UPLOAD or SUPERSEDED_NEVER_UPLOADED row was
-- declared dead and is never confirmed: if Amazon shows the same value landing anyway, the
-- observed row is written UNLOGGED and its note names the dead row, because that mislabel is
-- precisely what this record exists to surface.
--
-- WATERMARK AND RE-RUNS. The watermark is MAX(applied_at) over source = 'OBSERVED' rows; with none,
-- the run backfills the whole ledger scope (effective_from after 2026-08-20, the view's
-- in_ledger_scope). The scan opens 7 days BEFORE the watermark: a version's clock is Amazon's
-- last_updated_date but OI sees it only at the next Fivetran sync, hours later (Q5), so a scan
-- opening exactly at the watermark would lose a late version forever. Seven days is a declared
-- margin, far wider than that lag. Idempotence rests on the deterministic change_id, never on the
-- window.
-- GUARD: the run refuses (ASSERT, the step logs FAIL) if V_PPC_CHANGE_LOG_APPLIED shows any
-- OBSERVED row, i.e. if the view was redeployed without its exclusion; writing more rows into a
-- view every engine reads would compound the leak.
--
-- SCHEDULE: Refresh Task 2.2a of SP_ORCHESTRATE_DAILY_REFRESH, right after the three DIM loads.
-- Returns one summary row, then the inserted rows counted by action and LA week (Sunday start).
--
-- QUERIES BEHIND THE DESIGN (run them; this header states no measured number):
-- Q1 when applied log rows stop:
--   SELECT source, MAX(DATE(applied_at, 'America/Los_Angeles')) FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
--   WHERE source != 'OBSERVED' GROUP BY 1;
-- Q2 the 2026-08-25 book against the trail (logged rows that landed, by action):
--   SELECT l.action, COUNT(*) logged, COUNTIF(o.change_id IS NOT NULL) landed
--   FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` l
--   LEFT JOIN `onyga-482313.OI.FACT_PPC_CHANGE_LOG` o
--     ON o.source = 'OBSERVED' AND STARTS_WITH(o.upload_note, CONCAT('CONFIRMS ', l.change_id, ' '))
--   WHERE l.upload_status = 'PENDING_UPLOAD' GROUP BY 1;
-- Q3 the trail since 2026-08-20, by action:
--   SELECT action, COUNT(*) n, COUNT(DISTINCT entity_id) entities
--   FROM `onyga-482313.OI.V_AMAZON_OBSERVED_CHANGES` WHERE in_ledger_scope GROUP BY 1;
-- Q4 where a logged bid lands relative to its log stamp (minutes, nearest matching version):
--   WITH m AS (
--     SELECT l.change_id, TIMESTAMP_DIFF(v.applied_at, l.applied_at, MINUTE) AS off_min
--     FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` l
--     JOIN `onyga-482313.OI.V_AMAZON_OBSERVED_CHANGES` v
--       ON v.attr = 'bid' AND v.keyword_id = l.keyword_id AND ABS(v.new_bid - l.new_bid) <= 0.005
--     WHERE l.source = 'COACH' AND l.action IN ('INCREASE_BID', 'REDUCE_BID') AND l.new_bid IS NOT NULL
--     QUALIFY ROW_NUMBER() OVER (PARTITION BY l.change_id ORDER BY ABS(TIMESTAMP_DIFF(v.applied_at, l.applied_at, SECOND))) = 1)
--   SELECT CASE WHEN off_min < -1440 THEN 'a: over a day before' WHEN off_min < -60 THEN 'b: day before'
--               WHEN off_min <= 0 THEN 'c: hour before' WHEN off_min <= 1440 THEN 'd: day after'
--               WHEN off_min <= 4320 THEN 'e: days 2-3 after' ELSE 'f: later' END bucket, COUNT(*)
--   FROM m GROUP BY 1 ORDER BY 1;
-- Q5 how late a DIM_KEYWORD version arrives after its own effective_from (hours):
--   SELECT MAX(TIMESTAMP_DIFF(_fivetran_synced, TIMESTAMP(effective_from), SECOND)) / 3600
--   FROM `onyga-482313.OI.DIM_KEYWORD` WHERE effective_from > '2026-08-20';
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_RECORD_OBSERVED_CHANGES`()
OPTIONS (
  description = "Writes one FACT_PPC_CHANGE_LOG row (source OBSERVED, upload_status OBSERVED_ON_AMAZON, deterministic change_id) per change in V_AMAZON_OBSERVED_CHANGES (the DIM_KEYWORD / DIM_CAMPAIGN / DIM_AD_GROUP SCD2 trail: bid, state, budget, default bid; a new entity's first version is never a change). Reconciles against logged rows (upload_note 'CONFIRMS <change_id>') instead of duplicating them. Idempotent; watermark = MAX(applied_at) of OBSERVED rows, scan opens 7 days before it, ledger starts 2026-08-20."
)
BEGIN
  DECLARE start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE run_date DATE DEFAULT CURRENT_DATE('America/Los_Angeles');
  DECLARE watermark TIMESTAMP;
  DECLARE scan_from TIMESTAMP;
  DECLARE n_candidates INT64 DEFAULT 0;
  DECLARE n_inserted INT64 DEFAULT 0;

  ASSERT NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` WHERE source = 'OBSERVED')
    AS 'V_PPC_CHANGE_LOG_APPLIED shows OBSERVED rows: it was redeployed without the OBSERVED_ON_AMAZON exclusion, so every engine now reads hand changes as applied changes. Restore the exclusion before recording more.';

  SET watermark = (SELECT MAX(applied_at) FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE source = 'OBSERVED');
  SET scan_from = TIMESTAMP_SUB(watermark, INTERVAL 7 DAY);   -- NULL on the first run = the whole scope

  -- ── 1. the candidates: ledger-scope changes from the scan start on ───────────────────────────
  CREATE TEMP TABLE _obs_raw AS
  SELECT *
  FROM `onyga-482313.OI.V_AMAZON_OBSERVED_CHANGES`
  WHERE in_ledger_scope
    AND (scan_from IS NULL OR applied_at > scan_from);

  SET n_candidates = (SELECT COUNT(*) FROM _obs_raw);

  -- ── 2. reconcile against the log: which logged row does each observation confirm? ─────────────
  CREATE TEMP TABLE _obs_new AS
  WITH
  logged AS (
    SELECT change_id, applied_at, action, keyword_id, campaign_id, new_bid, new_budget, upload_status
    FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
    WHERE source != 'OBSERVED'
      -- an observation at t matches a log row stamped in [t - 3 days, t + 1 day]
      AND applied_at >= TIMESTAMP_SUB((SELECT MIN(applied_at) FROM _obs_raw), INTERVAL 3 DAY)
  ),
  -- the match predicate, written once and joined twice (live rows, dead rows)
  pairs AS (
    SELECT o.change_id AS obs_id, o.attr, o.applied_at AS obs_at,
           l.change_id AS log_id, l.upload_status AS log_status, l.applied_at AS log_at
    FROM _obs_raw o
    JOIN logged l
      ON o.applied_at BETWEEN TIMESTAMP_SUB(l.applied_at, INTERVAL 1 DAY) AND TIMESTAMP_ADD(l.applied_at, INTERVAL 3 DAY)
     AND (
          (o.entity = 'DIM_KEYWORD' AND o.attr = 'bid' AND l.keyword_id = o.keyword_id
             AND l.new_bid IS NOT NULL AND ABS(l.new_bid - o.new_bid) <= 0.005)
       OR (o.entity = 'DIM_CAMPAIGN' AND o.attr = 'daily_budget' AND l.campaign_id = o.campaign_id
             AND l.action LIKE '%BUDGET%'
             AND l.new_budget IS NOT NULL AND ABS(l.new_budget - o.new_budget) <= 0.01)
       OR (o.entity = 'DIM_KEYWORD' AND o.attr = 'state' AND l.keyword_id = o.keyword_id
             AND ((o.action = 'KEYWORD_PAUSE'  AND l.action IN ('KEYWORD_PAUSE', 'STOP_TARGET'))
               OR (o.action = 'KEYWORD_ENABLE' AND l.action IN ('KEYWORD_UNPAUSE_PARK', 'KEYWORD_ENABLE'))))
       OR (o.entity = 'DIM_CAMPAIGN' AND o.attr = 'state' AND l.campaign_id = o.campaign_id
             AND l.action = o.action)
     )
  ),
  live_pick AS (
    -- one log row per observation: applied (NULL) before PENDING_UPLOAD, then the nearest stamp
    SELECT * FROM pairs
    WHERE log_status IS NULL OR log_status = 'PENDING_UPLOAD'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY obs_id
                               ORDER BY IF(log_status IS NULL, 0, 1),
                                        ABS(TIMESTAMP_DIFF(obs_at, log_at, SECOND)), log_id) = 1
  ),
  live_1to1 AS (
    -- ...and one observation per log row and attribute: a bid that went A->B->A->B inside the
    -- window must not confirm the same log row twice; the nearest observation keeps it
    SELECT * FROM live_pick
    QUALIFY ROW_NUMBER() OVER (PARTITION BY log_id, attr
                               ORDER BY ABS(TIMESTAMP_DIFF(obs_at, log_at, SECOND)), obs_id) = 1
  ),
  dead_pick AS (
    SELECT * FROM pairs
    WHERE log_status IN ('FAILED_UPLOAD', 'SUPERSEDED_NEVER_UPLOADED')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY obs_id
                               ORDER BY ABS(TIMESTAMP_DIFF(obs_at, log_at, SECOND)), log_id) = 1
  )
  SELECT
    o.change_id,
    CONCAT('observed_', FORMAT_DATE('%Y%m%d', run_date))               AS batch_id,
    o.applied_at,
    o.action,
    CAST(NULL AS STRING)                                                AS search_term,
    o.targeting, o.keyword_id, o.match_type, o.campaign_id, o.campaign_name, o.campaign_type,
    o.ad_group_id,
    CAST(NULL AS STRING)                                                AS product,
    o.old_bid, o.new_bid, o.old_budget, o.new_budget,
    CAST(NULL AS FLOAT64) AS target_spend_8w, CAST(NULL AS INT64) AS target_orders_8w,
    CAST(NULL AS FLOAT64) AS target_net_roas_8w,
    CAST(NULL AS STRING)                                                AS coach_mode,
    'OBSERVED'                                                          AS source,
    CAST(NULL AS FLOAT64) AS expected_impact_weekly, CAST(NULL AS STRING) AS expected_impact_kind,
    'OBSERVED_ON_AMAZON'                                                AS upload_status,
    -- the note's FIRST word is load-bearing: V_PPC_CHANGE_LOG_LANDED reads '^CONFIRMS (\S+)'
    CONCAT(
      CASE
        WHEN m.log_id IS NOT NULL THEN
          CONCAT('CONFIRMS ', m.log_id, ' (logged ', IFNULL(m.log_status, 'NULL'), ' at ',
                 FORMAT_TIMESTAMP('%Y-%m-%d %H:%M UTC', m.log_at), ', seen on Amazon ',
                 CAST(TIMESTAMP_DIFF(o.applied_at, m.log_at, MINUTE) AS STRING), ' min after it)')
        WHEN d.log_id IS NOT NULL THEN
          CONCAT('UNLOGGED: no live change-log row within [-1 day, +3 days]; dead row ', d.log_id,
                 ' (', d.log_status, ') carries the same value, and Amazon shows it landed')
        ELSE 'UNLOGGED: no change-log row within [-1 day, +3 days]'
      END,
      '; ', o.entity, '.', o.attr, ' ',
      CASE o.attr
        WHEN 'state'        THEN CONCAT(o.old_state, ' -> ', o.new_state)
        WHEN 'daily_budget' THEN CONCAT(FORMAT('%.2f', o.old_budget), ' -> ', FORMAT('%.2f', o.new_budget))
        ELSE                     CONCAT(FORMAT('%.2f', o.old_bid), ' -> ', FORMAT('%.2f', o.new_bid))
      END,
      ' at ', FORMAT_DATETIME('%Y-%m-%d %H:%M:%S', o.effective_from), ' UTC')              AS upload_note
  FROM _obs_raw o
  LEFT JOIN live_1to1 m ON m.obs_id = o.change_id
  LEFT JOIN dead_pick d ON d.obs_id = o.change_id
  WHERE NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` f WHERE f.change_id = o.change_id);

  -- ── 3. append (never update, never delete) ────────────────────────────────────────────────────
  INSERT INTO `onyga-482313.OI.FACT_PPC_CHANGE_LOG` (
    change_id, batch_id, applied_at, action, search_term, targeting, keyword_id, match_type,
    campaign_id, campaign_name, campaign_type, ad_group_id, product,
    old_bid, new_bid, old_budget, new_budget,
    target_spend_8w, target_orders_8w, target_net_roas_8w, coach_mode, source,
    expected_impact_weekly, expected_impact_kind, upload_status, upload_note
  )
  SELECT
    change_id, batch_id, applied_at, action, search_term, targeting, keyword_id, match_type,
    campaign_id, campaign_name, campaign_type, ad_group_id, product,
    old_bid, new_bid, old_budget, new_budget,
    target_spend_8w, target_orders_8w, target_net_roas_8w, coach_mode, source,
    expected_impact_weekly, expected_impact_kind, upload_status, upload_note
  FROM _obs_new;

  SET n_inserted = @@row_count;

  -- ── 4. report ─────────────────────────────────────────────────────────────────────────────────
  SELECT FORMAT(
    'SP_RECORD_OBSERVED_CHANGES completed: watermark %s, scanned applied_at > %s, %d candidate changes, %d inserted (%d confirm a logged row, %d unlogged), batch %s, %d seconds',
    IFNULL(CAST(watermark AS STRING), 'none (first run)'),
    IFNULL(CAST(scan_from AS STRING), '2026-08-20 (whole ledger scope)'),
    n_candidates, n_inserted,
    (SELECT COUNTIF(STARTS_WITH(upload_note, 'CONFIRMS ')) FROM _obs_new),
    (SELECT COUNTIF(NOT STARTS_WITH(upload_note, 'CONFIRMS ')) FROM _obs_new),
    CONCAT('observed_', FORMAT_DATE('%Y%m%d', run_date)),
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) AS log_message;

  SELECT
    action,
    DATE_TRUNC(DATE(applied_at, 'America/Los_Angeles'), WEEK(SUNDAY)) AS la_week,
    COUNT(*)                                                           AS inserted,
    COUNTIF(STARTS_WITH(upload_note, 'CONFIRMS '))                     AS confirms_logged_row,
    COUNTIF(NOT STARTS_WITH(upload_note, 'CONFIRMS '))                 AS unlogged
  FROM _obs_new
  GROUP BY 1, 2
  ORDER BY 2, 1;
END;
