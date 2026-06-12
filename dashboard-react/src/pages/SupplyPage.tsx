/**
 * SupplyPage — PO / Payments / Shipments dashboard
 *
 * Summary cards: Unpaid to Manufacturer, Unpaid to Shipment, Other Unpaid
 * Three tabs with independent date filters and "show open" toggles:
 *   - Purchase Orders (filtered by order_date)
 *   - Payments (filtered by payment_date)
 *   - Shipments (filtered by shipment_date)
 */

import { useState, useMemo, useCallback, Fragment, useRef, useEffect } from 'react';
import type { DashboardData, SupplyPORow, SupplyPaymentRow, SupplyShipmentRow } from '../types';
import { Package, CreditCard, Truck, ChevronDown, ChevronUp, Filter, X, Download, Copy, Check, Pencil, Save, AlertCircle, BarChart3, Eye, ExternalLink } from 'lucide-react';
import XLSX from 'xlsx-js-style';
import { cubeLoad } from '../hooks/useCubeData';
import PODetailsModal from '../components/PODetailsModal';

/* ─── helpers ─── */
const fmt$ = (v?: number | null) => {
  if (v == null || Number.isNaN(Number(v))) return '—';
  const num = Number(v);
  return num >= 1000 ? `$${(num / 1000).toFixed(1)}K` : `$${num.toFixed(0)}`;
};
const fmtFull$ = (v?: number | null) => {
  if (v == null || Number.isNaN(Number(v))) return '—';
  return `$${Number(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
};
const fmtDate = (d: string) => d ? new Date(d + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '—';

type Tab = 'pos' | 'payments' | 'shipments' | 'snapshot';

/* ─── Stock Snapshot row type ─── */
interface StockSnapshotRow {
  date: string;
  source_type: string;
  product_family: string;
  product_short_name: string;
  quantity_balance: number;
  cost_of_goods: number | null;
  shipping_cost: number | null;
  stock_value: number;
  paid_amount: number;
}

/* ─── Horizontal Scroller ─── */
function HorizontalScroller({ items }: { items: { label: string; value: string; color?: string; sub?: string }[] }) {
  const ref = useRef<HTMLDivElement>(null);
  return (
    <div className="relative mb-3">
      <div
        ref={ref}
        className="flex gap-3 overflow-x-auto pb-1 scrollbar-thin"
        style={{ scrollbarWidth: 'thin', scrollbarColor: 'var(--color-border) transparent' }}
      >
        {items.map((item, i) => (
          <div
            key={i}
            className="shrink-0 flex flex-col gap-0.5 rounded-lg border border-border bg-card px-4 py-2.5 min-w-[140px]"
          >
            <span className="text-[10px] font-semibold text-faint uppercase tracking-wider whitespace-nowrap">{item.label}</span>
            <span className="text-lg font-bold font-mono whitespace-nowrap" style={{ color: item.color || 'var(--color-heading)' }}>{item.value}</span>
            {item.sub && <span className="text-[10px] text-muted whitespace-nowrap">{item.sub}</span>}
          </div>
        ))}
      </div>
    </div>
  );
}
type SortDir = 'asc' | 'desc';

/* ─── Summary Card ─── */
function SummaryCard({ label, value, icon, color, detail }: {
  label: string; value: number; icon: React.ReactNode; color: string; detail?: string;
}) {
  return (
    <div className="rounded-xl border border-border bg-card p-5 flex items-start gap-4 min-w-[220px]">
      <div className={`w-10 h-10 rounded-lg flex items-center justify-center shrink-0`} style={{ background: `${color}20` }}>
        <span style={{ color }}>{icon}</span>
      </div>
      <div>
        <div className="text-xs text-faint uppercase tracking-wider font-semibold mb-1">{label}</div>
        <div className="text-2xl font-bold text-heading">{fmtFull$(value)}</div>
        {detail && <div className="text-xs text-muted mt-0.5">{detail}</div>}
      </div>
    </div>
  );
}

/* ─── Per-product breakdown mini-table ─── */
function ProductBreakdown({ pos }: { pos: SupplyPORow[] }) {
  const byProduct = useMemo(() => {
    const map: Record<string, { product: string; unpaid_mfg: number; unpaid_ship: number; total: number }> = {};
    for (const po of pos) {
      const key = po.product_name || po.product_asin || 'Unknown';
      if (!map[key]) map[key] = { product: key, unpaid_mfg: 0, unpaid_ship: 0, total: 0 };
      map[key].unpaid_mfg += Math.max(po.unpaid_manufacturer, 0);
      map[key].unpaid_ship += Math.max(po.unpaid_shipment, 0);
      map[key].total += Math.max(po.total_unpaid, 0);
    }
    return Object.values(map).filter(r => r.total > 0.01).sort((a, b) => b.total - a.total);
  }, [pos]);

  if (byProduct.length === 0) return null;

  return (
    <div className="mt-4 rounded-xl border border-border overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-border bg-surface/50">
            <th className="text-left px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Product</th>
            <th className="text-right px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Unpaid Manufacturer</th>
            <th className="text-right px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Unpaid Shipment</th>
            <th className="text-right px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Total Unpaid</th>
          </tr>
        </thead>
        <tbody>
          {byProduct.map(r => (
            <tr key={r.product} className="border-b border-border/50 hover:bg-white/[.02] transition-colors">
              <td className="px-4 py-2.5 text-subtle font-medium">{r.product}</td>
              <td className="px-4 py-2.5 text-right text-red-400 font-mono text-xs">{fmtFull$(r.unpaid_mfg)}</td>
              <td className="px-4 py-2.5 text-right text-orange-400 font-mono text-xs">{fmtFull$(r.unpaid_ship)}</td>
              <td className="px-4 py-2.5 text-right text-heading font-semibold font-mono text-xs">{fmtFull$(r.total)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ─── Date range filter chip ─── */
function DateFilter({ label, from, to, onChange }: {
  label: string; from: string; to: string;
  onChange: (from: string, to: string) => void;
}) {
  return (
    <div className="flex items-center gap-2 text-xs">
      <span className="text-faint font-medium">{label}:</span>
      <input
        type="date"
        value={from}
        onChange={e => onChange(e.target.value, to)}
        className="bg-surface border border-border rounded px-2 py-1 text-subtle text-xs focus:outline-none focus:ring-1 focus:ring-blue-500/50"
      />
      <span className="text-faint">→</span>
      <input
        type="date"
        value={to}
        onChange={e => onChange(from, e.target.value)}
        className="bg-surface border border-border rounded px-2 py-1 text-subtle text-xs focus:outline-none focus:ring-1 focus:ring-blue-500/50"
      />
      {(from || to) && (
        <button onClick={() => onChange('', '')} className="text-faint hover:text-red-400 transition-colors" title="Clear dates">
          <X size={14} />
        </button>
      )}
    </div>
  );
}

/* ─── Status badge ─── */
function StatusBadge({ status }: { status: string }) {
  const s = status.toLowerCase();
  let bg = 'bg-gray-500/10 text-gray-400';
  if (s.includes('fully paid')) bg = 'bg-emerald-500/10 text-emerald-400';
  else if (s.includes('pending po')) bg = 'bg-red-500/10 text-red-400';
  else if (s.includes('po paid') && s.includes('pending ship')) bg = 'bg-amber-500/10 text-amber-400';
  else if (s.includes('po paid')) bg = 'bg-blue-500/10 text-blue-400';
  return <span className={`inline-block px-2 py-0.5 rounded-full text-[10px] font-semibold whitespace-nowrap ${bg}`}>{status}</span>;
}

function ShipmentStatusBadge({ status }: { status: string }) {
  const s = (status || '').toUpperCase();
  let bg = 'bg-gray-500/10 text-gray-400';
  if (s === 'PUT_AWAY' || s === 'RECEIVED') bg = 'bg-emerald-500/10 text-emerald-400';
  else if (s === 'IN_TRANSIT' || s === 'SHIPPED') bg = 'bg-blue-500/10 text-blue-400';
  else if (s === 'INSPECTED') bg = 'bg-purple-500/10 text-purple-400';
  else if (s === 'PREPARING' || s === 'PENDING') bg = 'bg-amber-500/10 text-amber-400';
  return <span className={`inline-block px-2 py-0.5 rounded-full text-[10px] font-semibold tracking-wide ${bg}`}>{status || '—'}</span>;
}

/* ─── Sortable column header ─── */
function SortHeader({ label, field, sortField, sortDir, onSort, align = 'right' }: {
  label: string; field: string; sortField: string; sortDir: SortDir;
  onSort: (field: string) => void;
  align?: 'left' | 'right' | 'center';
}) {
  const isActive = field === sortField;
  const alignClass = align === 'left' ? 'text-left' : align === 'center' ? 'text-center' : 'text-right';
  return (
    <th
      className={`${alignClass} px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider cursor-pointer hover:text-subtle select-none transition-colors`}
      onClick={() => onSort(field)}
    >
      <span className={`inline-flex items-center gap-0.5 ${align === 'right' ? 'justify-end w-full' : ''}`}>
        {label}
        {isActive && (sortDir === 'asc' ? <ChevronUp size={12} /> : <ChevronDown size={12} />)}
      </span>
    </th>
  );
}

/* ═══════════════════════════════════════════════════════════════
 * MAIN PAGE
 * ═══════════════════════════════════════════════════════════════ */
export function SupplyPage({ data }: { data: DashboardData }) {
  const [tab, setTab] = useState<Tab>('pos');
  const [showOpenOnly, setShowOpenOnly] = useState(true);
  const [showZeroBalances, setShowZeroBalances] = useState(false);

  // Independent date filters per tab
  const [poDateFrom, setPODateFrom] = useState('');
  const [poDateTo, setPODateTo] = useState('');
  const [payDateFrom, setPayDateFrom] = useState('');
  const [payDateTo, setPayDateTo] = useState('');
  const currentYearStr = new Date().getFullYear().toString();
  const [payYear, setPayYear] = useState<string>(currentYearStr);
  const [shipDateFrom, setShipDateFrom] = useState('');
  const [shipDateTo, setShipDateTo] = useState('');

  // Sort state per tab
  const [poSort, setPOSort] = useState<{ field: string; dir: SortDir }>({ field: 'order_date', dir: 'desc' });
  const [paySort, setPaySort] = useState<{ field: string; dir: SortDir }>({ field: 'payment_date', dir: 'desc' });
  const [shipSort, setShipSort] = useState<{ field: string; dir: SortDir }>({ field: 'shipment_date', dir: 'desc' });
  const [snapSort, setSnapSort] = useState<{ field: string; dir: SortDir }>({ field: 'stock_value', dir: 'desc' });

  // Stock snapshot state
  const [snapshotDate, setSnapshotDate] = useState(new Date().toISOString().slice(0, 10));
  const [snapshotRows, setSnapshotRows] = useState<StockSnapshotRow[]>([]);
  const [snapshotLoading, setSnapshotLoading] = useState(false);
  const [snapshotGroup, setSnapshotGroup] = useState<'source' | 'product'>('source');

  // Load stock snapshot data on-demand when tab is active and date changes
  useEffect(() => {
    if (tab !== 'snapshot' || !snapshotDate) return;
    let cancelled = false;
    const load = async () => {
      setSnapshotLoading(true);
      try {
        const rows = await cubeLoad({
          dimensions: [
            'InventorySnapshot.date',
            'InventorySnapshot.sourceType',
            'InventorySnapshot.productFamily',
            'InventorySnapshot.productShortName',
            'InventorySnapshot.quantityBalance',
            'InventorySnapshot.costOfGoods',
            'InventorySnapshot.shippingCost',
          ],
          measures: [
            'InventorySnapshot.totalPaidAmount'
          ],
          timeDimensions: [
            { dimension: 'InventorySnapshot.date', dateRange: [snapshotDate, snapshotDate] },
          ],
          limit: 5000,
        });
        if (cancelled) return;
        
        const mapped = (rows as Record<string, unknown>[])
          .map(r => {
          const qty = Number(r['InventorySnapshot.quantityBalance'] ?? 0);
          const cogs = r['InventorySnapshot.costOfGoods'] != null ? Number(r['InventorySnapshot.costOfGoods']) : null;
          const ship = r['InventorySnapshot.shippingCost'] != null ? Number(r['InventorySnapshot.shippingCost']) : null;
          const sourceType = String(r['InventorySnapshot.sourceType'] ?? '');
          const isMfr = sourceType === 'MFR Ready' || sourceType === 'In Production';
          const effectiveShip = isMfr ? 0 : (ship ?? 0);
          const stockValue = qty * ((cogs ?? 0) + effectiveShip);
          return {
            date: r['InventorySnapshot.date'] ? String(r['InventorySnapshot.date']).slice(0, 10) : snapshotDate,
            source_type: sourceType,
            product_family: String(r['InventorySnapshot.productFamily'] ?? ''),
            product_short_name: String(r['InventorySnapshot.productShortName'] ?? ''),
            quantity_balance: qty,
            cost_of_goods: cogs,
            shipping_cost: isMfr ? null : ship,
            stock_value: stockValue,
            paid_amount: Number(r['InventorySnapshot.totalPaidAmount'] ?? 0),
          };
        });
        setSnapshotRows(mapped);
      } catch (e) {
        console.error('[SupplyPage] Stock snapshot load failed:', e);
        setSnapshotRows([]);
      } finally {
        if (!cancelled) setSnapshotLoading(false);
      }
    };
    load();
    return () => { cancelled = true; };
  }, [tab, snapshotDate]);

  const filteredSnapshot = useMemo(() => {
    const { field, dir } = snapSort;
    return snapshotRows
      .filter(r => showZeroBalances || r.quantity_balance !== 0)
      .sort((a, b) => {
        const av = (a as Record<string, unknown>)[field];
        const bv = (b as Record<string, unknown>)[field];
        if (typeof av === 'number' && typeof bv === 'number') return dir === 'asc' ? av - bv : bv - av;
        return dir === 'asc' ? String(av ?? '').localeCompare(String(bv ?? '')) : String(bv ?? '').localeCompare(String(av ?? ''));
      });
  }, [snapshotRows, snapSort, showZeroBalances]);

  const toggleSort = useCallback((setter: React.Dispatch<React.SetStateAction<{ field: string; dir: SortDir }>>) =>
    (field: string) => setter(prev => ({
      field,
      dir: prev.field === field && prev.dir === 'desc' ? 'asc' : 'desc',
    })),
  []);

  /* ─── Summary from ALL POs (not filtered) ─── */
  const allPos = data.supply_pos || [];
  const summaryTotals = useMemo(() => {
    let mfg = 0, ship = 0, other = 0;
    for (const po of allPos) {
      mfg += Math.max(po.unpaid_manufacturer, 0);
      ship += Math.max(po.unpaid_shipment, 0);
    }
    // Other POs from DE_OTHER_PO
    for (const opo of (data.supply_other_pos || [])) {
      if (opo.payment_status !== 'PAID') other += opo.total_amount;
    }
    return { mfg, ship, other, total: mfg + ship + other };
  }, [allPos, data.supply_other_pos]);

  /* ─── Filtered POs ─── */
  const filteredPOs = useMemo(() => {
    let rows = allPos;
    if (showOpenOnly) rows = rows.filter(r => r.is_open);
    if (poDateFrom) rows = rows.filter(r => r.order_date >= poDateFrom);
    if (poDateTo) rows = rows.filter(r => r.order_date <= poDateTo);
    const { field, dir } = poSort;
    rows = [...rows].sort((a, b) => {
      const av = (a as Record<string, unknown>)[field];
      const bv = (b as Record<string, unknown>)[field];
      if (typeof av === 'number' && typeof bv === 'number') return dir === 'asc' ? av - bv : bv - av;
      return dir === 'asc' ? String(av ?? '').localeCompare(String(bv ?? '')) : String(bv ?? '').localeCompare(String(av ?? ''));
    });
    return rows;
  }, [allPos, showOpenOnly, poDateFrom, poDateTo, poSort]);

  /* ─── Filtered Payments ─── */
  const allPayments = data.supply_payments || [];
  const paymentYears = useMemo(() => {
    const ys = new Set<string>();
    for (const p of allPayments) {
      if (p.payment_date) ys.add(p.payment_date.slice(0, 4));
    }
    ys.add(currentYearStr);
    return Array.from(ys).sort().reverse();
  }, [allPayments, currentYearStr]);

  const filteredPayments = useMemo(() => {
    let rows = allPayments;
    // Don't filter payments by is_open — payments are completed actions
    if (payYear !== 'All') rows = rows.filter(r => r.payment_date?.startsWith(payYear));
    if (payDateFrom) rows = rows.filter(r => r.payment_date >= payDateFrom);
    if (payDateTo) rows = rows.filter(r => r.payment_date <= payDateTo);
    const { field, dir } = paySort;
    rows = [...rows].sort((a, b) => {
      const av = (a as Record<string, unknown>)[field];
      const bv = (b as Record<string, unknown>)[field];
      if (typeof av === 'number' && typeof bv === 'number') return dir === 'asc' ? av - bv : bv - av;
      return dir === 'asc' ? String(av ?? '').localeCompare(String(bv ?? '')) : String(bv ?? '').localeCompare(String(av ?? ''));
    });
    return rows;
  }, [allPayments, payYear, payDateFrom, payDateTo, paySort]);

  /* ─── Filtered Shipments ─── */
  const allShipments = data.supply_shipments || [];
  const filteredShipments = useMemo(() => {
    let rows = allShipments;
    if (showOpenOnly) rows = rows.filter(r => r.is_open);
    if (shipDateFrom) rows = rows.filter(r => r.shipment_date >= shipDateFrom);
    if (shipDateTo) rows = rows.filter(r => r.shipment_date <= shipDateTo);
    const { field, dir } = shipSort;
    rows = [...rows].sort((a, b) => {
      const av = (a as Record<string, unknown>)[field];
      const bv = (b as Record<string, unknown>)[field];
      if (typeof av === 'number' && typeof bv === 'number') return dir === 'asc' ? av - bv : bv - av;
      return dir === 'asc' ? String(av ?? '').localeCompare(String(bv ?? '')) : String(bv ?? '').localeCompare(String(av ?? ''));
    });
    return rows;
  }, [allShipments, showOpenOnly, shipDateFrom, shipDateTo, shipSort]);

  const handleExport = useCallback(() => {
    let rows: any[] = [];
    let headers: string[] = [];
    let filename = '';

    if (tab === 'pos') {
      rows = filteredPOs;
      headers = ['order_date', 'purchase_order_id', 'manufacturer_name', 'product_name', 'quantity', 'total_amount', 'total_paid', 'unpaid_manufacturer', 'payment_status'];
      filename = 'purchase_orders';
    } else if (tab === 'payments') {
      // ── Styled XLSX export with colored rows per type ──
      const xlHeaders = ['Date', 'Vendor', 'Payment ID', 'File Name', 'Amount', 'Bank Fee', 'Total', 'Currency', 'Method'];
      const colCount = xlHeaders.length;
      const round2 = (v: number) => Math.round(v * 100) / 100;

      // Group payments by PO
      const groupMap = new Map<string, typeof filteredPayments>();
      const unlinked: typeof filteredPayments = [];
      const groupOrder: string[] = [];
      for (const r of filteredPayments) {
        if (!r.purchase_order_id) {
          unlinked.push(r);
        } else {
          if (!groupMap.has(r.purchase_order_id)) {
            groupMap.set(r.purchase_order_id, []);
            groupOrder.push(r.purchase_order_id);
          }
          groupMap.get(r.purchase_order_id)!.push(r);
        }
      }

      // Row styles
      const sHeader = { fill: { fgColor: { rgb: '1F2937' } }, font: { color: { rgb: 'FFFFFF' }, bold: true, sz: 11 }, alignment: { horizontal: 'center' as const } };
      const sPO     = { fill: { fgColor: { rgb: 'DBEAFE' } }, font: { bold: true, sz: 10, color: { rgb: '1E3A5F' } } };
      const sPay    = { fill: { fgColor: { rgb: 'FFFFFF' } }, font: { sz: 10, color: { rgb: '374151' } } };
      const sSub    = { fill: { fgColor: { rgb: 'F3F4F6' } }, font: { bold: true, sz: 10, color: { rgb: '1F2937' } } };
      const sGrand  = { fill: { fgColor: { rgb: '1E40AF' } }, font: { bold: true, sz: 11, color: { rgb: 'FFFFFF' } } };
      const sUnlink = { fill: { fgColor: { rgb: 'FEF3C7' } }, font: { bold: true, sz: 10, color: { rgb: '92400E' } } };
      const sMoneyPay = { ...sPay, numFmt: '#,##0.00' };
      const sMoneyPO  = { ...sPO, numFmt: '#,##0.00' };
      const sMoneySub = { ...sSub, numFmt: '#,##0.00' };
      const sMoneyGr  = { ...sGrand, numFmt: '#,##0.00' };

      // Build AOA (array-of-arrays) with row type tracking
      type RowType = 'header' | 'po' | 'pay' | 'sub' | 'grand' | 'unlinked' | 'empty';
      const aoa: unknown[][] = [];
      const rowTypes: RowType[] = [];

      // Header row
      aoa.push(xlHeaders);
      rowTypes.push('header');

      let grandAmount = 0, grandFee = 0, grandTotal = 0;

      for (const poId of groupOrder) {
        const po = allPos.find(p => p.purchase_order_id === poId);
        const poCost = po ? round2(po.total_amount) : 0;
        const poPaid = po ? round2(po.total_paid) : 0;
        const poRem = round2(Math.max(poCost - poPaid, 0));
        const paidPct = poCost > 0 ? Math.round((poPaid / poCost) * 100) : 0;
        const payments = groupMap.get(poId)!;

        // PO header row
        aoa.push([poId, `${payments.length} payments`, `${paidPct}% paid`, '', poCost, poPaid, poRem, '', '']);
        rowTypes.push('po');

        let subAmount = 0, subFee = 0, subTotal = 0;
        for (const r of payments) {
          const typePrefix = Boolean(r.shipment_id) ? 'INV_' : 'PI_';
          const fileName = r.payment_id ? r.payment_id.replace(/^PAY_/, typePrefix) : '';
          subAmount += r.payment_amount;
          subFee += r.bank_fee;
          subTotal += r.total_amount;
          aoa.push([r.payment_date, r.vendor_name, r.payment_id, fileName, round2(r.payment_amount), round2(r.bank_fee), round2(r.total_amount), r.currency, r.payment_method || '']);
          rowTypes.push('pay');
        }

        if (payments.length > 1) {
          aoa.push([`Subtotal (${payments.length})`, '', '', '', round2(subAmount), round2(subFee), round2(subTotal), '', '']);
          rowTypes.push('sub');
        }

        grandAmount += subAmount;
        grandFee += subFee;
        grandTotal += subTotal;

        // Blank separator
        aoa.push(Array(colCount).fill(''));
        rowTypes.push('empty');
      }

      // Unlinked payments
      if (unlinked.length > 0) {
        aoa.push([`Unlinked Payments (${unlinked.length})`, '', '', '', '', '', '', '', '']);
        rowTypes.push('unlinked');

        let subAmount = 0, subFee = 0, subTotal = 0;
        for (const r of unlinked) {
          const typePrefix = Boolean(r.shipment_id) ? 'INV_' : 'PI_';
          const fileName = r.payment_id ? r.payment_id.replace(/^PAY_/, typePrefix) : '';
          subAmount += r.payment_amount;
          subFee += r.bank_fee;
          subTotal += r.total_amount;
          aoa.push([r.payment_date, r.vendor_name, r.payment_id, fileName, round2(r.payment_amount), round2(r.bank_fee), round2(r.total_amount), r.currency, r.payment_method || '']);
          rowTypes.push('pay');
        }
        if (unlinked.length > 1) {
          aoa.push([`Subtotal (${unlinked.length})`, '', '', '', round2(subAmount), round2(subFee), round2(subTotal), '', '']);
          rowTypes.push('sub');
        }
        grandAmount += subAmount;
        grandFee += subFee;
        grandTotal += subTotal;

        aoa.push(Array(colCount).fill(''));
        rowTypes.push('empty');
      }

      // Grand total
      aoa.push([`TOTAL: ${groupOrder.length} POs · ${filteredPayments.length} Payments`, '', '', '', round2(grandAmount), round2(grandFee), round2(grandTotal), '', '']);
      rowTypes.push('grand');

      // Create worksheet and apply styles
      const ws = XLSX.utils.aoa_to_sheet(aoa);

      // Column widths
      ws['!cols'] = [
        { wch: 14 }, // Date
        { wch: 20 }, // Vendor
        { wch: 34 }, // Payment ID
        { wch: 38 }, // File Name
        { wch: 14 }, // Amount
        { wch: 12 }, // Bank Fee
        { wch: 14 }, // Total
        { wch: 10 }, // Currency
        { wch: 16 }, // Method
      ];

      // Apply styles per row
      for (let r = 0; r < aoa.length; r++) {
        const type = rowTypes[r];
        for (let c = 0; c < colCount; c++) {
          const ref = XLSX.utils.encode_cell({ r, c });
          if (!ws[ref]) ws[ref] = { v: '', t: 's' };
          const isMoney = c >= 4 && c <= 6;
          switch (type) {
            case 'header':  ws[ref].s = sHeader; break;
            case 'po':      ws[ref].s = isMoney ? sMoneyPO : sPO; break;
            case 'pay':     ws[ref].s = isMoney ? sMoneyPay : sPay; break;
            case 'sub':     ws[ref].s = isMoney ? sMoneySub : sSub; break;
            case 'grand':   ws[ref].s = isMoney ? sMoneyGr : sGrand; break;
            case 'unlinked': ws[ref].s = sUnlink; break;
          }
        }
      }

      const wb = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(wb, ws, 'Payments');
      XLSX.writeFile(wb, `supply_payments_${new Date().toISOString().slice(0, 10)}.xlsx`);
      return;
    } else if (tab === 'shipments') {
      rows = filteredShipments;
      headers = ['shipment_date', 'estimated_arrival_date', 'products_list', 'shipment_type', 'total_quantity_shipped', 'cost_shipped', 'unpaid_to_shipment', 'shipment_status'];
      filename = 'shipments';
    } else if (tab === 'snapshot') {
      // Custom CSV for stock snapshot
      const csvHeaders = ['Available In', 'Product', 'Quantity', 'MFR Cost/unit', 'Ship Cost/unit', 'Stock Value', 'Total Paid'];
      const csvRows = filteredSnapshot.map(r => [
        r.source_type,
        r.product_short_name,
        r.quantity_balance,
        r.cost_of_goods != null ? r.cost_of_goods.toFixed(2) : '',
        r.shipping_cost != null ? r.shipping_cost.toFixed(2) : '',
        r.stock_value.toFixed(2),
        r.paid_amount.toFixed(2),
      ].map(v => `"${String(v).replace(/"/g, '""')}"`).join(','));
      const csv = [csvHeaders.join(','), ...csvRows].join('\n');
      const blob = new Blob([csv], { type: 'text/csv' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `stock_snapshot_${snapshotDate}.csv`;
      a.click();
      URL.revokeObjectURL(url);
      return;
    }

    if (rows.length === 0) return;

    const csvRows = rows.map(row => {
      return headers.map(header => {
        let val = row[header];
        if (header === 'file_name' && tab === 'payments') {
          const typePrefix = Boolean(row.shipment_id) ? "INV_" : "PI_";
          val = row.payment_id ? row.payment_id.replace(/^PAY_/, typePrefix) : '—';
        }
        if (val === null || val === undefined) {
          val = '';
        } else if (typeof val === 'number' && !header.includes('quantity')) {
          val = Math.round(val * 100) / 100;
        }
        const str = String(val).replace(/"/g, '""');
        return `"${str}"`;
      }).join(',');
    });

    const csv = [headers.join(','), ...csvRows].join('\n');
    const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `supply_${filename}_${new Date().toISOString().slice(0, 10)}.csv`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  }, [tab, filteredPOs, filteredPayments, filteredShipments, filteredSnapshot, snapshotDate, allPos]);

  const tabs: { id: Tab; label: string; icon: React.ReactNode; count: number }[] = [
    { id: 'pos', label: 'Purchase Orders', icon: <Package size={14} />, count: filteredPOs.length },
    { id: 'payments', label: 'Payments', icon: <CreditCard size={14} />, count: filteredPayments.length },
    { id: 'shipments', label: 'Shipments', icon: <Truck size={14} />, count: filteredShipments.length },
    { id: 'snapshot', label: 'Stock Snapshot', icon: <BarChart3 size={14} />, count: snapshotRows.length },
  ];

  return (
    <div className="space-y-6">
      {/* ─── HEADER ─── */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-heading">Supply Chain</h1>
          <p className="text-xs text-muted mt-0.5">Purchase orders, payments, and shipments overview</p>
        </div>
      </div>

      {/* ─── SUMMARY CARDS ─── */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <SummaryCard
          label="Unpaid Manufacturer"
          value={summaryTotals.mfg}
          icon={<Package size={18} />}
          color="#ef4444"
          detail={`${allPos.filter(p => p.unpaid_manufacturer > 0.01).length} open POs`}
        />
        <SummaryCard
          label="Unpaid Shipment"
          value={summaryTotals.ship}
          icon={<Truck size={18} />}
          color="#f97316"
          detail={`${allShipments.filter(s => s.unpaid_to_shipment > 0.01).length} unpaid shipments`}
        />
        <SummaryCard
          label="Other Unpaid"
          value={summaryTotals.other}
          icon={<CreditCard size={18} />}
          color="#a855f7"
          detail="Certifications, sampling, etc."
        />
        <SummaryCard
          label="Total Outstanding"
          value={summaryTotals.total}
          icon={<Package size={18} />}
          color="#3b82f6"
        />
      </div>

      {/* ─── Per-product Breakdown ─── */}
      <ProductBreakdown pos={allPos} />

      {/* ─── TAB BAR + CONTROLS ─── */}
      <div className="flex flex-col gap-3">
        <div className="flex items-center gap-1 border-b border-border">
          {tabs.map(t => (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`flex items-center gap-1.5 px-4 py-2.5 text-xs font-semibold transition-all border-b-2 -mb-px ${
                tab === t.id
                  ? 'text-blue-400 border-blue-400'
                  : 'text-muted border-transparent hover:text-subtle hover:border-border'
              }`}
            >
              {t.icon}
              {t.label}
              <span className={`ml-1 px-1.5 py-0.5 rounded-full text-[10px] ${
                tab === t.id ? 'bg-blue-500/20 text-blue-400' : 'bg-surface text-faint'
              }`}>
                {t.count}
              </span>
            </button>
          ))}
          <div className="flex-1" />
          {/* Open filter toggle (not for snapshot tab) */}
          {tab !== 'snapshot' && (
            <label className="flex items-center gap-1.5 text-xs text-muted cursor-pointer mr-2 select-none">
              <Filter size={12} />
              <input
                type="checkbox"
                checked={showOpenOnly}
                onChange={e => setShowOpenOnly(e.target.checked)}
                className="accent-blue-500"
              />
              Open only
            </label>
          )}
          {/* Zero balance toggle (only for snapshot tab) */}
          {tab === 'snapshot' && (
            <label className="flex items-center gap-1.5 text-xs text-muted cursor-pointer mr-2 select-none">
              <Filter size={12} />
              <input
                type="checkbox"
                checked={showZeroBalances}
                onChange={e => setShowZeroBalances(e.target.checked)}
                className="accent-blue-500"
              />
              Show zero balances
            </label>
          )}
        </div>

        {/* Tab-specific date filter */}
        <div className="flex items-center gap-4">
          {tab === 'pos' && (
            <DateFilter label="Order Date" from={poDateFrom} to={poDateTo}
              onChange={(f, t) => { setPODateFrom(f); setPODateTo(t); }} />
          )}
          {tab === 'payments' && (
            <div className="flex items-center gap-3">
              <select
                value={payYear}
                onChange={e => setPayYear(e.target.value)}
                className="bg-surface border border-border rounded px-2 py-1 text-subtle text-xs focus:outline-none focus:ring-1 focus:ring-blue-500/50 cursor-pointer hover:border-blue-500/50 transition-colors"
                title="Filter by Year"
              >
                <option value="All">All Years</option>
                {paymentYears.map(y => (
                  <option key={y} value={y}>{y}</option>
                ))}
              </select>
              <DateFilter label="Payment Date" from={payDateFrom} to={payDateTo}
                onChange={(f, t) => { setPayDateFrom(f); setPayDateTo(t); }} />
            </div>
          )}
          {tab === 'shipments' && (
            <DateFilter label="Shipment Date" from={shipDateFrom} to={shipDateTo}
              onChange={(f, t) => { setShipDateFrom(f); setShipDateTo(t); }} />
          )}
          {tab === 'snapshot' && (
            <div className="flex items-center gap-2 text-xs">
              <span className="text-faint font-medium">Snapshot Date:</span>
              <input
                type="date"
                value={snapshotDate}
                onChange={e => setSnapshotDate(e.target.value)}
                className="bg-surface border border-border rounded px-2 py-1 text-subtle text-xs focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              />
            </div>
          )}
          <div className="flex-1" />
          <button
            onClick={handleExport}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-surface border border-border rounded-md text-xs font-medium text-subtle hover:text-heading hover:border-blue-500/50 transition-colors"
          >
            <Download size={14} />
            Export CSV
          </button>
        </div>
      </div>

      {/* ─── TAB CONTENT ─── */}
      {tab === 'pos' && (() => {
        const totalCost = filteredPOs.reduce((s, r) => s + r.total_amount, 0);
        const totalPaid = filteredPOs.reduce((s, r) => s + r.total_paid, 0);
        const totalRemaining = filteredPOs.reduce((s, r) => s + Math.max(r.unpaid_manufacturer, 0), 0);
        return (
          <>
            <HorizontalScroller items={[
              { label: 'Cost', value: fmtFull$(totalCost) },
              { label: 'Paid', value: fmtFull$(totalPaid), color: 'var(--color-emerald, #34d399)' },
              { label: 'Remaining', value: fmtFull$(totalRemaining), color: totalRemaining > 0 ? 'var(--color-red, #f87171)' : 'var(--color-emerald, #34d399)' },
            ]} />
            <div className="rounded-xl border border-border overflow-x-auto">
              <POTable rows={filteredPOs} sort={poSort} onSort={toggleSort(setPOSort)} allPayments={allPayments} allShipments={allShipments} />
            </div>
          </>
        );
      })()}
      {tab === 'payments' && (() => {
        return (
          <div className="rounded-xl border border-border overflow-x-auto">
            <PaymentsTable rows={filteredPayments} allPos={allPos} sort={paySort} onSort={toggleSort(setPaySort)} />
          </div>
        );
      })()}
      {tab === 'shipments' && (() => {
        const totalShipCost = filteredShipments.reduce((s, r) => s + r.cost_shipped, 0);
        const totalShipPaid = filteredShipments.reduce((s, r) => s + Math.max(r.cost_shipped - r.unpaid_to_shipment, 0), 0);
        const totalShipUnpaid = filteredShipments.reduce((s, r) => s + Math.max(r.unpaid_to_shipment, 0), 0);
        return (
          <>
            <HorizontalScroller items={[
              { label: 'Cost', value: fmtFull$(totalShipCost) },
              { label: 'Paid', value: fmtFull$(totalShipPaid), color: 'var(--color-emerald, #34d399)' },
              { label: 'Remaining', value: fmtFull$(totalShipUnpaid), color: totalShipUnpaid > 0 ? 'var(--color-orange, #fb923c)' : 'var(--color-emerald, #34d399)' },
            ]} />
            <div className="rounded-xl border border-border overflow-x-auto">
              <ShipmentsTable rows={filteredShipments} sort={shipSort} onSort={toggleSort(setShipSort)} />
            </div>
          </>
        );
      })()}
      {tab === 'snapshot' && (() => {
        const totalQty = filteredSnapshot.reduce((s, r) => s + r.quantity_balance, 0);
        const totalValue = filteredSnapshot.reduce((s, r) => s + r.stock_value, 0);
        const totalPaid = filteredSnapshot.reduce((s, r) => s + r.paid_amount, 0);
        const byType = filteredSnapshot.reduce<Record<string, number>>((acc, r) => {
          acc[r.source_type] = (acc[r.source_type] || 0) + r.quantity_balance;
          return acc;
        }, {});
        const scrollerItems = [
          { label: 'Total Units', value: totalQty.toLocaleString() },
          { label: 'Stock Value', value: fmtFull$(totalValue), color: 'var(--color-blue, #3b82f6)' },
          { label: 'Total Paid', value: fmtFull$(totalPaid), color: 'var(--color-emerald, #34d399)' },
          ...Object.entries(byType).sort(([, a], [, b]) => b - a).map(([type, qty]) => ({
            label: type,
            value: qty.toLocaleString(),
            sub: `${((qty / totalQty) * 100).toFixed(0)}% of stock`,
          })),
        ];
        return (
          <>
            <HorizontalScroller items={scrollerItems} />
            <div className="flex items-center gap-2 mb-4">
              <span className="text-sm font-medium text-muted">Group by:</span>
              <div className="flex items-center bg-black/5 p-0.5 rounded-lg">
                <button
                  onClick={() => setSnapshotGroup('source')}
                  className={`px-3 py-1.5 text-xs font-semibold rounded-md transition-colors ${snapshotGroup === 'source' ? 'bg-white text-black shadow-sm' : 'text-muted hover:text-black'}`}
                >
                  Available In
                </button>
                <button
                  onClick={() => setSnapshotGroup('product')}
                  className={`px-3 py-1.5 text-xs font-semibold rounded-md transition-colors ${snapshotGroup === 'product' ? 'bg-white text-black shadow-sm' : 'text-muted hover:text-black'}`}
                >
                  Family + Product
                </button>
              </div>
            </div>
            <div className="rounded-xl border border-border overflow-x-auto">
              <StockSnapshotTable 
                rows={filteredSnapshot} 
                loading={snapshotLoading} 
                sort={snapSort} 
                onSort={toggleSort(setSnapSort)} 
                groupBy={snapshotGroup} 
              />
            </div>
          </>
        );
      })()}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════
 * INLINE READY QUANTITY CELL
 * ═══════════════════════════════════════════════════════════════ */
function InlineReadyCell({ poId, productId, initialQuantity, maxQuantity, isEditable }: { poId: string, productId: string, initialQuantity: number, maxQuantity: number, isEditable: boolean }) {
  const [isEditing, setIsEditing] = useState(false);
  const [val, setVal] = useState(initialQuantity.toString());
  const [saving, setSaving] = useState(false);
  const [currentVal, setCurrentVal] = useState(initialQuantity);

  const handleSave = async () => {
    setSaving(true);
    try {
      // If productId is a comma-separated list, just take the first one (fallback)
      const firstId = productId ? productId.split(',')[0].trim() : '';
      const parsedProductId = firstId || null;
      
      const res = await fetch('/api/po/update_line', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ po_id: poId, product_id: parsedProductId, ready_quantity: Number(val) })
      });
      const result = await res.json();
      if (result.error) throw new Error(result.error);
      
      setCurrentVal(Number(val));
      setIsEditing(false);
    } catch (e: any) {
      alert(e.message || 'Failed to save changes');
    } finally {
      setSaving(false);
    }
  };

  if (!isEditing) {
    return (
      <div 
        className={`group flex items-center justify-end min-w-[40px] min-h-[24px] rounded px-1 -mx-1 transition-colors ${isEditable ? 'cursor-pointer hover:bg-white/5' : ''}`} 
        onClick={() => { if (isEditable) { setIsEditing(true); setVal(currentVal.toString()); } }}
        title={isEditable ? "Click to edit ready quantity" : "Cannot edit: 'Ready By' date is not in the future"}
      >
        <span className={currentVal > 0 ? (currentVal >= maxQuantity ? 'text-emerald-400 font-semibold' : 'text-blue-400') : (isEditable ? 'text-muted group-hover:text-subtle' : 'text-muted')}>
          {currentVal.toLocaleString() || 0}
        </span>
      </div>
    );
  }

  return (
    <div className="flex items-center justify-end gap-1">
      <input 
        type="number" 
        value={val}
        onChange={e => setVal(e.target.value)}
        className="w-16 bg-black/40 border border-border rounded px-1.5 py-0.5 text-xs text-right focus:outline-none focus:border-blue-500 font-mono"
        autoFocus
        onKeyDown={e => {
          if (e.key === 'Enter') handleSave();
          if (e.key === 'Escape') setIsEditing(false);
        }}
        disabled={saving}
      />
      {saving ? (
        <div className="w-3 h-3 border-2 border-blue-500 border-t-transparent rounded-full animate-spin mx-1" />
      ) : (
        <>
          <button onClick={handleSave} className="text-emerald-400 hover:text-emerald-300 p-0.5 bg-surface rounded" title="Save">
            <Check size={14} />
          </button>
          <button onClick={() => setIsEditing(false)} className="text-muted hover:text-red-400 p-0.5 bg-surface rounded" title="Cancel">
            <X size={14} />
          </button>
        </>
      )}
    </div>
  );
}

