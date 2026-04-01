# OI Experiment System - Tutorial & Operations Guide

## Table of Contents

0. [Daily Protocol (Start Here)](#0-daily-protocol)
1. [How to Add a New Experiment](#1-how-to-add-a-new-experiment)
2. [How to Manage Existing Experiments](#2-how-to-manage-existing-experiments)
3. [How to Manage Campaigns](#3-how-to-manage-campaigns)
4. [View Reference](#4-view-reference)
5. [Join Keys Reference](#5-join-keys-reference)
6. [Strategy Templates](#6-strategy-templates) (incl. Campaign Structure & Strategy Playbooks)
7. [Search Term Segmentation](#7-search-term-segmentation)
8. [Placement & Ad Format Analysis](#8-placement--ad-format-analysis)
9. [Net ROAS & Profitability](#9-net-roas--profitability)
10. [Budget Health Monitoring](#10-budget-health-monitoring)
10b. [Search Term Recommendations + Hero ASIN](#10b-search-term-recommendations-per-term-signals--hero-asin)
11. [ASIN Conclusions (Learning System)](#11-asin-conclusions-learning-system)
12. [Seasonal Budget Behavior](#12-seasonal-budget-behavior)
13. [Known Gaps and Limitations](#13-known-gaps-and-limitations)

---

## 0. Daily Protocol

Your daily and weekly workflow to increase net ROAS and profit.

**System goal**: increase each parent family's net profit by advertising the right child ASIN on the right search terms.

**How it works**: the system explains every recommendation in plain English (the `reason` column). Read it, verify it makes sense, act on it. Over time you'll trust the numbers.

---

### DAILY (2-3 minutes)

#### 1.1 Data health check

**1.1a: Experiment data status** -- per experiment, per ASIN, per data source: what's fresh and what's missing?

Three data sources feed each experiment. If any is stale, that tier's metrics are outdated:
- **Ads** (Fivetran, auto-daily) -- feeds Tier 2 (ad ROAS)
- **SQP** (manual weekly upload) -- feeds Tier 3 (organic), hero scores
- **Business Reports** (Fivetran, auto-daily) -- feeds Tier 0-1 (family, ASIN)

```sql
WITH exp AS (
  SELECT e.experiment_id, e.strategy_id, e.start_date,
    DATE_DIFF(CURRENT_DATE(), e.start_date, DAY) as days_running
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  WHERE e.status = 'ACTIVE'
),
exp_asins AS (
  SELECT DISTINCT ec.experiment_id, fa.advertised_asins as asin
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN exp ON ec.experiment_id = exp.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON fa.advertised_asins = p.asin
  WHERE fa.advertised_asins IS NOT NULL
),
ads_freshness AS (
  SELECT ec.experiment_id,
    MAX(fa.date) as ads_latest_date,
    COUNT(DISTINCT fa.date) as ads_days_with_data
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN exp ON ec.experiment_id = exp.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id AND fa.date >= exp.start_date
  GROUP BY 1
),
sqp_freshness AS (
  SELECT fsq.ASIN as asin,
    MAX(fsq.week_end_date) as sqp_latest_week
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
  GROUP BY 1
),
br_freshness AS (
  SELECT fp.PURCHASED_ASIN as asin,
    MAX(fp.DATE) as br_latest_date
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fp
  GROUP BY 1
)
SELECT
  e.experiment_id,
  e.strategy_id,
  e.days_running,
  p.product_short_name,
  ea.asin,
  -- Ads data (experiment-level)
  af.ads_latest_date,
  DATE_DIFF(CURRENT_DATE(), af.ads_latest_date, DAY) as ads_days_stale,
  CASE
    WHEN af.ads_latest_date IS NULL THEN 'NO_ADS_DATA'
    WHEN DATE_DIFF(CURRENT_DATE(), af.ads_latest_date, DAY) <= 3 THEN 'OK'
    ELSE 'STALE'
  END as ads_status,
  -- SQP data (per ASIN)
  sf.sqp_latest_week,
  DATE_DIFF(CURRENT_DATE(), sf.sqp_latest_week, DAY) as sqp_days_stale,
  CASE
    WHEN sf.sqp_latest_week IS NULL THEN 'NO_SQP_DATA'
    WHEN DATE_DIFF(CURRENT_DATE(), sf.sqp_latest_week, DAY) <= 14 THEN 'OK'
    WHEN DATE_DIFF(CURRENT_DATE(), sf.sqp_latest_week, DAY) <= 21 THEN 'STALE'
    ELSE 'VERY_STALE'
  END as sqp_status,
  -- Business Reports (per ASIN)
  bf.br_latest_date,
  CASE
    WHEN bf.br_latest_date IS NULL THEN 'NO_BR_DATA'
    WHEN DATE_DIFF(CURRENT_DATE(), bf.br_latest_date, DAY) <= 3 THEN 'OK'
    ELSE 'STALE'
  END as br_status
FROM exp e
LEFT JOIN exp_asins ea ON e.experiment_id = ea.experiment_id
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON ea.asin = p.asin
LEFT JOIN ads_freshness af ON e.experiment_id = af.experiment_id
LEFT JOIN sqp_freshness sf ON ea.asin = sf.asin
LEFT JOIN br_freshness bf ON ea.asin = bf.asin
ORDER BY
  CASE WHEN af.ads_latest_date IS NULL THEN 0 ELSE 1 END,
  e.days_running DESC, e.experiment_id, p.product_short_name;
```

**How to read results:**

| Status | What it means | What to do |
|--------|---------------|------------|
| `ads_status = 'NO_ADS_DATA'` | Campaign not active or wrong campaign_id | Check Amazon Ads console + `DIM_EXPERIMENT_CAMPAIGN` mapping |
| `ads_status = 'STALE'` | Fivetran sync delayed | Check Fivetran dashboard |
| `sqp_status = 'STALE'` / `'VERY_STALE'` | SQP report not uploaded for this ASIN | Upload the latest SQP weekly report. Hero scores are outdated. |
| `sqp_status = 'NO_SQP_DATA'` | No SQP data at all for this ASIN | Upload SQP report. Tier 3 and hero ranking unavailable. |
| `br_status = 'NO_BR_DATA'` / `'STALE'` | Business Reports not syncing | Check Fivetran. Tier 0-1 metrics are outdated. |
| `product_short_name = NULL` | ASIN not in DIM_PRODUCT or campaign_id mapping wrong | Fix the mapping in `DIM_EXPERIMENT_CAMPAIGN` |

**1.1b: SQP freshness per ASIN** -- quick check even for ASINs not in experiments.

```sql
SELECT
  p.product_short_name,
  fsq.ASIN,
  MAX(fsq.week_end_date) as latest_sqp_week,
  DATE_DIFF(CURRENT_DATE(), MAX(fsq.week_end_date), DAY) as days_stale,
  CASE
    WHEN DATE_DIFF(CURRENT_DATE(), MAX(fsq.week_end_date), DAY) <= 14 THEN 'OK'
    WHEN DATE_DIFF(CURRENT_DATE(), MAX(fsq.week_end_date), DAY) <= 21 THEN 'STALE'
    ELSE 'VERY_STALE'
  END as sqp_status
FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
JOIN `onyga-482313.OI.DIM_PRODUCT` p ON fsq.ASIN = p.asin
WHERE fsq.data_source = 'SQP'
GROUP BY 1, 2
ORDER BY latest_sqp_week ASC;
```

If any ASIN shows `STALE` or `VERY_STALE`, upload the latest SQP report for that ASIN.

**1.1c: Missing search term segmentation** -- new terms without classification.

```sql
SELECT COUNT(*) as unsegmented_terms
FROM (
  SELECT DISTINCT LOWER(query_text) as search_term, ASIN
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY`
  WHERE data_source = 'SQP'
    AND week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 56 DAY)
) sqp
LEFT JOIN `onyga-482313.OI.V_SEARCH_TERM_SEGMENT` seg
  ON sqp.search_term = seg.search_term AND sqp.ASIN = seg.asin
WHERE seg.search_term IS NULL;
```

#### 1.2 Campaign momentum check (impression trends)

**Start here every day.** Uses `V_CAMPAIGN_DAILY_MOMENTUM`: two rolling comparisons per campaign, excluding partial days (before 9pm ET the current day is ignored).

- **2-day check** (last 2 full days avg vs prev 2 days avg) -- catches sudden drops quickly
- **4-day check** (last 4 full days avg vs prev 4 days avg) -- smooths noise, confirms real trends

```sql
SELECT
  campaign_name, latest_full_day,
  signal_2d, l2_avg_impr, p2_avg_impr, impr_chg_2d_pct,
  l2_spend, l2_orders, p2_spend, p2_orders,
  signal_4d, l4_avg_impr, p4_avg_impr, impr_chg_4d_pct,
  l4_spend, l4_orders, p4_spend, p4_orders
FROM `onyga-482313.OI.V_CAMPAIGN_DAILY_MOMENTUM`;
```

| Signal | Criteria | What to do |
|--------|----------|------------|
| **CRITICAL_DROP** | Impressions down >50% | Investigate immediately: check Amazon Ads for paused campaigns, bid issues, budget exhaustion, or account-level problems |
| **DROP** | Down 30-50% | Review bids and budget. Raise bid if campaign is profitable. |
| **DEAD** | 0 impressions both periods | Campaign is inactive or broken. Check Amazon Ads. |
| **STABLE** | Within ±30% | Normal. No action needed. |
| **RISING** / **SURGE** | Up 30%+ / 50%+ | Good. Check budget isn't exhausting too early in the day. |
| **NEW** | No prior-period data | New campaign ramping up. Monitor daily. |

**How to read:**
- `signal_2d = CRITICAL_DROP` but `signal_4d = STABLE` → sudden recent drop, investigate immediately (bid issue, pause, budget)
- Both `signal_2d` and `signal_4d = CRITICAL_DROP` → sustained decline, structural problem (demand shift, competition, account issue)
- `signal_2d = STABLE` but `signal_4d = DROP` → recovering from an earlier dip, monitor
- Multiple campaigns showing CRITICAL_DROP on the same day → check account-level or portfolio-level issues first

---

#### 1.3 Experiment performance (day + week-to-date comparison)

Two comparisons per experiment, anchored to the **actual latest day with data** (no NULLs from Fivetran lag):
1. **Latest day vs previous day** -- what changed overnight?
2. **Week-to-date (Sun through latest) vs same period last week** -- is this week better or worse?

```sql
WITH ue AS (
  SELECT p.asin,
    p.listing_price_amount - ch.TOTAL_COST_PER_UNIT as margin_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
),
exp_day_ranked AS (
  SELECT ec.experiment_id, fa.date,
    ROW_NUMBER() OVER (PARTITION BY ec.experiment_id ORDER BY fa.date DESC) as rn
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  WHERE e.status = 'ACTIVE'
  GROUP BY 1, 2
),
exp_anchors AS (
  SELECT experiment_id,
    MAX(CASE WHEN rn = 1 THEN date END) as latest,
    MAX(CASE WHEN rn = 2 THEN date END) as prev_day,
    DATE_TRUNC(MAX(CASE WHEN rn = 1 THEN date END), WEEK(SUNDAY)) as tw_sun,
    DATE_SUB(MAX(CASE WHEN rn = 1 THEN date END), INTERVAL 7 DAY) as lw_end,
    DATE_TRUNC(DATE_SUB(MAX(CASE WHEN rn = 1 THEN date END), INTERVAL 7 DAY), WEEK(SUNDAY)) as lw_sun
  FROM exp_day_ranked WHERE rn <= 2
  GROUP BY 1
),
exp_ads AS (
  SELECT ec.experiment_id, e.strategy_id, fa.date,
    SUM(fa.cost) as spend,
    SUM(fa.orders) as orders,
    SUM(fa.orders * ue.margin_per_unit) as gross_margin
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  LEFT JOIN ue ON fa.advertised_asins = ue.asin
  WHERE e.status = 'ACTIVE'
    AND fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 21 DAY)
  GROUP BY 1, 2, 3
)
SELECT
  ea.experiment_id,
  ea.strategy_id,
  a.latest as latest_data_date,
  -- Latest day
  ROUND(SUM(CASE WHEN ea.date = a.latest THEN ea.spend END), 2) as day_spend,
  SUM(CASE WHEN ea.date = a.latest THEN ea.orders END) as day_orders,
  ROUND(SUM(CASE WHEN ea.date = a.latest THEN ea.gross_margin - ea.spend END), 2) as day_profit,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN ea.date = a.latest THEN ea.gross_margin END),
    NULLIF(SUM(CASE WHEN ea.date = a.latest THEN ea.spend END), 0)), 2) as day_roas,
  -- Previous day with data
  ROUND(SUM(CASE WHEN ea.date = a.prev_day THEN ea.spend END), 2) as prev_spend,
  SUM(CASE WHEN ea.date = a.prev_day THEN ea.orders END) as prev_orders,
  ROUND(SUM(CASE WHEN ea.date = a.prev_day THEN ea.gross_margin - ea.spend END), 2) as prev_profit,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN ea.date = a.prev_day THEN ea.gross_margin END),
    NULLIF(SUM(CASE WHEN ea.date = a.prev_day THEN ea.spend END), 0)), 2) as prev_roas,
  -- WTD: Sunday of latest's week through latest
  ROUND(SUM(CASE WHEN ea.date >= a.tw_sun AND ea.date <= a.latest THEN ea.spend END), 2) as wtd_spend,
  SUM(CASE WHEN ea.date >= a.tw_sun AND ea.date <= a.latest THEN ea.orders END) as wtd_orders,
  ROUND(SUM(CASE WHEN ea.date >= a.tw_sun AND ea.date <= a.latest THEN ea.gross_margin - ea.spend END), 2) as wtd_profit,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN ea.date >= a.tw_sun AND ea.date <= a.latest THEN ea.gross_margin END),
    NULLIF(SUM(CASE WHEN ea.date >= a.tw_sun AND ea.date <= a.latest THEN ea.spend END), 0)), 2) as wtd_roas,
  -- Last week same period: Sunday through (latest - 7 days)
  ROUND(SUM(CASE WHEN ea.date >= a.lw_sun AND ea.date <= a.lw_end THEN ea.spend END), 2) as lw_wtd_spend,
  SUM(CASE WHEN ea.date >= a.lw_sun AND ea.date <= a.lw_end THEN ea.orders END) as lw_wtd_orders,
  ROUND(SUM(CASE WHEN ea.date >= a.lw_sun AND ea.date <= a.lw_end THEN ea.gross_margin - ea.spend END), 2) as lw_wtd_profit,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN ea.date >= a.lw_sun AND ea.date <= a.lw_end THEN ea.gross_margin END),
    NULLIF(SUM(CASE WHEN ea.date >= a.lw_sun AND ea.date <= a.lw_end THEN ea.spend END), 0)), 2) as lw_wtd_roas
