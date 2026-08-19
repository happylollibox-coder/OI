-- FACT_ADS_RESTATEMENT — measures HOW LONG an ads report-date keeps changing.
--
-- WHY (Ori 2026-08-06: "i want to find the sweet spot that data is fully refreshed"):
-- comparing the warehouse against Amazon for a recent day always disagrees, because the
-- Fivetran feed keeps restating a date for days after it closes. Observed by hand:
--   Aug 4 spend  $1,060.52 (Aug 5 09:30) -> $1,238.95 (Aug 5 15:00) -> $1,443.62 (Aug 6 11:28)
--   Aug 3 spend  $1,447.63 (Aug 5 09:30) -> $1,448.69 (Aug 6 11:28)   = +0.07%, settled
--   Aug 3 sales  $2,581.33 (Aug 5 09:30) -> $2,742.16 (Aug 6 11:28)   = +6.2%, still accruing
-- Ad-hoc observations cannot give a settle CURVE. This table records the same measurement on
-- every orchestrator run, so the answer becomes a query instead of a guess.
--
-- GRAIN: one row per (report_date, snapshot_at, channel). Append-only — never updated, or the
-- restatement history it exists to capture would be erased.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_ADS_RESTATEMENT` (
  report_date   DATE      NOT NULL OPTIONS(description="The ads report date being measured"),
  snapshot_at   TIMESTAMP NOT NULL OPTIONS(description="When this measurement was taken (UTC)"),
  channel       STRING             OPTIONS(description="SP | SB | ALL"),
  spend         FLOAT64            OPTIONS(description="SUM(Ads_cost) for report_date as of snapshot_at"),
  sales         FLOAT64            OPTIONS(description="SUM(Ads_sales) for report_date as of snapshot_at"),
  orders        INT64              OPTIONS(description="SUM(Ads_orders) as of snapshot_at"),
  clicks        INT64              OPTIONS(description="SUM(Ads_clicks) as of snapshot_at"),
  age_days      INT64              OPTIONS(description="LA days between report_date and the snapshot")
)
PARTITION BY report_date
OPTIONS(description="Restatement history of FACT_AMAZON_ADS: how a report date's spend/sales keep moving after the day closes. Appended by SP_SNAPSHOT_ADS_RESTATEMENT on every orchestrator run. Read V_ADS_SETTLE_CURVE for the answer.");
