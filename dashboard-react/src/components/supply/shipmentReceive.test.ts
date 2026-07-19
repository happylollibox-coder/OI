import { describe, it, expect } from 'vitest';
import { classifyDueShipments, isDueToReceive, isReceived, fmtMonDay } from './shipmentReceive';

const TODAY = '2026-07-10';
const base = { ship_date: '2026-06-10', type: 'SLOW_SEA', warehouse_id: 'WH1' };

describe('isReceived', () => {
  it('treats RECEIVED / INSPECTED / PUT_AWAY (any case) as received', () => {
    expect(isReceived('RECEIVED')).toBe(true);
    expect(isReceived('inspected')).toBe(true);
    expect(isReceived('Put_Away')).toBe(true);
  });
  it('treats PENDING / IN_TRANSIT / SHIPPED / empty as not received', () => {
    expect(isReceived('PENDING')).toBe(false);
    expect(isReceived('IN_TRANSIT')).toBe(false);
    expect(isReceived('SHIPPED')).toBe(false);
    expect(isReceived('')).toBe(false);
  });
});

describe('isDueToReceive', () => {
  it('is due when ETA is exactly 3 days out', () => {
    expect(isDueToReceive('PENDING', '2026-07-13', TODAY)).toBe(true);
  });
  it('is NOT due when ETA is 4+ days out', () => {
    expect(isDueToReceive('PENDING', '2026-07-14', TODAY)).toBe(false);
  });
  it('is due (overdue) when ETA is in the past', () => {
    expect(isDueToReceive('PENDING', '2026-07-01', TODAY)).toBe(true);
  });
  it('is never due once received, even if overdue', () => {
    expect(isDueToReceive('RECEIVED', '2026-07-01', TODAY)).toBe(false);
  });
  it('is not due without an ETA', () => {
    expect(isDueToReceive('PENDING', null, TODAY)).toBe(false);
    expect(isDueToReceive('PENDING', '', TODAY)).toBe(false);
  });
  it('accepts full-timestamp ETAs from Cube', () => {
    expect(isDueToReceive('PENDING', '2026-07-11T00:00:00.000', TODAY)).toBe(true);
  });
});

describe('classifyDueShipments', () => {
  const rows = [
    { shipment_id: 's_overdue', products: 'Bottle', qty: 100, eta: '2026-07-02', status: 'PENDING', ...base },
    { shipment_id: 's_soon', products: 'Fresh', qty: 50, eta: '2026-07-12', status: 'IN_TRANSIT', ...base },
    { shipment_id: 's_far', products: 'LolliME', qty: 30, eta: '2026-08-01', status: 'PENDING', ...base },
    { shipment_id: 's_received', products: 'Bunny', qty: 20, eta: '2026-07-05', status: 'RECEIVED', ...base },
    { shipment_id: 's_noeta', products: 'X', qty: 10, eta: '', status: 'PENDING', ...base },
  ];

  it('keeps only non-received shipments within the window / overdue', () => {
    const out = classifyDueShipments(rows, TODAY);
    expect(out.map(r => r.shipment_id)).toEqual(['s_overdue', 's_soon']);
  });

  it('flags overdue correctly and sorts soonest ETA first', () => {
    const out = classifyDueShipments(rows, TODAY);
    expect(out[0]).toMatchObject({ shipment_id: 's_overdue', overdue: true });
    expect(out[1]).toMatchObject({ shipment_id: 's_soon', overdue: false });
  });

  it('carries through ship_date, type and warehouse_id', () => {
    const out = classifyDueShipments(rows, TODAY);
    expect(out[0]).toMatchObject({ ship_date: '2026-06-10', type: 'SLOW_SEA', warehouse_id: 'WH1' });
  });
});

describe('fmtMonDay', () => {
  it('formats YYYY-MM-DD as "Mon DD"', () => {
    expect(fmtMonDay('2026-07-09')).toBe('Jul 09');
    expect(fmtMonDay('2026-12-01')).toBe('Dec 01');
  });
  it('accepts full ISO timestamps', () => {
    expect(fmtMonDay('2026-07-09T00:00:00.000')).toBe('Jul 09');
  });
  it('returns a dash for empty/invalid input', () => {
    expect(fmtMonDay('')).toBe('—');
    expect(fmtMonDay(null)).toBe('—');
  });
});
