"""
Apply a batch of curated add/remove edits to DE_PRODUCT_PHRASE_NEGATIVES.

Ori's edit list, 2026-07-17. Two themes:
  1. Un-fence real buyers: drop age/audience words that were blocking valid intent
     (kid/kids, woman/women, toy/toys) and swap Fresh's bare numbers 17-30 — which
     killed "gifts for 17 year old" — for explicit "<n> dollar(s)" price phrases.
  2. Cross-family + brand fencing: each family negates the OTHER families' product
     names, plus its own brand name (brand traffic belongs to defense campaigns only).
     Generic words are deliberately not added — e.g. Bottle does not negate "bottle".

'lol' is an _ALL row, so it cannot be removed for LolliBall alone. Per Ori: delete the
global row and re-add it family-level for the other five, so only LolliBall changes.

Snapshots the table first. Idempotent: re-running adds nothing and removes nothing twice.

Usage:
    /usr/bin/python3 tools/apply_phrase_negative_edits.py [--apply]   # default is dry-run
"""
import argparse
import subprocess
import json
import sys
import uuid

PROJECT = "onyga-482313"
TABLE = f"{PROJECT}.OI.DE_PRODUCT_PHRASE_NEGATIVES"
ALL_FAMILIES = ["Bottle", "Bunny", "Fresh", "LolliBall", "LolliME", "Lollibox"]

# Phrases are stored lowercase throughout this table; Amazon matches case-insensitively.
REMOVE = {
    "LolliBall": ["toy", "toys", "quinceanera", "random", "jewelry", "decorations"],
    "Bottle":    ["toy", "toys", "quinceanera", "night", "kid", "kids"],
    "Lollibox":  ["kid", "kids", "things", "things for girls 10-12", "dollar", "dollars", "quinceanera"],
    "Bunny":     ["woman", "women", "toy", "toys"],
    "Fresh":     ["woman", "women"] + [str(n) for n in range(17, 31)],
}

_PRICES = [f"{n} dollar" for n in range(17, 31)] + [f"{n} dollars" for n in range(17, 31)]
ADD = {
    "LolliBall": ["bottle", "lollibox", "fresh", "power shower", "lolliball"],
    "Bottle":    ["lollibox", "fresh", "power shower", "lolliball"],
    "Lollibox":  ["bottle", "lollibox", "fresh", "power shower", "lolliball"],
    "Bunny":     ["bottle", "lollibox", "fresh", "lolliball", "lollibunny"],
    "Fresh":     _PRICES + ["bottle", "lollibox", "fresh", "lolliball", "lollibunny"],
}

# 'lol' lives in _ALL. Drop it there, keep it for everyone except LolliBall.
LOL_KEEP_FOR = [f for f in ALL_FAMILIES if f != "LolliBall"]


def bq(sql, dry_run=False):
    cmd = ['bq', 'query', '--use_legacy_sql=false', '--format=json', '--max_rows=100000']
    if dry_run:
        cmd.append('--dry_run')
    out = subprocess.run(cmd + [sql], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"BigQuery failed:\n{out.stderr}\n--- SQL ---\n{sql[:600]}")
    if dry_run:
        return []
    try:
        return json.loads(out.stdout or '[]')
    except json.JSONDecodeError:
        return []  # DDL/DML print a status line, not JSON


