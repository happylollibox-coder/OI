# Rolling Weekly Plan — Purpose-Driven Learning Loop (Coacher sub-project D)

- **Date:** 2026-06-27
- **Owner:** Ori
- **Status:** Design approved (revised) — pending spec review → plan
- **Parent vision:** the per-product coacher. **D** is the "create/update a plan → perform → check → learn" loop between strategy (B/C) and the net-profit guardrail (E).
- **Builds on:** B/B.2 strategy profile ([[project_coacher_product_strategy_profile]]), C gaps/borrow/probe ([[project_coacher_gaps_borrow_probe]]), `V_ADS_COACH`, the business plan (`DE_PLAN_STRATEGY`/`V_PLAN_FORECAST`), `DIM_US_HOLIDAYS`. Mirrors the outcome pattern of `V_PRODUCT_STRATEGY_OUTCOMES` / the PPC close-the-loop.

---

## 1. Problem

The coacher produces live per-keyword decisions, but there is **no plan** and **no learning**: no forward view of what to pursue over the coming weeks, no record to check last week against, and no memory of what has worked per product. D adds a **rolling weekly plan at the strategy-cell grain**, where **every item states its purpose** and is judged by **the metric that purpose implies**, and whose **results feed back so each iteration's plan improves**.

## 2. Core model (locked from brainstorming)

