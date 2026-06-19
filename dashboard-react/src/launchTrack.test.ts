import { describe, it, expect } from 'vitest';
import {
  launchAnchorCpc,
  launchBid,
  launchStepDownBid,
  launchDecision,
} from './launchTrack';

// ── Aggressive launch bid: anchor (cpc30d ?? cpc12m) × 1.70, ceiling $1.40, cold-start chain ──
describe('launchAnchorCpc', () => {
  it('prefers cpc_30d over cpc_12m', () => {
    expect(launchAnchorCpc({ cpc30d: 0.5, cpc12m: 0.9 })).toBe(0.5);
  });
  it('falls back to cpc_12m when 30d is null', () => {
    expect(launchAnchorCpc({ cpc30d: null, cpc12m: 0.9 })).toBe(0.9);
  });
  it('is null when both are null', () => {
    expect(launchAnchorCpc({ cpc30d: null, cpc12m: null })).toBeNull();
  });
});

describe('launchBid', () => {
  it('computes anchor × 1.70 from cpc when under the ceiling', () => {
    const r = launchBid({ cpc30d: 0.5, cpc12m: null, marketCpc: null, strategyBidMax: null });
    expect(r.bid).toBeCloseTo(0.85); // 0.5 × 1.7
    expect(r.source).toBe('cpc');
  });
  it('caps at the $1.40 ceiling when anchor × 1.70 exceeds it', () => {
    const r = launchBid({ cpc30d: 1.0, cpc12m: null, marketCpc: null, strategyBidMax: null });
    expect(r.bid).toBeCloseTo(1.4); // 1.0 × 1.7 = 1.70 → capped
    expect(r.source).toBe('cpc');
  });
  it('cold start 1: uses market CPC × 1.70 when no research CPC', () => {
    const r = launchBid({ cpc30d: null, cpc12m: null, marketCpc: 0.4, strategyBidMax: 3 });
    expect(r.bid).toBeCloseTo(0.68); // 0.4 × 1.7
    expect(r.source).toBe('market');
  });
  it('cold start 2: uses strategy bid max × 1.70 (capped) when no CPC at all', () => {
    const r = launchBid({ cpc30d: null, cpc12m: null, marketCpc: null, strategyBidMax: 0.5 });
    expect(r.bid).toBeCloseTo(0.85); // 0.5 × 1.7
    expect(r.source).toBe('template');
  });
  it('cold start 3: flat $1.20 when nothing is available', () => {
    const r = launchBid({ cpc30d: null, cpc12m: null, marketCpc: null, strategyBidMax: null });
    expect(r.bid).toBeCloseTo(1.2);
    expect(r.source).toBe('cold');
  });
  it('ceiling caps even the strategy-template anchor', () => {
    const r = launchBid({ cpc30d: null, cpc12m: null, marketCpc: null, strategyBidMax: 5 });
    expect(r.bid).toBeCloseTo(1.4); // 5 × 1.7 capped
  });
});

describe('launchStepDownBid', () => {
  it('reduces the current bid by 20%', () => {
    expect(launchStepDownBid(1.0, null)).toBeCloseTo(0.8);
  });
  it('floors at the term CPC (never bids below what a click costs)', () => {
    expect(launchStepDownBid(1.0, 0.95)).toBeCloseTo(0.95); // 0.80 would be below the 0.95 floor
  });
  it('honors a normal floor when current×0.8 is above it', () => {
    expect(launchStepDownBid(2.0, 0.5)).toBeCloseTo(1.6);
  });
});

// ── The 15-click decision matrix + winner graduation ──
const base = {
  isNewCampaign: true,
  launchClicks: 0,
  orders: 0,
  netRoas: 0,
  profitableRoas: 1.1,
  winOrders: 0,
  winNetRoas: 0,
  clicksSinceLastBidChange: 99, // batch gate open unless a test overrides
};

describe('launchDecision — track membership', () => {
  it('returns NONE for a campaign past the launch window', () => {
    expect(launchDecision({ ...base, isNewCampaign: false }).decision).toBe('NONE');
  });
});

describe('launchDecision — winner graduation', () => {
  it('graduates when the winner window has ≥2 orders at/above the profitable bar', () => {
    const r = launchDecision({ ...base, orders: 3, netRoas: 1.5, winOrders: 2, winNetRoas: 1.3 });
    expect(r.decision).toBe('LAUNCH_GRADUATE');
  });
  it('does not graduate on 2 winner orders below the profitable bar', () => {
    const r = launchDecision({ ...base, orders: 3, netRoas: 1.5, winOrders: 2, winNetRoas: 0.9 });
    expect(r.decision).not.toBe('LAUNCH_GRADUATE');
  });
  it('does not graduate on a single winner-window order', () => {
    const r = launchDecision({ ...base, orders: 2, netRoas: 1.5, winOrders: 1, winNetRoas: 5 });
    expect(r.decision).not.toBe('LAUNCH_GRADUATE');
  });
});

describe('launchDecision — has orders', () => {
  it('holds when profitable (orders ≥1, net ROAS ≥ bar) and not a winner yet', () => {
    expect(launchDecision({ ...base, launchClicks: 20, orders: 1, netRoas: 1.2 }).decision).toBe('LAUNCH_HOLD');
  });
  it('reduces when it has orders but is below the profitable bar', () => {
    expect(launchDecision({ ...base, launchClicks: 20, orders: 1, netRoas: 0.6 }).decision).toBe('LAUNCH_REDUCE_BID');
  });
  it('waits (HOLD) on an unprofitable term if <15 clicks since the last bid change', () => {
    const r = launchDecision({ ...base, launchClicks: 20, orders: 1, netRoas: 0.6, clicksSinceLastBidChange: 8 });
    expect(r.decision).toBe('LAUNCH_HOLD');
  });
});

describe('launchDecision — zero orders progression (15/30/45)', () => {
  it('holds aggressive at 15 clicks, 0 orders (too early)', () => {
    expect(launchDecision({ ...base, launchClicks: 15 }).decision).toBe('LAUNCH_HOLD');
  });
  it('still holds below the first checkpoint', () => {
    expect(launchDecision({ ...base, launchClicks: 9 }).decision).toBe('LAUNCH_HOLD');
  });
  it('reduces at 30 clicks, 0 orders', () => {
    expect(launchDecision({ ...base, launchClicks: 30 }).decision).toBe('LAUNCH_REDUCE_BID');
  });
  it('negates at 45 clicks, 0 orders', () => {
    expect(launchDecision({ ...base, launchClicks: 45 }).decision).toBe('LAUNCH_NEGATE');
  });
  it('negate takes priority once the negate-click bar is crossed', () => {
    expect(launchDecision({ ...base, launchClicks: 60 }).decision).toBe('LAUNCH_NEGATE');
  });
});
