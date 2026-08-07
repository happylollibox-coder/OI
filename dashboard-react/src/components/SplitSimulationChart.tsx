// Presentation only. Renders the FBA/AWD split simulation the panel already
// computed via `fbaAwdSplit.ts` + `splitChart.ts` — no stock or DOC
// arithmetic happens here. Visual idiom matches `StockProjectionChart` in
// ShipmentEngine.tsx (toggleable legend buttons, stepAfter lines, a custom
// tooltip, ReferenceLine thresholds), but grid/axis/tooltip chrome comes
// from `chartTheme.ts` so it stays theme-aware in both light and dark mode.
import { useState } from 'react';
import {
  ComposedChart, Bar, Line, XAxis, YAxis, Tooltip as RTooltip,
  ResponsiveContainer, CartesianGrid, ReferenceLine,
} from 'recharts';
import { CHART_GRID, CHART_AXIS_TICK, CHART_TOOLTIP_STYLE } from '../chartTheme';
import { fmt } from '../utils';
import type { SplitWeekRow } from '../splitChart';

// Data-series colors stay explicit hex, matching the other charts in this codebase.
const FBA_COLOR = '#06b6d4';
const AWD_COLOR = '#8b5cf6';
const DOC_COLOR = '#f59e0b';

export interface SplitSimulationChartProps {
  rows: SplitWeekRow[];
  targetDoc: number;
  /** When set, shows an OOS warning in the header — the caller decides if/when FBA runs dry. */
  oosLabel?: string;
}

/** Toggleable legend chip, same idiom as StockProjectionChart's LegendBtn. */
function LegendBtn({ active, color, label, onClick }: { active: boolean; color: string; label: string; onClick: () => void }) {
  return (
    <button onClick={onClick}
      className="inline-flex items-center gap-1 transition-opacity cursor-pointer"
      style={{ opacity: active ? 1 : 0.35 }}
      title={active ? `Click to hide ${label}` : `Click to show ${label}`}>
      <span className="w-2 h-2 rounded-sm" style={{ background: color }} />
      <span>{label}</span>
    </button>
  );
}

/**
 * Declared outside the chart component (not inline in render) so Recharts
 * can clone it with fresh `active`/`label` props on every hover without
 * remounting it. `rows`/`showAwd`/`showDoc` ride along as ordinary props
 * rather than closures.
 */
function SplitTooltip({ active, label, rows, showAwd, showDoc }: {
  active?: boolean; label?: string; rows: SplitWeekRow[]; showAwd: boolean; showDoc: boolean;
}) {
  if (!active) return null;
  const row = rows.find(r => r.weekLabel === label);
  if (!row) return null;
  return (
    <div className="text-[11px] space-y-1 p-2.5 rounded-lg shadow-lg" style={CHART_TOOLTIP_STYLE(11)}>
      <div className="font-bold text-[color:var(--color-text)]">{row.weekLabel}</div>
      <div style={{ color: FBA_COLOR }}>FBA sellable: {fmt(row.fbaStock)} units</div>
      {showAwd && <div style={{ color: AWD_COLOR }}>AWD reserve: {fmt(row.awdStock)} units</div>}
      {showDoc && (
        <div style={{ color: DOC_COLOR }}>
          FBA DOC: {row.docCapped ? `${fmt(row.fbaDoc)}+` : `${fmt(row.fbaDoc)}d`}
        </div>
      )}
      {row.arrivals > 0 && (
        <div style={{ color: 'var(--color-positive)' }}>
          Arrivals: +{fmt(row.arrivals)}
          {row.arrivalNote && <span className="text-muted ml-1">({row.arrivalNote})</span>}
        </div>
      )}
    </div>
  );
}

export function SplitSimulationChart({ rows, targetDoc, oosLabel }: SplitSimulationChartProps) {
  const [showAwd, setShowAwd] = useState(true);
  const [showDoc, setShowDoc] = useState(true);

  if (!rows.length) return null;

  return (
    <div className="mt-3">
      <div className="flex items-center justify-between mb-2">
        <h4 className="text-[11px] font-bold text-[color:var(--color-text)] opacity-80">FBA / AWD Simulation</h4>
        <div className="flex items-center gap-3 text-[9px] text-muted">
          <span className="inline-flex items-center gap-1" title="FBA sellable stock — always shown">
            <span className="w-2 h-2 rounded-sm" style={{ background: FBA_COLOR }} />
            <span>FBA Sellable</span>
          </span>
          <LegendBtn active={showAwd} color={AWD_COLOR} label="AWD Reserve" onClick={() => setShowAwd(v => !v)} />
          <LegendBtn active={showDoc} color={DOC_COLOR} label="FBA DOC" onClick={() => setShowDoc(v => !v)} />
          {oosLabel && (
            <span className="font-bold" style={{ color: 'var(--color-negative)' }}>⚠ OOS: {oosLabel}</span>
          )}
        </div>
      </div>
      <ResponsiveContainer width="100%" height={200}>
        <ComposedChart data={rows} margin={{ top: 5, right: 5, left: 5, bottom: 0 }}>
          <CartesianGrid {...CHART_GRID} vertical={false} />
          <XAxis
            dataKey="weekLabel"
            tick={CHART_AXIS_TICK}
            tickLine={false}
            axisLine={false}
            interval="preserveStartEnd"
          />
          <YAxis yAxisId="stock" tick={CHART_AXIS_TICK} tickLine={false} axisLine={false} domain={[0, 'auto']} width={40} />
          <YAxis
            yAxisId="doc" orientation="right" tick={CHART_AXIS_TICK} tickLine={false} axisLine={false}
            domain={[0, 'auto']} width={34} tickFormatter={(v: number) => `${v}d`}
          />
          <RTooltip content={<SplitTooltip rows={rows} showAwd={showAwd} showDoc={showDoc} />} cursor={{ fill: 'var(--color-border-faint)' }} />

          <ReferenceLine
            yAxisId="stock" y={0} stroke="var(--color-negative)" strokeWidth={1.5} strokeDasharray="4 4"
            label={{ value: 'OOS', position: 'right', fill: 'var(--color-negative)', fontSize: 9 }}
          />
          <ReferenceLine
            yAxisId="doc" y={targetDoc} ifOverflow="extendDomain" stroke="var(--color-warning)" strokeWidth={1.5} strokeDasharray="4 4"
            label={{ value: `${targetDoc}d DOC`, position: 'insideTopLeft', fill: 'var(--color-warning)', fontSize: 9, offset: 5 }}
          />

          {showAwd && (
            <Bar yAxisId="stock" dataKey="awdStock" name="AWD Reserve" fill={AWD_COLOR} opacity={0.3} barSize={8} radius={[2, 2, 0, 0]} />
          )}

          <Line
            yAxisId="stock" dataKey="fbaStock" name="FBA Sellable" type="stepAfter"
            stroke={FBA_COLOR} strokeWidth={2} dot={false} activeDot={{ r: 3, fill: FBA_COLOR }}
          />

          {showDoc && (
            <Line
              yAxisId="doc" dataKey="fbaDoc" name="FBA DOC" type="stepAfter"
              stroke={DOC_COLOR} strokeWidth={1.5} strokeDasharray="4 2" dot={false} activeDot={{ r: 3, fill: DOC_COLOR }}
            />
          )}
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}
