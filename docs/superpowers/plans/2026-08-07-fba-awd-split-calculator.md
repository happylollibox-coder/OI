# FBA / AWD Split Calculator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only panel to the Plan page that takes a product and a carton count and recommends how many cartons go to FBA vs AWD, by which shipment method, arriving when — plus the AWD→FBA transfer schedule that keeps FBA near 100 days of cover.

**Architecture:** Hybrid. Policy inputs (transit days, inbound buffer, demand forecast, package quantity, on-hand stock) come from BigQuery via existing endpoints. The split arithmetic and forward-DOC walk are pure TypeScript, extracted from the projection math that already lives inside `StockProjectionChart` so both consumers share one implementation instead of two. The panel writes nothing.

**Tech Stack:** React 19, TypeScript 5.9 (strict), Vite 7, Recharts 3, Vitest 3, Tailwind 4.

**Spec:** `docs/superpowers/specs/2026-08-07-fba-awd-split-calculator-design.md`

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `dashboard-react/src/stockProjection.ts` | Create | Pure projection math: demand curve, weekly buckets, forward DOC. Extracted from `StockProjectionChart`. |
| `dashboard-react/src/stockProjection.test.ts` | Create | Parity + golden tests for the extraction. |
| `dashboard-react/src/fbaAwdSplit.ts` | Create | Pure split engine: method selection, FBA sizing, AWD remainder, transfer schedule. |
| `dashboard-react/src/fbaAwdSplit.test.ts` | Create | Behaviour tests, one per rule and edge case. |
| `dashboard-react/src/hooks/useInventorySnapshot.ts` | Create | Cube inventory query + pure row mapper, shared by both panels. |
| `dashboard-react/src/hooks/useInventorySnapshot.test.ts` | Create | Tests for the pure row mapper. |
| `dashboard-react/src/hooks/useShipmentConstants.ts` | Create | LOV fetch for transit days + FBA inbound buffer, with pure parser. |
| `dashboard-react/src/hooks/useShipmentConstants.test.ts` | Create | Tests for the pure LOV parser. |
| `dashboard-react/src/components/FbaAwdSplitPanel.tsx` | Create | Panel UI: input, ledger, decision rows. |
| `dashboard-react/src/components/SplitSimulationChart.tsx` | Create | Two-pool weekly chart with the display window. |
| `dashboard-react/src/components/ShipmentEngine.tsx` | Modify (~1401-1605) | Import the extracted math instead of inlining it. |
| `dashboard-react/src/pages/PlanPage.tsx` | Modify (~698-760, ~1804) | Use the shared inventory hook; mount the panel. |

**Run all tests with:** `cd /Users/ori/Develop/OI/dashboard-react && npm test`

**Modelling note carried through every task:** unmet demand is *lost*, not backlogged. Stock floors at zero. This matches the existing chart, which stores `Math.max(0, ...)` for both stock series.

---

### Task 1: Extract the projection math

The math currently lives inside a `useMemo` in `StockProjectionChart` (`ShipmentEngine.tsx:1443-1605`) and cannot be tested or reused. Extract it verbatim first, prove the extraction is faithful, then switch the chart over.

**Files:**
- Create: `dashboard-react/src/stockProjection.ts`
- Create: `dashboard-react/src/stockProjection.test.ts`
- Modify: `dashboard-react/src/components/ShipmentEngine.tsx:1401-1605`

- [ ] **Step 1: Create the module with the extracted math**

Create `dashboard-react/src/stockProjection.ts`:

```ts
// Pure stock-projection math, extracted from StockProjectionChart so the
// Weekly Stock Projection chart and the FBA/AWD split engine share one
// implementation. No React, no fetch — everything here is deterministic.
import type { MonthSeasonInfo } from './planTypes';

export interface ProjectionWeek {
  week: string;       // YYYY-MM-DD (Monday)
  weekLabel: string;  // Short label for x-axis
  stock: number;      // Projected stock at end of week (with suggested)
  confirmedStock: number; // Without suggested shipments
  arrivals: number;   // Units arriving this week (all sources)
  confirmedArrivals: number; // Only in-transit + approved + scheduled
  demand: number;     // Weekly demand consumed
  isPeak: boolean;
  arrivalDates: string[]; // Actual arrival dates within this week
  doc: number;        // Days of Cover (confirmed stock)
  docSuggested: number; // Days of Cover (confirmed + suggested stock)
  actualSales?: number;
  actualSalesLY?: number;
}

export type ShipmentStatus =
  | 'arrived' | 'transit' | 'approved' | 'scheduled'
  | 'suggested' | 'po_needed' | 'po';

export interface ProjectionShipment {
  qty: number;
  arrival_date: string;
  status: ShipmentStatus;
  route?: string;
}

/** product demand + family seasonality + growth override, as one curve */
export interface DemandCurve {
  productDemand: Record<number, number>;          // yyyyMM -> units
  familySeason: Record<number, MonthSeasonInfo>;  // yyyyMM -> peak/offseason days
  growth: number;                                 // growth override multiplier
}

/** Real, committed movements. Everything else is a proposal. */
export const CONFIRMED_STATUSES: ReadonlySet<string> = new Set(['transit', 'approved', 'scheduled']);

/** PO completion means goods sit at the manufacturer, not in a warehouse. */
export const EXCLUDED_STATUSES: ReadonlySet<string> = new Set(['po_needed', 'po']);

export function getMonday(d: Date): Date {
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  return new Date(d.getFullYear(), d.getMonth(), diff);
}

export function addDays(d: Date, n: number): Date {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}

/** Format a local Date as YYYY-MM-DD without the UTC shift toISOString applies. */
export function localDateKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export const MONTH_ABBR = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

export function fmtWeekLabel(d: Date): string {
  return `${MONTH_ABBR[d.getMonth()]} ${d.getDate()}`;
}

export function daysInMonth(year: number, month: number): number {
  return new Date(year, month + 1, 0).getDate();
}

/**
 * Demand for a single day. Peak days carry ~2x the rate of offseason days in
 * the same month: totalUnits = peakDays*rate*2 + offDays*rate.
 * Peak days are assumed to be the last N days of the month (holiday rush).
 */
export function dailyDemandOn(day: Date, curve: DemandCurve): { units: number; isPeak: boolean } {
  const yr = day.getFullYear();
  const mo = day.getMonth();
  const yearMonth = yr * 100 + (mo + 1);
  const monthUnits = (curve.productDemand[yearMonth] || 0) * curve.growth;
  if (monthUnits <= 0) return { units: 0, isPeak: false };

  const totalDaysInMo = daysInMonth(yr, mo);
  const season = curve.familySeason[yearMonth];
  const peakDays = season?.peakDays ?? 0;
  const offDays = season?.offseasonDays ?? (totalDaysInMo - peakDays);

  if (peakDays > 0 && offDays > 0) {
    const rate = monthUnits / (peakDays * 2 + offDays);
    const isPeakDay = day.getDate() > (totalDaysInMo - peakDays);
    return { units: isPeakDay ? rate * 2 : rate, isPeak: isPeakDay };
  }
  return { units: monthUnits / totalDaysInMo, isPeak: false };
}

/** Demand across a week (Mon-Sun), stopping at endDate. */
export function weeklyDemand(weekStart: Date, curve: DemandCurve, endDate: Date): { demand: number; isPeak: boolean } {
  let totalDemand = 0;
  let hasPeak = false;
  for (let d = 0; d < 7; d++) {
    const day = addDays(weekStart, d);
    if (day > endDate) break;
    const { units, isPeak } = dailyDemandOn(day, curve);
    totalDemand += units;
    if (isPeak) hasPeak = true;
  }
  return { demand: Math.round(totalDemand), isPeak: hasPeak };
}

/** Total demand over [start, endExclusive). Used to size a DOC target exactly. */
export function demandOverWindow(start: Date, endExclusive: Date, curve: DemandCurve): number {
  let total = 0;
  for (let d = new Date(start); d < endExclusive; d = addDays(d, 1)) {
    total += dailyDemandOn(d, curve).units;
  }
  return total;
}

/**
 * Days of cover: walk forward from week `fromIndex` consuming `startStock`
 * against each week's demand until it runs out. Capped at 365.
 */
export function forwardDoc(weeks: Array<{ demand: number }>, fromIndex: number, startStock: number): number {
  let rem = Math.max(0, startStock);
  let days = 0;
  for (let j = fromIndex; j < weeks.length && rem > 0; j++) {
    const futDemand = weeks[j].demand;
    if (futDemand <= 0) { days += 7; continue; }
    const dailyD = futDemand / 7;
    days += Math.min(7, rem / dailyD);
    rem -= futDemand;
  }
  return Math.min(Math.round(days), 365);
}

export interface ProjectionParams {
  currentStock: number;
  shipments: ProjectionShipment[];
  curve: DemandCurve;
  startDate: Date;  // snapped to its Monday internally
  endDate: Date;
  now: Date;
  weeklySales?: Record<string, number>;
  weeklySalesLY?: Record<string, number>;
}

/** Weekly stock projection. Past weeks carry no demand and no arrivals. */
export function buildWeeklyProjection(p: ProjectionParams): ProjectionWeek[] {
  const { currentStock, shipments, curve, endDate, now, weeklySales, weeklySalesLY } = p;
  const startMonday = getMonday(p.startDate);
  const currentMonday = getMonday(now);
  const weeks: ProjectionWeek[] = [];

  const arrivalByWeek = new Map<string, { confirmed: number; total: number; dates: Set<string> }>();
  for (const sh of shipments) {
    if (EXCLUDED_STATUSES.has(sh.status)) continue;
    const arrDate = sh.arrival_date ? new Date(sh.arrival_date) : null;
    if (!arrDate || isNaN(arrDate.getTime())) continue;
    const key = localDateKey(getMonday(arrDate));
    const entry = arrivalByWeek.get(key) || { confirmed: 0, total: 0, dates: new Set<string>() };
    entry.total += sh.qty;
    if (CONFIRMED_STATUSES.has(sh.status)) entry.confirmed += sh.qty;
    entry.dates.add(`${MONTH_ABBR[arrDate.getMonth()]} ${arrDate.getDate()}`);
    arrivalByWeek.set(key, entry);
  }

  let runningConfirmed = currentStock;
  let runningTotal = currentStock;
  let weekStart = new Date(startMonday);

  while (weekStart <= endDate) {
    const key = localDateKey(weekStart);
    const isPast = weekStart < currentMonday;
    const { demand: rawDemand, isPeak } = weeklyDemand(weekStart, curve, endDate);
    const demand = isPast ? 0 : rawDemand;
    const arrival = arrivalByWeek.get(key) || { confirmed: 0, total: 0, dates: new Set<string>() };
    const adjArrivalConf = isPast ? 0 : arrival.confirmed;
    const adjArrivalTotal = isPast ? 0 : arrival.total;

    runningConfirmed = runningConfirmed - demand + adjArrivalConf;
    runningTotal = runningTotal - demand + adjArrivalTotal;

    weeks.push({
      week: key,
      weekLabel: fmtWeekLabel(weekStart),
      stock: Math.max(0, Math.round(runningTotal)),
      confirmedStock: Math.max(0, Math.round(runningConfirmed)),
      arrivals: isPast ? 0 : arrival.total,
      confirmedArrivals: isPast ? 0 : arrival.confirmed,
      demand,
      isPeak,
      arrivalDates: isPast ? [] : [...arrival.dates],
      doc: 0,
      docSuggested: 0,
      actualSales: weeklySales?.[key],
      actualSalesLY: weeklySalesLY?.[key],
    });

    weekStart = addDays(weekStart, 7);
  }

  for (let i = 0; i < weeks.length; i++) {
    weeks[i].doc = forwardDoc(weeks, i, weeks[i].confirmedStock);
    weeks[i].docSuggested = forwardDoc(weeks, i, weeks[i].stock);
  }

  return weeks;
}
```

- [ ] **Step 2: Write the parity test**

This freezes a copy of the *original* inline implementation inside the test file and asserts the extracted module produces byte-identical output. It is scaffolding: Step 6 replaces it with golden values once parity is proven.

