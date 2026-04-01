# Impact Analysis: Removing CFG_TRANSACTION_CATEGORIZATION_RULES JOIN

## Current Situation

**Problem**: Multiple categorization rules match the same transaction, creating duplicates:
- Example: "Card charge (GOOGLE*ADS5932893176)" matches 3 rules (11, 17, 99)
- Result: FACT has 2,619 rows instead of 1,915 (STG has 1,915 rows)
- 708 duplicate rows created by the JOIN

## If We Remove CFG_TRANSACTION_CATEGORIZATION_RULES JOIN

### What Will Happen:

1. **All transactions will get default values:**
   - `budget_subcategory` = 'Uncategorized Transactions'
   - `budget_category` = 'UNKNOWN'
   - `category_type` = 'UNKNOWN'
   - `subcategory_id` = 9901
   - `is_recurring` = FALSE
   - `budget_confidence` = 'LOW'
   - `forecast_multiplier` = 1.0

2. **Row count will be fixed:**
   - FACT will have 1,915 rows (same as STG)
   - No more duplicates

3. **We will lose categorization for currently categorized transactions:**
   - Currently: 1,194 transactions are "Uncategorized Transactions" (62%)
   - Currently: 717 transactions are categorized (38%)
   - After removal: All 1,915 transactions will be "Uncategorized Transactions" (100%)

### Current Categorization Breakdown (from FACT):

| Category | Subcategory | Transaction Count | Percentage |
|----------|-------------|-------------------|------------|
| UNKNOWN | Uncategorized Transactions | 1,194 | 62% |
| FINANCIAL FEES | Payment Processing Fees | 476 | 25% |
| ACCOUNT TRANSFERS | Inter-Account Transfers | 172 | 9% |
| REVENUE | Amazon Sales & Commissions | 164 | 8.6% |
| PERSONNEL & PAYROLL | Salary & Wages | 144 | 7.5% |
| PERSONNEL & PAYROLL | Contractor Payments | 136 | 7.1% |
| FINANCIAL FEES | Currency Conversion Fees | 104 | 5.4% |
| MARKETING & ADVERTISING | Google Ads | 84 | 4.4% |
| TAXES & REGULATORY | Income Taxes | 78 | 4.1% |
| INVESTMENT & INTEREST | Interest Income | 46 | 2.4% |
| BUSINESS TOOLS & SOFTWARE | SEO & Research Tools | 21 | 1.1% |

### Transactions That Will Lose Categorization:

- **476 transactions** currently categorized as "Payment Processing Fees"
- **172 transactions** currently categorized as "Inter-Account Transfers"
- **164 transactions** currently categorized as "Amazon Sales & Commissions"
- **144 transactions** currently categorized as "Salary & Wages"
- **136 transactions** currently categorized as "Contractor Payments"
- **104 transactions** currently categorized as "Currency Conversion Fees"
- **84 transactions** currently categorized as "Google Ads"
- **78 transactions** currently categorized as "Income Taxes"
- **46 transactions** currently categorized as "Interest Income"
- **21 transactions** currently categorized as "SEO & Research Tools"

**Total: 717 transactions (38%) will lose their categorization**

### Alternative Solution:

Instead of removing the rules completely, we could:
1. Fix the duplicate issue by using QUALIFY to keep only the highest priority rule per transaction
2. Or restructure the categorization rules to avoid overlapping patterns

## Recommendation:

**Don't remove the rules** - instead fix the duplicate issue by:
- Adding `QUALIFY ROW_NUMBER() OVER (PARTITION BY ... ORDER BY r.priority ASC) = 1` after the categorization JOIN
- This will keep only the highest priority matching rule per transaction
- We'll keep the categorization AND fix the duplicates
