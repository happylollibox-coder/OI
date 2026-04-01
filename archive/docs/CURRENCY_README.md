# Currency Exchange Rates - Implementation Guide

## Overview

This implementation provides a complete currency exchange rate system for ILS (Israeli Shekel), USD (US Dollar), and HKD (Hong Kong Dollar) since 2023. The system supports daily updates and historical conversions for accurate financial reporting.

## Architecture

### Components

1. **DIM_CURRENCY_RATES** - Dimension table storing exchange rates
2. **SP_UPDATE_CURRENCY_RATES** - Stored procedure for fetching/updating rates
3. **V_SRC_CURRENCY_CONVERSION** - Interface view for easy conversions

### Data Flow

```
External API ──► Cloud Function ──► BigQuery SP ──► DIM_CURRENCY_RATES
                                       │
                                       ▼
                             V_SRC_CURRENCY_CONVERSION ◄── Applications
```

## Quick Start

### 1. Deploy Infrastructure

```bash
cd deployment
chmod +x deploy_currency.sh
./deploy_currency.sh
```

### 2. Load Historical Data

```sql
-- Load rates from 2023 to present
CALL `onyga-482313.OI.SP_UPDATE_CURRENCY_RATES`(
  DATE('2023-01-01'),
  CURRENT_DATE(),
  TRUE  -- Historical load
);
```

### 3. Schedule Daily Updates

Choose one of the following approaches:

#### Option A: BigQuery Scheduled Query
```sql
-- Schedule this query to run daily at 6 AM EST
CALL `onyga-482313.OI.SP_UPDATE_CURRENCY_RATES`(
  CURRENT_DATE(),
  CURRENT_DATE(),
  FALSE
);
```

#### Option B: Cloud Function + Cloud Scheduler
1. Create a Cloud Function that calls the stored procedure
2. Schedule it for weekdays at 6 AM EST

## Usage Examples

### Convert Transaction Amounts to USD

```sql
SELECT
  transaction_date,
  amount,
  currency,
  CASE
    WHEN currency = 'USD' THEN amount
    WHEN currency = 'ILS' THEN amount * c.inverse_rate
    WHEN currency = 'HKD' THEN amount * c.inverse_rate
  END as amount_in_usd
FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` t
LEFT JOIN `onyga-482313.OI.V_SRC_CURRENCY_CONVERSION` c
  ON c.base_currency = t.currency
  AND c.target_currency = 'USD'
  AND c.exchange_date <= t.transaction_date
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY t.transaction_id
  ORDER BY c.exchange_date DESC
) = 1;
```

### Get Current Exchange Rates

```sql
SELECT
  base_currency,
  target_currency,
  exchange_rate,
  rate_date,
  rate_quality_category
FROM `onyga-482313.OI.V_SRC_CURRENCY_CONVERSION`
WHERE rate_date = (
  SELECT MAX(rate_date)
  FROM `onyga-482313.OI.V_SRC_CURRENCY_CONVERSION`
)
ORDER BY base_currency, target_currency;
```

### Historical Currency Analysis

```sql
-- Show how USD/ILS rate has changed over time
SELECT
  exchange_date,
  exchange_rate as usd_to_ils,
  ROUND(100 * (exchange_rate - LAG(exchange_rate) OVER (ORDER BY exchange_date)) /
               LAG(exchange_rate) OVER (ORDER BY exchange_date), 2) as pct_change
FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
WHERE base_currency = 'USD'
  AND target_currency = 'ILS'
  AND data_quality_score > 0
ORDER BY exchange_date DESC;
```

## API Integration

### Current Implementation

The stored procedure includes a placeholder for API integration. For production, implement one of these approaches:

#### 1. Exchange Rate API (Recommended)

**Service**: [ExchangeRate-API](https://exchangerate-api.com/) (Free tier: 1,500 requests/month)

**Endpoint**: `https://api.exchangerate-api.com/v4/latest/USD`

**Response**:
```json
{
  "result": "success",
  "provider": "https://www.exchangerate-api.com",
  "documentation": "https://www.exchangerate-api.com/docs/free",
  "terms_of_use": "https://www.exchangerate-api.com/terms",
  "time_last_update_unix": 1704067201,
  "time_last_update_utc": "Sun, 01 Jan 2024 00:00:01 +0000",
  "time_next_update_unix": 1704153601,
  "time_next_update_utc": "Mon, 02 Jan 2024 00:00:01 +0000",
  "time_eol_unix": 0,
  "base_code": "USD",
  "rates": {
    "ILS": 3.85,
    "HKD": 7.82,
    "USD": 1.0
  }
}
```

