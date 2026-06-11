# Research Page Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the SQL layer the single owner of all Research-page scoring/segmentation logic, fix the five live bugs (orphaned segment overrides, Girl/Boy enum drift, dead Related toggle, lying all-families tooltip, LIMIT docstring), materialize the ranking view, collapse duplicated endpoint SQL, and split the 2,236-line React component.

**Architecture:** One UDF (`FN_EXTRACT_SEGMENTS`) owns the segment regex taxonomy and is consumed by every SQL site. `V_RESEARCH_RANKED` (parent × term) and a new `V_RESEARCH_TERMS` (term grain) own all scoring + aggregation and emit *explanation columns* so the frontend only formats. Both are materialized nightly into `FACT_RESEARCH_TERMS` / `FACT_RESEARCH_RANKED` by `SP_REFRESH_RESEARCH_RANKED` (same pattern as `SP_REFRESH_ADS_COACH_ACTIONS`). Flask endpoints become thin parameterized SELECTs. The React page deletes its parallel scoring implementation and is split into focused components under `pages/research/`.

**Tech Stack:** BigQuery Standard SQL (bq CLI deploy), Flask + google-cloud-bigquery, React 19 + TypeScript + Vitest.

**Known live-bug inventory this plan must fix:**
1. Segment edits write to `DE_SEARCH_TERM_SEGMENTS` but nothing reads it → wire into `V_SQP_QUERY_WEEKLY` + `V_RESEARCH_RANKED`.
2. `'Girl'/'Boy'` + `'0-4 (Toddler)'` enum drift in `V_RESEARCH_RANKED` ads-only branch → UDF.
3. "Related" toggle never unlocks when `DE_SYNONYM_CACHE` misses, even though backend has hardcoded groups → return hardcoded fallbacks from `/get-synonyms`.
4. `getAllFamiliesTooltip` shows the selected family's CPS for every family → replace with batch `/term-ranks` endpoint reading per-family SQL scores.
5. `/top-terms` docstring claims "top 30", no LIMIT → fix docstring (keep returning all; client paginates).

**Deployment constraints:**
- BQ objects deployed with `bq query --use_legacy_sql=false --project_id=onyga-482313 < file.sql` (pattern from `deployment/deploy_all.sh`). Deploy order: FN → V_SQP_QUERY_WEEKLY → V_RESEARCH_RANKED → V_RESEARCH_TERMS → SP → run SP.
- All BQ changes are backward-compatible (new columns / same names), so prod Flask keeps working until redeployed.
- Do NOT deploy Cloud Run (Flask/dashboard) — leave that to Ori; note it in the final summary.
- Git tree has pre-existing uncommitted changes (`config.yaml`, `cube/schema/*`). Never `git add` those hunks blindly: commit only files this plan touches; for `config.yaml`, inspect `git diff config.yaml` first and commit it in its own commit with a message noting any pre-existing hunks, or leave it staged-out if entangled.

---

### Task 0: Preflight verifications

**Files:** none (read-only)

- [ ] **Step 0.1:** Read `data-entry-app/app.py` lines 1-120 to find the `cache_result` decorator. Determine whether its cache key includes function args. If args are in the key → safe to decorate parameterized endpoints; if not → only decorate `/conversion-curve` and `/products` (no params... `/products` has none, `/conversion-curve` none).
- [ ] **Step 0.2:** `bq query --use_legacy_sql=false "SELECT DISTINCT product_type FROM \`onyga-482313\`.OI.DE_PRODUCT_TYPE_KEYWORDS ORDER BY 1"` — record the canonical product_type vocabulary. Compare with `SP_DERIVE_PRODUCT_SEGMENTS` regex vocab ('Food','Toys','Clothing',…). They are expected to differ — Task 5 unifies on the DE keyword vocabulary.
- [ ] **Step 0.3:** Read `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql` around one CALL block (e.g. lines 590-640) to copy its logging/error-handling block format for Task 4.
- [ ] **Step 0.4:** `git diff config.yaml | head -50` — note pre-existing hunks so the final config commit can be separated.
- [ ] **Step 0.5:** Confirm dead code before deletion:
  - `grep -n "reasoning_weights\|reasoning_gender" scripts/bigquery/views/V_RESEARCH_RANKED.sql` — confirm `reasoning_weights` is never referenced after its definition (CTEs `family_ads_tagged`, `reasoning_*`, `reasoning_weights` are dead).
  - `grep -n "getAdsPerfScore\|ratioBadge\|brand_hero" dashboard-react/src/pages/ResearchPage.tsx` — confirm `getAdsPerfScore` and `ratioBadge` are defined but never called in JSX, and `brand_hero_*` is mapped but never rendered.

### Task 1: SOP first — `architecture/RESEARCH_PAGE.md`

**Files:**
- Create: `architecture/RESEARCH_PAGE.md`

- [ ] **Step 1.1:** Write the SOP documenting the target architecture (this is required by the project constitution *before* code changes). Contents: data flow diagram (FACT_SEARCH_QUERY/FACT_AMAZON_ADS → V_SQP_QUERY_WEEKLY → V_RESEARCH_TERMS/V_RESEARCH_RANKED → SP_REFRESH_RESEARCH_RANKED → FACT_RESEARCH_TERMS/FACT_RESEARCH_RANKED → Flask `/api/research/*` → ResearchPage), the single-source-of-truth rules (segment taxonomy ONLY in FN_EXTRACT_SEGMENTS; product_type vocab ONLY in DE_PRODUCT_TYPE_KEYWORDS; scoring ONLY in V_RESEARCH_RANKED; frontend formats, never computes), the manual-override flow (DE_SEARCH_TERM_SEGMENTS → COALESCE in V_SQP_QUERY_WEEKLY), score semantics tables (seg fit pts 30/30/10/30, mismatch cap 10, age adjacency 80%; CPS brackets ≤5→100, ≤8→85, ≤12→70, ≤20→55, ≤35→35, ≤50→20, else 10; purchase rank buckets ≥1000→100…<5→10; rank = avg(fit, purchase_rank), off-season holiday → 0), holiday windows, refresh cadence, and the endpoint contract list.
- [ ] **Step 1.2:** Commit: `git add architecture/RESEARCH_PAGE.md && git commit -m "docs(research): SOP for consolidated Research page architecture"`

### Task 2: `FN_EXTRACT_SEGMENTS` + adopt in `V_SQP_QUERY_WEEKLY` + wire overrides

**Files:**
- Create: `scripts/bigquery/functions/FN_EXTRACT_SEGMENTS.sql`
- Modify: `scripts/bigquery/views/V_SQP_QUERY_WEEKLY.sql`

- [ ] **Step 2.1:** Create the UDF. The regex bodies are copied **verbatim** from `V_SQP_QUERY_WEEKLY.sql` lines 52-101 (canonical set — includes the `8-14` girl default and the richer tween/teen/adult patterns):

