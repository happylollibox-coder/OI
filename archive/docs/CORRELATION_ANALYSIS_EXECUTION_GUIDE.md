# Correlation Analysis Execution Guide

## 🎯 Goal: Find Solid Correlations That Bring Value

I've created a comprehensive suite of correlation analysis queries that dig deep into your data to find actionable insights. Here's how to execute them and what to look for.

## 📊 Query Suite Overview

### 1. **CORRELATION_ANALYSIS_FOCUSED.sql** (Base Analysis)
   - Search term level correlations
   - Statistical correlation coefficients
   - ASIN-level summaries
   - Top 100 opportunities

### 2. **DEEP_CORRELATION_ANALYSIS.sql** (Advanced Analysis)
   - **Time-lagged correlation**: Does paid investment lead to organic growth?
   - **Cumulative investment effect**: Does multi-week investment correlate better?
   - **High-performance term correlation**: Focus on terms that perform well
   - **ASIN-level strong correlations**: Find ASINs with strongest relationships
   - **Growth velocity correlation**: Do fast-growing paid terms also grow organically?

### 3. **FIND_STRONGEST_CORRELATIONS.sql** (Actionable Insights)
   - Identifies strongest correlations (≥0.3)
   - Classifies value categories
   - Ranks by investment priority
   - Focuses on actionable opportunities

## 🚀 Execution Steps

### Step 1: Run Base Correlation Analysis
```bash
cd /Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI

# Run the focused correlation analysis
bq query --use_legacy_sql=false \
  --project_id=onyga-482313 \
  --format=csv \
  < scripts/Analysis/CORRELATION_ANALYSIS_FOCUSED.sql > correlation_base_results.csv
```

**What to look for:**
- `correlation_orders` > 0.5 = Strong positive correlation
- `correlation_orders` between 0.3-0.5 = Moderate correlation
- Terms with high `investment_priority_score`

### Step 2: Run Deep Correlation Analysis
```bash
# Run the deep analysis (5 different correlation tests)
bq query --use_legacy_sql=false \
  --project_id=onyga-482313 \
  --format=csv \
  < scripts/Analysis/DEEP_CORRELATION_ANALYSIS.sql > correlation_deep_results.csv
```

**What to look for:**
- **Lagged correlation**: If `lagged_correlation_coefficient` > 0.3, paid investment leads to organic growth
- **Cumulative correlation**: If `correlation_cumulative_orders` > 0.4, sustained investment works better
- **High-performance terms**: Look for terms with `correlation_orders` > 0.5
- **ASIN correlations**: Find ASINs with `asin_correlation_orders` > 0.5

### Step 3: Find Strongest Correlations (MOST IMPORTANT)
```bash
# This query finds the strongest, most actionable correlations
bq query --use_legacy_sql=false \
  --project_id=onyga-482313 \
  --format=csv \
  --max_rows=10000 \
  < scripts/Analysis/FIND_STRONGEST_CORRELATIONS.sql > strongest_correlations.csv
```

**What to look for:**
- **VERY STRONG** or **STRONG** correlation_strength
- **HIGH VALUE** value_category = Best opportunities
- **GOOD CORRELATION** = Terms where both paid and organic work
- **OPPORTUNITY** = Terms with strong paid but no organic

## 📈 Interpreting Results

### Correlation Strength Guide
- **≥ 0.7**: VERY STRONG - Strong relationship, high confidence
- **≥ 0.5**: STRONG - Good relationship, actionable
- **≥ 0.3**: MODERATE - Some relationship, worth monitoring
- **< 0.3**: WEAK - Little to no relationship

### Value Categories

1. **HIGH VALUE - Strong Positive Correlation, Low Organic**
   - **Action**: Invest in these terms for organic growth
   - **Example**: correlation > 0.5, paid orders high, organic orders low

2. **GOOD CORRELATION - Both Performing**
   - **Action**: Maintain current strategy, both channels working
   - **Example**: correlation > 0.5, both paid and organic performing

3. **OPPORTUNITY - No Organic, Strong Paid**
   - **Action**: Focus SEO/content efforts on these terms
   - **Example**: correlation > 0.3, paid orders > 5, organic orders = 0

4. **NEGATIVE - Investigate**
   - **Action**: Review these terms - may indicate cannibalization
   - **Example**: correlation < -0.3

## 🎯 What Makes a "Solid Correlation"

A solid correlation that brings value has these characteristics:

1. **Statistical Strength**: Correlation coefficient ≥ 0.5
2. **Business Significance**: 
   - High paid orders (> 5-10 orders)
   - Meaningful organic gap (opportunity exists)
   - Consistent over time (≥ 3-4 weeks)
3. **Actionability**:
   - Clear investment opportunity
   - Measurable impact potential
   - Feasible to execute

## 📊 Expected Findings

Based on typical Amazon data patterns, you should find:

1. **Strong Positive Correlations** (0.5-0.8):
   - Terms where paid investment drives organic visibility
   - ASINs with consistent performance in both channels
   - High-performing search terms

2. **Moderate Correlations** (0.3-0.5):
   - Terms with some relationship but room for improvement
   - ASINs with mixed performance
   - Emerging opportunities

3. **Opportunity Gaps**:
   - Terms with strong paid performance but no organic presence
   - ASINs with high paid-to-organic ratios
   - Search terms with high investment priority scores

## 🔍 Next Steps After Running

1. **Identify Top 20 Search Terms** from `FIND_STRONGEST_CORRELATIONS.sql`
   - Focus on "HIGH VALUE" and "OPPORTUNITY" categories
   - Prioritize by `investment_priority_score`

2. **Review ASIN-Level Correlations**
   - Find ASINs with strongest correlations
   - Focus investment on these products

3. **Analyze Time-Lagged Effects**
   - If lagged correlation > 0.3, paid investment leads to organic growth
   - Plan campaigns with 1-2 week lead time

4. **Create Action Plan**
   - SEO/content strategy for high-opportunity terms
   - Paid campaign adjustments based on correlations
   - ASIN-level optimization priorities

## 💡 Pro Tips

- **Start with `FIND_STRONGEST_CORRELATIONS.sql`** - It's the most actionable
- **Look for correlation ≥ 0.5** - These are your strongest opportunities
- **Focus on terms with order gaps** - Where paid > organic significantly
- **Review ASIN-level results** - Some products show stronger correlations than others
- **Check time-lagged effects** - May reveal investment timing strategies

## 🚨 If Correlations Are Weak

If you find weak correlations (< 0.3), try:

1. **Segment by campaign type** - Some campaign types may correlate better
2. **Filter by date range** - Recent data may show different patterns
3. **Focus on high-volume terms** - More data = more reliable correlations
4. **Check for seasonality** - Some periods may show stronger correlations
5. **Review data quality** - Ensure both tables have sufficient data

---

**Ready to find solid correlations?** Start with `FIND_STRONGEST_CORRELATIONS.sql` - it's designed to surface the most actionable insights!
