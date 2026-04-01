"""
OI Data Entry Forms Application
Flask web application for entering purchase orders, manufacturer shipments, and vendor payments into BigQuery
Ultra-lean version for small companies
"""

from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, session
from google.cloud import bigquery
from datetime import datetime, timedelta, date
import uuid
import os
from functools import wraps
from time import time
from authlib.integrations.flask_client import OAuth
import requests

# Load environment variables from .env file if it exists
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # dotenv is optional

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')

@app.after_request
def add_no_cache_headers(response):
    """Prevent browser from caching HTML pages."""
    if response.content_type and 'text/html' in response.content_type:
        response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
    return response

# Allowed users (can be moved to environment variable or database)
ALLOWED_USERS = [
    'happylollibox@gmail.com',
    'adva.tal2@gmail.com'
]

# OAuth configuration
oauth = OAuth(app)

# Get OAuth credentials from environment
GOOGLE_CLIENT_ID = os.environ.get('GOOGLE_CLIENT_ID', '').strip()
GOOGLE_CLIENT_SECRET = os.environ.get('GOOGLE_CLIENT_SECRET', '').strip()

# Validate that credentials are set (warn but don't fail - allows app to start)
if not GOOGLE_CLIENT_ID or not GOOGLE_CLIENT_SECRET:
    print("WARNING: Google OAuth credentials not set in environment variables!")
    print(f"GOOGLE_CLIENT_ID: {'SET' if GOOGLE_CLIENT_ID else 'MISSING'}")
    print(f"GOOGLE_CLIENT_SECRET: {'SET' if GOOGLE_CLIENT_SECRET else 'MISSING'}")
    print("OAuth login will not work until credentials are configured in Cloud Run.")

google = oauth.register(
    name='google',
    client_id=GOOGLE_CLIENT_ID,
    client_secret=GOOGLE_CLIENT_SECRET,
    server_metadata_url='https://accounts.google.com/.well-known/openid-configuration',
    client_kwargs={
        'scope': 'openid email profile'
    }
)

# Authentication decorator
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            return redirect(url_for('login'))
        if session.get('user', {}).get('email') not in ALLOWED_USERS:
            flash('You do not have access to this application.', 'error')
            return redirect(url_for('logout'))
        return f(*args, **kwargs)
    return decorated_function

# Simple in-memory cache
_cache = {}
_cache_timestamps = {}

