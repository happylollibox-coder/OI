# KEYWORD_STATE — the roadmap of each keyword

**Born:** 2026-08-16 (engine-finalization plan Task 2.1). **Owner request:** "the roadmap of each
keyword" — every keyword in exactly ONE state, with exactly ONE owner, and always ONE NEXT
APPOINTMENT (a date on which something will re-judge it).

**v27.104 (2026-08-22): THE FLOOR RULING — SHIPPED.** Ori, verbatim: "floor question bid-up-to-floor
if after a few days still loosing kill it" and "i think it is not 0.25 (we already checked it)". One
floor per channel and creative (`FN_BID_FLOOR` via `V_BID_FLOOR`), affordability in BID space,
`FLOOR_PROBATION`, the kill only at the floor after an elapsed probation, and the guard extended to
AT_BAR's standing price. Gate: `SIM_2026-08-22_ladder_floor_probation.sql` (TMP_SIM_LADDER_FLOOR) —
the SP reproduced it **855/855 exact, 0 differing** on the consistent 2026-08-22 snapshot chain.

**v27.103 (2026-08-22): THE BAR/SE LADDER.** Four Ori rulings plus the clean-then-judge guard,
gated on the A1 clean-rerun simulation (`scripts/bigquery/simulations/SIM_2026-08-22_ladder_clean_rerun.sql`,
result table TMP_SIM_LADDER_CLEAN — SP output verified 854/855 exact key-level agreement; the one
difference is the PACED_WINNER overlay reading today's live pace instruction, by design).

## Objects

| object | role |
|---|---|
| `SP_SNAPSHOT_KEYWORD_STATE` | Assembles reverdict/ownership/pacing verdicts from the other snapshots AND owns the bar/SE judgment (the one place the account says what a keyword's record is worth against its family's bar). Orchestrator Task 20.8, after the preflight (20.7) and after `SP_SNAPSHOT_FAMILY_BAR`. Reads FACT_AMAZON_ADS at term grain for the guard (~40s). |
| `FACT_KEYWORD_STATE` | One row per (campaign, keyword): state, owner, next appointment, settled record, bar machinery (family_bar, se_eff, N_f, affordable_cpc, click sufficiency), guard columns (ns_share, cleaned record, negate-valve population), season context, view-authored reason. |
| `V_KEYWORD_STATE` | Thin read surface. No logic. `SELECT *` freezes schema — redeploy it with every FACT column change. |
| `FN_BID_FLOOR` / `V_BID_FLOOR` | The ONE floor definition (channel × creative) and its per-ad-group resolution; the SP reaches it through `DIM_KEYWORD.ad_group_id` (unresolved ad group → `FN_BID_FLOOR(channel, NULL)`, source suffixed `_NO_ADGROUP`). |
| `V_BID_CPC_TRANSFER` | `m_effective` (MAX over target kinds per campaign) — the A4 placement translation from affordable CPC to affordable BID, done once in the SP (`affordable_bid`, `clean_affordable_bid`). |
| `tools/build_reprice_bulksheet.py` | THE ONLY EXECUTOR. NO ENGINE reads the state table — the new states move bids exclusively through the manual reprice book Ori uploads by hand. |

## The states (first match wins — the derivation order IS the doctrine)

| state | predicate | next appointment |
|---|---|---|
| `DEAD` | settled_clk90 ≥ 15 AND settled_ord90 = 0 — **re-derived from current data every run (A7), never passed through** | none (the one exempt state) |
| `PENDING_SETTLE` | reverdict = PENDING_SETTLE | reverdict settle_due |
| `REVIVED_SETTLING` | revive_settling | its settle_due |
| `PARKED` | reverdict ∈ (REVIVE, SIBLING_REVIVE, CONFIRM_PARK, REDUNDANT, INSUFFICIENT) | REVIVE → today; CONFIRM_PARK/REDUNDANT → +14d; INSUFFICIENT → its settle_due |
| `LAUNCH_CONTAINED` | bar_exempt family AND flat-era loser record (roas < 0.6 at ≥ 10 clk) — **a launch is never judged on profit, including in its label (A8)** | +7d |
| `PACED_WINNER` | clears the bar beyond noise + a GO bid-lowering instruction live today | tomorrow |
| `WINNER` | settled_roas90 − family_bar > se_eff at ≥ 10 settled clicks | last change + 14d else +7d rolling |
| `AT_BAR` | \|settled_roas90 − family_bar\| ≤ se_eff AND the click record does not rule the bar out — whatever the bid — **winner demotion (ruling 2) lands here: labels only, no bid moves on a relabel**; standing price = `GREATEST(affordable_bid, bid_floor)` | the EARLIER of `nf_collapse_forecast_date` (from its own 90d order pace) and the 7d re-read, never before tomorrow (A9) |
| `REPRICE` | below bar beyond noise AND an affordable **bid** (`affordable_bid` = affordable CPC / m_effective) exists at/above the keyword's own floor AND the bid is above the floor — move to it, re-judge after settle | last applied + 14d when still ahead (the scorecard's settled read); else +7d |
| `FLOOR_PROBATION` | below bar beyond noise AND (bid at/below its floor, ±½¢, OR no affordable bid at/above it) — the move is TO THE FLOOR from either side; `floor_since` is written (seeded on entry, carried forward from the table's own prior row) | `probation_due_date` = probation clock start + `settle_days_eff` (SP 3 / SB 14) + CEIL(10 / own 90d click pace), never before tomorrow; no pace → settle + 7 |
| `LOSER` | ONLY: `probation_elapsed` (≥ 10 settled clicks dated on/after the probation clock start = later of `floor_since` and the last bid change) AND `at_floor` AND still below bar beyond noise. **An above-bar keyword is never a kill, whatever its bid.** | +7d |
| `TRIAL` | everything else (clk < 10, or 0 orders under 15 clicks) | guard settle_due else +7d |

### The bar and its noise band (rulings 1 + 2)

- **bar_f** = `T_FAMILY_BAR.keyword_bar` (halo-adjusted breakeven, per family; COALESCE 1.0 when a
  campaign is unmapped — judged flat, as before).
- **se** = settled_roas90 / SQRT(settled_ord90) — order-space standard error of the record.
- **N_f** = CEIL((bar_f/(1−bar_f))²), computed from T_FAMILY_BAR **at run time, never hardcoded**
  (ruling 1). At ≥ N_f orders `se_eff` = 0: the band collapses and the verdict is wherever the
  number sits. Take today's values from the table, not this file:
  `SELECT DISTINCT family, keyword_bar, CAST(CEIL(POW(keyword_bar/(1-keyword_bar),2)) AS INT64) nf
   FROM T_FAMILY_BAR WHERE NOT bar_exempt AND keyword_bar < 1.0;`
- **A2 click-space sufficiency:** at the family's measured GP-per-order gpo_f, a keyword running AT
  the bar on its settled spend would have produced ord_bar = spend × bar / gpo_f orders. If
  observed orders fall short beyond SQRT(ord_bar), the click record itself rules the bar out and
  the order-SE band may NOT hide the row (`click_collapse` — the 489-click/4-order bleeder can
  never re-enter a band).
- **A3 one window:** verdict and price both read the settled-90 window (settled_cpc90 /
  affordable_cpc = gp_per_click / bar_f, or their cleaned equivalents). Live 7d CPC appears only
  in the reprice book, labelled as context.

### THE KILL CLAUSE (ruling 4 + the floor ruling — v27.104)

The v27.103 assertion ("every LOSER has failed AT its price" — settled CPC at/below affordable, or
no affordable price above a flat $0.25, or bid at/below $0.25) is **REPEALED**: two of its three
arms were phantom kills against a parking price. The standing assertion is now: **every LOSER is a
keyword that failed AT ITS OWN FLOOR, after its probation** — `probation_elapsed AND at_floor AND
below bar`. `V_ENGINE_HEALTH.loser_kill_clause` reads it (red > 0); self-check, must return 0:

```sql
SELECT COUNT(*) FROM `onyga-482313.OI.V_KEYWORD_STATE`
WHERE state = 'LOSER'
  AND NOT (probation_elapsed AND at_floor AND COALESCE(settled_roas90, 0) < family_bar);
```

Companion (`state_floor_resolution`, red > 0): no priced state (AT_BAR / REPRICE / FLOOR_PROBATION /
LOSER) may carry a NULL `bid_floor`; rows resolved on channel alone (`*_NO_ADGROUP`) are counted in
the detail so a silent drift to the conservative $0.25 is visible.

### The floors (v27.104, 2026-08-22 — Ori: "i think it is not 0.25 (we already checked it)")

A floor is a property of the CHANNEL and the CREATIVE, never a flat number. The ONE definition is
`FN_BID_FLOOR(channel, creative_type)`; `V_BID_FLOOR` resolves it per current ad group
(`DIM_AD_GROUP.creative_type`, `is_current`), and a keyword reaches its floor through
`DIM_KEYWORD.ad_group_id`. `V_LAUNCH_BID_LADDER` calls the same function (byte-identical output).

| row | floor | source |
|---|---|---|
| SP (anything not SB) | **$0.20** | house floor — Amazon's SP minimum is $0.02, but a bid that low buys no placement worth having |
| SB, `PRODUCT_COLLECTION` / `STORE_SPOTLIGHT` | **$0.10** | Amazon `minBid` |
| SB, video (`BRAND_VIDEO` / `VIDEO`) or NULL creative | **$0.25** | Amazon `minBid` ($0.15 / $0.20 rejected in r32 / r33); NULL resolves conservatively |

`V_OOB_KEYWORD`'s `0.25` is **`bid_park`** — a PARKING price, not a floor. v27.103's state ladder
borrowed it as a flat `platform_floor` and manufactured three phantom kills: `close-match`
BOX-SP/AUTO (Purple) at $0.24 and `complements` BOX -SP/AUTO (Blue) at $0.21 — both ABOVE the real
$0.20 SP floor and both at/above their family bar — and `tween girl gifts` (BOX-SBS/BROAD, an SB
collection keyword) whose floor is $0.10 and whose affordable $0.49 CPC ($0.46 bid) is perfectly
executable. Executability is tested in BID space: affordable bid = affordable CPC / the campaign's
measured placement multiplier (`V_BID_CPC_TRANSFER.m_effective`, A4).

### FLOOR_PROBATION — the floor ruling (Ori 2026-08-22, verbatim: "bid-up-to-floor if after a few days still loosing kill it")

**Status: SHIPPED (Step 2, v27.104) — `SP_SNAPSHOT_KEYWORD_STATE` runs this ladder; production
`FACT_KEYWORD_STATE` reproduced the simulation 855/855, 0 differing.** Simulation of record: `scripts/bigquery/simulations/SIM_2026-08-22_ladder_floor_probation.sql`
(TMP_SIM_LADDER_FLOOR, 7-day expiry), on the 2026-08-22 07:41–08:09 UTC snapshot chain.

| state | predicate |
|---|---|
| `REPRICE` | below bar beyond noise AND an affordable BID exists at/above the channel floor AND the bid is above the floor — move to it, re-judge after settle. The v27.103 "failed AT its price" CPC-materiality kill arm is REPEALED: a keyword is only ever killed at its floor (the book still applies the 5% materiality step to whether a row is emitted). |
| `FLOOR_PROBATION` | below bar beyond noise AND (the bid sits at/below its channel floor OR no affordable bid exists at/above it) — the move is TO THE FLOOR, from either side, and the keyword is re-judged after a few settled days AT the floor. |
| `LOSER` | ONLY a keyword whose FLOOR_PROBATION has ELAPSED and still reads below bar beyond noise. An above-bar keyword is NEVER a kill, whatever its bid (the v27.103 A2b "unexecutable AT_BAR → LOSER" arm is REPEALED). |

**"A few days" is derived, never a round number.** Probation ELAPSES on evidence: ≥ `vol_floor` (10)
settled clicks dated on/after `floor_since` (the date the state machine put the keyword at its
floor — carried forward by the SP from its own prior row; seeded by the first v27.104 run). The
appointment is the earliest date that evidence can exist: `floor_since + settle_days_eff`
(`FACT_KEYWORD_GUARD`'s own discipline, SP 3 / SB 14) `+ CEIL(10 / the keyword's 90d click pace)`.
Today's two probation rows forecast 6 and 7 days. No snapshot has ever recorded a FLOOR_PROBATION,
so `floor_since` is NULL everywhere and **the sim asserts ZERO LOSERs today**.

The guard defers every deterioration verdict (REPRICE / FLOOR_PROBATION / LOSER) and re-reads it
cleaned, as before — **and, since v27.104, AT_BAR's standing price** (see the guard section: `guard_scope`).

#### Probation memory (how `floor_since` is honest)

The SP reads its own prior `FACT_KEYWORD_STATE` row into a temp table before the rebuild (the column
is absent before the first v27.104 run and the table absent on a fresh project; both cases are
handled, never a first-run failure). `floor_since` = `COALESCE(prior floor_since, today)` while the
state is FLOOR_PROBATION or LOSER; any other state clears it. The probation CLOCK starts at the later
of `floor_since` and `FACT_KEYWORD_GUARD.last_bid_change_date` — the bid must actually have landed at
the floor for clicks to count as evidence at the floor (a book row that is never uploaded never
starts the clock; a raise off the floor ends `at_floor` and the kill arm with it).
`probation_clk_settled` = clicks dated on/after the clock start and on/before wm − settle_days_eff.
The SP reading its own previous output is not an engine reading the table: no engine reads it.

Published columns (v27.104, beside the v27.103 set): `ad_group_id`, `creative_type`, `bid_floor`,
`bid_floor_source`, `m_effective`, `is_brand_defense`, `affordable_bid`, `clean_affordable_bid`,
`at_floor`, `guard_scope`, `raw_state`, `clean_state`, `settle_days_eff`, `floor_since`,
`probation_clock_start`, `probation_clk_settled`, `probation_elapsed`, `probation_due_date`,
`probation_bid`, `nf_collapse_forecast_date`, `prior_state`. `state_reason` is one plain sentence per
state on the numbers the verdict used (guard-cleaned where the guard fired).

#### v27.104 transition matrix (live v27.103 state → floor-corrected state, 855 tracked keys)

| v27.103 \ v27.104 | AT_BAR | FLOOR_PROBATION | REPRICE | WINNER | (unchanged) |
|---|---|---|---|---|---|
| LOSER (5) | 2 | 2 | 1 | — | — |
| WINNER (76) | 1 | — | — | 75 | — |
| AT_BAR (50) / REPRICE (11) / PACED_WINNER (7) / TRIAL (70) / LAUNCH_CONTAINED (28) / DEAD (33) / PARKED (546) / PENDING (3) / REVIVED (26) | — | — | — | — | 826 |

Assertions (all on TMP_SIM_LADDER_FLOOR): 0 LOSERs; the two Bottle auto clauses (`loose-match`
$0.22, `substitutes` $0.24, affordable bids $0.03 / $0.14 under the $0.20 floor) land
FLOOR_PROBATION → bid to $0.20; `close-match` (Purple) and `complements` (Blue) land AT_BAR;
`tween girl gifts` lands REPRICE ($0.70 → $0.46 affordable bid, floor $0.10); the guard re-derives
its bar at 12.0% and the two drift flips reproduce (`substitutes` BOX-SP/AUTO White 0.58x → WINNER,
`shower gift set` FRESH-VIDEO 0.72x → WINNER); sums hold (884 rows = 884 keys = 855 tracked + 29
untracked spenders). **The third v27.103 "flip" — `complements` BOX-SP/AUTO (Purple), 0.57x shown
/ 1.90x on its own terms — no longer reaches the guard:** its raw verdict was only a deterioration
(LOSER) because of the phantom $0.25 floor; at the real $0.20 floor it reads AT_BAR within noise
(se 0.29) and the guard, which fires only on deterioration verdicts, leaves it there. Its AT_BAR
standing price ($0.17 affordable bid, under the floor) would book a cut to $0.20 on a mix the guard
already knows is drifted — **closed in Step 2: the guard covers every verdict that can move a bid
DOWN, AT_BAR's standing price included** (`guard_scope = 'AT_BAR_PRICE'`: the label stays AT_BAR,
`guard_deferred` is TRUE and the book prices the cleaned record — $0.56 bid on 1.90x own-terms for
this row). Live at ship: 2 AT_BAR_PRICE deferrals, 2 DETERIORATION flips (both → WINNER).

### CLEAN-THEN-JUDGE (the mix-drift guard)

Before any verdict that can move a bid DOWN stands — a deterioration verdict (REPRICE /
FLOOR_PROBATION / LOSER), or AT_BAR whose standing price would cut the bid by more than the book's
5% step — the SP measures the share of the
judging window's clicks on search terms **never seen** for that keyword in the prior comparison
window (the preceding 90d), **on measurable terms only** (≥ 5 judging clicks — the one-off
long-tail churns ~100% in every window pair and is background in both windows). The materiality
bar is **derived at run time** as the account click-weighted never-seen share on the same
measurable-term basis over keys with a measurable prior record (≥ 10 prior clicks) — a keyword
defers only when its own mix drifted beyond the account's measured background. A deferred keyword
is RE-READ excluding its zero-order never-seen terms and only the cleaned reading may downgrade
(`guard_deferred`, `guard_scope` ∈ {DETERIORATION, AT_BAR_PRICE}, `guard_flip`, `clean_*` columns).
DETERIORATION re-labels from the clean ladder; AT_BAR_PRICE keeps the label (the band is terminal)
and defers only the price the book may act on. The excluded population (`ns_zero_ord_terms`,
`ns_zero_ord_clicks`) is the **negate valve's** — it routes through the coach pipeline (negatives
act at AD GROUP grain — see fact_oi_negate_grain_mismatch), never as a raw list. Guard applies
only where a prior record exists; a keyword absent from the prior window has no comparison and its
record IS its record.

**Owner:** unchanged — `FACT_PANEL_OWNERSHIP.owner` with the REVERDICT-above-LIFT keyword overlay.

## The two invariants (standing self-checks; V_ENGINE_HEALTH reads them)

1. **One state:** `SELECT campaign_id, keyword_id … HAVING COUNT(*) > 1` returns 0 rows.
2. **No keyword without a next appointment:** `COUNTIF(next_check_date IS NULL AND state != 'DEAD') = 0`.
3. **The kill clause (v27.104):** `loser_kill_clause = 0` — see THE KILL CLAUSE above.
4. **Every priced row has its floor (v27.104):** `state_floor_resolution = 0`.

## THE REPRICE BOOK — the manual executor

`tools/build_reprice_bulksheet.py` (conventions of `build_stop_nonconverting_bulksheet.py`):

- Emits keyword/target **bid updates** for REPRICE and AT_BAR rows whose placement-translated
  affordable bid (`affordable_bid` / `clean_affordable_bid` when the guard fired, never below the
  row's own `bid_floor`) differs from the current bid by more than one 5% ease step (the engine's
  own smallest standing move); **to-the-floor moves** for FLOOR_PROBATION rows (from either side;
  a row already at its floor is shown as PROBATION_RUNNING); and **pause rows** ONLY for LOSERs
  whose `probation_elapsed AND at_floor` — any other LOSER is shown as REFUSED_PAUSE (always
  CHECK FIRST on a pause). No flat floor constant exists in the book (v27.104).
- **One keyword, one price:** a key carrying a live GO instruction in `T_ENGINE_PREFLIGHT` today is
  shown as ENGINE_INSTRUCTED and never executed — the engine speaks for it that day.
- Batch ids are time-stamped (`reprice_book_YYYYMMDD_HHMM`) so a re-derived book never collides
  with an earlier build's batch; `--no-log` skips the change-log insert.
- **A4 placement translation:** new_bid = affordable_cpc / M_campaign, where M is
  `V_BID_CPC_TRANSFER.m_effective` (the campaign's measured placement multiplier — the model's
  trustworthy part; β = 0 on brand defense). A naive CPC→bid mapping would RAISE bids on
  below-bar keywords in placement-dosed campaigns (Fresh ~85% placement-dosed).
- **A5 season interlock:** every bid-down and pause row is checked against the season ledger's
  BLOCK_CUT (`V_KEYWORD_CONTEXT_GATE`, keyword grain); a blocked row appears in the book with its
  reason and is NOT emitted as an executable row.
- **HOLDOUT:** campaigns in `DE_HOLDOUT_ASSIGNMENT` arm = HOLDOUT are excluded from their
  `eligible_from` date (2026-09-01) — a hand upload into the holdout invalidates the trial.
- Brand-defense campaigns never appear with a profit-based row.
- CHECK FIRST: rows the per-family N_f collapse newly condemns, and every LOSER pause row.
- Portfolio echoed on every row (blank DETACHES on Campaign rows); SP and SB routed to their
  sheets; audit CSV + plain-English README; restore generator
  (`tools/build_restore_reprice_bulksheet.py`) rebuilds the inverse sheet from the audit CSV.
- The batch is logged to FACT_PPC_CHANGE_LOG (source MANUAL, coach_mode MANUAL_BULKSHEET) so the
  scorecard grades it; if the book is never uploaded, mark the batch FAILED_UPLOAD.

## v27.103 transition matrix (A1 — the clean rerun that gated this ship, 2026-08-22)

Old flat state → new bar/SE state (tracked population, 853 keys; UNTRACKED spenders excluded):

| old \ new | AT_BAR | REPRICE | LOSER | LAUNCH_CONTAINED | WINNER | TRIAL | (unchanged) |
|---|---|---|---|---|---|---|---|
| WINNER (95) | 22 | — | 2 | — | 71 | — | — |
| LOSER_BLEED (43) | — | 6 | 2 | 28 | 2 | 5 | — |
| TRIAL (102) | 27 | 5 | 1 | — | 4 | 65 | — |
| PACED_WINNER (7) | 1 | — | — | — | — | — | 6 |
| PARKED/PENDING/REVIVED/DEAD (608) | — | — | — | — | — | — | 608 |

Guard's proof (live, from the clean rerun and reproduced in production): 3 deferrals, all flips —
e.g. `shower gift set` (FRESH-VIDEO/BROAD) reads 0.72x at $0.78 shown but 3.92x at $0.83 on its
own terms; `substitutes` (BOX-SP/AUTO White) 0.58x → 3.53x. The investigation's original case
(`girls gifts age 8-10`, $0.49 shown vs $0.55 own-terms) resolved differently post-refresh: its
never-seen share fell to 1% (below the 12% background), so its REPRICE verdict stands on its own
terms — and it is N_f-condemned (62 orders ≥ N_f 20), so the book marks it CHECK FIRST.

## v1 honesty notes (still true)

- `SEASONAL_HOLD` is NOT yet a state (the gate's ENTRY_BLOCK verdict is not snapshotted).
- `state_since` is best-effort.
- The 360° SIGNAL PANEL remains the task's second half.
- The negate valve for guard-excluded terms is exposed as columns (`ns_zero_ord_*`) but not yet
  wired into the coach pipeline's negate flow.
- A probation is judged on the whole settled-90 window (A3), not on the floor-period clicks alone —
  the floor-period record improves the window as it accrues; a floor-only read is a possible
  refinement, not built.
- The book logs its batch at BUILD time. A batch that is never uploaded must be marked
  `FAILED_UPLOAD` (the README says so) — otherwise `V_PPC_CHANGE_LOG_APPLIED` readers (the guard,
  LIFT, OOB, this SP's REPRICE appointment) treat moves that never happened as applied. The v27.103
  build's batch `reprice_book_20260822` (54 rows, never uploaded) sat unmarked at v27.104 ship and
  the automated run could not mark it (write blocked by policy) — Ori marks it:
  `UPDATE OI.FACT_PPC_CHANGE_LOG SET upload_status='FAILED_UPLOAD' WHERE batch_id='reprice_book_20260822' AND upload_status IS NULL`.
- 85 overdue appointments at ship are all PARKED / REVIVED_SETTLING rows whose reverdict
  `settle_due` lies in the past — other objects' verdicts, assembled unchanged; not this ladder's.
