-- =============================================
-- V_AMAZON_OBSERVED_CHANGES — every change the DIM SCD2 trail shows on Amazon, one row per changed
-- attribute (2026-10-01, learning-system Task B). Read by SP_RECORD_OBSERVED_CHANGES, which writes
-- the rows inside the ledger scope into FACT_PPC_CHANGE_LOG, and by
-- scripts/bigquery/tests/OBSERVED_CHANGES_acceptance.sql, which checks the ledger against it. One
-- derivation, read by both, so the procedure and its test cannot drift apart.
-- SOP: architecture/PPC_CLOSE_THE_LOOP.md §Observed changes.
--
-- SOURCE. DIM_KEYWORD / DIM_CAMPAIGN / DIM_AD_GROUP are SCD2 copies of Fivetran's Amazon Ads mirror
-- (SP_LOAD_DIM_KEYWORD / _CAMPAIGN / _AD_GROUP, Refresh Tasks 2 / 2.1 / 2.2). A new version is
-- written whenever a tracked field differs from the current one. Each version is paired here with
-- its predecessor: LAG over the entity's history ordered by effective_from, then _fivetran_synced.
-- The old loads left duplicate (id, effective_from) pairs in DIM_AD_GROUP and DIM_CAMPAIGN; each
-- pair carries identical tracked values and two different _fivetran_synced stamps (Q1), so the
-- order is fixed and a duplicate never reads as a change.
--
-- WHAT IS A CHANGE (one row per changed attribute):
--   DIM_KEYWORD   bid          INCREASE_BID / REDUCE_BID                          old_bid -> new_bid
--                 state        KEYWORD_PAUSE / KEYWORD_ENABLE / KEYWORD_ARCHIVE    old_state -> new_state
--   DIM_CAMPAIGN  daily_budget BUDGET_CHANGE                                      old_budget -> new_budget
--                 state        CAMPAIGN_PAUSE / CAMPAIGN_ENABLE / CAMPAIGN_ARCHIVE
--   DIM_AD_GROUP  default_bid  ADGROUP_DEFAULT_BID                                old_bid -> new_bid
--                 state        ADGROUP_PAUSE / ADGROUP_ENABLE / ADGROUP_ARCHIVE
-- The FIRST version of an entity has no predecessor. That is a creation (a new keyword, a new ad
-- group), not a change, and it is never a row here: a new keyword's opening bid is not a raise,
-- and a scorecard window around it would grade a launch, not a decision.
-- A bid that is NULL on either side is not a bid change: a pause can clear the bid in the same
-- version (Q2 lists those versions), and that is one KEYWORD_PAUSE row, not a bid cut.
-- States are compared in UPPER() (the SB mirror writes 'enabled' / 'paused', SP writes 'ENABLED').
-- A state outside {ENABLED, PAUSED, ARCHIVED} on either side is not a state change (older
-- DIM_KEYWORD rows carry an empty state, Q3). Serving-status, name, portfolio, bidding-strategy and
-- match-type versions carry no action here and produce no row.
--
-- TIME. effective_from is a DATETIME holding the UTC wall clock: SP_LOAD_DIM_* write
-- CAST(<Fivetran TIMESTAMP> AS DATETIME), which keeps the UTC reading. Q4 checks it: versions whose
-- effective_from IS the sync stamp equal it read in UTC and never read in America/Los_Angeles.
-- applied_at = TIMESTAMP(effective_from, 'UTC') is therefore the real instant,
-- and change_date_la = DATE(applied_at, 'America/Los_Angeles') is the LA day, derived the same way
-- every reader of FACT_PPC_CHANGE_LOG derives it.
-- What the instant MEANS depends on the mirror: for SP keywords, SP product targets and campaigns
-- it is Amazon's own last_updated_date (the moment the change was saved in the console); for SB
-- keywords (the sb_keyword mirror keeps no history) it is the Fivetran sync that first saw the new
-- value, up to a day after the real change. Two changes between consecutive DIM loads collapse into
-- one version and therefore one row (SP_LOAD_DIM_KEYWORD compares only the latest source row).
--
-- change_id = 'obs|<DIM table>|<entity id>|<attribute>|<effective_from to the microsecond>' —
-- deterministic, so the procedure finds its own rows on every re-run and inserts nothing twice.
-- in_ledger_scope = effective_from after 2026-08-20 00:00 UTC, the start of the backfill: the
-- ledger in FACT_PPC_CHANGE_LOG starts there (the log itself carried the changes before it).
--
-- QUERIES (this header states no measured number):
-- Q1 duplicate (id, effective_from) pairs: how many, and do their values or sync stamps differ?
--   SELECT COUNT(*) pairs, COUNTIF(nvals > 1) differing_values, COUNTIF(nsync = 1) same_sync FROM (
--     SELECT ad_group_id, effective_from, COUNT(DISTINCT FORMAT('%T', (default_bid, state))) nvals,
--            COUNT(DISTINCT _fivetran_synced) nsync
--     FROM `onyga-482313.OI.DIM_AD_GROUP` GROUP BY 1, 2 HAVING COUNT(*) > 1);   -- and the same on DIM_CAMPAIGN
-- Q2 versions in the ledger scope whose bid became or stopped being NULL, with the state move beside them:
--   SELECT DATE(effective_from) d, prev_state, state, prev_bid, bid, COUNT(*) FROM (
--     SELECT effective_from, bid, UPPER(state) state,
--            LAG(bid) OVER w prev_bid, LAG(UPPER(state)) OVER w prev_state, LAG(effective_from) OVER w prev_from
--     FROM `onyga-482313.OI.DIM_KEYWORD` WINDOW w AS (PARTITION BY keyword_id ORDER BY effective_from, _fivetran_synced))
--   WHERE prev_from IS NOT NULL AND effective_from > '2026-08-20' AND (bid IS NULL) != (prev_bid IS NULL)
--   GROUP BY 1, 2, 3, 4, 5 ORDER BY 1;
-- Q3 empty states, all time and in the ledger scope:
--   SELECT COUNTIF(NULLIF(TRIM(state), '') IS NULL) all_time,
--          COUNTIF(NULLIF(TRIM(state), '') IS NULL AND effective_from > '2026-08-20') in_scope
--   FROM `onyga-482313.OI.DIM_KEYWORD`;
-- Q4 the clock: versions equal to their sync stamp read in UTC vs read in Los Angeles:
--   SELECT COUNT(*) n, COUNTIF(effective_from = DATETIME(_fivetran_synced)) eq_utc,
--          COUNTIF(effective_from = DATETIME(_fivetran_synced, 'America/Los_Angeles')) eq_la
--   FROM `onyga-482313.OI.DIM_KEYWORD` WHERE effective_from > '2026-08-20';
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_AMAZON_OBSERVED_CHANGES` AS
WITH
k AS (SELECT DATETIME '2026-08-20 00:00:00' AS ledger_from),
kw AS (
  SELECT keyword_id, ad_group_id, campaign_id, keyword_text, match_type, bid, effective_from,
         UPPER(NULLIF(TRIM(state), ''))                AS state,
         LAG(bid)                              OVER w  AS prev_bid,
         LAG(UPPER(NULLIF(TRIM(state), '')))   OVER w  AS prev_state,
         LAG(effective_from)                   OVER w  AS prev_from
  FROM `onyga-482313.OI.DIM_KEYWORD`
  WINDOW w AS (PARTITION BY keyword_id ORDER BY effective_from, _fivetran_synced)
),
cp AS (
  SELECT campaign_id, daily_budget, effective_from,
         UPPER(NULLIF(TRIM(state), ''))                AS state,
         LAG(daily_budget)                     OVER w  AS prev_budget,
         LAG(UPPER(NULLIF(TRIM(state), '')))   OVER w  AS prev_state,
         LAG(effective_from)                   OVER w  AS prev_from
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  WINDOW w AS (PARTITION BY campaign_id ORDER BY effective_from, _fivetran_synced)
),
ag AS (
  SELECT ad_group_id, campaign_id, default_bid, effective_from,
         UPPER(NULLIF(TRIM(state), ''))                AS state,
         LAG(default_bid)                      OVER w  AS prev_bid,
         LAG(UPPER(NULLIF(TRIM(state), '')))   OVER w  AS prev_state,
         LAG(effective_from)                   OVER w  AS prev_from
  FROM `onyga-482313.OI.DIM_AD_GROUP`
  WINDOW w AS (PARTITION BY ad_group_id ORDER BY effective_from, _fivetran_synced)
),
pairs AS (
  -- keyword / product-target bid
  SELECT 'DIM_KEYWORD' AS entity, 'bid' AS attr, keyword_id AS entity_id, effective_from, prev_from,
         IF(bid > prev_bid, 'INCREASE_BID', 'REDUCE_BID') AS action,
         keyword_text AS targeting, keyword_id, UPPER(match_type) AS match_type, campaign_id, ad_group_id,
         prev_bid AS old_bid, bid AS new_bid,
         CAST(NULL AS FLOAT64) AS old_budget, CAST(NULL AS FLOAT64) AS new_budget,
         CAST(NULL AS STRING) AS old_state, CAST(NULL AS STRING) AS new_state
  FROM kw
  WHERE prev_from IS NOT NULL
    AND bid IS NOT NULL AND prev_bid IS NOT NULL AND ABS(bid - prev_bid) > 0.0001
  UNION ALL
  -- keyword / product-target state
  SELECT 'DIM_KEYWORD', 'state', keyword_id, effective_from, prev_from,
         CASE state WHEN 'PAUSED' THEN 'KEYWORD_PAUSE' WHEN 'ENABLED' THEN 'KEYWORD_ENABLE' ELSE 'KEYWORD_ARCHIVE' END,
         keyword_text, keyword_id, UPPER(match_type), campaign_id, ad_group_id,
         NULL, NULL, NULL, NULL, prev_state, state
  FROM kw
  WHERE prev_from IS NOT NULL
    AND state IN ('ENABLED', 'PAUSED', 'ARCHIVED') AND prev_state IN ('ENABLED', 'PAUSED', 'ARCHIVED')
    AND state != prev_state
  UNION ALL
  -- campaign daily budget
  SELECT 'DIM_CAMPAIGN', 'daily_budget', campaign_id, effective_from, prev_from,
         'BUDGET_CHANGE',
         NULL, NULL, NULL, campaign_id, NULL,
         NULL, NULL, prev_budget, daily_budget, NULL, NULL
  FROM cp
  WHERE prev_from IS NOT NULL
    AND daily_budget IS NOT NULL AND prev_budget IS NOT NULL AND ABS(daily_budget - prev_budget) > 0.001
  UNION ALL
  -- campaign state
  SELECT 'DIM_CAMPAIGN', 'state', campaign_id, effective_from, prev_from,
         CASE state WHEN 'PAUSED' THEN 'CAMPAIGN_PAUSE' WHEN 'ENABLED' THEN 'CAMPAIGN_ENABLE' ELSE 'CAMPAIGN_ARCHIVE' END,
         NULL, NULL, NULL, campaign_id, NULL,
         NULL, NULL, NULL, NULL, prev_state, state
  FROM cp
  WHERE prev_from IS NOT NULL
    AND state IN ('ENABLED', 'PAUSED', 'ARCHIVED') AND prev_state IN ('ENABLED', 'PAUSED', 'ARCHIVED')
    AND state != prev_state
  UNION ALL
  -- ad group default bid
  SELECT 'DIM_AD_GROUP', 'default_bid', ad_group_id, effective_from, prev_from,
         'ADGROUP_DEFAULT_BID',
         NULL, NULL, NULL, campaign_id, ad_group_id,
         prev_bid, default_bid, NULL, NULL, NULL, NULL
  FROM ag
  WHERE prev_from IS NOT NULL
    AND default_bid IS NOT NULL AND prev_bid IS NOT NULL AND ABS(default_bid - prev_bid) > 0.0001
  UNION ALL
  -- ad group state
  SELECT 'DIM_AD_GROUP', 'state', ad_group_id, effective_from, prev_from,
         CASE state WHEN 'PAUSED' THEN 'ADGROUP_PAUSE' WHEN 'ENABLED' THEN 'ADGROUP_ENABLE' ELSE 'ADGROUP_ARCHIVE' END,
         NULL, NULL, NULL, campaign_id, ad_group_id,
         NULL, NULL, NULL, NULL, prev_state, state
  FROM ag
  WHERE prev_from IS NOT NULL
    AND state IN ('ENABLED', 'PAUSED', 'ARCHIVED') AND prev_state IN ('ENABLED', 'PAUSED', 'ARCHIVED')
    AND state != prev_state
)
SELECT
  CONCAT('obs|', p.entity, '|', p.entity_id, '|', p.attr, '|',
         FORMAT_DATETIME('%Y-%m-%dT%H:%M:%E6S', p.effective_from))   AS change_id,
  p.entity, p.attr, p.entity_id,
  p.effective_from, p.prev_from                                      AS prev_effective_from,
  TIMESTAMP(p.effective_from, 'UTC')                                 AS applied_at,
  DATE(TIMESTAMP(p.effective_from, 'UTC'), 'America/Los_Angeles')   AS change_date_la,
  p.action, p.targeting, p.keyword_id, p.match_type, p.campaign_id, p.ad_group_id,
  dc.campaign_name, dc.campaign_type,
  p.old_bid, p.new_bid, p.old_budget, p.new_budget, p.old_state, p.new_state,
  (p.effective_from > k.ledger_from)                                 AS in_ledger_scope
FROM pairs p
CROSS JOIN k
LEFT JOIN `onyga-482313.OI.DIM_CAMPAIGN` dc
  ON dc.campaign_id = p.campaign_id AND dc.is_current = TRUE
-- belt and braces: two versions with one (entity, effective_from) would mint one change_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY change_id ORDER BY p.new_bid, p.new_budget, p.new_state, p.old_bid, p.old_budget, p.old_state) = 1;
