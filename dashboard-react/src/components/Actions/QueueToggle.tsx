import { Plus, Check, X } from 'lucide-react';

interface Props {
  queued: boolean;
  onQueue: () => void;
  onUnqueue: () => void;
  size?: number;
}

export function QueueToggle({ queued, onQueue, onUnqueue, size = 13 }: Props) {
  if (queued) {
    return (
      <span className="inline-flex items-center gap-1">
        <Check size={size} className="text-emerald-400" aria-hidden />
        <button
          type="button"
          aria-label="unqueue"
          title="Remove from DO queue"
          onClick={onUnqueue}
          className="p-0.5 rounded text-faint hover:text-[var(--color-negative)] transition-colors"
        ><X size={size} /></button>
      </span>
    );
  }
  return (
    <button
      type="button"
      aria-label="queue"
      title="Add to DO queue"
      onClick={onQueue}
      className="p-0.5 rounded text-zinc-500 hover:text-[var(--color-text)] transition-colors"
    ><Plus size={size} /></button>
  );
}