Create `dashboard-react/src/stockProjection.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import type { MonthSeasonInfo } from './planTypes';
import {
  buildWeeklyProjection, getMonday, addDays, localDateKey, daysInMonth,
  type ProjectionShipment, type DemandCurve, type ProjectionWeek,
} from './stockProjection';

// ── Frozen copy of the pre-extraction implementation (ShipmentEngine.tsx:1455-1605).
// Exists only to prove the extraction is faithful. Deleted in Step 6.
function legacyProjection(
  currentStock: number,
  allShipments: ProjectionShipment[],
  productDemand: Record<number, number>,
  familySeason: Record<number, MonthSeasonInfo>,
  growthFactor: number,
  startRef: Date,
  endDate: Date,
  now: Date,
): ProjectionWeek[] {
  const startMonday = getMonday(startRef);
  const currentMonday = getMonday(now);
  const weeks: ProjectionWeek[] = [];
  const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  const arrivalByWeek = new Map<string, { confirmed: number; total: number; dates: Set<string> }>();
  for (const sh of allShipments) {
    if (sh.status === 'po_needed' || sh.status === 'po') continue;
    const arrDate = sh.arrival_date ? new Date(sh.arrival_date) : null;
    if (!arrDate || isNaN(arrDate.getTime())) continue;
    const key = localDateKey(getMonday(arrDate));
    const entry = arrivalByWeek.get(key) || { confirmed: 0, total: 0, dates: new Set<string>() };
    entry.total += sh.qty;
    if (sh.status === 'transit' || sh.status === 'approved' || sh.status === 'scheduled') {
      entry.confirmed += sh.qty;
    }
    entry.dates.add(`${MONTHS[arrDate.getMonth()]} ${arrDate.getDate()}`);
    arrivalByWeek.set(key, entry);
  }

  function weeklyDemandLegacy(weekStart: Date): { demand: number; isPeak: boolean } {
    let totalDemand = 0;
    let hasPeak = false;
    for (let d = 0; d < 7; d++) {
      const day = addDays(weekStart, d);
      if (day > endDate) break;
      const yr = day.getFullYear();
      const mo = day.getMonth();
      const yearMonth = yr * 100 + (mo + 1);
      const monthUnits = (productDemand[yearMonth] || 0) * growthFactor;
      if (monthUnits <= 0) continue;
      const totalDaysInMo = daysInMonth(yr, mo);
      const season = familySeason[yearMonth];
      const peakDays = season?.peakDays ?? 0;
      const offDays = season?.offseasonDays ?? (totalDaysInMo - peakDays);
      if (peakDays > 0 && offDays > 0) {
        const rate = monthUnits / (peakDays * 2 + offDays);
        const isPeakDay = day.getDate() > (totalDaysInMo - peakDays);
        totalDemand += isPeakDay ? rate * 2 : rate;
        if (isPeakDay) hasPeak = true;
      } else {
        totalDemand += monthUnits / totalDaysInMo;
      }
    }
    return { demand: Math.round(totalDemand), isPeak: hasPeak };
  }

  let runningConfirmed = currentStock;
  let runningTotal = currentStock;
  let weekStart = new Date(startMonday);

  while (weekStart <= endDate) {
    const key = localDateKey(weekStart);
    const isPast = weekStart < currentMonday;
    const { demand: rawDemand, isPeak } = weeklyDemandLegacy(weekStart);
    const demand = isPast ? 0 : rawDemand;
    const arrival = arrivalByWeek.get(key) || { confirmed: 0, total: 0, dates: new Set<string>() };
    const adjArrivalConf = isPast ? 0 : arrival.confirmed;
    const adjArrivalTotal = isPast ? 0 : arrival.total;
    runningConfirmed = runningConfirmed - demand + adjArrivalConf;
    runningTotal = runningTotal - demand + adjArrivalTotal;
    weeks.push({
      week: key,
      weekLabel: `${MONTHS[weekStart.getMonth()]} ${weekStart.getDate()}`,
      stock: Math.max(0, Math.round(runningTotal)),
      confirmedStock: Math.max(0, Math.round(runningConfirmed)),
      arrivals: isPast ? 0 : arrival.total,
      confirmedArrivals: isPast ? 0 : arrival.confirmed,
      demand, isPeak,
      arrivalDates: isPast ? [] : [...arrival.dates],
      doc: 0, docSuggested: 0,
      actualSales: undefined, actualSalesLY: undefined,
    });
    weekStart = addDays(weekStart, 7);
  }

  for (let i = 0; i < weeks.length; i++) {
    let remConf = Math.max(0, weeks[i].confirmedStock);
    let daysConf = 0;
    for (let j = i; j < weeks.length && remConf > 0; j++) {
      const futDemand = weeks[j].demand;
      if (futDemand <= 0) { daysConf += 7; continue; }
      const dailyD = futDemand / 7;
      daysConf += Math.min(7, remConf / dailyD);
      remConf -= futDemand;
    }
    weeks[i].doc = Math.min(Math.round(daysConf), 365);

    let remSugg = Math.max(0, weeks[i].stock);
    let daysSugg = 0;
    for (let j = i; j < weeks.length && remSugg > 0; j++) {
      const futDemand = weeks[j].demand;
      if (futDemand <= 0) { daysSugg += 7; continue; }
      const dailyD = futDemand / 7;
      daysSugg += Math.min(7, remSugg / dailyD);
      remSugg -= futDemand;
    }
    weeks[i].docSuggested = Math.min(Math.round(daysSugg), 365);
  }

  return weeks;
}

const SEASON: Record<number, MonthSeasonInfo> = {
  202610: { peakDays: 10, offseasonDays: 21, holidays: 'Halloween' },
  202611: { peakDays: 12, offseasonDays: 18, holidays: 'BFCM' },
  202612: { peakDays: 15, offseasonDays: 16, holidays: 'Christmas' },
};

const DEMAND: Record<number, number> = {
  202608: 900, 202609: 1000, 202610: 1400, 202611: 1800, 202612: 2200,
  202701: 800, 202702: 700, 202703: 700,
};

const NOW = new Date(2026, 7, 7);   // 2026-08-07
const END = new Date(2027, 2, 29);  // 2027-03-29

const FIXTURES: Array<{ name: string; stock: number; shipments: ProjectionShipment[]; growth: number }> = [
  { name: 'no shipments', stock: 5000, shipments: [], growth: 1.0 },
  {
    name: 'mixed statuses',
    stock: 1200,
    shipments: [
      { qty: 252, arrival_date: '2026-08-12', status: 'transit', route: 'MFR→FBA' },
      { qty: 1296, arrival_date: '2026-08-26', status: 'approved', route: 'MFR→AWD' },
      { qty: 4000, arrival_date: '2026-10-01', status: 'suggested', route: 'MFR→AWD' },
      { qty: 9999, arrival_date: '2026-09-15', status: 'po', route: 'MFR' },
      { qty: 8888, arrival_date: '2026-09-20', status: 'po_needed' },
    ],
    growth: 1.0,
  },
  { name: 'growth override', stock: 300, shipments: [{ qty: 2000, arrival_date: '2026-09-09', status: 'scheduled' }], growth: 1.25 },
];

describe('buildWeeklyProjection parity with pre-extraction implementation', () => {
  for (const fx of FIXTURES) {
    it(`matches legacy output — ${fx.name}`, () => {
      const curve: DemandCurve = { productDemand: DEMAND, familySeason: SEASON, growth: fx.growth };
      const extracted = buildWeeklyProjection({
        currentStock: fx.stock, shipments: fx.shipments, curve,
        startDate: NOW, endDate: END, now: NOW,
      });
      const legacy = legacyProjection(fx.stock, fx.shipments, DEMAND, SEASON, fx.growth, NOW, END, NOW);
      expect(extracted).toEqual(legacy);
    });
  }
});
```

- [ ] **Step 3: Run the parity test**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- stockProjection
```

Expected: 3 tests PASS. If any fail, the extraction diverged — fix `stockProjection.ts` to match the legacy copy, never the other way round.

- [ ] **Step 4: Commit the extraction**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/stockProjection.ts dashboard-react/src/stockProjection.test.ts
git commit -m "refactor: extract stock projection math into pure module

Verified byte-identical to the inline StockProjectionChart implementation
via a frozen legacy copy in the test file."
```

- [ ] **Step 5: Print golden values**

Add this line inside the parity test's `it(...)` body, directly after `const legacy = ...`:

```ts
      if (fx.name === 'no shipments') console.log('GOLDEN_FIRST_WEEK=' + JSON.stringify(extracted[0]));
```

Run:

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- stockProjection 2>&1 | grep GOLDEN_FIRST_WEEK
```

Expected: one line of JSON, for example
`GOLDEN_FIRST_WEEK={"week":"2026-08-03","weekLabel":"Aug 3","stock":5000,...}`

Copy that JSON object. Remove the `console.log` line before moving on.

- [ ] **Step 6: Replace parity scaffolding with golden tests**

Delete `legacyProjection` and the `describe` block that uses it from `stockProjection.test.ts`, and append these permanent tests. Fill `EXPECTED_FIRST_WEEK` with the values captured in Step 5.

```ts
describe('buildWeeklyProjection', () => {
  const curve: DemandCurve = { productDemand: DEMAND, familySeason: SEASON, growth: 1.0 };

  it('starts on the Monday of the start date', () => {
    const weeks = buildWeeklyProjection({
      currentStock: 5000, shipments: [], curve,
      startDate: new Date(2026, 7, 7), endDate: END, now: NOW,
    });
    expect(weeks[0].week).toBe('2026-08-03');
  });

  it('produces the recorded golden first week', () => {
    const weeks = buildWeeklyProjection({
      currentStock: 5000, shipments: [], curve,
      startDate: NOW, endDate: END, now: NOW,
    });
    // Paste the JSON object captured in Step 5 — these values were proven
    // identical to the pre-extraction implementation.
    expect(weeks[0]).toEqual(/* GOLDEN_FIRST_WEEK from Step 5 */);
  });

  it('excludes PO and po_needed shipments from arrivals', () => {
    const weeks = buildWeeklyProjection({
      currentStock: 0, curve, startDate: NOW, endDate: END, now: NOW,
      shipments: [
        { qty: 500, arrival_date: '2026-09-09', status: 'po' },
        { qty: 500, arrival_date: '2026-09-09', status: 'po_needed' },
      ],
    });
    expect(weeks.every(w => w.arrivals === 0)).toBe(true);
  });

  it('counts suggested in stock but not confirmedStock', () => {
    const weeks = buildWeeklyProjection({
      currentStock: 10000, curve, startDate: NOW, endDate: END, now: NOW,
      shipments: [{ qty: 3000, arrival_date: '2026-09-09', status: 'suggested' }],
    });
    const w = weeks.find(x => x.week === '2026-09-07')!;
    expect(w.arrivals).toBe(3000);
    expect(w.confirmedArrivals).toBe(0);
    expect(w.stock).toBeGreaterThan(w.confirmedStock);
  });

  it('floors stock at zero rather than going negative', () => {
    const weeks = buildWeeklyProjection({
      currentStock: 10, shipments: [], curve, startDate: NOW, endDate: END, now: NOW,
    });
    expect(weeks.every(w => w.stock >= 0 && w.confirmedStock >= 0)).toBe(true);
  });
});

describe('demandOverWindow', () => {
  const curve: DemandCurve = { productDemand: DEMAND, familySeason: SEASON, growth: 1.0 };

  it('sums a whole month back to that month total', () => {
    const total = demandOverWindow(new Date(2026, 8, 1), new Date(2026, 9, 1), curve);
    expect(total).toBeCloseTo(1000, 6);
  });

  it('applies the growth multiplier', () => {
    const grown: DemandCurve = { ...curve, growth: 2 };
    const total = demandOverWindow(new Date(2026, 8, 1), new Date(2026, 9, 1), grown);
    expect(total).toBeCloseTo(2000, 6);
  });

  it('returns zero for months with no forecast', () => {
    const total = demandOverWindow(new Date(2028, 0, 1), new Date(2028, 1, 1), curve);
    expect(total).toBe(0);
  });
});

