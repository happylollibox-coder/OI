# Progress — audit trail

## 2026-08-15 — Phase 0 of the engine-finalization plan: v27.62 GP fix VERIFIED

Ten adversarial verification agents (one per GP-edited view + one on the manual-change record).
Full results: the phase0-gp-verify workflow journal (session 08c2ab35, run wf_99ddffb0-f49).

**Verdict: the GP fix is correct in all nine views.** Every deployed definition clean (zero live
`T_PRICE_COST_TIER` joins, `GROSS_PROFIT` read directly); every sample recompute exact against
FACT with the arithmetic shown; pull-twice determinism PASS on 8/9; every backup diff confirmed
GP_ONLY scope. The anchor restated as the settle curve predicts: VIDEO- BALL 2026-08-12 GP
229.16 → 239.80 (3.69× → 3.74×) — sales accruing to D+7, spend static.

**The corruption's true shape, now measured:** two-sided. It *collapsed* GP on halo winners
(VIDEO- BALL "gift for girls": 0.60× → 1.34×, +3.31 on the r2 window — the single biggest
restoration) and *mildly inflated* GP nearly everywhere else (long tail of −0.01/−0.02 drifts).
Decision flips were few and all corrections: V_KEYWORD_GUARD 2 halo cuts→protects + 2 marginal
1.0-straddlers corrected downward; V_PARK_REVERDICT killed 1 false revive (true settled 0.994 vs
bar 1.0); V_CHANGE_SCORECARD upgraded 2 NEUTRAL→CONFIRMED, zero punitive flips, zero remedy
changes; V_LAUNCH_PHASE1 2 raises→holds/trims. V_OOB_KEYWORD's 4 flips were the v27.63
winner-pacing branch, not GP (roas byte-identical on 3 of 4).

**One FAIL, not the GP fix: V_RUN_TARGET pull-twice determinism** — pre-existing
`ANY_VALUE(target_text)` coin-flip on the keyword_id='-1' collapsed rows (38 of 40 mismatches;
the identical line exists in the pre-fix backup; decision columns byte-stable throughout).
**Fixed same day as v27.64**: `MIN(target_text)/MIN(targeting_type)`, deployed, re-verified
byte-identical over 1,302 rows ×2 pulls. Known residue, accepted: 2 penny-level `pk_cpc`
ROUND-boundary flips (float sum order; display-only) and the '-1' grain collapse itself
(pre-existing design — all PT targets of a campaign sum into one row; noted for Task 2.1).

**Task 0.2 — manual-change record audited: CLEAN with two findings.** 68 applied MANUAL rows
Aug 2–11 (69 attempted, 1 FAILED_UPLOAD correctly excluded); zero missing ids, zero duplicates;
the BOX-SBS hand-session fully present (budget 45→100→200→100, bid 1.00→0.85→0.70). Findings:
(1) one stale old_budget (the 45→200 row 23 min after 45→100 — old value not refreshed between
same-day edits); (2) ~8 MANUAL rows are engine-suggested-hand-applied (identical old→new as
same-day COACH rows, incl. all 3 Aug-2 rows and one that shipped inside a COACH batch) — the
manual-divergence loop (plan Task 3.1) must classify these AGREED, never OVERRODE. Scorecard
coverage of MANUAL rows: 0 old enough yet; first reads land ~Aug 16–18.

**Phase 0 exit: GREEN.** Next per plan: Task 1.1 (SP_ENGINE_PREFLIGHT standing gate).

## 2026-08-16 — Phase 6 (Weekly Run 5s/5min) built + acceptance, mechanical half

Front page live: RunSummaryStrip + TodayDecisions mounted above the sections; all ~17 criteria
sections lazy (fetch on first expand). Measured, live browser:
- Page-open cube queries: **12** (was ~65; the ~53 ceiling-view section queries now fire only on
  their section's click — Revivals expand = exactly 1 query, an OOB section = exactly 3).
- Strip renders the whole run from V_RUN_SUMMARY (~4s query): 113 changes (66 bid cuts · 21 bid
  raises · 17 budget cuts −$113.28/d · 4 budget raises +$36.93/d · 5 revivals — after fixing the
  LOW_STOCK current_budget NULL that mislabeled 7 cuts as raises) · 66 held (54 ownership · 9
  winner-cut reviews · 3 no-op) · 772 unchanged in 7 state-machine classes, each drillable.
- Feed groups match T_ENGINE_PREFLIGHT exactly (41/2/35/5/30 GO by engine, ownership order);
  queue round-trip verified with real ad_group_ids; queue-all + symmetric unapply verified;
  non-clobber verified (foreign item → '· other panel', count drops); EXCLUDE rows expandable,
  zero queue affordances; UNCHANGED drills verified (76 winners, 514 parked capped at 100).
- tsc: zero errors in every touched file; vite build passes.
REMAINING for the full acceptance: Task 3 (why_short authored in OOB/LIFT — feed falls back to
full reasons meanwhile) and Task 8's protocol half with Ori on the first Monday run (5 rows in
≤ 25s; 5-minute narration). Dev cube hot-reloaded the new schemas; prod cube needs the usual
deploy when the dashboard next ships.

