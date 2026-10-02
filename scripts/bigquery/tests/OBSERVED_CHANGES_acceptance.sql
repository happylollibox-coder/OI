-- =============================================================================================
-- OBSERVED_CHANGES acceptance — learning-system Task B (2026-10-01). Every real change on Amazon
-- is recorded, whether or not it came from a bulksheet. EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Objects: scripts/bigquery/views/V_AMAZON_OBSERVED_CHANGES.sql (the derivation),
--          scripts/bigquery/procedures/SP_RECORD_OBSERVED_CHANGES.sql (the writer, Refresh Task 2.2a),
--          scripts/bigquery/views/V_PPC_CHANGE_LOG_APPLIED.sql (excludes OBSERVED_ON_AMAZON),
--          scripts/bigquery/views/V_PPC_CHANGE_LOG_LANDED.sql (the grader's source),
--          scripts/bigquery/views/V_CHANGE_SCORECARD.sql (grades the observed rows too),
--          V_DAILY_BRIEF / V_ENGINE_HEALTH / V_THRESHOLD_TUNER (read the scorecard without them).
-- SOP: architecture/PPC_CLOSE_THE_LOOP.md §Observed changes.
--
-- WHAT THIS FILE PROVES. (1) The ledger is complete and idempotent: everything the SCD trail
-- shows since 2026-08-20 has exactly one row, so a second run inserts nothing. (2) No row is a
-- new entity's first version. (3) Every observed row is a real DIM version pair, re-derived here
-- from the loader's own effective_to chain (independently of the view's LAG). (4) The 2026-08-26
-- ME-SP/AUTO close-match raise is on record as INCREASE_BID. (5) Every reader of
-- V_PPC_CHANGE_LOG_APPLIED (the engines, /api/applied-recent) still reads exactly the
-- rows it read before the ledger existed. (6) The grader counts a logged change and its observed
-- landing once, and drops nothing. (7) The brief, the board and the tuner read the scorecard
-- without the observed rows.
--
-- NEGATIVE CONTROLS ARE STANDING CHECKS HERE, NOT A ONE-OFF. Each check is computed per COPY of
-- its input — the LIVE rows and doctored TEMP copies built below — in one statement, and every
-- control asserts that its doctored copy FIRES. No copy touches a table: the doctoring happens in
-- temp tables only. Emptiness terms make an empty input FAIL (an empty ledger is a broken
-- writer, not a clean one).
--
-- THE 2026-08-26 RAISE. The task named it '0.68 -> 1.10'. DIM_KEYWORD's trail for that target
-- (keyword_id 373381078695862, close-match, campaign 527422818407259) reads 0.74 (2026-08-15) ->
-- 0.68 (08-17) -> 0.64 (08-24) -> 0.53 (08-25) -> 1.10 (08-26): the raise to 1.10 is from 0.53,
-- and 0.68 -> 0.64 and 0.64 -> 0.53 are REDUCE_BID rows of their own. C05 asserts the pair the
-- trail shows, 0.53 -> 1.10.
--
-- RUN LOG — beside the raise's trail above (history C05 asserts), the only place this file
-- states a measurement. Each entry is dated; re-run the file (and the queries named) rather than
-- trusting a figure here.
--
-- RUN 2026-10-01 (evening, LA), after the backfill and every deploy: 20 rows, every one PASS, on
-- the live views. 14,671 slot-seconds, 175 s elapsed (the four ceiling reads — scorecard, brief,
-- board, tuner — are most of it). The intermediates were printed by a run of this file's own
-- temp-table steps, with the four ceiling views read from scratch copies taken that evening after
-- the last deploy (same deployed state), so each control is known to have FIRED, not to have
-- passed vacuously:
--   per copy (n_rows / missing / dup / bad_label / first_version / bid_mismatch / other_mismatch /
--   raise_rows): LIVE 246/0/0/0/0/0/0/1 (173 bid rows, 73 other); NC_DROP_ONE 245/1;
--   NC_DUP_ONE dup 1; NC_NULL_STATUS bad_label 1; NC_FIRST_VERSION first_version 1;
--   NC_BID_SHIFTED bid_mismatch 1, raise_rows 0; NC_DIRECTION_FLIPPED bid_mismatch 1, raise_rows 0;
--   NC_NO_RAISE raise_rows 0; NC_OTHER_SHIFTED other_mismatch 2; NC_EMPTY missing 246.
--   C06: LIVE 0, NC_OLD_FILTER 492 (each of the 246 observed rows counted as OBSERVED and as extra).
--   C07: LIVE 0/0/0; NC_FANOUT a=1; NC_PAIR_KEPT b=1; NC_OBS_DROPPED c=1 (70 observed rows confirm
--        an applied log row; 1,840 applied rows).
--   C08: LIVE 0, NC_ORPHAN 1, NC_TWIN_GRADED 2 (orphan + twin).
--   C09: brief VERDICT_NEW 0 = twin without 0 (with: 2 — the control fired); board c6 66.0 /
--        '53 judged · 8 too thin to judge' = twin without (with: 55.9 / 170 judged · 36 thin);
--        tuner n equals the twin without on all 9 printed scopes, and the twin with differs on 8.
--
-- ONE-TIME BEFORE/AFTER PROOFS, 2026-10-01 (not re-run by this file; the standing forms are C06-C09):
--   APPLIED fingerprint SELECT COUNT(*), BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) FROM
--     V_PPC_CHANGE_LOG_APPLIED t read 1840 / 1099856995586647352 before any deploy, after the view
--     gained its exclusion, after the 246-row backfill, and after every later deploy.
--   COUNT(*) on each view that reads APPLIED, before the first deploy and after the last:
--     V_ADS_COACH_DATA 59935/59935, V_ADS_INCREMENTAL_14D 19/19, V_DAILY_BRIEF 396/396,
--     V_FAMILY_SEAT_REGISTER 332/332, V_KEYWORD_GUARD 482/482, V_KEYWORD_LIFT 508/508,
--     V_MANUAL_DIVERGENCE 150/150, V_OOB_BUDGET_PHASE 21/21, V_OOB_KEYWORD 176/176,
--     V_OOB_SEARCH_TERM 88239/88239, V_PARK_REVERDICT 556/556, V_PPC_ACTION_OUTCOMES 1831/1831,
--     V_RUN_TARGET 1180/1180, V_SB_LAUNCH_TARGET 87/87, V_WEEKLY_RUN_CAMPAIGN 106/106,
--     V_WEEKLY_RUN_KEYWORD 367/367; V_CHANGE_SCORECARD 1828 -> 1973 by design (+145 graded
--     observed rows). The three procedures that read APPLIED (SP_MAINTAIN_FAMILY_SEATS,
--     SP_SNAPSHOT_KEYWORD_STATE, SP_SYNC_NEGATIVES) cannot be counted; their input is the
--     fingerprinted view.
--   V_CHANGE_SCORECARD, full outputs compared per column on change_id: 0 of the 1,828 earlier rows
--     lost, 0 non-observed rows gained, every column identical except the contamination flags on 8
--     rows (n_later_changes 8, next_change_date 5, superseded_in_window 5) — hand changes now seen
--     inside the windows of logged changes, e.g. chg_manual_20260811_boxsbs_bud100 (SB budget,
--     window to 2026-08-25) gained next_change_date 2026-08-21. No verdict, window or remedy moved.
--   V_DAILY_BRIEF (396 rows), V_ENGINE_HEALTH (32) and V_THRESHOLD_TUNER (10): byte-identical
--     before and after (EXCEPT DISTINCT on TO_JSON_STRING both ways: 0 / 0).
--   SP_RECORD_OBSERVED_CHANGES second run: 31 candidates in the 7-day overlap, 0 inserted.
--   Slot cost of the scorecard (SELECT COUNT(*), fingerprint over every column; five runs each,
--     alternating): before 801 / 1,295 / 1,032 / 642 / 1,153, after 2,044 / 1,306 / 1,097 / 1,485
--     / 1,698 — about half again, for 145 more graded changes. The brief, which embeds the
--     scorecard, measured 1,511 / 3,992 / 3,605 on the old scorecard and 1,520 / 2,631 / 2,380 on
--     the new one: no increase beyond run-to-run noise.
-- =============================================================================================

