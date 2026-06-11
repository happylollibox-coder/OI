# Trust Stage 1 — Clear-Case Selector + Decision Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the 200+-row Actions page into a short list of obviously-correct "decision cards" (claim → evidence → real past impact → exactly what changes in Amazon), with everything marginal collapsed into a "needs judgment" bucket — so Ori can read the whole list daily and verify the coacher's judgment.

**Architecture:** A pure, TDD'd `clearCase()` selector in `coachActuals.ts` applies the spec §7 confidence-gate defaults client-side over fields the engine already provides (`confidence`, 4w spend/clicks/orders/net-ROAS, coach mode). A new presentational `DecisionCard` renders each clear case. `ActionsPage` shows the cards on top (capped at 10); the existing tree becomes the collapsed remainder. No engine changes in this stage (the selector migrates into `V_ADS_COACH_DECISION` at Stage 3).

**Tech Stack:** React 19 + TypeScript 5.9 strict + Vitest 3, in `OI/dashboard-react/`. Node via nvm: `export PATH="/Users/ori/.nvm/versions/node/v22.22.1/bin:$PATH"`. Branch `feat/offseason-forecast`, commits local with `--no-verify`, exact files only, never push.

**Card content principle:** cards display **facts** (what the term actually did — spend, clicks, orders, ROAS over 4w), never speculative forecasts. Trust comes from checkable numbers.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `dashboard-react/src/coachActuals.ts` | Add `clearCase()` + `GateInput`/`GateVerdict` types | Modify (append) |
| `dashboard-react/src/coachActuals.test.ts` | Tests for `clearCase()` | Modify (append) |
| `dashboard-react/src/components/Actions/DecisionCard.tsx` | Presentational card (claim/evidence/impact/Amazon change + Queue button) | Create |
| `dashboard-react/src/pages/ActionsPage.tsx` | "Clear cases" section on top; existing tree collapsed by default | Modify |

---

### Task 1: `clearCase()` gate in coachActuals.ts (TDD)

**Files:**
- Modify: `dashboard-react/src/coachActuals.ts` (append)
- Test: `dashboard-react/src/coachActuals.test.ts` (append)

- [ ] **Step 1: Write the failing tests** — append to `coachActuals.test.ts` (add `clearCase` to the existing import from `./coachActuals`):

```ts
describe('clearCase', () => {
  const base = { spend: 22, clicks: 40, orders: 0, netRoas: 0, mode: 'GUARDIAN', confidence: 'HIGH' };
  it('zero-conversion negate with enough data is the cleanest clear case', () => {
    const v = clearCase({ ...base, action: 'NEGATE_TERM' });
    expect(v.clear).toBe(true);
  });
  it('parks thin data (spend < $5 or clicks < 10 or LOW confidence)', () => {
    expect(clearCase({ ...base, action: 'NEGATE_TERM', spend: 3 }).clear).toBe(false);
    expect(clearCase({ ...base, action: 'NEGATE_TERM', clicks: 4 }).clear).toBe(false);
    expect(clearCase({ ...base, action: 'NEGATE_TERM', confidence: 'LOW' }).clear).toBe(false);
    expect(clearCase({ ...base, action: 'NEGATE_TERM', spend: 3 }).reason).toMatch(/spend/i);
  });
  it('parks a negate that HAS orders (halo risk — direct ROAS understates value)', () => {
    const v = clearCase({ ...base, action: 'NEGATE_TERM', orders: 2, netRoas: 0.5 });
    expect(v.clear).toBe(false);
    expect(v.reason).toMatch(/order/i);
  });
  it('REDUCE_BID is clear only when ROAS is decisively below the gray band (<0.9)', () => {
    expect(clearCase({ ...base, action: 'REDUCE_BID', orders: 3, netRoas: 0.6 }).clear).toBe(true);
    expect(clearCase({ ...base, action: 'REDUCE_BID', orders: 3, netRoas: 0.95 }).clear).toBe(false); // gray band
  });
  it('promote needs mode-specific clear bar: GUARDIAN >=1.3, BLITZ >=1.15, COOLDOWN never', () => {
    const p = { ...base, action: 'INCREASE_BID', orders: 3 };
    expect(clearCase({ ...p, netRoas: 1.35, mode: 'GUARDIAN' }).clear).toBe(true);
    expect(clearCase({ ...p, netRoas: 1.2, mode: 'GUARDIAN' }).clear).toBe(false);
    expect(clearCase({ ...p, netRoas: 1.2, mode: 'BLITZ' }).clear).toBe(true);
    expect(clearCase({ ...p, netRoas: 5.0, mode: 'COOLDOWN' }).clear).toBe(false);
  });
  it('promote with fewer than 2 orders is parked even at high ROAS', () => {
    expect(clearCase({ ...base, action: 'INCREASE_BID', orders: 1, netRoas: 2.0 }).clear).toBe(false);
  });
  it('non-actionable types (MONITOR/KEEP/etc.) are never clear cases', () => {
    expect(clearCase({ ...base, action: 'MONITOR' }).clear).toBe(false);
    expect(clearCase({ ...base, action: 'KEEP' }).clear).toBe(false);
  });
});
```

