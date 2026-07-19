-- MIGRATE_STRATEGY_CONSOLIDATION — Ori 2026-07-17. Consolidates the offense strategy list:
--   HUNTER + LOW_COST_DISCOVERY  → INTENT   (one strategy; INTENT keeps HUNTER's rules verbatim)
--   COMPETITOR_CONQUEST          → COMPETITOR  (rename)
--   CATEGORY_CONQUEST            → COMPETITOR  (removed; its 5 campaigns reassign)
--
-- WHY CATEGORY_CONQUEST FOLDS INTO COMPETITOR: despite the name it was never doing category targeting.
-- All 5 campaigns are named COMPETE/Conquest, 14 of their top 15 targets (90d) are competitor ASINs —
-- asin="B0FDKRTH55" alone took 1,682 clicks / $1,732 — and exactly one target is a real category
-- (category="Kids' Scrapbooking Kits", 432 clicks). V_CAMPAIGN_ROLE already classified all of them as
-- the COMPETITOR coverage role, so this makes the label match what they were already treated as.
-- Only ONE is enabled: "ME-SP/PT (Conquest, Competitors)" — $2,572 / 90d at 1.12x net ROAS.
--
-- WHY INTENT INHERITS HUNTER, NOT LOW_COST_DISCOVERY: Ori's call ("rules of INTENT like hunter").
-- This RE-TUNES LOW_COST_DISCOVERY's 27 campaigns — they become more patient: scale at 2.0x not 1.5x,
-- negate at 0.3 ROAS / $15 not 0.5 / $8, judge at 15 clicks not 10, tolerate $10 wasted not $5.
--
-- ⚠ BEHAVIOUR CHANGE ON THE 5 REASSIGNED CAMPAIGNS: CATEGORY_CONQUEST carried 6 threshold overrides;
-- COMPETITOR_CONQUEST carried only BID_CAP_SUGGESTION. Folding into COMPETITOR drops those overrides,
-- so the reassigned campaigns fall back to GLOBAL: SCALE_UP_ROAS 1.0 → 2.0 (stops scaling as eagerly),
-- NEGATE_ROAS_THRESHOLD 0.3 → 0.5 (negates more), WASTED_SPEND_THRESHOLD 20 → 15. This affects the one
-- live campaign above. Preserving the old behaviour = re-add those keys under strategy_id='COMPETITOR'.
--
-- REVERSIBLE: run the ROLLBACK block at the bottom to restore every id. No row is deleted that cannot
-- be rebuilt from the seed files (DIM_STRATEGY_TEMPLATE.sql, DE_COACH_THRESHOLDS.sql).

-- ── 1. Campaign→strategy mappings (99 campaigns / 98 experiments) ──────────────────────────────────
UPDATE `onyga-482313.OI.DIM_EXPERIMENT`
SET strategy_id = 'INTENT'
WHERE strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY');

UPDATE `onyga-482313.OI.DIM_EXPERIMENT`
SET strategy_id = 'COMPETITOR'
WHERE strategy_id IN ('COMPETITOR_CONQUEST', 'CATEGORY_CONQUEST');

-- ── 2. Coach thresholds ───────────────────────────────────────────────────────────────────────────
-- INTENT = HUNTER's rules: drop LOW_COST_DISCOVERY's competing rows FIRST, then relabel HUNTER's.
DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` WHERE strategy_id = 'LOW_COST_DISCOVERY';
UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS` SET strategy_id = 'INTENT' WHERE strategy_id = 'HUNTER';

-- COMPETITOR keeps COMPETITOR_CONQUEST's rules (its 13 campaigns are the majority and already ran on
-- GLOBAL + BID_CAP); CATEGORY_CONQUEST's 6 overrides go — see the warning above.
DELETE FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` WHERE strategy_id = 'CATEGORY_CONQUEST';
UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS` SET strategy_id = 'COMPETITOR' WHERE strategy_id = 'COMPETITOR_CONQUEST';

-- ── 3. Strategy templates ─────────────────────────────────────────────────────────────────────────
-- INTENT from HUNTER's row (BROAD / UP_AND_DOWN / TOS 200) — the intent-grouped model's offense
-- strategy. Match type is an axis of the campaign grain (family x match-type x intent), not a property
-- of the strategy, so recommended_match_type is informational only.
UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET strategy_id = 'INTENT',
    strategy_name = 'Intent',
    description = 'Intent-grouped offense: one campaign per (family x match-type x intent theme), <=10 keywords. Supersedes Hunter (broad keyword hunting) and Low-Cost Discovery (cheap auto discovery) — both folded in 2026-07-17. New campaigns start at $10/day and a $1.00 bid, then follow the launch ramp for 20 days (architecture/CAMPAIGN_LAUNCH_RAMP.md).',
    updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'HUNTER';

UPDATE `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
SET strategy_id = 'COMPETITOR',
    strategy_name = 'Competitor',
    description = 'Target competitor ASINs with product targeting to show your ad on their product pages. Absorbed Category Conquest 2026-07-17 (which was doing ASIN conquest, not category targeting).',
    updated_at = CURRENT_TIMESTAMP()
WHERE strategy_id = 'COMPETITOR_CONQUEST';

DELETE FROM `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
WHERE strategy_id IN ('LOW_COST_DISCOVERY', 'CATEGORY_CONQUEST');

-- ── 4. Campaign-creation templates (bulksheet defaults) ───────────────────────────────────────────
UPDATE `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE`
SET strategy_id = 'INTENT' WHERE strategy_id = 'HUNTER';
DELETE FROM `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE` WHERE strategy_id = 'LOW_COST_DISCOVERY';
UPDATE `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE`
SET strategy_id = 'COMPETITOR' WHERE strategy_id = 'COMPETITOR_CONQUEST';
DELETE FROM `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE` WHERE strategy_id = 'CATEGORY_CONQUEST';

/* ── ROLLBACK ──────────────────────────────────────────────────────────────────────────────────────
   Restores the ids. NOTE: it cannot tell a former HUNTER from a former LOW_COST_DISCOVERY (or
   COMPETITOR_CONQUEST from CATEGORY_CONQUEST) — the merge is lossy at the mapping level. To undo
   fully, restore DIM_EXPERIMENT from a snapshot taken before this ran, and re-seed the threshold and
   template tables from scripts/bigquery/tables/.

   UPDATE `onyga-482313.OI.DIM_EXPERIMENT` SET strategy_id='HUNTER' WHERE strategy_id='INTENT';
   UPDATE `onyga-482313.OI.DIM_EXPERIMENT` SET strategy_id='COMPETITOR_CONQUEST' WHERE strategy_id='COMPETITOR';
   UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS` SET strategy_id='HUNTER' WHERE strategy_id='INTENT';
   UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS` SET strategy_id='COMPETITOR_CONQUEST' WHERE strategy_id='COMPETITOR';
   -- then re-run: scripts/bigquery/tables/DE/DE_COACH_THRESHOLDS.sql
   --              scripts/bigquery/tables/DIM/DIM_STRATEGY_TEMPLATE.sql
─────────────────────────────────────────────────────────────────────────────────────────────────── */
