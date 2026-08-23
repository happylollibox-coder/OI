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

## 2. Rulings (made in conversation 2026-08-23; each overrulable by one line)

| # | ruling | why |
|---|---|---|
| P-1 | **Rule B judges the window:** good / losing is decided on the window itself (7 complete days; 3 in peaks), not on the ladder's 90-day record. | Ori: "I think the answer is B" — and it is a learning question (P-9). |
| P-2 | **Pot = what the family's GOOD keywords actually spent in the window.** The allowance for not-good keywords = `k.allowance_share` (0.20) × that. Lollibox example: $3,500/week good → $700/week = $100/day not-good. | Ori's example, verbatim. Not 20% of the family total. |
| P-3 | **Good = at or above the family bar (gross profit per ad dollar, `T_FAMILY_BAR`) with 2+ orders in the window.** One order = "waiting — one order" → not-good side. Spent with no sale → not-good side. Below the bar with 2+ orders → losing. | Ori took the recommendation. One order at 3× is mostly luck; the 2-order floor is the cheapest guard. Measured 2026-08-23 (illustrative): the floor keeps 80–85% of each working family's window spend on the good side. |
| P-4 | **The good side is never cut and is not re-allocated.** Its keywords keep earning as they are; their prices are left alone by this plan. | Ori: "only the losing keywords get budgeted by the seats queuing method." CPC study: holding pays, churn loses. |
| P-5 | **Grace for proven winners.** A keyword the ladder calls a settled winner (`WINNER` / `PACED_WINNER`) that has a quiet window stays on the good side for ONE window, held, not cut. Two quiet windows in a row and rule B stands. | Measured 2026-08-23: 12 LolliME and 8 Lollibox settled winners had a quiet week; pure B would push them into the queue — cutting winners on noise, which the data already convicted. The ladder buys time, never money. |
| P-6 | **Seat cost = spend at the repaired price**, not last window's spend. | One $139/day repair would otherwise eat Lollibox's whole ~$61/day allowance alone. |
| P-7 | **Rank = dollars at stake × closeness to the bar** (window spend × window return ÷ bar), ties by clicks. Best first. | "Closest first" alone seats a $0.50/day keyword before a $50/day one; rank by how much money a repair could bring back. |
| P-8 | **Ramp the allowance over three windows**: close one third of the gap between today's not-good spend and the allowance each window, like the three-step bid cap. | Lollibox not-good ≈ $196/day vs ≈ $61/day allowance: the cliff would park two thirds in one upload. |
| P-9 | **Learning: B live, A in shadow, both backtested now.** A = the ladder decides the side, the window decides the amount. Both plans are written every night, both graded by the settled scorecard at T+14; the window per calendar is a declared setting the learning may change. | The holdout (10 %, from 2026-09-01) answers "engine vs nothing", not "A vs B". |
| P-10 | **Complete days only.** The window is `k.window_days` complete days ending at the ads watermark − 1 (America/Los_Angeles); the filling day never enters a window. Peaks: `k.peak_window_days` = 3 complete days. | Ori: "make sure you are calculating 7 days by entire days and not partial." House convention since 2026-08-17. |
| P-11 | **One engine.** For working families the plan is the sole authority on keyword bids and campaign budgets. LIFT and OOB retire as price and budget authorities for these families (their proposals are still recorded and held — "the plan owns this price" — so the scorecard can grade them); LIFT's probe list and REVERDICT's revival list remain candidate sources for the seat queue. Programs that do not set prices stay: negates (search-term blocking), low-stock override, launch controller (INVEST families), holdout. | Ori: "there should be one engine (and not multiple)." |
| P-12 | Every seat carries a **verdict date** (settle discipline at the new price: 7 days SP / 14 days SB): graduate, step again, or give the seat up. The allowance share is a **declared setting per calendar** (`DE_PLAN_CONFIG`), 0.20 everywhere today; the peak value is learnable. | Prevents the queue becoming a parking lot; keeps the share out of code. |

## 3. Windows and clocks

- Ads watermark `wm` = last complete ads day (`LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS`).
- Off-peak window = the 7 complete days ending at `wm − 1`. Peak window = the 3 complete days ending at `wm − 1`.
- Peak = the house calendar's boost windows (`DIM_US_HOLIDAYS`: Back-to-School, Q4, Prime Day); the plan reads the calendar, never a date literal.
- The plan is recomputed every night by the orchestrator (New York clock) after the keyword-state snapshot; Ori uploads at Weekly Run (Sunday) off-peak, every 3 days in peaks.
- Attribution lag is stated on every row: window sales are read as of the run day and are incomplete for the newest days (SP settles ~D+7, SB ~D+14). The plan uses them anyway (rule B); the shadow plan and the T+14 scorecard measure what that costs.

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
- Standing Rule 0: no measured figure pinned in an SOP, header or registry entry.

## 10. What Ori sees on Weekly Run

Per working family: the pot and the allowance (with the ramp step), the seats by number — occupant, cost,
move, verdict date — the queue in rank order, the campaign budgets the plan implies, the A-vs-B
disagreement count with one sentence on what it means, and one download. Figures are illustrative until
built; every published sentence is plain language a new user can act on.
