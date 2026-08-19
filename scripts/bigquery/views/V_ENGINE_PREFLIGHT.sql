-- =============================================
-- V_ENGINE_PREFLIGHT — thin read surface over T_ENGINE_PREFLIGHT (2026-08-15).
-- Spec: architecture/ENGINE_PREFLIGHT.md. NO LOGIC HERE — the verdicts are the SP's; this view
-- exists so the cube and panels have a stable name to read and so ad-hoc checks read one object.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ENGINE_PREFLIGHT` AS
SELECT * FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`;
