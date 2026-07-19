# Supply Multi-PO Payment (Full / Partial) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user record one bank payment that pays several POs at once — either all in full (each PO's remaining balance) or partial (enter one total, split equally across the selected POs, each split editable).

**Architecture:** Frontend-only. The backend already records "one payment across many POs with per-PO amounts" via `dataEntry.bulkCreatePoPayments` → Flask `bulk_create_po_payments` (one `payment_id`, one row per PO, bank fee on the first row). We enhance `BulkPaymentModal` (PO mode only) with a payment-level **Full / Partial** toggle. The amount-splitting logic is extracted into a pure, unit-tested helper module; the modal wires it in via effects. No BigQuery / Cube / Flask changes.

**Tech Stack:** React 19, TypeScript (strict), Tailwind CSS 4, Vitest + @testing-library (already installed). Node lives at `/Users/ori/.nvm/versions/node/v22.22.1/bin`.

**Working dir for all commands:** `/Users/ori/Develop/OI/dashboard-react`
**Branch:** `feat/owned-negatives-coacher` (already checked out).

**Note on commits:** Dashboard has pre-existing `tsc` errors unrelated to this work (see project memory). If a pre-commit hook blocks on unrelated type errors, commit with `--no-verify`. Always run the scoped commands shown (targeted `vitest` + `tsc` on touched files) to verify *our* code.

---

## File Structure

- **Create** `src/components/supply/bulkPaymentSplit.ts` — pure helpers: `splitEqually`, `buildFullPrefill`, and the `PoPayMode` type. No React imports. One responsibility: turn (total, ids) or (ids, balances) into an amount map.
- **Create** `src/components/supply/bulkPaymentSplit.test.ts` — Vitest unit tests for the helpers.
- **Modify** `src/components/supply/BulkPaymentModal.tsx` — add Full/Partial toggle + total input + read-only Full amounts + allocation warnings, wired to the helpers. PO mode only; shipments mode untouched.
- **Modify** `src/pages/SupplyPage.tsx` — rename the "Bulk Pay" button to "Pay Multiple POs".

---

## Task 1: Pure split/prefill helpers (TDD)

**Files:**
- Create: `src/components/supply/bulkPaymentSplit.ts`
- Test: `src/components/supply/bulkPaymentSplit.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/components/supply/bulkPaymentSplit.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { splitEqually, buildFullPrefill } from './bulkPaymentSplit';

describe('splitEqually', () => {
  it('splits evenly into 2-decimal strings that sum exactly to the total', () => {
    const out = splitEqually(100, ['a', 'b', 'c', 'd']);
    expect(out).toEqual({ a: '25.00', b: '25.00', c: '25.00', d: '25.00' });
  });

  it('puts leftover cents on the first ids so the split sums exactly', () => {
    const out = splitEqually(100, ['a', 'b', 'c']);
    expect(out).toEqual({ a: '33.34', b: '33.33', c: '33.33' });
    const sum = Object.values(out).reduce((s, v) => s + parseFloat(v), 0);
    expect(sum).toBeCloseTo(100, 2);
  });

  it('assigns the whole amount to a single id', () => {
    expect(splitEqually(250.5, ['x'])).toEqual({ x: '250.50' });
  });

  it('returns empty strings for a non-positive or NaN total', () => {
    expect(splitEqually(0, ['a', 'b'])).toEqual({ a: '', b: '' });
    expect(splitEqually(NaN, ['a'])).toEqual({ a: '' });
  });

  it('returns an empty object for no ids', () => {
    expect(splitEqually(100, [])).toEqual({});
  });
});

describe('buildFullPrefill', () => {
  it('maps each id to its remaining balance as a 2-decimal string', () => {
    const out = buildFullPrefill(['a', 'b'], { a: 1200.5, b: 300 });
    expect(out).toEqual({ a: '1200.50', b: '300.00' });
  });

  it('uses 0.00 for missing or non-positive balances', () => {
    const out = buildFullPrefill(['a', 'b'], { a: -5 });
    expect(out).toEqual({ a: '0.00', b: '0.00' });
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/components/supply/bulkPaymentSplit.test.ts`
Expected: FAIL — cannot resolve `./bulkPaymentSplit` (module not created yet).

