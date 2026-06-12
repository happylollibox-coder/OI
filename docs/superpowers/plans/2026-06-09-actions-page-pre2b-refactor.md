# Actions Page — Pre-Phase-2B Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up the existing coacher code in `ActionsPage.tsx` so Phase 2B (live thresholds, spend-lever→action, CPC targeting, multi-window ROAS, brand classifier) lands on a tested, well-factored base instead of compounding debt.

**Architecture:** Extract the in-component coacher business logic into a new pure, TDD'd module `coachActuals.ts` (mirroring the `planTypes.ts` standard); make `adRoasSignal` injectable so Phase-2B live `CoachThresholds` drop in without touching the signal logic; fix the latent bug where every family is judged on the *global* dominant coach mode instead of its own; and pull the family plan/actuals render block into a dedicated subcomponent. Refactor is behaviour-preserving **except** the per-family-mode bug fix.

**Tech Stack:** React 19 + TypeScript 5.9 (strict) + Vite 7 + Vitest 3, dashboard under `OI/dashboard-react/`.

---

## Scope

**In scope (this plan):** the 6 pre-2B cleanup items. No new data loaders, no Cube/BQ changes, no new product behaviour besides the bug fix.

**Out of scope (Phase 2B, later plans):** the actual multi-window ROAS wiring (7d ad-only from `Ads` cube reactive · 4w for strong waste/scale confirmation · peak/holiday-phase window for search-term potential), live `CoachThresholds` injection, spend-lever→DoQueue actions, CPC-to-`cpc_target` targeting with the `DIM_BRAND_PHRASES` brand classifier, and the server-side engine join. This plan only makes those *easy to add*.

## Conventions & Constraints (carry over from the brief)

- Branch `feat/offseason-forecast`; commits are **local, not pushed**. Never `git push`.
- **Never `git add -A`/`.`** — stage exact files only. Commit with `--no-verify`.
- Node via nvm full path. All commands below assume:
  `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH"` (prepend once per shell).
- Tests run from `OI/dashboard-react/`: `npm test` → `vitest run`.
- TDD all pure logic; live-verify the family panel in the preview before claiming done.

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `dashboard-react/src/coachActuals.ts` | **New.** Pure coacher helpers: `familyActuals`, `familyModes`, `dominantMode`. No React. | Create |
| `dashboard-react/src/coachActuals.test.ts` | **New.** Vitest unit tests for the above. | Create |
| `dashboard-react/src/planTypes.ts` | Make `adRoasSignal` injectable; export `MODE_ROAS` + `RoasBar`. | Modify (`:531-545`) |
| `dashboard-react/src/planTypes.test.ts` | Add tests for the new `overrides` path. | Modify (append) |
| `dashboard-react/src/pages/FamilyPlanActuals.tsx` | **New.** Presentational component for the per-family Plan + Last-7d block. | Create |
| `dashboard-react/src/pages/ActionsPage.tsx` | Use the new helpers/component; fix per-family mode; remove `enrichedActs`. | Modify |

---

### Task 1: Make `adRoasSignal` injectable (planTypes.ts)

Backward-compatible: existing 2-arg calls keep working (use built-in `MODE_ROAS` defaults); Phase 2B passes a third `overrides` arg sourced from live `CoachThresholds`.

**Files:**
- Modify: `dashboard-react/src/planTypes.ts:531-545`
- Test: `dashboard-react/src/planTypes.test.ts` (append after the existing `adRoasSignal` block, ~line 589)

- [ ] **Step 1: Write the failing test**

Append to `dashboard-react/src/planTypes.test.ts`:

```ts
describe('adRoasSignal overrides (live thresholds)', () => {
  it('applies a per-mode override over the built-in bar', () => {
    // GUARDIAN default scales at >=1.1; override the bar down to >=1.3
    const ov = { GUARDIAN: { up: 1.3 } };
    expect(adRoasSignal(1.27, 'GUARDIAN', ov).action).toBe('hold'); // below the raised bar
    expect(adRoasSignal(1.35, 'GUARDIAN', ov).action).toBe('scale');
  });
  it('falls back to the built-in bar when no override exists for that mode', () => {
    const ov = { BLITZ: { up: 2.0 } };
    expect(adRoasSignal(1.27, 'GUARDIAN', ov).action).toBe('scale'); // GUARDIAN unchanged
  });
  it('can flip scale off via override', () => {
    expect(adRoasSignal(5.0, 'GUARDIAN', { GUARDIAN: { scale: false } }).action).toBe('hold');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard-react && npm test -- planTypes`
