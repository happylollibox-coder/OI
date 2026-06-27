# Rolling Weekly Plan (Coacher sub-project D)

- **Date:** 2026-06-27
- **Owner:** Ori
- **Status:** Design approved — pending spec review → plan
- **Parent vision:** the per-product coacher. **D** is the "create/update a daily/weekly plan → perform → check" step between strategy (B/C) and the net-profit guardrail (E).
- **Builds on:** B/B.2 strategy profile ([[project_coacher_product_strategy_profile]]), C gaps/borrow/probe ([[project_coacher_gaps_borrow_probe]]), the coacher engine `V_ADS_COACH`, the business plan (`DE_PLAN_STRATEGY`/`V_PLAN_FORECAST`), the holiday calendar (`DIM_US_HOLIDAYS`).

---

## 1. Problem

The coacher produces live per-keyword decisions (Actions page), but there is **no plan**: no forward view of what to do over the coming weeks, and no record to check last week's results against. D adds a **rolling weekly plan per product** with a built-in **plan-vs-actual feedback loop**: plan the next weeks at a high level, and each week compare last week's actual results to the plan — **on plan → continue, off plan → adjust** — then detail the current week.

## 2. Decisions locked (from brainstorming)

| Axis | Decision |
|---|---|
| **Cadence / horizon** | **Weekly**, rolling. Plan the **current week + next 3 weeks**. |
| **Granularity gradient** | **Current week = specific** (concrete actions + expected results). **Future weeks = high-level** (objective + direction). |
| **Feedback loop** | At each week start, review **last week actual vs last week plan** → `ON_PLAN` (continue) / `OFF_PLAN` (adjust). Off-plan hands deeper escalation to **E**. |
| **On/off-plan metric** | **Net profit is primary** (actual vs expected, within a tolerance band). **Strategic targets** (e.g. "establish EXACT coverage for a weak product") are tracked alongside on their own terms. |
| **Expected net profit** | **Bottom-up coacher trend, reconciled to the business plan** — trailing-weeks net profit (season-adjusted) is the base; flag when it diverges from the `DE_PLAN_STRATEGY` target. |
| **Plan authorship** | **System-proposed, editable** — derived from the strategy profile + calendar (peaks) + C's gaps; MANUAL edits preserved. |
| **Hierarchy** | **Plan** (weekly objective + expected NP) → **Actions** (concrete, current week, from `V_ADS_COACH`) → **Expected results** (per action). |
| **Scope** | The 4 advertised parents. D **assesses** on/off-plan and proposes adjustments; the deeper auto-adjust + escalation is **E**. |

## 3. Component 1 — the plan (`DE_WEEKLY_PLAN` + `DE_WEEKLY_PLAN_TARGET`)

`DE_WEEKLY_PLAN` — one row per `parent_name × week_start`:
- `week_start` (Mon), `parent_name`, `horizon` (`CURRENT` | `FUTURE`).
- `objective` — short text (e.g. "scale EXACT winners", "defend brand through Prime", "build EXACT coverage").
- `expected_net_profit` — the week's bottom-up trend projection (Component 4).
- `plan_net_profit` — the business-plan target for the week (apportioned from `V_PLAN_FORECAST`), for reconciliation.
- `coach_mode_hint` — GUARDIAN / BLITZ / COOLDOWN derived from the calendar (peak windows → BLITZ).
- `source` (`DERIVED` | `MANUAL`), `status` (`PROPOSED` | `ON_PLAN` | `OFF_PLAN`), `updated_at`, `updated_by`.

`DE_WEEKLY_PLAN_TARGET` — zero+ strategic targets per `parent × week_start`:
- `target_type` (e.g. `MAP_EXACT`, `FILL_GAPS`, `GRADUATE_PROBES`, `REDUCE_BLEEDERS`), `target_detail` (text), `metric` (what success looks like — e.g. "EXACT cells steering for Bottle ≥ 1"), `source` (`DERIVED`/`MANUAL`), `status` (`OPEN`/`MET`/`MISSED`).
- Auto-proposed from C's `V_STRATEGY_GAPS` (weak/missing cells → MAP_EXACT / FILL_GAPS), from probe state (GRADUATE_PROBES), and from bleeders.

Both editable (MANUAL preserved), mirroring `DE_PRODUCT_STRATEGY_PROFILE`.

## 4. Component 2 — the plan generator (`tools/weekly_plan/`)

A Python tool (same pattern as `tools/strategy_profile`): derive → load (DELETE DERIVED + INSERT, MANUAL preserved). Builds the current + next 3 weeks:
- **Expected net profit (trend):** per parent, the trailing-N-weeks ads net profit (`GROSS_PROFIT − Ads_cost` from `FACT_AMAZON_ADS`, weekly, by `camp_parent`), projected to next week with a **season factor** (peak weeks scaled by the LY peak-vs-baseline ratio from `DIM_US_HOLIDAYS` + history).
- **plan_net_profit (business plan):** the `V_PLAN_FORECAST` / `DE_PLAN_STRATEGY` target apportioned to the week (so the review can flag trend-vs-target divergence).
- **objective + coach_mode_hint:** from the calendar (pre-peak → BOOST/BLITZ; off-season → GUARDIAN) and the strategy profile direction.
- **strategic targets:** from `V_STRATEGY_GAPS` (weak/missing cells → MAP_EXACT/FILL_GAPS), probe state (`DE_PROBE_LOG` ACTIVE → GRADUATE_PROBES), bleeders.
- Run by `SP_ORCHESTRATE_DAILY_REFRESH` (or weekly); idempotent.

