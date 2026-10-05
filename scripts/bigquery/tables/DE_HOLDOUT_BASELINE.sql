-- =============================================
-- DE_HOLDOUT_BASELINE — each founding control's value, at the assignment, of the settings no source can
-- date. Append-only. Spec: architecture/HOLDOUT.md §4, §6 ("What the alarm sees", kind 4). Plan:
-- docs/superpowers/plans/2026-10-03-holdout-restart.md (§2.7 kind 4, Task 2 Step 3b, Task 3, K12).
--
-- WHY. Placement and shopper-cohort bid adjustments and SB product targets live in current-state Fivetran
-- tables that keep no history, so a change to them cannot be dated. V_ENGINE_HEALTH c33
-- (holdout_unit_changed, BASELINE_DIFF) compares today's PRESENT settings of the watched controls with the
-- latest row here per (campaign_id, setting); a difference stands RED until Ori rules on it.
--
-- GRAIN. One row per (trial_id, campaign_id, setting) per recording; c33 reads the latest by recorded_at.
-- setting keys:
--   SP_PLACEMENT|<placement>                          = percentage, fivetran-hl campaign_placement_bidding
--   SB_PLACEMENT|<placement>                          = percentage, sb_campaign_bid_adjustments_by_placement
--   SB_SHOPPER_COHORT|<audience_id>|<cohort type>     = percentage, sb_campaign_bid_adjustments_shopper_cohort
--   SB_TARGET|<id>|bid  and  SB_TARGET|<id>|state     = bid / state, sb_product_target
-- value: the value as read. NULL means ABSENT; only a later re-baseline row may carry it, when Ori rules that
-- a setting is gone. The founding rows record no absent setting.
-- source / source_synced_at: the Fivetran table read and its MAX(_fivetran_synced) at the read.
-- ruling: NULL on the founding rows; a later row carries Ori's words.
--
-- WHAT IS PRESENT (the presence rule, §2.7 kind 4): a source row counts only when its _fivetran_synced is
-- within 1 hour of its own table's MAX(_fivetran_synced) and it is not _fivetran_deleted (only
-- sb_product_target has that column). The founding insert, c33 and K12 apply the same text.
--
-- WHO WRITES IT. scripts/bigquery/migrations/2026-10-05_holdout_t2_baseline.sql writes the founding rows
-- once, for the watched set only (the live trial's HOLDOUT units whose assignment_rule starts 'FOUNDING');
-- after that, only an appended re-baseline row carrying Ori's ruling. A LATE ARRIVAL control gets no row and
-- is unwatched on these settings.
--
-- APPEND-ONLY. Never UPDATE, DELETE, MERGE ... WHEN MATCHED or CREATE OR REPLACE TABLE. A second founding
-- row for a key would read as a re-baselined setting (c33 AMBER), so the founding insert refuses to run twice.
-- =============================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_HOLDOUT_BASELINE` (
  trial_id          STRING    NOT NULL,  -- = DE_HOLDOUT_ASSIGNMENT.trial_id
  campaign_id       STRING    NOT NULL,  -- = DE_HOLDOUT_ASSIGNMENT.unit_id (unit_type CAMPAIGN)
  setting           STRING    NOT NULL,  -- the key, see above
  recorded_at       TIMESTAMP NOT NULL,
  value             STRING,              -- as read; NULL = absent (a re-baseline row only)
  source            STRING,              -- the fivetran-hl.amazon_ads table read
  source_synced_at  TIMESTAMP,           -- that table's MAX(_fivetran_synced) at the read
  ruling            STRING               -- NULL on the founding rows; Ori's words on a re-baseline row
)
OPTIONS (description = 'Holdout baseline, append-only: each founding control\'s value at the assignment of the settings no source can date (placement and shopper-cohort bid adjustments, SB product targets), present settings only (re-stamped by the table\'s latest sync, not deleted). value NULL = absent (re-baseline rows only). Never UPDATE or DELETE. Read by V_ENGINE_HEALTH c33 (BASELINE_DIFF). Spec: architecture/HOLDOUT.md §6; plan docs/superpowers/plans/2026-10-03-holdout-restart.md.');
