-- V_CAMPAIGN_FAMILY_MAP — the single family attribution for every ENABLED campaign.
--
-- Coverage guarantee for the budget waterfall (Ori 2026-07-05): no enabled campaign can fall
-- outside the budget. Reused by V_FAMILY_NET_PROFIT_7D / _BUDGET_ALLOCATION / _CAMPAIGN_BUDGET_BASE
-- / _DAILY_MOVE so the whole waterfall shares one attribution.
--
-- PRECEDENCE, highest first. Each arm only ever fills what the arm above it left empty.
--   1. the explicit override in DE_CAMPAIGN_FAMILY — a human said so, and a human must always be
--      able to correct a name or an ASIN that would mislead;
--   2. the dominant advertised ASIN over the learning window — the campaign told us what it sells;
--   3. the campaign-name prefix, learned (see below) — the campaign told us nothing, but its
--      siblings did;
--   4. 'Unknown' — the honest answer. It is still a real value and downstream code depends on it:
--      a whole-store campaign that spans several families genuinely has no single family, and
--      V_BOOK_ASSIGNMENT deliberately refuses it so the two-book system never gains a family that
--      has no product P&L. Do not remove the sentinel because the bucket happens to be empty.
--
-- WHY ARM 3 EXISTS. Sponsored Brands video campaigns carry no advertised ASIN — the creative does
-- not name a product — so arm 2 cannot see them and they used to land on 'Unknown'. A campaign with
-- no family has no bar, so it was invisible to the per-family profitability judgement, to the
-- two-book P&L and to every family-level coach decision, while still spending money.
--
-- HOW ARM 3 LEARNS (mechanism, not a stored table — nothing here is hand-maintained).
-- Every campaign in this account is named with its family as the leading word. So: take the leading
-- unbroken run of letters of the name, uppercased, as its prefix — this absorbs every separator
-- style in the account because the run simply stops at the first non-letter. Then let every
-- campaign that SPENT inside the learning window teach, in any state, using whatever family arms 1
-- and 2 already gave it confidently. A prefix stamps a family only if BOTH guards pass:
--   · every teacher behind that prefix agrees on one family, and
--   · at least min_campaigns_behind_a_prefix teachers stand behind it.
-- A prefix that fails either guard teaches nothing and its campaigns stay 'Unknown' — which is
-- exactly the behaviour that preceded this arm. The rule can therefore withhold a right family; it
-- cannot invent a wrong one unless the ASIN path is itself wrong across a whole family's naming
-- convention, in which case the family bar is already wrong for far more than these campaigns.
--
-- WHAT IT CANNOT DO, so nobody expects it to. It cannot learn a prefix that is a channel, a colour
-- or a programme label rather than a family — those are either contested or too small, by design.
-- It cannot produce the virtual whole-store family at all, because no prefix votes for it
-- unanimously. And a brand-new family teaches nothing on day one, because it has no teachers yet.
-- All of those keep needing a DE_CAMPAIGN_FAMILY row. This arm is a fallback for the ASIN-blind
-- campaigns of an ESTABLISHED family, not a replacement for human judgement.
--
-- LEARNING FROM A NAME IS A DELIBERATE EXCEPTION, and it is worth naming. V_DIM_CAMPAIGN_FAMILY
-- carries a standing instruction not to parse campaign names downstream, because id-keyed rollups
-- survive a rename and name-keyed ones do not. That instruction still holds everywhere else. The
-- exception is confined here, to the LAST arm before a sentinel that the canonical view does not
-- have, and its price is real: rename a campaign's leading word and its family moves on the next
-- refresh, with no spend history to anchor it and no log entry. Prefer an override when that
-- matters.
--
-- INSPECT WHAT THE RULE LEARNED — run this to see the vote behind every prefix, which fired and
-- which was refused, on any day. No measurement from it is written into this file, on purpose.
--   WITH spent AS (SELECT DISTINCT campaign_id FROM `onyga-482313.OI.FACT_AMAZON_ADS`
--                  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND Ads_cost > 0),
--   latest AS (SELECT campaign_id, campaign_name FROM `onyga-482313.OI.DIM_CAMPAIGN`
--              QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC)=1),
--   asin_fam AS (SELECT campaign_id, parent_name FROM (
--       SELECT a.campaign_id, p.parent_name, ROW_NUMBER() OVER (PARTITION BY a.campaign_id
--              ORDER BY SUM(a.Ads_cost) DESC, p.parent_name) rn
--       FROM `onyga-482313.OI.FACT_AMAZON_ADS` a JOIN `onyga-482313.OI.DIM_PRODUCT` p
--         ON p.asin = COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME)
--       WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) GROUP BY 1,2) WHERE rn=1)
--   SELECT UPPER(REGEXP_EXTRACT(TRIM(l.campaign_name), r'^([A-Za-z]+)')) AS prefix,
--          COALESCE(o.parent_name, af.parent_name) AS family, COUNT(*) n
--   FROM latest l JOIN spent s USING (campaign_id)
--   LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_FAMILY` o USING (campaign_id)
--   LEFT JOIN asin_fam af USING (campaign_id)
--   GROUP BY 1,2 ORDER BY 1,3 DESC;
--
-- THE HAND-WRITTEN ROWS TAGGED 'mapping_inference_2026-08%' IN DE_CAMPAIGN_FAMILY ARE NOW
-- BELT-AND-BRACES. They were written by hand to rescue the ASIN-blind video campaigns before this
-- arm existed. Arm 3 was tested with those rows held out of BOTH the override arm and the learning
-- corpus and it reproduced every one of them independently, contradicting none and assigning no
-- campaign the human had not. They are kept because an override is a correct, explicit audit trail
-- and overrides are meant to win; deleting them would be safe and would simply hand those campaigns
-- to the rule. Nothing else depends on them.
--
-- resolution_source says in plain words which arm answered for each campaign, so a family can be
-- audited without re-deriving it. A wrong family is exactly the kind of error that otherwise hides.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` AS
WITH k AS (
  SELECT
    -- Unanimity alone is not enough: a prefix can agree with itself merely by being small, and a
    -- single mis-resolved campaign must never be able to carry a prefix on its own. This is set
    -- above the largest unanimous non-family token the account has produced and well below the
    -- smallest family that actually needs the rule; re-derive both from the query in the header
    -- before moving it.
    5  AS min_campaigns_behind_a_prefix,
    -- The same window the advertised-ASIN arm already reads, so this arm adds no new source and no
    -- new ordering dependency to the daily refresh. It also means a campaign keeps teaching for a
    -- season after its last spend, so pausing siblings does not quietly disarm a prefix.
    90 AS learning_window_days
),
latest AS (
  SELECT campaign_id, campaign_name, state
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC) = 1
),
enabled AS (
  SELECT campaign_id, campaign_name FROM latest WHERE state = 'ENABLED'
),
asin_fam AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      -- parent_name breaks the tie so two families with identical spend cannot coin-flip between
      -- refreshes.
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC, p.parent_name) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p
      ON p.asin = COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME)
    WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL (SELECT learning_window_days FROM k) DAY)
    GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
