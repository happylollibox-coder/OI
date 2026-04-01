# FACT_AMAZON_PERFORMANCE_DAILY – Validation Report

## 1. Source table totals

| Source table | Scenario | Row count | Orders | Units | Sales (USD) |
|--------------|----------|-----------|--------|-------|-------------|
| **STG_AMAZON_ADS** | (all) | 303,999 | 18,953 | 19,099 | 828,270.21 |
| **STG_AmazonAds_purchased_product** | SB | 4,944 | 13,978 | 14,518 | 613,467.87 |
| **STG_AmazonAds_purchased_product** | SP | 2,178 | 2,258 | 2,313 | 97,700.95 |
| **STG_AMAZON_PERFORMANCE** | (IS_LOADED=TRUE) | 3,360 | 40,279 | 41,443 | 1,870,185.21 |

*Note: STG_AMAZON_ADS also has impressions = 18,039,262 and clicks = 440,586 (not stored per row in FACT).*

---

## 2. FACT table totals by scenario

| Scenario | Row count | Orders | Units | Sales (USD) | Total cost | Gross profit |
|----------|-----------|--------|-------|-------------|------------|--------------|
| **Ads – same-ASIN (purchased_product)** | 937 | 11,811 | 4,614 | 200,175.24 | 99,653.70 | 100,521.54 |
| **Ads – cross-sell (purchased_product)** | 6,185 | 0 | 12,217 | 510,993.58 | 246,152.79 | 264,840.79 |
| **Ads – fallback (STG_AMAZON_ADS)** | 4,847 | 2,198 | 2,246 | 88,110.68 | 38,918.46 | 49,192.22 |
| **Organic delta** | 3,360 | 27,464 | 22,823 | 1,089,689.76 | 522,586.08 | 567,103.68 |
| **FACT Ads total** | **11,969** | **14,009** | **19,077** | **799,279.50** | — | **414,554.54** |

---

## 3. Reconciliation: source vs FACT

| Check | Source total | FACT total | Difference |
|-------|--------------|------------|------------|
| Purchased_product (SB+SP) units | 16,831 | 16,831 | 0 ✓ |
| Purchased_product (SB+SP) sales | 711,169 | 711,169 | 0 ✓ |
| FACT Ads total units vs STG_AMAZON_ADS | 19,099 | 19,077 | -22 |
| FACT Ads total sales vs STG_AMAZON_ADS | 828,270 | 799,280 | -28,990 |

- **Purchased_product**: Units and sales from SB+SP match exactly between source and FACT.
- **FACT Ads vs STG_AMAZON_ADS**: Small differences in units/sales are expected because FACT uses purchased_product (accurate units/sales) where available and only uses ADS for the fallback rows; cross-sell rows have orders=0 in FACT.

---

## 4. Example rows by scenario

### 4.1 Same-ASIN (advertised_asin = PURCHASED_ASIN) from purchased_product

| DATE | PURCHASED_ASIN | advertised_asin | campaign_name | PURCHASED_ORDERS | PURCHASED_UNITS | sales_usd | cost_per_unit | gross_profit | DATA_SOURCE |
|------|----------------|----------------|---------------|------------------|-----------------|-----------|---------------|--------------|-------------|
| 2026-02-11 | B0C1VLXYBP | B0C1VLXYBP | BRAND-STORE/BROAD (old one) | 1 | 1 | 54.40 | NULL | 54.40 | SB |
| 2026-02-11 | B0F9XFXQRW | B0F9XFXQRW | ME-VIDEO/EXACT (Girls journal) | 1 | 1 | 32.99 | NULL | 32.99 | SB |
| 2026-02-10 | B0F9XFXQRW | B0F9XFXQRW | ME-VIDEO/EXACT (Girls journal) | 5 | 3 | 98.97 | NULL | 98.97 | SB |
| 2026-02-10 | B0F9XFXQRW | B0F9XFXQRW | ME- VIDEO/ BROAD | 7 | 2 | 65.98 | NULL | 65.98 | SB |

*Orders and units from ads; sales from purchased_product. Cost/Gross profit populated when DIM_COSTS_HISTORY has a match.*

---

