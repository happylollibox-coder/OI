# Data Foundation + TOS-Aware Bidding (Coacher sub-project A)

- **Date:** 2026-06-26
- **Owner:** Ori
- **Status:** Design approved — pending spec review → plan
- **Parent vision:** the per-product coacher. This is sub-project **A — data foundation** (the trust unlock), scoped to **foundation + TOS-aware bidding**.
- **Builds on:** [[project_coacher_product_strategy_profile]] (B/B.2) and [[project_cpc_strategy_net_profit_analysis]]. Closes the audit-#5 "TOS-blind bidding" gap from [[project_coach_audit_findings]].

---

## 1. Goal

Give the coacher the keyword-level signals it's currently blind to — **true impressions (incl. no-traffic days)**, **top-of-search impression share**, and a clean keyword-day performance source — from `fivetran-hl.amazon_ads.targeting_keyword_report`, and use the TOS signal to add one new behavior: **bid up profitable-but-buried keywords toward a per-product top-of-search target**.

(The coacher already has the real *set bid* via `keyword_history.bid`; A's value is impressions / TOS / no-traffic, not the bid.)

## 2. Decisions locked (from brainstorming)

| Axis | Decision |
|---|---|
| **A v1 scope** | Foundation (keyword-day source + exposed signals) **+ TOS-aware bidding**. |
| **TOS target** | **Curated, seeded from data** — per cell, seed `tos_target_pct` from the TOS share the cell's already-profitable keywords achieve; editable. Not a derived "optimum." |
| **No-traffic** | Signal **exposed** (visibility) in v1; a no-traffic-driven action is deferred. |
| **CPC bands** | Stay clicks-only-sourced for now; re-deriving them on the report is a separate follow-on. |

## 3. `V_KEYWORD_DAILY` (new view)

Keyword×day from `targeting_keyword_report`. Grain: `campaign_id × ad_group_id × keyword_id × date`.
- Passthrough: `keyword_bid`, `impressions`, `clicks`, `cost`, `cost_per_click`, `click_through_rate`, `top_of_search_impression_share`, `units_sold_clicks_14_d`, `sales_14_d`, `ad_keyword_status`.
- Derived: `parent_name` (campaign→`ASIN_BY_CAMPAIGN_NAME`→`DIM_PRODUCT.parent_name`, the standard `camp_parent` mapping); `keyword_text` (join `keyword_history` on `id = keyword_id`); `no_traffic` = `impressions = 0`; `net_proxy = sales_14_d − cost` (a heuristic "winning" flag for TOS-target seeding only — true net stays the coacher's job).
- A view (like `V_CAMPAIGN_PLACEMENT_REPORT`); the report is small (~10k rows). Register in `config.yaml`.
- **Why it matters:** it includes the impression-only (37%) and zero-impression (3%) keyword-days that `FACT_AMAZON_ADS` (clicks-only) drops.

## 4. Signals exposed to the coacher

A per-keyword 8-week aggregate (lag-trimmed, last 2 days dropped) of `V_KEYWORD_DAILY`, LEFT-JOINed into `V_ADS_COACH_DATA` by `keyword_id`:
- `target_tos_share` — impression-weighted avg `top_of_search_impression_share` (position signal),
- `target_impressions_8w` — true impressions,
- `no_traffic_rate` — share of the keyword's days with zero impressions (starved signal; surfaced only).

Propagate to the view output (and the decision trace) like the other `target_*` columns.

## 5. `tos_target_pct` derivation (fills the deferred profile column)

Derived by `tools/strategy_profile` (same pipeline that derives the bands), written into `DE_PRODUCT_STRATEGY_PROFILE.tos_target_pct` per `parent × season × match_type × intent_class`:
- For each cell, among its **net-profitable** keyword-days (using the analysis net or `net_proxy`), take the **impression-weighted 75th-percentile `top_of_search_impression_share`** as the target ("match what your winners reach, with headroom").
- Fall back to the `parent × season` level when a cell is thin; NULL when no profitable data.
- `source='MANUAL'` rows preserved (editable), same as the rest of the profile.

## 6. TOS-aware bid decision (the new behavior)

In `V_ADS_COACH`, add an `INCREASE_BID` trigger:

> when a keyword is **profitable** (passes the existing profit bar / has orders) **AND** `target_tos_share < tos_target_pct` **AND** `current_bid < ceiling` → `INCREASE_BID`, with `recommended_bid` stepped toward `LEAST(cpc_max-if-steers-else-$2-ceiling, th_bid_cap)`.

- Reuses the existing bid-up computation and the band/ceiling clamp from B (so it can't run away; capped at the $2 global ceiling, or the product band max when the profile steers).
- Mirrors the existing `BRAND_DEFENSE` TOS bid-raise, generalized to profitable non-defense keywords, using the real ads TOS signal (`target_tos_share`) instead of SQP impression share.
- Adds a `tos` chip to the decision trace ("buried: TOS x% < target y%").
- Does **not** fire for unprofitable keywords, already-dominant keywords (`target_tos_share ≥ tos_target_pct`), suppressed GENERIC cells, or paused targets. REDUCE/STOP branches unchanged.
- Catches the concrete case from the analysis: LolliME journal-kit head terms — profitable but sitting at ~1.4% top-of-search.

## 7. Scope

**In:** `V_KEYWORD_DAILY`, the three exposed signals, `tos_target_pct` derivation, the TOS bid-up, config.yaml registration.
**Deferred:** a no-traffic/starved-keyword action; re-deriving the CPC *bands* on the report (bands stay clicks-only-sourced); a dashboard surface for the new signals.

## 8. Risks & limits
- **TOS isn't independently controllable** — bidding up doesn't guarantee position (the analysis showed exact head terms stuck at ~7% TOS even at $1 bids). So the TOS bid-up is capped at the ceiling and gated on profitability; it nudges, it doesn't force. Watch that it doesn't just buy more buried impressions.
- **`net_proxy` (sales−cost) is a heuristic**, used only to seed TOS targets; the real profit gate stays the coacher's net-ROAS.
- **Join grain**: `targeting_keyword_report` is keyword-targeting only — product/auto/category targets aren't covered (no `keyword_id` there), so the TOS signal applies to keyword targets; auto/product targets keep current behavior. Acceptable (TOS bidding is a keyword concept).
- **Attribution lag**: 8-week aggregate is lag-trimmed (drop last 2 days), same as elsewhere.
- Observational, US-only.

## 9. Testing
- `V_KEYWORD_DAILY`: row parity vs the raw `targeting_keyword_report` (since 2025-09-23); `no_traffic` correctly TRUE on zero-impression rows; `parent_name` populated for keyword-targeting campaigns.
- TOS aggregate: impression-weighted `target_tos_share` matches a hand check on one keyword; `no_traffic_rate` ∈ [0,1].
- `tos_target_pct`: per-cell values are in [0,100] and seeded from profitable-keyword TOS; a MANUAL row survives a re-derive.
- TOS bid-up (live validation): fires `INCREASE_BID` for a known profitable + low-TOS keyword (e.g. a LolliME journal head term), does NOT fire for an unprofitable or already-dominant one; every TOS-driven `recommended_bid ≤ ceiling`; coach-view row-count parity preserved; `reduce_inversions = 0` unchanged.