- [ ] **Step 2: Run to verify FAIL** — `cd dashboard-react && npm test -- coachActuals` → fails: `clearCase` not exported.

- [ ] **Step 3: Implement** — append to `coachActuals.ts`:

```ts
// ─── Stage-1 clear-case selector (spec §7 confidence gate, client-side) ──────
// Decides whether an action is a CLEAR case (surface as a decision card) or parked
// ("needs judgment"). Facts only — uses the engine's own 4w fields. Direct net ROAS
// carries NO organic/repeat halo, so: zero-conversion negates are the cleanest cut;
// negates on terms WITH orders are parked (halo risk); promotes need a margin above
// the mode's display bar (GUARDIAN 1.30 / BLITZ 1.15 / COOLDOWN never).
// Migrates into V_ADS_COACH_DECISION at Stage 3 — keep it dumb and tunable.
export interface GateInput {
  action: string; spend: number; clicks: number; orders: number;
  netRoas: number; mode: string; confidence: string;
}
export interface GateVerdict { clear: boolean; reason: string }

export const GATE = {
  minSpend: 5, minClicks: 10, grayLow: 0.9, grayHigh: 1.1, promoteMinOrders: 2,
  scaleClear: { GUARDIAN: 1.3, BLITZ: 1.15 } as Record<string, number>,
};

const CUT_ACTIONS = new Set(['NEGATE_TERM', 'NEGATE_ROAS_THRESHOLD', 'NEGATE_SPEND_THRESHOLD', 'NEGATE_PHRASE', 'NEGATE_BOOST_SIMILAR_EXACT', 'STOP', 'STOP_TARGET']);
const REDUCE_ACTIONS = new Set(['REDUCE_BID', 'REDUCE_BID_ROAS', 'REDUCE_BID_SPEND']);
const PROMOTE_ACTIONS = new Set(['INCREASE_BID', 'PROMOTE_TO_EXACT', 'SCALE', 'SCALE_UP', 'SCALE_UP_ROAS', 'BOOST']);

export function clearCase(g: GateInput): GateVerdict {
  const isCut = CUT_ACTIONS.has(g.action);
  const isReduce = REDUCE_ACTIONS.has(g.action);
  const isPromote = PROMOTE_ACTIONS.has(g.action);
  if (!isCut && !isReduce && !isPromote) return { clear: false, reason: 'not an act-now action' };
  if (g.confidence === 'LOW') return { clear: false, reason: 'low confidence — thin data' };
  if (g.spend < GATE.minSpend) return { clear: false, reason: `spend $${g.spend.toFixed(0)} < $${GATE.minSpend} floor` };
  if (g.clicks < GATE.minClicks) return { clear: false, reason: `${g.clicks} clicks < ${GATE.minClicks} floor` };
  if (isCut) {
    if (g.orders === 0) return { clear: true, reason: 'real spend, zero orders — nothing to lose' };
    return { clear: false, reason: `${g.orders} order(s) — halo risk, judge manually` };
  }
  if (isReduce) {
    if (g.netRoas < GATE.grayLow) return { clear: true, reason: `ROAS ${g.netRoas.toFixed(2)} decisively below breakeven` };
    return { clear: false, reason: `ROAS ${g.netRoas.toFixed(2)} inside gray band (${GATE.grayLow}–${GATE.grayHigh})` };
  }
  // promote
  const bar = GATE.scaleClear[g.mode];
  if (bar == null) return { clear: false, reason: `${g.mode} mode never promotes` };
  if (g.orders < GATE.promoteMinOrders) return { clear: false, reason: `${g.orders} order(s) < ${GATE.promoteMinOrders} — winner not proven` };
  if (g.netRoas >= bar) return { clear: true, reason: `ROAS ${g.netRoas.toFixed(2)} clears the ${g.mode} bar (${bar})` };
  return { clear: false, reason: `ROAS ${g.netRoas.toFixed(2)} below the ${g.mode} promote bar (${bar})` };
}
```

