# DB Field Lineage — Single Source of Truth

> Every dashboard field traced: **Source Table → Logic Owner (SP/View) → FACT/DIM → Cube → Dashboard Page**
>
> If you need to debug or modify a metric, check this file FIRST to find where the logic lives.

---

## Home Page — Header Cards & Family Table

### Source Chain
```
Fivetran raw tables → SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY → FACT_AMAZON_PERFORMANCE_DAILY
                                                              ↓
                                                     V_UNIFIED_DAILY (grain: asin × date)
                                                     ├── Cube: UnifiedPerformance (weekly/monthly trends)
                                                     └── V_SUMMARY_7D (grain: family)
                                                         └── Cube: Summary (header cards)
```

| Dashboard Field | Cube Measure/Dim | BQ View Column | Logic Owner | Source Tables |
|---|---|---|---|---|
| Sales | `UnifiedPerformance.sales` | `V_UNIFIED_DAILY.sales` | `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` Step 1 | `V_SRC_sales_and_traffic_business_sku_report_daily.ordered_product_sales_amount` |
| COGS | `UnifiedPerformance.cogs` | `V_UNIFIED_DAILY.cogs` | `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` Step 1 | `DIM_PRODUCT.total_cost` × units (via `FN_COGS` UDF) |
| Ads Spend | `UnifiedPerformance.adCost` | `V_UNIFIED_DAILY.ad_cost` | `V_UNIFIED_DAILY` join | `FACT_AMAZON_ADS.cost` (Fivetran → `V_SRC_AmazonAds_*`) |
| Ads Sales | `UnifiedPerformance.adSales` | `V_UNIFIED_DAILY.ad_sales` | `V_UNIFIED_DAILY` join | `FACT_AMAZON_ADS.sales` (Fivetran) |
| Ads Units | `UnifiedPerformance.adUnits` | `V_UNIFIED_DAILY.ad_units` | `V_UNIFIED_DAILY` join | `FACT_AMAZON_ADS.units` (Fivetran) |
| Net Profit | `UnifiedPerformance.netProfit` | Computed: `sales - ad_cost - cogs` | `UnifiedPerformance.js` (Cube) ✅ | — |
| NP/Unit | `UnifiedPerformance.npPerUnit` | Computed: `net_profit / units` | `UnifiedPerformance.js` (Cube) ✅ | — |
| Net ROAS | `UnifiedPerformance.netRoas` | Computed: `(sales - cogs) / ad_cost` | `UnifiedPerformance.js` (Cube) ✅ | — |
| TACoS | `UnifiedPerformance.tacos` | Computed: `ad_cost / sales × 100` | `UnifiedPerformance.js` (Cube) ✅ | — |
| Units | `UnifiedPerformance.units` | `V_UNIFIED_DAILY.units` | `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` Step 1 | `V_SRC_sales_and_traffic_*.units_ordered` |
| Total Orders | `UnifiedPerformance.orders` | `V_UNIFIED_DAILY.orders` | `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` Step 1 | `V_SRC_sales_and_traffic_*.total_order_items` |
| Organic Units | `UnifiedPerformance.organicUnits` | `V_UNIFIED_DAILY.organic_units` | `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` Step 3 | `units - ads_units` (ads from `FACT_AMAZON_ADS`) |
| Organic % | `UnifiedPerformance.organicPct` | Computed: `organic_units / units × 100` | `UnifiedPerformance.js` (Cube formula) | — |
| Clicks | `UnifiedPerformance.clicks` | `V_UNIFIED_DAILY.clicks` | `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` Step 2 | `FACT_AMAZON_ADS.clicks` |
| Sessions | `UnifiedPerformance.sessions` | `V_UNIFIED_DAILY.sessions` | `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` Step 1 | `V_SRC_sales_and_traffic_*.sessions` |

### Header Cards (Summary Cube)
| Dashboard Card | Cube Dim | BQ View Column | Logic Owner |
|---|---|---|---|
| Sales (7d) | `Summary.sales7d` | `V_SUMMARY_7D.sales_7d` | `V_SUMMARY_7D` aggregates `V_UNIFIED_DAILY` |
| Ads Spend (7d) | `Summary.adCost7d` | `V_SUMMARY_7D.ad_cost_7d` | `V_SUMMARY_7D` |
| Net Profit (7d) | `Summary.netProfit7d` | `V_SUMMARY_7D.net_profit_7d` | `V_SUMMARY_7D` |
| Net ROAS (7d) | `Summary.netRoas` | `V_SUMMARY_7D.net_roas` | `V_SUMMARY_7D` |
| Organic % (7d) | `Summary.organicPct` | `V_SUMMARY_7D.organic_pct` | `V_SUMMARY_7D`: `organic_units_7d / units_7d × 100` |

