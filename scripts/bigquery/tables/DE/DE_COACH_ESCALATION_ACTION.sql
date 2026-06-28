-- DE_COACH_ESCALATION_ACTION — log of Ori's actions on This Week escalations (Coacher E surface).
-- One row per action (ACK / SNOOZE). The surface view reads the latest action per escalation_key
-- (parent_name|trigger) to decide whether an escalation is currently handled (muted) or re-surfaced.
-- All-logic-in-backend: handled state lives here, not in the frontend.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_COACH_ESCALATION_ACTION` (
  escalation_key      STRING NOT NULL,   -- parent_name || '|' || trigger
  parent_name         STRING,
  trigger             STRING,
  action              STRING,            -- 'ACK' | 'SNOOZE'
  severity_at_action  STRING,            -- severity when actioned — re-surface if it later worsens
  note                STRING,
  snooze_until        DATE,              -- set for SNOOZE; handled until this date
  created_at          TIMESTAMP,
  created_by          STRING
);
