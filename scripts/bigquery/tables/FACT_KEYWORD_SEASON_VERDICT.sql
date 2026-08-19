-- =============================================
-- FACT_KEYWORD_SEASON_VERDICT — append-only cross-occurrence memory of the season-context ledger.
-- Spec: architecture/SEASON_CONTEXT_LEDGER.md.
--
-- One row per (occurrence_key, keyword_text) for CLOSED occurrences only
-- (occurrence_end <= anchor-7 — every day settled). Written by SP_SNAPSHOT_SEASON_VERDICT
-- (orchestrator Task 20.5d, v27.41) via idempotent MERGE; re-runs refresh rows in place.
--
-- verdict (v27.44, 2026-08-08): INSUFFICIENT (clicks<15) | WIN (clicks>=15 AND net>=0, exactly
-- GP-ROAS>=1.0) | LOSS (clicks>=15 AND net<=-5.00 AND GP-ROAS<0.95) | NEUTRAL (clicks>=15,
-- neither — the breakeven dead-band: near-breakeven or small-dollar outcomes carry NO memory;
-- the gate acts only on 'LOSS', so NEUTRAL is inert by construction).
-- Metrics stored so allowance calibration can split LOSS by depth without re-reading
-- history. MATURITY GUARD lives in mature_at_start: a prior verdict is only trusted when the
-- keyword's first-ever click was >= 30d before the occurrence started.
-- =============================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT` (
  occurrence_key    STRING NOT NULL,   -- e.g. XMAS_2025_20251001, OFF_20250218
  context_label     STRING NOT NULL,   -- e.g. XMAS_2025, BTS_2025, OFF
  occurrence_start  DATE   NOT NULL,
  occurrence_end    DATE   NOT NULL,
  is_peak           BOOL,
  keyword_text      STRING NOT NULL,   -- LOWER(TRIM(targeting))
  clicks            INT64,
  spend             FLOAT64,
  sales             FLOAT64,
  gross_profit      FLOAT64,           -- Ads_sales - IFNULL(TOTAL_COST_PER_UNIT,0)*Ads_units
  net               FLOAT64,           -- gross_profit - spend
  orders            INT64,
  units             INT64,
  active_days       INT64,
  first_click_date  DATE,
  mature_at_start   BOOL,
  verdict           STRING NOT NULL,   -- WIN | LOSS | NEUTRAL | INSUFFICIENT (v27.44)
  settled_through   DATE,              -- anchor-7 at snapshot time
  snapshot_ts       TIMESTAMP
)
PARTITION BY occurrence_end
CLUSTER BY context_label, keyword_text
OPTIONS (
  description = "Season-context verdicts per (keyword, closed context occurrence). v27.44: WIN (>=15c, net>=0 == GP-ROAS>=1.0) / LOSS (>=15c, net<=-5 AND GP-ROAS<0.95) / NEUTRAL (>=15c, neither — breakeven dead-band, carries no memory) / INSUFFICIENT (clicks<15) over settled days only (date<=anchor-7). Written by SP_SNAPSHOT_SEASON_VERDICT (idempotent MERGE, orchestrator Task 20.5d). Regenerated 2026-08-08 under v27.44: 5,739 rows, 172 LOSS->NEUTRAL, WIN/INSUFFICIENT bit-stable. Spec: architecture/SEASON_CONTEXT_LEDGER.md."
);
