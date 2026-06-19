import { useState, useCallback, type ReactNode } from 'react';
import { ChevronRight, ChevronDown } from 'lucide-react';

const STORAGE_KEY = 'oi_actions_sections';

function loadCollapsed(id: string, fallback: boolean): boolean {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    const map = raw ? (JSON.parse(raw) as Record<string, boolean>) : {};
    return id in map ? map[id] : fallback;
  } catch { return fallback; }
}

function saveCollapsed(id: string, collapsed: boolean) {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    const map = raw ? (JSON.parse(raw) as Record<string, boolean>) : {};
    map[id] = collapsed;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(map));
  } catch { /* ignore */ }
}

interface Props {
  id: string;
  title: ReactNode;
  summary: ReactNode;
  queueableCount: number;
  queuedCount: number;
  onQueueAll?: () => void;
  onUnqueueAll?: () => void;
  defaultCollapsed?: boolean;
  children: ReactNode;
}

export function CollapsibleSection({
  id, title, summary, queueableCount, queuedCount, onQueueAll, onUnqueueAll,
  defaultCollapsed = true, children,
}: Props) {
  const [collapsed, setCollapsed] = useState(() => loadCollapsed(id, defaultCollapsed));
  const toggle = useCallback(() => setCollapsed(c => { const n = !c; saveCollapsed(id, n); return n; }), [id]);

  const queueDisabled = queueableCount - queuedCount <= 0;
  const unqueueDisabled = queuedCount <= 0;

  return (
    <div className="mb-3 rounded-lg border border-[var(--color-border)] bg-[var(--color-card)]">
      <div className="flex items-center gap-2 px-3 py-2">
        <button
          type="button"
          onClick={toggle}
          className="flex items-center gap-2 flex-1 min-w-0 text-left"
          aria-expanded={!collapsed}
        >
          {collapsed ? <ChevronRight size={14} className="text-faint shrink-0" />
                     : <ChevronDown size={14} className="text-faint shrink-0" />}
          <span className="text-[11px] font-bold uppercase tracking-wider text-[var(--color-text)] shrink-0">{title}</span>
          <span className="text-[10px] text-faint truncate">{summary}</span>
        </button>
        {onQueueAll && (
          <button
            type="button"
            disabled={queueDisabled}
            onClick={onQueueAll}
            className="text-[10px] px-2 py-1 rounded border border-[var(--color-border)] text-sky-400 disabled:opacity-40 disabled:cursor-not-allowed shrink-0"
          >Queue all</button>
        )}
        {onUnqueueAll && (
          <button
            type="button"
            disabled={unqueueDisabled}
            onClick={onUnqueueAll}
            className="text-[10px] px-2 py-1 rounded border border-[var(--color-border)] text-faint disabled:opacity-40 disabled:cursor-not-allowed shrink-0"
          >Unqueue all</button>
        )}
      </div>
      {!collapsed && <div className="px-3 pb-3">{children}</div>}
    </div>
  );
}
