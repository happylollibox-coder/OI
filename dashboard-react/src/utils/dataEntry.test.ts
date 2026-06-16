import { describe, it, expect, vi, beforeEach } from 'vitest';
import * as api from './apiFetch';
import { dataEntry } from './dataEntry';

describe('dataEntry client', () => {
  beforeEach(() => vi.restoreAllMocks());

  it('getPO calls GET /api/po/<id> and returns parsed json', async () => {
    const spy = vi.spyOn(api, 'apiFetch').mockResolvedValue(
      new Response(JSON.stringify({ po: { purchase_order_id: 'PO_1' }, product_lines: [], payments: [], shipments: [] }), { status: 200 }),
    );
    const res = await dataEntry.getPO('PO_1');
    expect(spy).toHaveBeenCalledWith('/api/po/PO_1', expect.objectContaining({ method: 'GET' }));
    expect(res.po.purchase_order_id).toBe('PO_1');
  });

  it('createPO posts JSON body to /api/po', async () => {
    const spy = vi.spyOn(api, 'apiFetch').mockResolvedValue(
      new Response(JSON.stringify({ success: true, po_id: 'PO_2' }), { status: 200 }),
    );
    await dataEntry.createPO({ order_date: '2026-06-12', manufacturer_name: 'SYLVIA', product_lines: [{ product_id: 5, quantity: 10, total_amount: 100 }] });
    const [, init] = spy.mock.calls[0];
    expect(init?.method).toBe('POST');
    expect(JSON.parse(init?.body as string).manufacturer_name).toBe('SYLVIA');
  });

  it('throws normalized error on non-ok with {error}', async () => {
    vi.spyOn(api, 'apiFetch').mockResolvedValue(new Response(JSON.stringify({ error: 'bad' }), { status: 400 }));
    await expect(dataEntry.deletePO('PO_x')).rejects.toThrow('bad');
  });

  it('throws normalized error when body has success:false', async () => {
    vi.spyOn(api, 'apiFetch').mockResolvedValue(new Response(JSON.stringify({ success: false, error: 'nope' }), { status: 200 }));
    await expect(dataEntry.addPOLine('PO_1', { product_id: 1, quantity: 1, total_amount: 1 })).rejects.toThrow('nope');
  });

  it('encodes path ids', async () => {
    const spy = vi.spyOn(api, 'apiFetch').mockResolvedValue(new Response(JSON.stringify({ success: true }), { status: 200 }));
    await dataEntry.deletePO('PO/with space');
    expect(spy).toHaveBeenCalledWith('/api/po/PO%2Fwith%20space', expect.objectContaining({ method: 'DELETE' }));
  });
});

describe('dataEntry shipments', () => {
  beforeEach(() => vi.restoreAllMocks());

  it('getShipment calls GET /api/shipment/<id> and returns parsed json', async () => {
    const spy = vi.spyOn(api, 'apiFetch').mockResolvedValue(
      new Response(JSON.stringify({ shipment_id: 'SHP_1', shipment_date: '2026-06-01', lines: [] }), { status: 200 }),
    );
    const res = await dataEntry.getShipment('SHP_1');
    expect(spy).toHaveBeenCalledWith('/api/shipment/SHP_1', expect.objectContaining({ method: 'GET' }));
    expect((res as Record<string, unknown>).shipment_id).toBe('SHP_1');
  });

  it('createShipment posts JSON body to /api/shipments', async () => {
    const spy = vi.spyOn(api, 'apiFetch').mockResolvedValue(
      new Response(JSON.stringify({ success: true, shipment_id: 'SHP_2' }), { status: 200 }),
    );
    await dataEntry.createShipment({
      shipment_date: '2026-06-01',
      shipment_type: 'SEA',
      deliverer: 'DHL',
      cost_shipped: 500,
      lines: [{ purchase_order_id: 'PO_1', product_id: 1, quantity: 10 }],
    });
    const [, init] = spy.mock.calls[0];
    expect(init?.method).toBe('POST');
    expect(JSON.parse(init?.body as string).shipment_type).toBe('SEA');
  });

  it('updateShipmentLine calls PUT /api/shipment/<id>/lines/<line_id> with body', async () => {
    const spy = vi.spyOn(api, 'apiFetch').mockResolvedValue(
      new Response(JSON.stringify({ success: true }), { status: 200 }),
    );
    await dataEntry.updateShipmentLine('SHP_1', 'SHL_1', { quantity_shipped: 5 });
    const [url, init] = spy.mock.calls[0];
    expect(url).toBe('/api/shipment/SHP_1/lines/SHL_1');
    expect(init?.method).toBe('PUT');
    expect(JSON.parse(init?.body as string).quantity_shipped).toBe(5);
  });

  it('deleteShipment calls DELETE /api/shipment/<id>', async () => {
    const spy = vi.spyOn(api, 'apiFetch').mockResolvedValue(
      new Response(JSON.stringify({ success: true }), { status: 200 }),
    );
    await dataEntry.deleteShipment('SHP_1');
    expect(spy).toHaveBeenCalledWith('/api/shipment/SHP_1', expect.objectContaining({ method: 'DELETE' }));
  });

  it('throws normalized error on non-ok with {error}', async () => {
    vi.spyOn(api, 'apiFetch').mockResolvedValue(new Response(JSON.stringify({ error: 'not found' }), { status: 404 }));
    await expect(dataEntry.getShipment('SHP_x')).rejects.toThrow('not found');
  });

  it('encodes shipment id with slash and space', async () => {
    const spy = vi.spyOn(api, 'apiFetch').mockResolvedValue(
      new Response(JSON.stringify({ success: true }), { status: 200 }),
    );
    await dataEntry.deleteShipment('SHP/with space');
    expect(spy).toHaveBeenCalledWith('/api/shipment/SHP%2Fwith%20space', expect.objectContaining({ method: 'DELETE' }));
  });
});
