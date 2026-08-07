import { describe, it, expect } from 'vitest';
import type { MonthSeasonInfo, ForecastDemandMap, ForecastMetaMap, MonthSeasonMap } from './planTypes';
import type { DemandCurve, ProjectionShipment } from './stockProjection';
import { confirmedFbaInbound, planSplit, plannedWalkWindow, type SplitInput } from './fbaAwdSplit';
import {
  FBA_TARGET_DOC, FBA_REORDER_DOC, FBA_BATCH_DOC, TOTAL_TARGET_DOC, AWD_RESERVE_DOC,
  REQUIRED_TRANSIT_KEYS, EXCLUSION_REASONS,
  cartonPrefill, unitsFromCartons, docLabel, narrowTransitDays, resolveBatchInput,
  partitionShipmentsForLedger, buildDemandCurve, buildDemandLedger, transitLedgerEntries,
  groupProductsByFamily, resolveFamilySelection,
  reconcileInboundWithSnapshot, dispositionNote, awdInboundFromSnapshot,
} from './splitPanelData';

describe('the four cover levels', () => {
  // The AWD → FBA lead as DE_LIST_OF_VALUES supplies it: door to SELLABLE, so
  // no FBA inbound buffer on top, and — now that transfers are evaluated daily
  // rather than on Mondays — no ordering cadence on top either. It is the whole
  // physical floor. Named once, and only ever compared with `>`, so the LOV can
  // move without this file needing to.
  const AWD_TRANSFER_LEAD = 14;

  it('holds 100 days across FBA and AWD, of which a delivery puts 60 at FBA', () => {
    expect(FBA_REORDER_DOC).toBe(30);
    expect(FBA_TARGET_DOC).toBe(45);
    expect(FBA_BATCH_DOC).toBe(60);
    expect(TOTAL_TARGET_DOC).toBe(100);
  });

  it('stacks the four levels in the only order that can work', () => {
    // Not a magic sum — a chain of relationships, each of which has to hold.
    //
    // A transfer is ordered the day cover reaches the reorder point and lands
    // AWD_TRANSFER days later, so the reorder point must be above that lead or
    // the move arrives after the shelf is already empty. The transfer target
    // must be above the reorder point, because that difference is what a move
    // buys back — equal levels would trigger every single day. The delivery
    // fill must be at or above the transfer target, because the direct leg pays
    // no transfer handling and can never be the shallower of the two routes.
    // And the combined target caps the lot: every day of delivery fill is a day
    // off the reserve's share.
    expect(FBA_REORDER_DOC).toBeGreaterThan(AWD_TRANSFER_LEAD);
    expect(FBA_TARGET_DOC).toBeGreaterThan(FBA_REORDER_DOC);
    expect(FBA_BATCH_DOC).toBeGreaterThanOrEqual(FBA_TARGET_DOC);
    expect(TOTAL_TARGET_DOC).toBeGreaterThanOrEqual(FBA_BATCH_DOC);
  });

  it('buys transfer-free days with the gap between the delivery fill and the transfer target', () => {
    // The whole reason the fourth level exists. Landing at the transfer target
    // would reach the reorder point in FBA_TARGET_DOC − FBA_REORDER_DOC days;
    // landing at the delivery fill doubles that, at storage cost only.
    expect(FBA_TARGET_DOC - FBA_REORDER_DOC).toBe(15);
    expect(FBA_BATCH_DOC - FBA_REORDER_DOC).toBe(30);
  });

  it('leaves the balance to AWD rather than double-counting it', () => {
    // The reserve's share is measured against the DELIVERY fill, because that
    // is where a landed batch actually leaves FBA. Deriving it keeps the ledger
    // from ever printing a share the split does not produce.
    expect(AWD_RESERVE_DOC).toBe(40);
    expect(FBA_BATCH_DOC + AWD_RESERVE_DOC).toBe(TOTAL_TARGET_DOC);
    expect(FBA_BATCH_DOC).toBeLessThan(TOTAL_TARGET_DOC);
  });
});

describe('cartonPrefill', () => {
  it('floors ready units to whole cartons', () => {
    expect(cartonPrefill(1000, 10)).toBe(100);
    expect(cartonPrefill(1005, 10)).toBe(100); // 100.5 cartons -> 100
    expect(cartonPrefill(288, 24)).toBe(12);
  });

  it('returns 0 when there is less than one full carton', () => {
    expect(cartonPrefill(9, 10)).toBe(0);
  });

  it('returns 0 rather than Infinity when package quantity is zero or missing', () => {
    expect(cartonPrefill(1000, 0)).toBe(0);
    expect(cartonPrefill(1000, undefined)).toBe(0);
    expect(cartonPrefill(1000, NaN)).toBe(0);
    expect(cartonPrefill(1000, -10)).toBe(0);
  });

  it('returns 0 for missing or negative ready units', () => {
    expect(cartonPrefill(undefined, 10)).toBe(0);
    expect(cartonPrefill(-50, 10)).toBe(0);
  });
});

describe('unitsFromCartons', () => {
  it('multiplies cartons by package quantity', () => {
    expect(unitsFromCartons(100, 10)).toBe(1000);
    expect(unitsFromCartons(12, 24)).toBe(288);
  });

  it('returns 0 for a zero or unusable package quantity', () => {
    expect(unitsFromCartons(0, 10)).toBe(0);
    expect(unitsFromCartons(5, 0)).toBe(0);
    expect(unitsFromCartons(5, NaN)).toBe(0);
    expect(unitsFromCartons(NaN, 10)).toBe(0);
  });
});

