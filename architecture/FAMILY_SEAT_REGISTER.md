# FAMILY_SEAT_REGISTER — the 80/20 doctrine for working families

**Born:** 2026-08-22. **Owner request (verbatim):** "for working families (not launch in the last 3
month) make sure 80% of budget is for winning or margin keywords / the other 20% should be for
losing … number them per family so you always know what seat you are opening and what you are
probing or waiting for results." Design spec: `docs/superpowers/specs/2026-08-22-family-seat-register-design.md`
(Approach A, approved). Plan: `docs/superpowers/plans/2026-08-22-family-seat-register.md`.

**Status:** Task 1 (the ledger) SHIPPED 2026-08-22; repaired the same day (rulings R-a / R-b
encoded, ledger memory added, plain-sentence reasons); polished with Task 2 (snapshot-dated
window, raise-bounded click count, no silent catch-all, brand words). Task 2 (the register view
`V_FAMILY_SEAT_REGISTER`, rulings R-c / R-d / R-e) SHIPPED 2026-08-22; repair pass 2026-08-23
(rulings R-f … R-k, defects D1–D14 closed: sign-aware stalled proposal, per-family at-the-line
band, parked seats, overdue settling, not-yet-serving trials, product-target gaps, three-way
queue defense, whole-phrase brand match, two-digit dates, one raise clock, horizon-true counts).
Second repair pass 2026-08-23 after verification: R-k REFINED — gap rows worded by their
MEASURED cause (the blanket "the ladder does not track product targets" was false on live rows
and is retired; see the R-k ruling and Open ruling 7), and the FAMILY "what closes the gap"
sentence made HONEST — when the listed moves recover less than the gap it says so and names
what does (gap-closure honesty, B29).
Tasks 3–5 (leak generator arm, morning surface, health checks) pending — this file grows with each.

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
| **R-c — engine parity stands** (2026-08-22, closes Open ruling 1) | Any standing applied raise that expired the engine's own test is stalled, whatever its size: a keyword that could not buy the verdict's clicks in the probe window at its raised bid is neither earning nor being tested. The register publishes the raise on the row (`raise_old_bid → raise_new_bid`, `raised_on`, `clicks_since_raise`, `days_since_raise`) and words the sentence by its size: a raise of `k.entry_raise_ratio` (1.5×) or more reads "entered at $1.00 on Aug 4 — 8 clicks in the 17 complete days since"; a smaller one reads "was nudged $0.45→$0.47 on Aug 4 — 0 clicks …"; a bid lifted past the logged raise adds ", now sitting at $1.00". Proposal on both, superseded by R-f (2026-08-23): the move branches on the sign of (seat price − live bid) and the park price is the engine's published `bid_park`, never the floor and never a literal. The seat price is READ from the budget engine's seat economics (`T_OOB_SEAT_ECONOMICS.seat_cpc`, materialised from `V_OOB_KEYWORD`), never restated; a campaign outside the engine has no seat price and the sentence says so. |
| **R-d — no test clock** (2026-08-22, closes Open ruling 2) | A TRIAL whose bid moved (more than one distinct bid in `DIM_KEYWORD`'s history) with NO applied change-log row — or away from the last logged bid since, other than the activation-floor lift R-b already treats as the raise standing — is NOT seated and is NOT "waiting": it is its own category **"waiting — no test clock"** on the 80% side, with the sentence "this bid was set outside the change log, so there is no date to judge it from" and the move "log the bid (or restore it by sheet) so the clock can start". A `REDUCE_BID` that lands on an entry price is a cut, not an entry (Bottle "truth or dare game" stays waiting). |
| **R-e — idle at the floor** (2026-08-22) | A TRIAL at the park bid with $0 spend and 0 clicks in the basis window is the category **"idle at the floor"**: $0, shown so nothing is silent, on neither side (no ratio is affected). |
| **R-f — a stalled probe at or above the seat price is parked, never "raised"** (2026-08-23) | The stalled-probe proposal branches on the SIGN of (seat price − live bid). Live bid BELOW the seat price: "raise to the seat price $X to get a verdict". Live bid AT OR ABOVE it: it could not buy a verdict even at the seat price, so the move is "park it — bid to the engine's park price and let the ladder's revive cycle re-test it". The park price is the engine's own `bid_park`, published by `V_OOB_KEYWORD` (column added 2026-08-23) and read through `T_OOB_SEAT_ECONOMICS` — never a literal; a campaign outside the engine has no seat price and is told so, with the same park price. A "raise" to a price at or below the live bid is never printed (asserted, B10). *To overrule:* name another park source (e.g. the channel floor `FN_BID_FLOOR`) — the register then reads that column; no literal. |
| **R-g — the at-the-line band is the judged family's OWN noise** (2026-08-23, closes Open ruling 2) | `at_line_band` is derived per family: stddev ÷ mean of THAT family's daily spend over the 28-day context window ÷ √(basis days). Bottle's $17/day noise never decides whether LolliME is at the line. The band and its derivation in words are published on every FAMILY row (B25 re-derives it). *To overrule:* name a pooled or fixed band — it becomes a declared constant in `k`, recorded here, never a hidden literal. |
| **R-h — a parked keyword with an appointment is a seat, not a leak** (2026-08-23) | The ladder parks a keyword at the park bid WITH a re-verdict appointment (`FACT_KEYWORD_STATE.next_check_date`): until that date it is being tested by the revive cycle. PARKED + spend on the basis window + appointment on or after the snapshot date = a SEAT, occupant kind **"parked — awaiting re-verdict"** (20% side, cost = its spend, move "no move — re-judged on <date>"). PARKED past its appointment with spend, or DEAD with spend = LEAK (pause row). **Which case held (measured 2026-08-23):** every PARKED row on the snapshot carried a usable `next_check_date` (the `next_check_what` texts read "re-read at settle" / "14d revival sweep re-checks" / "revival proposed"), so the appointment reading is LIVE; the spec's original all-leak reading was not needed. The ledger seats them (`SP_MAINTAIN_FAMILY_SEATS`; closure code `PARK_LAPSED` when the appointment passes or the spend stops; A16). *To overrule:* treat every PARKED spender as a leak — one branch in the occupant set and the code, the acceptance rows A16 / B26 flip with it. |
| **R-i — an overdue settling verdict is named overdue** (2026-08-23) | `REVIVED_SETTLING` / `PENDING_SETTLE` with `next_check_date` before the snapshot date stays on the 80% side (waiting = 80, Ori's ruling) but the sentence and the move read "was due to settle on <date> — overdue by N days; the ladder has not re-judged it". The cause is upstream and is being diagnosed read-only; the register never changes the ladder (B18). *To overrule:* move overdue settling to the 20% side — one side value in the codes table. |
| **R-j — "too few clicks yet" needs clicks** (2026-08-23) | "waiting — too few clicks yet" requires clicks > 0 on the basis window (spec §3). A TRIAL with $0 and 0 clicks that is neither at the floor nor no-clock is **"waiting — not yet serving"**: $0, published, on no side (affects no ratio) (B27). *To overrule:* fold it back into waiting — one branch in the code. |
| **R-k — a gap is worded by its MEASURED cause** (2026-08-23; refined the same day after verification) | The original reading — "the verdict ladder reads `DIM_KEYWORD` only, so a product target never gets a verdict" — was FALSE on live rows: SP product targets live in `DIM_KEYWORD`, the ladder tracks them and this register seats them (repairs, probes, settling and parked seats with `asin=` targets exist on the snapshot; query the SEAT rows for `asin=` to see them — and when COUNTING product targets, match `asin=` OR `category=`: the snapshot carries both prefixes, and an `asin=`-only count silently drops the `category=` rows, a mislabel a verification pass actually caught). The real blind spot is narrower: SB video / PT product-target rows reach the warehouse with **`keyword_id` −1** — no keyword id, so no `DIM_KEYWORD` row can exist and the ladder cannot see them. Every GAP row is therefore worded by the cause the view MEASURES (`keyword_id` and the current `DIM_KEYWORD` state): `keyword_id` −1 → "no keyword id — the ladder cannot see it; a ruling for Ori, not a mapping fix"; a paused/archived current row → "trailing spend — leaves the universe when it stops; no verdict is coming and none is needed"; an enabled row → "verdict arrives on the next state run"; a real id with no current row → "check why". The blanket phrase "the verdict ladder does not track product targets" is retired and B19 asserts it appears nowhere. **Extending the pipeline/ladder to the no-keyword-id SB video rows is a RULING FOR ORI**, not built here. *To overrule:* give those rows an identity the ladder can read (or extend `SP_SNAPSHOT_KEYWORD_STATE` to a synthetic key) — the blind gap rows then disappear on their own. |

## Objects

| object | role | status |
|---|---|---|
| `DE_FAMILY_SEAT_LEDGER` | The only state the register keeps: one row per occupancy (family, campaign_id, keyword_id, opened_on) with `seat_no`, `closed_on`, `closed_reason`, `closed_reason_text`, `occupant_kind_at_open`, `last_observed_kind`, `last_observed_state`. | shipped |
| `SP_MAINTAIN_FAMILY_SEATS` | Orchestrator Task 20.8b, right after `SP_SNAPSHOT_KEYWORD_STATE`. Closes, reopens, admits, observes. Idempotent on the same snapshot. | shipped |
| `V_FAMILY_SEAT_REGISTER` | FAMILY / CATEGORY / SEAT / OPEN_SEAT / LEAK / GAP / NO_CLOCK / ABSORB / REFERENCE / UNMAPPED rows — the object Ori reads. | shipped |
| `T_OOB_SEAT_ECONOMICS` | The budget engine's seat economics (slots, seat_rank, seat_cpc, role, and since 2026-08-23 the engine's park price `bid_park` — R-f) materialised once per pass from `V_OOB_KEYWORD` by `SP_REFRESH_CUBE_TABLES` step 0b, right after `T_LIFT_PROBES`. Exists because `V_OOB_KEYWORD` is a planner-ceiling view measured in minutes and the register may never inline it. | shipped |
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
| `PARK_LAPSED` | The keyword reads parked on the ladder but is no longer a parked seat: it has no spend on the basis window, or its re-verdict appointment has passed. A parked keyword that still spends past its appointment is a leak (pause row). The seat is free. (R-h, 2026-08-23.) |
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

**Acceptance** (`scripts/bigquery/tests/DE_FAMILY_SEAT_LEDGER_acceptance.sql`, every check passes):
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
record 2026-08-23 (R-h): the new check FAILED on the live ledger (the parked spenders with an
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
as such) and the leaks are paused; `re-judged` assumes the repairs hold at their bar and move to
the good side at their day-one cost, probation keywords stay at their floor, failed keywords are
killed, stalled probes are parked, engine probes and settling verdicts hold, untracked spend is
unchanged. Projections are labelled projections in the sentence.

**Seat economics.** A seat costs what its occupant spends per day on the basis window. A probe's
admission cost is the engine's own: the campaign's `seat_cpc` × `k.click_goal_day` (4 — the seat
model's one 4-click trial a day), read from `T_OOB_SEAT_ECONOMICS`; the OPEN_SEAT row proposes
the first QUEUED keyword (by the engine's `seat_rank`) the open capacity can afford. The engine's
park price (`bid_park`) is read from the same table (R-f) — `V_OOB_KEYWORD` publishes it since
2026-08-23; the T_ is rebuilt by `SP_REFRESH_CUBE_TABLES` step 0b. The register proposes; the
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
defense category matches the whole-phrase re-derivation (D9); and a family whose listed moves
recover less than its gap is told they do not close it, with what does named on the row —
gap-closure honesty, so a reader who does everything on the row is never promised a closure the
moves cannot deliver (B29). The checks read their constants from
the test's `k` CTE, which mirrors the view's. TDD record
2026-08-22: run before the view existed, the script failed (object not found); after deploy one
check (B12) FAILED on a NULL-swallowing re-derivation in the TEST (a stalled test with no log row
is NULL, and `NOT NULL` hid the keyword) — the view was right, the test was fixed, then every check
PASSED. Repair pass, same day: the universe re-derivation tightened to spend on the BASIS window,
the defense test moved onto the row itself, the holdout check widened to every row naming a
campaign and to the move text, and checks added for unmapped spend and phantom gaps; against the
first view those new and tightened checks FAILED (the phantom $0 gaps, the 'happy lolli' defense
target published as a gap, the two holdout campaigns on ABSORB rows, the unmapped campaigns, the
$0 GAP rows); after the repaired view, every check PASSED, and two uncached pulls gave an
identical MD5. Repair pass 2026-08-23 (D1–D14): the tightened and new checks were run against the
live view FIRST and FAILED where the defects lived — the sign-blind stalled proposals (B10), the
overdue settling rows published as future (B18), the product-target gaps promised a verdict (B19),
the REFERENCE wording (B20), the projection counts (B21), the space-padded dates (B23), the two
clocks (B24), the shared band (B25), the missing parked seats (B26), the $0 trials read as
waiting (B27); the queue-defense and whole-phrase checks (B22, B28) passed on live data because
no live row exercised them and were proven on `TMP_` copies with injected rows (below); after the
repaired view every check PASSED and two uncached pulls gave an identical MD5.
Second repair pass 2026-08-23 (R-k refined + gap-closure honesty): B19 was rewritten to assert
the measured-cause wording and the absence of the retired blanket phrase, and B29 added; both
were run against the live view FIRST and FAILED exactly where verification had placed the
defects — every gap row and the family gap sentences carried the blanket phrase, the paused
SP product target was worded as ladder-blind, and one OUT family promised a closure its listed
moves could not deliver; after the repaired view every check PASSED and two uncached pulls gave
an identical MD5. (A test-side lesson recorded in the test file: filtering on the universe's
EXISTS-derived defense flag in a WHERE trips BigQuery's non-equality ANTISEMI-join limitation —
the house anti-join rule — so the gap-cause re-derivation keeps its filters inside COUNTIF.)
Determinism: two uncached pulls, identical MD5 (query at the bottom of the test file).

**`TMP_` proofs of 2026-08-23** (house rule: synthetic rows only on `TMP_` copies, never in a
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

## Open rulings for Ori (register, 2026-08-22)

Each is a design choice the register was BUILT with; none is a defect. Ori may overrule; the
change is then a derivation or a source, never a literal.

1. **Allowance base.** The 20% allowance is computed on the JUDGED spend (80% side + 20% side);
   brand-defense dollars are published beside the ratio and buy no seats. The alternative — 20%
   of all family spend including defense — would let defense dollars buy seats.
2. **`at_line_band`.** CLOSED by R-g (2026-08-23): the band is the judged family's OWN noise,
   one per family, published with its derivation on every FAMILY row.
3. **R-d detection.** "The bid moved" reads `DIM_KEYWORD`'s distinct bid count; a raise the SCD2
   did not capture reads "waiting", not "waiting — no test clock". Under-detection only — never a
   false seat. Accept, or point the test at another bid-history source.
4. **Where `T_OOB_SEAT_ECONOMICS` is built.** `SP_REFRESH_CUBE_TABLES` step 0b (one extra
   evaluation of `V_OOB_KEYWORD` per pass, minutes) vs folding it into
   `SP_SNAPSHOT_ENGINE_PROPOSALS`, which already evaluates the view. Built as the former.
5. **Stalled probes outside the budget engine** (e.g. the COPYCAT campaigns) have no published
   seat price. CLOSED by R-f (2026-08-23): the row says "price it by hand or park it at the
   engine's park price" — the park price is the engine's published `bid_park`, so even a
   campaign outside the seat model gets a real park price, never a literal.
6. **Unmapped spend** is published as its own block and charged to no family. The alternative —
   charging it to the 20% side of the family a campaign NAME suggests — would be a guess the
   register refuses to make; mapping is Admin's job (Campaign Mapping).
7. **SB video product-target rows with no keyword id** (from R-k, refined 2026-08-23). The
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
   Ori's call; measured 2026-08-23 it changes no live row.
9. **Misspelt brand entries.** `DIM_BRAND_PHRASES` lists `lolli pop` and `lolli and pops` as
   BRAND phrases; with whole-phrase matching those entries — not the bare `lolli` substring —
   now decide that a `lolli pop …` keyword is defense. Keep them (misspellings of the house
   name) or drop them (generic candy terms): a data-entry decision, not a code change.

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
