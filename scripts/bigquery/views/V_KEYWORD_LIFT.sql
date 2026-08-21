-- V_KEYWORD_LIFT — the 80/20 portfolio + probe rotation for WORKING campaigns (budget > low-budget
-- cap), SP v1. Spec: architecture/OOB_BUDGET_PHASE.md §"Lever 2B". Ori 2026-07-30:
--   "80% of spend should go to winner keywords and 20% to losers. most losers parked; 1-2 probes
--    raise the bid to check if they are profitable; after 20 clicks each, if profitable continue,
--    else park and probe the next 1-2. the goal is the best keyword for intent at the best bid so
--    all keywords are profitable per 7 days off-season / 3 days peak."
--
-- ############################################################################
-- # v27.62 — THE GP RULE: READ FACT_AMAZON_ADS.GROSS_PROFIT. NEVER RECOMPUTE. #
-- ############################################################################
-- (Ori 2026-08-13, found by checking the panel against Amazon.) All NINE gross-profit sites in this
-- view now read the STORED FACT_AMAZON_ADS.GROSS_PROFIT column. The old formula
--     Ads_sales - COALESCE(T_PRICE_COST_TIER.tier_cost, TOTAL_COST_PER_UNIT) * Ads_units
--   LEFT JOIN T_PRICE_COST_TIER pct ON Ads_units > 0
--     AND pct.unit_price = ROUND(SAFE_DIVIDE(Ads_sales, Ads_units), 2)
-- and all three of its joins ARE GONE. The join looked the cost tier up by an "implied unit price"
-- of Ads_sales / Ads_units — which is NOT the product's price: Ads_sales carries HALO sales of
-- OTHER products (~79% purchased-vs-advertised divergence in this account) while Ads_units does not
-- correspond to them. PROVEN on VIDEO- BALL / 2026-08-12: implied $24.39 for a $13.99 product
-- matched a ~$21.50 tier, overrode the real TOTAL_COST_PER_UNIT of $9.77, and collapsed
-- GP $229.16 -> $37.17 — a GP-ROAS of 3.69x read as 0.60x, on a campaign Amazon's own console
-- reports at $331.08 sales / $64.05 spend that day. Arithmetic: 317.09 - 9.77 x 13 = 229.16 =
-- FACT.GROSS_PROFIT exactly. WHY IT EXISTED: FACT began charging tier COGS at LOAD time on
-- 2026-08-01; these views predate that and were never updated, so they re-derived a number that
-- was already correct — and got it wrong. WHY IT HID: account-wide over 30 days the two agree to
-- ~3% (0.845 vs 0.817). The damage is PER ROW, on exactly the rows a decision is made about.
-- THIS VIEW IS THE 80/20 SORT: every winner/loser class, seat rank, probe verdict and park
-- decision here was ranked on the corrupted number. Same fix, same day: V_LOW_STOCK_ADS (v27.61)
-- and the other seven engine views.
--
--
-- WINDOW W = 7d off-season / 3d peak. CLASSES over W (corrected net ROAS):
--   WINNER >= 1.1 with >= 1 order · MARGINAL 0.7-1.1 with orders · LOSER < 0.7 or clicks w/ 0 orders
--   IDLE = no clicks in W (parked / dormant — the probe candidate pool, with untested keywords)
--
-- PROBE EPISODES ARE STATELESS: an episode = the last INCREASE_BID upload for the keyword
-- (FACT_PPC_CHANGE_LOG) within the last 14 days; test evidence = FACT activity AFTER that date.
-- Verdict at 20 episode clicks: net ROAS >= 1.0 → WINNER_FOUND (joins the 80% pool), else PARK.
-- While testing, the keyword is exempt from PARK here and (by design) from the coacher's pullback.
--
-- v2 (2026-07-30): + SB ARM — the same machinery on SB-native sources, the way V_SB_LAUNCH_TARGET
-- mirrors V_LAUNCH_PHASE1. Targets + live bids from the sb_keyword / sb_product_target config
-- mirrors; performance from sb_search_term_report (keyword grain) ∪ sb_target_report (product
-- targets) — NOT sb_keyword_report (died 2025-12-29; sb_product_target_report does not exist);
-- net ROAS is the SB ESTIMATE sales × (1 − mapped-ASIN cost_ratio) ÷ spend (SB has no per-unit
-- COGS). Target-CPC precedence: LY same-28d → FINE band (SB × ad_format via DIM_AD_GROUP
-- creative_type × match) → coarse ALL/ALL band. Capped guard: PROBE_START requires the campaign
-- NOT capping (dark ≤ 10% on the anchor day) — probing a capped campaign is a budget artifact.
-- `channel` ('SP'/'SB') routes panel rows to the right bulksheet tab.
--
-- v3 (2026-07-30): capped guard mirrored into the SP arm (sp_h/sp_ev/sp_sqd/sp_dark on SP
-- campaign_history events, anchored at FACT's watermark `wm`) — both arms now gate PROBE_START.
--
-- v27.39 (2026-08-07): FAMILY RESOLUTION FIX — `camp_parent` (shared by BOTH arms) now reads the
-- canonical `V_DIM_CAMPAIGN_FAMILY` instead of name-parsing ASIN_BY_CAMPAIGN_NAME with ANY_VALUE.
-- 134 of 650 rows were sitting on the wrong family's CPC band (BUNNY/BALL/ME-MINT → 'Lollibox',
-- BRAND-STORE → 'Bottle'). Coverage is unchanged (644/650 rows, 108/109 campaigns): this is a
-- CORRECTNESS fix, not a coverage fix. It does NOT close the 40 no-target rows — see the note at
-- the CTE; those are missing PRODUCT/AUTO band cells in DE_PRODUCT_STRATEGY_PROFILE.
--
-- v27.42 (2026-08-08): SEASON-CONTEXT GATES — the output layer reads V_KEYWORD_CONTEXT_GATE
-- (keyword rows only: the join carries NOT is_auto AND NOT is_pt). BLOCK_CUT (calibration PASS,
-- +$2,080 strict / +$21,386 wide): a keyword whose CURRENT occurrence settled record is >= 15
-- clicks at GP-ROAS >= 1.0 has every cut/park vetoed to HOLD — same-context settled evidence
-- outranks the 4-click window read (so it also pre-empts v27.34's park; the mirror conflict
-- cannot occur: a same-context LOSS can never mint a BLOCK_CUT gate). ENTRY_BLOCK (PASS only
-- WITH the half-allowance re-probe: +$551 vs hard block -$6,578): prior same-family MATURE LOSS
-- verdict -> the re-probe runs (PROBING: no interference) until the half allowance is spent
-- without paying back (STOP) -> funding actions PARK $0.25; window winners (>= 4c >= 1.0x, the
-- v27.28 bar) are always released — season memory never pulls down a live winner. PARK_CONTEXT:
-- calibration FAIL — ADVISORY ONLY, surfaces in context_gate/context_gate_reason, never acts.
-- Precedence + calibration record: architecture/SEASON_CONTEXT_LEDGER.md §5-6.
--
-- v27.43 (2026-08-08): RE-PROBE ALLOWANCE ENFORCEMENT (FIX C) — the gate's entry_state now runs
-- on NEAR-SETTLED numbers (gate v27.43 FIX A: [occurrence_start, anchor-3]) with a 90d escape
-- hatch (FIX B: >= 100c at GP-ROAS >= 1.0 releases a would-be STOP). On ENTRY_BLOCK/PROBING rows,
-- funding actions (PROBE_START, PROBE_ADJUST, NUDGE_UP, VOLUME_LIFT, seasonal RAISE_TO_TARGET)
-- respect the remaining allowance: suggested_bid clamped to LEAST(bid, remaining_allowance) when
-- the remainder clears the row's per-format floor (v27.33 — a clamped bid below its floor is a
-- violation, so below-floor remainders resolve to HOLD: "re-probe allowance exhausted"). A clamp
-- landing on the current bid is no real move (v27.29) -> HOLD. Window winners (v27.28 bar) are
-- never clamped. STOP behavior unchanged; its reason now shows the near-settled numbers.
--
-- v27.46 (2026-08-09) guard batch:
--   A3 SEASONAL_NOW vs GATE PRECEDENCE — a row with a mature same-context LOSS prior and gate
--   entry_state PROBING/STOP loses its seasonal authority unless it is an in-window winner
--   (clicks_w >= 4 AND roas_w >= 1.0 — the v27.28 bar; DOCTRINE per A2: current-window
--   conversion outranks prior-season memory) or BLOCK_CUT-protected (occurrence-level settled
--   winner, gate precedence). The emitted-instruction surface was already guarded (v27.42 STOP
--   blocks seasonal RAISE_TO_TARGET + all funding; v27.43 clamps PROBING funding to the
--   remaining allowance); v27.46 adds the PUBLISHED seasonal_now column neutralization so every
--   downstream consumer treats the row as non-seasonal. KNOWN LIMIT (documented in the SOP
--   §5.7): the inner seat/cand ordering still reads raw seasonal_now — gate columns cannot
--   reach those CTEs without re-planning the gate subtree inside the engines (the §5.1
--   plan-cost trap); the seat a jumped row holds can only spend its allowance-clamped bids.
--   A4 DARK-BRAKE MAGNITUDE BY 90d REALITY — AUTO_BRAKE (this engine's one dark-magnitude
--   brake; DARK_BRAKE proper lives in V_OOB_KEYWORD since v27.45 DEFER_OOB) scales its step by
--   the clause's own 90d record: roas90 >= 1.0 -> minimum ease 5%; 0.6-1.0 -> max(5%, 15% x
--   dark); < 0.6 or no data -> max(5%, 30% x dark). Trigger unchanged; floors unchanged; dark
--   is never a hold (the 5% minimum stands).
--
-- v27.48 (2026-08-09): REVIVAL MACHINERY — consumes FACT_PARK_REVERDICT (the snapshot of
-- V_PARK_REVERDICT; engines never read the view — plan-cost doctrine). Ori's settle rule:
-- "no condemnation before settle, re-judgment at settle" (SEASON_CONTEXT_LEDGER.md §7).
--   1. SEAT + CANDIDATE ORDERING (SP arm): reverdict REVIVE rows join the proven tier and rank
--      above fresh unproven inside it (settled-winner rank — fixes the queue-ranking half of
--      Cause 2 for revivals); CONFIRM_PARK rows sink with the tested losers and are skipped by
--      the probe-candidate ranking (their seat must go to a live candidate).
--   2. Output layer (both arms; SB rows read NULL reverdicts by construction — the parked stock
--      is SP config): REVIVE_SETTLE_HOLD vetoes PARK / PARK_WAIT / CUT_TO_BREAKEVEN /
--      CUT_TO_TARGET and the v27.34 window-loss re-park on engine_immune rows (revived off a
--      proven settled record until 10 NEW settled clicks accrue, or a manual change < 14d old —
--      Cause 3). EASE_TO_TARGET / RESEARCH_EASE / brakes stay live (dark is never a hold; the
--      veto blocks only condemnations). CONFIRM_PARK / manual parks never resurface via
--      PROBE_START/NUDGE/RAISE. ACTIVATE_REVIVE: a seated, uncapped, ungated REVIVE row comes
--      back at the CALIBRATED revive bid (clamp(min(pre-park bid, 1.1 x settled CPC), $0.31,
--      $1.50)) — never the flat $1 probe entry ($1 entries on proven sub-$0.30-CPC records is
--      Cause-2 behavior in reverse). ENTRY_BLOCK (STOP or PROBING) defers revival to the gate's
--      re-probe economics (season-gate precedence); the applied-today/unsynced self-test keeps
--      an uploaded revival from re-emitting (APPLIED_HOLD doctrine). REVIVE_SETTLE_HOLD is a
--      no-change action (v27.29 exempt set); ACTIVATE_REVIVE always carries a real bid.
--
-- v27.53 (2026-08-12, Ori approved "do all engine work") — ITEM 3 the cut gate is scaled to the
-- window it judges (NEW base column cut_gate = max(4, ceil(13 x eff_days / 7)), one definition
-- shared by all three ladders, replacing the fixed 13/30 at all 12 condemnation sites); ITEM 4 NEW
-- LONG_LEG_HOLD — PARK and CUT_TO_BREAKEVEN condemned on the SHORT window alone, so they now carry
-- V_OOB_BUDGET_PHASE's two-leg rule (the 8-28d settled window must not read >= 1.0x); ITEM 7 NEW
-- WAKE_STEP (the second half of the $1.00 on-ramp); ITEM 8c CONFIRM_PARK can no longer resurface as
-- WINNER_FOUND through EITHER door (outer winner shield + inner probe verdict); ITEM 8f MANUAL_HOLD
-- moved BELOW the dark brakes (dark is never a hold). ITEMS 3 AND 4 SHIPPED TOGETHER BY DESIGN:
-- 3 makes the engine eligible to act more often, 4 is the brake. Combined effect 2026-08-12 on 644
-- rows: emitted condemnations 5 -> 8 ($59.77 -> $145.10); items 2+3 alone would have emitted 15.
-- Spec: architecture/SEASON_CONTEXT_LEDGER.md §7.16.
--
-- v27.48.2 (2026-08-09, part 2): ENGINE GUARDS — consumes FACT_KEYWORD_GUARD (snapshot of
-- V_KEYWORD_GUARD, Task 20.5f; engines never read the view — plan-cost doctrine). Four guards:
--   1. GENERAL SETTLE VETO (Cause 1) — condemnations (PARK / CUT_TO_BREAKEVEN / CUT_TO_TARGET
--      + the v27.34 window-loss re-park) may fire only if (a) the condemning clicks are fully
--      settled (no clicks in the last D+7 SP / D+14 SB — guard settle_ok) OR (b) the
--      channel-aware settled 90d record corroborates (>= 10 settled clicks at GP-ROAS < 1.0,
--      and no season WIN prior). Else SETTLE_HOLD — "wave: sales not yet attributed, re-judge
--      at settle". EASE_TO_TARGET / RESEARCH_EASE / AUTO_* brakes and PARK_WAIT (seat-queue
--      mechanics, not a verdict) stay live — dark is never a hold. ENTRY_BLOCK rows are exempt
--      (season-gate precedence unchanged); the v27.28 winner shield and BLOCK_CUT sit above.
--   2. PROBE READS THE RECORD (Cause 2) — a PROBE_START entry is capped by the keyword's own
--      record: scope-lifetime >= 30 clicks -> entry <= lifetime conv CPC x 1.2; ENTRY_BLOCK
--      (prior same-family mature LOSS) -> entry <= LY conv CPC x 0.8 — BOTH compose with the
--      v27.43 allowance clamp (min of all three) and the per-format floor. A scope-lifetime
--      LOSER (>= 30 clicks < 0.6x) is NOT "untested": PROBE_START -> HOLD (the loser path owns
--      it, never a $1 entry). Queue ordering: settled evidence outranks fresh unsettled — a
--      settled-winner key extends the v27.38 profit ordering (probe_rank), the seat_rank proven
--      tier (below is_revive: part-1 revives stay on top) and cand_rank; scope-lifetime losers
--      leave the candidate pool.
--   3. MANUAL_HOLD (Cause 3) — the last bid change's source = 'MANUAL' (Ori's hand via the Do
--      page; COACH/REUPLOAD are engine-class) and < 7 days old -> every suggestion is
--      suppressed (MANUAL_HOLD, no bid) unless the settled 90d record is catastrophic
--      (< 0.6x on >= 10 settled clicks — a keyword losing money NOW is not protected).
--      Sits directly BELOW APPLIED_HOLD (upload holds keep working unchanged). COVERAGE HOLE
--      (SOP §7.8): changes made directly in the Amazon console are unlogged and cannot be held.
--   4. PACE_RAISE (Cause 4) — the LY-pacing raise, calibrated 2026-08-09 (threshold: 28d
--      instance clicks < 25% of the LY same-28d window, weekday-aligned; proven settled 90d
--      >= 1.2x on >= 10 settled clicks; scope lifetime >= 100 clicks; LY window >= 20 clicks;
--      bid < LY conv CPC; bid stable >= 7d; campaign not OOB-owned/capped). Fires only on
--      otherwise-idle rows (KEEP/KEEP_TAIL/HOLD/IDLE/PROBE_START), seated, ungated, not
--      window-losing, deferring to the part-1 revive path unless that path is manually blocked.
--      Glide +10%/day toward the guard's economics target: GREATEST(bid, LEAST(band cpc_max,
--      settled GP-per-click / 1.2, 1.5 x LY conv CPC)) capped $2.00 — the only signal that
--      reaches the starved-winner class the engines are structurally blind to.
--   SETTLE_HOLD / MANUAL_HOLD join the v27.29 no-change exempt set; PACE_RAISE always carries
--   a real bid (predicate requires target > bid).
--
-- v27.45 (2026-08-08): ONE BID OWNER + SINGLE BUDGET AUTHORITY.
--   DEFER_OOB: a campaign that V_CAMPAIGN_CAP_STATE marks is_oob_owned (per-day v27.15 dual
--   signal, hysteresis enter days_capped_7d >= 2 / exit at 0 — calibration in the SOP §v27.45)
--   is owned by the out-of-budget engine. Its rows here stay VISIBLE but do not instruct:
--   action 'DEFER_OOB', no suggested_bid, reason "capped Nd of 7 — out-of-budget engine owns
--   the bids". This lands ABOVE every output guard (it is structural ownership, not a verdict);
--   DEFENSE rows are exempt — a defense campaign's keywords stay DEFENSE in both engines and
--   neither engine ever touches their bids (the budget ladder is defense's remedy). DEFER_OOB
--   and APPLIED_HOLD are no-change actions (v27.29 no-empty-promises exempt set). Before this,
--   capped campaigns took instructions from BOTH engines ($1.2-1.3k/wk of contradictions, incl.
--   an applied CUT flipping into an OOB RAISE) — see iteration-4 D3 / iteration-5 3.2.
--   SINGLE BUDGET AUTHORITY: for campaigns present in V_OOB_BUDGET_PHASE, suggested_budget /
--   budget_reason are READ FROM PHASE (which carries its own applied-hold). LIFT's own
--   healthy-campaign loss-cut budget rule survives ONLY for campaigns not in PHASE. Before
--   this, LIFT's budget column contradicted PHASE on 3 campaigns ($31.7/day) and whichever
--   page the user read won.
--
-- v27.74 (2026-08-17, Task 4.7): COMPLETE-DAYS WINDOWS — every trailing multi-day ads window
--   (W, 3d, 4-14 band, 7d, 90d — both arms) now ends at wm-1, the last complete day; the filling
--   day (clk1/roas_1d) stands alone; prev-2d already ended wm-1; 8-28 settled legs, LY/season
--   windows, episode evidence, dark clock and cooldown math unchanged. Day counts keep their
--   names; only the spans shift.
--
-- v27.75 (2026-08-17, Task 4.8): THE LAST-DAY VETO — the standalone filling day (clicks_1d/roas_1d)
--   may only HOLD a published move, never drive one: a RAISE at >10 clicks under 0.50x waits a day;
--   a CUT at >10 clicks at/above 1.20x waits a day. Thin outer wrapper over the published rows
--   (pure functions of published columns), plain HOLD + bid NULLed; direction = suggested-vs-current
--   comparison, never the action name; tunables in the lastday CTE. Bid lever only — suggested_budget
--   / budget_reason and the whole budget arm are untouched.
--
-- v27.76 (2026-08-17, Task 4.9): THE EXPECTED-ORDERS GATE — the v27.75 RAISE veto over-fired on
--   AMBIGUOUS zeros. At age 1 we see ~85% of a day's spend but only ~69% of its sales
--   (V_ADS_SETTLE_CURVE), and 46% of at-volume keywords read exactly 0.00x on the filling day.
--   Worked example (Ori 2026-08-17): BOX-SP/AUTO (Pink) "substitutes" converts once per ~42 clicks
--   and has zero-order days 6 times in 13; on the filling day it took ~45 clicks (≈1 expected order),
--   got 0, read 0.00x — and its raise was vetoed. That is an ORDINARY day for that keyword, and
--   because it is busy every day its raise would be blocked ~63% of days FOREVER, not "a day".
--   So the raise arm now splits on whether the poor reading is INFORMATIVE:
--     roas_1d > 0 (or < 0)  — sales DID land and were poor ⇒ veto exactly as v27.75. No gate.
--     roas_1d = 0 or NULL   — ambiguous ⇒ veto ONLY IF the zero is surprising:
--       expected_orders_1d = clicks_1d × (orders_90d / clicks_90d) >= 3.0  (Poisson: P(0|3) ≈ 5%)
--     No rate, or zero orders in the window ⇒ expected_orders_1d = 0 ⇒ NO veto. No history = no
--     surprise = no block; the veto may only block when it HAS evidence.
--   THE CUT ARM IS UNCHANGED — missing sales can only make a day look worse, so a fresh day already
--   at/above 1.20x is conservative proof. Additive columns clicks_90d / orders_90d are now PUBLISHED
--   (the longest complete-day pair this view carries — t90 / sb_t90, ends wm-1 per Task 4.7) so the
--   gate reads published columns; expected orders is computed ONCE as an internal column inside the
--   same thin wrapper, so the boolean and its reason text cannot drift. New tunable in lastday:
--   veto_min_expected_orders. reason_short grammar is byte-for-byte unchanged.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_LIFT` AS
-- ── v27.75 THE LAST-DAY VETO (Task 4.8, Ori 2026-08-17) ─────────────────────────────────────
-- Complete-day windows DECIDE moves (Task 4.7 / v27.74); the standalone filling day
-- (clicks_1d/roas_1d) may only HOLD a move, never drive one. Symmetric, at real volume, as a THIN
-- OUTER WRAPPER over the published rows (the same shape the sibling V_OOB_KEYWORD carries at
-- v27.75, built on this view's own reason_short precedent): the veto booleans are computed ONCE
-- below as pure functions of already-published columns, so the four transformed columns
-- (action / suggested_bid / reason / reason_short) can never drift apart.
--   RAISE (suggested > current) at clicks_1d > 10 and COALESCE(roas_1d, 0) < 0.5 ⇒ HOLD, bid NULLed
--   CUT   (suggested < current) at clicks_1d > 10 and roas_1d >= 1.2             ⇒ HOLD, bid NULLed
-- Direction is the BID COMPARISON, never the action name — PROBE_START / PROBE_ADJUST / WAKE_STEP /
-- ACTIVATE_REVIVE / NUDGE_UP / PARK / CUT_TO_* all classify themselves (a probe ENTRY is a raise and
-- is vetoed like any raise; a PARK is a cut and is vetoed like any cut).
-- BID LEVER ONLY: suggested_budget / budget_reason and every budget arm are untouched, and
-- SP_SNAPSHOT_ENGINE_PROPOSALS takes LIFT budgets on `suggested_budget IS NOT NULL` alone (never on
-- action), so a vetoed keyword row cannot suppress its campaign's budget instruction.
-- Rows with no published bid (HOLD / DEFENSE / APPLIED_HOLD / MANUAL_HOLD / SETTLE_HOLD / DEFER_OOB /
-- IDLE / ...) are untouched — the veto only ever downgrades a published move to plain HOLD (this
-- view's do-nothing idiom), so a vetoed row drops out of the proposal snapshot naturally while the
-- panel still shows the row with its why.
WITH lastday AS (
  SELECT
    10  AS veto_clk1,        -- real-volume bar: the filling day only vetoes above this many of its own clicks (Ori tunable)
    0.5 AS veto_raise_roas,  -- a published RAISE waits a day when the filling day reads under this (Ori tunable)
    1.2 AS veto_cut_roas,    -- a published CUT waits a day when the filling day reads at/above this (Ori tunable)
    3.0 AS veto_min_expected_orders  -- v27.76: a 0.00x filling day only vetoes a RAISE when its own 90d rate expected at least this many orders (Ori tunable)
)
SELECT pub.* EXCEPT (veto_raise, veto_cut, exp_ord_1d) REPLACE (
  IF(pub.veto_raise OR pub.veto_cut, 'HOLD', pub.action) AS action,
  IF(pub.veto_raise OR pub.veto_cut, NULL, pub.suggested_bid) AS suggested_bid,
  CASE
    WHEN pub.veto_raise THEN CONCAT(
      'LAST-DAY VETO (Task 4.8): the standalone filling day read ', CAST(pub.clicks_1d AS STRING),
      ' clicks at ', FORMAT('%.2f', COALESCE(pub.roas_1d, 0)), 'x — under the ',
      FORMAT('%.2f', lv.veto_raise_roas), 'x raise bar at real volume (>',
      CAST(lv.veto_clk1 AS STRING), ' clicks). ',
      -- v27.76 Task 4.9: a 0.00x day only vetoes when the zero is SURPRISING — name the expectation
      IF(COALESCE(pub.roas_1d, 0) = 0,
         CONCAT('No sales landed at all, and its own 90d record (',
                CAST(COALESCE(pub.orders_90d, 0) AS STRING), ' orders on ',
                CAST(COALESCE(pub.clicks_90d, 0) AS STRING), ' clicks) expected about ',
                FORMAT('%.1f', pub.exp_ord_1d), " orders on yesterday's ",
                CAST(pub.clicks_1d AS STRING), ' clicks and got none — at/above ',
                FORMAT('%.1f', lv.veto_min_expected_orders),
                ' expected, a zero is a ~1-in-20 event and reads as evidence, not an ordinary day. '),
         'Sales DID land and were poor, so the reading is real evidence. '),
      'Complete-day windows decide moves; the filling day',
      ' may only hold one — the raise waits for the day to complete (was ', pub.action,
      ' to $', FORMAT('%.2f', pub.suggested_bid), ')')
    WHEN pub.veto_cut THEN CONCAT(
      'LAST-DAY VETO (Task 4.8): the standalone filling day read ', CAST(pub.clicks_1d AS STRING),
      ' clicks at ', FORMAT('%.2f', COALESCE(pub.roas_1d, 0)), 'x — at/above the ',
      FORMAT('%.2f', lv.veto_cut_roas), 'x cut bar at real volume (>',
      CAST(lv.veto_clk1 AS STRING), ' clicks). Complete-day windows decide moves; the filling day',
      ' may only hold one — the cut waits for the day to complete (was ', pub.action,
      ' to $', FORMAT('%.2f', pub.suggested_bid), ')')
    ELSE pub.reason END AS reason,
  CASE
    WHEN pub.veto_raise THEN CONCAT('yday: ', CAST(pub.clicks_1d AS STRING), 'c at ',
      FORMAT('%.2f', COALESCE(pub.roas_1d, 0)), 'x ⇒ raise waits a day')
    WHEN pub.veto_cut THEN CONCAT('yday: ', CAST(pub.clicks_1d AS STRING), 'c at ',
      FORMAT('%.2f', COALESCE(pub.roas_1d, 0)), 'x ⇒ cut waits a day')
    ELSE pub.reason_short END AS reason_short
),
  -- ── v27.98 (Ori 2026-08-21): THE VETO STOPS ERASING WHAT IT HELD ──────────────────────────
  -- Three ADDITIVE columns, NULL on every row the veto did not touch, identical in shape to the
  -- sibling V_OOB_KEYWORD. Nothing above changes: action still reads HOLD and suggested_bid is
  -- still NULL, so every existing consumer behaves exactly as it did yesterday.
  -- THE DEFECT THEY FIX: SP_SNAPSHOT_ENGINE_PROPOSALS takes a row on
  -- `action NOT IN ('HOLD', ...) AND suggested_bid IS NOT NULL`, and the veto breaks BOTH
  -- conjuncts, so a vetoed row vanished from FACT_ENGINE_PROPOSALS together with its reason —
  -- the one suppression in the engine that ERASES rather than LABELS, against the doctrine
  -- SP_ENGINE_PREFLIGHT states for the holdout arm ("block the export, never the judgement").
  -- held_bid is deliberately NOT suggested_bid: a value in suggested_bid is an instruction to
  -- Amazon, and a held row must be unable to become one no matter which consumer reads it.
  -- hold_source names the ARM: the cut arm is strong evidence (an unfinished day already at/above
  -- the cut bar can only rise as attribution accrues), the raise arm is weak (46% of at-volume
  -- rows read exactly 0.00x on a filling day) — an audit that cannot tell them apart cannot judge
  -- the veto. It also distinguishes a veto hold from a collision / claim / holdout exclusion
  -- downstream, the way is_holdout already does.
  IF(pub.veto_raise OR pub.veto_cut, pub.action,        CAST(NULL AS STRING))  AS held_action,
  IF(pub.veto_raise OR pub.veto_cut, pub.suggested_bid, CAST(NULL AS FLOAT64)) AS held_bid,
  CASE WHEN pub.veto_raise THEN 'LAST_DAY_VETO_RAISE'
       WHEN pub.veto_cut   THEN 'LAST_DAY_VETO_CUT'
       ELSE CAST(NULL AS STRING) END AS hold_source
FROM (
  SELECT p0.*,
    -- the two veto booleans, computed ONCE — every transformed column reads these, never a re-derivation
    -- v27.76 Task 4.9 — THE EXPECTED-ORDERS GATE, raise arm only:
    --   roas_1d != 0  ⇒ sales landed and were poor: real evidence, veto exactly as v27.75 did.
    --   roas_1d = 0/NULL ⇒ ambiguous ("no sales" vs "not attributed yet" — at age 1 we see ~85% of a
    --   day's spend but only ~69% of its sales). Veto ONLY when the zero is genuinely SURPRISING:
    --   exp_ord_1d >= veto_min_expected_orders. P(0 orders | 3 expected) ≈ 5%, so >= 3 means a zero
    --   here is a 1-in-20 event, not a Tuesday. No rate / no orders in the window ⇒ exp_ord_1d = 0 ⇒
    --   the veto does NOT fire: no history = no surprise = no block. The veto may only block when it
    --   HAS evidence; whether a never-converting keyword deserves a raise is the complete-day
    --   ladders' job (and the zero-sale floor's), never the veto's.
    COALESCE(p0.suggested_bid > p0.current_bid AND p0.clicks_1d > lv.veto_clk1
             AND COALESCE(p0.roas_1d, 0) < lv.veto_raise_roas
             AND (COALESCE(p0.roas_1d, 0) != 0
                  OR p0.exp_ord_1d >= lv.veto_min_expected_orders), FALSE) AS veto_raise,
    -- CUT ARM UNTOUCHED (v27.75 verbatim): missing sales can only make a day look WORSE, so a fresh
    -- day already at/above 1.20x is conservative proof — the gate has nothing to correct here.
    COALESCE(p0.suggested_bid < p0.current_bid AND p0.clicks_1d > lv.veto_clk1
             AND p0.roas_1d >= lv.veto_cut_roas, FALSE) AS veto_cut
  FROM (
    -- v27.76 Task 4.9: expected orders on the filling day = yesterday's clicks × the keyword's OWN
    -- complete-day order rate (90d, ends wm-1). ONE definition — the boolean above and the reason
    -- text below both read this column, so the gate and its explanation cannot drift. Internal
    -- (EXCEPT-ed out of the published schema, like bid_hold / bud_hold / bid_floor).
    SELECT v.*,
      COALESCE(v.clicks_1d * SAFE_DIVIDE(v.orders_90d, NULLIF(v.clicks_90d, 0)), 0) AS exp_ord_1d
    FROM (
-- ── Phase 6 Task 3 (WEEKLY_RUN_UX.md): the 5-SECOND WHY ──────────────────────────────────────
-- TRIGGER — EVIDENCE ⇒ MOVE, ≤ ~80 chars, computed HERE as a pure function of the PUBLISHED row
-- (final action + published numbers) — a thin wrapper, deliberately NOT a fourth predicate
-- ladder: it cannot drift from what the row already says. NULL on non-actionable rows (nothing
-- to accept there). The full paragraph stays in the reason column; panels show short + tooltip.
SELECT pub.*,
  CASE
    WHEN pub.suggested_bid IS NULL THEN CAST(NULL AS STRING)
    -- explanation audit 2026-08-16: every short = evidence numbers + move in plain words.
    -- Banned: 'wnd' (name the days), bare 'settled'/'seat'/'anchored', rule-names-as-reasons.
    WHEN pub.action = 'PARK' THEN CONCAT(
      'test done: ', CAST(CAST(COALESCE(pub.clicks_w, 0) AS INT64) AS STRING), ' clicks, $',
      FORMAT('%.2f', COALESCE(pub.spend_w, 0)), ' — no profit ⇒ park bid at $',
      FORMAT('%.2f', pub.suggested_bid))
    WHEN pub.action = 'CUT_TO_BREAKEVEN' THEN CONCAT(
      CAST(CAST(COALESCE(pub.clicks_w, 0) AS INT64) AS STRING), ' clicks at ',
      FORMAT('%.2f', COALESCE(pub.roas_w, 0)), 'x last ', CAST(pub.w_days AS STRING),
      'd (under 1.0) ⇒ lower bid to $', FORMAT('%.2f', pub.suggested_bid))
    WHEN pub.action IN ('CUT_TO_TARGET', 'EASE_TO_TARGET', 'RESEARCH_EASE', 'AUTO_TRIM', 'AUTO_BRAKE') THEN CONCAT(
      CAST(CAST(COALESCE(pub.clicks_w, 0) AS INT64) AS STRING), ' clicks at ',
      FORMAT('%.2f', COALESCE(pub.roas_w, 0)), 'x last ', CAST(pub.w_days AS STRING),
      'd ⇒ trim bid to $', FORMAT('%.2f', pub.suggested_bid))
    WHEN pub.action = 'AUTO_DAY_TRIM' THEN CONCAT(
      'no profit yday or day before (', CAST(COALESCE(pub.clicks_1d, 0) AS STRING), '+',
      CAST(COALESCE(pub.clicks_prev2, 0) AS STRING), ' clicks) ⇒ trim bid to $',
      FORMAT('%.2f', pub.suggested_bid))
    -- NUDGE_UP on a silent keyword gets its own sentence; else it reads as a raise below.
    -- v27.98: silence is the three COMPLETE days, matching the gate — the filling day alone
    -- said "0 clicks" about keywords that had clicked every day of the preceding week.
    WHEN pub.action = 'NUDGE_UP' AND COALESCE(pub.clicks_3d, 0) = 0 THEN CONCAT(
      '0 clicks over the last 3 complete days at $', FORMAT('%.2f', COALESCE(pub.current_bid, 0)),
      ' ⇒ nudge bid to $', FORMAT('%.2f', pub.suggested_bid), ' so the windows can refresh')
    WHEN pub.action IN ('RAISE_TO_TARGET', 'NUDGE_UP', 'VOLUME_LIFT', 'AUTO_RAISE', 'AUTO_DAY_RAISE', 'KEEP', 'PACE_RAISE') THEN CONCAT(
      CAST(CAST(COALESCE(pub.clicks_w, 0) AS INT64) AS STRING), ' clicks at ',
      FORMAT('%.2f', COALESCE(pub.roas_w, 0)), 'x last ', CAST(pub.w_days AS STRING),
      'd ⇒ raise bid to $', FORMAT('%.2f', pub.suggested_bid),
      IF(pub.target_cpc IS NOT NULL, CONCAT(' (target $', FORMAT('%.2f', pub.target_cpc), ')'), ''))
    WHEN pub.action = 'PROBE_ADJUST' THEN CONCAT(
      'test stalled: ', CAST(COALESCE(pub.clicks_1d, 0) AS STRING), ' clicks yday at $',
      FORMAT('%.2f', COALESCE(pub.current_bid, 0)), ' ⇒ ',
      IF(pub.suggested_bid > COALESCE(pub.current_bid, 0), 'lift', 'step'), ' to $',
      FORMAT('%.2f', pub.suggested_bid), ' (verdict at 20 clicks)')
    WHEN pub.action = 'PROBE_START' THEN CONCAT(
      'new test: bid $', FORMAT('%.2f', COALESCE(pub.current_bid, 0)), '→$',
      FORMAT('%.2f', pub.suggested_bid), ' — judged after 20 clicks')
    WHEN pub.action = 'WAKE_STEP' THEN CONCAT(
      'wake bought ', CAST(CAST(COALESCE(pub.wake_clicks, 0) AS INT64) AS STRING),
      ' clicks ⇒ step bid to $', FORMAT('%.2f', pub.suggested_bid))
    WHEN pub.action = 'ACTIVATE_REVIVE' THEN CONCAT(
      '90d record earns it back ⇒ un-park at $', FORMAT('%.2f', pub.suggested_bid))
    ELSE CONCAT(LOWER(REPLACE(pub.action, '_', ' ')), ' ⇒ $', FORMAT('%.2f', pub.suggested_bid))
  END AS reason_short
FROM (
WITH season AS (
  -- v27.50 (Ori 2026-08-12): the v27.49 gate PREDICATE moved to V_SEASON_PEAK_GATE (one row per
  -- occurrence active today), which is now its single definition — the predicate itself is
  -- unchanged (DIM_US_HOLIDAYS, categories gift_season/prime_event/back_to_school/seasonal,
  -- window boost_start..COALESCE(cooldown_end, holiday_date+3)). V_PEAK_WINDOW_RULE reads the
  -- same view, so the gate and the occurrence resolver cannot drift apart. Nothing about
  -- low_cap, the exploration allowance, probe slots, the budget floor or the CPC band changed.
  -- This CTE is expanded ~30 times below, so it must stay a single cheap scan — do not point it
  -- at V_PEAK_WINDOW_RULE (measured: exceeds BigQuery's planner, see the SOP).
  SELECT COUNT(*) > 0 AS in_peak FROM `onyga-482313.OI.V_SEASON_PEAK_GATE`
),
-- v27.50 ORI'S RULE — the judged window W is EVIDENCE-GATED, not hard-coded.
--   was: IF(in_peak, 3, 7)
--   now: V_PEAK_WINDOW_RULE.w_days = 7 off peak; in peak 3 by DEFAULT, and 7 ONLY for an
--        occurrence type where the same occurrence in a prior year was MEASURED to produce
--        better decisions at 7 than at 3 (DE_PEAK_WINDOW_OVERRIDE carries the proof).
--   Burden of proof is on the SLOWER window: no / thin / ambiguous / conflicting evidence = 3.
--   Granted 2026-08-12: XMAS_EARLY, XMAS_PEAK, EASTER -> 7. Everything else (incl. BTS, the live
--   season) stays 3. Re-measured yearly by updating a ROW, never this SQL.
--   Spec: architecture/PEAK_WINDOW_RULE.md
cap AS (SELECT in_peak, IF(in_peak, 30.0, 20.0) AS low_cap, w_days
        FROM `onyga-482313.OI.V_PEAK_WINDOW_RULE`),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
camps AS (
  SELECT c.campaign_id, c.campaign_name, c.daily_budget AS budget,
    LOWER(c.campaign_name) LIKE '%brand defense%' AS is_defense,
    -- v9 (Ori 2026-08-02): seasonal campaigns get their own Weekly Run home — name-based like
    -- is_defense ('prime'/'season' deliberately not matched, too ambiguous)
    REGEXP_CONTAINS(LOWER(c.campaign_name), r'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday') AS is_seasonal,
    -- RESEARCH MODE (Ori 2026-08-02): Hunter/Discovery campaigns are term-harvesting antennae —
    -- losers glide low instead of parking; winner terms without a keyword suggest ADD_KEYWORD
    REGEXP_CONTAINS(LOWER(c.campaign_name), r'hunter|discovery|research') AS is_research,
    -- v19: is the campaign's OWN season running right now (pre-season start -> cooldown end)?
    ah.holiday_name IS NOT NULL AS season_active
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c
  LEFT JOIN (SELECT DISTINCT holiday_name FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
             WHERE CURRENT_DATE('America/New_York') BETWEEN pre_season_start AND COALESCE(cooldown_end, holiday_date)) ah
    ON ah.holiday_name = CASE
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'christmas|xmas|santa|advent') THEN 'Christmas'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'valentine') THEN "Valentine's Day"
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'easter') THEN 'Easter'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'halloween') THEN 'Halloween'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'thanksgiving') THEN 'Thanksgiving'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'black friday|bfcm') THEN 'Black Friday'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'cyber monday') THEN 'Cyber Monday'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'back to school') THEN 'Back to School'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'mother.?s day') THEN "Mother's Day"
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'father.?s day') THEN "Father's Day"
    END, cap k
  -- v4 (Ori 2026-08-01): ANY budget — the Portfolio absorbs the launch controller; low-budget
  -- healthy campaigns run the same seat mechanism (slots = budget/$4). OOB owns them while dark.
  WHERE c.campaign_type = 'SP' AND c.campaign_state = 'ENABLED'
    AND c.serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET')
),
-- window W performance per (campaign, target). GP = the STORED FACT_AMAZON_ADS.GROSS_PROFIT
-- column — see THE GP RULE in the header.
kwW AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting,
    -- v27.74: complete days (Task 4.7) — ends wm-1
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL k.w_days DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_clicks, 0)) clk_w,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL k.w_days DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_cost, 0)) sp_w,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL k.w_days DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_orders, 0)) ord_w,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL k.w_days DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.GROSS_PROFIT, 0)) gp_w,
    SUM(IF(a.date = (SELECT d FROM wm), a.Ads_clicks, 0)) clk1,
    SUM(IF(a.date = (SELECT d FROM wm), a.Ads_cost, 0)) sp1,
    SUM(IF(a.date = (SELECT d FROM wm), a.GROSS_PROFIT, 0)) gp1,
    -- AUTO-section peak windows (Ori 2026-08-02): last 3d + day 4-14
    -- v27.74: complete days (Task 4.7) — 3d ends wm-1; 4-14 band shifts with it (wm-14..wm-4)
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_clicks, 0)) clk3,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_cost, 0)) sp3,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.GROSS_PROFIT, 0)) gp3,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_orders, 0)) ord3,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 14 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 4 DAY), a.Ads_clicks, 0)) clk4_14,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 14 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 4 DAY), a.Ads_cost, 0)) sp4_14,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 14 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 4 DAY), a.GROSS_PROFIT, 0)) gp4_14,
    -- prev-2d (the 2 days before the anchor) — the OOB-format windows for the low-budget tiers
    SUM(IF(a.date < (SELECT d FROM wm) AND a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY), a.Ads_clicks, 0)) clk2,
    SUM(IF(a.date < (SELECT d FROM wm) AND a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY), a.Ads_cost, 0)) sp2,
    SUM(IF(a.date < (SELECT d FROM wm) AND a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 2 DAY), a.GROSS_PROFIT, 0)) gp2,
    -- panel windows (Ori 2026-08-01: 'last 7 days' + 'prev 21 days, day 8 till 28')
    -- v27.74: complete days (Task 4.7) — 7d ends wm-1; 8-28 settled leg untouched (settle discipline)
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_clicks, 0)) clk7,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.Ads_cost, 0)) sp7,
    SUM(IF(a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY), a.GROSS_PROFIT, 0)) gp7,
    SUM(IF(a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY), a.Ads_clicks, 0)) clk8_28,
    SUM(IF(a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY), a.Ads_cost, 0)) sp8_28,
    SUM(IF(a.date <= DATE_SUB((SELECT d FROM wm), INTERVAL 7 DAY), a.GROSS_PROFIT, 0)) gp8_28
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camps c ON c.campaign_id = CAST(a.campaign_id AS STRING)
  CROSS JOIN cap k
  WHERE a.date > DATE_SUB((SELECT d FROM wm), INTERVAL 28 DAY)
  GROUP BY 1, 2
),
-- full target list (idle keywords included — the candidate pool), ids + current bid
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
-- probe episodes: last INCREASE_BID per keyword (change log), evidence AFTER the upload date
lastinc AS (
  SELECT keyword_id, MAX(DATE(applied_at)) AS inc_date,
         ARRAY_AGG(new_bid ORDER BY applied_at DESC LIMIT 1)[OFFSET(0)] AS probe_bid
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action = 'INCREASE_BID' AND keyword_id IS NOT NULL AND keyword_id != ''
  GROUP BY 1
),
episode AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting,
    SUM(a.Ads_clicks) ep_clk, SUM(a.Ads_cost) ep_sp, SUM(a.Ads_orders) ep_ord,
    SUM(a.GROSS_PROFIT) ep_gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camps c ON c.campaign_id = CAST(a.campaign_id AS STRING)
  JOIN td ON td.campaign_id = CAST(a.campaign_id AS STRING) AND td.target_text = a.targeting
  JOIN lastinc li ON li.keyword_id = td.keyword_id
  WHERE a.date > li.inc_date
  GROUP BY 1, 2
),
-- target CPC (probe entry anchor): LY same-28d-last-year else band (keywords only)
ly AS (
  -- ly_cpc (the personal target anchor): >= 10 clicks in the LY same-28d window for quality.
  -- ly_ord + ly_year_ord feed the SEASONAL CONCENTRATION test (Ori 2026-08-02: one LY order
  -- can't make a season — birthday keywords sell year-round): the window's share of the LY
  -- YEAR's orders must be >= 25% (uniform = ~8%) with >= 2 window orders.
  SELECT LOWER(TRIM(targeting)) AS kw,
         IF(SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_clicks, 0)) >= 10,
            ROUND(SAFE_DIVIDE(SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_cost, 0)),
                              SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_clicks, 0))), 2), NULL) AS ly_cpc,
         SUM(IF(date >= DATE_SUB((SELECT d FROM wm), INTERVAL 391 DAY), Ads_clicks, 0)) AS ly_clk,
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
-- v27.39 (2026-08-07): campaign→family now reads THE canonical source, V_DIM_CAMPAIGN_FAMILY
-- (manual DE_CAMPAIGN_FAMILY override > dominant-by-lifetime-spend ASIN chain, which itself
-- prefers the behavioral most_advertised_asin_impressions and falls back to the name-parsed ASIN).
-- The old body resolved family from ASIN_BY_CAMPAIGN_NAME alone with an ANY_VALUE tie-break —
-- name-parsing, arbitrarily broken — and mis-filed 134 of 650 rows onto the WRONG family's CPC
-- band: every BUNNY-*, BALL-* and ME/MINT-SP campaign read as 'Lollibox', and BRAND-STORE/BROAD
-- (Me,Box,Bottle) read as 'Bottle' instead of 'LolliME', because their name-parsed ASIN lands on
-- another family's listing. BUNNY-VIDEO/BROAD (Hunter) is the manual case: the chain says
-- Lollibox, DE_CAMPAIGN_FAMILY says Bunny, and a deliberate human assignment wins by design.
-- Feeds `band` (SP join below) AND `sb_band`/`band` (SB join further down) — one CTE, both arms.
-- No legacy COALESCE backstop: the canonical asin_chain already subsumes the name-parsed path
-- (measured on this view's population: gained 0 rows, lost 0 rows, changed 134), so a fallback
-- could only resurrect the wrong Lollibox answer it exists to replace.
-- SCOPE NOTE — this is NOT the cause of the 40 rows that carry no target_cpc; measured, it
-- recovers 0 of them. 34 of those 40 (20 Bottle, 12 Fresh SP, 2 Fresh SB) resolve a family
-- perfectly well under BOTH the old and new path, and go NULL because DE_PRODUCT_STRATEGY_PROFILE
-- holds no CONCLUSIVE cell at match_type PRODUCT or AUTO for Bottle/Fresh (only BROAD/EXACT/
-- PHRASE exist). The other 6 are MINT-VIDEO/EXACT (Back to School), an SB campaign with no
-- delivery yet, which is NULL in the canonical view too. Closing the 40 is a band-coverage job.
camp_parent AS (
  SELECT campaign_id AS cid, parent_name
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_FAMILY`
  WHERE parent_name IS NOT NULL
),
band AS (
  SELECT parent_name, UPPER(match_type) AS match_type, ROUND(AVG(cpc_target), 2) AS cpc_target
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`, season s
  WHERE enabled AND cpc_target IS NOT NULL AND confidence = 'CONCLUSIVE'
    AND COALESCE(campaign_type, 'ALL') = 'ALL' AND COALESCE(ad_format, 'ALL') = 'ALL'
    AND season = IF(s.in_peak, 'PEAK', 'OFF')
  GROUP BY 1, 2
),
-- 90d evidence per target (tested-loser bar + seat ranking). GP = FACT.GROSS_PROFIT (THE GP RULE).
t90 AS (
  SELECT CAST(a.campaign_id AS STRING) cid, a.targeting, SUM(a.Ads_clicks) clk90, SUM(a.Ads_orders) ord90,
    ROUND(SAFE_DIVIDE(SUM(a.GROSS_PROFIT),
                      NULLIF(SUM(a.Ads_cost), 0)), 2) AS roas90
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camps c ON c.campaign_id = CAST(a.campaign_id AS STRING)
  -- v27.74: complete days (Task 4.7) — ends wm-1
  WHERE a.date BETWEEN DATE_SUB((SELECT d FROM wm), INTERVAL 90 DAY) AND DATE_SUB((SELECT d FROM wm), INTERVAL 1 DAY)
  GROUP BY 1, 2
),
-- dark % on the SP anchor day (event log, same construction as the SB arm below) — the probe gate (v3)
sp_h AS (
  SELECT campaign_id cid, DATETIME(date, 'America/Los_Angeles') ts, serving_status
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`
  WHERE campaign_type = 'SP' AND DATE(date, 'America/Los_Angeles') = (SELECT d FROM wm)
    AND campaign_id IN (SELECT campaign_id FROM camps)
),
sp_ev AS (
  SELECT cid, ts, serving_status FROM sp_h
  UNION ALL SELECT DISTINCT cid, DATETIME((SELECT d FROM wm), TIME '00:00:00'), 'CAMPAIGN_STATUS_ENABLED' FROM sp_h
),
sp_sqd AS (SELECT cid, ts, serving_status, LEAD(ts) OVER (PARTITION BY cid ORDER BY ts) nxt FROM sp_ev),
sp_dark AS (
  SELECT cid, SUM(IF(serving_status = 'CAMPAIGN_OUT_OF_BUDGET',
    DATETIME_DIFF(COALESCE(nxt, DATETIME(DATE_ADD((SELECT d FROM wm), INTERVAL 1 DAY))), ts, MINUTE), 0)) / 1440.0 AS pd
  FROM sp_sqd GROUP BY 1
),
base AS (
  SELECT c.campaign_id, c.campaign_name, c.budget, c.is_defense, c.is_seasonal, c.season_active, c.is_research,
    td.target_text, td.keyword_id, td.ad_group_id, td.match_type,
    LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements') AS is_auto,
    LOWER(td.target_text) LIKE 'asin%' AS is_pt,
    COALESCE(td.keyword_bid, agb.default_bid) AS current_bid,
    -- LOW-BUDGET REBASE (Ori 2026-08-04, v27.7: "all low budget types time window is based on
    -- last day and 2-3 days INCLUDING the decision logic"): for low-budget campaigns W IS 3 DAYS
    -- — class, allowance, seat economics and every downstream decision inherit it.
    IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense, COALESCE(w.clk3, 0), COALESCE(w.clk_w, 0)) clk_w,
    IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense, COALESCE(w.sp3, 0), COALESCE(w.sp_w, 0)) sp_w,
    IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense, COALESCE(w.ord3, 0), COALESCE(w.ord_w, 0)) ord_w,
    ROUND(IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense,
             SAFE_DIVIDE(w.gp3, NULLIF(w.sp3, 0)), SAFE_DIVIDE(w.gp_w, NULLIF(w.sp_w, 0))), 2) AS roas_w,
    COALESCE(w.clk1, 0) clk1,
    COALESCE(w.sp1, 0) sp1, COALESCE(w.gp1, 0) gp1,
    IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense, COALESCE(w.gp3, 0), COALESCE(w.gp_w, 0)) gp_w_raw,
    COALESCE(w.clk2, 0) clk2, COALESCE(w.sp2, 0) sp2, COALESCE(w.gp2, 0) gp2,
    COALESCE(w.clk3, 0) clk3, COALESCE(w.sp3, 0) sp3, COALESCE(w.gp3, 0) gp3,
    COALESCE(w.clk4_14, 0) clk4_14, COALESCE(w.sp4_14, 0) sp4_14, COALESCE(w.gp4_14, 0) gp4_14,
    COALESCE(w.clk7, 0) clk7, ROUND(SAFE_DIVIDE(w.gp7, NULLIF(w.sp7, 0)), 2) AS roas7,
    COALESCE(w.sp7, 0) sp7, COALESCE(w.gp7, 0) gp7,
    COALESCE(w.clk8_28, 0) clk8_28, ROUND(SAFE_DIVIDE(w.gp8_28, NULLIF(w.sp8_28, 0)), 2) AS roas8_28,
    COALESCE(w.sp8_28, 0) sp8_28, COALESCE(w.gp8_28, 0) gp8_28,
    COALESCE(n90.clk90, 0) clk90, COALESCE(n90.ord90, 0) ord90, n90.roas90,
    li.inc_date, li.probe_bid,
    COALESCE(ep.ep_clk, 0) ep_clk, ROUND(SAFE_DIVIDE(ep.ep_gp, NULLIF(ep.ep_sp, 0)), 2) AS ep_roas,
    COALESCE(ep.ep_ord, 0) ep_ord,
    ROUND(COALESCE(IF(LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements')
                      OR LOWER(td.target_text) LIKE 'asin%', NULL, l.ly_cpc), bd.cpc_target), 2) AS tcpc,
    COALESCE(l.ly_clk, 0) AS ly_clk,
    -- SEASONAL REVIVAL (Ori 2026-08-01): it SOLD in this same 28-day window last year — its
    -- season is arriving; exempt from the tested-loser bar and jump the seat queue
    COALESCE(l.ly_ord, 0) >= 2 AND SAFE_DIVIDE(l.ly_ord, NULLIF(l.ly_year_ord, 0)) >= 0.25
      AND l.ly_first <= DATE_SUB((SELECT d FROM wm), INTERVAL 421 DAY)
      AND NOT (LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements')
               OR LOWER(td.target_text) LIKE 'asin%') AS seasonal_now,
    COALESCE(dk.pd, 0) > 0.10 AS capped,
    ROUND(COALESCE(dk.pd, 0) * 100) AS pct_dark,
    -- v27.48: the park reverdict feeds the seat/candidate ORDERING here (the output-layer
    -- branches join FACT_PARK_REVERDICT independently — see the final SELECT)
    COALESCE(rv.reverdict = 'REVIVE', FALSE) AS is_revive,
    -- v27.68: REDUNDANT (Task 2.4) = CONFIRM_PARK with the sibling named — same engine behavior
    COALESCE(rv.reverdict IN ('CONFIRM_PARK', 'REDUNDANT', 'SIBLING_REVIVE'), FALSE) AS confirm_park,
    -- ^ v27.71 (review, CRITICAL): SIBLING_REVIVE added — hand-queue ONLY; without this it walked the generic ACTIVATE door
    -- v27.48.2: settled-record ordering keys from the guard snapshot (table only — plan-cost
    -- doctrine); the output-layer guards join the snapshot independently at the wrapper.
    COALESCE(gd.settled_winner, FALSE) AS g_settled_winner,
    COALESCE(gd.record_loser, FALSE) AS g_record_loser,
    -- v27.53 ITEM 3 — THE CUT GATE, SCALED TO THE WINDOW IT JUDGES. The condemnation branches
    -- fired at a bar chosen by TIER and SEASON (13 low-tier/peak, 30 otherwise) while the window
    -- they measure is chosen independently (3 days low-tier, else V_PEAK_WINDOW_RULE.w_days). The
    -- two were never wired together, so changing the window silently changed how OFTEN the engine
    -- condemns, on top of what it sees — and V_PEAK_WINDOW_RULE can move w_days without touching
    -- the bar. Proven on the 2026-08-12 backtest (n = 11,019): hold the gate constant and every
    -- apparent 7-day advantage disappears — zero peaks favour 7 days and the dollars flip to the
    -- short window by +$6,876. So the bar is now ONE definition, anchored at the historical
    -- 13-clicks-per-7-days density and scaled by the row's OWN effective window:
    --     eff_days = 3 for low-budget non-defense rows (their W is rebased to 3d above), else w_days
    --     cut_gate = max(4, ceil(13 x eff_days / 7))   ->   6 at 3 days, 13 at 7 days
    -- The floor of 4 keeps single-click noise out of a very short window. Computed here so the
    -- action / bid / reason ladders share it and cannot drift the way v27.30-v27.32 did.
    GREATEST(4, CAST(CEIL(13.0 * IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense,
                                    3, (SELECT w_days FROM cap)) / 7.0) AS INT64)) AS cut_gate,
    -- v27.53 ITEM 7 — the $1.00 wake step-down, from the guard snapshot
    COALESCE(gd.wake_due, FALSE) AS g_wake_due, gd.wake_step_bid AS g_wake_step_bid,
    COALESCE(gd.wake_clk, 0) AS g_wake_clk, gd.wake_date AS g_wake_date
  FROM camps c
  JOIN td ON td.campaign_id = c.campaign_id
  LEFT JOIN agb ON agb.ad_group_id = td.ad_group_id
  LEFT JOIN kwW w ON w.cid = c.campaign_id AND w.targeting = td.target_text
  LEFT JOIN lastinc li ON li.keyword_id = td.keyword_id
  LEFT JOIN episode ep ON ep.cid = c.campaign_id AND ep.targeting = td.target_text
  LEFT JOIN ly l ON l.kw = LOWER(TRIM(td.target_text))
  LEFT JOIN camp_parent cp ON cp.cid = c.campaign_id
  LEFT JOIN band bd ON bd.parent_name = cp.parent_name
    AND bd.match_type = CASE WHEN LOWER(td.target_text) LIKE 'asin%' THEN 'PRODUCT'
                             WHEN LOWER(td.target_text) IN ('close-match','loose-match','substitutes','complements') THEN 'AUTO'
                             ELSE UPPER(COALESCE(td.match_type, '')) END
  LEFT JOIN sp_dark dk ON dk.cid = c.campaign_id
  LEFT JOIN t90 n90 ON n90.cid = c.campaign_id AND n90.targeting = td.target_text
  LEFT JOIN `onyga-482313.OI.FACT_PARK_REVERDICT` rv
    ON rv.campaign_id = c.campaign_id AND rv.keyword_id = td.keyword_id
  LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_GUARD` gd
    ON gd.campaign_id = c.campaign_id AND gd.keyword_id = td.keyword_id
),
classed AS (
  SELECT b.*,
    CASE
      WHEN b.ord_w >= 1 AND COALESCE(b.roas_w, 0) >= 1.1 THEN 'WINNER'
      WHEN b.ord_w >= 1 AND COALESCE(b.roas_w, 0) >= 0.7 THEN 'MARGINAL'
      WHEN b.clk_w > 0 THEN 'LOSER'
      ELSE 'IDLE'
    END AS class,
    -- active probe: raised within 14d and still under 20 episode clicks
    -- AUTOS EXCLUDED (v24.1): a raise on an auto clause is just a raise, not an experiment
    (b.inc_date IS NOT NULL AND NOT b.is_auto
     AND b.inc_date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
     AND b.ep_clk < 20) AS probing,
    -- probe just finished its 20 clicks — verdict due
    (b.inc_date IS NOT NULL AND NOT b.is_auto
     AND b.inc_date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
     AND b.ep_clk >= 20) AS probe_done
  FROM base b
),
agg AS (
  SELECT c.*,
    SUM(c.sp_w) OVER (PARTITION BY c.campaign_id) AS camp_sp,
    SUM(c.sp1) OVER (PARTITION BY c.campaign_id) AS camp_sp1,
    ROUND(SAFE_DIVIDE(SUM(c.gp1) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp1) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_1d,
    CAST(SUM(c.clk1) OVER (PARTITION BY c.campaign_id) AS INT64) AS camp_clk1,
    CAST(SUM(c.clk2) OVER (PARTITION BY c.campaign_id) AS INT64) AS camp_clk2,
    ROUND(SAFE_DIVIDE(SUM(c.gp2) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp2) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_prev2,
    LOGICAL_OR(c.is_auto) OVER (PARTITION BY c.campaign_id) AS is_auto_campaign,
    CAST(SUM(c.clk3) OVER (PARTITION BY c.campaign_id) AS INT64) AS camp_clk3,
    ROUND(SAFE_DIVIDE(SUM(c.gp3) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp3) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_3d,
    CAST(SUM(c.clk4_14) OVER (PARTITION BY c.campaign_id) AS INT64) AS camp_clk4_14,
    ROUND(SAFE_DIVIDE(SUM(c.gp4_14) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp4_14) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_4_14,
    ROUND(SAFE_DIVIDE(SUM(c.gp_w_raw) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp_w) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_w,
    SUM(c.clk7) OVER (PARTITION BY c.campaign_id) AS camp_clk7,
    ROUND(SAFE_DIVIDE(SUM(c.gp7) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp7) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas7,
    SUM(c.clk8_28) OVER (PARTITION BY c.campaign_id) AS camp_clk8_28,
    ROUND(SAFE_DIVIDE(SUM(c.gp8_28) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp8_28) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas8_28,
    SUM(IF(c.class = 'LOSER', c.sp_w, 0)) OVER (PARTITION BY c.campaign_id) AS loser_sp,
    SUM(IF(c.probing, 1, 0)) OVER (PARTITION BY c.campaign_id) AS active_probes,
    -- winners' avg CPC — the probe entry fallback anchor
    ROUND(SAFE_DIVIDE(SUM(IF(c.class IN ('WINNER','MARGINAL'), c.sp_w, 0)) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(IF(c.class IN ('WINNER','MARGINAL'), c.clk_w, 0)) OVER (PARTITION BY c.campaign_id), 0)), 2) AS win_cpc,
    -- keep-allowance ranking: best losers first (roas desc), cumulative spend against the 20% pool
    SUM(IF(c.class = 'LOSER' AND NOT c.probing, c.sp_w, 0))
      OVER (PARTITION BY c.campaign_id ORDER BY IF(c.class = 'LOSER' AND NOT c.probing, COALESCE(c.roas_w, 0), 999) DESC, c.sp_w
            ROWS UNBOUNDED PRECEDING) AS loser_cum_sp,
    -- candidate rank for probe promotion: anchored first, then LY volume, then least-tested
    -- v27.48: CONFIRM_PARK rows sort last — a settled-verified loser must not burn a probe
    -- seat a live candidate needs (the output layer also blocks its promotion outright).
    ROW_NUMBER() OVER (PARTITION BY c.campaign_id
      -- v27.48.2: a scope-lifetime LOSER (record_loser) leaves the candidate pool — the loser
      -- path owns it, never a probe seat; settled-proven candidates rank first (Cause 2).
      ORDER BY IF(c.class = 'IDLE' AND NOT c.probing AND NOT c.probe_done AND NOT c.confirm_park AND NOT c.g_record_loser, 0, 1),
               IF(c.seasonal_now, 0, 1),
               IF(c.g_settled_winner, 0, 1),
               IF(c.tcpc IS NOT NULL, 0, 1), c.ly_clk DESC, c.clk_w ASC, c.target_text) AS cand_rank,
    -- SEAT MECHANISM (Ori 2026-08-01, Portfolio absorbs the launch controller): slots = budget/$4;
    -- seats to proven keywords (roas90/class) then mid-tests then anchored candidates; tested
    -- losers never seated; beyond-seat rows queue at $0.25 until a seat frees.
    -- COST-AWARE SEATS (Ori 2026-08-02, ME-SP/PT B2 case): the $4 seat assumes $1 clicks — a
    -- winner bidding $1.56 takes a $6.24 seat. Winners' bid premium above $1 (x 4 clicks) is
    -- subtracted from the budget before dividing; after a few sales the budget ladder raises
    -- the budget and the seats come back.
    GREATEST(1, CAST(ROUND(GREATEST(0, c.budget - SUM(IF(c.class = 'WINNER', GREATEST(0, 4 * (COALESCE(c.current_bid, 0) - 1)), 0)) OVER (PARTITION BY c.campaign_id)) / 4) AS INT64)) AS slots,
    ROW_NUMBER() OVER (PARTITION BY c.campaign_id ORDER BY
      -- v27.48: CONFIRM_PARK sinks with the tested losers (settled record is the verdict; the
      -- engine-window roas90 can flatter it)
      IF((c.clk90 >= 15 AND c.ord90 = 0 AND NOT c.probing AND NOT c.probe_done AND NOT c.seasonal_now) OR c.confirm_park, 1, 0),
      -- v27.48: a REVIVE verdict IS settled proof — joins the proven tier even when the
      -- engine-window roas90 (unsettled tail) understates it, and ranks above fresh unproven
      -- inside the tier (Cause 2: queues ranked fresh losers over proven winners)
      IF(c.class IN ('WINNER','MARGINAL') OR COALESCE(c.roas90, 0) >= 1.0 OR c.probing OR c.probe_done OR c.is_revive, 0, 1),
      IF(c.is_revive, 0, 1),
      -- v27.48.2: settled evidence outranks fresh unsettled inside the proven tier (Cause 2);
      -- part-1 revives stay on top (the is_revive key above), live window classes above both.
      IF(c.g_settled_winner, 0, 1),
      -- seasonal revival: sold in this window last year -> jumps the queue as its season arrives
      IF(c.seasonal_now, 0, 1),
      COALESCE(c.roas90, 0) DESC,
      IF(c.clk90 > 0, 0, 1),
      c.clk90 DESC,
      IF(c.tcpc IS NOT NULL, 0, 1),
      c.target_text) AS seat_rank
  FROM classed c
),
-- ═══════════ SB ARM (v2 2026-07-30) — same machinery on SB-native sources ═══════════
sb_camps AS (
  SELECT c.campaign_id, c.campaign_name, c.daily_budget AS budget,
    LOWER(c.campaign_name) LIKE '%brand defense%' AS is_defense,
    -- v9 (Ori 2026-08-02): seasonal campaigns get their own Weekly Run home — name-based like
    -- is_defense ('prime'/'season' deliberately not matched, too ambiguous)
    REGEXP_CONTAINS(LOWER(c.campaign_name), r'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday') AS is_seasonal,
    -- RESEARCH MODE (Ori 2026-08-02): Hunter/Discovery campaigns are term-harvesting antennae —
    -- losers glide low instead of parking; winner terms without a keyword suggest ADD_KEYWORD
    REGEXP_CONTAINS(LOWER(c.campaign_name), r'hunter|discovery|research') AS is_research,
    -- v19: is the campaign's OWN season running right now (pre-season start -> cooldown end)?
    ah.holiday_name IS NOT NULL AS season_active
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c
  LEFT JOIN (SELECT DISTINCT holiday_name FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
             WHERE CURRENT_DATE('America/New_York') BETWEEN pre_season_start AND COALESCE(cooldown_end, holiday_date)) ah
    ON ah.holiday_name = CASE
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'christmas|xmas|santa|advent') THEN 'Christmas'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'valentine') THEN "Valentine's Day"
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'easter') THEN 'Easter'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'halloween') THEN 'Halloween'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'thanksgiving') THEN 'Thanksgiving'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'black friday|bfcm') THEN 'Black Friday'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'cyber monday') THEN 'Cyber Monday'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'back to school') THEN 'Back to School'
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'mother.?s day') THEN "Mother's Day"
      WHEN REGEXP_CONTAINS(LOWER(c.campaign_name), r'father.?s day') THEN "Father's Day"
    END, cap k
  WHERE c.campaign_type = 'SB' AND c.campaign_state = 'ENABLED'
    AND c.serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET')
),
-- per-channel anchor: the SB reports' own watermark (FACT undercounts SB; reports refresh intraday,
-- so W and episode windows are bounded ABOVE at the anchor too — FACT only holds complete days)
sb_wm AS (SELECT LEAST(MAX(report_date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
          FROM `fivetran-hl.amazon_ads.sb_search_term_report`),
-- est. COGS ratio per campaign via its mapped ASIN (same method as V_SB_LAUNCH_TARGET — SB reports
-- carry no per-unit COGS, so net ROAS is estimated as sales × (1 − cost_ratio) ÷ spend)
-- v27.67 (Task 1.9): DETERMINISM FIX, the v27.46 pattern copied from V_OOB_KEYWORD's `prod` CTE.
-- The old ANY_VALUE(cost)/ANY_VALUE(price) over a per-campaign group let BigQuery pick cost and
-- price from DIFFERENT arbitrary ASINs per plan on multi-ASIN campaigns — the documented
-- roas-coin-flip class (fact_oi_any_value_pairing_nondeterminism; back-to-back pulls flipped
-- 0.89 vs 1.18 across a tier boundary when this bit OOB). The campaign's DOMINANT mapped ASIN
-- (most all-history ad spend, tie-break ASIN string) now supplies BOTH cost and price —
-- deterministic and coherently paired. Latent here (today's pulls agreed), fixed on principle:
-- latent ≠ absent.
sb_prod AS (
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
sb_ptlabel AS (   -- product-target label from the target report (the config mirror has no text)
  SELECT target_id, ANY_VALUE(targeting_text) txt
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  WHERE report_date >= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 30 DAY)
  GROUP BY 1
),
-- full target list from the minutes-fresh config mirrors (keywords ∪ product targets; SB has no
-- auto clauses) — idle keywords included, they are the probe candidate pool
sb_td AS (
  SELECT k.id AS keyword_id, CAST(k.campaign_id AS STRING) campaign_id, CAST(k.ad_group_id AS STRING) ad_group_id,
    k.keyword_text AS target_text, FALSE AS is_pt, k.match_type, k.bid AS keyword_bid
  FROM `fivetran-hl.amazon_ads.sb_keyword` k
  WHERE NOT k._fivetran_deleted AND k.state = 'enabled'
    AND CAST(k.campaign_id AS STRING) IN (SELECT campaign_id FROM sb_camps)
  UNION ALL
  SELECT pt.id, CAST(pt.campaign_id AS STRING), CAST(pt.ad_group_id AS STRING),
    COALESCE(l.txt, 'product target'), TRUE, 'TARGETING_EXPRESSION', pt.bid
  FROM `fivetran-hl.amazon_ads.sb_product_target` pt
  LEFT JOIN sb_ptlabel l ON l.target_id = pt.id
  WHERE NOT pt._fivetran_deleted AND pt.state = 'enabled'
    AND CAST(pt.campaign_id AS STRING) IN (SELECT campaign_id FROM sb_camps)
),
-- per-day performance: keyword arm from the search-term report (keyword_id grain) ∪ product arm
-- from the target report — NOT sb_keyword_report (dead since 2025-12-29)
sb_day AS (
  SELECT keyword_id AS target_id, report_date date, SUM(clicks) clk, SUM(cost) sp,
         SUM(attributed_sales_14_d) sales, SUM(attributed_conversions_14_d) ord
  FROM `fivetran-hl.amazon_ads.sb_search_term_report`
  GROUP BY 1, 2
  UNION ALL
  SELECT target_id, report_date, SUM(clicks), SUM(cost), SUM(attributed_sales_14_d), SUM(attributed_conversions_14_d)
  FROM `fivetran-hl.amazon_ads.sb_target_report`
  GROUP BY 1, 2
),
sb_kwW AS (
  SELECT t.keyword_id,
    -- v27.74: complete days (Task 4.7) — W/3d/4-14/7d end wm-1 (clk1 = filling day, 8-28 settled leg untouched)
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL k.w_days DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.clk, 0)) clk_w,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL k.w_days DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.sp, 0)) sp_w,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL k.w_days DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.ord, 0)) ord_w,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL k.w_days DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp_w,
    SUM(IF(d.date = (SELECT d FROM sb_wm), d.clk, 0)) clk1,
    SUM(IF(d.date = (SELECT d FROM sb_wm), d.sp, 0)) sp1,
    SUM(IF(d.date = (SELECT d FROM sb_wm), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp1,
    SUM(IF(d.date < (SELECT d FROM sb_wm) AND d.date >= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 2 DAY), d.clk, 0)) clk2,
    SUM(IF(d.date < (SELECT d FROM sb_wm) AND d.date >= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 2 DAY), d.sp, 0)) sp2,
    SUM(IF(d.date < (SELECT d FROM sb_wm) AND d.date >= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 2 DAY), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp2,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.clk, 0)) clk3,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.sp, 0)) sp3,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp3,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 3 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.ord, 0)) ord3,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 14 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 4 DAY), d.clk, 0)) clk4_14,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 14 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 4 DAY), d.sp, 0)) sp4_14,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 14 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 4 DAY), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp4_14,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.clk, 0)) clk7,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.sp, 0)) sp7,
    SUM(IF(d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp7,
    SUM(IF(d.date <= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY), d.clk, 0)) clk8_28,
    SUM(IF(d.date <= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY), d.sp, 0)) sp8_28,
    SUM(IF(d.date <= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 7 DAY), d.sales * (1 - COALESCE(pr.cost_ratio, 0)), 0)) gp8_28
  FROM sb_td t
  JOIN sb_day d ON d.target_id = t.keyword_id
  CROSS JOIN cap k
  LEFT JOIN sb_prod pr ON pr.cid = t.campaign_id
  WHERE d.date > DATE_SUB((SELECT d FROM sb_wm), INTERVAL 28 DAY)
    AND d.date <= (SELECT d FROM sb_wm)
  GROUP BY 1
),
sb_episode AS (
  SELECT t.keyword_id,
    SUM(d.clk) ep_clk, SUM(d.sp) ep_sp, SUM(d.ord) ep_ord,
    SUM(d.sales * (1 - COALESCE(pr.cost_ratio, 0))) ep_gp
  FROM sb_td t
  JOIN lastinc li ON li.keyword_id = t.keyword_id
  JOIN sb_day d ON d.target_id = t.keyword_id
  LEFT JOIN sb_prod pr ON pr.cid = t.campaign_id
  WHERE d.date > li.inc_date AND d.date <= (SELECT d FROM sb_wm)
  GROUP BY 1
),
sb_t90 AS (
  SELECT t.keyword_id, SUM(d.clk) clk90, SUM(d.ord) ord90,
    ROUND(SAFE_DIVIDE(SUM(d.sales * (1 - COALESCE(pr.cost_ratio, 0))), NULLIF(SUM(d.sp), 0)), 2) AS roas90
  FROM sb_td t
  JOIN sb_day d ON d.target_id = t.keyword_id
  LEFT JOIN sb_prod pr ON pr.cid = t.campaign_id
  -- v27.74: complete days (Task 4.7) — ends wm-1
  WHERE d.date BETWEEN DATE_SUB((SELECT d FROM sb_wm), INTERVAL 90 DAY) AND DATE_SUB((SELECT d FROM sb_wm), INTERVAL 1 DAY)
  GROUP BY 1
),
sb_adfmt AS (   -- ad-group → SB creative type (BRAND_VIDEO / PRODUCT_COLLECTION / …): the profile's
  -- ad_format grain. Canonical derivation lives in SP_LOAD_DIM_AD_GROUP — read the dimension.
  SELECT ad_group_id, ANY_VALUE(creative_type) creative_type
  FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current AND creative_type IS NOT NULL GROUP BY 1
),
sb_band AS (   -- FINE band cell: SB × ad_format × match (CONCLUSIVE); coarse ALL/ALL is the fallback
  SELECT parent_name, UPPER(ad_format) AS ad_format, UPPER(match_type) AS match_type,
         ROUND(AVG(cpc_target), 2) AS cpc_target
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`, season s
  WHERE enabled AND cpc_target IS NOT NULL AND confidence = 'CONCLUSIVE'
    AND campaign_type = 'SB' AND COALESCE(ad_format, 'NA') != 'ALL'
    AND season = IF(s.in_peak, 'PEAK', 'OFF')
  GROUP BY 1, 2, 3
),
-- dark % on the SB anchor day (event log, same construction as V_SB_LAUNCH_TARGET) — the probe gate
sb_h AS (
  SELECT campaign_id cid, DATETIME(date, 'America/Los_Angeles') ts, serving_status
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`
  WHERE campaign_type = 'SB' AND DATE(date, 'America/Los_Angeles') = (SELECT d FROM sb_wm)
    AND campaign_id IN (SELECT campaign_id FROM sb_camps)
),
sb_ev AS (
  SELECT cid, ts, serving_status FROM sb_h
  UNION ALL SELECT DISTINCT cid, DATETIME((SELECT d FROM sb_wm), TIME '00:00:00'), 'CAMPAIGN_STATUS_ENABLED' FROM sb_h
),
sb_sqd AS (SELECT cid, ts, serving_status, LEAD(ts) OVER (PARTITION BY cid ORDER BY ts) nxt FROM sb_ev),
sb_dark AS (
  SELECT cid, SUM(IF(serving_status = 'CAMPAIGN_OUT_OF_BUDGET',
    DATETIME_DIFF(COALESCE(nxt, DATETIME(DATE_ADD((SELECT d FROM sb_wm), INTERVAL 1 DAY))), ts, MINUTE), 0)) / 1440.0 AS pd
  FROM sb_sqd GROUP BY 1
),
sb_base AS (
  SELECT c.campaign_id, c.campaign_name, c.budget, c.is_defense, c.is_seasonal, c.season_active, c.is_research,
    t.target_text, t.keyword_id, t.ad_group_id, t.match_type,
    FALSE AS is_auto, t.is_pt,
    COALESCE(t.keyword_bid, agb.default_bid) AS current_bid,
    -- LOW-BUDGET REBASE (Ori 2026-08-04, v27.7: "all low budget types time window is based on
    -- last day and 2-3 days INCLUDING the decision logic"): for low-budget campaigns W IS 3 DAYS
    -- — class, allowance, seat economics and every downstream decision inherit it.
    IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense, COALESCE(w.clk3, 0), COALESCE(w.clk_w, 0)) clk_w,
    IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense, COALESCE(w.sp3, 0), COALESCE(w.sp_w, 0)) sp_w,
    IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense, COALESCE(w.ord3, 0), COALESCE(w.ord_w, 0)) ord_w,
    ROUND(IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense,
             SAFE_DIVIDE(w.gp3, NULLIF(w.sp3, 0)), SAFE_DIVIDE(w.gp_w, NULLIF(w.sp_w, 0))), 2) AS roas_w,
    COALESCE(w.clk1, 0) clk1,
    COALESCE(w.sp1, 0) sp1, COALESCE(w.gp1, 0) gp1,
    IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense, COALESCE(w.gp3, 0), COALESCE(w.gp_w, 0)) gp_w_raw,
    COALESCE(w.clk2, 0) clk2, COALESCE(w.sp2, 0) sp2, COALESCE(w.gp2, 0) gp2,
    COALESCE(w.clk3, 0) clk3, COALESCE(w.sp3, 0) sp3, COALESCE(w.gp3, 0) gp3,
    COALESCE(w.clk4_14, 0) clk4_14, COALESCE(w.sp4_14, 0) sp4_14, COALESCE(w.gp4_14, 0) gp4_14,
    COALESCE(w.clk7, 0) clk7, ROUND(SAFE_DIVIDE(w.gp7, NULLIF(w.sp7, 0)), 2) AS roas7,
    COALESCE(w.sp7, 0) sp7, COALESCE(w.gp7, 0) gp7,
    COALESCE(w.clk8_28, 0) clk8_28, ROUND(SAFE_DIVIDE(w.gp8_28, NULLIF(w.sp8_28, 0)), 2) AS roas8_28,
    COALESCE(w.sp8_28, 0) sp8_28, COALESCE(w.gp8_28, 0) gp8_28,
    COALESCE(n90.clk90, 0) clk90, COALESCE(n90.ord90, 0) ord90, n90.roas90,
    li.inc_date, li.probe_bid,
    COALESCE(ep.ep_clk, 0) ep_clk, ROUND(SAFE_DIVIDE(ep.ep_gp, NULLIF(ep.ep_sp, 0)), 2) AS ep_roas,
    COALESCE(ep.ep_ord, 0) ep_ord,
    ROUND(COALESCE(IF(t.is_pt, NULL, l.ly_cpc), fb.cpc_target, bd.cpc_target), 2) AS tcpc,
    COALESCE(l.ly_clk, 0) AS ly_clk,
    COALESCE(l.ly_ord, 0) >= 2 AND SAFE_DIVIDE(l.ly_ord, NULLIF(l.ly_year_ord, 0)) >= 0.25 AND l.ly_first <= DATE_SUB((SELECT d FROM sb_wm), INTERVAL 421 DAY) AND NOT t.is_pt AS seasonal_now,
    COALESCE(dk.pd, 0) > 0.10 AS capped,
    ROUND(COALESCE(dk.pd, 0) * 100) AS pct_dark,
    -- v27.48: the park reverdict — DIM_KEYWORD (the reverdict population) carries SB keyword
    -- config too (discovered at wiring: 26 of the 33 calibrated revives sit in SB campaigns),
    -- so the SB arm reads the same snapshot by (campaign, keyword) id.
    COALESCE(rv.reverdict = 'REVIVE', FALSE) AS is_revive,
    -- v27.68: REDUNDANT (Task 2.4) = CONFIRM_PARK with the sibling named — same engine behavior
    COALESCE(rv.reverdict IN ('CONFIRM_PARK', 'REDUNDANT', 'SIBLING_REVIVE'), FALSE) AS confirm_park,
    -- ^ v27.71 (review, CRITICAL): SIBLING_REVIVE added — hand-queue ONLY; without this it walked the generic ACTIVATE door
    -- v27.48.2: same settled-record ordering keys as the SP arm (guard snapshot, table only)
    COALESCE(gd.settled_winner, FALSE) AS g_settled_winner,
    COALESCE(gd.record_loser, FALSE) AS g_record_loser,
    -- v27.53 ITEM 3 — THE CUT GATE, SCALED TO THE WINDOW IT JUDGES. The condemnation branches
    -- fired at a bar chosen by TIER and SEASON (13 low-tier/peak, 30 otherwise) while the window
    -- they measure is chosen independently (3 days low-tier, else V_PEAK_WINDOW_RULE.w_days). The
    -- two were never wired together, so changing the window silently changed how OFTEN the engine
    -- condemns, on top of what it sees — and V_PEAK_WINDOW_RULE can move w_days without touching
    -- the bar. Proven on the 2026-08-12 backtest (n = 11,019): hold the gate constant and every
    -- apparent 7-day advantage disappears — zero peaks favour 7 days and the dollars flip to the
    -- short window by +$6,876. So the bar is now ONE definition, anchored at the historical
    -- 13-clicks-per-7-days density and scaled by the row's OWN effective window:
    --     eff_days = 3 for low-budget non-defense rows (their W is rebased to 3d above), else w_days
    --     cut_gate = max(4, ceil(13 x eff_days / 7))   ->   6 at 3 days, 13 at 7 days
    -- The floor of 4 keeps single-click noise out of a very short window. Computed here so the
    -- action / bid / reason ladders share it and cannot drift the way v27.30-v27.32 did.
    GREATEST(4, CAST(CEIL(13.0 * IF(c.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT c.is_defense,
                                    3, (SELECT w_days FROM cap)) / 7.0) AS INT64)) AS cut_gate,
    -- v27.53 ITEM 7 — the $1.00 wake step-down, from the guard snapshot
    COALESCE(gd.wake_due, FALSE) AS g_wake_due, gd.wake_step_bid AS g_wake_step_bid,
    COALESCE(gd.wake_clk, 0) AS g_wake_clk, gd.wake_date AS g_wake_date
  FROM sb_camps c
  JOIN sb_td t ON t.campaign_id = c.campaign_id
  LEFT JOIN `onyga-482313.OI.FACT_PARK_REVERDICT` rv
    ON rv.campaign_id = CAST(c.campaign_id AS STRING) AND rv.keyword_id = CAST(t.keyword_id AS STRING)
  LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_GUARD` gd
    ON gd.campaign_id = CAST(c.campaign_id AS STRING) AND gd.keyword_id = CAST(t.keyword_id AS STRING)
  LEFT JOIN agb ON agb.ad_group_id = t.ad_group_id
  LEFT JOIN sb_kwW w ON w.keyword_id = t.keyword_id
  LEFT JOIN lastinc li ON li.keyword_id = t.keyword_id
  LEFT JOIN sb_episode ep ON ep.keyword_id = t.keyword_id
  LEFT JOIN ly l ON l.kw = LOWER(TRIM(t.target_text))
  LEFT JOIN camp_parent cp ON cp.cid = c.campaign_id
  LEFT JOIN sb_adfmt af ON af.ad_group_id = t.ad_group_id
  LEFT JOIN sb_band fb ON fb.parent_name = cp.parent_name
    AND fb.ad_format = UPPER(COALESCE(af.creative_type, 'NA'))
    AND fb.match_type = IF(t.is_pt, 'PRODUCT', UPPER(COALESCE(t.match_type, '')))
  LEFT JOIN band bd ON bd.parent_name = cp.parent_name
    AND bd.match_type = IF(t.is_pt, 'PRODUCT', UPPER(COALESCE(t.match_type, '')))
  LEFT JOIN sb_dark dk ON dk.cid = c.campaign_id
  LEFT JOIN sb_t90 n90 ON n90.keyword_id = t.keyword_id
),
sb_classed AS (
  SELECT b.*,
    CASE
      WHEN b.ord_w >= 1 AND COALESCE(b.roas_w, 0) >= 1.1 THEN 'WINNER'
      WHEN b.ord_w >= 1 AND COALESCE(b.roas_w, 0) >= 0.7 THEN 'MARGINAL'
      WHEN b.clk_w > 0 THEN 'LOSER'
      ELSE 'IDLE'
    END AS class,
    -- AUTOS EXCLUDED (v24.1): a raise on an auto clause is just a raise, not an experiment
    (b.inc_date IS NOT NULL AND NOT b.is_auto
     AND b.inc_date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
     AND b.ep_clk < 20) AS probing,
    (b.inc_date IS NOT NULL AND NOT b.is_auto
     AND b.inc_date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
     AND b.ep_clk >= 20) AS probe_done
  FROM sb_base b
),
sb_agg AS (
  SELECT c.*,
    SUM(c.sp_w) OVER (PARTITION BY c.campaign_id) AS camp_sp,
    SUM(c.sp1) OVER (PARTITION BY c.campaign_id) AS camp_sp1,
    ROUND(SAFE_DIVIDE(SUM(c.gp1) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp1) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_1d,
    CAST(SUM(c.clk1) OVER (PARTITION BY c.campaign_id) AS INT64) AS camp_clk1,
    CAST(SUM(c.clk2) OVER (PARTITION BY c.campaign_id) AS INT64) AS camp_clk2,
    ROUND(SAFE_DIVIDE(SUM(c.gp2) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp2) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_prev2,
    LOGICAL_OR(c.is_auto) OVER (PARTITION BY c.campaign_id) AS is_auto_campaign,
    CAST(SUM(c.clk3) OVER (PARTITION BY c.campaign_id) AS INT64) AS camp_clk3,
    ROUND(SAFE_DIVIDE(SUM(c.gp3) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp3) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_3d,
    CAST(SUM(c.clk4_14) OVER (PARTITION BY c.campaign_id) AS INT64) AS camp_clk4_14,
    ROUND(SAFE_DIVIDE(SUM(c.gp4_14) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp4_14) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_4_14,
    ROUND(SAFE_DIVIDE(SUM(c.gp_w_raw) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp_w) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas_w,
    SUM(c.clk7) OVER (PARTITION BY c.campaign_id) AS camp_clk7,
    ROUND(SAFE_DIVIDE(SUM(c.gp7) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp7) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas7,
    SUM(c.clk8_28) OVER (PARTITION BY c.campaign_id) AS camp_clk8_28,
    ROUND(SAFE_DIVIDE(SUM(c.gp8_28) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(c.sp8_28) OVER (PARTITION BY c.campaign_id), 0)), 2) AS camp_roas8_28,
    SUM(IF(c.class = 'LOSER', c.sp_w, 0)) OVER (PARTITION BY c.campaign_id) AS loser_sp,
    SUM(IF(c.probing, 1, 0)) OVER (PARTITION BY c.campaign_id) AS active_probes,
    ROUND(SAFE_DIVIDE(SUM(IF(c.class IN ('WINNER','MARGINAL'), c.sp_w, 0)) OVER (PARTITION BY c.campaign_id),
                      NULLIF(SUM(IF(c.class IN ('WINNER','MARGINAL'), c.clk_w, 0)) OVER (PARTITION BY c.campaign_id), 0)), 2) AS win_cpc,
    SUM(IF(c.class = 'LOSER' AND NOT c.probing, c.sp_w, 0))
      OVER (PARTITION BY c.campaign_id ORDER BY IF(c.class = 'LOSER' AND NOT c.probing, COALESCE(c.roas_w, 0), 999) DESC, c.sp_w
            ROWS UNBOUNDED PRECEDING) AS loser_cum_sp,
    ROW_NUMBER() OVER (PARTITION BY c.campaign_id
      -- v27.48.2: a scope-lifetime LOSER (record_loser) leaves the candidate pool — the loser
      -- path owns it, never a probe seat; settled-proven candidates rank first (Cause 2).
      ORDER BY IF(c.class = 'IDLE' AND NOT c.probing AND NOT c.probe_done AND NOT c.confirm_park AND NOT c.g_record_loser, 0, 1),
               IF(c.seasonal_now, 0, 1),
               IF(c.g_settled_winner, 0, 1),
               IF(c.tcpc IS NOT NULL, 0, 1), c.ly_clk DESC, c.clk_w ASC, c.target_text) AS cand_rank,
    -- cost-aware seats (Ori 2026-08-02): winners' bid premium above $1 shrinks the seat count
    GREATEST(1, CAST(ROUND(GREATEST(0, c.budget - SUM(IF(c.class = 'WINNER', GREATEST(0, 4 * (COALESCE(c.current_bid, 0) - 1)), 0)) OVER (PARTITION BY c.campaign_id)) / 4) AS INT64)) AS slots,
    ROW_NUMBER() OVER (PARTITION BY c.campaign_id ORDER BY
      -- v27.48: same revival ordering as the SP arm — CONFIRM_PARK sinks with the tested
      -- losers; a settled REVIVE joins the proven tier and ranks above fresh unproven.
      IF((c.clk90 >= 15 AND c.ord90 = 0 AND NOT c.probing AND NOT c.probe_done AND NOT c.seasonal_now) OR c.confirm_park, 1, 0),
      IF(c.class IN ('WINNER','MARGINAL') OR COALESCE(c.roas90, 0) >= 1.0 OR c.probing OR c.probe_done OR c.is_revive, 0, 1),
      IF(c.is_revive, 0, 1),
      -- v27.48.2: settled evidence outranks fresh unsettled inside the proven tier (Cause 2);
      -- part-1 revives stay on top (the is_revive key above), live window classes above both.
      IF(c.g_settled_winner, 0, 1),
      -- seasonal revival: sold in this window last year -> jumps the queue as its season arrives
      IF(c.seasonal_now, 0, 1),
      COALESCE(c.roas90, 0) DESC,
      IF(c.clk90 > 0, 0, 1),
      c.clk90 DESC,
      IF(c.tcpc IS NOT NULL, 0, 1),
      c.target_text) AS seat_rank
  FROM sb_classed c
),
-- APPLIED-HOLD (Ori 2026-08-04, "i already applied and approved this today why is it shown
-- again"): bulksheet uploads land in FACT_PPC_CHANGE_LOG immediately, but the config mirrors
-- (DIM_KEYWORD / sb config) lag Fivetran by 1-2 days — so the engine re-derives the SAME
-- daily-ladder step from the stale bid and invites a double-apply. Hold the row instead:
-- last applied change within 48h, and (applied TODAY — one ladder step per day — or the
-- applied value has not reached the config yet).
applied AS (
  SELECT CAST(campaign_id AS STRING) cid, LOWER(TRIM(targeting)) tgt,
         ARRAY_AGG(STRUCT(applied_at AS ts, new_bid) ORDER BY applied_at DESC LIMIT 1)[OFFSET(0)] last
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE applied_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 48 HOUR)
    AND action IN ('INCREASE_BID', 'REDUCE_BID') AND new_bid IS NOT NULL
  GROUP BY 1, 2
),
applied_bud AS (
  SELECT CAST(campaign_id AS STRING) cid,
         ARRAY_AGG(STRUCT(applied_at AS ts, new_budget) ORDER BY applied_at DESC LIMIT 1)[OFFSET(0)] last
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE applied_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 48 HOUR)
    AND action = 'BUDGET_CHANGE' AND new_budget IS NOT NULL
  GROUP BY 1
),
-- v27.45: the single membership function — who the out-of-budget engine owns (DEFER_OOB routing)
cap_state AS (
  SELECT CAST(campaign_id AS STRING) cid, is_oob_owned, days_capped_7d
  FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE`
),
-- v27.45: the single budget authority — PHASE's instruction verbatim for its campaigns
-- (PHASE applies its own applied-hold, so bud_hold is bypassed for these rows)
phase_bud AS (
  SELECT CAST(campaign_id AS STRING) cid, suggested_budget AS ph_budget, reason AS ph_reason
  FROM `onyga-482313.OI.V_OOB_BUDGET_PHASE`
),
out AS (
SELECT
  -- v27.98 (Ori 2026-08-21): CENTS. The budget was published to whole dollars while every
  -- suggested_budget arm below multiplies the UNROUNDED figure, so a row that said "cut 20%" and
  -- was arithmetically a 20% cut printed as -18.10% next to its own sentence, and the same
  -- campaign read $29.00 here and $29.16 in the sibling budget engine on one snapshot. Two harms,
  -- one cause. The sharper one: the export gate drops a row when the suggested value sits within
  -- half a cent of the current one, and on a floor-bound cut ($15.36 -> $15.00) the rounded
  -- current read $15 and the genuine 36-cent cut was silently binned as a no-op — measured on
  -- four consecutive snapshots, two campaigns. Publishing cents makes the printed change agree
  -- with the arithmetic, makes the two engines agree with each other, and lets a small real cut
  -- reach the export.
  a.campaign_id, a.campaign_name, 'SP' AS channel, ROUND(a.budget, 2) AS budget,
  (SELECT in_peak FROM season) AS in_peak, (SELECT w_days FROM cap) AS w_days,
  ROUND(a.camp_sp, 2) AS campaign_spend_w,
  ROUND(100 * SAFE_DIVIDE(a.loser_sp, NULLIF(a.camp_sp, 0))) AS loser_share_pct,
  a.active_probes,
  a.keyword_id, a.ad_group_id, a.target_text, a.match_type, a.is_auto, a.is_pt,
  ROUND(a.current_bid, 2) AS current_bid,
  a.clk_w AS clicks_w, ROUND(a.sp_w, 2) AS spend_w, a.ord_w AS orders_w, a.roas_w,
  a.tcpc AS target_cpc, a.class,
  a.probing, a.inc_date AS probe_started, a.ep_clk AS probe_clicks, a.ep_roas AS probe_roas,
  CAST(a.clk7 AS INT64) AS clicks_7d, a.roas7 AS roas_7d,
  CAST(a.clk8_28 AS INT64) AS clicks_8_28, a.roas8_28 AS roas_8_28,
  ROUND(a.sp1, 2) AS spend_1d, ROUND(a.camp_sp1, 2) AS camp_spend_1d,
  CAST(a.clk1 AS INT64) AS clicks_1d, ROUND(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 2) AS roas_1d,
  CAST(a.clk2 AS INT64) AS clicks_prev2, ROUND(SAFE_DIVIDE(a.gp2, NULLIF(a.sp2, 0)), 2) AS roas_prev2,
  CAST(a.clk3 AS INT64) AS clicks_3d, ROUND(SAFE_DIVIDE(a.gp3, NULLIF(a.sp3, 0)), 2) AS roas_3d,
  CAST(a.clk4_14 AS INT64) AS clicks_4_14, ROUND(SAFE_DIVIDE(a.gp4_14, NULLIF(a.sp4_14, 0)), 2) AS roas_4_14,
  a.is_auto_campaign, a.camp_clk3 AS camp_clicks_3d, a.camp_roas_3d, a.camp_clk4_14 AS camp_clicks_4_14, a.camp_roas_4_14,
  a.camp_clk1 AS camp_clicks_1d, a.camp_roas_1d,
  a.camp_clk2 AS camp_clicks_prev2, a.camp_roas_prev2,
  CAST(a.camp_clk7 AS INT64) AS camp_clicks_7d, a.camp_roas7 AS camp_roas_7d,
  CAST(a.camp_clk8_28 AS INT64) AS camp_clicks_8_28, a.camp_roas8_28 AS camp_roas_8_28,
  a.pct_dark, a.capped, a.slots, a.seat_rank, a.is_defense, a.is_seasonal, a.is_research, a.seasonal_now,
  -- v27.48.2: settled-record keys (guard snapshot) — published for verification, and probe_rank
  -- reads settled_winner (the settled-first key extending the v27.38 profit ordering)
  a.g_settled_winner AS settled_winner, a.g_record_loser AS record_loser,
  -- v27.53: the window-scaled cut gate (item 3) + the wake step-down facts (item 7), published
  a.cut_gate, a.g_wake_due AS wake_due, a.g_wake_step_bid AS wake_step_bid,
  a.g_wake_clk AS wake_clicks, a.g_wake_date AS wake_date,
  -- ROLE (Ori 2026-08-02): the keyword's job in the campaign economy, one word.
  -- FUNDER pays for everything · WATCH earns but thin · PROBE mid-test · CANDIDATE next up
  -- · TRIAL gathering its 4 clicks · PARKED allowance-parked (can return) · RETIRED tested
  -- loser (permanent, seasonal revival exempts) · QUEUED beyond the seats · IDLE waiting
  CASE
    WHEN a.is_defense THEN 'DEFENSE'
    WHEN a.probing OR a.probe_done THEN 'PROBE'
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now AND NOT a.is_auto THEN 'RETIRED'
    WHEN a.is_auto THEN CASE
      WHEN SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.sp7 + a.sp8_28, 0)) >= 1.1 AND (a.clk7 + a.clk8_28) >= 4 THEN 'FUNDER'
      WHEN a.class IN ('WINNER', 'MARGINAL') THEN 'WATCH'
      -- evidence in + bid at the floor: it is an antenna now — alive cheap, terms are the info
      WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND COALESCE(a.current_bid, 0) <= 0.25 THEN 'ANTENNA'
      WHEN a.class = 'LOSER' THEN 'TRIAL' ELSE 'IDLE' END
    WHEN a.seat_rank > a.slots THEN 'QUEUED'
    -- FUNDER is judged on 28 DAYS (Ori 2026-08-02) — a stable financier, not a hot week;
    -- and it needs EVIDENCE: >= 4 clicks in the 28d ("only 1 click can't be funder")
    WHEN SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.sp7 + a.sp8_28, 0)) >= 1.1 AND (a.clk7 + a.clk8_28) >= 4 THEN 'FUNDER'
    WHEN a.class IN ('WINNER', 'MARGINAL') THEN 'WATCH'
    WHEN a.is_research AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp THEN 'ANTENNA'
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp THEN 'PARKED'
    WHEN a.class = 'LOSER' THEN 'TRIAL'
    WHEN a.class = 'IDLE' AND NOT a.is_auto AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season))
         AND a.cand_rank <= (IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) - a.active_probes) THEN 'CANDIDATE'
    ELSE 'IDLE'
  END AS role,

  -- HEALTHY-CAMPAIGN BUDGET RULE (Ori 2026-08-01 tuning, knob #5): the only budget move for a
  -- not-capped campaign is the loss cut — evidence window (W) AND today both under 0.6x ->
  -- -20% with the seasonal floor ($10 off / $15 peak). Raises belong to the dark ladder
  -- (a healthy campaign is not hitting its cap, a raise buys nothing).
  CASE
    -- DARK-AUTO LADDER (Ori 2026-08-02: "if dark > 0 then must be a raise or trim") — the OOB
    -- budget ladder, brought into the Auto section for its capped campaigns:
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) >= 1.2 AND COALESCE(a.camp_roas_prev2, 0) >= 1.5
      THEN ROUND(a.budget * IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 2.0, 1.5), 2)
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) >= 1.2
      THEN ROUND(a.budget * IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 1.5, 1.25), 2)
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) < 0.6 AND COALESCE(a.camp_roas_prev2, 0) < 0.6
        AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
      THEN ROUND(GREATEST(a.budget * 0.8, (SELECT IF(in_peak, 15.0, 10.0) FROM season)), 2)
    WHEN NOT a.is_defense AND NOT (a.is_auto_campaign AND a.capped) AND COALESCE(a.camp_roas_w, 0) < 0.6 AND COALESCE(a.camp_roas_1d, 0) < 0.6
        AND a.camp_sp > 0 AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
      THEN ROUND(GREATEST(a.budget * 0.8, (SELECT IF(in_peak, 15.0, 10.0) FROM season)), 2)
  END AS suggested_budget,
  CASE
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) >= 1.2 AND COALESCE(a.camp_roas_prev2, 0) >= 1.5
      THEN CONCAT('dark ', CAST(CAST(a.pct_dark AS INT64) AS STRING), '% while converting strong (today ', CAST(COALESCE(a.camp_roas_1d,0) AS STRING), 'x, prev-2d ', CAST(COALESCE(a.camp_roas_prev2,0) AS STRING), 'x) — raise the cap')
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) >= 1.2
      THEN CONCAT('dark ', CAST(CAST(a.pct_dark AS INT64) AS STRING), '% while converting (today ', CAST(COALESCE(a.camp_roas_1d,0) AS STRING), 'x) — raise the cap')
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) < 0.6 AND COALESCE(a.camp_roas_prev2, 0) < 0.6
        AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
      THEN CONCAT('dark ', CAST(CAST(a.pct_dark AS INT64) AS STRING), '% AND losing both windows — cut 20%; the brakes trim the clicked clauses')
    WHEN NOT a.is_defense AND NOT (a.is_auto_campaign AND a.capped) AND COALESCE(a.camp_roas_w, 0) < 0.6 AND COALESCE(a.camp_roas_1d, 0) < 0.6
        AND a.camp_sp > 0 AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
      THEN CONCAT('W ', CAST(COALESCE(a.camp_roas_w,0) AS STRING), 'x AND today ',
                   CAST(COALESCE(a.camp_roas_1d,0) AS STRING), 'x — both losing → cut 20% (floor $',
                   CAST(CAST((SELECT IF(in_peak, 15, 10) FROM season) AS INT64) AS STRING), ')')
  END AS budget_reason,
  CASE
    -- probe verdicts first
    WHEN a.is_defense THEN 'DEFENSE'
    -- v27.53 ITEM 8c (second door): the PROBE verdict must not resurface a CONFIRM_PARK row
    -- either. Measured 2026-08-12: 'teenager girl gift ideas' — reverdict CONFIRM_PARK, a
    -- settled-verified retirement — was emitting WINNER_FOUND off ONE click at 14.27x. Falls
    -- through to the probe_done PARK below, which is what a confirmed park should do.
    WHEN a.probe_done AND NOT a.confirm_park AND (COALESCE(a.ep_roas, 0) >= 1.0
         -- v27.27 (Ori 2026-08-06: "it seems like it is profitable"). The probe window is a
         -- NARROW recent measurement, and ads sales restate for days (spend ~D+3, sales to
         -- D+7 SP / D+14 SB) -- so a probe reads 0x while the keyword's real windows are
         -- healthy. Measured: 'gifts for 12 year old girls' probe 37c at 0.00x vs 146c at
         -- 2.12x (7d) and 239c at 1.11x (8-28d) -- and it was being PARKED to $0.25.
         -- A probe verdict may never park a keyword its own evidence window says is winning.
                      OR COALESCE(a.roas_w, 0) >= 1.0) THEN 'WINNER_FOUND'
    WHEN a.probe_done AND a.is_auto THEN 'AUTO_TRIM'
    WHEN a.probe_done THEN 'PARK'
    -- active probes: daily movement by the click methodology
    -- STARVING PROBE (Ori 2026-08-04, "if last day probe is with less than 2 clicks need to
    -- raise it to 1 bid"): under 2 clicks/day the 20-click verdict never arrives — lift to $1.
    -- v27.70 (reviewer A, 2026-08-16): mirror the v27.69 bid arm's predicate — the entry prices
    -- only a RAISE, so when the entry lands at/below the current bid the bid arm emits NULL and
    -- this action must fall through too (PROBE_ADJUST is v27.29-exempt: without the gate it
    -- published an action with no bid — an empty promise).
    WHEN a.probing AND a.clk1 < 2 AND COALESCE(a.current_bid, 0) < 0.95
         AND ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
             > COALESCE(a.current_bid, 0) + 0.005 THEN 'PROBE_ADJUST'
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0 THEN 'PROBE_ADJUST'
    WHEN a.probing THEN 'PROBE_WAIT'
    -- v27.26 (Ori 2026-08-06: "if last day it was profitable and last 7 days doesnt, do not
    -- change anything. maybe we start a wave. when a not profitable day will occur you can
    -- check the 7 days again and decide what to do"). A profitable LAST DAY vetoes every
    -- window-driven move -- up or down. The window is history; a profitable day inside a
    -- losing window may be the turn, and cutting it kills the wave before it forms. Wait
    -- for an unprofitable day, THEN re-read the window and act.
    WHEN COALESCE(a.clk1, 0) >= 1 AND COALESCE(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 0) >= 1.0
         AND COALESCE(a.roas_w, 0) < 1.0
      THEN 'HOLD'
    -- tested loser (>=15 clicks/90d, no sale): permanent park — its seat frees for the next test
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now AND NOT a.is_auto THEN IF(COALESCE(a.current_bid, 0) > 0.30, 'PARK', 'IDLE')
    -- SEAT MECHANISM (Ori 2026-08-01): beyond the budget/$4 seats -> queue at $0.25
    WHEN a.seat_rank > a.slots AND NOT a.is_auto THEN IF(COALESCE(a.current_bid, 0) > 0.30, 'PARK_WAIT', 'IDLE')
    -- the 80% pool
    -- SEASON RAMP (Ori 2026-08-02): its season is arriving (seasonal_now) and the bid sits
    -- under 60% of the current LY-anchored target — glide UP toward target by max(+10%, +5c),
    -- never above it from this rule. WINNER/MARGINAL only (orders prove the season is real);
    -- losers re-enter through the probe path at 1.5x target instead.
    -- v27.11 (Ori 2026-08-04, "why it is not raised toward target?"): the mirror of
    -- EASE_TO_TARGET — a WINNER earning below its target price glides UP toward it, max(+10%, +5c),
    -- never past it (the target is the LY/band market price — the built-in ceiling). Not
    -- while capped (never raise into dark), not autos (own doctrine), not defense.
    WHEN a.class = 'WINNER' AND NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < a.tcpc - 0.05 THEN 'RAISE_TO_TARGET'
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc THEN 'RAISE_TO_TARGET'
    -- BREAKEVEN CUT (Ori 2026-08-03): a keyword with >= 30 clicks over 28d IS decidable at its
    -- own grain — and its economics name the bid: margin per sale ÷ clicks per sale = 28d
    -- profit per click ("30 clicks per sale x $3 margin -> bid $0.10"). Poor 28d net ROAS
    -- (< 1.0) with the bid above that breakeven -> cut TO it (floor $0.02). Outranks the
    -- volume lift and research ease — accumulated keyword evidence beats both.
    -- v27.12 (Ori 2026-08-04): breakeven economics moved to the W WINDOW (7d off / 3d peak;
    -- low tiers' W is already 3d) and softened to a GLIDE — -10%/day toward the window's
    -- profit-per-click, floor $0.15. Zero-profit windows still park $0.25.
    -- v27.55 (Ori 2026-08-13, on 'gift for teen girl': "the decision is good — gentle cut for it
    -- till we find a profitable converting CPC"): the STEP was already gentle; the DESTINATION was
    -- wrong. Per-click worth was computed from the W window alone, so that row glided toward $0.20
    -- priced off 58 clicks while its 8-28d window held 1,259 clicks at 0.81x — it would sail past
    -- the price where the keyword actually converts and grind on to the $0.15 floor, losing the
    -- volume. The destination is now POOLED 1-28d evidence (gp7+gp8_28 over clk7+clk8_28): the
    -- maximum-likelihood per-click worth over everything we have, which is what "find the
    -- profitable converting CPC" means. Pooling a keyword's own two disjoint windows needs no
    -- shrinkage constant — same keyword, the windows simply add. Spans 1-28d via clk7 (not clk_w)
    -- so the destination does not move when the peak window flips 7d -> 3d. The -10%/day step and
    -- the $0.15 floor are unchanged; a genuinely deteriorating keyword still walks down, to the
    -- right place.
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND a.gp_w_raw <= 0 AND COALESCE(a.current_bid, 0) > 0.30 THEN 'PARK'
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND COALESCE(a.roas_w, 0) < 1.0 AND a.gp_w_raw > 0
         AND SAFE_DIVIDE(a.sp7 + a.sp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) > SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) * 1.05 AND COALESCE(a.current_bid, 0) > 0.17 THEN 'CUT_TO_BREAKEVEN'
    -- VOLUME FLOOR (Ori 2026-08-03): under ~30 clicks/week a campaign cannot decide anything —
    -- classes are noise. Seated keywords below the entry anchor LIFT to it (max($1, min(1.5x
    -- target, $2))) to buy decision-grade traffic; parks/cuts above are volume-gated.
    WHEN NOT a.is_auto AND NOT a.capped AND IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), COALESCE(a.camp_clk3, 0) < 13, COALESCE(a.camp_clk7, 0) < 30) AND NOT a.is_defense AND a.seat_rank <= a.slots
         AND (a.clk7 + a.clk8_28) < 30 AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2) THEN 'VOLUME_LIFT'
    -- NUDGE_UP (Ori 2026-08-04, "no clicks need a nudge up"): a seated low-tier keyword with
    -- essentially no clicks (under the 10-click day bar over 1d+prev-2d) is priced out of
    -- visibility — no clicks, no evidence, stuck. Nudge +5%/day toward the entry anchor.
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND (a.clk1 + a.clk2) < 10
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2) THEN 'NUDGE_UP'
    -- v27.21 (Ori 2026-08-06): in the 7d / 8-28d strategies a SILENT keyword is the trigger.
    -- A seated, active keyword that is buying no clicks is priced out of the auction, so the
    -- very windows it is judged on can never refresh -- they just age. Same +5%/day nudge as
    -- the low tier.
    -- v27.98 (Ori 2026-08-21): SILENCE IS NOW MEASURED ON COMPLETE DAYS. Through v27.97 the
    -- gate was the filling day alone -- the one window in this file that ended AT the
    -- watermark, on a day that is only 88-90% loaded when the engine runs. Measured: 13.1% of
    -- steady clickers read zero on the filling day purely on arrival timing, so roughly one
    -- seated keyword in eight was eligible on any given morning and the proposal did not
    -- survive an hour: two of the four live rows flipped back to KEEP when a late click
    -- landed. It also made the sentence untrue -- it said "never enters the auction" about a
    -- keyword that had clicked on all seven preceding days. The gate is now the three
    -- COMPLETE days ending the day before the watermark, the same span the reason names, and
    -- the filling day keeps its house role: a one-way veto that may never drive a move.
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND COALESCE(a.clk3, 0) = 0
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN 'NUDGE_UP'
    -- AUTO RAISE (Ori 2026-08-02, "why is this not raised"): the third auto lever — increase
    -- bids when performance is good. Winner clause with real evidence, campaign not capped:
    -- +15%/day toward the $2 cap. (While capped, the budget raise is the lever, never the bid.)
    -- AUTO_BRAKE (Ori 2026-08-02): while a campaign caps, every clicked non-winner clause
    -- steps down max(5%, 30% x dark)/day — dark must produce a raise or a trim, never a hold
    -- LOW-BUDGET AUTO DAY RULES (Ori 2026-08-04, BOTTLE-SP/AUTO): "in auto low budget you
    -- should focus on short term windows (prev day, 2-3 prev days) and react base on it."
    -- Converted yesterday (>=3 clicks, net profit) -> raise a bit (+5%, cap $2). No profit
    -- yesterday AND prev-2d on >=10 combined clicks -> trim a bit (-5%, floor $0.20). A
    -- conversion in EITHER window blocks the trim. These outrank the weekly auto rules and
    -- the capped mechanics — the budget ladder owns the cap, the bid follows yesterday.
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.clk1 >= 1 AND a.gp1 > a.sp1 AND COALESCE(a.current_bid, 0) < 2.00 THEN 'AUTO_DAY_RAISE'
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.gp1 <= 0 AND a.gp2 <= 0 AND (a.clk1 + a.clk2) >= 10
         AND ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2) < COALESCE(a.current_bid, 0) THEN 'AUTO_DAY_TRIM'
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class = 'WINNER' AND a.clk1 >= 4
         AND COALESCE(a.current_bid, 0) > SAFE_DIVIDE(a.sp1, NULLIF(a.clk1, 0)) + 0.05 THEN 'AUTO_FIT'
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class != 'WINNER' AND a.clk1 >= 1 AND COALESCE(a.current_bid, 0) > 0.25 THEN 'AUTO_BRAKE'
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'WINNER' AND a.clk_w >= 4 AND NOT a.capped AND COALESCE(a.current_bid, 0) < 2.00 THEN 'AUTO_RAISE'
    -- LOW-AUTO FALLBACK (Ori 2026-08-04: "make sure auto low budget is not using 7 days
    -- window at all"): anything the day rules didn't decide HOLDS — no weekly class verdicts.
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) THEN IF(a.clk1 + a.clk2 > 0, 'KEEP', 'IDLE')
    WHEN a.class = 'WINNER' THEN 'KEEP'
    -- AUTO DOCTRINE (Ori 2026-08-02): 4 fixed clauses — never parked; underperformers TRIM
    -- -15%/day (floor $0.30), the real lever is negating bad terms; targets are advisory here.
    -- AUTO_NUDGE (Ori 2026-08-04, BUNNY Brave close-match): on starving clicks (under the
    -- 30-click weekly floor) a trim compounds into silence — fewer impressions, no new evidence,
    -- stuck. If the clause CONVERTED in the last 3 days, feed the signal instead: +5%/day.
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.clk_w < 30 AND NOT a.capped
         AND (a.gp1 > 0 OR a.gp3 > 0) AND COALESCE(a.current_bid, 0) < 2.00 THEN 'AUTO_NUDGE'
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND COALESCE(a.current_bid, 0) > 0.25
         -- v27.22 (Ori 2026-08-06: "the keyword already stuck"): do NOT trim a clause that
         -- took ZERO clicks yesterday. It is already out of the auction, so the trim has
         -- nothing left to achieve -- it only entrenches the invisibility that the last-day
         -- click gate (v27.21) exists to detect. No clicks yesterday => HOLD, not a cut.
         AND COALESCE(a.clk1, 0) >= 1 THEN 'AUTO_TRIM'
    WHEN a.is_auto THEN IF(a.class = 'MARGINAL', 'KEEP', IF(a.class = 'LOSER', 'KEEP_TAIL', 'IDLE'))
    -- target < bid (Ori 2026-08-01): MARGINAL glides -5%/day toward target; LOSING goes straight
    -- TO the target bid. Winners are never pulled down.
    WHEN a.class = 'MARGINAL' AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN 'EASE_TO_TARGET'
    WHEN a.class = 'MARGINAL' THEN 'KEEP'
    -- losers beyond the 20% allowance → park (worst first; the cum-sum keeps the best within it)
    -- 4-CLICK TRIAL GATE (Ori 2026-08-02, FRESH-SP/BROAD BTS case): "1 click do not break" —
    -- a loser can only be allowance-parked or cut-to-target once it has >= 4 clicks in W (the
    -- same evidence bar as TRIM). Under that it is still in its trial: KEEP_TAIL, keep gathering.
    -- (Without the gate, a day-1 campaign's 20% allowance is cents and first clicks park instantly.)
    WHEN a.is_research AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.35 THEN 'RESEARCH_EASE'
    WHEN a.class = 'LOSER' AND a.clk_w >= IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 10, 4) AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30 THEN 'PARK'
    WHEN a.class = 'LOSER' AND a.clk_w >= IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 10, 4) AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN 'CUT_TO_TARGET'
    WHEN a.class = 'LOSER' THEN 'KEEP_TAIL'
    -- idle pool: promote the next candidates into probes when slots are free
    -- v27.98 (Ori 2026-08-21): THE ENTRY MAY ONLY RAISE — the guard the sibling arm has had
    -- since v27.70, ported here. The doctrine is stated in the bid arm below and was being
    -- broken by this one: three live rows said 'lift to $0.54' / 'lift to $0.83' while
    -- CUTTING the bid 17-46%, because the candidate arm priced the anchored entry
    -- unconditionally and these keywords were already sitting above it at the legacy $1.00.
    -- A verb that contradicts its own sign is not a wording problem: the entry is not a
    -- trim, and pricing a probe DOWN on entry is the trim ladders' business. Predicate
    -- mirrored across action / value / sentence so the three can never disagree.
    WHEN a.class = 'IDLE' AND NOT a.is_auto AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) AND a.cand_rank <= (IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) - a.active_probes)

         AND ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
             > COALESCE(a.current_bid, 0) + 0.005
         THEN 'PROBE_START'
    ELSE 'IDLE'
  END AS action,
  CASE
    WHEN a.is_defense THEN NULL
    -- v27.53 ITEM 8c (second door): the PROBE verdict must not resurface a CONFIRM_PARK row
    -- either. Measured 2026-08-12: 'teenager girl gift ideas' — reverdict CONFIRM_PARK, a
    -- settled-verified retirement — was emitting WINNER_FOUND off ONE click at 14.27x. Falls
    -- through to the probe_done PARK below, which is what a confirmed park should do.
    WHEN a.probe_done AND NOT a.confirm_park AND (COALESCE(a.ep_roas, 0) >= 1.0
         -- v27.27 (Ori 2026-08-06: "it seems like it is profitable"). The probe window is a
         -- NARROW recent measurement, and ads sales restate for days (spend ~D+3, sales to
         -- D+7 SP / D+14 SB) -- so a probe reads 0x while the keyword's real windows are
         -- healthy. Measured: 'gifts for 12 year old girls' probe 37c at 0.00x vs 146c at
         -- 2.12x (7d) and 239c at 1.11x (8-28d) -- and it was being PARKED to $0.25.
         -- A probe verdict may never park a keyword its own evidence window says is winning.
                      OR COALESCE(a.roas_w, 0) >= 1.0)
      -- v27.31 (Ori 2026-08-06): "never shelve a winner" (v27.27) must not also mean "never
      -- PRICE a winner". Returning a bare NULL here swallowed RAISE_TO_TARGET: the action
      -- CASE still said raise, the value CASE said nothing, and the v27.29 no-op guard then
      -- resolved it to HOLD. Repro: 'teen girl gifts trendy stuff', 18c at 4.49x on a $0.15
      -- bid with a $0.31 target. A proven winner still under its target gets the normal
      -- glide -- max(+10%, +$0.05) capped at target; everything else still holds untouched.
      THEN IF(NOT a.is_auto AND NOT a.is_defense AND NOT a.capped AND a.tcpc IS NOT NULL
              AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < a.tcpc - 0.05,
              ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2),
              NULL)
    WHEN a.probe_done AND a.is_auto THEN ROUND(GREATEST(a.current_bid * 0.85, 0.20), 2)
    WHEN a.probe_done THEN 0.25
    -- v27.69 (Task 2.2): the probe ENTRY prices from the anchor when one exists — 1.5x target CPC
    -- (LY / band), else the campaign winners' CPC, else (genuinely anchorless) the old $1.00.
    -- Floor $0.31 (the revive floor — a real bid, never the platform-min trap), cap $2.00. Only a
    -- RAISE may come out of this arm: an anchored entry at/below the current bid emits NULL (the
    -- probe is already priced; cutting it is the trim ladders' business, never the entry's).
    -- DOCTRINE SUCCESSION, recorded: the flat $1.00 was Ori 2026-08-02 "i wont move if not";
    -- the Aug-9 post-mortem re-judged it — "real defect = $1.00 activation floor" — and Task 2.2
    -- encodes the newer verdict. Anchorless rows keep $1.00: with no clearing price to read, a
    -- deliberate overbid buys the first data fastest (the wake-step prices it DOWN after).
    WHEN a.probing AND a.clk1 < 2 AND COALESCE(a.current_bid, 0) < 0.95
      THEN IF(ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
                > COALESCE(a.current_bid, 0) + 0.005,
              ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2), NULL)
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0 THEN ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2)
    WHEN a.probing THEN NULL
    -- v27.26 (Ori 2026-08-06: "if last day it was profitable and last 7 days doesnt, do not
    -- change anything. maybe we start a wave. when a not profitable day will occur you can
    -- check the 7 days again and decide what to do"). A profitable LAST DAY vetoes every
    -- window-driven move -- up or down. The window is history; a profitable day inside a
    -- losing window may be the turn, and cutting it kills the wave before it forms. Wait
    -- for an unprofitable day, THEN re-read the window and act.
    WHEN COALESCE(a.clk1, 0) >= 1 AND COALESCE(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 0) >= 1.0
         AND COALESCE(a.roas_w, 0) < 1.0
      THEN NULL
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now AND NOT a.is_auto THEN IF(COALESCE(a.current_bid, 0) > 0.30, 0.25, NULL)
    WHEN a.seat_rank > a.slots AND NOT a.is_auto THEN IF(COALESCE(a.current_bid, 0) > 0.30, 0.25, NULL)
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)
    WHEN a.class = 'WINNER' AND NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < a.tcpc - 0.05
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND a.gp_w_raw <= 0 AND COALESCE(a.current_bid, 0) > 0.30 THEN 0.25
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND COALESCE(a.roas_w, 0) < 1.0 AND a.gp_w_raw > 0
         AND SAFE_DIVIDE(a.sp7 + a.sp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) > SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) * 1.05 AND COALESCE(a.current_bid, 0) > 0.17
      -- v27.55: the floor is the platform floor only. The per-click worth is a CPC-scale
      -- quantity and must NOT be used as a bid floor (that is the v27.40 units trap): a bid of
      -- $0.36 does not buy a $0.36 click. The loop finds the price instead — step -10%/day and
      -- stop when the row's REALIZED CPC falls to its per-click worth, which is exactly
      -- "gentle cut till we find a profitable converting CPC".
      THEN ROUND(GREATEST(a.current_bid * 0.90, 0.15), 2)
    WHEN NOT a.is_auto AND NOT a.capped AND IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), COALESCE(a.camp_clk3, 0) < 13, COALESCE(a.camp_clk7, 0) < 30) AND NOT a.is_defense AND a.seat_rank <= a.slots
         AND (a.clk7 + a.clk8_28) < 30
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND (a.clk1 + a.clk2) < 10
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2)
    -- v27.21 (Ori 2026-08-06): in the 7d / 8-28d strategies a SILENT keyword is the trigger.
    -- A seated, active keyword that is buying no clicks is priced out of the auction, so the
    -- very windows it is judged on can never refresh -- they just age. Same +5%/day nudge as
    -- the low tier.
    -- v27.98 (Ori 2026-08-21): SILENCE IS NOW MEASURED ON COMPLETE DAYS. Through v27.97 the
    -- gate was the filling day alone -- the one window in this file that ended AT the
    -- watermark, on a day that is only 88-90% loaded when the engine runs. Measured: 13.1% of
    -- steady clickers read zero on the filling day purely on arrival timing, so roughly one
    -- seated keyword in eight was eligible on any given morning and the proposal did not
    -- survive an hour: two of the four live rows flipped back to KEEP when a late click
    -- landed. It also made the sentence untrue -- it said "never enters the auction" about a
    -- keyword that had clicked on all seven preceding days. The gate is now the three
    -- COMPLETE days ending the day before the watermark, the same span the reason names, and
    -- the filling day keeps its house role: a one-way veto that may never drive a move.
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND COALESCE(a.clk3, 0) = 0
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2)
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.clk1 >= 1 AND a.gp1 > a.sp1 AND COALESCE(a.current_bid, 0) < 2.00
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.01), 2.00), 2)
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.gp1 <= 0 AND a.gp2 <= 0 AND (a.clk1 + a.clk2) >= 10
         AND ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2) < COALESCE(a.current_bid, 0)
      THEN ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2)
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class = 'WINNER' AND a.clk1 >= 4
         AND COALESCE(a.current_bid, 0) > SAFE_DIVIDE(a.sp1, NULLIF(a.clk1, 0)) + 0.05
      THEN ROUND(GREATEST(a.current_bid * 0.95, SAFE_DIVIDE(a.sp1, NULLIF(a.clk1, 0))), 2)
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class != 'WINNER' AND a.clk1 >= 1 AND COALESCE(a.current_bid, 0) > 0.25
      -- v27.46 A4: brake magnitude scaled by the clause's own 90d record — proven (>= 1.0x)
      -- eases the flat -5% minimum; middling (0.6-1.0x) max(5%, 15% x dark); losing / no data
      -- keeps max(5%, 30% x dark). Dark is never a hold: the 5% minimum and $0.20 floor stand.
      THEN ROUND(GREATEST(a.current_bid * LEAST(0.95,
                    CASE WHEN COALESCE(a.roas90, 0) >= 1.0 THEN 0.95
                         WHEN a.roas90 >= 0.6 THEN 1 - 0.15 * a.pct_dark / 100
                         ELSE 1 - 0.30 * a.pct_dark / 100 END), 0.20), 2)
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'WINNER' AND a.clk_w >= 4 AND NOT a.capped AND COALESCE(a.current_bid, 0) < 2.00
      THEN ROUND(LEAST(a.current_bid * 1.15, 2.00), 2)
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) THEN NULL
    -- v27.30 (Ori 2026-08-06): RAISE_TO_TARGET emitted NO VALUE. The action CASE fires it
    -- early, but in the VALUE case the bare `class = WINNER -> NULL` below short-circuited
    -- every winner before the raise branch (further down) could ever price it. Repro:
    -- 'teen girl gifts trendy stuff' -- 18c at 4.49x on a $0.15 bid, $0.31 target, action
    -- RAISE_TO_TARGET, suggested_bid NULL. Hoisting the raise above the catch-all fixes it:
    -- max(+10%, +$0.05) capped at the target = $0.20, which is also its own realized CPC
    -- ($3.47/18 clicks) -- a price it has already proven it clears.
    WHEN a.class = 'WINNER' AND NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < a.tcpc - 0.05
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)
    WHEN a.class = 'WINNER' THEN NULL
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.clk_w < 30 AND NOT a.capped
         AND (a.gp1 > 0 OR a.gp3 > 0) AND COALESCE(a.current_bid, 0) < 2.00
      THEN ROUND(LEAST(a.current_bid * 1.05, 2.00), 2)
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND COALESCE(a.current_bid, 0) > 0.25
         -- v27.22 (Ori 2026-08-06: "the keyword already stuck"): do NOT trim a clause that
         -- took ZERO clicks yesterday. It is already out of the auction, so the trim has
         -- nothing left to achieve -- it only entrenches the invisibility that the last-day
         -- click gate (v27.21) exists to detect. No clicks yesterday => HOLD, not a cut.
         AND COALESCE(a.clk1, 0) >= 1
      THEN ROUND(GREATEST(a.current_bid * 0.85, 0.20), 2)
    WHEN a.is_auto THEN NULL
    WHEN a.class = 'MARGINAL' AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN ROUND(GREATEST(a.current_bid * 0.95, a.tcpc), 2)
    WHEN a.class = 'MARGINAL' THEN NULL
    WHEN a.is_research AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.35
      THEN ROUND(GREATEST(a.current_bid * 0.85, 0.30), 2)
    WHEN a.class = 'LOSER' AND a.clk_w >= IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 10, 4) AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30 THEN 0.25
    WHEN a.class = 'LOSER' AND a.clk_w >= IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 10, 4) AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN a.tcpc
    WHEN a.class = 'LOSER' THEN NULL
    WHEN a.class = 'IDLE' AND NOT a.is_auto AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) AND a.cand_rank <= (IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) - a.active_probes)

         AND ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
             > COALESCE(a.current_bid, 0) + 0.005
      -- $1 SEAT-ENTRY FLOOR (Ori 2026-08-02: "i wont move if not") — also the anchorless entry:
      -- no LY target, no band, no winner CPC -> enter at the $1 floor instead of never starting.
      -- v27.98: guarded — an anchored entry at or below the current bid emits NULL, exactly as
      -- the arm's own doctrine (three lines up in the header of the probe block) already said.
      THEN ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
    ELSE NULL
  END AS suggested_bid,
  CASE
    WHEN a.is_defense THEN 'brand defense — the moat is bought at whatever it costs; bids run on the coacher defense mode, never parked by ROAS'
    -- v27.53 ITEM 8c (second door): the PROBE verdict must not resurface a CONFIRM_PARK row
    -- either. Measured 2026-08-12: 'teenager girl gift ideas' — reverdict CONFIRM_PARK, a
    -- settled-verified retirement — was emitting WINNER_FOUND off ONE click at 14.27x. Falls
    -- through to the probe_done PARK below, which is what a confirmed park should do.
    WHEN a.probe_done AND NOT a.confirm_park AND (COALESCE(a.ep_roas, 0) >= 1.0
         -- v27.27 (Ori 2026-08-06: "it seems like it is profitable"). The probe window is a
         -- NARROW recent measurement, and ads sales restate for days (spend ~D+3, sales to
         -- D+7 SP / D+14 SB) -- so a probe reads 0x while the keyword's real windows are
         -- healthy. Measured: 'gifts for 12 year old girls' probe 37c at 0.00x vs 146c at
         -- 2.12x (7d) and 239c at 1.11x (8-28d) -- and it was being PARKED to $0.25.
         -- A probe verdict may never park a keyword its own evidence window says is winning.
                      OR COALESCE(a.roas_w, 0) >= 1.0)
      THEN CONCAT('probe verdict: ', CAST(a.ep_clk AS STRING), ' clicks at ', CAST(COALESCE(a.ep_roas,0) AS STRING),
                  'x — WINNER found; joins the 80% pool, FIT/ROAS logic takes over')
    WHEN a.probe_done AND a.is_auto
      THEN CONCAT('probe verdict: ', CAST(a.ep_clk AS STRING), ' clicks at ', CAST(COALESCE(a.ep_roas,0) AS STRING),
                  'x — auto clause is never parked: trim -15%/day and negate its bad terms')
    WHEN a.probe_done
      THEN CONCAT('probe verdict: ', CAST(a.ep_clk AS STRING), ' clicks at ', CAST(COALESCE(a.ep_roas,0) AS STRING),
                  'x — not profitable, park $0.25 and promote the next candidate')
    -- v27.70 (reviewer A): same gate as the action/bid arms, and the reason prints the ACTUAL
    -- anchored entry value — never 'the $1 entry floor' (the entry is 1.5x target CPC / winners'
    -- CPC / $1 only when genuinely anchorless).
    WHEN a.probing AND a.clk1 < 2 AND COALESCE(a.current_bid, 0) < 0.95
         AND ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
             > COALESCE(a.current_bid, 0) + 0.005
      THEN CONCAT('probe starving — ', CAST(a.clk1 AS STRING), ' click(s) yesterday at $', FORMAT('%.2f', COALESCE(a.current_bid, 0)),
                  ': lift to the $', FORMAT('%.2f', ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)),
                  ' entry so the 20-click verdict (', CAST(a.ep_clk AS STRING), '/20 so far) actually arrives')
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0
      THEN CONCAT('probing (', CAST(a.ep_clk AS STRING), '/20 clicks) — 6+ clicks yesterday, no sale yet: -5% daily descent')
    WHEN a.probing
      THEN CONCAT('probing (', CAST(a.ep_clk AS STRING), '/20 clicks since ', CAST(a.inc_date AS STRING), ') — let the test run')
    -- v27.26 (Ori 2026-08-06: "if last day it was profitable and last 7 days doesnt, do not
    -- change anything. maybe we start a wave. when a not profitable day will occur you can
    -- check the 7 days again and decide what to do"). A profitable LAST DAY vetoes every
    -- window-driven move -- up or down. The window is history; a profitable day inside a
    -- losing window may be the turn, and cutting it kills the wave before it forms. Wait
    -- for an unprofitable day, THEN re-read the window and act.
    WHEN COALESCE(a.clk1, 0) >= 1 AND COALESCE(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 0) >= 1.0
         AND COALESCE(a.roas_w, 0) < 1.0
      THEN CONCAT('profitable yesterday (', CAST(CAST(a.clk1 AS INT64) AS STRING), 'c at ',
                  FORMAT('%.2f', COALESCE(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 0)), 'x) while the window is ',
                  FORMAT('%.2f', COALESCE(a.roas_w, 0)), 'x — hold everything: this may be the start of a wave. The window decides again on the next unprofitable day.')
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now AND NOT a.is_auto
      THEN CONCAT('tested ', CAST(a.clk90 AS STRING), ' clicks/90d with 0 orders — permanent park; its seat goes to the next candidate')
    WHEN a.seat_rank > a.slots AND NOT a.is_auto
      THEN CONCAT('queue #', CAST(a.seat_rank - a.slots AS STRING), ' — ', CAST(a.slots AS STRING),
                  ' seats (budget ÷ $4); its test resumes when a seat frees')
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc
      -- v27.98: same step, same fix as the winner arm below — the printed percentage is derived
      -- from the price this row actually proposes, not from a nominal 10%.
      THEN CONCAT('SEASON RAMP — its season is arriving and the bid is under 60% of the current target $',
                  FORMAT('%.2f', a.tcpc), ': raise ',FORMAT('%+.1f', SAFE_DIVIDE(ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2) - a.current_bid, NULLIF(a.current_bid, 0)) * 100), '% to $',
                  FORMAT('%.2f', ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)),
                  ' (beyond target only via the coacher)')
    WHEN a.class = 'WINNER' AND NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < a.tcpc - 0.05
      -- v27.98 (Ori 2026-08-21): the PERCENTAGE IS BUILT FROM THE ROW. The sentence used to say a
      -- flat "+10%/day" while the step actually taken is the LARGER of +10% and +5c, capped at the
      -- target — so on every live row the nickel arm won and the move landed at +11.9% to +22.7%.
      -- The uploaded price was right each time; only the words were wrong, which is the failure
      -- that makes a correct engine look broken. Deriving the number from the same expression that
      -- prices the row means the two can never disagree again.
      THEN CONCAT('winner (', CAST(COALESCE(a.roas_w, 0) AS STRING), 'x) earning under its target price $',
                  FORMAT('%.2f', a.tcpc), ' — raise ',FORMAT('%+.1f', SAFE_DIVIDE(ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2) - a.current_bid, NULLIF(a.current_bid, 0)) * 100), '% to $',
                  FORMAT('%.2f', ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)),
                  ' (never past target; beyond target only via the coacher)')
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND a.gp_w_raw <= 0 AND COALESCE(a.current_bid, 0) > 0.30
      THEN CONCAT(CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks this window with no net profit — park $0.25; the seat queue owns any comeback')
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND COALESCE(a.roas_w, 0) < 1.0 AND a.gp_w_raw > 0
         AND SAFE_DIVIDE(a.sp7 + a.sp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) > SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) * 1.05 AND COALESCE(a.current_bid, 0) > 0.17
      THEN CONCAT('under breakeven this window — ', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks at ',
                  FORMAT('%.2f', COALESCE(a.roas_w, 0)), 'x: glide -10%/day toward the per-click worth $',
                  CAST(ROUND(GREATEST(SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.clk7 + a.clk8_28, 0)), 0.15), 2) AS STRING), ' (floor $0.15)')
    WHEN NOT a.is_auto AND NOT a.capped AND IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), COALESCE(a.camp_clk3, 0) < 13, COALESCE(a.camp_clk7, 0) < 30) AND NOT a.is_defense AND a.seat_rank <= a.slots
         AND (a.clk7 + a.clk8_28) < 30
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season),
           CONCAT('campaign under the 13-click/3d decision floor (', CAST(COALESCE(a.camp_clk3, 0) AS STRING), 'c/3d) — lift to the entry anchor to buy decision data'),
           CONCAT('campaign under the 30-click/week decision floor (', CAST(COALESCE(a.camp_clk7, 0) AS STRING), 'c/7d) — lift to the entry anchor to buy decision data'))
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND (a.clk1 + a.clk2) < 10
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN CONCAT('invisible — ', CAST(CAST(a.clk1 + a.clk2 AS INT64) AS STRING), ' clicks over 3d at $', FORMAT('%.2f', COALESCE(a.current_bid, 0)),
                  ': the bid is priced out of the auction; nudge ', FORMAT('%+.1f', SAFE_DIVIDE(ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2) - a.current_bid, NULLIF(a.current_bid, 0)) * 100),
                  '% to $', FORMAT('%.2f', ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2)), ', walking toward the entry anchor $',
                  FORMAT('%.2f', ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), ' until it buys data')
    -- v27.21 (Ori 2026-08-06): in the 7d / 8-28d strategies a SILENT keyword is the trigger.
    -- A seated, active keyword that is buying no clicks is priced out of the auction, so the
    -- very windows it is judged on can never refresh -- they just age.
    -- v27.98 (Ori 2026-08-21): silence is measured on the three COMPLETE days, not the filling
    -- day, and the sentence below now says what is actually true -- the windows are aging out,
    -- not that the keyword never enters the auction (it clicked on all seven preceding days on
    -- the row that exposed this).
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND COALESCE(a.clk3, 0) = 0
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN CONCAT('no clicks on the last three complete days at $', FORMAT('%.2f', COALESCE(a.current_bid, 0)),
                  ' while holding a seat — the windows this keyword is judged on are aging out with nothing fresh arriving to refresh them: nudge ',
                  FORMAT('%+.1f', SAFE_DIVIDE(ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2) - a.current_bid, NULLIF(a.current_bid, 0)) * 100), '% to $', FORMAT('%.2f', ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2)),
                  ', walking toward the entry anchor $', FORMAT('%.2f', ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)))
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.clk1 >= 1 AND a.gp1 > a.sp1 AND COALESCE(a.current_bid, 0) < 2.00
      THEN CONCAT('converted yesterday — ', CAST(CAST(a.clk1 AS INT64) AS STRING), ' clicks, net +$', FORMAT('%.2f', a.gp1 - a.sp1), ': low-budget auto reacts daily, raise +5% (cap $2)')
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.gp1 <= 0 AND a.gp2 <= 0 AND (a.clk1 + a.clk2) >= 10
         AND ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2) < COALESCE(a.current_bid, 0)
      THEN CONCAT('no profit yesterday or prev-2d (', CAST(CAST(a.clk1 + a.clk2 AS INT64) AS STRING), ' clicks) — low-budget auto reacts daily: trim -5% (floor $0.20); negate the bad terms')
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class = 'WINNER' AND a.clk1 >= 4
         AND COALESCE(a.current_bid, 0) > SAFE_DIVIDE(a.sp1, NULLIF(a.clk1, 0)) + 0.05
      THEN CONCAT('selling while capped — fit toward the real CPC $', CAST(ROUND(SAFE_DIVIDE(a.sp1, NULLIF(a.clk1, 0)), 2) AS STRING), ': the budget raise buys volume, cheaper clicks buy more of it')
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class != 'WINNER' AND a.clk1 >= 1 AND COALESCE(a.current_bid, 0) > 0.25
      THEN CONCAT('campaign ', CAST(CAST(a.pct_dark AS INT64) AS STRING), '% dark — brake ',
                  CAST(CAST(ROUND(100 * (1 - LEAST(0.95,
                    CASE WHEN COALESCE(a.roas90, 0) >= 1.0 THEN 0.95
                         WHEN a.roas90 >= 0.6 THEN 1 - 0.15 * a.pct_dark / 100
                         ELSE 1 - 0.30 * a.pct_dark / 100 END))) AS INT64) AS STRING),
                  '%/day (dark must produce a raise or a trim, never a hold',
                  CASE WHEN COALESCE(a.roas90, 0) >= 1.0 THEN '; 90d proven — minimum ease'
                       WHEN a.roas90 >= 0.6 THEN '; 90d 0.6-1.0x — half brake' ELSE '' END, ')')
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'WINNER' AND a.clk_w >= 4 AND NOT a.capped AND COALESCE(a.current_bid, 0) < 2.00
      THEN CONCAT('auto clause performing — ', CAST(COALESCE(a.roas_w, 0) AS STRING), 'x on ', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks: raise +15%/day toward $2 (good terms deserve more traffic)')
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.gp1 > 0
      THEN CONCAT('sold yesterday under spend (', FORMAT('%.2f', COALESCE(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 0)), 'x net) — not a raise, not a cut: hold, tomorrow decides')
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.gp2 > 0
      THEN CONCAT('sold in prev-2d (', FORMAT('%.2f', COALESCE(SAFE_DIVIDE(a.gp2, NULLIF(a.sp2, 0)), 0)), 'x net) — day windows mixed: hold, tomorrow decides')
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND (a.clk1 + a.clk2) > 0
      THEN CONCAT(CAST(CAST(a.clk1 + a.clk2 AS INT64) AS STRING), ' clicks over 3d, no sales, under the 10-click day bar — gathering at daily grain')
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
      THEN 'quiet — no clicks yesterday or prev-2d'
    WHEN a.class = 'WINNER' THEN CONCAT('winner: ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x over ', CAST(CAST(IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT a.is_defense, 3, (SELECT w_days FROM cap)) AS INT64) AS STRING), 'd — funds the campaign')
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.clk_w < 30 AND NOT a.capped
         AND (a.gp1 > 0 OR a.gp3 > 0) AND COALESCE(a.current_bid, 0) < 2.00
      THEN CONCAT('converted in the last 3 days on starving clicks (', CAST(CAST(a.clk_w AS INT64) AS STRING), 'c this window, under the 30-click floor) — a trim would freeze it: nudge +5%/day so the sale can prove itself')
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND COALESCE(a.current_bid, 0) > 0.25
         -- v27.22 (Ori 2026-08-06: "the keyword already stuck"): do NOT trim a clause that
         -- took ZERO clicks yesterday. It is already out of the auction, so the trim has
         -- nothing left to achieve -- it only entrenches the invisibility that the last-day
         -- click gate (v27.21) exists to detect. No clicks yesterday => HOLD, not a cut.
         AND COALESCE(a.clk1, 0) >= 1
      THEN CONCAT('auto clause underperforming — ', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks at ', FORMAT('%.2f', COALESCE(a.roas_w, 0)), 'x this week (full evidence, over the 30-click floor): trim -15%/day (floor $0.20); the real lever is negating its bad terms')
    WHEN a.is_auto AND a.class = 'LOSER' AND a.clk_w >= 4
      THEN CONCAT('evidence in — ', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks this window with no profit and the bid already at the floor: negate its bad terms, nothing left to trim')
    WHEN a.is_auto AND a.class = 'LOSER' THEN 'auto clause in its 4-click trial — keep gathering; negate bad terms as they show'
    WHEN NOT a.is_auto AND NOT a.capped AND IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), COALESCE(a.camp_clk3, 0) < 13, COALESCE(a.camp_clk7, 0) < 30) AND a.class IN ('MARGINAL', 'LOSER') AND a.seat_rank <= a.slots
      THEN IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season),
           CONCAT('campaign under the 13-click/3d decision floor (', CAST(COALESCE(a.camp_clk3, 0) AS STRING), 'c/3d) — no window verdicts here; holding at the entry anchor'),
           CONCAT('campaign under the 30-click/week decision floor (', CAST(COALESCE(a.camp_clk7, 0) AS STRING), 'c/7d) — no window verdicts here; holding at the entry anchor'))
    WHEN a.class = 'MARGINAL' AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN CONCAT('marginal ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x with bid above target — glide -5%/day toward $', CAST(a.tcpc AS STRING))
    WHEN a.class = 'MARGINAL' THEN CONCAT('marginal: ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x — in the 80% pool, watch')
    WHEN a.class = 'LOSER' AND a.clk_w < 4
      THEN CONCAT('still in its 4-click trial (', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks so far) — 1 click does not break; keep gathering')
    WHEN a.is_research AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.35
      THEN 'research mode — the antenna stays alive: glide -15%/day, floor $0.30 (its winning terms seed new keywords)'
    WHEN a.class = 'LOSER' AND a.clk_w >= IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 10, 4) AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30
      THEN CONCAT('loser beyond the ', CAST(CAST((SELECT IF(in_peak, 40, 20) FROM season) AS INT64) AS STRING), '% exploration budget — park $0.25 (spend goes to the winners)')
    WHEN a.class = 'LOSER' AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN CONCAT('losing at ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x with bid above target — straight to the target bid $', CAST(a.tcpc AS STRING))
    WHEN a.class = 'LOSER' THEN CONCAT('loser inside the ', CAST(CAST((SELECT IF(in_peak, 40, 20) FROM season) AS INT64) AS STRING), '% allowance — keep gathering')
    WHEN a.class = 'IDLE' AND a.capped
      THEN 'idle — campaign capped (dark > 10%): probes held, a budget artifact not a bid problem'
    WHEN a.class = 'IDLE' AND a.seat_rank <= a.slots AND a.active_probes < IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) AND a.cand_rank <= (IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) - a.active_probes)

         AND ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
             > COALESCE(a.current_bid, 0) + 0.005
      THEN CONCAT(IF(a.seasonal_now, 'SEASONAL REVIVAL (sold in this window last year) — ', ''), 'next probe candidate — lift to $',
                  CAST(ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2) AS STRING),
                  -- v27.70 (reviewer A): the label names the anchor that actually priced the
                  -- entry (the value CONCAT above) — the old CASE tested 1.5x tcpc >= $1 and
                  -- mislabeled every sub-$1 anchored entry as 'the $1 floor'.
                  ' (', CASE WHEN a.tcpc IS NOT NULL THEN '1.5x target CPC (floor $0.31)'
                             WHEN a.win_cpc IS NOT NULL THEN "the winners' avg CPC"
                             ELSE '$1 anchorless entry' END,
                  '), verdict at 20 clicks')
    -- v27.98: the candidate whose bid already clears the entry anchor. It keeps its seat and
    -- its place in the queue; there is simply nothing to upload, and the sentence says so
    -- rather than announcing a lift that is really a cut.
    WHEN a.class = 'IDLE' AND a.seat_rank <= a.slots AND a.active_probes < IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) AND a.cand_rank <= (IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) - a.active_probes)
      THEN CONCAT('next probe candidate, and its bid $', FORMAT('%.2f', COALESCE(a.current_bid, 0)),
                  ' already sits at or above the $', FORMAT('%.2f', ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)),
                  ' entry price — the test runs at the price it already has; only the trim ladders may bring a bid down')
    ELSE 'idle — waiting for a probe slot'
  END AS reason,
  -- v27.76 (Task 4.9): the 90d complete-day click/order pair, PUBLISHED (additive) so the last-day
  -- veto's expected-orders gate can read the keyword's OWN order rate from published columns
  -- instead of re-deriving one. Same window the tested-loser bar and the seat ranking already use
  -- (t90 / sb_t90, ends wm-1 per Task 4.7) — the longest complete-day pair this view carries.
  CAST(a.clk90 AS INT64) AS clicks_90d, CAST(a.ord90 AS INT64) AS orders_90d
FROM agg a
UNION ALL
-- ── SB block: identical action grammar, incl. the capped PROBE_START gate (both arms since v3;
--    probing a dark campaign is a budget artifact — the no-loss-cuts rule; running probes still
--    get verdicts and the −5% descent); net ROAS is the cost-ratio ESTIMATE ──
SELECT
  -- v27.98: cents, same reason as the SP layer above — one rounding, both output layers.
  a.campaign_id, a.campaign_name, 'SB' AS channel, ROUND(a.budget, 2) AS budget,
  (SELECT in_peak FROM season) AS in_peak, (SELECT w_days FROM cap) AS w_days,
  ROUND(a.camp_sp, 2) AS campaign_spend_w,
  ROUND(100 * SAFE_DIVIDE(a.loser_sp, NULLIF(a.camp_sp, 0))) AS loser_share_pct,
  a.active_probes,
  a.keyword_id, a.ad_group_id, a.target_text, a.match_type, a.is_auto, a.is_pt,
  ROUND(a.current_bid, 2) AS current_bid,
  CAST(a.clk_w AS INT64) AS clicks_w, ROUND(a.sp_w, 2) AS spend_w, CAST(a.ord_w AS INT64) AS orders_w, a.roas_w,
  a.tcpc AS target_cpc, a.class,
  a.probing, a.inc_date AS probe_started, CAST(a.ep_clk AS INT64) AS probe_clicks, a.ep_roas AS probe_roas,
  CAST(a.clk7 AS INT64) AS clicks_7d, a.roas7 AS roas_7d,
  CAST(a.clk8_28 AS INT64) AS clicks_8_28, a.roas8_28 AS roas_8_28,
  ROUND(a.sp1, 2) AS spend_1d, ROUND(a.camp_sp1, 2) AS camp_spend_1d,
  CAST(a.clk1 AS INT64) AS clicks_1d, ROUND(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 2) AS roas_1d,
  CAST(a.clk2 AS INT64) AS clicks_prev2, ROUND(SAFE_DIVIDE(a.gp2, NULLIF(a.sp2, 0)), 2) AS roas_prev2,
  CAST(a.clk3 AS INT64) AS clicks_3d, ROUND(SAFE_DIVIDE(a.gp3, NULLIF(a.sp3, 0)), 2) AS roas_3d,
  CAST(a.clk4_14 AS INT64) AS clicks_4_14, ROUND(SAFE_DIVIDE(a.gp4_14, NULLIF(a.sp4_14, 0)), 2) AS roas_4_14,
  a.is_auto_campaign, a.camp_clk3 AS camp_clicks_3d, a.camp_roas_3d, a.camp_clk4_14 AS camp_clicks_4_14, a.camp_roas_4_14,
  a.camp_clk1 AS camp_clicks_1d, a.camp_roas_1d,
  a.camp_clk2 AS camp_clicks_prev2, a.camp_roas_prev2,
  CAST(a.camp_clk7 AS INT64) AS camp_clicks_7d, a.camp_roas7 AS camp_roas_7d,
  CAST(a.camp_clk8_28 AS INT64) AS camp_clicks_8_28, a.camp_roas8_28 AS camp_roas_8_28,
  a.pct_dark, a.capped, a.slots, a.seat_rank, a.is_defense, a.is_seasonal, a.is_research, a.seasonal_now,
  -- v27.48.2: settled-record keys (guard snapshot) — published for verification, and probe_rank
  -- reads settled_winner (the settled-first key extending the v27.38 profit ordering)
  a.g_settled_winner AS settled_winner, a.g_record_loser AS record_loser,
  -- v27.53: the window-scaled cut gate (item 3) + the wake step-down facts (item 7), published
  a.cut_gate, a.g_wake_due AS wake_due, a.g_wake_step_bid AS wake_step_bid,
  a.g_wake_clk AS wake_clicks, a.g_wake_date AS wake_date,
  -- ROLE (Ori 2026-08-02): the keyword's job in the campaign economy, one word.
  -- FUNDER pays for everything · WATCH earns but thin · PROBE mid-test · CANDIDATE next up
  -- · TRIAL gathering its 4 clicks · PARKED allowance-parked (can return) · RETIRED tested
  -- loser (permanent, seasonal revival exempts) · QUEUED beyond the seats · IDLE waiting
  CASE
    WHEN a.is_defense THEN 'DEFENSE'
    WHEN a.probing OR a.probe_done THEN 'PROBE'
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now AND NOT a.is_auto THEN 'RETIRED'
    WHEN a.is_auto THEN CASE
      WHEN SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.sp7 + a.sp8_28, 0)) >= 1.1 AND (a.clk7 + a.clk8_28) >= 4 THEN 'FUNDER'
      WHEN a.class IN ('WINNER', 'MARGINAL') THEN 'WATCH'
      -- evidence in + bid at the floor: it is an antenna now — alive cheap, terms are the info
      WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND COALESCE(a.current_bid, 0) <= 0.25 THEN 'ANTENNA'
      WHEN a.class = 'LOSER' THEN 'TRIAL' ELSE 'IDLE' END
    WHEN a.seat_rank > a.slots THEN 'QUEUED'
    -- FUNDER is judged on 28 DAYS (Ori 2026-08-02) — a stable financier, not a hot week;
    -- and it needs EVIDENCE: >= 4 clicks in the 28d ("only 1 click can't be funder")
    WHEN SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.sp7 + a.sp8_28, 0)) >= 1.1 AND (a.clk7 + a.clk8_28) >= 4 THEN 'FUNDER'
    WHEN a.class IN ('WINNER', 'MARGINAL') THEN 'WATCH'
    WHEN a.is_research AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp THEN 'ANTENNA'
    WHEN a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp THEN 'PARKED'
    WHEN a.class = 'LOSER' THEN 'TRIAL'
    WHEN a.class = 'IDLE' AND NOT a.is_auto AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season))
         AND a.cand_rank <= (IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) - a.active_probes) THEN 'CANDIDATE'
    ELSE 'IDLE'
  END AS role,

  -- HEALTHY-CAMPAIGN BUDGET RULE (Ori 2026-08-01 tuning, knob #5): the only budget move for a
  -- not-capped campaign is the loss cut — evidence window (W) AND today both under 0.6x ->
  -- -20% with the seasonal floor ($10 off / $15 peak). Raises belong to the dark ladder
  -- (a healthy campaign is not hitting its cap, a raise buys nothing).
  CASE
    -- DARK-AUTO LADDER (Ori 2026-08-02: "if dark > 0 then must be a raise or trim") — the OOB
    -- budget ladder, brought into the Auto section for its capped campaigns:
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) >= 1.2 AND COALESCE(a.camp_roas_prev2, 0) >= 1.5
      THEN ROUND(a.budget * IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 2.0, 1.5), 2)
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) >= 1.2
      THEN ROUND(a.budget * IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 1.5, 1.25), 2)
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) < 0.6 AND COALESCE(a.camp_roas_prev2, 0) < 0.6
        AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
      THEN ROUND(GREATEST(a.budget * 0.8, (SELECT IF(in_peak, 15.0, 10.0) FROM season)), 2)
    WHEN NOT a.is_defense AND NOT (a.is_auto_campaign AND a.capped) AND COALESCE(a.camp_roas_w, 0) < 0.6 AND COALESCE(a.camp_roas_1d, 0) < 0.6
        AND a.camp_sp > 0 AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
      THEN ROUND(GREATEST(a.budget * 0.8, (SELECT IF(in_peak, 15.0, 10.0) FROM season)), 2)
  END AS suggested_budget,
  CASE
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) >= 1.2 AND COALESCE(a.camp_roas_prev2, 0) >= 1.5
      THEN CONCAT('dark ', CAST(CAST(a.pct_dark AS INT64) AS STRING), '% while converting strong (today ', CAST(COALESCE(a.camp_roas_1d,0) AS STRING), 'x, prev-2d ', CAST(COALESCE(a.camp_roas_prev2,0) AS STRING), 'x) — raise the cap')
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) >= 1.2
      THEN CONCAT('dark ', CAST(CAST(a.pct_dark AS INT64) AS STRING), '% while converting (today ', CAST(COALESCE(a.camp_roas_1d,0) AS STRING), 'x) — raise the cap')
    WHEN a.is_auto_campaign AND a.capped AND COALESCE(a.camp_roas_1d, 0) < 0.6 AND COALESCE(a.camp_roas_prev2, 0) < 0.6
        AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
      THEN CONCAT('dark ', CAST(CAST(a.pct_dark AS INT64) AS STRING), '% AND losing both windows — cut 20%; the brakes trim the clicked clauses')
    WHEN NOT a.is_defense AND NOT (a.is_auto_campaign AND a.capped) AND COALESCE(a.camp_roas_w, 0) < 0.6 AND COALESCE(a.camp_roas_1d, 0) < 0.6
        AND a.camp_sp > 0 AND a.budget > (SELECT IF(in_peak, 15.0, 10.0) FROM season)
      THEN CONCAT('W ', CAST(COALESCE(a.camp_roas_w,0) AS STRING), 'x AND today ',
                   CAST(COALESCE(a.camp_roas_1d,0) AS STRING), 'x — both losing → cut 20% (floor $',
                   CAST(CAST((SELECT IF(in_peak, 15, 10) FROM season) AS INT64) AS STRING), ')')
  END AS budget_reason,
  CASE
    WHEN a.is_defense THEN 'DEFENSE'
    -- v27.53 ITEM 8c (second door): the PROBE verdict must not resurface a CONFIRM_PARK row
    -- either. Measured 2026-08-12: 'teenager girl gift ideas' — reverdict CONFIRM_PARK, a
    -- settled-verified retirement — was emitting WINNER_FOUND off ONE click at 14.27x. Falls
    -- through to the probe_done PARK below, which is what a confirmed park should do.
    WHEN a.probe_done AND NOT a.confirm_park AND (COALESCE(a.ep_roas, 0) >= 1.0
         -- v27.27 (Ori 2026-08-06: "it seems like it is profitable"). The probe window is a
         -- NARROW recent measurement, and ads sales restate for days (spend ~D+3, sales to
         -- D+7 SP / D+14 SB) -- so a probe reads 0x while the keyword's real windows are
         -- healthy. Measured: 'gifts for 12 year old girls' probe 37c at 0.00x vs 146c at
         -- 2.12x (7d) and 239c at 1.11x (8-28d) -- and it was being PARKED to $0.25.
         -- A probe verdict may never park a keyword its own evidence window says is winning.
                      OR COALESCE(a.roas_w, 0) >= 1.0) THEN 'WINNER_FOUND'
    WHEN a.probe_done AND a.is_auto THEN 'AUTO_TRIM'
    WHEN a.probe_done THEN 'PARK'
    -- STARVING PROBE (Ori 2026-08-04, "if last day probe is with less than 2 clicks need to
    -- raise it to 1 bid"): under 2 clicks/day the 20-click verdict never arrives — lift to $1.
    -- v27.70 (reviewer A, 2026-08-16): mirror the v27.69 bid arm's predicate — the entry prices
    -- only a RAISE, so when the entry lands at/below the current bid the bid arm emits NULL and
    -- this action must fall through too (PROBE_ADJUST is v27.29-exempt: without the gate it
    -- published an action with no bid — an empty promise).
    WHEN a.probing AND a.clk1 < 2 AND COALESCE(a.current_bid, 0) < 0.95
         AND ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
             > COALESCE(a.current_bid, 0) + 0.005 THEN 'PROBE_ADJUST'
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0 THEN 'PROBE_ADJUST'
    WHEN a.probing THEN 'PROBE_WAIT'
    -- v27.26 (Ori 2026-08-06: "if last day it was profitable and last 7 days doesnt, do not
    -- change anything. maybe we start a wave. when a not profitable day will occur you can
    -- check the 7 days again and decide what to do"). A profitable LAST DAY vetoes every
    -- window-driven move -- up or down. The window is history; a profitable day inside a
    -- losing window may be the turn, and cutting it kills the wave before it forms. Wait
    -- for an unprofitable day, THEN re-read the window and act.
    WHEN COALESCE(a.clk1, 0) >= 1 AND COALESCE(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 0) >= 1.0
         AND COALESCE(a.roas_w, 0) < 1.0
      THEN 'HOLD'
    -- tested loser (>=15 clicks/90d, no sale): permanent park — its seat frees for the next test
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now AND NOT a.is_auto THEN IF(COALESCE(a.current_bid, 0) > 0.30, 'PARK', 'IDLE')
    -- SEAT MECHANISM (Ori 2026-08-01): beyond the budget/$4 seats -> queue at $0.25
    WHEN a.seat_rank > a.slots AND NOT a.is_auto THEN IF(COALESCE(a.current_bid, 0) > 0.30, 'PARK_WAIT', 'IDLE')
    -- SEASON RAMP (Ori 2026-08-02): its season is arriving (seasonal_now) and the bid sits
    -- under 60% of the current LY-anchored target — glide UP toward target by max(+10%, +5c),
    -- never above it from this rule. WINNER/MARGINAL only (orders prove the season is real);
    -- losers re-enter through the probe path at 1.5x target instead.
    -- v27.11 (Ori 2026-08-04, "why it is not raised toward target?"): the mirror of
    -- EASE_TO_TARGET — a WINNER earning below its target price glides UP toward it, max(+10%, +5c),
    -- never past it (the target is the LY/band market price — the built-in ceiling). Not
    -- while capped (never raise into dark), not autos (own doctrine), not defense.
    WHEN a.class = 'WINNER' AND NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < a.tcpc - 0.05 THEN 'RAISE_TO_TARGET'
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc THEN 'RAISE_TO_TARGET'
    -- BREAKEVEN CUT (Ori 2026-08-03): a keyword with >= 30 clicks over 28d IS decidable at its
    -- own grain — and its economics name the bid: margin per sale ÷ clicks per sale = 28d
    -- profit per click ("30 clicks per sale x $3 margin -> bid $0.10"). Poor 28d net ROAS
    -- (< 1.0) with the bid above that breakeven -> cut TO it (floor $0.02). Outranks the
    -- volume lift and research ease — accumulated keyword evidence beats both.
    -- v27.12 (Ori 2026-08-04): breakeven economics moved to the W WINDOW (7d off / 3d peak;
    -- low tiers' W is already 3d) and softened to a GLIDE — -10%/day toward the window's
    -- profit-per-click, floor $0.15. Zero-profit windows still park $0.25.
    -- v27.55 (Ori 2026-08-13, on 'gift for teen girl': "the decision is good — gentle cut for it
    -- till we find a profitable converting CPC"): the STEP was already gentle; the DESTINATION was
    -- wrong. Per-click worth was computed from the W window alone, so that row glided toward $0.20
    -- priced off 58 clicks while its 8-28d window held 1,259 clicks at 0.81x — it would sail past
    -- the price where the keyword actually converts and grind on to the $0.15 floor, losing the
    -- volume. The destination is now POOLED 1-28d evidence (gp7+gp8_28 over clk7+clk8_28): the
    -- maximum-likelihood per-click worth over everything we have, which is what "find the
    -- profitable converting CPC" means. Pooling a keyword's own two disjoint windows needs no
    -- shrinkage constant — same keyword, the windows simply add. Spans 1-28d via clk7 (not clk_w)
    -- so the destination does not move when the peak window flips 7d -> 3d. The -10%/day step and
    -- the $0.15 floor are unchanged; a genuinely deteriorating keyword still walks down, to the
    -- right place.
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND a.gp_w_raw <= 0 AND COALESCE(a.current_bid, 0) > 0.30 THEN 'PARK'
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND COALESCE(a.roas_w, 0) < 1.0 AND a.gp_w_raw > 0
         AND SAFE_DIVIDE(a.sp7 + a.sp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) > SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) * 1.05 AND COALESCE(a.current_bid, 0) > 0.17 THEN 'CUT_TO_BREAKEVEN'
    -- VOLUME FLOOR (Ori 2026-08-03): under ~30 clicks/week a campaign cannot decide anything —
    -- classes are noise. Seated keywords below the entry anchor LIFT to it (max($1, min(1.5x
    -- target, $2))) to buy decision-grade traffic; parks/cuts above are volume-gated.
    WHEN NOT a.is_auto AND NOT a.capped AND IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), COALESCE(a.camp_clk3, 0) < 13, COALESCE(a.camp_clk7, 0) < 30) AND NOT a.is_defense AND a.seat_rank <= a.slots
         AND (a.clk7 + a.clk8_28) < 30 AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2) THEN 'VOLUME_LIFT'
    -- NUDGE_UP (Ori 2026-08-04, "no clicks need a nudge up"): a seated low-tier keyword with
    -- essentially no clicks (under the 10-click day bar over 1d+prev-2d) is priced out of
    -- visibility — no clicks, no evidence, stuck. Nudge +5%/day toward the entry anchor.
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND (a.clk1 + a.clk2) < 10
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2) THEN 'NUDGE_UP'
    -- v27.21 (Ori 2026-08-06): in the 7d / 8-28d strategies a SILENT keyword is the trigger.
    -- A seated, active keyword that is buying no clicks is priced out of the auction, so the
    -- very windows it is judged on can never refresh -- they just age. Same +5%/day nudge as
    -- the low tier.
    -- v27.98 (Ori 2026-08-21): SILENCE IS NOW MEASURED ON COMPLETE DAYS. Through v27.97 the
    -- gate was the filling day alone -- the one window in this file that ended AT the
    -- watermark, on a day that is only 88-90% loaded when the engine runs. Measured: 13.1% of
    -- steady clickers read zero on the filling day purely on arrival timing, so roughly one
    -- seated keyword in eight was eligible on any given morning and the proposal did not
    -- survive an hour: two of the four live rows flipped back to KEEP when a late click
    -- landed. It also made the sentence untrue -- it said "never enters the auction" about a
    -- keyword that had clicked on all seven preceding days. The gate is now the three
    -- COMPLETE days ending the day before the watermark, the same span the reason names, and
    -- the filling day keeps its house role: a one-way veto that may never drive a move.
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND COALESCE(a.clk3, 0) = 0
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN 'NUDGE_UP'
    -- AUTO RAISE (Ori 2026-08-02, "why is this not raised"): the third auto lever — increase
    -- bids when performance is good. Winner clause with real evidence, campaign not capped:
    -- +15%/day toward the $2 cap. (While capped, the budget raise is the lever, never the bid.)
    -- AUTO_BRAKE (Ori 2026-08-02): while a campaign caps, every clicked non-winner clause
    -- steps down max(5%, 30% x dark)/day — dark must produce a raise or a trim, never a hold
    -- LOW-BUDGET AUTO DAY RULES (Ori 2026-08-04, BOTTLE-SP/AUTO): "in auto low budget you
    -- should focus on short term windows (prev day, 2-3 prev days) and react base on it."
    -- Converted yesterday (>=3 clicks, net profit) -> raise a bit (+5%, cap $2). No profit
    -- yesterday AND prev-2d on >=10 combined clicks -> trim a bit (-5%, floor $0.20). A
    -- conversion in EITHER window blocks the trim. These outrank the weekly auto rules and
    -- the capped mechanics — the budget ladder owns the cap, the bid follows yesterday.
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.clk1 >= 1 AND a.gp1 > a.sp1 AND COALESCE(a.current_bid, 0) < 2.00 THEN 'AUTO_DAY_RAISE'
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.gp1 <= 0 AND a.gp2 <= 0 AND (a.clk1 + a.clk2) >= 10
         AND ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2) < COALESCE(a.current_bid, 0) THEN 'AUTO_DAY_TRIM'
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class = 'WINNER' AND a.clk1 >= 4
         AND COALESCE(a.current_bid, 0) > SAFE_DIVIDE(a.sp1, NULLIF(a.clk1, 0)) + 0.05 THEN 'AUTO_FIT'
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class != 'WINNER' AND a.clk1 >= 1 AND COALESCE(a.current_bid, 0) > 0.25 THEN 'AUTO_BRAKE'
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'WINNER' AND a.clk_w >= 4 AND NOT a.capped AND COALESCE(a.current_bid, 0) < 2.00 THEN 'AUTO_RAISE'
    -- LOW-AUTO FALLBACK (Ori 2026-08-04: "make sure auto low budget is not using 7 days
    -- window at all"): anything the day rules didn't decide HOLDS — no weekly class verdicts.
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) THEN IF(a.clk1 + a.clk2 > 0, 'KEEP', 'IDLE')
    WHEN a.class = 'WINNER' THEN 'KEEP'
    -- AUTO DOCTRINE (Ori 2026-08-02): 4 fixed clauses — never parked; underperformers TRIM
    -- -15%/day (floor $0.30), the real lever is negating bad terms; targets are advisory here.
    -- AUTO_NUDGE (Ori 2026-08-04, BUNNY Brave close-match): on starving clicks (under the
    -- 30-click weekly floor) a trim compounds into silence — fewer impressions, no new evidence,
    -- stuck. If the clause CONVERTED in the last 3 days, feed the signal instead: +5%/day.
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.clk_w < 30 AND NOT a.capped
         AND (a.gp1 > 0 OR a.gp3 > 0) AND COALESCE(a.current_bid, 0) < 2.00 THEN 'AUTO_NUDGE'
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND COALESCE(a.current_bid, 0) > 0.25
         -- v27.22 (Ori 2026-08-06: "the keyword already stuck"): do NOT trim a clause that
         -- took ZERO clicks yesterday. It is already out of the auction, so the trim has
         -- nothing left to achieve -- it only entrenches the invisibility that the last-day
         -- click gate (v27.21) exists to detect. No clicks yesterday => HOLD, not a cut.
         AND COALESCE(a.clk1, 0) >= 1 THEN 'AUTO_TRIM'
    WHEN a.is_auto THEN IF(a.class = 'MARGINAL', 'KEEP', IF(a.class = 'LOSER', 'KEEP_TAIL', 'IDLE'))
    -- target < bid (Ori 2026-08-01): MARGINAL glides -5%/day toward target; LOSING goes straight
    -- TO the target bid. Winners are never pulled down.
    WHEN a.class = 'MARGINAL' AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN 'EASE_TO_TARGET'
    WHEN a.class = 'MARGINAL' THEN 'KEEP'
    -- 4-CLICK TRIAL GATE (Ori 2026-08-02, FRESH-SP/BROAD BTS case): "1 click do not break" —
    -- a loser can only be allowance-parked or cut-to-target once it has >= 4 clicks in W (the
    -- same evidence bar as TRIM). Under that it is still in its trial: KEEP_TAIL, keep gathering.
    -- (Without the gate, a day-1 campaign's 20% allowance is cents and first clicks park instantly.)
    WHEN a.is_research AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.35 THEN 'RESEARCH_EASE'
    WHEN a.class = 'LOSER' AND a.clk_w >= IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 10, 4) AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30 THEN 'PARK'
    WHEN a.class = 'LOSER' AND a.clk_w >= IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 10, 4) AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN 'CUT_TO_TARGET'
    WHEN a.class = 'LOSER' THEN 'KEEP_TAIL'
    -- v27.98 (Ori 2026-08-21): THE ENTRY MAY ONLY RAISE — the guard the sibling arm has had
    -- since v27.70, ported here. The doctrine is stated in the bid arm below and was being
    -- broken by this one: three live rows said 'lift to $0.54' / 'lift to $0.83' while
    -- CUTTING the bid 17-46%, because the candidate arm priced the anchored entry
    -- unconditionally and these keywords were already sitting above it at the legacy $1.00.
    -- A verb that contradicts its own sign is not a wording problem: the entry is not a
    -- trim, and pricing a probe DOWN on entry is the trim ladders' business. Predicate
    -- mirrored across action / value / sentence so the three can never disagree.
    WHEN a.class = 'IDLE' AND NOT a.is_auto AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) AND a.cand_rank <= (IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) - a.active_probes)

         AND ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
             > COALESCE(a.current_bid, 0) + 0.005
         THEN 'PROBE_START'
    ELSE 'IDLE'
  END AS action,
  CASE
    WHEN a.is_defense THEN NULL
    -- v27.53 ITEM 8c (second door): the PROBE verdict must not resurface a CONFIRM_PARK row
    -- either. Measured 2026-08-12: 'teenager girl gift ideas' — reverdict CONFIRM_PARK, a
    -- settled-verified retirement — was emitting WINNER_FOUND off ONE click at 14.27x. Falls
    -- through to the probe_done PARK below, which is what a confirmed park should do.
    WHEN a.probe_done AND NOT a.confirm_park AND (COALESCE(a.ep_roas, 0) >= 1.0
         -- v27.27 (Ori 2026-08-06: "it seems like it is profitable"). The probe window is a
         -- NARROW recent measurement, and ads sales restate for days (spend ~D+3, sales to
         -- D+7 SP / D+14 SB) -- so a probe reads 0x while the keyword's real windows are
         -- healthy. Measured: 'gifts for 12 year old girls' probe 37c at 0.00x vs 146c at
         -- 2.12x (7d) and 239c at 1.11x (8-28d) -- and it was being PARKED to $0.25.
         -- A probe verdict may never park a keyword its own evidence window says is winning.
                      OR COALESCE(a.roas_w, 0) >= 1.0)
      -- v27.31 (Ori 2026-08-06): "never shelve a winner" (v27.27) must not also mean "never
      -- PRICE a winner". Returning a bare NULL here swallowed RAISE_TO_TARGET: the action
      -- CASE still said raise, the value CASE said nothing, and the v27.29 no-op guard then
      -- resolved it to HOLD. Repro: 'teen girl gifts trendy stuff', 18c at 4.49x on a $0.15
      -- bid with a $0.31 target. A proven winner still under its target gets the normal
      -- glide -- max(+10%, +$0.05) capped at target; everything else still holds untouched.
      THEN IF(NOT a.is_auto AND NOT a.is_defense AND NOT a.capped AND a.tcpc IS NOT NULL
              AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < a.tcpc - 0.05,
              ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2),
              NULL)
    WHEN a.probe_done AND a.is_auto THEN ROUND(GREATEST(a.current_bid * 0.85, 0.20), 2)
    WHEN a.probe_done THEN 0.25
    -- v27.69 (Task 2.2): the probe ENTRY prices from the anchor when one exists — 1.5x target CPC
    -- (LY / band), else the campaign winners' CPC, else (genuinely anchorless) the old $1.00.
    -- Floor $0.31 (the revive floor — a real bid, never the platform-min trap), cap $2.00. Only a
    -- RAISE may come out of this arm: an anchored entry at/below the current bid emits NULL (the
    -- probe is already priced; cutting it is the trim ladders' business, never the entry's).
    -- DOCTRINE SUCCESSION, recorded: the flat $1.00 was Ori 2026-08-02 "i wont move if not";
    -- the Aug-9 post-mortem re-judged it — "real defect = $1.00 activation floor" — and Task 2.2
    -- encodes the newer verdict. Anchorless rows keep $1.00: with no clearing price to read, a
    -- deliberate overbid buys the first data fastest (the wake-step prices it DOWN after).
    WHEN a.probing AND a.clk1 < 2 AND COALESCE(a.current_bid, 0) < 0.95
      THEN IF(ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
                > COALESCE(a.current_bid, 0) + 0.005,
              ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2), NULL)
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0 THEN ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2)
    WHEN a.probing THEN NULL
    -- v27.26 (Ori 2026-08-06: "if last day it was profitable and last 7 days doesnt, do not
    -- change anything. maybe we start a wave. when a not profitable day will occur you can
    -- check the 7 days again and decide what to do"). A profitable LAST DAY vetoes every
    -- window-driven move -- up or down. The window is history; a profitable day inside a
    -- losing window may be the turn, and cutting it kills the wave before it forms. Wait
    -- for an unprofitable day, THEN re-read the window and act.
    WHEN COALESCE(a.clk1, 0) >= 1 AND COALESCE(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 0) >= 1.0
         AND COALESCE(a.roas_w, 0) < 1.0
      THEN NULL
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now AND NOT a.is_auto THEN IF(COALESCE(a.current_bid, 0) > 0.30, 0.25, NULL)
    WHEN a.seat_rank > a.slots AND NOT a.is_auto THEN IF(COALESCE(a.current_bid, 0) > 0.30, 0.25, NULL)
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)
    WHEN a.class = 'WINNER' AND NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < a.tcpc - 0.05
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND a.gp_w_raw <= 0 AND COALESCE(a.current_bid, 0) > 0.30 THEN 0.25
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND COALESCE(a.roas_w, 0) < 1.0 AND a.gp_w_raw > 0
         AND SAFE_DIVIDE(a.sp7 + a.sp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) > SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) * 1.05 AND COALESCE(a.current_bid, 0) > 0.17
      -- v27.55: the floor is the platform floor only. The per-click worth is a CPC-scale
      -- quantity and must NOT be used as a bid floor (that is the v27.40 units trap): a bid of
      -- $0.36 does not buy a $0.36 click. The loop finds the price instead — step -10%/day and
      -- stop when the row's REALIZED CPC falls to its per-click worth, which is exactly
      -- "gentle cut till we find a profitable converting CPC".
      THEN ROUND(GREATEST(a.current_bid * 0.90, 0.15), 2)
    WHEN NOT a.is_auto AND NOT a.capped AND IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), COALESCE(a.camp_clk3, 0) < 13, COALESCE(a.camp_clk7, 0) < 30) AND NOT a.is_defense AND a.seat_rank <= a.slots
         AND (a.clk7 + a.clk8_28) < 30
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND (a.clk1 + a.clk2) < 10
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2)
    -- v27.21 (Ori 2026-08-06): in the 7d / 8-28d strategies a SILENT keyword is the trigger.
    -- A seated, active keyword that is buying no clicks is priced out of the auction, so the
    -- very windows it is judged on can never refresh -- they just age. Same +5%/day nudge as
    -- the low tier.
    -- v27.98 (Ori 2026-08-21): SILENCE IS NOW MEASURED ON COMPLETE DAYS. Through v27.97 the
    -- gate was the filling day alone -- the one window in this file that ended AT the
    -- watermark, on a day that is only 88-90% loaded when the engine runs. Measured: 13.1% of
    -- steady clickers read zero on the filling day purely on arrival timing, so roughly one
    -- seated keyword in eight was eligible on any given morning and the proposal did not
    -- survive an hour: two of the four live rows flipped back to KEEP when a late click
    -- landed. It also made the sentence untrue -- it said "never enters the auction" about a
    -- keyword that had clicked on all seven preceding days. The gate is now the three
    -- COMPLETE days ending the day before the watermark, the same span the reason names, and
    -- the filling day keeps its house role: a one-way veto that may never drive a move.
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND COALESCE(a.clk3, 0) = 0
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2)
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.clk1 >= 1 AND a.gp1 > a.sp1 AND COALESCE(a.current_bid, 0) < 2.00
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.01), 2.00), 2)
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.gp1 <= 0 AND a.gp2 <= 0 AND (a.clk1 + a.clk2) >= 10
         AND ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2) < COALESCE(a.current_bid, 0)
      THEN ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2)
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class = 'WINNER' AND a.clk1 >= 4
         AND COALESCE(a.current_bid, 0) > SAFE_DIVIDE(a.sp1, NULLIF(a.clk1, 0)) + 0.05
      THEN ROUND(GREATEST(a.current_bid * 0.95, SAFE_DIVIDE(a.sp1, NULLIF(a.clk1, 0))), 2)
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class != 'WINNER' AND a.clk1 >= 1 AND COALESCE(a.current_bid, 0) > 0.25
      -- v27.46 A4: brake magnitude scaled by the clause's own 90d record — proven (>= 1.0x)
      -- eases the flat -5% minimum; middling (0.6-1.0x) max(5%, 15% x dark); losing / no data
      -- keeps max(5%, 30% x dark). Dark is never a hold: the 5% minimum and $0.20 floor stand.
      THEN ROUND(GREATEST(a.current_bid * LEAST(0.95,
                    CASE WHEN COALESCE(a.roas90, 0) >= 1.0 THEN 0.95
                         WHEN a.roas90 >= 0.6 THEN 1 - 0.15 * a.pct_dark / 100
                         ELSE 1 - 0.30 * a.pct_dark / 100 END), 0.20), 2)
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'WINNER' AND a.clk_w >= 4 AND NOT a.capped AND COALESCE(a.current_bid, 0) < 2.00
      THEN ROUND(LEAST(a.current_bid * 1.15, 2.00), 2)
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) THEN NULL
    -- v27.30 (Ori 2026-08-06): RAISE_TO_TARGET emitted NO VALUE. The action CASE fires it
    -- early, but in the VALUE case the bare `class = WINNER -> NULL` below short-circuited
    -- every winner before the raise branch (further down) could ever price it. Repro:
    -- 'teen girl gifts trendy stuff' -- 18c at 4.49x on a $0.15 bid, $0.31 target, action
    -- RAISE_TO_TARGET, suggested_bid NULL. Hoisting the raise above the catch-all fixes it:
    -- max(+10%, +$0.05) capped at the target = $0.20, which is also its own realized CPC
    -- ($3.47/18 clicks) -- a price it has already proven it clears.
    WHEN a.class = 'WINNER' AND NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < a.tcpc - 0.05
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc
      THEN ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)
    WHEN a.class = 'WINNER' THEN NULL
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.clk_w < 30 AND NOT a.capped
         AND (a.gp1 > 0 OR a.gp3 > 0) AND COALESCE(a.current_bid, 0) < 2.00
      THEN ROUND(LEAST(a.current_bid * 1.05, 2.00), 2)
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND COALESCE(a.current_bid, 0) > 0.25
         -- v27.22 (Ori 2026-08-06: "the keyword already stuck"): do NOT trim a clause that
         -- took ZERO clicks yesterday. It is already out of the auction, so the trim has
         -- nothing left to achieve -- it only entrenches the invisibility that the last-day
         -- click gate (v27.21) exists to detect. No clicks yesterday => HOLD, not a cut.
         AND COALESCE(a.clk1, 0) >= 1
      THEN ROUND(GREATEST(a.current_bid * 0.85, 0.20), 2)
    WHEN a.is_auto THEN NULL
    WHEN a.class = 'MARGINAL' AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN ROUND(GREATEST(a.current_bid * 0.95, a.tcpc), 2)
    WHEN a.class = 'MARGINAL' THEN NULL
    WHEN a.is_research AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.35
      THEN ROUND(GREATEST(a.current_bid * 0.85, 0.30), 2)
    WHEN a.class = 'LOSER' AND a.clk_w >= IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 10, 4) AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30 THEN 0.25
    WHEN a.class = 'LOSER' AND a.clk_w >= IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 10, 4) AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05 THEN a.tcpc
    WHEN a.class = 'LOSER' THEN NULL
    WHEN a.class = 'IDLE' AND NOT a.is_auto AND NOT a.capped AND a.seat_rank <= a.slots
         AND a.active_probes < IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) AND a.cand_rank <= (IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) - a.active_probes)

         AND ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
             > COALESCE(a.current_bid, 0) + 0.005
      -- $1 SEAT-ENTRY FLOOR (Ori 2026-08-02: "i wont move if not") — also the anchorless entry:
      -- no LY target, no band, no winner CPC -> enter at the $1 floor instead of never starting.
      -- v27.98: guarded — an anchored entry at or below the current bid emits NULL, exactly as
      -- the arm's own doctrine (three lines up in the header of the probe block) already said.
      THEN ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
    ELSE NULL
  END AS suggested_bid,
  CASE
    WHEN a.is_defense THEN 'brand defense — the moat is bought at whatever it costs; bids run on the coacher defense mode, never parked by ROAS'
    -- v27.53 ITEM 8c (second door): the PROBE verdict must not resurface a CONFIRM_PARK row
    -- either. Measured 2026-08-12: 'teenager girl gift ideas' — reverdict CONFIRM_PARK, a
    -- settled-verified retirement — was emitting WINNER_FOUND off ONE click at 14.27x. Falls
    -- through to the probe_done PARK below, which is what a confirmed park should do.
    WHEN a.probe_done AND NOT a.confirm_park AND (COALESCE(a.ep_roas, 0) >= 1.0
         -- v27.27 (Ori 2026-08-06: "it seems like it is profitable"). The probe window is a
         -- NARROW recent measurement, and ads sales restate for days (spend ~D+3, sales to
         -- D+7 SP / D+14 SB) -- so a probe reads 0x while the keyword's real windows are
         -- healthy. Measured: 'gifts for 12 year old girls' probe 37c at 0.00x vs 146c at
         -- 2.12x (7d) and 239c at 1.11x (8-28d) -- and it was being PARKED to $0.25.
         -- A probe verdict may never park a keyword its own evidence window says is winning.
                      OR COALESCE(a.roas_w, 0) >= 1.0)
      THEN CONCAT('probe verdict: ', CAST(a.ep_clk AS STRING), ' clicks at ', CAST(COALESCE(a.ep_roas,0) AS STRING),
                  'x — WINNER found; joins the 80% pool, FIT/ROAS logic takes over')
    WHEN a.probe_done AND a.is_auto
      THEN CONCAT('probe verdict: ', CAST(a.ep_clk AS STRING), ' clicks at ', CAST(COALESCE(a.ep_roas,0) AS STRING),
                  'x — auto clause is never parked: trim -15%/day and negate its bad terms')
    WHEN a.probe_done
      THEN CONCAT('probe verdict: ', CAST(a.ep_clk AS STRING), ' clicks at ', CAST(COALESCE(a.ep_roas,0) AS STRING),
                  'x — not profitable, park $0.25 and promote the next candidate')
    -- v27.70 (reviewer A): same gate as the action/bid arms, and the reason prints the ACTUAL
    -- anchored entry value — never 'the $1 entry floor' (the entry is 1.5x target CPC / winners'
    -- CPC / $1 only when genuinely anchorless).
    WHEN a.probing AND a.clk1 < 2 AND COALESCE(a.current_bid, 0) < 0.95
         AND ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
             > COALESCE(a.current_bid, 0) + 0.005
      THEN CONCAT('probe starving — ', CAST(a.clk1 AS STRING), ' click(s) yesterday at $', FORMAT('%.2f', COALESCE(a.current_bid, 0)),
                  ': lift to the $', FORMAT('%.2f', ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)),
                  ' entry so the 20-click verdict (', CAST(a.ep_clk AS STRING), '/20 so far) actually arrives')
    WHEN a.probing AND a.clk1 > 6 AND a.ep_ord = 0
      THEN CONCAT('probing (', CAST(a.ep_clk AS STRING), '/20 clicks) — 6+ clicks yesterday, no sale yet: -5% daily descent')
    WHEN a.probing
      THEN CONCAT('probing (', CAST(a.ep_clk AS STRING), '/20 clicks since ', CAST(a.inc_date AS STRING), ') — let the test run')
    -- v27.26 (Ori 2026-08-06: "if last day it was profitable and last 7 days doesnt, do not
    -- change anything. maybe we start a wave. when a not profitable day will occur you can
    -- check the 7 days again and decide what to do"). A profitable LAST DAY vetoes every
    -- window-driven move -- up or down. The window is history; a profitable day inside a
    -- losing window may be the turn, and cutting it kills the wave before it forms. Wait
    -- for an unprofitable day, THEN re-read the window and act.
    WHEN COALESCE(a.clk1, 0) >= 1 AND COALESCE(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 0) >= 1.0
         AND COALESCE(a.roas_w, 0) < 1.0
      THEN CONCAT('profitable yesterday (', CAST(CAST(a.clk1 AS INT64) AS STRING), 'c at ',
                  FORMAT('%.2f', COALESCE(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 0)), 'x) while the window is ',
                  FORMAT('%.2f', COALESCE(a.roas_w, 0)), 'x — hold everything: this may be the start of a wave. The window decides again on the next unprofitable day.')
    WHEN a.clk90 >= 15 AND a.ord90 = 0 AND NOT a.seasonal_now AND NOT a.is_auto
      THEN CONCAT('tested ', CAST(a.clk90 AS STRING), ' clicks/90d with 0 orders — permanent park; its seat goes to the next candidate')
    WHEN a.seat_rank > a.slots AND NOT a.is_auto
      THEN CONCAT('queue #', CAST(a.seat_rank - a.slots AS STRING), ' — ', CAST(a.slots AS STRING),
                  ' seats (budget ÷ $4); its test resumes when a seat frees')
    WHEN a.class IN ('WINNER','MARGINAL') AND a.seasonal_now AND a.tcpc IS NOT NULL
         AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < 0.60 * a.tcpc
      -- v27.98: same step, same fix as the winner arm below — the printed percentage is derived
      -- from the price this row actually proposes, not from a nominal 10%.
      THEN CONCAT('SEASON RAMP — its season is arriving and the bid is under 60% of the current target $',
                  FORMAT('%.2f', a.tcpc), ': raise ',FORMAT('%+.1f', SAFE_DIVIDE(ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2) - a.current_bid, NULLIF(a.current_bid, 0)) * 100), '% to $',
                  FORMAT('%.2f', ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)),
                  ' (beyond target only via the coacher)')
    WHEN a.class = 'WINNER' AND NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > 0 AND a.current_bid < a.tcpc - 0.05
      -- v27.98 (Ori 2026-08-21): the PERCENTAGE IS BUILT FROM THE ROW. The sentence used to say a
      -- flat "+10%/day" while the step actually taken is the LARGER of +10% and +5c, capped at the
      -- target — so on every live row the nickel arm won and the move landed at +11.9% to +22.7%.
      -- The uploaded price was right each time; only the words were wrong, which is the failure
      -- that makes a correct engine look broken. Deriving the number from the same expression that
      -- prices the row means the two can never disagree again.
      THEN CONCAT('winner (', CAST(COALESCE(a.roas_w, 0) AS STRING), 'x) earning under its target price $',
                  FORMAT('%.2f', a.tcpc), ' — raise ',FORMAT('%+.1f', SAFE_DIVIDE(ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2) - a.current_bid, NULLIF(a.current_bid, 0)) * 100), '% to $',
                  FORMAT('%.2f', ROUND(LEAST(GREATEST(a.current_bid * 1.10, a.current_bid + 0.05), a.tcpc), 2)),
                  ' (never past target; beyond target only via the coacher)')
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND a.gp_w_raw <= 0 AND COALESCE(a.current_bid, 0) > 0.30
      THEN CONCAT(CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks this window with no net profit — park $0.25; the seat queue owns any comeback')
    WHEN a.class != 'WINNER' AND NOT a.is_auto AND NOT a.is_defense
         AND a.clk_w >= a.cut_gate
         AND COALESCE(a.roas_w, 0) < 1.0 AND a.gp_w_raw > 0
         AND SAFE_DIVIDE(a.sp7 + a.sp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) > SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.clk7 + a.clk8_28, 0)) * 1.05 AND COALESCE(a.current_bid, 0) > 0.17
      THEN CONCAT('under breakeven this window — ', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks at ',
                  FORMAT('%.2f', COALESCE(a.roas_w, 0)), 'x: glide -10%/day toward the per-click worth $',
                  CAST(ROUND(GREATEST(SAFE_DIVIDE(a.gp7 + a.gp8_28, NULLIF(a.clk7 + a.clk8_28, 0)), 0.15), 2) AS STRING), ' (floor $0.15)')
    WHEN NOT a.is_auto AND NOT a.capped AND IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), COALESCE(a.camp_clk3, 0) < 13, COALESCE(a.camp_clk7, 0) < 30) AND NOT a.is_defense AND a.seat_rank <= a.slots
         AND (a.clk7 + a.clk8_28) < 30
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season),
           CONCAT('campaign under the 13-click/3d decision floor (', CAST(COALESCE(a.camp_clk3, 0) AS STRING), 'c/3d) — lift to the entry anchor to buy decision data'),
           CONCAT('campaign under the 30-click/week decision floor (', CAST(COALESCE(a.camp_clk7, 0) AS STRING), 'c/7d) — lift to the entry anchor to buy decision data'))
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND (a.clk1 + a.clk2) < 10
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN CONCAT('invisible — ', CAST(CAST(a.clk1 + a.clk2 AS INT64) AS STRING), ' clicks over 3d at $', FORMAT('%.2f', COALESCE(a.current_bid, 0)),
                  ': the bid is priced out of the auction; nudge ', FORMAT('%+.1f', SAFE_DIVIDE(ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2) - a.current_bid, NULLIF(a.current_bid, 0)) * 100),
                  '% to $', FORMAT('%.2f', ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2)), ', walking toward the entry anchor $',
                  FORMAT('%.2f', ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), ' until it buys data')
    -- v27.21 (Ori 2026-08-06): in the 7d / 8-28d strategies a SILENT keyword is the trigger.
    -- A seated, active keyword that is buying no clicks is priced out of the auction, so the
    -- very windows it is judged on can never refresh -- they just age.
    -- v27.98 (Ori 2026-08-21): silence is measured on the three COMPLETE days, not the filling
    -- day, and the sentence below now says what is actually true -- the windows are aging out,
    -- not that the keyword never enters the auction (it clicked on all seven preceding days on
    -- the row that exposed this).
    WHEN NOT a.is_auto AND NOT a.is_defense AND NOT a.capped
         AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.seat_rank <= a.slots AND COALESCE(a.clk3, 0) = 0
         AND COALESCE(a.current_bid, 0) > 0.30 AND COALESCE(a.current_bid, 0) + 0.05 < ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
      THEN CONCAT('no clicks on the last three complete days at $', FORMAT('%.2f', COALESCE(a.current_bid, 0)),
                  ' while holding a seat — the windows this keyword is judged on are aging out with nothing fresh arriving to refresh them: nudge ',
                  FORMAT('%+.1f', SAFE_DIVIDE(ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2) - a.current_bid, NULLIF(a.current_bid, 0)) * 100), '% to $', FORMAT('%.2f', ROUND(LEAST(GREATEST(a.current_bid * 1.05, a.current_bid + 0.02), ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)), 2)),
                  ', walking toward the entry anchor $', FORMAT('%.2f', ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)))
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.clk1 >= 1 AND a.gp1 > a.sp1 AND COALESCE(a.current_bid, 0) < 2.00
      THEN CONCAT('converted yesterday — ', CAST(CAST(a.clk1 AS INT64) AS STRING), ' clicks, net +$', FORMAT('%.2f', a.gp1 - a.sp1), ': low-budget auto reacts daily, raise +5% (cap $2)')
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
         AND a.gp1 <= 0 AND a.gp2 <= 0 AND (a.clk1 + a.clk2) >= 10
         AND ROUND(GREATEST(a.current_bid * 0.95, 0.20), 2) < COALESCE(a.current_bid, 0)
      THEN CONCAT('no profit yesterday or prev-2d (', CAST(CAST(a.clk1 + a.clk2 AS INT64) AS STRING), ' clicks) — low-budget auto reacts daily: trim -5% (floor $0.20); negate the bad terms')
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class = 'WINNER' AND a.clk1 >= 4
         AND COALESCE(a.current_bid, 0) > SAFE_DIVIDE(a.sp1, NULLIF(a.clk1, 0)) + 0.05
      THEN CONCAT('selling while capped — fit toward the real CPC $', CAST(ROUND(SAFE_DIVIDE(a.sp1, NULLIF(a.clk1, 0)), 2) AS STRING), ': the budget raise buys volume, cheaper clicks buy more of it')
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.capped AND a.class != 'WINNER' AND a.clk1 >= 1 AND COALESCE(a.current_bid, 0) > 0.25
      THEN CONCAT('campaign ', CAST(CAST(a.pct_dark AS INT64) AS STRING), '% dark — brake ',
                  CAST(CAST(ROUND(100 * (1 - LEAST(0.95,
                    CASE WHEN COALESCE(a.roas90, 0) >= 1.0 THEN 0.95
                         WHEN a.roas90 >= 0.6 THEN 1 - 0.15 * a.pct_dark / 100
                         ELSE 1 - 0.30 * a.pct_dark / 100 END))) AS INT64) AS STRING),
                  '%/day (dark must produce a raise or a trim, never a hold',
                  CASE WHEN COALESCE(a.roas90, 0) >= 1.0 THEN '; 90d proven — minimum ease'
                       WHEN a.roas90 >= 0.6 THEN '; 90d 0.6-1.0x — half brake' ELSE '' END, ')')
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'WINNER' AND a.clk_w >= 4 AND NOT a.capped AND COALESCE(a.current_bid, 0) < 2.00
      THEN CONCAT('auto clause performing — ', CAST(COALESCE(a.roas_w, 0) AS STRING), 'x on ', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks: raise +15%/day toward $2 (good terms deserve more traffic)')
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.gp1 > 0
      THEN CONCAT('sold yesterday under spend (', FORMAT('%.2f', COALESCE(SAFE_DIVIDE(a.gp1, NULLIF(a.sp1, 0)), 0)), 'x net) — not a raise, not a cut: hold, tomorrow decides')
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.gp2 > 0
      THEN CONCAT('sold in prev-2d (', FORMAT('%.2f', COALESCE(SAFE_DIVIDE(a.gp2, NULLIF(a.sp2, 0)), 0)), 'x net) — day windows mixed: hold, tomorrow decides')
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND (a.clk1 + a.clk2) > 0
      THEN CONCAT(CAST(CAST(a.clk1 + a.clk2 AS INT64) AS STRING), ' clicks over 3d, no sales, under the 10-click day bar — gathering at daily grain')
    WHEN a.is_auto AND a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season)
      THEN 'quiet — no clicks yesterday or prev-2d'
    WHEN a.class = 'WINNER' THEN CONCAT('winner: ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x over ', CAST(CAST(IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND NOT a.is_defense, 3, (SELECT w_days FROM cap)) AS INT64) AS STRING), 'd — funds the campaign (est. net ROAS)')
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.clk_w < 30 AND NOT a.capped
         AND (a.gp1 > 0 OR a.gp3 > 0) AND COALESCE(a.current_bid, 0) < 2.00
      THEN CONCAT('converted in the last 3 days on starving clicks (', CAST(CAST(a.clk_w AS INT64) AS STRING), 'c this window, under the 30-click floor) — a trim would freeze it: nudge +5%/day so the sale can prove itself')
    WHEN a.is_auto AND a.budget > (SELECT IF(in_peak, 30.0, 20.0) FROM season) AND a.class = 'LOSER' AND a.clk_w >= 4 AND COALESCE(a.current_bid, 0) > 0.25
         -- v27.22 (Ori 2026-08-06: "the keyword already stuck"): do NOT trim a clause that
         -- took ZERO clicks yesterday. It is already out of the auction, so the trim has
         -- nothing left to achieve -- it only entrenches the invisibility that the last-day
         -- click gate (v27.21) exists to detect. No clicks yesterday => HOLD, not a cut.
         AND COALESCE(a.clk1, 0) >= 1
      THEN CONCAT('auto clause underperforming — ', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks at ', FORMAT('%.2f', COALESCE(a.roas_w, 0)), 'x this week (full evidence, over the 30-click floor): trim -15%/day (floor $0.20); the real lever is negating its bad terms')
    WHEN a.is_auto AND a.class = 'LOSER' AND a.clk_w >= 4
      THEN CONCAT('evidence in — ', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks this window with no profit and the bid already at the floor: negate its bad terms, nothing left to trim')
    WHEN a.is_auto AND a.class = 'LOSER' THEN 'auto clause in its 4-click trial — keep gathering; negate bad terms as they show'
    WHEN NOT a.is_auto AND NOT a.capped AND IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), COALESCE(a.camp_clk3, 0) < 13, COALESCE(a.camp_clk7, 0) < 30) AND a.class IN ('MARGINAL', 'LOSER') AND a.seat_rank <= a.slots
      THEN IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season),
           CONCAT('campaign under the 13-click/3d decision floor (', CAST(COALESCE(a.camp_clk3, 0) AS STRING), 'c/3d) — no window verdicts here; holding at the entry anchor'),
           CONCAT('campaign under the 30-click/week decision floor (', CAST(COALESCE(a.camp_clk7, 0) AS STRING), 'c/7d) — no window verdicts here; holding at the entry anchor'))
    WHEN a.class = 'MARGINAL' AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN CONCAT('marginal ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x with bid above target — glide -5%/day toward $', CAST(a.tcpc AS STRING))
    WHEN a.class = 'MARGINAL' THEN CONCAT('marginal: ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x — in the 80% pool, watch (est. net ROAS)')
    WHEN a.class = 'LOSER' AND a.clk_w < 4
      THEN CONCAT('still in its 4-click trial (', CAST(CAST(a.clk_w AS INT64) AS STRING), ' clicks so far) — 1 click does not break; keep gathering')
    WHEN a.is_research AND a.class = 'LOSER' AND a.clk_w >= 4 AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.35
      THEN 'research mode — the antenna stays alive: glide -15%/day, floor $0.30 (its winning terms seed new keywords)'
    WHEN a.class = 'LOSER' AND a.clk_w >= IF(a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season), 10, 4) AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.loser_cum_sp > (SELECT IF(in_peak, 0.40, 0.20) FROM season) * a.camp_sp AND COALESCE(a.current_bid, 0) > 0.30
      THEN CONCAT('loser beyond the ', CAST(CAST((SELECT IF(in_peak, 40, 20) FROM season) AS INT64) AS STRING), '% exploration budget — park $0.25 (spend goes to the winners)')
    WHEN a.class = 'LOSER' AND (a.budget <= (SELECT IF(in_peak, 30.0, 20.0) FROM season) OR COALESCE(a.camp_clk7, 0) >= 30) AND a.tcpc IS NOT NULL AND COALESCE(a.current_bid, 0) > a.tcpc + 0.05
      THEN CONCAT('losing at ', CAST(COALESCE(a.roas_w,0) AS STRING), 'x with bid above target — straight to the target bid $', CAST(a.tcpc AS STRING))
    WHEN a.class = 'LOSER' THEN CONCAT('loser inside the ', CAST(CAST((SELECT IF(in_peak, 40, 20) FROM season) AS INT64) AS STRING), '% allowance — keep gathering')
    WHEN a.class = 'IDLE' AND a.capped
      THEN 'idle — campaign capped (dark > 10%): probes held, a budget artifact not a bid problem'
    WHEN a.class = 'IDLE' AND a.seat_rank <= a.slots AND a.active_probes < IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) AND a.cand_rank <= (IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) - a.active_probes)

         AND ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)
             > COALESCE(a.current_bid, 0) + 0.005
      THEN CONCAT(IF(a.seasonal_now, 'SEASONAL REVIVAL (sold in this window last year) — ', ''), 'next probe candidate — lift to $',
                  CAST(ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2) AS STRING),
                  -- v27.70 (reviewer A): the label names the anchor that actually priced the
                  -- entry (the value CONCAT above) — the old CASE tested 1.5x tcpc >= $1 and
                  -- mislabeled every sub-$1 anchored entry as 'the $1 floor'.
                  ' (', CASE WHEN a.tcpc IS NOT NULL THEN '1.5x target CPC (floor $0.31)'
                             WHEN a.win_cpc IS NOT NULL THEN "the winners' avg CPC"
                             ELSE '$1 anchorless entry' END,
                  '), verdict at 20 clicks')
    -- v27.98: the candidate whose bid already clears the entry anchor. It keeps its seat and
    -- its place in the queue; there is simply nothing to upload, and the sentence says so
    -- rather than announcing a lift that is really a cut.
    WHEN a.class = 'IDLE' AND a.seat_rank <= a.slots AND a.active_probes < IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) AND a.cand_rank <= (IF(a.is_seasonal AND a.season_active, a.slots, (SELECT IF(in_peak, 4, 2) FROM season)) - a.active_probes)
      THEN CONCAT('next probe candidate, and its bid $', FORMAT('%.2f', COALESCE(a.current_bid, 0)),
                  ' already sits at or above the $', FORMAT('%.2f', ROUND(LEAST(GREATEST(COALESCE(1.5 * a.tcpc, a.win_cpc, 1.00), 0.31), 2.00), 2)),
                  ' entry price — the test runs at the price it already has; only the trim ladders may bring a bid down')
    ELSE 'idle — waiting for a probe slot'
  END AS reason,
  -- v27.76 (Task 4.9): same additive 90d pair as the SP arm above — positional twin of the UNION.
  CAST(a.clk90 AS INT64) AS clicks_90d, CAST(a.ord90 AS INT64) AS orders_90d
FROM sb_agg a
)
-- v27.37: bid_floor and probe_bid are internal working columns (per-format platform floor and the
-- anchored probe entry bid) — kept out of the published schema like bid_hold / bud_hold.
SELECT o.* EXCEPT (bid_hold, bud_hold, bid_floor, probe_bid) REPLACE (
  -- v27.46 A3: SEASONAL_NOW vs GATE PRECEDENCE — a mature same-context LOSS prior in
  -- PROBING/STOP strips the row's seasonal authority: the PUBLISHED seasonal_now flips FALSE so
  -- every downstream consumer treats it as non-seasonal. The winner exemption outranks (in-window
  -- winner, v27.28 bar: clicks_w >= 4 AND roas_w >= 1.0 — A2 doctrine), and BLOCK_CUT rows are
  -- structurally exempt (gate precedence: ENTRY_BLOCK is only emitted when BLOCK_CUT is not).
  -- The seasonal RAISE_TO_TARGET / funding actions were already blocked (STOP, v27.42) or
  -- allowance-clamped (PROBING, v27.43) below; the inner seat ordering limitation is documented
  -- in SEASON_CONTEXT_LEDGER.md §5.7.
  IF(cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state IN ('PROBING', 'STOP')
     AND NOT (COALESCE(o.clicks_w, 0) >= 4 AND COALESCE(o.roas_w, 0) >= 1.0),
     FALSE, o.seasonal_now) AS seasonal_now,
  -- ── OUTPUT GUARDS (Ori 2026-08-06 audit) ──────────────────────────────────────────
  -- C1 v27.28: a keyword its OWN evidence window calls a winner (>=4 clicks AND >=1.0x --
  -- the 4-click bar keeps 28x-on-one-click noise out) is never shelved. v27.27 fixed this
  -- only for probe_done; the audit found it leaking through PROBE_WAIT (15), PARK_WAIT (1)
  -- and IDLE (2) -- e.g. 'journal kit for girls' 157c at 1.39x being cut $0.75 -> $0.25.
  -- C2 v27.29: an action that PROMISES a bid change must carry a real one. The audit found
  -- 5 PARKs suggesting the bid they already have and 2 rows labelled cut/raise with no
  -- value at all -- pure bulksheet noise. No real move => HOLD.
  CASE
    -- v27.45 DEFER_OOB (top of the ladder — structural ownership outranks every verdict): the
    -- campaign is OOB-owned, so the out-of-budget engine owns its bids. The row stays visible
    -- but does not instruct. DEFENSE rows are exempt (defense bids belong to NEITHER engine).
    WHEN COALESCE(cs.is_oob_owned, FALSE) AND NOT o.is_defense THEN 'DEFER_OOB'
    -- v27.65 PARK DIRECTION GUARD (Task 1.5): a condemnation may NEVER raise the bid. Found live
    -- 2026-08-13 (3 rows recorded a raise as a park — a CUT_TO_BREAKEVEN whose breakeven price sat
    -- ABOVE the current bid published "cut to $X" where $X > current). Zero rows today, but the
    -- class is structural: any breakeven/park pricing arm can resolve upward whenever the current
    -- bid is already below its computed destination. If the row deserves a raise, a RAISE branch
    -- must say so in daylight — never a branch whose verb promises a cut. Same predicate in all
    -- three ladders (action / suggested_bid / reason), the file's no-drift rule.
    WHEN o.action IN ('PARK','CUT_TO_BREAKEVEN')
     AND o.suggested_bid IS NOT NULL AND o.suggested_bid > o.current_bid + 0.005 THEN 'HOLD'
    -- v27.53 ITEM 8c — a CONFIRM_PARK row may NOT resurface through the winner shield. CONFIRM_PARK
    -- is a SETTLED-VERIFIED retirement (V_PARK_REVERDICT re-read the 90d settled record and stood by
    -- the park); a 4-click unsettled window is exactly the evidence that verdict already outranks.
    -- Everywhere else in both engines CONFIRM_PARK sinks — this was the one door left open.
    WHEN (COALESCE(o.clicks_w, 0) >= 4 AND COALESCE(o.roas_w, 0) >= 1.0)
     AND COALESCE(rv.reverdict, '') NOT IN ('CONFIRM_PARK', 'REDUNDANT')
     AND o.action IN ('PARK','PARK_WAIT','IDLE','PROBE_WAIT') THEN 'WINNER_FOUND'
    -- v27.42 BLOCK_CUT (2026-08-08 calibration PASS): this context's settled record (>= 15c at
    -- >= 1.0x) vetoes every cut/park — including the park v27.34 is about to issue on a 4-click
    -- window loss (same-context settled evidence outranks the window read; documented choice,
    -- SEASON_CONTEXT_LEDGER.md §5.3). Sits below the v27.28 winner shield (which already keeps
    -- winners), above APPLIED_HOLD/v27.34. v27.26 wave-veto rows arrive here already HOLD, so
    -- there is no cut to veto — identical outcome, the wave reason is kept deliberately.
    WHEN cg.gate_action = 'BLOCK_CUT'
     AND (o.action IN ('PARK','PARK_WAIT','EASE_TO_TARGET','CUT_TO_TARGET','CUT_TO_BREAKEVEN','RESEARCH_EASE')
          OR ((COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')))
      THEN 'HOLD'
    WHEN bid_hold THEN 'APPLIED_HOLD'
    -- v27.48.2 MANUAL_HOLD (Cause 3): the last bid change is Ori's hand (source MANUAL, < 7d)
    -- — every suggestion is suppressed unless the settled record is catastrophic (< 0.6x on
    -- >= 10 settled clicks; the guard's manual_hold flag already carries the escape). Sits
    -- directly below APPLIED_HOLD: upload holds keep working exactly as before.
    -- v27.53 ITEM 8f: MANUAL_HOLD now sits BELOW the dark brakes. AUTO_BRAKE is the engine's
    -- dark-magnitude lever and doctrine is explicit — "dark is never a hold": a campaign burning
    -- its budget before the day ends must produce a raise or a trim, never a freeze. The hold
    -- protects Ori's PRICE decision, not the campaign's serving hours, so it must not swallow the
    -- brake. Every other suggestion is still suppressed exactly as before.
    WHEN COALESCE(g.manual_hold, FALSE) AND o.suggested_bid IS NOT NULL
     AND o.action NOT IN ('AUTO_BRAKE') THEN 'MANUAL_HOLD'
    -- v27.48 SETTLE VETO (SEASON_CONTEXT_LEDGER.md §7 — "no condemnation before settle"):
    -- an engine_immune row (revived off a proven settled record until 10 NEW settled clicks
    -- accrue, or carrying a manual change < 14d — Cause 3) is immune to PARK-class
    -- condemnations AND the v27.34 window-loss re-park (which judges clicks whose sales have
    -- not arrived — exactly Cause 1). EASE_TO_TARGET / RESEARCH_EASE / trims / brakes fall
    -- through and stay live: dark is never a hold, the veto blocks only condemnations.
    WHEN COALESCE(rv.engine_immune, FALSE)
     AND (o.action IN ('PARK','PARK_WAIT','CUT_TO_BREAKEVEN','CUT_TO_TARGET')
          OR ((COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')))
      THEN 'REVIVE_SETTLE_HOLD'
    -- v27.48.2 GENERAL SETTLE VETO (Cause 1): a condemnation — PARK / CUT_TO_BREAKEVEN /
    -- CUT_TO_TARGET or the v27.34 window-loss re-park — may fire only if (a) the condemning
    -- clicks are fully settled (guard settle_ok: no clicks in the last D+7 SP / D+14 SB) OR
    -- (b) the channel-aware settled 90d record corroborates (>= 10 settled clicks at < 1.0x,
    -- no season WIN prior). Else HOLD with the honest wave reason. PARK_WAIT (seat-queue
    -- mechanics, not a verdict) and every ease/brake stay live — dark is never a hold.
    -- ENTRY_BLOCK rows are exempt: season-gate precedence unchanged (STOP parks / PROBING
    -- allowance economics own those rows).
    WHEN (o.action IN ('PARK','CUT_TO_BREAKEVEN','CUT_TO_TARGET')
          OR ((COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')))
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND NOT COALESCE(g.settle_ok, TRUE)
     AND NOT (COALESCE(g.corroborated_loser, FALSE) AND NOT COALESCE(g.settle_amnesty, FALSE))
     AND NOT COALESCE(g.settle_deferral_expired, FALSE)
      THEN 'SETTLE_HOLD'
    -- v27.53 ITEM 4 — LONG_LEG_HOLD, the corroboration leg LIFT never had. V_OOB_BUDGET_PHASE has
    -- always required BOTH a short window AND a long settled window to agree before it cuts a
    -- budget, and that requirement does real work (measured 2026-08-12: 2 of 9 campaigns would cut
    -- on the short leg alone and are vetoed by the settled leg). LIFT's PARK and CUT_TO_BREAKEVEN
    -- condemned on the SHORT window alone — the least complete data the engine holds. Same rule
    -- now: the condemnation stands only if the LONG SETTLED WINDOW does not contradict it —
    -- the 8-28d window (>= 4 clicks; fully settled by construction, it ends at wm-7) at >= 1.0x.
    -- MEASURED AND REJECTED (2026-08-12): an earlier draft also let the guard's settled 90d record
    -- veto. That is stricter than PHASE and it over-braked — it held 3 cuts the recent settled
    -- window itself condemned ('teen girl essentials kit' 369c at 0.83x over 8-28d, 'journal for
    -- girls' 188c at 0.90x, 'journal kit for girls ages 8-12' 24c at 0.48x). A 90-day-old record
    -- is not a rebuttal when the recent settled window agrees with the short one. Both windows
    -- must AGREE — that is the whole rule, and it is exactly PHASE's.
    -- Deliberately narrower than the PHASE analogue in one way: PHASE's COALESCE(x, 0) treats
    -- NO DATA as a licence to cut. Here no long-window data simply fails to contradict, so a
    -- genuinely new keyword still condemns on its short window — the settle veto above is what
    -- guards that case, and stacking both would freeze new keywords entirely.
    -- Scope is exactly the two branches named in the audit: PARK and CUT_TO_BREAKEVEN. CUT_TO_TARGET
    -- is a price-to-market move, not a loss verdict, and is left alone.
    WHEN (o.action IN ('PARK','CUT_TO_BREAKEVEN')
          -- v27.53.1 (verifier, 2026-08-12): ALSO catch the parks MINTED FURTHER DOWN this ladder
          -- by the v27.34 loser guard. That branch turns probe-path actions into PARK below this
          -- test, so those condemnations never reached the long leg at all -- one live escape:
          -- 'diary for girls ages 8-12' parked $1.00 -> $0.25 on 4 clicks while its settled 8-28d
          -- read 34 clicks at 2.18x. Mirror the mint predicate exactly, including its > $0.25
          -- bid precondition (below that it HOLDs rather than PARKs, so there is nothing to veto).
          OR (COALESCE(o.clicks_w, 0) >= 4 AND COALESCE(o.roas_w, 0) < 0.6
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')
              AND COALESCE(o.current_bid, 0) > 0.25 + 0.005))
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND COALESCE(o.clicks_8_28, 0) >= 4 AND COALESCE(o.roas_8_28, 0) >= 1.0
      THEN 'LONG_LEG_HOLD'
    -- v27.53 ITEM 7 — WAKE_STEP, the missing second half of the $1.00 on-ramp ("wake it, then
    -- price it"). The wake half works; the step-down never had a scheduler, so 13 of 24 keywords
    -- woken since 2026-06-01 are still sitting at the flat entry price with their evidence already
    -- in. wake_due fires once the wake has bought 10 clicks, or 7 days, whichever comes first;
    -- wake_step_bid prices it from the keyword's own numbers (guard). Placed BELOW every hold and
    -- below the condemnations — a PARK is a stronger, better-evidenced step than this one, and an
    -- APPLIED/MANUAL/settle hold outranks a scheduled reprice.
    WHEN COALESCE(g.wake_due, FALSE) AND NOT o.is_defense
     AND o.action IN ('KEEP','KEEP_TAIL','HOLD','IDLE','PROBE_WAIT','PROBE_START')
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND g.wake_step_bid IS NOT NULL
     AND g.wake_step_bid < COALESCE(o.current_bid, 0) - 0.005
      THEN 'WAKE_STEP'
    -- v27.48.2 PACE_RAISE (Cause 4): the LY-pacing raise — a proven settled winner pacing
    -- < 25% of its LY same-28d window with the bid under LY conv CPC (guard pace_flag carries
    -- the full calibrated gate list incl. 7d bid stability + not-OOB-owned). Fires ONLY on
    -- otherwise-idle rows, seated, uncapped, ungated, not window-losing; defers to the part-1
    -- revive path unless that path is manually blocked (manual park 7-14d: pace is its ONLY
    -- recovery path — the calibration's canonical row). Glide +10%/day toward the economics
    -- target (band ceiling / settled GP-per-click ÷ 1.2 / 1.5x LY conv CPC, $2 cap).
    WHEN COALESCE(g.pace_flag, FALSE) AND NOT o.is_defense AND NOT o.capped
     AND o.action IN ('KEEP','KEEP_TAIL','HOLD','IDLE','PROBE_START')
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
     AND o.seat_rank <= o.slots
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND COALESCE(rv.reverdict, '') NOT IN ('CONFIRM_PARK', 'REDUNDANT')
     AND (COALESCE(rv.reverdict, '') != 'REVIVE' OR COALESCE(rv.manual_parked_recent, FALSE))
     AND COALESCE(o.current_bid, 0) > 0
     AND g.pace_target_bid > COALESCE(o.current_bid, 0) + 0.005
     AND NOT (ap.last IS NOT NULL
              AND (DATE(ap.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                   OR ABS(COALESCE(ap.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
      THEN 'PACE_RAISE'
    -- v27.48: CONFIRM_PARK (settled-verified loser) and MANUAL parks < 14d old never resurface
    -- via probe promotion / nudges / raises — the $1 entry on a settled loser is Cause-2
    -- behavior; the $1 entry over Ori's manual park is Cause 3.
    WHEN (COALESCE(rv.reverdict, '') IN ('CONFIRM_PARK', 'REDUNDANT') OR COALESCE(rv.manual_parked_recent, FALSE))
     AND COALESCE(o.current_bid, 0) <= 0.30
     AND o.action IN ('PROBE_START','PROBE_ADJUST','NUDGE_UP','VOLUME_LIFT','RAISE_TO_TARGET')
      THEN 'HOLD'
    -- v27.48 ACTIVATE_REVIVE: a seated, uncapped REVIVE row comes back at its CALIBRATED revive
    -- bid (clamp(min(pre-park bid, 1.1 x settled CPC), $0.31, $1.50) — snapshot-computed), never
    -- the flat $1 probe entry (proven record with an anchor). ENTRY_BLOCK (STOP or PROBING)
    -- defers revival to the gate's re-probe economics (season-gate precedence); the
    -- applied-today/unsynced self-test (v27.36 pattern) keeps an uploaded revival from
    -- re-emitting until Amazon syncs. Queue-stuck REVIVE rows keep their queue reason — their
    -- remedy is a BUDGET line for Ori (slots = budget/$4), not a bid line (v27.29).
    WHEN COALESCE(rv.reverdict, '') = 'REVIVE' AND COALESCE(o.current_bid, 0) <= 0.30
     AND NOT COALESCE(rv.manual_parked_recent, FALSE)
     AND o.seat_rank <= o.slots AND NOT o.capped AND NOT o.is_defense AND NOT o.is_auto
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     -- v27.52 FIX 3: the revive bid is now RECORD-CAPPED too (see the suggested_bid branch). The
     -- real-move test must read the CAPPED bid, or a capped-to-current revival would surface as an
     -- ACTIVATE_REVIVE that moves nothing (v27.29).
     AND rv.revive_bid IS NOT NULL
     AND ROUND(GREATEST(o.bid_floor, LEAST(rv.revive_bid,
           IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999))), 2)
         > COALESCE(o.current_bid, 0) + 0.005
     AND NOT (ap.last IS NOT NULL
              AND (DATE(ap.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                   OR ABS(COALESCE(ap.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
      THEN 'ACTIVATE_REVIVE'
    -- v27.48.2 PROBE READS THE RECORD (Cause 2): a scope-lifetime LOSER (>= 30 clicks under
    -- 0.6x GP-ROAS account-wide) is NOT "untested" — it needs the loser path, never a $1 probe.
    -- v27.52 FIX 3: PROBE_ADJUST joins PROBE_START here. The cap was wired to the entry action
    -- that issues the FEWEST entries: measured 2026-08-12, 5 of 5 live PROBE_ADJUST rows landed on
    -- the flat $1.00 and 2 of them were record losers (43c at 0.00x, 33c at 0.00x). A PROBE_ADJUST
    -- that LOWERS a bid is never blocked — it commits no new spend (the v27.37 #3a principle);
    -- only a RAISE onto a proven loser is the defect. Effective bid = the v27.37 #3b anchored
    -- probe_bid when it applies, else the ladder's own suggestion.
    WHEN o.action IN ('PROBE_START', 'PROBE_ADJUST')
     AND COALESCE(g.life_clk, 0) >= 30 AND COALESCE(g.life_roas, 1) < 0.6
     AND (o.action = 'PROBE_START'
          OR COALESCE(IF(COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
                         o.probe_bid, o.suggested_bid), 0) > COALESCE(o.current_bid, 0) + 0.005)
      THEN 'HOLD'
    -- v27.48.2 (Cause 2): the record-priced entry (lifetime conv CPC x 1.2; ENTRY_BLOCK rows
    -- also LY conv CPC x 0.8) lands on the bid the row already has — no real move (v27.29).
    -- Gate-STOP rows are exempt (the STOP park below owns them).
    -- v27.52 FIX 3: PROBE_ADJUST joins here as well, but ONLY when it is raising — capping a
    -- LOWERING adjust to the current bid must not turn a legitimate bid cut into a HOLD.
    WHEN o.action IN ('PROBE_START', 'PROBE_ADJUST')
     AND NOT (cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP')
     AND ((COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL)
          OR (cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL))
     AND IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
            o.probe_bid, o.suggested_bid) IS NOT NULL
     AND (o.action = 'PROBE_START'
          OR IF(COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL, o.probe_bid, o.suggested_bid)
             > COALESCE(o.current_bid, 0) + 0.005)
     AND ROUND(GREATEST(o.bid_floor, LEAST(
           IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
              o.probe_bid, o.suggested_bid),
           IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
           IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999))), 2)
         <= COALESCE(o.current_bid, 0) + 0.005
      THEN 'HOLD'
    -- v27.34 (Ori 2026-08-06 audit #2): the MIRROR of v27.28. That rule stopped the engine
    -- shelving a proven WINNER; nothing stopped it FUNDING a proven LOSER. Measured: 24
    -- PROBE_WAIT rows sat at a $1.00 bid awaiting a 20-click verdict they had already
    -- failed (e.g. 17c at 0.00x, $23.99 spent), 7 PROBE_ADJUST rows were being raised to
    -- $1.00 on 19-31 clicks at 0.00x, and 5 NUDGE_UPs raised keywords with 12c at 0.00x --
    -- the nudge exists for INVISIBLE keywords, not ones with losing evidence.
    -- >=4 window clicks under 0.6x is a verdict: stop paying to re-learn it. Park at $0.25,
    -- which clears every per-format floor (v27.33), or hold if already at/below it.
    WHEN (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6) AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')
      THEN IF(COALESCE(o.current_bid, 0) > 0.25 + 0.005, 'PARK', 'HOLD')
    -- v27.42 ENTRY_BLOCK STOP (2026-08-08 calibration: PASS only WITH the half-allowance
    -- re-probe — hard block -$6,578, block+reprobe +$551, 12/13 stops correct). The keyword
    -- failed this same season family last time (mature LOSS verdict) and has now spent its
    -- half allowance this occurrence without paying back — stop funding it: park at $0.25.
    -- PROBING state never lands here (the re-probe is the point); a current-window winner
    -- (>= 4c >= 1.0x, the v27.28 bar) is always released — the flip case. Sits BELOW v27.34:
    -- when both fire, the more current window evidence names the row.
    WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP'
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) >= 1.0)
     AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START','RAISE_TO_TARGET')
      THEN IF(COALESCE(o.current_bid, 0) > 0.25 + 0.005, 'PARK', 'HOLD')
    -- v27.43 FIX C: a RUNNING re-probe (ENTRY_BLOCK/PROBING) funds only up to the REMAINING half
    -- allowance (gate v27.43: remaining_allowance = probe_cap - near-settled occurrence spend).
    -- Two HOLD cases here; the actual bid clamp lives in the suggested_bid ladder (below the
    -- v27.37 pace branch, so a queued raise stays queued and unpriced):
    --   1. remainder below the row's per-format floor (v27.33) — any bid we could offer would
    --      violate the floor, so the row holds until the context ends or the record turns;
    --   2. the clamp lands on the bid the row already has — no real move (v27.29) => HOLD.
    -- Window winners (>= 4c >= 1.0x, the v27.28 bar) are never clamped — season memory must not
    -- pull down a live winner. PROBE_ADJUST is exempt from the no-move check (it may lower, and
    -- v27.29's own guard exempts it); PROBE_WAIT is not a funding action (no bid promised).
    WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) >= 1.0)
     AND o.action IN ('PROBE_START','PROBE_ADJUST','NUDGE_UP','VOLUME_LIFT','RAISE_TO_TARGET')
     AND (cg.remaining_allowance < o.bid_floor
          OR (o.action != 'PROBE_ADJUST' AND o.suggested_bid IS NOT NULL
              AND cg.remaining_allowance < o.suggested_bid - 0.005
              AND ABS(GREATEST(o.bid_floor, LEAST(o.suggested_bid, cg.remaining_allowance))
                      - COALESCE(o.current_bid, 0)) < 0.005))
      THEN 'HOLD'
    -- v27.36 #1 (Ori 2026-08-07): let UNDERPRICED proven winners climb. The ladder parked 36
    -- rows at KEEP with >=4 window clicks AND >=1.0x. 30 were uncapped, but only 4 were ALSO
    -- priced below their target CPC (median bid $0.57 vs median target $0.49) -- so the other 26
    -- are at/above their price already and KEEP is the RIGHT answer for them; this rule moves
    -- only the underpriced 4. Capped rows are never touched: raising a bid inside a dark campaign
    -- buys more darkness, not more clicks. Deliberately placed BELOW v27.34 (proven loser) and
    -- BELOW the bid_hold gate, and it also re-tests the applied-today/unsynced condition itself
    -- so it can never step on a bid that was just applied. The value comes from the matching
    -- v27.36 fill in the FROM clause, which uses this exact predicate.
    WHEN o.action = 'KEEP' AND NOT o.capped
     AND COALESCE(o.clicks_w, 0) >= 4 AND COALESCE(o.roas_w, 0) >= 1.0
     AND o.target_cpc IS NOT NULL AND COALESCE(o.current_bid, 0) > 0
     AND o.current_bid < o.target_cpc - 0.05
     AND NOT (ap.last IS NOT NULL
              AND (DATE(ap.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                   OR ABS(COALESCE(ap.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
      THEN 'RAISE_TO_TARGET'
    -- v27.37 #3a PACE (Ori 2026-08-07): PROBE_ADJUST held 54 rows (median clicks_w = 0, median
    -- bid $0.25) and issued 52 simultaneous raises to a flat $1.00 in ONE run. That is a large
    -- simultaneous spend commitment, and it contradicts the standing rule "do not activate new
    -- keywords while the campaign is dark". Release at the 20% pace instead: probe_pace = 20% of
    -- the budget at $4 a seat, probe_rank = position in the campaign's PROBE_ADJUST queue (most
    -- evidence first, v27.34-decided losers last). Beyond the pace the row must NOT raise -- it
    -- waits its turn on a coming day. Only RAISES are paced: a PROBE_ADJUST that LOWERS a bid
    -- (e.g. one the v27.37 anchor pulled down) commits no new spend, so it is never queued.
    WHEN o.action = 'PROBE_ADJUST' AND o.probe_rank > o.probe_pace
     AND COALESCE(o.probe_bid, 0) > COALESCE(o.current_bid, 0) + 0.005
      THEN 'HOLD'
    WHEN (NOT o.action IN ('HOLD','KEEP','KEEP_TAIL','IDLE','WINNER_FOUND','DEFENSE','APPLIED_HOLD','DEFER_OOB','SETTLE_HOLD','MANUAL_HOLD','LONG_LEG_HOLD','PROBE_WAIT','PROBE_ADJUST')
       AND (IF(o.channel = 'SB' AND o.suggested_bid IS NOT NULL AND o.suggested_bid < CASE WHEN o.channel != 'SB' THEN 0.20 WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o.ad_group_id AS STRING)) IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10 ELSE 0.25 END, CASE WHEN o.channel != 'SB' THEN 0.20 WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o.ad_group_id AS STRING)) IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10 ELSE 0.25 END, o.suggested_bid) IS NULL
            OR ABS(COALESCE(IF(o.channel = 'SB' AND o.suggested_bid IS NOT NULL AND o.suggested_bid < CASE WHEN o.channel != 'SB' THEN 0.20 WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o.ad_group_id AS STRING)) IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10 ELSE 0.25 END, CASE WHEN o.channel != 'SB' THEN 0.20 WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o.ad_group_id AS STRING)) IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10 ELSE 0.25 END, o.suggested_bid), o.current_bid) - o.current_bid) < 0.005)) THEN 'HOLD'
    ELSE o.action END AS action,
  -- SB PLATFORM FLOOR (Ori 2026-08-04, report 30): Amazon rejects SB bids under $0.25
  -- (minBid). Clamp every SB suggestion up to $0.25; if the clamp would not be a real move
  -- (current bid already at/under the floor), suppress the suggestion instead.
  CASE
    -- v27.45 DEFER_OOB: no suggested_bid — the out-of-budget engine owns the bids.
    WHEN COALESCE(cs.is_oob_owned, FALSE) AND NOT o.is_defense THEN NULL
    -- v27.65 park direction guard: a held direction violation carries no bid. Same predicate
    -- as the action ladder.
    WHEN o.action IN ('PARK','CUT_TO_BREAKEVEN')
     AND o.suggested_bid IS NOT NULL AND o.suggested_bid > o.current_bid + 0.005 THEN NULL
    WHEN (COALESCE(o.clicks_w, 0) >= 4 AND COALESCE(o.roas_w, 0) >= 1.0)
     AND COALESCE(rv.reverdict, '') NOT IN ('CONFIRM_PARK', 'REDUNDANT')
     AND o.action IN ('PARK','PARK_WAIT','IDLE','PROBE_WAIT') THEN NULL
    -- v27.42 BLOCK_CUT: a vetoed cut carries no bid (HOLD). Same predicate as the action ladder.
    WHEN cg.gate_action = 'BLOCK_CUT'
     AND (o.action IN ('PARK','PARK_WAIT','EASE_TO_TARGET','CUT_TO_TARGET','CUT_TO_BREAKEVEN','RESEARCH_EASE')
          OR ((COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')))
      THEN NULL
    WHEN bid_hold THEN NULL
    -- v27.48.2 MANUAL_HOLD: no bid — same predicate as the action ladder.
    WHEN COALESCE(g.manual_hold, FALSE) AND o.suggested_bid IS NOT NULL
     AND o.action NOT IN ('AUTO_BRAKE') THEN NULL
    -- v27.48: settle veto / resurface block carry no bid; ACTIVATE_REVIVE carries the
    -- calibrated revive bid. Same predicates as the action ladder.
    WHEN COALESCE(rv.engine_immune, FALSE)
     AND (o.action IN ('PARK','PARK_WAIT','CUT_TO_BREAKEVEN','CUT_TO_TARGET')
          OR ((COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')))
      THEN NULL
    -- v27.48.2 general settle veto: no bid — same predicate as the action ladder.
    WHEN (o.action IN ('PARK','CUT_TO_BREAKEVEN','CUT_TO_TARGET')
          OR ((COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')))
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND NOT COALESCE(g.settle_ok, TRUE)
     AND NOT (COALESCE(g.corroborated_loser, FALSE) AND NOT COALESCE(g.settle_amnesty, FALSE))
     AND NOT COALESCE(g.settle_deferral_expired, FALSE)
      THEN NULL
    -- v27.53 ITEM 4 LONG_LEG_HOLD: a vetoed condemnation carries no bid. Same predicate as the
    -- action ladder.
    WHEN (o.action IN ('PARK','CUT_TO_BREAKEVEN')
          -- v27.53.1 (verifier, 2026-08-12): ALSO catch the parks MINTED FURTHER DOWN this ladder
          -- by the v27.34 loser guard. That branch turns probe-path actions into PARK below this
          -- test, so those condemnations never reached the long leg at all -- one live escape:
          -- 'diary for girls ages 8-12' parked $1.00 -> $0.25 on 4 clicks while its settled 8-28d
          -- read 34 clicks at 2.18x. Mirror the mint predicate exactly, including its > $0.25
          -- bid precondition (below that it HOLDs rather than PARKs, so there is nothing to veto).
          OR (COALESCE(o.clicks_w, 0) >= 4 AND COALESCE(o.roas_w, 0) < 0.6
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')
              AND COALESCE(o.current_bid, 0) > 0.25 + 0.005))
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND COALESCE(o.clicks_8_28, 0) >= 4 AND COALESCE(o.roas_8_28, 0) >= 1.0
      THEN NULL
    -- v27.53 ITEM 7 WAKE_STEP: the priced step down off the $1.00 on-ramp. Same predicate as the
    -- action ladder; the value is the guard's wake_step_bid, floored at the row's platform floor.
    WHEN COALESCE(g.wake_due, FALSE) AND NOT o.is_defense
     AND o.action IN ('KEEP','KEEP_TAIL','HOLD','IDLE','PROBE_WAIT','PROBE_START')
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND g.wake_step_bid IS NOT NULL
     AND g.wake_step_bid < COALESCE(o.current_bid, 0) - 0.005
      THEN GREATEST(o.bid_floor, g.wake_step_bid)
    -- v27.48.2 PACE_RAISE: glide +10%/day toward the calibrated economics target — same
    -- predicate as the action ladder.
    WHEN COALESCE(g.pace_flag, FALSE) AND NOT o.is_defense AND NOT o.capped
     AND o.action IN ('KEEP','KEEP_TAIL','HOLD','IDLE','PROBE_START')
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
     AND o.seat_rank <= o.slots
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND COALESCE(rv.reverdict, '') NOT IN ('CONFIRM_PARK', 'REDUNDANT')
     AND (COALESCE(rv.reverdict, '') != 'REVIVE' OR COALESCE(rv.manual_parked_recent, FALSE))
     AND COALESCE(o.current_bid, 0) > 0
     AND g.pace_target_bid > COALESCE(o.current_bid, 0) + 0.005
     AND NOT (ap.last IS NOT NULL
              AND (DATE(ap.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                   OR ABS(COALESCE(ap.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
      THEN ROUND(LEAST(GREATEST(o.current_bid * 1.10, o.current_bid + 0.05), g.pace_target_bid), 2)
    WHEN (COALESCE(rv.reverdict, '') IN ('CONFIRM_PARK', 'REDUNDANT') OR COALESCE(rv.manual_parked_recent, FALSE))
     AND COALESCE(o.current_bid, 0) <= 0.30
     AND o.action IN ('PROBE_START','PROBE_ADJUST','NUDGE_UP','VOLUME_LIFT','RAISE_TO_TARGET')
      THEN NULL
    WHEN COALESCE(rv.reverdict, '') = 'REVIVE' AND COALESCE(o.current_bid, 0) <= 0.30
     AND NOT COALESCE(rv.manual_parked_recent, FALSE)
     AND o.seat_rank <= o.slots AND NOT o.capped AND NOT o.is_defense AND NOT o.is_auto
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     -- v27.52 FIX 3: same capped real-move test as the action ladder.
     AND rv.revive_bid IS NOT NULL
     AND ROUND(GREATEST(o.bid_floor, LEAST(rv.revive_bid,
           IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999))), 2)
         > COALESCE(o.current_bid, 0) + 0.005
     AND NOT (ap.last IS NOT NULL
              AND (DATE(ap.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                   OR ABS(COALESCE(ap.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
      -- v27.52 FIX 3: the calibrated revive bid is now capped by the LIFETIME record too. §7.7
      -- exempted ACTIVATE_REVIVE on the grounds that its bid is part-1-calibrated, but the
      -- calibration reads the settled-90d CPC only — it cannot see a scope-lifetime record that
      -- says the keyword has never cleared that price. The LY x 0.8 arm is deliberately NOT
      -- applied here: this branch already requires gate != ENTRY_BLOCK, so that arm is inert.
      THEN ROUND(GREATEST(o.bid_floor, LEAST(rv.revive_bid,
             IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999))), 2)
    -- v27.48.2: record-loser probe block + record-cap no-move carry no bid — same predicates
    -- as the action ladder (v27.52 FIX 3: PROBE_ADJUST included, raise-only).
    WHEN o.action IN ('PROBE_START', 'PROBE_ADJUST')
     AND COALESCE(g.life_clk, 0) >= 30 AND COALESCE(g.life_roas, 1) < 0.6
     AND (o.action = 'PROBE_START'
          OR COALESCE(IF(COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
                         o.probe_bid, o.suggested_bid), 0) > COALESCE(o.current_bid, 0) + 0.005)
      THEN NULL
    WHEN o.action IN ('PROBE_START', 'PROBE_ADJUST')
     AND NOT (cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP')
     AND ((COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL)
          OR (cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL))
     AND IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
            o.probe_bid, o.suggested_bid) IS NOT NULL
     AND (o.action = 'PROBE_START'
          OR IF(COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL, o.probe_bid, o.suggested_bid)
             > COALESCE(o.current_bid, 0) + 0.005)
     AND ROUND(GREATEST(o.bid_floor, LEAST(
           IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
              o.probe_bid, o.suggested_bid),
           IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
           IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999))), 2)
         <= COALESCE(o.current_bid, 0) + 0.005
      THEN NULL
    -- v27.34: see the action note above.
    WHEN (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6) AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')
      THEN IF(COALESCE(o.current_bid, 0) > 0.25 + 0.005, 0.25, NULL)
    -- v27.42 ENTRY_BLOCK STOP: park the stopped re-probe at $0.25. Same predicate as the action ladder.
    WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP'
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) >= 1.0)
     AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START','RAISE_TO_TARGET')
      THEN IF(COALESCE(o.current_bid, 0) > 0.25 + 0.005, 0.25, NULL)
    -- v27.43 FIX C: allowance-exhausted / no-move re-probe HOLD carries no bid. Same predicate as
    -- the action ladder branch.
    WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) >= 1.0)
     AND o.action IN ('PROBE_START','PROBE_ADJUST','NUDGE_UP','VOLUME_LIFT','RAISE_TO_TARGET')
     AND (cg.remaining_allowance < o.bid_floor
          OR (o.action != 'PROBE_ADJUST' AND o.suggested_bid IS NOT NULL
              AND cg.remaining_allowance < o.suggested_bid - 0.005
              AND ABS(GREATEST(o.bid_floor, LEAST(o.suggested_bid, cg.remaining_allowance))
                      - COALESCE(o.current_bid, 0)) < 0.005))
      THEN NULL
    -- v27.37 #3a: a probe raise past the 20% pace carries NO bid -- it is queued, not priced.
    -- Mirrors the 'HOLD' branch in the action CASE above, same predicate.
    WHEN o.action = 'PROBE_ADJUST' AND o.probe_rank > o.probe_pace
     AND COALESCE(o.probe_bid, 0) > COALESCE(o.current_bid, 0) + 0.005
      THEN NULL
    -- v27.43 FIX C: the allowance clamp — a funded re-probe bid may not exceed the remaining half
    -- allowance. Fires only when the clamp BINDS (effective bid > remaining); otherwise the row
    -- falls through unchanged. Effective bid = probe_bid for anchored PROBE_ADJUST (v27.37 #3b),
    -- else suggested_bid. GREATEST(bid_floor, ...) keeps v27.33 intact (remaining >= floor here,
    -- so the result never exceeds the remaining allowance). Sits BELOW the pace branch — a queued
    -- raise stays queued and unpriced — and ABOVE the v27.37 #3b branch so the anchored entry is
    -- clamped too.
    WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) >= 1.0)
     AND o.action IN ('PROBE_START','PROBE_ADJUST','NUDGE_UP','VOLUME_LIFT','RAISE_TO_TARGET')
     AND cg.remaining_allowance >= o.bid_floor
     AND IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
            o.probe_bid, o.suggested_bid) > cg.remaining_allowance + 0.005
      THEN ROUND(GREATEST(o.bid_floor,
                          LEAST(IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
                                   o.probe_bid, o.suggested_bid),
                                cg.remaining_allowance,
                                -- v27.48.2 (Cause 2): the record caps COMPOSE with the allowance
                                -- clamp on a PROBE_START entry — min of allowance, lifetime conv
                                -- CPC x 1.2 and (this IS an ENTRY_BLOCK row) LY conv CPC x 0.8.
                                -- v27.52 FIX 3: PROBE_ADJUST composes here too.
                                IF(o.action IN ('PROBE_START','PROBE_ADJUST') AND COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL,
                                   ROUND(1.2 * g.life_conv_cpc, 2), 999),
                                IF(o.action IN ('PROBE_START','PROBE_ADJUST') AND g.ly_conv_cpc IS NOT NULL,
                                   ROUND(0.8 * g.ly_conv_cpc, 2), 999))), 2)
    -- v27.48.2 (Cause 2): the standalone record cap — a PROBE_START entry above the record price
    -- is clamped to it (lifetime conv CPC x 1.2; ENTRY_BLOCK rows also LY conv CPC x 0.8), floor
    -- = the per-format platform floor. Fires only when the cap BINDS; gate-STOP rows exempt
    -- (their park branch above owns them); ENTRY_BLOCK/PROBING rows whose allowance clamp fired
    -- above already carry the composed min.
    -- v27.52 FIX 3: PROBE_ADJUST is capped here too, and the capped value is measured against the
    -- EFFECTIVE entry bid (the v27.37 #3b anchored probe_bid when it applies, else the ladder's
    -- own suggestion) — that effective bid is what the row would otherwise have carried out of
    -- the branch below. Sits ABOVE the #3b branch so the anchored entry is capped as well.
    WHEN o.action IN ('PROBE_START', 'PROBE_ADJUST')
     AND NOT (cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP')
     AND ((COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL)
          OR (cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL))
     AND IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
            o.probe_bid, o.suggested_bid) IS NOT NULL
     AND IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
            o.probe_bid, o.suggested_bid) > LEAST(
           IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
           IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999)) + 0.005
      THEN ROUND(GREATEST(o.bid_floor, LEAST(
           IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
              o.probe_bid, o.suggested_bid),
           IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
           IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999))), 2)
    -- v27.37 #3b: probes with real history enter at their own clearing price, not the flat $1.00.
    -- probe_bid is already LEAST()-capped at the ladder's own value (can only lower) and
    -- GREATEST()-clamped to the row's platform floor, so it does not need the ELSE clamp below.
    WHEN o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL
      THEN o.probe_bid
    ELSE -- v27.33: per-format SB floor, and CLAMP UP instead of suppressing. The old rule dropped
     -- the suggestion whenever the clamped value was not a 'real move', which stranded proven
     -- winners at a below-floor bid forever (repro: 'teen girl gifts trendy stuff').
     IF(o.channel = 'SB' AND o.suggested_bid IS NOT NULL
        AND o.suggested_bid < CASE WHEN o.channel != 'SB' THEN 0.20
              WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d
                    WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o.ad_group_id AS STRING))
                   IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10
              ELSE 0.25 END,
        CASE WHEN o.channel != 'SB' THEN 0.20
              WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d
                    WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o.ad_group_id AS STRING))
                   IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10
              ELSE 0.25 END,
        o.suggested_bid) END AS suggested_bid,
  CASE
    -- v27.45 DEFER_OOB: same predicate as the action ladder.
    WHEN COALESCE(cs.is_oob_owned, FALSE) AND NOT o.is_defense
      THEN CONCAT('capped ', CAST(cs.days_capped_7d AS STRING),
                  'd of 7 — out-of-budget engine owns the bids')
    -- v27.65 park direction guard: same predicate as the other two ladders.
    WHEN o.action IN ('PARK','CUT_TO_BREAKEVEN')
     AND o.suggested_bid IS NOT NULL AND o.suggested_bid > o.current_bid + 0.005
      THEN CONCAT('direction violation held — ', o.action, ' priced $',
                  FORMAT('%.2f', o.suggested_bid), ' ABOVE the current $',
                  FORMAT('%.2f', o.current_bid),
                  ': a condemnation may never raise the bid. If a raise is deserved, a raise branch must say so')
    WHEN (COALESCE(o.clicks_w, 0) >= 4 AND COALESCE(o.roas_w, 0) >= 1.0)
     AND COALESCE(rv.reverdict, '') NOT IN ('CONFIRM_PARK', 'REDUNDANT')
     AND o.action IN ('PARK','PARK_WAIT','IDLE','PROBE_WAIT')
      THEN CONCAT('its own window says winner — ', CAST(CAST(COALESCE(o.clicks_w,0) AS INT64) AS STRING),
                  ' clicks at ', FORMAT('%.2f', COALESCE(o.roas_w,0)), 'x: never shelve a proven earner (was ', o.action, ')')
    -- v27.42 BLOCK_CUT: see the action note above. Same predicate, third ladder.
    WHEN cg.gate_action = 'BLOCK_CUT'
     AND (o.action IN ('PARK','PARK_WAIT','EASE_TO_TARGET','CUT_TO_TARGET','CUT_TO_BREAKEVEN','RESEARCH_EASE')
          OR ((COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')))
      THEN CONCAT('this context (', cg.context_label, '): ', CAST(cg.cur_clicks AS STRING), 'c at ',
                  FORMAT('%.2f', COALESCE(cg.cur_gp_roas, 0)), 'x settled — cut vetoed (was ', o.action, ')')
    WHEN bid_hold THEN CONCAT('applied $', FORMAT('%.2f', ap.last.new_bid), ' at ',
       FORMAT_TIMESTAMP('%b %d %H:%M', ap.last.ts, 'America/Los_Angeles'),
       ' — step done; suggestions resume when the new bid syncs from Amazon')
    -- v27.48.2 MANUAL_HOLD reason — same predicate as the other two ladders.
    WHEN COALESCE(g.manual_hold, FALSE) AND o.suggested_bid IS NOT NULL
     AND o.action NOT IN ('AUTO_BRAKE')
      THEN CONCAT('MANUAL change ', CAST(g.last_bid_change_date AS STRING),
                  " — Ori's hand outranks the engines for 7 days (settled record not catastrophic): suggestion suppressed (was ",
                  o.action, ')')
    -- v27.48: settle veto / resurface block / revival reasons — same predicates as the other
    -- two ladders.
    WHEN COALESCE(rv.engine_immune, FALSE)
     AND (o.action IN ('PARK','PARK_WAIT','CUT_TO_BREAKEVEN','CUT_TO_TARGET')
          OR ((COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')))
      THEN CONCAT('no condemnation before settle — ', COALESCE(rv.immune_reason, 'revival settling'),
                  ' (eases/brakes stay live; was ', o.action, ')')
    -- v27.48.2 general settle veto reason — same predicate as the other two ladders.
    WHEN (o.action IN ('PARK','CUT_TO_BREAKEVEN','CUT_TO_TARGET')
          OR ((COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')))
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND NOT COALESCE(g.settle_ok, TRUE)
     AND NOT (COALESCE(g.corroborated_loser, FALSE) AND NOT COALESCE(g.settle_amnesty, FALSE))
     AND NOT COALESCE(g.settle_deferral_expired, FALSE)
      THEN CONCAT('wave — sales not yet attributed (last click ', CAST(g.last_click_date AS STRING),
                  ', settles ', CAST(g.settle_due AS STRING), ', D+', CAST(g.settle_days_eff AS STRING), ' ', o.channel,
                  '); settled 90d ',
                  IF(COALESCE(g.settled_clk90, 0) >= 10,
                     CONCAT(CAST(g.settled_clk90 AS STRING), 'c at ', FORMAT('%.2f', COALESCE(g.settled_roas90, 0)), 'x',
                            IF(COALESCE(g.settle_amnesty, FALSE), ' + season WIN prior (this season, mature) — amnesty holds',
                               IF(COALESCE(g.season_win_prior, FALSE), ' + season WIN prior', ''))),
                     CONCAT('only ', CAST(COALESCE(g.settled_clk90, 0) AS STRING), 'c — no corroboration')),
                  ' — no condemnation before settle, re-judge by ',
                  CAST(LEAST(COALESCE(g.settle_due, DATE_ADD(g.anchor_date, INTERVAL g.settle_days_eff DAY)),
                             DATE_ADD(COALESCE(g.first_click_60d, g.anchor_date), INTERVAL 2 * g.settle_days_eff DAY)) AS STRING),
                  ' (hard deferral bound: ', CAST(2 * g.settle_days_eff AS STRING),
                  'd of clicking; eases/brakes stay live; was ', o.action, ')')
    -- v27.53 ITEM 4 LONG_LEG_HOLD reason — same predicate as the other two ladders.
    WHEN (o.action IN ('PARK','CUT_TO_BREAKEVEN')
          -- v27.53.1 (verifier, 2026-08-12): ALSO catch the parks MINTED FURTHER DOWN this ladder
          -- by the v27.34 loser guard. That branch turns probe-path actions into PARK below this
          -- test, so those condemnations never reached the long leg at all -- one live escape:
          -- 'diary for girls ages 8-12' parked $1.00 -> $0.25 on 4 clicks while its settled 8-28d
          -- read 34 clicks at 2.18x. Mirror the mint predicate exactly, including its > $0.25
          -- bid precondition (below that it HOLDs rather than PARKs, so there is nothing to veto).
          OR (COALESCE(o.clicks_w, 0) >= 4 AND COALESCE(o.roas_w, 0) < 0.6
              AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')
              AND COALESCE(o.current_bid, 0) > 0.25 + 0.005))
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND COALESCE(o.clicks_8_28, 0) >= 4 AND COALESCE(o.roas_8_28, 0) >= 1.0
      THEN CONCAT('short window says cut, the long settled window disagrees — 8-28d ',
                  CAST(CAST(o.clicks_8_28 AS INT64) AS STRING), 'c at ',
                  FORMAT('%.2f', COALESCE(o.roas_8_28, 0)),
                  'x — both windows must agree before a condemnation (was ', o.action, ')')
    -- v27.53 ITEM 7 WAKE_STEP reason — same predicate as the other two ladders.
    WHEN COALESCE(g.wake_due, FALSE) AND NOT o.is_defense
     AND o.action IN ('KEEP','KEEP_TAIL','HOLD','IDLE','PROBE_WAIT','PROBE_START')
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND g.wake_step_bid IS NOT NULL
     AND g.wake_step_bid < COALESCE(o.current_bid, 0) - 0.005
      THEN CONCAT('woken to $1.00 on ', CAST(g.wake_date AS STRING), ' (', CAST(g.days_since_wake AS STRING),
                  'd ago) and never priced — ',
                  IF(COALESCE(g.wake_clk, 0) = 0,
                     'the wake bought no clicks at all: step back to $0.25',
                     CONCAT(CAST(CAST(g.wake_clk AS INT64) AS STRING), ' clicks / ',
                            CAST(CAST(g.wake_ord AS INT64) AS STRING), ' orders since the wake: price it at $',
                            FORMAT('%.2f', g.wake_step_bid))),
                  ' (wake it, then price it — the second half)')
    -- v27.48.2 PACE_RAISE reason — same predicate as the other two ladders.
    WHEN COALESCE(g.pace_flag, FALSE) AND NOT o.is_defense AND NOT o.capped
     AND o.action IN ('KEEP','KEEP_TAIL','HOLD','IDLE','PROBE_START')
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6)
     AND o.seat_rank <= o.slots
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     AND COALESCE(rv.reverdict, '') NOT IN ('CONFIRM_PARK', 'REDUNDANT')
     AND (COALESCE(rv.reverdict, '') != 'REVIVE' OR COALESCE(rv.manual_parked_recent, FALSE))
     AND COALESCE(o.current_bid, 0) > 0
     AND g.pace_target_bid > COALESCE(o.current_bid, 0) + 0.005
     AND NOT (ap.last IS NOT NULL
              AND (DATE(ap.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                   OR ABS(COALESCE(ap.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
      THEN CONCAT('LY-PACE RAISE — proven winner (settled 90d ', FORMAT('%.2f', COALESCE(g.settled_roas90, 0)),
                  'x) pacing ', CAST(CAST(ROUND(100 * COALESCE(g.pace_kw, 0)) AS INT64) AS STRING),
                  '% of its LY same-28d window (', CAST(g.clk28_kw AS STRING), ' vs ', CAST(g.ly_clk28 AS STRING),
                  ' clicks) at $', FORMAT('%.2f', COALESCE(o.current_bid, 0)), ' under LY conv CPC $',
                  FORMAT('%.2f', COALESCE(g.ly_conv_cpc, 0)), ': raise ',
                  FORMAT('%+.1f', SAFE_DIVIDE(ROUND(LEAST(GREATEST(o.current_bid * 1.10, o.current_bid + 0.05), g.pace_target_bid), 2) - o.current_bid, NULLIF(o.current_bid, 0)) * 100),
                  '% to $', FORMAT('%.2f', ROUND(LEAST(GREATEST(o.current_bid * 1.10, o.current_bid + 0.05), g.pace_target_bid), 2)),
                  ', walking toward the economics target $', FORMAT('%.2f', g.pace_target_bid),
                  ' (band ceiling / settled GP-per-click ÷ 1.2 / 1.5x LY conv CPC, $2 cap) — cheap proven winners must not starve the data that would justify raising them')
    WHEN (COALESCE(rv.reverdict, '') IN ('CONFIRM_PARK', 'REDUNDANT') OR COALESCE(rv.manual_parked_recent, FALSE))
     AND COALESCE(o.current_bid, 0) <= 0.30
     AND o.action IN ('PROBE_START','PROBE_ADJUST','NUDGE_UP','VOLUME_LIFT','RAISE_TO_TARGET')
      THEN CONCAT(IF(COALESCE(rv.reverdict, '') = 'CONFIRM_PARK',
                     'CONFIRM_PARK — never resurfaces via probe funding: ',
                     "MANUAL park < 14d old — Ori's hand outranks the engines: "),
                  COALESCE(rv.reverdict_reason, 'settled evidence confirms the park'),
                  ' (was ', o.action, ')')
    WHEN COALESCE(rv.reverdict, '') = 'REVIVE' AND COALESCE(o.current_bid, 0) <= 0.30
     AND NOT COALESCE(rv.manual_parked_recent, FALSE)
     AND o.seat_rank <= o.slots AND NOT o.capped AND NOT o.is_defense AND NOT o.is_auto
     AND COALESCE(cg.gate_action, 'NONE') != 'ENTRY_BLOCK'
     -- v27.52 FIX 3: same capped real-move test as the other two ladders.
     AND rv.revive_bid IS NOT NULL
     AND ROUND(GREATEST(o.bid_floor, LEAST(rv.revive_bid,
           IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999))), 2)
         > COALESCE(o.current_bid, 0) + 0.005
     AND NOT (ap.last IS NOT NULL
              AND (DATE(ap.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                   OR ABS(COALESCE(ap.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
      THEN CONCAT('REVIVED at its calibrated bid $',
                  FORMAT('%.2f', ROUND(GREATEST(o.bid_floor, LEAST(rv.revive_bid,
                    IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999))), 2)),
                  ' (min(pre-park bid, 1.1x settled CPC), floor $0.31 — never the $1 probe entry)',
                  -- v27.52 FIX 3: say so when the lifetime record, not the calibration, set the price.
                  IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL
                     AND ROUND(1.2 * g.life_conv_cpc, 2) < rv.revive_bid - 0.005,
                     CONCAT(', RECORD-CAPPED from $', FORMAT('%.2f', rv.revive_bid), ' — ',
                            CAST(g.life_clk AS STRING), ' lifetime clicks price it at $',
                            FORMAT('%.2f', g.life_conv_cpc), ' converting CPC (x1.2)'), ''),
                  '. ', COALESCE(rv.reverdict_reason, ''))
    -- v27.48.2 record-loser probe block + record-cap no-move reasons — same predicates as the
    -- other two ladders (v27.52 FIX 3: PROBE_ADJUST included, raise-only).
    WHEN o.action IN ('PROBE_START', 'PROBE_ADJUST')
     AND COALESCE(g.life_clk, 0) >= 30 AND COALESCE(g.life_roas, 1) < 0.6
     AND (o.action = 'PROBE_START'
          OR COALESCE(IF(COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
                         o.probe_bid, o.suggested_bid), 0) > COALESCE(o.current_bid, 0) + 0.005)
      THEN CONCAT('record says LOSER, not untested — ', CAST(g.life_clk AS STRING),
                  ' lifetime clicks at ', FORMAT('%.2f', COALESCE(g.life_roas, 0)),
                  'x GP-ROAS (scope-wide): no $', FORMAT('%.2f',
                    COALESCE(IF(COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL, o.probe_bid, o.suggested_bid), 0)),
                  ' entry, the loser path owns it (was ', o.action, ')')
    WHEN o.action IN ('PROBE_START', 'PROBE_ADJUST')
     AND NOT (cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP')
     AND ((COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL)
          OR (cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL))
     AND IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
            o.probe_bid, o.suggested_bid) IS NOT NULL
     AND (o.action = 'PROBE_START'
          OR IF(COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL, o.probe_bid, o.suggested_bid)
             > COALESCE(o.current_bid, 0) + 0.005)
     AND ROUND(GREATEST(o.bid_floor, LEAST(
           IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
              o.probe_bid, o.suggested_bid),
           IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
           IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999))), 2)
         <= COALESCE(o.current_bid, 0) + 0.005
      THEN CONCAT('record-priced entry (lifetime conv CPC x1.2',
                  IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ' / LY-LOSS conv CPC x0.8', ''),
                  ') is the bid it already has — no real move (was ', o.action, ')')
    -- v27.34: see the action note above.
    WHEN (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) < 0.6) AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START')
      THEN CONCAT('probe verdict already in — ', CAST(CAST(COALESCE(o.clicks_w,0) AS INT64) AS STRING),
                  ' clicks at ', FORMAT('%.2f', COALESCE(o.roas_w,0)), 'x ($', FORMAT('%.2f', COALESCE(o.spend_w,0)),
                  ' spent): stop funding it at the probe bid (was ', o.action, ')')
    -- v27.42 ENTRY_BLOCK STOP: see the action note above. Same predicate, third ladder.
    -- v27.43: the reason now shows the NEAR-SETTLED numbers (the state is decided on them).
    WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP'
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) >= 1.0)
     AND o.action IN ('PROBE_ADJUST','PROBE_WAIT','NUDGE_UP','VOLUME_LIFT','PROBE_START','RAISE_TO_TARGET')
      THEN CONCAT('prior ', cg.prior_label, ': LOSS (', CAST(cg.prior_clicks AS STRING), 'c, net -$',
                  FORMAT('%.2f', ABS(cg.prior_net)), ', mature) — half-allowance re-probe $',
                  FORMAT('%.2f', cg.probe_cap), ' spent ($', FORMAT('%.2f', cg.ns_spend), ' near-settled at ',
                  FORMAT('%.2f', COALESCE(cg.ns_gp_roas, 0)), 'x) without paying back — stop funding this occurrence (was ',
                  o.action, ')')
    -- v27.43 FIX C: the two HOLD reasons — same predicates as the action ladder, third ladder.
    WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) >= 1.0)
     AND o.action IN ('PROBE_START','PROBE_ADJUST','NUDGE_UP','VOLUME_LIFT','RAISE_TO_TARGET')
     AND cg.remaining_allowance < o.bid_floor
      THEN CONCAT('re-probe allowance exhausted ($', FORMAT('%.2f', cg.ns_spend), ' of $',
                  FORMAT('%.2f', cg.probe_cap), ' near-settled) — holds until context ends or record turns (was ',
                  o.action, ')')
    WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) >= 1.0)
     AND o.action IN ('PROBE_START','NUDGE_UP','VOLUME_LIFT','RAISE_TO_TARGET')
     AND o.suggested_bid IS NOT NULL
     AND cg.remaining_allowance < o.suggested_bid - 0.005
     AND ABS(GREATEST(o.bid_floor, LEAST(o.suggested_bid, cg.remaining_allowance))
             - COALESCE(o.current_bid, 0)) < 0.005
      THEN CONCAT('remaining re-probe allowance $', FORMAT('%.2f', cg.remaining_allowance),
                  ' clamps this to the bid it already has — no real move; holds until context ends or record turns (was ',
                  o.action, ')')
    -- v27.36 #1: see the action note above. Same predicate, third ladder.
    WHEN o.action = 'KEEP' AND NOT o.capped
     AND COALESCE(o.clicks_w, 0) >= 4 AND COALESCE(o.roas_w, 0) >= 1.0
     AND o.target_cpc IS NOT NULL AND COALESCE(o.current_bid, 0) > 0
     AND o.current_bid < o.target_cpc - 0.05
     AND NOT (ap.last IS NOT NULL
              AND (DATE(ap.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                   OR ABS(COALESCE(ap.last.new_bid, -1) - COALESCE(o.current_bid, -1)) > 0.005))
      -- v27.98 (Ori 2026-08-21): the percentage is derived from the price this arm actually
      -- fills, not from a nominal "+10%/day". The step is max(+10%, +5c) capped at the target,
      -- so on a cheap bid the nickel arm wins and the real move is +19% or +23% — the sentence
      -- said 10% next to a row that plainly moved more. Same expression as the fill below.
      THEN CONCAT('proven winner priced under its target — ',
                  CAST(CAST(COALESCE(o.clicks_w,0) AS INT64) AS STRING), ' clicks at ',
                  FORMAT('%.2f', COALESCE(o.roas_w,0)), 'x on a $', FORMAT('%.2f', o.current_bid),
                  ' bid against a $', FORMAT('%.2f', o.target_cpc),
                  ' target, and the campaign is not dark: raise ',
                  FORMAT('%+.1f', SAFE_DIVIDE(ROUND(LEAST(GREATEST(o.current_bid * 1.10, o.current_bid + 0.05), o.target_cpc), 2) - o.current_bid, NULLIF(o.current_bid, 0)) * 100),
                  '% to $', FORMAT('%.2f', ROUND(LEAST(GREATEST(o.current_bid * 1.10, o.current_bid + 0.05), o.target_cpc), 2)),
                  ' (winners already at/above their target keep holding)')
    -- v27.37 #3a: see the action note above. Same predicate, third ladder.
    WHEN o.action = 'PROBE_ADJUST' AND o.probe_rank > o.probe_pace
     AND COALESCE(o.probe_bid, 0) > COALESCE(o.current_bid, 0) + 0.005
      THEN CONCAT('probe raise queued — number ', CAST(o.probe_rank AS STRING),
                  ' in this campaign probe queue, ', CAST(o.probe_pace AS STRING),
                  ' releasable today (20% of a $', FORMAT('%.0f', COALESCE(o.budget,0)),
                  ' budget at $4 a seat): starting every probe at once is one big spend',
                  ' commitment and cannot run while the campaign is dark — its turn comes in a coming day')
    -- v27.43 FIX C: the allowance clamp reason — mirrors the suggested_bid clamp branch (below
    -- the pace reason so a queued raise keeps its queue reason; fires only when the clamp binds).
    WHEN cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'PROBING'
     AND NOT (COALESCE(o.clicks_w,0) >= 4 AND COALESCE(o.roas_w,0) >= 1.0)
     AND o.action IN ('PROBE_START','PROBE_ADJUST','NUDGE_UP','VOLUME_LIFT','RAISE_TO_TARGET')
     AND cg.remaining_allowance >= o.bid_floor
     AND IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
            o.probe_bid, o.suggested_bid) > cg.remaining_allowance + 0.005
      THEN CONCAT('re-probe running — $', FORMAT('%.2f', cg.remaining_allowance), ' of the $',
                  FORMAT('%.2f', cg.probe_cap), ' half allowance left ($', FORMAT('%.2f', cg.ns_spend),
                  ' near-settled spent): bid clamped to the remaining allowance (', o.action, ')')
    -- v27.48.2 standalone record-cap reason — same predicate as the suggested_bid clamp branch.
    -- v27.52 FIX 3: PROBE_ADJUST included, measured on the effective entry bid.
    WHEN o.action IN ('PROBE_START', 'PROBE_ADJUST')
     AND NOT (cg.gate_action = 'ENTRY_BLOCK' AND cg.entry_state = 'STOP')
     AND ((COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL)
          OR (cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL))
     AND IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
            o.probe_bid, o.suggested_bid) IS NOT NULL
     AND IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
            o.probe_bid, o.suggested_bid) > LEAST(
           IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, ROUND(1.2 * g.life_conv_cpc, 2), 999),
           IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL, ROUND(0.8 * g.ly_conv_cpc, 2), 999)) + 0.005
      THEN CONCAT('probe entry anchored to the record — ',
                  IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL,
                     CONCAT(CAST(g.life_clk AS STRING), ' lifetime clicks, conv CPC $',
                            FORMAT('%.2f', g.life_conv_cpc), ' x1.2'), ''),
                  IF(cg.gate_action = 'ENTRY_BLOCK' AND g.ly_conv_cpc IS NOT NULL,
                     CONCAT(IF(COALESCE(g.life_clk, 0) >= 30 AND g.life_conv_cpc IS NOT NULL, '; ', ''),
                            'prior same-season LOSS: LY conv CPC $', FORMAT('%.2f', g.ly_conv_cpc), ' x0.8'), ''),
                  ' — never the flat $', FORMAT('%.2f',
                    IF(o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15 AND o.probe_bid IS NOT NULL,
                       o.probe_bid, o.suggested_bid)),
                  ' on a keyword with a record (a keyword with hundreds of clicks is not untested; was ',
                  o.action, ')')
    -- v27.37 #3b: see the suggested_bid note above.
    WHEN o.action = 'PROBE_ADJUST' AND COALESCE(o.clicks_w, 0) >= 15
     AND o.probe_bid IS NOT NULL AND o.probe_bid < COALESCE(o.suggested_bid, 0) - 0.005
      THEN CONCAT('anchored to its own clearing price — ',
                  CAST(CAST(COALESCE(o.clicks_w,0) AS INT64) AS STRING), ' clicks at a $',
                  FORMAT('%.2f', SAFE_DIVIDE(o.spend_w, NULLIF(o.clicks_w, 0))), ' realized CPC',
                  ' (target $', FORMAT('%.2f', COALESCE(o.target_cpc, 0)), '): enter at $',
                  FORMAT('%.2f', o.probe_bid), ' — max(target, 1.2x realized CPC) — instead of the flat $',
                  FORMAT('%.2f', o.suggested_bid), ' it has never been shown to clear')
    WHEN (NOT o.action IN ('HOLD','KEEP','KEEP_TAIL','IDLE','WINNER_FOUND','DEFENSE','APPLIED_HOLD','DEFER_OOB','SETTLE_HOLD','MANUAL_HOLD','LONG_LEG_HOLD','PROBE_WAIT','PROBE_ADJUST')
       AND (IF(o.channel = 'SB' AND o.suggested_bid IS NOT NULL AND o.suggested_bid < CASE WHEN o.channel != 'SB' THEN 0.20 WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o.ad_group_id AS STRING)) IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10 ELSE 0.25 END, CASE WHEN o.channel != 'SB' THEN 0.20 WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o.ad_group_id AS STRING)) IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10 ELSE 0.25 END, o.suggested_bid) IS NULL
            OR ABS(COALESCE(IF(o.channel = 'SB' AND o.suggested_bid IS NOT NULL AND o.suggested_bid < CASE WHEN o.channel != 'SB' THEN 0.20 WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o.ad_group_id AS STRING)) IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10 ELSE 0.25 END, CASE WHEN o.channel != 'SB' THEN 0.20 WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o.ad_group_id AS STRING)) IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10 ELSE 0.25 END, o.suggested_bid), o.current_bid) - o.current_bid) < 0.005))
      THEN CONCAT('no real change to make (', o.action, ' resolved to the bid it already has) — hold')
    ELSE o.reason END AS reason,
  -- v27.45 SINGLE BUDGET AUTHORITY: campaigns present in V_OOB_BUDGET_PHASE take PHASE's
  -- instruction VERBATIM (value + reason; PHASE already applies its own applied-hold, so
  -- bud_hold is deliberately bypassed for them — no double-holding, no drift). LIFT's own
  -- healthy-campaign loss-cut survives only for campaigns not in PHASE.
  CASE WHEN pb.cid IS NOT NULL THEN pb.ph_budget
       WHEN bud_hold THEN NULL
       ELSE o.suggested_budget END AS suggested_budget,
  CASE WHEN pb.cid IS NOT NULL THEN pb.ph_reason
       WHEN bud_hold THEN CONCAT('budget applied $', FORMAT('%.2f', ab.last.new_budget), ' at ',
            FORMAT_TIMESTAMP('%b %d %H:%M', ab.last.ts, 'America/Los_Angeles'),
            ' — waiting for Amazon sync')
       ELSE o.budget_reason END AS budget_reason
),
-- v27.42: the season-context gate, visible per row (PARK_CONTEXT appears ONLY here — advisory).
cg.gate_action AS context_gate,
cg.gate_reason AS context_gate_reason,
-- v27.48: the park reverdict, exposed for verification + the sweep surfaces
rv.reverdict AS park_reverdict,
COALESCE(rv.engine_immune, FALSE) AS revive_immune,
rv.revive_bid AS reverdict_revive_bid,
-- v27.48.2: the guard-snapshot signals, exposed for verification + the advisory surfaces
g.settle_ok, g.settle_due, g.last_click_date,
g.settled_clk90, g.settled_roas90, g.season_win_prior,
-- v27.52 FIX 1: the bounded amnesty the settle veto actually reads (season_win_prior above is now
-- occurrence-scoped, and is kept as a display fact — the LICENCE is this column).
COALESCE(g.settle_amnesty, FALSE) AS settle_amnesty, COALESCE(g.catastrophic, FALSE) AS catastrophic,
g.life_clk AS lifetime_clicks, g.life_roas AS lifetime_gp_roas, g.life_conv_cpc AS lifetime_conv_cpc,
g.ly_conv_cpc,
COALESCE(g.manual_hold, FALSE) AS manual_hold, g.last_bid_source, g.last_bid_change_date,
COALESCE(g.pace_flag, FALSE) AS pace_flag, COALESCE(g.pace_watch, FALSE) AS pace_watch,
g.pace_kw AS pace_vs_ly, g.pace_target_bid
FROM (
  -- v27.32 (Ori 2026-08-06): the ACTION case and the VALUE case are two independently ordered
  -- CASE ladders, and they drifted -- a keyword can be labelled RAISE_TO_TARGET by one while
  -- an earlier branch of the other returns NULL. Repro: 'teen girl gifts trendy stuff',
  -- uncapped seated WINNER, 18c at 4.49x, $0.15 bid vs $0.31 target -> action RAISE_TO_TARGET,
  -- value NULL. Chasing branch order fixed neither (v27.30/v27.31). Instead DERIVE the value
  -- from the action: if the action promises a raise and nothing priced it, price it here with
  -- the same glide the branch would have used -- max(+10%, +$0.05), capped at the target.
  SELECT o1.*,
    -- v27.37 #3b ANCHOR (Ori 2026-08-07): the probe entry bid was a FLAT $1.00 that ignored the
    -- keyword's own evidence. Repro: a keyword with a $0.74 realized CPC (18 clicks, $13.26) and
    -- a $0.55 target CPC was still pushed to $1.00 -- well above the price it has been proven to
    -- clear at. Once a keyword has real history (>=15 window clicks) enter at what it actually
    -- costs: max(target CPC, 1.2x realized CPC). Two hard rails: LEAST() means this rule may only
    -- LOWER the entry, never raise it above the $1.00 the ladder already chose, and GREATEST()
    -- keeps it at/above the row's platform floor (v27.33). Under 15 clicks a keyword is genuinely
    -- anchorless -- there is no clearing price to read -- so it keeps the flat $1.00 entry.
    -- Computed at this level (not beside probe_rank) so it can reference bid_floor, which keeps
    -- the per-format floor to ONE definition instead of a fifth copy-paste.
    IF(o1.action = 'PROBE_ADJUST' AND o1.suggested_bid IS NOT NULL AND COALESCE(o1.clicks_w, 0) >= 15,
       GREATEST(o1.bid_floor,
                LEAST(o1.suggested_bid,
                      ROUND(GREATEST(COALESCE(o1.target_cpc, 0),
                                     1.2 * SAFE_DIVIDE(o1.spend_w, NULLIF(o1.clicks_w, 0))), 2))),
       o1.suggested_bid) AS probe_bid
  FROM (
  SELECT o0.* REPLACE (
    -- covers BOTH failure modes: no value at all, AND a value that equals the current bid
    -- (the repro produced $0.15 against a $0.15 bid -- a 'raise' that raises nothing).
    CASE
      WHEN o0.action = 'RAISE_TO_TARGET'
       AND (o0.suggested_bid IS NULL OR ABS(o0.suggested_bid - o0.current_bid) < 0.005)
       AND o0.target_cpc IS NOT NULL AND COALESCE(o0.current_bid, 0) > 0
       AND o0.current_bid < o0.target_cpc - 0.05
        THEN ROUND(LEAST(GREATEST(o0.current_bid * 1.10, o0.current_bid + 0.05), o0.target_cpc), 2)
      -- v27.36 #1 (Ori 2026-08-07): price the UNDERPRICED proven winners the action ladder parks
      -- at KEEP. Measured today: 36 rows sat at KEEP with >=4 window clicks AND >=1.0x; 30 of
      -- those were uncapped, but only 4 were ALSO priced under their target CPC (median bid $0.57
      -- vs median target $0.49). So the other 26 are already at/above their price and holding
      -- them is CORRECT -- this rule deliberately moves only the 4. Same glide the existing
      -- RAISE_TO_TARGET branches use: max(+10%, +$0.05), capped at the target. The action and
      -- reason CASEs in the output layer carry the IDENTICAL predicate so the three ladders
      -- cannot drift the way v27.30/v27.31/v27.32 did.
      -- No 'suggested_bid IS NULL' precondition here on purpose: a KEEP row carrying a bid change
      -- is already incoherent (measured: 0 such rows), and adding the clause would desync this
      -- fill from the output-layer predicate, which reads the POST-fill suggested_bid.
      WHEN o0.action = 'KEEP' AND NOT o0.capped
       AND COALESCE(o0.clicks_w, 0) >= 4 AND COALESCE(o0.roas_w, 0) >= 1.0
       AND o0.target_cpc IS NOT NULL AND COALESCE(o0.current_bid, 0) > 0
       AND o0.current_bid < o0.target_cpc - 0.05
       AND NOT (ap.last IS NOT NULL
                AND (DATE(ap.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
                     OR ABS(COALESCE(ap.last.new_bid, -1) - COALESCE(o0.current_bid, -1)) > 0.005))
        THEN ROUND(LEAST(GREATEST(o0.current_bid * 1.10, o0.current_bid + 0.05), o0.target_cpc), 2)
      ELSE o0.suggested_bid END AS suggested_bid
  ),
    -- v27.35 #3a PACE (Ori 2026-08-06): PROBE_ADJUST issued 55 raises to $1.00 in ONE run.
    -- Rank probe raises per campaign (most evidence first) and cap by the 20% rule, so they
    -- release a few per day instead of all at once.
    -- v27.37 #3a (Ori 2026-08-07): the v27.35 scaffold ranked over the WHOLE campaign, so
    -- probe_rank was a keyword's position among ALL its campaign's keywords while probe_pace is a
    -- count of probe SEATS -- apples to oranges. Measured: 'probe_rank <= probe_pace' passed only
    -- 4 of 52 raises, and it DEADLOCKED, because a 0-click probe sorted by clicks DESC sits below
    -- every clicked keyword forever and can never earn clicks without a bid. Partitioning by
    -- action ranks each row inside its OWN queue, so PROBE_ADJUST rows compete only with each
    -- other (22 of 52 pass) and the queue drains: today's released probe leaves the PROBE_ADJUST
    -- pool tomorrow and the next one advances. The extra sort key parks the rows v27.34 is about
    -- to PARK (>=4 clicks under 0.6x) at the BACK of the queue so a decided loser cannot burn a
    -- seat that a live candidate needs. Safe to redefine: the column was pure scaffold, unused by
    -- this view and unreferenced anywhere else in the repo.
    -- v27.38 (Ori 2026-08-06): PROFIT ORDERS THE QUEUE, not click volume. The v27.37 spec said
    -- "most evidence first" and ranked on clicks_w DESC -- which handed campaign 274901091172338
    -- its single daily seat to a clause at 2 clicks / 0.00x while a 1-click / 90.19x clause sat
    -- at rank 4, unfunded, draining at 1/day (~3 weeks). With only ~1 seat released per campaign
    -- per day the ORDER BY *is* the allocation policy, so it must rank by money:
    --   1. proven losers last (>=4 clicks under 0.6x)
    --   2. anything already earning (roas_w >= 1.0) ahead of anything not
    --   3. within each group, higher net ROAS first
    --   4. clicks only as a tiebreak, then name for determinism
    ROW_NUMBER() OVER (PARTITION BY o0.campaign_id, o0.action
                       ORDER BY (COALESCE(o0.clicks_w, 0) >= 4 AND COALESCE(o0.roas_w, 0) < 0.6),
                                IF(COALESCE(o0.roas_w, 0) >= 1.0, 0, 1),
                                -- v27.48.2 (Cause 2): settled evidence outranks fresh unsettled —
                                -- the settled-first key; live window earners above keep their rank.
                                IF(o0.settled_winner, 0, 1),
                                COALESCE(o0.roas_w, 0) DESC,
                                COALESCE(o0.clicks_w, 0) DESC, o0.target_text) AS probe_rank,
    GREATEST(1, CAST(FLOOR(0.20 * COALESCE(o0.budget,0) / 4) AS INT64)) AS probe_pace,
    -- v27.37: the per-format platform floor of v27.33, lifted into a column so the new probe
    -- anchor can clamp against the SAME numbers instead of a fifth inline copy.
    CASE WHEN o0.channel != 'SB' THEN 0.20
         WHEN (SELECT ANY_VALUE(creative_type) FROM `onyga-482313.OI.DIM_AD_GROUP` d
               WHERE d.is_current AND CAST(d.ad_group_id AS STRING) = CAST(o0.ad_group_id AS STRING))
              IN ('PRODUCT_COLLECTION','STORE_SPOTLIGHT') THEN 0.10
         ELSE 0.25 END AS bid_floor,
    ap.last IS NOT NULL AND o0.suggested_bid IS NOT NULL AND
      (DATE(ap.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
       OR ABS(COALESCE(ap.last.new_bid, -1) - COALESCE(o0.current_bid, -1)) > 0.005) AS bid_hold,
    ab.last IS NOT NULL AND o0.suggested_budget IS NOT NULL AND
      (DATE(ab.last.ts, 'America/Los_Angeles') = CURRENT_DATE('America/Los_Angeles')
       OR ABS(COALESCE(ab.last.new_budget, -1) - o0.budget) > 0.51) AS bud_hold  -- o0.budget is display-rounded to $1
  FROM out o0
  LEFT JOIN applied ap ON ap.cid = CAST(o0.campaign_id AS STRING) AND ap.tgt = o0.target_text
  LEFT JOIN applied_bud ab ON ab.cid = CAST(o0.campaign_id AS STRING)
  ) o1
) o
LEFT JOIN applied ap ON ap.cid = CAST(o.campaign_id AS STRING) AND ap.tgt = o.target_text
LEFT JOIN applied_bud ab ON ab.cid = CAST(o.campaign_id AS STRING)
-- v27.45: ownership routing (DEFER_OOB) + the single budget authority
LEFT JOIN cap_state cs ON cs.cid = CAST(o.campaign_id AS STRING)
LEFT JOIN phase_bud pb ON pb.cid = CAST(o.campaign_id AS STRING)
-- v27.42: season-context gate — KEYWORD ROWS ONLY (grain hazard: the ledger pools keyword_text
-- account-wide, so auto clauses and asin/category targets must never read a gate; the NOT
-- is_auto / NOT is_pt condition lives in the ON clause so those rows get NULL gates by construction).
LEFT JOIN `onyga-482313.OI.V_KEYWORD_CONTEXT_GATE` cg
  ON cg.keyword_text = LOWER(TRIM(o.target_text)) AND NOT o.is_auto AND NOT o.is_pt
-- v27.48: the park reverdict SNAPSHOT (never the view — plan-cost doctrine). (campaign, keyword)
-- grain; SB rows read NULL by construction (the parked stock is SP config).
LEFT JOIN `onyga-482313.OI.FACT_PARK_REVERDICT` rv
  ON rv.campaign_id = CAST(o.campaign_id AS STRING) AND rv.keyword_id = CAST(o.keyword_id AS STRING)
-- v27.48.2: the guard SNAPSHOT (never the view — plan-cost doctrine). (campaign, keyword) grain,
-- both channels; missing rows fail OPEN (COALESCE defaults keep pre-guard behavior).
LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_GUARD` g
  ON g.campaign_id = CAST(o.campaign_id AS STRING) AND g.keyword_id = CAST(o.keyword_id AS STRING)
) pub
    ) v
  ) p0
  CROSS JOIN lastday lv
) pub
CROSS JOIN lastday lv;
