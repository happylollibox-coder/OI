-- =============================================================================================
-- V_CATALOG_DWELL — how long has this been stuck? v27.143 (2026-08-24).
--
-- THE QUESTION §10.4 SAYS NOBODY CAN ANSWER. "Dwell time in any state. The Catalog holds one
-- snapshot and is replaced nightly, so no 'how long has this been stuck' question is answerable
-- anywhere. This is violation 6 obstructing the measurement of every other violation, and it is
-- the single highest-value thing to fix first."
--
-- NAME. The gap-closure plan (docs/superpowers/plans/2026-08-25-three-layers-gap-closure.md,
-- Task 0.4) names this object V_CATALOG_DWELL and later phases report against that name, so it
-- keeps the plan's name rather than a new one. It also keeps the plan's useful columns —
-- days_overdue, state_changes_28d / _90d, days_of_history — and replaces the plan's
-- `days_in_state = DATE_DIFF(as_of, run_start) + 1` with a censoring-aware pair, because on a
-- one-day history that expression reports "1 day" for every subject in the account and a reader
-- cannot tell a keyword that flipped this morning from one that has been parked since June. A
-- number that is silently a floor is the same failure as no number at all.
--
-- One row per SUBJECT (§2.2: campaign_id + keyword_id — a keyword id is scoped by Amazon to one
-- ad group, hence one campaign and one family; bare target text is never a valid subject). For
-- each it answers three things and refuses to answer a fourth:
--   * what state it is in now, and since when — as OBSERVED, not as declared;
--   * what it changed FROM, and the window inside which the change fell;
--   * how long it has been there — with an explicit basis, and a MINIMUM and a MAXIMUM rather
--     than a single number the evidence does not support;
--   * and it refuses to invent the part that predates the history.
--
-- READS THE HISTORY ONLY. Nothing here touches FACT_KEYWORD_STATE, so the view answers whether or
-- not tonight's pass has run (§1.4: no ordering dependency).
--
-- WHY IT DOES NOT USE FACT_KEYWORD_STATE.state_since. The snapshot publishes a column of that name
-- and it does NOT mean "when this state began". Read the procedure: it is the park date for a
-- park, floor_since on probation, and otherwise the last bid change or the last applied row — a
-- proxy for "when did something last happen to this keyword", NULL for a large share of the
-- account, and derived from the change log rather than from the ladder's own verdicts. So it can
-- move while the state stands still, and stand still while the state moves. This view therefore
-- measures dwell from OBSERVATION — consecutive snapshots of the same verdict — and publishes the
-- declared column beside it as state_since_declared with declared_agrees, so the disagreement is
-- visible instead of one being silently preferred. Re-derive how far apart they are with a
-- COUNTIF over declared_agrees; do not trust a number written in prose here (Standing Rule 0).
--
-- HONEST DEGRADATION IS THE POINT, NOT A CAVEAT. On the day the history starts, every subject has
-- been in its state for "at least one day" and NOTHING can be said about how much longer. A view
-- that printed a number there would be manufacturing the very memory violation 6 is about. So:
--   dwell_basis = 'AT_LEAST'  the run reaches back to the subject's first row in the history. The
--                             true start is UNKNOWN and may be far earlier. days_in_state_max IS
--                             NULL — deliberately, so an arithmetic consumer cannot average it
--                             into a fake mean.
--   dwell_basis = 'EXACT'     the state was observed to change: the previous snapshot for this
--                             subject is the day before the run started and it read a different
--                             state. Exact at the resolution the Catalog has, which is one day.
--   dwell_basis = 'BETWEEN'   the state changed, but the previous observation is older than the
--                             day before, so the change fell somewhere inside a window. Both
--                             bounds are published and they differ.
-- days_in_state is ALWAYS the floor — the number that is certainly true — and days_in_state_max
-- is the ceiling where one exists. A consumer that reads days_in_state alone is never misled
-- upward; it is only ever told less than the truth, never more.
-- dwell_gap_days counts days inside the run for which the history HAS a snapshot but this subject
-- has NO row — the subject vanished and came back. The dwell is still reported and the gap is
-- reported beside it, because a run with holes is a weaker claim than a run without.
-- state_changes_28d / _90d are OBSERVED counts over windows the history may not yet span; read
-- them against history_days, which every row carries.
--
-- A SUBJECT THAT VANISHED IS STILL A ROW. Appendix B of the doctrine is a keyword that was paused
-- and left no row in FACT_KEYWORD_STATE at all — "invisible to all three layers, with no mechanism
-- to return". A one-snapshot table cannot even tell you it is gone. Here it keeps its row:
-- is_current = FALSE, absent_since, absent_days, and the last verdict the Catalog ever gave it.
--
-- NOTHING HERE DECIDES ANYTHING. Read-only over an append-only table (§1.4: "asking changes
-- nothing"). No engine, generator or book reads it. It cannot move a bid, a budget or a pause.
--
-- Reads: FACT_KEYWORD_STATE_HISTORY only.
-- Acceptance: scripts/bigquery/tests/KEYWORD_STATE_HISTORY_acceptance.sql (C06..C09).
-- Spec: architecture/THREE_LAYERS.md §1.4, §6, §8 (violation 6), §10.4.
-- SOP:  architecture/KEYWORD_STATE.md §"The history".
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CATALOG_DWELL`
OPTIONS (description = "Dwell time in the Catalog's states — the question THREE_LAYERS.md §10.4 named as unanswerable and highest-value to fix. One row per subject (campaign_id, keyword_id) over FACT_KEYWORD_STATE_HISTORY: the current verdict, the date the run of that verdict was first OBSERVED, what it changed from, the window the change fell inside, how often it has flipped in 28 and 90 observed days, how overdue its own next_check_date is, and how long it has stood — as days_in_state (ALWAYS the floor, the number that is certainly true) with days_in_state_max and an explicit dwell_basis of EXACT (the change was observed; the previous snapshot is the day before), BETWEEN (the change fell inside a gap; both bounds published and they differ) or AT_LEAST (the run reaches the subject's first row in the history, so the true start is unknown and days_in_state_max is deliberately NULL rather than a number nothing supports). Measures dwell from observation, never from FACT_KEYWORD_STATE.state_since — which is the park date / floor_since / last bid change, is NULL for much of the account, and can move while the state stands still; that column is published beside it as state_since_declared with declared_agrees so the disagreement is visible. A subject that VANISHED from the snapshot keeps its row with is_current FALSE, absent_since and absent_days — the case doctrine Appendix B describes, which a one-snapshot table cannot even report. Reads the history only, so it answers whether or not tonight's pass has run (§1.4, no ordering dependency). Every row carries the history's own bounds (history_from / history_to / history_days) and a plain sentence. Read-only; no engine, generator or book reads it and it can move no bid, budget or pause. Spec: architecture/THREE_LAYERS.md §1.4/§6/§8/§10.4. SOP: architecture/KEYWORD_STATE.md.")
AS
WITH
bounds AS (
  SELECT
    MIN(snapshot_date) AS history_from,
    MAX(snapshot_date) AS history_to,
    COUNT(DISTINCT snapshot_date) AS history_days
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
),
-- every snapshot date the history actually holds, so a "gap" means the subject was missing on a
-- day the Catalog DID speak — never a day the pipeline simply did not run.
hist_dates AS (
  SELECT DISTINCT snapshot_date AS d
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
),
seq AS (
  SELECT
    h.snapshot_date, h.campaign_id, h.keyword_id, h.target_text, h.match_type, h.channel,
    h.campaign_name, h.family, h.state, h.owner_engine, h.state_since, h.prior_state,
    h.next_check_date, h.state_reason, h.current_bid, h.settled_clk90, h.settled_ord90,
    h.settled_roas90, h.settled_sp90, h.family_bar, h.se_eff, h.affordable_cpc, h.affordable_bid,
    h.bid_floor, h.is_brand_defense,
    LAG(h.state)         OVER w AS prev_state,
    LAG(h.snapshot_date) OVER w AS prev_date
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
  WINDOW w AS (PARTITION BY h.campaign_id, h.keyword_id ORDER BY h.snapshot_date)
),
-- a RUN is a maximal stretch of consecutive OBSERVATIONS carrying the same verdict. Observation
-- gaps do not break a run (the verdict did not change on the evidence we hold) — they are counted
-- separately as dwell_gap_days and said out loud, because a run with holes is a weaker claim.
runs AS (
  SELECT
    s.*,
    COUNTIF(s.prev_state IS NULL OR s.prev_state IS DISTINCT FROM s.state)
      OVER (PARTITION BY s.campaign_id, s.keyword_id ORDER BY s.snapshot_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS run_no
  FROM seq s
),
subj AS (
  SELECT
    campaign_id, keyword_id,
    MIN(snapshot_date) AS first_observed_on,
    MAX(snapshot_date) AS last_observed_on,
    COUNT(*)           AS days_of_history,
    MAX(run_no) - 1    AS state_changes_observed,
    COUNTIF(prev_state IS NOT NULL AND prev_state IS DISTINCT FROM state
            AND snapshot_date > DATE_SUB((SELECT history_to FROM bounds), INTERVAL 27 DAY))
                       AS state_changes_28d,
    COUNTIF(prev_state IS NOT NULL AND prev_state IS DISTINCT FROM state
            AND snapshot_date > DATE_SUB((SELECT history_to FROM bounds), INTERVAL 89 DAY))
                       AS state_changes_90d
  FROM runs
  GROUP BY 1, 2
),
last_row AS (
  SELECT *
  FROM runs
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id
                             ORDER BY snapshot_date DESC) = 1
),
cur_run AS (
  SELECT
    r.campaign_id, r.keyword_id,
    MIN(r.snapshot_date) AS run_started_on,
    COUNT(*)             AS observed_days_in_state
  FROM runs r
  JOIN last_row l
    ON l.campaign_id = r.campaign_id AND l.keyword_id = r.keyword_id AND l.run_no = r.run_no
  GROUP BY 1, 2
),
run_start_row AS (
  SELECT
    r.campaign_id, r.keyword_id, r.snapshot_date AS run_started_on,
    r.prev_state AS changed_from, r.prev_date AS previous_observation_on
  FROM runs r
  JOIN cur_run c
    ON c.campaign_id = r.campaign_id AND c.keyword_id = r.keyword_id
   AND c.run_started_on = r.snapshot_date
),
asm AS (
  SELECT
    l.campaign_id, l.keyword_id, l.target_text, l.match_type, l.channel,
    l.campaign_name, l.family, l.is_brand_defense,
    l.state AS current_state, l.owner_engine, l.state_reason, l.next_check_date,
    l.current_bid, l.settled_clk90, l.settled_ord90, l.settled_roas90, l.settled_sp90,
    l.family_bar, l.se_eff, l.affordable_cpc, l.affordable_bid, l.bid_floor,
    l.state_since AS state_since_declared,
    l.prior_state AS prior_state_declared,
    s.first_observed_on, s.last_observed_on, s.days_of_history, s.state_changes_observed,
    s.state_changes_28d, s.state_changes_90d,
    c.run_started_on, c.observed_days_in_state,
    rs.changed_from, rs.previous_observation_on,
    b.history_from, b.history_to, b.history_days,
    (SELECT COUNT(*) FROM hist_dates hd
      WHERE hd.d BETWEEN c.run_started_on AND s.last_observed_on) AS snapshot_days_in_run,
    (SELECT MIN(hd.d) FROM hist_dates hd WHERE hd.d > s.last_observed_on) AS absent_since
  FROM last_row l
  JOIN subj    s  ON s.campaign_id  = l.campaign_id AND s.keyword_id  = l.keyword_id
  JOIN cur_run c  ON c.campaign_id  = l.campaign_id AND c.keyword_id  = l.keyword_id
  JOIN run_start_row rs
                  ON rs.campaign_id = l.campaign_id AND rs.keyword_id = l.keyword_id
  CROSS JOIN bounds b
),
calc AS (
  SELECT
    a.*,
    (a.changed_from IS NULL) AS is_censored,
    (a.changed_from IS NOT NULL
     AND a.previous_observation_on = DATE_SUB(a.run_started_on, INTERVAL 1 DAY)) AS is_exact,
    (a.last_observed_on = a.history_to) AS is_current,
    -- INCLUSIVE day count: a subject first observed in this state today has been in it for 1 day.
    DATE_DIFF(a.last_observed_on, a.run_started_on, DAY) + 1 AS days_in_state_floor,
    a.snapshot_days_in_run - a.observed_days_in_state        AS dwell_gap_days
  FROM asm a
)
SELECT
  c.history_to                           AS as_of,

  -- the subject (§2.2)
  c.campaign_id,
  c.keyword_id,
  c.target_text,
  c.match_type,
  c.channel,
  c.campaign_name,
  c.family,
  c.is_brand_defense,

  -- what the Catalog says now (its last word, whenever that was)
  c.current_state                        AS state,
  c.owner_engine,
  c.state_reason,
  c.next_check_date,
  -- positive = the appointment is past due. NULL where there is no appointment (DEAD only).
  IF(c.next_check_date IS NULL, NULL,
     DATE_DIFF(c.history_to, c.next_check_date, DAY))        AS days_overdue,

  -- THE DWELL ANSWER. days_in_state is always the floor: certainly true, never over-claimed.
  c.run_started_on                       AS state_run_start,
  c.days_in_state_floor                  AS days_in_state,
  CASE
    WHEN c.is_censored THEN NULL
    WHEN c.is_exact    THEN c.days_in_state_floor
    ELSE DATE_DIFF(c.last_observed_on, c.previous_observation_on, DAY)
  END                                    AS days_in_state_max,
  CASE
    WHEN c.is_censored THEN 'AT_LEAST'
    WHEN c.is_exact    THEN 'EXACT'
    ELSE 'BETWEEN'
  END                                    AS dwell_basis,
  c.is_censored                          AS dwell_is_censored,
  c.observed_days_in_state,
  c.dwell_gap_days,

  -- the change: what it came from, and the window it fell inside
  c.changed_from,
  IF(c.is_censored, NULL, c.run_started_on)            AS changed_on_or_before,
  c.previous_observation_on                            AS changed_after,
  c.state_changes_observed,
  c.state_changes_28d,
  c.state_changes_90d,

  -- the snapshot's own declared column, published beside the observed one, never instead of it
  c.state_since_declared,
  c.prior_state_declared,
  (c.state_since_declared = c.run_started_on)          AS declared_agrees,

  -- presence: a subject that vanished from the Catalog keeps its row
  c.is_current,
  c.first_observed_on,
  c.last_observed_on,
  c.days_of_history,
  IF(c.is_current, NULL, c.absent_since)               AS absent_since,
  IF(c.is_current, NULL,
     DATE_DIFF(c.history_to, c.last_observed_on, DAY)) AS absent_days,

  -- the evidence the verdict was read off, carried so a grader (§6) needs no second join
  c.current_bid,
  c.settled_clk90,
  c.settled_ord90,
  c.settled_roas90,
  c.settled_sp90,
  c.family_bar,
  c.se_eff,
  c.affordable_cpc,
  c.affordable_bid,
  c.bid_floor,

  -- the history's own bounds, on every row, so no reader has to go and find them
  c.history_from,
  c.history_to,
  c.history_days,

  -- the plain sentence
  CONCAT(
    c.current_state,
    CASE
      WHEN c.is_censored THEN CONCAT(
        ' for AT LEAST ', CAST(c.days_in_state_floor AS STRING),
        IF(c.days_in_state_floor = 1, ' day', ' days'),
        ' — it already read ', c.current_state, ' on ', CAST(c.run_started_on AS STRING),
        ', the first day this history holds for it, so when it truly began is UNKNOWN')
      WHEN c.is_exact THEN CONCAT(
        ' for ', CAST(c.days_in_state_floor AS STRING),
        IF(c.days_in_state_floor = 1, ' day', ' days'),
        ' — observed changing from ', c.changed_from, ' on ', CAST(c.run_started_on AS STRING))
      ELSE CONCAT(
        ' for between ', CAST(c.days_in_state_floor AS STRING), ' and ',
        CAST(DATE_DIFF(c.last_observed_on, c.previous_observation_on, DAY) AS STRING),
        ' days — it changed from ', c.changed_from, ' somewhere after ',
        CAST(c.previous_observation_on AS STRING), ' and by ', CAST(c.run_started_on AS STRING))
    END,
    IF(c.dwell_gap_days > 0,
       CONCAT('; ', CAST(c.dwell_gap_days AS STRING),
              ' day(s) inside that stretch have a snapshot in which this subject has no row at all'),
       ''),
    IF(c.next_check_date IS NOT NULL AND c.next_check_date < c.history_to,
       CONCAT('; its own appointment was ', CAST(c.next_check_date AS STRING), ', ',
              CAST(DATE_DIFF(c.history_to, c.next_check_date, DAY) AS STRING), ' day(s) ago'),
       ''),
    IF(c.is_current, '',
       CONCAT('; it has been ABSENT from the Catalog since ', CAST(c.absent_since AS STRING),
              ' — the last thing said about it was said on ', CAST(c.last_observed_on AS STRING))),
    '. (History: ', CAST(c.history_days AS STRING),
    IF(c.history_days = 1, ' day, ', ' days, '),
    CAST(c.history_from AS STRING), '..', CAST(c.history_to AS STRING),
    '. Dwell is measured from observation, not from state_since.)'
  ) AS dwell_sentence
FROM calc c;
