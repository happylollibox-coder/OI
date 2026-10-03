-- =============================================================================================
-- SP_BUILD_NEXT_WEEK_PLAN — v27.169 (2026-10-03): the nightly plan for the working families.
-- v27.169 (2026-10-03): THE P-14b ASSERTION REJECTS A RELEASE REASON NO RULING NAMES. A demotion
--   under the guard's preconditions (not-good, was good, served, unsettled) passes only when
--   guard_released_by is HOLD_EXPIRED or LAST_DAY_NOT_STRONG. v27.147 .. v27.168 tested IS NULL
--   only, so the judge's UNEXPLAINED catch-all -- which V_PLAN_WINDOW_JUDGMENT keeps so that a
--   future reordering of its arms fails loudly -- passed this assertion, as did any unrecognised
--   value. No column, verdict, seat or move changes.
-- v27.168 (piece-1 follow-up G1, 2026-10-03; P-16 = Ori's ruling R2 of 2026-10-02):
--   AN INCUMBENT IS COSTED BY THE QUESTION IT KEEPS. P-16 keeps an incumbent's question (clicks,
--   due date, expected CPC, implied spend, request_basis), and its cost branch now follows that
--   question's basis (prior_seat.held_basis): 'HORIZON_PROBE_GOAL' — the basis this builder writes
--   on a probe's question (`questioned`.q_basis) — costs click_goal_day x kept price; any other
--   basis costs (w_sp / window_days) x kept price / current bid (0 with no spend or no current bid).
--   v27.164 .. v27.167 branched on tonight's is_probe, so a keyword seated as an ordinary seat that
--   turned probe the next night was costed as a probe while its question still asked for its
--   window's click rate: on the 2026-10-03 partition built 12:18 UTC, plan B Fresh keyword
--   388620934464557 (campaign 292848303399755), seated 10-02 at $0.25 asking 5 clicks by 10-16
--   (HORIZON_WINDOW_RATE, $0.1067 a day), a LIFT probe nominee on 10-03 with no window spend, cost
--   4 x $0.25 = $1.00 a day and its sentence said "A RAISE of about $1.00 a day in spend" at a price
--   held at its current bid. Tonight's is_probe still decides the move (OPEN_PROBE, P-25). The same
--   test is in `ranked`.inc_cost, the P-16 assertion's cost_tonight, acceptance T1 and
--   check_plan_seat_controls.py. A seat taken tonight is unchanged.
--   Measured: SOP §3, "An incumbent is costed by the question it keeps".
-- v27.167 (piece-1 follow-up F8, 2026-10-03; P-16 = Ori's ruling R2 of 2026-10-02):
--   WHEN THE ALLOWANCE SHRINKS, INCUMBENTS LEAVE LATEST-SEATED FIRST UNTIL THE REST FIT. Walk 1
--   (`walk_inc`) is a PREFIX of the incumbents in the order they took their seats (seat_since,
--   earliest first; tonight's rank breaks a tie): it keeps them while the running total fits the
--   ramped allowance, and the first one that does not fit leaves together with every incumbent
--   seated after it (LEFT_ALLOWANCE_SHRANK). Every branch of inc_cost multiplies non-negative
--   factors (a bid, a click goal, a window spend), so the running total only grows along the order
--   and this prefix is the set R2 names: the latest seated dropped one at a time until the rest fit.
--   v27.159 .. v27.164 walked the incumbents with walk 2's fit test (skip and continue), so an
--   earlier, costlier incumbent could leave while a later, cheaper one kept its seat. An incumbent
--   that leaves is a candidate like any other in walk 2, at tonight's price and in rank order
--   (unchanged). The P-16 assertion and acceptance T1 now test the order — no incumbent that left
--   was seated before one that kept its seat — and that the first one to leave did not fit what the
--   kept ones leave of the allowance; the TENURE ENDS EARLY sentence states the rule and what the
--   kept incumbents cost (inc_spent.n_kept, .spent).
--   Measured 2026-10-03 (dry runs, the partition write swapped for a scratch table; SOP §3,
--   "Incumbents leave latest-seated first"): on the judgement snapshot OI._tmp_f8_judge (11:00 UTC)
--   the v27.164 and v27.167 bodies write equal 10-03 partitions, 712 rows, every column but
--   built_at (no incumbent leaves that night). On a copy with LolliME's and Fresh's
--   allowance_share 0.25 and ramp_steps 1, four plan x family walks shrink: v27.164 kept 19
--   incumbents seated after one that left ($51.29 a day); v27.167 keeps none, sends 84 out and walk 2
--   re-seats 20 of them as NEW. On that copy the P-16 assertion refuses this body with walk 1 put
--   back to the fit test, and the prefix under the v27.164 eviction test.
-- v27.164 (piece-1 follow-up F2, 2026-10-03; P-16 = Ori's ruling R2 of 2026-10-02):
--   AN INCUMBENT'S COST IS TONIGHT'S MONEY. P-16 keeps an incumbent's seat, number, planned price,
--   verdict date and question — not the cost its seat was granted at, which was the window of the
--   night it was seated at that price. Its cost tonight is its KEPT price on TONIGHT's window:
--   (w_sp / window_days) x kept price / current bid (0 with no spend or no current bid), and on a
--   probe (is_probe tonight) click_goal_day x the kept price, the price it opened at
--   (`ranked`.inc_cost). Walk 1 charges that cost to the allowance, and the seat sentence's
--   direction clause ("A RAISE / a cut / no change"), planned_spend_per_day, the campaign need,
--   expected_after_upload_per_day and share_closed all read it. Until v27.160 an incumbent carried
--   its contract's cost: on the 2026-10-03 partition (built 08:12 UTC) 30 live incumbent rows
--   (Bottle 1, Fresh 7, LolliME 20, Lollibox 2) printed "A RAISE" while their price was held or
--   cut, $15.24 a day in total. The question (clicks, due date, expected CPC, implied spend, basis)
--   is still the one the seat was given, so on an incumbent implied_daily_spend is the money of
--   the night it was asked and seat_cost_per_day is tonight's (acceptance T3 and S04 compare the
--   two on the seats taken tonight; T1 recounts an incumbent's cost from its row).
-- v27.160 (piece-1 plan Task 6; Ori's ruling R11 of 2026-10-02 = spec P-24, and audit fix #25):
--   P-24     A NIGHT IS KEYED ON THE NEW YORK DATE: as_of_d = CURRENT_DATE('America/New_York'),
--            the date V_PLAN_WINDOW_JUDGMENT reads the calendar state on (its plan history and its
--            count of nights moved to the same date in the same version). The window fence stays
--            on Los Angeles. Partitions written before v27.160 are keyed on the Los Angeles date.
--            R11's GUARD: before the DELETE, a partition for as_of_d written under a calendar state
--            other than tonight's is never rewritten — the build refuses ("partition <date> was
--            written under <state>; tonight reads <state>; refusing to rewrite").
--   fix #25  a shadow (plan A) row whose side differs from the live plan's names the ladder state,
--            plan A's side and rule B's verdict, then plan A's own move; it no longer opens with the
--            judgement's rule-B sentence (and its P-4 "carries no planned price" clause).
--   The ramp step's upload count reads applied_at on the New York date too (the clock as_of is on).
-- Reads V_PLAN_WINDOW_JUDGMENT (the side and the price) ONCE and turns it into money:
--   1. POT (P-2, P-15)  the GOOD side's window spend per day, per family — EVERY GOOD keyword of
--                       the family, holdout included (P-15, Ori 2026-10-02). Not the family total.
--   2. ALLOWANCE (P-2)  allowance_share x pot, from DE_PLAN_CONFIG for today's calendar state.
--   3. RAMP (P-8, P-21) one third of the gap between today's not-good spend and the allowance is
--                       closed each window, so a family several times over the line is not parked
--                       in one upload, and the ramped allowance is never above today's not-good
--                       spend (P-21). Re-anchored on tonight's actual not-good spend, so it
--                       descends only as uploads cut that spend: with no upload, each night re-takes
--                       the same one-third step from a base that drifts with the window.
--                       ramp_step counts the plan uploads that LANDED (v27.158, audit fix #15).
--   4. SEATS (P-6, P-7, P-16, P-20)  INCUMBENTS FIRST (P-16, v27.159): a keyword seated in the
--                       previous partition under P-16, before its verdict date and still a
--                       candidate (not GOOD, not holdout, ladder not DEAD), keeps its seat, number,
--                       price, verdict date and question, and costs its kept price on tonight's
--                       window (v27.164); when tonight's allowance cannot carry
--                       every incumbent they leave latest-seated first until the rest fit (a prefix
--                       in seat order, v27.167). Then not-good CANDIDATES ranked by P-7's score, the zero-score ones
--                       by money burned with no return (P-20, v27.159), each costing its spend AT
--                       THE REPAIRED PRICE, walked in rank order into what the incumbents left: a
--                       candidate takes the lowest free seat WHENEVER ITS OWN COST FITS THE
--                       ALLOWANCE STILL UNSPENT (§4.4 — a fit test, not a prefix stop; one lumpy
--                       candidate does not close the queue behind it). A KEYWORD THE LADDER HAS
--                       CLOSED IS NOT SEATABLE AT ANY PRICE (v27.138). A seated keyword keeps its
--                       number from DE_FAMILY_SEAT_LEDGER (live plan only, v27.159), or failing
--                       that the number it held MOST RECENTLY in any earlier partition (P-28,
--                       v27.159; v27.138 read last night's only); a new occupant takes the family's
--                       lowest number neither source is still holding, in rank order.
--   5. QUEUE (§4.5)     every candidate that did not fit: parked at the engine's park price, held
--                       at the price it already has when that is at or below the park price, or
--                       paused when THE LADDER HAS ALREADY CLOSED IT; an UNSEATED PROBE gets no
--                       move and nothing is uploaded (P-25, v27.159). Planned spend zero — see
--                       the note. P-22 (v27.158) publishes what the family is EXPECTED to spend
--                       after the upload — the seats plus the queue at the price it is left at —
--                       and the share of the gap that closes, beside the allowance.
--   6. MOVES (§4.6)     one executable instruction per CANDIDATE; none on the good side, and none
--                       on a not-good keyword with nothing to repair (§9, v27.135). A seated probe
--                       is OPEN_PROBE (P-25, v27.159). Every seat names its question over its
--                       settle horizon (P-26, v27.159).
--   7. BUDGETS (§4.7)   a campaign's planned budget is ramped from today's budget by the same
--                       one-third step and floored at THE MONEY THE PLAN CAN SEE INSIDE THAT
--                       CAMPAIGN — its good side, its seats at the repaired price, AND the queue
--                       that keeps buying clicks at the park price (v27.138: the v27.137 floor
--                       counted the queue at zero, which is the plan's own arithmetic and not the
--                       money, so a campaign whose spend is all queued was ramped towards a figure
--                       the plan's own PARK sentence disowns). NO MOVE AT ALL on a campaign the
--                       plan measured nothing in, or on a brand-defense campaign (v27.138: the
--                       ramp was a one-third step towards zero on 19 unmeasured campaigns, one of
--                       them brand defense, compounding nightly). Then snapped out of the
--                       forbidden $20.01-$31.99 band and floored at Amazon's $1.00 minimum. Every
--                       row publishes the cap's delta, its basis and the visible spend, and says
--                       all three in words — the cap is the largest number here and used to be
--                       the silent one. v27.158: a HOLDOUT campaign's cap is not moved either
--                       (NO_MOVE_HOLDOUT, audit fix #11), and the basis names what bound the cap
--                       (RAMPED only when the cap is the one-third ramp's number, FLOORED_AT_NEED,
--                       BAND_SNAPPED_UP / _DOWN, FLOORED_AT_MINIMUM; audit fix #12).
-- BOTH PLANS ARE WRITTEN (P-9): 'B' is live (rule B decides the side), 'A' is the shadow (the
-- ladder decides the side, the window decides the amount). The scorecard grades both at T+14.
--
-- WHY THIS PROCEDURE IS A DOCTRINE DELIVERABLE AND NOT A REPORT. V_PLAN_WINDOW_JUDGMENT reads
-- this table back as the plan's MEMORY: `side` on the live rows is the P-14b guard's "was good"
-- from tomorrow onwards (the ladder is only the bootstrap for a keyword the plan has never seen),
-- and `verdict = 'GRACE'` is what SPENDS P-5's one quiet window. Writing the first partition ARMS
-- the grace limit that has been unenforceable since Task 1 — so GRACE is written as GRACE and is
-- never collapsed into GOOD, and the side is written from the same expression the view publishes.
-- C13 of the acceptance asserts the live plan reproduces the view row for row on side, verdict and
-- candidacy, precisely so no future edit here can quietly re-grant a permanent exemption.
--
-- THE QUEUED-SPEND NOTE, CORRECTED (v27.137). Parking lowers a keyword's price; it does not stop
-- its spend (the seat register's measured ruling R-l). This procedure follows the spec's
-- arithmetic — a queued row's PLANNED spend is zero — and says so in words on the row, so nobody
-- reads "queued" as "stopped". But the earlier version of this note claimed that made "seats +
-- queued = the not-good side" hold to the cent, and IT DOES NOT: with the queue at zero the
-- identity that holds is seats = the not-good side's PLANNED spend, while the queue's real spend
-- carries on at the park price and is exactly the residual between the plan and the money. The
-- restatement is in spec §9 and acceptance C19 asserts the identity that is true. Ori ruled on
-- 2026-10-02 (R8 = P-22, option (b)): the arithmetic stays, and the residual is PUBLISHED beside
-- the allowance — expected_after_upload_per_day (the seats' cost + the queue at the price the plan
-- leaves it at) and share_closed (the share of the gap to the allowance target that closes), per
-- family, on every row and in the FAMILY clause of the sentence (v27.158; acceptance M3).
-- What still holds unconditionally is seats <= the ramped allowance (P-2, P-8), asserted.
--
-- FOUR READINGS THIS BUILDER HAD TO MAKE, each recorded for Ori (SOP §3, "What Ori still rules"):
--   (a) THE HOLDOUT GETS NO MOVE, AND ITS GOOD KEYWORDS STILL SIZE THE POT (ruled 2026-10-02,
--       R1 = P-15, option (a); built v27.158). Until v27.157 this reading kept a holdout campaign's
--       spend out of the pot as well as out of the not-good side and the ramp base, so the treated
--       arm's allowance was set by the draw (Bottle's GOOD keywords all sit in the holdout campaign
--       BOTTLE-SP/AUTO, so its pot read $0 on every live night). Now the pot counts every GOOD
--       keyword of the family, holdout included; the not-good base still excludes holdout rows; a
--       holdout row still gets a row, a side and a sentence — the counterfactual — and no move, and
--       since v27.158 its CAMPAIGN CAP is not moved either (NO_MOVE_HOLDOUT, audit fix #11: on each
--       live partition 2026-09-28 .. 10-02 the plan moved the caps of 7 of the 8 holdout campaigns,
--       $57.53-$82.35 a day of raises; query in SOP §3, "What v27.158 moved").
--   (b) A NOT-GOOD KEYWORD WITH NOTHING TO REPAIR GETS NO MOVE. Spec §9 (v27.135): a keyword with
--       no spend, no clicks and no probe nomination takes no seat AND no queue position. Parking
--       a keyword that spends nothing saves nothing, and it would bury the ranking. move = 'NONE'.
--   (c) PLAN A CANNOT ALWAYS BE PRICED. P-4 makes the judgement view withhold planned_bid and
--       seat_cost_per_day wherever rule B calls the row GOOD (C14 of Task 1). Some of those rows
--       are NOT good to the ladder, so the SHADOW plan wants to price a keyword the LIVE plan
--       protects. Rather than compute the repaired price a second time — the "one keyword, two
--       prices" defect — the shadow holds such a row at its current price and costs its seat at
--       its current spend per day, and the row says so. This touches plan A only; plan A is never
--       uploaded. If Ori wants the shadow priced properly, the one-line fix is in the judgement
--       view (publish the unmasked price under a second name), never here.
--   (d) THE BUDGET SEES ONLY THE PLAN'S OWN KEYWORDS, SO IT IS RAMPED AND FLOORED AND SOMETIMES
--       NOT MOVED AT ALL. Brand defense, launch-contained and non-keyword targets are outside the
--       universe (§8), so a campaign that mixes them looks cheaper to the plan than it is. Ramping
--       only SLOWS a wrong descent; it does not stop one, and a cap the ramp re-reads every night
--       compounds. So v27.138 adds the two floors ramping cannot supply: the cap is never set
--       below the money the plan can SEE inside the campaign (queue included), and a campaign the
--       plan measured nothing in — or a brand-defense campaign — is not moved at all.
--
-- THE MONEY, AS ORI RULED IT ON 2026-10-02 (v27.158, piece-1 plan Task 4).
--   P-15 (R1)  the pot is every GOOD keyword of the family, holdout included (fam).
--   P-21 (R7)  the ramped allowance is capped at today's not-good spend (fam2).
--   P-22 (R8)  expected_after_upload_per_day and share_closed are published per family (fam_money).
--   fix #11    a holdout campaign's cap is not moved: NO_MOVE_HOLDOUT, asserted with the holdout rule.
--   fix #12    campaign_budget_basis names what bound the cap; RAMPED is asserted to be the ramp's
--              number to the cent.
--   fix #15    ramp_step = the plan uploads that LANDED for the family since its first plan night,
--              capped at ramp_steps (plan_uploads_landed); it was a calendar count of windows.
--   fix #24    acceptance C03 / C15 and V_ENGINE_HEALTH plan_pot_reconciliation read P-15.
-- Migration 2026-10-02_plan_money_columns.sql adds the three columns; deploy it first.
--
-- THE SEATS, AS ORI RULED THEM ON 2026-10-02 (v27.159, piece-1 plan Task 5).
--   P-16 (R2)  a seat is held until its verdict date while its keyword is still a candidate:
--              prior_seat, two walks (incumbents in seat order — a prefix since v27.167, follow-up
--              F8 — then newcomers in rank order into what is left), seat_since / seat_tenure on
--              the row, the tenure assertion. THE
--              CUTOVER: a seat is an incumbent only if it was written with seat_since (from
--              v27.159); seats written before were priced before P-19 / P-25 and asked before P-26.
--   P-20 (R6)  the builder ranks as the judge orders: GREATEST(rank_score, 0), rank_money_burned,
--              clicks, keys (the judge's half shipped in v27.157).
--   P-25 (R12) a seated probe is OPEN_PROBE at the judge's probe price; an unseated probe gets NONE
--              and nothing is uploaded (audit fix #19); the PARK / HOLD_AT_PARK words branch on
--              service; is_probe is copied onto the row.
--   P-26 (R13) clicks_requested = the window's click rate x settle_days (probes click_goal_day x
--              settle_days), due on the verdict date; expected_cpc follows so clicks x CPC /
--              horizon = implied_daily_spend = the seat's cost.
--   P-28 (R15) a seat number is the keyword's most recent seat in ANY earlier partition (claims);
--              the register numbers the live plan only; the continuity assertion reads the same
--              memory. SP_MAINTAIN_FAMILY_SEATS v27.159 re-opens a ledger row only with the plan's
--              number, so the register and the plan stop disagreeing.
-- Migration 2026-10-02_plan_seat_tenure_columns.sql adds seat_since, seat_tenure, is_probe; deploy
-- it first.
--
-- THE JUDGE'S MEMORY IS CARRIED (v27.156, 2026-10-02, rulings R3/R4/R16 = spec P-17/P-18/P-29).
-- hold_strong_day, hold_kept_by, grace_since and memory_cleared_by_gap are copied from the judge
-- (migration 2026-10-02_plan_judge_memory_columns.sql). memory_cleared_by_gap is not a report:
-- V_PLAN_WINDOW_JUDGMENT reads it back from this table as a reset, so a grace or hold memory a GOOD
-- gap window cleared tonight stays cleared tomorrow. The HELD assertion reads hold_kept_by (P-18:
-- a hold lasts while the very good day that started it is still in the window), so a hold kept by
-- that day is not refused for lacking a very good LAST day.
--
-- THE RULE IS CARRIED (v27.154 follow-up, 2026-10-01). strong_day_mult and strong_day_min_orders
-- are copied from the judge onto every row, so the plan table records the P-14c rule each decision
-- was made under and FN_PLAN_SCORECARD never grades history against today's constant. A column
-- copy: no assertion reads them.
--
-- Idempotent: deletes today's as_of partition (the New York date, v27.160) and rewrites it — unless
-- it was written under another calendar state (R11's guard). Never touches an earlier one.
-- Deterministic: every ordering reaches the keyword key.
-- Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.8c, after the seat ledger (20.8b).
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §4, §5, §9.
-- Acceptance: scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql
-- SOP: architecture/NEXT_WEEK_MONEY.md §3.
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN`()
OPTIONS (description = "v27.169 (2026-10-03): the P-14b assertion accepts a demotion under the guard's preconditions (not-good, was good, served, unsettled) only when guard_released_by is HOLD_EXPIRED or LAST_DAY_NOT_STRONG; until v27.168 it tested IS NULL only, so the judge's UNEXPLAINED catch-all, or any unrecognised value, passed it. No column, verdict, seat or move changes. v27.168 (2026-10-03, piece-1 follow-up G1, spec P-16): an incumbent is costed by the question it keeps -- its cost branch follows the kept question's request_basis (HORIZON_PROBE_GOAL: click_goal_day x kept price; any other basis: (w_sp / window_days) x kept price / current bid), not tonight's is_probe, which still decides the move (OPEN_PROBE); v27.164 to v27.167 costed an ordinary seat that turned probe the next night at click_goal_day x its price while its question asked for its window's click rate (2026-10-03: plan B Fresh keyword 388620934464557, $0.1067 a day asked, $1.00 a day costed, 'A RAISE' said at a held price). The P-16 assertion recounts the cost the same way. v27.167 (2026-10-03, piece-1 follow-up F8, spec P-16): when tonight's allowance cannot carry every incumbent, incumbents leave latest-seated first until the rest fit -- walk 1 keeps the longest prefix of the incumbents in seat order (seat_since, tonight's rank breaking a tie) whose running cost fits the ramped allowance, and the first that does not fit leaves with every incumbent seated after it (LEFT_ALLOWANCE_SHRANK), each then a candidate like any other in walk 2 at tonight's price; v27.159 to v27.164 walked the incumbents with the fit test, so an earlier, costlier incumbent could leave while a later, cheaper one kept its seat. The P-16 assertion checks that no incumbent that left was seated before one that kept its seat and that the first to leave did not fit; the TENURE ENDS EARLY sentence states the rule and what the kept incumbents cost. v27.164 (2026-10-03, piece-1 follow-up F2, spec P-16): an incumbent keeps its seat, number, planned price, verdict date and question, and its seat cost is its kept price on TONIGHT's window -- (w_sp / window_days) x kept planned bid / current bid, a probe click_goal_day x its kept price -- charged to the allowance by the incumbents' walk and read by the direction clause, planned_spend_per_day, the campaign need, expected_after_upload_per_day and share_closed; until v27.160 it carried the cost its seat was granted at (30 live incumbent rows of the 2026-10-03 partition printed 'A RAISE', $15.24 a day, while their price was held or cut). The P-16 assertion recounts that cost from the row. v27.160 (2026-10-02, piece-1 plan Task 6, ruling R11 = spec P-24, audit fix #25): a night is keyed on the New York date -- as_of = CURRENT_DATE('America/New_York'), the date V_PLAN_WINDOW_JUDGMENT reads the calendar state on and (from the same version) counts nights and reads the plan's history on; the window fence stays on Los Angeles; partitions written before v27.160 are keyed on the Los Angeles date. R11's guard: before the DELETE, a partition for tonight's date written under a different calendar state is never rewritten (the build raises 'partition <date> was written under <state>; tonight reads <state>; refusing to rewrite'), and every row of a night carries one calendar state (asserted). Fix #25: a shadow (plan A) row whose side differs from the live plan's names the ladder state, plan A's side and rule B's verdict, then plan A's own move, instead of the judgement's rule-B sentence and its P-4 'carries no planned price' clause. The ramp step's upload count reads applied_at on the New York date. v27.159 (2026-10-02, piece-1 plan Task 5, rulings R2/R6/R12/R13/R15 = spec P-16/P-20/P-25/P-26/P-28, audit fix #19): a seat is held until its verdict date while its keyword is still a candidate -- incumbents (last partition's seats written with seat_since, dated after tonight, still candidates, ladder not DEAD) keep their seat, number, price, cost, verdict date and question, are walked first in the order they took their seats, and leave only when tonight's allowance cannot carry them (LEFT_ALLOWANCE_SHRANK); newcomers are walked in rank order into what is left; candidates rank as the judge orders them (P-7 score, then money burned with no return, then clicks); a seated probe is OPEN_PROBE, an unseated probe gets NONE and nothing uploaded, and the queue's words branch on service; clicks_requested spans the settle horizon (window click rate x settle_days, probes click_goal_day x settle_days) with expected_cpc so that clicks x CPC / horizon = implied_daily_spend = the seat's cost; a seat number is the keyword's most recent seat in any earlier partition, the register numbers the live plan only, and the continuity assertion reads that memory; seat_since, seat_tenure and is_probe are written (migration 2026-10-02_plan_seat_tenure_columns.sql). v27.158 (2026-10-02, piece-1 plan Task 4, rulings R1/R7/R8 = spec P-15/P-21/P-22, audit fixes #11 #12 #15 #24): the pot is every GOOD keyword of the family, holdout included (P-15); the ramped allowance is capped at today's not-good spend (P-21); expected_after_upload_per_day (seats + the queue at the price the plan leaves it at) and share_closed (the share of the gap to the allowance target that closes; NULL when the family is at or under its target) are published per family and printed in a FAMILY clause on every row (P-22); a holdout campaign's cap is not moved (NO_MOVE_HOLDOUT, asserted); campaign_budget_basis names what bound the cap (RAMPED only when the cap is the one-third ramp's number to the cent, asserted; FLOORED_AT_NEED, BAND_SNAPPED_UP / BAND_SNAPPED_DOWN, FLOORED_AT_MINIMUM); ramp_step = plan uploads landed since the family's first plan night (BRAIN / PACING / CATALOG batches in V_PPC_CHANGE_LOG_APPLIED or confirmed by an observed change), capped at ramp_steps, published as plan_uploads_landed. The budget floor at need binds only a cap the plan moves. v27.156 (2026-10-02): copies hold_strong_day, hold_kept_by, grace_since and memory_cleared_by_gap from V_PLAN_WINDOW_JUDGMENT (spec P-17, P-18, P-29; the judge reads memory_cleared_by_gap back as a reset); the HELD assertion reads hold_kept_by -- every HELD row names LAST_DAY (with last_day_strong) or STRONG_DAY_IN_WINDOW (with window_from <= hold_strong_day), and no other row names one -- instead of requiring a very good last day on every hold. v27.154 follow-up (2026-10-01): carries strong_day_mult and strong_day_min_orders, the P-14c rule each row was judged under, from V_PLAN_WINDOW_JUDGMENT into the plan table so FN_PLAN_SCORECARD grades every decision against its own rule; a column copy, no assertion changed. v27.147 (2026-09-28): the P-14b assertion checks the judgement is COMPLETE (guard_released_by present on every demotion under the guard's preconditions; every HELD row on the good side with a very good last day, P-14c) instead of re-deriving the guard as a veto -- the v27.136 form refused every partition from 2026-08-29 to 2026-09-28 once the judge's hold clock first expired. Carries hold_since / hold_settles_on / hold_expired, last_day_* and guard_released_by into the plan table. v27.138 (2026-08-24): builds the next-week money plan for the HARVEST families and writes today's partition of FACT_PLAN_NEXT_WEEK, both plans (P-9). Reads V_PLAN_WINDOW_JUDGMENT once. Pot = the GOOD side's window spend per day (P-2); allowance = allowance_share x pot from DE_PLAN_CONFIG, ramped one third of the gap to today's not-good spend each window (P-8); not-good CANDIDATES are ranked by dollars at stake x closeness to the bar (P-7) and walked in rank order, each taking a numbered dollar-sized seat costing its spend at the repaired price (P-6) WHENEVER ITS OWN COST FITS THE ALLOWANCE STILL UNSPENT (spec 4.4 is a fit test, not a prefix stop), the rest queueing at the engine park price, held at a price already at or below it, or paused when the ladder has already closed them; seat numbers come from DE_FAMILY_SEAT_LEDGER and a number the register still holds OPEN is never reissued; one move per candidate, none on the good side (P-4) and none on a not-good keyword with nothing to repair (spec 9); EVERY SEAT carries a verdict date, held or repriced (P-12); every row publishes planned_spend_delta_per_day, so a repair that RAISES a keyword's spend says so in a column; campaign budgets are the sum of planned spend, ramped, floored at the spend the plan itself planned inside the campaign, snapped out of the forbidden $20.01-$31.99 band and floored at $1.00. Every guarantee is ASSERTed on a temp table BEFORE the partition is touched, so a broken build leaves yesterday's plan standing. Writing this table ARMS P-5's one-window grace limit and becomes the P-14b guard's memory, so GRACE is written as GRACE and never collapsed into GOOD. A holdout campaign's money is excluded from the pot, the not-good side and the ramp, and its row carries the counterfactual and no move. A queued row's planned spend is zero by the spec's arithmetic; the row says in words that parking lowers a price and does not stop a spend. Idempotent on one pass, deterministic. Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.8c. Spec 4, 5, 9. SOP: architecture/NEXT_WEEK_MONEY.md 3")
BEGIN
  -- P-24 (Ori 2026-10-02, R11 option (a); v27.160, piece-1 plan Task 6): A NIGHT IS KEYED ON THE
  -- NEW YORK DATE, the date V_PLAN_WINDOW_JUDGMENT reads the calendar state on, so one partition is
  -- one calendar state. Until v27.159 this was the Los Angeles date, and the ~22:35 Los Angeles
  -- pass (already the next New York date) rewrote the Los Angeles day's partition under the next
  -- day's state: the 2026-09-30 partition was written at 22:44 Los Angeles as BOOST, 3-day window,
  -- while FN_PLAN_CALENDAR_STATE('2026-09-30') is OFF_PEAK. Partitions written before v27.160 are
  -- keyed on the Los Angeles date. The window fence stays on Los Angeles (ads days are LA days), so
  -- inside one New York date the window can move forward a day between the 01:35 and 04:10 New York
  -- passes: fresher evidence for the same night, never a different calendar state.
  DECLARE as_of_d DATE DEFAULT CURRENT_DATE('America/New_York');
  DECLARE live_plan_code STRING DEFAULT 'B';
  -- R11's guard (P-24, v27.160): the calendar state tonight's rows carry, and the one an existing
  -- partition for as_of_d was written under (NULL when there is none)
  DECLARE tonight_state STRING;
  DECLARE written_state STRING;

  -- The ramp STEP is a report on how long this family has been planned for. Read BEFORE the
  -- delete, so the INSERT never reads the table it is writing.
  CREATE OR REPLACE TEMP TABLE first_seen AS
  SELECT family, MIN(as_of) AS first_as_of
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of < as_of_d
  GROUP BY 1;

  -- ONE scan of the judgement view; everything below reads this copy.
  CREATE OR REPLACE TEMP TABLE j AS
  SELECT * FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;

  -- Which plan is live comes from the judgement view's own DE_PLAN_CONFIG read, so the builder and
  -- the judge can never disagree about it (one source, not two).
  SET live_plan_code = COALESCE((SELECT MAX(live_plan) FROM j), 'B');

  -- THE RAMP STEP COUNTS UPLOADS THAT LANDED, NOT WINDOWS ON THE CALENDAR (v27.158, audit fix #15).
  -- Until v27.157 ramp_step was 1 + the windows elapsed since the family's first plan night, so it
  -- read 3 of 3 on every live row from 2026-09-28 although no plan batch had reached Amazon since
  -- the books of 2026-08-25 (PENDING_UPLOAD / SUPERSEDED_NEVER_UPLOADED). A plan batch is a
  -- batch_id of the plan's own book tiers (source BRAIN:*, PACING:*, CATALOG:*); it LANDED when one
  -- of its rows is in V_PPC_CHANGE_LOG_APPLIED (the one definition of an applied status) or an
  -- observed change on Amazon names one of its rows ('CONFIRMS <change_id>', the pairing
  -- V_PPC_CHANGE_LOG_LANDED reads). It counts for a family when it touched a campaign of the
  -- family's plan universe, on or after the family's first plan night, read on the clock as_of is
  -- keyed on (the New York date since v27.160, P-24; the Los Angeles date before). Nothing in the
  -- money reads it; ramp_step = LEAST(ramp_steps, this count).
  CREATE OR REPLACE TEMP TABLE uploads AS
  WITH fam_campaign AS (
    SELECT DISTINCT family, CAST(campaign_id AS STRING) AS campaign_id FROM j),
  plan_rows AS (
    SELECT change_id, batch_id, CAST(campaign_id AS STRING) AS campaign_id,
           DATE(applied_at, 'America/New_York') AS logged_on
    FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
    WHERE STARTS_WITH(source, 'BRAIN:') OR STARTS_WITH(source, 'PACING:')
       OR STARTS_WITH(source, 'CATALOG:')),
  confirmed AS (
    SELECT DISTINCT REGEXP_EXTRACT(upload_note, r'^CONFIRMS (\S+)') AS change_id
    FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
    WHERE source = 'OBSERVED' AND upload_status = 'OBSERVED_ON_AMAZON'),
  landed AS (
    SELECT p.* FROM plan_rows p
    WHERE p.change_id IN (SELECT change_id FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`)
       OR p.change_id IN (SELECT change_id FROM confirmed WHERE change_id IS NOT NULL))
  SELECT fc.family, COUNT(DISTINCT l.batch_id) AS plan_uploads_landed
  FROM fam_campaign fc
  LEFT JOIN first_seen fs ON fs.family = fc.family
  LEFT JOIN landed l ON l.campaign_id = fc.campaign_id
                    AND l.logged_on >= COALESCE(fs.first_as_of, as_of_d)
  GROUP BY 1;

  -- Both plans over the same keywords: 'B' takes rule B's side, 'A' takes the ladder's (P-9).
  -- Candidacy is the view's own expression with the PLAN's side substituted, so for plan B it is
  -- the view's is_candidate exactly (C13 asserts it).
  CREATE OR REPLACE TEMP TABLE r AS
  SELECT j.*,
         pl AS plan,
         IF(pl = 'B', j.side_b, j.side_a) AS side,
         (IF(pl = 'B', j.side_b, j.side_a) = 'NOT_GOOD'
          AND NOT j.holdout
          AND (j.verdict != 'NOT_SERVING' OR j.is_probe))                       AS is_cand,
         -- reading (c): the shadow wants to price a row the live plan protects under P-4
         (pl = 'A' AND j.side_a = 'NOT_GOOD' AND j.side_b = 'GOOD')             AS shadow_unpriced
  FROM j, UNNEST(['A', 'B']) AS pl;

  CREATE OR REPLACE TEMP TABLE r2 AS
  SELECT r.*,
    CASE WHEN r.side = 'GOOD'     THEN NULL              -- P-4: no price on the good side
         WHEN r.shadow_unpriced   THEN r.current_bid     -- reading (c)
         ELSE r.planned_bid END                                     AS plan_bid,
    CASE WHEN r.side = 'GOOD'     THEN NULL              -- P-4: no seat cost on the good side
         WHEN r.shadow_unpriced   THEN COALESCE(SAFE_DIVIDE(r.w_sp, r.window_days), 0)
         ELSE COALESCE(r.seat_cost_per_day, 0) END                   AS plan_seat_cost
  FROM r;

  -- 1-3. Pot, allowance, ramp — per plan x family.
  -- P-15 (Ori 2026-10-02, R1 option (a); v27.158): the POT is every GOOD keyword of the family,
  -- holdout included — P-2's own words ("what the family's GOOD keywords actually spent"). The
  -- holdout's good keywords receive no instruction, but they size the allowance, so the treated
  -- arm's allowance is no longer set by the draw. The NOT-GOOD base keeps excluding the holdout:
  -- a control's losers are not the plan's to ration, and every move still excludes it.
  CREATE OR REPLACE TEMP TABLE fam AS
  SELECT plan, family,
         MAX(window_days)     AS window_days,
         MAX(allowance_share) AS allowance_share,
         MAX(ramp_steps)      AS ramp_steps,
         COALESCE(SAFE_DIVIDE(SUM(IF(side = 'GOOD', w_sp, 0)), MAX(window_days)), 0)                 AS pot_per_day,
         COALESCE(SAFE_DIVIDE(SUM(IF(side = 'NOT_GOOD' AND NOT holdout, w_sp, 0)), MAX(window_days)), 0) AS notgood_today_per_day
  FROM r2
  GROUP BY 1, 2;

  CREATE OR REPLACE TEMP TABLE fam2 AS
  SELECT f.*,
         f.allowance_share * f.pot_per_day AS allowance_target_per_day,
         -- THE RAMP NEVER RAISES A FAMILY'S LOSER SPEND (P-21, Ori 2026-10-02, R7 option (a);
         -- v27.158). The ramp term alone closes one third of the gap between today's not-good
         -- spend and the allowance target, in whichever direction the gap runs; the GREATEST
         -- removes the downward half of that for a family already inside its target, which until
         -- v27.157 HANDED IT THE WHOLE TARGET ON NIGHT ONE — a bigger loss budget than it spends
         -- (audit 2026-10-02: Lollibox on 09-30, $3.43 a day above its not-good spend; 13 of 24
         -- August family-nights). The LEAST caps the result at tonight's not-good spend: a family
         -- inside its target is allowed what it spends now, and nothing more.
         LEAST(f.notgood_today_per_day,
               GREATEST(f.allowance_share * f.pot_per_day,
                        f.notgood_today_per_day
                        - (f.notgood_today_per_day - f.allowance_share * f.pot_per_day) / f.ramp_steps))
           AS allowance_ramped_per_day
  FROM fam f;

  -- THE PLAN'S OWN HISTORY, READ BEFORE THE WALK (v27.159, piece-1 plan Task 5). Both reads stop
  -- strictly before tonight's as_of — never tonight's own earlier write, which this pass replaces —
  -- so every pass of one night derives the same incumbents and the same claims from the same rows.
  -- P-16 (Ori 2026-10-02, R2 option (a)): A SEAT IS HELD UNTIL ITS VERDICT DATE. prior_seat holds
  -- last partition's seats whose verdict date is still ahead: their contract — number, planned
  -- price, verdict date, the night they were taken and the question they were given — is what
  -- an incumbent keeps. Not the cost it was seated at (v27.164, follow-up F2): that was the window of
  -- the seating night at the kept price, and the incumbent is costed on tonight's (`ranked`).
  -- THE CUTOVER: only a seat written WITH seat_since (every seat this builder
  -- writes from v27.159) is a contract. A seat written before it was priced before P-19 / P-25 and
  -- asked before P-26: of the 28 live seats of the 2026-10-01 partition that were still candidates
  -- on the 2026-10-02 judgement (snapshot OI._tmp_t5_judge), 11 carried a price above their current
  -- bid on a keyword whose corrected return was under the bar (P-19 forbids that raise), and no plan
  -- batch has landed since 2026-08-25, so no such contract was in force on Amazon (query: SOP §3,
  -- "Tenure, probes, the question and the numbers").
  CREATE OR REPLACE TEMP TABLE prior_seat AS
  SELECT plan, family, CAST(campaign_id AS STRING) AS campaign_id,
         CAST(keyword_id AS STRING) AS keyword_id,
         seat_no AS held_seat_no, planned_bid AS held_bid,
         verdict_date AS held_verdict_date, seat_since AS held_since,
         clicks_requested AS held_clicks, clicks_due_date AS held_due, expected_cpc AS held_cpc,
         implied_daily_spend AS held_implied, request_basis AS held_basis
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of < as_of_d)
    AND seat_no IS NOT NULL
    AND seat_since IS NOT NULL
    AND verdict_date > as_of_d;

  -- P-28 (Ori 2026-10-02, R15 option (a)): THE BUILDER'S MEMORY OF A NUMBER IS THE KEYWORD'S MOST
  -- RECENT SEAT IN ANY EARLIER PARTITION, not only last night's, so a one-night absence does not
  -- reissue it. claim_as_of says how recent the claim is: when two keywords seated tonight claim one
  -- number, the more recent claim keeps it.
  CREATE OR REPLACE TEMP TABLE claims AS
  SELECT plan, family, CAST(campaign_id AS STRING) AS campaign_id,
         CAST(keyword_id AS STRING) AS keyword_id, seat_no AS claim_no, as_of AS claim_as_of
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of < as_of_d AND seat_no IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY plan, family, CAST(campaign_id AS STRING),
                                          CAST(keyword_id AS STRING)
                             ORDER BY as_of DESC) = 1;

  -- 4. Rank the candidates (P-7, P-20). The ordering reaches the keyword key, so the walk below is
  -- deterministic on any re-run.
  -- P-20 (Ori 2026-10-02, R6 option (b); v27.159 — the judge's half shipped in v27.157): the
  -- builder ranks EXACTLY as the judgement view orders: P-7's score for every candidate it scores
  -- above zero, then every candidate with no positive score by money burned with no return, and
  -- clicks only after that (GREATEST(rank_score, 0): a candidate that sold at a loss ranks with the
  -- zeros, not below them). Until v27.158 this CTE ordered the zeros by clicks.
  -- A KEYWORD THE LADDER HAS CLOSED IS NOT SEATABLE (v27.138). It still gets a rank and a queue
  -- position — every candidate has exactly one of a seat or a queue position (§9) — but it can
  -- never take a seat, hold family allowance or be published with a price. v27.137 tested DEAD
  -- only AFTER the two seat branches of the move CASE, so whether a closed keyword was stopped or
  -- re-priced was decided by whether its cost happened to fit: on the first partition ten closed
  -- keywords took seats and were published with an executable bid while a single closed keyword
  -- that did not fit was told "a closed keyword is stopped, not re-priced". Two opposite
  -- instructions from one ladder state in one partition. Deciding it here rather than only in the
  -- move CASE is what makes it true of the MONEY as well as of the words: a closed keyword no
  -- longer consumes allowance a repairable keyword could have used.
  -- An INCUMBENT (P-16) is a candidate tonight whose contract is in prior_seat and whose ladder
  -- state is not DEAD: it is still a candidate (not GOOD, not holdout — is_cand), before its date.
  -- AN INCUMBENT COSTS ITS KEPT PRICE ON TONIGHT'S WINDOW (v27.164, piece-1 follow-up F2). inc_cost:
  -- an incumbent whose KEPT QUESTION is a probe's (held_basis 'HORIZON_PROBE_GOAL', the basis
  -- `questioned` writes on a probe's seat) funds click_goal_day clicks a day at its kept price (P-25's
  -- costing of a probe opened at a LIFT price); any other incumbent spends its window spend per day
  -- scaled by kept price / current bid (P-6); one with no spend or no current bid costs 0, as in the
  -- judge's non-probe branch. v27.168 (follow-up G1): the branch follows the question the incumbent
  -- keeps (P-16), not tonight's is_probe, which v27.164 .. v27.167 read — so an ordinary seat that
  -- turned probe the next night was costed click_goal_day x its price while its question asked for its
  -- window's click rate (plan B Fresh 388620934464557 on 2026-10-03: $1.00 a day costed, $0.1067
  -- asked; SOP §3, "An incumbent is costed by the question it keeps"). Tonight's is_probe still
  -- decides the move (OPEN_PROBE). The judge costs a probe WITHOUT a LIFT price
  -- differently (by its window when it spent, else at its seat CPC); an incumbent probe's price is the
  -- one it opened at, so it is costed at that. The kept price is the planned bid the seat was written
  -- with (prior_seat.held_bid). Until v27.160 the incumbent carried the cost its seat was granted
  -- at — the window of the seating night — so a seat whose price was held or cut tonight could still
  -- print "A RAISE" and hold that stale money in the allowance (30 live rows, $15.24 a day, on the
  -- 2026-10-03 partition built 08:12 UTC).
  CREATE OR REPLACE TEMP TABLE ranked AS
  SELECT r2.plan, r2.family, r2.campaign_id, r2.keyword_id,
         ROW_NUMBER() OVER w AS rank_no,
         COALESCE(r2.plan_seat_cost, 0) AS cost,
         (r2.ladder_state = 'DEAD') AS is_closed,
         (ps.keyword_id IS NOT NULL AND COALESCE(r2.ladder_state, '') != 'DEAD') AS is_incumbent,
         ps.held_since,
         IF(ps.keyword_id IS NULL, NULL,
            COALESCE(CASE WHEN ps.held_basis = 'HORIZON_PROBE_GOAL'
                            THEN r2.click_goal_day * ps.held_bid
                          WHEN r2.w_sp > 0 AND COALESCE(r2.current_bid, 0) > 0
                            THEN (r2.w_sp / r2.window_days) * SAFE_DIVIDE(ps.held_bid, r2.current_bid)
                          ELSE 0 END, 0)) AS inc_cost
  FROM r2
  LEFT JOIN prior_seat ps ON ps.plan = r2.plan AND ps.family = r2.family
                         AND ps.campaign_id = r2.campaign_id AND ps.keyword_id = r2.keyword_id
  WHERE r2.is_cand
  WINDOW w AS (PARTITION BY r2.plan, r2.family
               ORDER BY GREATEST(r2.rank_score, 0) DESC, r2.rank_money_burned DESC, r2.w_clk DESC,
                        r2.campaign_id, r2.keyword_id);

  -- THE WALK IS A FIT TEST, NOT A PREFIX STOP (spec §4.4, repaired v27.137). "A candidate takes
  -- the lowest free seat WHILE ITS COST FITS THE REMAINING ALLOWANCE" is per candidate: one lumpy
  -- candidate must not close the queue behind it. v27.136 filtered on a running prefix sum
  -- (cum_cost <= allowance), which halted each family's seating at the first candidate that did
  -- not fit and parked every cheaper candidate below it — cutting harder than P-8's ramp intends,
  -- on exactly the lumpy distributions P-8 exists for, and leaving a large part of the ramped
  -- allowance unassigned. Measured on the deployed v27.136 partition before this repair: three
  -- plan x family walks left a queued candidate that fitted the allowance they had not spent
  -- (acceptance C18, red before and green after).
  -- Skip-and-continue is exactly as deterministic as a prefix: the ranking is a total order down
  -- to the keyword key, and the recursion follows it one rank at a time. The invariant it leaves
  -- behind is checkable — every queued candidate costs more than the allowance the family ends
  -- with, because the remaining allowance only ever falls as the walk proceeds.
  -- P-16 (v27.159): TWO WALKS, INCUMBENTS FIRST. Walk 1 takes the incumbents in the order they took
  -- their seats (seat_since, earliest first; tonight's rank breaks a tie), each costing its kept
  -- price on tonight's window (inc_cost, v27.164; until v27.160 the cost its contract carried).
  -- When tonight's allowance can carry them all, all keep their seats. When it cannot (it shrank),
  -- INCUMBENTS LEAVE LATEST-SEATED FIRST UNTIL THE REST FIT (R2's words; v27.167, follow-up F8):
  -- walk 1 is a PREFIX, not a fit test — it keeps incumbents while the running total fits, and the
  -- first one that does not fit leaves together with every incumbent seated after it, however cheap.
  -- No inc_cost is negative (each branch multiplies a bid, a click goal or a window spend), so the
  -- running total only grows along the order and the prefix is exactly what dropping the latest
  -- seated one at a time until the rest fit leaves. Seniority is the contract P-16 protects, so the
  -- fit test that keeps the newcomers' queue open (the v27.136 defect above) is the wrong walk here:
  -- v27.159 .. v27.164 used it, so an earlier, costlier incumbent could leave while a later, cheaper
  -- one kept its seat (19 kept seats of that kind on the doctored copy in the header). Walk 2 is the
  -- v27.137 walk over every other candidate — newcomers, and every
  -- incumbent walk 1 sent out, at TONIGHT's price — in rank order, starting from what walk 1 spent.
  -- Remaining allowance still only falls, so C18's invariant holds across both walks.
  CREATE OR REPLACE TEMP TABLE inc_order AS
  SELECT plan, family, campaign_id, keyword_id, rank_no, inc_cost AS cost,
         ROW_NUMBER() OVER (PARTITION BY plan, family
                            ORDER BY held_since, rank_no, campaign_id, keyword_id) AS inc_no
  FROM ranked
  WHERE is_incumbent;

  CREATE OR REPLACE TEMP TABLE walk_inc AS
  WITH RECURSIVE w AS (
    SELECT k.plan, k.family, k.campaign_id, k.keyword_id, k.rank_no, k.inc_no, k.cost,
           f.allowance_ramped_per_day AS allow,
           (k.cost <= f.allowance_ramped_per_day + 0.0001) AS took,
           IF(k.cost <= f.allowance_ramped_per_day + 0.0001, k.cost, 0.0) AS spent
    FROM inc_order k
    JOIN fam2 f ON f.plan = k.plan AND f.family = k.family
    WHERE k.inc_no = 1
    UNION ALL
    -- v27.167 (F8): a prefix — once one incumbent has not fitted (w.took false), nobody seated
    -- after it takes a seat in this walk
    SELECT k.plan, k.family, k.campaign_id, k.keyword_id, k.rank_no, k.inc_no, k.cost,
           w.allow,
           (w.took AND w.spent + k.cost <= w.allow + 0.0001),
           w.spent + IF(w.took AND w.spent + k.cost <= w.allow + 0.0001, k.cost, 0.0)
    FROM w
    JOIN inc_order k ON k.plan = w.plan AND k.family = w.family AND k.inc_no = w.inc_no + 1
  )
  SELECT * FROM w;

  -- what walk 1 spent, and how many incumbents it kept, per plan x family (0 where nobody was an
  -- incumbent); the TENURE ENDS EARLY sentence prints both (v27.167)
  CREATE OR REPLACE TEMP TABLE inc_spent AS
  SELECT f.plan, f.family, COALESCE(SUM(IF(w.took, w.cost, 0)), 0) AS spent,
         COUNTIF(COALESCE(w.took, FALSE)) AS n_kept
  FROM fam2 f
  LEFT JOIN walk_inc w ON w.plan = f.plan AND w.family = f.family
  GROUP BY 1, 2;

  CREATE OR REPLACE TEMP TABLE new_order AS
  SELECT k.plan, k.family, k.campaign_id, k.keyword_id, k.rank_no, k.cost, k.is_closed,
         ROW_NUMBER() OVER (PARTITION BY k.plan, k.family ORDER BY k.rank_no) AS new_no
  FROM ranked k
  LEFT JOIN walk_inc i ON i.plan = k.plan AND i.family = k.family
                      AND i.campaign_id = k.campaign_id AND i.keyword_id = k.keyword_id AND i.took
  WHERE i.keyword_id IS NULL;

  CREATE OR REPLACE TEMP TABLE walk AS
  WITH RECURSIVE w AS (
    SELECT k.plan, k.family, k.campaign_id, k.keyword_id, k.rank_no, k.new_no, k.cost,
           f.allowance_ramped_per_day AS allow,
           (NOT k.is_closed AND s.spent + k.cost <= f.allowance_ramped_per_day + 0.0001) AS took,
           s.spent + IF(NOT k.is_closed AND s.spent + k.cost <= f.allowance_ramped_per_day + 0.0001,
                        k.cost, 0.0) AS spent
    FROM new_order k
    JOIN fam2 f ON f.plan = k.plan AND f.family = k.family
    JOIN inc_spent s ON s.plan = k.plan AND s.family = k.family
    WHERE k.new_no = 1
    UNION ALL
    SELECT k.plan, k.family, k.campaign_id, k.keyword_id, k.rank_no, k.new_no, k.cost,
           w.allow,
           (NOT k.is_closed AND w.spent + k.cost <= w.allow + 0.0001),
           w.spent + IF(NOT k.is_closed AND w.spent + k.cost <= w.allow + 0.0001, k.cost, 0.0)
    FROM w
    JOIN new_order k ON k.plan = w.plan AND k.family = w.family AND k.new_no = w.new_no + 1
  )
  SELECT * FROM w;

  -- every seat tonight, and its tenure: an incumbent walk 1 kept, or a seat walk 2 granted
  CREATE OR REPLACE TEMP TABLE seated0 AS
  SELECT plan, family, campaign_id, keyword_id, rank_no, 'INCUMBENT' AS seat_tenure
  FROM walk_inc WHERE took
  UNION ALL
  SELECT plan, family, campaign_id, keyword_id, rank_no, 'NEW' AS seat_tenure
  FROM walk WHERE took;

  -- the family's currently open seats — a continuing occupant keeps its number
  CREATE OR REPLACE TEMP TABLE led AS
  SELECT family, CAST(campaign_id AS STRING) AS campaign_id, CAST(keyword_id AS STRING) AS keyword_id,
         MIN(seat_no) AS led_seat_no
  FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
  WHERE closed_on IS NULL
  GROUP BY 1, 2, 3;

  -- THE PLAN'S OWN HISTORY IS THE SECOND SOURCE OF CONTINUITY (v27.138). §9 promises "seat
  -- numbers stable across days for continuing occupants", and the ledger alone cannot deliver it:
  -- SP_MAINTAIN_FAMILY_SEATS admits only the live plan's seats a pass later, so a keyword the PLAN
  -- seats has no open ledger row on the night it is seated, and, on v27.137, was handed a fresh
  -- number every night from an index into THAT NIGHT'S rank order. C05 checks uniqueness inside one
  -- partition and C17 checks non-collision with the register; C23 and T2 check continuity.
  -- The precedence is register > the plan's own most recent claim (claims, P-28) > lowest free
  -- number. The register still wins, because it is the authority Ori's vocabulary comes from; a
  -- claim only fills the gap the register leaves, and only with a number the register is not
  -- holding open for anyone else.
  -- THE REGISTER IS THE LIVE PLAN'S (v27.159). DE_FAMILY_SEAT_LEDGER admits plan B's seats only
  -- (SP_MAINTAIN_FAMILY_SEATS reads plan A for agreement_tier, never for numbers), so the shadow
  -- plan numbers its own seats from its own claims and ignores the register. Until v27.158 the
  -- register's precedence applied to plan A too: a plan-A seat was renumbered whenever plan B's
  -- register admitted the same keyword under plan B's number or held plan A's old number for
  -- another keyword, and when the register let go of that old number before a later pass of the
  -- same night, the continuity assertion refused the whole partition. Replayed with the ledger as of
  -- each refused pass (BigQuery time travel; 2026-09-29 16:53, 09-30 05:36, 10-01 16:58 and 10-02
  -- 05:34 UTC) against the partition the same night's first pass wrote: every refusal names plan-A
  -- seats renumbered by the register (09-29: Fresh 340057616788625 16 -> 5, LolliME
  -- 123153583900193 7 -> 6 and 546572942561610 13 -> 18; 10-01: LolliME 23713700698206 24 -> 30),
  -- and the 10-01 refusals also two plan-B seats (LolliME 485639729786108 24 -> 18,
  -- 359460728874259 28 -> 20) the register had admitted under fallback numbers because its REOPEN
  -- step re-opened two other keywords at their old numbers (fixed in SP_MAINTAIN_FAMILY_SEATS
  -- v27.159). Query: SOP §3, "Seat numbers".
  CREATE OR REPLACE TEMP TABLE seated AS
  WITH c AS (
    SELECT s.plan, s.family, s.campaign_id, s.keyword_id, s.rank_no, s.seat_tenure,
           IF(s.plan = live_plan_code, l.led_seat_no, NULL) AS led_seat_no,
           -- a claim is honoured on the live plan only if the register is not holding that number
           -- open for someone (when it holds it for this keyword, led_seat_no already carries it)
           IF(cl.claim_no IS NOT NULL
              AND (s.plan != live_plan_code
                   OR NOT EXISTS (SELECT 1 FROM led l2
                                  WHERE l2.family = s.family AND l2.led_seat_no = cl.claim_no)),
              cl.claim_no, NULL) AS claim_no,
           cl.claim_as_of
    FROM seated0 s
    LEFT JOIN led l    ON l.family = s.family AND l.campaign_id = s.campaign_id
                      AND l.keyword_id = s.keyword_id
    LEFT JOIN claims cl ON cl.plan = s.plan AND cl.family = s.family
                       AND cl.campaign_id = s.campaign_id AND cl.keyword_id = s.keyword_id)
  SELECT plan, family, campaign_id, keyword_id, rank_no, seat_tenure, led_seat_no,
         -- a number is honoured ONCE per plan x family: the REGISTER's claimant keeps it, then the
         -- MOST RECENT claim (P-28: the keyword that held it latest), then the better rank; the
         -- other is treated as a new occupant, so "numbered exactly once" cannot be broken by an
         -- inconsistency in either source
         IF(ROW_NUMBER() OVER (PARTITION BY plan, family, COALESCE(led_seat_no, claim_no)
                               ORDER BY (led_seat_no IS NULL), claim_as_of DESC, rank_no,
                                        campaign_id, keyword_id) = 1,
            COALESCE(led_seat_no, claim_no), NULL) AS kept_seat_no
  FROM c;

  -- the free seat numbers, lowest first, and the new occupants that take them in rank order
  -- SEAT NUMBERS ARE THE REGISTER'S, NOT THE PLAN'S (§9, repaired v27.137). A number is FREE only
  -- when the ledger has freed it — closed_on IS NULL means occupied, whether or not tonight's plan
  -- seats that occupant. v27.136 built the occupied set from the keywords THIS RUN seated, so any
  -- open ledger seat whose occupant the plan did not seat tonight read as free and was handed to a
  -- new occupant, splitting the register into two disagreeing authorities. Measured on the
  -- deployed v27.136 partition before this repair: acceptance C17, red before and green after.
  -- The pool is widened to n_seated + the family's highest number in use, which always leaves at
  -- least n_seated free numbers however many the register is holding. v27.159: the register's
  -- numbers are held for the live plan only (the shadow plan's numbers are its own).
  CREATE OR REPLACE TEMP TABLE seat_no_map AS
  WITH cnt AS (
    SELECT plan, family, COUNT(*) AS n_seated FROM seated GROUP BY 1, 2),
  ledmax AS (
    SELECT family, MAX(led_seat_no) AS max_led FROM led GROUP BY 1),
  keptmax AS (
    SELECT plan, family, MAX(kept_seat_no) AS max_kept FROM seated GROUP BY 1, 2),
  nums AS (
    SELECT c.plan, c.family, x AS seat_no
    FROM cnt c
    LEFT JOIN ledmax lm ON lm.family = c.family
    LEFT JOIN keptmax km ON km.plan = c.plan AND km.family = c.family,
    UNNEST(GENERATE_ARRAY(
      1, c.n_seated + GREATEST(IF(c.plan = live_plan_code, COALESCE(lm.max_led, 0), 0),
                               COALESCE(km.max_kept, 0)))) AS x),
  -- occupied = every number the REGISTER still holds open for this family (live plan), plus every
  -- number a continuing occupant kept tonight. Both must be excluded or a new occupant takes a
  -- number that is already somebody's.
  taken AS (
    SELECT c.plan, c.family, l.led_seat_no AS seat_no
    FROM cnt c JOIN led l ON l.family = c.family
    WHERE c.plan = live_plan_code
    UNION DISTINCT
    SELECT plan, family, kept_seat_no FROM seated WHERE kept_seat_no IS NOT NULL),
  free AS (
    SELECT n.plan, n.family, n.seat_no,
           ROW_NUMBER() OVER (PARTITION BY n.plan, n.family ORDER BY n.seat_no) AS free_ix
    FROM nums n
    LEFT JOIN taken t ON t.plan = n.plan AND t.family = n.family AND t.seat_no = n.seat_no
    WHERE t.seat_no IS NULL),
  fresh AS (
    SELECT plan, family, campaign_id, keyword_id,
           ROW_NUMBER() OVER (PARTITION BY plan, family ORDER BY rank_no) AS new_ix
    FROM seated WHERE kept_seat_no IS NULL)
  SELECT s.plan, s.family, s.campaign_id, s.keyword_id, s.seat_tenure,
         COALESCE(s.kept_seat_no, fr.seat_no) AS seat_no,
         CASE WHEN s.led_seat_no IS NOT NULL  THEN 'REGISTER'
              WHEN s.kept_seat_no IS NOT NULL THEN 'PLAN_CONTINUITY'
              ELSE 'NEW_LOWEST_FREE' END AS seat_no_source
  FROM seated s
  LEFT JOIN fresh n ON n.plan = s.plan AND n.family = s.family
                   AND n.campaign_id = s.campaign_id AND n.keyword_id = s.keyword_id
  LEFT JOIN free fr ON fr.plan = s.plan AND fr.family = s.family AND fr.free_ix = n.new_ix;

  -- 5-6. Assemble every row: side, seat or queue, move, planned price, planned spend, verdict date
  -- P-16 (v27.159): AN INCUMBENT KEEPS ITS CONTRACT. Its plan_bid is the one its seat was granted at
  -- (prior_seat), not tonight's — settle discipline at the new price means the price does not move
  -- before the verdict date. Its plan_seat_cost is that kept price on TONIGHT's window (inc_cost,
  -- v27.164, follow-up F2; until v27.160 the cost the seat was granted at). Tonight's own price and
  -- cost stay on the row as tonight_bid / tonight_cost for the sentence. Every other row keeps
  -- tonight's.
  -- seat_tenure: INCUMBENT | NEW on a seat; LEFT_ALLOWANCE_SHRANK on an incumbent walk 1 sent out
  -- (the first that did not fit, and every one seated after it; v27.167) and walk 2 did not
  -- re-seat; NULL otherwise.
  CREATE OR REPLACE TEMP TABLE assembled0 AS
  SELECT
    r2.* REPLACE (
      IF(m.seat_tenure = 'INCUMBENT', ps.held_bid,  r2.plan_bid)       AS plan_bid,
      IF(m.seat_tenure = 'INCUMBENT', k.inc_cost,   r2.plan_seat_cost) AS plan_seat_cost),
    r2.plan_bid AS tonight_bid, r2.plan_seat_cost AS tonight_cost,
    f.pot_per_day, f.allowance_target_per_day, f.allowance_ramped_per_day,
    f.notgood_today_per_day, f.ramp_steps AS fam_ramp_steps,
    k.rank_no,
    m.seat_no,
    CASE WHEN m.seat_no IS NOT NULL THEN m.seat_tenure
         WHEN k.is_incumbent        THEN 'LEFT_ALLOWANCE_SHRANK'
    END AS seat_tenure,
    ps.held_seat_no, ps.held_since, ps.held_verdict_date, ps.held_clicks, ps.held_due,
    ps.held_cpc, ps.held_implied, ps.held_basis,
    -- v27.167 (F8): the incumbents walk 1 kept, for the TENURE ENDS EARLY sentence
    s.n_kept AS inc_kept_n, s.spent AS inc_kept_per_day
  FROM r2
  JOIN fam2 f USING (plan, family)
  LEFT JOIN inc_spent s ON s.plan = r2.plan AND s.family = r2.family
  LEFT JOIN ranked k ON k.plan = r2.plan AND k.family = r2.family
                    AND k.campaign_id = r2.campaign_id AND k.keyword_id = r2.keyword_id
  LEFT JOIN seat_no_map m ON m.plan = r2.plan AND m.family = r2.family
                         AND m.campaign_id = r2.campaign_id AND m.keyword_id = r2.keyword_id
  LEFT JOIN prior_seat ps ON ps.plan = r2.plan AND ps.family = r2.family
                         AND ps.campaign_id = r2.campaign_id AND ps.keyword_id = r2.keyword_id;

  CREATE OR REPLACE TEMP TABLE assembled AS
  SELECT
    a.*,
    CASE
      WHEN a.side = 'GOOD'                                              THEN 'NONE'
      WHEN a.holdout                                                    THEN 'NONE_HOLDOUT'
      WHEN NOT a.is_cand                                                THEN 'NONE'
      -- §4.5: "parked at the channel park price OR PAUSED IF ALREADY CLOSED". Closed is the
      -- ladder's own DEAD state, not "the park price is not below the current bid" — v27.136 read
      -- the second and paused serving keywords on their FIRST window in the queue, against §4.5's
      -- own kill ladder (bid to the floor, probation, then kill).
      -- CLOSED IS TESTED BEFORE THE SEAT (v27.138), not merely before parking. "The stronger of
      -- the two instructions, not the fallback" was written of parking in v27.137 and then placed
      -- BELOW both seat branches, so on the first partition ten closed keywords were seated and
      -- re-priced while one was stopped — the difference being only whether the cost fitted. The
      -- walk above already refuses them a seat, so this branch can never be shadowed again.
      WHEN a.ladder_state = 'DEAD'                                      THEN 'PAUSE'
      -- P-25 (Ori 2026-10-02, R12 option (a); audit fix #19; v27.159): a probe that wins a seat
      -- OPENS at the price the judge set (LIFT's PROBE_START bid, capped; or P-6's where LIFT
      -- holds none) — its own move, not a REPRICE of a keyword that bought nothing.
      WHEN a.seat_no IS NOT NULL AND a.is_probe                         THEN 'OPEN_PROBE'
      WHEN a.seat_no IS NOT NULL
           AND ABS(COALESCE(a.plan_bid, a.current_bid, 0) - COALESCE(a.current_bid, 0)) > 0.005
                                                                        THEN 'REPRICE'
      WHEN a.seat_no IS NOT NULL                                        THEN 'HOLD_AT_PRICE'
      -- P-25: AN UNSEATED PROBE GETS NO MOVE — "probe not opened tonight; nothing uploaded". Until
      -- v27.158 it was parked: 27 PARK uploads $0.25 -> $0.20 over 2026-09-28 .. 10-01 on keywords
      -- that bought no clicks (audit fix #19), a cut on a keyword that spends nothing.
      WHEN a.is_probe                                                   THEN 'NONE'
      WHEN COALESCE(a.bid_park, a.bid_floor, 0) < COALESCE(a.current_bid, 0) - 0.005 THEN 'PARK'
      -- a queued keyword already at or below its park price has nothing to upload: it holds its
      -- queue position at the price it has, and the probation clock decides when it dies.
      ELSE 'HOLD_AT_PARK'
    END AS move
  FROM assembled0 a;

  CREATE OR REPLACE TEMP TABLE priced AS
  SELECT a.*,
    CASE a.move
      WHEN 'REPRICE'       THEN ROUND(a.plan_bid, 2)
      WHEN 'OPEN_PROBE'    THEN ROUND(a.plan_bid, 2)
      WHEN 'HOLD_AT_PRICE' THEN a.current_bid
      WHEN 'PARK'          THEN ROUND(COALESCE(a.bid_park, a.bid_floor, a.current_bid), 2)
      WHEN 'HOLD_AT_PARK'  THEN a.current_bid
      -- a paused row carries NO price: pause is a state change, and publishing a bid beside it
      -- invites a book generator to upload one on a keyword the plan says to stop. An unseated
      -- probe carries none either: nothing is uploaded (P-25).
      ELSE NULL
    END AS planned_bid_final,
    CASE
      WHEN a.side = 'GOOD' OR a.holdout OR NOT a.is_cand
                                        THEN COALESCE(SAFE_DIVIDE(a.w_sp, a.window_days), 0)
      WHEN a.seat_no IS NOT NULL        THEN a.plan_seat_cost
      ELSE 0
    END AS planned_spend_per_day,
    -- P-12 IS ABOUT SEATS, NOT ABOUT REPRICES (repaired v27.137). "Every seat carries a verdict
    -- date: graduate, step again, or give the seat up" — and it exists to stop the queue becoming
    -- a parking lot. A seat HELD AT ITS CURRENT PRICE is precisely the parking-lot case: it holds
    -- allowance and uploads nothing. v27.136 dated only the REPRICE rows and the acceptance froze
    -- that narrowing into a check; both are corrected, and the departure is on the list Ori reads.
    -- P-16 (v27.159): the date is stamped ONCE, the night the seat is taken, and an incumbent keeps
    -- it. Until v27.158 every seat was re-stamped as_of + settle_days every night, so no seat ever
    -- reached the date its sentence printed.
    CASE WHEN a.seat_no IS NULL               THEN NULL
         WHEN a.seat_tenure = 'INCUMBENT'     THEN a.held_verdict_date
         ELSE DATE_ADD(as_of_d, INTERVAL a.settle_days DAY) END AS verdict_date,
    CASE WHEN a.seat_no IS NULL               THEN NULL
         WHEN a.seat_tenure = 'INCUMBENT'     THEN a.held_since
         ELSE as_of_d END AS seat_since
  FROM assembled a;

  -- THE SEAT'S QUESTION SPANS ITS SETTLE HORIZON (P-26, Ori 2026-10-02, R13 option (a); v27.159).
  -- Until v27.158 an ordinary seat asked for the WINDOW's clicks (3 or 7 days) by a due date
  -- settle_days away (7 SP / 14 SB), so implied_daily_spend x days-to-due overstated the cost of the
  -- clicks asked for by settle_days / window_days (audit, 10-01 live: 51 seats, $3,717.17 implied to
  -- the due date against $1,017.99 for the clicks requested). Now, on a seat taken tonight:
  --   ordinary  clicks_requested = ROUND(w_clk x settle_days / window_days) — the window's click
  --             rate over the horizon — and probes click_goal_day x settle_days; due on verdict_date,
  --             which is as_of + settle_days, so the horizon IS settle_days.
  --   implied_daily_spend = the seat's cost per day, as written (S04: the request and the seat are
  --             the same money); expected_cpc = that cost x the horizon / clicks_requested, so
  --             clicks_requested x expected_cpc / horizon = implied_daily_spend to the rounding of
  --             expected_cpc (acceptance T3). Integer clicks make expected_cpc differ from the
  --             window's own CPC at the new price by at most half a click's share of the horizon.
  -- An INCUMBENT (P-16) repeats the question it was given the night it took the seat — clicks, due
  -- date, expected CPC, implied spend and basis — so FACT_SEAT_REQUEST holds ONE promise per seat
  -- and V_SEAT_REQUEST_OUTCOME grades the clicks delivered since that night against it. Its cost is
  -- tonight's (v27.164), so on an incumbent implied_daily_spend is the money of the night the
  -- question was asked and need not equal seat_cost_per_day: acceptance T3 and S04 hold the two
  -- equal on the seats taken tonight, and T1 holds the incumbent's question to the one it was given.
  CREATE OR REPLACE TEMP TABLE questioned AS
  WITH q AS (
    SELECT p.*,
      CASE WHEN p.seat_no IS NULL           THEN NULL
           WHEN p.seat_tenure = 'INCUMBENT' THEN p.held_clicks
           WHEN p.is_probe                  THEN CAST(p.click_goal_day * p.settle_days AS INT64)
           ELSE CAST(ROUND(p.w_clk * p.settle_days / p.window_days) AS INT64) END AS q_clicks,
      CASE WHEN p.seat_no IS NULL           THEN NULL
           WHEN p.seat_tenure = 'INCUMBENT' THEN p.held_basis
           WHEN p.is_probe                  THEN 'HORIZON_PROBE_GOAL'
           ELSE 'HORIZON_WINDOW_RATE' END AS q_basis
    FROM priced p)
  SELECT q.*,
    CASE WHEN q.seat_no IS NULL           THEN NULL
         WHEN q.seat_tenure = 'INCUMBENT' THEN q.held_implied
         ELSE ROUND(q.plan_seat_cost, 4) END AS q_implied,
    CASE WHEN q.seat_no IS NULL           THEN NULL
         WHEN q.seat_tenure = 'INCUMBENT' THEN q.held_cpc
         ELSE ROUND(SAFE_DIVIDE(ROUND(q.plan_seat_cost, 4) * q.settle_days, NULLIF(q.q_clicks, 0)), 4)
    END AS q_cpc
  FROM q;

  -- P-22 (Ori 2026-10-02, R8 option (b); v27.158): P-8's arithmetic stays, and what the family is
  -- EXPECTED to spend on its not-good side after the upload is published beside the allowance.
  --   expected_after_upload_per_day = the seats' cost (as written, 4 decimals)
  --                                 + each queued candidate's window spend per day scaled by the
  --                                   price the plan leaves it at over its current bid: the park
  --                                   price on a PARK row, its current bid on a HOLD_AT_PARK row
  --                                   (nothing uploads, so it keeps spending at today's rate), and
  --                                   ZERO on a PAUSE row (the one queue position whose spend stops).
  --   share_closed = (not-good today - expected after upload) / (not-good today - allowance target)
  --                  — NULL when the family's not-good spend is already at or under its target
  --                  (a gap of $0.005 a day or less): there is no gap to close, and the ratio's sign
  --                  would read backwards.
  -- Linear in price, the same model as a seat's cost (P-6); the queue's true park spend is re-decided
  -- once an upload has been scored (P-22). Non-candidate not-good rows outside the holdout carry no
  -- spend by construction (they are NOT_SERVING non-probes, and the judge's served is w_sp > 0 OR
  -- w_clk > 0), so the seats and the queue are the whole not-good side the base counts.
  -- Both figures are computed from the values this procedure WRITES (4-decimal money), so the
  -- acceptance's recount (M3) reproduces them from the row columns alone.
  CREATE OR REPLACE TEMP TABLE fam_money AS
  WITH m AS (
    SELECT plan, family,
           SUM(IF(seat_no IS NOT NULL, ROUND(plan_seat_cost, 4), 0)) AS seats_per_day,
           SUM(IF(is_cand AND seat_no IS NULL AND move != 'PAUSE',
                  COALESCE(SAFE_DIVIDE(w_sp, window_days), 0)
                  * COALESCE(SAFE_DIVIDE(planned_bid_final, NULLIF(current_bid, 0)), 1), 0))
             AS queue_at_park_per_day
    FROM priced
    GROUP BY 1, 2),
  e AS (
    SELECT m.*,
           ROUND(m.seats_per_day + m.queue_at_park_per_day, 4) AS expected_after_upload_per_day,
           ROUND(f.notgood_today_per_day, 4)                    AS ng,
           ROUND(f.allowance_target_per_day, 4)                 AS tgt
    FROM m JOIN fam2 f USING (plan, family))
  SELECT plan, family, seats_per_day, queue_at_park_per_day, expected_after_upload_per_day,
         IF(ng - tgt > 0.005,
            ROUND((ng - expected_after_upload_per_day) / (ng - tgt), 4),
            NULL) AS share_closed
  FROM e;

  -- 7. Campaign budgets. THE CAP IS THE LARGEST EXECUTABLE NUMBER THIS PROCEDURE PUBLISHES, and
  -- v27.137's floor — "the plan's own spend inside the campaign" — was satisfied by construction
  -- rather than by protecting anything, because the plan's own spend is exactly the figure that
  -- counts a queued keyword at zero and a keyword it never judged at nothing at all. Two ways that
  -- became an executable cut on the first partition:
  --   (i)  THE QUEUE'S RESIDUAL STEERED THE BUDGET. A campaign whose money is in the QUEUE implies
  --        almost nothing (queued rows are planned at zero) and was ramped towards that figure,
  --        which the plan's own PARK sentence disowns in words on the same row: parking lowers a
  --        price, it does not stop a spend. One campaign implied $2.56/day against $53.13/day of
  --        spend the plan could see, and its cap was ramped down by a third.
  --   (ii) CAMPAIGNS THE PLAN COULD NOT MEASURE WERE CUT TOWARDS ZERO. 19 campaigns had every
  --        keyword NOT_SERVING with no spend and no clicks in a three-day August window; implied
  --        was 0, so the ramp was a one-third step towards zero — $153.35/day of cuts on evidence
  --        the plan does not have, compounding nightly because the ramp re-reads the cap it wrote
  --        ($150 -> $100 -> $66.67 -> ...). One of them was a BRAND DEFENSE campaign whose five
  --        keywords are the house's own brand terms. That breaks two binding house rules at once:
  --        unmeasured never reads as bad, and brand defense is never judged on profit (§8).
  -- The repair (v27.138) is three parts:
  --   NEED is the money the plan can SEE inside the campaign — its good side, its seats at the
  --   repaired price, AND the queue's continuing spend at today's rate. Parking is expected to
  --   lower that, so using today's rate is deliberately conservative: it can only over-fund.
  --   THE UNMEASURED GATE: a campaign with no spend and no clicks on any keyword the plan can see
  --   gets NO MOVE. The plan has measured nothing there and has nothing to say about its cap.
  --   THE DEFENSE GATE: a brand-defense campaign gets NO MOVE, whatever the window says. Detected
  --   the way the seat register detects it (the ladder flag OR 'BRAND DEFENSE' in the campaign
  --   name) — the ladder flag alone reads FALSE on the live defense campaign, which is why §8's
  --   filter in the judgement view did not catch it. That the flag is wrong is a Task 1 file and
  --   is recorded for Ori, not patched here.
  -- v27.158 (2026-10-02, piece-1 plan Task 4):
  --   THE HOLDOUT GATE (audit fix #11): a HOLDOUT campaign gets NO MOVE — its cap stays at today's
  --   budget, delta 0, basis NO_MOVE_HOLDOUT, and the sentence says what the plan would have set.
  --   Holdout rows were already "a record and no move" on every keyword; the cap was the one move
  --   left (7 of the 8 holdout campaigns had their caps moved on every live partition 2026-09-28 ..
  --   10-02). A cap the plan does not move is not floored at need: a control campaign spending
  --   more than its budget is the control's own business (5 holdout campaigns showed need above
  --   today's budget on the 2026-10-02 partition), so the floor assertions read only moved caps.
  --   THE BASIS SAYS WHAT BOUND THE CAP (audit fix #12). The cap is GREATEST(ramp, need, good
  --   side, $1.00) snapped out of the band (P-27, §4.7). Until v27.157 every moved cap read RAMPED
  --   (FLOORED_AT_NEED needed today's budget above need, and a cut's ramp value is always above
  --   need, so the branch could not fire: 0 rows in its lifetime). Now, in order:
  --     BAND_SNAPPED_UP / _DOWN  the $20.01-$31.99 snap moved the cap off the GREATEST's number;
  --     FLOORED_AT_NEED          the GREATEST landed on need and need is not the ramp's number (a
  --                              raise lands on need in one night, P-27);
  --     FLOORED_AT_MINIMUM       Amazon's $1.00 minimum set it (ramp and need both under $1.00);
  --     RAMPED                   the cap IS ROUND(current + (need - current) / ramp_steps, 2);
  --     UNEXPLAINED              none of the above — asserted never to be written.
  CREATE OR REPLACE TEMP TABLE budgets AS
  WITH implied AS (
    SELECT plan, campaign_id,
           SUM(planned_spend_per_day)                          AS implied_budget,
           SUM(IF(side = 'GOOD', planned_spend_per_day, 0))    AS good_budget,
           -- the queue's residual: what parking lowers and does not stop. A PAUSED row is the one
           -- queue position whose spend really does stop, so it is not funded.
           SUM(IF(is_cand AND seat_no IS NULL AND move != 'PAUSE',
                  COALESCE(SAFE_DIVIDE(w_sp, window_days), 0), 0))  AS queue_spend,
           -- everything the plan can see this campaign spending, whatever side it is on
           SUM(COALESCE(SAFE_DIVIDE(w_sp, window_days), 0))    AS visible_spend,
           SUM(COALESCE(w_clk, 0))                             AS visible_clicks,
           LOGICAL_OR(COALESCE(is_brand_defense, FALSE)
                      OR UPPER(COALESCE(campaign_name, '')) LIKE '%BRAND DEFENSE%')
                                                               AS is_defense,
           LOGICAL_OR(COALESCE(holdout, FALSE))                AS is_holdout,
           MIN(IF(COALESCE(holdout, FALSE), holdout_eligible_from, NULL)) AS holdout_from,
           MAX(campaign_current_budget)                        AS current_budget,
           MAX(fam_ramp_steps)                                 AS ramp_steps
    FROM priced GROUP BY 1, 2),
  needed AS (
    SELECT i.*,
           i.implied_budget + i.queue_spend AS need_budget,
           (i.visible_spend <= 0.0001 AND i.visible_clicks = 0
            AND i.current_budget IS NOT NULL)                  AS unmeasured
    FROM implied i),
  rampd AS (
    SELECT n.*,
           COALESCE(n.current_budget, n.need_budget)
             + (n.need_budget - COALESCE(n.current_budget, n.need_budget)) / n.ramp_steps
             AS ramp_budget
    FROM needed n),
  floored AS (
    SELECT r.*, GREATEST(r.ramp_budget, r.need_budget, r.good_budget, 1.00) AS raw_budget
    FROM rampd r),
  snapped AS (
    SELECT r.*,
           ROUND(
             CASE WHEN r.raw_budget > 20.00 AND r.raw_budget < 32.00
                  -- never snap a cap BELOW the money the plan can see inside this campaign
                  THEN IF(r.raw_budget < 26.00 AND r.need_budget <= 20.00, 20.00, 32.00)
                  ELSE r.raw_budget END, 2) AS ramped_budget
    FROM floored r)
  SELECT plan, campaign_id, current_budget, need_budget, visible_spend, holdout_from,
         -- what the ramp alone would set, and what the GREATEST and the snap set; the holdout
         -- sentence prints the second, because the plan records what it would have done
         ROUND(ramp_budget, 2) AS ramp_value,
         ROUND(raw_budget, 2)  AS pre_snap_budget,
         ramped_budget         AS would_set_budget,
         CASE WHEN is_holdout OR is_defense OR unmeasured
                THEN ROUND(COALESCE(current_budget, ramped_budget), 2)
              ELSE ramped_budget END AS campaign_planned_budget,
         CASE WHEN is_holdout                          THEN 'NO_MOVE_HOLDOUT'
              WHEN is_defense                          THEN 'NO_MOVE_BRAND_DEFENSE'
              WHEN unmeasured                          THEN 'NO_MOVE_UNMEASURED'
              WHEN ABS(ramped_budget - ROUND(raw_budget, 2)) > 0.005
                THEN IF(ramped_budget > raw_budget, 'BAND_SNAPPED_UP', 'BAND_SNAPPED_DOWN')
              WHEN ABS(raw_budget - need_budget) <= 0.005
                   AND ABS(ROUND(need_budget, 2) - ROUND(ramp_budget, 2)) > 0.005
                                                       THEN 'FLOORED_AT_NEED'
              WHEN ABS(raw_budget - 1.00) <= 0.005
                   AND ramp_budget < 0.995 AND need_budget < 0.995
                                                       THEN 'FLOORED_AT_MINIMUM'
              WHEN ABS(ramped_budget - ROUND(ramp_budget, 2)) <= 0.01
                                                       THEN 'RAMPED'
              ELSE 'UNEXPLAINED' END AS campaign_budget_basis
  FROM snapped;

  -- THE GUARANTEES ARE ASSERTED BEFORE THE PARTITION IS TOUCHED (repaired v27.137). v27.136
  -- DELETEd, INSERTed and only then ASSERTed. BigQuery scripts are not transactional here and the
  -- orchestrator's Task 20.8c wraps this CALL in BEGIN ... EXCEPTION WHEN ERROR THEN, so a broken
  -- guarantee left the violating partition written and committed, logged one FAIL row and let the
  -- pass continue — an assertion that names a guarantee it could not protect. The rows are built
  -- into a TEMP TABLE with the fact table's own schema, the ASSERTs read that, and only a clean
  -- build reaches the partition. A failure now leaves YESTERDAY'S plan in place, which is the
  -- safe state: stale and correct beats fresh and wrong.
  CREATE OR REPLACE TEMP TABLE final AS
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE FALSE;

  INSERT INTO final
    (as_of, plan, is_live_plan, family, book, campaign_id, campaign_name, keyword_id, ad_group_id,
     target_text, match_type, channel, is_auto, is_pt, calendar_state, window_days, window_from,
     window_to, watermark, w_clk, w_ord, w_sp, w_gp, w_gp_corrected, settle_factor_min,
     settle_factor_eff, settle_curve_available, settled, settle_due_on, settle_arm, decided_by,
     was_good, family_bar, ret_raw, ret_corrected, ladder_state, side, verdict, is_candidate,
     rank_score, rank_dollars_at_stake, rank_closeness, rank_is_degenerate, served, prior_grace,
     last_grace_on, grace_limit_armed, held_despite_evidence, held_with_no_sale, good_side_no_sale,
     hold_since, hold_settles_on, hold_expired, last_day_sp, last_day_clk, last_day_ord, last_day_gp,
     last_day_gp_corrected, last_day_ret, last_day_strong, guard_released_by,
     -- v27.154 follow-up: the P-14c rule the row was judged under, copied from the judge
     strong_day_mult, strong_day_min_orders,
     -- v27.156: the judge's memory (P-17, P-18, P-29), copied; memory_cleared_by_gap is read back
     -- by the judge as a reset, so a cleared memory stays cleared the next night
     hold_strong_day, hold_kept_by, grace_since, memory_cleared_by_gap,
     rank_no, seat_no, seat_cost_per_day, current_bid, planned_bid, bid_floor, bid_park,
     bid_park_source, bid_park_seat_econ, move, planned_spend_per_day,
     planned_spend_delta_per_day, verdict_date, pot_per_day,
     allowance_target_per_day, allowance_ramped_per_day, notgood_today_per_day, ramp_step,
     ramp_steps, allowance_share, campaign_planned_budget, campaign_current_budget,
     campaign_planned_budget_delta_per_day, campaign_budget_basis, campaign_visible_spend_per_day,
     holdout, holdout_member, holdout_eligible_from, sentence, built_at,
     -- v27.146 (plan step 4, violation 27, §3.0 step 2): the seat names its question.
     clicks_requested, clicks_due_date, expected_cpc, implied_daily_spend, request_basis,
     -- v27.158 (P-22, audit fix #15): the realised cut beside the allowance, and the uploads that
     -- landed (migration 2026-10-02_plan_money_columns.sql)
     expected_after_upload_per_day, share_closed, plan_uploads_landed,
     -- v27.159 (P-16, P-25): the seat's tenure and the probe flag (migration
     -- 2026-10-02_plan_seat_tenure_columns.sql); seat_since is read back the next night
     seat_since, seat_tenure, is_probe)
  SELECT
    as_of_d, p.plan, (p.plan = live_plan_code), p.family, p.book, p.campaign_id, p.campaign_name,
    p.keyword_id, p.ad_group_id, p.target_text, p.match_type, p.channel, p.is_auto, p.is_pt,
    p.calendar_state, p.window_days, p.window_from, p.window_to, p.watermark,
    p.w_clk, p.w_ord, p.w_sp, p.w_gp, p.w_gp_corrected,
    p.settle_factor_min, p.settle_factor_eff, p.settle_curve_available, p.settled, p.settle_due_on,
    p.settle_arm, p.decided_by, p.was_good, p.family_bar, p.ret_raw, p.ret_corrected,
    p.ladder_state, p.side, p.verdict, p.is_cand,
    p.rank_score, p.rank_dollars_at_stake, p.rank_closeness,
    (p.is_cand AND p.rank_score = 0), p.served, p.prior_grace, p.last_grace_on,
    p.grace_limit_armed, p.held_despite_evidence, p.held_with_no_sale, p.good_side_no_sale,
    p.hold_since, p.hold_settles_on, p.hold_expired, p.last_day_sp, p.last_day_clk, p.last_day_ord,
    p.last_day_gp, p.last_day_gp_corrected, p.last_day_ret, p.last_day_strong, p.guard_released_by,
    p.strong_day_mult, p.strong_day_min_orders,
    p.hold_strong_day, p.hold_kept_by, p.grace_since, p.memory_cleared_by_gap,
    p.rank_no, p.seat_no,
    IF(p.side = 'GOOD', NULL, ROUND(p.plan_seat_cost, 4)),
    p.current_bid, p.planned_bid_final, p.bid_floor, p.bid_park, p.bid_park_source,
    p.bid_park_seat_econ, p.move, ROUND(p.planned_spend_per_day, 4),
    ROUND(p.planned_spend_per_day - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0), 4),
    p.verdict_date,
    ROUND(p.pot_per_day, 4), ROUND(p.allowance_target_per_day, 4),
    ROUND(p.allowance_ramped_per_day, 4), ROUND(p.notgood_today_per_day, 4),
    -- ramp_step is a REPORT: how many plan uploads have LANDED for this family since its first
    -- plan night, capped at ramp_steps (v27.158, audit fix #15; 0 = no step taken yet). The
    -- arithmetic above does not read it — each night's ramp is re-anchored on tonight's actual
    -- not-good spend, so it descends only as uploads cut that spend; with none, each night
    -- re-takes the same one-third step from a base that drifts with the window.
    LEAST(p.fam_ramp_steps, COALESCE(u.plan_uploads_landed, 0)),
    p.fam_ramp_steps, p.allowance_share,
    b.campaign_planned_budget, p.campaign_current_budget,
    ROUND(b.campaign_planned_budget - COALESCE(p.campaign_current_budget,
                                               b.campaign_planned_budget), 4),
    b.campaign_budget_basis, ROUND(b.visible_spend, 4),
    p.holdout, p.holdout_member, p.holdout_eligible_from,
    CONCAT(
      -- AUDIT FIX #25 (v27.160, piece-1 plan Task 6): A SHADOW ROW SPEAKS FOR PLAN A'S SIDE. The
      -- judgement's sentence and its settle-arm sentence are written for RULE B's verdict. Until
      -- v27.159 every plan-A row opened with them, so where the ladder and rule B disagree the row
      -- named the live plan's side and then plan A's move: on the 2026-10-02 partition v27.159 wrote
      -- (01:20 UTC 10-03) 118 of 361 shadow rows had a side other than the live plan's, 110 plan-A
      -- GOOD rows carried the not-good side's words and 8 plan-A NOT_GOOD rows the good side's, 54
      -- of the GOOD rows read both "competes for a seat at" and "No move: the good side is never
      -- cut", and 8 plan-A rows published a planned bid beside "this row carries no planned price"
      -- (acceptance K3 read 244 on that partition; query: SOP §3, "Which clock keys a
      -- night, and the shadow plan's sentences"). Now a shadow row whose side differs from the live
      -- plan's names the ladder state, plan A's side and rule B's verdict, and is followed by plan
      -- A's own move clause below; the judgement's rule-B sentence is not printed on it (its P-4
      -- "carries no planned price" clause with it). A shadow row on the live plan's side keeps the
      -- judgement's sentence: it names the side the row holds.
      CASE
        WHEN p.plan = live_plan_code
          THEN CONCAT(COALESCE(p.sentence, ''), ' ', COALESCE(p.settle_arm_sentence, ''), '.')
        WHEN p.side != p.side_b THEN FORMAT(
          'SHADOW PLAN A, recorded for grading and never uploaded (P-9): the ladder calls this %s, so plan A puts it on the %s side; rule B says %s for the window %t to %t (%d order(s) on $%.2f of ad spend, %.2f gross-profit dollars per ad dollar corrected, against the %s bar of %.2f), so the live plan puts it on the %s side. What follows is plan A\'s own move, never uploaded.',
          COALESCE(p.ladder_state, 'no ladder state'), IF(p.side = 'GOOD', 'good', 'not-good'),
          p.verdict, p.window_from, p.window_to, p.w_ord, p.w_sp, COALESCE(p.ret_corrected, 0),
          p.family, p.family_bar, IF(p.side_b = 'GOOD', 'good', 'not-good'))
        ELSE CONCAT('SHADOW PLAN A, recorded for grading and never uploaded (P-9). ',
                    COALESCE(p.sentence, ''), ' ', COALESCE(p.settle_arm_sentence, ''), '.')
      END,
      CASE
        WHEN p.move = 'REPRICE' THEN CONCAT(FORMAT(
          ' SEAT %d of %s: re-price $%.2f -> $%.2f, costing about $%.2f a day of the $%.2f a day this family allows the not-good side. That is %s of about $%.2f a day against what this keyword is spending now. Judged again on %t (P-12).',
          COALESCE(p.seat_no, 0), p.family, COALESCE(p.current_bid, 0),
          COALESCE(p.planned_bid_final, 0), COALESCE(p.plan_seat_cost, 0),
          COALESCE(p.allowance_ramped_per_day, 0),
          CASE WHEN p.planned_spend_per_day
                    - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0) > 0.005 THEN 'A RAISE'
               WHEN COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0)
                    - p.planned_spend_per_day > 0.005                         THEN 'a cut'
               ELSE 'no change' END,
          ABS(p.planned_spend_per_day - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0)),
          COALESCE(p.verdict_date, as_of_d)),
          -- P-16 (v27.159): the seat's tenure, in words
          IF(p.seat_tenure = 'INCUMBENT',
             FORMAT(' TENURE: it has held this seat since %t and keeps it, its price and its question until its verdict date while it stays a candidate (P-16); its cost is re-read each night at that price%s.',
                    p.seat_since,
                    IF(ABS(COALESCE(p.tonight_bid, p.current_bid, 0) - COALESCE(p.plan_bid, 0)) > 0.005,
                       FORMAT('; tonight\'s window alone would price it at $%.2f, and an incumbent\'s price does not move before its date',
                              COALESCE(p.tonight_bid, p.current_bid, 0)),
                       '')),
             ' TENURE: seated tonight; it holds the seat until its verdict date while it stays a candidate, and no newcomer displaces it before then (P-16).'),
          -- P-26 (v27.159): the seat's question, over its settle horizon
          FORMAT(' The seat asks for %d clicks by %t at about $%.2f a click: %s (P-26).',
                 COALESCE(p.q_clicks, 0), p.verdict_date, COALESCE(p.q_cpc, 0),
                 CASE WHEN p.seat_tenure = 'INCUMBENT'
                        THEN FORMAT('the question it was given on %t', p.seat_since)
                      ELSE FORMAT('the window\'s %d clicks in %d days, at that rate over the %d-day settle horizon',
                                  p.w_clk, p.window_days, p.settle_days) END))
        -- THE DIRECTION CLAUSE BELONGS HERE MOST OF ALL (v27.138). A held seat's sentence says
        -- nothing is uploaded, and a reader stops there — but the seat is still COSTED at the
        -- repaired price (P-6), so the plan can have budgeted MORE for this keyword than it is
        -- spending while telling the reader there is nothing to do. v27.137 added the clause to
        -- the REPRICE sentence only and its own account said both; these are exactly the rows
        -- where the number is invisible without it.
        WHEN p.move = 'HOLD_AT_PRICE' THEN CONCAT(FORMAT(
          ' SEAT %d of %s: the price is already where the plan wants it, so nothing is uploaded; it keeps its seat at about $%.2f a day of the $%.2f a day this family allows the not-good side. That is %s of about $%.2f a day against what this keyword is spending now, uploaded or not. A held seat is still a seat and still carries a clock: judged again on %t (P-12), when it graduates, steps again, or gives the seat up.',
          COALESCE(p.seat_no, 0), p.family, COALESCE(p.plan_seat_cost, 0),
          COALESCE(p.allowance_ramped_per_day, 0),
          CASE WHEN p.planned_spend_per_day
                    - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0) > 0.005 THEN 'A RAISE'
               WHEN COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0)
                    - p.planned_spend_per_day > 0.005                         THEN 'a cut'
               ELSE 'no change' END,
          ABS(p.planned_spend_per_day - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0)),
          COALESCE(p.verdict_date, as_of_d)),
          -- P-16 (v27.159): the seat's tenure, in words
          IF(p.seat_tenure = 'INCUMBENT',
             FORMAT(' TENURE: it has held this seat since %t and keeps it, its price and its question until its verdict date while it stays a candidate (P-16); its cost is re-read each night at that price%s.',
                    p.seat_since,
                    IF(ABS(COALESCE(p.tonight_bid, p.current_bid, 0) - COALESCE(p.plan_bid, 0)) > 0.005,
                       FORMAT('; tonight\'s window alone would price it at $%.2f, and an incumbent\'s price does not move before its date',
                              COALESCE(p.tonight_bid, p.current_bid, 0)),
                       '')),
             ' TENURE: seated tonight; it holds the seat until its verdict date while it stays a candidate, and no newcomer displaces it before then (P-16).'),
          -- P-26 (v27.159): the seat's question, over its settle horizon
          FORMAT(' The seat asks for %d clicks by %t at about $%.2f a click: %s (P-26).',
                 COALESCE(p.q_clicks, 0), p.verdict_date, COALESCE(p.q_cpc, 0),
                 CASE WHEN p.seat_tenure = 'INCUMBENT'
                        THEN FORMAT('the question it was given on %t', p.seat_since)
                      ELSE FORMAT('the window\'s %d clicks in %d days, at that rate over the %d-day settle horizon',
                                  p.w_clk, p.window_days, p.settle_days) END))
        -- P-25 (Ori 2026-10-02, R12; audit fix #19; v27.159): a seated probe OPENS. Its spend clause
        -- says "in spend": the probe's bid can sit below the bid it never bought a click at, while
        -- its spend rises from nothing to the clicks it asks for.
        WHEN p.move = 'OPEN_PROBE' THEN CONCAT(FORMAT(
          ' SEAT %d of %s: OPEN PROBE at $%.2f for about %d clicks a day (about $%.2f a day of the $%.2f a day this family allows the not-good side), judged after %d clicks or on %t, whichever comes first (P-25, P-12). That is %s of about $%.2f a day in spend against what this keyword is spending now.',
          COALESCE(p.seat_no, 0), p.family, COALESCE(p.planned_bid_final, 0),
          COALESCE(CAST(ROUND(SAFE_DIVIDE(p.q_clicks, DATE_DIFF(p.verdict_date, p.seat_since, DAY))) AS INT64), 0),
          COALESCE(p.plan_seat_cost, 0), COALESCE(p.allowance_ramped_per_day, 0),
          COALESCE(p.q_clicks, 0), p.verdict_date,
          CASE WHEN p.planned_spend_per_day
                    - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0) > 0.005 THEN 'A RAISE'
               WHEN COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0)
                    - p.planned_spend_per_day > 0.005                         THEN 'a cut'
               ELSE 'no change' END,
          ABS(p.planned_spend_per_day - COALESCE(SAFE_DIVIDE(p.w_sp, p.window_days), 0))),
          -- P-16 (v27.159): the seat's tenure, in words
          IF(p.seat_tenure = 'INCUMBENT',
             FORMAT(' TENURE: it has held this seat since %t and keeps it, its price and its question until its verdict date while it stays a candidate (P-16); its cost is re-read each night at that price%s.',
                    p.seat_since,
                    IF(ABS(COALESCE(p.tonight_bid, p.current_bid, 0) - COALESCE(p.plan_bid, 0)) > 0.005,
                       FORMAT('; tonight\'s window alone would price it at $%.2f, and an incumbent\'s price does not move before its date',
                              COALESCE(p.tonight_bid, p.current_bid, 0)),
                       '')),
             ' TENURE: seated tonight; it holds the seat until its verdict date while it stays a candidate, and no newcomer displaces it before then (P-16).'))
        -- audit fix #19 (v27.159): the queue's words branch on SERVICE. A keyword that took no click
        -- and spent nothing does not "keep buying clicks at the park price". Since P-25 every
        -- unserved candidate is a probe and an unseated probe gets NONE, so no PARK or HOLD_AT_PARK
        -- row is unserved by construction; the branch is the net under that (acceptance T4).
        WHEN p.move = 'PARK' THEN CONCAT(
          IF(p.served, FORMAT(
          ' QUEUED at rank %d, no seat: park the bid at $%.2f. Parking LOWERS the price, it does not stop the spend — this keyword keeps buying clicks at the park price until it earns a seat or is killed, so the real not-good spend of this family sits above the $%.2f a day allowance until then.',
          COALESCE(p.rank_no, 0), COALESCE(p.planned_bid_final, 0),
          COALESCE(p.allowance_ramped_per_day, 0)),
             FORMAT(' QUEUED at rank %d, no seat: park the bid at $%.2f. Not serving: it bought no clicks and spent nothing at $%.2f in the window, so the park price is a floor it already does not reach, and it adds nothing to the family\'s not-good spend.',
                    COALESCE(p.rank_no, 0), COALESCE(p.planned_bid_final, 0), COALESCE(p.current_bid, 0))),
          -- P-16 (v27.159): an incumbent tonight's allowance could not carry says so; v27.167 (F8):
          -- in R2's words, with what the incumbents that kept their seats cost
          IF(p.seat_tenure = 'LEFT_ALLOWANCE_SHRANK',
             FORMAT(' TENURE ENDS EARLY: it held SEAT %d of %s from %t with its verdict due on %t, but tonight\'s $%.2f a day allowance cannot carry every incumbent, so incumbents leave latest-seated first until the rest fit (P-16): %s, so it gives the seat up before its date.',
                    COALESCE(p.held_seat_no, 0), p.family, p.held_since, p.held_verdict_date,
                    COALESCE(p.allowance_ramped_per_day, 0),
                    CASE COALESCE(p.inc_kept_n, 0)
                      WHEN 0 THEN 'none keeps its seat, because the earliest seated does not fit on its own'
                      WHEN 1 THEN FORMAT('the one that keeps its seat was seated before it (tonight\'s rank breaking a tie of seat dates) and costs $%.2f a day',
                                         COALESCE(p.inc_kept_per_day, 0))
                      ELSE FORMAT('the %d that keep their seats were all seated before it (tonight\'s rank breaking a tie of seat dates) and cost $%.2f a day',
                                  p.inc_kept_n, COALESCE(p.inc_kept_per_day, 0)) END),
             ''))
        WHEN p.move = 'HOLD_AT_PARK' THEN CONCAT(
          IF(p.served, FORMAT(
          ' QUEUED at rank %d, no seat — and its bid is already at or below the $%.2f park price, so there is NOTHING TO UPLOAD for this keyword: it holds its queue position at the price it already has. It is not paused and it is not dead; it keeps buying clicks at that price. A keyword that queues a whole window with no seat is a kill candidate, and the probation ladder — bid to the floor, probation, then kill — decides that, not this plan.',
          COALESCE(p.rank_no, 0), COALESCE(COALESCE(p.bid_park, p.bid_floor), 0)),
             FORMAT(' QUEUED at rank %d, no seat, and nothing to upload. Not serving: it bought no clicks and spent nothing in the window, so the park price is a floor it already does not reach, and it adds nothing to the family\'s not-good spend.',
                    COALESCE(p.rank_no, 0))),
          -- P-16 (v27.159): an incumbent tonight's allowance could not carry says so; v27.167 (F8):
          -- in R2's words, with what the incumbents that kept their seats cost
          IF(p.seat_tenure = 'LEFT_ALLOWANCE_SHRANK',
             FORMAT(' TENURE ENDS EARLY: it held SEAT %d of %s from %t with its verdict due on %t, but tonight\'s $%.2f a day allowance cannot carry every incumbent, so incumbents leave latest-seated first until the rest fit (P-16): %s, so it gives the seat up before its date.',
                    COALESCE(p.held_seat_no, 0), p.family, p.held_since, p.held_verdict_date,
                    COALESCE(p.allowance_ramped_per_day, 0),
                    CASE COALESCE(p.inc_kept_n, 0)
                      WHEN 0 THEN 'none keeps its seat, because the earliest seated does not fit on its own'
                      WHEN 1 THEN FORMAT('the one that keeps its seat was seated before it (tonight\'s rank breaking a tie of seat dates) and costs $%.2f a day',
                                         COALESCE(p.inc_kept_per_day, 0))
                      ELSE FORMAT('the %d that keep their seats were all seated before it (tonight\'s rank breaking a tie of seat dates) and cost $%.2f a day',
                                  p.inc_kept_n, COALESCE(p.inc_kept_per_day, 0)) END),
             ''))
        WHEN p.move = 'PAUSE' THEN FORMAT(
          ' QUEUED at rank %d, and THE LADDER HAS ALREADY CLOSED THIS KEYWORD (state DEAD): pause it. THIS SUPERSEDES THE WHOLE JUDGEMENT ABOVE — a closed keyword does not compete for a seat at any price, holds none of the family allowance, and is stopped rather than parked or re-priced, so the plan publishes no bid on this row.',
          COALESCE(p.rank_no, 0))
        -- P-25 (v27.159): an unseated probe — no move, nothing uploaded. The judgement's own clause
        -- above still says it "queues at the park price"; this supersedes it.
        WHEN p.move = 'NONE' AND p.is_cand THEN CONCAT(FORMAT(
          ' QUEUED at rank %d: PROBE NOT OPENED TONIGHT; NOTHING UPLOADED (P-25). A probe that does not win a seat gets no move, so the park price the judgement names above is not applied%s.',
          COALESCE(p.rank_no, 0),
          IF(p.served, FORMAT(', and it keeps buying clicks at its current bid of $%.2f', COALESCE(p.current_bid, 0)),
             ' to a keyword that bought no clicks')),
          -- P-16 (v27.159): an incumbent tonight's allowance could not carry says so; v27.167 (F8):
          -- in R2's words, with what the incumbents that kept their seats cost
          IF(p.seat_tenure = 'LEFT_ALLOWANCE_SHRANK',
             FORMAT(' TENURE ENDS EARLY: it held SEAT %d of %s from %t with its verdict due on %t, but tonight\'s $%.2f a day allowance cannot carry every incumbent, so incumbents leave latest-seated first until the rest fit (P-16): %s, so it gives the seat up before its date.',
                    COALESCE(p.held_seat_no, 0), p.family, p.held_since, p.held_verdict_date,
                    COALESCE(p.allowance_ramped_per_day, 0),
                    CASE COALESCE(p.inc_kept_n, 0)
                      WHEN 0 THEN 'none keeps its seat, because the earliest seated does not fit on its own'
                      WHEN 1 THEN FORMAT('the one that keeps its seat was seated before it (tonight\'s rank breaking a tie of seat dates) and costs $%.2f a day',
                                         COALESCE(p.inc_kept_per_day, 0))
                      ELSE FORMAT('the %d that keep their seats were all seated before it (tonight\'s rank breaking a tie of seat dates) and cost $%.2f a day',
                                  p.inc_kept_n, COALESCE(p.inc_kept_per_day, 0)) END),
             ''))
        -- v27.158 (P-15): the holdout's GOOD keywords now count in the pot, so the clause says
        -- which of its money the plan leaves out — the not-good side's — and which it counts.
        WHEN p.move = 'NONE_HOLDOUT' THEN FORMAT(
          ' This campaign is a measurement control (HOLDOUT from %t): the plan records what it would have done and uploads nothing to it; its not-good spend stays out of the not-good side and the ramp, and only its good keywords count, in the family\'s pot (P-15).',
          p.holdout_eligible_from)
        -- audit fix #11: a GOOD keyword in a holdout campaign keeps move NONE (P-4 and acceptance
        -- C06 demand NONE on the good side) and its sentence now says it is a measurement control.
        ELSE IF(p.side = 'GOOD',
          CONCAT(
            ' No move: the good side is never cut and is not re-priced (P-4), and this row carries no planned price and no seat cost.',
            IF(COALESCE(p.holdout, FALSE),
               FORMAT(' This campaign is a measurement control (HOLDOUT from %t): the plan uploads nothing to it; its good keywords\' window spend still counts in the family\'s pot (P-15).',
                      p.holdout_eligible_from),
               '')),
          ' No move: there is nothing to repair here — no spend, no clicks and no probe nomination in the window — so this keyword takes neither a seat nor a queue position (spec §9).')
      END,
      IF(p.shadow_unpriced,
         ' SHADOW PRICING NOTE: the live plan calls this keyword GOOD, so P-4 withholds a repaired price for it and the shadow holds it at its current price and costs its seat at its current spend.',
         ''),
      -- THE CAMPAIGN CAP IS ALSO A MOVE, AND IT USED TO BE THE SILENT ONE (v27.138). Every
      -- campaign in the first partition got a different cap from the one it has, and no sentence
      -- anywhere mentioned the budget. A cap is executable in a way a bid is not: it starves every
      -- keyword in the campaign, including the ones the plan never judged. So it says its number,
      -- its direction and its reason on the row, next to the keyword move.
      CASE b.campaign_budget_basis
        -- v27.158, audit fix #11
        WHEN 'NO_MOVE_HOLDOUT' THEN FORMAT(
          ' CAMPAIGN CAP: unchanged at $%.2f a day — this campaign is in the HOLDOUT arm from %t; the plan records what it would have done (a cap of $%.2f a day) and moves nothing.',
          COALESCE(b.campaign_planned_budget, 0), b.holdout_from, COALESCE(b.would_set_budget, 0))
        WHEN 'NO_MOVE_BRAND_DEFENSE' THEN FORMAT(
          ' CAMPAIGN CAP: unchanged at $%.2f a day. This is a BRAND DEFENSE campaign and defense is never judged on profit (spec §8), so the plan does not move its budget whatever the window says.',
          COALESCE(b.campaign_planned_budget, 0))
        WHEN 'NO_MOVE_UNMEASURED' THEN FORMAT(
          ' CAMPAIGN CAP: unchanged at $%.2f a day. Not one keyword the plan can see in this campaign took a click or spent a cent in the window, so the plan has MEASURED NOTHING here and says nothing about the cap. Unmeasured never reads as bad.',
          COALESCE(b.campaign_planned_budget, 0))
        -- v27.158, audit fix #12: the tail names what bound the cap, one per basis. Until v27.157
        -- every moved cap said "the one-third ramp decided it", including the raises that landed
        -- on need and the caps the band snap set.
        ELSE FORMAT(
          ' CAMPAIGN CAP: $%.2f -> $%.2f a day, %s of $%.2f. The plan can see about $%.2f a day of spend inside this campaign (its good side, its seats at the repaired price, and the queue that keeps buying clicks at the park price) and the cap is never set below that%s.',
          COALESCE(p.campaign_current_budget, 0), COALESCE(b.campaign_planned_budget, 0),
          CASE WHEN COALESCE(b.campaign_planned_budget, 0)
                    - COALESCE(p.campaign_current_budget, 0) > 0.005 THEN 'A RAISE'
               WHEN COALESCE(p.campaign_current_budget, 0)
                    - COALESCE(b.campaign_planned_budget, 0) > 0.005 THEN 'a cut'
               ELSE 'no change' END,
          ABS(COALESCE(b.campaign_planned_budget, 0)
              - COALESCE(p.campaign_current_budget, 0)),
          COALESCE(b.need_budget, 0),
          CASE b.campaign_budget_basis
            WHEN 'RAMPED' THEN ' — tonight the one-third ramp decided it'
            WHEN 'FLOORED_AT_NEED' THEN FORMAT(
              ': the cap lands on that money tonight (the one-third ramp alone would have set $%.2f; a raise lands on need in one night, P-27)',
              COALESCE(b.ramp_value, 0))
            WHEN 'BAND_SNAPPED_UP' THEN FORMAT(
              ' — the forbidden $20.01-$31.99 band moved it UP to $32.00 from $%.2f, the figure the ramp and the floor gave',
              COALESCE(b.pre_snap_budget, 0))
            WHEN 'BAND_SNAPPED_DOWN' THEN FORMAT(
              ' — the forbidden $20.01-$31.99 band moved it DOWN to $20.00 from $%.2f, the figure the ramp and the floor gave (the snap goes down only when that money is $20.00 or less)',
              COALESCE(b.pre_snap_budget, 0))
            WHEN 'FLOORED_AT_MINIMUM' THEN ' — Amazon\'s $1.00 minimum set it'
            ELSE ' — UNEXPLAINED: no rule of §4.7 produced this number'
          END)
      END,
      -- v27.158 (P-15, P-21, P-22, audit fix #15): THE FAMILY'S MONEY, on every row of the family.
      -- The pot, the target, the not-good side, this window's allowance, what the family is
      -- expected to spend after the upload and the share of the gap that closes, and how many plan
      -- uploads have landed. Until v27.157 none of the money above the seat was on any sentence.
      FORMAT(
        ' FAMILY %s%s: pot $%.2f a day (every GOOD keyword\'s window spend, holdout included, P-15); allowance target $%.2f a day (%.2f x pot); not-good side today $%.2f a day outside the holdout; this window allows $%.2f a day (%s). Expected after the upload: $%.2f a day — the seats $%.2f plus the queue at the price the plan leaves it at $%.2f — %s (P-22). Ramp: %s.',
        p.family, IF(p.plan = live_plan_code, '', ' (shadow plan A)'),
        COALESCE(p.pot_per_day, 0), COALESCE(p.allowance_target_per_day, 0),
        COALESCE(p.allowance_share, 0), COALESCE(p.notgood_today_per_day, 0),
        COALESCE(p.allowance_ramped_per_day, 0),
        -- which of the two branches of fam2 set it: below the target the family keeps what it spends
        IF(COALESCE(p.notgood_today_per_day, 0) <= COALESCE(p.allowance_target_per_day, 0),
           'today\'s not-good spend: the target is above it, and the allowance never raises a family\'s loser spend, P-21',
           'one third of the gap between today\'s not-good spend and the target closed, P-8'),
        COALESCE(fm.expected_after_upload_per_day, 0), COALESCE(fm.seats_per_day, 0),
        COALESCE(fm.queue_at_park_per_day, 0),
        IF(fm.share_closed IS NULL,
           'the family is at or under its allowance target, so there is no gap to close',
           FORMAT('%.0f%% of the gap to the allowance target closes', 100 * fm.share_closed)),
        IF(COALESCE(u.plan_uploads_landed, 0) = 0,
           FORMAT('no step taken yet — no plan upload has landed for this family since %t',
                  COALESCE(fs.first_as_of, as_of_d)),
           FORMAT('step %d of %d — %d plan upload(s) landed since %t',
                  LEAST(p.fam_ramp_steps, u.plan_uploads_landed), p.fam_ramp_steps,
                  u.plan_uploads_landed, COALESCE(fs.first_as_of, as_of_d))))
      ) AS sentence,
    CURRENT_TIMESTAMP(),
    -- ------------------------------------------------------------------------------------------
    -- v27.146 — THE SEAT NAMES ITS QUESTION (violation 27, §3.0 step 2).
    -- Ori: the Brain must decide "what answers per keyword he is going to buy with it (seats) and
    -- HOW MANY CLICKS he want to deliver in a SPECIFIC TIME WINDOW."
    --
    -- NOTHING HERE IS A FORECAST. Both numbers were always implied by the seat's own dollars and
    -- were simply never written where anything could check them:
    --   ORDINARY: seat_cost = (w_sp/days) x (planned/current). At the new price CPC scales by the
    --   SAME ratio, so it cancels and the clicks bought per day are the window's rate. v27.146 asked
    --   for EXACTLY w_clk (the window's clicks) by the verdict date; P-26 (v27.159) asks for that
    --   rate over the settle horizon instead, so the clicks and the date describe the same days.
    --   PROBE: seat_cost = the probe's price x click_goal_day, a goal the register already
    --   declares (P-25); P-26 asks for it over the settle horizon too.
    -- click_goal_day is read from the view rather than re-declared here, so the register stays the
    -- single owner of it.
    -- NULL ON EVERY ROW WITHOUT A SEAT: a row that took no seat asked no question, and writing a
    -- target on it would invent an intention the Brain never had.
    -- v27.159 (P-26, P-16): the question spans the settle horizon; an incumbent repeats its own.
    -- Computed in `questioned` above (q_clicks, q_cpc, q_implied, q_basis); NULL without a seat.
    p.q_clicks                                                                AS clicks_requested,
    -- THE DUE DATE IS THE SEAT'S OWN VERDICT DATE, NOT THE WINDOW'S END. window_to closes the
    -- window that was JUDGED (in the past — it is the evidence), while the seat funds the
    -- window ahead. The first cut used window_to and acceptance check S08 caught it on all 94
    -- seats: every request was already overdue on the day it was written. verdict_date is the
    -- date P-12 promises this seat will be judged on (an incumbent's is the one it was given).
    IF(p.seat_no IS NULL, NULL, p.verdict_date)                               AS clicks_due_date,
    p.q_cpc                                                                   AS expected_cpc,
    p.q_implied                                                               AS implied_daily_spend,
    p.q_basis                                                                 AS request_basis,
    -- v27.158 (P-22, audit fix #15): per family, on every row of the family
    fm.expected_after_upload_per_day,
    fm.share_closed,
    COALESCE(u.plan_uploads_landed, 0),
    -- v27.159 (P-16, P-25)
    p.seat_since, p.seat_tenure, p.is_probe
  FROM questioned p
  LEFT JOIN budgets b   ON b.plan = p.plan AND b.campaign_id = p.campaign_id
  LEFT JOIN first_seen fs ON fs.family = p.family
  LEFT JOIN fam_money fm ON fm.plan = p.plan AND fm.family = p.family
  LEFT JOIN uploads u    ON u.family = p.family;

  -- §9 guarantees, asserted on the rows about to be written, never on the partition after the
  -- fact. An assertion failure names the guarantee it broke — fix the arithmetic, never the
  -- assertion — and leaves the previous partition standing.
  ASSERT (SELECT COUNT(DISTINCT plan) FROM final) = 2
    AS 'both plans must be written every night (P-9)';
  -- v27.146: a seat without a question is not a seat (violation 27, §3.0 step 2).
  ASSERT (SELECT COUNTIF(seat_no IS NOT NULL
                         AND (clicks_requested IS NULL OR clicks_requested <= 0
                              OR clicks_due_date IS NULL OR request_basis IS NULL
                              OR clicks_due_date <= as_of_d))
          FROM final) = 0
    AS 'every seat names how many clicks, by a FUTURE date, and how the number was derived (violation 27)';
  ASSERT (SELECT COUNTIF(seat_no IS NULL
                         AND (clicks_requested IS NOT NULL OR clicks_due_date IS NOT NULL))
          FROM final) = 0
    AS 'a row that took no seat asked no question — no request without a seat';
  ASSERT (SELECT COUNTIF(side = 'GOOD' AND (move != 'NONE' OR planned_bid IS NOT NULL OR seat_cost_per_day IS NOT NULL))
          FROM final) = 0
    AS 'the good side is never cut, is not re-priced, and carries no executable price (P-4)';
  ASSERT (SELECT COUNTIF(seat_cost > allowance + 0.01) FROM (
            SELECT plan, family, SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)) seat_cost,
                   MAX(allowance_ramped_per_day) allowance
            FROM final GROUP BY 1, 2)) = 0
    AS 'seats must fit the ramped allowance (P-2, P-8)';
  -- the other half of the same walk: nothing affordable may be left in the queue (spec §4.4)
  ASSERT (SELECT COUNTIF(min_queued <= allowance - seat_cost + 0.0001) FROM (
            SELECT plan, family, MAX(allowance_ramped_per_day) allowance,
                   SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)) seat_cost,
                   -- a keyword the ladder has closed is not seatable at any price, so it is not
                   -- evidence of a prefix stop (v27.138)
                   MIN(IF(is_candidate AND seat_no IS NULL AND ladder_state != 'DEAD',
                          seat_cost_per_day, NULL)) min_queued
            FROM final GROUP BY 1, 2) WHERE min_queued IS NOT NULL) = 0
    AS 'the seat walk is a fit test: no seatable queued candidate may fit the allowance left over (§4.4)';
  -- the seat register is one authority, not two (§9) — for the LIVE plan, whose seats it registers
  -- (v27.159: the shadow plan numbers its own seats; see `seated`)
  ASSERT (SELECT COUNT(*)
          FROM final f
          JOIN (SELECT family, CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
                       MIN(seat_no) seat_no
                FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
                WHERE closed_on IS NULL GROUP BY 1, 2, 3) l
            ON l.family = f.family AND l.seat_no = f.seat_no
          WHERE f.seat_no IS NOT NULL AND f.is_live_plan AND l.kid != f.keyword_id) = 0
    AS 'no seat number the register still holds OPEN may be reissued to another keyword of the live plan (§9)';
  ASSERT (SELECT COUNTIF(seat_no IS NOT NULL AND (verdict_date IS NULL OR verdict_date <= as_of))
                + COUNTIF(seat_no IS NULL AND verdict_date IS NOT NULL) FROM final) = 0
    AS 'every SEAT carries a verdict date in the future, held or repriced (P-12)';
  -- P-14b / P-14c, AS THE JUDGE RULES THEM (v27.147, 2026-09-28). The v27.136 form of this
  -- assertion was `side = NOT_GOOD AND was_good AND served AND NOT settled` = 0 -- a copy of the
  -- guard's PRECONDITIONS, read as a veto. The judge (v27.138) reads P-14b as a CLOCK anchored to
  -- the window that triggered the hold, lifting when that window settles. The two agreed until
  -- the first clock expired (2026-08-29); from that night the view demoted a keyword its rule
  -- allowed and this line refused the whole partition, every night, for a month -- nothing
  -- downstream saw a plan newer than 08-28, and because nothing was written the judge's memory
  -- froze too, so the same rows failed forever. A guard that re-judges is the second engine
  -- P-11 forbids. The builder now asserts the judgement is COMPLETE, not that it agrees with a
  -- copy: every demotion of a keyword that was good, served and sits on an unsettled window
  -- carries the judge's own published release reason (HOLD_EXPIRED, or LAST_DAY_NOT_STRONG
  -- under Ori's 2026-09-17 ruling), and every row the judge holds is on the good side and
  -- earned the hold with a very good last day.
  -- P-18 (Ori 2026-10-02, R4; v27.156): a hold also lasts while the very good day that started
  -- its run is still inside the judged window, so the second assertion READS the judge's
  -- hold_kept_by: every HELD row names what keeps it held, and the named reason stands on the
  -- row (LAST_DAY with last_day_strong, or STRONG_DAY_IN_WINDOW with window_from <=
  -- hold_strong_day); a row that is not held names nothing.
  -- v27.169: the reason must be one the rulings NAME. Until v27.168 this line tested IS NULL
  -- only, so a row the judge published as UNEXPLAINED (its CASE's catch-all, kept so that a
  -- reordering of its arms fails loudly) passed here, and so did any unrecognised value.
  ASSERT (SELECT COUNTIF(side = 'NOT_GOOD' AND was_good AND served AND NOT settled
                         AND COALESCE(guard_released_by, '') NOT IN ('HOLD_EXPIRED', 'LAST_DAY_NOT_STRONG'))
          FROM final WHERE is_live_plan) = 0
    AS 'a keyword that was good and served on an unsettled window is demoted only with a judge-published release reason a ruling names: the hold clock expired (HOLD_EXPIRED) or its last day was not very good (LAST_DAY_NOT_STRONG); NULL, UNEXPLAINED or any other value refuses the partition (P-14b/P-14c)';
  ASSERT (SELECT COUNTIF(verdict = 'HELD_UNSETTLED'
                         AND (side != 'GOOD'
                              OR hold_kept_by IS NULL
                              OR NOT ((hold_kept_by = 'LAST_DAY' AND COALESCE(last_day_strong, FALSE))
                                      OR (hold_kept_by = 'STRONG_DAY_IN_WINDOW'
                                          AND COALESCE(window_from <= hold_strong_day, FALSE)))))
                + COUNTIF(verdict != 'HELD_UNSETTLED' AND hold_kept_by IS NOT NULL)
          FROM final WHERE is_live_plan) = 0
    AS 'every keyword the guard holds is on the good side and names what keeps it held: a very good last day (P-14c), or the very good day that started its hold still inside the window (P-18)';
  -- v27.158 (audit fix #11): the cap is a move too, so a holdout campaign's cap is not moved and
  -- says why (NO_MOVE_HOLDOUT), and no other campaign carries that basis.
  ASSERT (SELECT COUNTIF(holdout AND (move NOT IN ('NONE', 'NONE_HOLDOUT') OR seat_no IS NOT NULL))
                + COUNTIF(holdout AND (ABS(campaign_planned_budget_delta_per_day) > 0.005
                                       OR campaign_budget_basis != 'NO_MOVE_HOLDOUT'))
                + COUNTIF(NOT COALESCE(holdout, FALSE) AND campaign_budget_basis = 'NO_MOVE_HOLDOUT')
          FROM final) = 0
    AS 'a holdout campaign gets a record and no move: no keyword move, no seat, and its cap unchanged (NO_MOVE_HOLDOUT)';
  -- the band rule governs a cap the plan SETS. Leaving a cap exactly where it is, on a campaign
  -- the plan measured nothing in, a defense campaign or a holdout campaign, is not a move into the band.
  ASSERT (SELECT COUNTIF(campaign_planned_budget > 20.00 AND campaign_planned_budget < 32.00
                         AND campaign_budget_basis NOT IN
                             ('NO_MOVE_UNMEASURED', 'NO_MOVE_BRAND_DEFENSE', 'NO_MOVE_HOLDOUT'))
          FROM final) = 0
    AS 'no campaign budget the plan MOVES may land in the forbidden $20.01-$31.99 band';
  -- a budget that cannot pay for the money the plan can SEE is not a budget, it is a squeeze.
  -- v27.158: on a cap the plan MOVES. A cap left where it is (NO_MOVE_*) is not the plan's squeeze:
  -- on the 2026-10-02 partition 5 holdout campaigns' visible spend was above today's budget.
  ASSERT (SELECT COUNTIF(bud < need - 0.005) FROM (
            SELECT plan, campaign_id, MAX(campaign_planned_budget) bud,
                   MAX(campaign_budget_basis) basis,
                   SUM(planned_spend_per_day)
                   + SUM(IF(is_candidate AND seat_no IS NULL AND move != 'PAUSE',
                            COALESCE(SAFE_DIVIDE(w_sp, window_days), 0), 0)) need
            FROM final GROUP BY 1, 2)
          WHERE bud IS NOT NULL AND NOT STARTS_WITH(basis, 'NO_MOVE_')) = 0
    AS 'a campaign budget the plan moves may never sit under the money the plan can SEE inside it — its good side, its seats, and the queue parking does not stop (P-4)';
  -- v27.158 (audit fix #12): the basis says what bound the cap, and RAMPED is the ramp's number.
  -- need is recounted from the rows about to be written (4-decimal money), so the ramp value can
  -- round a cent the other way; the tolerance is that cent.
  ASSERT (SELECT COUNTIF(basis = 'RAMPED'
                         AND ROUND(ABS(bud - ROUND(COALESCE(cur, need) + (need - COALESCE(cur, need)) / steps, 2)), 4) > 0.01)
                + COUNTIF(basis IS NULL OR basis NOT IN ('RAMPED', 'FLOORED_AT_NEED', 'BAND_SNAPPED_UP',
                                                         'BAND_SNAPPED_DOWN', 'FLOORED_AT_MINIMUM',
                                                         'NO_MOVE_HOLDOUT', 'NO_MOVE_BRAND_DEFENSE',
                                                         'NO_MOVE_UNMEASURED'))
                + COUNTIF(n_basis > 1)
          FROM (
            SELECT plan, campaign_id, MAX(campaign_planned_budget) bud,
                   MAX(campaign_current_budget) cur, MAX(campaign_budget_basis) basis,
                   COUNT(DISTINCT campaign_budget_basis) n_basis, MAX(ramp_steps) steps,
                   SUM(planned_spend_per_day)
                   + SUM(IF(is_candidate AND seat_no IS NULL AND move != 'PAUSE',
                            COALESCE(SAFE_DIVIDE(w_sp, window_days), 0), 0)) need
            FROM final GROUP BY 1, 2)) = 0
    AS 'every campaign cap names the §4.7 rule that set it, and a RAMPED cap is ROUND(current + (need - current) / ramp_steps, 2) to the cent (audit fix #12)';
  -- unmeasured never reads as bad, and defense is never judged on profit (§8)
  ASSERT (SELECT COUNT(*) FROM (
            SELECT plan, campaign_id, MAX(campaign_planned_budget) bud,
                   MAX(campaign_current_budget) cur, MAX(campaign_visible_spend_per_day) vis,
                   SUM(COALESCE(w_clk, 0)) clk,
                   LOGICAL_OR(UPPER(COALESCE(campaign_name, '')) LIKE '%BRAND DEFENSE%') def
            FROM final GROUP BY 1, 2)
          WHERE cur IS NOT NULL AND bud < cur - 0.005
            AND ((vis <= 0.0001 AND clk = 0) OR def)) = 0
    AS 'a campaign the plan measured nothing in, and a brand-defense campaign, may never have its budget cut';
  -- the ladder's closed keywords hold no seat, no allowance and no price (§4.5)
  ASSERT (SELECT COUNTIF(ladder_state = 'DEAD'
                         AND (seat_no IS NOT NULL OR planned_bid IS NOT NULL
                              OR (is_candidate AND move != 'PAUSE')))
          FROM final) = 0
    AS 'a keyword the ladder has closed takes no seat, carries no price, and its move is PAUSE (§4.5)';
  -- §9 and P-28 (v27.159): A SEAT NUMBER IS STICKY, by the same precedence the numbering uses. A
  -- keyword the register holds open (live plan) keeps the register's number; any other keyword
  -- seated tonight that held a seat in an earlier partition keeps the number it held MOST RECENTLY
  -- (claims — last night's for a continuing occupant, an older one across an absence), unless (live
  -- plan) the register holds that number open for a different keyword, or another keyword seated
  -- tonight held it more recently. Until v27.158 this compared last night only, and read the
  -- register's exception at the moment of a rewrite: when the register let go of an old number
  -- between two passes of one night, a renumbering the first pass had made legitimately refused the
  -- second (4 refused passes, 2026-09-29 .. 10-02; see `seated`). The register's own number is the
  -- authority for a keyword it holds: on the first v27.159 dry run (2026-10-02, judgement snapshot
  -- OI._tmp_t5_judge), 24 live seats returning after an absence held a register number equal to the
  -- number the v27.158 partition of 2026-10-02 had given them, not their older claim (query: SOP §3,
  -- "Seat numbers").
  ASSERT (SELECT COUNT(*)
          FROM (SELECT f.plan, f.family, f.campaign_id, f.keyword_id, f.seat_no,
                       IF(f.is_live_plan, l0.led_seat_no, NULL) AS own_led,
                       c.claim_no, c.claim_as_of
                FROM final f
                LEFT JOIN led l0 ON l0.family = f.family AND l0.campaign_id = f.campaign_id
                                AND l0.keyword_id = f.keyword_id
                LEFT JOIN claims c ON c.plan = f.plan AND c.family = f.family
                                  AND c.campaign_id = f.campaign_id AND c.keyword_id = f.keyword_id
                WHERE f.seat_no IS NOT NULL
                  AND f.seat_no != COALESCE(IF(f.is_live_plan, l0.led_seat_no, NULL), c.claim_no)) x
          LEFT JOIN led l ON x.own_led IS NULL AND x.plan = live_plan_code AND l.family = x.family
                         AND l.led_seat_no = x.claim_no AND l.keyword_id != x.keyword_id
          LEFT JOIN (SELECT g.plan, g.family, g.keyword_id, g.seat_no, c2.claim_as_of
                     FROM final g
                     JOIN claims c2 ON c2.plan = g.plan AND c2.family = g.family
                                   AND c2.campaign_id = g.campaign_id AND c2.keyword_id = g.keyword_id
                     WHERE g.seat_no IS NOT NULL AND g.seat_no = c2.claim_no) y
            ON x.own_led IS NULL AND y.plan = x.plan AND y.family = x.family AND y.seat_no = x.claim_no
           AND y.keyword_id != x.keyword_id AND y.claim_as_of > x.claim_as_of
          WHERE l.family IS NULL AND y.family IS NULL) = 0
    AS 'a seated keyword keeps the register number it holds (live plan), else the seat number it held most recently, unless the register holds that number open for another keyword or another keyword seated tonight held it more recently (§9, P-28)';
  -- P-16 (v27.159): A SEAT IS HELD UNTIL ITS VERDICT DATE. Every incumbent — last partition's seat,
  -- written under P-16 (seat_since), before its date, still a candidate tonight and not closed —
  -- keeps the seat and its whole contract (number checked above; price, verdict date, the night it
  -- was taken, the question), or leaves only because tonight's allowance cannot carry every
  -- incumbent, latest-seated first (v27.167, below). No other row carries an incumbent's tenure.
  -- v27.164 (follow-up F2): the cost is not part of the contract. cost_tonight recounts it from the
  -- row about to be written — its kept price (prior_seat.held_bid) on tonight's window, click goal x
  -- kept price on a probe — and both the kept seat's cost and the eviction test read it (until
  -- v27.160 both read the cost the seat was granted at).
  -- v27.168 (follow-up G1): "a probe" is the KEPT QUESTION's basis (prior_seat.held_basis =
  -- 'HORIZON_PROBE_GOAL'), as in `ranked`.inc_cost, not tonight's is_probe (v27.164 .. v27.167).
  -- v27.167 (follow-up F8): AN EVICTION FOLLOWS THE SEAT ORDER. Incumbents leave latest-seated
  -- first until the rest fit, so in walk 1's order (held_since, then tonight's rank — inc_order's,
  -- recounted here as inc_pos) no incumbent that left comes before one that kept its seat, and the
  -- FIRST one that left did not fit what the kept ones leave of the allowance. Until v27.164 the
  -- test asked "did not fit" of EVERY incumbent that left: the fit test's own invariant, which
  -- passes a walk that sends an earlier, costlier incumbent out and keeps a later, cheaper one, and
  -- refuses the prefix, whose later leavers may be cheap enough to fit on their own.
  ASSERT (SELECT COUNTIF(f.seat_tenure = 'INCUMBENT'
                         AND (f.seat_no IS NULL
                              OR f.seat_since IS DISTINCT FROM ps.held_since
                              OR f.verdict_date IS DISTINCT FROM ps.held_verdict_date
                              OR ABS(COALESCE(f.planned_bid, -1) - COALESCE(ps.held_bid, -1)) > 0.005
                              OR ABS(COALESCE(f.seat_cost_per_day, -1) - ROUND(f.cost_tonight, 4)) > 0.0001
                              OR f.clicks_requested IS DISTINCT FROM ps.held_clicks
                              OR f.clicks_due_date IS DISTINCT FROM ps.held_due
                              OR f.request_basis IS DISTINCT FROM ps.held_basis))
                + COUNTIF(COALESCE(f.seat_tenure, '') != 'INCUMBENT'
                          AND (f.inc_pos < f.last_kept_pos
                               OR (f.inc_pos = f.first_left_pos
                                   AND NOT (f.cost_tonight > fa.allow - fa.kept + 0.0001))))
          FROM (SELECT f1.*,
                       MAX(IF(f1.seat_tenure = 'INCUMBENT', f1.inc_pos, 0))
                         OVER (PARTITION BY f1.plan, f1.family) AS last_kept_pos,
                       MIN(IF(COALESCE(f1.seat_tenure, '') != 'INCUMBENT', f1.inc_pos, NULL))
                         OVER (PARTITION BY f1.plan, f1.family) AS first_left_pos
                FROM (SELECT f0.*,
                             COALESCE(CASE WHEN ps0.held_basis = 'HORIZON_PROBE_GOAL'
                                             THEN g.click_goal_day * ps0.held_bid
                                           WHEN f0.w_sp > 0 AND COALESCE(f0.current_bid, 0) > 0
                                             THEN (f0.w_sp / f0.window_days) * SAFE_DIVIDE(ps0.held_bid, f0.current_bid)
                                           ELSE 0 END, 0) AS cost_tonight,
                             ROW_NUMBER() OVER (PARTITION BY f0.plan, f0.family
                                                ORDER BY ps0.held_since, f0.rank_no,
                                                         f0.campaign_id, f0.keyword_id) AS inc_pos
                      FROM final f0
                      JOIN prior_seat ps0 ON ps0.plan = f0.plan AND ps0.family = f0.family
                                         AND ps0.campaign_id = f0.campaign_id AND ps0.keyword_id = f0.keyword_id
                      LEFT JOIN j g ON g.campaign_id = f0.campaign_id AND g.keyword_id = f0.keyword_id
                      WHERE f0.is_candidate AND COALESCE(f0.ladder_state, '') != 'DEAD') f1) f
          JOIN prior_seat ps ON ps.plan = f.plan AND ps.family = f.family
                            AND ps.campaign_id = f.campaign_id AND ps.keyword_id = f.keyword_id
          JOIN (SELECT plan, family, MAX(allowance_ramped_per_day) allow,
                       SUM(IF(seat_tenure = 'INCUMBENT', seat_cost_per_day, 0)) kept
                FROM final GROUP BY 1, 2) fa ON fa.plan = f.plan AND fa.family = f.family)
        + (SELECT COUNT(*)
           FROM final f
           LEFT JOIN prior_seat ps ON ps.plan = f.plan AND ps.family = f.family
                                  AND ps.campaign_id = f.campaign_id AND ps.keyword_id = f.keyword_id
           WHERE f.seat_tenure IN ('INCUMBENT', 'LEFT_ALLOWANCE_SHRANK')
             AND (ps.keyword_id IS NULL OR NOT f.is_candidate OR f.ladder_state = 'DEAD'))
        + (SELECT COUNTIF((seat_no IS NOT NULL) != (COALESCE(seat_tenure, '') IN ('INCUMBENT', 'NEW'))
                          OR (seat_no IS NOT NULL) != (seat_since IS NOT NULL))
           FROM final) = 0
    AS 'an incumbent before its verdict date that is still a candidate keeps its seat and its contract, or leaves only when tonight allowance cannot carry every incumbent, latest-seated first until the rest fit (P-16)';
  -- P-25 (v27.159): a seated probe OPENS, an unseated probe gets no move, and only a probe does either.
  ASSERT (SELECT COUNTIF(is_candidate AND is_probe AND COALESCE(ladder_state, '') != 'DEAD'
                         AND seat_no IS NOT NULL AND move != 'OPEN_PROBE')
                + COUNTIF(is_candidate AND is_probe AND COALESCE(ladder_state, '') != 'DEAD'
                          AND seat_no IS NULL AND (move != 'NONE' OR planned_bid IS NOT NULL))
                + COUNTIF(move = 'OPEN_PROBE' AND NOT (is_candidate AND is_probe AND seat_no IS NOT NULL))
                + COUNTIF(is_candidate AND move = 'NONE' AND NOT COALESCE(is_probe, FALSE))
          FROM final) = 0
    AS 'a seated probe opens (OPEN_PROBE) and an unseated probe gets no move and no price (P-25)';
  -- P-24 (v27.160): one night is one calendar state — every row tonight carries the one state the
  -- judgement read (acceptance K2 reads the same on every written partition).
  ASSERT (SELECT COUNT(DISTINCT calendar_state) FROM final) = 1
         AND (SELECT COUNTIF(calendar_state IS NULL) FROM final) = 0
    AS 'every row of a night carries the one calendar state the judgement read (P-24)';

  -- R11's GUARD (P-24, Ori 2026-10-02: option (a) with option (c)'s guard; v27.160). A partition is
  -- never rewritten under a different calendar state than the one it was written under. Keyed on
  -- the New York date, the calendar is read on the same date as the key, so in normal operation
  -- this never fires; it is the net under any future change of either clock. The 2026-09-30
  -- partition is what it prevents: written as OFF_PEAK (7-day window, share 0.20) at 01:22 and
  -- 09:42 Los Angeles, then deleted and rewritten as BOOST (3-day window, share 0.50) by the 22:44
  -- Los Angeles pass, which was already 2026-10-01 in New York (audit 2026-10-02, BigQuery time
  -- travel). The refusal leaves the partition already written standing, like every ASSERT above,
  -- and the orchestrator's Task 20.8c logs it as a FAIL.
  SET tonight_state = (SELECT MAX(calendar_state) FROM final);
  SET written_state = (SELECT STRING_AGG(DISTINCT calendar_state, ' + ' ORDER BY calendar_state)
                       FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d);
  IF written_state IS NOT NULL AND written_state != tonight_state THEN
    RAISE USING MESSAGE = FORMAT(
      'partition %t was written under %s; tonight reads %s; refusing to rewrite (P-24 / R11: a night is keyed on the New York date and is never rewritten under another calendar state)',
      as_of_d, written_state, tonight_state);
  END IF;

  DELETE FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d;
  INSERT INTO `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` SELECT * FROM final;
END;
