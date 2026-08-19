-- FN_TARGET_BID_SHADOW(anchor DATE, apply_season_gate BOOL)
-- =============================================================================
-- THE TARGET-BID MODEL, as a table function so the SAME arithmetic can be
-- evaluated at any historical anchor. V_TARGET_BID_SHADOW is a thin wrapper that
-- calls it at today's settled anchor; the backtest calls it at 2026-04-12 /
-- 2026-05-12 / 2026-06-11. There is no second implementation to drift.
--
-- SHADOW. Nothing reads this. It writes nothing, suggests nothing and is not
-- wired into V_ADS_COACH, V_OOB_KEYWORD, V_KEYWORD_LIFT or the bulksheet
-- generator. v27.40 shipped a target-CPC bid model straight into the engine and
-- was reverted the same day (267 rows / $2,457 per week of harm). This one gets
-- proven first.
--
-- ── WHAT IT COMPUTES ─────────────────────────────────────────────────────────
--   cvr_hat          hierarchical empirical-Bayes conversion rate
--                    account -> family -> campaign -> keyword, k = [300, 2500, 1000] clicks
--   gp_per_order     MEASURED family constant, SUM(GROSS_PROFIT)/SUM(Ads_orders), 90 settled days
--   breakeven_cpc    gp_per_order x cvr_hat        (GP-ROAS = breakeven_cpc / actual_cpc)
--   target_cpc       breakeven_cpc / TARGET_GP_ROAS
--   target_bid       (target_cpc / k_transfer) ^ (1 / gamma)      <- THE UNITS FIX
--                    then clamped by floor / $2 cap / safe ceiling / season gate
--
-- target_cpc and target_bid are DIFFERENT NUMBERS and are published as separate
-- columns with unmistakable names. Assigning target_cpc to a bid field is
-- exactly root cause (a) of the v27.40 revert: realized CPC ran ~1.26x the stated
-- bid, so "bid := target_cpc" systematically overpaid.
--
-- ── WHERE EVERY CONSTANT COMES FROM ──────────────────────────────────────────
-- cvr-structure study (2026-08-11), out-of-sample on 7 rolling monthly folds:
--   * CVR pools at FAMILY then CAMPAIGN. Campaign type (SP/SB), target type
--     (keyword/product/auto) and match type do NOT predict a held-out keyword's
--     CVR (leave-one-campaign-out: 0.6% / 3.8% / 2.3%, all CIs spanning zero) and
--     two of them make the model WORSE as standing levels. They are absent here
--     on purpose.
--   * k = [300 family, 2500 campaign, 1000 keyword] clicks. Flat ridge: any
--     k_keyword 600-1800 and k_campaign 1200-5000 scores within 0.25 pt.
--   * Estimates are stored as a RATIO to the account CVR level and multiplied by
--     the freshest level (cvr_ratio_to_account x cvr_account_level below). A
--     stale level is worth more damage than any segmentation choice: the 2026-01
--     fold goes NEGATIVE (worse than a flat global mean) on a Q4-fitted level.
--   * Cold start (campaign with zero fit-window clicks): family x target_kind is
--     the entry prior, not family alone (+7.97 pt leave-one-campaign-out). It is
--     an ENTRY prior only -- as a standing level target_kind costs -0.77 pt.
--
-- margin-structure study (2026-08-11):
--   * gp_per_order is a FAMILY constant. Channel R2_oos 0.027, target type 0.011.
--     No channel / ad_format / target-type / season / ASIN / campaign term.
--   * MEASURE it from FACT_AMAZON_ADS.GROSS_PROFIT, never compute it from
--     DIM_PRODUCT.listing_price_amount (stale on Bottle/Bunny/LolliBall) and never
--     from list_price - cost (misses cross-sell, which is +60%/-12% by family).
--   * 90 days, not 365: a trailing-365d margin window is +9.0% biased high, i.e. a
--     9% overbid on every keyword.
--   * FAMILY IS KEYED OFF V_DIM_CAMPAIGN_FAMILY, NOT ASIN_BY_CAMPAIGN_NAME.
--     SP_FACT_AMAZON_ADS.sql's ASIN_BY_CAMPAIGN_NAME CASE has no Bunny/LolliBall
--     branch and its terminal ELSE files them all as White Lollibox -- 16.5% of
--     current non-defense spend priced at $21.36/order when the truth is $5.36-5.92.
--     Correcting the label was worth +36% relative OOS R2, 6.7x more than the best
--     alternative segmentation. This view routes around the defect; the defect
--     itself still needs fixing at source.
--
-- bid-to-cpc study (2026-08-11):
--   * realized_CPC = k x bid^0.686. NOT a multiplier. gamma = 0.686 (95% CI
--     0.59-0.78) from 384 within-target bid changes; the out-of-sample gamma sweep
--     independently minimises at 0.6-0.8 and ranks gamma=1 worst of all tested.
--   * The 1.425 that v27.40 consumed is an artifact of the targeting report's
--     restamped keyword_bid (M5). Re-derived from true SCD2 bids: SP 1.26, SB 1.04.
--   * k by channel x target_type and NO FINER. On held-out targets the exponent is
--     worth 24%; all segmentation beyond it is worth <=7%, channel-alone is worse
--     than a single global k, and SB ad_format actively hurts.
--
-- ── SETTLE (M3) ──────────────────────────────────────────────────────────────
-- `anchor` must be a date whose orders are SETTLED. V_SRC_AmazonAds_SearchTerms
-- maps SP Ads_orders from purchases_30_d and SB from attributed_conversions_14_d,
-- so the binding constraint is SP at D-30, not the D+7 usually quoted.
-- V_TARGET_BID_SHADOW supplies MAX(FACT date) - 30.
--
-- ── WHAT IS DELIBERATELY NOT HERE ────────────────────────────────────────────
--   * Defense campaigns (M7). Strategic, never priced by this model.
--   * Any LY / year-over-year term. Ads data starts 2024-09-05 and keyword-grain
--     data starts 2025-10-28, so most keywords' LY window is their launch ramp.
--     The reverted v27.40 rule was LY-based and was the worst performer measured.
--   * Budget. This model prices a click; it does not allocate a campaign budget.
--     V_OOB_BUDGET_PHASE remains the sole budget authority.
--
-- Dependencies: FACT_AMAZON_ADS, V_DIM_CAMPAIGN_FAMILY, V_CAMPAIGN_ROLE,
--               DIM_KEYWORD, DIM_AD_GROUP, V_KEYWORD_CONTEXT_GATE
-- SOP: architecture/TARGET_BID_SHADOW.md
-- Project: onyga-482313 / Dataset: OI
-- =============================================================================

CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_TARGET_BID_SHADOW`(
  anchor DATE, apply_season_gate BOOL
) AS (

WITH p AS (
  SELECT
    -- CVR shrinkage, in CLICKS (cvr-structure study, out-of-sample optimum)
    300.0  AS k_family,
    2500.0 AS k_campaign,
    1000.0 AS k_keyword,
    -- bid -> CPC transfer exponent, and the click elasticity (bid-to-cpc study)
    0.686  AS gamma,
    1.706  AS eta_clicks,
    -- ══ THE TARGET GP-ROAS IS DERIVED, NOT CHOSEN ══
    -- Pricing to BREAKEVEN is a zero-net-profit objective: GP-ROAS = 1.0 means
    -- gross profit exactly equals ad spend. The profit-maximising bid sets the
    -- MARGINAL click to breakeven, not the average one. With clicks(b) = C.b^eta
    -- and cpc(b) = k.b^gamma:
    --      d(GP)/db = d(spend)/db  =>  theta.eta.GP = (eta+gamma).spend
    --   =>  target GP-ROAS = (eta + gamma) / (theta . eta)
    -- theta is the value of a marginal click relative to the average click.
    -- theta = 1.0 (marginal click as good as average) gives 1.402, i.e.
    -- target_cpc = 0.713 x breakeven_cpc. theta = 0.70 gives 2.003, i.e. 0.499x.
    -- That 0.499-0.713 range REPRODUCES the independently measured 0.49-0.70x
    -- safe bid band from first principles, which is why theta = 1.0 is used here:
    -- it is the conservative end of the derived range in bid terms, and the band
    -- corroborates it. Backtest: architecture/TARGET_BID_SHADOW.md.
    (1.706 + 0.686) / (1.0 * 1.706) AS target_gp_roas,   -- = 1.4021
    -- Safety clamp: bid may not exceed this fraction of breakeven CPC.
    -- Measured safe band is 0.49-0.70x; the loose end is used so the clamp is a
    -- backstop and not the model. `binding_clamp` reports when it actually binds.
    0.70   AS safe_ceiling_frac,
    2.00   AS bid_cap,
    -- A family needs this many settled orders in 90d to price its own margin.
    60     AS family_min_orders,
    -- HOLD band: a repricing smaller than this in absolute AND relative terms is
    -- not worth an upload row.
    0.02   AS hold_abs,
    0.05   AS hold_pct
),

-- ── M7: defense is excluded entirely, by role AND by name (so historical rows
-- whose role has not been recomputed are still caught) ───────────────────────
defense AS (
  SELECT DISTINCT c.campaign_id
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_FAMILY` c
  LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_ROLE` r ON r.campaign_id = c.campaign_id
  WHERE COALESCE(r.strategy_category, '') IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
     OR LOWER(COALESCE(c.campaign_name, '')) LIKE '%defense%'
),

-- CORRECTED family label. NOT DIM_PRODUCT via ASIN_BY_CAMPAIGN_NAME.
fam AS (
  SELECT campaign_id, campaign_name, campaign_state, parent_name, family_source
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_FAMILY`
  WHERE parent_name IS NOT NULL
),

