# Research Page — Match-Type Toggles + Brand-Card Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Research page's Direct/Related search toggle with a 3-way Direct/Phrase/Broad match-type-reach toggle, and make the Brand recommendation card show only own-brand terms we are not yet advertising on.

**Architecture:** A new pure Python module (`data-entry-app/research_match.py`) builds whole-word/plural-tolerant REGEXP predicates for Direct (exact term + plurals) and Phrase (all words, any order). The `/api/research/related-terms` endpoint uses it for those modes and keeps today's synonym-expansion path verbatim under the new name "Broad". The frontend swaps two ad-hoc fetch effects for one unified mode-driven effect and renders three toggle buttons. The Brand card filters out `ADVERTISED` rows client-side. No new BigQuery objects.

**Tech Stack:** Python 3 (Flask, BigQuery, stdlib `re`/`unittest`); React 19 + TypeScript + Vite + Tailwind; `bq` CLI for SQL smoke checks.

**Spec:** `docs/superpowers/specs/2026-06-16-research-match-type-toggles-and-brand-card-design.md`

**Environment notes:**
- Node (nvm): prefix npm/npx with `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH"`.
- Python unit tests need only stdlib `re`; run with system `python3`.
- `bq` CLI uses ADC; project `onyga-482313`.
- Branch: `feat/research-match-type-toggles` (already created off the working HEAD).

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `data-entry-app/research_match.py` | Pure REGEXP predicate builder for direct/phrase modes | Create |
| `data-entry-app/test_research_match.py` | Unit tests for the builder | Create |
| `data-entry-app/app.py` | `/api/research/related-terms`: accept direct/phrase/broad; rename related→broad | Modify |
| `dashboard-react/src/pages/research/RecommendationsCard.tsx` | Hide ADVERTISED rows in the Brand section | Modify |
| `dashboard-react/src/pages/ResearchPage.tsx` | 3-mode toggle, default Phrase, unified re-search effect | Modify |
| `architecture/RESEARCH_PAGE.md` | Endpoint contract: 3 modes + definitions, substring→regex note | Modify |

---

## Task 1: Pure match-predicate module (TDD)

**Files:**
- Create: `data-entry-app/research_match.py`
- Test: `data-entry-app/test_research_match.py`

- [ ] **Step 1: Write the failing test**

Create `data-entry-app/test_research_match.py`:

```python
import unittest
from research_match import research_match_predicate


class DirectMode(unittest.TestCase):
    def test_single_token_anchored_plural(self):
        params, names = research_match_predicate(['girl'], 'direct')
        self.assertEqual(names, ['rx_0'])
        self.assertEqual(params, [('rx_0', r'^\s*girls?\s*$')])

    def test_multi_token_in_order(self):
        params, names = research_match_predicate(['girl', 'gift'], 'direct')
        self.assertEqual(names, ['rx_0'])
        self.assertEqual(params, [('rx_0', r'^\s*girls?\s+gifts?\s*$')])


class PhraseMode(unittest.TestCase):
    def test_one_regex_per_token_any_order(self):
        params, names = research_match_predicate(['girl', 'gift'], 'phrase')
        self.assertEqual(names, ['rx_0', 'rx_1'])
        self.assertEqual(params, [('rx_0', r'\bgirls?\b'), ('rx_1', r'\bgifts?\b')])

    def test_number_token_keeps_word_boundary(self):
        # \b means the BQ-side regex won't match 7 inside 17 (RE2 semantics checked in Task 2)
        params, names = research_match_predicate(['7'], 'phrase')
        self.assertEqual(params, [('rx_0', r'\b7s?\b')])

    def test_tokens_lowercased(self):
        params, _ = research_match_predicate(['Girl'], 'phrase')
        self.assertEqual(params, [('rx_0', r'\bgirls?\b')])


if __name__ == '__main__':
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/ori/Develop/OI/data-entry-app && python3 -m unittest test_research_match -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'research_match'`.

- [ ] **Step 3: Write the minimal implementation**

Create `data-entry-app/research_match.py`:

