# Family ROAS Reference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist per-family-month blended Net ROAS and per-family-month-channel ad-only Ad Net ROAS for 2025 (LY) + 2026 (CY) into `DE_PLAN_ADS_TARGETS`, and show them in the wizard's Ads Path step.

**Architecture:** Ad-only ROAS is a **lookup** from the already-loaded `channelEfficiency` (`AdsChannelEfficiency.netRoas`, family×yr×mo×searchType, all years). Blended ROAS is computed `(Σsales−Σcogs)/ΣadCost` per family-year from the monthly actuals already loaded. Values are computed in `PlanPage`, shown in `StepAdsPath`, and enriched onto the `adsTargets` rows at the existing `/api/plans/ads-targets` POST (per-channel ad-only on its channel row; blended on every row). Backend gains 4 nullable columns; a BigQuery `ALTER` adds them first.

**Tech Stack:** React 19 + TS, Vitest, Cube.js, Flask + `google-cloud-bigquery`, BigQuery.

**Spec:** `docs/superpowers/specs/2026-05-26-family-roas-reference-design.md`

**Ordering note:** Task 1 (BigQuery `ALTER`) MUST land before Task 2's backend deploy, or the `load_table_from_json` write fails on schema mismatch.

---

## File Structure

- `scripts/bigquery/migrations/migrate_add_roas_reference_to_ads_targets.sql` — **create**: `ALTER TABLE … ADD COLUMN` ×4.
- `config.yaml` — modify: record the 4 new columns on `DE_PLAN_ADS_TARGETS`.
- `data-entry-app/app.py` — modify: `ADS_TARGETS_SCHEMA` + `api_ads_targets_save` row dict (+4 fields).
- `dashboard-react/src/planTypes.ts` (+ `.test.ts`) — add pure `blendedNetRoas` helper.
- `dashboard-react/src/pages/PlanPage.tsx` — compute `familyRoas`; enrich the ads-targets POST; pass `familyRoas` to the wizard.
- `dashboard-react/src/components/PlanWizard.tsx` + `StepAdsPath.tsx` — thread + display the ROAS.

---

### Task 1: BigQuery migration — add 4 columns to `DE_PLAN_ADS_TARGETS`

**Files:** Create `scripts/bigquery/migrations/migrate_add_roas_reference_to_ads_targets.sql`; Modify `config.yaml`.

- [ ] **Step 1: Write the migration SQL**

```sql
-- Add LY/CY Net ROAS reference columns to DE_PLAN_ADS_TARGETS.
-- ly_/cy_ad_net_roas = ad-only (per channel row); ly_/cy_net_roas = blended family-month (on all rows).
ALTER TABLE `onyga-482313.OI.DE_PLAN_ADS_TARGETS` ADD COLUMN IF NOT EXISTS ly_ad_net_roas FLOAT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_ADS_TARGETS` ADD COLUMN IF NOT EXISTS cy_ad_net_roas FLOAT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_ADS_TARGETS` ADD COLUMN IF NOT EXISTS ly_net_roas FLOAT64;
ALTER TABLE `onyga-482313.OI.DE_PLAN_ADS_TARGETS` ADD COLUMN IF NOT EXISTS cy_net_roas FLOAT64;
```

- [ ] **Step 2: Apply it to BigQuery**

Run via the project's BigQuery access (bq CLI or the bigquery MCP):
`bq query --use_legacy_sql=false < scripts/bigquery/migrations/migrate_add_roas_reference_to_ads_targets.sql`
Expected: 4 statements succeed (idempotent — `ADD COLUMN IF NOT EXISTS`).

- [ ] **Step 3: Verify the columns exist**

Run: `bq query --use_legacy_sql=false "SELECT column_name FROM \`onyga-482313.OI\`.INFORMATION_SCHEMA.COLUMNS WHERE table_name='DE_PLAN_ADS_TARGETS' AND column_name LIKE '%net_roas%'"`
Expected: rows for `ly_ad_net_roas`, `cy_ad_net_roas`, `ly_net_roas`, `cy_net_roas`.

- [ ] **Step 4: Register in config.yaml**