def cache_result(ttl_seconds=300):
    """Decorator to cache function results for specified TTL"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            cache_key = f"{func.__name__}:{str(args)}:{str(kwargs)}"
            now = time()
            
            # Check if cached result exists and is still valid
            if cache_key in _cache:
                if now - _cache_timestamps[cache_key] < ttl_seconds:
                    return _cache[cache_key]
            
            # Execute function and cache result
            result = func(*args, **kwargs)
            _cache[cache_key] = result
            _cache_timestamps[cache_key] = now
            
            return result
        return wrapper
    return decorator

def clear_cache(pattern=None):
    """Clear cache entries matching pattern (or all if None)"""
    if pattern is None:
        _cache.clear()
        _cache_timestamps.clear()
    else:
        keys_to_remove = [k for k in _cache.keys() if pattern in k]
        for k in keys_to_remove:
            _cache.pop(k, None)
            _cache_timestamps.pop(k, None)

def clear_data_cache():
    """Clear all data-related caches (called after inserts/updates/deletes)"""
    clear_cache('get_purchase_orders')
    clear_cache('get_dashboard_stats')
    clear_cache('get_po_details')
    clear_cache('get_all_shipments')
    clear_cache('get_open_pos_for_shipment')

# Custom Jinja2 filter for formatting numbers
@app.template_filter('format_currency')
def format_currency(value):
    """Format a number as currency with commas and 2 decimal places"""
    try:
        return f"{float(value):,.2f}"
    except (ValueError, TypeError):
        return "0.00"

@app.template_filter('format_percent')
def format_percent(value):
    """Format a number as percentage with 1 decimal place"""
    try:
        return f"{float(value):.1f}"
    except (ValueError, TypeError):
        return "0.0"

@app.template_filter('format_number')
def format_number(value):
    """Format a number with commas"""
    try:
        return f"{int(value):,}"
    except (ValueError, TypeError):
        return "0"

@app.template_filter('format_currency_with_commas')
def format_currency_with_commas(value):
    """Format a number as currency with commas and 2 decimal places"""
    try:
        return f"{float(value):,.2f}"
    except (ValueError, TypeError):
        return "0.00"

@app.template_filter('format_number_with_commas')
def format_number_with_commas(value):
    """Format a number with commas (handles floats and ints)"""
    try:
        num = float(value)
        if num == int(num):
            return f"{int(num):,}"
        else:
            return f"{num:,.2f}"
    except (ValueError, TypeError):
        return "0"

from config import PROJECT_ID, DATASET_ID, ORDERS_TABLE, SHIPMENTS_TABLE, SHIPMENT_LINES_TABLE, PAYMENTS_TABLE, PRODUCTS_TABLE, COSTS_HISTORY_TABLE

client = bigquery.Client(project=PROJECT_ID)

def generate_id(prefix):
    """Generate a unique ID for records"""
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


@cache_result(ttl_seconds=300)  # Cache for 5 minutes (products rarely change)
def get_products():
    """Get all active products from DIM_PRODUCT"""
    query = f"""
    SELECT 
      product_id,
      asin,
      product_name,
      display_name,
      sku,
      brand,
      manufacturer
    FROM `{PRODUCTS_TABLE}`
    WHERE is_active = TRUE
    ORDER BY product_name, asin
    """
    results = client.query(query).result()
    return [dict(row) for row in results]


@cache_result(ttl_seconds=60)  # Cache for 1 minute (cleared on updates)
def get_purchase_orders_with_status(filter_open_shipments=False, filter_unpaid=False, limit=None):
    # Note: filter_unpaid parameter kept for backward compatibility but not used in UI
    """Get purchase orders with payment and shipment status"""
    query = f"""
    WITH payment_totals AS (
      SELECT 
        purchase_order_id,
        SUM(payment_amount) as total_paid
      FROM `{PAYMENTS_TABLE}`
      GROUP BY purchase_order_id
    ),
    shipment_totals AS (
      SELECT 
        sl.purchase_order_id,
        SUM(COALESCE(sl.allocated_cost, 0)) as total_shipment_cost,
        SUM(CASE WHEN s.is_paid = TRUE THEN COALESCE(sl.allocated_cost, 0) ELSE 0 END) as paid_shipment_cost
      FROM `{SHIPMENT_LINES_TABLE}` sl
      INNER JOIN `{SHIPMENTS_TABLE}` s ON sl.shipment_id = s.shipment_id
      GROUP BY sl.purchase_order_id
    ),
    shipment_quantities AS (
      SELECT 
        sl.purchase_order_id,
        SUM(COALESCE(sl.quantity_shipped, 0)) as total_quantity_shipped
      FROM `{SHIPMENT_LINES_TABLE}` sl
      GROUP BY sl.purchase_order_id
    ),
    shipment_quantities_without_cost AS (
      -- Quantity shipped but without allocated_cost (for estimation calculation)
      SELECT 
        sl.purchase_order_id,
        SUM(COALESCE(sl.quantity_shipped, 0)) as quantity_without_cost
      FROM `{SHIPMENT_LINES_TABLE}` sl
      WHERE sl.quantity_shipped > 0 
        AND (sl.allocated_cost IS NULL OR sl.allocated_cost = 0)
      GROUP BY sl.purchase_order_id
    ),
    po_shipment_unit_cost AS (
      -- Weighted average unit cost from shipments in the same PO
      SELECT 
        sl.purchase_order_id,
        CASE 
          WHEN SUM(COALESCE(sl.quantity_shipped, 0)) > 0 
          THEN SUM(COALESCE(sl.allocated_cost, 0)) / SUM(COALESCE(sl.quantity_shipped, 0))
          ELSE NULL
        END as avg_unit_cost
      FROM `{SHIPMENT_LINES_TABLE}` sl
      WHERE (
        sl.allocated_cost IS NOT NULL AND sl.allocated_cost > 0 
        AND sl.quantity_shipped IS NOT NULL AND sl.quantity_shipped > 0
      )
      GROUP BY sl.purchase_order_id
    ),
    product_shipment_unit_cost AS (
      -- Weighted average unit cost from shipments in other POs for the same product
      SELECT 
        po.product_id,
        CASE 
          WHEN SUM(COALESCE(sl.quantity_shipped, 0)) > 0 
          THEN SUM(COALESCE(sl.allocated_cost, 0)) / SUM(COALESCE(sl.quantity_shipped, 0))
          ELSE NULL
        END as avg_unit_cost
      FROM `{ORDERS_TABLE}` po
      INNER JOIN `{SHIPMENT_LINES_TABLE}` sl ON po.purchase_order_id = sl.purchase_order_id
      WHERE (
        sl.allocated_cost IS NOT NULL AND sl.allocated_cost > 0 
        AND sl.quantity_shipped IS NOT NULL AND sl.quantity_shipped > 0
      )
      GROUP BY po.product_id
    ),
    last_12_months_unit_cost AS (
      -- Weighted average unit cost from all shipments in the last 12 months
      SELECT 
        CASE 
          WHEN SUM(COALESCE(sl.quantity_shipped, 0)) > 0 
          THEN SUM(COALESCE(sl.allocated_cost, 0)) / SUM(COALESCE(sl.quantity_shipped, 0))
          ELSE NULL
        END as avg_unit_cost
      FROM `{SHIPMENT_LINES_TABLE}` sl
      INNER JOIN `{SHIPMENTS_TABLE}` s ON sl.shipment_id = s.shipment_id
      INNER JOIN `{ORDERS_TABLE}` po ON sl.purchase_order_id = po.purchase_order_id
      WHERE (
        sl.allocated_cost IS NOT NULL AND sl.allocated_cost > 0 
        AND sl.quantity_shipped IS NOT NULL AND sl.quantity_shipped > 0
      )
      AND (
        COALESCE(s.shipment_date, po.order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      )
    )
    SELECT 
      po.purchase_order_id,
      po.order_date,
      po.manufacturer_name,
      po.product_id,
      po.product_asin,
      po.product_name,
      po.quantity,
      po.unit_price,
      po.total_amount,
      po.currency,
      COALESCE(pt.total_paid, 0) as total_paid,
      COALESCE(st.total_shipment_cost, 0) as total_shipment_cost,
      COALESCE(st.paid_shipment_cost, 0) as paid_shipment_cost,
      (po.total_amount + COALESCE(st.total_shipment_cost, 0)) as total_amount_with_shipments,
      (COALESCE(pt.total_paid, 0) + COALESCE(st.paid_shipment_cost, 0)) as total_paid_with_shipments,
      ((po.total_amount + COALESCE(st.total_shipment_cost, 0)) - (COALESCE(pt.total_paid, 0) + COALESCE(st.paid_shipment_cost, 0))) as amount_remaining_with_shipments,
      (po.total_amount - COALESCE(pt.total_paid, 0)) as amount_remaining,
      (po.total_amount - COALESCE(pt.total_paid, 0)) as remaining_manufactured,
      (COALESCE(st.total_shipment_cost, 0) - COALESCE(st.paid_shipment_cost, 0)) as remaining_shipments,
      ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01 as is_paid_in_full,
      COALESCE(sq.total_quantity_shipped, 0) as total_quantity_shipped,
      (po.quantity - COALESCE(sq.total_quantity_shipped, 0)) as remaining_quantity_to_ship,
      COALESCE(sqc.quantity_without_cost, 0) as quantity_without_cost,
      -- Estimated shipment cost: quantity shipped without cost × average unit cost
      -- Only calculate for shipments that exist but don't have cost_shipped
      -- First try PO average, then product average, then last 12 months average, else NULL
      CASE 
        WHEN COALESCE(sqc.quantity_without_cost, 0) > 0 THEN
          COALESCE(sqc.quantity_without_cost, 0) * 
          COALESCE(
            poc.avg_unit_cost,
            prc.avg_unit_cost,
            lm.avg_unit_cost,
            NULL
          )
        ELSE NULL
      END as remaining_shipments_estimated,
      -- Open shipments: true if PO not fully paid OR shipments not fully paid OR quantity remaining to ship
      -- Use ABS difference < 0.01 to handle floating point rounding issues
      (ABS(COALESCE(pt.total_paid, 0) - po.total_amount) >= 0.01
       OR (COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) >= 0.01)
       OR (po.quantity - COALESCE(sq.total_quantity_shipped, 0) > 0)) as has_open_shipments,
      -- Payment status calculation: Fully Paid if PO paid AND shipments paid AND all quantity shipped
      -- Use ABS difference < 0.01 to handle floating point rounding issues
      CASE 
        WHEN ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01
         AND (COALESCE(st.total_shipment_cost, 0) = 0 OR ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01)
         AND (po.quantity - COALESCE(sq.total_quantity_shipped, 0) <= 0)
        THEN 'Fully Paid'
        WHEN ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01
         AND (COALESCE(st.total_shipment_cost, 0) = 0 OR ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01)
        THEN 'PO Paid, Shipment Paid'
        WHEN ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01
        THEN CONCAT('PO Paid', 
                    CASE 
                      WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) >= 0.01
                      THEN ', Pending Shipment Payment'
                      WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01
                      THEN ', Shipment Paid'
                      ELSE ''
                    END)
        ELSE CONCAT('Pending PO Payment',
                    CASE 
                      WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) >= 0.01
                      THEN ', Pending Shipment Payment'
                      WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01
                      THEN ', Shipment Paid'
                      ELSE ''
                    END)
      END as payment_status_calculated,
      po.notes,
      po.created_at
    FROM `{ORDERS_TABLE}` po
    LEFT JOIN payment_totals pt ON po.purchase_order_id = pt.purchase_order_id
    LEFT JOIN shipment_totals st ON po.purchase_order_id = st.purchase_order_id
    LEFT JOIN shipment_quantities sq ON po.purchase_order_id = sq.purchase_order_id
    LEFT JOIN shipment_quantities_without_cost sqc ON po.purchase_order_id = sqc.purchase_order_id
    LEFT JOIN po_shipment_unit_cost poc ON po.purchase_order_id = poc.purchase_order_id
    LEFT JOIN product_shipment_unit_cost prc ON po.product_id = prc.product_id
    LEFT JOIN last_12_months_unit_cost lm ON TRUE
    """
    
    conditions = []
    if filter_open_shipments:
        # Open shipments: PO not fully paid OR shipments not fully paid OR quantity remaining to ship
        # Use ABS difference < 0.01 to handle floating point rounding issues
        conditions.append("(ABS(COALESCE(pt.total_paid, 0) - po.total_amount) >= 0.01 OR (COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) >= 0.01) OR (po.quantity - COALESCE(sq.total_quantity_shipped, 0) > 0))")
    if filter_unpaid:
        conditions.append("((po.total_amount + COALESCE(st.total_shipment_cost, 0)) - (COALESCE(pt.total_paid, 0) + COALESCE(st.paid_shipment_cost, 0))) > 0")
    
    if conditions:
        query += " WHERE " + " OR ".join(conditions)
    
    query += " ORDER BY po.order_date DESC, po.created_at DESC"
    
    # Add LIMIT if specified (for pagination)
    if limit:
        query += f" LIMIT {limit}"
    
    # Use to_dataframe for better performance on larger result sets
    try:
        df = client.query(query).to_dataframe()
        orders = df.to_dict('records')
        # Convert boolean values and ensure numeric fields are properly typed
        for order in orders:
            order['is_paid_in_full'] = bool(order.get('is_paid_in_full', False))
            order['has_open_shipments'] = bool(order.get('has_open_shipments', False))
            # Ensure numeric fields are floats
            order['total_quantity_shipped'] = float(order.get('total_quantity_shipped', 0) or 0)
            order['remaining_quantity_to_ship'] = float(order.get('remaining_quantity_to_ship', 0) or 0)
            # Handle estimated cost (can be None)
            estimated_cost = order.get('remaining_shipments_estimated')
            order['remaining_shipments_estimated'] = float(estimated_cost) if estimated_cost is not None else None
            # Ensure payment_status_calculated is a string
            order['payment_status_calculated'] = str(order.get('payment_status_calculated', 'Pending'))
    except Exception:
        # Fallback to standard method if pandas not available
        results = client.query(query).result()
        orders = []
        for row in results:
            order_dict = dict(row)
            order_dict['is_paid_in_full'] = bool(order_dict.get('is_paid_in_full', False))
            order_dict['has_open_shipments'] = bool(order_dict.get('has_open_shipments', False))
            order_dict['total_quantity_shipped'] = float(order_dict.get('total_quantity_shipped', 0) or 0)
            order_dict['remaining_quantity_to_ship'] = float(order_dict.get('remaining_quantity_to_ship', 0) or 0)
            # Handle estimated cost (can be None)
            estimated_cost = order_dict.get('remaining_shipments_estimated')
            order_dict['remaining_shipments_estimated'] = float(estimated_cost) if estimated_cost is not None else None
            order_dict['payment_status_calculated'] = str(order_dict.get('payment_status_calculated', 'Pending'))
            orders.append(order_dict)
    
    return orders


@cache_result(ttl_seconds=60)  # Cache for 1 minute (cleared on updates)
def get_po_details(po_id):
    """Get purchase order details with all payments and shipments"""
    # Get PO with payment and shipment totals (same calculation as home page)
    po_query = f"""
    WITH payment_totals AS (
      SELECT 
        purchase_order_id,
        SUM(payment_amount) as total_paid
      FROM `{PAYMENTS_TABLE}`
      GROUP BY purchase_order_id
    ),
    shipment_totals AS (
      SELECT 
        sl.purchase_order_id,
        SUM(COALESCE(sl.allocated_cost, 0)) as total_shipment_cost,
        SUM(CASE WHEN s.is_paid = TRUE THEN COALESCE(sl.allocated_cost, 0) ELSE 0 END) as paid_shipment_cost
      FROM `{SHIPMENT_LINES_TABLE}` sl
      INNER JOIN `{SHIPMENTS_TABLE}` s ON sl.shipment_id = s.shipment_id
      GROUP BY sl.purchase_order_id
    ),
    shipment_quantities AS (
      SELECT 
        sl.purchase_order_id,
        SUM(COALESCE(sl.quantity_shipped, 0)) as total_quantity_shipped
      FROM `{SHIPMENT_LINES_TABLE}` sl
      GROUP BY sl.purchase_order_id
    ),
    shipment_quantities_without_cost AS (
      SELECT 
        sl.purchase_order_id,
        SUM(COALESCE(sl.quantity_shipped, 0)) as quantity_without_cost
      FROM `{SHIPMENT_LINES_TABLE}` sl
      WHERE sl.quantity_shipped > 0 
        AND (sl.allocated_cost IS NULL OR sl.allocated_cost = 0)
      GROUP BY sl.purchase_order_id
    ),
    po_shipment_unit_cost AS (
      SELECT 
        sl.purchase_order_id,
        CASE 
          WHEN SUM(COALESCE(sl.quantity_shipped, 0)) > 0 
          THEN SUM(COALESCE(sl.allocated_cost, 0)) / SUM(COALESCE(sl.quantity_shipped, 0))
          ELSE NULL
        END as avg_unit_cost
      FROM `{SHIPMENT_LINES_TABLE}` sl
      WHERE (
        sl.allocated_cost IS NOT NULL AND sl.allocated_cost > 0 
        AND sl.quantity_shipped IS NOT NULL AND sl.quantity_shipped > 0
      )
      GROUP BY sl.purchase_order_id
    ),
    product_shipment_unit_cost AS (
      SELECT 
        po.product_id,
        CASE 
          WHEN SUM(COALESCE(sl.quantity_shipped, 0)) > 0 
          THEN SUM(COALESCE(sl.allocated_cost, 0)) / SUM(COALESCE(sl.quantity_shipped, 0))
          ELSE NULL
        END as avg_unit_cost
      FROM `{ORDERS_TABLE}` po
      INNER JOIN `{SHIPMENT_LINES_TABLE}` sl ON po.purchase_order_id = sl.purchase_order_id
      WHERE (
        sl.allocated_cost IS NOT NULL AND sl.allocated_cost > 0 
        AND sl.quantity_shipped IS NOT NULL AND sl.quantity_shipped > 0
      )
      GROUP BY po.product_id
    ),
    last_12_months_unit_cost AS (
      SELECT 
        CASE 
          WHEN SUM(COALESCE(sl.quantity_shipped, 0)) > 0 
          THEN SUM(COALESCE(sl.allocated_cost, 0)) / SUM(COALESCE(sl.quantity_shipped, 0))
          ELSE NULL
        END as avg_unit_cost
      FROM `{SHIPMENT_LINES_TABLE}` sl
      INNER JOIN `{SHIPMENTS_TABLE}` s ON sl.shipment_id = s.shipment_id
      INNER JOIN `{ORDERS_TABLE}` po ON sl.purchase_order_id = po.purchase_order_id
      WHERE (
        sl.allocated_cost IS NOT NULL AND sl.allocated_cost > 0 
        AND sl.quantity_shipped IS NOT NULL AND sl.quantity_shipped > 0
      )
      AND (
        COALESCE(s.shipment_date, po.order_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      )
    )
    SELECT 
      po.*,
      COALESCE(pt.total_paid, 0) as total_paid,
      COALESCE(st.total_shipment_cost, 0) as total_shipment_cost,
      COALESCE(st.paid_shipment_cost, 0) as paid_shipment_cost,
      (po.total_amount + COALESCE(st.total_shipment_cost, 0)) as total_amount_with_shipments,
      (COALESCE(pt.total_paid, 0) + COALESCE(st.paid_shipment_cost, 0)) as total_paid_with_shipments,
      ((po.total_amount + COALESCE(st.total_shipment_cost, 0)) - (COALESCE(pt.total_paid, 0) + COALESCE(st.paid_shipment_cost, 0))) as amount_remaining_with_shipments,
      (po.total_amount - COALESCE(pt.total_paid, 0)) as amount_remaining,
      (po.total_amount - COALESCE(pt.total_paid, 0)) as remaining_manufactured,
      (COALESCE(st.total_shipment_cost, 0) - COALESCE(st.paid_shipment_cost, 0)) as remaining_shipments,
      ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01 as is_paid_in_full,
      COALESCE(sq.total_quantity_shipped, 0) as total_quantity_shipped,
      (po.quantity - COALESCE(sq.total_quantity_shipped, 0)) as remaining_quantity_to_ship,
      COALESCE(sqc.quantity_without_cost, 0) as quantity_without_cost,
      -- Estimated shipment cost: quantity shipped without cost × average unit cost
      -- Only calculate for shipments that exist but don't have cost_shipped
      CASE 
        WHEN COALESCE(sqc.quantity_without_cost, 0) > 0 THEN
          COALESCE(sqc.quantity_without_cost, 0) * 
          COALESCE(
            poc.avg_unit_cost,
            prc.avg_unit_cost,
            lm.avg_unit_cost,
            NULL
          )
        ELSE NULL
      END as remaining_shipments_estimated,
      -- Payment status calculation: Fully Paid if PO paid AND shipments paid AND all quantity shipped
      -- Use ABS difference < 0.01 to handle floating point rounding issues
      CASE 
        WHEN ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01
         AND (COALESCE(st.total_shipment_cost, 0) = 0 OR ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01)
         AND (po.quantity - COALESCE(sq.total_quantity_shipped, 0) <= 0)
        THEN 'Fully Paid'
        WHEN ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01
         AND (COALESCE(st.total_shipment_cost, 0) = 0 OR ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01)
        THEN 'PO Paid, Shipment Paid'
        WHEN ABS(COALESCE(pt.total_paid, 0) - po.total_amount) < 0.01
        THEN CONCAT('PO Paid', 
                    CASE 
                      WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) >= 0.01
                      THEN ', Pending Shipment Payment'
                      WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01
                      THEN ', Shipment Paid'
                      ELSE ''
                    END)
        ELSE CONCAT('Pending PO Payment',
                    CASE 
                      WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) >= 0.01
                      THEN ', Pending Shipment Payment'
                      WHEN COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01
                      THEN ', Shipment Paid'
                      ELSE ''
                    END)
      END as payment_status_calculated
    FROM `{ORDERS_TABLE}` po
    LEFT JOIN payment_totals pt ON po.purchase_order_id = pt.purchase_order_id
    LEFT JOIN shipment_totals st ON po.purchase_order_id = st.purchase_order_id
    LEFT JOIN shipment_quantities sq ON po.purchase_order_id = sq.purchase_order_id
    LEFT JOIN shipment_quantities_without_cost sqc ON po.purchase_order_id = sqc.purchase_order_id
    LEFT JOIN po_shipment_unit_cost poc ON po.purchase_order_id = poc.purchase_order_id
    LEFT JOIN product_shipment_unit_cost prc ON po.product_id = prc.product_id
    LEFT JOIN last_12_months_unit_cost lm ON TRUE
    WHERE po.purchase_order_id = @po_id
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("po_id", "STRING", po_id)
        ]
    )
    po_result = list(client.query(po_query, job_config=job_config).result())
    if not po_result:
        return None, [], []
    
    po = dict(po_result[0])
    # Handle estimated cost (can be None)
    estimated_cost = po.get('remaining_shipments_estimated')
    try:
        po['remaining_shipments_estimated'] = float(estimated_cost) if estimated_cost is not None and estimated_cost != '' else None
    except (ValueError, TypeError):
        po['remaining_shipments_estimated'] = None
    # Convert boolean and ensure string fields
    po['is_paid_in_full'] = bool(po.get('is_paid_in_full', False))
    po['payment_status_calculated'] = str(po.get('payment_status_calculated', 'Pending'))
    po['total_quantity_shipped'] = float(po.get('total_quantity_shipped', 0) or 0)
    po['remaining_quantity_to_ship'] = float(po.get('remaining_quantity_to_ship', 0) or 0)
    # Ensure all financial fields have defaults
    po['total_paid'] = float(po.get('total_paid', 0) or 0)
    po['total_shipment_cost'] = float(po.get('total_shipment_cost', 0) or 0)
    po['total_amount_with_shipments'] = float(po.get('total_amount_with_shipments', po.get('total_amount', 0)) or 0)
    po['total_paid_with_shipments'] = float(po.get('total_paid_with_shipments', po.get('total_paid', 0)) or 0)
    po['amount_remaining_with_shipments'] = float(po.get('amount_remaining_with_shipments', po.get('amount_remaining', 0)) or 0)
    po['amount_remaining'] = float(po.get('amount_remaining', 0) or 0)
    po['remaining_manufactured'] = float(po.get('remaining_manufactured', 0) or 0)
    po['remaining_shipments'] = float(po.get('remaining_shipments', 0) or 0)
    po['remaining_quantity_to_ship'] = float(po.get('remaining_quantity_to_ship', 0) or 0)
    
    # Get payments
    payments_query = f"""
    SELECT * FROM `{PAYMENTS_TABLE}`
    WHERE purchase_order_id = @po_id
    ORDER BY payment_date DESC
    """
    payments_result = client.query(payments_query, job_config=job_config).result()
    payments = [dict(row) for row in payments_result]
    
    # Get shipments linked to this PO through DE_SHIPMENT_LINES
    shipments_query = f"""
    SELECT s.*, sl.quantity_shipped as line_quantity, sl.allocated_cost as line_allocated_cost,
           sl.num_cartons, sl.cubic_feet_per_carton, sl.total_cubic_feet
    FROM `{SHIPMENT_LINES_TABLE}` sl
    INNER JOIN `{SHIPMENTS_TABLE}` s ON sl.shipment_id = s.shipment_id
    WHERE sl.purchase_order_id = @po_id
    ORDER BY s.shipment_date DESC
    """
    shipments_result = client.query(shipments_query, job_config=job_config).result()
    shipments = [dict(row) for row in shipments_result]
    
    return po, payments, shipments


