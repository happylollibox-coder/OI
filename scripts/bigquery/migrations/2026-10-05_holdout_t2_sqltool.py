#!/usr/bin/env python3
"""Text helper for the holdout trial 2 runbook (2026-10-05_holdout_t2_deploy.sh / _rollback.sh).

Plan docs/superpowers/plans/2026-10-03-holdout-restart.md, Task 8 (Task R). It reads and rewrites SQL
text only; it never talks to BigQuery. Subcommands:

  strip FILE                 FILE with whole-line '--' comments removed (how every object of the plan
                             is deployed: grep -v '^[[:space:]]*--').
  xform FILE [opts]          the text the runbook sends:
      --prefix P             rehearsal: every object of this deploy (NAMES below) is renamed P+NAME,
                             whatever its quoting (`onyga-482313.OI.N`, `onyga-482313`.OI.N, OI.N);
      --pin DATE             CURRENT_DATE('America/Los_Angeles') becomes DATE 'DATE';
      --quoted               also renames the quoted literal 'NAME' (INFORMATION_SCHEMA filters in the
                             acceptance files);
      --k7 P                 K7's object filter and pattern read the P-prefixed copies;
      --create-or-replace    a saved INFORMATION_SCHEMA ddl (CREATE VIEW / CREATE PROCEDURE) becomes
                             CREATE OR REPLACE;
      --expect NAME          the first CREATE must create NAME (P+NAME with --prefix);
      --script               with --prefix: every write anywhere in the text (CREATE, INSERT, UPDATE,
                             DELETE, MERGE, TRUNCATE, DROP, CALL) must name a P-prefixed object or a
                             temp table. Without --script only the first CREATE is checked (an object
                             file: a procedure body's own writes do not run at CREATE).
                             With --prefix the output may not name any object of NAMES unprefixed.
  writes FILE                every write target in FILE, one per line (strings and comments masked).
  body FILE                  the body of the CREATE VIEW / CREATE PROCEDURE statement in FILE (the
                             query after AS / the BEGIN .. END block), comments removed and whitespace
                             collapsed. A saved ddl and a repo file give the same body for the same object.
  same A B                   exit 0 when body(A) == body(B), else print a line diff and exit 1.
  select FILE ID [ID ...]    the statements of an acceptance file whose check_name literal starts with
                             'ID_' (K1, K7, K9b, ...), in file order, ';'-joined.
  rows                       stdin: bq output (prettyjson / json); stdout: one JSON object per check row.
  columns FILE               'name TYPE [NOT NULL]' per column of the CREATE TABLE in FILE.
  bqcolumns                  stdin: bq json rows of INFORMATION_SCHEMA.COLUMNS (column_name, data_type,
                             is_nullable); stdout: the same format as columns.
  cte FILE NAME              the body (inside the parentheses) of the CTE 'NAME AS (' in FILE.
  block FILE START END       normalized text from the line holding START to the CTE named END, end of
                             its parentheses (used to prove two files carry the same block).
  guard [--date D] [...]     stdin: the runbook's guard query result (json); decides the deploy window.
"""
import argparse
import datetime as dt
import difflib
import json
import re
import sys

PROJECT = 'onyga-482313'
DATASET = 'OI'
# every object the deploy writes or replaces (and the live table the founding appends to)
NAMES = [
    'DE_HOLDOUT_TRIAL', 'DE_HOLDOUT_BASELINE', 'DE_HOLDOUT_ASSIGNMENT',
    'V_HOLDOUT_TRIAL', 'V_HOLDOUT_ARM', 'V_HOLDOUT_ELIGIBLE', 'SP_ASSIGN_HOLDOUT',
    'SP_ENGINE_PREFLIGHT', 'V_PLAN_WINDOW_JUDGMENT', 'V_FAMILY_SEAT_REGISTER',
    'V_HOLDOUT_READOUT', 'V_ENGINE_HEALTH',
]
LA_TODAY = "CURRENT_DATE('America/Los_Angeles')"


