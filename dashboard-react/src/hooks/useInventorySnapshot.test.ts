import { describe, it, expect, vi, afterEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { mapInventoryRows, useInventorySnapshot } from './useInventorySnapshot';
import { cubeLoad } from './useCubeData';

vi.mock('./useCubeData', () => ({ cubeLoad: vi.fn() }));
const mockCubeLoad = vi.mocked(cubeLoad);
afterEach(() => { mockCubeLoad.mockReset(); });

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

  it('keeps the two in-transit legs apart and out of the on-hand maps', () => {
    // "In Transit" is FBA-bound, "In Transit AWD" lands in the reserve. Neither
    // is on hand, so neither may reach stockMap/fbaMap/awdMap — but both are
    // owned, so both have to be readable.
    const maps = mapInventoryRows([
      row('Mint LolliME', 'FBA', 980),
      row('Mint LolliME', 'AWD', 0),
      row('Mint LolliME', 'In Transit', 1020),
      row('Mint LolliME', 'In Transit AWD', 1056),
    ]);
    expect(maps.inTransitFbaMap).toEqual({ 'Mint LolliME': 1020 });
    expect(maps.inTransitAwdMap).toEqual({ 'Mint LolliME': 1056 });
    expect(maps.fbaMap).toEqual({ 'Mint LolliME': 980 });
    expect(maps.awdMap).toEqual({ 'Mint LolliME': 0 });
    expect(maps.stockMap).toEqual({ 'Mint LolliME': 980 });
  });

  it('does not read "In Transit AWD" as "In Transit"', () => {
    const maps = mapInventoryRows([row('Bottle', 'In Transit AWD', 500)]);
    expect(maps.inTransitFbaMap).toEqual({});
    expect(maps.inTransitAwdMap).toEqual({ Bottle: 500 });
  });

  it('records an explicit zero, which is not the same as an absent product', () => {
    // The reconciliation treats a missing key as "unavailable" and a zero as
    // "Amazon says nothing is inbound" — two very different plans.
    const maps = mapInventoryRows([row('Bottle', 'In Transit', 0)]);
    expect(maps.inTransitFbaMap.Bottle).toBe(0);
    expect(maps.inTransitFbaMap.Bunny).toBeUndefined();
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

describe('useInventorySnapshot', () => {
  it('resolves populated maps with no error on the happy path', async () => {
    mockCubeLoad
      .mockResolvedValueOnce([{ 'InventorySnapshot.latestSnapshotDate': '2026-08-06' }])
      .mockResolvedValueOnce([row('Bottle', 'FBA', 300), row('Bottle', 'AWD', 700)]);

    const { result } = renderHook(() => useInventorySnapshot());

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.error).toBeNull();
    expect(result.current.snapshotDate).toBe('2026-08-06');
    expect(result.current.fbaMap).toEqual({ Bottle: 300 });
    expect(result.current.awdMap).toEqual({ Bottle: 700 });
    expect(result.current.stockMap).toEqual({ Bottle: 1000 });
  });

  it('exposes both in-transit maps off the same single query', async () => {
    mockCubeLoad
      .mockResolvedValueOnce([{ 'InventorySnapshot.latestSnapshotDate': '2026-08-06' }])
      .mockResolvedValueOnce([row('Bottle', 'In Transit', 250), row('Bottle', 'In Transit AWD', 800)]);

    const { result } = renderHook(() => useInventorySnapshot());

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.inTransitFbaMap).toEqual({ Bottle: 250 });
    expect(result.current.inTransitAwdMap).toEqual({ Bottle: 800 });
    expect(mockCubeLoad).toHaveBeenCalledTimes(2);
  });

  it('sets an error and stays empty when no latest snapshot date is returned', async () => {
    mockCubeLoad.mockResolvedValueOnce([]);

    const { result } = renderHook(() => useInventorySnapshot());

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.error).toBe('No inventory snapshot available');
    expect(result.current.stockMap).toEqual({});
    expect(result.current.fbaMap).toEqual({});
    expect(mockCubeLoad).toHaveBeenCalledTimes(1);
  });

  it('sets an error and stops loading when cubeLoad rejects', async () => {
    mockCubeLoad.mockRejectedValueOnce(new Error('Cube HTTP 500'));

    const { result } = renderHook(() => useInventorySnapshot());

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.error).toBe('Cube HTTP 500');
    expect(result.current.stockMap).toEqual({});
    expect(result.current.fbaMap).toEqual({});
  });
});
