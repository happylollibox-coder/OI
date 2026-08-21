-- V_OOB_KEYWORD — keyword layer of the Out-of-budget phase (Weekly Run). Spec: architecture/OOB_BUDGET_PHASE.md §v2.
--
-- v27.76 (2026-08-17, Task 4.9): THE EXPECTED-ORDERS GATE — the RAISE arm of the last-day veto no longer treats a 0.00x filling day as poor performance by default. Split: roas_1d <> 0 (sales landed and were poor) vetoes exactly as v27.75; roas_1d = 0/NULL is AMBIGUOUS ("no sales" vs "not attributed yet" — at age 1 we see ~85% of spend but only ~69% of sales, and 46% of at-volume keywords read exactly 0.00x) and vetoes ONLY when the zero is surprising: expected_orders_1d = clicks_1d * ord90/clk90 >= 3.0 (Poisson P(0|3) ~ 5%). No rate / no 90d orders => 0.0 => no veto: no history is no surprise, and the veto may only block where it HAS evidence. clk90/ord90/expected_orders_1d are now PUBLISHED (additive). THE CUT ARM IS UNTOUCHED — missing sales can only make a day look worse, so a fresh day already at/above 1.20x is conservative proof.
-- v27.75 (2026-08-17, Task 4.8): THE LAST-DAY VETO — the standalone filling day (clicks_1d/roas_1d) may only HOLD a published move, never drive one: a RAISE at >10 clicks under 0.50x waits a day; a CUT at >10 clicks at/above 1.20x waits a day. Thin outer wrapper over the published rows (pure functions of published columns), plain HOLD + bid NULLed; direction = suggested-vs-current comparison, never action name; tunables in the lastday CTE. Structurally no collision with the v27.65 zero-sale floor (its rows are cuts at 0.00x; the cut veto needs >= 1.2).
-- v27.74 (2026-08-17, Task 4.7): COMPLETE-DAYS WINDOWS — every trailing multi-day ads window ends at wm-1 (7d clk7/sp7, 90d roas90 SP+SB, 3d ev_cpc/conv_share via new clk3/sp3); last-day reads (clk1/roas1) and prev2 (already wm-2..wm-1) unchanged; LY/seasonal calendar windows untouched.
--
-- ############################################################################
-- # v27.65 — THE ZERO-SALE EVIDENCE FLOOR: 10+ CLICKS AT 0.00x BRAKES ≥ 15%.  #
-- ############################################################################
-- (Engine-finalization Task 1.3, 2026-08-16. Root case: Ori 2026-08-13, "this campaign in oob one
-- keyword has 22 clicks and no bid trimming. why?") Every DARK_BRAKE step was scaled by
-- max(5%, {15%|30%} x pct_dark) — CAMPAIGN darkness. When pct_dark reads low (a campaign OOB-owned
-- on the 7-day hysteresis can sit at 0% dark TODAY), every band collapses to the 5% minimum
-- regardless of how loudly the keyword's own day screamed: BALL Mint substitutes, 23 clicks at
-- 0.00x, braked 5%/day — 12+ days to the floor while burning ~$8/day. The fix is a THIRD term in
-- every brake LEAST (all 3 bid arms + all 3 reason mirrors, one shared fragment so they can never
-- drift): clk1 >= 10 AND roas1 = 0.00 AND roas90 < 1.0 ⇒ the day is EVIDENCE, step >= 15%.
-- Proven seats (roas90 >= 1.0) are exempt by construction — v27.47/v27.63 doctrine, a winner is
-- paced 5%, never punished for one unsettled day. Buffett test: this is valuation (the click is
-- demonstrably not worth the price today, at volume), not tape-chasing (the trigger is the
-- keyword's own record + own day, never the campaign's mood).
--
-- ############################################################################
-- # v27.63 — A WINNER IS NEVER FITTED DOWN TO THE CPC IT PAID AT THIS BID.    #
-- ############################################################################
-- (Ori 2026-08-13, pointing at a live FIT_CPC row on the panel: "this will starve it.")
-- The proven-seat exemption at the bottom of the ladder carries the comment "a proven keyword can
-- never fall through to TRIM_BID" — and it was UNREACHABLE for a converting keyword, because
-- `WHEN b.converting` matches earlier in the same CASE. So the one branch written to protect
-- winners never ran on winners. All three live FIT_CPC rows were role=WINNER and proven:
--     VIDEO- BALL  "surprise balls for girls"       $0.45 -> $0.38   4c 14.03x   90d 1.67x
--     ME-SBS       "girls journals age 10-12"       $1.00 -> $0.85   7c  2.06x   90d 1.59x
--     ME-VIDEO     "diy journal kit for girls 8-14" $0.54 -> $0.46   2c  0.00x   90d 1.99x
-- and two of the three sat at 0% dark that day — in this view on the 7-day cap hysteresis, while
-- the reason string lectured them about "never raise while dark".
-- WHY FIT_CPC STARVES A WINNER: the realized CPC is the price the keyword paid AT THE CURRENT BID.
-- VIDEO- BALL paid $0.33-0.35 bidding $0.45. Set the bid to $0.38 and every auction that cleared
-- between $0.38 and $0.45 is gone — the DEAR ones, which is where top-of-search sits. You keep the
-- cheap tail and lose the converting head, to save ~5c on a click returning 14x. The trade is only
-- sound when the click is NOT worth what it costs; on a proven keyword it is.
-- THE FIX is placement, not new policy: v27.47's proven rule (>4 clicks yesterday -> flat 5% pace
-- toward the floor, at/below the bar HOLD) is copied verbatim into the converting CASE, above the
-- FIT_CPC arm, in all three parallel CASEs (suggested_bid / bid_action / bid_reason). The
-- winner-concentrated >=80% arm is deliberately UNTOUCHED — Ori approved its -5%/day glide on
-- 2026-08-05 ("dark is never a hold"). Unproven converters still get FIT_CPC: that is the case the
-- branch was written for.
--
-- ############################################################################
-- # v27.62 — THE GP RULE: READ FACT_AMAZON_ADS.GROSS_PROFIT. NEVER RECOMPUTE. #
-- ############################################################################
-- (Ori 2026-08-13, found by checking the panel against Amazon.) Every gross-profit number sourced
-- from FACT in this view is now the STORED FACT_AMAZON_ADS.GROSS_PROFIT column. The old formula
--     Ads_sales - COALESCE(T_PRICE_COST_TIER.tier_cost, TOTAL_COST_PER_UNIT) * Ads_units
--   LEFT JOIN T_PRICE_COST_TIER pct ON Ads_units > 0
--     AND pct.unit_price = ROUND(SAFE_DIVIDE(Ads_sales, Ads_units), 2)
-- and its join ARE GONE. The join looked the cost tier up by an "implied unit price" of
-- Ads_sales / Ads_units — which is NOT the product's price: Ads_sales carries HALO sales of OTHER
-- products (~79% purchased-vs-advertised divergence in this account) while Ads_units does not
-- correspond to them. PROVEN on VIDEO- BALL / 2026-08-12: implied $24.39 for a $13.99 product
-- matched a ~$21.50 tier, overrode the real TOTAL_COST_PER_UNIT of $9.77, and collapsed
-- GP $229.16 -> $37.17 — a GP-ROAS of 3.69x read as 0.60x, on a campaign Amazon's own console
-- reports at $331.08 sales / $64.05 spend that day. Arithmetic: 317.09 - 9.77 x 13 = 229.16 =
-- FACT.GROSS_PROFIT exactly. WHY IT EXISTED: FACT began charging tier COGS at LOAD time on
-- 2026-08-01; these views predate that and were never updated, so they re-derived a number that
-- was already correct — and got it wrong. WHY IT HID: account-wide over 30 days the two agree to
-- ~3% (0.845 vs 0.817). The damage is PER ROW, on exactly the rows a decision is made about.
-- The SB arm is NOT affected and is deliberately untouched: it comes from the SB report stream,
-- not FACT, and derives its margin from the campaign's dominant mapped ASIN cost ratio.
-- Same fix, same day: V_LOW_STOCK_ADS (v27.61) and the other seven engine views.
--
-- One row per (OOB campaign, target) — SP keywords/auto clauses/product targets AND SB keywords/
-- product targets (v2.1, Ori 2026-07-30: "i cant see sb keywords as a hierarchy") — with a bid
-- suggestion built from the SAME constants as the launch controller, applied to every out-of-budget
-- campaign regardless of engine (launch or working). SP signals from FACT + price-tier COGS; SB from
-- the SB reports with the est. net ROAS via the campaign's mapped-ASIN cost ratio (same method as
-- V_SB_LAUNCH_TARGET — sb config mirrors sb_keyword/sb_product_target are minutes-fresh KEEP_RAW).
--
-- WHY BIDS AT ALL: a bid cut does not reduce spend — the budget caps spend either way. It lowers
-- CPC so the SAME budget buys more hours of the day: dark ↓ while utilization stays ~100%, which is
-- the phase's goal. Measured 2026-07-30: 69% of dark-campaign spend sat on 6+-click keywords.
--
-- RULES (Ori 2026-07-30):
--   CONVERTING (net ROAS >= 1.0 on last day OR prior-2d) — EXEMPT from the click band:
--     campaign capping and not itself strong → HOLD (the budget raise is the lever, not the bid)
--     both windows > 1.5x → RAISE_STRONG +30% · last day > 1.2x → RAISE_WEAK +15% · cap $2.00
--   NOT CONVERTING → the budget-constrained ladder below (PARK / TRIM_BID / DARK_BRAKE / ACTIVATE).
--     ⚠️ The old "< 4 PROBE · 4–5 HOLD · >= 6 SLOW" band is RETIRED here and lives only in the two
--     LAUNCH engines (V_LAUNCH_PHASE1, V_SB_LAUNCH_TARGET). This view emits no PROBE/SLOW action:
--     the brake is DARK_BRAKE, gated at >= 4 clicks yesterday (v27.18), and since v27.47 a 90d-proven
--     keyword loses its seat exemption above 4 clicks and brakes a flat 5% (Ori 2026-08-12).
--   1-day cooldown: changed < 1 day ago (FACT_PPC_CHANGE_LOG) → HOLD 'changed today'.
--
-- v27.42 (2026-08-08): SEASON-CONTEXT GATES — a new outp wrapper reads V_KEYWORD_CONTEXT_GATE
-- (keyword rows only: the join carries NOT is_auto AND NOT is_pt). BLOCK_CUT (calibration PASS):
-- current-occurrence settled >= 15c at GP-ROAS >= 1.0 -> every cut/park/brake (DARK_BRAKE, PARK,
-- PARK_WAIT, TRIM_BID, EASE, FIT_CPC) resolves to HOLD. ENTRY_BLOCK STOP (PASS only with the
-- half-allowance re-probe): prior same-family mature LOSS + half allowance spent without paying
-- back -> ACTIVATE (OOB's only new-spend action) resolves to HOLD. PARK_CONTEXT: calibration
-- FAIL — ADVISORY ONLY via context_gate/context_gate_reason, never moves an action or bid.
-- Precedence + calibration record: architecture/SEASON_CONTEXT_LEDGER.md §5-6.
--
-- v27.43 (2026-08-08): RE-PROBE ALLOWANCE ENFORCEMENT (FIX C) — the gate's entry_state now runs
-- on NEAR-SETTLED numbers (gate v27.43 FIX A: [occurrence_start, anchor-3]) with a 90d escape
-- hatch (FIX B: >= 100c at GP-ROAS >= 1.0 releases a would-be STOP). On ENTRY_BLOCK/PROBING rows,
-- ACTIVATE (OOB's only funding action) respects the remaining allowance: its bid is clamped to
-- LEAST(bid, remaining_allowance) when the remainder clears the row's bid_floor (v27.33 — a
-- clamped bid below its floor is a violation, so below-floor remainders resolve to HOLD:
-- "re-probe allowance exhausted"); a clamp landing on the current bid is no real move (v27.29)
-- -> HOLD. STOP behavior unchanged; its reason now shows the near-settled numbers.
--
-- v27.45 (2026-08-08): ONE BID OWNER — the population is no longer "pct_dark > 10 on the anchor
-- day" (which left 12 of the budget view's campaigns outside this engine while their budget rows
-- said "bids do the work"). It is now every V_OOB_BUDGET_PHASE campaign — PHASE membership itself
-- is V_CAMPAIGN_CAP_STATE.is_oob_owned (per-day dual signal, hysteresis enter >= 2 of 7 / exit at
-- 0). V_KEYWORD_LIFT emits DEFER_OOB for these campaigns: OOB owns the bids, no campaign in both
-- engines' emitting sets, none orphaned. Three consequences inside this view:
--   1. DEFENSE: an OOB-owned brand-defense campaign's keywords appear here but NEVER instruct —
--      bid_action 'DEFENSE', no bid (doctrine: defense bids are never touched by either engine;
--      the budget ladder is its remedy).
--   2. APPLIED-BID DOCTRINE (from V_KEYWORD_LIFT v27.4): a bid change uploaded within 48h that
--      (was applied TODAY America/Los_Angeles, or has not reached the config mirror yet,
--      |delta| > 0.005) holds the row — bid_action 'APPLIED_HOLD', no suggestion — instead of
--      re-deriving a step from DIM_KEYWORD's STALE bid (measured: 6 of 8 double-instructed rows
--      computed from the stale base; an applied CUT flipped into a RAISE on 'surprise balls').
--      Once the config syncs, suggestions resume FROM the applied bid. DEFER_OOB and APPLIED_HOLD
--      are no-change actions (v27.29 no-empty-promises exempt set).
--   3. Rows whose campaign anchor day came in light (pct_dark = 0) still run the seat model; the
--      v27.23 activation gate reads the 7d cap evidence too (pct_dark > 0 OR days_capped_7d >= 2)
--      so a chronically capped campaign never funds NEW keywords while it caps.
--
-- v27.46 (2026-08-09) guard batch:
--   A4 DARK_BRAKE SCALED BY 90d REALITY — the trigger at all three DARK_BRAKE sites is
--   unchanged (v27.17 clk1>10 volume override; v27.18 seated 4-click/click-hog brake; the flat
--   4-click brake); only the MAGNITUDE now reads the keyword's own 90d record (roas90, the
--   existing tier-COGS-corrected 90d net ROAS — its unsettled tail understates GP, which errs
--   toward the harder brake): roas90 >= 1.0 -> minimum ease 5%; 0.6 <= roas90 < 1.0 ->
--   max(5%, 15% x dark); roas90 < 0.6 OR no 90d data -> max(5%, 30% x dark). "Dark is never a
--   hold": the 5% minimum always stands; floors untouched; the BLOCK_CUT veto in the gated
--   layer still outranks every brake. roas90 exposed as an output column for verification.
--   TRIM_BID's max(15%, 30% x dark) is a trim, not the dark brake — deliberately untouched.
--   A3 SEASONAL_NOW vs GATE PRECEDENCE — a row with a mature same-context LOSS prior and gate
--   entry_state PROBING/STOP loses its seasonal authority unless converting (OOB's in-window
--   winner test — A2 doctrine: current-window conversion outranks prior-season memory) or
--   BLOCK_CUT-protected (structural: ENTRY_BLOCK is only emitted when BLOCK_CUT is not). The
--   emitted-instruction surface was already guarded (v27.42 STOP blocks ACTIVATE, v27.43 clamps
--   PROBING ACTIVATE to the remaining allowance); v27.46 neutralizes the PUBLISHED seasonal_now
--   column in the gated layer. Known limit (SEASON_CONTEXT_LEDGER.md §5.7): the inner seat
--   ordering still reads raw seasonal_now — gate columns cannot reach the seats CTE without
--   adding the gate subtree to this view's plan (planner-ceiling doctrine: edit in place only).
--
-- v27.48 (2026-08-09): REVIVAL MACHINERY — the engine consumes FACT_PARK_REVERDICT (the
-- SP_SNAPSHOT_PARK_REVERDICT snapshot of V_PARK_REVERDICT; a small (campaign, keyword) table —
-- NEVER the view: planner-ceiling doctrine). Ori's settle rule: "no condemnation before settle,
-- re-judgment at settle" (SEASON_CONTEXT_LEDGER.md §7). Iteration-6 root causes: engines
-- condemned keywords on clicks whose sales had not arrived (SP sales accrue to D+7; ~20% of the
-- Aug 2-6 park wave flipped to GP-ROAS >= 1.0 once settled), $1 ACTIVATE entries on keywords
-- with hundreds of lifetime clicks, seat queues ranking fresh losers over proven winners, and
-- engine parks landing over Ori's manual raises. Wiring:
--   1. SEAT PRIORITY — reverdict REVIVE rows join the proven tier of the seat ordering and rank
--      above fresh unproven rows inside it (settled-winner rank: fixes the queue-ranking half of
--      Cause 2 for revivals); CONFIRM_PARK rows sink with the tested losers and never re-seat.
--   2. ACTIVATE_REVIVE — a seated REVIVE row activates at the CALIBRATED revive bid
--      (clamp(min(pre-park bid, 1.1 x settled CPC), $0.31, $1.50) — computed in the snapshot),
--      NOT the $1 probe entry (these are proven records with anchors, not anchorless probes).
--      Same darkness gate + 20% pace as ACTIVATE (v27.23/v27.45: reviving into a dark campaign
--      splits the same money). Queue-stuck REVIVE rows HOLD — a budget decision for Ori
--      (slots = budget/$4), never a PARK_WAIT re-park (v27.29 no empty promises).
--   3. SETTLE VETO (engine_immune) — a keyword revived off a proven settled record, or carrying
--      a manual change < 14d old (Cause 3: Ori's hand outranks), is immune to PARK / PARK_WAIT
--      condemnations until 10 NEW settled clicks accrue — REVIVE_SETTLE_HOLD. DARK_BRAKE /
--      EASE / TRIM / FIT_CPC stay live same-day (dark is never a hold; the veto blocks only
--      condemnations). ACTIVATE_REVIVE and REVIVE_SETTLE_HOLD join the v27.29 exempt set
--      (REVIVE_SETTLE_HOLD is a no-change action; ACTIVATE_REVIVE always carries a real bid).
--   4. CONFIRM_PARK / manual parks never resurface — the generic ACTIVATE branch skips them
--      (a $1 activation on a settled-verified loser is Cause-2 behavior; a $1 activation over a
--      MANUAL park < 14d overrides Ori).
--   Gate precedence unchanged: the gated layer's ENTRY_BLOCK STOP/PROBING branches now catch
--   ACTIVATE_REVIVE exactly like ACTIVATE; BLOCK_CUT outranks as before. APPLIED_HOLD
--   (outermost) also catches ACTIVATE_REVIVE — an uploaded revival holds until Amazon syncs.
--
-- v27.53 (2026-08-12, Ori approved "do all engine work") — ITEM 2 the tested-loser PARK veto also
-- releases on the guard's settle_deferral_expired, and its reason publishes the real hard bound
-- instead of a settle_due a daily-clicking keyword never reaches; ITEM 7 NEW WAKE_STEP — 4 of the 5
-- keywords still stuck on the $1.00 wake on-ramp sit in OOB-owned campaigns, where V_KEYWORD_LIFT
-- can only ever say DEFER_OOB, so the step-down has to live here too; ITEM 8f MANUAL_HOLD no longer
-- swallows DARK_BRAKE. Spec: architecture/SEASON_CONTEXT_LEDGER.md §7.16.
--
-- v27.48.2 (2026-08-09, part 2): ENGINE GUARDS — consumes FACT_KEYWORD_GUARD (snapshot of
-- V_KEYWORD_GUARD, Task 20.5f; engines never read the view — planner-ceiling doctrine). The
-- snapshot joins ONLY at the gated layer (a small-table join on the final rowset) — the seat
-- CTEs are untouched, so the INNER seat ordering cannot read the settled-record key here
-- (same documented limitation as v27.46 A3 seasonal_now; the LIFT engine carries the
-- settled-first seat/cand/probe keys — this view's proven tier already ranks by roas90).
--   1. GENERAL SETTLE VETO (Cause 1, gated layer): the tested-loser PARK (this view's only
--      condemnation — PARK_WAIT is seat-queue mechanics, not a verdict) may fire only if
--      (a) the condemning clicks are fully settled (guard settle_ok — no clicks in the last
--      D+7 SP / D+14 SB) OR (b) the channel-aware settled 90d record corroborates (>= 10
--      settled clicks at GP-ROAS < 1.0, no season WIN prior). Else SETTLE_HOLD ("wave — sales
--      not yet attributed, re-judge at settle"). DARK_BRAKE / EASE / TRIM / FIT_CPC stay live
--      — dark is never a hold. BLOCK_CUT sits above (gate precedence unchanged).
--   2. PROBE READS THE RECORD (Cause 2, gated layer): the generic $1 ACTIVATE entry is capped
--      by the keyword's own record — scope-lifetime >= 30 clicks -> entry <= lifetime conv CPC
--      x 1.2; ENTRY_BLOCK rows (prior same-family mature LOSS) -> entry <= LY conv CPC x 0.8,
--      composing with the v27.43 remaining-allowance clamp (min of all, floor = bid_floor). A
--      scope-lifetime LOSER (>= 30 clicks < 0.6x) is NOT "untested": ACTIVATE -> HOLD (the
--      loser path owns it).
--      v27.52 FIX 3 (Ori approved 2026-08-12): ACTIVATE_REVIVE is NO LONGER exempt from the
--      PRICE cap. §7.7 exempted it because its bid is part-1-calibrated, but that calibration
--      reads the settled-90d CPC only and cannot see a scope-lifetime record saying the keyword
--      has never cleared that price — which is the entry-price defect itself. It stays exempt
--      from the record-LOSER HOLD: the reverdict (>= 10 settled clicks at >= 1.0x, or >= 0.8x
--      with a season WIN) owns the decision to revive; this cap only prices it.
--   3. MANUAL_HOLD (Cause 3, outermost — directly below APPLIED_HOLD, which keeps working
--      unchanged): last bid change source = 'MANUAL' (Ori's hand; COACH/REUPLOAD are
--      engine-class) < 7d old -> suggestion suppressed, unless the settled record is
--      catastrophic (< 0.6x on >= 10 settled clicks). Unlogged Amazon-console writes cannot
--      be held (coverage hole, SOP §7.8). SETTLE_HOLD / MANUAL_HOLD are no-change actions
--      (v27.29 exempt family alongside APPLIED_HOLD / DEFER_OOB / REVIVE_SETTLE_HOLD).
--   PACE_RAISE (Cause 4) deliberately does NOT live here: its calibration excludes OOB-owned /
--   capped campaigns (PHASE = budget authority; raising bids into darkness buys darkness).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_OOB_KEYWORD` AS
-- ── v27.75 THE LAST-DAY VETO (Task 4.8, Ori 2026-08-17) ─────────────────────────────────────
-- Complete-day windows DECIDE moves (Task 4.7); the standalone filling day (clicks_1d/roas_1d)
-- may only HOLD a move, never drive one. Symmetric, at real volume, as a THIN OUTER WRAPPER over
-- the published rows (the V_KEYWORD_LIFT reason_short precedent): the veto booleans are computed
-- ONCE below as pure functions of already-published columns, so the four transformed columns
-- (bid_action / suggested_bid / bid_reason / bid_reason_short) can never drift apart.
--   RAISE (suggested > current) at clicks_1d > 10 and COALESCE(roas_1d, 0) < 0.5 ⇒ HOLD, bid NULLed
--   CUT   (suggested < current) at clicks_1d > 10 and roas_1d >= 1.2             ⇒ HOLD, bid NULLed
--
-- ── v27.76 THE EXPECTED-ORDERS GATE (Task 4.9, Ori 2026-08-17) ──────────────────────────────
-- MEASURED FLAW, RAISE ARM ONLY: at age 1 the filling day shows ~85% of its spend but only ~69%
-- of its sales (V_ADS_SETTLE_CURVE), and 46% of at-volume keywords read exactly 0.00x on it. So
-- "0.00x at 45 clicks" is usually NOT a verdict — it is an unfinished sentence. Worked case:
-- BOX-SP/AUTO (Pink) "substitutes" converts once per ~42 clicks and has zero-order days 6 times
-- in 13; on the filling day it took 45 clicks (~1 expected order), got 0, read 0.00x, and its
-- raise was vetoed. That is an ORDINARY day for that keyword. Because it is busy every day, the
-- v27.75 raise veto would block it ~63% of days FOREVER — a permanent ban, not "wait a day".
-- THE SPLIT — is the poor reading INFORMATIVE?
--   (a) roas_1d <> 0 (and < 0.5): sales DID land and were poor. Real evidence. VETO, no gate.
--   (b) roas_1d = 0 or NULL: AMBIGUOUS ("no sales" vs "not attributed yet"). VETO ONLY IF a zero
--       is genuinely surprising:  expected_orders_1d >= veto_min_expected_orders (3.0), where
--         expected_orders_1d = clicks_1d * ord90 / clk90
--       — the keyword's OWN complete-day 90d order rate applied to the filling day's clicks.
--       Poisson: P(0 orders | mean 3) ~ 5%, so >= 3 means a zero here is a 1-in-20 event, not a
--       Tuesday. Rate uncomputable (clk90 = 0) or no 90d orders (ord90 = 0) => 0.0 => NO VETO.
--       That is deliberate: the veto may only block when it HAS evidence. Whether a
--       never-converting keyword deserves a raise is the complete-day ladders' job (and the
--       v27.65 zero-sale floor's) — never the last-day veto's.
-- THE CUT ARM HAS NO SUCH FLAW AND IS UNTOUCHED: under-attribution can only make a day look
-- WORSE, so a filling day already reading >= 1.2x is conservative proof that the cut is wrong.
-- clk90 / ord90 / expected_orders_1d are PUBLISHED (additive columns only) so the gate is
-- auditable from the row itself and computed from published columns, never re-derived.
-- Direction is the BID COMPARISON, never the action name (ACTIVATE / ACTIVATE_REVIVE / WAKE_STEP /
-- PARK all classify themselves). Structurally no collision with the v27.65 zero-sale floor: its
-- rows are CUTS at roas_1d = 0.00 and the cut veto needs >= 1.2. Rows with no published bid
-- (HOLD / DEFENSE / APPLIED_HOLD / MANUAL_HOLD / SETTLE_HOLD / ...) are untouched — the veto only
-- ever downgrades a published move to HOLD (the view's do-nothing idiom), so a vetoed row drops
-- out of the proposal snapshot naturally while the panel still shows the row with its why.
WITH lastday AS (
  SELECT
    10  AS veto_clk1,        -- real-volume bar: the filling day only vetoes above this many of its own clicks (Ori tunable)
    0.5 AS veto_raise_roas,  -- a published RAISE waits a day when the filling day reads under this (Ori tunable)
    1.2 AS veto_cut_roas,    -- a published CUT waits a day when the filling day reads at/above this (Ori tunable)
    3.0 AS veto_min_expected_orders  -- v27.76 Task 4.9: a 0.00x filling day only vetoes a RAISE when the keyword's own 90d rate expected at least this many orders on those clicks (Poisson P(0|3) ~ 5%) (Ori tunable)
)
SELECT pub.* EXCEPT (veto_raise, veto_cut) REPLACE (
  IF(pub.veto_raise OR pub.veto_cut, 'HOLD', pub.bid_action) AS bid_action,
  IF(pub.veto_raise OR pub.veto_cut, NULL, pub.suggested_bid) AS suggested_bid,
  CASE
    WHEN pub.veto_raise THEN CONCAT(
      'LAST-DAY VETO (Task 4.8): the standalone filling day read ', CAST(pub.clicks_1d AS STRING),
      ' clicks at ', FORMAT('%.2f', COALESCE(pub.roas_1d, 0)), 'x — under the ',
      FORMAT('%.2f', lv.veto_raise_roas), 'x raise bar at real volume (>',
      CAST(lv.veto_clk1 AS STRING), ' clicks). ',
      -- v27.76 (Task 4.9): a ZERO reading only vetoes when the zero is SURPRISING — the reason
      -- must name the expectation that made it surprising, or say that sales actually landed.
      IF(COALESCE(pub.roas_1d, 0) = 0,
         CONCAT('No sales at all, and its own complete-day 90d record (',
                CAST(COALESCE(pub.clk90, 0) AS STRING), ' clicks / ',
                CAST(COALESCE(pub.ord90, 0) AS STRING), ' orders) expected about ',
                FORMAT('%.1f', pub.expected_orders_1d), ' orders on those ',
                CAST(pub.clicks_1d AS STRING), ' clicks yesterday',
                ' and got none — at or above the ', FORMAT('%.1f', lv.veto_min_expected_orders),
                '-expected-order gate, a zero at this volume is evidence (~1-in-20), not the',
                ' ordinary quiet day the filling day usually shows. '),
         CONCAT('Sales DID land and were poor at ', FORMAT('%.2f', COALESCE(pub.roas_1d, 0)),
                'x — real evidence, so no expected-orders gate applies. ')),
      'Complete-day windows decide moves; the filling day',
      ' may only hold one — the raise waits for the day to complete (was ', pub.bid_action,
      ' to $', FORMAT('%.2f', pub.suggested_bid), ')')
    WHEN pub.veto_cut THEN CONCAT(
      'LAST-DAY VETO (Task 4.8): the standalone filling day read ', CAST(pub.clicks_1d AS STRING),
      ' clicks at ', FORMAT('%.2f', COALESCE(pub.roas_1d, 0)), 'x — at/above the ',
      FORMAT('%.2f', lv.veto_cut_roas), 'x cut bar at real volume (>',
      CAST(lv.veto_clk1 AS STRING), ' clicks). Complete-day windows decide moves; the filling day',
      ' may only hold one — the cut waits for the day to complete (was ', pub.bid_action,
      ' to $', FORMAT('%.2f', pub.suggested_bid), ')')
    ELSE pub.bid_reason END AS bid_reason,
  CASE
    WHEN pub.veto_raise THEN CONCAT('yday: ', CAST(pub.clicks_1d AS STRING), 'c at ',
      FORMAT('%.2f', COALESCE(pub.roas_1d, 0)), 'x ⇒ raise waits a day')
    WHEN pub.veto_cut THEN CONCAT('yday: ', CAST(pub.clicks_1d AS STRING), 'c at ',
      FORMAT('%.2f', COALESCE(pub.roas_1d, 0)), 'x ⇒ cut waits a day')
    ELSE pub.bid_reason_short END AS bid_reason_short
),
  -- ── v27.98 (Ori 2026-08-21): THE VETO STOPS ERASING WHAT IT HELD ──────────────────────────
  -- Three ADDITIVE columns, NULL on every row the veto did not touch. Nothing above changes:
  -- bid_action still reads HOLD and suggested_bid is still NULL, so every existing consumer —
  -- panels, cube, bulksheet builders, the proposal snapshot's own action/value filters — behaves
  -- exactly as it did yesterday. THE DEFECT THEY FIX: SP_SNAPSHOT_ENGINE_PROPOSALS takes a row
  -- on `bid_action NOT IN ('HOLD', ...) AND suggested_bid IS NOT NULL`, and the veto breaks BOTH
  -- conjuncts, so a vetoed row vanished from FACT_ENGINE_PROPOSALS together with its reason. That
  -- made this the ONE suppression in the engine that ERASES rather than LABELS — against the
  -- house doctrine SP_ENGINE_PREFLIGHT states for the holdout arm: "the proposal is still
  -- recorded ... only the verdict says EXCLUDE. Block the export, never the judgement."
  -- held_bid is deliberately NOT suggested_bid: a value in suggested_bid is an instruction to
  -- Amazon, and a held row must be unable to become one no matter which consumer reads it.
  -- hold_source names the ARM, not just the fact — the cut arm is strong evidence (a filling day
  -- already at/above the cut bar can only rise as attribution accrues) while the raise arm is
  -- weak (46% of at-volume rows read exactly 0.00x on a filling day), so an audit that cannot
  -- tell them apart cannot judge the veto at all. It is also what distinguishes a veto hold from
  -- a collision / claim / holdout exclusion downstream, the way is_holdout already does.
  IF(pub.veto_raise OR pub.veto_cut, pub.bid_action,     CAST(NULL AS STRING))  AS held_action,
  IF(pub.veto_raise OR pub.veto_cut, pub.suggested_bid,  CAST(NULL AS FLOAT64)) AS held_bid,
  CASE WHEN pub.veto_raise THEN 'LAST_DAY_VETO_RAISE'
       WHEN pub.veto_cut   THEN 'LAST_DAY_VETO_CUT'
       ELSE CAST(NULL AS STRING) END AS hold_source
FROM (
  SELECT p1.*,
    -- the two veto booleans, computed ONCE — every transformed column reads these, never a re-derivation
    -- v27.76 (Task 4.9): the RAISE arm gains the expected-orders gate as ONE extra conjunct.
    --   COALESCE(roas_1d, 0) <> 0  ⇒ sales landed and were poor: informative, veto as v27.75.
    --   COALESCE(roas_1d, 0)  = 0  ⇒ ambiguous: veto only when the zero is surprising.
    COALESCE(p1.suggested_bid > p1.current_bid AND p1.clicks_1d > lv.veto_clk1
             AND COALESCE(p1.roas_1d, 0) < lv.veto_raise_roas
             AND (COALESCE(p1.roas_1d, 0) <> 0
                  OR p1.expected_orders_1d >= lv.veto_min_expected_orders), FALSE) AS veto_raise,
    -- CUT ARM UNTOUCHED (v27.75 exactly): under-attribution can only make a day look WORSE, so a
    -- filling day already at/above the cut bar is conservative proof. No gate here, by design.
    COALESCE(p1.suggested_bid < p1.current_bid AND p1.clicks_1d > lv.veto_clk1
             AND p1.roas_1d >= lv.veto_cut_roas, FALSE) AS veto_cut
  FROM (
    -- v27.76 (Task 4.9): expected_orders_1d = the keyword's OWN complete-day 90d order rate
    -- (ord90/clk90 — the longest complete-day pair this view has, never touching the filling day)
    -- applied to the filling day's clicks. Its own projection layer so the two booleans above can
    -- read it as a column instead of re-deriving the arithmetic. PUBLISHED (additive) alongside
    -- clk90/ord90 so the gate is auditable from the row. No rate (clk90 = 0) or no orders
    -- (ord90 = 0) ⇒ 0.0 ⇒ the veto cannot fire: no history is no surprise.
    SELECT p0.*,
      COALESCE(p0.clicks_1d, 0) * COALESCE(SAFE_DIVIDE(p0.ord90, NULLIF(p0.clk90, 0)), 0)
        AS expected_orders_1d
    FROM (
-- ── Phase 6 Task 3 (WEEKLY_RUN_UX.md): the 5-SECOND WHY ──────────────────────────────────────
-- TRIGGER — EVIDENCE ⇒ MOVE, ≤ ~80 chars, computed HERE as a pure function of the PUBLISHED row
-- (final action + published numbers) — a thin wrapper, deliberately NOT a fourth predicate
-- ladder: it cannot drift from what the row already says. NULL on non-actionable rows (nothing
-- to accept there). The full paragraph stays in the reason column; panels show short + tooltip.
SELECT pub.*,
  CASE
    WHEN pub.suggested_bid IS NULL THEN CAST(NULL AS STRING)
    WHEN pub.bid_action = 'DARK_BRAKE' THEN CONCAT(
      CAST(COALESCE(pub.clicks_1d, 0) AS STRING), 'c ', FORMAT('%.2f', COALESCE(pub.roas_1d, 0)),
      'x yday · 90d ', FORMAT('%.2f', COALESCE(pub.roas90, 0)), ' ⇒ brake ',
      CAST(CAST(ROUND(100 * (1 - SAFE_DIVIDE(pub.suggested_bid, NULLIF(pub.current_bid, 0)))) AS INT64) AS STRING),
      '% to $', FORMAT('%.2f', pub.suggested_bid))
    -- explanation audit 2026-08-16: every short = evidence numbers + move in plain words.
    -- Banned: bare 'seat'/'settled'/'anchored'; settled_clk90 is LABELED 'full data' (raw clk90
    -- is published as of v27.76 but is the UNSETTLED engine window — never speak it as 'full
    -- data'). ACTIVATE names only the anchor the row can back (reviewer-A drift fix).
    WHEN pub.bid_action = 'EASE' THEN CONCAT(
      'winners take the spend, ', CAST(CAST(COALESCE(pub.pct_dark, 0) AS INT64) AS STRING),
      '% dark ⇒ ease bid to $', FORMAT('%.2f', pub.suggested_bid))
    WHEN pub.bid_action = 'FIT_CPC' THEN CONCAT(
      'bid $', FORMAT('%.2f', COALESCE(pub.current_bid, 0)),
      ' but clicks cost less ⇒ lower bid to $', FORMAT('%.2f', pub.suggested_bid))
    WHEN pub.bid_action = 'TRIM_BID' THEN CONCAT(
      'bid $', FORMAT('%.2f', COALESCE(pub.current_bid, 0)), ' but budget affords $',
      FORMAT('%.2f', COALESCE(pub.seat_cpc, 0)), '/click ⇒ trim to $', FORMAT('%.2f', pub.suggested_bid))
    WHEN pub.bid_action = 'PARK' THEN IF(COALESCE(pub.settled_clk90, 0) = 0,
      CONCAT('test complete, no profit ⇒ park bid at $', FORMAT('%.2f', pub.suggested_bid)),
      CONCAT(CAST(CAST(pub.settled_clk90 AS INT64) AS STRING),
        ' clicks (full data), no profit ⇒ park bid at $', FORMAT('%.2f', pub.suggested_bid)))
    WHEN pub.bid_action = 'PARK_WAIT' THEN IF(pub.seat_rank > pub.slots,
      CONCAT('no free budget slot (queue #', CAST(pub.seat_rank - pub.slots AS STRING),
        ') ⇒ wait at $', FORMAT('%.2f', pub.suggested_bid)),
      CONCAT('waiting for budget room ⇒ $', FORMAT('%.2f', pub.suggested_bid)))
    WHEN pub.bid_action = 'ACTIVATE' THEN CONCAT(
      'budget slot opened ⇒ resume test at $', FORMAT('%.2f', pub.suggested_bid),
      IF(pub.target_cpc IS NOT NULL, ' (1.5x target click cost)', ' (what the budget affords)'))
    WHEN pub.bid_action = 'ACTIVATE_REVIVE' THEN CONCAT(
      '90d record earns it back ⇒ un-park at $', FORMAT('%.2f', pub.suggested_bid))
    ELSE CONCAT(LOWER(REPLACE(pub.bid_action, '_', ' ')), ' ⇒ $', FORMAT('%.2f', pub.suggested_bid))
  END AS bid_reason_short
FROM (
WITH k AS (
  SELECT 1.5 AS strong_roas, 1.2 AS weak_roas,
         1.30 AS bid_raise_strong, 1.15 AS bid_raise_weak, 1.05 AS bid_probe, 0.95 AS bid_slow,
         0.20 AS bid_min, 1.50 AS bid_max, 2.00 AS bid_hard_cap,  -- SP floor; SB floors at $0.25 (platform minBid) via IF(is_sb,...) at every use
         4 AS click_goal_day, 6 AS click_cap_day,
         -- budget-constrained probing (Ori 2026-07-30): tested keywords park, big bids trim
         15 AS tested_clk, 0.25 AS bid_park, 1.00 AS big_bid, 0.85 AS bid_big_trim
),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- the phase's campaign population + campaign-level ROAS signals (for the hold-while-capping test)
-- v27.45: population = EVERY phase campaign (phase membership = V_CAMPAIGN_CAP_STATE.is_oob_owned)
-- — the pct_dark > 10 filter is gone; is_defense + days_capped_7d ride along for the doctrine.
oob AS (
  SELECT campaign_id, campaign_name, pct_dark, current_budget AS budget, roas_1d AS c_roas1, roas_prev2 AS c_roas_prev2, is_low_tier,
         is_defense, days_capped_7d
  FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
  WHERE channel = 'SP' AND is_oob_owned
),
-- target-day perf. GP = the STORED FACT_AMAZON_ADS.GROSS_PROFIT column — see THE GP RULE in the
-- header. (The SB cost-ratio arm further down is untouched — different stream, different mechanism.)
tday AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting, a.date,
    SUM(a.Ads_clicks) clk, SUM(a.Ads_cost) sp, SUM(a.Ads_units) units,
    SUM(a.GROSS_PROFIT) gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN oob o ON o.campaign_id = CAST(a.campaign_id AS STRING)
  -- v27.74: complete days (Task 4.7) — pull widened to wm-7 so the 7d window ends wm-1 (wm itself stays for the last-day reads)
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY) AND (SELECT d FROM wm)
  GROUP BY 1, 2, 3
),
tsig AS (
  SELECT cid, targeting,
    SUM(IF(date = (SELECT d FROM wm), clk, 0)) AS clk1,
    SUM(IF(date = (SELECT d FROM wm), sp, 0)) AS sp1,
    SUM(IF(date = (SELECT d FROM wm), units, 0)) AS units1,
    ROUND(SAFE_DIVIDE(SUM(IF(date = (SELECT d FROM wm), gp, 0)),
                      NULLIF(SUM(IF(date = (SELECT d FROM wm), sp, 0)), 0)), 2) AS roas1,
    SUM(IF(date < (SELECT d FROM wm) AND date >= DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY), clk, 0)) AS clk2,
    SUM(IF(date < (SELECT d FROM wm) AND date >= DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY), sp, 0)) AS sp2,
    SUM(IF(date < (SELECT d FROM wm) AND date >= DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY), units, 0)) AS units2,
    ROUND(SAFE_DIVIDE(SUM(IF(date < (SELECT d FROM wm) AND date >= DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY), gp, 0)),
                      NULLIF(SUM(IF(date < (SELECT d FROM wm) AND date >= DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY), sp, 0)), 0)), 2) AS roas_prev2,
    -- v27.74: complete days (Task 4.7) — 3d evidence (ev_cpc/conv_share) ends wm-1
    SUM(IF(date < (SELECT d FROM wm) AND date >= DATE_SUB((SELECT d FROM wm), INTERVAL 3 DAY), clk, 0)) AS clk3,
    SUM(IF(date < (SELECT d FROM wm) AND date >= DATE_SUB((SELECT d FROM wm), INTERVAL 3 DAY), sp, 0)) AS sp3,
    -- v27.74: complete days (Task 4.7) — ends wm-1
    SUM(IF(date < (SELECT d FROM wm), clk, 0)) AS clk7, SUM(IF(date < (SELECT d FROM wm), sp, 0)) AS sp7
  FROM tday GROUP BY 1, 2
),
-- tested clicks per target over 90d — the "has it had its test" evidence for the park rule
t90 AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting, SUM(a.Ads_clicks) clk90, SUM(a.Ads_orders) ord90,
    ROUND(SAFE_DIVIDE(SUM(a.GROSS_PROFIT), NULLIF(SUM(a.Ads_cost), 0)), 2) AS roas90
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN oob o ON o.campaign_id = CAST(a.campaign_id AS STRING)
  -- v27.74: complete days (Task 4.7) — ends wm-1
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 90 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY)
  GROUP BY 1, 2
),
-- current bid + ids: latest V_TARGET_DAILY row per (campaign, target); ad-group default as fallback
td AS (
  -- CONFIG TRUTH (Ori 2026-08-01): every ENABLED SP target from DIM_KEYWORD current rows —
  -- keywords, product targets AND auto clauses, including dormant ones with no recent delivery.
  -- Sourcing from V_TARGET_DAILY (delivery days only) silently dropped 14 enabled keywords that
  -- had not delivered recently — exactly the candidate/queue pool the engines exist to manage.
  -- One row per (campaign, target text): highest-bid copy wins (text is the FACT perf grain).
  SELECT campaign_id, target_text, keyword_id, ad_group_id, match_type, keyword_bid
  FROM (
    SELECT CAST(campaign_id AS STRING) campaign_id, keyword_text AS target_text,
           CAST(keyword_id AS STRING) keyword_id, CAST(ad_group_id AS STRING) ad_group_id,
           match_type, bid AS keyword_bid,
           ROW_NUMBER() OVER (PARTITION BY CAST(campaign_id AS STRING), keyword_text
                              ORDER BY bid DESC NULLS LAST, keyword_id) rn
    FROM `onyga-482313.OI.DIM_KEYWORD`
    WHERE is_current AND UPPER(state) = 'ENABLED'
  ) WHERE rn = 1
),
agb AS (SELECT ad_group_id, ANY_VALUE(default_bid) default_bid
        FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current GROUP BY 1),
-- v27.33 (Ori 2026-08-06, upload reports 32 + 33): the SB minimum bid is PER FORMAT, not one
-- number. Proven empirically against Amazon, not assumed:
--   SB BRAND_VIDEO/VIDEO      -> $0.25  ($0.15 rejected in r32, $0.20 rejected in r33, both
--                                        quoting minBid 0.25)
--   SB PRODUCT_COLLECTION/
--      STORE_SPOTLIGHT        -> $0.10  ($0.15 accepted in r32, $0.10 accepted in r33)
--   SB creative_type NULL     -> $0.25  conservative: bidding too high is recoverable, a
--                                        rejected bulksheet row fails SILENTLY. Covers the 1
--                                        enabled campaign missing creative_type and any new
--                                        campaign before its first sb_ad_report row lands.
--   SP                        -> x.bid_min ($0.20; Amazon's real SP min is far lower)
agfmt AS (SELECT CAST(ad_group_id AS STRING) ad_group_id, ANY_VALUE(creative_type) creative_type
          FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current GROUP BY 1),
-- ── target CPC (Ori 2026-07-30: "show also target cpc, based on time last year if data exists") ──
-- Precedence: (1) the SAME 28 days one year back (364-day offset keeps Sun–Sat weekday alignment),
-- per keyword TEXT account-wide, needs >= 10 LY clicks to count; (2) else the coacher band
-- cpc_target (DE_PRODUCT_STRATEGY_PROFILE, product × season × match, coarse ALL/ALL cells averaged
-- across intents, CONCLUSIVE + enabled only); (3) else NULL. Auto clauses + product targets skip LY
-- (the clause text is not product-specific across campaigns) — band or nothing.
ly AS (
  -- ly_cpc: >= 10 clicks in the LY same-28d window. seasonal = CONCENTRATION (Ori 2026-08-02):
  -- >= 2 window orders AND >= 25% of the LY YEAR's orders in the window (uniform ~8%).
  SELECT LOWER(TRIM(targeting)) AS kw,
         IF(SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_clicks, 0)) >= 10,
            ROUND(SAFE_DIVIDE(SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_cost, 0)),
                              SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_clicks, 0))), 2), NULL) AS ly_cpc,
         SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_orders, 0)) AS ly_ord,
         SUM(Ads_orders) AS ly_year_ord,
         -- launch-artifact guard: concentration only means SEASON if the keyword existed at
         -- least a month before the window (else all history sits inside it by construction)
         MIN(IF(Ads_clicks > 0, date, NULL)) AS ly_first
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 728 DAY)
                 AND DATE_SUB((SELECT d FROM wm), INTERVAL 364 DAY)
  GROUP BY 1 HAVING SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_clicks, 0)) >= 10
             OR SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_orders, 0)) >= 1
),
season AS (
  SELECT COUNTIF(CURRENT_DATE('America/New_York') BETWEEN boost_start AND cooldown_end) > 0 AS in_peak
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` WHERE category IN ('gift_season', 'prime_event')
),
camp_parent AS (
  SELECT CAST(f.campaign_id AS STRING) cid, ANY_VALUE(p.parent_name) parent_name
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = f.ASIN_BY_CAMPAIGN_NAME AND p.parent_name IS NOT NULL
  GROUP BY 1
),
band AS (
  SELECT parent_name, UPPER(match_type) AS match_type, ROUND(AVG(cpc_target), 2) AS cpc_target
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`, season s
  WHERE enabled AND cpc_target IS NOT NULL AND confidence = 'CONCLUSIVE'
    AND COALESCE(campaign_type, 'ALL') = 'ALL' AND COALESCE(ad_format, 'ALL') = 'ALL'
    AND season = IF(s.in_peak, 'PEAK', 'OFF')
  GROUP BY 1, 2
),
-- Portfolio 80/20 probe protection (same rule as the coacher suppression, ADS_COACH_DECISION_MATRIX
-- §Safety Guards): keywords mid-probe-episode (or imminent PROBE_START) are owned by the lift
-- engine — the seat model must not park/trim/brake them mid-test; verdict comes at 20 clicks.
lift_probes AS (
  SELECT DISTINCT keyword_id FROM `onyga-482313.OI.V_KEYWORD_LIFT`
  WHERE probing OR action = 'PROBE_START'
),
-- 1-day cooldown: did we already upload a change for this keyword?
lc AS (
  SELECT keyword_id, DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at)), DAY) AS days_since
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE keyword_id IS NOT NULL GROUP BY 1
),
-- v27.45 APPLIED-BID DOCTRINE — the SAME applied/ap pattern as V_KEYWORD_LIFT v27.4: the last
-- applied bid change per (campaign, target) within 48h. Bulksheet uploads land in
-- FACT_PPC_CHANGE_LOG immediately but the config mirrors lag Fivetran by 1-2 days, so without
-- this the engine re-derives its daily step from the STALE bid and invites a double-apply
-- (or flips an applied cut into a raise). Applied TODAY (America/Los_Angeles) or applied value
-- not yet in the config (|delta| > 0.005) => the row holds (APPLIED_HOLD, outermost wrapper).
applied AS (
  SELECT CAST(campaign_id AS STRING) cid, LOWER(TRIM(targeting)) tgt,
         ARRAY_AGG(STRUCT(applied_at AS ts, new_bid) ORDER BY applied_at DESC LIMIT 1)[OFFSET(0)] last
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE applied_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 48 HOUR)
    AND action IN ('INCREASE_BID', 'REDUCE_BID') AND new_bid IS NOT NULL
  GROUP BY 1, 2
),
-- ── SB arm (v2.1): dark SB campaigns' keywords + product targets, from the SB reports ──
-- v27.45: same population rule as the SP arm — every OOB-owned phase campaign.
oob_sb AS (
  SELECT campaign_id, campaign_name, pct_dark, current_budget AS budget, roas_1d AS c_roas1, roas_prev2 AS c_roas_prev2, is_low_tier,
         is_defense, days_capped_7d
  FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
  WHERE channel = 'SB' AND is_oob_owned
),
wm_sb AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `fivetran-hl.amazon_ads.sb_campaign_report`),
-- est. COGS ratio per SB campaign via its mapped ASIN (same method as the SB launch views).
-- v27.46 DETERMINISM FIX (found by this batch's pull-twice check): the old
-- ANY_VALUE(cost)/ANY_VALUE(price) let BigQuery pick cost and price from DIFFERENT arbitrary
-- ASINs per plan on multi-ASIN campaigns — back-to-back pulls flipped roas90 0.89 vs 1.18
-- straight across the A4 tier boundary (v27.42.1 APPROX_QUANTILES precedent). Now the
-- campaign's DOMINANT mapped ASIN (most all-history ad spend, tie-break ASIN string) supplies
-- BOTH cost and price — deterministic and coherently paired.
prod AS (
  SELECT cid, SAFE_DIVIDE(cost, NULLIF(price, 0)) AS cost_ratio
  FROM (
    SELECT CAST(f.campaign_id AS STRING) AS cid,
      ANY_VALUE(c.cost) AS cost, ANY_VALUE(p.listing_price_amount) AS price,
      ROW_NUMBER() OVER (PARTITION BY CAST(f.campaign_id AS STRING)
                         ORDER BY SUM(f.Ads_cost) DESC,
                                  f.ASIN_BY_CAMPAIGN_NAME IS NULL, f.ASIN_BY_CAMPAIGN_NAME) AS rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
    LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = f.ASIN_BY_CAMPAIGN_NAME
    LEFT JOIN (SELECT asin, TOTAL_COST_PER_UNIT cost FROM (
        SELECT asin, TOTAL_COST_PER_UNIT, ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin ORDER BY start_date DESC) rn
        FROM `onyga-482313.OI.DIM_COSTS_HISTORY` WHERE marketplace_id='ATVPDKIKX0DER' AND end_date IS NULL) WHERE rn=1) c
      ON c.asin = f.ASIN_BY_CAMPAIGN_NAME
    GROUP BY cid, f.ASIN_BY_CAMPAIGN_NAME
  ) WHERE rn = 1
),
sb_ptlabel AS (
  SELECT target_id, ANY_VALUE(targeting_text) txt
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  WHERE report_date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 30 DAY)
  GROUP BY 1
),
sb_tgt AS (
  SELECT k.id AS target_id, CAST(k.campaign_id AS STRING) cid, CAST(k.ad_group_id AS STRING) ad_group_id,
    k.keyword_text AS target_text, FALSE AS is_pt, k.match_type, k.bid
  FROM `fivetran-hl.amazon_ads.sb_keyword` k
  WHERE NOT k._fivetran_deleted AND k.state='enabled'
    AND CAST(k.campaign_id AS STRING) IN (SELECT campaign_id FROM oob_sb)
  UNION ALL
  SELECT pt.id, CAST(pt.campaign_id AS STRING), CAST(pt.ad_group_id AS STRING),
    COALESCE(l.txt, 'product target'), TRUE, 'TARGETING_EXPRESSION', pt.bid
  FROM `fivetran-hl.amazon_ads.sb_product_target` pt
  LEFT JOIN sb_ptlabel l ON l.target_id = pt.id
  WHERE NOT pt._fivetran_deleted AND pt.state='enabled'
    AND CAST(pt.campaign_id AS STRING) IN (SELECT campaign_id FROM oob_sb)
),
sb_tgtday AS (
  SELECT keyword_id AS target_id, report_date date, SUM(clicks) clk, SUM(cost) cost,
         SUM(attributed_sales_14_d) sales, SUM(attributed_conversions_14_d) orders
  FROM `fivetran-hl.amazon_ads.sb_search_term_report`
  -- v27.74: complete days (Task 4.7) — pull widened to wm_sb-7 so the 7d window ends wm_sb-1
  WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 7 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2
  UNION ALL
  SELECT target_id, report_date, SUM(clicks), SUM(cost), SUM(attributed_sales_14_d), SUM(attributed_conversions_14_d)
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  -- v27.74: complete days (Task 4.7) — pull widened to wm_sb-7 so the 7d window ends wm_sb-1
  WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 7 DAY) AND (SELECT d FROM wm_sb)
  GROUP BY 1, 2
),
sb_t90 AS (
  SELECT target_id, SUM(clk) clk90, SUM(conv) ord90, SUM(sp) sp90, SUM(sales) sales90 FROM (
    SELECT keyword_id AS target_id, SUM(clicks) clk, SUM(attributed_conversions_14_d) conv,
           SUM(cost) sp, SUM(attributed_sales_14_d) sales FROM `fivetran-hl.amazon_ads.sb_search_term_report`
    -- v27.74: complete days (Task 4.7) — ends wm_sb-1
    WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 90 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY) GROUP BY 1
    UNION ALL
    SELECT target_id, SUM(clicks), SUM(attributed_conversions_14_d), SUM(cost), SUM(attributed_sales_14_d)
    FROM `fivetran-hl.amazon_ads.sb_target_report`
    -- v27.74: complete days (Task 4.7) — ends wm_sb-1
    WHERE report_date BETWEEN DATE_SUB((SELECT d FROM wm_sb), INTERVAL 90 DAY) AND DATE_SUB((SELECT d FROM wm_sb), INTERVAL 1 DAY) GROUP BY 1
  ) GROUP BY 1
),
sb_tsig AS (
  SELECT t.target_id,
    SUM(IF(d.date=(SELECT d FROM wm_sb), d.clk,0)) clk1,
    SUM(IF(d.date=(SELECT d FROM wm_sb), d.cost,0)) sp1,
    SUM(IF(d.date=(SELECT d FROM wm_sb), d.orders,0)) units1,
    MAX(IF(d.date=(SELECT d FROM wm_sb), SAFE_DIVIDE(d.sales*(1-COALESCE(pr.cost_ratio,0)), NULLIF(d.cost,0)), NULL)) AS roas1,
    SUM(IF(d.date<(SELECT d FROM wm_sb) AND d.date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), d.clk,0)) clk2,
    SUM(IF(d.date<(SELECT d FROM wm_sb) AND d.date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), d.cost,0)) sp2,
    SUM(IF(d.date<(SELECT d FROM wm_sb) AND d.date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), d.orders,0)) units2,
    -- v27.74: complete days (Task 4.7) — 3d evidence (ev_cpc/conv_share) ends wm_sb-1
    SUM(IF(d.date<(SELECT d FROM wm_sb) AND d.date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 3 DAY), d.clk,0)) clk3,
    SUM(IF(d.date<(SELECT d FROM wm_sb) AND d.date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 3 DAY), d.cost,0)) sp3,
    -- v27.74: complete days (Task 4.7) — ends wm_sb-1
    SUM(IF(d.date<(SELECT d FROM wm_sb), d.clk, 0)) AS clk7, SUM(IF(d.date<(SELECT d FROM wm_sb), d.cost, 0)) AS sp7,
    SAFE_DIVIDE(SUM(IF(d.date<(SELECT d FROM wm_sb) AND d.date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), d.sales*(1-COALESCE(pr.cost_ratio,0)), 0)),
                NULLIF(SUM(IF(d.date<(SELECT d FROM wm_sb) AND d.date >= DATE_SUB((SELECT d FROM wm_sb), INTERVAL 2 DAY), d.cost,0)),0)) AS roas_prev2
  FROM sb_tgt t
  LEFT JOIN sb_tgtday d ON d.target_id = t.target_id
  LEFT JOIN prod pr ON pr.cid = t.cid
  GROUP BY 1
),
base AS (
  -- SEAT MODEL (Ori 2026-08-01): drive from the FULL current target list (td), not just targets
  -- that clicked recently — the queue includes zero-click keywords sitting at full bids, which
  -- were previously invisible to this view ("lottery tickets" stealing the odd click).
  SELECT o.campaign_id, o.campaign_name, o.pct_dark, o.budget, o.c_roas1, o.c_roas_prev2,
    td.target_text, td.keyword_id, td.ad_group_id, td.match_type,
    LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements') AS is_auto,
    LOWER(td.target_text) LIKE 'asin%' AS is_pt,
    FALSE AS is_sb,
    (SELECT bid_min FROM k) AS bid_floor,
    COALESCE(td.keyword_bid, agb.default_bid) AS current_bid,
    COALESCE(t.clk1, 0) clk1, COALESCE(t.sp1, 0) sp1, COALESCE(t.units1, 0) units1, t.roas1,
    COALESCE(t.clk2, 0) clk2, COALESCE(t.sp2, 0) sp2, COALESCE(t.units2, 0) units2, t.roas_prev2,
    COALESCE(t.clk3, 0) clk3, COALESCE(t.sp3, 0) sp3,  -- v27.74: complete days (Task 4.7)
    COALESCE(t.clk7, 0) clk7, COALESCE(t.sp7, 0) sp7, o.is_low_tier,
    (COALESCE(t.roas1, 0) >= 1.0 OR COALESCE(t.roas_prev2, 0) >= 1.0) AS converting,
    COALESCE(t90.clk90, 0) AS clk90, COALESCE(t90.ord90, 0) AS ord90,
    -- recent corrected net ROAS over the full 90d — the seat-priority ranking metric
    t90.roas90,
    lc.days_since AS days_since_change,
    o.is_defense, o.days_capped_7d,
    -- v27.48: the park reverdict (FACT_PARK_REVERDICT snapshot — never the view, planner ceiling)
    COALESCE(rv.reverdict = 'REVIVE', FALSE) AS is_revive,
    -- v27.68: REDUNDANT (Task 2.4) = CONFIRM_PARK with the sibling named — same engine behavior
    COALESCE(rv.reverdict IN ('CONFIRM_PARK', 'REDUNDANT', 'SIBLING_REVIVE'), FALSE) AS confirm_park,
    -- ^ v27.71 (review, CRITICAL): SIBLING_REVIVE added — hand-queue ONLY; without this it walked the generic ACTIVATE door
    rv.revive_bid,
    COALESCE(rv.engine_immune, FALSE) AS revive_immune,
    COALESCE(rv.manual_parked_recent, FALSE) AS manual_parked_recent,
    rv.immune_reason, rv.reverdict_reason
  FROM td
  JOIN oob o ON o.campaign_id = td.campaign_id
  LEFT JOIN tsig t ON t.cid = td.campaign_id AND t.targeting = td.target_text
  LEFT JOIN t90 ON t90.cid = td.campaign_id AND t90.targeting = td.target_text
  LEFT JOIN agb ON agb.ad_group_id = td.ad_group_id
  LEFT JOIN lc ON lc.keyword_id = td.keyword_id
  LEFT JOIN `onyga-482313.OI.FACT_PARK_REVERDICT` rv
    ON rv.campaign_id = td.campaign_id AND rv.keyword_id = td.keyword_id
  UNION ALL
  SELECT o.campaign_id, o.campaign_name, o.pct_dark, o.budget, o.c_roas1, o.c_roas_prev2,
    t.target_text, t.target_id AS keyword_id, t.ad_group_id, t.match_type,
    FALSE AS is_auto, t.is_pt, TRUE AS is_sb,
    CASE WHEN agf.creative_type IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10
         ELSE 0.25 END AS bid_floor,
    t.bid AS current_bid,
    s.clk1, ROUND(s.sp1,2), s.units1, ROUND(s.roas1,2), s.clk2, ROUND(s.sp2,2), s.units2, ROUND(s.roas_prev2,2),
    COALESCE(s.clk3, 0), ROUND(COALESCE(s.sp3, 0), 2),  -- v27.74: complete days (Task 4.7)
    COALESCE(s.clk7, 0), COALESCE(s.sp7, 0), o.is_low_tier,
    (COALESCE(s.roas1, 0) >= 1.0 OR COALESCE(s.roas_prev2, 0) >= 1.0) AS converting,
    COALESCE(s90.clk90, 0), COALESCE(s90.ord90, 0),
    ROUND(SAFE_DIVIDE(s90.sales90 * (1 - COALESCE(pr.cost_ratio, 0)), NULLIF(s90.sp90, 0)), 2) AS roas90,
    lc.days_since,
    o.is_defense, o.days_capped_7d,
    -- v27.48: the SB arm reads the SAME reverdict snapshot — DIM_KEYWORD (the reverdict
    -- population) carries SB keyword config too (discovered at wiring: 26 of the 33 calibrated
    -- revives sit in SB campaigns), and OOB owns the OOB-owned SB campaigns' bids (v27.45).
    COALESCE(rvb.reverdict = 'REVIVE', FALSE) AS is_revive,
    COALESCE(rvb.reverdict IN ('CONFIRM_PARK', 'REDUNDANT', 'SIBLING_REVIVE'), FALSE) AS confirm_park,
    -- ^ v27.71 (review, CRITICAL): SIBLING_REVIVE added — hand-queue ONLY; without this it walked the generic ACTIVATE door  -- v27.68
    rvb.revive_bid,
    COALESCE(rvb.engine_immune, FALSE) AS revive_immune,
    COALESCE(rvb.manual_parked_recent, FALSE) AS manual_parked_recent,
    rvb.immune_reason, rvb.reverdict_reason
  FROM sb_tgt t
  JOIN oob_sb o ON o.campaign_id = t.cid
  JOIN sb_tsig s ON s.target_id = t.target_id
  LEFT JOIN sb_t90 s90 ON s90.target_id = t.target_id
  LEFT JOIN prod pr ON pr.cid = t.cid
  LEFT JOIN agfmt agf ON agf.ad_group_id = CAST(t.ad_group_id AS STRING)
  LEFT JOIN lc ON lc.keyword_id = t.target_id
  LEFT JOIN `onyga-482313.OI.FACT_PARK_REVERDICT` rvb
    ON rvb.campaign_id = t.cid AND rvb.keyword_id = CAST(t.target_id AS STRING)
),
-- affordable CPC per campaign (Ori 2026-07-30: "TRIM floor should not stop at $1.00") —
-- budget ÷ (targets × 4-click goal), floored at bid_min. Self-scaling: a $10/17-target campaign
-- trims toward $0.20; a $70/10-target campaign has aff ≈ $1.75 and its bids are left alone.
baseN AS (
  SELECT b.*,
    ROUND(GREATEST(SAFE_DIVIDE(b.budget, COUNT(*) OVER (PARTITION BY b.campaign_id) * 4), 0.20), 2) AS aff_cpc,
    -- concentration (Ori 2026-07-30): share of window spend on CONVERTING keywords — when >= 80%
    -- the campaign is already winner-concentrated and converters glide -5% instead of -15% FIT
    -- v27.74: complete days (Task 4.7) — ends wm-1 (3d complete window sp3; was sp1+sp2 = wm-2..wm)
    SAFE_DIVIDE(SUM(IF(b.converting, b.sp3, 0)) OVER (PARTITION BY b.campaign_id),
                NULLIF(SUM(b.sp3) OVER (PARTITION BY b.campaign_id), 0)) AS conv_share
  FROM base b
),
-- target CPC resolved BEFORE the bid CASE so converting keywords can be fitted to it (Ori 2026-07-30)
withT AS (
  SELECT b.*,
    ROUND(COALESCE(IF(b.is_auto OR b.is_pt, NULL, ly.ly_cpc), bd.cpc_target), 2) AS tcpc,
    CASE WHEN NOT (b.is_auto OR b.is_pt) AND ly.ly_cpc IS NOT NULL THEN 'LY'
         WHEN bd.cpc_target IS NOT NULL THEN 'BAND' END AS tcpc_src,
    -- SEASONAL REVIVAL (Ori 2026-08-01): sold in this same 28d window LAST YEAR -> its season is
    -- arriving; it is never permanent-parked and jumps the candidate queue for a seat
    COALESCE(ly.ly_ord, 0) >= 2 AND SAFE_DIVIDE(ly.ly_ord, NULLIF(ly.ly_year_ord, 0)) >= 0.25 AND ly.ly_first <= DATE_SUB((SELECT d FROM wm), INTERVAL 421 DAY) AND NOT (b.is_auto OR b.is_pt) AS seasonal_now
  FROM baseN b
  LEFT JOIN ly ON ly.kw = LOWER(TRIM(b.target_text))
  LEFT JOIN camp_parent cp ON cp.cid = b.campaign_id
  LEFT JOIN band bd ON bd.parent_name = cp.parent_name
    AND bd.match_type = CASE WHEN b.is_pt THEN 'PRODUCT' WHEN b.is_auto THEN 'AUTO'
                             WHEN UPPER(COALESCE(b.match_type,'')) IN ('TARGETING_EXPRESSION','ASIN','ASIN EXPANDED') THEN 'PRODUCT'
                             ELSE UPPER(COALESCE(b.match_type, '')) END
),
-- ── SEAT MODEL (Ori 2026-08-01, "lets do it") ──────────────────────────────────────────────
-- slots = max(1, round(budget/4)) — $4/day buys one keyword its 4-click trial ($10 → 3 seats).
-- Seat ranking: converters by recent (90d corrected) net ROAS — winner is always main — then
-- mid-tests by clicks-so-far (finish what you started), then untested candidates (target-CPC
-- anchored first). Tested losers (>=15 clk/90d, 0 orders) are never seated. Beyond-seat rows
-- queue at $0.25 (the test pauses, not dies). When a seat frees, the next candidate ACTIVATEs
-- at min(1.5 x target CPC, $1.50) (fallback: per-seat affordable), paced at
-- max(1, floor(0.20 x budget / 4)) activations/day — 80% of any raise keeps feeding winners.
seats AS (
  SELECT b.*,
    -- COST-AWARE SEATS (Ori 2026-08-02): the $4 seat assumes $1 clicks — a WINNER's bid premium
    -- above $1 (x 4 clicks) comes off the budget before dividing. ME-SP/PT B2: $10 budget with a
    -- $1.56 winner -> (10 - 2.24)/4 = 2 seats, not 3. Sales raise the budget, seats come back.
    GREATEST(1, CAST(ROUND(GREATEST(0, b.budget - SUM(IF(b.converting, GREATEST(0, 4 * (COALESCE(b.current_bid, 0) - 1)), 0)) OVER (PARTITION BY b.campaign_id)) / 4) AS INT64)) AS slots,
    ROUND(GREATEST(SAFE_DIVIDE(b.budget, GREATEST(1, CAST(ROUND(GREATEST(0, b.budget - SUM(IF(b.converting, GREATEST(0, 4 * (COALESCE(b.current_bid, 0) - 1)), 0)) OVER (PARTITION BY b.campaign_id)) / 4) AS INT64)) * 4), 0.20), 2) AS seat_cpc,
    (b.clk90 >= 15 AND b.ord90 = 0 AND NOT b.seasonal_now) AS tested_loser,
    ROW_NUMBER() OVER (PARTITION BY b.campaign_id ORDER BY
      -- v27.48: CONFIRM_PARK sinks with the tested losers — a settled-verified loser must never
      -- re-seat (its engine-window roas90 can flatter it; the settled record is the verdict).
      IF((b.clk90 >= 15 AND b.ord90 = 0 AND NOT b.seasonal_now) OR b.confirm_park, 1, 0),
      -- v27.48: a REVIVE verdict IS settled proof — joins the proven tier even when the
      -- engine-window roas90 (unsettled tail) understates it.
      IF(b.converting OR COALESCE(b.roas90, 0) >= 1.0 OR b.is_revive, 0, 1),
      -- v27.20 (Ori 2026-08-05: "why park this · seems like you should park different keyword",
      -- then "why it still want to park this and activate this"). The tier above lumps
      -- "converting NOW" together with "proven over 90d", and the roas90 DESC key below then
      -- sorts inside it -- so a keyword converting at 11.37x on thin 90d history sank BELOW
      -- keywords that have never converted but carry a decent 90d number. Observed: two
      -- never-converting keywords held seats (one had never clicked at all) while three
      -- converting at 11.37x / 6.41x / 3.51x were parked to $0.25.
      -- Converting in the last 3 days now outranks proven-but-quiet. Ties inside each group
      -- still break on roas90, so this never reorders two live converters on thin evidence.
      IF(b.converting, 0, 1),
      -- v27.48: inside the non-converting proven tier, a settled REVIVE outranks fresh unproven
      -- rows and engine-window rank (Cause 2: queues ranked fresh losers over proven winners).
      -- Live converters above are never demoted by this key.
      IF(b.is_revive, 0, 1),
      IF(b.seasonal_now, 0, 1),
      COALESCE(b.roas90, 0) DESC,
      IF(b.clk90 > 0, 0, 1),
      b.clk90 DESC,
      IF(b.tcpc IS NOT NULL, 0, 1),
      b.target_text) AS seat_rank
  FROM withT b
),
seats2pre AS (
  SELECT s.*,
    s.keyword_id IS NOT NULL AND s.keyword_id IN (SELECT keyword_id FROM lift_probes) AS is_lift_probe,
    ROW_NUMBER() OVER (PARTITION BY s.campaign_id
      ORDER BY IF(s.seat_rank <= s.slots AND COALESCE(s.current_bid, 0) <= 0.30 AND NOT s.tested_loser, 0, 1),
               s.seat_rank) AS act_rank,
    -- v27.24 (Ori 2026-08-06: "you should reduce bids or decide to park keywords and activate
    -- new ones instead"). How many keywords THIS campaign is parking this run. While the
    -- campaign is dark an activation is only budget-neutral if it REPLACES a park -- a swap,
    -- not an addition. This counter is what makes the swap possible; v27.23's blanket ban
    -- drained campaigns one-way (parks with no replacement, everything else HOLD).
    COUNTIF(s.seat_rank > s.slots AND NOT s.is_auto AND COALESCE(s.current_bid, 0) > 0.30)
      OVER (PARTITION BY s.campaign_id) AS park_count
  FROM seats s
),
-- v27.8.2 (Ori 2026-08-04, BUNNY-VIDEO: "if I park so many keywords I free budget — no need
-- to dark brake as well"): how much the QUEUE spent yesterday. While beyond-seat rows still
-- eat budget, the parks are the cure — seated brakes wait until the parks land.
seats3 AS (
  SELECT s.*,
    SUM(IF(s.seat_rank > s.slots, COALESCE(s.sp1, 0), 0)) OVER (PARTITION BY s.campaign_id) AS queue_sp1,
    -- v27.25 (Ori 2026-08-06: "regarding dark%>0 need to reduce bid from keywords that take
    -- most of the clicks"). The flat 4-click bar (v27.18) is an ABSOLUTE test, and in a
    -- low-click campaign almost nothing clears it -- measured: only 31 of 150 keywords in dark
    -- campaigns, leaving 40-57%-dark campaigns with no lever at all. Share is the RELATIVE
    -- test that actually names the budget eater: what fraction of yesterday's campaign clicks
    -- did this one keyword take.
    SAFE_DIVIDE(COALESCE(s.clk1, 0),
                NULLIF(SUM(COALESCE(s.clk1, 0)) OVER (PARTITION BY s.campaign_id), 0)) AS clk_share1,
    -- v27.10 (Ori 2026-08-04): deliberate keyword actions (EASE / FIT_CPC / TRIM_BID) judge on
    -- the REGULAR window for working-tier campaigns — 7d clicks + 7d realized CPC; low tier
    -- keeps the short windows (v27.7). DARK_BRAKE stays on yesterday for every tier.
    IF(s.is_low_tier, s.clk1, s.clk7) AS ev_clk,
    -- v27.74: complete days (Task 4.7) — 3d realized CPC ends wm-1 (was (sp1+sp2)/(clk1+clk2) = wm-2..wm); ev_clk clk1 is a last-day read, stays
    IF(s.is_low_tier, SAFE_DIVIDE(s.sp3, NULLIF(s.clk3, 0)),
                      SAFE_DIVIDE(s.sp7, NULLIF(s.clk7, 0))) AS ev_cpc
  FROM seats2pre s
),
-- v27.42: the whole seat-model output becomes outp so the season-context gate can overlay it —
-- the same layered-guard pattern as V_KEYWORD_LIFT's output wrapper.
outp AS (
SELECT
  b.campaign_id, b.campaign_name, b.pct_dark, b.is_low_tier,
  b.is_defense, b.days_capped_7d,  -- v27.45
  b.keyword_id, b.ad_group_id, b.target_text, b.match_type, b.is_auto, b.is_pt, b.is_sb, b.bid_floor,
  ROUND(b.current_bid, 2) AS current_bid,
  b.clk1 AS clicks_1d, ROUND(b.sp1, 2) AS spend_1d, ROUND(SAFE_DIVIDE(b.sp1, NULLIF(b.clk1,0)), 2) AS cpc_1d,
  b.units1 AS units_1d, b.roas1 AS roas_1d,
  b.clk2 AS clicks_prev2, ROUND(b.sp2, 2) AS spend_prev2, ROUND(SAFE_DIVIDE(b.sp2, NULLIF(b.clk2,0)), 2) AS cpc_prev2,
  b.units2 AS units_prev2, b.roas_prev2,
  b.converting, b.days_since_change,
  -- v27.46 A4: the 90d record that scales the dark brake, exposed for verification
  b.roas90,
  -- v27.76 (Task 4.9): the 90d COMPLETE-DAY click/order pair that roas90 is built from, PUBLISHED
  -- (additive — never rename/remove; the cube reads this view and additive columns are safe). The
  -- last-day veto's expected-orders gate is computed from these two in the outer wrapper, so the
  -- gate reads published columns and can never drift from what the row shows.
  b.clk90, b.ord90,
  b.tcpc AS target_cpc,
  b.tcpc_src AS target_cpc_source,
  b.slots, b.seat_rank, b.seat_cpc, b.seasonal_now,
  -- v27.48: the park reverdict, exposed for verification + the sweep surfaces
  b.is_revive, b.confirm_park, b.revive_bid, b.revive_immune,
  -- ROLE (Ori 2026-08-02): the keyword's job in the campaign economy (see V_KEYWORD_LIFT)
  CASE
    -- v27.45 DEFENSE doctrine: defense keywords are never touched by either engine
    WHEN b.is_defense THEN 'DEFENSE'
    WHEN b.is_lift_probe AND b.seat_rank <= b.slots THEN 'PROBE'
    -- AUTO DOCTRINE (Ori 2026-08-02): 4 fixed clauses — never retired/queued; trim + negate
    WHEN b.is_auto THEN CASE
      WHEN b.converting THEN 'WINNER'
      WHEN COALESCE(b.roas90, 0) >= 1.0 THEN 'WATCH'
      ELSE 'TRIAL' END
    -- v27.48: settled reverdict names the role — REVIVE (proven, coming back) outranks the
    -- queue/candidate labels; CONFIRM_PARK is a settled-verified retirement.
    WHEN b.is_revive THEN 'REVIVE'
    WHEN (b.tested_loser OR b.confirm_park) AND NOT b.is_lift_probe THEN 'RETIRED'
    WHEN b.seat_rank > b.slots THEN 'QUEUED'
    WHEN COALESCE(b.current_bid, 0) > 0 AND b.current_bid <= 0.30 THEN 'CANDIDATE'
    -- OOB has WINNERS not funders (Ori 2026-08-02): net ROAS >= 1.0 over the LAST 3 DAYS,
    -- always seated first; 90d-proven but cold in the last 3 -> WATCH (holds its seat)
    WHEN b.converting THEN 'WINNER'
    WHEN COALESCE(b.roas90, 0) >= 1.0 THEN 'WATCH'
    ELSE 'TRIAL'
  END AS role,
  CASE
    -- v27.45 DEFENSE doctrine: never a bid on a defense keyword — the budget ladder is the remedy
    WHEN b.is_defense THEN NULL
    WHEN b.current_bid IS NULL THEN NULL
    WHEN COALESCE(b.days_since_change, 99) < 1 THEN NULL
    -- v27.17 (Ori 2026-08-05: "bid should be reduced as well above 10 clicks and dark>0
    -- even if probing can be reduced"). VOLUME OUTRANKS EVERY DEFERRAL. 10+ unprofitable clicks
    -- in a capped campaign is real money burnt today, so this pre-empts BOTH the queue-first
    -- deferral (v27.8.2, which parked the seat brake while the queue leaked) and the mid-probe
    -- exemption -- a probe that burnt 16 clicks at 0x already has its answer. Winners are still
    -- never pulled down: the roas1 < 1.0 gate protects anything that paid yesterday.
    WHEN b.clk1 > 10 AND b.pct_dark > 0 AND COALESCE(b.roas1, 0) < 1.0
         AND b.current_bid > b.bid_floor + 0.01
      -- v27.46 A4: magnitude scaled by the 90d record (trigger unchanged; 5% minimum stands)
      THEN ROUND(GREATEST(b.current_bid * LEAST(x.bid_slow,
                    CASE WHEN COALESCE(b.roas90, 0) >= 1.0 THEN x.bid_slow
                         WHEN b.roas90 >= 0.6 THEN 1 - 0.15 * b.pct_dark / 100
                         ELSE 1 - 0.30 * b.pct_dark / 100 END,
                    -- v27.65 ZERO-SALE EVIDENCE FLOOR (Task 1.3): 10+ clicks yesterday with ZERO
                    -- sales on an unproven record is evidence, not noise — the step never shrinks
                    -- below 15% for such a row. Without this, the dark-scaled terms collapse to
                    -- the 5% minimum whenever pct_dark reads low (BALL Mint substitutes: 23c at
                    -- 0.00x braked 5%/day at "0% dark" while the campaign sat OOB-owned on 7-day
                    -- hysteresis — 12+ days to the floor on a keyword burning $8/day). Proven
                    -- (roas90 >= 1.0) keeps the gentle pace: v27.47/v27.63 doctrine — a winner is
                    -- paced, never punished, least of all for ONE unsettled day.
                    IF(b.clk1 >= 10 AND COALESCE(b.roas1, 0) = 0 AND COALESCE(b.roas90, 0) < 1.0,
                       0.85, 1.0)),
                          b.bid_floor), 2)
    -- QUEUE OWNS THE DARK (v27.8.2): beyond-seat rows still spending — park those first,
    -- the seat brake waits its turn (one medicine at a time).
    WHEN b.pct_dark > 10 AND b.seat_rank <= b.slots AND b.clk1 >= 1 AND COALESCE(b.roas1, 0) < 1.0
         AND b.queue_sp1 >= GREATEST(0.10 * b.budget, 1.0) THEN NULL
    -- DARK, NO RAISE COMING (Ori 2026-08-04, VIDEO- BALL 72% dark): the converting/probe holds
    -- assume "the budget raise is the lever" — but when yesterday's blended ROAS is under the
    -- ladder's 1.2x raise gate the budget is cutting/floored and the BIDS own the dark. Brake
    -- every keyword that clicked unprofitably yesterday; only 90d-proven seats and keywords
    -- that PAID yesterday keep their bid (winners never pulled down).
    WHEN b.pct_dark > 10 AND COALESCE(b.c_roas1, 0) < 1.2 AND COALESCE(b.roas90, 0) < 1.0
         AND b.seat_rank <= b.slots
         -- v27.18 (Ori 2026-08-05: "dark break should not be on keywords under 4 clicks").
         -- 1 click is not evidence — same 4-click bar TRIM already uses.
         AND (b.clk1 >= x.click_goal_day
              -- v27.25: or it is a CLICK HOG -- 20%+ of the campaign's clicks yesterday.
              -- 2-click floor keeps single-click noise out of a tiny campaign.
              OR (b.clk1 >= 2 AND COALESCE(b.clk_share1, 0) >= 0.20))
         AND COALESCE(b.roas1, 0) < 1.0 AND b.current_bid > b.bid_floor + 0.05
      THEN ROUND(GREATEST(b.current_bid * LEAST(x.bid_slow,
                    CASE WHEN COALESCE(b.roas90, 0) >= 1.0 THEN x.bid_slow
                         WHEN b.roas90 >= 0.6 THEN 1 - 0.15 * b.pct_dark / 100
                         ELSE 1 - 0.30 * b.pct_dark / 100 END,
                    -- v27.65 ZERO-SALE EVIDENCE FLOOR (Task 1.3): 10+ clicks yesterday with ZERO
                    -- sales on an unproven record is evidence, not noise — the step never shrinks
                    -- below 15% for such a row. Without this, the dark-scaled terms collapse to
                    -- the 5% minimum whenever pct_dark reads low (BALL Mint substitutes: 23c at
                    -- 0.00x braked 5%/day at "0% dark" while the campaign sat OOB-owned on 7-day
                    -- hysteresis — 12+ days to the floor on a keyword burning $8/day). Proven
                    -- (roas90 >= 1.0) keeps the gentle pace: v27.47/v27.63 doctrine — a winner is
                    -- paced, never punished, least of all for ONE unsettled day.
                    IF(b.clk1 >= 10 AND COALESCE(b.roas1, 0) = 0 AND COALESCE(b.roas90, 0) < 1.0,
                       0.85, 1.0)), b.bid_floor), 2)
    -- mid-probe keyword: the Portfolio 80/20 engine owns it — no seat-model action mid-test
    -- v14 (Ori 2026-08-02 "should those be parked?"): a probe only keeps its bid while it HOLDS
    -- A SEAT — beyond the seats it queues at $0.25 like any mid-test (test pauses, not dies).
    -- A mid-probe keyword never permanent-parks (its 20-click verdict outranks the 15-click bar).
    WHEN b.is_lift_probe AND b.seat_rank <= b.slots THEN NULL
    -- v27.48 SETTLE VETO: a revived (or manually-touched < 14d) keyword is immune to PARK /
    -- PARK_WAIT condemnations until 10 NEW settled clicks accrue — no condemnation before
    -- settle. The DARK_BRAKE/volume branches ABOVE still fire (dark is never a hold).
    WHEN b.revive_immune AND NOT b.is_auto AND (b.tested_loser OR b.seat_rank > b.slots) THEN NULL
    -- v27.48 ACTIVATE_REVIVE: a seated REVIVE row comes back at the CALIBRATED revive bid
    -- (clamp(min(pre-park bid, 1.1 x settled CPC), $0.31, $1.50) — snapshot-computed), never the
    -- $1 probe entry (proven record with an anchor, not an anchorless probe — Cause 2 in
    -- reverse). Same darkness gate + 20% pace as ACTIVATE; no clk1 precondition — the Cause-4
    -- cheap winners still clicking at the park bid are exactly who the $0.31+ floor repaces.
    -- Queue-stuck REVIVE rows fall to the PARK_WAIT branch and HOLD (already at the park bid) —
    -- their remedy is a BUDGET line for Ori (slots = budget/$4), not a bid line (v27.29).
    WHEN b.is_revive AND NOT b.is_auto AND b.seat_rank <= b.slots AND b.current_bid <= 0.30 THEN
      CASE
        WHEN b.manual_parked_recent THEN NULL
        WHEN (b.pct_dark > 0 OR b.days_capped_7d >= 2) AND b.act_rank > COALESCE(b.park_count, 0) THEN NULL
        WHEN b.act_rank <= GREATEST(1, CAST(FLOOR(0.20 * b.budget / 4) AS INT64))
          THEN ROUND(LEAST(GREATEST(COALESCE(b.revive_bid, 0.31), b.bid_floor), x.bid_max), 2)
        ELSE NULL END
    -- tested loser: permanent park (had its 15-click trial, no sale)
    WHEN b.tested_loser AND NOT b.is_lift_probe AND NOT b.is_auto AND b.current_bid > x.bid_park + 0.05 THEN x.bid_park
    WHEN b.tested_loser AND NOT b.is_lift_probe AND NOT b.is_auto THEN NULL
    -- beyond the seats: queue at $0.25 — the test pauses, not dies (seat model, Ori 2026-08-01)
    WHEN b.seat_rank > b.slots AND NOT b.is_auto THEN IF(b.current_bid > 0.30, x.bid_park, NULL)
    -- seated after being parked: ACTIVATE at the probe entry bid, paced by the 20% rule
    -- v27.19 (Ori 2026-08-05: "already have 6 clicks no need to activate and raise bid to 1
    -- because it is already active. gentle raise in this case"). ACTIVATE is the DORMANT
    -- keyword's on-ramp — a $0.25 -> $1.00 jump (4x) is only defensible with no delivery to
    -- price from. Once it clicks at the 4-click evidence bar it is live, so fall through to
    -- the normal converting / click-band ladder and let it raise proportionately.
    -- v27.48: the generic $1-entry ACTIVATE never touches reverdicted rows — REVIVE rows come
    -- back only via ACTIVATE_REVIVE above (calibrated bid), CONFIRM_PARK is a settled-verified
    -- loser that must not resurface, and a MANUAL park < 14d old is Ori's hand (Cause 3).
    WHEN b.current_bid <= 0.30 AND b.clk1 < x.click_goal_day
         AND NOT b.is_revive AND NOT b.confirm_park AND NOT b.manual_parked_recent
      -- v27.23 (Ori 2026-08-06: "do not activate new keywords until you reduce the dark% to 0").
      -- Adding a keyword to a campaign that already runs out of budget just splits the same
      -- money more ways -- it cannot buy incremental clicks, only steal them from the seats
      -- already funded. Clear the darkness first (raise the budget or ease the bids), THEN
      -- activate. v27.45: the population is now every OOB-owned campaign (not pct_dark > 10),
      -- so the gate reads the 7d cap evidence too — an anchor-light day must not open the
      -- activation door on a campaign capped 2+ of the last 7 days.
      THEN IF((b.pct_dark > 0 OR b.days_capped_7d >= 2) AND b.act_rank > COALESCE(b.park_count, 0), NULL,
              IF(b.act_rank <= GREATEST(1, CAST(FLOOR(0.20 * b.budget / 4) AS INT64)),
                 -- v27.69 (Task 2.2): CALIBRATED SEAT ENTRY, the $1 floor retired. DOCTRINE
                 -- SUCCESSION recorded: the floor was Ori 2026-08-02 ("i wont move if not"); the
                 -- Aug-9 post-mortem re-judged it — "real defect = $1.00 activation floor". Entry
                 -- = 1.5x target CPC when an anchor exists, floored $0.31 (revive floor), capped
                 -- by the SEAT CPC (what this campaign's budget affords per click — it is the
                 -- OUT-OF-BUDGET phase; an entry the seat cannot fund just re-darkens the day)
                 -- and $2.00. Anchorless (no tcpc): the seat CPC itself. Platform floor last.
                 ROUND(GREATEST(LEAST(GREATEST(COALESCE(1.5 * b.tcpc, b.seat_cpc), 0.31),
                                      GREATEST(b.seat_cpc, 0.31), x.bid_max),
                                b.bid_floor), 2), NULL))
    -- CONVERTING while CAPPED (Ori 2026-07-30): never raise the bid — the budget raise buys the
    -- volume, CHEAPER clicks buy more of it. Enough clicks + bid above what clicks actually cost →
    -- FIT the bid down to the realized 3d CPC (you keep winning the same auctions, priced honestly).
    WHEN b.converting THEN CASE
      -- campaign already winner-concentrated (>=80% of spend on converters): purpose is MORE
      -- clicks — glide the 6+-clickers down gently -5%/day (floor: real CPC)
      WHEN COALESCE(b.conv_share, 0) >= 0.80 THEN
        IF(b.ev_clk > 6 AND b.current_bid > COALESCE(b.ev_cpc, b.current_bid) + 0.05,
           ROUND(GREATEST(b.current_bid * 0.95, b.ev_cpc), 2),
           -- v27.16 (Ori 2026-08-05: "this is dark>0 therefore you must act · in this case i
           -- would decrease bid gently"). DARK IS NEVER A HOLD. The old NULL here paired with
           -- the budget ladder's "evidence mid -> hold budget, bids do the work" and DEADLOCKED:
           -- each engine told the other to move while one winner ate ~80% of a capped budget.
           -- When the campaign is capped at all, glide the concentrated winner -5%/day so the
           -- same budget buys more clicks. Floor = its target CPC (never below the platform
           -- min), and only when the bid is actually above that floor — this never raises.
           IF(b.pct_dark > 0
              AND b.current_bid > b.bid_floor + 0.01,
              ROUND(GREATEST(b.current_bid * 0.95,
                             b.bid_floor), 2),
              NULL))
      -- v27.63 (Ori 2026-08-13, pointing at a live FIT_CPC row: "this will starve it").
      -- THE PROVEN SEAT IS CHECKED HERE, NOT ONLY BELOW. The branch at the bottom of this CASE
      -- ("seated PROVEN keyword ... a proven keyword can never fall through to TRIM_BID") was
      -- UNREACHABLE for a converting keyword: `WHEN b.converting` matches first, so the exemption
      -- never got to run on exactly the rows it exists to protect. Measured at the time: all three
      -- live FIT_CPC rows were role=WINNER and proven — VIDEO- BALL "surprise balls for girls"
      -- $0.45 -> $0.38 on 4 clicks at 14.03x (90d 1.67x), ME-SBS "girls journals age 10-12"
      -- $1.00 -> $0.85 (1.59x), ME-VIDEO "diy journal kit for girls 8-14" $0.54 -> $0.46 (1.99x).
      -- WHY FITTING A WINNER TO ITS OWN CPC STARVES IT: the realized CPC is the price it paid AT
      -- THE CURRENT BID. VIDEO- BALL paid $0.33-0.35 while bidding $0.45; set the bid to $0.38 and
      -- every auction that cleared between $0.38 and $0.45 is lost — the DEAR ones, which is where
      -- top-of-search sits. You keep the cheap tail and lose the converting head, to save ~5c on a
      -- click returning 14x. Fitting to realized CPC only makes sense when the click is NOT worth
      -- what it costs; on a proven keyword it is.
      -- The rule is v27.47's, unchanged and copied verbatim from the branch below so the two can
      -- never drift: >4 clicks yesterday -> a flat 5% pace toward the floor; at/below the bar the
      -- seat is cheap and it HOLDS. The winner-concentrated arm above is untouched (Ori 2026-08-05
      -- approved its -5%/day glide: "dark is never a hold").
      WHEN COALESCE(b.roas90, 0) >= 1.0 THEN
        IF(COALESCE(b.clk1, 0) > x.click_goal_day AND b.current_bid > b.bid_floor + 0.05,
           ROUND(GREATEST(b.current_bid * x.bid_slow, b.bid_floor), 2),
           NULL)
      -- mixed campaign: fit the converter to its real CPC -15%/day while the ladder cleans the leak
      WHEN b.ev_clk >= x.click_goal_day
        AND b.ev_cpc IS NOT NULL
        AND b.current_bid > b.ev_cpc + 0.05
        THEN ROUND(GREATEST(b.current_bid * x.bid_big_trim, b.ev_cpc), 2)
      ELSE NULL END
    -- seated PROVEN keyword (90d corrected net ROAS >= 1.0): holds its seat untouched — the
    -- budget raise is the lever for winners, never the brake (approved example: seat 2 at 1.03x).
    -- v27.47 (Ori 2026-08-12, "clicks>4, brake 5%"): the exemption is CAPPED BY VOLUME. A proven
    -- keyword taking MORE THAN 4 clicks yesterday is spending today's capped budget on its 90d
    -- reputation (the case Ori flagged: 10 clicks at 0.00x, bid $1.00 vs a $0.55 target, held).
    -- Above the bar it brakes a FLAT 5% — deliberately the gentlest step, NOT the mid-test TRIM
    -- (15%/day) below: this keyword is proven, it is being paced, not punished. At/below the bar
    -- the seat is still cheap, so it holds untouched. Both outcomes stay inside this branch so a
    -- proven keyword can never fall through to TRIM_BID.
    WHEN COALESCE(b.roas90, 0) >= 1.0 THEN
      IF(COALESCE(b.clk1, 0) > x.click_goal_day AND b.current_bid > b.bid_floor + 0.05,
         ROUND(GREATEST(b.current_bid * x.bid_slow, b.bid_floor), 2),
         NULL)
    -- seated mid-test: trial economics against the PER-SEAT affordable (budget / slots / 4 clicks).
    -- TRIM needs REAL evidence (Ori 2026-08-01) — 4+ clicks yesterday; step max(15%, 30% x dark).
    WHEN b.current_bid > b.seat_cpc + 0.05 AND b.ev_clk >= x.click_goal_day
      THEN ROUND(GREATEST(b.current_bid * LEAST(x.bid_big_trim, 1 - 0.30 * b.pct_dark / 100), b.seat_cpc), 2)
    -- DARK_BRAKE (Ori 2026-08-01, replaces flat SLOW -5%): the bid lever against darkness is
    -- CAMPAIGN-WIDE and proportional — every clicked keyword steps down max(5%, 30% x dark) per
    -- day, re-firing daily while the campaign stays capped, floor $0.20. No single keyword is
    -- "the eater"; the campaign bleeds from many bids collectively.
    -- only keywords that clicked YESTERDAY (Ori 2026-08-01: never brake a keyword that did not
    -- click — its bid did not eat the budget; it just loses its chance to ever test)
    WHEN b.clk1 >= x.click_goal_day AND b.current_bid > b.bid_floor + 0.05
      THEN ROUND(GREATEST(b.current_bid * LEAST(x.bid_slow,
                    CASE WHEN COALESCE(b.roas90, 0) >= 1.0 THEN x.bid_slow
                         WHEN b.roas90 >= 0.6 THEN 1 - 0.15 * b.pct_dark / 100
                         ELSE 1 - 0.30 * b.pct_dark / 100 END,
                    -- v27.65 ZERO-SALE EVIDENCE FLOOR (Task 1.3): 10+ clicks yesterday with ZERO
                    -- sales on an unproven record is evidence, not noise — the step never shrinks
                    -- below 15% for such a row. Without this, the dark-scaled terms collapse to
                    -- the 5% minimum whenever pct_dark reads low (BALL Mint substitutes: 23c at
                    -- 0.00x braked 5%/day at "0% dark" while the campaign sat OOB-owned on 7-day
                    -- hysteresis — 12+ days to the floor on a keyword burning $8/day). Proven
                    -- (roas90 >= 1.0) keeps the gentle pace: v27.47/v27.63 doctrine — a winner is
                    -- paced, never punished, least of all for ONE unsettled day.
                    IF(b.clk1 >= 10 AND COALESCE(b.roas1, 0) = 0 AND COALESCE(b.roas90, 0) < 1.0,
                       0.85, 1.0)), b.bid_floor), 2)
    ELSE NULL
  END AS suggested_bid,
  CASE
    -- v27.45 DEFENSE doctrine: visible, never instructs
    WHEN b.is_defense THEN 'DEFENSE'
    WHEN b.current_bid IS NULL THEN 'NO_BID'
    WHEN COALESCE(b.days_since_change, 99) < 1 THEN 'HOLD'
    -- v27.17 (Ori 2026-08-05: "bid should be reduced as well above 10 clicks and dark>0
    -- even if probing can be reduced"). VOLUME OUTRANKS EVERY DEFERRAL. 10+ unprofitable clicks
    -- in a capped campaign is real money burnt today, so this pre-empts BOTH the queue-first
    -- deferral (v27.8.2, which parked the seat brake while the queue leaked) and the mid-probe
    -- exemption -- a probe that burnt 16 clicks at 0x already has its answer. Winners are still
    -- never pulled down: the roas1 < 1.0 gate protects anything that paid yesterday.
    WHEN b.clk1 > 10 AND b.pct_dark > 0 AND COALESCE(b.roas1, 0) < 1.0
         AND b.current_bid > b.bid_floor + 0.01
      THEN 'DARK_BRAKE'
    WHEN b.pct_dark > 10 AND b.seat_rank <= b.slots AND b.clk1 >= 1 AND COALESCE(b.roas1, 0) < 1.0
         AND b.queue_sp1 >= GREATEST(0.10 * b.budget, 1.0) THEN 'HOLD'
    WHEN b.pct_dark > 10 AND COALESCE(b.c_roas1, 0) < 1.2 AND COALESCE(b.roas90, 0) < 1.0
         AND b.seat_rank <= b.slots
         AND (b.clk1 >= x.click_goal_day
              -- v27.25: or it is a CLICK HOG -- 20%+ of the campaign's clicks yesterday.
              -- 2-click floor keeps single-click noise out of a tiny campaign.
              OR (b.clk1 >= 2 AND COALESCE(b.clk_share1, 0) >= 0.20))
         AND COALESCE(b.roas1, 0) < 1.0 AND b.current_bid > b.bid_floor + 0.05 THEN 'DARK_BRAKE'  -- v27.18: 4-click evidence bar
    WHEN b.is_lift_probe AND b.seat_rank <= b.slots THEN 'HOLD'
    -- v27.48 settle veto — same predicate as the suggested_bid ladder. No-change action
    -- (v27.29 exempt set alongside APPLIED_HOLD/DEFER_OOB).
    WHEN b.revive_immune AND NOT b.is_auto AND (b.tested_loser OR b.seat_rank > b.slots) THEN 'REVIVE_SETTLE_HOLD'
    -- v27.48 ACTIVATE_REVIVE — same predicate as the suggested_bid ladder.
    WHEN b.is_revive AND NOT b.is_auto AND b.seat_rank <= b.slots AND b.current_bid <= 0.30 THEN
      CASE
        WHEN b.manual_parked_recent THEN 'HOLD'
        WHEN (b.pct_dark > 0 OR b.days_capped_7d >= 2) AND b.act_rank > COALESCE(b.park_count, 0) THEN 'HOLD'
        WHEN b.act_rank <= GREATEST(1, CAST(FLOOR(0.20 * b.budget / 4) AS INT64)) THEN 'ACTIVATE_REVIVE'
        ELSE 'HOLD' END
    WHEN b.tested_loser AND NOT b.is_lift_probe AND NOT b.is_auto THEN IF(b.current_bid > x.bid_park + 0.05, 'PARK', 'HOLD')
    WHEN b.seat_rank > b.slots AND NOT b.is_auto THEN IF(b.current_bid > 0.30, 'PARK_WAIT', 'HOLD')
    -- v27.19 (Ori 2026-08-05: "already have 6 clicks no need to activate and raise bid to 1
    -- because it is already active. gentle raise in this case"). ACTIVATE is the DORMANT
    -- keyword's on-ramp — a $0.25 -> $1.00 jump (4x) is only defensible with no delivery to
    -- price from. Once it clicks at the 4-click evidence bar it is live, so fall through to
    -- the normal converting / click-band ladder and let it raise proportionately.
    -- v27.48: generic ACTIVATE skips reverdicted rows (same predicate as the suggested_bid ladder)
    WHEN b.current_bid <= 0.30 AND b.clk1 < x.click_goal_day
         AND NOT b.is_revive AND NOT b.confirm_park AND NOT b.manual_parked_recent
      -- v27.23 (Ori 2026-08-06: "do not activate new keywords until you reduce the dark% to 0").
      -- Adding a keyword to a campaign that already runs out of budget just splits the same
      -- money more ways -- it cannot buy incremental clicks, only steal them from the seats
      -- already funded. Clear the darkness first (raise the budget or ease the bids), THEN
      -- activate. v27.45: gate reads the 7d cap evidence too (see the suggested_bid note).
      THEN IF((b.pct_dark > 0 OR b.days_capped_7d >= 2) AND b.act_rank > COALESCE(b.park_count, 0), 'HOLD', IF(b.act_rank <= GREATEST(1, CAST(FLOOR(0.20 * b.budget / 4) AS INT64)), 'ACTIVATE', 'HOLD'))
    WHEN b.converting THEN CASE
      WHEN COALESCE(b.conv_share, 0) >= 0.80 THEN
        IF(b.ev_clk > 6 AND b.current_bid > COALESCE(b.ev_cpc, b.current_bid) + 0.05, 'EASE',
           -- v27.16: dark is never a hold — see the suggested_bid note above.
           IF(b.pct_dark > 0
              AND b.current_bid > b.bid_floor + 0.01,
              'EASE', 'HOLD'))
      -- v27.63: the proven seat, checked before FIT_CPC — see the suggested_bid note above.
      WHEN COALESCE(b.roas90, 0) >= 1.0 THEN
        IF(COALESCE(b.clk1, 0) > x.click_goal_day AND b.current_bid > b.bid_floor + 0.05, 'DARK_BRAKE', 'HOLD')
      WHEN b.ev_clk >= x.click_goal_day
        AND b.current_bid > COALESCE(b.ev_cpc, b.current_bid) + 0.05 THEN 'FIT_CPC'
      ELSE 'HOLD' END
    -- v27.47: proven holds its seat at/below the 4-click bar; above it, a flat 5% brake (never TRIM)
    WHEN COALESCE(b.roas90, 0) >= 1.0 THEN
      IF(COALESCE(b.clk1, 0) > x.click_goal_day AND b.current_bid > b.bid_floor + 0.05, 'DARK_BRAKE', 'HOLD')
    WHEN b.current_bid > b.seat_cpc + 0.05 AND b.ev_clk >= x.click_goal_day THEN 'TRIM_BID'
    WHEN b.clk1 >= x.click_goal_day AND b.current_bid > b.bid_floor + 0.05 THEN 'DARK_BRAKE'
    ELSE 'HOLD'
  END AS bid_action,
  CASE
    -- v27.45 DEFENSE doctrine
    WHEN b.is_defense THEN 'brand defense — the moat is bought at whatever it costs; bids are never touched by either engine (the budget ladder is its remedy)'
    WHEN b.current_bid IS NULL THEN 'no bid on record'
    WHEN COALESCE(b.days_since_change, 99) < 1 THEN 'changed today — one suggestion per day'
    -- v27.17 (Ori 2026-08-05: "bid should be reduced as well above 10 clicks and dark>0
    -- even if probing can be reduced"). VOLUME OUTRANKS EVERY DEFERRAL. 10+ unprofitable clicks
    -- in a capped campaign is real money burnt today, so this pre-empts BOTH the queue-first
    -- deferral (v27.8.2, which parked the seat brake while the queue leaked) and the mid-probe
    -- exemption -- a probe that burnt 16 clicks at 0x already has its answer. Winners are still
    -- never pulled down: the roas1 < 1.0 gate protects anything that paid yesterday.
    WHEN b.clk1 > 10 AND b.pct_dark > 0 AND COALESCE(b.roas1, 0) < 1.0
         AND b.current_bid > b.bid_floor + 0.01
      THEN CONCAT(CAST(b.clk1 AS STRING), ' clicks yesterday at ', FORMAT('%.2f', COALESCE(b.roas1,0)),
                  'x while the campaign is ', CAST(CAST(b.pct_dark AS INT64) AS STRING),
                  '% dark — volume this size waits for neither the queue nor a probe verdict: brake ',
                  CAST(CAST(ROUND(100*(1 - LEAST(x.bid_slow,
                    CASE WHEN COALESCE(b.roas90, 0) >= 1.0 THEN x.bid_slow
                         WHEN b.roas90 >= 0.6 THEN 1 - 0.15 * b.pct_dark / 100
                         ELSE 1 - 0.30 * b.pct_dark / 100 END,
                    -- v27.65 ZERO-SALE EVIDENCE FLOOR (Task 1.3): 10+ clicks yesterday with ZERO
                    -- sales on an unproven record is evidence, not noise — the step never shrinks
                    -- below 15% for such a row. Without this, the dark-scaled terms collapse to
                    -- the 5% minimum whenever pct_dark reads low (BALL Mint substitutes: 23c at
                    -- 0.00x braked 5%/day at "0% dark" while the campaign sat OOB-owned on 7-day
                    -- hysteresis — 12+ days to the floor on a keyword burning $8/day). Proven
                    -- (roas90 >= 1.0) keeps the gentle pace: v27.47/v27.63 doctrine — a winner is
                    -- paced, never punished, least of all for ONE unsettled day.
                    IF(b.clk1 >= 10 AND COALESCE(b.roas1, 0) = 0 AND COALESCE(b.roas90, 0) < 1.0,
                       0.85, 1.0)))) AS INT64) AS STRING),
                  '% toward $', FORMAT('%.2f', b.bid_floor),
                  CASE WHEN COALESCE(b.roas90, 0) >= 1.0 THEN ' (90d proven — minimum ease)'
                       -- v27.65: name the zero-sale floor when it is the binding term
                       WHEN b.clk1 >= 10 AND COALESCE(b.roas1, 0) = 0
                         THEN ' (double-digit zero-sale day — the 15% evidence floor binds)'
                       WHEN b.roas90 >= 0.6 THEN ' (90d 0.6-1.0x — half brake)' ELSE '' END)
    WHEN b.pct_dark > 10 AND b.seat_rank <= b.slots AND b.clk1 >= 1 AND COALESCE(b.roas1, 0) < 1.0
         AND b.queue_sp1 >= GREATEST(0.10 * b.budget, 1.0)
      THEN CONCAT('dark ', CAST(CAST(b.pct_dark AS INT64) AS STRING), '% but the queue spent $',
                  FORMAT('%.2f', b.queue_sp1), ' yesterday beyond the seats — park those first (frees the budget); the seat brake waits its turn')
    WHEN b.pct_dark > 10 AND COALESCE(b.c_roas1, 0) < 1.2 AND COALESCE(b.roas90, 0) < 1.0
         AND b.seat_rank <= b.slots
         -- v27.18 (Ori 2026-08-05: "dark break should not be on keywords under 4 clicks").
         -- 1 click is not evidence — same 4-click bar TRIM already uses.
         AND (b.clk1 >= x.click_goal_day
              -- v27.25: or it is a CLICK HOG -- 20%+ of the campaign's clicks yesterday.
              -- 2-click floor keeps single-click noise out of a tiny campaign.
              OR (b.clk1 >= 2 AND COALESCE(b.clk_share1, 0) >= 0.20))
         AND COALESCE(b.roas1, 0) < 1.0 AND b.current_bid > b.bid_floor + 0.05
      -- v27.70 (reviewer A, structural): name the leg this predicate actually reads — the
      -- 1-day blended ROAS vs the 1.2x DAY-gate. It must not claim the budget ladder's raise
      -- gate: that ladder now judges peak windows, a different instrument this row never read.
      THEN CONCAT('campaign ', CAST(CAST(b.pct_dark AS INT64) AS STRING), '% dark (yesterday blended ',
                  FORMAT('%.2f', COALESCE(b.c_roas1, 0)), 'x under the 1.2x day-gate) — bids own the dark: brake ',
                  CAST(CAST(ROUND(100 * (1 - LEAST(x.bid_slow,
                    CASE WHEN COALESCE(b.roas90, 0) >= 1.0 THEN x.bid_slow
                         WHEN b.roas90 >= 0.6 THEN 1 - 0.15 * b.pct_dark / 100
                         ELSE 1 - 0.30 * b.pct_dark / 100 END,
                    -- v27.65 ZERO-SALE EVIDENCE FLOOR (Task 1.3): 10+ clicks yesterday with ZERO
                    -- sales on an unproven record is evidence, not noise — the step never shrinks
                    -- below 15% for such a row. Without this, the dark-scaled terms collapse to
                    -- the 5% minimum whenever pct_dark reads low (BALL Mint substitutes: 23c at
                    -- 0.00x braked 5%/day at "0% dark" while the campaign sat OOB-owned on 7-day
                    -- hysteresis — 12+ days to the floor on a keyword burning $8/day). Proven
                    -- (roas90 >= 1.0) keeps the gentle pace: v27.47/v27.63 doctrine — a winner is
                    -- paced, never punished, least of all for ONE unsettled day.
                    IF(b.clk1 >= 10 AND COALESCE(b.roas1, 0) = 0 AND COALESCE(b.roas90, 0) < 1.0,
                       0.85, 1.0)))) AS INT64) AS STRING),
                  '%/day toward $', FORMAT('%.2f', b.bid_floor), '; this bid spent ', CAST(b.clk1 AS STRING), ' clicks at ',
                  FORMAT('%.2f', COALESCE(b.roas1, 0)), 'x yesterday',
                  CASE WHEN COALESCE(b.roas90, 0) >= 1.0 THEN ' (90d proven — minimum ease)'
                       -- v27.65: name the zero-sale floor when it is the binding term
                       WHEN b.clk1 >= 10 AND COALESCE(b.roas1, 0) = 0
                         THEN ' (double-digit zero-sale day — the 15% evidence floor binds)'
                       WHEN b.roas90 >= 0.6 THEN ' (90d 0.6-1.0x — half brake)' ELSE '' END)
    WHEN b.is_lift_probe AND b.seat_rank <= b.slots THEN 'probe in flight — holds a seat until its 20-click verdict (the Portfolio 80/20 engine owns the bid)'
    -- v27.48 settle veto reason — same predicate as the other two ladders.
    WHEN b.revive_immune AND NOT b.is_auto AND (b.tested_loser OR b.seat_rank > b.slots)
      THEN CONCAT('no condemnation before settle — ', COALESCE(b.immune_reason, 'revival settling'),
                  ' (dark brakes/eases stay live; park-class actions wait for settled evidence)')
    -- v27.48 ACTIVATE_REVIVE reasons — same predicate as the other two ladders.
    WHEN b.is_revive AND NOT b.is_auto AND b.seat_rank <= b.slots AND b.current_bid <= 0.30 THEN
      CASE
        WHEN b.manual_parked_recent
          THEN CONCAT("REVIVE verdict, but the park is Ori's MANUAL change < 14d old — the engine defers; revive via the sweep sheet if intended. ",
                      COALESCE(b.reverdict_reason, ''))
        WHEN (b.pct_dark > 0 OR b.days_capped_7d >= 2) AND b.act_rank > COALESCE(b.park_count, 0)
          THEN CONCAT('REVIVE verdict waiting while the campaign is ', CAST(CAST(b.pct_dark AS INT64) AS STRING),
                      '% dark (capped ', CAST(b.days_capped_7d AS STRING),
                      'd of 7) — a revival is only budget-neutral if it replaces a park: clear the darkness, then revive. ',
                      COALESCE(b.reverdict_reason, ''))
        WHEN b.act_rank <= GREATEST(1, CAST(FLOOR(0.20 * b.budget / 4) AS INT64))
          THEN CONCAT('REVIVED at its calibrated bid (min(pre-park bid, 1.1x settled CPC), floor $0.31 — never the $1 probe entry: proven record, not an anchorless probe). ',
                      COALESCE(b.reverdict_reason, ''))
        ELSE CONCAT('REVIVE verdict — seat ready, activates on a coming day (20% pace). ', COALESCE(b.reverdict_reason, ''))
        END
    WHEN b.tested_loser AND NOT b.is_lift_probe AND NOT b.is_auto
      THEN CONCAT('tested ', CAST(b.clk90 AS STRING), ' clicks/90d with 0 orders — permanent park; its seat goes to the next candidate')
    WHEN b.seat_rank > b.slots AND NOT b.is_auto THEN
      IF(b.converting OR COALESCE(b.roas90, 0) >= 1.0,
         CONCAT('proven (', CAST(COALESCE(b.roas90, 0) AS STRING), 'x 90d) but the budget funds only ',
                CAST(b.slots AS STRING), ' seats — queue #', CAST(b.seat_rank - b.slots AS STRING)),
         CONCAT(IF(b.is_lift_probe, 'probe pauses — beyond the seats while the campaign caps; ', ''),
                'queue #', CAST(b.seat_rank - b.slots AS STRING), ' of the waiting line — ',
                CAST(b.slots AS STRING), ' seats (budget ÷ $4); its test resumes when a seat frees'))
    -- v27.48: same reverdict exclusions as the other two ladders; a CONFIRM_PARK / manual park
    -- that falls through reads the ELSE hold reason.
    WHEN b.current_bid <= 0.30 AND b.clk1 < x.click_goal_day
         AND NOT b.is_revive AND NOT b.confirm_park AND NOT b.manual_parked_recent THEN  -- v27.19: dormant only
      IF((b.pct_dark > 0 OR b.days_capped_7d >= 2) AND b.act_rank > COALESCE(b.park_count, 0),
         -- v27.23: darkness first (see the suggested_bid note above) · v27.45: 7d cap evidence too
         CONCAT('waiting while the campaign is ', CAST(CAST(b.pct_dark AS INT64) AS STRING),
                '% dark (capped ', CAST(b.days_capped_7d AS STRING),
                'd of 7) — an activation here is only budget-neutral if it REPLACES a park, and this run parks ',
                CAST(COALESCE(b.park_count, 0) AS STRING), ': ease the bids to clear the darkness, then activate'),
      IF(b.act_rank <= GREATEST(1, CAST(FLOOR(0.20 * b.budget / 4) AS INT64)),
         CONCAT(IF(b.seasonal_now, 'SEASONAL REVIVAL (sold in this window last year) — ', ''),
                'seat freed — ACTIVATE at ', IF(b.tcpc IS NOT NULL, '1.5x target CPC (floor $0.31, capped by the seat CPC — v27.69, the $1 floor retired)', 'the seat CPC (no anchor — v27.69)'),
                ' to resume its test (', CAST(b.clk90 AS STRING), '/', CAST(x.tested_clk AS STRING), ' clicks so far)'),
         'seat ready — activates on a coming day (20% pace: 80% of the budget keeps feeding the winners)'))
    WHEN b.converting THEN CASE
      WHEN COALESCE(b.conv_share, 0) >= 0.80 THEN
        IF(b.ev_clk > 6 AND b.current_bid > COALESCE(b.ev_cpc, b.current_bid) + 0.05,
           CONCAT('winners take ', CAST(ROUND(100*b.conv_share) AS STRING),
                  '% of spend — ease -5%/day toward real CPC $', CAST(ROUND(b.ev_cpc, 2) AS STRING),
                  ' to buy MORE clicks from the same budget'),
           -- v27.16: dark is never a hold. Say which lever moved and why.
           IF(b.pct_dark > 0
              AND b.current_bid > b.bid_floor + 0.01,
              CONCAT('winners take ', CAST(ROUND(100*b.conv_share) AS STRING),
                     '% of spend and the campaign is ', CAST(CAST(b.pct_dark AS INT64) AS STRING),
                     '% dark — the budget is capped, so ease -5%/day toward the $',
                     FORMAT('%.2f', b.bid_floor),
                     ': cheaper clicks buy more of the same budget'),
              'converting in a winner-concentrated campaign — hold (budget raise is the lever)'))
      -- v27.63: the proven seat, checked before FIT_CPC — see the suggested_bid note above.
      WHEN COALESCE(b.roas90, 0) >= 1.0 THEN
        IF(COALESCE(b.clk1, 0) > x.click_goal_day AND b.current_bid > b.bid_floor + 0.05,
           CONCAT('converting AND proven ', CAST(b.roas90 AS STRING), 'x over 90d, but ',
                  CAST(COALESCE(b.clk1, 0) AS STRING),
                  ' clicks yesterday (>4) on a capped budget — pace it 5%/day toward $',
                  CAST(b.bid_floor AS STRING),
                  '; a winner is paced, never fitted down to the CPC it paid at this bid'),
           CONCAT('converting AND proven ', CAST(b.roas90 AS STRING), 'x over 90d on ',
                  CAST(COALESCE(b.clk1, 0) AS STRING),
                  ' click(s) yesterday — holds its seat. Fitting the bid to its own realized CPC ',
                  'would cost it every auction clearing above the new bid — the dear ones, where ',
                  'top-of-search sits. The budget raise is the lever for a winner, not the brake'))
      WHEN b.ev_clk >= x.click_goal_day
        AND b.current_bid > COALESCE(b.ev_cpc, b.current_bid) + 0.05
        THEN CONCAT('selling while capping — fit bid down to the real CPC $',
                    CAST(ROUND(b.ev_cpc, 2) AS STRING),
                    ': budget raise buys volume, cheaper clicks buy more of it (never raise while dark)')
      ELSE 'converting — hold; the budget raise is the lever while capping' END
    -- v27.47: proven holds its seat at/below the 4-click bar; above it a flat 5% brake
    WHEN COALESCE(b.roas90, 0) >= 1.0 THEN
      IF(COALESCE(b.clk1, 0) > x.click_goal_day AND b.current_bid > b.bid_floor + 0.05,
         CONCAT('proven ', CAST(b.roas90 AS STRING), 'x over 90d but ', CAST(COALESCE(b.clk1, 0) AS STRING),
                ' clicks yesterday (>4) on a capped budget — brake 5%/day toward $', CAST(b.bid_floor AS STRING),
                '; the seat exemption stops at the 4-click bar (paced, not punished — no 15% trim)'),
         CONCAT('proven ', CAST(b.roas90 AS STRING), 'x over 90d and only ', CAST(COALESCE(b.clk1, 0) AS STRING),
                ' click(s) yesterday — holds its seat; the budget raise is the lever, not the brake'))
    WHEN b.current_bid > b.seat_cpc + 0.05 AND b.ev_clk >= x.click_goal_day
      THEN CONCAT('bid eats the capped budget (', CAST(b.ev_clk AS STRING), IF(b.is_low_tier, ' clicks yesterday', ' clicks/7d'), ') — trim ',
                  CAST(CAST(ROUND(100 * (1 - LEAST(x.bid_big_trim, 1 - 0.30 * b.pct_dark / 100))) AS INT64) AS STRING),
                  '%/day toward the seat CPC $', CAST(b.seat_cpc AS STRING), ' (= budget ÷ seats ÷ 4-click goal)')
    WHEN b.clk1 >= x.click_goal_day AND b.current_bid > b.bid_floor + 0.05
      -- v27.97 (Ori 2026-08-21, explanation audit) — TEXT ONLY. The predicate, the step and the
      -- floor are BYTE-IDENTICAL to v27.65; only the sentence changed. THE DEFECT: this is the
      -- FALL-THROUGH dark brake and its trigger is NOT darkness. A row is here because its
      -- CAMPAIGN is OOB-owned, and ownership is the DUAL signal — an out-of-budget event OR spend
      -- >= budget, held on the 7-day hysteresis (fact_oi_spend_over_budget_is_dark: the dark clock
      -- misses overdelivery entirely). So the anchor-day pct_dark reads 0.0 on a campaign that has
      -- been capped all week, and the old string opened "campaign 0% dark — brake all bids":
      -- a ZERO offered as the reason for a brake. It then dumped the rule's formula raw
      -- ("0.6-1.0x max(5%,15%×dark)") instead of the evidence, so the term that ACTUALLY set the
      -- rate was invisible — BOX-SBS/BROAD (Hunter, By Age) 2026-08-21 published two rows quoting
      -- the SAME "0% dark" and braking 5% ("8 year old girl birthday gift", 5 clicks) and 15%
      -- ("girls gifts age 8-10", 57 clicks). Same stated evidence, different move.
      -- THE GRAMMAR NOW (house shape, TRIGGER — EVIDENCE ⇒ MOVE, no formulas, no rule names):
      --   TRIGGER  = the cap evidence that actually fired (days_capped_7d of 7); darkness is named
      --              ONLY when there IS darkness, never as a zero.
      --   EVIDENCE = this bid's OWN clicks and sales yesterday — the numbers that differ between
      --              a 5% row and a 15% row, so two different moves can never quote one fact.
      --   MOVE     = the step, toward the row's REAL floor. The old string hard-coded "$0.20";
      --              the arithmetic floors at b.bid_floor, which is $0.25 on SB video/brand and
      --              $0.10 on SB collection/store — 6 of the 13 live rows were told a wrong number.
      --   CLOSER   = the term that BOUND the rate, in plain words (zero-sale evidence floor /
      --              darkness / the 5% minimum), so the rate is always traceable from the sentence.
      THEN CONCAT(
        CASE
          WHEN b.days_capped_7d >= 1 AND b.pct_dark > 0
            THEN CONCAT('out of budget ', CAST(b.days_capped_7d AS STRING),
                        ' of the last 7 days and dark ',
                        CAST(CAST(b.pct_dark AS INT64) AS STRING), '% of yesterday')
          WHEN b.days_capped_7d >= 1
            THEN CONCAT('out of budget ', CAST(b.days_capped_7d AS STRING), ' of the last 7 days')
          WHEN b.pct_dark > 0
            THEN CONCAT('dark ', CAST(CAST(b.pct_dark AS INT64) AS STRING), '% of yesterday')
          -- membership is is_oob_owned, so the campaign is capped even when both counters read low
          ELSE 'the campaign is out of budget'
        END,
        ' — ', CAST(b.clk1 AS STRING), ' clicks yesterday ',
        IF(COALESCE(b.roas1, 0) = 0, 'with no sales',
           CONCAT('at ', FORMAT('%.2f', b.roas1), 'x')),
        ' ⇒ brake ',
        -- UNCHANGED ARITHMETIC — the same LEAST(...) the suggested_bid branch above computes.
        -- v27.65 ZERO-SALE EVIDENCE FLOOR (Task 1.3): 10+ clicks yesterday with ZERO sales on an
        -- unproven record is evidence, not noise — the step never shrinks below 15% for such a
        -- row. Without it the dark-scaled terms collapse to the 5% minimum whenever pct_dark reads
        -- low (BALL Mint substitutes: 23c at 0.00x braked 5%/day at "0% dark" while the campaign
        -- sat OOB-owned on 7-day hysteresis — 12+ days to the floor on a keyword burning $8/day).
        -- Proven (roas90 >= 1.0) keeps the gentle pace: v27.47/v27.63 — a winner is paced, never
        -- punished, least of all for ONE unsettled day.
        CAST(CAST(ROUND(100 * (1 - LEAST(x.bid_slow,
          CASE WHEN COALESCE(b.roas90, 0) >= 1.0 THEN x.bid_slow
               WHEN b.roas90 >= 0.6 THEN 1 - 0.15 * b.pct_dark / 100
               ELSE 1 - 0.30 * b.pct_dark / 100 END,
          IF(b.clk1 >= 10 AND COALESCE(b.roas1, 0) = 0 AND COALESCE(b.roas90, 0) < 1.0,
             0.85, 1.0)))) AS INT64) AS STRING),
        '%/day toward $', FORMAT('%.2f', b.bid_floor),
        -- WHICH TERM BOUND THE RATE, in words. dark_pct = the dark-scaled step in percentage
        -- points (0 on the proven arm, which takes the flat 5%); zero_pct = 15 when the zero-sale
        -- floor applies. Whichever is larger is what the reader is told, so a 15% row and a 5% row
        -- can never close with the same sentence.
        CASE
          WHEN b.pct_dark * IF(COALESCE(b.roas90, 0) >= 1.0, 0,
                               IF(COALESCE(b.roas90, 0) >= 0.6, 0.15, 0.30)) > 5
               AND b.pct_dark * IF(COALESCE(b.roas90, 0) >= 1.0, 0,
                                   IF(COALESCE(b.roas90, 0) >= 0.6, 0.15, 0.30))
                   >= IF(b.clk1 >= 10 AND COALESCE(b.roas1, 0) = 0 AND COALESCE(b.roas90, 0) < 1.0, 15, 0)
            THEN ' — the step is sized to how much of yesterday the campaign spent dark'
          WHEN b.clk1 >= 10 AND COALESCE(b.roas1, 0) = 0 AND COALESCE(b.roas90, 0) < 1.0
            THEN ' — double digit clicks and not one sale is a verdict, so the full 15%, not the gentle 5%'
          WHEN COALESCE(b.roas1, 0) > 0
            THEN ' — sales did land, just short of paying, so this is the gentlest daily step'
          ELSE ' — under 10 clicks is too thin for a zero to be a verdict, so the gentlest daily step'
        END)
    -- v27.48: parked rows the reverdict keeps parked say so (they fell through every action branch)
    WHEN (b.confirm_park OR b.manual_parked_recent) AND NOT b.is_auto AND b.current_bid <= 0.30
      THEN CONCAT(IF(b.confirm_park, 'CONFIRM_PARK — never resurfaces via the $1 activation: ',
                     'MANUAL park < 14d old — the engine defers to Ori: '),
                  COALESCE(b.reverdict_reason, 'settled evidence confirms the park'))
    ELSE 'no clicks yesterday (its bid did not eat the budget) or already at the $0.20 floor — hold'
  END AS bid_reason
FROM seats3 b CROSS JOIN k x
),
-- ── v27.42 SEASON-CONTEXT GATE LAYER (2026-08-08, SEASON_CONTEXT_LEDGER.md §5) ──────────────
-- Keyword rows only: the ON clause carries NOT is_auto AND NOT is_pt, so auto clauses and
-- product targets read NULL gates by construction (the ledger pools keyword_text account-wide).
-- BLOCK_CUT: this context's settled record (>= 15c at >= 1.0x GP-ROAS) vetoes every
--   cut/park/brake to HOLD — calibration PASS (+$2,080 strict frame; protected winners earn ~3x
--   what wrong protections lose). Same-context evidence outranks the 1d/prev-2d window reads.
-- ENTRY_BLOCK STOP: prior same-family mature LOSS whose half-allowance re-probe is spent without
--   paying back — ACTIVATE (the only new-spend action here) resolves to HOLD; PROBING lets the
--   re-probe run (the re-probe is the point) but v27.43 clamps its funding to the remaining
--   allowance (see the header note). Hard blocks measured -$6,578; never hard-block.
-- PARK_CONTEXT: ADVISORY ONLY (calibration FAIL) — visible in context_gate/_reason, never acts.
gated AS (
SELECT
  o.* REPLACE (
    -- v27.46 A3: SEASONAL_NOW vs GATE PRECEDENCE — a mature same-context LOSS prior in
    -- PROBING/STOP strips the row's seasonal authority: the PUBLISHED seasonal_now flips FALSE
    -- so downstream consumers treat it as non-seasonal. Exemptions: converting (OOB's in-window
    -- winner test — A2 doctrine) and BLOCK_CUT (structural — ENTRY_BLOCK only emitted when
    -- BLOCK_CUT is not). ACTIVATE was already blocked on STOP (v27.42) and allowance-clamped on
    -- PROBING (v27.43); the inner seat-ordering limitation is documented in the SOP §5.7.
    IF(cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state IN ('PROBING', 'STOP')
       AND NOT o.converting,
       FALSE, o.seasonal_now) AS seasonal_now,
    CASE
      WHEN cg.gate_action = 'BLOCK_CUT'
       AND o.bid_action IN ('DARK_BRAKE','PARK','PARK_WAIT','TRIM_BID','EASE','FIT_CPC')
        THEN 'HOLD'
      WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP'
       AND o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
        THEN 'HOLD'
      -- v27.43 FIX C: a RUNNING re-probe (PROBING) may only fund up to the REMAINING half
      -- allowance (gate v27.43: remaining_allowance = probe_cap - near-settled occurrence spend).
      -- HOLD when the remainder is below the row's bid_floor (v27.33 — any offered bid would
      -- violate the floor: "re-probe allowance exhausted"), or when the clamp would land on the
      -- bid the row already has (no real move, v27.29). Otherwise the ACTIVATE bid is clamped to
      -- the remaining allowance in the suggested_bid CASE below.
      WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
       AND o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND (cg.remaining_allowance < o.bid_floor
            OR (o.suggested_bid IS NOT NULL
                AND cg.remaining_allowance < o.suggested_bid - 0.005
                AND ABS(GREATEST(o.bid_floor, LEAST(o.suggested_bid, cg.remaining_allowance))
                        - COALESCE(o.current_bid, 0)) < 0.005))
        THEN 'HOLD'
      -- v27.48.2 GENERAL SETTLE VETO (Cause 1): the tested-loser PARK may fire only on
      -- settled condemning clicks or a corroborating settled record (>= 10 settled clicks
      -- < 1.0x, no season WIN prior). BLOCK_CUT above outranks; PARK_WAIT / brakes stay live.
      WHEN o.bid_action = 'PARK'
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
       AND NOT COALESCE(g.settle_ok, TRUE)
       AND NOT (COALESCE(g.settled_clk90, 0) >= 10 AND COALESCE(g.settled_roas90, 0) < 1.0
                AND NOT COALESCE(g.settle_amnesty, FALSE))
       AND NOT COALESCE(g.settle_deferral_expired, FALSE)
        THEN 'SETTLE_HOLD'
      WHEN o.bid_action = 'HOLD' AND COALESCE(g.wake_due, FALSE)
       AND g.wake_step_bid IS NOT NULL
       AND g.wake_step_bid < COALESCE(o.current_bid, 0) - 0.005
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
        THEN 'WAKE_STEP'
      -- v27.48.2 PROBE READS THE RECORD (Cause 2): a scope-lifetime LOSER (>= 30 clicks under
      -- 0.6x) is NOT "untested" — never the $1 ACTIVATE entry; the loser path owns it.
      WHEN o.bid_action = 'ACTIVATE'
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
       AND COALESCE(g.life_clk, 0) >= 30 AND COALESCE(g.life_roas, 1) < 0.6
        THEN 'HOLD'
      -- v27.48.2 (Cause 2): the record-priced entry (lifetime conv CPC x 1.2; ENTRY_BLOCK rows
      -- also LY conv CPC x 0.8) lands on the bid the row already has — no real move (v27.29).
      -- v27.52 FIX 3: ACTIVATE_REVIVE is capped by the record too (was exempt, SOP §7.7).
      WHEN o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
       AND ((COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL)
            OR (cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL))
       AND o.suggested_bid IS NOT NULL
       AND ROUND(GREATEST(o.bid_floor, LEAST(o.suggested_bid,
             IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
             IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999))), 2)
           <= COALESCE(o.current_bid, 0) + 0.005
        THEN 'HOLD'
      ELSE o.bid_action END AS bid_action,
    CASE
      WHEN cg.gate_action = 'BLOCK_CUT'
       AND o.bid_action IN ('DARK_BRAKE','PARK','PARK_WAIT','TRIM_BID','EASE','FIT_CPC')
        THEN NULL
      WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP'
       AND o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
        THEN NULL
      -- v27.43 FIX C: exhausted / no-move re-probe HOLD carries no bid (same predicate as the
      -- bid_action ladder), else clamp the ACTIVATE bid to the remaining allowance — fires only
      -- when the clamp BINDS; GREATEST(bid_floor, ...) keeps v27.33 intact (remainder >= floor
      -- in this branch, so the result never exceeds the remaining allowance).
      WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
       AND o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND (cg.remaining_allowance < o.bid_floor
            OR (o.suggested_bid IS NOT NULL
                AND cg.remaining_allowance < o.suggested_bid - 0.005
                AND ABS(GREATEST(o.bid_floor, LEAST(o.suggested_bid, cg.remaining_allowance))
                        - COALESCE(o.current_bid, 0)) < 0.005))
        THEN NULL
      WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
       AND o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND cg.remaining_allowance >= o.bid_floor
       AND o.suggested_bid > cg.remaining_allowance + 0.005
        THEN ROUND(GREATEST(o.bid_floor, LEAST(o.suggested_bid, cg.remaining_allowance,
                     -- v27.48.2 (Cause 2): the record caps COMPOSE with the allowance clamp on
                     -- a generic ACTIVATE (min of all).
                     -- v27.52 FIX 3: ACTIVATE_REVIVE composes them too. §7.7 exempted it because
                     -- its bid is part-1-calibrated, but that calibration reads the settled-90d
                     -- CPC only -- it cannot see a scope-lifetime record saying the keyword has
                     -- never cleared that price, which is exactly the entry-price defect.
                     IF(o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE') AND COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL,
                        ROUND(1.2 * g.life_conv_cpc, 2), 999),
                     IF(o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE') AND g.ly_conv_cpc IS NOT NULL,
                        ROUND(0.8 * g.ly_conv_cpc, 2), 999))), 2)
      -- v27.48.2: settle veto / record-loser block / record-cap no-move carry no bid — same
      -- predicates as the bid_action ladder.
      WHEN o.bid_action = 'PARK'
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
       AND NOT COALESCE(g.settle_ok, TRUE)
       AND NOT (COALESCE(g.settled_clk90, 0) >= 10 AND COALESCE(g.settled_roas90, 0) < 1.0
                AND NOT COALESCE(g.settle_amnesty, FALSE))
       AND NOT COALESCE(g.settle_deferral_expired, FALSE)
        THEN NULL
      WHEN o.bid_action = 'HOLD' AND COALESCE(g.wake_due, FALSE)
       AND g.wake_step_bid IS NOT NULL
       AND g.wake_step_bid < COALESCE(o.current_bid, 0) - 0.005
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
        THEN GREATEST(o.bid_floor, g.wake_step_bid)
      WHEN o.bid_action = 'ACTIVATE'
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
       AND COALESCE(g.life_clk, 0) >= 30 AND COALESCE(g.life_roas, 1) < 0.6
        THEN NULL
      -- v27.52 FIX 3: ACTIVATE_REVIVE is capped by the record too (was exempt, SOP §7.7).
      WHEN o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
       AND ((COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL)
            OR (cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL))
       AND o.suggested_bid IS NOT NULL
       AND ROUND(GREATEST(o.bid_floor, LEAST(o.suggested_bid,
             IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
             IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999))), 2)
           <= COALESCE(o.current_bid, 0) + 0.005
        THEN NULL
      -- v27.48.2 (Cause 2): the standalone record cap — a generic ACTIVATE entry above the
      -- record price is clamped to it (fires only when the cap BINDS; the ENTRY_BLOCK branches
      -- above already carry the composed min for gated rows).
      -- v27.52 FIX 3: ACTIVATE_REVIVE is capped by the record too (was exempt, SOP §7.7).
      WHEN o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND ((COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL)
            OR (cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL))
       AND o.suggested_bid IS NOT NULL
       AND o.suggested_bid > LEAST(
             IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
             IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999)) + 0.005
        THEN ROUND(GREATEST(o.bid_floor, LEAST(o.suggested_bid,
             IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
             IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999))), 2)
      ELSE o.suggested_bid END AS suggested_bid,
    CASE
      WHEN cg.gate_action = 'BLOCK_CUT'
       AND o.bid_action IN ('DARK_BRAKE','PARK','PARK_WAIT','TRIM_BID','EASE','FIT_CPC')
        THEN CONCAT('this context (', cg.context_label, '): ', CAST(cg.cur_clicks AS STRING), 'c at ',
                    FORMAT('%.2f', COALESCE(cg.cur_gp_roas, 0)), 'x settled — cut vetoed (was ', o.bid_action, ')')
      WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP'
       AND o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
        -- v27.43: the reason now shows the NEAR-SETTLED numbers (the state is decided on them).
        THEN CONCAT('prior ', cg.prior_label, ': LOSS (', CAST(cg.prior_clicks AS STRING), 'c, net -$',
                    FORMAT('%.2f', ABS(cg.prior_net)), ', mature) — half-allowance re-probe $',
                    FORMAT('%.2f', cg.probe_cap), ' spent ($', FORMAT('%.2f', cg.ns_spend), ' near-settled at ',
                    FORMAT('%.2f', COALESCE(cg.ns_gp_roas, 0)),
                    'x) without paying back — do not activate this occurrence (was ', o.bid_action, ')')
      -- v27.43 FIX C reasons — same predicates as the bid_action / suggested_bid ladders.
      WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
       AND o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND cg.remaining_allowance < o.bid_floor
        THEN CONCAT('re-probe allowance exhausted ($', FORMAT('%.2f', cg.ns_spend), ' of $',
                    FORMAT('%.2f', cg.probe_cap),
                    ' near-settled) — holds until context ends or record turns (was ', o.bid_action, ')')
      WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
       AND o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND o.suggested_bid IS NOT NULL
       AND cg.remaining_allowance < o.suggested_bid - 0.005
       AND ABS(GREATEST(o.bid_floor, LEAST(o.suggested_bid, cg.remaining_allowance))
               - COALESCE(o.current_bid, 0)) < 0.005
        THEN CONCAT('remaining re-probe allowance $', FORMAT('%.2f', cg.remaining_allowance),
                    ' clamps the activation to the bid it already has — no real move; holds until context ends or record turns (was ', o.bid_action, ')')
      WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
       AND o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND cg.remaining_allowance >= o.bid_floor
       AND o.suggested_bid > cg.remaining_allowance + 0.005
        THEN CONCAT('seat freed — ACTIVATE clamped to the remaining re-probe allowance: $',
                    FORMAT('%.2f', cg.remaining_allowance), ' of the $', FORMAT('%.2f', cg.probe_cap),
                    ' half allowance left ($', FORMAT('%.2f', cg.ns_spend), ' near-settled spent this occurrence)')
      -- v27.48.2 settle-veto / record reasons — same predicates as the other two ladders.
      WHEN o.bid_action = 'PARK'
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
       AND NOT COALESCE(g.settle_ok, TRUE)
       AND NOT (COALESCE(g.settled_clk90, 0) >= 10 AND COALESCE(g.settled_roas90, 0) < 1.0
                AND NOT COALESCE(g.settle_amnesty, FALSE))
       AND NOT COALESCE(g.settle_deferral_expired, FALSE)
        THEN CONCAT('wave — sales not yet attributed (last click ', CAST(g.last_click_date AS STRING),
                    ', settles ', CAST(g.settle_due AS STRING), ', D+', CAST(g.settle_days_eff AS STRING),
                    IF(o.is_sb, ' SB', ' SP'), '); settled 90d ',
                    IF(COALESCE(g.settled_clk90, 0) >= 10,
                       CONCAT(CAST(g.settled_clk90 AS STRING), 'c at ', FORMAT('%.2f', COALESCE(g.settled_roas90, 0)), 'x',
                              IF(COALESCE(g.settle_amnesty, FALSE), ' + season WIN prior (this season, mature) — amnesty holds',
                                 IF(COALESCE(g.season_win_prior, FALSE), ' + season WIN prior', ''))),
                       CONCAT('only ', CAST(COALESCE(g.settled_clk90, 0) AS STRING), 'c — no corroboration')),
                    ' — no condemnation before settle, re-judge by ',
                    CAST(LEAST(COALESCE(g.settle_due, DATE_ADD(g.anchor_date, INTERVAL g.settle_days_eff DAY)),
                               DATE_ADD(COALESCE(g.first_click_60d, g.anchor_date), INTERVAL 2 * g.settle_days_eff DAY)) AS STRING),
                    ' (hard deferral bound: ', CAST(2 * g.settle_days_eff AS STRING),
                    'd of clicking; dark brakes/eases stay live; was PARK)')
      WHEN o.bid_action = 'HOLD' AND COALESCE(g.wake_due, FALSE)
       AND g.wake_step_bid IS NOT NULL
       AND g.wake_step_bid < COALESCE(o.current_bid, 0) - 0.005
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
        THEN CONCAT('woken to $1.00 on ', CAST(g.wake_date AS STRING), ' (', CAST(g.days_since_wake AS STRING),
                    'd ago) and never priced — ',
                    IF(COALESCE(g.wake_clk, 0) = 0,
                       'the wake bought no clicks at all: step back to $0.25',
                       CONCAT(CAST(CAST(g.wake_clk AS INT64) AS STRING), ' clicks / ',
                              CAST(CAST(g.wake_ord AS INT64) AS STRING), ' orders since the wake: price it at $',
                              FORMAT('%.2f', g.wake_step_bid))),
                    ' (wake it, then price it — the second half)')
      WHEN o.bid_action = 'ACTIVATE'
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
       AND COALESCE(g.life_clk, 0) >= 30 AND COALESCE(g.life_roas, 1) < 0.6
        THEN CONCAT('record says LOSER, not untested — ', CAST(g.life_clk AS STRING),
                    ' lifetime clicks at ', FORMAT('%.2f', COALESCE(g.life_roas, 0)),
                    'x GP-ROAS (scope-wide): no $1 activation, the loser path owns it (was ACTIVATE)')
      -- v27.52 FIX 3: ACTIVATE_REVIVE is capped by the record too (was exempt, SOP §7.7).
      WHEN o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND NOT (apg.last IS NOT NULL
                AND (DATE(apg.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(apg.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
       AND ((COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL)
            OR (cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL))
       AND o.suggested_bid IS NOT NULL
       AND ROUND(GREATEST(o.bid_floor, LEAST(o.suggested_bid,
             IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
             IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999))), 2)
           <= COALESCE(o.current_bid, 0) + 0.005
        THEN CONCAT('record-priced entry (lifetime conv CPC x1.2',
                    IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ' / LY-LOSS conv CPC x0.8', ''),
                    ') is the bid it already has — no real move (was ACTIVATE)')
      -- v27.52 FIX 3: ACTIVATE_REVIVE is capped by the record too (was exempt, SOP §7.7).
      WHEN o.bid_action IN ('ACTIVATE', 'ACTIVATE_REVIVE')
       AND ((COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL)
            OR (cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL))
       AND o.suggested_bid IS NOT NULL
       AND o.suggested_bid > LEAST(
             IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
             IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999)) + 0.005
        THEN CONCAT('activation anchored to the record — ',
                    IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL,
                       CONCAT(CAST(g.life_clk AS STRING), ' lifetime clicks, conv CPC $',
                              FORMAT('%.2f', g.life_conv_cpc), ' x1.2'), ''),
                    IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL,
                       CONCAT(IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, '; ', ''),
                              'prior same-season LOSS: LY conv CPC $', FORMAT('%.2f', g.ly_conv_cpc), ' x0.8'), ''),
                    ' — never the flat $', FORMAT('%.2f', o.suggested_bid),
                    ' on a keyword with a record (a keyword with hundreds of clicks is not untested)')
      ELSE o.bid_reason END AS bid_reason
  ),
  cg.gate_action AS context_gate,
  cg.gate_reason AS context_gate_reason,
  -- v27.48.2: the guard-snapshot signals, exposed for verification + the outermost manual hold
  g.settle_ok, g.settle_due, g.last_click_date,
  g.settled_clk90, g.settled_roas90, g.season_win_prior,
  -- v27.52 FIX 1: the bounded amnesty the settle veto actually reads (season_win_prior above is
  -- now occurrence-scoped and is kept as a display fact — the LICENCE is this column).
  COALESCE(g.settle_amnesty, FALSE) AS settle_amnesty, COALESCE(g.catastrophic, FALSE) AS catastrophic,
  g.life_clk AS lifetime_clicks, g.life_roas AS lifetime_gp_roas, g.life_conv_cpc AS lifetime_conv_cpc,
  g.ly_conv_cpc,
  COALESCE(g.manual_hold, FALSE) AS manual_hold, g.last_bid_source, g.last_bid_change_date
FROM outp o
LEFT JOIN `onyga-482313.OI.V_KEYWORD_CONTEXT_GATE` cg
  ON cg.keyword_text = LOWER(TRIM(o.target_text)) AND NOT o.is_auto AND NOT o.is_pt
-- v27.48.2: the guard SNAPSHOT (never the view — planner-ceiling doctrine): a small-table join
-- on the final rowset only; the seat CTEs are untouched. Missing rows fail OPEN.
LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_GUARD` g
  ON g.campaign_id = CAST(o.campaign_id AS STRING) AND g.keyword_id = CAST(o.keyword_id AS STRING)
-- v27.48.2: the applied-change self-test INSIDE the gated layer — the new guard HOLDs defer to
-- a pending applied change so the OUTERMOST layer still names those rows APPLIED_HOLD (the
-- applied doctrine outranks the new guards; without this a guard HOLD would strip the
-- suggestion the outermost ap-test keys on, and an uploaded row would lose its APPLIED_HOLD).
LEFT JOIN applied apg ON apg.cid = CAST(o.campaign_id AS STRING) AND apg.tgt = LOWER(TRIM(o.target_text))
)
-- ── v27.45 APPLIED-HOLD LAYER (outermost — mirrors V_OOB_BUDGET_PHASE's budget hold) ─────────
-- A bid change uploaded within 48h that was applied TODAY (America/Los_Angeles) — one ladder
-- step per day — or whose value has not reached the config mirror yet (|delta| > 0.005) holds
-- the row: bid_action 'APPLIED_HOLD', no suggestion. This sits ABOVE the season gate the same
-- way PHASE's budget hold sits above its ladder: a suggestion computed from a stale base is not
-- trustworthy no matter which layer priced it. Fires only on rows that would otherwise emit a
-- bid (suggested_bid IS NOT NULL) — no-change rows keep their labels. APPLIED_HOLD is a
-- no-change action (v27.29 no-empty-promises exempt set alongside DEFER_OOB in V_KEYWORD_LIFT).
-- v27.48.2 MANUAL_HOLD (Cause 3) rides in the SAME outermost layer, directly BELOW the applied
-- hold (APPLIED_HOLD keeps working unchanged — tomorrow every uploaded row still shows it):
-- the last bid change is Ori's hand (source MANUAL, < 7d — guard manual_hold, which already
-- carries the catastrophic escape: settled 90d < 0.6x on >= 10 settled clicks releases the
-- engine) and the row would otherwise instruct -> MANUAL_HOLD, no suggestion. No-change action
-- (v27.29 exempt family). Unlogged Amazon-console writes cannot be held (SOP §7.8).
SELECT g.* EXCEPT (ap_hold, man_hold) REPLACE (
  IF(g.ap_hold, 'APPLIED_HOLD', IF(g.man_hold, 'MANUAL_HOLD', g.bid_action)) AS bid_action,
  IF(g.ap_hold OR g.man_hold, NULL, g.suggested_bid) AS suggested_bid,
  IF(g.ap_hold, CONCAT('applied $', FORMAT('%.2f', ap.last.new_bid), ' at ',
       FORMAT_TIMESTAMP('%b %d %H:%M', ap.last.ts, 'America/Los_Angeles'),
       ' — step done; suggestions resume when the new bid syncs from Amazon'),
     IF(g.man_hold, CONCAT('MANUAL change ', CAST(g.last_bid_change_date AS STRING),
          " — Ori's hand outranks the engines for 7 days (settled record not catastrophic): suggestion suppressed (was ",
          g.bid_action, ')'),
        g.bid_reason)) AS bid_reason
)
FROM (
  SELECT g0.*,
    ap0.last IS NOT NULL AND g0.suggested_bid IS NOT NULL AND
      (DATE(ap0.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
       OR ABS(COALESCE(ap0.last.new_bid, -1) - COALESCE(g0.current_bid, -1)) > 0.005) AS ap_hold,
    g0.manual_hold AND g0.suggested_bid IS NOT NULL
      AND g0.bid_action NOT IN ('DARK_BRAKE') AS man_hold
  FROM gated g0
  LEFT JOIN applied ap0 ON ap0.cid = CAST(g0.campaign_id AS STRING) AND ap0.tgt = LOWER(TRIM(g0.target_text))
) g
LEFT JOIN applied ap ON ap.cid = CAST(g.campaign_id AS STRING) AND ap.tgt = LOWER(TRIM(g.target_text))
) pub
    ) p0
  ) p1
  CROSS JOIN lastday lv
) pub
CROSS JOIN lastday lv;
