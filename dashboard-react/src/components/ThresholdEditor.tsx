import { useState, useMemo } from 'react';
import { Badge } from './Badge';
import type { StrategyGroup, ThresholdRow } from '../hooks/useThresholds';

/* ═══════════════════════════════════════════════════════════════
   Strategy metadata
   ═══════════════════════════════════════════════════════════════ */
const STRATEGY_META: Record<string, { icon: string; label: string; color: string; desc: string }> = {
  GLOBAL:             { icon: '🌐', label: 'Global',             color: 'blue',   desc: 'Default fallback thresholds' },
  BRAND_DEFENSE:      { icon: '🛡️', label: 'Brand Defense',      color: 'purple', desc: 'Never negate — deter competitors' },
  EXACT_BOOST:        { icon: '🎯', label: 'Exact Boost',        color: 'green',  desc: 'Proven keywords, scale during peak' },
  HUNTER:             { icon: '🔍', label: 'Hunter',             color: 'amber',  desc: 'Discovery — fast negate, graduate winners' },
  LOW_COST_DISCOVERY: { icon: '💰', label: 'Low-Cost',           color: 'cyan',   desc: 'Ultra-cheap CPCs, fast kill' },
  CATEGORY_CONQUEST:  { icon: '⚔️', label: 'Category',           color: 'red',    desc: 'Attacking category terms' },
  PRODUCT_DEFENSE:    { icon: '🏰', label: 'Product Defense',    color: 'purple', desc: 'Protect product pages' },
  SEASONAL_PUSH:      { icon: '🚀', label: 'Seasonal',           color: 'amber',  desc: 'Boost peak → peak throttle' },
  NEW_LAUNCH:         { icon: '🆕', label: 'New Launch',         color: 'blue',   desc: 'Accept early losses for rank' },
  TOS_DOMINATION:     { icon: '🏆', label: 'TOS Domination',     color: 'green',  desc: 'Top-of-Search visibility' },
  RETARGETING:        { icon: '♻️', label: 'Retargeting',        color: 'red',    desc: 'Warm audience, high standards' },
};

const THRESHOLD_META: Record<string, { label: string; unit: string; tip: string }> = {
  INSUFFICIENT_DATA_CLICKS: { label: 'Min Clicks',       unit: 'clicks', tip: 'Skip if fewer clicks in 4 weeks' },
  WASTED_SPEND_THRESHOLD:   { label: 'Wasted Spend',     unit: '$',      tip: 'Flag wasted if spend ≥ this with 0 orders' },
  NEGATE_ROAS_THRESHOLD:    { label: 'Negate ROAS',      unit: 'x',      tip: 'Negate if Net ROAS below this' },
  NEGATE_SPEND_THRESHOLD:   { label: 'Negate Spend',     unit: '$',      tip: 'Only negate if spend exceeds this' },
  REDUCE_BID_ROAS:          { label: 'Reduce Bid ROAS',  unit: 'x',      tip: 'Reduce bid if Net ROAS below this' },
  REDUCE_BID_SPEND:         { label: 'Reduce Bid Spend', unit: '$',      tip: 'Only reduce bid if spend exceeds this' },
  SCALE_UP_ROAS:            { label: 'Scale Up ROAS',    unit: 'x',      tip: 'Scale up if Net ROAS exceeds this' },
  SCALE_UP_SPEND_CAP:       { label: 'Scale Spend Cap',  unit: '$',      tip: 'Only scale if spend below this cap' },
  PROFITABLE_ROAS:          { label: 'Profitable ROAS',  unit: 'x',      tip: 'KEEP at this Net ROAS or above' },
  HALO_ROAS:                { label: 'Halo ROAS',        unit: 'x',      tip: 'Keep if organic halo + ROAS ≥ this' },
  CONFIDENCE_DAYS_HIGH:     { label: 'High Conf Days',   unit: 'days',   tip: 'HIGH confidence minimum days' },
  CONFIDENCE_CLICKS_HIGH:   { label: 'High Conf Clicks', unit: 'clicks', tip: 'HIGH confidence minimum clicks' },
  CONFIDENCE_DAYS_MEDIUM:   { label: 'Med Conf Days',    unit: 'days',   tip: 'MEDIUM confidence minimum days' },
  CONFIDENCE_CLICKS_MEDIUM: { label: 'Med Conf Clicks',  unit: 'clicks', tip: 'MEDIUM confidence minimum clicks' },
};

