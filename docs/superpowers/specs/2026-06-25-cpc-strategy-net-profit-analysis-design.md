# CPC Investment-Strategy → Net-Profit Analysis (per parent product, per calendar part)

- **Date:** 2026-06-25
- **Owner:** Ori
- **Status:** Design approved — pending spec review → plan
- **Type:** Exploratory analysis (not a productionized BQ object, initially)

---

## 1. Question

> Is the current Ads Coach bidding strategy actually good? For each **parent product**, in each **part of the calendar**, which **CPC investment strategy** produces the most **ads-attributed net profit**?

We treat ad bidding as a controllable input (how CPC moves over time) and net profit as the outcome, and ask the data which CPC dynamics pay off best — separately during holidays (stronger customer intent) vs everyday.

This is **observational** data — no randomized assignment of CPC. Conclusions are associational, strengthened by per-target baselining and power gating, not causal proof. That caveat travels with every recommendation.

---

## 2. Decisions locked (from brainstorming)

| Axis | Decision |
|---|---|
| **Outcome** | **Ads-attributed net profit only** = `GROSS_PROFIT − Ads_cost`. No organic halo. |
| **Unit of analysis** | campaign × target (keyword / product-target) × day, rolled up to **parent product**. |
| **Input — CPC** | Keyword-level treatment = **day-over-day CPC movement** (increase / decrease / constant + magnitude). |
| **Input — Top-of-Page** | **Campaign-level covariate** (see §4) — Amazon does not report TOS at keyword grain, and it is only *set* per campaign. |
| **Strategy framing** | **Regime segmentation** (stable-CPC stretches labelled by entry transition) — not discrete pre/post events. "Constant CPC" is a first-class regime type. |
| **Outcome metric** | **Net-profit-per-active-day** within each regime (normalizes regime length), lag-trimmed. |
| **Calendar** | Start fine — per season AND per holiday window (`DIM_US_HOLIDAYS` phases) — then **merge segments whose strategy ranking is statistically indistinguishable** (Phase 3). |
| **Deliverable** | Exploratory first: Python in `tools/` + ad-hoc SQL + charts + written findings. Productionize only what proves useful. |

---

## 3. Data foundation (confirmed against BigQuery, 2026-06-25)

### Outcome + CPC — `OI.FACT_AMAZON_ADS` (keyword × day, via search-term rows)
Grain: `date × campaign_id × ad_group_id × keyword_id × targeting × search_term × placement_type`.
Rolled to the target×day unit:
- `net_profit = SUM(GROSS_PROFIT) − SUM(Ads_cost)`
  - Verified May'26: `GROSS_PROFIT ≈ Ads_sales − COGS` (pre ad cost); `Σ(GROSS_PROFIT−Ads_cost)=$3,818` on `$42,489` spend — razor-thin margin, consistent with the known thin-margin theme.
- `cpc = SUM(Ads_cost) / NULLIF(SUM(Ads_clicks),0)`
- carry `Ads_clicks`, `Ads_orders`, `Ads_units`, `Ads_sales`, `Ads_cost`.
- `target_key = (campaign_id, ad_group_id, COALESCE(keyword_id, targeting))` — `keyword_id` is NULL for auto/product targets (937 keyword_ids / 41.8k keyword-days; broader with `targeting`).

### Top-of-Page covariate — `OI.V_CAMPAIGN_PLACEMENT_REPORT` (campaign × placement × day)
Normalized placement enum incl. `TOP_OF_SEARCH`. Per campaign×day derive:
- `tos_cost_share = TOS cost / total placement cost`
- `tos_cpc`, `tos_roas`
Plus the *set* lever: `DIM_EXPERIMENT_CAMPAIGN.top_of_search_pct` / `V_CAMPAIGN_PLACEMENT_BIDDING.bid_adjustment_pct` (campaign TOS bid-adjustment %). Attached to each target×day by `campaign_id`.

### Calendar — `OI.DIM_US_HOLIDAYS`
Ships per-holiday windows: `pre_season_start`, `boost_start`, `peak_start`, `cooldown_start`, `cooldown_end`, `ramp_up_days`, `category`. Each day → one calendar segment: `{holiday}_PRE | _BOOST | _PEAK | _COOLDOWN`, else `EVERYDAY` (further split by month/season for the "per season" start). Timezone: holidays are `America/New_York`; ads facts are `America/Los_Angeles` — compare on the LA-local `date` and accept the boundary day fuzz (documented).

### Parent attribution
Map each target×day to a parent product via the row's advertised ASIN → `DIM_PRODUCT.parent_name`, taking the **dominant parent by spend** per target (reuse the parent-attribution logic already in `V_ADS_COACH_DATA` rather than re-deriving). Targets that span families are flagged and excluded from per-parent cells.

---

## 4. Method

