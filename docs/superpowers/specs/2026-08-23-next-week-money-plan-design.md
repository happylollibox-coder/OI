# Next Week's Money — the one engine for working families

**Date:** 2026-08-23 · **Owner:** Ori · **Status:** approved in conversation (sections 1–10), spec for review
**Supersedes, for working families:** the three separate 80/20s — LIFT's per-campaign loser allowance,
BASE/GROWTH's growth pot, and the seat register's backward-looking doctrine read (the register stays as the
plan's ledger). **Builds on:** `docs/superpowers/specs/2026-08-22-family-seat-register-design.md`
(ledger, seat numbers, leak book, morning surface) and the keyword verdict ladder (`FACT_KEYWORD_STATE`).

## 1. The idea, in Ori's words

> "Think of it more as a budget allocation: the good keywords' spending in the last 7 days should be the
> 80% of next week; 20% budget for the losing keywords. In peaks allocate by the last 3 days."
> "Only the losing keywords get budgeted by the seats queuing method. If last week I spent $3,500 on
> good keywords in Lollibox, next week I allocate $700 ($100 a day) for not-good keywords — the seats
> logic ranks the worse ones and queues them."
> "There should be one engine, not multiple."

Every working family (the HARVEST book: Bottle, Lollibox, LolliME, Fresh) gets next week's not-good money
planned from what its good keywords actually spent in the last window. Good keywords are left alone. The
not-good keywords compete for numbered, dollar-sized seats inside that allowance; the rest queue at zero
spend. One engine decides prices and budgets for these families; Ori uploads one file.

## 2. Rulings (made in conversation 2026-08-23; each overrulable by one line. P-14 is the answer to a defect Ori raised and has NOT ruled on — it is built as written until he does.)

| # | ruling | why |
|---|---|---|
| P-1 | **Rule B judges the window:** good / losing is decided on the window itself (7 complete days; 3 in peaks), not on the ladder's 90-day record. | Ori: "I think the answer is B" — and it is a learning question (P-9). |
| P-2 | **Pot = what the family's GOOD keywords actually spent in the window.** The allowance for not-good keywords = `k.allowance_share` (0.20) × that. Lollibox example: $3,500/week good → $700/week = $100/day not-good. | Ori's example, verbatim. Not 20% of the family total. |
| P-3 | **Good = at or above the family bar (gross profit per ad dollar, `T_FAMILY_BAR`) with 2+ orders in the window.** One order = "waiting — one order" → not-good side. Spent with no sale → not-good side. Below the bar with 2+ orders → losing. | Ori took the recommendation. One order at 3× is mostly luck; the 2-order floor is the cheapest guard. **No number is pinned here (Standing Rule 0)** — the earlier version of this cell claimed the floor keeps 80–85% of each working family's window spend on the good side, and that does not re-derive on the live window under any reading, for any family. What the floor costs, and how small the good side actually is, are both **read**: `architecture/NEXT_WEEK_MONEY.md` §1b publishes the query (share of family window spend on the good side, and share of bar-passing spend the floor keeps, per family and per window length). Run it before arguing about the floor — the good side being a minority of each family's window spend is the whole reason the allowance gap is what it is, and the sentence that used to sit here made the floor sound cheap. |
| P-4 | **The good side is never cut and is not re-allocated.** Its keywords keep earning as they are; their prices are left alone by this plan. | Ori: "only the losing keywords get budgeted by the seats queuing method." CPC study: holding pays, churn loses. |
| P-5 | **Grace for proven winners.** A keyword the ladder calls a settled winner (`WINNER` / `PACED_WINNER`) that has a quiet window stays on the good side for ONE window, held, not cut. Two quiet windows in a row and rule B stands. | Pure B would push settled winners with a quiet window into the queue — cutting winners on noise, which the CPC study already convicted. The ladder buys time, never money. **How many winners this covers is a measurement, not a constant, and is not pinned here** (the earlier version of this cell named two per-family counts that do not re-derive; they move with the window length and with the day). Count them: settled `WINNER`/`PACED_WINNER` rows in `V_KEYWORD_STATE` for the HARVEST families whose window orders fall under `min_orders`, over the window `DE_PLAN_CONFIG` declares today. |
| P-6 | **Seat cost = spend at the repaired price**, not last window's spend. | One $139/day repair would otherwise eat Lollibox's whole ~$61/day allowance alone. |
| P-7 | **Rank = dollars at stake × closeness to the bar** (window spend × window return ÷ bar), ties by clicks. Best first. | "Closest first" alone seats a $0.50/day keyword before a $50/day one; rank by how much money a repair could bring back. |
| P-8 | **Ramp the allowance over three windows**: close one third of the gap between today's not-good spend and the allowance each window, like the three-step bid cap. | Without a ramp the whole gap between a family's not-good spend and its allowance is parked in one upload. **The size of that gap is not pinned here** (the figures the earlier version named do not re-derive on the live window, and they move every day) — `architecture/NEXT_WEEK_MONEY.md` §1b publishes the query that reads per-family not-good spend per day beside `allowance_share ×` the good side's window spend. The gap being multiples of the allowance is exactly why P-8 exists. |
| P-9 | **Learning: B live, A in shadow, both backtested now.** A = the ladder decides the side, the window decides the amount. Both plans are written every night, both graded by the settled scorecard at T+14; the window per calendar is a declared setting the learning may change. | The holdout (10 %, from 2026-09-01) answers "engine vs nothing", not "A vs B". |
| P-10 | **Complete days only.** The window is `k.window_days` complete days ending at the ads watermark − 1 (America/Los_Angeles); the filling day never enters a window. Peaks: `k.peak_window_days` = 3 complete days. | Ori: "make sure you are calculating 7 days by entire days and not partial." House convention since 2026-08-17. |
| P-11 | **One engine.** For working families the plan is the sole authority on keyword bids and campaign budgets. LIFT and OOB retire as price and budget authorities for these families (their proposals are still recorded and held — "the plan owns this price" — so the scorecard can grade them); LIFT's probe list and REVERDICT's revival list remain candidate sources for the seat queue. Programs that do not set prices stay: negates (search-term blocking), low-stock override, launch controller (INVEST families), holdout. | Ori: "there should be one engine (and not multiple)." |
| P-12 | Every seat carries a **verdict date** (settle discipline at the new price: 7 days SP / 14 days SB): graduate, step again, or give the seat up. The allowance share and the window are declared settings per calendar state — see P-13. | Prevents the queue becoming a parking lot; keeps the share and the window out of code. |
| P-13 | **Calendar states and their settings** (`DE_PLAN_CONFIG`, one row per state; the plan reads the table, never a literal): **OFF-PEAK** — window 7 complete days, allowance share 0.20 · **BOOST** (the run-up before a peak, `boost_start` → `peak_start` on the house calendar) — window 3 complete days, allowance share **0.50** (Ori, 2026-08-23: "in boosting phase (before peak) make it 50% instead of 20%") · **PEAK** — window 3 complete days, allowance share 0.20 until Ori says otherwise. Ori is not sure 0.50 is right — **the correct share per state is a learning question**: the scorecard (P-9) publishes, per state, the realized net of the seats opened under the share in force, and the backtest replays 0.20 / 0.35 / 0.50 per state so the setting is chosen on evidence (the retired LIFT engine used 0.40 in peaks — recorded, not adopted). | Before a peak the queue must open seats for seasonal terms that have no record yet; once the peak starts the money should already be seated. The 3-day window at boost_start follows the house calendar convention the budget engine already used. |
| P-14 | **The window is corrected for settle completion, and the demotion guard is asymmetric.** (a) **CORRECTION** — a window's gross profit is divided by the published completion factor for its channel and the day's age, read from `V_ADS_SETTLE_CURVE` (`sales_pct_of_final_median` per `channel` x `age_days`) as a table, never as a literal or a hardcoded factor; where the curve cannot answer for a channel and age the factor is 1.0 and the row says the correction was unavailable, and the plan then rests on (b) alone. **Spend is not corrected, and the window is FENCED so that it never needs to be** (v27.131 repair — the clause published here first was unconditional and is not true unconditionally). The same curve publishes spend at essentially 100% of final from age 2 and materially short at age 1; read it, never a literal: `SELECT channel, age_days, spend_pct_of_final_median, spend_pct_worst FROM V_ADS_SETTLE_CURVE WHERE age_days <= 2 ORDER BY channel, age_days`. P-10 does **not** guarantee age 2 on its own: `FN_ADS_ANCHOR_CAP()` advances to the current Los Angeles date at 22:00 LA, so a run in the last two hours of an LA day can leave the youngest window day at age 1, where spend reads short — understating the pot, the allowance derived from it, and every seat cost quoted at the repaired price, all in the same direction, with no error and no log line. So the plan's window is fenced: `window_to = LEAST(wm − 1, CURRENT_DATE('America/Los_Angeles') − 2)`. Before 22:00 LA the two terms are equal and the fence costs nothing; after it, the fence gives up one day rather than judge money on a day the warehouse has not finished writing. That makes the no-spend-correction claim true by construction instead of by the hour the orchestrator happens to run. `V_PLAN_WINDOW_JUDGMENT` (Task 1) owns the fence and publishes `window_to` on every row. **Order COUNTS are never inflated**: a count cannot be fractionally corrected, so the 2-order floor of P-3 is always read on observed orders. (b) **ASYMMETRIC GUARD** — a keyword may be PROMOTED to the good side on corrected fresh evidence, but it is never DEMOTED to the not-good side until its window has settled (SP 7 / SB 14 complete days after `window_to`). An unsettled would-be demotion of a keyword that was good keeps the good side, held, with its settle-due date on the row. "Was good" = the previous night's plan said GOOD, or the ladder's own settled 90-day record is at or above the family bar with 2+ settled orders (the bootstrap on the first night). (c) Every row publishes **which arm decided it** — `settle_arm` in `SETTLED` / `CORRECTED` / `PROMOTED_ON_FRESH` / `HELD_UNSETTLED` / `UNCORRECTED_NO_CURVE` — and `decided_by` in `P-3` / `P-14b` / `P-5`, and the book and the panel print it in words. | Ori raised the defect on 2026-08-23 and has **not ruled** between the three offered fixes; this is the build-as-specified answer, recorded so it can be overruled in one line. The window's sales are still accruing (SP ~D+7, SB ~D+14), so a 3-day window read today has seen a fraction of its orders and the not-good side is overstated -- the plan would park keywords for the crime of being recent. Correction fixes the AVERAGE; the guard fixes the TAIL, because a median curve still mis-reads an individual keyword and a wrong demotion costs a working keyword its seat and its price. House rule: unmeasured never reads as bad. **To overrule:** Ori says "judge the window as it reads" -- drop the `corr` CTE and the `HELD_UNSETTLED` arm from `V_PLAN_WINDOW_JUDGMENT`, and the matching arms from `rule_b()` in `tools/build_reprice_bulksheet.py`; every other object is unchanged. **WHERE IT IS LIVE (v27.132):** P-14 is built in `tools/build_reprice_bulksheet.py --rule-b`, which is the ONLY path judging keywords until Task 1 lands: the corrected margin, the `HELD_UNSETTLED` guard on the ladder's settled 90-day record as the declared bootstrap, and `settle_arm` / `decided_by` / `settle_due` on every audit row and in every printed reason. **A MEASURED CAVEAT ORI SHOULD SEE BEFORE RULING, published as a query and not a number** (`architecture/NEXT_WEEK_MONEY.md` §1b): arm (a) lifts the window's gross profit for the whole book, but it can only carry a keyword across a bar if that keyword ALREADY clears the order floor and sits just under the bar -- and the overstatement Ori described lives behind the floor, in keywords with one observed order or none, which this ruling's own sentence forbids correcting. So on live data arm (a) can be real and promote nobody, and arm (b) can only HOLD keywords that were already good. If that is what the query returns, the open ruling is whether the ORDER FLOOR should bend for an unsettled window -- a change to P-3, not to P-14, and nobody has made it. |

## 3. Windows and clocks

- Ads watermark `wm` = last complete ads day (`LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS`).
- Off-peak window = the 7 complete days ending at `window_to`. Peak window = the 3 complete days ending at `window_to`, where `window_to = LEAST(wm − 1, CURRENT_DATE('America/Los_Angeles') − 2)` — the fence of P-14a, so the youngest judged day is always at least two days old and its spend is settled (the anchor cap advances at 22:00 LA and would otherwise admit an age-1 day).
- Calendar state (OFF-PEAK / BOOST / PEAK) comes from `DIM_US_HOLIDAYS` (`boost_start`, peak, anchor dates for Back-to-School, Q4, Prime Day); window and allowance share per state are in `DE_PLAN_CONFIG` (P-13); the plan reads both, never a date literal.
- The plan is recomputed every night by the orchestrator (New York clock) after the keyword-state snapshot; Ori uploads at Weekly Run (Sunday) off-peak, every 3 days in peaks.
- Attribution lag is stated on every row: window sales are read as of the run day and are incomplete for the newest days (SP settles ~D+7, SB ~D+14). The plan uses them anyway (rule B); the shadow plan and the T+14 scorecard measure what that costs.

## 3a. Settle completion and the asymmetric guard (P-14)

The window record is read twice. **Raw** is what the warehouse holds today. **Corrected** divides each
window day's gross profit by the completion factor the settle curve publishes for that day's channel and
age, so a 3-day window read on the day after it closes is compared with the bar on the scale it will
eventually have. The factor is read from `V_ADS_SETTLE_CURVE` through `V_PLAN_SETTLE_COMPLETION`, which
makes it monotone in age (the published medians wobble by a point either way), caps it at 1.0, floors it
at a declared 0.50 so no rebuilt curve can ever inflate a window more than twofold, and marks the rows
where the curve has too few report dates to answer. Nothing here is a constant in code: if the curve is
rebuilt, the correction moves with it, and if it cannot answer the plan says so on the row.

The correction alone is not enough, because it is a median over the whole account and an individual
keyword can sit anywhere around it. So the side is asymmetric in time: **promotion is allowed on fresh
evidence, demotion waits for settlement.** A keyword that was good and now reads not-good on a window
younger than its channel's attribution length keeps the good side, held, and carries the date its window
settles. On that date it is judged again with no guard, and it goes where the settled record says. The
guard is self-clearing and costs at most one settle window of allowance; a wrong demotion costs a working
keyword its price, its seat and its ranking for as long as it takes anyone to notice.

## 4. The plan, per family, every night

1. **Judge** every enabled, non-defense keyword in the family on the window (P-3, with P-5 grace): `good` / `losing` / `waiting — one order` / `no sale` / `not serving` ($0, 0 clicks).
2. **Pot** = window spend of the `good` set (P-2). **Allowance** = share × pot, ramped (P-8).
3. **Candidates** for the not-good side: losing, one-order, no-sale, stalled probes, and the probe / revival candidates that LIFT's probe list and REVERDICT's revival list still nominate — those lists stay as candidate SOURCES; they no longer set a price or open a seat on their own (P-11). Each candidate gets a **seat cost** (P-6): its expected spend at its planned price (losers: the affordable price from the ladder's price logic, capped at three 5 % steps per upload; probes: the engine's seat economics `T_OOB_SEAT_ECONOMICS`).
4. **Rank** candidates (P-7). Walk the ranking: a candidate takes the lowest free seat while its cost fits the remaining allowance; continuing occupants keep their seat numbers (`DE_FAMILY_SEAT_LEDGER`, unchanged mechanism).
5. **Queue** everything that did not fit: parked at the channel park price (`bid_park`) or paused if already closed — zero planned spend. A candidate queued for a full window with no seat is a kill candidate (probation rule unchanged: bid to the floor, probation, then kill).
6. **Moves** = one executable instruction per not-good keyword: re-price / park / pause / open probe. The good side gets none.
7. **Budgets**: a campaign's planned budget = the sum of its keywords' planned spend (good keywords at their window spend, seats at seat cost, queued at zero), rounded to the house budget rules (forbidden band $20.01–$31.99 respected). Shown AND moved — this plan owns budgets (P-11).

## 5. Two plans, one executed

- **Plan B** (executed): sections 3–4 as written.
- **Plan A** (shadow): identical except step 1 uses the ladder's state for the side (winning / at bar / waiting = good side; the rest not-good) and the window only for amounts.
- Both plans are written nightly to `FACT_PLAN_NEXT_WEEK` (one row per family × keyword × plan), never deleted. The preflight marks which plan is live (`DE_PLAN_CONFIG.live_plan = 'B'`).
- **Scorecard**: at T+14 the settled record of each keyword is compared with what each plan allocated to it; per family and per calendar state (off-peak / peak) the scorecard publishes which plan's allocation tracked realized net profit better. One declared decision rule turns that into a recommendation to switch the window or the live plan; Ori flips the setting, never the code.
- **Backtest** (before go-live): replay both plans weekly over Sep 2024 → today, by calendar, scoring each week's plan against the following window's realized net. Published as a report with its query; no pinned numbers in the SOP.

## 6. One engine — ownership in the preflight

`SP_ENGINE_PREFLIGHT` gains a fourth exclusion source, ordered after HOLDOUT and before the collision arm:
**PLAN-OWNED** — for a key (campaign, keyword) in a working family, any LIFT / OOB / REVERDICT bid or
budget proposal is EXCLUDEd with `verdict_reason = "held — the plan owns this keyword's price"` and
`hold_source = 'PLAN'`. Nothing is deleted; the held row is the counterfactual the scorecard reads.
The plan's own rows enter `FACT_ENGINE_PROPOSALS` as `engine = 'PLAN'` with top precedence on BID and BUDGET
for working families, so Weekly Run shows ONE list, counts by owner, and exports ONE bulksheet through the
existing DoPage path. LOW_STOCK keeps its override (it is the owner of its campaigns); NEGATE rows are
unaffected; launch families are untouched; holdout campaigns are excluded from every export from
2026-09-01.

The reprice book and the leak book become the PLAN's producers (same sign gates, cap, floors, portfolio
echo, PENDING_UPLOAD batches, `--mark-uploaded` / `--supersede` on PENDING rows only, restore sheets).

