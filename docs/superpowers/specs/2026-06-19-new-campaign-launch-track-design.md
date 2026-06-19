# New-Campaign Launch Coaching Track — Design

**Date:** 2026-06-19
**Status:** Approved (Ori) — implementing
**Branch:** feat/owned-negatives-coacher
**Approach:** A — engine-native (rules + bid math in `V_ADS_COACH` + `DE_COACH_THRESHOLDS`; dashboard renders only)

## Problem

New / low-volume campaigns never reach the HIGH-confidence bar (≥14 active days **and** ≥50 clicks), so their actions stay parked at LOW confidence and are invisible on the Action page. Observed on the **Bunny** family: 0 HIGH-confidence actions, ~825 LOW — nothing surfaces as a clear case.

## Goal

A parallel **launch track** for young campaigns: bid aggressively to buy clicks fast, then make an explicit decision **every 15 clicks**, surfaced in a dedicated "🆕 New campaigns" section — so new campaigns get acted on at 15 clicks instead of waiting for 50.

## Scope (non-negotiables from brainstorming)

- Decision rules + bid math live in **engine SQL** (`V_ADS_COACH` / `V_ADS_COACH_DATA`) and thresholds in **`DE_COACH_THRESHOLDS`**. The dashboard section only renders. (Per "coacher rules live in engine SQL".)
- Bids the coacher emits must be **deliberately decided** — no template auto-fill. (Per "coacher no auto-fill".)
- Net ROAS used here is **direct ad-attributed** (no halo), consistent with the rest of the coacher.

## 1. Identification — who is on the launch track

A keyword/target is on the launch track when **`campaign_age_days < LAUNCH_WINDOW_DAYS` (default 30)**.

- `campaign_age_days` already exists: `DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY)` at `V_ADS_COACH.sql:371`. Currently computed but unused.
- A keyword leaves the track on graduation (§5).

## 2. Aggressive launch bid

```
anchor      = cpc_30d ?? cpc_12m                      -- from V_RESEARCH_RANKED (join already at V_ADS_COACH.sql:221)
launch_bid  = MIN(anchor × LAUNCH_BID_MULT, LAUNCH_BID_CEILING)
            -- LAUNCH_BID_MULT = 1.70, LAUNCH_BID_CEILING = 1.40

cold start (anchor IS NULL — keyword never advertised):
   1. market CPC from SQP × 1.70          -- NEW field: market_cpc = market_spend / market_clicks
   2. else strategy recommended_bid_max × 1.70   -- DIM_STRATEGY_TEMPLATE
   3. else flat LAUNCH_COLD_BID = 1.20
```

- The ceiling caps **everything**, including the cold-start flat $1.20 (which is already under $1.40).
- `cpc_30d` / `cpc_12m` are research-page CPC columns from `V_RESEARCH_RANKED` ("your average cost-per-click for this term"). They are NULL for never-advertised keywords → cold-start chain.

## 3. The 15-click decision loop

Re-evaluate each time the keyword accrues another **`LAUNCH_CHECKPOINT_CLICKS` (15)** clicks. Decision matrix on cumulative-since-launch performance:

| Situation (cumulative since launch) | Decision (`launch_decision`) |
|---|---|
| orders ≥ 1 **and** net ROAS ≥ profitable bar | `LAUNCH_HOLD` (scale a notch if well above bar) |
| orders ≥ 1 **and** net ROAS < profitable bar | `LAUNCH_REDUCE_BID` (−20%, floor = term CPC) |
| 0 orders @ 15 clicks | `LAUNCH_HOLD` — too early, keep gathering |
| 0 orders @ 30 clicks | `LAUNCH_REDUCE_BID` (−20%) |
| 0 orders @ `LAUNCH_NEGATE_CLICKS` (45) clicks | `LAUNCH_NEGATE` / stop |

- "profitable bar" = the mode's `PROFITABLE_ROAS` threshold (already in `DE_COACH_THRESHOLDS`).
- **Step-down:** `LAUNCH_STEP_DOWN_PCT = 0.20` → `new_bid = MAX(current_bid × 0.80, term_cpc)`. Floor = the term's own CPC (don't bid below what a click costs).
- **Batch gating:** a "−20%" must fire **once per 15-click batch**, not on every daily refresh. Gate the reduce on `clicks_since_last_bid_change ≥ LAUNCH_CHECKPOINT_CLICKS`.

