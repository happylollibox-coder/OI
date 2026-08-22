-- V_KEYWORD_STATE — thin read surface over FACT_KEYWORD_STATE (2026-08-16, Task 2.1).
-- Spec: architecture/KEYWORD_STATE.md. NO LOGIC — the states are the SP's.
-- v27.103 (2026-08-22): redeployed for the bar/SE ladder columns — SELECT * freezes the schema
-- at CREATE time, so every column addition to the FACT needs this file re-run.
-- v27.104 (2026-08-22): redeployed for the floor / bid-space price / guard-scope / probation
-- columns (bid_floor, bid_floor_source, affordable_bid, clean_affordable_bid, at_floor,
-- guard_scope, floor_since, probation_clock_start, probation_clk_settled, probation_elapsed,
-- probation_due_date, probation_bid, nf_collapse_forecast_date, raw_state, clean_state, ...).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_STATE` AS
SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE`;
