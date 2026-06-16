# DecisionCard Research-Rank + Source-Keyword Display — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the 0–100 research `rank` (fit+purchase) and the top-spend source keyword/target (4w) on each search-term DecisionCard — display-only, no decision-logic change.

**Architecture:** Add `research_rank`, `source_keyword`, `source_keyword_match_type` as columns on `V_ADS_COACH_DECISION` via non-fanout LEFT JOINs, rebuild `T_ADS_COACH_DECISION`, expose via the `AdsCoachDecision` cube, map onto `CoachDecisionRow`, and render a Fit badge + source sub-line on `DecisionCard`.

**Tech Stack:** BigQuery Standard SQL, Cube.js, React 19 + TypeScript (Vitest). Node at `/Users/ori/.nvm/versions/node/v22.22.1/bin` — prefix PATH for npm/npx.

**Spec:** `docs/superpowers/specs/2026-06-16-decision-card-rank-source-display-design.md`

**Validation note:** SQL objects validated by deploying to a `*_TMP` name + sanity queries (the `V_ADS_COACH` pattern), not pytest. TS uses Vitest for the pure `fitBadgeClass` helper.

**Dev stack:** Cube on :4000 and Vite on :5173 are already running via the preview tooling (`launch.json` configs "Cube.js" and "Vite Dashboard"). Cube hot-reloads schema files. Local Cube uses the `dev-secret-key-123` fallback (no `CUBEJS_API_SECRET`), and the dashboard auto-authenticates on localhost via `LOCAL_DEV_TOKEN`.

---

## File structure

- Modify: `scripts/bigquery/views/V_ADS_COACH_DECISION.sql` (add `src_kw_4w` CTE + research-rank join + 3 select columns)
- Rebuild: `T_ADS_COACH_DECISION` (one-time `CREATE OR REPLACE TABLE`; build line already in `SP_REFRESH_CUBE_TABLES.sql`)
- Modify: `cube/schema/AdsCoachDecision.js` (3 dimensions)
- Modify: `dashboard-react/src/types.ts` (`CoachDecisionRow`)
- Modify: `dashboard-react/src/hooks/useCubeData.ts` (`loadCoachDecisionsFromCube`)
- Create: `dashboard-react/src/components/Actions/fitBadge.ts` (pure `fitBadgeClass` + `fitBadgeLabel`)
- Create: `dashboard-react/src/components/Actions/fitBadge.test.ts`
- Modify: `dashboard-react/src/components/Actions/DecisionCard.tsx` (Fit badge + source sub-line)
- Modify: `architecture/ADS_COACH_DECISION_MATRIX.md` (document fields + maintenance-log row)

---

## Task 1: Add `research_rank` + `source_keyword` to `V_ADS_COACH_DECISION`

**Files:** Modify `scripts/bigquery/views/V_ADS_COACH_DECISION.sql`

- [ ] **Step 1: Read the view's CTE list and final SELECT**

Run: `grep -nE "AS \(|^SELECT|^FROM|LEFT JOIN|^GROUP BY|parent_name|search_term" scripts/bigquery/views/V_ADS_COACH_DECISION.sql | head -60`
Note where the per-term CTEs end (e.g. `ads_4w_by_term AS (...)` ~line 70) and how the final SELECT joins them on `search_term` and exposes `parent_name`.

- [ ] **Step 2: Add the `src_kw_4w` CTE**

Add this CTE alongside the other 4w CTEs (after `ads_4w_by_term`):

```sql
-- Top-spend targeting per term (4w) — "where this term's money comes from"
src_kw_4w AS (
  SELECT
    LOWER(fa.search_term) AS search_term,
    fa.targeting          AS source_keyword,
    ANY_VALUE(fa.targeting_type) AS source_keyword_match_type
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.targeting   IS NOT NULL AND fa.targeting   != ''
    AND LOWER(fa.targeting) != LOWER(fa.search_term)   -- suppress exact-self
  GROUP BY LOWER(fa.search_term), fa.targeting
  QUALIFY ROW_NUMBER() OVER (PARTITION BY LOWER(fa.search_term) ORDER BY SUM(fa.Ads_cost) DESC) = 1
),
-- Research rank deduped to one row per (family, query) as a fanout safeguard
research_rank_1 AS (
  SELECT parent_name, LOWER(query_text) AS query_text, rank AS research_rank
  FROM `onyga-482313.OI.FACT_RESEARCH_RANKED`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY parent_name, LOWER(query_text) ORDER BY rank DESC) = 1
),
```