Expected: FAIL — the 3-arg `adRoasSignal(..., ov)` overrides are ignored (third arg currently unused), so the first assertion gets `scale` not `hold`.

- [ ] **Step 3: Write minimal implementation**

In `dashboard-react/src/planTypes.ts`, replace lines 531-545 with:

```ts
// Mode-aware reaction to a measured ad ROAS (a RESULT, not a plan target). ROAS is a margin-ROAS
// (~1.0 = breakeven). The "good enough to scale" bar follows the coacher MODE, mirroring its existing
// per-mode budget rules: GUARDIAN (defend profit) scales at >=1.1; BLITZ (grow) at >=1.0; COOLDOWN
// (wind-down) never scales and only holds while >=0.8. `overrides` lets a live source (CoachThresholds,
// per-mode/per-season) tune any bar field without changing this logic — Phase 2B passes them in.
export interface RoasBar { up: number; down: number; scale: boolean }
export const MODE_ROAS: Record<string, RoasBar> = {
  GUARDIAN: { up: 1.1, down: 0.9, scale: true },
  BLITZ:    { up: 1.0, down: 0.9, scale: true },
  COOLDOWN: { up: Infinity, down: 0.8, scale: false },
};
export function adRoasSignal(
  roas: number,
  mode: string,
  overrides?: Record<string, Partial<RoasBar>>,
): { action: 'scale' | 'hold' | 'cut' } {
  const base = MODE_ROAS[mode] ?? MODE_ROAS.GUARDIAN;
  const o = overrides?.[mode];
  const cfg: RoasBar = o ? { ...base, ...o } : base;
  if (cfg.scale && roas >= cfg.up) return { action: 'scale' };
  if (roas < cfg.down) return { action: 'cut' };
  return { action: 'hold' };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd dashboard-react && npm test -- planTypes`
Expected: PASS — the new 3 tests plus all pre-existing `adRoasSignal` tests (the 2-arg calls are unchanged).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/planTypes.ts dashboard-react/src/planTypes.test.ts
git commit --no-verify -m "refactor(actions): make adRoasSignal threshold-injectable for live CoachThresholds

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Extract `familyActuals` pure helper (coachActuals.ts)

Lift the in-component `famActuals` memo (`ActionsPage.tsx:352-386`) verbatim in behaviour into a pure, tested function. This is the seam Phase-2B item 5 (multi-window ROAS) will extend.

**Files:**
- Create: `dashboard-react/src/coachActuals.ts`
- Test: `dashboard-react/src/coachActuals.test.ts`

- [ ] **Step 1: Write the failing test**

