# Complete ASIN Insights Report: SQP + Ads Correlation

**Analysis Date:** January 2025  
**Data Sources:** 
- `SQP_ASIN_View_Simple_Week` (Organic Search Performance)
- `V_SRC_AmazonAds_SearchTerms` (Paid Advertising Performance)

---

## Executive Summary

This report combines insights from organic search query performance (SQP) with paid advertising performance to provide a comprehensive view of search term effectiveness and optimization opportunities.

### Key Findings

1. **Gift Card Queries**: 26-35% organic conversion rate - **NEEDS ADS VALIDATION**
2. **Same-Day Shipping**: 11.96% conversion (vs 8.56% for 1-day) - **CRITICAL OPPORTUNITY**
3. **Price Range Sweet Spot**: $25-$35 converts at 16.51% - **PRODUCT STRATEGY**
4. **Underperforming Queries**: 3,268 queries with optimization opportunity
5. **Cross-Channel Gaps**: Need to validate organic insights with paid performance

---

## Part 1: SQP Organic Search Insights

### Top Performing Search Queries

| Rank | Search Query | Organic Purchases | Conversion % | Action |
|------|-------------|-------------------|--------------|--------|
| 1 | gift cards | 1,416,316 | 26.22% | ⭐ **VALIDATE IN ADS** |
| 2 | roblox gift card | 455,752 | 35.20% | ⭐ **VALIDATE IN ADS** |
| 3 | gift card | 407,246 | 25.89% | ⭐ **VALIDATE IN ADS** |
| 4 | teen girl gifts trendy stuff | 392,657 | 6.16% | ✅ Monitor |
| 5 | mothers day gifts | 310,437 | 9.17% | ✅ Monitor |

**Key Insight**: Gift card queries have exceptional conversion rates (25-35%). Need to verify if paid campaigns match this performance.

### Shipping Speed Impact (Organic Data)

| Shipping Speed | Organic Conversion | Impact |
|---------------|-------------------|---------|
| Same Day | **11.96%** | ⭐ Highest |
| 1 Day | 8.56% | Standard |
| 2 Day | 6.84% | Lowest |

**Action Required**: 
- ⚠️ **CRITICAL**: Invest in same-day shipping capability
- 40% conversion lift potential
- Cannot validate in ads data (shipping info not in campaign data)

### Price Sensitivity (Organic Data)

| Price Range | Avg Price | Organic Conversion |
|------------|-----------|-------------------|
| **$25-$35** | $29.33 | **16.51%** ⭐ |
| $15-$25 | $19.35 | 7.74% |
| < $15 | $12.41 | 7.41% |

**Action Required**:
- Target $25-$35 price point for new products
- Bundle products to hit sweet spot
- ⚠️ Cannot directly correlate with ads (price not in campaign data)

---

## Part 2: Correlation Analysis with Paid Ads

### Correlation Queries Available

**File**: `correlate_sqp_with_ads.sql`

#### 1. Top Queries Correlation
**Purpose**: Compare organic vs paid performance for top queries

**Expected Insights**:
- Identify queries performing well in both channels
- Find gaps (high organic, no paid or vice versa)
- Calculate conversion rate differences

**Key Questions**:
- ✅ Are we bidding on our top organic performers?
- ✅ What's the conversion delta between organic and paid?
- ✅ How much organic volume are we capturing with ads?

#### 2. High Conversion Queries
**Purpose**: Identify queries with ≥15% conversion in both channels

**Performance Tiers**:
- **EXCELLENT_BOTH**: Scale aggressively
- **EXCELLENT_ORGANIC**: Test paid campaigns
- **EXCELLENT_PAID**: Leverage organic strategies
- **GOOD_BOTH**: Optimize and scale

#### 3. Gift Card Queries Deep Dive
**Purpose**: Validate gift card opportunity with paid data

**Metrics to Track**:
- ROAS (Return on Ad Spend)
- Paid conversion rate vs organic (26-35%)
- CPA (Cost per Acquisition)
- Campaign effectiveness

**Recommendations**:
- If ROAS ≥ 3.0 and conversion ≥ 25% → **SCALE AGGRESSIVELY**
- If ROAS < 2.0 → **OPTIMIZE CAMPAIGNS**
- If no paid data → **START TESTING CAMPAIGNS**

#### 4. Campaign Effectiveness
**Purpose**: Analyze which campaigns work best for top SQP queries

**ROI Tiers**:
- **HIGH_ROI** (ROAS ≥ 4.0): Scale
- **GOOD_ROI** (ROAS 2.0-4.0): Maintain/Increase
- **BREAK_EVEN** (ROAS 1.0-2.0): Optimize
- **LOW_ROI** (ROAS < 1.0): Pause/Restructure

#### 5. Opportunity Gap Analysis
**Purpose**: Find high organic performers with no/low paid investment

**Priority Matrix**:

| Organic Conversion | Ads Coverage | Priority | Action |
|-------------------|--------------|----------|--------|
| ≥20% | None | 🔴 **HIGH** | Start campaigns immediately |
| ≥15% | None | 🟡 **MEDIUM** | Test campaigns |
| ≥10% | <10% of organic | 🟡 **MEDIUM** | Increase spend |
| Any | ≥50% of organic | 🟢 **MONITOR** | Maintain |

#### 6. Performance Validation
**Purpose**: Validate SQP insights with actual paid performance

**Validation Status**:
- **VALIDATED_HIGH_VALUE**: ROAS ≥ 3.0, conversion within 90% of organic → **Scale**
- **VALIDATED_GOOD_VALUE**: ROAS ≥ 2.0, conversion within 80% of organic → **Maintain**
- **NEEDS_OPTIMIZATION**: ROAS < 1.5 → **Pause/Restructure**
- **MONITOR**: Track trends → **Continue monitoring**

