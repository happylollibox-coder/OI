# Per-Product Strategy Profile (Coacher sub-project B)

- **Date:** 2026-06-25
- **Owner:** Ori
- **Status:** Design approved — pending spec review → plan
- **Parent vision:** dashboard coacher that (1) defines a strategy per product parent, (2) makes a daily plan, (3) performs it, (4) checks net profit and escalates. This spec is **sub-project B: define the per-product strategy** — the spine. Foundation (A), gap-fill/probes (C), daily plan (D), guardrail (E), execution (F) are separate.
- **Builds on:** this session's CPC/match-type findings, recorded in [[project_cpc_strategy_net_profit_analysis]] and `architecture/CPC_STRATEGY_FINDINGS_2026-06.md`.

---

## 1. Goal

Give the coacher an explicit, per-product strategy it **steers toward**, instead of reactively nudging bids. For each product parent, define — per season and match type — the target CPC, the profitable band, which match types to run, and how to launch a new keyword; anchored on each product's proven main keywords. Seed it from the analysis; let Ori override.

## 2. Decisions locked (from brainstorming)

| Axis | Decision |
|---|---|
| **Grain** | `parent_name × season (PEAK/OFF) × match_type`, anchored on per-product **main keywords**. |
| **Main keywords** | Derived anchors (top net-profit / volume head terms per product×match-type), editable. |
| **How it drives** | **Steer toward target** — clamp the coacher's recommended bid into `[cpc_min, cpc_max]`, bias toward `cpc_target`; **hard-suppress** disabled match types (no bid-up). |
| **Seeding** | **Derived + editable** — `SP_REFRESH_PRODUCT_STRATEGY` fills DERIVED rows from the analysis; MANUAL edits preserved. |

## 3. Architecture

```
analysis logic (this session)                      Ori (data-entry app)
        │ SP_REFRESH_PRODUCT_STRATEGY                    │ edits (source='MANUAL')
        ▼ (fills DERIVED rows only, preserves MANUAL)    ▼
 DE_PRODUCT_MAIN_KEYWORDS    ─┐
 DE_PRODUCT_STRATEGY_PROFILE  ┘── LEFT JOIN ──▶ V_ADS_COACH_DATA → V_ADS_COACH
                                  (by parent × season × match_type)
                                  → steer bid into band, suppress disabled match types
```

Follows the existing pattern: the coacher already LEFT-JOINs `DIM_STRATEGY_TEMPLATE` by `strategy_id` for `recommended_bid_min/max` and pivots thresholds by `(strategy_id, coach_mode)`. The profile is a **per-product override layer COALESCEd over those generic defaults.**

## 4. Tables

### 4.1 `DE_PRODUCT_MAIN_KEYWORDS` — anchor keywords per product
| column | type | notes |
|---|---|---|
| parent_name | STRING NOT NULL | product family |
| keyword_text | STRING NOT NULL | the term |
| keyword_id | STRING | Amazon keyword id (nullable for auto/product) |
| match_type | STRING NOT NULL | BROAD / EXACT / PHRASE / AUTO / PRODUCT |
| rank | INT64 | 1 = top anchor within (parent, match_type) |
| net_profit_90d | FLOAT64 | evidence used to rank |
| is_anchor | BOOL | TRUE = managed as a main keyword |
| source | STRING | DERIVED / MANUAL |
| updated_at | TIMESTAMP | |
| updated_by | STRING | |

Grain: one row per (parent_name, keyword_text, match_type). Append/update, never `CREATE OR REPLACE` (preserve MANUAL rows).

### 4.2 `DE_PRODUCT_STRATEGY_PROFILE` — the levers
| column | type | notes |
|---|---|---|
| parent_name | STRING NOT NULL | |
| season | STRING NOT NULL | PEAK / OFF |
| match_type | STRING NOT NULL | BROAD / EXACT / PHRASE / AUTO / PRODUCT |
| enabled | BOOL NOT NULL | FALSE → suppress (no bid-up); seeded FALSE where net_per_dollar ≤ 0 |
| cpc_target | FLOAT64 | steer toward this |
| cpc_min | FLOAT64 | lower clamp |
| cpc_max | FLOAT64 | upper clamp |
| launch_cpc | FLOAT64 | start bid for a new keyword of this match type |
| raise_pace_pct | FLOAT64 | % to raise per step toward target (used by launch track) |
| net_per_dollar | FLOAT64 | evidence: Σnet / Σcost over the season |
| confidence | STRING | CONCLUSIVE / WEAK (from the power gate) |
| tos_target_pct | FLOAT64 | nullable — populated once foundation A (targeting_keyword_report) lands |
| borrowed_from | STRING | nullable — sub-project C |
| source | STRING NOT NULL | DERIVED / MANUAL / BORROWED |
| updated_at, updated_by | TIMESTAMP, STRING | |

Grain: one row per (parent_name, season, match_type) — ≈ 4 parents × 2 seasons × ≤5 match types.

## 5. Derivation — `SP_REFRESH_PRODUCT_STRATEGY`

Reads the same keyword×day base used by the analysis (`FACT_AMAZON_ADS` → net profit = `GROSS_PROFIT − Ads_cost`, season from `DIM_US_HOLIDAYS` boost/peak = PEAK else OFF, parent via `ASIN_BY_CAMPAIGN_NAME` → `DIM_PRODUCT.parent_name`, match_type from `targeting_type` normalized). Last 90d (configurable).

