# DecisionCard: Research Rank + Source Keyword Display — Design

**Date:** 2026-06-16
**Status:** Approved (brainstorming) — pending spec review
**Scope:** Display-only. No change to coach decision logic, thresholds, or the PROMOTE_TO_EXACT gate.

## Goal

Surface two existing-but-unshown signals on the search-term **DecisionCards** (Actions page) so the operator can see, at a glance:

1. **Research rank** — the 0–100 fit+purchase `rank` from `FACT_RESEARCH_RANKED`, i.e. *how well this term fits the family by segment + proven purchases*. Today the engine's PROMOTE logic ignores fit (see `feedback-promote-requires-research-rank`); showing it makes promote-questionable terms visible even before any gating change.
2. **Source keyword** — the single **top-spend targeting** the term matched through in the last 4 weeks, with its match type (e.g. `via BROAD: gifts for girls`), so the operator knows *where the term's spend comes from*.

This is the "display #2/#3" item; the promote-gate wiring is explicitly **out of scope** here.

## Non-Goals

- No PROMOTE_TO_EXACT gating on rank (separate future work).
- No new threshold rows; no change to `V_ADS_COACH.sql` decision branches.
- No change to card layout beyond adding one badge + one sub-line.

## Architecture (chosen approach)

Add both fields as columns on `V_ADS_COACH_DECISION` (the canonical per-term evidence view), then flow through the established path: **view → rebuild `T_ADS_COACH_DECISION` → `AdsCoachDecision` cube → `CoachDecisionRow` type + `useCubeData` mapping → `DecisionCard` render.** This keeps evidence/logic in engine SQL and the card purely presentational, consistent with `feedback-coacher-rules-in-engine`.

Rejected: computing `source_keyword` dashboard-side (splits logic across layers); a separate display view/cube (extra object + join for two columns).

## Data Layer — `scripts/bigquery/views/V_ADS_COACH_DECISION.sql`

Grain is unchanged: one row per `LOWER(search_term)`. Both additions are **non-fanout LEFT JOINs**, so row count must be identical before/after.

### `research_rank`
- Source: `FACT_RESEARCH_RANKED` (materialized; columns `parent_name`, `query_text`, `rank` ∈ [0,100]).
- Join: `LEFT JOIN` on `parent_name = <decision>.parent_name` **and** `query_text = <decision>.search_term` (lowercase both sides to be safe).
- Select: `ROUND(rr.rank)` AS `research_rank`. Null when the term has no research match.
- `FACT_RESEARCH_RANKED` is unique per (`parent_name`, `query_text`); add a dedupe-to-one safeguard (e.g. `QUALIFY ROW_NUMBER() … = 1` in a small subquery) so any accidental dupe can't fan out the decision grain.

### `source_keyword` + `source_keyword_match_type`
New CTE mirroring the existing 4w window (`fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)`):

```sql
src_kw_4w AS (
  SELECT
    LOWER(fa.search_term) AS search_term,
    fa.targeting          AS source_keyword,
    ANY_VALUE(fa.targeting_type) AS source_keyword_match_type,
    SUM(fa.Ads_cost) AS spend
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.targeting   IS NOT NULL AND fa.targeting   != ''
    AND LOWER(fa.targeting) != LOWER(fa.search_term)   -- suppress exact-self
  GROUP BY 1, 2
  QUALIFY ROW_NUMBER() OVER (PARTITION BY LOWER(fa.search_term) ORDER BY SUM(fa.Ads_cost) DESC) = 1
)
```
- `LEFT JOIN src_kw_4w USING (search_term)`. Null `source_keyword` ⇒ the term only ran as its own exact targeting (nothing useful to show).

### Validation (no pytest — `_TMP` + sanity, the `V_ADS_COACH` pattern)
1. Deploy to `V_ADS_COACH_DECISION_TMP`, confirm it compiles.
2. **Row-count parity:** `COUNT(*)` of `_TMP` == `COUNT(*)` of live `V_ADS_COACH_DECISION` (proves no fanout).
3. `research_rank` ∈ [0,100] or null; `COUNTIF(source_keyword = search_term) = 0`; spot-check a few rows have sensible rank + source.
4. Drop `_TMP`, deploy real view, rebuild `T_ADS_COACH_DECISION` (`CREATE OR REPLACE TABLE … AS SELECT * FROM V_ADS_COACH_DECISION`; the line already exists in `SP_REFRESH_CUBE_TABLES`).

## Cube — `cube/schema/AdsCoachDecision.js`

Add three dimensions:
- `researchRank` → `research_rank` (`number`)
- `sourceKeyword` → `source_keyword` (`string`)
- `sourceKeywordMatchType` → `source_keyword_match_type` (`string`)

## Type + Mapping

- `dashboard-react/src/types.ts` → `CoachDecisionRow`: add
  `research_rank: number | null`, `source_keyword: string | null`, `source_keyword_match_type: string | null`.
- `dashboard-react/src/hooks/useCubeData.ts` → `loadCoachDecisionsFromCube`: add the three dimensions to the query and map them (`nul(...)` for rank, string-or-null for the two text fields).

## Display — `dashboard-react/src/components/Actions/DecisionCard.tsx`

- **Fit badge** near the title: `Fit {research_rank}`. Color via a pure, exported helper `fitBadgeClass(rank: number | null): string`:
  - `>= 75` → green (promote-worthy)
  - `40–74` → amber
  - `< 40` → faint/muted
  - `null` → badge hidden entirely
- **Source sub-line** under the evidence grid: `via {MATCH_TYPE}: {source_keyword}` (match type upper-cased). Hidden when `source_keyword` is null.
- No other layout change. Both render on the search-term DecisionCards (clear-cases + needs-judgment sections).

## Testing

- SQL: the `_TMP` sanity queries above (parity, rank bounds, source ≠ term).
- TS: `fitBadgeClass` is a pure helper → Vitest covering the four bands (≥75, mid, <40, null). No DOM render test required.
- Typecheck: `npx tsc --noEmit` clean.

## File List

- Modify `scripts/bigquery/views/V_ADS_COACH_DECISION.sql` (research-rank join + `src_kw_4w` CTE + 3 select cols)
- Rebuild `T_ADS_COACH_DECISION` (one-time `CREATE OR REPLACE TABLE`; no file change — line already in `SP_REFRESH_CUBE_TABLES`)
- Modify `cube/schema/AdsCoachDecision.js`
- Modify `dashboard-react/src/types.ts`
- Modify `dashboard-react/src/hooks/useCubeData.ts`
- Modify `dashboard-react/src/components/Actions/DecisionCard.tsx` (+ exported `fitBadgeClass`)
- Add `DecisionCard` (or `fitBadgeClass`) Vitest
- Modify `architecture/ADS_COACH_DECISION_MATRIX.md` (note the two new display fields + maintenance-log row)
- Optionally refresh the `V_ADS_COACH_DECISION` description in `config.yaml` (no new object to register)

## Success Criteria

- Each search-term DecisionCard shows a `Fit NN` badge (color-coded) when research data exists, and a `via {MATCH_TYPE}: {term}` line when the term ran through a higher-spend targeting.
- Decision-view row count and all existing decision/evidence values are unchanged (additions are pure LEFT JOINs).
- `tsc` clean; `fitBadgeClass` tests pass.
