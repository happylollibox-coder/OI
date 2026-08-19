# Low Stock — Weekly Run criteria 1

> Highest-priority criteria on the Weekly Run page, above Launch exemption and above Revivals.
> Object: `V_LOW_STOCK_ADS` → cube `LowStockAds` → panel `LowStockPhase.tsx`.
> Advisory. Nothing here auto-applies to Amazon.

## Why it exists

Ori, 2026-08-13:

> "add a new criteria - low stock (this gets prioritised) - meaning if a family is going to be out
> of stock we need to reduce not-converting ad spend in order to reduce sales until the new batch
> arrives."

## What grades out on 2026-08-13 (v27.59, actual-sales velocity)

Ads watermark 2026-08-12 · `in_peak = TRUE`, `w_days = 3` · inventory snapshot 2026-08-13.

| family | grade (ACTUAL) | grade (forecast) | binding variation | cover actual | cover forecast | rate actual / forecast | season gap |
|---|---|---|---|---|---|---|---|
| **LolliBall** | **CRITICAL** | CRITICAL | Pink LolliBall | **23.3 d** | 23.3 d | 29.4 / 21.4 per day | −8,212 |
| Bunny | WATCH | THROTTLE | Love Bunny | 177.3 d | 110.6 d | 9.6 / 12.0 | covered |
| Fresh | WATCH | THROTTLE | Fresh in Pink | **143.9 d** | **48.4 d** | 11.0 / 26.7 | **−382** |
| Bottle | OK | OK | Truth Or Dare | 282.4 d | 103.0 d | 4.1 / 10.4 | covered |
| LolliME | OK | OK | Mint LolliME | 154.2 d | 71.4 d | 46.1 / 98.7 | covered |
| Lollibox | OK | THROTTLE | Pink Lollibox | 199.3 d | 118.9 d | 19.6 / 29.8 | covered |

Three families were **downgraded** by the correction (Fresh and Bunny THROTTLE → WATCH, Lollibox
THROTTLE → OK) because their forecast rate runs 1.2×–2.4× ahead of what they are actually selling.

**LolliBall did NOT downgrade, and the reason is the opposite of what was expected.** It is a launch
family climbing hard: its trailing-7-day rate is *above* its forecast on every variation. On the
trailing-30-day rate Pink LolliBall reads 38 days of cover; on the last 7 days it reads 23. Actual
sales made LolliBall **more** urgent, not less.

**LolliBall's proposal:** 20 targets halved (−50%, $58.71/day of bid removed), 2 non-converting
targets parked ($1.31/day), 7 protected, 6 watching · **$60.02/day freed · 5.5 days of cover bought
on the binding variation** · 4 paired budget cuts totalling **$38.89/day**. Nothing auto-applies.

## The interpretation, stated plainly

The instruction has two halves that pull in opposite directions, and the view is explicit about it.

**Cutting non-converting spend does not slow sales.** By definition those targets bought zero orders
on the settled window, so removing them removes zero units of demand. `days_bought` for every
non-converting row is **0.0**, printed, not hidden.

**Only throttling converting traffic stretches inventory.** That is a real trade — fewer units now
at full margin, in exchange for staying in stock and holding rank.

So the order of operations is:

1. **Cut the waste first — it is free.** Non-converting targets inside an at-risk family, ranked by
   dollars/day, `action = STOCK_CUT_WASTE`. It saves cash and stops paying to compete for a product
   you cannot supply. It buys no days of cover.

2. **…except inside a capped campaign, where cutting waste speeds the stock-out up.** This is where
   Ori's two halves genuinely reconcile. A campaign that is out of budget spends its whole budget
   every day. Removing a non-converting target does not return that money — it re-routes it to the
   converting targets in the same campaign, which sells **more** units, **sooner**. For campaigns
   where `V_CAMPAIGN_CAP_STATE.is_oob_owned`, the action is paired:
   `action = STOCK_CUT_WASTE_AND_BUDGET` — park the waste **and** take the freed dollars out of the
   daily budget. Un-paired, the cut is actively harmful to a family heading for a stock-out.

3. **In a CRITICAL family, a below-breakeven converting target gets a REAL action** (v27.58).
   See the section below — this is the change Ori asked for on 2026-08-13.

4. **In a THROTTLE or WATCH family, converting traffic is still only priced, never proposed.**
   `STOCK_PROTECT` with `days_bought_if_paused` attached, so the size of the trade is visible.
   Winners are not pulled down, and the honest levers remain the waste cut and the PO.

`days_bought` and `days_bought_if_paused` are **upper bounds** — they assume the stopped ad loses
100% of its units with zero organic recapture, which is false. The real number is smaller. Never
quote either as the expected gain.

## The CRITICAL rule (v27.59, Ori 2026-08-13) — the short-window 50% halve

> "table format of critical low stock use the last day, 7 days window format. If it wasn't
> profitable in last day AND 7 days (or 3 days in peak) reduce bid by 50%."

This **replaced the v27.58 breakeven-bid ladder outright**. `breakeven_bid`, `bid_cut_viable`,
`keep_factor`, the 10-click evidence gate and the proven-over-90d reprieve are gone.

### The rule

| | |
|---|---|
| **last day** | `LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP())` — the same anchor `V_OOB_KEYWORD` and `V_OOB_BUDGET_PHASE` call "last day", so every Weekly Run panel means the same day |
| **the w-window** | the last `w_days` days, `w_days` from `V_PEAK_WINDOW_RULE` (7 off peak · 3 in peak unless last year proved 7 is better). **2026-08-13: `in_peak = TRUE`, `w_days = 3` (BTS_2026, verdict NOT_PROVEN)** |
| **"profitable"** | GP-ROAS ≥ 1.0 on a window that actually **spent** — tier COGS charged, so 1.0 is breakeven *after* product cost |
| **fires when** | family `risk_state = 'CRITICAL'` · not brand defense · spend > 0 on the w-window · **both** windows failed |
| **the action** | `bid × 0.5`, floored at the row's own bid floor. No park, no stop, no ROAS-driven budget verdict. |
| **either window profitable** | no action — `STOCK_PROTECT`, and the reason names which window spared it |

