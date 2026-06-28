-- =============================================
-- SP_REFRESH_PEAK_KEYWORD_RECS
-- =============================================
-- Materializes V_PEAK_KEYWORD_RECS → T_PEAK_KEYWORD_RECS, kept unique per
-- (parent_name, search_term, holiday_name) so V_ADS_COACH can join the family's ACTIVE
-- occasion 1:1 for the 📈 Peak-plan decision-trace chip.
--
-- Decoupled from SP_REFRESH_ADS_COACH_ACTIONS on purpose: V_PEAK_KEYWORD_RECS re-scans the
-- heavy V_RESEARCH_RANKED, which tripled the coach SP's runtime. Schedule this to run BEFORE
-- the coach refresh so the chips reflect the current peak plan.
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_PEAK_KEYWORD_RECS`()
BEGIN
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_PEAK_KEYWORD_RECS` AS
  SELECT * EXCEPT(rn) FROM (
    SELECT *, ROW_NUMBER() OVER (
      PARTITION BY LOWER(parent_name), LOWER(search_term), holiday_name
      ORDER BY priority_score DESC
    ) AS rn
    FROM `onyga-482313.OI.V_PEAK_KEYWORD_RECS`
  ) WHERE rn = 1;
END;