FROM exp_ads ea
JOIN exp_anchors a ON ea.experiment_id = a.experiment_id
GROUP BY 1, 2, 3
ORDER BY wtd_profit DESC NULLS LAST;
```

**How to read:**
- `latest_data_date` = most recent day with actual data (handles Fivetran lag)
- `day_*` vs `prev_*` = latest day compared to the day before -- did something change overnight?
- `wtd_*` vs `lw_wtd_*` = this week (Sun through latest) vs last week (Sun through same day -7) -- apples-to-apples

| What to look for | Red flag | Action |
|---|---|---|
| `wtd_roas` < `lw_wtd_roas` by > 30% | Week significantly worse | Investigate search terms (Step 2.1.2) |
| `wtd_profit` negative + `lw_wtd_profit` also negative | Consistently losing money | Flag for weekly review, consider STOP |
| `latest_data_date` more than 3 days old | Fivetran sync issue | Check 1.1a data health |

#### 1.4 Campaign-level budget & ROAS check

Per campaign within each experiment: is it spending what it should, and is it profitable? Uses the **actual Amazon budget**.

```sql
SELECT
  vcs.experiment_id,
  vcs.campaign_name,
  vcs.campaign_budget as amazon_daily_budget,
  ROUND(SUM(fa.cost) / NULLIF(COUNT(DISTINCT fa.date), 0), 2) as actual_daily_spend,
  ROUND(
    SUM(fa.cost) / NULLIF(COUNT(DISTINCT fa.date), 0)
    / NULLIF(vcs.campaign_budget, 0) * 100
  , 1) as utilization_pct,
  COUNT(DISTINCT fa.date) as days_with_data,
  SUM(fa.orders) as total_orders,
  ROUND(SUM(fa.cost), 2) as total_spend,
  ROUND(SUM(fa.orders * ue.margin_per_unit), 2) as gross_margin,
  ROUND(SUM(fa.orders * ue.margin_per_unit) - SUM(fa.cost), 2) as net_profit,
  ROUND(SAFE_DIVIDE(SUM(fa.orders * ue.margin_per_unit), NULLIF(SUM(fa.cost), 0)), 2) as net_roas,
  CASE
    WHEN COUNT(DISTINCT fa.date) = 0 THEN 'NO_DATA'
    WHEN SUM(fa.cost) / NULLIF(COUNT(DISTINCT fa.date), 0)
         / NULLIF(vcs.campaign_budget, 0) * 100 < 30 THEN 'UNDERSPENDING'
    WHEN SUM(fa.cost) / NULLIF(COUNT(DISTINCT fa.date), 0)
         / NULLIF(vcs.campaign_budget, 0) * 100 > 120 THEN 'OVERSPENDING'
    ELSE 'OK'
  END as budget_status
FROM `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
  ON vcs.campaign_id = fa.campaign_id
  AND fa.date >= vcs.experiment_start_date
LEFT JOIN (
  SELECT p.asin,
    p.listing_price_amount - ch.TOTAL_COST_PER_UNIT as margin_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
) ue ON fa.advertised_asins = ue.asin
WHERE vcs.experiment_status = 'ACTIVE'
GROUP BY 1, 2, 3
ORDER BY
  CASE WHEN COUNT(DISTINCT fa.date) = 0 THEN 0 ELSE 1 END,
  vcs.experiment_id, net_profit ASC;
```

| Column | What to look for |
|---|---|
| `budget_status = 'NO_DATA'` | Campaign not active or campaign_id wrong |
| `budget_status = 'UNDERSPENDING'` (< 30%) | Raise bid or budget in Amazon Ads |
| `budget_status = 'OVERSPENDING'` (> 120%) | Raise budget if profitable (net_roas > 1) |
| `net_roas < 0.7` | Campaign losing money -- check search terms (Step 2.1.2) |
| `net_roas > 1.5` + `UNDERSPENDING` | Profitable but starved -- increase budget |

#### 1.5 Brand terms leaking into non-defense campaigns

Are your brand terms ("lollime", "happy lolli") appearing in **any** campaign that is NOT a BRAND_DEFENSE experiment? This includes campaigns not linked to any experiment. If so, you're paying for clicks you'd get organically -- negate them.

```sql
SELECT
  fa.campaign_name,
  COALESCE(e.experiment_id, 'NOT_IN_EXPERIMENT') as experiment_id,
  COALESCE(e.strategy_id, 'N/A') as strategy_id,
  LOWER(fa.search_term) as search_term,
  ROUND(SUM(fa.cost), 2) as spend_on_term,
  SUM(fa.orders) as orders,
  SUM(fa.clicks) as clicks
FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec ON fa.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON ec.experiment_id = e.experiment_id AND e.status = 'ACTIVE'
JOIN `onyga-482313.OI.V_SEARCH_TERM_SEGMENT` seg
  ON LOWER(fa.search_term) = seg.search_term
  AND fa.advertised_asins = seg.asin
WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND seg.experiment_segment = 'BRAND'
  AND fa.search_term IS NOT NULL
  AND COALESCE(e.strategy_id, 'NONE') NOT IN ('BRAND_DEFENSE')
GROUP BY 1, 2, 3, 4
HAVING SUM(fa.cost) > 1
ORDER BY spend_on_term DESC;
```

If any rows appear: negate these brand terms in that campaign. Either let organic handle them, or add to a BRAND_DEFENSE experiment for controlled defense spend.

---

### WEEKLY -- Monday (10-15 minutes)

#### 2.1 Optimize existing experiments

**2.1.1 Hero ASIN audit** -- are you advertising the right child on each term?

```sql
-- WRONG ASIN: terms where you're NOT advertising the hero
SELECT search_term, product_short_name as current_asin, action,
  hero_product_name as should_be, hero_sqp_cvr_pct as hero_cvr,
  ads_spend, ads_orders, reason
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
WHERE recommendation_type = 'ACTIVE_TERM'
  AND is_hero_match = FALSE
  AND hero_asin IS NOT NULL
ORDER BY ads_spend DESC;
```

If `is_hero_match = FALSE`, consider switching the ad to the hero ASIN for that term.

**2.1.2 Search term actions** -- STOP, REDUCE_BID, or PROMOTE terms.

```sql
-- Terms to STOP or REDUCE_BID (reason explains why + which ASIN to use if switching)
SELECT search_term, product_short_name, ads_spend, ads_orders,
  ads_net_roas, is_hero_match, hero_product_name, action, reason
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
WHERE action IN ('STOP', 'REDUCE_BID')
ORDER BY ads_spend DESC;
```

```sql
-- PROMOTE_TO_EXACT: proven discovery terms → create exact campaign on the hero ASIN
SELECT search_term, product_short_name as current_asin,
  hero_product_name as promote_this_asin, hero_sqp_cvr_pct,
  ads_orders, ads_net_profit, ads_net_roas, reason
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
WHERE action = 'PROMOTE_TO_EXACT'
ORDER BY ads_net_profit DESC;
```

**2.1.3 Untapped opportunities** -- organic demand with no ads running.

```sql
-- START: product_short_name already shows the hero ASIN to advertise
SELECT search_term, product_short_name as advertise_this_asin,
  hero_sqp_cvr_pct, sqp_purchases,
  strategy_id as suggested_strategy, reason
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
WHERE recommendation_type = 'OPPORTUNITY'
ORDER BY priority_score DESC
LIMIT 20;
```

**2.1.4 Placement % check** -- which placement delivers best ROAS per strategy?

```sql
SELECT
  strategy_name, ad_format, placement,
  experiment_count, total_orders, total_cost,
  ROUND(roas, 2) as roas,
  roas_rank_in_strategy
FROM `onyga-482313.OI.V_EXPERIMENT_PLACEMENT_LEARNINGS`
ORDER BY strategy_id, roas_rank_in_strategy;
```

If Top of Search consistently beats other placements, increase TOS%. If it's worse, reduce it.

**2.1.5 AUTO campaign search term review** -- negate wasteful keyword terms using cascading windows.

Uses `V_AUTO_CAMPAIGN_TERM_REVIEW`: for each keyword search term across all active AUTO campaigns, checks 30d then 60d then 90d windows. If a term reaches **50+ clicks** in any window, evaluates ROAS to decide:

```sql
-- Weekly: all terms needing action across all AUTO campaigns
SELECT
  campaign_name, search_term, targeting, action,
  threshold_window_days as window_d,
  clicks_30d, clicks_60d, clicks_90d,
  spend_90d, orders_90d, roas_90d
FROM `onyga-482313.OI.V_AUTO_CAMPAIGN_TERM_REVIEW`
WHERE action IN ('NEGATE', 'BORDERLINE', 'WATCH')
ORDER BY
  CASE action WHEN 'NEGATE' THEN 1 WHEN 'BORDERLINE' THEN 2 ELSE 3 END,
  campaign_name, clicks_90d DESC;
```

| Action | Criteria | What to do |
|---|---|---|
| **NEGATE** | 50+ clicks, ROAS < 1.0 | Add as negative exact in Amazon Ads |
| **BORDERLINE** | 50+ clicks, ROAS 1.0-3.0 | Review -- likely below margin threshold. Lean negate if < 2.5x |
| **WATCH** | 30-49 clicks, approaching threshold | Re-check next week |
| **KEEP** | 50+ clicks, ROAS 3.0+ | Profitable -- leave running. Consider PROMOTE_TO_EXACT |

**Note**: ASIN-based targets (substitutes) are excluded -- handle those via Seller Central by negating specific non-converting ASINs directly in the campaign.

| Action | What it means | What to do in Amazon Ads |
|---|---|---|
| **STOP** | Losing money, no chance of recovery | Negate the term. If `is_hero_match = FALSE`, re-target with hero ASIN. |
| **REDUCE_BID** | Slightly unprofitable, could break even | Lower the bid by ~30%. Check if hero ASIN would convert better. |
| **PROMOTE_TO_EXACT** | Profitable in broad/auto, not in exact | Create EXACT_BOOST using the `hero_asin` for this term. |
| **START** | Organic demand, no ads running | Advertise the `product_short_name` shown (already the hero). |
| **KEEP** | Making money | Do nothing. If `is_hero_match = FALSE`, consider testing hero. |
| **MONITOR** | Not enough data yet | Wait. |

#### 2.2 Close stale experiments

After 30+ days, if an experiment is clearly losing money, complete it. This triggers conclusion generation.

```sql
-- Candidates: 30+ days, losing money
SELECT experiment_id, strategy_id, days_running, data_status,
  ads_net_profit, ads_net_roas, parent_family_net_roas
FROM `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH`
WHERE days_running >= 30 AND ads_net_roas < 0.7
ORDER BY ads_net_profit ASC;
```

```sql
-- To complete an experiment:
UPDATE `onyga-482313.OI.DIM_EXPERIMENT`
SET status = 'COMPLETED', end_date = CURRENT_DATE()
WHERE experiment_id = 'THE_EXPERIMENT_ID';  -- replace
```

Then pause its campaigns in Amazon Ads.

#### 2.3 Review & approve DRAFT conclusions

Completing experiments generates DRAFT conclusions. Review and enable them so the system uses proven budgets for future suggestions.

```sql
SELECT
  asin, product_short_name, strategy_id, experiment_segment, season_context,
  ads_only_net_roas, sqp_net_roas, asin_net_roas,
  parent_name, parent_family_net_profit, parent_family_net_roas,
  total_ad_spend, total_experiment_days,
  learning_summary
FROM `onyga-482313.OI.FACT_ASIN_CONCLUSIONS`
WHERE status = 'DRAFT'
ORDER BY parent_family_net_profit DESC NULLS LAST;
```

```sql
-- Enable a conclusion (makes it permanent, feeds into future suggestions)
UPDATE `onyga-482313.OI.FACT_ASIN_CONCLUSIONS`
SET status = 'ENABLED', enabled_at = CURRENT_TIMESTAMP()
WHERE asin = 'BXXXXXXXXXX'           -- replace
  AND experiment_segment = 'SEGMENT' -- replace
  AND season_context = 'NORMAL'
  AND status = 'DRAFT';
```

#### 2.4 Check new experiment suggestions (after conclusions updated)

```sql
SELECT
  suggested_experiment_id,
  product_short_name,
  suggested_strategy_name,
  target_experiment_segment,
  ROUND(priority_score, 0) as score,
  addressable_weekly_orders as market_size,
  proven_term_count,
  reason,
  existing_experiment_id
FROM `onyga-482313.OI.V_EXPERIMENT_SUGGESTIONS`
WHERE priority_score > 300
  AND existing_experiment_id IS NULL
ORDER BY priority_score DESC
LIMIT 10;
```

If a suggestion looks good, see exact campaign setup:

```sql
SELECT
  suggested_experiment_id,
  suggested_campaign_name,
  ad_format, match_type,
  ROUND(season_adjusted_bid_max, 2) as bid,
  ROUND(season_adjusted_daily_budget, 0) as budget,
  season_adjusted_tos_pct as tos_pct,
  is_required, purpose, hist_verdict
FROM `onyga-482313.OI.V_EXPERIMENT_SUGGESTED_CAMPAIGNS`
WHERE suggested_experiment_id = 'THE_SUGGESTED_ID'  -- replace
ORDER BY campaign_seq;
```

Follow Section 1 below to launch. Create 1-2 new experiments per week maximum.

---

### Key metrics to track over time

| Metric | Where | Target | Red flag |
|--------|-------|--------|----------|
| hero_score | V_PARENT_HERO_ASIN | higher = better | 0 (no data) |
| ads_net_roas | V_EXPERIMENT_BUDGET_HEALTH | > 1.0 | < 0.7 |
| budget_utilization_pct | V_EXPERIMENT_BUDGET_HEALTH | 70-100% | < 30% (raise Amazon budgets) |
| ads_roas_trend | V_EXPERIMENT_BUDGET_HEALTH | STABLE/IMPROVING | DECLINING for 3+ weeks |
| STOP term count | V_EXPERIMENT_TERM_RECOMMENDATIONS | 0 | 5+ terms wasting money |
| SQP freshness | FACT_SEARCH_QUERY per ASIN | < 14 days | > 21 days (hero scores outdated) |

---

## 1. How to Add a New Experiment

### Step 1: Check suggestions

Before creating an experiment, check what the system recommends:

```sql
SELECT
  suggested_experiment_id,
  asin, product_short_name, suggested_strategy_name,
  target_experiment_segment, priority_score,
  addressable_weekly_orders, reason,
  suggested_campaign_type, suggested_match_type,
  suggested_bid_min, suggested_bid_max, suggested_tos_pct
FROM `onyga-482313.OI.V_EXPERIMENT_SUGGESTIONS`
WHERE priority_score > 0
ORDER BY priority_score DESC
LIMIT 20;
```

### Step 1b: See which campaigns to open

Once you have chosen a strategy from Step 1, see the exact campaigns the system recommends:

```sql
SELECT
  campaign_seq,
  ad_format,
  match_type,
  bidding_strategy,
  bid_min, bid_max,
  daily_budget,
  top_of_search_pct,
  product_page_pct,
  is_required,
  purpose,
  suggested_campaign_name,
  budget_confidence,          -- HIGH = backed by ASIN conclusions, LOW = template defaults
  margin_per_unit,            -- Selling price minus all costs (COGS + FBA + shipping)
  conclusion_net_roas,        -- Net ROAS from past experiments (if conclusions exist)
  hist_roas,
  hist_verdict,
  experiment_total_daily_budget
FROM `onyga-482313.OI.V_EXPERIMENT_SUGGESTED_CAMPAIGNS`
WHERE suggested_experiment_id = 'WHITE_LOLLIBOX_EXACT_BOOST_BIRTHDAY_KIDS'  -- From Step 1
ORDER BY campaign_seq;
```

Each row is one campaign to create in Amazon Ads Console:
- **`campaign_seq`**: Order of priority. Campaign 1 is the core driver.
- **`is_required`**: TRUE = must-have, FALSE = nice-to-have (open if budget allows).
- **`budget_confidence`**: `HIGH` means bids/budget are backed by ENABLED ASIN conclusions from past experiments. `LOW` means using template defaults (no proven data yet).
- **`margin_per_unit`**: Your profit margin per unit (selling price - all costs). Use this to understand how many units you need to sell to cover ad spend.
- **`conclusion_net_roas`**: The proven net ROAS from past experiments on this ASIN + segment. If > 1.0, past experiments were profitable.
- **`hist_roas` / `hist_verdict`**: Historical ROAS from previous experiments using this ad format + strategy. `PROVEN_STRONG` (ROAS >= 3) = high confidence, `NO_DATA` = untested.
- **`suggested_campaign_name`**: Ready-to-use name (follows the `{PRODUCT}-{FORMAT}/{MATCH} (context)` convention for automatic ad format detection).
- **`experiment_total_daily_budget`**: Total daily budget if all campaigns are opened.

Budget-constrained? Open only `is_required = TRUE` campaigns first, then add optional ones later.

### Step 1c: Pick keywords for your experiment

Once you have chosen a strategy and ASIN, use the matching query below.

**For EXACT_BOOST** -- proven keywords where your ASIN already converts:

```sql
SELECT
  seg.search_term, seg.occasion, seg.age_group, seg.product_match,
  seg.amazon_avg_weekly_orders,
  seg.your_total_orders,             -- Raw order count (non-holiday weeks)
  seg.ads_total_orders,              -- Ads order count (non-holiday weeks)
  seg.weeks_with_your_orders,        -- Consistency: how many non-holiday weeks you converted
  seg.your_conversion_rate_pct,      -- Your click-to-order rate (non-holiday)
  seg.ads_conversion_rate_pct,       -- Ads click-to-order rate (non-holiday)
  seg.amazon_conversion_rate_pct     -- Market click-to-order rate (non-holiday baseline)
FROM `onyga-482313.OI.V_EXPERIMENT_SUGGESTIONS` sug
JOIN `onyga-482313.OI.V_SEARCH_TERM_SEGMENT` seg
  ON sug.asin_segment_key = seg.asin_segment_key
WHERE sug.suggested_experiment_id = 'WHITE_LOLLIBOX_EXACT_BOOST_BIRTHDAY_KIDS'  -- From Step 1
  AND seg.is_occasion_in_season
  AND seg.is_best_asin_for_term                  -- Only terms where THIS ASIN has best organic potential
  AND (seg.your_total_orders + seg.ads_total_orders) >= 3  -- Proven volume (SQP + Ads combined)
  AND seg.weeks_with_your_orders >= 2            -- Consistent, not a fluke
  AND seg.amazon_avg_weekly_orders > 50          -- Worth the investment
ORDER BY
  seg.amazon_avg_weekly_orders
  * GREATEST(COALESCE(seg.your_conversion_rate_pct, 0), COALESCE(seg.ads_conversion_rate_pct, 0))
  * COALESCE(seg.amazon_conversion_rate_pct, 1) DESC  -- Big market x best conv rate x market conv rate
LIMIT 20;
```

**For SEASONAL_PUSH / pre-holiday experiments** -- use holiday metrics instead:

```sql
SELECT
  seg.search_term, seg.occasion, seg.age_group, seg.product_match,
  seg.holiday_amazon_avg_weekly_orders,
  seg.holiday_your_total_orders,
  seg.holiday_ads_total_orders,
  seg.holiday_weeks_with_your_orders,
  seg.holiday_your_conversion_rate_pct,
  seg.holiday_ads_conversion_rate_pct,
  seg.holiday_amazon_conversion_rate_pct
FROM `onyga-482313.OI.V_EXPERIMENT_SUGGESTIONS` sug
JOIN `onyga-482313.OI.V_SEARCH_TERM_SEGMENT` seg
  ON sug.asin_segment_key = seg.asin_segment_key
WHERE sug.suggested_experiment_id = 'WHITE_LOLLIBOX_SEASONAL_PUSH_CHRISTMAS'
  AND seg.holiday_amazon_avg_weekly_orders > 50
ORDER BY seg.holiday_amazon_avg_weekly_orders DESC
LIMIT 20;
```

**For LOW_COST_DISCOVERY** -- unproven high-potential keywords to test cheaply:

```sql
SELECT
  seg.search_term, seg.occasion, seg.age_group, seg.product_match,
  seg.amazon_avg_weekly_orders,
  seg.your_impressions_share_pct,
  seg.your_orders_share_pct,
  seg.ads_total_orders,
  seg.amazon_conversion_rate_pct
FROM `onyga-482313.OI.V_EXPERIMENT_SUGGESTIONS` sug
JOIN `onyga-482313.OI.V_SEARCH_TERM_SEGMENT` seg
  ON sug.asin_segment_key = seg.asin_segment_key
WHERE sug.suggested_experiment_id = 'WHITE_LOLLIBOX_LOW_COST_DISCOVERY_GIFT_GENERAL'
  AND seg.is_occasion_in_season
  AND seg.is_best_asin_for_term                  -- Only terms where THIS ASIN has best organic potential
  AND (seg.your_total_orders + seg.ads_total_orders) = 0  -- No proven orders yet
  AND seg.your_impressions_share_pct > 0         -- But Amazon shows your listing
  AND seg.amazon_avg_weekly_orders > 100         -- Big enough market to explore
ORDER BY
  seg.amazon_avg_weekly_orders
  * COALESCE(seg.amazon_conversion_rate_pct, 1) DESC  -- Big market x high-intent
LIMIT 20;
```

How to pick keywords:
- **`is_best_asin_for_term`**: Always filter on this. Each keyword is assigned to the ASIN with the highest organic winning potential. The ranking score is `proven_orders * (your_conversion_rate / amazon_conversion_rate)` -- so an ASIN that converts better than the market gets a boost, because Amazon rewards high-converting listings with organic rank. This prevents bidding on the same keyword for multiple ASINs.
- **`asin_rank_for_term`**: If you want to see which ASINs compete for a keyword, remove the `is_best_asin_for_term` filter and look at the rank. Rank 1 = best ASIN for that term. A rank-2 ASIN with conversion rate above market could be worth testing if rank-1 is already saturated.
- **EXACT_BOOST**: Pick 3-5 terms with highest `amazon_avg_weekly_orders` + conversion rate. "Proven" means 3+ orders (SQP + Ads combined) across 2+ non-holiday weeks on a market with 50+ orders/week. All metrics exclude holiday weeks so you see true baseline performance.
- **SEASONAL_PUSH**: Use `holiday_*` columns to see how the keyword performed during the last holiday period. High holiday volume + proven holiday conversions = good seasonal target.
- **LOW_COST_DISCOVERY**: Pick 5-10 broad terms to test. Expect most to fail -- you are looking for the 1-2 that reveal hidden demand.
- **Compare `your_conversion_rate_pct` vs `amazon_conversion_rate_pct`**: If yours is higher, you convert better than the market -- ideal for heavy exact investment. Check `ads_conversion_rate_pct` for additional proof from paid traffic.
- **`weeks_with_your_orders`**: The more non-holiday weeks you consistently convert, the stronger the proof. 2 is the minimum, 4+ is strong.

### Step 2: Create the Amazon campaign

In Amazon Ads Console:
1. Create the campaign (SP or SB) with the suggested settings
2. Set keywords, bids, budget, placement adjustments
3. Note the **campaign_id** from Amazon (visible in the URL or campaign list)
4. Let the campaign run -- Fivetran will sync the data automatically

### Step 3: Register the experiment in BigQuery

Use the `suggested_experiment_id` from Step 1 as your experiment_id:

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT`
  (experiment_id, experiment_name, description, start_date, end_date,
   baseline_days, status, strategy_id, lifecycle_stage, season_context)
VALUES
  ('WHITE_LOLLIBOX_EXACT_BOOST_BIRTHDAY_KIDS',   -- Copy from suggested_experiment_id
   'SB Exact - LolliME Mint Journal',           -- Descriptive name
   'Testing EXACT_BOOST on Mint variant based on EXP001 Pink success',  -- Why
   '2026-02-15',                                -- Start date (when campaign went live)
   NULL,                                        -- End date (NULL = still running)
   28,                                          -- Baseline days (28 = 4 weeks before start)
   'ACTIVE',                                    -- Status: ACTIVE / COMPLETED / PAUSED
   'EXACT_BOOST',                               -- Strategy from DIM_STRATEGY_TEMPLATE
   'ACTIVE',                                    -- Lifecycle: HYPOTHESIS / ACTIVE / REVIEW / VALIDATED / GRADUATED / FAILED
   'NORMAL'                                     -- Season: PEAK / OFF_SEASON / NORMAL / MIXED
  );
```

### Step 4: Link the campaign(s)

**Option A — You already know the campaign_id** (campaign exists in Amazon):

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
  (experiment_id, campaign_id, campaign_name, notes)
VALUES
  ('WHITE_LOLLIBOX_EXACT_BOOST_BIRTHDAY_KIDS',   -- Same suggested_experiment_id
   '289219791540688',                           -- Amazon campaign_id (as STRING)
   'ME-VIDEO/EXACT (Mint journal)',             -- Campaign name for reference
   'Exact match SB Video targeting journal kit keywords'
  );
```

**Option B — Campaign not synced yet** (just created in Amazon, Fivetran hasn't loaded it):

Use `PENDING_` prefix as campaign_id. The orchestrator will auto-resolve it by matching campaign_name.

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
  (experiment_id, campaign_id, campaign_name, notes)
VALUES
  ('WHITE_LOLLIBOX_EXACT_BOOST_BIRTHDAY_KIDS',
   'PENDING_1',                                -- Placeholder — auto-resolved by SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS
   'ME-VIDEO/EXACT (Mint journal)',            -- Must match EXACT campaign name in Amazon
   'PENDING AUTO-LINK. Exact match SB Video targeting journal kit keywords'
  );
```

`SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS` runs daily (Task 16.7 in the orchestrator, before snapshot). It:
1. Finds `DIM_EXPERIMENT_CAMPAIGN` rows where `campaign_id LIKE 'PENDING_%'`
2. Matches `campaign_name` to `V_SRC_AmazonAds_campaign_history` (current Fivetran data)
3. Replaces the pending row with the real numeric campaign_id
4. Logs how many were resolved (or how many are still pending)

Check pending status anytime:
```sql
SELECT experiment_id, campaign_id, campaign_name
FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
WHERE campaign_id LIKE 'PENDING_%';
```

You can link multiple campaigns to one experiment by inserting multiple rows.

**Note:** `top_of_search_pct` and `product_page_pct` in DIM_EXPERIMENT_CAMPAIGN are legacy fields. The actual placement adjustments are now auto-populated from Fivetran via `V_CAMPAIGN_PLACEMENT_BIDDING`.

### Step 5: Verify setup

Check your experiment appears correctly:

```sql
-- Verify experiment settings
SELECT * FROM `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS`
WHERE experiment_id = 'EXP002';

-- Verify search terms are being tracked
SELECT COUNT(*) as terms
FROM `onyga-482313.OI.V_EXPERIMENT_SEARCH_TERMS`
WHERE experiment_id = 'EXP002';

-- Verify segmentation of tracked terms
SELECT experiment_segment, occasion, COUNT(*) as terms
FROM `onyga-482313.OI.V_EXPERIMENT_SEARCH_TERMS` est
JOIN `onyga-482313.OI.V_SEARCH_TERM_SEGMENT` seg
  ON LOWER(est.search_term) = seg.search_term AND est.asin = seg.asin
WHERE est.experiment_id = 'EXP002'
GROUP BY 1, 2 ORDER BY terms DESC;
```

### Step 6: Monitor results

After 1-2 weeks, check progress using the daily protocol (Section 0 above).

The `V_EXPERIMENT_BUDGET_HEALTH` view shows profitability across 4 tiers. The `V_EXPERIMENT_TERM_RECOMMENDATIONS` view shows per-term signals with reasons.

For deeper analysis:

```sql
-- Search term detail per experiment
SELECT * FROM `onyga-482313.OI.V_EXPERIMENT_RESULTS_SEARCH_TERM`
WHERE experiment_id = 'YOUR_EXPERIMENT_ID'
ORDER BY ads_term_cost DESC;

-- ASIN-level performance
SELECT * FROM `onyga-482313.OI.V_EXPERIMENT_RESULTS_ASIN`
WHERE experiment_id = 'YOUR_EXPERIMENT_ID';

-- Campaign settings and placement ROAS
SELECT * FROM `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS`
WHERE experiment_id = 'YOUR_EXPERIMENT_ID';
```

---

## 2. How to Manage Existing Experiments

### View all experiments

```sql
SELECT experiment_id, experiment_name, status, lifecycle_stage,
  start_date, end_date, strategy_id
FROM `onyga-482313.OI.DIM_EXPERIMENT`
ORDER BY start_date DESC;
```

### Pause an experiment

```sql
UPDATE `onyga-482313.OI.DIM_EXPERIMENT`
SET status = 'PAUSED', lifecycle_stage = 'PAUSED', updated_at = CURRENT_TIMESTAMP()
WHERE experiment_id = 'EXP002';
```

Remember to also pause the actual Amazon campaign in Seller Central.

### Complete an experiment

When you decide an experiment is done:

```sql
UPDATE `onyga-482313.OI.DIM_EXPERIMENT`
SET
  status = 'COMPLETED',
  end_date = CURRENT_DATE(),
  lifecycle_stage = 'REVIEW',  -- Move to review for evaluation
  outcome_score = 7.5,         -- Your 1-10 rating
  outcome_tags = 'high_roas,ctr_improved,share_gained',
  outcome_notes = 'Strong ROAS on PRODUCT terms. CTR doubled. Orders share grew +0.09pp.',
  updated_at = CURRENT_TIMESTAMP()
WHERE experiment_id = 'EXP001';
```

### Graduate an experiment (make it a permanent rule)

When an experiment is proven and should become a permanent strategy:

```sql
-- 1. Update lifecycle stage
UPDATE `onyga-482313.OI.DIM_EXPERIMENT`
SET
  lifecycle_stage = 'GRADUATED',
  graduation_date = CURRENT_DATE(),
  graduation_confidence = 'HIGH',    -- LOW / MEDIUM / HIGH
  graduation_criteria_met = 'roas_above_3,days_above_28,share_gained',
  updated_at = CURRENT_TIMESTAMP()
WHERE experiment_id = 'EXP001';

-- 2. Record the graduated rule
INSERT INTO `onyga-482313.OI.FACT_GRADUATED_RULES`
  (rule_id, experiment_id, strategy_id, asin, keyword_match_type,
   campaign_type, bidding_strategy, bid_amount, daily_budget,
   top_of_search_pct, roas, experiment_days, rule_status, graduated_at)
VALUES
  ('RULE001', 'EXP001', 'EXACT_BOOST', 'B0F9XFXQRW', 'EXACT',
   'SB', 'legacy', 0.78, 200.0,
   30, 3.51, 62, 'ACTIVE', CURRENT_TIMESTAMP());
```

### Fail an experiment

```sql
UPDATE `onyga-482313.OI.DIM_EXPERIMENT`
SET
  status = 'COMPLETED',
  end_date = CURRENT_DATE(),
  lifecycle_stage = 'FAILED',
  outcome_score = 2.0,
  outcome_notes = 'ROAS below 1.0 after 30 days. No share improvement.',
  updated_at = CURRENT_TIMESTAMP()
WHERE experiment_id = 'EXP003';
```

### Check recommendations

Use the daily protocol (Section 0) to review experiment health, term recommendations, and hero ASINs.

---

## 3. How to Manage Campaigns

### View all campaigns linked to experiments

```sql
SELECT
  experiment_id, campaign_id, campaign_name,
  campaign_type, bidding_strategy, campaign_budget,
  top_of_search_pct, product_page_pct,
  avg_keyword_bid, num_keywords, primary_match_type,
  tos_roas, dp_roas,
  tos_cost_share_pct
FROM `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS`
ORDER BY experiment_id;
```

### Add a new campaign to an existing experiment

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
  (experiment_id, campaign_id, campaign_name, notes)
VALUES
  ('EXP001', '200171414843593', 'ME-SP/BROAD (Girls journal)', 'Adding SP Broad to test discovery');
```

### Remove a campaign from an experiment

```sql
DELETE FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
WHERE experiment_id = 'EXP001' AND campaign_id = '200171414843593';
```

### Log a setting change (for variation comparison)

Whenever you change a campaign setting in Seller Central (bid, budget, TOS%, add/remove campaign, etc.), log it so the system can split performance into before/after periods:

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CHANGE_LOG`
  (change_id, experiment_id, change_date, change_type, campaign_id, field_changed, old_value, new_value, reason)
VALUES
  ('EXP001_CHG_001',                    -- Unique ID (experiment + sequential number)
   'LOLLIBOX_BRAND_DEFENSE_BRAND',      -- Which experiment
   DATE '2026-03-10',                   -- When the change took effect
   'TOS_CHANGE',                        -- Type: BID_CHANGE, BUDGET_CHANGE, TOS_CHANGE, PP_CHANGE, ADD_CAMPAIGN, REMOVE_CAMPAIGN, KEYWORD_CHANGE, BIDDING_STRATEGY_CHANGE, STATUS_CHANGE, OTHER
   '289219791540688',                   -- Which campaign (NULL if experiment-level)
   'top_of_search_pct',                 -- Field name
   '500',                               -- Previous value
   '300',                               -- New value
   'Competitors gone. Testing lower TOS to reduce cost.'  -- Why
  );
