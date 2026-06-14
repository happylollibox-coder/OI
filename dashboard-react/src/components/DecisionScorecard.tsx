import { useEffect, useMemo, useState } from 'react';
import { Card } from './Card';
import { Badge, ActionBadge } from './Badge';
import { cubeLoad } from '../hooks/useCubeData';
import { fM } from '../utils';
import { ChevronDown, ChevronRight, Target, TrendingUp, TrendingDown, Clock, HelpCircle } from 'lucide-react';

/* ─── Decision Scorecard — close the loop on applied PPC changes ───
 * Reads V_PPC_ACTION_OUTCOMES via Cube (PpcActionOutcomes): every change
 * logged from the DO page, scored IMPROVED / WORSE / NO_DATA / TOO_EARLY
 * against 14d pre/post windows. SOP: architecture/PPC_CLOSE_THE_LOOP.md */

interface OutcomeRow {
  change_id: string;
  applied_at: string | null;
  action: string;
  action_group: string;
  verdict: 'IMPROVED' | 'WORSE' | 'NO_DATA' | 'TOO_EARLY';
  search_term: string;
  targeting: string;
  campaign_name: string;
  coach_mode: string;
  source: string;
  old_bid: number | null;
  new_bid: number | null;
  old_budget: number | null;
  new_budget: number | null;
  post_days_elapsed: number;
  pre_spend: number;
  pre_orders: number;
  pre_net_roas: number | null;
  pre_orders_per_day: number;
  post_spend: number;
  post_orders: number;
  post_net_roas: number | null;
  post_orders_per_day: number | null;
  net_roas_delta: number;
  weekly_savings: number;
  expected_impact_weekly: number | null;
  expected_impact_kind: string | null;
  actual_weekly_impact: number | null;
  target_status: string | null;
}

const num = (v: unknown): number => (v == null ? 0 : Number(v));
const numOrNull = (v: unknown): number | null => (v == null ? null : Number(v));

async function loadOutcomes(): Promise<OutcomeRow[]> {
  const raw = await cubeLoad({
    dimensions: [
      'PpcActionOutcomes.changeId', 'PpcActionOutcomes.appliedAt',
      'PpcActionOutcomes.action', 'PpcActionOutcomes.actionGroup', 'PpcActionOutcomes.verdict',
      'PpcActionOutcomes.searchTerm', 'PpcActionOutcomes.targeting', 'PpcActionOutcomes.campaignName',
      'PpcActionOutcomes.coachMode', 'PpcActionOutcomes.source',
      'PpcActionOutcomes.oldBid', 'PpcActionOutcomes.newBid',
      'PpcActionOutcomes.oldBudget', 'PpcActionOutcomes.newBudget',
      'PpcActionOutcomes.postDaysElapsed',
      'PpcActionOutcomes.preSpend', 'PpcActionOutcomes.preOrders', 'PpcActionOutcomes.preNetRoas',
      'PpcActionOutcomes.preOrdersPerDay',
      'PpcActionOutcomes.postSpend', 'PpcActionOutcomes.postOrders', 'PpcActionOutcomes.postNetRoas',
      'PpcActionOutcomes.postOrdersPerDay',
      'PpcActionOutcomes.netRoasDelta', 'PpcActionOutcomes.weeklySavings',
      'PpcActionOutcomes.expectedImpactWeekly', 'PpcActionOutcomes.expectedImpactKind',
      'PpcActionOutcomes.actualWeeklyImpact', 'PpcActionOutcomes.targetStatus',
    ],
    order: { 'PpcActionOutcomes.appliedAt': 'desc' },
    limit: 500,
  });
  return (raw as Record<string, unknown>[]).map(r => ({
    change_id: String(r['PpcActionOutcomes.changeId'] ?? ''),
    applied_at: r['PpcActionOutcomes.appliedAt'] ? String(r['PpcActionOutcomes.appliedAt']) : null,
    action: String(r['PpcActionOutcomes.action'] ?? ''),
    action_group: String(r['PpcActionOutcomes.actionGroup'] ?? 'OTHER'),
    verdict: String(r['PpcActionOutcomes.verdict'] ?? 'NO_DATA') as OutcomeRow['verdict'],
    search_term: String(r['PpcActionOutcomes.searchTerm'] ?? ''),
    targeting: String(r['PpcActionOutcomes.targeting'] ?? ''),
    campaign_name: String(r['PpcActionOutcomes.campaignName'] ?? ''),
    coach_mode: String(r['PpcActionOutcomes.coachMode'] ?? ''),
    source: String(r['PpcActionOutcomes.source'] ?? 'COACH'),
    old_bid: numOrNull(r['PpcActionOutcomes.oldBid']),
    new_bid: numOrNull(r['PpcActionOutcomes.newBid']),
    old_budget: numOrNull(r['PpcActionOutcomes.oldBudget']),
    new_budget: numOrNull(r['PpcActionOutcomes.newBudget']),
    post_days_elapsed: num(r['PpcActionOutcomes.postDaysElapsed']),
    pre_spend: num(r['PpcActionOutcomes.preSpend']),
    pre_orders: num(r['PpcActionOutcomes.preOrders']),
    pre_net_roas: numOrNull(r['PpcActionOutcomes.preNetRoas']),
    pre_orders_per_day: num(r['PpcActionOutcomes.preOrdersPerDay']),
    post_spend: num(r['PpcActionOutcomes.postSpend']),
    post_orders: num(r['PpcActionOutcomes.postOrders']),
    post_net_roas: numOrNull(r['PpcActionOutcomes.postNetRoas']),
    post_orders_per_day: numOrNull(r['PpcActionOutcomes.postOrdersPerDay']),
    net_roas_delta: num(r['PpcActionOutcomes.netRoasDelta']),
    weekly_savings: num(r['PpcActionOutcomes.weeklySavings']),
    expected_impact_weekly: numOrNull(r['PpcActionOutcomes.expectedImpactWeekly']),
    expected_impact_kind: r['PpcActionOutcomes.expectedImpactKind'] ? String(r['PpcActionOutcomes.expectedImpactKind']) : null,
    actual_weekly_impact: numOrNull(r['PpcActionOutcomes.actualWeeklyImpact']),
    target_status: r['PpcActionOutcomes.targetStatus'] ? String(r['PpcActionOutcomes.targetStatus']) : null,
  }));
}

