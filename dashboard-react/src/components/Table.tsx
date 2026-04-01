import { useState, useMemo } from 'react';

interface Column<T> {
  key: string;
  label: string;
  align?: 'left' | 'right';
  mono?: boolean;
  render?: (row: T) => React.ReactNode;
  sortValue?: (row: T) => number | string;
}

export function DataTable<T>({ columns, data, maxHeight, onRowClick, expandRow }: {
  columns: Column<T>[];
  data: T[];
  maxHeight?: string;
  onRowClick?: (row: T, i: number) => void;
  expandRow?: (row: T) => React.ReactNode;
}) {
  const [sortCol, setSortCol] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [expanded, setExpanded] = useState<Set<number>>(new Set());

  const sorted = useMemo(() => {
    if (!sortCol) return data;
    const col = columns.find(c => c.key === sortCol);
    if (!col) return data;
    return [...data].sort((a, b) => {
      const va = col.sortValue ? col.sortValue(a) : (a as Record<string, unknown>)[col.key] as number;
      const vb = col.sortValue ? col.sortValue(b) : (b as Record<string, unknown>)[col.key] as number;
      if (typeof va === 'number' && typeof vb === 'number') return sortDir === 'asc' ? va - vb : vb - va;
      return sortDir === 'asc' ? String(va).localeCompare(String(vb)) : String(vb).localeCompare(String(va));
    });
  }, [data, sortCol, sortDir, columns]);

  const handleSort = (key: string) => {
    if (sortCol === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortCol(key); setSortDir('desc'); }
  };

  const toggleExpand = (i: number) => {
    setExpanded(prev => {
      const next = new Set(prev);
      next.has(i) ? next.delete(i) : next.add(i);
      return next;
    });
  };

  if (!data.length) {
    return (
      <div className="border border-border rounded-lg bg-card p-12 text-center text-faint">
        <div className="text-3xl mb-2 opacity-50">📊</div>
        <div className="text-sm">No data available</div>
      </div>
    );
  }

  return (
    <div className="border border-border rounded-lg bg-card overflow-x-auto" style={maxHeight ? { maxHeight, overflowY: 'auto' } : undefined}>
      <table className="w-full border-collapse text-xs">
        <thead>
          <tr>
            {columns.map(col => (
              <th
                key={col.key}
                onClick={() => handleSort(col.key)}
                className={`bg-inset text-subtle text-left px-3 py-2.5 font-semibold text-[10px] uppercase tracking-wider border-b border-border whitespace-nowrap cursor-pointer select-none sticky top-0 z-[1] transition-colors hover:text-text ${col.align === 'right' ? 'text-right' : ''}`}
              >
                {col.label}
                {sortCol === col.key && <span className="ml-1 text-blue-400">{sortDir === 'asc' ? '↑' : '↓'}</span>}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {sorted.map((row, i) => (
            <>
              <tr
                key={i}
                onClick={() => {
                  if (expandRow) toggleExpand(i);
                  onRowClick?.(row, i);
                }}
                className={`border-b border-border-faint last:border-b-0 hover:bg-white/[.02] transition-colors ${onRowClick || expandRow ? 'cursor-pointer' : ''}`}
              >
                {columns.map(col => (
                  <td
                    key={col.key}
                    className={`px-3 py-2 ${col.align === 'right' ? 'text-right' : ''} ${col.mono ? 'font-mono text-[11px] font-medium' : ''}`}
                  >
                    {col.render ? col.render(row) : String((row as Record<string, unknown>)[col.key] ?? '--')}
                  </td>
                ))}
              </tr>
              {expandRow && expanded.has(i) && (
                <tr key={`exp-${i}`}>
                  <td colSpan={columns.length} className="p-0">
                    <div className="px-3.5 py-2.5 bg-inset text-[11px] text-subtle leading-relaxed">
                      {expandRow(row)}
                    </div>
                  </td>
                </tr>
              )}
            </>
          ))}
        </tbody>
      </table>
    </div>
  );
}
