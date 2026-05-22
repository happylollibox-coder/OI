import { ChevronDown, ChevronRight, Check, X } from 'lucide-react';
import { Package, Truck, Settings, Calendar, TrendingUp, AlertTriangle, AlertCircle, Info } from 'lucide-react';
import type { AlertRow } from '../types';
import { fmt } from '../utils';

// ─── Constants ────────────────────────────────────────────
export const SEVERITY_CONFIG = {
  CRITICAL: { icon: AlertTriangle, color: 'text-red-400', bg: 'bg-red-500/10', border: 'border-red-500/30', badge: 'bg-red-500', label: 'Critical' },
  WARNING:  { icon: AlertCircle,   color: 'text-amber-400', bg: 'bg-amber-500/10', border: 'border-amber-500/30', badge: 'bg-amber-500', label: 'Warning' },
  INFO:     { icon: Info,          color: 'text-blue-400', bg: 'bg-blue-500/10', border: 'border-blue-500/30', badge: 'bg-blue-500', label: 'Info' },
};

export const TYPE_CONFIG: Record<string, { icon: typeof Package; label: string; color: string }> = {
  CREATE_PO:         { icon: Package,    label: 'Create PO',         color: 'text-purple-400' },
  CREATE_SHIPMENT:   { icon: Truck,      label: 'Create Shipment',   color: 'text-emerald-400' },
  UPDATE_AWD_TARGET: { icon: Settings,   label: 'Update AWD Target', color: 'text-blue-400' },
  AWD_LIMITS:        { icon: Settings,   label: 'AWD Limits',        color: 'text-blue-400' },
  AMAZON_PLAN:       { icon: Calendar,   label: 'Amazon Plan',       color: 'text-orange-400' },
  PLAN_DRIFT:        { icon: TrendingUp, label: 'Plan Drift',        color: 'text-orange-400' },
  SALES_DEVIATION:   { icon: TrendingUp, label: 'Sales Deviation',   color: 'text-cyan-400' },
};