describe('resolveBatchInput', () => {
  const products = [{ product: 'Pink Lollibox', packageQuantity: 24 }, { product: 'Mint LolliME', packageQuantity: 0 }];
  const mfrReadyMap = { 'Pink Lollibox': 1000, 'Mint LolliME': 500 };
  const forPink = (typed: string) => resolveBatchInput({ product: 'Pink Lollibox', products, mfrReadyMap, typed });

  it('defaults to whole cartons of what is ready at the manufacturer', () => {
    // 1000 ready / 24 per carton = 41.6 -> 41 cartons -> 41 x 24 = 984 units.
    expect(forPink('')).toEqual({
      packageQuantity: 24, readyUnits: 1000, prefillCartons: 41,
      cartons: 41, batchUnits: 984, isDefaulted: true,
    });
  });

  it('treats a whitespace-only field as still defaulted', () => {
    expect(forPink('   ').isDefaulted).toBe(true);
    expect(forPink('   ').cartons).toBe(41);
  });

  it('uses the entered value once the operator types one', () => {
    expect(forPink('60')).toMatchObject({ cartons: 60, batchUnits: 1440, isDefaulted: false, prefillCartons: 41 });
  });

  it('passes an entered zero straight through instead of falling back to the default', () => {
    expect(forPink('0')).toMatchObject({ cartons: 0, batchUnits: 0, isDefaulted: false });
  });

  it('passes an unreadable entry through as NaN so the engine reports it', () => {
    expect(forPink('abc').cartons).toBeNaN();
    expect(forPink('abc').batchUnits).toBe(0);
  });

  it('yields zeroes for a product with no package quantity, never Infinity', () => {
    expect(resolveBatchInput({ product: 'Mint LolliME', products, mfrReadyMap, typed: '' })).toEqual({
      packageQuantity: 0, readyUnits: 500, prefillCartons: 0,
      cartons: 0, batchUnits: 0, isDefaulted: true,
    });
  });

  it('yields zeroes for a product absent from the lists', () => {
    expect(resolveBatchInput({ product: 'Nope', products, mfrReadyMap, typed: '' })).toMatchObject({
      packageQuantity: 0, readyUnits: 0, prefillCartons: 0, batchUnits: 0,
    });
  });
});

describe('docLabel', () => {
  it('renders a capped reading as "400+", never as a flat 400', () => {
    expect(docLabel({ days: 400, capped: true })).toBe('400+');
  });

  it('renders an uncapped reading with a day suffix', () => {
    expect(docLabel({ days: 97, capped: false })).toBe('97d');
    expect(docLabel({ days: 0, capped: false })).toBe('0d');
  });

  it('renders a missing reading as an em dash', () => {
    expect(docLabel(null)).toBe('—');
    expect(docLabel(undefined)).toBe('—');
  });
});

describe('narrowTransitDays', () => {
  const LIVE = { AIR: 10, FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 };

  it('requires exactly the four keys the engine reads', () => {
    expect([...REQUIRED_TRANSIT_KEYS]).toEqual(['SLOW_SEA', 'FAST_SEA', 'AWD_SLOW_SEA', 'AWD_TRANSFER']);
  });

  it('accepts a complete map and passes extra keys through untouched', () => {
    const got = narrowTransitDays(LIVE);
    expect(got.ok).toBe(true);
    if (!got.ok) return;
    expect(got.transitDays.SLOW_SEA).toBe(33);
    expect(got.transitDays.FAST_SEA).toBe(27);
    expect(got.transitDays.AWD_SLOW_SEA).toBe(63);
    expect(got.transitDays.AWD_TRANSFER).toBe(14);
    expect(got.transitDays.AIR).toBe(10); // extra keys survive; AIR is just never offered
  });

  it('rejects a map missing one required key and names it', () => {
    const partial: Record<string, number> = { ...LIVE };
    delete partial.AWD_TRANSFER;
    const got = narrowTransitDays(partial);
    expect(got.ok).toBe(false);
    if (got.ok) return;
    expect(got.missing).toEqual(['AWD_TRANSFER']);
  });

  it('rejects a non-finite value rather than letting it fabricate an arrival date', () => {
    expect(narrowTransitDays({ ...LIVE, SLOW_SEA: NaN })).toEqual({ ok: false, missing: ['SLOW_SEA'] });
    expect(narrowTransitDays({ ...LIVE, FAST_SEA: Infinity })).toEqual({ ok: false, missing: ['FAST_SEA'] });
  });

  it('accepts a zero-day transit — 0 is a value, not a missing key', () => {
    const got = narrowTransitDays({ ...LIVE, AWD_TRANSFER: 0 });
    expect(got.ok).toBe(true);
    if (!got.ok) return;
    expect(got.transitDays.AWD_TRANSFER).toBe(0);
  });

  it('lists the four routes the split reads first, then anything else the LOV carries', () => {
    expect(transitLedgerEntries(LIVE)).toEqual([
      { key: 'SLOW_SEA', days: 33, used: true },
      { key: 'FAST_SEA', days: 27, used: true },
      { key: 'AWD_SLOW_SEA', days: 63, used: true },
      { key: 'AWD_TRANSFER', days: 14, used: true },
      { key: 'AIR', days: 10, used: false }, // present in the LOV, never an option here
    ]);
  });

  it('sorts the extra LOV routes so the ledger order is stable', () => {
    const entries = transitLedgerEntries({ ...LIVE, ZEBRA: 5, ALPHA: 3 });
    expect(entries.slice(4).map(e => e.key)).toEqual(['AIR', 'ALPHA', 'ZEBRA']);
  });

  it('reports every missing key for an empty or absent map', () => {
    expect(narrowTransitDays({})).toEqual({
      ok: false, missing: ['SLOW_SEA', 'FAST_SEA', 'AWD_SLOW_SEA', 'AWD_TRANSFER'],
    });
    expect(narrowTransitDays(undefined)).toEqual({
      ok: false, missing: ['SLOW_SEA', 'FAST_SEA', 'AWD_SLOW_SEA', 'AWD_TRANSFER'],
    });
  });
});

