import { describe, it, expect } from 'vitest';
import { mergeUpdateRows, type BulkRow } from './bulksheetDedup';

const kw = (over: BulkRow): BulkRow => ({
  Product: 'Sponsored Products', Entity: 'Keyword', Operation: 'Update',
  'Keyword ID': '274585253932408', 'Keyword Text': 'teen gifts for girls',
  'Match Type': 'PHRASE', Bid: '', State: 'ENABLED', ...over,
});

describe('mergeUpdateRows', () => {
  it('collapses a blank-bid duplicate keyword into one row, keeping the real bid (report 17)', () => {
    const out = mergeUpdateRows([kw({ Bid: '0.66' }), kw({ Bid: '' })]);
    expect(out).toHaveLength(1);
    expect(out[0].Bid).toBe('0.66');
  });

  it('keeps the real bid regardless of which row comes first', () => {
    const out = mergeUpdateRows([kw({ Bid: '' }), kw({ Bid: '0.66' })]);
    expect(out).toHaveLength(1);
    expect(out[0].Bid).toBe('0.66');
  });

  it('does not merge two different keyword ids', () => {
    const out = mergeUpdateRows([
      kw({ 'Keyword ID': '111', Bid: '0.50' }),
      kw({ 'Keyword ID': '222', Bid: '0.70' }),
    ]);
    expect(out).toHaveLength(2);
  });

  it('merges a bid change + a pause on the same keyword into one row', () => {
    const out = mergeUpdateRows([
      kw({ Bid: '0.66', State: 'ENABLED' }),
      kw({ Bid: '', State: 'PAUSED' }),
    ]);
    expect(out).toHaveLength(1);
    expect(out[0].Bid).toBe('0.66');
    expect(out[0].State).toBe('PAUSED');
  });

  it('collapses duplicate Product Targeting Updates by Product Targeting ID', () => {
    const pt = (over: BulkRow): BulkRow => ({
      Product: 'Sponsored Products', Entity: 'Product Targeting', Operation: 'Update',
      'Product Targeting ID': '555', Bid: '', ...over,
    });
    const out = mergeUpdateRows([pt({ Bid: '0.32' }), pt({ Bid: '' })]);
    expect(out).toHaveLength(1);
    expect(out[0].Bid).toBe('0.32');
  });

  it('still merges campaign budget + rename Updates sharing a Campaign ID (report 10)', () => {
    const out = mergeUpdateRows([
      { Product: 'Sponsored Products', Entity: 'Campaign', Operation: 'Update', 'Campaign ID': '900', 'Daily Budget': '20' },
      { Product: 'Sponsored Products', Entity: 'Campaign', Operation: 'Update', 'Campaign ID': '900', 'Campaign Name': 'ME-COMPETE (Purple)' },
    ]);
    expect(out).toHaveLength(1);
    expect(out[0]['Daily Budget']).toBe('20');
    expect(out[0]['Campaign Name']).toBe('ME-COMPETE (Purple)');
  });

  it('handles the SB sheet spelling (Keyword Id / Campaign Id)', () => {
    const sbKw = (over: BulkRow): BulkRow => ({
      Product: 'Sponsored Brands', Entity: 'Keyword', Operation: 'Update',
      'Keyword Id': '999', Bid: '', ...over,
    });
    const out = mergeUpdateRows([sbKw({ Bid: '0.60' }), sbKw({ Bid: '' })]);
    expect(out).toHaveLength(1);
    expect(out[0].Bid).toBe('0.60');
  });

  it('never merges Create rows — only Update', () => {
    const create = (): BulkRow => ({
      Product: 'Sponsored Products', Entity: 'Keyword', Operation: 'Create',
      'Keyword Text': 'x', 'Match Type': 'EXACT',
    });
    const out = mergeUpdateRows([create(), create()]);
    expect(out).toHaveLength(2);
  });

  it('leaves an Update row with no entity id untouched (does not collapse blanks together)', () => {
    const out = mergeUpdateRows([kw({ 'Keyword ID': '', Bid: '0.4' }), kw({ 'Keyword ID': '', Bid: '0.5' })]);
    expect(out).toHaveLength(2);
  });
});
