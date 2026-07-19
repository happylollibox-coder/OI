-- FN_ADS_ANCHOR_CAP — the calendar cutoff for the launch controller's "last complete day" anchor.
--
-- Ads data (FACT_AMAZON_ADS) is America/Los_Angeles time. The anchor is LEAST(MAX(date), FN_ADS_ANCHOR_CAP()).
-- Normally the cap is YESTERDAY (LA) so the incomplete current day never shows false-low spend/ROAS. BUT once
-- the LA day is within its last 2 hours (hour >= 22), sales are effectively done for the day (Ori 2026-07-18),
-- so the current day counts as "complete enough" and becomes eligible as the anchor. This lets a user in a
-- timezone ahead of LA see the current LA date as "last day" late in the LA evening instead of waiting for
-- LA midnight. Trade-off: the last ~2h + any ads-reporting lag may still be settling.
CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_ADS_ANCHOR_CAP`() AS (
  IF(EXTRACT(HOUR FROM CURRENT_DATETIME('America/Los_Angeles')) >= 22,
     CURRENT_DATE('America/Los_Angeles'),
     DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY))
);
