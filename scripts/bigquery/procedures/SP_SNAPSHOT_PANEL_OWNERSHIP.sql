-- =============================================
-- SP_SNAPSHOT_PANEL_OWNERSHIP — materializes V_PANEL_OWNERSHIP into FACT_PANEL_OWNERSHIP
-- (v27.81, 2026-08-18; was v27.78 / v27.77 / v27.62, 2026-08-13).
-- Spec: architecture/PANEL_OWNERSHIP.md.
--
-- v27.81 — NO LOGIC CHANGE HERE EITHER. Both steps are byte-identical; only the description below
-- moves. Three hygiene items landed in the views: (1) claim_reason now has a hard 80-char guard
-- that drops whole clauses least-informative-first instead of overrunning — the longest live reason
-- was 79 of 80 with an unconditionally-appended clause, i.e. one data point from breaching;
-- (2) ls_redirect_mode is family-propagated like risk_state, closing the THROTTLE-day hole where a
-- re-aiming family's never-served campaign fell through unowned (latent, n_missed_fam = 0);
-- (3) binding_asin is published on the CAMPAIGN branch of V_LOW_STOCK_ADS and on this snapshot, so
-- serves_only_binding is reproducible from published columns. FACT_PANEL_OWNERSHIP gains two
-- ADDITIVE columns (binding_asin, ls_redirect_mode_row) and ls_redirect_mode now carries the
-- family-propagated value; owner / owner_rank / claim_rank / claim_scope / defer_* are unchanged on
-- every row. The step order matters for item 3 exactly as it did for v27.78: step 1 must rebuild the
-- T_ from the new V_LOW_STOCK_ADS before step 2 reads the newly-populated column out of it.
--
-- v27.78 — NO LOGIC CHANGE HERE. Both steps are untouched; only the description below is updated,
-- to name the THIRD basis a low-stock claim can now rest on. V_LOW_STOCK_ADS' CAMPAIGN branch now
-- publishes the real redirect_mode (it was NULL), so the step-1 slice carries it and arm B in
-- V_PANEL_OWNERSHIP can claim a family that low stock is RE-AIMING rather than braking. Worth
-- stating in this file because the ordering contract is what makes it work: step 1 must rebuild
-- the T_ from the new view before step 2 reads the new column out of it.
--
-- WHY A SNAPSHOT (identical doctrine to SP_SNAPSHOT_PARK_REVERDICT / SP_SNAPSHOT_KEYWORD_GUARD):
-- V_PANEL_OWNERSHIP reads the low-stock engine, whose own header records that it sits AT BigQuery's
-- query-planning ceiling — it drags the entire inventory chain (fam_state -> fam_agg ->
-- asin_shares -> V_SUPPLY_CHAIN_SUMMARY -> V_PLAN_FORECAST) plus a full FACT_AMAZON_ADS target
-- scan. The consumers (V_OOB_BUDGET_PHASE, V_OOB_KEYWORD, V_KEYWORD_LIFT, V_RUN_TARGET,
-- V_KEYWORD_GUARD, V_CHANGE_SCORECARD, V_PARK_REVERDICT) are at that ceiling themselves. That
-- subtree must never enter an engine plan. They LEFT JOIN this table instead — ~95 rows, one per
-- ENABLED campaign.
--
-- ── v27.77 — THIS PROCEDURE IS NOW TWO STEPS, AND THE ORDER IS THE CONTRACT ──────────────────
--   STEP 1  T_LOW_STOCK_CAMPAIGN  = SELECT * FROM V_LOW_STOCK_ADS
--                                   WHERE row_kind='CAMPAIGN' AND campaign_id IS NOT NULL
--   STEP 2  FACT_PANEL_OWNERSHIP  = SELECT * FROM V_PANEL_OWNERSHIP   (which reads step 1)
--
-- WHY: the snapshot itself stopped planning. V_PANEL_OWNERSHIP INLINED V_LOW_STOCK_ADS, and
-- V_LOW_STOCK_ADS grew twice on 2026-08-17 — v27.73 (redirect mode: rmode/hero CTEs + 5 published
-- columns) and v27.74 (complete-day windows). The 10:50 IDT build succeeded; the 16:24 run FAILED
-- with "Resources exceeded ... Not enough resources for query planning - too many subqueries or
-- query is too complex", and after that even `SELECT COUNT(*) FROM V_PANEL_OWNERSHIP` failed
-- deterministically on a dry run. Unfixed, the 07:50 UTC orchestrator pass fails and ownership
-- goes stale — which silently breaks the single-home ladder, DEFER_* routing and panel membership,
-- because every consumer LEFT JOINs this table and a missing/stale row reads as "no claim".
-- The fix is the house pattern for planner blowups (fact_oi_cube_table_planner_blowup): never
-- inline a ceiling view — read a T_ materialized earlier in the SAME procedure. Splitting the
-- plan in two is the whole remedy; each half plans comfortably on its own.
--
-- T_LOW_STOCK_CAMPAIGN IS A MATERIALIZATION, NEVER A TRANSFORMATION. It is a pure pass-through
-- slice — `SELECT *` plus the row_kind/campaign_id predicate, no aggregation, no projection, no
-- rename. All the ownership logic (the ls_camp per-campaign roll-up, the two claim arms, the
-- ladder) stays exactly where it was, in V_PANEL_OWNERSHIP. Nothing semantic moved out, so the
-- view remains the single readable definition of who owns a campaign. Small by construction:
-- 14 rows @ 2026-08-17.
--
-- Both steps are fully derived and idempotent: CREATE OR REPLACE TABLE from a view. Step 1 must
-- run first on every invocation — T_LOW_STOCK_CAMPAIGN is not durable state, it is this
-- procedure's own scratch, and a stale step 1 would make step 2 quietly re-publish yesterday's
-- stock verdicts.
--
-- STALE-SNAPSHOT DIRECTION IS SAFE, and worth stating precisely because a claim is a silencer:
--   · a stale CLAIM (family recovered, snapshot still says CRITICAL) leaves a campaign deferred
--     for up to one refresh cycle. Cost: the engines skip a raise for a day. Harmless.
--   · a stale NON-claim (family just turned CRITICAL, snapshot not rebuilt yet) is the direction
--     that matters, and it cannot outrun its own evidence: the claim's inputs are
--     FACT_INVENTORY_SNAPSHOT (loaded once a day) and the ads anchor (once a day). This snapshot
--     is rebuilt in the same daily pass that loads them, so it is never more stale than the
--     evidence a claim could possibly be taken on.
--
-- Called by SP_ORCHESTRATE_DAILY_REFRESH — AFTER FACT_INVENTORY_SNAPSHOT and the ads FACT load
-- (V_LOW_STOCK_ADS reads both) and BEFORE the engine T_ builds in SP_REFRESH_CUBE_TABLES, so the
-- engines compile against the ownership of the run they are part of.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_PANEL_OWNERSHIP`()
OPTIONS (
  description = "Panel-ownership snapshot (v27.81, 2026-08-18; was v27.78 / v27.77 / v27.62). v27.81 IS HYGIENE ONLY AND MOVES ZERO OWNERS (verified: owner / claim_rank / defer_* identical on all 93 rows) — three items out of the v27.78 verifier pass, all in the views, none in this procedure. (1) claim_reason CAN NO LONGER OVERRUN ITS 80-CHARACTER BUDGET: the longest live reason was 79 of 80 ('LolliBall CRITICAL - 42d cover, cut to $51.35, low stock is re-aiming these ads') and the re-aiming clause is appended UNCONDITIONALLY, so a 3-digit cover value, a >= $100 budget or a longer family name breached it by construction; the budget is now held by dropping WHOLE CLAUSES least-informative-first (cover days, then the cut, then the re-aiming note — each is also published as its own column, so a drop costs a glance and never a fact), with word-boundary truncation only as a last resort and never a mid-word cut. (2) ls_redirect_mode IS NOW FAMILY-PROPAGATED, like risk_state: it was a COALESCE off a LEFT JOIN, so a campaign the low-stock engine has no CAMPAIGN row for read FALSE, and on a THROTTLE day (arm A fires only on CRITICAL) a campaign of a RE-AIMING family that had never delivered an impression would fall through to rank 4 unowned with the bid engines free to raise into a stock problem — the exact hole v27.78 was written to close, left open on the one population arm A cannot cover. redirect_mode is family-constant so the window is an identity; LATENT closure, n_missed_fam = 0 today, zero live change. (3) binding_asin IS PUBLISHED (additive) on V_LOW_STOCK_ADS' CAMPAIGN branch and on this snapshot: serves_only_binding and the v27.80 redirect proposal gate are comparisons against an ASIN that was internal to the engine, so a panel could read the boolean but neither reproduce it nor name the variation it referred to. No new join on either side — rmc was already joined for the gate, ls_camp was already rolling up that grain. FACT_PANEL_OWNERSHIP therefore gains two ADDITIVE columns (binding_asin, ls_redirect_mode_row) and ls_redirect_mode now carries the family-propagated value (the one the claim is taken on), exactly the low_stock_state / low_stock_state_row pattern already published beside it. The step order below is what makes item 3 work, the same way it made v27.78 work: step 1 must rebuild the T_ from the new V_LOW_STOCK_ADS before step 2 reads the newly-populated column out of it. THREE BASES FOR A LOW-STOCK CLAIM as of v27.78 (arm A structural: family risk_state='CRITICAL'; arm B instructed: a campaign-row suggested budget, OR >=1 proposal target, OR — new — the family is in REDIRECT MODE). The third basis exists because v27.73 silenced the first two exactly where they mattered most: in redirect mode the engine re-aims ad doorways at an in-stock sibling instead of braking, so bid- and budget-cut rows are priced but NOT proposed, which collapsed ls_proposal_targets to 0 on 10 of 14 low-stock campaigns and left 5 of them (BALL-SP/AUTO (White), BUNNY - COMPETITORS, BUNNY-SP/AUTO (Birthday), BUNNY-VIDEO/BROAD (Hunter), VIDEO- COMP/BALL) carrying NEITHER signal — claimed today only because arm A happens to fire. The moment a redirect-mode family grades THROTTLE rather than CRITICAL, arm A would be silent and arm B blind, leaving the bid engines free to raise into a stock problem. THROTTLE, not WATCH: redirect_mode requires a THROTTLE/CRITICAL binding grade and the family inherits the binding grade whenever it is not OK, so a re-aiming family can never read WATCH — arm A covers CRITICAL, this arm covers THROTTLE with both money signals silent. A family being RE-AIMED is low stock ACTING. NO LOGIC MOVED INTO THIS PROCEDURE for it — the claim still lives entirely in V_PANEL_OWNERSHIP; what makes it work here is the step order, because step 1 must rebuild the slice from the new V_LOW_STOCK_ADS (whose CAMPAIGN branch now publishes the real redirect_mode instead of NULL) before step 2 reads that column out of it. TWO STEPS, AND THE ORDER IS THE CONTRACT: (1) CREATE OR REPLACE TABLE T_LOW_STOCK_CAMPAIGN AS SELECT * FROM V_LOW_STOCK_ADS WHERE row_kind='CAMPAIGN' AND campaign_id IS NOT NULL — a PURE PASS-THROUGH SLICE, no aggregation and no transformation, 14 rows @ 2026-08-17; then (2) CREATE OR REPLACE TABLE FACT_PANEL_OWNERSHIP AS SELECT * FROM V_PANEL_OWNERSHIP, whose ls_camp CTE reads that table. WHY STEP 1 EXISTS: V_PANEL_OWNERSHIP used to INLINE V_LOW_STOCK_ADS, which was enlarged twice on 2026-08-17 (v27.73 redirect mode — rmode/hero CTEs + 5 published columns; v27.74 complete-day windows) and pushed the combined plan past BigQuery's ceiling — the 16:24 run failed with 'Not enough resources for query planning - too many subqueries or query is too complex' and even SELECT COUNT(*) on the view then failed deterministically, which would have failed the 07:50 UTC orchestrator pass and left ownership stale (every consumer LEFT JOINs the table, so a stale row reads as 'no claim' and the single-home ladder, DEFER_* routing and panel membership all quietly break). House pattern for planner blowups: never inline a ceiling view, read a T_ materialized earlier in the same SP. Splitting the plan in two is the entire remedy — each half plans comfortably alone, and because the T_ is a materialization rather than a transformation, ZERO logic moved out of V_PANEL_OWNERSHIP (the per-campaign roll-up, the two claim arms and the ladder are all still in the view). Step 1 MUST run first every time: the T_ is this procedure's own scratch, not durable state, and a stale step 1 would re-publish yesterday's stock verdicts. FACT_PANEL_OWNERSHIP itself is unchanged: one row per ENABLED campaign carrying the Weekly Run single-home ladder (LOW STOCK > LAUNCH > REVIVALS > engines, Ori 2026-08-13) — owner, owner_rank, claim_rank, claim_scope, claim_reason, defer_action/defer_reason and the per-panel defer_* booleans. Engines and panels read the TABLE (planner-ceiling doctrine). Runs after the inventory + ads loads and before the engine T_ builds. Spec: architecture/PANEL_OWNERSHIP.md."
)
BEGIN
  -- STEP 1 — the planner firebreak. Pure slice; keep it a SELECT *.
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_LOW_STOCK_CAMPAIGN` AS
  SELECT * FROM `onyga-482313.OI.V_LOW_STOCK_ADS`
  WHERE row_kind = 'CAMPAIGN' AND campaign_id IS NOT NULL;

  -- STEP 2 — the ownership snapshot. V_PANEL_OWNERSHIP reads step 1, never V_LOW_STOCK_ADS.
  CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_PANEL_OWNERSHIP` AS
  SELECT * FROM `onyga-482313.OI.V_PANEL_OWNERSHIP`;
END;