def insert_purchase_order(data):
    """Insert purchase order data into BigQuery"""
    order_date = data.get('order_date')
    
    # Get product info if product_id is provided
    product_id = data.get('product_id')
    product_asin = None
    product_name = data.get('product_name')
    product_sku = None
    
    if product_id:
        # Look up product from DIM_PRODUCT
        query = f"""
        SELECT product_id, asin, product_name, display_name, sku
        FROM `{PRODUCTS_TABLE}`
        WHERE product_id = @product_id AND is_active = TRUE
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("product_id", "INT64", int(product_id))]
        )
        result = list(client.query(query, job_config=job_config).result())
        if result:
            product_asin = result[0].asin
            product_sku = result[0].sku
            # Use SKU as product name (e.g., "Mint LolliME")
            product_name = result[0].sku or result[0].display_name or result[0].product_name or product_name
    
    # Generate PO ID from date, SKU, and quantity
    quantity = float(data.get('quantity', 0))
    if not data.get('purchase_order_id'):
        # Format: PO_YYYYMMDD_SKU_QUANTITY
        date_str = order_date.replace('-', '') if order_date else ''
        sku_str = (product_sku or 'NOSKU').replace(' ', '_').replace('-', '_')[:20]  # Limit SKU length, sanitize
        qty_str = str(int(quantity))
        base_po_id = f"PO_{date_str}_{sku_str}_{qty_str}"
        
        # Check if PO ID already exists, add suffix if needed
        po_id = base_po_id
        suffix = 1
        while True:
            check_query = f"""
            SELECT COUNT(*) as cnt
            FROM `{ORDERS_TABLE}`
            WHERE purchase_order_id = @po_id
            """
            check_config = bigquery.QueryJobConfig(
                query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
            )
            check_result = list(client.query(check_query, job_config=check_config).result())
            if check_result[0].cnt == 0:
                break
            po_id = f"{base_po_id}_{suffix}"
            suffix += 1
    else:
        po_id = data.get('purchase_order_id')
    
    # Get amount and calculate unit price (quantity already retrieved above)
    total_amount = float(data.get('total_amount', 0))
    # Ensure unit_price is always a valid float (required field)
    unit_price = float(total_amount / quantity if quantity > 0 else 0)
    
    # Validate required fields
    if not order_date:
        return ['Order date is required'], None
    if not data.get('manufacturer_name'):
        return ['Manufacturer name is required'], None
    if quantity <= 0:
        return ['Quantity must be greater than 0'], None
    if total_amount < 0:
        return ['Total amount cannot be negative'], None
    
    row = {
        'purchase_order_id': po_id,
        'order_date': order_date,
        'manufacturer_name': data.get('manufacturer_name'),
        'quantity': int(quantity),
        'unit_price': unit_price,  # Always included as float (required field)
        'total_amount': float(total_amount),
        'currency': data.get('currency', 'USD'),
        'payment_status': data.get('payment_status', 'PENDING'),
    }
    
    # Add optional fields only if they have values
    if product_id:
        row['product_id'] = int(product_id)
    if product_asin:
        row['product_asin'] = product_asin
    if product_name:
        row['product_name'] = product_name
    if data.get('notes'):
        row['notes'] = data.get('notes')
    
    # Use batch loading instead of streaming insert to avoid streaming buffer issues
    table_ref = client.get_table(ORDERS_TABLE)
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=False,  # Use table's existing schema
        schema=table_ref.schema  # Explicitly use table schema
    )
    job = client.load_table_from_json([row], table_ref, job_config=job_config)
    job.result()  # Wait for the job to complete
    
    # Check for job errors
    if job.errors:
        return job.errors, po_id
    
    return [], po_id  # Return empty errors list for consistency


def update_purchase_order(po_id, data):
    """Update purchase order data in BigQuery"""
    # Get current PO to calculate total if quantity/price changes
    current_po_query = f"""
    SELECT quantity, unit_price, total_amount FROM `{ORDERS_TABLE}`
    WHERE purchase_order_id = @po_id
    """
    job_config_get = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
    )
    current_result = list(client.query(current_po_query, job_config=job_config_get).result())
    
    current_quantity = float(current_result[0].quantity) if current_result else 0
    current_total_amount = float(current_result[0].total_amount) if current_result else 0
    
    # Use new values or current values
    quantity = float(data.get('quantity', current_quantity))
    total_amount = float(data.get('total_amount', current_total_amount))
    
    # Calculate unit_price from total_amount / quantity
    unit_price = total_amount / quantity if quantity > 0 else 0
    
    # Build update query
    updates = []
    params = []
    
    if data.get('order_date'):
        updates.append('order_date = @order_date')
        params.append(bigquery.ScalarQueryParameter("order_date", "DATE", data.get('order_date')))
    if data.get('manufacturer_name'):
        updates.append('manufacturer_name = @manufacturer_name')
        params.append(bigquery.ScalarQueryParameter("manufacturer_name", "STRING", data.get('manufacturer_name')))
    if data.get('product_id'):
        # Look up product info
        product_id_val = int(data.get('product_id'))
        product_query = f"""
        SELECT product_id, asin, product_name, display_name, sku
        FROM `{PRODUCTS_TABLE}`
        WHERE product_id = @product_id AND is_active = TRUE
        """
        product_job_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("product_id", "INT64", product_id_val)]
        )
        product_result = list(client.query(product_query, job_config=product_job_config).result())
        if product_result:
            updates.append('product_id = @product_id')
            params.append(bigquery.ScalarQueryParameter("product_id", "INT64", product_id_val))
            updates.append('product_asin = @product_asin')
            params.append(bigquery.ScalarQueryParameter("product_asin", "STRING", product_result[0].asin))
            updates.append('product_name = @product_name')
            # Use SKU as product name (e.g., "Mint LolliME")
            product_name_val = product_result[0].sku or product_result[0].display_name or product_result[0].product_name
            params.append(bigquery.ScalarQueryParameter("product_name", "STRING", product_name_val))
    elif data.get('product_name'):
        updates.append('product_name = @product_name')
        params.append(bigquery.ScalarQueryParameter("product_name", "STRING", data.get('product_name')))
    if data.get('quantity'):
        updates.append('quantity = @quantity')
        params.append(bigquery.ScalarQueryParameter("quantity", "INT64", int(quantity)))
    # Always update unit_price and total_amount if quantity or total_amount changed
    if data.get('quantity') or data.get('total_amount'):
        updates.append('unit_price = @unit_price')
        params.append(bigquery.ScalarQueryParameter("unit_price", "FLOAT64", unit_price))
        updates.append('total_amount = @total_amount')
        params.append(bigquery.ScalarQueryParameter("total_amount", "FLOAT64", total_amount))
    
    if data.get('currency'):
        updates.append('currency = @currency')
        params.append(bigquery.ScalarQueryParameter("currency", "STRING", data.get('currency')))
    if data.get('payment_status'):
        updates.append('payment_status = @payment_status')
        params.append(bigquery.ScalarQueryParameter("payment_status", "STRING", data.get('payment_status')))
    if 'notes' in data:
        updates.append('notes = @notes')
        params.append(bigquery.ScalarQueryParameter("notes", "STRING", data.get('notes')))
    
    if not updates:
        return [], po_id
    
    params.append(bigquery.ScalarQueryParameter("po_id", "STRING", po_id))
    
    query = f"""
    UPDATE `{ORDERS_TABLE}`
    SET {', '.join(updates)}
    WHERE purchase_order_id = @po_id
    """
    
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    client.query(query, job_config=job_config).result()
    return [], po_id


@cache_result(ttl_seconds=120)  # Cache for 2 minutes
def get_open_pos_for_shipment():
    """Get all open POs with remaining quantity available to ship, plus product packaging info."""
    query = f"""
    WITH shipped AS (
      SELECT purchase_order_id, SUM(COALESCE(quantity_shipped, 0)) as total_shipped
      FROM `{SHIPMENT_LINES_TABLE}`
      GROUP BY purchase_order_id
    )
    SELECT po.purchase_order_id, po.product_name, po.product_asin, po.quantity as order_quantity,
           po.manufacturer_name,
           COALESCE(sh.total_shipped, 0) as total_shipped,
           (po.quantity - COALESCE(sh.total_shipped, 0)) as remaining_quantity,
           dp.package_quantity, dp.package_cubic_feet
    FROM `{ORDERS_TABLE}` po
    LEFT JOIN shipped sh ON po.purchase_order_id = sh.purchase_order_id
    LEFT JOIN `{PRODUCTS_TABLE}` dp ON po.product_id = dp.product_id
    WHERE po.payment_status != 'CANCELLED'
      AND (po.quantity - COALESCE(sh.total_shipped, 0)) > 0
    ORDER BY po.order_date DESC
    """
    result = client.query(query).result()
    return [dict(row) for row in result]


@cache_result(ttl_seconds=60)  # Cache for 1 minute (cleared on updates)
def get_all_shipments(status_filter='open'):
    """Get all shipments with aggregated line info for the shipments list page.
    
    Args:
        status_filter: 'open' (default) = exclude PUT_AWAY/RECEIVED/INSPECTED, 'all' = everything
    """
    # Auto-update: if estimated_arrival_date has passed AND is_paid, mark as RECEIVED
    try:
        client.query(f"""
            UPDATE `{SHIPMENTS_TABLE}`
            SET shipment_status = 'RECEIVED'
            WHERE estimated_arrival_date <= CURRENT_DATE()
              AND is_paid = TRUE
              AND shipment_status NOT IN ('RECEIVED', 'INSPECTED', 'PUT_AWAY')
        """).result()
    except Exception as e:
        print(f"Auto-status update error (non-blocking): {e}")
    
    status_clause = ""
    if status_filter == 'open':
        status_clause = "WHERE s.shipment_status NOT IN ('PUT_AWAY', 'RECEIVED', 'INSPECTED')"
    
    query = f"""
    SELECT s.*,
           ARRAY_AGG(
             CASE WHEN sl.line_id IS NOT NULL THEN
               STRUCT(
                 sl.purchase_order_id, sl.quantity_shipped, sl.allocated_cost,
                 po.product_name, po.product_asin
               )
             END IGNORE NULLS
           ) as line_items,
           COUNT(sl.line_id) as line_count
    FROM `{SHIPMENTS_TABLE}` s
    LEFT JOIN `{SHIPMENT_LINES_TABLE}` sl ON s.shipment_id = sl.shipment_id
    LEFT JOIN `{ORDERS_TABLE}` po ON sl.purchase_order_id = po.purchase_order_id
    {status_clause}
    GROUP BY s.shipment_id, s.shipment_date, s.estimated_arrival_date, s.tracking_number,
             s.shipment_type, s.total_quantity, s.kg_price, s.cost_shipped, s.is_paid,
             s.paid_date, s.shipment_status, s.notes, s.created_at
    ORDER BY s.shipment_date DESC
    """
    result = client.query(query).result()
    return [dict(row) for row in result]


@app.route('/shipments', methods=['GET'])
@login_required
def shipments_list():
    """Standalone shipments list page"""
    status_filter = request.args.get('filter', 'open')  # default: open shipments
    shipments = get_all_shipments(status_filter=status_filter)
    return render_template('shipments_list.html', shipments=shipments, status_filter=status_filter)


def insert_shipment(data, lines):
    """Insert shipment header + lines into BigQuery.
    
    Args:
        data: dict with shipment header fields (shipment_date, shipment_type, cost_shipped, etc.)
        lines: list of dicts with [{'purchase_order_id': ..., 'quantity_shipped': ...}, ...]
    """
    import math
    
    shipment_id = data.get('shipment_id') or generate_id('SHP')
    shipment_date = data.get('shipment_date')
    
    kg_price = float(data.get('kg_price')) if data.get('kg_price') else None
    cost_shipped = float(data.get('cost_shipped')) if data.get('cost_shipped') else None
    
    # Handle is_paid checkbox
    is_paid_value = data.get('is_paid')
    if isinstance(is_paid_value, str):
        is_paid = is_paid_value.lower() == 'true'
    else:
        is_paid = bool(is_paid_value)
    
    paid_date = data.get('paid_date') if is_paid and data.get('paid_date') else None
    
    # Calculate estimated_arrival_date based on shipment_type
    estimated_arrival_date = data.get('estimated_arrival_date')
    shipment_type = data.get('shipment_type', '').upper()
    
    if not estimated_arrival_date and shipment_date and shipment_type:
        if isinstance(shipment_date, str):
            shipment_date_obj = datetime.strptime(shipment_date, '%Y-%m-%d').date()
        elif isinstance(shipment_date, datetime):
            shipment_date_obj = shipment_date.date()
        elif hasattr(shipment_date, 'date'):
            shipment_date_obj = shipment_date.date()
        else:
            shipment_date_obj = shipment_date
        
        days_map = {'SLOW_SEA': 33, 'FAST_SEA': 27, 'AIR': 10}
        days_to_add = days_map.get(shipment_type)
        if days_to_add:
            estimated_arrival_date = (shipment_date_obj + timedelta(days=days_to_add)).isoformat()
    
    # Calculate total_quantity from lines
    total_quantity = sum(int(line.get('quantity_shipped', 0)) for line in lines)
    
    # --- Look up product cubic feet for each PO line ---
    po_ids = [line['purchase_order_id'] for line in lines]
    # Query product info for these POs
    placeholders = ', '.join([f'@po_{i}' for i in range(len(po_ids))])
    product_query = f"""
    SELECT po.purchase_order_id, dp.package_quantity, dp.package_cubic_feet
    FROM `{ORDERS_TABLE}` po
    LEFT JOIN `{PRODUCTS_TABLE}` dp ON po.product_id = dp.product_id
    WHERE po.purchase_order_id IN ({placeholders})
    """
    params = [bigquery.ScalarQueryParameter(f'po_{i}', 'STRING', po_id) for i, po_id in enumerate(po_ids)]
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    product_result = {dict(row)['purchase_order_id']: dict(row) for row in client.query(product_query, job_config=job_config).result()}
    
    # --- Build shipment lines with cubic-feet data ---
    line_rows = []
    for line in lines:
        po_id = line['purchase_order_id']
        qty = int(line.get('quantity_shipped', 0))
        product_info = product_result.get(po_id, {})
        
        pkg_qty = product_info.get('package_quantity') or 1
        cubic_ft = product_info.get('package_cubic_feet')
        
        num_cartons = math.ceil(qty / pkg_qty) if pkg_qty > 0 else None
        total_cubic_ft = (num_cartons * cubic_ft) if (num_cartons and cubic_ft) else None
        
        line_rows.append({
            'line_id': generate_id('SHL'),
            'shipment_id': shipment_id,
            'purchase_order_id': po_id,
            'quantity_shipped': qty,
            'num_cartons': num_cartons,
            'cubic_feet_per_carton': cubic_ft,
            'total_cubic_feet': total_cubic_ft,
            'allocated_cost': None,  # Calculated below
        })
    
    # --- Calculate cubic-feet-based cost allocation ---
    if cost_shipped is not None:
        grand_total_cubic = sum(lr.get('total_cubic_feet', 0) or 0 for lr in line_rows)
        if grand_total_cubic > 0:
            for lr in line_rows:
                lr_cubic = lr.get('total_cubic_feet', 0) or 0
                lr['allocated_cost'] = round((lr_cubic / grand_total_cubic) * cost_shipped, 2)
        else:
            # Fallback: equal split if no cubic feet data
            per_line = round(cost_shipped / len(line_rows), 2)
            for lr in line_rows:
                lr['allocated_cost'] = per_line
    
    # --- Insert shipment header ---
    header_row = {
        'shipment_id': shipment_id,
        'shipment_date': shipment_date,
        'total_quantity': total_quantity,
        'is_paid': is_paid,
        'shipment_status': data.get('shipment_status', 'PENDING'),
        'cost_shipped': cost_shipped,
    }
    
    if estimated_arrival_date:
        header_row['estimated_arrival_date'] = estimated_arrival_date
    if data.get('tracking_number'):
        header_row['tracking_number'] = data.get('tracking_number')
    if data.get('shipment_type'):
        header_row['shipment_type'] = data.get('shipment_type')
    if kg_price is not None:
        header_row['kg_price'] = kg_price
    if paid_date:
        header_row['paid_date'] = paid_date
    if data.get('notes'):
        header_row['notes'] = data.get('notes')
    
    # Batch load shipment header
    table_ref = client.get_table(SHIPMENTS_TABLE)
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=False,
        schema=table_ref.schema
    )
    job = client.load_table_from_json([header_row], table_ref, job_config=job_config)
    job.result()
    if job.errors:
        return job.errors, shipment_id
    
    # --- Insert shipment lines ---
    lines_table_ref = client.get_table(SHIPMENT_LINES_TABLE)
    lines_job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=False,
        schema=lines_table_ref.schema
    )
    lines_job = client.load_table_from_json(line_rows, lines_table_ref, job_config=lines_job_config)
    lines_job.result()
    if lines_job.errors:
        return lines_job.errors, shipment_id
    
    return [], shipment_id


def insert_payment(data):
    """Insert vendor payment data into BigQuery"""
    payment_id = data.get('payment_id') or generate_id('PAY')
    payment_date = data.get('payment_date')
    
    payment_amount = float(data.get('payment_amount', 0))
    bank_fee = float(data.get('bank_fee')) if data.get('bank_fee') else None
    
    # Handle vendor_name from checkboxes (can be list or single value)
    # vendor_name is REQUIRED, so validate it exists
    vendor_name_raw = data.get('vendor_name')
    if isinstance(vendor_name_raw, list):
        vendor_name = ', '.join(vendor_name_raw) if vendor_name_raw else None
    elif vendor_name_raw:
        vendor_name = str(vendor_name_raw)
    else:
        vendor_name = None
    
    # Validate required fields
    if not payment_date:
        return ['Payment date is required'], None
    if not data.get('purchase_order_id'):
        return ['Purchase order ID is required'], None
    if payment_amount <= 0:
        return ['Payment amount must be greater than 0'], None
    if not vendor_name:
        return ['At least one vendor must be selected'], None
    
    row = {
        'payment_id': payment_id,
        'purchase_order_id': data.get('purchase_order_id'),
        'payment_date': payment_date,
        'payment_amount': float(payment_amount),
        'vendor_name': vendor_name,  # Required field - always included
        'currency': data.get('currency', 'USD'),
    }
    
    # Add optional fields only if they have values
    if bank_fee is not None:
        row['bank_fee'] = bank_fee
    if data.get('payment_method'):
        row['payment_method'] = data.get('payment_method')
    if data.get('notes'):
        row['notes'] = data.get('notes')
    
    # Use batch loading instead of streaming insert to avoid streaming buffer issues
    table_ref = client.get_table(PAYMENTS_TABLE)
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=False,  # Use table's existing schema
        schema=table_ref.schema  # Explicitly use table schema
    )
    job = client.load_table_from_json([row], table_ref, job_config=job_config)
    job.result()  # Wait for the job to complete
    
    # Check for job errors
    if job.errors:
        return job.errors, payment_id
    
    return [], payment_id  # Return empty errors list for consistency


@cache_result(ttl_seconds=120)  # Cache for 2 minutes
def get_dashboard_stats(selected_year=None):
    """Get year-over-year comparison statistics"""
    if selected_year is None:
        current_year = datetime.now().year
    else:
        current_year = int(selected_year)
    last_year = current_year - 1
    
    # Query for PO Orders Amount - use parameterized query to avoid formatting issues
    po_query = f"""
    SELECT 
      EXTRACT(YEAR FROM order_date) as year,
      SUM(total_amount) as total_amount
    FROM `{ORDERS_TABLE}`
    WHERE EXTRACT(YEAR FROM order_date) IN (@last_year, @current_year)
    GROUP BY year
    ORDER BY year
    """
    
    po_job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("last_year", "INT64", last_year),
            bigquery.ScalarQueryParameter("current_year", "INT64", current_year)
        ]
    )
    
    # Query for Shipment Amount (cost_shipped)
    shipment_query = f"""
    SELECT 
      EXTRACT(YEAR FROM s.shipment_date) as year,
      SUM(COALESCE(s.cost_shipped, 0)) as total_cost_shipped,
      SUM(COALESCE(s.total_quantity, 0)) as total_quantity_shipped
    FROM `{SHIPMENTS_TABLE}` s
    WHERE EXTRACT(YEAR FROM s.shipment_date) IN (@last_year, @current_year)
    GROUP BY year
    ORDER BY year
    """
    
    shipment_job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("last_year", "INT64", last_year),
            bigquery.ScalarQueryParameter("current_year", "INT64", current_year)
        ]
    )
    
    # Execute queries
    po_results = list(client.query(po_query, job_config=po_job_config).result())
    shipment_results = list(client.query(shipment_query, job_config=shipment_job_config).result())
    
    # Initialize stats
    stats = {
        'po_orders': {'last_year': 0, 'this_year': 0},
        'shipment_amount': {'last_year': 0, 'this_year': 0},
        'quantity_amount': {'last_year': 0, 'this_year': 0}
    }
    
    # Process PO results
    for row in po_results:
        try:
            if hasattr(row, 'year') and row.year is not None:
                year = int(row.year)
                amount = float(row.total_amount) if row.total_amount and row.total_amount is not None else 0
                if year == last_year:
                    stats['po_orders']['last_year'] = amount
                elif year == current_year:
                    stats['po_orders']['this_year'] = amount
        except (ValueError, AttributeError) as e:
            print(f"Error processing PO row: {e}")
            continue
    
    # Process shipment results
    for row in shipment_results:
        try:
            if hasattr(row, 'year') and row.year is not None:
                year = int(row.year)
                cost = float(row.total_cost_shipped) if row.total_cost_shipped and row.total_cost_shipped is not None else 0
                qty = int(row.total_quantity_shipped) if row.total_quantity_shipped and row.total_quantity_shipped is not None else 0
                if year == last_year:
                    stats['shipment_amount']['last_year'] = cost
                    stats['quantity_amount']['last_year'] = qty
                elif year == current_year:
                    stats['shipment_amount']['this_year'] = cost
                    stats['quantity_amount']['this_year'] = qty
        except (ValueError, AttributeError) as e:
            print(f"Error processing shipment row: {e}")
            continue
    
    # Calculate percentage changes
    for key in stats:
        last = float(stats[key]['last_year']) if stats[key]['last_year'] is not None else 0.0
        current = float(stats[key]['this_year']) if stats[key]['this_year'] is not None else 0.0
        
        stats[key]['last_year'] = last
        stats[key]['this_year'] = current
        
        if last > 0:
            stats[key]['change_percent'] = ((current - last) / last) * 100
        else:
            stats[key]['change_percent'] = 100.0 if current > 0 else 0.0
        stats[key]['change_amount'] = current - last
    
    stats['current_year'] = int(current_year)
    stats['last_year'] = int(last_year)
    
    return stats


@app.route('/login')
def login():
    """Login page - shows login button"""
    if 'user' in session and session.get('user', {}).get('email') in ALLOWED_USERS:
        return redirect(url_for('index'))
    
    return render_template('login.html')


@app.route('/debug/oauth')
def debug_oauth():
    """Debug endpoint to check OAuth configuration"""
    if 'user' not in session or session.get('user', {}).get('email') not in ALLOWED_USERS:
        return "Access denied. This is a debug endpoint.", 403
    
    debug_info = {
        'module_level': {
            'GOOGLE_CLIENT_ID': GOOGLE_CLIENT_ID[:30] + '...' if GOOGLE_CLIENT_ID else 'MISSING',
            'GOOGLE_CLIENT_SECRET': 'SET' if GOOGLE_CLIENT_SECRET else 'MISSING'
        },
        'runtime_env': {
            'GOOGLE_CLIENT_ID': os.environ.get('GOOGLE_CLIENT_ID', 'NOT_FOUND')[:30] + '...' if os.environ.get('GOOGLE_CLIENT_ID') else 'NOT_FOUND',
            'GOOGLE_CLIENT_SECRET': 'SET' if os.environ.get('GOOGLE_CLIENT_SECRET') else 'NOT_FOUND'
        },
        'all_env_vars': [k for k in os.environ.keys() if 'GOOGLE' in k or 'CLIENT' in k],
        'oauth_registered': google is not None if 'google' in globals() else False
    }
    
    return jsonify(debug_info)


@app.route('/auth/google')
def auth_google():
    """Initiate Google OAuth flow"""
    try:
        # Read environment variables at runtime (in case they were updated)
        client_id = os.environ.get('GOOGLE_CLIENT_ID', '').strip()
        client_secret = os.environ.get('GOOGLE_CLIENT_SECRET', '').strip()
        
        # Debug logging
        print(f"DEBUG: Reading OAuth credentials at runtime")
        print(f"DEBUG: GOOGLE_CLIENT_ID from env: {client_id[:30] if client_id else 'EMPTY'}...")
        print(f"DEBUG: GOOGLE_CLIENT_SECRET from env: {'SET' if client_secret else 'EMPTY'}")
        print(f"DEBUG: GOOGLE_CLIENT_ID from module: {GOOGLE_CLIENT_ID[:30] if GOOGLE_CLIENT_ID else 'EMPTY'}...")
        
        # Use runtime values if available, otherwise fall back to module-level
        final_client_id = client_id if client_id else GOOGLE_CLIENT_ID
        final_client_secret = client_secret if client_secret else GOOGLE_CLIENT_SECRET
        
        # Check if OAuth credentials are configured
        if not final_client_id or not final_client_secret:
            # Log detailed debug information
            print("="*60)
            print("OAUTH CONFIGURATION ERROR - DETAILED DEBUG")
            print("="*60)
            print(f"Module-level GOOGLE_CLIENT_ID: {GOOGLE_CLIENT_ID[:50] if GOOGLE_CLIENT_ID else 'EMPTY'}")
            print(f"Module-level GOOGLE_CLIENT_SECRET: {'SET' if GOOGLE_CLIENT_SECRET else 'EMPTY'}")
            print(f"Runtime env GOOGLE_CLIENT_ID: {client_id[:50] if client_id else 'EMPTY'}")
            print(f"Runtime env GOOGLE_CLIENT_SECRET: {'SET' if client_secret else 'EMPTY'}")
            print(f"Final CLIENT_ID: {final_client_id[:50] if final_client_id else 'EMPTY'}")
            print(f"Final CLIENT_SECRET: {'SET' if final_client_secret else 'EMPTY'}")
            print(f"All env vars with 'GOOGLE': {[k for k in os.environ.keys() if 'GOOGLE' in k]}")
            print(f"All env vars with 'CLIENT': {[k for k in os.environ.keys() if 'CLIENT' in k]}")
            print("="*60)
            
            flash('OAuth is not configured. Please set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET environment variables.', 'error')
            return redirect(url_for('login'))
        
        # Re-register OAuth client with runtime values if needed
        # Use a global reference to update the google client
        global google
        if final_client_id != GOOGLE_CLIENT_ID or final_client_secret != GOOGLE_CLIENT_SECRET:
            print("DEBUG: Re-registering OAuth client with runtime environment variables")
            google = oauth.register(
                name='google',
                client_id=final_client_id,
                client_secret=final_client_secret,
                server_metadata_url='https://accounts.google.com/.well-known/openid-configuration',
                client_kwargs={
                    'scope': 'openid email profile'
                },
                overwrite=True  # Overwrite existing registration
            )
        
        # Build redirect URI dynamically based on the actual request host
        # Cloud Run sits behind a reverse proxy, so use X-Forwarded-Proto header
        scheme = request.headers.get('X-Forwarded-Proto', request.scheme)
        redirect_uri = f"{scheme}://{request.host}/auth/callback"
        
        print(f"OAuth redirect URI: {redirect_uri}")
        print(f"OAuth CLIENT_ID: {final_client_id[:20] if final_client_id else 'MISSING'}...")
        return google.authorize_redirect(redirect_uri)
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"OAuth initiation error: {error_details}")
        flash(f'OAuth initiation error: {str(e)}', 'error')
        return redirect(url_for('login'))


@app.route('/auth/callback')
def auth_callback():
    """OAuth callback - handles Google sign-in"""
    try:
        token = google.authorize_access_token()
        
        # Fetch userinfo from Google's userinfo endpoint using requests
        # authlib's google.get() might not work correctly, so use requests directly
        access_token = token.get('access_token')
        if not access_token:
            flash('Failed to get access token from Google', 'error')
            return redirect(url_for('login'))
        
        # Fetch userinfo from Google
        userinfo_response = requests.get(
            'https://www.googleapis.com/oauth2/v2/userinfo',
            headers={'Authorization': f'Bearer {access_token}'}
        )
        
        if userinfo_response.status_code != 200:
            flash('Failed to get user information from Google', 'error')
            print(f"Userinfo request failed: {userinfo_response.status_code} - {userinfo_response.text}")
            return redirect(url_for('login'))
        
        user_info = userinfo_response.json()
        email = user_info.get('email', '').lower()
        
        if not email:
            flash('Failed to get email from Google account', 'error')
            return redirect(url_for('login'))
        
        if email not in ALLOWED_USERS:
            flash(f'Access denied. Your email ({email}) is not authorized.', 'error')
            return render_template('login_denied.html', email=email)
        
        session['user'] = {
            'email': email,
            'name': user_info.get('name', ''),
            'picture': user_info.get('picture', '')
        }
        flash(f'Welcome, {user_info.get("name", email)}!', 'success')
        return redirect(url_for('index'))
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"OAuth callback error: {error_details}")
        flash(f'Authentication error: {str(e)}', 'error')
        return redirect(url_for('login'))


@app.route('/logout')
def logout():
    """Logout - clears session"""
    session.clear()
    flash('You have been logged out.', 'success')
    return redirect(url_for('login'))


@app.route('/dashboard')
@login_required
def dashboard():
    """Dashboard page with year-over-year comparisons"""
    try:
        # Get selected year from query parameter, default to current year
        selected_year = request.args.get('year')
        if not selected_year:
            selected_year = datetime.now().year
        
        stats = get_dashboard_stats(selected_year=selected_year)
        
        # Ensure all values are properly formatted as numbers
        for key in ['po_orders', 'shipment_amount', 'quantity_amount']:
            if key in stats:
                stats[key]['last_year'] = float(stats[key].get('last_year', 0) or 0)
                stats[key]['this_year'] = float(stats[key].get('this_year', 0) or 0)
                stats[key]['change_amount'] = float(stats[key].get('change_amount', 0) or 0)
                stats[key]['change_percent'] = float(stats[key].get('change_percent', 0) or 0)
        
        # Get list of available years for the dropdown
        current_year = datetime.now().year
        available_years = list(range(current_year - 5, current_year + 1))
        available_years.reverse()  # Most recent first
        
        return render_template('dashboard.html', stats=stats, selected_year=int(selected_year), available_years=available_years)
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        flash(f'Error loading dashboard: {str(e)}', 'error')
        print(f"Dashboard error: {error_details}")
        return redirect(url_for('index'))


@app.route('/')
@login_required
def index():
    """Home page - shows list of purchase orders"""
    # Open shipments filter is ON by default
    filter_open = request.args.get('filter_open_shipments', 'true').lower() == 'true'
    
    # Optional: Add pagination limit (default: show all, but can limit to 100 for faster loading)
    limit = request.args.get('limit', type=int)
    orders = get_purchase_orders_with_status(filter_open_shipments=filter_open, filter_unpaid=False, limit=limit)
    
    # Calculate remaining amounts
    # Remaining to Manufactured = PO amount remaining (for SYLVIA manufacturer)
    remaining_sylvia = sum(order.get('remaining_manufactured', order.get('amount_remaining', 0)) for order in orders 
                          if order.get('manufacturer_name') == 'SYLVIA' and order.get('remaining_manufactured', order.get('amount_remaining', 0)) > 0)
    
    # Remaining to Shipments = unpaid shipment costs (for all orders, not filtered by manufacturer)
    remaining_anna = sum(order.get('remaining_shipments', 0) for order in orders 
                        if order.get('remaining_shipments', 0) > 0)
    
    # Remaining Shipments Estimated = sum of all estimated shipment costs
    remaining_shipments_estimated_total = sum(order.get('remaining_shipments_estimated', 0) or 0 
                                               for order in orders 
                                               if order.get('remaining_shipments_estimated') is not None)
    
    # Get open shipments for the home page table
    try:
        open_shipments = get_all_shipments(status_filter='open')
    except Exception as e:
        print(f"Error fetching open shipments: {e}")
        open_shipments = []
    
    return render_template('index.html', 
                         orders=orders, 
                         filter_open=filter_open,
                         remaining_sylvia=remaining_sylvia,
                         remaining_anna=remaining_anna,
                         remaining_shipments_estimated_total=remaining_shipments_estimated_total,
                         open_shipments=open_shipments)


@app.route('/po/<po_id>')
@login_required
def po_details(po_id):
    """PO Details page - shows PO, payments, and shipments"""
    po, payments, shipments = get_po_details(po_id)
    
    if not po:
        flash(f'Purchase Order {po_id} not found', 'error')
        return redirect(url_for('index'))
    
    # Get products for the product dropdown
    try:
        products = get_products()
    except Exception as e:
        flash(f'Warning: Could not load products from DIM_PRODUCT: {str(e)}', 'error')
        products = []
    
    return render_template('po_details.html', po=po, payments=payments, shipments=shipments, products=products)


@app.route('/po/<po_id>/update', methods=['POST'])
@login_required
def update_po(po_id):
    """Update purchase order"""
    try:
        errors, updated_po_id = update_purchase_order(po_id, request.form.to_dict())
        if errors:
            flash(f'Error updating purchase order: {errors}', 'error')
        else:
            clear_data_cache()
            flash(f'Purchase Order {po_id} updated successfully!', 'success')
    except Exception as e:
        flash(f'Error: {str(e)}', 'error')
    
    return redirect(url_for('po_details', po_id=po_id))


@app.route('/orders/new', methods=['GET', 'POST'])
@login_required
def new_order():
    """Create a new purchase order"""
    if request.method == 'POST':
        try:
            errors, po_id = insert_purchase_order(request.form.to_dict())
            if errors:
                flash(f'Error inserting purchase order: {errors}', 'error')
            else:
                clear_data_cache()
                flash(f'Purchase Order {po_id} created successfully!', 'success')
                return redirect(url_for('po_details', po_id=po_id))
        except Exception as e:
            flash(f'Error: {str(e)}', 'error')
    
    try:
        products = get_products()
    except Exception as e:
        flash(f'Warning: Could not load products from DIM_PRODUCT: {str(e)}', 'error')
        products = []
    
    return render_template('order_form.html', products=products)


@app.route('/api/products', methods=['GET'])
@login_required
def api_products():
    """API endpoint to get products"""
    products = get_products()
    return jsonify(products)


@app.route('/shipments/new-test')
def new_shipment_test():
    """TEMPORARY: Auth-free test for shipment form debugging. REMOVE AFTER TESTING."""
    open_pos = get_open_pos_for_shipment()
    return render_template('shipment_form.html', po_id='', open_pos=open_pos)

@app.route('/shipments/new', methods=['GET', 'POST'])
@login_required
def new_shipment():
    """Create a new manufacturer shipment with multi-PO support"""
    po_id = request.args.get('po_id', '')
    
    if request.method == 'POST':
        try:
            form = request.form
            # Parse multi-PO lines from form: po_ids[] and quantities[]
            po_ids = form.getlist('po_ids[]')
            quantities = form.getlist('quantities[]')
            
            lines = []
            for pid, qty in zip(po_ids, quantities):
                if pid and int(qty or 0) > 0:
                    lines.append({'purchase_order_id': pid, 'quantity_shipped': int(qty)})
            
            if not lines:
                flash('At least one PO line with quantity > 0 is required', 'error')
                return redirect(url_for('new_shipment', po_id=po_id))
            
            header_data = {
                'shipment_date': form.get('shipment_date'),
                'shipment_type': form.get('shipment_type'),
                'cost_shipped': form.get('cost_shipped'),
                'kg_price': form.get('kg_price'),
                'tracking_number': form.get('tracking_number'),
                'is_paid': form.get('is_paid'),
                'paid_date': form.get('paid_date'),
                'shipment_status': form.get('shipment_status', 'PENDING'),
                'notes': form.get('notes'),
            }
            
            errors, shipment_id = insert_shipment(header_data, lines)
            if errors:
                flash(f'Error inserting shipment: {errors}', 'error')
            else:
                clear_data_cache()
                flash(f'Shipment {shipment_id} created successfully!', 'success')
                # Redirect to first PO or shipment
                first_po = lines[0]['purchase_order_id'] if lines else None
                if first_po:
                    return redirect(url_for('po_details', po_id=first_po))
                return redirect(url_for('shipment_details', shipment_id=shipment_id))
        except Exception as e:
            import traceback
            error_details = traceback.format_exc()
            flash(f'Error: {str(e)}', 'error')
            print(f"Shipment insertion error: {error_details}")
    
    # Fetch open POs for multi-PO picker
    open_pos = get_open_pos_for_shipment()
    return render_template('shipment_form.html', po_id=po_id, open_pos=open_pos)


@app.route('/po/<po_id>/shipments/add_row', methods=['POST'])
@login_required
def add_shipment_row(po_id):
    """Quick-add a shipment for a single PO with defaults."""
    last_shipment = None
    try:
        query = f"""
        SELECT s.shipment_date, s.estimated_arrival_date, s.shipment_type
        FROM `{SHIPMENT_LINES_TABLE}` sl
        INNER JOIN `{SHIPMENTS_TABLE}` s ON sl.shipment_id = s.shipment_id
        WHERE sl.purchase_order_id = @po_id
        ORDER BY s.shipment_date DESC, s.created_at DESC
        LIMIT 1
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
        )
        result = list(client.query(query, job_config=job_config).result())
        if result:
            last_shipment = {
                'shipment_date': result[0].shipment_date.isoformat() if result[0].shipment_date else None,
                'estimated_arrival_date': result[0].estimated_arrival_date.isoformat() if result[0].estimated_arrival_date else None,
                'shipment_type': result[0].shipment_type if result[0].shipment_type else None
            }
    except Exception as e:
        print(f"Error fetching last shipment: {e}")

    today_str = date.today().isoformat()
    data = {
        'shipment_date': today_str,
        'shipment_status': 'PENDING',
    }
    if last_shipment and last_shipment.get('shipment_type'):
        data['shipment_type'] = last_shipment['shipment_type']
    
    lines = [{'purchase_order_id': po_id, 'quantity_shipped': 0}]

    try:
        errors, shipment_id = insert_shipment(data, lines)
        if errors:
            flash(f'Error adding shipment: {errors}', 'error')
        else:
            clear_data_cache()
            flash(f'Shipment {shipment_id} added.', 'success')
    except Exception as e:
        import traceback
        flash(f'Error adding shipment: {str(e)}', 'error')
        print(traceback.format_exc())
    return redirect(url_for('po_details', po_id=po_id))


