-- =============================================
-- MIGRATE_DIM_US_HOLIDAYS_2024_BACKFILL — 2026-08-08
-- Spec: architecture/SEASON_CONTEXT_LEDGER.md (2024 backfill section).
--
-- The LIVE DIM_US_HOLIDAYS had ZERO 2024 rows -> no XMAS_2024/BF_2024/CM_2024/BTS_2024 contexts,
-- Christmas cross-occurrence memory blind for Q4. Insert the five 2024 rows whose
-- boost_start..cooldown window intersects the ads-data era (>= 2024-09-05), mirroring the 2025
-- rows' structure with the holidays' REAL 2024 calendar dates; categories identical.
--
-- TARGETED INSERT ONLY (Prime-Day-BLITZ precedent: live table differs from repo DDL — never
-- CREATE OR REPLACE this table). Idempotent: anti-join guard on (holiday_date, holiday_name).
--
-- Derivations, verified against the 2025/2026/2027 rows:
--   Christmas   : fixed month-days (pre 09-26, boost 10-01, peak 11-03, cd 12-24..12-28), ramp 90
--   Black Friday: pre=boost=peak = holiday-42d; cd_start = holiday-1d; cd_end = holiday+3d
--   Cyber Monday: pre=boost=peak = holiday-42d; cd_start = holiday-1d; cd_end = holiday+3d
--   Back to School: fixed (holiday 09-14, pre 07-04, boost 08-01, peak 08-10, cooldown NULL)
--   Halloween   : fixed (pre=boost=peak 10-10, cooldown NULL), category 'seasonal' (stays
--                 excluded from season contexts; inserted for table completeness only)
-- Real 2024 dates: BF = 2024-11-29 (day after 4th-Thursday Thanksgiving 11-28), CM = 2024-12-02.
-- =============================================
INSERT INTO `onyga-482313.OI.DIM_US_HOLIDAYS`
  (holiday_date, holiday_name, category, ramp_up_days, pre_season_start,
   boost_start, peak_start, cooldown_start, cooldown_end)
SELECT n.*
FROM UNNEST([
  STRUCT(DATE '2024-09-14' AS holiday_date, 'Back to School' AS holiday_name, 'back_to_school' AS category,
         28 AS ramp_up_days, DATE '2024-07-04' AS pre_season_start, DATE '2024-08-01' AS boost_start,
         DATE '2024-08-10' AS peak_start, CAST(NULL AS DATE) AS cooldown_start, CAST(NULL AS DATE) AS cooldown_end),
  STRUCT(DATE '2024-10-31', 'Halloween', 'seasonal',
         21, DATE '2024-10-10', DATE '2024-10-10',
         DATE '2024-10-10', NULL, NULL),
  STRUCT(DATE '2024-11-29', 'Black Friday', 'gift_season',
         42, DATE '2024-10-18', DATE '2024-10-18',
         DATE '2024-10-18', DATE '2024-11-28', DATE '2024-12-02'),
  STRUCT(DATE '2024-12-02', 'Cyber Monday', 'gift_season',
         42, DATE '2024-10-21', DATE '2024-10-21',
         DATE '2024-10-21', DATE '2024-12-01', DATE '2024-12-05'),
  STRUCT(DATE '2024-12-25', 'Christmas', 'gift_season',
         90, DATE '2024-09-26', DATE '2024-10-01',
         DATE '2024-11-03', DATE '2024-12-24', DATE '2024-12-28')
]) AS n
WHERE NOT EXISTS (
  SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` e
  WHERE e.holiday_date = n.holiday_date AND e.holiday_name = n.holiday_name
);