```python
"""Pure regex-predicate builder for the Research page's Direct / Phrase search modes.

No Flask/BigQuery imports — safe to unit-test in isolation. Broad mode (synonym
expansion) is handled inline in app.py, not here.
"""
import re


def _token_regex(token):
    """Escaped, lowercased token with an optional trailing 's' for plural tolerance."""
    return re.escape(token.lower()) + 's?'


def research_match_predicate(words, mode):
    """Build REGEXP_CONTAINS parameters for a search mode.

    Args:
        words: significant search tokens (stop-words already removed), e.g. ['girl', 'gift'].
        mode:  'direct' -> exact term + plurals, whole string (one anchored regex).
               anything else -> 'phrase': every token present, any order, extra words
               allowed (one whole-word regex per token, AND-ed by the caller).

    Returns:
        (param_map, rx_names):
          param_map: list of (param_name, regex_string) for ScalarQueryParameter(STRING).
          rx_names:  param names the caller ANDs as REGEXP_CONTAINS(LOWER(col), @name).

    Whole-word + plural-tolerant: '\\b' boundaries mean '7' != '17'; 'girls?' matches
    'girl' and 'girls'.
    """
    toks = [w for w in words if w]
    if mode == 'direct':
        body = r'\s+'.join(_token_regex(t) for t in toks)
        return [('rx_0', r'^\s*' + body + r'\s*$')], ['rx_0']
    param_map = []
    rx_names = []
    for i, t in enumerate(toks):
        name = f'rx_{i}'
        param_map.append((name, r'\b' + _token_regex(t) + r'\b'))
        rx_names.append(name)
    return param_map, rx_names
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/ori/Develop/OI/data-entry-app && python3 -m unittest test_research_match -v`
Expected: PASS — 5 tests OK.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add data-entry-app/research_match.py data-entry-app/test_research_match.py
git commit -m "feat(research): pure regex predicate builder for direct/phrase modes

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Wire direct/phrase/broad into `/api/research/related-terms`

**Files:**
- Modify: `data-entry-app/app.py` (import near the `from config import ...` line ~332; mode branch ~7532-7573)

- [ ] **Step 1: Import the helper**

Find (near line 332):

```python
from config import PROJECT_ID, DATASET_ID, ORDERS_TABLE, OTHER_PO_TABLE, SHIPMENTS_TABLE, SHIPMENT_LINES_TABLE, PAYMENTS_TABLE, PRODUCTS_TABLE, COSTS_HISTORY_TABLE, ALERTS_TABLE, PHRASE_NEGATIVES_TABLE
```

Add immediately after it:

```python
from research_match import research_match_predicate
```

- [ ] **Step 2: Replace the mode branch**

In `research_related_terms()` find this block (the `mode = ...` line through the `match_filter = ...` line, ~7532-7573):

```python
    mode = (data.get('mode') or 'direct').strip()  # 'direct' or 'related'
    # Frontend can pass pre-fetched synonyms from Gemini: {"bff": ["best friend", "bestie"]}
    frontend_synonyms = data.get('synonyms') or {}

    # Filter out stop words that add noise to multi-word AND search
    words = [w for w in term.strip().split() if w.lower() not in _RESEARCH_STOP_WORDS]
    if not words:
        # All words were stop words — use entire term as one pattern
        words = [term.strip()]

    if mode == 'related':
        # Expand each word to include synonyms using OR logic
        # Merge: frontend Gemini synonyms take priority, then hardcoded map
        word_groups_sq = []
        word_groups_t = []
        word_param_map = []
        for i, word in enumerate(words):
            gemini_syns = frontend_synonyms.get(word.lower(), [])
            hardcoded_syns = _SYNONYM_MAP.get(word.lower(), [])
            all_syns = list(dict.fromkeys([word] + gemini_syns + hardcoded_syns))  # dedupe, preserve order
            or_parts_sq = []
            or_parts_t = []
            for j, syn in enumerate(all_syns):
                param_name = f'word_{i}_{j}'
                or_parts_sq.append(f"LOWER(sq.query_text) LIKE LOWER(@{param_name})")
                or_parts_t.append(f"LOWER(t.query_text) LIKE LOWER(@{param_name})")
                word_param_map.append((param_name, f'%{syn}%'))
            word_groups_sq.append(f"({' OR '.join(or_parts_sq)})")
            word_groups_t.append(f"({' OR '.join(or_parts_t)})")
        word_likes_sq = ' AND '.join(word_groups_sq)
        word_likes_t = ' AND '.join(word_groups_t)
    else:
        # Direct mode: exact word matching
        word_param_map = [(f'word_{i}', f'%{word}%') for i, word in enumerate(words)]
        word_likes_sq = ' AND '.join([f"LOWER(sq.query_text) LIKE LOWER(@word_{i})" for i in range(len(words))])
        word_likes_t = ' AND '.join([f"LOWER(t.query_text) LIKE LOWER(@word_{i})" for i in range(len(words))])

    rr_cols, rr_join = _research_ranked_select(parent, alias='t')

    # Direct mode shows only word-matching terms (the old client-side filter,
    # now server-side); related mode also returns synonym + co-occurrence rows.
    match_filter = f"WHERE {word_likes_t}" if mode != 'related' else ""
```

