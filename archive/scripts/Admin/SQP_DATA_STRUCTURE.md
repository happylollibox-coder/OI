# SQP_ASIN_View_Simple_Week Data Structure Guide

## Column Naming Convention

### Key Distinction

**When "ASIN" is in the column name** → Refers to **YOUR PRODUCT** (SKU = B09XQ56RK5)  
**When "ASIN" is NOT in the column name** → Refers to **AMAZON-WIDE** metrics for that search term

---

## Column Categories

### 1. Product-Specific Columns (Contains "ASIN")

These metrics show **your product's performance**:

| Column Name | Description | Example Value |
|------------|-------------|---------------|
| `Impressions_ASIN_Count` | Your product's impressions for this search term | 63 |
| `Impressions_ASIN_Share_%` | Your product's share of total impressions | 0.16% |
| `Clicks_ASIN_Count` | Your product's clicks for this search term | 1 |
| `Clicks_ASIN_Share_%` | Your product's share of total clicks | 0.24% |
| `Clicks_ASIN_Price_Median` | Your product's price (median) | 54.4 |
| `Cart_Adds_ASIN_Count` | Your product's cart additions | 0 |
| `Cart_Adds_ASIN_Share_%` | Your product's share of cart additions | 0% |
| `Cart_Adds_ASIN_Price_Median` | Your product's price in cart | 54.4 |
| `Purchases_ASIN_Count` | Your product's purchases for this search term | 0 |
| `Purchases_ASIN_Share_%` | Your product's share of total purchases | 0% |
| `Purchases_ASIN_Price_Median` | Your product's purchase price | 54.4 |

**Key Insight**: These show your **market share** and **competitive position** for each search term.

### 2. Amazon-Wide Columns (No "ASIN" in name)

These metrics show **total market performance** for the search term across **all products** on Amazon:

| Column Name | Description | Example Value |
|------------|-------------|---------------|
| `Impressions_Total_Count` | Total impressions across all Amazon products | 38,351 |
| `Clicks_Total_Count` | Total clicks across all Amazon products | 413 |
| `Clicks_Price_Median` | Median price of products that received clicks | 25.99 |
| `Clicks_Click_Rate_%` | Overall CTR for the search term | 24.29% |
| `Cart_Adds_Total_Count` | Total cart additions across all products | 59 |
| `Cart_Adds_Cart_Add_Rate_%` | Overall cart add rate | 3.47% |
| `Purchases_Total_Count` | Total purchases across all products | 6 |
| `Purchases_Purchase_Rate_%` | Overall purchase rate | 0.35% |
| `Purchases_Price_Median` | Median price of purchased products | 25.99 |

**Key Insight**: These show the **market size** and **overall demand** for each search term.

---

## Understanding the Data

### Example Row Analysis

For search term: "jugetes. para. niñas de 10 a 12 años"

**Amazon-Wide Metrics:**
- Total Impressions: 38,351 (across all Amazon products)
- Total Clicks: 413
- Total Purchases: 6
- Overall Conversion Rate: 6/413 = 1.45%

**Your Product Metrics:**
- Your Impressions: 63 (your share: 0.16% of total)
- Your Clicks: 1 (your share: 0.24% of clicks)
- Your Purchases: 0 (your share: 0% of purchases)

**Interpretation:**
- This is a competitive search term with many products showing up
- Your product has very low market share (0.16% impressions, 0.24% clicks)
- You're not converting on this term (0 purchases vs 6 total)
- Opportunity: Improve visibility and conversion for this query

---

## Key Metrics to Calculate

### 1. Market Share Metrics

```
Impression Share = (Impressions_ASIN_Count / Impressions_Total_Count) * 100
Click Share = (Clicks_ASIN_Count / Clicks_Total_Count) * 100
Purchase Share = (Purchases_ASIN_Count / Purchases_Total_Count) * 100
```

**Interpretation:**
- High share = Strong competitive position
- Low share = Opportunity to improve visibility/conversion

### 2. Your Product's Conversion Rate

```
Your Conversion Rate = (Purchases_ASIN_Count / Clicks_ASIN_Count) * 100
```

**Compare with market:**
- If your conversion > market average → Strong product-market fit
- If your conversion < market average → Optimization opportunity

### 3. Market Competitiveness

```
Competition Level = Impressions_Total_Count / Purchases_Total_Count
```

**Interpretation:**
- High ratio = Very competitive (many products, few purchases)
- Low ratio = Less competitive, higher conversion market

### 4. Price Competitiveness

```
Price Difference = Clicks_ASIN_Price_Median - Clicks_Price_Median
```

**Interpretation:**
- Positive = Your product is priced higher than market median
- Negative = Your product is priced lower than market median
- Large difference may explain low share

---

## Re-analyzing Insights with This Understanding

### Original Insight: "Top Performing Search Queries"

**Before**: We analyzed `Purchases_Total_Count` (Amazon-wide)

**Now Understanding**: This shows market size, not your product's performance.

**Revised Analysis Needed**:
- **Market Size**: `Purchases_Total_Count` shows opportunity size
- **Your Performance**: `Purchases_ASIN_Count` shows your actual results
- **Market Share**: `Purchases_ASIN_Share_%` shows competitive position

**Key Questions**:
1. Are high-volume queries ones where you have market share?
2. Are you missing opportunities in large markets?
3. Which queries give you the best market share?

### Original Insight: "Conversion Rates"

**Before**: `Purchases_Purchase_Rate_%` (Amazon-wide conversion)