def die(msg):
    sys.stderr.write('sqltool: ' + msg + '\n')
    sys.exit(2)


def read(path):
    with open(path) as f:
        return f.read()


def strip_comment_lines(text):
    return '\n'.join(l for l in text.split('\n') if not re.match(r'^\s*--', l))


# ---------------------------------------------------------------------------------------------
# tokenizer: strings ('..', "..", '''..''', """..""", with backslash escapes), `identifiers`,
# comments (-- .., # .., /* .. */), words, whitespace, punctuation
# ---------------------------------------------------------------------------------------------
def tokens(sql):
    i, n = 0, len(sql)
    while i < n:
        c = sql[i]
        if c in ' \t\r\n\f':
            j = i
            while j < n and sql[j] in ' \t\r\n\f':
                j += 1
            yield ('ws', sql[i:j])
            i = j
        elif sql.startswith('--', i) or c == '#':
            j = sql.find('\n', i)
            j = n if j < 0 else j
            yield ('comment', sql[i:j])
            i = j
        elif sql.startswith('/*', i):
            j = sql.find('*/', i + 2)
            j = n if j < 0 else j + 2
            yield ('comment', sql[i:j])
            i = j
        elif c in '\'"':
            q = sql[i:i + 3] if sql[i:i + 3] in ("'''", '"""') else c
            j = i + len(q)
            while j < n:
                if sql[j] == '\\':
                    j += 2
                    continue
                if sql.startswith(q, j):
                    j += len(q)
                    break
                j += 1
            yield ('str', sql[i:j])
            i = j
        elif c == '`':
            j = sql.find('`', i + 1)
            j = n if j < 0 else j + 1
            yield ('ident', sql[i:j])
            i = j
        elif c.isalnum() or c == '_':
            j = i
            while j < n and (sql[j].isalnum() or sql[j] == '_'):
                j += 1
            yield ('word', sql[i:j])
            i = j
        else:
            yield ('punct', c)
            i += 1


def compact(sql):
    """tokens with comments and whitespace folded into single 'sp' tokens"""
    out = []
    for k, t in tokens(sql):
        if k in ('ws', 'comment'):
            if out and out[-1][0] != 'sp':
                out.append(('sp', ' '))
        else:
            out.append((k, t))
    while out and out[0][0] == 'sp':
        out.pop(0)
    return out


def text_of(toks):
    s = ''.join(t for _, t in toks).strip()
    while s.endswith(';'):
        s = s[:-1].rstrip()
    return s


def body(sql):
    """the body of the first CREATE VIEW / PROCEDURE statement: what INFORMATION_SCHEMA's ddl and a repo
    file have in common for one object (the name's quoting, OR REPLACE and OPTIONS differ)"""
    toks = compact(sql)
    sig = [(i, k, t) for i, (k, t) in enumerate(toks) if k != 'sp']

    def word(j, *ws):
        return j < len(sig) and sig[j][1] == 'word' and sig[j][2].upper() in ws

    def skip_parens(j):
        depth = 0
        while j < len(sig):
            if sig[j][1] == 'punct' and sig[j][2] == '(':
                depth += 1
            elif sig[j][1] == 'punct' and sig[j][2] == ')':
                depth -= 1
                if depth == 0:
                    return j + 1
            j += 1
        die('unbalanced parentheses')

    j = 0
    while j < len(sig) and not word(j, 'CREATE'):
        j += 1
    while j < len(sig) and not word(j, 'VIEW', 'PROCEDURE'):
        j += 1
    if j >= len(sig):
        die('no CREATE VIEW / PROCEDURE statement')
    kind = sig[j][2].upper()
    j += 1
    if kind == 'VIEW':
        while j < len(sig) and not word(j, 'OPTIONS', 'AS'):
            j += 1
        if word(j, 'OPTIONS'):
            j = skip_parens(j + 1)
        if not word(j, 'AS'):
            die('CREATE VIEW without AS')
        start = sig[j + 1][0]
    else:
        while j < len(sig) and not (sig[j][1] == 'punct' and sig[j][2] == '('):
            j += 1
        j = skip_parens(j)          # the parameter list
        if word(j, 'OPTIONS'):
            j = skip_parens(j + 1)
        if not word(j, 'BEGIN'):
            die('CREATE PROCEDURE without BEGIN')
        start = sig[j][0]
    return kind, text_of(toks[start:])


