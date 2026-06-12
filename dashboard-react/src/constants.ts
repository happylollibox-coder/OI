import { fM, fP, fR, fOrd, fClk, fShort } from './utils';

export type TrendMeasure = 'sales' | 'ad_cost' | 'cogs' | 'net_profit' | 'net_roas' | 'orders' | 'units' | 'clicks' | 'sessions' | 'organic_pct' | 'payment';

export const MEASURE_META: Record<TrendMeasure, { label: string; fmt: (v: number) => string; fmtShort?: (v: number) => string; color: string }> = {
  sales:       { label: 'Sales',       fmt: v => fM(v),    fmtShort: v => '$' + fShort(v), color: '#3b82f6' },
  ad_cost:     { label: 'Ads Spend',   fmt: v => fM(v),    fmtShort: v => '$' + fShort(v), color: '#ef4444' },
  cogs:        { label: 'COGS',        fmt: v => fM(v),    fmtShort: v => '$' + fShort(v), color: '#f97316' },
  net_profit:  { label: 'Net Profit',  fmt: v => fM(v),    fmtShort: v => '$' + fShort(v), color: '#22c55e' },
  net_roas:    { label: 'Net ROAS',    fmt: v => fR(v),    fmtShort: v => fShort(v) + 'x',  color: '#a855f7' },
  orders:      { label: 'Orders',      fmt: v => fOrd(v),  fmtShort: v => fShort(v),        color: '#06b6d4' },
  units:       { label: 'Units',       fmt: v => fOrd(v),  fmtShort: v => fShort(v),        color: '#14b8a6' },
  clicks:      { label: 'Clicks',      fmt: v => fClk(v),  fmtShort: v => fShort(v),        color: '#8b5cf6' },
  sessions:    { label: 'Sessions',    fmt: v => v.toLocaleString(),                          color: '#64748b' },
  organic_pct: { label: 'Organic %',   fmt: v => fP(v),    fmtShort: v => fShort(v) + '%',  color: '#10b981' },
  payment:     { label: 'Payment',     fmt: v => fM(v),    fmtShort: v => '$' + fShort(v), color: '#38bdf8' },
};
