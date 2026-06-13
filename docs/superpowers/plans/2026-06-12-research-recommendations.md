# Research Recommendations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per product family, surface 4 types of net-new keyword recommendations (Exact / Phrase / Broad / Brand defense) for terms we aren't advertising, capped at 5 new per type/family/week, persisted for the coacher and shown read-only on the Research page.

**Architecture:** A candidate view (`V_RESEARCH_RECOMMENDATION_CANDIDATES`) emits per-family qualifying terms by type off `FACT_RESEARCH_RANKED` + a 7-day not-advertised gate. A weekly idempotent SP (`SP_REFRESH_RESEARCH_RECOMMENDATIONS`) computes the Broad co-occurrence clusters and Phrase coverage, dedups against history, tops up to 5 new per type/family/week into `FACT_RESEARCH_RECOMMENDATIONS`, and flips NEW→ADVERTISED when a term starts getting clicks. A Flask GET endpoint and a read-only React card surface it; the coacher reads the same table.

**Tech Stack:** BigQuery Standard SQL (bq CLI deploy), Flask + google-cloud-bigquery, React 19 + TypeScript + Vitest.

**Spec:** `docs/superpowers/specs/2026-06-12-research-recommendations-design.md`

**Deployment constraints (from prior research work):**
- BQ deploy: `bq query --use_legacy_sql=false --project_id=onyga-482313 < file.sql`. Deploy order: FACT DDL → candidate view → SP → orchestrator → run SP.
- Confirmed columns: `FACT_RESEARCH_RANKED(parent_name, query_text, rank, overall_fit, brand, weekly_market_impressions, is_holiday_active)`, `FACT_RESEARCH_TERMS(query_text, market_purchases)`, `FACT_AMAZON_ADS(date, search_term, Ads_clicks, ASIN_BY_CAMPAIGN_NAME)`, `FACT_SEARCH_QUERY(ASIN, query_text, week_start_date)`, `DIM_PRODUCT(asin, parent_name, is_active)`.
- Own-brand label = `brand = 'Happy Lolli'`.
- Co-occurrence must stay bounded (we hit BigQuery's per-statement CPU guard with unbounded term cross-joins) — Broad is computed inside the SP via temp tables, restricted to `overall_fit >= 90` seeds.
- Pre-existing uncommitted files in the tree (cube schemas etc.) — only `git add` files this plan touches.

---

### Task 1: SOP — document the recommendations layer

**Files:**
- Modify: `architecture/RESEARCH_PAGE.md`

- [ ] **Step 1.1:** Append a `## Recommendations` section documenting: the 4 types and their filters (table from the spec), the "not advertised = 0 ads clicks in last 7 days" rule, the `FACT_RESEARCH_RECOMMENDATIONS` schema, the weekly top-up/dedup/status logic in `SP_REFRESH_RESEARCH_RECOMMENDATIONS`, the cost-bounded Broad co-occurrence, the coacher-reads-the-table contract, and the `GET /api/research/recommendations` endpoint + `RecommendationsCard`. Add a one-line entry to the `## History` list dated 2026-06-12.

- [ ] **Step 1.2:** Commit:
```bash
git add architecture/RESEARCH_PAGE.md
git commit -m "docs(research): SOP for recommendations layer"
```

### Task 2: `FACT_RESEARCH_RECOMMENDATIONS` table

**Files:**
- Create: `scripts/bigquery/tables/DE/FACT_RESEARCH_RECOMMENDATIONS.sql`

- [ ] **Step 2.1:** Write the DDL:
```sql
-- FACT_RESEARCH_RECOMMENDATIONS
-- Weekly net-new keyword recommendations per family × type (rate-limited to 5 new
-- per type/family/week). Written by SP_REFRESH_RESEARCH_RECOMMENDATIONS; read by the
-- Research page and the coacher. SOP: architecture/RESEARCH_PAGE.md
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS` (
  rec_id STRING NOT NULL,          -- TO_HEX(MD5(parent_name|rec_type|keyword)) — stable identity
  week_start DATE NOT NULL,        -- ISO Monday first emitted
  parent_name STRING NOT NULL,
  rec_type STRING NOT NULL,        -- EXACT | PHRASE | BROAD | BRAND
  match_type STRING NOT NULL,      -- EXACT | PHRASE | BROAD
  keyword STRING NOT NULL,         -- suggested keyword (seed term)
  query_text STRING NOT NULL,      -- source term
  rank FLOAT64,
  overall_fit FLOAT64,
  market_sales INT64,              -- cluster sales (BROAD) or term market purchases
  market_volume INT64,             -- weekly_market_impressions (BRAND ordering/display)
  coverage_count INT64,            -- PHRASE reach (NULL otherwise)
  cluster_size INT64,              -- BROAD cluster size (NULL otherwise)
  status STRING NOT NULL,          -- NEW | ADVERTISED | DISMISSED
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
```

- [ ] **Step 2.2:** Deploy: `bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/tables/DE/FACT_RESEARCH_RECOMMENDATIONS.sql`. Expected: `Created onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS` (or no error if it already exists).

- [ ] **Step 2.3:** Commit:
```bash
git add scripts/bigquery/tables/DE/FACT_RESEARCH_RECOMMENDATIONS.sql
git commit -m "feat(research): FACT_RESEARCH_RECOMMENDATIONS table"
```

### Task 3: `V_RESEARCH_RECOMMENDATION_CANDIDATES` view

**Files:**
- Create: `scripts/bigquery/views/V_RESEARCH_RECOMMENDATION_CANDIDATES.sql`

Emits one row per qualifying (family × term × type), already filtered to not-advertised. Broad rows are *seeds only* (cluster filtering happens in the SP). Phrase `coverage_count` is computed in the SP. `sort_metric` drives the per-type top-5 pick.

- [ ] **Step 3.1:** Write the view:
```sql
-- =============================================
-- V_RESEARCH_RECOMMENDATION_CANDIDATES
-- Per family × term candidates for the 4 recommendation types, filtered to
-- "not advertised" (0 ads clicks in last 7 days for the family). Broad rows are
-- seeds only — SP_REFRESH_RESEARCH_RECOMMENDATIONS computes the co-occurrence
-- cluster + >500-sales filter and Phrase coverage. SOP: architecture/RESEARCH_PAGE.md
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313`.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES AS

WITH advertised_7d AS (
  SELECT DISTINCT p.parent_name, LOWER(a.search_term) AS query_text
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
  JOIN `onyga-482313`.OI.DIM_PRODUCT p ON a.ASIN_BY_CAMPAIGN_NAME = p.asin
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    AND a.Ads_clicks > 0
),
base AS (
  SELECT r.parent_name, r.query_text, r.rank, r.overall_fit, r.brand,
         r.weekly_market_impressions,
         r.holiday, r.is_holiday_active,
         ARRAY_LENGTH(SPLIT(TRIM(r.query_text), ' ')) AS word_count
  FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED r
  LEFT JOIN advertised_7d ad
    ON ad.parent_name = r.parent_name AND ad.query_text = LOWER(r.query_text)
  WHERE ad.query_text IS NULL              -- not advertised
    AND r.query_text != 'OTHER'
    -- off-season holiday terms are rank 0 / not actionable now
    AND (r.holiday IS NULL OR r.is_holiday_active)
)
-- EXACT: not own brand, rank >= 75
SELECT parent_name, query_text, 'EXACT' AS rec_type, 'EXACT' AS match_type,
       query_text AS keyword, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64) AS market_volume,
       rank AS sort_metric
FROM base
WHERE (brand IS NULL OR brand != 'Happy Lolli') AND rank >= 75
UNION ALL
-- PHRASE: not own brand, rank >= 75, >= 3 words
SELECT parent_name, query_text, 'PHRASE', 'PHRASE',
       query_text, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64),
       rank
FROM base
WHERE (brand IS NULL OR brand != 'Happy Lolli') AND rank >= 75 AND word_count >= 3
UNION ALL
-- BROAD seeds: not own brand, fit >= 90 (cluster filter in SP)
SELECT parent_name, query_text, 'BROAD', 'BROAD',
       query_text, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64),
       overall_fit
FROM base
WHERE (brand IS NULL OR brand != 'Happy Lolli') AND overall_fit >= 90
UNION ALL
-- BRAND defense: own brand, any rank/fit; ordered by market volume
SELECT parent_name, query_text, 'BRAND', 'PHRASE',
       query_text, rank, overall_fit,
       CAST(weekly_market_impressions AS INT64),
       CAST(weekly_market_impressions AS FLOAT64)
FROM base
WHERE brand = 'Happy Lolli'
```

- [ ] **Step 3.2:** Deploy: `bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/views/V_RESEARCH_RECOMMENDATION_CANDIDATES.sql`. Expected: `Created ... V_RESEARCH_RECOMMENDATION_CANDIDATES`.

- [ ] **Step 3.3:** Sanity-check counts (expect non-zero EXACT/PHRASE/BRAND for at least one family):
```bash
bq query --use_legacy_sql=false --format=csv "SELECT rec_type, COUNT(*) n, COUNT(DISTINCT parent_name) fams FROM \`onyga-482313\`.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES GROUP BY rec_type ORDER BY rec_type"
```
Expected: 4 rows (BRAND, BROAD, EXACT, PHRASE), each `n > 0`.

- [ ] **Step 3.4:** Commit:
```bash
git add scripts/bigquery/views/V_RESEARCH_RECOMMENDATION_CANDIDATES.sql
git commit -m "feat(research): recommendation candidates view (not-advertised gate + 4 types)"
```

### Task 4: `SP_REFRESH_RESEARCH_RECOMMENDATIONS`

**Files:**
- Create: `scripts/bigquery/procedures/SP_REFRESH_RESEARCH_RECOMMENDATIONS.sql`

- [ ] **Step 4.1:** Write the procedure:
```sql
-- =============================================
-- SP_REFRESH_RESEARCH_RECOMMENDATIONS
-- Weekly idempotent top-up of FACT_RESEARCH_RECOMMENDATIONS:
--   1. Broad cluster compute (co-occurrence, fit>=90 seeds, >500 cluster sales)
--   2. Phrase coverage_count
--   3. dedup vs history + now-advertised
--   4. insert up to (5 - emitted_this_week) per family × type
--   5. flip NEW -> ADVERTISED when a term now has 7-day clicks
-- Called by SP_ORCHESTRATE_DAILY_REFRESH after SP_REFRESH_RESEARCH_RANKED.
-- SOP: architecture/RESEARCH_PAGE.md
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_RESEARCH_RECOMMENDATIONS`()
BEGIN
  DECLARE wk DATE DEFAULT DATE_TRUNC(CURRENT_DATE(), WEEK(MONDAY));

  -- ── Step A: status maintenance — terms that started getting clicks are now ADVERTISED
  CREATE TEMP TABLE _adv AS
  SELECT DISTINCT p.parent_name, LOWER(a.search_term) AS query_text
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON a.ASIN_BY_CAMPAIGN_NAME = p.asin
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND a.Ads_clicks > 0;

  UPDATE `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS` t
  SET status = 'ADVERTISED'
  FROM _adv
  WHERE t.status = 'NEW'
    AND t.parent_name = _adv.parent_name
    AND LOWER(t.keyword) = _adv.query_text;

  -- ── Step B: Broad clusters (bounded to fit>=90 seeds from the candidate view)
  -- seed ASINs from SQP (104w), related queries sharing those ASINs, kept only if
  -- they are also fit>=90 candidates in the same family; cluster sales summed from
  -- FACT_RESEARCH_TERMS.market_purchases.
  CREATE TEMP TABLE _broad_seeds AS
  SELECT parent_name, query_text
  FROM `onyga-482313.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES`
  WHERE rec_type = 'BROAD';

  CREATE TEMP TABLE _seed_asins AS
  SELECT s.parent_name, s.query_text AS seed, sq.ASIN
  FROM _broad_seeds s
  JOIN `onyga-482313.OI.FACT_SEARCH_QUERY` sq
    ON LOWER(sq.query_text) = LOWER(s.query_text)
   AND sq.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 104 WEEK);

  -- fit>=90 candidate terms per family (the only terms allowed into a cluster)
  CREATE TEMP TABLE _fit90 AS
  SELECT parent_name, LOWER(query_text) AS query_text
  FROM `onyga-482313.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES`
  WHERE rec_type = 'BROAD';

  CREATE TEMP TABLE _broad_cluster AS
  WITH related AS (
    -- related queries that share an ASIN with the seed, and are themselves fit>=90
    SELECT sa.parent_name, sa.seed, LOWER(sq2.query_text) AS related_term
    FROM _seed_asins sa
    JOIN `onyga-482313.OI.FACT_SEARCH_QUERY` sq2
      ON sq2.ASIN = sa.ASIN
     AND sq2.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 104 WEEK)
     AND sq2.query_text != 'OTHER'
    JOIN _fit90 f ON f.parent_name = sa.parent_name AND f.query_text = LOWER(sq2.query_text)
    GROUP BY sa.parent_name, sa.seed, related_term
  ),
  cluster_terms AS (
    -- seed + its qualifying related terms (distinct), one row per (seed, member)
    SELECT parent_name, seed, related_term AS member FROM related
    UNION DISTINCT
    SELECT parent_name, seed, LOWER(seed) FROM related
  )
  SELECT
    ct.parent_name, ct.seed,
    COUNT(DISTINCT ct.member) AS cluster_size,
    CAST(SUM(COALESCE(rt.market_purchases, 0)) AS INT64) AS cluster_sales
  FROM cluster_terms ct
  LEFT JOIN `onyga-482313.OI.FACT_RESEARCH_TERMS` rt
    ON LOWER(rt.query_text) = ct.member
  GROUP BY ct.parent_name, ct.seed;

  -- ── Step C: Phrase coverage_count (other not-advertised terms whose tokens ⊇ seed tokens)
  CREATE TEMP TABLE _phrase_cov AS
  WITH seeds AS (
    SELECT parent_name, query_text,
      (SELECT ARRAY_AGG(w) FROM UNNEST(SPLIT(LOWER(query_text), ' ')) w
       WHERE w NOT IN ('a','an','the','for','and','or','of','to','in','on','at','by','is','it','my','with') AND w != ''
      ) AS toks
    FROM `onyga-482313.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES`
    WHERE rec_type = 'PHRASE'
  ),
  fam_terms AS (
    SELECT DISTINCT parent_name, LOWER(query_text) AS term
    FROM `onyga-482313.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES`
  )
  SELECT s.parent_name, s.query_text,
    (SELECT COUNT(*) FROM fam_terms ft
      WHERE ft.parent_name = s.parent_name
        AND ft.term != LOWER(s.query_text)
        AND (SELECT LOGICAL_AND(ft.term LIKE CONCAT('%', t, '%')) FROM UNNEST(s.toks) t)
    ) AS coverage_count
  FROM seeds s;

  -- ── Step D: assemble candidate pool with sort_metric + dedup vs history & now-advertised
  CREATE TEMP TABLE _pool AS
  SELECT
    c.parent_name, c.rec_type, c.match_type, c.keyword, c.query_text,
    c.rank, c.overall_fit, c.market_volume,
    CASE
      WHEN c.rec_type = 'BROAD' THEN bc.cluster_sales
      ELSE NULL
    END AS market_sales,
    pc.coverage_count,
    CASE WHEN c.rec_type = 'BROAD' THEN bc.cluster_size ELSE NULL END AS cluster_size,
    CASE
      WHEN c.rec_type = 'BROAD' THEN CAST(bc.cluster_sales AS FLOAT64)
      WHEN c.rec_type = 'PHRASE' THEN c.sort_metric + COALESCE(pc.coverage_count, 0) / 1000.0  -- rank, tie-break coverage
      ELSE c.sort_metric
    END AS sort_metric
  FROM `onyga-482313.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES` c
  LEFT JOIN _broad_cluster bc
    ON bc.parent_name = c.parent_name AND LOWER(bc.seed) = LOWER(c.query_text)
  LEFT JOIN _phrase_cov pc
    ON pc.parent_name = c.parent_name AND pc.query_text = c.query_text
  LEFT JOIN _adv
    ON _adv.parent_name = c.parent_name AND _adv.query_text = LOWER(c.keyword)
  WHERE _adv.query_text IS NULL                                   -- not advertised now
    AND (c.rec_type != 'BROAD' OR bc.cluster_sales > 500)          -- Broad cluster threshold
    AND NOT EXISTS (                                               -- never re-recommend
      SELECT 1 FROM `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS` h
      WHERE h.parent_name = c.parent_name AND h.rec_type = c.rec_type
        AND LOWER(h.keyword) = LOWER(c.keyword)
        AND h.status IN ('NEW','ADVERTISED')
    );

  -- ── Step E: per family × type, insert up to (5 - already NEW this week), top by sort_metric
  INSERT INTO `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS`
    (rec_id, week_start, parent_name, rec_type, match_type, keyword, query_text,
     rank, overall_fit, market_sales, market_volume, coverage_count, cluster_size, status, created_at)
  SELECT
    TO_HEX(MD5(CONCAT(parent_name, '|', rec_type, '|', keyword))) AS rec_id,
    wk, parent_name, rec_type, match_type, keyword, query_text,
    rank, overall_fit, market_sales, market_volume, coverage_count, cluster_size,
    'NEW', CURRENT_TIMESTAMP()
  FROM (
    SELECT p.*,
      ROW_NUMBER() OVER (PARTITION BY p.parent_name, p.rec_type ORDER BY p.sort_metric DESC, p.keyword) AS rn,
      (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS` e
        WHERE e.parent_name = p.parent_name AND e.rec_type = p.rec_type
          AND e.week_start = wk AND e.status = 'NEW') AS n_existing
    FROM _pool p
  )
  WHERE rn <= (5 - n_existing);
END;
```

- [ ] **Step 4.2:** Deploy + run:
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/procedures/SP_REFRESH_RESEARCH_RECOMMENDATIONS.sql
bq query --use_legacy_sql=false "CALL \`onyga-482313.OI\`.SP_REFRESH_RESEARCH_RECOMMENDATIONS()"
```
Expected: both succeed (no CPU-limit error — temp tables break the statement up).

- [ ] **Step 4.3:** Verify the cap and shape:
```bash
bq query --use_legacy_sql=false --format=csv "SELECT rec_type, COUNT(*) n, COUNT(DISTINCT parent_name) fams, MAX(per) max_per_fam FROM (SELECT rec_type, parent_name, COUNT(*) per FROM \`onyga-482313\`.OI.FACT_RESEARCH_RECOMMENDATIONS WHERE status='NEW' GROUP BY rec_type, parent_name) GROUP BY rec_type"
```
Expected: `max_per_fam <= 5` for every rec_type.

- [ ] **Step 4.4:** Add the orchestrator hook. In `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql`, find the `SP_REFRESH_RESEARCH_RANKED` block (Task 20.6) and insert an identically-structured block (copy the `SET procedure_name=...` + `BEGIN ... EXCEPTION WHEN ERROR ...` template) for `SP_REFRESH_RESEARCH_RECOMMENDATIONS` immediately after it, as "Refresh Task 20.7". Deploy the orchestrator:
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql
```

- [ ] **Step 4.5:** Commit:
```bash
git add scripts/bigquery/procedures/SP_REFRESH_RESEARCH_RECOMMENDATIONS.sql scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql
git commit -m "feat(research): SP_REFRESH_RESEARCH_RECOMMENDATIONS (weekly top-up, broad clusters, dedup) + orchestrator hook"
```

### Task 5: Validation tool

**Files:**
- Create: `tools/validate_research_recommendations.py`

- [ ] **Step 5.1:** Write the validator (mirrors `tools/validate_research_ranked.py` structure):
```python
#!/usr/bin/env python3
"""Validate FACT_RESEARCH_RECOMMENDATIONS invariants. Exit non-zero on violation.
SOP: architecture/RESEARCH_PAGE.md"""
import sys
from google.cloud import bigquery

T = "`onyga-482313`.OI.FACT_RESEARCH_RECOMMENDATIONS"
CHECKS = [
    ("rec_type enum", f"SELECT COUNT(*) FROM {T} WHERE rec_type NOT IN ('EXACT','PHRASE','BROAD','BRAND')"),
    ("match_type enum", f"SELECT COUNT(*) FROM {T} WHERE match_type NOT IN ('EXACT','PHRASE','BROAD')"),
    ("status enum", f"SELECT COUNT(*) FROM {T} WHERE status NOT IN ('NEW','ADVERTISED','DISMISSED')"),
    ("<=5 NEW per family/type/week", f"""
        SELECT COUNT(*) FROM (
          SELECT parent_name, rec_type, week_start, COUNT(*) n
          FROM {T} WHERE status='NEW' GROUP BY 1,2,3 HAVING n > 5)"""),
    ("non-brand types exclude own brand", f"""
        SELECT COUNT(*) FROM {T}
        WHERE rec_type IN ('EXACT','PHRASE','BROAD') AND LOWER(keyword) LIKE '%happy lolli%'"""),
    ("brand type is PHRASE match", f"SELECT COUNT(*) FROM {T} WHERE rec_type='BRAND' AND match_type != 'PHRASE'"),
    ("broad rows have cluster sales > 500", f"""
        SELECT COUNT(*) FROM {T} WHERE rec_type='BROAD' AND COALESCE(market_sales,0) <= 500"""),
    ("phrase rows are >= 3 words", f"""
        SELECT COUNT(*) FROM {T}
        WHERE rec_type='PHRASE' AND ARRAY_LENGTH(SPLIT(TRIM(keyword),' ')) < 3"""),
]

def main():
    client = bigquery.Client(project='onyga-482313')
    fails = 0
    for name, sql in CHECKS:
        n = list(client.query(sql).result())[0][0]
        print(f"  {name}: {'OK' if n == 0 else f'FAIL ({n})'}")
        fails += 1 if n else 0
    sys.exit(1 if fails else 0)

if __name__ == '__main__':
    main()
```

- [ ] **Step 5.2:** Run: `/usr/bin/python3 tools/validate_research_recommendations.py 2>/dev/null`. Expected: all `OK`, exit 0. (If `broad rows have cluster sales > 500` fails because there are zero broad rows, that's still OK — the check counts violations, 0 rows = 0 violations.)

- [ ] **Step 5.3:** Commit:
```bash
git add tools/validate_research_recommendations.py
git commit -m "test(research): validate_research_recommendations.py invariants"
```

### Task 6: Flask endpoint

**Files:**
- Modify: `data-entry-app/app.py` (add after `research_term_ranks`)

- [ ] **Step 6.1:** Add the endpoint:
```python
@app.route('/api/research/recommendations', methods=['GET'])
def research_recommendations():
    """Current recommendations for a family, grouped by rec_type.

    Query: ?parent=<family>
    Returns: { "EXACT": [...], "PHRASE": [...], "BROAD": [...], "BRAND": [...] }
    Each row: {keyword, match_type, rank, overall_fit, market_sales, market_volume,
               coverage_count, cluster_size, status, week_start}
    """
    parent = (request.args.get('parent') or '').strip()
    if not parent:
        return jsonify({'error': 'parent is required'}), 400
    try:
        sql = """
        SELECT rec_type, match_type, keyword, rank, overall_fit, market_sales,
               market_volume, coverage_count, cluster_size, status,
               CAST(week_start AS STRING) AS week_start
        FROM `onyga-482313`.OI.FACT_RESEARCH_RECOMMENDATIONS
        WHERE parent_name = @parent AND status IN ('NEW','ADVERTISED')
        ORDER BY rec_type, status, market_sales DESC NULLS LAST, rank DESC NULLS LAST
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('parent', 'STRING', parent)
        ])
        out = {'EXACT': [], 'PHRASE': [], 'BROAD': [], 'BRAND': []}
        for row in client.query(sql, job_config=jc).result():
            d = dict(row)
            out.setdefault(d['rec_type'], []).append(d)
        return jsonify(out)
    except Exception as e:
        print(f"Error in research_recommendations: {e}")
        return jsonify({'error': str(e)}), 500
```

- [ ] **Step 6.2:** Verify it compiles: `python3 -W error::SyntaxWarning -m py_compile data-entry-app/app.py`. Expected: clean.

- [ ] **Step 6.3:** Live-test against BQ with a real family (proves the SQL shape; Flask isn't running):
```bash
bq query --use_legacy_sql=false --format=csv "SELECT rec_type, COUNT(*) FROM \`onyga-482313\`.OI.FACT_RESEARCH_RECOMMENDATIONS WHERE parent_name='LolliME' AND status IN ('NEW','ADVERTISED') GROUP BY rec_type"
```
Expected: returns rows (or empty if LolliME has none — try another family from the Task 4.3 output).

- [ ] **Step 6.4:** Commit:
```bash
git add data-entry-app/app.py
git commit -m "feat(research): GET /api/research/recommendations endpoint"
```

### Task 7: Frontend types + mapper

**Files:**
- Modify: `dashboard-react/src/pages/research/types.ts`
- Create: `dashboard-react/src/pages/research/mapRecommendation.ts`
- Create: `dashboard-react/src/pages/research/mapRecommendation.test.ts`

- [ ] **Step 7.1:** Append to `types.ts`:
```ts
export interface RecommendationRow {
  rec_type: 'EXACT' | 'PHRASE' | 'BROAD' | 'BRAND';
  match_type: 'EXACT' | 'PHRASE' | 'BROAD';
  keyword: string;
  rank: number | null;
  overall_fit: number | null;
  market_sales: number | null;
  market_volume: number | null;
  coverage_count: number | null;
  cluster_size: number | null;
  status: 'NEW' | 'ADVERTISED' | 'DISMISSED';
  week_start: string | null;
}

export type RecommendationsByType = Record<'EXACT' | 'PHRASE' | 'BROAD' | 'BRAND', RecommendationRow[]>;
```

- [ ] **Step 7.2:** Create `mapRecommendation.ts`:
```ts
import type { RecommendationRow, RecommendationsByType } from './types';

const num = (v: unknown): number | null => (v == null ? null : Number(v));

export function mapRecommendation(t: Record<string, unknown>): RecommendationRow {
  return {
    rec_type: (t.rec_type as RecommendationRow['rec_type']) ?? 'EXACT',
    match_type: (t.match_type as RecommendationRow['match_type']) ?? 'EXACT',
    keyword: String(t.keyword ?? ''),
    rank: num(t.rank),
    overall_fit: num(t.overall_fit),
    market_sales: num(t.market_sales),
    market_volume: num(t.market_volume),
    coverage_count: num(t.coverage_count),
    cluster_size: num(t.cluster_size),
    status: (t.status as RecommendationRow['status']) ?? 'NEW',
    week_start: (t.week_start as string) ?? null,
  };
}

/** Normalize the grouped API payload into a fully-populated 4-key map. */
export function mapRecommendationsByType(payload: Record<string, unknown[]>): RecommendationsByType {
  const out: RecommendationsByType = { EXACT: [], PHRASE: [], BROAD: [], BRAND: [] };
  (['EXACT', 'PHRASE', 'BROAD', 'BRAND'] as const).forEach(k => {
    out[k] = (payload[k] || []).map(r => mapRecommendation(r as Record<string, unknown>));
  });
  return out;
}
```

- [ ] **Step 7.3:** Create `mapRecommendation.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { mapRecommendation, mapRecommendationsByType } from './mapRecommendation';

describe('mapRecommendation', () => {
  it('coerces numerics and defaults', () => {
    const r = mapRecommendation({ rec_type: 'BROAD', match_type: 'BROAD', keyword: 'gift cards', market_sales: '740', rank: 58 });
    expect(r.rec_type).toBe('BROAD');
    expect(r.market_sales).toBe(740);
    expect(r.rank).toBe(58);
    expect(r.coverage_count).toBeNull();
    expect(r.status).toBe('NEW');
  });

  it('mapRecommendationsByType always returns all 4 keys', () => {
    const m = mapRecommendationsByType({ EXACT: [{ keyword: 'a' }] });
    expect(Object.keys(m).sort()).toEqual(['BRAND', 'BROAD', 'EXACT', 'PHRASE']);
    expect(m.EXACT).toHaveLength(1);
    expect(m.PHRASE).toEqual([]);
  });
});
```

- [ ] **Step 7.4:** Run: `cd dashboard-react && npx vitest run src/pages/research/mapRecommendation.test.ts`. Expected: 2 pass. Commit:
```bash
git add dashboard-react/src/pages/research/types.ts dashboard-react/src/pages/research/mapRecommendation.ts dashboard-react/src/pages/research/mapRecommendation.test.ts
git commit -m "feat(research-ui): recommendation types + mapper with tests"
```

### Task 8: `RecommendationsCard` component

**Files:**
- Create: `dashboard-react/src/pages/research/RecommendationsCard.tsx`

- [ ] **Step 8.1:** Create the component (read-only, 4 mini-sections, ≤5 chips each, follows the card styling already used in `FamilyInfoCard`/`ConversionCurveCard`):
```tsx
import { fShort } from '../../utils';
import type { RecommendationsByType, RecommendationRow } from './types';

interface RecommendationsCardProps {
  recs: RecommendationsByType | null;
  selectedProduct: string;
}

const TYPE_META: Record<keyof RecommendationsByType, { label: string; badge: string; hint: string }> = {
  EXACT:  { label: '🎯 Exact',  badge: 'bg-blue-500/15 text-blue-400',     hint: 'Not advertised · rank ≥ 75' },
  PHRASE: { label: '🔤 Phrase', badge: 'bg-purple-500/15 text-purple-400', hint: '≥3-word terms · rank ≥ 75 · phrase match' },
  BROAD:  { label: '🌐 Broad',  badge: 'bg-amber-500/15 text-amber-400',   hint: 'fit ≥ 90 cluster · >500 market sales' },
  BRAND:  { label: '🛡️ Brand',  badge: 'bg-cyan-500/15 text-cyan-400',      hint: 'Own-brand defense · phrase match' },
};

function metricFor(row: RecommendationRow): string {
  switch (row.rec_type) {
    case 'BROAD':  return `${fShort(row.market_sales ?? 0)} cluster sales` + (row.cluster_size ? ` · ${row.cluster_size} terms` : '');
    case 'PHRASE': return `rank ${row.rank ?? '—'}` + (row.coverage_count ? ` · covers ${row.coverage_count}` : '');
    case 'BRAND':  return `${fShort(row.market_volume ?? 0)} vol`;
    default:       return `rank ${row.rank ?? '—'}`;
  }
}

export function RecommendationsCard({ recs, selectedProduct }: RecommendationsCardProps) {
  if (!recs) return null;
  const order: (keyof RecommendationsByType)[] = ['EXACT', 'PHRASE', 'BROAD', 'BRAND'];
  const total = order.reduce((s, k) => s + recs[k].length, 0);
  if (total === 0) return null;

  return (
    <div className="mb-4 border border-border/30 rounded-lg overflow-hidden bg-white/[0.01]">
      <div className="px-4 py-2.5 bg-white/[0.02] border-b border-border/20 flex items-center gap-2">
        <span className="text-sm font-bold text-heading">💡 Keyword Recommendations</span>
        <span className="text-[10px] text-muted">{selectedProduct} · {total} new this week · shared with Coach</span>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-px bg-border/20">
        {order.map(type => {
          const rows = recs[type];
          const meta = TYPE_META[type];
          return (
            <div key={type} className="bg-surface px-4 py-3">
              <div className="flex items-center gap-2 mb-2">
                <span className={`px-1.5 py-0.5 rounded text-[9px] font-bold ${meta.badge}`}>{meta.label}</span>
                <span className="text-[9px] text-muted">{meta.hint}</span>
                <span className="ml-auto text-[9px] text-faint tabular-nums">{rows.length}</span>
              </div>
              {rows.length === 0 ? (
                <div className="text-[10px] text-faint italic">No new recommendations</div>
              ) : (
                <div className="flex flex-col gap-1">
                  {rows.map(r => (
                    <div key={r.keyword} className={`flex items-center gap-2 text-[10px] ${r.status === 'ADVERTISED' ? 'opacity-50' : ''}`}>
                      <span className="text-heading font-medium truncate max-w-[200px]" title={r.keyword}>{r.keyword}</span>
                      <span className="ml-auto text-[9px] text-muted tabular-nums whitespace-nowrap">{metricFor(r)}</span>
                      {r.status === 'ADVERTISED' && <span className="text-[8px] text-emerald-400" title="Now being advertised">✓ live</span>}
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
```

- [ ] **Step 8.2:** Verify: `cd dashboard-react && npx tsc --noEmit`. Expected: clean. Commit:
```bash
git add dashboard-react/src/pages/research/RecommendationsCard.tsx
git commit -m "feat(research-ui): RecommendationsCard (read-only, 4 types)"
```

### Task 9: Wire into ResearchPage

**Files:**
- Modify: `dashboard-react/src/pages/ResearchPage.tsx`

- [ ] **Step 9.1:** Add the import (near the other research imports, ~line 15):
```ts
import { RecommendationsCard } from './research/RecommendationsCard';
import { mapRecommendationsByType } from './research/mapRecommendation';
import type { RecommendationsByType } from './research/types';
```
(merge the `type` import into the existing `./research/types` type-import line instead of adding a duplicate if cleaner.)

- [ ] **Step 9.2:** Add state next to `familyInfo` (~line 45):
```ts
  const [recommendations, setRecommendations] = useState<RecommendationsByType | null>(null);
```

- [ ] **Step 9.3:** Fetch recommendations inside the existing `fetchFamily` callback so they load/refresh with the family. Change the `Promise.all` in `fetchFamily` to also fetch recommendations, and set state:
```ts
  const fetchFamily = useCallback(async (signal?: AbortSignal) => {
    const [fi, sr, rc] = await Promise.all([
      apiFetch(`/api/research/family-info?family=${encodeURIComponent(selectedProduct)}`, { signal }).then(r => r.ok ? r.json() : null).catch(() => null),
      apiFetch(`/api/research/segment-reasoning?family=${encodeURIComponent(selectedProduct)}`, { signal }).then(r => r.ok ? r.json() : null).catch(() => null),
      apiFetch(`/api/research/recommendations?parent=${encodeURIComponent(selectedProduct)}`, { signal }).then(r => r.ok ? r.json() : null).catch(() => null),
    ]);
    if (!signal?.aborted) {
      setFamilyInfo(fi);
      setSegmentReasoning(sr);
      setRecommendations(rc ? mapRecommendationsByType(rc) : null);
    }
  }, [selectedProduct]);
```
Also clear it when no product: in the effect that does `setFamilyInfo(null); setSegmentReasoning(null);` for the `!selectedProduct` case, add `setRecommendations(null);`.

- [ ] **Step 9.4:** Render the card right after `FamilyInfoCard` (the block that renders `{familyInfo && selectedProduct && (<FamilyInfoCard .../>)}` ~line 392). Add immediately below it:
```tsx
        {selectedProduct && (
          <RecommendationsCard recs={recommendations} selectedProduct={selectedProduct} />
        )}
```

- [ ] **Step 9.5:** Verify: `cd dashboard-react && npx tsc --noEmit && npm test 2>&1 | grep -E "Test Files|Tests " && npm run build 2>&1 | tail -1`. Expected: tsc clean, all tests pass, build succeeds.

- [ ] **Step 9.6:** Commit:
```bash
git add dashboard-react/src/pages/ResearchPage.tsx
git commit -m "feat(research-ui): wire RecommendationsCard into ResearchPage"
```

### Task 10: Register + final verification + deploy

**Files:**
- Modify: `config.yaml`

- [ ] **Step 10.1:** Register in `config.yaml`: `V_RESEARCH_RECOMMENDATION_CANDIDATES` (views), `FACT_RESEARCH_RECOMMENDATIONS` (tables, type fact, populated_by SP_REFRESH_RESEARCH_RECOMMENDATIONS), `SP_REFRESH_RESEARCH_RECOMMENDATIONS` (procedures). Follow the exact entry format of neighbouring entries.

- [ ] **Step 10.2:** Full verification:
```bash
/usr/bin/python3 tools/validate_research_recommendations.py 2>/dev/null            # exit 0
/usr/bin/python3 tools/validate_research_ranked.py 2>/dev/null                     # exit 0 (unbroken)
python3 -m py_compile data-entry-app/app.py
cd dashboard-react && npx tsc --noEmit && npm test 2>&1 | grep -E "Tests " && npm run build 2>&1 | tail -1
```

- [ ] **Step 10.3:** Commit config:
```bash
git add config.yaml
git commit -m "chore(config): register research recommendation objects"
```

- [ ] **Step 10.4:** Browser-verify locally (Vite + local Flask running): navigate to Research, pick a family with recommendations (from Task 4.3 output), confirm the 💡 Keyword Recommendations card renders with chips under the right type sections. Screenshot.

- [ ] **Step 10.5:** Deploy: `./deployment/deploy_all.sh flask` then `./deployment/deploy_all.sh dashboard`. Verify prod `GET /api/research/recommendations?parent=<family>` returns grouped rows (mint a token as in prior sessions). The BQ objects are already live; the SP runs nightly in the orchestrator.

---

## Self-review notes

- **Spec coverage:** not-advertised gate → Task 3 `advertised_7d`; 4 types → Task 3 UNION; Broad cluster + >500 → Task 4 Step B/D; Phrase coverage → Task 4 Step C; 5/type/family/week + dedup + status → Task 4 Step D/E + Step A; coacher-reads-table → Task 2 table + Task 6 endpoint (no FACT_ADS_COACH_ACTIONS injection); UI card → Tasks 8-9; validator → Task 5; SOP → Task 1; registration → Task 10. ✓
- **Type consistency:** `RecommendationRow` fields (Task 7) match the endpoint SELECT (Task 6) and the FACT DDL columns (Task 2): rec_type, match_type, keyword, rank, overall_fit, market_sales, market_volume, coverage_count, cluster_size, status, week_start. ✓
- **Cost risk:** Broad co-occurrence is in the SP via temp tables, bounded to fit≥90 seeds — mirrors the mitigation that fixed the earlier CPU-limit failure. If Step 4.2 still hits the CPU guard, split `_broad_cluster` into two temp tables (related first, then aggregate) — note left for the implementer.
- **Idempotency:** daily re-runs are safe — Step A (status) is monotone, Step D excludes history (NEW/ADVERTISED) + now-advertised, Step E caps at 5−n_existing per week. No history deletes.
