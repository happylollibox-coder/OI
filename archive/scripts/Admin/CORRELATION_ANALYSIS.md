# Correlation Analysis: SQP vs Amazon Ads Performance

## Overview

This analysis correlates insights from **SQP_ASIN_View_Simple_Week** (organic search query performance) with **V_SRC_AmazonAds_SearchTerms** (paid advertising performance) to validate insights and identify optimization opportunities.

---

## Data Sources Comparison

### SQP_ASIN_View_Simple_Week (Organic Search Performance)
- **Source**: Amazon Search Query Performance (organic search results)
- **Metrics**: Impressions, clicks, cart adds, purchases from organic search
- **Focus**: Overall search query performance across Amazon platform
- **Time Period**: Weekly aggregated data
- **Key Insight**: Shows what customers are searching for and converting on organically

### V_SRC_AmazonAds_SearchTerms (Paid Advertising Performance)
- **Source**: Amazon Ads campaign data (Sponsored Products, Sponsored Brands)
- **Metrics**: Impressions, clicks, cost, orders, sales from paid campaigns
- **Focus**: Performance of paid advertising campaigns
- **Time Period**: Daily aggregated data (filtered from 2025-10-28)
- **Key Insight**: Shows which search terms are profitable in paid campaigns

---

## Correlation Insights

### 1. Top Queries Correlation

**Purpose**: Compare top performing queries from organic search with paid ads performance.

**Key Questions Answered**:
- Are we bidding on our top organic performers?
- What's the conversion difference between organic and paid?
- How much of organic search volume are we capturing with ads?

**Expected Findings**:
- **BOTH**: Query performs well in both organic and paid → Validate, maintain/expand investment
- **SQP_ONLY**: High organic performance, low/no paid → **Opportunity**: Start bidding
- **ADS_ONLY**: High paid performance, low/no organic → **Opportunity**: Improve SEO/listing

**Business Impact**:
- Identify gaps in advertising coverage
- Validate organic insights with paid performance
- Optimize bid strategy based on organic-to-paid conversion ratios

---

### 2. High Conversion Queries Analysis

**Purpose**: Identify queries with high conversion rates in both organic and paid channels.

**Performance Tiers**:
- **EXCELLENT_BOTH**: ≥20% organic conversion AND ≥15% paid conversion
  - Action: **Increase investment, expand to similar queries**
- **EXCELLENT_ORGANIC**: ≥20% organic conversion
  - Action: **Test paid campaigns on these queries**
- **EXCELLENT_PAID**: ≥15% paid conversion
  - Action: **Leverage organic strategies from paid insights**
- **GOOD_BOTH**: Both channels performing well but below excellent thresholds
  - Action: **Optimize and scale**

**Business Impact**:
- Focus investment on highest-performing query types
- Cross-channel learning and optimization
- Identify sustainable growth opportunities

---

### 3. Gift Card Queries Deep Dive

**Purpose**: Analyze gift card queries (top performer from SQP insights - 26-35% conversion).

**Key Metrics to Track**:
- **ROAS**: Return on ad spend (sales/cost)
- **Conversion Rate**: Orders/clicks
- **CPA**: Cost per acquisition
- **Campaign Performance**: Which campaigns are most effective

**Recommendations**:
- **PRIORITY_INVEST**: High conversion in both → Increase budget
- **INVEST_IN_ADS**: High organic, low paid → Start bidding
- **LEVERAGE_ORGANIC**: High paid, lower organic → Improve SEO
- **MONITOR**: Moderate performance in both → Continue monitoring

**Business Impact**:
- Validate gift card opportunity from SQP insights
- Optimize campaign structure for gift card queries
- Capitalize on high-intent, high-converting search terms

---

### 4. Campaign Effectiveness by Query Type

**Purpose**: Analyze which campaigns are most effective for top SQP queries.

**ROI Tiers**:
- **HIGH_ROI** (ROAS ≥ 4.0): Exceptional return, scale aggressively
- **GOOD_ROI** (ROAS 2.0-4.0): Profitable, maintain/increase budget
- **BREAK_EVEN** (ROAS 1.0-2.0): Monitor, optimize for profitability
- **LOW_ROI** (ROAS < 1.0): Needs immediate optimization or pause

**Business Impact**:
- Reallocate budget from low-ROI to high-ROI campaigns
- Identify campaign structure best practices
- Optimize campaign-level performance

---

### 5. Opportunity Gap Analysis

**Purpose**: Identify high-performing organic queries with no/low paid investment.

**Coverage Status**:
- **NO_ADS_INVESTMENT**: High organic performance, no paid spend → **High priority**
- **UNDER_INVESTED**: Paid impressions < 10% of organic → **Increase spend**
- **PARTIAL_COVERAGE**: Paid impressions 10-50% of organic → **Monitor and optimize**
- **WELL_COVERED**: Paid impressions ≥ 50% of organic → **Maintain**

**Priority Recommendations**:
- **HIGH_PRIORITY_INVEST**: ≥20% organic conversion, no ads → Start immediately
- **MEDIUM_PRIORITY_INVEST**: ≥15% organic conversion, no ads → Test campaigns
- **INCREASE_SPEND**: High organic, low paid coverage → Scale existing campaigns
- **MONITOR**: Moderate performance → Track trends

**Business Impact**:
- Identify untapped opportunities
- Prioritize new campaign launches
- Maximize coverage of high-performing queries

---

### 6. Performance Validation

**Purpose**: Validate SQP insights with actual paid advertising performance.

**Performance Comparison**:
- **ADS_OUTPERFORMING**: Paid conversion > 20% higher than organic
  - Action: Learn from paid strategies, apply to organic/SEO
