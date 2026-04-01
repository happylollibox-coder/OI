import { Filter } from 'lucide-react';
import { Tip } from './Tooltip';

export function FilterInfoIcon({ items }: { items: string[] }) {
  const tooltipText =
    items.length === 0
      ? 'No filters'
      : `Filters on this section:\n${items.map(i => `• ${i}`).join('\n')}`;

  return (
    <Tip text={tooltipText} multiline>
      <span className="inline-flex items-center text-subtle hover:text-muted cursor-help transition-colors">
        <Filter className="w-3.5 h-3.5" strokeWidth={2} />
      </span>
    </Tip>
  );
}
