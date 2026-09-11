CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SCORE_INTENT_INDEXES`()
BEGIN
  -- ===========================================================================================
  -- SP_SCORE_INTENT_INDEXES
  -- Materialises the walk-forward evidence layer for the intent CVR index registry, in order:
  --   1. T_INTENT_IDX_HISTORY        <- every DE_INTENT_INDEX_REGISTRY row's source_object, one
  --                                     snapshot per index per UTC month (DELETE + INSERT)
  --   2. T_INTENT_INDEX_SCORECARD    <- V_INTENT_INDEX_SCORECARD  (index verdicts, 18 months)
  --   3. T_INTENT_BASE_TUNING        <- V_INTENT_BASE_TUNING       (recency shape x k_base grid)
  --   4. INTENT_CVR_CALIBRATION      <- T_INTENT_BASE_TUNING.implied_calibration, moved only
  --                                     inside INTENT_CVR_REFIT_MAX_STEP; every decision logged
  --                                     to T_INTENT_REFIT_LOG
  -- Step 1 runs FIRST because step 2 reads the history: a scorecard built before this month's
  -- snapshot exists would score every target month off last month's index. Step 4 runs LAST
  -- because it reads the tuning table step 3 just rebuilt.
  --
  -- WHY THE SNAPSHOT STEP EXISTS (2026-09-11). Until now the scorecard read the two index views
  -- as deployed -- fitted on all of history, including the months being scored -- and hardcoded
  -- their names. Both are fixed by keeping the index as it stood each month in
  -- T_INTENT_IDX_HISTORY: the scorecard scores target month M with the newest snapshot taken
  -- strictly BEFORE M (leakage_flag = TRUE where none exists yet), and it iterates index_name from
  -- the registry, so a new index is a registry row and nothing else.
  --
  -- EVERY REGISTRY ROW IS SNAPSHOTTED, ACTIVE OR NOT. An inactive index must still be scored, or
  -- there is no evidence to promote it on; is_active decides only which set the scorecard treats
  -- as the baseline.
  --
  -- THE DYNAMIC SQL IS GUARDED, NOT TRUSTED. source_object and join_keys are strings a human wrote
  -- into a table. Before either reaches EXECUTE IMMEDIATE:
  --   * index_name must match ^[a-z][a-z0-9_]{0,63}$ and is passed as a query PARAMETER, never
  --     spliced into SQL text;
  --   * source_object must match ^V_INTENT_IDX_[A-Z_]+$ -- that character class cannot close a
  --     backtick, so it is the only registry string that is interpolated;
  --   * join_keys must be a CSV drawn from product_short_name, intent_key, intent_type,
  --     month_of_year; it must include month_of_year (the scorecard joins the calendar month
  --     strictly, so an index without it would score as absent everywhere -- a vacuous NEUTRAL)
  --     and at least one of the other three (a row NULL on all three is a wildcard that matches
  --     every observation; acceptance R18). The key names are never interpolated either: each
  --     allowed key maps to a fixed column expression or to CAST(NULL AS STRING).
  -- Anything else RAISEs with the index named. A registry typo therefore stops the run rather
  -- than snapshotting the wrong thing, and R16/R17 report the missing refresh.
  --
  -- THE SOURCE VIEW'S CONTRACT IS ENFORCED AT WRITE TIME, INSIDE THE INSERT. A declared key that
  -- arrives NULL, an index_value that is NULL or <= 0, a NULL support_clicks or month_of_year --
  -- each is wrapped in IF(..., ERROR(...)), so the INSERT fails atomically and the DELETE that
  -- preceded it leaves that index with NO rows for the month, which acceptance R17 reports. That
  -- is deliberate: a NULL key would silently match every observation for that index, and a
  -- non-positive index_value would make the scorecard's LN() fail or price a bid at zero.
  -- An index view that returns zero rows is also refused (n_written = 0), for the same reason as
  -- the month_of_year rule: an absent index scores 1.000 everywhere and looks NEUTRAL.
  --
  -- IDEMPOTENT WITHIN A MONTH. DELETE that index's rows for the current UTC month, then INSERT, so
  -- a rerun overwrites and the LAST run in a month is that month's snapshot. Two overlapping runs
  -- can still both pass their DELETE before either INSERTs; acceptance R19 (history unique on its
  -- grain) is what catches that.
  --
  -- WHY THE TABLES EXIST AT ALL. Both source views walk 18 target months across the whole
  -- observation set. Reading them live costs enough that this chain has already hit the
  -- on-demand CPU cap -- V_INTENT_CVR_CURVE ran ~27k CPU-seconds per scan and every consumer
  -- had to be repointed at T_INTENT_CVR_CURVE, and the Task 4 acceptance file was REJECTED by
  -- BigQuery at 97,066 CPU-seconds against a 33,500 ceiling. Acceptance checks R12/R13/R14/R16
  -- and R20 therefore read THESE TABLES, not the views. Do not repoint them.
  --
  -- PROMOTES NOTHING. This procedure does not write DE_INTENT_INDEX_REGISTRY and must never be
  -- given permission to: is_active is set by a human, the same contract as DE_SEARCH_TERM_INTENT,
  -- because the Coacher has twice made unreviewed bid changes that lost money.
  --
  -- THE ONE THING IT DOES WRITE OUTSIDE ITS OWN TABLES (2026-09-11): INTENT_CVR_CALIBRATION, and
  -- only inside a band. Spec 4.4 says the constant "will drift" and "is a threshold row with a
  -- refit query"; T_INTENT_BASE_TUNING has published the refit value (implied_calibration = 1 /
  -- bias for the shipped shape at the shipped prior) since 08-31, and ten days later it read
  -- 1.1717 against a stored 1.151 with nothing applying it. Step 4 closes that loop with the
  -- same automation-proposes / human-disposes contract as the registry: a step of at most
  -- INTENT_CVR_REFIT_MAX_STEP (0.10 = ten percent) is APPLIED and logged; a larger one is
  -- SUGGESTED -- suggested_value / suggestion_reason written, threshold_value NOT touched, logged
  -- -- and a human decides; a step smaller than INTENT_CVR_REFIT_MIN_STEP (0.0025, the dead-band
  -- added 2026-09-12 after the first scheduled run applied a +0.01% move) is UNCHANGED and the
  -- threshold row is not written at all, so its updated_at keeps meaning "when it last moved";
  -- no usable tuning row (missing, or under 200 predictions) is SKIPPED with the reason on the
  -- threshold row. Every outcome is one row in T_INTENT_REFIT_LOG.
  -- CONSEQUENCE, read before touching the band: V_INTENT_CVR_CURVE_SHADOW reads this constant
  -- LIVE, so an APPLIED step moves the shadow curve -- and T_INTENT_BID_BASE once the shadow is
  -- promoted -- on its next scan, by exactly the step. V_INTENT_CVR_CURVE, the curve serving bids
  -- today, does not read it (measured: zero references in its SQL), so until promotion a refit
  -- changes evidence, not bids. R02b pins the constant to the last APPLIED log value (seed 1.151
  -- before any), so a hand edit outside this procedure still fails the suite.
  --
  -- CADENCE. R16 fails the suite when either table is more than 8 days old, R17 when the current
  -- month has no snapshot, R22 when the refit log has no row from the last scoring. Since
  -- 2026-09-11 this runs from SP_REFRESH_SEARCH_TERM_INTENT, which SP_ORCHESTRATE_DAILY_REFRESH
  -- calls three times a day right after FACT_AMAZON_ADS is rebuilt -- so it is never stale, and
  -- it MUST still be re-run by hand after any change to the index views, the thresholds, or the
  -- curve that lands between orchestrator runs, or a promotion decision is made against evidence
  -- from before the change.
  --
  -- scored_at is stamped per table by its own CURRENT_TIMESTAMP(), so a partial run (the first
  -- statement succeeding and the second failing) leaves the two tables with different stamps and
  -- R16, which checks BOTH, reports it. That is deliberate: one shared timestamp variable would
  -- hide exactly that failure.
  -- ===========================================================================================

  DECLARE snap DATE DEFAULT DATE_TRUNC(CURRENT_DATE(), MONTH);   -- UTC, same clock as R17
  DECLARE cur_idx STRING;
  DECLARE keys ARRAY<STRING>;
  DECLARE bad_keys ARRAY<STRING>;
  DECLARE col_psn STRING;
  DECLARE col_ik STRING;
  DECLARE col_it STRING;
  DECLARE n_written INT64;

  -- ---- STEP 1: snapshot every registered index into T_INTENT_IDX_HISTORY ----------------------
  FOR reg IN (
    SELECT index_name, source_object, join_keys
    FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY`
    ORDER BY index_name
  ) DO
    SET cur_idx = reg.index_name;

    IF cur_idx IS NULL OR NOT REGEXP_CONTAINS(cur_idx, r'^[a-z][a-z0-9_]{0,63}$') THEN
      RAISE USING MESSAGE = FORMAT(
        'SP_SCORE_INTENT_INDEXES: registry index_name %T does not match ^[a-z][a-z0-9_]{0,63}$; refusing to snapshot it.',
        cur_idx);
    END IF;

    IF reg.source_object IS NULL OR NOT REGEXP_CONTAINS(reg.source_object, r'^V_INTENT_IDX_[A-Z_]+$') THEN
      RAISE USING MESSAGE = FORMAT(
        'SP_SCORE_INTENT_INDEXES: index %s declares source_object %T, which does not match ^V_INTENT_IDX_[A-Z_]+$; refusing to build SQL from it.',
        cur_idx, reg.source_object);
    END IF;

    SET keys = ARRAY(SELECT DISTINCT TRIM(k)
                     FROM UNNEST(SPLIT(COALESCE(reg.join_keys, ''), ',')) AS k
                     WHERE TRIM(k) != '');
    SET bad_keys = ARRAY(SELECT k FROM UNNEST(keys) AS k
                         WHERE k NOT IN ('product_short_name', 'intent_key', 'intent_type', 'month_of_year'));

    IF ARRAY_LENGTH(keys) = 0 OR ARRAY_LENGTH(bad_keys) > 0 THEN
      RAISE USING MESSAGE = FORMAT(
        'SP_SCORE_INTENT_INDEXES: index %s declares join_keys %T; unknown key(s) %T. Allowed: product_short_name, intent_key, intent_type, month_of_year (CSV).',
        cur_idx, reg.join_keys, bad_keys);
    END IF;

    IF 'month_of_year' NOT IN UNNEST(keys) THEN
      RAISE USING MESSAGE = FORMAT(
        'SP_SCORE_INTENT_INDEXES: index %s declares join_keys %T without month_of_year. The scorecard joins the calendar month strictly, so this index would score as absent (1.000) in every month -- a vacuous verdict. Not snapshotted.',
        cur_idx, reg.join_keys);
    END IF;

    IF (SELECT COUNT(*) FROM UNNEST(keys) AS k
        WHERE k IN ('product_short_name', 'intent_key', 'intent_type')) = 0 THEN
      RAISE USING MESSAGE = FORMAT(
        'SP_SCORE_INTENT_INDEXES: index %s declares join_keys %T with no key besides month_of_year. Its history rows would be NULL on every wildcard key and match every observation (acceptance R18). Not snapshotted.',
        cur_idx, reg.join_keys);
    END IF;

    -- Each declared key is copied through a NULL trap; an undeclared key is written NULL, which
    -- the scorecard reads as a wildcard. Fixed expressions -- nothing from join_keys is spliced in.
    SET col_psn = IF('product_short_name' IN UNNEST(keys),
      "IF(product_short_name IS NULL, ERROR(CONCAT('SP_SCORE_INTENT_INDEXES: index ', @idx, ' published a NULL product_short_name; the scorecard would read it as a wildcard')), product_short_name)",
      'CAST(NULL AS STRING)');
    SET col_ik = IF('intent_key' IN UNNEST(keys),
      "IF(intent_key IS NULL, ERROR(CONCAT('SP_SCORE_INTENT_INDEXES: index ', @idx, ' published a NULL intent_key; the scorecard would read it as a wildcard')), intent_key)",
      'CAST(NULL AS STRING)');
    SET col_it = IF('intent_type' IN UNNEST(keys),
      "IF(intent_type IS NULL, ERROR(CONCAT('SP_SCORE_INTENT_INDEXES: index ', @idx, ' published a NULL intent_type; the scorecard would read it as a wildcard')), intent_type)",
      'CAST(NULL AS STRING)');

    DELETE FROM `onyga-482313.OI.T_INTENT_IDX_HISTORY`
    WHERE snapshot_month = snap AND index_name = cur_idx;

    EXECUTE IMMEDIATE FORMAT("""
      INSERT INTO `onyga-482313.OI.T_INTENT_IDX_HISTORY`
        (snapshot_month, snapshot_at, index_name,
         product_short_name, intent_key, intent_type, month_of_year,
         index_value, support_clicks)
      SELECT @snap, CURRENT_TIMESTAMP(), @idx,
             %s,
             %s,
             %s,
             IF(month_of_year IS NULL,
                ERROR(CONCAT('SP_SCORE_INTENT_INDEXES: index ', @idx, ' published a NULL month_of_year')),
                month_of_year),
             IF(index_value > 0, index_value,
                ERROR(CONCAT('SP_SCORE_INTENT_INDEXES: index ', @idx, ' published a NULL or non-positive index_value; contract 2 of the registry'))),
             IF(support_clicks IS NULL,
                ERROR(CONCAT('SP_SCORE_INTENT_INDEXES: index ', @idx, ' published a NULL support_clicks; contract 3 of the registry')),
                support_clicks)
      FROM `onyga-482313.OI.%s`
    """, col_psn, col_ik, col_it, reg.source_object)
    USING snap AS snap, cur_idx AS idx;

    SET n_written = (SELECT COUNT(*) FROM `onyga-482313.OI.T_INTENT_IDX_HISTORY`
                     WHERE snapshot_month = snap AND index_name = cur_idx);
    IF n_written = 0 THEN
      RAISE USING MESSAGE = FORMAT(
        'SP_SCORE_INTENT_INDEXES: index %s (%s) returned zero rows; an empty index would score as absent everywhere. Not scored.',
        cur_idx, reg.source_object);
    END IF;
  END FOR;

  -- ---- STEP 2: the scorecard, now read off the history ---------------------------------------
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_INTENT_INDEX_SCORECARD` AS
  SELECT CURRENT_TIMESTAMP() AS scored_at, *
  FROM `onyga-482313.OI.V_INTENT_INDEX_SCORECARD`;

  -- ---- STEP 3: the base tuning grid ----------------------------------------------------------
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_INTENT_BASE_TUNING` AS
  SELECT CURRENT_TIMESTAMP() AS scored_at, *
  FROM `onyga-482313.OI.V_INTENT_BASE_TUNING`;

  -- ---- STEP 4: bounded refit of INTENT_CVR_CALIBRATION ---------------------------------------
  -- Its own block so it can DECLARE its own variables (BigQuery scripting allows DECLARE only at
  -- the head of a block). Reads the tuning row for the shape the shadow curve ships
  -- (nested_1_2_3_6_12, spec 4.4) at the prior the shadow reads (INTENT_CVR_BASE_PRIOR_CLICKS),
  -- so a change to the prior re-targets the refit on its own. The arithmetic: step = implied /
  -- current - 1; UNCHANGED if |step| < INTENT_CVR_REFIT_MIN_STEP (or implied rounds to current at
  -- the stored 4 dp), APPLIED if |step| <= INTENT_CVR_REFIT_MAX_STEP, SUGGESTED beyond it, SKIPPED
  -- if the tuning row is missing or rests on fewer than 200 predictions. Every path writes
  -- T_INTENT_REFIT_LOG.
  -- The threshold row is addressed by the full key the readers use -- strategy_id INTENT,
  -- coach_mode GUARDIAN, product_family NULL -- because a row under any other mode is a
  -- different threshold to every view that reads this one.
  BEGIN
    DECLARE tune_shape STRING  DEFAULT 'nested_1_2_3_6_12';
    DECLARE tune_k     FLOAT64;
    DECLARE cal_cur    FLOAT64;
    DECLARE max_step   FLOAT64;
    DECLARE min_step   FLOAT64;
    DECLARE cal_new    FLOAT64;
    DECLARE cal_n      INT64;
    DECLARE step_pct   FLOAT64;
    DECLARE new_val    FLOAT64;
    DECLARE act        STRING;
    DECLARE why        STRING;

    SET tune_k = (SELECT MAX(IF(threshold_key = 'INTENT_CVR_BASE_PRIOR_CLICKS', threshold_value, NULL))
                  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
                  WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL);
    SET cal_cur = (SELECT MAX(IF(threshold_key = 'INTENT_CVR_CALIBRATION', threshold_value, NULL))
                   FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
                   WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL);
    SET max_step = (SELECT MAX(IF(threshold_key = 'INTENT_CVR_REFIT_MAX_STEP', threshold_value, NULL))
                    FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
                    WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL);

    SET min_step = (SELECT MAX(IF(threshold_key = 'INTENT_CVR_REFIT_MIN_STEP', threshold_value, NULL))
                    FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
                    WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL);

    IF tune_k IS NULL OR cal_cur IS NULL OR max_step IS NULL OR min_step IS NULL THEN
      RAISE USING MESSAGE = FORMAT(
        'SP_SCORE_INTENT_INDEXES step 4: threshold missing under strategy_id INTENT / coach_mode GUARDIAN / product_family NULL (k_base %T, calibration %T, max_step %T, min_step %T). Refusing to refit against an unknown band.',
        tune_k, cal_cur, max_step, min_step);
    END IF;

    -- MAX() over zero rows is NULL, not an error; a missing tuning row is a SKIPPED, not a crash.
    SET cal_new = (SELECT MAX(implied_calibration) FROM `onyga-482313.OI.T_INTENT_BASE_TUNING`
                   WHERE shape = tune_shape AND k_base = tune_k);
    SET cal_n   = (SELECT MAX(n_predictions) FROM `onyga-482313.OI.T_INTENT_BASE_TUNING`
                   WHERE shape = tune_shape AND k_base = tune_k);
    SET new_val = cal_cur;

    IF cal_new IS NULL OR cal_n IS NULL OR cal_n < 200 THEN
      SET act = 'SKIPPED';
      SET why = IF(cal_new IS NULL OR cal_n IS NULL,
                   FORMAT('REFIT_SKIPPED: no row for shape %s at k_base %.0f in T_INTENT_BASE_TUNING', tune_shape, tune_k),
                   FORMAT('REFIT_SKIPPED: shape %s at k_base %.0f rests on %d predictions (< 200)', tune_shape, tune_k, cal_n));
      UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS`
      SET suggestion_reason = why, suggested_at = CURRENT_DATETIME()
      WHERE strategy_id = 'INTENT' AND threshold_key = 'INTENT_CVR_CALIBRATION'
        AND coach_mode = 'GUARDIAN' AND product_family IS NULL;
    ELSE
      SET step_pct = (cal_new / cal_cur - 1.0) * 100.0;
      IF ABS(cal_new / cal_cur - 1.0) < min_step OR ROUND(cal_new, 4) = cal_cur THEN
        -- DEAD-BAND (2026-09-12). Without it every run applied a +0.01% move: a few hours of new
        -- clicks shift implied by ~0.0001, and the log filled with APPLIED rows that meant nothing
        -- while updated_at on the threshold row stopped meaning "when it last moved". Below
        -- INTENT_CVR_REFIT_MIN_STEP (0.0025 = a quarter percent) the step is recorded and not
        -- applied. Ordinary drift accumulates and crosses the band in about a week; it is then
        -- applied as one honest move.
        SET act = 'UNCHANGED';
        SET why = FORMAT('implied %.4f is %+.3f%% from current %.4f, inside the %.2f%% dead-band (INTENT_CVR_REFIT_MIN_STEP); nothing to apply',
                         cal_new, step_pct, cal_cur, min_step * 100.0);
      ELSEIF ABS(cal_new / cal_cur - 1.0) <= max_step THEN
        SET act = 'APPLIED';
        SET new_val = ROUND(cal_new, 4);
        SET why = FORMAT('AUTO_APPLIED within %.0f%% band from T_INTENT_BASE_TUNING (%s @ k_base %.0f, %d predictions): %.4f -> %.4f (%+.2f%%)',
                         max_step * 100.0, tune_shape, tune_k, cal_n, cal_cur, new_val, step_pct);
        UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS`
        SET threshold_value   = new_val,
            updated_at        = CURRENT_DATETIME(),
            updated_by        = 'SP_SCORE_INTENT_INDEXES',
            source            = 'AUTO_REFIT',
            suggested_value   = cal_new,
            suggested_at      = CURRENT_DATETIME(),
            suggestion_reason = why
        WHERE strategy_id = 'INTENT' AND threshold_key = 'INTENT_CVR_CALIBRATION'
          AND coach_mode = 'GUARDIAN' AND product_family IS NULL;
      ELSE
        SET act = 'SUGGESTED';
        SET why = FORMAT('OUT OF BAND (%+.2f%%, band %.0f%%), human decision required: T_INTENT_BASE_TUNING implies %.4f (%s @ k_base %.0f, %d predictions); current %.4f left untouched',
                         step_pct, max_step * 100.0, cal_new, tune_shape, tune_k, cal_n, cal_cur);
        UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS`
        SET suggested_value   = cal_new,
            suggested_at      = CURRENT_DATETIME(),
            suggestion_reason = why
        WHERE strategy_id = 'INTENT' AND threshold_key = 'INTENT_CVR_CALIBRATION'
          AND coach_mode = 'GUARDIAN' AND product_family IS NULL;
      END IF;
    END IF;

    INSERT INTO `onyga-482313.OI.T_INTENT_REFIT_LOG`
      (refit_at, shape, k_base, previous_value, implied_value, new_value, step_pct, max_step,
       n_predictions, action, reason)
    VALUES
      (CURRENT_TIMESTAMP(), tune_shape, tune_k, cal_cur, cal_new, new_val, step_pct, max_step,
       cal_n, act, why);
  END;
END;
