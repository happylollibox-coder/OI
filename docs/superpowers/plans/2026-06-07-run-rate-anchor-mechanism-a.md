# Run-Rate Forecast Anchor (Mechanism A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the wizard's stale 2025 forecast anchor with a **weighted run-rate × last-year seasonal shape** model for Mature + New families, driving both the Step 2 Growth display (kills the +98,900% / 8.3M explosion) and the Step 3 Ads Path order anchor (fixes the ~9/day under-call).

**Architecture:** Three pure builders in `planTypes.ts` (`weightedRunRate`, `detectLaunchMonth`, `seasonalShape`). PlanPage computes a per-product weighted run-rate (reusing the already-loaded weekly actuals) and a per-family 2025 monthly-units map, and passes both into the wizard. PlanWizard builds the per-family shape once and a `(anchorUnits, anchorSpend)` pair = run-rate × days × shape; StepAdsPath's profit-max engine consumes that anchor (its truthful "2025 baseline" callout is left untouched); StepGrowth projects future months as `channel recentRate × days × shape` (removing the `LY × growth` explosion path). Just-launched families (no clean own 2025 month) fall through to a conservative own-run-rate × reference shape — never exploding.

**Tech Stack:** React 19 + TypeScript (strict) + Vite + Vitest; Cube.js → BigQuery (`V_UNIFIED_DAILY` via the `UnifiedPerformance` cube).

**Conventions for every commit in this plan (session-specific, IMPORTANT):**
- Run node tools via nvm: prefix with `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH"`.
- `git add` ONLY the exact files named in the step — NEVER `git add -A`/`.` (the working tree has ~25 unrelated in-flight files).
- Commit with `--no-verify` (a repo-wide pre-existing eslint husky hook would otherwise block).
- The Vite preview ("Vite Dashboard") + Cube (:4000) are already running for live checks.

---

## File Structure

- `dashboard-react/src/planTypes.ts` — **modify**: add `weightedRunRate`, `detectLaunchMonth`, `seasonalShape` (pure, exported).
- `dashboard-react/src/planTypes.test.ts` — **modify**: add unit tests for the three builders.
- `dashboard-react/src/pages/PlanPage.tsx` — **modify**: build `runRateMap` (from `actualsWeekly`) + `familyMonthly2025` (from `actuals2025Full`); pass both to `<PlanWizard>`.
- `dashboard-react/src/components/PlanWizard.tsx` — **modify**: new props; compute family run-rate + `shape` + `anchorUnits`/`anchorSpend`; pass anchor to `StepAdsPath`, `shape` to `StepGrowth`; replace StepGrowth's projection + footnote.
- `dashboard-react/src/components/StepAdsPath.tsx` — **modify**: accept `anchorUnits`/`anchorSpend`; the profit-max plan uses the anchor instead of the raw 2025 arrays (the "2025 baseline" callout keeps the real-2025 arrays).

---

## Task 1: `weightedRunRate` builder

Recency-weighted daily rate from the last 4 complete weekly totals (28 days = 4×7; the spec explicitly allows deriving from the existing weekly actuals rather than a new daily query).

**Files:**
- Modify: `dashboard-react/src/planTypes.ts`
- Test: `dashboard-react/src/planTypes.test.ts`

- [ ] **Step 1: Write the failing test**

Add to `src/planTypes.test.ts` (import line + new describe block):

```ts
// add `weightedRunRate` to the existing planTypes import at top of the file
describe('weightedRunRate', () => {
  it('returns a flat per-day rate for uniform weeks', () => {
    // every week = 70 units (10/day); weights sum to 1 → 10/day
    expect(weightedRunRate([70, 70, 70, 70])).toBeCloseTo(10, 6);
  });
  it('weights the most recent week most heavily', () => {
    // only the most recent week has volume (70 = 10/day); rest 0 → 0.4 * 10 = 4
    expect(weightedRunRate([70, 0, 0, 0])).toBeCloseTo(4, 6);
    // only the oldest of 4 → 0.1 * 10 = 1
    expect(weightedRunRate([0, 0, 0, 70])).toBeCloseTo(1, 6);
  });
  it('treats missing buckets as 0 (fewer than 4 weeks)', () => {
    // one week of 70 (10/day) in the most-recent slot → 0.4 * 10 = 4
    expect(weightedRunRate([70])).toBeCloseTo(4, 6);
    expect(weightedRunRate([])).toBe(0);
  });
  it('accepts custom weights', () => {
    expect(weightedRunRate([7, 7], [0.5, 0.5])).toBeCloseTo(1, 6);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts -t weightedRunRate`