#### 2. Alternative APIs

- **Fixer.io**: More reliable, paid plans available
- **CurrencyAPI**: Real-time rates, paid service
- **Bank of Israel API**: Official ILS rates (free)

### Cloud Function Implementation

```javascript
// Example Cloud Function (Node.js)
const functions = require('@google-cloud/functions-framework');
const {BigQuery} = require('@google-cloud/bigquery');

functions.http('updateCurrencyRates', async (req, res) => {
  try {
    // Fetch rates from API
    const response = await fetch('https://api.exchangerate-api.com/v4/latest/USD');
    const data = await response.json();

    // Call BigQuery stored procedure
    const bigquery = new BigQuery();
    const query = `
      CALL \`onyga-482313.OI.SP_UPDATE_CURRENCY_RATES\`(
        CURRENT_DATE(), CURRENT_DATE(), FALSE
      )
    `;

    await bigquery.query(query);
    res.status(200).send('Currency rates updated successfully');
  } catch (error) {
    console.error('Error updating currency rates:', error);
    res.status(500).send('Error updating currency rates');
  }
});
```

## Data Quality & Monitoring

### Quality Checks

```sql
-- Check for missing rates
SELECT
  exchange_date,
  COUNT(*) as pairs_count,
  CASE WHEN COUNT(*) < 6 THEN 'INCOMPLETE' ELSE 'COMPLETE' END as status
FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
WHERE exchange_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY exchange_date
ORDER BY exchange_date DESC;

-- Monitor rate quality
SELECT
  rate_quality_category,
  COUNT(*) as rate_count,
  AVG(data_quality_score) as avg_quality_score
FROM `onyga-482313.OI.V_SRC_CURRENCY_CONVERSION`
WHERE rate_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY rate_quality_category;
```

### Alerts Setup

Set up monitoring for:
- Missing rates for business days
- API failures (quality_score = 0)
- Unusual rate changes (>5% day-over-day)

## Schema Details

### DIM_CURRENCY_RATES

| Field | Type | Description |
|-------|------|-------------|
| exchange_date | DATE | Effective date for the rate |
| base_currency | STRING | Source currency (USD, ILS, HKD) |
| target_currency | STRING | Target currency (USD, ILS, HKD) |
| exchange_rate | FLOAT64 | Rate: 1 base = X target |
| inverse_rate | FLOAT64 | Rate: 1 target = X base |
| rate_source | STRING | API source name |
| rate_timestamp | TIMESTAMP | When rate was fetched |
| is_business_day | BOOLEAN | Whether this is a business day |
| data_quality_score | INT64 | Quality indicator (0-100) |

### V_SRC_CURRENCY_CONVERSION

Provides a convenient interface with:
- Current rates for each pair
- Historical rates for time-travel queries
- Quality indicators
- Ready-to-use conversion logic

## Troubleshooting

### Common Issues

1. **Missing rates for weekends**
   - Solution: Rates are forward-filled from Friday

2. **API rate limits exceeded**
   - Solution: Implement caching or use paid API tier

3. **Historical data gaps**
   - Solution: Run historical load procedure with `is_historical_load=TRUE`

4. **Quality score = 0**
   - Indicates API failure or manual error record
   - Check override_reason field for details

### Manual Rate Override

```sql
-- Override rate manually (e.g., for API outage)
INSERT INTO `onyga-482313.OI.DIM_CURRENCY_RATES`
  (exchange_date, base_currency, target_currency, exchange_rate, inverse_rate,
   rate_source, rate_timestamp, is_business_day, data_quality_score,
   is_manual_override, override_reason)
VALUES
  (CURRENT_DATE(), 'USD', 'ILS', 3.85, 0.2597,
   'MANUAL_OVERRIDE', CURRENT_TIMESTAMP(), TRUE, 100,
   TRUE, 'API temporarily unavailable');
```

## Performance Considerations

- Table is partitioned by `exchange_date` for efficient queries
- Clustered by `base_currency, target_currency` for fast lookups
- Use appropriate date ranges in WHERE clauses
- Consider materialized views for frequently accessed conversions

## Future Enhancements

- Support for additional currencies
- Intraday rate updates for high-frequency trading
- Rate volatility analysis and alerts
- Integration with central bank APIs
- Machine learning-based rate prediction