@app.route('/payments/new', methods=['GET', 'POST'])
@login_required
def new_payment():
    """Create a new vendor payment"""
    po_id = request.args.get('po_id', '')
    
    if request.method == 'POST':
        try:
            errors, payment_id = insert_payment(request.form.to_dict())
            if errors:
                flash(f'Error inserting payment: {errors}', 'error')
            else:
                clear_data_cache()
                flash(f'Payment {payment_id} created successfully!', 'success')
                purchase_order_id = request.form.get('purchase_order_id')
                if purchase_order_id:
                    return redirect(url_for('po_details', po_id=purchase_order_id))
                return redirect(url_for('new_payment'))
        except Exception as e:
            flash(f'Error: {str(e)}', 'error')
    
    return render_template('payment_form.html', po_id=po_id)


@app.route('/api/orders', methods=['GET'])
@login_required
def get_orders():
    """API endpoint to get recent purchase orders (for lookup)"""
    query = f"""
    SELECT purchase_order_id, order_date, manufacturer_name, total_amount
    FROM `{ORDERS_TABLE}`
    ORDER BY order_date DESC, created_at DESC
    LIMIT 50
    """
    results = client.query(query).result()
    orders = [dict(row) for row in results]
    return jsonify(orders)


@app.route('/po/<po_id>/delete', methods=['POST'])
@login_required
def delete_po(po_id):
    """Delete a purchase order"""
    try:
        query = f"""
        DELETE FROM `{ORDERS_TABLE}`
        WHERE purchase_order_id = @po_id
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
        )
        client.query(query, job_config=job_config).result()
        clear_data_cache()
        flash(f'Purchase Order {po_id} deleted successfully!', 'success')
        return redirect(url_for('index'))
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        error_msg = str(e)
        
        # Check for streaming buffer error
        if 'streaming buffer' in error_msg.lower():
            flash(f'Cannot delete purchase order: This PO is still in BigQuery\'s streaming buffer. This may be an older PO created before we switched to batch loading. Please wait 5-10 minutes and try again. Note: New POs created now can be deleted immediately.', 'error')
        else:
            flash(f'Error deleting purchase order: {error_msg}', 'error')
        print(f"Delete PO error: {error_details}")
        return redirect(url_for('po_details', po_id=po_id))


@app.route('/po/<po_id>/shipments/bulk-update', methods=['POST'])
@login_required
def bulk_update_shipments(po_id):
    """Bulk update shipments - Multiple fields including dates"""
    try:
        shipment_ids = request.form.getlist('shipment_ids')
        if not shipment_ids:
            flash('No shipments selected for update', 'error')
            return redirect(url_for('po_details', po_id=po_id))
        
        # Build the SET clause dynamically based on provided fields
        set_clauses = []
        params = []
        
        # Shipment Date
        if request.form.get('clear_shipment_date') == 'true':
            set_clauses.append('shipment_date = NULL')
        elif request.form.get('shipment_date'):
            set_clauses.append('shipment_date = @shipment_date')
            params.append(bigquery.ScalarQueryParameter("shipment_date", "DATE", request.form.get('shipment_date')))
        
        # Estimated Arrival Date
        if request.form.get('clear_estimated_arrival_date') == 'true':
            set_clauses.append('estimated_arrival_date = NULL')
        elif request.form.get('estimated_arrival_date'):
            set_clauses.append('estimated_arrival_date = @estimated_arrival_date')
            params.append(bigquery.ScalarQueryParameter("estimated_arrival_date", "DATE", request.form.get('estimated_arrival_date')))
        
        # Shipment Type
        if request.form.get('shipment_type'):
            set_clauses.append('shipment_type = @shipment_type')
            params.append(bigquery.ScalarQueryParameter("shipment_type", "STRING", request.form.get('shipment_type')))
        
        # Shipment Status
        if request.form.get('shipment_status'):
            set_clauses.append('shipment_status = @shipment_status')
            params.append(bigquery.ScalarQueryParameter("shipment_status", "STRING", request.form.get('shipment_status')))
        
        # Paid status (always update if checkbox is present)
        if 'is_paid' in request.form:
            is_paid = request.form.get('is_paid') == 'true'
            set_clauses.append('is_paid = @is_paid')
            params.append(bigquery.ScalarQueryParameter("is_paid", "BOOL", is_paid))
            
            # Paid Date
            if is_paid and request.form.get('paid_date'):
                set_clauses.append('paid_date = @paid_date')
                params.append(bigquery.ScalarQueryParameter("paid_date", "DATE", request.form.get('paid_date')))
            elif is_paid:
                # If paid is checked but no date provided, set to NULL
                set_clauses.append('paid_date = NULL')
            else:
                # If paid is unchecked, clear paid_date
                set_clauses.append('paid_date = NULL')
        
        if not set_clauses:
            flash('No fields selected for update', 'error')
            return redirect(url_for('po_details', po_id=po_id))
        
        # Update each shipment individually
        # Note: Since we switched to batch loading, new shipments should be updatable immediately
        # Old shipments created with streaming inserts may still be in streaming buffer
        updated_count = 0
        failed_shipments = []
        
        for shipment_id in shipment_ids:
            try:
                query = f"""
                UPDATE `{SHIPMENTS_TABLE}`
                SET {', '.join(set_clauses)}
                WHERE shipment_id = @shipment_id
                """
                job_config = bigquery.QueryJobConfig(
                    query_parameters=[
                        bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)
                    ] + params
                )
                client.query(query, job_config=job_config).result()
                updated_count += 1
            except Exception as e:
                error_msg = str(e)
                # Check if this is a streaming buffer error
                if 'streaming buffer' in error_msg.lower():
                    failed_shipments.append(shipment_id)
                    print(f"Shipment {shipment_id} is in streaming buffer - this may be an old shipment created before batch loading was enabled")
                else:
                    # Re-raise if it's a different error
                    raise
        
        # Handle results with better messaging
        if failed_shipments:
            if updated_count > 0:
                flash(f'Successfully updated {updated_count} shipment(s). {len(failed_shipments)} shipment(s) could not be updated because they are still in BigQuery\'s streaming buffer. These may be older shipments created before we switched to batch loading. Please wait 5-10 minutes and try again, or update them individually.', 'warning')
            else:
                flash(f'Cannot update shipments: All {len(failed_shipments)} selected shipment(s) are still in BigQuery\'s streaming buffer. These may be older shipments created before we switched to batch loading. Please wait 5-10 minutes and try again. Note: New shipments created now will be updatable immediately.', 'error')
        else:
            clear_data_cache()
            flash(f'Successfully updated {updated_count} shipment(s)!', 'success')
            
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        error_msg = str(e)
        
        # Check for streaming buffer error
        if 'streaming buffer' in error_msg.lower():
            flash('Cannot update shipments: One or more shipments were recently added and are still in BigQuery\'s streaming buffer. Please wait 5-10 minutes after creating shipments before updating them. Note: New shipments created now will be updatable immediately.', 'error')
        else:
            flash(f'Error updating shipments: {error_msg}', 'error')
        print(f"Bulk update error: {error_details}")
    
    return redirect(url_for('po_details', po_id=po_id))


def get_shipment_details(shipment_id):
    """Get shipment details with associated PO lines"""
    query = f"""
    SELECT s.*
    FROM `{SHIPMENTS_TABLE}` s
    WHERE s.shipment_id = @shipment_id
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)]
    )
    result = list(client.query(query, job_config=job_config).result())
    if not result:
        return None
    shipment = dict(result[0])
    
    # Get shipment lines with PO info
    lines_query = f"""
    SELECT sl.*, po.product_name, po.product_asin, po.manufacturer_name, po.order_date
    FROM `{SHIPMENT_LINES_TABLE}` sl
    LEFT JOIN `{ORDERS_TABLE}` po ON sl.purchase_order_id = po.purchase_order_id
    WHERE sl.shipment_id = @shipment_id
    ORDER BY po.product_name
    """
    lines_result = client.query(lines_query, job_config=job_config).result()
    shipment['lines'] = [dict(row) for row in lines_result]
    
    return shipment


