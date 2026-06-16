import { describe, it, expect } from 'vitest';
import { buildCrossSellQueueItem, CROSS_SELL_ACTION } from './crossSell';
import type { CoachCrossSellRow } from '../../types';

const row: CoachCrossSellRow = {
  target_asin: 'B0TARGET001',
  advertise_asin: 'B0ADVERT002',
  target_name: 'Lollibox Classic',
  advertise_name: 'LolliME Mini',
  target_parent: 'Lollibox',
  cross_orders_30d: 12,
  cross_sales_30d: 340.5,
  confidence: 'HIGH',
};

describe('buildCrossSellQueueItem', () => {
  it('emits a PRODUCT_DEFENSE-bound cross-sell payload', () => {
    const item = buildCrossSellQueueItem(row);
    expect(item.action).toBe(CROSS_SELL_ACTION);
    expect(item.action).toBe('ADD_CROSS_SELL_TARGET');
    expect(item.targeting).toBe('asin="B0TARGET001"');   // target listing (A)
    expect(item.product).toBe('B0ADVERT002');             // advertised product (B)
    expect(item.match_type).toBe('PRODUCT_TARGETING');
  });

  it('does not fabricate bids/budgets (coacher no-auto-fill rule)', () => {
    const item = buildCrossSellQueueItem(row);
    expect(item.current_bid).toBeNull();
    expect(item.recommended_bid).toBeNull();
  });

  it('keeps each (target, advertise) pair unique under hasItem dedupe', () => {
    // hasItem(search_term, action, campaign, targeting) has no product field,
    // so search_term must carry advertise_asin to distinguish pairs on one target.
    const item = buildCrossSellQueueItem(row);
    expect(item.search_term).toBe('B0ADVERT002');
  });
});
