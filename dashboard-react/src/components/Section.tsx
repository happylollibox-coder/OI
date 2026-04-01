import type { ReactNode } from 'react';
import { FilterInfoIcon } from './FilterInfoIcon';

export function Section({
  title,
  count,
  filterItems,
  headerRight,
  children,
}: {
  title: string;
  count?: string;
  filterItems?: string[];
  headerRight?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="mb-6">
      <div className="flex items-center gap-2 text-sm font-bold mb-3 tracking-tight">
        {title}
        {count && <span className="text-[11px] text-subtle font-medium font-mono">{count}</span>}
        {filterItems && filterItems.length > 0 && <FilterInfoIcon items={filterItems} />}
        {headerRight && <div className="ml-auto">{headerRight}</div>}
      </div>
      {children}
    </div>
  );
}
