# Intent CVR curve: recency, holiday phase, and an index registry

**Date:** 2026-08-31 · **Status:** design approved by Ori, not yet implemented
**Supersedes nothing.** Modifies `V_INTENT_CVR_CURVE`; leaves its grain and every downstream
consumer intact.

## 1. Why

`T_INTENT_BID_BASE` is the catalog of willingness-to-pay per intent. It is used to price bids.
Measured against what actually happened, it under-prices a click by **1.69x**: it says a click is
worth **$0.387** where the realised value over the following week was **$0.655** (2,107
keyword-weeks, $159,056 of spend, Jan-Aug 2026, clicks-weighted).

Consequence, simulated on the same data with a rule of "cut if realised CPC exceeds
`target_bid`": the rule fires CUT on **708 of 730** keyword-weeks (97%) and **395 of those cuts
land on traffic that was profitable** (54% of all verdicts). Capping spend at `target_bid` would
have retained 3.6% of spend and forgone **$23,205** of profit.

The catalog is not useless — it *ranks* correctly. Sorted into quintiles by predicted value, the
realised value per click rises monotonically 0.419 -> 0.594 -> 0.713 -> 0.786 -> **0.976** and net
ROAS rises 0.944 -> 1.484. It knows which intents are worth more. It does not know what they are
worth.

## 2. Three defects, each measured

### D1 — `season_index` is inert

`INTENT_CVR_SEASON_PRIOR_CLICKS = 500`, applied at `intent_key x month_of_year`. Of 45,168 such
cells, **0.9% have >= 500 clicks**, 2.8% have >= 100, and the **median cell has 0**. Everything
shrinks to the intent's own all-month rate.

Result across the 122,124 catalog rows: **85.3% of `season_index` values fall between 0.95 and
1.05**; sd 0.0678; p05 0.909, p95 1.058. The seasonal layer contributes nothing.

### D2 — `month_of_year` cannot represent a moving holiday

Easter fell **2025-04-20** and **2026-04-05** — 15 days apart, which moves the peak across the
month boundary. Same intent, same product (`easter` x White Lollibox):

| year | month | clicks | actual CVR | `cvr_hat` | actual/predicted |
|---|---|---|---|---|---|
| 2025 | 3 | 4,341 | 0.691% | 2.892% | 0.24 |
| 2025 | 4 | 11,820 | 2.504% | 2.806% | 0.89 |
| 2026 | 3 | 3,218 | **5.562%** | 2.892% | **1.92** |
| 2026 | 4 | 2,922 | **6.434%** | 2.806% | **2.29** |

March 2025 was pre-peak (peak began 03-31); March 2026 was peak (peak began 03-16). Re-keyed on
the phase windows already present in `DIM_US_HOLIDAYS`, a consistent shape appears that the month
key destroys:

| phase | 2025 clicks | 2025 CVR | 2026 clicks | 2026 CVR |
|---|---|---|---|---|
| PRE | 527 | 0.380% | — | — |
| BOOST | 2,575 | 0.544% | 1,091 | 1.925% |
| **PEAK** | 7,166 | **2.972%** | 7,675 | **6.984%** |
| COOLDOWN | 612 | 4.575% | 975 | 4.718% |

**~5x swing from BOOST to PEAK within each year.**

Scope: only **8.3% of cost / 9.2% of clicks** carry a `holiday_name`. D2 affects that slice.

### D3 — full-history pooling with no recency weight

`obs` pools all history "on purpose". Account CVR was 3.476% in 2025 and 3.981% in 2026, and
per-intent the drift is far larger (`easter` PEAK: 2.972% -> 6.984%). Pooling anchors 2026
predictions to 2025 performance. **D3 affects 100% of the catalog** and is the largest of the
three by coverage.

Walk-forward test, 499 product x intent cells over 24 months, predicting each cell's next month
from its history, weighted by clicks:

| estimator | weighted abs error | bias (pred/actual) | predictions |
|---|---|---|---|
| **flat full history, k=200 — ships today** | **1.3402%** | **0.830** | 1,300 |
| nested 1/3/6/12/24m, k=400 | 1.3001% | 0.852 | 1,352 |
| **nested 1/2/3/6/12m, k=400** | **1.2583%** | 0.869 | **1,350** |
| exponential half-life 4m, k=400 | 1.2302% | 0.880 | 1,287 |
| exponential half-life 3m, k=400 | 1.2101% | 0.890 | 1,278 |

Two corrections to prior assumptions, both measured:

- **More shrinkage helps, not less.** k=400 beats k=200 beats k=0 at every decay shape. The
  original "over-shrinking" hypothesis was false.