Expected: FAIL — `weightedRunRate is not a function` / import error.

- [ ] **Step 3: Write the minimal implementation**

Append to `src/planTypes.ts`:

```ts
// Recency-weighted daily run-rate from the last N complete weekly totals.
// weeklyTotals[0] = most recent complete week's total, [1] = the week before, …
// Default weights bias the last 4 weeks 40/30/20/10. Each week is 7 days, so dividing
// every bucket by 7 yields a per-day rate; missing buckets contribute 0.
export function weightedRunRate(weeklyTotals: number[], weights: number[] = [0.4, 0.3, 0.2, 0.1]): number {
  let rate = 0;
  for (let i = 0; i < weights.length; i++) rate += weights[i] * ((weeklyTotals[i] ?? 0) / 7);
  return rate;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts -t weightedRunRate`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI && git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts
git commit --no-verify -m "feat(plan): weightedRunRate builder (4-week recency-weighted daily rate)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `detectLaunchMonth` builder

Decides whether a family's 2025 history is a launch ramp (so its first 3 months get excluded) — and crucially returns `null` for a mature family whose data simply starts in January.

**Files:**
- Modify: `dashboard-react/src/planTypes.ts`
- Test: `dashboard-react/src/planTypes.test.ts`

- [ ] **Step 1: Write the failing test**

Add to `src/planTypes.test.ts` (add `detectLaunchMonth` to the import):

```ts
describe('detectLaunchMonth', () => {
  const lollibox = [745, 891, 1058, 2040, 898, 666, 481, 692, 972, 944, 2066, 6225]; // full year
  const lollime  = [0, 0, 0, 0, 0, 0, 354, 520, 843, 983, 2929, 7620];               // launches Jul
  it('returns null for a mature family with January sales', () => {
    expect(detectLaunchMonth(lollibox)).toBeNull();
  });
  it('returns the launch month when 2025 starts mid-year', () => {
    expect(detectLaunchMonth(lollime)).toBe(7);
  });
  it('returns null when there is no 2025 data at all', () => {
    expect(detectLaunchMonth(Array(12).fill(0))).toBeNull();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts -t detectLaunchMonth`
Expected: FAIL — `detectLaunchMonth is not a function`.

- [ ] **Step 3: Write the minimal implementation**

Append to `src/planTypes.ts`:

```ts
// The launch month (1-based) for a family's 2025 monthly-units array, or null when the
// family is mature / has no data. A family with January sales (first-sale month === 1) is
// treated as mature (no launch ramp) — this avoids mis-flagging a mature product whose data
// window merely starts in January. `own[i]` is month i+1's 2025 total units.
export function detectLaunchMonth(own: number[], floor = 5): number | null {
  let first: number | null = null;
  for (let i = 0; i < 12; i++) if ((own[i] ?? 0) > floor) { first = i + 1; break; }
  if (first == null || first === 1) return null;
  return first;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts -t detectLaunchMonth`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI && git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts
git commit --no-verify -m "feat(plan): detectLaunchMonth (mature vs launch-ramp discriminator)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `seasonalShape` builder

The 12-month multiplier normalized so the current month = 1: own clean months kept, the rest (incl. the current-month anchor) stitched from a reference family.

**Files:**
- Modify: `dashboard-react/src/planTypes.ts`
- Test: `dashboard-react/src/planTypes.test.ts`

- [ ] **Step 1: Write the failing test**

Add to `src/planTypes.test.ts` (add `seasonalShape` to the import):

