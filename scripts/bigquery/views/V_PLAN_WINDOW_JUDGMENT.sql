-- =============================================================================================
-- V_PLAN_WINDOW_JUDGMENT — v27.147 (2026-09-28): ONE ROW PER working-family keyword, carrying the
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
--               plan's own history: grace is SPENT until the keyword earns a GOOD window back
--               (the most recent GRACE is later than the most recent GOOD). Reading only LAST
--               NIGHT, as v27.134 did, bought one NIGHT on a plan that runs nightly, and made an
--               unserved winner oscillate GOOD / NOT_GOOD / GOOD every night — flipping the side
--               that the P-14b memory and the T+14 scorecard both read.
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
--               strong_day_mult x the family bar (both declared in the k CTE). Otherwise the
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
--               release against the rule it was made under, never against today's k CTE. Only
--               the final SELECT changed. Measured at deploy, 2026-10-01: the view before (HEAD's
--               body run as a query) and after, keyed on campaign x keyword, 361 rows each side,
--               every published column equal except seat_cost_per_day on 2 rows, which moved by
--               0.0001 at its 4-decimal rounding (0.343 / 0.3429 and 1.0805 / 1.0804). Every row
--               carried 1.5 and 1.
--   LOSING / ONE_ORDER / NO_SALE / NOT_SERVING — the not-good side.
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
-- SEAT COST (P-6) is spend at THAT price, not last window's spend: the window's spend per day
-- scaled linearly by the price change (the same linear bid-to-spend guess the seat register uses
-- on its day-one horizon). A candidate with no window spend is priced at the engine's seat
-- economics — seat_cpc times the register's declared click goal per day.
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
OPTIONS (description = "v27.154 follow-up (2026-10-01): publishes strong_day_mult and strong_day_min_orders (the P-14c settings of the k CTE) on every row so SP_BUILD_NEXT_WEEK_PLAN stores the rule each decision was judged under and FN_PLAN_SCORECARD grades against it; no verdict changes. v27.147 (2026-09-28) P-14c (Ori, 2026-09-17): the P-14b hold is granted ONLY when the last complete day of the window was very good -- at least 1 order and a corrected return of at least 1.5x the family bar, declared in the k CTE -- so a losing window whose last day won a little is judged on the window. Publishes last_day_sp/clk/ord/gp/gp_corrected/ret, last_day_strong and guard_released_by (LAST_DAY_NOT_STRONG | HOLD_EXPIRED) so SP_BUILD_NEXT_WEEK_PLAN asserts every demotion under the guard's preconditions carries this view's own reason instead of re-deriving the guard: the builder's v27.136 copy read P-14b as a veto while this view read it as a clock, and from the first expired clock (2026-08-29) the builder refused every partition for a month. held_with_no_sale is now FALSE by construction. Earlier: one row per working-family (HARVEST) keyword — the complete-days window from DE_PLAN_CONFIG for today's calendar state, fenced so no judged day is younger than age 2 (P-10 + P-14a), the keyword's record in it raw AND corrected for settle completion via V_PLAN_SETTLE_COMPLETION, the side rule B gives it (P-1/P-3), and the arms in the order P-5 then P-14b: the grace for a ladder-settled winner with a quiet window comes FIRST (v27.135 — with the guard first it reached 36 of 39 such winners, so the ruling that buys ONE window was replaced by the one that buys every window, the shipped reprice book named a different ruling on the same rows, and the published unguarded counterfactual was wrong by 28% of the pot), and the grace limit is ONE WINDOW read from the live plan's own history — spent until the keyword earns a GOOD window back — with grace_limit_armed publishing whether the plan has a partition EARLIER than today to read it from (v27.138: SP_BUILD_NEXT_WEEK_PLAN ships and writes that table nightly, so the old wording 'no builder writes it yet' was live and false in this description and in the row's own sentence). Then the P-14b asymmetric guard (promote on fresh evidence, never demote until the window has settled: SP 7 / SB 14; the guard requires that the keyword actually SERVED, because a keyword with no clicks has no sales in flight; and v27.138 gives the hold a CLOCK — it is anchored via hold_since / hold_settles_on to the window that TRIGGERED it and lifts when that window settles, because was_good reads last night's side and a held row's side is GOOD, which made the protected side a one-way door no keyword could ever leave and left P-5's one-window limit inert in money), with held_despite_evidence AND held_with_no_sale naming the two populations it holds — the second is the larger by money and used to be told that promotion is allowed on fresh evidence on a window with no gross profit to promote. Also the shadow plan A side (P-9), the repaired price capped at three 5% steps and floored at the row's own bid_floor (P-6) published on the NOT-GOOD side only because P-4 forbids re-pricing the good side, the seat cost at that price, the park price with a declared source and a bid_floor fallback, and the P-7 rank — whose two named factors are published separately (rank_dollars_at_stake, rank_closeness) because their product cancels the spend identically and the ordering is corrected gross profit alone. Every seat sentence branches on is_candidate, so no row is promised a seat its own column refuses it and a keyword with no seat and no queue position says so. Publishes settle_arm, decided_by and two plain sentences on every row. Judges only; SP_BUILD_NEXT_WEEK_PLAN does the potting, seating and queueing. Spec P-1..P-14, §3a. SOP: architecture/NEXT_WEEK_MONEY.md")
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
         14     AS settle_days_sb,    -- SB attribution window, complete days
         -- P-14c (Ori, 2026-09-17): the P-14b hold is granted only when the LAST complete day
         -- of the window was VERY GOOD -- at least strong_day_min_orders order(s) on that day
         -- and a corrected return of at least strong_day_mult x the family bar. Measured on the
         -- 45 keywords the expired clock was releasing on 2026-09-28: 7 sold on their last day,
         -- 6 clear 1.0x the bar, 4 clear 1.5x, 2 clear 2.0x. 1.5x is where a last day that
         -- "won a little" (3 orders at 1.29x the bar on a window returning 0.54) is judged on
         -- the window and a very good one (1.86x and up) earns the wait. A ruling constant,
         -- declared beside the settle days; move it to DE_PLAN_CONFIG if it becomes per-state.
         1.5    AS strong_day_mult,
         1      AS strong_day_min_orders
),
caps AS (
  SELECT k.*,
         POW(1 + k.material_step, k.blind_steps) - 1 AS cap_up,
         1 - POW(1 - k.material_step, k.blind_steps) AS cap_down
  FROM k
),
today AS (
  SELECT CURRENT_DATE('America/Los_Angeles') AS d_la,
         CURRENT_DATE('America/New_York')    AS d_ny
),
cfg AS (
  -- Every setting, min_orders included. Copy this CTE, not a subset of it.
  SELECT calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders
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
-- read. So grace is SPENT until the keyword earns the good side back on its own: the most recent
-- GRACE is later than the most recent GOOD (or there has never been a GOOD). That is "one quiet
-- window, held; a second and rule B stands" as P-5 words it, and it is stable under a nightly run.
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
plan_hist AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         as_of, side, verdict, settle_due_on,
         MAX(as_of) OVER (PARTITION BY CAST(campaign_id AS STRING),
                                       CAST(keyword_id AS STRING)) AS last_as_of,
         -- the last night this keyword was NOT under the guard; the current hold run starts after it
         MAX(IF(verdict != 'HELD_UNSETTLED', as_of, NULL))
           OVER (PARTITION BY CAST(campaign_id AS STRING),
                              CAST(keyword_id AS STRING)) AS last_unheld_on
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan AND as_of < (SELECT d_la FROM today)
),
prior AS (
  SELECT cid, kid,
         TRUE AS prior_seen,
         LOGICAL_OR(side = 'GOOD' AND as_of = last_as_of) AS prior_good,
         MAX(IF(verdict = 'GRACE', as_of, NULL))          AS last_grace_on,
         (MAX(IF(verdict = 'GRACE', as_of, NULL)) IS NOT NULL
          AND (MAX(IF(verdict = 'GOOD', as_of, NULL)) IS NULL
               OR MAX(IF(verdict = 'GRACE', as_of, NULL))
                  > MAX(IF(verdict = 'GOOD', as_of, NULL))))  AS prior_grace,
         -- the hold run in force: when it started, and the settle date of the window that started
         -- it. MIN over the run picks the FIRST night's settle_due_on, because settle_due_on rolls
         -- forward with the window.
         MIN(IF(verdict = 'HELD_UNSETTLED'
                AND (last_unheld_on IS NULL OR as_of > last_unheld_on), as_of, NULL))
           AS hold_since,
         MIN(IF(verdict = 'HELD_UNSETTLED'
                AND (last_unheld_on IS NULL OR as_of > last_unheld_on), settle_due_on, NULL))
           AS hold_settles_on
  FROM plan_hist
  GROUP BY 1, 2
),
-- Whether the one-window limit can bite AT ALL. Until Task 2's builder writes the first live plan
-- there is no history, prior_grace is FALSE on every row, and grace is re-granted every night — so
-- the GRACE sentence must say the limit is not armed rather than promise a limit nothing enforces.
armed AS (
  SELECT (COUNT(*) > 0) AS grace_limit_armed FROM plan_hist
),
probes AS (
  SELECT DISTINCT CAST(keyword_id AS STRING) AS kid FROM `onyga-482313.OI.T_LIFT_PROBES`
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
    COALESCE(pr.prior_grace, FALSE) AS prior_grace,
    pr.last_grace_on,
    pr.hold_since,
    pr.hold_settles_on,
    am.grace_limit_armed,
    (pb.kid IS NOT NULL) AS is_probe,
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
    caps.strong_day_mult, caps.strong_day_min_orders,
    t.d_la AS today_la
  FROM ks
  CROSS JOIN win
  CROSS JOIN caps
  CROSS JOIN today t
  CROSS JOIN armed am
  LEFT JOIN camp cp ON cp.cid = CAST(ks.campaign_id AS STRING)
  LEFT JOIN rec ON rec.cid = CAST(ks.campaign_id AS STRING) AND rec.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN prior pr ON pr.cid = CAST(ks.campaign_id AS STRING) AND pr.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN probes pb ON pb.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN seatecon se ON se.cid = CAST(ks.campaign_id AS STRING) AND se.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN holdout h ON h.cid = CAST(ks.campaign_id AS STRING)
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
    -- P-6: the repaired price. Cap three 5% steps either way, floor at the row's own floor,
    -- ceiling the house $2.00 on a raise.
    LEAST(
      GREATEST(
        LEAST(
          GREATEST(COALESCE(b.affordable_bid, b.current_bid), b.current_bid * (1 - b.cap_down)),
          b.current_bid * (1 + b.cap_up)),
        COALESCE(b.bid_floor, 0)),
      GREATEST(b.raise_ceiling, b.current_bid))            AS planned_bid_raw
  FROM base b
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
     AND d.today_la > d.hold_settles_on)                                        AS hold_expired
  FROM derived d
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
      -- clock above. Measured 2026-09-28: of 45 keywords the expired clock was releasing, 4 had
      -- a very good last day; 41 are judged on the window.
      WHEN s.was_good AND NOT s.settled AND s.served AND NOT s.hold_expired
           AND s.last_day_strong THEN 'HELD_UNSETTLED'
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
    CASE
      WHEN IF(j.verdict IN ('GOOD','HELD_UNSETTLED','GRACE'), 'GOOD', 'NOT_GOOD') = 'NOT_GOOD'
           AND j.was_good AND j.served AND NOT j.settled THEN
        CASE WHEN NOT j.last_day_strong THEN 'LAST_DAY_NOT_STRONG'
             WHEN j.hold_expired        THEN 'HOLD_EXPIRED'
             ELSE 'UNEXPLAINED' END
      ELSE NULL
    END AS guard_released_by,
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
    -- P-6: seat cost = spend at the repaired price, per day. P-4: NULL on the good side.
    IF(j.verdict IN ('GOOD', 'HELD_UNSETTLED', 'GRACE'), NULL,
      CASE
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
    -- §4 step 3, hoisted out of the SELECT so the seat SENTENCE is built from the same expression
    -- that decides candidacy and the two can never disagree (v27.135; before this repair 41 rows
    -- were promised a seat in words that their own is_candidate refused them).
    (IF(j.verdict IN ('GOOD','HELD_UNSETTLED','GRACE'), 'GOOD', 'NOT_GOOD') = 'NOT_GOOD'
     AND NOT j.holdout
     AND (j.verdict != 'NOT_SERVING' OR j.is_probe))                         AS is_candidate
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
  f.hold_since, f.hold_settles_on, f.hold_expired,
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
  f.current_bid, f.bid_floor,
  f.bid_park, f.bid_park_source, f.bid_park_seat_econ,
  -- P-4: the good side carries no executable price and no seat cost
  IF(f.side_b = 'GOOD', NULL, ROUND(f.planned_bid_raw, 2)) AS planned_bid,
  ROUND(f.seat_cost_per_day, 4) AS seat_cost_per_day,
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
          'HELD, BUT THE WINDOW HAS ALREADY SPOKEN — %d orders on $%.2f of ad spend from %t to %t returning %.2f per ad dollar, CORRECTED for the sales still arriving, against the %s bar of %.2f. That is not a keyword waiting for evidence; it is a keyword whose evidence says LOSING. The guard holds it on the good side anyway (P-14b), where P-4 forbids cutting or re-pricing it. The hold is a DELAY bounded by a clock, not a veto: it lifts after %t, when the window that started it has settled and rule B judges the numbers (v27.138).',
          f.w_ord, f.w_sp, f.window_from, f.window_to, COALESCE(f.ret_corrected, 0), f.family, f.family_bar,
          COALESCE(f.hold_settles_on, f.settle_due_on))
        -- the biggest population the guard holds, and the one nothing used to name in words
        WHEN f.held_with_no_sale THEN FORMAT(
          'HELD, AND THE WINDOW SOLD NOTHING — $%.2f of ad spend and %d clicks from %t to %t bought nothing at all, so this window carries no gross profit. The settle correction cannot change that: it SCALES gross profit, and no factor turns zero into a sale, so "promotion on fresh evidence" is not available to this row. It keeps the good side only because its own settled 90-day record clears the %s bar of %.2f and the window that started this hold has not settled yet (P-14b) — and P-4 then forbids cutting or re-pricing it. THE HOLD HAS AN END: it lifts after %t, the settle date of the window that triggered it (v27.138 — before that repair the hold renewed itself every night and was permanent).',
          f.w_sp, f.w_clk, f.window_from, f.window_to, f.family, f.family_bar,
          COALESCE(f.hold_settles_on, f.settle_due_on))
        ELSE FORMAT(
          'HELD — this keyword was good and the window that started this hold has not settled, so it is not demoted today (P-14b). %s sales accrue for %d days; this window runs %t to %t and the hold lifts after %t, when the sales it is waiting for have landed and rule B judges the numbers (v27.138 — before that repair the hold renewed itself against a window that rolls forward nightly, so it never expired at all).',
          f.channel, f.settle_days, f.window_from, f.window_to,
          COALESCE(f.hold_settles_on, f.settle_due_on))
      END || f.last_day_clause
    WHEN 'GRACE' THEN FORMAT(
      'GRACE — the ladder calls this a settled winner (%s) and its window is quiet (%d order(s) on $%.2f). A proven winner keeps the good side for ONE quiet window (P-5), held, not cut.%s %s',
      f.ladder_state, f.w_ord, f.w_sp,
      IF(f.good_side_no_sale,
         FORMAT(' BUT THE WINDOW SOLD NOTHING: %d clicks and $%.2f of ad spend bought nothing at all, so "quiet" here means money spent with no return, not a keyword that was simply not shown. P-5 reads a quiet window as one under the order floor, which this is; the settle correction cannot change it either, because it scales gross profit and this window has none. P-4 then forbids cutting or re-pricing it.',
                f.w_clk, f.w_sp),
         ''),
      IF(f.grace_limit_armed,
         'This is that window: grace is now SPENT and will be refused every night until this keyword earns a GOOD window back, after which rule B stands on the next quiet one — though the P-14b guard may still delay the demotion until the window that triggers it has settled (v27.138: the guard is a clock, not a veto).',
         'THE ONE-WINDOW LIMIT IS NOT ARMED TONIGHT: it is read from the live plan\'s own history in FACT_PLAN_NEXT_WEEK, and that table holds no partition EARLIER THAN TODAY for this keyword — so there is nothing yet for the limit to read and grace is granted again. SP_BUILD_NEXT_WEEK_PLAN writes tonight\'s partition at the end of the pass (orchestrator 20.8c), and from the next run this reads TRUE and the limit bites.'))
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
  END AS sentence,
  CASE
    WHEN NOT f.served AND f.w_gp = 0 THEN 'nothing was corrected and nothing is arriving: a keyword that took no clicks in the window has no sales in flight, so the settle question does not arise for this row (P-14a)'
    ELSE CASE f.settle_arm
    WHEN 'PROMOTED_ON_FRESH'      THEN 'the settle correction promoted it: uncorrected it read under the bar, corrected for the sales still arriving it reads at or above it (P-14a)'
    WHEN 'HELD_UNSETTLED'         THEN 'the asymmetric guard decided it: promotion is allowed on fresh evidence, demotion waits for the window to settle (P-14b) -- granted because the last complete day was very good (P-14c)'
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
      WHEN f2.holdout_member THEN FORMAT(
        'It competes for a seat at the repaired price $%.2f today, but its campaign joins the HOLDOUT arm on %t, after which the plan proposes no move for it.',
        ROUND(f2.planned_bid_raw, 2), f2.holdout_eligible_from)
      WHEN f2.verdict = 'NOT_SERVING' THEN FORMAT(
        'It took no spend and no clicks in the window, so it competes for a seat at the repaired price $%.2f only because the probe list nominates it (P-11); if it does not get one it queues at the park price %s.',
        ROUND(f2.planned_bid_raw, 2),
        IF(f2.bid_park IS NULL, '(no park price is published for this keyword)',
           FORMAT('$%.2f (%s)', f2.bid_park, f2.bid_park_source)))
      ELSE FORMAT(
        'It competes for a seat at the repaired price $%.2f; if it does not get one it queues at the park price %s.',
        ROUND(f2.planned_bid_raw, 2),
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
      WHEN 'HOLD_EXPIRED' THEN FORMAT(
        ' This keyword was on the good side and its last complete day (%t) was very good, but the hold that began on %t has run its clock (the window that started it settled on %t), so rule B judges the numbers tonight (P-14b).',
        f2.window_to, f2.hold_since, f2.hold_settles_on)
      ELSE ''
    END AS guard_clause,
    -- ...and on the HELD side: what earned the wait.
    IF(f2.verdict = 'HELD_UNSETTLED', FORMAT(
        ' Its last complete day (%t) was VERY GOOD: %d order(s) on $%.2f returning %.2f per ad dollar, corrected, %.1fx the %s bar. That is what earns the wait (P-14c); a losing window whose last day only won a little would be judged on the window.',
        f2.window_to, f2.last_day_ord, f2.last_day_sp, COALESCE(f2.last_day_ret, 0),
        COALESCE(SAFE_DIVIDE(f2.last_day_ret, NULLIF(f2.family_bar, 0)), 0), f2.family), '') AS last_day_clause
  FROM final f2
) f
-- house rule: a total ordering, reaching the keyword key
ORDER BY f.family, f.side_b, f.rank_score DESC, f.w_clk DESC, f.campaign_id, f.keyword_id;
