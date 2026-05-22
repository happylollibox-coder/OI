import React from 'react';
import type { CoachStrategyRow, ActionRow } from '../types';
import { Target, TrendingDown, TrendingUp, Shield, Eye, Trash2, Rocket, RefreshCw, DollarSign, MapPin, AlertTriangle } from 'lucide-react';

/* ─── Capability icons ─── */
const TASK_ICONS: Record<string, React.ReactNode> = {
  ELIMINATE_WASTE:    <Trash2 size={16} />,
  OPTIMIZE_BIDS:     <TrendingDown size={16} />,
  SCALE_WINNERS:     <TrendingUp size={16} />,
  PROMOTE_TERMS:     <Rocket size={16} />,
  CORRECT_HEROES:    <RefreshCw size={16} />,
  MAINTAIN:          <Shield size={16} />,
  INCREASE_BUDGETS:  <DollarSign size={16} />,
  BOOST_PLACEMENTS:  <MapPin size={16} />,
  PROTECT_TERMS:     <Shield size={16} />,
  COST_CONTROL:      <AlertTriangle size={16} />,
  RESTORE_BUDGETS:   <DollarSign size={16} />,
  NORMALIZE_BIDS:    <TrendingDown size={16} />,
  MONITOR_PERFORMANCE: <Eye size={16} />,
};

const MODE_CONFIG: Record<string, { label: string; emoji: string; gradient: string; accent: string }> = {
  GUARDIAN:  { label: 'Guardian', emoji: '🛡️', gradient: 'linear-gradient(135deg, #1e40af 0%, #3b82f6 100%)', accent: '#3b82f6' },
  BLITZ:    { label: 'Blitz',    emoji: '🔥', gradient: 'linear-gradient(135deg, #b45309 0%, #f59e0b 100%)', accent: '#f59e0b' },
  COOLDOWN: { label: 'Cooldown', emoji: '❄️', gradient: 'linear-gradient(135deg, #0e7490 0%, #06b6d4 100%)', accent: '#06b6d4' },
};

interface Props {
  strategy: CoachStrategyRow[];
  actions: ActionRow[];
  activeMode: string;
  activeFilter: string | null;
  onFilterChange: (taskId: string | null) => void;
  activeOccasion?: string;
}

