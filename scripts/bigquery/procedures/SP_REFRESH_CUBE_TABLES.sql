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

END;