**It is deliberately blunt, and that is the point.** The family is running out of stock and the
objective is to **slow sales** until the next batch lands, not to optimise ROAS. So there is no
click bar, no 90-day reprieve and no breakeven arithmetic — all three of those exist to protect a
keyword's long-run value, and long-run value is not the binding constraint when the units it sells
cannot be replaced this season.

### Floors — per format, never crossed

```
SP                                        $0.20   house floor (Amazon's own SP minimum is $0.02,
                                                  but a bid that low buys no placement worth having)
SB video / brand                          $0.25   Amazon platform minBid
SB PRODUCT_COLLECTION / STORE_SPOTLIGHT   $0.10   accepted in upload rounds 32-33
```

Read from `DIM_AD_GROUP.creative_type`, the same split `V_OOB_KEYWORD` and `FN_TARGET_BID_SHADOW`
use. When a straight 50% would land under the floor the proposal is **clamped up to the floor** and
the reason says so (`$0.38 → $0.20`, not `→ $0.19`). When the bid is *already* at the floor there is
no executable cut: the row reports `STOCK_AT_FLOOR` and proposes nothing rather than inventing a
move Amazon would reject. A target with no bid of its own (SB product target) reports `STOCK_NO_BID`.
Both are counted in `not_executable_targets` so `escalated_targets` always reconciles.

### The three-state profitability, and the one judgement call in it

`profit_1d` and `profit_w` are published as **YES / NO / NO_SPEND**, never inferred by the panel.

- The **w-window must have spend**. With none there is no evidence and, more to the point, nothing
  to slow down — the row gets `STOCK_WATCH` and says so.
- The **last day having no spend does NOT veto** the w-window verdict. The guard Ori asked for exists
  because last-day data is unsettled and *understates* ROAS — clicks whose orders have not landed. A
  day with no clicks at all cannot be understating anything, so it carries no settle risk and cannot
  be the thing that spares a target.

### ⚠️ The settle caveat — stated once, then implemented as specified

Both short windows are **unsettled**: SP sales accrue to D+7, SB to D+14, so a fresh day understates
GP-ROAS. Requiring **both** windows to fail is the guard Ori chose. It is real but **partial** — the
w-window *contains* the last day, so the two tests are correlated, not independent. Settled windows
were **not** substituted: the rule has to react at the speed stock disappears. The settled 28d/90d
columns stay published on every row so the slow read is one glance away.

### ⚠️ In a CRITICAL family the short window outranks the settled class — in both directions

`STOCK_PROTECT` for a short-window winner sits **above** the waste park in the action order.
**"surprise balls for girls"** (VIDEO- BALL, 2026-08-13) is classed `NON_CONVERTING` — zero orders on
the settled 28d **and** the settled 90d — yet it bought **5 orders at 5.52× GP-ROAS in the last 3
days**. It is not waste; it is a fresh keyword whose orders have not settled, and parking it would
kill a live winner on stale evidence. The reason string flags the disagreement explicitly.

The converse holds too: a target that looks fine on the settled 28d is still halved if both short
windows failed.

### Sizing — the decision window and the money window are the same

`dollars_freed_per_day` and `units_removed_per_day` for a halve are computed off `w_spend_per_day` /
`w_units_per_day` (the short window), **not** the settled 28-day rate. Pricing today's move off a
month-old spend level is materially wrong on a family that is climbing: Purple LolliBall runs 3.40
units/day at 60 days and 8.00 at 7. The settled rates stay published beside them.

First-order model, unchanged: scaling the bid by *r* scales CPC (and so spend) by *r* at constant
click volume, so a halved bid frees half the daily spend and removes half the daily units.

### `STOCK_PROTECT` survives for

profitable on either short window (a real winner — priced via `days_bought_if_paused`, never
proposed) · brand defense (never profit-judged, never throttled, in any risk state). A target with
no w-window spend gets `STOCK_WATCH`.

