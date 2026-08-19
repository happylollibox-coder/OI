-- =============================================
-- SP_ASSIGN_HOLDOUT — flips the coin ONCE per unit, and never again. Spec: architecture/HOLDOUT.md.
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
-- ── THE ARM DOES NOT BITE UNTIL eligible_from ────────────────────────────────────────────────
-- Rows are written on 2026-08-19 with eligible_from = 2026-09-01. Between those dates the engine
-- runs normally on BOTH arms and nothing is withheld; SP_ENGINE_PREFLIGHT only starts excluding
-- holdout units on 2026-09-01. Two reasons. (1) The arms must be frozen BEFORE anyone can see how
-- the trial is going, and that is today. (2) The BASE/GROWTH transition is doctrine-scheduled for
-- Sep 15-30 with a +$70.64/day shift; if that reorg has not landed by Sep 1, MOVE BOTH DATES
-- TOGETHER (eligible_from and trial_end here, and the matching constants in V_HOLDOUT_READOUT) and
-- exclude any campaign the reorg relocates from BOTH arms. A structural migration landing mid-trial
-- is a differential shock if it touches one arm more than the other.
--
-- SEED: 'OI-HOLDOUT-v1|14'. Chosen by pre-declared rerandomization over seed_index 0,1,2,... —
-- first index satisfying (A1) exactly 14 holdout campaigns, (A2) holdout share of eligible 28-day
-- ad dollars in [0.18, 0.22], (A3) all five eligible families present in the holdout arm. Realized
-- at seed 14 on 2026-08-19: 14 HOLDOUT / 55 TREATED, holdout $5,137 vs treated $21,267 of 28-day
-- spend (19.45%), SB 4/14 vs 20/55, capped 4/14 vs 17/55, launch 11/14 vs 41/55, all 5 families
-- both sides. The DESIGN's placebo check on this randomization: -$72..+$35 per 14 days, against
-- +$1,505..+$2,445 for the rank-based selection placebo that made matched DiD unusable. The design
-- is unbiased. It is just imprecise — MDE $2,261 per 14 days, and see HOLDOUT.md before believing
-- any small number this trial produces.
--
-- ORDER IN THE ORCHESTRATOR: Task 20.55, immediately BEFORE SP_SNAPSHOT_ENGINE_PROPOSALS (20.6)
-- and therefore before SP_ENGINE_PREFLIGHT (20.7). The arms must exist before the day's opinions
-- are recorded, so that every proposal can be read against a known arm — the proposal is what makes
-- the holdout arm interpretable at all (see SP_ENGINE_PREFLIGHT: the judgement is recorded, only
-- the export is blocked).
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_ASSIGN_HOLDOUT`()
OPTIONS (
  description = "Assigns randomized holdout arms for trial HOLDOUT-2026Q4-CAMPAIGN. IDEMPOTENT AND APPEND-ONLY: the only write is one INSERT INTO DE_HOLDOUT_ASSIGNMENT whose source is V_HOLDOUT_ELIGIBLE anti-joined by equality on (trial_id, unit_id) against the rows already present — no UPDATE, no DELETE, no MERGE, no CREATE OR REPLACE TABLE. Re-running writes nothing; an already-assigned unit can never be reassigned, because ASSIGNMENT IS FROZEN FOREVER (an arm that can drift is not an experiment). New eligible campaigns are assigned on FIRST SIGHT by the same rule from the same seed, and their seq_in_stratum CONTINUES the stratum's existing sequence rather than recomputing it — a recompute would re-rank every unit the moment one campaign's spend moved and swap arms wholesale. RULE: stratum = channel|CAP-UNC|LNC-GRD frozen at assignment; seq_in_stratum = 0-based rank within stratum by spend_28d DESC then campaign_id; offset = MOD(ABS(FARM_FINGERPRINT(seed||'|'||stratum)),5); arm = HOLDOUT iff MOD(seq+offset,5)=0 — systematic 1-in-5 inside a size-ordered block, so ~20% per stratum with size blocked implicitly. SEED 'OI-HOLDOUT-v1|14' was chosen by PRE-DECLARED rerandomization (first seed_index in 0,1,2,... satisfying: exactly 14 holdouts; holdout share of eligible 28-day ad dollars in [0.18,0.22]; all five eligible families present in the holdout arm) — the acceptance region is part of the design and the readout's permutation inference must be run inside it. Founding cohort 2026-08-19: 69 eligible campaigns, 14 HOLDOUT / 55 TREATED, $5,137 vs $21,267 of 28-day spend. eligible_from 2026-09-01, trial_end 2026-12-22: the arm does not BITE until eligible_from, so the engine runs normally on both arms until then; if the BASE/GROWTH reorg slips past Sep 1, move eligible_from, trial_end and the matching constants in V_HOLDOUT_READOUT TOGETHER. Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.55, immediately before the proposal snapshot (20.6) so the arms exist before the day's opinions are recorded against them. Spec: architecture/HOLDOUT.md."
)
BEGIN
  -- ── TRIAL CONSTANTS. Changing any of these mid-trial changes what the readout means; they are
  -- declared once, here, and mirrored (with the same values and the same warning) in
  -- V_HOLDOUT_READOUT. There is no third copy.
  DECLARE c_trial_id     STRING DEFAULT 'HOLDOUT-2026Q4-CAMPAIGN';
  DECLARE c_unit_type    STRING DEFAULT 'CAMPAIGN';
  DECLARE c_seed         STRING DEFAULT 'OI-HOLDOUT-v1|14';
  DECLARE c_eligible_from DATE  DEFAULT DATE '2026-09-01';
  DECLARE c_trial_end     DATE  DEFAULT DATE '2026-12-22';
  -- 1 in c_every units is held out. 5 = the design's 20% share, the cheapest cell in the power
  -- grid that clears the account's own 14-day net magnitude (MDE $2,261 vs 25%'s $2,088 for
  -- $1,413/month more and more operational risk through peak).
  DECLARE c_every        INT64  DEFAULT 5;

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
    WHERE trial_id = c_trial_id AND unit_type = c_unit_type
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
      MOD(ABS(FARM_FINGERPRINT(CONCAT(c_seed, '|', f.stratum))), c_every) AS start_offset
    FROM fresh f
    LEFT JOIN used u ON u.stratum = f.stratum
  )
  SELECT
    c_trial_id, c_unit_type, s.campaign_id, s.campaign_name,
    IF(MOD(s.seq_in_stratum + s.start_offset, c_every) = 0, 'HOLDOUT', 'TREATED') AS arm,
    s.stratum, s.seq_in_stratum, c_seed,
    CURRENT_TIMESTAMP(), c_eligible_from, c_trial_end,
    s.channel, s.family, s.is_capped, s.is_launch,
    s.spend_28d, s.gp_28d, s.net_28d,
    FORMAT('systematic 1-in-%d within stratum ordered by spend_28d DESC; offset %d from seed %s',
           c_every,
           MOD(ABS(FARM_FINGERPRINT(CONCAT(c_seed, '|', s.stratum))), c_every),
           c_seed) AS assignment_rule
  FROM seq s;
END;