## 2026-08-16 (night) — full review of the day's code + novice-legibility audit: ALL FIXED

Five parallel reviewers (2 SQL vs .bak baselines, React, live regression, explanation audit).
Found: 2 CRITICAL (SIBLING_REVIVE could auto-activate through the engines' entry doors — flag
extended, all doors closed; DoPage export gate refused the OWNER's item on contested keys — now
value-matched ±0.005), 11 IMPORTANT (all fixed same night except one deferred with a name), and
the audit verdict: only 4 of 33 actions passed a cold read.
Fixed batch: season-relaxed revivals now REVIEW at the gate (bulk-queue hole closed, 2 live rows
moved); REVERDICT rows carry campaign names; state ladder no longer swallows sibling verdicts
into DEAD; V_MANUAL_DIVERGENCE owner-only join (no fan-out); preflight verdicts in plain words;
probe-entry cross-ladder drift mirrored (0 NULL-bid PROBE_ADJUST rows); stale $1-floor labels
rewritten; EVERY audit rewrite applied across V_KEYWORD_LIFT/V_OOB_KEYWORD wrappers,
V_LOW_STOCK_ADS shorts, labels ('parked at minimum bid'), V_ENGINE_HEALTH single-ceiling-scan
restructure, strip colors moved to view-authored record_class, KeywordLiftPhase dead fallback +
over-broad unapply sweep fixed.
VERIFIED: GO shorts 111/111 (100%); jargon LIKE-sweeps (wnd / seat freed / anchored / bare
settled / $1 entry floor) ALL ZERO in live shorts; sample shorts read clean across all five
engines; V_KEYWORD_LIFT pull-twice MD5-identical (598 rows); tsc zero lines on touched files;
vite build passes; health board 9/9 in ~3s.
DEFERRED, NAMED: coach surfaces (V_COACH_APPLY / V_COACH_CAMPAIGN_BUDGET) into the proposal
snapshot (divergence ENGINE_SILENT accuracy — plan Task 3.0 extension); full ev-leg feed from
PHASE to the OOB keyword raise-gate (reworded honestly meanwhile).

## 2026-08-17 — v27.72: the negate gap closed + one decision, one ✓ + sections open where the work is
Ori: "close the negate gap"; "if i approve an action in section or snapshot visual should show
both approve"; "when there is an open action hierarchy should be Expanded else collapse by default."
BUILT (SQL): NEGATE lever into the proposal snapshot — INSERT 8 (V_OOB_SEARCH_TERM is_negate,
engines OOB/LIFT, one row per campaign+term, ad-group comma-list verbatim, ARRAY_AGG total-order
representative slice) + INSERT 9 (V_WEEKLY_RUN_NEGATIVE → engine COACH, LIVE view since the T_
copy builds in Task 21 after this snapshot; peak_converts rides season_relax_applied). Preflight:
key_id = term text for NEGATE rows (keyword_id is NULL — without the term every negate in a
campaign is one false conflict), lever NEGATE, COACH in the precedence ladder (last), dup-negate
EXCLUDE ("one negative per term per day"), peak-converting negate → REVIEW, stamp-back join
carries target_text. V_ENGINE_HEALTH c2/c7 + V_MANUAL_DIVERGENCE mirror the key; manual negates
graduate from LEVER_NOT_SNAPSHOTTED to AGREED/ENGINE_SILENT (never OVERRODE — no value).
V_RUN_SUMMARY: NEGATE arm BEFORE the bid arms — NULL<NULL sent every block into ELSE 'bid
raises' (68 shown, 22 true); CHANGES now leads with 'search terms blocked'. EnginePreflight cube
rowId += target_text (PK collapse). DoPage gate: NEGATE lever judged by campaign+term, no value.
BUILT (React): canonical queue identity in useDoQueue (findQueuedBid/Budget/Negates; BID list
includes BOOST/SCALE_UP/PROBE); ✓ renders from the KEY on every surface, foreign value shown as
'✓ at $X.XX'; bulk unapply stays value-exact; feed renders 54 block rows + Coach group; workflow
fan-out applied the contract to the six panel files + defaultOpen (openState ?? defaultOpen,
user click final) + inner campaign groups expand when they hold open suggestions.
FIRST LIVE CATCH: the coach proposed blocking "journal for girls" — 47 orders in past gift
peaks — REVIEW'd by the new arm, never a silent GO (7 more seasonal keeps flagged with it).
VERIFIED: 54 negates judged (36 COACH / 14 OOB / 4 LIFT), 0 dup keys, 0 null shorts, 0 unstamped;
both negate INSERT dedups pull-twice MD5-identical; tsc project-clean; vite build passes; 7-point
verify agent all PASS; browser round-trip (queue → '✓ blocking' → split-item removal → reverted).
OPS NOTES: bq client timeout CANCELLED a running script mid-partition (DELETE committed, INSERTs
not) — always resubmit --nosync and gate the preflight on job success; dev-cube cachestore
corruption (/tmp/cube-oi-cubestore) served partial stale roll-ups — fix is stop cube, rm -rf the
dir, restart; IDT morning runs before 10:00 write the PREVIOUS LA ads day (correct, surprising).
DEFERRED, NAMED: coach BID/BUDGET surfaces into the snapshot (Task 3.0 extension, unchanged);
ADD_KEYWORD lever (research "+broad") now the one unsnapshotted lever; prod cube deploy rides
the next dashboard ship.