**Ranking.** `proposal_rank` orders every family's rows by dollars freed, then by days of cover
bought (Ori's words). `dollar_rank` is the older per-class spend order, kept as a fallback.

## Days of cover bought — on the binding variation

`days_bought_max` (family-cover based) was **removed** in v27.58. It measured against the family's
aggregate flat cover (58 days for LolliBall) while the panel header printed the binding variation's
(26 days) — two clocks in one row. Replaced by:

```
days_bought = binding_cover_avail × u / (V − u)        -- u = units/day this action removes
                                                       -- V = family velocity
u = units_per_day                for a park
u = units_per_day × (1 − r)      for a bid cut to factor r
u = 0                            for every non-converting / thin / already-off row
```

**Stated assumption:** ad units are removed in proportion to each variation's share of family
velocity, so cutting `u` off the family slows every variation by `V/(V−u)` and multiplies every
variation's cover by the same factor. A keyword's units cannot be attributed to one child ASIN, so a
proportional model is the most that can honestly be claimed. `days_bought_if_paused` is the same
formula with the target's whole `units_per_day` — the option price on a protected winner.

Family- and campaign-level figures are the **joint** effect of doing all of it at once, never the
sum of the per-row numbers (each per-row figure is computed with the other targets still running, so
adding them double-counts the curvature).

## ⚠️ Arrival freshness conflict (found 2026-08-13)

The FAMILY row's `next_arrival_date` is read **live** from `DE_MANUFACTURER_SHIPMENTS`. The
per-variation arrival — the one that actually drives `risk_state` — comes from
`FACT_INVENTORY_SNAPSHOT.next_shipment_arrival_date`, which `SP_LOAD_FACT_INVENTORY_SNAPSHOT` stamps
**once a day at 07:40 UTC**. A shipment booked after that load is invisible to the verdict.

Live on 2026-08-13: shipment `SHP_990487c02fee` (FAST_SEA, PENDING, ETA 2026-09-09) carries **160
Purple LolliBall + 320 Pink**. Under the v27.59 actual-sales grade **Pink** is the binding variation
(23.3 days of cover at 9.00 units/day), it reads "nothing booked", and that is what makes it CRITICAL.

**But the boat does not lift the family verdict**, and the v27.58 note that said it would was wrong
on this point. That note was written when Purple was binding and only considered the binding
variation. Run the arithmetic on all five:

| variation | share | cover (actual) | booked | verdict with the boat |
|---|---|---|---|---|
| Pink | 28.0% | 23.3 d | 320 u, ETA 09-09 (27 d) | gap −3.7 → **THROTTLE** |
| Purple | 28.7% | 23.9 d | 160 u, ETA 09-09 (27 d) | gap −3.1 → **THROTTLE** |
| Mint | 17.7% | 51.3 d | **nothing** | 51.3 < 60 → **CRITICAL**, unchanged |
| Blue | 14.3% | 71.1 d | nothing | THROTTLE |
| White | 11.3% | 88.5 d | nothing | THROTTLE |

Mint LolliBall is material (17.7% ≥ the 10% bar), has nothing booked and 51 days of cover against a
lead of 60+. **It is CRITICAL on its own**, so the family stays CRITICAL and the halve rule stays on
— the binding variation simply moves from Pink to Mint. A boat that carries two of five variations
does not rescue the other three. The conflict note now says exactly that instead of claiming the
family bridges.

Note also the direction the correction cuts here: on the *trailing-30-day* rate Pink reads 38 days
and would clear the boat with room; it is the last week's acceleration that makes it tight.

Confirmed to be a timing lag and **not** a loader bug: `SP_LOAD` applies no `shipment_type` filter,
and all seven other pending ETAs match the live table exactly.

**The view does not correct it.** Overriding the stamped column would change the verdict of the
whole criteria on data that has not been through the loader, and whether a shipment carries the
binding variation is a supply judgement, not an ads one. Instead it publishes
`arrival_freshness_conflict` + `arrival_conflict_note` on the FAMILY row and the panel renders the
note in amber above the actions. The test is narrow — the *binding* variation has a live pending
shipment its stamped arrival does not know about. A binding variation that simply has no boat while
its siblings do is **not** a conflict (Blue Lollibox, 2026-08-13); flagging that would cry wolf.

## Inventory sources (existing; nothing reinvented)

| What | Where |
|---|---|
| The six pipeline stages | `FACT_INVENTORY_SNAPSHOT` (loaded by `SP_LOAD_FACT_INVENTORY_SNAPSHOT` from `V_UNIFIED_INVENTORY_SNAPSHOT`) |
| Sellable / velocity / walk-DOC / next shipment | `V_SUPPLY_CHAIN_SUMMARY` — the Supply page's own summary |
| The seasonal month-by-month depletion walk | `V_PLAN_FORECAST.sellable_doc_walk` (read through the summary) |
| Booked arrivals + overdue pendings | `DE_MANUFACTURER_SHIPMENTS` × `DE_SHIPMENT_LINES` × `DE_PURCHASE_ORDERS` |
| Rest-of-year demand | `FACT_FORECAST_DEMAND` (the same rows `V_PLAN_FORECAST` walks) |
| Family attribution of campaigns | `V_CAMPAIGN_FAMILY_MAP` |
| Capped-campaign ownership | `V_CAMPAIGN_CAP_STATE.is_oob_owned` |

The six stages, in Supply-page order: **FBA at Amazon · AWD · In Transit · In Transit to AWD ·
Manufacturing ready · In Production**. `sellable_qty` = FBA + AWD only. `total_pipeline_qty` counts
all six — earlier numbers in this project were wrong precisely because they counted part of it.

## ⚠️ Open defect upstream: V_PLAN_FORECAST is non-deterministic

**Found 2026-08-13 while building this.** `V_PLAN_FORECAST` returns *different rate values for the
same ASIN on different evaluations of the same view* — reproduced inside a **single statement** that
joined `V_PLAN_FORECAST` to `V_SUPPLY_CHAIN_SUMMARY` (which is just `COALESCE(pf.proportional_daily_demand, …)`):

| product | `V_PLAN_FORECAST.proportional_daily_demand` | same value via `V_SUPPLY_CHAIN_SUMMARY.daily_velocity` | walk DOC |
|---|---|---|---|
| Fresh in Pink | 6.41 | **15.71** | 89 vs **55** |
| Mint LolliME | 19.91 | **41.97** | 71 vs **35** |
| White Lollibox | 16.83 | **11.54** | 99 vs **114** |
| Purple LolliBall | 5.77 | 5.77 (stable) | — |

Repro: `SELECT f.proportional_daily_demand, s.daily_velocity FROM V_PLAN_FORECAST f JOIN
V_SUPPLY_CHAIN_SUMMARY s ON s.asin = f.asin`. `last_30d_sold` is stable; only the forecast-derived
rates and the walk move, and they move in **both** directions, so it is not a partial-load artifact.

**Blast radius is much wider than this criteria.** `V_PLAN_FORECAST` feeds the Plan page,
`V_SUPPLY_CHAIN_SUMMARY` (the Supply page's days-of-coverage), `V_SHIPMENT_PLAN` and
`SP_GENERATE_ALERTS`. Days-of-coverage on the Supply page can therefore change between two page
loads with no data change behind it.

**Mitigation inside this view:** `velocity_30d` is derived first-party from
`V_SRC_sales_and_traffic_business_sku_report_daily`, cut at the orders watermark, instead of being
read through `V_SUPPLY_CHAIN_SUMMARY.last_30d_sold`. Since `velocity_used = GREATEST(forecast, this)`,
that guaranteed number is a **floor** under the cover estimate: however the forecast wobbles, cover
can never read longer than the last thirty days of real selling implies. It does **not** fix the
walk-DOC leg, and it does not fix the Supply page. This needs its own session.

## Cover — the grade runs on ACTUAL RECENT SALES (v27.59, Ori's correction 2)

> "CRITICAL means that by current sales qty (based on the last days) the family will be OOS and we
> need to spend less ads spend."

Until v27.58 the grade ran on `velocity_used = GREATEST(velocity_forecast, velocity_30d)` and **the
forecast won on all 29 ASINs** — every cover number and every risk grade in this view was
forecast-driven, on a forecast that is **3.4× reality** on the family carrying the most units.

```
velocity_actual        = GREATEST(units_7d/7, units_14d/14, units_30d/30)   -- THE GRADE'S RATE
velocity_forecast_used = GREATEST(velocity_forecast, velocity_actual)       -- the SEASON's rate

doc_flat_days          = sellable_qty / velocity_actual                     -- the grade
days_of_cover          = doc_flat_days                                      -- NO seasonal walk here
days_of_cover_avail    = days_of_cover + in_transit_qty / velocity_actual
cover_basis            = 'ACTUAL_7D' | 'ACTUAL_14D' | 'ACTUAL_30D' | 'NO_DEMAND'

doc_flat_forecast_days       = sellable_qty / velocity_forecast_used        -- published alongside
days_of_cover_forecast       = LEAST(doc_walk_days, doc_flat_forecast_days) -- exactly the old number
days_of_cover_avail_forecast = … + in_transit_qty / velocity_forecast_used
risk_state_forecast          = the SAME three tests, run on the forecast cover
```

**Why the max of three actual windows, and not one.** A single window is wrong in both directions
and the catalogue proves both failures on the same day:

| failure | evidence, 2026-08-13 |
|---|---|
| **7d alone is too noisy** on a low-volume variation | Nope Bunny sold **0 units in 7 days**, 2 in 30. A 7d-only rate is 0.0/day → *infinite* cover → "plenty of stock" on a product with 95 units. A zero week must never be able to manufacture safety. |
| **30d alone is too slow** on an accelerating one | Purple LolliBall: 3.40/d (60d) → 5.53/d (30d) → 7.36/d (14d) → **8.00/d (7d)**. The 30d rate says 35 days of cover; it is actually selling at 24. Ori's own worked example ("cover 26d becomes 35d") is the 30d reading, and it is the **optimistic** one — on LolliBall the trailing-30d actual is *below* the forecast while the trailing-7d actual is *above* it. |

Taking the max is the conservative choice among actual windows (max rate = shortest cover), it can
never return an infinite cover unless the product genuinely sold nothing in 30 days, and it catches a
real acceleration within a week instead of a month. It is biased slightly high (E[max] > true rate),
which for a stock-out grade is the **correct direction of error**, and `velocity_actual_basis`
publishes which window bound each row so the bias is auditable.

**The seasonal walk leg is on the forecast side only.** `doc_walk_days` is `V_PLAN_FORECAST`'s own
forecast-shaped depletion walk. Folding it into the grade would smuggle the forecast straight back
into the number Ori asked to be actual-driven. The whole old reading survives as
`days_of_cover_forecast` / `cover_basis_forecast` / `risk_state_forecast`, and the two are shown
side by side wherever they disagree.

**Bonus effect on the `V_PLAN_FORECAST` defect below:** since the grade now uses only first-party
trailing actuals, a forecast wobble can no longer flip a family between OK and THROTTLE run to run.
It can only move the published forecast column and the season gap.

## ⚠️ The seasonality tension — surfaced, never buried

Trailing actual sales going **into** a season understate future demand. The forecast exists because
Q4 demand is far above August, and a pure trailing-actual grade will say "plenty of stock" right
before the season when it is not. The two questions are therefore kept apart and are labelled
differently everywhere they appear:

| signal | question it answers | rate it uses |
|---|---|---|
| `risk_state` (OK / WATCH / THROTTLE / CRITICAL) | *"Am I about to go dark at the rate I am selling NOW?"* — Ori's definition, and the right trigger for cutting ad spend **today** | `velocity_actual` |
| `season_gap_units` / `season_demand_units` | *"Will I have enough for Q4?"* | `velocity_forecast_used`, vs `FACT_FORECAST_DEMAND` |
| `risk_state_forecast` | what the old, forecast-driven grade would have said | forecast cover |

**Never conflate them into one number.** The panel prints the season gap on its own line, in its own
colour, saying "a PO decision, not an ads one", and prints `risk_state_forecast` beside `risk_state`
whenever they differ. Fresh on 2026-08-13 is the case that matters: **WATCH on actual sales
(143.9 days of cover), THROTTLE on the forecast (48.4 days), and still 382 units short for the rest
of the year.** All three facts are true and all three are shown.

The 7d leg does partially answer the tension on its own: as real demand accelerates into Q4 it is
picked up within a week rather than lagging a month. It cannot *anticipate* the season — nothing
trailing can — which is exactly why the season signal stays separate.

**Why `_avail` drives the verdict.** Units Amazon has already taken in check in within days. Pink
Lollibox 2026-08-13 is 29 days strict and 93 with its 588 in-transit units, against an arrival in
28 — strict alone would have screamed "10 days dark" about a family that is fine. The strict number
stays published so the harsh figure is never hidden.

## Three ways a family goes dark, all three tested

| | Test | Escalates on |
|---|---|---|
| **A. The bridge** | `bridge_gap_days = days_of_cover_avail − days_to_arrival` | `< 0` → THROTTLE · `≤ −14` → CRITICAL · `< 14` → WATCH |
| **B. Nothing booked** | no PENDING shipment with a future ETA | cover `< 60` → CRITICAL · `< 120` → THROTTLE · `< 180` → WATCH |
| **C. The season** | `season_gap_units = GREATEST(rest-of-year forecast, velocity_used × days to 31-Dec) − total_pipeline_qty` | `> 0` → WATCH; → THROTTLE once `days_of_cover_avail < full_lead_days + 14` |

Test C exists because the bridge alone is blind to Q4. Fresh in Pink 2026-08-13 clears its 26-Aug
arrival comfortably and is still ~900 units short of the season. A season gap only becomes an *ads*
problem once the shortfall can no longer be manufactured and shipped in time — until then the honest
action is a PO, and the reason string says exactly that.

`po_deadline = stockout_date − full_lead_days` (`manufacture_day + shipment_days` from
`DIM_PRODUCT`). `too_late_to_replenish` = that date has passed.

## Family verdict

Set by the family's **material** variations (≥ 10% of family trailing-90d units), so one dead
keychain colour cannot throttle a family. If ≥ 25% of the family's units sit in at-risk variations,
the family escalates anyway. The **binding variation** is picked by risk rank first, then by cover —
the family's problem is its worst-off variation, not merely its shortest-cover one.

## Settled windows

"Not converting" is judged on a settled window or it condemns keywords whose orders simply have not
landed. `settle_cut = CURRENT_DATE(LA) − 7` for SP, `− 14` for SB. Action window = settled 28d;
history window = settled 90d, reported alongside.

`GP = Ads_sales − COALESCE(T_PRICE_COST_TIER.tier_cost, TOTAL_COST_PER_UNIT) × Ads_units`.
GP-ROAS = GP / spend; 1.0 = breakeven after product cost. Never sales-ROAS.

### Target classes

| class | test | action |
|---|---|---|
| `DEFENSE` | brand defense campaign | `STOCK_PROTECT` — never profit-judged, never throttled, in any risk state |
| `CONVERTING` | settled-28d orders > 0 | `STOCK_PROTECT` in a WATCH/THROTTLE family |
| `ALREADY_OFF` | keyword no longer ENABLED | `STOCK_NONE` |
| `THIN` | < 10 settled clicks | `STOCK_WATCH` |
| `STALLED` | 0 orders on 28d **but** > 0 on 90d | `STOCK_TRIM_STALLED` — a judgement, not free money |
| `NON_CONVERTING` | 0 orders on 28d **and** 0 on 90d | `STOCK_CUT_WASTE`, or `STOCK_CUT_WASTE_AND_BUDGET` when capped |

**In a CRITICAL family the settled class does not decide the action** — the short-window rule above
does, for every non-defense target with w-window spend, and its `STOCK_PROTECT` branch sits above the
waste park. The classes still drive the reason strings and the dormant rows (no w-window spend), and
they are the whole story in WATCH/THROTTLE families.

### Action vocabulary

`STOCK_BID_HALVE` · `STOCK_BID_HALVE_AND_BUDGET` · `STOCK_AT_FLOOR` · `STOCK_NO_BID` ·
`STOCK_CUT_WASTE` · `STOCK_CUT_WASTE_AND_BUDGET` · `STOCK_TRIM_STALLED` · `STOCK_PROTECT` ·
`STOCK_WATCH` · `STOCK_NONE`; CAMPAIGN rows: `STOCK_BUDGET_CUT` · `STOCK_BUDGET_HOLD` ·
`STOCK_NONE`. `STOCK_PARK` / `STOCK_BID_CUT` were retired with the breakeven ladder in v27.59.

`STALLED` exists because "girls gifts age 8-10" (Lollibox, 2026-08-13) is 3,523 settled clicks / 72
orders / 1.04× over 90 days and simply blank for the last four weeks. Calling that free to cut is
how a proven keyword gets killed on a month of noise.

## Timezones

The inventory pipeline is UTC-dated (`SP_LOAD_FACT_INVENTORY_SNAPSHOT` uses `CURRENT_DATE()`, and
`V_SUPPLY_CHAIN_SUMMARY` measures `days_to_next_shipment` against it), so every inventory date in
this view is measured against `CURRENT_DATE()`. Ads are `America/Los_Angeles`, so the settle cut is
LA. The two clocks are deliberately separate.

## Overdue pending shipments

Arrival is user-confirmed in this system, so a shipment whose ETA has passed and that nobody marked
received stays `PENDING` forever. Those units are neither sellable nor a future arrival, and
`next_shipment_arrival_date` (which filters `eta >= today`) correctly ignores them. They are
surfaced as `overdue_pending_qty` so a family is never called "nothing inbound" when the truth is
"inbound, and someone has to press **Mark received**". 2026-08-13 stock: **13,674 units** across six
families, oldest ETA 2026-07-08.

## Grain

`row_kind` = `FAMILY` (verdict + rolled-up ads totals) · `ASIN` (diagnosis) · `CAMPAIGN` (the budget
lever and the capped pairing) · `TARGET` (the money, ranked). CAMPAIGN and TARGET rows are emitted
only for WATCH/THROTTLE/CRITICAL families.

`now_value` / `suggested_value` are the panel's two money columns, filled by the view so the panel
never has to know which grain it is on: on a TARGET row they are the bid, on a CAMPAIGN row the
daily budget. `suggested_value` is NULL when there is nothing to change (a park has no new bid).

### CAMPAIGN rows — where the capped pairing lives

| campaign state | action | `suggested_budget` |
|---|---|---|
| capped (`is_oob_owned`) **and** something proposed | `STOCK_BUDGET_CUT` | `budget − dollars_freed`, floored at $1 |
| not capped **and** something proposed | `STOCK_BUDGET_HOLD` | NULL — it does not spend its allowance anyway, so the freed dollars genuinely leave |
| nothing proposed | `STOCK_NONE` | NULL |

In a capped campaign the budget is spent regardless, so removing a target — by park **or** by bid
cut — does not return money, it re-routes it to the neighbours and sells the remaining stock
**faster**. A bid cut is the sharper case, and under the v27.59 rule it is the *only* case: **a
halved bid on a capped campaign buys roughly twice the clicks for the same money, so unpaired it
sells the last stock faster than doing nothing at all.** The dollars only leave when the budget
leaves with them. The pairing is summed **once per campaign in the view**, so the panel adds nothing
up, and the target reason string carries a ⚠️ saying the move is worse than nothing unpaired.

The cut is sized by the freed dollars (`budget − Σ dollars_freed`, floored at Amazon's $1), not by a
flat proportion: a campaign usually holds a mix of halved and protected targets, and halving the
whole budget would starve the protected winners alongside the bleeders.

LolliBall 2026-08-13: 4 of its 8 campaigns are capped **and** have a proposal → 4 paired budget cuts
totalling **$38.89/day** (VIDEO- BALL $55.06 → $32.61, BALL-SP/AUTO Purple $12.29 → $5.58, Mint
$22.50 → $16.36, Blue $10.00 → $6.41).

### ⚠️ Query-planning ceiling

This view sits at BigQuery's planning limit. CTEs are **inlined at every reference**, and
`tgt_ranked` is referenced three times (TARGET branch, family roll-up, campaign roll-up), so every
extra CTE level is paid for three times on top of the already-deep inventory chain. Two changes were
forced by hard failures (`Not enough resources for query planning`, then an out-of-memory) and must
not be "tidied" back:

1. The target CTE chain is **flat** — predicates are repeated inline instead of getting their own
   level.
2. The at-risk filter lives in `tgt_class`, **not** in `camp`. As a subquery in `camp` it expanded
   the whole inventory chain (`fam_state → fam_agg → asin_shares → V_SUPPLY_CHAIN_SUMMARY →
   V_PLAN_FORECAST`) three extra times. `tgt` now aggregates ads across all ENABLED campaigns — a
   wider scan, but scans are cheap here and stages are not.

Likewise the family roll-up reads family velocity and binding cover **off `tgt_ranked`** rather than
re-joining `fam_state`, and the output uses `UNION ALL BY NAME` so a mismatched column is a compile
error rather than a silently shifted value.

## Interaction with criteria 2 (Launch exemption)

Low stock is evaluated **above** launch exemption. Since v27.58 the two genuinely meet, because
LolliBall — the only CRITICAL family — **is** a launch family: all 8 of its campaigns are
`exempt_active` until 2026-11-30, and every proposed stock action lands on an exempt campaign.

**What the exemption blocks:** campaign-level, ROAS-driven money cuts inside `V_ADS_COACH` —
`CAMPAIGN_STOP`, `GUARDIAN_BUDGET_DECREASE`, `BLITZ_BUDGET_DECREASE`, `COOLDOWN_BUDGET_REDUCE`,
`RESTORE_BUDGET_PRE_PEAK`, post-grace `GUARDIAN_BUDGET_CONTAIN`. Its purpose is that a young family
is not loss-cut out of existence before it has found its bid.

**What it does not block, and must not:** this. A stock action is a supply constraint, not a ROAS
verdict on a launch. The exemption's own doctrine is *"launch = FIND THE RIGHT BID, never
loss-cut"*; a stock brake is neither a loss-cut nor a park — it is a temporary throttle on delivery
that is lifted the moment the boat lands. **Nothing in `V_LOW_STOCK_ADS` reads `V_LAUNCH_EXEMPTION`
as a gate** — it is LEFT JOINed for display only, so an exempt campaign appears with its exemption
stated next to a live proposal instead of silently disappearing.
`launch_exempt_active` / `launch_exempt_until` are published on every TARGET and CAMPAIGN row, the
reason string on an escalated row says the exemption was seen and deliberately not applied, and the
panel shows a `· launch-exempt` badge on the campaign.

**The one place to be careful:** the paired budget cut on a capped campaign *is* a campaign-level
budget cut — the shape the exemption blocks elsewhere. It stands here because its size is set by the
freed dollars, not by a ROAS test, and because without it the target cut backfires. That is stated
on the CAMPAIGN row itself.

`family_age_months` and `first_sale_date` are published on FAMILY rows so the two panels can be read
together.

## Operational notes

- Runtime ~50-70 s cold (`V_SUPPLY_CHAIN_SUMMARY` → `V_PLAN_FORECAST` is ~11 s of it). The cube
  runs a 15-minute TTL, so the page is not paying that on every load, and the panel polls with 60
  retries rather than the default 20 (20 × 2 s gives up at 40 s and says "unavailable" for a query
  that was about to answer).
- Determinism: two independent pulls are byte-identical. The one moving part is the daily
  `SP_LOAD_FACT_INVENTORY_SNAPSHOT` reload (~07:40 UTC), which replaces the day's rows — pulls
  either side of it differ because the warehouse changed, not because the view wobbles.
- Thresholds live in the `k` CTE at the top of the view SQL, never in the panel
  (`feedback_coacher_rules_in_engine`, `feedback_all_logic_in_backend`).

## v27.62 — the table shape, and the why (Ori 2026-08-13)

> "same campaign with different measures shows in 2 criterias (this is not good)" … "table format
> should be like portfolio 80/20; there should be actions and the why must be short and readable."

This section covers the second half of that. **No decision, threshold, dollar or verdict changed** —
only the shape of the table and the length of the words in it.

### The row shape is now OobBudgetPhase's, slot for slot

`OobBudgetPhase.tsx` (Portfolio 80/20) is the reference. Its header row is

```
item — campaign ▸ keyword ▸ term | dark | now $ | last day | prev-2d | CPC/target | role
  | action | → $ | (spacer) | why
```

Eleven columns. `LowStockPhase.tsx` now carries the same eleven, in the same order, with the same
alignment (everything right-aligned except *item / class / action / why*) and the same visual
vocabulary — the same `text-label font-mono border-collapse` table, the same `border-border/40`
campaign row over `border-border/20 bg-surface/40` target rows, the same `pl-8` indent. Where the
measure differs the slot keeps its **job**, not its label:

| OOB slot | Low stock | why it is the same job |
|---|---|---|
| `dark` | `capped` — days out of budget /7 | both answer "is this campaign budget-constrained?", which is what decides whether a target cut frees money or merely re-routes it |
| `now $` | budget/bid **+ the $/day rate** in the same cell | OOB packs `$40 bud · $39.87 spent` into one cell; this packs `$0.43 bid · $26.57/d`. It frees a column. |
| `prev-2d` | the w-day window (7, or 3 in peak) | the panel's second window |
| `CPC/target` | `settled 28d` | the slow reference read |
| `role` | `class` — `target_class` from the view | the target's job in the campaign's economy |
| `(spacer)` | `days bought` | OOB uses that slot for its apply button; this panel is advisory and queues nothing, so the slot carries the number the ranking is built on |

**Every row carries an action and a `→ $`, campaign rows included.** They used to render blank; a
campaign with no budget change now says `budget unchanged` and `—` rather than nothing at all.

Two things were **removed** from the item cell because they widened the table without adding
information: the `· capped n/7` badge (it is a column now) and the `· both windows failed` badge (the
red `✗` on *last day* **and** on the w-day window already says exactly that, and the short why says
it in the view's own words). Item column −129 px.

### The why is one clause — and it is one clause IN THE VIEW

The old visible `why` was the full `action_reason`: up to **1019 characters**, wrapped over a
`min-w-[26rem] max-w-[34rem]` cell, four or five lines per row. It drowned the table.

`V_LOW_STOCK_ADS` now publishes **two** strings per row:

| column | length | where it renders |
|---|---|---|
| `action_reason` / `risk_reason` | up to 1019 chars | the cell's `title=` **tooltip** — unchanged, nothing was lost |
| `action_reason_short` / `risk_reason_short` | ≤ 53 chars, ≤ 11 words | the **visible** `why` column, one line, `whitespace-nowrap` |

Grammar everywhere is `<the evidence> — <the consequence>`, in Ori's own shape:

```
23d cover, dry 09-05 — 0.37x last day, 0.69x 3d
14 clicks, 0 orders — park AND cut $0.36/day (capped)
capped 7/7 — pair the cut or it re-routes
13.33x last day, 5.64x 3d — pays for its own stock
```

Rules that keep the two honest:

- The short `CASE` is **branch-for-branch identical** to the long one, in the same order, in the same
  CTE. They cannot drift apart without someone editing both.
- **The panel never shortens anything.** No truncation, no ellipsis, no substring, no re-wording.
  Shortening is a wording decision and every word on this page is written in the view
  (`feedback_all_logic_in_backend`). The panel's only fallback is `short ?? long`, so a schema skew
  degrades to the paragraph instead of an empty column.
- `FAMILY` rows deliberately have **no** `risk_reason_short`. That header is a full-width prose line,
  not a table cell — it is not what was drowning anything, and it keeps the long form.
- Formatting trap, recorded because it shipped once: the `x` suffix must live **inside** the
  `FORMAT('%.2f', …)` call, never after a `COALESCE(…, 'no spend')`, or a window with no spend prints
  `no spendx`.

The two new columns ride in the panel's **second, tolerant** cube request (the one that already
carries `suggested_bid` / `suggested_budget`), not the main one — same reasoning as when that split
was introduced: a Cube query naming a dimension the schema does not have fails as a whole, and that
must never take the stock panel down.

Coverage @ 2026-08-13: 87 TARGET + 15 CAMPAIGN + 29 ASIN rows, **0** with a long reason and no short
one. Deterministic, 2× byte-identical (`afe6a9f9e50226c0cc89f4c1a5f2c142`).

## v27.73 — REDIRECT MODE (2026-08-17, engine-finalization Task 4.6)

Ori: "if one variation is out of stock we should change the target of the out of stock target to
the best high demand variation we have in stock. we should cut budget if we have only low demand
variation or the entire family is out of stock" + "when it is back in inventory recheck if we
want to change it back or leave it."

Measured basis (Bunny, 2026-08-17): ads sell the LISTING, not the advertised ASIN — 77.6% of the
family's ad units land on a sibling of the doorway; the binding variation had zero own-ad sales;
braking the family bought 0.8 days. Re-aiming keeps the sibling sales AND closes the doorway.

**The ladder** (family still graded on its binding variation, unchanged):
1. REDIRECT — binding THROTTLE/CRITICAL and an in-stock sibling (cover ≥ 60d) sells at ≥ 50% of
   the binding rate → `redirect_mode = TRUE` on the FAMILY row (hero_* fields beside it; hero is
   computed ONCE, in `fam_agg`). Bid halves and budget cuts are PRICED, NOT PROPOSED (gate keyed
   on the MOVE: only `STOCK_CUT_WASTE%` parks stay offered — a halve is a brake whatever class
   earned it). `V_LOW_STOCK_REDIRECT` emits the rows: per SP ad group that advertised the dry
   ASIN in 30d — PAUSE its product ad (`out_ad_id` from the advertised-product report) + CREATE
   the hero's (by SKU). SB creatives cannot be swapped → SB stays on the brake arms.
2. BRAKE — no such sibling → the pre-v27.73 model, unchanged.
3. FULL BRAKE — family dry → unchanged, strongest.

**The return recheck** — never an automatic revert: exports write `DE_AD_REDIRECTS` (ACTIVE);
`V_AD_REDIRECT_RECHECK` re-opens the decision when the out ASIN is back (cover ≥ 45d, ≥ 14d of
hero data) with the interim evidence on the table; Ori's click writes RESTORED (re-enable
out_ad_id + pause hero ad) or KEPT.

**Wired so far:** SQL spine deployed + verified (Bunny→Proud 3 ad groups, LolliBall→Pink 2 ad
groups, $764/30d of doorway spend; gate exact: 0/34 brakes proposed, 8/8 parks kept; pull-twice
MD5-identical). **Pending:** snapshot INSERT (grain REDIRECT) + preflight lever + feed/panel
rows + DoPage PAUSE_PRODUCT_AD branch + ledger POST endpoint — plan Task 4.6 carries the spec.

### ⚠️ v27.80 corrects the gate above — the suppression was campaign-blind (Task 4.10)

Ori, 2026-08-17, verbatim:

> "BALL-SP/AUTO (Mint) is auto per product. auto we have for each product - so no need to change
> only reduce ads by reducing the bid."

He is right, and it exposes a hole in v27.73. The gate as written above suppresses bid **and**
budget cuts for **every** campaign of a redirect-mode family (only `STOCK_CUT_WASTE%` parks
survive). That reasoning holds for a **shared doorway**, where the traffic can be re-pointed at an
in-stock sibling. It does not hold for a **dedicated campaign**, and this account runs **one auto
campaign per variation**, so the case it gets wrong is the common one.

Measured, advertised-product report, 30 complete days:

| Campaign | Own ASINs in scope | Shape |
|---|---|---|
| BALL-SP/AUTO (Mint) | 1 (Mint only) | dedicated — nowhere to re-aim |
| BALL-SP/AUTO (Pink) | 1 (Pink only) | dedicated, and Pink is IN STOCK |
| BUNNY-SP/BROAD (Hunter…) | 3 | shared doorway |
| BALLS- BROAD | 5 | shared doorway |
| BUNNY- BROAD | 9 | shared doorway |
| BUNNY - COMPETITORS | 11 | shared doorway |

**The three cases, and only the third changes:**

| Campaign type in a redirect-mode family | v27.73 behaviour | Verdict | v27.80 |
|---|---|---|---|
| Shared doorway advertising the dry variation | suppressed + redirect offered | **CORRECT** | unchanged |
| Dedicated campaign of an **in-stock sibling** | suppressed, no redirect | **CORRECT** — braking BALL-SP/AUTO (Pink) would not save one unit of Mint and would lose Pink sales | unchanged |
| Dedicated campaign of the **dry variation** | suppressed, no usable redirect | **THE HOLE** — BALL-SP/AUTO (Mint), $417/30d, neither braked nor sensibly re-aimed | **brakes normally** |

Swapping the product ad inside BALL-SP/AUTO (Mint) to Pink is meaningless: **BALL-SP/AUTO (Pink)
already exists and already does exactly that job**, so the "redirect" would build a duplicate of a
live campaign. For a campaign dedicated to the dry variation the correct action is the **ordinary
brake — reduce the bid**, which is what v27.73 wrongly suppressed.

**The rule, restated:**

```
suppress brakes  ⇔  redirect_mode  AND NOT waste-park  AND NOT serves_only_binding
```

`serves_only_binding` = the campaign advertises exactly **one** of our own products and that
product **is** the family's binding (dry) variation.

**Where the scope comes from.** New object `V_CAMPAIGN_PRODUCT_SCOPE` — one row per campaign over
the last 30 **complete** days of the advertised-product report (window ends watermark−1, Task 4.7
convention), publishing `n_own_asins` and `sole_asin`. "Own" = `DIM_PRODUCT.parent_name IS NOT
NULL`, so a campaign advertising one of ours against forty competitor ASINs is still *dedicated*.
74 campaigns @ 2026-08-17: 67 dedicated, 7 shared.

**Planner safety is the binding constraint here, not the logic.** `V_LOW_STOCK_ADS` has no measured
headroom — it stopped planning entirely on 2026-08-17 and the whole v27.77 repair exists because of
it. So the scope is **materialized** as `T_CAMPAIGN_PRODUCT_SCOPE` and joined as a **physical
table**; `rmode` gained one column (`binding_asin`) instead of a new CTE. The table is rebuilt as
orchestrator **Task 20.5d3**, before anything reads the low-stock engine (Task 20.5g
`SP_SNAPSHOT_PANEL_OWNERSHIP`, then `SP_SNAPSHOT_ENGINE_PROPOSALS`). The join is not optional: a
missing table breaks the view outright. Re-verified after deploy — the CAMPAIGN branch plans and
runs (119 MB) and `SELECT COUNT(*) FROM V_PANEL_OWNERSHIP` returns **93**, the v27.78 number.

**`V_LOW_STOCK_REDIRECT` drops dedicated campaigns** (`COALESCE(n_own_asins, 2) > 1`) — computed
in-view off the report it already scans, over the same complete-day window so the two objects can
never disagree. 5 rows → 4: BALL-SP/AUTO (Mint) gone, the four shared doorways remain.

**Measured flip, 2026-08-17 — exactly one campaign moves.** BALL-SP/AUTO (Mint)
`serves_only_binding = TRUE`, `proposal_targets` 1 → 3: two AUTOMATIC bid halves regain proposals
(`substitutes` $0.41 → $0.20 freeing $4.23/day; `loose-match` $0.34 → $0.20 freeing $1.79/day —
$6.02/day of newly-proposed brake) on top of the `close-match` waste park that already survived.
Its CAMPAIGN-row `is_proposal` stays FALSE, correctly: the campaign is not capped
(`STOCK_BUDGET_HOLD`, no suggested budget), so the freed dollars leave without a paired budget cut.
The other 13 low-stock campaigns are unchanged.

**Known limit, conservative on purpose.** Amazon publishes no advertised-product report for
Sponsored Brands, so SB/video campaigns (VIDEO- BALL, VIDEO- COMP/BALL, BUNNY-VIDEO/BROAD) get no
scope row, read `serves_only_binding = FALSE`, and keep the v27.73 behaviour exactly. A dedicated
**SB** campaign of a dry variation therefore stays suppressed — the same hole, one channel over.
Closing it needs an SB campaign→ASIN source (DIM_AD_GROUP creative ASINs is the candidate).