-- MIN() not ANY_VALUE(): an ad group with two is_current rows must resolve the same way
-- on every run or the view is not byte-reproducible.
agfmt AS (
  SELECT ad_group_id, MIN(creative_type) AS creative_type,
         MIN(campaign_type) AS campaign_type
  FROM `onyga-482313.OI.DIM_AD_GROUP` WHERE is_current GROUP BY 1
),

-- ad-group default bid AS OF the anchor (the bid a target with no own bid runs at)
agbid AS (
  SELECT ad_group_id, default_bid
  FROM `onyga-482313.OI.DIM_AD_GROUP`
  WHERE effective_from <= DATETIME(anchor, TIME '23:59:59')
    AND COALESCE(effective_to, DATETIME '9999-12-31') > DATETIME(anchor, TIME '23:59:59')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ad_group_id ORDER BY effective_from DESC) = 1
),

-- ── 90 settled days ending at the anchor. One scan feeds the CVR hierarchy, the
-- 28-day account level and the family margin constant. ───────────────────────
raw AS (
  SELECT
    a.date, a.campaign_id, a.ad_group_id, a.keyword_id,
    a.campaign_type AS channel,
    CASE UPPER(COALESCE(a.targeting_type, ''))
      WHEN 'AUTOMATIC'     THEN 'AUTO'
      WHEN 'ASIN'          THEN 'PRODUCT'
      WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
      WHEN 'CATEGORY'      THEN 'PRODUCT'
      WHEN 'EXACT'         THEN 'KEYWORD'
      WHEN 'PHRASE'        THEN 'KEYWORD'
      WHEN 'BROAD'         THEN 'KEYWORD'
      ELSE 'UNKNOWN' END AS target_kind,
    a.source_table,
    a.Ads_clicks AS clicks, a.Ads_orders AS orders,
    a.Ads_cost AS cost, a.GROSS_PROFIT AS gp,
    a.date > DATE_SUB(anchor, INTERVAL 28 DAY) AS in_level
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.date <= anchor AND a.date > DATE_SUB(anchor, INTERVAL 90 DAY)
),

b AS (
  SELECT r.*, f.parent_name AS family
  FROM raw r
  JOIN fam f ON f.campaign_id = r.campaign_id
  WHERE r.campaign_id NOT IN (SELECT campaign_id FROM defense)
),

-- Account level. p_fit is the 90d base the hierarchy is expressed as a ratio to;
-- p_level is the freshest 28d level the ratio is multiplied back by.
acct AS (
  SELECT
    SAFE_DIVIDE(SUM(orders), SUM(clicks))                                             AS p_fit,
    SAFE_DIVIDE(SUM(IF(in_level, orders, 0)), NULLIF(SUM(IF(in_level, clicks, 0)), 0)) AS p_level,
    SUM(clicks)                     AS acct_clicks_90d,
    SUM(IF(in_level, clicks, 0))    AS acct_clicks_28d,
    SAFE_DIVIDE(SUM(gp), NULLIF(SUM(orders), 0)) AS gp_acct
  FROM b
),

