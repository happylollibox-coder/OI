-- =============================================
-- OI Database Project - V_FACT_AMAZON_PERFORMANCE_DAILY View
-- =============================================
--
-- Purpose: Simple passthrough view over FACT_AMAZON_PERFORMANCE_DAILY
--          to provide a stable object name for BI tools (e.g. Power BI)
--          without depending directly on the physical table definition.
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_FACT_AMAZON_PERFORMANCE_DAILY`
AS
SELECT
  *
FROM
  `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`;

