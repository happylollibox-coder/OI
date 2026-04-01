"""
Create Excel template files for loading historic data
"""

import pandas as pd
from datetime import datetime, date
import os

# Create templates directory if it doesn't exist
templates_dir = 'excel_templates'
os.makedirs(templates_dir, exist_ok=True)

print("Creating Excel templates...")

# 1. Purchase Orders Template
print("\n1. Creating Purchase Orders template...")
orders_data = {
    'purchase_order_id': ['PO_20240115_001', 'PO_20240120_002', ''],
    'order_date': ['2024-01-15', '2024-01-20', '2024-01-25'],
    'manufacturer_name': ['SYLVIA', 'SYLVIA', 'SYLVIA'],
    'product_id': ['', '', ''],  # Optional - can use product_asin or product_sku instead
    'product_asin': ['', '', ''],  # Optional - can use product_id or product_sku instead
    'product_sku': ['Mint LolliME', 'Mint LolliME', 'Mint LolliME'],  # Optional - can use product_id or product_asin instead
    'quantity': [100, 200, 150],
    'total_amount': [5000.00, 10000.00, 7500.00],
    'currency': ['USD', 'USD', 'USD'],
    'payment_status': ['PENDING', 'PENDING', 'PENDING'],
    'notes': ['First order', 'Second order', 'Third order']
}

orders_df = pd.DataFrame(orders_data)
orders_file = os.path.join(templates_dir, 'template_purchase_orders.xlsx')
orders_df.to_excel(orders_file, index=False, sheet_name='Purchase Orders')
print(f"   ✓ Created: {orders_file}")

# 2. Shipments Template
print("\n2. Creating Shipments template...")
shipments_data = {
    'shipment_id': ['SHP_20240120_001', 'SHP_20240201_002', ''],
    'purchase_order_id': ['PO_20240115_001', 'PO_20240115_001', 'PO_20240120_002'],
    'shipment_date': ['2024-01-20', '2024-02-01', '2024-01-25'],
    'estimated_arrival_date': ['2024-02-15', '2024-03-01', '2024-02-20'],
    'tracking_number': ['TRACK123456', 'TRACK789012', ''],
    'shipment_type': ['FAST_SEA', 'SLOW_SEA', 'AIR'],
    'quantity_shipped': [100, 100, 200],
    'kg_price': [2.50, 2.50, ''],
    'cost_shipped': [2000.00, 2000.00, 4000.00],
    'is_paid': ['Yes', 'No', 'Yes'],
    'paid_date': ['2024-01-25', '', '2024-01-30'],
    'shipment_status': ['IN_TRANSIT', 'PENDING', 'RECEIVED'],
    'notes': ['First shipment', 'Second shipment', 'Third shipment']
}

shipments_df = pd.DataFrame(shipments_data)
shipments_file = os.path.join(templates_dir, 'template_shipments.xlsx')
shipments_df.to_excel(shipments_file, index=False, sheet_name='Shipments')
print(f"   ✓ Created: {shipments_file}")

# 3. Payments Template
print("\n3. Creating Payments template...")
payments_data = {
    'payment_id': ['PAY_20240125_001', 'PAY_20240210_002', ''],
    'purchase_order_id': ['PO_20240115_001', 'PO_20240115_001', 'PO_20240120_002'],
    'payment_date': ['2024-01-25', '2024-02-10', '2024-01-30'],
    'payment_amount': [5000.00, 5000.00, 10000.00],
    'bank_fee': [10.00, 10.00, 20.00],
    'currency': ['USD', 'USD', 'USD'],
    'payment_method': ['Bank Leumi Business', 'Account Payoneer', 'Bank Leumi Private'],
    'vendor_name': ['SYLVIA', 'SYLVIA', 'SYLVIA'],  # Can be comma-separated: 'SYLVIA,ANNA'
    'notes': ['First payment', 'Second payment', 'Full payment']
}

payments_df = pd.DataFrame(payments_data)
payments_file = os.path.join(templates_dir, 'template_payments.xlsx')
payments_df.to_excel(payments_file, index=False, sheet_name='Payments')
print(f"   ✓ Created: {payments_file}")

# 4. Combined Template (all three sheets in one file)
print("\n4. Creating Combined template (all sheets)...")
combined_file = os.path.join(templates_dir, 'template_all_data.xlsx')
with pd.ExcelWriter(combined_file, engine='openpyxl') as writer:
    orders_df.to_excel(writer, sheet_name='Purchase Orders', index=False)
    shipments_df.to_excel(writer, sheet_name='Shipments', index=False)
    payments_df.to_excel(writer, sheet_name='Payments', index=False)
print(f"   ✓ Created: {combined_file}")

# 5. Empty Templates (for fresh data entry)
print("\n5. Creating Empty templates...")

# Empty Orders
empty_orders = pd.DataFrame(columns=[
    'purchase_order_id', 'order_date', 'manufacturer_name', 'product_id', 
    'product_asin', 'product_sku', 'quantity', 'total_amount', 
    'currency', 'payment_status', 'notes'
])
empty_orders_file = os.path.join(templates_dir, 'template_purchase_orders_empty.xlsx')
empty_orders.to_excel(empty_orders_file, index=False, sheet_name='Purchase Orders')
print(f"   ✓ Created: {empty_orders_file}")

# Empty Shipments
empty_shipments = pd.DataFrame(columns=[
    'shipment_id', 'purchase_order_id', 'shipment_date', 'estimated_arrival_date',
    'tracking_number', 'shipment_type', 'quantity_shipped', 'kg_price',
    'cost_shipped', 'is_paid', 'paid_date', 'shipment_status', 'notes'
])
empty_shipments_file = os.path.join(templates_dir, 'template_shipments_empty.xlsx')
empty_shipments.to_excel(empty_shipments_file, index=False, sheet_name='Shipments')
print(f"   ✓ Created: {empty_shipments_file}")

# Empty Payments
empty_payments = pd.DataFrame(columns=[
    'payment_id', 'purchase_order_id', 'payment_date', 'payment_amount',
    'bank_fee', 'currency', 'payment_method', 'vendor_name', 'notes'
])
empty_payments_file = os.path.join(templates_dir, 'template_payments_empty.xlsx')
empty_payments.to_excel(empty_payments_file, index=False, sheet_name='Payments')
print(f"   ✓ Created: {empty_payments_file}")

print("\n" + "="*60)
print("All Excel templates created successfully!")
print("="*60)
print(f"\nTemplates location: {os.path.abspath(templates_dir)}/")
print("\nFiles created:")
print("  • template_purchase_orders.xlsx (with sample data)")
print("  • template_shipments.xlsx (with sample data)")
print("  • template_payments.xlsx (with sample data)")
print("  • template_all_data.xlsx (all sheets combined)")
print("  • template_purchase_orders_empty.xlsx (empty template)")
print("  • template_shipments_empty.xlsx (empty template)")
print("  • template_payments_empty.xlsx (empty template)")
print("\nYou can:")
print("  1. Open these files in Excel")
print("  2. Replace sample data with your historic data")
print("  3. Use load_excel_data.py to import them into BigQuery")
