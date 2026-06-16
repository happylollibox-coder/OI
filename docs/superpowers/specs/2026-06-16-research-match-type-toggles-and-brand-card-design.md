# Research Page — Match-Type Toggles + Brand-Card Gaps — Design Spec

> Status: Approved 2026-06-16 · Owner: Ori
> Two scoped changes to the Research page:
> 1. The Direct/Related search toggle becomes a 4-way **Direct / Phrase / Broad / Related**
>    toggle that simulates Amazon match-type reach.
> 2. The **Brand** recommendation card shows only keywords we are *not* advertising on.

Governs: `dashboard-react/src/pages/ResearchPage.tsx`, `pages/research/RecommendationsCard.tsx`,
`/api/research/related-terms` in `data-entry-app/app.py`, and `architecture/RESEARCH_PAGE.md`.
No new BigQuery objects → no `config.yaml` change.

## Goal

- Let the analyst preview, for a searched term, the set of market search terms an Amazon
  **exact / phrase / broad** keyword would capture — plus the existing synonym ("Related")
  expansion — by toggling between four modes above the results table.
- Make the Brand defense card actionable: show only the own-brand terms we have **no
  keyword coverage on yet**, not the ones already running.

## Part 1 — Brand card hides advertised terms

### Current behavior
`GET /api/research/recommendations` returns rows with `status IN ('NEW','ADVERTISED')`
for all four rec types. `RecommendationsCard` renders `ADVERTISED` rows greyed (`opacity-50`)
with a "✓ live" badge. So the Brand card mixes already-running brand terms in with the gaps.

### Change (frontend only)
In `RecommendationsCard.tsx`, for the **BRAND** section only:
- Render only rows with `status !== 'ADVERTISED'`.
- The section count badge and the "No new recommendations" empty-state use that filtered list.

Exact / Phrase / Broad sections are unchanged — they keep showing ✓ live rows greyed.
No backend change; the endpoint keeps returning NEW+ADVERTISED (the coacher still reads both).

### Out of scope (explicitly not done)
- Fixing the BRAND not-advertised **gate** (it keys on `exact_kw_cost_7d` though brand is
  recommended as a PHRASE keyword — a possible leak). Ori chose the display-only hide.
- Applying the hide to the other three cards.

## Part 2 — Direct / Phrase / Broad / Related toggle

### Mode semantics
Predicates run against `query_text`, **whole-word and plural-tolerant** (`girl`=`girls`,
and word boundaries so `7`≠`17`). Seed = the searched term's significant tokens
(stop-words removed, per `_RESEARCH_STOP_WORDS`).

| Mode | Matches | Example for seed `girl gift` |
|---|---|---|
| **Direct** (exact) | the whole term + plural variants only | `girl gift`, `girl gifts` |
| **Phrase** | seed tokens appear contiguous, in order | `best girl gift ideas` |
| **Broad** | every seed token appears, any order | `gift for a girl` |
| **Related** | Broad reach + synonym expansion (**unchanged** from today) | `present for a daughter` |

### Naming-drift note (resolved here)
`architecture/RESEARCH_PAGE.md` already documents *"Direct mode = whole-word, plural-tolerant
match; not substring `LIKE '%word%'`"* — but the live code uses substring `LIKE` (the `7`/`17`
false-match bug). That documented behavior is exactly the new **Broad** mode. Moving to regex:
- fixes the substring bug,
- makes the new **Direct** genuinely stricter (exact term + plurals),
- aligns the SOP with the code.

### Default mode
Post-search default = **Broad** (today's default is the widest text match; new Direct returns
~1 row so it cannot be the default). Toggle order: `Direct │ Phrase │ Broad │ Related`,
with **Broad pre-selected** after a search. Related stays opt-in (disabled until synonyms load).

### Result-gathering approach (Fork A — chosen)
Reuse the existing co-occurrence pipeline in `/api/research/related-terms`; only swap the
text-match predicate per mode. This preserves the `asin_overlap` / `overlap_pct` relevance
stats and is the smallest change. (Fork B — pure text-match over all `FACT_RESEARCH_TERMS`
with no ASIN gate — was rejected: bigger refactor, loses the overlap stat, and for a real
seed the ASIN net is wide enough that A ≈ B in practice.)

