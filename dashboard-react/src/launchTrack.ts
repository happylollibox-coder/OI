// ─── New-campaign launch track — REFERENCE logic (spec 2026-06-19-new-campaign-launch-track) ──
// Source of truth for launch decisions/bids is V_ADS_COACH (engine SQL); the dashboard renders
// the engine's launch_bid / launch_decision. This module mirrors that arithmetic as an executable
// spec so the boundary maths (ceiling, cold-start chain, CPC floor, 15/30/45 checkpoints, winner
// graduation) is unit-testable independently of the warehouse. Keep it in lock-step with the SQL.
//
// Lifecycle: a young campaign (age < LAUNCH_WINDOW_DAYS) bids aggressively to buy clicks fast, then
// re-decides every LAUNCH_CHECKPOINT_CLICKS clicks (hold / reduce −20% / negate), and graduates off
// the track once it proves itself (winner) or the window closes.

export interface LaunchThresholds {
  windowDays: number;        // campaign age cutoff for the track
  bidMult: number;           // aggressive multiplier over anchor CPC
  bidCeiling: number;        // hard max launch bid ($)
  coldBid: number;           // flat fallback bid ($) when no CPC anchor
  stepDownPct: number;       // reduction fraction per reduce checkpoint
  checkpointClicks: number;  // clicks per decision checkpoint
  negateClicks: number;      // 0-order clicks that trigger negate
  winnerOrders: number;      // orders in the winner window to graduate
  winnerDays: number;        // trailing days for the winner check (used by SQL window)
}

export const LAUNCH_DEFAULTS: LaunchThresholds = Object.freeze({
  windowDays: 30,
  bidMult: 1.7,
  bidCeiling: 1.4,
  coldBid: 1.2,
  stepDownPct: 0.2,
  checkpointClicks: 15,
  negateClicks: 45,
  winnerOrders: 2,
  winnerDays: 3,
});

// ── Aggressive launch bid ──
export interface LaunchBidInput {
  cpc30d: number | null;       // research-page CPC (your avg, 30d)
  cpc12m: number | null;       // research-page CPC (your avg, 12m)
  marketCpc: number | null;    // SQP-derived market CPC (cold-start)
  strategyBidMax: number | null; // DIM_STRATEGY_TEMPLATE recommended_bid_max (cold-start)
}
export type LaunchBidSource = 'cpc' | 'market' | 'template' | 'cold';

/** anchor = cpc_30d ?? cpc_12m (research-page CPC). Null when never advertised. */
export function launchAnchorCpc(i: Pick<LaunchBidInput, 'cpc30d' | 'cpc12m'>): number | null {
  if (i.cpc30d != null && i.cpc30d > 0) return i.cpc30d;
  if (i.cpc12m != null && i.cpc12m > 0) return i.cpc12m;
  return null;
}

/** Aggressive launch bid with the cold-start fallback chain, capped at the ceiling. */
export function launchBid(i: LaunchBidInput, t: LaunchThresholds = LAUNCH_DEFAULTS): { bid: number; source: LaunchBidSource } {
  const cap = (v: number) => Math.min(v, t.bidCeiling);
  const anchor = launchAnchorCpc(i);
  if (anchor != null) return { bid: cap(anchor * t.bidMult), source: 'cpc' };
  if (i.marketCpc != null && i.marketCpc > 0) return { bid: cap(i.marketCpc * t.bidMult), source: 'market' };
  if (i.strategyBidMax != null && i.strategyBidMax > 0) return { bid: cap(i.strategyBidMax * t.bidMult), source: 'template' };
  return { bid: cap(t.coldBid), source: 'cold' };
}

/** Reduce step: current × (1 − stepDownPct), floored at the term's own CPC (don't bid below a click). */
export function launchStepDownBid(currentBid: number, termCpc: number | null, t: LaunchThresholds = LAUNCH_DEFAULTS): number {
  const stepped = currentBid * (1 - t.stepDownPct);
  return termCpc != null && termCpc > 0 ? Math.max(stepped, termCpc) : stepped;
}

// ── The 15-click decision matrix ──
export interface LaunchDecisionInput {
  isNewCampaign: boolean;          // campaign_age_days < windowDays
  launchClicks: number;            // cumulative clicks since launch
  orders: number;                  // cumulative orders since launch
  netRoas: number;                 // cumulative net ROAS since launch
  profitableRoas: number;          // the mode's PROFITABLE_ROAS bar
  winOrders: number;               // orders in the trailing winner window
  winNetRoas: number;              // net ROAS in the trailing winner window
  clicksSinceLastBidChange?: number; // deprecated — reduce cadence is now handled by the 3-day engine cooldown
}
export type LaunchDecision =
  | 'NONE'             // not on the launch track
  | 'LAUNCH_GRADUATE'  // proven winner → hand to normal coacher
  | 'LAUNCH_HOLD'      // keep current (aggressive) bid; too early or waiting for next batch
  | 'LAUNCH_REDUCE_BID'// step the bid down −20%
  | 'LAUNCH_NEGATE';   // real negative — negate/stop

export function launchDecision(i: LaunchDecisionInput, t: LaunchThresholds = LAUNCH_DEFAULTS): { decision: LaunchDecision; reason: string } {
  if (!i.isNewCampaign) return { decision: 'NONE', reason: 'campaign past launch window' };

  // Winner: proved itself in the trailing window → graduate to the normal coacher.
  if (i.winOrders >= t.winnerOrders && i.winNetRoas >= i.profitableRoas) {
    return { decision: 'LAUNCH_GRADUATE', reason: `${i.winOrders} orders @ net ROAS ${i.winNetRoas.toFixed(2)} in the last ${t.winnerDays}d — proven winner, graduate` };
  }

  // Has orders: profitable → hold; unprofitable → reduce. Judged on the target-clause rollup; churn is
  // prevented by the 3-day no-re-suggest cooldown (engine), so there is no per-click-batch gate.
  if (i.orders >= 1) {
    if (i.netRoas >= i.profitableRoas) {
      return { decision: 'LAUNCH_HOLD', reason: `net ROAS ${i.netRoas.toFixed(2)} ≥ ${i.profitableRoas} — working, hold` };
    }
    return { decision: 'LAUNCH_REDUCE_BID', reason: `net ROAS ${i.netRoas.toFixed(2)} < ${i.profitableRoas} with orders — too expensive` };
  }

  // Zero orders: progression by cumulative clicks (hold / reduce at 2× checkpoint / negate).
  if (i.launchClicks >= t.negateClicks) {
    return { decision: 'LAUNCH_NEGATE', reason: `${i.launchClicks} clicks, 0 orders ≥ ${t.negateClicks} — real negative` };
  }
  if (i.launchClicks >= 2 * t.checkpointClicks) {
    return { decision: 'LAUNCH_REDUCE_BID', reason: `${i.launchClicks} clicks, 0 orders — warning` };
  }
  return { decision: 'LAUNCH_HOLD', reason: `${i.launchClicks} clicks, 0 orders — too early, keep gathering` };
}
