# Daily Workflow Cockpit — S1 Implementation Plan (rung 1: SEE)

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` or
> `superpowers:executing-plans` to implement task-by-task. Steps use `- [ ]` for tracking.

**Goal:** Evolve `CoveragePage` into rung-1 of the cockpit — six strategy tiles (Ori's 6) rolling up
`defined / to-do / redundant`, each expandable to a family × intent-cell grid, all read-only.

**Architecture:** New `V_COVERAGE_CAMPAIGN` reconciles a target set (what SHOULD exist, from the intent
model) against the live set (`V_CAMPAIGN_ROLE`), minus rows suppressed by a new `DE_COVERAGE_EXPECTATION`
opt-out table. A Flask endpoint serves the strategy→family→intent tree; the React page renders it. No
action/apply logic in S1 (that's S4). Spec: [`DAILY_WORKFLOW_COCKPIT.md`](DAILY_WORKFLOW_COCKPIT.md).

**Tech stack:** BigQuery Standard SQL · Flask (`data-entry-app/app.py`) · React 19 + TS + Tailwind 4
(`dashboard-react/`) · vitest.

**Non-negotiables:** register every new BQ object in [`config.yaml`](../config.yaml); confirm payload
shapes before writing SQL (data-first); all decision logic in backend, page is presentation only.

---

## Task 0: Shape-confirmation spike (do this first — later tasks depend on it)

**Files:** none written. Produces `.tmp/s1_shapes.md` notes only.

The three build unknowns. Run each and record the answer in `.tmp/s1_shapes.md`.

- [ ] **Step 1: Confirm `V_CAMPAIGN_ROLE` output columns** (esp. that `strategy_category`, `parent_name`/family, `asin`, `match_type`, `campaign_name`, enabled flag exist and their exact names)

```bash
bq query --use_legacy_sql=false --max_rows=5 \
'SELECT * FROM `onyga-482313.OI.V_CAMPAIGN_ROLE` LIMIT 5'
bq query --use_legacy_sql=false \
'SELECT column_name,data_type FROM `onyga-482313.OI`.INFORMATION_SCHEMA.COLUMNS WHERE table_name="V_CAMPAIGN_ROLE" ORDER BY ordinal_position'
```

- [ ] **Step 2: Confirm `V_INTENT_KEYWORDS` — the "expected intents per family" set**

```bash
bq query --use_legacy_sql=false \
'SELECT column_name,data_type FROM `onyga-482313.OI`.INFORMATION_SCHEMA.COLUMNS WHERE table_name="V_INTENT_KEYWORDS" ORDER BY ordinal_position'
# expected intents per family = distinct (parent_name, intent_key) where is_relevant
bq query --use_legacy_sql=false --max_rows=20 \
'SELECT parent_name, intent_key, ANY_VALUE(intent_type) it, COUNT(*) kw
 FROM `onyga-482313.OI.V_INTENT_KEYWORDS` WHERE is_relevant GROUP BY 1,2 ORDER BY 1,2'
