# Sales Module Mapping Analysis
## How to Distinguish Amazon Sales Modules in Interface Views

---

## Overview

The Interface Views (`V_SRC_AmazonAds_*`) contain data from **paid advertising modules** only. These views represent:

- **Module #1 (Search Results - Paid Search portion)**: 15-25% of total sales
- **Module #4 (Sponsored Products / Display Ads)**: 15-25% of total sales

**Note**: These views do NOT contain:
- Organic Search (Module #1 - organic portion)
- Browse/Category (Module #3)
- Detail Page Direct (Module #2)
- Other ASIN/Recommendations (Module #5)
- Brand Store (Module #6)
- Deals/Promotions (Module #7)
- External Traffic (Module #10)
- Other non-ad modules

---

## View-by-View Analysis

### 1. V_SRC_AmazonAds_campaign_history ✅ **Best Distinction**

**Sales Module**: Module #4 (Sponsored Products/Display Ads) + Module #1 (Paid Search)

**Can Distinguish**:
- ✅ **`campaign_type`** field: `'SP'` (Sponsored Products) or `'SB'` (Sponsored Brands)
- ✅ Both types are **paid advertising** (Module #4)
- ✅ Both can appear in **search results** (Module #1 - Paid portion)

**Example**:
```sql
SELECT 
  campaign_id,
  campaign_name,
  campaign_type,  -- 'SP' or 'SB'
  budget,
  state
FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`
WHERE campaign_type = 'SP'  -- Sponsored Products
-- OR campaign_type = 'SB'  -- Sponsored Brands
```

**Module Mapping**:
- `campaign_type = 'SP'` → **Sponsored Products** (Module #4, Module #1-Paid)
- `campaign_type = 'SB'` → **Sponsored Brands** (Module #4, Module #1-Paid)

---

### 2. V_SRC_AmazonAds_keyword ⚠️ **Partial Distinction**

**Sales Module**: Module #4 (Sponsored Products/Display Ads) + Module #1 (Paid Search)

**Can Distinguish**:
- ⚠️ **No explicit `campaign_type` field** in this view
- ✅ Can **infer** by joining to `V_SRC_AmazonAds_campaign_history` via `campaign_id`
- ⚠️ Data comes from UNION of SP and SB keyword tables (mixed)

**Solution**: Join to campaign_history to get campaign_type
```sql
SELECT 
  k.keyword_id,
  k.keyword_text,
  k.match_type,
  c.campaign_type,  -- 'SP' or 'SB' (from join)
  k.bid
FROM `onyga-482313.OI.V_SRC_AmazonAds_keyword` k
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON k.campaign_id = c.campaign_id
  AND CURRENT_TIMESTAMP() BETWEEN c.OI_start_date AND c.OI_end_date
WHERE c.campaign_type = 'SP'  -- Filter by type
```

**Module Mapping** (after join):
- `campaign_type = 'SP'` → **SP Keyword Targeting** (Module #4, Module #1-Paid)
- `campaign_type = 'SB'` → **SB Keyword Targeting** (Module #4, Module #1-Paid)

---

### 3. V_SRC_AmazonAds_negative_keyword ⚠️ **Partial Distinction**

**Sales Module**: Module #4 (Sponsored Products/Display Ads) + Module #1 (Paid Search)

**Can Distinguish**:
- ⚠️ **No explicit `campaign_type` field** in this view
- ✅ Can **infer** by joining to `V_SRC_AmazonAds_campaign_history` via `campaign_id`
- ⚠️ Data comes from UNION of SP and SB negative keyword tables (mixed)

**Solution**: Join to campaign_history to get campaign_type
```sql
SELECT 
  n.negative_id,
  n.keyword_text,
  n.match_type,
  c.campaign_type,  -- 'SP' or 'SB' (from join)
  n.state
FROM `onyga-482313.OI.V_SRC_AmazonAds_negative_keyword` n
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON n.campaign_id = c.campaign_id
  AND CURRENT_TIMESTAMP() BETWEEN c.OI_start_date AND c.OI_end_date
WHERE c.campaign_type = 'SP'  -- Filter by type
```

**Module Mapping** (after join):
- `campaign_type = 'SP'` → **SP Negative Keywords** (Module #4, Module #1-Paid)
- `campaign_type = 'SB'` → **SB Negative Keywords** (Module #4, Module #1-Paid)

---

### 4. V_SRC_AmazonAds_purchased_product ⚠️ **Inferable Distinction**

**Sales Module**: Module #4 (Sponsored Products/Display Ads) + Module #1 (Paid Search)

**Can Distinguish**:
- ⚠️ **No explicit `campaign_type` or `source_table` field**
- ✅ Can **infer** by:
  1. `keyword_id = '-1'` → **SB campaigns** (Sponsored Brands)
  2. `keyword_id != '-1'` + join to campaign_history → **SP campaigns** (Sponsored Products)
  3. Join to campaign_history for explicit `campaign_type`

**Inference Logic**:
- Rows with `keyword_id = '-1'` → **Sponsored Brands** (from `sb_purchased_product` table)
- Rows with `keyword_id != '-1'` → **Sponsored Products** (from `purchased_product_targeting_report` or `purchased_product_keyword_report`)

**Better Solution**: Join to campaign_history
```sql
SELECT 
  p.campaign_id,
  p.purchased_asin,
  p.sales,
  p.orders,
  c.campaign_type,  -- 'SP' or 'SB' (from join)
  CASE 
    WHEN p.keyword_id = '-1' THEN 'SB_Purchased_Product'
    WHEN p.match_type = 'Unknown' THEN 'SB_Purchased_Product'
    ELSE 'SP_Purchased_Product'
  END AS inferred_source
FROM `onyga-482313.OI.V_SRC_AmazonAds_purchased_product` p
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON p.campaign_id = c.campaign_id
  AND TIMESTAMP(p.date) BETWEEN c.OI_start_date AND c.OI_end_date
```

**Module Mapping** (after join/inference):
- `campaign_type = 'SP'` → **SP Product Purchases** (Module #4, Module #1-Paid)
- `campaign_type = 'SB'` → **SB Product Purchases** (Module #4, Module #1-Paid)

---

### 5. V_SRC_AmazonAds_SearchTerms ✅ **Best Distinction**

**Sales Module**: Module #4 (Sponsored Products/Display Ads) + Module #1 (Paid Search)

**Can Distinguish**:
- ✅ **`source_table`** field explicitly distinguishes 4 types:
  - `'sp_keyword'` → SP keyword-based search terms
  - `'sp_targeting'` → SP targeting-based search terms
  - `'sb_search_term'` → SB keyword-based search terms
  - `'sb_target_report'` → SB targeting-based search terms

**Example**:
```sql
SELECT 
  campaign_id,
  search_term,
  source_table,  -- 'sp_keyword', 'sp_targeting', 'sb_search_term', 'sb_target_report'
  clicks,
  cost,
  sales,
  -- Can also get campaign_type from join
  c.campaign_type
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON campaign_id = c.campaign_id
  AND TIMESTAMP(date) BETWEEN c.OI_start_date AND c.OI_end_date
WHERE source_table IN ('sp_keyword', 'sp_targeting')  -- SP only
```

**Module Mapping**:
- `source_table = 'sp_keyword'` → **SP Keyword Search Terms** (Module #4, Module #1-Paid)
- `source_table = 'sp_targeting'` → **SP Targeting Search Terms** (Module #4, Module #1-Paid)
- `source_table = 'sb_search_term'` → **SB Keyword Search Terms** (Module #4, Module #1-Paid)
- `source_table = 'sb_target_report'` → **SB Targeting Search Terms** (Module #4, Module #1-Paid)

---

## Summary: Distinction Capabilities

| View | Direct Distinction | Indirect Distinction | Recommendation |
|------|-------------------|---------------------|----------------|
| **V_SRC_AmazonAds_campaign_history** | ✅ `campaign_type` ('SP'/'SB') | N/A | **Best** - Use directly |
| **V_SRC_AmazonAds_SearchTerms** | ✅ `source_table` (4 types) | ✅ Join for `campaign_type` | **Best** - Use `source_table` |
| **V_SRC_AmazonAds_keyword** | ❌ None | ✅ Join to campaign_history | Join to get `campaign_type` |
| **V_SRC_AmazonAds_negative_keyword** | ❌ None | ✅ Join to campaign_history | Join to get `campaign_type` |
| **V_SRC_AmazonAds_purchased_product** | ⚠️ Infer from `keyword_id = '-1'` | ✅ Join to campaign_history | Join to get `campaign_type` |

---

## Recommended Enhancement: Add `campaign_type` to All Views

To improve distinction capabilities, consider adding `campaign_type` field to views that don't have it:

### Option 1: Add `campaign_type` via JOIN in Views

**Example for `V_SRC_AmazonAds_keyword`**:
```sql
SELECT 
  k.*,
  COALESCE(c.campaign_type, 'UNKNOWN') AS campaign_type
FROM (
  -- existing UNION query
) k
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON k.campaign_id = c.campaign_id
  AND CURRENT_TIMESTAMP() BETWEEN c.OI_start_date AND c.OI_end_date
```

### Option 2: Add `source_table` or `campaign_type` at Source

**Example for `V_SRC_AmazonAds_purchased_product`**:
```sql
SELECT 
  *,
  'SP_Targeting' AS source_table
FROM `fivetran-hl.amazon_ads.purchased_product_targeting_report`
UNION ALL
SELECT 
  *,
  'SP_Keyword' AS source_table
FROM `fivetran-hl.amazon_ads.purchased_product_keyword_report`
UNION ALL
SELECT 
  *,
  'SB' AS source_table
FROM `fivetran-hl.amazon_ads.sb_purchased_product`
```

---

## Sales Module Mapping Reference

All rows in these views map to **two sales modules**:

1. **Module #1 (Search Results - Paid Search)**: 
   - Sponsored Products in search results
   - Sponsored Brands in search results
   
2. **Module #4 (Sponsored Products / Display Ads)**:
   - Sponsored Products ads
   - Sponsored Brands ads

**Distinction Within Views**:
- `campaign_type = 'SP'` → Sponsored Products (both modules)
- `campaign_type = 'SB'` → Sponsored Brands (both modules)
- `source_table` in SearchTerms → Further breakdown (keyword vs targeting)

**Note**: These views **cannot** distinguish between:
- Search results placement vs Product page placement (both are Module #4)
- Organic vs Paid search (only paid is in these views)
- Other sales modules (Browse, Detail Page Direct, etc.)

---

## Practical Usage

### Query to Get SP vs SB Breakdown:
```sql
-- Using campaign_history (best)
SELECT 
  campaign_type,
  COUNT(*) AS campaign_count,
  SUM(budget) AS total_budget
FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`
GROUP BY campaign_type;

-- Using SearchTerms (also good)
SELECT 
  source_table,
  COUNT(*) AS search_term_rows,
  SUM(sales) AS total_sales,
  SUM(cost) AS total_cost
FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
GROUP BY source_table;
```

### Query to Get Campaign Type for Any View:
```sql
-- Example: Add campaign_type to keyword view
SELECT 
  k.*,
  c.campaign_type
FROM `onyga-482313.OI.V_SRC_AmazonAds_keyword` k
LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
  ON k.campaign_id = c.campaign_id
  AND CURRENT_TIMESTAMP() BETWEEN c.OI_start_date AND c.OI_end_date;
```

---

**Last Updated**: January 2026