describe('partitionShipmentsForLedger', () => {
  // The engine walks 2026-08-07 .. 2027-11-15 for today = 2026-08-07 — 365 days
  // plus the 100-day combined target its horizon follows.
  const WINDOW = { from: '2026-08-07', to: '2027-11-15' };

  const inTransitFba: ProjectionShipment = { qty: 500, arrival_date: '2026-09-10', status: 'transit', route: 'FAST_SEA' };
  const approvedNoRoute: ProjectionShipment = { qty: 300, arrival_date: '2026-10-01', status: 'approved' };
  const scheduledAwd: ProjectionShipment = { qty: 200, arrival_date: '2026-09-20', status: 'scheduled', route: 'AWD_SLOW_SEA' };
  const suggested: ProjectionShipment = { qty: 400, arrival_date: '2026-11-01', status: 'suggested', route: 'SLOW_SEA' };
  const po: ProjectionShipment = { qty: 600, arrival_date: '2026-12-01', status: 'po', route: 'SLOW_SEA' };
  const poNeeded: ProjectionShipment = { qty: 100, arrival_date: '2026-12-15', status: 'po_needed' };
  const arrived: ProjectionShipment = { qty: 50, arrival_date: '2026-07-01', status: 'arrived' };
  const badDate: ProjectionShipment = { qty: 70, arrival_date: '', status: 'transit', route: 'SLOW_SEA' };

  const ALL = [inTransitFba, approvedNoRoute, scheduledAwd, suggested, po, poNeeded, arrived, badDate];
  const split = (rows: ProjectionShipment[]) => partitionShipmentsForLedger(rows, WINDOW);

  it('counts only confirmed, FBA-bound shipments landing inside the walked window', () => {
    const { counted } = split(ALL);
    expect(counted.map(r => r.shipment)).toEqual([inTransitFba, approvedNoRoute]);
    expect(counted.map(r => r.qty)).toEqual([500, 300]);
    expect(counted.every(r => r.exclusionReason === null)).toBe(true);
  });

  it('reads destination off the route, defaulting a routeless shipment to FBA', () => {
    expect(split(ALL).counted.map(r => r.destination)).toEqual(['FBA', 'FBA']);
  });

  it('excludes everything else, in input order, each with its own reason', () => {
    expect(split(ALL).excluded.map(r => [r.shipment, r.exclusionReason])).toEqual([
      [scheduledAwd, EXCLUSION_REASONS.AWD_BOUND],
      [suggested, EXCLUSION_REASONS.UNAPPROVED],
      [po, EXCLUSION_REASONS.PO],
      [poNeeded, EXCLUSION_REASONS.PO],
      [arrived, EXCLUSION_REASONS.ARRIVED_FBA],
      [badDate, EXCLUSION_REASONS.NO_ARRIVAL_DATE],
    ]);
  });

  it('says AWD, not FBA, for an arrived AWD-bound shipment', () => {
    // It is inside the AWD on-hand figure; claiming FBA would be untrue.
    const arrivedAwd: ProjectionShipment = { qty: 800, arrival_date: '2026-07-01', status: 'arrived', route: 'AWD_SLOW_SEA' };
    expect(split([arrivedAwd]).excluded[0].exclusionReason).toBe(EXCLUSION_REASONS.ARRIVED_AWD);
  });

  it('does not silently drop a confirmed shipment the engine would ignore for a bad date', () => {
    // The engine's own filter keeps `badDate` (confirmed, FBA-bound) and then drops it
    // inside the projection because the date will not parse. The ledger must SHOW that.
    expect(confirmedFbaInbound(ALL)).toEqual([inTransitFba, approvedNoRoute, badDate]);
    const { counted, excluded } = split(ALL);
    expect(counted).toHaveLength(2);
    expect(excluded.map(r => r.shipment)).toContain(badDate);
  });

  it('excludes a zero or negative quantity — arrivalsByDay skips it, so it adds nothing', () => {
    const empty: ProjectionShipment = { qty: 0, arrival_date: '2026-09-10', status: 'transit', route: 'SLOW_SEA' };
    const negative: ProjectionShipment = { qty: -40, arrival_date: '2026-09-10', status: 'transit', route: 'SLOW_SEA' };
    expect(split([empty, negative]).counted).toEqual([]);
    expect(split([empty, negative]).excluded.map(r => r.exclusionReason))
      .toEqual([EXCLUSION_REASONS.NO_UNITS, EXCLUSION_REASONS.NO_UNITS]);
  });

  it('accounts for every shipment exactly once — nothing is dropped without a reason', () => {
    const { counted, excluded } = split(ALL);
    const seen = [...counted, ...excluded].map(r => r.shipment);
    expect(seen).toHaveLength(ALL.length);
    for (const s of ALL) expect(seen.filter(x => x === s)).toHaveLength(1);
  });

  it('reports a PO reason ahead of anything else, since a PO is not shipped at all', () => {
    // po_needed + AWD route: still "at the manufacturer" is the honest headline.
    const awdPo: ProjectionShipment = { qty: 10, arrival_date: '2026-12-01', status: 'po_needed', route: 'AWD_SLOW_SEA' };
    expect(split([awdPo]).excluded[0].exclusionReason).toBe(EXCLUSION_REASONS.PO);
  });

  it('carries status and the arrival day the engine will use, for display', () => {
    expect(split([inTransitFba]).counted[0])
      .toMatchObject({ status: 'transit', arrivalDate: '2026-09-10', qty: 500, destination: 'FBA' });
  });

  it('returns two empty lists for no shipments', () => {
    expect(split([])).toEqual({ counted: [], excluded: [] });
  });

  it('makes no window judgement when there is no plan, so nothing is mislabelled', () => {
    const stale: ProjectionShipment = { qty: 900, arrival_date: '2020-01-01', status: 'transit', route: 'SLOW_SEA' };
    expect(partitionShipmentsForLedger([stale], null).counted).toHaveLength(1);
  });
});

