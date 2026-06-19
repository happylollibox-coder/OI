import { describe, it, expect } from 'vitest';
import { withWindow, daysBetween, weeksBetween, fillSeries, buildCampaignDailyIndex, buildTermWeeklyIndex, seriesFor, TERM_KEY } from './adsTrend.helpers';
import type { Ads7dRow, CampaignSearchTermWeeklyRow } from '../types';

describe('withWindow', () => {
  it('appends the window label to a count string', () => {
    expect(withWindow('82 active', 'week of Jun 8–14')).toBe('82 active · week of Jun 8–14');
  });
  it('returns the count unchanged when window is empty', () => {
    expect(withWindow('30 terms', '')).toBe('30 terms');
  });
});

describe('daysBetween', () => {
  it('returns inclusive calendar days oldest→newest', () => {
    expect(daysBetween('2026-06-08', '2026-06-11')).toEqual(
      ['2026-06-08', '2026-06-09', '2026-06-10', '2026-06-11']
    );
  });
  it('returns a single day when start === end', () => {
    expect(daysBetween('2026-06-08', '2026-06-08')).toEqual(['2026-06-08']);
  });
  it('returns [] when start is after end', () => {
    expect(daysBetween('2026-06-10', '2026-06-08')).toEqual([]);
  });
});

describe('weeksBetween', () => {
  it('steps by 7 days inclusive', () => {
    expect(weeksBetween('2026-05-24', '2026-06-14')).toEqual(
      ['2026-05-24', '2026-05-31', '2026-06-07', '2026-06-14']
    );
  });
  it('returns a single week when start === end', () => {
    expect(weeksBetween('2026-06-14', '2026-06-14')).toEqual(['2026-06-14']);
  });
});

describe('fillSeries', () => {
  it('maps each axis key to its bucket value, 0 for gaps', () => {
    const buckets = new Map<string, number>([
      ['2026-06-08', 5],
      ['2026-06-10', 2],
    ]);
    expect(fillSeries(buckets, ['2026-06-08', '2026-06-09', '2026-06-10'])).toEqual([5, 0, 2]);
  });
  it('returns all zeros when buckets is undefined', () => {
    expect(fillSeries(undefined, ['2026-06-08', '2026-06-09'])).toEqual([0, 0]);
  });
});

const campRow = (over: Partial<Ads7dRow>): Ads7dRow => ({
  row_type: 'campaign', campaign_id: 'C1', campaign_name: 'c', campaign_type: null,
  search_term: null, spend: 0, orders: 0, clicks: 0, impressions: 0, sales: 0,
  gross_profit: null, cpc: 0, conv_rate: 0, roas: 0, search_terms_count: null, ...over,
});

describe('buildCampaignDailyIndex', () => {
  it('buckets spend and net (gross_profit − spend) by campaign and date', () => {
    const idx = buildCampaignDailyIndex([
      campRow({ campaign_id: 'C1', date: '2026-06-08', spend: 10, gross_profit: 30 }),
      campRow({ campaign_id: 'C1', date: '2026-06-08', spend: 5, gross_profit: 5 }),
      campRow({ campaign_id: 'C2', date: '2026-06-09', spend: 2, gross_profit: 1 }),
    ]);
    expect(idx.get('C1')!.get('2026-06-08')).toEqual({ spend: 15, net: 20 }); // (30-10)+(5-5)=20
    expect(idx.get('C2')!.get('2026-06-09')).toEqual({ spend: 2, net: -1 });
  });
  it('falls back to sales − cogs when gross_profit is null', () => {
    const idx = buildCampaignDailyIndex([
      campRow({ campaign_id: 'C1', date: '2026-06-08', spend: 4, sales: 10, cogs: 3, gross_profit: null }),
    ]);
    expect(idx.get('C1')!.get('2026-06-08')).toEqual({ spend: 4, net: 3 }); // (10-3)-4
  });
});

describe('buildTermWeeklyIndex', () => {
  it('keys by campaign+term and buckets by week_start', () => {
    const rows: CampaignSearchTermWeeklyRow[] = [
      { campaign_id: 'C1', search_term: 'gift', week_start: '2026-06-07', spend: 8, gross_profit: 20 },
      { campaign_id: 'C1', search_term: 'gift', week_start: '2026-06-14', spend: 3, gross_profit: 2 },
    ];
    const idx = buildTermWeeklyIndex(rows);
    const k = TERM_KEY('C1', 'gift');
    expect(idx.get(k)!.get('2026-06-07')).toEqual({ spend: 8, net: 12 });
    expect(idx.get(k)!.get('2026-06-14')).toEqual({ spend: 3, net: -1 });
  });
});

describe('seriesFor', () => {
  it('extracts the spend metric across an axis, gap-filled with 0', () => {
    const idx = buildCampaignDailyIndex([
      campRow({ campaign_id: 'C1', date: '2026-06-08', spend: 10, gross_profit: 30 }),
      campRow({ campaign_id: 'C1', date: '2026-06-10', spend: 4, gross_profit: 0 }),
    ]);
    expect(seriesFor(idx.get('C1'), ['2026-06-08', '2026-06-09', '2026-06-10'], 'spend'))
      .toEqual([10, 0, 4]);
    expect(seriesFor(idx.get('C1'), ['2026-06-08', '2026-06-09', '2026-06-10'], 'net'))
      .toEqual([20, 0, -4]);
  });
  it('returns all zeros for an unknown key', () => {
    expect(seriesFor(undefined, ['2026-06-08'], 'spend')).toEqual([0]);
  });
});