/* ─── Verdict sentence: plain-English outcome per change ─── */
function verdictSentence(r: OutcomeRow): string {
  const entity = r.targeting || r.search_term || r.campaign_name || 'target';
  const roas = (v: number | null) => (v == null ? '—' : v.toFixed(2));

  if (r.verdict === 'TOO_EARLY') {
    return `${r.post_days_elapsed} of 14 post-change days in — verdict pending`;
  }
  if (r.verdict === 'NO_DATA') {
    return r.action_group === 'PROMOTE'
      ? `promoted "${entity}" — no spend recorded yet, keyword may not be live`
      : `no ads data matched this change — check campaign/keyword identifiers`;
  }

  switch (r.action_group) {
    case 'NEGATE':
    case 'PAUSE_TARGET': {
      const verb = r.action_group === 'NEGATE' ? 'negated' : 'paused';
      return r.verdict === 'IMPROVED'
        ? `${verb} "${entity}" — saving ${fM(r.weekly_savings)}/wk (was net ROAS ${roas(r.pre_net_roas)})`
        : `${verb} "${entity}" — it was profitable (net ROAS ${roas(r.pre_net_roas)}), likely wrong call`;
    }
    case 'BID_DOWN':
      return r.verdict === 'IMPROVED'
        ? `bid cut on "${entity}" — net ROAS ${roas(r.pre_net_roas)} → ${roas(r.post_net_roas)}, efficiency up`
        : `bid cut on "${entity}" — net ROAS ${roas(r.pre_net_roas)} → ${roas(r.post_net_roas)}${(r.post_orders_per_day ?? 0) < r.pre_orders_per_day ? ', orders dropped' : ''}, likely wrong call`;
    case 'BID_UP':
    case 'BUDGET_UP':
      return r.verdict === 'IMPROVED'
        ? `scaled "${entity}" — orders/day ${r.pre_orders_per_day.toFixed(1)} → ${(r.post_orders_per_day ?? 0).toFixed(1)} at net ROAS ${roas(r.post_net_roas)}`
        : `scaled "${entity}" — efficiency fell (net ROAS ${roas(r.pre_net_roas)} → ${roas(r.post_net_roas)}), didn't pay off`;
    case 'PROMOTE':
      return r.verdict === 'IMPROVED'
        ? `promoted "${entity}" — now ${(r.post_orders_per_day ?? 0).toFixed(1)} orders/day at net ROAS ${roas(r.post_net_roas)}`
        : `promoted "${entity}" — net ROAS ${roas(r.post_net_roas)} post-launch, below break-even`;
    default:
      return r.verdict === 'IMPROVED'
        ? `"${entity}" — net ROAS ${roas(r.pre_net_roas)} → ${roas(r.post_net_roas)}`
        : `"${entity}" — net ROAS ${roas(r.pre_net_roas)} → ${roas(r.post_net_roas)}, worse after change`;
  }
}

