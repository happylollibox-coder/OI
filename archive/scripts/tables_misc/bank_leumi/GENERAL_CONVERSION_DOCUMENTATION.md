# GENERAL_CONVERSION Table - List of Values Documentation

## Overview
The `GENERAL_CONVERSION` table stores conversion mappings for various transaction attributes. Each conversion type uses a unique combination of `list_of_values`, `SOURCE`, and `key` to map source values to target values.

---

## List of Values Options

### 1. Account-Nick-Name
**Purpose:** Maps account identifiers to friendly account names

**SOURCE Field:**
- **Source Table:** `STG_UNIFIED_TRANSACTION_SOURCES`
- **Field Used:** `source_system`
- **Possible Values:** `'BANK_LEUMI_ILS'`, `'BANK_LEUMI_FOREIGN'`, `'PAYONEER_ADVA_TAL'`, `'PAYONEER_HAPPY_LOLLI'`

**KEY Field:**
- **Source Table:** `STG_UNIFIED_TRANSACTION_SOURCES`
- **Field Used:** `account_name`
- **Example Values:** `'680-49923/21'`, `'680-227800/65'`, `'adva.tal'`, `'happy_lolli'`

**Target Field in FACT:**
- `account_nick_name STRING`
- **Example Target Values:** `'Main Business Account'`, `'Foreign Currency Account'`, `'Adva Tal Payoneer'`

**Lookup Logic:**
```sql
JOIN ON: list_of_values = 'Account-Nick-Name'
  AND SOURCE = source_system
  AND key = account_name
```

**Example:**
- SOURCE: `'BANK_LEUMI_ILS'`
- key: `'680-49923/21'`
- target: `'Main Business Account'`

---

### 2. subcategory_id
**Purpose:** Maps transaction descriptions to budget subcategory IDs for budget planning

**SOURCE Field:**
- **Source Table:** `STG_UNIFIED_TRANSACTION_SOURCES`
- **Field Used:** `source_system`
- **Possible Values:** `'BANK_LEUMI_ILS'`, `'BANK_LEUMI_FOREIGN'`, `'PAYONEER_ADVA_TAL'`, `'PAYONEER_HAPPY_LOLLI'`

**KEY Field:**
- **Source Table:** `STG_UNIFIED_TRANSACTION_SOURCES`
- **Field Used:** `transaction_description`
- **Example Values:** `'Card charge (GOOGLE*ADS5932893176)'`, `'העברה בנקאית'`, `'Amazon Sales'`

**Target Field in FACT:**
- `subcategory_id INT64`
- **Example Target Values:** `802` (Payment Processing Fees), `501` (Marketing & Advertising), `9901` (Uncategorized)

**Lookup Logic:**
```sql
JOIN ON: list_of_values = 'subcategory_id'
  AND SOURCE = source_system
  AND key = transaction_description
  AND target != 'Unknown'  -- Only use if manually overridden
```

**Example:**
- SOURCE: `'PAYONEER_HAPPY_LOLLI'`
- key: `'Card charge (GOOGLE*ADS5932893176)'`
- target: `'802'` (Payment Processing Fees subcategory_id)

---

### 3. payment_direction
**Purpose:** Maps transaction amount and description to payment direction (INCOMING/OUTGOING/INTERNAL_TRANSFER)

**SOURCE Field:**
- **Source Table:** `STG_UNIFIED_TRANSACTION_SOURCES`
- **Field Used:** `source_system`
- **Possible Values:** `'BANK_LEUMI_ILS'`, `'BANK_LEUMI_FOREIGN'`, `'PAYONEER_ADVA_TAL'`, `'PAYONEER_HAPPY_LOLLI'`

**KEY Field:**
- **Source Table:** `STG_UNIFIED_TRANSACTION_SOURCES`
- **Field Used:** `CONCAT(amount_sign, '|', transaction_description)`
- **Amount Sign Calculation:** 
  - `'POSITIVE'` if `amount > 0`
  - `'NEGATIVE'` if `amount < 0`
  - `'ZERO'` if `amount = 0`
