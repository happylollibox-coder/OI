import type { ReactNode } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import { FilterInfoIcon } from './FilterInfoIcon';

export function Section({
  title,
  count,
  filterItems,
  headerRight,
  children,
  collapsed,
  onToggle,
}: {
  title: string;
  count?: string;
  filterItems?: string[];
  headerRight?: ReactNode;
  children: ReactNode;
  collapsed?: boolean;
  onToggle?: () => void;
}) {
  const isCollapsible = onToggle !== undefined;
  return (
    <div className="mb-6 rounded-xl border border-border/30 bg-surface/50">
      <div className="flex items-center gap-2 text-sm font-bold px-4 py-3 tracking-tight border-b border-border/20">
        {isCollapsible ? (
          <button className="flex items-center gap-1.5 hover:opacity-80 transition-opacity" onClick={onToggle}>
            {collapsed ? <ChevronRight size={14} className="text-muted" /> : <ChevronDown size={14} className="text-muted" />}
            {title}
          </button>
        ) : title}
        {count && <span className="text-[11px] text-subtle font-medium font-mono">{count}</span>}
        {filterItems && filterItems.length > 0 && <FilterInfoIcon items={filterItems} />}
        {headerRight && <div className="ml-auto">{headerRight}</div>}
      </div>
      {!collapsed && <div className="px-4 py-3">{children}</div>}
    </div>
  );
}