export function AlertCard({ alert, expanded, onToggle, onDone, onCancel, onReopen, isArchive, onRemediate }: {
  alert: AlertRow; expanded: boolean; onToggle: () => void; onDone: () => void; onCancel: () => void; onReopen: () => void; isArchive: boolean; onRemediate?: () => void;
}) {
  const sev = SEVERITY_CONFIG[alert.severity as keyof typeof SEVERITY_CONFIG] || SEVERITY_CONFIG.INFO;
  const SevIcon = sev.icon;
  const typeCfg = TYPE_CONFIG[alert.alert_type] || TYPE_CONFIG.CREATE_PO;
  const age = Math.floor((Date.now() - new Date(alert.created_at).getTime()) / 86400000);

  return (
    <div className={`rounded-lg border ${sev.border} ${sev.bg} transition-all`}>
      {/* Header */}
      <div className="flex items-center gap-3 px-4 py-3 cursor-pointer select-none" onClick={onToggle}>
        <div className="flex items-center gap-2 flex-1 min-w-0">
          {expanded ? <ChevronDown size={12} className="text-muted flex-shrink-0" /> : <ChevronRight size={12} className="text-muted flex-shrink-0" />}
          <SevIcon size={14} className={`${sev.color} flex-shrink-0`} />
          <span className={`text-xs font-semibold ${sev.color} truncate`}>{alert.title}</span>
        </div>
        <div className="flex items-center gap-3 flex-shrink-0">
          {/* DOC badge */}
          {alert.fba_doc != null && (
            <span className={`text-[9px] font-mono px-1.5 py-0.5 rounded ${alert.fba_doc < 15 ? 'bg-red-500/20 text-red-300' : alert.fba_doc < 30 ? 'bg-amber-500/20 text-amber-300' : 'bg-white/5 text-muted'}`}>
              FBA {Math.round(alert.fba_doc)}d
            </span>
          )}
          {/* Qty badge */}
          {alert.suggested_qty != null && alert.suggested_qty > 0 && (
            <span className="text-[9px] font-mono text-muted bg-white/5 px-1.5 py-0.5 rounded">
              {fmt(alert.suggested_qty)} units
            </span>
          )}
          {/* Age */}
          <span className="text-[9px] text-faint w-12 text-right">
            {age === 0 ? 'Today' : `${age}d ago`}
          </span>
          {/* Actions */}
          {!isArchive && (
            <div className="flex items-center gap-1 ml-1" onClick={e => e.stopPropagation()}>
              <button onClick={onDone} className="p-1 rounded hover:bg-emerald-500/20 text-emerald-400 transition-colors" title="Mark as Done">
                <Check size={13} />
              </button>
              <button onClick={onCancel} className="p-1 rounded hover:bg-red-500/20 text-red-400/60 hover:text-red-400 transition-colors" title="Dismiss">
                <X size={13} />
              </button>
            </div>
          )}
          {isArchive && (
            <div className="flex items-center gap-2 relative z-10" onClick={e => e.stopPropagation()}>
              <button 
                onClick={onReopen}
                className="text-[10px] font-medium text-muted hover:text-blue-400 transition-colors px-2 py-1 rounded hover:bg-blue-500/10 cursor-pointer"
                title="Un-archive / Reopen alert"
              >
                Reopen
              </button>
              <span className={`text-[8px] uppercase font-bold px-1.5 py-0.5 rounded-full ${alert.status === 'DONE' ? 'bg-emerald-500/15 text-emerald-400' : 'bg-red-500/15 text-red-400'}`}>
                {alert.status}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Expanded details */}
      {expanded && (
        <div className="px-4 pb-3 pt-0 border-t border-white/5">
          <div className="grid grid-cols-2 gap-x-6 gap-y-2 mt-3">
            <DetailRow label="Product" value={alert.product_name || ''} />
            <DetailRow label="Alert Type" value={typeCfg.label} />
            {alert.fba_doc != null && <DetailRow label="FBA DOC" value={`${Math.round(alert.fba_doc)} days`} highlight={alert.fba_doc < 15 ? 'red' : alert.fba_doc < 30 ? 'amber' : undefined} />}
            {alert.system_doc != null && <DetailRow label="Total Stock DOC" value={`${Math.round(alert.system_doc || 0)} days`} />}
            {alert.suggested_qty != null && alert.suggested_qty > 0 && <DetailRow label="Suggested Qty" value={`${fmt(alert.suggested_qty)} units`} />}
            {alert.suggested_split_fba != null && alert.suggested_split_fba > 0 && <DetailRow label="→ FBA Split" value={`${fmt(alert.suggested_split_fba)} units`} />}
            {alert.suggested_split_awd != null && alert.suggested_split_awd > 0 && <DetailRow label="→ AWD Split" value={`${fmt(alert.suggested_split_awd)} units`} />}
            {/* Enriched inventory breakdown for CREATE_PO alerts */}
            {(() => {
              if (alert.alert_type !== 'CREATE_PO' || !alert.action_payload) return null;
              try {
                const p = typeof alert.action_payload === 'string' ? JSON.parse(alert.action_payload) : alert.action_payload;
                return (
                  <>
                    {p.current_stock != null && (
                      <DetailRow 
                        label="Current Stock" 
                        value={`${fmt(p.current_stock)} (FBA: ${fmt(p.fba_stock || 0)}, AWD: ${fmt(p.awd_stock || 0)}, Transit: ${fmt(p.in_transit || 0)})`} 
                      />
                    )}
                    {p.total_stock != null && (
                      <DetailRow label="Total Stock" value={`${fmt(p.total_stock)} (incl. ${fmt(p.at_manufacturer || 0)} at Mfr)`} />
                    )}
                    {p.approved_no_po_qty != null && p.approved_no_po_qty > 0 && (
                      <DetailRow label="Approved w/o PO" value={`${fmt(p.approved_no_po_qty)} units`} highlight="amber" />
                    )}
                  </>
                );
              } catch { return null; }
            })()}
            {alert.breach_date && <DetailRow label="Breach Date" value={alert.breach_date} />}
            {alert.related_po_id && <DetailRow label="Related PO" value={alert.related_po_id} />}
          </div>
          <div className="mt-3 p-2.5 rounded bg-white/[0.03] border border-white/5">
            <p className="text-[10px] text-subtle leading-relaxed">{alert.description}</p>
          </div>
          {alert.resolved_at && (
            <div className="mt-2 text-[9px] text-faint">
              Resolved {new Date(alert.resolved_at).toLocaleDateString()} by {alert.resolved_by || 'system'}
              {alert.notes && <span className="ml-2 text-muted">— {alert.notes}</span>}
            </div>
          )}
          {!isArchive && onRemediate && alert.action_type && alert.action_type.startsWith('MODAL_') && (
            <div className="mt-3 flex justify-end border-t border-white/5 pt-3">
              <button
                onClick={(e) => { e.stopPropagation(); onRemediate(); }}
                className={`inline-flex items-center gap-1.5 px-3 py-1.5 text-[10px] font-medium rounded-md transition-colors border ${
                  alert.alert_type === 'CREATE_PO'
                    ? 'text-purple-400 border-purple-500/30 bg-purple-500/10 hover:bg-purple-500/20'
                    : alert.alert_type === 'CREATE_SHIPMENT'
                    ? 'text-emerald-400 border-emerald-500/30 bg-emerald-500/10 hover:bg-emerald-500/20'
                    : 'text-blue-400 border-blue-500/30 bg-blue-500/10 hover:bg-blue-500/20'
                }`}
              >
                {alert.alert_type === 'CREATE_PO' ? <Package size={12} /> : alert.alert_type === 'CREATE_SHIPMENT' ? <Truck size={12} /> : <Settings size={12} />}
                {typeCfg.label}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function DetailRow({ label, value, highlight }: { label: string; value: string; highlight?: 'red' | 'amber' }) {
  return (
    <div className="flex items-baseline gap-2">
      <span className="text-[9px] text-faint uppercase tracking-wide w-24 flex-shrink-0">{label}</span>
      <span className={`text-[11px] font-medium ${highlight === 'red' ? 'text-red-400' : highlight === 'amber' ? 'text-amber-400' : 'text-subtle'}`}>
        {value}
      </span>
    </div>
  );
}
