-- V_LASTDAY_VETO_PREMISE_READOUT — THE ANSWER, both arms, as a distribution.
--
-- Reads V_LASTDAY_VETO_PREMISE (which carries the instrument, its model and every stated limit)
-- and answers the two questions the last-day veto has never been asked:
--   RAISE ARM: among at-volume keyword-days the filling reading would have held a raise on, what
--              did those same days read once SETTLED?
--   CUT ARM:   among at-volume keyword-days the filling reading would have held a cut on, what
--              did those same days read once SETTLED?
-- Each keyword-day contributes its PROBABILITY of tripping the arm, not a 0/1 — the filling
-- reading is a random thinning of the settled day, so a day that trips the arm on one draw and
-- not on another belongs partly to both. Sum the weights to read "expected keyword-days".
--
-- row_kind = 'SUMMARY' — one row per (arm, channel): the mass the arm touches and the share of
--            that mass that turned out FINE at the veto's own bars once settled.
-- row_kind = 'BAND'    — the distribution behind the summary, in settled GP-ROAS bands.
--
-- THREE ARMS ARE REPORTED, not two, because the raise arm changed shape in v27.76:
--   RAISE_v2775  every filling reading under the raise bar holds the raise (as first shipped)
--   RAISE_v2776  a 0.00x reading only holds when the keyword's own 90-day rate expected at least
--                min_expected_orders on the filling day's clicks (the expected-orders gate)
--   CUT          a filling reading at or above the cut bar holds the cut
--
-- HOW TO READ IT, in one sentence: for the RAISE arms, pct_settled_clears_raise_bar is the share
-- of holds placed on a day that was NOT poor — the veto's false-hold rate at its own bar. For the
-- CUT arm, pct_settled_under_cut_bar is the same quantity, and cut_arm_settled_floor is the
-- arithmetic guarantee that bounds it.
-- Every limit of the instrument is stated in the header of V_LASTDAY_VETO_PREMISE. Read it first.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_LASTDAY_VETO_PREMISE_READOUT` AS
WITH
armed AS (
  SELECT channel, settled_gp_roas, settled_clears_raise_bar, settled_clears_breakeven,
         settled_under_cut_bar, cut_arm_settled_floor, cut_arm_settled_floor_worst_fill,
         raise_bar, cut_bar,
         'RAISE_v2775' AS arm, p_veto_raise_v75 AS w
  FROM `onyga-482313.OI.V_LASTDAY_VETO_PREMISE` WHERE at_volume
  UNION ALL
  SELECT channel, settled_gp_roas, settled_clears_raise_bar, settled_clears_breakeven,
         settled_under_cut_bar, cut_arm_settled_floor, cut_arm_settled_floor_worst_fill,
         raise_bar, cut_bar,
         'RAISE_v2776', p_veto_raise_v76
  FROM `onyga-482313.OI.V_LASTDAY_VETO_PREMISE` WHERE at_volume
  UNION ALL
  SELECT channel, settled_gp_roas, settled_clears_raise_bar, settled_clears_breakeven,
         settled_under_cut_bar, cut_arm_settled_floor, cut_arm_settled_floor_worst_fill,
         raise_bar, cut_bar,
         'CUT', p_veto_cut
  FROM `onyga-482313.OI.V_LASTDAY_VETO_PREMISE` WHERE at_volume
),
banded AS (
  SELECT *,
    CASE
      WHEN COALESCE(settled_gp_roas, 0) <= 0    THEN '1. 0.00x (no gross profit at all)'
      WHEN settled_gp_roas < 0.25               THEN '2. 0.00-0.25x'
      WHEN settled_gp_roas < 0.50               THEN '3. 0.25-0.50x'
      WHEN settled_gp_roas < 0.75               THEN '4. 0.50-0.75x'
      WHEN settled_gp_roas < 1.00               THEN '5. 0.75-1.00x'
      WHEN settled_gp_roas < 1.50               THEN '6. 1.00-1.50x'
      WHEN settled_gp_roas < 2.50               THEN '7. 1.50-2.50x'
      ELSE                                           '8. 2.50x and above'
    END AS settled_band
  FROM armed
)
SELECT
  'SUMMARY' AS row_kind, arm, channel, CAST(NULL AS STRING) AS settled_band,
  ROUND(SUM(w), 1) AS keyword_days_expected,
  CAST(NULL AS FLOAT64) AS pct_of_arm,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(settled_clears_raise_bar, w, 0)), NULLIF(SUM(w), 0)), 1)
    AS pct_settled_clears_raise_bar,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(settled_clears_breakeven, w, 0)), NULLIF(SUM(w), 0)), 1)
    AS pct_settled_clears_breakeven,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(settled_under_cut_bar, w, 0)), NULLIF(SUM(w), 0)), 1)
    AS pct_settled_under_cut_bar,
  ROUND(MAX(cut_arm_settled_floor), 3)            AS cut_arm_settled_floor,
  ROUND(MAX(cut_arm_settled_floor_worst_fill), 3) AS cut_arm_settled_floor_worst_fill
FROM banded
GROUP BY 1, 2, 3, 4
UNION ALL
SELECT
  'BAND', arm, channel, settled_band,
  ROUND(SUM(w), 1),
  ROUND(100 * SAFE_DIVIDE(SUM(w), SUM(SUM(w)) OVER (PARTITION BY arm, channel)), 1),
  NULL, NULL, NULL, NULL, NULL
FROM banded
GROUP BY 1, 2, 3, 4
ORDER BY row_kind, arm, channel, settled_band;
