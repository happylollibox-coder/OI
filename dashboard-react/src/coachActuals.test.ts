import { describe, it, expect } from 'vitest';
import { familyActuals, familyModes, dominantMode } from './coachActuals';

// daily_trends rows are keyed by product_type = family. ad_cost & clicks are ad-only.
const trends = [
  { date: '2026-06-01', product_type: 'Lollibox', ad_cost: 70, clicks: 100 },
  { date: '2026-06-02', product_type: 'Lollibox', ad_cost: 70, clicks: 100 },
];
// acts carry the 4w window: net_roas spend-weighted by spend, family via getFamily(product_short_name).
const acts = [
  { product_short_name: 'White Lollibox', spend: 100, net_roas: 1.5 },
  { product_short_name: 'Pink Lollibox',  spend: 100, net_roas: 0.5 },
];
const getFamily = (n?: string | null) => (n ? (n.split(' ').slice(-1)[0] === 'Lollibox' ? 'Lollibox' : null) : null);

describe('familyActuals', () => {
  it('computes last-7d daily ad spend, ad-only CPC, and spend-weighted 4w ROAS per family', () => {
    const out = familyActuals(acts, trends, getFamily);
    const f = out.get('Lollibox')!;
    expect(f.dailyCost).toBeCloseTo(140 / 2);          // 2 days in window -> $70/d
    expect(f.cpc).toBeCloseTo(140 / 200);              // $0.70 ad-only CPC
    expect(f.roas).toBeCloseTo((1.5 * 100 + 0.5 * 100) / 200); // 1.0 spend-weighted
  });
  it('uses only the most recent 7 distinct trend dates (older dates excluded)', () => {
    // First 3 days carry a huge ad_cost; if they were counted, dailyCost would blow up.
    const long = Array.from({ length: 10 }, (_, i) => ({
      date: `2026-06-${String(i + 1).padStart(2, '0')}`, product_type: 'Lollibox',
      ad_cost: i < 3 ? 1000 : 10, clicks: 10,
    }));
    const out = familyActuals([], long, getFamily);
    // Only days 4-10 (the last 7) count: 7 x $10 / 7 = $10/d. The $1000 early days are excluded.
    expect(out.get('Lollibox')!.dailyCost).toBeCloseTo(10);
  });
  it('emits families that appear only in trends (spend, no ROAS) and only in acts (ROAS, no spend)', () => {
    const out = familyActuals(
      [{ product_short_name: 'White Lollibox', spend: 50, net_roas: 2 }],
      [{ date: '2026-06-01', product_type: 'LolliME', ad_cost: 30, clicks: 60 }],
      (n?: string | null) => (n?.includes('Lollibox') ? 'Lollibox' : null),
    );
    expect(out.get('LolliME')!.dailyCost).toBeCloseTo(30);
    expect(out.get('LolliME')!.roas).toBe(0);
    expect(out.get('Lollibox')!.roas).toBeCloseTo(2);
    expect(out.get('Lollibox')!.dailyCost).toBe(0);
  });
  it('never divides by zero (no clicks -> cpc 0, no spend -> roas 0)', () => {
    const out = familyActuals(
      [{ product_short_name: 'White Lollibox', spend: 0, net_roas: 9 }],
      [{ date: '2026-06-01', product_type: 'Lollibox', ad_cost: 5, clicks: 0 }],
      (n?: string | null) => (n?.includes('Lollibox') ? 'Lollibox' : null),
    );
    const f = out.get('Lollibox')!;
    expect(f.cpc).toBe(0);
    expect(f.roas).toBe(0);
  });
});

describe('dominantMode', () => {
  it('returns the most frequent coach_mode', () => {
    expect(dominantMode([{ coach_mode: 'BLITZ' }, { coach_mode: 'BLITZ' }, { coach_mode: 'GUARDIAN' }])).toBe('BLITZ');
  });
  it('defaults to GUARDIAN when empty', () => {
    expect(dominantMode([])).toBe('GUARDIAN');
  });
});

describe('familyModes', () => {
  const rows = [
    { product_short_name: 'White Lollibox', coach_mode: 'BLITZ' },
    { product_short_name: 'Pink Lollibox',  coach_mode: 'BLITZ' },
    { product_short_name: 'Mint LolliME',   coach_mode: 'COOLDOWN' },
  ];
  const fam = (n?: string | null) =>
    n?.includes('Lollibox') ? 'Lollibox' : n?.includes('LolliME') ? 'LolliME' : null;
  it('maps each family to its own dominant mode (keyed by getFamily)', () => {
    const m = familyModes(rows, fam);
    expect(m.get('Lollibox')).toBe('BLITZ');
    expect(m.get('LolliME')).toBe('COOLDOWN'); // NOT the global dominant (BLITZ)
  });
  it('ignores rows with no family or no mode', () => {
    const m = familyModes([{ product_short_name: 'Unknown', coach_mode: 'BLITZ' }], fam);
    expect(m.size).toBe(0);
  });
});
