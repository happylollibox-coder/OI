# Strategy Thresholds — every rule, per strategy

**Date:** 2026-07-17 · **Source of truth:** `DE_COACH_THRESHOLDS` (this doc is a readable snapshot of it)

Every number the coacher uses lives in `DE_COACH_THRESHOLDS`, keyed by
**(threshold_key, strategy_id, coach_mode, product_family)**. Nothing here is hardcoded in SQL or React
— change a value in the table and the engine follows on the next read.

## How a value is chosen

```
1. strategy_id + coach_mode + product_family   (most specific)
2. strategy_id + coach_mode
3. GLOBAL + coach_mode                          ← the fallback almost everything uses
4. hardcoded default in V_ADS_COACH.sql         (last resort)
```

**A strategy only overrides what it needs.** A blank cell below is not "no rule" — it means the strategy
inherits GLOBAL. COMPETITOR, for example, sets only `BID_CAP_SUGGESTION` and runs on GLOBAL for
everything else.

## The strategies (after the 2026-07-17 consolidation)

| strategy | campaigns | what it's for |
|---|---|---|
| **INTENT** | 81 | Intent-grouped offense: one campaign per (family × match-type × intent theme), ≤10 keywords. Merged HUNTER + LOW_COST_DISCOVERY; runs on **HUNTER's rules verbatim**. |
| **EXACT_BOOST** | 24 | Push a proven keyword hard on exact match, high top-of-search. |
| **COMPETITOR** | 14 | Competitor ASIN / category conquest. Renamed from COMPETITOR_CONQUEST; absorbed CATEGORY_CONQUEST. |
| **BRAND_DEFENSE** | 8 | Own the brand SERP. Never negates (`NEGATE_ROAS_THRESHOLD = -999`). |
| **PRODUCT_DEFENSE** | 8 | Cross-sell on own product pages. Never negates. $30 learning floor. |

Defined but unmapped: `SEASONAL_PUSH`, `NEW_LAUNCH`, `TOS_DOMINATION`, `RETARGETING`.

## GLOBAL — the base every strategy inherits

Varies by **coach mode**: GUARDIAN (protect profit) · BLITZ (peak push) · COOLDOWN (ease back after peak).

| threshold | GUARDIAN | BLITZ | COOLDOWN | meaning |
|---|---|---|---|---|
| `PROFITABLE_ROAS` | 1.1 | 1.0 | 1.1 | the bar for "this is working" |
| `SCALE_UP_ROAS` | 2.0 | 1.2 | 999999 | net ROAS above which budget grows (COOLDOWN = never) |
| `SCALE_UP_SPEND_CAP` | 50 | 100 | 0 | max daily spend when scaling |
| `REDUCE_BID_ROAS` | 0.7 | 0.7 | 1.0 | net ROAS below which bids get cut |
| `NEGATE_ROAS_THRESHOLD` | 0.5 | 0.5 | 0.5 | ROAS under which a term is negated |
| `NEGATE_SPEND_THRESHOLD` | 20 | 35 | 10 | $ spent before a term may be negated |
| `WASTED_SPEND_THRESHOLD` | 15 | 25 | 10 | $ of no-order spend that counts as waste |
| `INSUFFICIENT_DATA_CLICKS` | 15 | 10 | 15 | clicks needed before judging |
| `BID_CAP_SUGGESTION` | 2.0 | — | — | hard bid ceiling ($) |
| `PROMOTE_MIN_ORDERS` | 4 | 2 | 999999 | orders needed to promote to exact |
| `PROMOTE_MIN_SQP_VOLUME` | 500 | 300 | 999999 | market volume needed to promote |
| `CONFIDENCE_CLICKS_HIGH` | 50 | 30 | 50 | clicks for a high-confidence verdict |
| `CONFIDENCE_CLICKS_MEDIUM` | 20 | 15 | 20 | clicks for a medium-confidence verdict |
| `CONFIDENCE_DAYS_HIGH` | 14 | 10 | 14 | days for a high-confidence verdict |
| `CONFIDENCE_DAYS_MEDIUM` | 7 | 5 | 7 | days for a medium-confidence verdict |
| `HALO_ROAS` | 0.5 | 0.5 | 0.3 | assumed organic halo per $1 ad spend |

GUARDIAN-only globals (no mode variants): `ACUTE_LOSS_NET` 0 · `BLEEDER_FIT_RANK` 50 ·
`BLEEDER_MIN_CLICKS` 20 · `BLEEDER_REDUCE_PCT` 0.4 · `CROSS_SELL_MIN_ORDERS` 3 ·
`DEFENSE_DOMINATE_IS_PCT` 50 · `ESCALATE_OFF_PLAN_WEEKS` 2 · `ESCALATION_TREND_WEEKS` 8 ·
`NET_COLLAPSE_FRAC` 0.5.

## Per-strategy overrides (GUARDIAN mode)