-- The learning corpus: every campaign that spent inside the window, any state. Any state on
-- purpose — if only enabled campaigns could teach, pausing a family's siblings would silently drop
-- its prefix below the minimum and send its ASIN-blind campaigns back to 'Unknown', which is a
-- genuinely surprising coupling.
spent AS (
  SELECT DISTINCT campaign_id
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL (SELECT learning_window_days FROM k) DAY)
    AND Ads_cost > 0
),
-- One teacher per spending campaign: its prefix, and the family the two confident arms gave it.
-- A campaign those arms could not resolve teaches nothing rather than teaching 'Unknown'.
-- A name that does not begin with a letter has no prefix, so it neither teaches nor is taught.
teacher AS (
  SELECT
    UPPER(REGEXP_EXTRACT(TRIM(l.campaign_name), r'^([A-Za-z]+)')) AS prefix,
    COALESCE(cf.parent_name, af.parent_name) AS parent_name
  FROM latest l
  JOIN spent s ON s.campaign_id = l.campaign_id
  LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_FAMILY` cf ON cf.campaign_id = l.campaign_id
  LEFT JOIN asin_fam af ON af.campaign_id = l.campaign_id
),
prefix_vote AS (
  SELECT prefix, parent_name, COUNT(*) AS n
  FROM teacher
  WHERE prefix IS NOT NULL AND parent_name IS NOT NULL
  GROUP BY prefix, parent_name
),
-- A prefix stamps a family only when its teachers are unanimous and numerous enough. Anything
-- contested or thin is refused outright and its campaigns keep the sentinel.
prefix_map AS (
  SELECT prefix, parent_name FROM (
    SELECT prefix, parent_name,
      SUM(n)   OVER (PARTITION BY prefix) AS campaigns_behind_prefix,
      COUNT(*) OVER (PARTITION BY prefix) AS families_behind_prefix
    FROM prefix_vote
  )
  WHERE families_behind_prefix = 1
    AND campaigns_behind_prefix >= (SELECT min_campaigns_behind_a_prefix FROM k)
)
SELECT
  e.campaign_id,
  COALESCE(cf.parent_name, af.parent_name, pm.parent_name, 'Unknown') AS parent_name,
  CASE
    WHEN cf.parent_name IS NOT NULL THEN 'set by hand'
    WHEN af.parent_name IS NOT NULL THEN 'the product it advertises'
    WHEN pm.parent_name IS NOT NULL THEN 'the name it was given'
    ELSE 'nothing here says which family it belongs to'
  END AS resolution_source
FROM enabled e
LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_FAMILY` cf ON cf.campaign_id = e.campaign_id
LEFT JOIN asin_fam af ON af.campaign_id = e.campaign_id
LEFT JOIN prefix_map pm
  ON pm.prefix = UPPER(REGEXP_EXTRACT(TRIM(e.campaign_name), r'^([A-Za-z]+)'));