-- ---- inputs, each read ONCE -------------------------------------------------------------------
CREATE TEMP TABLE obs_live AS
  SELECT * FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE source = 'OBSERVED';
CREATE TEMP TABLE fact_rest AS
  SELECT change_id, source, upload_status FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE source != 'OBSERVED';
CREATE TEMP TABLE trail AS
  SELECT change_id FROM `onyga-482313.OI.V_AMAZON_OBSERVED_CHANGES` WHERE in_ledger_scope;
CREATE TEMP TABLE applied AS
  SELECT change_id, source, upload_status FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`;
CREATE TEMP TABLE landed AS
  SELECT change_id, source, landed_evidence, paired_change_id FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED`;
-- the scorecard and the three surfaces that read it (ceiling views: one scan apiece)
CREATE TEMP TABLE sc AS
  SELECT change_id, source, landed_evidence, verdict, read_gate_date, change_date, action_group, pct_change
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD`;
CREATE TEMP TABLE brief AS
  SELECT section FROM `onyga-482313.OI.V_DAILY_BRIEF`;
CREATE TEMP TABLE board AS
  SELECT check_name, measured, detail FROM `onyga-482313.OI.V_ENGINE_HEALTH`;
CREATE TEMP TABLE tuner AS
  SELECT scope, n FROM `onyga-482313.OI.V_THRESHOLD_TUNER`;

-- every DIM version, keyed by what an observed change_id names: entity, id, effective_from.
-- The predecessor is found through the loader's own close-out stamp (effective_to = the next
-- version's effective_from, SP_LOAD_DIM_*), NOT through the view's LAG, so C03/C04 are an
-- independent re-derivation. MIN/MAX fold the duplicate (id, effective_from) pairs the old loads
-- left in DIM_AD_GROUP / DIM_CAMPAIGN; they carry identical tracked values.
CREATE TEMP TABLE dimv AS
  SELECT 'DIM_KEYWORD' AS entity, keyword_id AS id, campaign_id, bid AS v_num, UPPER(NULLIF(TRIM(state), '')) AS v_state,
         effective_from, effective_to FROM `onyga-482313.OI.DIM_KEYWORD`
  UNION ALL
  SELECT 'DIM_CAMPAIGN', campaign_id, campaign_id, daily_budget, UPPER(NULLIF(TRIM(state), '')),
         effective_from, effective_to FROM `onyga-482313.OI.DIM_CAMPAIGN`
  UNION ALL
  SELECT 'DIM_AD_GROUP', ad_group_id, campaign_id, default_bid, UPPER(NULLIF(TRIM(state), '')),
         effective_from, effective_to FROM `onyga-482313.OI.DIM_AD_GROUP`;
CREATE TEMP TABLE ver AS
  SELECT entity, id, effective_from, MIN(v_num) AS v_num, MIN(v_state) AS v_state, MIN(campaign_id) AS campaign_id
  FROM dimv GROUP BY 1, 2, 3;
CREATE TEMP TABLE pred AS
  SELECT entity, id, effective_to, MIN(v_num) AS v_num, MIN(v_state) AS v_state
  FROM dimv WHERE effective_to IS NOT NULL GROUP BY 1, 2, 3;

-- ---- the ledger rows: LIVE and doctored copies -------------------------------------------------
-- victims, chosen deterministically: the smallest change_id; the 2026-08-26 raise; the smallest
-- budget row; the smallest keyword-pause row; and a FIRST version (no predecessor) of the raise's
-- own target, minted as a fake ledger row
CREATE TEMP TABLE victims AS
  SELECT
    (SELECT MIN(change_id) FROM obs_live) AS any_id,
    (SELECT MIN(change_id) FROM obs_live
      WHERE campaign_id = '527422818407259' AND keyword_id = '373381078695862' AND action = 'INCREASE_BID'
        AND DATE(applied_at, 'America/Los_Angeles') = DATE '2026-08-26') AS raise_id,
    (SELECT MIN(change_id) FROM obs_live WHERE action = 'BUDGET_CHANGE') AS budget_id,
    (SELECT MIN(change_id) FROM obs_live WHERE action = 'KEYWORD_PAUSE') AS pause_id,
    (SELECT CONCAT('obs|DIM_KEYWORD|373381078695862|bid|', FORMAT_DATETIME('%Y-%m-%dT%H:%M:%E6S', MIN(effective_from)))
       FROM `onyga-482313.OI.DIM_KEYWORD` WHERE keyword_id = '373381078695862') AS first_version_id;

CREATE TEMP TABLE obs_copies AS
  SELECT 'LIVE' AS copy, o.* FROM obs_live o
  UNION ALL  -- C01 fires: one row missing
  SELECT 'NC_DROP_ONE', o.* FROM obs_live o, victims v WHERE o.change_id != v.any_id
  UNION ALL  -- C02 fires: one row twice
  SELECT 'NC_DUP_ONE', o.* FROM obs_live o
  UNION ALL
  SELECT 'NC_DUP_ONE', o.* FROM obs_live o, victims v WHERE o.change_id = v.any_id
  UNION ALL  -- C02 fires: one row would read as applied (NULL status leaks into every engine)
  SELECT 'NC_NULL_STATUS', o.* REPLACE (IF(o.change_id = v.any_id, NULL, o.upload_status) AS upload_status)
  FROM obs_live o, victims v
  UNION ALL  -- C03 fires: a first version recorded as a change
  SELECT 'NC_FIRST_VERSION', o.* FROM obs_live o
  UNION ALL
  SELECT 'NC_FIRST_VERSION', o.* REPLACE (v.first_version_id AS change_id)
  FROM obs_live o, victims v WHERE o.change_id = v.raise_id
  UNION ALL  -- C04 and C05 fire: the raise's old bid off by a cent
  SELECT 'NC_BID_SHIFTED', o.* REPLACE (IF(o.change_id = v.raise_id, o.old_bid + 0.01, o.old_bid) AS old_bid)
  FROM obs_live o, victims v
  UNION ALL  -- C04 and C05 fire: the raise recorded as a cut
  SELECT 'NC_DIRECTION_FLIPPED', o.* REPLACE (IF(o.change_id = v.raise_id, 'REDUCE_BID', o.action) AS action)
  FROM obs_live o, victims v
  UNION ALL  -- C05 fires: the raise missing
  SELECT 'NC_NO_RAISE', o.* FROM obs_live o, victims v WHERE o.change_id != v.raise_id
  UNION ALL  -- C04b fires: a budget a dollar off, and a pause recorded as an enable
  SELECT 'NC_OTHER_SHIFTED', o.* REPLACE (
           IF(o.change_id = v.budget_id, o.new_budget + 1, o.new_budget) AS new_budget,
           IF(o.change_id = v.pause_id, 'KEYWORD_ENABLE', o.action) AS action)
  FROM obs_live o, victims v;
-- NC_EMPTY has no rows: an empty ledger
CREATE TEMP TABLE copies AS
  SELECT copy FROM UNNEST(['LIVE', 'NC_DROP_ONE', 'NC_DUP_ONE', 'NC_NULL_STATUS', 'NC_FIRST_VERSION',
                           'NC_BID_SHIFTED', 'NC_DIRECTION_FLIPPED', 'NC_NO_RAISE', 'NC_OTHER_SHIFTED',
                           'NC_EMPTY']) AS copy;

-- each copy row against the DIM version it names and that version's predecessor
CREATE TEMP TABLE obs_judged AS
  WITH p AS (
    SELECT c.*,
           SPLIT(c.change_id, '|')[SAFE_OFFSET(1)] AS p_entity,
           SPLIT(c.change_id, '|')[SAFE_OFFSET(2)] AS p_id,
           SPLIT(c.change_id, '|')[SAFE_OFFSET(3)] AS p_attr,
           SAFE.PARSE_DATETIME('%Y-%m-%dT%H:%M:%E6S', SPLIT(c.change_id, '|')[SAFE_OFFSET(4)]) AS p_ef
    FROM obs_copies c
  )
  SELECT p.copy, p.change_id, p.action, p.keyword_id, p.campaign_id, p.applied_at,
         p.old_bid, p.new_bid, p.old_budget, p.new_budget, p.p_entity, p.p_id, p.p_attr, p.p_ef,
         v.v_num AS ver_num, v.v_state AS ver_state, v.effective_from IS NOT NULL AS ver_found,
         pr.v_num AS pred_num, pr.v_state AS pred_state, pr.effective_to IS NOT NULL AS pred_found,
         p.action IN ('INCREASE_BID', 'REDUCE_BID') AS is_bid_row
  FROM p
  LEFT JOIN ver v   ON v.entity = p.p_entity AND v.id = p.p_id AND v.effective_from = p.p_ef
  LEFT JOIN pred pr ON pr.entity = p.p_entity AND pr.id = p.p_id AND pr.effective_to = p.p_ef;

CREATE TEMP TABLE per_copy AS
  WITH
  cnt AS (
    SELECT copy,
           COUNT(*) AS n_rows,
           -- C02: a change recorded twice, or a row not carrying the labels that keep it out of APPLIED
           COUNT(*) - COUNT(DISTINCT change_id) AS dup,
           COUNTIF(COALESCE(upload_status, '') != 'OBSERVED_ON_AMAZON' OR coach_mode IS NOT NULL
                   OR NOT STARTS_WITH(change_id, 'obs|') OR NOT STARTS_WITH(batch_id, 'observed_')
                   OR source != 'OBSERVED') AS bad_label,
           -- C05: the 2026-08-26 close-match raise, exactly once, as the trail shows it
           COUNTIF(campaign_id = '527422818407259' AND keyword_id = '373381078695862'
                   AND action = 'INCREASE_BID' AND DATE(applied_at, 'America/Los_Angeles') = DATE '2026-08-26'
                   AND ABS(new_bid - 1.10) < 0.0005 AND ABS(old_bid - 0.53) < 0.0005) AS raise_rows
    FROM obs_copies GROUP BY copy
  ),
  jud AS (
    SELECT copy,
           -- C03: the version a row names does not exist, or has no predecessor (a creation)
           COUNTIF(NOT ver_found OR NOT pred_found) AS first_version,
           -- C04: bid rows that are not the DIM_KEYWORD pair they name
           COUNTIF(is_bid_row) AS n_bid,
           COUNTIF(is_bid_row AND NOT COALESCE(
             p_entity = 'DIM_KEYWORD' AND p_attr = 'bid' AND p_id = keyword_id
             AND ABS(ver_num - new_bid) < 0.0001 AND ABS(pred_num - old_bid) < 0.0001
             AND action = IF(ver_num > pred_num, 'INCREASE_BID', 'REDUCE_BID'), FALSE)) AS bid_mismatch,
           -- C04b: budget, default-bid and state rows that are not the pair they name
           COUNTIF(NOT is_bid_row) AS n_other,
           COUNTIF(NOT is_bid_row AND NOT COALESCE(
             CASE
               WHEN action = 'BUDGET_CHANGE' THEN
                 p_entity = 'DIM_CAMPAIGN' AND p_attr = 'daily_budget' AND p_id = campaign_id
                 AND ABS(ver_num - new_budget) < 0.001 AND ABS(pred_num - old_budget) < 0.001
               WHEN action = 'ADGROUP_DEFAULT_BID' THEN
                 p_entity = 'DIM_AD_GROUP' AND p_attr = 'default_bid'
                 AND ABS(ver_num - new_bid) < 0.0001 AND ABS(pred_num - old_bid) < 0.0001
               WHEN REGEXP_CONTAINS(action, r'^(KEYWORD|CAMPAIGN|ADGROUP)_(PAUSE|ENABLE|ARCHIVE)$') THEN
                 p_attr = 'state'
                 AND p_entity = CASE SPLIT(action, '_')[OFFSET(0)] WHEN 'KEYWORD' THEN 'DIM_KEYWORD'
                                     WHEN 'CAMPAIGN' THEN 'DIM_CAMPAIGN' ELSE 'DIM_AD_GROUP' END
                 AND ver_state = CASE SPLIT(action, '_')[OFFSET(1)] WHEN 'PAUSE' THEN 'PAUSED'
                                      WHEN 'ENABLE' THEN 'ENABLED' ELSE 'ARCHIVED' END
                 AND pred_state IN ('ENABLED', 'PAUSED', 'ARCHIVED') AND pred_state != ver_state
               ELSE FALSE
             END, FALSE)) AS other_mismatch
    FROM obs_judged GROUP BY copy
  ),
  -- C01: changes the trail shows with no ledger row (what a second run would insert)
  miss AS (
    SELECT c.copy, COUNT(*) AS missing
    FROM copies c CROSS JOIN trail t
    LEFT JOIN obs_copies o ON o.copy = c.copy AND o.change_id = t.change_id
    WHERE o.change_id IS NULL
    GROUP BY 1
  )
  SELECT c.copy,
         COALESCE(cnt.n_rows, 0) AS n_rows, COALESCE(miss.missing, 0) AS missing,
         COALESCE(cnt.dup, 0) AS dup, COALESCE(cnt.bad_label, 0) AS bad_label,
         COALESCE(jud.first_version, 0) AS first_version,
         COALESCE(jud.n_bid, 0) AS n_bid, COALESCE(jud.bid_mismatch, 0) AS bid_mismatch,
         COALESCE(jud.n_other, 0) AS n_other, COALESCE(jud.other_mismatch, 0) AS other_mismatch,
         COALESCE(cnt.raise_rows, 0) AS raise_rows
  FROM copies c
  LEFT JOIN cnt  ON cnt.copy = c.copy
  LEFT JOIN jud  ON jud.copy = c.copy
  LEFT JOIN miss ON miss.copy = c.copy;

-- ---- C06: V_PPC_CHANGE_LOG_APPLIED — LIVE / the pre-2026-10-01 filter ----------------------------
-- expected = the log's own rows (never OBSERVED) through the filter APPLIED had before the ledger
-- existed. Those rows are untouched by this work, so LIVE == expected means every reader of APPLIED
-- reads exactly the rows it read before. NC_OLD_FILTER is the view as it stood before 2026-10-01
-- run over today's table: it must FIRE, because the observed rows pass its filter.
CREATE TEMP TABLE applied_expected AS
  SELECT change_id FROM fact_rest
  WHERE COALESCE(upload_status, '') NOT IN ('FAILED_UPLOAD', 'SUPERSEDED_NEVER_UPLOADED', 'PENDING_UPLOAD');
CREATE TEMP TABLE applied_copies AS
  SELECT 'LIVE' AS copy, change_id, source, upload_status FROM applied
  UNION ALL
  SELECT 'NC_OLD_FILTER', change_id, source, upload_status FROM fact_rest
  WHERE COALESCE(upload_status, '') NOT IN ('FAILED_UPLOAD', 'SUPERSEDED_NEVER_UPLOADED', 'PENDING_UPLOAD')
  UNION ALL
  SELECT 'NC_OLD_FILTER', change_id, source, upload_status FROM obs_live
  WHERE COALESCE(upload_status, '') NOT IN ('FAILED_UPLOAD', 'SUPERSEDED_NEVER_UPLOADED', 'PENDING_UPLOAD');
CREATE TEMP TABLE applied_v AS
  WITH
  cps AS (SELECT cp AS copy FROM UNNEST(['LIVE', 'NC_OLD_FILTER']) AS cp),
  agg AS (
    SELECT copy, COUNTIF(source = 'OBSERVED' OR upload_status = 'OBSERVED_ON_AMAZON') AS obs_rows,
           COUNT(*) - COUNT(DISTINCT change_id) AS dup
    FROM applied_copies GROUP BY copy
  ),
  extra AS (
    SELECT a.copy, COUNT(*) AS n
    FROM applied_copies a LEFT JOIN applied_expected e ON e.change_id = a.change_id
    WHERE e.change_id IS NULL GROUP BY 1
  ),
  miss AS (
    SELECT c.copy, COUNT(*) AS n
    FROM cps c CROSS JOIN applied_expected e
    LEFT JOIN applied_copies a ON a.copy = c.copy AND a.change_id = e.change_id
    WHERE a.change_id IS NULL GROUP BY 1
  )
  SELECT c.copy, COALESCE(agg.obs_rows, 0) + COALESCE(agg.dup, 0) + COALESCE(extra.n, 0) + COALESCE(miss.n, 0) AS v
  FROM cps c
  LEFT JOIN agg   ON agg.copy = c.copy
  LEFT JOIN extra ON extra.copy = c.copy
  LEFT JOIN miss  ON miss.copy = c.copy;

-- ---- C07: V_PPC_CHANGE_LOG_LANDED — LIVE / a fanned-out log row / a pair kept twice / a hand
-- change dropped ---------------------------------------------------------------------------------
-- the observed rows that confirm a row now in APPLIED: LANDED must drop each (the log row stands
-- for the pair); every other observed row must be in LANDED
CREATE TEMP TABLE obs_pairs AS
  SELECT o.change_id, REGEXP_EXTRACT(o.upload_note, r'^CONFIRMS (\S+)') AS confirms_id,
         a.change_id IS NOT NULL AS confirms_applied
  FROM obs_live o
  LEFT JOIN applied a ON a.change_id = REGEXP_EXTRACT(o.upload_note, r'^CONFIRMS (\S+)');
CREATE TEMP TABLE landed_copies AS
  SELECT 'LIVE' AS copy, l.* FROM landed l
  UNION ALL
  SELECT 'NC_FANOUT', l.* FROM landed l
  UNION ALL
  SELECT 'NC_FANOUT', l.* FROM landed l
  WHERE l.change_id = (SELECT MIN(change_id) FROM landed WHERE landed_evidence = 'LOGGED_AND_SEEN_ON_AMAZON')
  UNION ALL
  SELECT 'NC_PAIR_KEPT', l.* FROM landed l
  UNION ALL
  SELECT 'NC_PAIR_KEPT', p.change_id, 'OBSERVED', 'SEEN_ON_AMAZON_LOG_NOT_APPLIED', p.confirms_id
  FROM obs_pairs p WHERE p.change_id = (SELECT MIN(change_id) FROM obs_pairs WHERE confirms_applied)
  UNION ALL
  SELECT 'NC_OBS_DROPPED', l.* FROM landed l
  WHERE l.change_id != (SELECT MIN(change_id) FROM landed WHERE landed_evidence = 'SEEN_ON_AMAZON_NOT_LOGGED');
CREATE TEMP TABLE landed_v AS
  WITH
  cps AS (SELECT cp AS copy FROM UNNEST(['LIVE', 'NC_FANOUT', 'NC_PAIR_KEPT', 'NC_OBS_DROPPED']) AS cp),
  dups AS (
    SELECT copy,
           COUNTIF(source != 'OBSERVED') - COUNT(DISTINCT IF(source != 'OBSERVED', change_id, NULL)) AS log_dup,
           COUNTIF(source = 'OBSERVED')  - COUNT(DISTINCT IF(source = 'OBSERVED', change_id, NULL))  AS obs_dup
    FROM landed_copies GROUP BY copy
  ),
  -- (a) the log side is APPLIED exactly: same ids, none twice
  applied_missing AS (
    SELECT c.copy, COUNT(*) AS n
    FROM cps c CROSS JOIN applied a
    LEFT JOIN landed_copies l ON l.copy = c.copy AND l.change_id = a.change_id
    WHERE l.change_id IS NULL GROUP BY 1
  ),
  log_extra AS (
    SELECT l.copy, COUNT(*) AS n
    FROM landed_copies l LEFT JOIN applied a ON a.change_id = l.change_id
    WHERE l.source != 'OBSERVED' AND a.change_id IS NULL GROUP BY 1
  ),
  -- (b) no observed row whose logged twin is already there
  twin_kept AS (
    SELECT l.copy, COUNT(*) AS n
    FROM landed_copies l JOIN applied a ON a.change_id = l.paired_change_id
    WHERE l.source = 'OBSERVED' GROUP BY 1
  ),
  -- (c) every other observed row is there, once
  obs_missing AS (
    SELECT c.copy, COUNT(*) AS n
    FROM cps c CROSS JOIN obs_pairs p
    LEFT JOIN landed_copies l ON l.copy = c.copy AND l.change_id = p.change_id
    WHERE NOT p.confirms_applied AND l.change_id IS NULL GROUP BY 1
  )
  SELECT c.copy,
         COALESCE(d.log_dup, 0) + COALESCE(am.n, 0) + COALESCE(le.n, 0) AS a_log_side,
         COALESCE(tk.n, 0)                                              AS b_twin_kept,
         COALESCE(om.n, 0) + COALESCE(d.obs_dup, 0)                     AS c_obs_side
  FROM cps c
  LEFT JOIN dups d             ON d.copy = c.copy
  LEFT JOIN applied_missing am ON am.copy = c.copy
  LEFT JOIN log_extra le       ON le.copy = c.copy
  LEFT JOIN twin_kept tk       ON tk.copy = c.copy
  LEFT JOIN obs_missing om     ON om.copy = c.copy;

-- ---- C08: the scorecard grades what LANDED holds and nothing twice — LIVE / a twin graded / an
-- orphan -----------------------------------------------------------------------------------------
CREATE TEMP TABLE sc_copies AS
  SELECT 'LIVE' AS copy, change_id, source FROM sc
  UNION ALL
  SELECT 'NC_TWIN_GRADED', change_id, source FROM sc
  UNION ALL
  SELECT 'NC_TWIN_GRADED', p.change_id, 'OBSERVED' FROM obs_pairs p
  WHERE p.change_id = (SELECT MIN(change_id) FROM obs_pairs WHERE confirms_applied)
  UNION ALL
  SELECT 'NC_ORPHAN', IF(change_id = (SELECT MIN(change_id) FROM sc WHERE source != 'OBSERVED'),
                         'chg_not_in_any_log', change_id), source FROM sc;
CREATE TEMP TABLE sc_v AS
  WITH
  cps AS (SELECT cp AS copy FROM UNNEST(['LIVE', 'NC_TWIN_GRADED', 'NC_ORPHAN']) AS cp),
  agg AS (
    SELECT copy, COUNT(*) - COUNT(DISTINCT change_id) AS dup,
           IF(COUNTIF(source = 'OBSERVED') = 0, 1, 0) AS none_observed
    FROM sc_copies GROUP BY copy
  ),
  -- a graded row that is not in LANDED under its own source
  orphan AS (
    SELECT s.copy, COUNT(*) AS n
    FROM sc_copies s LEFT JOIN landed l ON l.change_id = s.change_id AND l.source = s.source
    WHERE l.change_id IS NULL GROUP BY 1
  ),
  -- a graded observed row whose logged twin is in APPLIED: the pair graded twice
  twin AS (
    SELECT s.copy, COUNT(*) AS n
    FROM sc_copies s JOIN obs_pairs p ON p.change_id = s.change_id
    WHERE p.confirms_applied GROUP BY 1
  )
  SELECT c.copy, COALESCE(agg.dup, 0) + COALESCE(orphan.n, 0) + COALESCE(twin.n, 0) + COALESCE(agg.none_observed, 1) AS v
  FROM cps c
  LEFT JOIN agg    ON agg.copy = c.copy
  LEFT JOIN orphan ON orphan.copy = c.copy
  LEFT JOIN twin   ON twin.copy = c.copy;

-- ---- C09: the three readers of the scorecard — twins with and without the observed rows ----------
-- TWIN of V_DAILY_BRIEF verdict_new: scorecard rows whose read gate fell in the last three days
CREATE TEMP TABLE brief_twin AS
  SELECT COUNTIF(source != 'OBSERVED' AND read_gate_date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 3 DAY)
                                                            AND CURRENT_DATE('America/Los_Angeles')) AS n_without,
         COUNTIF(read_gate_date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 3 DAY)
                                    AND CURRENT_DATE('America/Los_Angeles')) AS n_with
  FROM sc;
-- TWIN of V_ENGINE_HEALTH c6 (scorecard_reversed_share): measured and detail, last 42 days
CREATE TEMP TABLE c6_twin AS
  SELECT w AS copy,
         ROUND(SAFE_DIVIDE(COUNTIF(verdict = 'REVERSED'), NULLIF(COUNTIF(verdict != 'INSUFFICIENT'), 0)) * 100, 1) AS measured,
         CONCAT(CAST(COUNTIF(verdict != 'INSUFFICIENT') AS STRING), ' judged · ',
                CAST(COUNTIF(verdict = 'INSUFFICIENT') AS STRING), ' too thin to judge') AS detail
  FROM sc, UNNEST(['WITHOUT', 'WITH']) AS w
  WHERE change_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 42 DAY)
    AND (w = 'WITH' OR source != 'OBSERVED')
  GROUP BY 1;
-- TWIN of V_THRESHOLD_TUNER graded + cells: n per (action_group @ step bucket), cells of >= 20
CREATE TEMP TABLE tuner_twin AS
  SELECT w AS copy,
         CONCAT(action_group, ' @ ',
                CASE WHEN ABS(COALESCE(pct_change, 0)) <= 7.5 THEN 'step ≤5%'
                     WHEN ABS(COALESCE(pct_change, 0)) <= 12.5 THEN 'step ~10%'
                     WHEN ABS(COALESCE(pct_change, 0)) <= 20 THEN 'step ~15%'
                     ELSE 'step >20%' END) AS scope,
         COUNT(*) AS n
  FROM sc, UNNEST(['WITHOUT', 'WITH']) AS w
  WHERE verdict IS NOT NULL AND verdict != 'INSUFFICIENT'
    AND (w = 'WITH' OR source != 'OBSERVED')
  GROUP BY 1, 2
  HAVING COUNT(*) >= 20;
-- the tuner's printed proposal rows (the static PARK citation row carries n = 0 and no cell)
CREATE TEMP TABLE tuner_rows AS SELECT scope, n FROM tuner WHERE scope NOT LIKE 'PARK calibration%';

WITH
L AS (SELECT * FROM per_copy WHERE copy = 'LIVE'),
-- A SECOND RUN WOULD INSERT ROWS: a change on Amazon has no row — the nightly step failed or was
-- skipped after a DIM load, and the scorecard is grading without it.
c01 AS (
  SELECT 'C01 the ledger is complete: every change the SCD trail shows since 2026-08-20 has its row (a second run inserts 0)' AS check_name,
         (SELECT missing FROM L) + (SELECT IF(COUNT(*) = 0, 1, 0) FROM trail) AS violations
),
c01n AS (
  SELECT 'C01n NEGATIVE CONTROL C01 FIRES: one ledger row dropped -> 1 missing; an empty ledger -> all missing',
         (SELECT IF(missing = 1, 0, 1) FROM per_copy WHERE copy = 'NC_DROP_ONE')
       + (SELECT IF(missing = (SELECT COUNT(*) FROM trail) AND missing > 0, 0, 1) FROM per_copy WHERE copy = 'NC_EMPTY')
),
-- A CHANGE IS COUNTED TWICE, OR A ROW READS AS APPLIED: the scorecard grades it twice, or every
-- engine (cooldowns, probation clock, seat register) starts reading hand changes.
c02 AS (
  SELECT 'C02 one row per change, each labelled OBSERVED / OBSERVED_ON_AMAZON / observed_* / obs|* / no coach_mode',
         (SELECT dup + bad_label + IF(n_rows = 0, 1, 0) FROM L)
),
c02n AS (
  SELECT 'C02n NEGATIVE CONTROL C02 FIRES: a row doubled -> 1; a row with a NULL status -> 1',
         (SELECT IF(dup = 1, 0, 1) FROM per_copy WHERE copy = 'NC_DUP_ONE')
       + (SELECT IF(bad_label = 1, 0, 1) FROM per_copy WHERE copy = 'NC_NULL_STATUS')
),
-- A CREATION IS GRADED AS A DECISION: a new keyword's opening bid reads as a raise and its launch
-- week is scored as if someone chose it.
c03 AS (
  SELECT 'C03 no row is a first version: every row names a DIM version that has a predecessor',
         (SELECT first_version + IF(n_rows = 0, 1, 0) FROM L)
),
c03n AS (
  SELECT 'C03n NEGATIVE CONTROL C03 FIRES: a row naming the first version of target 373381078695862 -> 1',
         (SELECT IF(first_version = 1, 0, 1) FROM per_copy WHERE copy = 'NC_FIRST_VERSION')
),
-- A RECORDED BID IS NOT THE BID AMAZON HELD: the grader scores a change that did not happen, and a
-- REVERSED remedy restores a value the keyword never had.
c04 AS (
  SELECT 'C04 every observed bid change is a real DIM_KEYWORD version pair (new = version, old = predecessor via effective_to, direction agrees)',
         (SELECT bid_mismatch + IF(n_bid = 0, 1, 0) FROM L)
),
c04n AS (
  SELECT 'C04n NEGATIVE CONTROL C04 FIRES: the raise\'s old bid +$0.01 -> 1; the raise relabelled REDUCE_BID -> 1',
         (SELECT IF(bid_mismatch = 1, 0, 1) FROM per_copy WHERE copy = 'NC_BID_SHIFTED')
       + (SELECT IF(bid_mismatch = 1, 0, 1) FROM per_copy WHERE copy = 'NC_DIRECTION_FLIPPED')
),
c04b AS (
  SELECT 'C04b every observed budget, default-bid and state change is the DIM version pair it names',
         (SELECT other_mismatch + IF(n_other = 0, 1, 0) FROM L)
),
c04bn AS (
  SELECT 'C04bn NEGATIVE CONTROL C04b FIRES: a budget $1 off and a pause recorded as an enable -> 2',
         (SELECT IF(other_mismatch = 2, 0, 1) FROM per_copy WHERE copy = 'NC_OTHER_SHIFTED')
),
-- THE HAND RAISE THAT STARTED THIS IS NOT ON RECORD: the 2026-08-26 close-match raise is graded
-- nowhere and the learning loop misses the change Ori asked about.
c05 AS (
  SELECT 'C05 the 2026-08-26 ME-SP/AUTO close-match raise 0.53 -> 1.10 is one INCREASE_BID row, and LANDED carries it as a hand change',
         (SELECT ABS(raise_rows - 1) FROM L)
       + (SELECT IF(COUNT(*) = 1, 0, 1) FROM landed l JOIN victims v ON l.change_id = v.raise_id
          WHERE l.landed_evidence = 'SEEN_ON_AMAZON_NOT_LOGGED')
),
c05n AS (
  SELECT 'C05n NEGATIVE CONTROL C05 FIRES: the raise removed, relabelled, or its old bid shifted -> 0 rows each',
         (SELECT IF(raise_rows = 0, 0, 1) FROM per_copy WHERE copy = 'NC_NO_RAISE')
       + (SELECT IF(raise_rows = 0, 0, 1) FROM per_copy WHERE copy = 'NC_DIRECTION_FLIPPED')
       + (SELECT IF(raise_rows = 0, 0, 1) FROM per_copy WHERE copy = 'NC_BID_SHIFTED')
),
-- EVERY ENGINE STARTS READING HAND CHANGES AS ITS OWN: cooldowns, the keyword state machine's
-- probation clock, the seat register's live bid and the 48-hour change detectors all move.
c06 AS (
  SELECT 'C06 V_PPC_CHANGE_LOG_APPLIED = the log\'s own rows through the pre-ledger filter: no OBSERVED row, none missing, none extra',
         (SELECT v FROM applied_v WHERE copy = 'LIVE')
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM obs_live)   -- nothing to exclude proves nothing
),
c06n AS (
  SELECT 'C06n NEGATIVE CONTROL C06 FIRES: the view as it stood before 2026-10-01, over today\'s table, leaks every observed row',
         (SELECT IF(v = (SELECT COUNT(*) FROM obs_live) * 2 AND v > 0, 0, 1) FROM applied_v WHERE copy = 'NC_OLD_FILTER')
),
-- THE GRADER COUNTS A CHANGE TWICE OR LOSES ONE: a logged change and its landing both graded, an
-- applied row dropped, or a hand change missing from the record the grader reads.
c07 AS (
  SELECT 'C07 LANDED = APPLIED once each + every observed row except those confirming an applied row',
         (SELECT a_log_side + b_twin_kept + c_obs_side FROM landed_v WHERE copy = 'LIVE')
       + (SELECT IF(COUNTIF(confirms_applied) = 0, 1, 0) FROM obs_pairs)   -- no pair: the twin guard is untested
),
c07n AS (
  SELECT 'C07n NEGATIVE CONTROL C07 FIRES: a log row fanned out -> a; a confirmed pair kept twice -> b; a hand change dropped -> c',
         (SELECT IF(a_log_side = 1 AND b_twin_kept = 0 AND c_obs_side = 0, 0, 1) FROM landed_v WHERE copy = 'NC_FANOUT')
       + (SELECT IF(a_log_side = 0 AND b_twin_kept = 1 AND c_obs_side = 0, 0, 1) FROM landed_v WHERE copy = 'NC_PAIR_KEPT')
       + (SELECT IF(a_log_side = 0 AND b_twin_kept = 0 AND c_obs_side = 1, 0, 1) FROM landed_v WHERE copy = 'NC_OBS_DROPPED')
),
-- THE SCORECARD GRADES NOISE OR STOPS GRADING HAND CHANGES: a row that is in no record, a pair
-- graded twice, or no observed row graded at all.
c08 AS (
  SELECT 'C08 V_CHANGE_SCORECARD: every row is in LANDED under its own source, none twice, no confirmed twin, >= 1 OBSERVED row graded',
         (SELECT v FROM sc_v WHERE copy = 'LIVE')
),
c08n AS (
  SELECT 'C08n NEGATIVE CONTROL C08 FIRES: a confirmed twin graded -> >= 1; a row whose id is in no log -> >= 1',
         (SELECT IF(v >= 1, 0, 1) FROM sc_v WHERE copy = 'NC_TWIN_GRADED')
       + (SELECT IF(v >= 1, 0, 1) FROM sc_v WHERE copy = 'NC_ORPHAN')
),
-- THE MORNING BRIEF, THE BOARD OR THE TUNER CHANGED UNDER ORI WITHOUT A DECISION: a restore of a
-- hand change on the action list, a moved reversed-share, a threshold proposal fed by hand changes.
c09 AS (
  SELECT 'C09 brief VERDICT_NEW, board c6 and tuner n equal their twins computed WITHOUT the observed rows',
         (SELECT IF((SELECT COUNTIF(section = 'VERDICT_NEW') FROM brief) = n_without, 0, 1) FROM brief_twin)
       + (SELECT IF(COUNT(*) = 1, 0, 1) FROM board WHERE check_name = 'scorecard_reversed_share')
       + (SELECT COUNTIF(NOT COALESCE(b.measured = t.measured AND b.detail = t.detail, FALSE))
          FROM board b, c6_twin t WHERE b.check_name = 'scorecard_reversed_share' AND t.copy = 'WITHOUT')
       + (SELECT COUNT(*) FROM tuner_rows r
          WHERE NOT EXISTS (SELECT 1 FROM tuner_twin t WHERE t.copy = 'WITHOUT' AND t.scope = r.scope AND t.n = r.n))
),
c09n AS (
  SELECT 'C09n NEGATIVE CONTROL the twins WITH the observed rows differ from the deployed figures (each vacuous when no observed row falls in its window)',
         (SELECT COUNTIF(NOT (w.measured = o.measured AND w.detail = o.detail)   -- equal: no observed row in 42 days, vacuous
                         AND COALESCE(b.measured = w.measured AND b.detail = w.detail, FALSE))
          FROM c6_twin w JOIN c6_twin o ON w.copy = 'WITH' AND o.copy = 'WITHOUT'
          CROSS JOIN board b WHERE b.check_name = 'scorecard_reversed_share')
       + (SELECT IF(n_with = n_without, 0,
                    IF((SELECT COUNTIF(section = 'VERDICT_NEW') FROM brief) != n_with, 0, 1)) FROM brief_twin)
       + (SELECT IF((SELECT COUNT(*) FROM tuner_rows r JOIN tuner_twin t ON t.copy = 'WITH' AND t.scope = r.scope AND t.n != r.n) > 0
                    OR NOT EXISTS (SELECT 1 FROM tuner_twin w JOIN tuner_twin o ON o.copy = 'WITHOUT' AND o.scope = w.scope
                                   JOIN tuner_rows r ON r.scope = w.scope
                                   WHERE w.copy = 'WITH' AND w.n != o.n), 0, 1))
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c01n UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c02n
      UNION ALL SELECT * FROM c03 UNION ALL SELECT * FROM c03n UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c04n
      UNION ALL SELECT * FROM c04b UNION ALL SELECT * FROM c04bn UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c05n
      UNION ALL SELECT * FROM c06 UNION ALL SELECT * FROM c06n UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c07n
      UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c08n UNION ALL SELECT * FROM c09 UNION ALL SELECT * FROM c09n)
ORDER BY check_name;
