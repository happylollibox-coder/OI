import { describe, it, expect, vi, afterEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { parseTransitDays, parseBufferDays, DEFAULT_CONSTANTS, useShipmentConstants } from './useShipmentConstants';
import { apiFetch } from '../utils/apiFetch';

const lov = (value_id: string, attr1_value: string) => ({
  value_id, value_caption: value_id, is_default: false,
  attr1_name: 'SHIPMENT_DAYS', attr1_value,
});

describe('parseTransitDays', () => {
  it('maps value_id to numeric days', () => {
    const days = parseTransitDays([lov('FAST_SEA', '27'), lov('SLOW_SEA', '33'), lov('AWD_SLOW_SEA', '63')]);
    expect(days).toEqual({ FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63 });
  });

  it('skips entries with a non-numeric or missing value', () => {
    const days = parseTransitDays([lov('FAST_SEA', '27'), lov('BROKEN', 'soon'), { value_id: 'NOATTR', value_caption: '', is_default: false }]);
    expect(days).toEqual({ FAST_SEA: 27 });
  });

  it('returns an empty map for no rows', () => {
    expect(parseTransitDays([])).toEqual({});
  });
});

describe('parseBufferDays', () => {
  it('reads FBA_INBOUND_BUFFER_DAYS', () => {
    expect(parseBufferDays([lov('FBA_INBOUND_BUFFER_DAYS', '10'), lov('FBA_ARRIVAL_DEADLINE', '1205')])).toBe(10);
  });

  it('falls back to the default when absent', () => {
    expect(parseBufferDays([])).toBe(DEFAULT_CONSTANTS.fbaInboundBufferDays);
  });
});

vi.mock('../utils/apiFetch', () => ({ apiFetch: vi.fn() }));
const mockApiFetch = vi.mocked(apiFetch);
afterEach(() => { mockApiFetch.mockReset(); });

const jsonResponse = (body: unknown) => ({ json: async () => body }) as Response;

describe('useShipmentConstants', () => {
  it('resolves live transitDays and fbaInboundBufferDays on the happy path', async () => {
    mockApiFetch
      .mockResolvedValueOnce(jsonResponse([lov('FAST_SEA', '27'), lov('AWD_SLOW_SEA', '63')]))
      .mockResolvedValueOnce(jsonResponse([lov('FBA_INBOUND_BUFFER_DAYS', '10'), lov('FBA_ARRIVAL_DEADLINE', '1205')]));

    const { result } = renderHook(() => useShipmentConstants());

    await waitFor(() => expect(result.current.loaded).toBe(true));

    expect(result.current.error).toBeNull();
    expect(result.current.transitDays).toEqual({ FAST_SEA: 27, AWD_SLOW_SEA: 63 });
    expect(result.current.fbaInboundBufferDays).toBe(10);
  });

  it('keeps DEFAULT_CONSTANTS and stays not-loaded when the fetch rejects', async () => {
    mockApiFetch.mockRejectedValueOnce(new Error('network down'));

    const { result } = renderHook(() => useShipmentConstants());

    await waitFor(() => expect(result.current.error).not.toBeNull());

    expect(result.current.loaded).toBe(false);
    expect(result.current.transitDays).toEqual(DEFAULT_CONSTANTS.transitDays);
    expect(result.current.fbaInboundBufferDays).toBe(DEFAULT_CONSTANTS.fbaInboundBufferDays);
  });

  it('keeps DEFAULT_CONSTANTS and stays not-loaded on a non-array (error object) response body', async () => {
    mockApiFetch
      .mockResolvedValueOnce(jsonResponse({ error: 'lov_set not found' }))
      .mockResolvedValueOnce(jsonResponse([lov('FBA_INBOUND_BUFFER_DAYS', '10')]));

    const { result } = renderHook(() => useShipmentConstants());

    await waitFor(() => expect(result.current.error).not.toBeNull());

    expect(result.current.loaded).toBe(false);
    expect(result.current.transitDays).toEqual(DEFAULT_CONSTANTS.transitDays);
    expect(result.current.fbaInboundBufferDays).toBe(DEFAULT_CONSTANTS.fbaInboundBufferDays);
  });
});