- **ADS_UNDERPERFORMING**: Paid conversion < 80% of organic
  - Action: Optimize ads (copy, landing pages, bids)
- **CONSISTENT_PERFORMANCE**: Similar conversion rates (±20%)
  - Action: Validate insights, maintain strategy

**Validation Status**:
- **VALIDATED_HIGH_VALUE**: ROAS ≥ 3.0, conversion within 90% of organic
  - Action: **Scale and expand**
- **VALIDATED_GOOD_VALUE**: ROAS ≥ 2.0, conversion within 80% of organic
  - Action: **Maintain and optimize**
- **NEEDS_OPTIMIZATION**: ROAS < 1.5
  - Action: **Pause or restructure campaigns**
- **MONITOR**: Performance metrics need tracking
  - Action: **Continue monitoring**

**Business Impact**:
- Validate strategic decisions with data
- Identify optimization opportunities
- Build confidence in cross-channel strategies

---

## Key Correlations to Validate

### From SQP Insights:

1. **Gift Card Queries (26-35% conversion)**
   - ✅ Validate if these queries have corresponding paid campaigns
   - ✅ Check ROAS for gift card campaigns
   - ✅ Identify gaps where we're not bidding

2. **Same-Day Shipping Impact (11.96% conversion)**
   - ⚠️ Cannot directly correlate (not in ads data)
   - 💡 Action: Track in campaign notes/analysis

3. **$25-$35 Price Range (16.51% conversion)**
   - ⚠️ Cannot directly correlate (not in ads data)
   - 💡 Action: Cross-reference with product-level data

4. **Underperforming Queries (high volume, low conversion)**
   - ✅ Identify which underperforming organic queries are in paid campaigns
   - ✅ Determine if paid performance matches organic
   - ✅ Recommend pausing low-performing paid queries

---

## Actionable Recommendations

### Immediate Actions (0-2 weeks)

1. **Run Correlation Queries**
   - Execute `correlate_sqp_with_ads.sql` in BigQuery
   - Review all 6 correlation analyses
   - Prioritize based on business impact

2. **Gift Card Campaign Audit**
   - Identify all gift card queries in ads data
   - Calculate ROAS for gift card campaigns
   - Compare conversion rates with SQP insights

3. **Opportunity Gap Review**
   - List top 20 SQP queries with no ads coverage
   - Prioritize based on conversion rate
   - Create campaign launch plan

### Short-Term Actions (2-8 weeks)

1. **Campaign Optimization**
   - Reallocate budget from low-ROI to high-ROI campaigns
   - Pause or restructure underperforming campaigns
   - Scale high-performing campaigns

2. **New Campaign Launches**
   - Launch campaigns for high-priority opportunity gaps
   - Test queries with 15%+ organic conversion
   - Monitor and optimize based on paid performance

3. **Cross-Channel Learning**
   - Apply high-performing paid strategies to organic/SEO
   - Use organic insights to inform paid bidding strategies
   - Create unified search query strategy

### Long-Term Actions (2-6 months)

1. **Ongoing Monitoring**
   - Set up automated reporting for correlation metrics
   - Track trends over time
   - Identify seasonal patterns

2. **Strategic Alignment**
   - Align organic and paid search strategies
   - Create unified keyword/query strategy
   - Develop cross-channel optimization framework

---

## Expected Outcomes

### Quantitative Benefits

1. **Increased Ad Efficiency**
   - Higher ROAS through optimized query targeting
   - Reduced wasted spend on low-performing queries
   - Better budget allocation

2. **Improved Organic Performance**
   - Learnings from paid campaigns applied to SEO
   - Better content optimization based on query performance
   - Increased organic visibility

3. **Revenue Growth**
   - Capture untapped opportunities (SQP_ONLY queries)
   - Scale high-performing queries
   - Optimize conversion rates across channels

### Qualitative Benefits

1. **Better Decision Making**
   - Data-driven insights validated across channels
   - Clear prioritization framework
   - Reduced guesswork in strategy

2. **Cross-Channel Synergy**
   - Unified search strategy
   - Leverage strengths of both channels
   - Improved overall search presence

---

## Running the Analysis

### Prerequisites
- BigQuery access to `onyga-482313.OI` dataset
- Access to both `SQP_ASIN_View_Simple_Week` table and `V_SRC_AmazonAds_SearchTerms` view

### Execution Steps

1. **Open BigQuery Console**
   - Navigate to project: `onyga-482313`
   - Dataset: `OI`

2. **Run Correlation Queries**
   ```sql
   -- Run queries from correlate_sqp_with_ads.sql
   -- Start with Correlation 1 (Top Queries) for overview
   -- Then run other correlations based on priorities
   ```

3. **Analyze Results**
   - Export results to CSV/Google Sheets
   - Create visualizations (recommendations, ROI tiers, etc.)
   - Share with stakeholders

4. **Create Action Plan**
   - Prioritize recommendations by business impact
   - Assign ownership for implementation
   - Set up monitoring and reporting

### Expected Query Runtime
- Correlation 1-6: ~30 seconds to 2 minutes each
- Total analysis time: ~10-15 minutes
- Results size: 50-500 rows per query (depending on data volume)

---

## Next Steps

1. ✅ Execute correlation queries in BigQuery
2. ✅ Review and prioritize findings
3. ✅ Create implementation plan
4. ✅ Set up monitoring dashboards
5. ✅ Schedule regular correlation reviews (monthly/quarterly)

---

*Generated: January 2025*  
*For questions or additional analysis, see `scripts/Admin/` directory*
