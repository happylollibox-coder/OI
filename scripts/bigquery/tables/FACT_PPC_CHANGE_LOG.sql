-- =============================================
-- FACT_PPC_CHANGE_LOG — Applied PPC changes (close the loop)
-- =============================================
-- Append-only log of every PPC change marked "Uploaded to Amazon"
-- on the DO page. One row per change item; a batch upload shares
-- one batch_id. Carries a snapshot of the coach metrics at decision
-- time so each change is explainable and scoreable later.
--
-- Writer:  Flask POST /api/ppc-change-log (data-entry-app/app.py)
-- Reader:  V_PPC_ACTION_OUTCOMES (pre/post window outcome scoring)
-- SOP:     architecture/PPC_CLOSE_THE_LOOP.md
--
-- applied_at is a UTC TIMESTAMP; downstream views derive the LA-local
-- change date via DATE(applied_at, 'America/Los_Angeles').
-- Append-only: CREATE TABLE IF NOT EXISTS — never CREATE OR REPLACE.
-- =============================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
(
  change_id STRING NOT NULL,           -- chg_<uuid12>, minted server-side
  batch_id STRING NOT NULL,            -- groups items from a single upload
  applied_at TIMESTAMP NOT NULL,       -- when the user marked the batch uploaded (UTC)

  -- What changed
  action STRING NOT NULL,              -- NEGATE_TERM, REDUCE_BID, INCREASE_BID, PROMOTE_TO_EXACT, ...
  search_term STRING,                  -- shopper search term (term-level actions)
  targeting STRING,                    -- keyword/target text (target-level actions)
  keyword_id STRING,                   -- Amazon keyword / product-targeting ID
  match_type STRING,                   -- EXACT / PHRASE / BROAD / PRODUCT_TARGETING
  campaign_id STRING,
  campaign_name STRING,
  campaign_type STRING,                -- SPONSORED_PRODUCTS / SPONSORED_BRANDS / ...
  ad_group_id STRING,
  product STRING,                      -- ASIN or product short name from the DO queue

  -- Old → new values (bid / budget actions)
  old_bid FLOAT64,
  new_bid FLOAT64,
  old_budget FLOAT64,
  new_budget FLOAT64,

  -- Coach metric snapshot at decision time
  target_spend_8w FLOAT64,
  target_orders_8w INT64,
  target_net_roas_8w FLOAT64,
  coach_mode STRING,                   -- GUARDIAN / COOLDOWN / BLITZ / DEFAULT

  source STRING NOT NULL               -- 'COACH' | 'MANUAL'
)
PARTITION BY DATE(applied_at)
OPTIONS (
  description = 'Append-only log of applied PPC changes from the DO page, with coach decision snapshot. See architecture/PPC_CLOSE_THE_LOOP.md'
);