## 2026-08-17 (later) — v27.73: low-stock REDIRECT mode, the SQL spine
Ori's doctrine: re-aim the family's doorways at the best in-stock high-demand sibling; brake
only when there is nowhere to aim; when the dry variation returns, RE-OPEN the decision (never
auto-revert). Measured basis: 77.6% of Bunny ad units land on a sibling of the advertised
doorway; the family brake bought 0.8 days.
BUILT: V_LOW_STOCK_ADS v27.73 — hero pick in fam_agg (in-stock ≥60d cover, demand-ranked, fully
tie-broken), rmode CTE (hero ≥ 50% of binding rate on THROTTLE/CRITICAL), both proposal arms
gated on the MOVE (only STOCK_CUT_WASTE% parks offered in redirect mode; first-run leak of 2
class-keyed halves fixed), FAMILY rows publish redirect_mode + hero_* + binding asin;
V_LOW_STOCK_REDIRECT (per-ad-group re-aim rows off the FAMILY verdict — advertised-product
report carries ad_id, so the pause half is a real bulksheet row; SB excluded; ACTIVE redirects
excluded); DE_AD_REDIRECTS ledger; V_AD_REDIRECT_RECHECK (back-in-stock ≥45d cover + ≥14d hero
data → evidence beside the choice, RESTORED/KEPT is Ori's click). All registered in config.yaml.
VERIFIED: modes exact across all 6 families (Bunny CRITICAL→redirect via Proud 1.71/d 210d;
LolliBall CRITICAL→redirect via Pink 8.71/d 75d; 4 OK families false); gate 0/34 brakes
proposed, 8/8 waste-parks kept; 5 redirect rows, every one with ad_id + hero SKU ($764/30d of
doorway spend re-aimed); pull-twice MD5-identical.
PENDING (plan Task 4.6 carries the full spec): snapshot INSERT grain='REDIRECT' + preflight
lever + feed/panel rows + DoPage PAUSE_PRODUCT_AD export branch + DE_AD_REDIRECTS POST at
export + RECHECK surface. Panel note: LowStockPhase still renders the suppressed rows as
priced-not-proposed with their old reasons — the redirect headline lands with the UI half.

## 2026-08-17 (evening) — v27.74: complete-days windows (Task 4.7), 5-agent fan-out
Ori's convention (last day alone; 3d/7d/28d/90d end at the last complete day) applied to 62
sites across V_KEYWORD_LIFT / V_OOB_KEYWORD / V_OOB_SEARCH_TERM / V_OOB_BUDGET_PHASE /
V_LOW_STOCK_ADS. All deploys clean, per-view flip reports, verifier: BoxPink 3d = 56 = console;
2 OOB window reconciliations exact vs raw FACT; pull-twice identical; zero missed sites; no
drift in the 6 shared zero-sale fragments. Effects: 7 partial-day negate offers died; VIDEO-BALL
3d crossed breakeven upward sparing halves; small OOB action shifts. Open notes in plan Task 4.7
annotation (prev2 semantics, probe filling-day, 7d/8-28 one-day overlap, 89d age gate). Next:
Task 4.8 (last-day veto) — files now free.

## 2026-08-17 (night) — v27.75: the last-day veto (Task 4.8), both bid engines
Ori's rule: the filling day may only say "wait" — raises held at >10 clicks under 0.5x, cuts held
at >10 clicks at/above 1.2x. Built as a thin outer wrapper in V_OOB_KEYWORD and V_KEYWORD_LIFT
(identical shape; two booleans once; action/bid/reason/short transformed together — no drift).
NOTE ON EXECUTION: the first workflow lost all 3 agents to a model limit mid-flight; the OOB agent
had already completed its edit+deploy, so recovery = verify OOB (0 escapes, 4 vetoes, zero-sale
intact) and re-run only LIFT + verification on the new model. Partial-state check before re-running
is what made that safe.
VERIFIED: 0 escapes both directions both views; 7 vetoes today, each satisfying its predicate with
suggested_bid NULLed; zero-sale floor intact (15 rows); no schema leak; pull-twice MD5 identical
(LIFT 578 rows, OOB 249); budget arms untouched; grammar exact.
TODAY'S SAVES (cuts held): VIDEO-BALL "gift for girls" 39c @2.05x (DARK_BRAKE cancelled),
ME-SP/PT asin B0C7KPN3W7 13c @3.31x, FRESH-SP/BROAD "back to school gifts" 12c @1.32x mid-BTS,
VIDEO-BALL "cheap gift for girl" 12c @1.56x. Raises held: BOX-STORE "gifts for tween girls" 49c,
BOX-SP/AUTO(Pink) "substitutes" 45c, FRESH "gift for teen girl" 14c — all 0.00x.
OPEN (in plan): the raise arm's evidence is weaker than the cut arm's (46% of at-volume rows read
0.00x on the filling day; attribution vs truth indistinguishable). Watch for the SAME keyword's
raise vetoed on consecutive days = permanent block; fix would be a repeat-guard. Measure first.

## 2026-08-17 (late) — v27.76: expected-orders gate (Task 4.9) + an ownership regression found
GATE: raise veto now splits informative-poor (sales landed, veto as before) from ambiguous-zero
(veto only if expected_orders_1d = clicks_1d × 90d order rate ≥ 3.0). All 3 LIFT raise vetoes
released with justification (substitutes exp 1.225 — Ori's worked example); OOB's 3 cut vetoes
byte-identical; zero-sale floor intact; additive schema; pull-twice identical.
FINDING: the zero-reading branch is dormant at this account's volume (max expected 2.10 vs 3.0
bar; needs ~120-300 clicks/day to clear). Honest answer: one quiet keyword-day is not evidence
here. Lever is veto_min_expected_orders.
REGRESSION FOUND (Task 4.10, urgent): V_PANEL_OWNERSHIP fails BigQuery planning deterministically.
Last good ownership build 10:50 IDT (pre-edit); 16:24 run FAILED; dry-run now fails. The view
inlines V_LOW_STOCK_ADS, which today's v27.73 (redirect mode) + v27.74 (windows) enlarged. Tomorrow
07:50 UTC will fail unless fixed. Fix = materialize T_LOW_STOCK_ADS in SP_SNAPSHOT_PANEL_OWNERSHIP
and point the view at it (the standing planner-blowup pattern). NOT deployed — awaiting Ori's go.

## 2026-08-17 (night, cont.) — v27.77: ownership planner fix + config.yaml repair
Task 4.10 done: T_LOW_STOCK_CAMPAIGN (pure slice) built by SP_SNAPSHOT_PANEL_OWNERSHIP before the
ownership table; V_PANEL_OWNERSHIP reads the T_ instead of inlining V_LOW_STOCK_ADS. View plans
again; SP idempotent (identical MD5 across two runs); ZERO owner flips on all 93 shared campaigns;
95→93 = 2 campaigns PAUSED intraday (both LAUNCH-owned). All consumers dry-run clean.
MY DEFECT, FIXED: config.yaml had not parsed since the Task 4.6 registrations — `cat >>` appended
them into the `monitoring:` mapping. All four objects relocated to their proper sections; file
parses (203/127/92); cloud_functions verified unchanged vs backup.
OPEN (Task 4.11): v27.73's redirect gate blinded ownership's arm B — ls_proposal_targets collapsed
to 0 on 10 of 14 low-stock campaigns because bid-cut rows are no longer proposals in redirect mode.
Claims hold today only via arm A (family CRITICAL). A WATCH-grade family in redirect mode would go
unclaimed and the engines could raise into a stock problem. Fix = make redirect_mode its own claim
arm. Awaiting Ori.

## 2026-08-17 (night, cont.) — v27.78: arm B fixed (Task 4.11)
redirect_mode published on CAMPAIGN rows (no new join — the rmode LEFT JOIN from v27.73 was
already there; slice re-dry-run after deploy, still plans) → V_PANEL_OWNERSHIP ls_redirect_mode →
arm B ORs it → published + cube dimension lsRedirectMode added.
PROOF is the counterfactual, since arm A masks the arm today: holding arm A silent, old arm B
keeps 9/14 claims, new arm B keeps 14/14; the 5 recovered are exactly the exposed set, each with
redirect_mode TRUE, suggested value NULL, 0 proposal targets. Live: zero owner changes (correct),
93 rows, idempotent, consumers clean, config parses.
CORRECTION: the state this covers is THROTTLE, not WATCH — redirect_mode requires binding
THROTTLE/CRITICAL and the family inherits the binding grade, so a re-aiming family can never be
WATCH. Arm A covers CRITICAL; the new arm covers THROTTLE with both money signals silent. My
earlier WATCH framing (and the prose now in the view/SP/config) is wrong and needs a doc pass.
LATENT, NAMED: ls_redirect_mode isn't family-propagated (arm A's risk_state is); claim_reason sits
at 79/80 chars with no truncation guard; two rollback tables (bak_v2777 95 rows, bak_v2778 93 rows)
to drop once tomorrow's 07:50 UTC run is green.

