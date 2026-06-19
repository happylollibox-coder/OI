import { useState, useMemo, useEffect } from 'react';
import { PageHeader } from '../components/PageHeader';
import { Empty } from '../components/Empty';
import { Badge, ActionBadge } from '../components/Badge';
import { usePageSummary } from '../components/PageSummaryBar';
import { fM, fP, fOrd, ACTION_META } from '../utils';
import { termGrain, termGrainShort } from '../coachActuals';
import { useDoQueue, type DoQueueItem } from '../hooks/useDoQueue';
import { DecisionScorecard } from '../components/DecisionScorecard';
import { Copy, Check, Trash2, X, ChevronDown, ChevronRight, CheckCircle2, RotateCcw, ExternalLink, Download, Upload, AlertTriangle, RefreshCw } from 'lucide-react';
import type { DashboardData } from '../types';

/* ─── Action ordering: urgent first ─── */
const ACTION_ORDER = ['STOP_TERM', 'STOP_TARGET', 'STOP_SEASONAL', 'NEGATE_TERM', 'NEGATE_BOOST_SIMILAR_EXACT', 'REDUCE_BID', 'RESTORE_PRE_PEAK', 'REDUCE_TO_BASELINE', 'FIX_HERO', 'SWITCH_HERO', 'KEEP_TARGET', 'COOLDOWN_MONITOR', 'INCREASE_BID', 'PROMOTE_TO_EXACT', 'ADD_CROSS_SELL_TARGET', 'START_TERM', 'GUARDIAN_BUDGET_INCREASE', 'GUARDIAN_BUDGET_DECREASE', 'BLITZ_BUDGET_INCREASE', 'BLITZ_BUDGET_DECREASE', 'MONITOR_TARGET', 'KEEP', 'MONITOR'];

const ACTION_COLORS: Record<string, string> = {
  STOP_TERM: '#ef4444', STOP_TARGET: '#ef4444', STOP_SEASONAL: '#ef4444',
  NEGATE_TERM: '#ef4444', NEGATE_BOOST_SIMILAR_EXACT: '#ef4444',
  REDUCE_BID: '#f59e0b', RESTORE_PRE_PEAK: '#ef4444', REDUCE_TO_BASELINE: '#f59e0b',
  FIX_HERO: '#f59e0b', SWITCH_HERO: '#f59e0b',
  KEEP_TARGET: '#22c55e', INCREASE_BID: '#22c55e', COOLDOWN_MONITOR: '#6b7280',
  PROMOTE_TO_EXACT: '#3b82f6', ADD_CROSS_SELL_TARGET: '#3b82f6', START_TERM: '#a855f7',
  GUARDIAN_BUDGET_INCREASE: '#22c55e', BLITZ_BUDGET_INCREASE: '#22c55e',
  GUARDIAN_BUDGET_DECREASE: '#ef4444', BLITZ_BUDGET_DECREASE: '#f59e0b',
  MONITOR_TARGET: '#71717a', BUDGET_OK: '#71717a',
  // Legacy fallbacks
  STOP: '#ef4444', NEGATE: '#ef4444', KEEP: '#22c55e', BOOST: '#22c55e',
  SCALE_UP: '#22c55e', START: '#a855f7', MONITOR: '#71717a',
};

/* ─── Actions that show TARGETS (keywords) instead of search terms ─── */
const TARGET_LEVEL_ACTIONS = new Set(['INCREASE_BID', 'REDUCE_BID', 'STOP_TARGET', 'KEEP_TARGET', 'MONITOR_TARGET', 'SCALE_UP', 'BOOST', 'COOLDOWN_MONITOR', 'REDUCE_TO_BASELINE', 'RESTORE_PRE_PEAK', 'NEGATE_BOOST_SIMILAR_EXACT']);

interface ActionGroup {
  action: string;
  items: DoQueueItem[];
  // For target-level actions: group items by targeting keyword
  targets: { targeting: string; matchType: string; targetSpend8w: number; targetOrders8w: number; targetNetRoas8w: number; items: DoQueueItem[] }[];
}

interface CampaignGroup {
  campaign: string;
  actionGroups: ActionGroup[];
  totalCount: number;
  urgentCount: number;
  negateCount: number;
}

