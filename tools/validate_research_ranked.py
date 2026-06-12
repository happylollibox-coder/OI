#!/usr/bin/env python3
"""Validate FACT_RESEARCH_RANKED / FACT_RESEARCH_TERMS invariants.

Run after SP_REFRESH_RESEARCH_RANKED. Exits non-zero on violation.
SOP: architecture/RESEARCH_PAGE.md
"""
import sys
from google.cloud import bigquery

CHECKS = [
    ("gender enum", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE gender IS NOT NULL AND gender NOT IN ('Female','Male')"""),
    ("age enum", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE age_group IS NOT NULL AND age_group NOT IN
        ('0-2 (Baby)','2-4 (Toddler)','5-9 (Kid)','8-14','10-12 (Tween)','13-17 (Teen)','18+ (Adult)')"""),
    ("rank bounds", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE rank IS NOT NULL AND (rank < 0 OR rank > 100)"""),
    ("off-season holiday rank=0", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE holiday IS NOT NULL AND NOT is_holiday_active AND rank != 0"""),
    ("seg_fit consistency (no-mismatch rows)", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE seg_fit IS NOT NULL
          AND NOT (gender_score = -1 OR age_score = -1 OR occasion_score = -1 OR pt_score = -1)
          AND seg_fit != COALESCE(gender_score,0)+COALESCE(age_score,0)+COALESCE(occasion_score,0)+COALESCE(pt_score,0)"""),
    ("mismatch rows capped at 10", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE (gender_score = -1 OR age_score = -1 OR occasion_score = -1 OR pt_score = -1)
          AND seg_fit != 10"""),
    ("cps_source enum", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE cps_source IS NOT NULL AND cps_source NOT IN ('ads_30d','ads_12m','curve')"""),
    ("ads_cps and effective_cps agree", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE ads_cps IS NOT NULL
          AND (cps_source NOT IN ('ads_30d','ads_12m')
               OR ABS(effective_cps - ads_cps) > 0.06)"""),
    ("intent_factor clamped to [0.5, 2]", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE intent_factor IS NOT NULL AND (intent_factor < 0.5 OR intent_factor > 2.0)"""),
    ("est_cps = curve x intent (within rounding)", """
        -- intent_factor is stored rounded to 2dp while est_cps used the
        -- unrounded factor: tolerance = curve x 0.005 (factor rounding)
        -- + 0.05 (est rounding) + slack
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE est_cps IS NOT NULL AND est_cps_curve IS NOT NULL
          AND ABS(est_cps - est_cps_curve * COALESCE(intent_factor, 1))
              > est_cps_curve * 0.006 + 0.06"""),
    ("fallback overall_fit = seg_fit - bucket penalty", """
        SELECT COUNT(*) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE NOT (ads_family_orders > 3 AND cps_source IN ('ads_30d','ads_12m'))
          AND seg_fit IS NOT NULL
          AND overall_fit != GREATEST(seg_fit - CASE price_bucket
                WHEN 'C. Pricier' THEN 10
                WHEN 'D. Much pricier' THEN 20
                WHEN 'E. Way above' THEN 30
                ELSE 0 END, 0)"""),
    ("ranked table non-empty (inverted)", """
        SELECT IF(COUNT(*) > 0, 0, 1) FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED"""),
    ("terms table non-empty (inverted)", """
        SELECT IF(COUNT(*) > 0, 0, 1) FROM `onyga-482313`.OI.FACT_RESEARCH_TERMS"""),
]


def main():
    client = bigquery.Client(project='onyga-482313')
    failures = 0
    for name, sql in CHECKS:
        n = list(client.query(sql).result())[0][0]
        status = 'OK' if n == 0 else f'FAIL ({n} rows)'
        print(f"  {name}: {status}")
        failures += 1 if n != 0 else 0
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