/* ═══════════════════════════════════════════════════════════════
   Decision tree node definitions per strategy
   ═══════════════════════════════════════════════════════════════ */
interface TreeNode {
  id: string;
  condition: string;
  thresholdKeys: string[];          // which threshold(s) control this node
  yesLabel: string;
  yesColor: 'red' | 'amber' | 'green' | 'muted' | 'blue';
  noFallthrough?: boolean;          // if true, "No" flows to next node
}

function getTreeForStrategy(thresholds: ThresholdRow[]): TreeNode[] {
  const tv = (key: string): string => {
    const t = thresholds.find(r => r.threshold_key === key);
    if (!t) return '?';
    if (t.threshold_value === -999) return 'NEVER';
    const m = THRESHOLD_META[key];
    if (!m) return String(t.threshold_value);
    if (m.unit === '$') return `$${t.threshold_value}`;
    if (m.unit === 'x') return `${t.threshold_value}x`;
    return `${t.threshold_value} ${m.unit}`;
  };

  const has = (key: string) => thresholds.some(r => r.threshold_key === key);
  const isNever = (key: string) => thresholds.find(r => r.threshold_key === key)?.threshold_value === -999;

  const nodes: TreeNode[] = [];

  if (has('INSUFFICIENT_DATA_CLICKS')) {
    nodes.push({
      id: 'insufficient',
      condition: `clicks < ${tv('INSUFFICIENT_DATA_CLICKS')}?`,
      thresholdKeys: ['INSUFFICIENT_DATA_CLICKS'],
      yesLabel: 'INSUFFICIENT DATA',
      yesColor: 'muted',
      noFallthrough: true,
    });
  }

  if (has('WASTED_SPEND_THRESHOLD')) {
    nodes.push({
      id: 'wasted',
      condition: `$0 orders + spend ≥ ${tv('WASTED_SPEND_THRESHOLD')}?`,
      thresholdKeys: ['WASTED_SPEND_THRESHOLD'],
      yesLabel: 'NEGATE (wasted)',
      yesColor: 'red',
      noFallthrough: true,
    });
  }

  if (has('NEGATE_ROAS_THRESHOLD') && !isNever('NEGATE_ROAS_THRESHOLD')) {
    const parts = [`Net ROAS < ${tv('NEGATE_ROAS_THRESHOLD')}`];
    const keys = ['NEGATE_ROAS_THRESHOLD'];
    if (has('NEGATE_SPEND_THRESHOLD')) {
      parts.push(`spend ≥ ${tv('NEGATE_SPEND_THRESHOLD')}`);
      keys.push('NEGATE_SPEND_THRESHOLD');
    }
    nodes.push({
      id: 'negate',
      condition: parts.join(' + ') + '?',
      thresholdKeys: keys,
      yesLabel: 'NEGATE',
      yesColor: 'red',
      noFallthrough: true,
    });
  } else if (isNever('NEGATE_ROAS_THRESHOLD')) {
    nodes.push({
      id: 'negate-never',
      condition: 'Negate keyword?',
      thresholdKeys: ['NEGATE_ROAS_THRESHOLD'],
      yesLabel: 'NEVER NEGATE',
      yesColor: 'purple' as any,
      noFallthrough: true,
    });
  }

  if (has('REDUCE_BID_ROAS')) {
    const parts = [`Net ROAS < ${tv('REDUCE_BID_ROAS')}`];
    const keys = ['REDUCE_BID_ROAS'];
    if (has('REDUCE_BID_SPEND')) {
      parts.push(`spend ≥ ${tv('REDUCE_BID_SPEND')}`);
      keys.push('REDUCE_BID_SPEND');
    }
    nodes.push({
      id: 'reduce',
      condition: parts.join(' + ') + '?',
      thresholdKeys: keys,
      yesLabel: 'REDUCE BID',
      yesColor: 'amber',
      noFallthrough: true,
    });
  }

  if (has('SCALE_UP_ROAS')) {
    const parts = [`Net ROAS ≥ ${tv('SCALE_UP_ROAS')}`];
    const keys = ['SCALE_UP_ROAS'];
    if (has('SCALE_UP_SPEND_CAP')) {
      parts.push(`spend < ${tv('SCALE_UP_SPEND_CAP')}`);
      keys.push('SCALE_UP_SPEND_CAP');
    }
    nodes.push({
      id: 'scale',
      condition: parts.join(' + ') + '?',
      thresholdKeys: keys,
      yesLabel: 'SCALE UP',
      yesColor: 'green',
      noFallthrough: true,
    });
  }

  if (has('PROFITABLE_ROAS')) {
    nodes.push({
      id: 'profitable',
      condition: `Net ROAS ≥ ${tv('PROFITABLE_ROAS')}?`,
      thresholdKeys: ['PROFITABLE_ROAS'],
      yesLabel: 'KEEP',
      yesColor: 'green',
      noFallthrough: true,
    });
  }

  if (has('HALO_ROAS')) {
    nodes.push({
      id: 'halo',
      condition: `Organic halo + ROAS ≥ ${tv('HALO_ROAS')}?`,
      thresholdKeys: ['HALO_ROAS'],
      yesLabel: 'KEEP (halo)',
      yesColor: 'green',
      noFallthrough: true,
    });
  }

  return nodes;
}