### Phase 1 — Define strategies (CPC regime taxonomy)
1. For each `target_key`, build the daily series on active days (`Ads_clicks > 0`).
2. Smooth CPC with a 3-day median to damp auction noise.
3. **Regime boundary** when smoothed CPC shifts beyond `max(±15%, ±$0.10)` and the new level holds ≥2 active days, OR after an inactivity gap ≥ G days (default 5).
4. **Intersect regimes with calendar segments** so each regime-segment lies in one calendar phase.
5. Label each regime by its entry transition vs the prior regime level:
   - `CPC_INCREASE`, `CPC_DECREASE`, `CONSTANT`; first regime = `LAUNCH`; post-gap restart = `REACTIVATE`.
   - Magnitude tier on the % delta: `SMALL` (<25%), `MEDIUM` (25–60%), `LARGE` (>60%).
6. Per regime-segment record: CPC level, transition, magnitude, days, clicks, orders, spend, sales, **net profit**, and the campaign TOS covariate (avg `tos_cost_share`, `top_of_search_pct`).

A "**strategy**" = `transition × magnitude` (e.g., `CPC_INCREASE·MEDIUM`, `CONSTANT`). TOS covariate is a secondary split applied only where data allows.

### Phase 2 — Power check ("enough examples")
- Cell = `parent × calendar-segment × strategy`.
- Thresholds (tunable): a cell needs **≥5 independent regime-segments** AND **≥200 clicks** AND **≥10 orders** to be "conclusive". Orders are the binding constraint on thin margin — expect many thin cells.
- Output a coverage matrix marking each cell `CONCLUSIVE / WEAK / EMPTY`. This drives the Phase-3 merge and is a deliverable in its own right (it tells Ori where we simply cannot conclude yet).

### Phase 3 — Analyze
- Primary comparison: **net-profit-per-active-day** distribution by strategy, within each `parent × calendar-segment`, vs that parent's `CONSTANT`/`EVERYDAY` baseline.
- Report effect size + dispersion (median, IQR, n); use a non-parametric rank comparison (small-n, non-normal $/day). No p-value theater — flag "directional" vs "robust".
- **Merge** calendar segments whose per-strategy ranking is statistically indistinguishable (e.g., holiday `_PRE` collapses into `EVERYDAY` for a parent if its strategy ranking matches) — your "if same behaviour, merge".
- Cross-tab the TOS covariate: does high `tos_cost_share` change which CPC strategy wins?

### Phase 4 — Recommend
For each `parent × (merged) calendar-part`:
- The net-profit-maximizing CPC strategy, with a **confidence flag** from Phase 2.
- **Head-to-head vs the current coacher**: what `V_ADS_COACH`/`FACT_PPC_CHANGE_LOG` actually did in comparable cells, and the net-profit gap — the direct answer to "is the current strategy good."
- Where data is `WEAK/EMPTY`: say so plainly and recommend a deliberate test, not a guess.

---

## 5. Deliverables
- `tools/analysis/cpc_strategy_profit/` — atomic Python: (a) build enriched target×day base (SQL), (b) regime segmentation, (c) power matrix, (d) analysis + merge, (e) recommendation table.
- `.tmp/` intermediates (regime table, cell matrix) — not committed.
- A written findings doc (`architecture/` or `docs/`) with the per-parent/per-calendar recommendation table, the coverage matrix, charts (net-profit-per-day by strategy; CPC-vs-net-profit per parent), and the coacher comparison.
- No new BQ objects in v1. If a regime/enriched-base view proves reusable, register it in `config.yaml` in a follow-up.

---

## 6. Risks & honest limits
- **Observational, not causal.** CPC moves conflate our bid changes with auction dynamics. Mitigation: per-target baselining; optional cross-ref to set-bid (`V_SRC_AmazonAds_keyword`) / logged changes (`FACT_PPC_CHANGE_LOG`, but only since 2026-06-11).
- **9 months, single holiday occurrences.** Most holiday×parent cells will be under-powered → Phase 2 will mark them WEAK; Phase 3 merge and family-level pooling are the fallback. We will not over-claim on one Prime Day.
- **Thin margin / sparse orders** make net-profit-per-day noisy at fine grain — orders are the binding power constraint.
- **TOS is campaign-grain**, so its effect is coarser than CPC's and only suggestive at keyword level.
- **Attribution lag** (1–2d ads + up to 14d conversion): trim the last 2 days and require lag-complete windows; recent regimes reported as provisional.

## 7. Out of scope (v1)
- Organic/halo profit (ads-only by decision).
- Auto-feeding results into the coacher engine (separate follow-up once a strategy is validated).
- Non-US marketplaces (US-only warehouse).
- Bid-level (vs realized-CPC) treatment as the primary lever — realized CPC is primary; set-bid is only a cross-reference.