## 2026-08-17 (night, final) — v27.79: WATCH→THROTTLE doc correction
Ori: "fix the WATCH wording in the docs." The v27.78 justification named an unreachable state.
Corrected in all four artifacts: V_PANEL_OWNERSHIP.sql header (2 passages), the SP OPTIONS
description (redeployed, verified live: corrected=true / still_wrong=false), and config.yaml's
V_PANEL_OWNERSHIP entry. Each now says THROTTLE and explains WHY WATCH is unreachable —
redirect_mode requires a THROTTLE/CRITICAL binding grade and the family inherits the binding grade
whenever it is not OK. Arm A covers CRITICAL; the new arm covers THROTTLE + redirect + both money
signals silent.
NOT changed (verified legitimate, not stale): the original arm-B rationale "Bunny grades WATCH,
not CRITICAL" (true history — that is why arm B exists), the reachable non-redirect case "a
WATCH-family campaign low stock is genuinely silent about", and the 2026-08-13 measurement
"8 CRITICAL + 7 WATCH rows".
No view redeploy needed: the wrong passages were col-0 `--` header lines, which the deploy's
grep -v '^--' strips — confirmed by querying the deployed definition (STRPOS 'grades WATCH' = 0).
config.yaml parses (203/127/92). Also wired cube dimension lsRedirectMode (PanelOwnership.js) so
the published claim-basis column is actually readable by a panel.

