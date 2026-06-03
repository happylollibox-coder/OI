# Shipment ETA Auto-fill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In CreateShipmentModal, auto-fill the estimated arrival date as `ship_date + transit_days(type)` whenever the shipment type or ship date changes, with transit days sourced live from the SHIPMENT_TYPE LOV.

**Architecture:** A pure `etaFromType` helper does the date math. The modal already fetches `/api/lov/SHIPMENT_TYPE` into `typeOptions` (each record carries `attr1_value` = transit days), so we derive a `transitDays` map from it (no new fetch) and recompute the ETA via effects — one for the top-level shipment, one inside `updateSplitHeader` for per-split headers.

**Tech Stack:** React 19 + TS, Vitest.

**Spec:** `docs/superpowers/specs/2026-06-03-shipment-eta-autofill-design.md`

**Run commands from `dashboard-react/`. Prefix node/npx with** `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH"`. **Commit with `--no-verify`** (pre-existing repo-wide lint). **Only `git add` the exact files each task touches** — the working tree has ~25 unrelated in-flight files; never `git add -A`.

---

## File Structure

- `dashboard-react/src/utils.ts` — add pure `etaFromType` (date math).
- `dashboard-react/src/utils.test.ts` — tests for `etaFromType` (create if absent).
- `dashboard-react/src/components/Actions/CreateShipmentModal.tsx` — derive `transitDays` from `typeOptions`; recompute ETA (top-level effect + per-split in `updateSplitHeader`).

---

### Task 1: `etaFromType` pure helper

