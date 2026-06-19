# Actions Page Collapsible Sections — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap each Actions-page block in a collapsible section with a summary row + section-scoped Queue all / Unqueue all, add a consistent per-item unqueue toggle, surface budget-decrease actions as their own section, and wire New-Campaign (launch) decisions into the Do/bulksheet export.

**Architecture:** Pure frontend (`dashboard-react/`). A new reusable `<CollapsibleSection>` shell wraps the existing 4 blocks. Pure helpers (`sectionUtils.ts`) compute per-section membership, summary stats, and the launch→base-action translation; these are unit-tested. Integration into `ActionsPage.tsx` / `DoPage.tsx` reuses the existing `useDoQueue` API (`addItem` / `removeItem`). No BigQuery / Cube / engine changes.

**Tech Stack:** React 19 + TypeScript 5.9 (strict) + Tailwind 4 + Lucide React. Tests: Vitest (`src/**/*.test.ts(x)`, run with `npm test`). Node lives at `/Users/ori/.nvm/versions/node/v22.22.1/bin` — ensure it is on `PATH` (e.g. `nvm use 22`).

Spec: [docs/superpowers/specs/2026-06-19-actions-collapsible-sections-design.md](../specs/2026-06-19-actions-collapsible-sections-design.md)

---

## File Structure

- **Create** `dashboard-react/src/pages/sectionUtils.ts` — pure helpers: `isBudgetRow`, `budgetTrimPerDay`, `launchToBaseAction`, `summarizeSection`. One responsibility: section math + launch translation, no React.
- **Create** `dashboard-react/src/pages/sectionUtils.test.ts` — unit tests for the above.
- **Create** `dashboard-react/src/components/Actions/CollapsibleSection.tsx` — the reusable shell (header + summary + Queue all/Unqueue all + chevron + persisted collapse).
- **Create** `dashboard-react/src/components/Actions/CollapsibleSection.test.tsx` — component tests.
- **Create** `dashboard-react/src/components/Actions/QueueToggle.tsx` — the per-item `[+ queue] ↔ [✓ ✕]` control.
- **Modify** `dashboard-react/src/pages/ActionsPage.tsx` — exclude budget rows from `filtered`; render the 4 blocks inside `<CollapsibleSection>`; add the 💰 Budget section; section queue-all/unqueue-all; use `QueueToggle`.
- **Modify** `dashboard-react/src/pages/DoPage.tsx` — export queued budget items; handle translated launch reduce/negate, incl. SP-Auto target rows.

> **Note on `DoQueueItem.source`:** the spec mentioned tagging launch items `source: 'launch'`, but the existing `source` field is typed `'COACH' | 'MANUAL'`. We DROP that tag — launch items are translated to their base action (`REDUCE_BID` / `NEGATE_TERM` / `STOP_TARGET`) at queue time and keep `source: 'COACH'`. No type change to `DoQueueItem`.

---

## Task 1: `sectionUtils.ts` — pure helpers + tests

**Files:**
- Create: `dashboard-react/src/pages/sectionUtils.ts`
- Test: `dashboard-react/src/pages/sectionUtils.test.ts`

- [ ] **Step 1: Write the failing tests**