```

**View all changes for an experiment:**

```sql
SELECT change_date, change_type, field_changed, old_value, new_value, reason
FROM `onyga-482313.OI.DIM_EXPERIMENT_CHANGE_LOG`
WHERE experiment_id = 'LOLLIBOX_BRAND_DEFENSE_BRAND'
ORDER BY change_date;
```

**Compare performance across change periods:**

```sql
SELECT
  experiment_id, period_num, period_label,
  period_start, period_end, days_in_period,
  avg_daily_spend, avg_daily_ad_orders, avg_daily_organic_units,
  period_ads_net_roas,
  spend_delta_vs_prev, ad_orders_delta_vs_prev, organic_units_delta_vs_prev
FROM `onyga-482313.OI.V_EXPERIMENT_VARIATION_COMPARISON`
WHERE experiment_id = 'LOLLIBOX_BRAND_DEFENSE_BRAND'
ORDER BY period_num;
```

Period 0 = initial settings. Each subsequent period starts when a change was logged. The `_delta_vs_prev` columns show how metrics changed.

### View placement performance for a campaign

```sql
-- Placement report (daily performance per placement)
SELECT
  campaign_id, report_date, placement,
  impressions, clicks, cost, orders, sales, roas, cpc
FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT`
WHERE campaign_id = '289219791540688'
  AND report_date >= '2026-01-01'
ORDER BY report_date DESC, placement;

-- Placement bid adjustments (current settings)
SELECT *
FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_BIDDING`
WHERE campaign_id = '289219791540688';
```

### View campaign performance by search term

```sql
SELECT
  search_term, ads_term_cost, ads_term_sales, ads_term_roas,
  ads_term_orders, ads_term_cpc
FROM `onyga-482313.OI.V_EXPERIMENT_RESULTS_SEARCH_TERM`
WHERE experiment_id = 'EXP001'
ORDER BY ads_term_cost DESC
LIMIT 20;
```

### Compare ad formats per search term (SP vs SB Video vs SB Store)

```sql
-- Which ad format performs best for each search term?
SELECT
  search_term,
  ad_formats,
  ads_exp_orders,
  ROUND(ads_exp_cost, 2) as total_cost,
  -- SP performance
  sp_orders, sp_roas, sp_cpc,
  -- SB Video performance
  sbv_orders, sbv_roas, sbv_cpc,
  -- SB Store performance
  sbs_orders, sbs_roas, sbs_cpc,
  -- Search vs Product Page
  search_orders, search_roas,
  product_page_orders, product_page_roas,
  -- Winner
  best_roas_ad_format,
  best_roas_placement
FROM `onyga-482313.OI.V_EXPERIMENT_SEARCH_TERMS`
WHERE experiment_id = 'EXP001'
  AND ads_exp_orders > 0
ORDER BY ads_exp_cost DESC
LIMIT 20;
```

### Learn which placement works best per strategy

```sql
-- Aggregated across all experiments: which ad_format + placement combo
-- delivers the best ROAS for each strategy template?
SELECT
  strategy_name, ad_format, placement,
  experiment_count, days_of_data,
  total_orders, total_cost, total_sales,
  roas, cpc, conversion_rate_pct,
  cost_share_of_strategy_pct,
  roas_rank_in_strategy
FROM `onyga-482313.OI.V_EXPERIMENT_PLACEMENT_LEARNINGS`
ORDER BY strategy_id, roas_rank_in_strategy;
```

---

## 4. View Reference

### Core Experiment Views

| View | Purpose |
|------|---------|
| `V_EXPERIMENT_SUMMARY` | One-row-per-experiment dashboard with all key metrics |
| `V_EXPERIMENT_RESULTS_ASIN` | ASIN-level results (Business Reports data, reliable) |
| `V_EXPERIMENT_RESULTS_SEARCH_TERM` | Search-term-level results (SQP data + Ads ROAS + normalized lift) |
| `V_EXPERIMENT_CAMPAIGN_SETTINGS` | Campaign recipe + placement bid adjustments + placement ROAS |
| `V_EXPERIMENT_SEARCH_TERMS` | All search terms tracked per experiment + ad format & placement breakdown |

### Intelligence Views (feedback loop)

| View | Purpose |
|------|---------|
| `V_PARENT_HERO_ASIN` | **Start here.** Per search term × parent family, ranks children by organic growth potential (CVR × CTR × margin). Hero = child Amazon will reward on that term. Includes `reason` and `confidence`. |
| `V_EXPERIMENT_BUDGET_HEALTH` | Per experiment: 4-tier profitability (family, ASIN, ads, SQP), budget pacing, trends |
| `V_EXPERIMENT_TERM_RECOMMENDATIONS` | Per search term: KEEP/STOP/REDUCE_BID/PROMOTE_TO_EXACT + untapped opportunities. Every row has a `reason` + `hero_asin` (which child to advertise) + `is_hero_match` (are you on the right child?). |
| `V_SEARCH_TERM_SEGMENT` | Tags every SQP term with 4 dimensions: intent, occasion, age, product match |
| `V_ASIN_BEST_PRACTICES` | What worked per ASIN + segment (the "memory") |
| `V_EXPERIMENT_LEARNINGS` | Aggregated patterns across all experiments by 12 dimensions |
| `V_EXPERIMENT_SUGGESTIONS` | Recommended next experiments ranked by opportunity score |
| `V_EXPERIMENT_SUGGESTED_CAMPAIGNS` | Specific campaigns per suggestion (uses ASIN conclusions for proven budgets) |

### Placement Views

| View | Purpose |
|------|---------|
| `V_CAMPAIGN_PLACEMENT_REPORT` | SP + SB daily performance per placement (TOS, Detail Page, etc.) |
| `V_CAMPAIGN_PLACEMENT_BIDDING` | SP + SB bid adjustment percentages per placement |
| `V_EXPERIMENT_PLACEMENT_LEARNINGS` | Which ad format + placement combo works best per strategy (aggregated across experiments) |

### Variation & Change Tracking

| View / Table | Purpose |
|------|---------|
| `DIM_EXPERIMENT_CHANGE_LOG` | Manual log of setting changes (bid, TOS%, budget, campaigns added/removed). Enables period-based comparison. |
| `V_EXPERIMENT_VARIATION_COMPARISON` | Splits experiment performance into periods around logged changes. Compares spend, orders, ROAS, organic lift per period with deltas. |

### Strategy & Seasonal Views

| View | Purpose |
|------|---------|
| `V_STRATEGY_CURRENT_RECOMMENDATIONS` | Strategy settings adjusted for current season |
| `V_SEASONAL_INDEX_WEEKLY` | Weekly seasonal demand index |
| `V_EXPERIMENT_LEARNINGS` | Pattern recognition across completed experiments |

### Tables (manual data entry)

| Table | Purpose |
|-------|---------|
| `DIM_EXPERIMENT` | Experiment definitions (you INSERT/UPDATE) |
| `DIM_EXPERIMENT_CAMPAIGN` | Links experiments to Amazon campaigns (you INSERT) |
| `DIM_STRATEGY_TEMPLATE` | Strategy recipes and seasonal multipliers |
| `DIM_STRATEGY_CAMPAIGN_TEMPLATE` | Campaign mix per strategy (which campaigns to open) |
| `DIM_EXPERIMENT_CHANGE_LOG` | Tracks setting changes to experiments for variation comparison (you INSERT) |
| `FACT_GRADUATED_RULES` | Experiments that became permanent rules |
| `FACT_ASIN_CONCLUSIONS` | ASIN-level proven recipes with DRAFT/ENABLED lifecycle (auto-populated by SP_UPDATE_ASIN_CONCLUSIONS) |

### Stored Procedures (experiment-related)

| Procedure | When | Purpose |
|-----------|------|---------|
| `SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS` | Daily (Task 16.7, before snapshot) | Resolves `PENDING_` campaign links by matching campaign_name to Fivetran data |
| `SP_EXPERIMENT_DAILY_SNAPSHOT` | Daily (Task 16.8) | Populates `FACT_EXPERIMENT_DAILY` with ads + organic metrics per experiment |
| `SP_UPDATE_ASIN_CONCLUSIONS` | Daily (Task 16.9) | Aggregates completed experiment results into `FACT_ASIN_CONCLUSIONS` |
| `SP_EXPERIMENT_WEEKLY_REVIEW` | Weekly (Mondays, Task 17.2) | Generates weekly experiment recommendations |

---

## 5. Join Keys Reference

Every view has a `row_key` (its primary key) plus standardized join keys for single-column joins between views.

### Key Columns

| Key Name | Format | Description |
|----------|--------|-------------|
| `row_key` | varies per view | Unique identifier for each row |
| `search_term_key` | `search_term\|asin` | Joins search-term-level views |
| `experiment_asin_key` | `experiment_id\|asin` | Joins experiment-ASIN-level views |
| `asin_segment_key` | `asin\|experiment_segment` | Joins ASIN+segment views (suggestions to search terms) |

### Which views have which keys

| View | row_key | search_term_key | experiment_asin_key | asin_segment_key |
|------|---------|-----------------|---------------------|------------------|
| V_SEARCH_TERM_SEGMENT | search_term\|asin | Y | - | Y |
| V_EXPERIMENT_SUGGESTIONS | asin\|strategy\|segment | - | - | Y |
| V_EXPERIMENT_RESULTS_SEARCH_TERM | exp\|term\|asin | Y | Y | - |
| V_EXPERIMENT_RESULTS_ASIN | exp\|asin | - | Y | - |
| V_EXPERIMENT_SUMMARY | experiment_id | - | - | - |
| V_EXPERIMENT_CAMPAIGN_SETTINGS | exp\|campaign | - | - | - |
| V_EXPERIMENT_SEARCH_TERMS | exp\|term\|asin | Y | Y | - |
| V_ASIN_BEST_PRACTICES | exp\|asin\|segment | - | Y | Y |
| V_EXPERIMENT_LEARNINGS | dim\|value | - | - | - |
| V_EXPERIMENT_SUGGESTED_CAMPAIGNS | exp_id\|seq | - | - | Y |
| V_EXPERIMENT_PLACEMENT_LEARNINGS | strategy\|format\|placement | - | - | - |
| V_PARENT_HERO_ASIN | search_term\|parent_name\|asin | Y | - | - |
| V_EXPERIMENT_TERM_RECOMMENDATIONS | search_term\|asin | Y | - | - |
| V_EXPERIMENT_BUDGET_HEALTH | experiment_id | - | - | - |

### Common join examples

```sql
-- Suggestion keywords: V_EXPERIMENT_SUGGESTIONS -> V_SEARCH_TERM_SEGMENT
SELECT sug.*, seg.search_term, seg.amazon_avg_weekly_orders
FROM V_EXPERIMENT_SUGGESTIONS sug
JOIN V_SEARCH_TERM_SEGMENT seg ON sug.asin_segment_key = seg.asin_segment_key;

-- Experiment search term detail + segmentation
SELECT est.*, seg.experiment_segment, seg.occasion, seg.age_group
FROM V_EXPERIMENT_SEARCH_TERMS est
JOIN V_SEARCH_TERM_SEGMENT seg ON est.search_term_key = seg.search_term_key;

-- Experiment ASIN results + best practices per segment
SELECT ar.*, bp.experiment_segment, bp.segment_verdict
FROM V_EXPERIMENT_RESULTS_ASIN ar
JOIN V_ASIN_BEST_PRACTICES bp ON ar.experiment_asin_key = bp.experiment_asin_key;
```

---

## 6. Strategy Templates

Available strategies in `DIM_STRATEGY_TEMPLATE`:

| Strategy ID | Name | Campaign Type | Match Type | Use Case |
|-------------|------|---------------|------------|----------|
| BRAND_DEFENSE | Brand Defense | SP | EXACT | Protect brand keywords from competitors |
| EXACT_BOOST | Exact Keyword Boost | SP | EXACT | Increase visibility on high-intent exact keywords |
| TOS_DOMINATION | Top-of-Search Domination | SP | EXACT | Win top placement on key terms |
| HUNTER | Hunter | SP | BROAD | Discover new converting keywords |
| LOW_COST_DISCOVERY | Low-Cost Discovery | SP | AUTO | Cheap keyword discovery via auto campaigns |
| CATEGORY_CONQUEST | Category Conquest | SP | AUTO | Steal share from competitor brand terms |
| NEW_LAUNCH | New Product Launch | BOTH | MIXED | Full-funnel for new product launches |
| SEASONAL_PUSH | Seasonal Push | BOTH | MIXED | Peak season maximum visibility |
| RETARGETING | Retargeting | SB | MIXED | Re-engage past visitors |
| PRODUCT_DEFENSE | Product Defense | SP | EXACT | Protect your product detail pages |

### Campaign recipes per strategy

Each strategy prescribes specific campaigns to open. Use `V_EXPERIMENT_SUGGESTED_CAMPAIGNS` for the full detail, or see the summary below.

> **Budget rationale:** Budgets are calibrated for products in the $50-60 range with ~$0.60-0.70 CPC. Each campaign needs ~$15-50/day to collect 30+ clicks/day for statistically significant results within 1-2 weeks. High TOS boost strategies need larger budgets because effective bids are multiplied.

| Strategy | # | Ad Format | Match | $/day | TOS % | Required | Purpose |
|----------|---|-----------|-------|-------|-------|----------|---------|
| **EXACT_BOOST** ($80) | 1 | SP | EXACT | $40 | 500 | Yes | SP TOS dominance on proven terms |
| | 2 | SB_VIDEO | EXACT | $25 | 0 | Yes | Video slot above organic results |
| | 3 | SB_STORE | EXACT | $15 | 0 | No | Brand store traffic + cross-sell |
| **TOS_DOMINATION** ($75) | 1 | SP | EXACT | $50 | 900 | Yes | Extreme TOS to lock position 1 |
| | 2 | SB_VIDEO | EXACT | $25 | 0 | Yes | Video slot for double presence |
| **SEASONAL_PUSH** ($100) | 1 | SP | EXACT | $50 | 500 | Yes | Seasonal keywords max aggression |
| | 2 | SB_VIDEO | EXACT | $35 | 0 | Yes | Seasonal video creative |
| | 3 | SB_STORE | BROAD | $15 | 0 | No | Seasonal store spotlight |
| **NEW_LAUNCH** ($115) | 1 | SP | EXACT | $45 | 400 | Yes | Build initial sales velocity |
| | 2 | SP | AUTO | $25 | 0 | Yes | Discover unexpected keywords |
| | 3 | SB_VIDEO | BROAD | $30 | 0 | Yes | Brand awareness via video |
| | 4 | SB_STORE | BROAD | $15 | 0 | No | Store trust for new product |
| **HUNTER** ($50) | 1 | SP | BROAD | $30 | 200 | Yes | Broad match discovery |
| | 2 | SB_VIDEO | BROAD | $20 | 0 | No | Video on new terms |
| **LOW_COST_DISCOVERY** ($15) | 1 | SP | AUTO | $15 | 0 | Yes | Low-cost auto discovery |
| **BRAND_DEFENSE** ($40) | 1 | SP | EXACT | $25 | 300 | Yes | Core brand defense |
| | 2 | SB_VIDEO | EXACT | $15 | 0 | No | Video brand reinforcement |
| **CATEGORY_CONQUEST** ($45) | 1 | SP | AUTO | $25 | 0 | Yes | Target competitor ASINs |
| | 2 | SB_VIDEO | BROAD | $20 | 0 | No | Video on competitor terms |
| **PRODUCT_DEFENSE** ($20) | 1 | SP | PT | $20 | 0 | Yes | Defend product detail pages |
| **RETARGETING** ($35) | 1 | SB_VIDEO | BROAD | $20 | 100 | Yes | Video retargeting |
| | 2 | SB_STORE | BROAD | $15 | 0 | No | Store retargeting |

**Naming convention for automatic ad format detection:** Include `VIDEO` or `STORE` in SB campaign names (e.g., `BOX-VIDEO/EXACT (gifts)`). This ensures the system auto-classifies the campaign as `SB_VIDEO` or `SB_STORE` in `V_EXPERIMENT_SEARCH_TERMS` and `V_EXPERIMENT_PLACEMENT_LEARNINGS`.

### Campaign Structure Per Child ASIN

**Rules:**
- One campaign = one ASIN = one strategy = one experiment. Never mix.
- One BRAND_DEFENSE experiment per parent family (not per child ASIN).
- Start with LOW_COST_DISCOVERY, graduate winners to EXACT_BOOST. This is the flywheel.

**Typical ASIN = 2-4 campaigns:**
- Minimum (new/low budget): LOW_COST_DISCOVERY + BRAND_DEFENSE = 2 campaigns
- Standard (proven product): LOW_COST_DISCOVERY + EXACT_BOOST + BRAND_DEFENSE = 3 campaigns
- Aggressive (growth mode): all above + CATEGORY_CONQUEST or HUNTER = 4-5 campaigns

### Strategy Playbooks

Detailed playbook per strategy: what to expect, how to set up, and when to act.

---

#### LOW_COST_DISCOVERY

**Goal:** Find converting search terms at minimal cost. Always-on keyword net.

**When to use:** Always. Every ASIN should have one running permanently.
**When NOT to use:** Never stop this.

**Starting setup:** 1 SP Auto campaign, DOWN_ONLY, bid $0.10-$0.35, budget $15/day, no placement boosts.

| Week | What to expect | Action |
|------|---------------|--------|
| 1 | Impressions flowing, few clicks, likely 0 orders | Do nothing. Let Amazon learn. |
| 2 | 50-100+ search terms, 1-3 orders if lucky | Negate brand terms (waste of budget). |
| 3 | Converting terms emerge. $0.20-0.40 CPC. | Check term recommendations for PROMOTE_TO_EXACT. |
| 4+ | Steady long-tail discoveries. 1-5 orders/week. | Promote winners to EXACT_BOOST. Negate losers. Keep running. |

**Key metric:** New converting search terms discovered (not ROAS).
**Success:** 3+ terms worth promoting to EXACT_BOOST within 4 weeks.
**Failure:** After 4 weeks, zero orders and $200+ spent. Raise bid to $0.35 or check ASIN demand.
**Common mistakes:** Bids too high (defeats low-cost purpose), negating too aggressively (kills discovery), judging on ROAS (it's a discovery tool).

**Audit: which ASINs have/don't have LOW_COST_DISCOVERY?**

```sql
SELECT
  p.asin, p.product_short_name, p.parent_name,
  e.experiment_id, e.status as exp_status, e.start_date,
  ec.campaign_name, ec.campaign_id,
  vcs.campaign_budget as amazon_daily_budget,
  vcs.bidding_strategy, vcs.avg_keyword_bid,
  bh.days_running, bh.ads_net_profit, bh.ads_net_roas,
  bh.budget_utilization_pct, bh.data_status
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON e.strategy_id = 'LOW_COST_DISCOVERY' AND e.status = 'ACTIVE'
  AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec2
    JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec2.campaign_id = fa.campaign_id
    WHERE ec2.experiment_id = e.experiment_id AND fa.advertised_asins = p.asin
  )
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON ec.experiment_id = e.experiment_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
  ON vcs.experiment_id = e.experiment_id AND vcs.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  ON bh.experiment_id = e.experiment_id
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  AND p.listing_price_amount > 0
ORDER BY
  CASE WHEN e.experiment_id IS NULL THEN 0 ELSE 1 END,
  p.parent_name, p.product_short_name;
