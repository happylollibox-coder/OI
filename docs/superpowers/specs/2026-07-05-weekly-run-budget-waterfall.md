# Weekly Run — Budget Waterfall + Daily Optimizer — Design Spec

**Date:** 2026-07-05
**Owner:** Ori
**Status:** Approved design → ready for implementation plan

## Goal

Give the Weekly Run a top-level budget brain: set **one total daily ad budget** and have it flow down to families, then campaigns, on evidence — and have a daily loop tune each campaign on yesterday's numbers. Replace the ad-hoc per-campaign budget rules with a single, disciplined allocator.

## Constraints (standing)

- **All decision logic in the backend** (BigQuery SQL / Python). The React Step-1 UI is pure presentation + the two inputs (total budget, manual family overrides).
- **Prepare-only.** Every output is a *suggestion* surfaced in the Weekly Run; Ori reviews and uploads the bulksheet. Nothing auto-pushes to Amazon. "Close" = a suggested `CAMPAIGN_PAUSE`, never an auto-archive.
- **One budget engine.** These rules *replace* `V_ADS_COACH`'s current budget thresholds (raise ≥1.1 & ≥90% used / cut <0.9), so there are never two budget brains.
- **Total coverage.** 100% of **enabled** ad campaigns live inside the $700 — every one maps to exactly one family: the six product families, **Store** (mixed-family brand ads), or an **Unknown** catch-all for anything still unmapped. No enabled campaign falls outside the budget (Ori, 2026-07-05).
- Register every new BQ object in `config.yaml`.

## Architecture — four components

```
① WATERFALL (weekly re-base, Monday)
   DE_BUDGET_CONFIG(total=$700, floor=$10, …)
        → V_FAMILY_NET_PROFIT_7D        (real P&L net profit per family, incl organic)
        → V_FAMILY_BUDGET_ALLOCATION    (floor + winners take the rest; MANUAL override wins)
        → V_CAMPAIGN_BUDGET_BASE        (family slice split by campaign ads net profit)

② DAILY OPTIMIZER (existing daily job, on yesterday's data)
   → V_CAMPAIGN_DAILY_MOVE             (out-of-budget campaigns: −10% bids | +10% | +30% budget,
                                        bounded to the family cap)

③ ONE BUDGET ENGINE
   V_ADS_COACH budget_action → reads ①+② instead of its old 1.1/0.9/90% thresholds

④ FLOOR-CAMPAIGN LIFECYCLE (prove-it-or-die clock on $10-floor campaigns)
   DE_FLOOR_CAMPAIGN_LOG(floor_since) → V_FLOOR_CAMPAIGN_LIFECYCLE
   (STARVED→raise bid | MOVING→watch | 30d: <0.6 or still starved → CLOSE | else GRADUATE)
```

## Data model — new objects

### `DE_BUDGET_CONFIG` (data-entry, keyed like `DE_COACH_THRESHOLDS`)
| column | type | notes |
|---|---|---|
| config_key | STRING | see keys below |
| config_value | FLOAT64 | |
| note | STRING | |
| updated_at | TIMESTAMP | |
| updated_by | STRING | |

Seeded keys (Ori-editable): `total_daily_budget=700`, `family_floor_daily=10`, `campaign_launch_floor_daily=10`, `margin_roas_threshold=0.8`, `boost_roas_threshold=2.5`, `close_roas_threshold=0.6`, `floor_probation_days=30`, `starved_clicks_per_day=3`, `budget_increase_pct=0.10`, `boost_increase_pct=0.30`, `bid_cut_pct=0.10`, `out_of_budget_util=0.90`.

### `V_FAMILY_NET_PROFIT_7D` (view)
`parent_name, business_net_profit_7d, ads_net_profit_7d, weight`. Emits one row per family that has ≥1 enabled campaign — the six product families **plus Store and Unknown**.
- `business_net_profit_7d` — the **real business net profit** per **product** family (ads + organic − COGS − fees), summed over the 7 complete days ending at the **orders watermark** (not the ads watermark — see `[[feedback_oi_orders_vs_ads_watermark]]`); expression matches the KPI card (`V_UNIFIED_DAILY` cost_components split, per `[[project_kpi_pnl_real_cogs_breakdown]]`). NULL for Store/Unknown (no product P&L).
- `ads_net_profit_7d` — `SUM(GROSS_PROFIT − Ads_cost)` over the family's campaigns, 7d.
- `weight = GREATEST(COALESCE(business_net_profit_7d, ads_net_profit_7d), 0)` — product families are weighted by their real P&L (incl. organic, deliberately NOT ads-only); **Store/Unknown**, having no organic, fall back to their **ads** net profit. This is the split weight only.

