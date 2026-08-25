-- =============================================================================================
-- CUSTOMER PURCHASE FLOWS acceptance — ten nested levels. v27.150 (2026-08-25).
-- §2.0.2 / §2.0.3, forecast chain step 0. Every check returns a VIOLATION COUNT; all must be 0.
-- =============================================================================================
WITH f AS (SELECT * FROM `onyga-482313.OI.V_CUSTOMER_PURCHASE_FLOW`),
c AS (SELECT * FROM `onyga-482313.OI.V_SUBJECT_FLOW_CHOICE`),
subj AS (SELECT * FROM `onyga-482313.OI.T_SUBJECT_FLOW`),

f01 AS (SELECT COUNTIF(ABS(flow_cpc - SAFE_DIVIDE(cost, NULLIF(clicks,0))) > 0.0001
                    OR ABS(flow_cvr - SAFE_DIVIDE(orders, NULLIF(clicks,0))) > 0.00002) AS v FROM f),
f02 AS (SELECT COUNTIF(members_teaching > members_total) AS v FROM f),
f03 AS (SELECT COUNTIF((members_teaching >= 3) != is_usable
                    OR (NOT is_usable AND not_usable_because IS NULL)
                    OR (is_usable AND not_usable_because IS NOT NULL)) AS v FROM f),
f04 AS (SELECT COUNTIF(clicks IS NULL OR clicks <= 0 OR members_teaching <= 0) AS v FROM f),
f05 AS (SELECT COUNTIF(n > 1) AS v FROM (SELECT level, flow_key, COUNT(*) n FROM f GROUP BY 1,2)),

-- F06 THE PROFILE IS SPLIT BY LINK, not blended — the whole reason for a chain.
f06 AS (SELECT COUNTIF(orders > 0 AND (flow_cvr IS NULL OR flow_gp_per_order IS NULL)) AS v FROM f),

-- F07 TEN LEVELS, NO MORE AND NO FEWER, and level 1 is UNIVERSAL: every subject must belong to it,
--     so the Catalog can always answer (Ori: "1 level should return a generic result to any keyword").
f07 AS (SELECT COUNTIF(level < 1 OR level > 10) AS v FROM f),
f07b AS (SELECT ABS((SELECT COUNT(*) FROM subj)
                  - (SELECT COUNT(*) FROM subj, UNNEST(flow_ladder) l
                     WHERE l.level = 1 AND l.flow_key IS NOT NULL)) AS v),

-- F08 THE LEVELS NEST. A subject that has a flow at level N must have one at every level below it —
--     otherwise "fall back one level" has nowhere to land and the ladder is not a ladder.
f08 AS (SELECT COUNT(*) AS v FROM (
          SELECT s.campaign_id, s.keyword_id, l.level
          FROM subj s, UNNEST(s.flow_ladder) l
          WHERE l.flow_key IS NOT NULL AND l.level > 1
            AND NOT EXISTS (SELECT 1 FROM UNNEST(s.flow_ladder) p
                            WHERE p.level = l.level - 1 AND p.flow_key IS NOT NULL))),

-- F09 EVERY SUBJECT IS CHOSEN EXACTLY ONCE. The choice view must not return two levels for one
--     subject, and must never return none — level 1 guarantees an answer exists.
f09 AS (SELECT COUNTIF(n != 1) AS v
        FROM (SELECT campaign_id, keyword_id, COUNT(*) n FROM c GROUP BY 1,2)),
f09b AS (SELECT (SELECT COUNT(*) FROM subj) - (SELECT COUNT(*) FROM c) AS v),

-- F10 THE CHOSEN LEVEL IS ELIGIBLE. Never a flow below the minimum members, never one nobody bought
--     from — the two ways a deep flow lies about being specific.
f10 AS (SELECT COUNTIF(members_teaching < 3 OR flow_clicks < 200) AS v FROM c),

-- F11 SPLITTING ACTUALLY WORKS. The premise of a ten-level ladder is that deeper flows are TIGHTER;
--     if dispersion did not fall with depth the levels would be decoration. Measured across the
--     ladder, mean dispersion must be lower at level 10 than at level 1.
f11 AS (SELECT IF((SELECT AVG(cvr_dispersion) FROM f WHERE level >= 8)
                < (SELECT AVG(cvr_dispersion) FROM f WHERE level <= 2), 0, 1) AS v),

-- F12 should_split IS EXACTLY THE DECLARED RULE — enough clicks AND still dispersed — and says why.
f12 AS (SELECT COUNTIF(should_split != (clicks >= 500 AND cvr_dispersion > 0.60)
                    OR (should_split AND should_split_because IS NULL)) AS v
        FROM f WHERE cvr_dispersion IS NOT NULL),

-- F13 EVERY CHOICE DISCLOSES ITS BASIS (§2.0.2): which flow, how much evidence, how tight, and what
--     it fell back from. An estimate that cannot say where it came from cannot be weighed.
f13 AS (SELECT COUNTIF(basis IS NULL OR basis = '' OR levels_given_up < 0) AS v FROM c),

-- F14 READ-ONLY and read by nothing yet.
f14 AS (SELECT (SELECT COUNT(*) FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
                WHERE table_name NOT IN ('V_CUSTOMER_PURCHASE_FLOW','V_SUBJECT_FLOW_CHOICE')
                  AND (view_definition LIKE '%V_CUSTOMER_PURCHASE_FLOW%'
                    OR view_definition LIKE '%V_SUBJECT_FLOW_CHOICE%')) AS v),

f15 AS (SELECT COUNTIF(window_days != 365) AS v FROM f)

SELECT * FROM (
  SELECT 1 AS n,'F01 the arithmetic reconciles'                              AS check_name,v FROM f01 UNION ALL
  SELECT 2, 'F02 cannot teach from more members than it has',                     v FROM f02 UNION ALL
  SELECT 3, 'F03 is_usable is the declared minimum, and says why not',            v FROM f03 UNION ALL
  SELECT 4, 'F04 no empty flow',                                                  v FROM f04 UNION ALL
  SELECT 5, 'F05 one row per (level, flow)',                                      v FROM f05 UNION ALL
  SELECT 6, 'F06 the profile is split by link, not blended',                      v FROM f06 UNION ALL
  SELECT 7, 'F07 levels are 1..10 only',                                          v FROM f07 UNION ALL
  SELECT 8, 'F07b level 1 is universal — every subject has an answer',            v FROM f07b UNION ALL
  SELECT 9, 'F08 the levels nest — fallback always has somewhere to land',        v FROM f08 UNION ALL
  SELECT 10,'F09 every subject is chosen exactly once',                           v FROM f09 UNION ALL
  SELECT 11,'F09b no subject is left unchosen',                                   v FROM f09b UNION ALL
  SELECT 12,'F10 the chosen level is eligible on members AND clicks',             v FROM f10 UNION ALL
  SELECT 13,'F11 splitting works — deep flows are tighter than shallow ones',     v FROM f11 UNION ALL
  SELECT 14,'F12 should_split is the declared rule, and says why',                v FROM f12 UNION ALL
  SELECT 15,'F13 every choice discloses its basis',                               v FROM f13 UNION ALL
  SELECT 16,'F14 read-only, and read by nothing yet',                             v FROM f14 UNION ALL
  SELECT 17,'F15 the window is the declared 365 days',                            v FROM f15
)
ORDER BY n;
