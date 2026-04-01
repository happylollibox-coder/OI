-- =============================================
-- DIM_TIME - Consolidated Ecommerce Time Dimension
-- =============================================
--
-- Streamlined design with consolidated categories
-- Includes accumulation logic for rollup reporting
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_TIME` (
  -- Primary Key: Date in YYYYMMDD format
  date_key INT64 NOT NULL,

  -- Core Date Fields
  full_date DATE NOT NULL,
  year INT64 NOT NULL,
  quarter INT64 NOT NULL,
  month INT64 NOT NULL,
  day INT64 NOT NULL,

  -- Standard Calendar Fields
  month_name STRING(20) NOT NULL,
  day_of_week_name STRING(20) NOT NULL,
  is_weekend BOOL NOT NULL,
  is_weekday BOOL NOT NULL,

  -- ==========================================
  -- CONSOLIDATED ECOMMERCE CATEGORIES
  -- ==========================================

  -- Holiday Category (Consolidated)
  is_holiday BOOL NOT NULL,
  holiday_description STRING(100),        -- "Black Friday", "Christmas Day", "New Year's Eve", etc.
  holiday_category STRING(50),            -- "Major Holiday", "Seasonal", "Cultural", "Observance"
  holiday_importance INT64,               -- 1-5 scale (5 = highest business impact)

  -- Peak Selling Period Category (Consolidated)
  is_peak_selling_period BOOL NOT NULL,
  peak_period_description STRING(100),    -- "December Peak", "Back-to-School", "Payday Weekend", etc.
  peak_period_category STRING(50),        -- "Holiday", "Seasonal", "Promotional", "Behavioral"
  peak_intensity_level STRING(20),         -- "Very High", "High", "Medium", "Low"

  -- Event Category (Consolidated)
  is_special_event BOOL NOT NULL,
  event_description STRING(100),          -- "Labor Day Sale", "Flash Sale", "Prime Day", etc.
  event_category STRING(50),               -- "Sale", "Marketing", "Operational", "External"
  event_type STRING(50),                  -- "Fixed Date", "Floating", "Promotional", "Cultural"

  -- Season Category (Consolidated)
  is_seasonal_period BOOL NOT NULL,
  season_description STRING(100),         -- "Christmas Season", "Summer Vacation", "Tax Season", etc.
  season_category STRING(50),             -- "Holiday", "Weather", "Academic", "Economic"

  -- ==========================================
  -- BUSINESS METRICS & EXPECTATIONS
  -- ==========================================

  -- Traffic & Conversion Expectations
  expected_traffic_level STRING(20),      -- "Very High", "High", "Normal", "Low"
  traffic_multiplier FLOAT64,             -- Expected traffic vs 30-day average
  expected_conversion_rate FLOAT64,       -- Expected conversion rate percentage
  price_sensitivity STRING(20),           -- "High", "Normal", "Low"

  -- Shipping & Delivery
  is_critical_shipping_period BOOL NOT NULL,
  shipping_description STRING(100),       -- "Last Minute Holiday", "Safe Christmas Delivery", etc.
  guaranteed_delivery_days INT64,         -- Days for guaranteed delivery

  -- Business Day Classification
  business_day_type STRING(30),           -- "Regular", "Peak", "Holiday Eve", "Post-Holiday"
  operational_intensity STRING(20),       -- "Standard", "Increased", "Maximum", "Reduced"

  -- ==========================================
  -- ACCUMULATION SUPPORT FIELDS
  -- ==========================================

  -- Week Level Accumulation
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  week_key STRING(10) NOT NULL,           -- YYYYMMDD format (week start date)
  year_week STRING(10) NOT NULL,          -- YYYY-UU format (year-week number)

  -- Month Level Accumulation
  month_start_date DATE NOT NULL,
  month_end_date DATE NOT NULL,
  month_key STRING(7) NOT NULL,           -- YYYY-MM format

  -- Quarter Level Accumulation
  quarter_start_date DATE NOT NULL,
  quarter_end_date DATE NOT NULL,
  quarter_key STRING(7) NOT NULL,         -- YYYY-QN format

  -- Year Level Accumulation
  year_start_date DATE NOT NULL,
  year_end_date DATE NOT NULL,
  year_key STRING(4) NOT NULL,            -- YYYY format

  -- Holiday Season Accumulation
  holiday_season_key STRING(20),          -- "Holiday", "Christmas", etc.
  holiday_season_start_date DATE,
  holiday_season_end_date DATE,

  -- Peak Period Accumulation
  peak_period_key STRING(20),             -- "Black-Friday", "December-Peak", etc.
  peak_period_start_date DATE,
  peak_period_end_date DATE,

  -- Rolling Periods for Accumulation
  rolling_7_day_key STRING(15),           -- YYYY-MM-DD (end date)
  rolling_30_day_key STRING(15),          -- YYYY-MM-DD (end date)
  rolling_90_day_key STRING(15),          -- YYYY-MM-DD (end date)

  -- ==========================================
  -- ADDITIONAL ANALYTICS FIELDS
  -- ==========================================

  -- Comparative Analysis
  days_from_today INT64,
  is_current_week BOOL NOT NULL,
  is_current_month BOOL NOT NULL,
  is_current_quarter BOOL NOT NULL,
  is_year_to_date BOOL NOT NULL,

  -- Business Rules
  requires_extra_staffing BOOL NOT NULL,
  requires_inventory_boost BOOL NOT NULL,
  high_risk_return_period BOOL NOT NULL,

  -- Metadata
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  business_rules_version STRING(20) NOT NULL

) PARTITION BY DATE_TRUNC(full_date, YEAR)
CLUSTER BY year, month, peak_period_category, holiday_category;
