-- V_COVERAGE_KEYWORD — 90-day convenience wrapper over FN_COVERAGE_KEYWORD.
--
-- The real logic now lives in the window-parameterized table function
-- `FN_COVERAGE_KEYWORD(win_start, win_end, peak_only)` (mirrors FN_COVERAGE_CAMPAIGN), so the
-- cockpit's Time-window toggle governs keyword measures too — clicks, cost, cpc, net_roas,
-- target_cpc and profit_state all reflect the selected window.
--
-- This view is kept ONLY so ad-hoc queries / older consumers keep working at the historical
-- default (trailing 90 days, no peak restriction). It has no logic of its own — do NOT edit
-- rules here; change FN_COVERAGE_KEYWORD.sql instead or the two will drift.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COVERAGE_KEYWORD` AS
SELECT *
FROM `onyga-482313.OI.FN_COVERAGE_KEYWORD`(
  DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY),
  CURRENT_DATE(),
  FALSE
);