describe('forwardDoc', () => {
  it('caps at 365', () => {
    expect(forwardDoc([{ demand: 1 }], 0, 1_000_000)).toBe(365);
  });

  it('returns 0 for no stock', () => {
    expect(forwardDoc([{ demand: 100 }], 0, 0)).toBe(0);
  });

  it('gives 7 days when stock exactly covers one week', () => {
    expect(forwardDoc([{ demand: 70 }, { demand: 70 }], 0, 70)).toBe(7);
  });
});
```

Add `demandOverWindow` and `forwardDoc` to the import list at the top of the test file.

- [ ] **Step 7: Run tests**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- stockProjection
```

Expected: all PASS.

- [ ] **Step 8: Switch the chart over**

In `dashboard-react/src/components/ShipmentEngine.tsx`:

1. Add to the imports at the top of the file:

```ts
import {
  buildWeeklyProjection, getMonday, addDays, localDateKey, fmtWeekLabel, daysInMonth,
  type ProjectionWeek,
} from '../stockProjection';
```

2. Delete the local `interface ProjectionWeek` (line 1401) and the local `getMonday`, `addDays`, `localDateKey`, `fmtWeekLabel`, `daysInMonth` definitions (lines 1417-1441).

3. Replace the entire `useMemo` body inside `StockProjectionChart` (lines 1455-1605) with:

```ts
  const data = useMemo<ProjectionWeek[]>(() => {
    const now = new Date();
    const startRef = timelineMinDate ? new Date(Math.min(timelineMinDate, now.getTime())) : now;
    const yearEnd = new Date(now.getFullYear(), 11, 31);
    const lastArrival = allShipments.reduce((max, s) => {
      const t = s.arrival_date ? new Date(s.arrival_date).getTime() : 0;
      return t > max ? t : max;
    }, 0);
    const endDate = new Date(Math.max(yearEnd.getTime(), lastArrival) + 13 * 7 * 86400000);

    return buildWeeklyProjection({
      currentStock,
      shipments: allShipments,
      curve: {
        productDemand: demandMap[product] || {},
        familySeason: metaMap[product]?.family ? (seasonMap[metaMap[product].family] || {}) : {},
        growth: growthOverrides?.[product] ?? 1.0,
      },
      startDate: startRef,
      endDate,
      now,
      weeklySales,
      weeklySalesLY,
    });
  }, [product, currentStock, allShipments, demandMap, seasonMap, metaMap, growthOverrides, timelineMinDate, weeklySales, weeklySalesLY]);
```

- [ ] **Step 9: Verify nothing else broke**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test && npx tsc --noEmit
```

Expected: all tests PASS, no type errors. `npx tsc --noEmit` may surface pre-existing errors elsewhere — only errors in `ShipmentEngine.tsx` or `stockProjection.ts` are yours to fix.

- [ ] **Step 10: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/components/ShipmentEngine.tsx dashboard-react/src/stockProjection.test.ts
git commit -m "refactor: StockProjectionChart uses the shared projection module"
```

---

### Task 2: Inventory snapshot hook

`ReplenishmentFlowWrapper` loads FBA/AWD/MFR stock from Cube inline (`PlanPage.tsx:698-751`) and merges FBA+AWD into one `stockMap`. The split panel needs the same data unmerged, and firing the query twice would be wasteful. Lift it into a hook with a pure, testable row mapper.

**Files:**
- Create: `dashboard-react/src/hooks/useInventorySnapshot.ts`
- Create: `dashboard-react/src/hooks/useInventorySnapshot.test.ts`
- Modify: `dashboard-react/src/pages/PlanPage.tsx:698-751`

- [ ] **Step 1: Write the failing test**

Create `dashboard-react/src/hooks/useInventorySnapshot.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { mapInventoryRows } from './useInventorySnapshot';

const row = (product: string, source: string, units: number) => ({
  'InventorySnapshot.productShortName': product,
  'InventorySnapshot.sourceType': source,
  'InventorySnapshot.totalUnits': units,
});

describe('mapInventoryRows', () => {
  it('keeps FBA and AWD separate and also sums them into stockMap', () => {
    const maps = mapInventoryRows([row('Bottle', 'FBA', 300), row('Bottle', 'AWD', 700)]);
    expect(maps.fbaMap).toEqual({ Bottle: 300 });
    expect(maps.awdMap).toEqual({ Bottle: 700 });
    expect(maps.stockMap).toEqual({ Bottle: 1000 });
  });

  it('separates manufacturer buckets from sellable stock', () => {
    const maps = mapInventoryRows([
      row('Bunny', 'MFR Ready', 500),
      row('Bunny', 'In Production', 250),
    ]);
    expect(maps.mfrReadyMap).toEqual({ Bunny: 500 });
    expect(maps.mfrInProdMap).toEqual({ Bunny: 250 });
    expect(maps.stockMap).toEqual({});
  });

  it('accumulates repeated rows for the same product and source', () => {
    const maps = mapInventoryRows([row('Fresh', 'FBA', 100), row('Fresh', 'FBA', 50)]);
    expect(maps.fbaMap).toEqual({ Fresh: 150 });
  });

  it('ignores rows with no product name', () => {
    const maps = mapInventoryRows([row('', 'FBA', 999)]);
    expect(maps.fbaMap).toEqual({});
  });

  it('ignores unknown source types', () => {
    const maps = mapInventoryRows([row('Bottle', 'Reserved', 400)]);
    expect(maps.stockMap).toEqual({});
    expect(maps.fbaMap).toEqual({});
  });
});
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- useInventorySnapshot
```

Expected: FAIL — cannot resolve `./useInventorySnapshot`.

- [ ] **Step 3: Write the hook**

Create `dashboard-react/src/hooks/useInventorySnapshot.ts`:

```ts
import { useState, useEffect } from 'react';
import { cubeLoad } from './useCubeData';

export interface InventoryMaps {
  stockMap: Record<string, number>;    // FBA + AWD, for consumers that want one pooled number
  fbaMap: Record<string, number>;
  awdMap: Record<string, number>;
  mfrReadyMap: Record<string, number>;
  mfrInProdMap: Record<string, number>;
}

const EMPTY: InventoryMaps = { stockMap: {}, fbaMap: {}, awdMap: {}, mfrReadyMap: {}, mfrInProdMap: {} };

/** Pure: fold Cube rows into per-source maps. */
export function mapInventoryRows(rows: Record<string, unknown>[]): InventoryMaps {
  const maps: InventoryMaps = { stockMap: {}, fbaMap: {}, awdMap: {}, mfrReadyMap: {}, mfrInProdMap: {} };
  const add = (m: Record<string, number>, k: string, v: number) => { m[k] = (m[k] || 0) + v; };

  for (const r of rows) {
    const product = String(r['InventorySnapshot.productShortName'] ?? '');
    const source = String(r['InventorySnapshot.sourceType'] ?? '');
    const units = Number(r['InventorySnapshot.totalUnits'] ?? 0);
    if (!product) continue;

    if (source === 'FBA') { add(maps.stockMap, product, units); add(maps.fbaMap, product, units); }
    else if (source === 'AWD') { add(maps.stockMap, product, units); add(maps.awdMap, product, units); }
    else if (source === 'MFR Ready') add(maps.mfrReadyMap, product, units);
    else if (source === 'In Production') add(maps.mfrInProdMap, product, units);
  }
  return maps;
}

/** Latest InventorySnapshot, folded per source. One query shared by all consumers. */
export function useInventorySnapshot(): InventoryMaps & { loading: boolean; snapshotDate: string | null } {
  const [maps, setMaps] = useState<InventoryMaps>(EMPTY);
  const [snapshotDate, setSnapshotDate] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const dateRows = await cubeLoad({ measures: ['InventorySnapshot.latestSnapshotDate'] });
        const latestDate = (dateRows as Record<string, unknown>[])[0]?.['InventorySnapshot.latestSnapshotDate'];
        if (!latestDate) { setLoading(false); return; }

        const rows = await cubeLoad({
          measures: ['InventorySnapshot.totalUnits'],
          dimensions: ['InventorySnapshot.productShortName', 'InventorySnapshot.sourceType'],
          filters: [{ member: 'InventorySnapshot.date', operator: 'equals', values: [String(latestDate)] }],
        });
        setMaps(mapInventoryRows(rows as Record<string, unknown>[]));
        setSnapshotDate(String(latestDate));
      } catch (e) {
        console.warn('[useInventorySnapshot] load failed', e);
      }
      setLoading(false);
    })();
  }, []);

  return { ...maps, loading, snapshotDate };
}
```

- [ ] **Step 4: Run the test**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- useInventorySnapshot
```

Expected: 5 tests PASS.

- [ ] **Step 5: Use the hook in ReplenishmentFlowWrapper**

In `dashboard-react/src/pages/PlanPage.tsx`, delete the five `useState` map declarations and the whole `useEffect` that loads them (lines 698-751), and replace with:

```ts
  const {
    stockMap, fbaMap, awdMap, mfrReadyMap, mfrInProdMap,
    loading: stockLoading, snapshotDate,
  } = useInventorySnapshot();
```

Add the import near the other hook imports:

```ts
import { useInventorySnapshot } from '../hooks/useInventorySnapshot';
```

`snapshotDate` is unused here; prefix with `_` or omit it from the destructure if the linter objects.

- [ ] **Step 6: Verify**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test && npx tsc --noEmit 2>&1 | grep -E "PlanPage|useInventorySnapshot" || echo "no new type errors"
```

Expected: tests PASS, no type errors naming those two files.

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/hooks/useInventorySnapshot.ts dashboard-react/src/hooks/useInventorySnapshot.test.ts dashboard-react/src/pages/PlanPage.tsx
git commit -m "refactor: share the inventory snapshot query via useInventorySnapshot"
```

---

### Task 3: Shipment constants from LOV

Transit days and the FBA inbound buffer must be read at runtime, never hardcoded — a changed LOV has to explain a changed answer. `/api/lov/<lov_set>` already exists and is already used by `CreateShipmentModal.tsx:106`.

**Files:**
- Create: `dashboard-react/src/hooks/useShipmentConstants.ts`
- Create: `dashboard-react/src/hooks/useShipmentConstants.test.ts`

- [ ] **Step 1: Write the failing test**

Create `dashboard-react/src/hooks/useShipmentConstants.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { parseTransitDays, parseBufferDays, DEFAULT_CONSTANTS } from './useShipmentConstants';

const lov = (value_id: string, attr1_value: string) => ({
  value_id, value_caption: value_id, is_default: false,
  attr1_name: 'SHIPMENT_DAYS', attr1_value,
});

describe('parseTransitDays', () => {
  it('maps value_id to numeric days', () => {
    const days = parseTransitDays([lov('FAST_SEA', '27'), lov('SLOW_SEA', '33'), lov('AWD_SLOW_SEA', '63')]);
    expect(days).toEqual({ FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63 });
  });

  it('skips entries with a non-numeric or missing value', () => {
    const days = parseTransitDays([lov('FAST_SEA', '27'), lov('BROKEN', 'soon'), { value_id: 'NOATTR', value_caption: '', is_default: false }]);
    expect(days).toEqual({ FAST_SEA: 27 });
  });

  it('returns an empty map for no rows', () => {
    expect(parseTransitDays([])).toEqual({});
  });
});

describe('parseBufferDays', () => {
  it('reads FBA_INBOUND_BUFFER_DAYS', () => {
    expect(parseBufferDays([lov('FBA_INBOUND_BUFFER_DAYS', '10'), lov('FBA_ARRIVAL_DEADLINE', '1205')])).toBe(10);
  });

  it('falls back to the default when absent', () => {
    expect(parseBufferDays([])).toBe(DEFAULT_CONSTANTS.fbaInboundBufferDays);
  });
});
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- useShipmentConstants
```

Expected: FAIL — cannot resolve `./useShipmentConstants`.

- [ ] **Step 3: Write the hook**

Create `dashboard-react/src/hooks/useShipmentConstants.ts`:

```ts
import { useState, useEffect } from 'react';
import { apiFetch } from '../utils/apiFetch';

