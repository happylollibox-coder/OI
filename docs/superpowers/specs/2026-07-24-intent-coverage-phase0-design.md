# Phase 0 — Intent coverage on the ads search-term universe

Date: 2026-07-24
Status: **Implemented 2026-07-24.** Gate cleared: classified share of ads clicks 11.1% → 70.32%.
Owner: Ori

> **Changed during implementation.** The draft proposed a new `DE_INTENT_RULES` table. It was
> not built. `DE_INTENT_THEMES` (created 2026-07-16 for the intent-campaign model) already has
> the required shape — regex, priority, is_active, and a `holiday_name` FK to `DIM_US_HOLIDAYS`
> — and already carries a `back-to-school` theme. Building a parallel rule table would have
> split the vocabulary across two places and put `V_INTENT_KEYWORDS` and the new ads-side view
> on different rules. Instead `DE_INTENT_THEMES` gained one additive column, `match_ads_regex`.
> The sections below describe what was built.

## Why

Ori wants the system to learn a 12-month CVR curve per product × intent, and to set the base
bid from it (`base_bid = CVR × gross_profit_per_order × target_profit_share`). That model is
keyed on intent. Today intent cannot carry it.

`V_SEARCH_TERM_SEGMENT` — the only source of `occasion` and `intent_segment` — is built from
`FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` (SQP) at
[V_SEARCH_TERM_SEGMENT.sql:32](../../../scripts/bigquery/views/V_SEARCH_TERM_SEGMENT.sql).
The CVR signal lives in `FACT_AMAZON_ADS`, a much larger universe. Measured 2026-07-24 over
the trailing 365 days:

| Metric | Value |
|---|---|
| Distinct ads search terms | 201,054 |
| …with a row in `V_SEARCH_TERM_SEGMENT` | 13,579 (6.8%) |
| Ads clicks with a row | 50.2% |
| **Ads clicks with a real occasion** (non-null, not `NO_OCCASION`) | **11.1%** |

The missing traffic is not noise — it is the better traffic. LolliME, Aug 1 – Sep 28 2025:

| Bucket | Terms | Clicks | Orders | CVR | GP/click |
|---|---|---|---|---|---|
| Tagged `BACK_TO_SCHOOL` | 47 | 90 | 2 | 2.22% | $0.20 |
| School text, **not** tagged | 232 | 265 | 12 | 4.53% | **$0.72** |
| Everything else | 7,599 | 15,955 | 772 | 4.84% | $0.56 |

SQP only reports terms with real search volume, so the tag captures head terms
("school supplies for girls" — browsers) and misses the long-tail buyers
("back to school gift for 7 year old girl", "school journal for girl") that convert on the
first click. Pricing back-to-school off the tagged slice yields $0.20/click → a 14¢ bid →
switch the channel off. Pricing off real school traffic yields $0.72/click → a 50¢ bid,
against a $0.36 CPC that historically returned 4.15 ROAS.

Two failure modes, both must be fixed:

1. **Coverage** — 73% of school terms have no row at all. Rules are applied to the wrong universe.
2. **Rule width** — even with coverage, the back-to-school pattern is
   `back to school|school supplies`, which misses "school journal for girl",
   "middle school girls gifts", "personal drawing school kit for kids".

There is also an ordering defect: `birthday` is tested before `back to school`, so
"9 year old girl birthday gifts school supplies" classifies as BIRTHDAY.

## Goal

Every ads search term gets an intent classification, computed from its own text, with an
auditable rule table.

**Gate metric:** share of trailing-365-day ads clicks carrying a non-null occasion.
Today **11.1%**. Phase 1 does not start until this is **≥ 60%** with spot-check precision
≥ 90% on a 100-term sample. (60%, not 90% — a large share of terms genuinely have no
occasion, and forcing one would be worse than leaving it null. `NO_OCCASION` counts as
classified only once we trust the rules.)

## Design

Three objects. No changes to existing views in this phase.

### 1. `DE_INTENT_THEMES.match_ads_regex` (new column)

Migration: `scripts/bigquery/migrations/2026-07-24_intent_theme_ads_regex.sql`.

An RE2 pattern matched against `LOWER(FACT_AMAZON_ADS.search_term)`. Additive — existing
columns and `V_INTENT_KEYWORDS` behaviour are untouched, and a theme with a NULL
`match_ads_regex` simply never matches on the ads side (attribute-only themes such as
`match_product_type = 'Beauty'` cannot be resolved from raw text).

Seeded for 28 themes: the occasion and holiday themes at priority 10-20, the reliably
text-identifiable product types (journal-diary, stationery, keychain, gift-sets, bath-spa,
crafts-diy, board-game, party-supplies, care-package, mystery-box, advent-calendar), and the
bare `gift` fallback. Left narrow on purpose — a wrong product-type tag is worse than none,
because it steers campaign grouping.

