import { useState, useEffect, useCallback, useMemo } from 'react';
import { Info } from 'lucide-react';
import type { AlertRow } from '../types';
import { useFilters } from '../hooks/useFilters';
import { experimentMatchesFamily } from '../utils';
import type { FamilyName } from '../types';
import { AlertCard } from './AlertCard';
import { RemediationModal } from './Actions/RemediationModal';
import { apiFetch } from '../utils/apiFetch';

export function AlertsSummaryCard() {
  const [alerts, setAlerts] = useState<AlertRow[]>([]);
  const [loading, setLoading] = useState(true);
  const { filters } = useFilters();
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  const [showAll, setShowAll] = useState(false);
  const [activeAlert, setActiveAlert] = useState<AlertRow | null>(null);

  const loadAlerts = useCallback(async () => {
    try {
      const res = await apiFetch('/api/alerts?status=OPEN');
      if (res.ok) setAlerts(await res.json());
    } catch (e) {
      console.error('Failed to load alerts:', e);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadAlerts(); }, [loadAlerts]);

  // Filter alerts based on global family and product context
  const filteredAlerts = useMemo(() => {
    return alerts.filter(a => {
      if (filters.product) {
        return a.product_asin === filters.product || a.product_name === filters.product;
      }
      if (filters.family) {
        // Match product_name against family using substring matching (e.g. "Fresh in Beige" → "Fresh")
        const nameToMatch = a.product_name || a.product_asin || '';
        return experimentMatchesFamily(nameToMatch, filters.family as FamilyName);
      }
      return true;
    });
  }, [alerts, filters.family, filters.product]);

  const toggleExpand = (id: string) => {
    setExpandedIds(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
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

  if (loading) {
    return (
      <div className="rounded-xl p-4 flex items-center justify-center animate-pulse" style={{ background: 'var(--color-card)', border: '1px solid var(--color-border)' }}>
        <span className="text-[12px] text-faint">Loading alerts...</span>
      </div>
    );
  }

  if (filteredAlerts.length === 0) {
    return (
      <div className="rounded-xl p-4 flex flex-col items-center justify-center gap-2" style={{ background: 'var(--color-card)', border: '1px solid var(--color-border)' }}>
        <Info size={16} className="text-emerald-500" />
        <span className="text-[12px] font-medium" style={{ color: 'var(--color-text)' }}>No active alerts</span>
      </div>
    );
  }

  const displayedAlerts = showAll ? filteredAlerts : filteredAlerts.slice(0, 5);

  return (
    <div className="rounded-xl overflow-hidden flex flex-col" style={{ background: 'var(--color-card)', border: '1px solid var(--color-border)', boxShadow: 'var(--shadow-card)' }}>
      <div className="px-4 py-2 flex items-center justify-between" style={{ borderBottom: '1px solid var(--color-border)' }}>
        <span className="font-mono text-[10px] uppercase tracking-[0.12em] font-bold" style={{ color: 'var(--color-text)' }}>
          Active Alerts ({filteredAlerts.length})
        </span>
      </div>
      <div className="p-2 overflow-y-auto space-y-2">
        {displayedAlerts.map(a => (
          <AlertCard 
            key={a.alert_id || a.id} 
            alert={a} 
            expanded={expandedIds.has(a.alert_id || a.id)} 
            onToggle={() => toggleExpand(a.alert_id || a.id)} 
            onDone={() => markDone(a.alert_id || a.id)} 
            onCancel={() => cancelAlert(a.alert_id || a.id)} 
            onReopen={() => {}} 
            isArchive={false} 
            onRemediate={() => setActiveAlert(a)} 
          />
        ))}
        {filteredAlerts.length > 5 && (
          <div className="pt-1 flex justify-center">
            <button 
              onClick={() => setShowAll(!showAll)}
              className="text-[10px] font-semibold text-muted hover:text-heading transition-colors py-1 px-3 border border-border/50 rounded hover:bg-white/5"
            >
              {showAll ? 'Show Less' : `Show All (${filteredAlerts.length})`}
            </button>
          </div>
        )}
      </div>

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
    </div>
  );
}
