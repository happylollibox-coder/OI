-- =============================================
-- OI Database Project - DIM_US_HOLIDAYS Table
-- =============================================
--
-- Purpose: US holidays and Amazon sales events for seasonal recommendation engine
-- Method: Manual INSERT (pre-populated with 2025-2027 events)
--
-- Phase model (5 phases per seasonal occasion):
--   PRE_PEAK:  pre_season_start → boost_start    (research clicks, prepare campaigns)
--   BOOST:     boost_start → peak_start           (push bids, orders starting)
--   PEAK:      peak_start → holiday_date - 2      (graduated ROAS, take profit)
--   POST_PEAK: holiday_date - 2 → holiday_date+14 (stop seasonal keywords)
--   OFF_SEASON: everything else                    (override INCREASE→REDUCE)
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DIM_US_HOLIDAYS` (
  holiday_date DATE NOT NULL,
  holiday_name STRING NOT NULL,
  category STRING NOT NULL,  -- gift_season, back_to_school, seasonal, prime_event
  ramp_up_days INT64 NOT NULL,  -- days before holiday to start ramping ads
  pre_season_start DATE NOT NULL,  -- computed: holiday_date - ramp_up_days
  boost_start DATE,  -- when orders start ramping (push bids)
  peak_start DATE,   -- when heavy orders begin (use ROAS logic)

  PRIMARY KEY (holiday_date, holiday_name) NOT ENFORCED
)
OPTIONS (
  description = "US holidays and Amazon sales events with 5-phase peak model for seasonal bid management."
);

-- =============================================
-- Pre-populate with 2025-2027 events
-- Phase dates derived from 2025 actual sales data:
--   Valentine's: pre=42d, boost=25d, peak=11d
--   Easter:      pre=63d, boost=48d, peak=20d
--   Christmas:   pre=90d, boost=85d, peak=52d
--   Back to School: pre=boost=28d, peak=25d
--   Others: pre=boost=peak (single PEAK phase)
-- =============================================

-- Clear and reload
DELETE FROM `onyga-482313.OI.DIM_US_HOLIDAYS` WHERE TRUE;

INSERT INTO `onyga-482313.OI.DIM_US_HOLIDAYS` (holiday_date, holiday_name, category, ramp_up_days, pre_season_start, boost_start, peak_start)
VALUES
  -- ===================== 2025 =====================
  -- Valentine's Day (Feb 14): pre=42d, boost=25d, peak=11d
  ('2025-02-14', 'Valentines Day', 'gift_season', 42, '2025-01-03', '2025-01-20', '2025-02-03'),
  -- Easter (Apr 20): pre=63d, boost=48d, peak=20d
  ('2025-04-20', 'Easter', 'gift_season', 63, '2025-02-16', '2025-03-03', '2025-03-31'),
  -- Mothers Day: single-phase (no detailed data)
  ('2025-05-11', 'Mothers Day', 'gift_season', 21, '2025-04-20', '2025-04-20', '2025-04-20'),
  -- Fathers Day: single-phase
  ('2025-06-15', 'Fathers Day', 'gift_season', 21, '2025-05-25', '2025-05-25', '2025-05-25'),
  -- Prime Day: single-phase
  ('2025-07-15', 'Prime Day', 'prime_event', 14, '2025-07-01', '2025-07-01', '2025-07-01'),
  -- Back to School (Aug 1): no PRE_PEAK (pre=boost=28d), peak=25d
  ('2025-08-01', 'Back to School', 'back_to_school', 28, '2025-07-04', '2025-07-04', '2025-07-07'),
  -- Halloween: single-phase
  ('2025-10-31', 'Halloween', 'seasonal', 21, '2025-10-10', '2025-10-10', '2025-10-10'),
  -- Black Friday: single-phase
  ('2025-11-28', 'Black Friday', 'gift_season', 42, '2025-10-17', '2025-10-17', '2025-10-17'),
  -- Cyber Monday: single-phase
  ('2025-12-01', 'Cyber Monday', 'gift_season', 42, '2025-10-20', '2025-10-20', '2025-10-20'),
  -- Christmas (Dec 25): pre=90d, boost=85d, peak=52d
  ('2025-12-25', 'Christmas', 'gift_season', 90, '2025-09-26', '2025-10-01', '2025-11-03'),
  -- New Year: single-phase
  ('2026-01-01', 'New Year', 'seasonal', 0, '2026-01-01', '2026-01-01', '2026-01-01'),

  -- ===================== 2026 =====================
  -- Valentine's Day (Feb 14)
  ('2026-02-14', 'Valentines Day', 'gift_season', 42, '2026-01-03', '2026-01-20', '2026-02-03'),
  -- Easter (Apr 5): pre=63d, boost=48d, peak=20d
  ('2026-04-05', 'Easter', 'gift_season', 63, '2026-02-01', '2026-02-16', '2026-03-16'),
  -- Mothers Day
  ('2026-05-10', 'Mothers Day', 'gift_season', 21, '2026-04-19', '2026-04-19', '2026-04-19'),
  -- Fathers Day
  ('2026-06-21', 'Fathers Day', 'gift_season', 21, '2026-05-31', '2026-05-31', '2026-05-31'),
  -- Prime Day
  ('2026-07-15', 'Prime Day', 'prime_event', 14, '2026-07-01', '2026-07-01', '2026-07-01'),
  -- Back to School (Aug 1)
  ('2026-08-01', 'Back to School', 'back_to_school', 28, '2026-07-04', '2026-07-04', '2026-07-07'),
  -- Halloween
  ('2026-10-31', 'Halloween', 'seasonal', 21, '2026-10-10', '2026-10-10', '2026-10-10'),
  -- Black Friday
  ('2026-11-27', 'Black Friday', 'gift_season', 42, '2026-10-16', '2026-10-16', '2026-10-16'),
  -- Cyber Monday
  ('2026-11-30', 'Cyber Monday', 'gift_season', 42, '2026-10-19', '2026-10-19', '2026-10-19'),
  -- Christmas (Dec 25): pre=90d, boost=85d, peak=52d
  ('2026-12-25', 'Christmas', 'gift_season', 90, '2026-09-26', '2026-10-01', '2026-11-03'),
  -- New Year
  ('2027-01-01', 'New Year', 'seasonal', 0, '2027-01-01', '2027-01-01', '2027-01-01'),

  -- ===================== 2027 =====================
  -- Valentine's Day (Feb 14)
  ('2027-02-14', 'Valentines Day', 'gift_season', 42, '2027-01-03', '2027-01-20', '2027-02-03'),
  -- Easter (Mar 28): pre=63d, boost=48d, peak=20d
  ('2027-03-28', 'Easter', 'gift_season', 63, '2027-01-24', '2027-02-08', '2027-03-08'),
  -- Mothers Day
  ('2027-05-09', 'Mothers Day', 'gift_season', 21, '2027-04-18', '2027-04-18', '2027-04-18'),
  -- Fathers Day
  ('2027-06-20', 'Fathers Day', 'gift_season', 21, '2027-05-30', '2027-05-30', '2027-05-30'),
  -- Prime Day
  ('2027-07-15', 'Prime Day', 'prime_event', 14, '2027-07-01', '2027-07-01', '2027-07-01'),
  -- Back to School (Aug 1)
  ('2027-08-01', 'Back to School', 'back_to_school', 28, '2027-07-04', '2027-07-04', '2027-07-07'),
  -- Halloween
  ('2027-10-31', 'Halloween', 'seasonal', 21, '2027-10-10', '2027-10-10', '2027-10-10'),
  -- Black Friday
  ('2027-11-26', 'Black Friday', 'gift_season', 42, '2027-10-15', '2027-10-15', '2027-10-15'),
  -- Cyber Monday
  ('2027-11-29', 'Cyber Monday', 'gift_season', 42, '2027-10-18', '2027-10-18', '2027-10-18'),
  -- Christmas (Dec 25)
  ('2027-12-25', 'Christmas', 'gift_season', 90, '2027-09-26', '2027-10-01', '2027-11-03');