- **Example Values:** 
  - `'POSITIVE|Card charge (GOOGLE*ADS5932893176)'`
  - `'NEGATIVE|העברה בנקאית'`
  - `'POSITIVE|Amazon Sales'`

**Target Field in FACT:**
- `payment_direction STRING`
- **Example Target Values:** `'INCOMING'`, `'OUTGOING'`, `'INTERNAL_TRANSFER'`, `'UNKNOWN'`

**Lookup Logic:**
```sql
JOIN ON: list_of_values = 'payment_direction'
  AND SOURCE = source_system
  AND key = CONCAT(
    CASE WHEN amount > 0 THEN 'POSITIVE' 
         WHEN amount < 0 THEN 'NEGATIVE' 
         ELSE 'ZERO' END, 
    '|', 
    transaction_description
  )
```

**Example:**
- SOURCE: `'BANK_LEUMI_ILS'`
- key: `'NEGATIVE|העברה בנקאית'`
- target: `'OUTGOING'`

---

### 4. transaction_category
**Purpose:** Maps transaction descriptions to transaction category types (CARD_PAYMENT, BANK_TRANSFER, etc.)

**SOURCE Field:**
- **Source Table:** `STG_UNIFIED_TRANSACTION_SOURCES`
- **Field Used:** `source_system`
- **Possible Values:** `'BANK_LEUMI_ILS'`, `'BANK_LEUMI_FOREIGN'`, `'PAYONEER_ADVA_TAL'`, `'PAYONEER_HAPPY_LOLLI'`

**KEY Field:**
- **Source Table:** `STG_UNIFIED_TRANSACTION_SOURCES`
- **Field Used:** `transaction_description`
- **Example Values:** `'Card charge (GOOGLE*ADS5932893176)'`, `'העברה בנקאית'`, `'Amazon Sales'`

**Target Field in FACT:**
- `transaction_category STRING`
- **Example Target Values:** `'CARD_PAYMENT'`, `'BANK_TRANSFER'`, `'BANK_FEE'`, `'PAYMENT'`, `'OTHER'`, `'UNKNOWN'`

**Lookup Logic:**
```sql
JOIN ON: list_of_values = 'transaction_category'
  AND SOURCE = source_system
  AND key = transaction_description
```

**Example:**
- SOURCE: `'PAYONEER_HAPPY_LOLLI'`
- key: `'Card charge (GOOGLE*ADS5932893176)'`
- target: `'CARD_PAYMENT'`

---

### 5. payment_source
**Purpose:** Maps transaction descriptions to business entity/vendor names (AMAZON, GOOGLE_ADS, etc.)

**SOURCE Field:**
- **Source Table:** `STG_UNIFIED_TRANSACTION_SOURCES`
- **Field Used:** `source_system`
- **Possible Values:** `'BANK_LEUMI_ILS'`, `'BANK_LEUMI_FOREIGN'`, `'PAYONEER_ADVA_TAL'`, `'PAYONEER_HAPPY_LOLLI'`

**KEY Field:**
- **Source Table:** `STG_UNIFIED_TRANSACTION_SOURCES`
- **Field Used:** `transaction_description`
- **Example Values:** `'Card charge (GOOGLE*ADS5932893176)'`, `'Amazon Sales'`, `'HELIUM10 Subscription'`

**Target Field in FACT:**
- `payment_source STRING`
- **Example Target Values:** `'AMAZON'`, `'GOOGLE_ADS'`, `'HELIUM10'`, `'SYLVIA'`, `'ADVA_TAL'`, `'OTHER'`, `'UNKNOWN'`

**Lookup Logic:**
```sql
JOIN ON: list_of_values = 'payment_source'
  AND SOURCE = source_system
  AND key = transaction_description
```

**Example:**
- SOURCE: `'PAYONEER_HAPPY_LOLLI'`
- key: `'Card charge (GOOGLE*ADS5932893176)'`
- target: `'GOOGLE_ADS'`

---

### 6. ad_URL_ASIN
**Purpose:** Maps AD_Advertised_ID from Sponsored Brands ads to ASIN identifiers