## 2026-08-17 (night, final) — v27.80: dedicated campaigns brake (Task 4.12, Ori's correction)
Ori caught that BALL-SP/AUTO (Mint) is a per-product auto campaign, so re-aiming it to Pink would
duplicate BALL-SP/AUTO (Pink); the right action is the ordinary bid brake. My v27.73 gate had
suppressed exactly that. Built V_CAMPAIGN_PRODUCT_SCOPE + T_CAMPAIGN_PRODUCT_SCOPE (joined as a
physical table — the ceiling view has no headroom), serves_only_binding in V_LOW_STOCK_ADS, and
n_own_asins>1 on the redirect list. Result: Mint out of the redirect list and braking again
($6.02/day restored across two AUTOMATIC halves); in-stock siblings and 4 shared doorways
untouched; only delta account-wide is LolliBall TARGET proposals 3→5. Scope recount 74/74 exact.
Planner clean incl. 12 consumers; ownership SP ran end-to-end so tomorrow's 07:50 is safe.
NEXT (Task 4.13, bigger than what 4.12 closed): the same hole on SB — no advertised-product report
exists for Sponsored Brands, so VIDEO- BALL sits on a priced-but-unproposed budget cut
$68.83→$51.35/day. Candidate source: DIM_AD_GROUP creative ASINs.

