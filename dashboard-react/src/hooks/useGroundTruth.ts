import { useState, useCallback, useEffect } from 'react';
import type { GroundTruth } from '../types';

const GT_KEY = 'hl_ground_truths';
const API = '/api/ground-truths';

function loadFromStorage(): GroundTruth[] {
  try { return JSON.parse(localStorage.getItem(GT_KEY) || '[]'); } catch { return []; }
}

function saveToStorage(arr: GroundTruth[]) {
  localStorage.setItem(GT_KEY, JSON.stringify(arr));
}

async function fetchApi<T>(url: string, opts?: RequestInit): Promise<T> {
  const r = await fetch(url, { ...opts, headers: { 'Content-Type': 'application/json', ...opts?.headers } });
  if (!r.ok) throw new Error(r.statusText);
  return r.json();
}

export function useGroundTruth() {
  const [groundTruths, setGroundTruths] = useState<GroundTruth[]>(loadFromStorage);
  const [useApi, setUseApi] = useState(false);

  useEffect(() => {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 2000);
    fetch(API, { signal: ctrl.signal }).then(r => { if (r.ok) setUseApi(true); }).catch(() => {}).finally(() => clearTimeout(t));
  }, []);

  useEffect(() => {
    if (useApi) {
      const ctrl = new AbortController();
      const t = setTimeout(() => ctrl.abort(), 5000);
      fetch(API, { signal: ctrl.signal })
        .then(r => r.ok ? r.json() : Promise.reject(new Error('Not ok')))
        .then((data: GroundTruth[]) => setGroundTruths(Array.isArray(data) ? data : []))
        .catch(() => setGroundTruths(loadFromStorage()))
        .finally(() => clearTimeout(t));
    }
  }, [useApi]);

  const addGT = useCallback((gt: Omit<GroundTruth, 'id' | 'approved_at'>) => {
    const full: GroundTruth = {
      ...gt,
      id: 'gt_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6),
      approved_at: new Date().toISOString().slice(0, 10),
    };
    if (useApi) {
      fetchApi<GroundTruth>(API, { method: 'POST', body: JSON.stringify(gt) })
        .then((created) => setGroundTruths(prev => [...prev, { ...full, ...created }]))
        .catch(() => { const next = [...loadFromStorage(), full]; saveToStorage(next); setGroundTruths(next); });
    } else {
      const next = [...loadFromStorage(), full];
      saveToStorage(next);
      setGroundTruths(next);
    }
  }, [useApi]);

  const removeGT = useCallback((id: string) => {
    if (useApi) {
      fetchApi(`${API}/${id}`, { method: 'DELETE' })
        .then(() => setGroundTruths(prev => prev.filter(g => g.id !== id)))
        .catch(() => { const next = loadFromStorage().filter(g => g.id !== id); saveToStorage(next); setGroundTruths(next); });
    } else {
      const next = loadFromStorage().filter(g => g.id !== id);
      saveToStorage(next);
      setGroundTruths(next);
    }
  }, [useApi]);

  const matchAction = useCallback((a: { search_term?: string; experiment_id?: string; net_roas?: number; cpc?: number; conv_rate?: number }) => {
    const matches: { gt: GroundTruth; supported: boolean }[] = [];
    groundTruths.forEach(g => {
      if (g.keyword && a.search_term && g.keyword.toLowerCase() !== a.search_term.toLowerCase()) return;
      if (g.experiment_id && a.experiment_id && g.experiment_id !== a.experiment_id) return;
      let matched = false, supported = false;
      if (g.metric === 'net_roas' && a.net_roas != null) { matched = true; const ref = parseFloat(g.ref) || 1; if (g.op === '>=' && a.net_roas >= ref) supported = true; if (g.op === '<' && a.net_roas < ref) supported = true; }
      if (g.metric === 'cpc' && a.cpc != null) { matched = true; const ref = parseFloat(g.ref) || 1; if (g.op === '<=' && a.cpc <= ref) supported = true; if (g.op === '>' && a.cpc > ref) supported = true; }
      if (g.metric === 'conv_rate' && a.conv_rate != null) { matched = true; const ref = parseFloat(g.ref) || 1; if (g.op === '>=' && a.conv_rate >= ref) supported = true; if (g.op === '<' && a.conv_rate < ref) supported = true; }
      if (matched) matches.push({ gt: g, supported });
    });
    return matches;
  }, [groundTruths]);

  return { groundTruths, addGT, removeGT, matchAction };
}

export interface Observation {
  t: string;
  m: string;
  txt: string;
  good: boolean | null;
  val?: number;
  op?: string;
  ref?: string;
}

export interface WeekInsight {
  week: string;
  spend: number;
  orders: number;
  sales: number;
  organic: number;
  sessions: number;
  cvr: number;
  roas: number;
  orgP: number;
  obs: Observation[];
}

