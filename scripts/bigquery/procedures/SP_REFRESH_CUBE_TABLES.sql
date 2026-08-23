-- =============================================
-- OI Database Project - SP_REFRESH_CUBE_TABLES
-- =============================================
--
-- Purpose: Creates physical snapshot tables (T_*) from logical analytics
--          views (V_*) for fast querying in Cube.js.
--
-- Note: BigQuery Materialized Views do not support OUTER JOIN, UDFs,
--       or Window Functions, so Snapshot Tables are the best practice
--       for fast dashboard BI queries.
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_CUBE_TABLES`()
OPTIONS (
  description = "Creates physical snapshot tables (T_*) from logical analytics views (V_*) for fast querying in Cube.js."
)
BEGIN
  -- 0. Lift probe set — materialized FIRST so the coach chain never inlines the (large)
  -- V_KEYWORD_LIFT: planning it once here is fine; re-expanding it inside every coach
  -- T_ table blew query planning ("too many subqueries", 2026-08-03).
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_LIFT_PROBES` AS
    SELECT DISTINCT keyword_id FROM `onyga-482313.OI.V_KEYWORD_LIFT`
    WHERE probing OR action = 'PROBE_START';

  -- 0b. Seat economics of the budget engine (family seat register Task 2, 2026-08-22).
  -- V_OOB_KEYWORD is a planner-ceiling view measured in MINUTES; the register must never inline it,
  -- so its seat price (seat_cpc), slots, queue rank and role are materialised here once per pass.
  -- Same freshness contract as T_LIFT_PROBES: the register reads the previous pass's table until
  -- this step runs. Read by V_FAMILY_SEAT_REGISTER only.
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_OOB_SEAT_ECONOMICS`
  OPTIONS (description = 'Seat economics of the budget engine, materialised once per pass from V_OOB_KEYWORD (a planner-ceiling view that must never be inlined): one row per keyword the engine prices — its campaign slots, seat_rank, seat_cpc, role, bid_floor, current_bid, bid_action, suggested_bid, and the engine park price bid_park (published by V_OOB_KEYWORD since 2026-08-22, ruling R-f) — so the family seat register can read the seat price, the park price and the probe queue from a table. Built by SP_REFRESH_CUBE_TABLES step 0b, right after T_LIFT_PROBES. Read by V_FAMILY_SEAT_REGISTER. Spec: architecture/FAMILY_SEAT_REGISTER.md.') AS
    SELECT campaign_id, campaign_name, keyword_id, ad_group_id, target_text, match_type, is_auto, is_pt, is_sb,
           is_defense, days_capped_7d, bid_floor, current_bid, slots, seat_rank, seat_cpc, role, bid_action,
           suggested_bid, clk90, ord90, roas90, bid_park, CURRENT_DATE('America/Los_Angeles') AS built_on
    FROM `onyga-482313.OI.V_OOB_KEYWORD`;

  -- 1. Unified Daily
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_UNIFIED_DAILY` AS SELECT * FROM `onyga-482313.OI.V_UNIFIED_DAILY`;
  
  -- 2. Summary 7D
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_SUMMARY_7D` AS SELECT * FROM `onyga-482313.OI.V_SUMMARY_7D`;
  
  -- 3. Ads Coach Decision
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_ADS_COACH_DECISION` AS SELECT * FROM `onyga-482313.OI.V_ADS_COACH_DECISION`;

  -- 3b. Ads Coach Cross-Sell (self-brand product-target pairs)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_ADS_COACH_CROSSSELL` AS SELECT * FROM `onyga-482313.OI.V_ADS_COACH_CROSSSELL`;
  
  -- 4. Ads Coach Campaign
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_ADS_COACH_CAMPAIGN` AS SELECT * FROM `onyga-482313.OI.V_ADS_COACH_CAMPAIGN`;
  
  -- 5. Ads Coach Actions — SKIPPED (Cube reads FACT_ADS_COACH_ACTIONS directly, already materialized by SP_REFRESH_ADS_COACH_ACTIONS)

  -- 5a. Coacher F apply set — deduped keyword bids (heavy V_ADS_COACH dedup; materialize so Weekly Run loads fast)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_COACH_APPLY` AS SELECT * FROM `onyga-482313.OI.V_COACH_APPLY`;

  -- 5b. Coacher F apply set — campaign daily-budget changes
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_COACH_CAMPAIGN_BUDGET` AS SELECT * FROM `onyga-482313.OI.V_COACH_CAMPAIGN_BUDGET`;

  -- 5c. Weekly Run — complete campaign attribution (depends on 5b); 5d keywords; 5e product (depends on 5c)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_WEEKLY_RUN_CAMPAIGN` AS SELECT * FROM `onyga-482313.OI.V_WEEKLY_RUN_CAMPAIGN`;
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_WEEKLY_RUN_KEYWORD`  AS SELECT * FROM `onyga-482313.OI.V_WEEKLY_RUN_KEYWORD`;
  -- price→true-COGS tier lookup — MUST refresh before T_RUN_TARGET (which joins it for corrected net ROAS)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_PRICE_COST_TIER`    AS SELECT * FROM `onyga-482313.OI.V_PRICE_COST_TIER`;
  -- launch controller snapshot — V_RUN_TARGET references V_LAUNCH_PHASE1 TWICE (new_camp CTE + the bid
  -- join), so inlining it doubles that subtree into the T_RUN_TARGET plan. Reads T_PRICE_COST_TIER, so it
  -- MUST come after it (above) and before T_RUN_TARGET (below). The LaunchPhase1 cube and
  -- build_launch_phase1_bulksheet.py still read the live V_ — this T_ is only for V_RUN_TARGET.
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_LAUNCH_PHASE1`      AS SELECT * FROM `onyga-482313.OI.V_LAUNCH_PHASE1`;
  -- T_RUN_TARGET reads T_WEEKLY_RUN_KEYWORD + T_PRICE_COST_TIER + T_LAUNCH_PHASE1 (all above), NOT their V_:
  -- inlining V_WEEKLY_RUN_KEYWORD re-expands V_ADS_COACH here and blows query planning (2026-08-13). Keep
  -- all three preceding this statement.
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_RUN_TARGET`         AS SELECT * FROM `onyga-482313.OI.V_RUN_TARGET`;   -- merged step-4 card (keywords + auto groups, new + mature)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_WEEKLY_RUN_PRODUCT`  AS SELECT * FROM `onyga-482313.OI.V_WEEKLY_RUN_PRODUCT`;
  -- 5f. Weekly Run — NEGATE_TERM recommendations (level 3 under keywords)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_WEEKLY_RUN_NEGATIVE` AS SELECT * FROM `onyga-482313.OI.V_WEEKLY_RUN_NEGATIVE`;
  -- 5g. Weekly plan cells + last-wk net + trailing actual CPC (heavy double FACT scan → materialize)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_WEEKLY_PLAN_CELL` AS SELECT * FROM `onyga-482313.OI.V_WEEKLY_PLAN_CELL`;

  -- 6. Ads Coach Phrase Negatives
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_ADS_COACH_PHRASE_NEGATIVES` AS SELECT * FROM `onyga-482313.OI.V_ADS_COACH_PHRASE_NEGATIVES`;
  
  -- 7. Experiment Budget Health
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_EXPERIMENT_BUDGET_HEALTH` AS SELECT * FROM `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH`;
  
  -- 8. Experiment Learnings
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_EXPERIMENT_LEARNINGS` AS SELECT * FROM `onyga-482313.OI.V_EXPERIMENT_LEARNINGS`;
  
  -- 9. Experiment Evaluation
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_EXPERIMENT_EVALUATION` AS SELECT * FROM `onyga-482313.OI.V_EXPERIMENT_EVALUATION`;
  
  -- 10. Experiment Term Recommendations
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_EXPERIMENT_TERM_RECOMMENDATIONS` AS SELECT * FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`;
  -- SQP x Ads by search term (feeds SQP page Search Terms panel)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_SQP_ADS_BY_TERM` AS SELECT * FROM `onyga-482313.OI.V_SQP_ADS_BY_TERM`;

  -- 11. Keyword Strategy Predictions
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_KEYWORD_STRATEGY_PREDICTIONS` AS SELECT * FROM `onyga-482313.OI.V_KEYWORD_STRATEGY_PREDICTIONS`;
  
  -- 12. Brand Strength Weekly
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_BRAND_STRENGTH_WEEKLY` AS SELECT * FROM `onyga-482313.OI.V_BRAND_STRENGTH_WEEKLY`;
  
  -- 13. Parent Hero Asin
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_PARENT_HERO_ASIN` AS SELECT * FROM `onyga-482313.OI.V_PARENT_HERO_ASIN`;
  -- 14. Coach Hot Signals (3-day rapid alerts)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_COACH_HOT_SIGNALS` AS SELECT * FROM `onyga-482313.OI.V_COACH_HOT_SIGNALS`;

  -- 15. Campaign Launch Performance (first 3 months)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_CAMPAIGN_LAUNCH_PERF` AS SELECT * FROM `onyga-482313.OI.V_CAMPAIGN_LAUNCH_PERF`;

  -- 16. Campaign Launch Monthly (M1/M2/M3 bucketed metrics)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_CAMPAIGN_LAUNCH_MONTHLY` AS SELECT * FROM `onyga-482313.OI.V_CAMPAIGN_LAUNCH_MONTHLY`;

  -- 17. Product Phrase Negatives (curated per-product negative phrases)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_PRODUCT_PHRASE_NEGATIVES` AS SELECT * FROM `onyga-482313.OI.V_PRODUCT_PHRASE_NEGATIVES`;

  -- 18. Launch Negatives (phrases a new campaign launches with, per strategy × family)
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_LAUNCH_NEGATIVES` AS SELECT * FROM `onyga-482313.OI.V_LAUNCH_NEGATIVES`;

END;
