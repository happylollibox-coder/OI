import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { PerformanceGrid } from './PerformanceGrid';
import type { ActionRow } from '../../types';

// Mirrors a real budget row (BOX-SP/BROAD): Q4 peak (1.4×) beats LY peak (1.11×).
const row = {
  ads_net_roas_1w: 0.75, ads_orders_1w: 47, ads_cpc_1w: 0.51, ads_spend_1w: 1408.1, ads_clicks_1w: 1574,
  ads_net_roas_4w: 0.86, ads_orders_4w: 216, ads_cpc_4w: 0.5, ads_spend_4w: 5743.37, ads_clicks_4w: 6484,
  ly_net_roas: 1.11, ly_orders: 301, ly_spend: 6176,
  q4_peak_net_roas: 1.4, q4_peak_orders: 1199, q4_peak_spend: 19632,
} as unknown as ActionRow;

describe('PerformanceGrid', () => {
  it('renders the 1w/4w/Peak columns and the metric rows', () => {
    render(<PerformanceGrid action={row} />);
    ['1w', '4w', 'Peak', 'ROAS', 'Orders', 'CPC', 'Spend', 'Clicks'].forEach(t =>
      expect(screen.getByText(t)).toBeTruthy());
  });

  it('shows the 1w ROAS and picks the stronger peak (Q4 1.40×)', () => {
    render(<PerformanceGrid action={row} />);
    expect(screen.getByText('0.75×')).toBeTruthy();
    expect(screen.getByText('1.40×')).toBeTruthy();
  });

  it('renders an em-dash where Q4 peak has no clicks/cpc', () => {
    render(<PerformanceGrid action={row} />);
    expect(screen.getAllByText('—').length).toBeGreaterThan(0);
  });
});