Blank = inherits GLOBAL.

| threshold | GLOBAL | **INTENT** | EXACT_BOOST | COMPETITOR | BRAND_DEFENSE | PRODUCT_DEFENSE |
|---|---|---|---|---|---|---|
| `PROFITABLE_ROAS` | 1.1 | **1.1** | 1.1 | — | **3.0** | **2.0** |
| `SCALE_UP_ROAS` | 2.0 | **2.0** | 1.5 | — | **5.0** | — |
| `SCALE_UP_SPEND_CAP` | 50 | **30** | 100 | — | — | — |
| `REDUCE_BID_ROAS` | 0.7 | **0.5** | 0.7 | — | — | — |
| `NEGATE_ROAS_THRESHOLD` | 0.5 | **0.3** | 0.3 | — | **−999** | **−999** |
| `NEGATE_SPEND_THRESHOLD` | 20 | **15** | 40 | — | — | — |
| `WASTED_SPEND_THRESHOLD` | 15 | **10** | 25 | — | 5 | 5 |
| `INSUFFICIENT_DATA_CLICKS` | 15 | **15** | 20 | — | 10 | 10 |
| `PROMOTE_MIN_SQP_VOLUME` | 500 | **500** | — | — | — | — |
| `BID_CAP_SUGGESTION` | 2.0 | **2.0** | 2.0 | **2.0** | 2.0 | 2.0 |
| `CONFIDENCE_DAYS_HIGH` | 14 | — | — | — | 7 | — |

Reading the interesting ones:
- **BRAND_DEFENSE `PROFITABLE_ROAS` 3.0 / `SCALE_UP_ROAS` 5.0** — a very high bar, because brand terms
  should convert cheaply; if they don't, something is wrong.
- **`NEGATE_ROAS_THRESHOLD` −999 on both defense strategies** — defense never negates. You cannot
  defend a term you have blocked.
- **INTENT `SCALE_UP_SPEND_CAP` 30 vs GLOBAL 50** — discovery is deliberately capped; it's a net, not
  a scaling engine. Winners graduate to EXACT_BOOST (cap 100).
- **INTENT negates earlier than GLOBAL** (0.3 vs 0.5 ROAS, $15 vs $20) — discovery is expected to
  produce losers, and they should be cut fast.

## Unmapped strategies (defined, no campaigns)

| threshold | SEASONAL_PUSH | NEW_LAUNCH | TOS_DOMINATION | RETARGETING |
|---|---|---|---|---|
| `PROFITABLE_ROAS` | **0.7** | **0.5** | 1.1 | 1.1 |
| `SCALE_UP_ROAS` | 1.0 | 0.8 | 1.5 | 2.0 |
| `SCALE_UP_SPEND_CAP` | 150 | — | — | — |
| `NEGATE_ROAS_THRESHOLD` | 0.3 | 0.2 | — | — |
| `WASTED_SPEND_THRESHOLD` | 30 | 30 | 40 | 10 |
| `INSUFFICIENT_DATA_CLICKS` | 15 | 15 | 20 | 15 |

SEASONAL_PUSH 0.7 and NEW_LAUNCH 0.5 accept losing money — buying position and velocity respectively.

## Launch — being replaced

The `LAUNCH_*` GLOBAL keys are the **old** launch track: `LAUNCH_WINDOW_DAYS` 30 ·
`LAUNCH_BID_MULT` 1.7 · `LAUNCH_BID_CEILING` 1.4 · `LAUNCH_COLD_BID` 1.2 · `LAUNCH_STEP_DOWN_PCT` 0.2 ·
`LAUNCH_CHECKPOINT_CLICKS` 15 · `LAUNCH_NEGATE_CLICKS` 45 · `LAUNCH_WINNER_ORDERS` 2 ·
`LAUNCH_WINNER_DAYS` 3.

The new launch ramp (20 days, $10/$1.00, −7%/+10%) lives in `DE_BUDGET_CONFIG` under `launch_ramp_days`,
`launch_start_bid`, `launch_bid_cut_pct`, `launch_click_trigger`, `launch_budget_raise_pct`,
`launch_raise_roas`, `launch_raise_roas_days`. See `architecture/CAMPAIGN_LAUNCH_RAMP.md`.

**⚠ Both are live.** The ramp owns NEW-tier budgets in Weekly Run step 1; the old `LAUNCH_*` track still
drives launch *bids* through `V_ADS_COACH` → Actions page → bulksheet. Until the ramp's bid ladder gets
a consumer, these two disagree about new-campaign bids.

## Editing

Admin → Threshold editor writes `DE_COACH_THRESHOLDS` (`source='ori'` overrides seeds). Or edit
`scripts/bigquery/tables/DE/DE_COACH_THRESHOLDS.sql` and re-run it to re-seed defaults. Changes take
effect on the next `V_ADS_COACH` read — no deploy.