```

Rows with NULL `experiment_id` = ASIN missing this strategy. Every ASIN should have one.

---

#### EXACT_BOOST

**Goal:** Dominate top-of-search for proven keywords to boost sales velocity and organic rank.

**When to use:** Keywords with 3+ orders and proven conversion rate.
**When NOT to use:** Unproven keywords. Use HUNTER or LOW_COST_DISCOVERY first.

**Starting setup:**
- Campaign 1 (required): SP Exact, DOWN_ONLY, bid $0.50-$2.00, budget $40/day, TOS 500%
- Campaign 2 (required): SB Video Exact, DOWN_ONLY, bid $0.50-$1.50, budget $25/day
- Campaign 3 (optional): SB Store Exact, DOWN_ONLY, bid $0.30-$1.00, budget $15/day
- Pick 3-5 proven keywords max. Use the hero ASIN per keyword.

| Week | What to expect | Action |
|------|---------------|--------|
| 1 | High impressions, TOS share climbing. ROAS may be unstable. | If budget runs out before noon, raise budget. |
| 2 | CPC stabilizes. 5-15 orders. ROAS should be 1.0+. | If `ads_net_roas` < 0.7, reduce bid 20%. |
| 3 | Organic rank may start improving (check SQP impression share). | Compare SQP impression share vs week 1. |
| 4+ | Steady state. Organic sales lift visible alongside ad sales. | If `parent_family_net_roas` > 1.0, you're winning. |

**Key metric:** `ads_net_roas` > 1.0 + organic impression share trending up.
**Success:** ROAS > 1.0, TOS share > 30%, organic orders increasing. Graduate after 28+ days.
**Failure:** After 3 weeks, ROAS < 0.7 and no organic lift. Reduce bids or stop.
**Common mistakes:** Too many keywords (dilutes budget), not using TOS boost, ignoring hero ASIN.

**Audit: which ASINs have/don't have EXACT_BOOST?**

```sql
SELECT
  p.asin, p.product_short_name, p.parent_name,
  e.experiment_id, e.status as exp_status, e.start_date,
  ec.campaign_name, ec.campaign_id,
  vcs.campaign_budget as amazon_daily_budget,
  vcs.bidding_strategy, vcs.primary_match_type,
  vcs.top_of_search_pct, vcs.avg_keyword_bid, vcs.num_keywords,
  bh.days_running, bh.ads_net_profit, bh.ads_net_roas,
  bh.budget_utilization_pct, bh.data_status,
  bh.ads_roas_trend
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON e.strategy_id = 'EXACT_BOOST' AND e.status = 'ACTIVE'
  AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec2
    JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec2.campaign_id = fa.campaign_id
    WHERE ec2.experiment_id = e.experiment_id AND fa.advertised_asins = p.asin
  )
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON ec.experiment_id = e.experiment_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
  ON vcs.experiment_id = e.experiment_id AND vcs.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  ON bh.experiment_id = e.experiment_id
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  AND p.listing_price_amount > 0
ORDER BY
  CASE WHEN e.experiment_id IS NULL THEN 0 ELSE 1 END,
  p.parent_name, p.product_short_name;
```

Check: `top_of_search_pct` should be ~500%, `num_keywords` should be 3-5 (not more), `primary_match_type` should be EXACT. Rows with NULL `experiment_id` = no EXACT_BOOST yet (need proven terms first).

---

#### HUNTER

**Goal:** Broad net to discover new converting keywords and steal competitor traffic.

**When to use:** Expand keyword coverage. Good for competitor search terms.
**When NOT to use:** Tight budget (broad burns fast). Start with LOW_COST_DISCOVERY instead.

**Starting setup:**
- Campaign 1 (required): SP Broad, UP_AND_DOWN, bid $0.50-$1.50, budget $30/day, TOS 200%, PP 100%
- Campaign 2 (optional): SB Video Broad, UP_AND_DOWN, bid $0.40-$1.20, budget $20/day
- Seed 5-10 broad keywords (category terms or competitor names).

| Week | What to expect | Action |
|------|---------------|--------|
| 1 | Lots of impressions, many irrelevant terms. | Negate obvious junk. |
| 2 | 100+ unique terms. Some convert, most won't. | Negate 10+ click non-converters. Promote winners to EXACT_BOOST. |
| 3 | Funnel cleaner. ROAS improves as negatives accumulate. | Continue harvest: promote winners, negate losers. |
| 4-6 | Discovery rate slows. Most valuable terms found. | Reduce budget or pause if < 1 new winner/week. |

**Key metric:** New converting terms discovered per week.
**Success:** 5+ promotable terms within 6 weeks. ROAS 0.8-1.2 is acceptable.
**Failure:** After 6 weeks, zero promotable terms and ROAS < 0.5. Stop.
**Common mistakes:** Not negating aggressively, running forever (HUNTER is temporary discovery), promoting terms without checking hero ASIN.

**Audit: which ASINs have/don't have HUNTER?**

```sql
SELECT
  p.asin, p.product_short_name, p.parent_name,
  e.experiment_id, e.status as exp_status, e.start_date,
  ec.campaign_name, ec.campaign_id,
  vcs.campaign_budget as amazon_daily_budget,
  vcs.bidding_strategy, vcs.primary_match_type,
  vcs.top_of_search_pct, vcs.avg_keyword_bid,
  bh.days_running, bh.ads_net_profit, bh.ads_net_roas,
  bh.budget_utilization_pct, bh.data_status
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON e.strategy_id = 'HUNTER' AND e.status = 'ACTIVE'
  AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec2
    JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec2.campaign_id = fa.campaign_id
    WHERE ec2.experiment_id = e.experiment_id AND fa.advertised_asins = p.asin
  )
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON ec.experiment_id = e.experiment_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
  ON vcs.experiment_id = e.experiment_id AND vcs.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  ON bh.experiment_id = e.experiment_id
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  AND p.listing_price_amount > 0
ORDER BY
  CASE WHEN e.experiment_id IS NULL THEN 0 ELSE 1 END,
  p.parent_name, p.product_short_name;
```

Check: `primary_match_type` should be BROAD, `bidding_strategy` should be UP_AND_DOWN. Not every ASIN needs HUNTER -- only use when actively expanding keyword coverage.

---

#### CATEGORY_CONQUEST

**Goal:** Show up on competitor product pages and auto-discovered category terms.

**When to use:** You have competitive advantage (better reviews, lower price, unique product).
**When NOT to use:** Fewer reviews or higher price than competitors.

**Starting setup:**
- Campaign 1 (required): SP Auto, DOWN_ONLY, bid $0.25-$0.75, budget $25/day
- Campaign 2 (optional): SB Video Broad, DOWN_ONLY, bid $0.30-$0.80, budget $20/day

| Week | What to expect | Action |
|------|---------------|--------|
| 1 | Ads appear on competitor pages. Low CVR expected. | Review impression sources. |
| 2 | Search terms appearing. Competitor brand names visible. | Negate your own brand terms. |
| 3 | See which competitor audiences convert. Expect 1-3% CVR. | Note winning competitor ASINs. |
| 4+ | Patterns emerge: which competitor audiences buy your product. | Promote winners to EXACT_BOOST. Negate dead-end terms. |

**Key metric:** Orders from competitor terms + new keyword discoveries.
**Success:** ROAS > 0.8 on competitor terms and 3+ new keywords in 4 weeks.
**Failure:** After 4 weeks, ROAS < 0.5 and no converting competitor terms. Stop.
**Common mistakes:** Running against competitors with far more reviews, not separating product targeting from keyword targeting.

**Audit: which ASINs have/don't have CATEGORY_CONQUEST?**

```sql
SELECT
  p.asin, p.product_short_name, p.parent_name,
  e.experiment_id, e.status as exp_status, e.start_date,
  ec.campaign_name, ec.campaign_id,
  vcs.campaign_budget as amazon_daily_budget,
  vcs.bidding_strategy, vcs.avg_keyword_bid,
  bh.days_running, bh.ads_net_profit, bh.ads_net_roas,
  bh.budget_utilization_pct, bh.data_status
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON e.strategy_id = 'CATEGORY_CONQUEST' AND e.status = 'ACTIVE'
  AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec2
    JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec2.campaign_id = fa.campaign_id
    WHERE ec2.experiment_id = e.experiment_id AND fa.advertised_asins = p.asin
  )
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON ec.experiment_id = e.experiment_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
  ON vcs.experiment_id = e.experiment_id AND vcs.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  ON bh.experiment_id = e.experiment_id
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  AND p.listing_price_amount > 0
ORDER BY
  CASE WHEN e.experiment_id IS NULL THEN 0 ELSE 1 END,
  p.parent_name, p.product_short_name;
```

Check: `bidding_strategy` should be DOWN_ONLY. Not every ASIN needs this -- only when you have a competitive advantage.

---

#### BRAND_DEFENSE

**Goal:** Ensure your products appear first when shoppers search your brand name. Prevent copycats from stealing brand searches.

**When to use:** Always. One per product line that has brand search volume in SQP.
**When NOT to use:** Only skip if zero brand awareness (no one searches your name yet -- check SQP first).

**Starting setup (aggressive -- start maximum, reduce later):**
- Campaign 1 (required): SP Phrase+Exact, DOWN_ONLY, bid $0.50, budget $25/day, TOS 500%
- Campaign 2 (required): SB Video Phrase+Exact, DOWN_ONLY, bid $0.40, budget $15/day
- Keywords: use **Phrase** for brand stems (catches long-tail variations), **Exact** for specific product names
- Negative keywords: "lollipop" and sibling brand terms (e.g., negate "lollime" in lollibox defense)

**Why Phrase match (not Exact) for brand defense:**
- Your brand name is unique -- low risk of irrelevant matches
- SQP shows many long-tail variations you can't predict ("happy lolli gift for girls age 10")
- 1 phrase keyword catches what 20+ exact keywords would miss
- Use Exact alongside for specific product names ("lollibox", "lolli box")

| Week | What to expect | Action |
|------|---------------|--------|
| 1 | High CTR (5-10%+), CPC $0.15-0.40. Budget may not fully spend (good -- brand terms are cheap). | Verify TOS presence. Run week 1 check query below. |
| 2 | ROAS should be 3-20x. Brand clicks are cheap. SP and SB Video data accumulating. | If competitors still above you, raise TOS to 700%. Check SP vs SB Video in `V_EXPERIMENT_BUDGET_HEALTH`. |
| 3-4 | Steady state. Competitors get pushed to lower positions, their ROI craters. | Check `FACT_ASIN_CONCLUSIONS` (auto-populated after day 14). Compare `sp_net_roas` vs `sb_video_net_roas`. |
| 5+ | Competitors may stop bidding on your brand. CPC drops further. | Test reducing: lower TOS to 300%, bid to $0.30. Log changes in `DIM_EXPERIMENT_CHANGE_LOG`. Compare periods in `V_EXPERIMENT_VARIATION_COMPARISON`. |

**Key metric:** TOS impression share on brand terms > 80%, CPC < $0.50.
**Success:** Dominating brand search at low cost. ROAS > 3.0. Copycats gone from brand search results.
**Failure:** Rare. If ROAS < 1.0, non-brand terms may be leaking in (check 1.4 query).
**Common mistakes:** Missing brand variations, using Exact only (misses long-tail), mixing with non-defense campaigns, not negating brand terms in other campaigns.

##### Step-by-step: Create BRAND_DEFENSE experiments

**Experiment 1: Lollibox brand defense**

Hero ASIN: White Lollibox (B0C1VLXYBP) -- best seller, highest conversions on brand terms.

1. **Create campaigns in Amazon Seller Central:**

Campaign 1 (SP):
- Name: `BOX-SP/PHRASE (Brand Defense)`
- ASIN: White Lollibox (B0C1VLXYBP)
- Targeting: Manual
- Bidding: DOWN_ONLY, TOS 500%
- Budget: $25/day, Bid: $0.50
- Keywords:
  - Phrase: "happy lolli"
  - Exact: "lollibox", "lolli box", "happy lollibox", "happy lolli box", "lolli gift box"
- Negative Phrase: "lollipop", "lollime"

Campaign 2 (SB Video):
- Name: `BOX-VIDEO/PHRASE (Brand Defense)`
- ASIN: White Lollibox (B0C1VLXYBP)
- Bidding: DOWN_ONLY
- Budget: $15/day, Bid: $0.40
- Same keywords and negatives as Campaign 1

2. **Register the experiment in BigQuery:**

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT`
  (experiment_id, experiment_name, description, start_date, end_date,
   baseline_days, status, strategy_id, lifecycle_stage, season_context)
