# STG_AmazonAds_purchased_product vs STG_AMAZON_ADS Alignment Analysis

## Summary

These staging tables use **different Amazon reports** with **different attribution logic**. They are not expected to match at the aggregate level.

---

## Data Sources

### STG_AmazonAds_purchased_product
**Source:** `V_SRC_AmazonAds_purchased_product`  
**Fivetran tables:**
- `purchased_product_targeting_report` (SP targeting)
- `purchased_product_keyword_report` (SP keyword)
- `sb_purchased_product` (SB)

**Grain:** (date, campaign_id, ad_group_id, keyword_id, purchased_asin, advertised_asin)

### STG_AMAZON_ADS
**Source:** `V_SRC_AmazonAds_SearchTerms` + advertised product enrichment  
**Fivetran tables:**
- `search_term_ad_keyword_report` (SP keyword)
- `search_term_targeting_report` (SP targeting)
- `sb_search_term_report` (SB)
- `sb_target_report` (SB)

**Grain:** (date, campaign_id, ad_group_id, keyword_id, search_term)

---

## Root Causes of Misalignment

### 1. **Different report types (different attribution dimensions)**

| Aspect | Purchased Product Report | Search Term Report |
|--------|---------------------------|--------------------|
| **Primary dimension** | Product purchased (purchased_asin) | Search term that triggered the ad |
| **Attribution** | Groups by products customers bought | Groups by search queries that preceded clicks |
| **ASIN in Search Terms** | Explicit purchased_asin + advertised_asin | Inferred via most_advertised_asin_* from advertised_product |

### 2. **SP: "Other SKU" vs "All sales" (critical)**

From [Amazon Ads API docs](https://advertising.amazon.com/API/docs/en-us/guides/reporting/v3/report-types/purchased-product):

> **Sponsored Products purchased product reports** contain performance data for products that were **purchased, but were not advertised** as part of a campaign.

**V_SRC_AmazonAds_purchased_product** uses:
- `purchases_other_sku_30_d`, `units_sold_other_sku_30_d`, `sales_other_sku_30_d`

So for SP, the purchased product report **excludes same-SKU purchases** (when the customer buys the advertised product). It only includes **cross-sell** (customer clicked ad for ASIN A, bought ASIN B).

**Search term report** uses:
- `purchases_30_d`, `units_sold_clicks_30_d`, `sales_30_d`

These include **all attributed sales** (same-SKU + other-SKU).

**Result:** SP purchased product totals will be **lower** than search term totals when most sales are same-SKU.

### 3. **Attribution windows**

| Report | SP | SB |
|--------|----|----|
| Purchased Product | 30-day (other_sku) | 14-day |
| Search Term | 30-day | 14-day |

Windows match, but SP purchased product only counts other-SKU.

### 4. **Date filter in Search Terms**

`V_SRC_AmazonAds_SearchTerms` has:
```sql
WHERE date >= '2025-10-28'
```

`V_SRC_AmazonAds_purchased_product` has **no date filter** — includes all history.

**Result:** For dates before 2025-10-28, Search Terms has no data; Purchased Product has data.

### 5. **sb_target_report filter**

`V_SRC_AmazonAds_SearchTerms` includes:
```sql
FROM sb_target_report
WHERE cost <> 0
```

**Result:** Search terms with zero cost are excluded from SB target report. Purchased product has no such filter.

### 6. **ASIN attribution in Search Terms**

STG_AMAZON_ADS assigns sales to `most_advertised_asin_purchased` — the ASIN with highest orders in that campaign+ad_group+date from advertised_product. That is an **inferred** link, not Amazon’s published purchased-product attribution.

---

## Recommendations

### Option A: Use一致的 metrics (align on one report)

If you need a single source of truth for ads sales:

- **For search-term-level analysis:** Use STG_AMAZON_ADS (FACT_AMAZON_ADS) — already done.
- **For product-level attribution:** Use STG_AmazonAds_purchased_product for cross-sell only; it does not include same-SKU.

### Option B: Matching SP purchased product to search terms

To make SP purchased product comparable to search terms, you would need:

1. **Include same-SKU in purchased product** — if Fivetran exposes `purchases_30_d` / `sales_30_d` (not just `other_sku`) in the purchased product tables.
2. **Or** use the search term report as the source for SP sales (current approach).

### Option C: Document the difference

Keep both reports but document that:

- **Purchased Product (SP):** Cross-sell only (other-SKU).
- **Search Terms:** All attributed sales (same-SKU + other-SKU).

---

## Quick reference: Field mapping

| Purchased Product | Search Term |
|-------------------|-------------|
| `purchases_other_sku_30_d` (SP) | `purchases_30_d` |
| `sales_other_sku_30_d` (SP) | `sales_30_d` |
| `units_sold_other_sku_30_d` (SP) | `units_sold_clicks_30_d` |
| `orders_14_d` (SB) | `attributed_conversions_14_d` (SB) |
| `sales_14_d` (SB) | `attributed_sales_14_d` (SB) |
| purchased_asin (explicit) | most_advertised_asin_purchased (inferred) |
