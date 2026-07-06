/**
 * Pure amount-allocation helpers for BulkPaymentModal (PO mode).
 * No React — kept separate so the split logic is unit-testable.
 */

/** Payment-level allocation mode for POs. */
export type PoPayMode = 'full' | 'partial';

/**
 * Split `total` equally across `ids`, returned as 2-decimal strings.
 * Leftover cents are distributed to the first ids so the parts sum exactly
 * to `total`. Non-positive / NaN totals yield empty strings (nothing to pay).
 */
export function splitEqually(total: number, ids: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  const n = ids.length;
  if (n === 0) return out;
  if (!isFinite(total) || total <= 0) {
    for (const id of ids) out[id] = '';
    return out;
  }
  const totalCents = Math.round(total * 100);
  const base = Math.floor(totalCents / n);
  let remainder = totalCents - base * n;
  for (const id of ids) {
    const cents = base + (remainder > 0 ? 1 : 0);
    if (remainder > 0) remainder -= 1;
    out[id] = (cents / 100).toFixed(2);
  }
  return out;
}

/** Sortable columns of the PO candidate grid. */
export type PoSortKey = 'date' | 'product' | 'units' | 'manufacturer' | 'unpaid';
export interface PoSort {
  key: PoSortKey;
  dir: 'asc' | 'desc';
}

/** Minimal shape sortPos needs — matches the deduped PO rows. */
export interface SortablePo {
  order_date: string;
  products: string;
  units: number;
  manufacturer_name: string;
  unpaid_manufacturer: number;
}

/**
 * Return a new array sorted by the given column/direction. Pure, stable-ish
 * (relies on Array.prototype.sort). Dates are ISO strings so compare lexically.
 */
export function sortPos<T extends SortablePo>(rows: T[], sort: PoSort): T[] {
  const dir = sort.dir === 'asc' ? 1 : -1;
  const cmp = (a: T, b: T): number => {
    switch (sort.key) {
      case 'date':
        return a.order_date < b.order_date ? -1 : a.order_date > b.order_date ? 1 : 0;
      case 'product':
        return a.products.localeCompare(b.products);
      case 'units':
        return a.units - b.units;
      case 'manufacturer':
        return a.manufacturer_name.localeCompare(b.manufacturer_name);
      case 'unpaid':
        return a.unpaid_manufacturer - b.unpaid_manufacturer;
      default:
        return 0;
    }
  };
  return [...rows].sort((a, b) => cmp(a, b) * dir);
}

/** Sortable columns of the shipment candidate grid. */
export type ShipmentSortKey = 'date' | 'products' | 'type' | 'warehouse' | 'unpaid';
export interface ShipmentSort {
  key: ShipmentSortKey;
  dir: 'asc' | 'desc';
}

/** Minimal shape sortShipments needs — matches SupplyShipmentRow fields. */
export interface SortableShipment {
  shipment_date: string;
  products_list: string;
  shipment_type: string;
  tracking_number: string | null;
  unpaid_to_shipment: number;
}

/** Return a new array of shipments sorted by the given column/direction. Pure. */
export function sortShipments<T extends SortableShipment>(rows: T[], sort: ShipmentSort): T[] {
  const dir = sort.dir === 'asc' ? 1 : -1;
  const cmp = (a: T, b: T): number => {
    switch (sort.key) {
      case 'date':
        return a.shipment_date < b.shipment_date ? -1 : a.shipment_date > b.shipment_date ? 1 : 0;
      case 'products':
        return a.products_list.localeCompare(b.products_list);
      case 'type':
        return a.shipment_type.localeCompare(b.shipment_type);
      case 'warehouse':
        return (a.tracking_number ?? '').localeCompare(b.tracking_number ?? '');
      case 'unpaid':
        return a.unpaid_to_shipment - b.unpaid_to_shipment;
      default:
        return 0;
    }
  };
  return [...rows].sort((a, b) => cmp(a, b) * dir);
}

/**
 * Prefill each id with its remaining balance as a 2-decimal string.
 * Missing or non-positive balances become '0.00'.
 */
export function buildFullPrefill(
  ids: string[],
  balanceById: Record<string, number>,
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const id of ids) {
    const bal = balanceById[id] ?? 0;
    out[id] = bal > 0 ? bal.toFixed(2) : '0.00';
  }
  return out;
}
