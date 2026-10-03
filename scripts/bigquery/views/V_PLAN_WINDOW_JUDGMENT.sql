-- =============================================================================================
-- V_PLAN_WINDOW_JUDGMENT — v27.165 (2026-10-03, follow-up F3; v27.160, v27.157 and v27.156 2026-10-02; v27.147 2026-09-28): ONE ROW PER working-family keyword, carrying the
-- window, the window record (raw AND corrected for settle completion), the side BOTH plans give
-- it, the arm that decided it, the repaired price, the seat cost and the rank. It decides nothing
-- about money: the builder (SP_BUILD_NEXT_WEEK_PLAN) does the potting, seating and queueing. This
-- view is the JUDGEMENT, and it is a view so a person can read it at any moment without a pass.
--
-- THE UNIVERSE (spec §8, P-11): the HARVEST book's families, campaigns that are ENABLED today, no
-- brand defense (never judged on profit), no launch-contained keyword (the launch controller owns
-- those). Everything else in the account is outside this plan and is untouched by it.
--
-- THE WINDOW (P-10, P-13, P-14a). window_days complete days ending at
--   window_to = LEAST(watermark - 1, CURRENT_DATE('America/Los_Angeles') - 2)
-- where watermark = LEAST(MAX(date), FN_ADS_ANCHOR_CAP()) over FACT_AMAZON_ADS. The filling day
-- never enters a window (P-10), and neither does a day younger than two: FN_ADS_ANCHOR_CAP()
-- advances to the current LA date at 22:00 LA, so a late-evening run would otherwise admit an
-- age-1 day, whose SPEND the settle curve publishes as materially short of final — understating
-- the pot, the allowance and every seat cost in the same direction, with no error and no log line.
-- Before 22:00 LA the two terms are equal and the fence costs nothing. window_days, the allowance
-- share, the ramp and the ORDER FLOOR all come from DE_PLAN_CONFIG for the state
-- FN_PLAN_CALENDAR_STATE reads today — no setting is a literal in this file.
--
-- THE SIDE (P-1, P-3, P-5, P-14). Rule B judges the window, not the ladder's 90-day record. The
-- arms are tested in this order, and the order is doctrine, not taste:
--   GOOD        min_orders orders IN THE WINDOW and window gross profit per ad dollar at or above
--               the family bar. Order COUNTS are read as observed and are never inflated (P-14a:
--               a count cannot be fractionally corrected); the RETURN is read corrected.
--   GRACE (P-5) a ladder-settled winner (WINNER / PACED_WINNER) with a quiet window keeps the good
--               side for ONE window, held.
--               GRACE IS TESTED BEFORE THE GUARD (v27.135 repair). It used to sit after it, and
--               because every ladder-settled winner is by definition "was good", the guard reached
--               almost every winner with a quiet window first (measured on the deployed v27.134
--               view at the moment of this repair; the SOP publishes the query that re-reads it,
--               so no count is pinned here). Three things followed, all wrong:
--               the ruling that buys ONE window was replaced on those rows by the one that buys
--               every window and has no expiry, so P-5's limit could never bite for a keyword that
--               carries spend; the shipped reprice book (which tests grace first) named a DIFFERENT
--               ruling than this view on the same rows; and the published "unguarded"
--               counterfactual — what the pot and the allowance become if Ori drops the guard —
--               was wrong by that same money, in the direction that made the guard look more
--               expensive than it is, because dropping the guard drops those rows into GRACE, not
--               into the queue. SOP §2 publishes an equality query that verifies it now. Both rulings put the row on the GOOD side, so no money
--               moves with the order; what moves is which ruling answers for it, and whether the
--               limit Ori wrote can ever apply.
--               GRACE IS ONE WINDOW, NOT ONE NIGHT (v27.135 repair). The limit reads the live
--               plan's own history. Reading only LAST NIGHT, as v27.134 did, bought one NIGHT on
--               a plan that runs nightly, and made an unserved winner oscillate GOOD / NOT_GOOD /
--               GOOD every night — flipping the side that the P-14b memory and the T+14
--               scorecard both read. v27.135 then read "spent" as "the most recent GRACE is later
--               than the most recent GOOD", which granted grace for ONE nightly judgment and
--               refused it from the next night. P-17 (Ori, 2026-10-02, R3; built v27.156) makes
--               the grant last one WINDOW of nightly judgments: see THE JUDGE'S MEMORY below.
--               THE LIMIT ARMS FROM THE PLAN'S FIRST PARTITION EARLIER THAN TODAY (corrected
--               v27.138). SP_BUILD_NEXT_WEEK_PLAN ships and writes FACT_PLAN_NEXT_WEEK nightly at
--               orchestrator 20.8c, so grace_limit_armed reads FALSE only on a keyword the plan
--               has no EARLIER partition for — the day the first partition is written, and never
--               again after it. The sentence used to say "no builder writes that table until Task
--               2 ships", which stayed live in the deployed view and in config.yaml after the
--               builder shipped; it now says which condition is unmet and when it lifts (C22).
--   HELD_UNSETTLED (P-14b) a keyword that WAS good, THAT SERVED IN THE WINDOW, and now reads
--               not-good while its window has not settled (SP 7 / SB 14 complete days after
--               window_to). It keeps the good side, held. Promotion is allowed on fresh evidence;
--               only demotion waits. This is the ASYMMETRY.
--               THE GUARD IS A CLOCK, NOT A RATCHET (v27.138 repair). `was_good` reads last
--               night's SIDE, and a HELD row's side is GOOD — so one night under the guard wrote
--               the evidence that re-armed it the next night, while `settled` could never rescue
--               the row because the window ROLLS (window_to = the watermark - 1, so every night
--               brings a new unsettled window and settle_due_on is always ahead). The protected
--               side became a one-way door: a keyword could enter and never leave, the LADDER GATE
--               the spec attributes the guard to stopped applying after night one, and P-5's
--               one-window limit went inert in money because a keyword whose grace was spent fell
--               straight through into a permanent hold. The hold is now ANCHORED to the window
--               that triggered it: hold_since / hold_settles_on remember that window from the
--               plan's own history, and the guard lifts once its settle date has passed. This is
--               the literal reading of "not demoted until ITS WINDOW has settled" — one window,
--               which can settle. Promotion on fresh evidence is untouched and stays available
--               every night; the asymmetry is intact. Whether the delay should instead be an
--               unlimited veto is Ori's to rule (spec P-14, SOP §2).
--               THE GUARD REQUIRES SERVICE (v27.134 repair). P-14b exists because sales are still
--               ARRIVING. A keyword that took no spend and no clicks in the window has nothing in
--               flight, so there is no unsettled evidence to wait for and the guard has no basis.
--               Before this repair 11 such rows were held on the good side — where P-4 then forbids
--               re-pricing them — while their own settle_arm_sentence said, correctly, that the
--               settle question does not arise for them. Two published sentences contradicted each
--               other on the same row. Service is now a precondition of the guard, and C17 asserts
--               no HELD_UNSETTLED row has an empty window.
--               THE HOLD IS EARNED BY THE LAST DAY (P-14c, Ori 2026-09-17, built v27.147).
--               "The judge decides on losing or winning for the period: a keyword that was
--               losing but won a little on the last day is still not good. Only if the last
--               day was VERY good does it postpone its decision." So the guard is granted only
--               when the LAST complete day of the window (window_to) carried at least
--               strong_day_min_orders order(s) AND a corrected return of at least
--               strong_day_mult x the family bar (both read from DE_PLAN_CONFIG for today's
--               calendar state since v27.155; the k CTE declared them before). Otherwise the
--               window is judged as it reads and the row publishes guard_released_by =
--               LAST_DAY_NOT_STRONG; a hold whose anchored clock has run out publishes
--               HOLD_EXPIRED. The builder asserts every demotion under the guard's
--               preconditions carries one of those two reasons -- it checks the judgement is
--               COMPLETE and never re-derives the guard (P-11: one engine judges). That
--               matters because the builder's v27.136 copy of P-14b read it as a VETO while
--               this view read it as a clock; the two agreed until the first clock expired on
--               2026-08-29, and from that night the builder refused every partition for a
--               month. A consequence Ori should see: held_with_no_sale is now FALSE by
--               construction (a window that sold nothing cannot have a very good last day), so
--               the LARGEST population the guard used to hold is judged on the window.
--               THE RULE IS ON THE ROW (v27.154 follow-up, 2026-10-01). strong_day_mult and
--               strong_day_min_orders are published on every row, and SP_BUILD_NEXT_WEEK_PLAN
--               copies them into FACT_PLAN_NEXT_WEEK, so FN_PLAN_SCORECARD grades each hold and
--               release against the rule it was made under, never against today's setting. Only
--               the final SELECT changed. Measured at deploy, 2026-10-01: the view before (HEAD's
--               body run as a query) and after, keyed on campaign x keyword, 361 rows each side,
--               every published column equal except seat_cost_per_day on 2 rows, which moved by
--               0.0001 at its 4-decimal rounding (0.343 / 0.3429 and 1.0805 / 1.0804). Every row
--               carried 1.5 and 1.
--               THE RULE IS A SETTING WITH A HISTORY (v27.155, 2026-10-01). strong_day_mult and
--               strong_day_min_orders are no longer literals here: the cfg CTE reads them from
--               DE_PLAN_CONFIG with the other settings of today's calendar state, the win CTE
--               carries them, and a NULL raises an error instead of judging with no rule. A
--               change is Ori's retire-then-insert on DE_PLAN_CONFIG (SOP §1), its old value stays
--               in that table retired, and FACT_THRESHOLD_HISTORY records it the next orchestrator
--               pass. Only the k, cfg and win CTEs and one line of base changed; the seed carries
--               the 1.5 / 1 the k CTE carried. A NULL in the row of TODAY's state raises the
--               error; a NULL in another state's row does not, until that state comes round
--               (both run on TMP_ copies, 2026-10-01). Deploy DE_PLAN_CONFIG.sql BEFORE this
--               file: this body names columns the v27.154 table does not have.
--               Measured 2026-10-01 (LA), before deploy, on the same data: this body run as a
--               query on a TMP_ copy of DE_PLAN_CONFIG converted by its v27.155 DDL, against the
--               deployed v27.154 view run twice. 361 rows each; all 87 columns other than the key
--               equal (floats to 1e-9 relative) to the second run. The first run differed from
--               both on seat_cost_per_day on 2 rows at the 4th decimal: the deployed view's own
--               run-to-run noise. SP_BUILD_NEXT_WEEK_PLAN's body run on each output, partition
--               write removed: 722 rows each; side, verdict and guard_released_by differ on 0
--               rows; every other column but built_at equal, except rank_no on 4 rows (two pairs
--               whose rank_score ties to the last bit — rank_score differs in its last bit on 15
--               rows between two runs of the deployed view, so the tie order is not stable from
--               run to run). Both runs then stopped on the seat-number continuity assertion,
--               which also stopped the orchestrator's build at 2026-10-01 16:58 UTC.
--   LOSING / ONE_ORDER / NO_SALE / NOT_SERVING — the not-good side.
--
-- THE JUDGE'S MEMORY (v27.156, 2026-10-02: Ori's rulings R3, R4 and R16 of 2026-10-02, recorded
-- as spec P-17, P-18 and P-29, and audit fix #16). Four changes, all in plan_hist / prior / the
-- HELD arm / the published clock; the window, the correction, the price and the rank are untouched.
--   P-17 GRACE LASTS window_days NIGHTLY JUDGMENTS, anchored to the night it was granted. The run
--        in force starts at the first GRACE night after the last reset (a GOOD night, or a night
--        whose row says a gap cleared the grace memory, P-29); it lasts the window_days carried
--        by the plan row of that first night (a grace granted under a 7-day window keeps 7
--        nights after a switch to 3); prior_grace (= spent) is TRUE once
--        DATE_DIFF(today, grace_since) >= that length. grace_since / grace_window_days /
--        grace_ends_on are published and the GRACE sentence prints the last night.
--        "today" for this count is today_plan: the date FACT_PLAN_NEXT_WEEK.as_of is keyed on
--        (SP_BUILD_NEXT_WEEK_PLAN's as_of_d; the New York date since v27.160, P-24, the Los
--        Angeles date before it) — a count of nights must use the clock the nights are written on.
--   P-18 A HOLD LASTS WHILE THE VERY GOOD DAY THAT EARNED IT IS STILL IN THE JUDGED WINDOW, and
--        its clock has not run out. hold_strong_day = window_to of the hold run's first night;
--        the HELD arm reads last_day_strong OR (a hold run is in force AND window_from <=
--        hold_strong_day). hold_kept_by publishes which ('LAST_DAY' | 'STRONG_DAY_IN_WINDOW') so
--        the builder, V_ENGINE_HEALTH and every acceptance READ it; guard_released_by is
--        LAST_DAY_NOT_STRONG only when neither holds.
--   P-29 MEMORY ACROSS AN UNWRITTEN GAP IS CHECKED BEFORE IT IS HONOURED. A grace run whose last
--        GRACE night, or a hold run whose last night, is older than today_plan - window_days - 1
--        is checked against the nights after it that wrote no live row for the keyword (the gap):
--        each such night n would have judged the window ending n - 2 (the P-14a fence) of the
--        length its calendar state carries (FN_PLAN_CALENDAR_STATE(n) -> DE_PLAN_CONFIG), and
--        the windows ending after the memory's own window_to and before tonight's window_from
--        are read from FACT_AMAZON_ADS: GOOD = orders >= that state's min_orders AND raw gross
--        profit / spend >= tonight's family_bar (raw, not corrected: every such window ends
--        before tonight's window starts). If one reads GOOD the memory is cleared (no grace run,
--        no hold run) and the row publishes memory_cleared_by_gap and memory_gap_good_window_to;
--        SP_BUILD_NEXT_WEEK_PLAN stores the first, and plan_hist reads it back as a reset so the
--        clearing survives the next night (without it, tomorrow's history would rebuild the
--        same old run). One read of FACT_AMAZON_ADS, joined to those keywords' gap windows (bytes
--        processed by the whole view 2026-10-02: 127,048,011 for v27.155, 127,228,199 for this).
--   FIX #16 THE CLOCK IS PUBLISHED ON THE FIRST HELD NIGHT. hold_since / hold_settles_on /
--        hold_strong_day read the run from history and, on a first HELD night, today_plan /
--        tonight's settle_due_on / tonight's window_to. prior never reads hold_since from
--        history (only as_of, verdict, settle_due_on, window_to, window_days and
--        memory_cleared_by_gap), so publishing them cannot re-anchor a run. Run 2026-10-02 on a
--        TMP_ copy of the plan history with hold_since / hold_settles_on / hold_strong_day /
--        grace_since / hold_kept_by set to junk dates and LAST_DAY on every row: all 361 output
--        rows equal a run on the real history (verdict, both clocks, grace_since, prior_grace,
--        guard_released_by, sentence). On the history, the 9 hold runs started 09-28..10-01
--        each wrote hold_since NULL on night one and night one's as_of on night two.
-- MEASURED AT DEPLOY, 2026-10-02 (Los Angeles), on the same data (window 09-28..09-30, BOOST, 361
-- rows, w_sp equal on every row): the deployed v27.155 view snapshotted at 12:10 UTC against the
-- deployed v27.156 view at 12:46 UTC.
--   GRACE 4 -> 35: 25 keywords by P-17 (grace_since 09-28 under the 7-day window, through 10-04:
--   14; 09-30: 8; 10-01: 3) and 6 by P-29. HELD 0 -> 0. LAST_DAY_NOT_STRONG releases 10 -> 6
--   (the 4 are GRACE now), HOLD_EXPIRED 0 -> 0. prior_grace (spent) 59 -> 18 rows.
--   P-29 cleared 9 grace memories, every one written 08-23..08-28; the first GOOD gap window
--   ended 08-28..09-17; tonight 6 of them are GRACE, 2 GOOD on the window, 1 NO_SALE.
--   Sides: 31 keywords moved NOT_GOOD -> GOOD carrying $121.93/day of window spend (P-17 25 /
--   $102.75, P-29 6 / $19.18; $22.65/day of it on holdout rows); 0 moved the other way.
--   Persistence (a run with today's dates + 1 on the history SP_BUILD_NEXT_WEEK_PLAN v27.156
--   wrote): the 6 fresh graces stay GRACE with grace_since 10-02; on a copy of that history with
--   memory_cleared_by_gap nulled, all 6 read NO_SALE with their August grace spent.
--   Slot-seconds, three runs each as queries: the v27.155 body 631 / 657 / 681, this body 632 /
--   666 / 729; the new read of FACT_AMAZON_ADS (the gap chain, plan_hist0 .. gap_eval, run alone)
--   8 / 10 / 94. A first draft whose gap chain read win and ks ran at 2,988 (one run): every
--   reference to a CTE re-evaluates it, so that chain reads neither.
--
-- THE JUDGE'S PRICES AND RANKS (v27.157, 2026-10-02: Ori's rulings R5, R6 and R12 of 2026-10-02,
-- recorded as spec P-19, P-20 and P-25; piece-1 plan Task 3). Three changes, in the priced CTE, the
-- seat cost, the rank columns, the seat sentences and the final ORDER BY; the window, the sides, the
-- memory and the guard are untouched.
--   P-19 NO RAISE BELOW THE BAR. A non-probe row whose corrected return is under the family bar is
--        priced at LEAST(P-6's price, current bid); planned_bid_basis = P19_HELD_AT_CURRENT where P-6
--        would have raised it, repair_bid_p6 keeps P-6's price readable, and the seat cost follows
--        the gated price (it scales by planned / current). See the priced CTE for the floor case.
--   P-20 ZERO-SCORE CANDIDATES RANK BY MONEY BURNED WITH NO RETURN. rank_money_burned = spend per
--        day x GREATEST(0, 1 - return / bar) is published on every row; the final ORDER BY ranks
--        every candidate with no positive P-7 score below the positive ones, by it, ahead of clicks.
--        SP_BUILD_NEXT_WEEK_PLAN's ranked CTE still orders by clicks until plan Task 5 changes it.
--   P-25 A PROBE OPENS AT LIFT'S PROBE_START BID (the judge's half). probe_start_bid is LIFT's latest
--        single PROBE_START suggested_bid (FACT_ENGINE_PROPOSALS); a probe with one is priced at it,
--        capped at GREATEST(raise_ceiling, current bid), and costed at click_goal_day x that price.
--        A probe without one keeps P-6's price and says so. Whether an UNSEATED probe is parked or
--        left alone is the builder's half (plan Task 5); this view's queue clause is unchanged.
--   THE BOOK STILL PRICES BY P-6. tools/build_reprice_bulksheet.py mirrors P-6's cap constants, so
--   "the book and the plan cannot price the same keyword differently" (THE REPAIRED PRICE, below)
--   holds only on P6_REPAIR rows from v27.157: the book has no P-19 or P-25.
-- MEASURED BEFORE DEPLOY, 2026-10-02 (Los Angeles; 13:40-14:00 UTC), same data both sides (window
-- 09-28..09-30, BOOST, 361 rows): the deployed v27.156 view snapshotted, against this body run as a
-- query. Keyed on campaign x keyword, every published column equal except planned_bid (85 rows),
-- seat_cost_per_day (57) and sentence (49), plus the four new columns.
--   P-19 labelled 73 rows (Bottle 6, Fresh 16, LolliME 34, Lollibox 17), 37 of them candidates
--   (2 / 4 / 27 / 4); those 37 candidates' seat costs fell by $18.20 a day (0.08 / 2.11 / 10.94 /
--   5.07), the whole of what they were costed above their window spend; 0 candidates under the bar
--   still cost more than they spend.
--   P-25 repriced all 12 probes (Fresh 2, LolliME 9, Lollibox 1; every one NOT_SERVING and every
--   one with a LIFT price): 10 from $0.21 / $0.25 to $1.27 / $1.13, 1 SB probe $0.25 -> $1.05, and
--   1 Fresh probe $0.29 -> $0.27 (LIFT's own nomination; its preflight verdict was EXCLUDE). Probe
--   seat cost $9.80 -> $55.52 a day across the 12.
--   Candidate seat cost per family $/day: Bottle 0.78 -> 0.70, Fresh 59.88 -> 61.25, LolliME
--   150.49 -> 177.51, Lollibox 42.63 -> 41.84 (non-probe candidates 243.99 -> 225.79 in all).
--   P-20 moved 49 of the 76 candidates with no positive score (Fresh 15, LolliME 32, Lollibox 2);
--   each family's first such candidate is the same under both orders.
--   The builder's body (partition write removed, every ASSERT run) on each snapshot, live plan B:
--   seats (Bottle / Fresh / LolliME / Lollibox) 1/14/58/9 -> 1/18/54/9. Seats that raise spend
--   49 ($27.01/day: 33 that P-19 now holds $18.10, 10 probe seats costed at the floor $8.00, 6 at
--   or above the bar $0.91) -> 12 ($30.83/day: the same 6 at or above the bar $0.91, and 6 probe
--   seats at LIFT's bid $29.92). Probe seats 10 -> 6 (LolliME 9 -> 5: at ~$5/day a probe fits less).
--   Slot-seconds, three runs each as queries: the v27.156 body 833 / 985 / 1,270, this body 964 /
--   1,012 / 1,023; bytes 127,101,013 -> 127,661,417 (FACT_ENGINE_PROPOSALS; no new read of
--   FACT_AMAZON_ADS). The probe-price read alone: 0.5 slot-seconds, 560,404 bytes.
-- DEPLOYED 2026-10-02 14:12 UTC: the deployed view snapshotted at 14:13 equalled the pre-deploy run
-- on every column, all 361 rows; acceptance 30 of 30 PASS; the controls script exit 0 (34 copies).
-- SP_BUILD_NEXT_WEEK_PLAN's body (partition write removed) on the pre-deploy run's copy passed
-- every ASSERT, and the plan acceptance on that would-be partition read 26 of 26 PASS.
--
-- WHICH CLOCK KEYS A NIGHT (v27.160, 2026-10-02: Ori's ruling R11 of 2026-10-02, recorded as spec
-- P-24; piece-1 plan Task 6). One line changed: today.d_plan is CURRENT_DATE('America/New_York'),
-- the date `state` reads the calendar on, because SP_BUILD_NEXT_WEEK_PLAN v27.160 keys as_of on it.
-- Every read of the plan's history (plan_hist, armed: as_of < d_plan), every count of nights (P-17
-- grace, P-29's gap nights) and the first night a HELD or GRACE run publishes follow it. What stays
-- on Los Angeles is the ads clock: the window fence (window_to = LEAST(watermark - 1, d_la - 2)),
-- the settle ages, `settled`, the hold's settle clock (today_la > hold_settles_on, an ads date) and
-- the holdout date. So within one New York night the window can move a day between the 01:35 and
-- 04:10 New York passes: fresher evidence for the same night and the same calendar state.
-- Until v27.159 the ~22:35 Los Angeles pass judged on the next New York date's calendar while
-- reading the plan history and keying the partition on the Los Angeles date: on 2026-09-30 it
-- rewrote that day's OFF_PEAK partition as BOOST (audit 2026-10-02, time travel).
-- MEASURED 2026-10-02 19:36 Los Angeles (both dates 10-02), on the same data: this body run as a
-- query (OI._tmp_t6_judge) against the deployed v27.157 view (OI._tmp_t6_judge_old), keyed on
-- campaign x keyword: 361 rows each side, all 98 columns equal (floats to 1e-9 relative). The
-- change moves nothing while the two dates agree; after 21:00 Los Angeles it reads the plan history
-- through the Los Angeles day's partition, as the build keyed on the New York date requires.
-- MEASURED on a simulated 22:40 Los Angeles pass of 2026-10-02 (this body and the v27.157 body run
-- with the Los Angeles date 10-02, the New York date 10-03 and FN_ADS_ANCHOR_CAP 10-02 written in,
-- on a copy of the plan table holding the 10-02 partition SP_BUILD_NEXT_WEEK_PLAN v27.160 wrote at
-- 02:50 UTC; OI._tmp_t6_sim_judge against OI._tmp_t6_sim_judge_la): same window (09-28 .. 09-30,
-- BOOST, watermark 10-02), 361 rows each. The v27.157 body reads the history before 10-02 and is
-- about to rewrite 10-02; this one reads it through 10-02 and judges 10-03, one night later: GRACE 35
-- -> 27 — 8 grace runs count one more night and are spent (prior_grace differs on 9 rows): 6 go to
-- the not-good side (GRACE -> ONE_ORDER / NO_SALE: Bottle 1, LolliME 4, Lollibox 1; $27.68 a day of
-- window spend) and 2 LolliME are held instead (GRACE -> HELD_UNSETTLED: last night's GOOD side is
-- their "was good" and the guard comes after grace); HELD 0 -> 2; prior_good differs on 53 rows
-- (last night is 10-02, not 10-01). Slot-seconds: 401.6 (this body) and 694.2 (the
-- v27.157 body), one run each, 127,819,989 bytes each; no new read of FACT_AMAZON_ADS.
--
-- THE GRACE SENTENCE STATES THE ANCHORED RULE (v27.165, 2026-10-03, piece-1 follow-up F3; spec
-- P-17). The GRACE sentence said "A proven winner keeps the good side for ONE quiet window (P-5)"
-- and then granted the run's own length, which P-17 anchors to the window in force on the night
-- grace was granted. It now says "keeps the good side, held, not cut (P-5): grace lasts N nightly
-- judgments (the window length in force when it was granted, <grace_since>) through <grace_ends_on>".
-- The unarmed branch (no partition before tonight) says "THE GRACE LIMIT IS NOT ARMED TONIGHT" in
-- place of "THE ONE-WINDOW LIMIT". Only the sentence changed; no verdict, side, price or date.
-- MEASURED 2026-10-03 (Los Angeles and New York both 10-03; window 09-29 .. 10-01, BOOST, 3-day
-- window, 356 rows): the deployed v27.160 view snapshotted at 09:26 UTC (OI._tmp_f3_judge_old, 747.8
-- slot-seconds, 128,069,145 bytes) against this one deployed at 09:27 and snapshotted at 09:28
-- (OI._tmp_f3_judge_new, 666.4 slot-seconds, same bytes). Keyed on campaign x keyword: 356 rows each
-- side, 0 on one side only; of the 98 columns besides the key, 97 equal on every row (floats to 1e-9
-- relative), and `sentence` differs on 33 rows, the 33 GRACE rows. On each, the new sentence is the
-- old one with the rule phrase replaced and nothing else. 13 of the 33 are on a run of 7 nights granted
-- 2026-09-28 under a 7-day window, through 2026-10-04, while tonight's window is 3 days; before this
-- change they said "ONE quiet window" (e.g. Fresh 321715482318758: "grace lasts 7 nightly judgments
-- (the window length in force when it was granted, 2026-09-28) through 2026-10-04" now).
-- decided_by names the ruling that decided the row: P-3, P-14b or P-5. settle_arm names what the
-- correction did: SETTLED, CORRECTED, PROMOTED_ON_FRESH, HELD_UNSETTLED, NOT_CORRECTABLE_NO_GP,
-- UNCORRECTED_NO_CURVE.
--
-- AN ARM MUST NOT CLAIM WORK IT DID NOT DO (v27.134 repair, C17). The correction SCALES GROSS
-- PROFIT. A window with no gross profit at all — money spent, clicks taken, nothing sold — cannot
-- be corrected by any factor, because zero divided by anything is zero. Those rows used to fall
-- into the ELSE branch and print "the window record was corrected for the sales still arriving",
-- which was false on every one of them, and they are EXACTLY the population Ori described when he
-- raised the defect. They now carry their own arm, NOT_CORRECTABLE_NO_GP, and say in words that
-- only the order floor (P-3) or the guard (P-14b) can change their side. Read how many there are
-- and what they carry; do not take a number from this header:
--   SELECT settle_arm, COUNT(*) kw, ROUND(SUM(w_sp)/MAX(window_days), 2) sp_day
--   FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT` GROUP BY 1 ORDER BY 3 DESC;
--
-- "WAS GOOD" (P-14b) is last night's live-plan side IF THE PLAN HAS SEEN THIS KEYWORD, and only
-- otherwise the ladder's own settled record at or above the bar with min_orders settled orders.
-- v27.134 repair: this used to be an unconditional OR, which the header already described as a
-- fallback. The difference is invisible while FACT_PLAN_NEXT_WEEK is empty and decisive once Task 2
-- fills it: under the OR, a keyword the live plan demoted last night would be re-held every night
-- for as long as its 90-day ladder record cleared the bar, so the guard could never be worked off
-- and a demotion could never stick. prior_seen makes last night's plan the authority once it
-- exists, and leaves the ladder as the bootstrap it was always described to be.
--
-- HOW THE CORRECTION IS APPLIED, and one deliberate departure from the plan's sketch. The sketch
-- summed each day's gross profit divided by that day's own factor. That is right whenever a
-- window's days share a sign, and it is what this view computes in that case — but GROSS_PROFIT
-- can be negative on a day, and a window mixing a corrected positive day with an uncorrected
-- negative one can come out SMALLER in magnitude than the raw window, which breaks the §9
-- guarantee ("never smaller in magnitude") on live data rather than in theory. So the same
-- arithmetic is written as ONE division by a published effective factor:
--   settle_factor_eff = SUM(|gp_d|) / SUM(|gp_d| / f_d)   (a magnitude-weighted harmonic mean)
--   w_gp_corrected    = w_gp / settle_factor_eff
-- With every f_d <= 1 the effective factor is in (0, 1], so the correction can only ever RAISE
-- the magnitude and can never flip the sign — the guarantee holds by construction, for every
-- window, and the acceptance (C10) checks that corrected x settle_factor_eff reconstructs the raw
-- figure, so the correction remains ONE published, reversible division a reader can audit. When
-- every day of a window has the same sign this is ALGEBRAICALLY IDENTICAL to the sketch's sum.
--
-- THE GOOD SIDE CARRIES NO PRICE AND NO SEAT COST (P-4, v27.134 repair, C14). P-4 says the good
-- side is never cut and never re-priced. Before this repair the view published planned_bid and
-- seat_cost_per_day on EVERY row, good side included — an executable price sitting one column away
-- from a sentence reading "The good side is never cut and is not re-priced (P-4)", with only
-- is_candidate between that column and a move, and no acceptance check standing over it. Any
-- consumer that joined planned_bid without re-deriving the side would have re-priced good keywords,
-- some of them DOWN. planned_bid and seat_cost_per_day are now NULL whenever side_b = 'GOOD', and
-- C14 asserts it here, at the layer that publishes the number, rather than in Task 2.
--
-- A CONSEQUENCE ORI MUST SEE BEFORE HE RULES ON P-14, and it is not a bug in this file: the window
-- this view judges ALWAYS ends at window_to = today - 2 (the P-14a fence), and a window settles
-- settle_days AFTER window_to, so `settled` is FALSE on every row every night that the ads pipeline
-- is healthy. P-14b therefore does not delay a demotion — under a rolling window it PREVENTS one:
-- a keyword whose record clears its family bar cannot be moved to the not-good side by rule B at
-- all, whatever the window says, and no "judged again with no guard" date ever arrives, because the
-- next night judges a NEW unsettled window. That pulls rule B (P-1: the window decides the side)
-- back towards plan A (the ladder decides).
-- THE GUARD MOVES MONEY IN BOTH DIRECTIONS, AND BOTH BELONG ON THE PAGE (v27.134 disclosure
-- repair). Every earlier account of P-14b named only the first half: money taken OFF the seat
-- queue. But P-2 defines the pot as what the GOOD side actually spent, so the same held keywords
-- also RAISE the pot — and the allowance is a share of the pot. The guard therefore shrinks the
-- queue and enlarges the loss budget that queue is rationing, at the same time, from the same
-- rows. Read BOTH halves before arguing about the guard; the query is in
-- architecture/NEXT_WEEK_MONEY.md §2 under "THE OPEN QUESTION", and it now prints the pot and the
-- allowance guarded and unguarded, per family and for the book. The one-line fix, if Ori wants the
-- guard to be a DELAY and not a veto: demote on the last window that HAS settled (a second window
-- ending settle_days before window_to) while promoting on the fresh one — that is a change to
-- P-14b's evidence, and nobody has made it.
-- NOT EVERY HELD ROW IS WAITING FOR EVIDENCE, AND THERE ARE TWO KINDS, NOT ONE. Some held keywords
-- already MET the order floor in the window and still read under their family bar on CORRECTED
-- numbers: they are not quiet, they are losing, and the guard holds them anyway
-- (held_despite_evidence). The LARGER population by money is the other one: keywords that took
-- clicks, spent real money and SOLD NOTHING (held_with_no_sale). Their arm sentence used to read
-- "promotion is allowed on fresh evidence" — a promise the correction cannot keep, because it
-- scales gross profit and their window has none. This is the identical fact pattern the NOT-GOOD
-- side gets NOT_CORRECTABLE_NO_GP and an explicit sentence for; the only difference is that these
-- keywords' 90-day ladder records clear the bar, and until v27.135 the disclosure ran the opposite
-- way on the side carrying more money. Both flags are published, both sentences say it in words,
-- C20 asserts the second, and the SOP query counts and prices both. So "we do not know yet" is not
-- available as a reading of either.
--
-- A KEYWORD THAT DID NOT SERVE is not a keyword the curve failed on. Where the window holds no day
-- for a keyword there is nothing to correct and nothing in flight, so its empty record is already
-- final: the arm is SETTLED and the row says so in words. Reserving UNCORRECTED_NO_CURVE for rows
-- the curve genuinely could not answer keeps that label meaning something — it is the label that
-- tells Ori the plan is resting on the guard alone.
--
-- PLAN A (shadow, P-9) takes the side from the ladder state alone: WINNER, PACED_WINNER, AT_BAR
-- and the waiting states (TRIAL, PENDING_SETTLE, REVIVED_SETTLING) are its good side; REPRICE,
-- LOSER, FLOOR_PROBATION, PARKED and DEAD are not. The amounts are the same window amounts.
--
-- THE REPAIRED PRICE (P-6) is the ladder's affordable_bid, capped at three 5% steps in either
-- direction from the live bid, floored at the row's own bid_floor (the ONE floor definition,
-- FN_BID_FLOOR through the state table) and ceilinged at the house $2.00 for a raise. The cap
-- constants are mirrored from tools/build_reprice_bulksheet.py so the book and the plan cannot
-- price the same keyword differently. It is published on the NOT-GOOD side only (P-4, above).
-- v27.157: P-6's price is now repair_bid_p6; planned_bid is P-6's price gated by P-19 (no raise
-- below the bar) or replaced by P-25 (a probe opens at LIFT's bid) — see the priced CTE.
-- SEAT COST (P-6) is spend at THAT price, not last window's spend: the window's spend per day
-- scaled linearly by the price change (the same linear bid-to-spend guess the seat register uses
-- on its day-one horizon). A candidate with no window spend is priced at the engine's seat
-- economics — seat_cpc times the register's declared click goal per day; from v27.157 a probe with
-- a LIFT price is costed at click_goal_day x its opening price (P-25).
-- THE PARK PRICE has a fallback and says which one it used (v27.134 repair, C16). Spec §4 step 5
-- parks everything that does not win a seat at the channel park price. T_OOB_SEAT_ECONOMICS only
-- knows the keywords that entered OOB seat economics, so before this repair the park price was
-- NULL on most of the queue — a gap Task 2 would have discovered as a NULL, with no honesty column
-- and no check. bid_park now falls back to the row's OWN bid_floor (the house floor definition,
-- already on every row) and is never below it; bid_park_source declares which source answered
-- (SEAT_ECONOMICS / BID_FLOOR_FALLBACK / NONE) exactly as V_PLAN_SETTLE_COMPLETION.curve_available
-- declares it for the curve. bid_park_seat_econ keeps the raw seat-economics value so the coverage
-- gap stays visible and measurable. WHICH park price the plan SHOULD use is still one of Ori's open
-- rulings (spec §8); this repair makes the queue answerable, it does not make the ruling.
-- RANK (P-7) is written "dollars at stake times closeness to the bar" — window spend per day times
-- corrected return over the bar, ties broken by window clicks then by the keyword key.
-- THE TWO FACTORS ARE NOT TWO FACTORS: THE SPEND CANCELS, IDENTICALLY, ON EVERY ROW (v27.135
-- disclosure repair, C21). Return is gross profit DIVIDED BY spend, so
--   rank = (w_sp / window_days) x (w_gp_corrected / w_sp) / family_bar
--        = w_gp_corrected / (window_days x family_bar)
-- and window spend contributes NOTHING to the ordering. The seat queue is ordered by corrected
-- gross profit alone, rescaled by a constant per family. That is the exact inversion P-7's own
-- rationale exists to prevent ("closest first alone seats a $0.50/day keyword before a $50/day
-- one"): a keyword returning $3 of gross profit on $0.50/day outranks one returning $2 on
-- $50/day. Earlier versions of this header, the SOP and the spec all described a product of two
-- independent terms, and disclosed only the special case (rank = 0 when a keyword sold nothing),
-- which narrows a total collapse into an edge case. Both factors are now PUBLISHED separately —
-- rank_dollars_at_stake and rank_closeness — so the multiplication can be read rather than
-- trusted, C21 asserts the identity, and Ori can order by either factor while he rules.
-- P-7 SCORES ZERO WHEREVER THERE IS NO GROSS PROFIT, which is most of the queue: closeness to the
-- bar is zero when a keyword sold nothing, so a keyword burning real money with no order ranks
-- below every losing keyword and can never be seated for a repair. That is the same collapse seen
-- at its endpoint, and it is not silently absorbed: rank_is_degenerate is TRUE on every candidate
-- whose rank is zero, and the SOP publishes the count and the dollars it covers. The FORMULA is
-- Ori's ruling and is untouched here; what changed is that it is now described correctly. Ori
-- rules whether to park the no-sale keywords, or to make "dollars at stake" real by ranking on the
-- gross-profit SHORTFALL per day (spend/day x (bar - return)/bar), which does not cancel; until he
-- does, the ordering is corrected gross profit and then falls through to clicks and the key.
-- RULED 2026-10-02 (R6, spec P-20; built v27.157): P-7's score stands for every candidate it scores
-- above zero; the candidates with no positive score rank below them by rank_money_burned (that
-- shortfall, floored at 0), and clicks are only the tiebreak after it.
--
-- CANDIDACY (§4 step 3). A candidate is a not-good keyword that is not in the holdout AND has
-- something to repair: losing, one order, or spend with no sale. A keyword that took no spend and
-- no clicks in the window has no repair to buy and is NOT a candidate unless the probe list
-- nominates it (LIFT's probes stay a candidate SOURCE under P-11). Otherwise every dormant
-- keyword in the book would queue for a zero-cost seat and bury the ranking the seats exist for.
-- THE SENTENCE AND THE COLUMN NOW COME FROM THE SAME EXPRESSION (v27.135, C18/C19). is_candidate
-- is computed once, in `final`, and the seat clause branches on it first. Before this repair the
-- clause branched on holdout membership first, so dormant keywords in holdout campaigns read
-- "it competes for a seat at the repaired price $X today" while their own is_candidate said no —
-- and others read "only if the probe list nominates it", which it does not. That left most of
-- the not-good rows with neither a seat nor a queue position named anywhere, against §9's
-- promise that every not-good keyword has exactly one of them. §9's guarantee is about CANDIDATES:
-- a keyword with no spend, no clicks and no nomination has nothing to repair, so it takes no seat
-- AND no queue position, and its row now says exactly that instead of implying a seat.
-- THE HOLDOUT IS NAMED IN WORDS, NOT ONLY IN A COLUMN (v27.134 repair, C15). holdout is TRUE only
-- from the campaign's eligible_from, so a holdout campaign judged BEFORE that date is a candidate
-- today and silent tomorrow. The sentence used to promise those rows a seat with no mention of the
-- holdout, and C13 passed only because no campaign was eligible yet — a vacuous check on exactly
-- the arm that would break. holdout_member is TRUE for membership at any date, the sentence names
-- the holdout and its date wherever it names a seat, and C15 asserts it on the live rows today.
--
-- Planner note: every source here is a snapshot table or a small view. The ceiling views are read
-- only through their T_ tables (T_OOB_SEAT_ECONOMICS, T_LIFT_PROBES), per the house rule.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §3, §3a, §4, P-1..P-14.
-- SOP: architecture/NEXT_WEEK_MONEY.md §2.
-- Acceptance: scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql.
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
OPTIONS (description = "v27.165 (2026-10-03, piece-1 follow-up F3, spec P-17): the GRACE sentence states the anchored rule -- 'grace lasts N nightly judgments (the window length in force when it was granted, <date>) through <date>' -- where it said 'keeps the good side for ONE quiet window (P-5)' while granting the run's own length: on 2026-10-03 all 33 GRACE rows said it, 13 of them on a 7-night run granted 2026-09-28 under tonight's 3-day window. The unarmed branch says 'THE GRACE LIMIT' (it said 'THE ONE-WINDOW LIMIT'). Only the GRACE rows' sentence changed. v27.160 (2026-10-02, piece-1 plan Task 6, ruling R11 = spec P-24): a night is keyed on the New York date. today_plan -- the date the plan history is read before (plan_hist, armed: as_of < today_plan), the night every P-17 grace count and P-29 gap is counted on, and the first night a HELD or GRACE run publishes -- is CURRENT_DATE('America/New_York'), the date the calendar state is read on, because SP_BUILD_NEXT_WEEK_PLAN v27.160 keys as_of on it; the ads clock (the window fence, settle ages, settled, the hold's settle clock, the holdout date) stays on Los Angeles. While the two dates agree the output is unchanged (98 columns x 361 rows equal to the deployed v27.157 view, 2026-10-02 19:36 Los Angeles). v27.157 (2026-10-02, piece-1 plan Task 3): the judge's prices and ranks, Ori's rulings of 2026-10-02 R5 / R6 / R12 (spec P-19, P-20, P-25). P-19: a non-probe row whose corrected return is under the family bar is never priced above its current bid -- planned_bid = LEAST(P-6 price, current bid), even where the current bid is under the row's floor (holding it uploads nothing) -- and its seat cost follows that price; planned_bid_basis (P6_REPAIR | P19_HELD_AT_CURRENT | P25_LIFT_PROBE_START | P6_PROBE_NO_LIFT_PRICE) and repair_bid_p6 (P-6's own price) are published. P-20: rank_money_burned = window spend per day x GREATEST(0, 1 - corrected return / bar) is published, and the view orders every candidate with no positive P-7 score below the positive ones by it, ahead of clicks (ORDER BY GREATEST(rank_score, 0) DESC, rank_money_burned DESC, w_clk DESC, keys); SP_BUILD_NEXT_WEEK_PLAN still ranks by clicks until plan Task 5. P-25 (the judge's half): a probe whose keyword carries one LIFT PROBE_START suggested_bid in the latest FACT_ENGINE_PROPOSALS snapshot (probe_start_bid) is priced at it, capped at GREATEST(2.00, current bid), and costed at click_goal_day x that price; a probe without one keeps P-6's price and says so; P-19 does not apply to probes. Every seat sentence names its price through the rule that set it. v27.156 (2026-10-02): the judge's memory, Ori's rulings of 2026-10-02 (spec P-17, P-18, P-29) and audit fix #16. P-17: grace lasts window_days nightly judgments from the night it was granted (the window length carried by that night's plan row), then is spent until a GOOD window; grace_since / grace_window_days / grace_ends_on are published and the GRACE sentence prints the last night. P-18: a hold lasts while the very good day that started its run (hold_strong_day = that night's window_to) is still inside the judged window, never past its clock; hold_kept_by (LAST_DAY | STRONG_DAY_IN_WINDOW) is published so the builder, V_ENGINE_HEALTH and the acceptance read it; guard_released_by is LAST_DAY_NOT_STRONG only when neither holds. P-29: a grace or hold memory whose last night is older than today - window_days - 1 is checked against the windows the unwritten nights after it would have judged (FACT_AMAZON_ADS, the judge's GOOD on raw numbers, window length per night's calendar state, ending before tonight's window_from); a GOOD one clears it, published as memory_cleared_by_gap / memory_gap_good_window_to, stored by SP_BUILD_NEXT_WEEK_PLAN and read back by plan_hist as a reset. Fix #16: hold_since / hold_settles_on / hold_strong_day are published from the first HELD night. Nights are counted on today_plan, the clock FACT_PLAN_NEXT_WEEK.as_of is keyed on (the New York date since v27.160). Reads FACT_PLAN_NEXT_WEEK.memory_cleared_by_gap: deploy migration 2026-10-02_plan_judge_memory_columns.sql first. v27.155 (2026-10-01): strong_day_mult and strong_day_min_orders, the P-14c last-day test, are read from DE_PLAN_CONFIG for today's calendar state (cfg CTE) instead of being literals in the k CTE, so the rule is a setting Ori changes by retire-then-insert, with its old values kept; a NULL raises an error rather than judge with no rule; the seed carries the 1.5 / 1 the k CTE carried. v27.154 follow-up (2026-10-01): publishes strong_day_mult and strong_day_min_orders (the P-14c settings of the k CTE) on every row so SP_BUILD_NEXT_WEEK_PLAN stores the rule each decision was judged under and FN_PLAN_SCORECARD grades against it; no verdict changes. v27.147 (2026-09-28) P-14c (Ori, 2026-09-17): the P-14b hold is granted ONLY when the last complete day of the window was very good -- at least 1 order and a corrected return of at least 1.5x the family bar, declared in the k CTE -- so a losing window whose last day won a little is judged on the window. Publishes last_day_sp/clk/ord/gp/gp_corrected/ret, last_day_strong and guard_released_by (LAST_DAY_NOT_STRONG | HOLD_EXPIRED) so SP_BUILD_NEXT_WEEK_PLAN asserts every demotion under the guard's preconditions carries this view's own reason instead of re-deriving the guard: the builder's v27.136 copy read P-14b as a veto while this view read it as a clock, and from the first expired clock (2026-08-29) the builder refused every partition for a month. held_with_no_sale is now FALSE by construction. Earlier: one row per working-family (HARVEST) keyword — the complete-days window from DE_PLAN_CONFIG for today's calendar state, fenced so no judged day is younger than age 2 (P-10 + P-14a), the keyword's record in it raw AND corrected for settle completion via V_PLAN_SETTLE_COMPLETION, the side rule B gives it (P-1/P-3), and the arms in the order P-5 then P-14b: the grace for a ladder-settled winner with a quiet window comes FIRST (v27.135 — with the guard first it reached 36 of 39 such winners, so the ruling that buys ONE window was replaced by the one that buys every window, the shipped reprice book named a different ruling on the same rows, and the published unguarded counterfactual was wrong by 28% of the pot), and the grace limit is ONE WINDOW read from the live plan's own history — spent until the keyword earns a GOOD window back — with grace_limit_armed publishing whether the plan has a partition EARLIER than today to read it from (v27.138: SP_BUILD_NEXT_WEEK_PLAN ships and writes that table nightly, so the old wording 'no builder writes it yet' was live and false in this description and in the row's own sentence). Then the P-14b asymmetric guard (promote on fresh evidence, never demote until the window has settled: SP 7 / SB 14; the guard requires that the keyword actually SERVED, because a keyword with no clicks has no sales in flight; and v27.138 gives the hold a CLOCK — it is anchored via hold_since / hold_settles_on to the window that TRIGGERED it and lifts when that window settles, because was_good reads last night's side and a held row's side is GOOD, which made the protected side a one-way door no keyword could ever leave and left P-5's one-window limit inert in money), with held_despite_evidence AND held_with_no_sale naming the two populations it holds — the second is the larger by money and used to be told that promotion is allowed on fresh evidence on a window with no gross profit to promote. Also the shadow plan A side (P-9), the repaired price capped at three 5% steps and floored at the row's own bid_floor (P-6) published on the NOT-GOOD side only because P-4 forbids re-pricing the good side, the seat cost at that price, the park price with a declared source and a bid_floor fallback, and the P-7 rank — whose two named factors are published separately (rank_dollars_at_stake, rank_closeness) because their product cancels the spend identically and the ordering is corrected gross profit alone. Every seat sentence branches on is_candidate, so no row is promised a seat its own column refuses it and a keyword with no seat and no queue position says so. Publishes settle_arm, decided_by and two plain sentences on every row. Judges only; SP_BUILD_NEXT_WEEK_PLAN does the potting, seating and queueing. Spec P-1..P-14, §3a. SOP: architecture/NEXT_WEEK_MONEY.md")
AS
WITH k AS (
  -- P-3/P-13: min_orders is NOT a literal — it is read from DE_PLAN_CONFIG in the cfg CTE below
  -- and joined in. Writing `2 AS min_orders` here would put the order floor in two places that
  -- can disagree, which is the exact defect DE_PLAN_CONFIG exists to prevent.
  SELECT 0.05   AS material_step,     -- mirrored from tools/build_reprice_bulksheet.py MATERIAL_STEP
         3      AS blind_steps,       -- ...and BLIND_STEPS: the engine's blind run before a re-read
         2.00   AS raise_ceiling,     -- the house bid ceiling (GUARDIAN threshold redesign)
         4      AS click_goal_day,    -- mirrored from V_FAMILY_SEAT_REGISTER k.click_goal_day
         7      AS settle_days_sp,    -- SP attribution window, complete days (P-12, P-14b)
         14     AS settle_days_sb     -- SB attribution window, complete days
         -- P-14c's strong_day_mult and strong_day_min_orders are read from DE_PLAN_CONFIG in the
         -- cfg CTE (v27.155), like min_orders: a literal here would be a second copy of the rule.
),
caps AS (
  SELECT k.*,
         POW(1 + k.material_step, k.blind_steps) - 1 AS cap_up,
         1 - POW(1 - k.material_step, k.blind_steps) AS cap_down
  FROM k
),
today AS (
  SELECT CURRENT_DATE('America/Los_Angeles') AS d_la,
         CURRENT_DATE('America/New_York')    AS d_ny,
         -- the clock FACT_PLAN_NEXT_WEEK.as_of is keyed on (SP_BUILD_NEXT_WEEK_PLAN as_of_d): every
         -- read of the plan's history and every count of nights uses it (v27.156). P-24 (Ori
         -- 2026-10-02, R11 option (a); v27.160, piece-1 plan Task 6): the NEW YORK date, the date the
         -- calendar state is read on (state, below) — so one night is one calendar state. d_la stays
         -- the clock of the ads days: the window fence, the settle ages, `settled` and the hold's
         -- settle clock.
         CURRENT_DATE('America/New_York')    AS d_plan
),
cfg AS (
  -- Every setting, min_orders included. Copy this CTE, not a subset of it.
  SELECT calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders,
         strong_day_mult, strong_day_min_orders
  FROM `onyga-482313.OI.DE_PLAN_CONFIG`
  WHERE is_active
  QUALIFY ROW_NUMBER() OVER (PARTITION BY calendar_state ORDER BY updated_at DESC) = 1
),
state AS (
  SELECT `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(t.d_ny) AS calendar_state
  FROM today t
),
wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
win AS (
  -- P-10 + the P-14a FENCE (see the header).
  SELECT s.calendar_state, c.window_days, c.allowance_share, c.live_plan, c.ramp_steps,
         c.min_orders,
         -- P-14c (v27.155): the rule is a setting. NULL is not one: refuse to judge without it.
         COALESCE(c.strong_day_mult, ERROR(FORMAT(
           'DE_PLAN_CONFIG: the active %s row has no strong_day_mult (P-14c); retire it and insert a row that carries one (SOP: architecture/NEXT_WEEK_MONEY.md section 1)',
           s.calendar_state)))                                 AS strong_day_mult,
         COALESCE(c.strong_day_min_orders, ERROR(FORMAT(
           'DE_PLAN_CONFIG: the active %s row has no strong_day_min_orders (P-14c); retire it and insert a row that carries one (SOP: architecture/NEXT_WEEK_MONEY.md section 1)',
           s.calendar_state)))                                 AS strong_day_min_orders,
         wm.d                                                  AS watermark,
         LEAST(DATE_SUB(wm.d, INTERVAL 1 DAY),
               DATE_SUB(t.d_la, INTERVAL 2 DAY))               AS window_to,
         DATE_SUB(LEAST(DATE_SUB(wm.d, INTERVAL 1 DAY),
                        DATE_SUB(t.d_la, INTERVAL 2 DAY)),
                  INTERVAL c.window_days - 1 DAY)              AS window_from
  FROM state s
  JOIN cfg c USING (calendar_state)
  CROSS JOIN wm
  CROSS JOIN today t
),
books AS (
  SELECT family, book FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'
),
snap AS (
  SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
),
camp AS (
  -- one row per campaign, chosen deterministically (never a pair of ANY_VALUEs)
  SELECT CAST(campaign_id AS STRING) AS cid, campaign_state, daily_budget, portfolio_id
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(campaign_id AS STRING)
                             ORDER BY effective_from DESC, campaign_name) = 1
),
ks AS (
  SELECT s.*, b.book
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN snap ON s.snapshot_date = snap.d
  JOIN books b ON b.family = s.family
  JOIN camp c ON c.cid = CAST(s.campaign_id AS STRING)
  WHERE NOT COALESCE(s.is_brand_defense, FALSE)
    AND s.state != 'LAUNCH_CONTAINED'
    AND UPPER(COALESCE(c.campaign_state, 'ENABLED')) = 'ENABLED'
),
-- the window record, PER DAY, so each day can be corrected at its own age (P-14a)
fdays AS (
  SELECT CAST(f.campaign_id AS STRING) AS cid,
         CAST(f.keyword_id AS STRING)  AS kid,
         f.date,
         f.campaign_type               AS ch,
         SUM(f.Ads_cost)     AS sp,
         SUM(f.Ads_clicks)   AS clk,
         SUM(f.Ads_orders)   AS ord,
         SUM(f.GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  CROSS JOIN win
  WHERE f.date BETWEEN win.window_from AND win.window_to
    AND f.keyword_id IS NOT NULL
  GROUP BY 1, 2, 3, 4
),
rec AS (
  SELECT d.cid, d.kid,
         SUM(d.sp)  AS w_sp,
         SUM(d.clk) AS w_clk,
         SUM(d.ord) AS w_ord,
         SUM(d.gp)  AS w_gp,
         -- P-14a: the magnitude-weighted effective factor (see the header). COALESCE to 1.0 so a
         -- missing curve row can never drop a day out of the sum.
         SUM(ABS(d.gp))                                             AS w_absgp,
         SUM(SAFE_DIVIDE(ABS(d.gp), COALESCE(sc.sales_completion, 1.0))) AS w_absgp_corrected,
         MIN(COALESCE(sc.sales_completion, 1.0))                    AS settle_factor_min,
         LOGICAL_AND(COALESCE(sc.curve_available, FALSE))           AS settle_curve_available,
         MIN(DATE_DIFF(t.d_la, d.date, DAY))                        AS min_age_days,
         -- P-14c: the LAST complete day of the window on its own, raw and corrected with the
         -- same per-day factor, so the judgement can ask whether that day was very good.
         SUM(IF(d.date = w.window_to, d.sp,  0))                    AS ld_sp,
         SUM(IF(d.date = w.window_to, d.clk, 0))                    AS ld_clk,
         SUM(IF(d.date = w.window_to, d.ord, 0))                    AS ld_ord,
         SUM(IF(d.date = w.window_to, d.gp,  0))                    AS ld_gp,
         SUM(IF(d.date = w.window_to,
                SAFE_DIVIDE(d.gp, COALESCE(sc.sales_completion, 1.0)), 0)) AS ld_gp_corrected
  FROM fdays d
  CROSS JOIN today t
  CROSS JOIN win w
  LEFT JOIN `onyga-482313.OI.V_PLAN_SETTLE_COMPLETION` sc
    ON sc.channel = d.ch
   AND sc.age_days = LEAST(DATE_DIFF(t.d_la, d.date, DAY), 120)
  GROUP BY 1, 2
),
-- P-14b memory AND P-5's one-window limit, read from the LIVE plan's own history. Empty until
-- Task 2's builder runs, by design. prior_seen is the "if there is one" the header has always
-- promised: once the plan has judged a keyword, LAST NIGHT's plan is the authority on whether it
-- was good, and the ladder is only the bootstrap for a keyword the plan has never seen.
-- P-5'S LIMIT IS ONE WINDOW, NOT ONE NIGHT (v27.135 repair). Reading grace from last night alone
-- would buy exactly one NIGHT of grace on a plan that runs nightly over a rolling window, and it
-- would make an unserved winner oscillate GOOD / NOT_GOOD / GOOD every night: grace granted,
-- refused because last night granted it, then granted again because the night before last is not
-- read. v27.135 therefore read grace as SPENT from the night after it was granted until the
-- keyword earned a GOOD window back (the most recent GRACE later than the most recent GOOD) —
-- one nightly judgment of grace. P-17 (v27.156, R3) keeps the "spent until a GOOD window" half and
-- makes the grant last window_days nightly judgments from its first night: grace_since is the
-- first GRACE night after the last reset, and the run is spent once it has lasted the window
-- length carried by that first night's plan row. A reset is a GOOD night (the run may start the
-- night after) or a night whose row records that a gap cleared the grace memory (P-29; the run
-- may start that night).
-- P-14b IS A DELAY WITH A CLOCK, NOT A ONE-WAY RATCHET (v27.138 repair). The guard's own memory
-- made it permanent. `was_good` reads last night's SIDE, and side is GOOD for a HELD row — so one
-- night under the guard wrote the evidence that re-armed the guard the next night, and `settled`
-- can never rescue it because the window ROLLS: window_to is the watermark - 1, so every night
-- brings a brand-new unsettled window and settle_due_on is always in the future. Measured before
-- the repair on the first live partition: `settled` was FALSE on every row, and every keyword the
-- plan had put on the good side once satisfied the HELD_UNSETTLED branch unconditionally
-- thereafter, P-4 then forbidding any cut or re-price. Two things followed. The LADDER GATE the
-- spec attributes the guard to ("a keyword whose ladder record clears its family bar") stopped
-- applying after night one — the plan's own memory replaced it. And P-5's one-window limit went
-- inert in money: a keyword whose grace was spent fell straight through into a permanent hold, so
-- the armed sentence's promise that "rule B stands on the next quiet one" could never come true.
-- THE CLOCK. P-14b says a keyword is not demoted "until its window has settled". That is a
-- statement about ONE window — the window that produced the adverse read — and it can only be
-- honoured by remembering which one. So the hold is anchored: the first night of a hold run
-- records that window's settle_due_on, and the guard holds until that date passes. Promotion is
-- untouched and stays available every night (the asymmetry is the whole ruling). After the anchor
-- date the window that triggered the hold HAS settled, its sales have landed, and rule B judges on
-- the numbers. A keyword that earns the good side back starts a fresh clock on its next bad
-- window. Whether the delay should instead be a veto is Ori's to rule (spec P-14, SOP §2).
-- P-18 (v27.156, R4): the run also remembers the very good day that started it (hold_strong_day =
-- window_to of the run's first night), and the hold lasts while that day is still inside the
-- judged window — never past the clock above.
-- A hold run starts the night after the last night this keyword was NOT held, or ON a night whose
-- row records that a gap cleared the hold memory (P-29).
plan_hist0 AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         as_of, side, verdict, settle_due_on, window_to, window_days, memory_cleared_by_gap,
         MAX(as_of) OVER k AS last_as_of,
         -- the earliest night the grace run in force may start on (P-17, P-29)
         MAX(CASE WHEN verdict = 'GOOD' THEN DATE_ADD(as_of, INTERVAL 1 DAY)
                  WHEN memory_cleared_by_gap IN ('GRACE', 'GRACE_AND_HOLD') THEN as_of END)
           OVER k AS grace_from,
         -- the earliest night the hold run in force may start on (v27.138, P-29)
         MAX(CASE WHEN verdict != 'HELD_UNSETTLED' THEN DATE_ADD(as_of, INTERVAL 1 DAY)
                  WHEN memory_cleared_by_gap IN ('HOLD', 'GRACE_AND_HOLD') THEN as_of END)
           OVER k AS hold_from
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan AND as_of < (SELECT d_plan FROM today)
  WINDOW k AS (PARTITION BY CAST(campaign_id AS STRING), CAST(keyword_id AS STRING))
),
plan_hist AS (
  SELECT h.*,
         (h.verdict = 'GRACE'          AND (h.grace_from IS NULL OR h.as_of >= h.grace_from)) AS in_grace_run,
         (h.verdict = 'HELD_UNSETTLED' AND (h.hold_from  IS NULL OR h.as_of >= h.hold_from))  AS in_hold_run
  FROM plan_hist0 h
),
-- the memory as the plan's history holds it, BEFORE the P-29 gap test (base2 applies that test,
-- because it needs tonight's window_from and family bar, which only base carries). Each value
-- of a run is read from the run's own first or last night (as_of is unique per keyword in the
-- live plan, so ORDER BY as_of LIMIT 1 is deterministic).
prior0 AS (
  SELECT cid, kid,
         TRUE AS prior_seen,
         LOGICAL_OR(side = 'GOOD' AND as_of = last_as_of)                             AS prior_good,
         MAX(IF(verdict = 'GRACE', as_of, NULL))                                      AS last_grace_on,
         MIN(IF(in_grace_run, as_of, NULL))                                           AS grace_since,
         -- P-17: the window length in force on the night grace was granted, from that night's row
         ARRAY_AGG(IF(in_grace_run, window_days, NULL) IGNORE NULLS ORDER BY as_of LIMIT 1)[SAFE_OFFSET(0)]
                                                                                      AS grace_window_days,
         MAX(IF(in_grace_run, as_of, NULL))                                           AS grace_last_night,
         ARRAY_AGG(IF(in_grace_run, window_to, NULL) IGNORE NULLS ORDER BY as_of DESC LIMIT 1)[SAFE_OFFSET(0)]
                                                                                      AS grace_last_window_to,
         MIN(IF(in_hold_run, as_of, NULL))                                            AS hold_since,
         -- the settle date of the window that started the run. MIN over the run picks the FIRST
         -- night's settle_due_on, because settle_due_on rolls forward with the window.
         MIN(IF(in_hold_run, settle_due_on, NULL))                                    AS hold_settles_on,
         -- P-18: the very good last day that started the run is that first night's window_to
         ARRAY_AGG(IF(in_hold_run, window_to, NULL) IGNORE NULLS ORDER BY as_of LIMIT 1)[SAFE_OFFSET(0)]
                                                                                      AS hold_strong_day,
         MAX(IF(in_hold_run, as_of, NULL))                                            AS hold_last_night,
         ARRAY_AGG(IF(in_hold_run, window_to, NULL) IGNORE NULLS ORDER BY as_of DESC LIMIT 1)[SAFE_OFFSET(0)]
                                                                                      AS hold_last_window_to,
         -- every night this keyword has a live row: the nights NOT in it are its unwritten gap
         ARRAY_AGG(as_of)                                                             AS nights
  FROM plan_hist
  GROUP BY 1, 2
),
-- P-29 (v27.156, R16): the windows an unwritten gap would have judged, read from the ads record.
-- THIS CHAIN READS NO HEAVY CTE (not win, not ks): each CTE in a BigQuery view is re-evaluated
-- wherever it is referenced, and a first draft that read win and ks here ran at 2,988
-- slot-seconds against the deployed view's 523 (one run each, 2026-10-02). Tonight's window_from,
-- window_days and family bar are applied in base2, on the row.
-- The calendar of every night since the plan's first partition: the window length and order floor
-- that night's state carries.
gap_cal AS (
  SELECT d.n, c.window_days AS wd_n, c.min_orders AS min_orders_n
  FROM (SELECT n, `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(n) AS st
        FROM UNNEST(GENERATE_DATE_ARRAY(
               (SELECT MIN(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE is_live_plan),
               (SELECT DATE_SUB(d_plan, INTERVAL 1 DAY) FROM today))) AS n) d
  JOIN cfg c ON c.calendar_state = d.st
),
-- the gap: every night after a memory's last night, before today, that wrote no live row for this
-- keyword (the builder refused it, or the keyword was outside the universe that night); each such
-- night n would have judged the window ending n - 2 (the P-14a fence) of its own state's length.
-- Only windows ending after the memory's own window are the gap's.
gap_windows AS (
  SELECT p.cid, p.kid, m.kind, DATE_SUB(gn, INTERVAL 2 DAY) AS g_to, gc.wd_n, gc.min_orders_n
  FROM prior0 p
  CROSS JOIN today t
  CROSS JOIN UNNEST([
    STRUCT('GRACE' AS kind, p.grace_last_night AS m_night, p.grace_last_window_to AS m_window_to),
    STRUCT('HOLD'  AS kind, p.hold_last_night  AS m_night, p.hold_last_window_to  AS m_window_to)]) m
  CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(DATE_ADD(m.m_night, INTERVAL 1 DAY),
                                        DATE_SUB(t.d_plan, INTERVAL 1 DAY))) AS gn
  JOIN gap_cal gc ON gc.n = gn
  WHERE m.m_night IS NOT NULL
    AND gn NOT IN UNNEST(p.nights)
    AND DATE_SUB(gn, INTERVAL 2 DAY) > m.m_window_to
),
-- ONE read of FACT_AMAZON_ADS, joined to the gap windows of the keywords that carry such a memory
gap_win_rec AS (
  SELECT w.cid, w.kid, w.kind, w.g_to, w.wd_n, w.min_orders_n,
         COALESCE(SUM(f.Ads_cost), 0)     AS sp,
         COALESCE(SUM(f.Ads_orders), 0)   AS ord,
         COALESCE(SUM(f.GROSS_PROFIT), 0) AS gp
  FROM gap_windows w
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON CAST(f.campaign_id AS STRING) = w.cid
   AND CAST(f.keyword_id AS STRING) = w.kid
   AND f.date BETWEEN DATE_SUB(w.g_to, INTERVAL w.wd_n - 1 DAY) AND w.g_to
  GROUP BY 1, 2, 3, 4, 5, 6
),
gap_eval AS (
  SELECT cid, kid,
         ARRAY_AGG(STRUCT(kind, g_to, wd_n, min_orders_n, sp, ord, gp) ORDER BY kind, g_to) AS gap_wins
  FROM gap_win_rec
  GROUP BY 1, 2
),
-- Whether the one-window limit can bite AT ALL. Until Task 2's builder writes the first live plan
-- there is no history, prior_grace is FALSE on every row, and grace is re-granted every night — so
-- the GRACE sentence must say the limit is not armed rather than promise a limit nothing enforces.
-- (v27.156: read from the table directly — the same rows plan_hist reads — so the plan_hist chain
-- is not evaluated a second time for one boolean.)
armed AS (
  SELECT (COUNT(*) > 0) AS grace_limit_armed
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan AND as_of < (SELECT d_plan FROM today)
),
probes AS (
  SELECT DISTINCT CAST(keyword_id AS STRING) AS kid FROM `onyga-482313.OI.T_LIFT_PROBES`
),
-- P-25 (Ori 2026-10-02, R12; v27.157): LIFT's latest PROBE_START bid per keyword, the only
-- published probe price. One price per keyword or no probe price at all (the HAVING); MAX, not
-- ANY_VALUE, so the value read is deterministic (under the HAVING the two are the same number).
-- FACT_ENGINE_PROPOSALS is written by SP_SNAPSHOT_ENGINE_PROPOSALS earlier in the same orchestrator
-- pass than SP_BUILD_NEXT_WEEK_PLAN (20.8c), so the builder reads tonight's nomination.
probe_bid AS (
  SELECT CAST(keyword_id AS STRING) AS kid, MAX(suggested_bid) AS probe_start_bid
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE engine = 'LIFT' AND action = 'PROBE_START'
    AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)
  GROUP BY 1
  HAVING COUNT(DISTINCT suggested_bid) = 1
),
seatecon AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         MAX(seat_cpc) AS seat_cpc, MAX(bid_park) AS bid_park
  FROM `onyga-482313.OI.T_OOB_SEAT_ECONOMICS`
  GROUP BY 1, 2
),
holdout AS (
  SELECT CAST(unit_id AS STRING) AS cid, MIN(eligible_from) AS eligible_from
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT'
  GROUP BY 1
),
base AS (
  SELECT
    ks.family, ks.book,
    CAST(ks.campaign_id AS STRING) AS campaign_id, ks.campaign_name,
    CAST(ks.keyword_id AS STRING)  AS keyword_id,
    CAST(ks.ad_group_id AS STRING) AS ad_group_id,
    ks.target_text, ks.match_type, ks.channel,
    COALESCE(ks.is_auto, FALSE) AS is_auto, COALESCE(ks.is_pt, FALSE) AS is_pt,
    COALESCE(ks.is_brand_defense, FALSE) AS is_brand_defense,
    ks.state AS ladder_state, ks.current_bid, ks.affordable_bid, ks.bid_floor,
    ks.gp_per_click, ks.settled_ord90, ks.settled_gp90, ks.settled_sp90,
    COALESCE(ks.family_bar, 1.0) AS family_bar,
    win.calendar_state, win.window_days, win.window_from, win.window_to, win.watermark,
    win.allowance_share, win.ramp_steps, win.live_plan,
    cp.daily_budget AS campaign_current_budget, cp.portfolio_id,
    COALESCE(rec.w_sp, 0)  AS w_sp,
    COALESCE(rec.w_clk, 0) AS w_clk,
    COALESCE(rec.w_ord, 0) AS w_ord,
    COALESCE(rec.w_gp, 0)  AS w_gp,
    COALESCE(SAFE_DIVIDE(rec.w_absgp, NULLIF(rec.w_absgp_corrected, 0)), 1.0) AS settle_factor_eff,
    COALESCE(rec.settle_factor_min, 1.0) AS settle_factor_min,
    -- vacuously TRUE when the window holds no day for this keyword: "every day of this window had
    -- a factor" is true of an empty window, and reading it as FALSE would label a keyword that
    -- simply did not serve as one the curve could not answer for — two different things.
    COALESCE(rec.settle_curve_available, TRUE) AS settle_curve_available,
    rec.min_age_days,
    COALESCE(rec.ld_sp, 0)           AS last_day_sp,
    COALESCE(rec.ld_clk, 0)          AS last_day_clk,
    COALESCE(rec.ld_ord, 0)          AS last_day_ord,
    COALESCE(rec.ld_gp, 0)           AS last_day_gp,
    COALESCE(rec.ld_gp_corrected, 0) AS last_day_gp_corrected,
    COALESCE(pr.prior_seen, FALSE)  AS prior_seen,
    COALESCE(pr.prior_good, FALSE)  AS prior_good,
    pr.last_grace_on,
    -- the memory as the plan's history holds it (P-17, P-18), before the P-29 gap test, which
    -- base2 applies with tonight's window and bar. Raw names; base2 publishes the honoured ones.
    pr.grace_since          AS raw_grace_since,
    pr.grace_window_days    AS raw_grace_window_days,
    pr.grace_last_night     AS raw_grace_last_night,
    pr.hold_since           AS raw_hold_since,
    pr.hold_settles_on      AS raw_hold_settles_on,
    pr.hold_strong_day      AS raw_hold_strong_day,
    pr.hold_last_night      AS raw_hold_last_night,
    ge.gap_wins,
    am.grace_limit_armed,
    (pb.kid IS NOT NULL) AS is_probe,
    -- P-25: LIFT's PROBE_START bid, on a probe row only (a nomination is what makes it a probe)
    IF(pb.kid IS NOT NULL, pbb.probe_start_bid, NULL) AS probe_start_bid,
    se.seat_cpc,
    se.bid_park AS bid_park_seat_econ,
    -- P-11 / §4 step 5: the park price always answers, and always says which source answered.
    -- The house floor (FN_BID_FLOOR, already on the row) is the fallback, and the park is never
    -- below it — a bid under the platform minimum is not a price, it is a rejection.
    CASE
      WHEN se.bid_park IS NOT NULL AND ks.bid_floor IS NOT NULL THEN GREATEST(se.bid_park, ks.bid_floor)
      WHEN se.bid_park IS NOT NULL                              THEN se.bid_park
      WHEN ks.bid_floor IS NOT NULL                             THEN ks.bid_floor
      ELSE NULL
    END AS bid_park,
    CASE
      WHEN se.bid_park IS NOT NULL  THEN 'SEAT_ECONOMICS'
      WHEN ks.bid_floor IS NOT NULL THEN 'BID_FLOOR_FALLBACK'
      ELSE 'NONE'
    END AS bid_park_source,
    (h.cid IS NOT NULL AND t.d_la >= h.eligible_from) AS holdout,
    (h.cid IS NOT NULL)                               AS holdout_member,
    h.eligible_from AS holdout_eligible_from,
    IF(ks.channel = 'SB', caps.settle_days_sb, caps.settle_days_sp) AS settle_days,
    win.min_orders, caps.cap_up, caps.cap_down, caps.raise_ceiling, caps.click_goal_day,
    win.strong_day_mult, win.strong_day_min_orders,
    t.d_la AS today_la,
    t.d_plan AS today_plan
  FROM ks
  CROSS JOIN win
  CROSS JOIN caps
  CROSS JOIN today t
  CROSS JOIN armed am
  LEFT JOIN camp cp ON cp.cid = CAST(ks.campaign_id AS STRING)
  LEFT JOIN rec ON rec.cid = CAST(ks.campaign_id AS STRING) AND rec.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN prior0 pr ON pr.cid = CAST(ks.campaign_id AS STRING) AND pr.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN gap_eval ge ON ge.cid = CAST(ks.campaign_id AS STRING) AND ge.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN probes pb ON pb.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN probe_bid pbb ON pbb.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN seatecon se ON se.cid = CAST(ks.campaign_id AS STRING) AND se.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN holdout h ON h.cid = CAST(ks.campaign_id AS STRING)
),
-- P-29 (v27.156, R16) ON THE ROW: a memory whose last night is older than today_plan -
-- window_days - 1 is honoured only if no window its unwritten gap would have judged, ending before
-- tonight's window_from, reads GOOD (orders at that night's floor, raw gross profit per ad dollar at
-- tonight's family bar). Then P-17's spend test on the grace that survives.
base2 AS (
  SELECT b.* EXCEPT (raw_grace_since, raw_grace_window_days, raw_grace_last_night, raw_hold_since,
                     raw_hold_settles_on, raw_hold_strong_day, raw_hold_last_night, gap_wins,
                     grace_cleared, hold_cleared, gap_good_to),
    IF(b.grace_cleared, NULL, b.raw_grace_since)        AS prior_grace_since,
    IF(b.grace_cleared, NULL, b.raw_grace_window_days)  AS prior_grace_window_days,
    -- P-17: grace is SPENT once its run has lasted the window it was granted for
    COALESCE(NOT b.grace_cleared AND b.raw_grace_since IS NOT NULL
             AND DATE_DIFF(b.today_plan, b.raw_grace_since, DAY) >= b.raw_grace_window_days,
             FALSE)                                     AS prior_grace,
    IF(b.hold_cleared, NULL, b.raw_hold_since)          AS hold_since,
    IF(b.hold_cleared, NULL, b.raw_hold_settles_on)     AS hold_settles_on,
    IF(b.hold_cleared, NULL, b.raw_hold_strong_day)     AS hold_strong_day,
    CASE WHEN b.grace_cleared AND b.hold_cleared THEN 'GRACE_AND_HOLD'
         WHEN b.grace_cleared THEN 'GRACE'
         WHEN b.hold_cleared  THEN 'HOLD' END           AS memory_cleared_by_gap,
    IF(b.grace_cleared OR b.hold_cleared, b.gap_good_to, NULL) AS memory_gap_good_window_to
  FROM (
    SELECT b0.*,
      (b0.raw_grace_last_night < DATE_SUB(b0.today_plan, INTERVAL b0.window_days + 1 DAY)
       AND EXISTS (SELECT 1 FROM UNNEST(b0.gap_wins) x
                   WHERE x.kind = 'GRACE' AND x.g_to < b0.window_from
                     AND x.ord >= x.min_orders_n
                     AND COALESCE(SAFE_DIVIDE(x.gp, NULLIF(x.sp, 0)), -1) >= b0.family_bar))
        IS TRUE AS grace_cleared,
      (b0.raw_hold_last_night < DATE_SUB(b0.today_plan, INTERVAL b0.window_days + 1 DAY)
       AND EXISTS (SELECT 1 FROM UNNEST(b0.gap_wins) x
                   WHERE x.kind = 'HOLD' AND x.g_to < b0.window_from
                     AND x.ord >= x.min_orders_n
                     AND COALESCE(SAFE_DIVIDE(x.gp, NULLIF(x.sp, 0)), -1) >= b0.family_bar))
        IS TRUE AS hold_cleared,
      -- the end of the first gap window that read GOOD, of either memory's gap
      (SELECT MIN(x.g_to) FROM UNNEST(b0.gap_wins) x
       WHERE x.g_to < b0.window_from AND x.ord >= x.min_orders_n
         AND COALESCE(SAFE_DIVIDE(x.gp, NULLIF(x.sp, 0)), -1) >= b0.family_bar
         AND ((x.kind = 'GRACE' AND b0.raw_grace_last_night
                                    < DATE_SUB(b0.today_plan, INTERVAL b0.window_days + 1 DAY))
              OR (x.kind = 'HOLD' AND b0.raw_hold_last_night
                                    < DATE_SUB(b0.today_plan, INTERVAL b0.window_days + 1 DAY))))
        AS gap_good_to
    FROM base b0
  ) b
),
derived AS (
  SELECT b.*,
    SAFE_DIVIDE(b.w_gp, b.settle_factor_eff)          AS w_gp_corrected,
    SAFE_DIVIDE(b.w_gp, NULLIF(b.w_sp, 0))            AS ret_raw,
    SAFE_DIVIDE(SAFE_DIVIDE(b.w_gp, b.settle_factor_eff), NULLIF(b.w_sp, 0)) AS ret_corrected,
    DATE_ADD(b.window_to, INTERVAL b.settle_days DAY) AS settle_due_on,
    (DATE_DIFF(b.today_la, b.window_to, DAY) >= b.settle_days) AS settled,
    -- the keyword took money or attention in the window, so it has sales that may still arrive.
    -- This is the precondition of the P-14b guard (see the header).
    (b.w_sp > 0 OR b.w_clk > 0)                       AS served,
    SAFE_DIVIDE(b.last_day_gp_corrected, NULLIF(b.last_day_sp, 0)) AS last_day_ret,
    -- P-14c: was the last complete day VERY GOOD? Orders are observed (never corrected, as the
    -- P-3 floor reads them); the return is corrected for that day's sales still arriving.
    (b.last_day_ord >= b.strong_day_min_orders
     AND COALESCE(SAFE_DIVIDE(b.last_day_gp_corrected, NULLIF(b.last_day_sp, 0)), -1)
         >= b.family_bar * b.strong_day_mult)                                   AS last_day_strong,
    -- the ladder's own settled record, the bootstrap half of "was good" (P-14b)
    (COALESCE(b.settled_ord90, 0) >= b.min_orders
     AND COALESCE(SAFE_DIVIDE(b.settled_gp90, NULLIF(b.settled_sp90, 0)), 0) >= b.family_bar)
      AS ladder_settled_good,
    -- P-6: the ladder's repaired price. Cap three 5% steps either way, floor at the row's own
    -- floor, ceiling the house $2.00 on a raise. P-19 and P-25 (priced, below) decide whether it
    -- is the price; this column is what P-6 alone would have asked.
    LEAST(
      GREATEST(
        LEAST(
          GREATEST(COALESCE(b.affordable_bid, b.current_bid), b.current_bid * (1 - b.cap_down)),
          b.current_bid * (1 + b.cap_up)),
        COALESCE(b.bid_floor, 0)),
      GREATEST(b.raise_ceiling, b.current_bid))            AS planned_bid_p6
  FROM base2 b
),
-- THE PRICE (v27.157, Ori's rulings R5 and R12 of 2026-10-02, spec P-19 and P-25). Applied in this
-- order, and the order is the rulings', not taste:
--   P-25 A PROBE WITH A LIFT PRICE opens at LIFT's PROBE_START bid, capped by the raise ceiling
--        (GREATEST(raise_ceiling, current_bid), the P-6 ceiling): a probe opened below the bid that
--        bought it zero clicks is not a probe. A probe with no single LIFT price keeps P-6's formula
--        and its sentence says so. P-19 does not apply to a probe: it has no window to be under the
--        bar on (every probe on 2026-10-02 was NOT_SERVING; a served probe is exempt too, as the
--        plan writes the rule — 0 rows today).
--   P-19 NO RAISE BELOW THE BAR. A repair on the not-good side is a step toward the bar, never away
--        from it: where the corrected return is under the family bar the price is never above the
--        current bid. The gate is the return against the bar, not the verdict label: five
--        ONE_ORDER rows on 2026-10-01 sat under the bar and would survive a label gate. A NULL
--        return (no spend) reads as 0, i.e. under the bar. P-19 WINS OVER P-6'S FLOOR: a current
--        bid already under the row's bid_floor is held where it is, not raised to the floor (that
--        would be a raise); holding it uploads nothing (the builder's HOLD_AT_PRICE / HOLD_AT_PARK
--        carry the current bid), and C08 accepts a price at the current bid when the current bid
--        is under the floor. 5 not-good rows on 2026-10-02 had a current bid under the floor, none
--        a candidate (1 holdout, 4 NOT_SERVING with no nomination).
-- planned_bid_basis names which rule set the price, so the sentence and the acceptance read it:
--   P25_LIFT_PROBE_START | P6_PROBE_NO_LIFT_PRICE | P19_HELD_AT_CURRENT (P-6 would have raised it,
--   and P-19 held it at the current bid) | P6_REPAIR (P-6's price stands: at or above the bar, or
--   not a raise).
priced AS (
  SELECT d.*,
    CASE
      WHEN d.is_probe AND d.probe_start_bid IS NOT NULL
        THEN LEAST(d.probe_start_bid, GREATEST(d.raise_ceiling, COALESCE(d.current_bid, d.raise_ceiling)))
      WHEN d.is_probe THEN d.planned_bid_p6
      WHEN COALESCE(d.ret_corrected, 0) < d.family_bar THEN LEAST(d.planned_bid_p6, d.current_bid)
      ELSE d.planned_bid_p6
    END AS planned_bid_raw,
    CASE
      WHEN d.is_probe AND d.probe_start_bid IS NOT NULL THEN 'P25_LIFT_PROBE_START'
      WHEN d.is_probe THEN 'P6_PROBE_NO_LIFT_PRICE'
      WHEN COALESCE(d.ret_corrected, 0) < d.family_bar
           AND ROUND(d.planned_bid_p6, 2) > ROUND(d.current_bid, 2) THEN 'P19_HELD_AT_CURRENT'
      ELSE 'P6_REPAIR'
    END AS planned_bid_basis
  FROM derived d
),
sided AS (
  SELECT d.*,
    (d.w_ord >= d.min_orders AND COALESCE(d.ret_raw, -1)       >= d.family_bar) AS good_raw,
    (d.w_ord >= d.min_orders AND COALESCE(d.ret_corrected, -1) >= d.family_bar) AS good_corrected,
    -- "if there is one": last night's plan wins once it exists; the ladder is the bootstrap only.
    IF(d.prior_seen, d.prior_good, d.ladder_settled_good)                       AS was_good,
    -- the hold's clock (v27.138). A run that has been going since a window whose settle date has
    -- passed has had exactly the delay P-14b buys, and rule B judges the row on the numbers.
    (d.hold_since IS NOT NULL AND d.hold_settles_on IS NOT NULL
     AND d.today_la > d.hold_settles_on)                                        AS hold_expired,
    -- P-18 (v27.156): a hold run is in force AND the very good day that started it is still
    -- inside tonight's judged window. FALSE when no run is in force (a first night needs the
    -- last day itself).
    COALESCE(d.hold_since IS NOT NULL AND d.window_from <= d.hold_strong_day, FALSE)
                                                                                AS strong_day_in_window
  FROM priced d
),
judged AS (
  SELECT s.*,
    CASE
      WHEN s.good_corrected THEN 'GOOD'
      -- P-5 IS TESTED BEFORE P-14b (v27.135 repair). Both put the row on the GOOD side, so no
      -- money moves either way — but the ORDER decides which ruling is named, whether P-5's limit
      -- can ever bite, and what the published "unguarded" counterfactual means. With the guard
      -- first it reached 36 of the 39 ladder winners with a quiet window, so the ruling that buys
      -- ONE window was silently replaced by the one that buys every window and has no expiry, the
      -- shipped reprice book (which tests grace first) named a different ruling on the same rows,
      -- and "drop the guard and the pot reverts to the unguarded column" was false by 28% of the
      -- pot, because those rows would have fallen through to grace, not to the queue. Grace first
      -- makes the limited ruling the one that speaks, and makes both other surfaces true.
      WHEN s.w_ord < s.min_orders AND s.ladder_state IN ('WINNER', 'PACED_WINNER')
           AND NOT s.prior_grace THEN 'GRACE'
      -- P-14b: the guard needs sales in flight, and sales in flight need service — AND IT NEEDS AN
      -- END (v27.138). hold_expired is FALSE on the first night of a hold (there is no run yet) and
      -- stays FALSE until the settle date of the window that STARTED the hold has passed. Without
      -- it the branch was satisfied unconditionally for anything the plan had put on the good side
      -- once, because `settled` reads a window that rolls forward every night and never settles.
      -- P-14c (Ori, 2026-09-17): AND ONLY WHEN THE LAST COMPLETE DAY WAS VERY GOOD. The window
      -- is what is judged; a losing window whose last day "won a little" is not good, and the
      -- guard does not postpone that. Only a last day strong enough to change the window's
      -- reading once its sales land earns the wait -- and the wait is still bounded by the
      -- clock above. Read from the 2026-09-28 live partition of FACT_PLAN_NEXT_WEEK (spec §3b
      -- publishes the query): all 44 keywords the expired clock released were judged on the
      -- window -- 40 LAST_DAY_NOT_STRONG, and 4 HOLD_EXPIRED whose last day cleared 1.5x (1.90x,
      -- 1.93x, 11.71x, 22.19x the bar) on August clocks that had run out. The 4 rows held that
      -- night were first-night holds at 1.51x-1.65x the bar.
      -- P-18 (Ori, 2026-10-02, R4; v27.156): OR the very good day that started the hold run is
      -- still inside the judged window. P-14c's own reason — wait until that day's sales land —
      -- lasts as long as that day is part of what is judged, and the clock above still bounds it.
      WHEN s.was_good AND NOT s.settled AND s.served AND NOT s.hold_expired
           AND (s.last_day_strong OR s.strong_day_in_window) THEN 'HELD_UNSETTLED'
      WHEN s.w_ord >= s.min_orders THEN 'LOSING'
      WHEN s.w_ord = 1 THEN 'ONE_ORDER'
      WHEN s.served THEN 'NO_SALE'
      ELSE 'NOT_SERVING'
    END AS verdict
  FROM sided s
),
final AS (
  SELECT j.*,
    IF(j.verdict IN ('GOOD', 'HELD_UNSETTLED', 'GRACE'), 'GOOD', 'NOT_GOOD') AS side_b,
    IF(j.ladder_state IN ('WINNER', 'PACED_WINNER', 'AT_BAR', 'TRIAL', 'PENDING_SETTLE',
                          'REVIVED_SETTLING'), 'GOOD', 'NOT_GOOD')           AS side_a,
    CASE
      WHEN j.verdict = 'HELD_UNSETTLED' THEN 'P-14b'
      WHEN j.verdict = 'GRACE'          THEN 'P-5'
      ELSE 'P-3'
    END AS decided_by,
    -- the guard is holding money the window has already spoken about, not money awaiting evidence
    (j.verdict = 'HELD_UNSETTLED' AND j.w_ord >= j.min_orders) AS held_despite_evidence,
    -- ...and the OTHER population the guard holds, which carries more money than the first: a
    -- keyword that took clicks and spent money in the window and sold NOTHING. Its arm sentence
    -- used to say "promotion is allowed on fresh evidence" — a promise the correction cannot keep,
    -- because the correction scales gross profit and this window has none. This is the identical
    -- fact pattern the not-good side gets NOT_CORRECTABLE_NO_GP and a plain sentence for; the only
    -- difference is that these keywords' 90-day ladder record clears the bar.
    -- SINCE P-14c THIS IS FALSE BY CONSTRUCTION: a window with no order has no very good last
    -- day, so the guard cannot hold it. Kept as a column because the plan table, the scorecard
    -- and the SOP read it; it now reads as a record of what the guard no longer does.
    (j.verdict = 'HELD_UNSETTLED' AND j.w_ord = 0 AND j.w_sp > 0) AS held_with_no_sale,
    -- P-14c / P-11: when a keyword that WAS good, served, and sits on an unsettled window is
    -- nonetheless on the NOT-GOOD side, this names the reason the guard let it through. The
    -- builder asserts it is never NULL on such a row -- it checks the judgement is complete
    -- without re-deriving the guard. NULL on every other row. UNEXPLAINED is unreachable by
    -- the CASE above and exists so a future reordering of the arms fails loudly.
    -- P-18 (v27.156): LAST_DAY_NOT_STRONG only when NEITHER the last day nor the very good day
    -- that started a hold run in force (still inside the window) holds it.
    CASE
      WHEN IF(j.verdict IN ('GOOD','HELD_UNSETTLED','GRACE'), 'GOOD', 'NOT_GOOD') = 'NOT_GOOD'
           AND j.was_good AND j.served AND NOT j.settled THEN
        CASE WHEN NOT j.last_day_strong AND NOT j.strong_day_in_window THEN 'LAST_DAY_NOT_STRONG'
             WHEN j.hold_expired        THEN 'HOLD_EXPIRED'
             ELSE 'UNEXPLAINED' END
      ELSE NULL
    END AS guard_released_by,
    -- P-18: what keeps a HELD row held, published so the builder, V_ENGINE_HEALTH and the
    -- acceptance read it and never re-derive it. NULL on every row that is not HELD.
    CASE WHEN j.verdict != 'HELD_UNSETTLED' THEN NULL
         WHEN j.last_day_strong             THEN 'LAST_DAY'
         WHEN j.strong_day_in_window        THEN 'STRONG_DAY_IN_WINDOW'
    END AS hold_kept_by,
    -- FIX #16 (v27.156): the clock on the row from the FIRST held night. On a held row with no
    -- run in force tonight starts it: today_plan, tonight's settle date, tonight's last day.
    COALESCE(j.hold_since,      IF(j.verdict = 'HELD_UNSETTLED', j.today_plan, NULL))    AS hold_since_pub,
    COALESCE(j.hold_settles_on, IF(j.verdict = 'HELD_UNSETTLED', j.settle_due_on, NULL)) AS hold_settles_on_pub,
    COALESCE(j.hold_strong_day, IF(j.verdict = 'HELD_UNSETTLED', j.window_to, NULL))     AS hold_strong_day_pub,
    -- P-17: the grace run, on the row. A GRACE row with no run in force tonight starts one,
    -- lasting tonight's window_days. A non-GRACE row carries the run its history holds, if any.
    IF(j.verdict = 'GRACE', COALESCE(j.prior_grace_since, j.today_plan), j.prior_grace_since)
                                                                                     AS grace_since_pub,
    IF(j.verdict = 'GRACE' AND j.prior_grace_since IS NULL, j.window_days, j.prior_grace_window_days)
                                                                                     AS grace_window_days_pub,
    -- the same fact for the WHOLE protected side. P-4 forbids cutting or re-pricing anything on
    -- the good side, so a keyword sitting there on a window that took money and returned no sale
    -- must say so whichever ruling put it there — otherwise reordering the arms would move the
    -- disclosure off the money instead of onto it.
    (IF(j.verdict IN ('GOOD','HELD_UNSETTLED','GRACE'), 'GOOD', 'NOT_GOOD') = 'GOOD'
     AND j.w_ord = 0 AND j.w_sp > 0) AS good_side_no_sale,
    CASE
      WHEN j.verdict = 'HELD_UNSETTLED'                     THEN 'HELD_UNSETTLED'
      -- nothing was read, so nothing was corrected and nothing is in flight: a keyword that took
      -- no clicks in the window has no sales arriving later and its empty record is already final.
      -- (The reprice book says the same thing in words on its NOT SERVING rows.)
      WHEN NOT j.served AND j.w_gp = 0                      THEN 'SETTLED'
      WHEN NOT j.settle_curve_available                     THEN 'UNCORRECTED_NO_CURVE'
      WHEN j.good_corrected AND NOT j.good_raw              THEN 'PROMOTED_ON_FRESH'
      WHEN j.settled                                        THEN 'SETTLED'
      -- the correction scales gross profit; a window with none cannot be corrected by any factor
      WHEN j.w_gp = 0                                       THEN 'NOT_CORRECTABLE_NO_GP'
      ELSE 'CORRECTED'
    END AS settle_arm,
    -- P-6: seat cost = spend at the planned price, per day. P-4: NULL on the good side.
    -- v27.157: the planned price is the one P-19 / P-25 set (priced CTE), so a price P-19 held at
    -- the current bid costs the window's spend per day and never more. P-25: a probe with a LIFT
    -- price funds the clicks it asks for at the price it opens at — click_goal_day x that price
    -- (THREE_LAYERS §3: the seat funds the answer it demands); a probe with no LIFT price keeps
    -- the v27.134 costing.
    IF(j.verdict IN ('GOOD', 'HELD_UNSETTLED', 'GRACE'), NULL,
      CASE
        WHEN j.planned_bid_basis = 'P25_LIFT_PROBE_START'
          THEN j.click_goal_day * j.planned_bid_raw
        WHEN j.w_sp > 0 AND COALESCE(j.current_bid, 0) > 0
          THEN (j.w_sp / j.window_days) * SAFE_DIVIDE(j.planned_bid_raw, j.current_bid)
        WHEN j.is_probe
          THEN COALESCE(j.seat_cpc, j.bid_floor, 0) * j.click_goal_day
        ELSE 0
      END) AS seat_cost_per_day,
    -- P-7: dollars at stake x closeness to the bar. BOTH FACTORS ARE PUBLISHED SEPARATELY
    -- (v27.135) because their PRODUCT is not what the words say it is — see the header. The score
    -- below is exactly rank_dollars_at_stake * rank_closeness, and C21 asserts that identity, so
    -- nobody has to take the multiplication on trust and Ori can order by either factor alone.
    (j.w_sp / j.window_days)                                                 AS rank_dollars_at_stake,
    COALESCE(SAFE_DIVIDE(j.ret_corrected, NULLIF(j.family_bar, 0)), 0)       AS rank_closeness,
    (j.w_sp / j.window_days) * COALESCE(SAFE_DIVIDE(j.ret_corrected, NULLIF(j.family_bar, 0)), 0)
      AS rank_score,
    -- P-20 (Ori 2026-10-02, R6; v27.157): money burned with no return, per day — the window's
    -- spend per day times the share of it the bar did not return, floored at 0. It orders the
    -- candidates P-7 gives no positive score (the final ORDER BY), instead of their clicks. It does
    -- not cancel the way P-7's two factors do: a zero-return keyword scores its whole spend.
    (j.w_sp / j.window_days)
      * GREATEST(0, 1 - COALESCE(j.ret_corrected, 0) / NULLIF(j.family_bar, 0)) AS rank_money_burned,
    -- §4 step 3, hoisted out of the SELECT so the seat SENTENCE is built from the same expression
    -- that decides candidacy and the two can never disagree (v27.135; before this repair 41 rows
    -- were promised a seat in words that their own is_candidate refused them).
    (IF(j.verdict IN ('GOOD','HELD_UNSETTLED','GRACE'), 'GOOD', 'NOT_GOOD') = 'NOT_GOOD'
     AND NOT j.holdout
     AND (j.verdict != 'NOT_SERVING' OR j.is_probe))                         AS is_candidate,
    -- v27.157: the price a seat clause names, in words, from planned_bid_basis — the same
    -- expression that set the price, so the sentence cannot name a rule the price did not follow.
    CASE j.planned_bid_basis
      WHEN 'P25_LIFT_PROBE_START' THEN FORMAT(
        'LIFT\'s PROBE_START bid $%.2f%s, costed at its click goal of %d clicks a day (about $%.2f a day): a probe opens at the bid LIFT nominated it at, and its seat funds the clicks it asks for (P-25, Ori 2026-10-02)',
        ROUND(j.planned_bid_raw, 2),
        IF(j.probe_start_bid > j.planned_bid_raw + 0.005,
           FORMAT(' (LIFT asked $%.2f; capped at the $%.2f ceiling)', j.probe_start_bid,
                  GREATEST(j.raise_ceiling, COALESCE(j.current_bid, j.raise_ceiling))),
           ''),
        j.click_goal_day, j.click_goal_day * j.planned_bid_raw)
      WHEN 'P6_PROBE_NO_LIFT_PRICE' THEN FORMAT(
        'the repaired price $%.2f — LIFT holds no single PROBE_START bid for this keyword tonight, so this probe is priced by the ladder\'s repair (P-6) instead of opening at a LIFT bid (P-25)',
        ROUND(j.planned_bid_raw, 2))
      WHEN 'P19_HELD_AT_CURRENT' THEN FORMAT(
        'its current price $%.2f — the ladder\'s repaired price $%.2f would RAISE it, and a not-good keyword whose corrected return (%.2f per ad dollar) is under the %.2f bar is never priced above its current bid (P-19, Ori 2026-10-02)',
        ROUND(j.planned_bid_raw, 2), ROUND(j.planned_bid_p6, 2), COALESCE(j.ret_corrected, 0),
        j.family_bar)
      ELSE FORMAT('the repaired price $%.2f', ROUND(j.planned_bid_raw, 2))
    END                                                                      AS price_clause
  FROM judged j
)
SELECT
  f.family, f.book, f.campaign_id, f.campaign_name, f.keyword_id, f.ad_group_id,
  f.target_text, f.match_type, f.channel, f.is_auto, f.is_pt, f.is_brand_defense,
  f.portfolio_id, f.campaign_current_budget,
  f.calendar_state, f.window_days, f.window_from, f.window_to, f.watermark,
  f.allowance_share, f.ramp_steps, f.live_plan, f.min_orders,
  f.w_clk, f.w_ord, f.w_sp, f.w_gp, f.w_gp_corrected,
  f.settle_factor_min, f.settle_factor_eff, f.settle_curve_available, f.min_age_days,
  f.settled, f.settle_due_on, f.settle_days, f.settle_arm, f.decided_by, f.was_good,
  f.served, f.prior_seen, f.prior_good, f.prior_grace, f.last_grace_on, f.grace_limit_armed,
  -- fix #16 (v27.156): published from the first HELD night; the prior CTE never reads them back
  f.hold_since_pub AS hold_since, f.hold_settles_on_pub AS hold_settles_on, f.hold_expired,
  -- P-18 (v27.156): the very good day that started the hold run, and what keeps a HELD row held
  f.hold_strong_day_pub AS hold_strong_day, f.hold_kept_by,
  -- P-17 (v27.156): the grace run — its first night, its length and its last night
  f.grace_since_pub AS grace_since, f.grace_window_days_pub AS grace_window_days,
  DATE_ADD(f.grace_since_pub, INTERVAL f.grace_window_days_pub - 1 DAY) AS grace_ends_on,
  -- P-29 (v27.156): a GRACE / HOLD memory a GOOD window inside an unwritten gap cleared tonight,
  -- and the end of the first such window. SP_BUILD_NEXT_WEEK_PLAN stores the first; plan_hist
  -- reads it back as a reset.
  f.memory_cleared_by_gap, f.memory_gap_good_window_to,
  f.last_day_sp, f.last_day_clk, f.last_day_ord, f.last_day_gp, f.last_day_gp_corrected,
  f.last_day_ret, f.last_day_strong, f.guard_released_by,
  -- v27.154 follow-up: the P-14c rule this row was judged under, for the plan table to keep
  f.strong_day_mult, f.strong_day_min_orders,
  f.held_despite_evidence, f.held_with_no_sale, f.good_side_no_sale,
  f.family_bar, f.ret_raw, f.ret_corrected, f.good_raw, f.good_corrected,
  f.ladder_state, f.verdict, f.side_b, f.side_a,
  f.is_candidate,
  f.rank_score, f.rank_dollars_at_stake, f.rank_closeness,
  -- P-7 scores zero wherever there is no gross profit; say so rather than let a seat walk
  -- silently fall through to the tiebreak. See the header and SOP §2.
  (f.is_candidate AND f.rank_score = 0) AS rank_is_degenerate,
  -- P-20 (v27.157): what orders the candidates with no positive P-7 score (acceptance P2)
  f.rank_money_burned,
  f.current_bid, f.bid_floor,
  f.bid_park, f.bid_park_source, f.bid_park_seat_econ,
  -- P-4: the good side carries no executable price and no seat cost
  IF(f.side_b = 'GOOD', NULL, ROUND(f.planned_bid_raw, 2)) AS planned_bid,
  ROUND(f.seat_cost_per_day, 4) AS seat_cost_per_day,
  -- v27.157 (P-19, P-25): which rule set planned_bid, the price P-6 alone asked (so a raise P-19
  -- removed stays readable), and LIFT's PROBE_START bid on a probe. NULL on the good side (P-4).
  IF(f.side_b = 'GOOD', NULL, f.planned_bid_basis)            AS planned_bid_basis,
  IF(f.side_b = 'GOOD', NULL, ROUND(f.planned_bid_p6, 2))     AS repair_bid_p6,
  f.probe_start_bid,
  -- v27.146 (plan step 4, violation 27): the two inputs a seat's CLICK TARGET is derived
  -- from. Published so SP_BUILD_NEXT_WEEK_PLAN can write the target without re-deriving a
  -- constant this view already owns — a second copy of click_goal_day would drift the day
  -- the register changes it. Neither column changes any decision here.
  f.click_goal_day, f.seat_cpc,
  f.is_probe, f.holdout, f.holdout_member, f.holdout_eligible_from,
  -- the plain sentence, printed on the book, the panel and the brief
  CASE f.verdict
    WHEN 'GOOD' THEN FORMAT(
      'GOOD on the window — %d orders on $%.2f of ad spend from %t to %t, returning %.2f gross-profit dollars per ad dollar against the %s bar of %.2f. The good side is never cut and is not re-priced (P-4), and this row carries no planned price.',
      f.w_ord, f.w_sp, f.window_from, f.window_to, COALESCE(f.ret_corrected, 0), f.family, f.family_bar)
    WHEN 'HELD_UNSETTLED' THEN
      CASE
        WHEN f.held_despite_evidence THEN FORMAT(
          'HELD, BUT THE WINDOW HAS ALREADY SPOKEN — %d orders on $%.2f of ad spend from %t to %t returning %.2f per ad dollar, CORRECTED for the sales still arriving, against the %s bar of %.2f. That is not a keyword waiting for evidence; it is a keyword whose evidence says LOSING. The guard holds it on the good side anyway (P-14b), where P-4 forbids cutting or re-pricing it. The hold is a DELAY bounded by a clock, not a veto.',
          f.w_ord, f.w_sp, f.window_from, f.window_to, COALESCE(f.ret_corrected, 0), f.family, f.family_bar)
        -- the biggest population the guard held before P-14c, and the one nothing used to name
        WHEN f.held_with_no_sale THEN FORMAT(
          'HELD, AND THE WINDOW SOLD NOTHING — $%.2f of ad spend and %d clicks from %t to %t bought nothing at all, so this window carries no gross profit. The settle correction cannot change that: it SCALES gross profit, and no factor turns zero into a sale, so "promotion on fresh evidence" is not available to this row. It keeps the good side only because the window that started this hold has not settled yet (P-14b) — and P-4 then forbids cutting or re-pricing it. THE HOLD HAS AN END.',
          f.w_sp, f.w_clk, f.window_from, f.window_to)
        ELSE FORMAT(
          'HELD — this keyword was good and the window that started this hold has not settled, so it is not demoted today (P-14b). %s sales accrue for %d days; this window runs %t to %t.',
          f.channel, f.settle_days, f.window_from, f.window_to)
      END || f.hold_clause || f.last_day_clause
    WHEN 'GRACE' THEN FORMAT(
      -- F3 (v27.165): the anchored rule, in the words P-17 rules it. Through v27.160 this read "keeps
      -- the good side for ONE quiet window (P-5)" beside a run of 7 nights on a 3-day window.
      'GRACE — the ladder calls this a settled winner (%s) and its window is quiet (%d order(s) on $%.2f). A proven winner keeps the good side, held, not cut (P-5): grace lasts %d nightly judgments (the window length in force when it was granted, %t) through %t (P-17, Ori 2026-10-02).%s %s',
      f.ladder_state, f.w_ord, f.w_sp,
      f.grace_window_days_pub, f.grace_since_pub,
      DATE_ADD(f.grace_since_pub, INTERVAL f.grace_window_days_pub - 1 DAY),
      IF(f.good_side_no_sale,
         FORMAT(' BUT THE WINDOW SOLD NOTHING: %d clicks and $%.2f of ad spend bought nothing at all, so "quiet" here means money spent with no return, not a keyword that was simply not shown. P-5 reads a quiet window as one under the order floor, which this is; the settle correction cannot change it either, because it scales gross profit and this window has none. P-4 then forbids cutting or re-pricing it.',
                f.w_clk, f.w_sp),
         ''),
      IF(f.grace_limit_armed,
         FORMAT('From the night after %t grace is SPENT and is refused every night until this keyword earns a GOOD window back, after which rule B stands on the next quiet one — though the P-14b guard may still delay a demotion (P-14c, P-18).',
                DATE_ADD(f.grace_since_pub, INTERVAL f.grace_window_days_pub - 1 DAY)),
         'THE GRACE LIMIT IS NOT ARMED TONIGHT: it is read from the live plan\'s own history in FACT_PLAN_NEXT_WEEK, and that table holds no partition EARLIER THAN TODAY — so tonight is counted as the first night of this grace. SP_BUILD_NEXT_WEEK_PLAN writes tonight\'s partition at the end of the pass (orchestrator 20.8c), and from the next run the limit reads it.'))
    WHEN 'LOSING' THEN FORMAT(
      'LOSING on the window — %d orders on $%.2f of ad spend returning %.2f per ad dollar, under the %s bar of %.2f. ',
      f.w_ord, f.w_sp, COALESCE(f.ret_corrected, 0), f.family, f.family_bar) || f.seat_clause || f.guard_clause
    WHEN 'ONE_ORDER' THEN FORMAT(
      'WAITING, one order — one order on $%.2f of ad spend is not evidence whatever the return, so this keyword is on the not-good side. ',
      f.w_sp) || f.seat_clause || f.guard_clause
    WHEN 'NO_SALE' THEN FORMAT(
      'NO SALE — $%.2f of ad spend and %d clicks from %t to %t bought nothing. ',
      f.w_sp, f.w_clk, f.window_from, f.window_to) || f.seat_clause || f.guard_clause
    ELSE FORMAT(
      'NOT SERVING — no spend and no clicks from %t to %t. There is nothing to repair and nothing arriving later. ',
      f.window_from, f.window_to) || f.seat_clause || f.guard_clause
  END || f.memory_clause AS sentence,
  CASE
    WHEN NOT f.served AND f.w_gp = 0 THEN 'nothing was corrected and nothing is arriving: a keyword that took no clicks in the window has no sales in flight, so the settle question does not arise for this row (P-14a)'
    ELSE CASE f.settle_arm
    WHEN 'PROMOTED_ON_FRESH'      THEN 'the settle correction promoted it: uncorrected it read under the bar, corrected for the sales still arriving it reads at or above it (P-14a)'
    WHEN 'HELD_UNSETTLED'         THEN 'the asymmetric guard decided it: promotion is allowed on fresh evidence, demotion waits for the window to settle (P-14b) -- '
      || IF(f.hold_kept_by = 'STRONG_DAY_IN_WINDOW',
            'kept because the very good day that started the hold is still inside the judged window (P-18)',
            'granted because the last complete day was very good (P-14c)')
      || IF(f.w_gp = 0,
            ' — but not on THIS row: the correction scales gross profit and this window has none, so no factor can promote it and only the guard is holding it',
            IF(NOT f.settle_curve_available,
               ' — and the curve could not answer for at least one day of this window, so nothing was corrected and the guard is alone here too',
               ''))
    WHEN 'UNCORRECTED_NO_CURVE'   THEN 'the settle curve could not answer for this channel and age, so nothing was corrected and the guard alone protects this row (P-14a)'
    WHEN 'NOT_CORRECTABLE_NO_GP'  THEN 'the settle correction could NOT help this row and no correction was applied: it scales gross profit and this window has none, so only the order floor (P-3) or the guard (P-14b) can change this side (P-14a)'
    WHEN 'SETTLED'                THEN 'the window has settled, so the record is read exactly as it stands, with no correction and no guard'
    ELSE 'the window record was corrected for the sales still arriving, using the published settle curve (P-14a)'
    END
  END AS settle_arm_sentence
FROM (
  SELECT f2.*,
    -- what happens to this keyword next, in words — and it names the holdout wherever it names a
    -- seat, because holdout membership silences the plan from eligible_from, not from today (C15).
    -- EVERY BRANCH IS DECIDED BY is_candidate FIRST (v27.135). The v27.134 holdout branch was
    -- tested ahead of the NOT_SERVING branch, so 41 dormant keywords in holdout campaigns were
    -- told in words that they "compete for a seat at the repaired price today" while their own
    -- is_candidate column refused them one — and C15 could not catch it, because it only asked
    -- whether the word "holdout" appeared, never whether the row actually competes.
    CASE
      WHEN f2.holdout THEN FORMAT(
        'Its campaign is in the HOLDOUT arm (from %t), so the plan proposes no move for it at all and it does not compete for a seat.',
        f2.holdout_eligible_from)
      -- a not-good keyword that took no spend and no clicks and that no probe nominates: there is
      -- no repair to buy, so it takes no seat AND no queue position. Spec §9's "one seat or one
      -- queue position" is a guarantee about CANDIDATES; this row simply has no move, and saying
      -- so is what makes the plan readable end to end.
      WHEN NOT f2.is_candidate THEN
        'It does not compete for a seat and it is not queued or parked either: it took no spend and no clicks in the window and the probe list does not nominate it, so there is nothing to repair and the plan proposes no move for it at all.'
      -- v27.157: every seat branch names its price through price_clause (P-19 / P-25 / P-6)
      WHEN f2.holdout_member THEN FORMAT(
        'It competes for a seat at %s today, but its campaign joins the HOLDOUT arm on %t, after which the plan proposes no move for it.',
        f2.price_clause, f2.holdout_eligible_from)
      WHEN f2.verdict = 'NOT_SERVING' THEN FORMAT(
        'It took no spend and no clicks in the window, so it competes for a seat only because the probe list nominates it (P-11), at %s; if it does not get one it queues at the park price %s.',
        f2.price_clause,
        IF(f2.bid_park IS NULL, '(no park price is published for this keyword)',
           FORMAT('$%.2f (%s)', f2.bid_park, f2.bid_park_source)))
      ELSE FORMAT(
        'It competes for a seat at %s; if it does not get one it queues at the park price %s.',
        f2.price_clause,
        IF(f2.bid_park IS NULL, '(no park price is published for this keyword)',
           FORMAT('$%.2f (%s)', f2.bid_park, f2.bid_park_source)))
    END AS seat_clause,
    -- P-14c, in words, on the NOT-GOOD side: why the guard did not hold a keyword that was good.
    CASE f2.guard_released_by
      WHEN 'LAST_DAY_NOT_STRONG' THEN FORMAT(
        ' This keyword was on the good side and its window has not settled, but the guard does not hold it: its last complete day (%t) was not very good (%d order(s) on $%.2f%s), and a window that is losing with a last day that did not clearly win is judged on the window (P-14c, Ori 2026-09-17).',
        f2.window_to, f2.last_day_ord, f2.last_day_sp,
        IF(f2.last_day_ord > 0,
           FORMAT(', %.2f per ad dollar corrected against the %.2f a very good day needs', COALESCE(f2.last_day_ret, 0), f2.family_bar * f2.strong_day_mult),
           ''))
        -- P-18: a hold run that was in force lifted because its very good day left the window
        || IF(f2.hold_since IS NOT NULL, FORMAT(
             ' The hold that began on %t because %t was very good lifts tonight: that day is no longer inside the judged window (%t to %t), and the last day did not earn a new one (P-18).',
             f2.hold_since, f2.hold_strong_day, f2.window_from, f2.window_to), '')
      WHEN 'HOLD_EXPIRED' THEN FORMAT(
        ' This keyword was on the good side and %s, but the hold that began on %t has run its clock (the window that started it settled on %t), so rule B judges the numbers tonight (P-14b).',
        IF(f2.last_day_strong,
           FORMAT('its last complete day (%t) was very good', f2.window_to),
           FORMAT('the very good day that started its hold (%t) is still inside the judged window', f2.hold_strong_day)),
        f2.hold_since, f2.hold_settles_on)
      ELSE ''
    END AS guard_clause,
    -- P-18 + fix #16: the hold's two limits, on every HELD row from its first night.
    IF(f2.verdict = 'HELD_UNSETTLED', FORMAT(
        ' Held since %t because %t was very good; that day leaves the judged window after the window ending %t, and the hold lifts then or when its window settles on %t, whichever is first (P-18).',
        f2.hold_since_pub, f2.hold_strong_day_pub,
        DATE_ADD(f2.hold_strong_day_pub, INTERVAL f2.window_days - 1 DAY),
        f2.hold_settles_on_pub), '') AS hold_clause,
    -- ...and on the HELD side: what earned the wait, or what is still earning it.
    CASE
      WHEN f2.hold_kept_by = 'LAST_DAY' THEN FORMAT(
        ' Its last complete day (%t) was VERY GOOD: %d order(s) on $%.2f returning %.2f per ad dollar, corrected, %.1fx the %s bar. That is what earns the wait (P-14c); a losing window whose last day only won a little would be judged on the window.',
        f2.window_to, f2.last_day_ord, f2.last_day_sp, COALESCE(f2.last_day_ret, 0),
        COALESCE(SAFE_DIVIDE(f2.last_day_ret, NULLIF(f2.family_bar, 0)), 0), f2.family)
      WHEN f2.hold_kept_by = 'STRONG_DAY_IN_WINDOW' THEN FORMAT(
        ' Its last complete day (%t) was not very good (%d order(s) on $%.2f, %.2f per ad dollar corrected, %.1fx the %s bar), but the very good day that started this hold (%t) is still inside the judged window %t to %t, so the wait it earned is not over (P-18, Ori 2026-10-02); a losing window with no very good day left in it is judged on the window.',
        f2.window_to, f2.last_day_ord, f2.last_day_sp, COALESCE(f2.last_day_ret, 0),
        COALESCE(SAFE_DIVIDE(f2.last_day_ret, NULLIF(f2.family_bar, 0)), 0), f2.family,
        f2.hold_strong_day_pub, f2.window_from, f2.window_to)
      ELSE ''
    END AS last_day_clause,
    -- P-29: a memory that a GOOD window inside an unwritten gap cleared tonight, on every row
    IF(f2.memory_cleared_by_gap IS NOT NULL, FORMAT(
        ' MEMORY CLEARED (P-29): the %s memory this keyword carried from before nights no plan was written for was cleared tonight, because the window ending %t, judged by one of those nights, reads GOOD on the ads record; it is not honoured.',
        CASE f2.memory_cleared_by_gap WHEN 'GRACE' THEN 'grace' WHEN 'HOLD' THEN 'hold'
             ELSE 'grace and hold' END,
        f2.memory_gap_good_window_to), '') AS memory_clause
  FROM final f2
) f
-- house rule: a total ordering, reaching the keyword key. P-20 (v27.157): P-7's score orders the
-- candidates it scores above zero; every candidate with no positive score (zero, or the rare
-- negative one: 2 of 978 live candidate-nights 08-23 .. 10-02) ranks below them all, by money
-- burned with no return, and clicks are only the tiebreak after that. GREATEST(rank_score, 0) is
-- Ori's "among candidates with no positive score" (R6): ordering on rank_score itself would put a
-- keyword that sold at a loss below every zero-sale one, whatever it burned.
ORDER BY f.family, f.side_b, GREATEST(f.rank_score, 0) DESC, f.rank_money_burned DESC, f.w_clk DESC,
         f.campaign_id, f.keyword_id;
