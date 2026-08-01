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
| COGS (landed) | `UnifiedPerformance.cogs` | `V_UNIFIED_DAILY.cogs` | `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY` Step 1 | `DIM_COSTS_HISTORY.TOTAL_COST_PER_UNIT` × units (via `FN_COGS` UDF). **LANDED** = `cogs_goods + shipping_cost + pick_pack_cost + referral_cost` (goods + freight + FBA fulfillment + referral). |
| COGS — goods only | `UnifiedPerformance.cogsGoods` | `V_UNIFIED_DAILY.cogs_goods` | `V_UNIFIED_DAILY` `cost_components` CTE | units × `DIM_COSTS_HISTORY.cost_of_goods` (SCD2 date-range join) |
| Shipping (freight-in) | `UnifiedPerformance.shippingCost` | `V_UNIFIED_DAILY.shipping_cost` | `V_UNIFIED_DAILY` `cost_components` CTE | units × `DIM_COSTS_HISTORY.shipping_cost` (SCD2 date-range join) |
| Pick & Pack | `UnifiedPerformance.pickPackCost` | `V_UNIFIED_DAILY.pick_pack_cost` | `V_UNIFIED_DAILY` `cost_components` CTE | units × `DIM_COSTS_HISTORY.estimated_pick_pack_fee_per_unit` (SCD2 date-range join) |
| Referral Fee | `UnifiedPerformance.referralCost` | `V_UNIFIED_DAILY.referral_cost` | `V_UNIFIED_DAILY` `cost_components` CTE | units × `DIM_COSTS_HISTORY.FBA_COST_estimated_referral_fee_per_unit` (SCD2 date-range join) |
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


## Campaign → family attribution (canonical: V_DIM_CAMPAIGN_FAMILY)

`V_DIM_CAMPAIGN_FAMILY` is THE canonical campaign→family source (built 2026-08-01, Task D). One row per `campaign_id` (STRING) for ALL campaigns in `V_DIM_CAMPAIGN_CURRENT`, any state. Do not derive family from `campaign_name` tokens or by re-joining the ASIN chain in new views — join this view instead.

**Precedence** (in-view, documented in the header):
1. `family_source='manual'` — `DE_CAMPAIGN_FAMILY` (Admin Campaign Mapping panel). A deliberate human assignment always wins. Measured 2026-08-01: manual and the ASIN chain disagree on exactly 4 campaigns (BUNNY-VIDEO/BROAD (Hunter) → Bunny; 2× BRAND-STORE/BROAD and Brand - Auto Collection → Store; the chain says Lollibox for all 4) — precisely the ASIN-blind campaigns the DE table was created for, so manual-wins is a correctness rule, not a tie-break.
2. `family_source='asin_chain'` — dominant own-product family by lifetime ad spend. Per FACT row the family prefers `most_advertised_asin_impressions` (behavioral, survives renames) and falls back to name-parsed `ASIN_BY_CAMPAIGN_NAME` at FAMILY level. The family-level fallback matters: video/SB rows carry the literal string 'Unknown' as impressions-ASIN, so `COALESCE`-ing the ASIN strings (the pattern in V_ADS_COACH_DATA et al.) silently drops those campaigns (282 vs 294 covered). Only `DIM_PRODUCT.parent_name IS NOT NULL` rows count (DIM_PRODUCT also holds competitor ASINs).
3. `family_source IS NULL` — neither source knows (807/1113 on 2026-08-01; 783 ARCHIVED, 19 PAUSED, 5 ENABLED new zero-delivery campaigns). There is deliberately NO 'Unknown' catch-all — that fabrication belongs to `V_CAMPAIGN_FAMILY_MAP`'s budget-coverage guarantee only.

**Audit**: `SELECT * FROM V_DIM_CAMPAIGN_FAMILY WHERE family_source='manual' AND parent_name != asin_chain_parent_name` lists every override that changes the chain's answer.

**Migration debt** (existing consumers still deriving family on their own; repoint opportunistically, family attribution only — ASIN-grain economics stay put): V_CAMPAIGN_FAMILY_MAP.sql:13-28 (then its consumers V_FAMILY_NET_PROFIT_7D:12,24 · V_BUDGET_STEP1_FAMILY:25,30 · V_BUDGET_STEP1_CAMPAIGN:77 · V_CAMPAIGN_BUDGET_BASE:32 · V_CAMPAIGN_HALO:26 · tests/BUDGET_WATERFALL_INVARIANTS:8,21), V_CAMPAIGN_ROLE_BY_NAME.sql:36-45 (prefix-token map), V_KEYWORD_DAILY.sql:8, V_INTENT_COVERAGE.sql:29, V_PRODUCT_STRATEGY_OUTCOMES.sql:8, V_BRAND_STRENGTH_WEEKLY.sql:109, V_WEEKLY_CELL_NET.sql:20, V_CAMPAIGN_LAUNCH_MONTHLY.sql:42-45, V_OOB_BUDGET_PHASE.sql:99-103, V_ADS_COACH_DATA.sql:413+ (~30 sites, ASIN-grain — family part only), V_KEYWORD_INTELLIGENCE.sql:62,99.