**Files:** Modify `dashboard-react/src/utils.ts`; Test `dashboard-react/src/utils.test.ts` (create if it doesn't exist).

- [ ] **Step 1: Write the failing test**

If `src/utils.test.ts` exists, append this `describe`; else create the file with this content (importing whatever path matches the others — `./utils`):

```ts
import { describe, it, expect } from 'vitest';
import { etaFromType } from './utils';

describe('etaFromType', () => {
  const days = { FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14, AIR: 10 };
  it('adds the type transit days to the ship date', () => {
    expect(etaFromType('2026-06-03', 'FAST_SEA', days)).toBe('2026-06-30'); // 3 + 27
    expect(etaFromType('2026-06-03', 'AIR', days)).toBe('2026-06-13');      // 3 + 10
  });
  it('rolls across months correctly', () => {
    expect(etaFromType('2026-06-03', 'AWD_SLOW_SEA', days)).toBe('2026-08-05'); // 3 + 63
  });
  it('returns null for an unknown type or empty/invalid date', () => {
    expect(etaFromType('2026-06-03', 'NOPE', days)).toBeNull();
    expect(etaFromType('', 'FAST_SEA', days)).toBeNull();
    expect(etaFromType('not-a-date', 'FAST_SEA', days)).toBeNull();
  });
  it('is timezone-stable (no off-by-one)', () => {
    // noon anchor → date component never shifts regardless of local TZ
    expect(etaFromType('2026-12-31', 'AIR', days)).toBe('2027-01-10');
  });
});
```

- [ ] **Step 2: Run → fail**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/utils.test.ts`
Expected: FAIL — `etaFromType is not a function` (or module/file not found if created fresh — then it fails on the missing export).

- [ ] **Step 3: Implement** (append to `src/utils.ts`)

```ts
// Estimated arrival = ship date + transit days for the given shipment type.
// shipDateISO is 'YYYY-MM-DD'. Returns an ISO date string, or null when the date is
// empty/invalid or the type has no mapped days (caller then leaves the existing ETA untouched).
// Anchors at local noon so adding whole days never shifts the date across a timezone boundary.
export function etaFromType(shipDateISO: string, type: string, transitDays: Record<string, number>): string | null {
  const days = transitDays[type];
  if (!shipDateISO || days == null || !Number.isFinite(days)) return null;
  const d = new Date(shipDateISO + 'T12:00:00');
  if (isNaN(d.getTime())) return null;
  d.setDate(d.getDate() + days);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
```

- [ ] **Step 4: Run → pass**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/utils.test.ts` → all pass.
Then `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → exit 0.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/utils.ts dashboard-react/src/utils.test.ts
git commit --no-verify -m "feat(supply): etaFromType helper — ship date + transit days"
```

---

### Task 2: Derive `transitDays` + top-level ETA recompute

**Files:** Modify `dashboard-react/src/components/Actions/CreateShipmentModal.tsx`.

**Context:** The modal already fetches `/api/lov/SHIPMENT_TYPE` into `typeOptions` (state). Each record has `value_id` (e.g. `FAST_SEA`) and `attr1_value` (the transit days as a string, e.g. `"27"`). Top-level shipment state: `shipmentType`, `shipmentDate`, `estimatedArrival` (with `setEstimatedArrival`). `useMemo`/`useEffect` are already imported.

- [ ] **Step 1: Import the helper**

Add `etaFromType` to the existing import from `'../../utils'` (the file already imports formatters from utils; match that import path — confirm whether it's `'../../utils'` and add `etaFromType` to it, or add a new import line if utils isn't imported yet).

- [ ] **Step 2: Derive the `transitDays` map** (place right after the `typeOptions` state or near the other derived values)

```ts
  // type → transit days, from the SHIPMENT_TYPE LOV (attr1_value). Single source w/ the SP.
  const transitDays = useMemo(() => {
    const m: Record<string, number> = {};
    for (const o of typeOptions) {
      const d = Number((o as { attr1_value?: unknown }).attr1_value);
      const id = (o as { value_id?: string }).value_id;
      if (id && Number.isFinite(d)) m[id] = d;
    }
    return m;
  }, [typeOptions]);
```

- [ ] **Step 3: Add the top-level recompute effect** (after `transitDays`)

```ts
  // Auto-fill ETA when the type or ship date changes (recompute on every change; stays hand-editable
  // between changes since estimatedArrival is not a dependency).
  useEffect(() => {
    const eta = etaFromType(shipmentDate, shipmentType, transitDays);
    if (eta) setEstimatedArrival(eta);
  }, [shipmentType, shipmentDate, transitDays]);
```

- [ ] **Step 4: Verify**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → 0.
`PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx eslint src/components/Actions/CreateShipmentModal.tsx` → no NEW errors vs the file's current baseline (check the problem count before/after; the file's pre-existing count must not increase).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/components/Actions/CreateShipmentModal.tsx
git commit --no-verify -m "feat(supply): auto-fill shipment ETA from type (top-level)"
```

---

### Task 3: Per-split ETA recompute

**Files:** Modify `dashboard-react/src/components/Actions/CreateShipmentModal.tsx` (`updateSplitHeader`, currently):

```ts
  const updateSplitHeader = (idx: number, field: string, value: any) => {
    setSplitHeaders(prev => {
      const updated = [...prev];
      updated[idx] = { ...updated[idx], [field]: value };
      return updated;
    });
  };
```

- [ ] **Step 1: Recompute the split's ETA when its type/date changes**

Replace the body with:

```ts
  const updateSplitHeader = (idx: number, field: string, value: any) => {
    setSplitHeaders(prev => {
      const updated = [...prev];
      updated[idx] = { ...updated[idx], [field]: value };
      if (field === 'shipment_type' || field === 'shipment_date') {
        const h = updated[idx];
        const eta = etaFromType(h.shipment_date, h.shipment_type, transitDays);
        if (eta) updated[idx] = { ...updated[idx], estimated_arrival_date: eta };
      }
      return updated;
    });
  };
```

(`transitDays` is in scope from Task 2; the closure captures the latest value since `updateSplitHeader` is recreated each render.)

- [ ] **Step 2: Verify**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit` → 0; eslint count unchanged.

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/components/Actions/CreateShipmentModal.tsx
git commit --no-verify -m "feat(supply): auto-fill ETA per split header on type/date change"
```

---

### Task 4: Live verification

- [ ] **Step 1:** Preview → open the Create Shipment modal (e.g. from a shipment action / Supply page). With a ship date set, confirm **ETA auto-fills** = ship_date + the type's days (FAST_SEA → +27, AWD_SLOW_SEA → +63).
- [ ] **Step 2:** Change the shipment **type** → ETA updates immediately; change the **ship date** → ETA updates.
- [ ] **Step 3:** Add a split, change that split's type/date → its ETA recomputes independently of the others.
- [ ] **Step 4:** Hand-edit the ETA field → the typed value stays until you next change the type/date.

---

## Self-Review

- **Spec coverage:** live in CreateShipmentModal (Tasks 2–3); LOV-sourced days from `typeOptions` (Task 2 — reuses the existing fetch); recompute on every change (Tasks 2–3 effects); per-split (Task 3); pure helper + tests incl. TZ + unknown-type (Task 1); hand-editable (estimatedArrival not a dep). ✓
- **Placeholders:** none — code/commands in every step.
- **Type consistency:** `etaFromType(shipDateISO, type, transitDays)` defined Task 1, used Tasks 2–3; `transitDays` defined Task 2, used Tasks 2–3.
- **Flagged for implementation (from spec):** confirm the modal's `shipment_type` values equal the LOV `value_id`s — they do (the selector is populated from the same `typeOptions`, line ~110), so the map keys match by construction.
- **Out of scope (unchanged):** backend `days_map`, the PO `estimated_arrival_date`, `SP_GENERATE_SHIPMENT_PLAN`.
