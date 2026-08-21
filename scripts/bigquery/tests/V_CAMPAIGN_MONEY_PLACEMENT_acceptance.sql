-- =============================================================================================
-- ACCEPTANCE — V_CAMPAIGN_MONEY_PLACEMENT. Runs against the DEPLOYED view in one pass.
-- Every row this returns must read PASS. Deploy:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
--
-- WHAT EACH CHECK PROTECTS, AND WHY IT EXISTS RATHER THAN A REVIEWER READING THE VIEW:
--   A1/A2  The founding complaint behind this design was a total that lied by omission. If a bucket
--          is dropped, renamed out of the spine, or filtered on its way into the roll-up, the money
--          silently leaves the page. These two make that impossible: the buckets must add to the
--          account, in BOTH dollar quantities, to the cent.
--   A3     The same reconciliation at campaign grain, which catches a bucket that double-counts.
--   A4/A5  Every campaign in exactly one bucket. A campaign in two inflates a total; a campaign in
--          none is money that vanished.
--   A6     No campaign in the launch bucket may carry a profitability figure ANYWHERE on its row —
--          not a verdict, not a bar, not a return, not a band, not a shortfall, and not the gross
--          profit itself, because gross profit over spend IS the verdict one division away.
--   A7     Every published row carries a sentence. A silent row is a row nobody reads.
--   A8     The spine is complete and unduplicated, so an empty bucket reads as "no campaigns"
--          rather than disappearing.
--   A9     Unmeasured must never read as losing. A campaign with no measured gross profit may not
--          land in the unprofitable bucket — that COALESCE-to-zero failure has been found three
--          separate times in this warehouse.
--   A10    The band is symmetric and the three judged buckets are exhaustive over the judgeable set,
--          so nothing falls between "clears", "misses" and "too close".
-- =============================================================================================
WITH v AS (SELECT * FROM `onyga-482313.OI.V_CAMPAIGN_MONEY_PLACEMENT`),
acct AS (SELECT budget_per_day AS b, spend_window AS s, n_campaigns AS n FROM v WHERE row_kind = 'ACCOUNT'),
bk   AS (SELECT SUM(budget_per_day) b, SUM(spend_window) s, SUM(n_campaigns) n FROM v WHERE row_kind = 'BUCKET'),
cp   AS (SELECT SUM(budget_per_day) b, SUM(spend_window) s, COUNT(*) n FROM v WHERE row_kind = 'CAMPAIGN')

SELECT 'A1 budget reconciles: buckets = account' AS check,
       FORMAT('%.2f', (SELECT b FROM bk) - (SELECT b FROM acct)) AS gap,
       IF(ROUND((SELECT b FROM bk) - (SELECT b FROM acct), 2) = 0, 'PASS', 'FAIL') AS result
UNION ALL SELECT 'A2 spend reconciles: buckets = account',
       FORMAT('%.2f', (SELECT s FROM bk) - (SELECT s FROM acct)),
       IF(ROUND((SELECT s FROM bk) - (SELECT s FROM acct), 2) = 0, 'PASS', 'FAIL')
UNION ALL SELECT 'A3 campaign rows reconcile to the account, both quantities',
       FORMAT('budget %.2f / spend %.2f', (SELECT b FROM cp) - (SELECT b FROM acct), (SELECT s FROM cp) - (SELECT s FROM acct)),
       IF(ROUND((SELECT b FROM cp) - (SELECT b FROM acct), 2) = 0
          AND ROUND((SELECT s FROM cp) - (SELECT s FROM acct), 2) = 0, 'PASS', 'FAIL')
UNION ALL SELECT 'A4 no campaign in two buckets',
       CAST((SELECT COUNT(*) FROM (SELECT campaign_id FROM v WHERE row_kind='CAMPAIGN' GROUP BY 1 HAVING COUNT(*) > 1)) AS STRING),
       IF((SELECT COUNT(*) FROM (SELECT campaign_id FROM v WHERE row_kind='CAMPAIGN' GROUP BY 1 HAVING COUNT(*) > 1)) = 0, 'PASS', 'FAIL')
