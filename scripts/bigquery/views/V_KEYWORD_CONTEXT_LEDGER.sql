-- =============================================
-- V_KEYWORD_CONTEXT_LEDGER — settled per-(keyword, season-context occurrence) money ledger.
-- Spec: architecture/SEASON_CONTEXT_LEDGER.md (Ori doctrine 2026-08-07: "I want not to lose money
-- on the same keyword for the same period.").
--
-- Grain: (keyword_text = LOWER(TRIM(targeting)), occurrence_key from V_SEASON_CONTEXT).
-- All targeting kinds included (keywords, auto clauses, product targets); empty targeting dropped;
-- a row exists only where the keyword had clicks>0 OR spend>0 inside the occurrence.
--
-- SETTLED DAYS ONLY: date <= anchor-7 (spend settles ~D+3 but sales accrue to D+7 SP / D+14 SB;
-- younger windows manufacture false loss verdicts; SB tail slack is absorbed by the allowance).
-- Anchor = LEAST(MAX(date), FN_ADS_ANCHOR_CAP()) from FACT_AMAZON_ADS.
--
-- gross_profit = Ads_sales - IFNULL(TOTAL_COST_PER_UNIT,0)*Ads_units (doctrine formula verbatim;
-- deliberately NOT the tier-COGS variant the engines use — the ledger stays self-contained).
-- net = gross_profit - spend.
--
-- first_click_date = first date ever with a click (FULL history, not settled-capped).
-- mature_at_start (MATURITY GUARD) = first_click_date <= occurrence_start - 30d: only a mature
-- keyword's verdict is trusted cross-occurrence — early history is launch ramp, not season signal.
-- tested = clicks >= 15 (the account's tested_clk bar). Thin-evidence trap: 1-3 clicks at high
-- ROAS is noise, never a winner.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_CONTEXT_LEDGER` AS
WITH
anchor AS (
  SELECT LEAST((SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
               `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS a
),
fx AS (
  SELECT
    LOWER(TRIM(targeting)) AS keyword_text,
    date,
    Ads_clicks,
    Ads_cost,
    Ads_sales,
    Ads_units,
    Ads_orders,
    Ads_sales - IFNULL(TOTAL_COST_PER_UNIT, 0) * Ads_units AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE targeting IS NOT NULL AND TRIM(targeting) != ''
),
first_click AS (
  SELECT keyword_text, MIN(IF(Ads_clicks > 0, date, NULL)) AS first_click_date
  FROM fx
  GROUP BY keyword_text
),
led AS (
  SELECT
    f.keyword_text,
    c.context_label,
    c.occurrence_key,
    c.occurrence_start,
    c.occurrence_end,
    c.is_peak,
    c.occurrence_closed,
    SUM(f.Ads_clicks)              AS clicks,
    ROUND(SUM(f.Ads_cost), 2)      AS spend,
    ROUND(SUM(f.Ads_sales), 2)     AS sales,
    ROUND(SUM(f.gp), 2)            AS gross_profit,
    ROUND(SUM(f.gp) - SUM(f.Ads_cost), 2) AS net,
    SUM(f.Ads_orders)              AS orders,
    SUM(f.Ads_units)               AS units,
    MIN(f.date)                    AS first_active_date,
    MAX(f.date)                    AS last_active_date,
    COUNT(DISTINCT f.date)         AS active_days
  FROM fx f
  JOIN `onyga-482313.OI.V_SEASON_CONTEXT` c ON c.date = f.date
  CROSS JOIN anchor an
  WHERE f.date <= DATE_SUB(an.a, INTERVAL 7 DAY)   -- SETTLED days only
  GROUP BY 1, 2, 3, 4, 5, 6, 7
  HAVING SUM(f.Ads_clicks) > 0 OR SUM(f.Ads_cost) > 0
)
SELECT
  l.*,
  fc.first_click_date,
  (fc.first_click_date IS NOT NULL
   AND fc.first_click_date <= DATE_SUB(l.occurrence_start, INTERVAL 30 DAY)) AS mature_at_start,
  l.clicks >= 15 AS tested,
  (SELECT DATE_SUB(a, INTERVAL 7 DAY) FROM anchor) AS settled_through
FROM led l
LEFT JOIN first_click fc USING (keyword_text);
