import { describe, it, expect } from 'vitest';
import { familyForRow, rowMatchesFamily, extractFamilyFromCampaign } from './adsHierarchy.helpers';

describe('familyForRow — canonical family for an ads row', () => {
  it('uses parent_name (V_PRODUCT_FAMILY_MAP family) when present', () => {
    expect(familyForRow({ parent_name: 'Bunny', campaign_name: 'Awesome Bunny / SP' })).toBe('Bunny');
  });

  it('keeps a Bunny product out of "Other" even when the campaign name has no family token (the reported bug)', () => {
    expect(familyForRow({ parent_name: 'Bunny', campaign_name: 'gift for girls (Choice)' })).toBe('Bunny');
  });

  it('files "White Lollibox" under Lollibox via parent_name, not "Other"', () => {
    // campaign named after a person, not the product — old logic dumped it in "Other"
    expect(familyForRow({ parent_name: 'Lollibox', campaign_name: 'Jenna / SP-VIDEO' })).toBe('Lollibox');
  });

  it('falls back to campaign-name parsing only when parent_name is missing', () => {
    expect(familyForRow({ parent_name: null, campaign_name: 'BOX-SP' })).toBe('Lollibox');
    expect(familyForRow({ parent_name: '', campaign_name: 'fresh-sp' })).toBe('Fresh');
  });

  it('returns "Other" only when neither parent_name nor a known campaign token exists', () => {
    expect(familyForRow({ parent_name: null, campaign_name: 'random thing' })).toBe('Other');
  });
});

describe('rowMatchesFamily — global family filter predicate', () => {
  it('matches by parent_name, case-insensitively (data "BUNNY" vs enum "Bunny")', () => {
    expect(rowMatchesFamily({ parent_name: 'BUNNY', campaign_name: '' }, 'Bunny')).toBe(true);
  });

  it('does not match a different family', () => {
    expect(rowMatchesFamily({ parent_name: 'Lollibox', campaign_name: '' }, 'Bunny')).toBe(false);
  });

  it('treats a null/empty family filter as "match everything"', () => {
    expect(rowMatchesFamily({ parent_name: 'Fresh', campaign_name: '' }, null)).toBe(true);
  });

  it('still matches via campaign-name fallback when parent_name is missing', () => {
    expect(rowMatchesFamily({ parent_name: null, campaign_name: 'BOX-SP' }, 'Lollibox')).toBe(true);
  });
});

describe('extractFamilyFromCampaign — legacy fallback, behavior preserved', () => {
  it('maps known campaign-name tokens', () => {
    expect(extractFamilyFromCampaign('Truth Bottle')).toBe('Bottle');
    expect(extractFamilyFromCampaign('fresh restock')).toBe('Fresh');
  });

  it('returns "Other" for unknown names', () => {
    expect(extractFamilyFromCampaign('random thing')).toBe('Other');
  });
});