Replace it with:

```python
    mode = (data.get('mode') or 'phrase').strip()  # 'direct' | 'phrase' | 'broad'
    if mode not in ('direct', 'phrase', 'broad'):
        mode = 'phrase'
    # Frontend can pass pre-fetched synonyms from Gemini: {"bff": ["best friend", "bestie"]}
    frontend_synonyms = data.get('synonyms') or {}

    # Filter out stop words that add noise to multi-word matching
    words = [w for w in term.strip().split() if w.lower() not in _RESEARCH_STOP_WORDS]
    if not words:
        # All words were stop words — use entire term as one pattern
        words = [term.strip()]

    if mode == 'broad':
        # Broad = Phrase reach + synonym expansion (was the old 'related' mode, unchanged):
        # per-word OR over [word + synonyms], AND-ed across words; returns the full
        # co-occurrence net (no final match_filter) marking direct vs related rows.
        word_groups_sq = []
        word_groups_t = []
        word_param_map = []
        for i, word in enumerate(words):
            gemini_syns = frontend_synonyms.get(word.lower(), [])
            hardcoded_syns = _SYNONYM_MAP.get(word.lower(), [])
            all_syns = list(dict.fromkeys([word] + gemini_syns + hardcoded_syns))  # dedupe, preserve order
            or_parts_sq = []
            or_parts_t = []
            for j, syn in enumerate(all_syns):
                param_name = f'word_{i}_{j}'
                or_parts_sq.append(f"LOWER(sq.query_text) LIKE LOWER(@{param_name})")
                or_parts_t.append(f"LOWER(t.query_text) LIKE LOWER(@{param_name})")
                word_param_map.append((param_name, f'%{syn}%'))
            word_groups_sq.append(f"({' OR '.join(or_parts_sq)})")
            word_groups_t.append(f"({' OR '.join(or_parts_t)})")
        word_likes_sq = ' AND '.join(word_groups_sq)
        word_likes_t = ' AND '.join(word_groups_t)
    else:
        # Direct (exact term + plurals, whole string) / Phrase (all words, any order):
        # whole-word, plural-tolerant REGEXP predicates (fixes the old substring 7/17 bug).
        word_param_map, rx_names = research_match_predicate(words, mode)
        word_likes_sq = ' AND '.join(f"REGEXP_CONTAINS(LOWER(sq.query_text), @{n})" for n in rx_names)
        word_likes_t = ' AND '.join(f"REGEXP_CONTAINS(LOWER(t.query_text), @{n})" for n in rx_names)

    rr_cols, rr_join = _research_ranked_select(parent, alias='t')

    # Direct/Phrase narrow the co-occurrence net to text-matching terms; Broad keeps the
    # full net (synonym + co-occurrence) and marks rows direct vs related.
    match_filter = f"WHERE {word_likes_t}" if mode != 'broad' else ""
```

(The param-binding loop below — `for param_name, param_val in word_param_map:` — already binds every entry as a STRING parameter, so it works unchanged for both regex and `%like%` values.)

- [ ] **Step 3: Verify the Python module still imports cleanly**

Run: `cd /Users/ori/Develop/OI/data-entry-app && python3 -c "import ast; ast.parse(open('app.py').read()); print('app.py parses')"`
Expected: `app.py parses` (syntax check without triggering the BigQuery client).