VALUES
  ('LOLLIBOX_BRAND_DEFENSE_BRAND',
   'Lollibox - Brand Defense',
   'SP + SB Video defending brand terms (happy lolli, lollibox). Hero ASIN: White Lollibox. Aggressive: TOS 500%, bid $0.50.',
   CURRENT_DATE(),
   NULL,
   28,
   'ACTIVE',
   'BRAND_DEFENSE',
   'ACTIVE',
   'NORMAL'
  );
```

3. **Link both campaigns** (replace campaign_id with actual Amazon campaign IDs):

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
  (experiment_id, campaign_id, campaign_name, notes)
VALUES
  ('LOLLIBOX_BRAND_DEFENSE_BRAND',
   'REPLACE_WITH_SP_CAMPAIGN_ID',
   'BOX-SP/PHRASE (Brand Defense)',
   'SP Phrase+Exact on brand terms. TOS 500%, bid $0.50.'),
  ('LOLLIBOX_BRAND_DEFENSE_BRAND',
   'REPLACE_WITH_SB_VIDEO_CAMPAIGN_ID',
   'BOX-VIDEO/PHRASE (Brand Defense)',
   'SB Video Phrase+Exact on brand terms. Bid $0.40.');
```

**Experiment 2: LolliME brand defense**

Hero ASIN: Mint LolliME (B0F9X95K5H).

1. **Create campaigns in Amazon Seller Central:**

Campaign 1 (SP):
- Name: `ME-SP/PHRASE (Brand Defense)`
- ASIN: Mint LolliME (B0F9X95K5H)
- Bidding: DOWN_ONLY, TOS 500%
- Budget: $15/day, Bid: $0.50
- Keywords:
  - Phrase: "lollime", "lolli me"
  - Exact: "happy lollime"
- Negative Phrase: "lollipop"

Campaign 2 (SB Video):
- Name: `ME-VIDEO/PHRASE (Brand Defense)`
- ASIN: Mint LolliME (B0F9X95K5H)
- Bidding: DOWN_ONLY
- Budget: $10/day, Bid: $0.40
- Same keywords and negatives as Campaign 1

2. **Register the experiment:**

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT`
  (experiment_id, experiment_name, description, start_date, end_date,
   baseline_days, status, strategy_id, lifecycle_stage, season_context)
VALUES
  ('LOLLIME_BRAND_DEFENSE_BRAND',
   'LolliME - Brand Defense',
   'SP + SB Video defending brand terms (lollime, lolli me). Hero ASIN: Mint LolliME. Aggressive: TOS 500%, bid $0.50.',
   CURRENT_DATE(),
   NULL,
   28,
   'ACTIVE',
   'BRAND_DEFENSE',
   'ACTIVE',
   'NORMAL'
  );
```

3. **Link both campaigns:**

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
  (experiment_id, campaign_id, campaign_name, notes)
VALUES
  ('LOLLIME_BRAND_DEFENSE_BRAND',
   'REPLACE_WITH_SP_CAMPAIGN_ID',
   'ME-SP/PHRASE (Brand Defense)',
   'SP Phrase+Exact on lollime brand terms. TOS 500%, bid $0.50.'),
  ('LOLLIME_BRAND_DEFENSE_BRAND',
   'REPLACE_WITH_SB_VIDEO_CAMPAIGN_ID',
   'ME-VIDEO/PHRASE (Brand Defense)',
   'SB Video Phrase+Exact on lollime brand terms. Bid $0.40.');
```

4. **After setup: negate brand terms in existing campaigns.**

Add "happy lolli", "lollibox", "lolli box", "lollime" as NEGATIVE PHRASE in these campaigns (they're currently wasting money on brand terms):
- BOX- STORE broad (BY AGE)
- BOX- STORE/ BROAD
- BOX- COMPETE (Copycats)
- BOX- COMPETE (Copycats white)
- BRAND-STORE/BROAD (Me,Box,Bottle)
- All other BROAD/AUTO campaigns

5. **Verify setup:**

```sql
SELECT * FROM `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS`
WHERE experiment_id LIKE '%BRAND_DEFENSE%';
```

6. **Backfill daily data** (run once after creating experiments):

```sql
CALL `onyga-482313.OI.SP_EXPERIMENT_DAILY_SNAPSHOT`();
```

##### Week-by-week check queries

**Week 1 check -- is it running?**

```sql
SELECT
  experiment_id, snapshot_date, day_number,
  ads_exp_cost, ads_exp_orders, ads_exp_sales,
  performance_total_orders, performance_organic_units
FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY`
WHERE experiment_id LIKE '%BRAND_DEFENSE%'
ORDER BY experiment_id, snapshot_date DESC
LIMIT 14;
```

**Week 2+ check -- SP vs SB Video breakdown:**

```sql
SELECT
  experiment_id, strategy_id,
  days_running, data_status,
  ads_net_roas, ads_net_profit,
  budget_utilization_pct, ads_roas_trend
FROM `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH`
WHERE experiment_id LIKE '%BRAND_DEFENSE%';
```

**Week 3+ check -- auto-generated conclusions:**

```sql
SELECT
  asin, strategy_id, experiment_segment,
  ads_only_net_roas, sp_net_roas, sb_video_net_roas,
  proven_daily_budget, avg_cpc,
  total_experiment_days, total_ad_spend,
  learning_summary
FROM `onyga-482313.OI.FACT_ASIN_CONCLUSIONS`
WHERE strategy_id = 'BRAND_DEFENSE'
ORDER BY updated_at DESC;
```

**Week 5+ check -- after reducing settings, compare periods:**

```sql
SELECT
  experiment_id, period_num, period_label,
  period_start, period_end, days_in_period,
  field_changed, old_value, new_value, change_reason,
  avg_daily_spend, avg_daily_ad_orders, avg_daily_organic_units,
  period_ads_net_roas, period_traditional_roas,
  spend_delta_vs_prev, ad_orders_delta_vs_prev, organic_units_delta_vs_prev
FROM `onyga-482313.OI.V_EXPERIMENT_VARIATION_COMPARISON`
WHERE experiment_id LIKE '%BRAND_DEFENSE%'
ORDER BY experiment_id, period_num;
```

##### Phased variation testing

**Phase 1 (Weeks 1-4):** Maximum defense: SP + SB Video, bid $0.50, TOS 500%. Establish dominance.

**Phase 2 (Weeks 5-8):** Review `FACT_ASIN_CONCLUSIONS`. If one format clearly underperforms (`sb_video_net_roas` < 1.0), test pausing it or reducing its budget. Log change:

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CHANGE_LOG`
  (change_id, experiment_id, change_date, change_type, campaign_id, field_changed, old_value, new_value, reason)
VALUES
  ('LOLLIBOX_BD_001', 'LOLLIBOX_BRAND_DEFENSE_BRAND', CURRENT_DATE(),
   'BUDGET_CHANGE', 'YOUR_SB_VIDEO_CAMPAIGN_ID', 'daily_budget', '15', '0',
   'SB Video ROAS < 1.0 after 4 weeks. Pausing to test SP-only performance.');
```

**Phase 3 (Weeks 9-12):** If competitors are gone, test reducing TOS to 300% and bid to $0.30. Log and compare:

```sql
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CHANGE_LOG`
  (change_id, experiment_id, change_date, change_type, campaign_id, field_changed, old_value, new_value, reason)
VALUES
  ('LOLLIBOX_BD_002', 'LOLLIBOX_BRAND_DEFENSE_BRAND', CURRENT_DATE(),
   'TOS_CHANGE', 'YOUR_SP_CAMPAIGN_ID', 'top_of_search_pct', '500', '300',
   'Competitors gone from brand search. Testing if 300% TOS maintains position 1 at lower cost.');
```

**Phase 4:** Graduate the lowest-cost configuration that maintains position 1.

**Audit: which parent families have/don't have BRAND_DEFENSE?**

```sql
SELECT
  families.parent_name,
  families.child_count,
  families.children,
  e.experiment_id, e.status as exp_status, e.start_date,
  ec.campaign_name, ec.campaign_id,
  vcs.campaign_budget as amazon_daily_budget,
  vcs.top_of_search_pct, vcs.avg_keyword_bid, vcs.num_keywords,
  bh.days_running, bh.ads_net_profit, bh.ads_net_roas,
  bh.budget_utilization_pct, bh.data_status
FROM (
  SELECT parent_name,
    COUNT(*) as child_count,
    STRING_AGG(product_short_name, ', ' ORDER BY product_short_name) as children
  FROM `onyga-482313.OI.DIM_PRODUCT`
  WHERE parent_name IS NOT NULL AND asin != 'UNKNOWN' AND listing_price_amount > 0
  GROUP BY 1
) families
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON e.strategy_id = 'BRAND_DEFENSE' AND e.status = 'ACTIVE'
  AND LOWER(e.experiment_id) LIKE CONCAT('%', LOWER(REPLACE(families.parent_name, ' ', '_')), '%')
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON ec.experiment_id = e.experiment_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
  ON vcs.experiment_id = e.experiment_id AND vcs.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  ON bh.experiment_id = e.experiment_id
ORDER BY
  CASE WHEN e.experiment_id IS NULL THEN 0 ELSE 1 END,
  families.parent_name;
```

Rows with NULL `experiment_id` = parent family has no BRAND_DEFENSE. Check: `top_of_search_pct` should be 300-500%.

---

#### SEASONAL_PUSH

**Goal:** Maximum visibility during holiday periods for high-intent gift shoppers.

**When to use:** 2-3 weeks before major holidays (Valentine's, Mother's Day, Christmas).
**When NOT to use:** Off-season. This is expensive.

**Starting setup:**
- Campaign 1 (required): SP Exact, UP_AND_DOWN, bid $0.75-$3.00, budget $50/day, TOS 500%, PP 200%
- Campaign 2 (required): SB Video Exact, UP_AND_DOWN, bid $0.75-$2.50, budget $35/day
- Campaign 3 (optional): SB Store Broad, UP_AND_DOWN, bid $0.50-$2.00, budget $15/day
- Keywords: proven seasonal terms from SQP `holiday_*` columns.

| Week | What to expect | Action |
|------|---------------|--------|
| Pre-holiday | Set up 2-3 weeks before. Start at 50% budget. | Gradually increase budget as holiday approaches. |
| Holiday week | Volume spikes 2-5x. Budget may exhaust quickly. | Increase budget to 150%. |
| Post-holiday | Volume drops sharply. | Reduce to 50%, then pause within 1 week. |

**Key metric:** Total holiday orders + revenue ROAS during the window.
**Success:** Orders spike > 2x baseline and ROAS > 1.0.
**Failure:** ROAS < 0.7 during holiday. Product may not be a strong gift item for that holiday.
**Common mistakes:** Starting too late (need 2-3 weeks ramp), not stopping after holiday, using normal-season bids.

**Audit: which ASINs have/don't have SEASONAL_PUSH?**

```sql
SELECT
  p.asin, p.product_short_name, p.parent_name,
  e.experiment_id, e.status as exp_status, e.start_date, e.end_date,
  e.season_context,
  ec.campaign_name, ec.campaign_id,
  vcs.campaign_budget as amazon_daily_budget,
  vcs.bidding_strategy, vcs.top_of_search_pct,
  bh.days_running, bh.ads_net_profit, bh.ads_net_roas,
  bh.budget_utilization_pct, bh.data_status
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON e.strategy_id = 'SEASONAL_PUSH'
  AND e.status IN ('ACTIVE', 'COMPLETED')
  AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec2
    JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec2.campaign_id = fa.campaign_id
    WHERE ec2.experiment_id = e.experiment_id AND fa.advertised_asins = p.asin
  )
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON ec.experiment_id = e.experiment_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
  ON vcs.experiment_id = e.experiment_id AND vcs.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  ON bh.experiment_id = e.experiment_id
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  AND p.listing_price_amount > 0
ORDER BY
  CASE WHEN e.experiment_id IS NULL THEN 0 ELSE 1 END,
  p.parent_name, p.product_short_name;
```

Includes COMPLETED experiments so you can see past seasonal history. Check `season_context` and `end_date` to verify holidays were properly bounded.

---

#### TOS_DOMINATION

**Goal:** Lock position 1 for your top 2-3 keywords. Visibility play, not efficiency play.

**When to use:** Most important keywords where being #1 matters more than short-term ROAS.
**When NOT to use:** More than 3 keywords. Unproven keywords. Tight budgets.

**Starting setup:**
- Campaign 1 (required): SP Exact, DOWN_ONLY, bid $1.00-$3.00, budget $50/day, TOS 900%
- Campaign 2 (required): SB Video Exact, bid $0.75-$2.00, budget $25/day
- Max 2-3 keywords only.

| Week | What to expect | Action |
|------|---------------|--------|
| 1 | Very high TOS impression share (50%+). Expensive CPC. | Verify position 1. If not, raise bid. |
| 2 | ROAS may be 0.5-1.5. Value is in organic rank lift. | Check SQP organic impression share. |
| 3-4 | Organic rank should improve if working. | If organic share not increasing, keyword may be too competitive. |

**Key metric:** TOS impression share > 50% + organic rank improvement.
**Success:** Organic rank improves and holds after reducing spend. `parent_family_net_roas` > 1.0.
**Failure:** After 4 weeks, no organic rank improvement. Stop and redirect budget.
**Common mistakes:** Too many keywords (pick 2-3 max), expecting direct ROAS, running without monitoring organic rank.

**Audit: which ASINs have/don't have TOS_DOMINATION?**

```sql
SELECT
  p.asin, p.product_short_name, p.parent_name,
  e.experiment_id, e.status as exp_status, e.start_date,
  ec.campaign_name, ec.campaign_id,
  vcs.campaign_budget as amazon_daily_budget,
  vcs.top_of_search_pct, vcs.avg_keyword_bid, vcs.num_keywords,
  bh.days_running, bh.ads_net_profit, bh.ads_net_roas,
  bh.budget_utilization_pct, bh.data_status
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON e.strategy_id = 'TOS_DOMINATION' AND e.status = 'ACTIVE'
  AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec2
    JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec2.campaign_id = fa.campaign_id
    WHERE ec2.experiment_id = e.experiment_id AND fa.advertised_asins = p.asin
  )
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON ec.experiment_id = e.experiment_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
  ON vcs.experiment_id = e.experiment_id AND vcs.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  ON bh.experiment_id = e.experiment_id
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  AND p.listing_price_amount > 0
ORDER BY
  CASE WHEN e.experiment_id IS NULL THEN 0 ELSE 1 END,
  p.parent_name, p.product_short_name;