## 5. Component 3 — actions + expected results (`V_WEEKLY_PLAN_ACTIONS`)

A view over `V_ADS_COACH`, filtered to the **current week's** actionable rows, grouped under each parent's plan. Per action: the existing `target_action`, `current_bid → recommended_bid`, the distilled `reason`, **plus an `expected_result`**:
- `INCREASE_BID` → "more volume at held ROAS" + projected spend/orders from recent CPC×CVR×margin.
- `MONITOR_TARGET`/TOS-brake hold → "maintain position/net".
- `PROBE` → "reach 15 clicks to decide".
- `REDUCE_BID`/`NEGATE` → "cut wasted spend ≈ $X/wk".
- borrow/map-exact → "establish steering coverage".

## 6. Component 4 — the weekly review (`V_WEEKLY_PLAN_REVIEW`)

Per `parent × week_start` (last completed week): compute **actual** weekly net profit and compare to that week's `DE_WEEKLY_PLAN`:
- `actual_net_profit` (weekly ads net by parent), `expected_net_profit`, `delta`, `delta_pct`.
- `status` = `ON_PLAN` if `actual ≥ tolerance × expected` (tolerance seeded at **0.90**, tunable in `DE_COACH_THRESHOLDS`), else `OFF_PLAN`.
- `vs_business_plan` flag — `BELOW_TARGET` when `actual < plan_net_profit`, even if on trend (the reconciliation Ori asked for).
- `targets_met` / `targets_open` — strategic-target progress (e.g. did the weak cell start steering?).
- Writes `status` back onto `DE_WEEKLY_PLAN` for the reviewed week; the current week's plan is (re)detailed accordingly. **OFF_PLAN rows are the hand-off signal to E.**

## 7. Component 5 — surface

Render per product, reusing the **Home Brief** plain-language pattern (no full new page in v1): a "This Week's Plan" card per parent showing **status (on/off plan vs last week)**, the **week objective + expected vs actual net profit + business-plan flag**, the **actions & expected results**, the **strategic targets**, and a compact **forward 3-week** strip. Backed by a Cube loader over `V_WEEKLY_PLAN_REVIEW` + `V_WEEKLY_PLAN_ACTIONS`. A dedicated full Plan page is a fast-follow.

## 8. Scope

**In:** `DE_WEEKLY_PLAN` + `DE_WEEKLY_PLAN_TARGET`; `tools/weekly_plan/` generator; `V_WEEKLY_PLAN_ACTIONS`; `V_WEEKLY_PLAN_REVIEW`; the lightweight per-product surface; `config.yaml` registration; tolerance in `DE_COACH_THRESHOLDS`.
**Deferred:** auto-adjust / escalation when OFF_PLAN (that's **E**); a dedicated full Plan page; multi-week *action-level* detail (future weeks stay high-level); non-advertised products.

## 9. Risks & limits

- **Trend projection is naive** (trailing weeks + season factor); it sets expectations, not guarantees. The business-plan reconciliation is the sanity check.
- **Net profit = ads-attributed** (`GROSS_PROFIT − Ads_cost`), consistent with the coacher's net (not the full P&L incl. all fees). Stated explicitly.
- **Week boundary** = Monday (America/Los_Angeles); the review runs on completed weeks only (respects the orders/ads watermark, [[feedback_oi_orders_vs_ads_watermark]]).
- **Strategic targets** are coarse (proposed from gaps); they guide, they don't gate the net-profit decision.
- Observational, US-only.

## 10. Testing

- `DE_WEEKLY_PLAN`: generator produces current + 3 future weeks per parent; MANUAL rows preserved on re-run; peak weeks get BLITZ `coach_mode_hint`.
- `V_WEEKLY_PLAN_REVIEW`: a parent whose actual NP ≥ 0.90×expected is `ON_PLAN`, below is `OFF_PLAN`; `vs_business_plan=BELOW_TARGET` when actual < plan_net_profit; status written back to the plan row; no fan-out (one row per parent×week).
- `V_WEEKLY_PLAN_ACTIONS`: every current-week `V_ADS_COACH` actionable row appears once under its parent with a non-null `expected_result`; counts reconcile to the coacher.
- Strategic targets: a known weak/missing cell (from `V_STRATEGY_GAPS`) yields a `MAP_EXACT`/`FILL_GAPS` target; a cell that started steering flips the target to `MET`.
- Surface: the per-product card renders status + expected-vs-actual + actions for a sampled parent.