### Backend — `/api/research/related-terms` (`app.py`)
- Accept `mode ∈ {direct, phrase, broad, related}` (was `{direct, related}`); default `direct`
  is still valid as an API default, but the UI sends `broad` first.
- Extract a pure helper:
  ```
  _research_match_predicate(words, mode, alias) -> (sql_predicate, [(param_name, value), ...])
  ```
  builds the per-mode predicate for a given table alias (`sq` for the seed CTE, `t` for the
  term table). Pure string/param assembly → unit-testable in isolation.
  - **direct:** `REGEXP_CONTAINS(LOWER(col), r'(?i)^\s*tok1s?\s+tok2s?\s*$')` (anchored whole-string).
  - **phrase:** `REGEXP_CONTAINS(LOWER(col), r'(?i)\btok1s?\s+tok2s?\b')` (contiguous, in order).
  - **broad:** one `REGEXP_CONTAINS(LOWER(col), r'(?i)\btokNs?\b')` per token, AND-ed (any order).
  - **related:** unchanged — keep the existing synonym OR-expansion (`_SYNONYM_MAP` + frontend
    Gemini synonyms), substring `LIKE`, and no final `match_filter`.
  - Plural tolerance uses an optional trailing `s` per token (covers the documented
    `girl`/`girls` case); `es`/irregular plurals are out of scope, matching today's tolerance.
- Use the predicate for both `seed_asins` (which queries seed the ASIN net) and the final
  `match_filter` for direct/phrase/broad. Related keeps its current shape (no filter).
- `match_type` column: for direct/phrase/broad every returned row passes the predicate, so it
  resolves to `'direct'`; Related still splits direct vs related. (No new enum value — keeps
  `ResearchRow.match_type` and the mapper unchanged.)

### Frontend — `ResearchPage.tsx`
- `searchMode` state type → `'direct' | 'phrase' | 'broad' | 'related'`.
- Initial search (`doSearch`) sets mode `'broad'` and runs the first query with `mode: 'broad'`.
- Toggle block (currently 2 buttons) renders 4 buttons in order Direct / Phrase / Broad / Related:
  - Direct / Phrase / Broad: always enabled; clicking sets the mode.
  - Related: keeps current gating (disabled until `synonymsReady`), synonym tooltip, count badge.
- Generalize the existing "re-search when switching to related" effect so switching to
  **phrase / broad / related** re-fetches with the new `mode` (passing `synonyms` only for
  related). Direct is also a re-fetch.
- `clusterSyn` passed to `ResultsTable` stays Related-only
  (`searchMode === 'related' && synonymsReady ? synonyms : undefined`).
- Summary stat cards: the two "Direct Matches / Related Terms" tiles get relabeled to reflect
  the active mode (cosmetic; counts still derive from `match_type`).

## Files

- `dashboard-react/src/pages/research/RecommendationsCard.tsx` — Brand-section ADVERTISED filter.
- `dashboard-react/src/pages/ResearchPage.tsx` — 4-mode `searchMode`, 4 toggle buttons,
  default `broad`, generalized re-search effect, stat-tile labels.
- `data-entry-app/app.py` — `_research_match_predicate` helper + 4-mode `related-terms`.
- `data-entry-app/` test — Python unit test for `_research_match_predicate` (direct/phrase/broad
  predicates + params; plural tolerance; `7`≠`17`).
- `architecture/RESEARCH_PAGE.md` — endpoint contract: 4 modes + definitions, substring→regex note.

## Testing / verification

- Unit: Python test of `_research_match_predicate` for each mode (predicate text + params),
  including plural tolerance and the `7`/`17` boundary.
- Manual (preview): search a multi-word term, cycle Direct → Phrase → Broad → Related and
  confirm result counts narrow/widen as expected; confirm the Brand card no longer shows
  ✓ live rows while Exact/Phrase/Broad still do.

## Out of scope

- BRAND gate column fix; hiding advertised on the other three cards (Part 1 out-of-scope).
- New BigQuery objects, new match_type enum values, `es`/irregular plural handling.
- Changing Related's synonym source or the co-occurrence ASIN logic.