- [ ] **Step 4: Smoke-test the regex semantics against BigQuery (RE2)**

Run:

```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 --format=prettyjson '
SELECT
  REGEXP_CONTAINS("17 year old", r"\b7s?\b")                              AS seven_not_in_17,   -- expect false
  REGEXP_CONTAINS("7 year old girls", r"\b7s?\b")                         AS seven_matches_7,   -- expect true
  (REGEXP_CONTAINS("gift for a girl", r"\bgirls?\b")
   AND REGEXP_CONTAINS("gift for a girl", r"\bgifts?\b"))                 AS phrase_any_order,  -- expect true
  REGEXP_CONTAINS("girl gifts", r"^\s*girls?\s+gifts?\s*$")               AS direct_exact_true, -- expect true
  REGEXP_CONTAINS("best girl gifts ideas", r"^\s*girls?\s+gifts?\s*$")    AS direct_exact_false -- expect false
'
```

Expected: `seven_not_in_17=false`, `seven_matches_7=true`, `phrase_any_order=true`, `direct_exact_true=true`, `direct_exact_false=false`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add data-entry-app/app.py
git commit -m "feat(research): related-terms supports direct/phrase/broad modes

Direct/Phrase use whole-word regex (research_match_predicate); Broad is
the former synonym-expansion 'related' path, renamed. Default mode is phrase.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Brand card hides advertised terms

**Files:**
- Modify: `dashboard-react/src/pages/research/RecommendationsCard.tsx:25-64`

- [ ] **Step 1: Compute per-type displayed rows (Brand drops ADVERTISED)**

Find:

```tsx
export function RecommendationsCard({ recs, selectedProduct }: RecommendationsCardProps) {
  if (!recs) return null;
  const order: (keyof RecommendationsByType)[] = ['EXACT', 'PHRASE', 'BROAD', 'BRAND'];
  const total = order.reduce((s, k) => s + recs[k].length, 0);
  if (total === 0) return null;
```

Replace with:

```tsx
export function RecommendationsCard({ recs, selectedProduct }: RecommendationsCardProps) {
  if (!recs) return null;
  const order: (keyof RecommendationsByType)[] = ['EXACT', 'PHRASE', 'BROAD', 'BRAND'];
  // Brand defense surfaces only gaps — drop terms we already advertise (✓ live).
  const displayed: RecommendationsByType = {
    EXACT: recs.EXACT,
    PHRASE: recs.PHRASE,
    BROAD: recs.BROAD,
    BRAND: recs.BRAND.filter(r => r.status !== 'ADVERTISED'),
  };
  const total = order.reduce((s, k) => s + displayed[k].length, 0);
  if (total === 0) return null;
```

- [ ] **Step 2: Render from `displayed` instead of `recs`**

Find:

```tsx
        {order.map(type => {
          const rows = recs[type];
          const meta = TYPE_META[type];
```

Replace with:

```tsx
        {order.map(type => {
          const rows = displayed[type];
          const meta = TYPE_META[type];
```

- [ ] **Step 3: Typecheck + lint + build**

Run:
```bash
cd /Users/ori/Develop/OI/dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npm run build && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npm run lint
```
Expected: build succeeds (tsc + vite), lint passes (no new errors in RecommendationsCard.tsx).

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/pages/research/RecommendationsCard.tsx
git commit -m "feat(research): Brand recommendation card shows only not-advertised terms

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: 3-mode toggle, default Phrase, unified re-search effect

**Files:**
- Modify: `dashboard-react/src/pages/ResearchPage.tsx` (searchMode state ~33; doSearch ~148-196; effects ~199-246; toggle JSX ~595-645; clusterSyn ~662)

- [ ] **Step 1: Change the `searchMode` state type and default**

Find:

```tsx
  const [searchMode, setSearchMode] = useState<'direct' | 'related'>('direct');
```

Replace with:

```tsx
  const [searchMode, setSearchMode] = useState<'direct' | 'phrase' | 'broad'>('phrase');
```

- [ ] **Step 2: Simplify `doSearch`'s non-empty branch (no inline results fetch)**

