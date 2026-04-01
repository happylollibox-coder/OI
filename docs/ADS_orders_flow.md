# How PURCHASED_ORDERS (orders from ADS) is populated

## Current logic in `SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY`

### Step 1: `ads_aggregated` CTE

- **Source:** `STG_AMAZON_ADS`
- **Group by:** `date`, `campaign_id`, `ad_group_id`, **keyword_id** (for SB we force `keyword_id = '-1'`), `most_advertised_asin_impressions` (= `advertised_asin`)
- **Measures:**  
  `orders = SUM(orders)`  
  (and `SUM(impressions)`, `SUM(clicks)`, `SUM(cost)`, `SUM(units)`, `SUM(sales)`)

So for **SB** we collapse all **keywords** in the same (date, campaign, ad_group, advertised_asin) into **one** row and **sum** their `orders`.

### Step 2: Join and output

- **FULL OUTER JOIN** `ads_aggregated` **a** with `STG_AmazonAds_purchased_product` **pp**  
  on: `date`, `campaign_id`, `ad_group_id`, `keyword_id`, `a.advertised_asin = pp.advertised_asin`
- **PURCHASED_ORDERS** (orders from ADS):
  - **Same-ASIN** (pp row exists and `pp.advertised_asin = pp.PURCHASED_ASIN`): `a.orders`
  - **Cross-sell** (pp row exists but different ASIN): `0`
  - **Fallback** (no pp row): `a.orders`

So for same-ASIN we take **orders from ADS** = the summed `a.orders` from `ads_aggregated`.

---

## Your example: 2025-12-13, campaign 342313119548309, ad_group 472447908809960, ASIN B0D7N31M6S

### What happens in ADS

**STG_AMAZON_ADS** has **several rows per keyword** (search-term level) for this (date, campaign, ad_group, advertised_asin = B0D7N31M6S):

| keyword_id (real) | row_count | sum(orders) | sum(units) |
|-------------------|-----------|-------------|------------|
| 412357927409346   | 336       | 11          | 11         |
| 549989054780338   | 198       | 8           | 8          |
| 472871506551769   | 165       | 4           | 4          |
| 478262319688209   | 45        | 0           | 0          |

We then **force keyword_id = '-1'** for SB and **sum** over all keywords:

- **One** row in `ads_aggregated`:  
  (date, campaign_id, ad_group_id, **keyword_id = '-1'**, advertised_asin = B0D7N31M6S)
- **orders = 11 + 8 + 4 + 0 = 23**  
- **ads_units_fallback = 11 + 8 + 4 + 0 = 23**

So **orders from ADS** for this fact row = **23**.

### What happens from purchased_product

- **STG_AmazonAds_purchased_product** has **one** row for (date, campaign, ad_group, keyword_id = '-1', PURCHASED_ASIN = B0D7N31M6S):
  - **PURCHASED_ORDERS = 11**
  - **PURCHASED_UNITS = 11**
  - **PURCHASED_AMOUNT_USD = 548.90**

We use **units and sales** from purchased_product, but **orders** from ADS (see Step 2 above), so we output:

- **PURCHASED_ORDERS = 23** (from `a.orders`)
- **PURCHASED_UNITS = 11** (from pp)
- **PURCHASED_AMOUNT_USD = 548.90** (from pp)

So we get **23 orders, 11 units** for the same-ASIN row.

---

## Why 23 vs 11?

- **23** = sum of ADS `orders` over **all keywords** (11 + 8 + 4 + 0) in that ad group for that advertised ASIN on that date.
- **11** = orders/units in **purchased_product** for that ASIN (one row per ad group, keyword_id = '-1').

So the same **real** orders are likely attributed to **multiple keywords** in ADS (e.g. one purchase attributed to several search terms). Summing ADS orders across keywords then **over-counts** (23), while purchased_product gives the **actual** count (11). So:

- **Orders from ADS** in the procedure = **23** (sum across keywords).
- **Units from purchased_product** = **11**.

That’s why you see **23 orders and 11 units** for that example.

---

## Summary

- **How we do it:**  
  - **Orders:** from ADS only: `a.orders` for same-ASIN and fallback; 0 for cross-sell.  
  - **Units / sales:** from purchased_product when we have a pp row; otherwise from ADS.
- **Why 23 vs 11:**  
  For SB we **sum** ADS `orders` over **all keywords** (keyword_id forced to '-1') before the join, so we get 23. Purchased_product has a single count per (date, campaign, ad_group, ASIN), so we get 11 units and 11 orders there. So “orders from ads” in the fact is the **aggregated** ADS number (23), not the purchased_product number (11).

If you want “orders from ads” but **no double-count across keywords**, we’d need to change the aggregation (e.g. for SB use something like **MAX(orders)** per (date, campaign, ad_group, advertised_asin) instead of **SUM(orders)** when building the grain that joins to purchased_product).