```ts
// dashboard-react/src/pages/sectionUtils.test.ts
import { describe, it, expect } from 'vitest';
import { isBudgetRow, budgetTrimPerDay, launchToBaseAction, summarizeSection } from './sectionUtils';

describe('isBudgetRow', () => {
  it('is true for BUDGET action_type that is not BUDGET_OK', () => {
    expect(isBudgetRow({ action_type: 'BUDGET', action: 'GUARDIAN_BUDGET_DECREASE' })).toBe(true);
  });
  it('is false for BUDGET_OK (no-op)', () => {
    expect(isBudgetRow({ action_type: 'BUDGET', action: 'BUDGET_OK' })).toBe(false);
  });
  it('is false for non-budget rows', () => {
    expect(isBudgetRow({ action_type: 'TERM', action: 'NEGATE_TERM' })).toBe(false);
  });
});

describe('budgetTrimPerDay', () => {
  it('returns positive $ trimmed for a decrease', () => {
    expect(budgetTrimPerDay({ current_budget: 20, recommended_budget: 17 })).toBe(3);
  });
  it('returns 0 when budgets missing', () => {
    expect(budgetTrimPerDay({ current_budget: null, recommended_budget: null })).toBe(0);
  });
});

describe('launchToBaseAction', () => {
  it('maps LAUNCH_REDUCE_BID to REDUCE_BID with the launch bid', () => {
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_REDUCE_BID', launch_recommended_bid: 0.45, match_type: 'SEARCH_TERM' }))
      .toEqual({ action: 'REDUCE_BID', recommended_bid: 0.45 });
  });
  it('maps LAUNCH_NEGATE on a search term to NEGATE_TERM', () => {
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_NEGATE', match_type: 'SEARCH_TERM' }))
      .toEqual({ action: 'NEGATE_TERM', recommended_bid: null });
  });
  it('maps LAUNCH_NEGATE on an Automatic auto-clause to STOP_TARGET', () => {
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_NEGATE', match_type: 'Automatic', targeting: 'loose-match' }))
      .toEqual({ action: 'STOP_TARGET', recommended_bid: null });
  });
  it('returns null for HOLD and GRADUATE (no-op)', () => {
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_HOLD' })).toBeNull();
    expect(launchToBaseAction({ launch_decision: 'LAUNCH_GRADUATE' })).toBeNull();
  });
});

describe('summarizeSection', () => {
  it('counts actionable rows and sums the dollars', () => {
    const rows = [{ _dollars: 10 }, { _dollars: 5 }, { _dollars: 0 }];
    const s = summarizeSection(rows, r => (r as { _dollars: number })._dollars, () => true, () => false);
    expect(s).toEqual({ count: 3, dollars: 15, queueable: 3, queued: 0 });
  });
  it('separates queued from queueable', () => {
    const rows = [{ id: 'a' }, { id: 'b' }];
    const s = summarizeSection(rows, () => 0, () => true, r => (r as { id: string }).id === 'a');
    expect(s).toEqual({ count: 2, dollars: 0, queueable: 1, queued: 1 });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd dashboard-react && npm test -- sectionUtils`
Expected: FAIL — `Cannot find module './sectionUtils'`.

- [ ] **Step 3: Implement `sectionUtils.ts`**

```ts
// dashboard-react/src/pages/sectionUtils.ts

/** A budget row that should appear in the 💰 Budget section (excludes the BUDGET_OK no-op). */
export function isBudgetRow(r: { action_type?: string | null; action?: string | null }): boolean {
  return r.action_type === 'BUDGET' && r.action !== 'BUDGET_OK';
}

/** $/day trimmed by a budget decrease (current − recommended); 0 when unknown or an increase. */
export function budgetTrimPerDay(r: { current_budget?: number | null; recommended_budget?: number | null }): number {
  const cur = r.current_budget ?? null;
  const rec = r.recommended_budget ?? null;
  if (cur == null || rec == null) return 0;
  return Math.max(0, cur - rec);
}

export type BaseAction = { action: string; recommended_bid: number | null };

/**
 * Translate a launch decision into the base bulksheet operation queued for it.
 * HOLD / GRADUATE are no-ops (null = not queueable).
 * NEGATE routes by target type: SP-Auto clauses / product targets → STOP_TARGET; keywords → NEGATE_TERM.
 */
export function launchToBaseAction(r: {
  launch_decision?: string | null;
  launch_recommended_bid?: number | null;
  match_type?: string | null;
  targeting?: string | null;
}): BaseAction | null {
  switch (r.launch_decision) {
    case 'LAUNCH_REDUCE_BID':
      return { action: 'REDUCE_BID', recommended_bid: r.launch_recommended_bid ?? null };
    case 'LAUNCH_NEGATE': {
      const isAutoOrProduct =
        r.match_type === 'Automatic' || (r.targeting ?? '').toLowerCase().startsWith('asin=');
      return { action: isAutoOrProduct ? 'STOP_TARGET' : 'NEGATE_TERM', recommended_bid: null };
    }
    default:
      return null; // LAUNCH_HOLD, LAUNCH_GRADUATE, undefined
  }
}

export type SectionSummary = { count: number; dollars: number; queueable: number; queued: number };

/** Roll up a section's rows: total count, summed dollars, how many are queueable vs already queued. */
export function summarizeSection<T>(
  rows: T[],
  dollarsOf: (r: T) => number,
  isQueueable: (r: T) => boolean,
  isQueued: (r: T) => boolean,
): SectionSummary {
  let dollars = 0, queueable = 0, queued = 0;
  for (const r of rows) {
    dollars += dollarsOf(r) || 0;
    if (isQueued(r)) queued += 1;
    else if (isQueueable(r)) queueable += 1;
  }
  return { count: rows.length, dollars, queueable, queued };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd dashboard-react && npm test -- sectionUtils`