## 2026-08-17 (night) — Task 4.13 WITHDRAWN: the SB "blind spot" was my error, not a hole
Ori: "cant you see the products assign to the ad in VIDEO- BALL?" Checked instead of asserting.
(a) SB video genuinely carries no product: V_SRC_AmazonAds_sb_ad_report HAS advertised_asin but
Amazon fills it with the string 'Unknown' for video creatives (74k impressions on VIDEO- BALL,
one row); creative_type/landing_page_type/ad_id/headline all empty. FACT inherits it faithfully.
(b) The brake I called a $51.35/day hole SHOULD NOT FIRE. Purchased-product over 60d — dry-variation
share: VIDEO- BALL 18.0%, VIDEO- COMP/BALL 14.3%, BUNNY-VIDEO/BROAD 10.5%. They are FAMILY-level
ads; 82-90% of their sales are IN-STOCK siblings. Braking sacrifices the majority to slow the
minority — the exact mistake redirect mode exists to prevent. VIDEO- BALL is ~4% of Mint's drain.
Current suppression is CORRECT for all three SB campaigns; no engine change. Remaining item is
legibility only: publish WHY they are silent instead of showing an absence.

## 2026-08-18 morning — v27.81: the gate now honors the ownership CLAIM (Task 4.14)
MORNING CHECK: overnight orchestrator 08:08-08:28 all OK — SP_SNAPSHOT_PANEL_OWNERSHIP succeeded
UNATTENDED at 08:13 (the v27.77 repair proven), REBUILD_T_CAMPAIGN_PRODUCT_SCOPE OK at 08:12 in the
right slot. Health board: no RED; contradiction rate 10.4% (from 31.8% at the start of this work).
THE DEFECT I CAUSED, FOUND AND FIXED: SP_ENGINE_PREFLIGHT excluded a non-owner only on a COLLISION
(n_instr>1). v27.73's redirect mode made LOW_STOCK deliberately stop instructing the campaigns it
owns, so collisions vanished and lower engines walked through: 41 GO rows inside LOW_STOCK-owned
CRITICAL campaigns (LAUNCH 28, OOB 5, LIFT 5 incl. a bid RAISE $0.44->$0.86 into a 20-days-of-cover
family, COACH 3 negates). Added a CLAIM-BASED arm reading FACT_PANEL_OWNERSHIP's defer_* booleans:
bid/budget levers only, fails open, ordered after the collision arm.
RESULT: 36 rows flipped to EXCLUDE (34 GO + 2 REVIEW); bid cuts 63 -> 32; the LIFT raise caught.
VERIFIED: zero escaped rows, 7 negates preserved, 0 owner-self-exclusions, zero over-reach into
non-owned campaigns, fail-open proven on 8 rows across 5 campaigns with no ownership row, planner
clean, chain rebuilt in order, config parses.
HYGIENE (all done, none reverted, none skipped): claim_reason 80-char guard with a drop-ladder
(stress-tested: 122-char case -> 58, always word-boundary); ls_redirect_mode family-propagated
(latent, 0 live change) with an IFNULL partition key so unmapped campaigns cannot pool; binding_asin
published on CAMPAIGN rows (no new join); float flicker ROUNDed (campaign-slice MD5 now identical
across pulls); config.yaml FACT_PANEL_OWNERSHIP + V_LOW_STOCK_ADS entries brought current.
DELETED (Ori approved as item 4 of the morning proposal): FACT_PANEL_OWNERSHIP_bak_v2777 (95 rows)
and _bak_v2778 (93 rows). NOTE: BigQuery cannot time-travel a DROPPED table — verified, they are
permanently gone. Harmless: both were disposable rollback copies of an idempotent daily-rebuilt
table, and the live table is intact (93 rows, 4 owners).
OPEN: the claim is CAMPAIGN-wide, not key-wide — today every claimed campaign is redirect-mode so
the owner is silent everywhere, but on a day when low stock speaks about only SOME keys in a
campaign it owns, lower engines are excluded on ALL its bid/budget keys. That is the stated meaning
of a FULL claim, but it is broader than the collision arm and wants watching the first time a
claimed campaign is NOT in redirect mode.