Create `dashboard-react/src/coachActuals.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { familyActuals } from './coachActuals';

// daily_trends rows are keyed by product_type = family. ad_cost & clicks are ad-only.
const trends = [
  { date: '2026-06-01', product_type: 'Lollibox', ad_cost: 70, clicks: 100 },
  { date: '2026-06-02', product_type: 'Lollibox', ad_cost: 70, clicks: 100 },
];
// acts carry the 4w window: net_roas spend-weighted by spend, family via getFamily(product_short_name).
const acts = [
  { product_short_name: 'White Lollibox', spend: 100, net_roas: 1.5 },
  { product_short_name: 'Pink Lollibox',  spend: 100, net_roas: 0.5 },
];
const getFamily = (n?: string | null) => (n ? n.split(' ').slice(-1)[0] === 'Lollibox' ? 'Lollibox' : null : null);

describe('familyActuals', () => {
  it('computes last-7d daily ad spend, ad-only CPC, and spend-weighted 4w ROAS per family', () => {
    const out = familyActuals(acts, trends, getFamily);
    const f = out.get('Lollibox')!;
    expect(f.dailyCost).toBeCloseTo(140 / 2);          // 2 days in window → $70/d
    expect(f.cpc).toBeCloseTo(140 / 200);              // $0.70 ad-only CPC
    expect(f.roas).toBeCloseTo((1.5 * 100 + 0.5 * 100) / 200); // 1.0 spend-weighted
  });
  it('uses only the most recent 7 distinct trend dates', () => {
    const long = Array.from({ length: 10 }, (_, i) => ({
      date: `2026-06-${String(i + 1).padStart(2, '0')}`, product_type: 'Lollibox', ad_cost: 10, clicks: 10,
    }));
    const out = familyActuals([], long, getFamily);
    expect(out.get('Lollibox')!.dailyCost).toBeCloseTo(10); // 7 days × $10 / 7 = $10/d
  });
  it('emits families that appear only in trends (spend, no ROAS) and only in acts (ROAS, no spend)', () => {
    const out = familyActuals(
      [{ product_short_name: 'White Lollibox', spend: 50, net_roas: 2 }],
      [{ date: '2026-06-01', product_type: 'LolliME', ad_cost: 30, clicks: 60 }],
      (n?: string | null) => (n?.includes('Lollibox') ? 'Lollibox' : null),
    );
    expect(out.get('LolliME')!.dailyCost).toBeCloseTo(30);
    expect(out.get('LolliME')!.roas).toBe(0);
    expect(out.get('Lollibox')!.roas).toBeCloseTo(2);
    expect(out.get('Lollibox')!.dailyCost).toBe(0);
  });
  it('never divides by zero (no clicks → cpc 0, no spend → roas 0)', () => {
    const out = familyActuals(
      [{ product_short_name: 'White Lollibox', spend: 0, net_roas: 9 }],
      [{ date: '2026-06-01', product_type: 'Lollibox', ad_cost: 5, clicks: 0 }],
      (n?: string | null) => (n?.includes('Lollibox') ? 'Lollibox' : null),
    );
    const f = out.get('Lollibox')!;
    expect(f.cpc).toBe(0);
    expect(f.roas).toBe(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard-react && npm test -- coachActuals`
Expected: FAIL — `Cannot find module './coachActuals'` / `familyActuals is not a function`.

- [ ] **Step 3: Write minimal implementation**

Create `dashboard-react/src/coachActuals.ts`:

```ts
// ─── Ads-Coacher in-component logic, extracted pure + TDD'd ──────────────────
// Mirrors the planTypes.ts standard. These were inline memos in ActionsPage.tsx;
// extracted so Phase 2B can extend the ROAS window (7d ad-only / 4w / peak) and
// inject live thresholds without touching the component.

export interface FamilyActual { dailyCost: number; cpc: number; roas: number }

// Minimal structural shapes (avoid importing the heavy DashboardData types here).
export interface DailyTrendLike { date: string; product_type: string; ad_cost?: number; clicks?: number }
export interface ActLike { product_short_name?: string | null; spend?: number; net_roas?: number }

// Per-family last-week actuals vs the (daily) plan guidelines:
//   • dailyCost + cpc = last 7 distinct trend dates from daily_trends (ad-only), non-overlapping.
//   • roas = last 4w ad-only, spend-weighted over the family's coach term rows (acts) — the only
//     ad-only ROAS currently available (a daily_trends ROAS would be blended/halo).
// Keyed by getFamily(product_short_name) so it matches the family panel's bucket keys exactly.
export function familyActuals(
  acts: ActLike[],
  dailyTrends: DailyTrendLike[],
  getFamily: (name?: string | null) => string | null,
): Map<string, FamilyActual> {
  const dates = [...new Set(dailyTrends.map(r => r.date))].sort();
  const recentDates = new Set(dates.slice(-7)); // last week
  const nDays = recentDates.size || 1;

  const sp = new Map<string, { cost: number; clicks: number }>();
  for (const r of dailyTrends) {
    if (!recentDates.has(r.date)) continue;
    const e = sp.get(r.product_type) ?? { cost: 0, clicks: 0 };
    e.cost += r.ad_cost || 0;
    e.clicks += r.clicks || 0;
    sp.set(r.product_type, e);
  }

  const ro = new Map<string, { spend: number; roasW: number }>();
  for (const a of acts) {
    const fam = getFamily(a.product_short_name);
    if (!fam) continue;
    const s = a.spend || 0;
    const e = ro.get(fam) ?? { spend: 0, roasW: 0 };
    e.spend += s;
    e.roasW += (a.net_roas || 0) * s;
    ro.set(fam, e);
  }

  const out = new Map<string, FamilyActual>();
  for (const fam of new Set([...sp.keys(), ...ro.keys()])) {
    const s = sp.get(fam);
    const r = ro.get(fam);
    out.set(fam, {
      dailyCost: s ? s.cost / nDays : 0,
      cpc: s && s.clicks > 0 ? s.cost / s.clicks : 0,
      roas: r && r.spend > 0 ? r.roasW / r.spend : 0,
    });
  }
  return out;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd dashboard-react && npm test -- coachActuals`
