# 🎯 Pilot Candidates Guide: Finding the Best Terms for Testing

## Your Criteria for Pilot Candidates

1. **Order Ratio ≥ 0.2** (5 clicks = 1 order) - Higher is better
2. **Consistency** - Maintained ratio over last 6 months
3. **Seasonality** - Better performance vs same month last year

## 📊 Understanding the Pilot Candidate Score

### Scoring System (0-100 points)

**Ratio Score (0-40 points)**:
- ≥ 0.3 (3.3:1 ratio): 40 points - Excellent
- ≥ 0.25 (4:1 ratio): 35 points - Very good
- ≥ 0.2 (5:1 ratio): 30 points - Meets target ✅
- ≥ 0.15 (6.7:1 ratio): 20 points - Close
- < 0.15: 10 points - Below target

**Consistency Score (0-30 points)**:
- ≥ 0.8 (80%+ months met target): 30 points - Very consistent
- ≥ 0.6 (60-80%): 25 points - Consistent
- ≥ 0.4 (40-60%): 20 points - Moderate
- ≥ 0.2 (20-40%): 15 points - Some consistency
- < 0.2: 10 points - Inconsistent

**Seasonality Score (0-20 points)**:
- 20%+ better than last year: 20 points - Much better
- 10-20% better: 15 points - Better
- Better than last year: 10 points - Improved
- No last year data but meets target: 15 points - New opportunity
- Similar/worse: 5 points - No improvement

**Volume Score (0-10 points)**:
- ≥ 100 clicks in 6 months: 10 points
- ≥ 50 clicks: 8 points
- ≥ 25 clicks: 6 points
- < 25 clicks: 4 points

### Total Pilot Candidate Score
- **80-100**: 🔥 EXCELLENT - Top priority for pilot
- **60-79**: ✅ STRONG - Great candidates
- **40-59**: 💡 GOOD - Consider for pilot
- **< 40**: 📊 MONITOR - Needs improvement

---

## 🎯 How to Use the Results

### Step 1: Run the Query
Execute `FIND_PILOT_CANDIDATES.sql` in BigQuery

### Step 2: Filter for Best Candidates
**Top Tier (Start Here)**:
```sql
WHERE pilot_candidate_score >= 70
  AND orders_per_click_6m >= 0.2
  AND consistency_score_6m >= 0.6
  AND better_than_last_year = TRUE
```

**Second Tier**:
```sql
WHERE pilot_candidate_score >= 60
  AND orders_per_click_6m >= 0.2
  AND consistency_score_6m >= 0.4
```

**Third Tier**:
```sql
WHERE pilot_candidate_score >= 50
  AND orders_per_click_6m >= 0.15
```

### Step 3: Review Key Metrics

**Must Have**:
- ✅ `orders_per_click_6m >= 0.2` (Meets 5:1 target)
- ✅ `consistency_score_6m >= 0.4` (At least 40% consistency)
- ✅ `pilot_candidate_score >= 60` (Strong candidate)

**Nice to Have**:
- 🔥 `better_than_last_year = TRUE` (Seasonal improvement)
- 🔥 `consistency_score_6m >= 0.6` (High consistency)
- 🔥 `orders_per_click_6m >= 0.25` (Better than 5:1)

### Step 4: Create Pilot Campaigns

**For Top Candidates (Score ≥ 70)**:
- Create dedicated pilot campaign
- Set higher budgets
- Scale aggressively
- Monitor closely

**For Good Candidates (Score 60-69)**:
- Create pilot campaign
- Set moderate budgets
- Test scaling
- Optimize based on results

**For Moderate Candidates (Score 50-59)**:
- Include in broader test
- Lower initial budgets
- Monitor for improvement
- Optimize to reach 0.2 ratio

---

## 📋 Pilot Campaign Setup Rules

### Rule 1: Budget Allocation
```
IF pilot_candidate_score >= 70:
  Daily Budget = Expected Clicks * 0.2 (5:1 ratio)
  Example: 50 clicks/day = 10 orders/day expected

IF pilot_candidate_score 60-69:
  Daily Budget = Expected Clicks * 0.15 (conservative)
  
IF pilot_candidate_score 50-59:
  Daily Budget = Expected Clicks * 0.1 (test mode)
```

### Rule 2: Bid Strategy
```
IF orders_per_click_6m >= 0.25:
  Start with higher bids (top of range)
  
IF orders_per_click_6m >= 0.2:
  Start with medium bids
  
IF orders_per_click_6m >= 0.15:
  Start with lower bids, optimize up
```

### Rule 3: Monitoring
```
Week 1-2: Monitor daily
  - Check if maintaining 5:1 ratio
  - Adjust bids if needed
  
Week 3-4: Weekly review
  - Compare to historical performance
  - Scale if meeting targets
  
Week 5-8: Monthly review
  - Evaluate pilot success
  - Decide on full rollout
```

---

## 🎯 Expected Results by Score Tier

### Top Tier (Score ≥ 70)
- **Expected**: Maintain 5:1 ratio or better
- **Action**: Scale aggressively
- **Timeline**: 4-6 weeks to full rollout

### Strong Tier (Score 60-69)
- **Expected**: Maintain or improve ratio
- **Action**: Scale gradually
- **Timeline**: 6-8 weeks to full rollout

### Good Tier (Score 50-59)
- **Expected**: Reach 5:1 ratio with optimization
- **Action**: Test and optimize
- **Timeline**: 8-12 weeks to evaluate

---

## 💡 Key Insights from Analysis

### Insight 1: Consistency Matters
- Terms with `consistency_score_6m >= 0.6` are more reliable
- Even if ratio is slightly below 0.2, high consistency = good candidate
- **Action**: Prioritize consistent performers

### Insight 2: Seasonality is Important
- Terms that performed better last year = proven seasonal winners
- **Action**: Focus on these for seasonal campaigns

### Insight 3: Volume + Ratio = Confidence
- High volume (100+ clicks) + good ratio = high confidence
- **Action**: Scale these first

### Insight 4: Current Month Performance
- Check `current_month_meets_target` - is it still performing?
- **Action**: If current month is weak, investigate before pilot

---

## 📊 Success Metrics for Pilot

### Week 1-2:
- [ ] Maintain 5:1 ratio (or better)
- [ ] No significant drop in performance
- [ ] Orders tracking as expected

### Week 3-4:
- [ ] Ratio maintained or improved
- [ ] Budget efficiency meeting targets
- [ ] Ready to scale

### Week 5-8:
- [ ] Pilot success rate (how many met targets)
- [ ] ROI improvement vs baseline
- [ ] Decision on full rollout

---

## ✅ Quick Start Checklist

- [ ] Run `FIND_PILOT_CANDIDATES.sql`
- [ ] Filter for `pilot_candidate_score >= 60`
- [ ] Review top 50 candidates
- [ ] Check consistency and seasonality
- [ ] Create pilot campaigns
- [ ] Set budgets based on scores
- [ ] Monitor weekly performance
- [ ] Scale successful pilots

---

## 🚨 Red Flags to Watch

1. **Low Consistency** (< 0.4): Unreliable, may not maintain ratio
2. **Worse Than Last Year**: May indicate declining trend
3. **Current Month Weak**: Recent performance drop
4. **Low Volume** (< 25 clicks): Not enough data for confidence

---

**Remember**: The best pilot candidates have:
- ✅ Ratio ≥ 0.2 (5:1)
- ✅ Consistency ≥ 0.6 (60%+ months)
- ✅ Better than last year (seasonal improvement)
- ✅ High pilot candidate score (≥ 70)

Focus on these for your pilot! 🚀