describe('partitionShipmentsForLedger — the walked-window edges', () => {
  const WINDOW = { from: '2026-08-07', to: '2027-11-15' };
  /** An arrival_date that reads back as this exact local day in any timezone. */
  const onDay = (y: number, m: number, d: number) => new Date(y, m - 1, d).toISOString();
  const shipmentOn = (iso: string): ProjectionShipment =>
    ({ qty: 1000, arrival_date: iso, status: 'transit', route: 'SLOW_SEA' });
  const reasonFor = (iso: string) =>
    partitionShipmentsForLedger([shipmentOn(iso)], WINDOW).excluded[0]?.exclusionReason ?? null;

  it('counts an arrival on the first walked day', () => {
    expect(reasonFor(onDay(2026, 8, 7))).toBeNull();
  });

  it('excludes an arrival one day before the walk starts', () => {
    expect(reasonFor(onDay(2026, 8, 6))).toBe(EXCLUSION_REASONS.ALREADY_LANDED);
  });

  it('counts an arrival on the last walked day', () => {
    expect(reasonFor(onDay(2027, 11, 15))).toBeNull();
  });

  it('excludes an arrival one day after the walk ends', () => {
    expect(reasonFor(onDay(2027, 11, 16))).toBe(EXCLUSION_REASONS.BEYOND_HORIZON);
  });

  it('files a timestamped arrival under the local day the engine uses, not the raw string', () => {
    // localDateKey(new Date(iso)) is exactly what `arrivalsByDay` keys on.
    const row = partitionShipmentsForLedger([shipmentOn(onDay(2026, 9, 10))], WINDOW).counted[0];
    expect(row.arrivalDate).toBe('2026-09-10');
  });
});

describe('the engine states its own walk window', () => {
  // The panel reads plan.walkWindow rather than re-deriving it from plan.series.
  // This pins the invariant that made that safe: the stated window is exactly
  // the span of the series the engine walked.
  const input: SplitInput = {
    cartons: 100, packageQuantity: 10, fbaOnHand: 50_000, awdOnHand: 0, shipments: [],
    curve: {
      productDemand: { 202608: 300, 202609: 300, 202610: 310, 202611: 300, 202612: 310 },
      familySeason: {}, growth: 1,
    },
    transitDays: { FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 },
    fbaInboundBufferDays: 10, today: new Date(2026, 7, 7),
    fbaTargetDoc: 45, fbaReorderDoc: 30, fbaBatchDoc: 60, totalTargetDoc: 100,
  };

  it('spans the series it produced', () => {
    const plan = planSplit(input);
    expect(plan.ok).toBe(true);
    expect(plan.series.length).toBeGreaterThan(0);
    expect(plan.walkWindow).toEqual({
      from: plan.series[0].date,
      to: plan.series[plan.series.length - 1].date,
    });
  });

  it('is null when there is no plan to have a window', () => {
    expect(planSplit({ ...input, cartons: 0 }).walkWindow).toBeNull();
  });

  it('states the same window BEFORE the plan exists, which is what the ledger needs', () => {
    // The ledger has to know the window in order to decide which shipments the
    // engine is even given — it cannot wait for `plan.walkWindow`. This pins the
    // two together so the window judged and the window walked cannot drift.
    expect(plannedWalkWindow(input.today, input.totalTargetDoc)).toEqual(planSplit(input).walkWindow);
    expect(plannedWalkWindow(input.today, input.totalTargetDoc)).toEqual({ from: '2026-08-07', to: '2027-11-15' });

    // The four levels move together or not at all: a reorder point must stay
    // strictly under the transfer target, and the delivery fill between that
    // target and the combined one. 30 against a 20-day target, or a 60-day fill
    // against a 30-day combined target, would be rejected outright.
    const shorter = {
      ...input, fbaTargetDoc: 20, fbaReorderDoc: 12, fbaBatchDoc: 25, totalTargetDoc: 30,
    };
    expect(plannedWalkWindow(shorter.today, shorter.totalTargetDoc)).toEqual(planSplit(shorter).walkWindow);
  });
});

describe('the ledger agrees with what the engine measurably did', () => {
  // Flat 300/month ~ 10/day, matching the engine's own test fixture.
  const FLAT: Record<number, number> = {
    202608: 300, 202609: 300, 202610: 310, 202611: 300, 202612: 310, 202701: 310,
    202702: 280, 202703: 310, 202704: 300, 202705: 310, 202706: 300, 202707: 310,
    202708: 310, 202709: 300, 202710: 310, 202711: 300, 202712: 310,
  };
  const base: SplitInput = {
    cartons: 100, packageQuantity: 10, fbaOnHand: 50_000, awdOnHand: 0, shipments: [],
    curve: { productDemand: FLAT, familySeason: {}, growth: 1 },
    transitDays: { FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 },
    fbaInboundBufferDays: 10, today: new Date(2026, 7, 7),
    fbaTargetDoc: 45, fbaReorderDoc: 30, fbaBatchDoc: 60, totalTargetDoc: 100,
  };
  const onDay = (y: number, m: number, d: number) => new Date(y, m - 1, d).toISOString();

  it('never counts a past-dated arrival, because the engine measurably ignores it', () => {
    const past: ProjectionShipment = { qty: 9000, arrival_date: onDay(2026, 6, 1), status: 'transit', route: 'SLOW_SEA' };
    const without = planSplit(base);
    const withPast = planSplit({ ...base, shipments: [past] });

    // Measured: the 9,000 units move nothing. walkFba starts at today and reads no
    // earlier key, so the stock is presumed already inside the fbaOnHand snapshot.
    expect(withPast.onHandAtSellable).toBe(without.onHandAtSellable);
    expect(withPast.onHandAtSellable).toBe(49_528);
    expect(withPast.legs).toEqual(without.legs);

    const { counted, excluded } = partitionShipmentsForLedger([past], withPast.walkWindow);
    expect(counted).toEqual([]);
    expect(excluded[0].exclusionReason).toBe(EXCLUSION_REASONS.ALREADY_LANDED);
  });

  it('never counts an arrival past the end of the walk, for the same measured reason', () => {
    const plan = planSplit(base);
    const lastDay = plan.series[plan.series.length - 1].date;
    const [y, m, d] = lastDay.split('-').map(Number);
    const beyond: ProjectionShipment = { qty: 9000, arrival_date: onDay(y, m, d + 1), status: 'transit', route: 'SLOW_SEA' };

    const withBeyond = planSplit({ ...base, shipments: [beyond] });
    expect(withBeyond.onHandAtSellable).toBe(plan.onHandAtSellable);
    expect(withBeyond.series.map(s => s.fbaUnits)).toEqual(plan.series.map(s => s.fbaUnits));

    const { counted, excluded } = partitionShipmentsForLedger([beyond], withBeyond.walkWindow);
    expect(counted).toEqual([]);
    expect(excluded[0].exclusionReason).toBe(EXCLUSION_REASONS.BEYOND_HORIZON);
  });

  it('still counts an in-window arrival, which the engine measurably does use', () => {
    const soon: ProjectionShipment = { qty: 9000, arrival_date: onDay(2026, 9, 10), status: 'transit', route: 'SLOW_SEA' };
    const withSoon = planSplit({ ...base, shipments: [soon] });
    // 9,000 units land before the sellable date, so on-hand there is 9,000 higher.
    expect(withSoon.onHandAtSellable).toBe(49_528 + 9_000);

    const { counted } = partitionShipmentsForLedger([soon], withSoon.walkWindow);
    expect(counted).toHaveLength(1);
    expect(counted[0].exclusionReason).toBeNull();
  });
});