def sql_list(items):
    return ", ".join("'" + i.replace("'", "\\'") + "'" for i in items)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true', help='Execute. Without this, only reports what would change.')
    args = ap.parse_args()

    # ── What the edits will actually touch (case-insensitive, ACTIVE rows only) ──
    del_clauses = [
        f"(parent_name = '{fam}' AND LOWER(phrase) IN ({sql_list(ph)}))"
        for fam, ph in REMOVE.items()
    ]
    del_where = " OR ".join(del_clauses) + " OR (parent_name = '_ALL' AND LOWER(phrase) = 'lol')"

    hits = bq(f"SELECT parent_name, phrase FROM `{TABLE}` WHERE {del_where} ORDER BY parent_name, phrase")
    print(f"REMOVE — {len(hits)} rows matched:")
    for fam in sorted({h['parent_name'] for h in hits}):
        got = [h['phrase'] for h in hits if h['parent_name'] == fam]
        print(f"  {fam:<10} ({len(got):>2}) {', '.join(got)}")

    # Report anything on the remove list that isn't there (typo / already gone)
    for fam, phrases in REMOVE.items():
        present = {h['phrase'].lower() for h in hits if h['parent_name'] == fam}
        missing = [p for p in phrases if p not in present]
        if missing:
            print(f"  ! {fam}: not in table, skipping — {', '.join(missing)}")

    # ── Adds, skipping any that already exist at that family level ──
    existing = bq(f"""
        SELECT parent_name, LOWER(phrase) AS phrase FROM `{TABLE}`
        WHERE parent_name IN ({sql_list(list(ADD.keys()) + ['_ALL'])})
    """)
    have = {(e['parent_name'], e['phrase']) for e in existing}
    # A phrase removed above is gone, so it may be legitimately re-added
    removed = {(h['parent_name'], h['phrase'].lower()) for h in hits}
    have -= removed

    to_add, redundant = [], []
    for fam, phrases in ADD.items():
        for p in phrases:
            if (fam, p) in have:
                continue
            if ('_ALL', p) in have:
                # Already global — the view's _ALL expansion covers this family already
                redundant.append((fam, p))
                continue
            to_add.append((fam, p))

    lol_rows = [(fam, 'lol') for fam in LOL_KEEP_FOR]
    print(f"\nADD — {len(to_add) + len(lol_rows)} rows:")
    for fam in sorted({f for f, _ in to_add}):
        got = [p for f, p in to_add if f == fam]
        print(f"  {fam:<10} ({len(got):>2}) {', '.join(got)}")
    print(f"  {'(lol)':<10} ({len(lol_rows):>2}) re-added family-level for {', '.join(LOL_KEEP_FOR)}")
    if redundant:
        print(f"\n  skipped as already global in _ALL: {', '.join(f'{f}/{p}' for f, p in redundant)}")

    if not args.apply:
        print("\nDRY RUN — nothing changed. Re-run with --apply.")
        return

    # ── Snapshot before mutating ──
    snap = f"{PROJECT}.OI.DE_PRODUCT_PHRASE_NEGATIVES_BAK_20260717"
    bq(f"CREATE OR REPLACE TABLE `{snap}` AS SELECT * FROM `{TABLE}`")
    print(f"\nsnapshot → {snap}")

    bq(f"DELETE FROM `{TABLE}` WHERE {del_where}")
    print(f"deleted {len(hits)} rows")

    rows = to_add + lol_rows
    values = ", ".join(
        f"('{uuid.uuid4()}', '{fam}', NULL, '{p}', 'Negative Phrase', 'MANUAL', 'ACTIVE', "
        f"CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP())"
        for fam, p in rows
    )
    bq(f"""INSERT INTO `{TABLE}`
           (id, parent_name, product_short_name, phrase, match_type, source, status, created_at, updated_at)
           VALUES {values}""")
    print(f"inserted {len(rows)} rows")

    for t in ("T_PRODUCT_PHRASE_NEGATIVES", "T_LAUNCH_NEGATIVES"):
        v = t.replace("T_", "V_", 1)
        bq(f"CREATE OR REPLACE TABLE `{PROJECT}.OI.{t}` AS SELECT * FROM `{PROJECT}.OI.{v}`")
    print("refreshed T_PRODUCT_PHRASE_NEGATIVES + T_LAUNCH_NEGATIVES")

    after = bq(f"SELECT effective_parent_name AS fam, COUNT(*) n FROM `{PROJECT}.OI.V_PRODUCT_PHRASE_NEGATIVES` GROUP BY 1 ORDER BY 1")
    print("\nresolved phrases per family now:")
    for r in after:
        print(f"  {r['fam']:<10} {r['n']}")


if __name__ == '__main__':
    main()
