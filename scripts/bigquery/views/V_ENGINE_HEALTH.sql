-- =============================================
-- V_ENGINE_HEALTH — the engine's standing self-check, one row per check (2026-08-16, Task 3.3).
-- Spec: architecture/ENGINE_HEALTH.md.
--
-- (Ori 2026-08-15: the engine "should always check himself.") Every check reads SMALL tables
-- except the scorecard (ceiling view), which appears exactly once — the shared `sc` CTE below,
-- read by BOTH #6 and #7. Statuses are the VIEW's — GREEN / AMBER / RED / INFO — with the
-- threshold printed beside the measurement so a reader never has to guess what "bad" means.
-- A quiet board is the goal state, not a malfunction.
-- v27.104 (2026-08-22): c12 loser_kill_clause + c13 state_floor_resolution (KEYWORD_STATE.md).
-- v27.127 (2026-08-23): c14–c22, the family seat register's checks (FAMILY_SEAT_REGISTER.md,
-- "Health"). They read the register's once-per-pass IMAGE (T_FAMILY_SEAT_REGISTER, the table the
-- morning surfaces read), the seat ledger, the keyword-state snapshot, the change log, the holdout
-- table and LOG_PIPELINE_RUNS — never the live register view (tens of seconds) and never a
-- ceiling view. Two are REPORTS (INFO) by design: the overdue-appointment counter, whose cause is
-- upstream of the register (the park-era settle_due, diagnosed, not applied), and the days-since
-- counter, which is a clock on the orchestrator (New York), not a verdict on the ledger.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ENGINE_HEALTH` AS
WITH pf AS (SELECT * FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`),
ks AS (SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
-- ONE shared scorecard scan (review 2026-08-16, planner safety): c6 and c7 both read THIS CTE.
-- Before this, c7 read V_MANUAL_DIVERGENCE, which embeds its own full V_CHANGE_SCORECARD scan —
-- two copies of the ceiling view inlined into one statement.
sc AS (
  SELECT source, verdict, change_date, change_id, campaign_id, keyword_id, action_group,
         SAFE_CAST(new_value AS FLOAT64) AS new_val
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD`
),

c1 AS (  -- contradiction rate: EXCLUDE share of the day's instructions
  SELECT 'contradiction_rate' AS check_name,
    ROUND(SAFE_DIVIDE(COUNTIF(verdict = 'EXCLUDE'), COUNT(*)) * 100, 1) AS measured,
    'EXCLUDE % of instructions · amber > 5, red > 15 (iteration-6 found 29.9 unGated)' AS threshold,
    CASE WHEN SAFE_DIVIDE(COUNTIF(verdict = 'EXCLUDE'), COUNT(*)) > 0.15 THEN 'RED'
         WHEN SAFE_DIVIDE(COUNTIF(verdict = 'EXCLUDE'), COUNT(*)) > 0.05 THEN 'AMBER'
         ELSE 'GREEN' END AS status,
    CONCAT(CAST(COUNTIF(verdict = 'EXCLUDE') AS STRING), ' of ', CAST(COUNT(*) AS STRING),
           ' instructions excluded by ownership — high is not broken (the gate is WORKING) but says the engines overlap a lot') AS detail
  FROM pf
),
c2 AS (  -- single voice: no key+lever with two live instructions
  -- v27.72: the key mirrors SP_ENGINE_PREFLIGHT's key_id — NEGATE rows key on the TERM (they
  -- have no keyword_id; without the term, every negate in a campaign is one false "overlap")
  SELECT 'ownership_overlaps',
    CAST(COUNT(*) AS FLOAT64),
    'keys with >1 non-EXCLUDE instruction · red > 0',
    IF(COUNT(*) > 0, 'RED', 'GREEN'),
    'one key, one lever, one voice — the preflight assertion, standing'
  FROM (SELECT campaign_id,
               IF(grain = 'NEGATE', CONCAT('term|', LOWER(TRIM(COALESCE(target_text, '')))),
                  COALESCE(keyword_id, '')) k,
               lever
        FROM pf GROUP BY 1, 2, 3 HAVING COUNTIF(verdict != 'EXCLUDE') > 1)
),
c3 AS (  -- state invariant 1
  SELECT 'state_duplicate', CAST(COUNT(*) AS FLOAT64),
    'keywords in two states · red > 0', IF(COUNT(*) > 0, 'RED', 'GREEN'),
    'V_KEYWORD_STATE invariant 1'
  FROM (SELECT campaign_id, keyword_id FROM ks GROUP BY 1, 2 HAVING COUNT(*) > 1)
),
c4 AS (  -- state invariant 2
  SELECT 'missing_appointment',
    CAST(COUNTIF(next_check_date IS NULL AND state != 'DEAD') AS FLOAT64),
    'non-DEAD keywords with no next appointment · red > 0',
    IF(COUNTIF(next_check_date IS NULL AND state != 'DEAD') > 0, 'RED', 'GREEN'),
    'V_KEYWORD_STATE invariant 2 — every keyword has a date something re-judges it'
  FROM ks
),
c5 AS (  -- overdue appointments (found on the state machine's first day)
  SELECT 'overdue_appointments',
    CAST(COUNTIF(next_check_date < CURRENT_DATE('America/Los_Angeles') AND state != 'DEAD') AS FLOAT64),
    'appointments in the past · amber > 50 (judgments due that nothing has re-run)',
    CASE WHEN COUNTIF(next_check_date < CURRENT_DATE('America/Los_Angeles') AND state != 'DEAD') > 50
         THEN 'AMBER' ELSE 'GREEN' END,
    CONCAT('oldest: ', CAST(MIN(IF(next_check_date < CURRENT_DATE('America/Los_Angeles'), next_check_date, NULL)) AS STRING))
  FROM ks
),
c6 AS (  -- outcome mix, trailing settled window (reads the shared sc scan — the ceiling view's one appearance)
  SELECT 'scorecard_reversed_share',
    ROUND(SAFE_DIVIDE(COUNTIF(verdict = 'REVERSED'), NULLIF(COUNTIF(verdict != 'INSUFFICIENT'), 0)) * 100, 1),
    'REVERSED % of judged, changes from the last 42d · amber > 35 (measured era baseline 46)',
    CASE WHEN SAFE_DIVIDE(COUNTIF(verdict = 'REVERSED'), NULLIF(COUNTIF(verdict != 'INSUFFICIENT'), 0)) > 0.35
         THEN 'AMBER' ELSE 'GREEN' END,
    CONCAT(CAST(COUNTIF(verdict != 'INSUFFICIENT') AS STRING), ' judged · ',
           CAST(COUNTIF(verdict = 'INSUFFICIENT') AS STRING), ' too thin to judge')
  FROM sc
  WHERE change_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 42 DAY)
),
c7 AS (  -- the human-vs-model ledger: MANUAL_BETTER rows demand a model fix
  -- PLANNER SAFETY (review 2026-08-16): this DUPLICATES V_MANUAL_DIVERGENCE's kind logic BY
  -- DESIGN instead of reading that view — the view embeds its own full V_CHANGE_SCORECARD scan,
  -- and stacking it beside c6 put two copies of the ceiling view in one statement. Kind here =
  -- OVERRODE: a same-day non-EXCLUDE proposal exists on the key+lever (owning engine first, the
  -- view's priority order) and the hand's value diverges > 5% from it (a proposal carrying no
  -- value diverges by definition — the view's ELSE). MANUAL_BETTER = OVERRODE + CONFIRMED.
  -- Both definitions are owned by architecture/MANUAL_DIVERGENCE.md — change them together.
  SELECT 'manual_better_unresolved',
    CAST(COUNT(DISTINCT s.change_id) AS FLOAT64),
    'OVERRODE changes where the hand beat the model · INFO until resolution tracking exists',
    IF(COUNT(DISTINCT s.change_id) > 0, 'AMBER', 'GREEN'),
    'doctrine: each one ends as a threshold change or a documented disagreement (MANUAL_DIVERGENCE.md)'
  FROM sc s
  JOIN (
    -- v27.72: NEGATE rows key on the term and are OVERRODE-exempt (a negate has no value to
    -- diverge from) — the lever filter below keeps this check to the value levers.
    SELECT snapshot_date, campaign_id, COALESCE(keyword_id, '') AS kid,
           CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever,
           suggested_bid, suggested_budget
    FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    WHERE COALESCE(verdict, '') != 'EXCLUDE' AND grain != 'NEGATE'
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY snapshot_date, campaign_id, COALESCE(keyword_id, ''),
                   CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END
      ORDER BY CASE engine WHEN 'LOW_STOCK' THEN 1 WHEN 'LAUNCH' THEN 2 WHEN 'OOB' THEN 3
                           WHEN 'REVERDICT' THEN 4 WHEN 'LIFT' THEN 5 WHEN 'COACH' THEN 6 ELSE 9 END) = 1
  ) p ON p.snapshot_date = s.change_date
     AND p.campaign_id = s.campaign_id
     AND p.kid = COALESCE(s.keyword_id, '')
     AND p.lever = IF(s.action_group IN ('BUDGET_UP', 'BUDGET_DOWN'), 'BUDGET', 'BID')
  WHERE s.source = 'MANUAL' AND s.verdict = 'CONFIRMED'
    AND (COALESCE(p.suggested_bid, p.suggested_budget) IS NULL
         OR ABS(COALESCE(s.new_val, 0) - COALESCE(p.suggested_bid, p.suggested_budget))
            > 0.05 * COALESCE(p.suggested_bid, p.suggested_budget))
),
c8 AS (  -- snapshot freshness: the memory must not silently stop
  SELECT 'snapshot_freshness',
    CAST(DATE_DIFF(CURRENT_DATE('America/Los_Angeles'),
                   (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`), DAY) AS FLOAT64),
    'days since the last proposal snapshot · red > 2',
    IF(DATE_DIFF(CURRENT_DATE('America/Los_Angeles'),
                 (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`), DAY) > 2, 'RED', 'GREEN'),
    'FACT_ENGINE_PROPOSALS — without the memory, nothing learns'
),
c9 AS (  -- no-op leakage: engines carry their own guards; the gate counts what still leaks
  SELECT 'noop_leakage',
    CAST(COUNTIF(verdict_reason LIKE 'no-op%') AS FLOAT64),
    'instructions that were no-ops at the gate · amber > 10 (ladder thrash)',
    IF(COUNTIF(verdict_reason LIKE 'no-op%') > 10, 'AMBER', 'GREEN'),
    'v27.29/v27.46 no-op guards should catch these upstream; the gate is the belt'
  FROM pf
),
c10 AS (  -- v27.101: view-body headroom — no view may creep up on BigQuery's hard ceiling unseen
  -- V_KEYWORD_LIFT reached the ceiling with a fraction of a percent to spare and nothing measured
  -- it, so the discovery came from a change that would not fit. Past the ceiling a view can no
  -- longer be edited at all, only migrated, and the migration lands under whatever deadline
  -- happens to expose it. This check fires while the fix is still an edit.
  --   Declared constants: ceiling 262,144 characters (BigQuery's maximum view query length),
  --   amber at 70% of it, red at 85%.
  -- The number is CHARACTERS, matching LENGTH() and BigQuery's own limit — not bytes, which
  -- overstate any view whose commentary carries non-ASCII text.
  -- Pre-deploy twin (measures the repo files, before BigQuery ever sees them):
  --   python3 scripts/bigquery/check_view_body_size.py
  SELECT 'view_body_headroom',
    ROUND(MAX(LENGTH(view_definition)) / 262144 * 100, 2),
    'largest view body as % of the 262,144-character ceiling · amber > 70, red > 85',
    CASE WHEN MAX(LENGTH(view_definition)) > 262144 * 0.85 THEN 'RED'
         WHEN MAX(LENGTH(view_definition)) > 262144 * 0.70 THEN 'AMBER'
         ELSE 'GREEN' END,
    CONCAT('largest is ',
           ARRAY_AGG(table_name ORDER BY LENGTH(view_definition) DESC LIMIT 1)[OFFSET(0)],
           ' — comment markers in column 0 cost nothing (the deploy strips them), indented ones ',
           'are shipped to BigQuery and charged against the ceiling')
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
),
c11 AS (  -- v27.102: one keyword, one price, on the day's EXPORTABLE plan
  -- WHY THIS IS NOT c2. c2 reads T_ENGINE_PREFLIGHT and counts non-EXCLUDE ROWS — it asks whether
  -- the gate resolved the contention. This reads FACT_ENGINE_PROPOSALS, the table every consumer
  -- downstream actually reads, and counts distinct exportable PRICES. The difference is the whole
  -- point: the gate can resolve a contention perfectly and the verdict can still fail to reach the
  -- reader — because the stamp-back join missed the row, because a row was skipped by the gate and
  -- left unjudged in the table, or because a consumer never asked for the verdict at all. That
  -- last one is what happened: the morning brief printed three prices for one keyword out of a
  -- table the gate had already resolved, and c2 was GREEN the whole time.
  -- A hand-built bulksheet is copied off that list, so two prices on one keyword is not an
  -- untidiness — it is the account's bid being decided by which line the eye landed on.
  -- COUNT(DISTINCT) ignores NULL, so negates (no value) can never trip this.
  SELECT 'plan_price_ambiguity',
    CAST(COUNT(*) AS FLOAT64),
    'keys whose exportable plan carries >1 distinct price today · red > 0',
    IF(COUNT(*) > 0, 'RED', 'GREEN'),
    'one keyword, one lever, one price — measured on the proposal table the consumers read, not on the gate table, so a verdict that never reached a reader is visible here'
  FROM (
    SELECT campaign_id,
           IF(grain = 'NEGATE', CONCAT('term|', LOWER(TRIM(COALESCE(target_text, '')))),
              COALESCE(keyword_id, '')) AS k,
           CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever
    FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)
      -- the exportable set, defined exactly as V_DAILY_BRIEF defines it: a held row is not an
      -- instruction, and an unstamped row fails open into the plan
      AND hold_source IS NULL
      AND COALESCE(verdict, 'GO') != 'EXCLUDE'
    GROUP BY 1, 2, 3
    HAVING COUNT(DISTINCT COALESCE(suggested_bid, suggested_budget)) > 1
  )
),
c12 AS (  -- v27.104: THE KILL CLAUSE — a LOSER is only ever a keyword that failed AT its floor
  -- (ruling 4 + Ori's floor ruling, 2026-08-22). The SP asserts it by construction; this is the
  -- belt: a LOSER whose probation has not elapsed, or whose bid is not at its own channel floor,
  -- or which clears its family bar, is a phantom kill and must never reach the reprice book.
  SELECT 'loser_kill_clause',
    CAST(COUNTIF(state = 'LOSER'
                 AND NOT (COALESCE(probation_elapsed, FALSE) AND COALESCE(at_floor, FALSE)
                          AND COALESCE(settled_roas90, 0) < family_bar)) AS FLOAT64),
    'LOSERs not (probation elapsed AND bid at its floor AND below bar) · red > 0',
    IF(COUNTIF(state = 'LOSER'
               AND NOT (COALESCE(probation_elapsed, FALSE) AND COALESCE(at_floor, FALSE)
                        AND COALESCE(settled_roas90, 0) < family_bar)) > 0, 'RED', 'GREEN'),
    CONCAT(CAST(COUNTIF(state = 'LOSER') AS STRING), ' LOSERs · ',
           CAST(COUNTIF(state = 'FLOOR_PROBATION') AS STRING), ' on floor probation · ',
           'KEYWORD_STATE.md "The floors" — a keyword is only ever killed at its floor, after its probation')
  FROM ks
),
c13 AS (  -- v27.104: every judged row carries a resolved floor from the ONE definition
  -- (FN_BID_FLOOR via V_BID_FLOOR). A NULL floor means a private constant crept back in, or the
  -- DIM_KEYWORD -> ad group resolution broke; *_NO_ADGROUP sources are the fallback, counted here
  -- as detail so a silent drift to the conservative $0.25 is visible.
  SELECT 'state_floor_resolution',
    CAST(COUNTIF(bid_floor IS NULL AND state IN ('AT_BAR', 'REPRICE', 'FLOOR_PROBATION', 'LOSER')) AS FLOAT64),
    'priced states (AT_BAR/REPRICE/FLOOR_PROBATION/LOSER) with no floor · red > 0',
    IF(COUNTIF(bid_floor IS NULL AND state IN ('AT_BAR', 'REPRICE', 'FLOOR_PROBATION', 'LOSER')) > 0, 'RED', 'GREEN'),
    CONCAT(CAST(COUNTIF(bid_floor_source LIKE '%_NO_ADGROUP') AS STRING),
           ' rows resolved on channel alone (ad group unresolved) · sources: ',
           COALESCE((SELECT STRING_AGG(CONCAT(src, ' ', CAST(n AS STRING)), ', ' ORDER BY n DESC)
                     FROM (SELECT bid_floor_source src, COUNT(*) n FROM ks GROUP BY 1)), 'none'))
  FROM ks
),
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- c14–c22: the family seat register (v27.127, FAMILY_SEAT_REGISTER.md "Health"). Sources are the
-- pass IMAGE and small tables only. `sr` is T_FAMILY_SEAT_REGISTER — what the brief, the Weekly
-- Run and the cube read — so a check here judges the same image a reader saw, not a live view that
-- may already have moved on (the live view re-anchors the moment the ads watermark advances; the
-- ledger moves only when SP_MAINTAIN_FAMILY_SEATS runs — see "When B04 is valid" in the SOP).
-- Tolerances: $0.01 on a reconciliation, the acceptance suite's own (B01/B02) — an aggregate
-- rendered to the cent against a sum of per-row costs each rounded on its own row (ruling R-m:
-- one cent of aggregate-vs-components drift is a display fact). bid_tol 0.005 mirrors the view's.
-- ───────────────────────────────────────────────────────────────────────────────────────────
sr AS (SELECT * FROM `onyga-482313.OI.T_FAMILY_SEAT_REGISTER`),
sl AS (SELECT * FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`),
sl_open AS (SELECT * FROM sl WHERE closed_on IS NULL),
c14 AS (  -- the register reconciles: categories = the family's spend; seats + leaks + gaps = the bad side
  SELECT 'seat_reconciliation_gap',
    CAST(COUNT(*) AS FLOAT64),
    'FAMILY rows (any horizon) whose CATEGORY rows miss the spend, or whose SEAT(20%)+LEAK+GAP miss the bad side today, by more than $0.01 · red > 0',
    IF(COUNT(*) > 0, 'RED', 'GREEN'),
    CONCAT('largest gap found $', FORMAT('%.4f', COALESCE(MAX(gap), 0)), '/day on the pass image (T_FAMILY_SEAT_REGISTER, as of ',
           COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM sr), 'no image'), ') — the acceptance suite (B01/B02) holds the live view to the same cent')
  FROM (
    SELECT f.family, f.horizon,
           GREATEST(ABS(COALESCE(c.s, 0) - f.spend_horizon_per_day),
                    IF(f.horizon = 'today', ABS(COALESCE(b.s, 0) - f.bad_side_per_day), 0)) AS gap
    FROM sr f
    LEFT JOIN (SELECT family, horizon, SUM(cost_per_day) AS s FROM sr WHERE row_type = 'CATEGORY' GROUP BY 1, 2) c
           ON c.family = f.family AND c.horizon = f.horizon
    LEFT JOIN (SELECT family, SUM(cost_per_day) AS s FROM sr
               WHERE (row_type = 'SEAT' AND side = '20') OR row_type IN ('LEAK', 'GAP') GROUP BY 1) b
           ON b.family = f.family AND f.horizon = 'today'
    WHERE f.row_type = 'FAMILY'
  )
  WHERE gap > 0.01
),
c15 AS (  -- the ledger's invariants — the ones a second, non-idempotent admission or a re-insert on one snapshot would break
  -- Idempotence PROPER is proven by two runs with one fingerprint (the query in the SOP, "Idempotence");
  -- a view cannot run the procedure twice, so this is the necessary condition, standing every day.
  SELECT 'seat_ledger_idempotence',
    CAST((SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id, opened_on FROM sl GROUP BY 1, 2, 3, 4 HAVING COUNT(*) > 1))
       + (SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id FROM sl_open GROUP BY 1, 2, 3 HAVING COUNT(*) > 1))
       + (SELECT COUNT(*) FROM (SELECT family, seat_no FROM sl_open GROUP BY 1, 2 HAVING COUNT(*) > 1))
       + (SELECT COUNTIF(seat_no < 1 OR closed_on < opened_on OR opened_on > (SELECT MAX(snapshot_date) FROM ks)) FROM sl) AS FLOAT64),
    'duplicate occupancy keys + keys with two open rows + two keywords on one open number + malformed rows · red > 0',
    IF((SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id, opened_on FROM sl GROUP BY 1, 2, 3, 4 HAVING COUNT(*) > 1))
       + (SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id FROM sl_open GROUP BY 1, 2, 3 HAVING COUNT(*) > 1))
       + (SELECT COUNT(*) FROM (SELECT family, seat_no FROM sl_open GROUP BY 1, 2 HAVING COUNT(*) > 1))
       + (SELECT COUNTIF(seat_no < 1 OR closed_on < opened_on OR opened_on > (SELECT MAX(snapshot_date) FROM ks)) FROM sl) > 0, 'RED', 'GREEN'),
    CONCAT((SELECT CAST(COUNT(*) AS STRING) FROM sl_open), ' open seats · ', (SELECT CAST(COUNT(*) AS STRING) FROM sl), ' occupancies · ',
           'a second run on the same snapshot must close, reopen and admit nothing — the proof is two runs, one fingerprint (SOP)')
),
c16 AS (  -- every occupant on the image carries its number, once; numbers agree with the ledger
  -- RED only for what the image itself gets wrong (an unnumbered seat, a number held twice).
  -- Image-vs-ledger disagreement is AMBER: between orchestrator step 20.8b (the ledger) and
  -- SP_REFRESH_CUBE_TABLES step 0c (the image) of one pass the two are legitimately apart.
  SELECT 'seat_every_occupant_numbered',
    CAST((SELECT COUNTIF(seat_no IS NULL) FROM sr WHERE row_type = 'SEAT')
       + (SELECT COUNT(*) FROM (SELECT family, seat_no FROM sr WHERE row_type = 'SEAT' AND seat_no IS NOT NULL GROUP BY 1, 2 HAVING COUNT(*) > 1)) AS FLOAT64),
    'SEAT rows on the image with no seat number, or a number held by two seats of one family · red > 0; ledger disagreements amber > 0 (transient inside a pass)',
    CASE WHEN (SELECT COUNTIF(seat_no IS NULL) FROM sr WHERE row_type = 'SEAT')
            + (SELECT COUNT(*) FROM (SELECT family, seat_no FROM sr WHERE row_type = 'SEAT' AND seat_no IS NOT NULL GROUP BY 1, 2 HAVING COUNT(*) > 1)) > 0 THEN 'RED'
         WHEN (SELECT COUNT(*) FROM sr s LEFT JOIN sl_open l ON l.family = s.family AND l.campaign_id = s.campaign_id AND l.keyword_id = s.keyword_id
               WHERE s.row_type = 'SEAT' AND (l.seat_no IS NULL OR l.seat_no != s.seat_no))
            + (SELECT COUNT(*) FROM sl_open l LEFT JOIN sr s ON s.row_type = 'SEAT' AND s.family = l.family AND s.campaign_id = l.campaign_id AND s.keyword_id = l.keyword_id
               WHERE s.keyword_id IS NULL) > 0 THEN 'AMBER'
         ELSE 'GREEN' END,
    CONCAT((SELECT CAST(COUNT(*) AS STRING) FROM sr WHERE row_type = 'SEAT'), ' seats on the image · ',
           CAST((SELECT COUNT(*) FROM sr s LEFT JOIN sl_open l ON l.family = s.family AND l.campaign_id = s.campaign_id AND l.keyword_id = s.keyword_id
                 WHERE s.row_type = 'SEAT' AND (l.seat_no IS NULL OR l.seat_no != s.seat_no)) AS STRING), ' image seats the ledger numbers differently or not at all · ',
           CAST((SELECT COUNT(*) FROM sl_open l LEFT JOIN sr s ON s.row_type = 'SEAT' AND s.family = l.family AND s.campaign_id = l.campaign_id AND s.keyword_id = l.keyword_id
                 WHERE s.keyword_id IS NULL) AS STRING), ' open ledger rows with no seat on the image (compare the last SP_MAINTAIN_FAMILY_SEATS in LOG_PIPELINE_RUNS against the image as_of before calling it a defect)')
),
c17 AS (  -- a launch family is never seated, never judged (house rule 12; V_BOOK_ASSIGNMENT decides the book)
  SELECT 'seat_no_launch_seat',
    CAST((SELECT COUNT(*) FROM sl l LEFT JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` b USING (family) WHERE COALESCE(b.book, '') != 'HARVEST')
       + (SELECT COUNT(*) FROM sr s JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` b USING (family)
          WHERE b.book != 'HARVEST' AND s.row_type IN ('FAMILY', 'SEAT', 'OPEN_SEAT', 'LEAK', 'GAP', 'ABSORB')) AS FLOAT64),
    'ledger rows (open or closed) outside the HARVEST book + image rows judging a non-HARVEST family · red > 0',
    IF((SELECT COUNT(*) FROM sl l LEFT JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` b USING (family) WHERE COALESCE(b.book, '') != 'HARVEST')
       + (SELECT COUNT(*) FROM sr s JOIN `onyga-482313.OI.V_BOOK_ASSIGNMENT` b USING (family)
          WHERE b.book != 'HARVEST' AND s.row_type IN ('FAMILY', 'SEAT', 'OPEN_SEAT', 'LEAK', 'GAP', 'ABSORB')) > 0, 'RED', 'GREEN'),
    'launch (INVEST) families appear on the register as REFERENCE rows only — never a FAMILY read, never a seat, never a move'
),
c18 AS (  -- house rule 13: a holdout campaign is on no sheet from its eligible_from
  -- Reads the register's two books in the change log by batch prefix (seat_moves_ / reprice_book_)
  -- at EVERY upload status — a superseded book was still a sheet built with a holdout row on it.
  SELECT 'seat_holdout_row_on_sheet',
    CAST(COUNT(*) AS FLOAT64),
    'change-log rows of the seat books (seat_moves_* / reprice_book_*) naming a HOLDOUT-arm campaign, built on or after its eligible_from · red > 0',
    IF(COUNT(*) > 0, 'RED', 'GREEN'),
    CONCAT(CAST(COUNTIF(c.upload_status = 'PENDING_UPLOAD') AS STRING), ' pending · ',
           CAST(COUNTIF(c.upload_status IS NULL) AS STRING), ' applied · ',
           CAST(COUNTIF(c.upload_status NOT IN ('PENDING_UPLOAD') AND c.upload_status IS NOT NULL) AS STRING), ' labelled · ',
           'the arm starts ', COALESCE((SELECT CAST(MIN(eligible_from) AS STRING) FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` WHERE arm = 'HOLDOUT'), 'never'),
           ' — before it a holdout campaign may sit on a book; from it no generator may write one')
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` c
  JOIN `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` h
    ON h.unit_id = c.campaign_id AND h.arm = 'HOLDOUT'
  WHERE (c.batch_id LIKE 'seat_moves_%' OR c.batch_id LIKE 'reprice_book_%')
    AND DATE(c.applied_at, 'America/Los_Angeles') >= h.eligible_from
),
c19 AS (  -- ruling R-f: a "raise" is only ever to a price ABOVE the live bid
  SELECT 'seat_raise_at_or_below_live_bid',
    CAST(COUNTIF(move LIKE 'raise to the seat price $%' AND seat_price <= current_bid + 0.005) AS FLOAT64),
    'stalled-probe seats proposing a raise to a seat price at or below the live bid · red > 0',
    IF(COUNTIF(move LIKE 'raise to the seat price $%' AND seat_price <= current_bid + 0.005) > 0, 'RED', 'GREEN'),
    CONCAT(CAST(COUNTIF(move LIKE 'raise to the seat price $%') AS STRING), ' raise proposals · ',
           CAST(COUNTIF(move LIKE 'park it%') AS STRING), ' park proposals · ',
           CAST(COUNTIF(seat_price IS NULL) AS STRING), ' outside the seat model (by hand or park) — the move branches on the sign of seat price − live bid')
  FROM sr WHERE row_type = 'SEAT' AND occupant_kind = 'stalled probe'
),
c20 AS (  -- ruling R-i: a due date already past is never printed as a future event
  SELECT 'seat_past_due_in_future_tense',
    CAST(COUNTIF(due_on < as_of AND NOT (sentence LIKE '%overdue%' AND move LIKE '%overdue%')) AS FLOAT64),
    'seats whose due date is before the image date but whose sentence or move does not say overdue · red > 0',
    IF(COUNTIF(due_on < as_of AND NOT (sentence LIKE '%overdue%' AND move LIKE '%overdue%')) > 0, 'RED', 'GREEN'),
    CONCAT(CAST(COUNTIF(due_on < as_of) AS STRING), ' seats past their due date on the image, all named overdue when this is green · ',
           'the cause is upstream of the register (see seat_overdue_vs_snapshot)')
  FROM sr WHERE row_type = 'SEAT'
),
c21 AS (  -- REPORTS only: appointments the ladder owes, measured on the SNAPSHOT's own date
  -- Not a verdict: the cause is the snapshot procedure stamping a park-era settle_due on revived
  -- and parked rows (diagnosed 2026-08-23, fix proposed and NOT applied — the ladder is outside
  -- the seat register's scope). overdue_appointments (c5) measures the same rows against today's
  -- wall clock; this one against the snapshot date the register judged them on, so it is a pure
  -- function of the snapshot and moves only when the ladder does.
  SELECT 'seat_overdue_vs_snapshot',
    CAST(COUNTIF(next_check_date < snapshot_date AND state != 'DEAD') AS FLOAT64),
    'keywords whose next_check_date is before the snapshot date they were judged on · INFO (reports, never red)',
    'INFO',
    CONCAT('by state: ',
           COALESCE((SELECT STRING_AGG(CONCAT(state, ' ', CAST(n AS STRING)), ', ' ORDER BY n DESC, state)
                     FROM (SELECT state, COUNT(*) n FROM ks WHERE next_check_date < snapshot_date AND state != 'DEAD' GROUP BY 1)), 'none'),
           ' · the register names each seated one overdue (R-i); the ladder fix is open for Ori (FAMILY_SEAT_REGISTER.md "Open rulings")')
  FROM ks
),
c22 AS (  -- REPORTS: days since the seat step last ran inside an orchestrator pass (New York clock)
  -- LOG_PIPELINE_RUNS is written by the orchestrator only — a hand CALL leaves no row — so a row
  -- here IS a pass. started_at is a UTC timestamp; run_date is the UTC date; the orchestrator is
  -- scheduled on New York time, so the day is read as DATE(started_at, 'America/New_York').
  SELECT 'seat_step_days_since_pass',
    CAST(DATE_DIFF(CURRENT_DATE('America/New_York'), MAX(DATE(started_at, 'America/New_York')), DAY) AS FLOAT64),
    'days since SP_MAINTAIN_FAMILY_SEATS last logged OK in a pass, New York clock · amber > 1, red > 2 (the pass is nightly); red when never logged',
    CASE WHEN MAX(started_at) IS NULL THEN 'RED'
         WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), MAX(DATE(started_at, 'America/New_York')), DAY) > 2 THEN 'RED'
         WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), MAX(DATE(started_at, 'America/New_York')), DAY) > 1 THEN 'AMBER'
         ELSE 'GREEN' END,
    CONCAT('last OK pass ', COALESCE(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', MAX(started_at), 'America/New_York'), 'never'), ' New York · ',
           CAST(COUNT(*) AS STRING), ' OK passes logged · image as of ',
           COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM sr), 'no image'),
           ' (snapshot ', COALESCE((SELECT CAST(MAX(snapshot_date) AS STRING) FROM ks), 'none'), ')')
  FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
  WHERE procedure_name = 'SP_MAINTAIN_FAMILY_SEATS' AND status = 'OK'
)
SELECT * FROM c1 UNION ALL SELECT * FROM c2 UNION ALL SELECT * FROM c3
UNION ALL SELECT * FROM c4 UNION ALL SELECT * FROM c5 UNION ALL SELECT * FROM c6
UNION ALL SELECT * FROM c7 UNION ALL SELECT * FROM c8 UNION ALL SELECT * FROM c9
UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12
UNION ALL SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15
UNION ALL SELECT * FROM c16 UNION ALL SELECT * FROM c17 UNION ALL SELECT * FROM c18
UNION ALL SELECT * FROM c19 UNION ALL SELECT * FROM c20 UNION ALL SELECT * FROM c21
UNION ALL SELECT * FROM c22;
