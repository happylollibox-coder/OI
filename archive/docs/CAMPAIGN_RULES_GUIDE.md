# 🎯 Campaign Rules Guide: 5 Clicks = 1 Order

## Your Goal
Find search terms and ASINs where **5 paid clicks = 1 order** (either paid or organic), then create campaigns with exact rules based on this ratio.

## 📊 Understanding the Analysis

### Key Metric: `orders_per_paid_click`
- **Target**: ≥ 0.2 (1 order per 5 clicks = 20% conversion)
- **Calculation**: `(Paid Orders + Organic Orders) / Paid Clicks`
- **Example**: 10 paid clicks → 2 total orders = 0.2 ✅

### Why This Matters
When you find terms/ASINs with `orders_per_paid_click >= 0.2`, you can:
1. **Scale campaigns** with confidence
2. **Set bid rules** based on expected conversion
3. **Forecast orders** from click volume
4. **Optimize budget** allocation

---

## 🔍 How to Use the Results

### Query 1: `FIND_5_CLICKS_TO_1_ORDER.sql`
**Purpose**: Find search terms that achieve 5:1 ratio

**Key Columns to Review**:
- `orders_per_paid_click` - Should be ≥ 0.2
- `meets_5_to_1_ratio` - TRUE = Meets target
- `campaign_action` - What to do with this term
- `campaign_rule_score` - Higher = Better for rules

**Filter For**:
```sql
WHERE orders_per_paid_click >= 0.2
  AND total_paid_clicks >= 20  -- Minimum volume for reliability
  AND weeks_active >= 3  -- Consistency
```

### Query 2: `CAMPAIGN_RULES_BY_ASIN.sql`
**Purpose**: Find ASINs that consistently achieve 5:1 ratio

**Key Columns to Review**:
- `orders_per_paid_click` - Should be ≥ 0.2
- `weeks_meeting_5_to_1` - How many weeks met target
- `consistency_status` - "VERY CONSISTENT" = Best
- `asin_campaign_rule` - Specific rule for this ASIN

**Filter For**:
```sql
WHERE orders_per_paid_click >= 0.2
  AND weeks_meeting_5_to_1 >= weeks_active * 0.7  -- 70%+ consistency
  AND total_paid_clicks >= 25
```

---

## 🚀 Creating Campaign Rules

### Rule Type 1: Search Term Level Rules

**For terms with `orders_per_paid_click >= 0.2`**:

#### Rule: "Scale High-Performing Terms"
```
IF orders_per_paid_click >= 0.2 
  AND total_paid_clicks >= 20
  AND weeks_active >= 3
THEN:
  - Increase bid by 10-20%
  - Increase daily budget
  - Add to high-priority campaign
```

#### Rule: "Maintain Target Terms"
```
IF orders_per_paid_click >= 0.2 
  AND total_paid_clicks < 20
THEN:
  - Maintain current bid
  - Test scaling gradually
  - Monitor for consistency
```

#### Rule: "Optimize Close-to-Target Terms"
```
IF orders_per_paid_click >= 0.15 AND < 0.2
  AND total_paid_clicks >= 15
THEN:
  - Optimize ad copy
  - Test different match types
  - Improve landing page
  - Goal: Reach 0.2 ratio
```

### Rule Type 2: ASIN Level Rules

**For ASINs with `orders_per_paid_click >= 0.2`**:

#### Rule: "Scale Consistent ASINs"
```
IF orders_per_paid_click >= 0.2
  AND weeks_meeting_5_to_1 >= weeks_active * 0.7
  AND total_paid_clicks >= 25
THEN:
  - Create dedicated campaign for this ASIN
  - Increase budget allocation
  - Add all high-performing search terms
  - Set bid rules: 5 clicks expected = 1 order
```

#### Rule: "Optimize ASIN Campaigns"
```
IF orders_per_paid_click >= 0.15 AND < 0.2
  AND total_paid_clicks >= 25
THEN:
  - Review all search terms for this ASIN
  - Pause low-performing terms
  - Focus on terms close to 0.2
  - Optimize product listing
```

---

## 📋 Campaign Creation Workflow

### Step 1: Identify Target Terms/ASINs
1. Run `FIND_5_CLICKS_TO_1_ORDER.sql`
2. Filter: `orders_per_paid_click >= 0.2` AND `total_paid_clicks >= 20`
3. Export top 50 terms

### Step 2: Group by Campaign Rules
Create campaigns based on performance tiers:

