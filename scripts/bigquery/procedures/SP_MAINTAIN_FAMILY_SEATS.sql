-- =============================================
-- SP_MAINTAIN_FAMILY_SEATS — keeps DE_FAMILY_SEAT_LEDGER honest, once per keyword-state snapshot.
-- v27.139 (2026-08-24): UNIFIED WITH THE PLAN, AGREEMENT-TIER AWARE. Before this pass the ledger
-- derived its occupant set independently from FACT_KEYWORD_STATE (the 90-day ladder verdict
-- alone) while FACT_PLAN_NEXT_WEEK (SP_BUILD_NEXT_WEEK_PLAN, shipped 2026-08-23/24) derives its
-- own, DIFFERENT, budget-rationed occupant set from the 7/14/28-day WINDOW (rule B). The two
-- disagreed: measured live on 2026-08-24, the ledger held 83 open seats, the live plan seated 62,
-- and of those 62 only 37 were keywords BOTH the ladder's 90-day record and the window agreed
-- deserved a seat (CONFIRMED); 25 were seated on the window's word alone, the ladder disagreeing
-- (DISPUTED); a further 4 keywords the ladder alone still called not-good were EXCLUDED by the
-- window and correctly held no seat at all — the exact P-5 grace population (a keyword that just
-- turned good; cutting it on the 90-day record alone is exactly the risk P-4/P-5 exist to
-- prevent). Ori's ruling: a keyword both judges agree on deserves to be acted on FIRST and with
-- the HIGHEST confidence; a keyword the two judges DISAGREE about is acted on by NEITHER alone —
-- it holds its current seat state until the next window's plan resolves the disagreement.
--
-- WHAT CHANGED, in one sentence: the occupant set is now FACT_PLAN_NEXT_WEEK plan='B' (the LIVE
-- plan)'s own SEATED keywords (seat_no IS NOT NULL) — the plan's already budget-rationed decision,
-- not a re-derivation — joined to plan='A' (the ladder-driven shadow) on (family, campaign_id,
-- keyword_id) to read the SAME keyword's ladder-only verdict, and the two are compared to publish
-- one new column, agreement_tier ('CONFIRMED' | 'DISPUTED'), on every open row. CONFIRMED means
-- plan A's side is ALSO NOT_GOOD (side_a — V_PLAN_WINDOW_JUDGMENT's own ladder-state test: GOOD
-- only for WINNER / PACED_WINNER / AT_BAR / TRIAL / PENDING_SETTLE / REVIVED_SETTLING, NOT_GOOD
-- otherwise — REPRICE / FLOOR_PROBATION / LOSER / DEAD / PARKED all read NOT_GOOD by that test,
-- exactly the population Ori named). DISPUTED means plan A disagrees (side_a is GOOD, or the
-- ladder carries no row for the key at all — treated as GOOD, the conservative default: absence of
-- ladder evidence is not evidence of ladder agreement).
--
-- WHY THE PLAN'S OWN SEATED SET, NOT ITS FULL CANDIDATE LIST. FACT_PLAN_NEXT_WEEK carries every
-- not-good candidate (side = NOT_GOOD, is_candidate), but only a SUBSET actually holds a seat_no —
-- the rest queue, rationed by the family's ramped allowance (SP_BUILD_NEXT_WEEK_PLAN §4.4's fit-
-- test walk). A "seat" has always meant an occupied dollar-sized slot inside that allowance
-- (DE_FAMILY_SEAT_LEDGER's own header: "a seat is a dollar-sized slot ... occupied by ONE keyword
-- the family is knowingly paying for"); a queued candidate does not occupy one. Reading the plan's
-- seat_no IS NOT NULL rows is what makes reconciliation with the plan exact, not approximate:
-- Task 3 asserts DE_FAMILY_SEAT_LEDGER's open set for plan B's seated keywords equals
-- FACT_PLAN_NEXT_WEEK's seated set for plan B, one seat number per seated keyword, no orphans
-- either direction.
--
-- ONE PASS OF LAG, DELIBERATE, MIRRORING THE EXISTING T_LIFT_PROBES PRECEDENT. This procedure runs
-- at orchestrator Task 20.8b; SP_BUILD_NEXT_WEEK_PLAN (which WRITES today's FACT_PLAN_NEXT_WEEK
-- partition) runs after it at Task 20.8c IN THE SAME PASS. So at the moment this procedure runs,
-- today's plan does not exist yet — it reads the MOST RECENT partition available
-- (MAX(as_of) WHERE plan = 'B'), which on any night after the first is YESTERDAY's plan. Tonight's
-- plan build (20.8c) then reads THIS RUN's freshly-updated ledger for its own seat-number
-- continuity (SP_BUILD_NEXT_WEEK_PLAN's own comment: "the precedence is register > last night's
-- plan > lowest free number. The register still wins, because it is the authority Ori's vocabulary
-- comes from"), closing the loop one night later. This is the same trade already accepted and
-- documented for T_LIFT_PROBES (rebuilt by Task 21, after 20.8b): reordering the orchestrator to
-- remove the lag entirely is a bigger, riskier change than this task asked for, and one pass of lag
-- on a nightly plan is immaterial (unchanged from the prior header's own reasoning).
--
-- WHAT AN OCCUPANT'S KIND IS. occupant_kind is still read from TODAY's FACT_KEYWORD_STATE snapshot
-- (freshest ground truth for "what is happening right now"), by the SAME probe test as before
-- (engine-listed on T_LIFT_PROBES, at the floor with spend, or a stalled standing raise past the
-- engine's own test) — deliberately kept, not rebuilt, because it is well tested and nothing in
-- this task asked it to change. The one addition: a ladder state the old CASE never had to handle
-- (WINNER, PACED_WINNER, AT_BAR, DEAD, or the keyword missing from today's snapshot entirely) now
-- reads occupant_kind = 'disputed' — NEW VALUE, occurring ONLY on a DISPUTED occupant by
-- construction (a CONFIRMED occupant's ladder state is, by side_a's own definition, always one of
-- REPRICE / FLOOR_PROBATION / LOSER / REVIVED_SETTLING / PENDING_SETTLE / TRIAL / PARKED — the old
-- CASE already covers all of those).
--
-- CLOSURE IS NOW AGREEMENT-TIER GATED (P-4/P-5 spirit: never cut on one judge's word alone). A key
-- that leaves today's occupant set (no longer plan B seat_no IS NOT NULL) is inspected against
-- plan A ONE more time:
--   plan A says NOT_GOOD too (the ladder still wants this keyword seated, the window let it go) —
--     the two judges DISAGREE about the departure. The seat is HELD OPEN, not closed:
--     held_reason = 'HELD_DISPUTED' (NEW VALUE — a new column, never an overload of closed_reason),
--     held_reason_text carries the plain sentence, agreement_tier reads 'DISPUTED', and
--     last_observed_kind / last_observed_state are still refreshed from today's ladder so the
--     register keeps its memory current. closed_on / closed_reason / closed_reason_text stay NULL:
--     the row is still OPEN. An occupant already open before this run is NEVER evicted just because
--     it turns disputed — the seat it already holds is untouched; only a NEW admission is ever
--     gated by tier (see ADMIT below).
--   plan A agrees too (side_a is GOOD, or the ladder carries no row for the key at all) — both
--     judges now agree the keyword is not a not-good occupant: the seat closes NORMALLY, exactly
--     as before this change, through the same first-match reason ladder (KILLED > PAUSED >
--     PARK_LAPSED > LEFT_FAMILY > DEFENSE_EXEMPT > TO_GOOD_SIDE > TO_WAITING > STATE_CHANGED) read
--     from TODAY's FACT_KEYWORD_STATE, unchanged. held_reason / held_reason_text are cleared (NULL)
--     on a normal close, exactly as closed_reason / closed_reason_text are on a normal open.
-- A row already HELD whose disagreement resolves (plan A comes to agree on a later run) closes on
-- THAT run, through the same ladder, the moment it stops being CONFIRMED-not-good on plan A's side.
--
-- ADMISSION IS AGREEMENT-TIER ORDERED, NOT SEAT-RATIONED A SECOND TIME. Every keyword the plan
-- seated (occupant set) is admitted to the ledger — the ledger does not re-rank who HOLDS a seat;
-- the plan already decided that with its own allowance walk. What changes is the ORDER in which
-- SEVERAL SIMULTANEOUS new admissions consume the family's lowest free NUMBERS (the ledger's own
-- numbering is elastic — GENERATE_ARRAY always finds enough free numbers for every admission, so
-- ordering here decides WHICH number an occupant gets, never WHETHER it is admitted): CONFIRMED
-- candidates take the lower free numbers before any DISPUTED candidate, ranked within each tier by
-- the plan's own rank_score (dollars at stake × closeness to the bar, descending) — replacing the
-- old kind-priority order (repair > probation > failed > settling > parked > probe > stalled
-- probe). A DISPUTED candidate is still admitted this run (the plan seated it; the ledger does not
-- second-guess that) — it simply never takes a lower number than a CONFIRMED candidate admitted in
-- the same run when both are new.
--
-- WHAT ORI RULED, RECORDED (SOP ruling R-o, architecture/FAMILY_SEAT_REGISTER.md): a HELD_DISPUTED
-- row does not appear as a brand-new gap in the family's accounting — it keeps costing exactly what
-- it was seated at, because the plan's own money never moved for it (it left the plan's seat, not
-- the ledger's), and the register (Task 2) reads held_reason to say "held — judges disagree,
-- waiting on next window" instead of silently closing or silently staying as if nothing changed.
--
-- WHAT DID NOT CHANGE: REOPEN (a same-day flip keeps its number), OBSERVE (every open row's memory
-- is refreshed every run, idempotent), the ladder-state → occupant_kind probe test (engine-listed /
-- at-floor-with-spend / stalled raise, rulings R-a, R-b), the PARKED-with-appointment test
-- (ruling R-h), and every closed_reason and its plain sentence. Brand-defense filtering is now
-- inherited from the plan's own universe (V_PLAN_WINDOW_JUDGMENT's ks CTE: the ladder's own
-- is_brand_defense flag only) rather than re-derived here with the three-way test (flag, campaign
-- name, DIM_BRAND_PHRASES) — a DELIBERATE reading, because re-deriving a narrower filter here would
-- break the exact reconciliation Task 3 requires (the ledger would refuse to seat a keyword the
-- plan itself seated). The three-way test is measured live in the acceptance suite (A10) as a
-- standing safety check, not a filter: today it finds zero brand-defense leaks in the plan's seated
-- set; if it ever finds one, that is a signal to fix the ladder's is_brand_defense flag or the
-- plan's own filter (V_PLAN_WINDOW_JUDGMENT / SP_BUILD_NEXT_WEEK_PLAN), not to patch it here.
--
-- IDEMPOTENT: two runs against the SAME FACT_KEYWORD_STATE snapshot AND the SAME
-- FACT_PLAN_NEXT_WEEK partitions (nothing upstream changed) write byte-identical ledgers. Every
-- write is keyed on set differences and refreshed values, never on the wall clock.
--
-- Orchestrator: Task 20.8b, immediately after SP_SNAPSHOT_KEYWORD_STATE (20.8), before
-- SP_BUILD_NEXT_WEEK_PLAN (20.8c).
-- Spec: architecture/FAMILY_SEAT_REGISTER.md (ruling R-o), Task 5 of the family seat register.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_MAINTAIN_FAMILY_SEATS`()
OPTIONS (
  description = "v27.139 (2026-08-24): maintains DE_FAMILY_SEAT_LEDGER from FACT_PLAN_NEXT_WEEK plan='B' (the live plan)'s own SEATED keywords (seat_no IS NOT NULL, its own budget-rationed decision, not re-derived) at the most recent available as_of (one pass of lag by construction, since SP_BUILD_NEXT_WEEK_PLAN writes today's partition AFTER this procedure runs in the same orchestrator pass — mirrors the existing T_LIFT_PROBES lag). Joined to plan='A' (the ladder-driven shadow) on (family, campaign_id, keyword_id): agreement_tier = CONFIRMED when plan A's side is also NOT_GOOD (side_a: GOOD only for WINNER / PACED_WINNER / AT_BAR / TRIAL / PENDING_SETTLE / REVIVED_SETTLING), else DISPUTED (plan A says GOOD, or carries no row for the key). occupant_kind is read from today's FACT_KEYWORD_STATE snapshot by the existing probe test (engine-listed T_LIFT_PROBES / at-floor-with-spend / stalled standing raise, rulings R-a/R-b), with a NEW fallback value 'disputed' for a ladder state the old CASE never covered (WINNER / PACED_WINNER / AT_BAR / DEAD / no snapshot row) — occurring only on a DISPUTED occupant by construction. CLOSURE is agreement-tier gated (P-4/P-5 spirit): a key leaving the occupant set closes through the unchanged first-match reason ladder (KILLED > PAUSED > PARK_LAPSED > LEFT_FAMILY > DEFENSE_EXEMPT > TO_GOOD_SIDE > TO_WAITING > STATE_CHANGED) ONLY when plan A also no longer says NOT_GOOD (both judges agree it left); when plan A still says NOT_GOOD the seat is HELD OPEN instead — a NEW column pair held_reason='HELD_DISPUTED' / held_reason_text (never an overload of closed_reason) — and an existing occupant is never evicted for turning disputed. ADMISSION admits every plan-B-seated keyword (the ledger does not re-ration who holds a seat), but orders SEVERAL SIMULTANEOUS new admissions CONFIRMED before DISPUTED, ranked within tier by the plan's own rank_score DESC, so a CONFIRMED candidate always takes a lower free seat number than a co-admitted DISPUTED one. REOPEN and OBSERVE are unchanged. Brand-defense filtering is inherited from the plan's own universe (the ladder's is_brand_defense flag only, via V_PLAN_WINDOW_JUDGMENT), not re-derived with the three-way test here, so the ledger's admissions reconcile exactly with the plan's; the three-way test still runs as a standing acceptance safety check (A10), not a filter. Idempotent on the same snapshot and the same plan partitions. Orchestrator Task 20.8b, before SP_BUILD_NEXT_WEEK_PLAN (20.8c). Spec: architecture/FAMILY_SEAT_REGISTER.md (ruling R-o)."
)
BEGIN
  DECLARE run_day DATE;      -- today's FACT_KEYWORD_STATE snapshot — freshest ground truth for occupant_kind and closure reason wording
  DECLARE plan_as_of DATE;   -- the most recent FACT_PLAN_NEXT_WEEK partition — the occupant-set and agreement-tier authority

  SET run_day = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`);
  SET plan_as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE plan = 'B');

  IF run_day IS NULL THEN
    SELECT 'SP_MAINTAIN_FAMILY_SEATS: no keyword-state snapshot — nothing to do' AS log_message;
    RETURN;
  END IF;
  IF plan_as_of IS NULL THEN
    SELECT 'SP_MAINTAIN_FAMILY_SEATS: no FACT_PLAN_NEXT_WEEK partition yet — the plan has not run once; nothing to do (the ledger has no plan to unify with)' AS log_message;
    RETURN;
  END IF;

  -- ── 0. THE TWO PLANS AT THE SAME as_of, AND THE TIER THEY IMPLY FOR EVERY KEY THE PLAN KNOWS ──
  -- planA_side reads plan A's own side (side_a — the ladder-state test) for every working-family
  -- keyword the plan judged, whatever plan B did with it. A key absent from plan A entirely (never
  -- judged) defaults to 'GOOD' — the conservative reading in both directions: it cannot CONFIRM a
  -- not-good admission, and it cannot hold open a departure the ladder never spoke about.
  CREATE TEMP TABLE plan_a AS
  SELECT family, campaign_id, keyword_id, side AS side_a
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE plan = 'A' AND as_of = plan_as_of;

  -- today's occupant set: plan B's own SEATED keywords — its already budget-rationed decision.
  CREATE TEMP TABLE occupants_raw AS
  SELECT b.family, b.campaign_id, b.keyword_id, b.ladder_state, b.rank_score,
         IF(COALESCE(a.side_a, 'GOOD') = 'NOT_GOOD', 'CONFIRMED', 'DISPUTED') AS agreement_tier
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` b
  LEFT JOIN plan_a a
    ON a.family = b.family AND a.campaign_id = b.campaign_id AND a.keyword_id = b.keyword_id
  WHERE b.plan = 'B' AND b.as_of = plan_as_of AND b.seat_no IS NOT NULL;

  -- ── 1. OCCUPANT KIND — read fresh from TODAY's FACT_KEYWORD_STATE (unchanged probe test) ──────
  CREATE TEMP TABLE occupants AS
  WITH
  wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
         FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
  k AS (SELECT 7 AS basis_days, 14 AS probe_window_days, 20 AS verdict_clicks),
  probes AS (SELECT DISTINCT CAST(keyword_id AS STRING) AS kid FROM `onyga-482313.OI.T_LIFT_PROBES`),
  lastchg AS (
    SELECT campaign_id, keyword_id, action, DATE(applied_at, 'America/Los_Angeles') AS chg_date, old_bid, new_bid
    FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
    WHERE action IN ('INCREASE_BID', 'REDUCE_BID') AND new_bid IS NOT NULL
      AND keyword_id IS NOT NULL AND keyword_id != ''
    QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY applied_at DESC, change_id DESC) = 1),
  sp AS (SELECT CAST(f.campaign_id AS STRING) AS cid, CAST(f.keyword_id AS STRING) AS kid,
                SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL k.basis_days DAY)
                                  AND DATE_SUB(wm.d, INTERVAL 1 DAY), f.Ads_cost, 0)) AS spend_basis,
                SUM(IF(lc.chg_date IS NOT NULL AND f.date > lc.chg_date AND f.date < wm.d, f.Ads_clicks, 0)) AS clicks_since_raise
         FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN wm CROSS JOIN k
         LEFT JOIN lastchg lc
           ON lc.campaign_id = CAST(f.campaign_id AS STRING) AND lc.keyword_id = CAST(f.keyword_id AS STRING)
         WHERE f.date >= LEAST(DATE_SUB(wm.d, INTERVAL k.basis_days DAY),
                               COALESCE((SELECT MIN(chg_date) FROM lastchg), wm.d))
           AND f.date < wm.d
         GROUP BY 1, 2),
  fks AS (SELECT campaign_id, keyword_id, state, at_floor, current_bid, next_check_date
          FROM `onyga-482313.OI.FACT_KEYWORD_STATE` WHERE snapshot_date = run_day),
  pos AS (
    SELECT o.family, o.campaign_id, o.keyword_id, o.agreement_tier, o.rank_score,
           f.state AS fks_state,
           COALESCE(sp.spend_basis, 0) AS spend_basis,
           p.kid IS NOT NULL AS engine_probe,
           (COALESCE(f.at_floor, FALSE) AND COALESCE(sp.spend_basis, 0) > 0) AS park_probe,
           (f.state = 'PARKED' AND COALESCE(sp.spend_basis, 0) > 0 AND f.next_check_date >= run_day) AS parked_seat,
           (p.kid IS NULL AND NOT COALESCE(f.at_floor, FALSE)
            AND lc.action = 'INCREASE_BID'
            AND f.current_bid >= lc.new_bid - 0.005 AND f.current_bid > lc.old_bid + 0.005
            AND lc.chg_date <= DATE_SUB(run_day, INTERVAL k.probe_window_days DAY)
            AND COALESCE(sp.clicks_since_raise, 0) < k.verdict_clicks) AS stalled_probe
    FROM occupants_raw o
    LEFT JOIN fks f ON f.campaign_id = o.campaign_id AND f.keyword_id = o.keyword_id
    LEFT JOIN sp ON sp.cid = o.campaign_id AND sp.kid = o.keyword_id
    LEFT JOIN probes p ON p.kid = o.keyword_id
    LEFT JOIN lastchg lc ON lc.campaign_id = o.campaign_id AND lc.keyword_id = o.keyword_id
    CROSS JOIN k)
  SELECT family, campaign_id, keyword_id, agreement_tier, rank_score,
         CASE fks_state
           WHEN 'REPRICE'          THEN 'repair'
           WHEN 'FLOOR_PROBATION'  THEN 'probation'
           WHEN 'LOSER'            THEN 'failed'
           WHEN 'REVIVED_SETTLING' THEN 'settling'
           WHEN 'PENDING_SETTLE'   THEN 'settling'
           WHEN 'TRIAL'            THEN IF(engine_probe OR park_probe, 'probe', 'stalled probe')
           WHEN 'PARKED'           THEN IF(parked_seat, 'parked — awaiting re-verdict', 'parked')
           -- NEW VALUE 'disputed' (v27.139): a ladder state the old occupant-kind CASE never had to
           -- handle (WINNER / PACED_WINNER / AT_BAR / DEAD), or the key missing from today's
           -- snapshot entirely. Occurs only on a DISPUTED occupant by construction — a CONFIRMED
           -- occupant's ladder state (side_a's own definition) is always one of the branches above.
           ELSE 'disputed'
         END AS occupant_kind
  FROM pos;

  -- ── 2. CLOSE / HOLD ───────────────────────────────────────────────────────────────────────
  -- A row leaves the occupant set when its key is no longer plan B's seated set. Whether it CLOSES
  -- or is HELD depends on plan A's CURRENT side for that key (same plan_as_of read as step 0):
  --   plan A still NOT_GOOD  → the ladder disagrees with letting it go → HOLD (held_reason)
  --   plan A GOOD or absent  → both judges agree it left            → CLOSE (closed_reason, unchanged ladder)
  CREATE TEMP TABLE leaving_keys AS
  SELECT l.family, l.campaign_id, l.keyword_id, l.opened_on,
         IF(COALESCE(a.side_a, 'GOOD') = 'NOT_GOOD', TRUE, FALSE) AS ladder_disagrees
  FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  LEFT JOIN occupants o
    ON o.family = l.family AND o.campaign_id = l.campaign_id AND o.keyword_id = l.keyword_id
  LEFT JOIN plan_a a
    ON a.family = l.family AND a.campaign_id = l.campaign_id AND a.keyword_id = l.keyword_id
  WHERE l.closed_on IS NULL AND o.campaign_id IS NULL;

  -- ── 2a. HOLD (DISPUTED departure) — refresh memory, do not close ─────────────────────────────
  UPDATE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  SET agreement_tier = 'DISPUTED',
      held_reason = 'HELD_DISPUTED',
      held_reason_text = 'Held — the two judges disagree about this keyword: the 90-day ladder record still calls it not-good but this week\'s window no longer seats it (or never judged it a candidate). It keeps its seat until the next window\'s plan resolves the disagreement — nobody cuts a keyword on one judge\'s word alone.',
      last_observed_kind = 'disputed',
      last_observed_state = COALESCE(f.state, l.last_observed_state)
  FROM leaving_keys x
  LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` f
    ON f.campaign_id = x.campaign_id AND f.keyword_id = x.keyword_id AND f.snapshot_date = run_day
  WHERE l.family = x.family AND l.campaign_id = x.campaign_id AND l.keyword_id = x.keyword_id
    AND l.opened_on = x.opened_on AND l.closed_on IS NULL
    AND x.ladder_disagrees;

  -- ── 2b. CLOSE (both judges agree it left) — the unchanged reason ladder, read from TODAY ───────
  CREATE TEMP TABLE leaving AS
  WITH
  working AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'),
  brand_hit AS (SELECT DISTINCT s.campaign_id, s.keyword_id
                FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
                JOIN (SELECT DISTINCT CONCAT(r'\b', REGEXP_REPLACE(TRIM(LOWER(phrase), ' |,'), r'([.*+?^${}()|\[\]\\])', r'\\\1'), r'\b') AS rx
                      FROM `onyga-482313.OI.DIM_BRAND_PHRASES`
                      WHERE phrase_type = 'BRAND' AND TRIM(LOWER(phrase), ' |,') != '') b
                  ON REGEXP_CONTAINS(LOWER(s.target_text), b.rx)),
  today AS (SELECT s.campaign_id, s.keyword_id, s.family, s.state,
                   (COALESCE(s.is_brand_defense, FALSE)
                    OR REGEXP_CONTAINS(UPPER(COALESCE(s.campaign_name, '')), r'BRAND DEFENSE')
                    OR bh.keyword_id IS NOT NULL) AS is_brand_defense,
                   s.family IN (SELECT family FROM working) AS in_working
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
            LEFT JOIN brand_hit bh ON bh.campaign_id = s.campaign_id AND bh.keyword_id = s.keyword_id
            WHERE s.snapshot_date = run_day),
  coded AS (
    SELECT lk.family, lk.campaign_id, lk.keyword_id, lk.opened_on,
           CASE
             WHEN t.campaign_id IS NULL
               THEN IF(COALESCE(l.last_observed_state IN ('LOSER', 'DEAD'),
                                l.occupant_kind_at_open = 'failed'), 'KILLED', 'PAUSED')
             WHEN t.family IS DISTINCT FROM lk.family OR NOT t.in_working THEN 'LEFT_FAMILY'
             WHEN t.is_brand_defense THEN 'DEFENSE_EXEMPT'
             WHEN t.state = 'DEAD'   THEN 'KILLED'
             WHEN t.state = 'PARKED' THEN 'PARK_LAPSED'
             WHEN t.state = 'TRIAL'  THEN 'TO_WAITING'
             WHEN t.state IN ('WINNER', 'PACED_WINNER', 'AT_BAR') THEN 'TO_GOOD_SIDE'
             ELSE 'STATE_CHANGED'
           END AS closed_reason,
           CASE t.state
             WHEN 'LAUNCH_CONTAINED' THEN 'launch, contained by the launch controller'
             WHEN 'REVIVED_SETTLING' THEN 'revived, its verdict settling'
             WHEN 'PENDING_SETTLE'   THEN 'a verdict pending until its clicks settle'
             WHEN 'REPRICE'          THEN 'losing, being re-priced toward its bar'
             WHEN 'FLOOR_PROBATION'  THEN 'losing, on probation at its floor'
             WHEN 'LOSER'            THEN 'failed at its floor'
             ELSE CONCAT('an unmapped ladder state (', COALESCE(t.state, 'none'), ')')
           END AS state_words
    FROM leaving_keys lk
    JOIN `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
      ON l.family = lk.family AND l.campaign_id = lk.campaign_id AND l.keyword_id = lk.keyword_id
     AND l.opened_on = lk.opened_on AND l.closed_on IS NULL
    LEFT JOIN today t ON t.campaign_id = lk.campaign_id AND t.keyword_id = lk.keyword_id
    WHERE NOT lk.ladder_disagrees)
  SELECT c.*,
         CASE c.closed_reason
           WHEN 'KILLED'         THEN 'The keyword is gone from the snapshot after its last verdict was failed or dead, or the ladder now reads dead: the book paused a failed keyword. The seat is free.'
           WHEN 'PAUSED'         THEN 'The keyword is gone from the snapshot, or the ladder now reads parked, without a failed verdict first. The seat is free.'
           WHEN 'PARK_LAPSED'    THEN 'The keyword reads parked on the ladder but is no longer a parked seat: it has no spend on the basis window, or its re-verdict appointment has passed. A parked keyword that still spends past its appointment is a leak (pause row). The seat is free.'
           WHEN 'LEFT_FAMILY'    THEN 'The keyword is still tracked but now belongs to another family, or its family left the working (HARVEST) book. The seat is free.'
           WHEN 'DEFENSE_EXEMPT' THEN 'The keyword is now brand defense. Defense is never judged on profit, so it is never seated. The seat is free.'
           WHEN 'TO_GOOD_SIDE'   THEN 'The keyword is now winning or at its bar: it moved to the 80% side. The seat is free.'
           WHEN 'TO_WAITING'     THEN 'The keyword is still a trial but is no longer bought at an entry or park bid and is not a stalled probe: it is back to waiting for clicks on the 80% side, no verdict yet. The seat is free.'
           WHEN 'STATE_CHANGED'  THEN CONCAT('The keyword left the seat set — it now reads ', c.state_words, '. The seat is free.')
         END AS closed_reason_text
  FROM coded c;

  -- agreement_tier at close reads 'CONFIRMED': this branch (leaving_keys.NOT ladder_disagrees) is
  -- reached exactly when both plan A and plan B agree the keyword is no longer a not-good occupant
  -- — an AGREED departure, the same sense of "CONFIRMED" the spec uses for closure ("both judges
  -- agree the keyword left the not-good set, or both agree it should close"), distinct from but
  -- symmetric with the admission sense (both agree it IS not-good).
  UPDATE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  SET closed_on = run_day, closed_reason = x.closed_reason, closed_reason_text = x.closed_reason_text,
      agreement_tier = 'CONFIRMED', held_reason = NULL, held_reason_text = NULL
  FROM leaving x
  WHERE l.family = x.family AND l.campaign_id = x.campaign_id AND l.keyword_id = x.keyword_id
    AND l.opened_on = x.opened_on AND l.closed_on IS NULL;

  -- ── 3. REOPEN (same-day flip keeps its number and keeps the key unique) ──────────────────
  UPDATE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  SET closed_on = NULL, closed_reason = NULL, closed_reason_text = NULL,
      held_reason = NULL, held_reason_text = NULL
  FROM occupants o
  WHERE l.family = o.family AND l.campaign_id = o.campaign_id AND l.keyword_id = o.keyword_id
    AND l.closed_on = run_day
    AND NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` z
                    WHERE z.family = l.family AND z.campaign_id = l.campaign_id
                      AND z.keyword_id = l.keyword_id AND z.closed_on IS NULL);

  -- ── 4. ADMIT at the lowest free number, CONFIRMED before DISPUTED (v27.139) ────────────────
  INSERT INTO `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
    (family, campaign_id, keyword_id, seat_no, opened_on, closed_on, closed_reason, occupant_kind_at_open,
     last_observed_kind, last_observed_state, closed_reason_text, agreement_tier, held_reason, held_reason_text)
  WITH
  open_seats AS (SELECT family, seat_no FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL),
  open_seats_keys AS (SELECT family, campaign_id, keyword_id
                      FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL),
  admits AS (
    SELECT o.*
    FROM occupants o
    LEFT JOIN open_seats_keys l
      ON l.family = o.family AND l.campaign_id = o.campaign_id AND l.keyword_id = o.keyword_id
    WHERE l.campaign_id IS NULL),
  need AS (
    SELECT n.family, COUNT(*) AS n_new,
           (SELECT COUNT(*) FROM open_seats s WHERE s.family = n.family) AS n_open
    FROM admits n GROUP BY n.family),
  free AS (
    SELECT c.family, cand AS seat_no,
           ROW_NUMBER() OVER (PARTITION BY c.family ORDER BY cand) AS rk
    FROM need c, UNNEST(GENERATE_ARRAY(1, c.n_open + c.n_new)) AS cand
    LEFT JOIN open_seats s ON s.family = c.family AND s.seat_no = cand
    WHERE s.seat_no IS NULL),
  ranked AS (
    SELECT n.*,
           ROW_NUMBER() OVER (PARTITION BY n.family
             ORDER BY CASE n.agreement_tier WHEN 'CONFIRMED' THEN 1 ELSE 2 END,
                      COALESCE(n.rank_score, 0) DESC, n.campaign_id, n.keyword_id) AS rk
    FROM admits n)
  SELECT r.family, r.campaign_id, r.keyword_id, f.seat_no, run_day,
         CAST(NULL AS DATE), CAST(NULL AS STRING), r.occupant_kind,
         r.occupant_kind, CAST(NULL AS STRING), CAST(NULL AS STRING), r.agreement_tier,
         CAST(NULL AS STRING), CAST(NULL AS STRING)
  FROM ranked r
  JOIN free f ON f.family = r.family AND f.rk = r.rk;

  -- last_observed_state on a fresh admission — set from today's ladder, mirroring what OBSERVE
  -- would write on the very next run (kept out of the INSERT above to avoid a second FACT_KEYWORD_STATE
  -- read there; done here in one UPDATE against the rows just inserted).
  UPDATE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  SET last_observed_state = f.state
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` f
  WHERE l.opened_on = run_day AND l.closed_on IS NULL AND l.last_observed_state IS NULL
    AND f.campaign_id = l.campaign_id AND f.keyword_id = l.keyword_id AND f.snapshot_date = run_day;

  -- ── 5. OBSERVE — refresh memory (kind, state, tier) for every open row still an occupant ────
  UPDATE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  SET last_observed_kind = o.occupant_kind, last_observed_state = COALESCE(f.state, l.last_observed_state),
      agreement_tier = o.agreement_tier, held_reason = NULL, held_reason_text = NULL
  FROM occupants o
  LEFT JOIN `onyga-482313.OI.FACT_KEYWORD_STATE` f
    ON f.campaign_id = o.campaign_id AND f.keyword_id = o.keyword_id AND f.snapshot_date = run_day
  WHERE l.family = o.family AND l.campaign_id = o.campaign_id AND l.keyword_id = o.keyword_id
    AND l.closed_on IS NULL
    AND (l.last_observed_kind IS DISTINCT FROM o.occupant_kind
         OR l.last_observed_state IS DISTINCT FROM COALESCE(f.state, l.last_observed_state)
         OR l.agreement_tier IS DISTINCT FROM o.agreement_tier
         OR l.held_reason IS NOT NULL);

  SELECT FORMAT('SP_MAINTAIN_FAMILY_SEATS: snapshot %s, plan as_of %s — %d occupants (plan B seated) — %d closed, %d held (disputed)',
                CAST(run_day AS STRING), CAST(plan_as_of AS STRING),
                (SELECT COUNT(*) FROM occupants),
                (SELECT COUNT(*) FROM leaving),
                (SELECT COUNT(*) FROM leaving_keys WHERE ladder_disagrees)) AS log_message;
END;