### Two click counters (important)
- **`launch_clicks`** — cumulative clicks since launch. For a campaign < 30 days old, `ads_clicks_4w` ≈ launch clicks (the 4w window ≈ its whole life). Drives the 0-order negate progression (15/30/45).
- **`clicks_since_last_bid_change`** — NEW state. Clicks accrued since the last bid change. Gates the −20% step-down cadence so it fires once per batch. Derived from Ads clicks since the keyword's last bid-change date (`last_updated_date` / `FACT_PPC_CHANGE_LOG`).

## 4. Surfacing

A dedicated **"🆕 New campaigns"** section on the Action page (`ActionsPage.tsx`), on the 15-click cadence, clearly labeled launch-phase so launch bets (15 clicks, aggressive bid) read differently from mature clear cases (50+ clicks). The standard "✅ Clear cases" list is unchanged. Section renders only — no decision logic client-side.

## 5. Exits — leaving the launch track

- **Winner (graduate up):** in the **last `LAUNCH_WINNER_DAYS` (3) days of available ads data** (ending at the ads watermark, not literally today — ads lag is 1–2 days), **orders ≥ `LAUNCH_WINNER_ORDERS` (2)** with net ROAS ≥ profitable bar → hand to the normal coacher. Uses existing `ads_orders_3d` / `ads_net_roas_3d`.
- **Time:** the 30-day window ends and the keyword is neither a winner nor negated → hand to the normal coacher at its current (reduced) bid — it is now a normal low-volume keyword.

## 6. Architecture / data flow

```
V_ADS_COACH_DATA   ← NEW: market_cpc, cpc_30d/cpc_12m surfaced, clicks_since_last_bid_change, is_new_campaign, launch_clicks
V_ADS_COACH        ← NEW: launch_bid, launch_decision, launch_phase, launch_decision_trace; matrix + winner/graduation logic
DE_COACH_THRESHOLDS ← NEW tunable keys (§7)
        │
SP_REFRESH_ADS_COACH_ACTIONS → FACT_ADS_COACH_ACTIONS   ← carry new columns
V_ADS_COACH_ACTIONS ← carry new columns (passthrough view)
        │
Cube AdsCoachDecision.js / AdsCoachActions.js  ← expose campaign_age_days + launch_* (not exposed today)
        │
dashboard-react: types.ts → useCubeData.ts → ActionsPage "🆕 New campaigns" section (render only)
```

## 7. New thresholds (`DE_COACH_THRESHOLDS`)

All tunable without redeploy. Seeded GLOBAL (strategy/mode = applicable scope per existing convention):

| key | default | meaning |
|---|---|---|
| `LAUNCH_WINDOW_DAYS` | 30 | campaign age cutoff for the launch track |
| `LAUNCH_BID_MULT` | 1.70 | aggressive multiplier over anchor CPC |
| `LAUNCH_BID_CEILING` | 1.40 | hard max launch bid ($) |
| `LAUNCH_COLD_BID` | 1.20 | flat fallback when no CPC anchor ($) |
| `LAUNCH_STEP_DOWN_PCT` | 0.20 | bid reduction per reduce checkpoint |
| `LAUNCH_CHECKPOINT_CLICKS` | 15 | clicks per decision checkpoint |
| `LAUNCH_NEGATE_CLICKS` | 45 | 0-order clicks → negate |
| `LAUNCH_WINNER_ORDERS` | 2 | orders in winner window to graduate |
| `LAUNCH_WINNER_DAYS` | 3 | trailing days for the winner check |

## 8. Risks / open implementation details

- **`clicks_since_last_bid_change`** is the main net-new engine state and the riskiest piece. Need a reliable "last bid change date" per keyword. `FACT_PPC_CHANGE_LOG` records uploaded bid changes; keyword `last_updated_date` is a fallback. Resolve the source in the plan.
- **Ads lag** on the 3-day winner window — anchor the window to the ads watermark (`MAX` available ads date), not `CURRENT_DATE`.
- **`launch_clicks` ≈ `ads_clicks_4w`** holds only while campaign age < 28 days. For 28–30 day campaigns the 4w window slightly understates lifetime clicks; acceptable for v1 (the window closes at 30 anyway). A true lifetime-clicks sum is a possible follow-up.
- Register threshold seed changes; no new BQ *objects* (columns + rows only), but confirm `config.yaml` needs no new entries.

## 9. Testing

