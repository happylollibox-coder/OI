-- =============================================
-- V_UNOWNED_SPEND / V_UNOWNED_SPEND_SUMMARY — acceptance suite (2026-08-25).
-- Doctrine: architecture/THREE_LAYERS.md §1.4. SOP: architecture/UNOWNED_SPEND.md.
--
-- HOW TO RUN (house rule — never cat a .sql into bq):
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
--     "$(grep -v '^--' scripts/bigquery/tests/V_UNOWNED_SPEND_acceptance.sql)"
--
-- EVERY ROW MUST READ pass = TRUE. `violations` is a COUNT, so a failure says how big it is rather
-- than only that it happened — which is what makes this suite usable as a regression check and what
-- let it be written failing-first: the first deployment of the view was deliberately built with a
-- loose anti-join (keyword_id only, no campaign_id) and no final reason arm, and this suite
-- returned measured violation counts on A1 and A2 before the real view was deployed.
--
-- WHAT IT ASSERTS
--   A1  every row genuinely has NO row in FACT_KEYWORD_STATE (the population's whole claim)
--   A2  the classification is exhaustive AND a partition — no blank reason, no value outside the
--       declared vocabulary, and no reason that maps to two classes
--   A3  the account reconciles against FACT_AMAZON_ADS: unowned + owned = the account, exactly
--   A4  the summary's classes partition its own total. NOTE THE TOLERANCE, and note that it is
--       DERIVED rather than picked: the summary ROUNDs each class to cents independently, so n
--       class rows can sit up to n x 0.005 away from the rounded total with nothing wrong. The
--       tolerance is 0.005 x (classes + 1), computed from the row count at run time. At a flat 0.01
--       this assertion failed on its first run against a CORRECT summary — a false positive of
--       exactly the kind V_FAMILY_BAR's header warns about — which is why it is computed here.
--   A5  determinism — two independent evaluations of the view agree, hash for hash
--   A6  the grain is one row per (campaign, keyword, target)
--   A7  unmeasured never reads as bad — no bar distance is published without both a bar and a reading
--   A8  no verdict is issued — the view publishes no verdict/state/action column
--   A9  the view is a VIEW, its definition contains no DML or DDL, and nothing in the warehouse
--       reads it — it creates and mutates nothing
--   A10 lineage — the population and the spend equal the baseline probe's own query, re-run
--       (docs/superpowers/specs/2026-08-24-three-layers-baseline.md, "OUTSIDE THE CATALOG ENTIRELY")
-- =============================================
WITH
u AS (SELECT * FROM `onyga-482313.OI.V_UNOWNED_SPEND`),
s AS (SELECT * FROM `onyga-482313.OI.V_UNOWNED_SPEND_SUMMARY`),
w AS (SELECT MAX(as_of) AS as_of, MAX(window_days) AS window_days FROM u),
cat AS (
  SELECT DISTINCT campaign_id, keyword_id
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
),
-- Every spending (campaign, keyword) pair in the same window, split by whether the Catalog has it.
pairs AS (
  SELECT a.campaign_id, a.keyword_id, SUM(a.Ads_cost) / w.window_days AS spend_d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  CROSS JOIN w
  WHERE a.date BETWEEN DATE_SUB(w.as_of, INTERVAL w.window_days - 1 DAY) AND w.as_of
    AND a.keyword_id IS NOT NULL
  GROUP BY a.campaign_id, a.keyword_id, w.window_days
  HAVING SUM(a.Ads_cost) > 0
),
recon AS (
  SELECT
    SUM(p.spend_d)                                            AS pair_spend,
    SUM(IF(c.keyword_id IS NULL, p.spend_d, 0))               AS unowned_spend,
    SUM(IF(c.keyword_id IS NOT NULL, p.spend_d, 0))           AS owned_spend,
    COUNTIF(c.keyword_id IS NULL)                             AS unowned_pairs
  FROM pairs p LEFT JOIN cat c ON c.campaign_id = p.campaign_id AND c.keyword_id = p.keyword_id
),
acct AS (
  SELECT SUM(a.Ads_cost) / w.window_days AS account_spend_d,
         SUM(IF(a.keyword_id IS NULL, a.Ads_cost, 0)) / w.window_days AS null_key_spend_d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  CROSS JOIN w
  WHERE a.date BETWEEN DATE_SUB(w.as_of, INTERVAL w.window_days - 1 DAY) AND w.as_of
  GROUP BY w.window_days
),
-- A5: two INDEPENDENT evaluations of the view, hashed. Same query text would let the planner reuse
-- one scan, so the two arms are deliberately shaped differently (one ordered by spend, one by key)
-- and reduced with an ORDER-INDEPENDENT aggregate, which is what makes agreement meaningful.
det_a AS (
  SELECT BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS h,
         SUM(MOD(ABS(FARM_FINGERPRINT(TO_JSON_STRING(t))), 1000003)) AS h2, COUNT(*) AS n
  FROM (SELECT * FROM `onyga-482313.OI.V_UNOWNED_SPEND` ORDER BY spend_per_day_28d DESC) t
),
det_b AS (
  SELECT BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS h,
         SUM(MOD(ABS(FARM_FINGERPRINT(TO_JSON_STRING(t))), 1000003)) AS h2, COUNT(*) AS n
  FROM (SELECT * FROM `onyga-482313.OI.V_UNOWNED_SPEND`
        ORDER BY campaign_id, keyword_id, target_text) t
),
-- A9: the object's own definition, and every other view in the dataset that might read it.
defn AS (
  SELECT table_name, view_definition
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
  WHERE table_name IN ('V_UNOWNED_SPEND', 'V_UNOWNED_SPEND_SUMMARY')
),
kind AS (
  SELECT table_name, table_type
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
  WHERE table_name IN ('V_UNOWNED_SPEND', 'V_UNOWNED_SPEND_SUMMARY')
),
readers AS (
  SELECT COUNT(*) AS n
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
  WHERE REGEXP_CONTAINS(view_definition, r'V_UNOWNED_SPEND')
    AND table_name NOT IN ('V_UNOWNED_SPEND', 'V_UNOWNED_SPEND_SUMMARY')
),
cols AS (
  SELECT COUNT(*) AS n
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'V_UNOWNED_SPEND'
    AND REGEXP_CONTAINS(LOWER(column_name), r'verdict|state|action|instruction|suggest')
    AND column_name NOT IN ('verdict_withheld_because', 'campaign_state', 'subject_state')
),
-- A10: the baseline probe's own population test, re-run verbatim on this view's window.
baseline AS (
  SELECT COUNTIF(c.keyword_id IS NULL) AS rows_outside, ROUND(SUM(IF(c.keyword_id IS NULL, p.spend_d, 0)), 2) AS spend_outside
  FROM pairs p LEFT JOIN cat c ON c.campaign_id = p.campaign_id AND c.keyword_id = p.keyword_id
),
vocab AS (
  SELECT ['SENTINEL_TARGET_ID', 'CAMPAIGN_ABSENT_FROM_DIM', 'CAMPAIGN_NOT_ENABLED',
          'SUBJECT_ABSENT_FROM_DIM_KEYWORD', 'SUBJECT_NOT_ENABLED', 'IN_UNIVERSE_NO_STATE_ROW'] AS reasons,
         ['SENTINEL', 'CAMPAIGN_OUTSIDE_UNIVERSE', 'SUBJECT_OUTSIDE_UNIVERSE',
          'DROPPED_DOWNSTREAM'] AS classes
)

SELECT 1 AS ord, 'A1 every row genuinely has NO row in FACT_KEYWORD_STATE' AS assertion,
  (SELECT COUNT(*) FROM u JOIN cat c ON c.campaign_id = u.campaign_id AND c.keyword_id = u.keyword_id) AS violations,
  (SELECT COUNT(*) FROM u JOIN cat c ON c.campaign_id = u.campaign_id AND c.keyword_id = u.keyword_id) = 0 AS pass,
  CONCAT('rows in view = ', (SELECT CAST(COUNT(*) AS STRING) FROM u),
         '; of them, present in the latest keyword-state snapshot = ',
         (SELECT CAST(COUNT(*) AS STRING) FROM u JOIN cat c ON c.campaign_id = u.campaign_id AND c.keyword_id = u.keyword_id)) AS evidence

UNION ALL
SELECT 2, 'A2 classification is exhaustive and a partition',
  (SELECT COUNT(*) FROM u CROSS JOIN vocab v
   WHERE u.reason IS NULL OR TRIM(u.reason) = '' OR u.reason_class IS NULL OR TRIM(u.reason_class) = ''
      OR u.reason NOT IN UNNEST(v.reasons) OR u.reason_class NOT IN UNNEST(v.classes))
  + (SELECT COUNT(*) FROM (SELECT reason FROM u GROUP BY reason HAVING COUNT(DISTINCT reason_class) > 1)),
  ((SELECT COUNT(*) FROM u CROSS JOIN vocab v
    WHERE u.reason IS NULL OR TRIM(u.reason) = '' OR u.reason_class IS NULL OR TRIM(u.reason_class) = ''
       OR u.reason NOT IN UNNEST(v.reasons) OR u.reason_class NOT IN UNNEST(v.classes))
   + (SELECT COUNT(*) FROM (SELECT reason FROM u GROUP BY reason HAVING COUNT(DISTINCT reason_class) > 1))) = 0,
  CONCAT('reasons present: ', (SELECT STRING_AGG(DISTINCT reason ORDER BY reason) FROM u),
         ' | classes present: ', (SELECT STRING_AGG(DISTINCT reason_class ORDER BY reason_class) FROM u),
         ' | rows with a blank or unknown label: ',
         (SELECT CAST(COUNT(*) AS STRING) FROM u CROSS JOIN vocab v
          WHERE u.reason IS NULL OR TRIM(u.reason) = '' OR u.reason NOT IN UNNEST(v.reasons)))

UNION ALL
SELECT 3, 'A3 the account reconciles against FACT_AMAZON_ADS',
  (SELECT COUNTIF(ABS(r.unowned_spend + r.owned_spend + a.null_key_spend_d - a.account_spend_d) > 0.01)
        + COUNTIF(ABS((SELECT SUM(spend_per_day_28d) FROM u) - r.unowned_spend) > 0.01)
   FROM recon r CROSS JOIN acct a),
  (SELECT COUNTIF(ABS(r.unowned_spend + r.owned_spend + a.null_key_spend_d - a.account_spend_d) > 0.01)
        + COUNTIF(ABS((SELECT SUM(spend_per_day_28d) FROM u) - r.unowned_spend) > 0.01)
   FROM recon r CROSS JOIN acct a) = 0,
  (SELECT CONCAT('account $', FORMAT('%.2f', a.account_spend_d), '/day = owned $',
                 FORMAT('%.2f', r.owned_spend), ' + unowned $', FORMAT('%.2f', r.unowned_spend),
                 ' + unkeyed $', FORMAT('%.2f', a.null_key_spend_d),
                 '; view sums to $', FORMAT('%.2f', (SELECT SUM(spend_per_day_28d) FROM u)),
                 ' at target grain over ', (SELECT CAST(COUNT(*) AS STRING) FROM u), ' rows / ',
                 (SELECT CAST(COUNT(DISTINCT CONCAT(campaign_id, '|', keyword_id)) AS STRING) FROM u),
                 ' pairs')
   FROM recon r CROSS JOIN acct a)

UNION ALL
SELECT 4, 'A4 the summary classes partition the summary total',
  (SELECT COUNTIF(ABS(part_spend - all_spend) > tol) + COUNTIF(part_subj <> all_subj)
          + COUNTIF(ABS(part_spend7 - all_spend7) > tol)
   FROM (SELECT
           (SELECT SUM(spend_per_day_28d) FROM s WHERE reason_class <> '__ALL__') AS part_spend,
           (SELECT SUM(spend_per_day_28d) FROM s WHERE reason_class  = '__ALL__') AS all_spend,
           (SELECT SUM(spend_per_day_7d)  FROM s WHERE reason_class <> '__ALL__') AS part_spend7,
           (SELECT SUM(spend_per_day_7d)  FROM s WHERE reason_class  = '__ALL__') AS all_spend7,
           (SELECT SUM(subjects) FROM s WHERE reason_class <> '__ALL__')          AS part_subj,
           (SELECT SUM(subjects) FROM s WHERE reason_class  = '__ALL__')          AS all_subj,
           (SELECT 0.005 * (COUNT(*) + 1) FROM s WHERE reason_class <> '__ALL__') AS tol)),
  (SELECT COUNTIF(ABS(part_spend - all_spend) > tol) + COUNTIF(part_subj <> all_subj)
          + COUNTIF(ABS(part_spend7 - all_spend7) > tol)
   FROM (SELECT
           (SELECT SUM(spend_per_day_28d) FROM s WHERE reason_class <> '__ALL__') AS part_spend,
           (SELECT SUM(spend_per_day_28d) FROM s WHERE reason_class  = '__ALL__') AS all_spend,
           (SELECT SUM(spend_per_day_7d)  FROM s WHERE reason_class <> '__ALL__') AS part_spend7,
           (SELECT SUM(spend_per_day_7d)  FROM s WHERE reason_class  = '__ALL__') AS all_spend7,
           (SELECT SUM(subjects) FROM s WHERE reason_class <> '__ALL__')          AS part_subj,
           (SELECT SUM(subjects) FROM s WHERE reason_class  = '__ALL__')          AS all_subj,
           (SELECT 0.005 * (COUNT(*) + 1) FROM s WHERE reason_class <> '__ALL__') AS tol)) = 0,
  CONCAT('classes sum to $',
         (SELECT FORMAT('%.2f', SUM(spend_per_day_28d)) FROM s WHERE reason_class <> '__ALL__'),
         '/day over ', (SELECT CAST(SUM(subjects) AS STRING) FROM s WHERE reason_class <> '__ALL__'),
         ' subjects; __ALL__ reads $',
         (SELECT FORMAT('%.2f', SUM(spend_per_day_28d)) FROM s WHERE reason_class = '__ALL__'),
         '/day over ', (SELECT CAST(SUM(subjects) AS STRING) FROM s WHERE reason_class = '__ALL__'))

UNION ALL
SELECT 5, 'A5 determinism — two independent evaluations agree',
  (SELECT COUNTIF(a.h <> b.h) + COUNTIF(a.h2 <> b.h2) + COUNTIF(a.n <> b.n) FROM det_a a CROSS JOIN det_b b),
  (SELECT COUNTIF(a.h <> b.h) + COUNTIF(a.h2 <> b.h2) + COUNTIF(a.n <> b.n) FROM det_a a CROSS JOIN det_b b) = 0,
  (SELECT CONCAT('rows ', CAST(a.n AS STRING), ' vs ', CAST(b.n AS STRING),
                 '; xor ', CAST(a.h AS STRING), ' vs ', CAST(b.h AS STRING),
                 '; checksum ', CAST(a.h2 AS STRING), ' vs ', CAST(b.h2 AS STRING))
   FROM det_a a CROSS JOIN det_b b)

UNION ALL
SELECT 6, 'A6 grain is one row per (campaign, keyword, target)',
  (SELECT COUNT(*) FROM (SELECT campaign_id, keyword_id, target_text FROM u
                         GROUP BY 1, 2, 3 HAVING COUNT(*) > 1)),
  (SELECT COUNT(*) FROM (SELECT campaign_id, keyword_id, target_text FROM u
                         GROUP BY 1, 2, 3 HAVING COUNT(*) > 1)) = 0,
  CONCAT((SELECT CAST(COUNT(*) AS STRING) FROM u), ' rows, ',
         (SELECT CAST(COUNT(DISTINCT CONCAT(campaign_id, '|', keyword_id, '|', target_text)) AS STRING) FROM u),
         ' distinct keys')

UNION ALL
SELECT 7, 'A7 unmeasured never reads as bad',
  (SELECT COUNTIF(reading <> 'MEASURED' AND gp_roas_minus_bar_28d IS NOT NULL)
        + COUNTIF(family_bar IS NULL AND gp_roas_minus_bar_28d IS NOT NULL)
        + COUNTIF(judgeability = 'HAS_BAR' AND (family_bar IS NULL OR reading <> 'MEASURED'))
        + COUNTIF(verdict_withheld_because IS NULL OR TRIM(verdict_withheld_because) = '') FROM u),
  (SELECT COUNTIF(reading <> 'MEASURED' AND gp_roas_minus_bar_28d IS NOT NULL)
        + COUNTIF(family_bar IS NULL AND gp_roas_minus_bar_28d IS NOT NULL)
        + COUNTIF(judgeability = 'HAS_BAR' AND (family_bar IS NULL OR reading <> 'MEASURED'))
        + COUNTIF(verdict_withheld_because IS NULL OR TRIM(verdict_withheld_because) = '') FROM u) = 0,
  CONCAT('judgeability split: ',
         (SELECT STRING_AGG(CONCAT(judgeability, '=', CAST(n AS STRING)), ', ' ORDER BY judgeability)
          FROM (SELECT judgeability, COUNT(*) AS n FROM u GROUP BY judgeability)),
         ' | rows publishing a bar distance: ',
         (SELECT CAST(COUNTIF(gp_roas_minus_bar_28d IS NOT NULL) AS STRING) FROM u))

UNION ALL
SELECT 8, 'A8 no verdict is issued — no verdict/state/action column',
  (SELECT n FROM cols),
  (SELECT n FROM cols) = 0,
  CONCAT('columns matching verdict|state|action|instruction|suggest, excluding the three named ',
         'exceptions (verdict_withheld_because, campaign_state, subject_state): ',
         (SELECT CAST(n AS STRING) FROM cols))

UNION ALL
SELECT 9, 'A9 read-only — it is a VIEW, its definition holds no DML/DDL, and nothing reads it',
  (SELECT COUNTIF(REGEXP_CONTAINS(UPPER(view_definition),
     r'\b(INSERT|UPDATE|DELETE|MERGE|TRUNCATE|DROP|ALTER|CALL|EXPORT DATA|CREATE\s+(OR\s+REPLACE\s+)?(TABLE|FUNCTION|PROCEDURE))\b'))
   FROM defn)
  + (SELECT COUNTIF(table_type <> 'VIEW') FROM kind)
  + (SELECT IF(COUNT(*) <> 2, 1, 0) FROM defn)
  + (SELECT n FROM readers),
  ((SELECT COUNTIF(REGEXP_CONTAINS(UPPER(view_definition),
     r'\b(INSERT|UPDATE|DELETE|MERGE|TRUNCATE|DROP|ALTER|CALL|EXPORT DATA|CREATE\s+(OR\s+REPLACE\s+)?(TABLE|FUNCTION|PROCEDURE))\b'))
    FROM defn)
   + (SELECT COUNTIF(table_type <> 'VIEW') FROM kind)
   + (SELECT IF(COUNT(*) <> 2, 1, 0) FROM defn)
   + (SELECT n FROM readers)) = 0,
  CONCAT('objects found: ', (SELECT CAST(COUNT(*) AS STRING) FROM defn),
         ' | table_type(s): ', (SELECT STRING_AGG(DISTINCT table_type) FROM kind),
         ' | other views referencing them: ', (SELECT CAST(n AS STRING) FROM readers),
         ' | DML/DDL keywords in either definition: ',
         (SELECT CAST(COUNTIF(REGEXP_CONTAINS(UPPER(view_definition),
            r'\b(INSERT|UPDATE|DELETE|MERGE|TRUNCATE|DROP|ALTER|CALL|EXPORT DATA|CREATE\s+(OR\s+REPLACE\s+)?(TABLE|FUNCTION|PROCEDURE))\b')) AS STRING)
          FROM defn))

UNION ALL
SELECT 10, 'A10 lineage — population and spend equal the baseline probe, re-run',
  (SELECT COUNTIF(b.rows_outside <> (SELECT COUNT(DISTINCT CONCAT(campaign_id, '|', keyword_id)) FROM u))
        + COUNTIF(ABS(b.spend_outside - (SELECT ROUND(SUM(spend_per_day_28d), 2) FROM u)) > 0.01)
   FROM baseline b),
  (SELECT COUNTIF(b.rows_outside <> (SELECT COUNT(DISTINCT CONCAT(campaign_id, '|', keyword_id)) FROM u))
        + COUNTIF(ABS(b.spend_outside - (SELECT ROUND(SUM(spend_per_day_28d), 2) FROM u)) > 0.01)
   FROM baseline b) = 0,
  (SELECT CONCAT('baseline probe: ', CAST(b.rows_outside AS STRING), ' pairs at $',
                 FORMAT('%.2f', b.spend_outside), '/day; view: ',
                 (SELECT CAST(COUNT(DISTINCT CONCAT(campaign_id, '|', keyword_id)) AS STRING) FROM u),
                 ' pairs at $', (SELECT FORMAT('%.2f', SUM(spend_per_day_28d)) FROM u), '/day over ',
                 (SELECT CAST(COUNT(*) AS STRING) FROM u), ' target-grain rows')
   FROM baseline b)

ORDER BY ord;