def display_lines(sql):
    """comment-free lines with inner whitespace collapsed, for a readable diff"""
    out = []
    for k, t in tokens(sql):
        if k == 'comment':
            continue
        out.append(t)
    lines = []
    for l in ''.join(out).split('\n'):
        l = re.sub(r'[ \t]+', ' ', l).strip()
        if l:
            lines.append(l)
    return lines


def body_lines(sql):
    kind, b = body(sql)
    # re-split the collapsed body for display at the main clause keywords
    b = re.sub(r' (?=(WITH|SELECT|FROM|WHERE|JOIN|LEFT JOIN|UNION ALL|GROUP BY|ORDER BY|QUALIFY|AND|OR|'
               r'[A-Za-z_][A-Za-z0-9_]* AS \())\b', '\n', b)
    return b.split('\n')


# ---------------------------------------------------------------------------------------------
# renaming for the rehearsal, and the write guard
# ---------------------------------------------------------------------------------------------
def rename(sql, prefix, quoted):
    for n in NAMES:
        pat = r'`?%s`?\.`?%s`?\.`?%s\b`?' % (re.escape(PROJECT), DATASET, n)
        sql = re.sub(pat, '`%s.%s.%s%s`' % (PROJECT, DATASET, prefix, n), sql)
        if quoted:
            sql = sql.replace("'%s'" % n, "'%s%s'" % (prefix, n))
    return sql


def masked(sql):
    """comments dropped and string contents blanked, so a write named in a string is not a write"""
    out = []
    for k, t in tokens(sql):
        if k == 'comment':
            out.append(' ')
        elif k == 'str':
            out.append("''")
        else:
            out.append(t)
    return ''.join(out)


WRITE_RX = re.compile(
    r'\b(CREATE(?:\s+OR\s+REPLACE)?(?:\s+TEMP(?:ORARY)?)?\s+(?:TABLE|VIEW|PROCEDURE|FUNCTION)'
    r'(?:\s+IF\s+NOT\s+EXISTS)?|INSERT(?:\s+INTO)?|UPDATE|DELETE(?:\s+FROM)?|MERGE(?:\s+INTO)?|'
    r'TRUNCATE\s+TABLE|DROP\s+(?:TABLE|VIEW|PROCEDURE|FUNCTION)(?:\s+IF\s+EXISTS)?|CALL)\s+'
    r'((?:`[^`]+`|[A-Za-z_][A-Za-z0-9_\-]*)(?:\.(?:`[^`]+`|[A-Za-z_][A-Za-z0-9_\-]*))*)',
    re.I)


def write_targets(sql):
    res = []
    for m in WRITE_RX.finditer(masked(sql)):
        res.append((re.sub(r'\s+', ' ', m.group(1).upper()), m.group(2)))
    return res


def object_of(target):
    """('OI', NAME) for an object of the dataset, (None, NAME) for a temp table"""
    parts = target.replace('`', '').split('.')
    if len(parts) == 1:
        return None, parts[0]
    return parts[-2], parts[-1]


def first_create(sql):
    for verb, tgt in write_targets(sql):
        if verb.startswith('CREATE'):
            return verb, tgt
    return None, None


