import { useState, useEffect } from 'react';
import { apiFetch } from '../utils/apiFetch';

export interface LovRow {
  value_id: string;
  value_caption: string;
  is_default: boolean;
  attr1_name?: string;
  attr1_value?: string;
}

export interface ShipmentConstants {
  transitDays: Record<string, number>;  // value_id -> days
  fbaInboundBufferDays: number;
  loaded: boolean;  // true = transitDays/fbaInboundBufferDays are live LOV values; false = still loading OR fetch attempt finished but failed and DEFAULT_CONSTANTS are in use — check `error` to tell those apart
  error: string | null;
}

/** Used only when Flask is unreachable or the LOV endpoint errors; the panel says so when this kicks in. */
export const DEFAULT_CONSTANTS = {
  transitDays: Object.freeze({ AIR: 10, FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 }) as Record<string, number>,
  fbaInboundBufferDays: 10,
};

/** A blank or whitespace-only string is "missing", not the number 0. */
function isBlank(v: string | undefined | null): v is undefined | null | '' {
  return v == null || v.trim() === '';
}

export function parseTransitDays(rows: LovRow[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const r of rows) {
    if (!r.value_id || isBlank(r.attr1_value)) continue;
    const n = Number(r.attr1_value);
    if (!Number.isFinite(n)) continue;
    out[r.value_id] = n;
  }
  return out;
}

export function parseBufferDays(rows: LovRow[]): number {
  const row = rows.find(r => r.value_id === 'FBA_INBOUND_BUFFER_DAYS');
  if (isBlank(row?.attr1_value)) return DEFAULT_CONSTANTS.fbaInboundBufferDays;
  const n = Number(row?.attr1_value);
  return Number.isFinite(n) ? n : DEFAULT_CONSTANTS.fbaInboundBufferDays;
}

/** Transit days + FBA inbound buffer, read from DE_LIST_OF_VALUES at runtime. */
export function useShipmentConstants(): ShipmentConstants {
  const [state, setState] = useState<ShipmentConstants>({
    transitDays: { ...DEFAULT_CONSTANTS.transitDays },
    fbaInboundBufferDays: DEFAULT_CONSTANTS.fbaInboundBufferDays,
    loaded: false,
    error: null,
  });

  useEffect(() => {
    (async () => {
      try {
        const [typeRes, peakRes] = await Promise.all([
          apiFetch('/api/lov/SHIPMENT_TYPE'),
          apiFetch('/api/lov/Q4_PEAK'),
        ]);
        const typeRows: LovRow[] = await typeRes.json();
        const peakRows: LovRow[] = await peakRes.json();
        if (!Array.isArray(typeRows) || !Array.isArray(peakRows)) {
          setState(s => ({ ...s, transitDays: { ...DEFAULT_CONSTANTS.transitDays }, error: 'LOV endpoint returned an unexpected (non-array) response; using default constants' }));
          return;
        }
        const transitDays = parseTransitDays(typeRows);
        if (Object.keys(transitDays).length === 0) {
          setState(s => ({ ...s, transitDays: { ...DEFAULT_CONSTANTS.transitDays }, error: 'SHIPMENT_TYPE LOV rows had no usable SHIPMENT_DAYS values; using default constants' }));
          return;
        }
        setState({
          transitDays,
          fbaInboundBufferDays: parseBufferDays(peakRows),
          loaded: true,
          error: null,
        });
      } catch (e) {
        console.warn('[useShipmentConstants] LOV load failed, using defaults', e);
        setState(s => ({ ...s, transitDays: { ...DEFAULT_CONSTANTS.transitDays }, error: e instanceof Error ? e.message : 'LOV load failed; using default constants' }));
      }
    })();
  }, []);

  return state;
}
