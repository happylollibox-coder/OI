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
-- v27.152 (2026-10-01): c23–c32, the next-week money plan's checks (plan Task 5, NEXT_WEEK_MONEY.md
-- §6) and two ALARMS for a night that was not saved. WHY NOW: SP_BUILD_NEXT_WEEK_PLAN failed every
-- pass from 2026-08-29 to 2026-09-28; LOG_PIPELINE_RUNS logged every failure and no surface told
-- Ori. The plan checks read the plan's latest partition, the proposal snapshot and the gate table —
-- small — never the judgement view and never a ceiling view. Three depart from the Task 5 draft
-- because the draft's forms read RED on a healthy partition (measured 2026-10-01 before deploy:
-- draft window test 0 but fails after 22:00 Los Angeles by the acceptance's own finding, draft pot
-- test 7, draft move test 152; the acceptance suite's v27.147 forms 0, 0, 0), so each takes the
-- form FACT_PLAN_NEXT_WEEK_acceptance.sql already holds: C01 (the age-2 fence), C03 (holdout spend
-- is outside the pot — the builder's unruled reading then; Ori ruled the opposite on 2026-10-02,
-- P-15, and v27.158 restates both) and C06 (one move per CANDIDATE). c28 is restated for P-14c: the guard is a
-- clock and a last-day test, not a veto — a demotion under its preconditions is legitimate iff the
-- judge published guard_released_by, and this check READS that column and never re-derives the
-- guard (the builder vetoed every partition for a month by re-deriving it). c26 is a REPORT until
-- plan Task 3 ships, because no engine PLAN writes proposals today and the check would otherwise
-- assert ownership the plan does not yet hold. The two alarms: plan_partition_fresh (a night the
-- plan step reached and did not save, or any night older than yesterday) and pipeline_step_failing
-- (ANY procedure whose three most recent runs all logged FAIL — the generic form of the outage,
-- which it would have named on day 1). V_DAILY_BRIEF reads this view's RED rows into one SYSTEM
-- line (section_rank 7), so the alarm reaches the one query Ori reads every morning.
-- v27.156 (2026-10-02, piece-1 plan Task 2, P-18): c28's hold half reads hold_kept_by. A hold now
-- also lasts while the very good day that started it is still inside the window, so a HELD row
-- is RED only when it has neither a very good last day nor hold_kept_by = STRONG_DAY_IN_WINDOW
-- with window_from <= hold_strong_day; the detail counts the holds kept by that day. Only the
-- guard and c28 CTEs changed.
-- v27.158 (2026-10-02, piece-1 plan Task 4, P-15, audit fix #24): plan_pot_reconciliation reads
-- the pot as Ori ruled it — every GOOD keyword's window spend, holdout included. The v27.152 form
-- (and the paragraph above calling the all-GOOD sum the draft's error) enforced the builder's
-- unruled reading (a) under a "(P-2)" label. The detail now prints each family's not-good side,
-- the expected spend after the upload and the share of the gap it closes (P-22). Only the pot_rec
-- and c24 CTEs changed.
-- v27.159 (2026-10-02, piece-1 plan Task 5, P-25, audit fix #19): plan_one_move_per_notgood reads the
-- two probe moves — a seated probe is OPEN_PROBE, an unseated probe NONE (nothing uploaded) — and
-- counts a candidate's NONE on anything but an unseated probe, or an OPEN_PROBE on anything but a
-- seated one (reads FACT_PLAN_NEXT_WEEK.is_probe, migration 2026-10-02_plan_seat_tenure_columns.sql).
-- Only that CTE changed.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ENGINE_HEALTH` AS
WITH pf AS (SELECT * FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`),
ks AS (SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
-- ONE shared scorecard scan (review 2026-08-16, planner safety): c6 and c7 both read THIS CTE.
-- Before this, c7 read V_MANUAL_DIVERGENCE, which embeds its own full V_CHANGE_SCORECARD scan —
-- two copies of the ceiling view inlined into one statement.
-- 2026-10-01: the scorecard now also grades changes observed on Amazon (source = 'OBSERVED', hand
-- changes from the DIM SCD2 trail). They are left out here so c6 and c7 measure what they always
-- measured; counting graded hand changes on the board is Ori's call (PPC_CLOSE_THE_LOOP.md).
sc AS (
  SELECT source, verdict, change_date, change_id, campaign_id, keyword_id, action_group,
         SAFE_CAST(new_value AS FLOAT64) AS new_val
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD`
  WHERE source != 'OBSERVED'
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
),
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- c23–c32: the next-week money plan (v27.152, NEXT_WEEK_MONEY.md §6 "Health") and the two
-- alarms for a night that was not saved. Sources: FACT_PLAN_NEXT_WEEK's latest partition (`pl`,
-- live rows `plb`), FACT_ENGINE_PROPOSALS' latest partition (`fep`), T_ENGINE_PREFLIGHT (`pf`,
-- above) and LOG_PIPELINE_RUNS. Tolerance $0.01 on a reconciliation, the acceptance suite's own.
-- EMPTINESS IS RED, NOT GREEN: a check that counts violations over an empty partition finds none,
-- and an empty partition is the very failure these checks exist to catch, so every partition
-- check says RED when it read no rows (the threshold column says so on each).
-- ───────────────────────────────────────────────────────────────────────────────────────────
pl AS (
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
),
plb AS (SELECT * FROM pl WHERE is_live_plan),
fep AS (
  SELECT * FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)
),
c23 AS (  -- the window is complete days only, fenced to age 2, and exactly window_days long
  -- The Task 5 draft asserted window_to = watermark - 1, which is P-10 without the P-14a fence and
  -- fails by construction after 22:00 Los Angeles, when FN_ADS_ANCHOR_CAP() advances and the
  -- fence gives up a day (FACT_PLAN_NEXT_WEEK_acceptance.sql C01). The fence is the convention.
  SELECT 'plan_window_complete_days' AS check_name,
    CAST(COUNTIF(window_to != LEAST(DATE_SUB(watermark, INTERVAL 1 DAY), DATE_SUB(as_of, INTERVAL 2 DAY))
                 OR DATE_DIFF(window_to, window_from, DAY) + 1 != window_days) AS FLOAT64),
    'rows whose window touches the filling day, breaks the age-2 fence, or is not window_days long · red > 0 (P-10, P-14a); red when the partition is empty',
    CASE WHEN COUNT(*) = 0 THEN 'RED'
         WHEN COUNTIF(window_to != LEAST(DATE_SUB(watermark, INTERVAL 1 DAY), DATE_SUB(as_of, INTERVAL 2 DAY))
                      OR DATE_DIFF(window_to, window_from, DAY) + 1 != window_days) > 0 THEN 'RED'
         ELSE 'GREEN' END,
    CONCAT('plan of ', COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM pl), 'none'),
           ' · window ', COALESCE((SELECT CAST(MAX(window_days) AS STRING) FROM pl), '-'),
           ' complete days ending ', COALESCE((SELECT CAST(MAX(window_to) AS STRING) FROM pl), '-'),
           ' · state ', COALESCE((SELECT MAX(calendar_state) FROM pl), '-'),
           ' · ', CAST(COUNT(*) AS STRING), ' rows, both plans')
  FROM pl
),
pot_rec AS (  -- the pot and the allowance per (plan, family), the acceptance's C03/C04 form
  -- P-15 (Ori 2026-10-02, v27.158): the pot is every GOOD keyword's window spend, holdout included
  -- (P-2's own words). The v27.152 form excluded holdout rows under a "(P-2)" label (audit fix #24).
  SELECT plan, family, MAX(pot_per_day) AS pot, MAX(allowance_target_per_day) AS alw,
         MAX(allowance_share) AS share, MAX(allowance_ramped_per_day) AS ramped,
         MAX(notgood_today_per_day) AS ng, MAX(expected_after_upload_per_day) AS exp_after,
         MAX(share_closed) AS closed,
         SAFE_DIVIDE(SUM(IF(side = 'GOOD', w_sp, 0)), MAX(window_days)) AS good
  FROM pl GROUP BY 1, 2
),
c24 AS (  -- the pot and the allowance reconcile to the cent
  SELECT 'plan_pot_reconciliation',
    CAST(COUNTIF(ABS(pot - good) > 0.01 OR ABS(alw - share * pot) > 0.01) AS FLOAT64),
    'plan x family rows whose pot (every GOOD keyword, holdout included) or allowance (share x pot) is off by more than a cent · red > 0 (P-15, P-2); red when the partition is empty',
    CASE WHEN COUNT(*) = 0 THEN 'RED'
         WHEN COUNTIF(ABS(pot - good) > 0.01 OR ABS(alw - share * pot) > 0.01) > 0 THEN 'RED'
         ELSE 'GREEN' END,
    -- the per-family line is built one level down: an aggregate may not enclose another
    CONCAT('per family, live plan: ',
           COALESCE((SELECT STRING_AGG(line, ', ' ORDER BY line) FROM (
                       SELECT FORMAT('%s pot $%.2f/d allowance $%.2f/d not-good $%.2f/d expected after upload $%.2f/d %s',
                                     COALESCE(p.family, '(no family)'),
                                     COALESCE(p.pot, 0), COALESCE(p.ramped, 0), COALESCE(p.ng, 0),
                                     COALESCE(p.exp_after, 0),
                                     IF(p.closed IS NULL, '(no gap to close)',
                                        FORMAT('(%.0f%% of the gap closes)', 100 * p.closed))) AS line
                       FROM pot_rec p JOIN (SELECT DISTINCT plan FROM plb) l USING (plan))), 'none'))
  FROM pot_rec
),
c25 AS (  -- one move per CANDIDATE, none on the good side, none where there is nothing to repair
  -- The draft demanded one of four moves on EVERY not-good row and read 152 violations on a
  -- healthy partition: a keyword with no spend, no clicks and no probe nomination has nothing to
  -- repair and carries NONE by spec §9 (v27.135). This is the acceptance's C06 (v27.147).
  SELECT 'plan_one_move_per_notgood',
    CAST(COUNTIF(side = 'GOOD' AND move != 'NONE')
       + COUNTIF(is_candidate AND move NOT IN ('REPRICE', 'HOLD_AT_PRICE', 'OPEN_PROBE', 'PARK', 'HOLD_AT_PARK', 'PAUSE', 'NONE'))
       + COUNTIF(is_candidate AND move = 'NONE' AND NOT (COALESCE(is_probe, FALSE) AND seat_no IS NULL))
       + COUNTIF(move = 'OPEN_PROBE' AND NOT (is_candidate AND COALESCE(is_probe, FALSE) AND seat_no IS NOT NULL))
       + COUNTIF(NOT is_candidate AND COALESCE(holdout, FALSE) AND side = 'NOT_GOOD' AND move != 'NONE_HOLDOUT')
       + COUNTIF(NOT is_candidate AND NOT COALESCE(holdout, FALSE) AND side = 'NOT_GOOD' AND move != 'NONE')
       + COUNTIF(move IS NULL) AS FLOAT64),
    'live-plan rows: good side carrying a move, candidates carrying none of the seven (an unseated probe NONE, a seated probe OPEN_PROBE, P-25), non-candidates carrying one, rows with no move · red > 0 (P-4, §9); red when the live plan is empty',
    CASE WHEN COUNT(*) = 0 THEN 'RED'
         WHEN COUNTIF(side = 'GOOD' AND move != 'NONE')
            + COUNTIF(is_candidate AND move NOT IN ('REPRICE', 'HOLD_AT_PRICE', 'OPEN_PROBE', 'PARK', 'HOLD_AT_PARK', 'PAUSE', 'NONE'))
       + COUNTIF(is_candidate AND move = 'NONE' AND NOT (COALESCE(is_probe, FALSE) AND seat_no IS NULL))
       + COUNTIF(move = 'OPEN_PROBE' AND NOT (is_candidate AND COALESCE(is_probe, FALSE) AND seat_no IS NOT NULL))
            + COUNTIF(NOT is_candidate AND COALESCE(holdout, FALSE) AND side = 'NOT_GOOD' AND move != 'NONE_HOLDOUT')
            + COUNTIF(NOT is_candidate AND NOT COALESCE(holdout, FALSE) AND side = 'NOT_GOOD' AND move != 'NONE')
            + COUNTIF(move IS NULL) > 0 THEN 'RED'
         ELSE 'GREEN' END,
    CONCAT('moves on the live plan: ',
           COALESCE((SELECT STRING_AGG(CONCAT(move, ' ', CAST(n AS STRING)), ', ' ORDER BY n DESC, move)
                     FROM (SELECT COALESCE(move, '(null)') AS move, COUNT(*) n FROM plb GROUP BY 1)), 'none'),
           ' · ', CAST(COUNTIF(is_candidate) AS STRING), ' candidates')
  FROM plb
),
c26 AS (  -- REPORTS until plan Task 3 ships: foreign GO rows on money levers inside live-plan campaigns
  -- The draft asserted P-11 (nothing but PLAN and LOW_STOCK moves money in a plan family) with
  -- red > 0. Measured 2026-10-01: no engine PLAN has written a proposal and no row carries
  -- hold_source = 'PLAN' — plan Task 3 (ownership and the preflight) is not built, so the plan
  -- owns nothing at the gate and a RED here would be a verdict on work that does not exist. It
  -- counts the rows a RED would count, as a number, and says so; when Task 3 ships, the status
  -- becomes IF(count > 0, 'RED', 'GREEN') and this comment is retired.
  SELECT 'plan_ownership_no_foreign_go',
    CAST((SELECT COUNTIF(engine NOT IN ('PLAN', 'LOW_STOCK') AND lever IN ('BID', 'BUDGET') AND verdict = 'GO'
                         AND campaign_id IN (SELECT DISTINCT campaign_id FROM plb)) FROM pf) AS FLOAT64),
    'GO rows on a money lever from an engine other than PLAN or LOW_STOCK, inside a live-plan campaign · INFO (reports) until plan Task 3 ships, then red > 0 (P-11)',
    'INFO',
    CONCAT('plan Task 3 is NOT built — no engine PLAN writes proposals and no proposal carries hold_source PLAN, so the plan holds no ownership at the gate yet · foreign GO rows on money levers inside live-plan campaigns, by engine: ',
           COALESCE((SELECT STRING_AGG(CONCAT(engine, ' ', CAST(n AS STRING)), ', ' ORDER BY n DESC, engine)
                     FROM (SELECT engine, COUNT(*) n FROM pf
                           WHERE engine NOT IN ('PLAN', 'LOW_STOCK') AND lever IN ('BID', 'BUDGET') AND verdict = 'GO'
                             AND campaign_id IN (SELECT DISTINCT campaign_id FROM plb)
                           GROUP BY 1)), 'none'),
           ' · held by the plan today: ', CAST((SELECT COUNTIF(hold_source = 'PLAN') FROM fep) AS STRING), ' proposal(s)',
           ' · live-plan campaigns: ', CAST((SELECT COUNT(DISTINCT campaign_id) FROM plb) AS STRING))
),
c27 AS (  -- both plans are written every night
  SELECT 'plan_both_plans_written',
    CAST((SELECT COUNT(DISTINCT plan) FROM pl) AS FLOAT64),
    'distinct plans in the latest partition · must be 2 (A shadow + B live); red otherwise, red when the partition is empty (P-9)',
    IF((SELECT COUNT(DISTINCT plan) FROM pl) = 2, 'GREEN', 'RED'),
    CONCAT('live plan is ', COALESCE((SELECT MAX(plan) FROM plb), 'none'),
           ' · rows A/B: ', CAST((SELECT COUNTIF(plan = 'A') FROM pl) AS STRING), '/',
           CAST((SELECT COUNTIF(plan = 'B') FROM pl) AS STRING),
           ' · partition ', COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM pl), 'none'))
),
guard AS (  -- the P-14b/P-14c ledger on the live plan, counted once for c28
  -- under_guard = the guard's PRECONDITIONS (demoted, was good, served, unsettled). A row under
  -- them is legitimate iff the judge published why it released it: guard_released_by is READ,
  -- never re-derived (the builder re-derived it and vetoed every partition 2026-08-29..09-28).
  SELECT COUNT(*) AS n_rows,
         COUNTIF(under_guard) AS n_under,
         COUNTIF(under_guard AND guard_released_by = 'LAST_DAY_NOT_STRONG') AS n_lds,
         COUNTIF(under_guard AND guard_released_by = 'HOLD_EXPIRED') AS n_exp,
         COUNTIF(under_guard AND COALESCE(guard_released_by, '') NOT IN ('HOLD_EXPIRED', 'LAST_DAY_NOT_STRONG')) AS n_no_release,
         COUNTIF(under_guard AND guard_released_by IS NULL) AS n_null_release,
         COUNTIF(verdict = 'HELD_UNSETTLED') AS n_held,
         -- P-18 (v27.156): a hold is earned by a very good last day OR kept while the very good
         -- day that started it is still inside the window; hold_kept_by is READ, never re-derived
         COUNTIF(verdict = 'HELD_UNSETTLED'
                 AND NOT (COALESCE(last_day_strong, FALSE)
                          OR (COALESCE(hold_kept_by, '') = 'STRONG_DAY_IN_WINDOW'
                              AND COALESCE(window_from <= hold_strong_day, FALSE)))) AS n_held_weak,
         COUNTIF(verdict = 'HELD_UNSETTLED' AND hold_kept_by = 'STRONG_DAY_IN_WINDOW') AS n_held_kept_sd,
         SAFE_DIVIDE(SUM(IF(verdict = 'HELD_UNSETTLED', w_sp, 0)), MAX(window_days)) AS held_per_day
  FROM (SELECT *, (side = 'NOT_GOOD' AND COALESCE(was_good, FALSE) AND COALESCE(served, FALSE)
                   AND NOT COALESCE(settled, FALSE)) AS under_guard
        FROM plb)
),
c28 AS (  -- P-14b is a clock and P-14c a last-day test, not a veto: every release is PUBLISHED, every hold is EARNED
  SELECT 'plan_settle_guard_holds',
    CAST(n_no_release + n_held_weak AS FLOAT64),
    'live-plan rows demoted under the guard preconditions (not-good, was good, served, unsettled) with no release the judge published (HOLD_EXPIRED | LAST_DAY_NOT_STRONG), plus HELD_UNSETTLED rows held by neither a very good last day nor (hold_kept_by STRONG_DAY_IN_WINDOW) the very good day that started the hold still inside the window · red > 0 (P-14b, P-14c, P-18); red when the live plan is empty',
    CASE WHEN n_rows = 0 THEN 'RED' WHEN n_no_release + n_held_weak > 0 THEN 'RED' ELSE 'GREEN' END,
    CONCAT('under the guard preconditions: ', CAST(n_under AS STRING),
           ' — released by LAST_DAY_NOT_STRONG ', CAST(n_lds AS STRING),
           ', HOLD_EXPIRED ', CAST(n_exp AS STRING),
           ', no release published ', CAST(n_null_release AS STRING),
           ', unknown reason ', CAST(n_no_release - n_null_release AS STRING),
           ' · held (HELD_UNSETTLED): ', CAST(n_held AS STRING),
           ', of which kept by the very good day still in the window ', CAST(n_held_kept_sd AS STRING),
           ', held by neither ', CAST(n_held_weak AS STRING),
           ' · the hold is $', FORMAT('%.2f', COALESCE(held_per_day, 0)),
           '/day of window spend the not-good side does not see yet')
  FROM guard
),
c29 AS (  -- REPORTS: how much of the correction the curve could actually answer for
  SELECT 'plan_settle_curve_coverage',
    CAST(SAFE_DIVIDE(COUNTIF(COALESCE(settle_curve_available, FALSE)), NULLIF(COUNT(*), 0)) AS FLOAT64),
    'share of live-plan rows whose settle curve could answer · INFO (reports); 0 means the plan rests on the guard alone (P-14a)',
    'INFO',
    CONCAT(CAST(COUNTIF(NOT COALESCE(settle_curve_available, FALSE)) AS STRING),
           ' row(s) uncorrected because the curve could not answer · smallest factor applied ',
           FORMAT('%.3f', COALESCE(MIN(settle_factor_min), 1.0)),
           ' · arms: ',
           COALESCE((SELECT STRING_AGG(CONCAT(settle_arm, ' ', CAST(n AS STRING)), ', ' ORDER BY n DESC, settle_arm)
                     FROM (SELECT COALESCE(settle_arm, '(null)') AS settle_arm, COUNT(*) n FROM plb GROUP BY 1)), 'none'))
  FROM plb
),
c30 AS (  -- REPORTS: how far the live plan sits behind the proposal snapshot
  SELECT 'plan_proposal_lag_days',
    CAST(DATE_DIFF((SELECT MAX(snapshot_date) FROM fep),
                   COALESCE((SELECT MAX(as_of) FROM plb), DATE '1900-01-01'), DAY) AS FLOAT64),
    'days between the latest proposal snapshot and the latest live plan · INFO (reports); amber > 2; red when no live plan exists',
    CASE WHEN (SELECT MAX(as_of) FROM plb) IS NULL THEN 'RED'
         WHEN DATE_DIFF((SELECT MAX(snapshot_date) FROM fep), (SELECT MAX(as_of) FROM plb), DAY) > 2 THEN 'AMBER'
         ELSE 'INFO' END,
    CONCAT('proposals of ', COALESCE((SELECT CAST(MAX(snapshot_date) AS STRING) FROM fep), 'none'),
           ' · live plan of ', COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM plb), 'none'),
           ' · the proposal snapshot (Task 20.6) runs before the plan (20.8c) inside one pass, so the proposals read the plan an earlier pass wrote — one pass of lag is by design (open ruling for Ori)')
),
plan_clock AS (  -- the day the plan step was last REACHED (OK or FAIL) and the latest plan saved
  -- The orchestrator passes three times a day (about 01:35, 04:10 and 12:40 New York) and the
  -- plan step writes as_of = CURRENT_DATE('America/Los_Angeles'), so a plan for Los Angeles day D
  -- first exists after the 04:10 New York pass. "MAX(as_of) < today" alone is therefore RED every
  -- day between midnight and that pass for no reason. The due date is the LATER of two days: the
  -- Los Angeles day of the last LOG_PIPELINE_RUNS row the plan step itself logged (a pass that
  -- reached the step and did not save a partition for its own day is the outage — OK or FAIL,
  -- because an OK that saved nothing is the same failure), and yesterday (so a dead orchestrator
  -- is RED the next morning). A hand CALL leaves no row and does not move the clock.
  SELECT GREATEST(COALESCE((SELECT MAX(DATE(started_at, 'America/Los_Angeles'))
                            FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
                            WHERE procedure_name = 'SP_BUILD_NEXT_WEEK_PLAN'
                              AND run_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)), DATE '1900-01-01'),
                  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)) AS due,
         (SELECT MAX(started_at) FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
          WHERE procedure_name = 'SP_BUILD_NEXT_WEEK_PLAN'
            AND run_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)) AS last_reached_at,
         (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) AS last_plan
),
c31 AS (  -- ALARM: a night the plan was not saved
  SELECT 'plan_partition_fresh',
    CAST(IF(last_plan IS NULL, NULL, GREATEST(DATE_DIFF(due, last_plan, DAY), 0)) AS FLOAT64),
    'nights with no plan partition, up to the later of yesterday and the Los Angeles day the plan step last ran (OK or FAIL) · red > 0; red when no plan was ever saved',
    CASE WHEN last_plan IS NULL THEN 'RED' WHEN last_plan < due THEN 'RED' ELSE 'GREEN' END,
    CONCAT('last plan ', COALESCE(CAST(last_plan AS STRING), 'never'), ', ',
           IF(last_plan IS NULL, 'every night',
              CONCAT(CAST(GREATEST(DATE_DIFF(due, last_plan, DAY), 0) AS STRING), ' night(s)')),
           ' missing · a plan is due for every night up to ', CAST(due AS STRING),
           ' · the plan step last ran ',
           COALESCE(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', last_reached_at, 'America/Los_Angeles'), 'never in 7 days'),
           ' Los Angeles · the step is SP_BUILD_NEXT_WEEK_PLAN (Refresh Task 20.8c); its error, if it failed, is on pipeline_step_failing and in LOG_PIPELINE_RUNS; nothing re-runs it by itself')
  FROM plan_clock
),
pr AS (  -- every procedure's runs in the last 30 days, newest first
  -- Declared constants: 30 days is the memory (older failures belong to a step nothing runs
  -- any more, which the freshness checks own); 3 runs is the streak (the pass runs three times a
  -- day, so a step broken for one night fails three runs and is named the next morning).
  SELECT procedure_name, status, error_message, started_at,
         ROW_NUMBER() OVER (PARTITION BY procedure_name ORDER BY started_at DESC) AS rn
  FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
  WHERE run_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
),
pipe_fail AS (  -- procedures whose three most recent runs all logged FAIL, with the streak behind them
  SELECT f.procedure_name, f.last_error, f.last_started,
         s.n_streak, s.streak_since
  FROM (SELECT procedure_name,
               ARRAY_AGG(IF(rn = 1, SUBSTR(COALESCE(error_message, '(no message)'), 1, 120), NULL) IGNORE NULLS)[SAFE_OFFSET(0)] AS last_error,
               MAX(IF(rn = 1, started_at, NULL)) AS last_started
        FROM pr WHERE rn <= 3
        GROUP BY 1
        HAVING COUNT(*) = 3 AND COUNTIF(status = 'FAIL') = 3) f
  JOIN (SELECT p.procedure_name,
               COUNTIF(p.rn < COALESCE(o.first_ok_rn, 2147483647)) AS n_streak,
               MIN(IF(p.rn < COALESCE(o.first_ok_rn, 2147483647), p.started_at, NULL)) AS streak_since
        FROM pr p
        LEFT JOIN (SELECT procedure_name, MIN(IF(status != 'FAIL', rn, NULL)) AS first_ok_rn
                   FROM pr GROUP BY 1) o USING (procedure_name)
        GROUP BY 1) s USING (procedure_name)
),
c32 AS (  -- ALARM, GENERIC: a step that fails three runs running is a step nobody is running by hand
  -- This is the check that would have named SP_BUILD_NEXT_WEEK_PLAN on 2026-08-29, the first
  -- night of its month-long outage. It names ANY procedure, so the next outage needs no new check.
  SELECT 'pipeline_step_failing',
    CAST((SELECT COUNT(*) FROM pipe_fail) AS FLOAT64),
    'procedures whose three most recent runs (last 30 days, by started_at) all logged FAIL · red > 0',
    IF((SELECT COUNT(*) FROM pipe_fail) > 0, 'RED', 'GREEN'),
    COALESCE((SELECT STRING_AGG(CONCAT(procedure_name, ': ', last_error,
                                       ' [', CAST(n_streak AS STRING), ' run(s) failing in a row since ',
                                       FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', streak_since, 'America/New_York'), ' New York]'),
                                '; ' ORDER BY last_started DESC) FROM pipe_fail),
             CONCAT('no step has failed its last three runs · ',
                    CAST((SELECT COUNT(DISTINCT procedure_name) FROM pr) AS STRING), ' procedures logged in the last 30 days · ',
                    CAST((SELECT COUNTIF(status = 'FAIL') FROM pr) AS STRING), ' FAIL row(s) among ',
                    CAST((SELECT COUNT(*) FROM pr) AS STRING), ' runs · last run ',
                    COALESCE((SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', MAX(started_at), 'America/New_York') FROM pr), 'never'),
                    ' New York'))
)
SELECT * FROM c1 UNION ALL SELECT * FROM c2 UNION ALL SELECT * FROM c3
UNION ALL SELECT * FROM c4 UNION ALL SELECT * FROM c5 UNION ALL SELECT * FROM c6
UNION ALL SELECT * FROM c7 UNION ALL SELECT * FROM c8 UNION ALL SELECT * FROM c9
UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12
UNION ALL SELECT * FROM c13 UNION ALL SELECT * FROM c14 UNION ALL SELECT * FROM c15
UNION ALL SELECT * FROM c16 UNION ALL SELECT * FROM c17 UNION ALL SELECT * FROM c18
UNION ALL SELECT * FROM c19 UNION ALL SELECT * FROM c20 UNION ALL SELECT * FROM c21
UNION ALL SELECT * FROM c22 UNION ALL SELECT * FROM c23 UNION ALL SELECT * FROM c24
UNION ALL SELECT * FROM c25 UNION ALL SELECT * FROM c26 UNION ALL SELECT * FROM c27
UNION ALL SELECT * FROM c28 UNION ALL SELECT * FROM c29 UNION ALL SELECT * FROM c30
UNION ALL SELECT * FROM c31 UNION ALL SELECT * FROM c32;
