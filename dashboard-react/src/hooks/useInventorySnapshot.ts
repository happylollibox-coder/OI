import { useState, useEffect } from 'react';
import { cubeLoad } from './useCubeData';

export interface InventoryMaps {
  stockMap: Record<string, number>;    // FBA + AWD only, for consumers that want one pooled sellable number; excludes MFR Ready / In Production because that stock isn't sellable yet
  fbaMap: Record<string, number>;
  awdMap: Record<string, number>;
  mfrReadyMap: Record<string, number>;
  mfrInProdMap: Record<string, number>;
  /**
   * Amazon's own count of stock on the water to FBA. Deliberately NOT folded
   * into stockMap: it is not on hand and not sellable. It is the authority on
   * HOW MUCH is inbound — the shipment records are only the authority on WHEN
   * it lands, and where the two disagree the records are the ones that are
   * wrong (a shipment entered but never dispatched still reads as in transit).
   */
  inTransitFbaMap: Record<string, number>;
  /** Same, for stock on the water to the AWD reserve. Owned, not yet sellable. */
  inTransitAwdMap: Record<string, number>;
}

const EMPTY: InventoryMaps = {
  stockMap: {}, fbaMap: {}, awdMap: {}, mfrReadyMap: {}, mfrInProdMap: {},
  inTransitFbaMap: {}, inTransitAwdMap: {},
};

/** Pure: fold Cube rows into per-source maps. */
export function mapInventoryRows(rows: Record<string, unknown>[]): InventoryMaps {
  const maps: InventoryMaps = {
    stockMap: {}, fbaMap: {}, awdMap: {}, mfrReadyMap: {}, mfrInProdMap: {},
    inTransitFbaMap: {}, inTransitAwdMap: {},
  };
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
    // 'In Transit AWD' must be tested before 'In Transit' would ever be matched
    // loosely; they are exact comparisons here, so order is only readability.
    else if (source === 'In Transit AWD') add(maps.inTransitAwdMap, product, units);
    else if (source === 'In Transit') add(maps.inTransitFbaMap, product, units);
  }
  return maps;
}

/** Latest InventorySnapshot, folded per source. One query shared by all consumers. */
export function useInventorySnapshot(): InventoryMaps & { loading: boolean; snapshotDate: string | null; error: string | null } {
  const [maps, setMaps] = useState<InventoryMaps>(EMPTY);
  const [snapshotDate, setSnapshotDate] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const dateRows = await cubeLoad({ measures: ['InventorySnapshot.latestSnapshotDate'] });
        const latestDate = (dateRows as Record<string, unknown>[])[0]?.['InventorySnapshot.latestSnapshotDate'];
        if (!latestDate) { setError('No inventory snapshot available'); setLoading(false); return; }

        const rows = await cubeLoad({
          measures: ['InventorySnapshot.totalUnits'],
          dimensions: ['InventorySnapshot.productShortName', 'InventorySnapshot.sourceType'],
          filters: [{ member: 'InventorySnapshot.date', operator: 'equals', values: [String(latestDate)] }],
        });
        setMaps(mapInventoryRows(rows as Record<string, unknown>[]));
        setSnapshotDate(String(latestDate));
      } catch (e) {
        console.warn('[useInventorySnapshot] load failed', e);
        setError(e instanceof Error ? e.message : 'Inventory snapshot load failed');
      }
      setLoading(false);
    })();
  }, []);

  return { ...maps, loading, snapshotDate, error };
}
