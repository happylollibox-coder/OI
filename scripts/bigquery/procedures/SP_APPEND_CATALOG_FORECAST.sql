CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_APPEND_CATALOG_FORECAST`()
OPTIONS (description = "Writes tonight's Catalog claims into FACT_CATALOG_FORECAST so they can be scored later (forecast chain step 3; THREE_LAYERS.md 2.0.1 and 6). WITHOUT THIS THE CATALOG CANNOT BE GRADED AT ALL: V_CATALOG_FORECAST is a live view over CREATE-OR-REPLACE snapshots, so tomorrow it answers from tomorrow's data and tonight's prediction is gone -- the actuals survive and the forecast does not. APPEND-THEN-PRUNE, exactly as SP_APPEND_SEAT_REQUEST and SP_APPEND_KEYWORD_STATE_HISTORY: INSERT the whole day stamped with this run's captured_at, then prune any forecast_on carrying more than one stamp down to its newest, keyed on the LEDGER'S OWN duplicate stamps rather than on any date the source happens to carry, and run before the append as well as after -- so a strand left on any date is repaired by any later call, including a manual one. The failure mode points the safe way: a crash between the two statements leaves a duplicate, never a lost claim. ONE SEASON PER RUN: the view publishes all four, and this picks the one holding the MAJORITY OF DAYS in the forecast window, so a window straddling October and November is claimed for whichever season most of it sits in and the row records which. Rows the chain refused -- no baseline, no flow, no halo -- are simply absent rather than stored as zeros, because a claim never made must not be graded. Guarded so an empty or missing view is a no-op rather than an emptied partition. It decides nothing, writes nothing any other task consults, and can move no bid, budget or pause. Acceptance: scripts/bigquery/tests/CATALOG_FORECAST_OUTCOME_acceptance.sql.")
BEGIN
  DECLARE run_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE fc_day DATE DEFAULT CURRENT_DATE('America/Los_Angeles');
  DECLARE win_start DATE;
  DECLARE win_end DATE;
  DECLARE win_days INT64 DEFAULT 7;
  DECLARE win_season STRING;
  DECLARE n_rows INT64;

  IF NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
                 WHERE table_name = 'FACT_CATALOG_FORECAST') THEN
    RETURN;
  END IF;

  -- Prune FIRST as well as last: any duplicate strand left by an earlier crash is repaired by any
  -- later call, rather than waiting for someone to notice it.
  DELETE FROM `onyga-482313.OI.FACT_CATALOG_FORECAST` t
  WHERE t.captured_at < (SELECT MAX(x.captured_at) FROM `onyga-482313.OI.FACT_CATALOG_FORECAST` x
                         WHERE x.forecast_on = t.forecast_on);

  SET win_start = DATE_ADD(fc_day, INTERVAL 1 DAY);
  SET win_end   = DATE_ADD(fc_day, INTERVAL win_days DAY);

  -- The season holding the most days of the window. Deterministic tie-break by name so a 50/50
  -- straddle does not flip between runs and silently re-label a claim.
  SET win_season = (
    SELECT season FROM (
      SELECT CASE WHEN EXTRACT(MONTH FROM d) IN (11,12) THEN 'HOLIDAY'
                  WHEN EXTRACT(MONTH FROM d) IN (8,9)   THEN 'BACK_TO_SCHOOL'
                  WHEN EXTRACT(MONTH FROM d) IN (1,2)   THEN 'POST_HOLIDAY'
                  ELSE 'OFF_SEASON' END AS season, COUNT(*) AS n
      FROM UNNEST(GENERATE_DATE_ARRAY(win_start, win_end)) AS d
      GROUP BY season ORDER BY n DESC, season ASC LIMIT 1));

  SET n_rows = (SELECT COUNT(*) FROM `onyga-482313.OI.V_CATALOG_FORECAST` WHERE season = win_season);

  -- A missing or empty source is a no-op. Writing nothing is recoverable; writing an empty day and
  -- calling it a forecast is a claim the Catalog never made.
  IF n_rows = 0 THEN
    RETURN;
  END IF;

  DELETE FROM `onyga-482313.OI.FACT_CATALOG_FORECAST` WHERE forecast_on = fc_day;

  INSERT INTO `onyga-482313.OI.FACT_CATALOG_FORECAST` (
    forecast_on, captured_at, source, source_detail,
    window_start, window_end, window_days, season, settles_on,
    family, campaign_id, campaign_name, keyword_id, target_text, match_type, channel,
    best_cpc, ceiling_cpc, best_cpc_closed_form, best_cpc_at_grid_edge, optimum_below_floor,
    predicted_clicks, predicted_orders, predicted_cost, predicted_gross_profit,
    predicted_ads_net_roas, predicted_net_roas, predicted_contribution,
    cvr_used, gp_per_order_used, gp_per_click_modelled, elasticity,
    baseline_cpc, baseline_clicks_per_day, halo_factor, keyword_bar, halo_credit,
    rate_basis, clicks_basis, elasticity_basis, sentence)
  SELECT
    fc_day, run_ts, 'ORCHESTRATOR',
    CONCAT('V_CATALOG_FORECAST season=', win_season, ' read ', CAST(run_ts AS STRING)),
    win_start, win_end, win_days, v.season,
    -- Settle lag is per channel and declared, not inlined: SB reports slower than SP, and grading
    -- an unsettled window marks the Catalog down for sales that have not landed yet.
    DATE_ADD(win_end, INTERVAL IF(v.channel = 'SB', 14, 7) DAY),
    v.family, v.campaign_id, v.campaign_name, v.keyword_id, v.target_text, v.match_type, v.channel,
    v.best_cpc, v.ceiling_cpc, v.best_cpc_closed_form, v.best_cpc_at_grid_edge, v.optimum_below_floor,
    v.clicks_per_day       * win_days,
    v.orders_per_day       * win_days,
    v.cost_per_day         * win_days,
    v.gross_profit_per_day * win_days,
    v.ads_net_roas,          -- a RATIO: it does not scale with the window and must not be multiplied
    v.net_roas,
    v.contribution_per_day * win_days,
    v.cvr_used, v.gp_per_order_used, v.gp_per_click_modelled, v.elasticity,
    v.baseline_cpc, v.baseline_clicks_per_day, v.halo_factor, v.keyword_bar, v.halo_credit,
    v.rate_basis, v.clicks_basis, v.elasticity_basis, v.sentence
  FROM `onyga-482313.OI.V_CATALOG_FORECAST` v
  WHERE v.season = win_season;

  DELETE FROM `onyga-482313.OI.FACT_CATALOG_FORECAST` t
  WHERE t.captured_at < (SELECT MAX(x.captured_at) FROM `onyga-482313.OI.FACT_CATALOG_FORECAST` x
                         WHERE x.forecast_on = t.forecast_on);
END;
