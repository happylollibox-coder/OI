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
-- ORDER IN THE ORCHESTRATOR: after SP_SNAPSHOT_PANEL_OWNERSHIP (the engines' deferral reads it)
-- and after SP_REFRESH_ADS_COACH_ACTIONS (the launch ladder reads the coach), before
-- SP_REFRESH_CUBE_TABLES — so the snapshot records the same opinions the day's panels will show.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_ENGINE_PROPOSALS`()
OPTIONS (
  description = "Daily engine-proposal snapshot (2026-08-15, negates v27.72). Deletes today's partition of FACT_ENGINE_PROPOSALS and re-inserts every live instruction from V_KEYWORD_LIFT (bids + budgets), V_OOB_KEYWORD, V_OOB_BUDGET_PHASE, V_LOW_STOCK_ADS (TARGET bids + CAMPAIGN budgets), V_LAUNCH_BID_LADDER, V_PARK_REVERDICT (REVIVE), plus NEGATE rows from V_OOB_SEARCH_TERM (OOB+LIFT populations) and V_WEEKLY_RUN_NEGATIVE (COACH). One single-view scan per INSERT (planner-ceiling doctrine). HOLD/WATCH/DEFER rows excluded. Runs in SP_ORCHESTRATE_DAILY_REFRESH after the ownership snapshot, before the cube T_ builds. Spec: architecture/DAILY_BRIEF.md."
)
BEGIN
  DECLARE snap DATE DEFAULT CURRENT_DATE('America/Los_Angeles');

  DELETE FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` WHERE snapshot_date = snap;

  -- 1. LIFT keyword bids (Portfolio 80/20 / Auto / research ladders)
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied)
  SELECT snap, 'LIFT', 'BID', CAST(campaign_id AS STRING), campaign_name,
         CAST(keyword_id AS STRING), CAST(ad_group_id AS STRING), target_text, match_type, channel,
         action, current_bid, suggested_bid, NULL, NULL, reason, reason_short, CAST(NULL AS BOOL)
  FROM `onyga-482313.OI.V_KEYWORD_LIFT`
  WHERE action NOT IN ('HOLD', 'DEFER_OOB', 'PROBE_WAIT') AND suggested_bid IS NOT NULL;

  -- 2. LIFT campaign budgets (one row per campaign; the view repeats them per keyword row)
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied)
  SELECT snap, 'LIFT', 'BUDGET', CAST(campaign_id AS STRING), ANY_VALUE(campaign_name),
         NULL, CAST(NULL AS STRING), NULL, NULL, ANY_VALUE(channel),
         'BUDGET_CHANGE', NULL, NULL, ANY_VALUE(budget), ANY_VALUE(suggested_budget), ANY_VALUE(budget_reason),
         -- audit rewrite: 'W 0x' was undecodable — name the windows, show the dollars
         ANY_VALUE(CONCAT('week ', FORMAT('%.2f', COALESCE(camp_roas_7d, 0)), 'x · today ',
                          FORMAT('%.2f', COALESCE(camp_roas_1d, 0)), 'x ⇒ budget $',
                          FORMAT('%.2f', budget), '→$', FORMAT('%.2f', suggested_budget))), CAST(NULL AS BOOL)
  FROM `onyga-482313.OI.V_KEYWORD_LIFT`
  WHERE suggested_budget IS NOT NULL
  GROUP BY campaign_id;  -- one budget per campaign — ANY_VALUE here is safe: every keyword row
                         -- of a campaign carries the SAME campaign-level budget fields

  -- 3. OOB keyword bids (the seat model)
  INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id, target_text,
     match_type, channel, action, current_bid, suggested_bid, current_budget, suggested_budget, reason, reason_short, season_relax_applied)
  SELECT snap, 'OOB', 'BID', CAST(campaign_id AS STRING), campaign_name,
         CAST(keyword_id AS STRING), CAST(ad_group_id AS STRING), target_text, match_type, IF(is_sb, 'SB', 'SP'),
         bid_action, current_bid, suggested_bid, NULL, NULL, bid_reason, bid_reason_short, CAST(NULL AS BOOL)
  FROM `onyga-482313.OI.V_OOB_KEYWORD`
  WHERE bid_action NOT IN ('HOLD', 'APPLIED_HOLD') AND suggested_bid IS NOT NULL;

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
         'REVIVE', r.current_bid, r.revive_bid, NULL, NULL, r.reverdict_reason,
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
         'NEGATE_TERM', NULL, NULL, NULL, NULL, g.s.reason,
         IF(g.peak_converts,
            CONCAT('bought in past gift peaks (', CAST(g.peak_orders AS STRING),
                   IF(g.peak_orders = 1, ' order', ' orders'), ') — check before blocking'),
            'coach rule: irrelevant or money-losing term ⇒ block this search term'),
         g.peak_converts
  FROM (
    SELECT CAST(w.campaign_id AS STRING) AS cid, w.search_term AS term,
           LOGICAL_OR(COALESCE(w.peak_converts, FALSE)) AS peak_converts,
           MAX(COALESCE(w.peak_orders, 0)) AS peak_orders,
           -- highest-priority slice speaks; ORDER BY is total so a re-run is byte-identical
           ARRAY_AGG(STRUCT(w.campaign_name, w.ad_group_id, w.reason)
                     ORDER BY w.priority_score DESC, w.keyword_id LIMIT 1)[OFFSET(0)] AS s
    FROM `onyga-482313.OI.V_WEEKLY_RUN_NEGATIVE` w
    GROUP BY 1, 2
  ) g
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
    ON CAST(dc.campaign_id AS STRING) = g.cid;
END;
