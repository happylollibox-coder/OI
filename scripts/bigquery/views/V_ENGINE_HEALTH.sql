-- =============================================
-- V_ENGINE_HEALTH — the engine's standing self-check, one row per check (2026-08-16, Task 3.3).
-- Spec: architecture/ENGINE_HEALTH.md.
--
-- (Ori 2026-08-15: the engine "should always check himself.") Every check reads SMALL tables
-- except the scorecard (ceiling view), which appears exactly once — the shared `sc` CTE below,
-- read by BOTH #6 and #7. Statuses are the VIEW's — GREEN / AMBER / RED / INFO — with the
-- threshold printed beside the measurement so a reader never has to guess what "bad" means.
-- A quiet board is the goal state, not a malfunction.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ENGINE_HEALTH` AS
WITH pf AS (SELECT * FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`),
ks AS (SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
-- ONE shared scorecard scan (review 2026-08-16, planner safety): c6 and c7 both read THIS CTE.
-- Before this, c7 read V_MANUAL_DIVERGENCE, which embeds its own full V_CHANGE_SCORECARD scan —
-- two copies of the ceiling view inlined into one statement.
sc AS (
  SELECT source, verdict, change_date, change_id, campaign_id, keyword_id, action_group,
         SAFE_CAST(new_value AS FLOAT64) AS new_val
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD`
),

c1 AS (  -- contradiction rate: EXCLUDE share of the day's instructions
  SELECT 'contradiction_rate' AS check_name,
    ROUND(SAFE_DIVIDE(COUNTIF(verdict = 'EXCLUDE'), COUNT(*)) * 100, 1) AS measured,
    'EXCLUDE % of instructions · amber > 5, red > 15 (iteration-6 found 29.9 unGated)' AS threshold,
    CASE WHEN SAFE_DIVIDE(COUNTIF(verdict = 'EXCLUDE'), COUNT(*)) > 0.15 THEN 'RED'
         WHEN SAFE_DIVIDE(COUNTIF(verdict = 'EXCLUDE'), COUNT(*)) > 0.05 THEN 'AMBER'
         ELSE 'GREEN' END AS status,
    CONCAT(CAST(COUNTIF(verdict = 'EXCLUDE') AS STRING), ' of ', CAST(COUNT(*) AS STRING),
           ' instructions excluded by ownership — high is not broken (the gate is WORKING) but says the engines overlap a lot') AS detail
  FROM pf
),
c2 AS (  -- single voice: no key+lever with two live instructions
  -- v27.72: the key mirrors SP_ENGINE_PREFLIGHT's key_id — NEGATE rows key on the TERM (they
  -- have no keyword_id; without the term, every negate in a campaign is one false "overlap")
  SELECT 'ownership_overlaps',
    CAST(COUNT(*) AS FLOAT64),
    'keys with >1 non-EXCLUDE instruction · red > 0',
    IF(COUNT(*) > 0, 'RED', 'GREEN'),
    'one key, one lever, one voice — the preflight assertion, standing'
  FROM (SELECT campaign_id,
               IF(grain = 'NEGATE', CONCAT('term|', LOWER(TRIM(COALESCE(target_text, '')))),
                  COALESCE(keyword_id, '')) k,
               lever
        FROM pf GROUP BY 1, 2, 3 HAVING COUNTIF(verdict != 'EXCLUDE') > 1)
),
c3 AS (  -- state invariant 1
  SELECT 'state_duplicate', CAST(COUNT(*) AS FLOAT64),
    'keywords in two states · red > 0', IF(COUNT(*) > 0, 'RED', 'GREEN'),
    'V_KEYWORD_STATE invariant 1'
  FROM (SELECT campaign_id, keyword_id FROM ks GROUP BY 1, 2 HAVING COUNT(*) > 1)
),
c4 AS (  -- state invariant 2
  SELECT 'missing_appointment',
    CAST(COUNTIF(next_check_date IS NULL AND state != 'DEAD') AS FLOAT64),
    'non-DEAD keywords with no next appointment · red > 0',
    IF(COUNTIF(next_check_date IS NULL AND state != 'DEAD') > 0, 'RED', 'GREEN'),
    'V_KEYWORD_STATE invariant 2 — every keyword has a date something re-judges it'
  FROM ks
),
c5 AS (  -- overdue appointments (found on the state machine's first day)
  SELECT 'overdue_appointments',
    CAST(COUNTIF(next_check_date < CURRENT_DATE('America/Los_Angeles') AND state != 'DEAD') AS FLOAT64),
    'appointments in the past · amber > 50 (judgments due that nothing has re-run)',
    CASE WHEN COUNTIF(next_check_date < CURRENT_DATE('America/Los_Angeles') AND state != 'DEAD') > 50
         THEN 'AMBER' ELSE 'GREEN' END,
    CONCAT('oldest: ', CAST(MIN(IF(next_check_date < CURRENT_DATE('America/Los_Angeles'), next_check_date, NULL)) AS STRING))
  FROM ks
),
c6 AS (  -- outcome mix, trailing settled window (reads the shared sc scan — the ceiling view's one appearance)
  SELECT 'scorecard_reversed_share',
    ROUND(SAFE_DIVIDE(COUNTIF(verdict = 'REVERSED'), NULLIF(COUNTIF(verdict != 'INSUFFICIENT'), 0)) * 100, 1),
    'REVERSED % of judged, changes from the last 42d · amber > 35 (measured era baseline 46)',
    CASE WHEN SAFE_DIVIDE(COUNTIF(verdict = 'REVERSED'), NULLIF(COUNTIF(verdict != 'INSUFFICIENT'), 0)) > 0.35
         THEN 'AMBER' ELSE 'GREEN' END,
    CONCAT(CAST(COUNTIF(verdict != 'INSUFFICIENT') AS STRING), ' judged · ',
           CAST(COUNTIF(verdict = 'INSUFFICIENT') AS STRING), ' too thin to judge')
  FROM sc
  WHERE change_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 42 DAY)
),
c7 AS (  -- the human-vs-model ledger: MANUAL_BETTER rows demand a model fix
  -- PLANNER SAFETY (review 2026-08-16): this DUPLICATES V_MANUAL_DIVERGENCE's kind logic BY
  -- DESIGN instead of reading that view — the view embeds its own full V_CHANGE_SCORECARD scan,
  -- and stacking it beside c6 put two copies of the ceiling view in one statement. Kind here =
  -- OVERRODE: a same-day non-EXCLUDE proposal exists on the key+lever (owning engine first, the
  -- view's priority order) and the hand's value diverges > 5% from it (a proposal carrying no
  -- value diverges by definition — the view's ELSE). MANUAL_BETTER = OVERRODE + CONFIRMED.
  -- Both definitions are owned by architecture/MANUAL_DIVERGENCE.md — change them together.
  SELECT 'manual_better_unresolved',
    CAST(COUNT(DISTINCT s.change_id) AS FLOAT64),
    'OVERRODE changes where the hand beat the model · INFO until resolution tracking exists',
    IF(COUNT(DISTINCT s.change_id) > 0, 'AMBER', 'GREEN'),
    'doctrine: each one ends as a threshold change or a documented disagreement (MANUAL_DIVERGENCE.md)'
  FROM sc s
  JOIN (
    -- v27.72: NEGATE rows key on the term and are OVERRODE-exempt (a negate has no value to
    -- diverge from) — the lever filter below keeps this check to the value levers.
    SELECT snapshot_date, campaign_id, COALESCE(keyword_id, '') AS kid,
           CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever,
           suggested_bid, suggested_budget
    FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
    WHERE COALESCE(verdict, '') != 'EXCLUDE' AND grain != 'NEGATE'
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY snapshot_date, campaign_id, COALESCE(keyword_id, ''),
                   CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END
      ORDER BY CASE engine WHEN 'LOW_STOCK' THEN 1 WHEN 'LAUNCH' THEN 2 WHEN 'OOB' THEN 3
                           WHEN 'REVERDICT' THEN 4 WHEN 'LIFT' THEN 5 WHEN 'COACH' THEN 6 ELSE 9 END) = 1
  ) p ON p.snapshot_date = s.change_date
     AND p.campaign_id = s.campaign_id
     AND p.kid = COALESCE(s.keyword_id, '')
     AND p.lever = IF(s.action_group IN ('BUDGET_UP', 'BUDGET_DOWN'), 'BUDGET', 'BID')
  WHERE s.source = 'MANUAL' AND s.verdict = 'CONFIRMED'
    AND (COALESCE(p.suggested_bid, p.suggested_budget) IS NULL
         OR ABS(COALESCE(s.new_val, 0) - COALESCE(p.suggested_bid, p.suggested_budget))
            > 0.05 * COALESCE(p.suggested_bid, p.suggested_budget))
),
c8 AS (  -- snapshot freshness: the memory must not silently stop
  SELECT 'snapshot_freshness',
    CAST(DATE_DIFF(CURRENT_DATE('America/Los_Angeles'),
                   (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`), DAY) AS FLOAT64),
    'days since the last proposal snapshot · red > 2',
    IF(DATE_DIFF(CURRENT_DATE('America/Los_Angeles'),
                 (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`), DAY) > 2, 'RED', 'GREEN'),
    'FACT_ENGINE_PROPOSALS — without the memory, nothing learns'
),
c9 AS (  -- no-op leakage: engines carry their own guards; the gate counts what still leaks
  SELECT 'noop_leakage',
    CAST(COUNTIF(verdict_reason LIKE 'no-op%') AS FLOAT64),
    'instructions that were no-ops at the gate · amber > 10 (ladder thrash)',
    IF(COUNTIF(verdict_reason LIKE 'no-op%') > 10, 'AMBER', 'GREEN'),
    'v27.29/v27.46 no-op guards should catch these upstream; the gate is the belt'
  FROM pf
),
c10 AS (  -- v27.101: view-body headroom — no view may creep up on BigQuery's hard ceiling unseen
  -- V_KEYWORD_LIFT reached the ceiling with a fraction of a percent to spare and nothing measured
  -- it, so the discovery came from a change that would not fit. Past the ceiling a view can no
  -- longer be edited at all, only migrated, and the migration lands under whatever deadline
  -- happens to expose it. This check fires while the fix is still an edit.
  --   Declared constants: ceiling 262,144 characters (BigQuery's maximum view query length),
  --   amber at 70% of it, red at 85%.
  -- The number is CHARACTERS, matching LENGTH() and BigQuery's own limit — not bytes, which
  -- overstate any view whose commentary carries non-ASCII text.
  -- Pre-deploy twin (measures the repo files, before BigQuery ever sees them):
  --   python3 scripts/bigquery/check_view_body_size.py
  SELECT 'view_body_headroom',
    ROUND(MAX(LENGTH(view_definition)) / 262144 * 100, 2),
    'largest view body as % of the 262,144-character ceiling · amber > 70, red > 85',
    CASE WHEN MAX(LENGTH(view_definition)) > 262144 * 0.85 THEN 'RED'
         WHEN MAX(LENGTH(view_definition)) > 262144 * 0.70 THEN 'AMBER'
         ELSE 'GREEN' END,
    CONCAT('largest is ',
           ARRAY_AGG(table_name ORDER BY LENGTH(view_definition) DESC LIMIT 1)[OFFSET(0)],
           ' — comment markers in column 0 cost nothing (the deploy strips them), indented ones ',
           'are shipped to BigQuery and charged against the ceiling')
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
)
SELECT * FROM c1 UNION ALL SELECT * FROM c2 UNION ALL SELECT * FROM c3
UNION ALL SELECT * FROM c4 UNION ALL SELECT * FROM c5 UNION ALL SELECT * FROM c6
UNION ALL SELECT * FROM c7 UNION ALL SELECT * FROM c8 UNION ALL SELECT * FROM c9
UNION ALL SELECT * FROM c10;