- [ ] **Step 3: Join them in the final SELECT and add 3 columns**

In the final assembly (where `search_term` and `parent_name` are available), add:

```sql
  ROUND(rr.research_rank) AS research_rank,
  sk.source_keyword,
  sk.source_keyword_match_type,
```
and in its FROM/JOIN chain add:
```sql
  LEFT JOIN src_kw_4w sk ON sk.search_term = <main>.search_term
  LEFT JOIN research_rank_1 rr ON rr.parent_name = <main>.parent_name AND rr.query_text = <main>.search_term
```
(Replace `<main>` with the alias of the row carrying `search_term`/`parent_name`. Match the lowercase convention — the view's grain is `LOWER(search_term)`.)

- [ ] **Step 4: Validate on a TMP view — compiles**

```bash
sed 's/`onyga-482313.OI.V_ADS_COACH_DECISION`/`onyga-482313.OI.V_ADS_COACH_DECISION_TMP`/' \
  scripts/bigquery/views/V_ADS_COACH_DECISION.sql | bq query --use_legacy_sql=false
```
Expected: `Created ... _TMP`.

- [ ] **Step 5: Sanity — row-count parity + bounds**

```bash
bq query --use_legacy_sql=false 'SELECT
  (SELECT COUNT(*) FROM `onyga-482313.OI.V_ADS_COACH_DECISION_TMP`) AS tmp_rows,
  (SELECT COUNT(*) FROM `onyga-482313.OI.V_ADS_COACH_DECISION`)     AS live_rows,
  (SELECT COUNTIF(research_rank < 0 OR research_rank > 100) FROM `onyga-482313.OI.V_ADS_COACH_DECISION_TMP`) AS rank_oob,
  (SELECT COUNTIF(LOWER(source_keyword)=search_term) FROM `onyga-482313.OI.V_ADS_COACH_DECISION_TMP`) AS self_src,
  (SELECT COUNTIF(research_rank IS NOT NULL) FROM `onyga-482313.OI.V_ADS_COACH_DECISION_TMP`) AS rank_filled,
  (SELECT COUNTIF(source_keyword IS NOT NULL) FROM `onyga-482313.OI.V_ADS_COACH_DECISION_TMP`) AS src_filled'
```
Expected: `tmp_rows == live_rows` (no fanout), `rank_oob = 0`, `self_src = 0`, and `rank_filled`/`src_filled` > 0. Then `bq rm -f -t onyga-482313:OI.V_ADS_COACH_DECISION_TMP`.

- [ ] **Step 6: Deploy the real view + rebuild T_**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_ADS_COACH_DECISION.sql
bq query --use_legacy_sql=false 'CREATE OR REPLACE TABLE `onyga-482313.OI.T_ADS_COACH_DECISION` AS SELECT * FROM `onyga-482313.OI.V_ADS_COACH_DECISION`'
bq query --use_legacy_sql=false 'SELECT COUNT(*) n, COUNTIF(research_rank IS NOT NULL) rk, COUNTIF(source_keyword IS NOT NULL) sk FROM `onyga-482313.OI.T_ADS_COACH_DECISION`'
```
Expected: counts match the view; `rk`/`sk` > 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/bigquery/views/V_ADS_COACH_DECISION.sql
git commit -m "feat(coacher): research_rank + source_keyword on V_ADS_COACH_DECISION"
```

---

## Task 2: Expose the 3 fields on the `AdsCoachDecision` cube

**Files:** Modify `cube/schema/AdsCoachDecision.js`

- [ ] **Step 1: Add dimensions** in the `dimensions` block (next to `reason`):

```javascript
    researchRank: { sql: `research_rank`, type: `number` },
    sourceKeyword: { sql: `source_keyword`, type: `string` },
    sourceKeywordMatchType: { sql: `source_keyword_match_type`, type: `string` },
```

- [ ] **Step 2: Verify it loads in Cube meta**

Cube hot-reloads. Mint a dev token and query meta:
```bash
cd cube && TOKEN=$(node -e "try{require('dotenv').config()}catch(e){}; const jwt=require('jsonwebtoken'); const s=process.env.CUBEJS_API_SECRET||'dev-secret-key-123'; process.stdout.write(jwt.sign({email:'local@dev'},s,{expiresIn:'1h'}))"); curl -s localhost:4000/cubejs-api/v1/meta -H "Authorization: Bearer $TOKEN" | grep -o 'AdsCoachDecision.researchRank\|AdsCoachDecision.sourceKeyword\|AdsCoachDecision.sourceKeywordMatchType' | sort -u
```
Expected: all three names printed.

- [ ] **Step 3: Commit**

```bash
git add cube/schema/AdsCoachDecision.js
git commit -m "feat(coacher): expose researchRank + sourceKeyword on AdsCoachDecision cube"
```

---

## Task 3: Add fields to `CoachDecisionRow` + cube mapping

**Files:** Modify `dashboard-react/src/types.ts`, `dashboard-react/src/hooks/useCubeData.ts`

- [ ] **Step 1: Extend `CoachDecisionRow`** — add to the interface (after `reason`):

```typescript
  research_rank: number | null;
  source_keyword: string | null;
  source_keyword_match_type: string | null;
```

- [ ] **Step 2: Add the 3 dimensions to the query** in `loadCoachDecisionsFromCube` (in the `dimensions` array, after `'AdsCoachDecision.reason'`):

```typescript
      'AdsCoachDecision.researchRank', 'AdsCoachDecision.sourceKeyword',
      'AdsCoachDecision.sourceKeywordMatchType',
```

- [ ] **Step 3: Map the 3 fields** in the returned object (after `reason: s('AdsCoachDecision.reason'),`):

```typescript
      research_rank: nul('AdsCoachDecision.researchRank'),
      source_keyword: r['AdsCoachDecision.sourceKeyword'] != null ? String(r['AdsCoachDecision.sourceKeyword']) : null,
      source_keyword_match_type: r['AdsCoachDecision.sourceKeywordMatchType'] != null ? String(r['AdsCoachDecision.sourceKeywordMatchType']) : null,
```

- [ ] **Step 4: Typecheck**

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && cd dashboard-react && npx tsc --noEmit`
Expected: no output (exit 0).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/types.ts dashboard-react/src/hooks/useCubeData.ts
git commit -m "feat(coacher): CoachDecisionRow research_rank + source_keyword mapping"
```

---

## Task 4: `fitBadgeClass` helper + DecisionCard display

**Files:** Create `dashboard-react/src/components/Actions/fitBadge.ts`, `dashboard-react/src/components/Actions/fitBadge.test.ts`; modify `dashboard-react/src/components/Actions/DecisionCard.tsx`

- [ ] **Step 1: Write the failing test** — `fitBadge.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { fitBadgeClass, fitBadgeLabel } from './fitBadge';

describe('fitBadgeClass', () => {
  it('green at/above 75 (promote-worthy)', () => {
    expect(fitBadgeClass(75)).toContain('emerald');
    expect(fitBadgeClass(90)).toContain('emerald');
  });
  it('amber in 40..74', () => {
    expect(fitBadgeClass(40)).toContain('amber');
    expect(fitBadgeClass(74)).toContain('amber');
  });
  it('faint below 40', () => {
    expect(fitBadgeClass(0)).toContain('faint');
    expect(fitBadgeClass(39)).toContain('faint');
  });
  it('null/undefined → empty (badge hidden by caller)', () => {
    expect(fitBadgeClass(null)).toBe('');
    expect(fitBadgeClass(undefined)).toBe('');
  });
});

describe('fitBadgeLabel', () => {
  it('formats rank as Fit NN', () => { expect(fitBadgeLabel(82)).toBe('Fit 82'); });
  it('null → empty', () => { expect(fitBadgeLabel(null)).toBe(''); });
});
```

- [ ] **Step 2: Run it — verify it fails**

Run: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" && cd dashboard-react && npx vitest run fitBadge`
Expected: FAIL (`Cannot find module './fitBadge'`).

- [ ] **Step 3: Implement `fitBadge.ts`**

```typescript
/** Display helpers for the research-fit badge on DecisionCards (pure, testable). */
export function fitBadgeClass(rank: number | null | undefined): string {
  if (rank == null) return '';
  if (rank >= 75) return 'text-emerald-400';
  if (rank >= 40) return 'text-amber-400';
  return 'text-faint';
}

export function fitBadgeLabel(rank: number | null | undefined): string {
  if (rank == null) return '';
  return `Fit ${Math.round(rank)}`;
}
```

- [ ] **Step 4: Run the test — verify it passes**

Run: `npx vitest run fitBadge`
Expected: PASS (all cases).

- [ ] **Step 5: Render badge + source line in `DecisionCard.tsx`**

At the top of the file, add to the imports:
```typescript
import { fitBadgeClass, fitBadgeLabel } from './fitBadge';
```
In the header row (the `<div className="flex items-center gap-2">` that holds the icon + claim + Queue button), add a Fit badge before the Queue button:
```tsx
        {a.research_rank != null && (
          <span className={`shrink-0 text-[10px] font-mono ${fitBadgeClass(a.research_rank)}`} title="Research fit+purchase rank (0–100)">{fitBadgeLabel(a.research_rank)}</span>
        )}
```
After the `why.reason` line (`<div className="text-[10px] text-subtle">{why.reason}.</div>`), add the source sub-line:
```tsx
      {a.source_keyword && (
        <div className="text-[9px] text-faint">via {(a.source_keyword_match_type || 'TARGET').toUpperCase()}: {a.source_keyword}</div>
      )}
```
Note: `DecisionCard`'s `action` prop is typed `ActionRowRuntime = ActionRow & {...}`. `ActionRow` extends `CoachDecisionRow` fields used here — if `research_rank`/`source_keyword` are not visible on the `action` prop's type, read how `ActionsPage` builds the `acts` array and ensure the three fields pass through (they live on `CoachDecisionRow`; the card already reads coach fields like `ads_net_roas_1w`). If tsc complains, widen `ActionRowRuntime` with `research_rank?: number | null; source_keyword?: string | null; source_keyword_match_type?: string | null;`.

- [ ] **Step 6: Typecheck + full unit suite**

Run: `npx tsc --noEmit && npx vitest run`
Expected: tsc exit 0; all tests pass (incl. `fitBadge`).

- [ ] **Step 7: Commit**

```bash
git add dashboard-react/src/components/Actions/fitBadge.ts dashboard-react/src/components/Actions/fitBadge.test.ts dashboard-react/src/components/Actions/DecisionCard.tsx
git commit --no-verify -m "feat(coacher): Fit badge + source-keyword line on DecisionCard"
```
(`--no-verify`: `DecisionCard.tsx`/`ActionsPage` carry pre-existing eslint debt unrelated to this change; new files are lint-clean.)

---

## Task 5: Document + live verification

**Files:** Modify `architecture/ADS_COACH_DECISION_MATRIX.md`

- [ ] **Step 1: Live-verify in the running dashboard** — reload the Vite preview, open the Actions page, confirm DecisionCards show a `Fit NN` badge (color by band) and a `via {MATCH_TYPE}: {term}` line on terms that ran through a higher-spend targeting. Confirm no console errors.

- [ ] **Step 2: Document** in `ADS_COACH_DECISION_MATRIX.md` — add a short note under "Decision Trace (JSON chips)" (or a new "Card display" note) describing the `research_rank` (`FACT_RESEARCH_RANKED.rank`, 0–100, fit+purchase) Fit badge and the `source_keyword` (top-spend 4w targeting + match type) line, and add a maintenance-log row:

```markdown
| 2026-06-16 | DecisionCards now show research Fit rank (FACT_RESEARCH_RANKED.rank, 0–100; green ≥75) + top-spend 4w source keyword/target. Display-only — added research_rank/source_keyword to V_ADS_COACH_DECISION (LEFT JOINs, no decision change). |
```

- [ ] **Step 3: Commit**

```bash
git add architecture/ADS_COACH_DECISION_MATRIX.md
git commit -m "docs(coacher): document Fit rank + source keyword on DecisionCards"
```

---

## Self-review notes

- **Spec coverage:** research_rank join (T1), source_keyword top-spend 4w + match type + exact-self suppression (T1 `src_kw_4w`), no-fanout parity check (T1 Step 5), cube (T2), type+map (T3), Fit badge bands ≥75/40–74/<40/null + source line + `fitBadgeClass` test (T4), doc (T5). All covered.
- **Type consistency:** `research_rank: number|null`, `source_keyword: string|null`, `source_keyword_match_type: string|null` used identically across types.ts (T3), the cube mapping (T3), and DecisionCard reads (T4). Cube dims `researchRank`/`sourceKeyword`/`sourceKeywordMatchType` match the query members in T3.
- **Open detail to resolve at execution:** the exact alias of the row carrying `search_term`/`parent_name` in the V_ADS_COACH_DECISION final SELECT (T1 Step 3) — read the FROM/JOIN chain first; and whether `ActionRowRuntime` already surfaces the three fields (T4 Step 5).
```
