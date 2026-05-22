import { useState, useEffect } from 'react';
import type { AlertRow } from '../../types';
import { Package, Truck, Settings, X, Loader2, TrendingUp } from 'lucide-react';
import { fmt } from '../../utils';

export function RemediationModal({
  alert,
  onClose,
  onSuccess,
}: {
  alert: AlertRow;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form states
  const payload = alert.action_payload 
    ? (typeof alert.action_payload === 'string' ? JSON.parse(alert.action_payload) : alert.action_payload) 
    : {};
  const isPO = alert.action_type === 'MODAL_CREATE_PO';
  const isShipment = alert.action_type === 'MODAL_CREATE_SHIPMENT';
  const isAwdTarget = alert.action_type === 'MODAL_AWD_TARGET';
  const isAdjustForecast = alert.action_type === 'MODAL_ADJUST_FORECAST';

  // Shared
  const [qty, setQty] = useState<number>(
    isPO ? payload.recommended_qty || 0 : payload.recommended_qty || 0
  );

  // PO specifics
  const [orderDate, setOrderDate] = useState(new Date().toISOString().split('T')[0]);
  const [manufacturer, setManufacturer] = useState(payload.manufacturer || 'Standard Supplier');
  const [currency, setCurrency] = useState('USD');
  const [paymentStatus, setPaymentStatus] = useState('PENDING');
  const [notes, setNotes] = useState('');
  const [totalAmount, setTotalAmount] = useState((payload.recommended_qty || 0) * (payload.unit_cost || 0));
  const [manufacturerOptions, setManufacturerOptions] = useState<string[]>([]);

  useEffect(() => {
    if (isPO) {
      fetch('/api/lov/SUPPLIER')
        .then(res => res.json())
        .then(data => {
          if (Array.isArray(data)) {
            const mfrs = data.filter((v: any) => v.attr1_value === 'Manufacturer').map((v: any) => v.value_id);
            setManufacturerOptions(mfrs);
            if (mfrs.length > 0 && !mfrs.includes(manufacturer) && manufacturer === 'Standard Supplier') {
              setManufacturer(mfrs[0]);
            }
          }
        })
        .catch(console.error);
    }
  }, [isPO]);

  // Shipment specifics
  const [fbaQty, setFbaQty] = useState<number>(payload.recommended_fba_qty || 0);
  const [awdQty, setAwdQty] = useState<number>(payload.recommended_awd_qty || 0);
  const [poId, setPoId] = useState<string>('');
  
  // AWD Target specifics
  const [awdTargetMin, setAwdTargetMin] = useState<number>(
    payload.current_approved_min != null ? payload.current_approved_min : (payload.recommended_awd_target_min || 0)
  );
  const [awdTargetMax, setAwdTargetMax] = useState<number>(
    payload.current_approved_max != null ? payload.current_approved_max : (payload.recommended_awd_target_max || payload.recommended_qty || 0)
  );
  
  // Forecast Adjust specifics
  const [forecastTarget, setForecastTarget] = useState<number>(payload.recommended_qty || 0);

  const handleSubmit = async () => {
    setLoading(true);
    setError(null);
    try {
      if (isPO) {
        // Create PO
        const res = await fetch('/api/po', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            order_date: orderDate,
            manufacturer_name: manufacturer,
            currency: currency,
            payment_status: paymentStatus,
            notes: notes,
            product_lines: [
              {
                asin: payload.asin || alert.product_asin,
                quantity: qty,
                total_amount: totalAmount,
              },
            ],
          }),
        });
        const data = await res.json();
        if (!res.ok || !data.success) throw new Error(data.error || 'Failed to create PO');
      } else if (isShipment) {
        // Create Shipment
        const res = await fetch('/api/shipments', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            ship_date: new Date().toISOString().split('T')[0],
            eta: new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0],
            type: 'Sea',
            status: 'PLANNED',
            route: awdQty > 0 ? 'FCL AWD' : 'LCL',
            lines: [
              ...(fbaQty > 0
                ? [
                    {
                      purchase_order_id: poId || 'UNKNOWN',
                      asin: payload.asin || alert.product_asin,
                      quantity: fbaQty,
                    },
                  ]
                : []),
              ...(awdQty > 0
                ? [
                    {
                      purchase_order_id: poId || 'UNKNOWN',
                      asin: payload.asin || alert.product_asin,
                      quantity: awdQty,
                    },
                  ]
                : []),
            ],
          }),
        });
        const data = await res.json();
        if (!res.ok || !data.success) throw new Error(data.error || 'Failed to create Shipment');
      } else if (isAwdTarget) {
        // Update AWD Target
        const res = await fetch('/api/awd_target', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            asin: payload.asin || alert.product_asin,
            approved_max_units: awdTargetMax,
            approved_min_units: awdTargetMin,
          }),
        });
        const data = await res.json();
        if (!res.ok || !data.success) throw new Error(data.error || 'Failed to update AWD Target');
      } else if (isAdjustForecast) {
        // Adjust Forecast
        const res = await fetch('/api/adjust_forecast', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            asin: payload.asin || alert.product_asin,
            target_qty: forecastTarget,
          }),
        });
        const data = await res.json();
        if (!res.ok || !data.success) throw new Error(data.error || 'Failed to adjust forecast');
      }

      // Mark alert as DONE
      const doneRes = await fetch(`/api/alerts/${alert.id}/done`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ notes: `Auto-remediated via ${alert.action_type}` }),
      });
      if (doneRes.ok) {
        onSuccess();
      } else {
        throw new Error('Action succeeded, but failed to close alert.');
      }
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-[#1C1C1F] border border-border w-full max-w-md rounded-xl shadow-2xl overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-border/50 bg-white/[0.02]">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg ${isPO ? 'bg-purple-500/10 text-purple-400' : isShipment ? 'bg-emerald-500/10 text-emerald-400' : isAdjustForecast ? 'bg-cyan-500/10 text-cyan-400' : 'bg-blue-500/10 text-blue-400'}`}>
              {isPO ? <Package size={18} /> : isShipment ? <Truck size={18} /> : isAdjustForecast ? <TrendingUp size={18} /> : <Settings size={18} />}
            </div>
            <div>
              <h2 className="text-sm font-semibold text-heading">
                {isPO ? 'Create Purchase Order' : isShipment ? 'Create Shipment' : isAwdTarget ? 'Update AWD Target' : isAdjustForecast ? 'Adjust Forecast Override' : 'Remediate Alert'}
              </h2>
              <p className="text-[11px] text-muted truncate max-w-[250px]">{alert.product_name}</p>
            </div>
          </div>
          <button onClick={onClose} className="p-1.5 text-muted hover:text-heading hover:bg-white/5 rounded-md transition-colors">
            <X size={16} />
          </button>
        </div>

        {/* Body */}
        <div className="px-5 py-6 space-y-5">
          {error && (
            <div className="p-3 text-[11px] text-red-400 bg-red-500/10 border border-red-500/20 rounded-md">
              {error}
            </div>
          )}

          {isPO && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">Order Date</label>
                  <input
                    type="date"
                    value={orderDate}
                    onChange={e => setOrderDate(e.target.value)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading focus:outline-none focus:border-blue-500/50"
                  />
                </div>
                <div>
                  <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">Manufacturer</label>
                  <select
                    value={manufacturer}
                    onChange={e => setManufacturer(e.target.value)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading focus:outline-none focus:border-blue-500/50"
                  >
                    {manufacturerOptions.length === 0 ? (
                      <option value={manufacturer}>{manufacturer}</option>
                    ) : (
                      manufacturerOptions.map(mfr => (
                        <option key={mfr} value={mfr}>{mfr}</option>
                      ))
                    )}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">Currency</label>
                  <select
                    value={currency}
                    onChange={e => setCurrency(e.target.value)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading focus:outline-none focus:border-blue-500/50"
                  >
                    <option value="USD">USD ($)</option>
                    <option value="GBP">GBP (£)</option>
                    <option value="EUR">EUR (€)</option>
                    <option value="CAD">CAD ($)</option>
                    <option value="AUD">AUD ($)</option>
                  </select>
                </div>
                <div>
                  <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">Payment Status</label>
                  <select
                    value={paymentStatus}
                    onChange={e => setPaymentStatus(e.target.value)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading focus:outline-none focus:border-blue-500/50"
                  >
                    <option value="PENDING">Pending</option>
                    <option value="PAID">Paid</option>
                  </select>
                </div>
              </div>

              {/* Product Line Area */}
              <div className="p-3 bg-white/[0.02] border border-border rounded-md space-y-3">
                <div className="flex items-center gap-2">
                  <Package size={14} className="text-muted" />
                  <span className="text-sm text-heading font-medium truncate">
                    {payload.product_name || payload.asin || alert.product_name}
                  </span>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-[10px] text-muted mb-1">Quantity</label>
                    <input
                      type="number"
                      value={qty || ''}
                      onChange={e => {
                        const newQty = parseInt(e.target.value) || 0;
                        setQty(newQty);
                        setTotalAmount(parseFloat((newQty * (payload.unit_cost || 0)).toFixed(2)));
                      }}
                      className="w-full bg-black/40 border border-border rounded-md px-3 py-1.5 text-sm text-heading focus:outline-none focus:border-blue-500/50"
                    />
                    <div className="mt-1 text-[10px] text-muted text-right">Rec: {fmt(payload.recommended_qty || alert.suggested_qty)}</div>
                  </div>
                  <div>
                    <label className="block text-[10px] text-muted mb-1">Amount ({currency})</label>
                    <input
                      type="number"
                      value={totalAmount || ''}
                      onChange={e => setTotalAmount(parseFloat(e.target.value) || 0)}
                      className="w-full bg-black/40 border border-border rounded-md px-3 py-1.5 text-sm text-heading focus:outline-none focus:border-blue-500/50"
                    />
                  </div>
                </div>
              </div>

              <div>
                <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">Notes (Optional)</label>
                <textarea
                  value={notes}
                  onChange={e => setNotes(e.target.value)}
                  rows={2}
                  className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading placeholder-muted focus:outline-none focus:border-blue-500/50 resize-none"
                  placeholder="Any additional instructions..."
                />
              </div>
            </div>
          )}

          {isShipment && (
            <>
              <div>
                <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">PO ID Source</label>
                <input
                  type="text"
                  value={poId}
                  onChange={e => setPoId(e.target.value)}
                  placeholder="e.g., PO_20250101_ABC"
                  className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading placeholder-muted focus:outline-none focus:border-emerald-500/50"
                />
                <div className="mt-1 text-[10px] text-muted text-right">At Mfr: {fmt(payload.at_manufacturer || 0)}</div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">FBA Qty</label>
                  <input
                    type="number"
                    value={fbaQty || ''}
                    onChange={e => setFbaQty(parseInt(e.target.value) || 0)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading placeholder-muted focus:outline-none focus:border-emerald-500/50"
                  />
                  <div className="mt-1 text-[10px] text-muted text-right">Rec: {fmt(payload.recommended_fba_qty || alert.suggested_split_fba)}</div>
                </div>
                <div>
                  <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">AWD Qty</label>
                  <input
                    type="number"
                    value={awdQty || ''}
                    onChange={e => setAwdQty(parseInt(e.target.value) || 0)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading placeholder-muted focus:outline-none focus:border-emerald-500/50"
                  />
                  <div className="mt-1 text-[10px] text-muted text-right">Rec: {fmt(payload.recommended_awd_qty || alert.suggested_split_awd)}</div>
                </div>
              </div>
            </>
          )}
          
          {isAwdTarget && (
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">New Approved AWD Min Target</label>
                <input
                  type="number"
                  value={awdTargetMin || ''}
                  onChange={e => setAwdTargetMin(parseInt(e.target.value) || 0)}
                  className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading placeholder-muted focus:outline-none focus:border-blue-500/50"
                />
                <div className="mt-1 text-[10px] text-muted text-right">Rec: {fmt(payload.recommended_awd_target_min || 0)}</div>
              </div>
              <div>
                <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">New Approved AWD Max Target</label>
                <input
                  type="number"
                  value={awdTargetMax || ''}
                  onChange={e => setAwdTargetMax(parseInt(e.target.value) || 0)}
                  className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading placeholder-muted focus:outline-none focus:border-blue-500/50"
                />
                <div className="mt-1 text-[10px] text-muted text-right">Rec: {fmt(payload.recommended_awd_target_max || payload.recommended_qty || 0)}</div>
              </div>
            </div>
          )}

          {isAdjustForecast && (
            <div>
              <label className="block text-[11px] font-medium text-subtle mb-1.5 uppercase tracking-wide">New Forecast Override Qty</label>
              <input
                type="number"
                value={forecastTarget || ''}
                onChange={e => setForecastTarget(parseInt(e.target.value) || 0)}
                className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-heading placeholder-muted focus:outline-none focus:border-cyan-500/50"
              />
              <div className="mt-1 text-[10px] text-muted flex justify-between">
                <span>Current: {fmt(payload.current_qty || 0)}</span>
                <span>System Rec: {fmt(payload.recommended_qty || 0)}</span>
              </div>
            </div>
          )}

        </div>

        {/* Footer */}
        <div className="px-5 py-4 bg-white/[0.02] border-t border-border/50 flex justify-end gap-3">
          <button
            onClick={onClose}
            className="px-4 py-2 text-xs font-medium text-subtle hover:text-heading bg-transparent border border-border hover:bg-white/5 rounded-md transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={loading}
            className={`flex items-center gap-2 px-4 py-2 text-xs font-medium text-white rounded-md transition-colors ${
              isPO ? 'bg-purple-600 hover:bg-purple-500' : 
              isShipment ? 'bg-emerald-600 hover:bg-emerald-500' :
              isAdjustForecast ? 'bg-cyan-600 hover:bg-cyan-500' :
              'bg-blue-600 hover:bg-blue-500'
            } disabled:opacity-50`}
          >
            {loading && <Loader2 size={14} className="animate-spin" />}
            Confirm
          </button>
        </div>
      </div>
    </div>
  );
}
