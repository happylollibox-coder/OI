-- =============================================
-- V_KEYWORD_GUARD — per-instance guard signals for BOTH engines (v27.48 part 2, 2026-08-09).
-- Spec: architecture/SEASON_CONTEXT_LEDGER.md §7 (settle doctrine) + §7.6-7.9 (part-2 guards).
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
-- v27.53 (2026-08-12, Ori approved "do all engine work") — ITEM 2 the settle veto becomes a real
-- deferral: SP settle_days 7 -> 3 (SB stays 14 — measured understatement SP -3..-6%, SB -17.5%),
-- the SP veto frame moves [wm-96, wm-7] -> [wm-92, wm-3] so a RECENT loss can corroborate at all,
-- and NEW settle_deferral_expired bounds any single deferral to 2 x settle_days of clicking
-- (6d SP / 28d SB) — settle_ok is unsatisfiable for a keyword that clicks daily (193 of 344
-- unsettled rows clicked on the anchor date itself), so the "deferral" was permanent.
-- ITEM 7 the $1.00 wake step-down: wake_open / wake_due / wake_step_bid + the wake-window evidence.
-- ITEM 8a pace_kw was an instance numerator over a scope denominator (both scope now).
-- ITEM 8b the band-ceiling join spoke the wrong match vocabulary (234 of 606 rows had no ceiling).
-- ITEM 8d NEW manual_budget_hold — the hold only ever covered bid changes, never Ori's budgets.
-- Spec: architecture/SEASON_CONTEXT_LEDGER.md §7.16.
--
-- v27.52 (2026-08-12, Ori approved) — FIX 1, the season amnesty was unbounded. `season_win_prior`
-- matched ANY verdict='WIN' ever recorded for the lowercase keyword TEXT, account-wide, back to
-- 2024-09. It is the settle veto's escape hatch, so it made a keyword permanently un-condemnable
-- on unsettled clicks no matter how much settled money it was losing. Two bounds, both here:
--   (a) `settle_amnesty` (NEW, the flag the engines now read) = season_win_prior AND NOT
--       catastrophic — a < 0.6x record on >= 10 SETTLED clicks overrides the amnesty entirely;
--   (b) `season_win_prior` itself is now OCCURRENCE-SCOPED (see the `seas` CTE): the WIN must come
--       from a closed PRIOR occurrence of the SAME context family we are in today, and must be
--       mature — the same memory rule the LOSS-side ENTRY_BLOCK gate has always used.
-- Measured impact on the 2026-08-12 standing population (606 enabled targets): WIN priors
-- 332 -> 126; structurally un-condemnable settled losers 123 -> 22.
--
-- WHY (iteration-6 root causes, Ori approved 2026-08-09):
--   Cause 1 — engines condemn keywords on clicks whose sales have not arrived (SP sales accrue
--             to D+7, SB to D+14). Signals here: settle_ok / settle_due / channel-aware settled
--             90d record (corroborated_loser / settled_winner / catastrophic) + season WIN prior
--             (v27.52: consumed via settle_amnesty, never season_win_prior directly).
--   Cause 2 — probe system treats "no recent data" as "never tested": $1.00 entries on keywords
--             with hundreds of lifetime clicks. Signals: life_clk / life_roas / life_conv_cpc
--             (scope grain — see IDENTITY) + record_loser; ly_conv_cpc for the season-gate
--             LY-LOSS entry cap (0.8x).
--   Cause 3 — no manual-override hold: OOB parked over Ori's Aug-4 manual raise within days.
--             Signals: last_bid_source / last_bid_change_date / manual_recent7 / manual_hold
--             (7-day hold, catastrophic escape: settled 90d < 0.6 on >= 10 settled clicks —
--             a keyword losing money NOW is not protected by the hold).
--             COVERAGE HOLE (documented, not pretended fixed): only changes that flow through
--             OI's upload flow land in FACT_PPC_CHANGE_LOG (source COACH = engine batch,
--             MANUAL = Ori's hand via the Do page, REUPLOAD = the re-upload flow — engine-class).
--             Changes made directly in the Amazon console are UNLOGGED and cannot be held.
--   Cause 4 — no LY-pacing signal: cheap proven winners starve the data that would justify
--             raising them ('gift for girls': 90d 2.16x at $0.20 pacing 8% of LY volume — engine
--             silent). Signals: pace_flag / pace_watch / pace_target_bid per the 2026-08-09
--             calibration (threshold 0.25, formula B economics caps, ~10 rows, $56-74/wk).
--
-- IDENTITY (the calibration's load-bearing finding): keyword_ids do NOT survive campaign
-- recreations ('gift for girls': 8 keyword_ids across 15 campaigns; SB rows before 2025-10-28
-- carry keyword_id=-1). Lifetime + LY metrics are therefore computed at SCOPE grain:
--   KEYWORD text -> account-wide LOWER(targeting) ('*|text');
--   AUTO clause  -> (dominant-family, clause) ('family|text') — account-wide pooling of auto
--                   clause names mixes products and produced garbage flags in calibration v1.
-- Instance (recent) windows use (campaign_id, keyword_id) — solid at recent horizons.
-- Family here = dominant-by-lifetime-ad-spend (camp_parent_full), NOT V_DIM_CAMPAIGN_FAMILY:
-- the LY/lifetime pools must cover DELETED LY campaigns, and the 2026-08-09 pace calibration
-- (approved) was computed on exactly this identity. The band CEILING join shares it.
--
-- FRAMES: two settled-90d frames on purpose (v27.53 rebased the SP veto frame) —
--   channel-aware  [wm - settle_days - 89, wm - settle_days] -> the SETTLE VETO fields
--                  (corroborated_loser etc.). SP settle_days = 3, so [wm-92, wm-3]; SB = 14, so
--                  [wm-103, wm-14] — an SB day-8..14 sales tail would understate GP and fake a
--                  corroboration, so SB still waits the full 14. Before v27.53 the SP frame ended
--                  at wm-7 and a loss that STARTED inside the last week could never corroborate;
--   calibration    [wm-96, wm-7] for every row -> the PACE fields (pace_roas90s etc.): the
--                  2026-08-09 pace grid was approved on this exact frame and is NOT rebased.
-- wm = LEAST(MAX(FACT date), FN_ADS_ANCHOR_CAP()) — the engines' anchor.
--
-- SETTLE TEST: settle_ok = no clicks in the last settle_days (last_click <= wm - 3 SP / -14 SB)
-- => every condemning click has settled. last_click read over a 60d tail (older clicks are
-- settled by construction). settle_due = last_click + settle_days.
-- v27.53: settle_ok alone was NOT a deferral — a keyword that clicks every day can never satisfy
-- it, so settle_due was a promise that never came due. settle_deferral_expired is the hard bound:
-- first_click_60d <= wm - 2 x settle_days means a full settle_days of this keyword's clicks is
-- already settled and readable, the wait has been served, and the row must be judged on what it
-- has. Ceiling on any single deferral: 6 days SP, 28 days SB.
--
-- DETERMINISM: plain SUMs over fixed windows; every ROW_NUMBER/ARRAY_AGG fully tie-broken; no
-- ANY_VALUE pairs ever divided (v27.46 lesson).
-- v27.53: the LIFETIME and LY conv-CPC / ROAS ratios are summed in NUMERIC, then cast back to
-- FLOAT64 (schema unchanged). FLOAT64 addition is not associative and BigQuery parallelises the
-- shuffle differently between runs, so a SUM over the FULL FACT history can move in its last bits.
-- Caught by the v27.53 determinism check: `gift for tween girls 11-14` returned life_conv_cpc
-- 0.383 on one pull and 0.382 on the next — one row, one column, a rounding boundary. It is not a
-- logic bug and it predates v27.53, but this column PRICES BIDS (the OOB record-priced entry cap
-- and the item-7 wake step-down both read it), so a coin-flip in it is not acceptable. NUMERIC is
-- fixed-point: its summation is exact and order-independent. The short instance windows are left
-- as FLOAT64 — they aggregate at most 104 days per keyword and have never flipped.
--
-- CONSUMERS: SP_SNAPSHOT_KEYWORD_GUARD -> FACT_KEYWORD_GUARD (engines read the SNAPSHOT ONLY —
-- planner-ceiling doctrine: this view's FACT subtrees must never enter an engine plan).
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_GUARD` AS
WITH
k AS (
  SELECT 10 AS min_settled_clk, 30 AS life_clk_bar, 100 AS pace_life_clk, 20 AS pace_ly_clk,
         0.25 AS pace_threshold, 0.40 AS pace_watch_threshold, 1.2 AS pace_roas_bar,
         7 AS manual_hold_days, 7 AS bid_stable_days, 2.00 AS bid_hard_cap,
         -- v27.53 ITEM 2 — CHANNEL-SPLIT SETTLE DAYS. Measured fresh-data understatement on the
         -- JUDGED window: SP -3% to -6%, SB -17.5%. On SP the 7-day wait bought almost nothing and
         -- was blocking correct cuts (measured 2026-08-12: 14 rows blocked, $344.10 per 7 days of
         -- run-rate; 4 of 6 SP holds WRONG on the settled 90-day record — $120.58 of $155.76 =
         -- 77% of blocked SP spend, GP shortfall $71.65/7d. Worst: 'gifts for 12 year old girl'
         -- 47c at 0.86x, settled 66c at 0.700x — it can never reach 1.0, so waiting is pointless).
         -- SB keeps 14: a -17.5% understatement really can flip a verdict.
         3 AS sp_settle_days, 14 AS sb_settle_days
),
d AS (SELECT CURRENT_DATE('America/Los_Angeles') AS today),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
season AS (
  SELECT COUNTIF(CURRENT_DATE('America/New_York') BETWEEN boost_start AND cooldown_end) > 0 AS in_peak
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` WHERE category IN ('gift_season', 'prime_event')
),
-- dominant family per campaign over FULL history (covers deleted LY campaigns — calibration identity)
camp_parent_full AS (
  SELECT campaign_id, parent_name FROM (
    SELECT CAST(a.campaign_id AS STRING) AS campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY CAST(a.campaign_id AS STRING)
                         ORDER BY SUM(a.Ads_cost) DESC, p.parent_name) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    GROUP BY 1, 2
  ) WHERE rn = 1
),
-- population: every current ENABLED target (keywords, auto clauses, product targets — SP and SB
-- config both live in DIM_KEYWORD), enabled campaigns only; one row per (campaign, keyword)
kw AS (
  SELECT campaign_id, keyword_id, keyword_text, match_type, channel, current_bid,
         LOWER(keyword_text) IN ('close-match','loose-match','substitutes','complements') AS is_auto,
         LOWER(keyword_text) LIKE 'asin%' OR LOWER(keyword_text) LIKE 'category%' AS is_pt
  FROM (
    SELECT CAST(k.campaign_id AS STRING) AS campaign_id, CAST(k.keyword_id AS STRING) AS keyword_id,
           k.keyword_text, k.match_type,
           IF(UPPER(COALESCE(c.campaign_type, 'SP')) = 'SB', 'SB', 'SP') AS channel,
           COALESCE(k.bid, ag.default_bid) AS current_bid,
           ROW_NUMBER() OVER (PARTITION BY CAST(k.campaign_id AS STRING), CAST(k.keyword_id AS STRING)
                              ORDER BY k.effective_from DESC, k.bid DESC NULLS LAST) AS rn
    FROM `onyga-482313.OI.DIM_KEYWORD` k
    JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c
      ON c.campaign_id = CAST(k.campaign_id AS STRING) AND c.campaign_state = 'ENABLED'
    LEFT JOIN (SELECT ad_group_id, ANY_VALUE(default_bid) AS default_bid
               FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current GROUP BY 1) ag
      ON ag.ad_group_id = CAST(k.ad_group_id AS STRING)
    WHERE k.is_current AND UPPER(k.state) = 'ENABLED'
  ) WHERE rn = 1
),
kws AS (
  SELECT kw.*, cp.parent_name,
         IF(kw.is_auto, CONCAT(COALESCE(cp.parent_name, '?'), '|', LOWER(kw.keyword_text)),
                        CONCAT('*|', LOWER(kw.keyword_text))) AS scope,
         -- v27.53 ITEM 8b — BAND-CEILING MATCH VOCABULARY. DIM_KEYWORD speaks Amazon's bulksheet
         -- vocabulary (AUTOMATIC / ASIN / 'ASIN EXPANDED' / CATEGORY / BROAD / EXACT / PHRASE);
         -- DE_PRODUCT_STRATEGY_PROFILE speaks the strategy vocabulary (AUTO / PRODUCT / CATEGORY /
         -- OTHER / BROAD / EXACT / PHRASE). The join was raw UPPER(match_type) = UPPER(match_type),
         -- so AUTOMATIC and ASIN never matched a cell: 234 of 606 rows (38.6%) carried NO band
         -- ceiling, which silently removed the pace target's market-price cap on every auto clause
         -- and product target. Translate once, here, and fall back to the profile's own OTHER cell.
         CASE UPPER(COALESCE(kw.match_type, ''))
           WHEN 'AUTOMATIC'     THEN 'AUTO'
           WHEN 'ASIN'          THEN 'PRODUCT'
           WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
           ELSE UPPER(COALESCE(kw.match_type, ''))
         END AS band_match
  FROM kw
  LEFT JOIN camp_parent_full cp ON cp.campaign_id = kw.campaign_id
),
-- one FACT stream. GP = FACT_AMAZON_ADS.GROSS_PROFIT, the stored column — see THE GP RULE above.
f AS (
  SELECT a.date, CAST(a.campaign_id AS STRING) AS cid, CAST(a.keyword_id AS STRING) AS kwid,
         IF(LOWER(a.targeting) IN ('close-match','loose-match','substitutes','complements'),
            CONCAT(COALESCE(cp.parent_name, '?'), '|', LOWER(a.targeting)),
            CONCAT('*|', LOWER(a.targeting))) AS scope,
         a.Ads_clicks AS clk, a.Ads_cost AS sp, a.Ads_orders AS ord,
         a.GROSS_PROFIT AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  LEFT JOIN camp_parent_full cp ON cp.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.targeting IS NOT NULL
),
-- instance recent windows: last click (60d tail — older is settled by construction), the two
-- settled-90 frames (D+7 and D+14 cuts), and the current-28d pace numerator
inst AS (
  SELECT cid, kwid,
    MAX(IF(clk > 0 AND date > DATE_SUB(wm.d, INTERVAL 60 DAY), date, NULL)) AS last_click_date,
    -- v27.53 ITEM 2a — the START of the current run of activity, over the same 60d tail. The
    -- deferral bound needs to know how LONG a keyword has been clicking, not just when it last did.
    MIN(IF(clk > 0 AND date > DATE_SUB(wm.d, INTERVAL 60 DAY), date, NULL)) AS first_click_60d,
    -- v27.53 ITEM 2b — SP VETO FRAME, [wm-92, wm-3]. Was [wm-96, wm-7], which ends SEVEN days back:
    -- a keyword whose loss STARTED inside the last 7 days had settled_clk90 = 0, so it could never
    -- corroborate, and (with settle_ok also unreachable — hole 2a) it was vetoed indefinitely. The
    -- frame now ends exactly at the SP settle horizon, so evidence becomes readable 3 days after it
    -- is earned. Same 90-day depth. SB keeps [wm-103, wm-14] (its own horizon) below.
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 92 DAY) AND DATE_SUB(wm.d, INTERVAL 3 DAY), clk, 0)) AS s3_clk,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 92 DAY) AND DATE_SUB(wm.d, INTERVAL 3 DAY), sp, 0)) AS s3_sp,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 92 DAY) AND DATE_SUB(wm.d, INTERVAL 3 DAY), ord, 0)) AS s3_ord,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 92 DAY) AND DATE_SUB(wm.d, INTERVAL 3 DAY), gp, 0)) AS s3_gp,
    -- calibration frame [wm-96, wm-7] — the pace grid's exact settled window
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 96 DAY) AND DATE_SUB(wm.d, INTERVAL 7 DAY), clk, 0)) AS s7_clk,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 96 DAY) AND DATE_SUB(wm.d, INTERVAL 7 DAY), sp, 0)) AS s7_sp,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 96 DAY) AND DATE_SUB(wm.d, INTERVAL 7 DAY), ord, 0)) AS s7_ord,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 96 DAY) AND DATE_SUB(wm.d, INTERVAL 7 DAY), gp, 0)) AS s7_gp,
    -- SB frame [wm-103, wm-14] — the day-8..14 SB sales tail must not fake a corroboration
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 103 DAY) AND DATE_SUB(wm.d, INTERVAL 14 DAY), clk, 0)) AS s14_clk,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 103 DAY) AND DATE_SUB(wm.d, INTERVAL 14 DAY), sp, 0)) AS s14_sp,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 103 DAY) AND DATE_SUB(wm.d, INTERVAL 14 DAY), ord, 0)) AS s14_ord,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 103 DAY) AND DATE_SUB(wm.d, INTERVAL 14 DAY), gp, 0)) AS s14_gp,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 27 DAY) AND wm.d, clk, 0)) AS clk28_kw
  FROM f, wm
  WHERE date > DATE_SUB(wm.d, INTERVAL 104 DAY)
  GROUP BY 1, 2
),
-- scope lifetime record (Cause 2) — conv CPC = order-day CPC, fallback whole-scope CPC
life AS (
  SELECT scope, SUM(clk) AS life_clk, SUM(ord) AS life_ord,
         CAST(ROUND(SAFE_DIVIDE(SUM(CAST(gp AS NUMERIC)), NULLIF(SUM(CAST(sp AS NUMERIC)), 0)), 3) AS FLOAT64) AS life_roas,
         CAST(ROUND(COALESCE(
           SAFE_DIVIDE(SUM(IF(ord > 0, CAST(sp AS NUMERIC), 0)), NULLIF(SUM(IF(ord > 0, CAST(clk AS NUMERIC), 0)), 0)),
           SAFE_DIVIDE(SUM(CAST(sp AS NUMERIC)), NULLIF(SUM(CAST(clk AS NUMERIC)), 0))), 3) AS FLOAT64) AS life_conv_cpc
  FROM f GROUP BY 1
),
-- scope LY same-28d window (weekday-aligned, date-364d) + current-28d scope clicks (pace)
lys AS (
  SELECT scope,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 27 + 364 DAY) AND DATE_SUB(wm.d, INTERVAL 364 DAY), clk, 0)) AS ly_clk28,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 27 + 364 DAY) AND DATE_SUB(wm.d, INTERVAL 364 DAY), ord, 0)) AS ly_ord28,
    CAST(ROUND(COALESCE(
      SAFE_DIVIDE(SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 27 + 364 DAY) AND DATE_SUB(wm.d, INTERVAL 364 DAY) AND ord > 0, CAST(sp AS NUMERIC), 0)),
                  NULLIF(SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 27 + 364 DAY) AND DATE_SUB(wm.d, INTERVAL 364 DAY) AND ord > 0, CAST(clk AS NUMERIC), 0)), 0)),
      SAFE_DIVIDE(SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 27 + 364 DAY) AND DATE_SUB(wm.d, INTERVAL 364 DAY), CAST(sp AS NUMERIC), 0)),
                  NULLIF(SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 27 + 364 DAY) AND DATE_SUB(wm.d, INTERVAL 364 DAY), CAST(clk AS NUMERIC), 0)), 0))), 3) AS FLOAT64) AS ly_conv_cpc,
    SUM(IF(date BETWEEN DATE_SUB(wm.d, INTERVAL 27 DAY) AND wm.d, clk, 0)) AS clk28_scope
  FROM f, wm GROUP BY 1
),
-- band CEILING (pace cap): coarse ALL/ALL cpc_max per (parent, match), season-resolved
band AS (
  SELECT parent_name, UPPER(match_type) AS match_type,
         MAX(IF(season = 'OFF', cpc_max, NULL)) AS ceil_off,
         MAX(IF(season = 'PEAK', cpc_max, NULL)) AS ceil_peak
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`
  WHERE enabled AND COALESCE(campaign_type, 'ALL') = 'ALL' AND COALESCE(ad_format, 'ALL') = 'ALL'
  GROUP BY 1, 2
),
cap AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         LOGICAL_OR(is_oob_owned) AS is_oob_owned, MAX(days_capped_7d) AS days_capped_7d
  FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` GROUP BY 1
),
-- season memory by text (Cause 1: a WIN prior is never condemned on unsettled clicks)
-- v27.52 FIX 1b — OCCURRENCE-SCOPED. Was: COUNTIF(verdict = 'WIN') over the WHOLE table — ANY WIN
-- ever recorded for the text, any season, any year, back to 2024-09 (452 WIN texts, 332 of 606
-- enabled targets carrying one). That is a permanent account-wide amnesty: it disarmed the settle
-- veto's escape hatch with no bound on how much settled counter-evidence it overrode, and it
-- contradicts the ledger's founding doctrine ("a verdict belongs to (keyword x season-context
-- occurrence), never to the keyword alone — off-season history must never veto peak funding, and
-- vice versa", SEASON_CONTEXT_LEDGER.md §4). It also ignored the §4 MATURITY GUARD, which §7.6
-- already specified in words ("any MATURE-FRAME WIN verdict for the text") but the code never
-- enforced. This CTE now mirrors V_KEYWORD_CONTEXT_GATE's `prior` CTE selection discipline
-- verbatim — same family match, same closed-prior-occurrence test, same maturity guard, same
-- OFF exclusion — so the WIN amnesty and the LOSS entry block read the SAME memory.
curctx AS (
  SELECT REGEXP_REPLACE(context_label, r'_\d{4}$', '') AS family, occurrence_start
  FROM `onyga-482313.OI.V_SEASON_CONTEXT`
  WHERE date = CURRENT_DATE('America/Los_Angeles')
),
seas AS (
  SELECT LOWER(TRIM(v.keyword_text)) AS kw, COUNT(*) AS n_win
  FROM `onyga-482313.OI.FACT_KEYWORD_SEASON_VERDICT` v
  JOIN curctx c
    ON REGEXP_REPLACE(v.context_label, r'_\d{4}$', '') = c.family
   AND v.occurrence_end < c.occurrence_start
  WHERE c.family != 'OFF'          -- OFF runs carry no entry memory (gate precedent, §5.1)
    AND v.verdict = 'WIN'
    AND v.mature_at_start          -- §4 maturity guard
  GROUP BY 1
),
-- last bid-shaped change per keyword_id: age + source (COACH/REUPLOAD = engine, MANUAL = Ori)
chg AS (
  SELECT keyword_id,
         DATE_DIFF((SELECT today FROM d), MAX(DATE(applied_at, 'America/Los_Angeles')), DAY) AS days_since_bid_change,
         ARRAY_AGG(STRUCT(source AS src, DATE(applied_at, 'America/Los_Angeles') AS dt)
                   ORDER BY applied_at DESC, change_id LIMIT 1)[OFFSET(0)] AS lastc
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action IN ('INCREASE_BID', 'REDUCE_BID') AND keyword_id IS NOT NULL AND keyword_id != ''
  GROUP BY 1
),
-- v27.53 ITEM 8d — MANUAL BUDGET HOLD. `chg` above only ever read INCREASE_BID / REDUCE_BID, so
-- Ori's manual BUDGET changes got no hold at all: the engines could re-cut a budget he had set by
-- hand the same day. Budget changes are campaign-grain, so this is a campaign-grain flag that every
-- keyword row of the campaign carries. Measured 2026-08-12: 9 MANUAL BUDGET_CHANGE rows, most
-- recent 2026-08-11 — it binds today. Budget actions of every shape count (BUDGET_CHANGE plus the
-- GUARDIAN_/DEFENSE_ budget families) so an engine cannot dodge the hold by relabelling.
bchg AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         ARRAY_AGG(STRUCT(source AS src, DATE(applied_at, 'America/Los_Angeles') AS dt)
                   ORDER BY applied_at DESC, change_id LIMIT 1)[OFFSET(0)] AS lastb
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action IN ('BUDGET_CHANGE', 'GUARDIAN_BUDGET_DECREASE', 'GUARDIAN_BUDGET_INCREASE',
                   'GUARDIAN_BUDGET_CONTAIN', 'DEFENSE_BUDGET_FLOOR')
    AND campaign_id IS NOT NULL AND CAST(campaign_id AS STRING) != ''
  GROUP BY 1
),
-- v27.53 ITEM 7 — THE $1.00 WAKE STEP-DOWN, the missing half of a deliberate on-ramp.
-- Ori confirmed the intent and the code documents it: "wake it, then price it". The WAKE half
-- works (24 keywords woken to $1.00 since 2026-06-01). The PRICE half does not: only 11 were ever
-- reduced (average 2.7 days later) and 13 are STILL at $1.00 or above, because nothing schedules
-- the repricing — it happens only if some branch of the ladder happens to catch the row. These two
-- CTEs make the second half a scheduled, bounded step instead of an accident.
-- Wake signature = an APPLIED INCREASE_BID landing exactly on the $1.00 entry from a dormant/park
-- level (old_bid <= $0.30). Verified 2026-08-12: this predicate returns exactly the 24 known wakes.
wk AS (
  SELECT keyword_id,
         ARRAY_AGG(STRUCT(DATE(applied_at, 'America/Los_Angeles') AS wake_date, source AS wake_source)
                   ORDER BY applied_at DESC, change_id LIMIT 1)[OFFSET(0)] AS w
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action = 'INCREASE_BID' AND keyword_id IS NOT NULL AND keyword_id != ''
    AND new_bid = 1.00 AND COALESCE(old_bid, 0) <= 0.30
  GROUP BY 1
),
-- evidence EARNED SINCE THE WAKE (the thing the step-down is supposed to read), instance grain
wkev AS (
  SELECT f.cid, f.kwid,
         SUM(f.clk) AS wake_clk, ROUND(SUM(f.sp), 2) AS wake_sp,
         SUM(f.ord) AS wake_ord, ROUND(SUM(f.gp), 2) AS wake_gp
  FROM f JOIN wk ON wk.keyword_id = f.kwid
  WHERE f.date > wk.w.wake_date
  GROUP BY 1, 2
),
calc AS (
  SELECT
    kws.campaign_id, kws.keyword_id, kws.keyword_text, kws.match_type, kws.channel,
    kws.is_auto, kws.is_pt, kws.current_bid, kws.parent_name, kws.scope,
    wm.d AS anchor_date, d.today AS snapshot_date,
    IF(kws.channel = 'SB', x0.sb_settle_days, x0.sp_settle_days) AS settle_days_eff,
    i.last_click_date, i.first_click_60d,
    (i.last_click_date IS NULL
     OR i.last_click_date <= DATE_SUB(wm.d, INTERVAL IF(kws.channel = 'SB', x0.sb_settle_days, x0.sp_settle_days) DAY)) AS settle_ok,
    DATE_ADD(i.last_click_date, INTERVAL IF(kws.channel = 'SB', x0.sb_settle_days, x0.sp_settle_days) DAY) AS settle_due,
    -- v27.53 ITEM 2a — THE DEFERRAL MUST EXPIRE. settle_ok is "no clicks in the last settle_days",
    -- so a keyword that clicks EVERY DAY can never satisfy it: measured 2026-08-12, 193 of 344
    -- unsettled rows clicked on the anchor date itself, and the veto's reason string promised a
    -- re-judge date (settle_due) that arrives only if the keyword goes quiet. That is a PERMANENT
    -- veto wearing a deferral's clothes. Honest bound: once a keyword has been clicking for at
    -- least 2 x settle_days, a full settle_days' worth of its clicks IS settled and readable (the
    -- v27.53 frame above now ends at the settle horizon, so it is genuinely in settled_*90) — the
    -- wait has been served and the row must be judged on what it has, not deferred again. Hard
    -- ceiling on any single deferral: 6 days SP, 28 days SB.
    (i.first_click_60d IS NOT NULL
     AND i.first_click_60d <= DATE_SUB(wm.d, INTERVAL 2 * IF(kws.channel = 'SB', x0.sb_settle_days, x0.sp_settle_days) DAY)) AS settle_deferral_expired,
    -- channel-aware settled 90d (the veto frame) — v27.53: SP now reads the [wm-92, wm-3] frame
    COALESCE(IF(kws.channel = 'SB', i.s14_clk, i.s3_clk), 0) AS settled_clk90,
    ROUND(COALESCE(IF(kws.channel = 'SB', i.s14_sp, i.s3_sp), 0), 2) AS settled_sp90,
    COALESCE(IF(kws.channel = 'SB', i.s14_ord, i.s3_ord), 0) AS settled_ord90,
    ROUND(COALESCE(IF(kws.channel = 'SB', i.s14_gp, i.s3_gp), 0), 2) AS settled_gp90,
    ROUND(SAFE_DIVIDE(IF(kws.channel = 'SB', i.s14_gp, i.s3_gp),
                      NULLIF(IF(kws.channel = 'SB', i.s14_sp, i.s3_sp), 0)), 3) AS settled_roas90,
    ROUND(SAFE_DIVIDE(IF(kws.channel = 'SB', i.s14_sp, i.s3_sp),
                      NULLIF(IF(kws.channel = 'SB', i.s14_clk, i.s3_clk), 0)), 3) AS settled_cpc90,
    -- calibration-frame settled 90d (the pace frame — the approved grid's exact numbers)
    COALESCE(i.s7_clk, 0) AS pace_clk90s,
    ROUND(SAFE_DIVIDE(i.s7_gp, NULLIF(i.s7_sp, 0)), 3) AS pace_roas90s,
    ROUND(SAFE_DIVIDE(i.s7_gp, NULLIF(i.s7_clk, 0)), 3) AS pace_gp_click,
    COALESCE(s.n_win, 0) >= 1 AS season_win_prior,
    COALESCE(lf.life_clk, 0) AS life_clk, COALESCE(lf.life_ord, 0) AS life_ord,
    lf.life_roas, lf.life_conv_cpc,
    COALESCE(l.ly_clk28, 0) AS ly_clk28, COALESCE(l.ly_ord28, 0) AS ly_ord28, l.ly_conv_cpc,
    COALESCE(i.clk28_kw, 0) AS clk28_kw, COALESCE(l.clk28_scope, 0) AS clk28_scope,
    -- v27.53 ITEM 8a — PACE NUMERATOR/DENOMINATOR GRAIN. Was SAFE_DIVIDE(i.clk28_kw, l.ly_clk28):
    -- an INSTANCE numerator (this campaign_id x keyword_id, last 28d) over a SCOPE denominator
    -- (account-wide text pool, LY same-28d). keyword_ids do NOT survive campaign recreations — the
    -- calibration's own load-bearing finding — so the ratio understated pace by however much of the
    -- text's traffic sits on OTHER instances, and PACE_RAISE fired on keywords already pacing fine.
    -- Measured 2026-08-12: 3 of 3 live PACE_RAISE rows were at 66-226% of LY pace, not < 25%.
    -- Both sides are now scope grain, which is the grain ly_clk28 was always computed at.
    ROUND(SAFE_DIVIDE(l.clk28_scope, NULLIF(l.ly_clk28, 0)), 3) AS pace_kw,
    ROUND(SAFE_DIVIDE(i.clk28_kw, NULLIF(l.ly_clk28, 0)), 3) AS pace_kw_instance,  -- pre-v27.53 form, display/audit only
    -- v27.53 ITEM 8b: vocabulary-translated join, profile OTHER cell as the fallback
    IF((SELECT in_peak FROM season),
       COALESCE(b.ceil_peak, b.ceil_off, bo.ceil_peak, bo.ceil_off),
       COALESCE(b.ceil_off, bo.ceil_off)) AS band_ceil,
    c.days_since_bid_change, c.lastc.src AS last_bid_source, c.lastc.dt AS last_bid_change_date,
    bc.lastb.src AS last_budget_source, bc.lastb.dt AS last_budget_change_date,
    -- v27.53 ITEM 7 — wake facts
    w.w.wake_date, w.w.wake_source,
    DATE_DIFF(wm.d, w.w.wake_date, DAY) AS days_since_wake,
    COALESCE(we.wake_clk, 0) AS wake_clk, COALESCE(we.wake_sp, 0) AS wake_sp,
    COALESCE(we.wake_ord, 0) AS wake_ord, COALESCE(we.wake_gp, 0) AS wake_gp,
    COALESCE(cp.is_oob_owned, FALSE) AS is_oob_owned, COALESCE(cp.days_capped_7d, 0) AS days_capped_7d
  FROM kws
  CROSS JOIN wm CROSS JOIN d CROSS JOIN k x0
  LEFT JOIN inst i ON i.cid = kws.campaign_id AND i.kwid = kws.keyword_id
  LEFT JOIN life lf ON lf.scope = kws.scope
  LEFT JOIN lys l ON l.scope = kws.scope
  LEFT JOIN band b ON b.parent_name = kws.parent_name AND b.match_type = kws.band_match
  LEFT JOIN band bo ON bo.parent_name = kws.parent_name AND bo.match_type = 'OTHER'
  LEFT JOIN seas s ON s.kw = LOWER(TRIM(kws.keyword_text))
  LEFT JOIN chg c ON c.keyword_id = kws.keyword_id
  LEFT JOIN bchg bc ON bc.campaign_id = kws.campaign_id
  LEFT JOIN wk w ON w.keyword_id = kws.keyword_id
  LEFT JOIN wkev we ON we.cid = kws.campaign_id AND we.kwid = kws.keyword_id
  LEFT JOIN cap cp ON cp.campaign_id = kws.campaign_id
)
SELECT
  c.*,
  -- derived verdict fields (the engines consume these flags)
  (c.settled_clk90 >= x.min_settled_clk AND COALESCE(c.settled_roas90, 0) >= 1.0) AS settled_winner,
  (c.settled_clk90 >= x.min_settled_clk AND COALESCE(c.settled_roas90, 0) < 1.0) AS corroborated_loser,
  (c.settled_clk90 >= x.min_settled_clk AND COALESCE(c.settled_roas90, 0) < 0.6) AS catastrophic,
  -- v27.52 FIX 1a — THE SETTLE VETO'S ESCAPE HATCH, bounded. This is the flag both engines read
  -- (season_win_prior stays published, but as a FACT for display/audit, never as the licence).
  -- A season WIN prior may excuse a corroborated settled loser from condemnation on unsettled
  -- clicks — but never a CATASTROPHIC one (< 0.6x on >= 10 SETTLED clicks). Measured 2026-08-12:
  -- 68 targets were structurally un-condemnable at that depth — $25,762 settled spend -> $18,872
  -- settled GP (0.733x blended, -$6,890 already spent, ~$498/day still running). A keyword losing
  -- money NOW at that depth is not a keyword with a good season behind it. This is the SAME escape
  -- manual_hold already carries (Cause 3): the season amnesty must not outrank Ori's own hand.
  (COALESCE(c.season_win_prior, FALSE)
   AND NOT (c.settled_clk90 >= x.min_settled_clk AND COALESCE(c.settled_roas90, 0) < 0.6)) AS settle_amnesty,
  (c.life_clk >= x.life_clk_bar AND COALESCE(c.life_roas, 1) < 0.6) AS record_loser,
  (c.last_bid_source = 'MANUAL'
   AND c.last_bid_change_date >= DATE_SUB(c.snapshot_date, INTERVAL x.manual_hold_days DAY)) AS manual_recent7,
  (c.last_bid_source = 'MANUAL'
   AND c.last_bid_change_date >= DATE_SUB(c.snapshot_date, INTERVAL x.manual_hold_days DAY)
   AND NOT (c.settled_clk90 >= x.min_settled_clk AND COALESCE(c.settled_roas90, 0) < 0.6)) AS manual_hold,
  -- v27.53 ITEM 8d — the BUDGET-side manual hold (campaign grain, carried on every keyword row of
  -- the campaign). No catastrophic escape: a budget is Ori's explicit, deliberate lever, and the
  -- bid-side dark brakes stay live above it (item 8f) so a dark campaign is still braked.
  (c.last_budget_source = 'MANUAL'
   AND c.last_budget_change_date >= DATE_SUB(c.snapshot_date, INTERVAL x.manual_hold_days DAY)) AS manual_budget_hold,
  -- LY-PACING RAISE (Cause 4) — the approved 2026-08-09 calibration, verbatim gates
  (COALESCE(c.pace_roas90s, 0) >= x.pace_roas_bar AND c.pace_clk90s >= x.min_settled_clk
   AND c.life_clk >= x.pace_life_clk AND c.ly_clk28 >= x.pace_ly_clk
   AND COALESCE(c.pace_kw, 1) < x.pace_threshold
   AND c.current_bid IS NOT NULL AND c.ly_conv_cpc IS NOT NULL AND c.current_bid < c.ly_conv_cpc
   AND NOT (c.is_oob_owned OR c.days_capped_7d >= 2)
   AND COALESCE(c.days_since_bid_change, 999) >= x.bid_stable_days) AS pace_flag,
  -- display-only WATCH tier (0.25 <= pace < 0.40): never instructs
  (COALESCE(c.pace_roas90s, 0) >= x.pace_roas_bar AND c.pace_clk90s >= x.min_settled_clk
   AND c.life_clk >= x.pace_life_clk AND c.ly_clk28 >= x.pace_ly_clk
   AND COALESCE(c.pace_kw, 1) >= x.pace_threshold AND COALESCE(c.pace_kw, 1) < x.pace_watch_threshold
   AND c.current_bid IS NOT NULL AND c.ly_conv_cpc IS NOT NULL AND c.current_bid < c.ly_conv_cpc
   AND NOT (c.is_oob_owned OR c.days_capped_7d >= 2)
   AND COALESCE(c.days_since_bid_change, 999) >= x.bid_stable_days) AS pace_watch,
  -- calibrated economics target (formula B): floor at current bid (winners never pulled down),
  -- caps = band ceiling (season cell), gp/click ÷ 1.2 (stays >= 1.2x at the target CPC),
  -- 1.5x LY conv CPC (anchor sanity), $2 hard cap
  ROUND(LEAST(GREATEST(COALESCE(c.current_bid, 0),
                       LEAST(COALESCE(c.band_ceil, 999),
                             COALESCE(SAFE_DIVIDE(c.pace_gp_click, 1.2), 0),
                             1.5 * COALESCE(c.ly_conv_cpc, 999))),
              x.bid_hard_cap), 2) AS pace_target_bid,
  -- ── v27.53 ITEM 7: THE WAKE STEP-DOWN ────────────────────────────────────────────
  -- WAKE_OPEN: still parked on the on-ramp — woken to $1.00, nothing has repriced it since
  -- (last logged bid change is the wake itself or older), bid still at/above the entry.
  -- $0.90 not $1.00: two of the 13 stuck rows read 0.94/0.95 in config (Amazon rounding / partial
  -- sync). The defect is "no reprice was ever logged", not the exact cent.
  (c.wake_date IS NOT NULL
   AND COALESCE(c.current_bid, 0) >= 0.90
   AND COALESCE(c.last_bid_change_date, c.wake_date) <= c.wake_date) AS wake_open,
  -- WAKE_DUE: the bounded deadline — evidence-driven with a hard time cap. The wake buys a keyword
  -- a LOOK, not a permanent $1.00 seat. Price it as soon as it has bought decision-grade traffic
  -- (10 clicks — the guard's own min_settled_clk), and in any case by day 7. The 11 keywords that
  -- DID get repriced averaged 2.7 days, so 7 days is a backstop, not the normal path.
  (c.wake_date IS NOT NULL
   AND COALESCE(c.current_bid, 0) >= 0.90
   AND COALESCE(c.last_bid_change_date, c.wake_date) <= c.wake_date
   AND (COALESCE(c.wake_clk, 0) >= x.min_settled_clk
        OR DATE_DIFF(c.anchor_date, c.wake_date, DAY) >= 7)) AS wake_due,
  -- WAKE_STEP_BID: what "then price it" means, in the keyword's own numbers. Never a raise
  -- (LEAST 1.00 — this is the step DOWN half), never below the SP platform floor.
  --   earned (>= 4 clicks and GP > 0) -> its own profit per click since the wake (breakeven price);
  --   clicked without earning        -> the price it has historically CLEARED at (lifetime conv
  --                                     CPC), capped at $0.60 so a rich history cannot re-anchor it;
  --   never clicked at all           -> the wake bought nothing in 7+ days: back to $0.25.
  ROUND(LEAST(1.00, GREATEST(0.20, COALESCE(
    IF(COALESCE(c.wake_clk, 0) >= 4 AND COALESCE(c.wake_gp, 0) > 0,
       SAFE_DIVIDE(c.wake_gp, NULLIF(c.wake_clk, 0)), NULL),
    IF(COALESCE(c.wake_clk, 0) >= 4, LEAST(COALESCE(c.life_conv_cpc, 0.25), 0.60), NULL),
    0.25))), 2) AS wake_step_bid
FROM calc c CROSS JOIN k x;
