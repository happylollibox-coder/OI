# Coacher × Plan Integration — Handoff Brief

> Paste this into the new conversation. Goal: make the **Ads Coacher (Actions page)
> plan-aware** so it reacts to last-week performance against the plan.
>
> **Status: Phase 1 + Phase 2A are DONE and committed** on `feat/offseason-forecast`
> (commits `453fb9e`, `bb42b1e`, `f06c996`, `c9914ca`, `6b0dced`, `b31ff81`). Pick up at **2B**.

---

## 0. The model (decided with the owner this session)

- **Plan = daily guidelines, not hard targets.** Stored daily already (`daily_spend_target`, `cpc_target`).
- **Inputs the coacher steers (levers):** daily ad **spend** + **CPC** → these ARE compared to the plan.
- **ROAS / ad ROAS = measured RESULTS** (≈2-day lag), **NOT** taken from the plan. Judged on their own
  "good" bar, never vs `predicted_roas`.
- **Actuals window = last week** (last 7 days for spend/CPC; ROAS is 4w ad-only — see open item).
- **Reaction is mode-aware** (the coacher has modes): a good ROAS → push to grow net profit by
  **increasing daily spend** ("scale"); a bad one → "cut". The bar follows the mode.

---

## 1. Where the plan data already lives (persisted by the Plan wizard)

The Plan wizard already writes everything the coacher needs:

| Table | Cube | Grain | Key fields |
|---|---|---|---|
| `DE_PLAN_STRATEGY` | `PlanStrategy` ✅ exists | family × month | `strategy`, `multiplier`, `target_roas`, `base_roas`, `status` (DRAFT/APPROVED), `plan_year/version`, `forecast_year/month` |
| `DE_PLAN_ADS_TARGETS` | ❌ **no cube yet** | family × month × channel | **`daily_spend_target`** (planned ad cost/day), **`cpc_target`** (planned CPC), **`predicted_roas`** (planned ROAS), `predicted_cvr`, `predicted_units`, `predicted_net_profit`, `ads_share`, `season_type`, `multiplier_k`, `plan_strategy_id` |
| `DE_FORECAST_SNAPSHOT` | — | product × month | frozen units when a plan is APPROVED |

- Flask read already exists: `GET /api/plans/ads-targets/<family>` (data-entry-app/app.py:5048).
- **`DE_PLAN_ADS_TARGETS` is the gold mine** — it has planned ad cost, CPC, ROAS per family-month-channel.

## 2. Current Actions page (the coacher UI)

- File: `dashboard-react/src/pages/ActionsPage.tsx`, rendered `<ActionsPage data={data} matchAction=… />`.
- Reads from `DashboardData`: `data.actions` (ActionRow[] — per term/keyword recs), `data.coach_decisions`, `data.coach_strategy`, `data.hot_signals`, `data.coach_phrase_negatives`.
- **Already** groups by family (`getFamily`, `famFilter`, `famTotalSpend`) and is month-aware (`today = new Date()`).
- **Neither plan cube is loaded into DashboardData yet** — that's the wiring to add.

## 3. Coacher backend (for the phase-2 logic)

- Views: `V_ADS_COACH`, `V_ADS_COACH_DECISION`, `V_ADS_COACH_ACTIONS`, `V_ADS_COACH_DATA`, `V_ADS_COACH_CAMPAIGN`, `V_ADS_COACH_PHRASE_NEGATIVES`, `V_ADS_COACH_SEASONAL_CAMPAIGNS`.
- SP: `SP_REFRESH_ADS_COACH_ACTIONS`. Cubes: `AdsCoachActions/Decision/Campaign/Strategy`, `CoachHotSignals`, `CoachThresholds`. MCP: `oi-coach`.

---

## 4. Implementation plan

### Phase 1 — Actions page *sees* the plan ✅ DONE (`453fb9e`)
- **Cube** `cube/schema/PlanAdsTargets.js` over `DE_PLAN_ADS_TARGETS` (hot-reloads; `data.plan_ads_targets`).
- Loaded via `useCubeData.ts` loader `loadPlanAdsTargetsFromCube` (light-loader idx 36) → `DashboardData.plan_ads_targets`; type `PlanAdsTargetRow` in `types.ts`; empty default in `useUnifiedData.ts`.
- `monthlyPlanTargets(rows, year, month)` helper (planTypes.ts, TDD) → per family {dailyCost, cpc, roas}.
- `ActionsPage` "Per Family Breakdown" shows `Plan Jun: $110/d · CPC $0.45` per family.
- ⚠️ `config.yaml`: the `PlanAdsTargets` cube reads an existing table, so no new BQ object — but you may still want to note the cube there (owner edits config.yaml; left untouched).