def cmd_xform(a):
    sql = strip_comment_lines(read(a.file))
    if a.create_or_replace:
        sql, n = re.subn(r'^\s*CREATE\s+(VIEW|PROCEDURE)\b', r'CREATE OR REPLACE \1', sql, count=1, flags=re.I)
        if n != 1:
            die('--create-or-replace: no leading CREATE VIEW / PROCEDURE in ' + a.file)
    if a.prefix:
        if not a.prefix.startswith('TMP_HT2_'):
            die('a rehearsal prefix must start with TMP_HT2_')
        sql = rename(sql, a.prefix, a.quoted)
    if a.k7:
        sql2 = sql.replace("NOT STARTS_WITH(object_name, 'TMP_HT2_')", "STARTS_WITH(object_name, '%s')" % a.k7)
        sql2 = sql2.replace(r"DE_HOLDOUT_ASSIGNMENT\b')", r"%sDE_HOLDOUT_ASSIGNMENT\b')" % a.k7)
        if sql2.count(a.k7) < sql.count(a.k7) + 2:
            die('--k7: K7 text not found')
        sql = sql2
    if a.pin:
        if not re.match(r'^\d{4}-\d{2}-\d{2}$', a.pin):
            die('--pin wants YYYY-MM-DD')
        sql = sql.replace(LA_TODAY, "DATE '%s'" % a.pin)
    if a.expect:
        verb, tgt = first_create(sql)
        want = (a.prefix or '') + a.expect
        if tgt is None or object_of(tgt)[1] != want:
            die('%s: first CREATE targets %s, expected %s' % (a.file, tgt, want))
    if a.prefix:
        left = re.findall(r'\b%s`?\.`?(%s)\b' % (DATASET, '|'.join(NAMES)), sql)
        if left:
            die('%s: live object(s) still named after renaming: %s' % (a.file, sorted(set(left))))
        targets = write_targets(sql) if a.script else [first_create(sql)]
        for verb, tgt in targets:
            if tgt is None:
                continue
            ds, name = object_of(tgt)
            if ds is None and not verb.startswith('CALL'):
                continue          # a temp table
            if not name.startswith(a.prefix):
                die('%s: %s %s is not a rehearsal object' % (a.file, verb, tgt))
    sys.stdout.write(sql.rstrip() + '\n')


def cmd_writes(a):
    for verb, tgt in write_targets(read(a.file)):
        print(verb, tgt)


def cmd_body(a):
    kind, b = body(read(a.file))
    print(b)


def cmd_same(a):
    ka, ba = body(read(a.a))
    kb, bb = body(read(a.b))
    if ka == kb and ba == bb:
        print('same %s body (%d characters, comments and whitespace aside)' % (ka.lower(), len(ba)))
        return
    print('DIFFERENT (%s vs %s; comments and whitespace aside):' % (a.a, a.b))
    la, lb = body_lines(read(a.a)), body_lines(read(a.b))
    d = list(difflib.unified_diff(la, lb, a.label_a or a.a, a.label_b or a.b, lineterm='', n=1))
    for l in d[:a.max_lines]:
        print('  ' + l[:400])
    if len(d) > a.max_lines:
        print('  ... %d more diff lines' % (len(d) - a.max_lines))
    sys.exit(1)


def statements(sql):
    """top-level ';'-separated statements of a flat script (no BEGIN blocks)"""
    cur, out = [], []
    for k, t in tokens(sql):
        if k == 'punct' and t == ';':
            out.append(''.join(cur).strip())
            cur = []
        else:
            cur.append(t)
    if ''.join(cur).strip():
        out.append(''.join(cur).strip())
    return [s for s in out if s and not all(k in ('ws', 'comment') for k, _ in tokens(s))]


def cmd_select(a):
    want = set(a.ids)
    picked = []
    for s in statements(strip_comment_lines(read(a.file))):
        m = re.search(r"'(K\d+b?)_[A-Za-z0-9_]+' AS check_name", s)
        if m and m.group(1) in want:
            picked.append((m.group(1), s))
    got = [i for i, _ in picked]
    missing = [i for i in a.ids if i not in got]
    if missing:
        die('%s: no statement for %s' % (a.file, ', '.join(missing)))
    sys.stdout.write(';\n\n'.join(s for _, s in picked) + ';\n')