```sql
-- FN_EXTRACT_SEGMENTS — single source of truth for search-term segment extraction.
-- Consumed by: V_SQP_QUERY_WEEKLY, V_RESEARCH_RANKED, SP_DERIVE_PRODUCT_SEGMENTS,
--              /api/research/segment-reasoning.
-- product_type and brand are NOT here: product_type comes from DE_PRODUCT_TYPE_KEYWORDS
-- lookup, brand needs DIM_PRODUCT (table refs don't belong in a scalar UDF).
CREATE OR REPLACE FUNCTION `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(query_text STRING)
RETURNS STRUCT<gender STRING, age_group STRING, occasion STRING, holiday STRING>
AS (STRUCT(
  CASE
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(girl|girls|daughter|her|women|woman|granddaughter|niece|sister|female)\b') THEN 'Female'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(boy|boys|son|him|men|man|grandson|nephew|brother|male)\b') THEN 'Male'
    ELSE NULL
  END,
  CASE
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(baby|infant|newborn)\b') THEN '0-2 (Baby)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(toddler)\b') THEN '2-4 (Toddler)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(\b1[0-2]\s*(?:year|yr|yo|th|old|\+)|1[0-2]-1[0-4]|\b[89]-1[0-2]\b|\b10-1[0-3]\b|\b8-12\b|\b9-12\b|\b10-12\b|\b10-13\b|\btween\b|\btweens\b|\bpreteen\b|\bages?\s*1[0-2]\b|gift.{0,15}\b1[0-2]\b|\b1[0-2]\b.{0,5}girl|\b1[0-2]\b.{0,5}boy)') THEN '10-12 (Tween)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(\b1[3-7]\s*(?:year|yr|yo|th|old|\+)|1[3-7]-1[4-9]|\bteen\b|\bteens\b|\bteenage\b|\bteenager\b|\bteenagers\b|\bages?\s*1[3-7]\b|\bsweet 16\b|\bsweet sixteen\b|\bquinceanera\b)') THEN '13-17 (Teen)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(\b18\s*(?:year|yr|th|old|\+)|\badult\b|\bwomen\b|\bwoman\b|\bmen\b|\bman\b|\bcollege\b|\bfor her\b|\bfor him\b|\bmom\b|\bdad\b|\bwife\b|\bhusband\b|\bgirlfriend\b|\bboyfriend\b|\bmadre\b|\bmama\b|\bpapa\b)') THEN '18+ (Adult)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(\b[3-9]\s*(?:year|yr|yo|th|old|\+)|\b[3-9]-[5-9]\b|\b[5-9]-1[0-2]\b|\bages?\s*[3-9]\b|\bkid\b|\bkids\b|\bchild\b|\bchildren\b)') THEN '5-9 (Kid)'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\bgirls?\b') THEN '8-14'
    ELSE NULL
  END,
  CASE
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(birthday|bday)') THEN 'Birthday'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(graduat)') THEN 'Graduation'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(back to school|first day of school)') THEN 'Back to School'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(recital|cheerleader|competition|dance )') THEN 'Performance'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(get well|hospital|surgery)') THEN 'Get Well'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(encouragement|cheer up|comfort|thinking of you)') THEN 'Encouragement'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(wedding|bride|bridal)') THEN 'Wedding'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(sleepover|slumber party|pajama party|pj party)') THEN 'Sleepover'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(\bcamp\b|sleep away camp|summer camp)') THEN 'Camp'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(sweet 16|sweet sixteen)') THEN 'Sweet 16'
    ELSE NULL
  END,
  CASE
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(christmas|xmas|stocking stuffer|advent|\bholiday\b|hanukkah|chanukah)') THEN 'Christmas'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(easter)') THEN 'Easter'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(valentine)') THEN 'Valentines'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(halloween|trick or treat)') THEN 'Halloween'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(new year|nye\b)') THEN 'New Years'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(mother.?s?.?day|mothers day|for mom|for mama)') THEN 'Mothers Day'
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'(father.s day|for dad|for papa)') THEN 'Fathers Day'
    ELSE NULL
  END
));
```

- [ ] **Step 2.2:** Deploy: `bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/functions/FN_EXTRACT_SEGMENTS.sql`
- [ ] **Step 2.3:** Smoke test (expected: Female / 10-12 (Tween) / Birthday / NULL):
  `bq query --use_legacy_sql=false "SELECT \`onyga-482313\`.OI.FN_EXTRACT_SEGMENTS('birthday gift for 11 year old girl').*"`
- [ ] **Step 2.4:** Rewrite `V_SQP_QUERY_WEEKLY.sql`: in `base`, replace the four regex CASE blocks (gender/age_group/occasion/holiday, lines 51-101) with `` `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(query_text) AS seg ``. Keep cost_tier and brand CASEs as-is. Final SELECT becomes:

```sql
SELECT
  b.* EXCEPT(seg, cost_tier, brand),
  COALESCE(o.gender,       b.seg.gender)    AS gender,
  COALESCE(o.age_group,    b.seg.age_group) AS age_group,
  COALESCE(o.occasion,     b.seg.occasion)  AS occasion,
  b.seg.holiday                             AS holiday,
  COALESCE(o.cost_tier,    b.cost_tier)     AS cost_tier,
  COALESCE(o.brand,        b.brand)         AS brand,
  COALESCE(o.product_type, ptl.product_type) AS product_type
FROM base b
LEFT JOIN product_type_lookup ptl ON b.query_text = ptl.query_text
LEFT JOIN (
  -- Manual overrides from the Research page editor (latest row per term wins)
  SELECT query_text, gender, age_group, occasion, cost_tier, product_type, brand
  FROM `onyga-482313`.OI.DE_SEARCH_TERM_SEGMENTS
  QUALIFY ROW_NUMBER() OVER (PARTITION BY LOWER(query_text) ORDER BY updated_at DESC) = 1
) o ON LOWER(o.query_text) = LOWER(b.query_text)
```

  (`holiday` has no override column in DE_SEARCH_TERM_SEGMENTS — derived only.) Update the view header comment to mention FN_EXTRACT_SEGMENTS + overrides.
- [ ] **Step 2.5:** Deploy the view; verify columns and overrides:
  - `bq query --use_legacy_sql=false "SELECT gender, age_group, occasion, holiday, cost_tier, brand, product_type FROM \`onyga-482313\`.OI.V_SQP_QUERY_WEEKLY LIMIT 5"`
  - `bq query --use_legacy_sql=false "SELECT s.query_text, s.gender FROM \`onyga-482313\`.OI.V_SQP_QUERY_WEEKLY s JOIN \`onyga-482313\`.OI.DE_SEARCH_TERM_SEGMENTS o ON LOWER(o.query_text)=LOWER(s.query_text) AND o.gender IS NOT NULL LIMIT 5"` — gender must equal the override.
- [ ] **Step 2.6:** Commit both SQL files: `feat(research): FN_EXTRACT_SEGMENTS single-source taxonomy + manual overrides wired into V_SQP_QUERY_WEEKLY`

### Task 3: Rewrite `V_RESEARCH_RANKED`

**Files:**
- Modify: `scripts/bigquery/views/V_RESEARCH_RANKED.sql`

Changes (keeping the score semantics byte-identical where not buggy):
1. **Delete dead CTEs** `family_ads_tagged`, `reasoning_gender/age/occasion/product_type`, `reasoning_weights` (lines 67-174 — confirmed unreferenced in Step 0.5).
2. **Fix ads-only enum drift:** `search_terms` UNION branch derives gender/age/occasion/holiday via `FN_EXTRACT_SEGMENTS`, product_type via `DE_PRODUCT_TYPE_KEYWORDS` lookup (same pattern as V_SQP_QUERY_WEEKLY), and applies `DE_SEARCH_TERM_SEGMENTS` overrides.
3. **Add family SQP metrics** (moves the per-request subquery out of `/related-terms`).
4. **Compute `effective_cps` once** in a CTE; bracket once (deletes the 6× repeated COALESCE/CASE monster).
5. **Emit explanation columns:** `gender_score, age_score, occasion_score, pt_score` (from `seg_fit_calc`), `cps_source` (`'ads_30d' | 'ads_12m' | 'curve' | NULL`).

- [ ] **Step 3.1:** Apply the rewrite. New/changed sections in full:

```sql
-- (in WITH list, replacing search_terms_ads + search_terms)
search_terms_ads AS (
  SELECT DISTINCT LOWER(a.search_term) AS query_text
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
  WHERE a.Ads_clicks > 0
    AND LOWER(a.search_term) NOT IN (SELECT LOWER(query_text) FROM search_terms_sqp)
),

ads_term_overrides AS (
  SELECT query_text, gender, age_group, occasion, cost_tier, product_type, brand
  FROM `onyga-482313`.OI.DE_SEARCH_TERM_SEGMENTS
  QUALIFY ROW_NUMBER() OVER (PARTITION BY LOWER(query_text) ORDER BY updated_at DESC) = 1
),

ads_term_product_type AS (
  SELECT
    ats.query_text,
    ARRAY_AGG(ptk.product_type ORDER BY ptk.priority ASC, LENGTH(ptk.keyword) DESC LIMIT 1)[OFFSET(0)] AS product_type
  FROM search_terms_ads ats
  CROSS JOIN `onyga-482313.OI.DE_PRODUCT_TYPE_KEYWORDS` ptk
  WHERE REGEXP_CONTAINS(LOWER(ats.query_text), CONCAT(r'(?:^|\W)', ptk.keyword, r'(?:\W|$)'))
  GROUP BY ats.query_text
),

search_terms AS (
  SELECT * FROM search_terms_sqp
  UNION ALL
  SELECT
    ats.query_text,
    COALESCE(o.gender,    `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(ats.query_text).gender)    AS gender,
    COALESCE(o.age_group, `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(ats.query_text).age_group) AS age_group,
    COALESCE(o.occasion,  `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(ats.query_text).occasion)  AS occasion,
    `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(ats.query_text).holiday                          AS holiday,
    COALESCE(o.product_type, atpt.product_type) AS product_type,
    o.brand                                     AS brand,
    o.cost_tier                                 AS cost_tier,
    CAST(NULL AS INT64)   AS weekly_market_impressions,
    CAST(NULL AS INT64)   AS weekly_market_clicks,
    CAST(NULL AS INT64)   AS weekly_market_purchases,
    CAST(NULL AS FLOAT64) AS median_click_price
  FROM search_terms_ads ats
  LEFT JOIN ads_term_overrides o ON LOWER(o.query_text) = ats.query_text
  LEFT JOIN ads_term_product_type atpt ON atpt.query_text = ats.query_text
),

-- Family-level SQP performance per term (was a per-request subquery in /related-terms)
family_sqp AS (
  SELECT
    dp.parent_name,
    LOWER(sq.query_text) AS query_text,
    SUM(sq.conversions) AS family_purchases,
    SUM(sq.clicks)      AS family_clicks,
    SUM(sq.impressions) AS family_impressions
  FROM `onyga-482313`.OI.FACT_SEARCH_QUERY sq
  JOIN `onyga-482313`.OI.DIM_PRODUCT dp ON sq.ASIN = dp.asin
  WHERE sq.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 104 WEEK)
  GROUP BY dp.parent_name, query_text
),
```

  In `scored`, add after the est_cps join:

```sql
  LEFT JOIN family_sqp fq
    ON fq.parent_name = fs.parent_name AND fq.query_text = LOWER(st.query_text)
```

  and in its SELECT list add:

```sql
    COALESCE(fq.family_purchases, 0)   AS family_purchases,
    COALESCE(fq.family_clicks, 0)      AS family_clicks,
    COALESCE(fq.family_impressions, 0) AS family_impressions,
    sf.gender_score, sf.age_score, sf.occasion_score, sf.pt_score,
```

  `seg_fit_final` must therefore also pass through the four per-field scores:

```sql
seg_fit_final AS (
  SELECT
    parent_name, query_text,
    gender_score, age_score, occasion_score, pt_score,
    CASE
      WHEN gender_score = -1 OR age_score = -1 OR occasion_score = -1 OR pt_score = -1 THEN 10
      ELSE COALESCE(gender_score, 0) + COALESCE(age_score, 0) + COALESCE(occasion_score, 0) + COALESCE(pt_score, 0)
    END AS seg_fit
  FROM seg_fit_calc
),
```

  Replace the `effective_cps` + `cps_fit` + `overall_fit` block in `scored` with a two-stage computation. `scored` keeps everything *except* cps_fit/overall_fit and instead emits:

```sql
    -- CPS for scoring (real CVR → 1/CVR, else curve estimate) + provenance
    CASE
      WHEN COALESCE(am.ads_family_orders, 0) > 0 AND COALESCE(am.units_cvr_30d, am.units_cvr_12m) > 0
        THEN 1.0 / COALESCE(am.units_cvr_30d, am.units_cvr_12m)
      ELSE ec.est_cps
    END AS effective_cps,
    CASE
      WHEN COALESCE(am.ads_family_orders, 0) > 0 AND COALESCE(am.units_cvr_30d, am.units_cvr_12m) > 0
        THEN IF(am.units_cvr_30d IS NOT NULL, 'ads_30d', 'ads_12m')
      WHEN ec.est_cps IS NOT NULL THEN 'curve'
      ELSE NULL
    END AS cps_source,
    COALESCE(am.ads_family_orders, 0) > 3
      AND COALESCE(am.units_cvr_30d, am.units_cvr_12m) > 0 AS has_reliable_ads_cvr,
```

  Then the final SELECT (after `scored`) becomes:

```sql
SELECT
  * EXCEPT(has_reliable_ads_cvr),
  CASE
    WHEN holiday IS NOT NULL AND NOT is_holiday_active THEN 0
    ELSE ROUND(
      (COALESCE(overall_fit, 0) + COALESCE(purchase_rank, 0))
      / NULLIF(IF(overall_fit IS NOT NULL, 1, 0) + IF(purchase_rank IS NOT NULL, 1, 0), 0)
    )
  END AS rank
FROM (
  SELECT
    *,
    CASE
      WHEN effective_cps IS NULL THEN NULL
      WHEN effective_cps <= 5  THEN 100
      WHEN effective_cps <= 8  THEN 85
      WHEN effective_cps <= 12 THEN 70
      WHEN effective_cps <= 20 THEN 55
      WHEN effective_cps <= 35 THEN 35
      WHEN effective_cps <= 50 THEN 20
      ELSE 10
    END AS cps_fit,
    CASE
      WHEN has_reliable_ads_cvr THEN
        CASE
          WHEN effective_cps <= 5  THEN 100
          WHEN effective_cps <= 8  THEN 85
          WHEN effective_cps <= 12 THEN 70
          WHEN effective_cps <= 20 THEN 55
          WHEN effective_cps <= 35 THEN 35
          WHEN effective_cps <= 50 THEN 20
          ELSE 10
        END
      ELSE ROUND(
        (COALESCE(seg_fit, 0) +
         COALESCE(CASE
           WHEN est_cps <= 5  THEN 100
           WHEN est_cps <= 8  THEN 85
           WHEN est_cps <= 12 THEN 70
           WHEN est_cps <= 20 THEN 55
           WHEN est_cps <= 35 THEN 35
           WHEN est_cps <= 50 THEN 20
           WHEN est_cps IS NOT NULL THEN 10
           ELSE NULL END, 0)
        ) / NULLIF(IF(seg_fit IS NOT NULL, 1, 0) + IF(est_cps IS NOT NULL, 1, 0), 0)
      )
    END AS overall_fit
  FROM scored
)
```

  Note the semantic preservation quirk: in the no-reliable-ads branch, `overall_fit` averages seg_fit with the **est_cps** bracket (not effective_cps) — identical to today's behavior where a term with 1-3 orders uses real CPS for `cps_fit` but curve CPS inside `overall_fit`.
  Update the header comment (dependencies now include FN_EXTRACT_SEGMENTS, DE_SEARCH_TERM_SEGMENTS, DE_PRODUCT_TYPE_KEYWORDS, FACT_SEARCH_QUERY; new output columns documented).
- [ ] **Step 3.2:** Deploy the view.
- [ ] **Step 3.3:** Validation queries (all must pass):
  - `SELECT DISTINCT gender FROM OI.V_RESEARCH_RANKED WHERE gender IS NOT NULL` → only `Female`,`Male`.
  - `SELECT DISTINCT age_group FROM OI.V_RESEARCH_RANKED WHERE age_group IS NOT NULL` → subset of `{0-2 (Baby), 2-4 (Toddler), 5-9 (Kid), 8-14, 10-12 (Tween), 13-17 (Teen), 18+ (Adult)}`.
  - `SELECT COUNT(*) FROM OI.V_RESEARCH_RANKED WHERE rank NOT BETWEEN 0 AND 100` → 0.
  - `SELECT COUNT(*) FROM OI.V_RESEARCH_RANKED WHERE holiday IS NOT NULL AND NOT is_holiday_active AND rank != 0` → 0.
  - Spot-check one row's `gender_score+age_score+occasion_score+pt_score` vs `seg_fit` (no-mismatch case).
- [ ] **Step 3.4:** Commit: `fix(research): V_RESEARCH_RANKED — UDF taxonomy (kills Girl/Boy drift), overrides, family SQP metrics, explanation columns, dead reasoning CTEs removed`

### Task 4: `V_RESEARCH_TERMS` + materialization

**Files:**
- Create: `scripts/bigquery/views/V_RESEARCH_TERMS.sql`
- Create: `scripts/bigquery/procedures/SP_REFRESH_RESEARCH_RANKED.sql`
- Modify: `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql`

- [ ] **Step 4.1:** Create `V_RESEARCH_TERMS` — term-grain aggregates over a fixed 104-week window, extracted verbatim from the duplicated endpoint CTEs (`last_week_data`, `median_price_fallback`, aggregation, `is_brand_term`):