- [ ] **Step 4: Run to verify PASS** — `npm test -- coachActuals` → all pass (prior 8 + new 7). Also `npx tsc --noEmit` → clean.

- [ ] **Step 5: Commit**
```bash
git add src/coachActuals.ts src/coachActuals.test.ts
git commit --no-verify -m "feat(actions): clearCase() confidence gate — Stage 1 trust selector

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `DecisionCard` component

**Files:**
- Create: `dashboard-react/src/components/Actions/DecisionCard.tsx`

Presentational only (verified in preview, not unit-tested). Before coding, read `dashboard-react/src/pages/ActionsPage.tsx` for: the `acts` row shape (4w fields are mapped to `spend/clicks/orders/net_roas` at the top of `ActionsPage`), how existing rows call `doQueue.addItem(...)` (copy that exact item construction so cards queue identically), and `ACTIONS`-style labels in `utils.ts` (`ACTION_CONFIG` / `humanize`). Use only CSS-var colors per house rules.

- [ ] **Step 1: Create the component**

```tsx
import { ArrowDownRight, ArrowUpRight, Ban, Plus } from 'lucide-react';
import type { ActionRow } from '../../types';
import { fM } from '../../utils';
import type { GateVerdict } from '../../coachActuals';

// One clear-case action as a 10-second-readable card:
//   CLAIM      what to do, for which family
//   EVIDENCE   the 3 facts that justify it (4w window — real past numbers, no forecasts)
//   CHANGE     exactly what will change in Amazon (campaign + object)
// Queue button adds to the Do queue exactly like the row UI does.
export function DecisionCard({ action: a, family, why, inQueue, onQueue }: {
  action: ActionRow; family: string; why: GateVerdict; inQueue: boolean; onQueue: () => void;
}) {
  const isCut = /NEGATE|STOP/.test(a.action);
  const isReduce = /REDUCE/.test(a.action);
  const icon = isCut ? <Ban size={13} className="text-red-400" />
    : isReduce ? <ArrowDownRight size={13} className="text-amber-400" />
    : <ArrowUpRight size={13} className="text-emerald-400" />;
  const claim = isCut
    ? `Stop "${a.search_term}" for ${family}`
    : isReduce
    ? `Lower the bid on "${a.targeting || a.search_term}" for ${family}`
    : `Bid up "${a.targeting || a.search_term}" for ${family}`;
  const amazonChange = isCut
    ? `Add negative exact in: ${a.campaign_name}`
    : `${isReduce ? 'Reduce' : 'Raise'} keyword bid in: ${a.campaign_name}` +
      (a.recommended_bid ? ` → $${Number(a.recommended_bid).toFixed(2)}` : '');
  return (
    <div className="border border-border rounded-xl bg-card p-3 flex flex-col gap-1.5">
      <div className="flex items-center gap-2">
        {icon}
        <span className="text-[12px] font-semibold">{claim}</span>
        <button
          onClick={onQueue}
          disabled={inQueue}
          className={`ml-auto text-[10px] px-2 py-1 rounded-md border ${inQueue ? 'border-border text-faint' : 'border-blue-500/40 text-blue-400 hover:bg-blue-500/10'}`}
        >
          {inQueue ? 'Queued ✓' : <span className="flex items-center gap-1"><Plus size={10} /> Queue</span>}
        </button>
      </div>
      <div className="text-[10px] font-mono text-muted flex gap-3 tabular-nums">
        <span>spent {fM(a.spend || 0)} / 4w</span>
        <span>{a.clicks ?? 0} clicks</span>
        <span>{a.orders ?? 0} orders{(a.orders ?? 0) > 0 && a.net_roas != null ? ` · ROAS ${Number(a.net_roas).toFixed(2)}×` : ''}</span>
      </div>
      <div className="text-[10px] text-subtle">{why.reason}.</div>
      <div className="text-[9px] text-faint">{amazonChange}</div>
    </div>
  );
}
```

(Adjust field names only if `ActionRow` differs — verify against `types.ts` before assuming; `recommended_bid` may be `suggested_bid` on the row. If a referenced field doesn't exist on `ActionRow`, use the row's actual field and note it in the report.)

- [ ] **Step 2: Typecheck** — `npx tsc --noEmit` → clean.

- [ ] **Step 3: Commit**
```bash
git add src/components/Actions/DecisionCard.tsx
git commit --no-verify -m "feat(actions): DecisionCard — claim/evidence/change card for clear cases

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: ActionsPage integration — clear cases on top, the rest collapsed