```

- [ ] **Step 3: THE FORK — how is a live campaign tied to an intent?** Determine whether any existing object maps a campaign to an `intent_key`. Check `DIM_EXPERIMENT_CAMPAIGN`, `DIM_CAMPAIGN`, and campaign-name conventions.

```bash
bq query --use_legacy_sql=false \
'SELECT column_name FROM `onyga-482313.OI`.INFORMATION_SCHEMA.COLUMNS WHERE table_name IN ("DIM_EXPERIMENT_CAMPAIGN","DIM_CAMPAIGN") ORDER BY table_name,ordinal_position'
grep -rn "intent" scripts/bigquery/views/V_CAMPAIGN_ROLE.sql scripts/bigquery/views/V_INTENT_KEYWORDS.sql
```

- [ ] **Step 4: Read the existing coverage query** to reuse its status logic verbatim

Read `data-entry-app/app.py` around `ads_coverage_scan()` (~line 8973, status logic ~9095–9102). Copy the exact `ok/missing/redundant` CASE and the family/store/auto grain rollup into `.tmp/s1_shapes.md`.

- [ ] **Step 5: Record the intent-grain decision in the spec**

**RESOLVED 2026-07-21 → (B) NO campaign→intent linkage.** Evidence in `.tmp/s1_shapes.md`: no
`%intent%` column on DIM_EXPERIMENT_CAMPAIGN / DIM_CAMPAIGN / V_CAMPAIGN_ROLE; campaign names don't
encode intent; the only intent signal is `strategy_id='INTENT'` (one of 6 buckets, not *which* intent).
**S1 ships at `parent_name × strategy_category` grain.** Per-intent cells → S1b, prerequisite = a
campaign→intent_key tagging step (extend `DIM_EXPERIMENT_CAMPAIGN`).

Confirmed shapes for the tasks below:
- `V_CAMPAIGN_ROLE` = thin classifier keyed on `campaign_id`: `campaign_type, targeting_type,
  strategy_id, role, is_offense_role, strategy_category`. **No** family/ASIN/name/state/metrics.
- Family/ASIN/state/metrics are assembled by the existing `ads_coverage_scan()` in app.py (ASIN via
  `V_SRC_AmazonAds_advertised_product.advertised_asin` → `parent_name` via DIM_PRODUCT; state via
  `V_SRC_AmazonAds_campaign_history`; metrics via FACT_AMAZON_ADS).
- Existing status logic: `n_enabled = COUNTIF(state='ENABLED')`; `0 → missing`, `>1 → redundant`,
  `1 → ok`. Reuse verbatim.
- `V_INTENT_KEYWORDS`: `parent_name`, `intent_key`, `is_relevant` (BOOL) — target set for S1b only.

---

## Task 1: `DE_COVERAGE_EXPECTATION` opt-out table

**Files:**
- Create: `scripts/bigquery/tables/DE_COVERAGE_EXPECTATION.sql`
- Modify: `config.yaml` (register the object)

- [ ] **Step 1: Write the DDL**

```sql
-- One row per (scope) the user has marked NOT expected, to suppress false "missing".
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_COVERAGE_EXPECTATION` (
  id            STRING NOT NULL,          -- uuid
  scope_grain  STRING NOT NULL,           -- 'STRATEGY' | 'FAMILY_STRATEGY' | 'INTENT_CELL'
  parent_name  STRING,                    -- family (NULL for store-wide)
  strategy     STRING NOT NULL,           -- AUTO|INTENT|EXACT_BOOST|COMPETITOR|BRAND_DEFENSE|PRODUCT_DEFENSE
  intent_key   STRING,                    -- NULL unless scope_grain='INTENT_CELL'
  match_type   STRING,                    -- NULL unless intent-cell needs it
  is_active    BOOL NOT NULL,             -- FALSE = tombstone (un-suppress)
  reason       STRING,
  updated_by   STRING,
  updated_at   TIMESTAMP NOT NULL
);
```

- [ ] **Step 2: Create it and register**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/tables/DE_COVERAGE_EXPECTATION.sql
```
Add a `DE_COVERAGE_EXPECTATION` entry under the DE tables section of `config.yaml` mirroring an existing `DE_` entry's format.

- [ ] **Step 3: Verify it exists and is empty**

```bash
bq query --use_legacy_sql=false 'SELECT COUNT(*) n FROM `onyga-482313.OI.DE_COVERAGE_EXPECTATION`'
```
Expected: `n = 0`.

---

## Task 2: `V_COVERAGE_CAMPAIGN` view

**Files:**
- Create: `scripts/bigquery/views/V_COVERAGE_CAMPAIGN.sql`
- Modify: `config.yaml`

**Grain:** per (parent_name × strategy [× intent_key × match_type if fork=A]). One row per target cell,
carrying live presence + status + suppression flag. Uses the EXACT status CASE copied in Task 0 Step 4.

- [ ] **Step 1: Write the view** (column names from Task 0; the skeleton below is the shape)

```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_COVERAGE_CAMPAIGN` AS
WITH
-- TARGET: what should exist, per strategy. AUTO=per ASIN; INTENT/EXACT_BOOST/COMPETITOR=per family×intent;
-- BRAND_DEFENSE=per family; PRODUCT_DEFENSE=store. (Fork A adds intent_key/match_type to the intent rows.)
target AS (
  -- Intent-based strategies: one target per relevant (family × intent)
  SELECT parent_name, 'INTENT' AS strategy, intent_key
  FROM `onyga-482313.OI.V_INTENT_KEYWORDS` WHERE is_relevant GROUP BY 1,2,3
  UNION ALL
  SELECT parent_name, 'BRAND_DEFENSE' AS strategy, CAST(NULL AS STRING)
  FROM `onyga-482313.OI.V_INTENT_KEYWORDS` GROUP BY 1,2,3
  -- … EXACT_BOOST, COMPETITOR, PRODUCT_DEFENSE, AUTO per §3 of the spec; exact sources from Task 0
),
live AS (  -- what exists, from V_CAMPAIGN_ROLE grouped to the same grain
  SELECT parent_name, strategy_category AS strategy, /* intent_key if fork A */
         COUNTIF(is_enabled) AS n_enabled, COUNT(*) AS n_any,
         SUM(impressions) impressions, SUM(clicks) clicks, SUM(units) units,
         SAFE_DIVIDE(SUM(gross_profit), NULLIF(SUM(ad_spend),0)) AS net_roas,
         STRING_AGG(DISTINCT campaign_name, ', ' LIMIT 5) AS campaigns
  FROM `onyga-482313.OI.V_CAMPAIGN_ROLE` GROUP BY 1,2 /* ,3 */
),
suppressed AS (
  SELECT parent_name, strategy, intent_key FROM `onyga-482313.OI.DE_COVERAGE_EXPECTATION` WHERE is_active
)
SELECT
  t.parent_name, t.strategy, t.intent_key,
  COALESCE(l.n_enabled,0) n_enabled, COALESCE(l.n_any,0) n_any,
  l.impressions, l.clicks, l.units, l.net_roas, l.campaigns,
  s.parent_name IS NOT NULL AS suppressed,
  CASE WHEN s.parent_name IS NOT NULL THEN 'suppressed'
       WHEN COALESCE(l.n_enabled,0)=0 THEN 'missing'
       WHEN l.n_enabled>1 THEN 'redundant' ELSE 'ok' END AS status
FROM target t
LEFT JOIN live l USING (parent_name, strategy /*, intent_key */)
LEFT JOIN suppressed s USING (parent_name, strategy /*, intent_key */);
```

