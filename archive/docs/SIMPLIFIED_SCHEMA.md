# Simplified Schema for Small Companies

## Overview

The tables have been simplified to include only essential fields needed for a small company's operations. Complex fields and advanced features have been removed to make data entry faster and easier.

## What Was Simplified

### DE_PURCHASE_ORDERS

**Removed:**
- Complex manufacturer address fields (now just name, email, phone)
- Product category, description, manufacturer SKU
- Delivery terms (FOB, CIF, etc.)
- Shipping method and cost estimates
- Internal notes, tags
- Quarter dimension

**Kept (Essential):**
- Order date, PO number
- Manufacturer name, email, phone
- Product name, SKU
- Quantity, unit price, total amount
- Order status, payment status
- Payment terms, expected delivery date
- Destination warehouse
- Notes

**Result:** ~15 essential fields instead of 30+

---

### DE_MANUFACTURER_SHIPMENTS

**Removed:**
- Complex origin/destination address breakdowns
- Package dimensions and weight
- Insurance, handling, customs duty costs
- Quality inspection details
- Damage tracking
- Inventory bin locations
- Multiple date fields (inspected, put-away)
- Quarter dimension

**Kept (Essential):**
- Purchase order link
- Shipment date, tracking number, carrier
- Destination warehouse and address
- Product name
- Quantity shipped and received
- Shipping cost
- Shipment status, received date
- Notes

**Result:** ~12 essential fields instead of 30+

---

### DE_VENDOR_PAYMENTS

**Removed:**
- Complex bank account details (routing, SWIFT codes)
- Payment fees breakdown
- Partial payment tracking
- Overdue calculations
- Refund/credit memo details
- Complex reconciliation fields
- Quarter dimension

**Kept (Essential):**
- Purchase order link
- Payment date, amount, method
- Payment reference, status
- Vendor name
- Payment terms, due date
- Invoice number and amount
- Bank accounts (from/to)
- Reconciliation flag and date
- Notes

**Result:** ~15 essential fields instead of 30+

---

## Benefits

✅ **Faster data entry** - Fewer fields to fill  
✅ **Less confusion** - Only essential information  
✅ **Easier to use** - Simpler forms  
✅ **Still complete** - All critical data captured  
✅ **Easy to extend** - Can add fields later if needed  

## What You Can Still Do

- Track all purchase orders from manufacturers
- Monitor shipments and receiving
- Record all vendor payments
- Link orders → shipments → payments
- Generate reports on all data
- Track payment terms and due dates
- Reconcile payments

## If You Need More Later

The schema can be easily extended. Just:
1. Add fields to the SQL table schema
2. Update the form template
3. Update the app.py insert function

All the infrastructure is in place - we just removed the complex fields you don't need right now.