**Main keywords:** per (parent, match_type), rank keywords by `net_profit_90d` desc; top N (default 10) → `DE_PRODUCT_MAIN_KEYWORDS` with `is_anchor=TRUE`, `source='DERIVED'`.

**Profile, per (parent × season × match_type):**
- `net_per_dollar` = Σnet_profit / Σcost.
- `enabled` = `net_per_dollar > 0` (auto-suppresses EXACT on Fresh/Lollibox).
- `cpc_target` = volume-weighted CPC of the **most profitable CPC band** for that cell (from the band analysis); `cpc_min`/`cpc_max` = the contiguous band edges where net_per_dollar stays > 0.
- `launch_cpc` = the match-type **traffic floor** (lowest CPC band where ≥ ~55% of keyword-days get clicks); `raise_pace_pct` default 15%.
- `confidence` = CONCLUSIVE if (≥5 regimes, ≥200 clicks, ≥10 orders) else WEAK.

**Override preservation:** MERGE that updates only rows where `source='DERIVED'` (or absent); never overwrites `source='MANUAL'`. (Same discipline as `SP_DERIVE_PRODUCT_SEGMENTS`.)

## 6. Steering integration (`V_ADS_COACH_DATA` / `V_ADS_COACH`)

1. Derive `season` for each row from the existing `coach_mode` (BLITZ / peak-relevant → PEAK; GUARDIAN / COOLDOWN / default → OFF).
2. LEFT JOIN `DE_PRODUCT_STRATEGY_PROFILE` on `(parent_name, season, match_type)`.
3. **Bid band:** `strategy_bid_min` / `strategy_bid_max` become `COALESCE(psp.cpc_min, stmpl.recommended_bid_min)` / `COALESCE(psp.cpc_max, stmpl.recommended_bid_max)`. The final `recommended_bid` is clamped into this band (the existing outer `LEAST(..., bid_cap)` is extended with `GREATEST(cpc_min)` / `LEAST(cpc_max)`), and biased toward `cpc_target` when within band.
4. **Suppression:** when `psp.enabled = FALSE` **and** `psp.confidence = 'CONCLUSIVE'` (don't act on thin/noisy negatives), target-level bid-up actions (`INCREASE_BID`) are blocked for those keywords — capped at `MONITOR_TARGET`, and money-bleeders there route to `REDUCE_BID`/`STOP_TARGET` as today. A WEAK-negative cell applies the band only, no suppression. A decision-trace chip records "suppressed by product strategy: {parent}/{season}/{match_type} net/\$ {x}".
5. **Anchor:** main keywords (join `DE_PRODUCT_MAIN_KEYWORDS`) are flagged `is_main_keyword` so the band/steer applies to them first; non-anchor long tail keeps generic handling.

All rules stay in the engine SQL (per [[feedback_coacher_rules_in_engine]]); the dashboard only reflects.

## 7. Seed values (from this session, for sanity-checking the SP output)

| Parent | Match-type guidance | CPC target (peak / off) |
|---|---|---|
| **LolliME** | run all incl EXACT (only product where exact profits, +$4.8k) | peak $0.9–1.1 / off $0.6–0.8 |
| **Fresh** | BROAD + PRODUCT/ASIN; **suppress EXACT** (−$502) | peak $0.5–0.8 / off $0.5–0.6 |
| **Lollibox** | AUTO + BROAD; **suppress EXACT** (−$3,086) | peak ≤$1.0 / off ≤$0.7 |
| **Bottle** | BROAD + PHRASE; keep cheap | ≤$0.6 both seasons |

Business-wide: most profitable band $0.50–0.60; off-season net profit turns negative above ~$0.80.

## 8. Scope

**In:** the two tables, `SP_REFRESH_PRODUCT_STRATEGY`, and the steering join in `V_ADS_COACH_DATA`/`V_ADS_COACH`. Register all in `config.yaml`. Data-entry CRUD for both tables.

**Deferred (columns exist, populated later):** `tos_target_pct` (needs foundation A / `targeting_keyword_report`); `borrowed_from` + borrow-similar logic (sub-project C).

## 9. Risks & limits
- **Clicks-only data** (same caveat as the analysis): `launch_cpc`/traffic-floor derivation is approximate until foundation A lands; flag in the SP.
- **Thin cells** → WEAK confidence; the steering should treat WEAK rows softly (band only, no aggressive suppression) to avoid acting on noise. Suppression fires only on CONCLUSIVE negative cells.
- **Selection effects** in the source analysis (raising winners) — the profile encodes associations, not proven causation; Ori's MANUAL overrides are the safety valve.
- Observational, US-only.

## 10. Testing
- `SP_REFRESH_PRODUCT_STRATEGY`: run against a synthetic keyword×day fixture; assert per-cell `enabled`/`cpc_target`/`confidence` match expected, and that a pre-seeded `source='MANUAL'` row is left untouched.
- Steering SQL: row-count parity before/after the join (no fan-out); every `recommended_bid` for a profiled row lands within `[cpc_min, cpc_max]`; `enabled=FALSE` cells emit zero `INCREASE_BID`; a decision-trace chip is present.
- Seed sanity: SP output matches the §7 table directionally (EXACT suppressed for Fresh/Lollibox, enabled for LolliME).