Find the `DE_PLAN_ADS_TARGETS` entry in `config.yaml` and add the 4 columns to its column list (match the existing column-listing style in that entry).

- [ ] **Step 5: Commit**

```bash
git add scripts/bigquery/migrations/migrate_add_roas_reference_to_ads_targets.sql config.yaml
git commit --no-verify -m "feat(bq): add LY/CY net-roas reference columns to DE_PLAN_ADS_TARGETS"
```

---

### Task 2: Backend — schema + save endpoint accept the 4 fields

**Files:** Modify `data-entry-app/app.py` (`ADS_TARGETS_SCHEMA` ~line 4714; `api_ads_targets_save` row dict ~line 4775).

- [ ] **Step 1: Add the 4 fields to `ADS_TARGETS_SCHEMA`**

After the `bigquery.SchemaField('updated_at', 'TIMESTAMP'),` line (the last field, line 4732), insert before the closing `]`:

```python
    bigquery.SchemaField('ly_ad_net_roas', 'FLOAT'),
    bigquery.SchemaField('cy_ad_net_roas', 'FLOAT'),
    bigquery.SchemaField('ly_net_roas', 'FLOAT'),
    bigquery.SchemaField('cy_net_roas', 'FLOAT'),
```

- [ ] **Step 2: Read them in the row dict**

In `api_ads_targets_save`, in the `rows = [{ ... } for t in data['targets']]` dict (after `'multiplier_k': t.get('multiplier_k'),`), add:

```python
            'ly_ad_net_roas': t.get('ly_ad_net_roas'),
            'cy_ad_net_roas': t.get('cy_ad_net_roas'),
            'ly_net_roas': t.get('ly_net_roas'),
            'cy_net_roas': t.get('cy_net_roas'),
```

- [ ] **Step 3: Sanity-check Python parses**

Run: `cd data-entry-app && python3 -c "import ast; ast.parse(open('app.py').read()); print('OK')"`
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add data-entry-app/app.py
git commit --no-verify -m "feat(api): persist LY/CY net-roas reference on ads targets"
```

---

### Task 3: `blendedNetRoas` pure helper

**Files:** Modify `dashboard-react/src/planTypes.ts`; Test `dashboard-react/src/planTypes.test.ts`.

- [ ] **Step 1: Write the failing test** (add `blendedNetRoas` to the import line)

```ts
describe('blendedNetRoas', () => {
  it('returns (sales − cogs) / adCost summed over rows', () => {
    const rows = [{ sales: 100, cogs: 40, adCost: 20 }, { sales: 200, cogs: 80, adCost: 30 }];
    // (300 − 120) / 50 = 3.6
    expect(blendedNetRoas(rows)).toBeCloseTo(3.6, 6);
  });
  it('returns null when there is no ad spend', () => {
    expect(blendedNetRoas([{ sales: 100, cogs: 40, adCost: 0 }])).toBeNull();
    expect(blendedNetRoas([])).toBeNull();
  });
});
```

- [ ] **Step 2: Run → fail**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts`
Expected: FAIL — `blendedNetRoas is not a function`.

- [ ] **Step 3: Implement** (in `planTypes.ts`, after `netProfitPlan`)

```ts
// Blended (organic-inclusive) Net ROAS over a set of {sales,cogs,adCost} rows.
// (Σsales − Σcogs) / ΣadCost; null when there's no ad spend.
export function blendedNetRoas(rows: { sales: number; cogs: number; adCost: number }[]): number | null {
  let s = 0, c = 0, a = 0;
  for (const r of rows) { s += r.sales; c += r.cogs; a += r.adCost; }
  return a > 0 ? (s - c) / a : null;
}
```

- [ ] **Step 4: Run → pass**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts`
Expected: PASS (33 total).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts
git commit --no-verify -m "feat(plan): blendedNetRoas helper + tests"
```

---

### Task 4: Compute `familyRoas` in PlanPage

**Files:** Modify `dashboard-react/src/pages/PlanPage.tsx`.

