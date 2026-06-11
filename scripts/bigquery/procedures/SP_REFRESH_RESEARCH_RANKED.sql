-- =============================================
-- SP_REFRESH_RESEARCH_RANKED
-- =============================================
--
-- Purpose: Materializes the Research page scoring layer so endpoints read
--          pre-computed tables instead of recomputing the family × term
--          cross-join views per request:
--            V_RESEARCH_TERMS  → FACT_RESEARCH_TERMS   (term grain)
--            V_RESEARCH_RANKED → FACT_RESEARCH_RANKED  (parent × term grain)
--
-- Manual segment overrides (DE_SEARCH_TERM_SEGMENTS) surface in the FACT
-- tables on the next run of this procedure.
--
-- Called by: SP_ORCHESTRATE_DAILY_REFRESH (after SP_LOAD_FACT_SEARCH_QUERY)
-- Validation: tools/validate_research_ranked.py
-- SOP: architecture/RESEARCH_PAGE.md
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_RESEARCH_RANKED`()
BEGIN

  CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_RESEARCH_TERMS`
  AS SELECT * FROM `onyga-482313.OI.V_RESEARCH_TERMS`;

  CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_RESEARCH_RANKED`
  CLUSTER BY parent_name, query_text
  AS SELECT * FROM `onyga-482313.OI.V_RESEARCH_RANKED`;

END;
