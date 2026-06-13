# Research Recommendations — Design Spec

> Status: Approved 2026-06-12 · Owner: Ori
> Feature: 4 types of net-new keyword recommendations per product family on the
> Research page, shared with the coacher, rate-limited to 5 new per type/family/week.

## Goal

For each product family, surface keyword opportunities we are **not currently
advertising** (0 ads clicks in the last 7 days), classified into 4 campaign types,
capped at 5 new per type per family per week, persisted so the coacher can act on them.

## Definitions (locked)

- **Not advertised** = the term has **0 ads clicks in the last 7 days** for that
  family's ASINs (`FACT_AMAZON_ADS`, `date >= CURRENT_DATE()-7`, joined to family via
  `ASIN_BY_CAMPAIGN_NAME → DIM_PRODUCT.parent_name`). The coacher decides whether each
  is brand-new or an existing keyword needing a bid raise.
- **Own brand** = `brand = 'Happy Lolli'` in `FACT_RESEARCH_RANKED`.
- **rank** = `FACT_RESEARCH_RANKED.rank` (0-100). **fit** = `overall_fit` (0-100).
- **Weekly cap** = 5 **new** recommendations per type, per family, per ISO week
  (`DATE_TRUNC(CURRENT_DATE(), WEEK(MONDAY))`).

## The four types (per family)

| Type | match_type | Candidate filter | Keyword | Ranked by |
|---|---|---|---|---|
| **EXACT** | EXACT | not-advertised, `brand != 'Happy Lolli'` (or NULL), `rank >= 75` | the term | rank desc |
| **PHRASE** | PHRASE | not-advertised, `brand != 'Happy Lolli'`, `rank >= 75`, word-count ≥ 3 | the term (used as a phrase match) | rank desc, tie-break coverage desc |
| **BROAD** | BROAD | not-advertised seed `overall_fit >= 90`, whose co-occurrence related terms also have `overall_fit >= 90`, and cluster's summed `market_purchases` (104w, all sellers) `> 500` | the seed term | cluster sales desc |
| **BRAND** | PHRASE | not-advertised, `brand = 'Happy Lolli'` (no rank/fit bar) | the term | market volume desc |

Judgment calls (approved): **Phrase keyword = the seed term itself** (≥3 words used
as a phrase match; `coverage_count` = how many other not-advertised family terms its
significant words cover, shown for context). **Brand defense uses PHRASE match**
(per `README_EXPERIMENTS.md` brand-defense convention).

### PHRASE coverage
For a seed term (rank≥75, ≥3 words), `coverage_count` = number of OTHER not-advertised
terms in the same family whose token set contains all the seed's significant tokens
(stop-words removed). Surfaces the phrase's reach; used only as a tie-breaker + display.

### BROAD co-occurrence (cost-bounded)
Computed only over `overall_fit >= 90` not-advertised seeds (small set), inside the
weekly SP (not a live view) — we hit BigQuery's per-statement CPU guard earlier with
unbounded term cross-joins, so this stays narrow. Related = ASIN co-occurrence from
`FACT_SEARCH_QUERY` (same seed-ASINs → related queries), restricted to also-`fit>=90`
terms in the same family. `cluster_sales` = SUM of `market_purchases` (FACT_RESEARCH_TERMS,
104w) across {seed + qualifying related}; qualifies if `> 500`. `cluster_size` stored.

## Persistence + rate limit

`FACT_RESEARCH_RECOMMENDATIONS` (the weekly memory):

| column | type | note |
|---|---|---|
| rec_id | STRING | hash(parent_name, rec_type, keyword) — stable identity |
| week_start | DATE | ISO Monday of the week it was first emitted |
| parent_name | STRING | family |
| rec_type | STRING | EXACT / PHRASE / BROAD / BRAND |
| match_type | STRING | EXACT / PHRASE / BROAD |
| keyword | STRING | suggested keyword (seed term) |
| query_text | STRING | source term (== keyword today) |
| rank | FLOAT64 | from ranked |
| overall_fit | FLOAT64 | from ranked |
| market_sales | INT64 | cluster sales (BROAD) or term market purchases |
| market_volume | INT64 | weekly_market_impressions (for BRAND ordering / display) |
| coverage_count | INT64 | PHRASE reach (NULL for others) |
| cluster_size | INT64 | BROAD cluster size (NULL for others) |
| status | STRING | NEW / ADVERTISED / DISMISSED |
| created_at | TIMESTAMP | insert time |

`SP_REFRESH_RESEARCH_RECOMMENDATIONS()` (idempotent, hooked into
`SP_ORCHESTRATE_DAILY_REFRESH` after `SP_REFRESH_RESEARCH_RANKED`):
1. `week_start = DATE_TRUNC(CURRENT_DATE(), WEEK(MONDAY))`.
2. Build candidate pool per (family × type) from the rules above, **excluding** any
   `keyword` already present for that family+type with status in (NEW, ADVERTISED)
   — never re-recommend — and excluding now-advertised terms.
3. Per (family × type): `n_existing = count(status=NEW for this week)`; insert up to
   `5 - n_existing` top candidates ordered by the type's metric. → tops up to exactly
   5 new/week, resets each Monday.
4. Flip prior `status=NEW` rows whose term now has 7-day clicks → `status=ADVERTISED`
   (the coacher picked it up / we started bidding).

Daily runs are safe: step 2's "never re-recommend" + step 3's per-week cap make it a
monotone top-up. No DELETEs of history.

## Coacher sharing

The coacher reads `FACT_RESEARCH_RECOMMENDATIONS` directly (same table the UI reads).
It surfaces NEW rows as "new keyword" suggestions to review/queue; it does **not**
auto-create campaigns, and we do **not** inject into `FACT_ADS_COACH_ACTIONS`.

## API + UI

- `GET /api/research/recommendations?parent=<family>` → NEW + recent rows for that
  family, grouped by rec_type. Reads `FACT_RESEARCH_RECOMMENDATIONS`.
- New read-only `RecommendationsCard` on the Research page (below `FamilyInfoCard`):
  4 mini-sections (Exact / Phrase / Broad / Brand), each up to 5 chips showing the
  keyword + match-type badge + its key metric (rank, coverage, cluster sales, or
  market volume). Read-only; the coacher acts on them.

## Files

- `scripts/bigquery/views/V_RESEARCH_RECOMMENDATION_CANDIDATES.sql` — candidate logic (EXACT/PHRASE/BRAND; BROAD seeds)
- `scripts/bigquery/tables/DE/FACT_RESEARCH_RECOMMENDATIONS.sql` — DDL (FACT-typed memory table)
- `scripts/bigquery/procedures/SP_REFRESH_RESEARCH_RECOMMENDATIONS.sql` — weekly top-up + dedup + status + BROAD cluster compute
- `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql` — add CALL hook
- `data-entry-app/app.py` — `GET /api/research/recommendations`
- `dashboard-react/src/pages/research/RecommendationsCard.tsx` + `types.ts` + `ResearchPage.tsx` wiring
- `config.yaml` + `architecture/RESEARCH_PAGE.md`
- `tools/validate_research_recommendations.py`

## Out of scope

- Coacher auto-creating campaigns from recommendations.
- Editing/dismissing recommendations from the Research UI (read-only for now; status
  transitions are SP-driven). A future `POST .../dismiss` can set status=DISMISSED.
- Multi-word phrase EXTRACTION beyond the seed term (Phrase = seed-as-phrase for now).
