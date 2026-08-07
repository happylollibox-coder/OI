import { describe, it, expect } from 'vitest';
import type { MonthSeasonInfo, ForecastDemandMap, ForecastMetaMap, MonthSeasonMap } from './planTypes';
import type { DemandCurve, ProjectionShipment } from './stockProjection';
import { confirmedFbaInbound, planSplit, type SplitInput } from './fbaAwdSplit';
import {
  TARGET_DOC, REQUIRED_TRANSIT_KEYS, EXCLUSION_REASONS,
  cartonPrefill, unitsFromCartons, docLabel, narrowTransitDays, resolveBatchInput,
  partitionShipmentsForLedger, buildDemandCurve, buildDemandLedger, transitLedgerEntries,
  groupProductsByFamily, resolveFamilySelection,
} from './splitPanelData';

describe('TARGET_DOC', () => {
  it('is the 100-day FBA cover level the operating rule names', () => {
    expect(TARGET_DOC).toBe(100);
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
  // The engine walks 2026-08-07 .. 2027-11-15 for today = 2026-08-07, targetDoc = 100.
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
    fbaInboundBufferDays: 10, today: new Date(2026, 7, 7), targetDoc: 100,
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
    fbaInboundBufferDays: 10, today: new Date(2026, 7, 7), targetDoc: 100,
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