- **Exponential's lower error is partly an easier subset** — it scores 60-70 fewer cells because
  decay thins evidence below the floor. Nested retains them.

A residual **~13% under-bias survives every shape**, because shrinking toward a global prior pulls
scored cells (which are the larger, better-converting ones) downward. It is removed by an explicit
multiplicative calibration.

## 3. Decision

**Approach A — keep the `product x intent x month_of_year` grain, fix the content.**

Rejected: (B) adding a phase dimension to the key, and (C) a date-keyed season view. Both are more
correct; both break the uniqueness assumption that `T_INTENT_BID_BASE`, the intent-grid popup,
`tools/intent_grid/build_tier_a.py`, `tools/intent_grid/absorb_existing.py` and
`tools/intent_grid/backtest_2025.py` rely on. **C is the eventual target**; A is what ships now.

The cost of A: the curve is correct for one year ahead and must be rebuilt when
`DIM_US_HOLIDAYS` rolls forward. A month straddling two phases receives a clicks-weighted blend.

## 4. Architecture

The curve stops being a hardcoded formula and becomes a base estimator times a **registry of
indexes**.

```
cvr_hat = calibration x base_cvr(product, intent) x PRODUCT( index_i )   for every ACTIVE index i
```

### 4.1 Index contract

Every index is a view named `V_INTENT_IDX_<name>` emitting:

| column | type | rule |
|---|---|---|
| *join keys* | — | any subset of `parent_name`, `product_short_name`, `intent_key`, `intent_type`, `month_of_year` |
| `index_value` | FLOAT64 | **normalised so its clicks-weighted mean is 1.000** |
| `support_clicks` | INT64 | evidence behind the cell |

Normalisation is load-bearing: an un-normalised index silently shifts the catalog's level and the
calibration factor absorbs it, hiding the change. Absent cells default to `1.0`, so an index may
be sparse without punching holes in the curve. An index whose `support_clicks` falls below
`INTENT_IDX_MIN_SUPPORT` is shrunk toward 1.0 rather than trusted.

### 4.2 New objects

| object | type | purpose |
|---|---|---|
| `DE_INTENT_INDEX_REGISTRY` | BASE TABLE | one row per index: `index_name` (PK), `description`, `source_object`, `join_keys` (CSV), `is_active` BOOL, `added_at`, `added_by`, `notes` |
| `V_INTENT_IDX_SEASON_MONTH` | VIEW | today's `season_index`, re-pooled at `intent_type x month_of_year` |
| `V_INTENT_IDX_SEASON_PHASE` | VIEW | holiday-phase index projected onto `intent_key x month_of_year` |
| `V_INTENT_INDEX_SCORECARD` | VIEW | walk-forward verdict per index per month |
| `V_INTENT_BASE_TUNING` | VIEW | walk-forward error/bias over a grid of base parameters |
| `SP_SCORE_INTENT_INDEXES` | PROCEDURE | refreshes the scorecard and tuning tables |
| `V_INTENT_CVR_CURVE_SHADOW` | VIEW | the rebuilt curve, unpromoted |

All must be registered in `OI/config.yaml`.

### 4.3 Changed objects

- **`V_INTENT_CVR_CURVE`** — `obs` gains the nested weighting; the hardcoded `season` CTE is
  replaced by a join over active registry indexes; `cvr_hat` gains the calibration factor.
- **`SP_REFRESH_SEARCH_TERM_INTENT`** — rebuilds `T_INTENT_CVR_CURVE` from the new view; gains a
  call to `SP_SCORE_INTENT_INDEXES`.
- **`V_INTENT_BID_BASE`** — one change only, see §7.

### 4.4 New thresholds (`DE_COACH_THRESHOLDS`, `strategy_id = 'INTENT'`)

| key | value | note |
|---|---|---|
| `INTENT_CVR_RECENCY_WINDOWS` | `1,2,3,6,12` | nested month windows, summed |
| `INTENT_CVR_BASE_PRIOR_CLICKS` | 200 -> **400** | measured |
| `INTENT_CVR_SEASON_PRIOR_CLICKS` | 500 -> **derived** | re-derived against pooled cell sizes during implementation; 500 is unusable at the new grain |
| `INTENT_CVR_CALIBRATION` | **1.151** | = 1 / 0.869, refit periodically |
| `INTENT_IDX_MIN_SUPPORT` | **100** | per-cell: an index cell with fewer clicks shrinks toward 1.0 |
| `INTENT_IDX_MIN_SCORED_CLICKS` | **500** | per-month: below this the scorecard returns INSUFFICIENT rather than a verdict |