function POTable({ rows, sort, onSort, allPayments, allShipments }: {
  rows: SupplyPORow[];
  sort: { field: string; dir: SortDir };
  onSort: (field: string) => void;
  allPayments: SupplyPaymentRow[];
  allShipments: SupplyShipmentRow[];
}) {
  const [selectedPO, setSelectedPO] = useState<SupplyPORow | null>(null);

  if (rows.length === 0) return <div className="p-8 text-center text-muted text-sm">No purchase orders match filters</div>;
  return (
    <>
      <table className="w-full text-sm">
      <thead>
        <tr className="border-b border-border bg-surface/50">
          <SortHeader label="Date" field="order_date" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Ready By" field="expected_ready_date" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="PO ID" field="purchase_order_id" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="left" />
          <SortHeader label="Manufacturer" field="manufacturer_name" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="left" />
          <SortHeader label="Product" field="product_name" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="left" />
          <SortHeader label="Qty" field="quantity" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Remain" field="remaining_to_ship" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Ready" field="ready_quantity" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Shipped" field="total_quantity_shipped" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Cost" field="total_amount" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Paid" field="total_paid" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Unpaid" field="unpaid_manufacturer" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Status" field="payment_status" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="left" />
        </tr>
      </thead>
      <tbody>
        {rows.map(r => {
          const todayStr = new Date().toISOString().slice(0, 10);
          const isReadyFuture = !!r.expected_ready_date && r.expected_ready_date > todayStr;
          
          return (
          <Fragment key={r.purchase_order_id}>
          <tr className="border-b border-border/50 hover:bg-white/[.02] transition-colors">
            <td className="px-4 py-2.5 text-xs text-muted whitespace-nowrap text-right">{fmtDate(r.order_date)}</td>
            <td className="px-4 py-2.5 text-xs text-muted whitespace-nowrap text-right">{fmtDate(r.expected_ready_date)}</td>
            <td className="px-4 py-2.5 text-xs font-mono whitespace-nowrap">
              <div className="flex items-center gap-1.5">
                <button
                  onClick={() => setSelectedPO(r)}
                  className="text-blue-400 hover:text-blue-300 hover:underline underline-offset-2 transition-colors flex items-center gap-1 cursor-pointer"
                  title={`View details: ${r.purchase_order_id}`}
                >
                  <Eye size={12} className="shrink-0 opacity-60" />
                  <span className="truncate max-w-[200px]">{r.purchase_order_id}</span>
                </button>
                <CopyButton text={r.purchase_order_id} />
              </div>
            </td>
            <td className="px-4 py-2.5 text-subtle text-xs">{r.manufacturer_name}</td>
            <td className="px-4 py-2.5 text-subtle text-xs font-medium max-w-[200px] truncate" title={r.product_name}>{r.product_name}</td>
            <td className="px-4 py-2.5 text-right text-subtle font-mono text-xs">{r.quantity.toLocaleString()}</td>
            <td className="px-4 py-2.5 text-right font-mono text-xs">
              <span className={r.remaining_to_ship > 0 ? 'text-amber-400 font-medium' : 'text-muted'}>
                {r.remaining_to_ship.toLocaleString()}
              </span>
            </td>
            <td className="px-4 py-2.5 text-right font-mono text-xs group relative">
              <InlineReadyCell 
                poId={r.purchase_order_id}
                productId={r.product_id}
                initialQuantity={r.ready_quantity || 0}
                maxQuantity={r.quantity}
                isEditable={isReadyFuture}
              />
            </td>
            <td className="px-4 py-2.5 text-right text-subtle font-mono text-xs">{r.total_quantity_shipped?.toLocaleString() || 0}</td>
            <td className="px-4 py-2.5 text-right text-subtle font-mono text-xs">{fmtFull$(r.total_amount)}</td>
            <td className="px-4 py-2.5 text-right text-emerald-400 font-mono text-xs">{fmtFull$(r.total_paid)}</td>
            <td className="px-4 py-2.5 text-right font-mono text-xs">
              <span className={r.unpaid_manufacturer > 0.01 ? 'text-red-400 font-semibold' : 'text-emerald-400'}>
                {fmtFull$(Math.max(r.unpaid_manufacturer, 0))}
              </span>
            </td>
            <td className="px-4 py-2.5"><StatusBadge status={r.payment_status} /></td>
          </tr>
          </Fragment>
        )})}
      </tbody>
      <tfoot>
        <tr className="border-t border-border bg-surface/30">
          <td colSpan={5} className="px-4 py-2.5 text-xs font-semibold text-faint uppercase">{rows.length} POs</td>
          <td className="px-4 py-2.5 text-right text-heading font-semibold font-mono text-xs">
            {rows.reduce((s, r) => s + r.quantity, 0).toLocaleString()}
          </td>
          <td className="px-4 py-2.5 text-right text-amber-400 font-semibold font-mono text-xs">
            {rows.reduce((s, r) => s + r.remaining_to_ship, 0).toLocaleString()}
          </td>
          <td className="px-4 py-2.5 text-right text-heading font-semibold font-mono text-xs pr-8">
            {rows.reduce((s, r) => s + (r.ready_quantity || 0), 0).toLocaleString()}
          </td>
          <td className="px-4 py-2.5 text-right text-heading font-semibold font-mono text-xs">
            {rows.reduce((s, r) => s + (r.total_quantity_shipped || 0), 0).toLocaleString()}
          </td>
          <td className="px-4 py-2.5 text-right text-heading font-semibold font-mono text-xs">
            {fmtFull$(rows.reduce((s, r) => s + r.total_amount, 0))}
          </td>
          <td className="px-4 py-2.5 text-right text-emerald-400 font-semibold font-mono text-xs">
            {fmtFull$(rows.reduce((s, r) => s + r.total_paid, 0))}
          </td>
          <td className="px-4 py-2.5 text-right text-red-400 font-semibold font-mono text-xs">
            {fmtFull$(rows.reduce((s, r) => s + Math.max(r.unpaid_manufacturer, 0), 0))}
          </td>
          <td></td>
        </tr>
      </tfoot>
    </table>
    {selectedPO && (
       <PODetailsModal
         po={selectedPO}
         allPORows={rows}
         payments={allPayments}
         shipments={allShipments}
         onClose={() => setSelectedPO(null)}
       />
     )}
    </>
  );
}

