-- DE_WEEKLY_RUN — per-(family × week) status for the Weekly Run workflow (Coacher D surface).
-- One row per Ori action (APPROVE / DONE); V_WEEKLY_RUN reads the latest per (family, week).
-- All-logic-in-backend: workflow status lives here, not in the frontend.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_WEEKLY_RUN` (
  parent_name    STRING NOT NULL,   -- family
  week_start     DATE   NOT NULL,   -- Sunday week start (matches DE_WEEKLY_PLAN)
  status         STRING,            -- 'APPROVED' | 'DONE'
  approved_at    TIMESTAMP,
  done_at        TIMESTAMP,
  note           STRING,
  actions_queued INT64,
  updated_at     TIMESTAMP,
  updated_by     STRING
);