## FACT_ADS_ADVERTISED_DAILY — advertised-ASIN-grain ads fact (SP only)

**Why it exists.** ~79% of ad-attributed purchases land on a different ASIN than the advertised one, and FACT_AMAZON_ADS (search-term grain) only approximates the advertised ASIN via `most_advertised_asin_impressions` / `ASIN_BY_CAMPAIGN_NAME` heuristics. Amazon reports advertised-product metrics directly; this table records them verbatim so per-product ad spend and P&L attribution are honest. 28d spot-check: the heuristic over-attributed one ASIN 2.4x ($1,076.54 vs $444.10 true), under-attributed another 8.5x, and missed a third entirely.

**Lineage.** `fivetran-hl.amazon_ads.advertised_product_report` → `V_SRC_AmazonAds_advertised_product` → `SP_LOAD_FACT_ADS_ADVERTISED_DAILY(reload_days)` → `FACT_ADS_ADVERTISED_DAILY`. Names enriched from DIM_CAMPAIGN / DIM_AD_GROUP current rows (Type-1, not as-of-date).

**Grain and load.** One row per date x ad_id x advertised_asin (also unique on date x campaign x ad group x ASIN). Loader is an idempotent MERGE: `NULL` = 30-day rolling window anchored on `CURRENT_DATE('America/Los_Angeles')`; pass `10000` for full history. Rows restated away by Fivetran inside the window are deleted (NOT MATCHED BY SOURCE, window-scoped); rows outside the window are never touched. The report `date` is already profile-local (LA) — no timezone conversion.

**Measures.** `Ads_impressions/Ads_clicks/Ads_cost` are exact (impressions here are the TRUE numbers; FACT_AMAZON_ADS term grain undercounts them ~3x). `Ads_orders/Ads_units/Ads_sales` use the 14d window (Amazon console convention), split into `*_same_sku_14d` (this ad sold THIS product) and `*_other_sku_14d` (halo on other ASINs, 42–88% of sales per ASIN); 7d trio included for coacher parity.

**Coverage caveats (by design).** SP only — Amazon has no advertised-ASIN report for SB (`sb_ad_report` is creative-grain, no ASIN; ~42% of spend), and SD's `sd_product_ad_report` has no ASIN column and negligible volume. History starts 2025-09-23 (vs 2024-09-05 for FACT_AMAZON_ADS). Spend runs ~1.4% below FACT_AMAZON_ADS SP totals (28d: $18,063.68 vs $18,325.86), spread thinly across all campaigns — report-level reconciliation noise, not missing campaigns. When building per-product P&L, take SP spend from this table and handle SB spend separately.


## FACT_AMAZON_ADS.TOTAL_COST_PER_UNIT / GROSS_PROFIT — price-tier COGS imputation (prepared 2026-08-01, NOT YET DEPLOYED)

SP_FACT_AMAZON_ADS now charges COGS by the product ACTUALLY SOLD, identified by sale price: `COALESCE(T_PRICE_COST_TIER.tier_cost, purchased-ASIN cost, impressions-ASIN cost, single-advertised-ASIN cost)`, tier matched on `units > 0 AND unit_price = ROUND(SAFE_DIVIDE(sales, units), 2)` — the same pattern V_ADS_NET_CORRECTED validated. Rationale: the advertised-ASIN chain mis-costs ~80% of ad-attributed units (cross-product sales) and mis-tiers discounted sales. Restatement measured Feb–Jul 2026: account COGS −$1,423.37 (−0.54%, GP up), but LolliME +$1,333.78 (+1.30%, its ad GP was over-credited) vs Lollibox −$1,729.72 / Fresh −$975.60; worst cell LolliME 2026-03 +$691.50 (+3.53%). 95.9% of units price-match a tier; the rest keep the advertised chain. On deploy the full FACT history restates at once (TRUNCATE+INSERT). Ordering note: the FACT load reads the previous run's T_PRICE_COST_TIER because SP_REFRESH_CUBE_TABLES runs last in SP_ORCHESTRATE_DAILY_REFRESH — fine for a 180-day rolling map. Consumers already applying COALESCE(tier_cost, TOTAL_COST_PER_UNIT) themselves (V_ADS_NET_CORRECTED, V_KEYWORD_LIFT, V_LAUNCH_PHASE1, V_OOB_KEYWORD, V_OOB_BUDGET_PHASE, V_RUN_TARGET) are idempotent and unaffected; everything reading FACT.GROSS_PROFIT raw (Cube Ads + UnifiedPerformance via V_UNIFIED_DAILY, the coacher stack, weekly-run/launch/coverage views) restates.