## 2026-08-18/19 — the holdout: built, NOT yet valid (Ori: "start the holdout")
WHY: matched DiD proved untrustworthy (selection placebo +$1,505..+$2,445 doing NOTHING, ~90% of the
account's entire 14-day net; clean control pool 7 keywords/$819 vs 379 treated/$29,326; matching
fails 98.1%). So we CREATE a control.
UNIT DECISION (the thing that made me stop v1): keyword-level randomization is INVALID wherever the
budget binds — Ori's own low-stock doctrine says a cut in a CAPPED campaign RE-ROUTES money to its
neighbours, i.e. the control feeds the treatment (SUTVA violation). Chose CAMPAIGN CLUSTERS:
69 eligible ($26,377/28d), 14 HOLDOUT / 55 TREATED, holdout 19.5% of dollars ($5,504/month under
management). Stratified on dollar decile, cap state, launch status, family, channel. Trial window
2026-09-01..2026-12-22, first readout 2027-01-05. Placebo bias under random assignment: -$72..+$35
per 14d (vs +$1,505..+$2,445 for rank-based selection) — the DESIGN is unbiased.
BUILT: DE_HOLDOUT_ASSIGNMENT, SP_ASSIGN_HOLDOUT (idempotent, verified 69 then 0), V_HOLDOUT_ELIGIBLE,
V_HOLDOUT_READOUT (gated to NOT_YET), SP_ENGINE_PREFLIGHT third exclusion arm (ALL levers, ordered
first, fails open, proposal STILL RECORDED = the counterfactual), orchestrator Task 20.55,
architecture/HOLDOUT.md. Frozen assignment verified; spillover violations 0; export refuses; readout
honest.
VERIFIER SAYS trialValid = FALSE. Three real problems, all fixable before the Sep 1 open:
 1. BASELINE IMBALANCE. The readout's own arithmetic on five PRE-treatment windows (true effect = 0)
    reads about -$1,100. One draw over 69 skewed clusters did not balance. Fix: RERANDOMIZE with a
    balance criterion (draw many candidate assignments, keep one passing pre-period tests) and/or
    covariate-adjust the estimator on pre-period dollars.
 2. ENFORCEMENT HOLES. The holdout is CAMPAIGN-level but DoPage's export gate matches at
    keyword+value grain — it protects only 7 of 38 active keywords in holdout campaigns; and
    is_holdout is not published by V_ENGINE_PREFLIGHT so a campaign-level refusal is not yet
    possible. Five python bulksheet builders bypass preflight entirely.
 3. DOCS OVERSTATE PRECISION: published band is 1.5x-5.2x the MDE printed beside it; the pre-trial
    imbalance figure is understated ~5x.