Find (the non-empty-term portion of `doSearch`, from `const searchTerm` through the end of step 1's inline fetch):

```tsx
    const searchTerm = term.trim();
    setLoading(true);
    setSubmittedTerm(searchTerm);
    setSynonyms({});
    setSynonymsReady(false);
    setSearchMode('direct');  // Always start with direct
    setCurrentPage(1);

    // 1. Run direct search immediately
    try {
      const res = await apiFetch('/api/research/related-terms', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ term: searchTerm, parent: parent || undefined, mode: 'direct' }),
      });
      if (res.ok) {
        const data: Record<string, unknown>[] = await res.json();
        setResults(data.map(mapResearchRow));
      }
    } catch (e) {
      console.error('Research search failed:', e);
    } finally {
      setLoading(false);
    }

    // 2. Background: fetch synonyms (DE_SYNONYM_CACHE + hardcoded fallback)
```

Replace with:

```tsx
    const searchTerm = term.trim();
    setLoading(true);
    setSubmittedTerm(searchTerm);
    setSynonyms({});
    setSynonymsReady(false);
    setSearchMode('phrase');  // default match-type after a search; the mode effect fetches
    setCurrentPage(1);

    // Results are fetched by the mode effect below (keyed on submittedTerm + searchMode).
    // Background: fetch synonyms (DE_SYNONYM_CACHE + hardcoded fallback) to enable Broad.
```

- [ ] **Step 3: Replace the two ad-hoc fetch effects with one unified mode effect**

Find both effects — the "switch to Related" effect and the "parent changed" effect (from the comment `// When user toggles to Related mode...` through the closing of the `parentRef` effect, ~198-246):

```tsx
  // When user toggles to Related mode with available synonyms, re-search
  useEffect(() => {
    if (searchMode !== 'related' || !submittedTerm || submittedTerm === '__top__') return;
    if (Object.keys(synonyms).length === 0) return;

    setLoading(true);
    apiFetch('/api/research/related-terms', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        term: submittedTerm, parent: parent || undefined,
        mode: 'related', synonyms,
      }),
    })
      .then(r => r.ok ? r.json() : [])
      .then((data: Record<string, unknown>[]) => setResults(data.map(mapResearchRow)))
      .catch(e => console.error('Related search failed:', e))
      .finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchMode]);

  // Auto-re-fetch when parent scope changes (e.g. user changes family tab mid-search)
  const parentRef = useRef(parent);
  useEffect(() => {
    if (parentRef.current === parent) return; // skip initial
    parentRef.current = parent;
    if (submittedTerm && submittedTerm !== '__top__') {
      (async () => {
        setLoading(true);
        try {
          const res = await apiFetch('/api/research/related-terms', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              term: submittedTerm, parent: parent || undefined,
              mode: searchMode,
              ...(searchMode === 'related' ? { synonyms } : {}),
            }),
          });
          if (res.ok) {
            const data: Record<string, unknown>[] = await res.json();
            setResults(data.map(mapResearchRow));
          }
        } catch (e) { console.error('Re-fetch failed:', e); }
        finally { setLoading(false); }
      })();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [parent, submittedTerm]);
```

Replace both with:

```tsx
  // Single fetch path for a live search: runs whenever the term, family, or match-type
  // mode changes. Synonyms only matter for Broad, so a synonym arrival re-fetches only
  // in that mode (reqKey dedupes against modes synonyms don't affect). Replaces the old
  // per-mode and per-parent effects, and the inline fetch that doSearch used to do.
  const searchReqRef = useRef('');
  useEffect(() => {
    if (!submittedTerm || submittedTerm === '__top__') return;
    const synActive = searchMode === 'broad' && synonymsReady;
    const reqKey = `${submittedTerm}|${parent}|${searchMode}|${synActive}`;
    if (searchReqRef.current === reqKey) return;
    searchReqRef.current = reqKey;
    setLoading(true);
    apiFetch('/api/research/related-terms', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        term: submittedTerm,
        parent: parent || undefined,
        mode: searchMode,
        ...(searchMode === 'broad' ? { synonyms } : {}),
      }),
    })
      .then(r => r.ok ? r.json() : [])
      .then((data: Record<string, unknown>[]) => setResults(data.map(mapResearchRow)))
      .catch(e => console.error('Research mode fetch failed:', e))
      .finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [submittedTerm, parent, searchMode, synonymsReady]);
```

- [ ] **Step 4: Replace the toggle JSX (Direct/Related → Direct/Phrase/Broad)**

Find the whole toggle block (from `{/* ─── Direct / Related toggle (above table) ─── */}` through its closing `)}`, ~595-645) and replace it with:

```tsx
        {/* ─── Direct / Phrase / Broad toggle (above table) ─── */}
        {!loading && submittedTerm && submittedTerm !== '__top__' && (
          <div className="flex items-center gap-3 mb-3">
            <div className="inline-flex rounded-lg border border-border overflow-hidden">
              <button
                onClick={() => setSearchMode('direct')}
                title="Exact term + plurals only"
                className={`px-4 py-1.5 text-xs font-semibold transition-all ${
                  searchMode === 'direct'
                    ? 'text-white bg-blue-600'
                    : 'text-muted bg-white/[0.02] hover:text-subtle'
                }`}
              >
                Direct
              </button>
              <button
                onClick={() => setSearchMode('phrase')}
                title="All words, any order, extra words allowed"
                className={`px-4 py-1.5 text-xs font-semibold transition-all border-l border-border ${
                  searchMode === 'phrase'
                    ? 'text-white bg-blue-600'
                    : 'text-muted bg-white/[0.02] hover:text-subtle'
                }`}
              >
                Phrase
              </button>
              <button
                onClick={() => setSearchMode('broad')}
                className={`px-4 py-1.5 text-xs font-semibold transition-all border-l border-border relative ${
                  searchMode === 'broad'
                    ? 'text-white bg-purple-600'
                    : synonymsReady
                      ? 'text-purple-400 bg-purple-500/10 hover:bg-purple-500/20'
                      : 'text-muted bg-white/[0.02] hover:text-subtle'
                }`}
                title={
                  synonymsLoading ? 'Finding synonyms...'
                  : synonymsReady ? `Phrase reach + synonyms: ${Object.entries(synonyms).map(([w, s]) => `${w} → ${s.join(', ')}`).join(' | ')}`
                  : 'Phrase reach + synonyms (none found yet for these words)'
                }
              >
                {synonymsLoading && <RefreshCw size={10} className="inline animate-spin mr-1" />}
                Broad
                {synonymsReady && (
                  <span className="absolute -top-1.5 -right-1.5 min-w-[16px] h-4 flex items-center justify-center rounded-full bg-purple-500 text-white text-[9px] font-bold px-1">
                    {Object.values(synonyms).flat().length}
                  </span>
                )}
              </button>
            </div>
            {searchMode === 'broad' && synonymsReady && (
              <span className="text-[11px] text-muted">
                {Object.entries(synonyms).filter(([, s]) => s.length > 0).map(([w, s]) => (
                  <span key={w} className="mr-3">
                    <span className="text-purple-400 font-semibold">{w}</span>
                    <span className="text-muted/60"> → {s.join(', ')}</span>
                  </span>
                ))}
              </span>
            )}
          </div>
        )}
```

- [ ] **Step 5: Make `clusterSyn` Broad-only**

Find:

```tsx
            clusterSyn={searchMode === 'related' && synonymsReady ? synonyms : undefined}
```

Replace with:

```tsx
            clusterSyn={searchMode === 'broad' && synonymsReady ? synonyms : undefined}
```

- [ ] **Step 6: Typecheck + lint + unit tests + build**

Run:
```bash
cd /Users/ori/Develop/OI/dashboard-react && \
  PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npm run build && \
  PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npm run lint && \
  PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npm run test
```
Expected: build succeeds (no TS errors — e.g. no remaining `'related'` literal mismatches), lint passes, vitest passes. If lint flags an unused `useRef` import, it is still used by `searchReqRef` — re-check the edit landed.

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/pages/ResearchPage.tsx
git commit -m "feat(research): 3-way Direct/Phrase/Broad search toggle

Default mode Phrase; Broad carries synonym expansion; one unified mode
effect replaces the per-mode and per-parent fetch effects.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Update the SOP

**Files:**
- Modify: `architecture/RESEARCH_PAGE.md` (the `related-terms` endpoint row ~130; History section ~198)

- [ ] **Step 1: Update the endpoint contract row**

Find:

```markdown
| `related-terms` | POST `{term, parent?, mode, synonyms?}` | FACT_SEARCH_QUERY (seeds) + FACT tables | co-occurrence expansion. **Direct mode = whole-word, plural-tolerant match** (`7`≠`17`, `girl`=`girls`); not substring `LIKE '%word%'`. Related mode keeps synonym `LIKE` expansion. |
```

Replace with:

```markdown
| `related-terms` | POST `{term, parent?, mode, synonyms?}` | FACT_SEARCH_QUERY (seeds) + FACT tables | co-occurrence expansion. **mode ∈ {direct, phrase, broad}** (default `phrase`). **Direct** = exact term + plurals, whole-string regex. **Phrase** = every token present, any order, extra words allowed (whole-word, plural-tolerant regex; `7`≠`17`, `girl`=`girls`). Direct/Phrase predicates built by `research_match.research_match_predicate` and applied as a `match_filter`. **Broad** = the former `related` mode unchanged: per-word synonym `LIKE` OR-expansion over the full co-occurrence net (no `match_filter`), marking rows direct vs related. |
```

- [ ] **Step 2: Add a History entry**

Find the History list and add as the newest bullet (after the 2026-06-12 entry):

```markdown
- 2026-06-16: Search toggle is now 3-way **Direct / Phrase / Broad** (was Direct/Related);
  Direct/Phrase use whole-word plural-tolerant regex (fixes the substring `7`/`17` bug),
  Broad = the old synonym-expansion path. Default mode = Phrase. Brand recommendation card
  now hides ADVERTISED rows (shows only not-yet-advertised own-brand gaps). Helper:
  `data-entry-app/research_match.py`. Spec:
  `docs/superpowers/specs/2026-06-16-research-match-type-toggles-and-brand-card-design.md`.
```

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add architecture/RESEARCH_PAGE.md
git commit -m "docs(research): SOP — 3-way match-type toggle + brand-card gaps

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Final verification

- [ ] **Step 1: Python unit tests pass**

Run: `cd /Users/ori/Develop/OI/data-entry-app && python3 -m unittest test_research_match -v`
Expected: 5 tests OK.

- [ ] **Step 2: Frontend build + lint + tests pass**

Run:
```bash
cd /Users/ori/Develop/OI/dashboard-react && \
  PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npm run build && \
  PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npm run lint && \
  PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npm run test
```
Expected: all pass.

- [ ] **Step 3: BigQuery regex smoke check passes**

Re-run the Task 2 Step 4 `bq query`; confirm the 5 boolean expectations.

- [ ] **Step 4 (optional, requires API): live preview**

The research page calls `/api/research/*`, which the Vite dev proxy sends to
`VITE_FLASK_API_URL` (default `http://localhost:5050`). To exercise the new modes end-to-end,
point that at a `data-entry-app/app.py` running locally (or the deployed Cloud Run URL) and:
1. `cd dashboard-react && PATH=".../node/v22.22.1/bin:$PATH" VITE_FLASK_API_URL=<flask-url> npm run dev`
2. Search a multi-word term; cycle Direct → Phrase → Broad and confirm result counts widen
   (exact → all-words-any-order → +synonyms).
3. Confirm the Brand recommendation card shows no "✓ live" rows while Exact/Phrase/Broad still do.

Note: the deployed Flask must be redeployed with the Task 2 change before the new modes work
in production — deployment is out of scope for this plan.

---

## Notes / deviations from spec

- **Helper module location:** the spec said "extract a pure helper in `app.py`"; the plan puts
  it in a dedicated `data-entry-app/research_match.py` so the unit test imports it without
  triggering `app.py`'s import-time BigQuery client. Same intent (pure, isolated, testable).
- **Summary stat tiles:** left as "Direct Matches" / "Related Terms" — both still read
  accurately across modes (in Broad, `match_type` splits text-matching vs co-occurrence-only),
  so the spec's optional cosmetic relabel is unnecessary.