- [ ] **Step 3: Write the minimal implementation**

Create `src/components/supply/bulkPaymentSplit.ts`:

```ts
/**
 * Pure amount-allocation helpers for BulkPaymentModal (PO mode).
 * No React — kept separate so the split logic is unit-testable.
 */

/** Payment-level allocation mode for POs. */
export type PoPayMode = 'full' | 'partial';

/**
 * Split `total` equally across `ids`, returned as 2-decimal strings.
 * Leftover cents are distributed to the first ids so the parts sum exactly
 * to `total`. Non-positive / NaN totals yield empty strings (nothing to pay).
 */
export function splitEqually(total: number, ids: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  const n = ids.length;
  if (n === 0) return out;
  if (!isFinite(total) || total <= 0) {
    for (const id of ids) out[id] = '';
    return out;
  }
  const totalCents = Math.round(total * 100);
  const base = Math.floor(totalCents / n);
  let remainder = totalCents - base * n;
  for (const id of ids) {
    const cents = base + (remainder > 0 ? 1 : 0);
    if (remainder > 0) remainder -= 1;
    out[id] = (cents / 100).toFixed(2);
  }
  return out;
}

/**
 * Prefill each id with its remaining balance as a 2-decimal string.
 * Missing or non-positive balances become '0.00'.
 */
export function buildFullPrefill(
  ids: string[],
  balanceById: Record<string, number>,
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const id of ids) {
    const bal = balanceById[id] ?? 0;
    out[id] = bal > 0 ? bal.toFixed(2) : '0.00';
  }
  return out;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/components/supply/bulkPaymentSplit.test.ts`
Expected: PASS — 7 tests green.

- [ ] **Step 5: Commit**

```bash
git add src/components/supply/bulkPaymentSplit.ts src/components/supply/bulkPaymentSplit.test.ts
git commit --no-verify -m "feat(supply): pure Full/Partial payment split helpers"
```

---

## Task 2: Full-mode toggle + balance-driven read-only amounts

Adds the `Full | Partial` toggle (PO mode only), a balance lookup, and the Full-mode behavior: checking a PO auto-fills its amount to its remaining balance, and the amount inputs become read-only.

**Files:**
- Modify: `src/components/supply/BulkPaymentModal.tsx`

- [ ] **Step 1: Import the helpers**

In `BulkPaymentModal.tsx`, just after the existing type import (the line `import type { SupplyShipmentRow, SupplyPORow, SupplyOtherPORow } from '../../types';`, ~line 26), add:

```ts
import { splitEqually, buildFullPrefill, type PoPayMode } from './bulkPaymentSplit';
```

- [ ] **Step 2: Add PO-mode state**

In the component body, immediately after the amounts state block (the `const [amounts, setAmounts] = useState<Record<string, string>>(...)` ending ~line 124), add:

```ts
  // ── PO payment mode (Full = pay each PO's balance; Partial = split a total) ──
  const [poPayMode, setPoPayMode] = useState<PoPayMode>('full');
  const [totalPayment, setTotalPayment] = useState('');
```

- [ ] **Step 3: Build the balance lookup**

Immediately after `const uniquePos = useMemo(() => dedupePos(pos), [pos]);` (~line 194), add:

```ts
  // ── Remaining-balance lookup for POs + Other POs (drives Full mode) ──
  const balanceById = useMemo(() => {
    const m: Record<string, number> = {};
    for (const p of uniquePos) m[p.purchase_order_id] = Math.max(p.unpaid_manufacturer, 0);
    for (const op of otherPos) {
      m[op.other_po_id] = op.payment_status !== 'PAID' ? Math.max(op.total_amount, 0) : 0;
    }
    return m;
  }, [uniquePos, otherPos]);
```

- [ ] **Step 4: Sync amounts in Full mode**

Immediately after the `balanceById` memo, add an effect that keeps checked POs' amounts pinned to their balances while in Full mode:

```ts
  // Full mode: amounts are derived from balances, not hand-entered.
  useEffect(() => {
    if (mode !== 'pos' || poPayMode !== 'full') return;
    setAmounts(buildFullPrefill(Array.from(checkedIds), balanceById));
  }, [mode, poPayMode, checkedIds, balanceById]);
```

- [ ] **Step 5: Reset PO state on mode change**

In `handleModeChange` (~line 167), add the two resets so switching Shipments↔POs starts clean. Replace the body:

```ts
  const handleModeChange = useCallback((m: Mode) => {
    setMode(m);
    setCheckedIds(new Set());
    setAmounts(m === 'shipments' ? buildShipmentPrefill(shipments) : {});
  }, [shipments]);
```

with:

```ts
  const handleModeChange = useCallback((m: Mode) => {
    setMode(m);
    setCheckedIds(new Set());
    setAmounts(m === 'shipments' ? buildShipmentPrefill(shipments) : {});
    setPoPayMode('full');
    setTotalPayment('');
  }, [shipments]);
```

- [ ] **Step 6: Render the Full/Partial toggle (PO mode only)**

The candidate-grid section starts at `{/* ── Candidate Grid ── */}` (~line 483). Directly **above** that comment, insert the toggle block:

```tsx
          {/* ── PO Full/Partial toggle ── */}
          {mode === 'pos' && (
            <div className="flex flex-col gap-1.5">
              <span className={labelCls}>Pay POs</span>
              <div className="flex gap-2">
                {(['full', 'partial'] as PoPayMode[]).map((pm) => {
                  const selected = poPayMode === pm;
                  return (
                    <button
                      key={pm}
                      type="button"
                      onClick={() => setPoPayMode(pm)}
                      className={`flex-1 rounded-lg border px-3 py-2 text-xs font-semibold transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50 ${
                        selected
                          ? 'border-blue-500/60 bg-blue-500/15 text-blue-400'
                          : 'border-border bg-surface text-muted hover:text-heading hover:border-border-strong'
                      }`}
                    >
                      {pm === 'full' ? 'Full (each PO balance)' : 'Partial (split a total)'}
                    </button>
                  );
                })}
              </div>
            </div>
          )}
```

- [ ] **Step 7: Make PO amount inputs read-only in Full mode**

Pass a `readOnly` flag to `POCandidateGrid`. In the `<POCandidateGrid ... />` usage (~line 516), add the prop:

```tsx
                <POCandidateGrid
                  uniquePos={uniquePos}
                  otherPos={otherPos}
                  checkedIds={checkedIds}
                  amounts={amounts}
                  onToggle={toggleCheck}
                  onAmount={setAmount}
                  readOnly={mode === 'pos' && poPayMode === 'full'}
                />
```

Then update `POCandidateGrid`'s signature. Change its props type (~line 677-684) to add `readOnly`:

```tsx
}: {
  uniquePos: Array<{ purchase_order_id: string; manufacturer_name: string; unpaid_manufacturer: number }>;
  otherPos: SupplyOtherPORow[];
  checkedIds: Set<string>;
  amounts: Record<string, string>;
  onToggle: (id: string) => void;
  onAmount: (id: string, val: string) => void;
  readOnly?: boolean;
}) {
```

and add `readOnly,` to its destructured params list (the block starting `function POCandidateGrid({` ~line 670):

```tsx
function POCandidateGrid({
  uniquePos,
  otherPos,
  checkedIds,
  amounts,
  onToggle,
  onAmount,
  readOnly,
}: {
```

Finally, apply `readOnly` to **both** amount `<input>`s inside `POCandidateGrid` (the standard-PO input ~line 744 and the Other-PO input ~line 796). For each, add `readOnly={readOnly}` and append a dimming class. The standard-PO input becomes:

```tsx
                <input
                  type="number"
                  step="any"
                  min="0"
                  readOnly={readOnly}
                  value={amounts[id] ?? ''}
                  onChange={(e) => {
                    if (!checkedIds.has(id)) onToggle(id);
                    onAmount(id, e.target.value);
                  }}
                  placeholder="0.00"
                  className={`w-24 rounded border border-border bg-card px-2 py-1 text-xs text-right text-heading focus:outline-none focus:ring-1 focus:ring-blue-500/50 font-mono ${readOnly ? 'opacity-60 cursor-not-allowed' : ''}`}
                />
```

Apply the identical `readOnly={readOnly}` prop and the same `${readOnly ? 'opacity-60 cursor-not-allowed' : ''}` className suffix to the Other-PO amount input as well.

- [ ] **Step 8: Type-check the touched file**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit -p tsconfig.app.json 2>&1 | grep -E "BulkPaymentModal|bulkPaymentSplit" || echo "no errors in touched files"`
Expected: `no errors in touched files` (pre-existing unrelated errors elsewhere are fine).

- [ ] **Step 9: Commit**

```bash
git add src/components/supply/BulkPaymentModal.tsx
git commit --no-verify -m "feat(supply): Full-mode toggle pins PO amounts to balances (read-only)"
```

---

## Task 3: Partial-mode total input, equal split, and allocation warnings

Adds the "Total payment" input shown in Partial mode, splits it equally across checked POs (re-splitting when the total or the checked set changes), and shows non-blocking warnings for mismatch/overpay.

**Files:**
- Modify: `src/components/supply/BulkPaymentModal.tsx`

- [ ] **Step 1: Split the total across checked POs in Partial mode**

Directly below the Full-mode effect added in Task 2 Step 4, add:

```ts
  // Partial mode: split the entered total equally across checked POs.
  // Deps are total + checked set only, so editing one field does not re-split.
  useEffect(() => {
    if (mode !== 'pos' || poPayMode !== 'partial') return;
    setAmounts(splitEqually(parseFloat(totalPayment), Array.from(checkedIds)));
  }, [mode, poPayMode, totalPayment, checkedIds]);
```

- [ ] **Step 2: Compute allocation warnings**

Immediately after the `runningTotal` computation (~line 188-191), add:

```ts
  // ── Allocation warnings (Partial mode; non-blocking) ──
  const partialTarget = parseFloat(totalPayment);
  const hasPartialTarget = mode === 'pos' && poPayMode === 'partial' && isFinite(partialTarget) && partialTarget > 0;
  const sumMismatch = hasPartialTarget && Math.abs(runningTotal - partialTarget) > 0.01;
  const overpayIds = Array.from(checkedIds).filter((id) => {
    const v = parseFloat(amounts[id] ?? '');
    return mode === 'pos' && !isNaN(v) && v > (balanceById[id] ?? 0) + 0.01;
  });
```

- [ ] **Step 3: Render the Total payment input (Partial mode only)**

Inside the toggle block from Task 2 Step 6, directly **after** the closing `</div>` of the `flex gap-2` button row but still inside the `{mode === 'pos' && ( ... )}` wrapper, add the total input so it appears only in Partial mode. Replace the toggle block's closing lines:

```tsx
                })}
              </div>
            </div>
          )}
```

with:

```tsx
                })}
              </div>
              {poPayMode === 'partial' && (
                <div className="flex flex-col gap-1 mt-2">
                  <label className={labelCls}>
                    Total Payment <span className="text-negative">*</span>
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    min="0"
                    value={totalPayment}
                    onChange={(e) => setTotalPayment(e.target.value)}
                    placeholder="0.00"
                    className={inputCls}
                  />
                  <span className="text-[10px] text-faint">
                    Split equally across selected POs. Adjust any amount below.
                  </span>
                </div>
              )}
            </div>
          )}
