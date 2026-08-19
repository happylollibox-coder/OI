-- =============================================================================================
-- V_PANEL_OWNERSHIP — THE single-home function for the Weekly Run panels
-- (v27.81, 2026-08-18; was v27.78 / v27.77 / v27.62, 2026-08-13).
-- =============================================================================================
-- Ori 2026-08-13: "same campaign with different measures shows in 2 criterias (this is not good)."
--
-- THE DEFECT, MEASURED (2026-08-13 anchor, before this view existed):
--   VIDEO- BALL (128961407602974), LolliBall — a family with 23 days of cover that goes dry
--   2026-09-05 with the next boat landing 2026-09-09.
--     Low stock panel   : STOCK_BUDGET_CUT   $55.06 -> $48.85   (-$6.21/day)
--     Portfolio 80/20   : RAISE_WEAK         $55.06 -> $68.83   (+$13.77/day)
--   One campaign, one day, two panels, a $19.98/day contradiction pointing in opposite
--   directions. Whichever Ori clicked, the other panel was still on screen telling him the
--   opposite. That is the bug. It is not a display bug — both numbers are computed, correct
--   inside their own engine, and neither engine knows the other exists.
--
-- THE RULE (Ori's priority order, 2026-08-13): LOW STOCK > LAUNCH > REVIVALS > everything else.
-- A campaign belongs to exactly ONE criteria. The losing panels either drop the row or show it
-- as an explicit deferral carrying NO instruction — never a second, contradictory number.
--
-- ── PRECEDENT FOLLOWED EXACTLY: V_CAMPAIGN_CAP_STATE ────────────────────────────────────────
-- The account already solved this once. V_CAMPAIGN_CAP_STATE (v27.45) is THE single membership
-- function that decides OOB-vs-LIFT ownership of a capped campaign's bids; V_KEYWORD_LIFT reads
-- it and emits action 'DEFER_OOB' with no suggested_bid and the reason "capped Nd of 7 — out-of-
-- budget engine owns the bids". Three ladders in the consumer (action / value / reason), one
-- predicate each, all reading the same boolean. This view is the same shape one level up: it
-- decides which CRITERIA owns a campaign, and the consumers emit 'DEFER_LOW_STOCK' the same way.
--
-- GRAIN: one row per ENABLED campaign (campaign_state = 'ENABLED', serving_status in
-- CAMPAIGN_STATUS_ENABLED / CAMPAIGN_OUT_OF_BUDGET / PENDING_START_DATE). That is the cap-state
-- population plus PENDING_START_DATE, so a brand-new launch campaign is never unowned.
--
-- ── THE LADDER ───────────────────────────────────────────────────────────────────────────────
--   rank 1  LOW_STOCK   FULL claim. Evicts the campaign from every lower panel, both levers
--                       (bid AND budget). Predicate below.
--   rank 2  LAUNCH      PARTIAL claim, and it is ALREADY IMPLEMENTED ELSEWHERE — see the note
--                       below. Emits no eviction. Present in the ladder because Ori ranked it,
--                       because it is what a stock claim has to outrank, and because the day a
--                       launch panel starts issuing numbers again the rank is already here.
--   rank 3  REVIVAL     keyword-grain, ALREADY single-homed — see the note below. Present so a
--                       revival row can test `owner_rank < 3` and defer to a stock claim.
--   rank 4  OOB / LIFT  the engines. Which of the two owns the bids is NOT decided here — it
--                       stays exactly where it has always been, V_CAMPAIGN_CAP_STATE.is_oob_owned.
--                       This view only reports it so one row shows the whole ownership chain.
--
-- ── WHY LAUNCH (rank 2) EVICTS NOTHING — this is a finding, not an omission ──────────────────
-- The launch controller has had NO panel of its own on the Weekly Run page since 2026-08-01:
-- "Launch-controller cards DISSOLVED (Ori 2026-08-01): low-budget campaigns live in the Portfolio
-- 80/20 (seat mechanism) or Out-of-budget while dark; the launch BUDGET engine feeds the Portfolio
-- campaign rows. NewCampaignCards is retired from this page." (WeeklyRunPage.tsx). The Portfolio
-- 80/20 LOW tier IS the launch campaigns' home — is_low_tier is literally budget <= low_budget_cap,
-- the same predicate as V_LAUNCH_POPULATION. Evicting launch campaigns from the engine panels on
-- rank-2 grounds would empty their only home and delete 28 of 108 campaigns from the page.
-- What the launch claim DOES enforce is already live and stays where it is: V_LAUNCH_EXEMPTION
-- blocks ROAS-driven money cuts inside V_ADS_COACH and (since v27.57) inside V_OOB_BUDGET_PHASE's
-- CUT branches. That is a PARTIAL claim on one lever in one direction, which is exactly the launch
-- doctrine ("launch = FIND THE RIGHT BID, never loss-cut") and is NOT the same thing as owning the
-- panel. So: claim_scope = 'PARTIAL_NO_CUT', defer_action = NULL.
--
-- ── WHY REVIVALS (rank 3) EVICTS NOTHING EITHER ──────────────────────────────────────────────
-- A revival is a KEYWORD verdict, not a campaign one. Claiming a whole campaign for revivals would
-- silence both engines over every keyword in it because one parked keyword's settled record
-- turned. The keyword-grain single-home already exists and already works: FACT_PARK_REVERDICT
-- carries engine_immune (post-revival settle veto) and CONFIRM_PARK (must-not-resurface), and both
-- engines honour them. Nothing to rebuild. What this view adds is the one thing that was missing:
-- a revival must now DEFER to a stock claim (`owner_rank < 3`), because reviving a keyword inside
-- a family that is going dry is the same contradiction in miniature.
--   MEASURED 2026-08-13: 0 of 25 REVIVE-ready rows sit in the CRITICAL family, so this arm changes
--   nothing today — it is the guard for the next CRITICAL family, not a live correction.
--   ⚠️ OPEN, NEEDS ORI: 12 of the 25 REVIVE rows sit in LAUNCH-population campaigns. Under a
--   literal reading of "LAUNCH > REVIVALS" those 12 would be deferred and the Revivals panel would
--   lose half its content. They are NOT deferred here. A revival is a settled-90d record (>= 10
--   clicks at >= 1.0x); the launch claim only blocks CUTS; a revival is not a cut. Flipping this
--   is one predicate — defer_revival_panel would read `owner_rank < 3` instead of `< 2` — and it
--   is Ori's call, not an engine's. Recorded here so the decision is visible, not silently made.
--
-- ── THE LOW-STOCK CLAIM PREDICATE (rank 1) — two arms, and both are needed ───────────────────
-- claimed = NOT is_defense AND (
--     A. STRUCTURAL: the family's risk_state = 'CRITICAL'
--  OR B. INSTRUCTED: the low-stock panel carries a live instruction for THIS campaign —
--        a campaign-row suggested budget, or >= 1 proposal target row,
--        or (v27.78) the family is in REDIRECT MODE )
--
--   ARM A exists because of VIDEO- COMP/BALL (274901091172338). Low stock says nothing about it
--   (STOCK_NONE, 0 proposals) while the Portfolio panel proposes RAISE_WEAK $12.00 -> $18.00.
--   Without the structural arm that raise stands: +$6.00/day of fresh demand poured into a family
--   with 23 days of cover. "Low stock proposed nothing" does not mean "do what you like" — it
--   means HOLD until the boat lands. Silence from the owner is still the owner's answer.
--
--   ARM B exists because of BUNNY-SP/AUTO (Brave) (112036454757078). Bunny grades WATCH, not
--   CRITICAL, so arm A does not fire — but low stock IS cutting it (STOCK_BUDGET_CUT $10.00 ->
--   $9.63, the paired cut on a capped campaign) while the Portfolio panel proposes RAISE_WEAK
--   $10.00 -> $15.00. A contradiction does not need a CRITICAL grade to be a contradiction. Arm B
--   claims a campaign the moment low stock actually says something about it, at any risk state.
--
--   ARM B GAINED A THIRD SIGNAL IN v27.78 (Ori 2026-08-17: "fix arm b"), and the reason is that
--   v27.73 turned the first two OFF on exactly the campaigns that need them most. REDIRECT MODE:
--   when a family's binding variation runs dry but a high-demand sibling is in stock, the engine
--   RE-AIMS ad doorways instead of braking, so bid- and budget-cut rows are priced but deliberately
--   NOT proposed (is_proposal=FALSE; only waste-parks stay proposals). Measured the same day:
--   ls_proposal_targets collapsed to 0 on 10 of 14 low-stock campaigns, and 5 — BALL-SP/AUTO
--   (White), BUNNY - COMPETITORS, BUNNY-SP/AUTO (Birthday), BUNNY-VIDEO/BROAD (Hunter) and
--   VIDEO- COMP/BALL — carried NEITHER a suggested budget NOR a proposal target. They kept the
--   claim only because arm A happened to fire (Bunny and LolliBall both grade CRITICAL today).
--   The moment a redirect-mode family grades THROTTLE rather than CRITICAL, arm A is silent and
--   arm B was blind: no claim, and the bid engines free to raise into a stock problem — the exact
--   contradiction this view exists to prevent.
--   THROTTLE, NOT WATCH (corrected 2026-08-17 — the first cut of this note said WATCH and that
--   state is unreachable): redirect_mode requires the BINDING variation to grade THROTTLE or
--   CRITICAL, and the family inherits the binding grade whenever it is not OK, so a re-aiming
--   family can never read WATCH. Arm A covers CRITICAL; the state this arm actually covers is
--   THROTTLE + redirect + both money signals silent.
--   So the reading of arm B is unchanged and only its evidence widened: silence
--   caused by the engine CHOOSING not to brake is not silence, it is the loudest thing low stock
--   says all day. A family being RE-AIMED *is* low stock acting.
--
--   The three signals together are exactly "low stock has an opinion here" — one structural, two
--   explicit. A WATCH-family campaign low stock is genuinely silent about (no instruction, no
--   redirect, no engine row either) is claimed by NEITHER arm and stays where it was. Nothing is
--   claimed for the sake of tidiness.
--
--   DEFENSE CARVE-OUT: brand defense is never profit-judged and never throttled by low stock (it
--   emits STOCK_PROTECT and proposes nothing, any risk state), so low stock must not claim it
--   either — a claim with no instruction behind it would silence the budget ladder, which is
--   defense's only remedy. Defense campaigns fall straight through to rank 4. Same doctrine
--   V_CAMPAIGN_CAP_STATE states for bids, applied to criteria ownership.
--
-- ── WHAT A CLAIM MEANS ───────────────────────────────────────────────────────────────────────
-- A FULL claim (defer_action IS NOT NULL) means: for this campaign, the owning criteria is the
-- ONLY source of bid and budget instructions. Lower panels show the row with defer_action /
-- defer_reason and NO suggested value — the DEFER_OOB shape — or drop it. If the owner proposes
-- nothing, nothing happens; that is the intended reading of "hold while the family is dry", not a
-- gap to be filled by whichever engine still has a row.
--
-- ── CONSUMERS AND THEIR PANEL RANK (the one-line hook is in PANEL_OWNERSHIP.md) ──────────────
--   rank 1  V_LOW_STOCK_ADS                              never defers
--   rank 2  V_LAUNCH_PHASE1, V_SB_LAUNCH_TARGET          defer_launch_panel
--   rank 3  V_PARK_REVERDICT (Revivals)                  defer_revival_panel
--   rank 4  V_OOB_BUDGET_PHASE, V_OOB_KEYWORD,           defer_engine_panel
--           V_KEYWORD_LIFT, V_RUN_TARGET, V_KEYWORD_GUARD,
--           V_CHANGE_SCORECARD
--
-- ── PLANNER DOCTRINE: NOTHING HOT READS THIS VIEW ────────────────────────────────────────────
-- This view reads V_LOW_STOCK_ADS, which drags the whole inventory chain (fam_state -> fam_agg ->
-- asin_shares -> V_SUPPLY_CHAIN_SUMMARY -> V_PLAN_FORECAST) and the full ads target scan behind
-- it; V_LOW_STOCK_ADS' own header records that it sits AT BigQuery's query-planning ceiling. The
-- engines are at that ceiling too (fact_oi_cube_table_planner_blowup). So this view is the
-- DEFINITION, and SP_SNAPSHOT_PANEL_OWNERSHIP materialises it into FACT_PANEL_OWNERSHIP, which is
-- what every engine, every cube and every panel actually reads — the same doctrine as
-- FACT_PARK_REVERDICT and FACT_KEYWORD_GUARD. One definition, one snapshot, one answer.
--
-- ── v27.77 (2026-08-17): THE LOW-STOCK READ IS NOW MATERIALISED — T_LOW_STOCK_CAMPAIGN ────────
-- DEPENDENCY: `ls_camp` reads `T_LOW_STOCK_CAMPAIGN`, a pure pass-through slice of V_LOW_STOCK_ADS
-- (row_kind='CAMPAIGN', campaign_id IS NOT NULL, 14 rows @ 2026-08-17) that
-- SP_SNAPSHOT_PANEL_OWNERSHIP builds IMMEDIATELY BEFORE FACT_PANEL_OWNERSHIP in the same call.
-- WHY: v27.73 (redirect mode — rmode/hero CTEs + 5 published columns) and v27.74 (complete-day
-- windows) each enlarged V_LOW_STOCK_ADS, and on 2026-08-17 even ONE inlined expansion of it
-- stopped planning: `SELECT COUNT(*) FROM V_PANEL_OWNERSHIP` failed deterministically with "Not
-- enough resources for query planning - too many subqueries or query is too complex" (the 16:24
-- snapshot run died on it; the 10:50 build was the last good one). The header note below —
-- "one read, do not add a second" — was already the last inch of headroom; the ceiling then moved
-- under it. The T_ is a MATERIALIZATION, NEVER A TRANSFORMATION: no aggregation, no projection, no
-- rename moved out of this view, so every semantic below is untouched and the ls_camp GROUP BY
-- still owns the whole per-campaign roll-up.
-- Freshness: the claim's inputs all move once a day (FACT_INVENTORY_SNAPSHOT once daily, the ads
-- anchor once daily), so a daily snapshot is exactly as fresh as the evidence under it.
--
-- ── v27.78 (2026-08-17): ARM B NOW SEES REDIRECT MODE ────────────────────────────────────────
-- Third arm-B signal `ls_redirect_mode`, sourced from V_LOW_STOCK_ADS' CAMPAIGN branch (which
-- published CAST(NULL AS BOOL) until the matching v27.78 change) and rolled up in ls_camp with
-- LOGICAL_OR. Also published as an output column so a panel can show which signal a claim rests
-- on, and named in claim_reason so a redirect-based claim says so in words. FUTURE-PROOFING, and
-- a NO-OP TODAY BY DESIGN: both redirect-mode families (Bunny, LolliBall) grade CRITICAL right
-- now, so arm A already claims all 14 campaigns and zero owners move. The arm earns its keep the
-- first day a re-aiming family grades THROTTLE instead of CRITICAL: arm A fires only on CRITICAL,
-- so THROTTLE + redirect + both money signals silent is the gap it closes. It is the shape of the
-- BUNNY-SP/AUTO (Brave) case arm B was built for, one grade up — NOT that case literally, because
-- a re-aiming family can never grade WATCH (see the THROTTLE, NOT WATCH note above).
--
-- ── v27.81 (2026-08-18): HYGIENE ONLY — THREE ITEMS, ZERO OWNERS MOVE ────────────────────────
-- Nothing in this version changes who owns a campaign today. All three came out of the v27.78
-- verifier pass; each is a hole that is closed BEFORE it is stepped in, which is the only time
-- closing one is cheap. Verified at deploy: owner / claim_rank / defer_* identical on all 93 rows.
--
--   1. claim_reason CAN NO LONGER OVERRUN ITS 80-CHAR BUDGET. The longest live reason was 79 of 80
--      and the re-aiming clause is appended unconditionally, so a 3-digit cover value, a >= $100
--      budget or a slightly longer family name breached it BY CONSTRUCTION. Now held by dropping
--      whole clauses least-informative-first, with a word-boundary truncation as the last resort.
--      The rule and the drop order are stated at the reason_parts CTE.
--   2. ls_redirect_mode IS FAMILY-PROPAGATED, like risk_state. It was a COALESCE off a LEFT JOIN,
--      so a campaign the low-stock engine has no CAMPAIGN row for read FALSE — and on a THROTTLE
--      day (arm A fires only on CRITICAL) a campaign of a RE-AIMING family that had never delivered
--      an impression would fall through to rank 4 unowned. That is exactly the hole v27.78 was
--      written to close, left open on the one population arm A cannot cover. redirect_mode is
--      family-constant, so the window is an identity. LATENT: n_missed_fam = 0 today.
--   3. binding_asin IS PUBLISHED (additive, both here and on V_LOW_STOCK_ADS' CAMPAIGN branch).
--      serves_only_binding and the v27.80 redirect proposal gate are computed against an ASIN that
--      was internal to the engine, so a panel could read the boolean but not reproduce it or name
--      the variation. No new join either side: rmc was already joined there for the gate, and
--      ls_camp was already rolling up this grain here.
--
-- Advisory. Nothing here auto-applies to Amazon.
-- Spec: architecture/PANEL_OWNERSHIP.md.
-- ── ONE EXPANSION OF V_LOW_STOCK_ADS, AND THAT IS NOT A STYLE CHOICE ────────────────────────
-- The first cut of this view read the low-stock engine at TWO grains — row_kind='FAMILY' for the
-- verdict and row_kind='CAMPAIGN' for the lever — as two CTEs over one `WHERE row_kind IN (...)`
-- read. BigQuery inlines CTEs, so that was two full expansions of a view already at the planning
-- ceiling, and it failed outright: "Not enough resources for query planning - too many subqueries
-- or query is too complex." The CAMPAIGN branch already carries the family verdict on every row
-- (risk_state, risk_rank and binding_cover_days come straight from the family grade), so the
-- FAMILY read bought nothing but a second expansion. One read. Do not add a second.
--   v27.77: that one read is now a read of T_LOW_STOCK_CAMPAIGN, so the expansion is gone
--   altogether — but the rule stands unchanged for the T_: one slice, one read. If a second grain
--   is ever genuinely needed, widen the SLICE in the SP; never re-inline the view.
--   The one thing lost with the FAMILY read is stockout_date / next_arrival_date, which the
--   CAMPAIGN branch NULLs out. The reason strings therefore quote cover days and not the dry
--   date; the dry date stays one glance away on the low-stock panel itself, which is where the
--   full diagnosis belongs.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PANEL_OWNERSHIP` AS
WITH
-- the campaign lever — one row per campaign inside an at-risk family, carrying its family's
-- verdict. GROUP BY is defensive only (verified 1:1 on 2026-08-13: 8 CRITICAL + 7 WATCH rows over
-- 15 distinct campaigns); per-column MAX is deterministic and never pairs two aggregates into one
-- derived number (fact_oi_any_value_pairing_nondeterminism).
-- v27.77: SOURCE IS T_LOW_STOCK_CAMPAIGN, not V_LOW_STOCK_ADS (planner ceiling — see header). The
-- T_ is already exactly this slice; the WHERE below is kept, redundant and deliberately so, so the
-- predicate that DEFINES the slice stays visible here and this CTE is correct against either
-- source if the table is ever rebuilt wider.
ls_camp AS (
  SELECT CAST(campaign_id AS STRING)      AS cid,
         MAX(family)                      AS ls_family,
         MAX(risk_state)                  AS risk_state,
         MIN(risk_rank)                   AS risk_rank,
         MAX(binding_cover_days)          AS binding_cover_days,
         MAX(binding_product)             AS binding_product,
         -- v27.81, additive observability. Family-constant (it comes off the family's binding
         -- grade), so MAX is an identity here exactly like the three lines above it. Published so a
         -- panel can name the dry variation a redirect claim is about; V_LOW_STOCK_ADS' CAMPAIGN
         -- branch started emitting it the same version (it was CAST(NULL AS STRING) before).
         MAX(binding_asin)                AS binding_asin,
         MAX(action)                      AS ls_action,
         MAX(now_value)                   AS ls_now,
         MAX(suggested_value)             AS ls_suggested,
         MAX(COALESCE(proposal_targets, 0))       AS ls_proposal_targets,
         MAX(COALESCE(proposal_freed_per_day, 0)) AS ls_freed_per_day,
         -- v27.78: the third arm-B signal. LOGICAL_OR, not MAX, because it is a family-constant
         -- BOOL and OR states the intent exactly: if ANY row of this campaign says the family is
         -- being re-aimed, low stock is acting on it. Published by V_LOW_STOCK_ADS' CAMPAIGN branch
         -- since v27.78 (it was CAST(NULL AS BOOL) before, which is why arm B could not see it).
         LOGICAL_OR(COALESCE(redirect_mode, FALSE)) AS ls_redirect_mode
  FROM `onyga-482313.OI.T_LOW_STOCK_CAMPAIGN`
  WHERE row_kind = 'CAMPAIGN' AND campaign_id IS NOT NULL
  GROUP BY 1
),
-- campaign -> family. 1:1 (112 rows / 112 campaigns, 2026-08-13); GROUP BY is defensive.
fmap AS (
  SELECT CAST(campaign_id AS STRING) AS cid, MAX(parent_name) AS family
  FROM `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` GROUP BY 1
),
lpop AS (
  SELECT DISTINCT CAST(campaign_id AS STRING) AS cid FROM `onyga-482313.OI.V_LAUNCH_POPULATION`
),
camp AS (
  SELECT CAST(c.campaign_id AS STRING) AS campaign_id,
         c.campaign_name,
         IF(UPPER(COALESCE(c.campaign_type, 'SP')) = 'SB', 'SB', 'SP') AS channel,
         c.serving_status,
         c.daily_budget AS budget_now
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c
  WHERE c.campaign_state = 'ENABLED'
    AND c.serving_status IN ('CAMPAIGN_STATUS_ENABLED', 'CAMPAIGN_OUT_OF_BUDGET', 'PENDING_START_DATE')
),
j AS (
  SELECT
    c.campaign_id, c.campaign_name, c.channel, c.serving_status, c.budget_now,
    fmap.family,
    -- flags: cap state is the authority where it has the campaign; the name test is the fallback
    -- for a PENDING_START_DATE campaign it has no row for (defense doctrine must not depend on
    -- whether a campaign has started serving).
    COALESCE(cs.is_defense, LOWER(c.campaign_name) LIKE '%brand defense%') AS is_defense,
    COALESCE(cs.is_seasonal, FALSE)        AS is_seasonal,
    COALESCE(cs.is_auto_campaign, FALSE)   AS is_auto_campaign,
    COALESCE(cs.is_oob_owned, FALSE)       AS is_oob_owned,
    COALESCE(cs.days_capped_7d, 0)         AS days_capped_7d,
    (lpop.cid IS NOT NULL)                 AS is_launch,
    COALESCE(le.exempt_active, FALSE)      AS launch_exempt_active,
    le.exempt_until                        AS launch_exempt_until,
    lc.risk_state, lc.risk_rank, lc.binding_cover_days, lc.binding_product,
    lc.binding_asin,
    lc.ls_action, lc.ls_now, lc.ls_suggested,
    COALESCE(lc.ls_proposal_targets, 0) AS ls_proposal_targets,
    COALESCE(lc.ls_freed_per_day, 0)    AS ls_freed_per_day,
    -- LEFT JOIN: NULL where low stock has no CAMPAIGN row for this campaign, which is a
    -- not-re-aiming, exactly like the two signals above it.
    COALESCE(lc.ls_redirect_mode, FALSE) AS ls_redirect_mode
  FROM camp c
  LEFT JOIN fmap    ON fmap.cid = c.campaign_id
  LEFT JOIN ls_camp lc ON lc.cid = c.campaign_id
  LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` cs
         ON CAST(cs.campaign_id AS STRING) = c.campaign_id
  LEFT JOIN lpop    ON lpop.cid = c.campaign_id
  LEFT JOIN `onyga-482313.OI.V_LAUNCH_EXEMPTION` le
         ON CAST(le.campaign_id AS STRING) = c.campaign_id
),
-- STRUCTURAL COVERAGE: arm A has to reach every campaign of a CRITICAL family, including one the
-- low-stock engine has no CAMPAIGN row for (that row set is built off FACT_AMAZON_ADS, so a
-- campaign of the family that has never delivered an ad impression is absent). The family verdict
-- is propagated across the family map instead. risk_state / risk_rank / binding_cover_days are
-- FAMILY-CONSTANT by construction — the CAMPAIGN branch copies them from the family grade — so
-- these aggregates are identities, not choices, and are deterministic.
-- v27.81 — ARM B'S THIRD SIGNAL GETS THE SAME WINDOW, and this is latent-gap closure, not a live
-- correction (measured 2026-08-18: n_missed_fam = 0, so ZERO owners move today).
-- The gap: risk_state is propagated here precisely so arm A reaches a campaign the low-stock engine
-- has no CAMPAIGN row for. ls_redirect_mode had no such window — it is a COALESCE off a LEFT JOIN,
-- so "no row" reads as FALSE. On a THROTTLE day (arm A silent by construction — it fires only on
-- CRITICAL) a campaign of a RE-AIMING family that had never delivered an impression would therefore
-- carry no claim from any of the three signals and fall through to rank 4 unowned, with the bid
-- engines free to raise into a stock problem. That is the exact hole v27.78 was written to close,
-- left open on the one campaign population arm A cannot cover either.
-- redirect_mode is FAMILY-CONSTANT (V_LOW_STOCK_ADS derives it from the family's binding grade), so
-- the OR is an identity across a family's rows, not a choice — same standing as the three aggregates
-- above it. LOGICAL_OR, not MAX, to state the intent: if any row of this family says low stock is
-- re-aiming it, low stock is acting on every campaign of it.
-- NULL-FAMILY GUARD: an unmapped campaign (no V_CAMPAIGN_FAMILY_MAP row) must be its own partition.
-- A bare PARTITION BY family would pool every unmapped campaign into one bucket and let one of them
-- spread a redirect claim across all the others, which would be a real (wrong) owner change rather
-- than gap closure. 0 unmapped campaigns today; the guard is so it stays true when there is one.
fam_prop AS (
  SELECT j.*,
    MIN(j.risk_rank)          OVER (PARTITION BY j.family) AS fam_risk_rank,
    MIN(j.risk_state)         OVER (PARTITION BY j.family) AS fam_risk_state,
    MAX(j.binding_cover_days) OVER (PARTITION BY j.family) AS fam_binding_cover_days,
    LOGICAL_OR(j.ls_redirect_mode)
      OVER (PARTITION BY IFNULL(j.family, CONCAT('__nofam__', j.campaign_id)))
                                                           AS fam_ls_redirect_mode
  FROM j
),
claim AS (
  SELECT f.*,
    -- ARM A structural (family CRITICAL) OR ARM B instructed (low stock says something here).
    -- Defense is carved out of BOTH: low stock never issues an instruction for it, so a claim
    -- would silence the budget ladder for nothing.
    -- v27.78 third arm-B signal (ls_redirect_mode): a family being RE-AIMED is low stock acting.
    -- It has to be here because redirect mode SILENCES the other two — v27.73 prices the bid and
    -- budget cuts but stops proposing them while the doorways move, so ls_suggested goes NULL and
    -- ls_proposal_targets goes 0 on the very campaigns low stock is working hardest on. Read
    -- through the old predicate that silence is indistinguishable from "low stock has no opinion
    -- here", and the moment a re-aiming family grades below CRITICAL the campaign would fall to
    -- rank 4 with nothing owning it — the bid engines free to raise into a stock problem, which is
    -- the one thing this view exists to prevent.
    -- v27.81: the redirect signal now reads the FAMILY-PROPAGATED flag, not the row-level one, for
    -- the same reason arm A reads fam_risk_state — a campaign with no low-stock CAMPAIGN row is
    -- still a campaign of a re-aiming family. See the fam_prop note. No live change (n_missed_fam=0).
    (NOT f.is_defense
     AND (f.fam_risk_state = 'CRITICAL'
          OR f.ls_suggested IS NOT NULL
          OR f.ls_proposal_targets > 0
          OR f.fam_ls_redirect_mode)) AS low_stock_claim
  FROM fam_prop f
),
ranked AS (
  SELECT c.*,
    CASE
      WHEN c.low_stock_claim                    THEN 1
      WHEN c.is_launch AND NOT c.is_defense     THEN 2
      ELSE 4
    END AS owner_rank,
    -- claim_rank is the rank of the highest FULL claim on this campaign — the only thing that
    -- can evict a panel. A PARTIAL claim (rank 2, LAUNCH) is deliberately NOT a claim_rank: it
    -- constrains one lever in one direction where it already lives (V_LAUNCH_EXEMPTION) and must
    -- never empty a panel. 99 = nothing owns this campaign but its own engine.
    IF(c.low_stock_claim, 1, 99) AS claim_rank
  FROM claim c
),
-- ══ v27.81 — THE CLAIM-REASON LENGTH GUARD ═══════════════════════════════════════════════════
-- THE RULE, stated once: claim_reason is a display string with an 80-CHARACTER BUDGET, and it must
-- be IMPOSSIBLE for the published value to exceed it. The budget is held by DROPPING WHOLE CLAUSES,
-- least-informative first — never by cutting a word in half. Only if the base clause alone (family
-- + grade) is still over budget does it truncate at all, and then on a word boundary.
--
-- WHY: measured 2026-08-18, the longest live reason was 79 of 80 —
--   'LolliBall CRITICAL — 42d cover, cut to $51.35, low stock is re-aiming these ads'
-- and the re-aiming clause is appended UNCONDITIONALLY. A three-digit cover value, a >= $100
-- budget, or a family name one character longer each breach the budget BY CONSTRUCTION. The string
-- was one ordinary data point from overflowing, which is not a bug you wait for.
--
-- DROP ORDER, and why each clause sits where it does. Every clause is ALSO published as its own
-- column on this row (binding_cover_days, ls_suggested, ls_redirect_mode), so a drop costs a glance,
-- never a fact:
--   1st  ' — Nd cover'  pure context, and it is repeated verbatim in defer_reason beside it.
--   2nd  ', cut to $X'  the instruction — but the low-stock panel that OWNS the row prints that
--                       number itself; claim_reason answers WHY this panel owns it, not how much.
--   3rd  re-aiming      LAST, because on a redirect-based claim with both money clauses empty it is
--                       the only thing between the reason and a bare grade (the v27.78 note above).
--                       It can only ever be dropped from a string long enough to need three drops,
--                       which by construction still carries the money clause — so this ladder can
--                       never produce the bare grade v27.78 set out to prevent.
-- Ranks 2 and 4 are bounded by construction (fixed prose plus a MM-DD date or a single digit —
-- 44 chars at the widest), but the final arm still covers them, so the 80-char promise holds for
-- EVERY row and not just for the branch that happens to be long today.
reason_parts AS (
  SELECT r.*,
    CONCAT(COALESCE(r.family, 'family'), ' ', COALESCE(r.fam_risk_state, 'at risk')) AS r1_base,
    IF(r.fam_binding_cover_days IS NULL, '',
       CONCAT(' — ', FORMAT('%.0f', r.fam_binding_cover_days), 'd cover'))           AS r1_cover,
    IF(r.ls_suggested IS NULL, '',
       CONCAT(', cut to $', FORMAT('%.2f', r.ls_suggested)))                         AS r1_cut,
    IF(r.fam_ls_redirect_mode, ', low stock is re-aiming these ads', '')             AS r1_redirect
  FROM ranked r
),
reason_sized AS (
  SELECT p.*,
    -- the unabridged reason — byte-for-byte what v27.78 published, so the guard below is provably
    -- a no-op on every row that already fits (93 of 93 @ 2026-08-18, longest 79).
    CASE p.owner_rank
      WHEN 1 THEN CONCAT(p.r1_base, p.r1_cover, p.r1_cut, p.r1_redirect)
      WHEN 2 THEN CONCAT('launch campaign — cuts blocked',
        IF(p.launch_exempt_until IS NULL, '',
           CONCAT(' to ', FORMAT_DATE('%m-%d', p.launch_exempt_until))))
      ELSE IF(p.is_oob_owned,
        CONCAT('capped ', CAST(p.days_capped_7d AS STRING), 'd of 7 — out-of-budget engine'),
        'not capped — keyword-lift engine')
    END AS r_full
  FROM reason_parts p
)
SELECT
  campaign_id, campaign_name, channel, serving_status, budget_now, family,
  is_defense, is_seasonal, is_auto_campaign,
  -- rank 4 detail, reported not decided: V_CAMPAIGN_CAP_STATE remains the OOB/LIFT authority
  is_oob_owned, days_capped_7d,
  is_launch, launch_exempt_active, launch_exempt_until,
  -- the low-stock evidence the claim was taken on. The fam_* pair is the family verdict as this
  -- view applied it (arm A); the un-prefixed pair is what the low-stock CAMPAIGN row itself said,
  -- NULL where that engine has no row for the campaign.
  fam_risk_state AS low_stock_state, fam_binding_cover_days AS binding_cover_days,
  risk_state AS low_stock_state_row, binding_cover_days AS binding_cover_days_row,
  binding_product,
  -- v27.81, additive OBSERVABILITY: the binding (dry) ASIN this family's redirect is about.
  -- V_LOW_STOCK_ADS computes serves_only_binding — and the proposal gate that turns on it — against
  -- this ASIN internally, so a panel could read the boolean but could not reproduce it or name the
  -- variation it refers to. Costs no join: it rides the ls_camp roll-up that was already there.
  -- Deliberately NOT family-propagated, unlike the claim signals: this column decides nothing, it is
  -- evidence, and evidence must not be invented for a row that has none. NULL where low stock has no
  -- CAMPAIGN row for this campaign, exactly like binding_cover_days_row beside it.
  binding_asin,
  ls_action, ls_now, ls_suggested, ls_proposal_targets, ls_freed_per_day,
  -- v27.78, additive: the third arm-B basis, published so a panel can show WHICH signal the claim
  -- was taken on. TRUE = low stock is re-aiming this family's ad doorways at an in-stock variation
  -- rather than braking, which is why the two money signals beside it can both be empty.
  -- v27.81: this column is now the FAMILY-PROPAGATED value — the one the claim is actually taken
  -- on — which makes it the exact analogue of low_stock_state above (the family verdict as applied).
  -- The raw per-campaign value keeps its own column beside it, the same low_stock_state_row pattern.
  fam_ls_redirect_mode AS ls_redirect_mode,
  ls_redirect_mode     AS ls_redirect_mode_row,
  -- ── the ladder ──────────────────────────────────────────────────────────────────────────
  owner_rank,
  CASE owner_rank
    WHEN 1 THEN 'LOW_STOCK'
    WHEN 2 THEN 'LAUNCH'
    ELSE IF(is_oob_owned, 'OOB', 'LIFT')
  END AS owner,
  CASE owner_rank
    WHEN 1 THEN 'FULL'            -- owns both levers; lower panels defer
    WHEN 2 THEN 'PARTIAL_NO_CUT'  -- blocks ROAS money cuts only (V_LAUNCH_EXEMPTION); evicts nobody
    ELSE 'FULL'
  END AS claim_scope,
  -- WHY, in one short clause. The backend owns every word of this (feedback_all_logic_in_backend);
  -- the long version belongs in a tooltip, never in the visible column.
  -- v27.81: THE 80-CHARACTER GUARD. Clauses are dropped least-informative-first (cover, then the
  -- cut, then the re-aiming note — see the reason_parts header for why that order); the last arm
  -- only ever fires when the family name ALONE overruns, and it ends on a word boundary rather than
  -- mid-word, falling back to a hard cut only for an 80-character string containing no space at all.
  CASE
    WHEN LENGTH(r_full) <= 80 THEN r_full
    WHEN owner_rank = 1 AND LENGTH(CONCAT(r1_base, r1_cut, r1_redirect)) <= 80
      THEN CONCAT(r1_base, r1_cut, r1_redirect)                              -- dropped: cover days
    WHEN owner_rank = 1 AND LENGTH(CONCAT(r1_base, r1_redirect)) <= 80
      THEN CONCAT(r1_base, r1_redirect)                                      -- dropped: + the cut
    WHEN owner_rank = 1 AND LENGTH(r1_base) <= 80
      THEN r1_base                                                           -- dropped: + re-aiming
    ELSE IFNULL(NULLIF(REGEXP_REPLACE(SUBSTR(r_full, 1, 81), r'\s*\S*$', ''), ''),
                SUBSTR(r_full, 1, 80))
  END AS claim_reason,
  -- ── the eviction. NULL unless a FULL claim outranks the panel asking. ────────────────────
  claim_rank,
  IF(claim_rank = 1, 'DEFER_LOW_STOCK', CAST(NULL AS STRING)) AS defer_action,
  IF(claim_rank = 1,
     CONCAT('low stock owns this — ', COALESCE(family, 'family'), ' ',
            COALESCE(fam_risk_state, 'at risk'),
            IF(fam_binding_cover_days IS NULL, '',
               CONCAT(', ', FORMAT('%.0f', fam_binding_cover_days), 'd cover'))),
     CAST(NULL AS STRING)) AS defer_reason,
  -- One boolean per panel rank so the consumer hook carries no arithmetic and no threshold.
  -- Today all three coincide, because LOW_STOCK is the only FULL claim in the ladder — see the
  -- LAUNCH and REVIVAL notes in the header. They are kept separate so that changing which rank
  -- evicts which panel stays a one-line edit HERE and never spreads back into the engines.
  (claim_rank < 2) AS defer_launch_panel,
  (claim_rank < 3) AS defer_revival_panel,
  (claim_rank < 4) AS defer_engine_panel
FROM reason_sized;   -- v27.81: was `ranked`; reason_sized is ranked + the reason clauses, no join.