`INTENT_CVR_CALIBRATION` **will drift** — the account's CVR and AOV both moved more than 30% this
year. It is a threshold row with a refit query, never a literal in SQL.

## 4.5 AMENDMENT 2026-08-31 — two errors found by the Task 3 implementer

Task 3 came back BLOCKED against its own acceptance bar. Both causes are defects in this spec.

### Error 1: R06 and R07 were mutually contradictory

R06 pins each index to a clicks-weighted mean of **1.000 per `intent_key`**. R07 demanded
`MAX(index_value) >= 1.5` for `easter`. Measured, `easter`'s phase click shares are:

| phase | clicks | click share | CVR | index (unshrunk) |
|---|---|---|---|---|
| **PEAK** | 24,875 | **70.9%** | 4.149% | **1.206** |
| BOOST | 6,652 | 19.0% | 1.037% | 0.301 |
| COOLDOWN | 2,029 | 5.8% | 4.485% | 1.304 |
| PRE | 997 | 2.8% | 0.602% | 0.175 |
| OFF | 530 | 1.5% | 1.698% | 0.494 |

**Scope note.** Those absolute counts are UNSCOPED — they omit the view's own filters
(`campaign_id <> '-1'`, `parent_name IS NOT NULL / != 'UNKNOWN'`, launch-ramp quarantine). Measured
at the view's actual scope the totals are **21,052 clicks with 14,841 in PEAK = 70.5%**. The
conclusion is unaffected: PEAK is ~70% of clicks either way. Flagged because a reader reproducing
these numbers from the view's own scope will get the smaller set.

With PEAK at ~70% of clicks, a mean of 1.000 caps PEAK's index at **1/0.705 = 1.42**, reachable
only if every other phase were exactly 0. **`MAX >= 1.5` is unattainable for any `k_season`.**

The signal is nonetheless intact and large — **PEAK/BOOST = 4.0x**, PEAK/PRE = 6.9x. It simply
expresses as "off-season is 0.18-0.30" rather than "peak is 5x", because the mean it is normalised
against is itself peak-dominated. That is correct behaviour: `base_cvr` already carries the
peak-weighted level, so the index's job is to say how far each month departs from it.

**R07 is measuring the wrong statistic.** It is replaced by a RATIO test:

```sql
-- R07 THE PHASE INDEX SEPARATES PEAK FROM TROUGH. A mean-1.000 contract caps the maximum at
--     1/peak_click_share (1.41 for easter), so testing MAX is testing the normaliser, not the
--     signal. What must survive is the SPREAD: unshrunk, easter runs PEAK 1.206 against BOOST
--     0.301, a 4.0x swing. If the ratio collapses the moving-holiday fix has done nothing and
--     V_INTENT_CVR_CURVE keeps pricing Easter peak week off a pre-peak March average.
r07 AS (
  SELECT CAST(COALESCE(SAFE_DIVIDE(MAX(index_value), NULLIF(MIN(index_value),0)), 0) < 2.0
              AS INT64) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` WHERE intent_key = 'easter'
)
```

### Error 2: this index needs its own prior

`INTENT_CVR_SEASON_PRIOR_CLICKS = 4038` was derived in Task 2 for `intent_type x month`, where a
cell holds 100k+ clicks. The phase grain is 33x smaller:

| grain | cells | p25 | median | max |
|---|---|---|---|---|
| `intent_type x month` (Task 2) | 36 | 4,038 | 7,163 | — |
| **`intent_key x phase` (Task 3)** | **99** | **13** | **123** | **15,465** |

At 4038 the prior swamps every cell: easter's real 4.0x PEAK/BOOST swing arrived as 1.85x. New
threshold **`INTENT_PHASE_PRIOR_CLICKS = 123`** (this grain's median). Task 2's p25 rule would give
13, which is too little shrinkage for a 13-click cell — but thin cells are already neutralised
downstream by `INTENT_IDX_MIN_SUPPORT = 100` in the shadow curve, so the prior only has to handle
the middle of the distribution, and the median does that.

**Generalised lesson for the registry: a prior belongs to a grain, not to the system.** Any future
index must derive its own from its own cell distribution. Reusing another index's constant is the
same class of error as the `k_season = 500` defect this project exists to fix.

### Also recorded, not blocking

- `back-to-school` and `halloween` carry NULL `cooldown_start`/`cooldown_end` in `DIM_US_HOLIDAYS`,
  so `phase_of` cannot resolve them and they produce no rows. The curve COALESCEs them to 1.000.
- Latent: `GENERATE_DATE_ARRAY(..., DATE_ADD(..., INTERVAL 11 MONTH))` ends on the *first* of the
  twelfth month, so that month blends one day rather than a full month. Harmless today (no intent
  has a row there); fix is `LAST_DAY(...)`.
- The launch-ramp guard added after Task 2 is correct but **immaterial at this grain**: it drops 2
  of 47 rows (5 and 2 support clicks) and shifts the largest surviving row by 0.0268. Zero effect on
  `easter`. Kept because it is correct and cheap, but the premise that "one product's launch can
  dominate a cell" did not hold.

## 5. The scorecard

`SP_SCORE_INTENT_INDEXES` walks forward over the **trailing 18 months**. Ads data begins
2024-09-05; the first ~6 months are launch-ramp noise and are excluded. For each target month M,
the curve is fitted on observations strictly before M and scored against M. Errors are weighted by
clicks so verdicts follow the money.

Two tests per index:

- **ADD_ONE_IN** — `error(active set + candidate)` vs `error(active set)`. Answers *"does this new
  index help?"*
- **LEAVE_ONE_OUT** — `error(active set)` vs `error(active set - index)`. Answers *"is this index
  still earning its place?"* Without it the registry only ever grows.

Output columns: `index_name`, `test_kind`, `target_month`, `err_with`, `err_without`,
`err_delta_pct`, `bias_with`, `bias_without`, `n_predictions`, `clicks_scored`, `verdict`.

`err_delta_pct` is the **relative** change in weighted absolute error,
`(err_with - err_without) / err_without * 100`, so a value of `-1.0` means the error fell by one
percent of itself, not by one percentage point.

`verdict` is one of **IMPROVES / NEUTRAL / HURTS / INSUFFICIENT**, evaluated in this order:

1. `INSUFFICIENT` when `clicks_scored < INTENT_IDX_MIN_SCORED_CLICKS`.
2. `HURTS` when `err_delta_pct >= +1.0`, **or** when `ABS(bias_with - 1.0) > ABS(bias_without - 1.0) + 0.02`.
3. `IMPROVES` when `err_delta_pct <= -1.0` **and** `ABS(bias_with - 1.0) <= ABS(bias_without - 1.0) + 0.02`.
4. `NEUTRAL` otherwise.

Bias is checked alongside error because an index can lower error while skewing the level, which is
exactly how D3 went unnoticed. The 0.02 tolerance stops trivial bias jitter from vetoing a genuine
error reduction.

A pooled all-months row accompanies the per-month rows, carrying `months_improved` /
`months_scored` — an index that wins eleven months and loses December is a different thing from
one that wins six and loses six.

**Promotion is manual.** The scorecard never flips `is_active`. Ori does, the same contract as
`DE_SEARCH_TERM_INTENT`: automation proposes, a human disposes.

## 6. Rollout

1. Build `V_INTENT_CVR_CURVE_SHADOW` plus the registry and both index views. Nothing repointed.
2. Register `season_month` and `season_phase` with `is_active = FALSE`.
3. Run `SP_SCORE_INTENT_INDEXES`. Expect `season_month` to read INSUFFICIENT on the great majority
   of cells at today's grain, and `season_phase` to read IMPROVES in Feb-Apr and Nov-Dec and
   NEUTRAL elsewhere. **If it does not, the diagnosis in §2 is wrong and this design stops here.**
4. Diff shadow against live across all 122,124 rows: `cvr_hat` distribution, count of rows moving
   more than 2x, and the direction of movement per intent_type.
5. **Acceptance gate — re-run the §1 simulation against the shadow curve.** Required: the 1.69x
   under-pricing closes to within 1.15x, and the false-CUT rate falls from 54%.
6. Only on passing 5: flip the two indexes active, repoint `SP_REFRESH_SEARCH_TERM_INTENT`,
   rebuild `T_INTENT_CVR_CURVE` and `T_INTENT_BID_BASE`.

This follows the documented lesson from the target-CPC work, where a change went straight to a live
bidding view and had to be reverted: *write to a shadow view, promote only after safety passes.*

## 7. `gp_per_order` — folded into this change

`T_INTENT_BID_BASE` carries a clicks-weighted `gp_per_order` of **$19.96** against an actual
trailing-90-day figure of **$13.73** — 45% high. Because `value_per_click = cvr_hat x
gp_per_order`, this error runs *opposite* to D3 and partially masked it. Fixing `cvr_hat` alone
would leave the catalog over-priced on margin.

`V_KEYWORD_RATES` (shipped 2026-08-26) already publishes a recency-weighted `gp_per_order` under
the house's nested-window definition, and its stated purpose is that *"the Catalog and the engine
cannot price against different money."* **`V_INTENT_BID_BASE` sources `gp_per_order` from that
shared definition** rather than computing its own.

## 7.5 KNOWN DRIFT — `INTENT_IDX_MIN_SUPPORT` silently loosens over time

Recorded 2026-08-31, raised by the Task 3 implementer and verified by its reviewer. **Not fixed;
this is a deliberate deferral with a stated trigger.**

`V_INTENT_IDX_SEASON_PHASE` computes `day_support = phase_clicks / n_days`, dividing
**whole-history** clicks by **one** projection year. Ads history currently spans about two
occurrences of each holiday compressed onto twelve forward months, so per-day support runs roughly
**2x a true one-year rate**. That is why the conservation invariant lands on each intent's total
click count, and it does not distort `index_value` — the scaling divides out of the normaliser.

But it means **`INTENT_IDX_MIN_SUPPORT = 100` currently behaves like ~50 clicks in one-year terms**,
and that equivalence moves as history accumulates: three occurrences makes it ~33, four makes it
~25. The gate loosens on its own, without anyone changing it.

This matters because the gate is load-bearing. **161 of 204 published `season_phase` rows sit below
it and are pinned to 1.000**; only 43 are applied. It is the only thing keeping `christmas`'s
off-season 0.2567 — resting on 755 OFF clicks carrying **2 orders** — away from the curve.

**Why not fixed now:** correcting it means redefining `support_clicks` a third time, which would
break the conservation invariant just established and re-open a settled review. The exposure is
bounded by two things already in place — promotion is manual, and the scorecard judges the index
before anyone can activate it.

**Trigger to fix:** normalise support to holiday occurrences rather than raw history when either
(a) `season_phase` is promoted to `is_active = TRUE`, or (b) ads history passes three occurrences of
the major holidays, whichever comes first. At that point the threshold should be re-derived rather
than inherited — the same rule §4.5 states for priors.

## 7.6 MEASURED CONSEQUENCE — 30.7% of cells lose their own evidence

Found in Task 4, tested and accepted. The nested 1/2/3/6/12 windows give weight 0 to anything 12+
months old, so **38,436 of 125,280 catalog rows (30.7%) have `base_clicks = 0`** at today's
watermark and price entirely off their family rung. The live view has zero such rows.

**The window choice was re-validated against the objection.** The original sweep required >=60
clicks in the target month, which selects dense cells. Re-run at every density, nested still wins:

| min target-month clicks | flat (ships today) | nested 1/2/3/6/12 | cells scored |
|---|---|---|---|
| 60 | 1.3259% | **1.2595%** | 1,378 |
| 20 | 1.3645% | **1.2985%** | 2,108 |
| 5 | 1.3973% | **1.3311%** | 3,066 |
| 1 | 1.4072% | **1.3414%** | 4,255 |

Cells losing all own evidence differ by only 7 between the two shapes (506 vs 499).

**Why the two numbers differ.** The walk-forward evaluates a cell at a target month using earlier
history — it scores cells while they are active. The 30.7% is measured at the current watermark and
counts **dormant** cells: product x intent pairs with no click in over a year. For those, falling
back to the family rung is the honest answer; pooling two-year-old clicks as if current is the
defect being fixed. Accepted, but **Task 8's money gate must see it explicitly** rather than
discover it.

Also unresolved and carried to Task 8: the `confidence` cut-points (500/100/20) and
`base_self_weight` now read recency-weighted clicks but were chosen against raw ones, and
`V_INTENT_IDX_SEASON_MONTH` has no launch-ramp quarantine, so activating it loses a guard the live
curve carries.

## 8. Limitations, stated

- The phase projection is correct for **one year ahead**. When `DIM_US_HOLIDAYS` rolls forward the
  curve must be rebuilt. Approach C removes this; it is not in scope here.
- The holiday fix reaches **~9% of clicks**. The recency fix reaches all of them. Expect most of
  the measured gain to come from D3.
- `INTENT_CVR_CALIBRATION` is fit on current data and drifts with the account.
- The walk-forward harness scores **CVR prediction**, not profit. A curve that predicts CVR better
  should price better, but that link is asserted, not proven — which is why §6 step 5 gates on the
  money simulation rather than on the scorecard.
- 24 months of history exist; 18 are scored. A yearly-seasonal index therefore gets at most **two
  observations per month**, which is thin. `season_phase` verdicts should be read with that in
  mind, and it is a reason to prefer manual promotion.