---

## Actions Page — Ads Coach

### Source Chain
```
FACT_AMAZON_ADS (Fivetran)  ──┐
FACT_SQP (manual upload)   ──┼── V_ADS_COACH_DECISION (grain: search_term)
DIM_PRODUCT                ──┘   ├── Cube: AdsCoachDecision
                                 ├── V_ADS_COACH_ACTIONS (grain: campaign × term)
                                 │   └── Cube: AdsCoachTerm
                                 └── V_ADS_COACH_CAMPAIGN (grain: campaign)
                                     └── Cube: AdsCoachCampaign
```

| Dashboard Field | Cube Dim | BQ View Column | Logic Owner |
|---|---|---|---|
| Signal (STOP/KEEP/etc) | `AdsCoachDecision.signal` | `V_ADS_COACH_DECISION.ads_signal` | `V_ADS_COACH_DECISION` CASE logic |
| Decision text | `AdsCoachDecision.decision` | `V_ADS_COACH_DECISION.decision` | `V_ADS_COACH_DECISION` CASE logic |
| Priority Score | `AdsCoachDecision.priorityScore` | `V_ADS_COACH_DECISION.priority_score` | `V_ADS_COACH_DECISION` scoring formula |
| Ads Spend 4w | `AdsCoachDecision.adsSpend4w` | `V_ADS_COACH_DECISION.ads_spend_4w` | `V_ADS_COACH_DECISION` → `FACT_AMAZON_ADS` last 4 weeks |
| SQP Organic Units 4w | `AdsCoachDecision.sqpOrganicUnits4w` | `V_ADS_COACH_DECISION.sqp_organic_units_4w` | `V_ADS_COACH_DECISION`: `sqp_orders - ads_orders` |
| Campaign Action | `AdsCoachCampaign.campaignAction` | `V_ADS_COACH_CAMPAIGN.campaign_action` | `V_ADS_COACH_CAMPAIGN` aggregates term decisions |
| Est Weekly Savings | `AdsCoachCampaign.estWeeklySavings` | `V_ADS_COACH_CAMPAIGN.est_weekly_savings` | `V_ADS_COACH_CAMPAIGN` |

---

## Experiment Page

### Source Chain
```
FACT_AMAZON_PERFORMANCE_DAILY ──┐
FACT_AMAZON_ADS               ──┼── SP_EXPERIMENT_DAILY_SNAPSHOT → FACT_EXPERIMENT_DAILY
FACT_SQP                      ──┘   ├── V_EXPERIMENT_RESULTS_ASIN (perf lift by ASIN)
DE_EXPERIMENTS                      ├── V_EXPERIMENT_RESULTS_SEARCH_TERM (SQP lift by term)
                                    ├── V_EXPERIMENT_SUMMARY (rolled up per experiment)
                                    │   └── Cube: Experiment
                                    ├── V_EXPERIMENT_BUDGET_HEALTH
                                    │   └── Cube: ExperimentBudgetHealth
                                    ├── V_EXPERIMENT_VARIATION_COMPARISON (period breakdown)
                                    └── Cube: ExperimentDaily (weekly aggregation)
```

| Dashboard Field | Cube Measure/Dim | BQ View/Table Column | Logic Owner |
|---|---|---|---|
| Organic Lift % | `Experiment.organicLiftPct` | `V_EXPERIMENT_SUMMARY.performance_organic_units_lift_pct` | `V_EXPERIMENT_RESULTS_ASIN` → `V_EXPERIMENT_SUMMARY` |
| Baseline Organic Units | — | `V_EXPERIMENT_SUMMARY.performance_baseline_organic_units` | `V_EXPERIMENT_RESULTS_ASIN.performance_bl_organic_units` |
| Experiment Organic Units | — | `V_EXPERIMENT_SUMMARY.performance_experiment_organic_units` | `V_EXPERIMENT_RESULTS_ASIN.performance_exp_organic_units` |
| Performance Total Orders | `ExperimentDaily.performanceTotalOrders` | `FACT_EXPERIMENT_DAILY.performance_total_orders` | `SP_EXPERIMENT_DAILY_SNAPSHOT` |
| Performance Organic Units | `ExperimentDaily.performanceOrganicUnits` | `FACT_EXPERIMENT_DAILY.performance_organic_units` | `SP_EXPERIMENT_DAILY_SNAPSHOT`: `total_orders - ads_orders` |
| Cumulative Organic Units | — | `FACT_EXPERIMENT_DAILY.cum_performance_organic_units` | `SP_EXPERIMENT_DAILY_SNAPSHOT` running SUM |
| Daily Experiment Snapshot | — | `SP_EXPERIMENT_WEEKLY_REVIEW` | Reads `V_EXPERIMENT_SUMMARY`, generates signals |