```ts
describe('seasonalShape', () => {
  const lollibox = [745, 891, 1058, 2040, 898, 666, 481, 692, 972, 944, 2066, 6225];
  const lollime  = [0, 0, 0, 0, 0, 0, 354, 520, 843, 983, 2929, 7620];
  const empty    = Array(12).fill(0);

  it('current month is always 1', () => {
    expect(seasonalShape(lollibox, lollibox, 6, null)[5]).toBeCloseTo(1, 6);
    expect(seasonalShape(lollime, lollibox, 6, 7)[5]).toBeCloseTo(1, 6);
  });

  it('mature family uses its own shape (reference unused)', () => {
    const s = seasonalShape(lollibox, lollibox, 6, null);
    expect(s[11]).toBeCloseTo(6225 / 666, 4); // Dec/Jun ≈ 9.35
    expect(s[6]).toBeCloseTo(481 / 666, 4);    // Jul/Jun
  });

  it('new family keeps own Oct-Dec peak, borrows June anchor from reference', () => {
    const s = seasonalShape(lollime, lollibox, 6, 7); // clean own = Oct,Nov,Dec
    // a = mean(983/944, 2929/2066, 7620/6225) ≈ 1.228 ; u[Jun] = a*666 ≈ 818
    expect(s[11]).toBeGreaterThan(8.5);  // Dec ≈ 9.3 (finite, not 21x, not exploding)
    expect(s[11]).toBeLessThan(10);
    expect(s[10]).toBeCloseTo(2929 / (1.228 * 666), 1); // Nov uses own value
  });

  it('brand-new family (no clean own months) falls back to pure reference shape', () => {
    const s = seasonalShape(empty, lollibox, 6, null);
    expect(s[11]).toBeCloseTo(6225 / 666, 4); // = reference shape
    expect(s[5]).toBeCloseTo(1, 6);
  });

  it('never produces NaN when reference current month is also 0', () => {
    const s = seasonalShape(empty, empty, 6, null);
    expect(s.every(x => Number.isFinite(x))).toBe(true);
    expect(s[5]).toBe(1);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts -t seasonalShape`
Expected: FAIL — `seasonalShape is not a function`.

- [ ] **Step 3: Write the minimal implementation**

Append to `src/planTypes.ts`:

