# FAMILY_SEAT_REGISTER — the 80/20 doctrine for working families

**Born:** 2026-08-22. **Owner request (verbatim):** "for working families (not launch in the last 3
month) make sure 80% of budget is for winning or margin keywords / the other 20% should be for
losing … number them per family so you always know what seat you are opening and what you are
probing or waiting for results." Design spec: `docs/superpowers/specs/2026-08-22-family-seat-register-design.md`
(Approach A, approved). Plan: `docs/superpowers/plans/2026-08-22-family-seat-register.md`.

**Status:** Task 1 (the ledger) SHIPPED 2026-08-22; repaired the same day (rulings R-a / R-b
encoded, ledger memory added, plain-sentence reasons); polished with Task 2 (snapshot-dated
window, raise-bounded click count, no silent catch-all, brand words). Task 2 (the register view
`V_FAMILY_SEAT_REGISTER`, rulings R-c / R-d / R-e) SHIPPED 2026-08-22; repair pass 2026-08-22
(rulings R-f … R-k, defects D1–D14 closed: sign-aware stalled proposal, per-family at-the-line
band, parked seats, overdue settling, not-yet-serving trials, product-target gaps, three-way
queue defense, whole-phrase brand match, two-digit dates, one raise clock, horizon-true counts).
Second repair pass 2026-08-22 after verification: R-k REFINED — gap rows worded by their
MEASURED cause (the blanket "the ladder does not track product targets" was false on live rows
and is retired; see the R-k ruling and Open ruling 7), and the FAMILY "what closes the gap"
sentence made HONEST — when the listed moves recover less than the gap it says so and names
what does (gap-closure honesty, B29). Third repair pass 2026-08-22: that closing promise counts
ONLY money a person recovers by doing what the row lists today — the repair dollars had been added
to it, so a family could read "enough to close the gap" off a small executable total plus a large
re-judged-horizon projection; B29 was rewritten to re-derive the executable total from the
register's own rows instead of from the sentence, and B30 to forbid the projection ever wearing the
`(−$…/day)` form. Fourth repair pass 2026-08-22: **R-l settled the arithmetic** — only a PAUSE
counts as recovered today; parking a stalled probe and re-pricing a repair each get their own named
line outside that total, and the closing sentence reads in one fixed order (recovery, gap, verdict,
what the rest depends on, pointer to the re-judged row). B29 re-derives the figure from the
register's own per-row costs with a stated tolerance, B30 keeps the two non-recovering lines named
and excluded, B31 asserts the order. Fifth repair pass 2026-08-23: **R-l binds the two projections
and the promise as well** — the re-judged horizon stopped modelling a parked stalled probe as $0
(B33), both projections stopped booking changes for holdout campaigns that get no sheet row (B34),
and the FAMILY row names the book its pauses ride on instead of promising an upload today (B32).
Read the numbers from the view, never from this file.
Tasks 3–5 (leak generator arm, morning surface, health checks) pending — this file grows with each;
until Task 3 ships, the leak half of the recovered-today figure has no generator behind it (open
ruling 12).

**Which clock every date in this file is on.** Data dates (`snapshot_date`, `opened_on`, `closed_on`,
basis windows) are Los Angeles, the warehouse clock. Pass times (`LOG_PIPELINE_RUNS`, when a routine
was deployed) are New York, the orchestrator clock. Dates recording when a ruling was made or a
measurement taken are the same two clocks — **never the author's local clock**. This paragraph exists
because a repair pass wrote its own record as 2026-08-23 while it was still 2026-08-22 in both New
York and Los Angeles: the author's machine runs on Israel time, seven hours ahead of New York, so
every evening's work lands on tomorrow's date locally. A reader comparing a record header here to a
ledger `opened_on` or a `LOG_PIPELINE_RUNS` `run_date` was off by a day. Every such date has been
corrected to the warehouse clock — 46 of them, on 43 lines, across this file, `config.yaml`, four
SQL sources and one deployed table description; count it yourself against a pre-fix backup with
`grep -o '2026-08-23' FILE | wc -l` (the per-file line count is not the occurrence count, and a
repair pass once published the one for the other). Before dating anything in this file, read the clock you mean:
`TZ=America/New_York date` / `TZ=America/Los_Angeles date`.
**Drift check 2026-08-22** (see "Drift check" below): the two new steps are DEPLOYED but had not yet
run inside an orchestrator pass; the ledger and the seat-economics table have only ever been written
by hand. The drift instrument the A-suite was missing now exists
(`scripts/bigquery/tests/DE_FAMILY_SEAT_LEDGER_drift.sql`, D00–D08).

## The doctrine in one paragraph

For the WORKING families — the HARVEST book in `V_BOOK_ASSIGNMENT`; the launches (INVEST) are
outside the doctrine entirely — 80% of spend should sit on keywords that are winning, at their bar,
or waiting for a verdict with volume. The other 20% is a dollar-sized allowance of NUMBERED SEATS,
each holding one keyword the family is knowingly paying for while it is repaired, on probation,
failed, probed, stalled in a probe, or settling. Closed-but-spending and untracked spend also count
on the 20% side: a family cannot pass by hiding spend in the cracks. The register prescribes keyword
moves executed by MANUAL bulksheet; campaign budgets are shown, never moved. No engine reads the
register.

## Rulings (from the spec, binding)

