import { memo } from 'react';

/** Skeleton shimmer – pulse animation for loading states */
function Shimmer({ className = '', style }: { className?: string; style?: React.CSSProperties }) {
  return (
    <div
      className={`rounded-lg animate-pulse ${className}`}
      style={{
        background: 'var(--color-inset, #1e1e23)',
        ...style,
      }}
    />
  );
}

/** Header-like pills skeleton */
function HeaderPills() {
  return (
    <div className="flex items-center gap-4 px-4">
      {[80, 120, 90, 100, 60].map((w, i) => (
        <Shimmer key={i} className="h-6" style={{ width: w }} />
      ))}
    </div>
  );
}

/** KPI cards row skeleton */
function KpiCards() {
  return (
    <div className="flex gap-4 mb-6">
      {[1, 2, 3, 4, 5].map(i => (
        <div key={i} className="flex-1 rounded-xl border border-border p-4 space-y-2" style={{ background: 'var(--color-card)' }}>
          <Shimmer className="h-3 w-16" />
          <Shimmer className="h-7 w-24" />
          <Shimmer className="h-3 w-20" />
        </div>
      ))}
    </div>
  );
}

/** Table rows skeleton */
function TableRows({ rows = 5, cols = 8 }: { rows?: number; cols?: number }) {
  return (
    <div className="space-y-1.5">
      <div className="flex gap-3 mb-3">
        {Array.from({ length: cols }, (_, i) => (
          <Shimmer key={i} className="h-3 flex-1" />
        ))}
      </div>
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="flex gap-3">
          {Array.from({ length: cols }, (_, j) => (
            <Shimmer key={j} className="h-8 flex-1 rounded-md" />
          ))}
        </div>
      ))}
    </div>
  );
}

/** Chart area skeleton */
function ChartArea() {
  return (
    <div className="mb-6">
      <div className="flex gap-3 mb-4">
        {[1, 2, 3, 4].map((_, i) => (
          <Shimmer key={i} className="h-[180px]" style={{ width: `${100 / 4}%` }} />
        ))}
      </div>
    </div>
  );
}

/** Full-page skeleton matching HOME layout: header pills, KPI cards, chart area, table */
export const DashboardSkeleton = memo(function DashboardSkeleton() {
  return (
    <div className="space-y-5" role="status" aria-label="Loading dashboard">
      {/* Filter bar skeleton */}
      <div className="flex items-center gap-2.5 px-2 py-2 rounded-xl border border-border" style={{ background: 'var(--color-overlay)' }}>
        {[60, 80, 100, 80, 120, 60].map((w, i) => (
          <Shimmer key={i} className="h-6" style={{ width: w }} />
        ))}
      </div>

      {/* Summary bar skeleton */}
      <div className="flex items-center gap-6 px-4 py-2">
        {[120, 140, 130, 100, 90].map((w, i) => (
          <Shimmer key={i} className="h-4" style={{ width: w }} />
        ))}
      </div>

      <div className="rounded-xl border border-border p-6" style={{ background: 'var(--color-card)' }}>
        {/* KPI cards */}
        <KpiCards />

        {/* Chart area */}
        <ChartArea />

        {/* Table */}
        <TableRows rows={5} cols={10} />
      </div>
    </div>
  );
});

export { Shimmer, HeaderPills, KpiCards, TableRows, ChartArea };
