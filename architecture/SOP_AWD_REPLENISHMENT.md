# Architecture SOP: AWD Auto-Replenishment Optimization

## 1. Problem Statement
Amazon's default FBA auto-replenishment algorithms often over-forecast demand during Q4, leading to excessive transfers from Amazon Warehousing & Distribution (AWD) to FBA. This results in heavy FBA storage fees. Conversely, keeping inventory too low causes Amazon to pool inventory in limited Fulfillment Centers, resulting in poor geographic spread, slower Prime delivery speeds (e.g. 4-7 days instead of 1-day), and degraded conversion rates.

## 2. The Solution: The "Hybrid Leash" Strategy
We maintain the benefits of AWD auto-replenishment (zero inbound placement fees, automated logistics) while protecting against volatile forecasting by setting strict **Min and Max unit limits** in Seller Central for each sku, calculated by their 30-day trailing velocity.

### The Mechanics:
- **Min unit limit (The Floor):** Set to exactly **30 Days of Supply (30 DOS)**.
  - *Purpose:* Forces Amazon to always maintain enough volume in the FBA network to guarantee nationwide geographic spread, preserving 1-day/2-day Prime delivery speeds and protecting layout conversion.
- **Max unit limit (The Ceiling):** Set to exactly **45 Days of Supply (45 DOS)**.
  - *Purpose:* Acts as a hard stop against Amazon's Q4 over-forecasting algorithms. Once FBA inventory hits 45 DOS, Amazon is physically stopped from pulling any more units from AWD, protecting against exorbitant Q4 storage fees.

## 3. Implementation Logic For Dashboards (Ori Intelligence)
When implementing AWD and FBA monitoring inside the Shipment Planner or Dashboards:
1. **Calculate Baseline Velocity**: Query `V_UNIFIED_DAILY` to determine the exact trailing 30-day unit velocity (`total_units_30d`) per ASIN.
2. **Calculate Thresholds**:
   - `Min_Limit = total_units_30d` (30 DOS).
   - `Max_Limit = total_units_30d * 1.5` (45 DOS).
3. **Dashboard Indicators**:
   - The UI should flag any product where `current_fba_inventory < Min_Limit` as **"Low Spread Risk"**.
   - The UI should flag any product where `current_fba_inventory > Max_Limit` as **"Storage Fee Risk"**.
4. **Data Sync**: Ensure the dashboard reflects the hard limits input into Seller Central to contextualize Amazon's recent AWD-to-FBA transfers.
