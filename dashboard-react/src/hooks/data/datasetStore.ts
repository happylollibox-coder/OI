import type { DatasetName, Status } from './datasetTypes';
import { fallbackFor } from './datasetTypes';

type Entry = { status: Status; data: unknown };

export class DatasetStore {
  private entries = new Map<DatasetName, Entry>();
  private inflight = new Map<DatasetName, Promise<void>>();
  private listeners = new Set<() => void>();

  private loaders: Record<DatasetName, () => Promise<unknown>>;
  constructor(loaders: Record<DatasetName, () => Promise<unknown>>) {
    this.loaders = loaders;
  }

  getStatus(name: DatasetName): Status { return this.entries.get(name)?.status ?? 'idle'; }
  getData(name: DatasetName): unknown { return this.entries.get(name)?.data; }

  subscribe = (fn: () => void): (() => void) => {
    this.listeners.add(fn);
    return () => { this.listeners.delete(fn); };
  };

  private emit() { this.listeners.forEach(l => l()); }
  private set(name: DatasetName, status: Status, data: unknown) {
    this.entries.set(name, { status, data });
    this.emit();
  }

  ensure(names: DatasetName[]): Promise<void> {
    return Promise.all(names.map(n => this.ensureOne(n))).then(() => {});
  }

  private ensureOne(name: DatasetName): Promise<void> {
    const status = this.getStatus(name);
    if (status === 'ready' || status === 'error') return Promise.resolve();
    const existing = this.inflight.get(name);
    if (existing) return existing;

    this.set(name, 'loading', this.getData(name));
    const loader = this.loaders[name];
    const p = loader()
      .then(
        d => this.set(name, 'ready', d ?? fallbackFor(name)),
        err => { console.error(`[datasetStore] ${name} failed:`, err); this.set(name, 'error', fallbackFor(name)); },
      )
      .finally(() => { this.inflight.delete(name); });
    this.inflight.set(name, p);
    return p;
  }

  isPageReady(names: DatasetName[]): boolean {
    return names.every(n => { const s = this.getStatus(n); return s === 'ready' || s === 'error'; });
  }

  /** Names that have never been requested — used by idle prefetch. */
  idleDatasets(all: DatasetName[]): DatasetName[] {
    return all.filter(n => this.getStatus(n) === 'idle');
  }
}