def update_shipment(shipment_id, data):
    """Update shipment data in BigQuery"""
    updates = []
    params = []
    
    shipment_date = data.get('shipment_date')
    shipment_type = data.get('shipment_type', '').upper() if data.get('shipment_type') else None
    estimated_arrival_date = data.get('estimated_arrival_date')
    
    # If shipment_type is being updated but shipment_date is not provided, fetch current shipment_date from DB
    if shipment_type and not shipment_date and not estimated_arrival_date:
        try:
            current_shipment = get_shipment_details(shipment_id)
            if current_shipment and current_shipment.get('shipment_date'):
                shipment_date = current_shipment.get('shipment_date')
        except Exception as e:
            print(f"Error fetching current shipment_date: {e}")
    
    # Calculate estimated_arrival_date if shipment_date or shipment_type changed and estimated_arrival_date not explicitly provided
    if shipment_date and shipment_type and not estimated_arrival_date:
        # Parse shipment_date if it's a string
        if isinstance(shipment_date, str):
            shipment_date_obj = datetime.strptime(shipment_date, '%Y-%m-%d').date()
        elif isinstance(shipment_date, datetime):
            shipment_date_obj = shipment_date.date()
        elif hasattr(shipment_date, 'date'):
            shipment_date_obj = shipment_date.date()
        else:
            shipment_date_obj = shipment_date
        
        # Calculate days based on shipment type
        if shipment_type == 'SLOW_SEA':
            days_to_add = 33
        elif shipment_type == 'FAST_SEA':
            days_to_add = 27
        elif shipment_type == 'AIR':
            days_to_add = 10
        else:
            days_to_add = None
        
        if days_to_add:
            estimated_arrival_date = (shipment_date_obj + timedelta(days=days_to_add)).isoformat()
    
    if shipment_date:
        updates.append('shipment_date = @shipment_date')
        params.append(bigquery.ScalarQueryParameter("shipment_date", "DATE", shipment_date))
    
    if estimated_arrival_date:
        updates.append('estimated_arrival_date = @estimated_arrival_date')
        params.append(bigquery.ScalarQueryParameter("estimated_arrival_date", "DATE", estimated_arrival_date))
    elif 'estimated_arrival_date' in data and not data.get('estimated_arrival_date'):
        updates.append('estimated_arrival_date = NULL')
    
    if data.get('tracking_number'):
        updates.append('tracking_number = @tracking_number')
        params.append(bigquery.ScalarQueryParameter("tracking_number", "STRING", data.get('tracking_number')))
    elif 'tracking_number' in data and not data.get('tracking_number'):
        updates.append('tracking_number = NULL')
    
    if data.get('shipment_type'):
        new_shipment_type = data.get('shipment_type').upper()
        updates.append('shipment_type = @shipment_type')
        params.append(bigquery.ScalarQueryParameter("shipment_type", "STRING", new_shipment_type))
        
        # Recalculate estimated_arrival_date if shipment_type changed and shipment_date exists
        if shipment_date and not estimated_arrival_date:
            # Parse shipment_date if it's a string
            if isinstance(shipment_date, str):
                shipment_date_obj = datetime.strptime(shipment_date, '%Y-%m-%d').date()
            elif isinstance(shipment_date, datetime):
                shipment_date_obj = shipment_date.date()
            elif hasattr(shipment_date, 'date'):
                shipment_date_obj = shipment_date.date()
            else:
                shipment_date_obj = shipment_date
            
            if new_shipment_type == 'SLOW_SEA':
                days_to_add = 33
            elif new_shipment_type == 'FAST_SEA':
                days_to_add = 27
            elif new_shipment_type == 'AIR':
                days_to_add = 10
            else:
                days_to_add = None
            
            if days_to_add:
                estimated_arrival_date = (shipment_date_obj + timedelta(days=days_to_add)).isoformat()
                # Add estimated_arrival_date update if not already in updates
                if 'estimated_arrival_date = @estimated_arrival_date' not in updates:
                    updates.append('estimated_arrival_date = @estimated_arrival_date')
                    params.append(bigquery.ScalarQueryParameter("estimated_arrival_date", "DATE", estimated_arrival_date))
    elif 'shipment_type' in data and not data.get('shipment_type'):
        updates.append('shipment_type = NULL')
    
    if data.get('quantity_shipped'):
        # quantity_shipped is now on DE_SHIPMENT_LINES, update total_quantity on header
        updates.append('total_quantity = @total_quantity')
        params.append(bigquery.ScalarQueryParameter("total_quantity", "INT64", int(data.get('quantity_shipped'))))
    
    if data.get('kg_price'):
        updates.append('kg_price = @kg_price')
        params.append(bigquery.ScalarQueryParameter("kg_price", "FLOAT64", float(data.get('kg_price'))))
    elif 'kg_price' in data and not data.get('kg_price'):
        updates.append('kg_price = NULL')
    
    if data.get('cost_shipped'):
        cost_shipped = float(data.get('cost_shipped'))
        updates.append('cost_shipped = @cost_shipped')
        params.append(bigquery.ScalarQueryParameter("cost_shipped", "FLOAT64", cost_shipped))
    elif 'cost_shipped' in data and not data.get('cost_shipped'):
        updates.append('cost_shipped = NULL')
    
    # Recalculate allocated_cost on lines when cost_shipped changes
    if data.get('cost_shipped'):
        import math
        cost_val = float(data.get('cost_shipped'))
        # Get existing lines for this shipment
        lines_q = f"SELECT line_id, total_cubic_feet FROM `{SHIPMENT_LINES_TABLE}` WHERE shipment_id = @shipment_id"
        lines_jc = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)])
        line_rows = [dict(r) for r in client.query(lines_q, job_config=lines_jc).result()]
        grand_cubic = sum((lr.get('total_cubic_feet') or 0) for lr in line_rows)
        if grand_cubic > 0 and line_rows:
            for lr in line_rows:
                lr_cubic = lr.get('total_cubic_feet') or 0
                alloc = round((lr_cubic / grand_cubic) * cost_val, 2)
                upd_q = f"UPDATE `{SHIPMENT_LINES_TABLE}` SET allocated_cost = @alloc WHERE line_id = @line_id"
                upd_jc = bigquery.QueryJobConfig(query_parameters=[
                    bigquery.ScalarQueryParameter("alloc", "FLOAT64", alloc),
                    bigquery.ScalarQueryParameter("line_id", "STRING", lr['line_id']),
                ])
                client.query(upd_q, job_config=upd_jc).result()
        elif line_rows:
            per_line = round(cost_val / len(line_rows), 2)
            for lr in line_rows:
                upd_q = f"UPDATE `{SHIPMENT_LINES_TABLE}` SET allocated_cost = @alloc WHERE line_id = @line_id"
                upd_jc = bigquery.QueryJobConfig(query_parameters=[
                    bigquery.ScalarQueryParameter("alloc", "FLOAT64", per_line),
                    bigquery.ScalarQueryParameter("line_id", "STRING", lr['line_id']),
                ])
                client.query(upd_q, job_config=upd_jc).result()
    
    # Handle is_paid checkbox
    is_paid_value = data.get('is_paid')
    if isinstance(is_paid_value, str):
        is_paid = is_paid_value.lower() == 'true'
    else:
        is_paid = bool(is_paid_value)
    updates.append('is_paid = @is_paid')
    params.append(bigquery.ScalarQueryParameter("is_paid", "BOOL", is_paid))
    
    # Handle paid_date
    if is_paid and data.get('paid_date'):
        updates.append('paid_date = @paid_date')
        params.append(bigquery.ScalarQueryParameter("paid_date", "DATE", data.get('paid_date')))
    else:
        updates.append('paid_date = NULL')
    
    if data.get('shipment_status'):
        updates.append('shipment_status = @shipment_status')
        params.append(bigquery.ScalarQueryParameter("shipment_status", "STRING", data.get('shipment_status')))
    
    if data.get('notes') is not None:
        if data.get('notes'):
            updates.append('notes = @notes')
            params.append(bigquery.ScalarQueryParameter("notes", "STRING", data.get('notes')))
        else:
            updates.append('notes = NULL')
    
    if not updates:
        return []
    
    query = f"""
    UPDATE `{SHIPMENTS_TABLE}`
    SET {', '.join(updates)}
    WHERE shipment_id = @shipment_id
    """
    params.append(bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id))
    
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    client.query(query, job_config=job_config).result()
    return []