Expected: PASS — all 4 tests.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/coachActuals.ts dashboard-react/src/coachActuals.test.ts
git commit --no-verify -m "refactor(actions): extract familyActuals into pure, tested coachActuals module

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Add `familyModes` + `dominantMode` helpers (fixes the per-family mode bug)

The latent bug: `ActionsPage.tsx:1413` judges **every** family's ROAS on `effectiveCoachMode` (the single global dominant mode). It must use each family's own mode. Add a per-family mode map keyed by `getFamily(product_short_name)` so it aligns with the panel's bucket keys, plus a shared `dominantMode` to kill the duplicated mode-counting.

**Files:**
- Modify: `dashboard-react/src/coachActuals.ts`
- Test: `dashboard-react/src/coachActuals.test.ts`

- [ ] **Step 1: Write the failing test**

Append to `dashboard-react/src/coachActuals.test.ts`:

```ts
import { familyModes, dominantMode } from './coachActuals';

describe('dominantMode', () => {
  it('returns the most frequent coach_mode', () => {
    expect(dominantMode([{ coach_mode: 'BLITZ' }, { coach_mode: 'BLITZ' }, { coach_mode: 'GUARDIAN' }])).toBe('BLITZ');
  });
  it('defaults to GUARDIAN when empty', () => {
    expect(dominantMode([])).toBe('GUARDIAN');
  });
});

describe('familyModes', () => {
  const rows = [
    { product_short_name: 'White Lollibox', coach_mode: 'BLITZ' },
    { product_short_name: 'Pink Lollibox',  coach_mode: 'BLITZ' },
    { product_short_name: 'Mint LolliME',   coach_mode: 'COOLDOWN' },
  ];
  const getFamily = (n?: string | null) =>
    n?.includes('Lollibox') ? 'Lollibox' : n?.includes('LolliME') ? 'LolliME' : null;
  it('maps each family to its own dominant mode (keyed by getFamily)', () => {
    const m = familyModes(rows, getFamily);
    expect(m.get('Lollibox')).toBe('BLITZ');
    expect(m.get('LolliME')).toBe('COOLDOWN'); // NOT the global dominant (BLITZ)
  });
  it('ignores rows with no family or no mode', () => {
    const m = familyModes([{ product_short_name: 'Unknown', coach_mode: 'BLITZ' }], getFamily);
    expect(m.size).toBe(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard-react && npm test -- coachActuals`
Expected: FAIL — `familyModes`/`dominantMode` not exported.

- [ ] **Step 3: Write minimal implementation**

Append to `dashboard-react/src/coachActuals.ts`:

```ts
export interface ModeRowLike { product_short_name?: string | null; coach_mode?: string | null }

// Most frequent coach_mode across rows; GUARDIAN when there are none.
export function dominantMode(rows: { coach_mode?: string | null }[]): string {
  const counts: Record<string, number> = {};
  for (const r of rows) if (r.coach_mode) counts[r.coach_mode] = (counts[r.coach_mode] || 0) + 1;
  return Object.entries(counts).sort((a, b) => b[1] - a[1])[0]?.[0] || 'GUARDIAN';
}

// Per-family dominant coach mode, keyed by getFamily(product_short_name) so it lines up with the
// family panel's bucket keys. Replaces the previous global-mode-for-every-family behaviour.
export function familyModes(
  rows: ModeRowLike[],
  getFamily: (name?: string | null) => string | null,
): Map<string, string> {
  const byFam = new Map<string, { coach_mode?: string | null }[]>();
  for (const r of rows) {
    const fam = getFamily(r.product_short_name);
    if (!fam || !r.coach_mode) continue;
    (byFam.get(fam) ?? byFam.set(fam, []).get(fam)!).push(r);
  }
  const out = new Map<string, string>();
  for (const [fam, frows] of byFam) out.set(fam, dominantMode(frows));
  return out;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd dashboard-react && npm test -- coachActuals`
