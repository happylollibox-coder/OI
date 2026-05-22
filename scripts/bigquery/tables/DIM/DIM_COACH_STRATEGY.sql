-- =============================================
-- OI Database Project - DIM_COACH_STRATEGY Table
-- =============================================
--
-- Purpose: Defines the strategic framework for each coach mode.
--          Each mode has a north star (KPI target), strategic tasks
--          that explain HOW the coach achieves the target, and
--          mitigation plans if targets aren't being met.
--
-- Grain: coach_mode × task_id
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_COACH_STRATEGY` (
  coach_mode STRING NOT NULL,           -- GUARDIAN / BLITZ / COOLDOWN
  north_star STRING NOT NULL,           -- human-readable target description
  north_star_metric STRING NOT NULL,    -- metric identifier for dashboard
  north_star_target FLOAT64,            -- numeric target value (e.g. 1.1 for ROAS)
  task_id STRING NOT NULL,              -- strategic task identifier
  task_name STRING NOT NULL,            -- display name
  task_description STRING NOT NULL,     -- one-line explanation of the task
  capability STRING NOT NULL,           -- BID_ADJUST / BUDGET_ADJUST / PLACEMENT_ADJUST / NEGATE_TERM / BOOST_TERM / REPLACE_HERO / MONITOR
  capability_direction STRING,          -- UP / DOWN / null (for non-directional)
  display_order INT64 NOT NULL,         -- sort order in dashboard
  mitigation STRING,                    -- fallback plan description (advisory)
  emoji STRING,                         -- display emoji for task card

  PRIMARY KEY (coach_mode, task_id) NOT ENFORCED
)
OPTIONS (
  description = "Coach strategy framework: north star targets, strategic tasks, capabilities, and mitigation plans per mode."
);

-- =============================================
-- Seed data: 16 strategic tasks across 3 modes
-- =============================================
DELETE FROM `onyga-482313.OI.DIM_COACH_STRATEGY` WHERE TRUE;

INSERT INTO `onyga-482313.OI.DIM_COACH_STRATEGY`
  (coach_mode, north_star, north_star_metric, north_star_target, task_id, task_name, task_description, capability, capability_direction, display_order, mitigation, emoji)
VALUES
  -- ===================== 🛡 GUARDIAN =====================
  ('GUARDIAN', 'Net ROAS ≥ 1.1 portfolio-wide', 'NET_ROAS', 1.1, 'ELIMINATE_WASTE',
   'Eliminate Waste', 'Cut terms spending with zero conversions and sufficient data',
   'NEGATE_TERM', null, 1,
   'If ROAS drops below 0.9, lower min_clicks threshold to catch more waste faster', '🗑️'),

  ('GUARDIAN', 'Net ROAS ≥ 1.1 portfolio-wide', 'NET_ROAS', 1.1, 'OPTIMIZE_BIDS',
   'Optimize Bids', 'Reduce bids on underperforming targets to cut losses',
   'BID_ADJUST', 'DOWN', 2,
   'If losses persist after bid reduction, escalate to STOP_TARGET', '📉'),

  ('GUARDIAN', 'Net ROAS ≥ 1.1 portfolio-wide', 'NET_ROAS', 1.1, 'SCALE_WINNERS',
   'Scale Winners', 'Increase bids on profitable targets to capture more volume',
   'BID_ADJUST', 'UP', 3,
   'If ROAS drops after scaling, reduce back to original bid', '📈'),

  ('GUARDIAN', 'Net ROAS ≥ 1.1 portfolio-wide', 'NET_ROAS', 1.1, 'PROMOTE_TERMS',
   'Promote Terms', 'Graduate proven broad/auto terms to exact match campaigns',
   'BOOST_TERM', null, 4,
   'Monitor promoted terms for 2 weeks; revert if ROAS < 0.7', '🚀'),

  ('GUARDIAN', 'Net ROAS ≥ 1.1 portfolio-wide', 'NET_ROAS', 1.1, 'CORRECT_HEROES',
   'Fix Hero ASINs', 'Switch advertised ASIN to the proven hero for each keyword',
   'REPLACE_HERO', null, 5,
   'If CVR drops after hero switch, revert within 7 days', '🔄'),

  ('GUARDIAN', 'Net ROAS ≥ 1.1 portfolio-wide', 'NET_ROAS', 1.1, 'MAINTAIN',
   'Maintain', 'No action needed — targets performing at acceptable levels',
   'MONITOR', null, 6,
   null, '✅'),

  -- ===================== 🔥 BLITZ =====================
  ('BLITZ', 'Maximize impression share and capture peak demand', 'IMPRESSION_SHARE', null, 'INCREASE_BUDGETS',
   'Increase Budgets', 'Scale campaign budgets to capture peak season demand',
   'BUDGET_ADJUST', 'UP', 1,
   'If spend > 2× baseline with ROAS < 0.5, reduce budgets 20%', '💰'),

  ('BLITZ', 'Maximize impression share and capture peak demand', 'IMPRESSION_SHARE', null, 'BOOST_PLACEMENTS',
   'Boost Placements', 'Increase TOS and Product Page placement bids for visibility',
   'PLACEMENT_ADJUST', 'UP', 2,
   'If ACoS exceeds 40% on placements, reduce modifiers by 50%', '📍'),

  ('BLITZ', 'Maximize impression share and capture peak demand', 'IMPRESSION_SHARE', null, 'SCALE_WINNERS',
   'Scale Winners', 'Aggressively increase bids on converting terms during peak',
   'BID_ADJUST', 'UP', 3,
   'Cap bid increases at 2× pre-peak level', '📈'),

  ('BLITZ', 'Maximize impression share and capture peak demand', 'IMPRESSION_SHARE', null, 'PROMOTE_TERMS',
   'Promote Terms', 'Capture high-volume seasonal terms in exact match campaigns',
   'BOOST_TERM', null, 4,
   'Priority: terms with SQP volume > 1000 and purchases > 0', '🚀'),

  ('BLITZ', 'Maximize impression share and capture peak demand', 'IMPRESSION_SHARE', null, 'PROTECT_TERMS',
   'Protect Terms', 'Keep seasonal terms active even with marginal ROAS (relaxed thresholds)',
   'MONITOR', null, 5,
   'Only negate if ROAS < -1.0 (severe loss)', '🛡️'),

  ('BLITZ', 'Maximize impression share and capture peak demand', 'IMPRESSION_SHARE', null, 'COST_CONTROL',
   'Cost Control', 'Reduce severely bleeding terms even during peak season',
   'BID_ADJUST', 'DOWN', 6,
   'Escalate: if 3+ consecutive days of negative ROAS, switch to STOP_TARGET', '⚠️'),

  -- ===================== ❄️ COOLDOWN =====================
  ('COOLDOWN', 'Restore daily spend to pre-peak baseline', 'BUDGET_RATIO', 1.0, 'RESTORE_BUDGETS',
   'Restore Budgets', 'Return campaign budgets to pre-peak levels',
   'BUDGET_ADJUST', 'DOWN', 1,
   'If revenue drops > 30% after budget cut, slow the reduction', '💰'),

  ('COOLDOWN', 'Restore daily spend to pre-peak baseline', 'BUDGET_RATIO', 1.0, 'NORMALIZE_BIDS',
   'Normalize Bids', 'Reduce inflated bids back to pre-peak levels per ROAS tier',
   'BID_ADJUST', 'DOWN', 2,
   'If any campaign ROAS < 0.3 post-peak, escalate to RESTORE_PRE_PEAK immediately', '📉'),

  ('COOLDOWN', 'Restore daily spend to pre-peak baseline', 'BUDGET_RATIO', 1.0, 'PROTECT_TERMS',
   'Protect Terms', 'Preserve all term targeting — zero negations during cooldown',
   'MONITOR', null, 3,
   'Negation suppressed systemically; no mitigation needed', '🛡️'),

  ('COOLDOWN', 'Restore daily spend to pre-peak baseline', 'BUDGET_RATIO', 1.0, 'MONITOR_PERFORMANCE',
   'Monitor Performance', 'Track post-peak ROAS for controlled wind-down decisions',
   'MONITOR', null, 4,
   'If performance strong post-peak, delay bid reduction to preserve momentum', '👁️');