@app.route('/api/shipment/<shipment_id>/update', methods=['POST'])
@login_required
def api_update_shipment(shipment_id):
    """API endpoint for inline editing of shipment fields"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'success': False, 'error': 'No data provided'}), 400
        
        # Convert empty strings to None for optional fields
        for key in ['estimated_arrival_date', 'tracking_number', 'shipment_type', 'kg_price', 'cost_shipped', 'paid_date', 'notes']:
            if key in data and data[key] == '':
                data[key] = None
        
        # Convert number strings to proper types
        if 'quantity_shipped' in data and data['quantity_shipped']:
            data['quantity_shipped'] = int(data['quantity_shipped'])
        if 'kg_price' in data and data['kg_price']:
            data['kg_price'] = float(data['kg_price'])
        if 'cost_shipped' in data and data['cost_shipped']:
            data['cost_shipped'] = float(data['cost_shipped'])
        
        errors = update_shipment(shipment_id, data)
        if errors:
            return jsonify({'success': False, 'error': str(errors)}), 400
        
        clear_data_cache()
        
        # Return updated shipment data
        shipment = get_shipment_details(shipment_id)
        # Convert date objects to strings for JSON serialization
        if shipment:
            for key in ['shipment_date', 'estimated_arrival_date', 'paid_date']:
                if shipment.get(key) and hasattr(shipment[key], 'strftime'):
                    shipment[key] = shipment[key].strftime('%Y-%m-%d')
        
        return jsonify({'success': True, 'shipment': shipment})
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"API shipment update error: {error_details}")
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/shipment/<shipment_id>', methods=['GET', 'POST'])
@login_required
def shipment_details(shipment_id):
    """View and edit a specific shipment"""
    shipment = get_shipment_details(shipment_id)
    if not shipment:
        flash('Shipment not found', 'error')
        return redirect(url_for('index'))
    
    # Get first linked PO for navigation
    po_id = shipment.get('lines', [{}])[0].get('purchase_order_id') if shipment.get('lines') else None
    
    if request.method == 'POST':
        try:
            errors = update_shipment(shipment_id, request.form.to_dict())
            if errors:
                flash(f'Error updating shipment: {errors}', 'error')
            else:
                clear_data_cache()
                flash(f'Shipment {shipment_id} updated successfully!', 'success')
                return redirect(url_for('shipment_details', shipment_id=shipment_id))
        except Exception as e:
            import traceback
            error_details = traceback.format_exc()
            flash(f'Error: {str(e)}', 'error')
            print(f"Shipment update error: {error_details}")
    
    # Refresh shipment data after update
    shipment = get_shipment_details(shipment_id)
    return render_template('shipment_details.html', shipment=shipment, po_id=po_id)


@app.route('/shipment/<shipment_id>/delete', methods=['POST'])
@login_required
def delete_shipment(shipment_id):
    """Delete a shipment and its lines"""
    po_id = None
    try:
        # Get PO ID from lines before deleting for redirect
        query_get_po = f"""
        SELECT purchase_order_id FROM `{SHIPMENT_LINES_TABLE}`
        WHERE shipment_id = @shipment_id
        LIMIT 1
        """
        job_config_get = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)]
        )
        po_result = list(client.query(query_get_po, job_config=job_config_get).result())
        po_id = po_result[0].purchase_order_id if po_result else None
        
        # Delete lines first
        query_lines = f"""
        DELETE FROM `{SHIPMENT_LINES_TABLE}`
        WHERE shipment_id = @shipment_id
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)]
        )
        client.query(query_lines, job_config=job_config).result()
        
        # Delete header
        query_header = f"""
        DELETE FROM `{SHIPMENTS_TABLE}`
        WHERE shipment_id = @shipment_id
        """
        client.query(query_header, job_config=job_config).result()
        
        clear_data_cache()
        flash(f'Shipment {shipment_id} deleted successfully!', 'success')
        
        if po_id:
            return redirect(url_for('po_details', po_id=po_id))
        else:
            return redirect(url_for('index'))
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        error_msg = str(e)
        
        # Check for streaming buffer error
        if 'streaming buffer' in error_msg.lower():
            flash(f'Cannot delete shipment: This shipment is still in BigQuery\'s streaming buffer. This may be an older shipment created before we switched to batch loading. Please wait 5-10 minutes and try again. Note: New shipments created now can be deleted immediately.', 'error')
        else:
            flash(f'Error deleting shipment: {error_msg}', 'error')
        print(f"Delete shipment error: {error_details}")
        
        if po_id:
            return redirect(url_for('po_details', po_id=po_id))
        else:
            return redirect(url_for('index'))