/* ═══════════════════════════════════════════════════════════════
 * PAYMENTS TABLE
 * ═══════════════════════════════════════════════════════════════ */
function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      onClick={() => {
        navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }}
      className="shrink-0 text-muted hover:text-heading transition-colors focus:outline-none"
      title="Copy file name"
    >
      {copied ? <Check size={14} className="text-emerald-400" /> : <Copy size={13} />}
    </button>
  );
}

function PaymentsTable({ rows, allPos, sort, onSort }: { rows: SupplyPaymentRow[]; allPos: SupplyPORow[]; sort: { field: string; dir: SortDir }; onSort: (field: string) => void }) {
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  if (rows.length === 0) return <div className="p-8 text-center text-muted text-sm">No payments match filters</div>;

  const toggleGroup = (paymentId: string) => {
    setCollapsed(prev => {
      const next = new Set(prev);
      if (next.has(paymentId)) next.delete(paymentId); else next.add(paymentId);
      return next;
    });
  };

  // Each payment is a top-level row; linked POs are children
  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="border-b border-border bg-surface/50">
          <SortHeader label="Date" field="payment_date" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <th className="text-left px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Vendor</th>
          <th className="text-left px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Payment ID</th>
          <SortHeader label="Amount" field="payment_amount" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Bank Fee" field="bank_fee" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Total" field="total_amount" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <th className="text-left px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Currency</th>
          <th className="text-left px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Method</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r, i) => {
          // Parse linked PO IDs (may be comma-separated)
          const linkedPoIds = r.purchase_order_id
            ? r.purchase_order_id.split(',').map(s => s.trim()).filter(Boolean)
            : [];
          const linkedPos = linkedPoIds
            .map(poId => allPos.find(p => p.purchase_order_id === poId))
            .filter(Boolean) as SupplyPORow[];
          const hasLinkedPOs = linkedPos.length > 0;
          const payKey = r.payment_id || `pay_${i}`;
          const isOpen = !collapsed.has(payKey);

          return (
            <Fragment key={payKey}>
              {/* ── Payment Row (Parent) ── */}
              <tr
                className={`border-b border-border/50 transition-colors ${hasLinkedPOs ? 'cursor-pointer hover:bg-surface/80' : 'hover:bg-white/[.03]'}`}
                onClick={hasLinkedPOs ? () => toggleGroup(payKey) : undefined}
              >
                <td className="px-4 py-2.5 text-xs text-muted whitespace-nowrap text-right">
                  <div className="flex items-center gap-2 justify-end">
                    {hasLinkedPOs && (
                      <span className="text-muted shrink-0 transition-transform" style={{ transform: isOpen ? 'rotate(0deg)' : 'rotate(-90deg)' }}>
                        <ChevronDown size={12} />
                      </span>
                    )}
                    {fmtDate(r.payment_date)}
                  </div>
                </td>
                <td className="px-4 py-2.5 text-subtle text-xs">{r.vendor_name}</td>
                <td className="px-4 py-2.5 text-xs font-mono whitespace-nowrap max-w-[280px]">
                  <div className="flex items-center gap-2">
                    <span className="truncate flex-1 min-w-0 text-heading font-medium" title={r.payment_id}>{r.payment_id || '—'}</span>
                    {r.payment_id && <CopyButton text={r.payment_id} />}
                  </div>
                </td>
                <td className={`px-4 py-2.5 text-right font-mono text-xs font-semibold ${r.payment_amount < 0 ? 'text-red-400' : 'text-heading'}`}>{fmtFull$(r.payment_amount)}</td>
                <td className="px-4 py-2.5 text-right text-amber-400 font-mono text-xs">{r.bank_fee > 0 ? fmtFull$(r.bank_fee) : '—'}</td>
                <td className="px-4 py-2.5 text-right text-blue-400 font-mono text-xs font-semibold">{fmtFull$(r.total_amount)}</td>
                <td className="px-4 py-2.5 text-xs text-muted">{r.currency}</td>
                <td className="px-4 py-2.5 text-xs text-muted">{r.payment_method || '—'}</td>
              </tr>
              {/* ── Linked PO Lines (Children) ── */}
              {hasLinkedPOs && isOpen && linkedPos.map(po => (
                <tr key={`${payKey}_${po.purchase_order_id}`} className="border-b border-border/20 hover:bg-white/[.02] transition-colors">
                  <td colSpan={3} className="px-4 py-1.5 pl-10 border-l-2 border-blue-500/20">
                    <div className="flex items-center gap-3 text-xs">
                      <Package size={12} className="text-muted shrink-0" />
                      <span className="font-mono text-subtle font-medium truncate max-w-[220px]" title={po.purchase_order_id}>{po.purchase_order_id}</span>
                      <span className="text-faint">·</span>
                      <span className="text-muted truncate max-w-[150px]" title={po.product_name}>{po.product_name}</span>
                    </div>
                  </td>
                  <td className="px-4 py-1.5 text-right font-mono text-[11px]">
                    <div className="flex items-center justify-end gap-1.5">
                      <span className="text-faint text-[10px]">Cost</span>
                      <span className="text-subtle">{fmtFull$(po.total_amount)}</span>
                    </div>
                  </td>
                  <td className="px-4 py-1.5 text-right font-mono text-[11px]">
                    <div className="flex items-center justify-end gap-1.5">
                      <span className="text-faint text-[10px]">Paid</span>
                      <span className="text-emerald-400">{fmtFull$(po.total_paid)}</span>
                    </div>
                  </td>
                  <td className="px-4 py-1.5 text-right font-mono text-[11px]">
                    <div className="flex items-center justify-end gap-1.5">
                      <span className="text-faint text-[10px]">Rem</span>
                      <span className={Math.max(po.unpaid_manufacturer, 0) > 0.01 ? 'text-red-400' : 'text-emerald-400'}>{fmtFull$(Math.max(po.unpaid_manufacturer, 0))}</span>
                    </div>
                  </td>
                  <td colSpan={2} className="px-4 py-1.5">
                    <StatusBadge status={po.payment_status} />
                  </td>
                </tr>
              ))}
            </Fragment>
          );
        })}
      </tbody>
      <tfoot>
        <tr className="border-t-2 border-border bg-surface/40">
          <td colSpan={3} className="px-4 py-3 text-xs font-semibold text-faint uppercase">
            {rows.length} Payments
          </td>
          <td className="px-4 py-3 text-right text-heading font-bold font-mono text-xs">
            {fmtFull$(rows.reduce((s, r) => s + r.payment_amount, 0))}
          </td>
          <td className="px-4 py-3 text-right text-amber-400 font-bold font-mono text-xs">
            {fmtFull$(rows.reduce((s, r) => s + r.bank_fee, 0))}
          </td>
          <td className="px-4 py-3 text-right text-blue-400 font-bold font-mono text-xs">
            {fmtFull$(rows.reduce((s, r) => s + r.total_amount, 0))}
          </td>
          <td></td>
          <td></td>
        </tr>
      </tfoot>
    </table>
  );
}