famagg AS (SELECT family, SUM(clicks) clk, SUM(orders) ord, SUM(gp) gp FROM b GROUP BY 1),
famtk  AS (SELECT family, target_kind, SUM(clicks) clk, SUM(orders) ord FROM b GROUP BY 1, 2),
-- campaign level includes sb_target_report rows: they carry a real campaign_id and
-- their clicks are real evidence about the campaign, they just have no keyword grain.
campagg AS (SELECT campaign_id, SUM(clicks) clk, SUM(orders) ord FROM b GROUP BY 1),
-- keyword level excludes them (keyword_id = -1 is a placeholder for 12 SB campaigns)
kwagg AS (
  SELECT campaign_id, ad_group_id, keyword_id,
         SUM(clicks) clk, SUM(orders) ord, SUM(cost) cost, SUM(gp) gp,
         ARRAY_AGG(target_kind ORDER BY clicks DESC, target_kind LIMIT 1)[OFFSET(0)] AS target_kind_obs,
         ARRAY_AGG(channel     ORDER BY clicks DESC, channel     LIMIT 1)[OFFSET(0)] AS channel_obs
  FROM b
  WHERE source_table <> 'sb_target_report' AND keyword_id <> '-1'
  GROUP BY 1, 2, 3
),

-- ── MARGIN: measured family constant, account fallback for thin families ─────
gpfam AS (
  SELECT f.family,
         IF(f.ord >= (SELECT family_min_orders FROM p), SAFE_DIVIDE(f.gp, f.ord), a.gp_acct) AS gp_per_order,
         f.ord < (SELECT family_min_orders FROM p) AS gp_is_account_fallback,
         f.ord AS family_orders_90d
  FROM famagg f CROSS JOIN acct a
),

-- ── POPULATION: config targets as of the anchor, plus anything that took a click
-- in the fit window but is missing from config ──────────────────────────────
cfg AS (
  SELECT keyword_id AS target_id, campaign_id, ad_group_id,
         keyword_text AS target_text, UPPER(match_type) AS mt_raw,
         bid AS own_bid, UPPER(state) AS target_state
  FROM `onyga-482313.OI.DIM_KEYWORD`
  WHERE effective_from <= DATETIME(anchor, TIME '23:59:59')
    AND COALESCE(effective_to, DATETIME '9999-12-31') > DATETIME(anchor, TIME '23:59:59')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY effective_from DESC) = 1
),
uni AS (
  SELECT target_id, campaign_id, ad_group_id, target_text, mt_raw, own_bid, target_state,
         TRUE AS in_config
  FROM cfg
  UNION ALL
  SELECT k.keyword_id, k.campaign_id, k.ad_group_id,
         CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS FLOAT64), CAST(NULL AS STRING),
         FALSE
  FROM kwagg k
  WHERE k.keyword_id NOT IN (SELECT target_id FROM cfg)
),

-- ── ASSEMBLY ─────────────────────────────────────────────────────────────────
asm AS (
  SELECT
    u.target_id, u.campaign_id, u.ad_group_id, u.target_text, u.target_state, u.in_config,
    f.campaign_name, f.campaign_state, f.parent_name AS family, f.family_source,
    COALESCE(kw.channel_obs, ag.campaign_type)   AS channel,
    COALESCE(kw.target_kind_obs,
      CASE u.mt_raw
        WHEN 'AUTOMATIC'     THEN 'AUTO'
        WHEN 'ASIN'          THEN 'PRODUCT'
        WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
        WHEN 'CATEGORY'      THEN 'PRODUCT'
        ELSE 'KEYWORD' END)                      AS target_kind,
    u.mt_raw                                     AS match_type,
    IF(COALESCE(kw.channel_obs, ag.campaign_type) = 'SB', ag.creative_type, NULL) AS sb_ad_format,
    COALESCE(u.own_bid, ab.default_bid)          AS bid_now,
    u.own_bid IS NULL                            AS bid_from_ad_group_default,
    COALESCE(kw.clk, 0)  AS kw_clicks_90d,
    COALESCE(kw.ord, 0)  AS kw_orders_90d,
    COALESCE(kw.cost, 0) AS kw_cost_90d,
    COALESCE(kw.gp, 0)   AS kw_gp_90d,
    COALESCE(ca.clk, 0)  AS camp_clicks_90d,
    COALESCE(ca.ord, 0)  AS camp_orders_90d,
    COALESCE(fa.clk, 0)  AS fam_clicks_90d,
    COALESCE(fa.ord, 0)  AS fam_orders_90d,
    COALESCE(ft.clk, 0)  AS famtk_clicks_90d,
    COALESCE(ft.ord, 0)  AS famtk_orders_90d,
    gf.gp_per_order, gf.gp_is_account_fallback, gf.family_orders_90d,
    ac.p_fit, ac.p_level, ac.acct_clicks_90d, ac.acct_clicks_28d
  FROM uni u
  JOIN fam f ON f.campaign_id = u.campaign_id
  CROSS JOIN acct ac
  LEFT JOIN kwagg   kw ON kw.campaign_id = u.campaign_id AND kw.ad_group_id = u.ad_group_id
                      AND kw.keyword_id  = u.target_id
  LEFT JOIN campagg ca ON ca.campaign_id = u.campaign_id
  LEFT JOIN famagg  fa ON fa.family      = f.parent_name
  LEFT JOIN gpfam   gf ON gf.family      = f.parent_name
  LEFT JOIN agfmt   ag ON ag.ad_group_id = u.ad_group_id
  LEFT JOIN agbid   ab ON ab.ad_group_id = u.ad_group_id
  LEFT JOIN famtk   ft ON ft.family      = f.parent_name
                      AND ft.target_kind = COALESCE(kw.target_kind_obs,
                            CASE u.mt_raw
                              WHEN 'AUTOMATIC'     THEN 'AUTO'
                              WHEN 'ASIN'          THEN 'PRODUCT'
                              WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
                              WHEN 'CATEGORY'      THEN 'PRODUCT'
                              ELSE 'KEYWORD' END)
  WHERE u.campaign_id NOT IN (SELECT campaign_id FROM defense)
),