export interface LovRow {
  value_id: string;
  value_caption: string;
  is_default: boolean;
  attr1_name?: string;
  attr1_value?: string;
}

export interface ShipmentConstants {
  transitDays: Record<string, number>;  // value_id -> days
  fbaInboundBufferDays: number;
  loaded: boolean;
}

/** Used only when Flask is unreachable; the panel says so when this kicks in. */
export const DEFAULT_CONSTANTS = {
  transitDays: { AIR: 10, FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 } as Record<string, number>,
  fbaInboundBufferDays: 10,
};

export function parseTransitDays(rows: LovRow[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const r of rows) {
    const n = Number(r.attr1_value);
    if (!r.value_id || r.attr1_value == null || !Number.isFinite(n)) continue;
    out[r.value_id] = n;
  }
  return out;
}

export function parseBufferDays(rows: LovRow[]): number {
  const row = rows.find(r => r.value_id === 'FBA_INBOUND_BUFFER_DAYS');
  const n = Number(row?.attr1_value);
  return Number.isFinite(n) ? n : DEFAULT_CONSTANTS.fbaInboundBufferDays;
}

/** Transit days + FBA inbound buffer, read from DE_LIST_OF_VALUES at runtime. */
export function useShipmentConstants(): ShipmentConstants {
  const [state, setState] = useState<ShipmentConstants>({
    transitDays: DEFAULT_CONSTANTS.transitDays,
    fbaInboundBufferDays: DEFAULT_CONSTANTS.fbaInboundBufferDays,
    loaded: false,
  });

  useEffect(() => {
    (async () => {
      try {
        const [typeRes, peakRes] = await Promise.all([
          apiFetch('/api/lov/SHIPMENT_TYPE'),
          apiFetch('/api/lov/Q4_PEAK'),
        ]);
        const typeRows: LovRow[] = await typeRes.json();
        const peakRows: LovRow[] = await peakRes.json();
        if (!Array.isArray(typeRows) || !Array.isArray(peakRows)) return;
        setState({
          transitDays: parseTransitDays(typeRows),
          fbaInboundBufferDays: parseBufferDays(peakRows),
          loaded: true,
        });
      } catch (e) {
        console.warn('[useShipmentConstants] LOV load failed, using defaults', e);
      }
    })();
  }, []);

  return state;
}
```

- [ ] **Step 4: Run the test**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- useShipmentConstants
```

Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/hooks/useShipmentConstants.ts dashboard-react/src/hooks/useShipmentConstants.test.ts
git commit -m "feat: read shipment transit days and FBA inbound buffer from LOV"
```

---

### Task 4: The split engine

The core. Pure, no React, fully tested.

**Files:**
- Create: `dashboard-react/src/fbaAwdSplit.ts`
- Create: `dashboard-react/src/fbaAwdSplit.test.ts`

- [ ] **Step 1: Write the failing test for units, guards and Wednesday snapping**

Create `dashboard-react/src/fbaAwdSplit.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import type { MonthSeasonInfo } from './planTypes';
import type { DemandCurve, ProjectionShipment } from './stockProjection';
import { planSplit, nextWednesday, type SplitInput } from './fbaAwdSplit';

const SEASON: Record<number, MonthSeasonInfo> = {
  202611: { peakDays: 12, offseasonDays: 18, holidays: 'BFCM' },
  202612: { peakDays: 15, offseasonDays: 16, holidays: 'Christmas' },
};

// Flat 300/month everywhere = ~10/day, so DOC arithmetic is easy to reason about.
const FLAT: Record<number, number> = {
  202608: 300, 202609: 300, 202610: 310, 202611: 300, 202612: 310,
  202701: 310, 202702: 280, 202703: 310, 202704: 300, 202705: 310, 202706: 300,
};

const CURVE: DemandCurve = { productDemand: FLAT, familySeason: {}, growth: 1.0 };
const TODAY = new Date(2026, 7, 7); // Friday 2026-08-07

const base: SplitInput = {
  product: 'Bottle',
  cartons: 100,
  packageQuantity: 10,
  fbaOnHand: 0,
  awdOnHand: 0,
  shipments: [],
  curve: CURVE,
  transitDays: { FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 },
  fbaInboundBufferDays: 10,
  today: TODAY,
  targetDoc: 100,
};

describe('nextWednesday', () => {
  it('moves a Friday forward to the following Wednesday', () => {
    expect(nextWednesday(new Date(2026, 7, 7))).toEqual(new Date(2026, 7, 12));
  });

  it('returns the same day when already Wednesday', () => {
    expect(nextWednesday(new Date(2026, 7, 12))).toEqual(new Date(2026, 7, 12));
  });
});

describe('planSplit — input handling', () => {
  it('converts cartons to units via package quantity', () => {
    const plan = planSplit(base);
    expect(plan.units).toBe(1000);
  });

  it('refuses to compute with no demand forecast', () => {
    const plan = planSplit({ ...base, curve: { productDemand: {}, familySeason: {}, growth: 1 } });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/no demand forecast/i);
  });

  it('refuses to compute with a non-positive package quantity', () => {
    const plan = planSplit({ ...base, packageQuantity: 0 });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/package quantity/i);
  });

  it('refuses to compute with zero cartons', () => {
    const plan = planSplit({ ...base, cartons: 0 });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/cartons/i);
  });
});
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- fbaAwdSplit
```

Expected: FAIL — cannot resolve `./fbaAwdSplit`.

- [ ] **Step 3: Write the engine**

Create `dashboard-react/src/fbaAwdSplit.ts`:

```ts
// Pure FBA/AWD split engine. Given a batch of cartons ready at the
// manufacturer, decide how much goes to FBA now, how much to AWD, by which
// method, and what AWD->FBA transfers hold FBA near its DOC target.
//
// Advisory only: nothing here writes, and nothing here is a commitment.
// Modelling note: unmet demand is lost, not backlogged. Stock floors at zero.
import {
  addDays, localDateKey, getMonday, demandOverWindow, dailyDemandOn,
  CONFIRMED_STATUSES, EXCLUDED_STATUSES,
  type DemandCurve, type ProjectionShipment,
} from './stockProjection';

export type FbaMethod = 'SLOW_SEA' | 'FAST_SEA';

/** Cheapest first. AIR is deliberately absent — never auto-selected, never offered. */
export const FBA_METHODS: FbaMethod[] = ['SLOW_SEA', 'FAST_SEA'];

export interface SplitInput {
  product: string;
  cartons: number;
  packageQuantity: number;
  fbaOnHand: number;
  awdOnHand: number;
  shipments: ProjectionShipment[];
  curve: DemandCurve;
  transitDays: Record<string, number>;
  fbaInboundBufferDays: number;
  today: Date;
  targetDoc: number;
  methodOverride?: FbaMethod;
}

export interface SplitLeg {
  destination: 'FBA' | 'AWD';
  units: number;
  cartons: number;
  method: string;
  shipDate: string;
  transitDays: number;
  arrivalDate: string;
  sellableDate: string;
  reason: string;
}

export interface TransferRow {
  orderDate: string;
  arrivalDate: string;
  units: number;
  cartons: number;
  docBefore: number;
  docAfter: number;
}

export interface SplitPlan {
  ok: boolean;
  error?: string;
  units: number;
  legs: SplitLeg[];
  transfers: TransferRow[];
  fbaDocAtArrival: number;
  fbaOosDate: string | null;
  leftoverAwdUnits: number;
  warnings: string[];
}

const fail = (error: string): SplitPlan => ({
  ok: false, error, units: 0, legs: [], transfers: [],
  fbaDocAtArrival: 0, fbaOosDate: null, leftoverAwdUnits: 0, warnings: [],
});

/** Ship dates snap to Wednesday, matching the plan engine's ship_wednesday convention. */
export function nextWednesday(from: Date): Date {
  const d = new Date(from.getFullYear(), from.getMonth(), from.getDate());
  return addDays(d, (3 - d.getDay() + 7) % 7);
}

export function isConfirmed(s: ProjectionShipment): boolean {
  return CONFIRMED_STATUSES.has(s.status);
}

/** Destination is not stored — it is read off the route, as the Excel export does. */
export function destinationOf(s: ProjectionShipment): 'FBA' | 'AWD' {
  return (s.route || '').includes('AWD') ? 'AWD' : 'FBA';
}

export function confirmedFbaInbound(shipments: ProjectionShipment[]): ProjectionShipment[] {
  return shipments.filter(s =>
    !EXCLUDED_STATUSES.has(s.status) && isConfirmed(s) && destinationOf(s) === 'FBA');
}

/** FBA units on hand at `when`, given confirmed FBA-bound arrivals. Floors at zero. */
export function projectedFbaAt(
  when: Date, fbaOnHand: number, inbound: ProjectionShipment[], curve: DemandCurve, today: Date,
): number {
  const consumed = demandOverWindow(today, when, curve);
  const arrived = inbound.reduce((sum, s) => {
    const a = new Date(s.arrival_date);
    return !isNaN(a.getTime()) && a <= when ? sum + s.qty : sum;
  }, 0);
  return Math.max(0, fbaOnHand + arrived - consumed);
}

/** First day FBA hits zero, walking day by day. Null if it never does inside `horizonDays`. */
export function fbaOosDate(
  fbaOnHand: number, inbound: ProjectionShipment[], curve: DemandCurve, today: Date, horizonDays: number,
): Date | null {
  let stock = fbaOnHand;
  for (let i = 0; i < horizonDays; i++) {
    const day = addDays(today, i);
    stock += inbound.reduce((sum, s) => {
      const a = new Date(s.arrival_date);
      return !isNaN(a.getTime()) && localDateKey(a) === localDateKey(day) ? sum + s.qty : sum;
    }, 0);
    stock -= dailyDemandOn(day, curve).units;
    if (stock <= 0) return day;
  }
  return null;
}

/**
 * Cheapest method that still lands before FBA runs out. If even the fastest
 * lands late, take the fastest and report the gap rather than hiding it.
 */
export function selectFbaMethod(
  shipDate: Date, oos: Date | null, transitDays: Record<string, number>, bufferDays: number,
): { method: FbaMethod; reason: string; lateDays: number } {
  const landed = (m: FbaMethod) => addDays(shipDate, (transitDays[m] ?? 0) + bufferDays);
  const fmt = (d: Date) => localDateKey(d);

  if (!oos) {
    return { method: 'SLOW_SEA', reason: `FBA does not run out inside the horizon — cheapest method`, lateDays: 0 };
  }
  for (const m of FBA_METHODS) {
    if (landed(m) <= oos) {
      return { method: m, reason: `${m} lands ${fmt(landed(m))}, FBA OOS ${fmt(oos)} — no further escalation needed`, lateDays: 0 };
    }
  }
  const fastest = FBA_METHODS[FBA_METHODS.length - 1];
  const lateDays = Math.ceil((landed(fastest).getTime() - oos.getTime()) / 86400000);
  return {
    method: fastest,
    reason: `${fastest} lands ${fmt(landed(fastest))}, ${lateDays}d after FBA OOS ${fmt(oos)} — unavoidable stockout`,
    lateDays,
  };
}

const floorToCartons = (units: number, pkg: number) => Math.floor(Math.max(0, units) / pkg) * pkg;

