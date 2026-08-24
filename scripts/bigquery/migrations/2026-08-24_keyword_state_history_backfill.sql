-- =============================================================================================
-- FACT_KEYWORD_STATE_HISTORY backfill — v27.143 (2026-08-24). ONE SHOT, AND IT HAS A FUSE.
--
-- WHAT WAS RECOVERABLE, AND FROM WHERE. FACT_KEYWORD_STATE is CREATE OR REPLACE'd on every
-- orchestrator pass, so no copy of an earlier snapshot exists anywhere in the warehouse: there is
-- no TMP_, no T_, no cube materialisation and no export that holds one (checked before writing
-- this file). What DOES exist is BigQuery's own seven-day table history. Probed at three-hour
-- resolution across the whole window, the replaced versions are readable through
-- FOR SYSTEM_TIME AS OF and they carry their TRUE snapshot_date. Seven days were recovered:
-- 2026-08-17 through 2026-08-23, each taken from the LAST version that carried that date, which
-- is the same rule the live append step follows (the last pass of a day is the day's final word).
--
-- NOTHING IS INVENTED. No row here is synthesised, interpolated or dated by inference. Every row
-- is a row the Catalog actually wrote, and source_detail on each names the exact time-travel
-- timestamp it was read from, so any reader can re-derive it — until the fuse burns.
--
-- THE FUSE IS SEVEN DATES, NOT ONE, AND THE FIRST ONE IS 2026-08-25 (corrected v27.146). The
-- window is 168 hours (dataset maxTimeTravelHours = 168, checked), and each timestamp below leaves
-- it on its OWN day — so "around 2026-08-31", as this header first read, is the LAST expiry and not
-- the first:
--
--     snapshot_date  read from            unrecoverable after
--     2026-08-17     2026-08-18 06:00Z    2026-08-25 06:00Z   <- FIRST
--     2026-08-18     2026-08-19 06:00Z    2026-08-26 06:00Z
--     2026-08-19     2026-08-20 06:00Z    2026-08-27 06:00Z
--     2026-08-20     2026-08-21 06:00Z    2026-08-28 06:00Z
--     2026-08-21     2026-08-22 06:00Z    2026-08-29 06:00Z
--     2026-08-22     2026-08-23 06:00Z    2026-08-30 06:00Z
--     2026-08-23     2026-08-24 06:00Z    2026-08-31 06:00Z
--
-- This file is committed as the AUDIT RECORD of how those seven partitions got there, not as a
-- repeatable step. Everything after 2026-08-24 comes from SP_APPEND_KEYWORD_STATE_HISTORY on the
-- live pass, which is why the history is only ever this thin once.
--
-- BECAUSE THE FIRST EXPIRY LANDED HOURS AFTER THIS FILE RAN, A SECOND COPY WAS TAKEN:
-- FACT_KEYWORD_STATE_HISTORY_SEED_20260824, an immutable snapshot created 2026-08-24 23:15 UTC
-- (scripts/bigquery/tables/FACT/FACT_KEYWORD_STATE_HISTORY_SEED_20260824.sql). The history's own
-- time travel is NOT a second copy — it expires on the same rolling window.
--
-- TWO SCHEMA ERAS, HONESTLY LOADED. 2026-08-17..21 predate v27.103/104/105 and the procedure
-- published 22 columns then; 2026-08-22..23 publish the current 65. Each date is inserted with
-- the column list that ACTUALLY EXISTED on it. The bar/SE machinery, the floor and the probation
-- record are therefore NULL on the five earlier partitions — because the Catalog did not say them
-- then, not because they were lost. This is the same tolerance the append step relies on for the
-- columns §2.7 (confidence), §2.8 (market volume) and §4 (seasonality) will add.
--
-- IDEMPOTENT: each statement is guarded on its own date being absent, so re-running inside the
-- window adds nothing.
--
-- RUN ORDER MATTERS. This file runs BEFORE the first live append. The backfilled rows then all
-- carry a captured_at earlier than the first orchestrator-written partition, which is what the
-- acceptance's C05 ("no row is ever mutated": every older partition predates the newest) reads.
--
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
--
-- Spec: architecture/THREE_LAYERS.md §8 violation 6, §10.4. SOP: architecture/KEYWORD_STATE.md.
-- =============================================================================================

-- 2026-08-17: recovered from the table's own version as of 2026-08-18 06:00:00 UTC — the LAST build that
-- carried snapshot_date 2026-08-17 (22-column era of the procedure).
INSERT INTO `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  (captured_at, source, source_detail,
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     season_context, next_check_date, next_check_what, state_reason)
SELECT CURRENT_TIMESTAMP(), 'BACKFILL_TIME_TRAVEL',
       'FACT_KEYWORD_STATE FOR SYSTEM_TIME AS OF TIMESTAMP 2026-08-18 06:00:00 UTC (22 columns present)',
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     season_context, next_check_date, next_check_what, state_reason
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
FOR SYSTEM_TIME AS OF TIMESTAMP '2026-08-18 06:00:00 UTC'
WHERE (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
        WHERE snapshot_date = DATE '2026-08-17') = 0;

-- 2026-08-18: recovered from the table's own version as of 2026-08-19 06:00:00 UTC — the LAST build that
-- carried snapshot_date 2026-08-18 (22-column era of the procedure).
INSERT INTO `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  (captured_at, source, source_detail,
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     season_context, next_check_date, next_check_what, state_reason)
SELECT CURRENT_TIMESTAMP(), 'BACKFILL_TIME_TRAVEL',
       'FACT_KEYWORD_STATE FOR SYSTEM_TIME AS OF TIMESTAMP 2026-08-19 06:00:00 UTC (22 columns present)',
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     season_context, next_check_date, next_check_what, state_reason
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
FOR SYSTEM_TIME AS OF TIMESTAMP '2026-08-19 06:00:00 UTC'
WHERE (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
        WHERE snapshot_date = DATE '2026-08-18') = 0;

-- 2026-08-19: recovered from the table's own version as of 2026-08-20 06:00:00 UTC — the LAST build that
-- carried snapshot_date 2026-08-19 (22-column era of the procedure).
INSERT INTO `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  (captured_at, source, source_detail,
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     season_context, next_check_date, next_check_what, state_reason)
SELECT CURRENT_TIMESTAMP(), 'BACKFILL_TIME_TRAVEL',
       'FACT_KEYWORD_STATE FOR SYSTEM_TIME AS OF TIMESTAMP 2026-08-20 06:00:00 UTC (22 columns present)',
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     season_context, next_check_date, next_check_what, state_reason
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
FOR SYSTEM_TIME AS OF TIMESTAMP '2026-08-20 06:00:00 UTC'
WHERE (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
        WHERE snapshot_date = DATE '2026-08-19') = 0;

-- 2026-08-20: recovered from the table's own version as of 2026-08-21 06:00:00 UTC — the LAST build that
-- carried snapshot_date 2026-08-20 (22-column era of the procedure).
INSERT INTO `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  (captured_at, source, source_detail,
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     season_context, next_check_date, next_check_what, state_reason)
SELECT CURRENT_TIMESTAMP(), 'BACKFILL_TIME_TRAVEL',
       'FACT_KEYWORD_STATE FOR SYSTEM_TIME AS OF TIMESTAMP 2026-08-21 06:00:00 UTC (22 columns present)',
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     season_context, next_check_date, next_check_what, state_reason
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
FOR SYSTEM_TIME AS OF TIMESTAMP '2026-08-21 06:00:00 UTC'
WHERE (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
        WHERE snapshot_date = DATE '2026-08-20') = 0;

-- 2026-08-21: recovered from the table's own version as of 2026-08-22 06:00:00 UTC — the LAST build that
-- carried snapshot_date 2026-08-21 (22-column era of the procedure).
INSERT INTO `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  (captured_at, source, source_detail,
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     season_context, next_check_date, next_check_what, state_reason)
SELECT CURRENT_TIMESTAMP(), 'BACKFILL_TIME_TRAVEL',
       'FACT_KEYWORD_STATE FOR SYSTEM_TIME AS OF TIMESTAMP 2026-08-22 06:00:00 UTC (22 columns present)',
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     season_context, next_check_date, next_check_what, state_reason
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
FOR SYSTEM_TIME AS OF TIMESTAMP '2026-08-22 06:00:00 UTC'
WHERE (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
        WHERE snapshot_date = DATE '2026-08-21') = 0;

-- 2026-08-22: recovered from the table's own version as of 2026-08-23 06:00:00 UTC — the LAST build that
-- carried snapshot_date 2026-08-22 (65-column era of the procedure).
INSERT INTO `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  (captured_at, source, source_detail,
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     settled_gp90, settled_sp90, season_context, next_check_date, next_check_what, state_reason,
     family_bar, bar_exempt, nf_orders, se_eff, gp_per_click, affordable_cpc,
     ord_bar_expected, click_collapse, guard_prior_clk, guard_ns_share, guard_bar_material, guard_deferred,
     guard_flip, clean_clk90, clean_ord90, clean_roas90, clean_cpc90, clean_affordable_cpc,
     ns_zero_ord_terms, ns_zero_ord_clicks, ad_group_id, creative_type, bid_floor, bid_floor_source,
     m_effective, is_brand_defense, affordable_bid, clean_affordable_bid, at_floor, guard_scope,
     raw_state, clean_state, settle_days_eff, floor_since, probation_clock_start, probation_clk_settled,
     probation_elapsed, probation_due_date, probation_bid, nf_collapse_forecast_date, prior_state)
SELECT CURRENT_TIMESTAMP(), 'BACKFILL_TIME_TRAVEL',
       'FACT_KEYWORD_STATE FOR SYSTEM_TIME AS OF TIMESTAMP 2026-08-23 06:00:00 UTC (65 columns present)',
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     settled_gp90, settled_sp90, season_context, next_check_date, next_check_what, state_reason,
     family_bar, bar_exempt, nf_orders, se_eff, gp_per_click, affordable_cpc,
     ord_bar_expected, click_collapse, guard_prior_clk, guard_ns_share, guard_bar_material, guard_deferred,
     guard_flip, clean_clk90, clean_ord90, clean_roas90, clean_cpc90, clean_affordable_cpc,
     ns_zero_ord_terms, ns_zero_ord_clicks, ad_group_id, creative_type, bid_floor, bid_floor_source,
     m_effective, is_brand_defense, affordable_bid, clean_affordable_bid, at_floor, guard_scope,
     raw_state, clean_state, settle_days_eff, floor_since, probation_clock_start, probation_clk_settled,
     probation_elapsed, probation_due_date, probation_bid, nf_collapse_forecast_date, prior_state
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
FOR SYSTEM_TIME AS OF TIMESTAMP '2026-08-23 06:00:00 UTC'
WHERE (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
        WHERE snapshot_date = DATE '2026-08-22') = 0;

-- 2026-08-23: recovered from the table's own version as of 2026-08-24 06:00:00 UTC — the LAST build that
-- carried snapshot_date 2026-08-23 (65-column era of the procedure).
INSERT INTO `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
  (captured_at, source, source_detail,
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     settled_gp90, settled_sp90, season_context, next_check_date, next_check_what, state_reason,
     family_bar, bar_exempt, nf_orders, se_eff, gp_per_click, affordable_cpc,
     ord_bar_expected, click_collapse, guard_prior_clk, guard_ns_share, guard_bar_material, guard_deferred,
     guard_flip, clean_clk90, clean_ord90, clean_roas90, clean_cpc90, clean_affordable_cpc,
     ns_zero_ord_terms, ns_zero_ord_clicks, ad_group_id, creative_type, bid_floor, bid_floor_source,
     m_effective, is_brand_defense, affordable_bid, clean_affordable_bid, at_floor, guard_scope,
     raw_state, clean_state, settle_days_eff, floor_since, probation_clock_start, probation_clk_settled,
     probation_elapsed, probation_due_date, probation_bid, nf_collapse_forecast_date, prior_state)
SELECT CURRENT_TIMESTAMP(), 'BACKFILL_TIME_TRAVEL',
       'FACT_KEYWORD_STATE FOR SYSTEM_TIME AS OF TIMESTAMP 2026-08-24 06:00:00 UTC (65 columns present)',
   snapshot_date, campaign_id, keyword_id, target_text, match_type, channel,
     is_auto, is_pt, campaign_name, family, current_bid, state,
     owner_engine, state_since, settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
     settled_gp90, settled_sp90, season_context, next_check_date, next_check_what, state_reason,
     family_bar, bar_exempt, nf_orders, se_eff, gp_per_click, affordable_cpc,
     ord_bar_expected, click_collapse, guard_prior_clk, guard_ns_share, guard_bar_material, guard_deferred,
     guard_flip, clean_clk90, clean_ord90, clean_roas90, clean_cpc90, clean_affordable_cpc,
     ns_zero_ord_terms, ns_zero_ord_clicks, ad_group_id, creative_type, bid_floor, bid_floor_source,
     m_effective, is_brand_defense, affordable_bid, clean_affordable_bid, at_floor, guard_scope,
     raw_state, clean_state, settle_days_eff, floor_since, probation_clock_start, probation_clk_settled,
     probation_elapsed, probation_due_date, probation_bid, nf_collapse_forecast_date, prior_state
FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
FOR SYSTEM_TIME AS OF TIMESTAMP '2026-08-24 06:00:00 UTC'
WHERE (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY`
        WHERE snapshot_date = DATE '2026-08-23') = 0;
