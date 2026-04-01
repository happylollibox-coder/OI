# Correlation Analysis: Ready Checklist

## ✅ What I've Created

1. **CORRELATION_ANALYSIS_PLAN.md** - Comprehensive analysis plan with:
   - Data structure overview
   - Key questions to answer
   - Required information checklist
   - Proposed analysis approach
   - Expected deliverables

2. **CORRELATION_ORGANIC_VS_PAID_SEARCH.sql** - Ready-to-run SQL queries for:
   - Phase 1: Data exploration & validation
   - Phase 2: Correlation analysis (matched terms)
   - Phase 3: Opportunity identification (unique paid terms, ASIN summaries)
   - Phase 4: Statistical correlation coefficients

## 🔍 What I Need to Know to Complete the Analysis

### Critical Questions (Must Answer Before Running Analysis)

#### 1. **Date Alignment** ⚠️ CRITICAL
- **Question**: Does `Reporting_Date` in `FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` represent the same week as `week_end_date` in `V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY`?
- **Why**: Both tables need to align on the same week definition to compare performance
- **Action**: 
  - Check if both use Sunday-starting weeks (TimeDIM standard)
  - Or verify the week definition used in your data sources
  - **Quick Test**: Run this query to check alignment:
    ```sql
    SELECT 
      org.Reporting_Date,
      paid.week_end_date,
      COUNT(*) as matches
    FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` org
    INNER JOIN `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` paid
      ON org.Reporting_Date = paid.week_end_date
    GROUP BY 1, 2
    ORDER BY 1 DESC
    LIMIT 10;
    ```

#### 2. **Search Term Matching Logic** ⚠️ CRITICAL
- **Question**: How should we match `Search_Query` (organic) with `search_term` (paid)?
- **Current Assumption**: Case-insensitive, trimmed whitespace
- **Need to Verify**:
  - Are there variations in how terms are stored? (e.g., "dog toy" vs "dog-toy" vs "dogtoy")
  - Should we use fuzzy matching or exact matching?
  - Are there any special characters that need normalization?
- **Action**: Review sample data from both tables to understand matching requirements

#### 3. **Metric Definitions** ⚠️ IMPORTANT
- **Question**: Are `ORDERS` in both tables comparable?
  - Attribution window: 30-day vs immediate?
  - Order definition: Same across both sources?
- **Question**: What does `Search_Query_Score` represent?
  - Is it relevance score, ranking position, or something else?
- **Action**: Confirm metric definitions match your business logic

#### 4. **Business Priorities** 📊 IMPORTANT
- **Question**: What's your primary goal?
  - [ ] Find search terms to invest in for organic growth
  - [ ] Identify ASINs with highest growth potential
  - [ ] Reduce paid spend where organic performs better
  - [ ] All of the above
- **Question**: What's the minimum threshold for "opportunity"?
  - Minimum paid orders to consider?
  - Minimum conversion rate threshold?
  - Timeframe for analysis (last 4 weeks, 8 weeks, etc.)?

#### 5. **Data Quality** ✅ CAN RUN QUERIES TO CHECK
- **Question**: What date range should we analyze?
- **Question**: Are there any known data quality issues?
- **Action**: The SQL queries include data quality checks - we can run these first

### Optional but Helpful Information

- **Product Categories**: Should we filter by specific product types or analyze all?
- **Campaign Types**: Should we include all campaign types or filter (SP, SB, etc.)?
- **Sales Module Focus**: Should we focus on specific `inferred_sales_module` values?
- **Historical Context**: Do you have historical data showing organic growth after paid investment?

## 🚀 Next Steps

### Immediate Actions (You Can Do Now)

1. **Run Data Exploration Queries** (Phase 1 in SQL file)
   - These will show data ranges, overlaps, and quality
   - No business logic assumptions needed

2. **Review Sample Data**
   - Check a few rows from both tables to understand:
     - Date formats
     - Search term formats
     - Metric values

3. **Answer Critical Questions Above**
   - Especially date alignment and search term matching

### After Getting Answers

1. **Adjust SQL Queries** based on your answers
2. **Run Full Correlation Analysis**
3. **Generate Opportunity Reports**
4. **Create Actionable Recommendations**

## 📋 Quick Start Guide

1. **First, run Phase 1 queries** to understand your data:
   ```sql
   -- Copy Phase 1 queries from CORRELATION_ORGANIC_VS_PAID_SEARCH.sql
   -- These will show you data ranges and quality
   ```

2. **Check date alignment**:
   ```sql
   -- Use the date alignment test query above
   ```

3. **Review sample search terms**:
   ```sql
   SELECT DISTINCT Search_Query 
   FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
   WHERE Search_Query IS NOT NULL
   LIMIT 20;
   
   SELECT DISTINCT search_term 
   FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY`
   WHERE search_term IS NOT NULL
   LIMIT 20;
   ```

4. **Share findings** and I'll adjust the analysis queries accordingly

## 💡 What the Analysis Will Tell You

Once we have the answers above, the analysis will provide:

1. **Top 100 Unique Paid Search Terms** with no organic presence (highest opportunity)
2. **ASIN-Level Investment Priorities** ranked by growth potential
3. **Correlation Metrics** showing relationship strength between paid and organic
4. **Efficiency Gaps** identifying where to reduce paid spend
5. **Actionable Recommendations** per ASIN with specific search terms to target

---

**Ready to proceed?** Share the answers to the critical questions, and I'll customize the analysis queries for your specific needs!