export function planSplit(input: SplitInput): SplitPlan {
  const {
    cartons, packageQuantity: pkg, fbaOnHand, awdOnHand, shipments, curve,
    transitDays, fbaInboundBufferDays: buffer, today, targetDoc, methodOverride,
  } = input;

  if (!Number.isFinite(pkg) || pkg <= 0) return fail('Invalid package quantity — cannot convert cartons to units.');
  if (!Number.isFinite(cartons) || cartons <= 0) return fail('Enter a carton count greater than zero.');
  if (Object.values(curve.productDemand).every(v => !v)) {
    return fail('No demand forecast for this product — cannot compute days of cover.');
  }

  const units = Math.round(cartons * pkg);
  const warnings: string[] = [];
  const inbound = confirmedFbaInbound(shipments);
  const shipDate = nextWednesday(today);

  // Horizon must outrun the display window: forward DOC at the last shown week
  // needs targetDoc days of demand beyond it, and transfers run past year-end.
  const horizonDays = 365 + targetDoc;
  const oos = fbaOosDate(fbaOnHand, inbound, curve, today, horizonDays);

  const selected = selectFbaMethod(shipDate, oos, transitDays, buffer);
  const method: FbaMethod = methodOverride ?? selected.method;
  const methodReason = methodOverride
    ? `${method} chosen manually (auto pick was ${selected.method})`
    : selected.reason;
  if (selected.lateDays > 0 && !methodOverride) {
    warnings.push(`FBA runs out ${selected.lateDays} day(s) before the fastest allowed method can land. Stockout is unavoidable from this batch alone.`);
  }

  const fbaTransit = transitDays[method] ?? 0;
  const fbaArrival = addDays(shipDate, fbaTransit);
  const fbaSellable = addDays(fbaArrival, buffer);

  // 100 DOC at the sellable date means holding exactly the demand of the next 100 days.
  const target = demandOverWindow(fbaSellable, addDays(fbaSellable, targetDoc), curve);
  const onHandAtSellable = projectedFbaAt(fbaSellable, fbaOnHand, inbound, curve, today);
  const fbaUnits = Math.min(floorToCartons(target - onHandAtSellable, pkg), floorToCartons(units, pkg));
  const awdUnits = units - fbaUnits;

  if (fbaUnits === 0) {
    warnings.push(`FBA is already at or above ${targetDoc} DOC on ${localDateKey(fbaSellable)} — the whole batch goes to AWD.`);
  }
  if (awdUnits === 0 && fbaUnits < target - onHandAtSellable) {
    const shortUnits = Math.round(target - onHandAtSellable - fbaUnits);
    const shortDays = Math.round(targetDoc * (shortUnits / Math.max(1, target)));
    warnings.push(`Batch is too small to reach ${targetDoc} DOC — short by ${shortUnits} units (~${shortDays} days).`);
  }

  const awdTransit = transitDays.AWD_SLOW_SEA ?? 0;
  const awdArrival = addDays(shipDate, awdTransit);

  const legs: SplitLeg[] = [];
  if (fbaUnits > 0) {
    legs.push({
      destination: 'FBA', units: fbaUnits, cartons: Math.round(fbaUnits / pkg), method,
      shipDate: localDateKey(shipDate), transitDays: fbaTransit,
      arrivalDate: localDateKey(fbaArrival), sellableDate: localDateKey(fbaSellable),
      reason: `${methodReason}. ${fbaUnits} units = demand ${localDateKey(fbaSellable)}–${localDateKey(addDays(fbaSellable, targetDoc - 1))} (${targetDoc} DOC, ${Math.round(target)} units) minus ${Math.round(onHandAtSellable)} projected on hand.`,
    });
  }
  if (awdUnits > 0) {
    legs.push({
      destination: 'AWD', units: awdUnits, cartons: Math.round(awdUnits / pkg), method: 'AWD_SLOW_SEA',
      shipDate: localDateKey(shipDate), transitDays: awdTransit,
      arrivalDate: localDateKey(awdArrival), sellableDate: localDateKey(awdArrival),
      reason: `Remainder after topping FBA to ${targetDoc} DOC. Held at AWD until transferred.`,
    });
  }

  const { transfers, leftover } = scheduleTransfers({
    curve, today, horizonDays, targetDoc, pkg,
    transferLeadDays: (transitDays.AWD_TRANSFER ?? 0) + buffer,
    fbaOnHand, inbound,
    batchArrival: fbaUnits > 0 ? { date: fbaSellable, units: fbaUnits } : null,
    pool: [
      { availableFrom: today, units: awdOnHand },
      ...(awdUnits > 0 ? [{ availableFrom: awdArrival, units: awdUnits }] : []),
    ].filter(t => t.units > 0),
  });

  if (leftover > 0) {
    warnings.push(`${leftover} units remain at AWD at the end of the horizon — not needed to hold ${targetDoc} DOC.`);
  }

  const docAtArrival = onHandAtSellable + fbaUnits > 0
    ? docFromStock(onHandAtSellable + fbaUnits, fbaSellable, curve, targetDoc * 4)
    : 0;

  return {
    ok: true, units, legs, transfers,
    fbaDocAtArrival: docAtArrival,
    fbaOosDate: oos ? localDateKey(oos) : null,
    leftoverAwdUnits: leftover,
    warnings,
  };
}

/** Days of cover from a stock level at a date, walking the daily curve. */
export function docFromStock(stock: number, from: Date, curve: DemandCurve, maxDays: number): number {
  let rem = stock;
  for (let i = 0; i < maxDays; i++) {
    rem -= dailyDemandOn(addDays(from, i), curve).units;
    if (rem <= 0) return i;
  }
  return maxDays;
}

interface PoolTranche { availableFrom: Date; units: number }

interface TransferParams {
  curve: DemandCurve;
  today: Date;
  horizonDays: number;
  targetDoc: number;
  pkg: number;
  transferLeadDays: number;
  fbaOnHand: number;
  inbound: ProjectionShipment[];
  batchArrival: { date: Date; units: number } | null;
  pool: PoolTranche[];
}

/**
 * Walk weekly. At each week, look ahead by the transfer lead time: if FBA DOC
 * would be under target by the time a transfer ordered today could land, order
 * one sized to restore the target, capped by pool available now. Transfers
 * landing within 14 days of each other merge, so the output is roughly monthly
 * rather than a weekly dribble.
 */
export function scheduleTransfers(p: TransferParams): { transfers: TransferRow[]; leftover: number } {
  const { curve, today, horizonDays, targetDoc, pkg, transferLeadDays, fbaOnHand, inbound, batchArrival, pool } = p;
  const transfers: TransferRow[] = [];
  const extra: Array<{ date: Date; units: number }> = [];
  const tranches = pool.map(t => ({ ...t }));

  const stockAt = (when: Date): number => {
    const base = projectedFbaAt(when, fbaOnHand, inbound, curve, today);
    const batch = batchArrival && batchArrival.date <= when ? batchArrival.units : 0;
    const added = extra.reduce((s, e) => (e.date <= when ? s + e.units : s), 0);
    return base + batch + added;
  };

  const availableAt = (when: Date): number =>
    tranches.reduce((s, t) => (t.availableFrom <= when ? s + t.units : s), 0);

  const drawFrom = (when: Date, qty: number): number => {
    let left = qty;
    for (const t of tranches) {
      if (left <= 0) break;
      if (t.availableFrom > when) continue;
      const take = Math.min(t.units, left);
      t.units -= take;
      left -= take;
    }
    return qty - left;
  };

  const weeks = Math.floor(horizonDays / 7);
  for (let w = 0; w < weeks; w++) {
    const orderDate = getMonday(addDays(today, w * 7));
    if (orderDate < getMonday(today)) continue;
    const arrival = addDays(orderDate, transferLeadDays);

    const docBefore = docFromStock(stockAt(arrival), arrival, curve, targetDoc * 4);
    if (docBefore >= targetDoc) continue;

    const need = demandOverWindow(arrival, addDays(arrival, targetDoc), curve) - stockAt(arrival);
    const capped = Math.min(need, availableAt(orderDate));
    const qty = Math.floor(Math.max(0, capped) / pkg) * pkg;
    if (qty <= 0) continue;

    const drawn = drawFrom(orderDate, qty);
    if (drawn <= 0) continue;

    // Merge into the previous transfer if it lands within 14 days.
    const prev = transfers[transfers.length - 1];
    const prevArrival = prev ? new Date(prev.arrivalDate) : null;
    if (prev && prevArrival && (arrival.getTime() - prevArrival.getTime()) / 86400000 <= 14) {
      const slot = extra.find(e => localDateKey(e.date) === prev.arrivalDate);
      if (slot) slot.units += drawn;
      prev.units += drawn;
      prev.cartons = Math.round(prev.units / pkg);
      prev.docAfter = docFromStock(stockAt(prevArrival), prevArrival, curve, targetDoc * 4);
      continue;
    }

    extra.push({ date: arrival, units: drawn });
    transfers.push({
      orderDate: localDateKey(orderDate),
      arrivalDate: localDateKey(arrival),
      units: drawn,
      cartons: Math.round(drawn / pkg),
      docBefore,
      docAfter: docFromStock(stockAt(arrival), arrival, curve, targetDoc * 4),
    });
  }

  return { transfers, leftover: tranches.reduce((s, t) => s + t.units, 0) };
}
```

- [ ] **Step 4: Run the test**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- fbaAwdSplit
```

Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/fbaAwdSplit.ts dashboard-react/src/fbaAwdSplit.test.ts
git commit -m "feat: FBA/AWD split engine — units, guards, Wednesday snapping"
```

- [ ] **Step 6: Add the method-selection tests**

Append to `dashboard-react/src/fbaAwdSplit.test.ts`:

```ts
import { selectFbaMethod, destinationOf, confirmedFbaInbound } from './fbaAwdSplit';

describe('selectFbaMethod', () => {
  const transit = { FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 };
  const ship = new Date(2026, 7, 12); // Wed 2026-08-12

  it('takes the cheapest method when it lands in time', () => {
    // SLOW_SEA lands 2026-08-12 + 33 + 10 = 2026-09-24
    const r = selectFbaMethod(ship, new Date(2026, 9, 30), transit, 10);
    expect(r.method).toBe('SLOW_SEA');
    expect(r.lateDays).toBe(0);
  });

  it('escalates to FAST_SEA when SLOW_SEA lands late', () => {
    // FAST_SEA lands 2026-09-18, SLOW_SEA 2026-09-24
    const r = selectFbaMethod(ship, new Date(2026, 8, 20), transit, 10);
    expect(r.method).toBe('FAST_SEA');
    expect(r.lateDays).toBe(0);
  });

  it('never selects AIR even when FAST_SEA is late', () => {
    const r = selectFbaMethod(ship, new Date(2026, 7, 20), transit, 10);
    expect(r.method).toBe('FAST_SEA');
    expect(r.lateDays).toBeGreaterThan(0);
    expect(r.reason).toMatch(/unavoidable stockout/i);
  });

  it('defaults to the cheapest when FBA never runs out', () => {
    const r = selectFbaMethod(ship, null, transit, 10);
    expect(r.method).toBe('SLOW_SEA');
  });
});

describe('shipment classification', () => {
  it('reads destination off the route', () => {
    expect(destinationOf({ qty: 1, arrival_date: '2026-09-01', status: 'transit', route: 'MFR→AWD' })).toBe('AWD');
    expect(destinationOf({ qty: 1, arrival_date: '2026-09-01', status: 'transit', route: 'PO→MFR→FBA' })).toBe('FBA');
    expect(destinationOf({ qty: 1, arrival_date: '2026-09-01', status: 'transit' })).toBe('FBA');
  });

  it('keeps only confirmed FBA-bound shipments', () => {
    const all: ProjectionShipment[] = [
      { qty: 100, arrival_date: '2026-09-01', status: 'transit', route: 'PO→MFR→FBA' },
      { qty: 200, arrival_date: '2026-09-01', status: 'suggested', route: 'PO→MFR→FBA' },
      { qty: 300, arrival_date: '2026-09-01', status: 'approved', route: 'MFR→AWD' },
      { qty: 400, arrival_date: '2026-09-01', status: 'po', route: 'MFR' },
    ];
    expect(confirmedFbaInbound(all).map(s => s.qty)).toEqual([100]);
  });
});
```

- [ ] **Step 7: Run the tests**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- fbaAwdSplit
```

Expected: 12 tests PASS.

- [ ] **Step 8: Add the sizing and edge-case tests**

Append to `dashboard-react/src/fbaAwdSplit.test.ts`:

```ts
describe('planSplit — sizing', () => {
  it('sends everything to FBA when the batch cannot reach the DOC target', () => {
    // ~10 units/day => 100 DOC needs ~1000 units. Batch is 300.
    const plan = planSplit({ ...base, cartons: 30, fbaOnHand: 0 });
    expect(plan.ok).toBe(true);
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    expect(fba.units).toBe(300);
    expect(plan.legs.find(l => l.destination === 'AWD')).toBeUndefined();
    expect(plan.warnings.join(' ')).toMatch(/too small/i);
  });

  it('sends everything to AWD when FBA is already above target', () => {
    const plan = planSplit({ ...base, cartons: 100, fbaOnHand: 50_000 });
    expect(plan.legs.find(l => l.destination === 'FBA')).toBeUndefined();
    const awd = plan.legs.find(l => l.destination === 'AWD')!;
    expect(awd.units).toBe(1000);
    expect(awd.method).toBe('AWD_SLOW_SEA');
    expect(plan.warnings.join(' ')).toMatch(/already at or above/i);
  });

  it('splits a large batch between both destinations', () => {
    const plan = planSplit({ ...base, cartons: 500, fbaOnHand: 0 });
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    const awd = plan.legs.find(l => l.destination === 'AWD')!;
    expect(fba.units + awd.units).toBe(5000);
    expect(fba.units).toBeGreaterThan(0);
    expect(awd.units).toBeGreaterThan(0);
  });

  it('rounds the FBA leg down to whole cartons', () => {
    const plan = planSplit({ ...base, cartons: 500, packageQuantity: 7 });
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    expect(fba.units % 7).toBe(0);
    expect(fba.cartons * 7).toBe(fba.units);
  });

  it('conserves units across both legs', () => {
    const plan = planSplit({ ...base, cartons: 333, packageQuantity: 12 });
    const total = plan.legs.reduce((s, l) => s + l.units, 0);
    expect(total).toBe(plan.units);
  });

  it('honours a manual method override', () => {
    const plan = planSplit({ ...base, cartons: 500, methodOverride: 'FAST_SEA' });
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    expect(fba.method).toBe('FAST_SEA');
    expect(fba.transitDays).toBe(27);
    expect(fba.reason).toMatch(/chosen manually/i);
  });

  it('reports the FBA OOS date it computed', () => {
    const plan = planSplit({ ...base, fbaOnHand: 100 });
    expect(plan.fbaOosDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});

describe('planSplit — transfers', () => {
  it('schedules AWD to FBA transfers when a pool exists', () => {
    const plan = planSplit({ ...base, cartons: 800, fbaOnHand: 0, awdOnHand: 0 });
    expect(plan.transfers.length).toBeGreaterThan(0);
    for (const t of plan.transfers) {
      expect(t.units).toBeGreaterThan(0);
      expect(t.units % base.packageQuantity).toBe(0);
      expect(new Date(t.arrivalDate).getTime()).toBeGreaterThan(new Date(t.orderDate).getTime());
    }
  });

  it('never transfers more than the pool holds', () => {
    const plan = planSplit({ ...base, cartons: 200, awdOnHand: 500 });
    const moved = plan.transfers.reduce((s, t) => s + t.units, 0);
    const awdLeg = plan.legs.find(l => l.destination === 'AWD');
    expect(moved).toBeLessThanOrEqual(500 + (awdLeg?.units ?? 0));
  });

  it('schedules nothing when there is no AWD pool at all', () => {
    const plan = planSplit({ ...base, cartons: 30, awdOnHand: 0 });
    expect(plan.transfers).toEqual([]);
  });

  it('keeps transfer arrivals at least 14 days apart after merging', () => {
    const plan = planSplit({ ...base, cartons: 2000, awdOnHand: 20_000 });
    for (let i = 1; i < plan.transfers.length; i++) {
      const gap = (new Date(plan.transfers[i].arrivalDate).getTime()
        - new Date(plan.transfers[i - 1].arrivalDate).getTime()) / 86400000;
      expect(gap).toBeGreaterThan(14);
    }
  });

  it('reports leftover pool units when the AWD stock outlasts the horizon', () => {
    const plan = planSplit({ ...base, cartons: 10, awdOnHand: 1_000_000 });
    expect(plan.leftoverAwdUnits).toBeGreaterThan(0);
    expect(plan.warnings.join(' ')).toMatch(/remain at AWD/i);
  });
});
```

- [ ] **Step 9: Run the tests and fix what fails**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- fbaAwdSplit
```

Expected: 24 tests PASS. If the merge-gap test fails, the merge comparison in `scheduleTransfers` is using the wrong anchor — it must compare against the *previous emitted transfer's* arrival, not the current week.

- [ ] **Step 10: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/fbaAwdSplit.ts dashboard-react/src/fbaAwdSplit.test.ts
git commit -m "feat: FBA/AWD sizing, method escalation and transfer schedule"
```

---

### Task 5: The simulation chart

**Files:**
- Create: `dashboard-react/src/components/SplitSimulationChart.tsx`
- Modify: `dashboard-react/src/stockProjection.ts` (add the window helper)
- Modify: `dashboard-react/src/stockProjection.test.ts`

- [ ] **Step 1: Write the failing test for the display window**

Append to `dashboard-react/src/stockProjection.test.ts`:

```ts
import { splitChartWindow } from './stockProjection';

describe('splitChartWindow', () => {
  it('starts four days before today', () => {
    const w = splitChartWindow(new Date(2026, 7, 7));
    expect(w.start).toEqual(new Date(2026, 7, 3));
  });

  it('ends at year end when that is further out than 100 days', () => {
    const w = splitChartWindow(new Date(2026, 7, 7)); // +100d = 2026-11-15
    expect(w.end).toEqual(new Date(2026, 11, 31));
  });

  it('ends at today+100 days when that runs past year end', () => {
    const w = splitChartWindow(new Date(2026, 10, 20)); // +100d = 2027-02-28
    expect(w.end).toEqual(new Date(2027, 1, 28));
  });

  it('keeps the internal horizon well past the display end', () => {
    const w = splitChartWindow(new Date(2026, 7, 7));
    expect(w.horizonEnd.getTime()).toBeGreaterThan(w.end.getTime() + 100 * 86400000);
  });
});
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- stockProjection
```

Expected: FAIL — `splitChartWindow` is not exported.

- [ ] **Step 3: Add the helper**

Append to `dashboard-react/src/stockProjection.ts`:

```ts
export interface ChartWindow {
  start: Date;       // today - 4 days
  end: Date;         // max(Dec 31 this year, today + 100 days)
  horizonEnd: Date;  // computation runs past `end` so forward DOC is not truncated
}

/**
 * Display window for the split simulation: four days of context behind, and
 * forward to whichever is later — year end or 100 days out.
 *
 * The engine computes past `end`: forward DOC at the last shown week needs a
 * further 100 days of demand, and transfers can be scheduled past year end.
 * Without the extra horizon, DOC would decay toward the right edge as an
 * artifact of running out of forecast rather than running out of stock.
 */
export function splitChartWindow(today: Date, docTarget = 100): ChartWindow {
  const start = addDays(today, -4);
  const yearEnd = new Date(today.getFullYear(), 11, 31);
  const hundred = addDays(today, docTarget);
  const end = yearEnd.getTime() >= hundred.getTime() ? yearEnd : hundred;
  return { start, end, horizonEnd: addDays(end, docTarget + 90) };
}
```

- [ ] **Step 4: Run the tests**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test -- stockProjection
```

Expected: all PASS.

- [ ] **Step 5: Write the chart component**

Create `dashboard-react/src/components/SplitSimulationChart.tsx`:

```tsx
import { useState } from 'react';
import {
  ComposedChart, Bar, Line, XAxis, YAxis, Tooltip as RTooltip,
  ResponsiveContainer, CartesianGrid, ReferenceLine,
} from 'recharts';
import { CHART_GRID, CHART_AXIS_TICK, CHART_TOOLTIP_STYLE } from '../chartTheme';
import { fmt } from '../utils';

export interface SplitChartWeek {
  weekLabel: string;
  fbaStock: number;
  awdStock: number;
  fbaDoc: number;
  demand: number;
  arrivals: number;
  arrivalNote?: string;
}

const COLORS = { fba: '#06b6d4', awd: '#67e8f9', doc: '#f59e0b', demand: '#f87171', arrival: '#22c55e' };