---

## SQP Page

### Source Chain
```
FACT_SQP (manual upload via tools/upload_sqp.py)
  └── Cube: Sqp (grain: asin × search_term × week)
```

| Dashboard Field | Cube Dim | BQ Column | Logic Owner |
|---|---|---|---|
| Show Rate % | `Sqp.showRatePct` | `FACT_SQP` computed | Cube formula or view |
| Organic Rank | `Sqp.estimatedOrganicRank` | `FACT_SQP.estimated_organic_rank` | `SP_LOAD_SQP` |
| SQP Orders | `Sqp.orders` | `FACT_SQP.your_purchases` | Fivetran/manual upload |

---

## Ads Performance Page

### Source Chain
```
V_SRC_AmazonAds_SearchTerms (Fivetran) ──┐
V_SRC_AmazonAds_keyword (Fivetran)     ──┼── FACT_AMAZON_ADS
campaign_history (Fivetran)             ──┘   └── Cube: Ads (grain: date × campaign × term)
```

| Dashboard Field | Cube Measure | BQ Column | Logic Owner |
|---|---|---|---|
| Spend | `Ads.spend` | `FACT_AMAZON_ADS.ad_spend` | Direct from Fivetran |
| Orders | `Ads.orders` | `FACT_AMAZON_ADS.orders` | Direct from Fivetran |
| ROAS | `Ads.roas` | `FACT_AMAZON_ADS.sales / ad_spend` | Cube formula |

---

## Data Entry Tables (Flask App)

| Table | Managed By | Used In |
|---|---|---|
| `DE_PURCHASE_ORDERS` | Flask data-entry app | PO management |
| `DE_PURCHASE_ORDER_LINES` | Flask data-entry app | PO line items |
| `DE_MANUFACTURER_SHIPMENTS` | Flask data-entry app | Shipment tracking |
| `DE_SHIPMENT_LINES` | Flask data-entry app | Shipment line items |
| `DE_VENDOR_PAYMENTS` | Flask data-entry app | Payment tracking |
| `DE_EXPERIMENTS` | Flask data-entry app | Experiment definitions |
| `DE_EXPERIMENT_CHANGE_LOG` | Flask data-entry app | Experiment audit trail |
| `DE_COACH_THRESHOLDS` | Flask data-entry app | Ads coach decision thresholds |

---

## Key Computed Fields — Where Logic Lives

| Metric | Single Logic Owner | Formula |
|---|---|---|
| **Net Profit** | `UnifiedPerformance.js` (Cube) ✅ | `sales - ad_cost - cogs` |
| **Net ROAS** | `UnifiedPerformance.js` (Cube) ✅ | `(sales - cogs) / ad_cost` |
| **Organic %** | `UnifiedPerformance.js` (Cube) ✅ | `organic_units / units × 100` |
| **Organic Units** | `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` Step 3 ✅ | `units - ads_attributed_units` |
| **TACoS** | `UnifiedPerformance.js` (Cube) ✅ | `ad_cost / sales × 100` |
| **NP/Unit** | `UnifiedPerformance.js` (Cube) ✅ | `(sales - ad_cost - cogs) / units` |
| **Ads Signal** | `V_ADS_COACH_DECISION.sql` | Multi-rule CASE statement |
| **Experiment Organic Lift** | `V_EXPERIMENT_RESULTS_ASIN.sql` | `(exp_daily_organic - bl_daily_organic) / bl_daily_organic × 100` |
| **FN_ORGANIC_PCT** | `FN_ORGANIC_PCT.sql` (UDF) | `GREATEST(organic_units, 0) / total_units × 100` |
| **Ads Active Last 7d** | `V_ADS_COACH_DECISION.sql` ✅ | `ads_impressions_7d > 0` — flags stale STOP actions |

---

## Naming Conventions Reminder

| Prefix | Type | Example |
|---|---|---|
| `V_SRC_` | Fivetran interface view | `V_SRC_AmazonAds_keyword` |
| `V_` | Analytics view | `V_UNIFIED_DAILY` |
| `FACT_` | Fact table | `FACT_AMAZON_PERFORMANCE_DAILY` |
| `DIM_` | Dimension table | `DIM_PRODUCT` |
| `DE_` | Data-entry table | `DE_EXPERIMENTS` |
| `SP_` | Stored procedure | `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` |
| `FN_` | UDF | `FN_ORGANIC_PCT` |