```ts
// 12-month seasonal multiplier `s` for a family, normalized so s[currentMonth-1] === 1.
// own/ref are 2025 monthly-units arrays (index 0 = January). A month is a "clean own month"
// when its own units exceed `floor` AND it is past the launch ramp (launchMonth+3); launchMonth
// null means mature (no ramp exclusion). The reference (most-mature full-year family) fills every
// non-clean month — including the current-month anchor — scaled to the family's level by
// a = mean(own/ref) over the clean overlap. Mature → pure own shape; brand-new → pure reference.
export function seasonalShape(
  own: number[],
  ref: number[],
  currentMonth: number,   // 1-based
  launchMonth: number | null,
  floor = 5,
): number[] {
  const clean = own.map((v, i) => v > floor && (launchMonth == null || (i + 1) >= launchMonth + 3));
  let aNum = 0, aCnt = 0;
  for (let i = 0; i < 12; i++) if (clean[i] && (ref[i] ?? 0) > 0) { aNum += own[i] / ref[i]; aCnt++; }
  const a = aCnt ? aNum / aCnt : 1;
  const u = own.map((v, i) => (clean[i] ? v : a * (ref[i] ?? 0)));
  const ucm = u[currentMonth - 1];
  return u.map((x, i) => (ucm > 0 ? x / ucm : (i === currentMonth - 1 ? 1 : 0)));
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/planTypes.test.ts -t seasonalShape`
Expected: PASS (5 tests). Then run the whole file: `npx vitest run src/planTypes.test.ts` → all green.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI && git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts
git commit --no-verify -m "feat(plan): seasonalShape builder (own clean months + reference stitch)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: PlanPage — run-rate map + family 2025 shape inputs, passed to the wizard

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx`

- [ ] **Step 1: Import the new builder**

In `src/pages/PlanPage.tsx`, extend the existing `planTypes` import (currently `import { composeMonthlyPlan, … MONTH_ABBR } from '../planTypes';`) to also import `weightedRunRate`:

```ts
import { composeMonthlyPlan, aggregateAdsTargetSpend, buildEffectiveProjs, monthFractions, sumOverPeriod, netProfitPlan, latestCompleteWeekRange, blendedNetRoas, MONTH_ABBR, weightedRunRate } from '../planTypes';
```

- [ ] **Step 2: Compute `runRateMap` and `familyMonthly2025`**

Add these two `useMemo`s. Put them just after the `families` memo (currently `const families = useMemo(() => isLoading ? [] : buildFamilyBaselines(data, inv, metaMap), [...]);` at ~L1118). `actualsWeekly`, `actuals2025Full`, and `latestDataDate` are already in scope (the run-rate reuses the weekly actuals — no new query):

```tsx
  // Per-product weighted run-rate (units/day, ad-spend/day) from the last 4 COMPLETE weeks of
  // actualsWeekly. Recency-weighted 40/30/20/10. Drives the new forecast anchor.
  const runRateMap = useMemo(() => {
    const m = new Map<string, { unitsPerDay: number; spendPerDay: number }>();
    if (!latestDataDate) return m;
    for (const [prod, weeks] of actualsWeekly) {
      const complete = Array.from(weeks.entries())
        .filter(([ws]) => { const end = new Date(ws + 'T00:00:00'); end.setDate(end.getDate() + 6); return end <= latestDataDate; })
        .sort((a, b) => b[0].localeCompare(a[0]))   // most recent week first
        .slice(0, 4);
      m.set(prod, {
        unitsPerDay: weightedRunRate(complete.map(([, w]) => w.units)),
        spendPerDay: weightedRunRate(complete.map(([, w]) => w.adCost)),
      });
    }
    return m;
  }, [actualsWeekly, latestDataDate]);

  // Per-family 2025 monthly total units (index 0 = Jan) — the own/reference inputs for the shape.
  const familyMonthly2025 = useMemo(() => {
    const out: Record<string, number[]> = {};
    for (const fam of families) {
      const arr = Array(12).fill(0) as number[];
      for (const v of fam.variations) {
        const pm = actuals2025Full.get(v.name);
        if (!pm) continue;
        for (let mo = 0; mo < 12; mo++) arr[mo] += pm.get(mo)?.units ?? 0;
      }
      out[fam.family] = arr;
    }
    return out;
  }, [families, actuals2025Full]);
```

- [ ] **Step 3: Pass the two new props to `<PlanWizard>`**

In the `<PlanWizard …>` render (~L2169), add the two props next to the existing `latestDataDate={latestDataDate}`:

```tsx
          latestDataDate={latestDataDate}
          runRateMap={runRateMap}
          familyMonthly2025={familyMonthly2025}
```

- [ ] **Step 4: Typecheck (props will error until Task 5 adds them — expected)**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit 2>&1 | grep -i "PlanPage\|PlanWizard" | head`
Expected: only errors about `runRateMap`/`familyMonthly2025` not existing on the PlanWizard props — resolved in Task 5. No other PlanPage errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI && git add dashboard-react/src/pages/PlanPage.tsx
git commit --no-verify -m "feat(plan): PlanPage computes run-rate map + family 2025 shape inputs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: PlanWizard — build shape + anchor, thread to both steps

**Files:**
- Modify: `dashboard-react/src/components/PlanWizard.tsx`

- [ ] **Step 1: Import the builders**

Extend the `planTypes` import (currently `import { MFR, SHIP, allocateOrder, splitTrajectoryToProducts, monthKey, offSeasonTrend, dataCutoffDay } from '../planTypes';`) to add `seasonalShape, detectLaunchMonth`:

```ts
import { MFR, SHIP, allocateOrder, splitTrajectoryToProducts, monthKey, offSeasonTrend, dataCutoffDay, seasonalShape, detectLaunchMonth } from '../planTypes';
```

- [ ] **Step 2: Add the two props to the `Props` interface**

In the `interface Props { … }` block, add after `latestDataDate?: Date | null;`:

```ts
  runRateMap: Map<string, { unitsPerDay: number; spendPerDay: number }>;
  familyMonthly2025: Record<string, number[]>;
```

- [ ] **Step 3: Destructure the new props**

In the `export function PlanWizard({ … }: Props)` parameter list, add `runRateMap, familyMonthly2025` (e.g. after `latestDataDate`):

```ts
export function PlanWizard({ family: f, months, demandMap, metaMap, seasonMap, adsEfficiency, projs, growthOverrides: initGrowth, actuals2025, actuals2026, brandedSearch, channelEfficiency, roas, latestDataDate, runRateMap, familyMonthly2025, onSave, onClose }: Props) {
```

- [ ] **Step 4: Compute family run-rate, shape, and the anchor**

Immediately AFTER the existing `monthlySpend2025` useMemo (ends at ~L130), add:

```tsx
  // ── Run-rate × seasonal-shape anchor (replaces the stale 2025 anchor for the profit-max plan) ──
  const familyRun = useMemo(() => {
    let unitsPerDay = 0, spendPerDay = 0;
    for (const v of f.variations) {
      const rr = runRateMap.get(v.name);
      if (rr) { unitsPerDay += rr.unitsPerDay; spendPerDay += rr.spendPerDay; }
    }
    return { unitsPerDay, spendPerDay };
  }, [runRateMap, f.variations]);

  const shape = useMemo(() => {
    const own = familyMonthly2025[f.family] ?? Array(12).fill(0);
    const ref = familyMonthly2025['Lollibox'] ?? Array(12).fill(0);
    const cm = new Date().getMonth() + 1;
    return seasonalShape(own, ref, cm, detectLaunchMonth(own));
  }, [familyMonthly2025, f.family]);

  // anchorUnits[mo] = run-rate units/day × days-in-month × shape (shape[currentMonth] = 1).
  const anchorUnits = useMemo(
    () => Array.from({ length: 12 }, (_, i) => familyRun.unitsPerDay * new Date(2026, i + 1, 0).getDate() * shape[i]),
    [familyRun, shape]);
  const anchorSpend = useMemo(
    () => Array.from({ length: 12 }, (_, i) => familyRun.spendPerDay * new Date(2026, i + 1, 0).getDate() * shape[i]),
    [familyRun, shape]);
```

- [ ] **Step 5: Pass `anchorUnits`/`anchorSpend` to StepAdsPath and `shape` to StepGrowth**

In the step-3 render (~L259) add `anchorUnits={anchorUnits} anchorSpend={anchorSpend}` (keep `monthlyUnits={monthlyUnits2025} monthlySpend={monthlySpend2025}` — those stay for the truthful 2025 baseline callout):

```tsx
          {step === 3 && <StepAdsPath famEff={famEff} path={adsPath} onPath={setAdsPath} customDaily={customDaily} onCustom={setCustomDaily} totals={pathTotals} channelData={channelData} months={months} asp={f.asp} costPerUnit={f.costPerUnit} monthlyUnits={monthlyUnits2025} monthlySpend={monthlySpend2025} anchorUnits={anchorUnits} anchorSpend={anchorSpend} roas={roas} latestDataDate={latestDataDate} onTargets={setAdsTargets} onTrajectory={setTrajectory} />}
```

In the step-2 render (~L257) add `shape={shape}`:

```tsx
          {step === 2 && <StepGrowth products={products} months={months} demandMap={demandMap} actuals2025={actuals2025} actuals2026={actuals2026} brandedSearch={brandedSearch} family={f.family} seasonMap={seasonMap} latestDataDate={latestDataDate} shape={shape} onGrowthChange={setBrandGrowth} />}
```

