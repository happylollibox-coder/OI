import { describe, it, expect } from 'vitest';
import {
  buildCompetitorSpRows, buildCompetitorSbRows,
  type CompetitorCtx, type CompetitorItem, type BulksheetRow,
} from './competitorBulksheet';

/* Regression suite for the three bulksheet mechanics that Amazon rejected in production
 * (Ori 2026-07-24). Each `describe` names the real failure it prevents. */

const baseCtx = (over: Partial<CompetitorCtx> = {}): CompetitorCtx => {
  const live = over.liveIds ?? new Map();
  return {
    spTemplate: { daily_budget: 10, bid_min: 0.25, product_page_pct: 200 },
    sbTemplate: { daily_budget: 10, bid_min: 0.25 },
    liveIds: new Map(),
    // "Live on Amazon" is exactly membership of liveIds here; the export tracks scaffolding
    // separately so a second ASIN of a NEW campaign still addresses it by name.
    isLiveOnAmazon: (name: string) => live.has(name.trim().toUpperCase()),
    scaffolded: new Set<string>(),
    videoAssetFor: () => 'amzn1.assetlibrary.asset1.abc:version_v1',
    portfolioFor: () => '41310184067669',
    skuFor: () => 'SKU-MINT',
    brandEntityId: 'ENTITY1QO3J3WCA4V66',
    brandName: 'Happy Lolli',
    startDate: '20260724',
    formatPTExpression: (t: string) => t,
    ...over,
  };
};

const item = (over: Partial<CompetitorItem> = {}): CompetitorItem => ({
  action: 'ADD_COMPETITOR_TARGET',
  campaign: 'ME-SP/PT (Competitors, Mint, A1)',
  ad_group_name: 'ME - Competitors Mint A1',
  targeting: 'asin="B0CL1YP5X3"',
  asin: 'B0F9X95K5H',
  product: 'Mint LolliME',
  recommended_bid: 2,
  ...over,
});

const entities = (rows: BulksheetRow[]) => rows.map(r => r.Entity);
const targetRow = (rows: BulksheetRow[]) => rows.find(r => r.Entity === 'Product Targeting')!;

describe('new campaign — full scaffold, addressed by name', () => {
  it('emits Campaign + Bidding Adjustment + Ad Group + Product Ad + Product Targeting', () => {
    const res = buildCompetitorSpRows(item(), baseCtx());
    expect(entities(res.spRows)).toEqual(
      ['Campaign', 'Bidding Adjustment', 'Ad Group', 'Product Ad', 'Product Targeting']);
  });

  it('uses the campaign NAME in the id columns (Amazon resolves it within the same sheet)', () => {
    const res = buildCompetitorSpRows(item(), baseCtx());
    const t = targetRow(res.spRows);
    expect(t['Campaign ID']).toBe('ME-SP/PT (Competitors, Mint, A1)');
    expect(t['Ad Group ID']).toBe('ME - Competitors Mint A1');
  });

  it('scaffolds only ONCE when several ASINs share a campaign', () => {
    const ctx = baseCtx();
    const a = buildCompetitorSpRows(item({ targeting: 'asin="B01"' }), ctx);
    const b = buildCompetitorSpRows(item({ targeting: 'asin="B02"' }), ctx);
    expect(entities(a.spRows)).toContain('Campaign');
    expect(entities(b.spRows)).toEqual(['Product Targeting']);
  });
});