### Phase 2A — last-week actuals + mode-aware reaction ✅ DONE
- Per family, under the plan line, a **Last 7d** line (shows even for unplanned families, with `· no plan yet`):
  - **Spend/d + CPC** = last 7 days from `daily_trends` (ad_cost & clicks are ad-only) → colored delta vs plan levers via `planDelta()` (TDD). *Avoid `ads_7d` (it's 180-day) and the term-spend sum (double-counts).*
  - **ROAS** = last 4w ad-only (spend-weighted over coach term rows) → `adRoasSignal(roas, mode)` (TDD) → **scale / hold / cut**, colored, **independent of the plan**.
- **Mode-aware bar** in `MODE_ROAS` (planTypes.ts), mirroring the coach's own budget rules:
  GUARDIAN scale≥1.1/cut<0.9 · BLITZ scale≥1.0 · COOLDOWN never scales, hold≥0.8. Header shows `· {mode} mode`.

### Phase 2B — the engine enacts it (NEXT)
1. **Live thresholds:** replace the `MODE_ROAS` constants with `CoachThresholds` (per-mode, per-season) so the bar is owner-tunable, not hard-coded.
2. **Spend lever → action:** turn "↑ scale budget" into a real campaign/family budget recommendation
   (GUARDIAN +10%, BLITZ +20%, etc. — the coach already has these labels in `utils.ts`); "↓ cut spend" → decrease. Wire into the DoQueue / coach actions.
3. **CPC lever:** the coach's recommended bids should aim at the plan's `cpc_target` (per channel — needs a branded/non-branded classifier per term, `DIM_BRAND_PHRASES`).
4. **Engine join:** push plan `daily_spend_target` / `cpc_target` into `V_ADS_COACH_DECISION` / `V_ADS_COACH_DATA` + `SP_REFRESH_ADS_COACH_ACTIONS` so decisions are plan- and last-week-aware server-side (production deploy = owner OK).
5. **Open item — ROAS window:** spend/CPC are last-7d but ROAS is last-4w (ad-only). No ad-only 7d ROAS is loaded (daily_trends ROAS is blended/halo). To unify, add a last-7d ad-only ROAS by family from the `Ads` cube. Also honor the **2-day ROAS lag** (don't react to the most recent 1–2 days).
6. **"Hold or beat":** good ROAS shouldn't just hold the target — propose *beating* it (scale for more net profit). Bad ROAS → a corrective plan (cut/bid-down) before scaling.

### Phase 3 (bonus) — OOS-aware coaching
- From this session's stock work: pause/reduce ads on ~0-sellable (FBA) products
  (e.g. Fresh in Pink burning ~$90/day on an empty shelf). Join sellable FBA stock
  (`InventorySnapshot`) into the coach decision → emit a **"PAUSE — OOS"** action.

---

## 4b. Reusable building blocks already in place (planTypes.ts, all TDD'd)

- `monthlyPlanTargets(rows, year, month)` → `Map<family, {dailyCost, cpc, roas}>` (blends channels).
- `planDelta(actual, plan, tol=0.1)` → `{pct, status: over|under|on|none}` (the spend/CPC vs-plan deltas).
- `adRoasSignal(roas, mode)` → `{action: scale|hold|cut}` + the `MODE_ROAS` per-mode threshold map.
- `data.plan_ads_targets` (`PlanAdsTargetRow[]`) is loaded app-wide — no re-plumbing needed.
- `effectiveCoachMode` (ActionsPage) = the dominant `coach_mode`; `coachFilter` overrides it.

---

## 5. Context: the plan side was just upgraded (this session)

- Forecast anchor = **run-rate × seasonal shape**, now **stockout-corrected** (skips OOS weeks → uses last healthy in-stock weeks).
- Family margin no longer collapses to $0 when OOS; Ads-Path STOCK chip splits **sellable (FBA)** vs **incoming pipeline**.
- So the plan/ads-targets the coacher reads already reflect the corrected demand.

## 6. Constraints (carry over)

- Branch `feat/offseason-forecast`; commits are **local, not pushed**.
- Never `git add -A`/`.` (exact files only); commit `--no-verify`; node via nvm full PATH; **don't push**; production SQL deploy needs explicit OK.
- Register every new BQ object (cube/view) in `config.yaml`.
- TDD pure logic; live-verify in the preview before claiming done.