- **Unit (vitest):** bid formula (ceiling cap, cold-start chain order, CPC floor) and matrix (each row + boundaries at 15/30/45 clicks, winner detection, graduation) — as a pure helper in `coachActuals.ts` mirroring the SQL, so the logic is independently testable even though the engine is the source of truth.
- **SQL validation:** `bq query --dry_run` on the changed views; targeted query on Bunny showing launch rows now appear with sane `launch_bid` / `launch_decision`.
- **Dashboard:** verify the "🆕 New campaigns" section renders for Bunny in the preview.

## 10. Deploy (GATED)

Source changes + local validation only in this pass. **Deploying the views + running `SP_REFRESH_ADS_COACH_ACTIONS` against prod uploads real bids to Amazon** — hold for Ori's explicit go-ahead before deploy/refresh.

---

# Follow-on: Money-bleeder fit-gated rule (BUILT + validated 2026-06-19, deploy gated)

> Status: implemented in `V_ADS_COACH` (fit short-circuit + not-fit negate catch + target REDUCE_BID + recommended_bid −40%), `DE_COACH_THRESHOLDS` (BLEEDER_FIT_RANK/REDUCE_PCT/MIN_CLICKS), and `coachActuals.ts` (reduces clear at MEDIUM). Validated on the bleeder terms via temp pipeline: fit→MONITOR+REDUCE_BID (e.g. teen girl gifts 0.65→0.39), not-fit→NEGATE. Spend floor = $5 (panel), not th_negate_spend, so fit terms can't slip into negation. CPC floor applies only when CPC < current bid (else full −40% to $0.10). Known edge: EXACT_BOOST self-targets resolve to STOP_TARGET (not REDUCE) at target level — term still protected from negation.

## Problem (diagnosed on live data)
The "Money Bleeders — 0 Orders (4w)" panel shows terms with real spend and 0 orders that the trust list does NOT surface. Live `V_ADS_COACH` query revealed three gaps:
1. **MONITOR on obvious bleeders** — e.g. "teen girl gifts" (HUNTER, HIGH conf, 47 clicks, $44, 0 orders) → `action=MONITOR`. The negate branch requires `ads_clicks_recent_5d > 0`; a term that stopped getting recent clicks never negates.
2. **MEDIUM confidence parks negates** — e.g. "14 year old girl gifts" / "gifts for 9 year old girls" → engine says `NEGATE_TERM` but at MEDIUM confidence, and the clearCase gate requires HIGH → parked.
3. **No research-fit fork** — negate fires (or doesn't) regardless of rank (ranks observed 23–63).

## Rule (Ori-approved)
For a money bleeder = **0 orders (4w) AND spend ≥ `th_negate_spend` AND clicks ≥ ~20**:
- **research_rank ≥ 50 (fit)** → `REDUCE_BID` **aggressively (−40%, floor = term CPC)**, not negate. Reversible; the existing bid-up logic re-raises slowly once a sale signals.
- **research_rank < 50 OR NULL/not-in-research** → `NEGATE_TERM` / stop.
- A bleeder must **never** resolve to MONITOR.

## Surfacing (clearCase gate)
- Fit **reduces** (reversible) surface at **MEDIUM** confidence.
- **Negates** (permanent) still require **HIGH** confidence.

## Implementation (engine-native, the careful part)
- `V_ADS_COACH` **term-action CASE** (lines ~455–629): fork the negate branches on `research_rank` — only `NEGATE_TERM` when rank < 50; when rank ≥ 50, defer to the target-action reduce. Ensure a bleeder never falls through to `MONITOR` (relax/replace the `ads_clicks_recent_5d > 0` gate for the 0-order bleeder case).
- `V_ADS_COACH` **target-action CASE**: fit bleeder (rank ≥ 50, 0 orders, spend ≥ negate_spend) → `REDUCE_BID` with an aggressive −40% step (new `BLEEDER_REDUCE_PCT` threshold, floor = term CPC).
- New `DE_COACH_THRESHOLDS` keys: `BLEEDER_FIT_RANK=50`, `BLEEDER_REDUCE_PCT=0.40`, `BLEEDER_MIN_CLICKS=20` (reuse `NEGATE_SPEND_THRESHOLD` for the spend floor).
- `clearCase` gate (`coachActuals.ts`): allow REDUCE verdicts at MEDIUM confidence; keep CUT/negate at HIGH.
- **Validate** via the same throwaway `_LTMP` view+FACT+SP pipeline; confirm the bleeders above flip to REDUCE (fit) / NEGATE (not-fit) and surface. Deploy stays gated.
