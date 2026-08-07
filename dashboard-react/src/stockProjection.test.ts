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
      if (fx.name === 'no shipments') console.log('GOLDEN_FIRST_WEEK=' + JSON.stringify(extracted[0]));
      expect(extracted).toEqual(legacy);
    });
  }
});