def get_payment_details(payment_id):
    """Get payment details with associated PO information"""
    query = f"""
    SELECT p.*, po.purchase_order_id, po.order_date, po.manufacturer_name, po.product_name, po.product_asin, po.total_amount
    FROM `{PAYMENTS_TABLE}` p
    LEFT JOIN `{ORDERS_TABLE}` po ON p.purchase_order_id = po.purchase_order_id
    WHERE p.payment_id = @payment_id
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("payment_id", "STRING", payment_id)]
    )
    result = list(client.query(query, job_config=job_config).result())
    if not result:
        return None
    return dict(result[0])


def update_payment(payment_id, data):
    """Update payment data in BigQuery"""
    updates = []
    params = []
    
    if data.get('payment_date'):
        updates.append('payment_date = @payment_date')
        params.append(bigquery.ScalarQueryParameter("payment_date", "DATE", data.get('payment_date')))
    
    if data.get('payment_amount'):
        updates.append('payment_amount = @payment_amount')
        params.append(bigquery.ScalarQueryParameter("payment_amount", "FLOAT64", float(data.get('payment_amount'))))
    
    if data.get('bank_fee'):
        updates.append('bank_fee = @bank_fee')
        params.append(bigquery.ScalarQueryParameter("bank_fee", "FLOAT64", float(data.get('bank_fee'))))
    elif 'bank_fee' in data and not data.get('bank_fee'):
        updates.append('bank_fee = NULL')
    
    if data.get('currency'):
        updates.append('currency = @currency')
        params.append(bigquery.ScalarQueryParameter("currency", "STRING", data.get('currency')))
    
    if data.get('payment_method'):
        updates.append('payment_method = @payment_method')
        params.append(bigquery.ScalarQueryParameter("payment_method", "STRING", data.get('payment_method')))
    elif 'payment_method' in data and not data.get('payment_method'):
        updates.append('payment_method = NULL')
    
    # Handle vendor_name from checkboxes (can be list or single value)
    vendor_name = data.get('vendor_name')
    if isinstance(vendor_name, list):
        vendor_name = ', '.join(vendor_name)
    elif not vendor_name:
        vendor_name = None
    
    if vendor_name:
        updates.append('vendor_name = @vendor_name')
        params.append(bigquery.ScalarQueryParameter("vendor_name", "STRING", vendor_name))
    
    if data.get('notes') is not None:
        if data.get('notes'):
            updates.append('notes = @notes')
            params.append(bigquery.ScalarQueryParameter("notes", "STRING", data.get('notes')))
        else:
            updates.append('notes = NULL')
    
    if not updates:
        return []
    
    query = f"""
    UPDATE `{PAYMENTS_TABLE}`
    SET {', '.join(updates)}
    WHERE payment_id = @payment_id
    """
    params.append(bigquery.ScalarQueryParameter("payment_id", "STRING", payment_id))
    
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    client.query(query, job_config=job_config).result()
    return []


@app.route('/payment/<payment_id>', methods=['GET', 'POST'])
@login_required
def payment_details(payment_id):
    """View and edit a specific payment"""
    payment = get_payment_details(payment_id)
    if not payment:
        flash('Payment not found', 'error')
        return redirect(url_for('index'))
    
    po_id = payment.get('purchase_order_id')
    
    if request.method == 'POST':
        try:
            errors = update_payment(payment_id, request.form.to_dict())
            if errors:
                flash(f'Error updating payment: {errors}', 'error')
            else:
                clear_data_cache()
                flash(f'Payment {payment_id} updated successfully!', 'success')
                return redirect(url_for('payment_details', payment_id=payment_id))
        except Exception as e:
            import traceback
            error_details = traceback.format_exc()
            flash(f'Error: {str(e)}', 'error')
            print(f"Payment update error: {error_details}")
    
    # Refresh payment data after update
    payment = get_payment_details(payment_id)
    # Parse vendor_name for checkboxes (it's stored as comma-separated string)
    vendor_names = []
    if payment.get('vendor_name'):
        vendor_names = [v.strip() for v in payment.get('vendor_name', '').split(',')]
    payment['vendor_names_list'] = vendor_names
    
    return render_template('payment_details.html', payment=payment, po_id=po_id)


@app.route('/payment/<payment_id>/delete', methods=['POST'])
@login_required
def delete_payment(payment_id):
    """Delete a payment"""
    po_id = None
    try:
        # Get PO ID before deleting for redirect
        query_get_po = f"""
        SELECT purchase_order_id FROM `{PAYMENTS_TABLE}`
        WHERE payment_id = @payment_id
        """
        job_config_get = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("payment_id", "STRING", payment_id)]
        )
        po_result = list(client.query(query_get_po, job_config=job_config_get).result())
        po_id = po_result[0].purchase_order_id if po_result else None
        
        query = f"""
        DELETE FROM `{PAYMENTS_TABLE}`
        WHERE payment_id = @payment_id
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("payment_id", "STRING", payment_id)]
        )
        client.query(query, job_config=job_config).result()
        clear_data_cache()
        flash(f'Payment {payment_id} deleted successfully!', 'success')
        
        if po_id:
            return redirect(url_for('po_details', po_id=po_id))
        else:
            return redirect(url_for('index'))
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        error_msg = str(e)
        
        # Check for streaming buffer error
        if 'streaming buffer' in error_msg.lower():
            flash(f'Cannot delete payment: This payment is still in BigQuery\'s streaming buffer. This may be an older payment created before we switched to batch loading. Please wait 5-10 minutes and try again. Note: New payments created now can be deleted immediately.', 'error')
        else:
            flash(f'Error deleting payment: {error_msg}', 'error')
        print(f"Delete payment error: {error_details}")
        
        if po_id:
            return redirect(url_for('po_details', po_id=po_id))
        else:
            return redirect(url_for('index'))