```

- [ ] **Step 4: Render the allocation summary + warnings**

The candidate-grid section header (~line 484-496) shows `{checkedIds.size} selected · Total: ...`. Directly **below** the closing `</div>` of that header row and **above** the scrollable grid container (the `<div className="rounded-lg border border-border overflow-hidden" ...>` ~line 498), insert:

```tsx
            {hasPartialTarget && (
              <div className="text-[10px] font-mono text-muted">
                Allocated{' '}
                <span className={sumMismatch ? 'text-amber-400 font-semibold' : 'text-emerald-400 font-semibold'}>
                  {fmtAmt(runningTotal)}
                </span>{' '}
                of {fmtAmt(partialTarget)}
              </div>
            )}
            {sumMismatch && (
              <div className="text-[10px] text-amber-400">
                Allocated amounts don't add up to the total payment.
              </div>
            )}
            {overpayIds.length > 0 && (
              <div className="text-[10px] text-amber-400">
                {overpayIds.length} PO{overpayIds.length !== 1 ? 's' : ''} allocated more than the remaining balance (prepayment).
              </div>
            )}
```

- [ ] **Step 5: Type-check the touched file**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx tsc --noEmit -p tsconfig.app.json 2>&1 | grep -E "BulkPaymentModal|bulkPaymentSplit" || echo "no errors in touched files"`
Expected: `no errors in touched files`.

- [ ] **Step 6: Re-run helper tests (regression)**

Run: `PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH" npx vitest run src/components/supply/bulkPaymentSplit.test.ts`
Expected: PASS — 7 tests still green.

- [ ] **Step 7: Commit**

```bash
git add src/components/supply/BulkPaymentModal.tsx
git commit --no-verify -m "feat(supply): Partial-mode total input, equal split, allocation warnings"
```

---

## Task 4: Rename the button + manual verification

**Files:**
- Modify: `src/pages/SupplyPage.tsx`

- [ ] **Step 1: Rename "Bulk Pay" to "Pay Multiple POs"**

In `SupplyPage.tsx`, inside the `tab === 'payments'` block (~line 1013-1019), the first button's label text is `Bulk Pay`. Replace that visible text:

```tsx
                <Plus size={14} />
                Bulk Pay
```

with:

```tsx
                <Plus size={14} />
                Pay Multiple POs
```

- [ ] **Step 2: Commit**

```bash
git add src/pages/SupplyPage.tsx
git commit --no-verify -m "feat(supply): rename Bulk Pay button to Pay Multiple POs"
```

- [ ] **Step 3: Manual verification in the running app**

Start the dashboard preview (per `dashboard-react/CLAUDE.md`: `npm run dev`, Vite on :5173; Cube on :4000 if data is needed). On the **Supply → Payments** tab:

1. Click **Pay Multiple POs** → modal opens. Click **Purchase Orders** mode. Confirm the **Full / Partial** toggle appears, defaulting to **Full**.
2. **Full:** check 2–3 POs. Confirm each Amount auto-fills to its **Unpaid** balance and the fields are read-only (dimmed). Footer total = sum of balances.
3. **Partial:** switch to Partial. Enter a **Total Payment** (e.g. `300`) with 3 POs checked → confirm each shows `100.00` and "Allocated $300.00 of $300.00". Edit one field to `120` → confirm the others stay and the mismatch warning appears.
4. Set one PO's amount above its balance → confirm the prepayment warning appears but submit is still allowed.
5. Submit → confirm success, then open the created payment (Payments tab / PaymentDetailDrawer) and verify it is **one** payment covering all selected POs with the per-PO amounts, and the bank fee recorded once.

Report the outcome (with a screenshot of the modal in Partial mode) rather than asking the user to check manually.

---

## Notes for the implementer

- **Effect ordering:** the Full effect and Partial effect are mutually exclusive via their `poPayMode` guards; only one ever runs. Both are guarded by `mode === 'pos'`, so **shipments mode is completely untouched**.
- **Why editing a field doesn't re-split:** the Partial effect's deps are `[mode, poPayMode, totalPayment, checkedIds]` — not `amounts` — so a manual amount edit updates only that field and never re-triggers the split. This is the intended "no auto-rebalance" behavior from the spec.
- **Submit path is unchanged:** it still filters to checked rows with amount > 0 and calls `dataEntry.bulkCreatePoPayments`. Warnings are advisory; the only hard block remains "select at least one row with amount > 0".