```sql
-- =============================================
-- V_RESEARCH_TERMS
-- Purpose: per-search-term market/brand aggregates for the Research page.
--          Single home for the CTE block previously duplicated across
--          /api/research/top-terms and /api/research/related-terms.
-- Grain: query_text. Window: fixed 104 weeks (2 years).
-- Note: top-terms previously used a 12-month window; unified to 104w here.
-- Dependencies: V_SQP_QUERY_WEEKLY, SRC_ACC_SQP_WEEKLY, DIM_PRODUCT
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313`.OI.V_RESEARCH_TERMS AS
WITH brand_stems AS (
  SELECT DISTINCT LOWER(SUBSTR(parent_name, 1, LEAST(5, LENGTH(parent_name)))) AS stem
  FROM `onyga-482313`.OI.DIM_PRODUCT
  WHERE is_active = true
),
last_week_data AS (
  SELECT v.query_text, v.week_start_date AS last_week,
    v.search_query_volume AS lw_impressions,
    v.TOTAL_CLICKS AS lw_clicks,
    v.TOTAL_PURCHASES AS lw_purchases,
    MAX(s.Purchases_Price_Median) AS lw_median_click_price,
    MAX(s.Clicks_Price_Median) AS lw_clicks_median
  FROM `onyga-482313`.OI.V_SQP_QUERY_WEEKLY v
  LEFT JOIN `onyga-482313`.OI.SRC_ACC_SQP_WEEKLY s
    ON s.Search_Query = v.query_text AND s.Reporting_Date = v.week_end_date
  WHERE v.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 104 WEEK)
    AND v.query_text != 'OTHER'
  GROUP BY v.query_text, v.week_start_date, v.week_end_date, v.search_query_volume, v.TOTAL_CLICKS, v.TOTAL_PURCHASES
  QUALIFY ROW_NUMBER() OVER (PARTITION BY v.query_text ORDER BY v.week_start_date DESC) = 1
),
median_price_fallback AS (
  SELECT query_text, TOTAL_MEDIAN_CLICK_PRICE AS fallback_median_price
  FROM `onyga-482313`.OI.V_SQP_QUERY_WEEKLY
  WHERE TOTAL_MEDIAN_CLICK_PRICE IS NOT NULL
    AND week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY query_text ORDER BY week_start_date DESC) = 1
),
aggregated AS (
  SELECT
    v.query_text,
    COUNT(*) AS weeks_appeared,
    SUM(v.TOTAL_IMPRESSIONS) AS market_impressions,
    SUM(v.TOTAL_CLICKS) AS market_clicks,
    COALESCE(SUM(v.TOTAL_PURCHASES), 0) AS market_purchases,
    SUM(v.BRAND_IMPRESSIONS) AS brand_impressions,
    SUM(v.BRAND_CLICKS) AS brand_clicks,
    SUM(v.BRAND_PURCHASES) AS brand_purchases,
    SUM(v.BRAND_SALES) AS brand_sales,
    COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) AS median_click_price,
    COALESCE(ANY_VALUE(lw.lw_clicks_median), ANY_VALUE(mpf.fallback_median_price)) AS clicks_median,
    CAST(ANY_VALUE(lw.last_week) AS STRING) AS last_week,
    ANY_VALUE(lw.lw_impressions) AS weekly_market_impressions,
    ANY_VALUE(lw.lw_clicks) AS weekly_market_clicks,
    ANY_VALUE(lw.lw_purchases) AS weekly_market_purchases,
    ANY_VALUE(v.gender) AS gender,
    ANY_VALUE(v.age_group) AS age_group,
    ANY_VALUE(v.occasion) AS occasion,
    ANY_VALUE(v.holiday) AS holiday,
    CASE
      WHEN COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) < 10 THEN 'Budget (<$10)'
      WHEN COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) < 20 THEN 'Value ($10-$20)'
      WHEN COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) < 35 THEN 'Mid ($20-$35)'
      WHEN COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) < 50 THEN 'Premium ($35-$50)'
      WHEN COALESCE(ANY_VALUE(lw.lw_median_click_price), ANY_VALUE(mpf.fallback_median_price)) >= 50 THEN 'Luxury ($50+)'
      ELSE NULL
    END AS cost_tier,
    ANY_VALUE(v.product_type) AS product_type,
    ANY_VALUE(v.brand) AS brand
  FROM `onyga-482313`.OI.V_SQP_QUERY_WEEKLY v
  LEFT JOIN last_week_data lw ON lw.query_text = v.query_text
  LEFT JOIN median_price_fallback mpf ON mpf.query_text = v.query_text
  WHERE v.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 104 WEEK)
    AND v.query_text != 'OTHER'
  GROUP BY v.query_text
)
SELECT
  a.*,
  ROUND(SAFE_DIVIDE(a.market_purchases, a.market_clicks) * 100, 2) AS market_cvr_pct,
  ROUND(SAFE_DIVIDE(a.weekly_market_purchases, a.weekly_market_clicks) * 100, 2) AS weekly_market_cvr_pct,
  ROUND(SAFE_DIVIDE(a.brand_impressions, a.market_impressions) * 100, 4) AS show_rate_pct,
  EXISTS(SELECT 1 FROM brand_stems bs WHERE LOWER(a.query_text) LIKE CONCAT('%', bs.stem, '%')) AS is_brand_term
FROM aggregated a
```

- [ ] **Step 4.2:** Create `SP_REFRESH_RESEARCH_RANKED.sql`:

```sql
-- =============================================
-- SP_REFRESH_RESEARCH_RANKED
-- Purpose: Materializes V_RESEARCH_TERMS → FACT_RESEARCH_TERMS and
--          V_RESEARCH_RANKED → FACT_RESEARCH_RANKED so Research page
--          endpoints read pre-computed tables instead of recomputing
--          the cross-join view per request.
-- Called by: SP_ORCHESTRATE_DAILY_REFRESH (after SP_LOAD_FACT_SEARCH_QUERY)
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_RESEARCH_RANKED`()
BEGIN
  CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_RESEARCH_TERMS`
  AS SELECT * FROM `onyga-482313.OI.V_RESEARCH_TERMS`;

  CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_RESEARCH_RANKED`
  CLUSTER BY parent_name, query_text
  AS SELECT * FROM `onyga-482313.OI.V_RESEARCH_RANKED`;
END;
```

- [ ] **Step 4.3:** Deploy view + SP, then run: `bq query --use_legacy_sql=false "CALL \`onyga-482313.OI\`.SP_REFRESH_RESEARCH_RANKED()"`. Verify: `SELECT COUNT(*) FROM OI.FACT_RESEARCH_TERMS` > 0 and `SELECT COUNT(*) FROM OI.FACT_RESEARCH_RANKED` > 0.
- [ ] **Step 4.4:** Append a CALL block for `SP_REFRESH_RESEARCH_RANKED` to `SP_ORCHESTRATE_DAILY_REFRESH.sql` after the `SP_LOAD_FACT_SEARCH_QUERY` block, copying the exact logging/BEGIN-EXCEPTION format observed in Step 0.3. Deploy the orchestrator.
- [ ] **Step 4.5:** Commit: `feat(research): materialize research scoring — V_RESEARCH_TERMS, FACT_RESEARCH_TERMS/RANKED, SP_REFRESH_RESEARCH_RANKED in daily orchestration`

### Task 5: Unify the remaining two regex copies

**Files:**
- Modify: `scripts/bigquery/procedures/SP_DERIVE_PRODUCT_SEGMENTS.sql`
- Modify: `data-entry-app/app.py` (`segment_reasoning` endpoint, ~line 7590)

- [ ] **Step 5.1:** In `SP_DERIVE_PRODUCT_SEGMENTS.sql`, replace the gender/age/occasion regex CASE blocks with `FN_EXTRACT_SEGMENTS(a.search_term).gender / .age_group / .occasion`, and replace the product_type regex CASE with a `DE_PRODUCT_TYPE_KEYWORDS` lookup join (same `REGEXP_CONTAINS(CONCAT(r'(?:^|\W)', ptk.keyword, r'(?:\W|$)'))` + `priority ASC, LENGTH DESC` pattern). Deploy.
- [ ] **Step 5.2:** In `segment_reasoning()` in app.py, replace the four inline CASE blocks in the `tagged` CTE with:

