import type { CoachCrossSellRow, DoQueueItem } from '../../types';

export const CROSS_SELL_ACTION = 'ADD_CROSS_SELL_TARGET';

/**
 * Build the Do-queue item for one self-brand cross-sell pair.
 *
 * Pure + shared so the Actions page (dedupe via hasItem) and the DoPage
 * bulksheet generator agree on the exact payload, and so it is unit-testable.
 *
 *   product / asin = advertise_asin  — the product we will advertise (B)
 *   targeting      = asin="<target>" — the listing we product-target (A)
 *   search_term    = advertise_asin  — keeps each (target, advertise) pair unique
 *                    under hasItem(search_term, action, campaign, targeting),
 *                    which has no `product` field.
 *
 * No bids/budgets are fabricated here — those come from the PRODUCT_DEFENSE
 * template at bulksheet time (DoPage), per the coacher no-auto-fill rule.
 */
export function buildCrossSellQueueItem(row: CoachCrossSellRow): Omit<DoQueueItem, 'id' | 'addedAt'> {
  return {
    search_term: row.advertise_asin,
    action: CROSS_SELL_ACTION,
    campaign: '',
    campaign_id: '',
    ad_group_id: '',
    targeting: `asin="${row.target_asin}"`,
    keyword_id: '',
    match_type: 'PRODUCT_TARGETING',
    target_spend_8w: 0,
    target_orders_8w: row.cross_orders_30d,
    target_net_roas_8w: 0,
    current_bid: null,
    recommended_bid: null,
    campaign_type: 'SPONSORED_PRODUCTS',
    product: row.advertise_asin,
    asin: row.advertise_asin,
    spend: 0,
    orders: row.cross_orders_30d,
    cpc: 0,
    conv_rate: 0,
    source: 'COACH',
  };
}
