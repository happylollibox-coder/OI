-- SP_REVIEW_WEEKLY_PLAN — persist the review's status/actual onto DE_WEEKLY_PLAN so learnings
-- accumulate. Run weekly (after the week completes), before the generator. Coacher D. Idempotent.
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REVIEW_WEEKLY_PLAN`()
BEGIN
  UPDATE `onyga-482313.OI.DE_WEEKLY_PLAN` p
  SET status = r.status,
      actual_value = CASE p.success_metric WHEN 'NET_PROFIT' THEN r.actual_net
                                            WHEN 'SPEND_DOWN' THEN r.actual_spend ELSE p.actual_value END,
      updated_at = CURRENT_TIMESTAMP()
  FROM `onyga-482313.OI.V_WEEKLY_PLAN_REVIEW` r
  WHERE p.week_start = r.week_start AND p.parent_name = r.parent_name
    AND p.season = r.season AND p.match_type = r.match_type AND p.intent_class = r.intent_class
    AND r.status IN ('ON_PLAN','OFF_PLAN');
END;