def cmd_rows(a):
    text = sys.stdin.read()
    dec = json.JSONDecoder()
    i, n = 0, 0
    while True:
        i = text.find('{', i)
        if i < 0:
            break
        try:
            obj, j = dec.raw_decode(text, i)
        except ValueError:
            i += 1
            continue
        if isinstance(obj, dict) and 'check_name' in obj:
            print(json.dumps(obj, sort_keys=True))
            n += 1
            i = j
        else:
            i += 1
    if n == 0:
        sys.exit(1)


def cmd_columns(a):
    sql = masked(strip_comment_lines(read(a.file)))
    m = re.search(r'CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+\S+\s*\(', sql, re.I)
    if not m:
        die('no CREATE TABLE in ' + a.file)
    j, depth, start = m.end(), 1, m.end()
    while depth:
        if sql[j] == '(':
            depth += 1
        elif sql[j] == ')':
            depth -= 1
        j += 1
    for col in re.split(r',(?![^(<]*[)>])', sql[start:j - 1]):
        col = col.strip()
        if not col:
            continue
        mm = re.match(r'(\w+)\s+([A-Za-z0-9_<>, ]+?)(\s+NOT\s+NULL)?\s*$', col, re.I)
        if not mm:
            die('cannot read column: ' + col)
        print('%s %s%s' % (mm.group(1), mm.group(2).upper(),
                           ' NOT NULL' if mm.group(3) else ''))


def cmd_bqcolumns(a):
    rows = json.load(sys.stdin)
    for r in sorted(rows, key=lambda r: int(r['ordinal_position'])):
        print('%s %s%s' % (r['column_name'], r['data_type'], ' NOT NULL' if r['is_nullable'] == 'NO' else ''))


def paren_end(s, open_idx):
    """index after the ')' matching s[open_idx] == '(' (strings and comments respected)"""
    depth = 0
    pos = 0
    for k, t in tokens(s[open_idx:]):
        if k == 'punct' and t == '(':
            depth += 1
        elif k == 'punct' and t == ')':
            depth -= 1
            if depth == 0:
                return open_idx + pos + 1
        pos += len(t)
    die('unbalanced CTE')


def cmd_cte(a):
    s = read(a.file)
    m = re.search(r'\b%s AS \(' % re.escape(a.name), s)
    if not m:
        die('CTE %s not found in %s' % (a.name, a.file))
    end = paren_end(s, m.end() - 1)
    print(s[m.end():end - 1])


def cmd_block(a):
    s = strip_comment_lines(read(a.file))
    i = s.find(a.start)
    m = re.search(r'\b%s AS \(' % re.escape(a.end), s[i:]) if i >= 0 else None
    if i < 0 or not m:
        die('block %s .. %s not found in %s' % (a.start, a.end, a.file))
    j = paren_end(s, i + m.end() - 1)
    print(text_of(compact(s[i:j])))


# ---------------------------------------------------------------------------------------------
# the deploy window (plan Task 8): see the deploy script's header for the measured pass pattern
# ---------------------------------------------------------------------------------------------
def ts(v):
    if v in (None, '', 'NULL'):
        return None
    v = v.replace(' UTC', '').replace('T', ' ').rstrip('Z')
    for f in ('%Y-%m-%d %H:%M:%S.%f', '%Y-%m-%d %H:%M:%S'):
        try:
            return dt.datetime.strptime(v, f)
        except ValueError:
            pass
    try:
        return dt.datetime.utcfromtimestamp(float(v))
    except ValueError:
        die('bad timestamp ' + v)