-- ── THE CVR HIERARCHY. Each level is the child's own evidence shrunk toward its
-- parent by k clicks: p_child = (orders + k x p_parent) / (clicks + k). ──────
h AS (
  SELECT a.*,
    SAFE_DIVIDE(a.fam_orders_90d + pp.k_family * a.p_fit, a.fam_clicks_90d + pp.k_family) AS p_fam,
    SAFE_DIVIDE(a.famtk_orders_90d + pp.k_family *
      SAFE_DIVIDE(a.fam_orders_90d + pp.k_family * a.p_fit, a.fam_clicks_90d + pp.k_family),
      a.famtk_clicks_90d + pp.k_family) AS p_famtk,
    pp.k_family, pp.k_campaign, pp.k_keyword, pp.gamma, pp.target_gp_roas,
    pp.safe_ceiling_frac, pp.bid_cap, pp.hold_abs, pp.hold_pct
  FROM asm a CROSS JOIN p pp
),
h2 AS (
  SELECT h.*,
    -- COLD START: a campaign with no fit-window clicks enters on family x target_kind.
    -- Once it has clicks it falls back to family (target_kind as a standing level costs -0.77 pt).
    IF(h.camp_clicks_90d = 0, h.p_famtk, h.p_fam) AS p_prior_camp
  FROM h
),
h3 AS (
  SELECT h2.*,
    SAFE_DIVIDE(h2.camp_orders_90d + h2.k_campaign * h2.p_prior_camp,
                h2.camp_clicks_90d + h2.k_campaign) AS p_camp
  FROM h2
),
h4 AS (
  SELECT h3.*,
    SAFE_DIVIDE(h3.kw_orders_90d + h3.k_keyword * h3.p_camp,
                h3.kw_clicks_90d + h3.k_keyword) AS p_kw
  FROM h3
),

