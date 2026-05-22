import { useState, useEffect, useCallback } from 'react';
import { cubeLoad } from './useCubeData';

/**
 * Hook that replaces the legacy `famFromProduct` heuristic.
 * It queries the ProductColorMap cube (which maps to V_PRODUCT_FAMILY_MAP)
 * to provide a data-driven mapping from product short name to family name.
 */
export function useProductFamily() {
  const [map, setMap] = useState<Map<string, string>>(new Map());
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    cubeLoad({
      dimensions: ['ProductColorMap.productShortName', 'ProductColorMap.family'],
    })
      .then((rows) => {
        if (!active) return;
        const newMap = new Map<string, string>();
        for (const r of rows as any[]) {
          const prod = r['ProductColorMap.productShortName'];
          const fam = r['ProductColorMap.family'];
          if (prod && fam) {
            newMap.set(prod, fam);
            // Also map lowercase for robust matching if needed
            newMap.set(prod.toLowerCase(), fam);
          }
        }
        setMap(newMap);
        setLoading(false);
      })
      .catch((err) => {
        console.error('Failed to load product family map:', err);
        if (active) setLoading(false);
      });

    return () => { active = false; };
  }, []);

  const getFamily = useCallback((productName: string | null | undefined): string | null => {
    if (!productName) return null;
    // Exact match first
    if (map.has(productName)) return map.get(productName)!;
    // Lowercase match
    if (map.has(productName.toLowerCase())) return map.get(productName.toLowerCase())!;
    
    // Fallback logic for unmatched items (should ideally be empty if data is complete, 
    // but useful during transition or for edge case names)
    const p = productName.toLowerCase();
    for (const [key, family] of map.entries()) {
      // Very basic substring match as a last resort, similar to old heuristic but data-driven
      // Only do this if we really need to fallback
      if (p.includes(key.toLowerCase()) && key.length > 3) {
        return family;
      }
    }
    return null;
  }, [map]);

  return { getFamily, loading };
}
