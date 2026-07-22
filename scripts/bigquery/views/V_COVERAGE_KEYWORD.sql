-- V_COVERAGE_KEYWORD — coverage-cockpit reconciler, Stage 3 (S3 rung).
--
-- Grain: one row per (parent_name × match_type × keyword_text).
-- Reconciles keywords that ARE RUNNING (V_KEYWORD_DAILY, last 90d) against keywords that are
-- RECOMMENDED-but-not-yet-advertised (FACT_RESEARCH_RECOMMENDATIONS latest week, status='NEW'),
-- enriched with relevance (FACT_RESEARCH_RANKED) and the intent-theme is_relevant flag
-- (V_INTENT_KEYWORDS). Emits a per-keyword `status` so the cockpit can surface orphan waste
-- (running+enabled but off-strategy/irrelevant) and missing coverage (recommended, not running).
--
-- net_profit := SUM(V_KEYWORD_DAILY.net_proxy) over 90d, where net_proxy = sales_14d − ad cost.
--   It is AFTER ad cost but is NOT true net profit (no COGS; sales_14d is a 14d-rolling proxy).
--   Used as a directional earn-vs-waste signal per the S3 spec (Ori 2026-07-21).
-- orphan rule (MODERATE, Ori 2026-07-21): running+enabled keyword that is either flagged
--   not-relevant (is_relevant=FALSE) OR has no research rank at all (research_rank IS NULL).
--
-- cell_key = CONCAT('INTENT|', parent_name) — keyword coverage attaches to the Intent family cell.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COVERAGE_KEYWORD` AS
WITH
-- ── RUNNING: live keyword×day rolled to (family, keyword, match) over 90d ──
running AS (
  SELECT
    parent_name,
    LOWER(keyword_text) AS keyword_text,
    match_type,
    CAST(SUM(clicks) AS INT64) AS clicks,
    SUM(cost) AS cost,
    SUM(net_proxy) AS net_profit,                                   -- see header caveat
    ARRAY_AGG(ad_keyword_status ORDER BY date DESC LIMIT 1)[OFFSET(0)] AS kw_status,
    MAX(date) AS last_seen,
    ARRAY_AGG(DISTINCT campaign_id IGNORE NULLS) AS campaign_ids
  FROM `onyga-482313.OI.V_KEYWORD_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    AND parent_name IS NOT NULL
    AND keyword_text IS NOT NULL
    AND match_type IS NOT NULL
  GROUP BY parent_name, LOWER(keyword_text), match_type
),
-- ── MISSING: recommended-but-not-advertised, latest research week only ──
missing AS (
  SELECT
    parent_name,
    LOWER(query_text) AS keyword_text,
    match_type,
    MIN(rank) AS rec_rank,               -- best (lowest) rank across dupes
    ANY_VALUE(rec_type) AS rec_type
  FROM `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS`
  WHERE status = 'NEW'
    AND week_start = (SELECT MAX(week_start)
                      FROM `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS`
                      WHERE status = 'NEW')
    AND parent_name IS NOT NULL
    AND query_text IS NOT NULL
    AND match_type IS NOT NULL
  GROUP BY parent_name, LOWER(query_text), match_type
),
-- ── RELEVANCE: one row per (family, term), match-agnostic ──
relevance AS (
  SELECT
    parent_name,
    LOWER(query_text) AS keyword_text,
    CAST(MAX(rank) AS INT64) AS research_rank,
    CAST(MAX(overall_fit) AS FLOAT64) AS overall_fit
  FROM `onyga-482313.OI.FACT_RESEARCH_RANKED`
  WHERE parent_name IS NOT NULL AND query_text IS NOT NULL
  GROUP BY parent_name, LOWER(query_text)
),
-- ── INTENT relevance flag + ad return, one row per (family, term) ──
intent_rel AS (
  SELECT
    parent_name,
    LOWER(query_text) AS keyword_text,
    LOGICAL_OR(is_relevant) AS is_relevant,
    MAX(ads_net_roas) AS ads_net_roas
  FROM `onyga-482313.OI.V_INTENT_KEYWORDS`
  WHERE parent_name IS NOT NULL AND query_text IS NOT NULL
  GROUP BY parent_name, LOWER(query_text)
),
-- ── Universe: every (family, match, term) that is running OR recommended ──
keys AS (
  SELECT DISTINCT parent_name, match_type, keyword_text
  FROM (
    SELECT parent_name, match_type, keyword_text FROM running
    UNION ALL
    SELECT parent_name, match_type, keyword_text FROM missing
  )
)
SELECT
  k.parent_name,
  k.match_type,
  k.keyword_text,
  (r.keyword_text IS NOT NULL) AS is_running,
  COALESCE(r.kw_status = 'ENABLED', FALSE) AS is_enabled,
  (m.keyword_text IS NOT NULL) AS is_recommended,
  COALESCE(r.clicks, 0) AS clicks,
  r.cost,
  r.net_profit,
  rel.research_rank,
  rel.overall_fit,
  ir.is_relevant,
  ir.ads_net_roas,
  m.rec_type,
  r.last_seen,
  CASE
    WHEN (r.keyword_text IS NOT NULL) AND COALESCE(r.kw_status = 'ENABLED', FALSE)
         AND (ir.is_relevant = FALSE OR rel.research_rank IS NULL) THEN 'orphan'
    WHEN (r.keyword_text IS NOT NULL) AND COALESCE(r.kw_status = 'ENABLED', FALSE) THEN 'running'
    WHEN (r.keyword_text IS NOT NULL) AND NOT COALESCE(r.kw_status = 'ENABLED', FALSE) THEN 'paused'
    WHEN (r.keyword_text IS NULL) AND (m.keyword_text IS NOT NULL) THEN 'missing'
    ELSE 'other'
  END AS status,
  CONCAT('INTENT|', k.parent_name) AS cell_key
FROM keys k
LEFT JOIN running    r  ON r.parent_name = k.parent_name
                       AND r.match_type  = k.match_type
                       AND r.keyword_text = k.keyword_text
LEFT JOIN missing    m  ON m.parent_name = k.parent_name
                       AND m.match_type  = k.match_type
                       AND m.keyword_text = k.keyword_text
LEFT JOIN relevance  rel ON rel.parent_name = k.parent_name
                        AND rel.keyword_text = k.keyword_text
LEFT JOIN intent_rel ir  ON ir.parent_name = k.parent_name
                        AND ir.keyword_text = k.keyword_text