---

## Part 3: Integrated Recommendations

### Priority 1: Gift Card Query Validation 🔴

**From SQP Insights**:
- Gift card queries convert at 26-35% organically
- "gift cards" = 1.4M purchases, 26.22% conversion
- "roblox gift card" = 455K purchases, 35.20% conversion

**Correlation Action Required**:
1. Run Correlation Query #3 (Gift Card Deep Dive)
2. Check if these queries exist in paid campaigns
3. Calculate ROAS for gift card campaigns
4. Compare paid conversion vs organic (target: ≥25%)

**Expected Outcomes**:
- ✅ If ROAS ≥ 3.0 → Scale gift card campaigns
- ⚠️ If ROAS < 2.0 → Optimize campaigns
- 🆕 If no paid data → Launch test campaigns

### Priority 2: Opportunity Gap Analysis 🟡

**From SQP Insights**:
- 3,054 queries with 10+ organic purchases
- Top 20 queries range from 75K to 1.4M purchases

**Correlation Action Required**:
1. Run Correlation Query #5 (Opportunity Gap)
2. Identify top queries with no/low paid coverage
3. Prioritize by organic conversion rate
4. Create campaign launch plan

**Expected Outcomes**:
- New campaigns for high-priority gaps
- Increased coverage of high-performing queries
- Revenue growth from untapped opportunities

### Priority 3: Campaign Optimization 🟢

**From SQP Insights**:
- 3,268 underperforming queries (high volume, low conversion)
- Average CTR: 1.15%, Conversion: 8.74%

**Correlation Action Required**:
1. Run Correlation Query #6 (Performance Validation)
2. Identify underperforming queries in both channels
3. Pause low-ROI paid campaigns
4. Optimize campaign structure for high performers

**Expected Outcomes**:
- Improved ROAS across campaigns
- Reduced wasted spend
- Better budget allocation

---

## Action Plan

### Week 1: Correlation Analysis

- [ ] Execute all 6 correlation queries in BigQuery
- [ ] Export results and create summary tables
- [ ] Review gift card query performance (Priority 1)
- [ ] Identify top 20 opportunity gaps (Priority 2)

### Week 2: Validation & Planning

- [ ] Validate gift card insights with paid data
- [ ] Create campaign launch plan for opportunity gaps
- [ ] Review campaign performance for optimization
- [ ] Prioritize actions by ROI potential

### Week 3-4: Implementation

- [ ] Launch gift card campaigns (if validated)
- [ ] Start campaigns for top opportunity gaps
- [ ] Optimize/pause underperforming campaigns
- [ ] Set up monitoring dashboards

### Month 2+: Monitoring & Optimization

- [ ] Review correlation metrics weekly
- [ ] Track ROI improvements
- [ ] Identify new opportunity gaps
- [ ] Refine strategy based on results

---

## Success Metrics

### Quantitative KPIs

1. **ROAS Improvement**
   - Target: Increase average ROAS by 20%
   - Measure: Compare before/after correlation analysis

2. **Query Coverage**
   - Target: Cover 50% of top 100 organic queries with paid ads
   - Measure: % of SQP queries with corresponding ads

3. **Conversion Rate Optimization**
   - Target: Match or exceed organic conversion in paid channels
   - Measure: Paid conversion vs organic conversion ratio

4. **Revenue Growth**
   - Target: 15% increase from new campaigns
   - Measure: Revenue from newly launched campaigns

### Qualitative KPIs

1. **Data-Driven Decisions**
   - % of decisions based on correlation insights
   - Reduced guesswork in campaign planning

2. **Cross-Channel Synergy**
   - Unified strategy for organic and paid
   - Shared learnings between channels

---

## Files Generated

### Analysis Scripts
1. **`generate_asin_insights_simple.py`** - Python script for SQP analysis (standard library only)
2. **`correlate_sqp_with_ads.sql`** - SQL queries for correlation analysis

### Documentation
3. **`ASIN_INSIGHTS_SUMMARY.md`** - SQP insights summary
4. **`CORRELATION_ANALYSIS.md`** - Detailed correlation methodology
5. **`COMPLETE_INSIGHTS_REPORT.md`** - This integrated report

### Output Files
6. **`asin_insights_report.txt`** - Raw analysis output from Python script

---

## Next Steps

1. **Run Correlation Queries**
   ```bash
   # In BigQuery Console, execute queries from:
   scripts/Admin/correlate_sqp_with_ads.sql
   ```

2. **Review Results**
   - Focus on Correlation #1 (Top Queries) first
   - Then Correlation #3 (Gift Cards)
   - Finally Correlation #5 (Opportunity Gaps)

3. **Create Action Plan**
   - Prioritize recommendations by ROI potential
   - Assign ownership for implementation
   - Set up tracking and reporting

4. **Implement & Monitor**
   - Execute high-priority actions
   - Monitor performance weekly
   - Iterate based on results

---

## Questions to Answer

### Critical Questions
1. ✅ Are gift card queries profitable in paid campaigns?
2. ✅ What's the conversion rate difference between organic and paid?
3. ✅ Which top organic queries have no paid coverage?

### Strategic Questions
4. ✅ Which campaigns have highest ROAS for top queries?
5. ✅ Are we under-investing in high-converting queries?
6. ✅ What can we learn from paid to improve organic?

### Optimization Questions
7. ✅ Which underperforming organic queries are wasting ad spend?
8. ✅ How can we optimize campaign structure based on query performance?
9. ✅ What's the optimal budget allocation across query types?

---

*Complete Insights Report - January 2025*  
*For questions or additional analysis, see `scripts/Admin/` directory*