-- ── ECONOMICS ────────────────────────────────────────────────────────────────
econ AS (
  SELECT h4.*,
    -- stored as a ratio to the fit-window account level, then re-levelled on the
    -- freshest 28d level. Never store an absolute CVR.
    SAFE_DIVIDE(h4.p_kw, h4.p_fit)                       AS cvr_ratio_to_account,
    SAFE_DIVIDE(h4.p_kw, h4.p_fit) * h4.p_level          AS cvr_hat,
    -- evidence weights, for a human auditing the row
    SAFE_DIVIDE(h4.kw_clicks_90d, h4.kw_clicks_90d + h4.k_keyword) AS w_own,
    CASE WHEN h4.channel = 'SP' AND COALESCE(h4.target_kind, '') = 'KEYWORD' THEN 1.093
         WHEN h4.channel = 'SP' AND COALESCE(h4.target_kind, '') = 'AUTO'    THEN 0.994
         WHEN h4.channel = 'SP' AND COALESCE(h4.target_kind, '') = 'PRODUCT' THEN 1.031
         WHEN h4.channel = 'SB' AND COALESCE(h4.target_kind, '') = 'KEYWORD' THEN 0.786
         ELSE 0.928 END                                  AS k_transfer,
    -- per-format bid floors, empirically proven via real uploads. An unknown SB
    -- format takes the video floor: too low is a rejected row, too high is only money.
    CASE WHEN h4.channel = 'SB' AND h4.sb_ad_format IN ('PRODUCT_COLLECTION', 'STORE_SPOTLIGHT') THEN 0.10
         WHEN h4.channel = 'SB'                                                                  THEN 0.25
         ELSE 0.20 END                                   AS bid_floor
  FROM h4
),
priced AS (
  SELECT e.*,
    e.gp_per_order * e.cvr_hat                                       AS breakeven_cpc,
    SAFE_DIVIDE(e.gp_per_order * e.cvr_hat, e.target_gp_roas)        AS target_cpc_raw,
    e.safe_ceiling_frac * e.gp_per_order * e.cvr_hat                 AS bid_cap_safe
  FROM econ e
),
bid AS (
  SELECT pr.*,
    -- ══ THE UNITS FIX ══ invert realized_CPC = k x bid^gamma.
    POWER(SAFE_DIVIDE(pr.target_cpc_raw, pr.k_transfer), 1.0 / pr.gamma) AS target_bid_raw
  FROM priced pr
),

-- ── SEASON GATE. The per-occurrence keyword ledger: BLOCK_CUT protects a keyword
-- that has already earned inside this occurrence; ENTRY_BLOCK caps a keyword whose
-- prior same-season occurrence lost. NOTE: V_KEYWORD_CONTEXT_GATE is CURRENT state
-- (no anchor parameter), so apply_season_gate=FALSE for any historical evaluation
-- or the backtest leaks the future. ─────────────────────────────────────────
gate AS (
  SELECT LOWER(TRIM(keyword_text)) AS kw,
         MIN(gate_action)               AS gate_action,   -- BLOCK_CUT < ENTRY_BLOCK: protection wins, deterministically
         MIN(probe_cap)                 AS probe_cap,
         MIN(remaining_allowance)       AS remaining_allowance
  FROM `onyga-482313.OI.V_KEYWORD_CONTEXT_GATE`
  WHERE gate_action IN ('BLOCK_CUT', 'ENTRY_BLOCK')
  GROUP BY 1
),

clamped AS (
  SELECT b.*,
    g.gate_action AS season_gate_action,
    g.probe_cap   AS season_probe_cap,
    g.remaining_allowance AS season_remaining_allowance,
    LEAST(b.bid_cap, b.bid_cap_safe) AS ceiling_eff,
    -- season gate applied to the model bid BEFORE the hard clamps
    CASE
      WHEN NOT apply_season_gate OR g.gate_action IS NULL THEN b.target_bid_raw
      WHEN g.gate_action = 'BLOCK_CUT'   THEN GREATEST(b.target_bid_raw, COALESCE(b.bid_now, 0))
      WHEN g.gate_action = 'ENTRY_BLOCK' THEN LEAST(b.target_bid_raw, COALESCE(g.probe_cap, b.target_bid_raw))
      ELSE b.target_bid_raw END AS bid_after_gate
  FROM bid b
  LEFT JOIN gate g ON g.kw = LOWER(TRIM(b.target_text))
),

final AS (
  SELECT c.*,
    ROUND(LEAST(GREATEST(c.bid_after_gate, c.bid_floor), GREATEST(c.ceiling_eff, c.bid_floor)), 2) AS target_bid,
    -- which constraint actually decided the number
    CASE
      WHEN c.bid_cap_safe < c.bid_floor                       THEN 'BELOW_FLOOR'
      WHEN c.bid_after_gate < c.bid_floor                     THEN 'FLOOR'
      WHEN c.bid_after_gate > c.ceiling_eff
           AND c.bid_cap_safe <= c.bid_cap                    THEN 'SAFE_CEILING'
      WHEN c.bid_after_gate > c.ceiling_eff                   THEN 'CAP_2USD'
      WHEN apply_season_gate AND c.season_gate_action IS NOT NULL
           AND ABS(c.bid_after_gate - c.target_bid_raw) > 0.005 THEN CONCAT('SEASON_', c.season_gate_action)
      ELSE 'NONE' END AS binding_clamp
  FROM clamped c
)