### `V_FAMILY_BUDGET_ALLOCATION` (view)
Per family: `floor, profit_share_pct, allocated_daily, source`.
```
pot          = total_daily_budget − (family_floor_daily × n_active_families)
allocated    = family_floor_daily + pot × SAFE_DIVIDE(weight, SUM(weight) OVER ())
```
`weight` from `V_FAMILY_NET_PROFIT_7D` (product families = business net profit; Store/Unknown = ads net profit). `n_active_families` = families with ≥1 **enabled** coached campaign (parked/all-archived families get no floor).
- Loser families (weight = 0) keep only the floor.
- A `DE_PRODUCT_BUDGET` row with `source='MANUAL'` for that family **overrides** `allocated` (source='MANUAL'); everything else is `source='WATERFALL'`.
- Edge: if every family's 7d net profit ≤ 0, split the pot **equally** (avoid divide-by-zero → all-floor collapse).

### `V_CAMPAIGN_BUDGET_BASE` (view)
Per campaign within its family budget: `campaign_id, parent_name, family_budget, campaign_ads_net_profit_4w, base_daily, is_floor`.
```
pot_f      = family_budget − (campaign_launch_floor_daily × n_campaigns_in_family)
pos_np     = GREATEST(campaign_ads_net_profit_4w, 0)
base_daily = campaign_launch_floor_daily + pot_f × SAFE_DIVIDE(pos_np, SUM(pos_np) OVER (PARTITION BY parent_name))
is_floor   = base_daily ≤ campaign_launch_floor_daily × 1.05
```
- Ads net profit = `SUM(GROSS_PROFIT − Ads_cost)` over trailing 4 weeks, per campaign.
- Family attribution uses the `DE_CAMPAIGN_FAMILY` override + ASIN path (shipped 2026-07-05, `[[project_google_ads_pmax_audit_mcp]]`-adjacent work — the ASIN-blind video/Store fix).
- New / no-history campaigns (no spend in window) → `base_daily = launch_floor`, `is_floor = TRUE`.
- Only **enabled** campaigns participate; archived/paused excluded.

### `V_CAMPAIGN_DAILY_MOVE` (view) — the daily optimizer
Per **out-of-budget** enabled campaign, on **yesterday's** ads performance:
- `out_of_budget = yesterday_spend ≥ out_of_budget_util × current_daily_budget` (robust proxy; also honor `DIM_CAMPAIGN.serving_status='CAMPAIGN_OUT_OF_BUDGET'`).
- `y_net_roas = SAFE_DIVIDE(SUM(GROSS_PROFIT), SUM(Ads_cost))` for yesterday; **small-sample guard**: if yesterday clicks < 10, fall back to trailing-7d net ROAS.

| condition | `move_type` | effect |
|---|---|---|
| `y_net_roas < margin_roas_threshold (0.8)` | `BID_CUT` | no budget change; emit `REDUCE_BID −10%` on the campaign's worst keywords (see below) |
| `0.8 ≤ y_net_roas < 2.5` | `BUDGET_UP_10` | `proposed_daily = base_daily × 1.10` |
| `y_net_roas ≥ 2.5` | `BUDGET_UP_30` | `proposed_daily = base_daily × 1.30` |
| not out of budget | `NONE` | keep `base_daily` |

**Worst-keyword targeting (BID_CUT):** within that campaign, keywords with **net profit < 0 over trailing 8wk AND ≥15 clicks** (enough to judge, per existing bar) → `REDUCE_BID −10%`, floored at the CPC band `cpc_min`. Cut **all** that qualify (not top-N) so the campaign's ROAS actually shifts. Reuses the existing `REDUCE_BID` apply path.

**Cap discipline (reallocate within cap):** within each family, if `SUM(proposed_daily) > family_budget`, scale the *increase portion* (`proposed_daily − base_daily`) down pro-rata across the increased campaigns so `SUM(proposed_daily) = family_budget`; non-increased campaigns keep `base_daily` untouched. The weekly waterfall re-bases everything Monday.

### `DE_FLOOR_CAMPAIGN_LOG` + `V_FLOOR_CAMPAIGN_LIFECYCLE`
`DE_FLOOR_CAMPAIGN_LOG(campaign_id, floor_since DATE, last_state STRING, updated_at, updated_by)` — the daily job MERGEs: insert `floor_since = today` the first day a campaign is `is_floor`; delete the row when it stops being a floor campaign (graduated or got a real slice).

`V_FLOOR_CAMPAIGN_LIFECYCLE(campaign_id, floor_since, days_on_floor, state, decision, reason)`:
- `state = STARVED` if yesterday clicks/day < `starved_clicks_per_day (3)`, else `MOVING`.
- While `days_on_floor < 30`:
  - `STARVED` → `decision = RAISE_BID` (reuse PROBE/launch-track bid raise to try to buy clicks).
  - `MOVING` → `decision = WATCH`.