**Now Understanding**: This is market conversion, not your product's conversion.

**Revised Analysis Needed**:
- **Market Conversion**: `Purchases_Purchase_Rate_%` = market benchmark
- **Your Conversion**: `Purchases_ASIN_Count / Clicks_ASIN_Count` = your performance
- **Comparison**: Are you above or below market?

**Key Questions**:
1. Are you converting better than the market average?
2. Which queries give you highest conversion relative to market?
3. Where can you improve to match/beat market rates?

### Original Insight: "Price Sensitivity"

**Before**: `Clicks_Price_Median` (market median price)

**Now Understanding**: This is competitor pricing, your price is `Clicks_ASIN_Price_Median`.

**Revised Analysis Needed**:
- **Your Price**: `Clicks_ASIN_Price_Median` = 54.4 (fixed)
- **Market Median**: `Clicks_Price_Median` = varies by query
- **Price Competitiveness**: Your price vs market median

**Key Questions**:
1. Are you overpriced relative to market (explaining low share)?
2. Which queries have market prices closer to yours?
3. Where does price competitiveness drive better share?

---

## Revised Key Metrics to Analyze

### 1. Market Share Leaders

**Queries where you have highest share:**
```sql
SELECT 
  Search_Query,
  Purchases_ASIN_Share_%,
  Purchases_Total_Count,
  Purchases_ASIN_Count
FROM SQP_ASIN_View_Simple_Week
WHERE Purchases_ASIN_Count > 0
ORDER BY Purchases_ASIN_Share_% DESC
```

**Insight**: Shows where you're winning market share.

### 2. High Opportunity, Low Share

**Large markets where you have low share:**
```sql
SELECT 
  Search_Query,
  Purchases_Total_Count,
  Purchases_ASIN_Count,
  Purchases_ASIN_Share_%,
  Impressions_ASIN_Share_%
FROM SQP_ASIN_View_Simple_Week
WHERE Purchases_Total_Count >= 100  -- Large market
  AND Purchases_ASIN_Share_% < 1    -- Low share
ORDER BY Purchases_Total_Count DESC
```

**Insight**: Opportunities to increase market share in large markets.

### 3. Your Product's Conversion vs Market

**Where you outperform/underperform market:**
```sql
SELECT 
  Search_Query,
  Clicks_Total_Count,
  Purchases_Total_Count,
  ROUND(SAFE_DIVIDE(Purchases_Total_Count, Clicks_Total_Count) * 100, 2) as market_conversion_rate,
  Clicks_ASIN_Count,
  Purchases_ASIN_Count,
  ROUND(SAFE_DIVIDE(Purchases_ASIN_Count, Clicks_ASIN_Count) * 100, 2) as your_conversion_rate,
  ROUND(SAFE_DIVIDE(Purchases_ASIN_Count, Clicks_ASIN_Count) * 100, 2) - 
    ROUND(SAFE_DIVIDE(Purchases_Total_Count, Clicks_Total_Count) * 100, 2) as conversion_delta
FROM SQP_ASIN_View_Simple_Week
WHERE Clicks_ASIN_Count > 0 AND Clicks_Total_Count > 0
ORDER BY ABS(conversion_delta) DESC
```

**Insight**: Shows where your product converts better/worse than market.

### 4. Price Competitiveness Analysis

**Your price vs market price:**
```sql
SELECT 
  Search_Query,
  Clicks_Price_Median as market_median_price,
  Clicks_ASIN_Price_Median as your_price,
  Clicks_ASIN_Price_Median - Clicks_Price_Median as price_difference,
  Impressions_ASIN_Share_%,
  Clicks_ASIN_Share_%
FROM SQP_ASIN_View_Simple_Week
WHERE Clicks_Price_Median > 0 AND Clicks_ASIN_Price_Median > 0
ORDER BY ABS(Clicks_ASIN_Price_Median - Clicks_Price_Median) DESC
```

**Insight**: Shows if price competitiveness affects market share.

---

## Updated Insights Recommendations

### Priority 1: Market Share Analysis

**Question**: Where do you have the highest market share?

**Analysis**:
- Focus on queries with highest `Purchases_ASIN_Share_%`
- Understand what makes you successful there
- Replicate strategies to other queries

### Priority 2: Opportunity Identification

**Question**: Which large markets have you not captured?

**Analysis**:
- High `Purchases_Total_Count` + Low `Purchases_ASIN_Share_%`
- Identify why you're not competing effectively
- Price? Visibility? Conversion? Listing quality?

### Priority 3: Conversion Optimization

**Question**: Where are you underperforming market conversion?

**Analysis**:
- Compare your conversion vs market conversion
- Identify optimization opportunities
- Test improvements on underperforming queries

### Priority 4: Price Strategy

**Question**: Is price affecting your competitiveness?

**Analysis**:
- Compare your price vs market median
- Identify queries where price gap is smallest
- Test if price-competitive queries have better share

---

## Summary

**Key Understanding**:
- **ASIN columns** = Your product (B09XQ56RK5) metrics
- **Non-ASIN columns** = Amazon-wide market metrics
- **Share percentages** = Your competitive position
- **Total counts** = Market size and opportunity

**Revised Focus**:
1. Market share analysis (where you're winning)
2. Opportunity gaps (large markets, low share)
3. Conversion benchmarking (your performance vs market)
4. Price competitiveness (how pricing affects share)

---

*Updated: January 2025*  
*This understanding changes the interpretation of all SQP insights*