## 7. Safety

Never delete a change-log row · batches are `PENDING_UPLOAD` until Ori says `--mark-uploaded` · a restore
sheet for every book · holdout excluded from every sheet from its `eligible_from` · the family pot is read,
never grown · no engine other than the plan moves a working family's bid or budget · nothing uploads itself.

## 8. Not in this plan

The ladder's verdicts, bars and floors (still computed; the shadow judge and the grace rule read them) ·
the three rulings on Ori's desk (product targets with no keyword id; the park-price source; the
overdue-settle ladder fix) · launch governance (`V_INVEST_STATUS`) · brand defense (never judged on profit).

## 9. Guarantees, asserted at deploy and in `V_ENGINE_HEALTH`

- Window = complete days only: every row's `window_from/window_to` ≤ `wm − 1`; no window touches the filling day.
- Pot reconciliation: good-set window spend = pot to the cent; seats + queued = not-good side; allowance = share × pot (ramped) to the cent.
- Every not-good keyword has exactly one seat or one queue position and exactly one move; no good keyword has a move.
- Seat numbers stable across days for continuing occupants; freed numbers reused lowest-first.
- Grace: no settled winner is moved to the not-good side after a single quiet window.
- Ownership: zero GO rows from LIFT / OOB / REVERDICT on BID or BUDGET in working families; every held row carries the plan's sentence.
- Both plans written every night; determinism (two uncached pulls identical); backtest reproducible from its query.
- Settle correction (P-14a): the corrected window gross profit never changes sign against the raw one and is never smaller in magnitude (a factor below 1 scales a profit up and a loss down — more unsettled orders are still arriving on both); no window day is younger than age 2; every row names its `settle_arm`, and a row whose curve could not answer says `UNCORRECTED_NO_CURVE`.
- Asymmetric guard (P-14b): no keyword that was good is on the not-good side while its window is unsettled; every `HELD_UNSETTLED` row carries a settle-due date in the future; promotion on fresh evidence is allowed and counted.
- Standing Rule 0: no measured figure pinned in an SOP, header or registry entry.

## 10. What Ori sees on Weekly Run

Per working family: the pot and the allowance (with the ramp step), the seats by number — occupant, cost,
move, verdict date — the queue in rank order, the campaign budgets the plan implies, the A-vs-B
disagreement count with one sentence on what it means, and one download. Figures are illustrative until
built; every published sentence is plain language a new user can act on.