```sql
            `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(a.search_term).gender    AS gender,
            `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(a.search_term).age_group AS age_group,
            `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(a.search_term).occasion  AS occasion,
            ptl.product_type AS product_type
```

  adding to the CTE's FROM:

```sql
          LEFT JOIN (
            SELECT LOWER(t.search_term) AS search_term,
              ARRAY_AGG(ptk.product_type ORDER BY ptk.priority ASC, LENGTH(ptk.keyword) DESC LIMIT 1)[OFFSET(0)] AS product_type
            FROM (SELECT DISTINCT search_term FROM `onyga-482313`.OI.FACT_AMAZON_ADS WHERE Ads_clicks > 0) t
            CROSS JOIN `onyga-482313.OI.DE_PRODUCT_TYPE_KEYWORDS` ptk
            WHERE REGEXP_CONTAINS(LOWER(t.search_term), CONCAT(r'(?:^|\W)', ptk.keyword, r'(?:\W|$)'))
            GROUP BY 1
          ) ptl ON ptl.search_term = LOWER(a.search_term)
```

- [ ] **Step 5.3:** Re-run derive for one family and eyeball: `curl -s -X POST localhost? — not running locally;` instead verify by running the SP directly: `bq query "CALL OI.SP_DERIVE_PRODUCT_SEGMENTS(''<family from Step 0.2 data>'')"` then `SELECT seg_gender, seg_age_group, seg_product_type FROM OI.DIM_PRODUCT WHERE parent_name='<family>' LIMIT 3` — values must be in canonical vocab. **Only run if Ori's current seg values would be regenerated identically — otherwise skip the CALL (it overwrites manually curated segments) and verify via dry SELECT of the SP's internal query logic.** Safer default: do NOT call the SP; deploy only.
- [ ] **Step 5.4:** Commit: `refactor(research): SP_DERIVE_PRODUCT_SEGMENTS + segment-reasoning use FN_EXTRACT_SEGMENTS / DE_PRODUCT_TYPE_KEYWORDS vocab`

### Task 6: Backend endpoint rewrite

**Files:**
- Modify: `data-entry-app/app.py` (research section, lines 6819-7352)

- [ ] **Step 6.1: `/api/research/top-terms`** — replace body with a thin SELECT over the FACT tables (fix docstring; keep returning all rows):

```python
@app.route('/api/research/top-terms', methods=['GET'])
def research_top_terms():
    """Return all search terms with brand purchases (104-week window), enriched
    with per-family scores from FACT_RESEARCH_RANKED when ?parent= is given.
    Client sorts/paginates."""
    parent = (request.args.get('parent') or '').strip() or None
    try:
        rr_cols = """
          rr.cpc_12m, rr.cpc_30d, rr.units_cvr_30d, rr.units_cvr_12m,
          COALESCE(rr.ads_family_orders, 0) AS ads_family_orders,
          COALESCE(rr.ads_units_30d, 0) AS ads_units_30d, COALESCE(rr.ads_units_12m, 0) AS ads_units_12m,
          rr.roas_30d,
          rr.cvr_christmas, rr.cvr_easter, rr.cvr_valentines, rr.cvr_graduation, rr.cvr_back_to_school, rr.cvr_mothers_day,
          rr.seg_fit, rr.cps_fit, rr.overall_fit,
          rr.gender_score, rr.age_score, rr.occasion_score, rr.pt_score,
          rr.cps_source, rr.effective_cps, rr.is_holiday_active,
          rr.purchase_rank AS purchase_rank_score, rr.rank AS rank_score,
          rr.ads_purch, rr.ads_cps, rr.est_cps,
          COALESCE(rr.family_purchases, 0) AS family_purchases,
          COALESCE(rr.family_clicks, 0) AS family_clicks,
          COALESCE(rr.family_impressions, 0) AS family_impressions
        """ if parent else """
          CAST(NULL AS FLOAT64) AS cpc_12m, CAST(NULL AS FLOAT64) AS cpc_30d,
          CAST(NULL AS FLOAT64) AS units_cvr_30d, CAST(NULL AS FLOAT64) AS units_cvr_12m,
          0 AS ads_family_orders, 0 AS ads_units_30d, 0 AS ads_units_12m,
          CAST(NULL AS FLOAT64) AS roas_30d,
          CAST(NULL AS FLOAT64) AS cvr_christmas, CAST(NULL AS FLOAT64) AS cvr_easter,
          CAST(NULL AS FLOAT64) AS cvr_valentines, CAST(NULL AS FLOAT64) AS cvr_graduation,
          CAST(NULL AS FLOAT64) AS cvr_back_to_school, CAST(NULL AS FLOAT64) AS cvr_mothers_day,
          CAST(NULL AS FLOAT64) AS seg_fit, CAST(NULL AS INT64) AS cps_fit, CAST(NULL AS FLOAT64) AS overall_fit,
          CAST(NULL AS INT64) AS gender_score, CAST(NULL AS INT64) AS age_score,
          CAST(NULL AS INT64) AS occasion_score, CAST(NULL AS INT64) AS pt_score,
          CAST(NULL AS STRING) AS cps_source, CAST(NULL AS FLOAT64) AS effective_cps,
          CAST(NULL AS BOOL) AS is_holiday_active,
          CAST(NULL AS FLOAT64) AS purchase_rank_score, CAST(NULL AS FLOAT64) AS rank_score,
          CAST(NULL AS INT64) AS ads_purch, CAST(NULL AS FLOAT64) AS ads_cps, CAST(NULL AS FLOAT64) AS est_cps,
          0 AS family_purchases, 0 AS family_clicks, 0 AS family_impressions
        """
        join = ("LEFT JOIN `onyga-482313`.OI.FACT_RESEARCH_RANKED rr "
                "ON rr.parent_name = @parent AND LOWER(rr.query_text) = LOWER(t.query_text)") if parent else ""
        sql = f"""
        SELECT t.*, {rr_cols}
        FROM `onyga-482313`.OI.FACT_RESEARCH_TERMS t
        {join}
        WHERE t.brand_purchases > 0
        ORDER BY t.brand_purchases DESC
        """
        params = [bigquery.ScalarQueryParameter('parent', 'STRING', parent)] if parent else []
        job_config = bigquery.QueryJobConfig(query_parameters=params) if params else None
        rows = [dict(r) for r in client.query(sql, job_config=job_config).result()]
        return jsonify(rows)
    except Exception as e:
        print(f"Error in research_top_terms: {e}")
        return jsonify({'error': str(e)}), 500
```

- [ ] **Step 6.2: `/api/research/related-terms`** — keep the synonym/word-pattern machinery and `seed_asins`/`related_queries` co-occurrence CTEs **unchanged**, delete `last_week_data`/`median_price_fallback`/`aggregated`/hero/family-purchases subqueries, and join FACT tables instead. Remove the dead `weeks` body param (window fixed at 104 in the FACT layer; keep `@weeks=104` only for the seed CTEs). New SQL body:

```python
    sql = f"""
    WITH seed_asins AS (
      SELECT DISTINCT sq.ASIN
      FROM `onyga-482313`.OI.FACT_SEARCH_QUERY sq
      WHERE {word_likes_sq}
        AND sq.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL @weeks WEEK)
    ),
    seed_count AS (SELECT COUNT(*) AS total_seed_asins FROM seed_asins),
    related_queries AS (
      SELECT sq2.query_text, COUNT(DISTINCT sq2.ASIN) AS asin_overlap
      FROM `onyga-482313`.OI.FACT_SEARCH_QUERY sq2
      WHERE sq2.ASIN IN (SELECT ASIN FROM seed_asins)
        AND sq2.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL @weeks WEEK)
        AND sq2.query_text != 'OTHER'
      GROUP BY sq2.query_text
    )
    SELECT
      t.*,
      CASE WHEN {word_likes_t} THEN 'direct' ELSE 'related' END AS match_type,
      rq.asin_overlap,
      sc.total_seed_asins,
      ROUND(SAFE_DIVIDE(rq.asin_overlap, sc.total_seed_asins) * 100, 1) AS overlap_pct,
      {rr_cols}
    FROM related_queries rq
    JOIN `onyga-482313`.OI.FACT_RESEARCH_TERMS t ON t.query_text = rq.query_text
    CROSS JOIN seed_count sc
    {join}
    ORDER BY t.market_purchases DESC
    """
