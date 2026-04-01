# Currency Exchange Rates - Data Policy

## 🚫 **NO FUTURE DATES ALLOWED**

This system **only accepts real historical exchange rates**. Future dates, projections, or estimates are **strictly prohibited**.

## ✅ **What is Allowed:**

- **Real historical data** only (verified, no estimates or projections)
- **Current date** rates (same day, from live APIs)
- **Verified exchange rates** from reliable sources
- **No projections, estimates, or future predictions**

## ❌ **What is NOT Allowed:**

- Future dates (2025+)
- Economic projections
- Estimated rates for future periods
- Hypothetical scenarios

## 🛡️ **System Protections:**

### **Automatic Prevention:**
- Scripts automatically reject future dates
- End dates are capped at today's date
- Future date requests return errors

### **Data Validation:**
```python
# Example validation in scripts
today = date.today()
if end_date > today:
    print(f"❌ Cannot load future dates. End date {end_date} is after today {today}")
    end_date = today  # Auto-adjust
```

## 📊 **Current Data Coverage:**

| Year | Status | Data Type | Records |
|------|--------|-----------|---------|
| 2023 | ✅ Complete | Real Historical | 3,285 |
| 2024 | ✅ Complete | Real Historical | 3,294 |
| 2025 | ✅ Complete | Real Historical (95 quality) | 19,710 |
| 2026 | ✅ Partial | Real Historical (Jan 1-6) | 54 |

## 🔄 **Daily Update Process:**

### **Automated Updates (Recommended):**
```bash
# Updates only today's rates
python3 scripts/update_exchange_rates.py --project onyga-482313
```

### **Manual Historical Loading:**
```bash
# Only loads real historical data (no future dates)
python3 scripts/load_historical_rates.py --start-date 2023-01-01 --end-date 2024-12-31 --method csv --file your_historical_data.csv
```

## 📋 **Data Sources:**

### **Approved Sources:**
- ✅ Exchange rate APIs (exchangerate-api.com, fixer.io)
- ✅ Central banks (Bank of Israel, Federal Reserve)
- ✅ Financial data providers (Bloomberg, Reuters)
- ✅ Verified historical databases

### **Rejected Sources:**
- ❌ Future projections
- ❌ Economic forecasts
- ❌ Hypothetical scenarios
- ❌ AI-generated predictions

## 🔍 **Verification Queries:**

### **Check for Future Data:**
```sql
-- This should return no rows
SELECT COUNT(*) as future_dates
FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
WHERE exchange_date > CURRENT_DATE();
```

### **Data Quality Check:**
```sql
SELECT
  EXTRACT(YEAR FROM exchange_date) as year,
  COUNT(*) as total_rates,
  ROUND(AVG(data_quality_score), 1) as avg_quality,
  STRING_AGG(DISTINCT rate_source LIMIT 1) as source
FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
GROUP BY year
ORDER BY year;
```

## 🚨 **Policy Violations:**

If future dates are detected:
1. **Immediate removal** of future data
2. **Script updates** to prevent recurrence
3. **Audit trail** documentation

## 🎯 **Why This Policy Exists:**

1. **Accuracy**: Only real rates ensure accurate financial calculations
2. **Compliance**: Prevents misleading financial reporting
3. **Auditability**: Historical data must be verifiable
4. **Risk Management**: Future projections introduce uncertainty

## 📞 **Contact:**

For questions about currency data policy, contact the data governance team.
