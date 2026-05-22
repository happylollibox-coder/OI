import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { ChevronDown, ChevronRight, Check, CheckCircle, ArrowRight, Lock, RotateCcw, Download, X, Loader2, Plus, ShoppingCart, Package, CalendarDays } from 'lucide-react';
import { CreatePOModal } from './Actions/CreatePOModal';
import type { DraftPOLine } from './Actions/CreatePOModal';
import { CreateShipmentModal } from './Actions/CreateShipmentModal';
import type { DraftShipmentLine } from './Actions/CreateShipmentModal';
import { ComposedChart, Bar, Line, XAxis, YAxis, Tooltip as RTooltip, ResponsiveContainer, CartesianGrid, ReferenceLine, Cell } from 'recharts';
import XLSX from 'xlsx-js-style';
import type { ShipmentPlanFactRow, ScheduledShipmentRow, UnifiedShipmentRow } from '../types';
import { Section } from '../components/Section';
import { fmt } from '../utils';


// ─── Forecast types (mirror from PlanPage) ────────────────
type ForecastDemandMap = Record<string, Record<number, number>>; // product → yearMonth(yyyyMM) → units
interface MonthSeasonInfo { peakDays: number; offseasonDays: number; holidays: string | null }
type MonthSeasonMap = Record<string, Record<number, MonthSeasonInfo>>; // family → yearMonth → info
interface ForecastProductMeta { isNew: boolean; isDraft: boolean; share: number; family: string; forecastPhase?: string; modelProduct?: string }
type ForecastMetaMap = Record<string, ForecastProductMeta>;

// ─── Constants ────────────────────────────────────────────
const CUBE_API = import.meta.env.VITE_CUBE_API_URL || (import.meta.env.DEV ? 'http://localhost:4000' : '');
const FLASK_API = import.meta.env.VITE_DATA_ENTRY_URL || import.meta.env.VITE_FLASK_API_URL || '';

const TYPE_ICONS: Record<string, string> = { 
  EMERGENCY: '🚨', EMERGENCY_PO: '⚡', 'EMERGENCY (NEW PO NEEDED)': '⚡', AWD_MAINTENANCE: '📦', Q4_BULK: '📅', 'Purchase Order': '🏭',
  'Standard Ship': '🚢', SEA: '🚢', AIR: '✈️', PO_NEEDED: '📝'
};
const TYPE_COLORS: Record<string, string> = {
  EMERGENCY: '#ef4444', EMERGENCY_PO: '#f97316', 'EMERGENCY (NEW PO NEEDED)': '#f97316', AWD_MAINTENANCE: '#3b82f6', Q4_BULK: '#a855f7',
  PO_NEEDED: '#14b8a6', 'Purchase Order': '#8b5cf6',
  'Standard Ship': '#64748b', SEA: '#64748b', AIR: '#64748b', Transit: '#64748b',
};
const STATUS_COLORS: Record<string, string> = {
  suggested: 'rgba(100,116,139,0.5)', approved: '#f59e0b', scheduled: '#22c55e', po: '#a855f7'
};
const NODE_COLORS = {
  plan: '#3b82f6', stock: '#06b6d4', fba: '#06b6d4', awd: '#67e8f9',
  inTransit: '#f59e0b', approved: '#fbbf24', scheduled: '#fde68a',
  mfr: '#14b8a6', mfrReady: '#14b8a6', mfrInProd: '#5eead4', poSugg: '#99f6e4',
  suggested: '#8b5cf6', toShip: '#ef4444',
};

// ─── Cube Load helper ─────────────────────────────────────
async function cubeLoad(query: object): Promise<unknown[]> {
  if (!CUBE_API) return [];
  try {
    let retries = 0;
    while (retries < 10) {
      const token = localStorage.getItem('dashboard_token');
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const res = await fetch(`${CUBE_API}/cubejs-api/v1/load`, { method: 'POST', headers, body: JSON.stringify({ query }) });
      if (!res.ok) return [];
      const json = await res.json();
      if (json.error === 'Continue wait') { retries++; await new Promise(r => setTimeout(r, 2000)); continue; }
      if (json.error) return [];
      return json.data ?? [];
    }
    return [];
  } catch { return []; }
}

// ═══════════════════════════════════════════════════════════
// HOOKS
// ═══════════════════════════════════════════════════════════

/** Fetch all active rows from DE_SCHEDULED_SHIPMENTS via Flask API (bypasses Cube cache) */
async function fetchScheduledShipments(): Promise<Record<string, unknown>[]> {
  const base = FLASK_API || '';
  try {
    const res = await fetch(`${base}/api/scheduled-shipments?_t=${Date.now()}`);
    if (!res.ok) return [];
    return await res.json();
  } catch { return []; }
}

/** Load SUGGESTED shipments from DE_SCHEDULED_SHIPMENTS (via Flask API — no cache) */
export function useShipmentPlan() {
  const [rows, setRows] = useState<ShipmentPlanFactRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshKey, setRefreshKey] = useState(0);

  const reload = useCallback(() => setRefreshKey(k => k + 1), []);

  useEffect(() => {
    (async () => {
      try {
        const data = await fetchScheduledShipments();
        const suggested = data.filter(r => String(r.status) === 'SUGGESTED');
        const mapped: ShipmentPlanFactRow[] = suggested.map(r => ({
          schedule_id: String(r.schedule_id ?? ''),
          product: String(r.product ?? ''),
          asin: String(r.asin ?? ''),
          shipment_type: Number(r.shipment_type ?? 0),
          shipment_type_name: String(r.shipment_type_name ?? ''),
          route: String(r.route ?? ''),
          transit_type: String(r.transit_type ?? ''),
          transit_days: Number(r.transit_days ?? 0),
          priority: Number(r.priority ?? 0),
          days_until_oos: Number(r.days_until_oos ?? 0),
          ship_qty: Number(r.ship_qty ?? 0),
          ship_cartons: Number(r.ship_cartons ?? 0),
          mfr_ready_before: Number(r.mfr_ready_before ?? 0),
          in_production: Number(r.in_production ?? 0),
          prior_type_allocations: 0,
          needs_new_po: r.needs_new_po === true || r.needs_new_po === 'true',
          new_po_qty: r.new_po_qty != null ? Number(r.new_po_qty) : null,
          po_ready_date: null,
          ship_wednesday: String(r.ship_wednesday ?? '').split('T')[0],
          amazon_plan_date: String(r.amazon_plan_date ?? '').split('T')[0],
          arrival_date: String(r.arrival_date ?? '').split('T')[0],
          shipment_num: r.shipment_num != null ? Number(r.shipment_num) : null,
          available_stock: Number(r.available_stock ?? 0),
          fba_stock: Number(r.fba_stock ?? 0),
          awd_stock: Number(r.awd_stock ?? 0),
          in_transit: Number(r.in_transit ?? 0),
          demand_window: Number(r.demand_window ?? 0),
          demand_awd_window: Number(r.demand_awd_window ?? 0),
          shipment_trigger_reason: String(r.shipment_trigger_reason ?? ''),
          ship_qty_reason: String(r.ship_qty_reason ?? ''),
        })).filter(r => r.product && r.ship_qty > 0);
        setRows(mapped);
      } catch (e) { console.warn('[ShipmentEngine] plan load failed', e); }
      setLoading(false);
    })();
  }, [refreshKey]);
  return { suggestions: rows, loading, reload };
}

/** Load DE_SCHEDULED_SHIPMENTS (approved + scheduled only, not SUGGESTED) via Flask API */
export function useScheduledShipments() {
  const [rows, setRows] = useState<ScheduledShipmentRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshKey, setRefreshKey] = useState(0);

  const reload = useCallback(() => setRefreshKey(k => k + 1), []);

  useEffect(() => {
    (async () => {
      try {
        const data = await fetchScheduledShipments();
        const nonSuggested = data.filter(r => String(r.status) !== 'SUGGESTED');
        const mapped: ScheduledShipmentRow[] = nonSuggested.map(r => ({
          schedule_id: String(r.schedule_id ?? ''),
          product: String(r.product ?? ''),
          asin: String(r.asin ?? ''),
          shipment_type: Number(r.shipment_type ?? 0),
          shipment_type_name: String(r.shipment_type_name ?? ''),
          route: String(r.route ?? ''),
          transit_type: String(r.transit_type ?? ''),
          ship_qty: Number(r.ship_qty ?? 0),
          ship_cartons: Number(r.ship_cartons ?? 0),
          ship_wednesday: String(r.ship_wednesday ?? '').split('T')[0],
          amazon_plan_date: '',
          arrival_date: String(r.arrival_date ?? '').split('T')[0],
          shipment_num: r.shipment_num != null ? Number(r.shipment_num) : null,
          status: String(r.status ?? 'APPROVED') as 'APPROVED' | 'SCHEDULED',
          shipment_trigger_reason: String(r.shipment_trigger_reason ?? ''),
          ship_qty_reason: String(r.ship_qty_reason ?? ''),
          approved_at: String(r.approved_at ?? ''),
          scheduled_at: r.scheduled_at ? String(r.scheduled_at) : null,
        })).filter(r => r.schedule_id && r.product);
        setRows(mapped);
      } catch (e) { console.warn('[ShipmentEngine] scheduled load failed', e); }
      setLoading(false);
    })();
  }, [refreshKey]);
  return { scheduled: rows, loading, reload };
}

/** Load arrived + in-transit shipments from ShipmentsDashboard */
export function useShipmentHistory() {
  const [arrived, setArrived] = useState<{ product: string; type: string; qty: number; date: string }[]>([]);
  const [inTransit, setInTransit] = useState<{ product: string; type: string; qty: number; eta: string; ship_date: string }[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    (async () => {
      try {
        // Load per-product line-level data to avoid double-counting multi-product shipments
        const data = await cubeLoad({
          dimensions: [
            'ShipmentLineDashboard.productName', 'ShipmentLineDashboard.shipmentType',
            'ShipmentLineDashboard.shipmentStatus', 'ShipmentLineDashboard.estimatedArrivalDate',
            'ShipmentLineDashboard.shipmentDate',
          ],
          measures: ['ShipmentLineDashboard.totalQtyShipped'],
        });
        const arr: typeof arrived = [];
        const trans: typeof inTransit = [];
        for (const r of data as Record<string, unknown>[]) {
          const status = String(r['ShipmentLineDashboard.shipmentStatus'] ?? '');
          const product = String(r['ShipmentLineDashboard.productName'] ?? '');
          const type = String(r['ShipmentLineDashboard.shipmentType'] ?? '');
          const qty = Number(r['ShipmentLineDashboard.totalQtyShipped'] ?? 0);
          const eta = String(r['ShipmentLineDashboard.estimatedArrivalDate'] ?? '').split('T')[0];
          const shipDate = String(r['ShipmentLineDashboard.shipmentDate'] ?? '').split('T')[0];
          if (!product || qty <= 0) continue;
          // Classify as arrived if status says so, OR if ETA has already passed (stale PENDING)
          const etaPassed = eta && eta <= new Date().toISOString().split('T')[0];
          if (['PUT_AWAY', 'RECEIVED', 'INSPECTED'].includes(status) || etaPassed) {
            arr.push({ product, type, qty, date: shipDate });
          } else {
            trans.push({ product, type, qty, eta, ship_date: shipDate });
          }
        }
        setArrived(arr);
        setInTransit(trans);
      } catch (e) { console.warn('[ShipmentEngine] history load failed', e); }
      setLoading(false);
    })();
  }, []);
  return { arrived, inTransit, loading };
}

/** PO record for replenishment flow */
export interface PORecord {
  product: string; po_id: string; qty_remaining: number;
  order_date: string; ready_date: string; production_status: 'READY' | 'IN_PRODUCTION';
}

/** Load open POs with remaining qty > 0 */
export function usePurchaseOrdersFlow() {
  const [rows, setRows] = useState<PORecord[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    (async () => {
      try {
        const data = await cubeLoad({
          dimensions: [
            'PurchaseOrdersDashboard.purchaseOrderId',
            'PurchaseOrdersDashboard.productName',
            'PurchaseOrdersDashboard.orderDate',
            'PurchaseOrdersDashboard.quantity',
            'PurchaseOrdersDashboard.remainingToShip',
            'PurchaseOrdersDashboard.isOpen',
          ],
        });
        const mapped: PORecord[] = [];
        for (const r of data as Record<string, unknown>[]) {
          const remaining = Number(r['PurchaseOrdersDashboard.remainingToShip'] ?? 0);
          const isOpen = r['PurchaseOrdersDashboard.isOpen'];
          if (remaining <= 0 || isOpen === false || isOpen === 'false') continue;
          const orderDate = String(r['PurchaseOrdersDashboard.orderDate'] ?? '').split('T')[0];
          // Estimate ready date: order_date + 35 days (avg manufacture). Exact per-product would need DIM_PRODUCT join.
          const od = new Date(orderDate);
          const readyDate = new Date(od.getTime() + 35 * 86400000).toISOString().split('T')[0];
          const isPast = new Date(readyDate) <= new Date();
          mapped.push({
            product: String(r['PurchaseOrdersDashboard.productName'] ?? ''),
            po_id: String(r['PurchaseOrdersDashboard.purchaseOrderId'] ?? ''),
            qty_remaining: remaining,
            order_date: orderDate,
            ready_date: readyDate,
            production_status: isPast ? 'READY' : 'IN_PRODUCTION',
          });
        }
        setRows(mapped);
      } catch (e) { console.warn('[ShipmentEngine] PO load failed', e); }
      setLoading(false);
    })();
  }, []);
  return { purchaseOrders: rows, loading };
}

