# SOP — Research Page (Keyword Research)

> Status: Active · Owner: Ori · Last updated: 2026-06-11
> Governs: `dashboard-react/src/pages/ResearchPage.tsx` + `pages/research/*`,
> `/api/research/*` in `data-entry-app/app.py`, and the BQ research objects below.

## Purpose

The Research page answers: **"Which Amazon search terms should this product family
target next, and at what expected cost per sale?"** It scores every search term
(from SQP market data + our Ads history) against each product family.

## Data Flow

```
FACT_SEARCH_QUERY (SQP weekly)      FACT_AMAZON_ADS (ads daily)
        │                                   │
        ▼                                   │
V_SQP_QUERY_WEEKLY ◄── DE_SEARCH_TERM_SEGMENTS (manual overrides, COALESCE wins)
        │          ◄── FN_EXTRACT_SEGMENTS (regex taxonomy)
        │          ◄── DE_PRODUCT_TYPE_KEYWORDS (product_type lookup)
        ├──────────────────┬────────────────┘
        ▼                  ▼
V_RESEARCH_TERMS    V_RESEARCH_RANKED  ◄── V_CONVERSION_CURVE, DIM_PRODUCT(seg_*),
 (term grain,        (parent × term,        V_DIM_LISTING_CURRENT, DIM_COSTS_HISTORY
  104w window)        all scoring)
        │                  │
        └── SP_REFRESH_RESEARCH_RANKED (nightly, in SP_ORCHESTRATE_DAILY_REFRESH)
                   │
                   ▼
 FACT_RESEARCH_TERMS + FACT_RESEARCH_RANKED   ← endpoints read ONLY these
                   │
                   ▼
 Flask /api/research/* (thin parameterized SELECTs)
                   │
                   ▼
 ResearchPage (formats; never computes scores)
```

## Single-Source-of-Truth Rules (Invariants)

1. **Segment taxonomy** (gender, age_group, occasion, holiday) lives ONLY in
   `FN_EXTRACT_SEGMENTS`. Consumers: `V_SQP_QUERY_WEEKLY`, `V_RESEARCH_RANKED`
   (ads-only terms), `SP_DERIVE_PRODUCT_SEGMENTS`, `/api/research/segment-reasoning`.
   Never copy the regexes inline.
2. **Product-type vocabulary** lives ONLY in `DE_PRODUCT_TYPE_KEYWORDS`
   (values like `Food & Treats`, `Bath & Spa`, `Journal & Diary`). Any product_type
   tagging must use the keyword-lookup join (priority ASC, longest keyword wins).
3. **Scoring** (seg fit, CPS fit, overall fit, purchase rank, rank) lives ONLY in
   `V_RESEARCH_RANKED`. The frontend renders SQL outputs and formats tooltips from
   the explanation columns — it must never re-implement brackets or weights.
4. **Manual overrides** (`DE_SEARCH_TERM_SEGMENTS`, written by the page's ✏️ editor
   via atomic MERGE) win over derived segments via COALESCE in `V_SQP_QUERY_WEEKLY`
   and in `V_RESEARCH_RANKED`'s ads-only branch. They appear in views immediately
   and in FACT tables after the next refresh.
5. Endpoints read `FACT_RESEARCH_TERMS` / `FACT_RESEARCH_RANKED`, never the views
   (except `/related-terms`' co-occurrence seed CTEs which need request-time
   `FACT_SEARCH_QUERY` access).

## Score Semantics

### Seg Fit (0-100)
Per-field points vs family `DIM_PRODUCT.seg_*` (CSV values, merged across ASINs):

| Field | Match | Adjacent | Unknown term value | Family not segmented | Mismatch |
|---|---|---|---|---|---|
| gender | +30 | — | +0 | skipped (NULL) | **cap total at 10** |
| age_group | +30 | +24 (80%) | +0 | skipped | cap 10 |
| occasion | +10 | — | +0 | skipped | cap 10 |
| product_type | +30 | — | +0 (`General` = unknown) | skipped | cap 10 |

Age adjacency: `5-9 (Kid)` ↔ `10-12 (Tween)`; `8-14` ↔ Kid/Tween/Teen (both directions).
Explanation columns: `gender_score`, `age_score`, `occasion_score`, `pt_score`
(-1 encodes mismatch pre-cap).

### CPS Fit (0-100)
`effective_cps` = `1/CVR` from real ads, using the SAME trust rule as the
displayed `ads_cps` (so the two always agree): 30d CVR if `ads_units_30d > 3`
and CVR > 0, **else 12m CVR if > 0** (a zero 30d CVR falls through — it must
not mask a valid 12m CVR), else conversion-curve estimate (`est_cps`, `_ALL`
season). Provenance in `cps_source`: `ads_30d` | `ads_12m` | `curve` | NULL.
Invariant: whenever `ads_cps` is non-null, `cps_source` is `ads_*` and
`effective_cps ≈ ads_cps` (validated by tools/validate_research_ranked.py).
Brackets: ≤5→100, ≤8→85, ≤12→70, ≤20→55, ≤35→35, ≤50→20, else 10.

