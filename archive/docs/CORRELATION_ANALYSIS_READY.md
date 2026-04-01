# Correlation Analysis: Ready to Run! 🚀

## ✅ What's Ready

Based on your answers, I've created a **focused correlation analysis** that will show you:

1. **Correlation between paid and organic performance** (your main goal)
2. **Statistical correlation coefficients** (Pearson correlations)
3. **Search term opportunities** ranked by investment potential
4. **ASIN-level summaries** showing which products have the best growth potential

## 📝 Quick Explanation: Search Term Matching

**What is "normalization"?** It's making sure search terms match even if they're written differently:
- "dog toy" = "Dog Toy" = "DOG TOY" = "dog  toy" (with extra spaces)
- The queries use `UPPER(TRIM())` to handle this automatically
- So you don't need to worry about case sensitivity or extra spaces

## 📊 What the Analysis Will Show

### 1. **Search Term Level Correlation** (Main Query)
Shows each search term with:
- Organic vs Paid performance side-by-side
- Correlation indicators (gaps, ratios)
- **Investment Priority Score** (higher = better opportunity)
- Opportunity categories:
  - "High Opportunity - No Organic" = Paid performs but no organic presence
  - "High Opportunity - Paid Dominant" = Paid much stronger than organic
  - "Efficiency Opportunity - Organic Better" = Organic converts better (reduce paid?)
  - "Both Present - Monitor" = Both performing, watch trends

### 2. **Statistical Correlation Coefficients**
Shows overall correlation strength:
- **Correlation Impressions**: How well paid impressions correlate with organic impressions
- **Correlation Orders**: How well paid orders correlate with organic orders  
- **Correlation Conversion Rate**: How well conversion rates correlate
- **Interpretation**:
  - **+1.0** = Perfect positive correlation (when paid goes up, organic goes up)
  - **0.0** = No correlation
  - **-1.0** = Perfect negative correlation (when paid goes up, organic goes down)
  - **+0.5 to +0.8** = Strong positive correlation (good sign!)
  - **+0.3 to +0.5** = Moderate correlation
  - **Below +0.3** = Weak correlation

### 3. **ASIN-Level Summary**
Shows which ASINs have:
- Highest paid-to-organic gaps (opportunity)
- Most unique paid terms without organic presence
- Best conversion rates
- **ASIN Opportunity Score** (ranked list)

### 4. **Top 100 Investment Opportunities**
Ranked list of search terms with:
- Strong paid performance
- Weak or no organic presence
- Highest investment priority scores

## 🎯 How to Use

### Step 1: Run the Main Correlation Query
```sql
-- Open: scripts/Analysis/CORRELATION_ANALYSIS_FOCUSED.sql
-- Run the first query (Search Term Level Correlation)
-- This shows all matched terms with correlation metrics
```

**What to look for:**
- Terms with `has_organic = 1 AND has_paid = 1` = Both present (correlation analysis)
- Terms with `has_organic = 0 AND has_paid = 1` = No organic (investment opportunity)
- High `investment_priority_score` = Best opportunities

### Step 2: Check Statistical Correlations
```sql
-- Run the second query (Statistical Correlation Coefficients)
-- This gives you overall correlation strength
```

**What to look for:**
- **correlation_orders > 0.5** = Strong positive correlation (paid investment helps organic)
- **correlation_orders < 0.3** = Weak correlation (may need different strategy)
- **correlation_conversion_rate** = Shows if efficient paid terms also convert well organically

### Step 3: Review ASIN Opportunities
```sql
-- Run the third query (ASIN-Level Correlation Summary)
-- This shows which products have the best growth potential
```

**What to look for:**
- High `asin_opportunity_score` = Best ASINs to focus on
- High `term_gap` = Many paid terms without organic presence
- High `pct_paid_terms_with_organic` = Shows overlap (higher = more correlation)

### Step 4: Get Actionable Recommendations
```sql
-- Run the fourth query (Top 100 Investment Opportunities)
-- This gives you specific search terms to target
```

**What to do:**
- Focus on terms with "High Opportunity" categories
- Prioritize by `investment_priority` score
- Target ASINs with multiple high-opportunity terms

## 📈 Interpreting Results

### Strong Positive Correlation (Good!)
- **Paid orders ↑ → Organic orders ↑**
- **Meaning**: Your paid investment is helping organic growth
- **Action**: Continue investing in these terms, they're working!

### Weak/No Correlation (Opportunity!)
- **Paid orders ↑ → Organic orders stay flat**
- **Meaning**: Paid isn't driving organic yet, but there's potential
- **Action**: These are your investment opportunities - focus SEO/content on these terms

### Negative Correlation (Investigate!)
- **Paid orders ↑ → Organic orders ↓**
- **Meaning**: Something unusual happening
- **Action**: Review these terms - may need to reduce paid or investigate cannibalization

## 🎯 Key Metrics to Watch

1. **Investment Priority Score** (0-100+)
   - Higher = Better opportunity
   - Combines: paid performance + gap size + consistency

2. **Order Gap** (paid_orders - organic_orders)
   - Positive = Paid stronger (opportunity to grow organic)
   - Negative = Organic stronger (maybe reduce paid?)

3. **Term Gap** (unique_paid_terms - unique_organic_terms)
   - Shows how many paid terms don't have organic presence
   - Higher = More opportunities

4. **Correlation Coefficients** (-1.0 to +1.0)
   - Shows relationship strength
   - +0.5+ = Strong positive correlation

## 🚀 Next Steps After Running

1. **Identify Top 20 Search Terms** with highest investment priority
2. **Focus on ASINs** with highest opportunity scores
3. **Create SEO/Content Strategy** for high-opportunity terms
4. **Monitor Correlation Trends** over time (run monthly)

## 💡 Pro Tips

- **Start with ASINs** that have high opportunity scores - they'll give you the best ROI
- **Focus on terms** with "High Opportunity - No Organic" first - easiest wins
- **Track correlation over time** - run this analysis monthly to see if correlations strengthen
- **Combine with conversion rates** - high correlation + high conversion = best opportunities

---

**Ready to run?** Open `scripts/Analysis/CORRELATION_ANALYSIS_FOCUSED.sql` and start with the first query!
