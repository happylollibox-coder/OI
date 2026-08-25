-- =============================================================================================
-- V_CUSTOMER_PURCHASE_FLOW acceptance — §2.0.2, forecast chain step 0. v27.149 (2026-08-25).
-- Every check returns a VIOLATION COUNT; every row must read PASS.
-- =============================================================================================
WITH f AS (SELECT * FROM `onyga-482313.OI.V_CUSTOMER_PURCHASE_FLOW`),

-- F01 THE ARITHMETIC RECONCILES. Each published link figure must equal its own definition, or the
--     flow is quoting numbers that came from somewhere else.
f01 AS (SELECT COUNTIF(ABS(flow_cpc - SAFE_DIVIDE(cost, NULLIF(clicks,0))) > 0.0001
                    OR ABS(flow_cvr - SAFE_DIVIDE(orders, NULLIF(clicks,0))) > 0.00002) AS v FROM f),

-- F02 A FLOW CANNOT TEACH FROM MORE MEMBERS THAN IT HAS.
f02 AS (SELECT COUNTIF(members_teaching > members_total) AS v FROM f),

-- F03 is_usable IS EXACTLY the declared minimum test, and an unusable flow says why.
f03 AS (SELECT COUNTIF((members_teaching >= 3) != is_usable
                    OR (NOT is_usable AND not_usable_because IS NULL)
                    OR (is_usable AND not_usable_because IS NOT NULL)) AS v FROM f),

-- F04 NO EMPTY FLOW. A flow with no clicks taught nothing and must not exist.
f04 AS (SELECT COUNTIF(clicks IS NULL OR clicks <= 0 OR members_teaching <= 0) AS v FROM f),

-- F05 ONE ROW PER FLOW.
f05 AS (SELECT COUNTIF(n > 1) AS v FROM (SELECT flow_key, COUNT(*) n FROM f GROUP BY 1)),

-- F06 THE PROFILE IS SPLIT BY LINK, not blended. Each link must be separately present wherever the
--     evidence exists for it — that is the whole purpose (Ori: 'split the forecast in order to
--     understand what is working good and what is not'). A flow with orders must publish a CVR and a
--     GP per order; one that publishes only a blended ROAS could never name the broken link.
f06 AS (SELECT COUNTIF(orders > 0 AND (flow_cvr IS NULL OR flow_gp_per_order IS NULL)) AS v FROM f),

-- F07 NO SUBJECT IS AMBIGUOUS — it maps to at most ONE flow. Two flows for one subject would mean
--     two different assumptions could be quoted for the same answer, which is the failure that
--     matters. Mapping to NONE is not a failure: it means no member of that flow had enough clicks
--     to teach it, so the subject is honestly UNKNOWN and publishes nulls (§2.0.2). The first cut of
--     this check demanded EXACTLY one and flagged `SP|PHRASE_KEYWORD|UNSPECIFIED`, a flow whose only
--     member has under 30 clicks in a year — the abstention working, not a defect.
f07 AS (
  SELECT COUNTIF(flows > 1) AS v FROM (
    SELECT m.campaign_id, m.keyword_id, COUNT(DISTINCT f.flow_key) AS flows
    FROM `onyga-482313.OI.T_SUBJECT_FLOW` m
    LEFT JOIN f ON f.flow_key = m.flow_key
    GROUP BY 1,2)),

-- F08 DISPERSION IS PUBLISHED WHEREVER IT CAN BE. A flow that hides how spread its members are is an
--     assumption pretending to be tighter than it is.
f08 AS (SELECT COUNTIF(members_teaching >= 2 AND cvr_dispersion IS NULL AND flow_cvr > 0) AS v FROM f),

-- F09 READ-ONLY, and read by nothing yet.
f09 AS (SELECT (SELECT COUNT(*) FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
                WHERE table_name='V_CUSTOMER_PURCHASE_FLOW' AND table_type != 'VIEW')
             + (SELECT COUNT(*) FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
                WHERE table_name != 'V_CUSTOMER_PURCHASE_FLOW'
                  AND view_definition LIKE '%V_CUSTOMER_PURCHASE_FLOW%') AS v),

-- F11 ABSTENTION STAYS RARE AND VISIBLE. Subjects whose flow could not be learned are legitimate
--     UNKNOWNs, but if that population suddenly grows the mapping or the teaching threshold has
--     broken and every forecast quietly degrades. A declared ceiling of 10 % turns a silent
--     regression into a red check.
f11 AS (SELECT IF(SAFE_DIVIDE(COUNTIF(f.flow_key IS NULL), COUNT(*)) > 0.10, 1, 0) AS v
        FROM `onyga-482313.OI.T_SUBJECT_FLOW` m
        LEFT JOIN f ON f.flow_key = m.flow_key),

-- F10 THE WINDOW IS THE DECLARED ONE (§2.0.2: 365 days, not 180).
f10 AS (SELECT COUNTIF(window_days != 365) AS v FROM f)

SELECT * FROM (
  SELECT 1 AS n, 'F01 the arithmetic reconciles'                        AS check_name, v FROM f01 UNION ALL
  SELECT 2,  'F02 cannot teach from more members than it has',              v FROM f02 UNION ALL
  SELECT 3,  'F03 is_usable is the declared minimum, and says why not',     v FROM f03 UNION ALL
  SELECT 4,  'F04 no empty flow',                                           v FROM f04 UNION ALL
  SELECT 5,  'F05 one row per flow',                                        v FROM f05 UNION ALL
  SELECT 6,  'F06 the profile is split by link, not blended',               v FROM f06 UNION ALL
  SELECT 7,  'F07 no subject is ambiguous (maps to at most one flow)',        v FROM f07 UNION ALL
  SELECT 8,  'F08 dispersion is published wherever it can be',              v FROM f08 UNION ALL
  SELECT 9,  'F09 read-only, and read by nothing yet',                      v FROM f09 UNION ALL
  SELECT 10, 'F10 the window is the declared 365 days',                     v FROM f10 UNION ALL
  SELECT 11, 'F11 abstention stays under the declared 10% ceiling',          v FROM f11
)
ORDER BY n;
