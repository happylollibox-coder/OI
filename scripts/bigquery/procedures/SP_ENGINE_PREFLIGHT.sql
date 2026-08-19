-- =============================================
-- SP_ENGINE_PREFLIGHT — judges the day's engine instructions for contradictions (2026-08-15).
-- Spec: architecture/ENGINE_PREFLIGHT.md. Engine-finalization plan Task 1.1.
--
-- WHY: manual preflights killed two bad upload batches in two attempts (iteration-6 cut
-- contradiction 29.9% -> ~4%; the 27 stale restores of 2026-08-15 died on a live-state check).
-- A check that runs only when someone remembers it is not a gate. This one is mechanical, daily,
-- and CHEAP: it reads ONLY the two small snapshot tables (FACT_ENGINE_PROPOSALS, the day's
-- instructions, ~200 rows; FACT_KEYWORD_GUARD, the settled records, ~600 rows) — never the
-- planner-ceiling views, whose scanning is the snapshot SP's job (Task 20.6, runs just before).
--
-- CONFLICT DOMAIN: (campaign_id, key_id, LEVER) where lever = BUDGET for grain='BUDGET',
-- NEGATE for grain='NEGATE', else BID (a REVIVE and a BID on one keyword are the same lever; a
-- bid and a budget on one campaign are two levers and no conflict). key_id = keyword_id for
-- bid/budget rows; for NEGATE rows it is the TERM TEXT (negates have no keyword_id — without the
-- term in the key, every negate in a campaign would collide into one false "conflict").
-- OWNERSHIP: LOW_STOCK > LAUNCH > OOB > REVERDICT > LIFT > COACH — the plan's precedence,
-- campaign-level cousin of FACT_PANEL_OWNERSHIP's ladder. For NEGATE the duplicate is the SAME
-- action twice, not a contradiction — the gate keeps one and marks the rest EXCLUDE anyway,
-- because one negative per term per day is also the export rule.
--
-- ── TWO INDEPENDENT SOURCES OF EXCLUSION (v27.81, 2026-08-18) ────────────────────────────────
-- 1. COLLISION-BASED (the original, above): two engines instructed the SAME (campaign, key, lever)
--    today, so the lower-ranked one is dropped. It needs a collision to fire — `n_instr > 1`.
-- 2. CLAIM-BASED (new): FACT_PANEL_OWNERSHIP says a higher panel OWNS this campaign outright,
--    whether or not that owner said anything today.
--
-- WHY 2 EXISTS — the hole 1 left, measured live 2026-08-18. FACT_PANEL_OWNERSHIP is the
-- single-home authority and today grants LOW_STOCK a FULL claim on 14 campaigns; a FULL claim
-- "evicts every lower panel on BOTH levers" (V_PANEL_OWNERSHIP header). But v27.73's REDIRECT MODE
-- made low stock deliberately STOP proposing bid and budget cuts on exactly those campaigns — it
-- re-aims the ad doorways at an in-stock sibling instead of braking. No proposal from the owner
-- means no collision, and a gate that only counts collisions saw an empty doorway and waved the
-- lower engines through: 41 GO rows from non-owner engines inside LOW_STOCK-owned, CRITICAL,
-- redirect-mode campaigns — LAUNCH 28 (all bid cuts), OOB 5, LIFT 5 (one of them a bid RAISE into
-- a family with 20 days of cover and nothing booked), COACH 3 negates.
-- The doctrine was already written one view over: "Silence from the owner is still the owner's
-- answer." The gate simply never read the claim. Now it does.
--
-- SCOPE OF THE CLAIM ARM, and every boundary is deliberate:
--   · LEVERS: BID and BUDGET only. A claim is about MONEY. NEGATE is not a money lever, so a
--     wasteful search term stays blockable inside a low-stock family.
--   · PER-CONSUMER BOOLEAN, no arithmetic here: LAUNCH reads defer_launch_panel, REVERDICT reads
--     defer_revival_panel, OOB and LIFT read defer_engine_panel. That is the whole point of
--     V_PANEL_OWNERSHIP publishing one boolean per rank — which rank evicts which panel stays a
--     one-line edit THERE and never spreads into consumers like this one.
--   · LOW_STOCK is never deferred by this arm: it is the owner, and an owner cannot defer to
--     itself. COACH is never deferred by it either.
--   · FAILS OPEN: COALESCE(defer_*, FALSE). A missing or stale ownership row must never silence
--     legitimate work — the claim only ever ADDS an exclusion where ownership positively says so.
--     (5 of today's 63 proposal campaigns have no ownership row; they are untouched.)
--   · ORDERED AFTER the collision arm, so a real collision keeps its more specific reason.
--
-- ── A THIRD INDEPENDENT SOURCE OF EXCLUSION (v27.83, 2026-08-19): HOLDOUT ────────────────────
-- 3. HOLDOUT-BASED: DE_HOLDOUT_ASSIGNMENT says this campaign is a randomized MEASUREMENT CONTROL.
--    Nothing the engine wants to do to it may be exported, on ANY lever — bid, budget or negate.
--
-- WHY, and it is not an engine-quality reason at all: Ori's question is "the main goal of ads is to
-- make more total dollars that we would do without the changes", and until now nothing in the stack
-- could answer it. Matched difference-in-differences was tried and PROVED untrustworthy on this
-- account (2026-08-18): emulate the engine's selection, do NOTHING, and the placebo still reads
-- +$1,505..+$2,445 on the losers arm and -$1,094..-$1,829 on the winners arm — about 90% of the
-- account's entire 14-day net, manufactured out of selection alone. And there is no natural control
-- to borrow: 73.5% of active keywords and 85.1% of ad dollars are touched, and the untouched pool
-- is untouched BECAUSE it is dying. So a control is CREATED by randomization, and this gate is the
-- mechanism that keeps it a control. A holdout campaign that receives even one uploaded change
-- stops being one, permanently.
--
-- *** THE PROPOSAL IS STILL RECORDED. *** This procedure has never deleted a row and does not start
-- now: FACT_ENGINE_PROPOSALS keeps the holdout campaign's instruction with its intended action and
-- its verbatim reason, and only the verdict says EXCLUDE. THAT RECORD IS THE COUNTERFACTUAL. It is
-- what lets V_HOLDOUT_READOUT compare "the engine wanted to cut AND we cut" against "the engine
-- wanted to cut AND the coin said don't" — without it the holdout arm degrades from "campaigns the
-- engine was forbidden to move" into "campaigns nothing happened to", which is a different and much
-- weaker question. BLOCK THE EXPORT, NEVER THE JUDGEMENT.
--
-- SCOPE, every boundary deliberate:
--   · ALL LEVERS. Unlike the claim arm, this one covers NEGATE too. A negative keyword is a real
--     intervention with a real dollar effect; letting negates through would make the holdout arm
--     "the engine minus its bid levers", and the readout would silently measure the wrong thing.
--   · TIME-BOUNDED. It fires only for CURRENT_DATE between eligible_from and trial_end. Before the
--     trial opens and after it closes the engine runs normally on both arms, which is what makes
--     the arms assignable today and the trial endable without a code change.
--   · FAILS OPEN. A LEFT JOIN plus COALESCE: a missing assignment table, an empty trial or an
--     unassigned campaign never silences legitimate work. The gate can only ADD an exclusion where
--     an assignment row positively says HOLDOUT.
--   · ORDERED FIRST, ahead of both the collision and claim arms. When a holdout row is also a
--     collision loser either reason is true, but only this one explains why the campaign will not
--     move for four months — and an auditor reading "LAUNCH already moved this bid today" on a
--     frozen campaign would draw the wrong conclusion about the trial.
--   · TREATED campaigns get NO special handling of any kind. Treatment IS the status quo.
--
-- VERDICTS (precedence): EXCLUDE (a randomized holdout campaign, any lever; or non-owner in a
--                                 multi-instruction domain; or a higher panel holds a full claim
--                                 on the campaign's money; or a no-op)
--                        REVIEW  (bid cut on a settled >=1.2x/>=10clk winner; or bid > $2.00 cap)
--                        GO      (everything else)
-- Verdicts are stamped back onto the day's FACT_ENGINE_PROPOSALS partition, so proposal history
-- doubles as the contradiction-rate time series.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_ENGINE_PREFLIGHT`()
OPTIONS (
  description = "Standing contradiction gate (Task 1.1, 2026-08-15; negates v27.72; panel claim v27.81, 2026-08-18; HOLDOUT v27.83, 2026-08-19). Judges the latest FACT_ENGINE_PROPOSALS partition against FACT_KEYWORD_GUARD, FACT_PANEL_OWNERSHIP and DE_HOLDOUT_ASSIGNMENT. THREE INDEPENDENT SOURCES OF EXCLUSION. (1) COLLISION-BASED, the original: single-owner per (campaign, key, lever) — key = keyword for bid/budget, the term text for NEGATE — with precedence LOW_STOCK > LAUNCH > OOB > REVERDICT > LIFT > COACH; it fires only when two engines instruct the SAME key. (2) CLAIM-BASED, new in v27.81: FACT_PANEL_OWNERSHIP is the single-home authority, and a FULL claim evicts every lower panel on BOTH levers whether or not the owner said anything today — LAUNCH defers on defer_launch_panel, REVERDICT on defer_revival_panel, OOB and LIFT on defer_engine_panel, LOW_STOCK never (it is the owner) and COACH never. WHY (2) EXISTS: v27.73's redirect mode made LOW_STOCK deliberately STOP proposing bid/budget cuts on the campaigns it owns — it re-aims ad doorways at an in-stock sibling instead of braking — so the collisions vanished and the collision-only gate waved lower-ranked engines through the empty doorway. Measured live 2026-08-18: 41 GO rows from non-owner engines inside LOW_STOCK-owned, CRITICAL, redirect-mode campaigns (LAUNCH 28 all bid cuts, OOB 5, LIFT 5 including a bid RAISE into a family with 20 days of cover and nothing booked, COACH 3 negates). Silence from the owner is still the owner's answer; the gate now reads the claim, not just the collisions. SCOPE, all boundaries deliberate: the claim arm covers lever IN ('BID','BUDGET') only (a claim is about money — NEGATE stays available, a wasteful search term must remain blockable inside a low-stock family); it FAILS OPEN via COALESCE(defer_*, FALSE) so a missing or stale ownership row never silences legitimate work; and it is ordered AFTER the collision arm so a genuine collision keeps its more specific reason. No-ops EXCLUDE; settled-winner cuts, >$2 bids and peak-converting negates REVIEW. Writes T_ENGINE_PREFLIGHT and stamps verdict/verdict_reason back onto the partition. Reads ONLY snapshot tables — runs in seconds. (3) HOLDOUT-BASED, new in v27.83 and ordered FIRST: DE_HOLDOUT_ASSIGNMENT says this campaign is a randomized MEASUREMENT CONTROL, so nothing may be exported to it on ANY lever — bid, budget AND negate — for the whole trial window (eligible_from..trial_end; the arm therefore does not bite before 2026-09-01 nor after 2026-12-22, with no code change either time). It exists because Ori's question — does the engine make more total dollars than we would without the changes — had no answerable form: matched DiD was measured on 2026-08-18 and proved untrustworthy here (a pure selection placebo reads +$1,505..+$2,445 on the losers arm, ~90% of the account's entire 14-day net) and no natural control exists (73.5% of active keywords and 85.1% of ad dollars are touched; the untouched pool is untouched because it is dying). So the control is CREATED by randomization and this gate is what keeps it one. CRITICALLY, THE PROPOSAL IS STILL RECORDED: this procedure deletes nothing, so FACT_ENGINE_PROPOSALS keeps the holdout campaign's instruction with its intended action and verbatim reason and only the verdict says EXCLUDE. That record IS the counterfactual — it lets V_HOLDOUT_READOUT compare 'the engine wanted to cut AND we cut' against 'the engine wanted to cut AND the coin said do not'. Block the export, never the judgement. Covers negates too (unlike the claim arm) because a negative keyword is a real intervention and letting them through would make the holdout arm 'the engine minus its bid levers'. Fails open on a missing row; TREATED campaigns get no special handling at all, since treatment IS the status quo. Reuses the EXCLUDE verdict deliberately so DoPage's existing export refusal enforces it with no dashboard change. Publishes is_holdout / holdout_trial_id on T_ENGINE_PREFLIGHT so an audit can tell a HOLDOUT exclusion from a CLAIM or COLLISION one. Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.7, right after the proposal snapshot; FACT_PANEL_OWNERSHIP is built earlier in the same pass by SP_SNAPSHOT_PANEL_OWNERSHIP and DE_HOLDOUT_ASSIGNMENT by SP_ASSIGN_HOLDOUT (Task 20.55). DoPage.exportBulksheet refuses EXCLUDE rows at export time. Spec: architecture/ENGINE_PREFLIGHT.md and architecture/HOLDOUT.md."
)
BEGIN
  DECLARE snap DATE DEFAULT (
    SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`);

  CREATE OR REPLACE TABLE `onyga-482313.OI.T_ENGINE_PREFLIGHT` AS
  WITH p AS (
    -- Phase 6 Task 1: ad_group_id (the upload key — the feed queues directly from the gate) and
    -- reason_short (the 5-second why, per-view rollout) ride through to T_.
    SELECT snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id,
           target_text, match_type, channel, action, current_bid, suggested_bid, current_budget,
           suggested_budget, reason, reason_short, season_relax_applied,
           CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever,
           -- the conflict key: keyword for value levers, the term itself for negates
           IF(grain = 'NEGATE',
              CONCAT('term|', LOWER(TRIM(COALESCE(target_text, '')))),
              COALESCE(keyword_id, '')) AS key_id
    FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    WHERE snapshot_date = snap
  ),
  rec AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           settled_roas90, settled_clk90
    FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`
  ),
  -- the single-home claim, one row per ENABLED campaign. GROUP BY is DEFENSIVE ONLY (verified 1:1
  -- on 2026-08-18: 93 rows over 93 distinct campaigns) — it guarantees this join can never fan the
  -- proposal set out, no matter what the ownership snapshot is rebuilt as. LOGICAL_OR is the
  -- correct collapse for a claim: if any row says a panel is evicted here, it is evicted.
  -- v27.83 THE HOLDOUT ARM. One row per randomization unit, written once and never updated by
  -- SP_ASSIGN_HOLDOUT (orchestrator 20.55, which runs before the proposal snapshot). Only HOLDOUT
  -- units are selected, and only while the trial window is open — so this CTE is empty before
  -- 2026-09-01 and empty again after 2026-12-22, with no code change either time. GROUP BY is
  -- defensive: the table's grain is already one row per (trial, unit), and collapsing here
  -- guarantees the join can never fan the proposal set out even if a second trial is ever added.
  hold AS (
    SELECT CAST(unit_id AS STRING) AS cid,
           MAX(trial_id) AS trial_id
    FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
    WHERE unit_type = 'CAMPAIGN'
      AND arm = 'HOLDOUT'
      AND CURRENT_DATE('America/Los_Angeles') BETWEEN eligible_from AND trial_end
    GROUP BY 1
  ),
  own AS (
    SELECT CAST(campaign_id AS STRING) AS cid,
           LOGICAL_OR(COALESCE(defer_launch_panel,  FALSE)) AS defer_launch_panel,
           LOGICAL_OR(COALESCE(defer_revival_panel, FALSE)) AS defer_revival_panel,
           LOGICAL_OR(COALESCE(defer_engine_panel,  FALSE)) AS defer_engine_panel,
           MAX(owner) AS owner_panel
    FROM `onyga-482313.OI.FACT_PANEL_OWNERSHIP`
    GROUP BY 1
  ),
  ranked AS (
    SELECT p.*,
      -- CLAIM-BASED DEFERRAL — one boolean per consumer rank, read straight off the ownership
      -- snapshot so this procedure carries no ladder arithmetic of its own (see header).
      -- LOW_STOCK and COACH fall to the ELSE: the owner never defers to itself, and COACH is not
      -- deferred by this arm at all. LEFT JOIN + COALESCE = FAIL OPEN on a missing/stale row.
      CASE p.engine
        WHEN 'LAUNCH'    THEN COALESCE(o.defer_launch_panel,  FALSE)
        WHEN 'REVERDICT' THEN COALESCE(o.defer_revival_panel, FALSE)
        WHEN 'OOB'       THEN COALESCE(o.defer_engine_panel,  FALSE)
        WHEN 'LIFT'      THEN COALESCE(o.defer_engine_panel,  FALSE)
        ELSE FALSE
      END AS claim_deferred,
      o.owner_panel AS claim_owner,
      -- v27.83: TRUE iff this campaign is a randomized measurement control today. Fails open —
      -- an absent row is simply not a holdout.
      (h.cid IS NOT NULL) AS is_holdout,
      h.trial_id          AS holdout_trial_id,
      ROW_NUMBER() OVER (
        PARTITION BY p.campaign_id, p.key_id, p.lever
        ORDER BY CASE p.engine
                   WHEN 'LOW_STOCK' THEN 1 WHEN 'LAUNCH' THEN 2 WHEN 'OOB' THEN 3
                   WHEN 'REVERDICT' THEN 4 WHEN 'LIFT' THEN 5 WHEN 'COACH' THEN 6 ELSE 9 END,
                 p.engine  -- total order even if two rows share an engine tier
      ) AS own_rank,
      COUNT(*) OVER (PARTITION BY p.campaign_id, p.key_id, p.lever) AS n_instr,
      -- the owner's engine name, for the EXCLUDE reason
      FIRST_VALUE(p.engine) OVER (
        PARTITION BY p.campaign_id, p.key_id, p.lever
        ORDER BY CASE p.engine
                   WHEN 'LOW_STOCK' THEN 1 WHEN 'LAUNCH' THEN 2 WHEN 'OOB' THEN 3
                   WHEN 'REVERDICT' THEN 4 WHEN 'LIFT' THEN 5 WHEN 'COACH' THEN 6 ELSE 9 END,
                 p.engine
      ) AS owner_engine
    FROM p
    LEFT JOIN own o  ON o.cid = CAST(p.campaign_id AS STRING)
    LEFT JOIN hold h ON h.cid = CAST(p.campaign_id AS STRING)
  )
  SELECT r.snapshot_date, r.engine, r.grain, r.lever, r.campaign_id, r.campaign_name,
         r.keyword_id, r.ad_group_id, r.target_text, r.match_type, r.channel, r.action,
         r.current_bid, r.suggested_bid, r.current_budget, r.suggested_budget, r.reason, r.reason_short, r.season_relax_applied,
         r.own_rank, r.n_instr, r.owner_engine,
         r.claim_deferred, r.claim_owner,
         r.is_holdout, r.holdout_trial_id,
         rc.settled_roas90, rc.settled_clk90,
         CURRENT_TIMESTAMP() AS preflight_at,
    CASE
      -- v27.83 HOLDOUT, ordered FIRST and covering EVERY lever. This is not a judgement about the
      -- instruction — the instruction may be perfectly good, and it is kept in full in
      -- FACT_ENGINE_PROPOSALS as the trial's counterfactual. It simply must not be exported.
      WHEN r.is_holdout THEN 'EXCLUDE'
      WHEN r.n_instr > 1 AND r.own_rank > 1 THEN 'EXCLUDE'
      -- v27.81 CLAIM-BASED: a higher panel owns this campaign's money outright. Money levers only
      -- — NEGATE is not covered, so a wasteful term stays blockable in a low-stock family.
      WHEN r.lever IN ('BID', 'BUDGET') AND r.claim_deferred THEN 'EXCLUDE'
      WHEN r.lever = 'BID'
        AND ABS(COALESCE(r.suggested_bid, 0) - COALESCE(r.current_bid, 0)) <= 0.005 THEN 'EXCLUDE'
      WHEN r.lever = 'BUDGET'
        AND ABS(COALESCE(r.suggested_budget, 0) - COALESCE(r.current_budget, 0)) <= 0.005 THEN 'EXCLUDE'
      WHEN r.lever = 'BID' AND r.suggested_bid < COALESCE(r.current_bid, 0) - 0.005
        AND COALESCE(rc.settled_roas90, 0) >= 1.2 AND COALESCE(rc.settled_clk90, 0) >= 10 THEN 'REVIEW'
      WHEN r.lever = 'BID' AND r.suggested_bid > 2.00 THEN 'REVIEW'
      -- v27.72: a negate on a term that converted in past gift peaks — the coach view's own
      -- warning ("converts in peak → keep/seasonal, don't negate"); never a silent GO
      WHEN r.lever = 'NEGATE' AND COALESCE(r.season_relax_applied, FALSE) THEN 'REVIEW'
      -- live-regression find: season-relaxed revivals are the panel's hand-check class — the
      -- bulk feed must not GO them
      WHEN COALESCE(r.season_relax_applied, FALSE) THEN 'REVIEW'
      ELSE 'GO' END AS verdict,
    CASE
      -- audit rewrites: plain words, no house slogans
      -- v27.83 HOLDOUT. The plainest sentence in the gate, because it will be read by someone
      -- wondering why a campaign has not moved in months.
      WHEN r.is_holdout
        THEN 'skipped — this campaign is a measurement control: it was randomly chosen to be left alone so we can tell what the engine is actually worth, and no bid, budget or negative may be uploaded to it until the trial ends'
      WHEN r.n_instr > 1 AND r.own_rank > 1 AND r.lever = 'NEGATE'
        THEN CONCAT('skipped — ', r.owner_engine, ' already blocks this term today (one negative per term per day)')
      WHEN r.n_instr > 1 AND r.own_rank > 1
        THEN CONCAT('skipped — ', r.owner_engine, ' already moves this ',
                    IF(r.lever = 'BUDGET', 'budget', 'bid'), ' today (one change per keyword per day)')
      -- v27.81 CLAIM-BASED. The owner said nothing about this key today and that IS the answer.
      WHEN r.lever IN ('BID', 'BUDGET') AND r.claim_deferred
        THEN CONCAT('skipped — ',
                    IF(r.claim_owner = 'LOW_STOCK', 'low stock', LOWER(COALESCE(r.claim_owner, 'a higher panel'))),
                    ' owns this campaign today and chose not to brake its ',
                    IF(r.lever = 'BUDGET', 'budget', 'bid'), ' (nothing else may)')
      WHEN r.lever = 'BID'
        AND ABS(COALESCE(r.suggested_bid, 0) - COALESCE(r.current_bid, 0)) <= 0.005
        THEN 'no change — the suggested value equals the current one'
      WHEN r.lever = 'BUDGET'
        AND ABS(COALESCE(r.suggested_budget, 0) - COALESCE(r.current_budget, 0)) <= 0.005
        THEN 'no change — the suggested value equals the current one'
      WHEN r.lever = 'BID' AND r.suggested_bid < COALESCE(r.current_bid, 0) - 0.005
        AND COALESCE(rc.settled_roas90, 0) >= 1.2 AND COALESCE(rc.settled_clk90, 0) >= 10
        THEN CONCAT('cuts a proven winner — ', FORMAT('%.2f', rc.settled_roas90), 'x over ',
                    CAST(rc.settled_clk90 AS STRING), ' clicks of full data; check before sending')
      WHEN r.lever = 'BID' AND r.suggested_bid > 2.00
        THEN CONCAT('suggested $', CAST(r.suggested_bid AS STRING), ' is above the $2.00 house cap')
      WHEN r.lever = 'NEGATE' AND COALESCE(r.season_relax_applied, FALSE)
        THEN 'this term bought in past gift peaks — a seasonal keep, check before blocking'
      WHEN COALESCE(r.season_relax_applied, FALSE)
        THEN "its own record loses money; the revival rests on last season's win — check before sending"
      ELSE NULL END AS verdict_reason
  FROM ranked r
  LEFT JOIN rec rc
    ON rc.cid = r.campaign_id AND rc.kid = COALESCE(r.keyword_id, '');

  -- stamp the verdicts back onto the day's proposal history. target_text joins too (v27.72):
  -- NEGATE rows share (engine, campaign, NULL keyword, grain) — without the term in the join,
  -- every negate in a campaign would take the same stamped verdict.
  UPDATE `onyga-482313.OI.FACT_ENGINE_PROPOSALS` f
  SET f.verdict = t.verdict, f.verdict_reason = t.verdict_reason
  FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT` t
  WHERE f.snapshot_date = snap
    AND f.engine = t.engine
    AND f.campaign_id = t.campaign_id
    AND COALESCE(f.keyword_id, '') = COALESCE(t.keyword_id, '')
    AND COALESCE(f.target_text, '') = COALESCE(t.target_text, '')
    AND f.grain = t.grain;
END;
