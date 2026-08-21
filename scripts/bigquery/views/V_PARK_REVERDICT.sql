-- =============================================
-- V_PARK_REVERDICT — settled re-judgment of every parked / STOPped / recently-revived keyword
-- (v27.48 part 1, 2026-08-09). Spec: architecture/SEASON_CONTEXT_LEDGER.md §7 (settle doctrine).
--
-- ############################################################################
-- # v27.62 — THE GP RULE: READ FACT_AMAZON_ADS.GROSS_PROFIT. NEVER RECOMPUTE. #
-- ############################################################################
-- (Ori 2026-08-13, found by checking the panel against Amazon.) Every gross-profit number in this
-- view is now the STORED FACT_AMAZON_ADS.GROSS_PROFIT column. The old formula
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
-- Same fix, same day: V_LOW_STOCK_ADS (v27.61) and the other seven engine views.
--
-- WHY (iteration-6 root causes, Ori approved 2026-08-09): the engines condemn keywords on clicks
-- whose sales have not arrived (SP sales accrue to D+7, SB to D+14; spend settles ~D+3) — ~20% of
-- the Aug 2-6 park wave now shows settled condemning-window GP-ROAS >= 1.0. Ori's rule:
-- "no condemnation before settle, re-judgment at settle" — for all keywords that have been
-- stopped, check whether their ads net ROAS changed once settled; if so, revive them.
--
-- POPULATION (one row per (campaign_id, keyword_id) from DIM_KEYWORD current config — which
-- carries BOTH SP and SB keyword config (discovered at wiring: 26 of the 33 calibrated revives
-- sit in SB campaigns). channel = the campaign's type; settle_due is channel-aware (D+7 SP /
-- D+14 SB after the last pre-park click). The BAR deliberately stays on the CALIBRATED cut
-- (settle_cut = today-7 for every row — the exact frame the 2026-08-09 grid was approved on):
-- for SB rows the day-8..14 sales tail only UNDERSTATES GP, so the error direction is a missed
-- revive that self-heals on a later daily run — never a false revive. A false CONFIRM_PARK on
-- an SB row likewise flips back within ~7 days as the tail accrues (the snapshot re-judges
-- daily); the engines' CONFIRM_PARK block is re-read from each day's snapshot, not sticky.):
--   PARKED — is_current ENABLED bid <= $0.26, auto clauses excluded (asin/category product
--            targets KEPT: they park and revive like keywords; season/gate joins simply read
--            NULL for them). The 2026-08-09 stock: 551 rows across 54 campaigns.
--   LIVE   — rows carrying revival/manual protection the engines must read:
--            (a) revive-shaped raise applied within 45d (old <= 0.26 -> new >= 0.305) — the
--                post-revival settle veto lives here;
--            (b) last applied change source = 'MANUAL' within 14d (Cause 3: OOB parked over
--                Ori's Aug-4 manual raise within days — Ori's hand outranks the engines 14d).
--
-- REVERDICT (PARKED rows; calibrated 2026-08-09 on the full 551 — read-only grid in the batch
-- record; bench $6,126 settled-90d GP on $5,364 settled spend across the 33 revives):
--   REVIVE         settled-90d [settle_cut-89, settle_cut] at (campaign, keyword_id) grain:
--                  clicks >= 10 AND GP-ROAS >= 1.0 (or >= 0.8 with a season-WIN verdict for the
--                  text — 8 rows, +$2,172 bench GP, the right keywords live entering BTS peak).
--                  Bar is flat 10-15 (identical set); dropping to 5 adds only 3 tiny rows.
--   CONFIRM_PARK   >= 10 settled clicks and the bar FAILS — the park was correct (60 rows at
--                  blended 0.34x validate the floor). Also: gate entry_state = STOP without a
--                  current-occurrence settled release (season-gate precedence, guard 4 — the 2
--                  conflicted texts are flagged for Ori's gate re-audit, never auto-released),
--                  and one-revive-per-occurrence re-parks (guard 3). MUST NOT RESURFACE: the
--                  engines block ACTIVATE / probe promotion on these rows.
--   PENDING_SETTLE settled evidence still thin (< 10 settled clicks) and the last pre-park click
--                  has not settled yet (settle_due = last pre-park click + 7) — judged at settle.
--   INSUFFICIENT   < 10 settled clicks, nothing pending — stays in the normal candidate queue.
--
-- REVIVE BID (calibrated): clamp( min(pre-park bid, 1.10 x settled-90d CPC), $0.31, $1.50 );
-- unknown-era rows (no logged park — launch-queue creation and/or the Aug-6 upload-failure log
-- gap): clamp(1.10 x settled CPC, $0.31, $1.50). Median $0.40. The $0.31 floor deliberately
-- clears both engines' bid > 0.30 park-detection threshold AND repaces cheap proven winners
-- (Cause 4: 'gift for girls' 613 settled clicks at $0.186 CPC 1.98x -> +67% pressure). NEVER the
-- OOB $1 ACTIVATE entry — these are proven records with anchors, not anchorless probes; $1
-- entries on sub-$0.30-CPC winners is Cause-2 behavior in reverse.
--
-- ANTI-CHURN GUARDS (encoded as data; engines consume FACT_PARK_REVERDICT, the snapshot):
--   engine_immune       post-revival settle veto (guard 1): a revived keyword (>= 10 settled
--                       clicks + >= 1 settled order BEFORE the revival — distinguishes a true
--                       revival from a fresh $1 probe activation, which keeps its 20-click
--                       discipline) is immune to PARK / PARK_WAIT / CUT_TO_* / STOP-class
--                       condemnations until >= 10 NEW settled clicks accrue post-revival.
--                       DARK_BRAKE / EASE / TRIM stay live same-day — dark is never a hold.
--                       Also carries the 14d manual hold (Cause 3).
--   re-park guard       one revive per season occurrence (guard 3): a keyword re-parked AFTER a
--                       revive inside the CURRENT V_SEASON_CONTEXT occurrence reads CONFIRM_PARK
--                       until the occurrence turns — with the settle veto in place, a landed
--                       re-park implies fresh settled evidence (or Ori's hand).
--   manual_parked_recent (Cause 3, other direction): a MANUAL park < 14d old is never
--                       auto-revived by the engines (the advisory sweep may still list it —
--                       Ori decides); engines also never generic-ACTIVATE it at $1.
--
-- Seat coupling (guard 2) lives in the ENGINES: ACTIVATE_REVIVE only where seat_rank <= slots;
-- queue-stuck settled winners are a BUDGET decision (slots = round(budget/$4) -> +$4/day each),
-- routed to Ori — reviving into PARK_WAIT is an empty promise (v27.29).
--
-- v27.53 FIX (2026-08-12) — THE SEASON RELAXATION IS OCCURRENCE-SCOPED AND AGE-BOUNDED
-- (defect 5 of the iteration-6 audit; the last item standing between Ori and the Revivals panel).
-- The ">= 0.8 with a season WIN" arm of the REVIVE bar is the only way a keyword whose SETTLED
-- record LOSES money can be brought back. Until now its licence was `seas` = COUNTIF(verdict =
-- 'WIN') over the WHOLE FACT_KEYWORD_SEASON_VERDICT table, matched on lowercase text: ANY win,
-- ANY season, ANY year, back to 2024-09, mature or not. That is the exact defect v27.52 FIX 1
-- removed from V_KEYWORD_GUARD.season_win_prior — it survived here because the two views carry
-- their own copies of the same lookup.
-- Measured on the 2026-08-12 population, 6 of the 29 REVIVE rows were sub-1.0 rows riding this
-- relaxation (7,415 settled clicks, $2,114.99 settled spend -> $1,793.83 settled GP, -$321.16):
--   'spa kit for girls ages 12-14'  0.821x  BTS_2025 WIN exists but mature_at_start = FALSE
--                                           (first click 2025-07-19, 13d before the occurrence)
--   '15 year old girl gift ideas'   0.827x  relaxed by a XMAS_PEAK_2024 WIN — occurrence ended
--                                           2024-12-28, TWENTY MONTHS before today's BTS peak
--   'girls journal kit'             0.835x  7 WINs, NONE of them BTS — OFF/PRIME/EASTER/VDAY/XMAS
--   'category="Kids Scrapbooking Kits"' 0.868x  4 WINs, NONE BTS (GRAD/MDAY/EASTER + an immature
--                                           XMAS_PEAK_2025) — the "wrong season entirely" shape
-- The fix mirrors v27.52 FIX 1(b) verbatim — the `seas` CTE now applies V_KEYWORD_CONTEXT_GATE's
-- `prior` selection discipline: same family match (REGEXP_REPLACE of the label against TODAY's
-- occurrence), same closed-prior-occurrence test (occurrence_end < occurrence_start), same §4
-- maturity guard (mature_at_start), same family != 'OFF' exclusion — PLUS the age bound this
-- view's defect specifically calls for: the prior occurrence must have ENDED within
-- win_max_age_days (400) of the current occurrence's start, i.e. ONE cycle back, never two.
-- The WIN amnesty, the LOSS entry block and the guard's settle amnesty now read the SAME memory.
-- FIX 1(a) (the catastrophic override) needs no mirror here: this bar's season floor is 0.80,
-- already above the 0.60 catastrophic line, so a catastrophic row can never be revived anyway.
-- Two audit columns keep the history visible without letting it decide: n_win_any / win_labels_any
-- (the OLD unscoped count — display only, never a licence) and season_relax_applied (TRUE exactly
-- when a row is REVIVE only because of the relaxation). win_prior_end dates the licence.
-- Measured effect: REVIVE 29 -> 25. Four rows move to CONFIRM_PARK on 2,432 settled clicks,
-- $1,178.49 settled spend -> $992.83 settled GP (-$185.66). Two sub-1.0 rows KEEP their revival on
-- a real BTS_2025 mature WIN ('gifts for tween girls' 1,017c +$62.57; 'gifts for teen girls' 51c
-- +$3.21). No row moves in the other direction; CONFIRM_PARK / PENDING_SETTLE / INSUFFICIENT are
-- otherwise untouched, and NO revive_bid changes (the bid formula never read the season memory).
-- Keyed parity old-vs-new at one instant, 619 rows, 0 added / 0 dropped: exactly six columns move
-- (n_win, win_labels 154 rows — the memory itself; passes_bar 6; reverdict 4; reverdict_reason 7;
-- stop_released 2). The other 53 columns are byte-identical. Of the 6 passes_bar changes, 2 are on
-- LIVE rows where passes_bar is inert (reverdict is NULL for LIVE); both stop_released changes are
-- on rows with entry_state != 'STOP', where stop_released is inert. So: 4 verdicts moved, and
-- nothing else in the view moved.
-- The 400-day bound removes 0 additional rows TODAY (BTS_2024 ran 2024-09-05..09-14, inside the
-- first 10 days of all ads history, so it carries ZERO mature verdicts) — it is installed as the
-- structural guarantee for the next cycle, not as today's saving.
--
-- v27.52 FIX 2 (2026-08-12) — EVIDENCE IS KEYED ON keyword_id, NOT ON TEXT. The v27.48 build
-- joined FACT_AMAZON_ADS on (campaign_id, targeting text), which handed one target's record to
-- every ENABLED sibling sharing that text in the same campaign (12 colliding pairs / 24 targets
-- today) and made CATEGORY targets invisible (DIM stores the category ID, FACT the NAME). See the
-- fd_raw / tgt_name / solo / fd_noid block below for the full statement and the two measured
-- consequences. Two new output columns: fact_targeting (the FACT-reported name) and evidence_join
-- (KEYWORD_ID / TEXT_FALLBACK / NONE). The season lookup now resolves through the same map, so a
-- category target reaches its own season memory. NOT changed in v27.52: the season relaxation
-- itself is still neither occurrence-scoped nor recency-bounded (defect 5, measured not fixed).
--
-- DETERMINISM: plain SUMs over fixed windows; ARRAY_AGG fully tie-broken; no ANY_VALUE pairs
-- (v27.46 lesson); settle_cut = CURRENT_DATE(LA) - 7, evaluated on today's FACT restatement.
-- GP formula = tier-COGS exactly as V_OOB_KEYWORD computes it. Timezone: applied_at -> LA date
-- (FACT_PPC_CHANGE_LOG doctrine).
--
-- CONSUMERS: SP_SNAPSHOT_PARK_REVERDICT -> FACT_PARK_REVERDICT (the engines read the SNAPSHOT,
-- never this view — plan-cost doctrine: V_OOB_KEYWORD is at the planner ceiling and re-plans
-- V_KEYWORD_LIFT, so this view's FACT+gate subtree must not enter either engine plan); the
-- one-time 2026-08-09 sweep (OI/.tmp/park_revival_sweep_20260809.xlsx, ADVISORY — coacher
-- no-auto-fill: nothing auto-uploads).
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PARK_REVERDICT` AS
WITH
k AS (
  SELECT 0.26 AS park_bid_max, 0.31 AS revive_floor, 1.50 AS revive_cap,
         10 AS min_settled_clk, 1.0 AS bar_roas, 0.8 AS bar_roas_season,
         7 AS settle_days, 14 AS manual_hold_days, 45 AS revive_lookback_days,
         -- v27.53: the season relaxation's age bound. A qualifying prior occurrence must have
         -- ENDED within this many days of the CURRENT occurrence's start — one cycle back for an
         -- annual season (BTS_2025 ended 321d before BTS_2026 started), never two (BTS_2024: 686d).
         400 AS win_max_age_days
),
d AS (
  SELECT CURRENT_DATE('America/Los_Angeles') AS today,
         DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY) AS settle_cut
),
occ AS (
  -- v27.53: `family` added — the season relaxation is scoped against it (same derivation as
  -- V_KEYWORD_CONTEXT_GATE.cur and V_KEYWORD_GUARD.curctx: strip the trailing _YYYY).
  SELECT occurrence_key, context_label, occurrence_start, occurrence_end,
         REGEXP_REPLACE(context_label, r'_\d{4}$', '') AS family
  FROM `onyga-482313.OI.V_SEASON_CONTEXT`
  WHERE date = CURRENT_DATE('America/Los_Angeles')
),
-- every current ENABLED SP keyword / product target (auto clauses out), one row per (campaign, keyword)
kw AS (
  SELECT campaign_id, keyword_id, ad_group_id, keyword_text, match_type, current_bid
  FROM (
    SELECT CAST(campaign_id AS STRING) AS campaign_id, CAST(keyword_id AS STRING) AS keyword_id,
           CAST(ad_group_id AS STRING) AS ad_group_id, keyword_text, match_type, bid AS current_bid,
           ROW_NUMBER() OVER (PARTITION BY CAST(campaign_id AS STRING), CAST(keyword_id AS STRING)
                              ORDER BY effective_from DESC, bid DESC NULLS LAST) AS rn
    FROM `onyga-482313.OI.DIM_KEYWORD`
    WHERE is_current AND UPPER(state) = 'ENABLED'
      AND LOWER(keyword_text) NOT IN ('close-match', 'loose-match', 'complements', 'substitutes')
  ) WHERE rn = 1
),
-- last applied park event (bid change INTO park level) per keyword_id
park AS (
  SELECT keyword_id, COUNT(*) AS n_park_events,
         ARRAY_AGG(STRUCT(DATE(applied_at, 'America/Los_Angeles') AS park_date,
                          old_bid AS pre_park_bid, new_bid AS park_bid, source AS park_source)
                   ORDER BY applied_at DESC, new_bid, COALESCE(old_bid, -1) LIMIT 1)[OFFSET(0)] AS pk
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action IN ('REDUCE_BID', 'INCREASE_BID') AND keyword_id IS NOT NULL
    AND new_bid IS NOT NULL AND new_bid <= 0.26
  GROUP BY 1
),
-- last revive-shaped raise (park level -> >= $0.305) per keyword_id — the revival event
raise_ev AS (
  SELECT keyword_id,
         ARRAY_AGG(STRUCT(DATE(applied_at, 'America/Los_Angeles') AS revive_date,
                          new_bid AS revive_bid_applied, source AS revive_source)
                   ORDER BY applied_at DESC, new_bid, COALESCE(old_bid, -1) LIMIT 1)[OFFSET(0)] AS rv
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action IN ('REDUCE_BID', 'INCREASE_BID') AND keyword_id IS NOT NULL
    AND old_bid IS NOT NULL AND old_bid <= 0.26 AND new_bid IS NOT NULL AND new_bid >= 0.305
  GROUP BY 1
),
-- last applied bid change of any shape per keyword_id (manual-hold detection)
lastchg AS (
  SELECT keyword_id,
         ARRAY_AGG(STRUCT(DATE(applied_at, 'America/Los_Angeles') AS chg_date, source AS src)
                   ORDER BY applied_at DESC, COALESCE(new_bid, -1), COALESCE(old_bid, -1) LIMIT 1)[OFFSET(0)] AS lc
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action IN ('REDUCE_BID', 'INCREASE_BID') AND keyword_id IS NOT NULL
  GROUP BY 1
),
pop AS (
  SELECT kw.campaign_id, kw.keyword_id, kw.ad_group_id, kw.keyword_text, kw.match_type, kw.current_bid,
         kw.current_bid <= x.park_bid_max AS is_parked,
         p.pk.park_date, p.pk.pre_park_bid, p.pk.park_bid, p.pk.park_source,
         COALESCE(p.n_park_events, 0) AS n_park_events,
         r.rv.revive_date, r.rv.revive_bid_applied, r.rv.revive_source,
         l.lc.chg_date AS last_change_date, l.lc.src AS last_source
  FROM kw CROSS JOIN k x CROSS JOIN d
  LEFT JOIN park p ON p.keyword_id = kw.keyword_id
  LEFT JOIN raise_ev r ON r.keyword_id = kw.keyword_id
  LEFT JOIN lastchg l ON l.keyword_id = kw.keyword_id
  WHERE kw.current_bid <= x.park_bid_max
     OR (r.rv.revive_date IS NOT NULL AND r.rv.revive_date >= DATE_SUB(d.today, INTERVAL 45 DAY))
     OR (l.lc.src = 'MANUAL' AND l.lc.chg_date >= DATE_SUB(d.today, INTERVAL 14 DAY))
),
-- daily FACT at (campaign, keyword_id) grain for the population targets. GP = the STORED
-- FACT_AMAZON_ADS.GROSS_PROFIT column — see THE GP RULE in the header. The recompute that used to
-- sit here (and its T_PRICE_COST_TIER join) is gone; this is the same currency V_OOB_KEYWORD,
-- V_KEYWORD_GUARD and V_CHANGE_SCORECARD now speak, so a revive bar and a scorecard verdict still
-- compare like for like.
--
-- v27.52 FIX 2 — the evidence join was keyed on (campaign_id, targeting TEXT), discarding
-- keyword_id. Two proven consequences, both removed here:
--   (a) PHANTOM EVIDENCE. Text is not unique inside a campaign: 12 (campaign, text) pairs across
--       24 ENABLED targets collide today (same ASIN targeted from two ad groups). Every colliding
--       target read the SUM of the whole group's record. Campaign 341550011573799 carries
--       asin="B0CQ896SQT" twice — 357926511307572 (live $0.72, 2,318 lifetime clicks) and
--       304857473067279 (parked $0.24, ZERO clicks of its own). The parked one reverdicted REVIVE
--       and was priced at $0.75 (1.10 x a $0.681 settled CPC) entirely off its sibling's record.
--   (b) CATEGORY TARGETS 100% INVISIBLE. DIM_KEYWORD stores a category target as its category ID
--       (category="166073011"); FACT_AMAZON_ADS stores the NAME
--       (category="Kids' Scrapbooking Kits"). Text never matched, so a real 503-click / $370.78 /
--       0.868x settled record read as zero evidence.
-- keyword_id is the one key both sides agree on (non-NULL on 100% of FACT rows in the window, same
-- id space as DIM_KEYWORD), so keying on it resolves ID <-> NAME by construction.
fd_raw AS (
  SELECT CAST(a.campaign_id AS STRING) AS cid, CAST(a.keyword_id AS STRING) AS kid,
         a.targeting AS tgt, a.date,
         SUM(a.Ads_clicks) AS clk, SUM(a.Ads_cost) AS sp, SUM(a.Ads_orders) AS ord,
         SUM(a.GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN (SELECT DISTINCT campaign_id, keyword_id FROM pop) p
    ON CAST(a.campaign_id AS STRING) = p.campaign_id
   AND CAST(a.keyword_id AS STRING) = p.keyword_id
  WHERE a.keyword_id IS NOT NULL
  GROUP BY 1, 2, 3, 4
),
-- FACT-side reported name per target — the ID <-> NAME resolver. DIM_KEYWORD's text is the target's
-- CONFIG identity (what goes on a bulksheet); FACT_AMAZON_ADS' targeting is its REPORTED identity,
-- and every text-keyed memory built downstream of FACT — FACT_KEYWORD_SEASON_VERDICT included —
-- is keyed on the reported form. For a category target those differ (ID vs NAME), so the season
-- lookup below resolves through this map instead of the raw DIM text. Deterministic: fully
-- tie-broken ARRAY_AGG, no ANY_VALUE.
-- (ROW_NUMBER rather than ARRAY_AGG, and the ambiguity count below is an analytic COUNT rather
-- than HAVING COUNT(DISTINCT): BigQuery rejects "aggregations of aggregations" once these CTEs
-- are inlined. Determinism is identical — tgt is unique inside (cid, kid), so the tie-break is total.)
tgt_name AS (
  SELECT cid, kid, tgt AS fact_tgt
  FROM (
    SELECT cid, kid, tgt, ROW_NUMBER() OVER (PARTITION BY cid, kid ORDER BY n_clk DESC, tgt) AS rn
    FROM (
      SELECT CAST(a.campaign_id AS STRING) AS cid, CAST(a.keyword_id AS STRING) AS kid,
             a.targeting AS tgt, SUM(a.Ads_clicks) AS n_clk
      FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
      JOIN (SELECT DISTINCT campaign_id, keyword_id FROM pop) p
        ON CAST(a.campaign_id AS STRING) = p.campaign_id
       AND CAST(a.keyword_id AS STRING) = p.keyword_id
      WHERE a.keyword_id IS NOT NULL
      GROUP BY 1, 2, 3
    )
  ) WHERE rn = 1
),
-- (campaign, text) pairs that resolve to exactly ONE population target, where "text" is either the
-- DIM config text or the FACT reported name. This is the only place an id-less FACT row may be
-- attributed by text: attributing one to an AMBIGUOUS text is precisely defect (a) above.
pop_txt AS (
  SELECT p.campaign_id, p.keyword_id, p.keyword_text AS txt FROM pop p
  UNION DISTINCT
  SELECT p.campaign_id, p.keyword_id, n.fact_tgt
  FROM pop p JOIN tgt_name n ON n.cid = p.campaign_id AND n.kid = p.keyword_id
  WHERE n.fact_tgt IS NOT NULL
),
solo AS (
  SELECT campaign_id, txt, keyword_id
  FROM (SELECT campaign_id, txt, keyword_id,
               COUNT(*) OVER (PARTITION BY campaign_id, txt) AS n_kid
        FROM pop_txt)
  WHERE n_kid = 1
),
-- text fallback: FACT rows carrying NO keyword_id cannot be keyed on it. Current stock: 0 rows
-- (keyword_id is non-NULL on every FACT row in the window, all four source_tables) — this arm is a
-- safety valve, not a live path. evidence_join on the output row says which arm fed it.
fd_noid AS (
  SELECT s.campaign_id AS cid, s.keyword_id AS kid, a.date,
         SUM(a.Ads_clicks) AS clk, SUM(a.Ads_cost) AS sp, SUM(a.Ads_orders) AS ord,
         SUM(a.GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN solo s ON CAST(a.campaign_id AS STRING) = s.campaign_id AND a.targeting = s.txt
  WHERE a.keyword_id IS NULL
  GROUP BY 1, 2, 3
),
fd AS (
  SELECT cid, kid, date, clk, sp, ord, gp, 'ID' AS src FROM fd_raw
  UNION ALL
  SELECT cid, kid, date, clk, sp, ord, gp, 'TEXT' AS src FROM fd_noid
),
w AS (
  SELECT p.campaign_id, p.keyword_id,
    SUM(IF(f.date BETWEEN DATE_SUB(d.settle_cut, INTERVAL 89 DAY) AND d.settle_cut, f.clk, 0)) AS s90_clk,
    ROUND(SUM(IF(f.date BETWEEN DATE_SUB(d.settle_cut, INTERVAL 89 DAY) AND d.settle_cut, f.sp, 0)), 2) AS s90_sp,
    SUM(IF(f.date BETWEEN DATE_SUB(d.settle_cut, INTERVAL 89 DAY) AND d.settle_cut, f.ord, 0)) AS s90_ord,
    ROUND(SUM(IF(f.date BETWEEN DATE_SUB(d.settle_cut, INTERVAL 89 DAY) AND d.settle_cut, f.gp, 0)), 2) AS s90_gp,
    SUM(IF(p.park_date IS NOT NULL
           AND f.date BETWEEN DATE_SUB(p.park_date, INTERVAL 89 DAY) AND LEAST(p.park_date, d.settle_cut),
           f.clk, 0)) AS cond_clk,
    ROUND(SUM(IF(p.park_date IS NOT NULL
                 AND f.date BETWEEN DATE_SUB(p.park_date, INTERVAL 89 DAY) AND LEAST(p.park_date, d.settle_cut),
                 f.sp, 0)), 2) AS cond_sp,
    SUM(IF(p.park_date IS NOT NULL
           AND f.date BETWEEN DATE_SUB(p.park_date, INTERVAL 89 DAY) AND LEAST(p.park_date, d.settle_cut),
           f.ord, 0)) AS cond_ord,
    ROUND(SUM(IF(p.park_date IS NOT NULL
                 AND f.date BETWEEN DATE_SUB(p.park_date, INTERVAL 89 DAY) AND LEAST(p.park_date, d.settle_cut),
                 f.gp, 0)), 2) AS cond_gp,
    SUM(IF(f.date <= d.settle_cut, f.clk, 0)) AS life_settled_clk,
    MAX(IF(f.clk > 0 AND f.date <= COALESCE(p.park_date, d.today), f.date, NULL)) AS last_prepark_click,
    SUM(IF(p.revive_date IS NOT NULL AND f.date > p.revive_date AND f.date <= d.settle_cut, f.clk, 0)) AS post_revive_settled_clk,
    SUM(IF(p.revive_date IS NOT NULL AND f.date <= DATE_SUB(p.revive_date, INTERVAL 7 DAY), f.clk, 0)) AS pre_revive_settled_clk,
    SUM(IF(p.revive_date IS NOT NULL AND f.date <= DATE_SUB(p.revive_date, INTERVAL 7 DAY), f.ord, 0)) AS pre_revive_settled_ord,
    LOGICAL_OR(f.src = 'ID') AS has_id_evidence,
    LOGICAL_OR(f.src = 'TEXT') AS has_text_evidence
  FROM pop p
  CROSS JOIN d
  JOIN fd f ON f.cid = p.campaign_id AND f.kid = p.keyword_id
  GROUP BY 1, 2
),
-- campaign type — channel-aware settle horizon (D+7 SP / D+14 SB)
ctype AS (
  SELECT CAST(campaign_id AS STRING) AS cid,
         IF(LOGICAL_OR(UPPER(COALESCE(campaign_type, 'SP')) = 'SB'), 'SB', 'SP') AS channel
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  GROUP BY 1
),
-- season memory by text. FACT_KEYWORD_SEASON_VERDICT is keyed on the FACT-REPORTED form, so the
-- join below reads the resolved name (tgt_name), not the raw DIM config text — otherwise a
-- category target's whole season memory is unreachable: category="166073011" (DIM) carries no
-- verdict rows while category="Kids' Scrapbooking Kits" (FACT) carries nine.
-- v27.53 FIX — OCCURRENCE-SCOPED, MATURE, AGE-BOUNDED. This is the licence for the 0.80 arm of
-- the REVIVE bar and for the guard-4 STOP release, so it is exactly as load-bearing as
-- V_KEYWORD_GUARD.season_win_prior was, and it was wrong in exactly the same way (see header).
-- Selection discipline copied from V_KEYWORD_CONTEXT_GATE's `prior` CTE:
--   same family as TODAY's occurrence · occurrence CLOSED before this one started · §4 maturity
--   guard (first click >= 30d before that occurrence began) · no memory during an OFF run,
-- plus this view's own age bound (k.win_max_age_days): the prior must have ended within one
-- cycle. Deterministic: plain COUNT/MAX; STRING_AGG fully tie-broken (occurrence_end, label).
seas AS (
  SELECT LOWER(TRIM(v.keyword_text)) AS kw,
         COUNT(*) AS n_win,
         STRING_AGG(v.context_label, '|' ORDER BY v.occurrence_end DESC, v.context_label LIMIT 3) AS win_labels,
         MAX(v.occurrence_end) AS win_prior_end
  FROM `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT` v
  JOIN occ o
    ON REGEXP_REPLACE(v.context_label, r'_\d{4}$', '') = o.family
   AND v.occurrence_end < o.occurrence_start
  CROSS JOIN k xk
  WHERE o.family != 'OFF'                -- OFF runs carry no entry memory (gate precedent, §5.1)
    AND v.verdict = 'WIN'
    AND v.mature_at_start                -- §4 maturity guard
    AND v.occurrence_end >= DATE_SUB(o.occurrence_start, INTERVAL xk.win_max_age_days DAY)
  GROUP BY 1
),
-- UNSCOPED season history — AUDIT/DISPLAY ONLY, never a licence. This is precisely the old
-- (defective) `seas` payload, kept so the Revivals panel can still show "11 wins overall, 1 of
-- them in this season" rather than losing the context entirely. Nothing downstream may branch
-- on these two columns.
seas_any AS (
  SELECT kw, COUNT(*) AS n_win_any,
         STRING_AGG(context_label, '|' ORDER BY occurrence_end DESC, context_label LIMIT 3) AS win_labels_any
  FROM (
    SELECT LOWER(TRIM(keyword_text)) AS kw, context_label, occurrence_end
    FROM `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT`
    WHERE verdict = 'WIN'
  )
  GROUP BY 1
),
calc AS (
  SELECT p.*,
    o.occurrence_key, o.context_label, o.occurrence_start, o.family AS occurrence_family,
    x.win_max_age_days,   -- carried for the reason strings only; not published
    COALESCE(w.s90_clk, 0) AS s90_clk, COALESCE(w.s90_sp, 0) AS s90_sp,
    COALESCE(w.s90_ord, 0) AS s90_ord, COALESCE(w.s90_gp, 0) AS s90_gp,
    ROUND(SAFE_DIVIDE(w.s90_gp, NULLIF(w.s90_sp, 0)), 3) AS s90_gp_roas,
    ROUND(SAFE_DIVIDE(w.s90_sp, NULLIF(w.s90_clk, 0)), 3) AS s90_cpc,
    COALESCE(w.cond_clk, 0) AS cond_clk, COALESCE(w.cond_sp, 0) AS cond_sp,
    COALESCE(w.cond_ord, 0) AS cond_ord, COALESCE(w.cond_gp, 0) AS cond_gp,
    ROUND(SAFE_DIVIDE(w.cond_gp, NULLIF(w.cond_sp, 0)), 3) AS cond_gp_roas,
    COALESCE(w.life_settled_clk, 0) AS life_settled_clk,
    w.last_prepark_click,
    COALESCE(ct.channel, 'SP') AS channel,
    IF(COALESCE(ct.channel, 'SP') = 'SB', 14, x.settle_days) AS settle_days_eff,
    IF(w.last_prepark_click IS NOT NULL,
       DATE_ADD(w.last_prepark_click, INTERVAL IF(COALESCE(ct.channel, 'SP') = 'SB', 14, x.settle_days) DAY),
       NULL) AS settle_due,
    d.settle_cut AS settled_through, d.today AS snapshot_date,
    COALESCE(w.post_revive_settled_clk, 0) AS post_revive_settled_clk,
    COALESCE(w.pre_revive_settled_clk, 0) AS pre_revive_settled_clk,
    COALESCE(w.pre_revive_settled_ord, 0) AS pre_revive_settled_ord,
    COALESCE(s.n_win, 0) AS n_win, s.win_labels, s.win_prior_end,
    COALESCE(sa.n_win_any, 0) AS n_win_any, sa.win_labels_any,
    tn.fact_tgt AS fact_targeting,
    CASE
      WHEN COALESCE(w.has_id_evidence, FALSE) AND COALESCE(w.has_text_evidence, FALSE) THEN 'KEYWORD_ID+TEXT_FALLBACK'
      WHEN COALESCE(w.has_id_evidence, FALSE) THEN 'KEYWORD_ID'
      WHEN COALESCE(w.has_text_evidence, FALSE) THEN 'TEXT_FALLBACK'
      ELSE 'NONE'
    END AS evidence_join,
    g.gate_action, g.entry_state,
    g.cur_clicks AS gate_cur_clicks, g.cur_gp_roas AS gate_cur_gp_roas,
    -- calibrated bar on the SETTLED 90d record
    (COALESCE(w.s90_clk, 0) >= x.min_settled_clk
     AND (COALESCE(SAFE_DIVIDE(w.s90_gp, NULLIF(w.s90_sp, 0)), 0) >= x.bar_roas
          OR (COALESCE(SAFE_DIVIDE(w.s90_gp, NULLIF(w.s90_sp, 0)), 0) >= x.bar_roas_season
              AND COALESCE(s.n_win, 0) >= 1))) AS passes_bar,
    -- v27.53: TRUE exactly when the row clears the bar ONLY because of the season relaxation —
    -- i.e. its own settled record loses money and a same-season mature prior WIN carried it.
    -- Ori's read-this-first flag on the panel: these are the revivals that are a judgement call.
    (COALESCE(w.s90_clk, 0) >= x.min_settled_clk
     AND COALESCE(SAFE_DIVIDE(w.s90_gp, NULLIF(w.s90_sp, 0)), 0) < x.bar_roas
     AND COALESCE(SAFE_DIVIDE(w.s90_gp, NULLIF(w.s90_sp, 0)), 0) >= x.bar_roas_season
     AND COALESCE(s.n_win, 0) >= 1) AS season_relax_applied,
    -- gate STOP release only via the CURRENT-occurrence settled record (guard 4)
    (COALESCE(g.cur_clicks, 0) >= x.min_settled_clk
     AND (COALESCE(g.cur_gp_roas, 0) >= x.bar_roas
          OR (COALESCE(g.cur_gp_roas, 0) >= x.bar_roas_season AND COALESCE(s.n_win, 0) >= 1))) AS stop_released,
    -- one revive per occurrence (guard 3): re-parked AFTER a revive inside the current occurrence
    (p.park_date IS NOT NULL AND p.revive_date IS NOT NULL
     AND p.park_date > p.revive_date AND p.revive_date >= o.occurrence_start) AS re_parked_this_occ,
    (p.is_parked AND p.last_source = 'MANUAL'
     AND p.last_change_date >= DATE_SUB(d.today, INTERVAL 14 DAY)) AS manual_parked_recent,
    -- post-revival settle veto (guard 1): a LIVE row revived within 45d off a proven settled
    -- record (>= 10 settled clicks AND >= 1 settled order BEFORE the revive — a fresh $1 probe
    -- activation has neither and keeps its 20-click discipline), fewer than 10 NEW settled clicks
    (NOT p.is_parked AND p.revive_date IS NOT NULL
     AND p.revive_date >= DATE_SUB(d.today, INTERVAL 45 DAY)
     AND COALESCE(w.pre_revive_settled_clk, 0) >= x.min_settled_clk
     AND COALESCE(w.pre_revive_settled_ord, 0) >= 1
     AND COALESCE(w.post_revive_settled_clk, 0) < x.min_settled_clk) AS revive_settling,
    (NOT p.is_parked AND p.last_source = 'MANUAL'
     AND p.last_change_date >= DATE_SUB(d.today, INTERVAL 14 DAY)) AS manual_live_hold,
    -- calibrated revive bid: clamp(min(pre-park bid, 1.10 x settled CPC), $0.31, $1.50);
    -- unknown-era (no logged park): clamp(1.10 x settled CPC, $0.31, $1.50)
    IF(COALESCE(w.s90_clk, 0) > 0 OR p.pre_park_bid IS NOT NULL,
       ROUND(LEAST(GREATEST(
         COALESCE(LEAST(p.pre_park_bid, 1.10 * SAFE_DIVIDE(w.s90_sp, NULLIF(w.s90_clk, 0))),
                  p.pre_park_bid, 1.10 * SAFE_DIVIDE(w.s90_sp, NULLIF(w.s90_clk, 0))),
         x.revive_floor), x.revive_cap), 2), NULL) AS revive_bid
  FROM pop p
  CROSS JOIN k x CROSS JOIN d CROSS JOIN occ o
  LEFT JOIN ctype ct ON ct.cid = p.campaign_id
  LEFT JOIN w ON w.campaign_id = p.campaign_id AND w.keyword_id = p.keyword_id
  LEFT JOIN tgt_name tn ON tn.cid = p.campaign_id AND tn.kid = p.keyword_id
  LEFT JOIN seas s ON s.kw = LOWER(TRIM(COALESCE(tn.fact_tgt, p.keyword_text)))
  LEFT JOIN seas_any sa ON sa.kw = LOWER(TRIM(COALESCE(tn.fact_tgt, p.keyword_text)))
  LEFT JOIN `onyga-482313.OI.V_KEYWORD_CONTEXT_GATE` g
    ON g.keyword_text = LOWER(TRIM(COALESCE(tn.fact_tgt, p.keyword_text)))
),
-- ── v27.68 SIBLING EVIDENCE (Task 2.4; Ori 2026-08-15: "you can check the general performance of
-- the product keyword in other campaign and decide if it worth to lift it again") ────────────────
-- A parked keyword generates zero data. Its own settled record can only re-read OLD clicks — it
-- cannot see that the term now converts. But the SAME TERM in the family's OTHER campaigns is our
-- own conversions on our own listing: the one external signal that moves without our clicks.
-- The pool reads ONLY snapshot tables (guard + panel ownership) — planner-safe, ≤1 day stale,
-- harmless for 90d records. Same shape as V_TERM_FAMILY_EVIDENCE (the standalone surface); inlined
-- here so this view adds no new heavy dependency.
sib_pool AS (
  SELECT sg.parent_name AS fam, LOWER(TRIM(sg.keyword_text)) AS txt,
         CAST(sg.campaign_id AS STRING) AS cid,
         spo.campaign_name AS sib_campaign, UPPER(COALESCE(sg.match_type, '')) AS sib_match,
         sg.settled_clk90 AS sib_clk, sg.settled_roas90 AS sib_roas, sg.settled_cpc90 AS sib_cpc,
         COALESCE(spo.is_oob_owned, FALSE) AS sib_capped
  FROM `onyga-482313.OI.FACT_KEYWORD_GUARD` sg
  LEFT JOIN `onyga-482313.OI.FACT_PANEL_OWNERSHIP` spo
    ON CAST(spo.campaign_id AS STRING) = CAST(sg.campaign_id AS STRING)
  WHERE sg.parent_name IS NOT NULL AND sg.keyword_text IS NOT NULL
    -- only siblings that CLEAR THE REVIVAL BAR (the one bar, reused — k.bar_roas/min_settled_clk)
    AND sg.settled_roas90 >= 1.0 AND sg.settled_clk90 >= 10
),
-- best qualifying sibling per parked key: most settled clicks, deterministic tie-break.
-- Built against pop (light), NEVER against calc (re-inlining the heavy chain twice is the
-- planner-blowup class).
sib_best AS (
  SELECT CAST(p2.campaign_id AS STRING) AS cid, CAST(p2.keyword_id AS STRING) AS kid,
         s.sib_campaign, s.sib_match, s.sib_clk, s.sib_roas, s.sib_cpc, s.sib_capped
  FROM pop p2
  JOIN `onyga-482313.OI.FACT_PANEL_OWNERSHIP` f2
    ON CAST(f2.campaign_id AS STRING) = CAST(p2.campaign_id AS STRING)
  JOIN sib_pool s
    ON s.fam = f2.family AND s.txt = LOWER(TRIM(p2.keyword_text))
   AND s.cid != CAST(p2.campaign_id AS STRING)
  WHERE p2.is_parked
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p2.campaign_id, p2.keyword_id
                             ORDER BY s.sib_clk DESC, s.cid) = 1
)
SELECT
  c.campaign_id, c.keyword_id, c.ad_group_id, c.keyword_text, c.match_type,
  c.fact_targeting, c.evidence_join,
  c.channel, c.settle_days_eff,
  (LOWER(c.keyword_text) LIKE 'asin%' OR LOWER(c.keyword_text) LIKE 'category%') AS is_pt,
  IF(c.is_parked, 'PARKED', 'LIVE') AS row_kind,
  c.current_bid,
  c.park_date, c.pre_park_bid, c.park_bid, c.park_source,
  IF(c.park_date IS NOT NULL, 'LOGGED', 'UNKNOWN') AS park_era,
  c.n_park_events, c.last_change_date, c.last_source,
  c.revive_date, c.revive_bid_applied, c.revive_source,
  c.last_prepark_click, c.settle_due, c.settled_through, c.snapshot_date,
  c.s90_clk, c.s90_sp, c.s90_ord, c.s90_gp, c.s90_gp_roas, c.s90_cpc,
  c.cond_clk, c.cond_sp, c.cond_ord, c.cond_gp, c.cond_gp_roas,
  c.life_settled_clk,
  c.post_revive_settled_clk, c.pre_revive_settled_clk, c.pre_revive_settled_ord,
  c.n_win, c.win_labels, c.win_prior_end, c.n_win_any, c.win_labels_any,
  c.gate_action, c.entry_state, c.gate_cur_clicks, c.gate_cur_gp_roas,
  c.occurrence_key, c.context_label, c.occurrence_start, c.occurrence_family,
  c.passes_bar, c.season_relax_applied, c.stop_released, c.re_parked_this_occ, c.manual_parked_recent,
  -- v27.68: a SIBLING_REVIVE prices off the SIBLING's settled CPC (its own record failed, so its
  -- own CPC is the wrong anchor): min(pre-park bid, 1.1 x sibling CPC), clamped to k's
  -- [0.31, 1.50] (literals mirror k.revive_floor / k.revive_cap — k is out of scope here).
  -- Full predicate chain replicated because this CASE stands alone (same-predicate no-drift rule).
  CASE WHEN c.is_parked AND NOT c.re_parked_this_occ
        AND NOT (c.entry_state = 'STOP' AND NOT c.stop_released)
        AND NOT c.passes_bar
        AND c.s90_clk >= 10 AND bs.sib_clk IS NOT NULL
        AND (c.s90_ord > 0 OR c.s90_clk < 15 OR bs.sib_clk >= 20)
        AND ((UPPER(COALESCE(c.match_type, '')) = 'EXACT' AND bs.sib_match != 'EXACT')
             OR bs.sib_capped)
       THEN ROUND(LEAST(GREATEST(
              LEAST(COALESCE(c.pre_park_bid, 1.50), ROUND(1.1 * bs.sib_cpc, 2)),
              0.31), 1.50), 2)
       ELSE c.revive_bid END AS revive_bid,
  CASE
    WHEN NOT c.is_parked THEN NULL
    WHEN c.re_parked_this_occ THEN 'CONFIRM_PARK'
    WHEN c.entry_state = 'STOP' AND NOT c.stop_released THEN 'CONFIRM_PARK'
    WHEN c.passes_bar THEN 'REVIVE'
    -- v27.68 sibling arms (Task 2.4): evaluated ONLY where the own-record verdict would say
    -- CONFIRM_PARK — the own-record arms above stay untouched and rank first. A tested loser
    -- (>= 15 settled clicks, 0 orders — the DEAD class) needs the DOUBLED sibling bar (>= 20
    -- settled sibling clicks): the one-way door gets a keyhole, not a hinge.
    -- SIBLING_REVIVE only when THIS instance would serve the term BETTER or ADDITIONALLY:
    -- parked EXACT vs a non-EXACT sibling (exact serves what broad finds, cheaper), or the
    -- sibling is capped (proves the term but cannot fund it). Otherwise the family already owns
    -- the term there — REDUNDANT, stay parked, and that is knowledge, not failure: reviving
    -- would double-bid (the intent-grid legacy double-bid class).
    WHEN c.s90_clk >= 10 AND bs.sib_clk IS NOT NULL
     AND (c.s90_ord > 0 OR c.s90_clk < 15 OR bs.sib_clk >= 20)
      THEN IF((UPPER(COALESCE(c.match_type, '')) = 'EXACT' AND bs.sib_match != 'EXACT')
              OR bs.sib_capped,
              'SIBLING_REVIVE', 'REDUNDANT')
    WHEN c.s90_clk >= 10 THEN 'CONFIRM_PARK'
    WHEN c.last_prepark_click IS NOT NULL
     AND c.last_prepark_click > DATE_SUB(c.snapshot_date, INTERVAL c.settle_days_eff DAY) THEN 'PENDING_SETTLE'
    ELSE 'INSUFFICIENT'
  END AS reverdict,
  CASE
    WHEN NOT c.is_parked THEN NULL
    WHEN c.re_parked_this_occ THEN
      CONCAT('re-parked ', CAST(c.park_date AS STRING), ' after the ', CAST(c.revive_date AS STRING),
             ' revive inside ', c.context_label, ' — one revive per occurrence: stays parked until the occurrence turns')
    WHEN c.entry_state = 'STOP' AND NOT c.stop_released THEN
      CONCAT('season gate STOP (', COALESCE(c.gate_action, ''), ') and the current-occurrence settled record (',
             CAST(COALESCE(c.gate_cur_clicks, 0) AS STRING), 'c at ',
             FORMAT('%.2f', COALESCE(c.gate_cur_gp_roas, 0)), 'x) does not clear the bar — gate precedence: never auto-revive',
             IF(c.passes_bar, ' [90d blend passes — flagged for gate re-audit]', ''))
    WHEN c.passes_bar THEN
      CONCAT('settled ', CAST(c.s90_clk AS STRING), 'c at ', FORMAT('%.2f', COALESCE(c.s90_gp_roas, 0)),
             'x GP-ROAS ($', FORMAT('%.2f', c.s90_gp), ' GP on $', FORMAT('%.2f', c.s90_sp), ')',
             -- v27.53: the relaxation must show its licence — WHICH occurrence, and how old it is
             IF(c.season_relax_applied,
                CONCAT(' — under 1.0, relaxed to the 0.80 bar by a mature ', COALESCE(c.win_labels, ''),
                       ' WIN (same season as today, prior occurrence ended ',
                       CAST(c.win_prior_end AS STRING), ')'), ''),
             -- v27.99 (audit C8): the PRICE used to be stated here, and this sentence is
             -- inherited VERBATIM by V_KEYWORD_LIFT and V_OOB_KEYWORD, which may cap the revival
             -- lower against the keyword's lifetime record. The row then closed by naming a bid
             -- it had just rejected. The verdict travels; the price does not. Each consumer names
             -- the price it actually proposes, exactly once — including this view's own snapshot
             -- row, where the price is revive_bid and SP_SNAPSHOT_ENGINE_PROPOSALS appends it.
             ' — the settled record overturns the park',
             IF(c.manual_parked_recent, ' [MANUAL park <14d — sweep-only, engines defer]', ''))
    -- v27.68 sibling reasons — same predicate as the verdict ladder (no-drift rule)
    WHEN c.s90_clk >= 10 AND bs.sib_clk IS NOT NULL
     AND (c.s90_ord > 0 OR c.s90_clk < 15 OR bs.sib_clk >= 20) THEN
      IF((UPPER(COALESCE(c.match_type, '')) = 'EXACT' AND bs.sib_match != 'EXACT') OR bs.sib_capped,
         CONCAT('own record fails (', CAST(c.s90_clk AS STRING), 'c at ',
                FORMAT('%.2f', COALESCE(c.s90_gp_roas, 0)), 'x) but the FAMILY proves the term: ',
                COALESCE(bs.sib_campaign, '?'), ' (', LOWER(bs.sib_match), ') holds ',
                CAST(bs.sib_clk AS STRING), ' settled clicks at ', FORMAT('%.2f', bs.sib_roas),
                'x — and this instance serves it ',
                IF(UPPER(COALESCE(c.match_type, '')) = 'EXACT' AND bs.sib_match != 'EXACT',
                   'BETTER (exact serves what broad finds, cheaper)',
                   'ADDITIONALLY (the proving sibling is budget-capped)'),
                IF(c.s90_clk >= 15 AND c.s90_ord = 0,
                   ' [tested-loser door: opened by the doubled >= 20-click sibling bar]', ''),
                ' — revive priced off the sibling CPC',
                IF(c.manual_parked_recent, ' [MANUAL park <14d — sweep-only, engines defer]', '')),
         CONCAT('family already serves this term: ', COALESCE(bs.sib_campaign, '?'), ' (',
                LOWER(bs.sib_match), ') at ', FORMAT('%.2f', bs.sib_roas), 'x over ',
                CAST(bs.sib_clk AS STRING),
                ' settled clicks, uncapped — reviving here would double-bid against ourselves; stay parked'))
    WHEN c.s90_clk >= 10 THEN
      CONCAT('settled ', CAST(c.s90_clk AS STRING), 'c at ', FORMAT('%.2f', COALESCE(c.s90_gp_roas, 0)),
             'x GP-ROAS — the park was correct on settled evidence',
             -- v27.53: a row in the 0.80-1.00 band is where the season relaxation WOULD have fired.
             -- Say why it did not, naming the season history that does NOT count, so the panel
             -- never leaves Ori guessing why a keyword with wins on its record stays parked.
             IF(COALESCE(c.s90_gp_roas, 0) >= 0.8 AND COALESCE(c.s90_gp_roas, 0) < 1.0,
                CONCAT('; no QUALIFYING ', COALESCE(c.occurrence_family, ''),
                       '-season prior WIN (same season, closed occurrence, mature, within ',
                       CAST(c.win_max_age_days AS STRING), 'd), so the 0.80 relaxation does not apply — ',
                       CAST(c.n_win_any AS STRING), ' WIN',
                       IF(c.n_win_any = 1, '', 's'), ' on record',
                       IF(c.n_win_any > 0, CONCAT(': ', COALESCE(c.win_labels_any, '')), ''),
                       ', none of them count here'), ''))
    WHEN c.last_prepark_click IS NOT NULL
     AND c.last_prepark_click > DATE_SUB(c.snapshot_date, INTERVAL c.settle_days_eff DAY) THEN
      CONCAT('condemning clicks not settled yet (last pre-park click ', CAST(c.last_prepark_click AS STRING),
             ', settles ', CAST(c.settle_due AS STRING), ' — D+', CAST(c.settle_days_eff AS STRING), ' ', c.channel,
             ') — re-judged at settle')
    ELSE CONCAT('only ', CAST(c.s90_clk AS STRING), ' settled clicks (< 10) — not enough evidence either way; normal queue')
  END AS reverdict_reason,
  c.revive_settling,
  (c.revive_settling OR c.manual_live_hold) AS engine_immune,
  CASE
    WHEN c.revive_settling AND c.manual_live_hold THEN
      CONCAT('revived ', CAST(c.revive_date AS STRING), ' — settling: ', CAST(c.post_revive_settled_clk AS STRING),
             ' of 10 new settled clicks; manual change ', CAST(c.last_change_date AS STRING), ' — 14d hold')
    WHEN c.revive_settling THEN
      CONCAT('revived ', CAST(c.revive_date AS STRING), ' off a settled record (',
             CAST(c.pre_revive_settled_clk AS STRING), 'c) — no condemnation before settle: ',
             CAST(c.post_revive_settled_clk AS STRING), ' of 10 new settled clicks accrued')
    WHEN c.manual_live_hold THEN
      CONCAT('manual change ', CAST(c.last_change_date AS STRING), " — Ori's hand outranks the engines for 14 days")
  END AS immune_reason
FROM calc c
-- v27.68: the best qualifying sibling, at most one row per key (QUALIFY rn=1 in sib_best)
LEFT JOIN sib_best bs
  ON bs.cid = CAST(c.campaign_id AS STRING) AND bs.kid = CAST(c.keyword_id AS STRING);