**Grain:** the plan is written per **`parent × season × match_type × intent`** — the same cell grain as the strategy profile (B) and gaps (C), so plan ↔ strategy ↔ gaps ↔ actions line up 1:1. Season is carried by the week (each week in the horizon is peak or off, and pulls that season's cells).

**Every plan item carries a PURPOSE (the incentive / "why"), and the success metric follows the purpose** — net profit is only one of several:

| Purpose | Success metric ("on plan" means…) | Judged at |
|---|---|---|
| `SCALE` (grow a profitable cell at its target CPC) | net profit ≥ expected | **cell → aggregated to product** |
| `MAP` / `ESTABLISH` (e.g. Bunny EXACT) | **15 clicks** gathered, then graduate — *not* profit | cell |
| `PROBE` / `EXPLORE` (C's probe) | 15 clicks / 14 days | cell |
| `DEFEND` (brand) | hold top-of-search / impression share | cell |
| `CUT` (bleeders) | wasted spend reduced (spend ↓, net ↑) | cell |
| `HOLD` (TOS-brake at target) | maintain position/net, no churn | cell |

Every metric is measured at the **cell grain**; the product view is the roll-up (SCALE net profit sums cells → product; thin cells land `INCONCLUSIVE` in learnings rather than polluting the product verdict).

**SCALE ↔ target CPC (one feedback loop with B).** SCALE operationalizes the per-cell target CPC from `DE_PRODUCT_STRATEGY_PROFILE`: the plan item operates the cell at its **`cpc_target`** (+ band) and its **`expected_value` (net profit) = `net_per_dollar × planned_spend`** at that CPC. The review measures both actual net profit **and** the actual achieved CPC vs `cpc_target`. The learning closes back to B — if at target CPC the cell underdelivers, recalibrate `cpc_target` down; if it beats expectation with CPC headroom, push it up. B sets the target CPC; D operates at it, measures, and tunes it.

**Learning loop:** plan → act → measure (per purpose's metric) → **learn** (accumulate what works per product/cell/purpose) → **next plan improves** (calibrate expectations + re-assign purposes from the track record). History is retained, never overwritten.

**Budget-first.** The plan **starts from a budget** (per product, the weekly spend ceiling) before any actions. The budget is **allocated across the product's cells by purpose** (SCALE weighted by opportunity / `net_per_dollar`; MAP/PROBE a small exploration slice; DEFEND its share) — that allocation is each cell's **`planned_spend`**, which drives the SCALE expected net profit. Configured Amazon daily budgets ≈ `weekly_budget / 7`, but actual can exceed the configured daily by up to ~2× (Amazon flexes high-traffic days, balancing over the month), so the budget is a **control lever + soft ceiling**, not a hard cap — the review tracks actual-vs-budget and flags overspend early.

| Axis | Decision |
|---|---|
| Budget | Per-product weekly ceiling (editable, optionally seeded from the business plan); allocated to cells by purpose → `planned_spend`. |
| Cadence / horizon | Weekly, rolling; current week + next 3. |
| Granularity | Current week = specific (cell actions + expected results); future weeks = high-level (cell objectives). |
| Net-profit expectation | Bottom-up coacher trend, **calibrated from realized history**, reconciled to the business-plan target (flag divergence). |
| Authorship | System-proposed, editable (MANUAL preserved). |
| Scope | Plan/act for the 4 advertised parents; **MAP targets may name currently-unadvertised products** (e.g. Bunny) — execution of those is **F**. Deeper auto-adjust + escalation on persistent OFF_PLAN is **E**. |

## 3. Component 1 — the plan (`DE_WEEKLY_PLAN`, cell grain, history-retained)

One row per `week_start × parent_name × season × match_type × intent` (the active season's cells for each week in the horizon):
- `week_start` (Mon, America/Los_Angeles), `horizon` (`CURRENT` | `FUTURE`).
- **`purpose`** (`SCALE`/`MAP`/`PROBE`/`DEFEND`/`CUT`/`HOLD`) — always set.
- `objective` — short text ("establish EXACT coverage for Bunny", "scale Fresh EXACT winners").
- **`success_metric`** (`NET_PROFIT`/`CLICKS`/`TOS_SHARE`/`SPEND_DOWN`/`HOLD`) + **`expected_value`** (the target number for that metric).
- **`target_cpc`** — for SCALE items, the cell's operating CPC carried from `DE_PRODUCT_STRATEGY_PROFILE.cpc_target` (NULL for non-SCALE purposes).
- **`planned_spend`** — the cell's slice of the product budget (Component 0); the spend envelope its actions operate within and the basis for SCALE expected NP.

**Component 0 — the budget (`DE_PRODUCT_BUDGET`).** One editable row per `parent_name × week_start`: `weekly_budget` (the product's spend ceiling), `source` (`MANUAL` | `BUSINESS_PLAN`), `updated_at`. The generator allocates it across the product's active cells by purpose → each cell's `planned_spend`. This is the entry point of the whole plan: no budget → no planned spend → no expected results.
- `expected_net_profit`, `plan_net_profit` (business-plan target for the week) — populated for product-level reconciliation regardless of item purpose.
- `coach_mode_hint` (GUARDIAN/BLITZ/COOLDOWN from the calendar).
- `source` (`DERIVED`|`MANUAL`), `status` (`PROPOSED`|`ON_PLAN`|`OFF_PLAN`|`MET`|`MISSED`), `updated_at`, `updated_by`.
- **History retained:** rows are keyed by `week_start`, so past weeks persist with their realized status — this is the learning corpus. MANUAL edits preserved (DELETE only `source='DERIVED'` for the *current+future* weeks; never delete past weeks).

## 4. Component 2 — the plan generator (`tools/weekly_plan/`)

Python tool (same pattern as `tools/strategy_profile`): derive → load (preserving MANUAL + past weeks). For the current + next 3 weeks, per active cell:
- **Allocate the product budget (Component 0) to cells → `planned_spend`:** SCALE cells weighted by opportunity (`net_per_dollar` × room-to-grow), MAP/PROBE a small fixed exploration slice, DEFEND its historical share, CUT ~0. Sum of cell `planned_spend` ≤ product `weekly_budget`. Translate to configured Amazon daily budgets ≈ `planned_spend / 7` (knowing actual can flex to ~2× daily).
- **Assign purpose from strategy + gaps + learnings:** a CONCLUSIVE profitable cell → `SCALE`; a weak/missing gap cell (from `V_STRATEGY_GAPS`) → `MAP`/`PROBE`; a brand cell → `DEFEND`; a bleeder → `CUT`; a TOS-dominant cell → `HOLD`. **`V_PLAN_LEARNINGS` (Component 5) overrides:** a cell whose `MAP` has repeatedly failed to convert after its clicks → switch to `CUT`; a `SCALE` that consistently beats expectation → keep/raise.
- **Set `expected_value` from realized history** (calibrated), not a naïve guess: SCALE expected NP = the cell's `net_per_dollar` × planned spend **at its `cpc_target`** (carried into `target_cpc`); MAP/PROBE = 15 clicks; etc.
- **expected_net_profit (trend)** per product, season-adjusted, reconciled to `V_PLAN_FORECAST`.
- Run by `SP_ORCHESTRATE_DAILY_REFRESH` (weekly cadence); idempotent for the current+future window.

## 5. Component 3 — measure, review & learn

**`V_WEEKLY_PLAN_REVIEW`** (last completed week, per plan item): compute the **actual** value of the item's `success_metric` and compare to `expected_value`:
- `SCALE`/NET_PROFIT → actual weekly net profit **per cell** vs expected (then summed to the product roll-up); `ON_PLAN` if `actual ≥ tol × expected` (tol seeded 0.90 in `DE_COACH_THRESHOLDS`), else `OFF_PLAN`; also record **actual achieved CPC vs `target_cpc`**; plus `vs_business_plan = BELOW_TARGET` when product `actual < plan_net_profit`.
- `MAP`/`PROBE`/CLICKS → clicks accumulated (joins `DE_PROBE_LOG` / `V_KEYWORD_DAILY`); `MET` at ≥ 15, else `OPEN`/`MISSED` (14-day).
- `DEFEND`/TOS_SHARE, `CUT`/SPEND_DOWN, `HOLD` → their respective actuals.
- **Budget adherence (every cell/product):** actual spend vs `planned_spend` / `weekly_budget`; flag `OVERSPEND` early when the run-rate trends over the ceiling (Amazon front-loads up to ~2× the configured daily), so it can be pulled back mid-week rather than discovered after the fact.
- Writes `status` + `actual_value` back onto the reviewed week's `DE_WEEKLY_PLAN` rows (building the corpus). **Persistent OFF_PLAN/MISSED is the hand-off signal to E.**

**`V_PLAN_LEARNINGS`** (the memory that makes next plans better): per `parent × season × match × intent × purpose`, aggregate the **track record across all completed weeks** — attempts, success rate, realized metric (net-per-dollar / click-yield / etc.), realized-CPC-vs-target, and a `verdict` (`WORKS` / `DOESNT` / `INCONCLUSIVE`). The generator (Component 2) reads this to calibrate `expected_value`, **recalibrate the SCALE `target_cpc`** (under-delivering at target → lower it; beating it with CPC headroom → raise it — the loop back to B), and re-assign purposes. *This is the "learn what works per product and improve" loop.*

## 6. Component 4 — actions + expected results (`V_WEEKLY_PLAN_ACTIONS`)

A view over `V_ADS_COACH` for the **current week**, each keyword action grouped under its cell's plan item, carrying the cell's `purpose` and an `expected_result` string derived from purpose + the action (e.g. SCALE INCREASE_BID → "+volume at held ROAS, ~$X net"; MAP/PROBE → "reach 15 clicks to decide"; CUT REDUCE_BID → "cut ≈ $X/wk wasted").

## 7. Component 5 — surface

Per product, reusing the **Home Brief** plain-language pattern (no full new page in v1): a "This Week's Plan" card per parent showing, grouped by purpose: the **on/off-plan status vs last week**, **expected vs actual** for each purpose's metric, the **business-plan flag**, the **actions & expected results**, the **strategic/MAP targets**, a compact **forward-3-week** strip, and a **"what we've learned"** line from `V_PLAN_LEARNINGS`. Backed by a Cube loader over the review/actions/learnings views. A dedicated full Plan page is a fast-follow.

## 8. Scope

**In:** `DE_PRODUCT_BUDGET` (per-product weekly ceiling, editable); `DE_WEEKLY_PLAN` (cell grain, history-retained, purpose + success_metric + expected_value + target_cpc + planned_spend); `tools/weekly_plan/` generator (budget allocation → planned_spend) (purpose assignment + history-calibrated expectations, reads `V_PLAN_LEARNINGS`); `V_WEEKLY_PLAN_REVIEW`; `V_PLAN_LEARNINGS`; `V_WEEKLY_PLAN_ACTIONS`; the lightweight per-product surface; `config.yaml`; tolerance in `DE_COACH_THRESHOLDS`.
**Deferred:** auto-adjust/escalation on persistent OFF_PLAN (**E**); executing MAP targets for unadvertised products / creating campaigns (**F**); a dedicated full Plan page; future-week *action-level* detail.

## 9. Risks & limits

- **Purpose mis-assignment** propagates a wrong yardstick; mitigated because purpose is editable and `V_PLAN_LEARNINGS` corrects it over iterations.
- **Net profit = ads-attributed** (`GROSS_PROFIT − Ads_cost`), consistent with the coacher's net (not the full P&L). Stated explicitly.
- **Learning needs history** — `V_PLAN_LEARNINGS` is thin until several weeks accumulate; early plans lean on strategy/gaps, not yet on learnings (cold start, like C).
- **Week boundary** Monday LA; review runs on completed weeks only (orders/ads watermark, [[feedback_oi_orders_vs_ads_watermark]]).
- **Amazon budget overspend:** a configured campaign daily budget can be exceeded up to ~2× on a given day (Amazon balances over the calendar month), so `weekly_budget` is a soft ceiling enforced by the configured-budget lever + early overspend flagging, not a hard guarantee. Setting configured budgets conservatively (with a buffer) and watching the run-rate is the mitigation.
- Observational, US-only.

## 10. Testing

- `DE_WEEKLY_PLAN`: generator produces current + 3 future weeks per active cell, each with a `purpose` + `success_metric` + `expected_value`; peak weeks carry BLITZ `coach_mode_hint`; MANUAL rows and past weeks preserved on re-run.
- Purpose→metric: a CONCLUSIVE profitable cell gets `SCALE`/NET_PROFIT; a `V_STRATEGY_GAPS` weak cell gets `MAP`/CLICKS with `expected_value=15`; a brand cell gets `DEFEND`/TOS_SHARE.
- `V_WEEKLY_PLAN_REVIEW`: a SCALE product with actual NP ≥ 0.90×expected → `ON_PLAN`, below → `OFF_PLAN`; a MAP cell with ≥15 clicks → `MET`; `vs_business_plan=BELOW_TARGET` when actual < plan target; status written back; one row per item (no fan-out).
- `V_PLAN_LEARNINGS`: a cell+purpose with repeated success shows `verdict=WORKS`; a repeatedly-missed MAP shows `DOESNT`; the generator flips that cell's next purpose away from MAP.
- `V_WEEKLY_PLAN_ACTIONS`: every current-week `V_ADS_COACH` action appears once under its cell with a non-null purpose-derived `expected_result`.
- Surface: the per-product card renders status + expected-vs-actual + actions + a learnings line for a sampled parent.