// ─── API calls ────────────────────────────────────────────
async function apiCall(url: string, opts: RequestInit) {
  const base = FLASK_API || '';
  const fullUrl = `${base}${url}`;
  console.log(`[apiCall] ${opts.method || 'GET'} ${fullUrl}`, opts.body ? JSON.parse(opts.body as string) : '');
  const res = await fetch(fullUrl, { ...opts, headers: { 'Content-Type': 'application/json', ...opts.headers } });
  const body = await res.json().catch(() => null);
  console.log(`[apiCall] Response ${res.status}:`, body);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}: ${JSON.stringify(body)}`);
  return body;
}

function approveShipment(scheduleId: string, qty?: number, recalculate?: boolean) {
  const body: any = { schedule_id: scheduleId };
  if (qty !== undefined) body.ship_qty = qty;
  if (recalculate !== undefined) body.recalculate = recalculate;
  return apiCall('/api/shipment-plan/approve', { method: 'POST', body: JSON.stringify(body) });
}
function approveProductBulk(product: string) {
  return apiCall('/api/shipment-plan/approve-product', { method: 'POST', body: JSON.stringify({ product }) });
}
function unapproveProductBulk(product: string) {
  return apiCall('/api/shipment-plan/unapprove-product', { method: 'POST', body: JSON.stringify({ product }) });
}
function updateQty(scheduleId: string, qty: number) {
  return apiCall(`/api/shipment-plan/${scheduleId}/qty`, { method: 'PUT', body: JSON.stringify({ ship_qty: qty }) });
}
function scheduleShipment(scheduleId: string) {
  return apiCall(`/api/shipment-plan/${scheduleId}/schedule`, { method: 'PUT' });
}
function revertShipment(scheduleId: string) {
  return apiCall(`/api/shipment-plan/${scheduleId}/revert`, { method: 'DELETE' });
}
function unscheduleShipment(scheduleId: string) {
  return apiCall(`/api/shipment-plan/${scheduleId}/unschedule`, { method: 'PUT' });
}
function updatePoEta(poId: string, date: string) {
  return apiCall(`/api/po/${poId}/update-eta`, { method: 'POST', body: JSON.stringify({ estimated_arrival_date: date }) });
}

// ─── Shared helpers ───────────────────────────────────────
const fmtDate = (s: string) => {
  if (!s) return '—';
  const d = new Date(s);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
};

/** Timeline range: start of this year → end of March next year */
function getTimelineRange(inTransitShipments: { ship_date: string }[]): { minDate: number; maxDate: number } {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const startOfYear = new Date(today.getFullYear(), 0, 1);
  // End of March next year — aligns with stock projection horizon
  const endOfMarch = new Date(today.getFullYear() + 1, 2, 31); // March 31 next year
  return {
    minDate: startOfYear.getTime(),
    maxDate: endOfMarch.getTime(),
  };
}

// ═══════════════════════════════════════════════════════════
// REPLENISHMENT FLOW SECTION
// ═══════════════════════════════════════════════════════════

function FlowNode({ label, qty, color, remaining }: {
  label: string; qty: number; color: string; remaining?: number;
}) {
  if (qty === 0) return null;
  return (
    <div className="flex flex-col items-center" style={{ minWidth: 90 }}>
      <div className="rounded-xl border px-4 py-2 text-center w-full"
        style={{ borderColor: color + '50', background: color + '18' }}>
        <div className="text-[8px] uppercase tracking-wider font-bold" style={{ color }}>{label}</div>
        <div className="text-lg font-bold tabular-nums" style={{ color: 'var(--color-text)' }}>{fmt(qty)}</div>
      </div>
      {remaining !== undefined && (
        <div className="text-[9px] text-muted mt-0.5 tabular-nums">rem {fmt(remaining)}</div>
      )}
    </div>
  );
}

function FlowArrow() {
  return <ArrowRight size={12} className="text-muted/30 mx-0.5 flex-shrink-0 mt-2" />;
}

/** Shipment item for timeline */
interface ShipmentItem {
  product: string; type: string; qty: number; cartons?: number;
  ship_date: string; arrival_date: string;
  status: 'arrived' | 'transit' | 'approved' | 'scheduled' | 'suggested' | 'po_needed' | 'po';
  schedule_id?: string;
  po_id?: string;
  trigger_reason?: string;
  qty_reason?: string;
  route?: string;
  transit_type?: string;
}

/** Color bar by TYPE — uniform height, qty + dates as text */
function TypeBar({ sh, minDate, maxDate, onAddPo, onAddShipment, onEditEta }: {
  sh: ShipmentItem; minDate: number; maxDate: number;
  onAddPo?: (sh: ShipmentItem) => void;
  onAddShipment?: (sh: ShipmentItem) => void;
  onEditEta?: (poId: string) => void;
}) {
  const range = maxDate - minDate || 1;
  const shipTs = Math.max(new Date(sh.ship_date).getTime(), minDate);
  const arrTs = new Date(sh.arrival_date).getTime();
  const left = ((shipTs - minDate) / range) * 100;
  const width = Math.max(3, ((arrTs - shipTs) / range) * 100);
  const clampedLeft = Math.max(0, left);
  const clampedWidth = Math.min(width, 100 - clampedLeft);

  const typeColor = TYPE_COLORS[sh.type] ?? '#64748b';
  const isDashed = sh.status === 'suggested' || sh.status === 'po_needed';
  const isDotted = sh.status === 'approved';
  const isPo = sh.status === 'po';
  const needsPo = sh.status === 'po_needed';
  const isSolid = !isDashed && !isDotted && !isPo;

  const tooltip = [
    needsPo ? `PO NEEDED — ${fmt(sh.qty)} units` :
    isPo ? `PO — ${fmt(sh.qty)} units` : `${sh.type.replace(/_/g, ' ')} — ${sh.status.toUpperCase()}`,
    !isPo && !needsPo ? `${fmt(sh.qty)} units${sh.cartons ? ` (${sh.cartons} ctns)` : ''}` : '',
    isPo || needsPo ? `Order by: ${fmtDate(sh.ship_date)} → Ready: ${fmtDate(sh.arrival_date)}` : `Ship: ${fmtDate(sh.ship_date)} → Arrive: ${fmtDate(sh.arrival_date)}`,
    sh.route ? `Route: ${sh.route}` : '',
    sh.transit_type ? `Transit: ${sh.transit_type}` : '',
    sh.trigger_reason ? `Trigger: ${sh.trigger_reason}` : '',
    sh.qty_reason ? `Qty: ${sh.qty_reason}` : '',
  ].filter(Boolean).join('\n');

  return (
    <div className="relative h-7 flex items-center">
      {/* Bar */}
      <div className="absolute h-5" title={tooltip} style={{
        left: `${clampedLeft}%`,
        width: `${clampedWidth}%`,
        background: isPo ? typeColor + '15' : isSolid ? typeColor : needsPo ? 'transparent' : typeColor + '25',
        opacity: isSolid ? 0.9 : 1,
        border: isPo ? `1px solid ${typeColor}` : isDashed ? `1.5px dashed ${typeColor}` : isDotted ? `1.5px dotted ${typeColor}` : 'none',
        borderRadius: isPo || needsPo ? '2px' : '10px',
      }} />
      {/* Text on bar: ship date — qty — arrival date */}
      <div className="absolute flex items-center justify-between pointer-events-none text-[8px] tabular-nums px-1" style={{
        left: `${clampedLeft}%`,
        width: `${clampedWidth}%`,
        height: 20,
      }}>
        <span className="font-medium truncate" style={{ color: 'var(--color-muted)' }}>{fmtDate(sh.ship_date)}</span>
        <span className="font-bold" style={{ color: 'var(--color-text)' }}>{fmt(sh.qty)}{sh.cartons ? <span className="font-normal text-[7px]" style={{ color: 'var(--color-subtle)' }}> ({sh.cartons})</span> : null}</span>
        <span className="font-medium truncate" style={{ color: 'var(--color-muted)' }}>{fmtDate(sh.arrival_date)}</span>
      </div>

      {/* Add PO Button */}
      {sh.status === 'po_needed' && onAddPo && (
        <div className="absolute z-20 flex items-center" style={{ left: `${clampedLeft + clampedWidth}%`, height: '100%', paddingLeft: 6 }}>
          <button 
             onClick={(e) => { e.stopPropagation(); onAddPo(sh); }}
             className="bg-emerald-500/20 hover:bg-emerald-500/40 text-emerald-400 rounded-full w-4 h-4 flex items-center justify-center transition-colors shadow-sm cursor-pointer"
             title="Add to PO Draft"
          >
             <Plus size={10} strokeWidth={3} />
          </button>
        </div>
      )}
      {/* Add Shipment Button */}
      {sh.status === 'approved' && onAddShipment && (
        <div className="absolute z-20 flex items-center gap-1" style={{ left: `${clampedLeft + clampedWidth}%`, height: '100%', paddingLeft: 6 }}>
          <button 
             onClick={(e) => { e.stopPropagation(); onAddShipment(sh); }}
             className="bg-blue-500/20 hover:bg-blue-500/40 text-blue-400 rounded-full w-4 h-4 flex items-center justify-center transition-colors shadow-sm cursor-pointer"
             title={`Add ${sh.type.replace(/_/g, ' ')} to Shipment Draft (${sh.transit_type || 'N/A'})`}
          >
             <Plus size={10} strokeWidth={3} />
          </button>
          <span className="text-[7px] font-medium whitespace-nowrap pointer-events-none" style={{ color: typeColor, opacity: 0.7 }}>{sh.type.replace(/_/g, ' ')}</span>
        </div>
      )}
      {/* Edit ETA Button + inline popup for POs */}
      {sh.status === 'po' && sh.po_id && onEditEta && (
        <div className="absolute z-20 flex items-center" style={{ left: `${clampedLeft + clampedWidth}%`, height: '100%', paddingLeft: 6 }}>
          <button 
             onClick={(e) => { e.stopPropagation(); onEditEta(sh.po_id!); }}
             className="bg-purple-500/20 hover:bg-purple-500/40 text-purple-400 rounded-full w-4 h-4 flex items-center justify-center transition-colors shadow-sm cursor-pointer"
             title="Update arrival date"
          >
             <CalendarDays size={9} strokeWidth={2.5} />
          </button>
        </div>
      )}
    </div>
  );
}

/** Legend for shipment types */
function TypeLegend({ types }: { types: string[] }) {
  const unique = [...new Set(types)];
  if (unique.length === 0) return null;
  return (
    <div className="flex items-center gap-3 text-[9px] text-muted">
      {unique.map(t => (
        <span key={t} className="flex items-center gap-1">
          <span className="inline-block w-2.5 h-2.5 rounded-sm" style={{ background: TYPE_COLORS[t] ?? '#64748b' }} />
          {t.replace(/_/g, ' ')}
        </span>
      ))}
      <span className="text-muted/40 ml-2">|</span>
      <span className="text-muted/50">━ scheduled / PO</span>
      <span className="text-muted/50">┈ approved</span>
      <span className="text-muted/50">╌ suggested</span>
      <span className="text-muted/50">╌ PO NEEDED</span>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════
// WATERFALL CHART — single-line visualization
// Bars go UP for adds (MFR supply) and DOWN for reduces (demand coverage)
// ═══════════════════════════════════════════════════════════

interface WaterfallSegment {
  label: string;
  value: number;
  color: string;
  group: 'sellable' | 'ontheway' | 'mfr' | 'gap';
}

function buildWaterfallSegments(f: {
  yearlyPlan: number; fba: number; awd: number; inTransit: number;
  mfrReady: number; mfrInProd: number; poSuggested: number;
  approved: number; scheduled: number; suggested: number;
  poFeasible?: boolean;
}): { segments: WaterfallSegment[]; planned: number; gap: number } {
  const poFeasible = f.poFeasible !== false;
  const segments: WaterfallSegment[] = [];

  // Sellable group
  if (f.fba > 0) segments.push({ label: 'FBA', value: f.fba, color: NODE_COLORS.fba, group: 'sellable' });
  if (f.awd > 0) segments.push({ label: 'AWD', value: f.awd, color: NODE_COLORS.awd, group: 'sellable' });

  // On the Way group
  if (f.inTransit > 0) segments.push({ label: 'In Transit', value: f.inTransit, color: NODE_COLORS.inTransit, group: 'ontheway' });
  if (f.approved > 0) segments.push({ label: 'Shipments', value: f.approved, color: NODE_COLORS.approved, group: 'ontheway' });
  if (f.scheduled > 0) segments.push({ label: 'Scheduled', value: f.scheduled, color: NODE_COLORS.scheduled, group: 'ontheway' });

  // MFR group
  if (f.mfrReady > 0) segments.push({ label: 'MFR', value: f.mfrReady, color: NODE_COLORS.mfrReady, group: 'mfr' });
  if (f.mfrInProd > 0) segments.push({ label: 'In Prod', value: f.mfrInProd, color: NODE_COLORS.mfrInProd, group: 'mfr' });
  if (f.poSuggested > 0 && poFeasible) segments.push({ label: 'PO Sugg', value: f.poSuggested, color: NODE_COLORS.poSugg, group: 'mfr' });

  const totalSupply = segments.reduce((s, seg) => s + seg.value, 0);
  const gap = Math.max(0, f.yearlyPlan - totalSupply);

  if (gap > 0) {
    segments.push({ label: !poFeasible && f.poSuggested > 0 ? 'Gap (Expired)' : 'Gap', value: gap, color: NODE_COLORS.toShip, group: 'gap' });
  }

  return { segments, planned: f.yearlyPlan, gap };
}

const GROUP_LABELS: Record<string, string> = {
  sellable: 'Sellable',
  ontheway: 'On the Way',
  mfr: 'MFR',
  gap: '',
};

const GROUP_COLORS: Record<string, string> = {
  sellable: NODE_COLORS.fba,
  ontheway: NODE_COLORS.inTransit,
  mfr: NODE_COLORS.mfr,
  gap: NODE_COLORS.toShip,
};

function WaterfallChart({ segments, planned, gap, compact }: {
  segments: WaterfallSegment[];
  planned: number;
  gap: number;
  compact?: boolean;
}) {
  const barH = compact ? 26 : 32;
  const covered = gap === 0;
  const total = Math.max(planned, 1);
  const pct = (v: number) => Math.max(0, (v / total) * 100);

  // Group segments for bottom labels
  const groups: { group: string; totalValue: number; segments: WaterfallSegment[] }[] = [];
  for (const seg of segments) {
    const last = groups[groups.length - 1];
    if (last && last.group === seg.group) {
      last.totalValue += seg.value;
      last.segments.push(seg);
    } else {
      groups.push({ group: seg.group, totalValue: seg.value, segments: [seg] });
    }
  }

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-1.5">
        <span style={{ fontSize: compact ? '10px' : '11px', color: 'var(--color-muted)', fontWeight: 600 }}>
          Rem. Planned
        </span>
        <span className="tabular-nums" style={{ fontSize: compact ? '12px' : '14px', fontWeight: 700, color: NODE_COLORS.plan }}>
          {fmt(planned)}
        </span>
      </div>

      {/* Single stacked bar */}
      <div className="flex rounded-lg overflow-hidden" style={{ height: barH, background: 'var(--color-surface)' }}>
        {segments.map((seg, i) => {
          const w = pct(seg.value);
          if (w < 0.5) return null;
          const isGap = seg.group === 'gap';
          return (
            <div key={i} className="relative flex items-center justify-center transition-all duration-300"
              style={{
                width: `${w}%`,
                background: isGap
                  ? `repeating-linear-gradient(135deg, ${seg.color}15, ${seg.color}15 4px, transparent 4px, transparent 8px)`
                  : seg.color + '30',
                borderRight: i < segments.length - 1 ? `1px solid ${seg.color}50` : 'none',
              }}
              title={`${seg.label}: ${fmt(seg.value)}`}
            >
              {w >= 4 && (
                <span className="tabular-nums" style={{
                  fontSize: compact ? '9px' : '11px', fontWeight: 700,
                  color: seg.color, whiteSpace: 'nowrap',
                  textShadow: '0 0 8px var(--color-bg)',
                }}>
                  {fmt(seg.value)}
                </span>
              )}
            </div>
          );
        })}
        {covered && (
          <div className="flex items-center justify-center px-2" style={{ minWidth: 20 }}>
            <span style={{ fontSize: '12px', fontWeight: 700, color: '#22c55e' }}>✓</span>
          </div>
        )}
      </div>

      {/* Segment labels below bar */}
      <div className="flex mt-1" style={{ gap: 0 }}>
        {segments.map((seg, i) => {
          const w = pct(seg.value);
          if (w < 0.5) return null;
          return (
            <div key={i} className="flex flex-col items-center" style={{ width: `${w}%` }}>
              <span className="tabular-nums" style={{
                fontSize: compact ? '8px' : '9px', fontWeight: 600,
                color: seg.color, whiteSpace: 'nowrap',
              }}>
                {seg.label}
              </span>
            </div>
          );
        })}
        {covered && (
          <div className="flex flex-col items-center" style={{ minWidth: 20 }}>
            <span style={{ fontSize: compact ? '8px' : '9px', fontWeight: 700, color: '#22c55e' }}>
              Covered
            </span>
          </div>
        )}
      </div>
    </div>
  );
}

/** Per-product flow data */
interface ProductFlow {
  product: string;
  family: string;
  yearlyPlan: number;
  unconstrainedForecast?: number;
  stock: number; stockRem: number;
  fba: number; awd: number;
  inTransit: number; transitRem: number;
  mfrReady: number; mfrReadyRem: number;
  mfrInProd: number; mfrInProdRem: number;
  poSuggested: number; poSuggestedRem: number;
  approved: number; approvedRem: number;
  scheduled: number; scheduledRem: number;
  suggested: number; suggestedRem: number;
  toShip: number;
  allShipments: ShipmentItem[];
  hasSuggested: boolean;
  hasApproved: boolean;
}

export function ReplenishmentFlowSection({ yearlyPlanMap, unconstrainedForecastMap, salesSummary, stockMap, fbaMap, awdMap, mfrReadyMap, mfrInProdMap, suggestions, scheduled, inTransitShipments, arrivedShipments, onAction, demandMap, seasonMap, metaMap, growthOverrides, poFeasibleMap, activePOs, productMeta, onUpdateEtaOptimistic }: {
  yearlyPlanMap: Record<string, number>;
  unconstrainedForecastMap?: Record<string, number>;
  salesSummary: {asin: string; product_name: string; sold: number}[];
  stockMap: Record<string, number>;
  fbaMap?: Record<string, number>;
  awdMap?: Record<string, number>;
  mfrReadyMap?: Record<string, number>;
  mfrInProdMap?: Record<string, number>;
  suggestions: ShipmentPlanFactRow[];
  scheduled: ScheduledShipmentRow[];
  inTransitShipments: { product: string; type: string; qty: number; eta: string; ship_date: string }[];
  arrivedShipments: { product: string; type: string; qty: number; date: string }[];
  onAction: () => void;
  demandMap?: ForecastDemandMap;
  seasonMap?: MonthSeasonMap;
  metaMap?: ForecastMetaMap;
  growthOverrides?: Record<string, number>;
  poFeasibleMap?: Record<string, boolean>;
  activePOs?: ActivePORow[];
  productMeta?: any[];
  onUpdateEtaOptimistic?: (poId: string, date: string) => void;
}) {
  const [expandedProduct, setExpandedProduct] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [editQty, setEditQty] = useState<Record<string, number>>({});

  const [draftPOLines, setDraftPOLines] = useState<DraftPOLine[]>([]);
  const [showPOModal, setShowPOModal] = useState(false);

  const [draftShipmentLines, setDraftShipmentLines] = useState<DraftShipmentLine[]>([]);
  const [showShipmentModal, setShowShipmentModal] = useState(false);
  const [draftShipmentType, setDraftShipmentType] = useState<string | undefined>();
  const [draftShipmentDate, setDraftShipmentDate] = useState<string | undefined>();

  const [editEtaPoId, setEditEtaPoId] = useState<string | null>(null);
  const handleEditEta = useCallback(async (poId: string, date: string) => {
    setBusy(poId);
    if (onUpdateEtaOptimistic) onUpdateEtaOptimistic(poId, date);
    try {
      await updatePoEta(poId, date);
      setEditEtaPoId(null);
      onAction();
    } catch (e) { console.error(e); }
    setBusy(null);
  }, [onAction, onUpdateEtaOptimistic]);

  const handleAddPoLine = useCallback((sh: ShipmentItem) => {
    const pMeta = productMeta?.find(p => p.product_short_name === sh.product);
    const asin = pMeta?.asin || 'UNKNOWN';
    const cogs = pMeta?.cogs || 0;
    
    setDraftPOLines(prev => {
      // Update qty if it already exists, otherwise add it
      const existing = prev.find(l => l.product === sh.product);
      if (existing) {
        return prev.map(l => l.product === sh.product ? { ...l, qty: sh.qty } : l);
      }
      return [...prev, { product: sh.product, qty: sh.qty, asin, cogs }];
    });
  }, [productMeta]);

  const handleAddShipmentLine = useCallback((sh: ShipmentItem) => {
    console.log('[ShipmentEngine] handleAddShipmentLine called:', {
      product: sh.product, type: sh.type, transit_type: sh.transit_type,
      ship_date: sh.ship_date, qty: sh.qty
    });
    const pMeta = productMeta?.find(p => p.product_short_name === sh.product);
    const asin = pMeta?.asin || 'UNKNOWN';
    
    setDraftShipmentLines([{ product: sh.product, qty: sh.qty, asin }]);
    // Derive correct transit type: AWD/Q4 shipments always use AWD_SLOW_SEA
    const resolvedType = (sh.type === 'AWD_MAINTENANCE' || sh.type === 'Q4_BULK')
      ? 'AWD_SLOW_SEA'
      : sh.transit_type;
    console.log('[ShipmentEngine] resolvedType:', resolvedType);
    setDraftShipmentType(resolvedType);
    setDraftShipmentDate(sh.ship_date);
    setShowShipmentModal(true);
  }, [productMeta]);

  // Fetch weekly actual sales per product from Cube (for stock projection tooltip)
  const [weeklySalesMap, setWeeklySalesMap] = useState<Record<string, Record<string, number>>>({});
  const [weeklySalesLYMap, setWeeklySalesLYMap] = useState<Record<string, Record<string, number>>>({});
  useEffect(() => {
    const thisYear = new Date().getFullYear();
    const startOfYear = `${thisYear}-01-01`;
    const today = new Date().toISOString().split('T')[0];
    const token = localStorage.getItem('dashboard_token');
    const headers: Record<string, string> = {};
    if (token) headers['Authorization'] = `Bearer ${token}`;

    // This year
    fetch(`${CUBE_API}/cubejs-api/v1/load?query=${encodeURIComponent(JSON.stringify({
      measures: ['UnifiedPerformance.units'],
      dimensions: ['UnifiedPerformance.productShortName', 'UnifiedPerformance.weekStart'],
      timeDimensions: [{ dimension: 'UnifiedPerformance.date', dateRange: [startOfYear, today] }],
    }))}`, { headers })
      .then(r => r.json())
      .then(d => {
        const map: Record<string, Record<string, number>> = {};
        for (const row of d.data || []) {
          const product = row['UnifiedPerformance.productShortName'];
          const weekRaw = row['UnifiedPerformance.weekStart'];
          const units = Number(row['UnifiedPerformance.units']) || 0;
          if (!product || !weekRaw) continue;
          // weekStart in BQ is Sunday-based; parse and align to Monday (local time)
          const parts = weekRaw.split('T')[0].split('-');
          const sun = new Date(+parts[0], +parts[1] - 1, +parts[2]);
          sun.setDate(sun.getDate() + 1); // Sunday → Monday
          const key = `${sun.getFullYear()}-${String(sun.getMonth() + 1).padStart(2, '0')}-${String(sun.getDate()).padStart(2, '0')}`;
          if (!map[product]) map[product] = {};
          map[product][key] = (map[product][key] || 0) + units;
        }
        setWeeklySalesMap(map);
      })
      .catch(e => console.warn('[ShipmentEngine] Weekly sales fetch failed', e));

    // Last year — shifted +1 year so keys align with this year's chart
    const lyStart = `${thisYear - 1}-01-01`;
    const lyEnd = `${thisYear - 1}-12-31`;
    fetch(`${CUBE_API}/cubejs-api/v1/load?query=${encodeURIComponent(JSON.stringify({
      measures: ['UnifiedPerformance.units'],
      dimensions: ['UnifiedPerformance.productShortName', 'UnifiedPerformance.weekStart'],
      timeDimensions: [{ dimension: 'UnifiedPerformance.date', dateRange: [lyStart, lyEnd] }],
    }))}`, { headers })
      .then(r => r.json())
      .then(d => {
        const map: Record<string, Record<string, number>> = {};
        for (const row of d.data || []) {
          const product = row['UnifiedPerformance.productShortName'];
          const weekRaw = row['UnifiedPerformance.weekStart'];
          const units = Number(row['UnifiedPerformance.units']) || 0;
          if (!product || !weekRaw) continue;
          const parts = weekRaw.split('T')[0].split('-');
          const sun = new Date(+parts[0], +parts[1] - 1, +parts[2]);
          sun.setDate(sun.getDate() + 1); // Sunday → Monday
          // Shift to this year — then snap back to Monday of that week
          sun.setFullYear(sun.getFullYear() + 1);
          const dow = sun.getDay();
          sun.setDate(sun.getDate() - dow + (dow === 0 ? -6 : 1));
          const key = `${sun.getFullYear()}-${String(sun.getMonth() + 1).padStart(2, '0')}-${String(sun.getDate()).padStart(2, '0')}`;
          if (!map[product]) map[product] = {};
          map[product][key] = (map[product][key] || 0) + units;
        }
        console.log('[ShipmentEngine] LY sales loaded:', Object.keys(map).length, 'products',
          Object.fromEntries(Object.entries(map).map(([p, wks]) => [p, { weeks: Object.keys(wks).length, sample: Object.entries(wks).slice(0, 3) }])));
        setWeeklySalesLYMap(map);
      })
      .catch(e => console.warn('[ShipmentEngine] LY sales fetch failed', e));
  }, []);

  const { minDate, maxDate } = useMemo(() => getTimelineRange(inTransitShipments), [inTransitShipments]);

  const products = useMemo(() => [...new Set([
    ...Object.keys(yearlyPlanMap),
    ...suggestions.map(s => s.product),
    ...scheduled.map(s => s.product),
  ])].sort(), [yearlyPlanMap, suggestions, scheduled]);

  const flows: ProductFlow[] = useMemo(() => products.map(product => {
    const firstSugg = suggestions.find(s => s.product === product);
    const firstSched = scheduled.find(s => s.product === product);
    const salesRow = salesSummary.find(s => s.product_name === product);
    const asin = salesRow?.asin || firstSugg?.asin || firstSched?.asin;
    
    // First try ASIN mapping, then fallback to string match if ASIN somehow not found
    const family = (asin 
      ? productMeta?.find(p => p.asin === asin)?.family_name 
      : productMeta?.find(p => p.product_short_name === product)?.family_name) ?? 'Other';
    const plan = yearlyPlanMap[product] || 0;
    const unconstrainedForecast = unconstrainedForecastMap?.[product] ?? plan;
    // Subtract YTD sold to get remaining demand
    const ytdSold = salesRow?.sold ?? 0;
    const remaining = Math.max(0, plan - ytdSold);
    const unconstrainedForecastRem = Math.max(0, unconstrainedForecast - ytdSold);
    const stockQty = stockMap[product] || 0;
    const fbaQty = fbaMap?.[product] || 0;
    const awdQty = awdMap?.[product] || 0;
    const transitQty = inTransitShipments.filter(s => s.product === product).reduce((s, r) => s + r.qty, 0);
    const approvedQty = scheduled.filter(s => s.product === product && s.status === 'APPROVED').reduce((s, r) => s + r.ship_qty, 0);
    const scheduledQty = scheduled.filter(s => s.product === product && s.status === 'SCHEDULED').reduce((s, r) => s + r.ship_qty, 0);
    const suggestedQty = suggestions.filter(s => s.product === product).reduce((s, v) => s + v.ship_qty, 0);

    // Manufacturer data: prefer inventory snapshot (always available) over suggestion rows
    // (suggestion rows lose MFR data when all suggestions are approved)
    const mfrReady = mfrReadyMap?.[product] ?? firstSugg?.mfr_ready_before ?? 0;
    const mfrInProd = mfrInProdMap?.[product] ?? firstSugg?.in_production ?? 0;

    const stockRem = remaining - stockQty;
    const transitRem = stockRem - transitQty;

    // ── PO track: Rem - Stock - Transit - MFR Ready - In Prod → PO Suggested
    const mfrReadyRem = transitRem - mfrReady;
    const mfrInProdRem = mfrReadyRem - mfrInProd;
    const poSuggested = Math.max(0, mfrInProdRem); // units to order from manufacturer
    const poSuggestedRem = mfrInProdRem - poSuggested; // should be 0

    // ── Ship track: Rem - Stock - Transit → Approved → Scheduled → Ship Suggested
    const approvedRem = transitRem - approvedQty;
    const scheduledRem = approvedRem - scheduledQty;
    const suggestedRem = scheduledRem - suggestedQty;
    const toShip = Math.max(0, suggestedRem);

    const allShipments: ShipmentItem[] = [
      ...inTransitShipments.filter(s => s.product === product).map(s => ({
        product, type: s.type, qty: s.qty, ship_date: s.ship_date, arrival_date: s.eta,
        status: 'transit' as const,
      })),
      ...scheduled.filter(s => s.product === product && s.status === 'APPROVED').map(s => ({
        product, type: s.shipment_type_name, qty: s.ship_qty, cartons: s.ship_cartons,
        ship_date: s.ship_wednesday, arrival_date: s.arrival_date,
        status: 'approved' as const, schedule_id: s.schedule_id,
        trigger_reason: s.shipment_trigger_reason, qty_reason: s.ship_qty_reason,
        route: s.route, transit_type: s.transit_type,
      })),
      ...scheduled.filter(s => s.product === product && s.status === 'SCHEDULED').map(s => ({
        product, type: s.shipment_type_name, qty: s.ship_qty, cartons: s.ship_cartons,
        ship_date: s.ship_wednesday, arrival_date: s.arrival_date,
        status: 'scheduled' as const, schedule_id: s.schedule_id,
        trigger_reason: s.shipment_trigger_reason, qty_reason: s.ship_qty_reason,
        route: s.route, transit_type: s.transit_type,
      })),
      ...suggestions.filter(s => s.product === product).map(s => ({
        product, type: s.shipment_type_name, qty: s.ship_qty, cartons: s.ship_cartons,
        ship_date: s.ship_wednesday, arrival_date: s.arrival_date,
        status: 'suggested' as const,
        trigger_reason: s.shipment_trigger_reason, qty_reason: s.ship_qty_reason,
        route: s.route, transit_type: s.transit_type,
      })),
      ...(activePOs?.filter(po => {
        const pAsin = productMeta?.find(p => (p.product_short_name || p.product) === product)?.asin;
        return po.product === product || (pAsin && po.asin === pAsin);
      }) || []).map(po => {
        const mfrDay = productMeta?.find(p => p.asin === po.asin)?.manufacture_day ?? 30;
        const od = new Date(po.order_date);
        const computedArrival = new Date(od.getTime() + mfrDay * 86400000).toISOString().split('T')[0];
        const arrival = po.estimated_arrival_date || computedArrival;
        return {
          product, type: 'Purchase Order', qty: po.qty, cartons: 0,
          ship_date: po.order_date, arrival_date: arrival,
          status: 'po' as const,
          po_id: po.po_id,
          trigger_reason: 'Active Purchase Order', qty_reason: 'Ordered qty',
          route: 'MFR', transit_type: 'MFR',
        };
      }),
    ].sort((a, b) => a.ship_date.localeCompare(b.ship_date));

    // Add PO needed bar: qty = waterfall gap (remaining after all existing supply)
    const poGap = Math.max(0, mfrInProdRem);  // what's left after stock + transit + mfrReady + mfrInProd
    if (poGap > 0) {
      const today = new Date();
      const orderByDate = today.toISOString().split('T')[0];
      // Manufacture period: ~42 days for Lollibox, ~30 for LolliME — use 35 as default
      const mfrDays = product.toLowerCase().includes('lolli') && !product.toLowerCase().includes('me') ? 42 : 30;
      const readyDate = new Date(today.getTime() + mfrDays * 86400000).toISOString().split('T')[0];
      allShipments.unshift({
        product, type: 'PO_NEEDED', qty: poGap,
        ship_date: orderByDate, arrival_date: readyDate,
        status: 'po_needed' as const,
        trigger_reason: `New PO needed: ${fmt(poGap)} units`,
        qty_reason: `Order now, ready in ${mfrDays} days`,
      });
    }

    return {
      product, family, yearlyPlan: remaining, unconstrainedForecast: unconstrainedForecastRem,
      stock: stockQty, stockRem, fba: fbaQty, awd: awdQty,
      inTransit: transitQty, transitRem,
      mfrReady, mfrReadyRem,
      mfrInProd, mfrInProdRem,
      poSuggested, poSuggestedRem,
      approved: approvedQty, approvedRem,
      scheduled: scheduledQty, scheduledRem,
      suggested: suggestedQty, suggestedRem,
      toShip, allShipments,
      hasSuggested: suggestedQty > 0,
      hasApproved: approvedQty > 0,
    };
  }).filter(f => f.yearlyPlan > 0 || f.suggested > 0 || f.scheduled > 0 || f.approved > 0 || f.stock > 0 || f.poSuggested > 0 || f.mfrReady > 0 || f.mfrInProd > 0), [products, yearlyPlanMap, salesSummary, stockMap, fbaMap, awdMap, mfrReadyMap, mfrInProdMap, suggestions, scheduled, inTransitShipments]);

  // TOTAL aggregation
  const total = useMemo(() => ({
    plan: flows.reduce((s, f) => s + f.yearlyPlan, 0),
    stock: flows.reduce((s, f) => s + f.stock, 0),
    fba: flows.reduce((s, f) => s + f.fba, 0),
    awd: flows.reduce((s, f) => s + f.awd, 0),
    inTransit: flows.reduce((s, f) => s + f.inTransit, 0),
    mfrReady: flows.reduce((s, f) => s + f.mfrReady, 0),
    mfrInProd: flows.reduce((s, f) => s + f.mfrInProd, 0),
    poSuggested: flows.reduce((s, f) => s + f.poSuggested, 0),
    approved: flows.reduce((s, f) => s + f.approved, 0),
    scheduled: flows.reduce((s, f) => s + f.scheduled, 0),
    suggested: flows.reduce((s, f) => s + f.suggested, 0),
    toShip: flows.reduce((s, f) => s + f.toShip, 0),
    covered: flows.reduce((s, f) => s + f.yearlyPlan - f.toShip, 0),
  }), [flows]);

  // ─── Action handlers ───────────────────────────────────
  const handleApproveProduct = useCallback(async (product: string) => {
    setBusy(`approve-${product}`);
    try {
      await approveProductBulk(product);
      onAction();
    } catch (e) { console.error('Approve product failed', e); }
    setBusy(null);
  }, [onAction]);

  const handleUnapproveProduct = useCallback(async (product: string) => {
    setBusy(`unapprove-${product}`);
    try {
      await unapproveProductBulk(product);
      onAction();
    } catch (e) { console.error('Unapprove product failed', e); }
    setBusy(null);
  }, [onAction]);

  const handleApproveSingle = useCallback(async (product: string, shipType: number, shipWed: string) => {
    const key = `${product}-${shipType}-${shipWed}`;
    setBusy(key);
    try {
      const orig = suggestions.find(s => s.product === product && s.shipment_type === shipType && s.ship_wednesday === shipWed);
      if (orig) await approveShipment(orig.schedule_id);
      onAction();
    } catch (e) { console.error('Approve failed', e); }
    setBusy(null);
  }, [suggestions, onAction]);

  const handleSchedule = useCallback(async (id: string) => {
    setBusy(id); try { await scheduleShipment(id); onAction(); } catch (e) { console.error(e); } setBusy(null);
  }, [onAction]);

  const handleRevert = useCallback(async (id: string) => {
    setBusy(id); try { await revertShipment(id); onAction(); } catch (e) { console.error(e); } setBusy(null);
  }, [onAction]);

  const handleUnschedule = useCallback(async (id: string) => {
    setBusy(id); try { await unscheduleShipment(id); onAction(); } catch (e) { console.error(e); } setBusy(null);
  }, [onAction]);

  const handleQtyUpdate = useCallback(async (id: string, qty: number) => {
    setBusy(id); try { await updateQty(id, qty); onAction(); } catch (e) { console.error(e); } setBusy(null);
  }, [onAction]);

  return (
    <>
    {/* ─── TOTAL overview card ─── */}
    <Section title="Replenishment Overview">
      <div>
      <div className="rounded-lg border border-border/20 bg-surface/30 overflow-hidden px-4 py-3">
        {(() => {
          const w = buildWaterfallSegments({
            yearlyPlan: total.plan, fba: total.fba, awd: total.awd, inTransit: total.inTransit,
            mfrReady: total.mfrReady, mfrInProd: total.mfrInProd, poSuggested: total.poSuggested,
            approved: total.approved, scheduled: total.scheduled, suggested: total.suggested,
            poFeasible: Object.values(poFeasibleMap ?? {}).every(v => v),
          });
          return <WaterfallChart segments={w.segments} planned={w.planned} gap={w.gap} compact />;
        })()}
      </div>
      </div>
    </Section>

    {/* ─── Per-product cards grouped by family ─── */}
    {Object.entries(flows.reduce((acc, f) => {
      if (!acc[f.family]) acc[f.family] = [];
      acc[f.family].push(f);
      return acc;
    }, {} as Record<string, ProductFlow[]>))
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([family, famFlows]) => (
      <div key={family} className="mb-8">
        <h3 className="text-[14px] font-bold text-muted uppercase tracking-wider mb-3 px-1">{family}</h3>
        <div className="space-y-2">
          {famFlows.map(f => {
            const isExp = expandedProduct === f.product;
            const coverage = f.yearlyPlan > 0 ? Math.round((f.yearlyPlan - f.toShip) / f.yearlyPlan * 100) : 100;

            return (
              <div key={f.product} className="rounded border border-border/20 bg-surface/30 overflow-hidden flex flex-col mb-2">
                {/* ── HEADER ── */}
                <div 
                  className={`flex items-center justify-between px-3 py-2 cursor-pointer hover:bg-surface/50 transition-colors ${isExp ? 'bg-surface/50 border-b border-border/20' : ''}`}
                  onClick={() => setExpandedProduct(isExp ? null : f.product)}
                >
                  <div className="flex items-center gap-2">
                    <ChevronRight size={14} className={`text-muted transition-transform ${isExp ? 'rotate-90' : ''}`} />
                    <span className="font-bold text-[13px]">{f.product}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    {/* Mini flow inline pills */}
                    <div className="flex items-center gap-0.5 overflow-hidden">
                      <MiniPill label="Rem" qty={f.yearlyPlan} color={NODE_COLORS.plan} title="Remaining yearly plan" />
                      {f.unconstrainedForecast !== undefined && f.unconstrainedForecast !== f.yearlyPlan && (
                        <MiniPill label="Unconst." qty={f.unconstrainedForecast} color={NODE_COLORS.plan} outlined title="Unconstrained remaining forecast" />
                      )}
                      {f.stock > 0 && <MiniPill label="Sellable" qty={f.stock} color={NODE_COLORS.stock} />}
                      {f.inTransit > 0 && <MiniPill label="Transit" qty={f.inTransit} color={NODE_COLORS.inTransit} />}
                      {f.mfrReady > 0 && <MiniPill label="MFR" qty={f.mfrReady} color={NODE_COLORS.mfr} outlined />}
                      {f.mfrInProd > 0 && <MiniPill label="Prod" qty={f.mfrInProd} color={NODE_COLORS.mfr} outlined />}
                      {f.poSuggested > 0 && <MiniPill label="PO" qty={f.poSuggested} color={NODE_COLORS.mfr} outlined />}
                      {f.approved > 0 && <MiniPill label="Appr" qty={f.approved} color={NODE_COLORS.approved} />}
                      {f.scheduled > 0 && <MiniPill label="Sched" qty={f.scheduled} color={NODE_COLORS.scheduled} />}
                      {f.suggested > 0 && <MiniPill label="Ship" qty={f.suggested} color={NODE_COLORS.suggested} />}
                      {f.toShip > 0 && <MiniPill label="Gap" qty={f.toShip} color={NODE_COLORS.toShip} />}
                    </div>

                    {/* Coverage % */}
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <div className="w-16 h-1.5 rounded-full bg-border/30 overflow-hidden">
                        <div className="h-full rounded-full" style={{
                          width: `${coverage}%`,
                          background: coverage >= 90 ? '#22c55e' : coverage >= 60 ? '#f59e0b' : '#ef4444',
                        }} />
                      </div>
                      <span className="text-[10px] tabular-nums w-8 text-right" style={{ color: 'var(--color-muted)' }}>{coverage}%</span>
                    </div>

                    {/* Action buttons */}
                    {f.hasSuggested && (
                      <button onClick={(e) => { e.stopPropagation(); handleApproveProduct(f.product); }}
                        disabled={busy === `approve-${f.product}`}
                        className={`flex-shrink-0 inline-flex items-center gap-1 px-2.5 py-1 text-[9px] rounded-lg font-bold transition-all whitespace-nowrap ${busy === `approve-${f.product}` ? 'bg-emerald-500/20 border-emerald-500/50 text-emerald-300 cursor-wait' : 'bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20 border border-emerald-500/30'}`}>
                        {busy === `approve-${f.product}` ? <Loader2 size={10} className="animate-spin" /> : <Check size={10} />}
                        {busy === `approve-${f.product}` ? 'Approving…' : 'Approve All'}
                      </button>
                    )}
                    {f.hasApproved && (
                      <button onClick={(e) => { e.stopPropagation(); handleUnapproveProduct(f.product); }}
                        disabled={busy === `unapprove-${f.product}`}
                        className={`flex-shrink-0 inline-flex items-center gap-1 px-2.5 py-1 text-[9px] rounded-lg font-bold transition-all whitespace-nowrap ${busy === `unapprove-${f.product}` ? 'bg-amber-500/20 border-amber-500/50 text-amber-300 cursor-wait' : 'bg-amber-500/10 text-amber-400 hover:bg-amber-500/20 border border-amber-500/30'}`}>
                        {busy === `unapprove-${f.product}` ? <Loader2 size={10} className="animate-spin" /> : <X size={10} />}
                        {busy === `unapprove-${f.product}` ? 'Unapproving…' : 'Unapprove All'}
                      </button>
                    )}
                  </div>
                </div>

                {isExp && (
                  <div className="p-3 bg-surface/10 space-y-2 border-t border-border/20">
                    {/* Card 1: Waterfall chart */}
                    <div className="rounded-lg border border-border/20 bg-surface/30 overflow-hidden px-4 py-3 mb-2">
                      <div className="text-[9px] font-bold text-muted/60 uppercase tracking-wider mb-2">Coverage Waterfall</div>
                      {(() => {
                        const w = buildWaterfallSegments({
                          yearlyPlan: f.yearlyPlan, fba: f.fba, awd: f.awd, inTransit: f.inTransit,
                          mfrReady: f.mfrReady, mfrInProd: f.mfrInProd, poSuggested: f.poSuggested,
                          approved: f.approved, scheduled: f.scheduled, suggested: f.suggested,
                          poFeasible: poFeasibleMap?.[f.product] ?? true,
                        });
                        return <WaterfallChart segments={w.segments} planned={w.planned} gap={w.gap} />;
                      })()}
                    </div>

                    {/* Card 1b: Next Shipment — action card */}
                    {(() => {
                      const nextSugg = f.allShipments
                        .filter(s => s.status === 'suggested' || s.status === 'po_needed')
                        .sort((a, b) => a.ship_date.localeCompare(b.ship_date));
                      if (nextSugg.length === 0) return null;
                      // Group by ship_wednesday (first date)
                      const nextDate = nextSugg[0].ship_date;
                      const nextBatch = nextSugg.filter(s => s.ship_date === nextDate);
                      const isToday = nextDate === new Date().toISOString().split('T')[0];
                      const isPast = nextDate < new Date().toISOString().split('T')[0];
                      const dateLabel = isToday ? 'Today' : isPast ? 'Overdue' : fmtDate(nextDate);

                      return (
                        <div className="rounded-lg border overflow-hidden mb-2" style={{
                          borderColor: isToday || isPast ? '#f59e0b50' : 'var(--color-border-20)',
                          background: isToday || isPast ? 'rgba(245,158,11,0.04)' : 'var(--color-surface-30)',
                        }}>
                          {/* Header */}
                          <div className="flex items-center justify-between px-4 py-2" style={{
                            background: isToday || isPast ? 'rgba(245,158,11,0.08)' : 'var(--color-surface-10)',
                            borderBottom: '1px solid var(--color-border-10)',
                          }}>
                            <div className="flex items-center gap-2">
                              <span className="text-[9px] font-bold uppercase tracking-wider" style={{
                                color: isToday || isPast ? '#f59e0b' : 'var(--color-muted)',
                              }}>
                                Next Shipment
                              </span>
                              <span className="text-[10px] font-bold tabular-nums" style={{
                                color: isToday ? '#f59e0b' : isPast ? '#ef4444' : 'var(--color-heading)',
                              }}>
                                {dateLabel}
                              </span>
                            </div>
                            {f.hasSuggested && (
                              <button onClick={(e) => { e.stopPropagation(); handleApproveProduct(f.product); }}
                                disabled={busy === `approve-${f.product}`}
                                className="inline-flex items-center gap-1 px-2.5 py-1 text-[9px] rounded-lg font-bold transition-all bg-emerald-500/15 text-emerald-400 hover:bg-emerald-500/25 border border-emerald-500/30 whitespace-nowrap"
                              >
                                <Check size={10} /> Approve All
                              </button>
                            )}
                          </div>

                          {/* Action rows */}
                          <div className="divide-y divide-border/10">
                            {nextBatch.map((sh, i) => {
                              const typeColor = TYPE_COLORS[sh.type] ?? '#64748b';
                              const isPO = sh.status === 'po_needed';
                              const dest = sh.type === 'EMERGENCY' ? 'FBA' : 'AWD';
                              const reasonText = sh.trigger_reason || sh.qty_reason || '';

                              return (
                                <div key={i} className="flex items-center gap-3 px-4 py-2.5 hover:bg-surface/20 transition-colors">
                                  {/* Type dot + label */}
                                  <div className="flex items-center gap-2 min-w-[100px]">
                                    <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: typeColor }} />
                                    <span className="text-[10px] font-bold" style={{ color: typeColor }}>
                                      {isPO ? 'PO NEEDED' : sh.type.replace(/_/g, ' ')}
                                    </span>
                                  </div>

                                  {/* Qty + destination */}
                                  <div className="flex items-center gap-1.5 min-w-[80px]">
                                    <span className="text-[12px] font-bold tabular-nums" style={{ color: 'var(--color-heading)' }}>
                                      {fmt(sh.qty)}
                                    </span>
                                    {!isPO && (
                                      <span className="text-[8px] font-bold rounded px-1 py-0.5" style={{
                                        background: dest === 'FBA' ? '#ef444420' : '#3b82f620',
                                        color: dest === 'FBA' ? '#ef4444' : '#3b82f6',
                                      }}>
                                        → {dest}
                                      </span>
                                    )}
                                    {isPO && (
                                      <span className="text-[8px] font-bold rounded px-1 py-0.5" style={{
                                        background: '#14b8a620', color: '#14b8a6',
                                      }}>
                                        units
                                      </span>
                                    )}
                                  </div>

                                  {/* Reasoning */}
                                  <div className="flex-1 text-[9px] text-muted/60 truncate" title={reasonText}>
                                    {reasonText}
                                  </div>

                                  {/* Action button */}
                                  <button
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      if (isPO) { handleAddPoLine(sh); }
                                      else { handleAddShipmentLine(sh); }
                                    }}
                                    className="flex-shrink-0 inline-flex items-center gap-1 px-2 py-1 text-[9px] rounded-md font-bold transition-all border whitespace-nowrap"
                                    style={{
                                      background: typeColor + '15',
                                      borderColor: typeColor + '40',
                                      color: typeColor,
                                    }}
                                  >
                                    <Plus size={9} />
                                    {isPO ? 'Create PO' : 'Ship'}
                                  </button>
                                </div>
                              );
                            })}
                          </div>
                        </div>
                      );
                    })()}

                    {/* Card 2: Timeline — color-coded bars with qty + dates */}
                    {f.allShipments.length > 0 && (
                      <div className="rounded-lg border border-border/20 bg-surface/30 px-4 py-3 mb-2">
                        <div className="text-[9px] font-bold text-muted/60 uppercase tracking-wider mb-2">Shipment Timeline</div>
                        {/* Legend */}
                        <TypeLegend types={f.allShipments.map(s => s.type)} />

                        {/* Timeline axis */}
                        <div className="flex justify-between text-[8px] text-muted/40 mt-2 mb-1 px-0.5">
                          <span>{fmtDate(new Date(minDate).toISOString().split('T')[0])}</span>
                          <span>{fmtDate(new Date(maxDate).toISOString().split('T')[0])}</span>
                        </div>

                        {/* Shipment bars — one row per shipment, sorted by ship date */}
                        <div className="space-y-0.5 relative">
                          {(() => {
                            const nowTs = new Date().getTime();
                            const todayPct = ((nowTs - minDate) / (maxDate - minDate || 1)) * 100;
                            return todayPct >= 0 && todayPct <= 100 && (
                              <div className="absolute top-0 bottom-0 border-l border-dashed border-muted/50 z-10 pointer-events-none" style={{ left: `${todayPct}%` }} title="Today">
                                <span className="absolute -left-3 -top-3.5 text-[8px] font-bold text-muted/60 bg-surface px-0.5 rounded">Today</span>
                              </div>
                            );
                          })()}
                          {f.allShipments.map((sh, i) => (
                            <TypeBar key={i} sh={sh} minDate={minDate} maxDate={maxDate} onAddPo={handleAddPoLine} onAddShipment={handleAddShipmentLine} onEditEta={(poId) => setEditEtaPoId(poId)} />
                          ))}
                          {/* Popup date picker for PO ETA edit — positioned near the calendar button */}
                          {editEtaPoId && f.allShipments.some(sh => sh.po_id === editEtaPoId) && (() => {
                            const poSh = f.allShipments.find(sh => sh.po_id === editEtaPoId)!;
                            const shipTs = Math.max(new Date(poSh.ship_date).getTime(), minDate);
                            const arrTs = new Date(poSh.arrival_date).getTime();
                            const barEnd = Math.max(3, Math.min(100, ((arrTs - minDate) / (maxDate - minDate || 1)) * 100));
                            return (
                              <div className="absolute z-30" style={{ left: `${barEnd}%`, top: '100%', marginLeft: 24, marginTop: -4 }}>
                                <div className="flex items-center gap-1.5 py-1 px-2 bg-surface border border-purple-500/30 rounded-lg shadow-lg whitespace-nowrap">
                                  <input type="date" autoFocus
                                    defaultValue={poSh.arrival_date}
                                    className="bg-transparent border border-purple-500/30 rounded px-1.5 py-0.5 text-[10px] tabular-nums text-heading font-mono"
                                    onKeyDown={(e) => {
                                      if (e.key === 'Enter') {
                                        const val = (e.target as HTMLInputElement).value;
                                        if (val && editEtaPoId) handleEditEta(editEtaPoId, val);
                                      } else if (e.key === 'Escape') {
                                        setEditEtaPoId(null);
                                      }
                                    }}
                                  />
                                  <button
                                    onClick={() => {
                                      const inp = document.querySelector<HTMLInputElement>('input[type="date"]');
                                      if (inp?.value && editEtaPoId) handleEditEta(editEtaPoId, inp.value);
                                    }}
                                    className="px-2 py-0.5 text-[8px] rounded bg-purple-500/20 text-purple-400 hover:bg-purple-500/30 border border-purple-500/30 font-bold"
                                  >Save</button>
                                  <button
                                    onClick={() => setEditEtaPoId(null)}
                                    className="px-1 py-0.5 text-[8px] rounded bg-red-500/10 text-red-400 hover:bg-red-500/20 border border-red-500/20 font-bold"
                                  >✕</button>
                                </div>
                              </div>
                            );
                          })()}
                        </div>
                      </div>
                    )}

                    {/* Card 3: Weekly Stock Projection Chart */}
                    {demandMap && seasonMap && metaMap && (
                      <div className="rounded-lg border border-border/20 bg-surface/30 overflow-hidden px-4 py-3">
                        <div className="text-[9px] font-bold text-muted/60 uppercase tracking-wider mb-2">Stock Projection</div>
                        <StockProjectionChart
                          product={f.product}
                          currentStock={f.stock}
                          allShipments={f.allShipments}
                          demandMap={demandMap}
                          seasonMap={seasonMap}
                          metaMap={metaMap}
                          growthOverrides={growthOverrides}
                          timelineMinDate={minDate}
                          weeklySales={weeklySalesMap[f.product]}
                          weeklySalesLY={weeklySalesLYMap[f.product]}
                        />
                      </div>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    ))}

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
            onClick={() => setDraftPOLines([])}
            className="px-4 py-1.5 text-xs font-medium text-muted hover:text-heading hover:bg-white/5 rounded-full transition-colors"
          >
            Cancel
          </button>
          <button 
            onClick={() => setShowPOModal(true)}
            className="px-5 py-1.5 bg-purple-500 hover:bg-purple-600 text-white text-xs font-bold rounded-full shadow-lg shadow-purple-500/20 transition-all"
          >
            Create PO
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
          onAction();
        }}
      />
    )}

    {/* Create Shipment Modal */}
    {showShipmentModal && (
      <CreateShipmentModal
        draftLines={draftShipmentLines}
        defaultDate={draftShipmentDate || (draftShipmentLines.length > 0 ? new Date().toISOString().split('T')[0] : undefined)}
        defaultType={draftShipmentType}
        onClose={() => {
          setShowShipmentModal(false);
          setDraftShipmentLines([]);
          setDraftShipmentType(undefined);
          setDraftShipmentDate(undefined);
        }}
        onSuccess={() => {
          setShowShipmentModal(false);
          setDraftShipmentLines([]);
          setDraftShipmentType(undefined);
          setDraftShipmentDate(undefined);
          onAction();
        }}
      />
    )}
    </>
  );
}

// ═══════════════════════════════════════════════════════════
// WEEKLY STOCK PROJECTION CHART
// Running balance: current stock + shipment arrivals − forecasted demand
// Uses peak-day weighting for Oct–Dec to distribute demand unevenly
// ═══════════════════════════════════════════════════════════

interface ProjectionWeek {
  week: string;       // YYYY-MM-DD (Monday)
  weekLabel: string;  // Short label for x-axis
  stock: number;      // Projected stock at end of week (with suggested)
  confirmedStock: number; // Without suggested shipments
  arrivals: number;   // Units arriving this week (all sources)
  confirmedArrivals: number; // Only in-transit + approved
  demand: number;     // Weekly demand consumed
  isPeak: boolean;
  arrivalDates: string[]; // Actual arrival dates within this week
  doc: number;        // Days of Cover (confirmed stock)
  docSuggested: number; // Days of Cover (confirmed + suggested stock)
  actualSales?: number; // Actual units sold this week (past weeks only)
  actualSalesLY?: number; // Last year same-week actual sales
}

function getMonday(d: Date): Date {
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  return new Date(d.getFullYear(), d.getMonth(), diff);
}

function addDays(d: Date, n: number): Date {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}

/** Format a local Date as YYYY-MM-DD without timezone shift (unlike toISOString which converts to UTC) */
function localDateKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function fmtWeekLabel(d: Date): string {
  const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][d.getMonth()];
  return `${mo} ${d.getDate()}`;
}

function daysInMonth(year: number, month: number): number {
  return new Date(year, month + 1, 0).getDate();
}

function StockProjectionChart({ product, currentStock, allShipments, demandMap, seasonMap, metaMap, growthOverrides, timelineMinDate, weeklySales, weeklySalesLY }: {
  product: string;
  currentStock: number;
  allShipments: ShipmentItem[];
  demandMap: ForecastDemandMap;
  seasonMap: MonthSeasonMap;
  metaMap: ForecastMetaMap;
  growthOverrides?: Record<string, number>;
  timelineMinDate?: number;
  weeklySales?: Record<string, number>;
  weeklySalesLY?: Record<string, number>;
}) {
  const data = useMemo<ProjectionWeek[]>(() => {
    const now = new Date();
    // Start from the timeline's minDate to align x-axes
    const startRef = timelineMinDate ? new Date(Math.min(timelineMinDate, now.getTime())) : now;
    const startMonday = getMonday(startRef);
    const currentMonday = getMonday(now);
    const yearEnd = new Date(now.getFullYear(), 11, 31);
    // Extend timeline 13 weeks past year-end or last shipment arrival for DOC look-ahead
    const lastArrival = allShipments.reduce((max, s) => {
      const t = s.arrival_date ? new Date(s.arrival_date).getTime() : 0;
      return t > max ? t : max;
    }, 0);
    const endDate = new Date(Math.max(yearEnd.getTime(), lastArrival) + 13 * 7 * 86400000);
    const weeks: ProjectionWeek[] = [];

    // Get product's forecast data (product → yearMonth → units)
    const productDemand = demandMap[product] || {};
    const family = metaMap[product]?.family;
    const familySeason = family ? (seasonMap[family] || {}) : {};

    // Build arrival map: week_monday → { confirmed, total, dates }
    const arrivalByWeek = new Map<string, { confirmed: number; total: number; dates: Set<string> }>();
    for (const sh of allShipments) {
      if (sh.status === 'po_needed' || sh.status === 'po') continue; // PO completion = at manufacturer, not warehouse arrival
      const arrDate = sh.arrival_date ? new Date(sh.arrival_date) : null;
      if (!arrDate || isNaN(arrDate.getTime())) continue;
      const monday = getMonday(arrDate);
      const key = localDateKey(monday);
      const entry = arrivalByWeek.get(key) || { confirmed: 0, total: 0, dates: new Set<string>() };
      entry.total += sh.qty;
      if (sh.status === 'transit' || sh.status === 'approved' || sh.status === 'scheduled') {
        entry.confirmed += sh.qty;
      }
      // Track the actual arrival date for display
      const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][arrDate.getMonth()];
      entry.dates.add(`${mo} ${arrDate.getDate()}`);
      arrivalByWeek.set(key, entry);
    }

    // Calculate weekly demand per month using peak-day weighting
    // Peak days have ~2x the daily demand rate of offseason days within the same month
    // This gives us a weighted daily rate for each day type
    function weeklyDemand(weekStart: Date): { demand: number; isPeak: boolean } {
      let totalDemand = 0;
      let hasPeak = false;

      // For each day in this week (Mon-Sun), determine its month and allocate demand
      for (let d = 0; d < 7; d++) {
        const day = addDays(weekStart, d);
        if (day > endDate) break;
        const yr = day.getFullYear();
        const mo = day.getMonth(); // 0-based
        const yearMonth = yr * 100 + (mo + 1); // yyyyMM key
        const rawMonthUnits = productDemand[yearMonth] || 0;
        // Apply growth override to match the Plan page's adjusted forecast
        const growthFactor = growthOverrides?.[product] ?? 1.0;
        const monthUnits = rawMonthUnits * growthFactor;
        if (monthUnits <= 0) continue;

        const totalDaysInMo = daysInMonth(yr, mo);
        const season = familySeason[yearMonth];
        const peakDays = season?.peakDays ?? 0;
        const offDays = season?.offseasonDays ?? (totalDaysInMo - peakDays);

        if (peakDays > 0 && offDays > 0) {
          // Weight: peak days get 2x demand rate vs offseason days
          // totalUnits = peakDays * rate * 2 + offDays * rate
          // rate = totalUnits / (peakDays * 2 + offDays)
          const rate = monthUnits / (peakDays * 2 + offDays);
          // Is this specific day a peak day? (Oct-Dec holiday periods)
          // Simple heuristic: last N days of month = peak_days (holiday rush tends toward month end)
          const dayOfMonth = day.getDate();
          const isPeakDay = dayOfMonth > (totalDaysInMo - peakDays);
          totalDemand += isPeakDay ? rate * 2 : rate;
          if (isPeakDay) hasPeak = true;
        } else {
          // Even distribution
          totalDemand += monthUnits / totalDaysInMo;
        }
      }

      return { demand: Math.round(totalDemand), isPeak: hasPeak };
    }

    // Build weekly projection
    let runningConfirmed = currentStock;
    let runningTotal = currentStock;
    let weekStart = new Date(startMonday);

    // Pass 1: Build weekly stock levels (DOC placeholder = 0)
    while (weekStart <= endDate) {
      const key = localDateKey(weekStart);
      const isPast = weekStart < currentMonday;
      const { demand: rawDemand, isPeak } = weeklyDemand(weekStart);
      const demand = isPast ? 0 : rawDemand;
      const arrival = arrivalByWeek.get(key) || { confirmed: 0, total: 0, dates: new Set<string>() };
      const adjArrivalConf = isPast ? 0 : arrival.confirmed;
      const adjArrivalTotal = isPast ? 0 : arrival.total;

      runningConfirmed = runningConfirmed - demand + adjArrivalConf;
      runningTotal = runningTotal - demand + adjArrivalTotal;

      weeks.push({
        week: key,
        weekLabel: fmtWeekLabel(weekStart),
        stock: Math.max(0, Math.round(runningTotal)),
        confirmedStock: Math.max(0, Math.round(runningConfirmed)),
        arrivals: isPast ? 0 : arrival.total,
        confirmedArrivals: isPast ? 0 : arrival.confirmed,
        demand,
        isPeak,
        arrivalDates: isPast ? [] : [...arrival.dates],
        doc: 0,
        docSuggested: 0,
        actualSales: weeklySales?.[key],
        actualSalesLY: weeklySalesLY?.[key],
      });

      weekStart = addDays(weekStart, 7);
    }

    // Pass 2: Forward-looking DOC — simulate forward from each week
    // counting days until stock runs out using future varying demand
    for (let i = 0; i < weeks.length; i++) {
      const w = weeks[i];
      // DOC for confirmed stock
      let remConf = Math.max(0, w.confirmedStock);
      let daysConf = 0;
      for (let j = i; j < weeks.length && remConf > 0; j++) {
        const futDemand = weeks[j].demand;
        if (futDemand <= 0) { daysConf += 7; continue; }
        const dailyD = futDemand / 7;
        const daysThisWeek = Math.min(7, remConf / dailyD);
        daysConf += daysThisWeek;
        remConf -= futDemand;
      }
      w.doc = Math.min(Math.round(daysConf), 365);

      // DOC for suggested stock
      let remSugg = Math.max(0, w.stock);
      let daysSugg = 0;
      for (let j = i; j < weeks.length && remSugg > 0; j++) {
        const futDemand = weeks[j].demand;
        if (futDemand <= 0) { daysSugg += 7; continue; }
        const dailyD = futDemand / 7;
        const daysThisWeek = Math.min(7, remSugg / dailyD);
        daysSugg += daysThisWeek;
        remSugg -= futDemand;
      }
      w.docSuggested = Math.min(Math.round(daysSugg), 365);
    }

    return weeks;
  }, [product, currentStock, allShipments, demandMap, seasonMap, metaMap, growthOverrides, timelineMinDate, weeklySales, weeklySalesLY]);

  const [showConfirmed, setShowConfirmed] = useState(true);
  const [showSuggested, setShowSuggested] = useState(true);
  const [showDocConf, setShowDocConf] = useState(true);
  const [showDocSugg, setShowDocSugg] = useState(false);
  const [showActualSales, setShowActualSales] = useState(false);
  const [showDemand, setShowDemand] = useState(false);
  const [showSalesLY, setShowSalesLY] = useState(false);
  const [showArrivals, setShowArrivals] = useState(true);

  if (!data.length) return null;

  // Find first OOS week (confirmed path)
  const oosWeek = data.find(w => w.confirmedStock <= 0);

  // Custom tooltip
  const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ value: number; dataKey: string }>; label?: string }) => {
    if (!active || !payload?.length) return null;
    const row = data.find(w => w.weekLabel === label);
    if (!row) return null;
    return (
      <div className="bg-surface border border-border rounded-lg p-2.5 text-[11px] space-y-1 shadow-lg" style={{ background: 'var(--color-card)', border: '1px solid var(--color-border-strong)' }}>
        <div className="font-bold text-heading">{row.weekLabel}</div>
        {showConfirmed && <div style={{ color: '#06b6d4' }}>Confirmed: {fmt(row.confirmedStock)} units</div>}
        {showSuggested && <div style={{ color: '#8b5cf6' }}>+ Suggested: {fmt(row.stock)} units</div>}
        {showDocConf && <div style={{ color: '#f59e0b' }}>DOC Confirmed: {row.doc < 365 ? `${row.doc}d` : '365d+'}</div>}
        {showDocSugg && <div style={{ color: '#fb923c' }}>DOC +Suggested: {row.docSuggested < 365 ? `${row.docSuggested}d` : '365d+'}</div>}
        {row.arrivals > 0 && <div style={{ color: '#22c55e' }}>📦 Arrivals: +{fmt(row.arrivals)}{row.arrivalDates.length > 0 && <span className="text-muted ml-1">({row.arrivalDates.join(', ')})</span>}</div>}
        <div style={{ color: '#f87171' }}>Demand: −{fmt(row.demand)}/wk</div>
        {row.actualSales != null && <div style={{ color: '#60a5fa' }}>Actual sold: {fmt(row.actualSales)}/wk</div>}
        {row.actualSalesLY != null && <div style={{ color: '#a78bfa' }}>LY sold: {fmt(row.actualSalesLY)}/wk</div>}
        {row.isPeak && <div style={{ color: '#f59e0b' }}>🔥 Peak season</div>}
      </div>
    );
  };

  // Legend toggle button helper
  const LegendBtn = ({ active, color, label, sub, onClick }: { active: boolean; color: string; label: string; sub?: string; onClick: () => void }) => (
    <button onClick={onClick}
      className="inline-flex items-center gap-1 transition-opacity cursor-pointer"
      style={{ opacity: active ? 1 : 0.35 }}
      title={active ? `Click to hide ${label}` : `Click to show ${label}`}>
      <span className="w-2 h-2 rounded-sm" style={{ background: color }} />
      <span>{label}</span>
      {sub && <span className="text-[7px] text-muted/50">{sub}</span>}
    </button>
  );

  return (
    <div className="mt-3">
      <div className="flex items-center justify-between mb-2">
        <h4 className="text-[11px] font-bold text-heading/80">Weekly Stock Projection</h4>
        <div className="flex items-center gap-3 text-[9px] text-muted">
          <LegendBtn active={showConfirmed} color="#06b6d4" label="Confirmed" onClick={() => setShowConfirmed(v => !v)} />
          <LegendBtn active={showSuggested} color="#8b5cf6" label="+Suggested" onClick={() => setShowSuggested(v => !v)} />
          <span className="text-muted/30">|</span>
          <LegendBtn active={showDocConf} color="#f59e0b" label="DOC" sub="(confirmed)" onClick={() => setShowDocConf(v => !v)} />
          <LegendBtn active={showDocSugg} color="#fb923c" label="DOC" sub="(+suggested)" onClick={() => setShowDocSugg(v => !v)} />
          <span className="text-muted/30">|</span>
          <LegendBtn active={showActualSales} color="#60a5fa" label="Actual Sales" onClick={() => setShowActualSales(v => !v)} />
          <LegendBtn active={showDemand} color="#f87171" label="Demand" onClick={() => setShowDemand(v => !v)} />
          <LegendBtn active={showSalesLY} color="#a78bfa" label="LY Sales" onClick={() => setShowSalesLY(v => !v)} />
          <span className="text-muted/30">|</span>
          <LegendBtn active={showArrivals} color="#22c55e" label="Arrivals" onClick={() => setShowArrivals(v => !v)} />
          {oosWeek && <span className="text-red-400 font-bold">⚠ OOS: {oosWeek.weekLabel}</span>}
        </div>
      </div>
      <ResponsiveContainer width="100%" height={180}>
        <ComposedChart data={data} margin={{ top: 5, right: 5, left: 5, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#334155" strokeOpacity={0.3} />
          <XAxis
            dataKey="weekLabel"
            tick={{ fontSize: 9, fill: '#64748b' }}
            tickLine={false}
            axisLine={{ stroke: '#334155' }}
            interval="preserveStartEnd"
          />
          <YAxis yAxisId="left" hide domain={[0, 'auto']} />
          <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 9, fill: '#f59e0b' }} tickLine={false} axisLine={false} domain={[0, 'auto']} tickFormatter={(v) => `${v}d`} width={30} />
          <RTooltip content={<CustomTooltip />} cursor={{ fill: 'rgba(255,255,255,0.03)' }} />
          <ReferenceLine yAxisId="left" y={0} stroke="#ef4444" strokeWidth={1.5} strokeDasharray="4 4" label={{ value: 'OOS', position: 'right', fill: '#ef4444', fontSize: 9 }} />
          <ReferenceLine yAxisId="right" y={100} ifOverflow="extendDomain" stroke="#ef4444" strokeWidth={1.5} strokeDasharray="4 4" label={{ value: '100d DOC', position: 'insideTopLeft', fill: '#ef4444', fontSize: 9, offset: 5 }} />

          {/* Suggested (optimistic) path */}
          {showSuggested && (
            <Bar yAxisId="left" dataKey="stock" name="+ Suggested" barSize={8} radius={[2, 2, 0, 0]} opacity={0.25}>
              {data.map((w, i) => (
                <Cell key={i} fill={w.stock > 0 ? '#8b5cf6' : '#ef4444'} />
              ))}
            </Bar>
          )}

          {/* Confirmed path — solid line */}
          {showConfirmed && (
            <Line
              yAxisId="left"
              dataKey="confirmedStock"
              name="Confirmed Stock"
              type="stepAfter"
              stroke="#06b6d4"
              strokeWidth={2}
              dot={false}
              activeDot={{ r: 3, fill: '#06b6d4' }}
            />
          )}

          {/* DOC confirmed — dashed amber on right axis */}
          {showDocConf && (
            <Line
              yAxisId="right"
              dataKey="doc"
              name="DOC Confirmed"
              type="stepAfter"
              stroke="#f59e0b"
              strokeWidth={1.5}
              strokeDasharray="4 2"
              dot={false}
              activeDot={{ r: 3, fill: '#f59e0b' }}
            />
          )}

          {/* DOC +suggested — dashed orange on right axis */}
          {showDocSugg && (
            <Line
              yAxisId="right"
              dataKey="docSuggested"
              name="DOC +Suggested"
              type="stepAfter"
              stroke="#fb923c"
              strokeWidth={1.5}
              strokeDasharray="6 3"
              dot={false}
              activeDot={{ r: 3, fill: '#fb923c' }}
            />
          )}

          {/* Actual sales — blue bars, hidden by default */}
          {showActualSales && (
            <Bar yAxisId="left" dataKey="actualSales" name="Actual Sales" barSize={5} radius={[2, 2, 0, 0]} fill="#60a5fa" opacity={0.6} />
          )}

          {/* Demand forecast — red dashed line, hidden by default */}
          {showDemand && (
            <Line
              yAxisId="left"
              dataKey="demand"
              name="Demand"
              type="stepAfter"
              stroke="#f87171"
              strokeWidth={1.5}
              strokeDasharray="4 3"
              dot={false}
              activeDot={{ r: 3, fill: '#f87171' }}
            />
          )}

          {/* Last year sales — dotted purple line, hidden by default */}
          {showSalesLY && (
            <Line
              yAxisId="left"
              dataKey="actualSalesLY"
              name="LY Sales"
              type="monotone"
              stroke="#a78bfa"
              strokeWidth={2}
              strokeDasharray="4 3"
              dot={{ r: 2, fill: '#a78bfa', strokeWidth: 0 }}
              activeDot={{ r: 4, fill: '#a78bfa' }}
              connectNulls
            />
          )}

          {/* Arrival markers */}
          {showArrivals && data.some(w => w.arrivals > 0) && (
            <Line
              yAxisId="left"
              dataKey="arrivals"
              name="Arrivals"
              type="monotone"
              stroke="transparent"
              dot={(props: { cx?: number; cy?: number; payload?: ProjectionWeek }) => {
                if (!props.payload?.arrivals) return <g />;
                const dateLabel = props.payload.arrivalDates.length > 0 ? props.payload.arrivalDates[0] : '';
                return (
                  <g>
                    <circle cx={props.cx} cy={props.cy} r={4} fill="#22c55e" stroke="#0f172a" strokeWidth={1.5} />
                    <text x={props.cx} y={(props.cy ?? 0) - 14} textAnchor="middle" fill="#22c55e" fontSize={8} fontWeight={700}>
                      +{fmt(props.payload.arrivals)}
                    </text>
                    {dateLabel && (
                      <text x={props.cx} y={(props.cy ?? 0) - 5} textAnchor="middle" fill="#94a3b8" fontSize={7}>
                        {dateLabel}
                      </text>
                    )}
                  </g>
                );
              }}
            />
          )}
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}

/** Mini inline pill for collapsed product row — wider with brighter text */
function MiniPill({ label, qty, color, outlined, title }: { label: string; qty: number; color: string; outlined?: boolean; title?: string }) {
  return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[9px] font-bold mx-0.5 tabular-nums"
      title={title}
      style={{
        background: outlined ? 'transparent' : color + '20',
        color: 'var(--color-text)',
        border: outlined ? `1.5px dashed ${color}60` : `1px solid ${color}30`,
      }}>
      <span style={{ color, fontSize: 8, fontWeight: 700 }}>{label}</span> {fmt(qty)}
    </span>
  );
}


// ═══════════════════════════════════════════════════════════
// SHIPMENT PLAN SECTION — Compact one-line-per-product table
// ═══════════════════════════════════════════════════════════

interface ShipmentGroup {
  key: string;
  type_name: string;
  ship_wednesday: string;
  rows: UnifiedShipmentRow[];
  totalQty: number;
  approvedCount: number;
  scheduledCount: number;
  suggestedCount: number;
}

import type { ActivePORow } from '../pages/PlanPage';

export function ShipmentCardSection({ suggestions, scheduled, activePOs, productMeta, inTransitShipments = [], stockMap = {}, mfrReadyMap = {}, mfrInProdMap = {}, yearlyPlanMap = {}, salesSummary = [], onAction, onUpdateEtaOptimistic }: {
  suggestions: ShipmentPlanFactRow[];
  scheduled: ScheduledShipmentRow[];
  activePOs?: ActivePORow[];
  productMeta?: any[];
  inTransitShipments?: { product: string; type: string; qty: number; eta: string; ship_date: string; asin?: string; }[];
  stockMap?: Record<string, number>;
  mfrReadyMap?: Record<string, number>;
  mfrInProdMap?: Record<string, number>;
  yearlyPlanMap?: Record<string, number>;
  salesSummary?: { asin: string; product_name: string; sold: number }[];
  onAction: () => void;
  onUpdateEtaOptimistic?: (poId: string, date: string) => void;
}) {
  const [expanded, setExpanded] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [editQty, setEditQty] = useState<Record<string, number>>({});
  const [planFilter, setPlanFilter] = useState<'open' | 'done' | 'all'>('open');
  const [editEtaPoId, setEditEtaPoId] = useState<string | null>(null);

  const [draftPOLines, setDraftPOLines] = useState<DraftPOLine[]>([]);
  const [showPOModal, setShowPOModal] = useState(false);

  const [draftShipmentLines, setDraftShipmentLines] = useState<DraftShipmentLine[]>([]);
  const [showShipmentModal, setShowShipmentModal] = useState<GanttGroupItem | false>(false);

  // De-duplicate: remove suggestions that already have a matching scheduled/approved row
  const dedupedSuggestions = useMemo(() => {
    const scheduledKeys = new Set(scheduled.map(s => `${s.product}__${s.shipment_type}__${s.ship_wednesday}`));
    return suggestions.filter(s => !scheduledKeys.has(`${s.product}__${s.shipment_type}__${s.ship_wednesday}`));
  }, [suggestions, scheduled]);

  const groups: ShipmentGroup[] = useMemo(() => {
    const all: UnifiedShipmentRow[] = [
      ...dedupedSuggestions.map(s => ({
        product: s.product, asin: s.asin, shipment_type: s.shipment_type,
        shipment_type_name: s.shipment_type_name, route: s.route, transit_type: s.transit_type,
        ship_qty: s.ship_qty, ship_cartons: s.ship_cartons, ship_wednesday: s.ship_wednesday, arrival_date: s.arrival_date,
        shipment_num: s.shipment_num,
        shipment_trigger_reason: s.shipment_trigger_reason, ship_qty_reason: s.ship_qty_reason,
        _status: 'suggested' as const,
      })),
      ...scheduled.map(s => ({
        product: s.product, asin: s.asin, shipment_type: s.shipment_type,
        shipment_type_name: s.shipment_type_name, route: s.route, transit_type: s.transit_type,
        ship_qty: s.ship_qty, ship_cartons: s.ship_cartons, ship_wednesday: s.ship_wednesday, arrival_date: s.arrival_date,
        shipment_num: s.shipment_num,
        shipment_trigger_reason: s.shipment_trigger_reason, ship_qty_reason: s.ship_qty_reason,
        _status: s.status === 'SCHEDULED' ? 'scheduled' as const : 'approved' as const,
        _schedule_id: s.schedule_id,
      })),
      ...(activePOs || []).map(po => {
        const pMeta = productMeta?.find(p => p.asin === po.asin);
        const canonicalProduct = pMeta ? (pMeta.product_short_name || pMeta.product) : po.product;
        const mfrDay = pMeta?.manufacture_day ?? 30;
        const od = new Date(po.order_date);
        const computedArrival = new Date(od.getTime() + mfrDay * 86400000).toISOString().split('T')[0];
        const arrival = po.estimated_arrival_date || computedArrival;
        return {
          product: canonicalProduct, asin: po.asin, shipment_type: 0,
          shipment_type_name: 'Purchase Order', route: 'MFR', transit_type: 'MFR',
          ship_qty: po.qty, ship_cartons: 0, ship_wednesday: po.order_date, arrival_date: arrival,
          shipment_num: null,
          shipment_trigger_reason: 'Active Purchase Order', ship_qty_reason: 'Ordered qty',
          _status: 'po' as const,
          _po_id: po.po_id,
          _has_manual_eta: !!po.estimated_arrival_date,
        };
      }),
      ...(inTransitShipments || []).map(t => {
        const asin = t.asin || productMeta?.find(p => p.product_short_name === t.product || p.product === t.product)?.asin || '';
        return {
          product: t.product, asin, shipment_type: 0,
          shipment_type_name: t.type || 'Standard Ship', route: '', transit_type: 'Transit',
          ship_qty: t.qty, ship_cartons: 0, ship_wednesday: t.ship_date, arrival_date: t.eta,
          shipment_num: null,
          shipment_trigger_reason: 'In Transit', ship_qty_reason: 'Actual qty',
          _status: 'transit' as const,
        };
      }),
      ...((productMeta || []).map(p => {
        const product = p.product_short_name || p.product;
        const plan = yearlyPlanMap[product] || 0;
        const salesRow = salesSummary.find(s => s.product_name === product || s.asin === p.asin);
        const ytdSold = salesRow?.sold ?? 0;
        const remaining = Math.max(0, plan - ytdSold);
        
        const stockQty = stockMap[product] || 0;
        const transitQty = (inTransitShipments || []).filter(s => s.product === product).reduce((s, r) => s + r.qty, 0);
        const mfrReady = mfrReadyMap[product] || 0;
        const mfrInProd = mfrInProdMap[product] || 0;

        const stockRem = remaining - stockQty;
        const transitRem = stockRem - transitQty;
        const mfrReadyRem = transitRem - mfrReady;
        const mfrInProdRem = mfrReadyRem - mfrInProd;
        const poGap = Math.max(0, mfrInProdRem);

        if (poGap > 1) { // small buffer for rounding
          const today = new Date();
          const orderByDate = today.toISOString().split('T')[0];
          const mfrDays = product.toLowerCase().includes('lolli') && !product.toLowerCase().includes('me') ? 42 : 30;
          const readyDate = new Date(today.getTime() + mfrDays * 86400000).toISOString().split('T')[0];
          return {
            product, asin: p.asin, shipment_type: 0,
            shipment_type_name: 'PO_NEEDED', route: 'MFR', transit_type: 'MFR',
            ship_qty: poGap, ship_cartons: 0, ship_wednesday: orderByDate, arrival_date: readyDate,
            shipment_num: null,
            shipment_trigger_reason: 'Inventory Gap', ship_qty_reason: 'Waterfall logic',
            _status: 'po_needed' as const,
          };
        }
        return null;
      }).filter(Boolean) as UnifiedShipmentRow[])
    ];

    const map = new Map<string, UnifiedShipmentRow[]>();
    for (const r of all) {
      const key = `${r.shipment_type_name}__${r.ship_wednesday}`;
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(r);
    }

    return [...map.entries()].map(([key, rows]) => ({
      key, type_name: rows[0].shipment_type_name, ship_wednesday: rows[0].ship_wednesday,
      rows: rows.sort((a, b) => a.product.localeCompare(b.product)),
      totalQty: rows.reduce((s, r) => s + r.ship_qty, 0),
      approvedCount: rows.filter(r => r._status === 'approved').length,
      scheduledCount: rows.filter(r => r._status === 'scheduled').length,
      suggestedCount: rows.filter(r => r._status === 'suggested').length,
      poCount: rows.filter(r => r._status === 'po').length,
      transitCount: rows.filter(r => r._status === 'transit').length,
      poNeededCount: rows.filter(r => r._status === 'po_needed').length,
    })).sort((a, b) => {
      const typeOrder: Record<string, number> = { EMERGENCY: 1, EMERGENCY_PO: 2, 'EMERGENCY (NEW PO NEEDED)': 2, AWD_MAINTENANCE: 3, Q4_BULK: 4, PO_NEEDED: 5 };
      return (typeOrder[a.type_name] ?? 99) - (typeOrder[b.type_name] ?? 99) || a.ship_wednesday.localeCompare(b.ship_wednesday);
    });
  }, [dedupedSuggestions, scheduled, activePOs, inTransitShipments, stockMap, mfrReadyMap, mfrInProdMap, yearlyPlanMap, salesSummary]);

  const filteredGroups = useMemo(() => {
    return groups.filter(g => {
      const arrDates = g.rows.map(r => r.arrival_date).sort();
      const latestArrivalStr = arrDates[arrDates.length - 1];
      const latestArrival = latestArrivalStr ? new Date(latestArrivalStr).getTime() : 0;
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const isDone = latestArrival > 0 && latestArrival < today.getTime();
      
      if (planFilter === 'open') return !isDone;
      if (planFilter === 'done') return isDone;
      return true;
    });
  }, [groups, planFilter]);

  const handleApprove = useCallback(async (row: UnifiedShipmentRow, currentQty?: number) => {
    const k = row.product + row.ship_wednesday;
    setBusy(k);
    try {
      const orig = dedupedSuggestions.find(s => s.product === row.product && s.shipment_type === row.shipment_type && s.ship_wednesday === row.ship_wednesday);
      if (orig && orig.schedule_id) {
        const res = await approveShipment(orig.schedule_id, currentQty, true);
        if (res.job_id) {
          // Toast or UI indication can be handled elsewhere, but recalculation is running.
        }
      }
      onAction();
    } catch (e) { console.error(e); }
    setBusy(null);
  }, [dedupedSuggestions, onAction]);

  const handleApproveAll = useCallback(async (group: ShipmentGroup) => {
    setBusy(group.key);
    try {
      for (const row of group.rows) {
        if (row._status !== 'suggested') continue;
        const orig = dedupedSuggestions.find(s => s.product === row.product && s.shipment_type === row.shipment_type && s.ship_wednesday === row.ship_wednesday);
        if (orig && orig.schedule_id) await approveShipment(orig.schedule_id, undefined, true);
      }
      onAction();
    } catch (e) { console.error(e); }
    setBusy(null);
  }, [dedupedSuggestions, onAction]);

  const handleSchedule = useCallback(async (id: string) => { setBusy(id); try { await scheduleShipment(id); onAction(); } catch (e) { console.error(e); } setBusy(null); }, [onAction]);
  const handleRevert = useCallback(async (id: string) => { setBusy(id); try { await revertShipment(id); onAction(); } catch (e) { console.error(e); } setBusy(null); }, [onAction]);
  const handleUnschedule = useCallback(async (id: string) => { setBusy(id); try { await unscheduleShipment(id); onAction(); } catch (e) { console.error(e); } setBusy(null); }, [onAction]);
  const handleQtyUpdate = useCallback(async (id: string, qty: number) => { setBusy(id); try { await updateQty(id, qty); onAction(); } catch (e) { console.error(e); } setBusy(null); }, [onAction]);
  const handleUpdateEta = useCallback(async (poId: string, date: string) => {
    setBusy(poId);
    if (onUpdateEtaOptimistic) onUpdateEtaOptimistic(poId, date);
    try {
      await updatePoEta(poId, date);
      setEditEtaPoId(null);
      onAction();
    } catch (e) { console.error(e); }
    setBusy(null);
  }, [onAction, onUpdateEtaOptimistic]);

  if (filteredGroups.length === 0 && groups.length === 0) return (
    <Section title="Shipment Plan">
      <div className="text-center text-muted text-sm py-8">No shipment suggestions available. Run the SP or check data.</div>
    </Section>
  );

  // ─── Excel Export ─────────────────────────────────────
  const handleExport = useCallback(() => {
    try {
      // Filter to approved shipments only and sort by date
      const exportGroups = groups.map(g => {
        const rows = g.rows.filter(r => r._status === 'approved');
        if (rows.length === 0) return null;
        return {
          ...g,
          rows,
          totalQty: rows.reduce((s, r) => s + r.ship_qty, 0),
          totalCartons: rows.reduce((s, r) => s + (r.ship_cartons || 0), 0)
        };
      }).filter(Boolean) as any[];

      if (exportGroups.length === 0) {
        alert("No approved shipments to export.");
        return;
      }

      // Order by shipment date
      exportGroups.sort((a, b) => a.ship_wednesday.localeCompare(b.ship_wednesday));

      // Build mapping for product -> family for hierarchy in headers
      const productToFamily = new Map<string, string>();
      for (const p of productMeta || []) {
        const name = p.product_short_name || p.product;
        if (name) productToFamily.set(name, p.family_name || 'Other');
      }

      const sortedProducts = [...new Set(exportGroups.flatMap(g => g.rows.map(r => r.product)))]
        .sort((a, b) => {
          const famA = productToFamily.get(a) || 'Other';
          const famB = productToFamily.get(b) || 'Other';
          return famA.localeCompare(famB) || a.localeCompare(b);
        });

      const productLabels = sortedProducts.map(p => {
        const fam = productToFamily.get(p) || 'Other';
        return { product: p, label: `[${fam}] ${p}` };
      });

      const TRANSIT_CAPTION_MAP: Record<string, string> = {
        'AIR': 'Air',
        'AWD_SLOW_SEA': 'AWD Slow Sea 60 Days',
        'FAST_SEA': 'Fast Sea',
        'SLOW_SEA': 'Slow Sea',
        'AWD_TRANSFER': 'AWD → FBA Transfer'
      };

      // Extract metadata per shipment group
      const shipmentMeta = exportGroups.map(g => {
        const shipDates = g.rows.map(r => r.ship_wednesday).sort();
        const arrDates = g.rows.map(r => r.arrival_date).sort();
        const route = g.rows[0]?.route || '';
        const destination = route.includes('AWD') ? 'AWD' : 'FBA';
        const transitId = g.rows[0]?.transit_type || '';
        const transitCaption = TRANSIT_CAPTION_MAP[transitId] || transitId;
        return {
          type: (g.type_name || '').replace(/_/g, ' '),
          shipDate: shipDates[0],
          arrDate: arrDates[arrDates.length - 1],
          destination,
          transit: transitCaption,
          totalProducts: g.rows.length,
          totalQty: g.totalQty,
          totalCartons: g.rows.reduce((s: number, r: any) => s + (r.ship_cartons || 0), 0),
          rows: g.rows,
        };
      });

      // ── Build transposed sheet (rows = labels, columns = shipments) ──
      const metaFields = [
        'Shipment Date', 'Destination', 'Transit', 'Total Products',
      ];

      // Format date as YYYY_MMM_DD (e.g. 2026_May_06)
      const formatDate = (dateStr: string) => {
        if (!dateStr) return '';
        const d = new Date(dateStr + 'T00:00:00');
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        const yyyy = d.getFullYear();
        const mmm = months[d.getMonth()];
        const dd = String(d.getDate()).padStart(2, '0');
        return `${yyyy}_${mmm}_${dd}`;
      };

      const buildTransposedSheet = (mode: 'units' | 'cartons') => {
        const totalLabel = mode === 'units' ? 'Total Units' : 'Total Cartons';
        const headerLabels = [...metaFields, totalLabel, ...productLabels.map(pl => pl.label)];
        const totalRows = headerLabels.length;
        const totalCols = 1 + shipmentMeta.length; // label col + one per shipment

        // Create empty worksheet
        const ws: XLSX.WorkSheet = {};
        ws['!ref'] = XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: totalRows - 1, c: totalCols - 1 } });

        // Define common thin border to restore gridlines
        const borderStyle = {
          top: { style: 'thin', color: { rgb: 'D4D4D4' } },
          bottom: { style: 'thin', color: { rgb: 'D4D4D4' } },
          left: { style: 'thin', color: { rgb: 'D4D4D4' } },
          right: { style: 'thin', color: { rgb: 'D4D4D4' } },
        };

        // Column A: labels
        headerLabels.forEach((label, r) => {
          const cellRef = XLSX.utils.encode_cell({ r, c: 0 });
          const isBoldRow = r <= metaFields.length; // meta rows + total row
          const isDateRow = r === 0;
          ws[cellRef] = {
            v: label, t: 's',
            s: {
              border: borderStyle,
              font: {
                bold: isBoldRow,
                ...(isDateRow ? { sz: 16 } : {}),
              },
            },
          };
        });

        // Fill shipment columns (B, C, D, ...)
        shipmentMeta.forEach((sm, colIdx) => {
          const c = colIdx + 1; // offset by label column
          const bgFill = colIdx % 2 === 0 ? 'FFFFFF' : 'F1F5F9'; // Zebra striping (Slate 100)
          const baseStyle = { fill: { fgColor: { rgb: bgFill } }, border: borderStyle };

          const metaValues: { val: string | number; style?: any }[] = [
            { // Row 0: Shipment Date — font 16, bold, YYYY_MMM_DD
              val: formatDate(sm.shipDate),
              style: { ...baseStyle, font: { bold: true, sz: 16 } },
            },
            { val: sm.destination, style: { ...baseStyle, font: { bold: true } } },   // Row 1: Destination
            { val: sm.transit, style: { ...baseStyle, font: { bold: true } } },       // Row 2: Transit
            { val: sm.totalProducts, style: baseStyle },                              // Row 3: Total Products
            { val: mode === 'units' ? sm.totalQty : sm.totalCartons, style: baseStyle }, // Row 4: Total Units/Cartons
          ];

          // Metadata rows
          metaValues.forEach(({ val, style }, r) => {
            const cellRef = XLSX.utils.encode_cell({ r, c });
            ws[cellRef] = {
              v: val,
              t: typeof val === 'number' ? 'n' : 's',
              s: style || baseStyle,
            };
          });

          // Product rows
          productLabels.forEach((pl, pIdx) => {
            const r = metaFields.length + 1 + pIdx; // after meta + total row
            const match = sm.rows.find((row: any) => row.product === pl.product);
            const val = mode === 'units'
              ? (match ? match.ship_qty : '')
              : (match && match.ship_cartons ? match.ship_cartons : '');
            const cellRef = XLSX.utils.encode_cell({ r, c });
            // Always write cell to maintain zebra background color and borders
            ws[cellRef] = { 
              v: val, 
              t: typeof val === 'number' && val !== '' ? 'n' : 's',
              s: baseStyle
            };
          });
        });

        // Column widths: label col wide, shipment cols narrower
        ws['!cols'] = [
          { wch: 30 }, // labels column
          ...shipmentMeta.map(() => ({ wch: 16 })),
        ];

        // Row heights: date row taller for font 16
        ws['!rows'] = [{ hpt: 24 }];

        return ws;
      };

      const wsUnits = buildTransposedSheet('units');
      const wsCartons = buildTransposedSheet('cartons');

      const wb = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(wb, wsUnits, 'Units');
      XLSX.utils.book_append_sheet(wb, wsCartons, 'Cartons');
      const today = new Date().toISOString().split('T')[0];
      XLSX.writeFile(wb, `Shipment_Plan_${today}.xlsx`);
    } catch (err: any) {
      console.error("Export to Excel failed:", err);
      alert("Failed to export: " + (err.message || String(err)));
    }
  }, [groups, productMeta]);

  // Build aggregated Gantt items (one per group, not per product)
  interface GanttGroupItem {
    key: string; type: string; icon: string;
    ship_date: string; arrival_date: string;
    route: string; transit_type: string;
    totalQty: number; productCount: number;
    products: { name: string; qty: number; status: string; asin: string; po_id?: string; arrival_date?: string; }[];
    hasAllApproved: boolean; hasAllScheduled: boolean;
    po_id?: string;
    po_ids: string[]; // All unique PO IDs in this group
  }
  const ganttGroups: GanttGroupItem[] = useMemo(() => {
    return filteredGroups.map(g => {
      // Earliest ship, latest arrival across rows
      const shipDates = g.rows.map(r => r.ship_wednesday).sort();
      const arrDates = g.rows.map(r => r.arrival_date).sort();
      const poIds = [...new Set(g.rows.filter(r => r._po_id).map(r => r._po_id!))];
      return {
        key: g.key, type: g.type_name,
        icon: TYPE_ICONS[g.type_name] || '📦',
        ship_date: shipDates[0],
        arrival_date: arrDates[arrDates.length - 1],
        route: g.rows[0]?.route || '',
        transit_type: g.rows[0]?.transit_type || '',
        totalQty: g.totalQty, productCount: g.rows.length,
        products: g.rows.map(r => ({ name: r.product, qty: r.ship_qty, status: r._status, asin: r.asin, po_id: r._po_id, arrival_date: r.arrival_date })),
        hasAllApproved: g.rows.every(r => r._status === 'approved'),
        hasAllScheduled: g.rows.every(r => r._status === 'scheduled'),
        po_id: g.rows.find(r => r._po_id)?._po_id,
        po_ids: poIds,
      };
    }).sort((a, b) => a.ship_date.localeCompare(b.ship_date));
  }, [filteredGroups]);

  // Gantt timeline range (same as replenishment)
  const ganttRange = useMemo(() => {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const startOfYear = new Date(today.getFullYear(), 0, 1);
    const endOfMarch = new Date(today.getFullYear() + 1, 2, 31);
    return { minDate: startOfYear.getTime(), maxDate: endOfMarch.getTime() };
  }, [ganttGroups]);

  // Hover state for Gantt tooltips
  const [ganttHover, setGanttHover] = useState<string | null>(null);

  const handleAddPoGroup = useCallback((g: GanttGroupItem) => {
    setDraftPOLines(g.products.map(p => ({ product: p.name, asin: p.asin, qty: p.qty })));
    setShowPOModal(true);
  }, []);

  const handleAddShipmentGroup = useCallback((g: GanttGroupItem) => {
    setDraftShipmentLines(g.products.map(p => ({ product: p.name, asin: p.asin, qty: p.qty })));
    setShowShipmentModal(g);
  }, []);

  return (
    <>
    <Section title="Shipment Plan" headerRight={
      <div className="flex items-center gap-3">
        <div className="flex bg-surface/50 p-0.5 rounded-lg border border-border/30 text-[10px] font-medium">
          <button 
            onClick={() => setPlanFilter('all')}
            className={`px-3 py-1 rounded-md transition-colors ${planFilter === 'all' ? 'bg-surface text-text shadow-sm border border-border/50' : 'text-muted hover:text-text'}`}>
            All
          </button>
          <button 
            onClick={() => setPlanFilter('open')}
            className={`px-3 py-1 rounded-md transition-colors ${planFilter === 'open' ? 'bg-surface text-text shadow-sm border border-border/50' : 'text-muted hover:text-text'}`}>
            Open
          </button>
          <button 
            onClick={() => setPlanFilter('done')}
            className={`px-3 py-1 rounded-md transition-colors ${planFilter === 'done' ? 'bg-surface text-text shadow-sm border border-border/50' : 'text-muted hover:text-text'}`}>
            Done
          </button>
        </div>
        <button onClick={handleExport}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-[10px] rounded-lg bg-blue-500/10 text-blue-400 hover:bg-blue-500/20 border border-blue-500/30 font-bold transition-colors">
          <Download size={12} /> Export to Excel
        </button>
      </div>
    }>
      <div>

      {/* ─── Full Gantt Timeline — aggregated by shipment group ─── */}
      {ganttGroups.length > 0 && (
        <div className="rounded-lg border border-border/20 bg-surface/30 px-4 py-3 mb-3">
          <div className="text-[9px] font-bold text-muted/60 uppercase tracking-wider mb-2">Shipment Plan Timeline</div>
          <TypeLegend types={ganttGroups.map(g => g.type)} />
          {/* Timeline axis */}
          <div className="flex justify-between text-[8px] text-muted/40 mt-2 mb-1 px-0.5">
            <span>{fmtDate(new Date(ganttRange.minDate).toISOString().split('T')[0])}</span>
            <span>{fmtDate(new Date(ganttRange.maxDate).toISOString().split('T')[0])}</span>
          </div>
          {/* Aggregated bars — one per shipment group */}
          <div className="space-y-1 relative">
            {(() => {
              const nowTs = new Date().getTime();
              const todayPct = ((nowTs - ganttRange.minDate) / (ganttRange.maxDate - ganttRange.minDate || 1)) * 100;
              return todayPct >= 0 && todayPct <= 100 && (
                <div className="absolute top-0 bottom-0 border-l border-dashed border-muted/50 z-10 pointer-events-none" style={{ left: `${todayPct}%` }} title="Today">
                  <span className="absolute -left-3 -top-3.5 text-[8px] font-bold text-muted/60 bg-surface px-0.5 rounded">Today</span>
                </div>
              );
            })()}
            {ganttGroups.map(g => {
              const range = ganttRange.maxDate - ganttRange.minDate || 1;
              const shipTs = Math.max(new Date(g.ship_date).getTime(), ganttRange.minDate);
              const arrTs = Math.min(new Date(g.arrival_date).getTime(), ganttRange.maxDate);
              const left = ((shipTs - ganttRange.minDate) / range) * 100;
              const width = Math.max(2, ((arrTs - shipTs) / range) * 100);
              const color = TYPE_COLORS[g.type] ?? '#64748b';
              const isPo = g.products.some(p => p.status === 'po_needed' || p.status === 'po');
              const needsPo = g.products.some(p => p.status === 'po_needed');
              const isTransit = g.products.some(p => p.status === 'transit');
              const isSugg = !isPo && !isTransit && !g.hasAllApproved && !g.hasAllScheduled;
              const isAppr = !isPo && !isTransit && g.hasAllApproved && !g.hasAllScheduled;
              const isSolid = isTransit || (!isSugg && !isAppr && !isPo);
              const isHovered = ganttHover === g.key;
              const clampedLeft = Math.max(0, left);
              const clampedWidth = Math.min(width, 100 - clampedLeft);

              const isEditing = editEtaPoId === g.key;

              return (
                <div key={g.key} className={`relative h-7 flex items-center ${isHovered || isEditing ? 'z-[100]' : 'z-10'}`}>
                  {/* Bar — hover only triggers on the rectangle */}
                  <div className="absolute h-5 cursor-default"
                    onMouseEnter={() => setGanttHover(g.key)}
                    onMouseLeave={() => setGanttHover(null)}
                    style={{
                      left: `${clampedLeft}%`,
                      width: `${clampedWidth}%`,
                      background: isPo ? color + '15' : isSolid ? color : color + '25',
                      opacity: isSolid ? 0.9 : 1,
                      border: isPo ? `1px solid ${color}` : isSugg ? `1.5px dashed ${color}` : isAppr ? `1.5px dotted ${color}` : 'none',
                      borderRadius: isPo ? '2px' : '10px',
                    }}
                  >
                    {/* Text on bar: ship date — qty — arrival date */}
                    <div className="flex items-center justify-between pointer-events-none text-[8px] tabular-nums px-1 h-full">
                      <span className="font-medium truncate" style={{ color: 'var(--color-muted)' }}>{fmtDate(g.ship_date)}</span>
                      <span className="font-bold" style={{ color: 'var(--color-text)' }}>{fmt(g.totalQty)}</span>
                      <span className="font-medium truncate" style={{ color: 'var(--color-muted)' }}>{fmtDate(g.arrival_date)}</span>
                    </div>
                    {/* Hover tooltip — product breakdown */}
                    {isHovered && (
                      <div className="absolute z-50 rounded-lg border border-border bg-surface shadow-lg px-3 py-2 min-w-[180px]"
                        style={{ left: 0, top: 22 }}>
                        <div className="text-[9px] font-bold text-heading mb-1">{g.icon} {g.type.replace(/_/g, ' ')} — {fmtDate(g.ship_date)}</div>
                        <div className="text-[9px] text-muted mb-2">
                          {g.route && <span>Route: {g.route}</span>}
                          {g.route && g.transit_type && <span> | </span>}
                          {g.transit_type && <span>Transit: {g.transit_type}</span>}
                        </div>
                        <div className="space-y-0.5">
                          {g.products.map((p, i) => (
                            <div key={i} className="flex items-center justify-between gap-4 text-[9px]">
                              <span className="text-muted truncate">{p.name}</span>
                              <span className="font-bold tabular-nums" style={{ color: 'var(--color-heading)' }}>{fmt(p.qty)}</span>
                            </div>
                          ))}
                        </div>
                        <div className="border-t border-border/30 mt-1 pt-1 flex items-center justify-between text-[9px] font-bold">
                          <span className="text-muted">Total</span>
                          <span style={{ color }}>{fmt(g.totalQty)}</span>
                        </div>
                      </div>
                    )}
                  </div>

                  {/* Add PO Button */}
                  {needsPo && (
                    <div className="absolute z-20 flex items-center" style={{ left: `${clampedLeft + clampedWidth}%`, height: '100%', paddingLeft: 6 }}>
                      <button 
                        onClick={(e) => { e.stopPropagation(); handleAddPoGroup(g); }}
                        className="bg-emerald-500/20 hover:bg-emerald-500/40 text-emerald-400 rounded-full w-4 h-4 flex items-center justify-center transition-colors shadow-sm cursor-pointer"
                        title="Add to PO Draft"
                      >
                        <Plus size={10} strokeWidth={3} />
                      </button>
                    </div>
                  )}

                  {/* Edit ETA Button for POs */}
                  {isPo && !needsPo && g.po_ids.length > 0 && (
                    <div className="absolute z-20 flex items-center" style={{ left: `${clampedLeft + clampedWidth}%`, height: '100%', paddingLeft: 6 }}>
                      <button 
                        onClick={(e) => { e.stopPropagation(); setEditEtaPoId(editEtaPoId === g.key ? null : g.key); }}
                        className="bg-purple-500/20 hover:bg-purple-500/40 text-purple-400 rounded-full w-4 h-4 flex items-center justify-center transition-colors shadow-sm cursor-pointer"
                        title="Update arrival date"
                      >
                        <CalendarDays size={9} strokeWidth={2.5} />
                      </button>
                    </div>
                  )}

                  {/* Per-PO Date Picker Popup */}
                  {isEditing && (
                    <div className="absolute rounded-xl shadow-2xl border border-purple-500/40 bg-[var(--color-card)] z-[100]"
                      style={{ left: `${Math.min(clampedLeft + clampedWidth + 2, 75)}%`, top: '100%', marginTop: 4, minWidth: 240 }}
                      onClick={(e) => e.stopPropagation()}
                    >
                      <div className="px-3 pt-2.5 pb-1.5 border-b border-border/30 flex items-center justify-between">
                        <span className="text-[10px] font-bold text-heading flex items-center gap-1.5">
                          <CalendarDays size={11} className="text-purple-400" /> Update Arrival Dates
                        </span>
                        <button onClick={(e) => { e.stopPropagation(); setEditEtaPoId(null); }}
                          className="text-muted hover:text-heading transition-colors p-0.5">
                          <X size={12} />
                        </button>
                      </div>
                      <div className="p-2.5 space-y-2">
                        {g.products.filter(p => p.po_id).map((p, i) => (
                          <div key={p.po_id || i} className="flex items-center gap-2">
                            <div className="flex-1 min-w-0">
                              <div className="text-[9px] font-medium text-muted truncate">{p.name}</div>
                              <div className="text-[8px] text-muted/60 tabular-nums">{fmt(p.qty)} units</div>
                            </div>
                            <input type="date"
                              defaultValue={p.arrival_date || g.arrival_date}
                              data-po-id={p.po_id}
                              className="bg-transparent border border-border/40 focus:border-purple-500/60 rounded-md px-2 py-1 text-[10px] tabular-nums text-heading font-mono outline-none transition-colors w-[120px]"
                            />
                            <button
                              onClick={async (e) => {
                                e.stopPropagation();
                                const btn = e.currentTarget;
                                const row = btn.parentElement!;
                                const inp = row.querySelector('input[type="date"]') as HTMLInputElement;
                                if (inp?.value && p.po_id) {
                                  const originalText = btn.textContent;
                                  const originalClass = btn.className;
                                  btn.textContent = 'Saving...';
                                  btn.className = "px-2 py-1 text-[9px] rounded-md bg-purple-500/30 text-purple-400 border border-purple-500/50 font-semibold transition-colors whitespace-nowrap opacity-70 pointer-events-none";
                                  try {
                                    await handleUpdateEta(p.po_id, inp.value);
                                    btn.textContent = 'Saved!';
                                    btn.className = "px-2 py-1 text-[9px] rounded-md bg-emerald-500/20 text-emerald-500 border border-emerald-500/40 font-semibold transition-colors whitespace-nowrap";
                                    setTimeout(() => {
                                      btn.textContent = originalText;
                                      btn.className = originalClass;
                                    }, 2000);
                                  } catch (err) {
                                    btn.textContent = 'Error';
                                    btn.className = "px-2 py-1 text-[9px] rounded-md bg-red-500/20 text-red-500 border border-red-500/40 font-semibold transition-colors whitespace-nowrap";
                                    setTimeout(() => {
                                      btn.textContent = originalText;
                                      btn.className = originalClass;
                                    }, 2000);
                                  }
                                }
                              }}
                              className="px-2 py-1 text-[9px] rounded-md bg-purple-500/15 text-purple-400 hover:bg-purple-500/30 border border-purple-500/30 font-semibold transition-colors whitespace-nowrap"
                            >Save</button>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Add Shipment Button */}
                  {isAppr && (
                    <div className="absolute z-20 flex items-center" style={{ left: `${clampedLeft + clampedWidth}%`, height: '100%', paddingLeft: 6 }}>
                      <button 
                        onClick={(e) => { e.stopPropagation(); handleAddShipmentGroup(g); }}
                        className="bg-blue-500/20 hover:bg-blue-500/40 text-blue-400 rounded-full w-4 h-4 flex items-center justify-center transition-colors shadow-sm cursor-pointer"
                        title="Add to Shipment Draft"
                      >
                        <Plus size={10} strokeWidth={3} />
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      <div className="space-y-2">
        {filteredGroups.map(group => {
          const isExp = expanded === group.key || expanded === '__ALL__';
          const color = TYPE_COLORS[group.type_name] || '#666';
          const icon = TYPE_ICONS[group.type_name] || '📦';
          const allDone = group.suggestedCount === 0;

          return (
            <div key={group.key} className="rounded-lg border overflow-hidden" style={{ borderColor: color + '25' }}>
              {/* Parent card header */}
              <button className="w-full flex items-center gap-2 px-3 py-2 text-left hover:bg-white/[0.02] transition-colors"
                onClick={() => setExpanded(isExp ? null : group.key)}>
                {isExp ? <ChevronDown size={12} className="text-muted" /> : <ChevronRight size={12} className="text-muted" />}
                <span className="text-sm">{icon}</span>
                <span className="font-bold text-[12px]" style={{ color }}>{group.type_name.replace(/_/g, ' ')}</span>
                <span className="text-[10px] text-muted">{fmtDate(group.ship_wednesday)}</span>
                <span className="text-[10px] text-muted">•</span>
                <span className="text-[10px] text-muted">{group.rows.length} prod</span>
                <span className="text-[10px] text-muted">•</span>
                <span className="text-[10px] font-bold tabular-nums" style={{ color: 'var(--color-text)' }}>{fmt(group.totalQty)}</span>
                <span className="ml-auto flex items-center gap-2">
                  {group.type_name === 'Purchase Order' 
                    ? <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-purple-500/20 text-purple-400 font-bold flex items-center gap-0.5">In Progress</span>
                    : allDone
                      ? <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 font-bold flex items-center gap-0.5"><CheckCircle size={9} /> Done</span>
                      : <span className="text-[9px] text-muted">{group.approvedCount + group.scheduledCount}/{group.rows.length}</span>}
                </span>
              </button>

              {/* Expanded: compact table */}
              <div data-shipment-group-body className="border-t" style={{ borderColor: color + '15', display: isExp ? 'block' : 'none' }}>
                  {/* Approve All */}
                  {group.suggestedCount > 0 && (
                    <div className="flex justify-end px-3 pt-2">
                      <button onClick={() => handleApproveAll(group)} disabled={busy === group.key}
                        className="inline-flex items-center gap-1 px-2 py-1 text-[9px] rounded bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20 border border-emerald-500/30 font-bold">
                        <Check size={10} /> Approve All ({group.suggestedCount})
                      </button>
                    </div>
                  )}

                  {/* Compact table */}
                  <div className="overflow-x-auto">
                    <table className="w-full text-[10px]">
                      <thead><tr className="text-muted/60 text-[9px] uppercase tracking-wider">
                        <th className="text-left py-1.5 px-3 font-medium">Product</th>
                        <th className="text-center py-1.5 px-2 font-medium">Status</th>
                        <th className="text-right py-1.5 px-2 font-medium">Qty</th>
                        <th className="text-right py-1.5 px-2 font-medium">Ship</th>
                        <th className="text-right py-1.5 px-2 font-medium">Arrives</th>
                        <th className="text-left py-1.5 px-2 font-medium">Route</th>
                        <th className="text-right py-1.5 px-3 font-medium">Actions</th>
                      </tr></thead>
                      <tbody>
                        {group.rows.map((row, i) => {
                          const sc = STATUS_COLORS[row._status];
                          const busyKey = row._schedule_id || (row.product + row.ship_wednesday);
                          const isBusy = busy === busyKey;
                          const editKey = row._schedule_id || '';
                          const currentQty = editQty[editKey] ?? row.ship_qty;
                          const plan = yearlyPlanMap[row.product] || 0;
                          const ytdSold = salesSummary.find(s => s.product_name === row.product)?.sold ?? 0;
                          const maxAllowed = Math.max(Math.max(0, plan - ytdSold), row.ship_qty);

                          return (
                            <tr key={`${row.product}-${i}`} className="border-t border-border/5 hover:bg-white/[0.015]">
                              <td className="py-1.5 px-3 font-medium" style={{ color: 'var(--color-text)' }}>{row.product}</td>
                              <td className="py-1.5 px-2 text-center">
                                <span className="inline-block px-1.5 py-0.5 rounded-full text-[8px] font-bold whitespace-nowrap"
                                  style={{ background: sc + '20', color: sc, border: `1px solid ${sc}40` }}>
                                  {row._status === 'suggested' ? 'SUGG' : row._status === 'approved' ? 'APPR' : row._status === 'po' ? 'PO' : 'SCHED'}
                                </span>
                              </td>
                              <td className="py-1.5 px-2 text-right tabular-nums font-bold">
                                {(row._status === 'approved' || row._status === 'suggested') && row._schedule_id ? (
                                  <input type="number" value={currentQty} min={1} max={maxAllowed}
                                    onChange={e => {
                                      let val = Number(e.target.value) || 0;
                                      if (val > maxAllowed) val = maxAllowed;
                                      setEditQty(p => ({ ...p, [editKey]: val }));
                                    }}
                                    onBlur={() => { 
                                      if (currentQty !== row.ship_qty && row._schedule_id) {
                                        if (row._status === 'approved') {
                                          handleQtyUpdate(row._schedule_id, currentQty); 
                                        } else if (row._status === 'suggested') {
                                          handleApprove(row, currentQty);
                                        }
                                      }
                                    }}
                                    className={`w-14 text-right bg-surface border rounded px-1 py-0.5 text-[10px] tabular-nums text-heading font-mono ${row._status === 'suggested' ? 'border-emerald-500/30' : 'border-amber-500/30'}`} />
                                ) : <span style={{ color: 'var(--color-text)' }}>{fmt(row.ship_qty)}{row.ship_cartons > 0 && <span className="text-muted text-[8px] ml-0.5">({row.ship_cartons} ctns)</span>}</span>}
                              </td>
                              <td className="py-1.5 px-2 text-right tabular-nums text-muted">{fmtDate(row.ship_wednesday)}</td>
                              <td className="py-1.5 px-2 text-right tabular-nums text-muted">
                                {row._status === 'po' && editEtaPoId === row._po_id ? (
                                  <input type="date" autoFocus
                                    defaultValue={row.arrival_date}
                                    onBlur={(e) => {
                                      const val = e.target.value;
                                      if (val && val !== row.arrival_date) {
                                        handleUpdateEta(row._po_id!, val);
                                      } else {
                                        setEditEtaPoId(null);
                                      }
                                    }}
                                    onKeyDown={(e) => {
                                      if (e.key === 'Enter') {
                                        const val = (e.target as HTMLInputElement).value;
                                        if (val) handleUpdateEta(row._po_id!, val);
                                      } else if (e.key === 'Escape') {
                                        setEditEtaPoId(null);
                                      }
                                    }}
                                    className="w-[110px] bg-surface border border-purple-500/30 rounded px-1 py-0.5 text-[10px] tabular-nums text-heading font-mono"
                                  />
                                ) : (
                                  <span className={`${row._has_manual_eta ? 'text-purple-400 font-medium' : ''}`}>
                                    {fmtDate(row.arrival_date)}
                                  </span>
                                )}
                              </td>
                              <td className="py-1.5 px-2 text-muted">{row.transit_type}</td>
                              <td className="py-1.5 px-3 text-right">
                                <div className="flex justify-end gap-1">
                                  {row._status === 'po' && row._po_id && (
                                    <button onClick={() => setEditEtaPoId(row._po_id!)}
                                      disabled={busy === row._po_id}
                                      className="px-1.5 py-0.5 text-[8px] rounded bg-purple-500/10 text-purple-400 hover:bg-purple-500/20 border border-purple-500/30 font-bold"
                                      title="Update arrival date"
                                    >
                                      <CalendarDays size={8} className="inline" />
                                    </button>
                                  )}
                                  {row._status === 'suggested' && (
                                    <button onClick={() => handleApprove(row, currentQty)} disabled={isBusy}
                                      className="px-1.5 py-0.5 text-[8px] rounded bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20 border border-emerald-500/30 font-bold">
                                      ✓
                                    </button>
                                  )}
                                  {row._status === 'approved' && row._schedule_id && (<>
                                    <button onClick={() => handleSchedule(row._schedule_id!)} disabled={isBusy}
                                      className="px-1.5 py-0.5 text-[8px] rounded bg-blue-500/10 text-blue-400 hover:bg-blue-500/20 border border-blue-500/30 font-bold">
                                      <Lock size={8} className="inline" />
                                    </button>
                                    <button onClick={() => handleRevert(row._schedule_id!)} disabled={isBusy}
                                      className="px-1.5 py-0.5 text-[8px] rounded bg-red-500/10 text-red-400 hover:bg-red-500/20 border border-red-500/30 font-bold">
                                      ✕
                                    </button>
                                  </>)}
                                  {row._status === 'scheduled' && row._schedule_id && (
                                    <button onClick={() => handleUnschedule(row._schedule_id!)} disabled={isBusy}
                                      className="px-1.5 py-0.5 text-[8px] rounded bg-amber-500/10 text-amber-400 hover:bg-amber-500/20 border border-amber-500/30 font-bold">
                                      <RotateCcw size={8} className="inline" />
                                    </button>
                                  )}
                                </div>
                              </td>
                            </tr>
                          );
                        })}
                        {/* Totals row */}
                        <tr className="border-t border-border/20 bg-surface/30 font-bold text-[9px]">
                          <td className="py-1.5 px-3 text-muted uppercase">{group.rows.length} products</td>
                          <td className="py-1.5 px-2"></td>
                          <td className="py-1.5 px-2 text-right tabular-nums" style={{ color: 'var(--color-text)' }}>{fmt(group.totalQty)}</td>
                          <td className="py-1.5 px-2"></td>
                          <td className="py-1.5 px-2"></td>
                          <td className="py-1.5 px-2"></td>
                          <td className="py-1.5 px-3"></td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
              </div>
            </div>
          );
        })}
      </div>
      </div>
    </Section>

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
            onClick={() => setDraftPOLines([])}
            className="px-4 py-1.5 text-xs font-medium text-muted hover:text-heading hover:bg-white/5 rounded-full transition-colors"
          >
            Cancel
          </button>
          <button 
            onClick={() => setShowPOModal(true)}
            className="px-5 py-1.5 bg-purple-500 hover:bg-purple-600 text-white text-xs font-bold rounded-full shadow-lg shadow-purple-500/20 transition-all"
          >
            Create PO
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
          onAction();
        }}
      />
    )}

    {/* Create Shipment Modal */}
    {showShipmentModal && (
      <CreateShipmentModal
        draftLines={draftShipmentLines}
        defaultDate={showShipmentModal.ship_date || (draftShipmentLines.length > 0 ? new Date().toISOString().split('T')[0] : undefined)}
        defaultType={showShipmentModal.transit_type}
        onClose={() => setShowShipmentModal(false)}
        onSuccess={() => {
          setShowShipmentModal(false);
          setDraftShipmentLines([]);
          onAction();
        }}
      />
    )}
    </>
  );
}