UNION ALL SELECT 'A5 no enabled campaign missing from every bucket',
       CAST((SELECT COUNTIF(m.campaign_id IS NULL) FROM
              (SELECT CAST(campaign_id AS STRING) cid FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` WHERE campaign_state='ENABLED') d
              LEFT JOIN (SELECT DISTINCT campaign_id FROM v WHERE row_kind='CAMPAIGN') m ON m.campaign_id = d.cid) AS STRING),
       IF((SELECT COUNTIF(m.campaign_id IS NULL) FROM
              (SELECT CAST(campaign_id AS STRING) cid FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` WHERE campaign_state='ENABLED') d
              LEFT JOIN (SELECT DISTINCT campaign_id FROM v WHERE row_kind='CAMPAIGN') m ON m.campaign_id = d.cid) = 0, 'PASS', 'FAIL')
UNION ALL SELECT 'A6 launch rows carry no profitability figure at all',
       CAST((SELECT COUNTIF(profit_verdict IS NOT NULL OR keyword_bar IS NOT NULL OR gp_roas_window IS NOT NULL
                            OR band_half_width IS NOT NULL OR shortfall_window IS NOT NULL
                            OR gross_profit_window IS NOT NULL) FROM v WHERE bucket_code = 'LAUNCH') AS STRING),
       IF((SELECT COUNTIF(profit_verdict IS NOT NULL OR keyword_bar IS NOT NULL OR gp_roas_window IS NOT NULL
                            OR band_half_width IS NOT NULL OR shortfall_window IS NOT NULL
                            OR gross_profit_window IS NOT NULL) FROM v WHERE bucket_code = 'LAUNCH') = 0, 'PASS', 'FAIL')
UNION ALL SELECT 'A7 every row carries a sentence',
       CAST((SELECT COUNTIF(sentence IS NULL OR LENGTH(TRIM(sentence)) = 0) FROM v) AS STRING),
       IF((SELECT COUNTIF(sentence IS NULL OR LENGTH(TRIM(sentence)) = 0) FROM v) = 0, 'PASS', 'FAIL')
UNION ALL SELECT 'A8 the bucket spine is complete and unduplicated',
       CAST((SELECT COUNT(*) FROM v WHERE row_kind='BUCKET') AS STRING),
       IF((SELECT COUNT(*) FROM v WHERE row_kind='BUCKET') = 8
          AND (SELECT COUNT(DISTINCT bucket_code) FROM v WHERE row_kind='BUCKET') = 8, 'PASS', 'FAIL')
UNION ALL SELECT 'A9 unmeasured never reads as losing',
       CAST((SELECT COUNTIF(gross_profit_window IS NULL) FROM v WHERE row_kind='CAMPAIGN' AND bucket_code='UNPROFITABLE') AS STRING),
       IF((SELECT COUNTIF(gross_profit_window IS NULL) FROM v WHERE row_kind='CAMPAIGN' AND bucket_code='UNPROFITABLE') = 0, 'PASS', 'FAIL')
UNION ALL SELECT 'A10 the three judged buckets are exhaustive over the judgeable set',
       CAST((SELECT COUNTIF(NOT (
              (gp_roas_window - band_half_width >= keyword_bar AND bucket_code='PROFITABLE') OR
              (gp_roas_window + band_half_width <  keyword_bar AND bucket_code='UNPROFITABLE') OR
              (gp_roas_window - band_half_width <  keyword_bar AND gp_roas_window + band_half_width >= keyword_bar
               AND bucket_code='MARGINAL')))
            FROM v WHERE row_kind='CAMPAIGN' AND bucket_code IN ('PROFITABLE','MARGINAL','UNPROFITABLE')) AS STRING),
       IF((SELECT COUNTIF(NOT (
              (gp_roas_window - band_half_width >= keyword_bar AND bucket_code='PROFITABLE') OR
              (gp_roas_window + band_half_width <  keyword_bar AND bucket_code='UNPROFITABLE') OR
              (gp_roas_window - band_half_width <  keyword_bar AND gp_roas_window + band_half_width >= keyword_bar
               AND bucket_code='MARGINAL')))
            FROM v WHERE row_kind='CAMPAIGN' AND bucket_code IN ('PROFITABLE','MARGINAL','UNPROFITABLE')) = 0, 'PASS', 'FAIL')
ORDER BY 1;