export function deriveInsights(expRows: { week_start: string; ads_spend: number; ads_orders: number; sessions: number; sales: number; organic_units: number; total_orders: number }[]): WeekInsight[] {
  const weeks = [...new Set(expRows.map(r => r.week_start))].sort();
  const insights: WeekInsight[] = [];
  for (let i = 0; i < weeks.length; i++) {
    const w = weeks[i], pw = weeks[i - 1];
    const cur = expRows.filter(r => r.week_start === w);
    const prev = pw ? expRows.filter(r => r.week_start === pw) : [];
    const cs = cur.reduce((a, r) => ({ sp: a.sp + (r.ads_spend || 0), or: a.or + (r.ads_orders || 0), ss: a.ss + (r.sessions || 0), sl: a.sl + (r.sales || 0), oo: a.oo + (r.organic_units || 0), to: a.to + (r.total_orders || 0) }), { sp: 0, or: 0, ss: 0, sl: 0, oo: 0, to: 0 });
    const ps = prev.length ? prev.reduce((a, r) => ({ sp: a.sp + (r.ads_spend || 0), or: a.or + (r.ads_orders || 0), ss: a.ss + (r.sessions || 0), sl: a.sl + (r.sales || 0), oo: a.oo + (r.organic_units || 0), to: a.to + (r.total_orders || 0) }), { sp: 0, or: 0, ss: 0, sl: 0, oo: 0, to: 0 }) : null;
    const cvr = cs.ss ? (cs.to / cs.ss * 100) : 0, roas = cs.sp ? (cs.sl - cs.sp) / cs.sp : 0, orgP = cs.to ? (cs.oo / cs.to * 100) : 0;
    const obs: Observation[] = [];
    if (ps) {
      const pCvr = ps.ss ? (ps.to / ps.ss * 100) : 0, pRoas = ps.sp ? (ps.sl - ps.sp) / ps.sp : 0;
      const dRoas = pRoas ? ((roas - pRoas) / Math.abs(pRoas) * 100) : 0;
      const dCvr = pCvr ? ((cvr - pCvr) / pCvr * 100) : 0;
      const dOrd = ps.to ? ((cs.to - ps.to) / ps.to * 100) : 0;
      if (Math.abs(dRoas) > 10) obs.push({ t: 'metric', m: 'net_roas', txt: `Net ROAS ${dRoas > 0 ? 'improved' : 'dropped'} ${Math.abs(dRoas).toFixed(0)}% (${pRoas.toFixed(2)}x → ${roas.toFixed(2)}x)`, good: dRoas > 0, val: roas, op: dRoas > 0 ? '>=' : '<', ref: roas.toFixed(2) });
      if (Math.abs(dCvr) > 10) obs.push({ t: 'metric', m: 'conv_rate', txt: `Conv rate ${dCvr > 0 ? 'improved' : 'dropped'} ${Math.abs(dCvr).toFixed(0)}% (${pCvr.toFixed(1)}% → ${cvr.toFixed(1)}%)`, good: dCvr > 0, val: cvr, op: dCvr > 0 ? '>=' : '<', ref: cvr.toFixed(1) });
      if (Math.abs(dOrd) > 15) obs.push({ t: 'metric', m: 'orders', txt: `Orders ${dOrd > 0 ? 'up' : 'down'} ${Math.abs(dOrd).toFixed(0)}% (${ps.to} ord → ${cs.to} ord)`, good: dOrd > 0, val: cs.to });
    }
    if (roas >= 1.5) obs.push({ t: 'threshold', m: 'net_roas', txt: `Strong ROAS at ${roas.toFixed(2)}x — profitable baseline`, good: true, val: roas, op: '>=', ref: roas.toFixed(2) });
    else if (roas < 0 && cs.sp > 5) obs.push({ t: 'threshold', m: 'net_roas', txt: `ROAS at ${roas.toFixed(2)}x — below break-even`, good: false, val: roas, op: '<', ref: '0' });
    if (orgP > 40) obs.push({ t: 'threshold', m: 'organic_pct', txt: `Healthy organic at ${orgP.toFixed(0)}% — ads driving halo`, good: true, val: orgP, op: '>=', ref: orgP.toFixed(0) });
    if (cvr > 0 && cvr < 1.5 && cs.sp > 10) obs.push({ t: 'threshold', m: 'conv_rate', txt: `Low conv rate ${cvr.toFixed(1)}% — check listing or targeting`, good: false, val: cvr, op: '<', ref: '1.5' });
    if (obs.length === 0 && cs.sp > 0) obs.push({ t: 'stable', m: 'overall', txt: 'Stable week — no significant changes detected', good: null });
    insights.push({ week: w, spend: cs.sp, orders: cs.to, sales: cs.sl, organic: cs.oo, sessions: cs.ss, cvr, roas, orgP, obs });
  }
  return insights;
}