# ═══════════════════════════════════════════════════════════════
# COACH THRESHOLDS API
# ═══════════════════════════════════════════════════════════════

@app.route('/api/thresholds', methods=['GET'])
def api_thresholds_get():
    """Get all coach thresholds, grouped by strategy"""
    try:
        query = """
            SELECT threshold_key, strategy_id, product_family,
                   threshold_value, description,
                   suggested_value, suggested_at, suggestion_reason,
                   peak_multiplier, boost_peak_multiplier,
                   source, updated_at, updated_by
            FROM `{project}.{dataset}.DE_COACH_THRESHOLDS`
            ORDER BY strategy_id, threshold_key
        """.format(project=PROJECT_ID, dataset=DATASET_ID)
        results = client.query(query).result()
        rows = [dict(row) for row in results]
        # Convert datetime objects to ISO strings for JSON serialization
        for row in rows:
            if row.get('suggested_at'):
                row['suggested_at'] = row['suggested_at'].isoformat()
            if row.get('updated_at'):
                row['updated_at'] = row['updated_at'].isoformat()
        return jsonify(rows)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/thresholds', methods=['POST'])
def api_thresholds_update():
    """Update a threshold value or approve a suggestion.
    
    Body JSON:
      { "threshold_key": "WASTED_SPEND_THRESHOLD",
        "strategy_id": "EXACT_BOOST",
        "product_family": null,
        "threshold_value": 30,          // new value (or omit to approve suggestion)
        "approve_suggestion": false }    // if true, copies suggested_value → threshold_value
    """
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON body provided'}), 400
        
        threshold_key = data.get('threshold_key')
        strategy_id = data.get('strategy_id')
        product_family = data.get('product_family')
        
        if not threshold_key or not strategy_id:
            return jsonify({'error': 'threshold_key and strategy_id are required'}), 400
        
        user_email = session.get('user', {}).get('email', 'unknown')
        
        if data.get('approve_suggestion'):
            # Approve: copy suggested_value → threshold_value
            query = """
                UPDATE `{project}.{dataset}.DE_COACH_THRESHOLDS`
                SET threshold_value = suggested_value,
                    suggested_value = NULL,
                    suggested_at = NULL,
                    suggestion_reason = NULL,
                    source = 'AUTO_SUGGESTED',
                    updated_at = CURRENT_DATETIME(),
                    updated_by = @user_email
                WHERE threshold_key = @threshold_key
                  AND strategy_id = @strategy_id
                  AND COALESCE(product_family, '') = COALESCE(@product_family, '')
                  AND suggested_value IS NOT NULL
            """.format(project=PROJECT_ID, dataset=DATASET_ID)
        else:
            # Manual update
            new_value = data.get('threshold_value')
            if new_value is None:
                return jsonify({'error': 'threshold_value is required for manual update'}), 400
            query = """
                UPDATE `{project}.{dataset}.DE_COACH_THRESHOLDS`
                SET threshold_value = @new_value,
                    source = 'MANUAL',
                    updated_at = CURRENT_DATETIME(),
                    updated_by = @user_email
                WHERE threshold_key = @threshold_key
                  AND strategy_id = @strategy_id
                  AND COALESCE(product_family, '') = COALESCE(@product_family, '')
            """.format(project=PROJECT_ID, dataset=DATASET_ID)
        
        params = [
            bigquery.ScalarQueryParameter("threshold_key", "STRING", threshold_key),
            bigquery.ScalarQueryParameter("strategy_id", "STRING", strategy_id),
            bigquery.ScalarQueryParameter("product_family", "STRING", product_family),
            bigquery.ScalarQueryParameter("user_email", "STRING", user_email),
        ]
        
        if not data.get('approve_suggestion'):
            params.append(bigquery.ScalarQueryParameter("new_value", "FLOAT64", float(data['threshold_value'])))
        
        job_config = bigquery.QueryJobConfig(query_parameters=params)
        job = client.query(query, job_config=job_config)
        job.result()
        
        if job.errors:
            return jsonify({'error': str(job.errors)}), 500
        
        clear_data_cache()
        return jsonify({'success': True, 'message': f'Threshold {threshold_key} updated for {strategy_id}'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ==========================================
# Shipment Line Edit/Delete (Issue #6)
# ==========================================

# ═══════════════════════════════════════════════════════════════
# BULKSHEET UPLOADS API — logs actions uploaded to Amazon
# ═══════════════════════════════════════════════════════════════

@app.route('/api/bulksheet-uploads', methods=['POST'])
def api_bulksheet_uploads():
    """Log bulksheet actions that were uploaded to Amazon.
    
    Body JSON: array of items, each with:
      { "search_term": "...", "campaign_id": "...", "campaign_name": "...",
        "action": "NEGATE", "entity": "Negative Keyword", "operation": "Create",
        "field_changed": "negative_keyword", "old_value": null, "new_value": "...",
        "product": "..." }
    """
    try:
        data = request.get_json()
        if not data or not isinstance(data, list):
            return jsonify({'error': 'Expected JSON array of items'}), 400
        
        import uuid
        batch_id = f'batch_{datetime.now().strftime("%Y%m%d_%H%M%S")}_{uuid.uuid4().hex[:6]}'
        now = datetime.now().isoformat()
        
        rows = []
        for item in data:
            rows.append({
                'upload_id': f'upl_{uuid.uuid4().hex[:12]}',
                'batch_id': batch_id,
                'uploaded_at': now,
                'search_term': item.get('search_term', ''),
                'campaign_id': item.get('campaign_id', ''),
                'campaign_name': item.get('campaign_name', ''),
                'action': item.get('action', ''),
                'entity': item.get('entity', ''),
                'operation': item.get('operation', ''),
                'field_changed': item.get('field_changed', ''),
                'old_value': item.get('old_value', ''),
                'new_value': item.get('new_value', ''),
                'product': item.get('product', ''),
                'source': 'dashboard',
            })
        
        table_ref = f'{PROJECT_ID}.{DATASET_ID}.DE_BULKSHEET_UPLOADS'
        job_config = bigquery.LoadJobConfig(
            schema=[
                bigquery.SchemaField('upload_id', 'STRING'),
                bigquery.SchemaField('batch_id', 'STRING'),
                bigquery.SchemaField('uploaded_at', 'DATETIME'),
                bigquery.SchemaField('search_term', 'STRING'),
                bigquery.SchemaField('campaign_id', 'STRING'),
                bigquery.SchemaField('campaign_name', 'STRING'),
                bigquery.SchemaField('action', 'STRING'),
                bigquery.SchemaField('entity', 'STRING'),
                bigquery.SchemaField('operation', 'STRING'),
                bigquery.SchemaField('field_changed', 'STRING'),
                bigquery.SchemaField('old_value', 'STRING'),
                bigquery.SchemaField('new_value', 'STRING'),
                bigquery.SchemaField('product', 'STRING'),
                bigquery.SchemaField('source', 'STRING'),
            ],
            write_disposition='WRITE_APPEND',
        )
        
        job = client.load_table_from_json(rows, table_ref, job_config=job_config)
        job.result()
        
        if job.errors:
            return jsonify({'error': str(job.errors)}), 500
        
        clear_data_cache()
        return jsonify({
            'success': True,
            'batch_id': batch_id,
            'items_logged': len(rows),
        })
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"Bulksheet upload log error: {error_details}")
        return jsonify({'error': str(e)}), 500


@app.route('/shipment/<shipment_id>/line/<line_id>/update', methods=['POST'])
@login_required
def update_shipment_line(shipment_id, line_id):
    """Update a single shipment line (quantity and allocated cost)."""
    try:
        data = request.form
        updates = []
        params = [bigquery.ScalarQueryParameter("line_id", "STRING", line_id)]
        
        quantity = data.get('quantity_shipped')
        if quantity:
            updates.append("quantity_shipped = @quantity")
            params.append(bigquery.ScalarQueryParameter("quantity", "INT64", int(quantity)))
        
        allocated_cost = data.get('allocated_cost')
        if allocated_cost:
            updates.append("allocated_cost = @allocated_cost")
            params.append(bigquery.ScalarQueryParameter("allocated_cost", "FLOAT64", float(allocated_cost)))
        
        if not updates:
            flash('No changes to update', 'warning')
            return redirect(url_for('shipment_details', shipment_id=shipment_id))
        
        query = f"""
            UPDATE `{SHIPMENT_LINES_TABLE}`
            SET {', '.join(updates)}
            WHERE line_id = @line_id
        """
        job_config = bigquery.QueryJobConfig(query_parameters=params)
        job = client.query(query, job_config=job_config)
        job.result()
        
        if job.errors:
            flash(f'Error updating line: {job.errors}', 'danger')
        else:
            # Update the shipment header total_quantity
            recalc_query = f"""
                UPDATE `{SHIPMENTS_TABLE}` s
                SET total_quantity = (
                    SELECT COALESCE(SUM(sl.quantity_shipped), 0)
                    FROM `{SHIPMENT_LINES_TABLE}` sl
                    WHERE sl.shipment_id = s.shipment_id
                )
                WHERE s.shipment_id = @shipment_id
            """
            recalc_params = [bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)]
            recalc_config = bigquery.QueryJobConfig(query_parameters=recalc_params)
            recalc_job = client.query(recalc_query, job_config=recalc_config)
            recalc_job.result()
            
            flash('Shipment line updated successfully', 'success')
            clear_data_cache()
        
        return redirect(url_for('shipment_details', shipment_id=shipment_id))
    except Exception as e:
        flash(f'Error updating shipment line: {str(e)}', 'danger')
        return redirect(url_for('shipment_details', shipment_id=shipment_id))


@app.route('/shipment/<shipment_id>/line/<line_id>/delete', methods=['POST'])
@login_required
def delete_shipment_line(shipment_id, line_id):
    """Delete a single shipment line."""
    try:
        query = f"""
            DELETE FROM `{SHIPMENT_LINES_TABLE}`
            WHERE line_id = @line_id
        """
        params = [bigquery.ScalarQueryParameter("line_id", "STRING", line_id)]
        job_config = bigquery.QueryJobConfig(query_parameters=params)
        job = client.query(query, job_config=job_config)
        job.result()
        
        if job.errors:
            flash(f'Error deleting line: {job.errors}', 'danger')
        else:
            # Update the shipment header total_quantity
            recalc_query = f"""
                UPDATE `{SHIPMENTS_TABLE}` s
                SET total_quantity = (
                    SELECT COALESCE(SUM(sl.quantity_shipped), 0)
                    FROM `{SHIPMENT_LINES_TABLE}` sl
                    WHERE sl.shipment_id = s.shipment_id
                )
                WHERE s.shipment_id = @shipment_id
            """
            recalc_params = [bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)]
            recalc_config = bigquery.QueryJobConfig(query_parameters=recalc_params)
            recalc_job = client.query(recalc_query, job_config=recalc_config)
            recalc_job.result()
            
            flash('Shipment line deleted successfully', 'success')
            clear_data_cache()
        
        return redirect(url_for('shipment_details', shipment_id=shipment_id))
    except Exception as e:
        if 'UPDATE or DELETE statement over table' in str(e) and 'would affect rows in the streaming buffer' in str(e):
            flash('Cannot delete this line yet — it is still in BigQuery streaming buffer. Please wait 5-10 minutes and try again.', 'warning')
        else:
            flash(f'Error deleting shipment line: {str(e)}', 'danger')
        return redirect(url_for('shipment_details', shipment_id=shipment_id))


# ==========================================
# Costs Report Page (Issue #9)
# ==========================================

@cache_result(ttl_seconds=300)  # Cache for 5 minutes
def get_costs_history():
    """Get current cost data from DIM_COSTS_HISTORY joined with DIM_PRODUCT for listing price."""
    query = f"""
        SELECT
            ch.sku,
            ch.asin,
            ch.product_name,
            ch.estimated_pick_pack_fee_per_unit,
            ch.FBA_COST_estimated_referral_fee_per_unit,
            ch.cost_of_goods,
            ch.shipping_cost,
            ch.TOTAL_COST_PER_UNIT,
            dp.listing_price_amount
        FROM `{COSTS_HISTORY_TABLE}` ch
        LEFT JOIN `{PROJECT_ID}.{DATASET_ID}.DIM_PRODUCT` dp
            ON ch.asin = dp.asin
        WHERE ch.end_date IS NULL
        ORDER BY ch.sku
    """
    results = client.query(query).result()
    return [dict(row) for row in results]


@app.route('/costs-report')
@login_required
def costs_report():
    """Display the Costs Report page with DIM_COSTS_HISTORY data."""
    try:
        costs = get_costs_history()
        return render_template('costs_report.html', costs=costs)
    except Exception as e:
        flash(f'Error loading costs report: {str(e)}', 'danger')
        return render_template('costs_report.html', costs=[])


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    print(f"Starting OI Data Entry Forms application...")
    print(f"Server will be available at: http://localhost:{port}")
    print(f"Press Ctrl+C to stop the server")
    app.run(host='0.0.0.0', port=port, debug=True)