describe('EXISTING campaign — "Missing Parent ID" regression (37 records → 0 applied)', () => {
  const liveIds = new Map([['ME-SP/PT (COMPETITORS, MINT, A1)',
    { campaign_id: '43890791772293', ad_group_id: '110705660935518' }]]);

  it('skips the Create scaffold and emits only the target row', () => {
    const res = buildCompetitorSpRows(item(), baseCtx({ liveIds }));
    expect(entities(res.spRows)).toEqual(['Product Targeting']);
  });

  it('addresses the parent by REAL numeric ids, never by name', () => {
    const t = targetRow(buildCompetitorSpRows(item(), baseCtx({ liveIds })).spRows);
    expect(t['Campaign ID']).toBe('43890791772293');
    expect(t['Ad Group ID']).toBe('110705660935518');
    // the name must not leak into a value column (Amazon would read it as a rename)
    expect(t['Campaign Name']).toBeUndefined();
    expect(t['Campaign Name (Informational only)']).toBe('ME-SP/PT (Competitors, Mint, A1)');
  });

  it('DROPS the row when the campaign is live but its ids are unknown', () => {
    // One unaddressable row voids the entire upload, so losing one target beats losing all.
    const unknown = new Map([['ME-SP/PT (COMPETITORS, MINT, A1)',
      { campaign_id: '', ad_group_id: '' }]]);
    const res = buildCompetitorSpRows(item(), baseCtx({ liveIds: unknown }));
    expect(res.spRows).toEqual([]);
    expect(res.warnings.join(' ')).toMatch(/ids are unknown/);
  });
});

describe('SB video — "bidAdjustmentsByPlacement cannot be empty" regression', () => {
  const sbItem = item({
    action: 'ADD_COMPETITOR_TARGET_SB',
    campaign: 'ME-VIDEO/PT (Competitors, Pink, C1)',
    ad_group_name: 'ME - Competitors Pink C1',
    recommended_bid: 1.09,
  });

  it('always sets Bid Optimization=true (false requires placement adjustments we do not send)', () => {
    const res = buildCompetitorSbRows(sbItem, baseCtx());
    const camp = res.sbRows.find(r => r.Entity === 'Campaign')!;
    expect(camp['Bid Optimization']).toBe('true');
  });

  it('emits Campaign + Ad Group + Video Ad + Product Targeting on the SB sheet only', () => {
    const res = buildCompetitorSbRows(sbItem, baseCtx());
    expect(entities(res.sbRows)).toEqual(['Campaign', 'Ad Group', 'Video Ad', 'Product Targeting']);
    expect(res.spRows).toEqual([]);   // SB entities on the SP sheet are rejected
  });

  it('links the video ad to the winner variation, not the competitor', () => {
    const ad = buildCompetitorSbRows(sbItem, baseCtx()).sbRows.find(r => r.Entity === 'Video Ad')!;
    expect(ad['Creative ASINs']).toBe('B0F9X95K5H');
    expect(ad['Video asset IDs']).toBe('amzn1.assetlibrary.asset1.abc:version_v1');
  });

  it('emits NOTHING when the family has no video asset', () => {
    const res = buildCompetitorSbRows(sbItem, baseCtx({ videoAssetFor: () => '' }));
    expect(res.sbRows).toEqual([]);
    expect(res.warnings.join(' ')).toMatch(/no video asset/);
  });

  it('uses real ids for an existing SB campaign', () => {
    const liveIds = new Map([['ME-VIDEO/PT (COMPETITORS, PINK, C1)',
      { campaign_id: '236737185271075', ad_group_id: '400807565840782' }]]);
    const res = buildCompetitorSbRows(sbItem, baseCtx({ liveIds }));
    expect(entities(res.sbRows)).toEqual(['Product Targeting']);
    expect(res.sbRows[0]['Campaign Id']).toBe('236737185271075');
    expect(res.sbRows[0]['Ad Group Id']).toBe('400807565840782');
  });
});

describe('guards', () => {
  it('drops a row with no target expression rather than emitting an empty target', () => {
    const res = buildCompetitorSpRows(item({ targeting: '' }), baseCtx());
    expect(res.spRows).toEqual([]);
    expect(res.warnings.join(' ')).toMatch(/missing target expression/);
  });

  it('falls back to the template floor when the plan supplied no bid', () => {
    const t = targetRow(buildCompetitorSpRows(item({ recommended_bid: null }), baseCtx()).spRows);
    expect(t.Bid).toBe('0.25');
  });
});
