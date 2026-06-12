import type { ChartMeasureId } from './types';
import { fM, fP, fR, fOrd, fShort, fCpc } from '../utils';

export const CHART_MEASURE_META: Record<ChartMeasureId, {
  label: string;
  fmt: (v: number) => string;
  fmtShort?: (v: number) => string;
  color: string;
}> = {
  spend:      { label: 'Spend',      fmt: v => fM(v),    fmtShort: v => '$' + fShort(v), color: '#ef4444' },
  sales:      { label: 'Sales',      fmt: v => fM(v),    fmtShort: v => '$' + fShort(v), color: '#3b82f6' },
  orders:     { label: 'Orders',     fmt: v => fOrd(v),  fmtShort: v => fShort(v),        color: '#06b6d4' },
  conv_rate:  { label: 'Conv%',      fmt: v => fP(v),    fmtShort: v => fShort(v) + '%',  color: '#8b5cf6' },
  net_roas:   { label: 'Ads ROAS',   fmt: v => fR(v),    fmtShort: v => fShort(v) + 'x',  color: '#a855f7' },
  organic_pct: { label: 'Organic %', fmt: v => fP(v),    fmtShort: v => fShort(v) + '%',   color: '#10b981' },
  cpc:         { label: 'Ads CPC',   fmt: v => fCpc(v),   fmtShort: v => '$' + fShort(v),   color: '#f97316' },
};

export const ALL_CHART_MEASURES: ChartMeasureId[] = ['spend', 'sales', 'orders', 'conv_rate', 'net_roas', 'cpc', 'organic_pct'];
