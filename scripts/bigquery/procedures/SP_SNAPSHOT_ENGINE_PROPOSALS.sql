-- =============================================
-- SP_SNAPSHOT_ENGINE_PROPOSALS — writes today's engine instructions into FACT_ENGINE_PROPOSALS
-- (2026-08-15). Spec: architecture/DAILY_BRIEF.md.
--
-- One INSERT per engine surface, each a SINGLE-VIEW scan (planner-ceiling doctrine: these views
-- are individually at BigQuery's planning ceiling — two of them in one statement is a compile
-- error waiting to happen; see SP_SNAPSHOT_PANEL_OWNERSHIP's header for the full argument).
-- DELETE-today-then-INSERT so a same-day re-run replaces rather than duplicates.
--
-- WHAT COUNTS AS A PROPOSAL: a row the engine wants ACTED ON — an action string that is not a
-- hold/defer, carrying a concrete suggested value. HOLD / WATCH / APPLIED_HOLD / DEFER_* are
-- deliberately excluded: they are the engine saying "do nothing", and a memory full of nothing
-- would bury the signal. NEGATE proposals ARE captured since v27.72 (Ori 2026-08-17: "close the
-- negate gap") — grain='NEGATE', one row per (campaign, term), no values, keyed by the term text.
-- The remaining known gap is the ADD_KEYWORD lever (research-mode "+broad" offers) — named in
-- the SOP, not silently omitted.
--
-- ── v27.98 (Ori 2026-08-21): STOP DELETING VETOED PROPOSALS, LABEL THEM ──────────────────────
-- ONE EXCEPTION to the paragraph above, and it is not a hold at all. The last-day veto
-- (v27.75/v27.76) does not decline to propose: it takes a proposal the engine ALREADY MADE and
-- makes it wait a day. It does that by rewriting the action to 'HOLD' and NULLing the bid — which
-- breaks BOTH conjuncts of the filters below, so the row AND ITS REASON simply vanished. Across
-- the snapshots taken since this table was born, not one carried a word of veto text.
-- That made the veto the only suppression in the engine that ERASES instead of LABELLING, against
-- the doctrine SP_ENGINE_PREFLIGHT states in its own header for the holdout arm: "the proposal is
-- still recorded ... only the verdict says EXCLUDE. Block the export, never the judgement."
-- SO: the two bid INSERTs (1 = LIFT, 3 = OOB) now also admit rows carrying hold_source, and write
--   action = 'HOLD' and suggested_bid = NULL  (unchanged — no consumer of those columns moves)
--   held_action / held_bid                    (what the engine wanted, additive, never exported)
--   verdict = 'EXCLUDE'                       (stamped HERE, not by the gate — see below)
--   verdict_reason = the veto's OWN sentence  ("yday: 23c at 0.00x ⇒ raise waits a day")
-- IN THE SAME SCAN, deliberately: a separate INSERT per engine would re-read a view that is at
-- BigQuery's planning ceiling and double this procedure's daily cost for nothing.
-- WHY THE VERDICT IS WRITTEN HERE AND NOT BY THE GATE: a held row is not an instruction to judge.
-- It carries no value, so every value test in SP_ENGINE_PREFLIGHT would read it as a no-op, and —
-- far worse — it would take part in the single-owner contention as a live instruction, where a
-- held OOB row could outrank a real LIFT one and silence the engine that was actually ready to
-- act. The gate therefore skips hold_source rows outright, which also keeps them out of
-- T_ENGINE_PREFLIGHT, the EnginePreflight cube, the decisions feed and DoPage's bulksheet export.
-- The record lives here; nothing downstream can turn it back into an instruction.
--
-- ORDER IN THE ORCHESTRATOR: after SP_SNAPSHOT_PANEL_OWNERSHIP (the engines' deferral reads it)
-- and after SP_REFRESH_ADS_COACH_ACTIONS (the launch ladder reads the coach), before
-- SP_REFRESH_CUBE_TABLES — so the snapshot records the same opinions the day's panels will show.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_ENGINE_PROPOSALS`()
OPTIONS (
  description = "Daily engine-proposal snapshot (2026-08-15, negates v27.72). Deletes today's partition of FACT_ENGINE_PROPOSALS and re-inserts every live instruction from V_KEYWORD_LIFT (bids + budgets), V_OOB_KEYWORD, V_OOB_BUDGET_PHASE, V_LOW_STOCK_ADS (TARGET bids + CAMPAIGN budgets), V_LAUNCH_BID_LADDER, V_PARK_REVERDICT (REVIVE), plus NEGATE rows from V_OOB_SEARCH_TERM (OOB+LIFT populations) and V_WEEKLY_RUN_NEGATIVE (COACH). One single-view scan per INSERT (planner-ceiling doctrine). HOLD/WATCH/DEFER rows excluded. Runs in SP_ORCHESTRATE_DAILY_REFRESH after the ownership snapshot, before the cube T_ builds. Spec: architecture/DAILY_BRIEF.md. v27.98 (2026-08-21): the LAST-DAY VETO no longer erases what it held. The veto rewrites action to HOLD and NULLs the bid, which broke both conjuncts of the bid filters, so a vetoed proposal vanished with its reason and no snapshot ever carried a word of veto text — the one suppression in the engine that ERASED instead of LABELLING, against the doctrine SP_ENGINE_PREFLIGHT states for the holdout arm (block the export, never the judgement). INSERTs 1 (LIFT) and 3 (OOB) now also admit rows carrying hold_source, IN THE SAME SCAN (a separate INSERT would re-read a planning-ceiling view for nothing), writing held_action/held_bid additively, leaving action=HOLD and suggested_bid=NULL untouched so no existing consumer moves, and stamping verdict=EXCLUDE with the veto's own sentence as verdict_reason. The verdict is written HERE rather than by the gate because a held row is not an instruction to judge: it carries no value, and admitting it to the single-owner contention would let a held row outrank and silence an engine that was ready to act. SP_ENGINE_PREFLIGHT skips hold_source rows, so held rows never reach T_ENGINE_PREFLIGHT, the cube, the decisions feed or the bulksheet export."
)
BEGIN
  DECLARE snap DATE DEFAULT CURRENT_DATE('America/Los_Angeles');

  DELETE FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` WHERE snapshot_date = snap;

  -- 1. LIFT keyword bids (Portfolio 80/20 / Auto / research ladders)
  --    v27.98: + the rows the last-day veto held. Same scan, additive columns, verdict written
  --    here (see header). A held row has action = 'HOLD' and suggested_bid = NULL by construction.
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied,
     held_action, held_bid, hold_source, verdict, verdict_reason)
  SELECT snap, 'LIFT', 'BID', CAST(campaign_id AS STRING), campaign_name,
         CAST(keyword_id AS STRING), CAST(ad_group_id AS STRING), target_text, match_type, channel,
         action, current_bid, suggested_bid, NULL, NULL, reason, reason_short, CAST(NULL AS BOOL),
         held_action, held_bid, hold_source,
         IF(hold_source IS NOT NULL, 'EXCLUDE',      CAST(NULL AS STRING)),
         IF(hold_source IS NOT NULL, reason_short,   CAST(NULL AS STRING))
  FROM `onyga-482313.OI.V_KEYWORD_LIFT`
  WHERE (action NOT IN ('HOLD', 'DEFER_OOB', 'PROBE_WAIT') AND suggested_bid IS NOT NULL)
     OR hold_source IS NOT NULL;

  -- 2. LIFT campaign budgets (one row per campaign; the view repeats them per keyword row)
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied)
  SELECT snap, 'LIFT', 'BUDGET', CAST(campaign_id AS STRING), ANY_VALUE(campaign_name),
         NULL, CAST(NULL AS STRING), NULL, NULL, ANY_VALUE(channel),
         'BUDGET_CHANGE', NULL, NULL, ANY_VALUE(budget), ANY_VALUE(suggested_budget), ANY_VALUE(budget_reason),
         -- v27.99 (audit C5): THE SHORT IS NO LONGER COMPOSED HERE. It was built out of
         -- camp_roas_7d and labelled 'week', while the paragraph beside it judged camp_roas_w —
         -- three days in a live peak — and labelled it 'W'. Two windows, two indistinguishable
         -- labels, one row: they disagreed on 31 of 57 budget rows, 17 shorts sat at or above the
         -- very bar the paragraph called breached, and 6 announced a 20% cut next to a week ROAS
         -- of 1.0 or better. V_KEYWORD_LIFT now builds budget_reason_short from the SAME branches
         -- and the SAME numbers as budget_reason, and names the span ('last 3d') instead of
         -- calling it a week. Taking it verbatim is what keeps them from drifting again.
         ANY_VALUE(budget_reason_short), CAST(NULL AS BOOL)
  FROM `onyga-482313.OI.V_KEYWORD_LIFT`
  WHERE suggested_budget IS NOT NULL
  GROUP BY campaign_id;  -- one budget per campaign — ANY_VALUE here is safe: every keyword row
                         -- of a campaign carries the SAME campaign-level budget fields

  -- 3. OOB keyword bids (the seat model)
  --    v27.98: + the rows the last-day veto held. Same scan, additive columns, verdict written
  --    here (see header). A held row has bid_action = 'HOLD' and suggested_bid = NULL.
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied,
     held_action, held_bid, hold_source, verdict, verdict_reason)
  SELECT snap, 'OOB', 'BID', CAST(campaign_id AS STRING), campaign_name,
         CAST(keyword_id AS STRING), CAST(ad_group_id AS STRING), target_text, match_type, IF(is_sb, 'SB', 'SP'),
         bid_action, current_bid, suggested_bid, NULL, NULL, bid_reason, bid_reason_short, CAST(NULL AS BOOL),
         held_action, held_bid, hold_source,
         IF(hold_source IS NOT NULL, 'EXCLUDE',         CAST(NULL AS STRING)),
         IF(hold_source IS NOT NULL, bid_reason_short,  CAST(NULL AS STRING))
  FROM `onyga-482313.OI.V_OOB_KEYWORD`
  WHERE (bid_action NOT IN ('HOLD', 'APPLIED_HOLD') AND suggested_bid IS NOT NULL)
     OR hold_source IS NOT NULL;

  -- 4. OOB campaign budgets (the budget ladder)
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied)
  SELECT snap, 'OOB', 'BUDGET', CAST(campaign_id AS STRING), campaign_name,
         NULL, CAST(NULL AS STRING), NULL, NULL, channel,
         action, NULL, NULL, current_budget, suggested_budget, reason,
         CONCAT('hit budget cap ', CAST(COALESCE(days_capped_7d, 0) AS STRING), ' of 7 days · 3d ',
                FORMAT('%.2f', COALESCE(roas_3d, 0)), 'x ⇒ $', FORMAT('%.2f', current_budget),
                '→$', FORMAT('%.2f', suggested_budget)), CAST(NULL AS BOOL)
  FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
  WHERE action NOT IN ('HOLD', 'WATCH', 'APPLIED_HOLD') AND suggested_budget IS NOT NULL;

  -- 5. LOW_STOCK target bids + campaign budgets (only inside WATCH/THROTTLE/CRITICAL families)
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied)
  SELECT snap, 'LOW_STOCK', IF(row_kind = 'TARGET', 'BID', 'BUDGET'),
         CAST(campaign_id AS STRING), campaign_name,
         CAST(keyword_id AS STRING), CAST(ad_group_id AS STRING), target_text, match_type, channel,
         -- Phase 6 fix (found by the feed build): current_budget was inserted NULL, which made
         -- V_RUN_SUMMARY's direction CASE mislabel the paired stock CUTS as "budget raises".
         action, current_bid, suggested_bid, campaign_budget, suggested_budget, action_reason, action_reason_short, CAST(NULL AS BOOL)
  FROM `onyga-482313.OI.V_LOW_STOCK_ADS`
  WHERE row_kind IN ('TARGET', 'CAMPAIGN') AND COALESCE(is_proposal, FALSE)
    AND (suggested_bid IS NOT NULL OR suggested_budget IS NOT NULL);

  -- 6. LAUNCH bid ladder (trims toward the launch bid on exempt families)
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied)
  SELECT snap, 'LAUNCH', 'BID', CAST(campaign_id AS STRING), campaign_name,
         CAST(keyword_id AS STRING), CAST(ad_group_id AS STRING), targeting, match_type, campaign_type,
         ladder_action, current_bid, proposed_bid, NULL, NULL, ladder_reason,
         CONCAT(CAST(COALESCE(judged_window_days, 3) AS STRING), 'd: ',
                CAST(COALESCE(w_clicks, 0) AS STRING), ' clicks at ',
                FORMAT('%.2f', COALESCE(w_gp_roas, 0)), 'x ⇒ trim bid $',
                FORMAT('%.2f', current_bid), '→$', FORMAT('%.2f', proposed_bid)), CAST(NULL AS BOOL)
  FROM `onyga-482313.OI.V_LAUNCH_BID_LADDER`
  WHERE is_proposal AND proposed_bid IS NOT NULL;

  -- 7. REVERDICT revivals (settled record overturns the park)
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied)
  SELECT snap, 'REVERDICT', 'REVIVE', CAST(r.campaign_id AS STRING), dc.campaign_name,
         CAST(r.keyword_id AS STRING), CAST(r.ad_group_id AS STRING), r.keyword_text, r.match_type, r.channel,
         -- v27.99 (audit C8): V_PARK_REVERDICT no longer bakes the price into its verdict
         -- sentence (its consumers may cap the revival lower and were closing by naming a bid
         -- they had rejected). Here the reverdict IS the proposal, so this is where its price
         -- belongs — stated once, from the same column the row proposes.
         'REVIVE', r.current_bid, r.revive_bid, NULL, NULL,
         CONCAT(r.reverdict_reason, ' — un-park at $', FORMAT('%.2f', r.revive_bid)),
         CONCAT('90d: ', CAST(COALESCE(r.s90_clk, 0) AS STRING), ' clicks at ',
                FORMAT('%.2f', COALESCE(r.s90_gp_roas, 0)), 'x ⇒ un-park at $',
                FORMAT('%.2f', r.revive_bid)),
         COALESCE(r.season_relax_applied, FALSE)
  FROM `onyga-482313.OI.V_PARK_REVERDICT` r
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
    ON CAST(dc.campaign_id AS STRING) = CAST(r.campaign_id AS STRING)
  WHERE r.reverdict = 'REVIVE' AND r.revive_bid IS NOT NULL;

  -- 8. Search-term negates, OOB + LIFT populations (v27.72, Ori 2026-08-17: "close the negate
  -- gap"). One row per (campaign, term): the negative lands once even when several keyword
  -- slices earned it, and the panels key their queue items the same way (campaign_id + term).
  -- ad_group_id carries the view's comma-list VERBATIM — SB negatives need one bulksheet row per
  -- ad group, and the consumer splits the list exactly as the panels do (upload report 29).
  -- The view has already excluded: applied negates (change log), winners, defense campaigns,
  -- SQP-wait terms, and PT rows. The representative slice for the reason is the one with the
  -- most clicks — ARRAY_AGG with a total ORDER BY, so a re-run is byte-identical (the
  -- ANY_VALUE-pairing ban's constructive cousin).
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied)
  SELECT snap, g.engine, 'NEGATE', g.cid, dc.campaign_name,
         NULL, g.s.ad_group_ids, g.term, 'NEGATIVE_EXACT', g.s.channel,
         'NEGATE_TERM', NULL, NULL, NULL, NULL, g.s.reason, g.s.reason_short, CAST(NULL AS BOOL)
  FROM (
    SELECT CAST(t.campaign_id AS STRING) AS cid, t.engine, t.search_term AS term,
           ARRAY_AGG(STRUCT(
             t.ad_group_ids,
             IF(t.kind = 'SB', 'SB', 'SP') AS channel,
             IF(t.is_big,
                CONCAT('big search term (the market buys it: ', CAST(t.market_purchases_90d AS STRING),
                       ' Amazon purchases in 90d) — this campaign gave it ', CAST(t.clicks_90d AS STRING),
                       ' clicks over 90+ days with no order, so the two-window rule blocks it here'),
                CONCAT('small search term — ', CAST(t.clicks AS STRING),
                       ' clicks and no order in 28 days under "', t.target_text,
                       '", so the two-window rule blocks it here')) AS reason,
             IF(t.is_big,
                CONCAT(CAST(t.clicks_90d AS STRING), ' clicks over 90d, no sale ⇒ block this search term'),
                CONCAT(CAST(t.clicks AS STRING), ' clicks in 28d, no sale ⇒ block this search term')) AS reason_short
           ) ORDER BY t.clicks_90d DESC, t.clicks DESC, t.target_text LIMIT 1)[OFFSET(0)] AS s
    FROM `onyga-482313.OI.V_OOB_SEARCH_TERM` t
    WHERE t.is_negate
    GROUP BY 1, 2, 3
  ) g
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
    ON CAST(dc.campaign_id AS STRING) = g.cid;

  -- 9. Coach negates (v27.72) — the coacher's own NEGATE_TERM decisions, relevance/brand/
  -- seasonal-aware. Reads the LIVE V_WEEKLY_RUN_NEGATIVE, not T_WEEKLY_RUN_NEGATIVE: the T_ copy
  -- is built by SP_REFRESH_CUBE_TABLES (Task 21) AFTER this snapshot runs, so the T_ here would
  -- be yesterday's offers. One ceiling-view scan — the LIFT/OOB INSERT precedent. One row per
  -- (campaign, term); a term offered under two keywords is still one negative. peak_converts
  -- rides in season_relax_applied → the preflight turns it into REVIEW, never a silent GO
  -- (the view's own warning: "converts in peak → keep/seasonal, don't negate").
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied)
  SELECT snap, 'COACH', 'NEGATE', g.cid, g.s.campaign_name,
         NULL, g.s.ad_group_id, g.term, 'NEGATIVE_EXACT',
         IF(dc.campaign_type LIKE 'SPONSORED_BRANDS%', 'SB', 'SP'),
         -- v27.99 (audit C4): THE VISIBLE WHY ON A NEGATE NOW CARRIES EVIDENCE.
         -- This was a compile-time literal — 'coach rule: irrelevant or money-losing term ⇒
         -- block this search term' — with no data in it at all, and the only number-free
         -- reason_short in the whole snapshot. TodayDecisions prints reason_short as the visible
         -- why-column and hides the paragraph in a hover title, so on the ONE action class that is
         -- practically irreversible (a negative lands in DE_NEGATIVE_KEYWORDS and the term is
         -- suppressed for good) the justification Ori actually sees stated nothing. The OOB negate
         -- short thirty lines above has always carried its numbers; this is that same shape.
         -- The figures are the ad-group-grain block evidence — the grain the negative acts on —
         -- taken from the SAME highest-priority slice as the paragraph, so short and long agree.
         'NEGATE_TERM', NULL, NULL, NULL, NULL, g.s.reason,
         IF(g.peak_converts,
            CONCAT('bought in past gift peaks (', CAST(g.peak_orders AS STRING),
                   IF(g.peak_orders = 1, ' order', ' orders'), ') — check before blocking'),
            CONCAT(
              CAST(COALESCE(g.s.block_clicks_8w, 0) AS STRING), ' clicks in 8 weeks, ',
              CASE
                WHEN COALESCE(g.s.block_orders_8w, 0) = 0 THEN 'no order'
                ELSE CONCAT(CAST(g.s.block_orders_8w AS STRING),
                            IF(g.s.block_orders_8w = 1, ' order', ' orders'), ' but -$',
                            FORMAT('%.0f', ABS(COALESCE(g.s.block_net_profit_8w, 0))))
              END,
              ' ⇒ block this search term')),
         g.peak_converts
  FROM (
    SELECT CAST(w.campaign_id AS STRING) AS cid, w.search_term AS term,
           LOGICAL_OR(COALESCE(w.peak_converts, FALSE)) AS peak_converts,
           MAX(COALESCE(w.peak_orders, 0)) AS peak_orders,
           -- highest-priority slice speaks; ORDER BY is total so a re-run is byte-identical
           ARRAY_AGG(STRUCT(w.campaign_name, w.ad_group_id, w.reason,
                            w.block_clicks_8w, w.block_orders_8w, w.block_net_profit_8w)
                     ORDER BY w.priority_score DESC, w.keyword_id LIMIT 1)[OFFSET(0)] AS s
    FROM `onyga-482313.OI.V_WEEKLY_RUN_NEGATIVE` w
    GROUP BY 1, 2
  ) g
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
    ON CAST(dc.campaign_id AS STRING) = g.cid;
END;