/* ═══════════════════════════════════════════════════════════════
   Decision Tree visual component
   ═══════════════════════════════════════════════════════════════ */
const NODE_COLORS: Record<string, string> = {
  red: 'bg-red-500/15 text-red-400 border-red-500/30',
  amber: 'bg-amber-500/15 text-amber-400 border-amber-500/30',
  green: 'bg-emerald-500/15 text-emerald-400 border-emerald-500/30',
  muted: 'bg-zinc-700/30 text-zinc-400 border-zinc-600/30',
  blue: 'bg-blue-500/15 text-blue-400 border-blue-500/30',
  purple: 'bg-purple-500/15 text-purple-400 border-purple-500/30',
};

function DecisionTree({ nodes, highlightKeys }: { nodes: TreeNode[]; highlightKeys: string[] }) {
  return (
    <div className="space-y-0">
      {/* Start */}
      <div className="flex items-center gap-2 mb-3">
        <div className="bg-blue-500/15 border border-blue-500/30 text-blue-400 text-[11px] font-semibold px-3 py-1.5 rounded-lg">
          Keyword enters coach
        </div>
      </div>

      {nodes.map((node, i) => {
        const isHighlighted = node.thresholdKeys.some(k => highlightKeys.includes(k));
        return (
          <div key={node.id} className="relative pl-4 ml-2.5">
            {/* Vertical connector line */}
            <div className="absolute left-0 top-0 bottom-0 w-px bg-zinc-700/50" />
            {/* Horizontal connector */}
            <div className="absolute left-0 top-5 w-4 h-px bg-zinc-700/50" />

            <div className={`flex items-center gap-2.5 py-1.5 transition-all duration-200 ${isHighlighted ? 'scale-[1.02]' : ''}`}>
              {/* Diamond-style condition */}
              <div className={`shrink-0 text-[11px] font-mono px-3 py-1.5 rounded-md border transition-all duration-200 ${
                isHighlighted
                  ? 'bg-blue-500/15 border-blue-500/40 text-blue-300 shadow-[0_0_12px_rgba(59,130,246,0.15)]'
                  : 'bg-zinc-800/60 border-zinc-700/40 text-zinc-300'
              }`}>
                <span className="text-zinc-500 mr-1">◆</span>
                {node.condition}
              </div>

              {/* Arrow */}
              <span className="text-zinc-600 text-[10px]">→ Yes →</span>

              {/* Outcome badge */}
              <div className={`text-[10px] font-bold px-2.5 py-1 rounded-md border ${NODE_COLORS[node.yesColor] || NODE_COLORS.muted}`}>
                {node.yesLabel}
              </div>
            </div>

            {/* "No ↓" label between nodes */}
            {node.noFallthrough && i < nodes.length - 1 && (
              <div className="relative pl-0 ml-0">
                <div className="text-[9px] text-zinc-600 font-mono py-0.5 pl-1">↓ No</div>
              </div>
            )}
          </div>
        );
      })}

      {/* Default fallthrough */}
      <div className="relative pl-4 ml-2.5">
        <div className="absolute left-0 top-0 h-5 w-px bg-zinc-700/50" />
        <div className="absolute left-0 top-5 w-4 h-px bg-zinc-700/50" />
        <div className="flex items-center gap-2.5 py-1.5">
          <div className="text-[11px] font-mono text-zinc-500 px-3 py-1.5 rounded-md border border-zinc-700/30 bg-zinc-800/40">
            default
          </div>
          <span className="text-zinc-600 text-[10px]">→</span>
          <div className={`text-[10px] font-bold px-2.5 py-1 rounded-md border ${NODE_COLORS.muted}`}>
            MONITOR
          </div>
        </div>
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════
   Threshold value editor (right panel)
   ═══════════════════════════════════════════════════════════════ */
function ThresholdPanel({
  thresholds, saving, highlightKeys, setHighlightKeys, onUpdate, onApprove,
}: {
  thresholds: ThresholdRow[];
  saving: boolean;
  highlightKeys: string[];
  setHighlightKeys: (keys: string[]) => void;
  onUpdate: (key: string, strategyId: string, family: string | null, value: number) => Promise<void>;
  onApprove: (key: string, strategyId: string, family: string | null) => Promise<void>;
}) {
  const [editingKey, setEditingKey] = useState<string | null>(null);
  const [draft, setDraft] = useState('');

  const handleEdit = (t: ThresholdRow) => {
    setEditingKey(t.threshold_key);
    setDraft(String(t.threshold_value));
  };

  const handleSave = async (t: ThresholdRow) => {
    const val = parseFloat(draft);
    if (isNaN(val)) return;
    await onUpdate(t.threshold_key, t.strategy_id, t.product_family, val);
    setEditingKey(null);
  };

  return (
    <div className="space-y-1.5">
      {thresholds.map(t => {
        const meta = THRESHOLD_META[t.threshold_key] || { label: t.threshold_key, unit: '', tip: '' };
        const isEditing = editingKey === t.threshold_key;
        const isHighlighted = highlightKeys.includes(t.threshold_key);
        const isNever = t.threshold_value === -999;

        return (
          <div
            key={`${t.threshold_key}-${t.product_family || ''}`}
            className={`flex items-center gap-2 px-3 py-2 rounded-lg border transition-all duration-200 ${
              isHighlighted
                ? 'bg-blue-500/[.06] border-blue-500/25 shadow-[0_0_8px_rgba(59,130,246,0.08)]'
                : 'bg-inset border-border-faint hover:border-border'
            }`}
            onMouseEnter={() => setHighlightKeys([t.threshold_key])}
            onMouseLeave={() => setHighlightKeys([])}
          >
            {/* Label */}
            <div className="flex-1 min-w-0">
              <div className="text-[11px] font-semibold truncate">{meta.label}</div>
              <div className="text-[9px] text-subtle truncate">{meta.tip}</div>
            </div>

            {/* Value */}
            {isEditing ? (
              <div className="flex items-center gap-1">
                <input
                  type="number"
                  step="any"
                  value={draft}
                  onChange={e => setDraft(e.target.value)}
                  onKeyDown={e => { if (e.key === 'Enter') handleSave(t); if (e.key === 'Escape') setEditingKey(null); }}
                  className="w-[72px] bg-[#09090b] border border-blue-500/50 text-white px-2 py-1 rounded text-[11px] font-mono focus:outline-none"
                  autoFocus
                />
                <button onClick={() => handleSave(t)} disabled={saving} className="text-emerald-400 hover:text-emerald-300 text-[12px] p-1 disabled:opacity-30">✓</button>
                <button onClick={() => setEditingKey(null)} className="text-zinc-500 hover:text-zinc-300 text-[12px] p-1">✕</button>
              </div>
            ) : (
              <button
                onClick={() => handleEdit(t)}
                className={`font-mono text-[12px] font-bold px-2.5 py-1 rounded-md border transition-all ${
                  isNever
                    ? 'bg-purple-500/15 border-purple-500/30 text-purple-400'
                    : 'bg-zinc-800/80 border-border hover:border-border-strong hover:bg-zinc-700/80 text-white'
                }`}
              >
                {isNever ? 'NEVER' : formatValue(t.threshold_value, meta.unit)}
              </button>
            )}

            {/* Seasonal multipliers */}
            {(t.boost_peak_multiplier !== 1.0 || t.peak_multiplier !== 1.0) && (
              <div className="flex gap-1">
                {t.boost_peak_multiplier !== 1.0 && (
                  <span className="text-[8px] bg-amber-500/10 text-amber-400/80 px-1 py-0.5 rounded font-mono">🔥×{t.boost_peak_multiplier}</span>
                )}
                {t.peak_multiplier !== 1.0 && (
                  <span className="text-[8px] bg-red-500/10 text-red-400/80 px-1 py-0.5 rounded font-mono">🎄×{t.peak_multiplier}</span>
                )}
              </div>
            )}

            {/* Suggestion */}
            {t.suggested_value != null && (
              <div className="flex items-center gap-1">
                <span className="text-[9px] text-amber-400 font-mono">💡{t.suggested_value}</span>
                <button
                  onClick={() => onApprove(t.threshold_key, t.strategy_id, t.product_family)}
                  disabled={saving}
                  className="text-[9px] text-emerald-400 font-semibold px-1.5 py-0.5 border border-emerald-500/30 rounded bg-emerald-500/10 hover:bg-emerald-500/20 disabled:opacity-30"
                >
                  ✓
                </button>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function formatValue(v: number, unit: string): string {
  if (unit === '$') return `$${v}`;
  if (unit === 'x') return `${v}x`;
  return `${v} ${unit}`;
}

/* ═══════════════════════════════════════════════════════════════
   Main: ThresholdEditor — Strategy tabs + split view
   ═══════════════════════════════════════════════════════════════ */
interface ThresholdEditorProps {
  grouped: StrategyGroup[];
  saving: boolean;
  onUpdate: (key: string, strategyId: string, family: string | null, value: number) => Promise<void>;
  onApprove: (key: string, strategyId: string, family: string | null) => Promise<void>;
  onStrategySelect?: (strategyId: string) => void;
}

export function ThresholdEditor({ grouped, saving, onUpdate, onApprove, onStrategySelect }: ThresholdEditorProps) {
  const [selectedStrategy, setSelectedStrategy] = useState('GLOBAL');
  const [highlightKeys, setHighlightKeys] = useState<string[]>([]);

  const currentGroup = useMemo(
    () => grouped.find(g => g.strategyId === selectedStrategy),
    [grouped, selectedStrategy]
  );

  const treeNodes = useMemo(
    () => currentGroup ? getTreeForStrategy(currentGroup.thresholds) : [],
    [currentGroup]
  );

  const meta = STRATEGY_META[selectedStrategy] || { icon: '📋', label: selectedStrategy, color: 'muted', desc: '' };

  return (
    <div>
      {/* Strategy selector tabs */}
      <div className="flex gap-1.5 flex-wrap mb-4 p-2 bg-surface/50 backdrop-blur border border-border rounded-xl">
        {grouped.map(g => {
          const m = STRATEGY_META[g.strategyId] || { icon: '📋', label: g.strategyId, color: 'muted', desc: '' };
          const isActive = selectedStrategy === g.strategyId;
          const hasSuggestions = g.thresholds.some(t => t.suggested_value != null);
          return (
            <button
              key={g.strategyId}
              onClick={() => { setSelectedStrategy(g.strategyId); setHighlightKeys([]); onStrategySelect?.(g.strategyId); }}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[11px] font-semibold transition-all ${
                isActive
                  ? 'bg-blue-500/15 border border-blue-500/40 text-blue-300 shadow-[0_0_8px_rgba(59,130,246,0.1)]'
                  : 'border border-transparent text-subtle hover:text-muted hover:bg-white/[.03]'
              }`}
            >
              <span>{m.icon}</span>
              <span>{m.label}</span>
              {hasSuggestions && <span className="text-amber-400 text-[9px]">💡</span>}
            </button>
          );
        })}
      </div>

      {/* Strategy description */}
      <div className="flex items-center gap-2 mb-4 px-1">
        <span className="text-lg">{meta.icon}</span>
        <div>
          <div className="text-[13px] font-bold">{meta.label}</div>
          <div className="text-[11px] text-subtle">{meta.desc}</div>
        </div>
        <Badge variant="muted" className="ml-auto">{currentGroup?.thresholds.length || 0} thresholds</Badge>
      </div>

      {/* Split view: Tree + Thresholds */}
      {currentGroup && (
        <div className="grid grid-cols-1 lg:grid-cols-[1.2fr_1fr] gap-4">
          {/* LEFT: Decision Tree */}
          <div className="bg-card border border-border rounded-lg p-4">
            <div className="text-[11px] font-bold text-subtle uppercase tracking-wider mb-3">Decision Flow</div>
            <DecisionTree nodes={treeNodes} highlightKeys={highlightKeys} />
          </div>

          {/* RIGHT: Editable Thresholds */}
          <div className="bg-card border border-border rounded-lg p-4">
            <div className="text-[11px] font-bold text-subtle uppercase tracking-wider mb-3">Thresholds</div>
            <ThresholdPanel
              thresholds={currentGroup.thresholds}
              saving={saving}
              highlightKeys={highlightKeys}
              setHighlightKeys={setHighlightKeys}
              onUpdate={onUpdate}
              onApprove={onApprove}
            />
          </div>
        </div>
      )}
    </div>
  );
}
