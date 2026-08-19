-- =============================================
-- V_PEAK_WINDOW_RULE — ONE ROW. The engines' season gate and judged-window length, resolved
-- for today, with the evidence that justifies the window carried alongside it.
--
-- v27.50 (Ori 2026-08-12). Implements ORI'S RULE:
--   "The algorithm should switch from 7 days to 3 days [in peak] UNLESS it has examined last
--    year's same peak and proved that 7 days is better than 3."
--
--   BURDEN OF PROOF IS ON THE SLOWER WINDOW.
--     off peak            -> 7 days   (unchanged; not overridable — the override table is a
--                                      PEAK rule only)
--     in peak, no row     -> 3 days   (the default)
--     in peak, row exists -> DE_PEAK_WINDOW_OVERRIDE.w_days for that occurrence type
--   No evidence / thin evidence / ambiguous evidence / conflicting evidence = 3 days.
--   The evidence lives in DE_PEAK_WINDOW_OVERRIDE, never in this SQL.
--
-- CONSUMERS:
--   V_KEYWORD_LIFT — `cap` CTE reads w_days from here. Its `season` CTE reads in_peak from
--   V_SEASON_PEAK_GATE (see PERFORMANCE below), which is also this view's own source, so both
--   engines' notion of "in peak" comes from one predicate.
--
-- NOT a consumer (deliberately, this pass): V_OOB_BUDGET_PHASE carries its own separate
--   IF(in_peak, r3, r7) budget-cut construct and its own `today AND prev-2d` 3-day cut. It is
--   the same question about the same data and Ori's rule logically covers it, but it was NOT
--   measured and is NOT wired here. See architecture/PEAK_WINDOW_RULE.md §6 for the
--   recommendation. V_KEYWORD_GUARD and V_OOB_KEYWORD still run the PRE-v27.49 season gate —
--   also out of scope here, also recorded in §6.
--
-- OCCURRENCE TYPE RESOLUTION — deliberately mirrors V_SEASON_CONTEXT so the ledger and the
-- engine agree about which occurrence today belongs to:
--   * candidate set = DIM_US_HOLIDAYS rows in the ENGINE's in_peak categories
--     ('gift_season','prime_event','back_to_school','seasonal'), window
--     boost_start .. COALESCE(cooldown_end, holiday_date + 3 days)   <- the v27.49 engine window
--   * PRECEDENCE: earliest boost_start owns the date (tie-break earlier holiday_date, then name).
--     Consequence: Black Friday, Cyber Monday and Halloween are all absorbed into Christmas;
--     Father's Day is absorbed into Graduation.
--   * XMAS SPLIT: Christmas dates before Nov 15 of the holiday year -> XMAS_EARLY, else
--     XMAS_PEAK (same boundary V_SEASON_CONTEXT uses; the ~Nov 15 flip is real).
--   The candidate rows come from V_SEASON_PEAK_GATE, the SAME view V_KEYWORD_LIFT's `season`
--   CTE counts for in_peak, so the gate and the occurrence resolver cannot disagree — the
--   predicate is written once, in that view.
--
-- TWO KNOWN CALENDAR DIVERGENCES, recorded not fixed (SOP §6.5):
--   (a) this view and the engines end a season at COALESCE(cooldown_end, holiday_date + 3);
--       V_SEASON_CONTEXT ends it at COALESCE(cooldown_end, holiday_date). For a NULL-cooldown
--       season (Back to School) that is a 3-day tail where the engines are in peak and the
--       ledger says OFF.
--   (b) V_SEASON_CONTEXT excludes category='seasonal'; the engines (v27.49) include it. Harmless
--       in day terms because Halloween nests inside Christmas, but they are different objects.
--
-- GUARANTEE: exactly ONE row, always. `own` is LIMIT 1 (0 or 1 row) and `base` projects it
-- through uncorrelated scalar subqueries with no table in its FROM clause, so an empty gate
-- still yields one all-NULL row (in_peak FALSE, w_days 7). This matters because V_KEYWORD_LIFT
-- CROSS JOINs this view — an empty result would empty the engine.
--
-- PERFORMANCE — KEEP THIS VIEW SMALL, AND DO NOT POINT V_KEYWORD_LIFT's `season` CTE AT IT.
-- Two measured failures got us to this shape:
--   1. First cut resolved the override with a LEFT JOIN + GROUP BY/ARRAY_AGG. The join shape
--      stopped BigQuery folding in_peak/w_days to constants inside the FACT_AMAZON_ADS window
--      scans: V_KEYWORD_LIFT went from 25.6M slot-ms / 45s to 753M slot-ms / 717s. Uncorrelated
--      scalar subqueries fold; joins do not. DO NOT REINTRODUCE A JOIN HERE.
--   2. Second cut was join-free but still expanded ~30 times, once per `(SELECT ... FROM season)`
--      site in the engine, and BigQuery refused to plan it at all ("Not enough resources for
--      query planning - too many subqueries or query is too complex"). Fixed by extracting the
--      bare predicate into V_SEASON_PEAK_GATE: the engine's ~30 in_peak sites read that trivial
--      view, and only the 3 `cap` sites read this one.
-- After both fixes the engine runs 24s / 11.3M slot-ms and 26s / 9.7M slot-ms on two consecutive
-- pulls, against a 45s / 25.6M slot-ms pre-change baseline.
--
-- SAFETY: w_days is clamped to [1, 28]. A typo in the data table cannot make the engine judge on
-- a zero-day or year-long window.
--
-- DETERMINISM: the override row is picked by a total ORDER BY (measured_on, updated_at, then
-- every field that is read) with LIMIT 1, and the whole record is pulled as ONE struct — never
-- two ANY_VALUE()s out of one GROUP BY, which coin-flips field pairings.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PEAK_WINDOW_RULE` AS
WITH
own AS (
  SELECT
    g.holiday_name,
    g.holiday_date,
    g.boost_start,
    g.win_end,
    CASE
      WHEN g.holiday_name = 'Christmas' THEN
        IF(CURRENT_DATE('America/New_York') < DATE(EXTRACT(YEAR FROM g.holiday_date), 11, 15),
           'XMAS_EARLY', 'XMAS_PEAK')
      WHEN g.holiday_name = 'Black Friday'   THEN 'BF'
      WHEN g.holiday_name = 'Cyber Monday'   THEN 'CM'
      WHEN g.holiday_name = 'Back to School' THEN 'BTS'
      WHEN g.holiday_name = 'Prime Day'      THEN 'PRIME'
      WHEN g.holiday_name = 'Valentines Day' THEN 'VDAY'
      WHEN g.holiday_name = 'Mothers Day'    THEN 'MDAY'
      WHEN g.holiday_name = 'Fathers Day'    THEN 'FDAY'
      WHEN g.holiday_name = 'Graduation'     THEN 'GRAD'
      WHEN g.holiday_name = 'Easter'         THEN 'EASTER'
      ELSE UPPER(REPLACE(g.holiday_name, ' ', '_'))
    END AS occurrence_type
  FROM `onyga-482313.OI.V_SEASON_PEAK_GATE` g
  ORDER BY g.boost_start, g.holiday_date, g.holiday_name
  LIMIT 1
),

base AS (
  SELECT
    (SELECT AS STRUCT * FROM own) AS h,
    (SELECT AS STRUCT o.*
     FROM `onyga-482313.OI.DE_PEAK_WINDOW_OVERRIDE` o
     WHERE o.is_active
       AND o.occurrence_type = (SELECT occurrence_type FROM own)
     ORDER BY o.measured_on DESC, o.updated_at DESC, o.w_days ASC,
              COALESCE(o.evidence_verdict, '') ASC,
              COALESCE(o.evidence_occurrences, '') ASC,
              COALESCE(o.evidence_metric, '') ASC,
              COALESCE(o.comment, '') ASC
     LIMIT 1) AS r
)

SELECT
  b.h.holiday_name IS NOT NULL AS in_peak,
  b.h.occurrence_type          AS occurrence_type,
  b.h.holiday_name             AS holiday_name,
  b.h.boost_start              AS occurrence_start,
  b.h.win_end                  AS occurrence_end,

  -- v27.50.1 (verifier nit, 2026-08-12): GREATEST(1, ...) meant a typo'd 0 in the data table
  -- clamped to 1 — the MOST aggressive window the engine can hold — rather than falling back to
  -- the safe default. An out-of-range value now resolves to 3 (the peak default) instead.
  CAST(IF(b.h.holiday_name IS NULL, 7,
          IF(b.r.w_days BETWEEN 1 AND 28, b.r.w_days, 3)) AS INT64) AS w_days,

  CASE
    WHEN b.h.holiday_name IS NULL THEN 'OFF_PEAK_DEFAULT'
    WHEN b.r.w_days IS NULL       THEN 'PEAK_DEFAULT_NO_ROW'
    WHEN b.r.w_days = 3           THEN 'PEAK_DEFAULT_NOT_PROVEN'
    ELSE                               'PEAK_OVERRIDE_PROVEN'
  END AS w_days_source,

  CASE
    WHEN b.h.holiday_name IS NULL THEN 'off peak - 7-day judged window (unchanged; the override table is a peak rule only)'
    ELSE CONCAT(
      'peak (', COALESCE(b.h.occurrence_type, 'UNKNOWN'), ') - ',
      CAST(LEAST(28, GREATEST(1, COALESCE(b.r.w_days, 3))) AS STRING),
      '-day judged window: ',
      CASE
        WHEN b.r.w_days IS NULL THEN 'no measurement row for this occurrence type, so the 3-day default stands (burden of proof is on 7)'
        WHEN b.r.w_days = 3     THEN CONCAT('measured ', CAST(b.r.measured_on AS STRING), ' - verdict ',
                                            COALESCE(b.r.evidence_verdict, 'NOT_PROVEN'),
                                            ', 7 granted in ', CAST(COALESCE(b.r.specs_granted_7, 0) AS STRING), '/',
                                            CAST(COALESCE(b.r.specs_total, 0) AS STRING),
                                            ' specifications, so the 3-day default stands')
        ELSE                         CONCAT('7 PROVEN better on ', COALESCE(b.r.evidence_occurrences, 'prior occurrences'),
                                            ' (measured ', CAST(b.r.measured_on AS STRING),
                                            ', n=', CAST(COALESCE(b.r.evidence_n, 0) AS STRING),
                                            ', granted in ', CAST(COALESCE(b.r.specs_granted_7, 0) AS STRING), '/',
                                            CAST(COALESCE(b.r.specs_total, 0) AS STRING), ' specifications)')
      END)
  END AS w_days_reason,

  b.r.evidence_verdict     AS evidence_verdict,
  b.r.evidence_occurrences AS evidence_occurrences,
  b.r.evidence_n           AS evidence_n,
  b.r.evidence_metric      AS evidence_metric,
  b.r.specs_granted_7      AS specs_granted_7,
  b.r.specs_total          AS specs_total,
  b.r.measured_on          AS measured_on,
  b.r.measured_by          AS measured_by,
  b.r.remeasure_after      AS remeasure_after,
  b.r.comment              AS evidence_comment,
  b.r.remeasure_after IS NOT NULL
    AND CURRENT_DATE('America/New_York') > b.r.remeasure_after AS remeasure_due
FROM base b;