export function DoPage({ data, onNav }: { data: DashboardData; onNav?: (page: string) => void }) {
  const doQueue = useDoQueue();
  const [expandedCampaigns, setExpandedCampaigns] = useState<Set<string>>(new Set());
  const [expandedTargets, setExpandedTargets] = useState<Set<string>>(new Set());
  const [copiedCampaign, setCopiedCampaign] = useState<string | null>(null);
  const [showDone, setShowDone] = useState(false);
  const [showUploaded, setShowUploaded] = useState(false);

  /* ─── Auto-cleanup: remove uploaded items when no longer in data.actions ─── */
  useEffect(() => {
    if (doQueue.uploadedItems.length > 0 && data.actions?.length > 0) {
      doQueue.cleanupUploaded(data.actions);
    }
  }, [data.actions]);

  /* ─── End SQP Lookup ─── */

  /* ─── Group: Campaign → Action → Target/Keywords ─── */
  const campaignGroups = useMemo((): CampaignGroup[] => {
    const byCamp: Record<string, DoQueueItem[]> = {};
    for (const item of doQueue.items) {
      const c = item.campaign || 'Unassigned';
      if (!byCamp[c]) byCamp[c] = [];
      byCamp[c].push(item);
    }

    return Object.entries(byCamp).map(([campaign, items]) => {
      // Group items by action
      const byAction: Record<string, DoQueueItem[]> = {};
      for (const item of items) {
        if (!byAction[item.action]) byAction[item.action] = [];
        byAction[item.action].push(item);
      }

      const actionGroups: ActionGroup[] = Object.entries(byAction).map(([action, aItems]) => {
        // For target-level actions, sub-group by targeting keyword
        const isTargetLevel = TARGET_LEVEL_ACTIONS.has(action);
        let targets: ActionGroup['targets'] = [];

        if (isTargetLevel) {
          const byTarget: Record<string, DoQueueItem[]> = {};
          for (const item of aItems) {
            const t = item.targeting || item.search_term || 'Other';
            if (!byTarget[t]) byTarget[t] = [];
            byTarget[t].push(item);
          }
          targets = Object.entries(byTarget).map(([targeting, tItems]) => {
            const first = tItems[0];
            return {
              targeting,
              matchType: first.match_type || '',
              targetSpend8w: first.target_spend_8w || 0,
              targetOrders8w: first.target_orders_8w || 0,
              targetNetRoas8w: first.target_net_roas_8w || 0,
              items: tItems.sort((a, b) => (b.spend || 0) - (a.spend || 0)),
            };
          }).sort((a, b) => b.targetSpend8w - a.targetSpend8w);
        }

        return {
          action,
          items: aItems.sort((a, b) => (b.spend || 0) - (a.spend || 0)),
          targets,
        };
      }).sort((a, b) => {
        const ai = ACTION_ORDER.indexOf(a.action);
        const bi = ACTION_ORDER.indexOf(b.action);
        return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
      });

      const urgentCount = items.filter(i => ACTION_META[i.action]?.group === 'urgent').length;
      const negateCount = items.filter(i => ['NEGATE', 'NEGATE_TERM'].includes(i.action)).length;

      return { campaign, actionGroups, totalCount: items.length, urgentCount, negateCount };
    }).sort((a, b) => b.urgentCount - a.urgentCount || b.totalCount - a.totalCount);
  }, [doQueue.items]);

  // Group done items by completion date
  const doneGroups = useMemo(() => {
    const byDate: Record<string, DoQueueItem[]> = {};
    for (const item of doQueue.doneItems) {
      const dt = item.doneAt ? new Date(item.doneAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : 'Unknown';
      if (!byDate[dt]) byDate[dt] = [];
      byDate[dt].push(item);
    }
    return Object.entries(byDate).sort(([, a], [, b]) => (b[0].doneAt || 0) - (a[0].doneAt || 0));
  }, [doQueue.doneItems]);

  const totalItems = doQueue.items.length;
  const totalDone = doQueue.doneItems.length;
  const totalUploaded = doQueue.uploadedItems.length;
  const totalUrgent = campaignGroups.reduce((s, g) => s + g.urgentCount, 0);

  usePageSummary({
    title: 'DO',
    breadcrumbs: [
      { label: 'Home', onClick: () => window.dispatchEvent(new CustomEvent('nav', { detail: 'home' })) },
      { label: 'DO' },
    ],
    items: [
      { label: 'Queued', value: `${totalItems}` },
      { label: 'Done', value: `${totalDone}`, color: 'green' },
      { label: 'Uploaded', value: `${totalUploaded}`, color: 'blue' },
      { label: 'Urgent', value: `${totalUrgent}`, color: 'red' },
    ],
  });

  if (!doQueue.items.length && !doQueue.doneItems.length && !doQueue.uploadedItems.length) {
    return (
      <div className="animate-in">
        <PageHeader title="DO — Your Task Queue" subtitle="Keywords you decided to act on" />
        <DecisionScorecard />
        <Empty
          icon="📋"
          message="No tasks queued yet"
          hint="Go to the Actions page and click the + button next to any action badge to add keywords here."
        />
      </div>
    );
  }

  const toggleCampaign = (camp: string) => {
    setExpandedCampaigns(prev => {
      const n = new Set(prev);
      n.has(camp) ? n.delete(camp) : n.add(camp);
      return n;
    });
  };

  const expandAll = () => setExpandedCampaigns(new Set(campaignGroups.map(g => g.campaign)));
  const collapseAll = () => setExpandedCampaigns(new Set());

  const copyBlacklist = (campaign: string, group: CampaignGroup) => {
    const negateItems = group.actionGroups
      .filter(ag => ['NEGATE', 'NEGATE_TERM'].includes(ag.action))
      .flatMap(ag => ag.items);
    const keywords = negateItems.map(i => i.search_term).filter(Boolean);
    if (!keywords.length) return;
    navigator.clipboard.writeText(keywords.join('\n'));
    setCopiedCampaign(campaign);
    setTimeout(() => setCopiedCampaign(null), 2000);
  };

  const navigateToActions = () => onNav?.('actions');

  const toggleTarget = (key: string) => {
    setExpandedTargets(prev => {
      const n = new Set(prev);
      n.has(key) ? n.delete(key) : n.add(key);
      return n;
    });
  };

  /* ─── Action instruction: what will happen in Amazon ─── */
  const getActionInstruction = (item: DoQueueItem): { icon: string; lines: string[] } => {
    const cn = (item.campaign || '').toUpperCase();
    const campName = item.campaign || 'Unknown';

    if (item.action === 'STOP_TERM' || item.action === 'NEGATE_TERM' || item.action === 'STOP' || item.action === 'NEGATE' || item.action === 'NEGATE_EXACT' || item.action === 'NEGATE_BOOST_SIMILAR_EXACT' || item.action === 'NEGATE_PHRASE' || item.action === 'PROMOTE_TO_PEAK_PHRASE') {
      const matchTypeLabel = (item.action === 'NEGATE_PHRASE' || item.action === 'PROMOTE_TO_PEAK_PHRASE') ? 'NEGATIVE_PHRASE' : 'NEGATIVE_EXACT';
      const termVal = item.search_term || item.targeting || '';
      const isAsinNegate = /^B0[A-Z0-9]{8,}$/i.test(termVal);
      if (isAsinNegate) {
        return {
          icon: '⛔',
          lines: [`Add NEGATIVE_PRODUCT_TARGETING asin="${termVal.toUpperCase()}" to ${campName}`],
        };
      }
      return {
        icon: '⛔',
        lines: [`Add ${matchTypeLabel} "${termVal}" to ${campName}`],
      };
    }

    if (item.action === 'SWITCH_HERO') {
      return {
        icon: '🔄',
        lines: [`Add NEGATIVE_EXACT "${item.search_term}" to ${campName}`, `Switch advertised ASIN to hero product`],
      };
    }

    if (item.action === 'STOP_TARGET') {
      const mt = item.match_type ? item.match_type.toUpperCase() : 'TARGET';
      const bidStr = item.current_bid ? `$${item.current_bid.toFixed(2)}` : (item.cpc ? `$${item.cpc.toFixed(2)}` : '?');
      return {
        icon: '⏸',
        lines: [`Pause keyword "${item.targeting || item.search_term}" [${mt}] in ${campName} (current bid: ${bidStr})`],
      };
    }

    if (item.action === 'REDUCE_BID') {
      const mt = item.match_type ? item.match_type.toUpperCase() : 'TARGET';
      const currentBidVal = item.current_bid || item.cpc;
      const currentBid = currentBidVal ? `$${currentBidVal.toFixed(2)}` : '?';
      const newBid = item.recommended_bid
        ? `$${item.recommended_bid.toFixed(2)}`
        : (currentBidVal ? `$${Math.max(0.02, +(currentBidVal * 0.7).toFixed(2)).toFixed(2)}` : '?');
      const pct = item.recommended_bid && currentBidVal && currentBidVal > 0
        ? Math.round(((item.recommended_bid - currentBidVal) / currentBidVal) * 100)
        : -30;
      return {
        icon: '📉',
        lines: [`Update bid: ${currentBid} → ${newBid} (${pct > 0 ? '+' : ''}${pct}%) on "${item.targeting || item.search_term}" [${mt}] in ${campName}`],
      };
    }

    if (item.action === 'INCREASE_BID' || item.action === 'BOOST' || item.action === 'SCALE_UP') {
      const mt = item.match_type ? item.match_type.toUpperCase() : 'TARGET';
      const currentBidVal = item.current_bid || item.cpc;
      const currentBid = currentBidVal ? `$${currentBidVal.toFixed(2)}` : '?';
      const newBid = item.recommended_bid
        ? `$${item.recommended_bid.toFixed(2)}`
        : (currentBidVal ? `$${+(currentBidVal * 1.25).toFixed(2)}` : '?');
      const pct = item.recommended_bid && currentBidVal && currentBidVal > 0
        ? Math.round(((item.recommended_bid - currentBidVal) / currentBidVal) * 100)
        : 25;
      return {
        icon: '📈',
        lines: [`Update bid: ${currentBid} → ${newBid} (+${Math.abs(pct)}%) on "${item.targeting || item.search_term}" [${mt}] in ${campName}`],
      };
    }

    if (item.action === 'PROMOTE_TO_EXACT') {
      // Mirror the export: all values come from the EXACT_BOOST template, not hardcoded.
      const tmpls = data.strategy_campaign_templates || [];
      const spTmpl = tmpls.find(t => t.strategy_id === 'EXACT_BOOST' && t.ad_format === 'SP');
      const videoTmpl = tmpls.find(t => t.strategy_id === 'EXACT_BOOST' && t.ad_format === 'SB_VIDEO');
      const bidMin = spTmpl?.bid_min ?? 0.5;
      const bidMax = spTmpl?.bid_max ?? 2.0;
      const bid = item.cpc ? `$${Math.min(bidMax, Math.max(bidMin, +(item.cpc * 1.1).toFixed(2))).toFixed(2)}` : `$${bidMin.toFixed(2)}`;
      const spBudget = spTmpl?.daily_budget ?? null;
      const spTos = spTmpl?.top_of_search_pct ?? 0;
      const videoBudget = videoTmpl?.daily_budget ?? null;
      const productPrefix = cn.match(/^(BOTTLE|BOX|ME|FRESH)/)?.[1] || 'PRODUCT';
      const kwShort = item.search_term.split(' ').slice(0, 4).join(' ');
      const spCampName = `${productPrefix}-SP/EXACT (Boost, ${kwShort})`;
      const videoCampName = `${productPrefix}-VIDEO/EXACT (Boost, ${kwShort})`;
      const tosStr = spTos > 0 ? ` + TOS ${spTos}%` : '';
      return {
        icon: '🚀',
        lines: [
          `Create SP campaign: ${spCampName}`,
          `  Bid: ${bid} · Budget: ${spBudget != null ? `$${spBudget}/day` : '—'} · DOWN_ONLY${tosStr}`,
          `Create SB Video: ${videoCampName}`,
          `  Bid: ${bid} · Budget: ${videoBudget != null ? `$${videoBudget}/day` : '—'}`,
        ],
      };
    } else if (item.action === 'PROMOTE_TO_PEAK_PHRASE') {
      const theme = item.seasonal_theme || 'General Peak';
      return {
        icon: '🚀',
        lines: [
          `Create SP/EXACT (Seasonal Peak - ${theme}) campaign`,
          `Add EXACT match "${item.search_term}" with bid $1.50`,
        ],
      };
    }

    if (item.action === 'ADD_CROSS_SELL_TARGET') {
      // Mirror the export: all values come from the PRODUCT_DEFENSE template.
      const tmpls = data.strategy_campaign_templates || [];
      const spTmpl = tmpls.find(t => t.strategy_id === 'PRODUCT_DEFENSE' && t.ad_format === 'SP');
      const bid = spTmpl?.bid_min != null ? `$${spTmpl.bid_min.toFixed(2)}` : '—';
      const budget = spTmpl?.daily_budget ?? null;
      const targetAsin = (item.targeting || '').replace(/^asin="?|"?$/gi, '').toUpperCase();
      return {
        icon: '🔁',
        lines: [
          `Create SP product-targeting campaign (PRODUCT_DEFENSE)`,
          `Advertise ${item.product} on ${item.targeting || `asin="${targetAsin}"`}`,
          `  Bid: ${bid} · Budget: ${budget != null ? `$${budget}/day` : '—'} · product-page boost`,
        ],
      };
    }

    if (item.action === 'START_TERM' || item.action === 'START') {
      return {
        icon: '✨',
        lines: [`Start advertising "${item.search_term}" — SQP shows organic demand, no ads targeting yet`],
      };
    }

    if (item.action === 'REMOVE_NEGATIVE') {
      return {
        icon: '🗑️',
        lines: [`Archive negative "${item.search_term}" in ${campName} — it blocks a converting term`],
      };
    }

    // Budget actions
    if (item.action.includes('BUDGET')) {
      const currentBudget = (item as any).current_budget ?? '?';
      const recBudget = (item as any).recommended_budget ?? '?';
      const isIncrease = item.action.includes('INCREASE');
      const isOk = item.action === 'BUDGET_OK';
      if (isOk) {
        return { icon: '✅', lines: [`Budget $${currentBudget}/day is on track for ${campName}`] };
      }
      return {
        icon: isIncrease ? '📈' : '📉',
        lines: [`Update daily budget: $${currentBudget} → $${recBudget} in ${campName}`],
      };
    }

    return { icon: '👁', lines: [`Monitor "${item.search_term}" in ${campName}`] };
  };

  /* ─── Render a search term row ─── */
  const renderSearchTermRow = (item: DoQueueItem, indent = false) => {
    const instruction = getActionInstruction(item);
    const grain = (item.search_term || item.targeting) ? termGrain(item) : null;
    return (
    <div key={item.id} className={indent ? 'pl-8' : ''}>
      <div
        className={`flex items-center gap-3 px-4 py-2 text-[11px] hover:bg-card-hover transition-colors group`}
      >
        <button
          onClick={() => doQueue.markDone(item.id)}
          className="w-5 h-5 rounded-full border-2 border-border-strong flex items-center justify-center shrink-0 hover:border-emerald-400 hover:bg-emerald-500/15 transition-all group/check"
          title="Mark as done"
        >
          <Check size={10} className="text-transparent group-hover/check:text-emerald-400" />
        </button>
        <button
          onClick={navigateToActions}
          className="font-medium text-blue-400 hover:text-blue-300 hover:underline transition-colors text-left min-w-[180px] flex items-center gap-1 cursor-pointer"
          title="View in Actions page"
        >
          {grain && <span className="text-[8px] font-mono uppercase tracking-wider text-faint shrink-0 px-1 py-px rounded border border-border" title={grain}>{termGrainShort(grain)}</span>}
          {item.search_term || item.campaign || '--'}
          <ExternalLink size={9} className="opacity-0 group-hover:opacity-50" />
        </button>
        <div className="flex-1" />
        <span className="w-16 text-right font-mono text-faint shrink-0 text-[10px]">{fM(item.spend)}</span>
        <span className="w-14 text-right font-mono text-faint shrink-0 text-[10px]">{fOrd(item.orders)}</span>
        <span className="w-14 text-right font-mono text-faint shrink-0 text-[10px]">{fM(item.cpc)}</span>
        <span className="w-14 text-right font-mono text-faint shrink-0 text-[10px]">{fP(item.conv_rate)}</span>
        <button
          onClick={() => doQueue.removeItem(item.id)}
          className="w-5 h-5 rounded-md flex items-center justify-center text-faint hover:text-red-400 hover:bg-red-500/15 transition-all opacity-0 group-hover:opacity-100 shrink-0"
          title="Remove from queue"
        >
          <X size={11} />
        </button>
      </div>
      {/* Action instruction */}
      <div className={`px-4 pb-2 ${indent ? '' : 'pl-12'}`}>
        <div className="flex items-start gap-1.5 text-[10px] text-subtle/70 font-mono leading-relaxed bg-inset rounded-md px-2.5 py-1.5 border border-border-faint">
          <span className="shrink-0">{instruction.icon}</span>
          <div className="flex flex-col gap-px">
            {instruction.lines.map((line, i) => (
              <span key={i} className={line.startsWith('  ') ? 'pl-3 text-faint' : ''}>{line}</span>
            ))}
          </div>
        </div>
      </div>
    </div>
    );
  };

  /* ─── Export Amazon Bulksheet v2.0 XLSX ─── */
  const exportBulksheet = () => {
    if (!doQueue.items.length) return;
    import('xlsx').then((XLSX) => {
      // ═══ Brand Asset Config (fetched dynamically from DIM_PRODUCT_CREATIVES via Cube.js) ═══
      let defaultBrandEntityId = '';
      let defaultBrandName = 'Happy Lolli';
      const VIDEO_MEDIA_IDS: Record<string, string> = {};

      const creatives = data.product_creatives || [];
      for (const c of creatives) {
        if (c.video_asset_id) VIDEO_MEDIA_IDS[c.product_family] = c.video_asset_id;
        if (c.brand_entity_id) defaultBrandEntityId = c.brand_entity_id;
        if (c.brand_name) defaultBrandName = c.brand_name;
      }

      const BRAND_ENTITY_ID = defaultBrandEntityId;
      const BRAND_NAME = defaultBrandName;

      // ═══ SP Headers (Sponsored Products upload format) ═══
      const SP_HEADERS = [
        'Product', 'Entity', 'Operation',
        'Campaign ID', 'Ad Group ID', 'Portfolio ID', 'Ad ID', 'Keyword ID', 'Product Targeting ID',
        'Campaign Name', 'Ad Group Name',
        'Campaign Name (Informational only)', 'Ad Group Name (Informational only)',
        'Portfolio Name (Informational only)',
        'Start Date', 'End Date', 'Targeting Type', 'State',
        'Campaign State (Informational only)', 'Ad Group State (Informational only)',
        'Daily Budget', 'SKU', 'ASIN (Informational only)',
        'Eligibility Status (Informational only)', 'Reason for Ineligibility (Informational only)',
        'Ad Group Default Bid', 'Ad Group Default Bid (Informational only)',
        'Bid', 'Keyword Text', 'Native Language Keyword', 'Native Language Locale',
        'Match Type', 'Bidding Strategy', 'Placement', 'Percentage',
        'Product Targeting Expression', 'Resolved Product Targeting Expression (Informational only)',
      ];

      // ═══ SB Headers (Sponsored Brands upload format) ═══
      const SB_HEADERS = [
        'Product', 'Entity', 'Operation',
        'Campaign Id', 'Ad Group Id', 'Ad Id', 'Keyword Id', 'Draft Campaign Id', 'Portfolio Id',
        'Campaign Name', 'Ad Group Name', 'Ad Name', 'Start Date', 'End Date', 'State',
        'Budget Type', 'Budget',
        'Bid Optimization', 'Bid Multiplier',
        'Bid', 'Keyword Text', 'Match Type',
        'Product Targeting Expression',
        'Ad Format', 'Landing Page URL', 'Landing page ASINs',
        'Brand Entity Id', 'Brand Name',
        'Creative Headline', 'Creative ASINs', 'Video asset IDs', 'Creative Type',
      ];

      const PORTFOLIO_MAP: Record<string, string> = {
        'BOX': '6487122589020',
        'BRAND': '111579864441847',
        'FRESH': '19847592608433',
        'BOTTLE': '81817188183510',
        'ME': '41310184067669',
      };

      // ═══ ASIN / SKU resolution maps ═══
      // Primary: items queued after 2026-06-12 carry item.asin from ActionRow.asin.
      // Fallback for older items: resolve ASIN from supply_chain (asin → product_short_name)
      // and SKU from products (asin → sku loaded from DIM_PRODUCT via Product cube).
      const asinByShortName = new Map<string, string>(
        (data.supply_chain || []).filter(r => r.asin && r.product_short_name).map(r => [r.product_short_name, r.asin])
      );
      const skuByAsin = new Map<string, string>(
        (data.products || []).filter(r => r.asin && r.sku).map(r => [r.asin, r.sku])
      );

      // ═══ Helper: detect Product Targeting entities (ASIN targets + AUTO groups) ═══
      const AUTO_TARGETING_GROUPS = new Set(['close-match', 'loose-match', 'substitutes', 'complements']);
      const isProductTargeting = (item: DoQueueItem): boolean => {
        const mt = (item.match_type || '').toUpperCase();
        // SQL now provides PRODUCT_TARGETING for product targeting entities
        if (mt === 'PRODUCT_TARGETING' || mt.startsWith('ASIN')) return true;
        // Fallback: targeting expression starts with asin= (Amazon format)
        if (/^asin=/i.test(item.targeting || '')) return true;
        // Fallback: targeting expression starts with category= (Amazon category targeting)
        if (/^category=/i.test(item.targeting || '')) return true;
        // Fallback: targeting looks like a raw ASIN (B0 + 8+ alphanumeric)
        if (!mt && /^B0[A-Z0-9]{8,}$/i.test(item.targeting || '')) return true;
        // Fallback: AUTO campaign targeting groups
        if (AUTO_TARGETING_GROUPS.has((item.targeting || '').toLowerCase())) return true;
        return false;
      };

      // ═══ Helper: format Product Targeting Expression for Amazon ═══
      // For Update operations, the Product Targeting ID is sufficient — Amazon
      // looks up the expression from the ID. We only populate the expression 
      // when we have the correct unresolved format.
      const formatPTExpression = (targeting: string): string => {
        // AUTO targeting groups use their name directly (close-match, substitutes, etc.)
        if (AUTO_TARGETING_GROUPS.has(targeting.toLowerCase())) return targeting;
        // If already in asin="..." format, keep as-is
        if (/^asin=/i.test(targeting)) return targeting;
        // Category targets: our data has the resolved name (e.g. "Kids' Scrapbooking Kits")
        // but Amazon requires the unresolved numeric node ID. Omit expression — 
        // for Update ops the Product Targeting ID is enough.
        if (/^category=/i.test(targeting)) return '';
        // If looks like a raw ASIN, wrap in asin="..." format
        if (/^B0[A-Z0-9]{8,}$/i.test(targeting)) return `asin="${targeting}"`;
        return targeting;
      };

      const spRows: Record<string, string>[] = [];
      const sbRows: Record<string, string>[] = [];

      // ═══ Dedup guard: never emit Create rows for a campaign that already exists ═══
      // Sources: live campaigns (Ads cube, ~1–2d lag) + campaigns the coach already tracks.
      const normCamp = (s: string) => s.trim().toUpperCase();
      const existingCampaigns = new Set<string>();
      for (const r of (data.ads_7d || [])) {
        if (r.row_type === 'campaign' && r.campaign_name) existingCampaigns.add(normCamp(r.campaign_name));
      }
      for (const c of (data.coach_campaigns || [])) {
        if (c.campaign_name) existingCampaigns.add(normCamp(c.campaign_name));
      }
      // Returns true only if this campaign is new (not already live AND not already
      // queued earlier in this export). Registers the name so later rows dedup too.
      const createdInExport = new Set<string>();
      const claimNewCampaign = (name: string): boolean => {
        const key = normCamp(name);
        if (existingCampaigns.has(key) || createdInExport.has(key)) return false;
        createdInExport.add(key);
        return true;
      };

      // ═══ Campaign-creation defaults come from DIM_STRATEGY_CAMPAIGN_TEMPLATE (no hardcoding) ═══
      const campaignTemplates = data.strategy_campaign_templates || [];
      const findTemplate = (strategyId: string, adFormat: string) =>
        campaignTemplates.find(t => t.strategy_id === strategyId && t.ad_format === adFormat);

      for (const item of doQueue.items) {
        const campId = item.campaign_id || '';
        const campName = item.campaign || '';
        const adGroupId = item.ad_group_id || '';

        // Determine if this is an SB campaign (Sponsored Brands / Video)
        const ct = (item.campaign_type || '').toUpperCase();
        const cn = campName.toUpperCase();
        const isSB = ct === 'SB' || ct === 'SBV' || ct.includes('BRAND') || ct.includes('VIDEO')
          || cn.includes('SBV') || cn.includes('VIDEO') || cn.includes('STORE');

        const spBase: Record<string, string> = {
          'Product': 'Sponsored Products',
          'Campaign ID': campId,
          'Ad Group ID': adGroupId,
          'Campaign Name (Informational only)': campName,
        };

        // ═══════════════════════════════════════════════════════════
        // TIER 2: Per-SEARCH-TERM actions (Create operations)
        // Uses: item.search_term as Keyword Text
        // ═══════════════════════════════════════════════════════════
        if (item.action === 'STOP_TERM' || item.action === 'NEGATE_TERM' || item.action === 'SWITCH_HERO'
            || item.action === 'STOP' || item.action === 'NEGATE' || item.action === 'NEGATE_EXACT'
            || item.action === 'NEGATE_PHRASE' || item.action === 'NEGATE_BOOST_SIMILAR_EXACT'
            || item.action === 'PROMOTE_TO_PEAK_PHRASE') {
          
          const isPhrase = item.action === 'NEGATE_PHRASE' || item.action === 'PROMOTE_TO_PEAK_PHRASE';
          // Force campaign level if no Ad Group ID is known, or if it's a phrase negative
          const isCampaignLevel = !adGroupId || isPhrase;

          if (isSB) {
            // SB campaigns: add negative keyword (SB only supports Ad Group level Negative Keywords)
            const matchTypeSB = isPhrase ? 'negativePhrase' : 'negativeExact';
            
            const sbRow: Record<string, string> = {
              'Product': 'Sponsored Brands',
              'Entity': 'Negative Keyword',
              'Operation': 'Create',
              'Campaign Id': campId,
              'Campaign Name': campName,
              'Ad Group Id': adGroupId || '', // Amazon requires Ad Group ID for SB negatives
              'Keyword Text': item.search_term,
              'Match Type': matchTypeSB,
              'State': 'enabled',
            };
            sbRows.push(sbRow);
          } else {
            // SP campaigns: detect if this is an ASIN to negate via Product Targeting
            const termToNegate = item.search_term || item.targeting || '';
            const isAsinNegate = /^B0[A-Z0-9]{8,}$/i.test(termToNegate) || /^asin=/i.test(termToNegate);

            if (isAsinNegate && !isPhrase) {
              // ASIN negation → Negative Product Targeting
              const entityPT = isCampaignLevel ? 'Campaign Negative Product Targeting' : 'Negative Product Targeting';
              const asinVal = termToNegate.replace(/^asin="?|"?$/gi, '').toUpperCase();
              const spRow: Record<string, string> = {
                ...spBase,
                'Entity': entityPT,
                'Operation': 'Create',
                'Product Targeting Expression': `asin="${asinVal}"`,
                'State': 'ENABLED',
              };
              if (isCampaignLevel) {
                delete spRow['Ad Group ID'];
              }
              spRows.push(spRow);
            } else {
              // Keyword negation → Negative Keyword
              const entitySP = isCampaignLevel ? 'Campaign Negative Keyword' : 'Negative Keyword';
              // Match type is always NEGATIVE_EXACT/NEGATIVE_PHRASE — campaign scope
              // is conveyed by Entity = 'Campaign Negative Keyword', not by match type
              const matchTypeSP = isPhrase ? 'NEGATIVE_PHRASE' : 'NEGATIVE_EXACT';
                
              const spRow: Record<string, string> = {
                ...spBase,
                'Entity': entitySP,
                'Operation': 'Create',
                'Keyword Text': termToNegate,
                'Match Type': matchTypeSP,
                'State': 'ENABLED',
              };
              if (isCampaignLevel) {
                delete spRow['Ad Group ID'];
              }
              spRows.push(spRow);
            }
          }

        // ═══════════════════════════════════════════════════════════
        // TIER 1: Per-TARGET actions (Update operations)
        // ASIN targets → Entity: Product Targeting + Product Targeting ID
        // Keywords     → Entity: Keyword + Keyword ID + Match Type
        // ═══════════════════════════════════════════════════════════
        } else if (item.action === 'REDUCE_BID') {
          // Use coach recommended bid, fallback to CPC × 0.70
          const bid = item.recommended_bid
            ? String(item.recommended_bid)
            : (item.cpc ? String(Math.max(0.02, +(item.cpc * 0.7).toFixed(2))) : '');
          const isAsin = isProductTargeting(item);
          console.log('[Bulksheet] REDUCE_BID', { keyword_id: item.keyword_id, match_type: item.match_type, targeting: item.targeting, isAsin, bid, isSB });
          if (isSB) {
            // SB campaigns: update keyword on the Sponsored Brands sheet
            const mt = (item.match_type || 'broad').toLowerCase();
            sbRows.push({
              'Product': 'Sponsored Brands',
              'Entity': 'Keyword',
              'Operation': 'Update',
              'Campaign Id': campId,
              'Ad Group Id': adGroupId,
              'Keyword Id': item.keyword_id,
              'Keyword Text': item.targeting || item.search_term,
              'Match Type': mt,
              'Bid': bid,
              'State': 'enabled',
            });
          } else if (isAsin) {
            spRows.push({
              ...spBase,
              'Entity': 'Product Targeting',
              'Operation': 'Update',
              'Product Targeting ID': item.keyword_id,
              'Product Targeting Expression': formatPTExpression(item.targeting || item.search_term),
              'Bid': bid,
              'State': 'ENABLED',
            });
          } else {
            const mt = item.match_type || 'BROAD';
            spRows.push({
              ...spBase,
              'Entity': 'Keyword',
              'Operation': 'Update',
              'Keyword ID': item.keyword_id,
              'Keyword Text': item.targeting || item.search_term,
              'Match Type': mt.toUpperCase(),
              'Bid': bid,
              'State': 'ENABLED',
            });
          }

        } else if (item.action === 'STOP_TARGET') {
          const isAsin = isProductTargeting(item);
          console.log('[Bulksheet] STOP_TARGET', { keyword_id: item.keyword_id, match_type: item.match_type, targeting: item.targeting, isAsin, isSB });
          if (isSB) {
            // SB campaigns: pause keyword on the Sponsored Brands sheet
            const mt = (item.match_type || 'broad').toLowerCase();
            sbRows.push({
              'Product': 'Sponsored Brands',
              'Entity': 'Keyword',
              'Operation': 'Update',
              'Campaign Id': campId,
              'Ad Group Id': adGroupId,
              'Keyword Id': item.keyword_id,
              'Keyword Text': item.targeting || item.search_term,
              'Match Type': mt,
              'State': 'paused',
            });
          } else if (isAsin) {
            spRows.push({
              ...spBase,
              'Entity': 'Product Targeting',
              'Operation': 'Update',
              'Product Targeting ID': item.keyword_id,
              'Product Targeting Expression': formatPTExpression(item.targeting || item.search_term),
              'State': 'PAUSED',
            });
          } else {
            const mt = item.match_type || 'BROAD';
            spRows.push({
              ...spBase,
              'Entity': 'Keyword',
              'Operation': 'Update',
              'Keyword ID': item.keyword_id,
              'Keyword Text': item.targeting || item.search_term,
              'Match Type': mt.toUpperCase(),
              'State': 'PAUSED',
            });
          }

        } else if (item.action === 'INCREASE_BID' || item.action === 'BOOST' || item.action === 'SCALE_UP') {
          // Use coach recommended bid, fallback to CPC × 1.25
          const bid = item.recommended_bid
            ? String(item.recommended_bid)
            : (item.cpc ? String(+(item.cpc * 1.25).toFixed(2)) : '');
          const isAsin = isProductTargeting(item);
          console.log('[Bulksheet] INCREASE_BID', { keyword_id: item.keyword_id, match_type: item.match_type, targeting: item.targeting, isAsin, bid, isSB });
          if (isSB) {
            // SB campaigns: update keyword on the Sponsored Brands sheet
            const mt = (item.match_type || 'broad').toLowerCase();
            sbRows.push({
              'Product': 'Sponsored Brands',
              'Entity': 'Keyword',
              'Operation': 'Update',
              'Campaign Id': campId,
              'Ad Group Id': adGroupId,
              'Keyword Id': item.keyword_id,
              'Keyword Text': item.targeting || item.search_term,
              'Match Type': mt,
              'Bid': bid,
              'State': 'enabled',
            });
          } else if (isAsin) {
            spRows.push({
              ...spBase,
              'Entity': 'Product Targeting',
              'Operation': 'Update',
              'Product Targeting ID': item.keyword_id,
              'Product Targeting Expression': formatPTExpression(item.targeting || item.search_term),
              'Bid': bid,
              'State': 'ENABLED',
            });
          } else {
            const mt = item.match_type || 'BROAD';
            spRows.push({
              ...spBase,
              'Entity': 'Keyword',
              'Operation': 'Update',
              'Keyword ID': item.keyword_id,
              'Keyword Text': item.targeting || item.search_term,
              'Match Type': mt.toUpperCase(),
              'Bid': bid,
              'State': 'ENABLED',
            });
          }

        // ═══════════════════════════════════════════════════════════
        // TIER 2: PROMOTE_TO_EXACT — Create new campaigns
        // Uses: item.search_term as the new exact keyword
        // ═══════════════════════════════════════════════════════════
        } else if (item.action === 'PROMOTE_TO_EXACT') {
          // EXACT_BOOST recipe — budget / TOS / bid bounds all sourced from
          // DIM_STRATEGY_CAMPAIGN_TEMPLATE (no hardcoded defaults).
          const spTmpl = findTemplate('EXACT_BOOST', 'SP');
          const videoTmpl = findTemplate('EXACT_BOOST', 'SB_VIDEO');
          const bidMin = spTmpl?.bid_min ?? 0.5;
          const bidMax = spTmpl?.bid_max ?? 2.0;
          const bid = item.cpc
            ? String(Math.min(bidMax, Math.max(bidMin, +(item.cpc * 1.1).toFixed(2))))
            : String(bidMin);
          // Resolve ASIN: use item.asin (set since 2026-06-12), fall back to supply_chain lookup by short-name
          const asin = item.asin || asinByShortName.get(item.product) || '';
          // Resolve SKU from DIM_PRODUCT (via products loader); never write product short-name
          const sku = skuByAsin.get(asin) || '';
          if (!asin) console.warn('[Bulksheet] unresolved ASIN/SKU for', item.product);
          if (asin && !sku) console.warn('[Bulksheet] unresolved ASIN/SKU for', item.product, '— ASIN found but SKU missing, check DIM_PRODUCT');
          const kwShort = item.search_term.split(' ').slice(0, 4).join(' ');

          let productPrefix = cn.match(/^(BOTTLE|BOX|ME|FRESH|BRAND)/)?.[1];
          const productShortUpper = item.product.toUpperCase();
          if (productShortUpper.includes('ME')) productPrefix = 'ME';
          else if (productShortUpper.includes('BOX')) productPrefix = 'BOX';
          else if (productShortUpper.includes('FRESH')) productPrefix = 'FRESH';
          else if (productShortUpper.includes('BOTTLE')) productPrefix = 'BOTTLE';
          productPrefix = productPrefix || 'PRODUCT';
          const startDate = new Date().toISOString().slice(0, 10).replace(/-/g, '');
          const portfolioId = PORTFOLIO_MAP[productPrefix] || '';

          // ── SP/EXACT Boost Campaign (Sponsored Products sheet) ──
          const spCampName = `${productPrefix}-SP/EXACT (Boost, ${kwShort})`;
          const spAdGroupName = `${productPrefix} - Exact Boost`;
          if (!spTmpl) {
            console.warn('[Bulksheet] No EXACT_BOOST/SP template loaded — skipping SP campaign creation for', item.product);
          } else if (claimNewCampaign(spCampName)) {
            spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Campaign', 'Operation': 'Create',
              'Campaign ID': spCampName, 'Campaign Name': spCampName, 'Portfolio ID': portfolioId,
              'Daily Budget': String(spTmpl.daily_budget ?? ''), 'Targeting Type': 'MANUAL',
              'Bidding Strategy': 'Dynamic bids - down only', 'Start Date': startDate, 'State': 'ENABLED' });
            // Top-of-search placement adjustment — only when the recipe sets one (> 0)
            if ((spTmpl.top_of_search_pct ?? 0) > 0) {
              spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Bidding Adjustment', 'Operation': 'Create',
                'Campaign ID': spCampName, 'Campaign Name': spCampName, 'Placement': 'Placement Top',
                'Percentage': String(spTmpl.top_of_search_pct) });
            }
            spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Ad Group', 'Operation': 'Create',
              'Campaign ID': spCampName, 'Campaign Name': spCampName,
              'Ad Group ID': spAdGroupName, 'Ad Group Name': spAdGroupName,
              'Ad Group Default Bid': bid, 'State': 'ENABLED' });
            spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Keyword', 'Operation': 'Create',
              'Campaign ID': spCampName, 'Campaign Name': spCampName,
              'Ad Group ID': spAdGroupName, 'Ad Group Name': spAdGroupName,
              'Keyword Text': item.search_term, 'Match Type': 'EXACT', 'Bid': bid, 'State': 'ENABLED' });
            spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Product Ad', 'Operation': 'Create',
              'Campaign ID': spCampName, 'Campaign Name': spCampName,
              'Ad Group ID': spAdGroupName, 'Ad Group Name': spAdGroupName,
              ...(sku ? { 'SKU': sku } : asin ? { 'ASIN (Informational only)': asin } : {}),
              'State': 'ENABLED' });
          }


          // ── VIDEO/EXACT Boost Campaign (Sponsored Brands sheet) ──
          const videoCampName = `${productPrefix}-VIDEO/EXACT (Boost, ${kwShort})`;
          const videoAdGroupName = `${productPrefix} - Video Exact Boost`;
          const videoMediaId = VIDEO_MEDIA_IDS[productPrefix] || '';
          if (videoMediaId && videoTmpl && claimNewCampaign(videoCampName)) {
            // 1. Campaign Row
            sbRows.push({
              'Product': 'Sponsored Brands', 'Entity': 'Campaign', 'Operation': 'Create',
              'Campaign Id': videoCampName, 'Campaign Name': videoCampName, 'Portfolio Id': portfolioId,
              'Start Date': startDate, 'State': 'enabled',
              'Budget Type': 'daily', 'Budget': String(videoTmpl.daily_budget ?? ''),
              'Bid Optimization': 'true',
              'Brand Entity Id': BRAND_ENTITY_ID, 'Brand Name': BRAND_NAME
            });

            // 2. Ad Group Row
            sbRows.push({
              'Product': 'Sponsored Brands', 'Entity': 'Ad Group', 'Operation': 'Create',
              'Campaign Id': videoCampName, 'Campaign Name': videoCampName,
              'Ad Group Id': videoAdGroupName, 'Ad Group Name': videoAdGroupName,
              'State': 'enabled'
            });

            // 3. Video Ad Row
            const videoAdName = `${productPrefix} - Video Ad`;
            console.log('[SB Debug] Video Ad values:', { asin, sku, videoMediaId, BRAND_ENTITY_ID, productPrefix });
            if (!asin) console.warn('[Bulksheet] unresolved ASIN/SKU for', item.product, '— Creative ASINs will be blank');
            sbRows.push({
              'Product': 'Sponsored Brands', 'Entity': 'Video Ad', 'Operation': 'Create',
              'Campaign Id': videoCampName, 'Campaign Name': videoCampName,
              'Ad Group Id': videoAdGroupName, 'Ad Group Name': videoAdGroupName,
              'Ad Id': videoAdName, 'Ad Name': videoAdName,
              'State': 'enabled',
              'Ad Format': 'video',
              'Creative ASINs': asin, // resolved ASIN (never product short-name)
              'Video asset IDs': videoMediaId,
              'Creative Type': 'video'
            });

            // 4. Keyword Row
            sbRows.push({
              'Product': 'Sponsored Brands', 'Entity': 'Keyword', 'Operation': 'Create',
              'Campaign Id': videoCampName, 'Campaign Name': videoCampName,
              'Ad Group Id': videoAdGroupName, 'Ad Group Name': videoAdGroupName,
              'Keyword Text': item.search_term, 'Match Type': 'exact',
              'Bid': bid, 'State': 'enabled'
            });
          }
        } else if (item.action === 'ADD_CROSS_SELL_TARGET') {
          // TIER 2: ADD_CROSS_SELL_TARGET — advertise product B on product A's
          // listing via a Sponsored Products *product-targeting* campaign. Budget,
          // bid bounds and placement all come from the PRODUCT_DEFENSE template
          // (no fabricated values, per the coacher no-auto-fill rule).
          const spTmpl = findTemplate('PRODUCT_DEFENSE', 'SP');
          if (!spTmpl) {
            console.warn('[Bulksheet] No PRODUCT_DEFENSE/SP template loaded — skipping cross-sell campaign for', item.product);
          } else {
            const bidMin = spTmpl.bid_min ?? 0.3;
            // Brand-new product target: no per-pair CPC history, so start at the
            // template's floor bid (a deliberate template value, not a guess).
            const bid = String(bidMin);
            // Advertised product (B) — queue builder sets item.asin = advertise_asin.
            const asin = item.asin || asinByShortName.get(item.product) || item.product;
            const sku = skuByAsin.get(asin) || '';
            if (!asin) console.warn('[Bulksheet] cross-sell: unresolved advertised ASIN for', item.product);
            else if (!sku) console.warn('[Bulksheet] cross-sell: ASIN', asin, 'has no SKU in DIM_PRODUCT');
            // Target listing (A) — the asin="..." expression carried on the queue item.
            const targetExpr = formatPTExpression(item.targeting || '');
            const targetAsin = (item.targeting || '').replace(/^asin="?|"?$/gi, '').toUpperCase();
            // Resolve the advertised product's family → portfolio (blank if unknown).
            const advProduct = (data.products || []).find(p => p.asin === asin);
            const advName = (advProduct?.product_short_name || advProduct?.parent_name || '').toUpperCase();
            let productPrefix = 'PRODUCT';
            if (advName.includes('ME')) productPrefix = 'ME';
            else if (advName.includes('BOX')) productPrefix = 'BOX';
            else if (advName.includes('FRESH')) productPrefix = 'FRESH';
            else if (advName.includes('BOTTLE')) productPrefix = 'BOTTLE';
            const portfolioId = PORTFOLIO_MAP[productPrefix] || '';
            const startDate = new Date().toISOString().slice(0, 10).replace(/-/g, '');

            const xsCampName = `${productPrefix}-SP/DEFENSE (Cross-sell ${asin} → ${targetAsin})`;
            const xsAdGroupName = `${productPrefix} - Cross-sell ${targetAsin}`;
            if (!targetExpr) {
              console.warn('[Bulksheet] cross-sell: missing target expression for', item.product, '— skipping');
            } else if (claimNewCampaign(xsCampName)) {
              spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Campaign', 'Operation': 'Create',
                'Campaign ID': xsCampName, 'Campaign Name': xsCampName, 'Portfolio ID': portfolioId,
                'Daily Budget': String(spTmpl.daily_budget ?? ''), 'Targeting Type': 'MANUAL',
                'Bidding Strategy': 'Dynamic bids - down only', 'Start Date': startDate, 'State': 'ENABLED' });
              // Product-page placement boost — product targets serve on detail pages.
              if ((spTmpl.product_page_pct ?? 0) > 0) {
                spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Bidding Adjustment', 'Operation': 'Create',
                  'Campaign ID': xsCampName, 'Campaign Name': xsCampName, 'Placement': 'Placement Product Page',
                  'Percentage': String(spTmpl.product_page_pct) });
              }
              spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Ad Group', 'Operation': 'Create',
                'Campaign ID': xsCampName, 'Campaign Name': xsCampName,
                'Ad Group ID': xsAdGroupName, 'Ad Group Name': xsAdGroupName,
                'Ad Group Default Bid': bid, 'State': 'ENABLED' });
              spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Product Targeting', 'Operation': 'Create',
                'Campaign ID': xsCampName, 'Campaign Name': xsCampName,
                'Ad Group ID': xsAdGroupName, 'Ad Group Name': xsAdGroupName,
                'Product Targeting Expression': targetExpr, 'Bid': bid, 'State': 'ENABLED' });
              spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Product Ad', 'Operation': 'Create',
                'Campaign ID': xsCampName, 'Campaign Name': xsCampName,
                'Ad Group ID': xsAdGroupName, 'Ad Group Name': xsAdGroupName,
                ...(sku ? { 'SKU': sku } : asin ? { 'ASIN (Informational only)': asin } : {}),
                'State': 'ENABLED' });
            }
          }
        } else if (item.action === 'PROMOTE_TO_PEAK_PHRASE') {
          // Seasonal Peak Campaign Strategy
          const bid = '1.50'; // Aggressive default bid for Peak Seasonal
          // Resolve ASIN and SKU — never write product short-name into Amazon fields
          const asin = item.asin || asinByShortName.get(item.product) || '';
          const sku = skuByAsin.get(asin) || '';
          if (!asin) console.warn('[Bulksheet] unresolved ASIN/SKU for', item.product);

          let productPrefix = cn.match(/^(BOTTLE|BOX|ME|FRESH|BRAND)/)?.[1] || 'PRODUCT';
          const productShortUpper = item.product.toUpperCase();
          if (productShortUpper.includes('ME')) productPrefix = 'ME';
          else if (productShortUpper.includes('BOX')) productPrefix = 'BOX';
          else if (productShortUpper.includes('FRESH')) productPrefix = 'FRESH';
          else if (productShortUpper.includes('BOTTLE')) productPrefix = 'BOTTLE';
          
          const startDate = new Date().toISOString().slice(0, 10).replace(/-/g, '');
          const portfolioId = PORTFOLIO_MAP[productPrefix] || '';
          const theme = item.seasonal_theme || 'General Peak';
          
          const spCampName = `${productPrefix}-SP/EXACT (Seasonal Peak - ${theme})`;
          const spAdGroupName = `${productPrefix} - Exact Peak (${theme})`;
          
          // Deduplicate campaign creation (within export + against already-live campaigns)
          if (claimNewCampaign(spCampName)) {
            spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Campaign', 'Operation': 'Create',
              'Campaign ID': spCampName, 'Campaign Name': spCampName, 'Portfolio ID': portfolioId, 'Daily Budget': '25', 'Targeting Type': 'MANUAL',
              'Bidding Strategy': 'Dynamic bids - down only', 'Start Date': startDate, 'State': 'ENABLED' });
            // Aggressive TOS markup
            spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Bidding Adjustment', 'Operation': 'Create',
              'Campaign ID': spCampName, 'Campaign Name': spCampName, 'Placement': 'Placement Top', 'Percentage': '300' });
            spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Ad Group', 'Operation': 'Create',
              'Campaign ID': spCampName, 'Campaign Name': spCampName,
              'Ad Group ID': spAdGroupName, 'Ad Group Name': spAdGroupName,
              'Ad Group Default Bid': bid, 'State': 'ENABLED' });
            spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Product Ad', 'Operation': 'Create',
              'Campaign ID': spCampName, 'Campaign Name': spCampName,
              'Ad Group ID': spAdGroupName, 'Ad Group Name': spAdGroupName,
              ...(sku ? { 'SKU': sku } : asin ? { 'ASIN (Informational only)': asin } : {}),
              'State': 'ENABLED' });
          }
          
          // Add the specific term to the Exact Ad Group
          spRows.push({ 'Product': 'Sponsored Products', 'Entity': 'Keyword', 'Operation': 'Create',
            'Campaign ID': spCampName, 'Campaign Name': spCampName,
            'Ad Group ID': spAdGroupName, 'Ad Group Name': spAdGroupName,
            'Keyword Text': item.search_term, 'Match Type': 'EXACT', 'Bid': bid, 'State': 'ENABLED' });
        // ═══════════════════════════════════════════════════════════
        // BUDGET actions — Campaign entity Update with new Daily Budget
        // ═══════════════════════════════════════════════════════════
        } else if (item.action.includes('BUDGET_INCREASE') || item.action.includes('BUDGET_DECREASE')) {
          const recBudget = item.recommended_budget;
          if (recBudget != null) {
            spRows.push({
              ...spBase,
              'Entity': 'Campaign',
              'Operation': 'Update',
              'Daily Budget': String(recBudget),
            });
          }
        // ═══ REMOVE_NEGATIVE — archive an existing negative keyword (conflict removal) ═══
        // Keyed by the real Amazon Keyword ID; State=archived removes the block.
        } else if (item.action === 'REMOVE_NEGATIVE' && item.keyword_id) {
          const isCampaignLevel = !item.ad_group_id;
          const mtDisplay = (item.match_type || '').toUpperCase().includes('PHRASE') ? 'Negative Phrase' : 'Negative Exact';
          spRows.push({
            'Product': 'Sponsored Products',
            'Entity': isCampaignLevel ? 'Campaign Negative Keyword' : 'Negative Keyword',
            'Operation': 'Update',
            'Campaign ID': item.campaign_id,
            ...(isCampaignLevel ? {} : { 'Ad Group ID': item.ad_group_id }),
            'Keyword ID': item.keyword_id,
            'Keyword Text': item.search_term,
            'Match Type': mtDisplay,
            'State': 'archived',
          });
        }
      }

      if (!spRows.length && !sbRows.length) return;

      const wb = XLSX.utils.book_new();
      // SP sheet
      if (spRows.length) {
        const spData = [SP_HEADERS, ...spRows.map(row => SP_HEADERS.map(h => row[h] || ''))];
        XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(spData), 'Sponsored Products Campaigns');
      }
      // SB sheets — split between legacy (neg keywords) and V4 (new campaigns)
      if (sbRows.length) {
        // Legacy SB sheet: negative keywords on existing campaigns
        const sbLegacyRows = sbRows.filter(r => r['Entity'] === 'Negative Keyword');
        // V4 Multi Ad Group sheet: new campaign creation (Campaign, Ad Group, Video Ad, Keyword)
        const sbV4Rows = sbRows.filter(r => r['Entity'] !== 'Negative Keyword');

        if (sbLegacyRows.length) {
          const sbLegacyData = [SB_HEADERS, ...sbLegacyRows.map(row => SB_HEADERS.map(h => row[h] || ''))];
          XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(sbLegacyData), 'Sponsored Brands Campaigns');
        }
        if (sbV4Rows.length) {
          const sbV4Data = [SB_HEADERS, ...sbV4Rows.map(row => SB_HEADERS.map(h => row[h] || ''))];
          XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(sbV4Data), 'SB Multi Ad Group Campaigns');
        }
      }
      XLSX.writeFile(wb, `amazon_bulksheet_${new Date().toISOString().slice(0, 10)}.xlsx`);
    });
  };

  return (
    <div className="animate-in">
      <PageHeader title="DO — Your Task Queue" subtitle={`${totalItems} pending · ${totalDone} done · ${totalUploaded} uploaded`} />

      <DecisionScorecard />

      {/* Uploaded ≠ logged: changes marked uploaded whose change-log POST never
          reached BigQuery. Without this, the scorecard silently under-counts. */}
      {doQueue.pendingSyncCount > 0 && (
        <div className="mb-5 flex items-center gap-3 px-4 py-3 rounded-lg border border-amber-500/30 bg-amber-500/[.06]">
          <AlertTriangle size={15} className="text-amber-400 shrink-0" />
          <div className="flex-1 min-w-0">
            <div className="text-[12px] font-semibold text-amber-300">
              {doQueue.pendingSyncCount} uploaded change{doQueue.pendingSyncCount !== 1 ? 's' : ''} not yet logged to the scorecard
            </div>
            <div className="text-[10px] text-subtle">
              The change-log save to BigQuery didn’t go through (API unreachable). These won’t appear on the Decision Scorecard until synced.
            </div>
          </div>
          <button
            onClick={doQueue.retryPendingSync}
            className="text-[10px] px-2.5 py-1.5 rounded-lg border border-amber-500/40 text-amber-300 hover:bg-amber-500/15 transition-colors font-semibold flex items-center gap-1 shrink-0"
          >
            <RefreshCw size={11} /> Retry sync
          </button>
        </div>
      )}

      {totalItems > 0 && (
        <div className="flex gap-2 mb-4">
          <button onClick={expandAll} className="text-[10px] px-2.5 py-1.5 rounded-lg border border-border text-subtle hover:text-text hover:bg-card-hover transition-colors font-semibold">
            Expand All
          </button>
          <button onClick={collapseAll} className="text-[10px] px-2.5 py-1.5 rounded-lg border border-border text-subtle hover:text-text hover:bg-card-hover transition-colors font-semibold">
            Collapse All
          </button>
          <div className="flex-1" />
          <button
            onClick={exportBulksheet}
            className="text-[10px] px-2.5 py-1.5 rounded-lg border border-blue-500/30 text-blue-400 hover:bg-blue-500/15 transition-colors font-semibold flex items-center gap-1"
          >
            <Download size={11} /> Export Bulksheet
          </button>
          <button
            onClick={() => {
              if (confirm('Mark all queued items as uploaded to Amazon? This will hide them from the Actions page.')) {
                doQueue.markAllUploaded();
              }
            }}
            className="text-[10px] px-2.5 py-1.5 rounded-lg border border-emerald-500/30 text-emerald-400 hover:bg-emerald-500/15 transition-colors font-semibold flex items-center gap-1"
          >
            <Upload size={11} /> Uploaded to Amazon ✓
          </button>
          <button
            onClick={() => { if (confirm('Clear all queued tasks?')) doQueue.clearAll(); }}
            className="text-[10px] px-2.5 py-1.5 rounded-lg border border-red-500/30 text-red-400 hover:bg-red-500/15 transition-colors font-semibold flex items-center gap-1"
          >
            <Trash2 size={11} /> Clear All
          </button>
        </div>
      )}


      {/* Pending tasks — Campaign → Action → Target / Keywords */}
      <div className="space-y-3">
        {campaignGroups.map(group => {
          const isExpanded = expandedCampaigns.has(group.campaign);

          return (
            <div key={group.campaign} className="border border-border rounded-xl bg-card overflow-hidden">
              {/* Campaign header */}
              <div
                className="flex items-center gap-2.5 px-4 py-3 cursor-pointer hover:bg-card-hover transition-colors"
                onClick={() => toggleCampaign(group.campaign)}
              >
                <span className="text-[11px] text-faint">
                  {isExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                </span>
                <span className="font-mono text-[12px] font-bold text-text">{group.campaign}</span>
                <span className="text-[10px] text-subtle font-mono">
                  ({group.totalCount})
                </span>
                {group.urgentCount > 0 && <Badge variant="red">{group.urgentCount} urgent</Badge>}

                <div className="ml-auto flex items-center gap-2">
                  {group.negateCount > 0 && (
                    <button
                      onClick={(e) => { e.stopPropagation(); copyBlacklist(group.campaign, group); }}
                      className="flex items-center gap-1 px-2 py-1 rounded-md text-[10px] font-semibold border border-red-500/30 text-red-400 hover:bg-red-500/15 transition-all"
                      title={`Copy ${group.negateCount} keywords to blacklist`}
                    >
                      {copiedCampaign === group.campaign ? <Check size={12} /> : <Copy size={12} />}
                      {copiedCampaign === group.campaign ? 'Copied!' : `Blacklist (${group.negateCount})`}
                    </button>
                  )}
                  <button
                    onClick={(e) => { e.stopPropagation(); doQueue.clearCampaign(group.campaign); }}
                    className="flex items-center gap-1 px-2 py-1 rounded-md text-[10px] font-semibold border border-border text-faint hover:text-red-400 hover:border-red-500/30 transition-all"
                    title="Remove all tasks for this campaign"
                  >
                    <X size={11} />
                  </button>
                </div>
              </div>

              {/* Expanded: Action groups */}
              {isExpanded && (
                <div className="border-t border-border">
                  {group.actionGroups.map(ag => {
                    const color = ACTION_COLORS[ag.action] || '#71717a';
                    const isTargetLevel = TARGET_LEVEL_ACTIONS.has(ag.action);

                    return (
                      <div key={ag.action} className="border-b border-border-faint last:border-0">
                        {/* Action header */}
                        <div className="flex items-center gap-2 px-4 py-2 bg-surface/30"
                          style={{ borderLeft: `3px solid ${color}` }}
                        >
                          <ActionBadge action={ag.action} />
                          <span className="text-[10px] text-subtle font-mono">
                            {isTargetLevel
                              ? `${ag.targets.length} target${ag.targets.length !== 1 ? 's' : ''}`
                              : `${ag.items.length} keyword${ag.items.length !== 1 ? 's' : ''}`
                            }
                          </span>
                        </div>

                        {/* Content: Target rows (for bid ops) or flat keyword rows (for search-term ops) */}
                        <div className="divide-y divide-border-faint">
                          {isTargetLevel ? (
                            /* ═══ Target-level: show expandable target rows ═══ */
                            ag.targets.map(target => {
                              const targetKey = `${group.campaign}::${ag.action}::${target.targeting}`;
                              const isTargetExpanded = expandedTargets.has(targetKey);

                              return (
                                <div key={targetKey}>
                                  {/* Target header */}
                                  <div
                                    className="flex items-center gap-2 px-6 py-2 cursor-pointer hover:bg-card-hover transition-colors"
                                    onClick={() => toggleTarget(targetKey)}
                                  >
                                    <span className="text-[10px] text-faint">
                                      {isTargetExpanded ? <ChevronDown size={11} /> : <ChevronRight size={11} />}
                                    </span>
                                    <span className="font-mono text-[11px] font-semibold text-text">
                                      {target.targeting}
                                    </span>
                                    {target.matchType && (
                                      <span className="text-[9px] px-1.5 py-0.5 rounded bg-surface border border-border-faint text-muted font-mono uppercase">
                                        {target.matchType}
                                      </span>
                                    )}
                                    <span className="text-[10px] text-subtle font-mono">
                                      ({target.items.length})
                                    </span>
                                    <div className="flex-1" />
                                    <span className="text-[10px] font-mono text-faint">{fM(target.targetSpend8w)}</span>
                                    {target.targetNetRoas8w > 0 && (
                                      <span className={`text-[10px] font-mono ml-1 ${target.targetNetRoas8w >= 1 ? 'text-emerald-400/70' : 'text-amber-400/70'}`}>
                                        ROAS {target.targetNetRoas8w.toFixed(2)}
                                      </span>
                                    )}
                                    <span className="text-[10px] font-mono text-faint ml-2">{fOrd(target.targetOrders8w)} ord</span>
                                  </div>

                                  {/* Expanded: search terms under this target */}
                                  {isTargetExpanded && (
                                    <div className="divide-y divide-border-faint bg-surface/5">
                                      {target.items.map((item: DoQueueItem) => renderSearchTermRow(item, true))}
                                    </div>
                                  )}
                                </div>
                              );
                            })
                          ) : (
                            /* ═══ Search-term-level: show flat keyword rows ═══ */
                            ag.items.map((item: DoQueueItem) => renderSearchTermRow(item))
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Done section */}
      {totalDone > 0 && (
        <div className="mt-6">
          <button
            onClick={() => setShowDone(p => !p)}
            className="flex items-center gap-2 mb-3 text-sm font-bold"
          >
            <span className="text-faint">
              {showDone ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
            </span>
            <CheckCircle2 size={14} className="text-emerald-400" />
            <span className="text-emerald-400">Done</span>
            <Badge variant="green">{totalDone}</Badge>
            <div className="flex-1" />
            {showDone && (
              <button
                onClick={(e) => { e.stopPropagation(); if (confirm('Clear done log?')) doQueue.clearDone(); }}
                className="text-[10px] px-2 py-1 rounded-md border border-border text-faint hover:text-red-400 hover:border-red-500/30 transition-all font-normal"
              >
                Clear Done
              </button>
            )}
          </button>

          {showDone && (
            <div className="space-y-3 animate-in">
              {doneGroups.map(([date, items]) => (
                <div key={date} className="border border-emerald-500/15 rounded-xl bg-emerald-500/[.02] overflow-hidden">
                  <div className="px-4 py-2 text-[10px] text-emerald-400/60 font-mono font-semibold uppercase tracking-wider border-b border-emerald-500/10">
                    {date} · {items.length} completed
                  </div>
                  <div className="divide-y divide-emerald-500/10">
                    {items.map(item => (
                      <div
                        key={item.id}
                        className="flex items-center gap-3 px-4 py-2 text-[11px] group"
                      >
                        <CheckCircle2 size={14} className="text-emerald-500/50 shrink-0" />
                        <span className="text-subtle line-through min-w-0 truncate max-w-[160px]">{item.targeting || item.search_term}</span>
                        <ActionBadge action={item.action} />
                        <span className="text-[10px] text-faint truncate max-w-[200px]">{item.campaign}</span>
                        <div className="ml-auto flex items-center gap-2 shrink-0">
                          <button
                            onClick={() => doQueue.undoDone(item.id)}
                            className="flex items-center gap-1 px-1.5 py-0.5 rounded text-[9px] text-faint hover:text-amber-400 transition-all opacity-0 group-hover:opacity-100"
                            title="Move back to queue"
                          >
                            <RotateCcw size={10} /> Undo
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Uploaded to Amazon section */}
      {totalUploaded > 0 && (
        <div className="mt-6">
          <button
            onClick={() => setShowUploaded(p => !p)}
            className="flex items-center gap-2 mb-3 text-sm font-bold"
          >
            <span className="text-faint">
              {showUploaded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
            </span>
            <Upload size={14} className="text-blue-400" />
            <span className="text-blue-400">Uploaded to Amazon</span>
            <Badge variant="blue">{totalUploaded}</Badge>
            <div className="flex-1" />
            {showUploaded && (
              <button
                onClick={(e) => { e.stopPropagation(); if (confirm('Clear uploaded log?')) doQueue.clearUploaded(); }}
                className="text-[10px] px-2 py-1 rounded-md border border-border text-faint hover:text-red-400 hover:border-red-500/30 transition-all font-normal"
              >
                Clear Uploaded
              </button>
            )}
          </button>

          {showUploaded && (
            <div className="space-y-3 animate-in">
              {(() => {
                const byDate: Record<string, DoQueueItem[]> = {};
                for (const item of doQueue.uploadedItems) {
                  const dt = item.uploadedAt
                    ? new Date(item.uploadedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
                    : 'Unknown';
                  if (!byDate[dt]) byDate[dt] = [];
                  byDate[dt].push(item);
                }
                return Object.entries(byDate)
                  .sort(([, a], [, b]) => (b[0].uploadedAt || 0) - (a[0].uploadedAt || 0))
                  .map(([date, items]) => (
                    <div key={date} className="border border-blue-500/15 rounded-xl bg-blue-500/[.02] overflow-hidden">
                      <div className="px-4 py-2 text-[10px] text-blue-400/60 font-mono font-semibold uppercase tracking-wider border-b border-blue-500/10">
                        {date} · {items.length} uploaded
                      </div>
                      <div className="divide-y divide-blue-500/10">
                        {items.map(item => (
                          <div
                            key={item.id}
                            className="flex items-center gap-3 px-4 py-2 text-[11px] group"
                          >
                            <Upload size={12} className="text-blue-500/50 shrink-0" />
                            <span className="text-subtle">{item.search_term}</span>
                            <ActionBadge action={item.action} />
                            <span className="text-[10px] text-faint truncate max-w-[150px]">{item.campaign}</span>
                            <div className="ml-auto flex items-center gap-2 shrink-0">
                              <button
                                onClick={() => doQueue.undoUploaded(item.id)}
                                className="flex items-center gap-1 px-1.5 py-0.5 rounded text-[9px] text-faint hover:text-amber-400 transition-all opacity-0 group-hover:opacity-100"
                                title="Move back to queue"
                              >
                                <RotateCcw size={10} /> Undo
                              </button>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  ));
              })()}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

