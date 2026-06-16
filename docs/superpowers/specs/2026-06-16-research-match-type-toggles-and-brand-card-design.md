# Research Page — Match-Type Toggles + Brand-Card Gaps — Design Spec

> Status: Approved 2026-06-16 · Owner: Ori
> Two scoped changes to the Research page:
> 1. The Direct/Related search toggle becomes a 3-way **Direct / Phrase / Broad**
>    toggle that simulates Amazon match-type reach (the old "Related" synonym mode is
>    removed and folded into Broad).
> 2. The **Brand** recommendation card shows only keywords we are *not* advertising on.

Governs: `dashboard-react/src/pages/ResearchPage.tsx`, `pages/research/RecommendationsCard.tsx`,
`/api/research/related-terms` in `data-entry-app/app.py`, and `architecture/RESEARCH_PAGE.md`.
No new BigQuery objects → no `config.yaml` change.

## Goal

- Let the analyst preview, for a searched term, the set of market search terms an Amazon
  **exact / phrase / broad** keyword would capture, by toggling between three modes above the
  results table. Synonym expansion (previously its own "Related" toggle) becomes part of Broad.
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

## Part 2 — Direct / Phrase / Broad toggle

### Mode semantics
Seed = the searched term's significant tokens (stop-words removed, per `_RESEARCH_STOP_WORDS`).
Direct/Phrase predicates run against `query_text`, **whole-word and plural-tolerant**
(`girl`=`girls`, and word boundaries so `7`≠`17`).

| Mode | Matches | Example for seed `girl gift` |
|---|---|---|
| **Direct** (exact) | the whole term + plural variants only | `girl gift`, `girl gifts` |
| **Phrase** | every seed token present — **order may change, extra words allowed** | `gift for a girl`, `cute girl birthday gifts` |
| **Broad** | Phrase reach **+ synonym expansion** (today's "Related" logic, unchanged) | `present for a daughter` |

The old **Related** toggle is **removed**; its synonym expansion is exactly what Broad now does.
(This supersedes the earlier "keep Related as a 4th toggle" choice — Ori reversed it: Broad
absorbs synonyms, so we're back to 3 toggles, matching the original request.)

### Naming-drift note (resolved here)
`architecture/RESEARCH_PAGE.md` already documents *"Direct mode = whole-word, plural-tolerant
match; not substring `LIKE '%word%'`"* — but the live code uses substring `LIKE` (the `7`/`17`
false-match bug). That documented "whole-word, any-order" behavior is exactly the new **Phrase**
mode. Moving to regex:
- fixes the substring bug,
- makes the new **Direct** genuinely stricter (exact term + plurals),
- aligns the SOP with the code.

### Default mode
Post-search default = **Phrase** (today's default returns all-words text matches, which now
maps to Phrase; new Direct returns ~1 row and Broad needs the background synonym fetch, so
neither can be the default). Toggle order: `Direct │ Phrase │ Broad`, with **Phrase
pre-selected** after a search.

**Broad is always clickable** (not gated the way Related was). If the background synonym fetch
hasn't completed, Broad runs the co-occurrence net without synonyms and **re-runs when they
arrive**. The synonym count badge + tooltip (previously on Related) move onto Broad.

### Result-gathering approach (Fork A — chosen)
Reuse the existing co-occurrence pipeline in `/api/research/related-terms`; only swap the
text-match predicate per mode for Direct/Phrase. Broad keeps today's "Related" path verbatim.
This preserves the `asin_overlap` / `overlap_pct` relevance stats and is the smallest change.
(Fork B — pure text-match over all `FACT_RESEARCH_TERMS` with no ASIN gate — was rejected:
bigger refactor, loses the overlap stat, and for a real seed the ASIN net is wide enough that
A ≈ B in practice.)

### Backend — `/api/research/related-terms` (`app.py`)
- Accept `mode ∈ {direct, phrase, broad}` (was `{direct, related}`).
- **Broad = today's `related` branch, unchanged**: per-word synonym OR-groups (`_SYNONYM_MAP`
  + frontend Gemini synonyms), substring `LIKE`, **no** final `match_filter` (returns the full
  co-occurrence net; `match_type` splits text-matching `direct` vs co-occurrence-only `related`
  rows). Just rename the trigger from `mode == 'related'` to `mode == 'broad'`.