/** FBA sellable vs AWD reserve, with the DOC target line. Display only. */
export function SplitSimulationChart({ weeks, targetDoc, oosLabel }: {
  weeks: SplitChartWeek[];
  targetDoc: number;
  oosLabel?: string | null;
}) {
  const [showAwd, setShowAwd] = useState(true);
  const [showDoc, setShowDoc] = useState(true);
  const [showDemand, setShowDemand] = useState(false);

  if (!weeks.length) return null;

  const LegendBtn = ({ active, color, label, onClick }: { active: boolean; color: string; label: string; onClick: () => void }) => (
    <button onClick={onClick} className="inline-flex items-center gap-1 transition-opacity cursor-pointer"
      style={{ opacity: active ? 1 : 0.35 }} title={active ? `Click to hide ${label}` : `Click to show ${label}`}>
      <span className="w-2 h-2 rounded-sm" style={{ background: color }} />
      <span>{label}</span>
    </button>
  );

  const Tip = ({ active, label }: { active?: boolean; label?: string }) => {
    if (!active) return null;
    const row = weeks.find(w => w.weekLabel === label);
    if (!row) return null;
    return (
      <div className="rounded-lg p-2.5 text-[11px] space-y-1 shadow-lg" style={CHART_TOOLTIP_STYLE}>
        <div className="font-bold text-heading">{row.weekLabel}</div>
        <div style={{ color: COLORS.fba }}>FBA sellable: {fmt(row.fbaStock)} units</div>
        {showAwd && <div style={{ color: COLORS.awd }}>AWD reserve: {fmt(row.awdStock)} units</div>}
        {showDoc && <div style={{ color: COLORS.doc }}>FBA DOC: {row.fbaDoc}d</div>}
        <div style={{ color: COLORS.demand }}>Demand: −{fmt(row.demand)}/wk</div>
        {row.arrivals > 0 && <div style={{ color: COLORS.arrival }}>📦 Arrivals: +{fmt(row.arrivals)}{row.arrivalNote ? ` (${row.arrivalNote})` : ''}</div>}
      </div>
    );
  };

  return (
    <div className="mt-3">
      <div className="flex items-center justify-between mb-2">
        <h4 className="text-[11px] font-bold text-heading/80">Simulated Stock — FBA vs AWD</h4>
        <div className="flex items-center gap-3 text-[9px] text-muted">
          <span className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-sm" style={{ background: COLORS.fba }} />FBA</span>
          <LegendBtn active={showAwd} color={COLORS.awd} label="AWD" onClick={() => setShowAwd(v => !v)} />
          <LegendBtn active={showDoc} color={COLORS.doc} label="FBA DOC" onClick={() => setShowDoc(v => !v)} />
          <LegendBtn active={showDemand} color={COLORS.demand} label="Demand" onClick={() => setShowDemand(v => !v)} />
          {oosLabel && <span className="text-red-400 font-bold">⚠ OOS: {oosLabel}</span>}
        </div>
      </div>
      <ResponsiveContainer width="100%" height={200}>
        <ComposedChart data={weeks} margin={{ top: 5, right: 5, left: 5, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" {...CHART_GRID} />
          <XAxis dataKey="weekLabel" tick={CHART_AXIS_TICK} tickLine={false} interval="preserveStartEnd" />
          <YAxis yAxisId="left" hide domain={[0, 'auto']} />
          <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 9, fill: COLORS.doc }}
            tickLine={false} axisLine={false} domain={[0, 'auto']} tickFormatter={(v) => `${v}d`} width={30} />
          <RTooltip content={<Tip />} cursor={{ fill: 'rgba(255,255,255,0.03)' }} />
          <ReferenceLine yAxisId="left" y={0} stroke="#ef4444" strokeWidth={1.5} strokeDasharray="4 4"
            label={{ value: 'OOS', position: 'right', fill: '#ef4444', fontSize: 9 }} />
          <ReferenceLine yAxisId="right" y={targetDoc} ifOverflow="extendDomain" stroke="#ef4444" strokeWidth={1.5} strokeDasharray="4 4"
            label={{ value: `${targetDoc}d DOC`, position: 'insideTopLeft', fill: '#ef4444', fontSize: 9, offset: 5 }} />

          {showAwd && <Bar yAxisId="left" dataKey="awdStock" name="AWD reserve" barSize={8} radius={[2, 2, 0, 0]} fill={COLORS.awd} opacity={0.3} />}
          <Line yAxisId="left" dataKey="fbaStock" name="FBA sellable" type="stepAfter" stroke={COLORS.fba} strokeWidth={2} dot={false} activeDot={{ r: 3, fill: COLORS.fba }} />
          {showDoc && <Line yAxisId="right" dataKey="fbaDoc" name="FBA DOC" type="stepAfter" stroke={COLORS.doc} strokeWidth={1.5} strokeDasharray="4 2" dot={false} />}
          {showDemand && <Line yAxisId="left" dataKey="demand" name="Demand" type="stepAfter" stroke={COLORS.demand} strokeWidth={1.5} strokeDasharray="4 3" dot={false} />}
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}
```

- [ ] **Step 6: Verify the chart theme exports exist**

```bash
cd /Users/ori/Develop/OI/dashboard-react && grep -n "CHART_GRID\|CHART_AXIS_TICK\|CHART_TOOLTIP_STYLE" src/chartTheme.ts
```

Expected: all three are exported. If `CHART_GRID` is not a spreadable prop object, replace `{...CHART_GRID}` with `stroke="var(--color-border)" strokeOpacity={0.3}`.

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/components/SplitSimulationChart.tsx dashboard-react/src/stockProjection.ts dashboard-react/src/stockProjection.test.ts
git commit -m "feat: split simulation chart with FBA/AWD pools and display window"
```

---

### Task 6: The panel

**Files:**
- Create: `dashboard-react/src/components/FbaAwdSplitPanel.tsx`

- [ ] **Step 1: Write the panel**

Create `dashboard-react/src/components/FbaAwdSplitPanel.tsx`:

```tsx
import { useState, useMemo } from 'react';
import { Split, ChevronDown, ChevronRight } from 'lucide-react';
import { planSplit, destinationOf, type FbaMethod, type SplitInput } from '../fbaAwdSplit';
import {
  splitChartWindow, demandOverWindow, dailyDemandOn, addDays, localDateKey, fmtWeekLabel, getMonday,
  CONFIRMED_STATUSES, EXCLUDED_STATUSES,
  type DemandCurve, type ProjectionShipment,
} from '../stockProjection';
import { SplitSimulationChart, type SplitChartWeek } from './SplitSimulationChart';
import { fmt } from '../utils';
import type { ForecastDemandMap, ForecastMetaMap, MonthSeasonMap } from '../planTypes';

const TARGET_DOC = 100;

export interface SplitPanelProduct {
  product: string;
  packageQuantity: number;
}

export function FbaAwdSplitPanel({
  products, fbaMap, awdMap, mfrReadyMap, shipmentsByProduct,
  demandMap, seasonMap, metaMap, growthOverrides,
  transitDays, fbaInboundBufferDays, constantsLoaded, snapshotDate,
}: {
  products: SplitPanelProduct[];
  fbaMap: Record<string, number>;
  awdMap: Record<string, number>;
  mfrReadyMap: Record<string, number>;
  shipmentsByProduct: Record<string, ProjectionShipment[]>;
  demandMap: ForecastDemandMap;
  seasonMap: MonthSeasonMap;
  metaMap: ForecastMetaMap;
  growthOverrides?: Record<string, number>;
  transitDays: Record<string, number>;
  fbaInboundBufferDays: number;
  constantsLoaded: boolean;
  snapshotDate: string | null;
}) {
  const [product, setProduct] = useState<string>(products[0]?.product ?? '');
  const [cartonsInput, setCartonsInput] = useState<string>('');
  const [override, setOverride] = useState<FbaMethod | ''>('');
  const [showLedger, setShowLedger] = useState(false);

  const meta = products.find(p => p.product === product);
  const pkg = meta?.packageQuantity ?? 1;
  const defaultCartons = Math.floor((mfrReadyMap[product] ?? 0) / Math.max(1, pkg));
  const cartons = cartonsInput === '' ? defaultCartons : Number(cartonsInput);

  const today = useMemo(() => new Date(), []);
  const shipments = shipmentsByProduct[product] ?? [];

  const curve: DemandCurve = useMemo(() => ({
    productDemand: demandMap[product] || {},
    familySeason: metaMap[product]?.family ? (seasonMap[metaMap[product].family] || {}) : {},
    growth: growthOverrides?.[product] ?? 1.0,
  }), [product, demandMap, seasonMap, metaMap, growthOverrides]);

  const plan = useMemo(() => {
    const input: SplitInput = {
      product, cartons, packageQuantity: pkg,
      fbaOnHand: fbaMap[product] ?? 0,
      awdOnHand: awdMap[product] ?? 0,
      shipments, curve, transitDays, fbaInboundBufferDays,
      today, targetDoc: TARGET_DOC,
      methodOverride: override || undefined,
    };
    return planSplit(input);
  }, [product, cartons, pkg, fbaMap, awdMap, shipments, curve, transitDays, fbaInboundBufferDays, today, override]);

  const chartWeeks: SplitChartWeek[] = useMemo(() => {
    if (!plan.ok) return [];
    const win = splitChartWindow(today, TARGET_DOC);
    const arrivals = new Map<string, { units: number; notes: string[] }>();
    const push = (d: string, units: number, note: string) => {
      const key = localDateKey(getMonday(new Date(d)));
      const e = arrivals.get(key) || { units: 0, notes: [] };
      e.units += units; e.notes.push(note);
      arrivals.set(key, e);
    };
    for (const leg of plan.legs) push(leg.sellableDate, leg.units, `${leg.destination} batch`);
    for (const t of plan.transfers) push(t.arrivalDate, t.units, 'AWD→FBA');
    for (const s of shipments) {
      if (EXCLUDED_STATUSES.has(s.status) || !CONFIRMED_STATUSES.has(s.status)) continue;
      push(s.arrival_date, s.qty, `confirmed ${destinationOf(s)}`);
    }

    const fbaLeg = plan.legs.find(l => l.destination === 'FBA');
    const awdLeg = plan.legs.find(l => l.destination === 'AWD');

    const rows: SplitChartWeek[] = [];
    let fba = fbaMap[product] ?? 0;
    let awd = awdMap[product] ?? 0;

    for (let w = getMonday(win.start); w <= win.end; w = addDays(w, 7)) {
      const key = localDateKey(w);
      let demand = 0;
      for (let d = 0; d < 7; d++) demand += dailyDemandOn(addDays(w, d), curve).units;
      const isPast = w < getMonday(today);

      const inbound = arrivals.get(key);
      if (!isPast) {
        if (fbaLeg && localDateKey(getMonday(new Date(fbaLeg.sellableDate))) === key) fba += fbaLeg.units;
        if (awdLeg && localDateKey(getMonday(new Date(awdLeg.arrivalDate))) === key) awd += awdLeg.units;
        for (const t of plan.transfers) {
          if (localDateKey(getMonday(new Date(t.arrivalDate))) === key) { awd -= t.units; fba += t.units; }
        }
        fba = Math.max(0, fba - demand);
      }

      const docWindow = demandOverWindow(w, addDays(w, TARGET_DOC), curve);
      rows.push({
        weekLabel: fmtWeekLabel(w),
        fbaStock: Math.round(fba),
        awdStock: Math.max(0, Math.round(awd)),
        fbaDoc: docWindow > 0 ? Math.min(TARGET_DOC * 4, Math.round((fba / docWindow) * TARGET_DOC)) : 0,
        demand: Math.round(isPast ? 0 : demand),
        arrivals: isPast ? 0 : (inbound?.units ?? 0),
        arrivalNote: inbound?.notes.join(', '),
      });
    }
    return rows;
  }, [plan, curve, today, fbaMap, awdMap, product, shipments]);

  const Row = ({ label, value }: { label: string; value: string }) => (
    <div className="flex justify-between gap-4 text-[10px] py-0.5">
      <span className="text-muted">{label}</span>
      <span className="text-heading font-mono">{value}</span>
    </div>
  );

  return (
    <div className="rounded-lg border border-border/20 bg-surface/30 overflow-hidden px-4 py-3">
      <div className="flex items-center gap-2 mb-3">
        <Split className="text-cyan-400" size={16} />
        <h3 className="text-sm font-bold text-heading">FBA / AWD Split Calculator</h3>
        <span className="text-[9px] text-muted">Advisory — writes nothing</span>
      </div>

      {/* Inputs */}
      <div className="flex flex-wrap items-end gap-3 mb-3">
        <label className="text-[10px] text-muted">
          <div className="mb-1">Product</div>
          <select value={product} onChange={e => { setProduct(e.target.value); setCartonsInput(''); }}
            className="bg-surface border border-border rounded px-2 py-1 text-[11px] text-heading min-w-[180px]">
            {products.map(p => <option key={p.product} value={p.product}>{p.product}</option>)}
          </select>
        </label>
        <label className="text-[10px] text-muted">
          <div className="mb-1">Cartons ready</div>
          <input type="number" min={0} value={cartonsInput} placeholder={String(defaultCartons)}
            onChange={e => setCartonsInput(e.target.value)}
            className="bg-surface border border-border rounded px-2 py-1 text-[11px] text-heading font-mono w-28" />
        </label>
        <label className="text-[10px] text-muted">
          <div className="mb-1">FBA method</div>
          <select value={override} onChange={e => setOverride(e.target.value as FbaMethod | '')}
            className="bg-surface border border-border rounded px-2 py-1 text-[11px] text-heading">
            <option value="">Auto</option>
            <option value="SLOW_SEA">Slow Sea</option>
            <option value="FAST_SEA">Fast Sea</option>
          </select>
        </label>
        <div className="text-[10px] text-muted">
          = <span className="font-mono text-heading">{fmt(cartons * pkg)}</span> units ({pkg}/carton)
        </div>
      </div>

      {!constantsLoaded && (
        <div className="text-[10px] text-amber-400 mb-2">
          Transit days could not be read from DE_LIST_OF_VALUES — using built-in defaults. Start Flask to use live values.
        </div>
      )}

      {!plan.ok ? (
        <div className="text-[11px] text-red-400 py-3">{plan.error}</div>
      ) : (
        <>
          {/* Decision rows */}
          <div className="space-y-1.5 mb-3">
            {plan.legs.map(leg => (
              <div key={leg.destination} className="rounded border border-border/30 px-3 py-2">
                <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1 text-[11px]">
                  <span className={`font-bold ${leg.destination === 'FBA' ? 'text-cyan-300' : 'text-cyan-100'}`}>{leg.destination}</span>
                  <span className="font-mono text-heading">{fmt(leg.units)} units</span>
                  <span className="font-mono text-muted">{fmt(leg.cartons)} cartons</span>
                  <span className="text-heading">{leg.method.replace(/_/g, ' ')}</span>
                  <span className="text-muted">{leg.transitDays}d transit</span>
                  <span className="text-muted">ship {leg.shipDate}</span>
                  <span className="text-muted">arrive {leg.arrivalDate}</span>
                  <span className="text-emerald-300">sellable {leg.sellableDate}</span>
                </div>
                <div className="text-[9px] text-muted mt-1">{leg.reason}</div>
              </div>
            ))}
          </div>

          {plan.transfers.length > 0 && (
            <div className="mb-3">
              <div className="text-[9px] font-bold text-muted/60 uppercase tracking-wider mb-1">AWD → FBA transfers</div>
              <table className="w-full text-[10px]">
                <thead><tr className="text-muted text-left">
                  <th className="font-normal py-0.5">Order</th><th className="font-normal">Arrive</th>
                  <th className="font-normal text-right">Units</th><th className="font-normal text-right">Cartons</th>
                  <th className="font-normal text-right">DOC before</th><th className="font-normal text-right">DOC after</th>
                </tr></thead>
                <tbody>
                  {plan.transfers.map(t => (
                    <tr key={t.orderDate} className="border-t border-border/20">
                      <td className="py-0.5 font-mono">{t.orderDate}</td>
                      <td className="font-mono">{t.arrivalDate}</td>
                      <td className="text-right font-mono">{fmt(t.units)}</td>
                      <td className="text-right font-mono">{fmt(t.cartons)}</td>
                      <td className="text-right font-mono text-amber-300">{t.docBefore}d</td>
                      <td className="text-right font-mono text-emerald-300">{t.docAfter}d</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {plan.warnings.map((w, i) => (
            <div key={i} className="text-[10px] text-amber-400 mb-1">⚠ {w}</div>
          ))}

          <SplitSimulationChart weeks={chartWeeks} targetDoc={TARGET_DOC} oosLabel={plan.fbaOosDate} />

          {/* Calculation ledger */}
          <button onClick={() => setShowLedger(v => !v)}
            className="mt-3 flex items-center gap-1 text-[10px] text-muted hover:text-heading">
            {showLedger ? <ChevronDown size={11} /> : <ChevronRight size={11} />}
            Calculation inputs
          </button>
          {showLedger && (
            <div className="mt-2 grid grid-cols-1 md:grid-cols-2 gap-x-6 border-t border-border/20 pt-2">
              <div>
                <div className="text-[9px] font-bold text-muted/60 uppercase tracking-wider mb-1">On hand & conversion</div>
                <Row label="Snapshot date" value={snapshotDate ?? '—'} />
                <Row label="FBA on hand" value={`${fmt(fbaMap[product] ?? 0)} units`} />
                <Row label="AWD on hand" value={`${fmt(awdMap[product] ?? 0)} units`} />
                <Row label="Units per carton (DIM_PRODUCT)" value={String(pkg)} />
                <Row label="Cartons entered" value={String(cartons)} />
                <Row label="Batch units" value={fmt(plan.units)} />
                <Row label="Growth override" value={`×${(growthOverrides?.[product] ?? 1).toFixed(2)}`} />

                <div className="text-[9px] font-bold text-muted/60 uppercase tracking-wider mt-3 mb-1">Constants (DE_LIST_OF_VALUES)</div>
                {['SLOW_SEA', 'FAST_SEA', 'AWD_SLOW_SEA', 'AWD_TRANSFER'].map(k => (
                  <Row key={k} label={`${k.replace(/_/g, ' ')} (SHIPMENT_TYPE)`} value={`${transitDays[k] ?? '—'}d`} />
                ))}
                <Row label="FBA inbound buffer (Q4_PEAK)" value={`${fbaInboundBufferDays}d`} />
                <Row label="DOC target" value={`${TARGET_DOC}d`} />
              </div>

              <div>
                <div className="text-[9px] font-bold text-muted/60 uppercase tracking-wider mb-1">Inbound shipments counted</div>
                {shipments.filter(s => !EXCLUDED_STATUSES.has(s.status) && CONFIRMED_STATUSES.has(s.status)).map((s, i) => (
                  <Row key={`in-${i}`} label={`${s.arrival_date} · ${destinationOf(s)} · ${s.status}`} value={`${fmt(s.qty)} units`} />
                ))}
                {shipments.filter(s => !EXCLUDED_STATUSES.has(s.status) && CONFIRMED_STATUSES.has(s.status)).length === 0 && (
                  <div className="text-[10px] text-muted py-0.5">None</div>
                )}

                <div className="text-[9px] font-bold text-muted/60 uppercase tracking-wider mt-3 mb-1">Excluded</div>
                {shipments.filter(s => EXCLUDED_STATUSES.has(s.status) || !CONFIRMED_STATUSES.has(s.status)).map((s, i) => (
                  <div key={`ex-${i}`} className="flex justify-between gap-4 text-[10px] py-0.5 opacity-50">
                    <span className="text-muted">{s.arrival_date} · {fmt(s.qty)} units</span>
                    <span className="text-muted italic">
                      {EXCLUDED_STATUSES.has(s.status) ? 'PO — still at manufacturer' : 'suggested — not approved'}
                    </span>
                  </div>
                ))}

                <div className="text-[9px] font-bold text-muted/60 uppercase tracking-wider mt-3 mb-1">Demand forecast (V_FORECAST_DEMAND)</div>
                {Object.entries(curve.productDemand).sort(([a], [b]) => a.localeCompare(b)).slice(0, 14).map(([ym, units]) => {
                  const season = curve.familySeason[Number(ym)];
                  return (
                    <Row key={ym}
                      label={`${ym}${season?.peakDays ? ` · ${season.peakDays} peak days` : ''}`}
                      value={`${fmt(Math.round(units * curve.growth))} units`} />
                  );
                })}
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Type-check the panel**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npx tsc --noEmit 2>&1 | grep -E "FbaAwdSplitPanel|SplitSimulationChart" || echo "clean"
```

Expected: `clean`. Fix any error naming those two files.

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/components/FbaAwdSplitPanel.tsx
git commit -m "feat: FBA/AWD split panel with calculation ledger"
```

---

### Task 7: Mount the panel on the Plan page

The panel needs the same inventory and shipment data `ReplenishmentFlowWrapper` builds. Mount it inside that wrapper, which already holds all of it, and render the wrapper's output above the simulator header.

**Files:**
- Modify: `dashboard-react/src/pages/PlanPage.tsx`

- [ ] **Step 1: Build the shipment map inside the wrapper**

In `ReplenishmentFlowWrapper` in `dashboard-react/src/pages/PlanPage.tsx`, after the existing hooks, add:

```ts
  const shipmentsByProduct = useMemo(() => {
    const map: Record<string, ProjectionShipment[]> = {};
    const add = (product: string, s: ProjectionShipment) => {
      (map[product] ||= []).push(s);
    };
    for (const s of inTransit) add(s.product, { qty: s.qty, arrival_date: s.arrival_date, status: 'transit', route: s.route });
    for (const s of scheduled) add(s.product, { qty: s.ship_qty ?? s.qty, arrival_date: s.arrival_date, status: 'scheduled', route: s.route });
    for (const s of suggestions) add(s.product, { qty: s.ship_qty ?? s.qty, arrival_date: s.arrival_date, status: 'suggested', route: s.route });
    return map;
  }, [inTransit, scheduled, suggestions]);

  const splitProducts = useMemo(
    () => products
      .map(p => ({ product: p.product_short_name || p.product, packageQuantity: p.package_quantity ?? 1 }))
      .filter(p => p.product)
      .sort((a, b) => a.product.localeCompare(b.product)),
    [products],
  );
```

Add the imports at the top of `PlanPage.tsx`:

```ts
import { FbaAwdSplitPanel } from '../components/FbaAwdSplitPanel';
import { useShipmentConstants } from '../hooks/useShipmentConstants';
import type { ProjectionShipment } from '../stockProjection';
```

and inside the wrapper body:

```ts
  const { transitDays, fbaInboundBufferDays, loaded: constantsLoaded } = useShipmentConstants();
```

If the field names on `inTransit` / `scheduled` / `suggestions` rows differ from `qty` / `ship_qty` / `arrival_date` / `route`, check the shapes with:

```bash
cd /Users/ori/Develop/OI/dashboard-react && grep -n "useShipmentHistory\|useScheduledShipments\|useShipmentPlan" -A 25 src/components/ShipmentEngine.tsx | grep -E "qty|arrival|route" | head -20
```

and adjust the mapping to match. Do not guess field names.

- [ ] **Step 2: Render the panel**

In the JSX returned by `ReplenishmentFlowWrapper`, immediately before the existing `<ReplenishmentFlowSection ... />`, add:

```tsx
      <div className="mb-6">
        <FbaAwdSplitPanel
          products={splitProducts}
          fbaMap={fbaMap}
          awdMap={awdMap}
          mfrReadyMap={mfrReadyMap}
          shipmentsByProduct={shipmentsByProduct}
          demandMap={demandMap}
          seasonMap={seasonMap}
          metaMap={metaMap}
          growthOverrides={growthOverrides}
          transitDays={transitDays}
          fbaInboundBufferDays={fbaInboundBufferDays}
          constantsLoaded={constantsLoaded}
          snapshotDate={snapshotDate}
        />
      </div>
```

Re-add `snapshotDate` to the `useInventorySnapshot()` destructure from Task 2 Step 5 if it was dropped.

- [ ] **Step 3: Move the wrapper above the simulator header**

`ReplenishmentFlowWrapper` currently renders at `PlanPage.tsx:2414`, below the simulator. The panel must sit *above* the `Plan — Ads & Inventory Simulator` header (`PlanPage.tsx:1804`) while the replenishment flow stays where it is.

Split them: give `ReplenishmentFlowWrapper` a `slot` prop of `'split'` or `'flow'`, returning only the split panel for `'split'` and only `<ReplenishmentFlowSection />` for `'flow'`. Render `<ReplenishmentFlowWrapper slot="split" ... />` immediately before the `<div className="flex items-center justify-between">` that opens the simulator header, and leave the existing call at line 2414 as `slot="flow"`.

Because the wrapper would then mount twice, hoist its hooks into a shared parent or accept the duplicate mount — `useInventorySnapshot` and `useShipmentConstants` both fetch once per mount, so prefer hoisting. The simplest hoist: move the two `useX()` calls and the derived memos into `PlanPage` itself and pass them down as props to both slots.

- [ ] **Step 4: Verify types and tests**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test && npx tsc --noEmit 2>&1 | grep -E "PlanPage|FbaAwdSplit" || echo "clean"
```

Expected: all tests PASS, `clean`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/pages/PlanPage.tsx
git commit -m "feat: mount the FBA/AWD split panel above the Plan simulator"
```

---

### Task 8: Verify in the browser

**Files:** none — verification only.

- [ ] **Step 1: Start Cube and Flask**

```bash
cd /Users/ori/Develop/OI/cube && npm run dev
```

```bash
cd /Users/ori/Develop/OI/data-entry-app && env -u CUBEJS_API_SECRET PORT=5050 python3 app.py
```

Flask on :5050 is required — without it the LOV fetch falls back to defaults and the panel shows the amber warning.

- [ ] **Step 2: Start the dashboard preview**

Use `preview_start` with the dev-server config for the dashboard (Vite on :5173), not a Bash command.

- [ ] **Step 3: Check the panel renders**

Navigate to the Plan page, switch to admin view mode, and confirm:
- The panel sits above `Plan — Ads & Inventory Simulator`.
- Selecting a product prefills cartons from manufacturer-ready stock.
- The FBA and AWD rows show units, cartons, method, dates.
- The chart starts 4 days before today and ends at year end.
- `Calculation inputs` expands and lists the shipments counted and excluded.

- [ ] **Step 4: Check for runtime errors**

Use `read_console_messages` with `onlyErrors: true`. Expected: no errors from `FbaAwdSplitPanel`, `SplitSimulationChart`, or `fbaAwdSplit`.

- [ ] **Step 5: Screenshot the result**

Use `computer` with `action: "screenshot"` and share it.

- [ ] **Step 6: Final full-suite run**

```bash
cd /Users/ori/Develop/OI/dashboard-react && npm test
```

Expected: all tests PASS, including the pre-existing suites.

---

## Self-Review Notes

**Spec coverage:** input prefill (T6), units conversion (T4), method escalation without AIR (T4 S6), 100-DOC sizing (T4 S8), AWD remainder (T4 S8), transfer schedule with merge (T4 S8), ledger with counted *and* excluded shipments (T6), decision-row reasons (T4/T6), two-pool chart (T5), display window and longer internal horizon (T5 S3), all five edge cases (T4 S1/S8), characterization test for the extraction (T1 S2), backend-sourced constants (T3).

**Deferred by spec:** shipment-row writes, Excel export, multi-product batches.

**Riskiest step:** Task 7 Step 3 — moving the wrapper requires hoisting hooks so they do not fire twice. If the hoist proves messy, mounting the panel inside the existing wrapper and moving the whole wrapper above the header is an acceptable fallback, provided the replenishment flow's position is checked with the user first.