/* ═══════════════════════════════════════════════════════════════
 * SHIPMENTS TABLE
 * ═══════════════════════════════════════════════════════════════ */
function ShipmentsTable({ rows, sort, onSort }: { rows: SupplyShipmentRow[]; sort: { field: string; dir: SortDir }; onSort: (field: string) => void }) {
  if (rows.length === 0) return <div className="p-8 text-center text-muted text-sm">No shipments match filters</div>;
  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="border-b border-border bg-surface/50">
          <SortHeader label="Ship Date" field="shipment_date" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Arrival" field="estimated_arrival_date" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <th className="text-left px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Products</th>
          <th className="text-left px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Type</th>
          <SortHeader label="Qty" field="total_quantity_shipped" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Cost" field="cost_shipped" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <SortHeader label="Unpaid" field="unpaid_to_shipment" sortField={sort.field} sortDir={sort.dir} onSort={onSort} />
          <th className="text-left px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider">Status</th>
        </tr>
      </thead>
      <tbody>
        {rows.map(r => (
          <tr key={r.shipment_id} className="border-b border-border/50 hover:bg-white/[.02] transition-colors">
            <td className="px-4 py-2.5 text-xs text-muted whitespace-nowrap text-right">{fmtDate(r.shipment_date)}</td>
            <td className="px-4 py-2.5 text-xs text-muted whitespace-nowrap text-right">{r.estimated_arrival_date ? fmtDate(r.estimated_arrival_date) : '—'}</td>
            <td className="px-4 py-2.5 text-subtle text-xs font-medium max-w-[250px] truncate" title={r.products_list}>{r.products_list || '—'}</td>
            <td className="px-4 py-2.5 text-xs text-muted">{r.shipment_type || '—'}</td>
            <td className="px-4 py-2.5 text-right text-subtle font-mono text-xs">{r.total_quantity_shipped.toLocaleString()}</td>
            <td className="px-4 py-2.5 text-right text-subtle font-mono text-xs">{r.cost_shipped > 0 ? fmtFull$(r.cost_shipped) : '—'}</td>
            <td className="px-4 py-2.5 text-right font-mono text-xs">
              <span className={r.unpaid_to_shipment > 0.01 ? 'text-orange-400 font-semibold' : 'text-emerald-400'}>
                {fmtFull$(Math.max(r.unpaid_to_shipment, 0))}
              </span>
            </td>
            <td className="px-4 py-2.5"><ShipmentStatusBadge status={r.shipment_status} /></td>
          </tr>
        ))}
      </tbody>
      <tfoot>
        <tr className="border-t border-border bg-surface/30">
          <td colSpan={4} className="px-4 py-2.5 text-xs font-semibold text-faint uppercase">{rows.length} Shipments</td>
          <td className="px-4 py-2.5 text-right text-heading font-semibold font-mono text-xs">
            {rows.reduce((s, r) => s + r.total_quantity_shipped, 0).toLocaleString()}
          </td>
          <td className="px-4 py-2.5 text-right text-heading font-semibold font-mono text-xs">
            {fmtFull$(rows.reduce((s, r) => s + r.cost_shipped, 0))}
          </td>
          <td className="px-4 py-2.5 text-right text-orange-400 font-semibold font-mono text-xs">
            {fmtFull$(rows.reduce((s, r) => s + Math.max(r.unpaid_to_shipment, 0), 0))}
          </td>
          <td></td>
        </tr>
      </tfoot>
    </table>
  );
}