- [ ] **Step 6: Typecheck (StepAdsPath/StepGrowth props error until Tasks 6–7 — expected)**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit 2>&1 | grep -i "PlanWizard\|StepAdsPath\|StepGrowth\|PlanPage" | head`
Expected: errors only about `anchorUnits`/`anchorSpend` (StepAdsPath) and `shape` (StepGrowth) not yet in their prop types; PlanPage's earlier errors are now gone.

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI && git add dashboard-react/src/components/PlanWizard.tsx
git commit --no-verify -m "feat(plan): wizard builds run-rate x shape anchor; threads to both steps

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: StepAdsPath — profit-max plan uses the run-rate anchor

The profit-max engine (`profitMaxPlan`) switches from the raw 2025 arrays to `anchorUnits`/`anchorSpend`. The `baseline2025` callout (the "2025 → recommended" line) keeps using `monthlyUnits`/`monthlySpend` so it still shows what 2025 actually did.

**Files:**
- Modify: `dashboard-react/src/components/StepAdsPath.tsx`

- [ ] **Step 1: Add the two anchor props to the signature**

In `export function StepAdsPath({ …, monthlyUnits, monthlySpend, roas, latestDataDate, onTargets, onTrajectory }: {` add `anchorUnits, anchorSpend` to the destructure and the inline type (after the `monthlySpend?` lines):

```ts
export function StepAdsPath({ famEff, path, onPath, customDaily, onCustom, totals, channelData, months, asp, costPerUnit, monthlyUnits, monthlySpend, anchorUnits, anchorSpend, roas, latestDataDate, onTargets, onTrajectory }: {
```

and in the prop type block, after the `monthlySpend?: number[];` line:

```ts
  monthlyUnits?: number[]; // total units (organic+ad) per calendar month, prior year — for the 2025 baseline callout
  monthlySpend?: number[]; // prior-year ad spend per calendar month — for the 2025 baseline callout
  anchorUnits?: number[];  // run-rate × shape units per calendar month — anchors the profit-max curve
  anchorSpend?: number[];  // run-rate × shape ad spend per calendar month — anchors the profit-max curve
```

- [ ] **Step 2: Point the profit-max anchor at the run-rate arrays**

In the `profitMaxPlan` useMemo (~L290–306), change the two anchor reads (currently `monthlyUnits?.[i]` / `monthlySpend?.[i]`) to the anchor arrays:

```ts
      const u0 = anchorUnits?.[i] ?? 0;
      const s0 = anchorSpend?.[i] ?? 0;
```

and update that memo's dependency array — replace `monthlyUnits, monthlySpend` with `anchorUnits, anchorSpend` in the deps list at the end of the `profitMaxPlan` memo (the line containing `}, [monthlyUnits, monthlySpend, margin, seasonBenchmarks, baseAdsShare]);`):

```ts
  }, [anchorUnits, anchorSpend, margin, seasonBenchmarks, baseAdsShare]);