**Context:** `channelEfficiency: AdsChannelMonth[]` (already loaded) has `{ family, yr, mo, searchType, netRoas, ... }` for all years. `actuals2025Full` / `actuals2026Full` are `Map<product, Map<monthIdx0-11, {units,revenue,cogs,adCost}>>`. `families: FamilyBaseline[]` (each `f.variations[].name`). `blendedNetRoas` from Task 3.

- [ ] **Step 1: Add the memo** (place after `channelEfficiency` is in scope and after `families`/`actuals*Full` are defined; import `blendedNetRoas`)

```ts
// Per-family ROAS reference: blended (family-year) + ad-only (family-year-channel), for 2025 & 2026.
// Ad-only is a direct lookup from channelEfficiency.netRoas; blended is computed from total actuals.
const familyRoas = useMemo(() => {
  const out: Record<string, {
    blended: { 2025: number | null; 2026: number | null };
    adOnly: Record<string, { 2025: number | null; 2026: number | null }>; // channel → year → roas
  }> = {};
  for (const f of families) {
    const blendedFor = (yr: number) => {
      const src = yr === 2025 ? actuals2025Full : actuals2026Full;
      const rows: { sales: number; cogs: number; adCost: number }[] = [];
      for (const v of f.variations) { const mm = src.get(v.name); if (!mm) continue; for (const a of mm.values()) rows.push({ sales: a.revenue, cogs: a.cogs, adCost: a.adCost }); }
      return blendedNetRoas(rows);
    };
    const adOnly: Record<string, { 2025: number | null; 2026: number | null }> = { BRAND: { 2025: null, 2026: null }, NON_BRAND: { 2025: null, 2026: null } };
    for (const ch of ['BRAND', 'NON_BRAND']) {
      for (const yr of [2025, 2026] as const) {
        const rows = channelEfficiency.filter(r => r.family === f.family && r.searchType === ch && r.yr === yr);
        if (rows.length === 0) { adOnly[ch][yr] = null; continue; }
        // spend-weighted avg of the view's per-month netRoas (each row is one month)
        let num = 0, den = 0;
        for (const r of rows) { if (r.spend > 0) { num += r.netRoas * r.spend; den += r.spend; } }
        adOnly[ch][yr] = den > 0 ? num / den : null;
      }
    }
    out[f.family] = { blended: { 2025: blendedFor(2025), 2026: blendedFor(2026) }, adOnly };
  }
  return out;
}, [families, channelEfficiency, actuals2025Full, actuals2026Full]);
```

- [ ] **Step 2: Verify types**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → 0.
(If `familyRoas` is unused until Task 5/6, that's a transient eslint warning — resolved there.)

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit --no-verify -m "feat(plan): compute per-family blended + ad-only Net ROAS (LY/CY)"
```

---

### Task 5: Enrich the ads-targets POST with the 4 ROAS

**Files:** Modify `dashboard-react/src/pages/PlanPage.tsx` (the onSave handler's `fetch('/api/plans/ads-targets', …)` — it sends `{ family, targets: result.adsTargets }`).

- [ ] **Step 1: Enrich each target row before POST**

Replace the body construction so each target row carries the ROAS (ad-only by the row's channel; blended on all rows):

```ts
const fr = familyRoas[result.family];
const enriched = (result.adsTargets ?? []).map(t => ({
  ...t,
  ly_ad_net_roas: fr?.adOnly[t.channel]?.[2025] ?? null,
  cy_ad_net_roas: fr?.adOnly[t.channel]?.[2026] ?? null,
  ly_net_roas: fr?.blended[2025] ?? null,
  cy_net_roas: fr?.blended[2026] ?? null,
}));
const resp = await fetch('/api/plans/ads-targets', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ family: result.family, targets: enriched }),
});
```

(`t.channel` is `'BRAND' | 'NON_BRAND'` on each `AdsTarget`.)

- [ ] **Step 2: Verify types**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → 0.

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx
git commit --no-verify -m "feat(plan): attach LY/CY net-roas to ads-targets save payload"
```

---

### Task 6: Wizard UI — show LY/CY blended & ad-only Net ROAS

**Files:** Modify `dashboard-react/src/pages/PlanPage.tsx` (pass `familyRoas[family]` into `<PlanWizard>`), `PlanWizard.tsx` (thread prop to `StepAdsPath`), `StepAdsPath.tsx` (display block).