### 4.2 Cross-sell (advertised_asin ≠ PURCHASED_ASIN) from purchased_product

| DATE | PURCHASED_ASIN | advertised_asin | campaign_name | PURCHASED_ORDERS | PURCHASED_UNITS | sales_usd | gross_profit | DATA_SOURCE |
|------|----------------|-----------------|---------------|------------------|-----------------|-----------|--------------|-------------|
| 2026-02-11 | B0DJFG5ZJ7 | B0C1VLXYBP | BOX-SP/BROAD-(white- gift for girl) | **0** | 1 | 54.40 | 54.40 | SP |
| 2026-02-11 | B0CR6N3WRC | B0C1VLXYBP | BOX-SP/BROAD-(white- gift for girl) | **0** | 1 | 54.40 | 54.40 | SP |
| 2026-02-10 | B0D7N2MLDP | B0D7N31M6S | FRESH- VIDEO / BROAD (Jenna) | **0** | 4 | 199.60 | 199.60 | SB |
| 2026-02-10 | B0D7N2MLDP | B0D7N31M6S | FRESH-VIDEO/ BROAD | **0** | 3 | 146.15 | 146.15 | SB |

*Orders = 0 by design; units and sales from purchased_product.*

---

### 4.3 Ads fallback (STG_AMAZON_ADS only, no purchased_product match)

| DATE | PURCHASED_ASIN | advertised_asin | campaign_name | PURCHASED_ORDERS | PURCHASED_UNITS | sales_usd | gross_profit | DATA_SOURCE |
|------|----------------|-----------------|---------------|------------------|-----------------|-----------|--------------|-------------|
| 2026-02-11 | B0F4KCCSWN | B0F4KCCSWN | BOTTLE- AUTO | 1 | 1 | 29.90 | 29.90 | STG_AMAZON_ADS |
| 2026-02-11 | B0C1VLXYBP | B0C1VLXYBP | BOX - EXACT (white - teen) | 0 | 0 | 0.00 | 0.00 | STG_AMAZON_ADS |
| 2026-02-11 | B0CR6N3WRC | B0CR6N3WRC | BOX- STORE/ BROAD | 0 | 0 | 0.00 | 0.00 | STG_AMAZON_ADS |
| 2026-02-11 | B0F9XFXQRW | B0F9XFXQRW | ME- VIDEO/ BROAD | 0 | 0 | 0.00 | 0.00 | STG_AMAZON_ADS |

*Measures from STG_AMAZON_ADS when no row in purchased_product.*

---

### 4.4 Organic delta (Performance − Ads)

| DATE | PURCHASED_ASIN | PURCHASED_ORDERS | PURCHASED_UNITS | sales_usd | cost_per_unit | gross_profit | DATA_SOURCE |
|------|----------------|------------------|-----------------|-----------|---------------|--------------|-------------|
| 2026-02-08 | B0C1VLXYBP | 4 | 4 | 217.60 | NULL | 217.60 | STG_AMAZON_PERFORMANCE |
| 2026-02-08 | B0F9XDSVYB | 8 | 5 | 164.95 | NULL | 164.95 | STG_AMAZON_PERFORMANCE |
| 2026-02-08 | B0F9X95K5H | 8 | 4 | 131.96 | NULL | 131.96 | STG_AMAZON_PERFORMANCE |
| 2026-02-08 | B0D7N2MLDP | 7 | 2 | 99.80 | NULL | 99.80 | STG_AMAZON_PERFORMANCE |

*Delta = STG_AMAZON_PERFORMANCE − aggregated Ads by PURCHASED_ASIN/date.*

---

## 5. Summary

- **Purchased_product (SB+SP)**: Units and sales in FACT match source exactly.
- **Same-ASIN**: Ads orders/units + purchased_product sales; TOTAL_COST_PER_UNIT and GROSS_PROFIT when DIM_COSTS_HISTORY matches.
- **Cross-sell**: Orders = 0; units and sales from purchased_product.
- **Fallback**: All measures from STG_AMAZON_ADS when no purchased_product row.
- **Organic**: Performance − Ads by ASIN/date; cost/profit when DIM_COSTS_HISTORY matches.

*Report generated from BigQuery validation queries.*