### Est. CPS (market model, independent of our ads)
`est_cps = est_cps_curve × intent_factor` (changed 2026-06-12; was the raw
curve value, a family-wide constant per bucket — every term in a bucket showed
the same number):
- `est_cps_curve` — family conversion curve (`_ALL` season) at the term's
  price bucket (`product_price / term median purchase price`).
- `intent_factor` — the term's market clicks-per-purchase (SQP, 104w, all
  sellers) ÷ the median market clicks-per-purchase of terms in the SAME
  family × bucket, clamped to [0.5, 2.0]. High-intent terms estimate lower,
  weak terms higher. NULL market data → factor 1 (pure curve).
The **Est. CPS column always shows this model value** — compare it against the
real `ads_cps` side by side (display unification rolled back 2026-06-12 per Ori).
`effective_cps` (scoring) still prefers real ads CVR and falls back to this
improved estimate.

### Overall Fit
- `ads_family_orders > 3` with positive CVR → CPS-fit bracket of the real CPS only.
- Else (no reliable ads data) → **SEG FIT is the base; the price bucket can only
  reduce it** (changed 2026-06-12, was avg(seg_fit, est-CPS bracket)):
  `overall_fit = GREATEST(seg_fit − penalty, 0)` with penalty by conversion-curve
  price bucket (`price_ratio = product_price / median_click_price`):
  | A. Cheaper | B. Sweet spot | C. Pricier | D. Much pricier | E. Way above | no bucket |
  |---|---|---|---|---|---|
  | −0 | −0 | −10 | −20 | −30 | −0 |
  The matched bucket is exposed as `price_bucket` for tooltips.

### Purchase Rank (0-100)
Weekly market purchases buckets: ≥1000→100, ≥500→90, ≥200→80, ≥100→70,
≥50→55, ≥20→40, ≥5→25, >0→10, 0→0, NULL→NULL.

### Rank
`ROUND(avg(overall_fit, purchase_rank))` over non-NULL members.
**Off-season override:** `holiday` set and not in window → rank = 0.

### Holiday Windows (months, inclusive)
Christmas 10-12 · Easter 2-4 · Valentines 1-2 · Halloween 9-10 ·
Mothers Day 3-5 · Fathers Day 5-6 · New Years 11-1 (wraps).
Computed in SQL (`is_holiday_active`), exposed to the UI.

## Endpoint Contract (`/api/research/`)

| Endpoint | Method | Reads | Notes |
|---|---|---|---|
| `top-terms?parent=` | GET | FACT_RESEARCH_TERMS (+RANKED if parent) | all terms with brand purchases, 104w window |
| `related-terms` | POST `{term, parent?, mode, synonyms?}` | FACT_SEARCH_QUERY (seeds) + FACT tables | co-occurrence expansion. **Direct mode = whole-word, plural-tolerant match** (`7`≠`17`, `girl`=`girls`); not substring `LIKE '%word%'`. Related mode keeps synonym `LIKE` expansion. |
| `term-ranks` | POST `{terms[]}` | FACT_RESEARCH_RANKED | per-family hover comparison (≤500 terms) |
| `get-synonyms` | POST `{words[]}` | DE_SYNONYM_CACHE → hardcoded fallback | fallback unlocks Related mode |
| `update-segments` | POST | MERGE into DE_SEARCH_TERM_SEGMENTS | atomic upsert |
| `conversion-curve` | GET (cached) | V_CONVERSION_CURVE | |
| `products` | GET (cached) | V_DIM_LISTING_CURRENT + FACT_AMAZON_ADS | |
| `family-info?family=` | GET | DIM_PRODUCT + costs | NOT cached (param not in cache key) |
| `segment-reasoning?family=` | GET | FACT_AMAZON_ADS via FN_EXTRACT_SEGMENTS | |
| `product-segments` | POST | UPDATE DIM_PRODUCT seg_* | |
| `derive-segments` | POST | CALL SP_DERIVE_PRODUCT_SEGMENTS | overwrites seg_*; force clears first |

⚠️ `cache_result` keys on Python args only — Flask routes read `request`, so the
decorator is ONLY safe on endpoints without query/body params.

`recommendations?parent=` — GET, reads `FACT_RESEARCH_RECOMMENDATIONS`, returns NEW +
ADVERTISED rows grouped by rec_type. See the Recommendations section below.

## Recommendations