| question | ruling |
|---|---|
| Working families | HARVEST book. Launch families appear only as a labelled reference block, never judged on profit. |
| 80% side | winning + marginal (at bar) + waiting for results. |
| 20% side | losing + everything not earning or being tested: closed-but-spending, untracked. |
| The lever | keyword moves by manual bulksheet. Budgets shown, never moved. |
| A seat | a dollar-sized slot in the 20% allowance, occupied by one keyword; numbers are stable per keyword, not per rank. |
| Occupants | REPRICE (repair), FLOOR_PROBATION (probation), LOSER (failed), TRIAL keywords in a probe position (probe / stalled probe — see the two probe rulings below), REVIVED_SETTLING / PENDING_SETTLE (settling — reported on the 80% side, seated on the 20% ledger). |
| Brand defense | never seated, never given a profit-based move (house rule: defense is never judged on profit). A seated keyword that becomes defense is closed `DEFENSE_EXEMPT`. The register shows defense spend as its own category OUTSIDE both sides of the ratio. **Defense is tested three ways** (Task 2): the ladder's `is_brand_defense`, the campaign-name rule the ladder's source uses (`V_BID_CPC_TRANSFER`: "BRAND DEFENSE" in the name), and the keyword text against the house brand phrases (`DIM_BRAND_PHRASES`, `phrase_type = 'BRAND'`) — the flag alone misses brand-word keywords in SB campaigns (the Bottle "happy lolli truth or dare" trials). Never a literal list in a view. |
| **R-a — a probe** (2026-08-22) | A TRIAL keyword on the engine's own probe list `T_LIFT_PROBES` (a bid raised within the engine's probe window with fewer than the verdict's clicks since; the set `V_OOB_KEYWORD` calls `is_lift_probe`) is a seat **whether or not it spent this week** — it costs $0 today and still answers "what am I probing". A TRIAL keyword at the **park bid** — the ladder's `at_floor` (the live bid observed at the channel floor `FN_BID_FLOOR` publishes, never a literal) — that the engine does NOT list is a seat **only with spend** in the basis window: a floor-priced keyword buying nothing is idle, not a probe. |
| **R-b — a stalled probe** (2026-08-22) | A TRIAL keyword parked at an activation entry bid — its latest applied bid change in `V_PPC_CHANGE_LOG_APPLIED` is an `INCREASE_BID` that still stands: the live bid is **at or above** the logged `new_bid` and above the logged `old_bid`, never lowered since — past the engine's probe window (`k_probe_window_days`) with fewer than the verdict's clicks (`k_verdict_clicks`) since, no longer engine-listed and not at the floor, is a **STALLED PROBE**: a seat on the 20% side with a standing proposal (re-price to the seat price, or park), NOT "waiting for results" on the 80% side. A test that cannot produce a verdict at its pace is not a test. The set is read from the data on every run (the change log × the snapshot), never from a list. **At or above, not equal** (repair pass 2026-08-22): the generator's $1.00 activation floor can lift a bid past the logged raise after the log row is written (a known defect), so a keyword logged as a +$0.02 nudge but sitting live at $1.00 is exactly the parked entry this ruling names and is seated. **The change log is the authority for the raise date**: a bid raised with no applied log row at all has no date to age, reads WAITING on the 80% side, and is not seated — a raise outside the log is a logging gap to close, not a position to guess. A `REDUCE_BID` that lands on $1.00 is a cut, not an entry, and reads WAITING. |
| Waiting | A TRIAL keyword in none of the three probe positions (engine-listed; at the floor with spend; stalled) is WAITING on the 80% side and is never seated. |
| **R-c — engine parity stands** (2026-08-22, closes Open ruling 1) | Any standing applied raise that expired the engine's own test is stalled, whatever its size: a keyword that could not buy the verdict's clicks in the probe window at its raised bid is neither earning nor being tested. The register publishes the raise on the row (`raise_old_bid → raise_new_bid`, `raised_on`, `clicks_since_raise`, `days_since_raise`) and words the sentence by its size: a raise of `k.entry_raise_ratio` (1.5×) or more reads "entered at $1.00 on Aug 4 — 8 clicks in the 17 complete days since"; a smaller one reads "was nudged $0.45→$0.47 on Aug 4 — 0 clicks …"; a bid lifted past the logged raise adds ", now sitting at $1.00". Proposal on both, superseded by R-f (2026-08-22): the move branches on the sign of (seat price − live bid) and the park price is the engine's published `bid_park`, never the floor and never a literal. The seat price is READ from the budget engine's seat economics (`T_OOB_SEAT_ECONOMICS.seat_cpc`, materialised from `V_OOB_KEYWORD`), never restated; a campaign outside the engine has no seat price and the sentence says so. |
| **R-d — no test clock** (2026-08-22, closes Open ruling 2) | A TRIAL whose bid moved (more than one distinct bid in `DIM_KEYWORD`'s history) with NO applied change-log row — or away from the last logged bid since, other than the activation-floor lift R-b already treats as the raise standing — is NOT seated and is NOT "waiting": it is its own category **"waiting — no test clock"** on the 80% side, with the sentence "this bid was set outside the change log, so there is no date to judge it from" and the move "log the bid (or restore it by sheet) so the clock can start". A `REDUCE_BID` that lands on an entry price is a cut, not an entry (Bottle "truth or dare game" stays waiting). |
| **R-e — idle at the floor** (2026-08-22) | A TRIAL at the park bid with $0 spend and 0 clicks in the basis window is the category **"idle at the floor"**: $0, shown so nothing is silent, on neither side (no ratio is affected). |
| **R-f — a stalled probe at or above the seat price is parked, never "raised"** (2026-08-22) | The stalled-probe proposal branches on the SIGN of (seat price − live bid). Live bid BELOW the seat price: "raise to the seat price $X to get a verdict". Live bid AT OR ABOVE it: it could not buy a verdict even at the seat price, so the move is "park it — bid to the engine's park price and let the ladder's revive cycle re-test it". The park price is the engine's own `bid_park`, published by `V_OOB_KEYWORD` (column added 2026-08-22) and read through `T_OOB_SEAT_ECONOMICS` — never a literal; a campaign outside the engine has no seat price and is told so, with the same park price. A "raise" to a price at or below the live bid is never printed (asserted, B10). **`bid_park` is not a floor and not a channel price.** It reads $0.25 on all 212 rows of `T_OOB_SEAT_ECONOMICS` today across all nine engine roles, while `bid_floor` on those same rows ranges $0.10–$0.25 and only 69 of them are SB — so the flat $0.25 is the house PARK price the engine's PARK / PARK_WAIT actions bid to, which happens to coincide with the SB video floor and sits ABOVE the $0.10 and $0.20 floors. Calling it "the SB video park price" is wrong twice over: it is not SB-only and it is not a floor. (The same confusion once cost three phantom kills — the keyword-state ladder borrowed `bid_park` as a flat floor; see `V_BID_FLOOR` / `FN_BID_FLOOR`.) *To overrule:* name another park source (e.g. the channel floor `FN_BID_FLOOR`) — the register then reads that column; no literal. |
| **R-g — the at-the-line band is the judged family's OWN noise** (2026-08-22, closes Open ruling 2) | `at_line_band` is derived per family: stddev ÷ mean of THAT family's daily spend over the 28-day context window ÷ √(basis days). One family's spend level never decides whether another is at the line, and the band is a RATIO published in POINTS, never a dollar figure — a small family's spend is noisier relative to its own mean than a large one's, which is the whole reason the band is per-family. Do not pin the number (Standing Rule 0) — read it: `SELECT family, at_line_band, at_line_band_derivation FROM onyga-482313.OI.V_FAMILY_SEAT_REGISTER WHERE row_type = 'FAMILY' AND horizon = 'today'`. The band and its derivation in words are published on every FAMILY row (B25 re-derives it). *To overrule:* name a pooled or fixed band — it becomes a declared constant in `k`, recorded here, never a hidden literal. |
| **R-h — a parked keyword with an appointment is a seat, not a leak** (2026-08-22) | The ladder parks a keyword at the park bid WITH a re-verdict appointment (`FACT_KEYWORD_STATE.next_check_date`): until that date it is being tested by the revive cycle. PARKED + spend on the basis window + appointment on or after the snapshot date = a SEAT, occupant kind **"parked — awaiting re-verdict"** (20% side, cost = its spend, move "no move — re-judged on <date>"). PARKED past its appointment with spend, or DEAD with spend = LEAK (pause row). **Which case held (measured 2026-08-22):** every PARKED row on the snapshot carried a usable `next_check_date` (the `next_check_what` texts read "re-read at settle" / "14d revival sweep re-checks" / "revival proposed"), so the appointment reading is LIVE; the spec's original all-leak reading was not needed. The ledger seats them (`SP_MAINTAIN_FAMILY_SEATS`; closure code `PARK_LAPSED` when the appointment passes or the spend stops; A16). *To overrule:* treat every PARKED spender as a leak — one branch in the occupant set and the code, the acceptance rows A16 / B26 flip with it. |
| **R-i — an overdue settling verdict is named overdue** (2026-08-22) | `REVIVED_SETTLING` / `PENDING_SETTLE` with `next_check_date` before the snapshot date stays on the 80% side (waiting = 80, Ori's ruling) but the sentence and the move read "was due to settle on <date> — overdue by N days; the ladder has not re-judged it". The cause is upstream and is being diagnosed read-only; the register never changes the ladder (B18). *To overrule:* move overdue settling to the 20% side — one side value in the codes table. |
| **R-j — "too few clicks yet" needs clicks** (2026-08-22) | "waiting — too few clicks yet" requires clicks > 0 on the basis window (spec §3). A TRIAL with $0 and 0 clicks that is neither at the floor nor no-clock is **"waiting — not yet serving"**: $0, published, on no side (affects no ratio) (B27). *To overrule:* fold it back into waiting — one branch in the code. |
| **R-k — a gap is worded by its MEASURED cause** (2026-08-22; refined the same day after verification) | The original reading — "the verdict ladder reads `DIM_KEYWORD` only, so a product target never gets a verdict" — was FALSE on live rows: SP product targets live in `DIM_KEYWORD`, the ladder tracks them and this register seats them (repairs, probes, settling and parked seats with `asin=` targets exist on the snapshot; query the SEAT rows for `asin=` to see them — and when COUNTING product targets, match `asin=` OR `category=`: the snapshot carries both prefixes, and an `asin=`-only count silently drops the `category=` rows, a mislabel a verification pass actually caught). The real blind spot is narrower: SB video / PT product-target rows reach the warehouse with **`keyword_id` −1** — no keyword id, so no `DIM_KEYWORD` row can exist and the ladder cannot see them. Every GAP row is therefore worded by the cause the view MEASURES (`keyword_id` and the current `DIM_KEYWORD` state): `keyword_id` −1 → "no keyword id — the ladder cannot see it; a ruling for Ori, not a mapping fix"; a paused/archived current row → "trailing spend — leaves the universe when it stops; no verdict is coming and none is needed"; an enabled row → "verdict arrives on the next state run"; a real id with no current row → "check why". The blanket phrase "the verdict ladder does not track product targets" is retired and B19 asserts it appears nowhere. **Extending the pipeline/ladder to the no-keyword-id SB video rows is a RULING FOR ORI**, not built here. *To overrule:* give those rows an identity the ladder can read (or extend `SP_SNAPSHOT_KEYWORD_STATE` to a synthetic key) — the blind gap rows then disappear on their own. |
| **R-l — the gap-closure arithmetic** (2026-08-22, settled; three verifier rounds died on it) | A family's "what closes the gap" clause may count as RECOVERED TODAY only dollars that provably leave the bad side when the sheet lands — that is, a **PAUSE** (the keyword's spend goes to $0) and nothing else: a leak paused, or a failed keyword killed with a pause row. A row in a holdout campaign gets no sheet row from its `eligible_from`, so it recovers nothing either. **Parking a stalled probe LOWERS its price; the spend does not vanish** — it is its own line, its dollars named as spend at risk of continuing, and it is EXCLUDED from the recovered-today total. **Re-pricing a repair recovers nothing today by construction** — its own line too, named as a change of price whose result arrives at the re-judged horizon. The sentence must, in this order: name the executable recovery (pauses only), name the gap, state plainly whether the recovery closes it, then say what the remaining dollars depend on and point to the family's re-judged row. No projection may appear inside the recovered-today number, and no sentence may claim a closure its own executable recovery does not deliver. The acceptance check re-derives the recovered-today figure from the register's OWN per-row costs — the today-horizon LEAK rows and failed SEAT rows, holdout-suppressed rows removed — and never from the sentence it is testing, comparing within a **$0.02** tolerance whose reason is on the row: the sentence renders one aggregate to two decimals while the re-derivation sums per-row costs each rounded on its own row (R-m). B29 / B30 / B31. **R-l binds the PROJECTIONS too (2026-08-23, fifth repair pass).** (a) The re-judged horizon used to model parking a stalled probe as taking the spend to $0 — the very belief R-l retired — in the exact row the today sentence points the reader at. A stalled probe is now re-priced by the move on its OWN row (R-f: raise to the seat price where the live bid is below it, otherwise park at the engine's park price) and keeps spending at that price on the same linear bid→spend guess the day-one horizon uses; it stays on the 20% side until a verdict arrives (B33). (b) Both projections respect the holdout arm: a campaign in the holdout arm from its `eligible_from` gets no sheet row of any kind, so neither day one nor re-judged may book a change for it — its cost on both equals its cost today, a repair in one never moves to the good side and keeps the 'losing — in repair' category, and the family clause lists no move for it (B34; B10 and B11 carry the same guard). (c) The FAMILY row names the BOOK its pauses ride on instead of promising an upload 'today': every dollar of the recovered-today figure rides the next book a generator builds — the leak arm of `tools/build_reprice_bulksheet.py` for a leak (Task 3, not yet shipped), the shipped reprice generator's pause row for a failed keyword — exactly as the LEAK row's own move already said. The arithmetic is untouched; only the promise is (B32). **(d) The leak half binds the projections too (2026-08-23, sixth repair pass).** (c) changed the today sentence and left both projections crediting the same unbuilt sheet: `cost_day1` and `cost_rejudged` took every LEAK row to $0, and the published day-one assumption attributed that pause to the PENDING_UPLOAD book — a book that carries bid changes only. Neither projection zeroes a leak now: a leak costs on day one and on re-judged what it costs today (a book row that touches one re-prices it linearly like any other keyword, never to $0), both assumptions name the unbuilt leak arm the dollars wait on, and the projection sentence reads "N leaks still costing $…/day (nothing pauses them until the leak arm ships)" instead of "N leaks paused". The FAILED half is untouched and still goes to $0 on re-judged, because the shipped generator builds that pause row today — same rule, opposite answer, because one sheet exists and the other does not (B35). *To overrule:* ship the leak arm — the sheet then exists and the branch is one line in the same two CASE expressions, with B35's first three legs flipping with it. *To overrule (the original rule):* name another move whose dollars provably leave the bad side on upload — it joins the pause set in one branch of the view and the same branch of B29. |
| **R-m — report prose is not an artifact** (2026-08-22) | A number in an agent's report is ephemeral. A false or drifted figure blocks ONLY if it lives in a committed file or a published sentence, cited `path:line`; otherwise it is a note. **Rounding differences of one cent between an aggregate and the sum of independently rounded components are display facts, not defects** — stated here once, and not re-litigated anywhere in this design. Every tolerance a check uses carries its reason on the check. |

## Objects

| object | role | status |
|---|---|---|
| `DE_FAMILY_SEAT_LEDGER` | The only state the register keeps: one row per occupancy (family, campaign_id, keyword_id, opened_on) with `seat_no`, `closed_on`, `closed_reason`, `closed_reason_text`, `occupant_kind_at_open`, `last_observed_kind`, `last_observed_state`. | shipped |
| `SP_MAINTAIN_FAMILY_SEATS` | Orchestrator Task 20.8b, right after `SP_SNAPSHOT_KEYWORD_STATE`. Closes, reopens, admits, observes. Idempotent on the same snapshot. | shipped |
| `V_FAMILY_SEAT_REGISTER` | FAMILY / CATEGORY / SEAT / OPEN_SEAT / LEAK / GAP / NO_CLOCK / ABSORB / REFERENCE / UNMAPPED rows — the object Ori reads. | shipped |
| `T_OOB_SEAT_ECONOMICS` | The budget engine's seat economics (slots, seat_rank, seat_cpc, role, and since 2026-08-22 the engine's park price `bid_park` — R-f) materialised once per pass from `V_OOB_KEYWORD` by `SP_REFRESH_CUBE_TABLES` step 0b, right after `T_LIFT_PROBES`. Exists because `V_OOB_KEYWORD` is a planner-ceiling view measured in minutes and the register may never inline it. | shipped |
| leak arm of `tools/build_reprice_bulksheet.py` | pause rows + ad-group-grain negates for closed-but-spending keywords. | Task 3 |
| `V_DAILY_BRIEF` SEATS section, `SeatRegister` cube | the morning surface. | Task 4 |
| `V_ENGINE_HEALTH` checks | reconciliation, idempotence, every occupant numbered. | Task 5 |

## The seat lifecycle (Task 1 — what the ledger does)

**The occupant set** is read from `FACT_KEYWORD_STATE` — which holds exactly ONE snapshot, see
"Memory" below — working families only:

| ladder state | occupant kind |
|---|---|
| `REPRICE` | repair |
| `FLOOR_PROBATION` | probation |
| `LOSER` | failed |
| `REVIVED_SETTLING`, `PENDING_SETTLE` | settling |
| `TRIAL` AND (on the engine's probe list `T_LIFT_PROBES`, spend or not — OR `at_floor` with spend in the basis window) | probe (R-a) |
| `TRIAL` AND not engine-listed AND not `at_floor` AND the latest applied bid change is an `INCREASE_BID` that still stands (live bid ≥ its `new_bid` and > its `old_bid`), dated on or before today − `k_probe_window_days`, with fewer than `k_verdict_clicks` clicks since | stalled probe (R-b) |
| `PARKED` AND spend in the basis window AND `next_check_date` on or after the snapshot date | parked — awaiting re-verdict (R-h) |
| any state AND brand defense (three-way test; brand phrases matched as WHOLE phrases on word boundaries — D9) | never an occupant |

The basis window is the `k_basis_days` (declared 7) complete days ending at the ads watermark − 1,
where the watermark is `LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS` — the same
anchor the ladder uses. `k_probe_window_days` (declared 14) and `k_verdict_clicks` (declared 20)
mirror the engine's own probing test in `V_KEYWORD_LIFT` (raised within 14 days, under 20 episode
clicks) — a stalled probe is that test expired; if the engine changes them, change them here.
The window is aged against the SNAPSHOT date (`run_day`), never the wall clock, so the occupant
set is a pure function of the snapshot; the clicks since the raise are counted on complete days
(before the watermark) from the raise date itself — the ads scan starts at the basis window or
the oldest standing raise, whichever is earlier — so the count is never truncated by a fixed
window (`FACT_AMAZON_ADS` is partitioned by year: the dry-run byte bound is the same as the old
120-day scan; only the rows read change).
Every kind except the floor-priced probe is seated on its verdict alone, spend or no spend (a
repair with no spend this week is still in repair — its seat simply costs nothing today; an
engine-listed probe with no clicks yet is still being funded; a stalled probe with no clicks is
exactly the problem). Only a TRIAL keyword at the park bid needs spend to be seated. Spend
therefore never flips a seat day to day: a probe seat closes when the engine drops the keyword
from its list or its bid leaves the floor, not when a quiet week passes.

**Probe-list freshness.** `T_LIFT_PROBES` is rebuilt by `SP_REFRESH_CUBE_TABLES` (Task 21), which
runs AFTER this procedure (20.8b) in the same orchestrator pass, so the list read is the previous
pass's. Deliberate: inlining `V_KEYWORD_LIFT` here cost tens of seconds and risks BigQuery's
planning limit, the engine's probe window is two weeks, and the register never reads a ceiling
view.

**Admission.** An occupant with no open row gets the LOWEST seat number not held by an open row of
its family. Several admissions in one run are ordered totally (kind: repair, probation, failed,
settling, parked, probe, stalled probe; then spend DESC, campaign_id, keyword_id) and take the free
numbers in ascending order, so a run is deterministic and reproducible.

**Stability.** A continuing occupant's number is never touched. It is kept for as long as the
keyword stays seated, whatever its kind becomes (repair → probation → failed is the ladder doing
its job, not a new seat). `occupant_kind_at_open` records what the seat held on admission;
`last_observed_kind` is what it held on the latest run; the CURRENT kind is the ladder's, read
live by the register.

**Memory.** `FACT_KEYWORD_STATE` is `CREATE OR REPLACE`'d by `SP_SNAPSHOT_KEYWORD_STATE` on every
run and holds exactly one snapshot. A keyword still on the snapshot does carry `prior_state` — the
snapshot procedure reads the old table into `prior_snapshot` before replacing it — so "what did
this keyword read yesterday" CAN be asked of it for a keyword that is still there. A keyword that
has VANISHED from the snapshot (paused or archived in Amazon) has no row at all, and the vanish is
precisely the KILLED-vs-PAUSED question. For that keyword the ledger is the only memory: on every
run each OPEN row is stamped with `last_observed_kind` / `last_observed_state` from today's
occupant set (re-stamping the same snapshot writes the same values). When a keyword vanishes,
KILLED vs PAUSED is decided from `last_observed_state`; a row opened before the memory columns
existed (NULL) falls back to the kind it opened with.

**Closure.** An open row whose keyword is no longer an occupant is closed on the snapshot date with
one reason code and the same reason as one plain sentence (`closed_reason_text`), first match
wins. The sentences below are the ones written to the ledger, asserted by the acceptance test, and
to be shown wherever a person reads the code:

| code | the sentence a person reads |
|---|---|
| `KILLED` | The keyword is gone from the snapshot after its last verdict was failed or dead, or the ladder now reads dead: the book paused a failed keyword. The seat is free. |
| `PAUSED` | The keyword is gone from the snapshot, or the ladder now reads parked, without a failed verdict first. The seat is free. |
| `PARK_LAPSED` | The keyword reads parked on the ladder but is no longer a parked seat: it has no spend on the basis window, or its re-verdict appointment has passed. A parked keyword that still spends past its appointment is a leak (pause row). The seat is free. (R-h, 2026-08-22.) |
| `LEFT_FAMILY` | The keyword is still tracked but now belongs to another family, or its family left the working (HARVEST) book. The seat is free. |
| `DEFENSE_EXEMPT` | The keyword is now brand defense. Defense is never judged on profit, so it is never seated. The seat is free. |
| `TO_GOOD_SIDE` | The keyword is now winning or at its bar: it moved to the 80% side. The seat is free. (`WINNER`, `PACED_WINNER`, `AT_BAR` — named explicitly, never a catch-all.) |
| `TO_WAITING` | The keyword is still a trial but is no longer bought at an entry or park bid and is not a stalled probe: it is back to waiting for clicks on the 80% side, no verdict yet. The seat is free. |
| `STATE_CHANGED` | The keyword left the seat set — it now reads *\<the state in plain words\>*. The seat is free. (Any state the rows above do not name — e.g. "launch, contained by the launch controller" — so nothing closes silently. Synthetic record 2026-08-22 on `TMP_` copies: a repair seat flipped to `LAUNCH_CONTAINED` closed with exactly that sentence; a repair seat flipped to `REVIVED_SETTLING` stayed open, number kept, kind re-observed as settling.) |

Occupant kinds, for the same reason: repair = "losing, being re-priced toward its bar";
probation = "losing, held at its floor to be seen serving"; failed = "lost at its floor";
probe = "a trial being bought at an entry or park bid"; stalled probe = "a trial parked at an
entry bid past the probe window without enough clicks for a verdict — re-price to the seat price
or park"; settling = "a verdict is pending until its clicks settle"; parked — awaiting re-verdict =
"parked by the ladder with a re-verdict appointment still ahead, and still buying clicks — being
re-tested, not leaking".

A closed number is free for the next admission. A keyword that returns later opens a NEW occupancy
and may receive a different number — stability is for the duration of a stay, not forever.

**Same-day flip.** A row closed on this snapshot date whose key is an occupant again is reopened
rather than re-inserted, so it keeps its number and the occupancy key stays unique.

**Idempotence.** Every write is keyed on the snapshot date and on set differences: a second run on
the same snapshot closes, reopens and admits nothing and re-stamps identical memory. Evidence is
two runs with an identical table fingerprint:

```sql
SELECT COUNT(*) n, FARM_FINGERPRINT(STRING_AGG(TO_JSON_STRING(t), '|' ORDER BY family, campaign_id, keyword_id, opened_on))
FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` t;
```

**Acceptance** — two files. `scripts/bigquery/tests/DE_FAMILY_SEAT_LEDGER_acceptance.sql` (A01–A16)
judges the ledger against ONE snapshot; `scripts/bigquery/tests/DE_FAMILY_SEAT_LEDGER_drift.sql`
(D00–D08) judges what a NEW snapshot did to it — see "Drift check" below, and run it whenever the
question is whether a pass kept the numbers. **It needs a copy of the ledger taken BEFORE the pass**
(`TMP_FSR_LEDGER_BEFORE`); the ledger has no archive, so after the pass that image is gone. D00
reports `VACUOUS` rather than PASS if the before and after copies turn out to be the same image. A01–A16, every check passes:
one open row per ladder occupant; no open row without an occupant; one keyword per open
number in a family; numbers ≥ 1; no launch-family row; closed rows carry a mapped reason;
open probe / stalled-probe seats hold TRIAL keywords; the occupancy key is unique; no keyword
holds two open rows; no brand-defense keyword holds an open seat; R-a both ways (every open TRIAL
seat is engine-listed, or at the floor WITH spend, or stalled — and every engine-listed TRIAL,
spend or not, and every at-floor TRIAL with spend, holds one open row); R-b (every stalled probe
holds one open row observed as 'stalled probe'); every open row remembers its last observed kind
and state and the state matches the ladder today; every closed row carries the sentence mapped to
its code (for `STATE_CHANGED`, the mapped prefix, the state in plain words, and "The seat is
free."); R-h both ways (every parked keyword with spend and an appointment ahead holds one open
row observed as 'parked — awaiting re-verdict', and no other PARKED keyword holds one). TDD
record 2026-08-22 (R-h): the new check FAILED on the live ledger (the parked spenders with an
appointment ahead held no seat); after the procedure was deployed and run they were admitted,
every check PASSED, and two consecutive runs gave an identical fingerprint. TDD record 2026-08-22: with the memory columns added but the old procedure live, A13
(stalled probes unseated) and A14 (no memory) FAILED; after the new procedure, every check PASSED.
Repair pass, same day: A13 rewritten to the at-or-above gate FAILED on the live procedure
(violations = the keywords logged as a small nudge but parked at the activation floor); after the
gate was deployed and the procedure run, they were admitted, every check PASSED, and two
consecutive runs gave an identical fingerprint. Task 2 polish, same day: the snapshot-dated window,
the raise-bounded click count and the brand-word test changed no live occupant (every check passed
before and after; two runs, identical fingerprint); `STATE_CHANGED` was proven on `TMP_` copies
(above) because no live seat had left for an unnamed state.

**Synthetic tests** are run by hand on `TMP_` copies, never on the live snapshot or ledger (house
rule: no synthetic rows in a production table consumers read). Ship record: a `TMP_` copy of the
procedure pointed at `TMP_` copies of the snapshot and the ledger; three seated keywords deleted
from the snapshot copy — one with memory `LOSER` closed `KILLED`, one with memory `REPRICE` closed
`PAUSED`, one with no memory and opened as failed closed `KILLED` — each with its sentence; the
`TMP_` objects dropped afterwards. Earlier records (first ship): two synthetic REPRICE rows took
the two lowest free numbers; the first removed closed `PAUSED`; a third took the freed number;
a synthetic brand-defense REPRICE row closed `DEFENSE_EXEMPT`; a probe seat at neither bid closed
`TO_WAITING`; a keyword added to the probe list with no spend was seated and, once removed,
closed `TO_WAITING`.

**Seat census** — how many seats each family holds, by kind, and what they cost per day on the
basis window — is a measurement; read it from the ledger, never from this file:

```sql
WITH wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
sp AS (SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid, SUM(Ads_cost) sp7
       FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN wm
       WHERE f.date BETWEEN DATE_SUB(wm.d, INTERVAL 7 DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY) GROUP BY 1, 2)
SELECT l.family, l.last_observed_kind, COUNT(*) seats, ROUND(SUM(COALESCE(sp.sp7, 0)) / 7, 2) cost_per_day
FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
LEFT JOIN sp ON sp.cid = l.campaign_id AND sp.kid = l.keyword_id
WHERE l.closed_on IS NULL GROUP BY 1, 2 ORDER BY 1, 2;
```

## Rulings closed on 2026-08-22 (kept for the record)

Both open rulings below were closed by R-c and R-d in the rulings table above. The measurement
query under item 1 still answers "which stalled seats are entries and which are nudges" — read
the register's `raise_old_bid` / `raise_new_bid` instead, it carries the same facts.

1. **Engine parity vs activation-sized entries.** (closed by R-c — parity stands; the sentence is
   size-aware and the raise is published on the row.) The stalled-probe position is the engine's own
   probing test expired — ANY applied `INCREASE_BID`, whatever its size. So a coach nudge of a few
   cents that bought no clicks in two weeks is seated as a stalled probe beside a $1.00 activation
   entry. The spec's words are "activation entry bid"; no published entry-bid column exists
   (`V_KEYWORD_LIFT.probe_bid` is internal and excluded from its schema), so narrowing the set would
   need either a published column or a declared threshold. Until Ori rules, engine parity stands —
   it is the only definition that reads from published data. Measure the split with:
   ```sql
   SELECT l.family, l.seat_no, s.target_text, s.current_bid, c.old_bid, c.new_bid, c.source,
          DATE(c.applied_at, 'America/Los_Angeles') AS raised_on
   FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
   JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` s USING (campaign_id, keyword_id)
   JOIN `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` c USING (campaign_id, keyword_id)
   WHERE l.closed_on IS NULL AND l.last_observed_kind = 'stalled probe'
   QUALIFY ROW_NUMBER() OVER (PARTITION BY l.family, l.seat_no ORDER BY c.applied_at DESC, c.change_id DESC) = 1
   ORDER BY 1, 2;
   ```
2. **A raise with no applied log row.** (closed by R-d — "waiting — no test clock", its own
   category with its own move; never seated, never aged from `state_since`.)

## The register (Task 2 — `V_FAMILY_SEAT_REGISTER`)

One view, one wide shape, every row carrying a `sentence` a new reader can act on and a
`sort_key` that orders the whole register totally (determinism). Read it sorted:

```sql
SELECT row_type, family, horizon, seat_no, category, side, cost_per_day, move, sentence
FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER` ORDER BY sort_key;
```

**Row types.** `FAMILY` (one per working family per horizon — the doctrine read), `CATEGORY`
(one per family × category × horizon; they sum to the family's spend on that horizon to the
cent), `SEAT` (one per occupant, numbered by the ledger), `OPEN_SEAT` (one per working family:
the lowest free number, the open capacity and the next probe the capacity can afford from the
budget engine's queue), `LEAK` (closed but still spending), `GAP` (a keyword that SPENT on the
basis window with no verdict row — an off-ladder keyword at $0 on the basis window is not in the
universe and gets no row), `NO_CLOCK` (a trial whose bid moved outside the change log — its own
sentence and move, R-d), `ABSORB` (advisory: an above-bar campaign capped on at least
`k.absorb_capped_days` of the last 7 that could take freed spend — shown, never moved),
`REFERENCE` (the launch families, same categories, never judged), `UNMAPPED` (spend in the
cracks, spec §2: one row per campaign that spent on the basis window and that no family claims —
no `T_FAMILY_BAR` row and no ladder row with a family — plus one total row; the family column
reads `Unmapped`, the side `UNMAPPED`, the move is Admin's: map the campaign. The register never
guesses a family from a campaign name; the dollars are published so no family read is silently
short, and the total row says so).

**Brand defense, on and off the ladder.** The three-way test (ladder flag, 'BRAND DEFENSE' in
the campaign name, a house brand phrase from `DIM_BRAND_PHRASES` in the keyword text) is applied
to the ads rows too — campaign name and targeting text — so an untracked keyword in a defense
campaign is `brand defense — never judged on profit`, never a GAP on the 20% side. Defense is
tested BEFORE the gap test, and the same three-way test gates the probe queue (D6): a QUEUED
keyword in a defense campaign or carrying a brand phrase is never proposed as an OPEN_SEAT
candidate, whatever the engine's own flag says.

**The brand-phrase hazard (D9).** `DIM_BRAND_PHRASES` carries short BRAND phrases such as
`lolli`; matched as a bare substring (`LIKE '%lolli%'`) that phrase claims `lolli pop` and
`lolli and pops` — competitor and generic terms — as house defense, hiding them from every
profit judgment. Every brand test in the register, the ledger procedure and both acceptance
files therefore matches a phrase as a WHOLE phrase on word boundaries (`REGEXP_CONTAINS` with
`\b…\b`, leading/trailing separators trimmed, regex metacharacters escaped). Only
`phrase_type = 'BRAND'` phrases are used; the PRODUCT-type phrases (`lollibox`, `lollime` …) are
house product names that the ladder flag and the campaign-name rule already cover on every live
row today — whether they should ALSO be matched as phrases is listed under "Open rulings".

**Categories and sides** (category ← ladder state; the codes live only inside the view, a person
reads the category words):

| category | ladder state / position | side |
|---|---|---|
| winning | `WINNER`, `PACED_WINNER` | 80 |
| marginal — at its bar | `AT_BAR` | 80 |
| waiting — too few clicks yet | `TRIAL` in no probe position WITH clicks on the basis window | 80 |
| waiting — no test clock | `TRIAL`, bid moved outside the change log (R-d) | 80 |
| waiting — not yet serving | `TRIAL` in no probe position, $0 and 0 clicks (R-j) | none, $0 |
| waiting — verdict settling | `REVIVED_SETTLING`, `PENDING_SETTLE` — seated, counted on the 80% side by ruling | 80 |
| losing — in repair | `REPRICE` | 20 · seat |
| losing — on probation at its floor | `FLOOR_PROBATION` | 20 · seat |
| losing — failed at its floor | `LOSER` | 20 · seat |
| probe — being bought at an entry bid | `TRIAL` engine-listed, or at the floor with spend (R-a) | 20 · seat |
| probe — stalled | `TRIAL`, standing applied raise past the engine's test (R-b, R-c); proposal by the sign of seat price − live bid (R-f) | 20 · seat |
| parked — awaiting re-verdict | `PARKED` with spend and a re-verdict appointment on or after the snapshot date (R-h) | 20 · seat |
| closed but still spending | `PARKED` past its appointment with spend, `DEAD` with spend | 20 · leak |
| untracked — no verdict row | spend on the basis window, no ladder row; worded by the measured cause — no keyword id / paused trailing / enabled next-run / check why (R-k refined) | 20 · gap |
| idle at the floor | `TRIAL` at the floor, $0, 0 clicks (R-e) | none, $0 |
| closed — not spending | `PARKED` / `DEAD`, $0 | none, $0 |
| brand defense — never judged on profit | the three-way defense test | outside the ratio |
| launch — contained | `LAUNCH_CONTAINED` (reference families) | outside the doctrine |
| other — not earning, not being tested | any state not named above | 20 (a family cannot pass by hiding spend) |

**The ratio.** `judged_per_day` = good side + bad side; `good_share` = good ÷ judged;
`allowance_per_day` = `k.allowance_share` (0.20) × judged; `open_capacity` = allowance − bad side;
`over_by` = the excess when OUT. Brand-defense spend is published beside the ratio
(`defense_per_day`) and is in neither side, so the allowance is 20% of the JUDGED spend — a
choice recorded here for Ori (the alternative, 20% of all spend including defense, would let
defense dollars buy seats). `doctrine_status`: IN at 80% or above; AT_LINE within `at_line_band`
under the line; OUT below that. **`at_line_band` is derived, never declared, per family (R-g)**:
the relative noise of a 7-day spend read for the JUDGED family itself — stddev ÷ mean of its own
daily spend over the context window, ÷ √(basis days) — published with its derivation in words on
every FAMILY row:

```sql
SELECT family, at_line_band, at_line_band_derivation
FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER` WHERE row_type = 'FAMILY' AND horizon = 'today' ORDER BY family;
```

**The two clocks of a stalled probe (D8).** The 14-day test ages the raise against the SNAPSHOT
date (the ledger's clock, so the seat set is a pure function of the snapshot); the clicks since
the raise are counted on COMPLETE ads days (through the basis window's last day). The row publishes
`days_since_raise` on the snapshot clock and the sentence states both: "N clicks on the M complete
ads days since (through <date>); the raise is D days old on the snapshot date (<date>)". Dates in
sentences are two-digit (`%b %d`), never space-padded (D7).

**Projections count by their own side (D5).** On the day-one and re-judged rows the "N seats",
"N leaks", "N untracked" are the HORIZON's own counts (a repair that moved to the good side at
re-judged is not a seat there) and the verb is conditional ("the N seats would cost"); B21
re-derives the counts from that horizon's CATEGORY rows.

**Horizons** (FAMILY and CATEGORY rows, column `horizon`, each with `as_of`, the basis dates and
`horizon_assumption` on the row): `today` is measured; `day one` assumes the PENDING_UPLOAD book
lands — every keyword on it spends in proportion to new bid ÷ old bid (a linear guess, labelled
as such) — and nothing else; `re-judged` assumes the repairs hold at their bar and move to the
good side at their day-one cost, probation keywords stay at their floor, failed keywords are
killed with a pause row, engine probes and settling verdicts hold, untracked spend is unchanged.
Projections are labelled projections in the sentence.

**A projection may never spend back dollars no sheet recovers (R-l, both halves — read this
paragraph with R-l, not instead of it).** Three consequences, all of them in the published
`horizon_assumption` and asserted:

- **Leaks are NOT paused on either projection** (leak half, B35). The sheet that would pause a
  closed-but-spending keyword is the **leak arm** of `tools/build_reprice_bulksheet.py`, recorded
  in the object table above as **Task 3, not shipped** — the shipped generator selects
  `AT_BAR / REPRICE / FLOOR_PROBATION / LOSER` only. So a leak costs on day one and on re-judged
  exactly what it costs today, and both assumptions name the unbuilt arm the dollars wait on. The
  **failed** half is different and stays at $0 on re-judged: its pause row (`KEYWORD_PAUSE`,
  `State: PAUSED`) is one the shipped generator builds today. Same rule, opposite answer, because
  one sheet exists and the other does not.
- **A stalled probe is re-priced, never parked to $0** (B33). The move on its own row is R-f's
  sign branch — raise to the seat price where the live bid is below it, otherwise park at the
  engine's `bid_park` — and it keeps spending at that price on the same linear bid→spend guess,
  because parking lowers a price and does not stop the spend. It stays on the 20% side until a
  verdict arrives.
- **A holdout campaign gets no sheet row on either projection** (holdout half, B34). From its
  `eligible_from`, every row it holds costs on both projections what it costs today, a repair in
  one never moves to the good side and keeps `losing — in repair`, and the family clause lists no
  move for it.

**Seat economics.** A seat costs what its occupant spends per day on the basis window. A probe's
admission cost is the engine's own: the campaign's `seat_cpc` × `k.click_goal_day` (4 — the seat
model's one 4-click trial a day), read from `T_OOB_SEAT_ECONOMICS`; the OPEN_SEAT row proposes
the first QUEUED keyword (by the engine's `seat_rank`) the open capacity can afford. The engine's
park price (`bid_park`) is read from the same table (R-f) — `V_OOB_KEYWORD` publishes it since
2026-08-22; the T_ is rebuilt by `SP_REFRESH_CUBE_TABLES` step 0b. The register proposes; the
engine activates; nobody here bids.

**Holdout.** Every row that names a campaign — SEAT / LEAK / GAP / NO_CLOCK / ABSORB / UNMAPPED
and the OPEN_SEAT candidate — in a holdout campaign (`DE_HOLDOUT_ASSIGNMENT`, arm HOLDOUT)
carries `holdout`, `holdout_eligible_from` and a note; before `eligible_from` the sentence says
when the campaign joins the arm. From `eligible_from`: every SEAT move (repair, probation,
failed, stalled, probe, settling alike) reads "no sheet row — holdout campaign", the LEAK / GAP /
NO_CLOCK moves read "no sheet row", the ABSORB advisory reads "advisory suppressed" (no freed
spend is sent there), and the probe queue skips the campaign so no OPEN_SEAT candidate can sit in
one. Proven on a `TMP_` copy of the view with `eligible_from` shifted 60 days back (every holdout
row suppressed, no candidate in a holdout campaign); the copy dropped afterwards.

**Planner.** Reads tables and light views only: `FACT_KEYWORD_STATE`, `T_FAMILY_BAR`,
`FACT_AMAZON_ADS`, `DE_FAMILY_SEAT_LEDGER`, `T_LIFT_PROBES`, `T_OOB_SEAT_ECONOMICS`,
`V_CAMPAIGN_CAP_STATE` (measured in seconds and tens of MB), `V_PPC_CHANGE_LOG_APPLIED`,
`FACT_PPC_CHANGE_LOG` (PENDING_UPLOAD only), `DIM_KEYWORD`, `DIM_BRAND_PHRASES`,
`DE_HOLDOUT_ASSIGNMENT`, `V_BOOK_ASSIGNMENT`. `V_OOB_KEYWORD` is a planner-ceiling view measured
in minutes and is never inlined — its seat economics come through `T_OOB_SEAT_ECONOMICS`. The read
cost and the wall time are measurements; take them from a dry run and a timed uncached pull, never
from this file (a wall figure quoted in a report is the report's measurement on that day, not a
property of the view — the view runs in tens of seconds, not single digits):

```
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --dry_run \
  "SELECT * FROM \`onyga-482313.OI.V_FAMILY_SEAT_REGISTER\`"
time bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "SELECT COUNT(*) FROM \`onyga-482313.OI.V_FAMILY_SEAT_REGISTER\`"
```

**Acceptance** (`scripts/bigquery/tests/V_FAMILY_SEAT_REGISTER_acceptance.sql`, a script that
reads the view once into a temp table; every check passes): category rows sum to the family spend
on every horizon to the cent; SEAT (20% side) + LEAK + GAP equal the bad side; every keyword of a
working family is counted exactly once against an independent re-derivation; every seat is
numbered by its open ledger row and every open ledger row has a seat; no launch family in a
FAMILY row; no brand-defense keyword holds a move (three-way test); `sort_key` is unique; every
row has a sentence and every actionable row a move; holdout marked exactly where it belongs;
stalled-probe rows publish the raise and a size-aware sentence; three horizons per family; the
R-d / R-e categories match a re-derivation; one OPEN_SEAT row per family at the lowest free
number; ABSORB rows are capped, non-defense campaigns; the FAMILY figures reconcile; the UNMAPPED
rows equal an independent re-derivation of the spend in the cracks (campaign set and cost to the
cent, total row = sum and count); no GAP row at $0; overdue settling named overdue (R-i);
every gap worded by its measured cause with the retired blanket phrase appearing nowhere (R-k
refined); the REFERENCE wording names waiting; projection
counts are the horizon's own (D5); no OPEN_SEAT candidate is defense three ways (D6); dates are
two-digit (D7); one raise clock (D8); the at-the-line band is the family's own (R-g); parked seats
and leaks match their re-derivation (R-h); not-yet-serving matches its re-derivation (R-j); the
defense category matches the whole-phrase re-derivation (D9); and the gap-closure arithmetic of
R-l — the recovered-today figure is the register's OWN pause rows and nothing else, within a stated
tolerance whose reason is on the check (B29); the stalled-probe and repair lines are named for what
they are and are excluded from that figure (B30); and the closing sentence reads recovery, gap,
verdict, what the rest depends on, pointer to the re-judged row (B31) — so a reader who does
everything on the row is never promised a closure the pauses cannot deliver.
The checks read their constants from the test's `k` CTE, which mirrors the view's. TDD record
2026-08-22: run before the view existed, the script failed (object not found); after deploy one
check (B12) FAILED on a NULL-swallowing re-derivation in the TEST (a stalled test with no log row
is NULL, and `NOT NULL` hid the keyword) — the view was right, the test was fixed, then every check
PASSED. Repair pass, same day: the universe re-derivation tightened to spend on the BASIS window,
the defense test moved onto the row itself, the holdout check widened to every row naming a
campaign and to the move text, and checks added for unmapped spend and phantom gaps; against the
first view those new and tightened checks FAILED (the phantom $0 gaps, the 'happy lolli' defense
target published as a gap, the two holdout campaigns on ABSORB rows, the unmapped campaigns, the
$0 GAP rows); after the repaired view, every check PASSED, and two uncached pulls gave an
identical MD5. Repair pass 2026-08-22 (D1–D14): the tightened and new checks were run against the
live view FIRST and FAILED where the defects lived — the sign-blind stalled proposals (B10), the
overdue settling rows published as future (B18), the product-target gaps promised a verdict (B19),
the REFERENCE wording (B20), the projection counts (B21), the space-padded dates (B23), the two
clocks (B24), the shared band (B25), the missing parked seats (B26), the $0 trials read as
waiting (B27); the queue-defense and whole-phrase checks (B22, B28) passed on live data because
no live row exercised them and were proven on `TMP_` copies with injected rows (below); after the
repaired view every check PASSED and two uncached pulls gave an identical MD5.
Second repair pass 2026-08-22 (R-k refined + gap-closure honesty): B19 was rewritten to assert
the measured-cause wording and the absence of the retired blanket phrase, and B29 added; both
were run against the live view FIRST and FAILED exactly where verification had placed the
defects — every gap row and the family gap sentences carried the blanket phrase, the paused
SP product target was worded as ladder-blind, and one OUT family promised a closure its listed
moves could not deliver; after the repaired view every check PASSED and two uncached pulls gave
an identical MD5. (A test-side lesson recorded in the test file: filtering on the universe's
EXISTS-derived defense flag in a WHERE trips BigQuery's non-equality ANTISEMI-join limitation —
the house anti-join rule — so the gap-cause re-derivation keeps its filters inside COUNTIF.)

**Third repair pass 2026-08-22 — the closing promise counts only money you recover today
(B29 rewritten, B30 added).** The gap-closure sentence added four numbers together and called the
total a recovery: the leaks, the stalled probes, the failed keywords **and the repairs**. A repair
is not a recovery. Nothing comes back when you re-price a losing keyword; the dollars move to the
good side only if that keyword then holds at its bar when it is re-judged, which is a projection.
So a family could read "enough to close the gap" off moves that recover a fraction of it, and the
register contradicted itself one row away — query the FAMILY rows across the three horizons and
compare the today row's promise against the day-one row's `over_by_per_day` to see it. Two changes.
The repair clause no longer borrows the `(−$…/day)` form the executable moves use; it says the
repairs give back nothing today and names the projection as a projection. The closing sentence
counted only leaks + stalled probes + failed keywords.

**Fourth repair pass 2026-08-22 — R-l: only a PAUSE is a recovery (B29 rewritten again, B30
rewritten, B31 added).** The third pass had removed the repairs but left the stalled probes in the
recovered total, and that was still wrong for the same reason one step down: **the move on a stalled
probe is "re-price it, or park it", and parking LOWERS a price — the keyword keeps serving and keeps
spending.** Money only provably leaves the 20% side when a keyword is PAUSED: a leak paused, or a
failed keyword killed with a pause row. A holdout campaign gets no sheet row at all from its
`eligible_from`, so its rows recover nothing either, and the register now says which of its closed
or failed keywords are in that position instead of silently counting them.

Read the ruling in the table (R-l). What it changed in the view: the recovered-today figure is
`leak_exec_today + failed_exec_today` and nothing else; the stalled probes get their own line naming
their dollars as **spend at risk of continuing, not recovered today**; the repairs get theirs naming
themselves **a change of price, not a recovery**, whose result arrives at the re-judged horizon; and
the closing sentence reads in one fixed order — the executable recovery, the gap, a plain *closes /
does not close* verdict, what the remaining dollars depend on, and a pointer to that family's
re-judged row. A reader who does everything the row lists today is never promised a closure the
pauses cannot deliver, and every dollar the row mentions is either recovered, at risk of continuing,
or explicitly a projection.

**Why the test could not catch it, and what replaced it.** The first B29 re-derived the recovery by
regex-extracting every `(−$…/day)` parenthetical out of the sentence the VIEW had just written —
test and view shared the assumption, so folding a projection into the total passed both. Since the
third pass B29 re-derives INDEPENDENTLY from the register's own keyword rows and never from the
sentence; since R-l that re-derivation is the **pause rows only** — the today-horizon LEAK rows plus
the SEAT rows whose occupant is `failed`, minus any row whose campaign is holdout-suppressed. B29
requires the sentence's stated recovery, its listed `(−$…/day)` moves and that re-derivation to
agree within **$0.02** — the tolerance a two-decimal rendering of one aggregate carries against a
sum of per-row costs each rounded on its own row (R-m) — requires the gap it names to be the row's
own `over_by_per_day`, and judges the closes / does-not-close verdict on the re-derived number.
B30 is the structural half: neither the stalled-probe clause nor the repair clause may wear the
executable `(−$…/day)` form, each must name what it actually is, and neither family's dollars may
sit inside the recovered figure. B31 asserts the sentence's fixed order. B30 deliberately does NOT
forbid a family that has repairs or stalled probes from also claiming a closure — a family whose
pauses alone reach its gap may legitimately do both, and that is B29's call on the re-derived
number.

**TDD record (R-l, 2026-08-22).** The rewritten B29, the rewritten B30 and the new B31 were run
against the LIVE deployed view first and each read **3 violations** — one for every family whose 20%
side is over its allowance — while B01–B28 all passed; the deployed sentences were counting the
stalled probes' dollars as recovered. After the repaired view was deployed, all **31** checks read
PASS, A01–A16 stayed 16/16, and two uncached pulls gave an identical MD5. Earlier record (third
pass): the then-new B29 and B30 were run against the PRE-FIX definition stood up under a `TMP_` name
(never against production, dropped afterwards) and read 2 violations each while B01–B28 passed.

**The holdout branch of R-l, proven on a `TMP_` copy (2026-08-22).** No live row exercises it: the
holdout arm's `eligible_from` is still ahead of the snapshot, so nothing is suppressed today and the
clause would read as untested. A `TMP_` copy of the view was pointed at a one-row `TMP_` holdout
table naming a working family's leak campaign with an `eligible_from` in the past (never
`DE_HOLDOUT_ASSIGNMENT`; both copies dropped afterwards). The family's sentence then paused only the
leaks outside that campaign, named the suppressed ones as sitting in holdout campaigns with no sheet
row and recovering nothing, and its recovered-today figure fell by exactly their cost — the
suppressed dollars never entered the total. Re-run it that way whenever the holdout rule changes.

Determinism: two uncached pulls, identical MD5 (query at the bottom of the test file).

**Fifth repair pass 2026-08-23 — R-l carried into the two projections and into the promise (B32,
B33, B34 added; B10, B11, B30 given the same holdout guard).** R-l had been applied to the today
sentence and to nothing else, so the register contradicted itself about the same dollars in the
exact row the today sentence sends the reader to. Three things:

1. **The re-judged horizon no longer zeroes a stalled probe.** It modelled parking as taking the
   spend to $0 and published that belief in its own `horizon_assumption` — the belief R-l retired.
   A stalled probe is now re-priced by the move on its OWN row (R-f) and keeps spending at that
   price on the same linear bid→spend guess the day-one horizon already uses, staying on the 20%
   side until a verdict arrives. B33 asserts a family that pays for stalled probes today still pays
   for them when re-judged, and that no assumption claims otherwise.
2. **Both projections respect the holdout arm.** The holdout half of R-l had been applied to the
   today figure only; `cost_day1` and `cost_rejudged` had no guard at all, so from the arm's
   `eligible_from` they would have booked improvements from a sheet that never lands — including the
   pending-book rows that already sit in holdout campaigns. A holdout-suppressed row now costs on
   both projections exactly what it costs today, a repair in one never moves to the good side and
   keeps its "losing — in repair" category, and the family clause lists no move for it. B34 asserts
   it; B10, B11 and B30's re-derivation carry the same guard.
3. **The FAMILY row names the book its pauses ride on.** It said "the pauses you can upload today",
   but today every dollar of that figure comes from LEAK rows and the leak arm that would emit their
   pause rows is Task 3, not yet shipped — while the LEAK row's own move had always said "pause it
   on the next book (leak arm)". The FAMILY row now says the same thing. The arithmetic did not
   change; the promise did. B32 asserts it, and open ruling 12 records what is still Ori's.

**TDD record (fifth pass, 2026-08-23).** Against the LIVE deployed view the rewritten B31 read 3
violations, the new B32 3, the new B33 14 and the new B34 8, while B01–B30 all passed. After the
repaired view was deployed all **34** checks read PASS, `DE_FAMILY_SEAT_LEDGER` A01–A16 stayed
16/16, and two uncached pulls gave an identical MD5.

**Sixth repair pass (2026-08-23) — the leak half, and the prose the SQL suite cannot see.** The
fifth pass carried R-l into the stalled-probe and holdout halves of both projections and left the
LEAK half exactly as it was: `cost_day1` and `cost_rejudged` still took every leak to $0, and the
published day-one assumption attributed that pause to the PENDING_UPLOAD book — the book that
carries bid changes only. So the register said two things about the same dollars in adjacent rows:
the today row sent the reader to "the next book (leak arm)", the day-one row priced those keywords
as already paused. It changed a published verdict, not just wording: one family's day-one row read
IN on the strength of dollars nothing recovers and now reads AT THE LINE (read the rows, don't take
a number from this file). Neither projection zeroes a leak now; the FAILED half is untouched,
because the shipped generator builds that pause row today. B35 asserts all six halves of it.
Two committed files also still carried the RETIRED model in the one place that summarises it — the
view's own header block and the SOP's Horizons paragraph — while every check passed, because the
deploy strips `--` lines and the suite reads only the deployed definition. Both were rewritten with
the code, the Horizons paragraph now carries all three "a projection may never spend back dollars no
sheet recovers" consequences, and the acceptance file records the grep that is the only instrument
for those two files.

**TDD record (sixth pass, 2026-08-23).** Against the LIVE deployed view the new B35 read **65**
violations while B01–B34 all passed; after the repaired view was deployed all **35** read PASS,
`DE_FAMILY_SEAT_LEDGER` A01–A16 stayed 16/16, two uncached pulls gave 331 rows and an identical
MD5, and the dry-run read stayed at the same order (~163 MB) with no ceiling view inlined.

**The holdout branch, re-proven on `TMP_` copies (2026-08-23) — and what the proof caught.** Still
no live row exercises it (the arm's `eligible_from` is ahead of the snapshot), so a `TMP_` holdout
table was built naming the three Lollibox campaigns that hold that family's repairs and stalled
probes with an `eligible_from` in the past, and a `TMP_` copy of the view was pointed at it (never
`DE_HOLDOUT_ASSIGNMENT`; all three `TMP_` objects dropped afterwards). Twelve rows became suppressed.
The repair category's cost was then IDENTICAL on the today and the re-judged horizons, the category
survived the horizon instead of becoming "marginal — at its bar", the stalled-probe cost was
identical on both, and the family's re-judged row flipped from IN to OUT — the honest reading, since
no sheet may touch those keywords while the arm runs. Running the acceptance file against that world
(with its holdout source pointed at the same `TMP_` table) read **34/34 PASS**; run against it with
the test still reading the real `DE_HOLDOUT_ASSIGNMENT` it read 24 B09 violations, which is the
substitution artifact, not a defect. The proof also caught two LATENT TEST defects that pass
vacuously on today's snapshot: B11 forbade a "losing — in repair" category on the re-judged horizon
outright, and B30's re-derivation priced stalled probes and repairs a sheet can never reach. Both
now carry the holdout guard, as does B10, whose R-f proposal check must exempt a row whose move is
correctly the holdout move.

**`TMP_` proofs of 2026-08-22** (house rule: synthetic rows only on `TMP_` copies, never in a
production table; the copies were dropped afterwards). A copy of the snapshot received one
synthetic Fresh TRIAL keyword whose text was `lollipop candy`; a copy of the seat-economics
table received one synthetic QUEUED keyword `happy lolli bath bombs` in a non-defense Fresh
campaign at the best queue rank, engine flag FALSE. Copies of the OLD and the NEW view were
pointed at those copies. Under the OLD view the `lollipop candy` trial read "brand defense —
never judged on profit" (the bare-substring `lolli` match, D9) and the brand-phrase probe was
proposed as Fresh's OPEN_SEAT candidate (the one-way engine flag, D6); under the NEW view the
trial read "waiting — not yet serving" (R-j) and the OPEN_SEAT row read "no queued candidate
fits the capacity". A first attempt used `lolli pop candy` and proved nothing, because
`lolli pop` is itself a listed BRAND phrase — whether the misspelt `lolli pop` / `lolli and
pops` entries belong in `DIM_BRAND_PHRASES` at all is Ori's call (listed under "Open rulings").

**The morning read** is a measurement — take it from the view, never from this file:

```sql
SELECT family, sentence FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER`
WHERE row_type = 'FAMILY' AND horizon = 'today' ORDER BY family;
```

**Spend in the cracks** is a measurement; read it from the register, never from this file:

```sql
SELECT campaign_name, cost_per_day, holdout, move
FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER` WHERE row_type = 'UNMAPPED' ORDER BY sort_key;
```

## Drift check — what a new snapshot must not break

**The gap this closes.** The A-suite judges the ledger against ONE snapshot. It cannot see whether a
seat number survived the night, because the number is a stored column and no live table remembers
what it was yesterday; and while the live ledger has never closed a row, its closure checks (A06,
A15) and the reuse of a freed number pass VACUOUSLY. `DE_FAMILY_SEAT_LEDGER_drift.sql` (D00–D08) is
the missing half: it compares an AFTER ledger against a BEFORE one and asserts the three things a
pass must not break — a continuing occupant keeps its number (D01), every closed row carries the
mapped code, the snapshot date and the SOP's own sentence (D02–D05), and admissions take the lowest
free numbers without ever landing on a number a still-seated keyword holds (D06–D08).

**What the check found first (2026-08-22).** There was no pass to check. Both new steps —
orchestrator Task 20.8b and `SP_REFRESH_CUBE_TABLES` step 0b — were deployed AFTER the last full
pass had already started, so neither had ever executed inside one: `SP_MAINTAIN_FAMILY_SEATS` has
no row in `LOG_PIPELINE_RUNS` at all, and every logged `SP_REFRESH_CUBE_TABLES` run predates the
step-0b deploy. The ledger and `T_OOB_SEAT_ECONOMICS` were current only because the build session
ran them by hand. Nothing is broken — the wiring is deployed and correct in both routine bodies —
but **the first automated proof of the ledger is the first pass after 2026-08-22**, and the check
that matters is the one above, run against it. Confirm the wiring any time with:

```sql
SELECT routine_name,
       REGEXP_CONTAINS(routine_definition, r'CALL `onyga-482313.OI.SP_MAINTAIN_FAMILY_SEATS`\(\)') AS calls_seats,
       REGEXP_CONTAINS(routine_definition, r'CREATE OR REPLACE TABLE `onyga-482313.OI.T_OOB_SEAT_ECONOMICS`') AS builds_seat_economics
FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN ('SP_ORCHESTRATE_DAILY_REFRESH', 'SP_REFRESH_CUBE_TABLES');
```

Also measured that day: re-running `SP_MAINTAIN_FAMILY_SEATS` on the unchanged live snapshot closed,
reopened and admitted nothing and left the table fingerprint identical — idempotence holds on the
live ledger, not only on a copy.

**How to run it — and the one step there is no second chance at.** The ledger has no archive, so
nothing remembers what a seat number was yesterday except a copy someone takes. The check reads
three copies and never a live table: `TMP_FSR_LEDGER_BEFORE`, `TMP_FSR_LEDGER_AFTER` and
`TMP_FSR_STATE`. **To check a real pass, copy the ledger BEFORE the pass runs** — after it, the
BEFORE image is gone for good:

```sql
-- run this BEFORE the pass (the orchestrator starts about 01:00 New York)
CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_FSR_LEDGER_BEFORE` AS
  SELECT * FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`;
-- and these two AFTER it finishes
CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_FSR_LEDGER_AFTER` AS
  SELECT * FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`;
CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_FSR_STATE` AS
  SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE`;
```

**The BEFORE image for the first automated pass has been taken.** `TMP_FSR_LEDGER_BEFORE` was
created at 2026-08-22 20:57 New York, hours ahead of the ~01:00 pass, holding 88 rows all open —
the same 88 the live ledger holds, which had not been written since 19:16 New York that day.
Whoever reads the register after the pass finishes runs only the two AFTER copies above and then
the drift file; check the BEFORE copy is still the pre-pass image before trusting the result
(D00 reports `VACUOUS` if it is not). Re-take it by hand before every later pass until the ledger
archive of Open ruling 10 exists.

Then run the file, and drop the three copies. To check without waiting for a pass, replay it: copy
the ledger twice (BEFORE and AFTER), copy the snapshot with `snapshot_date` advanced one day plus
whatever departures and arrivals the case needs, `sed` the procedure's two table names onto
`TMP_FSR_STATE` and `TMP_FSR_LEDGER_AFTER`, CALL it, run the file, drop the copies (house rule:
synthetic rows only on `TMP_` copies).

**Why the check reads copies and not the live ledger — and what D00 is for.** The first version of
this file took its BEFORE image from the live `DE_FAMILY_SEAT_LEDGER`. That is safe only until a
pass actually runs: afterwards the live table IS the after image, so BEFORE and AFTER are the same
image, D01 compares the table to itself, and every check reports PASS having tested nothing — a
failure in the safe direction, which is the worst kind, because it looks like proof. **D00 now names
that case**: if the two copies are byte-identical it reads `VACUOUS`, not `PASS`. Two innocent
causes — the pass genuinely changed nothing (confirm in `LOG_PIPELINE_RUNS`), or the BEFORE copy was
taken after the pass instead of before it, in which case the run proves nothing and must be repeated
at the next pass. **A permanent, pass-by-pass version of D01 still wants a ledger archive** — a
number rewritten in place cannot be detected without one, and the copy above has to be taken by hand
every night. That archive is a Task 5 (health checks) item and is Open ruling 10 below.

**Record 2026-08-22 (TDD, on `TMP_` copies; the copies were dropped).** Two replays of tomorrow's
pass against the live snapshot advanced one day.
*Injected case* — a repair flipped to `WINNER`, a repair deleted from the snapshot, a stalled probe
flipped to `LAUNCH_CONTAINED`, a parked seat flipped to `DEAD`, and two non-seated winners flipped
to `REPRICE`: run BEFORE the replay, D04 and D05 FAILED; after it every check PASSED, the ledger's
first-ever closures carried `TO_GOOD_SIDE` / `PAUSED` / `STATE_CHANGED` / `KILLED` / `PARK_LAPSED`
each with its mapped sentence, the two admissions took the two numbers the closures had freed in the
procedure's own total order, and two consecutive replays gave an identical fingerprint.
*D00, the vacuity guard* (added 2026-08-22 after verification, TDD): pointed at the same ledger copied twice — the exact mistake a reader makes by copying the ledger AFTER the pass — D01 through D08 all reported PASS and D00 reported `VACUOUS`. Re-pointed at a genuine before-and-after pair, D00 reported PASS with the other eight. The nine PASSes on an untested run are why D00 exists.
*Plain case* (the date advance alone, no injection): D05 FAILED before the replay and PASSED after;
A01–A16 and B01–B29 both passed on the new snapshot, and this time A06 / A15 were NOT vacuous.
The plain case also produced the register's first real closures **without any injection at all**:
the parked seats whose re-verdict appointment falls on the current snapshot date lapse the moment
the date moves, and close `PARK_LAPSED`. Their `next_check_what` reads "revival proposed — in
today's plan", so whether they actually lapse in the live pass depends on whether the ladder
renews the appointment that night — the seat code does the right thing either way. Read who is
about to lapse with:

```sql
SELECT l.family, l.seat_no, s.next_check_date, s.next_check_what
FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` s USING (campaign_id, keyword_id)
WHERE l.closed_on IS NULL AND s.state = 'PARKED'
  AND s.next_check_date <= (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
ORDER BY l.family, l.seat_no;
```

**A canary, not a defect (B08 + B02).** Under the injected case, `LAUNCH_CONTAINED` on a
working-family keyword — a state the register's category table does not name — landed in
`other — not earning, not being tested` (20% side, by design, so a family cannot pass by hiding
spend), and that made B08 fail ("no `other` category in a working family") AND B02 fail
(`SEAT + LEAK + GAP` no longer equals the bad side, because `other` is on the bad side and is none
of the three). Both are the SAME alarm and it is working: **if the verdict ladder ever emits a state
the register does not name, B08 fires first and B02 fires with it, and the fix is to name the state
in the category table — never to widen the test.** Neither check fired on the plain case.

**What a pass costs.** The seat ledger step and the seat-economics step are separate costs; both are
measurements, so take them from the log and a timed uncached run, never from this file:

```sql
SELECT run_date, procedure_name, status, duration_seconds
FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
WHERE procedure_name IN ('SP_SNAPSHOT_KEYWORD_STATE', 'SP_MAINTAIN_FAMILY_SEATS', 'SP_REFRESH_CUBE_TABLES')
ORDER BY started_at DESC LIMIT 20;
```

```bash
# step 0b on its own — one evaluation of the view in the shape the step actually builds, into a
# TMP_ so the live table is untouched. Run it SEVERAL times: one reading is not the price (below).
time bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
  "CREATE OR REPLACE TABLE \`onyga-482313.OI.TMP_FSR_SEATECON\` AS
   SELECT campaign_id, campaign_name, keyword_id, ad_group_id, target_text, match_type, is_auto,
          is_pt, is_sb, is_defense, days_capped_7d, bid_floor, current_bid, slots, seat_rank,
          seat_cpc, role, bid_action, suggested_bid, clk90, ord90, roas90, bid_park,
          CURRENT_DATE('America/Los_Angeles') AS built_on
   FROM \`onyga-482313.OI.V_OOB_KEYWORD\`"
```

Wall time is a property of the warehouse that hour, not of the query. The figure that IS a property
of the query is slot time, and it is what tells a fast run from a slow one apart from a busy
afternoon. Read both together, for every reading:

```sql
SELECT FORMAT_TIMESTAMP('%m-%d %H:%M', creation_time, 'America/New_York') AS ny,
       ROUND(TIMESTAMP_DIFF(end_time, start_time, MILLISECOND)/1000, 1) AS server_s,
       ROUND(total_slot_ms/1000/60, 0) AS slot_min, total_bytes_processed AS bytes
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 HOUR)
  AND job_type = 'QUERY' AND state = 'DONE' AND error_result IS NULL
  AND STRPOS(IFNULL(query, ''), 'FROM `onyga-482313.OI.V_OOB_KEYWORD`') > 0
  AND STRPOS(IFNULL(query, ''), 'CREATE OR REPLACE TABLE') > 0
  AND total_bytes_processed > 1000000
ORDER BY creation_time;
```

**Measured 2026-08-22 — and the reason it needed eight readings, not one.** Step 0b does not have a
price; it has two. Eight uncached evaluations that day, server-side, in seconds and in slot-minutes:
148/1060, 155/1045, **414/9131**, 161/1094, 98/973, 93/642, **693/14927**, 106/784. Six of the eight
ran between a minute and a half and two minutes forty. Two ran seven and eleven and a half minutes —
and those two burned nine and fourteen times the slot-minutes of the others on the same 174 MB of
input, so they were not a busy warehouse making the same work take longer: they were the same query
doing an order of magnitude more work. (BigQuery warns "Number of stages in query is high" on this
view; the long runs are the plan spilling.) The column list makes no difference — the two readings
taken in the deployed 23-column shape, 148 s and 155 s, sit in the middle of the pack.

Against that, `SP_REFRESH_CUBE_TABLES` itself over the preceding fortnight: 48 OK runs, fastest
521 s, slowest 2,932 s, the middle two 753 s and 777 s. So on a normal night step 0b adds something
like an eighth to a fifth of that step; on a bad night it adds half again or more — and the step's
own 2,932 s maximum says the warehouse already has nights like that. `SP_MAINTAIN_FAMILY_SEATS`
takes well under a minute and is not part of this question.

**This prices Open ruling 4**, and the honest form of the price is a range with a tail, not a single
number: two earlier passes each published one reading — one of the slow ones ("just over seven
minutes"), one of the fast ones ("about two") — and each was true of its own run and wrong as a
price. Folding the build into `SP_SNAPSHOT_ENGINE_PROPOSALS`, which already evaluates
`V_OOB_KEYWORD`, recovers the whole of it, tail included; keeping it where it is buys the register a
table with the same freshness contract as `T_LIFT_PROBES`. Re-measure before ruling: run the timed
command at least three times and read the slot-minutes beside the seconds.

## Open rulings for Ori (register, 2026-08-22)

Each is a design choice the register was BUILT with; none is a defect. Ori may overrule; the
change is then a derivation or a source, never a literal.

1. **Allowance base.** The 20% allowance is computed on the JUDGED spend (80% side + 20% side);
   brand-defense dollars are published beside the ratio and buy no seats. The alternative — 20%
   of all family spend including defense — would let defense dollars buy seats.
2. **`at_line_band`.** CLOSED by R-g (2026-08-22): the band is the judged family's OWN noise,
   one per family, published with its derivation on every FAMILY row.
3. **R-d detection.** "The bid moved" reads `DIM_KEYWORD`'s distinct bid count; a raise the SCD2
   did not capture reads "waiting", not "waiting — no test clock". Under-detection only — never a
   false seat. Accept, or point the test at another bid-history source.
4. **Where `T_OOB_SEAT_ECONOMICS` is built.** `SP_REFRESH_CUBE_TABLES` step 0b (one extra
   evaluation of `V_OOB_KEYWORD` per pass, minutes) vs folding it into
   `SP_SNAPSHOT_ENGINE_PROPOSALS`, which already evaluates the view. Built as the former.
   **Now priced** (see "What a pass costs"): over eight uncached readings the extra evaluation
   ran between a minute and a half and two minutes forty on six of them, and seven to eleven and
   a half minutes on the other two — the slow pair burning nine to fourteen times the slot-minutes
   on the same input, so the tail is the query re-planning, not a busy warehouse. Against a
   cube-refresh step whose 48 OK runs that fortnight ran 521–2,932 s (middle two 753 s and 777 s),
   that is roughly an eighth to a fifth of the step on a normal night and half again or more on a
   bad one. Re-measure with the timed command AND the slot-minutes query in that section before
   ruling — one reading is not the price.
5. **Stalled probes outside the budget engine** (e.g. the COPYCAT campaigns) have no published
   seat price. CLOSED by R-f (2026-08-22): the row says "price it by hand or park it at the
   engine's park price" — the park price is the engine's published `bid_park`, so even a
   campaign outside the seat model gets a real park price, never a literal.
6. **Unmapped spend** is published as its own block and charged to no family. The alternative —
   charging it to the 20% side of the family a campaign NAME suggests — would be a guess the
   register refuses to make; mapping is Admin's job (Campaign Mapping).
7. **SB video product-target rows with no keyword id** (from R-k, refined 2026-08-22). The
   ladder DOES track SP product targets — they live in `DIM_KEYWORD` and the register seats
   them. The blind spot is the SB video / PT rows that arrive with `keyword_id` −1: no keyword
   id, no `DIM_KEYWORD` row, so the ladder cannot see them and their spend stays untracked on
   the 20% side (in Bottle it is the whole reason the family reads OUT — the row says so).
   The ruling for Ori: give those rows an identity the ladder can read (a synthetic key in the
   pipeline, then `SP_SNAPSHOT_KEYWORD_STATE` sweeps them), pause them, or accept the untracked
   spend. Measure them any day with:
   `SELECT family, campaign_name, target_text, cost_per_day FROM V_FAMILY_SEAT_REGISTER
    WHERE row_type = 'GAP' AND keyword_id = '-1' ORDER BY cost_per_day DESC;`
   (An earlier form of this ruling claimed the ladder reads keywords only and that every
   untracked gap was in a VIDEO/PT or COMPETE campaign; both claims were false on live rows —
   one gap was an SP product target, untracked only because its current `DIM_KEYWORD` row is
   paused and its spend trailing. The register now words that row as trailing, not blind.)
8. **PRODUCT-type brand phrases** (from D9). Only `phrase_type = 'BRAND'` phrases are matched;
   the PRODUCT-type phrases (`lollibox`, `lollime` …) are covered today by the ladder flag and
   the campaign-name rule on every live row. Whether they should also be matched as whole
   phrases (a keyword "lollibox gift" in a non-defense SB campaign would then be defense) is
   Ori's call; measured 2026-08-22 it changes no live row.
9. **Misspelt brand entries.** `DIM_BRAND_PHRASES` lists `lolli pop` and `lolli and pops` as
   BRAND phrases; with whole-phrase matching those entries — not the bare `lolli` substring —
   now decide that a `lolli pop …` keyword is defense. Keep them (misspellings of the house
   name) or drop them (generic candy terms): a data-entry decision, not a code change.
10. **A ledger archive.** Nothing remembers what a seat number was yesterday. The drift check
   therefore needs a copy of the ledger taken by hand BEFORE every pass, and a number rewritten
   in place cannot be detected at all without one. One row per open seat per snapshot date
   (or a slowly-changing copy) written by `SP_MAINTAIN_FAMILY_SEATS` itself would make D01 a
   pass-by-pass check on live data and remove the manual step. It is the natural home for Task
   5's health checks. Build it, or accept the hand-taken copy as the only instrument — in which
   case D00 is what stands between a forgotten copy and a run that reports PASS having tested
   nothing.
11. **A revival proposed but never applied.** Four parked seats (Fresh 6, LolliME 46, Lollibox 12,
   Lollibox 13) carry a re-verdict appointment on the current snapshot date, and their
   `next_check_what` reads "revival proposed — in today's plan". If the revival is proposed but
   never uploaded, the appointment expires, the seat closes `PARK_LAPSED`, and the same keyword
   can be re-seated the next time the ladder proposes a revival — a seat that opens and closes
   while nothing actually happens to the keyword. R-h decides what the seat is; it does not decide
   what happens to a proposal nobody acted on. Should an un-applied revival proposal renew the
   appointment, or should a lapsed one become a pause row? Read who is about to lapse with the
   query in the "Drift check" section.
12. **What the leak arm's pause row actually is** (2026-08-23). The recovered-today figure counts a
   PAUSE, and today every dollar of it comes from LEAK rows — PARKED / DEAD keywords still
   spending. The generator that would emit those rows is the leak arm of
   `tools/build_reprice_bulksheet.py` and it is **Task 3, not yet shipped**: the shipped generator
   selects `state IN ('AT_BAR','REPRICE','FLOOR_PROBATION','LOSER')`, so it emits a pause row for a
   FAILED keyword (state `LOSER`) but none for a leak. The register now says "on the next book
   (leak arm)" on the FAMILY row, exactly as the LEAK row's move always did, so no sentence claims
   a sheet that exists. Two things are still Ori's: (a) confirm the leak arm's row is a PAUSE on
   Amazon (a `State: paused` row), not an archive or a delete — if it is an archive, the same
   reasoning that excludes parking from the recovery may exclude it too; (b) decide whether Task 3
   ships before the register's recovered-today figure is acted on, since until it does the leak
   half of that figure has no generator behind it. **Since 2026-08-23 the two PROJECTIONS say the
   same thing** (R-l leak half, B35): neither day one nor re-judged takes a leak to $0 any more,
   because the sheet that would pause it does not exist. That is the honest reading, and it makes a
   family's projected rows worse, not better — a family whose day-one row read IN on the strength of
   those unearned dollars can now read AT THE LINE. Nothing about the failed half changed: the
   shipped generator builds that pause row today, so it still goes to $0 on re-judged. Read what is
   waiting:
   `SELECT family, campaign_name, target_text, cost_per_day, move FROM
    onyga-482313.OI.V_FAMILY_SEAT_REGISTER WHERE row_type = 'LEAK' ORDER BY cost_per_day DESC;`

## What the register never does

No engine reads it. No budget is moved. No seat count is chosen — counts fall out of dollars and
the engine's seat cost. No change to the verdict ladder, the bar or the floors. No family is
guessed from a campaign name — unmapped spend is published as unmapped. Holdout campaigns
(`DE_HOLDOUT_ASSIGNMENT`, arm HOLDOUT, from `eligible_from`) may hold seats and are marked on
every register row that names them, but are excluded from every sheet the register prescribes,
from the absorption advisory and from the probe queue.

## Standing Rule 0

Mechanism in prose, queries for numbers. The only constants declared here are `k_basis_days` = 7
(the spend basis), `k_context_days` = 28 (context), `k_probe_window_days` = 14 and
`k_verdict_clicks` = 20 (the engine's probing test, mirrored for the stalled-probe position),
`allowance_share` = 0.20 (the doctrine), `click_goal_day` = 4 (the seat model's daily click goal,
mirrored from `V_OOB_KEYWORD`), `absorb_capped_days` = 4 and `entry_raise_ratio` = 1.5 (the
wording rule of R-c). `at_line_band` is derived, not declared. Today's seat counts, costs, shares
and the acceptance tallies come from the ledger, the register and the test files, never from this
file.
