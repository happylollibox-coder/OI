#!/usr/bin/env python3
"""Validate FACT_RESEARCH_RECOMMENDATIONS invariants. Exit non-zero on violation.
SOP: architecture/RESEARCH_PAGE.md"""
import sys
from google.cloud import bigquery

T = "`onyga-482313`.OI.FACT_RESEARCH_RECOMMENDATIONS"
CHECKS = [
    ("rec_type enum", f"SELECT COUNT(*) FROM {T} WHERE rec_type NOT IN ('EXACT','PHRASE','BROAD','BRAND')"),
    ("match_type enum", f"SELECT COUNT(*) FROM {T} WHERE match_type NOT IN ('EXACT','PHRASE','BROAD')"),
    ("status enum", f"SELECT COUNT(*) FROM {T} WHERE status NOT IN ('NEW','ADVERTISED','DISMISSED')"),
    ("<=5 NEW per family/type/week", f"""
        SELECT COUNT(*) FROM (
          SELECT parent_name, rec_type, week_start, COUNT(*) n
          FROM {T} WHERE status='NEW' GROUP BY 1,2,3 HAVING n > 5)"""),
    ("non-brand types exclude own brand", f"""
        SELECT COUNT(*) FROM {T}
        WHERE rec_type IN ('EXACT','PHRASE','BROAD') AND LOWER(keyword) LIKE '%happy lolli%'"""),
    ("brand type is PHRASE match", f"SELECT COUNT(*) FROM {T} WHERE rec_type='BRAND' AND match_type != 'PHRASE'"),
    ("broad rows have cluster sales > 500", f"""
        SELECT COUNT(*) FROM {T} WHERE rec_type='BROAD' AND COALESCE(market_sales,0) <= 500"""),
    ("phrase rows are >= 3 words", f"""
        SELECT COUNT(*) FROM {T}
        WHERE rec_type='PHRASE' AND ARRAY_LENGTH(SPLIT(TRIM(keyword),' ')) < 3"""),
]


def main():
    client = bigquery.Client(project='onyga-482313')
    fails = 0
    for name, sql in CHECKS:
        n = list(client.query(sql).result())[0][0]
        print(f"  {name}: {'OK' if n == 0 else f'FAIL ({n})'}")
        fails += 1 if n else 0
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
