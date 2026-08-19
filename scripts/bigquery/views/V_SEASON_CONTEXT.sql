-- =============================================
-- V_SEASON_CONTEXT — the context calendar of the season-context ledger.
-- Spec: architecture/SEASON_CONTEXT_LEDGER.md (Ori doctrine 2026-08-07: a verdict belongs to
-- (keyword x season-context occurrence), never to the keyword alone).
--
-- One row per date, 2024-09-05 (first ads data) .. anchor+180d (future included — engines need
-- today's context). Anchor = LEAST(MAX(date) FROM FACT_AMAZON_ADS, FN_ADS_ANCHOR_CAP()).
--
-- Peak set: LIVE DIM_US_HOLIDAYS rows, category IN ('gift_season','prime_event','back_to_school'),
-- window boost_start..COALESCE(cooldown_end, holiday_date). gift_season+prime_event over
-- boost..cooldown is exactly the engines' in_peak rule; back_to_school is a documented extension
-- (BTS is a first-class season here: boost Aug 1 / peak Aug 10 / anchor Sep 14, cooldown_end NULL).
-- category='seasonal' (Halloween, New Year) excluded, matching the engines' in_peak.
--
-- PRECEDENCE (documented): overlapping windows — earliest boost_start owns the date (tie-break
-- earlier holiday_date, then name). Consequences: BF+CM absorbed into XMAS (Q4 belongs to XMAS);
-- FDAY_2025 fully absorbed by GRAD_2025. A row's owned days are a contiguous suffix of its window.
-- OFF = contiguous gaps between owned peak days; each contiguous run is its own occurrence.
--
-- XMAS SPLIT (2026-08-08, calibration-driven): every XMAS context is TWO occurrences —
-- XMAS_EARLY_<yr> (Oct 1..Nov 14) and XMAS_PEAK_<yr> (Nov 15..Dec 28 cooldown end). Measured
-- rationale: PARK_CONTEXT auto-park lost -$109k (doctrine default; all 40 settings negative)
-- under the coarse single Q4 occurrence because it contains the real flip boundary (~Nov 15) —
-- October losses vetoed December funding, 25/26 flip winners re-parked. There is no combined
-- XMAS_<yr> label anymore.
--
-- Keys: context_label = code_year ('XMAS_EARLY_2025','XMAS_PEAK_2025','BTS_2026','PRIME_2026')
-- or 'OFF'; occurrence_key = context_label || '_' || yyyymmdd(occurrence_start).
--
-- 2024 BACKFILL (2026-08-08): DIM_US_HOLIDAYS 2024 rows inserted (BTS/Halloween/BF/CM/XMAS via
-- MIGRATE_DIM_US_HOLIDAYS_2024_BACKFILL.sql) -> BTS_2024 (truncated at 2024-09-05) and
-- XMAS_EARLY/PEAK_2024 now exist as contexts.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_SEASON_CONTEXT` AS
WITH
anchor AS (
  SELECT LEAST((SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
               `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS a
),
peaks AS (
  SELECT
    CONCAT(
      CASE holiday_name
        WHEN 'Christmas'      THEN 'XMAS'
        WHEN 'Black Friday'   THEN 'BF'
        WHEN 'Cyber Monday'   THEN 'CM'
        WHEN 'Back to School' THEN 'BTS'
        WHEN 'Prime Day'      THEN 'PRIME'
        WHEN 'Valentines Day' THEN 'VDAY'
        WHEN 'Mothers Day'    THEN 'MDAY'
        WHEN 'Fathers Day'    THEN 'FDAY'
        WHEN 'Graduation'     THEN 'GRAD'
        WHEN 'Easter'         THEN 'EASTER'
        ELSE UPPER(REPLACE(holiday_name, ' ', '_'))
      END,
      '_', CAST(EXTRACT(YEAR FROM holiday_date) AS STRING)
    ) AS context_label,
    holiday_name,
    category,
    holiday_date,
    boost_start                                AS win_start,
    COALESCE(cooldown_end, holiday_date)       AS win_end
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category IN ('gift_season', 'prime_event', 'back_to_school')
    AND boost_start IS NOT NULL
),
days AS (
  SELECT d AS date
  FROM anchor, UNNEST(GENERATE_DATE_ARRAY(DATE '2024-09-05', DATE_ADD(anchor.a, INTERVAL 180 DAY))) AS d
),
-- earliest boost_start wins each date (precedence above)
owned AS (
  SELECT
    dy.date,
    ARRAY_AGG(p ORDER BY p.win_start, p.holiday_date, p.holiday_name LIMIT 1)[SAFE_OFFSET(0)] AS p
  FROM days dy
  LEFT JOIN peaks p
    ON dy.date BETWEEN p.win_start AND p.win_end
  GROUP BY dy.date
),
labeled AS (
  SELECT
    date,
    COALESCE(p.context_label, 'OFF') AS context_label,
    p.holiday_name,
    p.category
  FROM owned
),
-- XMAS split: the single Q4 occurrence hides the ~Nov 15 flip boundary (PARK_CONTEXT -$109k).
-- Relabel XMAS_<yr> dates: before Nov 15 of that holiday year -> XMAS_EARLY_<yr>, else XMAS_PEAK_<yr>.
relabeled AS (
  SELECT
    date,
    CASE
      WHEN REGEXP_CONTAINS(context_label, r'^XMAS_\d{4}$') THEN
        IF(date < DATE(CAST(REGEXP_EXTRACT(context_label, r'_(\d{4})$') AS INT64), 11, 15),
           REPLACE(context_label, 'XMAS_', 'XMAS_EARLY_'),
           REPLACE(context_label, 'XMAS_', 'XMAS_PEAK_'))
      ELSE context_label
    END AS context_label,
    holiday_name,
    category
  FROM labeled
),
-- gaps-and-islands: contiguous run per label = occurrence
runs AS (
  SELECT
    *,
    DATE_SUB(date, INTERVAL ROW_NUMBER() OVER (PARTITION BY context_label ORDER BY date) DAY) AS island
  FROM relabeled
),
occ AS (
  SELECT
    date, context_label, holiday_name, category,
    MIN(date) OVER (PARTITION BY context_label, island) AS occurrence_start,
    MAX(date) OVER (PARTITION BY context_label, island) AS occurrence_end
  FROM runs
)
SELECT
  o.date,
  o.context_label,
  CONCAT(o.context_label, '_', FORMAT_DATE('%Y%m%d', o.occurrence_start)) AS occurrence_key,
  o.occurrence_start,
  o.occurrence_end,
  o.context_label != 'OFF'                        AS is_peak,
  o.holiday_name,
  o.category,
  o.date <= DATE_SUB(an.a, INTERVAL 7 DAY)        AS is_settled,          -- settle-curve rule: judge only <= anchor-7
  o.occurrence_end <= DATE_SUB(an.a, INTERVAL 7 DAY) AS occurrence_closed -- every day of the occurrence is settled
FROM occ o
CROSS JOIN anchor an;
