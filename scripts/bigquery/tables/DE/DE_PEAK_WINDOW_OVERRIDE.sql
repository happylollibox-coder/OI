-- =============================================
-- DE_PEAK_WINDOW_OVERRIDE — the judged-window rule, as DATA
--
-- ORI'S RULE (2026-08-12), implemented v27.50:
--   "The algorithm should switch from 7 days to 3 days [in peak] UNLESS it has examined last
--    year's same peak and proved that 7 days is better than 3."
--
--   The BURDEN OF PROOF sits on the SLOWER window.
--     * Default in peak            = 3 days.
--     * Default off peak           = 7 days (unchanged, and NOT overridable here).
--     * A 7-day override is granted for an occurrence type ONLY where the SAME occurrence in a
--       prior year demonstrably produced BETTER DECISIONS at 7 than at 3.
--     * No evidence, thin evidence, ambiguous evidence or CONFLICTING evidence  ->  3 days.
--
-- WHY THIS IS A TABLE AND NOT A CASE EXPRESSION: the window is an empirical finding, not a
-- constant. Next year's re-measurement must update a ROW, not the engine SQL, and anyone
-- reading the row must be able to see the evidence that bought the window. Every column after
-- `w_days` exists to answer "why is this occurrence on this window?".
--
-- CONSUMED BY: V_PEAK_WINDOW_RULE (resolves today's occurrence -> w_days), which is read by
--              V_KEYWORD_LIFT (season / cap CTEs). Nothing else reads this table directly.
--
-- KEY: occurrence_type = V_SEASON_CONTEXT.context_label with the trailing _<year> stripped
--      ('BTS', 'XMAS_EARLY', 'XMAS_PEAK', 'VDAY', 'EASTER', 'MDAY', 'GRAD', 'FDAY', 'PRIME',
--       'HALLOWEEN', 'BF', 'CM').  One ACTIVE row per type; superseded measurements stay in the
--      table with is_active = FALSE so the audit trail survives a re-measurement.
--
-- HOW TO RE-MEASURE (SOP: architecture/PEAK_WINDOW_RULE.md §4):
--   1. Wait until the next occurrence of the type is CLOSED and settled
--      (V_SEASON_CONTEXT.occurrence_closed = TRUE, i.e. every day <= anchor-7).
--   2. Re-run the 3-vs-7 study over ALL prior occurrences of that type.
--   3. UPDATE the existing row to is_active = FALSE, INSERT the new verdict row.
--      NEVER edit a row in place — the point of the table is the history.
--
-- SAFETY: V_PEAK_WINDOW_RULE clamps w_days to [1, 28]. A row cannot make the engine judge on a
--         zero-day or year-long window by typo.
--
-- CREATE IF NOT EXISTS: never wipe rows on redeploy. The seed below deletes and re-inserts ONLY
-- the rows carrying this study's (measured_on, measured_by) stamp, so a redeploy is idempotent
-- and a human-entered row is never destroyed.
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PEAK_WINDOW_OVERRIDE`
(
  occurrence_type      STRING NOT NULL,   -- 'XMAS_PEAK', 'BTS', ... (context_label minus _<year>)
  w_days               INT64  NOT NULL,   -- judged window IN PEAK for this occurrence type (3 = default, 7 = proven override)
  is_active            BOOL   NOT NULL,   -- FALSE = superseded by a later measurement; kept for the audit trail
  evidence_verdict     STRING,            -- PROVEN_7 / NOT_PROVEN / CONFLICTING / NO_EVIDENCE
  evidence_occurrences STRING,            -- which prior occurrences were tested, and their known defects
  evidence_n           INT64,             -- simulated decisions scored across those occurrences
  evidence_metric      STRING,            -- the numbers that decided it (accuracy, dollar-skill, CIs, p-values)
  specs_granted_7      INT64,             -- robustness: specifications (of specs_total) in which 7 won
  specs_total          INT64,
  measured_on          DATE,              -- when the study was run
  measured_by          STRING,            -- which study produced this row
  remeasure_after      DATE,              -- re-run the study once the next occurrence of this type has closed + settled
  comment              STRING,            -- plain-language "why this window"
  updated_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- =============================================
-- SEED — verdicts of the 3-vs-7 study, 2026-08-12 (v27.50)
--
-- Scope of the study: 17 closed prior peak occurrences, 2024-09-05 .. 2026-06-29.
-- 34,688 SP decisions (occurrence x day x campaign x target) over 2,058 keyword-occurrences and
-- 524 occurrence-days, $234,461 of in-window spend; SB measured as a second arm (72,513
-- decisions, directional only — different grain from the live SB arm).
-- Method: each historical keyword-day deflated to what was VISIBLE that morning via the measured
-- V_ADS_SETTLE_CURVE accrual, integer counts thinned by seeded stochastic rounding; the engine's
-- own cut tree (class gates, wave veto, PARK, CUT_TO_BREAKEVEN) simulated at both windows and
-- scored against settled forward-7d GP-ROAS at >=20 forward clicks. Primary dollar metric = SKILL
-- (edge over a random policy spending the identical cut-mass), so mean reversion is controlled.
-- Holm-Bonferroni within family; clustered bootstrap by keyword (2,000 reps, seed 20260812).
-- Defense excluded. Launch families (Bunny, LolliBall) excluded. GP-ROAS = gross profit / spend.
--
-- 3 of 9 measured types earned a 7-day override: EASTER, XMAS_EARLY, XMAS_PEAK.
-- 6 stayed at the 3-day default: BTS, VDAY, MDAY, GRAD, FDAY, PRIME.
--
-- KNOWN CONFOUND, recorded here on purpose (SOP §5): every 7-grant traces to the engine's
-- clk_w >= 13 cut gate, which is 4.3 clicks/day over 3 days but only 1.9 over 7. On a MATCHED
-- population (both windows clear 13 clicks) or under a window-scaled gate (K3 = 6), ZERO types
-- grant 7. These rows are the honest answer to Ori's rule as asked, applied to the engine
-- EXACTLY AS DEPLOYED. If the click gate is ever scaled to the window, EVERY row here must be
-- re-measured, because the confound that produced the three 7s disappears.
-- =============================================

DELETE FROM `onyga-482313.OI.DE_PEAK_WINDOW_OVERRIDE`
WHERE measured_on = DATE '2026-08-12' AND measured_by = 'w_days 3-vs-7 study (v27.50)';

INSERT INTO `onyga-482313.OI.DE_PEAK_WINDOW_OVERRIDE`
  (occurrence_type, w_days, is_active, evidence_verdict, evidence_occurrences, evidence_n,
   evidence_metric, specs_granted_7, specs_total, measured_on, measured_by, remeasure_after, comment)
VALUES

-- ── 7-DAY OVERRIDES GRANTED (the burden of proof was discharged) ──────────────────────────────
('XMAS_PEAK', 7, TRUE, 'PROVEN_7',
 'XMAS_PEAK_2024 (2024-11-15..12-28, 44 days, $74,740 spend) + XMAS_PEAK_2025 (2025-11-15..12-28, 44 days, $167,235 spend). Two clean occurrences, the largest in the warehouse.',
 7074,
 'Dollar-skill $5,163 (3d) vs $8,584 (7d), delta -$3,421, clustered bootstrap CI [-4980,-2025]. BOTH occurrences individually verdict 7-BETTER with CIs excluding zero (2024 -$1,693 CI[-3193,-576]; 2025 -$1,697 CI[-2608,-887]). Accuracy 0.640/0.639 (3d) vs 0.646/0.642 (7d).',
 9, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2027-01-11',
 'Strongest case in the study: two full occurrences, both agreeing, dollars significant on each one separately. Black Friday and Cyber Monday are absorbed into this occurrence by V_SEASON_CONTEXT precedence (earliest boost_start wins), so they inherit the 7.'),

('EASTER', 7, TRUE, 'PROVEN_7',
 'EASTER_2025 (2025-03-03..04-23, 52 days, $55,961 spend) + EASTER_2026 (2026-02-18..04-10, 52 days, $49,529 spend).',
 7410,
 'The only type where BOTH metrics are significant and agree. Accuracy 0.572 (3d) vs 0.614 (7d), McNemar b=221/c=339, p_holm<0.001. Dollar-skill $1,863 vs $2,870, delta -$1,007, CI [-1945,-134].',
 10, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2027-04-14',
 'Most robust result: 7 wins in 10 of 10 specifications, on both accuracy and dollars. Easter is a long, slow-building occurrence (52 days) where a 3-day read is mostly noise.'),

('XMAS_EARLY', 7, TRUE, 'PROVEN_7',
 'XMAS_EARLY_2024 (2024-10-01..11-14, 45 days, $25,078 spend) + XMAS_EARLY_2025 (2025-10-01..11-14, 45 days, $46,202 spend).',
 5282,
 'Dollar-skill $24 (3d) vs $852 (7d), delta -$828, CI [-1822,-98] excludes zero. Accuracy 0.539 vs 0.561 (not significant). 2024 alone is 7-BETTER (-$367, CI [-756,-36]); 2025 alone is indistinguishable.',
 8, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2026-11-28',
 'Weakest of the three grants: dollars carry it, accuracy does not, and it fails on the campaign_id=-1-clean subset (that data-quality hole covers 18-32% of the 2024/2025 October rows) and at lambda_cut=0.10. Halloween nests entirely inside this window and is governed by it. Re-measure first when the gate confound is addressed.'),

-- ── NOT PROVEN — the 3-day default stands (rows exist to record WHY, and to be re-measured) ───
('BTS', 3, TRUE, 'NOT_PROVEN',
 'BTS_2025 (2025-08-01..09-14, 45 decision days) is the only usable prior. BTS_2024 exists only as a 10-day truncated stub (2024-09-05..09-14) because the ads feed starts 2024-09-05, mid-window — 386 decisions, all in the anchor phase; the August boost and peak phases predate the data entirely. Effectively ONE occurrence deep.',
 3561,
 'Pooled accuracy 0.562 (3d) vs 0.578 (7d), McNemar b=116/c=135, p_holm=0.768. Dollar-skill delta -$132 (nominally favours 7), CI [-447,+168] spans zero. The stub occurrence nominally favours 3 on b=13/c=1 — not leanable.',
 1, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2026-10-01',
 'THIN + AMBIGUOUS = 3. This is the live season (BTS_2026) and the reason the question was asked. One prior occurrence cannot separate a window effect from that one year demand shape, and 7 was granted in only 1 of 10 specifications. Under the rule the burden is not discharged, so BTS runs 3. Re-measure after BTS_2026 closes and settles (~2026-09-24) — that will be the second real occurrence.'),

('VDAY', 3, TRUE, 'NOT_PROVEN',
 'VDAY_2025 (2025-01-27..02-17, 22 days) + VDAY_2026 (2026-01-27..02-17, 22 days).',
 2018,
 'Dollar-skill delta -$137, CI [-584,+303] spans zero. Accuracy 0.580 vs 0.617, p_holm=0.058 — misses the bar. VDAY_2026 alone reads 7-BETTER but its CI [-553,+210] spans zero.',
 2, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2027-03-03',
 'AMBIGUOUS = 3. Nominally leans 7 on both metrics but nothing clears significance, and 7 was granted in only 2 of 10 specifications. Close enough that VDAY_2027 could flip it — re-measure.'),

('MDAY', 3, TRUE, 'NOT_PROVEN',
 'MDAY_2025 (2025-04-24..05-14, 21 days) + MDAY_2026 (2026-04-12..05-13, 32 days).',
 3123,
 'Dollar-skill delta -$67, CI [-575,+448] spans zero. Accuracy 0.521 vs 0.552, p_holm=0.196. The two occurrences disagree in sign: 2025 favours 3 (+$202), 2026 favours 7 (-$337), neither significant.',
 3, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2027-05-26',
 'AMBIGUOUS = 3. The two occurrences point opposite ways. Also the one type whose verdict moves under the alternative settle curve (Curve B) — and it moves toward 3.'),

('GRAD', 3, TRUE, 'CONFLICTING',
 'GRAD_2025 (2025-05-15..06-20, 37 days) + GRAD_2026 (2026-05-14..06-20, 38 days). FDAY_2025 is absorbed into GRAD_2025 by V_SEASON_CONTEXT precedence.',
 4717,
 'Metrics CONTRADICT. Accuracy significantly favours 7 (0.532 vs 0.568, McNemar b=185/c=253, p_holm=0.011). Dollar-skill favours 3 (+$54, CI [-467,+556]). Reaction lag favours 3 decisively (3-day faster on 29 regime turns vs 8 for 7-day, p_holm=0.006).',
 0, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2027-07-04',
 'CONFLICT = 3, and this is the instructive case for the rule. 7 is more often RIGHT here but 3 is more often PROFITABLE and reacts a week sooner. Under the rule conflicting evidence is ambiguous evidence, and ambiguous means 3. 7 was granted in 0 of 10 specifications.'),

('PRIME', 3, TRUE, 'NOT_PROVEN',
 'PRIME_2025 (2025-07-08..07-14, 7 days) + PRIME_2026 (2026-06-25..06-29, 5 days). Both occurrences are SHORTER than the 7-day window under test, so a 7-day read necessarily reaches outside the event and measures pre-event traffic.',
 1173,
 'Dollar-skill favours 3 (+$150, CI [-56,+363]). Accuracy favours 7 (0.572 vs 0.608) but p_holm=0.255, not significant. Both occurrences individually favour 3 on dollars.',
 0, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2027-08-01',
 'STRUCTURALLY UNTESTABLE at 7 = 3. A window longer than the occurrence is not a measurement of the occurrence. 7 was granted in 0 of 10 specifications. Prime should stay at 3 permanently unless the event window itself lengthens.'),

('FDAY', 3, TRUE, 'NO_EVIDENCE',
 'FDAY_2026 (2026-06-21..06-24, 4 days, 330 decisions) is the ENTIRE evidence base. FDAY_2025 does not exist as an occurrence — it is fully absorbed by GRAD_2025 under the V_SEASON_CONTEXT earliest-boost_start precedence.',
 330,
 'Both metrics favour 3 (dollar-skill delta +$13; accuracy 0.535 vs 0.512), neither significant. n is far too small to test anything.',
 0, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2027-07-07',
 'NO EVIDENCE = 3. One 4-day occurrence is not a prior year. Note FDAY 2027 is again inside the GRAD window (boost 2027-05-23 vs GRAD 2027-04-20), so precedence will absorb it again and this row may never acquire a second occurrence.'),

-- ── ABSORBED BY PRECEDENCE — documented so a reader does not have to rediscover it ────────────
('HALLOWEEN', 3, TRUE, 'NO_EVIDENCE',
 'No occurrence exists. Halloween is category seasonal, which v27.49 admitted to the engines in_peak, but its window (Oct 10 .. holiday_date+3 = Nov 3) nests ENTIRELY inside the Christmas window (Oct 1 .. Dec 28), so under earliest-boost_start precedence it never owns a date and adds ZERO unique peak days.',
 0,
 'Not measurable — no distinct occurrence to measure. V_SEASON_CONTEXT does not even carry a Halloween row.',
 0, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2026-11-28',
 'INERT. In practice Halloween dates resolve to XMAS_EARLY and inherit its 7. This row only fires if the Christmas row is ever removed or its boost_start pushed past Oct 10, in which case the safe default applies.'),

('BF', 3, TRUE, 'NO_EVIDENCE',
 'No occurrence exists. the Black Friday window (boost mid-Oct) starts AFTER the Christmas window (Oct 1), so precedence absorbs every Black Friday day into XMAS_EARLY / XMAS_PEAK.',
 0,
 'Not measurable — no distinct occurrence to measure.',
 0, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2027-01-11',
 'INERT. Black Friday days are judged as XMAS_PEAK (7 days). This row is the safe default if precedence ever changes.'),

('CM', 3, TRUE, 'NO_EVIDENCE',
 'No occurrence exists. the Cyber Monday window starts after the Christmas window, so precedence absorbs it into XMAS_EARLY / XMAS_PEAK.',
 0,
 'Not measurable — no distinct occurrence to measure.',
 0, 10, DATE '2026-08-12', 'w_days 3-vs-7 study (v27.50)', DATE '2027-01-11',
 'INERT. Cyber Monday days are judged as XMAS_PEAK (7 days). This row is the safe default if precedence ever changes.');
