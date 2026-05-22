/**
 * SeasonalReferenceLines — renders vertical phase lines on Recharts trend charts.
 *
 * For each gift_season holiday whose phases overlap the chart's date range,
 * draws lines for:
 *   - Pre-Peak  📋 (green)  = 4 weeks before peak_start (pre_season_start)
 *   - Boost     🔥 (amber)  = 2 weeks before peak_start
 *   - Peak      🎄 (red)    = peak_start (pre_season_start — selling period begins)
 *   - Peak End  ✅ (blue)   = holiday_date − 2 days (too late to ship)
 *
 * Usage: place `<SeasonalReferenceLines ... />` inside any Recharts chart component.
 */
import { ReferenceLine } from 'recharts';
import type { HolidayRow } from '../types';

interface SeasonalReferenceLinesProps {
  /** All holidays from data.holidays */
  holidays: HolidayRow[];
  /** The x-axis tick labels currently displayed on the chart (date strings like '2026-03-01' or 'Mar 1') */
  xLabels: string[];
  /** Optional: y-axis ID if chart has multiple axes. Defaults to 'left'. */
  yAxisId?: string;
}

/** Map month abbreviation → number */
const MON: Record<string, string> = { Jan:'01',Feb:'02',Mar:'03',Apr:'04',May:'05',Jun:'06',Jul:'07',Aug:'08',Sep:'09',Oct:'10',Nov:'11',Dec:'12' };

/**
 * Normalise any label format to YYYY-MM-DD for matching.
 * Handles: '2026-03-15', 'Mar 15', 'Mar 2026', '3/15', 'W12 2026', etc.
 */
function normDate(label: string): string | null {
  if (!label) return null;
  // Already ISO: 2026-03-15 (at least YYYY-MM-DD)
  if (/^\d{4}-\d{2}-\d{2}/.test(label)) return label.slice(0, 10);
  // Week range: "Mar 1 – 7" or "Dec 28 – Jan 3" (use start date)
  const mRange = label.match(/^([A-Z][a-z]{2})\s+(\d{1,2})\s*[–—-]\s*(?:[A-Z][a-z]{2}\s+)?\d{1,2}(?:,?\s*(\d{4}))?$/);
  if (mRange) {
    const yr = mRange[3] || new Date().getFullYear().toString();
    return `${yr}-${MON[mRange[1]] || '01'}-${mRange[2].padStart(2, '0')}`;
  }
  // "Mar 15", "Mar 15, 2026"
  const m1 = label.match(/^([A-Z][a-z]{2})\s+(\d{1,2})(?:,?\s*(\d{4}))?$/);
  if (m1) {
    const yr = m1[3] || new Date().getFullYear().toString();
    return `${yr}-${MON[m1[1]] || '01'}-${m1[2].padStart(2, '0')}`;
  }
  // "Mar 2026" (monthly)
  const m2 = label.match(/^([A-Z][a-z]{2})\s+(\d{4})$/);
  if (m2) return `${m2[2]}-${MON[m2[1]] || '01'}-01`;
  // Week label "W12 2026" — approximate to week start
  const m3 = label.match(/^W(\d+)\s+(\d{4})$/);
  if (m3) {
    const d = new Date(Number(m3[2]), 0, 1 + (Number(m3[1]) - 1) * 7);
    return d.toISOString().slice(0, 10);
  }
  // "2026-03" (month key only)
  if (/^\d{4}-\d{2}$/.test(label)) return label + '-01';
  return null;
}

/** Find the closest matching x-axis label for a given ISO date */
function findClosestLabel(targetDate: string, xLabels: string[]): string | null {
  if (!targetDate || xLabels.length === 0) return null;
  const targetMs = new Date(targetDate).getTime();
  if (isNaN(targetMs)) return null;

  let bestLabel: string | null = null;
  let bestDist = Infinity;

  for (const label of xLabels) {
    const norm = normDate(label);
    if (!norm) continue;
    const labelMs = new Date(norm).getTime();
    if (isNaN(labelMs)) continue;
    const dist = Math.abs(labelMs - targetMs);
    if (dist < bestDist) {
      bestDist = dist;
      bestLabel = label;
    }
  }

  // Only match if within 14 days — avoids false matches for sparse charts
  if (bestDist > 14 * 86400000) return null;
  return bestLabel;
}

/** Helper: add N days to an ISO date string */
function addDaysToDate(isoDate: string, days: number): string {
  const ms = new Date(isoDate).getTime() + days * 86400000;
  return new Date(ms).toISOString().slice(0, 10);
}