- [ ] **Step 2: Dry-run validate (no cost, catches column errors)**

```bash
bq query --use_legacy_sql=false --dry_run < scripts/bigquery/views/V_COVERAGE_CAMPAIGN.sql
```
Expected: succeeds. Fix any unresolved column against Task 0 notes.

- [ ] **Step 3: Create + invariant checks**

```bash
bq query --use_legacy_sql=false < scripts/bigquery/views/V_COVERAGE_CAMPAIGN.sql
bq query --use_legacy_sql=false \
'SELECT strategy, status, COUNT(*) n FROM `onyga-482313.OI.V_COVERAGE_CAMPAIGN` GROUP BY 1,2 ORDER BY 1,2'
```
Expected invariants: every row's `strategy` is one of the 6; no NULL `status`; `missing` count is
non-zero only where a target genuinely lacks a live campaign. Spot-check 3 `missing` rows against
Amazon reality before trusting.

- [ ] **Step 4: Register in `config.yaml` and commit**

```bash
git add scripts/bigquery/views/V_COVERAGE_CAMPAIGN.sql scripts/bigquery/tables/DE_COVERAGE_EXPECTATION.sql config.yaml
git commit -m "feat(cockpit): V_COVERAGE_CAMPAIGN + DE_COVERAGE_EXPECTATION (S1 backend)"
```

---

## Task 3: Endpoint — serve the strategy→family(→intent) tree

**Files:**
- Modify: `data-entry-app/app.py` (add `/api/daily-workflow`, near `ads_coverage_scan`)

- [ ] **Step 1: Add the endpoint** (reuse `@login_required`, `@cache_result`, the raw-BQ read pattern)

```python
@app.route('/api/daily-workflow')
@login_required
@cache_result(ttl_seconds=300)
def daily_workflow():
    rows = [dict(r) for r in bq_client.query(
        "SELECT parent_name, strategy, intent_key, status, suppressed, "
        "n_enabled, n_any, impressions, clicks, units, net_roas, campaigns "
        "FROM `onyga-482313.OI.V_COVERAGE_CAMPAIGN`").result()]
    STRATS = ['AUTO','INTENT','EXACT_BOOST','COMPETITOR','BRAND_DEFENSE','PRODUCT_DEFENSE']
    def roll(pred):  # per-strategy tile counts
        return {s: {
            'defined':   sum(1 for r in rows if r['strategy']==s and r['status']=='ok'),
            'missing':   sum(1 for r in rows if r['strategy']==s and r['status']=='missing'),
            'redundant': sum(1 for r in rows if r['strategy']==s and r['status']=='redundant'),
        } for s in STRATS}
    return jsonify({'strategies': STRATS, 'tiles': roll(None), 'cells': rows})
```

- [ ] **Step 2: Smoke test locally**

```bash
env -u CUBEJS_API_SECRET PORT=5050 venv/bin/python data-entry-app/app.py &
curl -s localhost:5050/api/daily-workflow | python3 -m json.tool | head -40
```
Expected: JSON with `tiles` (6 strategies, integer counts) and a `cells` array. Kill the server after.

---

## Task 4: React — strategy tiles (rung 1 rollup)

**Files:**
- Modify: `dashboard-react/src/pages/CoveragePage.tsx`
- Test: `dashboard-react/src/pages/CoveragePage.test.tsx` (create)

- [ ] **Step 1: Failing test for the tile rollup renderer**