```

Check: `top_of_search_pct` should be ~900%, `num_keywords` should be 2-3 max. Most ASINs won't have this -- only your top performers need it.

---

#### NEW_LAUNCH

**Goal:** Build initial sales velocity for a brand new ASIN. Accept lower ROAS initially.

**When to use:** First 4-8 weeks of a new product. No existing sales data.
**When NOT to use:** Established products. Use EXACT_BOOST instead.

**Starting setup:**
- Campaign 1 (required): SP Exact, DOWN_ONLY, bid $0.75-$2.50, budget $45/day, TOS 400%, PP 200%
- Campaign 2 (required): SP Auto, UP_AND_DOWN, bid $0.50-$1.50, budget $25/day
- Campaign 3 (required): SB Video Broad, UP_AND_DOWN, bid $0.60-$2.00, budget $30/day
- Campaign 4 (optional): SB Store Broad, DOWN_ONLY, bid $0.40-$1.50, budget $15/day

| Week | What to expect | Action |
|------|---------------|--------|
| 1-2 | Low CVR, ROAS < 0.5. New listing, few reviews. | Normal. Focus on getting first 5-10 orders for reviews. |
| 3-4 | CVR improves with reviews. ROAS climbing toward 0.7-1.0. | Harvest converting terms from Auto. Refine exact keywords. |
| 5-6 | Organic impressions starting. Some terms ranking. | Promote best terms to EXACT_BOOST. Reduce Auto budget. |
| 7-8 | Transition out of launch. Close underperformers. | Switch to standard: LOW_COST_DISCOVERY + EXACT_BOOST. |

**Key metric:** First 10 orders velocity + review timing + organic impression share growth.
**Success:** 1+ orders/day organically by week 8. Transition to standard strategies.
**Failure:** After 8 weeks, < 5 total orders despite $500+ spend. Listing problem (photos, title, price), not traffic.
**Common mistakes:** Giving up too early (week 2 ROAS will be terrible), not transitioning to EXACT_BOOST, running all 4 campaigns on tight budget.

**Audit: which ASINs have/don't have NEW_LAUNCH?**

```sql
SELECT
  p.asin, p.product_short_name, p.parent_name,
  e.experiment_id, e.status as exp_status, e.start_date,
  ec.campaign_name, ec.campaign_id,
  vcs.campaign_budget as amazon_daily_budget,
  vcs.bidding_strategy, vcs.primary_match_type,
  vcs.top_of_search_pct,
  bh.days_running, bh.ads_net_profit, bh.ads_net_roas,
  bh.budget_utilization_pct, bh.data_status
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON e.strategy_id = 'NEW_LAUNCH' AND e.status IN ('ACTIVE', 'COMPLETED')
  AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec2
    JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec2.campaign_id = fa.campaign_id
    WHERE ec2.experiment_id = e.experiment_id AND fa.advertised_asins = p.asin
  )
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON ec.experiment_id = e.experiment_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
  ON vcs.experiment_id = e.experiment_id AND vcs.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  ON bh.experiment_id = e.experiment_id
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  AND p.listing_price_amount > 0
ORDER BY
  CASE WHEN e.experiment_id IS NULL THEN 0 ELSE 1 END,
  p.parent_name, p.product_short_name;
```

Includes COMPLETED so you can see launch history. If `days_running` > 56 and still ACTIVE, it's time to transition out of launch mode.

---

#### PRODUCT_DEFENSE

**Goal:** Prevent competitor ads on your product detail pages.

**When to use:** Competitors are running product targeting ads on your ASINs.
**When NOT to use:** No competitor activity on your listings.

**Starting setup:** 1 SP Product Targeting, DOWN_ONLY, bid $0.30-$0.75, budget $20/day, PP 300%.

| Week | What to expect | Action |
|------|---------------|--------|
| 1 | Your ads appear on your own pages instead of competitors'. | Verify product page impression share. |
| 2+ | Low spend. Only fires when competitors bid on your pages. | Check monthly. Low maintenance. |

**Key metric:** Product page impression share + competitor displacement.
**Success:** Competitors gone from your listings. Spend stays low.
**Failure:** Rare. If spend very high, competitors are aggressive -- raise bids.
**Common mistakes:** Budget too high, running preemptively without evidence of competitor targeting.

**Audit: which ASINs have/don't have PRODUCT_DEFENSE?**

```sql
SELECT
  p.asin, p.product_short_name, p.parent_name,
  e.experiment_id, e.status as exp_status, e.start_date,
  ec.campaign_name, ec.campaign_id,
  vcs.campaign_budget as amazon_daily_budget,
  vcs.bidding_strategy, vcs.product_page_pct,
  bh.days_running, bh.ads_net_profit, bh.ads_net_roas,
  bh.budget_utilization_pct, bh.data_status
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON e.strategy_id = 'PRODUCT_DEFENSE' AND e.status = 'ACTIVE'
  AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec2
    JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec2.campaign_id = fa.campaign_id
    WHERE ec2.experiment_id = e.experiment_id AND fa.advertised_asins = p.asin
  )
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON ec.experiment_id = e.experiment_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
  ON vcs.experiment_id = e.experiment_id AND vcs.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  ON bh.experiment_id = e.experiment_id
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  AND p.listing_price_amount > 0
ORDER BY
  CASE WHEN e.experiment_id IS NULL THEN 0 ELSE 1 END,
  p.parent_name, p.product_short_name;
```

Check: `product_page_pct` should be ~300%, `bidding_strategy` should be DOWN_ONLY. Only needed if competitors target your listings.

---

#### RETARGETING

**Goal:** Re-engage past viewers/purchasers for repeat purchases and cross-sells.

**When to use:** Products with repeat purchase potential or complementary lines.
**When NOT to use:** One-time purchase products with no cross-sell.

**Starting setup:**
- Campaign 1 (required): SB Video Broad, DOWN_ONLY, bid $0.30-$1.00, budget $20/day, TOS 100%, PP 100%
- Campaign 2 (optional): SB Store Broad, DOWN_ONLY, bid $0.25-$0.75, budget $15/day

| Week | What to expect | Action |
|------|---------------|--------|
| 1-2 | Small audience, low impressions. Building pool. | Don't judge yet. |
| 3-4 | Audience grows. High CVR (people know your brand). | If CVR > 5%, scale budget. |
| 4+ | Steady repeat purchases. ROAS 2-5x. | Maintain. Refresh creative quarterly. |

**Key metric:** CVR (should be highest of all strategies) + repeat purchase rate.
**Success:** CVR > 5%, ROAS > 2.0, driving measurable repeat purchases.
**Failure:** After 4 weeks, audience pool too small (< 1000 viewers). Not enough traffic.
**Common mistakes:** Expecting immediate results, using same creative as non-retargeting campaigns.

**Audit: which ASINs have/don't have RETARGETING?**

```sql
SELECT
  p.asin, p.product_short_name, p.parent_name,
  e.experiment_id, e.status as exp_status, e.start_date,
  ec.campaign_name, ec.campaign_id,
  vcs.campaign_budget as amazon_daily_budget,
  vcs.bidding_strategy, vcs.top_of_search_pct, vcs.product_page_pct,
  bh.days_running, bh.ads_net_profit, bh.ads_net_roas,
  bh.budget_utilization_pct, bh.data_status
FROM `onyga-482313.OI.DIM_PRODUCT` p
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
  ON e.strategy_id = 'RETARGETING' AND e.status = 'ACTIVE'
  AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec2
    JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec2.campaign_id = fa.campaign_id
    WHERE ec2.experiment_id = e.experiment_id AND fa.advertised_asins = p.asin
  )
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON ec.experiment_id = e.experiment_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
  ON vcs.experiment_id = e.experiment_id AND vcs.campaign_id = ec.campaign_id
LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  ON bh.experiment_id = e.experiment_id
WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
  AND p.listing_price_amount > 0
ORDER BY
  CASE WHEN e.experiment_id IS NULL THEN 0 ELSE 1 END,
  p.parent_name, p.product_short_name;
```

Only relevant for products with repeat purchase potential. Check: `bidding_strategy` should be DOWN_ONLY, should have both `top_of_search_pct` and `product_page_pct` at ~100%.

---

To customize recipes, edit `DIM_STRATEGY_CAMPAIGN_TEMPLATE` directly:

```sql
SELECT strategy_id, campaign_seq, ad_format, match_type,
  bid_min, bid_max, daily_budget, top_of_search_pct, product_page_pct,
  is_required, purpose
FROM `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE`
ORDER BY strategy_id, campaign_seq;
```

---

## 7. Search Term Segmentation

Every search term is tagged with 4 independent dimensions:

### Dimension 1: Intent Segment (who are they looking for?)

| Segment | Meaning | Example |
|---------|---------|---------|
| BRAND | Looking for Happy Lolli | "happy lolli journal kit" |
| COMPETITOR | Looking for a rival brand | "claires accessories" |
| PRODUCT | Looking for your exact product type | "journal kit for girls" |
| CATEGORY | Browsing the category | "cute diary for girls" |
| GIFT | Shopping for a gift | "10 year old girl gifts" |
| GENERIC | Everything else | "amazon mystery box" |

### Dimension 2: Occasion

BIRTHDAY, CHRISTMAS, SLEEPOVER, PARTY, VALENTINES, BACK_TO_SCHOOL, EASTER, GRADUATION, NO_OCCASION

### Dimension 3: Age Group

AGE_5_7, AGE_8_10, AGE_11_14, TWEEN, TEEN, COLLEGE, NO_AGE

### Dimension 4: Product Match (which Happy Lolli product?)

| Product Match | Maps To |
|---------------|---------|
| LOLLIME_JOURNAL | B0F9XFXQRW (Pink), B0F9X95K5H (Mint), B0F9XDSVYB (Purple) |
| LOLLIBOX_GIFT | B09XQ56RK5, B0C1VLXYBP, B0CR6N3WRC, B0DJFG5ZJ7 |
| TRUTH_OR_DARE | B0F4KCCSWN |
| POWER_SHOWER | B0D7N2MLDP (Beige), B0D7N31M6S (Pink) |
| NO_MATCH | Generic terms not specific to a product line |

### Derived dimension: Experiment Segment

The 4 dimensions above are analytical. For experiment targeting, the system derives a 5th column called `experiment_segment` that combines intent_segment + occasion + age_group + product_match into actionable, non-overlapping groups. Priority order (first match wins):

| experiment_segment | Rule | What it captures |
|---|---|---|
| BRAND | intent_segment = BRAND | People searching your brand/product names (happy lolli, lollibox, etc.) |
| PRODUCT | product_match is not NO_MATCH/MULTI_MATCH (and not BRAND) | Generic terms that match your product category (gift box, surprise box, etc.) |
| ACTIVITY | occasion = SLEEPOVER or PARTY | Activity-specific niche (Truth Or Dare sweet spot) |
| BIRTHDAY_KIDS | occasion = BIRTHDAY, age = 8-14 | High-intent birthday shoppers for your core audience |
| BIRTHDAY_TEEN | occasion = BIRTHDAY, age = TEEN/TWEEN | Birthday shoppers for older kids |
| BIRTHDAY_GENERAL | occasion = BIRTHDAY, other ages | Birthday terms without clear age targeting |
| CHRISTMAS | occasion = CHRISTMAS | Seasonal: only active during ramp-up window |
| EASTER | occasion = EASTER | Seasonal: only active during ramp-up window |
| VALENTINES | occasion = VALENTINES | Seasonal: only active during ramp-up window |
| BACK_TO_SCHOOL | occasion = BACK_TO_SCHOOL | Seasonal: only active during ramp-up window |
| GRADUATION | occasion = GRADUATION | Seasonal: only active during ramp-up window |
| GIFT_KIDS | no occasion, age = 5-14 | General gift shoppers looking for kids |
| GIFT_TEEN | no occasion, age = TEEN/TWEEN | General gift shoppers looking for teens |
| GIFT_GENERAL | everything else | Broad generic gift terms |

**Why this matters for experiments:**
- `intent_segment` is too coarse for gift-focused catalogs (80%+ of terms are GIFT)
- `experiment_segment` creates groups with similar buyer behavior, conversion patterns, and bid strategies
- Each experiment targets one `experiment_segment`, producing focused keyword lists

**Experiment naming convention:**

`{PRODUCT}_{STRATEGY}_{EXPERIMENT_SEGMENT}`

Examples:
- `WHITE_LOLLIBOX_BRAND_DEFENSE_BRAND` -- defend brand name searches
- `WHITE_LOLLIBOX_EXACT_BOOST_BIRTHDAY_KIDS` -- birthday terms for 8-14 year olds
- `TRUTH_OR_DARE_EXACT_BOOST_ACTIVITY` -- sleepover and party terms
- `WHITE_LOLLIBOX_SEASONAL_PUSH_CHRISTMAS` -- Christmas holiday terms
- `MINT_LOLLIME_HUNTER_GIFT_GENERAL` -- broad discovery for generic gift terms

---

## 8. Placement & Ad Format Analysis

### Ad format derivation

Since the Amazon API does not provide a creative type field, ad format is derived from campaign naming conventions:

| `ad_format` | Rule | Campaign name example |
|-------------|------|-----------------------|
| `SP` | campaign_type = SP | Any SP campaign |
| `SB_VIDEO` | SB + name contains "VIDEO" | `ME-VIDEO/EXACT (Mint journal)` |
| `SB_STORE` | SB + name contains "STORE" | `BOX-STORE/BROAD` |
| `SB_OTHER` | SB + neither VIDEO nor STORE | `ME-EXACT/Compete` |

**Important:** Name your SB campaigns with `VIDEO` or `STORE` in the name for automatic classification.

### Two levels of placement data

1. **Search term level** (`V_EXPERIMENT_SEARCH_TERMS`): Shows SP vs SB_VIDEO vs SB_STORE per search term, plus Search_Results vs Product_Page placement. Use this to see which format drives the best ROAS for a specific keyword.

2. **Strategy level** (`V_EXPERIMENT_PLACEMENT_LEARNINGS`): Aggregates across experiments within each strategy. Uses the granular placement report (TOP_OF_SEARCH, REST_OF_SEARCH, DETAIL_PAGE). Use this to learn placement best practices per strategy template.

**Note:** The Amazon search term report only provides `Search_Results` vs `Product_Page` placement. The more granular `TOP_OF_SEARCH` vs `REST_OF_SEARCH` split is only available at the campaign level (in `V_CAMPAIGN_PLACEMENT_REPORT` and `V_EXPERIMENT_PLACEMENT_LEARNINGS`).

---

### Query segmented data

```sql
-- See your search terms by experiment_segment
SELECT experiment_segment, occasion, age_group, product_match,
  COUNT(*) as terms,
  ROUND(SUM(amazon_avg_weekly_orders), 0) as market_weekly_orders,
  SUM(your_total_orders + ads_total_orders) as total_orders,
  ROUND(AVG(your_orders_share_pct), 2) as avg_share