Per family, 4 types of net-new keyword recommendations for terms we are **not
advertising as a keyword of that match type**. "Not advertised" is KEYWORD-based and
per match type (changed 2026-06-13, was search-term-clicks): a term is excluded from a
type only if we already run a keyword of that match type on it — i.e.
`exact_kw_cost_7d > 0` (Exact), `phrase_kw_cost_7d > 0` (Phrase), `exact_kw_cost_7d > 0` (Brand), or
`broad_kw_cost_7d > 0` (Broad). These come from `V_RESEARCH_RANKED.keyword_cost_7d`
(`FACT_AMAZON_ADS.targeting` text = term, by `targeting_type`, last 7d; Automatic/ASIN/
Category excluded). A term served only via broad/auto with no dedicated keyword is
therefore still recommendable — that's the "graduate to its own keyword" signal. The
per-search-term `ads_cost_7d` (any keyword that served the query) is shown as a table
column but is NOT the gate. Own brand = `brand = 'Happy Lolli'`.

| Type | match | filter | keyword | ranked by |
|---|---|---|---|---|
| EXACT | EXACT | not-advertised, not own-brand, `rank ≥ 75` | the term | rank desc |
| PHRASE | PHRASE | eligible if seed `rank ≥ 75`, not own-brand, ≥3 words | the term (as phrase) + `coverage_count` (count of **all** searchable terms in `FACT_RESEARCH_TERMS` whose text contains every seed token by **whole-word, plural-tolerant** match — `7`≠`17`, but `girl`=`girls` — the real phrase reach, not the candidate subset). **Stored/displayed `rank` is DEMAND-WEIGHTED**: `Σ(overall_fit × weekly_market_purchases) ÷ Σ(weekly_market_purchases)` over the seed + every covered term (each term's FIT taken for the seed's family), so the rank reflects the whole phrase's reach, not just the seed. | weighted rank desc, tie-break coverage |
| BROAD | BROAD | not-advertised seed gated **like PHRASE** — `market_purchases > 0 AND rank ≥ 75` (NOT fit-only; word_count≥3 omitted since broad is a discovery match); co-occurrence related terms drawn from the same demand+rank-gated pool; cluster `market_purchases` (104w) `> 500` | the seed | cluster sales desc |
| BRAND | PHRASE | not-advertised, own-brand, `overall_fit ≥ 75` (fit not rank — brand terms have low market volume) | the term | market volume desc |

`V_RESEARCH_RECOMMENDATION_CANDIDATES` emits per-family candidates (Broad rows are
seeds only). `SP_REFRESH_RESEARCH_RECOMMENDATIONS` (in `SP_ORCHESTRATE_DAILY_REFRESH`
after `SP_REFRESH_RESEARCH_RANKED`, idempotent daily) computes the Broad co-occurrence
clusters (bounded to fit≥90 seeds via temp tables — avoids the per-statement CPU guard),
the Phrase coverage, dedups against history (never re-recommend a keyword already
NEW/ADVERTISED) and now-advertised terms, and inserts up to `5 − (already NEW this week)`
per family × type into `FACT_RESEARCH_RECOMMENDATIONS` (caps at 5 new/type/family/week,
resets Monday). It also flips prior NEW rows whose term now has 7-day clicks → ADVERTISED.

**Coacher sharing:** the coacher reads `FACT_RESEARCH_RECOMMENDATIONS` directly (same
table the UI reads); no injection into `FACT_ADS_COACH_ACTIONS`. UI: read-only
`RecommendationsCard` below `FamilyInfoCard`. Validation:
`python3 tools/validate_research_recommendations.py`.

## Refresh Cadence

`SP_REFRESH_RESEARCH_RANKED` (CREATE OR REPLACE both FACT tables) runs inside
`SP_ORCHESTRATE_DAILY_REFRESH` right after `SP_LOAD_FACT_SEARCH_QUERY`.
Manual run: `CALL `onyga-482313.OI`.SP_REFRESH_RESEARCH_RANKED();`
Validation: `python3 tools/validate_research_ranked.py` (enum/bounds/consistency invariants).

## Frontend Rules

- One row mapper: `pages/research/mapRow.ts::mapResearchRow` — the only place API
  rows become `ResearchRow`. Counters default 0, optionals null.
- Components: `research/FamilyTabs`, `research/FamilyInfoCard`,
  `research/ConversionCurveCard`, `research/ResultsTable`; `ResearchPage` orchestrates.
- Tooltips format SQL explanation columns; the family-comparison hover uses
  `/term-ranks` (batched per page), not client-side recomputation.

## History

- 2026-06-11: Consolidation — taxonomy UDF, overrides wired (was orphaned),
  Girl/Boy enum drift fixed, materialized FACT tables, endpoint dedup, component
  split. Plan: `docs/superpowers/plans/2026-06-11-research-page-consolidation.md`.
- 2026-06-12: Recommendations layer — 4 net-new keyword recommendation types per
  family, rate-limited 5/type/family/week, shared with the coacher. Spec:
  `docs/superpowers/specs/2026-06-12-research-recommendations-design.md`.
