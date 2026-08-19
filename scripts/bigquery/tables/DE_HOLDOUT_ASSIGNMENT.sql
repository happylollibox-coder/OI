-- =============================================
-- DE_HOLDOUT_ASSIGNMENT — the randomized arms. THE most safety-critical table in the ads stack,
-- because it is the only one whose VALUE comes from never changing. Spec: architecture/HOLDOUT.md.
--
-- ONE ROW PER RANDOMIZATION UNIT, FOREVER. unit_type = 'CAMPAIGN' (see V_HOLDOUT_ELIGIBLE for why
-- the campaign and not the keyword). A row is written ONCE, by SP_ASSIGN_HOLDOUT, on the first day
-- the unit is seen eligible, and is NEVER updated and NEVER deleted. An arm that can drift is not
-- an experiment — it is a story about the past told by whoever last ran the query.
--
-- WHY A TABLE AND NOT A VIEW. A view would recompute the arms from today's data every time it is
-- read: a campaign that changes cap state, graduates out of the launch population, or moves family
-- would silently change arm, and the readout would then compare "campaigns that ended up looking
-- like X" against "campaigns that ended up looking like Y" — which is the selection artifact that
-- made the matched difference-in-differences unusable here in the first place (+$1,505..+$2,445 of
-- pure placebo on a rank-selected arm, ~90% of the account's entire 14-day net). The whole point of
-- randomization is that the arms were fixed BEFORE the outcome existed. That property lives in this
-- table's immutability and nowhere else.
--
-- THE ASSIGNMENT RULE, reproducible from these columns alone:
--   stratum        = channel | CAP/UNC | LNC/GRD   (frozen at assignment; see V_HOLDOUT_ELIGIBLE)
--   seq_in_stratum = rank within stratum ORDER BY spend_28d DESC, campaign_id, 0-based, continued
--                    (never recomputed) as later units are appended
--   offset         = MOD(ABS(FARM_FINGERPRINT(CONCAT(seed, '|', stratum))), 5)
--   arm            = HOLDOUT iff MOD(seq_in_stratum + offset, 5) = 0, else TREATED
-- Systematic 1-in-5 inside a size-ordered block: exactly ~20% per stratum by construction, with
-- size blocked implicitly because every consecutive run of five is a run of neighbours in spend.
--
-- THE SEED WAS CHOSEN BY PRE-DECLARED RERANDOMIZATION, and the rule was declared before the draws
-- were looked at (Morgan & Rubin): search seed_index = 0, 1, 2, ... and take the FIRST that
-- satisfies all three criteria taken verbatim from the design — (A1) exactly 14 holdout campaigns,
-- the design's recommended 20% share of 69; (A2) the holdout arm's share of eligible 28-day ad
-- dollars inside [0.18, 0.22]; (A3) all five eligible families present in the holdout arm, since
-- family is a stratum precisely to control organic halo. seed_index 14 is the first pass; 0-13 all
-- fail (6 and 8 give 15 holdouts, 10 covers only 4 families, the rest miss the dollar band). The
-- acceptance region is part of the design and the readout's permutation inference must be run
-- INSIDE it — permute only over assignments that would also have been accepted.
--
-- WHAT INVALIDATES THE TRIAL (each of these destroys the answer, not just degrades it):
--   · UPDATE or DELETE on this table. Re-randomizing after seeing outcomes is not a fix for an
--     unlucky draw; it is the manufacture of the result you wanted.
--   · Hand-uploading a bid, budget or negative for a HOLDOUT campaign. The holdout arm's contract
--     is that NO instruction reaches it, from the engine or from a person.
--   · Deliberately moving budget from the holdout arm to the treated arm (or the reverse). That
--     makes the arms trade with each other and the difference stops being an effect.
--   · Pulling a holdout unit out mid-trial for a reason correlated with its performance or its
--     stock. Use the symmetric censoring rule in HOLDOUT.md instead.
-- See architecture/HOLDOUT.md for the full list and for what the readout will and will not cover.
--
-- WRITTEN BY: SP_ASSIGN_HOLDOUT (orchestrator Task 20.55, immediately BEFORE the proposal
-- snapshot 20.6 — the arms must exist before the day's opinions are recorded against them).
-- READ BY: SP_ENGINE_PREFLIGHT (the export gate) and V_HOLDOUT_READOUT (the answer).
-- =============================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` (
  trial_id          STRING    NOT NULL,  -- 'HOLDOUT-2026Q4-CAMPAIGN'. A second trial gets a new id and its own rows.
  unit_type         STRING    NOT NULL,  -- 'CAMPAIGN' — the randomization unit
  unit_id           STRING    NOT NULL,  -- campaign_id AS STRING (19-digit ids exceed 2^53; STRING end to end)
  unit_name         STRING,              -- campaign_name at assignment, for humans only
  arm               STRING    NOT NULL,  -- 'HOLDOUT' | 'TREATED'
  stratum           STRING    NOT NULL,  -- channel|CAP/UNC|LNC/GRD, FROZEN at assignment
  seq_in_stratum    INT64     NOT NULL,  -- 0-based position in the size-ordered systematic sequence
  seed              STRING    NOT NULL,  -- 'OI-HOLDOUT-v1|14' — the full offset key prefix
  assigned_at       TIMESTAMP NOT NULL,  -- when the coin was flipped
  eligible_from     DATE      NOT NULL,  -- the arm only BITES from this date; before it the engine runs normally on both arms
  trial_end         DATE      NOT NULL,  -- last day the holdout is enforced
  -- ── the blocking facts, FROZEN at assignment (intention-to-treat) ──────────────────────────
  -- A campaign that graduates out of the launch population, starts or stops capping, or changes
  -- family mid-trial KEEPS these values and KEEPS its arm. Re-deriving them later would let the
  -- strata drift with the outcome, which is the artifact the trial exists to avoid.
  channel           STRING,              -- SP | SB
  family            STRING,              -- parent_name at assignment
  is_capped         BOOL,                -- V_CAMPAIGN_CAP_STATE.is_oob_owned at assignment
  is_launch         BOOL,                -- V_LAUNCH_POPULATION membership at assignment
  spend_28d_at_assign FLOAT64,           -- the size the block was built on
  gp_28d_at_assign    FLOAT64,           -- gross profit, same window — the pre-period baseline
  net_28d_at_assign   FLOAT64,           -- gp - spend: the pre-trial level, published so the readout can adjust for it
  assignment_rule   STRING               -- one line naming the rule that produced this row, for audit
)
CLUSTER BY unit_id
OPTIONS (description = 'The randomized holdout arms — one row per randomization unit, WRITTEN ONCE AND NEVER UPDATED. unit_type=CAMPAIGN; arm HOLDOUT|TREATED; stratum = channel|CAP/UNC|LNC/GRD frozen at assignment; systematic 1-in-5 inside a size-ordered block with a per-stratum offset MOD(ABS(FARM_FINGERPRINT(seed||stratum)),5); seed OI-HOLDOUT-v1|14 chosen by pre-declared rerandomization (first seed_index satisfying: exactly 14 holdouts, holdout dollar share in [0.18,0.22], all five eligible families represented). Eligibility comes from V_HOLDOUT_ELIGIBLE. Written by SP_ASSIGN_HOLDOUT (orchestrator Task 20.55, before the proposal snapshot); read by SP_ENGINE_PREFLIGHT (the export gate, all levers) and V_HOLDOUT_READOUT (the answer). THE VALUE OF THIS TABLE IS THAT IT NEVER CHANGES: UPDATE, DELETE or re-randomization after outcomes exist invalidates the trial outright, as does hand-uploading to a HOLDOUT campaign or moving budget between arms. Spec: architecture/HOLDOUT.md.');