**SOURCE Field:**
- **Source Table:** `V_SRC_AmazonAds_sb_ad_report`
- **Field Used:** Fixed value `'AMAZON_ADS_SB'`
- **Possible Values:** `'AMAZON_ADS_SB'`

**KEY Field:**
- **Source Table:** `V_SRC_AmazonAds_sb_ad_report`
- **Field Used:** `AD_Advertised_ID` (conditional logic)
  - If `custom_image_url` is not empty: uses `custom_image_url`
  - If `custom_image_url` is empty: uses `campaign_name|ad_group_id`
- **Example Values:** 
  - `'https://m.media-amazon.com/images/S/al-na-9d5791cf-3faf/1503873b-10a6-4421-a2f1-837fbabb310d.png'` (when custom_image_url exists)
  - `'FRESH- VIDEO / BROAD (Jenna)|291025799038676'` (when custom_image_url is empty)

**Target Field:**
- `target STRING` - ASIN identifier
- **Example Target Values:** `'B0F9X95K5H'`, `'B0C1VLXYBP'`, etc.

**Lookup Logic:**
```sql
JOIN ON: list_of_values = 'ad_URL_ASIN'
  AND SOURCE = 'AMAZON_ADS_SB'
  AND key = AD_Advertised_ID
```

**Example:**
- SOURCE: `'AMAZON_ADS_SB'`
- key: `'https://m.media-amazon.com/images/S/al-na-9d5791cf-3faf/1503873b-10a6-4421-a2f1-837fbabb310d.png'` (or `'Campaign Name|AdGroup ID'` if no image URL)
- target: `'B0F9X95K5H'` (ASIN to be populated manually or via extraction)

**Population:**
- Populated via `SP_MERGE_GENERAL_CONVERSION_AD_URL_ASIN` stored procedure
- Merges distinct `AD_Advertised_ID` values from `V_SRC_AmazonAds_sb_ad_report`
- `AD_Advertised_ID` uses `custom_image_url` if available, otherwise falls back to `campaign_name|ad_group_id`
- Initial target value is `'Unknown'` and should be populated with ASIN manually or via extraction logic

---

## Summary Table

| list_of_values | SOURCE Field | KEY Field | Target Type | FACT Field | Purpose |
|----------------|--------------|-----------|-------------|------------|---------|
| **Account-Nick-Name** | `source_system` | `account_name` | STRING | `account_nick_name` | Friendly account names |
| **subcategory_id** | `source_system` | `transaction_description` | INT64 | `subcategory_id` | Budget subcategory ID |
| **payment_direction** | `source_system` | `amount_sign\|transaction_description` | STRING | `payment_direction` | Payment direction (IN/OUT) |
| **transaction_category** | `source_system` | `transaction_description` | STRING | `transaction_category` | Transaction method type |
| **payment_source** | `source_system` | `transaction_description` | STRING | `payment_source` | Business entity/vendor |
| **ad_URL_ASIN** | `'AMAZON_ADS_SB'` | `AD_Advertised_ID` (custom_image_url or campaign_name\|ad_group_id) | STRING | N/A | Maps SB ad identifiers to ASINs |

---

## Key Patterns

### Pattern 1: Simple Description Mapping
- **Used by:** `subcategory_id`, `transaction_category`, `payment_source`
- **KEY:** `transaction_description` (direct mapping)
- **Same key, different targets:** These three use the same key but map to different analytical dimensions

### Pattern 2: Account Mapping
- **Used by:** `Account-Nick-Name`
- **KEY:** `account_name` (direct mapping)
- **Purpose:** User-friendly account names

### Pattern 3: Amount-Aware Mapping
- **Used by:** `payment_direction`
- **KEY:** `CONCAT(amount_sign, '|', transaction_description)`
- **Purpose:** Considers both amount sign and description for direction determination

---

## Notes

1. **SOURCE is always:** `source_system` from `STG_UNIFIED_TRANSACTION_SOURCES`
2. **Unique Constraint:** Combination of `(list_of_values, SOURCE, key)` must be unique
3. **Default Target:** All conversions start with `target = 'Unknown'` and can be manually updated
4. **Example Field:** Stores one example amount value for reference during manual categorization
