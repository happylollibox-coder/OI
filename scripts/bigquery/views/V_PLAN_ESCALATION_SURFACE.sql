-- V_PLAN_ESCALATION_SURFACE — V_PLAN_ESCALATION + Ori's handled state (Coacher E surface).
-- Adds escalation_key (parent|trigger) and is_handled: an escalation is handled (muted) once
-- acknowledged/snoozed, UNLESS it later worsens (current severity > severity when actioned) or the
-- snooze window expires — mirroring the D/E "persistent → re-escalate" rule. Served fresh by Flask
-- (/api/coach/escalations) so the page reflects an Ack/Snooze immediately.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_ESCALATION_SURFACE` AS
WITH esc AS (
  SELECT *,
    CONCAT(parent_name, '|', COALESCE(trigger, '')) AS escalation_key,
    CASE UPPER(severity) WHEN 'ESCALATE' THEN 2 WHEN 'WATCH' THEN 1 ELSE 0 END AS sev_rank
  FROM `onyga-482313.OI.V_PLAN_ESCALATION`
),
key_sev AS (   -- current worst severity per escalation_key
  SELECT escalation_key, MAX(sev_rank) AS cur_sev_rank
  FROM esc GROUP BY escalation_key
),
latest AS (    -- most recent action per escalation_key
  SELECT escalation_key, action, snooze_until, note, created_at,
    CASE UPPER(severity_at_action) WHEN 'ESCALATE' THEN 2 WHEN 'WATCH' THEN 1 ELSE 0 END AS acted_sev_rank,
    ROW_NUMBER() OVER (PARTITION BY escalation_key ORDER BY created_at DESC) AS rn
  FROM `onyga-482313.OI.DE_COACH_ESCALATION_ACTION`
)
SELECT
  e.* EXCEPT (sev_rank),
  la.action       AS last_action,
  la.snooze_until AS snooze_until,
  la.note         AS handled_note,
  la.created_at   AS handled_at,
  CASE
    WHEN la.action IS NULL THEN FALSE
    WHEN ks.cur_sev_rank > la.acted_sev_rank THEN FALSE   -- worsened since handled → re-surface
    WHEN la.action = 'SNOOZE' AND la.snooze_until IS NOT NULL
         AND la.snooze_until < CURRENT_DATE('America/Los_Angeles') THEN FALSE   -- snooze expired
    ELSE TRUE
  END AS is_handled
FROM esc e
JOIN key_sev ks ON ks.escalation_key = e.escalation_key
LEFT JOIN latest la ON la.escalation_key = e.escalation_key AND la.rn = 1