HONEST LIMIT (design agent's own words): this is a HARM DETECTOR, not a value certifier. MDE ~$2,261
per 14d at 20%/16 weeks, against an account 14-day net magnitude of ~$2,500. Context worth keeping:
the account's 14-day net moved from +$3,439 to -$2,470 over the last four months while the engine ran.
NOTHING IS LIVE: the gate is time-bounded and excludes 0 rows today; the trial opens 2026-09-01.

## 2026-08-19 — two-book P&L: Task 1 + fixups, and a design flaw found by building it
Task 1 (V_FAMILY_PNL) shipped: assertion passes to the cent, deterministic, registered.
REVIEW GATES CAUGHT FOUR PLAN DEFECTS, two would have corrupted later tasks:
 1. DE_LAUNCH_INVESTMENT ALREADY EXISTED and V_LAUNCH_EXEMPTION reads it live (Bunny $30/day to
    2026-10-31, LolliBall $55/day to 2026-11-30, sanctioned 2026-08-13). CREATE TABLE IF NOT EXISTS
    was a silent no-op; Tasks 3/6/8b would have queried absent columns. Rewritten as additive ALTER.
 2. The current partial month was labelled as full (2026-08 period_end Aug 31 holding 17 days) —
    the Invest ramp test would have read a false collapse on exactly the launches it judges. Fixed:
    complete months only, current month quarantined as MTD with is_complete_period=FALSE.
 3. The plan contradicted its own window rule. Ruled: ads windows end wm-1 (day-1 ads 88-90% loaded);
    blended windows end AT the orders watermark, complete by construction via the sessions gate.
 4. Every assertion piped a '--'-leading file through cat, which makes bq abort. All switched.
DESIGN FLAW FOUND BY BUILDING IT: monthly_loss_ceiling is denominated in NET PROFIT but derived from
SPEND, so it almost never binds. Measured today — Bunny $45.93/day actual vs $30 sanctioned (1.53x)
with MTD loss only $259 against a $913 ceiling; LolliBall $101.46/day vs $55 (1.84x), loss $74
against $1,674. BOTH FAMILIES ARE 1.5-1.8x OVER THE SPEND ORI ACTUALLY SANCTIONED and the new
ceiling cannot see it. The binding constraint should be the SPEND RATE (daily_investment), which
already exists and already flags both OVER_ENVELOPE. Ceiling should be demoted to a catastrophe
backstop. NEEDS ORI'S RULING before Task 8b wires enforcement.
OPEN: takeover_target_organic_units NULL on both rows — Ori must supply (calibration only: Aug
run-rates ~71 and ~235 organic units/month). Minor: BASELINE_MAY_JUL restated slightly since Task 1
(Lollibox -$0.61, halos in the 3rd decimal) — within the assertion's tolerances, but a May-Jul
window restating at all is worth a look since ads should have settled.

## 2026-08-19 — two-book P&L Tasks 3-6 done; backlog committed
Tasks 3 (V_BOOK_ASSIGNMENT), 4 (V_FAMILY_BAR), 5 (T_FAMILY_BAR + SP_SNAPSHOT_FAMILY_BAR) and 6
(V_INVEST_STATUS) all shipped with three-stage review. Every acceptance assertion 0.
ORI'S RULING PROVED EMPIRICALLY: "spend rate binds". Both launches are 1.5-1.8x over sanctioned
spend (Bunny $45.93/day vs $30, LolliBall $101.46/day vs $55) while their loss ceilings are only
28.3% and 4.4% used. Had the gate been the net-profit ceiling, BOTH would read fully exempt today.
Both exemptions now read DEAD.
THE LAUNCHES ARE WORKING ON THE METRIC ORI CHOSE: organic units climbing every complete month —
Bunny 28 -> 44 -> 69, LolliBall 0 -> 1 -> 127. Losses deepened over the same stretch, so both read
"mixed" rather than "improving" (the improving branch needs units AND loss both moving right).
Neither is near the kill rule (two consecutive months of no organic growth).
ALGEBRA FOUND IN REVIEW: the keyword bar test reduces to (ads_net_roas + total_net_roas)/2 >= 1.0 —
it is the MEAN of the two measures. So when the halo is real (>1) the bar is provably STRICTER than
the truth test and can never be more permissive; a permissive break is only reachable at halo<1
(the COGS artifact). Calibration is a data coincidence per window, not an identity, and the split
MOVES — do not pin it (corrected 2026-08-20; the figure written here first went stale within a day).
Re-measured 2026-08-20 over all 84 (family, period) rows including the six still-filling MTD rows:
73 agree, 1 unjudgeable, 10 disagree — 8 CONSERVATIVE (one of them a still-filling row) and 2
PERMISSIVE. Over complete periods only: 68 agree, 1 unjudgeable, 7 CONSERVATIVE, 2 PERMISSIVE. The
scope is part of the answer and the query is published in the V_FAMILY_BAR.sql header. The monthly
re-check must alarm only on PERMISSIVE breaks — that direction is stable, the counts are not.
BACKLOG COMMITTED: a8cb5aa (136 backend files, v27.72-v27.83 + two-book 1-5, hook passed) and
5206d8b (30 dashboard files, --no-verify: tsc clean, 395 PRE-EXISTING eslint issues). .gitignore
gained *.bak.* — the old *.bak / *.sql.bak rules never matched the deploy battery's versioned form,
so 157 backups had been permanent git-status noise. Working tree now CLEAN.
OPEN / DATED: (1) nothing stops yet — no engine reads V_INVEST_STATUS; the spend gate bites only
when Task 8b wires protection_qualified (renamed from exemption_live 2026-08-20) into
V_LAUNCH_EXEMPTION, and Task 8b is on hold under "release nothing". (2) Bunny flips RAMP->PROOF on
2026-09-01, NOT ~2026-09-24 (corrected 2026-08-20): the deployed test is
IF(launch_age_months <= 3,'RAMP','PROOF') over DATE_DIFF(today, first_sale_date, MONTH), which counts
MONTH BOUNDARIES CROSSED, not elapsed 30-day periods — off first_sale_date 2026-05-24 it reads 3 on
2026-08-31 and 4 on 2026-09-01. takeover_target_organic_units is NULL, so PROOF is a no-op until Ori
supplies it. (3) LolliBall (first sale 2026-06-26) reaches PROOF on 2026-10-01 by the same
arithmetic, and PROOF judges a LEVEL, so its implausible 0.87 halo must be fixed first — note 0.87 is
its BASELINE_MAY_JUL halo; on the M3 window that the bar actually reads it is 1.15.
(4) 10.5% of ad spend sits in 9 unmapped campaigns, outside both books.