**Campaign 1: "5:1 Ratio Champions"**
- Terms with `orders_per_paid_click >= 0.2`
- `campaign_rule_score >= 50`
- `weeks_active >= 4`
- **Action**: Scale aggressively

**Campaign 2: "5:1 Ratio Maintainers"**
- Terms with `orders_per_paid_click >= 0.2`
- `campaign_rule_score 30-50`
- `weeks_active 2-3`
- **Action**: Maintain and test scale

**Campaign 3: "Close to Target"**
- Terms with `orders_per_paid_click 0.15-0.2`
- `total_paid_clicks >= 15`
- **Action**: Optimize to reach 0.2

### Step 3: Set Campaign Rules

For each campaign, set rules:

```
BID RULE:
- If clicks < 5: Maintain bid
- If clicks >= 5 AND orders < 1: Reduce bid 10%
- If clicks >= 5 AND orders >= 1: Increase bid 10%
- If clicks >= 10 AND orders >= 2: Increase bid 20%

BUDGET RULE:
- Expected orders = clicks / 5
- Set daily budget to support target orders
- Example: 50 clicks/day = 10 orders/day expected

PAUSE RULE:
- If clicks >= 15 AND orders < 2: Pause (below 5:1)
- If clicks >= 25 AND orders < 4: Pause (below 6.25:1)
```

### Step 4: Monitor and Adjust

**Weekly Review**:
1. Check if terms still meet 5:1 ratio
2. Identify new terms that reached 0.2
3. Pause terms that dropped below 0.15
4. Adjust bids based on performance

---

## 💡 Key Insights from Analysis

### Insight 1: Organic Contribution
Look at `pct_orders_from_organic`:
- **High % (50%+)**: Paid clicks are driving strong organic orders
- **Low % (<20%)**: Mostly direct paid conversions
- **Action**: High organic % = Better ROI (free orders!)

### Insight 2: Consistency
Look at `weeks_meeting_5_to_1`:
- **High consistency (70%+)**: Reliable, can scale confidently
- **Low consistency (<30%)**: Unreliable, needs optimization

### Insight 3: Volume vs Efficiency
- **High volume + 5:1 ratio**: Best opportunities (scale these)
- **Low volume + 5:1 ratio**: Test scaling carefully
- **High volume + <5:1 ratio**: Optimize to reach target

---

## 🎯 Expected Results

### After Implementing Rules:

**Week 1-2**:
- Identify 20-50 terms meeting 5:1 ratio
- Create campaigns with rules
- Set initial bids and budgets

**Week 3-4**:
- Monitor performance
- Adjust bids based on actual 5:1 ratio
- Scale high performers

**Week 5-8**:
- 20-30% improvement in overall conversion efficiency
- Better budget allocation
- More predictable order forecasting

**Week 9-12**:
- Established baseline of terms meeting 5:1
- Automated rules working effectively
- 30-40% improvement in ROI

---

## 📊 Success Metrics

Track these KPIs:

1. **% of Terms Meeting 5:1 Ratio**
   - Target: Increase from baseline
   - Track monthly

2. **Average Orders per Paid Click**
   - Target: ≥ 0.2 (5:1 ratio)
   - Track weekly

3. **Campaign Efficiency**
   - Compare campaigns with rules vs without
   - Measure ROI improvement

4. **Order Forecasting Accuracy**
   - Expected orders = clicks / 5
   - Compare to actual orders
   - Target: 90%+ accuracy

---

## 🚨 Common Pitfalls to Avoid

1. **Don't scale too fast**: Test with small budgets first
2. **Monitor organic contribution**: High organic % = better
3. **Check consistency**: One week of 5:1 isn't enough
4. **Review regularly**: Ratios can change over time
5. **Consider seasonality**: Some terms may be seasonal

---

## ✅ Quick Start Checklist

- [ ] Run `FIND_5_CLICKS_TO_1_ORDER.sql`
- [ ] Filter for `orders_per_paid_click >= 0.2`
- [ ] Export top 50 terms
- [ ] Run `CAMPAIGN_RULES_BY_ASIN.sql`
- [ ] Identify top 20 ASINs
- [ ] Create campaigns with rules
- [ ] Set bid and budget rules
- [ ] Monitor weekly performance
- [ ] Adjust based on actual ratios

---

**Remember**: The goal is to find terms/ASINs where 5 paid clicks consistently = 1 order, then create campaigns with rules based on this proven ratio! 🎯
