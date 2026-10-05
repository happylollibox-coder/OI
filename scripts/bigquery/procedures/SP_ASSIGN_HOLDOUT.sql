-- =============================================
-- SP_ASSIGN_HOLDOUT — flips the coin ONCE per unit, and never again. Spec: architecture/HOLDOUT.md.
--
-- ── DEPLOY ORDER (holdout restart 2026-10-05, plan docs/superpowers/plans/2026-10-03-holdout-restart.md
-- Task 4 and Task 8, review fix 3) ─────────────────────────────────────────────────────────────
--   1. DE_HOLDOUT_TRIAL, its rows and V_HOLDOUT_TRIAL (Task 2);
--   2. the founding cohort (migrations/2026-10-05_holdout_t2_founding.sql, Task 3);
--   3. THIS PROCEDURE, and only then views/V_HOLDOUT_ELIGIBLE.sql (trial 2's stock literal).
--   The procedure goes BEFORE the view, and no orchestrator pass and no hand CALL may run between the
--   two (Task 8's window). The body deployed before 2026-10-05 carries trial 1's constants and
--   appends every eligible campaign it does not find among trial 1's rows. Under the new view the 5
--   Bunny campaigns are eligible, so that body's next run would append them to TRIAL 1, permanently
--   (the table is append-only), and K2 (trial 1's 69-row fingerprint) would fail for good.
--   Measured 2026-10-04 on TMP_HT2_ copies holding trial 1's 69 rows and trial 2's 59 founding
--   rows: the trial-1 body appended 0 rows under the deployed view and 5 under this branch's view,
--   all to trial 1, all Bunny (K2 then read 1: 74 rows). This body wrote 0 under the same view.
--   This body cannot go before step 1: BigQuery validates a procedure body at CREATE, and creating
--   it with no V_HOLDOUT_TRIAL failed ("Error validating procedure body ... Not found: Table").
--   Between steps 1 and 2 it finds trial 2 live with no rows and writes nothing.
--
-- ── WHICH TRIAL IT WRITES (from 2026-10-05) ──────────────────────────────────────────────────
-- The trial's constants are not literals here. They are the LIVE trial's row in V_HOLDOUT_TRIAL
-- (the append-only registry DE_HOLDOUT_TRIAL), the newest assigned_on first on a tie: trial_id,
-- seed, win_start (written as eligible_from) and win_end (written as trial_end).
-- A FOUNDING COHORT IS NEVER WRITTEN HERE. It is written once, from the list Ori approved
-- (migrations/2026-10-05_holdout_t2_founding.sql). So this procedure writes NOTHING when no trial
-- is live, and nothing into a live trial that has no rows yet; it never falls back to another
-- trial. Otherwise it appends LATE ARRIVALS only: campaigns eligible today that the live trial does
-- not hold, by the same rule from the trial's seed, assignment_rule prefixed
-- 'LATE ARRIVAL (first sight): '. A founding campaign paused later keeps its row and its arm.
-- The INSERT below is the trial-1 body byte for byte, except c_trial_id -> t.trial_id,
-- c_seed -> t.seed, c_eligible_from -> t.win_start, c_trial_end -> t.win_end and that prefix.
-- Tested 2026-10-04 on TMP_HT2_ copies (registry from its DDL and rows file, V_HOLDOUT_TRIAL's
-- date pinned to LA 2026-10-05 unless said, assignment copied from the live table with the founding
-- file run on it, this branch's eligible view; all dropped):
--   no registry row: wrote 0.  Trial 2 live, no trial-2 row: wrote 0, also on LA 10-03 with both
--   trials live (the tie-break took trial 2). The same body without the guard wrote 59 LATE ARRIVAL
--   rows into trial 2 there: a live re-draw.  Founding rows present, eligible = the population read
--   2026-10-04 (the approved 59 exactly): wrote 0, and 0 again.  One extra eligible campaign in
--   SB|UNC|GRD: exactly one row, trial 2, LATE ARRIVAL, seq 4 after the stratum's 0..3, HOLDOUT by
--   the rule, eligible_from 2026-10-06, trial_end 2027-01-26; a second call wrote 0; K1-K6 read 0.
--   Slot time: 3.6-4.8 s when it writes nothing at the guard; 111-130 s for a full run over the
--   eligible view, against 117 s for the trial-1 body on the same copy.
--
-- IDEMPOTENT BY CONSTRUCTION, and the construction is the whole safety argument: the only
-- statement that touches DE_HOLDOUT_ASSIGNMENT is a single INSERT whose source is
-- V_HOLDOUT_ELIGIBLE ANTI-JOINED against the rows already there. There is no UPDATE, no DELETE,
-- no MERGE ... WHEN MATCHED, and no CREATE OR REPLACE TABLE anywhere in this procedure. Running it
-- a hundred times in one day writes nothing after the first. That is not a convenience — an arm
-- that can be rewritten is not an arm, and a procedure that CAN rewrite it will eventually be run
-- by someone who does not know that.
--
-- (Anti-join by EQUALITY on (trial_id, unit_id) — the house rule after the NOT EXISTS/STRPOS
-- failure documented in fact_oi_bigquery_antisemi_join_needs_equality.)
--
-- ── WHAT "ASSIGN NEW UNITS ON FIRST SIGHT" MEANS, and why it is safe ──────────────────────────
-- Campaigns are created and paused constantly. A new eligible campaign appearing in October gets
-- an arm the day it appears, by the same rule, from the same seed. It CANNOT change the arm of any
-- unit already assigned, because seq_in_stratum is CONTINUED, never recomputed: the new units are
-- ranked among themselves and appended after the count already sitting in that stratum. (A naive
-- "recompute the whole sequence each day" would re-rank everybody the moment one campaign's spend
-- moved, and half the account would silently swap arms. This is the single most important line in
-- the procedure.)
-- Cost of continuation: a late arrival's position depends on when it arrived, not on its size, so
-- size-blocking is exact for the founding cohort and approximate afterwards. That is the right
-- trade — exact size balance is worth less than an arm that cannot move.
--
-- ── THE ARM DOES NOT BITE UNTIL ITS GATE OPENS ───────────────────────────────────────────────
-- Trial 1 (archived from 2026-10-05): rows written on 2026-08-19 with eligible_from = 2026-09-01.
-- Between those dates the engine ran normally on BOTH arms; SP_ENGINE_PREFLIGHT started excluding
-- holdout units on 2026-09-01. Two reasons. (1) The arms must be frozen BEFORE anyone can see how
-- the trial is going. (2) The BASE/GROWTH transition was doctrine-scheduled for Sep 15-30 with a
-- +$70.64/day shift; a structural migration landing mid-trial is a differential shock if it touches
-- one arm more than the other, so if a trial's dates must move, MOVE THEM TOGETHER, by appending a
-- registry row (DE_HOLDOUT_TRIAL), and exclude any campaign the reorg relocates from BOTH arms.
-- Trial 2: the gate opens on gate_from 2026-10-05 and the window on win_start 2026-10-06 (plan
-- §2.3); the dates live in the registry.
--
-- SEED. Trial 1: 'OI-HOLDOUT-v1|14'. Chosen by pre-declared rerandomization over seed_index 0,1,2,...
-- — first index satisfying (A1) exactly 14 holdout campaigns, (A2) holdout share of eligible 28-day
-- ad dollars in [0.18, 0.22], (A3) all five eligible families present in the holdout arm. Realized
-- at seed 14 on 2026-08-19: 14 HOLDOUT / 55 TREATED, holdout $5,137 vs treated $21,267 of 28-day
-- spend (19.45%), SB 4/14 vs 20/55, capped 4/14 vs 17/55, launch 11/14 vs 41/55, all 5 families
-- both sides. The DESIGN's placebo check on this randomization: -$72..+$35 per 14 days, against
-- +$1,505..+$2,445 for the rank-based selection placebo that made matched DiD unusable. The design
-- is unbiased. It is just imprecise — MDE $2,261 per 14 days, and see HOLDOUT.md before believing
-- any small number this trial produces.
-- Trial 2: 'OI-HOLDOUT-v2|5', the same method with A1 = ROUND(59/5) = 12: the first index passing
-- (plan §2.5, HOLDOUT.md §5). Founding cohort 12 HOLDOUT / 47 TREATED, 21.01% of the 28-day ad
-- dollars, 5 of 5 families; MDE $2,089 per 14 days.
--
-- ORDER IN THE ORCHESTRATOR: Task 20.55, immediately BEFORE SP_SNAPSHOT_ENGINE_PROPOSALS (20.6)
-- and therefore before SP_ENGINE_PREFLIGHT (20.7). The arms must exist before the day's opinions
-- are recorded, so that every proposal can be read against a known arm — the proposal is what makes
-- the holdout arm interpretable at all (see SP_ENGINE_PREFLIGHT: the judgement is recorded, only
-- the export is blocked).
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_ASSIGN_HOLDOUT`()
OPTIONS (
  description = "Assigns randomized holdout arms to LATE ARRIVALS of the LIVE trial (holdout restart, plan docs/superpowers/plans/2026-10-03-holdout-restart.md Task 4; from 2026-10-05). The trial's constants (trial_id, seed, win_start written as eligible_from, win_end written as trial_end) are the live trial's row in V_HOLDOUT_TRIAL (registry DE_HOLDOUT_TRIAL), the newest assigned_on first on a tie. A founding cohort is written once from the approved list (migrations/2026-10-05_holdout_t2_founding.sql), never here: with no live trial, or a live trial with no rows yet, it writes nothing and never falls back to another trial. Otherwise it appends campaigns eligible today that the live trial does not hold, assignment_rule prefixed 'LATE ARRIVAL (first sight): '. IDEMPOTENT AND APPEND-ONLY: the only write is one INSERT INTO DE_HOLDOUT_ASSIGNMENT whose source is V_HOLDOUT_ELIGIBLE anti-joined by equality on (trial_id, unit_id) against the rows already present — no UPDATE, no DELETE, no MERGE, no CREATE OR REPLACE TABLE. Re-running writes nothing; an already-assigned unit can never be reassigned, because ASSIGNMENT IS FROZEN FOREVER (an arm that can drift is not an experiment). Late arrivals are assigned on FIRST SIGHT by the same rule from the trial's seed, and their seq_in_stratum CONTINUES the stratum's existing sequence rather than recomputing it — a recompute would re-rank every unit the moment one campaign's spend moved and swap arms wholesale. RULE: stratum = channel|CAP-UNC|LNC-GRD frozen at assignment; seq_in_stratum = 0-based rank within stratum by spend_28d DESC then campaign_id; offset = MOD(ABS(FARM_FINGERPRINT(seed||'|'||stratum)),5); arm = HOLDOUT iff MOD(seq+offset,5)=0 — systematic 1-in-5 inside a size-ordered block. Trial 1 HOLDOUT-2026Q4-CAMPAIGN (seed 'OI-HOLDOUT-v1|14', 69 units from 2026-08-19, window 2026-09-01..2026-12-22) is archived from 2026-10-05; trial 2 HOLDOUT-2026Q4-CAMPAIGN-T2 (seed 'OI-HOLDOUT-v2|5', 59 founding units, gate 2026-10-05, window 2026-10-06..2027-01-26) is live. DEPLOY ORDER: this procedure BEFORE V_HOLDOUT_ELIGIBLE's trial-2 literal; the trial-1 body under that literal appends the 5 Bunny campaigns to trial 1. Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.55, immediately before the proposal snapshot (20.6) so the arms exist before the day's opinions are recorded against them. Spec: architecture/HOLDOUT.md."
)
BEGIN
  -- ── THE TRIAL. Its constants are the live trial's registry row, read once here; changing any of
  -- them mid-trial changes what the readout means, and they change only by appending a row to the
  -- append-only registry. Only the two below are literals.
  DECLARE c_unit_type    STRING DEFAULT 'CAMPAIGN';
  -- 1 in c_every units is held out. 5 = the design's 20% share, the cheapest cell in the power
  -- grid that clears the account's own 14-day net magnitude (MDE $2,261 vs 25%'s $2,088 for
  -- $1,413/month more and more operational risk through peak).
  DECLARE c_every        INT64  DEFAULT 5;
  DECLARE t STRUCT<trial_id STRING, seed STRING, win_start DATE, win_end DATE>;
  SET t = (SELECT AS STRUCT trial_id, seed, win_start, win_end
           FROM `onyga-482313.OI.V_HOLDOUT_TRIAL` WHERE is_live
           QUALIFY ROW_NUMBER() OVER (ORDER BY assigned_on DESC, trial_id DESC) = 1);
  -- A founding cohort is written once, from the list Ori approved (plan 2026-10-03, Task 3), never by
  -- this procedure. No live trial, or a live trial with no rows yet: write nothing.
  IF t.trial_id IS NULL
     OR (SELECT COUNT(*) FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` WHERE trial_id = t.trial_id) = 0 THEN
    RETURN;
  END IF;

  INSERT INTO `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
    (trial_id, unit_type, unit_id, unit_name, arm, stratum, seq_in_stratum, seed,
     assigned_at, eligible_from, trial_end,
     channel, family, is_capped, is_launch,
     spend_28d_at_assign, gp_28d_at_assign, net_28d_at_assign, assignment_rule)
  WITH
  -- what is already decided, and MUST NOT be touched. Equality anti-join key.
  assigned AS (
    SELECT trial_id, unit_id, stratum
    FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
    WHERE trial_id = t.trial_id AND unit_type = c_unit_type
  ),
  -- how far each stratum's systematic sequence has already run. New units continue from here;
  -- they NEVER renumber the units already placed. A stratum seen for the first time starts at 0.
  used AS (
    SELECT stratum, COUNT(*) AS n_done FROM assigned GROUP BY 1
  ),
  -- eligible today, minus everything already assigned. This is the ONLY set that gets a row.
  fresh AS (
    SELECT e.*
    FROM `onyga-482313.OI.V_HOLDOUT_ELIGIBLE` e
    LEFT JOIN assigned a
      ON a.unit_id = e.campaign_id      -- equality anti-join; a.trial_id already filtered above
    WHERE a.unit_id IS NULL
  ),
  seq AS (
    SELECT f.*,
      COALESCE(u.n_done, 0)
        + ROW_NUMBER() OVER (PARTITION BY f.stratum ORDER BY f.spend_28d DESC, f.campaign_id)
        - 1 AS seq_in_stratum,
      -- the per-stratum start of the 1-in-5 cycle. FARM_FINGERPRINT is deterministic across
      -- BigQuery runs and regions, which is what makes the assignment auditable years later.
      MOD(ABS(FARM_FINGERPRINT(CONCAT(t.seed, '|', f.stratum))), c_every) AS start_offset
    FROM fresh f
    LEFT JOIN used u ON u.stratum = f.stratum
  )
  SELECT
    t.trial_id, c_unit_type, s.campaign_id, s.campaign_name,
    IF(MOD(s.seq_in_stratum + s.start_offset, c_every) = 0, 'HOLDOUT', 'TREATED') AS arm,
    s.stratum, s.seq_in_stratum, t.seed,
    CURRENT_TIMESTAMP(), t.win_start, t.win_end,
    s.channel, s.family, s.is_capped, s.is_launch,
    s.spend_28d, s.gp_28d, s.net_28d,
    FORMAT('LATE ARRIVAL (first sight): systematic 1-in-%d within stratum ordered by spend_28d DESC; offset %d from seed %s',
           c_every,
           MOD(ABS(FARM_FINGERPRINT(CONCAT(t.seed, '|', s.stratum))), c_every),
           t.seed) AS assignment_rule
  FROM seq s;
END;