```

  where `rr_cols`/`join` are the same strings as Step 6.1 (extract both into a module-level helper `_research_ranked_select(parent)` returning `(rr_cols, join)` so the two endpoints share them — `join` here uses alias `t`). `word_likes_t` = the existing `word_likes_v` builder with alias `v.` → `t.`. Keep the param assembly; drop the `weeks = data.get(...)` line (already hardcoded) and the hero/family JOIN blocks entirely.
- [ ] **Step 6.3: new `/api/research/term-ranks`** (replaces the frontend's N×2 family-info preloading and the broken all-families tooltip):

```python
@app.route('/api/research/term-ranks', methods=['POST'])
def research_term_ranks():
    """Per-family rank breakdown for a batch of terms (hover comparison).
    Body: { "terms": ["...", ...] }  (≤500)
    Returns: { "<term>": [ {parent_name, rank, purchase_rank, overall_fit, seg_fit, cps_fit, ads_cps, est_cps}, ... ] }"""
    data = request.get_json() or {}
    terms = [t.lower() for t in (data.get('terms') or [])][:500]
    if not terms:
        return jsonify({})
    try:
        sql = """
        SELECT parent_name, LOWER(query_text) AS query_text,
               rank, purchase_rank, overall_fit, seg_fit, cps_fit, ads_cps, est_cps
        FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE LOWER(query_text) IN UNNEST(@terms)
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ArrayQueryParameter('terms', 'STRING', terms)
        ])
        out = {}
        for row in client.query(sql, job_config=jc).result():
            d = dict(row)
            out.setdefault(d.pop('query_text'), []).append(d)
        return jsonify(out)
    except Exception as e:
        print(f"Error in research_term_ranks: {e}")
        return jsonify({'error': str(e)}), 500
```

- [ ] **Step 6.4: `/api/research/get-synonyms`** — move `_SYNONYM_GROUPS` + `_SYNONYM_MAP` construction from inside `research_related_terms()` to module level (just above `_synonym_cache`), and in `research_get_synonyms()` replace the final "Words not in the table get empty arrays" loop with:

```python
    # Words not in the table fall back to the hardcoded synonym groups
    for w in uncached_words:
        if w not in result:
            fallback = _SYNONYM_MAP.get(w, [])
            _synonym_cache[w] = fallback
            result[w] = fallback
```

  (`research_related_terms` keeps using the module-level `_SYNONYM_MAP` for its server-side merge.)
- [ ] **Step 6.5: `/api/research/update-segments`** — replace DELETE+load with one atomic MERGE:

```python
        sql = """
        MERGE `onyga-482313`.OI.DE_SEARCH_TERM_SEGMENTS t
        USING (SELECT @query_text AS query_text) s
        ON t.query_text = s.query_text
        WHEN MATCHED THEN UPDATE SET
          gender = @gender, age_group = @age_group, occasion = @occasion,
          cost_tier = @cost_tier, product_type = @product_type, brand = @brand,
          updated_at = CURRENT_TIMESTAMP()
        WHEN NOT MATCHED THEN INSERT
          (query_text, gender, age_group, occasion, cost_tier, product_type, brand, updated_at)
        VALUES (@query_text, @gender, @age_group, @occasion, @cost_tier, @product_type, @brand, CURRENT_TIMESTAMP())
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('query_text', 'STRING', query_text),
            bigquery.ScalarQueryParameter('gender', 'STRING', updates.get('gender')),
            bigquery.ScalarQueryParameter('age_group', 'STRING', updates.get('age_group')),
            bigquery.ScalarQueryParameter('occasion', 'STRING', updates.get('occasion')),
            bigquery.ScalarQueryParameter('cost_tier', 'STRING', updates.get('cost_tier')),
            bigquery.ScalarQueryParameter('product_type', 'STRING', updates.get('product_type')),
            bigquery.ScalarQueryParameter('brand', 'STRING', updates.get('brand')),
        ])
        client.query(sql, job_config=jc).result()
        clear_data_cache()
        return jsonify({'success': True})
```

  Note in the endpoint docstring: overrides surface after the next `SP_REFRESH_RESEARCH_RANKED` run (views read them live; FACT tables on next refresh).
- [ ] **Step 6.6:** Add `@cache_result(...)` to `/conversion-curve` and `/products` (and to `/family-info`, `/segment-reasoning`, `/top-terms` **only if** Step 0.1 confirmed arg-aware keys). Place decorator between `@app.route` and the function per existing app convention (verify with an existing cached route).
- [ ] **Step 6.7:** Verify: `python3 -m py_compile data-entry-app/app.py`. Then live-test each query shape directly against BQ with `bq query` (substituting a real parent name) since Flask isn't running locally — at minimum the top-terms SQL and the related-terms SQL with one word param.
- [ ] **Step 6.8:** Commit: `refactor(research): endpoints read FACT_RESEARCH_* — dedup 200-line SQL, term-ranks batch endpoint, synonym fallback, atomic MERGE for overrides`

### Task 7: SQL validation tool

**Files:**
- Create: `tools/validate_research_ranked.py`

- [ ] **Step 7.1:** Write a deterministic assertion script (project pattern: atomic Python tool):

```python
#!/usr/bin/env python3
"""Validate FACT_RESEARCH_RANKED / FACT_RESEARCH_TERMS invariants.
Run after SP_REFRESH_RESEARCH_RANKED. Exits non-zero on violation."""
import sys
from google.cloud import bigquery