/** Phase colors and styles */
const PHASE_STYLES = {
  pre_peak:   { stroke: '#22c55e', label: '📋', opacity: 0.6 },  // green  — preparation starts
  boost:      { stroke: '#f59e0b', label: '🔥', opacity: 0.6 },  // amber  — ramp up / boost
  peak:       { stroke: '#ef4444', label: '🎄', opacity: 0.7 },  // red    — peak selling begins
  peak_end:   { stroke: '#3b82f6', label: '✅', opacity: 0.6 },  // blue   — peak ended
} as const;

export function SeasonalReferenceLines({ holidays, xLabels, yAxisId = 'left' }: SeasonalReferenceLinesProps) {
  if (!holidays || holidays.length === 0 || xLabels.length === 0) return null;

  // Determine chart date range from x-axis labels
  const normLabels = xLabels.map(normDate).filter(Boolean) as string[];
  if (normLabels.length === 0) return null;
  const chartStart = normLabels[0];
  const chartEnd = normLabels[normLabels.length - 1];

  // Collect lines: for each holiday, compute phases and see if they fall within chart range
  const lines: { x: string; phase: keyof typeof PHASE_STYLES; holiday: string }[] = [];

  for (const h of holidays) {
    if (!h.holiday_date || !h.pre_season_start) continue;

    const peakStart = h.pre_season_start;   // peak selling period begins
    const holidayDate = h.holiday_date;      // the actual holiday

    // Phase dates (matching loadPeakFromCube business logic):
    //   Pre-peak:  4 weeks before peak_start
    //   Boost:     2 weeks before peak_start
    //   Peak:      peak_start (pre_season_start)
    //   Peak End:  holiday_date − 2 days (too late to ship)
    const prePeakDate = addDaysToDate(peakStart, -28);
    const boostDate = addDaysToDate(peakStart, -14);
    const peakEndDate = addDaysToDate(holidayDate, -2);

    const phases: { date: string; phase: keyof typeof PHASE_STYLES }[] = [
      { date: prePeakDate, phase: 'pre_peak' },
      { date: boostDate, phase: 'boost' },
      { date: peakStart, phase: 'peak' },
      { date: peakEndDate, phase: 'peak_end' },
    ];

    for (const p of phases) {
      // Skip if outside chart range
      if (p.date < chartStart || p.date > chartEnd) continue;
      const matchLabel = findClosestLabel(p.date, xLabels);
      if (matchLabel) {
        // Avoid duplicate lines at the same x position
        if (!lines.some(l => l.x === matchLabel && l.phase === p.phase)) {
          lines.push({ x: matchLabel, phase: p.phase, holiday: h.holiday_name || '' });
        }
      }
    }
  }

  if (lines.length === 0) return null;

  // Group lines by x position — merge multiple events at the same bar into one label
  const byX: Record<string, typeof lines> = {};
  for (const line of lines) {
    (byX[line.x] ??= []).push(line);
  }

  // Assign stagger index per unique x position to avoid vertical overlap
  const xPositions = Object.keys(byX);
  const staggerMap: Record<string, number> = {};
  xPositions.forEach((x, i) => { staggerMap[x] = i; });

  // Build merged lines: one ReferenceLine per unique x, combined label
  const merged = xPositions.map(x => {
    const group = byX[x];
    const primary = group[0];
    const style = PHASE_STYLES[primary.phase];
    const label = group.map(g => {
      const s = PHASE_STYLES[g.phase];
      const short = g.holiday.length > 6 ? g.holiday.slice(0, 5) + '..' : g.holiday;
      return `${s.label}${short}`;
    }).join(' ');
    return { x, style, label, stagger: staggerMap[x] };
  });

  return (
    <>
      {merged.map((line, i) => (
        <ReferenceLine
          key={`season-${i}`}
          yAxisId={yAxisId}
          x={line.x}
          stroke={line.style.stroke}
          strokeDasharray="4 3"
          strokeWidth={1.5}
          strokeOpacity={line.style.opacity}
          label={{
            value: line.label,
            position: 'top',
            fill: line.style.stroke,
            fontSize: 8,
            fontWeight: 600,
            dy: line.stagger % 2 === 0 ? 0 : -10,
          }}
        />
      ))}
    </>
  );
}

/**
 * Shorthand hook: compute the x-axis labels from trend data array.
 * Pass the same `dataKey` used for the XAxis.
 */
export function getXLabels(trendData: Record<string, unknown>[], dataKey: string = 'label'): string[] {
  return trendData.map(d => String(d[dataKey] ?? '')).filter(Boolean);
}
