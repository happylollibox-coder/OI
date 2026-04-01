import React, { useState, useMemo } from 'react';
import type { DashboardData } from '../types';
import { useFilters } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { FilterInfoIcon } from '../components/FilterInfoIcon';
import { Badge } from '../components/Badge';
import { PageHeader } from '../components/PageHeader';
import { Empty } from '../components/Empty';
import { SortTh, useSort } from '../components/Tooltip';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';
import { usePageSummary } from '../components/PageSummaryBar';

const LOG_TABLE_COLUMNS: MeasureDef[] = [
  { id: 'change_date', label: 'Date', group: 'Info' },
  { id: 'experiment_id', label: 'Experiment', group: 'Info' },
  { id: 'change_type', label: 'Type', group: 'Info' },
  { id: 'field_changed', label: 'Field', group: 'Info' },
  { id: 'old_value', label: 'Old', group: 'Info' },
  { id: 'new_value', label: 'New', group: 'Info' },
  { id: 'reason', label: 'Reason', group: 'Info' },
];

const NK_TABLE_COLUMNS: MeasureDef[] = [
  { id: 'campaign_name', label: 'Campaign', group: 'Info' },
  { id: 'negative_keyword', label: 'Keyword', group: 'Info' },
  { id: 'spend_30d', label: 'Spend 30d', group: 'Ads' },
];