**Files:**
- Modify: `dashboard-react/src/pages/ActionsPage.tsx`

- [ ] **Step 1: Compute the clear list.** After the `famModes` memo, add:

```ts
  // Stage-1 trust list: confidence-gated clear cases, capped, sorted by spend at stake.
  const CLEAR_CARD_CAP = 10;
  const clearCases = useMemo(() => {
    const out: { a: ActionRow; family: string; why: GateVerdict }[] = [];
    for (const a of acts) {
      const family = getFamily(a.product_short_name) || a.parent_name || '';
      if (!family) continue;
      const v = clearCase({
        action: a.action, spend: a.spend || 0, clicks: a.clicks || 0, orders: a.orders || 0,
        netRoas: a.net_roas ?? 0, mode: famModes.get(family) ?? effectiveCoachMode,
        confidence: (a as any).confidence || 'HIGH',
      });
      if (v.clear && !doQueue.isUploaded(a.search_term, a.campaign_id) && !doQueue.isDone(a.search_term, a.campaign_id)) {
        out.push({ a, family, why: v });
      }
    }
    out.sort((x, y) => (y.a.spend || 0) - (x.a.spend || 0));
    return out.slice(0, CLEAR_CARD_CAP);
  }, [acts, getFamily, famModes, effectiveCoachMode, doQueue.isUploaded, doQueue.isDone]);
```
Imports: add `clearCase` and `GateVerdict` to the `../coachActuals` import; add `DecisionCard` import. If `confidence` is not on `ActionRow`, check whether `V_ADS_COACH_ACTIONS`→cube loader already maps it (`grep -n confidence src/hooks/useCubeData.ts src/types.ts`); if it genuinely isn't loaded, default `'HIGH'` and report DONE_WITH_CONCERNS so the controller can decide whether to add the loader field.

- [ ] **Step 2: Render the section** above the Daily Queue block (before `{unifiedTree.length > 0 && (`):

```tsx
      {clearCases.length > 0 && (
        <div className="mb-4">
          <div className="flex items-baseline gap-2 mb-2">
            <span className="text-[11px] font-bold uppercase tracking-wider">✅ Clear cases</span>
            <span className="text-[10px] text-faint">{clearCases.length} obvious calls · everything else is under "Daily Queue" below</span>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
            {clearCases.map(({ a, family, why }) => (
              <DecisionCard
                key={`${a.campaign_id}|${a.search_term}|${a.action}`}
                action={a} family={family} why={why}
                inQueue={doQueue.hasItem(a.search_term, a.action, a.campaign_name)}
                onQueue={() => {/* copy the EXACT doQueue.addItem({...}) construction used by the existing row's queue button — find it in ActionRowComponent and reuse verbatim */}}
              />
            ))}
          </div>
        </div>
      )}
```
For `onQueue`: locate the existing add-to-queue call in `ActionRowComponent` (search `doQueue.addItem` / `addItem(` in ActionsPage.tsx) and replicate its exact item construction — same fields, same defaults — so queued cards are indistinguishable from queued rows downstream (Do page, bulksheet).

- [ ] **Step 3: Collapse the Daily Queue by default.** Add `const [showQueue, setShowQueue] = useState(false);` and wrap the existing Daily Queue tree: header row stays visible with item count + chevron toggling `showQueue`; the `divide-y` body renders only when `showQueue`. Rename its label to `Needs judgment / full queue`.

- [ ] **Step 4: Verify** — `npx tsc --noEmit && npm test && npm run build` all clean, then live-check in the preview (`:5173` Actions page): cards render with claim/evidence/reason, "Queue" adds the item (check the Do page), the big tree is collapsed by default. Screenshot as proof.

- [ ] **Step 5: Commit**
```bash
git add src/pages/ActionsPage.tsx
git commit --no-verify -m "feat(actions): Stage-1 trust view — clear-case decision cards, full queue collapsed

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Success test (the Stage-1 gate, human)
Ori reads the clear-case list daily for a few days and agrees with ~all of it. Disagreements = tune `GATE` constants (or report a coacher bug). Only then proceed to widening anything.
