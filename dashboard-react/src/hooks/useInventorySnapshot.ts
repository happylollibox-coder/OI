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
