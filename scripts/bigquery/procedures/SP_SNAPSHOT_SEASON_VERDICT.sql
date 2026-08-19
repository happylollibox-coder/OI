-- =============================================
-- SP_SNAPSHOT_SEASON_VERDICT — writes final WIN/LOSS/NEUTRAL/INSUFFICIENT verdicts into
-- FACT_KEYWORD_SEASON_VERDICT for every season-context occurrence that has CLOSED
-- (occurrence_end <= anchor-7, i.e. fully settled). Idempotent MERGE on
-- (occurrence_key, keyword_text): newly closed occurrences insert, previously written rows are
-- refreshed in place (absorbs any late restatement tail). Open occurrences are never written.
--
-- v27.44 (2026-08-08) — LOSS dead-band. The old LOSS = "net < 0" had no breakeven dead-band and
-- no evidence floor on the dollar amount: a 190-click prior at net -$0.10 (GP-ROAS 0.9984) was
-- blocked identically to a GP-ROAS-0 disaster. New rule, applied at verdict time:
--   INSUFFICIENT : settled clicks < 15                          (UNCHANGED — the verified
--                  invariant: INSUFFICIENT is EXACTLY the <15-settled-clicks set)
--   WIN          : clicks >= 15 AND net >= 0                    (UNCHANGED; net >= 0 is exactly
--                  GP-ROAS >= 1.0 — verified 0 disagreements, no zero-spend rows at >= 15c)
--   LOSS         : clicks >= 15 AND net <= -5.00 AND GP-ROAS < 0.95
--   NEUTRAL      : clicks >= 15 AND neither WIN nor LOSS        (NEW label — the dead-band:
--                  near-breakeven or small-dollar outcomes carry NO memory)
-- NEUTRAL is a FOURTH label, deliberately NOT folded into INSUFFICIENT (that would break the
-- invariant). The gate (V_KEYWORD_CONTEXT_GATE) acts only on prior_verdict = 'LOSS', so NEUTRAL
-- is inert by construction — verified: no consumer treats unknown verdict labels as LOSS.
-- Regenerated 2026-08-08 (fully derived table): 5,739 rows deleted, 5,739 rewritten by one SP
-- run — 172 LOSS -> NEUTRAL, WIN (1,405) and INSUFFICIENT (2,563) bit-stable.
--
-- Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.5d (v27.41), after SP_FACT_AMAZON_ADS.
-- Spec: architecture/SEASON_CONTEXT_LEDGER.md.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_SEASON_VERDICT`()
OPTIONS (
  description = "Season-context verdict snapshot (v27.44). MERGEs V_KEYWORD_CONTEXT_LEDGER rows of CLOSED occurrences into FACT_KEYWORD_SEASON_VERDICT with verdict = INSUFFICIENT (clicks<15) / WIN (net>=0) / LOSS (net<=-5 AND GP-ROAS<0.95) / NEUTRAL (>=15c, neither — the breakeven dead-band, carries no memory). Idempotent. Spec: architecture/SEASON_CONTEXT_LEDGER.md."
)
BEGIN
  MERGE `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT` t
  USING (
    SELECT
      occurrence_key,
      context_label,
      occurrence_start,
      occurrence_end,
      is_peak,
      keyword_text,
      clicks,
      spend,
      sales,
      gross_profit,
      net,
      orders,
      units,
      active_days,
      first_click_date,
      mature_at_start,
      CASE
        WHEN clicks < 15 THEN 'INSUFFICIENT'   -- tested_clk bar: thin evidence is never a verdict
        WHEN net >= 0    THEN 'WIN'            -- == GP-ROAS >= 1.0 (spend > 0 at >= 15 clicks)
        WHEN net <= -5.00
         AND SAFE_DIVIDE(gross_profit, NULLIF(spend, 0)) < 0.95
                         THEN 'LOSS'           -- v27.44: a loss must be REAL money AND clearly
                                               -- under breakeven to earn cross-occurrence memory
        ELSE                  'NEUTRAL'        -- v27.44 dead-band: near-breakeven / small-dollar
      END AS verdict,
      settled_through
    FROM `onyga-482313.OI.V_KEYWORD_CONTEXT_LEDGER`
    WHERE occurrence_closed
  ) s
  ON t.occurrence_key = s.occurrence_key AND t.keyword_text = s.keyword_text
  WHEN MATCHED THEN UPDATE SET
    context_label    = s.context_label,
    occurrence_start = s.occurrence_start,
    occurrence_end   = s.occurrence_end,
    is_peak          = s.is_peak,
    clicks           = s.clicks,
    spend            = s.spend,
    sales            = s.sales,
    gross_profit     = s.gross_profit,
    net              = s.net,
    orders           = s.orders,
    units            = s.units,
    active_days      = s.active_days,
    first_click_date = s.first_click_date,
    mature_at_start  = s.mature_at_start,
    verdict          = s.verdict,
    settled_through  = s.settled_through,
    snapshot_ts      = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT (
    occurrence_key, context_label, occurrence_start, occurrence_end, is_peak, keyword_text,
    clicks, spend, sales, gross_profit, net, orders, units, active_days,
    first_click_date, mature_at_start, verdict, settled_through, snapshot_ts
  ) VALUES (
    s.occurrence_key, s.context_label, s.occurrence_start, s.occurrence_end, s.is_peak, s.keyword_text,
    s.clicks, s.spend, s.sales, s.gross_profit, s.net, s.orders, s.units, s.active_days,
    s.first_click_date, s.mature_at_start, s.verdict, s.settled_through, CURRENT_TIMESTAMP()
  );
END;
