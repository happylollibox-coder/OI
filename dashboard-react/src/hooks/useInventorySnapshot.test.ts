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