```

(Leave `baseline2025` at ~L342–346 untouched — it intentionally keeps `monthlyUnits`/`monthlySpend` = real 2025.)

- [ ] **Step 3: Typecheck**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit 2>&1 | grep -i "StepAdsPath\|PlanWizard" | head`
Expected: no StepAdsPath errors (StepGrowth's `shape` error may remain until Task 7).

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI && git add dashboard-react/src/components/StepAdsPath.tsx
git commit --no-verify -m "feat(plan): profit-max anchor uses run-rate x shape (2025 baseline callout intact)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: StepGrowth — project future months as run-rate × shape (remove the explosion)

**Files:**
- Modify: `dashboard-react/src/components/PlanWizard.tsx` (the `StepGrowth` function lives here)

- [ ] **Step 1: Add the `shape` prop to StepGrowth's signature**

In `function StepGrowth({ products, months, demandMap, actuals2025, actuals2026, brandedSearch, family, seasonMap, latestDataDate, onGrowthChange }: {` add `shape` and its type:

```ts
function StepGrowth({ products, months, demandMap, actuals2025, actuals2026, brandedSearch, family, seasonMap, latestDataDate, shape, onGrowthChange }: {
  products: FamilyBaseline['variations']; months: MonthDef[];
  demandMap: ForecastDemandMap; actuals2025: ActualsMap; actuals2026: ActualsMap;
  brandedSearch: BrandedSearchMonth[]; family: string;
  seasonMap: Record<string, Record<number, { peakDays: number; offseasonDays: number }>>;
  latestDataDate?: Date | null;
  shape: number[];
  onGrowthChange: (g: number) => void;
}) {
```

- [ ] **Step 2: Replace the current-month-remaining projection**

In the `brandComparison` memo, the `m === currentMonth` branch currently reads:

```ts
        const bRemaining = noUsableBase(bLy, brandTrend, m)
          ? Math.round(brandTrend.recentRate * daysRemaining) : Math.round(bLy * (1 - prorateFactor) * brandGrowth);
        const nbRemaining = noUsableBase(nbLy, nbTrend, m)
          ? Math.round(nbTrend.recentRate * daysRemaining) : Math.round(nbLy * (1 - prorateFactor) * nbGrowth);
```

Replace BOTH lines with (run-rate × remaining days; shape[currentMonth] = 1):

```ts
        const bRemaining = Math.round(brandTrend.recentRate * daysRemaining);
        const nbRemaining = Math.round(nbTrend.recentRate * daysRemaining);
```

- [ ] **Step 3: Replace the future-month projection**

The `else` (future-month) branch currently reads:

```ts
        const bLy = (d25?.purchases ?? 0) + (d25?.adsUnits ?? 0);
        const nbLy = (d25?.totalSqpPurchases ?? 0) + (d25?.totalAdsUnits ?? 0) - bLy;
        const bProj = noUsableBase(bLy, brandTrend, m)
          ? brandTrend.forecastUnits(2026, m) : Math.round(bLy * brandGrowth);
        const nbProj = noUsableBase(nbLy, nbTrend, m)
          ? nbTrend.forecastUnits(2026, m) : Math.round(nbLy * nbGrowth);
```

Replace with (each channel's current daily rate × days × the family seasonal shape — no `LY × growth`, so peak months can't explode):

```ts
        const daysInM = new Date(2026, m, 0).getDate();
        const bProj = Math.round(brandTrend.recentRate * daysInM * (shape[m - 1] ?? 1));
        const nbProj = Math.round(nbTrend.recentRate * daysInM * (shape[m - 1] ?? 1));
```

- [ ] **Step 4: Add `shape` to the `brandComparison` dependency array**

The memo's deps line (currently `}, [brandedSearch, family, latestDataDate]);`) becomes:

```ts
  }, [brandedSearch, family, latestDataDate, shape]);
```

- [ ] **Step 5: Remove the now-unused `noUsableBase` helper**

`noUsableBase` is no longer referenced. Delete its definition (the `const ordOf = …` line and the `const noUsableBase = (…) => … ;` block, ~L461–464 inside the memo) to avoid an unused-var lint error. Leave `ordOf` only if it's referenced elsewhere — verify with: `grep -n "ordOf\|noUsableBase" src/components/PlanWizard.tsx`; remove whichever becomes unused.

- [ ] **Step 6: Update the forecast footnote**

The footnote (~L834) currently shows the raw YoY growth %:

```tsx
              {brandComparison.periodLabel} compared YoY (prorated). <span className="italic text-blue-400/70">Blue italic = forecast (Brand {brandComparison.brandGrowthPct > 0 ? '+' : ''}{brandComparison.brandGrowthPct.toFixed(0)}% · Non-brand {brandComparison.nbGrowthPct > 0 ? '+' : ''}{brandComparison.nbGrowthPct.toFixed(0)}%)</span>
```

Replace the trailing `<span>` so it describes the new method (no misleading +98,900%):

```tsx
              {brandComparison.periodLabel} compared YoY (prorated). <span className="italic text-blue-400/70">Blue italic = forecast (recent run-rate × last-year seasonal shape)</span>
```

- [ ] **Step 7: Typecheck + run the unit tests**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit`
Expected: clean (0 errors).
Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run`
Expected: all green.

- [ ] **Step 8: Commit**

```bash
cd /Users/ori/Develop/OI && git add dashboard-react/src/components/PlanWizard.tsx
git commit --no-verify -m "feat(plan): StepGrowth projects run-rate x shape (removes YoY explosion)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Live verification across the three maturity tiers

**Files:** none (verification only).

- [ ] **Step 1: Confirm no new lint regressions on touched files**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx eslint src/planTypes.ts src/planTypes.test.ts src/components/PlanWizard.tsx src/components/StepAdsPath.tsx 2>&1 | tail -4`
Expected: problem count unchanged from the pre-existing baseline (12 on these files at session start) — no NEW errors. PlanPage.tsx has a known pre-existing baseline; confirm no new errors were introduced near the added blocks.

- [ ] **Step 2: Verify LolliME (new) — explosion gone + order fixed**

With the Vite preview running, open the Plan page → LolliME wizard. Read the live values via the preview eval tool (Step 2 demand table + Step 3 trajectory):
- **Step 2 (Growth):** the Combined/Non-brand row's far months are sane — **Dec ≈ 13K, not 166,991**; the **Year** total is realistic (tens of thousands, not 8.3M).
- **Step 3 (Ads Path):** the trajectory mid-year is ≈ the real run-rate (~40–46/day), **not ~9/day**; December peaks.
Expected: both true.

- [ ] **Step 3: Verify Lollibox (mature) — unchanged/own shape**

Open the Lollibox wizard. Step 2 December is its own ~9× peak (≈ 5–6K range given its run-rate); Step 3 trajectory tracks its own pace. No explosion, no collapse.
Expected: sane, consistent with the pre-existing Lollibox behavior.

- [ ] **Step 4: Verify Bunny (just-launched) — safe conservative fallback**

Open the Bunny wizard. With no clean own 2025 month it falls back to the conservative own-run-rate × reference shape: low numbers, **December does not explode** and is not astronomically high. (Proper staged-batch handling is the separate mechanism-B spec.)
Expected: small, finite, non-exploding.

- [ ] **Step 5: Final full check + summary**

Run: `cd dashboard-react && PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit && npx vitest run 2>&1 | tail -3`
Expected: tsc clean, all tests green. Report the LolliME before/after (Dec 166,991 → ~13K display; ~9/d → ~40/d order) as the headline verification.

---

## Self-Review

**1. Spec coverage**
- Level = weighted run-rate → Task 1 (`weightedRunRate`) + Task 4 (`runRateMap`). ✓
- Seasonal shape (own clean + reference stitch, current month = 1) → Task 3 (`seasonalShape`). ✓
- Launch-ramp exclusion + maturity-not-from-first-sale → Task 2 (`detectLaunchMonth`). ✓
- Reference resolves to Lollibox → Task 5 (`familyMonthly2025['Lollibox']`). ✓ (Derivation of "most-mature family" is simplified to the known Lollibox reference per spec's v1; noted.)
- Step 3 anchor = run-rate × shape → Tasks 5–6. ✓
- Step 2 display = recentRate × shape, remove `LY × growth` → Task 7. ✓
- Both tables, one shape → the single `shape` from Task 5 feeds StepAdsPath (anchor) and StepGrowth (display). ✓
- Just-launched conservative fallback (no explosion) → seasonalShape's pure-reference degenerate + Task 8 Step 4 check. ✓
- Mechanism B (staged batches) intentionally OUT — separate spec. ✓

**2. Placeholder scan:** no TBD/TODO; every code step shows full code and exact run/expected lines. ✓

**3. Type consistency:** `runRateMap: Map<string,{unitsPerDay:number;spendPerDay:number}>` and `familyMonthly2025: Record<string, number[]>` are declared identically in PlanPage (Task 4), the PlanWizard `Props` (Task 5 Step 2), and consumed unchanged. `anchorUnits`/`anchorSpend: number[]` declared in PlanWizard (Task 5) and StepAdsPath props (Task 6) match. `shape: number[]` declared in PlanWizard and StepGrowth (Task 7) match. `seasonalShape`/`detectLaunchMonth`/`weightedRunRate` signatures are identical between definition (Tasks 1–3) and call sites (Tasks 4–5). ✓

**4. Ambiguity:** the "complete week" rule (weekStart + 6 ≤ latestDataDate) and the `shape[m-1] ?? 1` guard are explicit; `new Date(2026, m, 0).getDate()` gives days-in-month for 1-based `m`. ✓