const VERDICT_META: Record<OutcomeRow['verdict'], { color: string; icon: typeof TrendingUp; label: string }> = {
  IMPROVED: { color: 'text-emerald-400', icon: TrendingUp, label: 'Improved' },
  WORSE: { color: 'text-red-400', icon: TrendingDown, label: 'Worse' },
  TOO_EARLY: { color: 'text-amber-400', icon: Clock, label: 'Too early' },
  NO_DATA: { color: 'text-zinc-500', icon: HelpCircle, label: 'No data' },
};

export function DecisionScorecard() {
  const [rows, setRows] = useState<OutcomeRow[] | null>(null);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    let alive = true;
    loadOutcomes()
      .then(r => { if (alive) setRows(r); })
      .catch(() => { if (alive) setRows([]); });
    return () => { alive = false; };
  }, []);

  const stats = useMemo(() => {
    const r = rows ?? [];
    const improved = r.filter(x => x.verdict === 'IMPROVED').length;
    const worse = r.filter(x => x.verdict === 'WORSE').length;
    const tooEarly = r.filter(x => x.verdict === 'TOO_EARLY').length;
    const noData = r.filter(x => x.verdict === 'NO_DATA').length;
    const scoreable = improved + worse;
    const accuracy = scoreable > 0 ? (improved / scoreable) * 100 : null;
    const weeklySavings = r
      .filter(x => (x.action_group === 'NEGATE' || x.action_group === 'PAUSE_TARGET') && x.verdict === 'IMPROVED')
      .reduce((s, x) => s + x.weekly_savings, 0);
    const gradedTargets = r.filter(x => x.target_status === 'TARGET_MET' || x.target_status === 'BELOW_TARGET');
    const targetsMet = gradedTargets.filter(x => x.target_status === 'TARGET_MET').length;
    const targetsTotal = gradedTargets.length;
    return { improved, worse, tooEarly, noData, scoreable, accuracy, weeklySavings, targetsMet, targetsTotal };
  }, [rows]);

  // Hide entirely until the first change has been logged
  if (rows === null || rows.length === 0) return null;

  const visible = expanded ? rows : rows.slice(0, 8);

  return (
    <Card className="mb-5 !p-0 overflow-hidden">
      {/* Header: aggregate accuracy */}
      <div className="flex items-center gap-3 px-4 py-3 border-b border-border">
        <Target size={15} className="text-blue-400 shrink-0" />
        <span className="text-[13px] font-bold text-text">Decision Scorecard</span>
        <span className="text-[10px] text-subtle">{rows.length} logged changes · last 180d</span>
        <div className="flex-1" />
        {stats.accuracy != null && (
          <span className={`font-mono text-[13px] font-bold ${stats.accuracy >= 70 ? 'text-emerald-400' : stats.accuracy >= 50 ? 'text-amber-400' : 'text-red-400'}`}>
            {stats.accuracy.toFixed(0)}% right
          </span>
        )}
        {stats.weeklySavings > 0 && (
          <Badge variant="green">{fM(stats.weeklySavings)}/wk saved</Badge>
        )}
        {stats.targetsTotal > 0 && (
          <span className={`text-[10px] font-mono ${stats.targetsMet === stats.targetsTotal ? 'text-emerald-400' : stats.targetsMet > 0 ? 'text-amber-400' : 'text-red-400'}`}>
            {stats.targetsMet}/{stats.targetsTotal} targets met
          </span>
        )}
        <span className="flex items-center gap-2 text-[10px] font-mono">
          <span className="text-emerald-400">✓ {stats.improved}</span>
          <span className="text-red-400">✗ {stats.worse}</span>
          <span className="text-amber-400">⏳ {stats.tooEarly}</span>
          {stats.noData > 0 && <span className="text-zinc-500">? {stats.noData}</span>}
        </span>
      </div>

      {/* Per-change verdicts */}
      <div className="divide-y divide-border-faint">
        {visible.map(r => {
          const meta = VERDICT_META[r.verdict];
          const Icon = meta.icon;
          const entity = r.targeting || r.search_term || '(campaign-level)';
          const bidChange = r.new_bid != null
            ? `${r.old_bid != null ? `$${r.old_bid.toFixed(2)}→` : ''}$${r.new_bid.toFixed(2)}`
            : r.new_budget != null
            ? `${r.old_budget != null ? `$${r.old_budget.toFixed(0)}→` : ''}$${r.new_budget.toFixed(0)}/d`
            : null;
          const fullDetail = `${r.action} "${entity}" in ${r.campaign_name}`
            + (bidChange ? ` · ${r.new_budget != null ? 'budget' : 'bid'} ${bidChange}` : '')
            + (r.coach_mode ? ` · ${r.coach_mode}` : '')
            + ` · ${verdictSentence(r)}`;
          return (
            <div key={r.change_id} className="flex items-center gap-3 px-4 py-2 text-[11px] hover:bg-card-hover transition-colors" title={fullDetail}>
              <Icon size={13} className={`${meta.color} shrink-0`} />
              <ActionBadge action={r.action} />
              <span className="font-semibold text-[var(--color-text)] shrink-0 max-w-[180px] truncate" title={entity}>"{entity}"</span>
              {bidChange && (
                <span className="text-[9px] font-mono text-muted shrink-0 px-1.5 py-0.5 rounded bg-surface border border-border-faint">{bidChange}</span>
              )}
              <span className="text-subtle flex-1 min-w-0 truncate" title={verdictSentence(r)}>
                {verdictSentence(r)}
              </span>
              {r.expected_impact_weekly != null && r.target_status && r.target_status !== 'NO_TARGET' && (
                <span className={`text-[9px] font-mono shrink-0 px-1.5 py-0.5 rounded border ${
                  r.target_status === 'TARGET_MET'
                    ? 'text-emerald-400 border-emerald-800 bg-emerald-950/30'
                    : r.target_status === 'BELOW_TARGET'
                    ? 'text-red-400 border-red-800 bg-red-950/30'
                    : 'text-zinc-500 border-zinc-700 bg-zinc-900/30'
                }`}>
                  target {fM(r.expected_impact_weekly)}/wk →{' '}
                  {r.target_status === 'TARGET_MET' ? '✓ met' : r.target_status === 'BELOW_TARGET' ? '✗ below' : '… early'}
                </span>
              )}
              <span className="text-[10px] text-faint font-mono truncate max-w-[160px] shrink-0" title={r.campaign_name}>{r.campaign_name}</span>
              {r.coach_mode && (
                <span className="text-[9px] px-1.5 py-0.5 rounded bg-surface border border-border-faint text-muted font-mono uppercase shrink-0">
                  {r.coach_mode}
                </span>
              )}
              <span className="text-[10px] text-faint font-mono shrink-0 w-16 text-right">
                {r.applied_at ? new Date(r.applied_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : ''}
              </span>
            </div>
          );
        })}
      </div>

      {rows.length > 8 && (
        <button
          onClick={() => setExpanded(p => !p)}
          className="w-full flex items-center justify-center gap-1 px-4 py-2 text-[10px] text-subtle hover:text-text hover:bg-card-hover transition-colors font-semibold border-t border-border-faint"
        >
          {expanded ? <ChevronDown size={11} /> : <ChevronRight size={11} />}
          {expanded ? 'Show less' : `Show all ${rows.length}`}
        </button>
      )}
    </Card>
  );
}
