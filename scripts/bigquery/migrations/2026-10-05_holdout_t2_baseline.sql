-- =============================================
-- 2026-10-05 — holdout trial 2: the founding baseline (plan docs/superpowers/plans/2026-10-03-holdout-restart.md
-- §2.7 kind 4, Task 2 Step 3b, Task 3 "The baseline"; deploy step 2 of Task 8, right after the founding file).
--
-- WHAT. One DE_HOLDOUT_BASELINE row per PRESENT setting of each watched control: trial 2's HOLDOUT units
-- whose assignment_rule starts 'FOUNDING', read back from DE_HOLDOUT_ASSIGNMENT (never an id literal).
-- A watched control with no present setting gets no row and is still compared by c33. Absence is not
-- recorded: a setting absent today that is present later is a touch.
--
-- THE PRESENCE RULE. The CTEs hu_k4_sp .. hu_k4_present below are V_ENGINE_HEALTH.sql's c33 text
-- verbatim (the runbook checks the two blocks are equal before it runs anything): a row counts only when
-- its _fivetran_synced is within 1 hour of its table's MAX(_fivetran_synced), and an SB product target
-- only when it is not _fivetran_deleted. K12 (tests/HOLDOUT_RESTART_acceptance.sql) re-reads the four
-- sources by the same text and compares (campaign_id, setting, value) right after this script.
--
-- RUN ORDER AND RUN-ONCE. After 2026-10-05_holdout_t2_founding.sql (the second ASSERT needs its 12
-- founding controls). The first ASSERT refuses a second run: a second founding row for a key would read
-- as a re-baselined setting (c33 AMBER). The third refuses to write when the sources show no present
-- setting for any watched control (an empty read would pass K12's comparison). If this script fails, the
-- founding rows stand (they are the record): fix and run this script again on its own, before deploy
-- step 3 (plan Task 3).
-- Measured 2026-10-04 at the 02:14 UTC sync (plan Appendix C11): 15 settings on 8 controls.
-- =============================================
ASSERT (SELECT COUNT(*) FROM `onyga-482313.OI.DE_HOLDOUT_BASELINE`
        WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2') = 0
  AS 'trial 2 already has baseline rows: the founding baseline runs once';
ASSERT (SELECT COUNT(*) FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
        WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2' AND unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT'
          AND STARTS_WITH(assignment_rule, 'FOUNDING')) = 12
  AS 'trial 2 does not have its 12 founding controls: run 2026-10-05_holdout_t2_founding.sql first';
CREATE TEMP TABLE present AS
WITH
watch AS (  -- kind 4's watched set: trial 2's founding controls
  SELECT unit_id FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2' AND unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT'
    AND STARTS_WITH(assignment_rule, 'FOUNDING')),
hu_k4_sp  AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM `fivetran-hl.amazon_ads.campaign_placement_bidding`),
hu_k4_sbp AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM `fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_by_placement`),
hu_k4_sbc AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM `fivetran-hl.amazon_ads.sb_campaign_bid_adjustments_shopper_cohort`),
hu_k4_sbt AS (SELECT *, MAX(_fivetran_synced) OVER () AS mx FROM `fivetran-hl.amazon_ads.sb_product_target`),
hu_k4_present AS (  -- the presence rule: re-stamped by its table's latest sync, and not deleted
  SELECT campaign_id, CONCAT('SP_PLACEMENT|', placement) AS setting, CAST(percentage AS STRING) AS value
  FROM hu_k4_sp WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR)
  UNION ALL SELECT campaign_id, CONCAT('SB_PLACEMENT|', placement), CAST(percentage AS STRING)
  FROM hu_k4_sbp WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR)
  UNION ALL SELECT campaign_id, CONCAT('SB_SHOPPER_COHORT|', audience_id, '|', shopper_cohort_type),
         CAST(percentage AS STRING)
  FROM hu_k4_sbc WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR)
  UNION ALL SELECT campaign_id, CONCAT('SB_TARGET|', id, '|', kv.k), kv.v
  FROM hu_k4_sbt, UNNEST([STRUCT('bid' AS k, CAST(bid AS STRING) AS v), STRUCT('state', state)]) kv
  WHERE _fivetran_synced >= TIMESTAMP_SUB(mx, INTERVAL 1 HOUR) AND NOT COALESCE(_fivetran_deleted, FALSE)),
synced AS (  -- each source's latest sync at this read
  SELECT 'SP_PLACEMENT' AS kind, 'campaign_placement_bidding' AS source, MAX(mx) AS synced_at FROM hu_k4_sp
  UNION ALL SELECT 'SB_PLACEMENT', 'sb_campaign_bid_adjustments_by_placement', MAX(mx) FROM hu_k4_sbp
  UNION ALL SELECT 'SB_SHOPPER_COHORT', 'sb_campaign_bid_adjustments_shopper_cohort', MAX(mx) FROM hu_k4_sbc
  UNION ALL SELECT 'SB_TARGET', 'sb_product_target', MAX(mx) FROM hu_k4_sbt)
SELECT p.campaign_id, p.setting, p.value, s.source, s.synced_at
FROM hu_k4_present p
JOIN synced s ON s.kind = SPLIT(p.setting, '|')[OFFSET(0)]
WHERE p.campaign_id IN (SELECT unit_id FROM watch);
ASSERT (SELECT COUNT(*) FROM present) > 0
  AS 'no present setting on any watched control: the four sources read empty, nothing written';
INSERT INTO `onyga-482313.OI.DE_HOLDOUT_BASELINE`
  (trial_id, campaign_id, setting, recorded_at, value, source, source_synced_at, ruling)
SELECT 'HOLDOUT-2026Q4-CAMPAIGN-T2', campaign_id, setting, CURRENT_TIMESTAMP(), value, source, synced_at,
       CAST(NULL AS STRING)
FROM present;
SELECT 'baseline_written' AS check_name,
       (SELECT COUNT(*) FROM present) - (SELECT COUNT(*) FROM `onyga-482313.OI.DE_HOLDOUT_BASELINE`
                                          WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2' AND ruling IS NULL) AS violations,
       (SELECT FORMAT('%d rows on %d controls (%s)', COUNT(*), COUNT(DISTINCT campaign_id),
                      STRING_AGG(DISTINCT SPLIT(setting, '|')[OFFSET(0)], ', '))
        FROM present) AS detail;