def cmd_guard(a):
    text = sys.stdin.read()
    m = re.search(r'^\[', text, re.M)      # bq may print progress lines before the JSON
    if not m:
        die('guard: no JSON result in: ' + text[-500:])
    rows = json.loads(text[m.start():])
    if not rows:
        die('guard: empty result')
    r = rows[0]
    now = ts(r['now_utc'])
    la = r['la_date']
    d = dt.datetime.strptime(a.date, '%Y-%m-%d')
    p2_lo, p2_hi = d + dt.timedelta(hours=7), d + dt.timedelta(hours=12)
    p3_lo, p3_hi = d + dt.timedelta(hours=12), d + dt.timedelta(hours=24)
    prim_end = d + dt.timedelta(hours=15, minutes=40)
    fb_end = d + dt.timedelta(days=1, hours=4, minutes=40)
    passes = json.loads(r.get('passes_json') or 'null') or []
    jobs = json.loads(r.get('jobs_json') or 'null') or []

    def pass_in(lo, hi):
        c = [p for p in passes if p.get('pass_start') and lo <= ts(p['pass_start']) < hi]
        c.sort(key=lambda p: ts(p['pass_start']))
        return c[0] if c else None

    def fmt(p):
        if not p:
            return 'not started'
        return 'run %s started %s UTC, %s' % (
            p['run_id'][:8], p['pass_start'][:19],
            'finished %s UTC (%s logged)' % (p['pass_end'][:19], r['last_step']) if p.get('pass_end')
            else 'NOT FINISHED (no %s row yet; last row %s UTC)' % (r['last_step'], (p.get('last_row_at') or '')[:19]))

    p2, p3 = pass_in(p2_lo, p2_hi), pass_in(p3_lo, p3_hi)
    # a pass with no last-step row is RUNNING while it started less than 8 h ago (the longest pass measured
    # took 7.0 h); an older one died, or predates its last step (SP_SNAPSHOT_ENGINE_HEALTH was added in the
    # 2026-10-03 07:35 pass), and is listed only. An orchestrator job not DONE always counts as running.
    running = [p for p in passes if not p.get('pass_end') and now - ts(p['pass_start']) < dt.timedelta(hours=8)]
    stale = [p for p in passes if not p.get('pass_end') and p not in running]
    lines = [
        'now %s UTC, Los Angeles date %s (BigQuery clock)' % (now.strftime('%Y-%m-%d %H:%M:%S'), la),
        'orchestrator SP_ORCHESTRATE_DAILY_REFRESH: %s steps, first %s, last %s' % (r['n_steps'], r['first_step'], r['last_step']),
        'pass 2 of %s (first step 07:00-12:00 UTC): %s' % (a.date, fmt(p2)),
        'pass 3 of %s (first step 12:00-24:00 UTC): %s' % (a.date, fmt(p3)),
        'passes running (no %s row, started < 8 h ago): %s' % (
            r['last_step'], '; '.join(fmt(p) for p in running) or 'none'),
        'older passes with no %s row (not running: started > 8 h ago): %s' % (
            r['last_step'], '; '.join(fmt(p) for p in stale) or 'none'),
        'orchestrator jobs not DONE (INFORMATION_SCHEMA.JOBS_BY_PROJECT, last 36 h): %s' % (
            '; '.join('%s %s since %s' % (j['job_id'], j['state'], j['creation_time'][:19]) for j in jobs) or 'none'),
    ]
    for l in lines:
        print('  ' + l)
    reasons = []
    if r['first_step'] != a.first or r['last_step'] != a.last:
        reasons.append('the orchestrator no longer runs %s first and %s last (it runs %s .. %s): '
                       're-measure the pass pattern before trusting this guard'
                       % (a.first, a.last, r['first_step'], r['last_step']))
    if running:
        reasons.append('a pass is running (its first step is logged, its last step %s is not, and it '
                       'started less than 8 h ago): wait for it' % r['last_step'])
    if jobs:
        reasons.append('an orchestrator job is not DONE in JOBS_BY_PROJECT')
    if a.running_only:
        if reasons:
            for x in reasons:
                print('  REFUSE: ' + x)
            sys.exit(3)
        print('  OK: no pass is running')
        return
    if la != a.date:
        reasons.append('the Los Angeles date is %s, not %s: the deploy runs on LA %s only'
                       % (la, a.date, a.date))
    window, end = None, None
    if p2 and p2.get('pass_end') and ts(p2['pass_end']) <= now < prim_end:
        window, end = 'PRIMARY', prim_end
    elif p3 and p3.get('pass_end') and ts(p3['pass_end']) <= now < fb_end:
        window, end = 'FALLBACK', fb_end
    if window is None:
        def state(p):
            return ' (it has not started)' if not p else ' (it has not finished)'
        if now < prim_end:
            reasons.append('the primary window has not opened: it opens when pass 2 of %s (starts ~07:35 UTC) '
                           'has logged %s%s' % (a.date, r['last_step'], state(p2)))
        elif now < fb_end:
            reasons.append('the primary window closed at %s UTC; the fallback window opens when pass 3 of %s '
                           '(starts ~16:00 UTC) has logged %s%s' % (prim_end.strftime('%H:%M'), a.date,
                                                                   r['last_step'], state(p3)))
        else:
            reasons.append('both windows are closed (the fallback closed %s UTC): every trial-2 date and '
                           'trial 1\'s ARCHIVED date shift together before step 1 (plan Task 0, Task 8)'
                           % fb_end.strftime('%Y-%m-%d %H:%M'))
    elif a.need_minutes and (end - now).total_seconds() < a.need_minutes * 60:
        reasons.append('the %s window closes at %s UTC, %.0f min from now; this step needs %d min: '
                       'resume it in the next window' % (window.lower(), end.strftime('%Y-%m-%d %H:%M'),
                                                          (end - now).total_seconds() / 60, a.need_minutes))
    if reasons:
        for x in reasons:
            print('  REFUSE: ' + x)
        sys.exit(3)
    print('  OPEN: %s window, closes %s UTC (%.0f min left)' % (
        window.lower(), end.strftime('%Y-%m-%d %H:%M'), (end - now).total_seconds() / 60))


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('strip'); p.add_argument('file')
    p = sp.add_parser('xform'); p.add_argument('file')
    p.add_argument('--prefix'); p.add_argument('--pin'); p.add_argument('--quoted', action='store_true')
    p.add_argument('--k7'); p.add_argument('--create-or-replace', action='store_true')
    p.add_argument('--expect'); p.add_argument('--script', action='store_true')
    p = sp.add_parser('writes'); p.add_argument('file')
    p = sp.add_parser('body'); p.add_argument('file')
    p = sp.add_parser('same'); p.add_argument('a'); p.add_argument('b')
    p.add_argument('--label-a'); p.add_argument('--label-b'); p.add_argument('--max-lines', type=int, default=120)
    p = sp.add_parser('select'); p.add_argument('file'); p.add_argument('ids', nargs='+')
    sp.add_parser('rows')
    p = sp.add_parser('columns'); p.add_argument('file')
    sp.add_parser('bqcolumns')
    p = sp.add_parser('cte'); p.add_argument('file'); p.add_argument('name')
    p = sp.add_parser('block'); p.add_argument('file'); p.add_argument('start'); p.add_argument('end')
    p = sp.add_parser('guard'); p.add_argument('--date', default='2026-10-05')
    p.add_argument('--first', default='SP_SRC_ACC_PRODUCTS'); p.add_argument('--last', default='SP_SNAPSHOT_ENGINE_HEALTH')
    p.add_argument('--need-minutes', type=int, default=0); p.add_argument('--running-only', action='store_true')
    a = ap.parse_args()
    if a.cmd == 'strip':
        sys.stdout.write(strip_comment_lines(read(a.file)))
    else:
        globals()['cmd_' + a.cmd](a)


if __name__ == '__main__':
    main()