Expected: PASS — all `coachActuals` tests (Task 2 + Task 3).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/coachActuals.ts dashboard-react/src/coachActuals.test.ts
git commit --no-verify -m "refactor(actions): add familyModes/dominantMode helpers (per-family mode)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Wire helpers into ActionsPage — replace `famActuals`, fix the bug, DRY the mode counting

Swap the inline logic for the tested helpers and fix the per-family-mode bug at the ROAS pill.

**Files:**
- Modify: `dashboard-react/src/pages/ActionsPage.tsx`

- [ ] **Step 1: Add the import**

In `dashboard-react/src/pages/ActionsPage.tsx:2`, change:

```ts
import { monthlyPlanTargets, planDelta, adRoasSignal } from '../planTypes';
```
to add the new module:
```ts
import { monthlyPlanTargets, planDelta, adRoasSignal } from '../planTypes';
import { familyActuals, familyModes, dominantMode } from '../coachActuals';
```

- [ ] **Step 2: Replace the `famActuals` memo body**

Replace `ActionsPage.tsx:352-386` (the whole `const famActuals = useMemo(...)` block, keeping the doc comment at 346-351 above it) with:

```ts
  const famActuals = useMemo(
    () => familyActuals(acts, data.daily_trends || [], getFamily),
    [acts, getFamily, data.daily_trends],
  );

  // Per-family dominant coach mode (keyed by getFamily) — each family is judged on its OWN mode.
  const famModes = useMemo(() => familyModes(data.actions || [], getFamily), [data.actions, getFamily]);
```

- [ ] **Step 3: Fix the per-family-mode bug at the ROAS pill**

In `ActionsPage.tsx:1413`, change:

```ts
                                  const sig = adRoasSignal(act.roas, effectiveCoachMode).action;
```
to use the family's own mode (`f.family` is in scope in the `famBuckets.map`):
```ts
                                  const sig = adRoasSignal(act.roas, famModes.get(f.family) ?? effectiveCoachMode).action;
```

- [ ] **Step 4: DRY `effectiveCoachMode` via `dominantMode`**

In `ActionsPage.tsx:401-409`, replace the body of the `effectiveCoachMode` memo with the shared helper:

```ts
  const effectiveCoachMode = useMemo(() => {
    if (coachFilter !== 'all') return coachFilter;
    return dominantMode(data.actions || []);
  }, [coachFilter, data.actions]);
```

Then in the inline CoachStrategyPanel block at `ActionsPage.tsx:1194-1198`, replace the manual `modeCounts` loop:

```ts
        const modeCounts: Record<string, number> = {};
        for (const ct of coachTerms) {
          if (ct.coach_mode) modeCounts[ct.coach_mode] = (modeCounts[ct.coach_mode] || 0) + 1;
        }
        const activeMode = (coachFilter !== 'all' ? coachFilter : Object.entries(modeCounts).sort((a, b) => b[1] - a[1])[0]?.[0]) || 'GUARDIAN';
```
with:
```ts
        const activeMode = coachFilter !== 'all' ? coachFilter : dominantMode(coachTerms);
```

- [ ] **Step 5: Typecheck + tests + build**

Run: `cd dashboard-react && npx tsc --noEmit && npm test`
Expected: no TS errors; all unit tests PASS.

- [ ] **Step 6: Live-verify in the preview**

Start the dev server (Cube on :4000 if needed, Vite on :5173), open the Actions page, confirm:
- The per-family "Last 7d" line still renders Plan/Spend/CPC/ROAS for each family.
- A family whose own mode differs from the global dominant now shows its **own** scale/hold/cut hint (e.g. a COOLDOWN family no longer shows "↑ scale budget" just because the deck is mostly BLITZ).
Capture a screenshot as proof.

- [ ] **Step 7: Commit**