describe('reconcileInboundWithSnapshot', () => {
  const WINDOW = { from: '2026-08-07', to: '2027-11-15' };
  const rec = (qty: number, arrival: string): ProjectionShipment =>
    ({ qty, arrival_date: arrival, status: 'transit', route: 'SLOW_SEA' });
  /** The rows the ledger would otherwise count — built through the real partition. */
  const countedRows = (rows: ProjectionShipment[]) =>
    partitionShipmentsForLedger(rows, WINDOW).counted;

  // 1,400 units of records across four arrivals, latest 2026-11-01.
  const RECORDS = [rec(400, '2026-08-20'), rec(500, '2026-09-10'), rec(300, '2026-10-01'), rec(200, '2026-11-01')];

  it('keeps latest first, trims the row that straddles the total, and drops the rest', () => {
    // Snapshot 600. Walking back from the latest arrival: 11-01 takes 200
    // (running 200), 10-01 takes 300 (running 500), 09-10 has only 100 of
    // headroom left so it is trimmed from 500 to 100, and 08-20 gets nothing.
    const got = reconcileInboundWithSnapshot(countedRows(RECORDS), 600);

    expect(got.rows.map(r => [r.row.arrivalDate, r.disposition, r.countedUnits])).toEqual([
      ['2026-11-01', 'KEPT', 200],
      ['2026-10-01', 'KEPT', 300],
      ['2026-09-10', 'TRIMMED', 100],
      ['2026-08-20', 'DROPPED', 0],
    ]);
    expect(got.recordUnits).toBe(1400);
    expect(got.snapshotUnits).toBe(600);
    expect(got.countedUnits).toBe(600);
    expect(got.removedUnits).toBe(800);
    expect(got.unexplainedUnits).toBe(0);
  });

  it('hands the engine the trimmed quantities, not the recorded ones', () => {
    const got = reconcileInboundWithSnapshot(countedRows(RECORDS), 600);
    expect(got.shipments.map(s => [s.arrival_date, s.qty])).toEqual([
      ['2026-11-01', 200], ['2026-10-01', 300], ['2026-09-10', 100],
    ]);
    expect(got.shipments.reduce((s, x) => s + x.qty, 0)).toBe(600);
  });

  it('names the record total, the snapshot total and the gap in one line', () => {
    const said = reconcileInboundWithSnapshot(countedRows(RECORDS), 600).summary;
    expect(said).toMatch(/records claim 1,400 units inbound to FBA/);
    expect(said).toMatch(/Amazon's snapshot says 600/);
    expect(said).toMatch(/800 units were removed/);
    expect(said).toMatch(/2 kept whole, 1 trimmed, 1 dropped/);
  });

  it('leaves the record objects untouched, so the ledger and the engine agree', () => {
    const rows = countedRows(RECORDS);
    const got = reconcileInboundWithSnapshot(rows, 600);
    // A kept row is passed by reference; only a trimmed one is a copy.
    expect(got.shipments[0]).toBe(rows.find(r => r.arrivalDate === '2026-11-01')!.shipment);
    expect(got.shipments[2]).not.toBe(rows.find(r => r.arrivalDate === '2026-09-10')!.shipment);
    expect(RECORDS.map(s => s.qty)).toEqual([400, 500, 300, 200]);
  });

  it('conserves units: what is counted plus what was removed is what the records claimed', () => {
    for (const snapshot of [0, 137, 600, 1399, 1400]) {
      const got = reconcileInboundWithSnapshot(countedRows(RECORDS), snapshot);
      expect(got.countedUnits + got.removedUnits).toBe(got.recordUnits);
      expect(got.rows.reduce((s, r) => s + r.countedUnits, 0)).toBe(got.countedUnits);
      expect(got.shipments.reduce((s, x) => s + x.qty, 0)).toBe(got.countedUnits);
    }
  });

  it('changes nothing when the snapshot matches the records exactly', () => {
    const got = reconcileInboundWithSnapshot(countedRows(RECORDS), 1400);
    expect(got.rows.every(r => r.disposition === 'KEPT')).toBe(true);
    expect(got.countedUnits).toBe(1400);
    expect(got.removedUnits).toBe(0);
    expect(got.unexplainedUnits).toBe(0);
    expect(got.summary).toMatch(/Amazon's snapshot agrees\. Nothing was changed\./);
  });

  it('keeps every row when the snapshot is larger, and reports the surplus rather than inventing it', () => {
    // Amazon knows about 600 units no shipment record explains. They are named,
    // not added: nothing here says when they would land.
    const got = reconcileInboundWithSnapshot(countedRows(RECORDS), 2000);
    expect(got.rows.every(r => r.disposition === 'KEPT')).toBe(true);
    expect(got.countedUnits).toBe(1400);
    expect(got.removedUnits).toBe(0);
    expect(got.unexplainedUnits).toBe(600);
    expect(got.summary).toMatch(/600 units Amazon reports have no shipment record behind them/);
    expect(got.summary).toMatch(/NOT added to the projection/);
  });

  it('drops everything when the snapshot says nothing is on the water', () => {
    const got = reconcileInboundWithSnapshot(countedRows(RECORDS), 0);
    expect(got.rows.every(r => r.disposition === 'DROPPED')).toBe(true);
    expect(got.shipments).toEqual([]);
    expect(got.countedUnits).toBe(0);
    expect(got.removedUnits).toBe(1400);
    expect(got.snapshotUnits).toBe(0);
  });

  it('falls back to the records unchanged when the snapshot is unavailable — never to zero', () => {
    // A missing figure means "unverified". Reading it as zero would delete every
    // inbound shipment and oversize the batch just as blindly.
    for (const missing of [undefined, null, NaN, -5]) {
      const got = reconcileInboundWithSnapshot(countedRows(RECORDS), missing);
      expect(got.snapshotUnits).toBeNull();
      expect(got.countedUnits).toBe(1400);
      expect(got.removedUnits).toBe(0);
      expect(got.rows.every(r => r.disposition === 'KEPT')).toBe(true);
      expect(got.shipments).toHaveLength(4);
      expect(got.summary).toMatch(/in-transit figure is unavailable/);
      expect(got.summary).toMatch(/unverified/);
    }
  });

  it('still orders an unavailable-snapshot fallback latest first, so the table reads the same either way', () => {
    const got = reconcileInboundWithSnapshot(countedRows(RECORDS), undefined);
    expect(got.rows.map(r => r.row.arrivalDate))
      .toEqual(['2026-11-01', '2026-10-01', '2026-09-10', '2026-08-20']);
  });

  it('handles no rows at all', () => {
    expect(reconcileInboundWithSnapshot([], 500)).toMatchObject({
      shipments: [], rows: [], recordUnits: 0, countedUnits: 0,
      removedUnits: 0, unexplainedUnits: 500,
    });
    expect(reconcileInboundWithSnapshot([], 0).summary).toMatch(/claim 0 units inbound to FBA and Amazon's snapshot agrees/);
    expect(reconcileInboundWithSnapshot([], undefined).snapshotUnits).toBeNull();
  });

  it('breaks a same-day tie by input order, so the result is reproducible', () => {
    const sameDay = [rec(100, '2026-09-10'), rec(100, '2026-09-10'), rec(100, '2026-09-10')];
    const got = reconcileInboundWithSnapshot(countedRows(sameDay), 150);
    expect(got.rows.map(r => [r.recordUnits, r.disposition, r.countedUnits])).toEqual([
      [100, 'KEPT', 100], [100, 'TRIMMED', 50], [100, 'DROPPED', 0],
    ]);
  });

  it('says what happened per row, without borrowing an exclusion reason', () => {
    const notes = reconcileInboundWithSnapshot(countedRows(RECORDS), 600).rows.map(dispositionNote);
    expect(notes[0]).toBe('Adds 200 units to FBA on 2026-11-01');
    expect(notes[2]).toMatch(/Trimmed to 100 of 500 units on 2026-09-10/);
    expect(notes[3]).toMatch(/^Dropped — /);
    const reasons = Object.values(EXCLUSION_REASONS);
    for (const note of notes) expect(reasons).not.toContain(note);
  });
});

describe('reconcileInboundWithSnapshot — the Mint LolliME case that prompted this', () => {
  // Real DE_MANUFACTURER_SHIPMENTS lines for Mint LolliME, all status PENDING —
  // which `useShipmentHistory` reads as "in transit" because nothing ever sets
  // the IN_TRANSIT the LOV offers. 17 lines claim 2,868 units; six of them are
  // past-dated and the ledger already excludes those, leaving 11 lines and
  // 1,548 units in the window. Amazon's own snapshot says 1,020.
  const WINDOW = { from: '2026-08-07', to: '2027-11-15' };
  const line = (qty: number, arrival: string): ProjectionShipment =>
    ({ qty, arrival_date: arrival, status: 'transit', route: 'SLOW_SEA' });

  const ALL_LINES = [
    line(360, '2026-07-15'), line(156, '2026-07-20'), line(276, '2026-07-20'), line(180, '2026-07-20'),
    line(180, '2026-07-29'), line(168, '2026-07-31'),
    line(36, '2026-08-12'), line(48, '2026-08-12'), line(48, '2026-08-12'), line(48, '2026-08-12'), line(72, '2026-08-12'),
    line(96, '2026-08-26'), line(120, '2026-08-26'), line(156, '2026-08-26'), line(696, '2026-08-26'),
    line(108, '2026-08-26'), line(120, '2026-08-26'),
  ];

  it("trims 1,548 recorded units down to Amazon's 1,020", () => {
    const ledger = partitionShipmentsForLedger(ALL_LINES, WINDOW);
    expect(ALL_LINES.reduce((s, l) => s + l.qty, 0)).toBe(2868);
    expect(ledger.counted).toHaveLength(11);
    expect(ledger.excluded).toHaveLength(6);   // the six past-dated lines
    expect(ledger.counted.reduce((s, r) => s + r.qty, 0)).toBe(1548);

    const got = reconcileInboundWithSnapshot(ledger.counted, 1020);
    // Latest first: the 08-26 group takes 96 + 120 + 156 = 372, the 696-unit
    // line straddles the 1,020 line and is trimmed to 648, and everything
    // earlier — the last two 08-26 lines and all five 08-12 lines — is dropped.
    expect(got.rows.map(r => [r.recordUnits, r.disposition, r.countedUnits])).toEqual([
      [96, 'KEPT', 96], [120, 'KEPT', 120], [156, 'KEPT', 156], [696, 'TRIMMED', 648],
      [108, 'DROPPED', 0], [120, 'DROPPED', 0],
      [36, 'DROPPED', 0], [48, 'DROPPED', 0], [48, 'DROPPED', 0], [48, 'DROPPED', 0], [72, 'DROPPED', 0],
    ]);
    expect(got.countedUnits).toBe(1020);
    expect(got.removedUnits).toBe(528);
    expect(got.summary).toMatch(/records claim 1,548 units inbound to FBA; Amazon's snapshot says 1,020/);
    expect(got.summary).toMatch(/3 kept whole, 1 trimmed, 7 dropped/);
  });

  it('leaves the FBA leg bigger, because less stock is believed inbound', () => {
    // 5,000-unit batch, nothing at FBA, flat 10/day demand. FBA is empty today
    // so the method escalates and the batch is sellable 2026-09-18; the 60-day
    // delivery fill from there is 600 units.
    const FLAT: Record<number, number> = {
      202608: 300, 202609: 300, 202610: 310, 202611: 300, 202612: 310, 202701: 310,
      202702: 280, 202703: 310, 202704: 300, 202705: 310, 202706: 300, 202707: 310,
      202708: 310, 202709: 300, 202710: 310, 202711: 300, 202712: 310,
    };
    const input: SplitInput = {
      cartons: 500, packageQuantity: 10, fbaOnHand: 0, awdOnHand: 0, shipments: [],
      curve: { productDemand: FLAT, familySeason: {}, growth: 1 },
      transitDays: { FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 },
      fbaInboundBufferDays: 10, today: new Date(2026, 7, 7),
      fbaTargetDoc: 45, fbaReorderDoc: 30, fbaBatchDoc: 60, totalTargetDoc: 100,
    };
    const records = [
      { qty: 300, arrival_date: '2026-09-10', status: 'transit' as const, route: 'SLOW_SEA' },
      { qty: 200, arrival_date: '2026-09-15', status: 'transit' as const, route: 'SLOW_SEA' },
    ];
    const counted = partitionShipmentsForLedger(records, plannedWalkWindow(input.today, 100)).counted;

    // Believing all 500: both land before 09-18, and 8 days of demand burn from
    // the first arrival — 500 − 80 = 420 on hand, so only 180 units are needed.
    const believed = planSplit({ ...input, shipments: reconcileInboundWithSnapshot(counted, undefined).shipments });
    expect(believed.onHandAtSellable).toBe(420);
    expect(believed.legs.find(l => l.destination === 'FBA')!.units).toBe(180);

    // Amazon says 200. The later row survives whole, the 300 is dropped: 200
    // lands 09-15 and burns 3 days = 170 on hand, so 430 units are needed.
    // Not the full 300 difference — for five of those days FBA is simply dark,
    // and unmet demand is lost rather than eating the reserve.
    const reconciled = planSplit({ ...input, shipments: reconcileInboundWithSnapshot(counted, 200).shipments });
    expect(reconciled.onHandAtSellable).toBe(170);
    expect(reconciled.legs.find(l => l.destination === 'FBA')!.units).toBe(430);

    // The whole point: less believed inbound means a BIGGER shipment to FBA.
    expect(reconciled.legs.find(l => l.destination === 'FBA')!.units)
      .toBeGreaterThan(believed.legs.find(l => l.destination === 'FBA')!.units);
    expect(reconciled.units).toBe(believed.units); // and the batch is unchanged
  });
});

describe('awdInboundFromSnapshot', () => {
  it('carries the quantity and deliberately no date', () => {
    expect(awdInboundFromSnapshot(1056)).toEqual([{ units: 1056 }]);
  });

  it('yields nothing for zero, missing or unreadable figures', () => {
    expect(awdInboundFromSnapshot(0)).toEqual([]);
    expect(awdInboundFromSnapshot(undefined)).toEqual([]);
    expect(awdInboundFromSnapshot(null)).toEqual([]);
    expect(awdInboundFromSnapshot(NaN)).toEqual([]);
    expect(awdInboundFromSnapshot(-10)).toEqual([]);
  });
});

describe('buildDemandCurve', () => {
  const demandMap: ForecastDemandMap = { 'Pink Lollibox': { 202608: 300, 202609: 310 } };
  const season: Record<number, MonthSeasonInfo> = { 202611: { peakDays: 12, offseasonDays: 18, holidays: 'BFCM' } };
  const seasonMap: MonthSeasonMap = { Lollibox: season };
  const metaMap: ForecastMetaMap = {
    'Pink Lollibox': { isNew: false, isDraft: false, share: 0.4, family: 'Lollibox' },
    'Orphan Product': { isNew: false, isDraft: false, share: 0.1, family: '' },
  };

  it('assembles product demand, family seasonality and the growth override', () => {
    expect(buildDemandCurve({
      product: 'Pink Lollibox', demandMap, seasonMap, metaMap, growthOverrides: { 'Pink Lollibox': 1.2 },
    })).toEqual({ productDemand: { 202608: 300, 202609: 310 }, familySeason: season, growth: 1.2 });
  });

  it('defaults growth to 1.0 when the product has no override', () => {
    expect(buildDemandCurve({ product: 'Pink Lollibox', demandMap, seasonMap, metaMap }).growth).toBe(1.0);
    expect(buildDemandCurve({
      product: 'Pink Lollibox', demandMap, seasonMap, metaMap, growthOverrides: {},
    }).growth).toBe(1.0);
  });

  it('leaves seasonality empty for a product with no family', () => {
    // Blank family and no meta row at all both mean "no family season to apply".
    expect(buildDemandCurve({ product: 'Orphan Product', demandMap, seasonMap, metaMap }).familySeason).toEqual({});
    expect(buildDemandCurve({ product: 'Unknown Product', demandMap, seasonMap, metaMap }).familySeason).toEqual({});
  });

  it('leaves seasonality empty when the family has no season map entry', () => {
    expect(buildDemandCurve({
      product: 'Pink Lollibox', demandMap, seasonMap: {}, metaMap,
    }).familySeason).toEqual({});
  });

  it('leaves product demand empty for a product with no forecast', () => {
    expect(buildDemandCurve({ product: 'Unknown Product', demandMap, seasonMap, metaMap }).productDemand).toEqual({});
  });
});

describe('buildDemandLedger', () => {
  const FLAT: Record<number, number> = { 202608: 300, 202609: 300, 202610: 310, 202611: 300, 202612: 310 };
  const SEASON: Record<number, MonthSeasonInfo> = {
    202611: { peakDays: 12, offseasonDays: 18, holidays: 'BFCM' },
    202612: { peakDays: 15, offseasonDays: 16, holidays: 'Christmas' },
  };

  it('emits one row per calendar month the horizon touches, inclusive of both ends', () => {
    const curve: DemandCurve = { productDemand: FLAT, familySeason: {}, growth: 1 };
    const rows = buildDemandLedger(curve, '2026-08-07', '2026-10-15');
    expect(rows.map(r => r.yearMonth)).toEqual([202608, 202609, 202610]);
    expect(rows.map(r => r.label)).toEqual(['Aug 2026', 'Sep 2026', 'Oct 2026']);
  });

  it('shows the raw forecast, the growth multiplier and the product of the two', () => {
    const curve: DemandCurve = { productDemand: FLAT, familySeason: {}, growth: 1.2 };
    const [aug] = buildDemandLedger(curve, '2026-08-07', '2026-08-31');
    expect(aug.forecastUnits).toBe(300);
    expect(aug.growth).toBe(1.2);
    expect(aug.units).toBeCloseTo(360, 6); // 300 x 1.2
  });

  it('spreads an unseasoned month evenly across its days', () => {
    const curve: DemandCurve = { productDemand: FLAT, familySeason: {}, growth: 1 };
    const [aug] = buildDemandLedger(curve, '2026-08-01', '2026-08-31');
    expect(aug.daysInMonth).toBe(31);
    expect(aug.peakDays).toBe(0);
    expect(aug.offseasonDays).toBe(31);
    expect(aug.holidays).toBeNull();
    // No peak weighting: every day carries 300 / 31 units.
    expect(aug.offseasonDailyUnits).toBeCloseTo(300 / 31, 9);
    expect(aug.peakDailyUnits).toBeCloseTo(300 / 31, 9);
  });

  it('weights peak days at twice the offseason rate, per the family season map', () => {
    const curve: DemandCurve = { productDemand: FLAT, familySeason: SEASON, growth: 1 };
    const [nov] = buildDemandLedger(curve, '2026-11-01', '2026-11-30');
    expect(nov.daysInMonth).toBe(30);
    expect(nov.peakDays).toBe(12);
    expect(nov.offseasonDays).toBe(18);
    expect(nov.holidays).toBe('BFCM');
    // 300 units over (12 peak x 2) + 18 offseason = 42 rate-units -> 300/42 per offseason day.
    expect(nov.offseasonDailyUnits).toBeCloseTo(300 / 42, 9);
    expect(nov.peakDailyUnits).toBeCloseTo(600 / 42, 9);
  });

  it('applies growth to the peak-weighted daily rates too', () => {
    const curve: DemandCurve = { productDemand: FLAT, familySeason: SEASON, growth: 2 };
    const [nov] = buildDemandLedger(curve, '2026-11-01', '2026-11-30');
    expect(nov.units).toBeCloseTo(600, 6);
    expect(nov.offseasonDailyUnits).toBeCloseTo(600 / 42, 9);
    expect(nov.peakDailyUnits).toBeCloseTo(1200 / 42, 9);
  });

  it('shows a month with no forecast as a zero row rather than hiding it', () => {
    const curve: DemandCurve = { productDemand: { 202608: 300 }, familySeason: {}, growth: 1 };
    const rows = buildDemandLedger(curve, '2026-08-15', '2026-09-15');
    expect(rows.map(r => r.yearMonth)).toEqual([202608, 202609]);
    expect(rows[1]).toMatchObject({ forecastUnits: 0, units: 0, offseasonDailyUnits: 0, peakDailyUnits: 0 });
  });

  it('crosses a year boundary', () => {
    const curve: DemandCurve = { productDemand: FLAT, familySeason: {}, growth: 1 };
    const rows = buildDemandLedger(curve, '2026-12-20', '2027-02-03');
    expect(rows.map(r => r.yearMonth)).toEqual([202612, 202701, 202702]);
    expect(rows.map(r => r.label)).toEqual(['Dec 2026', 'Jan 2027', 'Feb 2027']);
  });

  it('returns nothing for an unreadable or reversed range', () => {
    const curve: DemandCurve = { productDemand: FLAT, familySeason: {}, growth: 1 };
    expect(buildDemandLedger(curve, '2026-10-01', '2026-08-01')).toEqual([]);
    expect(buildDemandLedger(curve, '', '2026-08-01')).toEqual([]);
  });
});

describe('family → product selection', () => {
  const products = [
    { product: 'Pink Lollibox', packageQuantity: 12 },
    { product: 'Blue Lollibox', packageQuantity: 12 },
    { product: 'Hug Bunny', packageQuantity: 24 },
    { product: 'Orphan Item', packageQuantity: 6 },
  ];
  const familyOf = (p: string) =>
    ({ 'Pink Lollibox': 'Lollibox', 'Blue Lollibox': 'Lollibox', 'Hug Bunny': 'Bunny' } as Record<string, string>)[p];

  it('groups by family, sorts both levels, and parks familyless products under Other', () => {
    const g = groupProductsByFamily(products, familyOf);
    expect(g.families).toEqual(['Bunny', 'Lollibox', 'Other']);
    expect(g.byFamily.Lollibox.map(p => p.product)).toEqual(['Blue Lollibox', 'Pink Lollibox']);
    expect(g.byFamily.Other.map(p => p.product)).toEqual(['Orphan Item']);
  });

  it('keeps a valid pair as chosen', () => {
    const g = groupProductsByFamily(products, familyOf);
    expect(resolveFamilySelection(g, 'Lollibox', 'Pink Lollibox'))
      .toEqual({ family: 'Lollibox', product: 'Pink Lollibox' });
  });

  it('falls back to the first family when the wanted one is unknown', () => {
    const g = groupProductsByFamily(products, familyOf);
    expect(resolveFamilySelection(g, '', '').family).toBe('Bunny');
  });

  it('drops a product that does not belong to the chosen family', () => {
    const g = groupProductsByFamily(products, familyOf);
    // Hug Bunny is real, but not a Lollibox — the family wins.
    expect(resolveFamilySelection(g, 'Lollibox', 'Hug Bunny'))
      .toEqual({ family: 'Lollibox', product: 'Blue Lollibox' });
  });

  it('yields empty strings rather than throwing on an empty catalogue', () => {
    const g = groupProductsByFamily([], familyOf);
    expect(resolveFamilySelection(g, 'Lollibox', 'Anything')).toEqual({ family: '', product: '' });
  });
});
