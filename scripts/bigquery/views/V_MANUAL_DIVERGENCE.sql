-- =============================================
-- V_MANUAL_DIVERGENCE — every manual change vs what the engine said that day (2026-08-16, Task 3.1).
-- Spec: architecture/MANUAL_DIVERGENCE.md.
--
-- THE DOCTRINE (Ori 2026-08-11, verbatim): "i preffer fixing the model then supporting manual —
-- the goal is that the engine will be 100% auto — if i change something manually you should ask
-- why and if it is the right decision. if so we need to fix the model." This view mechanizes the
-- asking. Every source='MANUAL' change is classified against the engine's own proposal snapshot
-- for the day it was applied, then graded by the scorecard at the honest lag:
--
--   kind: AGREED         manual value ≈ the engine's proposal (±5%) — Ori applied the coach by
--                        hand; NEVER count agreement as disagreement (Task 0.2 found ~8 such rows).
--                        A manual NEGATE with a same-day engine negate on the term is AGREED too
--                        (v27.72 — a negate has no value to diverge from)
--         OVERRODE       the engine proposed differently that day — the divergence that matters
--         ENGINE_SILENT  no proposal on that key+lever that day — the human saw what the engine
--                        did not, which is a MODEL GAP, not a human error
--         LEVER_NOT_SNAPSHOTTED  pauses, hero swaps etc. — levers the snapshot does not carry
--                        (negates graduated OUT of this class in v27.72)
--   era:  PRE_SNAPSHOT   applied before 2026-08-15 (no proposal memory exists) — graded on its
--                        own scorecard verdict alone, kind necessarily UNKNOWN
--
--   judgment (settled rows only): MANUAL_BETTER (OVERRODE + CONFIRMED — the hand beat the model:
--   a rule should change), ENGINE_BETTER (OVERRODE + REVERSED — the model was right: the hold
--   doctrine earned its keep), TIE (OVERRODE + NEUTRAL), else GRADED_<verdict> / PENDING.
--
-- Every MANUAL_BETTER row must end as either a threshold change (V_THRESHOLD_TUNER) or a
-- documented disagreement — that is the SOP's closing rule. Planner: the scorecard (ceiling
-- view) appears once, filtered to MANUAL; everything else is small.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_MANUAL_DIVERGENCE` AS
WITH m AS (
  -- v27.72: negates are a snapshotted lever now. A manual negate keys on the TERM (kid stays the
  -- keyword for value levers); NEGATE has no value, so kind for it is AGREED when the engine
  -- proposed the same negate that day, else ENGINE_SILENT — never OVERRODE.
  SELECT change_id, CAST(campaign_id AS STRING) AS cid,
         action, applied_at, DATE(applied_at, 'America/Los_Angeles') AS applied_day,
         targeting, old_bid, new_bid, old_budget, new_budget,
         CASE WHEN action LIKE '%BUDGET%' THEN 'BUDGET'
              WHEN action IN ('INCREASE_BID', 'REDUCE_BID', 'BOOST', 'SCALE_UP') THEN 'BID'
              WHEN action IN ('NEGATE_TERM', 'NEGATE_EXACT', 'NEGATE_PHRASE', 'NEGATE_BOOST_SIMILAR_EXACT') THEN 'NEGATE'
              ELSE 'OTHER' END AS lever,
         CASE WHEN action IN ('NEGATE_TERM', 'NEGATE_EXACT', 'NEGATE_PHRASE', 'NEGATE_BOOST_SIMILAR_EXACT')
              THEN CONCAT('term|', LOWER(TRIM(COALESCE(search_term, targeting, ''))))
              ELSE CAST(keyword_id AS STRING) END AS kid
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE source = 'MANUAL'
),
p AS (
  SELECT snapshot_date, campaign_id AS cid,
         IF(grain = 'NEGATE', CONCAT('term|', LOWER(TRIM(COALESCE(target_text, '')))),
            COALESCE(keyword_id, '')) AS kid,
         CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever,
         engine, action AS engine_action,
         suggested_bid, suggested_budget, verdict AS preflight_verdict, reason AS engine_reason
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  -- review find: without this, a manual change on a multi-engine key fans out into several
  -- divergence rows. The OWNING instruction is the engine's voice; excluded rows are not.
  WHERE COALESCE(verdict, '') != 'EXCLUDE'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY snapshot_date, campaign_id,
                 IF(grain = 'NEGATE', CONCAT('term|', LOWER(TRIM(COALESCE(target_text, '')))),
                    COALESCE(keyword_id, '')),
                 CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END
    ORDER BY CASE engine WHEN 'LOW_STOCK' THEN 1 WHEN 'LAUNCH' THEN 2 WHEN 'OOB' THEN 3
                         WHEN 'REVERDICT' THEN 4 WHEN 'LIFT' THEN 5 WHEN 'COACH' THEN 6 ELSE 9 END) = 1
),
sc AS (
  SELECT change_id, verdict, verdict_reason, remedy_value,
         win_gp_roas, prior_gp_roas, prior_available, read_gate_date
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD`
  WHERE source = 'MANUAL'
),
cls AS (
  SELECT m.*,
    p.engine, p.engine_action, p.suggested_bid, p.suggested_budget, p.engine_reason,
    IF(m.applied_day < DATE '2026-08-15', 'PRE_SNAPSHOT', 'SNAPSHOT') AS era,
    CASE
      WHEN m.applied_day < DATE '2026-08-15' THEN 'UNKNOWN'
      WHEN m.lever = 'OTHER' THEN 'LEVER_NOT_SNAPSHOTTED'
      WHEN p.cid IS NULL THEN 'ENGINE_SILENT'
      -- a negate has no value to diverge from: the engine proposing the same block IS agreement
      WHEN m.lever = 'NEGATE' THEN 'AGREED'
      WHEN m.lever = 'BID' AND p.suggested_bid IS NOT NULL
       AND ABS(COALESCE(m.new_bid, 0) - p.suggested_bid) <= 0.05 * p.suggested_bid THEN 'AGREED'
      WHEN m.lever = 'BUDGET' AND p.suggested_budget IS NOT NULL
       AND ABS(COALESCE(m.new_budget, 0) - p.suggested_budget) <= 0.05 * p.suggested_budget THEN 'AGREED'
      ELSE 'OVERRODE' END AS kind
  FROM m
  LEFT JOIN p ON p.snapshot_date = m.applied_day AND p.cid = m.cid
             AND p.kid = COALESCE(m.kid, '') AND p.lever = m.lever
)
SELECT c.*,
  sc.verdict AS outcome_verdict, sc.verdict_reason AS outcome_reason,
  sc.remedy_value, sc.win_gp_roas, sc.prior_gp_roas, sc.read_gate_date,
  CASE
    WHEN sc.verdict IS NULL THEN 'PENDING'
    WHEN sc.verdict = 'INSUFFICIENT' THEN 'INSUFFICIENT'
    WHEN c.kind = 'OVERRODE' AND sc.verdict = 'CONFIRMED' THEN 'MANUAL_BETTER'
    WHEN c.kind = 'OVERRODE' AND sc.verdict = 'REVERSED' THEN 'ENGINE_BETTER'
    WHEN c.kind = 'OVERRODE' THEN 'TIE'
    ELSE CONCAT('GRADED_', sc.verdict) END AS judgment,
  -- the question, per the doctrine — asked only where there is a real disagreement to resolve
  CASE
    WHEN c.kind = 'OVERRODE' AND sc.verdict IS NOT NULL AND sc.verdict != 'INSUFFICIENT' THEN
      CONCAT('you set ', COALESCE(CAST(COALESCE(c.new_bid, c.new_budget) AS STRING), '?'),
             ' where the engine (', COALESCE(c.engine, '?'), ') said ',
             COALESCE(c.engine_action, '?'), ' ',
             COALESCE(CAST(COALESCE(c.suggested_bid, c.suggested_budget) AS STRING), '(no value)'),
             ' — settled verdict ', sc.verdict,
             IF(sc.verdict = 'CONFIRMED', '. Your call won: which engine rule should change?',
                IF(sc.verdict = 'REVERSED', '. The engine had it: the hold doctrine earned its keep here.',
                   '. A wash — no rule change indicated.')))
    WHEN c.kind = 'ENGINE_SILENT' AND sc.verdict = 'CONFIRMED' THEN
      'the engine proposed NOTHING here and your change was CONFIRMED — a model gap: what did you see that it did not?'
    ELSE NULL END AS question
FROM cls c
LEFT JOIN sc ON sc.change_id = c.change_id;
