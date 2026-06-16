import { apiFetch } from './apiFetch';

async function json<T>(input: string, init: RequestInit = {}): Promise<T> {
  const res = await apiFetch(input, { headers: { 'Content-Type': 'application/json' }, ...init });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || (data && (data as Record<string, unknown>).success === false)) {
    const d = data as Record<string, unknown>;
    throw new Error((d && (d.error as string || d.message as string)) || `Request failed (${res.status})`);
  }
  return data as T;
}

export interface POLineInput { product_id: number; quantity: number; total_amount: number; }
export interface CreatePOInput {
  order_date: string; manufacturer_name: string; currency?: string;
  payment_status?: string; notes?: string; product_lines: POLineInput[];
}
export interface PODetail {
  po: Record<string, unknown>;
  product_lines: Record<string, unknown>[];
  payments: Record<string, unknown>[];
  shipments: Record<string, unknown>[];
}
export interface LovItem { value_id: string; value_caption: string; is_default: boolean; [k: string]: unknown; }

export interface Product {
  product_id: number;
  asin: string | null;
  product_name: string | null;
  display_name: string | null;
  sku: string | null;
  brand: string | null;
  manufacturer: string | null;
  parent_name: string | null;
  product_short_name: string | null;
}

export interface ShipmentLineInput {
  purchase_order_id: string;
  product_id: number;
  quantity: number;
  cartons?: number;
}

export interface CreateShipmentInput {
  shipment_date: string;
  shipment_type: string;
  deliverer: string;
  cost_shipped: number;
  amazon_commission?: number;
  kg_price?: number;
  tracking_number?: string;
  shipment_status?: string;
  notes?: string;
  is_paid?: boolean;
  paid_date?: string;
  lines: ShipmentLineInput[];
}

export interface ShipmentDetail {
  shipment_id: string;
  shipment_date: string;
  shipment_type: string;
  deliverer: string;
  cost_shipped: number;
  amazon_commission?: number;
  kg_price?: number;
  tracking_number?: string;
  shipment_status?: string;
  notes?: string;
  is_paid?: boolean;
  paid_date?: string;
  lines: Record<string, unknown>[];
  [k: string]: unknown;
}

export const dataEntry = {
  listOrders: () => json<Record<string, unknown>[]>('/api/orders', { method: 'GET' }),
  getPO: (id: string) => json<PODetail>(`/api/po/${encodeURIComponent(id)}`, { method: 'GET' }),
  createPO: (b: CreatePOInput) => json<{ po_id: string }>('/api/po', { method: 'POST', body: JSON.stringify(b) }),
  updatePOHeader: (id: string, b: Record<string, unknown>) =>
    json(`/api/po/${encodeURIComponent(id)}/header`, { method: 'POST', body: JSON.stringify(b) }),
  addPOLine: (id: string, b: POLineInput) =>
    json(`/api/po/${encodeURIComponent(id)}/lines`, { method: 'POST', body: JSON.stringify(b) }),
  updatePOLine: (id: string, productId: number, field: string, value: number) =>
    json(`/api/po/${encodeURIComponent(id)}/lines/${productId}`, { method: 'PUT', body: JSON.stringify({ field, value }) }),
  deletePOLine: (id: string, productId: number) =>
    json(`/api/po/${encodeURIComponent(id)}/lines/${productId}`, { method: 'DELETE' }),
  deletePO: (id: string) => json(`/api/po/${encodeURIComponent(id)}`, { method: 'DELETE' }),
  getLovs: () => json<Record<string, LovItem[]>>('/api/lov', { method: 'GET' }),
  listOtherPOs: () => json<Record<string, unknown>[]>('/api/other_po', { method: 'GET' }),
  createOtherPO: (b: Record<string, unknown>) => json<{ other_po_id: string }>('/api/other_po', { method: 'POST', body: JSON.stringify(b) }),
  deleteOtherPO: (id: string) => json(`/api/other_po/${encodeURIComponent(id)}`, { method: 'DELETE' }),
  listProducts: () => json<Product[]>('/api/products', { method: 'GET' }),
  getShipment: (id: string) => json<ShipmentDetail>(`/api/shipment/${encodeURIComponent(id)}`, { method: 'GET' }),
  createShipment: (b: CreateShipmentInput) => json<{ shipment_id: string }>('/api/shipments', { method: 'POST', body: JSON.stringify(b) }),
  updateShipmentHeader: (id: string, b: Record<string, unknown>) => json(`/api/shipment/${encodeURIComponent(id)}/update`, { method: 'POST', body: JSON.stringify(b) }),
  deleteShipment: (id: string) => json(`/api/shipment/${encodeURIComponent(id)}`, { method: 'DELETE' }),
  addShipmentLine: (id: string, b: { purchase_order_id: string; product_id: number; quantity_shipped: number }) => json<{ line_id: string }>(`/api/shipment/${encodeURIComponent(id)}/lines`, { method: 'POST', body: JSON.stringify(b) }),
  updateShipmentLine: (id: string, lineId: string, b: { quantity_shipped?: number; allocated_cost?: number }) => json(`/api/shipment/${encodeURIComponent(id)}/lines/${encodeURIComponent(lineId)}`, { method: 'PUT', body: JSON.stringify(b) }),
  deleteShipmentLine: (id: string, lineId: string) => json(`/api/shipment/${encodeURIComponent(id)}/lines/${encodeURIComponent(lineId)}`, { method: 'DELETE' }),
  getOpenPOs: async () => {
    // /api/open-pos returns { success, data: [...] } — unwrap to the array
    const r = await json<{ success?: boolean; data?: Record<string, unknown>[] }>('/api/open-pos', { method: 'GET' });
    return Array.isArray(r) ? r : (r.data ?? []);
  },
};