CHECKS = [
    ("gender enum", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE gender IS NOT NULL AND gender NOT IN ('Female','Male')"""),
    ("age enum", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE age_group IS NOT NULL AND age_group NOT IN
        ('0-2 (Baby)','2-4 (Toddler)','5-9 (Kid)','8-14','10-12 (Tween)','13-17 (Teen)','18+ (Adult)')"""),
    ("rank bounds", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE rank IS NOT NULL AND (rank < 0 OR rank > 100)"""),
    ("off-season holiday rank=0", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE holiday IS NOT NULL AND NOT is_holiday_active AND rank != 0"""),
    ("seg_fit consistency (no-mismatch rows)", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE seg_fit != 10
          AND seg_fit != COALESCE(gender_score,0)+COALESCE(age_score,0)+COALESCE(occasion_score,0)+COALESCE(pt_score,0)"""),
    ("terms table non-empty (inverted)", """
        SELECT IF(COUNT(*) > 0, 0, 1) FROM `onyga-482313`.OI.FACT_RESEARCH_TERMS"""),
]

def main():
    client = bigquery.Client(project='onyga-482313')
    failures = 0
    for name, sql in CHECKS:
        n = list(client.query(sql).result())[0][0]
        status = 'OK' if n == 0 else f'FAIL ({n} rows)'
        print(f"  {name}: {status}")
        failures += 1 if n != 0 else 0
    sys.exit(1 if failures else 0)

if __name__ == '__main__':
    main()
```

- [ ] **Step 7.2:** Run: `/usr/bin/python3 tools/validate_research_ranked.py` → all OK, exit 0. (If `seg_fit consistency` fails, inspect rows — the mismatch-cap path must be excluded correctly.)
- [ ] **Step 7.3:** Commit: `test(research): validate_research_ranked.py invariant checks`

### Task 8: Frontend shared modules + tests

**Files:**
- Create: `dashboard-react/src/pages/research/types.ts`
- Create: `dashboard-react/src/pages/research/mapRow.ts`
- Create: `dashboard-react/src/pages/research/mapRow.test.ts`

- [ ] **Step 8.1:** `types.ts`: move `ResearchRow`, `ConversionCurveRow`, `SortKey`, `SortDir`, `ProductInfo`, `FamilyProduct`, `FamilySummary`, `FamilyInfo`, `SEASONS` out of ResearchPage.tsx verbatim, with these `ResearchRow` changes: **add** `gender_score: number | null; age_score: number | null; occasion_score: number | null; pt_score: number | null; cps_source: 'ads_30d' | 'ads_12m' | 'curve' | null; effective_cps: number | null; is_holiday_active: boolean | null;` and **add** `TermRank` + `TermRanksMap`:

```ts
export interface TermRank {
  parent_name: string;
  rank: number | null;
  purchase_rank: number | null;
  overall_fit: number | null;
  seg_fit: number | null;
  cps_fit: number | null;
  ads_cps: number | null;
  est_cps: number | null;
}
export type TermRanksMap = Record<string, TermRank[]>;
```

- [ ] **Step 8.2:** `mapRow.ts` — THE single mapper (both fetch sites use it; kills the diverged copies):

```ts
import type { ResearchRow } from './types';

const num = (v: unknown): number | null => (v == null ? null : Number(v));
const int = (v: unknown): number => (v == null ? 0 : Number(v));

/** Normalize an API row (top-terms or related-terms) into a ResearchRow.
 *  Single place that decides defaults — keep null for "unknown",
 *  0 only for additive counters. */
export function mapResearchRow(t: Record<string, unknown>): ResearchRow {
  return {
    query_text: String(t.query_text ?? ''),
    match_type: (t.match_type as 'direct' | 'related') ?? 'direct',
    asin_overlap: int(t.asin_overlap),
    total_seed_asins: int(t.total_seed_asins),
    overlap_pct: num(t.overlap_pct),
    weeks_appeared: int(t.weeks_appeared),
    market_impressions: int(t.market_impressions),
    market_clicks: int(t.market_clicks),
    market_purchases: int(t.market_purchases),
    market_cvr_pct: num(t.market_cvr_pct),
    brand_impressions: int(t.brand_impressions),
    brand_clicks: int(t.brand_clicks),
    brand_purchases: int(t.brand_purchases),
    brand_sales: int(t.brand_sales),
    show_rate_pct: num(t.show_rate_pct),
    median_click_price: num(t.median_click_price),
    cost_tier: (t.cost_tier as string) ?? null,
    gender: (t.gender as string) ?? null,
    age_group: (t.age_group as string) ?? null,
    occasion: (t.occasion as string) ?? null,
    holiday: (t.holiday as string) ?? null,
    cpc_12m: num(t.cpc_12m),
    cpc_30d: num(t.cpc_30d),
    product_type: (t.product_type as string) ?? null,
    is_brand_term: Boolean(t.is_brand_term),
    brand: (t.brand as string) ?? null,
    units_cvr_30d: num(t.units_cvr_30d),
    units_cvr_12m: num(t.units_cvr_12m),
    ads_family_orders: int(t.ads_family_orders),
    ads_units_30d: num(t.ads_units_30d),
    ads_units_12m: num(t.ads_units_12m),
    roas_30d: num(t.roas_30d),
    cvr_christmas: num(t.cvr_christmas),
    cvr_easter: num(t.cvr_easter),
    cvr_valentines: num(t.cvr_valentines),
    cvr_graduation: num(t.cvr_graduation),
    cvr_back_to_school: num(t.cvr_back_to_school),
    cvr_mothers_day: num(t.cvr_mothers_day),
    family_purchases: int(t.family_purchases),
    family_clicks: int(t.family_clicks),
    family_impressions: int(t.family_impressions),
    last_week: (t.last_week as string) ?? null,
    weekly_market_impressions: int(t.weekly_market_impressions),
    weekly_market_clicks: int(t.weekly_market_clicks),
    weekly_market_purchases: int(t.weekly_market_purchases),
    weekly_market_cvr_pct: num(t.weekly_market_cvr_pct),
    clicks_median: num(t.clicks_median),
    seg_fit: num(t.seg_fit),
    cps_fit: num(t.cps_fit),
    overall_fit: num(t.overall_fit),
    purchase_rank_score: num(t.purchase_rank_score),
    rank_score: num(t.rank_score),
    ads_purch: num(t.ads_purch),
    ads_cps: num(t.ads_cps),
    est_cps: num(t.est_cps),
    gender_score: num(t.gender_score),
    age_score: num(t.age_score),
    occasion_score: num(t.occasion_score),
    pt_score: num(t.pt_score),
    cps_source: (t.cps_source as ResearchRow['cps_source']) ?? null,
    effective_cps: num(t.effective_cps),
    is_holiday_active: t.is_holiday_active == null ? null : Boolean(t.is_holiday_active),
  };
}
```

  (Note: `brand_hero_asin`/`brand_hero_name`/`avg_cpc` are intentionally dropped — confirmed dead in Step 0.5.)
- [ ] **Step 8.3:** `mapRow.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { mapResearchRow } from './mapRow';

describe('mapResearchRow', () => {
  it('defaults counters to 0 and optionals to null on empty input', () => {
    const r = mapResearchRow({ query_text: 'x' });
    expect(r.market_impressions).toBe(0);
    expect(r.ads_family_orders).toBe(0);
    expect(r.weekly_market_purchases).toBe(0);
    expect(r.median_click_price).toBeNull();
    expect(r.rank_score).toBeNull();
    expect(r.cps_source).toBeNull();
    expect(r.is_holiday_active).toBeNull();
    expect(r.match_type).toBe('direct');
  });
  it('passes through API values and coerces numerics', () => {
    const r = mapResearchRow({
      query_text: 'gift', match_type: 'related', rank_score: '72',
      seg_fit: 60, cps_source: 'curve', is_holiday_active: false,
      weekly_market_purchases: 120, est_cps: 9.4,
    });
    expect(r.match_type).toBe('related');
    expect(r.rank_score).toBe(72);
    expect(r.seg_fit).toBe(60);
    expect(r.cps_source).toBe('curve');
    expect(r.is_holiday_active).toBe(false);
    expect(r.weekly_market_purchases).toBe(120);
    expect(r.est_cps).toBeCloseTo(9.4);
  });
});
```

- [ ] **Step 8.4:** Run `cd dashboard-react && npx vitest run src/pages/research/mapRow.test.ts` → PASS. Commit: `feat(research-ui): shared types + single mapResearchRow with tests`

### Task 9: ResearchPage — delete client scoring, adopt SQL explanations

**Files:**
- Modify: `dashboard-react/src/pages/ResearchPage.tsx`

- [ ] **Step 9.1: Delete** (confirmed replaceable/dead): `getMatchRank`, `getSegFitTooltip` (replaced), `getCpsFitScore`, `getCpsFitTooltip` (replaced), `getAdsPerfScore` (dead), `getOverallFit`, `getPurchaseRank`, `getRank`, `getEstCps`, `HOLIDAY_WINDOWS`, `isHolidayActive`, `HOLIDAY_CVR_MAP`, `OCCASION_CVR_MAP`, `getMatchRankForFamily`, `getAllFamiliesTooltip`, `ratioBadge` (dead), the `allFamiliesData` state + its N×2-fetch `useEffect`, and the client-side search-word re-filter block inside `displayRows` (server already filters).
- [ ] **Step 9.2: Replace both inline mapping blocks** with `mapResearchRow`: `setResults(topData.map(mapResearchRow))` / `setResults((await res.json()).map(mapResearchRow))`; import types from `./research/types` and delete the local interface declarations. Remove `weeks` from all request payloads and the `weeks` const.
- [ ] **Step 9.3: New SQL-backed tooltips** (pure formatters over row fields):

```ts
const segFitTooltip = (row: ResearchRow): string => {
  const fld = (label: string, val: string | null, score: number | null, pts: number) => {
    if (score == null) return `${label}: family not segmented (skipped)`;
    if (score === -1) return `${label}: "${val}" ✗ MISMATCH → cap 10`;
    if (score === 0) return `${label}: unknown → +0`;
    return `${label}: "${val}" ${score < pts ? '~ ADJACENT' : '✓ MATCH'} → +${score}`;
  };
  return [
    `SEG FIT for "${row.query_text}" — ${row.seg_fit ?? '—'}/100`,
    fld('Gender', row.gender, row.gender_score, 30),
    fld('Age', row.age_group, row.age_score, 30),
    fld('Occasion', row.occasion, row.occasion_score, 10),
    fld('Prod Type', row.product_type, row.pt_score, 30),
  ].join('\n');
};

const cpsFitTooltip = (row: ResearchRow): string => {
  const lines = [`CPS FIT for "${row.query_text}" — ${row.cps_fit ?? '—'}/100`];
  if (row.cps_source === 'ads_30d' || row.cps_source === 'ads_12m') {
    lines.push(`Source: real ads CVR (${row.cps_source === 'ads_30d' ? '30d' : '12m'}, ${row.ads_family_orders} orders)`);
  } else if (row.cps_source === 'curve') {
    lines.push(`Source: conversion curve (median price $${row.median_click_price?.toFixed(2) ?? '?'})`);
  } else {
    lines.push('No CVR data and no curve match');
  }
  if (row.effective_cps != null) lines.push(`CPS: ${row.effective_cps.toFixed(1)} clicks/sale`);
  lines.push('', 'Brackets: ≤5→100 | ≤8→85 | ≤12→70 | ≤20→55 | ≤35→35 | ≤50→20 | 50+→10');
  return lines.join('\n');
};
```

  Holiday badge color: replace `isHolidayActive(row.holiday)` with `row.is_holiday_active ?? false`.
  Est. CPS cell: `estCps` becomes `row.effective_cps ?? row.est_cps`; `isRealCps` becomes `row.cps_source === 'ads_30d' || row.cps_source === 'ads_12m'`.
- [ ] **Step 9.4: term-ranks hover** — replace `allFamiliesData` machinery:

```ts
const [termRanks, setTermRanks] = useState<TermRanksMap>({});

// fetch per-family comparison for the current page of rows
useEffect(() => {
  const terms = pagedRowTerms; // memo of displayRows for current page → query_text[], lowercased
  if (terms.length === 0) return;
  const missing = terms.filter(t => !(t in termRanks));
  if (missing.length === 0) return;
  const controller = new AbortController();
  fetch('/api/research/term-ranks', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ terms: missing }), signal: controller.signal,
  }).then(r => r.ok ? r.json() : {})
    .then((data: TermRanksMap) => setTermRanks(prev => ({ ...prev, ...data })))
    .catch(() => {});
  return () => controller.abort();
}, [pagedRowTerms]);

const familyCompareTooltip = (row: ResearchRow): string => {
  const ranks = termRanks[row.query_text.toLowerCase()];
  if (!ranks || ranks.length === 0) return row.query_text;
  const lines = [`"${row.query_text}"`, '', 'Family        │ Rank│  Fit│ Seg │ CPS'];
  for (const fr of [...ranks].sort((a, b) => (b.rank ?? -1) - (a.rank ?? -1))) {
    const hero = fr.parent_name === selectedProduct ? ' ★' : '';
    lines.push(`${(fr.parent_name + hero).padEnd(14)}│${String(fr.rank ?? '—').padStart(4)} │${String(fr.overall_fit ?? '—').padStart(4)} │${String(fr.seg_fit ?? '—').padStart(4)} │${String(fr.cps_fit ?? '—').padStart(4)}`);
  }
  return lines.join('\n');
};
```

  `pagedRowTerms` is `useMemo(() => pagedRows.map(r => r.query_text.toLowerCase()), [displayRows, currentPage])` — note pagination math must move above it or be recomputed in the memo. The search-term `<td title=...>` uses `familyCompareTooltip(row)`.
- [ ] **Step 9.5:** Verify: `cd dashboard-react && npx tsc --noEmit && npm test`. Expected: clean compile, tests pass.
- [ ] **Step 9.6:** Commit: `fix(research-ui): SQL owns scoring — tooltips read explanation columns, batch term-ranks replaces broken all-families compare, single row mapper`

### Task 10: Split the component

**Files:**
- Create: `dashboard-react/src/pages/research/FamilyTabs.tsx` (family selector tabs — current lines ~1003-1047)
- Create: `dashboard-react/src/pages/research/FamilyInfoCard.tsx` (family card + editable segments + per-product table — current lines ~1049-1365)
- Create: `dashboard-react/src/pages/research/ConversionCurveCard.tsx` (current lines ~1494-1576)
- Create: `dashboard-react/src/pages/research/ResultsTable.tsx` (sections split, SortHeader, row rendering, inline segment editor, pagination — current lines ~1681-2231)
- Modify: `dashboard-react/src/pages/ResearchPage.tsx` (becomes orchestrator: state, fetches, doSearch, filters/season UI, summary cards)

Props contracts (define exactly; JSX moves verbatim apart from prop renames):

```ts
// FamilyTabs
{ products: ProductInfo[]; selected: string; onSelect: (name: string) => void }
// FamilyInfoCard
{ familyInfo: FamilyInfo; selectedProduct: string;
  segmentReasoning: Record<string, SegmentReason[]> | null;
  showPerProduct: boolean; onTogglePerProduct: () => void;
  onRefreshFamily: () => Promise<void> }   // owns add/remove/derive fetch calls internally, calls onRefreshFamily after writes
// ConversionCurveCard
{ curve: ConversionCurveRow[]; products: ProductInfo[]; selectedProduct: string }
// ResultsTable
{ rows: ResearchRow[]; sortKey: SortKey; sortDir: SortDir; onSort: (k: SortKey) => void;
  currentPage: number; pageSize: number; onPageChange: (p: number) => void;
  selectedProduct: string; productPrice: number;
  termRanks: TermRanksMap;
  editingTerm: string | null; onEditTerm: (t: string | null) => void;
  onSaveSegments: (queryText: string, segs: Record<string, string | null>) => Promise<void> }
```

- [ ] **Step 10.1:** Create the four components by moving the JSX blocks; `SegmentReason` type (`{value: string; pct: number; orders: number; clicks_per_sale: number | null}`) goes to `research/types.ts`. The tooltip formatters (`segFitTooltip`, `cpsFitTooltip`, `familyCompareTooltip` builder, `ratioColor`) move into `ResultsTable.tsx` (familyCompare takes `termRanks` + `selectedProduct` from props).
- [ ] **Step 10.2:** Reduce `ResearchPage.tsx` to orchestration (~450 lines): state, the three data effects, `doSearch`, season tabs, segment filter dropdowns, summary stat cards, loading/empty states, direct/related toggle, and composition of the four components.
- [ ] **Step 10.3:** Verify `npx tsc --noEmit && npm test` clean; `npm run build` succeeds.
- [ ] **Step 10.4:** Commit: `refactor(research-ui): split ResearchPage into research/ components`

### Task 11: Registration, docs, final verification

**Files:**
- Modify: `config.yaml`
- Modify: `architecture/RESEARCH_PAGE.md` (only if implementation diverged)

- [ ] **Step 11.1:** Register in `config.yaml` (views section: `V_RESEARCH_TERMS`; functions: `FN_EXTRACT_SEGMENTS`; procedures: `SP_REFRESH_RESEARCH_RANKED`; tables: `FACT_RESEARCH_TERMS`, `FACT_RESEARCH_RANKED` with `type: "fact"` and loader reference). Update `V_RESEARCH_RANKED` and `V_SQP_QUERY_WEEKLY` dependency lists (add FN_EXTRACT_SEGMENTS, DE_SEARCH_TERM_SEGMENTS, DE_PRODUCT_TYPE_KEYWORDS, FACT_SEARCH_QUERY).
- [ ] **Step 11.2:** Full verification suite:
  - `/usr/bin/python3 tools/validate_research_ranked.py` → exit 0
  - `python3 -m py_compile data-entry-app/app.py`
  - `cd dashboard-react && npx tsc --noEmit && npm test && npm run build`
- [ ] **Step 11.3:** Commit `config.yaml` **separately** (respecting pre-existing hunks noted in Step 0.4 — if entangled, mention in commit body): `chore(config): register research consolidation objects`
- [ ] **Step 11.4:** Final summary to Ori must include: what was deployed to BigQuery (live), what requires a Cloud Run redeploy (`./deployment/deploy_all.sh flask` and `dashboard`) before the UI changes take effect, and that segment-edit overrides now persist (visible immediately in views, in FACT tables after next refresh).

---

## Self-review notes

- Spec coverage: bugs 1-5 → Tasks 2/3 (overrides + enums), 6.4 (synonyms), 6.3+9.4 (tooltip), 6.1 (docstring); "do differently" items 1-6 → Tasks 2-4 (single owner + taxonomy + materialization), 6 (endpoint collapse), 8-10 (frontend), 7+8.3 (tests). ✓
- Type consistency: `rr_cols` column list in 6.1/6.2 matches `ResearchRow` additions in 8.1 and `V_RESEARCH_RANKED` outputs in 3.1 (gender_score/age_score/occasion_score/pt_score, cps_source, effective_cps, is_holiday_active, family_*). `TermRank` matches `/term-ranks` SELECT. ✓
- Risk: Step 5.3 explicitly avoids overwriting curated DIM_PRODUCT segments. `weeks` window unification (12m→104w in top-terms) is documented in V_RESEARCH_TERMS header. ✓