/* ═══════════════════════════════════════════════════════════════
 * STOCK SNAPSHOT TABLE
 * ═══════════════════════════════════════════════════════════════ */
const SOURCE_COLORS: Record<string, string> = {
  FBA: 'bg-blue-500/15 text-blue-400',
  AWD: 'bg-purple-500/15 text-purple-400',
  'In Transit': 'bg-orange-500/15 text-orange-400',
  'In Production': 'bg-orange-600/15 text-orange-500',
  'MFR Ready': 'bg-emerald-500/15 text-emerald-400',
};

function StockSnapshotTable({ rows, loading, sort, onSort, groupBy }: {
  rows: StockSnapshotRow[];
  loading: boolean;
  sort: { field: string; dir: SortDir };
  onSort: (field: string) => void;
  groupBy: 'source' | 'product';
}) {
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());

  const toggleGroup = (key: string) => {
    setCollapsed(prev => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  // Calculate grouped rows (MUST BE BEFORE EARLY RETURNS)
  const groupedData = useMemo(() => {
    const groups = new Map<string, { key: string; rows: StockSnapshotRow[]; qty: number; value: number; paid: number; source_type: string }>();
    for (const r of rows) {
      const key = groupBy === 'source' ? r.source_type : `${r.product_family} / ${r.product_short_name}`;
      if (!groups.has(key)) {
        groups.set(key, { key, rows: [], qty: 0, value: 0, paid: 0, source_type: r.source_type });
      }
      const g = groups.get(key)!;
      g.rows.push(r);
      g.qty += r.quantity_balance;
      g.value += r.stock_value;
      g.paid += r.paid_amount;
    }
    
    // Sort groups
    const { field, dir } = sort;
    const sortedGroups = Array.from(groups.values()).sort((a, b) => {
      if (field === 'quantity_balance') return dir === 'asc' ? a.qty - b.qty : b.qty - a.qty;
      if (field === 'stock_value') return dir === 'asc' ? a.value - b.value : b.value - a.value;
      return dir === 'asc' ? a.key.localeCompare(b.key) : b.key.localeCompare(a.key);
    });
    
    // Sort rows inside each group
    for (const g of sortedGroups) {
      g.rows.sort((a, b) => {
        const av = (a as Record<string, any>)[field];
        const bv = (b as Record<string, any>)[field];
        if (typeof av === 'number' && typeof bv === 'number') return dir === 'asc' ? av - bv : bv - av;
        return dir === 'asc' ? String(av ?? '').localeCompare(String(bv ?? '')) : String(bv ?? '').localeCompare(String(av ?? ''));
      });
    }
    
    return sortedGroups;
  }, [rows, sort, groupBy]);

  const totalQty = groupedData.reduce((s, g) => s + g.qty, 0);
  const totalValue = groupedData.reduce((s, g) => s + g.value, 0);
  const totalPaid = groupedData.reduce((s, g) => s + g.paid, 0);

  if (loading) {
    return (
      <div className="p-12 text-center">
        <div className="inline-block w-5 h-5 border-2 border-blue-400 border-t-transparent rounded-full animate-spin mb-2" />
        <p className="text-muted text-sm">Loading snapshot…</p>
      </div>
    );
  }
  if (rows.length === 0) {
    return <div className="p-8 text-center text-muted text-sm">No inventory data for this date</div>;
  }

  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="border-b border-border bg-surface/50 text-left">
          <SortHeader label="Available In" field="source_type" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="left" />
          <SortHeader label="Product Family" field="product_family" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="left" />
          <SortHeader label="Product" field="product_short_name" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="left" />
          <SortHeader label="Qty" field="quantity_balance" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="right" />
          <SortHeader label="MFR Cost/unit" field="cost_of_goods" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="right" />
          <SortHeader label="Ship Cost/unit" field="shipping_cost" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="right" />
          <SortHeader label="Stock Value" field="stock_value" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="right" />
          <SortHeader label="Total Paid" field="paid_amount" sortField={sort.field} sortDir={sort.dir} onSort={onSort} align="right" />
        </tr>
      </thead>
      <tbody>
        {groupedData.map((g, i) => {
          const isCollapsed = collapsed.has(g.key);
          const badgeClass = groupBy === 'source' ? (SOURCE_COLORS[g.source_type] ?? 'bg-white/10 text-muted') : 'bg-white/10 text-muted';
          
          return (
            <Fragment key={i}>
              {/* Group Header Row */}
              <tr 
                className="bg-surface/80 border-b border-border cursor-pointer hover:bg-surface transition-colors select-none"
                onClick={() => toggleGroup(g.key)}
              >
                <td colSpan={7} className="px-4 py-2.5">
                  <div className="flex items-center gap-3">
                    <span className="text-muted shrink-0 transition-transform" style={{ transform: isCollapsed ? 'rotate(-90deg)' : 'rotate(0deg)' }}>
                      <ChevronDown size={14} />
                    </span>
                    {groupBy === 'source' ? (
                      <span className={`inline-flex px-2 py-0.5 rounded-full text-[10px] font-semibold uppercase tracking-wider ${badgeClass}`}>
                        {g.key}
                      </span>
                    ) : (
                      <span className="font-mono text-xs font-semibold text-heading truncate">{g.key}</span>
                    )}
                    <span className="shrink-0 px-1.5 py-0.5 rounded-full bg-blue-500/15 text-blue-400 text-[10px] font-semibold leading-none">
                      {g.rows.length} {g.rows.length === 1 ? 'item' : 'items'}
                    </span>
                    
                    <div className="ml-auto flex items-center justify-end gap-5 font-mono text-xs">
                      <div className="flex items-center gap-1.5">
                        <span className="text-faint text-[10px] uppercase tracking-wider">Qty</span>
                        <span className="text-heading font-semibold">{g.qty.toLocaleString()}</span>
                      </div>
                      <div className="flex items-center gap-1.5">
                        <span className="text-faint text-[10px] uppercase tracking-wider">Value</span>
                        <span className="text-blue-400 font-semibold">{fmtFull$(g.value)}</span>
                      </div>
                      {g.paid > 0 && (
                      <div className="flex items-center gap-1.5">
                        <span className="text-faint text-[10px] uppercase tracking-wider">Paid</span>
                        <span className="text-emerald-400 font-semibold">{fmtFull$(g.paid)}</span>
                      </div>
                      )}
                    </div>
                  </div>
                </td>
              </tr>
              
              {/* Child Rows */}
              {!isCollapsed && g.rows.map((r, j) => (
                <tr key={`${i}-${j}`} className="border-b border-border/40 bg-white/[.01] hover:bg-white/[.03] transition-colors">
                  <td className="px-4 py-2 pl-10">
                    <span className={`inline-flex px-1.5 py-0.5 rounded-full text-[9px] font-semibold uppercase tracking-wider ${SOURCE_COLORS[r.source_type] ?? 'bg-white/10 text-muted'}`}>
                      {r.source_type}
                    </span>
                  </td>
                  <td className="px-4 py-2 text-subtle text-xs font-medium">{r.product_family}</td>
                  <td className="px-4 py-2 text-subtle text-xs font-medium">{r.product_short_name}</td>
                  <td className="px-4 py-2 text-right text-heading font-mono text-xs font-semibold">{r.quantity_balance.toLocaleString()}</td>
                  <td className="px-4 py-2 text-right text-subtle font-mono text-xs">
                    {r.cost_of_goods != null ? `$${r.cost_of_goods.toFixed(2)}` : '—'}
                  </td>
                  <td className="px-4 py-2 text-right text-subtle font-mono text-xs">
                    {r.shipping_cost != null ? `$${r.shipping_cost.toFixed(2)}` : '—'}
                  </td>
                  <td className="px-4 py-2 text-right text-blue-400 font-mono text-xs font-semibold">
                    {fmtFull$(r.stock_value)}
                  </td>
                  <td className="px-4 py-2 text-right font-mono text-xs font-semibold">
                    {r.paid_amount > 0 ? <span className="text-emerald-400">{fmtFull$(r.paid_amount)}</span> : <span className="text-muted">—</span>}
                  </td>
                </tr>
              ))}
            </Fragment>
          );
        })}
      </tbody>
      <tfoot>
        <tr className="border-t-2 border-border bg-surface/40">
          <td colSpan={3} className="px-4 py-2.5 text-xs font-semibold text-faint uppercase">{rows.length} Total Items</td>
          <td className="px-4 py-2.5 text-right text-heading font-bold font-mono text-xs">{totalQty.toLocaleString()}</td>
          <td colSpan={2}></td>
          <td className="px-4 py-2.5 text-right text-blue-400 font-bold font-mono text-xs">{fmtFull$(totalValue)}</td>
          <td className="px-4 py-2.5 text-right text-emerald-400 font-bold font-mono text-xs">{fmtFull$(totalPaid)}</td>
        </tr>
      </tfoot>
    </table>
  );
}