- At `days_on_floor ≥ 30`:
  - `net_roas_30d < 0.6` **OR** still `STARVED` (never reached ≥3 clicks/day) → `decision = CLOSE` (suggest `CAMPAIGN_PAUSE`).
  - else (`MOVING` and `net_roas_30d ≥ 0.6`) → `decision = GRADUATE` (drops out of `DE_FLOOR_CAMPAIGN_LOG`; next waterfall gives it a real profit-share slice).

## Component ③ — one budget engine (reconciliation)

`V_ADS_COACH` / `V_ADS_COACH_CAMPAIGN` currently compute `budget_action` from `camp_budget_util ≥ 90% AND camp_effective_roas ≥ 1.1 → +10/+20%`, `< 0.9 → −15%`. **Replace** that block: the campaign budget suggestion becomes `COALESCE(V_CAMPAIGN_DAILY_MOVE.proposed_daily, V_CAMPAIGN_BUDGET_BASE.base_daily)`, and the reason string comes from the new views. The `BID_CUT` keywords flow into the existing `REDUCE_BID` keyword surface; `CLOSE` flows into the existing `CAMPAIGN_PAUSE` surface. No second budget code path survives.

## UI — new Weekly Run Step 1

A thin step above today's family-budget step:
- **Total daily budget** input (writes `DE_BUDGET_CONFIG.total_daily_budget`), default $700.
- **Family allocation table:** family · 7d net profit · floor · computed daily · **manual override** input (writes a `DE_PRODUCT_BUDGET` MANUAL row). Shows the split live.
- A one-line waterfall summary: `$700 → 6 families → campaigns`.
- Read-only surfacing of floor-campaign lifecycle verdicts (GRADUATE / CLOSE) so Ori sees which floor campaigns are up for a decision.

All numbers come from Cube measures over the new views (`FamilyBudgetAllocation`, `CampaignBudgetBase`, `CampaignDailyMove`, `FloorCampaignLifecycle`). No math in React.

## Cadence / orchestration

- **Daily** (existing job / `SP_REFRESH_CUBE_TABLES` chain): MERGE `DE_FLOOR_CAMPAIGN_LOG`, rebuild T_ tables for the daily-move + lifecycle views so yesterday's offers are ready when Ori opens the Weekly Run.
- **Weekly (Monday) re-base:** recompute `V_FAMILY_BUDGET_ALLOCATION` and write the family budgets into `DE_PRODUCT_BUDGET` (source `WATERFALL`), resetting the cap to $700 and clearing intra-week drift.

## Edge cases / error handling

- All families' 7d net profit ≤ 0 → equal split of the pot (no divide-by-zero).
- A family with 0 campaigns → its budget parks unused (surfaced, not force-spent).
- Yesterday had no ads data yet (lag) → daily move falls back to trailing-7d; if still none, `move_type = NONE`.
- Manual family override that exceeds the total → allowed, but Step 1 shows an "over cap" warning (like today's Step-3 over-budget banner).
- `serving_status` snapshot is stale → the util≥90% proxy is authoritative for out-of-budget.

## Testing

- **SQL:** row-count + sum invariants — `SUM(V_FAMILY_BUDGET_ALLOCATION.allocated) ≈ total_daily_budget`; `SUM(V_CAMPAIGN_BUDGET_BASE.base_daily) per family ≈ family_budget`. **Coverage invariant (hard):** `COUNT(DISTINCT campaign_id) in V_CAMPAIGN_BUDGET_BASE == COUNT(DISTINCT enabled campaign_id)` — no enabled campaign may be missing; unmapped campaigns land in the `Unknown` family, never dropped. Golden-case fixtures for the waterfall math (winners+floor) and each daily-move branch (<0.6 / 0.8–2.5 / ≥2.5).
- **Lifecycle:** fixture campaigns at 10/29/30/31 days on floor across STARVED/MOVING × profitable/losing → assert RAISE_BID / WATCH / CLOSE / GRADUATE.
- **Frontend:** unit-test the Step-1 allocation table renders backend numbers verbatim (no client math); Playwright smoke that the total-budget input persists and the override writes.

## Out of scope (explicit)

- Auto-push to Amazon via the Ads write-API (stays prepare-only).
- Cross-family reallocation *within* a day (families are capped independently; rebalancing is the weekly re-base's job).
- Changing the net-profit / COGS definitions (reuse the KPI card's).

## Resolved at review (2026-07-05)

- **Family net-profit source** ✅ — `V_FAMILY_NET_PROFIT_7D` matches the KPI card's net-profit definition; exact `V_UNIFIED_DAILY` expression to be verified against the data at build time (mechanical, not a design question).
- **Store + Unknown participate** ✅ — Store is a legitimate mixed-family brand spender, so it (and any still-unmapped "Unknown" campaign) is a full family in the waterfall. Every enabled campaign is covered. Product families are weighted by real business net profit; Store/Unknown (no organic P&L) by their ads net profit.