SELECT
  anchor                                   AS anchor_date,
  target_id, campaign_id, ad_group_id,
  campaign_name, campaign_state, family, family_source,
  channel, target_kind, match_type, sb_ad_format, target_text, target_state, in_config,
  campaign_state = 'ENABLED' AND COALESCE(target_state, 'ENABLED') = 'ENABLED' AS is_live,

  -- ── OUTPUTS. target_cpc and target_bid are different numbers. ──
  ROUND(target_cpc_raw, 4)                 AS target_cpc,
  target_bid,
  ROUND(bid_now, 2)                        AS bid_now,
  bid_from_ad_group_default,
  ROUND(target_bid - bid_now, 2)           AS bid_delta,
  ROUND(SAFE_DIVIDE(target_bid, NULLIF(bid_now, 0)) - 1, 4) AS bid_delta_pct,
  CASE
    WHEN bid_now IS NULL THEN 'NO_CURRENT_BID'
    WHEN binding_clamp = 'BELOW_FLOOR' THEN 'PARK_UNPRICEABLE'
    WHEN ABS(target_bid - bid_now) < hold_abs
      OR ABS(SAFE_DIVIDE(target_bid, NULLIF(bid_now, 0)) - 1) < hold_pct THEN 'HOLD'
    WHEN target_bid > bid_now THEN 'RAISE'
    ELSE 'CUT' END                         AS bid_action,
  binding_clamp,
  -- what the transfer function says this bid will actually cost per click
  ROUND(k_transfer * POWER(target_bid, gamma), 4) AS expected_cpc_at_target_bid,

  -- ── INPUTS, so any row can be audited by hand ──
  ROUND(cvr_hat, 5)                        AS cvr_hat,
  ROUND(cvr_ratio_to_account, 4)           AS cvr_ratio_to_account,
  ROUND(p_level, 5)                        AS cvr_account_level_28d,
  ROUND(p_fit, 5)                          AS cvr_account_base_90d,
  ROUND(p_fam, 5)                          AS cvr_family,
  ROUND(p_camp, 5)                         AS cvr_campaign,
  ROUND(SAFE_DIVIDE(kw_orders_90d, NULLIF(kw_clicks_90d, 0)), 5) AS cvr_own_raw,
  camp_clicks_90d = 0                      AS is_cold_start,
  ROUND(gp_per_order, 2)                   AS gp_per_order,
  gp_is_account_fallback, family_orders_90d,
  ROUND(breakeven_cpc, 4)                  AS breakeven_cpc,
  ROUND(bid_cap_safe, 4)                   AS bid_cap_safe,
  ROUND(bid_floor, 2)                      AS bid_floor,
  ROUND(target_gp_roas,4) AS target_gp_roas, k_transfer, gamma,

  -- ── EVIDENCE WEIGHTS: how much of cvr_hat is the target's own data ──
  ROUND(w_own, 4)                                                                        AS w_own,
  ROUND((1 - w_own) * SAFE_DIVIDE(camp_clicks_90d, camp_clicks_90d + k_campaign), 4)      AS w_campaign,
  ROUND((1 - w_own) * (1 - SAFE_DIVIDE(camp_clicks_90d, camp_clicks_90d + k_campaign))
        * SAFE_DIVIDE(fam_clicks_90d, fam_clicks_90d + k_family), 4)                      AS w_family,
  ROUND(1 - w_own
        - (1 - w_own) * SAFE_DIVIDE(camp_clicks_90d, camp_clicks_90d + k_campaign)
        - (1 - w_own) * (1 - SAFE_DIVIDE(camp_clicks_90d, camp_clicks_90d + k_campaign))
          * SAFE_DIVIDE(fam_clicks_90d, fam_clicks_90d + k_family), 4)                    AS w_account,

  kw_clicks_90d, kw_orders_90d,
  ROUND(kw_cost_90d, 2)                    AS kw_cost_90d,
  ROUND(kw_gp_90d, 2)                      AS kw_gp_90d,
  ROUND(SAFE_DIVIDE(kw_gp_90d, NULLIF(kw_cost_90d, 0)), 3) AS kw_gp_roas_90d,
  ROUND(SAFE_DIVIDE(kw_cost_90d, NULLIF(kw_clicks_90d, 0)), 4) AS kw_cpc_90d,
  camp_clicks_90d, fam_clicks_90d, acct_clicks_90d, acct_clicks_28d,
  season_gate_action, season_probe_cap, season_remaining_allowance
FROM final
);
