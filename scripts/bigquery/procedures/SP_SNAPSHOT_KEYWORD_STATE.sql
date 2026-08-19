-- =============================================
-- SP_SNAPSHOT_KEYWORD_STATE — the roadmap of each keyword (2026-08-16, Task 2.1).
-- Spec: architecture/KEYWORD_STATE.md.
--
-- ASSEMBLY, NOT JUDGMENT: every input is a verdict some other object already made — the guard's
-- settled record, the reverdict's park ruling, panel ownership's single-home ladder, today's
-- preflight instructions, the change log's last touch. This SP only PLACES each keyword in the
-- one state those verdicts imply, names its owner, and stamps its next appointment. If a state
-- looks wrong, the fix belongs in the SOURCE object, never here.
--
-- Reads ONLY snapshot tables + the applied change log (all small) — seconds, planner-safe.
-- Population: FULL OUTER of guard keys and parked-population keys (~1k rows).
-- Orchestrator Task 20.8, right after SP_ENGINE_PREFLIGHT (20.7) so PACED_WINNER and the
-- REVIVE-today appointment read the same day's instructions the panels show.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_KEYWORD_STATE`()
OPTIONS (
  description = "Keyword state machine (Task 2.1, 2026-08-16): one row per (campaign, keyword) — state (DEAD | PENDING_SETTLE | REVIVED_SETTLING | PARKED | PACED_WINNER | WINNER | LOSER_BLEED | TRIAL, first-match ladder), owner (FACT_PANEL_OWNERSHIP ladder + REVERDICT-above-LIFT overlay), next_check_date (never NULL except DEAD — invariant 2), season context and a view-authored reason. Pure assembly of other snapshots' verdicts. Runs as orchestrator Task 20.8 after the preflight. Invariants read by V_ENGINE_HEALTH. Spec: architecture/KEYWORD_STATE.md."
)
BEGIN
  CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_KEYWORD_STATE` AS
  WITH g AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           keyword_text, match_type, channel, is_auto, is_pt, current_bid, parent_name,
           settled_clk90, settled_ord90, settled_roas90, settled_cpc90,
           settle_ok, settle_due, last_click_date, season_win_prior, last_bid_change_date
    FROM `onyga-482313.OI.FACT_KEYWORD_GUARD`
  ),
  rv AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           keyword_text, match_type, channel, current_bid,
           reverdict, revive_bid, revive_settling, park_date, settle_due AS rv_settle_due,
           s90_gp_roas AS rv_roas90, s90_clk AS rv_clk90
    FROM `onyga-482313.OI.FACT_PARK_REVERDICT`
    WHERE reverdict IN ('REVIVE', 'SIBLING_REVIVE', 'CONFIRM_PARK', 'REDUNDANT', 'PENDING_SETTLE', 'INSUFFICIENT')
       OR COALESCE(revive_settling, FALSE)
  ),
  po AS (
    SELECT CAST(campaign_id AS STRING) cid, campaign_name, family, owner
    FROM `onyga-482313.OI.FACT_PANEL_OWNERSHIP`
  ),
  -- today's instructions: PACED_WINNER + the "revive is in today's plan" appointment
  pf AS (
    SELECT campaign_id cid, COALESCE(keyword_id, '') kid,
           LOGICAL_OR(verdict = 'GO' AND lever = 'BID'
                      AND suggested_bid IS NOT NULL AND current_bid IS NOT NULL
                      AND suggested_bid < current_bid - 0.005) AS go_bid_down
    FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`
    GROUP BY 1, 2
  ),
  lc AS (
    SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
           MAX(DATE(applied_at, 'America/Los_Angeles')) AS last_applied
    FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
    WHERE keyword_id IS NOT NULL
    GROUP BY 1, 2
  ),
  base AS (
    SELECT
      COALESCE(g.cid, rv.cid) AS campaign_id,
      COALESCE(g.kid, rv.kid) AS keyword_id,
      COALESCE(g.keyword_text, rv.keyword_text) AS target_text,
      COALESCE(g.match_type, rv.match_type) AS match_type,
      COALESCE(g.channel, rv.channel) AS channel,
      g.is_auto, g.is_pt,
      COALESCE(g.current_bid, rv.current_bid) AS current_bid,
      g.settled_clk90, g.settled_ord90, g.settled_roas90, g.settled_cpc90,
      g.settle_ok, g.settle_due, g.last_click_date, g.season_win_prior, g.last_bid_change_date,
      rv.reverdict, rv.revive_bid, rv.revive_settling, rv.park_date, rv.rv_settle_due,
      rv.rv_roas90, rv.rv_clk90
    FROM g
    FULL OUTER JOIN rv ON rv.cid = g.cid AND rv.kid = g.kid
  ),
  st AS (
    SELECT b.*,
      po.campaign_name, po.family, po.owner AS campaign_owner,
      COALESCE(pf.go_bid_down, FALSE) AS paced_today,
      lc.last_applied,
      -- THE LADDER (first match wins — order is doctrine, see the SOP table)
      CASE
        -- review find: a tested loser carrying a SIBLING verdict must SURFACE, not vanish into DEAD
        WHEN COALESCE(b.settled_clk90, 0) >= 15 AND COALESCE(b.settled_ord90, 0) = 0
         AND COALESCE(b.reverdict, '') NOT IN ('SIBLING_REVIVE', 'REDUNDANT') THEN 'DEAD'
        WHEN b.reverdict = 'PENDING_SETTLE' THEN 'PENDING_SETTLE'
        WHEN COALESCE(b.revive_settling, FALSE) THEN 'REVIVED_SETTLING'
        WHEN b.reverdict IN ('REVIVE', 'SIBLING_REVIVE', 'CONFIRM_PARK', 'REDUNDANT', 'INSUFFICIENT') THEN 'PARKED'
        WHEN COALESCE(b.settled_roas90, 0) >= 1.0 AND COALESCE(b.settled_clk90, 0) >= 10
          THEN IF(COALESCE(pf.go_bid_down, FALSE), 'PACED_WINNER', 'WINNER')
        WHEN COALESCE(b.settled_roas90, 1) < 0.6 AND COALESCE(b.settled_clk90, 0) >= 10 THEN 'LOSER_BLEED'
        ELSE 'TRIAL' END AS state
    FROM base b
    LEFT JOIN po ON po.cid = b.campaign_id
    LEFT JOIN pf ON pf.cid = b.campaign_id AND pf.kid = b.keyword_id
    LEFT JOIN lc ON lc.cid = b.campaign_id AND lc.kid = b.keyword_id
  )
  SELECT
    CURRENT_DATE('America/Los_Angeles') AS snapshot_date,
    s.campaign_id, s.keyword_id, s.target_text, s.match_type, s.channel, s.is_auto, s.is_pt,
    s.campaign_name, s.family, s.current_bid,
    s.state,
    -- OWNER: the campaign's single-home owner, with the one keyword-grain overlay — a LIFT-owned
    -- keyword whose reverdict says REVIVE belongs to REVERDICT (the preflight ladder, at rest).
    CASE WHEN s.reverdict = 'REVIVE' AND COALESCE(s.campaign_owner, 'LIFT') = 'LIFT'
         THEN 'REVERDICT' ELSE COALESCE(s.campaign_owner, 'LIFT') END AS owner_engine,
    -- state_since: best-effort (SOP v1 note) — park events are dated, live states use the last touch
    CASE WHEN s.state IN ('PARKED', 'PENDING_SETTLE') THEN s.park_date
         ELSE COALESCE(s.last_bid_change_date, s.last_applied) END AS state_since,
    s.settled_clk90, s.settled_ord90, s.settled_roas90, s.settled_cpc90,
    s.season_win_prior AS season_context,
    -- NEXT APPOINTMENT (invariant 2: NULL only on DEAD)
    CASE s.state
      WHEN 'DEAD' THEN CAST(NULL AS DATE)
      WHEN 'PENDING_SETTLE' THEN COALESCE(s.rv_settle_due, DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY))
      WHEN 'REVIVED_SETTLING' THEN COALESCE(s.rv_settle_due, DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY))
      WHEN 'PARKED' THEN CASE s.reverdict
          WHEN 'REVIVE' THEN CURRENT_DATE('America/Los_Angeles')
          WHEN 'SIBLING_REVIVE' THEN CURRENT_DATE('America/Los_Angeles')
          WHEN 'CONFIRM_PARK' THEN DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
          WHEN 'REDUNDANT' THEN DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
          ELSE COALESCE(s.rv_settle_due, DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)) END
      WHEN 'PACED_WINNER' THEN DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
      ELSE COALESCE(
        IF(NOT COALESCE(s.settle_ok, TRUE), s.settle_due, NULL),
        IF(s.last_applied IS NOT NULL, DATE_ADD(s.last_applied, INTERVAL 14 DAY), NULL),
        DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)) END AS next_check_date,
    CASE s.state
      WHEN 'DEAD' THEN 'tested loser — thesis falsified; only family sibling evidence reopens it'
      WHEN 'PENDING_SETTLE' THEN 'park re-judged when its clicks settle'
      WHEN 'REVIVED_SETTLING' THEN 'revived — new clicks settling before the next verdict'
      WHEN 'PARKED' THEN CASE s.reverdict
          WHEN 'REVIVE' THEN "revival proposed — in today's plan"
          WHEN 'CONFIRM_PARK' THEN 'park confirmed on settled evidence — 14d revival sweep re-checks'
          ELSE 'parked, record too thin to judge — re-read at settle' END
      WHEN 'PACED_WINNER' THEN 'winner being paced today (capped budget) — pace re-fires daily'
      WHEN 'WINNER' THEN 'proven — holding; the budget raise is the lever'
      WHEN 'LOSER_BLEED' THEN 'settled loser still live — negates first, bid second'
      ELSE 'gathering evidence at seat pace' END AS next_check_what,
    -- the reason with the numbers (view-authored, one sentence)
    CASE s.state
      WHEN 'DEAD' THEN CONCAT(CAST(s.settled_clk90 AS STRING), ' settled clicks, 0 orders')
      WHEN 'WINNER' THEN CONCAT(FORMAT('%.2f', s.settled_roas90), 'x over ', CAST(s.settled_clk90 AS STRING), ' settled clicks')
      WHEN 'PACED_WINNER' THEN CONCAT(FORMAT('%.2f', s.settled_roas90), 'x proven; a GO pace instruction is live today')
      WHEN 'LOSER_BLEED' THEN CONCAT(FORMAT('%.2f', COALESCE(s.settled_roas90, 0)), 'x over ', CAST(s.settled_clk90 AS STRING), ' settled clicks — below 0.6')
      WHEN 'PARKED' THEN CASE s.reverdict
          WHEN 'REVIVE' THEN CONCAT('settled record overturns the park — revival proposed at $',
                                    FORMAT('%.2f', COALESCE(s.revive_bid, 0)))
          WHEN 'SIBLING_REVIVE' THEN 'a sibling campaign proves this term — revival proposed (hand-check)'
          WHEN 'REDUNDANT' THEN 'family already serves this term elsewhere — stays parked (no double-bid)'
          WHEN 'CONFIRM_PARK' THEN CONCAT('re-checked on full 90d data (',
              CAST(COALESCE(s.settled_clk90, s.rv_clk90, 0) AS STRING), ' clicks) — the park stands')
          ELSE CONCAT('only ', CAST(COALESCE(s.settled_clk90, s.rv_clk90, 0) AS STRING),
                      ' settled clicks — too thin to judge either way yet') END
      ELSE CONCAT(CAST(COALESCE(s.settled_clk90, 0) AS STRING), ' settled clicks so far') END AS state_reason
  FROM st s;
END;
