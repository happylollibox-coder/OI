import { useState, useEffect, useCallback } from 'react';
import { Bell, AlertTriangle, AlertCircle, Info, Check, X, RefreshCw, Package, Truck, Settings, Calendar, ChevronDown, ChevronRight, ExternalLink, TrendingUp, ShoppingCart } from 'lucide-react';
import type { AlertRow } from '../types';
import { Section } from '../components/Section';
import { fmt } from '../utils';
import { RemediationModal } from '../components/Actions/RemediationModal';
import { CreatePOModal } from '../components/Actions/CreatePOModal';
import type { DraftPOLine } from '../components/Actions/CreatePOModal';

import { AlertCard, SEVERITY_CONFIG, TYPE_CONFIG } from '../components/AlertCard';
import { apiFetch } from '../utils/apiFetch';

// ─── Component ────────────────────────────────────────────
export function AlertsPage() {
  const [alerts, setAlerts] = useState<AlertRow[]>([]);
  const [archive, setArchive] = useState<AlertRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [tab, setTab] = useState<'open' | 'archive'>('open');
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  const [typeFilter, setTypeFilter] = useState<string | null>(null);
  const [activeAlert, setActiveAlert] = useState<AlertRow | null>(null);

  const [draftPOLines, setDraftPOLines] = useState<DraftPOLine[]>([]);
  const [showPOModal, setShowPOModal] = useState(false);

  const handleAddPoLine = useCallback((alert: AlertRow) => {
    let cogs = 1.00;
    if (alert.payload_json) {
      try {
        const payload = JSON.parse(alert.payload_json);
        cogs = payload.cogs || 1.00;
      } catch (e) {}
    }
    setDraftPOLines(prev => [...prev, {
      product: alert.product_name || alert.product_asin || '',
      qty: alert.suggested_qty || 0,
      cogs: cogs,
      asin: alert.product_asin || 'UNKNOWN'
    }]);
  }, []);

  const loadAlerts = useCallback(async () => {
    try {
      const [openRes, doneRes] = await Promise.all([
        apiFetch('/api/alerts?status=OPEN'),
        apiFetch('/api/alerts?status=DONE'),
      ]);
      if (openRes.ok) setAlerts(await openRes.json());
      if (doneRes.ok) setArchive(await doneRes.json());
    } catch (e) {
      console.error('Failed to load alerts:', e);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadAlerts(); }, [loadAlerts]);

  const generateAlerts = async () => {
    setGenerating(true);
    try {
      const res = await apiFetch('/api/alerts/generate', { method: 'POST' });
      if (res.ok) await loadAlerts();
    } catch (e) {
      console.error('Failed to generate alerts:', e);
    } finally {
      setGenerating(false);
    }
  };

  const markDone = async (id: string) => {
    try {
      const res = await apiFetch(`/api/alerts/${id}/done`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) });
      if (res.ok) await loadAlerts();
    } catch (e) { console.error('Failed:', e); }
  };

  const cancelAlert = async (id: string) => {
    try {
      const res = await apiFetch(`/api/alerts/${id}/cancel`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) });
      if (res.ok) await loadAlerts();
    } catch (e) { console.error('Failed:', e); }
  };

  const toggleExpand = (id: string) => {
    setExpandedIds(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  // ─── Computed ────────────────────────────────────────────
  const displayAlerts = tab === 'open' ? alerts : archive;
  const filtered = typeFilter ? displayAlerts.filter(a => a.alert_type === typeFilter) : displayAlerts;
  const critical = alerts.filter(a => a.severity === 'CRITICAL').length;
  const warning = alerts.filter(a => a.severity === 'WARNING').length;
  const info = alerts.filter(a => a.severity === 'INFO').length;

  // Group by type
  const grouped = filtered.reduce<Record<string, AlertRow[]>>((acc, a) => {
    (acc[a.alert_type] = acc[a.alert_type] || []).push(a);
    return acc;
  }, {});

  const handleReopen = async (alertId: string) => {
    try {
      const res = await apiFetch(`/api/alerts/${alertId}/reopen`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) });
      if (res.ok) await loadAlerts();
      else console.error('Failed to reopen alert', await res.text());
    } catch (e) { console.error('Failed to reopen alert', e); }
  };

  if (loading) {
    return (
      <Section title="Alerts">
        <div className="flex items-center justify-center py-20">
          <RefreshCw className="animate-spin text-muted" size={20} />
          <span className="ml-2 text-muted text-sm">Loading alerts...</span>
        </div>
      </Section>
    );
  }

  return (
    <Section title="Supply Chain Alerts">
      {/* ─── Summary Cards ─── */}
      <div className="grid grid-cols-4 gap-3 mb-5">
        <div className="p-3 rounded-lg border border-border bg-white/[0.02]">
          <div className="text-[10px] text-muted uppercase tracking-wide mb-1">Total Open</div>
          <div className="text-2xl font-bold text-heading">{alerts.length}</div>
        </div>
        <div className={`p-3 rounded-lg border ${critical > 0 ? 'border-red-500/30 bg-red-500/5' : 'border-border bg-white/[0.02]'}`}>
          <div className="text-[10px] text-muted uppercase tracking-wide mb-1">Critical</div>
          <div className={`text-2xl font-bold ${critical > 0 ? 'text-red-400' : 'text-heading'}`}>{critical}</div>
        </div>
        <div className={`p-3 rounded-lg border ${warning > 0 ? 'border-amber-500/30 bg-amber-500/5' : 'border-border bg-white/[0.02]'}`}>
          <div className="text-[10px] text-muted uppercase tracking-wide mb-1">Warning</div>
          <div className={`text-2xl font-bold ${warning > 0 ? 'text-amber-400' : 'text-heading'}`}>{warning}</div>
        </div>
        <div className="p-3 rounded-lg border border-border bg-white/[0.02]">
          <div className="text-[10px] text-muted uppercase tracking-wide mb-1">Info</div>
          <div className="text-2xl font-bold text-heading">{info}</div>
        </div>
      </div>

      {/* ─── Toolbar ─── */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <button onClick={() => setTab('open')}
            className={`px-3 py-1.5 text-[10px] font-semibold rounded-md transition-colors ${tab === 'open' ? 'bg-blue-500/15 text-blue-400 border border-blue-500/30' : 'text-muted hover:text-subtle border border-border/50'}`}>
            Open ({alerts.length})
          </button>
          <button onClick={() => setTab('archive')}
            className={`px-3 py-1.5 text-[10px] font-semibold rounded-md transition-colors ${tab === 'archive' ? 'bg-blue-500/15 text-blue-400 border border-blue-500/30' : 'text-muted hover:text-subtle border border-border/50'}`}>
            Archive ({archive.length})
          </button>
          <div className="w-px h-5 bg-border mx-1" />
          {Object.entries(TYPE_CONFIG).map(([type, cfg]) => {
            const count = displayAlerts.filter(a => a.alert_type === type).length;
            if (count === 0 && !typeFilter) return null;
            return (
              <button key={type} onClick={() => setTypeFilter(typeFilter === type ? null : type)}
                className={`inline-flex items-center gap-1 px-2 py-1 text-[9px] rounded-md transition-colors ${typeFilter === type ? `${cfg.color} bg-white/[0.06] border border-white/10` : 'text-muted hover:text-subtle border border-transparent'}`}>
                <cfg.icon size={10} />
                {cfg.label} ({count})
              </button>
            );
          })}
        </div>
        <button onClick={generateAlerts} disabled={generating}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[10px] font-medium text-emerald-400 bg-emerald-500/10 border border-emerald-500/30 rounded-md hover:bg-emerald-500/20 transition-colors disabled:opacity-50">
          <RefreshCw size={11} className={generating ? 'animate-spin' : ''} />
          {generating ? 'Generating...' : 'Run Engine'}
        </button>
      </div>

      {/* ─── Empty State ─── */}
      {filtered.length === 0 && (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <Bell className="text-emerald-500/40 mb-3" size={32} />
          <h3 className="text-sm font-medium text-emerald-400 mb-1">
            {tab === 'open' ? 'All Clear!' : 'No Archived Alerts'}
          </h3>
          <p className="text-[10px] text-muted max-w-xs">
            {tab === 'open' ? 'No open alerts. Your supply chain is running smoothly.' : 'Resolved alerts will appear here.'}
          </p>
        </div>
      )}

      {/* ─── Alert Groups ─── */}
      {Object.entries(grouped).map(([type, items]) => {
        const cfg = TYPE_CONFIG[type] || TYPE_CONFIG.CREATE_PO;
        return (
          <div key={type} className="mb-5">
            <div className="flex items-center gap-2 mb-2.5">
              <cfg.icon size={14} className={cfg.color} />
              <span className={`text-xs font-semibold ${cfg.color}`}>{cfg.label}</span>
              <span className="text-[9px] text-muted">({items.length})</span>
            </div>
            <div className="space-y-2">
              {items.map(alert => (
                <AlertCard 
                  key={alert.id} 
                  alert={alert} 
                  expanded={expandedIds.has(alert.id)} 
                  onToggle={() => toggleExpand(alert.id)} 
                  onDone={() => markDone(alert.id)} 
                  onCancel={() => cancelAlert(alert.id)} 
                  onReopen={() => handleReopen(alert.id)} 
                  isArchive={tab === 'archive'} 
                  onRemediate={() => {
                    if (alert.alert_type === 'CREATE_PO') {
                      handleAddPoLine(alert);
                    } else {
                      setActiveAlert(alert);
                    }
                  }} 
                />
              ))}
            </div>
          </div>
        );
      })}

      {activeAlert && (
        <RemediationModal
          alert={activeAlert}
          onClose={() => setActiveAlert(null)}
          onSuccess={() => {
            setActiveAlert(null);
            loadAlerts();
          }}
        />
      )}

      {/* Floating PO Draft Cart Widget */}
      {draftPOLines.length > 0 && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-surface border border-border shadow-2xl rounded-full px-5 py-3 flex items-center gap-4 z-50 animate-in slide-in-from-bottom-5">
          <div className="flex items-center gap-2">
            <div className="bg-purple-500/20 text-purple-400 p-2 rounded-full">
              <ShoppingCart size={16} />
            </div>
            <div className="text-sm font-bold text-heading">
              {draftPOLines.length} PO line{draftPOLines.length > 1 ? 's' : ''} drafted
            </div>
          </div>
          <div className="w-[1px] h-6 bg-border" />
          <div className="flex items-center gap-2">
            <button 
              onClick={() => setShowPOModal(true)}
              className="px-4 py-1.5 bg-purple-500 hover:bg-purple-600 text-white text-sm font-semibold rounded-full shadow-lg transition-colors"
            >
              Create PO
            </button>
            <button 
              onClick={() => setDraftPOLines([])}
              className="px-3 py-1.5 text-muted hover:text-red-400 text-sm font-medium transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* Create PO Modal */}
      {showPOModal && (
        <CreatePOModal 
          draftLines={draftPOLines}
          onClose={() => setShowPOModal(false)}
          onSuccess={() => {
            setShowPOModal(false);
            setDraftPOLines([]);
            loadAlerts(); // Refresh alerts after creating PO
          }}
        />
      )}
    </Section>
  );
}