```bash
git add dashboard-react/src/pages/ActionsPage.tsx
git commit --no-verify -m "fix(actions): judge each family's ROAS on its own coach mode; DRY mode counting

Replaces global-dominant-mode-for-every-family with familyModes; routes the
extracted familyActuals/dominantMode helpers into ActionsPage.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Extract `<FamilyPlanActuals>` subcomponent

Pull the deeply-nested IIFE that renders the Plan + Last-7d block (`ActionsPage.tsx:1383-1425`) into its own presentational component, so Phase-2B spend-lever and CPC rows have a clean home. Presentational only — verified in the preview, not unit-tested.

**Files:**
- Create: `dashboard-react/src/pages/FamilyPlanActuals.tsx`
- Modify: `dashboard-react/src/pages/ActionsPage.tsx`

- [ ] **Step 1: Create the subcomponent**

Create `dashboard-react/src/pages/FamilyPlanActuals.tsx`:

```tsx
import { planDelta, adRoasSignal } from '../planTypes';
import type { FamilyActual } from '../coachActuals';

interface PlanTarget { dailyCost: number; cpc: number; roas: number }

// The per-family "Plan {mo}: $X/d · CPC $Y" + "Last 7d: …" block from the Actions family panel.
// Spend/CPC are last-7d levers (badged vs plan); ROAS is a measured RESULT → scale/hold/cut per the
// family's own coach mode (NOT vs plan). Returns null when the family has neither a plan nor actuals.
export function FamilyPlanActuals({
  planTarget, actual, mode, planMoLabel,
}: {
  planTarget?: PlanTarget;
  actual?: FamilyActual;
  mode: string;
  planMoLabel: string;
}) {
  const hasPlan = !!planTarget && planTarget.dailyCost > 0;
  const actualDaily = actual?.dailyCost ?? 0;
  const hasActual = actualDaily > 0 || (!!actual && actual.cpc > 0);
  if (!hasPlan && !hasActual) return null;

  // higherIsBetter=false for spend/CPC (over plan = bad/red); within ±10% = on-plan (faint).
  const badge = (av: number, plan: number, higherIsBetter: boolean) => {
    const d = planDelta(av, plan);
    if (d.pct === null) return null;
    const good = higherIsBetter ? d.status !== 'under' : d.status !== 'over';
    const cls = d.status === 'on' ? 'text-faint' : good ? 'text-emerald-400' : 'text-red-400';
    return <span className={cls}>({d.pct >= 0 ? '+' : ''}{Math.round(d.pct * 100)}%)</span>;
  };

  return (
    <>
      {hasPlan && planTarget && (
        <div className="text-[9px] tabular-nums text-faint mb-0.5" title={`Plan inputs for ${planMoLabel} — the levers the coacher steers (daily spend & CPC). ROAS is a measured result, not a plan target.`}>
          <span className="text-blue-400/80 font-semibold">Plan {planMoLabel}:</span>{' '}
          <span className="text-muted">${planTarget.dailyCost.toFixed(0)}</span>/d · CPC <span className="text-muted">${planTarget.cpc.toFixed(2)}</span>
        </div>
      )}
      {hasActual && (
        <div className="text-[9px] tabular-nums text-faint mb-1" title={`Spend/d & CPC = last 7 days (ad), vs the plan levers. ROAS = last 4 weeks ad-only, a RESULT (2-day lag) → coacher reacts per ${mode} mode (scale/hold/cut), not vs plan.`}>
          <span className="text-subtle font-semibold">Last 7d:</span>{' '}
          ${actualDaily.toFixed(0)}/d {hasPlan && planTarget && badge(actualDaily, planTarget.dailyCost, false)}
          {actual && actual.cpc > 0 && <> · CPC ${actual.cpc.toFixed(2)} {hasPlan && planTarget && badge(actual.cpc, planTarget.cpc, false)}</>}
          {actual && actual.roas > 0 && (() => {
            const sig = adRoasSignal(actual.roas, mode).action;
            const roasCls = sig === 'scale' ? 'text-emerald-400' : sig === 'cut' ? 'text-red-400' : 'text-muted';
            const hint = sig === 'scale' ? { t: ' ↑ scale budget', c: 'text-emerald-400/80' }
                       : sig === 'cut'   ? { t: ' ↓ cut spend',     c: 'text-red-400/80' }
                       :                   { t: ' · hold',          c: 'text-faint' };
            return <> · ROAS <span className={roasCls}>{actual.roas.toFixed(2)}×</span><span className={hint.c}>{hint.t}</span></>;
          })()}
          {!hasPlan && <span className="text-faint/60"> · no plan yet</span>}
        </div>
      )}
    </>
  );
}
```

- [ ] **Step 2: Use it in ActionsPage**

Add the import near the top of `ActionsPage.tsx` (after the `coachActuals` import from Task 4):

```ts
import { FamilyPlanActuals } from './FamilyPlanActuals';
```

Then replace the entire IIFE block at `ActionsPage.tsx:1383-1425` (the `{(() => { const pt = planTargets.get(f.family); … })()}`) with:

```tsx
                      <FamilyPlanActuals
                        planTarget={planTargets.get(f.family)}
                        actual={famActuals.get(f.family)}
                        mode={famModes.get(f.family) ?? effectiveCoachMode}
                        planMoLabel={planMoLabel}
                      />