- **Direct / Phrase** use a new pure helper:
  ```
  _research_match_predicate(words, mode, alias) -> (sql_predicate, [(param_name, value), ...])
  ```
  builds the per-mode regex predicate for a given table alias (`sq` for the seed CTE, `t` for
  the term table). Pure string/param assembly → unit-testable in isolation.
  - **direct:** `REGEXP_CONTAINS(LOWER(col), r'(?i)^\s*tok1s?\s+tok2s?\s*$')` (anchored whole-string).
  - **phrase:** one `REGEXP_CONTAINS(LOWER(col), r'(?i)\btokNs?\b')` per token, AND-ed
    (every token present, any order, extra words allowed).
  - Plural tolerance = optional trailing `s` per token (covers the documented `girl`/`girls`
    case); `es`/irregular plurals are out of scope, matching today's tolerance.
- Use the predicate for both `seed_asins` (which queries seed the ASIN net) and the final
  `match_filter` for direct/phrase. For these modes every returned row passes the predicate, so
  `match_type` resolves to `'direct'` (no new enum value — `ResearchRow.match_type` and the
  mapper stay unchanged).

### Frontend — `ResearchPage.tsx`
- `searchMode` state type → `'direct' | 'phrase' | 'broad'`.
- Initial search (`doSearch`) sets mode `'phrase'` and runs the first query with `mode: 'phrase'`
  (the background synonym fetch is unchanged — it still kicks off so Broad is ready).
- Toggle block (currently 2 buttons) renders 3 buttons in order Direct / Phrase / Broad:
  - Direct / Phrase: always enabled; clicking sets the mode and re-fetches.
  - Broad: always enabled; carries the synonym count badge + tooltip; uses whatever synonyms
    are loaded.
- Generalize the existing "re-search on mode switch" effect so switching to **phrase / broad**
  re-fetches with the new `mode` (passing `synonyms` only for broad); also re-run when in broad
  mode and `synonyms` become ready.
- `clusterSyn` passed to `ResultsTable` becomes Broad-only
  (`searchMode === 'broad' && synonymsReady ? synonyms : undefined`).
- Summary stat tiles: the two "Direct Matches / Related Terms" tiles stay (in Broad mode the
  `match_type` split still distinguishes text-matching vs co-occurrence-only); relabel to read
  naturally for the active mode (cosmetic).

## Files

- `dashboard-react/src/pages/research/RecommendationsCard.tsx` — Brand-section ADVERTISED filter.
- `dashboard-react/src/pages/ResearchPage.tsx` — 3-mode `searchMode`, 3 toggle buttons, default
  `phrase`, Broad-carries-synonyms, generalized re-search effect, stat-tile labels.
- `data-entry-app/app.py` — `_research_match_predicate` helper (direct/phrase) + rename
  `related`→`broad`; accept `mode ∈ {direct, phrase, broad}`.
- `data-entry-app/` test — Python unit test for `_research_match_predicate` (direct/phrase
  predicates + params; plural tolerance; `7`≠`17`).
- `architecture/RESEARCH_PAGE.md` — endpoint contract: 3 modes + definitions, substring→regex
  note, Related removal.

## Testing / verification

- Unit: Python test of `_research_match_predicate` for direct + phrase (predicate text + params),
  including plural tolerance and the `7`/`17` boundary.
- Manual (preview): search a multi-word term, cycle Direct → Phrase → Broad and confirm result
  counts widen as expected (exact → all-words-any-order → +synonyms); confirm the Brand card no
  longer shows ✓ live rows while Exact/Phrase/Broad recommendation sections still do.

## Out of scope

- BRAND gate column fix; hiding advertised on the other three cards (Part 1 out-of-scope).
- New BigQuery objects, new `match_type` enum values, `es`/irregular plural handling.
- Changing Broad's synonym source or the co-occurrence ASIN logic (Broad = today's Related path).