Back-to-school is the widening that started this work:
`back to school|school suppl|\bschool\b`. The old pattern was `back to school|school supplies`,
which caught the browsers and missed every buyer.

**Priority is load-bearing.** `back-to-school` was moved from 10 to **25** during
implementation. Its bare `\bschool\b` arm is greedy, and at priority 10 it stole
"high school grad party gifts for girls" from `graduation` and "middle school girl halloween
gift basket" from `halloween`. At 25 every other occasion theme (10-20) resolves first and
back-to-school only claims terms no other occasion wants. This is why routing defects are a
data fix here, not a code change.

### 2. `V_ADS_SEARCH_TERM_INTENT` (new view)

Grain: one row per distinct `FACT_AMAZON_ADS.search_term` (201,054 of them).

Match rule: `match_ads_regex` must match, AND `match_keyword_regex` must also match when it is
non-null and different — so `christmas-gift` needs both the christmas pattern and `\bgifts?\b`.

Specificity routing, same principle as `V_INTENT_KEYWORDS` — one term gets exactly ONE theme:
`ads_specificity DESC` (1, +1 when `match_keyword_regex` adds a second independent condition),
then `priority ASC`, then `intent_key`. So `christmas-gift` outranks both `christmas` and
`gift`, and `back-to-school` (25) beats `journal-diary` (30) for "school journal for girl".

Emits `ads_specificity`, `matched_priority`, `candidate_theme_count` and `is_unclassified` so
any classification can be traced back to why it won.

Deliberately not joined to SQP. This view is the authority for ads-side work;
`V_SEARCH_TERM_SEGMENT` stays the authority for SQP-side work. No attempt to reconcile them.

### 3. `V_INTENT_COVERAGE` (new view)

The gate, as a query. Grain `parent_name × intent_key` over the trailing 365 days, with
`FAMILY_TOTAL` and `ACCOUNT_TOTAL` rollups via GROUPING SETS.

**Always filter on `row_type`** (`THEME` | `UNCLASSIFIED` | `FAMILY_TOTAL` | `ACCOUNT_TOTAL`).
The first cut of this view omitted that column and the genuinely-unclassified bucket was
indistinguishable from the rollups — both carry a NULL `intent_key`, and reading the gate
naively returned duplicate family rows at 0%.

Carries `cvr_pct`, `cpc` and `gp_per_click` per theme, so an intent's economics are readable
without writing a join.

## Result (2026-07-24)

Classified share of trailing-365-day ads clicks, `V_INTENT_COVERAGE`:

| Scope | Terms | Clicks | Classified |
|---|---|---|---|
| **All families** | 201,054 | 833,230 | **70.32%** (was 11.1%) |
| Fresh | 41,278 | 105,142 | 83.11% |
| Lollibox | 116,586 | 461,765 | 73.02% |
| LolliME | 51,607 | 198,597 | 62.96% |
| Bottle | 28,367 | 67,726 | 53.67% |

Precision: 25/25 correct on a random sample across back-to-school, graduation,
christmas-gift, journal-diary and sleepover, after the priority fix. All seven known misses
now classify.

The point of the exercise, visible for the first time — LolliME `back-to-school`:

| | Clicks | CVR | CPC paid | GP/click | ROAS |
|---|---|---|---|---|---|
| In season (Aug 1 – Sep 28) | 351 | 3.70% | $0.37 | **$0.56** | **4.20** |
| Out of season | 2,519 | 1.75% | $0.51 | **$0.21** | 1.12 |

Blended it reads as a loser, which is why the existing profit gate in `V_INTENT_KEYWORDS`
dropped it. Split by season it is profitable for eight weeks and loses money for the other
forty-four — roughly $1,285 spent out of season to return $529 of gross profit, on one family.

This is the case for Phase 1: the bid has to be a function of intent AND month, not a blend.

## Phase 1 (also shipped 2026-07-24)

Advisory only — nothing writes to a campaign.

**`V_INTENT_CVR_CURVE`** — grain product × intent_key × month_of_year (1-12), always fully
populated. Multiplicative rather than a lookup, because at product × intent × month only 25%
of cells clear 100 clicks:

```
cvr_hat(product, intent, month) = base_cvr(product, intent) × season_index(intent, month)
```

`base_cvr` is Beta-binomial shrunk `(orders + k·parent) / (clicks + k)` up product × intent →
family × intent → intent → global. `season_index` shrinks intent × month toward that intent's
own all-month rate and divides by it, so no seasonal signal lands on exactly 1.00 — the honest
default. Season is pooled across products deliberately: back-to-school is a property of the
intent, not of the journal, and pooling gives the shape roughly 10× the data.

The learned back-to-school shape, with no hand-holding:

| Month | Jan | Feb | Mar | Apr | May | Jun | **Jul** | **Aug** | Sep | Oct | Nov | Dec |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| season_index | 1.06 | 0.89 | 0.93 | 0.61 | 0.99 | 0.70 | **0.68** | **1.45** | 1.11 | 0.82 | 1.23 | 1.46 |

That is the Jul-vs-Aug split this whole investigation started from, recovered from the data
rather than typed in. December at 1.46 is the Q4 gift demand that lands on the same keywords.

**`V_INTENT_BID_BASE`** — `value_per_click = cvr_hat × gp_per_order`, then two distinct numbers:

- `max_bid` = value_per_click — the **breakeven ceiling**. Pay more and the click loses money.
- `target_bid` = value_per_click × `INTENT_BID_PROFIT_SHARE` (0.70) — the bid that also hits
  the margin goal.

The first cut collapsed these and was wrong in both directions: it called money-losing months
"tighten", and it called a target below market "run" when we would never win the auction.
`action` now reads OFF when the market clears above breakeven, RUN_THIN between target and
breakeven (profitable but under goal — a judgement call, not a cut), RUN otherwise.

Purple LolliME × back-to-school: **OFF for eleven months, RUN_THIN in August alone**
(max 0.41 / target 0.29 / market 0.38). September flips to OFF because the market at $0.37
sits just above its $0.32 breakeven.

Discrimination check: `journal-diary` and `gift` price at $0.90–1.74 max bid against a $0.65
blended CPC and come back RUN. Action mix across all cells above INSUFFICIENT confidence:
RUN 1,069 / RUN_THIN 433 / OFF 718.

Knobs in `DE_COACH_THRESHOLDS`, `strategy_id = 'INTENT'`: `INTENT_BID_PROFIT_SHARE` 0.70,
`INTENT_CVR_BASE_PRIOR_CLICKS` 200, `INTENT_CVR_SEASON_PRIOR_CLICKS` 500,
`INTENT_BID_CEILING` 2.00, `INTENT_BID_FLOOR` 0.15.

## Testing

- **Golden set**: ~100 hand-labelled terms drawn from real ads traffic, weighted toward the
  long tail, stored as a fixture. Asserts precision and recall per occasion.
- **Regression on the head**: terms that today classify via `V_SEARCH_TERM_SEGMENT` must
  classify the same way, unless the change is a deliberate rule fix with a note.
- **The seven known misses** from this investigation are test cases:
  `back to school gift for 7 year old girl`, `school journal for girl`,
  `personal drawing school kit for kids`, `school supplies gift sets`,
  `middle school girls gifts`, `9 and 11 year old girls gifts school`,
  `11 year old girl gifts school`.
- **Coverage assertion**: `V_INTENT_COVERAGE` occasion share ≥ 60%.

## Out of scope

No CVR model, no bid changes, no coach changes, no forecast changes, no campaign changes.
No edits to `V_SEARCH_TERM_SEGMENT`. No new occasion values — the existing nine stand.

## Value independent of Phase 1

Even if the CVR curve is never built, this phase makes intent-level negatives and
intent-segmented campaigns possible, which they are not today at 11% coverage. It is
worth shipping on its own.

## Open questions

1. Should `V_ADS_SEARCH_TERM_INTENT` be materialised as `T_`? Cube reads `T_` tables, and
   201k terms × regex is not free. Recommend measuring first, materialising only if slow.
2. `age_group` and `product_match` are also computed in `V_SEARCH_TERM_SEGMENT` and have the
   same coverage problem. Recommend leaving them out of Phase 0 to keep it small, but the
   rule table should be shaped so they can be added as further `dimension` values later.

## Follow-ups noted during this investigation (not in scope)

- `V_FORECAST_DEMAND.sql:41` and `:193` filter `category = 'gift_season'`;
  `V_PEAK_RELEVANCE.sql:16` filters `IN ('gift_season','prime_event')`. Back to School
  (`back_to_school`) and Halloween (`seasonal`) are invisible to both engines. Do **not**
  add back-to-school to the forecast — measurement showed it is a targeting window, not a
  demand event.
- `DE_FAMILY_OCCASION_OVERRIDE` with `is_active = FALSE` cannot suppress an auto-detected
  occasion. The final `WHERE` in `V_FAMILY_OCCASION_MAP.sql` is
  `lift_ratio >= 1.3 OR (override AND is_active)` — the first branch still passes the row.
  The override can only add, never remove.
- `is_occasion_in_season` in `V_SEARCH_TERM_SEGMENT.sql:327-338` maps only 4 of 8 occasions
  and gives the rest a blanket `TRUE`. Its window is `pre_season_start → holiday_date`,
  which for most occasions is not where conversion actually happens.