```

- [ ] **Step 3: Typecheck + tests + build**

Run: `cd dashboard-react && npx tsc --noEmit && npm test && npm run build`
Expected: no TS errors, tests PASS, build succeeds.

- [ ] **Step 4: Live-verify in the preview**

Reload the Actions page; confirm the per-family Plan + Last-7d block is **pixel-identical** to before the extraction (same Plan line, same badges, same ROAS hint colour driven by the family's own mode). Screenshot as proof.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/pages/FamilyPlanActuals.tsx dashboard-react/src/pages/ActionsPage.tsx
git commit --no-verify -m "refactor(actions): extract FamilyPlanActuals subcomponent from the family panel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Remove the `enrichedActs` dead alias

`const enrichedActs = acts;` (`ActionsPage.tsx:388`) is a no-op indirection used at lines 412, 451, 481, 488. Inline it back to `acts`.

**Files:**
- Modify: `dashboard-react/src/pages/ActionsPage.tsx`

- [ ] **Step 1: Delete the alias and replace its uses**

- Delete line 388: `const enrichedActs = acts;`
- Line 412: `let f = [...enrichedActs];` → `let f = [...acts];`
- Line 451 (deps array): `}, [enrichedActs, …]` → `}, [acts, …]`
- Line 481: `for (const r of enrichedActs) {` → `for (const r of acts) {`
- Line 488 (deps array): `}, [enrichedActs]);` → `}, [acts]);`

Verify nothing else references it:

Run: `cd dashboard-react && grep -n enrichedActs src/pages/ActionsPage.tsx`
Expected: no output.

- [ ] **Step 2: Typecheck + tests**

Run: `cd dashboard-react && npx tsc --noEmit && npm test`
Expected: no TS errors; all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/ActionsPage.tsx
git commit --no-verify -m "refactor(actions): inline dead enrichedActs alias to acts

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final Verification

- [ ] `cd dashboard-react && npx tsc --noEmit` → clean
- [ ] `cd dashboard-react && npm test` → all unit tests pass (planTypes + coachActuals)
- [ ] `cd dashboard-react && npm run build` → succeeds
- [ ] Actions page in the preview: family panel unchanged visually; a family whose own mode ≠ global dominant shows its own scale/hold/cut hint (the bug fix). Screenshot captured.
- [ ] `git log --oneline -6` shows the six refactor commits, none pushed.

## Phase 2B Readiness (what this unlocked)

- **Live thresholds:** `adRoasSignal(roas, mode, overrides)` — feed `overrides` from `CoachThresholds` (via `useThresholds`).
- **Multi-window ROAS:** extend `familyActuals` (or add siblings) in `coachActuals.ts` — 7d ad-only from the `Ads` cube (reactive) · keep 4w for strong waste/scale confirmation · add a peak/holiday-phase window for search-term potential. All TDD'd in `coachActuals.test.ts`.
- **Per-family mode** is now correct and centralised (`familyModes`), so spend-lever→action (GUARDIAN +10% / BLITZ +20%) keys off the right mode.
- **Spend-lever & CPC rows** have a home in `<FamilyPlanActuals>`.
- **Brand classifier:** wire `DIM_BRAND_PHRASES` (+ `SP_ACCUMULATE_BRAND_PHRASES`) into the CPC targeting in a later 2B task — independent of this refactor.
