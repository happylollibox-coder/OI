import { describe, it, expect, vi } from 'vitest';
import { DatasetStore } from './datasetStore';
import type { DatasetName } from './datasetTypes';

const mkLoaders = (impl: Partial<Record<DatasetName, () => Promise<unknown>>>) =>
  impl as Record<DatasetName, () => Promise<unknown>>;

describe('DatasetStore', () => {
  it('loads a dataset once and exposes ready data', async () => {
    const fn = vi.fn().mockResolvedValue([1, 2, 3]);
    const store = new DatasetStore(mkLoaders({ summary: fn }));
    await store.ensure(['summary']);
    expect(store.getStatus('summary')).toBe('ready');
    expect(store.getData('summary')).toEqual([1, 2, 3]);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('skips already-ready datasets on re-ensure', async () => {
    const fn = vi.fn().mockResolvedValue([1]);
    const store = new DatasetStore(mkLoaders({ summary: fn }));
    await store.ensure(['summary']);
    await store.ensure(['summary']);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('dedupes concurrent in-flight requests', async () => {
    let resolve!: (v: unknown) => void;
    const fn = vi.fn().mockImplementation(() => new Promise(r => { resolve = r; }));
    const store = new DatasetStore(mkLoaders({ summary: fn }));
    const p1 = store.ensure(['summary']);
    const p2 = store.ensure(['summary']);
    resolve([9]);
    await Promise.all([p1, p2]);
    expect(fn).toHaveBeenCalledTimes(1);
    expect(store.getData('summary')).toEqual([9]);
  });

  it('on loader rejection sets error status + fallback []', async () => {
    const fn = vi.fn().mockRejectedValue(new Error('boom'));
    const store = new DatasetStore(mkLoaders({ summary: fn }));
    await store.ensure(['summary']);
    expect(store.getStatus('summary')).toBe('error');
    expect(store.getData('summary')).toEqual([]);
  });

  it('isPageReady true when all are ready or error', async () => {
    const ok = vi.fn().mockResolvedValue([1]);
    const bad = vi.fn().mockRejectedValue(new Error('x'));
    const store = new DatasetStore(mkLoaders({ summary: ok, peak: bad }));
    expect(store.isPageReady(['summary', 'peak'])).toBe(false);
    await store.ensure(['summary', 'peak']);
    expect(store.isPageReady(['summary', 'peak'])).toBe(true);
  });

  it('notifies subscribers on status change', async () => {
    const fn = vi.fn().mockResolvedValue([1]);
    const store = new DatasetStore(mkLoaders({ summary: fn }));
    const listener = vi.fn();
    store.subscribe(listener);
    await store.ensure(['summary']);
    expect(listener).toHaveBeenCalled();
  });
});