export function LogPage({ data }: { data: DashboardData }) {
  const { filters, setFilter } = useFilters();
  const logs = data.change_log || [];
  const nk = data.negative_keywords || [];
  const [typeFilter, setTypeFilter] = useState('all');

  const types = useMemo(() => [...new Set(logs.map(r => r.change_type).filter(Boolean))].sort(), [logs]);
  const exps = useMemo(() => [...new Set(logs.map(r => r.experiment_id).filter(Boolean))].sort(), [logs]);

  const filtered = useMemo(() => {
    let f = logs;
    if (typeFilter !== 'all') f = f.filter(r => r.change_type === typeFilter);
    if (filters.experiment) f = f.filter(r => r.experiment_id === filters.experiment);
    return f.slice(0, 100);
  }, [logs, typeFilter, filters.experiment]);
  const logSort = useSort('change_date');
  const nkSort = useSort('spend_30d');
  const [logCols, setLogCols] = useMeasureSelection('log_changelog', LOG_TABLE_COLUMNS);
  const [nkCols, setNkCols] = useMeasureSelection('log_negative_keywords', NK_TABLE_COLUMNS);
  const visibleLogCols = useMemo(() => LOG_TABLE_COLUMNS.filter(c => logCols.has(c.id)), [logCols]);
  const visibleNkCols = useMemo(() => NK_TABLE_COLUMNS.filter(c => nkCols.has(c.id)), [nkCols]);
  const logFilterItems = useMemo(
    () => formatSectionFilters(filters, typeFilter !== 'all' ? { Type: typeFilter } : undefined),
    [filters, typeFilter]
  );
  const nkFilterItems = useMemo(() => formatSectionFilters(filters), [filters]);

  usePageSummary({ title: 'Log', items: [{ label: 'Change Log', value: 'Active' }] });
  return (
    <div className="animate-in">
      <div className="flex items-center gap-2 mb-5">
        <PageHeader title="Change Log" subtitle="Recent changes" />
        {logFilterItems.length > 0 && <FilterInfoIcon items={logFilterItems} />}
        <div className="ml-auto"><MeasureSelector tableId="log_changelog" measures={LOG_TABLE_COLUMNS} selected={logCols} onSelectedChange={setLogCols} /></div>
      </div>

      <div className="flex gap-2 items-center flex-wrap p-2.5 bg-surface/50 backdrop-blur border border-border rounded-xl mb-3.5">
        <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold">Type</label>
        <select value={typeFilter} onChange={e => setTypeFilter(e.target.value)} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
          <option value="all">All</option>
          {types.map(t => <option key={t} value={t}>{t}</option>)}
        </select>
        <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold ml-2">Experiment</label>
        <select value={filters.experiment || 'all'} onChange={e => setFilter('experiment', e.target.value === 'all' ? null : e.target.value)} className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500">
          <option value="all">All</option>
          {exps.map(e => <option key={e} value={e}>{e}</option>)}
        </select>
      </div>

      {!filtered.length ? <Empty message="No changes" /> : (
        <div className="border border-border rounded-xl bg-card overflow-x-auto" style={{ maxHeight: '55vh', overflowY: 'auto' }}>
          <table className="w-full border-collapse text-xs">
            <thead>
              <tr>
                {visibleLogCols.map(c => (
                  <SortTh key={c.id} k={c.id} sort={logSort.sort} toggle={logSort.toggle} right={c.id === 'old_value' || c.id === 'new_value'}>{c.label}</SortTh>
                ))}
              </tr>
            </thead>
            <tbody>
              {logSort.sorted(filtered).map((r, i) => {
                const tc = r.change_type === 'bid_change' ? 'blue' : r.change_type === 'budget_change' ? 'green' : r.change_type === 'status_change' ? 'amber' : 'muted';
                const cells: Record<string, React.ReactNode> = {
                  change_date: <td key="change_date" className="px-3 py-2 font-mono whitespace-nowrap">{r.change_date || r.created_at || '--'}</td>,
                  experiment_id: <td key="experiment_id" className="px-3 py-2">{r.experiment_id || '--'}</td>,
                  change_type: <td key="change_type" className="px-3 py-2"><Badge variant={tc}>{r.change_type || '--'}</Badge></td>,
                  field_changed: <td key="field_changed" className="px-3 py-2">{r.field_changed || '--'}</td>,
                  old_value: <td key="old_value" className="px-3 py-2 font-mono max-w-[100px] overflow-hidden text-ellipsis">{r.old_value || '--'}</td>,
                  new_value: <td key="new_value" className="px-3 py-2 font-mono max-w-[100px] overflow-hidden text-ellipsis">{r.new_value || '--'}</td>,
                  reason: <td key="reason" className="px-3 py-2 text-[11px] text-subtle max-w-[180px]">{r.reason || '--'}</td>,
                };
                return (
                  <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                    {visibleLogCols.map(c => cells[c.id])}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Negative Keywords */}
      <div className="mt-6">
        <div className="flex items-center gap-2 text-sm font-bold mb-3">
          Negative Keywords
          {nkFilterItems.length > 0 && <FilterInfoIcon items={nkFilterItems} />}
          <div className="ml-auto"><MeasureSelector tableId="log_negative_keywords" measures={NK_TABLE_COLUMNS} selected={nkCols} onSelectedChange={setNkCols} /></div>
        </div>
        {!nk.length ? <Empty message="No data" /> : (
          <div className="border border-border rounded-xl bg-card overflow-x-auto" style={{ maxHeight: '36vh', overflowY: 'auto' }}>
            <table className="w-full border-collapse text-xs">
              <thead>
                <tr>
                  {visibleNkCols.map(c => (
                    <SortTh key={c.id} k={c.id} sort={nkSort.sort} toggle={nkSort.toggle} right={c.id === 'spend_30d'}>{c.label}</SortTh>
                  ))}
                </tr>
              </thead>
              <tbody>
                {nkSort.sorted(nk).slice(0, 100).map((r, i) => {
                  const ks = Object.keys(r);
                  const cells: Record<string, React.ReactNode> = {
                    campaign_name: <td key="campaign_name" className="px-3 py-2">{r.campaign_name || (r as unknown as Record<string, unknown>)[ks[0]] as string || '--'}</td>,
                    negative_keyword: <td key="negative_keyword" className="px-3 py-2">{r.negative_keyword || (r as unknown as Record<string, unknown>)[ks[1]] as string || '--'}</td>,
                    spend_30d: <td key="spend_30d" className="px-3 py-2 text-right font-mono">{r.spend_30d ?? (r as unknown as Record<string, unknown>)[ks[2]] ?? '--'}</td>,
                  };
                  return (
                    <tr key={i} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                      {visibleNkCols.map(c => cells[c.id])}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
