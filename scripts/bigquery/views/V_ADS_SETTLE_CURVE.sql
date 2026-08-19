-- V_ADS_SETTLE_CURVE — THE ANSWER to "when is an ads day fully refreshed?" (Ori 2026-08-06).
--
-- For every report_date, compares the FIRST measurement taken at each age (0,1,2,...) against
-- the LATEST measurement we hold. pct_of_final = how complete the number looked at that age.
-- Read the median row per age_days: the age where pct_of_final reaches ~100% and stops moving
-- is the sweet spot. Spend and sales settle at DIFFERENT ages — spend closes first, sales keep
-- accruing across the attribution window (SP 7d, SB 14d), so the two columns are read apart.
--
-- Needs a few days of SP_SNAPSHOT_ADS_RESTATEMENT samples before it says anything; until then
-- the newest report dates have no "final" to compare against and are excluded.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_SETTLE_CURVE` AS
WITH
-- the most recent sample per (report_date, channel) = the best "final" we currently have
final AS (
  SELECT report_date, channel,
         ARRAY_AGG(STRUCT(spend, sales, orders) ORDER BY snapshot_at DESC LIMIT 1)[OFFSET(0)] f,
         MAX(age_days) AS observed_to_age
  FROM `onyga-482313.OI.FACT_ADS_RESTATEMENT`
  GROUP BY 1, 2
),
-- the first sample taken at each age
by_age AS (
  SELECT report_date, channel, age_days,
         ARRAY_AGG(STRUCT(spend, sales, orders) ORDER BY snapshot_at ASC LIMIT 1)[OFFSET(0)] a
  FROM `onyga-482313.OI.FACT_ADS_RESTATEMENT`
  GROUP BY 1, 2, 3
)
SELECT
  b.channel,
  b.age_days,
  COUNT(*) AS report_dates,
  -- how complete the number looked at this age, vs what it eventually became
  ROUND(APPROX_QUANTILES(SAFE_DIVIDE(b.a.spend, NULLIF(f.f.spend, 0)), 2)[OFFSET(1)] * 100, 1) AS spend_pct_of_final_median,
  ROUND(APPROX_QUANTILES(SAFE_DIVIDE(b.a.sales, NULLIF(f.f.sales, 0)), 2)[OFFSET(1)] * 100, 1) AS sales_pct_of_final_median,
  ROUND(MIN(SAFE_DIVIDE(b.a.spend, NULLIF(f.f.spend, 0))) * 100, 1) AS spend_pct_worst,
  ROUND(MIN(SAFE_DIVIDE(b.a.sales, NULLIF(f.f.sales, 0))) * 100, 1) AS sales_pct_worst
FROM by_age b
JOIN final f USING (report_date, channel)
-- only judge a date whose "final" is meaningfully older than the sample being scored
WHERE f.observed_to_age >= b.age_days + 2
GROUP BY 1, 2
ORDER BY channel, age_days;