```tsx
import { render, screen } from '@testing-library/react';
import { StrategyTile } from './CoveragePage';
test('tile shows defined/to-do/redundant counts', () => {
  render(<StrategyTile name="INTENT" c={{ defined: 12, missing: 3, redundant: 1 }} onOpen={() => {}} open={false} />);
  expect(screen.getByText(/12 defined/)).toBeInTheDocument();
  expect(screen.getByText(/3 to do/)).toBeInTheDocument();
});
```

- [ ] **Step 2: Run it, expect fail** — `cd dashboard-react && npx vitest run src/pages/CoveragePage.test.tsx` → FAIL (`StrategyTile` not exported).

- [ ] **Step 3: Add `StrategyTile` + fetch `/api/daily-workflow`** (keep today's colour language)

```tsx
const STRAT_LABEL: Record<string,string> = { AUTO:'Auto', INTENT:'Intent', EXACT_BOOST:'Exact Boost',
  COMPETITOR:'Competitor', BRAND_DEFENSE:'Brand Defense', PRODUCT_DEFENSE:'Product Defense' };
interface Tile { defined: number; missing: number; redundant: number; }

export function StrategyTile({ name, c, onOpen, open }:{ name:string; c:Tile; onOpen:()=>void; open:boolean }) {
  const tone = c.missing>0 ? 'border-red-500/40 bg-red-500/10' : c.redundant>0 ? 'border-amber-500/40 bg-amber-500/10' : 'border-emerald-500/50 bg-emerald-500/10';
  return (
    <button onClick={onOpen} className={`rounded-lg border px-4 py-3 text-left min-w-[150px] ${tone} ${open?'ring-2 ring-blue-400/60':''}`}>
      <div className="text-xs font-bold text-heading">{STRAT_LABEL[name] ?? name}</div>
      <div className="mt-1 text-[10px] font-semibold">
        <span className="text-emerald-400">✓ {c.defined} defined</span>
        {c.missing>0 && <span className="text-red-400"> · ✗ {c.missing} to do</span>}
        {c.redundant>0 && <span className="text-amber-400"> · ⚠ {c.redundant} redundant</span>}
      </div>
    </button>
  );
}
```
Replace the current `apiFetch('/api/coverage')` effect with `/api/daily-workflow`; render one `StrategyTile` per `data.strategies`, driven by `data.tiles[name]`.

- [ ] **Step 4: Run test, expect pass.**

- [ ] **Step 5: Commit** — `git commit -m "feat(cockpit): 6-strategy tiles on Coverage page (S1 rung 1)"`

---

## Task 5: React — tile → family × intent cell grid

**Files:**
- Modify: `dashboard-react/src/pages/CoveragePage.tsx`

- [ ] **Step 1: On tile open, render its `cells`** filtered to that strategy, grouped by `parent_name`, each cell a row using the existing `StatusPill` + `Metrics` components (reuse verbatim — they already map `ok/missing/redundant`). Show `intent_key` as the row label when present, else the family.

```tsx
{open && (
  <div className="mt-3 border border-border/40 rounded-lg p-4 space-y-1 text-xs max-w-[860px]">
    {cells.filter(c => c.strategy === open).map((c,i) => (
      <div key={i} className="flex items-center gap-2 py-1 border-b border-border-faint last:border-0">
        <span className="text-heading">{c.parent_name}{c.intent_key ? ` · ${c.intent_key}` : ''}</span>
        <span className="ml-auto"><Metrics c={c} /></span>
        <span className="w-[92px] text-right"><StatusPill c={c} /></span>
      </div>
    ))}
  </div>
)}
```

- [ ] **Step 2: Verify in the browser** — run the dashboard (`preview_start` the Vite dev server), open the cockpit, confirm tiles render, clicking Intent expands family×intent rows with correct pills. Screenshot for Ori.

- [ ] **Step 3: Commit** — `git commit -m "feat(cockpit): intent-cell grid under strategy tiles (S1 rung 1)"`

---

## Self-review checklist (run before handing off)

- Spec §3 (6 strategies) → Tasks 2,4. §4 Reconciler A (campaign presence + suppression) → Tasks 1,2.
  §6 backend spine items 2,4,5 → Tasks 1,2,3. §7 IA tiles+grid → Tasks 4,5. ✅ S1 rows covered.
- S1 explicitly **excludes**: Reconciler B / keyword grain (S3), reason/trace (S2), any apply/action (S4).
  Confirm no task added those.
- Fork from Task 0 Step 5 is respected: if (B) no campaign→intent linkage, Task 2/5 drop `intent_key`
  and ship family×strategy only — the plan still produces a working rung-1 cockpit.
