import { useState, useCallback, useEffect } from 'react';
import type { BusinessConclusion } from '../types';

const KEY = 'hl_business_conclusions';
const API = '/api/conclusions';

function loadFromStorage(): BusinessConclusion[] {
  try { return JSON.parse(localStorage.getItem(KEY) || '[]'); } catch { return []; }
}

function saveToStorage(arr: BusinessConclusion[]) {
  localStorage.setItem(KEY, JSON.stringify(arr));
}

async function fetchApi<T>(url: string, opts?: RequestInit): Promise<T> {
  const r = await fetch(url, { ...opts, headers: { 'Content-Type': 'application/json', ...opts?.headers } });
  if (!r.ok) throw new Error(r.statusText);
  return r.json();
}

export function useConclusions() {
  const [conclusions, setConclusions] = useState<BusinessConclusion[]>(loadFromStorage);
  const [useApi, setUseApi] = useState(false);

  useEffect(() => {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 2000);
    fetch(API, { signal: ctrl.signal }).then(r => { if (r.ok) setUseApi(true); }).catch(() => {}).finally(() => clearTimeout(t));
  }, []);

  useEffect(() => {
    if (useApi) {
      fetchApi<BusinessConclusion[]>(API).then(setConclusions).catch(() => setConclusions(loadFromStorage()));
    }
  }, [useApi]);

  const add = useCallback((c: Omit<BusinessConclusion, 'id' | 'created_at' | 'status'>) => {
    const full: BusinessConclusion = {
      ...c,
      id: 'bc_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6),
      created_at: new Date().toISOString().slice(0, 10),
      status: 'active',
    };
    if (useApi) {
      fetchApi<BusinessConclusion>(API, { method: 'POST', body: JSON.stringify(c) })
        .then((created) => setConclusions(prev => [...prev, { ...full, ...created }]))
        .catch(() => { const next = [...loadFromStorage(), full]; saveToStorage(next); setConclusions(next); });
    } else {
      const next = [...loadFromStorage(), full];
      saveToStorage(next);
      setConclusions(next);
    }
  }, [useApi]);

  const remove = useCallback((id: string) => {
    if (useApi) {
      fetchApi(`${API}/${id}`, { method: 'DELETE' })
        .then(() => setConclusions(prev => prev.filter(c => c.id !== id)))
        .catch(() => { const next = loadFromStorage().filter(c => c.id !== id); saveToStorage(next); setConclusions(next); });
    } else {
      const next = loadFromStorage().filter(c => c.id !== id);
      saveToStorage(next);
      setConclusions(next);
    }
  }, [useApi]);

  const archive = useCallback((id: string) => {
    const arr = loadFromStorage();
    const item = arr.find(x => x.id === id);
    if (!item) return;
    const status = item.status === 'active' ? 'archived' : 'active';
    if (useApi) {
      fetchApi(`${API}/${id}`, { method: 'PATCH', body: JSON.stringify({ status }) })
        .then(() => setConclusions(prev => prev.map(c => c.id === id ? { ...c, status } : c)))
        .catch(() => { item.status = status; saveToStorage(arr); setConclusions([...arr]); });
    } else {
      item.status = status;
      saveToStorage(arr);
      setConclusions([...arr]);
    }
  }, [useApi]);

  const active = conclusions.filter(c => c.status === 'active');
  const archived = conclusions.filter(c => c.status === 'archived');

  return { conclusions, active, archived, add, remove, archive };
}