FROM `onyga-482313.OI.V_SEARCH_TERM_SEGMENT`
WHERE asin = 'B0F9XFXQRW'
GROUP BY 1, 2, 3, 4
HAVING market_weekly_orders > 10
ORDER BY total_orders DESC;
```

---

## 9. Net ROAS & Profitability

### What is net ROAS?

**Net ROAS** is the primary profitability metric. It answers: "For every $1 spent on ads, how many dollars of profit did I generate?"

```
margin_per_unit = selling_price - TOTAL_COST_PER_UNIT
net_revenue     = TOTAL_units_sold * margin_per_unit
net_roas        = net_revenue / ad_spend
```

- **`net_roas > 1.0`** = profitable (every $1 in ads generates > $1 in total profit)
- **`net_roas = 1.0`** = break-even
- **`net_roas < 1.0`** = losing money

`TOTAL_units_sold` includes both ads-driven and organic units. This is intentional -- ads drive organic growth too (the "organic halo" effect). The ad spend is the investment; the total business result is the return.

### Example

White Lollibox sells for $54.40, TOTAL_COST_PER_UNIT ~$26.70 (COGS + FBA fees + shipping):
- Ads generate 5 units for $50 ad spend, and there were 5 organic units as well
- `net_revenue = 10 * (54.40 - 26.70) = $277.00` (all 10 units contribute)
- `net_roas = 277.00 / 50.00 = 5.54` (profitable -- $5.54 profit per $1 ad spend)

Compare to traditional ROAS = `(5 * 54.40) / 50.00 = 5.44` -- misses costs and organic halo.

### Four levels of net ROAS

| Level | Metric | Formula | What it captures |
|-------|--------|---------|------------------|
| **Family** | `parent_family_net_roas` | all sibling units × margin / all sibling ad spend | Cross-sibling halo across the family |
| **ASIN** | `asin_net_roas` | ASIN total units × margin / all ASIN ad spend | True ASIN profitability (organic + ads) |
| **Ads** | `ads_net_roas` | ad-attributed units × margin / experiment ad spend | Direct ad profitability per experiment |
| **SQP** | `sqp_net_roas` | SQP purchases × margin / experiment ad spend | Per-search-term organic + ads |

All use `net_roas = margin / ad_spend` where margin = `selling_price - TOTAL_COST_PER_UNIT`.

### Data sources

- `selling_price`: `DIM_PRODUCT.listing_price_amount`
- `TOTAL_COST_PER_UNIT`: `DIM_COSTS_HISTORY.TOTAL_COST_PER_UNIT` (COGS + FBA fees + shipping). Single source of truth -- sourced from `DE_PURCHASE_ORDERS`, `DE_MANUFACTURER_SHIPMENTS`, and Amazon `fee_preview_report`.
- ASIN units: `FACT_AMAZON_PERFORMANCE_DAILY.PURCHASED_UNITS` (Business Reports)
- Ad data: `FACT_AMAZON_ADS` (Fivetran sync)
- SQP data: `FACT_SEARCH_QUERY` (manual SQP uploads, ~2 week lag)

### Where net ROAS appears

- `V_PARENT_HERO_ASIN`: hero ranking by organic potential (CVR × CTR × margin) + ad profitability context
- `V_EXPERIMENT_BUDGET_HEALTH`: 4-tier ROAS per experiment
- `V_EXPERIMENT_TERM_RECOMMENDATIONS`: per-term ads + SQP ROAS with reasons
- `V_EXPERIMENT_SUGGESTED_CAMPAIGNS`: proven ROAS from ASIN conclusions
- `FACT_ASIN_CONCLUSIONS`: strategy-level proven ROAS

---

## 10. Budget Health Monitoring

### The budget health dashboard

`V_EXPERIMENT_BUDGET_HEALTH` provides real-time monitoring per experiment with 4 tiers:

| Tier | What it measures | Key columns |
|------|-----------------|-------------|
| **0 (Family)** | All siblings in the parent family combined | `parent_family_net_profit`, `parent_family_net_roas` |
| **1 (ASIN)** | This child's total performance (organic + ads) | `asin_net_profit`, `asin_net_roas` |
| **2 (Ads)** | This experiment's direct ad ROI | `ads_net_profit`, `ads_net_roas` |
| **3 (SQP)** | Per search term, organic + ads (~2 week lag) | `sqp_net_profit`, `sqp_net_roas` |

For all tiers: ROAS > 1.0 = profitable, = 1.0 = break-even, < 1.0 = losing money.

```sql
SELECT
  experiment_id, strategy_id, days_running, data_status,
  parent_name, parent_family_net_profit, parent_family_net_roas,
  asin_net_profit, asin_net_roas,
  ads_net_profit, ads_net_roas,
  sqp_net_profit, sqp_net_roas,
  ads_roas_trend
FROM `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH`
ORDER BY parent_family_net_profit DESC NULLS LAST;
```

### Data readiness

The `data_status` column tells you how much data is available:

| Status | Meaning |
|--------|---------|
| `NO_DATA` | No ad data yet. Campaign may not be active. |
| `COLLECTING` | Less than 7 days of data. Wait. |
| `ADS_DATA_READY` | 7+ days of Tier 1-2 data. Ads and ASIN metrics are reliable. |
| `ALL_TIERS_AVAILABLE` | SQP data also available. All 4 tiers are complete. |

### Manual decisions (no automated actions)

The system shows you the data and explains it. **You decide** what to do.

There are no automated budget actions. Use the tier metrics + term recommendations to make budget decisions. Over time, the conclusions system (`FACT_ASIN_CONCLUSIONS`) learns from outcomes.

---

## 10b. Search Term Recommendations (Per-Term Signals + Hero ASIN)

### What it does

`V_EXPERIMENT_TERM_RECOMMENDATIONS` answers two questions per search term:

1. **Should I KEEP, STOP, or PROMOTE this term?** (action + reason)
2. **Am I advertising the right ASIN for this term?** (hero_asin + is_hero_match)

Every row has a `reason` column that explains both the performance logic AND whether you're on the right child.

### How it works

For every search term served by experiment campaigns (last 60 days):
- Calculates `ads_net_profit` and `ads_net_roas` using actual unit margins
- Overlays SQP organic data for the organic+ads picture
- Produces an `action` signal with a human-readable `reason`
- Joins with `V_PARENT_HERO_ASIN` to identify the hero child for each term

### Hero ASIN columns

| Column | What it tells you |
|--------|-------------------|
| `hero_asin` | The child ASIN with the highest organic growth potential for this search term |
| `hero_product_name` | Human-readable name of the hero |
| `hero_score` | Organic potential score (blended CVR × CTR × margin) |
| `hero_sqp_cvr_pct` | Hero's SQP conversion rate on this term |
| `hero_ads_cvr_pct` | Hero's ads conversion rate on this term |
| `hero_confidence` | HIGH / MEDIUM / LOW / NO_DATA |
| `is_hero_match` | TRUE = you're advertising the right child. FALSE = switch. |

For **OPPORTUNITY** rows (action = START), the `asin` and `product_short_name` columns already show the hero ASIN. You don't need to look elsewhere.

### Actions

| Action | When it fires | What to do |
|--------|---------------|------------|
| **STOP** | $30+ spend with zero return, or ROAS < 0.5 with $20+ spend | Negate the term. If `is_hero_match = FALSE`, consider re-targeting with `hero_asin`. |
| **REDUCE_BID** | ROAS 0.5-0.7 with $15+ spend | Lower the bid by ~30%. Check if hero ASIN would convert better. |
| **PROMOTE_TO_EXACT** | Broad/auto term with 3+ profitable orders, not in an exact campaign | Create EXACT_BOOST using the `hero_asin` for this term. |
| **KEEP** | Ads ROAS >= 1.0, or SQP halo makes it worthwhile | Do nothing. If `is_hero_match = FALSE`, consider testing the hero ASIN. |
| **MONITOR** | < $5 spend | Wait for more data |
| **START** | SQP term with purchases, not targeted by any experiment | Advertise the `product_short_name` shown (already set to hero). |

### Example queries

```sql
-- AUDIT: which active terms are on the WRONG ASIN?
SELECT search_term, product_short_name as current_asin,
  hero_product_name as hero, hero_sqp_cvr_pct as hero_cvr,
  ads_spend, ads_orders, ads_net_roas, action, reason
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
WHERE recommendation_type = 'ACTIVE_TERM'
  AND is_hero_match = FALSE AND hero_asin IS NOT NULL
ORDER BY ads_spend DESC;
```

```sql
-- PROMOTE: which term should go to exact, and on which ASIN?
SELECT search_term, product_short_name as current_asin,
  hero_product_name as promote_this_asin, hero_sqp_cvr_pct,
  ads_orders, ads_net_profit, ads_net_roas, reason
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
WHERE action = 'PROMOTE_TO_EXACT'
ORDER BY ads_net_profit DESC;
```

```sql
-- START: untapped opportunities (product_short_name = hero ASIN to advertise)
SELECT search_term, product_short_name as advertise_this_asin,
  hero_sqp_cvr_pct, sqp_purchases,
  strategy_id as suggested_strategy, reason
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
WHERE recommendation_type = 'OPPORTUNITY'
ORDER BY priority_score DESC
LIMIT 20;
```

```sql
-- Summary: how many terms per action per strategy
SELECT strategy_id, action, COUNT(*) as terms,
  ROUND(SUM(ads_spend), 0) as total_spend,
  SUM(ads_orders) as total_orders,
  ROUND(SUM(ads_net_profit), 0) as total_profit
FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
WHERE recommendation_type = 'ACTIVE_TERM' AND action != 'MONITOR'
GROUP BY 1, 2
ORDER BY strategy_id, action;
```

---

## 11. ASIN Conclusions (Learning System)

### What are ASIN conclusions?

`FACT_ASIN_CONCLUSIONS` stores proven recipes from completed experiments. When you complete multiple experiments on an ASIN, the system aggregates results into a "conclusion" -- the best strategy, ad format, bids, and budget that worked.

### Lifecycle: DRAFT -> ENABLED

1. **SP_UPDATE_ASIN_CONCLUSIONS** runs daily (after experiment snapshots). It aggregates completed experiment results and creates/updates **DRAFT** rows.
2. While **DRAFT**, re-running the procedure overwrites with the latest data.
3. You manually set `status = 'ENABLED'` after reviewing the conclusion.
4. Once **ENABLED**, the conclusion is immutable -- the system never overwrites it.
5. **ENABLED** conclusions feed back into `V_EXPERIMENT_SUGGESTED_CAMPAIGNS` as proven budgets.

### Review conclusions (with parent-family context)

```sql
-- See all DRAFT conclusions with parent-family impact
SELECT
  asin, product_short_name, strategy_id, experiment_segment, season_context,
  -- 3-tier ROAS
  ads_only_net_roas, sqp_net_roas, asin_net_roas,
  -- Parent family cross-sibling impact
  parent_name,
  parent_family_net_profit,
  parent_family_net_roas,
  parent_family_ad_spend,
  parent_family_units,
  -- Data
  total_ad_spend, total_experiment_days,
  -- Auto-generated learning
  learning_summary
FROM `onyga-482313.OI.FACT_ASIN_CONCLUSIONS`
WHERE status = 'DRAFT'
ORDER BY parent_family_net_profit DESC NULLS LAST;
```

```sql
-- Enable a conclusion (makes it permanent, feeds into future suggestions)
UPDATE `onyga-482313.OI.FACT_ASIN_CONCLUSIONS`
SET
  status = 'ENABLED',
  enabled_at = CURRENT_TIMESTAMP()
WHERE asin = 'B0F9XFXQRW'
  AND experiment_segment = 'BIRTHDAY_KIDS'
  AND season_context = 'NORMAL'
  AND status = 'DRAFT';
```

### How conclusions improve suggestions

When `V_EXPERIMENT_SUGGESTED_CAMPAIGNS` generates campaign recommendations:
- If an **ENABLED** conclusion exists for the ASIN + segment + season:
  - Uses `proven_daily_budget` instead of template default
  - Uses `proven_bid_min` / `proven_bid_max` instead of template defaults
  - Shows `budget_confidence = 'HIGH'`
- If no conclusion exists:
  - Uses strategy template defaults
  - Shows `budget_confidence = 'LOW'`

---

## 12. Seasonal Budget Behavior

### How peak season affects the system

During peak season (holiday ramp-up windows from `DIM_US_HOLIDAYS`):

1. **Budget suggestions**: `V_EXPERIMENT_SUGGESTED_CAMPAIGNS` applies `peak_budget_multiplier` from `DIM_STRATEGY_TEMPLATE` (typically 1.5-2.5x).
2. **ASIN conclusions**: Stored separately for `season_context = 'PEAK'` vs `'NORMAL'`, because peak-season behavior is fundamentally different.
3. **Peak flag**: `V_EXPERIMENT_BUDGET_HEALTH` shows `is_peak_season = TRUE` and `current_holiday` so you know context when making decisions.

### Interpreting seasonal results

Peak season experiments should be compared to peak baselines, not normal-season ones. The system handles this through:
- Separate `PEAK` conclusions in `FACT_ASIN_CONCLUSIONS`
- `is_peak_season` flag in `V_EXPERIMENT_BUDGET_HEALTH`

```sql
-- Compare NORMAL vs PEAK conclusions for an ASIN
SELECT
  season_context, experiment_segment,
  proven_net_roas, proven_daily_budget,
  best_strategy_id, experiment_count
FROM `onyga-482313.OI.FACT_ASIN_CONCLUSIONS`
WHERE asin = 'B0F9XFXQRW'
ORDER BY season_context, experiment_segment;
```

---

## 13. Known Gaps and Limitations

Issues identified during system testing. Updated 2026-02-09.

### GAP 1: 4-tier measurement dashboard (RESOLVED)

Each tier shows **net profit** (actual $) and **net ROAS** (normalized ratio). No auto actions -- you decide.

| Tier | Metrics | Source | What it captures |
|------|---------|--------|------------------|
| Tier 0 (Family) | `parent_family_net_profit`, `parent_family_net_roas` | FACT_AMAZON_PERFORMANCE_DAILY + FACT_AMAZON_ADS | Cross-sibling halo across parent family |
| Tier 1 (ASIN) | `asin_net_profit`, `asin_net_roas` | FACT_EXPERIMENT_DAILY + FACT_AMAZON_ADS | Total ASIN performance (organic + ads) |
| Tier 2 (Ads) | `ads_net_profit`, `ads_net_roas` | FACT_EXPERIMENT_DAILY | Direct ad ROI per experiment |
| Tier 3 (SQP) | `sqp_net_profit`, `sqp_net_roas` | FACT_SEARCH_QUERY | Per search term, organic + ads (~2 week lag) |

Additionally, `V_PARENT_HERO_ASIN` ranks children within each family by ad profitability.

You review the tiers, read the reasons, and decide. The conclusions system learns from outcomes over time.

### GAP 2: Multi-ASIN experiments (OPERATIONAL FIX)

**Decision**: Target only one ASIN per campaign in Amazon Ads. This is an operational choice, not a code fix.

**Impact**: Only affects the Tier 1 `net_roas` reference metric. Tier 2 and Tier 3 are unaffected because they attribute at the ad/search-term level.

### GAP 3: Conclusions system (RESOLVED)

**Previous problem**: `SP_UPDATE_ASIN_CONCLUSIONS` only processed COMPLETED experiments.

**Fix**: The procedure now processes ACTIVE experiments with 14+ days of data. Key changes:
- **Grain**: Per `asin + strategy_id + experiment_segment + season_context` (was per ASIN only)
- **Status lifecycle**: DRAFT (auto-updated) / DISABLED (user excludes) -- no ENABLED status
- **Metrics**: 3-tier ROAS (ads_only, SQP, ASIN-level), per ad-format breakdown (SP vs SB_VIDEO vs SB_STORE)
- **Learning summary**: Auto-generated text per strategy, e.g. "EXACT_BOOST on White Lollibox (GIFT_TEEN/NORMAL): PROFITABLE ads ROAS 1.65, SQP ROAS 1.12. SP ROAS=2.1 VIDEO ROAS=0.8."
- **Schedule**: Runs daily in orchestrator; meaningful conclusions appear after 14 days

### GAP 4: SQP pipeline was broken (RESOLVED)

**Previous problem**: `FACT_SEARCH_QUERY` was stuck at Jan 25 (1,522 rows) because `SP_LOAD_FACT_SEARCH_QUERY` read from `STG_SQP_WEEKLY` (OpenBridge, stale). The fresh data was in `SRC_ACC_SQP_WEEKLY` (51,092 rows up to Feb 14).

**Fix**: Changed `SP_LOAD_FACT_SEARCH_QUERY` to read from `SRC_ACC_SQP_WEEKLY` instead of `STG_SQP_WEEKLY`. Now 51,111 rows covering Sep 2024 to Feb 2026.

### GAP 5: MINT_LOLLIME_LOW_COST_DISCOVERY has no ad data

**Problem**: This experiment shows `NO_DATA` status. The campaign may not be active in Amazon Ads, or the campaign_id mapping may be incorrect.

**Action needed**: Verify in Amazon Ads console that the mapped campaign is active and spending. If not, update `DIM_EXPERIMENT_CAMPAIGN` with the correct campaign_id.

### GAP 6: SP_LOAD_COMPARE_QUANTITY_CLICKS_BY_ASIN has a column name bug

**Problem**: This procedure fails with `Unrecognized name: CLICKS`. Pre-existing bug, not related to the experiment system.

**Impact**: Does not affect experiment tracking or budget decisions. Affects only the comparison analytics table.

### GAP 7: Budget utilization calculation uses template budget, not actual Amazon budget

**Problem**: The `budget_utilization_pct` compares actual daily spend to the `DIM_STRATEGY_CAMPAIGN_TEMPLATE` budget. Actual Amazon campaign budgets may differ from templates.

**Future fix**: Store actual Amazon campaign budgets in `DIM_EXPERIMENT_CAMPAIGN` and use those for utilization calculations.
