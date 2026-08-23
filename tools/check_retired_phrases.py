#!/usr/bin/env python3
"""THE RETIRED-PHRASE CHECK — the only instrument for the files the SQL suite cannot read.

The deploy command strips every `--` line, so the view's own header block does not exist in the
deployed definition: no acceptance check, and no query against INFORMATION_SCHEMA.VIEWS, can catch
a stale sentence in the header of a .sql file, in an SOP, or in the object registry. A retired
belief has now survived in those three places twice while every SQL check passed.

WHY THIS IS A SCRIPT AND NOT A GREP IN A COMMENT (2026-08-23, eighth repair pass)
    The check used to be a `grep -nE '…' file file` written inside the acceptance suite's doc
    block. It failed twice, in two different ways, and both are structural:
      1. IT IS LINE-BASED AND THE FILES ARE HARD-WRAPPED. "the sheet that would pause it does not
         exist" IS in the SOP and the documented grep does not return it, because the phrase
         straddles a line break. Run as written the grep returned 2 hits; a whitespace-insensitive
         scan of the same two files returns 4. Any retired sentence longer than a few words has
         roughly even odds of being missed the same way.
      2. IT READ TWO FILES AND THERE ARE THREE. config.yaml carries the same doctrine at book
         length — the V_FAMILY_SEAT_REGISTER entry is a page of prose — and sat outside the grep
         entirely, which is exactly where the next retired clause was found.
    So: whitespace-insensitive, every file that carries the doctrine, and runnable.

THE RULE IT ENFORCES
    A retired phrase may appear ONLY inside quotation marks, where a repair-pass narrative records
    what a dead sentence used to say. A match outside quotes — in a view header, a normative
    paragraph, a rulings row or a registry description — is the defect. The quoting test is a
    a LOCAL test — a quote mark close before the phrase and another close after it — so a phrase
    quoted across a line break still reads as quoted and one stray quote elsewhere in the file
    cannot invert the answer for everything below it.

WHEN A MODEL IS RETIRED, ITS PHRASES ARE ADDED HERE IN THE SAME COMMIT that retires it. A check
that only knows yesterday's wrong answer passes over today's.

    /usr/bin/python3 tools/check_retired_phrases.py          # exit 1 on any unquoted hit
    /usr/bin/python3 tools/check_retired_phrases.py --list   # what it hunts, and why
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Every file that publishes the family seat register's doctrine in prose. The SQL acceptance suite
# can read none of them: two are stripped of comments before deploy, the third is never deployed.
# (path, does a straight " mark a QUOTATION here?). In config.yaml a straight " is the YAML
# scalar delimiter — the whole description is wrapped in one — so counting it as quotation would
# make every retired clause in the registry read as "quoted, therefore allowed", which is exactly
# how the stale R-l(d) reasoning survived there. Registry prose quotes a dead sentence with the
# typographic pair or with single quotes; only those count.
FILES = [
    ('scripts/bigquery/views/V_FAMILY_SEAT_REGISTER.sql', True),
    ('architecture/FAMILY_SEAT_REGISTER.md', True),
    ('config.yaml', False),
    ('tools/build_seat_moves_bulksheet.py', True),
    ('tools/build_reprice_bulksheet.py', True),
    ('scripts/bigquery/views/V_DAILY_BRIEF.sql', True),
    ('scripts/bigquery/views/V_RUN_SUMMARY.sql', True),
]

# (regex, retired on, what replaced it). The regex is matched against the file with ALL runs of
# whitespace collapsed to one space, so a phrase that wraps is still found.
RETIRED = [
    (r'closed-but-spending keywords are paused', '2026-08-22',
     'a projection may not pause a category — the credit is per row, against the change log'),
    (r'leaks stay paused', '2026-08-22', 'same'),
    (r'the leaks are paused', '2026-08-22', 'same'),
    (r'stalled probes are parked', '2026-08-22',
     'parking lowers a price; the spend continues (R-l)'),
    (r'pauses you can upload', '2026-08-22',
     'the FAMILY row names the BOOK its pauses ride on, never an upload "today"'),
    (r'Task 3, not (yet )?shipped', '2026-08-23',
     'the leak arm shipped that day (tools/build_seat_moves_bulksheet.py)'),
    (r'Leaks are NOT paused on either projection', '2026-08-23',
     'a leak reaches $0 exactly where a pending KEYWORD_PAUSE row carries it'),
    (r'nothing pauses them until the leak arm ships', '2026-08-23', 'same'),
    (r'leak arm of .tools/build_reprice_bulksheet', '2026-08-23',
     'the leak arm is its own file, tools/build_seat_moves_bulksheet.py'),
    (r'the sheet that would pause it does not exist', '2026-08-23', 'both sheets exist'),
    (r'the unbuilt (leak )?arm', '2026-08-23', 'same'),
    (r'The pauses on the next book recover', '2026-08-23',
     'the closing sentence reads "The pauses named above recover $…"'),
    # ── eighth pass, 2026-08-23 ───────────────────────────────────────────────────────────────
    (r'same rule, opposite answer, because one sheet exists and the other does not', '2026-08-23',
     'R-l(d) reasoning, true only for the one day the leak sheet did not exist; both exist now'),
    (r'--supersede BATCH. labels an earlier never-uploaded book', '2026-08-23',
     '--supersede is a terminal action that labels and stops, stated as such beside '
     '--mark-uploaded, and the register names it in the row that offers the choice'),
    (r'counts every non-holdout LEAK', '2026-08-23',
     'the recovered-today figure counts only the pauses the leak book will WRITE (B36)'),
    (r'ads watermark [0-9-]+\)\s*while', '2026-08-23',
     'the book and the register measure one window: LEAST(MAX(date), FN_ADS_ANCHOR_CAP())'),
    # ── ninth pass, 2026-08-23 (first-production-night cleanup) ──────────────────────────────
    (r'publishes are that same week', '2026-08-23',
     'the README states the book\'s OWN window; the register re-anchors daily'),
    (r'ride the next leak book \(tools', '2026-08-23',
     'one leak book, one instruction (R-n): a stale book is rebuilt with --replaces, never '
     'uploaded beside a next book'),
    (r"upload_status IS NULL OR upload_status = 'PENDING_UPLOAD'", '2026-08-23',
     'a label is written on PENDING_UPLOAD rows only; NULL is the applied state'),
    (r"THEN 'passes — no action'", '2026-08-23',
     'the brief action is derived from what is executable (sheet_row), never the status alone'),
    (r"THEN 'close the gap'", '2026-08-23', 'same'),
]

# how far either side of a match a quotation mark may sit and still be the one enclosing it
BEFORE, AFTER = 250, 350


def inside_quotes(text, start, end, straight_quotes=True):
    """True when the span [start, end) sits inside a quotation — a quote mark close before it and
    another close after it.

    WHY LOCAL AND NOT A PARITY COUNT. The first version of this counted quote characters from the
    top of the file and called an odd count 'inside'. That is exact prose and wrong on real files:
    one Markdown code span holding a triple quote, one SQL string literal, one apostrophe-heavy
    comment, and every match below it flips to the wrong answer - a check that reports the
    opposite of the truth because of an unrelated edit is worse than no check. A quotation is a
    LOCAL fact, so it is measured locally, and the windows are stated rather than tuned.
    """
    opens = '"“„«' if straight_quotes else '“„«'
    closes = '"”»' if straight_quotes else '”»'
    before = text[max(0, start - BEFORE):start]
    after = text[end:end + AFTER]
    return any(c in before for c in opens) and any(c in after for c in closes)


def line_of(raw, collapsed_pos, offsets):
    """The 1-based line in the ORIGINAL file for a position in the collapsed text."""
    orig = offsets[min(collapsed_pos, len(offsets) - 1)]
    return raw.count('\n', 0, orig) + 1


def collapse(raw):
    """The file with every whitespace run collapsed to one space, plus a map from each collapsed
    position back to its original offset."""
    out, offs, prev_ws = [], [], False
    for i, ch in enumerate(raw):
        if ch.isspace():
            if not prev_ws:
                out.append(' ')
                offs.append(i)
            prev_ws = True
        else:
            out.append(ch)
            offs.append(i)
            prev_ws = False
    offs.append(len(raw))
    return ''.join(out), offs


def scan(files=None):
    """Every hit, as (path, line, phrase, quoted, excerpt)."""
    hits = []
    for rel, straight in (files or FILES):
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        raw = open(path, encoding='utf-8').read()
        text, offs = collapse(raw)
        for pat, when, replacement in RETIRED:
            for m in re.finditer(pat, text, re.IGNORECASE):
                hits.append((rel, line_of(raw, m.start(), offs), pat,
                             inside_quotes(text, m.start(), m.end(), straight),
                             text[max(0, m.start() - 60):m.end() + 40], when, replacement))
    return hits


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--list', action='store_true', help='print what is hunted and why')
    ap.add_argument('--all', action='store_true', help='also print the quoted (allowed) hits')
    args = ap.parse_args()

    if args.list:
        for pat, when, why in RETIRED:
            print(f"  retired {when}  {pat}\n      now: {why}")
        return 0

    hits = scan()
    bad = [h for h in hits if not h[3]]
    if args.all:
        for rel, ln, pat, quoted, excerpt, when, why in hits:
            print(f"{'quoted ' if quoted else 'UNQUOTED'} {rel}:{ln}  /{pat}/\n    …{excerpt}…")
    if not bad:
        print(f"retired phrases: {len(hits)} hit(s), all inside quotation marks — "
              f"{len(FILES)} file(s) scanned, whitespace-insensitive. PASS")
        return 0
    for rel, ln, pat, _q, excerpt, when, why in bad:
        print(f"FAIL {rel}:{ln} — a phrase retired {when} is published OUTSIDE quotation marks:\n"
              f"    /{pat}/\n    …{excerpt}…\n    the model now in force: {why}")
    return 1


if __name__ == '__main__':
    sys.exit(main())
