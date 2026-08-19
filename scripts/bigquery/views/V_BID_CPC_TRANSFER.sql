-- =============================================================================
-- V_BID_CPC_TRANSFER   —  SHADOW.  NOTHING READS THIS.
-- Built 2026-08-11.  Corrects the pooled bid->CPC curve of 2026-08-10.
--
-- THE MODEL
--   realised_CPC = k_seg * bid^gamma * M_campaign          (forward)
--   bid          = (target_cpc / (k_seg * M_campaign))^(1/gamma)   (inverse)
--
--   M_campaign = SUM over placements of  click_share_p * I_p * (1 + adj_p/100)^beta
--
-- WHAT CHANGED vs the 2026-08-10 form  CPC = k_seg * bid^0.686
--   The old k_seg was a per-(channel x target_kind) constant that silently blended
--   the AUCTION with each campaign's PLACEMENT SETTINGS.  Placement is a lookup,
--   not a fit.  M is that lookup, exposed per campaign in this view.  k_seg is
--   re-levelled net of M (k_pure below) so the two are not double-counted.
--
-- PARAMETERS, and how each was measured
--   gamma = 0.778  95% CI [0.638, 0.872]
--       Within-TARGET fixed-effects WLS of log(cpc) on log(bid), 2,799 target-days
--       / 270 targets / 93 campaigns / 24,828 clicks, Jun-Aug 2026, weight = clicks,
--       CI = campaign-cluster bootstrap (2,000 reps).  Bids are the EXACT old_bid/
--       new_bid pairs OI itself posted (V_PPC_CHANGE_LOG_APPLIED), carried forward
--       to the next posted change — never V_TARGET_DAILY.keyword_bid and never the
--       Fivetran SCD2 mirrors (see KNOWN DEFECTS).  0.686 lies inside this CI, so
--       there is no contradiction; the higher point estimate is what errors-in-
--       variables predicts once the bid is measured without noise.
--
--   beta  = 0.725  95% CI [0.550, 0.908]   CONTESTED auctions
--   beta  = 0.0                            BRAND-DEFENSE auctions
--       Pass-through of a NOMINAL placement uplift into REALISED CPC at that
--       placement.  Within-campaign WLS of log(cpc_p / cpc_OTHER) on log(1+adj/100)
--       with placement-specific intercepts, 127 campaign-placements (39 dosed),
--       weight = harmonic-mean clicks of the two arms, 6,000-rep bootstrap.
--       'Other on-Amazon' is the control: SP exposes NO adjustment lever for it.
--       Estimated separately per placement it reproduces itself — TOS 0.658, detail
--       page 0.668 — which is the main reason to believe it.
--
--       THE BRAND-DEFENSE SPLIT IS LOad-BEARING, NOT A COSMETIC EXCLUSION.
--       On brand terms you own the auction, so a second-price multiplier never
--       binds.  Four campaigns across both channels sit at +500% and every one of
--       them realises a premium of 0.85-1.48 where beta=0.725 predicts 4.2x.
--       Applying a single beta to the whole account makes this model WORSE than
--       having no placement term at all (held-out RMSE +8.2%); applying beta=0 to
--       brand defense makes it BETTER (-8.5%).  Do not "simplify" this away.
--       (n=1 brand-defense campaign clears the >=10-click-both-arms bar, so the
--       coefficient itself is weakly identified; the FALSIFICATION of beta=0.725
--       on that population is what is strong, not the estimate of 0.)
--
--   I_p  intrinsic premium of placement p vs 'Other on-Amazon', measured on
--        UN-adjusted campaigns only:
--          Top of Search 1.162 | Detail Page 0.939 | Other 1.000 | Off Amazon 0.418
--        Detail page is intrinsically CHEAPER than rest-of-search.  Any detail-page
--        uplift is paying a premium for inventory that was available below base rate.
--
--   k_pure by channel x target_kind, gamma pinned at 0.778, fitted on log(cpc)-log(M):
--          SP KEYWORD 0.9286 | SP AUTO 0.8505 | SP PRODUCT 0.8415 | SB PRODUCT 0.7759
--          SB KEYWORD -> falls back to the all-segment 0.8665 (too thin to fit)
--
-- EVIDENCE THAT M IS A REAL KNOWN INPUT AND NOT A STORY
--   * cross-campaign: log(cpc / bid^gamma) regressed on log(M) has slope +0.951,
--     95% CI [+0.462, +1.380] over 64 campaigns / 24,226 clicks.  A correctly
--     specified known input has slope 1.  It excludes 0.
--   * leave-one-CAMPAIGN-out held-out RMSE of log(cpc): 0.3066 -> 0.2805 (-8.5%),
--     and the gain is monotone in the dose: -5.4% at M<1.05, -7.5% at 1.05-1.15,
--     -17.1% at M>=1.15.  That monotonicity is the signature you want.
--
-- HOW MUCH OF THE 0.686 EXPONENT WAS REALLY PLACEMENT:  +0.007 of exponent and
--   3.9 percentage points of within-R2.  Essentially none, and it pushes the
--   exponent UP, not down.  It could not have been much: the adjustment is a
--   campaign-level constant and 0.686 came from a within-target design, so the
--   only route in is MIX SHIFT — and mix does not move with the bid (log(M_mix)
--   on log(bid) with target FE: slope +0.0005, R2 0.00000).  What the old k was
--   wrong about is the LEVEL, and only for the ~7% of spend that carries a real
--   uplift: M ranges 0.96 to 2.7 across campaigns while the account mean is 1.034.
--
-- KNOWN DEFECTS — read before trusting a LEVEL (gamma and M are ratio designs and
-- do not depend on these):
--  1. NO ADJUSTMENT HISTORY EXISTS.  campaign_placement_bidding and
--     sb_campaign_bid_adjustments_by_placement carry ONE row per campaign+placement.
--     _fivetran_synced is "last time the API returned this record", not "when the
--     value was set".  M is a CURRENT snapshot applied to a historical window and
--     that is provably wrong for at least the four *-SP/PT (Product Defense)
--     campaigns, whose +300% detail-page setting switched on in June 2026 (detail-
--     page impression share 0.00-0.07 -> 0.47-0.91 in one month).  RE-READ THIS
--     VIEW BEFORE EVERY RUN; it can change under you with no audit trail.
--  2. THE ARITHMETIC BOUND STILL FAILS.  On dynamic-bids-DOWN-ONLY campaigns a
--     second-price auction cannot charge more than bid x M.  Using the exact bids
--     OI posted, 31-43% of down-only clicks violate it in every target kind
--     (AUTO 32.7%, KEYWORD 43.0%, PRODUCT 31.2%).  So either some posted bids never
--     took effect, or DIM_CAMPAIGN.bidding_strategy is stale, or there is a
--     multiplier nobody has found.  Until that is closed, treat k_pure as
--     provisional and gamma/M as the trustworthy parts.
--  3. SB shopper-cohort multipliers (up to +150%, on the largest SB campaigns)
--     compound with the placement lever and their EXPOSURE SHARE is in no report,
--     so they cannot enter M.  sb_cohort_max_pct is carried here as a warning flag:
--     a non-null value means M is an UNDER-estimate for that campaign.
--  4. SITE_AMAZON_BUSINESS is a SITE adjustment, not a placement.  Its clicks sit
--     inside the four placement rows and cannot be separated.  Carried as a flag,
--     NOT netted out.
--  5. Population: the fit rests on targets the coach actually touched between
--     2026-06-14 and 2026-08-09.  Untouched targets are unrepresented.
--
-- LABEL MAP (the join that silently returned zero rows for months):
--   campaign_id is STRING in campaign_placement_bidding and both sb_* adjustment
--   tables, INT64 in campaign_placement_report.  CAST or you get nothing, quietly.
--   PLACEMENT_TOP -> 'Top of Search on-Amazon' · PLACEMENT_PRODUCT_PAGE ->
--   'Detail Page on-Amazon' · SITE_AMAZON_BUSINESS -> no report row.
--   'Other on-Amazon' and 'Off Amazon' have NO adjustment lever at all — that is
--   what makes 'Other' a valid within-campaign control.
--   A missing SP row genuinely means 0% (Amazon omits defaults; the minimum stored
--   SP percentage is +1).  A missing SB row means the API did not return the
--   campaign — SB stores explicit 0 and negative rows.  Not the same thing.
-- =============================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BID_CPC_TRANSFER` AS
WITH params AS (
  SELECT 0.778 AS gamma, 0.638 AS gamma_lo, 0.872 AS gamma_hi,
         0.725 AS beta,  0.550 AS beta_lo,  0.908 AS beta_hi,
         0.0   AS beta_brand_defense
),
win AS (
  SELECT DATE_SUB(MAX(date), INTERVAL  14 DAY) AS d_end,
         DATE_SUB(MAX(date), INTERVAL 103 DAY) AS d_start
  FROM `fivetran-hl`.amazon_ads.campaign_placement_report
),
-- intrinsic premium of each placement, measured on un-adjusted campaigns
intrinsic AS (
  SELECT * FROM UNNEST([
    STRUCT('TOP_OF_SEARCH' AS placement, 1.162 AS i_p),
    STRUCT('DETAIL_PAGE',   0.939),
    STRUCT('OTHER',         1.000),
    STRUCT('OFF_AMAZON',    0.418),
    STRUCT('HOMEPAGE',      1.000)   -- SB only, no un-adjusted control exists
  ])
),
-- k_pure: gamma pinned at 0.778, level fitted on log(cpc) - log(M)
kseg AS (
  SELECT * FROM UNNEST([
    STRUCT('SP' AS channel, 'KEYWORD' AS target_kind, 0.9286 AS k_pure, 0.9347 AS k_pooled_old, 7007 AS fit_clicks),
    STRUCT('SP', 'AUTO',    0.8505, 0.8638, 13297),
    STRUCT('SP', 'PRODUCT', 0.8415, 0.9649,  3222),
    STRUCT('SB', 'PRODUCT', 0.7759, 0.8571,  1302),
    STRUCT('SB', 'KEYWORD', 0.8665, 0.8665,     0)   -- fallback: all-segment level
  ])
),
-- current adjustment snapshot, latest row per campaign+placement, both channels
adj AS (
  SELECT campaign_id, channel, placement, adjustment_pct, adj_last_seen FROM (
    SELECT CAST(campaign_id AS STRING) AS campaign_id, 'SP' AS channel,
           CASE placement WHEN 'PLACEMENT_TOP'          THEN 'TOP_OF_SEARCH'
                          WHEN 'PLACEMENT_PRODUCT_PAGE' THEN 'DETAIL_PAGE'
                          WHEN 'SITE_AMAZON_BUSINESS'   THEN 'AMAZON_BUSINESS'
                          ELSE placement END AS placement,
           percentage AS adjustment_pct, DATE(_fivetran_synced) AS adj_last_seen,
           ROW_NUMBER() OVER (PARTITION BY campaign_id, placement ORDER BY _fivetran_synced DESC) AS rn
    FROM `fivetran-hl`.amazon_ads.campaign_placement_bidding
    UNION ALL
    SELECT CAST(campaign_id AS STRING), 'SB',
           CASE placement WHEN 'HOME' THEN 'HOMEPAGE' ELSE placement END,
           percentage, DATE(_fivetran_synced),
           ROW_NUMBER() OVER (PARTITION BY campaign_id, placement ORDER BY _fivetran_synced DESC)
    FROM `fivetran-hl`.amazon_ads.sb_campaign_bid_adjustments_by_placement
  ) WHERE rn = 1
),
amazon_business AS (
  SELECT campaign_id, adjustment_pct AS ab_pct FROM adj WHERE placement = 'AMAZON_BUSINESS'
),
cohort AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, MAX(percentage) AS sb_cohort_max_pct
  FROM `fivetran-hl`.amazon_ads.sb_campaign_bid_adjustments_shopper_cohort
  GROUP BY 1
),
-- realised placement mix over the settled window
rpt AS (
  SELECT CAST(r.campaign_id AS STRING) AS campaign_id, 'SP' AS channel,
         CASE r.placement WHEN 'Top of Search on-Amazon' THEN 'TOP_OF_SEARCH'
                          WHEN 'Detail Page on-Amazon'   THEN 'DETAIL_PAGE'
                          WHEN 'Other on-Amazon'         THEN 'OTHER'
                          WHEN 'Off Amazon'              THEN 'OFF_AMAZON'
                          ELSE UPPER(REPLACE(r.placement,' ','_')) END AS placement,
         SUM(r.clicks) AS clicks, SUM(r.cost) AS cost
  FROM `fivetran-hl`.amazon_ads.campaign_placement_report r, win
  WHERE r.date BETWEEN win.d_start AND win.d_end
  GROUP BY 1,2,3
  UNION ALL
  SELECT CAST(s.campaign_id AS STRING), 'SB',
         CASE s.placement WHEN 'Top of Search on-Amazon' THEN 'TOP_OF_SEARCH'
                          WHEN 'Detail Page on-Amazon'   THEN 'DETAIL_PAGE'
                          WHEN 'Other on-Amazon'         THEN 'OTHER'
                          WHEN 'Homepage on-Amazon'      THEN 'HOMEPAGE'
                          ELSE UPPER(REPLACE(s.placement,' ','_')) END,
         SUM(s.clicks), SUM(s.cost)
  FROM `fivetran-hl`.amazon_ads.sb_placement_report s, win
  WHERE s.report_date BETWEEN win.d_start AND win.d_end
  GROUP BY 1,2,3
),
camp AS (
  SELECT dc.campaign_id, dc.campaign_name, dc.campaign_type AS channel, dc.campaign_state,
         dc.daily_budget, dc.bidding_strategy,
         REGEXP_CONTAINS(UPPER(dc.campaign_name), r'BRAND DEFENSE') AS is_brand_defense
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
),
-- per campaign x placement: the audit trail behind M
leg AS (
  SELECT r.campaign_id, r.channel, r.placement, r.clicks, r.cost,
         a.adjustment_pct, a.adj_last_seen, i.i_p,
         c.is_brand_defense,
         IF(c.is_brand_defense, p.beta_brand_defense, p.beta)    AS beta_used,
         IF(c.is_brand_defense, p.beta_brand_defense, p.beta_lo) AS beta_used_lo,
         IF(c.is_brand_defense, p.beta_brand_defense, p.beta_hi) AS beta_used_hi
  FROM rpt r
  CROSS JOIN params p
  LEFT JOIN adj a ON a.campaign_id=r.campaign_id AND a.channel=r.channel AND a.placement=r.placement
  LEFT JOIN intrinsic i ON i.placement = r.placement
  LEFT JOIN camp c ON c.campaign_id = r.campaign_id
),
m AS (
  SELECT campaign_id, channel,
         SUM(clicks) AS window_clicks, SUM(cost) AS window_cost,
         SAFE_DIVIDE(SUM(cost), NULLIF(SUM(clicks),0)) AS measured_cpc,
         -- THE MULTIPLIER
         SAFE_DIVIDE(SUM(clicks * COALESCE(i_p,1.0)
                       * POWER(1 + GREATEST(COALESCE(adjustment_pct,0),0)/100.0, beta_used)),
                     NULLIF(SUM(clicks),0)) AS m_effective,
         SAFE_DIVIDE(SUM(clicks * COALESCE(i_p,1.0)
                       * POWER(1 + GREATEST(COALESCE(adjustment_pct,0),0)/100.0, beta_used_lo)),
                     NULLIF(SUM(clicks),0)) AS m_effective_lo,
         SAFE_DIVIDE(SUM(clicks * COALESCE(i_p,1.0)
                       * POWER(1 + GREATEST(COALESCE(adjustment_pct,0),0)/100.0, beta_used_hi)),
                     NULLIF(SUM(clicks),0)) AS m_effective_hi,
         -- what a naive full-pass-through model would have applied
         SAFE_DIVIDE(SUM(clicks * (1 + GREATEST(COALESCE(adjustment_pct,0),0)/100.0)),
                     NULLIF(SUM(clicks),0)) AS m_nominal,
         -- mix alone, adjustments zeroed: what the campaign would carry from placement mix
         SAFE_DIVIDE(SUM(clicks * COALESCE(i_p,1.0)), NULLIF(SUM(clicks),0)) AS m_mix_only,
         -- audit trail, per placement
         SUM(IF(placement='TOP_OF_SEARCH', clicks,0)) AS clicks_tos,
         SUM(IF(placement='DETAIL_PAGE',   clicks,0)) AS clicks_detail_page,
         SUM(IF(placement='OTHER',         clicks,0)) AS clicks_other,
         SUM(IF(placement='OFF_AMAZON',    clicks,0)) AS clicks_off_amazon,
         SUM(IF(placement='HOMEPAGE',      clicks,0)) AS clicks_homepage,
         MAX(IF(placement='TOP_OF_SEARCH', adjustment_pct, NULL)) AS adj_tos_pct,
         MAX(IF(placement='DETAIL_PAGE',   adjustment_pct, NULL)) AS adj_detail_page_pct,
         MAX(IF(placement='OTHER',         adjustment_pct, NULL)) AS adj_other_pct_sb,
         MAX(IF(placement='HOMEPAGE',      adjustment_pct, NULL)) AS adj_homepage_pct_sb,
         MAX(adj_last_seen) AS adjustment_last_seen,
         LOGICAL_OR(COALESCE(adjustment_pct,0) > 0) AS has_any_uplift,
         MAX(beta_used) AS beta_used
  FROM leg GROUP BY 1,2
)
SELECT
  m.campaign_id,
  c.campaign_name,
  m.channel,
  c.campaign_state,
  c.bidding_strategy,
  c.daily_budget,
  c.is_brand_defense,
  -- ── THE OUTPUT THE MODEL CONSUMES ────────────────────────────────────────
  ROUND(m.m_effective, 5)     AS m_effective,      -- multiply k_pure by this
  ROUND(m.m_effective_lo, 5)  AS m_effective_lo,   -- beta = 0.550
  ROUND(m.m_effective_hi, 5)  AS m_effective_hi,   -- beta = 0.908
  p.gamma, p.gamma_lo, p.gamma_hi,
  m.beta_used                 AS beta_used,
  -- ── THE INPUTS, so a human can audit any row ─────────────────────────────
  ROUND(m.m_nominal, 5)       AS m_nominal_naive,  -- what full pass-through would say
  ROUND(m.m_mix_only, 5)      AS m_mix_only,       -- placement mix with adjustments zeroed
  CAST(m.adj_tos_pct         AS INT64) AS adj_tos_pct,
  CAST(m.adj_detail_page_pct AS INT64) AS adj_detail_page_pct,
  CAST(m.adj_other_pct_sb    AS INT64) AS adj_other_pct_sb,
  CAST(m.adj_homepage_pct_sb AS INT64) AS adj_homepage_pct_sb,
  CAST(ab.ab_pct AS INT64)    AS adj_amazon_business_pct,   -- NOT in M; site, not placement
  CAST(co.sb_cohort_max_pct AS INT64) AS sb_cohort_max_pct, -- NOT in M; M is an under-estimate when set
  m.adjustment_last_seen,
  m.clicks_tos, m.clicks_detail_page, m.clicks_other, m.clicks_off_amazon, m.clicks_homepage,
  m.window_clicks, ROUND(m.window_cost,2) AS window_cost,
  ROUND(SAFE_DIVIDE(m.clicks_tos,         NULLIF(m.window_clicks,0)),4) AS share_tos,
  ROUND(SAFE_DIVIDE(m.clicks_detail_page, NULLIF(m.window_clicks,0)),4) AS share_detail_page,
  ROUND(SAFE_DIVIDE(m.clicks_other,       NULLIF(m.window_clicks,0)),4) AS share_other,
  ROUND(SAFE_DIVIDE(m.clicks_off_amazon,  NULLIF(m.window_clicks,0)),4) AS share_off_amazon,
  ROUND(m.measured_cpc, 4)    AS measured_cpc_window,
  -- ── WORKED VALUES, one per target kind, so the row is checkable by eye ────
  k.target_kind,
  k.k_pure,
  k.k_pooled_old,                                    -- the 2026-08-10 constant
  k.fit_clicks                AS k_fit_clicks,
  ROUND(k.k_pure * m.m_effective, 5)                          AS k_effective,
  ROUND(k.k_pure * m.m_effective * POWER(1.00, p.gamma), 4)   AS expected_cpc_at_bid_1_00,
  ROUND(POWER(SAFE_DIVIDE(0.50, NULLIF(k.k_pure * m.m_effective,0)), 1.0/p.gamma), 4)
                                                              AS bid_for_target_cpc_0_50,
  -- how far the old pooled form was off for THIS campaign, at a $1.00 bid
  ROUND(SAFE_DIVIDE(k.k_pure * m.m_effective, NULLIF(k.k_pooled_old,0)), 4) AS ratio_new_over_old,
  m.has_any_uplift,
  (SELECT d_start FROM win) AS window_start,
  (SELECT d_end   FROM win) AS window_end
FROM m
CROSS JOIN params p
JOIN camp c ON c.campaign_id = m.campaign_id
JOIN kseg k ON k.channel = m.channel
LEFT JOIN amazon_business ab ON ab.campaign_id = m.campaign_id
LEFT JOIN cohort co ON co.campaign_id = m.campaign_id AND m.channel = 'SB'
WHERE m.window_clicks > 0