Expected: PASS (10+ assertions green).

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/pages/sectionUtils.ts dashboard-react/src/pages/sectionUtils.test.ts
git commit -m "feat(actions): section math + launch->base-action helpers"
```

---

## Task 2: `CollapsibleSection.tsx` — the section shell + tests

**Files:**
- Create: `dashboard-react/src/components/Actions/CollapsibleSection.tsx`
- Test: `dashboard-react/src/components/Actions/CollapsibleSection.test.tsx`

- [ ] **Step 1: Write the failing tests**

```tsx
// dashboard-react/src/components/Actions/CollapsibleSection.test.tsx
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { CollapsibleSection } from './CollapsibleSection';

beforeEach(() => localStorage.clear());

describe('CollapsibleSection', () => {
  it('starts collapsed by default and shows the summary, hides the body', () => {
    render(
      <CollapsibleSection id="t1" title="Budget" summary={<span>summary-here</span>} queueableCount={3} queuedCount={0}>
        <div>body-content</div>
      </CollapsibleSection>
    );
    expect(screen.getByText('summary-here')).toBeTruthy();
    expect(screen.queryByText('body-content')).toBeNull();
  });

  it('expands on header click and reveals the body', () => {
    render(
      <CollapsibleSection id="t2" title="Budget" summary={null} queueableCount={3} queuedCount={0}>
        <div>body-content</div>
      </CollapsibleSection>
    );
    fireEvent.click(screen.getByRole('button', { name: /Budget/ }));
    expect(screen.getByText('body-content')).toBeTruthy();
  });

  it('disables Queue all when nothing is queueable, Unqueue all when nothing queued', () => {
    const onQueueAll = vi.fn(), onUnqueueAll = vi.fn();
    render(
      <CollapsibleSection id="t3" title="Budget" summary={null} queueableCount={0} queuedCount={0}
        onQueueAll={onQueueAll} onUnqueueAll={onUnqueueAll}>
        <div />
      </CollapsibleSection>
    );
    fireEvent.click(screen.getByRole('button', { name: /Queue all/ }));
    fireEvent.click(screen.getByRole('button', { name: /Unqueue all/ }));
    expect(onQueueAll).not.toHaveBeenCalled();
    expect(onUnqueueAll).not.toHaveBeenCalled();
  });

  it('persists collapse state per id across remounts', () => {
    const { unmount } = render(
      <CollapsibleSection id="t4" title="Budget" summary={null} queueableCount={1} queuedCount={0}>
        <div>body-content</div>
      </CollapsibleSection>
    );
    fireEvent.click(screen.getByRole('button', { name: /Budget/ })); // expand
    unmount();
    render(
      <CollapsibleSection id="t4" title="Budget" summary={null} queueableCount={1} queuedCount={0}>
        <div>body-content</div>
      </CollapsibleSection>
    );
    expect(screen.getByText('body-content')).toBeTruthy(); // still expanded
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd dashboard-react && npm test -- CollapsibleSection`
Expected: FAIL — `Cannot find module './CollapsibleSection'`. (If `@testing-library/react` is missing, install it as a dev dep: `npm i -D @testing-library/react`. Check `package.json` first — other component tests may already use it.)

- [ ] **Step 3: Implement `CollapsibleSection.tsx`**

```tsx
// dashboard-react/src/components/Actions/CollapsibleSection.tsx
import { useState, useCallback, type ReactNode } from 'react';
import { ChevronRight, ChevronDown } from 'lucide-react';

const STORAGE_KEY = 'oi_actions_sections';

function loadCollapsed(id: string, fallback: boolean): boolean {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    const map = raw ? (JSON.parse(raw) as Record<string, boolean>) : {};
    return id in map ? map[id] : fallback;
  } catch { return fallback; }
}

function saveCollapsed(id: string, collapsed: boolean) {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    const map = raw ? (JSON.parse(raw) as Record<string, boolean>) : {};
    map[id] = collapsed;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(map));
  } catch { /* ignore */ }
}

interface Props {
  id: string;
  title: ReactNode;
  summary: ReactNode;
  queueableCount: number;
  queuedCount: number;
  onQueueAll?: () => void;
  onUnqueueAll?: () => void;
  defaultCollapsed?: boolean;
  children: ReactNode;
}

export function CollapsibleSection({
  id, title, summary, queueableCount, queuedCount, onQueueAll, onUnqueueAll,
  defaultCollapsed = true, children,
}: Props) {
  const [collapsed, setCollapsed] = useState(() => loadCollapsed(id, defaultCollapsed));
  const toggle = useCallback(() => setCollapsed(c => { const n = !c; saveCollapsed(id, n); return n; }), [id]);

  const queueDisabled = queueableCount - queuedCount <= 0;
  const unqueueDisabled = queuedCount <= 0;

  return (
    <div className="mb-3 rounded-lg border border-[var(--color-border)] bg-[var(--color-card)]">
      <div className="flex items-center gap-2 px-3 py-2">
        <button
          type="button"
          onClick={toggle}
          className="flex items-center gap-2 flex-1 min-w-0 text-left"
          aria-expanded={!collapsed}
        >
          {collapsed ? <ChevronRight size={14} className="text-faint shrink-0" />
                     : <ChevronDown size={14} className="text-faint shrink-0" />}
          <span className="text-[11px] font-bold uppercase tracking-wider text-[var(--color-text)] shrink-0">{title}</span>
          <span className="text-[10px] text-faint truncate">{summary}</span>
        </button>
        {onQueueAll && (
          <button
            type="button"
            disabled={queueDisabled}
            onClick={onQueueAll}
            className="text-[10px] px-2 py-1 rounded border border-[var(--color-border)] text-sky-400 disabled:opacity-40 disabled:cursor-not-allowed shrink-0"
          >Queue all</button>
        )}
        {onUnqueueAll && (
          <button
            type="button"
            disabled={unqueueDisabled}
            onClick={onUnqueueAll}
            className="text-[10px] px-2 py-1 rounded border border-[var(--color-border)] text-faint disabled:opacity-40 disabled:cursor-not-allowed shrink-0"
          >Unqueue all</button>
        )}
      </div>
      {!collapsed && <div className="px-3 pb-3">{children}</div>}
    </div>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd dashboard-react && npm test -- CollapsibleSection`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/components/Actions/CollapsibleSection.tsx dashboard-react/src/components/Actions/CollapsibleSection.test.tsx
git commit -m "feat(actions): reusable CollapsibleSection shell"
```

---

## Task 3: `QueueToggle.tsx` — consistent per-item queue/unqueue control

**Files:**
- Create: `dashboard-react/src/components/Actions/QueueToggle.tsx`
- Test: `dashboard-react/src/components/Actions/QueueToggle.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// dashboard-react/src/components/Actions/QueueToggle.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { QueueToggle } from './QueueToggle';

describe('QueueToggle', () => {
  it('shows add affordance and calls onQueue when not queued', () => {
    const onQueue = vi.fn(), onUnqueue = vi.fn();
    render(<QueueToggle queued={false} onQueue={onQueue} onUnqueue={onUnqueue} />);
    fireEvent.click(screen.getByRole('button', { name: /queue/i }));
    expect(onQueue).toHaveBeenCalledTimes(1);
    expect(onUnqueue).not.toHaveBeenCalled();
  });

  it('shows unqueue affordance and calls onUnqueue when queued', () => {
    const onQueue = vi.fn(), onUnqueue = vi.fn();
    render(<QueueToggle queued={true} onQueue={onQueue} onUnqueue={onUnqueue} />);
    fireEvent.click(screen.getByRole('button', { name: /unqueue/i }));
    expect(onUnqueue).toHaveBeenCalledTimes(1);
    expect(onQueue).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dashboard-react && npm test -- QueueToggle`
Expected: FAIL — `Cannot find module './QueueToggle'`.

- [ ] **Step 3: Implement `QueueToggle.tsx`**

```tsx
// dashboard-react/src/components/Actions/QueueToggle.tsx
import { Plus, Check, X } from 'lucide-react';

interface Props {
  queued: boolean;
  onQueue: () => void;
  onUnqueue: () => void;
  size?: number;
}

export function QueueToggle({ queued, onQueue, onUnqueue, size = 13 }: Props) {
  if (queued) {
    return (
      <span className="inline-flex items-center gap-1">
        <Check size={size} className="text-emerald-400" aria-hidden />
        <button
          type="button"
          aria-label="unqueue"
          title="Remove from DO queue"
          onClick={onUnqueue}
          className="p-0.5 rounded text-faint hover:text-[var(--color-negative)] transition-colors"
        ><X size={size} /></button>
      </span>
    );
  }
  return (
    <button
      type="button"
      aria-label="queue"
      title="Add to DO queue"
      onClick={onQueue}
      className="p-0.5 rounded text-zinc-500 hover:text-[var(--color-text)] transition-colors"
    ><Plus size={size} /></button>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd dashboard-react && npm test -- QueueToggle`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add dashboard-react/src/components/Actions/QueueToggle.tsx dashboard-react/src/components/Actions/QueueToggle.test.tsx
git commit -m "feat(actions): QueueToggle per-item queue/unqueue control"
```

---

## Task 4: ActionsPage — exclude budget rows from the table + section queue helpers

**Files:**
- Modify: `dashboard-react/src/pages/ActionsPage.tsx`

Read `ActionsPage.tsx:494-534` (`filtered`) and `:465-492` (`queueAction`) before editing.

- [ ] **Step 1: Exclude budget rows from the main table**

In the `filtered` memo (`ActionsPage.tsx:494`), after `let f = [...acts];`, add (import `isBudgetRow` from `./sectionUtils`):

```ts
    // Budget rows are owned by the 💰 Budget section — keep them out of the table to avoid double-listing.
    f = f.filter(a => !isBudgetRow(a as { action_type?: string | null; action?: string | null }));
```

- [ ] **Step 2: Add a launch-aware queue helper + section bulk helpers**

Near `queueAction` (`:465`), add:

```ts
  // Queue a launch row by translating its decision to the base bulksheet op; returns false if no-op.
  const queueLaunchAction = (a: ActionRow): boolean => {
    const base = launchToBaseAction(a as Parameters<typeof launchToBaseAction>[0]);
    if (!base) return false;
    doQueue.addItem({
      search_term: a.search_term || '', action: base.action,
      campaign: a.campaign_name || '', campaign_id: a.campaign_id || '',
      ad_group_id: a.ad_group_id || '', targeting: a.targeting || '',
      keyword_id: a.keyword_id || '', match_type: a.match_type || '',
      target_spend_8w: a.ads_spend_4w || 0, target_orders_8w: a.ads_orders_4w || 0,
      target_net_roas_8w: (a as { net_roas_4w?: number }).net_roas_4w || 0,
      current_bid: a.current_bid ?? null, recommended_bid: base.recommended_bid,
      campaign_type: a.campaign_type || '', product: a.product_short_name || '', asin: a.asin || '',
      spend: a.ads_spend_4w || 0, orders: a.ads_orders_4w || 0,
      cpc: a.ads_cpc_4w || 0, conv_rate: a.ads_cvr_pct_4w || 0,
      coach_mode: a.coach_mode || '', source: 'COACH',
    });
    return true;
  };

  // Is this row already in the queue? (match by campaign + action + keyword/targeting)
  const rowQueued = (a: ActionRow, action?: string): boolean =>
    doQueue.items.some(q => q.campaign_id === (a.campaign_id || '')
      && q.action === (action ?? a.action)
      && (q.search_term === (a.search_term || '') || q.targeting === (a.targeting || '')));

  // Find the queued item id for a row, so it can be removed (unqueue).
  const queuedIdFor = (a: ActionRow, action?: string): string | undefined =>
    doQueue.items.find(q => q.campaign_id === (a.campaign_id || '')
      && q.action === (action ?? a.action)
      && (q.search_term === (a.search_term || '') || q.targeting === (a.targeting || '')))?.id;

  const queueAllRows = (rows: ActionRow[], launch = false) =>
    rows.forEach(a => { if (launch) queueLaunchAction(a); else if (!rowQueued(a)) queueAction(a); });

  const unqueueAllRows = (rows: ActionRow[]) =>
    rows.forEach(a => { const id = queuedIdFor(a); if (id) doQueue.removeItem(id); });
```

Add imports at the top of the file:

```ts
import { isBudgetRow, budgetTrimPerDay, launchToBaseAction, summarizeSection } from './sectionUtils';
import { CollapsibleSection } from '../components/Actions/CollapsibleSection';
import { QueueToggle } from '../components/Actions/QueueToggle';
```

- [ ] **Step 3: Type-check**

Run: `cd dashboard-react && npx tsc --noEmit`
Expected: no new errors from these additions (pre-existing lint debt may remain; do not introduce new ones).

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/pages/ActionsPage.tsx
git commit -m "feat(actions): exclude budget rows from table + section queue helpers"
```

---

## Task 5: ActionsPage — build the 💰 Budget section data

**Files:**
- Modify: `dashboard-react/src/pages/ActionsPage.tsx`

- [ ] **Step 1: Derive budget rows**

Near `launchGroups` (`:450`), add a memo for budget rows (decreases/increases, not BUDGET_OK, not already done/uploaded):

```ts
  const budgetRows = useMemo(() => acts.filter(a =>
    isBudgetRow(a as { action_type?: string | null; action?: string | null })
    && !doQueue.isUploaded(a.search_term, a.campaign_id)
    && !doQueue.isDone(a.search_term, a.campaign_id)
  ), [acts, doQueue.isUploaded, doQueue.isDone]);
```

- [ ] **Step 2: Type-check**

Run: `cd dashboard-react && npx tsc --noEmit`
Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/ActionsPage.tsx
git commit -m "feat(actions): derive budget-section rows"
```

---

## Task 6: ActionsPage — wrap blocks in `<CollapsibleSection>` + render Budget section

**Files:**
- Modify: `dashboard-react/src/pages/ActionsPage.tsx`

Read the page's `return (...)` JSX to find the render order of the clear-case cards, the launch block (`:1499`), and the main table, so each is wrapped without changing its internals.

- [ ] **Step 1: Wrap the 🎯 Top picks (clear cases) block**

Wrap the existing clear-cases render with:

```tsx
<CollapsibleSection
  id="top-picks"
  title="🎯 Top picks"
  summary={(() => { const s = summarizeSection(clearCases, c => c.opp?.dollars ?? 0, () => true, c => rowQueued(c.a)); return `${s.count} picks · ~$${Math.round(s.dollars)}/wk opportunity · ${s.queued} queued`; })()}
  queueableCount={clearCases.length}
  queuedCount={clearCases.filter(c => rowQueued(c.a)).length}
  onQueueAll={() => clearCases.forEach(c => { if (!rowQueued(c.a)) queueAction(c.a, c.opp); })}
  onUnqueueAll={() => unqueueAllRows(clearCases.map(c => c.a))}
>
  {/* …existing clear-case cards render, unchanged… */}
</CollapsibleSection>
```

- [ ] **Step 2: Add the 💰 Budget Actions section (new block)**

Render directly after Top picks:

```tsx
{budgetRows.length > 0 && (
  <CollapsibleSection
    id="budget"
    title="💰 Budget Actions"
    summary={`${budgetRows.length} campaigns · trim ~$${Math.round(budgetRows.reduce((s, a) => s + budgetTrimPerDay(a as { current_budget?: number|null; recommended_budget?: number|null }), 0))}/day · ${budgetRows.filter(a => rowQueued(a)).length} queued`}
    queueableCount={budgetRows.length}
    queuedCount={budgetRows.filter(a => rowQueued(a)).length}
    onQueueAll={() => queueAllRows(budgetRows)}
    onUnqueueAll={() => unqueueAllRows(budgetRows)}
  >
    <div className="flex flex-col gap-1">
      {budgetRows.map(a => (
        <div key={`${a.campaign_id}:${a.action}`} className="flex items-center justify-between gap-2 rounded border border-[var(--color-border)] px-2.5 py-1.5">
          <div className="min-w-0">
            <div className="text-[12px] font-semibold text-[var(--color-text)] truncate">{a.campaign_name}</div>
            <div className="text-[10px] text-muted">
              {a.action.replace(/_/g, ' ').toLowerCase()} · ${(a as { current_budget?: number }).current_budget ?? '?'} → ${(a as { recommended_budget?: number }).recommended_budget ?? '?'}/day
            </div>
          </div>
          <QueueToggle
            queued={rowQueued(a)}
            onQueue={() => queueAction(a)}
            onUnqueue={() => { const id = queuedIdFor(a); if (id) doQueue.removeItem(id); }}
          />
        </div>
      ))}
    </div>
  </CollapsibleSection>
)}
```

- [ ] **Step 3: Wrap the 🆕 New campaigns (launch) block** — `:1499`

Wrap the existing launch block. Compute the reduce/negate/hold breakdown for the summary, and queue-all using the launch translator:

```tsx
<CollapsibleSection
  id="new-campaigns"
  title="🆕 New campaigns"
  summary={(() => {
    const all = launchGroups.flatMap(g => g.rows);
    const red = all.filter(a => a.launch_decision === 'LAUNCH_REDUCE_BID').length;
    const neg = all.filter(a => a.launch_decision === 'LAUNCH_NEGATE').length;
    const queued = all.filter(a => { const b = launchToBaseAction(a as Parameters<typeof launchToBaseAction>[0]); return b ? rowQueued(a, b.action) : false; }).length;
    return `${all.length} launch kw · ${red} reduce / ${neg} negate / ${all.length - red - neg} hold · ${queued} queued`;
  })()}
  queueableCount={launchGroups.flatMap(g => g.rows).filter(a => launchToBaseAction(a as Parameters<typeof launchToBaseAction>[0]) !== null).length}
  queuedCount={launchGroups.flatMap(g => g.rows).filter(a => { const b = launchToBaseAction(a as Parameters<typeof launchToBaseAction>[0]); return b ? rowQueued(a, b.action) : false; }).length}
  onQueueAll={() => queueAllRows(launchGroups.flatMap(g => g.rows), true)}
  onUnqueueAll={() => launchGroups.flatMap(g => g.rows).forEach(a => { const b = launchToBaseAction(a as Parameters<typeof launchToBaseAction>[0]); if (b) { const id = queuedIdFor(a, b.action); if (id) doQueue.removeItem(id); } })}
>
  {/* …existing launch groups render, unchanged… */}
</CollapsibleSection>
```

- [ ] **Step 4: Wrap the 📋 All actions (table) block**

Wrap the main grouped table (the `filtered`→tree render + its hierarchy selector). Use the existing per-bucket weekly $ if available, else action count only:

```tsx
<CollapsibleSection
  id="all-actions"
  title="📋 All actions"
  summary={`${filtered.length} actions · ${filtered.filter(a => rowQueued(a)).length} queued`}
  queueableCount={filtered.length}
  queuedCount={filtered.filter(a => rowQueued(a)).length}
  onQueueAll={() => queueAllRows(filtered)}
  onUnqueueAll={() => unqueueAllRows(filtered)}
  defaultCollapsed={false}
>
  {/* …existing toolbar (hierarchy selector, Show Monitor) + table tree, unchanged… */}
</CollapsibleSection>
```

> The 📋 All actions section uses `defaultCollapsed={false}` so the page still opens with its primary content visible; the other three default collapsed.

- [ ] **Step 5: Type-check + run unit tests**

Run: `cd dashboard-react && npx tsc --noEmit && npm test -- sectionUtils CollapsibleSection QueueToggle`
Expected: tsc clean (no new errors); tests PASS.

- [ ] **Step 6: Commit**

```bash
git add dashboard-react/src/pages/ActionsPage.tsx
git commit -m "feat(actions): wrap blocks in collapsible sections + Budget section"
```

---

## Task 7: ActionsPage — standardize per-item unqueue across existing rows/cards

**Files:**
- Modify: `dashboard-react/src/pages/ActionsPage.tsx`

- [ ] **Step 1: Replace add-only buttons with `QueueToggle`**

Find the per-item queue buttons in the clear-case cards, hot-signal rows (`~:1025`), phrase rows (`~:1063`), and table leaf rows. Replace each with `<QueueToggle queued={rowQueued(a)} onQueue={() => queueAction(a, opp)} onUnqueue={() => { const id = queuedIdFor(a); if (id) doQueue.removeItem(id); }} />`, passing the row/opp in scope. For hot-signal/phrase items that build their own `addItem` payloads, keep their existing add payload inside `onQueue` and add the matching `onUnqueue` via their existing `doQueue.items.find(...)` id.

- [ ] **Step 2: Type-check**

Run: `cd dashboard-react && npx tsc --noEmit`
Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add dashboard-react/src/pages/ActionsPage.tsx
git commit -m "feat(actions): consistent per-item unqueue via QueueToggle"
```

---

## Task 8: DoPage — export queued budget items + translated launch ops

**Files:**
- Modify: `dashboard-react/src/pages/DoPage.tsx`

Read `DoPage.tsx:14` (`ACTION_ORDER`), the budget-update branch (`~:989-996`), and the `REDUCE_BID` / `NEGATE_TERM` / `STOP_TARGET` export branches before editing.

- [ ] **Step 1: Verify/extend the budget export branch**

Confirm a queued item with `action ∈ {GUARDIAN_BUDGET_DECREASE, GUARDIAN_BUDGET_INCREASE, BLITZ_BUDGET_DECREASE, BLITZ_BUDGET_INCREASE}` and a `recommended_budget` produces a Campaign Update row with `'Daily Budget': String(item.recommended_budget)`. The existing `item.action.includes('BUDGET_INCREASE'|'BUDGET_DECREASE')` branch (`~:989`) already covers this — ensure those actions are in `ACTION_ORDER` so they aren't dropped, and that the row keys off `item.campaign_id` / `item.campaign`.

- [ ] **Step 2: Confirm launch ops need no special branch**

Because launch rows are queued as their base actions (`REDUCE_BID` / `NEGATE_TERM` / `STOP_TARGET`), they flow through the existing branches. Verify those branches read `item.recommended_bid` (set from `launch_recommended_bid`) for the bid update, and that `STOP_TARGET` emits a state/negative row valid for an SP-Auto clause or product target. If `STOP_TARGET` currently assumes a keyword, add an auto/product branch keyed off `item.match_type === 'Automatic'` or `item.targeting.startsWith('asin=')` that emits a Product Targeting state/negative row instead of a keyword negative.

- [ ] **Step 3: Manual export check (preview)**

Start the app (Task 9), queue one budget decrease and one launch reduce on the Actions page, open the Do page, export the bulksheet, and confirm a Campaign `Daily Budget` update row and a bid-update row appear with the right values.

- [ ] **Step 4: Commit**

```bash
git add dashboard-react/src/pages/DoPage.tsx
git commit -m "feat(do): export queued budget + launch reduce/negate ops"
```

---

## Task 9: Verify in the running app + full test pass

**Files:** none (verification)

- [ ] **Step 1: Start servers**

```bash
cd cube && npm run dev   # :4000 (separate terminal)
cd dashboard-react && VITE_CUBE_API_URL=http://localhost:4000 npm run dev   # :5173
```

- [ ] **Step 2: Verify on the Actions page**
  - All four sections render with summary rows; 🎯/💰/🆕 default collapsed, 📋 expanded.
  - 💰 Budget Actions lists the `GUARDIAN_BUDGET_DECREASE` campaigns; `BUDGET_OK` is absent.
  - Queue all on 💰 stages every budget row; Unqueue all clears them; the queued count updates.
  - A per-item `✕` on any queued row removes just that item.
  - 🆕 New campaigns Queue all stages only reduce/negate rows (holds skipped).

- [ ] **Step 3: Verify export on the Do page** — queued budget + launch items produce correct bulksheet rows (see Task 8 Step 3).

- [ ] **Step 4: Full unit test + type pass**

Run: `cd dashboard-react && npx tsc --noEmit && npm test`
Expected: tsc clean (no new errors); all vitest suites green.

- [ ] **Step 5: Commit any verification fixups**

```bash
git add -A
git commit -m "test(actions): verify collapsible sections + section queue controls"
```

---

## Self-Review

- **Spec coverage:** CollapsibleSection (T2) ✓; 4 sections incl. Budget (T5,T6) ✓; summary rows (T6) ✓; section Queue all/Unqueue all (T4 helpers, T6 wiring) ✓; per-item unqueue (T3,T7) ✓; budget queue+export (T5,T6,T8) ✓; launch→export incl. SP-Auto nuance (T1,T6,T8) ✓; exclude budget from table to avoid double-listing (T4) ✓; default-collapsed except table (T6) ✓; out-of-scope grain-bug/engine untouched ✓.
- **Type consistency:** `launchToBaseAction` returns `{action, recommended_bid}` used identically in T1/T6/T8; `rowQueued(a, action?)`/`queuedIdFor(a, action?)` signatures match across T4/T6/T7; `summarizeSection` signature matches its T1 test and T6 callers; `CollapsibleSection` props match T2 tests and T6 usage; `QueueToggle` props match T3 tests and T6/T7 usage.
- **Placeholders:** none — every code step shows real code; integration steps name exact files/anchors and the new code to insert.
