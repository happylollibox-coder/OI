import { useState, useMemo } from 'react';
import { ChevronDown } from 'lucide-react';

export interface MeasureDef {
  id: string;
  label: string;
  tip?: string;
  defaultVisible?: boolean;
  /** Group for display in selector (e.g. 'Ads', 'SQP', 'PnL', 'Info') */
  group?: string;
}

const STORAGE_PREFIX = 'oi_table_measures_';

function loadSelection(tableId: string, measureIds: string[], defaults: Record<string, boolean>): Set<string> {
  try {
    const raw = localStorage.getItem(STORAGE_PREFIX + tableId);
    if (raw) {
      const arr = JSON.parse(raw) as string[];
      const saved = new Set(arr.filter((id: string) => measureIds.includes(id)));
      if (saved.size > 0) return saved;
    }
  } catch {
    /* ignore */
  }
  return new Set(measureIds.filter(id => defaults[id] !== false));
}

function saveSelection(tableId: string, selected: Set<string>) {
  try {
    localStorage.setItem(STORAGE_PREFIX + tableId, JSON.stringify([...selected]));
  } catch {
    /* ignore */
  }
}

export function MeasureSelector({
  tableId,
  measures,
  selected,
  onSelectedChange,
  className = '',
  buttonLabel = 'Columns',
}: {
  tableId: string;
  measures: MeasureDef[];
  selected: Set<string>;
  onSelectedChange: (next: Set<string>) => void;
  className?: string;
  buttonLabel?: string;
}) {
  const [open, setOpen] = useState(false);
  const defaults = useMemo(() => Object.fromEntries(measures.map(m => [m.id, m.defaultVisible !== false])), [measures]);
  const measureIds = useMemo(() => measures.map(m => m.id), [measures]);

  const toggle = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) {
      if (next.size > 1) next.delete(id);
    } else {
      next.add(id);
    }
    onSelectedChange(next);
    saveSelection(tableId, next);
  };

  const selectAll = () => {
    const next = new Set(measureIds);
    onSelectedChange(next);
    saveSelection(tableId, next);
  };

  const resetDefaults = () => {
    const next = new Set(measureIds.filter(id => defaults[id]));
    onSelectedChange(next);
    saveSelection(tableId, next);
  };

  const groupedMeasures = useMemo(() => {
    const groups: Record<string, MeasureDef[]> = {};
    measures.forEach(m => {
      const g = m.group || 'Other';
      if (!groups[g]) groups[g] = [];
      groups[g].push(m);
    });
    const order = ['Info', 'PnL', 'Ads', 'SQP', 'Other'];
    const sorted = order.filter(g => groups[g]?.length).concat(Object.keys(groups).filter(g => !order.includes(g)));
    return sorted.map(g => ({ group: g, items: groups[g] }));
  }, [measures]);

  return (
    <div className={`relative ${className}`}>
      <button
        type="button"
        onClick={() => setOpen(o => !o)}
        className="flex items-center gap-1 px-2 py-1 rounded border border-border hover:border-border-strong text-[10px] text-subtle hover:text-muted transition-colors"
      >
        <span>{buttonLabel}</span>
        <ChevronDown size={10} className={open ? 'rotate-180' : ''} />
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} aria-hidden />
          <div className="absolute right-0 top-full mt-1 z-50 min-w-[200px] max-h-[70vh] overflow-y-auto py-1 rounded-lg border border-border bg-card shadow-xl">
            <div className="px-2 py-1 border-b border-border text-[9px] uppercase text-faint font-semibold">Columns</div>
            {groupedMeasures.map(({ group, items }) => (
              <div key={group}>
                <div className="px-2 py-1 mt-1 first:mt-0 text-[9px] uppercase text-zinc-500 font-semibold border-b border-border">{group}</div>
                {items.map(m => (
                  <label key={m.id} className="flex items-center gap-2 px-2 py-1.5 hover:bg-white/[.03] cursor-pointer">
                    <input
                      type="checkbox"
                      checked={selected.has(m.id)}
                      onChange={() => toggle(m.id)}
                      className="rounded border-border"
                    />
                    <span className="text-[11px]">{m.label}</span>
                  </label>
                ))}
              </div>
            ))}
            <div className="border-t border-border mt-1 pt-1 px-2 flex gap-1 sticky bottom-0 bg-card">
              <button type="button" onClick={selectAll} className="text-[10px] text-blue-400 hover:underline">
                All
              </button>
              <button type="button" onClick={resetDefaults} className="text-[10px] text-faint hover:underline">
                Reset
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

export function useMeasureSelection(tableId: string, measures: MeasureDef[]): [Set<string>, (next: Set<string>) => void] {
  const defaults = useMemo(() => Object.fromEntries(measures.map(m => [m.id, m.defaultVisible !== false])), [measures]);
  const measureIds = useMemo(() => measures.map(m => m.id), [measures]);
  const [selected, setSelected] = useState<Set<string>>(() => loadSelection(tableId, measureIds, defaults));
  return [selected, setSelected];
}