export function CoachStrategyPanel({ strategy, actions, activeMode, activeFilter, onFilterChange, activeOccasion }: Props) {
  const modeConfig = MODE_CONFIG[activeMode] || MODE_CONFIG.GUARDIAN;
  const modeTasks = strategy
    .filter(s => s.coach_mode === activeMode)
    .sort((a, b) => a.display_order - b.display_order);

  if (!modeTasks.length) return null;

  const northStar = modeTasks[0]?.north_star ?? '';

  // Compute stats per task from actions
  const taskStats = new Map<string, {
    count: number;
    spendImpacted: number;
    campaignsAffected: Set<string>;
    budgetDelta: number;
  }>();

  // Count RESTORE_BUDGETS separately: one action per campaign with inflated budget
  const budgetCampaignsSeen = new Set<string>();
  for (const t of actions) {
    // Count budget restorations by unique campaign (not by term)
    if (t.current_budget != null && t.pre_peak_budget != null && t.current_budget > t.pre_peak_budget) {
      if (!budgetCampaignsSeen.has(t.campaign_id)) {
        budgetCampaignsSeen.add(t.campaign_id);
        let s = taskStats.get('RESTORE_BUDGETS');
        if (!s) {
          s = { count: 0, spendImpacted: 0, campaignsAffected: new Set(), budgetDelta: 0 };
          taskStats.set('RESTORE_BUDGETS', s);
        }
        s.count++;
        s.campaignsAffected.add(t.campaign_id);
        if (t.recommended_budget != null) {
          s.budgetDelta += t.current_budget - t.recommended_budget;
        }
      }
    }

    if (!t.strategic_task) continue;
    // Skip RESTORE_BUDGETS from strategic_task — we count it above by actual inflated budgets
    if (t.strategic_task === 'RESTORE_BUDGETS') continue;
    let s = taskStats.get(t.strategic_task);
    if (!s) {
      s = { count: 0, spendImpacted: 0, campaignsAffected: new Set(), budgetDelta: 0 };
      taskStats.set(t.strategic_task, s);
    }
    s.count++;
    s.spendImpacted += Number(t.target_spend_8w ?? 0);
    s.campaignsAffected.add(t.campaign_id);
    if (t.current_budget && t.recommended_budget) {
      s.budgetDelta += t.current_budget - t.recommended_budget;
    }
  }

  // North star progress
  let northStarCurrent: number | null = null;
  let northStarTarget = modeTasks[0]?.north_star_target;
  let progressPct = 0;
  let progressLabel = '';

  if (activeMode === 'GUARDIAN' && modeTasks[0]?.north_star_metric === 'NET_ROAS') {
    // Calculate portfolio ROAS from coach terms
    const totalSpend = actions.reduce((s, t) => s + (Number(t.target_spend_8w) || 0), 0);
    const totalSales = actions.reduce((s, t) => s + (Number(t.target_spend_8w) || 0) * (Number(t.target_net_roas_8w) || 0), 0);
    northStarCurrent = totalSpend > 0 ? totalSales / totalSpend : 0;
    progressPct = northStarTarget ? Math.min(100, Math.round((northStarCurrent / northStarTarget) * 100)) : 0;
    progressLabel = `Net ROAS: ${northStarCurrent.toFixed(2)} / ${northStarTarget}`;
  } else if (activeMode === 'COOLDOWN' && modeTasks[0]?.north_star_metric === 'BUDGET_RATIO') {
    // Calculate budget reduction progress
    const campaignsNeedingReduction = new Set<string>();
    const campaignsAtBaseline = new Set<string>();
    for (const t of actions) {
      if (t.current_budget != null && t.pre_peak_budget != null) {
        const key = t.campaign_id;
        if (t.current_budget > t.pre_peak_budget) campaignsNeedingReduction.add(key);
        else campaignsAtBaseline.add(key);
      }
    }
    const totalCampaigns = campaignsNeedingReduction.size + campaignsAtBaseline.size;
    progressPct = totalCampaigns > 0 ? Math.round((campaignsAtBaseline.size / totalCampaigns) * 100) : 100;
    progressLabel = `${campaignsAtBaseline.size}/${totalCampaigns} campaigns at baseline`;
  }

  // Mitigation warnings
  const mitigationWarnings: string[] = [];
  for (const task of modeTasks) {
    if (!task.mitigation) continue;
    const stats = taskStats.get(task.task_id);
    if (!stats) continue;
    // Show mitigation if this task has a lot of actions
    if (activeMode === 'COOLDOWN' && task.task_id === 'NORMALIZE_BIDS' && stats.count > 0) {
      // Check for campaigns with very low ROAS
      const lowRoasTerms = actions.filter(t =>
        t.strategic_task === 'NORMALIZE_BIDS' &&
        t.pp_target_net_roas != null && t.pp_target_net_roas < 0.3
      );
      if (lowRoasTerms.length > 0) {
        mitigationWarnings.push(`⚠️ ${lowRoasTerms.length} targets with ROAS < 0.3 — escalated to RESTORE_PRE_PEAK`);
      }
    }
    if (activeMode === 'GUARDIAN' && task.task_id === 'ELIMINATE_WASTE' && stats.spendImpacted > 500) {
      mitigationWarnings.push(`⚠️ $${Math.round(stats.spendImpacted)} in wasted spend identified — ${stats.count} terms to cut`);
    }
  }

  return (
    <div style={{
      borderRadius: 12,
      overflow: 'hidden',
      marginBottom: 20,
      border: '1px solid var(--border)',
      background: 'var(--card-bg)',
    }}>
      {/* Header */}
      <div style={{
        background: modeConfig.gradient,
        color: '#fff',
        padding: '16px 20px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 12,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ fontSize: 24 }}>{modeConfig.emoji}</span>
          <div>
            <div style={{ fontSize: 15, fontWeight: 700, letterSpacing: 0.3 }}>
              {modeConfig.label} Mode{activeOccasion ? ` — ${activeOccasion}` : ''}
            </div>
            <div style={{ fontSize: 12, opacity: 0.9, marginTop: 2 }}>
              <Target size={12} style={{ display: 'inline', marginRight: 4, verticalAlign: -1 }} />
              {northStar}
            </div>
          </div>
        </div>

        {/* Progress */}
        {progressLabel && (
          <div style={{ textAlign: 'right', minWidth: 180 }}>
            <div style={{ fontSize: 12, opacity: 0.85, marginBottom: 4 }}>{progressLabel}</div>
            <div style={{
              height: 6,
              borderRadius: 3,
              background: 'rgba(255,255,255,0.25)',
              overflow: 'hidden',
            }}>
              <div style={{
                height: '100%',
                borderRadius: 3,
                width: `${progressPct}%`,
                background: '#fff',
                transition: 'width 0.6s ease',
              }} />
            </div>
          </div>
        )}
      </div>

      {/* Task Cards */}
      <div style={{
        display: 'flex',
        gap: 8,
        padding: '12px 16px',
        overflowX: 'auto',
        flexWrap: 'wrap',
      }}>
        {/* All button */}
        <button
          onClick={() => onFilterChange(null)}
          style={{
            padding: '8px 14px',
            borderRadius: 8,
            border: activeFilter === null ? `2px solid ${modeConfig.accent}` : '1px solid var(--border)',
            background: activeFilter === null ? `${modeConfig.accent}18` : 'var(--card-bg)',
            cursor: 'pointer',
            fontSize: 12,
            fontWeight: 600,
            color: activeFilter === null ? modeConfig.accent : 'var(--muted)',
            transition: 'all 0.2s',
            whiteSpace: 'nowrap',
          }}
        >
          All Tasks
        </button>

        {modeTasks.map(task => {
          const stats = taskStats.get(task.task_id);
          const count = stats?.count ?? 0;
          const isActive = activeFilter === task.task_id;
          const spend = stats?.spendImpacted ?? 0;
          const campaignCount = stats?.campaignsAffected.size ?? 0;
          const budgetDelta = stats?.budgetDelta ?? 0;

          // Choose the most relevant metric to show
          let metricLabel = `${count} actions`;
          if (task.capability === 'BUDGET_ADJUST' && budgetDelta > 0) {
            metricLabel = `${campaignCount} campaigns · -$${Math.round(budgetDelta)}/day`;
          } else if (count > 0 && spend > 0) {
            metricLabel = `${count} actions · $${Math.round(spend)}`;
          }

          return (
            <button
              key={task.task_id}
              onClick={() => onFilterChange(isActive ? null : task.task_id)}
              style={{
                padding: '8px 14px',
                borderRadius: 8,
                border: isActive ? `2px solid ${modeConfig.accent}` : '1px solid var(--border)',
                background: isActive ? `${modeConfig.accent}18` : 'var(--card-bg)',
                cursor: 'pointer',
                textAlign: 'left',
                transition: 'all 0.2s',
                minWidth: 140,
                opacity: count === 0 ? 0.4 : 1,
              }}
            >
              <div style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                fontSize: 13,
                fontWeight: 600,
                color: isActive ? modeConfig.accent : 'var(--fg)',
              }}>
                <span style={{ color: modeConfig.accent }}>{TASK_ICONS[task.task_id] ?? task.emoji}</span>
                {task.task_name}
              </div>
              <div style={{
                fontSize: 11,
                color: 'var(--muted)',
                marginTop: 3,
                whiteSpace: 'nowrap',
              }}>
                {metricLabel}
              </div>
            </button>
          );
        })}
      </div>

      {/* Mitigation warnings */}
      {mitigationWarnings.length > 0 && (
        <div style={{
          padding: '8px 16px 12px',
          display: 'flex',
          flexDirection: 'column',
          gap: 4,
        }}>
          {mitigationWarnings.map((w, i) => (
            <div key={i} style={{
              fontSize: 12,
              color: '#f59e0b',
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              padding: '4px 10px',
              borderRadius: 6,
              background: 'rgba(245, 158, 11, 0.08)',
            }}>
              <AlertTriangle size={13} />
              {w}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