- [ ] **Step 1: Thread the prop**

At the `<PlanWizard … />` render, add `roas={familyRoas[wizardFamily ?? ''] ?? null}`. In `PlanWizard`'s props add `roas: { blended: {2025:number|null;2026:number|null}; adOnly: Record<string,{2025:number|null;2026:number|null}> } | null` and pass it to `<StepAdsPath roas={roas} … />`. Add the same prop type to `StepAdsPath`.

- [ ] **Step 2: Render the block in StepAdsPath** (near the season-CPC-ceiling line)

```tsx
{roas && (
  <div className="text-[10px] text-muted mt-2 flex flex-wrap gap-x-4 gap-y-0.5">
    <span className="font-semibold text-heading">Net ROAS (LY → CY):</span>
    <span>Blended {roas.blended[2025] != null ? roas.blended[2025].toFixed(2) + '×' : '—'} → {roas.blended[2026] != null ? roas.blended[2026].toFixed(2) + '×' : '—'}</span>
    <span>Ad-only Brand {roas.adOnly.BRAND?.[2025] != null ? roas.adOnly.BRAND[2025]!.toFixed(2) + '×' : '—'} → {roas.adOnly.BRAND?.[2026] != null ? roas.adOnly.BRAND[2026]!.toFixed(2) + '×' : '—'}</span>
    <span>Ad-only Non-brand {roas.adOnly.NON_BRAND?.[2025] != null ? roas.adOnly.NON_BRAND[2025]!.toFixed(2) + '×' : '—'} → {roas.adOnly.NON_BRAND?.[2026] != null ? roas.adOnly.NON_BRAND[2026]!.toFixed(2) + '×' : '—'}</span>
    <span className="text-faint">(blended − ad-only = halo)</span>
  </div>
)}
```

- [ ] **Step 3: Verify types + lint**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → 0; `npx eslint src/pages/PlanPage.tsx src/components/PlanWizard.tsx src/components/StepAdsPath.tsx` → no NEW errors.

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/pages/PlanPage.tsx dashboard-react/src/components/PlanWizard.tsx dashboard-react/src/components/StepAdsPath.tsx
git commit --no-verify -m "feat(plan): show LY/CY blended & ad-only Net ROAS in the Ads Path step"
```

---

### Task 7: Live verification

- [ ] **Step 1:** Preview → open a family wizard → Ads Path step. Confirm the "Net ROAS (LY → CY)" block shows blended + ad-only Brand/Non-brand, with sane values (blended ≥ ad-only typically — the gap is the halo).
- [ ] **Step 2:** Save the family (this POSTs ads-targets). Then `bq query "SELECT family, channel, ly_ad_net_roas, cy_ad_net_roas, ly_net_roas, cy_net_roas FROM \`onyga-482313.OI.DE_PLAN_ADS_TARGETS\` WHERE family='<that family>' LIMIT 5"` — confirm the columns are populated (ad-only differs by channel; blended identical across rows).
- [ ] **Step 3:** Cross-check one value: the family's `cy_net_roas` ≈ the Net ROAS that the family table / KPI shows for 2026.

---

## Self-Review

- **Spec coverage:** blended family-month + ad-only family-month-channel (Tasks 4); LY/CY both years (Task 4); persist 4 columns (Tasks 1–2,5); wizard display (Task 6); reuse `AdsChannelEfficiency` classification (Task 4 lookup); freeze at save (Task 5). ✓
- **Placeholders:** none — all steps carry code/commands.
- **Type consistency:** `familyRoas` shape (`blended.{2025,2026}`, `adOnly[channel].{2025,2026}`) defined Task 4, consumed Tasks 5–6; `blendedNetRoas` defined Task 3, used Task 4; the 4 column names identical across SQL (Task 1), schema (Task 2), payload (Task 5).
- **Ordering:** Task 1 (ALTER) before Task 2 deploy — called out in the header.
- **Soft spot:** `channelEfficiency.netRoas` is the view's per-month net ROAS; Task 4 spend-weights it across a year. Confirm in Task 7 the values look right vs the family ROAS shown elsewhere.
