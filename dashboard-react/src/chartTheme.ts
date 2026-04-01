/** Shared Recharts styling — references CSS design tokens for consistency */

export const CHART_GRID = {
  strokeDasharray: '3 3',
  stroke: 'var(--color-border-faint)',
} as const;

export const CHART_AXIS_TICK = {
  fill: 'var(--color-subtle)',
  fontSize: 'var(--text-caption)',
} as const;

export const CHART_AXIS_TICK_MD = {
  fill: 'var(--color-subtle)',
  fontSize: 'var(--text-caption)',
} as const;

export const CHART_AXIS_TICK_LG = {
  fill: 'var(--color-subtle)',
  fontSize: 'var(--text-caption)',
} as const;

export const CHART_TOOLTIP_STYLE = (fontSize = 10) => ({
  background: 'var(--color-card)',
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-sm)',
  fontSize,
  color: 'var(--color-text)',
});
