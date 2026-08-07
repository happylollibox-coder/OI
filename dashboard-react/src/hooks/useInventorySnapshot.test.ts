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
