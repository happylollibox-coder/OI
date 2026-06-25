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
from concurrent.futures import ThreadPoolExecutor
import jwt
import json as json_lib

# Load environment variables from .env file if it exists
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # dotenv is optional

app = Flask(__name__)

# On Cloud Run / App Engine, secrets must come from the environment — the dev
# fallbacks are committed to the repo and would let anyone forge sessions/tokens.
IS_MANAGED_RUNTIME = bool(os.environ.get('K_SERVICE') or os.environ.get('GAE_ENV'))

app.secret_key = os.environ.get('SECRET_KEY') or (
    None if IS_MANAGED_RUNTIME else 'dev-secret-key-change-in-production'
)
if not app.secret_key:
    raise RuntimeError('SECRET_KEY env var must be set when running on Cloud Run')

@app.after_request
def add_response_headers(response):
    """Add cache-control and CORS headers."""
    if response.content_type and 'text/html' in response.content_type:
        response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
    # CORS: only the React dashboard origins may call API endpoints (see architecture/API_AUTH.md)
    if request.path.startswith('/api/'):
        origin = request.headers.get('Origin', '')
        if origin in ALLOWED_ORIGINS:
            response.headers['Access-Control-Allow-Origin'] = origin
            response.headers['Vary'] = 'Origin'
            response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
            response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    return response

# Dashboard origins allowed to call /api/* cross-origin
ALLOWED_ORIGINS = {
    'https://oi-dashboard-405291422506.us-central1.run.app',
    'https://oi-dashboard-cllsaft6eq-uc.a.run.app',
    'http://localhost:5173',
    'http://127.0.0.1:5173',
}

# Handle CORS preflight (OPTIONS) for API routes
@app.route('/api/<path:path>', methods=['OPTIONS'])
def api_options(path):
    return '', 204

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
CUBEJS_API_SECRET = (os.environ.get('CUBEJS_API_SECRET') or (
    '' if IS_MANAGED_RUNTIME else 'dev-secret-key-123'
)).strip()
if not CUBEJS_API_SECRET:
    raise RuntimeError('CUBEJS_API_SECRET env var must be set when running on Cloud Run')

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
            session['next_url'] = request.url
            return redirect(url_for('login'))
        if session.get('user', {}).get('email') not in ALLOWED_USERS:
            flash('You do not have access to this application.', 'error')
            return redirect(url_for('logout'))
        return f(*args, **kwargs)
    return decorated_function


# ─── API authentication gate (see architecture/API_AUTH.md) ───
# Every /api/* request must carry either the dashboard JWT (signed with
# CUBEJS_API_SECRET, same token Cube verifies) or an allowed session cookie.
# No per-route decorators: new /api routes are protected by default.

def _has_valid_api_token() -> bool:
    auth = request.headers.get('Authorization', '')
    token = auth[7:] if auth.startswith('Bearer ') else auth
    if not token:
        return False
    try:
        jwt.decode(token, CUBEJS_API_SECRET, algorithms=['HS256'])
        return True
    except Exception:
        return False


@app.before_request
def protect_api():
    if not request.path.startswith('/api/'):
        return None
    if request.method == 'OPTIONS':  # CORS preflight carries no credentials
        return None
    # Auth bootstrap: the token-issuing endpoint must be reachable WITHOUT a
    # token (otherwise a secret rotation locks everyone out). It enforces its
    # own auth: ALLOWED_USERS session or redirect into Google OAuth.
    if request.path == '/api/auth/dashboard-token':
        return None
    if session.get('user', {}).get('email') in ALLOWED_USERS:
        return None  # data-entry HTML pages (same-origin session)
    if _has_valid_api_token():
        return None
    return jsonify({'error': 'unauthorized'}), 401

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
    clear_cache('get_costs_history')


def auto_close_received_shipments():
    """Auto-close shipments whose ETA has passed and that have been paid.
    Called after payment insertion so shipment status updates immediately."""
    try:
        client.query(f"""
            UPDATE `{SHIPMENTS_TABLE}` s
            SET shipment_status = 'RECEIVED'
            WHERE s.estimated_arrival_date <= CURRENT_DATE()
              AND s.shipment_status NOT IN ('RECEIVED', 'INSPECTED', 'PUT_AWAY')
              AND (
                s.is_paid = TRUE
                OR EXISTS (
                  SELECT 1 FROM `{PAYMENTS_TABLE}` p
                  WHERE p.shipment_id = s.shipment_id
                )
              )
        """).result()
    except Exception as e:
        print(f"Auto-close shipments error (non-blocking): {e}")


def sync_shipment_paid_status(shipment_ids):
    """Sync is_paid and paid_date on shipments based on actual vendor payment records.
    
    Compares total payments for a shipment against its cost (cost_shipped + amazon_commission).
    If total_paid >= shipment_cost (within 0.01 tolerance), marks is_paid=TRUE and sets paid_date
    to the latest payment date. Otherwise resets is_paid=FALSE and paid_date=NULL.
    
    Args:
        shipment_ids: single string or list of shipment_id values to sync
    """
    if not shipment_ids:
        return
    if isinstance(shipment_ids, str):
        shipment_ids = [shipment_ids]
    # Deduplicate and filter None values
    shipment_ids = list(set(sid for sid in shipment_ids if sid))
    if not shipment_ids:
        return
    
    try:
        placeholders = ', '.join([f'@sid_{i}' for i in range(len(shipment_ids))])
        params = [bigquery.ScalarQueryParameter(f'sid_{i}', 'STRING', sid) for i, sid in enumerate(shipment_ids)]
        
        # Update shipments: mark as paid if total payments cover the cost
        query = f"""
            UPDATE `{SHIPMENTS_TABLE}` s
            SET
              s.is_paid = CASE
                WHEN COALESCE(pay.total_paid, 0) >= (COALESCE(s.cost_shipped, 0) + COALESCE(s.amazon_commission, 0)) - 0.01
                 AND COALESCE(pay.total_paid, 0) > 0
                THEN TRUE
                ELSE FALSE
              END,
              s.paid_date = CASE
                WHEN COALESCE(pay.total_paid, 0) >= (COALESCE(s.cost_shipped, 0) + COALESCE(s.amazon_commission, 0)) - 0.01
                 AND COALESCE(pay.total_paid, 0) > 0
                THEN pay.latest_payment_date
                ELSE NULL
              END
            FROM (
              SELECT shipment_id,
                     COALESCE(SUM(payment_amount), 0) AS total_paid,
                     MAX(payment_date) AS latest_payment_date
              FROM `{PAYMENTS_TABLE}`
              WHERE shipment_id IN ({placeholders})
              GROUP BY shipment_id
            ) pay
            WHERE s.shipment_id = pay.shipment_id
        """
        client.query(query, job_config=bigquery.QueryJobConfig(query_parameters=params)).result()
        
        # Handle shipments that have NO payment records at all (e.g. all payments deleted)
        # These won't be matched by the JOIN above, so update them separately
        query_no_payments = f"""
            UPDATE `{SHIPMENTS_TABLE}` s
            SET s.is_paid = FALSE, s.paid_date = NULL
            WHERE s.shipment_id IN ({placeholders})
              AND NOT EXISTS (
                SELECT 1 FROM `{PAYMENTS_TABLE}` p WHERE p.shipment_id = s.shipment_id
              )
        """
        client.query(query_no_payments, job_config=bigquery.QueryJobConfig(query_parameters=params)).result()
        
        print(f"Synced paid status for shipments: {shipment_ids}")
    except Exception as e:
        print(f"sync_shipment_paid_status error (non-blocking): {e}")

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

from config import PROJECT_ID, DATASET_ID, ORDERS_TABLE, OTHER_PO_TABLE, SHIPMENTS_TABLE, SHIPMENT_LINES_TABLE, SHIPMENT_OTHER_PO_TABLE, PAYMENTS_TABLE, PRODUCTS_TABLE, COSTS_HISTORY_TABLE, ALERTS_TABLE, PHRASE_NEGATIVES_TABLE
from research_match import research_match_predicate

client = bigquery.Client(project=PROJECT_ID)

@cache_result(ttl_seconds=3600)  # Cache for 1 hour
def get_lovs():
    """Fetch all LOVs and return them as a nested dictionary: {lov_set: [records]}"""
    try:
        query = f"""
        SELECT lov_set, value_id, value_caption, is_default, attr1_name, attr1_value, attr2_name, attr2_value
        FROM `{PROJECT_ID}.{DATASET_ID}.DE_LIST_OF_VALUES`
        ORDER BY lov_set, value_caption
        """
        results = list(client.query(query).result())
        
        lovs = {}
        for row in results:
            if row.lov_set not in lovs:
                lovs[row.lov_set] = []
            lovs[row.lov_set].append(dict(row))
        return lovs
    except Exception as e:
        print(f"Error fetching LOVs: {e}")
        return {}

@app.context_processor
def inject_lovs():
    """Inject LOVs into all templates automatically"""
    return dict(lovs=get_lovs())

def generate_id(prefix):
    """Generate a unique ID for records"""
    return f"{prefix}_{uuid.uuid4().hex[:12]}"

def generate_other_po_id(order_date, vendor_name, service_type):
    """Generate deterministic Other PO ID: OPO_YYYYMMDD_VENDOR_SERVICE_CCC"""
    import re
    date_part = str(order_date).replace('-', '') if order_date else ''
    vendor_clean = re.sub(r'[^A-Za-z0-9]', '', (vendor_name or 'UNKNOWN').split(',')[0].split(' ')[0]).upper()
    service_clean = re.sub(r'[^A-Za-z0-9]', '', str(service_type or 'OTHER')).upper()
    
    if len(service_clean) > 20:
        service_clean = service_clean[:20]
        
    base_id = f"PO_{date_part}_{vendor_clean}_{service_clean}"
    
    try:
        check_query = f"""
        SELECT COUNT(DISTINCT other_po_id) AS cnt
        FROM `{OTHER_PO_TABLE}`
        WHERE other_po_id LIKE @prefix
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter("prefix", "STRING", f"{base_id}%")
        ])
        result = list(client.query(check_query, job_config=jc).result())
        count = result[0].cnt if result else 0
        if count > 0:
            return f"{base_id}_{count:03d}"
    except Exception as e:
        print(f"Error checking other PO ID: {e}")
        
    return base_id


def generate_payment_id(payment_date, vendor_name, shipments, purchase_orders=None):
    """Generate a meaningful payment ID.
    Format: PAY_YYYYMMDD_VENDOR_PRODUCT[_YYYY_MMM][_NNN]
    - PRODUCT = product name if single product, parent name if single parent, or NP (N products) if multi
    - YYYY_MMM = reference month if all shipments/POs share the same month
    - _NNN appended only if duplicate exists for that date
    """
    import re
    from datetime import datetime
    
    MONTH_ABBR = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
                  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC']
    
    # Date part
    date_part = payment_date.replace('-', '')
    
    # Vendor part — first word, uppercased, alphanumeric only
    vendor_clean = re.sub(r'[^A-Za-z0-9]', '', (vendor_name or 'UNKNOWN').split(',')[0].split(' ')[0]).upper()
    
    # Product part — collect unique product names from shipment lines
    product_names = set()
    parent_names = set()
    for shp in (shipments or []):
        for line in (shp.get('lines') or []):
            pn = line.get('product_name', '')
            if pn:
                product_names.add(pn)
                parent_names.add(pn.split('(')[0].strip())
    
    is_shipment_payment = bool(shipments and len(shipments) > 0)

    if is_shipment_payment:
        # Shipment payments do not include the product part
        product_part = ""
    else:
        if len(product_names) == 1:
            raw = list(product_names)[0].split('(')[0].strip()
            product_part = "_" + re.sub(r'[^A-Za-z0-9]', '', raw)
        elif len(parent_names) == 1:
            raw = list(parent_names)[0]
            product_part = "_" + re.sub(r'[^A-Za-z0-9]', '', raw)
        else:
            product_part = f"_{len(product_names) or len(purchase_orders or [])}P"
    
    # Truncate product part to keep ID reasonable
    if len(product_part) > 20:
        product_part = product_part[:20]
    
    # Reference month part — if all shipments/POs share the same month
    month_part = ''
    ref_months = set()
    # Try shipment dates first
    for shp in (shipments or []):
        sd = shp.get('shipment_date')
        if sd:
            try:
                dt = datetime.strptime(str(sd)[:10], '%Y-%m-%d')
                ref_months.add((dt.year, dt.month))
            except (ValueError, TypeError):
                pass
    # If no shipments or mixed, try PO dates
    if not ref_months or len(ref_months) > 1:
        po_months = set()
        for po in (purchase_orders or []):
            od = po.get('order_date')
            if od:
                try:
                    dt = datetime.strptime(str(od)[:10], '%Y-%m-%d')
                    po_months.add((dt.year, dt.month))
                except (ValueError, TypeError):
                    pass
        if len(po_months) == 1:
            ref_months = po_months
    
    if len(ref_months) == 1:
        year, month = list(ref_months)[0]
        month_part = f"_{MONTH_ABBR[month - 1]}_{year}"
    
    base_id = f"PAY_{date_part}_{vendor_clean}{product_part}{month_part}"
    
    # Check for existing payments with same base prefix
    try:
        check_query = f"""
        SELECT COUNT(DISTINCT payment_id) AS cnt
        FROM `{PAYMENTS_TABLE}`
        WHERE payment_id LIKE @prefix
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter("prefix", "STRING", f"{base_id}%")
        ])
        result = list(client.query(check_query, job_config=jc).result())
        existing_count = result[0].cnt if result else 0
        if existing_count > 0:
            base_id = f"{base_id}_{existing_count + 1:03d}"
    except Exception:
        # Fallback: add short random suffix to guarantee uniqueness
        base_id = f"{base_id}_{uuid.uuid4().hex[:4]}"
    
    return base_id


@cache_result(ttl_seconds=600)  # Cache for 10 minutes (products rarely change)
def get_products():
    """Get all active products from DIM_PRODUCT, with parent hierarchy info"""
    query = f"""
    SELECT 
      product_id,
      asin,
      product_name,
      display_name,
      sku,
      brand,
      manufacturer,
      parent_name,
      product_short_name
    FROM `{PRODUCTS_TABLE}`
    WHERE is_active = TRUE
    ORDER BY COALESCE(parent_name, 'zzz'), product_short_name, product_name
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
      po.product_names_combined,
      po.quantity,
      po.unit_price,
      po.total_amount,
      COALESCE(po.adjustments, 0) as adjustments,
      po.currency,
      COALESCE(pt.total_paid, 0) as total_paid,
      COALESCE(st.total_shipment_cost, 0) as total_shipment_cost,
      COALESCE(st.paid_shipment_cost, 0) as paid_shipment_cost,
      (po.total_amount + COALESCE(po.adjustments, 0) + COALESCE(st.total_shipment_cost, 0)) as total_amount_with_shipments,
      (COALESCE(pt.total_paid, 0) + COALESCE(st.paid_shipment_cost, 0)) as total_paid_with_shipments,
      ((po.total_amount + COALESCE(po.adjustments, 0) + COALESCE(st.total_shipment_cost, 0)) - (COALESCE(pt.total_paid, 0) + COALESCE(st.paid_shipment_cost, 0))) as amount_remaining_with_shipments,
      (po.total_amount + COALESCE(po.adjustments, 0) - COALESCE(pt.total_paid, 0)) as amount_remaining,
      (po.total_amount + COALESCE(po.adjustments, 0) - COALESCE(pt.total_paid, 0)) as remaining_manufactured,
      (COALESCE(st.total_shipment_cost, 0) - COALESCE(st.paid_shipment_cost, 0)) as remaining_shipments,
      ABS(COALESCE(pt.total_paid, 0) - (po.total_amount + COALESCE(po.adjustments, 0))) < 0.01 as is_paid_in_full,
      COALESCE(sq.total_quantity_shipped, 0) as total_quantity_shipped,
      (po.quantity - COALESCE(sq.total_quantity_shipped, 0)) as remaining_quantity_to_ship,
      COALESCE(sqc.quantity_without_cost, 0) as quantity_without_cost,
      CASE 
        WHEN COALESCE(sqc.quantity_without_cost, 0) > 0 THEN
          COALESCE(sqc.quantity_without_cost, 0) * 
          COALESCE(
            poc.avg_unit_cost,
            lm.avg_unit_cost,
            NULL
          )
        ELSE NULL
      END as remaining_shipments_estimated,
      (ABS(COALESCE(pt.total_paid, 0) - (po.total_amount + COALESCE(po.adjustments, 0))) >= 0.01
       OR (COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) >= 0.01)
       OR (po.quantity - COALESCE(sq.total_quantity_shipped, 0) > 0)) as has_open_shipments,
      CASE 
        WHEN ABS(COALESCE(pt.total_paid, 0) - (po.total_amount + COALESCE(po.adjustments, 0))) < 0.01
         AND (COALESCE(st.total_shipment_cost, 0) = 0 OR ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01)
         AND (po.quantity - COALESCE(sq.total_quantity_shipped, 0) <= 0)
        THEN 'Fully Paid'
        WHEN ABS(COALESCE(pt.total_paid, 0) - (po.total_amount + COALESCE(po.adjustments, 0))) < 0.01
         AND (COALESCE(st.total_shipment_cost, 0) = 0 OR ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01)
        THEN 'PO Paid, Shipment Paid'
        WHEN ABS(COALESCE(pt.total_paid, 0) - (po.total_amount + COALESCE(po.adjustments, 0))) < 0.01
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
    FROM (
      SELECT
        purchase_order_id,
        ANY_VALUE(order_date) as order_date,
        ANY_VALUE(manufacturer_name) as manufacturer_name,
        MIN(product_id) as product_id,
        MIN(product_asin) as product_asin,
        -- For single-product POs, show the product name; for multi, show first
        ANY_VALUE(product_name) as product_name,
        -- Comma-separated product names for display
        STRING_AGG(DISTINCT product_name ORDER BY product_name) as product_names_combined,
        SUM(quantity) as quantity,
        CASE WHEN SUM(quantity) > 0 THEN SUM(total_amount) / SUM(quantity) ELSE 0 END as unit_price,
        SUM(total_amount) as total_amount,
        COALESCE(SUM(adjustments), 0) as adjustments,
        COALESCE(SUM(deposit), 0) as deposit,
        ANY_VALUE(remaining_payment_date) as remaining_payment_date,
        ANY_VALUE(currency) as currency,
        ANY_VALUE(payment_status) as payment_status,
        ANY_VALUE(notes) as notes,
        MIN(created_at) as created_at
      FROM `{ORDERS_TABLE}`
      GROUP BY purchase_order_id
    ) po
    LEFT JOIN payment_totals pt ON po.purchase_order_id = pt.purchase_order_id
    LEFT JOIN shipment_totals st ON po.purchase_order_id = st.purchase_order_id
    LEFT JOIN shipment_quantities sq ON po.purchase_order_id = sq.purchase_order_id
    LEFT JOIN shipment_quantities_without_cost sqc ON po.purchase_order_id = sqc.purchase_order_id
    LEFT JOIN po_shipment_unit_cost poc ON po.purchase_order_id = poc.purchase_order_id
    LEFT JOIN last_12_months_unit_cost lm ON TRUE
    """
    
    conditions = []
    if filter_open_shipments:
        # Open shipments: PO not fully paid OR shipments not fully paid OR quantity remaining to ship
        # Use ABS difference < 0.01 to handle floating point rounding issues
        conditions.append("(ABS(COALESCE(pt.total_paid, 0) - (po.total_amount + po.adjustments)) >= 0.01 OR (COALESCE(st.total_shipment_cost, 0) > 0 AND ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) >= 0.01) OR (po.quantity - COALESCE(sq.total_quantity_shipped, 0) > 0))")
    if filter_unpaid:
        conditions.append("((po.total_amount + po.adjustments + COALESCE(st.total_shipment_cost, 0)) - (COALESCE(pt.total_paid, 0) + COALESCE(st.paid_shipment_cost, 0))) > 0")
    
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
      (po.total_amount + COALESCE(po.adjustments, 0) + COALESCE(st.total_shipment_cost, 0)) as total_amount_with_shipments,
      (COALESCE(pt.total_paid, 0) + COALESCE(st.paid_shipment_cost, 0)) as total_paid_with_shipments,
      ((po.total_amount + COALESCE(po.adjustments, 0) + COALESCE(st.total_shipment_cost, 0)) - (COALESCE(pt.total_paid, 0) + COALESCE(st.paid_shipment_cost, 0))) as amount_remaining_with_shipments,
      (po.total_amount + COALESCE(po.adjustments, 0) - COALESCE(pt.total_paid, 0)) as amount_remaining,
      (po.total_amount + COALESCE(po.adjustments, 0) - COALESCE(pt.total_paid, 0)) as remaining_manufactured,
      (COALESCE(st.total_shipment_cost, 0) - COALESCE(st.paid_shipment_cost, 0)) as remaining_shipments,
      ABS(COALESCE(pt.total_paid, 0) - (po.total_amount + COALESCE(po.adjustments, 0))) < 0.01 as is_paid_in_full,
      COALESCE(sq.total_quantity_shipped, 0) as total_quantity_shipped,
      (po.quantity - COALESCE(sq.total_quantity_shipped, 0)) as remaining_quantity_to_ship,
      COALESCE(sqc.quantity_without_cost, 0) as quantity_without_cost,
      CASE 
        WHEN COALESCE(sqc.quantity_without_cost, 0) > 0 THEN
          COALESCE(sqc.quantity_without_cost, 0) * 
          COALESCE(
            poc.avg_unit_cost,
            lm.avg_unit_cost,
            NULL
          )
        ELSE NULL
      END as remaining_shipments_estimated,
      CASE 
        WHEN ABS(COALESCE(pt.total_paid, 0) - (po.total_amount + COALESCE(po.adjustments, 0))) < 0.01
         AND (COALESCE(st.total_shipment_cost, 0) = 0 OR ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01)
         AND (po.quantity - COALESCE(sq.total_quantity_shipped, 0) <= 0)
        THEN 'Fully Paid'
        WHEN ABS(COALESCE(pt.total_paid, 0) - (po.total_amount + COALESCE(po.adjustments, 0))) < 0.01
         AND (COALESCE(st.total_shipment_cost, 0) = 0 OR ABS(COALESCE(st.paid_shipment_cost, 0) - COALESCE(st.total_shipment_cost, 0)) < 0.01)
        THEN 'PO Paid, Shipment Paid'
        WHEN ABS(COALESCE(pt.total_paid, 0) - (po.total_amount + COALESCE(po.adjustments, 0))) < 0.01
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
    FROM (
      SELECT
        purchase_order_id,
        ANY_VALUE(order_date) as order_date,
        ANY_VALUE(manufacturer_name) as manufacturer_name,
        STRING_AGG(DISTINCT product_name ORDER BY product_name) as product_names_combined,
        SUM(quantity) as quantity,
        SUM(COALESCE(ready_quantity, 0)) as ready_quantity,
        CASE WHEN SUM(quantity) > 0 THEN SUM(total_amount) / SUM(quantity) ELSE 0 END as unit_price,
        SUM(total_amount) as total_amount,
        COALESCE(SUM(adjustments), 0) as adjustments,
        COALESCE(SUM(deposit), 0) as deposit,
        ANY_VALUE(remaining_payment_date) as remaining_payment_date,
        ANY_VALUE(currency) as currency,
        ANY_VALUE(notes) as notes,
        MIN(created_at) as created_at,
        COUNT(*) as line_count
      FROM `{ORDERS_TABLE}`
      WHERE purchase_order_id = @po_id
      GROUP BY purchase_order_id
    ) po
    LEFT JOIN payment_totals pt ON po.purchase_order_id = pt.purchase_order_id
    LEFT JOIN shipment_totals st ON po.purchase_order_id = st.purchase_order_id
    LEFT JOIN shipment_quantities sq ON po.purchase_order_id = sq.purchase_order_id
    LEFT JOIN shipment_quantities_without_cost sqc ON po.purchase_order_id = sqc.purchase_order_id
    LEFT JOIN po_shipment_unit_cost poc ON po.purchase_order_id = poc.purchase_order_id
    LEFT JOIN last_12_months_unit_cost lm ON TRUE
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("po_id", "STRING", po_id)
        ]
    )
    po_result = list(client.query(po_query, job_config=job_config).result())
    if not po_result:
        return None, [], [], []
    
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
    po['ready_quantity'] = int(po.get('ready_quantity', 0) or 0)
    
    # Get individual product lines for this PO
    lines_query = f"""
    SELECT 
      o.product_id, o.product_asin, o.product_name, o.quantity, o.unit_price, o.total_amount, o.ready_quantity,
      COALESCE(SUM(sl.quantity_shipped), 0) as quantity_shipped
    FROM `{ORDERS_TABLE}` o
    LEFT JOIN `{SHIPMENT_LINES_TABLE}` sl 
      ON o.purchase_order_id = sl.purchase_order_id AND o.product_id = sl.product_id
    WHERE o.purchase_order_id = @po_id
    GROUP BY o.product_id, o.product_asin, o.product_name, o.quantity, o.unit_price, o.total_amount, o.ready_quantity
    ORDER BY o.product_name
    """
    lines_result = client.query(lines_query, job_config=job_config).result()
    product_lines = [dict(row) for row in lines_result]
    
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
    
    return po, payments, shipments, product_lines


def insert_purchase_order(data, product_lines=None):
    """Insert purchase order data into BigQuery.
    
    Supports multi-product POs via product_lines parameter.
    If product_lines is provided, inserts one row per line sharing the same PO ID.
    Falls back to single-product mode using data dict for backward compatibility.
    
    Args:
        data: dict with header fields (order_date, manufacturer_name, currency, payment_status, notes)
        product_lines: list of dicts, each with {product_id, quantity, total_amount}
    """
    order_date = data.get('order_date')
    manufacturer_name = data.get('manufacturer_name')
    
    # Validate required header fields
    if not order_date:
        return ['Order date is required'], None
    if not manufacturer_name:
        return ['Manufacturer name is required'], None
    
    # Build product lines list
    if not product_lines:
        # Backward compatibility: single-product mode from data dict
        product_lines = [{
            'product_id': data.get('product_id'),
            'quantity': data.get('quantity', 0),
            'total_amount': data.get('total_amount', 0),
        }]
    
    # Resolve product info for each line
    resolved_lines = []
    total_quantity = 0
    grand_total = 0
    
    for line in product_lines:
        product_id = line.get('product_id')
        quantity = float(line.get('quantity', 0))
        line_amount = float(line.get('total_amount', 0))
        product_asin = None
        product_name = None
        product_sku = None
        
        if quantity <= 0:
            return ['Each product line must have quantity > 0'], None
        if line_amount < 0:
            return ['Amount cannot be negative'], None
        
        if product_id:
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
                product_name = result[0].sku or result[0].display_name or result[0].product_name
        
        unit_price = float(line_amount / quantity if quantity > 0 else 0)
        total_quantity += quantity
        grand_total += line_amount
        
        resolved_lines.append({
            'product_id': int(product_id) if product_id else None,
            'product_asin': product_asin,
            'product_name': product_name,
            'product_sku': product_sku,
            'quantity': int(quantity),
            'ready_quantity': int(line.get('ready_quantity', 0)) if line.get('ready_quantity') else 0,
            'unit_price': unit_price,
            'total_amount': float(line_amount),
        })
    
    if not resolved_lines:
        return ['At least one product line is required'], None
    
    # Generate PO ID: PO_YYYYMMDD_MANUFACTURER_PRODUCT_QTY (single line) or PO_YYYYMMDD_MANUFACTURER_QTY (multi)
    if not data.get('purchase_order_id'):
        date_str = order_date.replace('-', '') if order_date else ''
        mfr_str = (manufacturer_name or 'UNKNOWN').replace(' ', '_').replace('-', '_')[:20]
        qty_str = str(int(total_quantity))
        # Include product name when single product line for easy identification
        if len(resolved_lines) == 1 and resolved_lines[0].get('product_name'):
            prod_str = resolved_lines[0]['product_name'].replace(' ', '').replace('-', '')[:20]
            base_po_id = f"PO_{date_str}_{mfr_str}_{prod_str}_{qty_str}"
        else:
            base_po_id = f"PO_{date_str}_{mfr_str}_{qty_str}"
        
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
    
    # Build rows — one per product line, all sharing the same PO header fields
    rows = []
    for line in resolved_lines:
        row = {
            'purchase_order_id': po_id,
            'order_date': order_date,
            'manufacturer_name': manufacturer_name,
            'quantity': line['quantity'],
            'ready_quantity': line['ready_quantity'],
            'unit_price': line['unit_price'],
            'total_amount': line['total_amount'],
            'currency': data.get('currency', 'USD'),
            'payment_status': data.get('payment_status', 'PENDING'),
        }
        if line['product_id']:
            row['product_id'] = line['product_id']
        if line['product_asin']:
            row['product_asin'] = line['product_asin']
        if line['product_name']:
            row['product_name'] = line['product_name']
        if data.get('notes'):
            row['notes'] = data.get('notes')
        rows.append(row)
    
    # Use batch loading
    table_ref = client.get_table(ORDERS_TABLE)
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=False,
        schema=table_ref.schema
    )
    job = client.load_table_from_json(rows, table_ref, job_config=job_config)
    job.result()
    
    if job.errors:
        return job.errors, po_id
    
    return [], po_id


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
    if 'adjustments' in data:
        adj_val = float(data.get('adjustments') or 0)
        updates.append('adjustments = @adjustments')
        params.append(bigquery.ScalarQueryParameter("adjustments", "FLOAT64", adj_val))
    if 'deposit' in data:
        dep_val = float(data.get('deposit') or 0)
        updates.append('deposit = @deposit')
        params.append(bigquery.ScalarQueryParameter("deposit", "FLOAT64", dep_val))
    if data.get('remaining_payment_date'):
        updates.append('remaining_payment_date = @remaining_payment_date')
        params.append(bigquery.ScalarQueryParameter("remaining_payment_date", "DATE", data.get('remaining_payment_date')))
    elif 'remaining_payment_date' in data and not data.get('remaining_payment_date'):
        updates.append('remaining_payment_date = NULL')
    if data.get('estimated_arrival_date'):
        updates.append('estimated_arrival_date = @estimated_arrival_date')
        params.append(bigquery.ScalarQueryParameter("estimated_arrival_date", "DATE", data.get('estimated_arrival_date')))
    elif 'estimated_arrival_date' in data and not data.get('estimated_arrival_date'):
        updates.append('estimated_arrival_date = NULL')
    
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
def get_open_pos_for_shipment(include_all=False):
    """Get POs available for shipment, plus product packaging info.
    
    Args:
        include_all: If True, return all non-cancelled POs (even fully shipped).
                     If False, only POs with remaining quantity > 0.
    """
    remaining_filter = ""
    if not include_all:
        remaining_filter = "AND (po.quantity - COALESCE(sh.total_shipped, 0)) > 0"
    
    query = f"""
    WITH shipped AS (
      SELECT l.purchase_order_id,
             COALESCE(l.product_id, po.product_id) AS product_id,
             SUM(COALESCE(l.quantity_shipped, 0)) as total_shipped
      FROM `{SHIPMENT_LINES_TABLE}` l
      JOIN `{ORDERS_TABLE}` po ON l.purchase_order_id = po.purchase_order_id
      GROUP BY 1, 2
    )
    SELECT po.purchase_order_id, po.product_id, po.product_name, COALESCE(dp.asin, po.product_asin) as product_asin,
           po.quantity as order_quantity,
           po.total_amount,
           po.manufacturer_name,
           COALESCE(sh.total_shipped, 0) as total_shipped,
           (po.quantity - COALESCE(sh.total_shipped, 0)) as remaining_quantity,
           dp.package_quantity, dp.package_cubic_feet
    FROM `{ORDERS_TABLE}` po
    LEFT JOIN shipped sh ON po.purchase_order_id = sh.purchase_order_id
                         AND po.product_id = sh.product_id
    LEFT JOIN `{PRODUCTS_TABLE}` dp ON po.product_id = dp.product_id
    WHERE po.payment_status != 'CANCELLED'
      {remaining_filter}
    ORDER BY po.order_date DESC
    """
    result = client.query(query).result()
    return [dict(row) for row in result]


@cache_result(ttl_seconds=60)  # Cache for 1 minute (cleared on updates)
def get_all_shipments(status_filter='open', year_filter=None, shipment_id_filter=None):
    """Get all shipments with aggregated line info for the shipments list page.
    
    Args:
        status_filter: 'open' (default) = exclude PUT_AWAY/RECEIVED/INSPECTED, 'all' = everything
        year_filter: year string (e.g. '2025') or 'all' for no year filter
        shipment_id_filter: string to partial match on shipment_id
    """
    # Auto-update paid+arrived shipments to RECEIVED
    auto_close_received_shipments()
    
    where_clauses = []
    if status_filter == 'open':
        where_clauses.append("s.shipment_status NOT IN ('PUT_AWAY', 'RECEIVED', 'INSPECTED')")
    if year_filter and year_filter != 'all':
        where_clauses.append(f"EXTRACT(YEAR FROM s.shipment_date) = {int(year_filter)}")
    if shipment_id_filter:
        # Prevent SQL injection by escaping single quotes and removing dangerous characters
        safe_shipment_id = shipment_id_filter.replace("'", "''")
        where_clauses.append(f"UPPER(s.shipment_id) LIKE UPPER('%{safe_shipment_id}%')")
    
    where_sql = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""
    
    query = f"""
    SELECT s.*,
           COALESCE(agg.line_items, []) as line_items,
           COALESCE(agg.line_count, 0) as line_count,
           -- Derive paid status from actual vendor payment records
           COALESCE(pay_agg.payment_count, 0) as payment_count,
           COALESCE(pay_agg.total_paid, 0) as total_paid,
           (COALESCE(pay_agg.payment_count, 0) > 0) as has_payments
    FROM `{SHIPMENTS_TABLE}` s
    LEFT JOIN (
      SELECT sl.shipment_id,
             ARRAY_AGG(
               CASE WHEN sl.line_id IS NOT NULL THEN
                 STRUCT(
                   sl.purchase_order_id, sl.quantity_shipped, sl.allocated_cost,
                   po.product_name, po.product_asin
                 )
               END IGNORE NULLS
             ) as line_items,
             COUNT(DISTINCT sl.line_id) as line_count
      FROM `{SHIPMENT_LINES_TABLE}` sl
      LEFT JOIN `{ORDERS_TABLE}` po ON sl.purchase_order_id = po.purchase_order_id AND (sl.product_id = po.product_id OR sl.product_id IS NULL)
      GROUP BY sl.shipment_id
    ) agg ON s.shipment_id = agg.shipment_id
    LEFT JOIN (
      SELECT shipment_id, COUNT(*) as payment_count, SUM(payment_amount) as total_paid
      FROM `{PAYMENTS_TABLE}`
      WHERE shipment_id IS NOT NULL
      GROUP BY shipment_id
    ) pay_agg ON s.shipment_id = pay_agg.shipment_id
    {where_sql}
    ORDER BY s.shipment_date DESC
    """
    result = client.query(query).result()
    return [dict(row) for row in result]


@app.route('/shipments', methods=['GET'])
@login_required
def shipments_list():
    """Standalone shipments list page"""
    status_filter = request.args.get('filter', 'open')  # default: open shipments
    # Year filter — default to current year
    from datetime import datetime as dt
    current_year = dt.now().year
    year_filter = request.args.get('year', str(current_year))
    shipment_id_filter = request.args.get('shipment_id', '').strip()
    
    shipments = get_all_shipments(status_filter=status_filter, year_filter=year_filter, shipment_id_filter=shipment_id_filter)
    
    # Apply paid filter client-side (post-query, since has_payments is computed)
    paid_filter = request.args.get('paid', 'all')  # 'paid', 'unpaid', 'all'
    if paid_filter == 'paid':
        shipments = [s for s in shipments if s.get('has_payments')]
    elif paid_filter == 'unpaid':
        shipments = [s for s in shipments if not s.get('has_payments')]
    
    # Available years for the filter (last 3 years + all)
    available_years = [str(y) for y in range(current_year, current_year - 4, -1)]
    
    return render_template('shipments_list.html', 
                         shipments=shipments, 
                         status_filter=status_filter,
                         year_filter=year_filter,
                         paid_filter=paid_filter,
                         shipment_id_filter=shipment_id_filter,
                         available_years=available_years)


def insert_shipment(data, lines, other_po_ids=None):
    """Insert shipment header + lines into BigQuery.

    Args:
        data: dict with shipment header fields (shipment_date, shipment_type, cost_shipped, etc.)
        lines: list of dicts with [{'purchase_order_id': ..., 'quantity_shipped': ...}, ...]
        other_po_ids: optional list of DE_OTHER_PO ids whose total_amount is rolled into landed cost
    """
    import math
    
    shipment_id = data.get('shipment_id') or generate_id('SHP')
    shipment_date = data.get('shipment_date')
    
    kg_price = float(data.get('kg_price')) if data.get('kg_price') else None
    cost_shipped = float(data.get('cost_shipped')) if data.get('cost_shipped') else None
    amazon_commission = float(data.get('amazon_commission')) if data.get('amazon_commission') else 0.0
    
    # --- Roll connected Other PO amounts into the allocable cost ---
    other_po_ids = [str(pid) for pid in (other_po_ids or []) if pid]
    other_po_total = 0.0
    if other_po_ids:
        opo_ph = ', '.join([f'@opo_{i}' for i in range(len(other_po_ids))])
        opo_q = f"SELECT COALESCE(SUM(total_amount), 0) AS s FROM `{OTHER_PO_TABLE}` WHERE other_po_id IN ({opo_ph})"
        opo_params = [bigquery.ScalarQueryParameter(f'opo_{i}', 'STRING', pid) for i, pid in enumerate(other_po_ids)]
        opo_rows = list(client.query(opo_q, job_config=bigquery.QueryJobConfig(query_parameters=opo_params)).result())
        other_po_total = float(opo_rows[0].s) if opo_rows else 0.0

    # total_cost = shipment cost + amazon commission + connected Other POs (used for allocation)
    total_cost = (cost_shipped or 0) + amazon_commission + other_po_total
    
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
    
    # --- Look up product cubic feet for each line ---
    # Collect all product_ids specified in lines (for multi-product POs)
    # Also collect po_ids for fallback lookup
    po_ids = list(set(line['purchase_order_id'] for line in lines))
    line_product_ids = [int(line.get('product_id', 0)) for line in lines if line.get('product_id')]
    
    # Query product info directly from DIM_PRODUCT for specified product_ids
    product_info_by_id = {}
    if line_product_ids:
        pid_placeholders = ', '.join([f'@pid_{i}' for i in range(len(line_product_ids))])
        pid_query = f"""
        SELECT product_id, package_quantity, package_cubic_feet
        FROM `{PRODUCTS_TABLE}`
        WHERE product_id IN ({pid_placeholders})
        """
        pid_params = [bigquery.ScalarQueryParameter(f'pid_{i}', 'INT64', pid) for i, pid in enumerate(line_product_ids)]
        pid_config = bigquery.QueryJobConfig(query_parameters=pid_params)
        for row in client.query(pid_query, job_config=pid_config).result():
            product_info_by_id[row.product_id] = dict(row)
    
    # Fallback: query product info via PO → DIM_PRODUCT (for lines without product_id)
    product_info_by_po = {}
    placeholders = ', '.join([f'@po_{i}' for i in range(len(po_ids))])
    product_query = f"""
    SELECT po.purchase_order_id, po.product_id, dp.package_quantity, dp.package_cubic_feet
    FROM `{ORDERS_TABLE}` po
    LEFT JOIN `{PRODUCTS_TABLE}` dp ON po.product_id = dp.product_id
    WHERE po.purchase_order_id IN ({placeholders})
    """
    params = [bigquery.ScalarQueryParameter(f'po_{i}', 'STRING', po_id) for i, po_id in enumerate(po_ids)]
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    for row in client.query(product_query, job_config=job_config).result():
        r = dict(row)
        # For multi-product POs, key by (po_id, product_id)
        product_info_by_po[(r['purchase_order_id'], r.get('product_id'))] = r
    
    # --- Build shipment lines with cubic-feet data ---
    line_rows = []
    for line in lines:
        po_id = line['purchase_order_id']
        qty = int(line.get('quantity_shipped', 0))
        line_product_id = int(line.get('product_id', 0)) if line.get('product_id') else None
        
        # Look up product info: prefer direct product_id, then PO+product_id, then first PO match
        if line_product_id and line_product_id in product_info_by_id:
            product_info = product_info_by_id[line_product_id]
        elif line_product_id and (po_id, line_product_id) in product_info_by_po:
            product_info = product_info_by_po[(po_id, line_product_id)]
        else:
            # Fallback: find any product_info for this PO
            product_info = next((v for k, v in product_info_by_po.items() if k[0] == po_id), {})
        
        pkg_qty = product_info.get('package_quantity') or 1
        cubic_ft = product_info.get('package_cubic_feet')
        
        num_cartons = math.ceil(qty / pkg_qty) if pkg_qty > 0 else None
        total_cubic_ft = (num_cartons * cubic_ft) if (num_cartons and cubic_ft) else None
        
        line_row = {
            'line_id': generate_id('SHL'),
            'shipment_id': shipment_id,
            'purchase_order_id': po_id,
            'quantity_shipped': qty,
            'num_cartons': num_cartons,
            'cubic_feet_per_carton': cubic_ft,
            'total_cubic_feet': total_cubic_ft,
            'allocated_cost': None,  # Calculated below
        }
        if line_product_id:
            line_row['product_id'] = line_product_id
        line_rows.append(line_row)
    
    # --- Calculate cubic-feet-based cost allocation ---
    if total_cost > 0:
        grand_total_cubic = sum(lr.get('total_cubic_feet', 0) or 0 for lr in line_rows)
        if grand_total_cubic > 0:
            for lr in line_rows:
                lr_cubic = lr.get('total_cubic_feet', 0) or 0
                lr['allocated_cost'] = round((lr_cubic / grand_total_cubic) * total_cost, 2)
        else:
            # Fallback: equal split if no cubic feet data
            per_line = round(total_cost / len(line_rows), 2)
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
        'amazon_commission': amazon_commission,
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
    if data.get('deliverer'):
        header_row['deliverer'] = data.get('deliverer')
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

    # --- Insert connected Other PO junction rows ---
    if other_po_ids:
        link_rows = [{
            'link_id': generate_id('SOP'),
            'shipment_id': shipment_id,
            'other_po_id': pid,
        } for pid in other_po_ids]
        sop_table_ref = client.get_table(SHIPMENT_OTHER_PO_TABLE)
        sop_job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            autodetect=False,
            schema=sop_table_ref.schema,
        )
        sop_job = client.load_table_from_json(link_rows, sop_table_ref, job_config=sop_job_config)
        sop_job.result()
        if sop_job.errors:
            return sop_job.errors, shipment_id

    # --- Cleanup APPROVED schedules to prevent duplication ---
    try:
        product_ids = [str(l.get('product_id')) for l in lines if l.get('product_id')]
        if product_ids:
            pid_list_str = ', '.join(product_ids)
            scheduled_table = f"{PROJECT_ID}.{DATASET_ID}.DE_SCHEDULED_SHIPMENTS"
            product_table = f"{PROJECT_ID}.{DATASET_ID}.DIM_PRODUCT"
            
            # Delete any APPROVED suggestions for the ASINs included in this shipment
            # We also clear cache so the dashboard immediately reflects the changes
            delete_query = f"""
                DELETE FROM `{scheduled_table}`
                WHERE status = 'APPROVED'
                  AND asin IN (
                      SELECT asin FROM `{product_table}`
                      WHERE product_id IN ({pid_list_str})
                  )
            """
            client.query(delete_query).result()
            print(f"Cleaned up APPROVED scheduled shipments for product_ids: {pid_list_str}")
    except Exception as e:
        print(f"Warning: Failed to cleanup scheduled shipments: {e}")
        
    clear_data_cache()
    
    return [], shipment_id


def insert_payment(data):
    """Insert vendor payment data into BigQuery"""
    payment_date = data.get('payment_date')
    
    # Handle vendor_name from checkboxes (can be list or single value)
    # vendor_name is REQUIRED, so validate it exists
    vendor_name_raw = data.get('vendor_name')
    if isinstance(vendor_name_raw, list):
        vendor_name = ', '.join(vendor_name_raw) if vendor_name_raw else None
    elif vendor_name_raw:
        vendor_name = str(vendor_name_raw)
    else:
        vendor_name = None

    payment_id = data.get('payment_id')
    if not payment_id:
        if vendor_name and payment_date:
            ships = []
            if data.get('shipment_id'):
                sd = get_shipment_details(data.get('shipment_id'))
                if sd: ships.append(sd)
            pos = []
            if data.get('purchase_order_id'):
                po = get_po_details(data.get('purchase_order_id'))
                if po and po[0]: pos.append(po[0])
            payment_id = generate_payment_id(payment_date, vendor_name, ships, pos)
        else:
            payment_id = generate_id('PAY')
            
    payment_amount = float(data.get('payment_amount', 0))
    bank_fee = float(data.get('bank_fee')) if data.get('bank_fee') else None
    
    # Validate required fields
    if not payment_date:
        return ['Payment date is required'], None
    # At least one of purchase_order_id or shipment_id must be provided
    has_po = bool(data.get('purchase_order_id'))
    has_shipment = bool(data.get('shipment_id'))
    # PO or shipment link is optional for standalone adjustments/discounts
    if payment_amount == 0:
        return ['Payment amount cannot be zero'], None
    if not vendor_name:
        return ['At least one vendor must be selected'], None
    
    row = {
        'payment_id': payment_id,
        'payment_date': payment_date,
        'payment_amount': float(payment_amount),
        'vendor_name': vendor_name,  # Required field - always included
        'currency': data.get('currency', 'USD'),
    }
    
    # Add linkage fields (at least one will be present)
    if has_po:
        row['purchase_order_id'] = data.get('purchase_order_id')
    if has_shipment:
        row['shipment_id'] = data.get('shipment_id')
    
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
    
    # Sync shipment paid status if this payment is linked to a shipment
    if has_shipment:
        sync_shipment_paid_status(data.get('shipment_id'))
    
    # Auto-close shipments that are now paid and past ETA
    auto_close_received_shipments()
    
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
      SUM(COALESCE(s.cost_shipped, 0) + COALESCE(s.amazon_commission, 0)) as total_cost_shipped,
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


@app.route('/api/auth/dashboard-token')
def auth_dashboard_token():
    """Issue a JWT token for the React Dashboard/Cube.js"""
    try:
        user_email = session.get('user', {}).get('email')
        if not user_email or user_email not in ALLOWED_USERS:
            # Save destination and skip login.html by going straight to Google Auth
            session['next_url'] = request.url
            return redirect(url_for('auth_google'))
            
        # Create token valid for 30 days
        payload = {
            'email': user_email,
            'exp': datetime.utcnow() + timedelta(days=30),
            'iat': datetime.utcnow()
        }
        
        token = jwt.encode(payload, CUBEJS_API_SECRET, algorithm='HS256')
        
        # Get redirect URL, default to local dev if not set
        dashboard_url = os.environ.get('VITE_DASHBOARD_URL', 'http://localhost:5173')
        
        # Determine if we should append properly
        separator = '&' if '?' in dashboard_url else '?'
        redirect_url = f"{dashboard_url}{separator}token={token}"
        
        return redirect(redirect_url)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


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
        
        # Redirect to original destination if saved, otherwise index
        next_url = session.pop('next_url', url_for('index'))
        return redirect(next_url)
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
    
    # Product & family filters
    family_filter = request.args.get('family', '')
    product_filter = request.args.get('product', '')
    
    limit = request.args.get('limit', type=int)
    orders = get_purchase_orders_with_status(filter_open_shipments=filter_open, filter_unpaid=False, limit=limit)
    
    # Build product/family filter options from DIM_PRODUCT
    try:
        products = get_products()
    except Exception as e:
        print(f"Error fetching products for filters: {e}")
        products = []
    
    # Build lookups by product_id (reliable join key between PO and DIM_PRODUCT)
    families = sorted(set(p['parent_name'] for p in products if p.get('parent_name')))
    
    # product_id → family (parent_name)
    pid_to_family = {}
    # product_id → short_name (for display)
    pid_to_short_name = {}
    for p in products:
        pid = p.get('product_id')
        if pid:
            pid_to_family[pid] = p.get('parent_name', '')
            pid_to_short_name[pid] = p.get('product_short_name') or p.get('product_name') or ''
    
    # Build dropdown options: list of (product_id, short_name) tuples
    if family_filter:
        dropdown_products = sorted(
            [(pid, sn) for pid, sn in pid_to_short_name.items() if pid_to_family.get(pid) == family_filter],
            key=lambda x: x[1]
        )
    else:
        dropdown_products = sorted(pid_to_short_name.items(), key=lambda x: x[1])
    
    # Apply product/family filter to orders by product_id
    if product_filter:
        # product_filter is a product_id (as string)
        try:
            filter_pid = int(product_filter)
        except (ValueError, TypeError):
            filter_pid = None
        if filter_pid:
            orders = [o for o in orders if o.get('product_id') == filter_pid]
    elif family_filter:
        # Get all product_ids belonging to the selected family
        family_pids = set(pid for pid, fam in pid_to_family.items() if fam == family_filter)
        orders = [o for o in orders if o.get('product_id') in family_pids]
    
    # Also fetch Other POs for the dashboard
    other_pos_query = f"""
    WITH payment_totals AS (
      SELECT purchase_order_id, SUM(payment_amount) as total_paid
      FROM `{PAYMENTS_TABLE}`
      GROUP BY purchase_order_id
    )
    SELECT opo.*, COALESCE(pt.total_paid, 0) as total_paid
    FROM `{OTHER_PO_TABLE}` opo
    LEFT JOIN payment_totals pt ON opo.other_po_id = pt.purchase_order_id
    ORDER BY opo.order_date DESC
    """
    other_pos = client.query(other_pos_query).result()
    other_pos = [dict(row) for row in other_pos]
    
    # Calculate remaining amounts (based on filtered orders)
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
                         other_pos=other_pos,
                         filter_open=filter_open,
                         family_filter=family_filter,
                         product_filter=product_filter,
                         families=families,
                         dropdown_products=dropdown_products,
                         remaining_sylvia=remaining_sylvia,
                         remaining_anna=remaining_anna,
                         remaining_shipments_estimated_total=remaining_shipments_estimated_total,
                         open_shipments=open_shipments)


@app.route('/po/<po_id>')
@login_required
def po_details(po_id):
    """PO Details page - shows PO, payments, and shipments"""
    po, payments, shipments, product_lines = get_po_details(po_id)
    
    if not po:
        flash(f'Purchase Order {po_id} not found', 'error')
        return redirect(url_for('index'))
    
    # Get products for the product dropdown
    try:
        products = get_products()
    except Exception as e:
        flash(f'Warning: Could not load products from DIM_PRODUCT: {str(e)}', 'error')
        products = []
    
    return render_template('po_details.html', po=po, payments=payments, shipments=shipments, products=products, product_lines=product_lines)


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


def insert_other_po(data):
    """Insert a new Other PO row. Returns (errors_list, other_po_id)."""
    order_date = data.get('order_date')
    service_type = data.get('service_type')
    supplier_name = data.get('supplier_name')

    if not order_date or not service_type or not supplier_name:
        return (['Order date, service type, and supplier are required'], None)

    other_po_id = data.get('other_po_id') or generate_other_po_id(order_date, supplier_name, service_type)

    # Normalize product_asins: list → join; string → use as-is; empty → None
    product_asins_raw = data.get('product_asins')
    if isinstance(product_asins_raw, list):
        product_asins = ', '.join(product_asins_raw) if product_asins_raw else None
    elif isinstance(product_asins_raw, str):
        product_asins = product_asins_raw if product_asins_raw else None
    else:
        product_asins = None

    row = {
        'other_po_id': other_po_id,
        'order_date': order_date,
        'service_type': service_type,
        'supplier_name': supplier_name,
        'product_asins': product_asins,
        'total_amount': float(data.get('total_amount', 0)),
        'currency': data.get('currency', 'USD'),
        'payment_status': 'PENDING',
        'notes': data.get('notes', ''),
        'created_at': datetime.utcnow().isoformat()
    }

    table_ref = client.get_table(OTHER_PO_TABLE)
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=False,
        schema=table_ref.schema
    )
    job = client.load_table_from_json([row], table_ref, job_config=job_config)
    job.result()
    return (job.errors or [], other_po_id)


def delete_other_po_record(po_id):
    """Delete an Other PO and its related payments. Returns errors_list (empty on success)."""
    jc = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
    )
    client.query(f"DELETE FROM `{PAYMENTS_TABLE}` WHERE purchase_order_id = @po_id", job_config=jc).result()
    client.query(f"DELETE FROM `{OTHER_PO_TABLE}` WHERE other_po_id = @po_id", job_config=jc).result()
    return []


@app.route('/other_po/new', methods=['GET', 'POST'])
@login_required
def new_other_po():
    """Create a new record in DE_OTHER_PO"""
    if request.method == 'POST':
        try:
            data = request.form.to_dict()
            # Pass product_asins as a list (from multi-select form field)
            data['product_asins'] = request.form.getlist('product_asins')
            errors, other_po_id = insert_other_po(data)
            if errors:
                flash(f'Error inserting Other PO: {errors}', 'error')
                if 'required' in str(errors):
                    return render_template('other_po_form.html')
            else:
                clear_data_cache()
                flash(f'Other PO {other_po_id} created successfully!', 'success')
                return redirect(url_for('other_po_details', po_id=other_po_id))
        except Exception as e:
            flash(f'Error: {str(e)}', 'error')
    
    try:
        products = get_products()
    except Exception as e:
        flash(f'Warning: Could not load products from DIM_PRODUCT: {str(e)}', 'error')
        products = []
    
    return render_template('other_po_form.html', products=products)

@app.route('/other_po/<po_id>')
@login_required
def other_po_details(po_id):
    """View details of a specific Other PO"""
    query = f"""
    SELECT opo.*
    FROM `{OTHER_PO_TABLE}` opo
    WHERE opo.other_po_id = @po_id
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("po_id", "STRING", po_id)
        ]
    )
    po_results = list(client.query(query, job_config=job_config).result())
    
    if not po_results:
        flash(f'Other PO {po_id} not found', 'error')
        return redirect(url_for('index'))
        
    po = dict(po_results[0])
    
    # Get payments
    payments_query = f"""
    SELECT p.*
    FROM `{PAYMENTS_TABLE}` p
    WHERE p.purchase_order_id = @po_id
    ORDER BY p.payment_date DESC
    """
    payments = list(client.query(payments_query, job_config=job_config).result())
    payments = [dict(p) for p in payments]
    
    # Calculate sum of payments
    total_paid = sum(p.get('payment_amount', 0) for p in payments)
    
    return render_template('other_po_details.html', po=po, payments=payments, total_paid=total_paid)

@app.route('/other_po/<po_id>/delete', methods=['POST'])
@login_required
def delete_other_po(po_id):
    """Delete an Other PO and its payments"""
    try:
        errors = delete_other_po_record(po_id)
        if errors:
            flash(f'Error deleting Other PO: {errors}', 'error')
        else:
            clear_data_cache()
            flash(f'Other PO {po_id} and related payments deleted successfully', 'success')
    except Exception as e:
        flash(f'Error deleting Other PO: {str(e)}', 'error')

    return redirect(url_for('index'))


@app.route('/api/other_po', methods=['GET'])
def api_other_po_list():
    q = f"SELECT * FROM `{OTHER_PO_TABLE}` ORDER BY order_date DESC LIMIT 200"
    rows = [dict(r) for r in client.query(q).result()]
    for d in rows:
        for k, v in list(d.items()):
            if hasattr(v, 'isoformat'):
                d[k] = v.isoformat()
    return jsonify(rows)


@app.route('/api/other_po/<po_id>', methods=['GET'])
def api_other_po_get(po_id):
    jc = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)])
    rows = list(client.query(f"SELECT * FROM `{OTHER_PO_TABLE}` WHERE other_po_id=@po_id", job_config=jc).result())
    if not rows:
        return jsonify({'error': 'Other PO not found'}), 404
    d = dict(rows[0])
    for k, v in list(d.items()):
        if hasattr(v, 'isoformat'):
            d[k] = v.isoformat()
    return jsonify(d)


@app.route('/api/other_po', methods=['POST'])
def api_other_po_create():
    try:
        errors, oid = insert_other_po(request.get_json() or {})
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True, 'other_po_id': oid})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/other_po/<po_id>', methods=['DELETE'])
def api_other_po_delete(po_id):
    try:
        errors = delete_other_po_record(po_id)
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/orders/new', methods=['GET', 'POST'])
@login_required
def new_order():
    """Create a new purchase order (supports multiple product lines)"""
    if request.method == 'POST':
        try:
            form = request.form
            # Parse multi-product lines from form arrays
            product_ids = form.getlist('product_ids[]')
            quantities = form.getlist('quantities[]')
            amounts = form.getlist('amounts[]')
            
            # Build product lines
            product_lines = []
            for pid, qty, amt in zip(product_ids, quantities, amounts):
                if pid and int(qty or 0) > 0:
                    product_lines.append({
                        'product_id': pid,
                        'quantity': int(qty),
                        'total_amount': float(amt or 0),
                    })
            
            if not product_lines:
                flash('At least one product line with quantity > 0 is required', 'error')
                return redirect(url_for('new_order'))
            
            header_data = {
                'order_date': form.get('order_date'),
                'manufacturer_name': form.get('manufacturer_name'),
                'currency': form.get('currency', 'USD'),
                'payment_status': form.get('payment_status', 'PENDING'),
                'notes': form.get('notes'),
            }
            
            errors, po_id = insert_purchase_order(header_data, product_lines)
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
def api_products():
    """API endpoint to get products"""
    products = get_products()
    return jsonify(products)
@app.route('/api/products/update-costs', methods=['POST'])
def api_update_product_costs():
    """Update product costs (shipping, cogs) directly in DIM_COSTS_HISTORY."""
    try:
        data = request.json
        if not data or not data.get('asin'):
            return jsonify({'success': False, 'error': 'Missing required field: asin'}), 400
        
        asin = data['asin']
        shipping_cost = data.get('shipping_cost')
        cogs = data.get('cogs')
        
        if shipping_cost is None and cogs is None:
            return jsonify({'success': False, 'error': 'Must provide shipping_cost or cogs to update'}), 400
        
        # Build dynamic update parts
        updates = []
        params = [bigquery.ScalarQueryParameter("asin", "STRING", asin)]
        
        if shipping_cost is not None:
            updates.append("shipping_cost = @shipping_cost")
            params.append(bigquery.ScalarQueryParameter("shipping_cost", "FLOAT", float(shipping_cost)))
            
        if cogs is not None:
            updates.append("cost_of_goods = @cogs")
            params.append(bigquery.ScalarQueryParameter("cogs", "FLOAT", float(cogs)))
            
        # Also recalculate total cost per unit
        updates.append("TOTAL_COST_PER_UNIT = COALESCE(cost_of_goods, 0) + COALESCE(FBA_COST_estimated_fee_total, 0) + COALESCE(shipping_cost, 0)")
        
        update_str = ", ".join(updates)
        
        query = f"""
        UPDATE `{PROJECT_ID}.{DATASET_ID}.DIM_COSTS_HISTORY`
        SET {update_str}
        WHERE asin = @asin AND end_date IS NULL
        """
        
        job_config = bigquery.QueryJobConfig(query_parameters=params)
        client.query(query, job_config=job_config).result()
        
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        import traceback
        print(f"Error updating product costs: {traceback.format_exc()}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/awd_target', methods=['POST'])
def api_update_awd_target():
    """Update AWD limits for a given ASIN via JSON payload."""
    try:
        data = request.json
        if not data or not data.get('asin') or data.get('approved_max_units') is None:
            return jsonify({'success': False, 'error': 'Missing required fields (asin, approved_max_units)'}), 400
        
        asin = data['asin']
        max_units = int(data['approved_max_units'])
        min_units = int(data.get('approved_min_units', 0))
        
        query = f"""
        MERGE `{PROJECT_ID}.{DATASET_ID}.DE_AWD_SETTINGS` T
        USING (SELECT @asin as asin) S
        ON T.asin = S.asin
        WHEN MATCHED THEN
          UPDATE SET approved_min_units = @min_units, approved_max_units = @max_units, approved_at = CURRENT_TIMESTAMP(), approved_by = 'system'
        WHEN NOT MATCHED THEN
          INSERT (asin, approved_min_units, approved_max_units, approved_at, approved_by)
          VALUES (@asin, @min_units, @max_units, CURRENT_TIMESTAMP(), 'system')
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("asin", "STRING", asin),
                bigquery.ScalarQueryParameter("min_units", "INTEGER", min_units),
                bigquery.ScalarQueryParameter("max_units", "INTEGER", max_units)
            ]
        )
        client.query(query, job_config=job_config).result()
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/adjust_forecast', methods=['POST'])
def api_adjust_forecast():
    """Update order override forecast for a given ASIN via JSON payload."""
    try:
        data = request.json
        if not data or not data.get('asin') or data.get('target_qty') is None:
            return jsonify({'success': False, 'error': 'Missing required fields (asin, target_qty)'}), 400
            
        asin = data['asin']
        target_qty = int(data['target_qty'])
        
        query = f"""
        UPDATE `{PROJECT_ID}.{DATASET_ID}.DE_PLAN_STRATEGY`
        SET order_overrides_json = TO_JSON_STRING(JSON_SET(PARSE_JSON(COALESCE(order_overrides_json, '{{}}')), CONCAT('$.', @asin), @target_qty)),
            updated_at = CURRENT_DATETIME(),
            updated_by = 'system'
        WHERE plan_year = EXTRACT(YEAR FROM CURRENT_DATE())
          AND status = 'APPROVED'
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("asin", "STRING", asin),
                bigquery.ScalarQueryParameter("target_qty", "INTEGER", target_qty)
            ]
        )
        client.query(query, job_config=job_config).result()
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/shipments', methods=['POST'])
def api_create_shipment():
    """Create a new shipment from the dashboard via JSON payload."""
    try:
        data = request.json
        if not data:
            return jsonify({'success': False, 'error': 'Missing JSON body'}), 400
            
        header_data = {
            'shipment_date': data.get('shipment_date'),
            'estimated_arrival_date': data.get('estimated_arrival_date'),
            'shipment_type': data.get('shipment_type', 'Sea'),
            'shipment_status': data.get('shipment_status', 'PENDING'),
            'deliverer': data.get('deliverer', ''),
            'tracking_number': data.get('tracking_number', ''),
            'notes': data.get('notes', ''),
            'cost_shipped': data.get('cost_shipped'),
            'kg_price': data.get('kg_price'),
            'is_paid': data.get('is_paid', False),
            'paid_date': data.get('paid_date'),
        }
        
        lines = []
        for line in data.get('lines', []):
            purchase_order_id = line.get('purchase_order_id')
            product_id = line.get('product_id')
            asin = line.get('asin')
            
            if not product_id and asin:
                # Look up product_id by ASIN
                prod_query = f"SELECT product_id FROM `{PRODUCTS_TABLE}` WHERE asin = @asin LIMIT 1"
                prod_config = bigquery.QueryJobConfig(
                    query_parameters=[bigquery.ScalarQueryParameter("asin", "STRING", asin)]
                )
                res = list(client.query(prod_query, job_config=prod_config).result())
                if res:
                    product_id = res[0].product_id
            
            if purchase_order_id and product_id and int(line.get('quantity', 0)) > 0:
                lines.append({
                    'purchase_order_id': purchase_order_id,
                    'product_id': product_id,
                    'quantity_shipped': int(line.get('quantity')),
                    'cartons': int(line.get('cartons', 0))
                })
        
        if not lines:
            return jsonify({'success': False, 'error': 'At least one shipment line is required (must provide PO ID and product)'}), 400

        # Validate connected Other POs (rolled into landed cost) — reject unknown ids
        other_po_ids = [str(x) for x in (data.get('other_po_ids') or []) if x]
        if other_po_ids:
            chk_ph = ', '.join([f'@id_{i}' for i in range(len(other_po_ids))])
            chk_q = f"SELECT other_po_id FROM `{OTHER_PO_TABLE}` WHERE other_po_id IN ({chk_ph})"
            chk_params = [bigquery.ScalarQueryParameter(f'id_{i}', 'STRING', pid) for i, pid in enumerate(other_po_ids)]
            found = {r.other_po_id for r in client.query(chk_q, job_config=bigquery.QueryJobConfig(query_parameters=chk_params)).result()}
            missing = [pid for pid in other_po_ids if pid not in found]
            if missing:
                return jsonify({'success': False, 'error': f"Unknown Other PO id(s): {', '.join(missing)}"}), 400

        errors, shipment_id = insert_shipment(header_data, lines, other_po_ids=other_po_ids)
        if errors:
            return jsonify({'success': False, 'error': f"Error inserting shipment: {errors}"}), 500
            
        clear_data_cache()
        return jsonify({'success': True, 'shipment_id': shipment_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500



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
            # Parse multi-PO lines from form: po_ids[], quantities[], product_ids[]
            po_ids = form.getlist('po_ids[]')
            quantities = form.getlist('quantities[]')
            product_ids = form.getlist('product_ids[]')
            
            lines = []
            for i, (pid, qty) in enumerate(zip(po_ids, quantities)):
                if pid and int(qty or 0) > 0:
                    line = {'purchase_order_id': pid, 'quantity_shipped': int(qty)}
                    # Include product_id if provided (for multi-product POs)
                    if i < len(product_ids) and product_ids[i]:
                        line['product_id'] = int(product_ids[i])
                    lines.append(line)
            
            if not lines:
                flash('At least one PO line with quantity > 0 is required', 'error')
                return redirect(url_for('new_shipment', po_id=po_id))
            
            header_data = {
                'shipment_date': form.get('shipment_date'),
                'shipment_type': form.get('shipment_type'),
                'cost_shipped': form.get('cost_shipped'),
                'kg_price': form.get('kg_price'),
                'tracking_number': form.get('tracking_number'),
                'deliverer': form.get('deliverer'),
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
                return redirect(url_for('index'))
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
    shipment_id = request.args.get('shipment_id', '')
    
    # Pre-fill shipment context for the form
    shipment_context = None
    if shipment_id:
        try:
            shp = get_shipment_details(shipment_id)
            if shp:
                shipment_context = {
                    'shipment_id': shipment_id,
                    'deliverer': shp.get('deliverer', ''),
                    'cost_shipped': shp.get('cost_shipped', 0),
                    'shipment_date': shp.get('shipment_date', ''),
                    'shipment_type': shp.get('shipment_type', ''),
                }
        except Exception as e:
            print(f"Error fetching shipment context: {e}")
    
    if request.method == 'POST':
        try:
            errors, payment_id = insert_payment(request.form.to_dict())
            if errors:
                flash(f'Error inserting payment: {errors}', 'error')
            else:
                clear_data_cache()
                flash(f'Payment {payment_id} created successfully!', 'success')
                # Redirect: prefer shipment detail if shipment-linked, else PO detail
                form_shipment_id = request.form.get('shipment_id')
                purchase_order_id = request.form.get('purchase_order_id')
                if form_shipment_id:
                    return redirect(url_for('shipment_details', shipment_id=form_shipment_id))
                elif purchase_order_id:
                    # Check if it's an Other PO
                    is_other_po = False
                    try:
                        q = f"SELECT 1 FROM `{OTHER_PO_TABLE}` WHERE other_po_id = @po_id LIMIT 1"
                        jc = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", purchase_order_id)])
                        res = list(client.query(q, job_config=jc).result())
                        if res: is_other_po = True
                    except Exception:
                        pass
                        
                    if is_other_po:
                        return redirect(url_for('other_po_details', po_id=purchase_order_id))
                    return redirect(url_for('po_details', po_id=purchase_order_id))
                return redirect(url_for('new_payment'))
        except Exception as e:
            flash(f'Error: {str(e)}', 'error')
    
    return render_template('payment_form.html', po_id=po_id, shipment_id=shipment_id, shipment_context=shipment_context)


@app.route('/payments', methods=['GET'])
@login_required
def payments_list():
    """List all vendor payments, grouped by payment_id"""
    query = f"""
    SELECT p.payment_id,
           MIN(p.payment_date) AS payment_date,
           SUM(p.payment_amount) AS payment_amount,
           SUM(COALESCE(p.bank_fee, 0)) AS bank_fee,
           ANY_VALUE(p.currency) AS currency,
           ANY_VALUE(p.payment_method) AS payment_method,
           ANY_VALUE(p.vendor_name) AS vendor_name,
           ANY_VALUE(p.notes) AS notes,
           COUNT(*) AS line_count,
           STRING_AGG(DISTINCT COALESCE(p.shipment_id, p.purchase_order_id), ', ' ORDER BY COALESCE(p.shipment_id, p.purchase_order_id)) AS linked_ids,
           CASE
             WHEN COUNTIF(p.shipment_id IS NOT NULL) > 0 AND COUNTIF(p.purchase_order_id IS NOT NULL AND p.shipment_id IS NULL) > 0 THEN 'Both'
             WHEN COUNTIF(p.shipment_id IS NOT NULL) > 0 THEN 'Shipment'
             ELSE 'PO'
           END AS payment_type
    FROM `{PAYMENTS_TABLE}` p
    GROUP BY p.payment_id
    ORDER BY MIN(p.payment_date) DESC
    """
    results = client.query(query).result()
    payments = [dict(row) for row in results]
    return render_template('payments_list.html', payments=payments)


def bulk_create_shipment_payments(data):
    """Helper: create payments for multiple shipments from a data dict.

    Expected keys in *data*:
        shipment_ids  – list[str]   parallel with amounts
        amounts       – list[str|float]   one per shipment_id
        payment_date  – str  (YYYY-MM-DD)
        payment_method – str
        vendor_name   – str
        currency      – str  (default 'USD')
        bank_fee      – float|None  (applied to first row only)
        notes         – str

    Returns (errors_list, created_count, payment_id).
    errors_list is [] on success.
    """
    shipment_ids = data.get('shipment_ids') or []
    amounts = data.get('amounts') or []
    payment_date = data.get('payment_date')
    payment_method = data.get('payment_method')
    vendor_name = data.get('vendor_name')
    currency = data.get('currency', 'USD')
    raw_fee = data.get('bank_fee')
    bank_fee = float(raw_fee) if raw_fee is not None and raw_fee != '' else None
    notes = data.get('notes', '')

    errors = []
    if not shipment_ids:
        errors.append('No shipments selected')
    if not payment_date or not vendor_name:
        errors.append('Payment date and vendor are required')
    if errors:
        return errors, 0, None

    rows = []
    shipment_details = [get_shipment_details(sid) for sid in shipment_ids]
    shipment_details = [s for s in shipment_details if s]
    payment_id = generate_payment_id(payment_date, vendor_name, shipment_details)

    for i, sid in enumerate(shipment_ids):
        amount = float(amounts[i]) if i < len(amounts) else 0
        if amount <= 0:
            continue
        row = {
            'payment_id': payment_id,
            'shipment_id': sid,
            'payment_date': payment_date,
            'payment_amount': round(amount, 2),
            'vendor_name': vendor_name,
            'currency': currency,
            'payment_method': payment_method,
        }
        if notes:
            row['notes'] = notes
        if bank_fee and len(rows) == 0:
            row['bank_fee'] = bank_fee
        rows.append(row)

    created = 0
    if rows:
        table_ref = client.get_table(PAYMENTS_TABLE)
        job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            autodetect=False,
            schema=table_ref.schema
        )
        job = client.load_table_from_json(rows, table_ref, job_config=job_config)
        job.result()
        if job.errors:
            errors.append(f'BigQuery errors: {job.errors}')
        else:
            created = len(rows)

    if created > 0:
        paid_shipment_ids = [r['shipment_id'] for r in rows if r.get('shipment_id')]
        sync_shipment_paid_status(paid_shipment_ids)
        auto_close_received_shipments()

    return errors, created, payment_id


def bulk_create_po_payments(data):
    """Helper: create payments for multiple POs (standard + Other) from a data dict.

    Expected keys in *data*:
        po_ids        – list[str]   parallel with amounts (all PO IDs: standard + other)
        amounts       – list[str|float]   one per po_id
        payment_date  – str  (YYYY-MM-DD)
        payment_method – str
        vendor_name   – str
        currency      – str  (default 'USD')
        bank_fee      – float|None  (applied to first row only)
        notes         – str

    Returns (errors_list, created_count, payment_id).
    errors_list is [] on success.
    """
    po_ids = data.get('po_ids') or []
    amounts = data.get('amounts') or []
    payment_date = data.get('payment_date')
    payment_method = data.get('payment_method')
    vendor_name = data.get('vendor_name')
    currency = data.get('currency', 'USD')
    raw_fee = data.get('bank_fee')
    bank_fee = float(raw_fee) if raw_fee is not None and raw_fee != '' else None
    notes = data.get('notes', '')

    errors = []
    if not po_ids:
        errors.append('No purchase orders selected')
    if not payment_date or not vendor_name:
        errors.append('Payment date and vendor are required')
    if errors:
        return errors, 0, None

    po_details_list = []
    for pid in po_ids:
        po_data = get_po_details(pid)
        if po_data and po_data[0]:
            po_details_list.append(po_data[0])
    payment_id = generate_payment_id(payment_date, vendor_name, [], po_details_list)

    rows = []
    for i, pid in enumerate(po_ids):
        amount = float(amounts[i]) if i < len(amounts) else 0
        if amount <= 0:
            continue
        row = {
            'payment_id': payment_id,
            'purchase_order_id': pid,
            'payment_date': payment_date,
            'payment_amount': round(amount, 2),
            'vendor_name': vendor_name,
            'currency': currency,
            'payment_method': payment_method,
        }
        if notes:
            row['notes'] = notes
        if bank_fee and len(rows) == 0:
            row['bank_fee'] = bank_fee
        rows.append(row)

    created = 0
    if rows:
        table_ref = client.get_table(PAYMENTS_TABLE)
        job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            autodetect=False,
            schema=table_ref.schema
        )
        job = client.load_table_from_json(rows, table_ref, job_config=job_config)
        job.result()
        if job.errors:
            errors.append(f'BigQuery errors: {job.errors}')
        else:
            created = len(rows)

    if created > 0:
        auto_close_received_shipments()

    return errors, created, payment_id


@app.route('/payments/bulk-new', methods=['GET', 'POST'])
@login_required
def bulk_new_payments():
    """Create payments for multiple shipments at once"""
    if request.method == 'POST':
        data = {
            'shipment_ids': request.form.getlist('shipment_ids'),
            'amounts': request.form.getlist('amounts'),
            'payment_date': request.form.get('payment_date'),
            'payment_method': request.form.get('payment_method'),
            'vendor_name': request.form.get('vendor_name'),
            'currency': request.form.get('currency', 'USD'),
            'bank_fee': request.form.get('bank_fee'),
            'notes': request.form.get('notes', ''),
        }
        errors, created, _payment_id = bulk_create_shipment_payments(data)
        if errors:
            for e in errors:
                flash(str(e), 'error')
            return redirect(url_for('shipments_list'))
        clear_data_cache()
        if created > 0:
            flash(f'{created} payment(s) created successfully!', 'success')
        return redirect(url_for('payments_list'))
    
    # GET: Fetch shipment details for selected IDs
    shipment_ids = request.args.getlist('shipment_ids')
    if not shipment_ids:
        flash('No shipments selected', 'error')
        return redirect(url_for('shipments_list'))
    
    # Query existing payments for these shipments in one go
    placeholders = ', '.join([f'@sid{i}' for i in range(len(shipment_ids))])
    paid_query = f"""
    SELECT shipment_id, COALESCE(SUM(payment_amount), 0) AS total_paid
    FROM `{PAYMENTS_TABLE}`
    WHERE shipment_id IN ({placeholders})
    GROUP BY shipment_id
    """
    paid_params = [
        bigquery.ScalarQueryParameter(f"sid{i}", "STRING", sid)
        for i, sid in enumerate(shipment_ids)
    ]
    paid_jc = bigquery.QueryJobConfig(query_parameters=paid_params)
    paid_results = client.query(paid_query, job_config=paid_jc).result()
    paid_map = {row['shipment_id']: float(row['total_paid']) for row in paid_results}
    
    shipments = []
    total_remaining = 0
    deliverer = None
    for sid in shipment_ids:
        shp = get_shipment_details(sid)
        if shp:
            cost = round(float(shp.get('cost_shipped') or 0), 2)
            already_paid = round(paid_map.get(sid, 0), 2)
            remaining = round(max(0, cost - already_paid), 2)
            shp['already_paid'] = already_paid
            shp['remaining'] = remaining
            shipments.append(shp)
            total_remaining += remaining
            if not deliverer:
                deliverer = shp.get('deliverer', '')
    
    return render_template('bulk_payment_form.html',
                           shipments=shipments,
                           shipment_ids=shipment_ids,
                           total_cost=total_remaining,
                           deliverer=deliverer)


@app.route('/payments/bulk-po-new', methods=['GET', 'POST'])
@login_required
def bulk_po_payments():
    """Create payments for multiple purchase orders at once (standard + Other POs)"""
    if request.method == 'POST':
        data = {
            'po_ids': request.form.getlist('po_ids'),
            'amounts': request.form.getlist('amounts'),
            'payment_date': request.form.get('payment_date'),
            'payment_method': request.form.get('payment_method'),
            'vendor_name': request.form.get('vendor_name'),
            'currency': request.form.get('currency', 'USD'),
            'bank_fee': request.form.get('bank_fee'),
            'notes': request.form.get('notes', ''),
        }
        errors, created, _payment_id = bulk_create_po_payments(data)
        if errors:
            for e in errors:
                flash(str(e), 'error')
            return redirect(url_for('index'))
        clear_data_cache()
        if created > 0:
            flash(f'{created} payment(s) created for {created} PO(s)!', 'success')
        return redirect(url_for('payments_list'))
    
    # GET: Fetch PO details for selected IDs (standard + other)
    po_ids = request.args.getlist('po_ids')
    other_po_ids = request.args.getlist('other_po_ids')
    
    if not po_ids and not other_po_ids:
        flash('No purchase orders selected', 'error')
        return redirect(url_for('index'))
    
    # Combine all IDs to query existing payments in one go
    all_ids = list(po_ids) + list(other_po_ids)
    placeholders = ', '.join([f'@pid{i}' for i in range(len(all_ids))])
    paid_query = f"""
    SELECT purchase_order_id, COALESCE(SUM(payment_amount), 0) AS total_paid
    FROM `{PAYMENTS_TABLE}`
    WHERE purchase_order_id IN ({placeholders})
    GROUP BY purchase_order_id
    """
    paid_params = [
        bigquery.ScalarQueryParameter(f"pid{i}", "STRING", pid)
        for i, pid in enumerate(all_ids)
    ]
    paid_jc = bigquery.QueryJobConfig(query_parameters=paid_params)
    paid_results = client.query(paid_query, job_config=paid_jc).result()
    paid_map = {row['purchase_order_id']: float(row['total_paid']) for row in paid_results}
    
    pos = []
    total_remaining = 0
    manufacturer = None
    
    # Standard POs
    for pid in po_ids:
        po_data = get_po_details(pid)
        if po_data and po_data[0]:
            po = po_data[0]
            po_amount = round(float(po.get('total_amount') or 0) + float(po.get('adjustments') or 0), 2)
            already_paid = round(paid_map.get(pid, 0), 2)
            remaining = round(max(0, po_amount - already_paid), 2)
            po['already_paid'] = already_paid
            po['remaining'] = remaining
            po['_po_type'] = 'standard'
            pos.append(po)
            total_remaining += remaining
            if not manufacturer:
                manufacturer = po.get('manufacturer_name', '')
    
    # Other POs — fetch from DE_OTHER_PO and normalise into same shape
    for oid in other_po_ids:
        try:
            q = f"SELECT * FROM `{OTHER_PO_TABLE}` WHERE other_po_id = @oid LIMIT 1"
            jc = bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter("oid", "STRING", oid)
            ])
            result = list(client.query(q, job_config=jc).result())
            if result:
                opo = dict(result[0])
                po_amount = round(float(opo.get('total_amount') or 0), 2)
                already_paid = round(paid_map.get(oid, 0), 2)
                remaining = round(max(0, po_amount - already_paid), 2)
                # Normalise keys to match standard PO shape expected by template
                normalised = {
                    'purchase_order_id': opo['other_po_id'],
                    'order_date': opo.get('order_date'),
                    'manufacturer_name': opo.get('supplier_name', ''),
                    'product_names_combined': opo.get('service_type', ''),
                    'quantity': None,
                    'total_amount': po_amount,
                    'adjustments': 0,
                    'already_paid': already_paid,
                    'remaining': remaining,
                    '_po_type': 'other',
                }
                pos.append(normalised)
                total_remaining += remaining
                if not manufacturer:
                    manufacturer = opo.get('supplier_name', '')
        except Exception as e:
            print(f"Error fetching Other PO {oid}: {e}")
    
    return render_template('bulk_po_payment_form.html',
                           pos=pos,
                           po_ids=all_ids,
                           total_remaining=total_remaining,
                           manufacturer=manufacturer)


@app.route('/api/payments/bulk', methods=['POST'])
def api_payments_bulk():
    """JSON twin: create payments for multiple shipments.

    Body (application/json):
        shipment_ids  – list[str]
        amounts       – list[str|float]  (parallel with shipment_ids)
        payment_date  – str  (YYYY-MM-DD)
        payment_method – str
        vendor_name   – str
        currency      – str  (default 'USD')
        bank_fee      – float|null
        notes         – str
    """
    try:
        errors, created, payment_id = bulk_create_shipment_payments(request.get_json() or {})
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True, 'created': created, 'payment_id': payment_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/payments/bulk-po', methods=['POST'])
def api_payments_bulk_po():
    """JSON twin: create payments for multiple POs (standard + Other).

    Body (application/json):
        po_ids        – list[str]  (standard PO IDs and/or other_po_ids, merged)
        amounts       – list[str|float]  (parallel with po_ids)
        payment_date  – str  (YYYY-MM-DD)
        payment_method – str
        vendor_name   – str
        currency      – str  (default 'USD')
        bank_fee      – float|null
        notes         – str
    """
    try:
        errors, created, payment_id = bulk_create_po_payments(request.get_json() or {})
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True, 'created': created, 'payment_id': payment_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/orders', methods=['GET'])
def get_orders():
    """API endpoint to get recent purchase orders (for lookup)"""
    query = f"""
    SELECT purchase_order_id, order_date, manufacturer_name as supplier_name, total_amount, 'Standard' as type
    FROM `{ORDERS_TABLE}`
    UNION ALL
    SELECT other_po_id as purchase_order_id, order_date, supplier_name, total_amount, 'Other' as type
    FROM `{OTHER_PO_TABLE}`
    ORDER BY order_date DESC
    LIMIT 100
    """
    results = client.query(query).result()
    orders = [dict(row) for row in results]
    return jsonify(orders)


@app.route('/api/po', methods=['POST'])
def api_create_po():
    """Create a new PO from the dashboard via JSON payload."""
    try:
        data = request.json
        if not data:
            return jsonify({'success': False, 'error': 'Missing JSON body'}), 400
        
        # Build header
        header_data = {
            'order_date': data.get('order_date'),
            'manufacturer_name': data.get('manufacturer_name'),
            'currency': data.get('currency', 'USD'),
            'payment_status': data.get('payment_status', 'PENDING'),
            'notes': data.get('notes', ''),
        }
        
        # We need product_id, not just ASIN. Let's look it up if only ASIN is provided.
        product_lines = []
        for line in data.get('product_lines', []):
            product_id = line.get('product_id')
            asin = line.get('asin')
            
            if not product_id and asin:
                # Look up product_id by ASIN
                prod_query = f"SELECT product_id FROM `{PRODUCTS_TABLE}` WHERE asin = @asin LIMIT 1"
                prod_config = bigquery.QueryJobConfig(
                    query_parameters=[bigquery.ScalarQueryParameter("asin", "STRING", asin)]
                )
                res = list(client.query(prod_query, job_config=prod_config).result())
                if res:
                    product_id = res[0].product_id
                
            if product_id and int(line.get('quantity', 0)) > 0:
                product_lines.append({
                    'product_id': product_id,
                    'quantity': int(line.get('quantity')),
                    'total_amount': float(line.get('total_amount', 0))
                })
        
        if not product_lines:
            return jsonify({'success': False, 'error': 'At least one product line with quantity > 0 is required'}), 400
            
        errors, po_id = insert_purchase_order(header_data, product_lines)
        if errors:
            return jsonify({'success': False, 'error': f"Error inserting PO: {errors}"}), 500
            
        clear_data_cache()
        return jsonify({'success': True, 'po_id': po_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/po/<po_id>/update-eta', methods=['POST'])
def api_update_po_eta(po_id):
    """Update estimated arrival date for a PO from the React dashboard."""
    try:
        data = request.json
        if not data:
            return jsonify({'success': False, 'error': 'Missing JSON body'}), 400

        eta = data.get('estimated_arrival_date')

        if eta:
            query = f"""
            UPDATE `{ORDERS_TABLE}`
            SET estimated_arrival_date = @eta
            WHERE purchase_order_id = @po_id
            """
            params = [
                bigquery.ScalarQueryParameter("eta", "DATE", eta),
                bigquery.ScalarQueryParameter("po_id", "STRING", po_id),
            ]
        else:
            # Clear the estimated arrival date
            query = f"""
            UPDATE `{ORDERS_TABLE}`
            SET estimated_arrival_date = NULL
            WHERE purchase_order_id = @po_id
            """
            params = [
                bigquery.ScalarQueryParameter("po_id", "STRING", po_id),
            ]

        job_config = bigquery.QueryJobConfig(query_parameters=params)
        client.query(query, job_config=job_config).result()
        clear_data_cache()

        return jsonify({'success': True, 'po_id': po_id, 'estimated_arrival_date': eta})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ---------------------------------------------------------------------------
# PO line / delete helpers — shared by HTML routes and JSON API twins
# ---------------------------------------------------------------------------

def add_po_line(po_id, product_id, quantity, total_amount):
    """Insert one product line row into an existing PO.

    Returns (errors_list, po_id).  Caller is responsible for clear_data_cache().
    """
    if not po_id:
        return (['Missing PO ID'], po_id)
    if not product_id or quantity <= 0:
        return (['Product and quantity > 0 are required'], po_id)

    # Get PO header info from existing rows
    header_query = f"""
    SELECT order_date, manufacturer_name, currency, payment_status, notes
    FROM `{ORDERS_TABLE}`
    WHERE purchase_order_id = @po_id
    LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
    )
    header_result = list(client.query(header_query, job_config=job_config).result())
    if not header_result:
        return ([f'PO {po_id} not found'], po_id)

    header = dict(header_result[0])

    # Look up product info
    product_asin = None
    product_name = None
    prod_query = f"""
    SELECT product_id, asin, product_name, display_name, sku
    FROM `{PRODUCTS_TABLE}`
    WHERE product_id = @product_id AND is_active = TRUE
    """
    prod_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("product_id", "INT64", int(product_id))]
    )
    prod_result = list(client.query(prod_query, job_config=prod_config).result())
    if prod_result:
        product_asin = prod_result[0].asin
        product_name = prod_result[0].sku or prod_result[0].display_name or prod_result[0].product_name

    unit_price = total_amount / quantity if quantity > 0 else 0

    row = {
        'purchase_order_id': po_id,
        'order_date': header['order_date'].isoformat() if header['order_date'] else None,
        'manufacturer_name': header['manufacturer_name'],
        'product_id': int(product_id),
        'quantity': quantity,
        'unit_price': unit_price,
        'total_amount': total_amount,
        'currency': header['currency'] or 'USD',
        'payment_status': header['payment_status'] or 'PENDING',
    }
    if product_asin:
        row['product_asin'] = product_asin
    if product_name:
        row['product_name'] = product_name
    if header.get('notes'):
        row['notes'] = header['notes']

    table_ref = client.get_table(ORDERS_TABLE)
    load_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=False,
        schema=table_ref.schema
    )
    job = client.load_table_from_json([row], table_ref, job_config=load_config)
    job.result()
    return (job.errors or [], po_id)


def delete_po_line(po_id, product_id):
    """Delete a single product line from a PO.

    Refuses to delete the last remaining line.
    Returns errors_list (empty on success).  Caller is responsible for clear_data_cache().
    """
    count_query = f"""
    SELECT COUNT(*) as cnt FROM `{ORDERS_TABLE}`
    WHERE purchase_order_id = @po_id
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
    )
    count_result = list(client.query(count_query, job_config=job_config).result())
    line_count = count_result[0].cnt if count_result else 0

    if line_count <= 1:
        return ['Cannot delete the last product line. Delete the entire PO instead.']

    delete_query = f"""
    DELETE FROM `{ORDERS_TABLE}`
    WHERE purchase_order_id = @po_id AND product_id = @product_id
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("po_id", "STRING", po_id),
            bigquery.ScalarQueryParameter("product_id", "INT64", product_id),
        ]
    )
    client.query(delete_query, job_config=job_config).result()
    return []


def update_po_line(po_id, product_id, field, value):
    """Update quantity | total_amount | ready_quantity for a product line.

    product_id may be None — in that case the WHERE clause omits it.
    Returns errors_list (empty on success).  Caller is responsible for clear_data_cache().
    """
    where_params = [
        bigquery.ScalarQueryParameter("po_id", "STRING", po_id)
    ]
    if product_id is not None:
        where_clause = "purchase_order_id = @po_id AND product_id = @product_id"
        where_params.append(bigquery.ScalarQueryParameter("product_id", "INT64", product_id))
    else:
        where_clause = "purchase_order_id = @po_id"

    if field == 'quantity':
        new_value = int(value) if value is not None else 0
        if new_value < 1:
            return ['Quantity must be at least 1']
        set_clause = "quantity = @new_value"
        where_params.append(bigquery.ScalarQueryParameter("new_value", "INT64", new_value))
    elif field == 'total_amount':
        new_value = float(value) if value is not None else 0.0
        if new_value < 0:
            return ['Amount cannot be negative']
        set_clause = "total_amount = @new_value"
        where_params.append(bigquery.ScalarQueryParameter("new_value", "FLOAT64", new_value))
    else:
        # Default: ready_quantity
        new_value = int(value) if value is not None else 0
        if new_value < 0:
            return ['Ready quantity cannot be negative']
        set_clause = "ready_quantity = @new_value"
        where_params.append(bigquery.ScalarQueryParameter("new_value", "INT64", new_value))

    update_query = f"""
    UPDATE `{ORDERS_TABLE}`
    SET {set_clause}
    WHERE {where_clause}
    """
    job_config = bigquery.QueryJobConfig(query_parameters=where_params)
    client.query(update_query, job_config=job_config).result()
    return []


def _do_delete_po(po_id):
    """Delete an entire PO (all rows) from ORDERS_TABLE.

    Returns errors_list (empty on success).  Caller is responsible for clear_data_cache().
    Raises on streaming-buffer or other BQ errors so the caller can inspect the exception.
    """
    query = f"""
    DELETE FROM `{ORDERS_TABLE}`
    WHERE purchase_order_id = @po_id
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
    )
    client.query(query, job_config=job_config).result()
    return []


# ---------------------------------------------------------------------------
# HTML routes — delegate to helpers, keep original flash/redirect behaviour
# ---------------------------------------------------------------------------

@app.route('/po/add_line', methods=['POST'])
@login_required
def add_po_product_line():
    """Add a product line to an existing PO"""
    po_id = request.form.get('po_id')
    if not po_id:
        flash('Missing PO ID', 'error')
        return redirect(url_for('index'))
    try:
        product_id = request.form.get('product_id')
        quantity = int(request.form.get('quantity', 0))
        total_amount = float(request.form.get('total_amount', 0))

        errors, _ = add_po_line(po_id, product_id, quantity, total_amount)
        if errors:
            # Distinguish "not found" vs validation errors for redirect target
            msg = str(errors[0]) if errors else 'Error adding product line'
            if 'not found' in msg:
                flash(msg, 'error')
                return redirect(url_for('index'))
            flash(f'Error adding product line: {errors}', 'error')
            return redirect(url_for('po_details', po_id=po_id))

        clear_data_cache()
        flash(f'Product line added to PO {po_id}', 'success')
    except Exception as e:
        flash(f'Error: {str(e)}', 'error')

    return redirect(url_for('po_details', po_id=po_id))


@app.route('/po/delete_line', methods=['POST'])
@login_required
def delete_po_product_line():
    """Delete a single product line from a PO"""
    po_id = request.form.get('po_id')
    product_id = int(request.form.get('product_id', 0))
    if not po_id or not product_id:
        flash('Missing PO ID or product ID', 'error')
        return redirect(url_for('index'))
    try:
        errors = delete_po_line(po_id, product_id)
        if errors:
            flash(errors[0], 'error')
            return redirect(url_for('po_details', po_id=po_id))
        clear_data_cache()
        flash(f'Product line removed from PO {po_id}', 'success')
    except Exception as e:
        flash(f'Error: {str(e)}', 'error')

    return redirect(url_for('po_details', po_id=po_id))

@app.route('/po/update_line', methods=['POST'])
@login_required
def update_po_product_line():
    """Update a field (ready_quantity, quantity, or total_amount) for a specific product line"""
    po_id = request.form.get('po_id')
    field = request.form.get('field', 'ready_quantity')  # Default to ready_quantity for backward compat

    # Handle NULL product_id scenario
    product_id_str = request.form.get('product_id')
    if product_id_str == 'None' or not product_id_str:
        product_id = None
    else:
        product_id = int(product_id_str)

    if not po_id:
        flash('Missing PO ID', 'error')
        return redirect(url_for('index'))

    try:
        # Pull the correct raw value from the form for the chosen field
        if field == 'quantity':
            raw_value = request.form.get('quantity', 0)
            label = 'Quantity'
        elif field == 'total_amount':
            raw_value = request.form.get('total_amount', 0)
            label = 'Amount'
        else:
            raw_value = request.form.get('ready_quantity', 0)
            label = 'Ready Quantity'

        errors = update_po_line(po_id, product_id, field, raw_value)
        if errors:
            flash(errors[0], 'error')
            return redirect(url_for('po_details', po_id=po_id))
        clear_data_cache()
        flash(f'{label} updated successfully', 'success')
    except Exception as e:
        flash(f'Error updating product line: {str(e)}', 'error')

    return redirect(url_for('po_details', po_id=po_id))

@app.route('/api/po/<po_id>', methods=['GET'])
def api_po_get(po_id):
    """Full PO detail (header aggregates + lines + linked payments + shipments) as JSON."""
    try:
        po, payments, shipments, product_lines = get_po_details(po_id)
        if po is None:
            return jsonify({'error': 'PO not found'}), 404

        def _ser(rows):
            out = []
            for r in rows:
                d = dict(r)
                for k, v in d.items():
                    if hasattr(v, 'isoformat'):
                        d[k] = v.isoformat()
                out.append(d)
            return out

        return jsonify({
            'po': _ser([po])[0],
            'product_lines': _ser(product_lines),
            'payments': _ser(payments),
            'shipments': _ser(shipments),
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/po/<po_id>/lines', methods=['GET'])
def api_po_lines_get(po_id):
    """API endpoint to get product lines for a PO (returns JSON)"""
    try:
        po, payments, shipments, product_lines = get_po_details(po_id)
        if po is None:
            return jsonify({'error': 'PO not found'}), 404
        return jsonify({'lines': product_lines})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/po/update_line', methods=['POST'])
def api_po_line_update():
    """API endpoint to update ready quantity for a specific product line"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON body provided'}), 400
            
        po_id = data.get('po_id')
        product_id = data.get('product_id')
        ready_quantity = data.get('ready_quantity')
        
        if not po_id or ready_quantity is None:
            return jsonify({'error': 'Missing PO ID or Ready Quantity'}), 400
            
        ready_quantity = int(ready_quantity)
        if ready_quantity < 0:
            return jsonify({'error': 'Ready quantity cannot be negative'}), 400
            
        params = [
            bigquery.ScalarQueryParameter("ready_qty", "INT64", ready_quantity),
            bigquery.ScalarQueryParameter("po_id", "STRING", po_id)
        ]
        
        if product_id is not None:
            where_clause = "purchase_order_id = @po_id AND product_id = @product_id"
            params.append(bigquery.ScalarQueryParameter("product_id", "INT64", int(product_id)))
        else:
            # If product_id is not provided, update all lines for this PO (usually there is only 1 line anyway)
            where_clause = "purchase_order_id = @po_id"
            
        update_query = f"""
        UPDATE `{ORDERS_TABLE}`
        SET ready_quantity = @ready_qty
        WHERE {where_clause}
        """
        
        job_config = bigquery.QueryJobConfig(query_parameters=params)
        client.query(update_query, job_config=job_config).result()
        clear_data_cache()
        
        return jsonify({'success': True, 'message': 'Product line updated successfully'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ---------------------------------------------------------------------------
# JSON API twins — no @login_required; global JWT gate covers /api/*
# ---------------------------------------------------------------------------

@app.route('/api/po/<po_id>/header', methods=['POST'])
def api_po_header_update(po_id):
    try:
        errors, _ = update_purchase_order(po_id, request.get_json() or {})
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True, 'po_id': po_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/po/<po_id>/lines', methods=['POST'])
def api_po_line_add(po_id):
    try:
        d = request.get_json() or {}
        errors, _ = add_po_line(po_id, d.get('product_id'), d.get('quantity', 0), d.get('total_amount', 0))
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True, 'po_id': po_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/po/<po_id>/lines/<int:product_id>', methods=['PUT'])
def api_po_line_edit(po_id, product_id):
    try:
        d = request.get_json() or {}
        field = d.get('field', 'ready_quantity')
        errors = update_po_line(po_id, product_id, field, d.get('value'))
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/po/<po_id>/lines/<int:product_id>', methods=['DELETE'])
def api_po_line_delete(po_id, product_id):
    try:
        errors = delete_po_line(po_id, product_id)
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/po/<po_id>', methods=['DELETE'])
def api_po_delete(po_id):
    try:
        errors = _do_delete_po(po_id)
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/po/<po_id>/delete', methods=['POST'])
@login_required
def delete_po(po_id):
    """Delete a purchase order"""
    try:
        _do_delete_po(po_id)
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


@app.route('/po/bulk-delete', methods=['POST'])
@login_required
def bulk_delete_pos():
    """Bulk delete multiple purchase orders"""
    po_ids = request.form.getlist('po_ids')
    if not po_ids:
        flash('No purchase orders selected for deletion.', 'error')
        return redirect(url_for('index'))
    
    deleted = 0
    errors = []
    for po_id in po_ids:
        try:
            query = f"""
            DELETE FROM `{ORDERS_TABLE}`
            WHERE purchase_order_id = @po_id
            """
            job_config = bigquery.QueryJobConfig(
                query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
            )
            client.query(query, job_config=job_config).result()
            deleted += 1
        except Exception as e:
            errors.append(f'{po_id}: {str(e)}')
    
    clear_data_cache()
    if deleted:
        flash(f'Successfully deleted {deleted} Purchase Order(s).', 'success')
    if errors:
        flash(f'Errors deleting {len(errors)} PO(s): {";".join(errors[:3])}', 'error')
    return redirect(url_for('index'))


@app.route('/shipments/bulk-delete', methods=['POST'])
@login_required
def bulk_delete_shipments():
    """Bulk delete multiple shipments and their lines"""
    shipment_ids = request.form.getlist('shipment_ids')
    if not shipment_ids:
        flash('No shipments selected for deletion.', 'error')
        return redirect(url_for('shipments_list'))
    
    deleted = 0
    errors = []
    for shipment_id in shipment_ids:
        try:
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
            deleted += 1
        except Exception as e:
            errors.append(f'{shipment_id}: {str(e)}')
    
    clear_data_cache()
    if deleted:
        flash(f'Successfully deleted {deleted} Shipment(s).', 'success')
    if errors:
        flash(f'Errors deleting {len(errors)} shipment(s): {";".join(errors[:3])}', 'error')
    return redirect(url_for('shipments_list'))


@app.route('/shipments/bulk-update', methods=['POST'])
@login_required
def bulk_update_shipments_standalone():
    """Bulk update shipments from the shipments list page (status + paid)"""
    try:
        shipment_ids = request.form.getlist('shipment_ids')
        if not shipment_ids:
            flash('No shipments selected for update', 'error')
            return redirect(url_for('shipments_list'))
        
        # Build the SET clause dynamically based on provided fields
        set_clauses = []
        params = []
        
        # Shipment Status
        if request.form.get('shipment_status'):
            set_clauses.append('shipment_status = @shipment_status')
            params.append(bigquery.ScalarQueryParameter("shipment_status", "STRING", request.form.get('shipment_status')))
        
        # Paid status — only update if the hidden flag indicates the user set this field
        if request.form.get('update_is_paid') == 'true':
            is_paid = request.form.get('is_paid') == 'true'
            set_clauses.append('is_paid = @is_paid')
            params.append(bigquery.ScalarQueryParameter("is_paid", "BOOL", is_paid))
            
            # Paid Date
            if is_paid and request.form.get('paid_date'):
                set_clauses.append('paid_date = @paid_date')
                params.append(bigquery.ScalarQueryParameter("paid_date", "DATE", request.form.get('paid_date')))
            elif is_paid:
                set_clauses.append('paid_date = NULL')
            else:
                # If paid is unchecked, clear paid_date
                set_clauses.append('paid_date = NULL')
        
        if not set_clauses:
            flash('No fields selected for update', 'error')
            return redirect(url_for('shipments_list'))
        
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
                if 'streaming buffer' in error_msg.lower():
                    failed_shipments.append(shipment_id)
                else:
                    raise
        
        if failed_shipments:
            if updated_count > 0:
                flash(f'Updated {updated_count} shipment(s). {len(failed_shipments)} could not be updated (streaming buffer).', 'warning')
            else:
                flash(f'Cannot update: All {len(failed_shipments)} shipment(s) are in streaming buffer. Wait a few minutes.', 'error')
        else:
            clear_data_cache()
            flash(f'Successfully updated {updated_count} shipment(s)!', 'success')
            
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        error_msg = str(e)
        
        if 'streaming buffer' in error_msg.lower():
            flash('Cannot update: Shipments are in streaming buffer. Wait a few minutes.', 'error')
        else:
            flash(f'Error updating shipments: {error_msg}', 'error')
        print(f"Bulk update shipments error: {error_details}")
    
    return redirect(url_for('shipments_list'))


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
    LEFT JOIN `{ORDERS_TABLE}` po 
        ON sl.purchase_order_id = po.purchase_order_id
        AND (sl.product_id IS NULL OR sl.product_id = po.product_id)
    WHERE sl.shipment_id = @shipment_id
    ORDER BY po.product_name
    """
    lines_result = client.query(lines_query, job_config=job_config).result()
    # Deduplicate lines in case of multi-match (legacy lines without product_id)
    seen_line_ids = set()
    lines = []
    for row in lines_result:
        d = dict(row)
        if d['line_id'] not in seen_line_ids:
            seen_line_ids.add(d['line_id'])
            lines.append(d)
    shipment['lines'] = lines

    return shipment


@app.route('/api/shipment/<shipment_id>', methods=['GET'])
def api_shipment_get(shipment_id):
    """Full shipment detail (header + lines) as JSON."""
    try:
        shipment = get_shipment_details(shipment_id)
        if shipment is None:
            return jsonify({'error': 'Shipment not found'}), 404

        def _ser(d):
            out = {}
            for k, v in d.items():
                if k == 'lines' and isinstance(v, list):
                    out[k] = [_ser(x) for x in v]
                elif hasattr(v, 'isoformat'):
                    out[k] = v.isoformat()
                else:
                    out[k] = v
            return out

        return jsonify(_ser(shipment))
    except Exception as e:
        return jsonify({'error': str(e)}), 500


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
    
    # Handle amazon_commission
    if 'amazon_commission' in data:
        amazon_commission_val = float(data.get('amazon_commission') or 0)
        updates.append('amazon_commission = @amazon_commission')
        params.append(bigquery.ScalarQueryParameter("amazon_commission", "FLOAT64", amazon_commission_val))
    
    # Recalculate allocated_cost on lines when cost_shipped or amazon_commission changes
    cost_changed = data.get('cost_shipped') or 'amazon_commission' in data
    if cost_changed:
        import math
        # Fetch current shipment to get both cost fields
        current = get_shipment_details(shipment_id) or {}
        new_cost_shipped = float(data.get('cost_shipped')) if data.get('cost_shipped') else (current.get('cost_shipped') or 0)
        new_amazon_commission = float(data.get('amazon_commission') or 0) if 'amazon_commission' in data else (current.get('amazon_commission') or 0)
        total_cost = new_cost_shipped + new_amazon_commission
        
        if total_cost > 0:
            # Get existing lines for this shipment
            lines_q = f"SELECT line_id, total_cubic_feet FROM `{SHIPMENT_LINES_TABLE}` WHERE shipment_id = @shipment_id"
            lines_jc = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)])
            line_rows = [dict(r) for r in client.query(lines_q, job_config=lines_jc).result()]
            grand_cubic = sum((lr.get('total_cubic_feet') or 0) for lr in line_rows)
            if line_rows:
                cases = []
                alloc_params = []
                line_ids = []
                for i, lr in enumerate(line_rows):
                    if grand_cubic > 0:
                        lr_cubic = lr.get('total_cubic_feet') or 0
                        alloc = round((lr_cubic / grand_cubic) * total_cost, 2)
                    else:
                        alloc = round(total_cost / len(line_rows), 2)
                    
                    cases.append(f"WHEN @line_id_{i} THEN @alloc_{i}")
                    alloc_params.extend([
                        bigquery.ScalarQueryParameter(f"line_id_{i}", "STRING", lr['line_id']),
                        bigquery.ScalarQueryParameter(f"alloc_{i}", "FLOAT64", alloc)
                    ])
                    line_ids.append(f"@line_id_{i}")
                
                upd_q = f"""
                    UPDATE `{SHIPMENT_LINES_TABLE}` 
                    SET allocated_cost = CASE line_id
                        {' '.join(cases)}
                        ELSE allocated_cost
                    END
                    WHERE line_id IN ({', '.join(line_ids)})
                """
                # Retry on concurrent DML errors
                import time as _time
                for attempt in range(3):
                    try:
                        client.query(upd_q, job_config=bigquery.QueryJobConfig(query_parameters=alloc_params)).result()
                        break
                    except Exception as e:
                        if 'concurrent' in str(e).lower() and attempt < 2:
                            _time.sleep(1 + attempt)
                        else:
                            raise
    
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
    
    # Retry on concurrent DML errors
    import time as _time
    for attempt in range(3):
        try:
            client.query(query, job_config=job_config).result()
            break
        except Exception as e:
            if 'concurrent' in str(e).lower() and attempt < 2:
                _time.sleep(1 + attempt)
            else:
                raise
    return []


@app.route('/api/shipment/<shipment_id>/update', methods=['POST'])
def api_update_shipment(shipment_id):
    """API endpoint for inline editing of shipment fields"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'success': False, 'error': 'No data provided'}), 400
        
        # Convert empty strings to None for optional fields
        for key in ['estimated_arrival_date', 'tracking_number', 'shipment_type', 'kg_price', 'cost_shipped', 'amazon_commission', 'paid_date', 'notes']:
            if key in data and data[key] == '':
                data[key] = None
        
        # Convert number strings to proper types
        if 'quantity_shipped' in data and data['quantity_shipped']:
            data['quantity_shipped'] = int(data['quantity_shipped'])
        if 'kg_price' in data and data['kg_price']:
            data['kg_price'] = float(data['kg_price'])
        if 'cost_shipped' in data and data['cost_shipped']:
            data['cost_shipped'] = float(data['cost_shipped'])
        if 'amazon_commission' in data and data['amazon_commission']:
            data['amazon_commission'] = float(data['amazon_commission'])
        
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
    # Get open POs for the "Add PO Line" picker
    open_pos = get_open_pos_for_shipment()
    # Exclude POs already linked to this shipment
    # Use composite key (po_id, product_id) to allow partial shipment of multi-product POs
    linked_keys = {
        (line.get('purchase_order_id'), str(line.get('product_id', '')))
        for line in (shipment.get('lines') or [])
    }
    available_pos = [
        po for po in open_pos
        if (po['purchase_order_id'], str(po.get('product_id', ''))) not in linked_keys
    ]
    
    # Fetch payments linked to this shipment
    shipment_payments = []
    try:
        pay_query = f"""
        SELECT payment_id, payment_date, payment_amount, bank_fee, currency, payment_method, vendor_name, notes
        FROM `{PAYMENTS_TABLE}`
        WHERE shipment_id = @shipment_id
        ORDER BY payment_date DESC
        """
        pay_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)]
        )
        shipment_payments = [dict(row) for row in client.query(pay_query, job_config=pay_config).result()]
    except Exception as e:
        print(f"Error fetching shipment payments: {e}")
    
    return render_template('shipment_details.html', shipment=shipment, po_id=po_id, available_pos=available_pos, shipment_payments=shipment_payments)


@app.route('/shipment/<shipment_id>/delete', methods=['POST'])
@login_required
def delete_shipment(shipment_id):
    """Delete a shipment and its lines"""
    # Get PO ID from lines before deleting for redirect
    po_id = None
    try:
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
    except Exception:
        pass

    errors = delete_shipment_record(shipment_id)
    if errors:
        flash(errors[0], 'error')
    else:
        clear_data_cache()
        flash(f'Shipment {shipment_id} deleted successfully!', 'success')

    if po_id:
        return redirect(url_for('po_details', po_id=po_id))
    else:
        return redirect(url_for('index'))


def get_payment_details(payment_id):
    """Get payment details with all associated lines (PO and/or shipment)"""
    query = f"""
    SELECT p.*,
           po.order_date, po.manufacturer_name, po.product_name, po.product_asin, po.total_amount AS po_total_amount, po.quantity AS po_quantity,
           s.shipment_date, s.shipment_type, s.cost_shipped, s.deliverer, s.shipment_status
    FROM `{PAYMENTS_TABLE}` p
    LEFT JOIN `{ORDERS_TABLE}` po ON p.purchase_order_id = po.purchase_order_id
    LEFT JOIN `{SHIPMENTS_TABLE}` s ON p.shipment_id = s.shipment_id
    WHERE p.payment_id = @payment_id
    ORDER BY p.shipment_id, p.purchase_order_id
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("payment_id", "STRING", payment_id)]
    )
    result = [dict(row) for row in client.query(query, job_config=job_config).result()]
    if not result:
        return None, []
    # First row as summary, all rows as lines
    summary = dict(result[0])
    summary['total_payment_amount'] = sum(r.get('payment_amount', 0) or 0 for r in result)
    summary['total_bank_fee'] = sum(r.get('bank_fee', 0) or 0 for r in result)
    summary['line_count'] = len(result)
    return summary, result


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
    payment, payment_lines = get_payment_details(payment_id)
    if not payment:
        flash('Payment not found', 'error')
        return redirect(url_for('index'))
    
    po_id = payment.get('purchase_order_id')
    linked_shipment_id = payment.get('shipment_id')
    
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
    payment, payment_lines = get_payment_details(payment_id)
    # Parse vendor_name for checkboxes (it's stored as comma-separated string)
    vendor_names = []
    if payment.get('vendor_name'):
        vendor_names = [v.strip() for v in payment.get('vendor_name', '').split(',')]
    payment['vendor_names_list'] = vendor_names
    
    open_pos = get_open_pos_for_shipment(include_all=True)
    available_shipments = get_all_shipments(status_filter='all')
    
    # Get other POs
    try:
        from app import OTHER_PO_TABLE, client
        other_po_query = f"SELECT other_po_id, supplier_name, total_amount FROM `{OTHER_PO_TABLE}` ORDER BY order_date DESC"
        other_pos = [dict(row) for row in client.query(other_po_query).result()]
    except Exception as e:
        print(f"Error fetching other POs: {e}")
        other_pos = []
    
    return render_template('payment_details.html', payment=payment, payment_lines=payment_lines, po_id=po_id, linked_shipment_id=linked_shipment_id, open_pos=open_pos, available_shipments=available_shipments, other_pos=other_pos)


@app.route('/payment/<payment_id>/add_line', methods=['POST'])
@login_required
def add_payment_line(payment_id):
    """Add an additional line (Shipment or PO) to an existing payment"""
    payment, _ = get_payment_details(payment_id)
    if not payment:
        flash('Payment not found', 'error')
        return redirect(url_for('index'))
    
    line_type = request.form.get('line_type')
    linked_id = request.form.get('linked_id')
    amount = request.form.get('payment_amount', 0)
    bank_fee = request.form.get('bank_fee') or None
    
    if not linked_id:
        flash('Please select a Shipment or PO.', 'error')
        return redirect(url_for('payment_details', payment_id=payment_id))
        
    # Inherit core details from the parent payment
    data = {
        'payment_id': payment_id,
        'payment_date': str(payment.get('payment_date', '')),
        'vendor_name': payment.get('vendor_name'),
        'currency': payment.get('currency', 'USD'),
        'payment_method': payment.get('payment_method'),
        'payment_amount': amount,
        'bank_fee': bank_fee,
        'notes': request.form.get('notes', ''),
    }
    
    if line_type == 'shipment':
        data['shipment_id'] = linked_id
    elif line_type == 'po':
        data['purchase_order_id'] = linked_id
    elif line_type == 'other_po':
        data['purchase_order_id'] = linked_id
        
    try:
        errors, _ = insert_payment(data)
        if errors:
            flash(f'Error adding payment line: {errors}', 'error')
        else:
            clear_data_cache()
            flash('Payment line added successfully!', 'success')
    except Exception as e:
        flash(f'Error: {str(e)}', 'error')
        
    return redirect(url_for('payment_details', payment_id=payment_id))


def delete_payment_record(payment_id):
    """Delete all rows for a payment_id and re-sync linked shipment paid status.
    Returns (errors_list, linked_shipment_ids, first_po_id).
    errors_list is [] on success."""
    try:
        # Collect linked refs before deleting for sync + caller redirect
        query_get_ref = f"""
        SELECT purchase_order_id, shipment_id FROM `{PAYMENTS_TABLE}`
        WHERE payment_id = @payment_id
        """
        job_config_get = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("payment_id", "STRING", payment_id)]
        )
        ref_result = list(client.query(query_get_ref, job_config=job_config_get).result())
        linked_shipment_ids = list(set(r.shipment_id for r in ref_result if r.shipment_id))
        first_po_id = ref_result[0].purchase_order_id if ref_result else None

        query = f"""
        DELETE FROM `{PAYMENTS_TABLE}`
        WHERE payment_id = @payment_id
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("payment_id", "STRING", payment_id)]
        )
        client.query(query, job_config=job_config).result()

        # Re-sync paid status for affected shipments
        if linked_shipment_ids:
            sync_shipment_paid_status(linked_shipment_ids)

        return [], linked_shipment_ids, first_po_id
    except Exception as e:
        error_msg = str(e)
        if 'streaming buffer' in error_msg.lower():
            return (["Cannot delete payment: This payment is still in BigQuery's streaming buffer. "
                     "This may be an older payment created before we switched to batch loading. "
                     "Please wait 5-10 minutes and try again. "
                     "Note: New payments created now can be deleted immediately."],
                    [], None)
        return [f'Error deleting payment: {error_msg}'], [], None


@app.route('/payment/<payment_id>/delete', methods=['POST'])
@login_required
def delete_payment(payment_id):
    """Delete a payment"""
    errors, linked_shipment_ids, po_id = delete_payment_record(payment_id)
    linked_shipment_id = linked_shipment_ids[0] if linked_shipment_ids else None
    if errors:
        import traceback
        flash(errors[0], 'error')
    else:
        clear_data_cache()
        flash(f'Payment {payment_id} deleted successfully!', 'success')

    # Redirect: prefer shipment detail if shipment-linked
    if linked_shipment_id:
        return redirect(url_for('shipment_details', shipment_id=linked_shipment_id))
    elif po_id:
        if po_id.startswith('OPO_'):
            return redirect(url_for('other_po_details', po_id=po_id))
        return redirect(url_for('po_details', po_id=po_id))
    else:
        return redirect(url_for('index'))


def delete_payment_line_record(payment_id, shipment_id=None, po_id=None):
    """Delete a single line from a payment (matched by shipment_id OR po_id).
    Re-syncs shipment paid status when a shipment line is removed.
    Returns [] on success, list of error strings on failure."""
    if not shipment_id and not po_id:
        return ['No line identifier provided (shipment_id or purchase_order_id required)']
    try:
        if shipment_id:
            query = f"""
            DELETE FROM `{PAYMENTS_TABLE}`
            WHERE payment_id = @payment_id AND shipment_id = @shipment_id
            """
            job_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("payment_id", "STRING", payment_id),
                    bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)
                ]
            )
        else:
            query = f"""
            DELETE FROM `{PAYMENTS_TABLE}`
            WHERE payment_id = @payment_id AND purchase_order_id = @po_id
            """
            job_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("payment_id", "STRING", payment_id),
                    bigquery.ScalarQueryParameter("po_id", "STRING", po_id)
                ]
            )

        client.query(query, job_config=job_config).result()

        # Re-sync paid status for the affected shipment
        if shipment_id:
            sync_shipment_paid_status(shipment_id)

        return []
    except Exception as e:
        error_msg = str(e)
        if 'streaming buffer' in error_msg.lower():
            return ["Cannot delete payment line: This payment is still in BigQuery's streaming buffer. "
                    "Please wait 5-10 minutes and try again."]
        return [f'Error deleting payment line: {error_msg}']


@app.route('/payment/<payment_id>/delete_line', methods=['POST'])
@login_required
def delete_payment_line(payment_id):
    """Delete a specific line from a payment"""
    shipment_id = request.form.get('shipment_id')
    po_id = request.form.get('purchase_order_id')

    if not shipment_id and not po_id:
        flash("No line specified for deletion.", "error")
        return redirect(url_for('payment_details', payment_id=payment_id))

    errors = delete_payment_line_record(payment_id, shipment_id=shipment_id, po_id=po_id)
    if errors:
        flash(errors[0], 'error')
    else:
        clear_data_cache()
        flash('Payment line removed successfully!', 'success')

    return redirect(url_for('payment_details', payment_id=payment_id))


# ═══════════════════════════════════════════════════════════════
# PAYMENT JSON API TWINS — no @login_required; global JWT gate
# ═══════════════════════════════════════════════════════════════

@app.route('/api/payment/<payment_id>', methods=['GET'])
def api_payment_get(payment_id):
    """Full payment detail (summary + lines) as JSON."""
    try:
        summary, lines = get_payment_details(payment_id)
        if summary is None:
            return jsonify({'error': 'Payment not found'}), 404
        def _ser(d):
            o = {}
            for k, v in d.items():
                o[k] = v.isoformat() if hasattr(v, 'isoformat') else v
            return o
        return jsonify({'payment': _ser(summary), 'lines': [_ser(x) for x in lines]})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/payments', methods=['POST'])
def api_payment_create():
    """Create a new payment. insert_payment already calls sync_shipment_paid_status
    and auto_close_received_shipments internally."""
    try:
        data = request.get_json() or {}
        errors, payment_id = insert_payment(data)
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True, 'payment_id': payment_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/payment/<payment_id>/update', methods=['POST'])
def api_payment_update(payment_id):
    """Update payment header fields. The HTML update route calls no additional
    sync beyond clear_data_cache — replicated here exactly."""
    try:
        data = request.get_json() or {}
        errors = update_payment(payment_id, data)
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/payment/<payment_id>', methods=['DELETE'])
def api_payment_delete(payment_id):
    """Delete all rows for a payment and re-sync linked shipment paid status
    (via delete_payment_record which calls sync_shipment_paid_status)."""
    try:
        errors, _shipment_ids, _po_id = delete_payment_record(payment_id)
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/payment/<payment_id>/lines', methods=['POST'])
def api_payment_line_add(payment_id):
    """Add a line to an existing payment (inheriting header fields from the parent
    payment row). insert_payment calls sync_shipment_paid_status internally."""
    try:
        parent, _ = get_payment_details(payment_id)
        if parent is None:
            return jsonify({'success': False, 'error': 'Payment not found'}), 404
        d = request.get_json() or {}
        line_type = d.get('line_type')  # 'shipment', 'po', or 'other_po'
        linked_id = d.get('linked_id')
        if not linked_id:
            return jsonify({'success': False, 'error': 'linked_id is required'}), 400
        data = {
            'payment_id': payment_id,
            'payment_date': str(parent.get('payment_date', '')),
            'vendor_name': parent.get('vendor_name'),
            'currency': parent.get('currency', 'USD'),
            'payment_method': parent.get('payment_method'),
            'payment_amount': d.get('payment_amount', 0),
            'bank_fee': d.get('bank_fee') or None,
            'notes': d.get('notes', ''),
        }
        if line_type == 'shipment':
            data['shipment_id'] = linked_id
        elif line_type in ('po', 'other_po'):
            data['purchase_order_id'] = linked_id
        errors, _ = insert_payment(data)
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True, 'payment_id': payment_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/payment/<payment_id>/lines/<line_id>', methods=['DELETE'])
def api_payment_line_delete(payment_id, line_id):
    """Delete one line from a payment.  line_id is either a shipment_id ('SHP_…')
    or a purchase_order_id ('PO_…' / 'OPO_…').
    delete_payment_line_record calls sync_shipment_paid_status when needed."""
    try:
        if line_id.startswith('SHP'):
            errors = delete_payment_line_record(payment_id, shipment_id=line_id)
        else:
            errors = delete_payment_line_record(payment_id, po_id=line_id)
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


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

# ═══════════════════════════════════════════════════════════════
# AWD SETTINGS API
# ═══════════════════════════════════════════════════════════════

@app.route('/api/awd-settings', methods=['POST'])
def api_awd_settings_update():
    """Approve AWD Targets per ASIN.
    
    Body JSON:
      { "asin": "B08...", "min_units": 300, "max_units": 450 }
    """
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON body provided'}), 400
        
        asin = data.get('asin')
        min_units = data.get('min_units')
        max_units = data.get('max_units')
        
        if not asin or min_units is None or max_units is None:
            return jsonify({'error': 'asin, min_units, max_units are required'}), 400
            
        user_email = session.get('user', {}).get('email', 'unknown')
        
        query = """
            MERGE `{project}.{dataset}.DE_AWD_SETTINGS` T
            USING (SELECT @asin as asin, @min_units as min_units, @max_units as max_units) S
            ON T.asin = S.asin
            WHEN MATCHED THEN
              UPDATE SET approved_min_units = S.min_units,
                         approved_max_units = S.max_units,
                         approved_at = CURRENT_TIMESTAMP(),
                         approved_by = @user_email
            WHEN NOT MATCHED THEN
              INSERT (asin, approved_min_units, approved_max_units, approved_at, approved_by)
              VALUES (S.asin, S.min_units, S.max_units, CURRENT_TIMESTAMP(), @user_email)
        """.format(project=PROJECT_ID, dataset=DATASET_ID)
        
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("asin", "STRING", asin),
                bigquery.ScalarQueryParameter("min_units", "INT64", int(min_units)),
                bigquery.ScalarQueryParameter("max_units", "INT64", int(max_units)),
                bigquery.ScalarQueryParameter("user_email", "STRING", user_email),
            ]
        )
        
        client.query(query, job_config=job_config).result()
        clear_data_cache()
        return jsonify({'success': True, 'message': f'AWD settings updated for {asin}'})
    except Exception as e:
        print(f"Error updating AWD Settings: {e}")
        return jsonify({'error': str(e)}), 500


# ═══════════════════════════════════════════════════════════════
# PLAN STRATEGY API — Versioned plans with lifecycle (DRAFT/APPROVED)
# ═══════════════════════════════════════════════════════════════

PLAN_SCHEMA = [
    bigquery.SchemaField('plan_id', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('plan_name', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('plan_year', 'INTEGER', mode='REQUIRED'),
    bigquery.SchemaField('plan_version', 'INTEGER', mode='REQUIRED'),
    bigquery.SchemaField('status', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('family', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('strategy', 'STRING'),
    bigquery.SchemaField('forecast_year', 'INTEGER'),
    bigquery.SchemaField('forecast_month', 'INTEGER'),
    bigquery.SchemaField('multiplier', 'FLOAT'),
    bigquery.SchemaField('target_roas', 'FLOAT'),
    bigquery.SchemaField('base_roas', 'FLOAT'),
    bigquery.SchemaField('updated_at', 'DATETIME'),
    bigquery.SchemaField('updated_by', 'STRING'),
    bigquery.SchemaField('growth_rate', 'FLOAT'),
    bigquery.SchemaField('growth_json', 'STRING'),
    bigquery.SchemaField('order_overrides_json', 'STRING'),
    bigquery.SchemaField('original_overrides_json', 'STRING'),
    bigquery.SchemaField('snapshot_units_json', 'STRING'),
]
PLAN_TABLE = f'{PROJECT_ID}.{DATASET_ID}.DE_PLAN_STRATEGY'


@app.route('/api/plans', methods=['GET'])
def api_plans_list():
    """List all plans (plan_id, plan_name, plan_version, status, updated_at)"""
    try:
        query = """
            SELECT plan_id, plan_name, plan_year, plan_version, status,
                   MAX(updated_at) as updated_at, ANY_VALUE(updated_by) as updated_by
            FROM `{t}`
            GROUP BY plan_id, plan_name, plan_year, plan_version, status
            ORDER BY plan_year DESC, plan_version DESC
        """.format(t=PLAN_TABLE)
        results = client.query(query).result()
        plans = []
        for row in results:
            d = dict(row)
            if d.get('updated_at'):
                d['updated_at'] = d['updated_at'].isoformat()
            plans.append(d)
        return jsonify(plans)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/plans/<plan_id>', methods=['GET'])
def api_plans_get(plan_id):
    """Load one plan's full row data"""
    try:
        query = """
            SELECT plan_id, plan_name, plan_year, plan_version, status,
                   family, strategy, forecast_year, forecast_month,
                   multiplier, target_roas, base_roas, growth_rate, growth_json,
                   order_overrides_json, original_overrides_json, snapshot_units_json, updated_at
            FROM `{t}`
            WHERE plan_id = @plan_id
            ORDER BY family, forecast_year, forecast_month
        """.format(t=PLAN_TABLE)
        results = client.query(query, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result()
        rows = []
        for row in results:
            d = dict(row)
            if d.get('updated_at'):
                d['updated_at'] = d['updated_at'].isoformat()
            rows.append(d)
        if not rows:
            return jsonify({'error': 'Plan not found'}), 404
        return jsonify({
            'plan_id': rows[0]['plan_id'],
            'plan_name': rows[0]['plan_name'],
            'plan_year': rows[0]['plan_year'],
            'plan_version': rows[0]['plan_version'],
            'status': rows[0]['status'],
            'rows': rows,
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/plans', methods=['POST'])
def api_plans_create():
    """Create a new plan. Body: { rows: [...], plan_year?: number }
    Auto-assigns plan_name as '{year} V{next_version}'
    """
    try:
        data = request.get_json()
        if not data or not isinstance(data.get('rows'), list) or len(data['rows']) == 0:
            return jsonify({'error': 'Expected { rows: [...] }'}), 400

        plan_year = data.get('plan_year', datetime.now().year)

        # Check: only one DRAFT at a time
        draft_q = """
            SELECT plan_id FROM `{t}`
            WHERE plan_year = @year AND status = 'DRAFT'
            LIMIT 1
        """.format(t=PLAN_TABLE)
        draft_rows = list(client.query(draft_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("year", "INT64", plan_year)]
        )).result())
        if draft_rows:
            return jsonify({'error': 'A draft plan already exists. Save to it or delete it first.'}), 409

        # Determine next version
        ver_q = """
            SELECT COALESCE(MAX(plan_version), 0) as max_ver
            FROM `{t}`
            WHERE plan_year = @year
        """.format(t=PLAN_TABLE)
        ver_rows = list(client.query(ver_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("year", "INT64", plan_year)]
        )).result())
        next_ver = (ver_rows[0]['max_ver'] if ver_rows else 0) + 1

        import uuid
        plan_id = str(uuid.uuid4())
        plan_name = f'{plan_year} V{next_ver}'
        now = datetime.now().isoformat()
        user_email = session.get('user', {}).get('email', 'dashboard')

        order_overrides_json = data.get('order_overrides_json')
        snapshot_units_json = data.get('snapshot_units_json')  # Frozen simulation output
        rows = [{
            'plan_id': plan_id,
            'plan_name': plan_name,
            'plan_year': plan_year,
            'plan_version': next_ver,
            'status': 'DRAFT',
            'family': item['family'],
            'strategy': item.get('strategy', 'SEASONAL'),
            'forecast_year': item['forecast_year'],
            'forecast_month': item['forecast_month'],
            'multiplier': item.get('multiplier', 1.0),
            'target_roas': item.get('target_roas'),
            'base_roas': item.get('base_roas'),
            'growth_rate': item.get('growth_rate', 1.0),
            'growth_json': item.get('growth_json'),
            'order_overrides_json': order_overrides_json,
            'original_overrides_json': None,
            'snapshot_units_json': snapshot_units_json,
            'updated_at': now,
            'updated_by': user_email,
        } for item in data['rows']]

        job_config = bigquery.LoadJobConfig(schema=PLAN_SCHEMA, write_disposition='WRITE_APPEND')
        job = client.load_table_from_json(rows, PLAN_TABLE, job_config=job_config)
        job.result()
        if job.errors:
            return jsonify({'error': str(job.errors)}), 500

        clear_data_cache()
        return jsonify({'success': True, 'plan_id': plan_id, 'plan_name': plan_name, 'plan_version': next_ver, 'rows_saved': len(rows)})
    except Exception as e:
        import traceback
        print(f"Plan create error: {traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/plans/<plan_id>', methods=['PUT'])
def api_plans_update(plan_id):
    """Update a DRAFT plan. Body: { rows: [...] }
    Deletes existing rows for this plan_id, then inserts fresh.
    """
    try:
        data = request.get_json()
        if not data or not isinstance(data.get('rows'), list):
            return jsonify({'error': 'Expected { rows: [...] }'}), 400

        # Verify plan exists and is DRAFT
        check_q = """
            SELECT plan_name, plan_year, plan_version, status
            FROM `{t}` WHERE plan_id = @plan_id LIMIT 1
        """.format(t=PLAN_TABLE)
        check_rows = list(client.query(check_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result())
        if not check_rows:
            return jsonify({'error': 'Plan not found'}), 404
        plan_info = dict(check_rows[0])
        if plan_info['status'] != 'DRAFT':
            return jsonify({'error': 'Cannot update an approved plan. Unapprove first.'}), 403

        # Delete existing rows
        del_q = """DELETE FROM `{t}` WHERE plan_id = @plan_id""".format(t=PLAN_TABLE)
        client.query(del_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result()

        # Insert fresh
        now = datetime.now().isoformat()
        user_email = session.get('user', {}).get('email', 'dashboard')
        order_overrides_json = data.get('order_overrides_json')
        snapshot_units_json = data.get('snapshot_units_json')  # Frozen simulation output
        rows = [{
            'plan_id': plan_id,
            'plan_name': plan_info['plan_name'],
            'plan_year': plan_info['plan_year'],
            'plan_version': plan_info['plan_version'],
            'status': 'DRAFT',
            'family': item['family'],
            'strategy': item.get('strategy', 'SEASONAL'),
            'forecast_year': item['forecast_year'],
            'forecast_month': item['forecast_month'],
            'multiplier': item.get('multiplier', 1.0),
            'target_roas': item.get('target_roas'),
            'base_roas': item.get('base_roas'),
            'growth_rate': item.get('growth_rate', 1.0),
            'growth_json': item.get('growth_json'),
            'order_overrides_json': order_overrides_json,
            'original_overrides_json': None,
            'snapshot_units_json': snapshot_units_json,
            'updated_at': now,
            'updated_by': user_email,
        } for item in data['rows']]

        job_config = bigquery.LoadJobConfig(schema=PLAN_SCHEMA, write_disposition='WRITE_APPEND')
        # Debug: log growth_json values
        sample = rows[0] if rows else {}
        print(f"[PlanSave] growth_json sample: {sample.get('growth_json')!r}, total rows: {len(rows)}")
        job = client.load_table_from_json(rows, PLAN_TABLE, job_config=job_config)
        job.result()
        print(f"[PlanSave] job errors: {job.errors}, output_rows: {job.output_rows}")
        if job.errors:
            return jsonify({'error': str(job.errors)}), 500

        clear_data_cache()
        return jsonify({'success': True, 'plan_id': plan_id, 'rows_saved': len(rows)})
    except Exception as e:
        import traceback
        print(f"Plan update error: {traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/plans/<plan_id>/approve', methods=['POST'])
def api_plans_approve(plan_id):
    """Approve a DRAFT plan → APPROVED.
    On first approval, snapshot order_overrides_json → original_overrides_json (immutable).
    """
    try:
        check_q = """
            SELECT status, plan_year, order_overrides_json, original_overrides_json
            FROM `{t}` WHERE plan_id = @plan_id LIMIT 1
        """.format(t=PLAN_TABLE)
        check_rows = list(client.query(check_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result())
        if not check_rows:
            return jsonify({'error': 'Plan not found'}), 404
        info = dict(check_rows[0])
        if info['status'] == 'APPROVED':
            return jsonify({'error': 'Plan is already approved'}), 400

        # On first approval, snapshot current overrides as the original (immutable)
        has_original = info.get('original_overrides_json') is not None
        if has_original:
            # Re-approval after unapprove: keep original, just flip status
            update_q = """
                UPDATE `{t}` SET status = 'APPROVED', updated_at = CURRENT_DATETIME()
                WHERE plan_id = @plan_id
            """.format(t=PLAN_TABLE)
        else:
            # First-ever approval: copy order_overrides → original_overrides
            update_q = """
                UPDATE `{t}`
                SET status = 'APPROVED',
                    original_overrides_json = order_overrides_json,
                    updated_at = CURRENT_DATETIME()
                WHERE plan_id = @plan_id
            """.format(t=PLAN_TABLE)

        client.query(update_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result()

        # ── Snapshot forecast on first approval ──────────────────
        if not has_original:
            try:
                snapshot_q = """
                    INSERT INTO `{p}.{d}.DE_FORECAST_SNAPSHOT`
                      (plan_id, product, asin, forecast_year, forecast_month, forecast_units, peak_days, approved_at)
                    SELECT
                      @plan_id,
                      fd.product,
                      dp.asin,
                      fd.forecast_year,
                      fd.forecast_month,
                      CAST(fd.forecast_units AS INT64),
                      fd.peak_days,
                      CURRENT_TIMESTAMP()
                    FROM `{p}.{d}.V_FORECAST_DEMAND` fd
                    LEFT JOIN `{p}.{d}.DIM_PRODUCT` dp ON dp.product_short_name = fd.product
                    WHERE fd.forecast_units > 0
                      AND fd.product IS NOT NULL
                      AND fd.forecast_year = @plan_year
                """.format(p=PROJECT_ID, d=DATASET_ID)
                client.query(snapshot_q, job_config=bigquery.QueryJobConfig(
                    query_parameters=[
                        bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id),
                        bigquery.ScalarQueryParameter("plan_year", "INT64", int(info.get('plan_year', datetime.now().year))),
                    ]
                )).result()
                print(f"[PlanApprove] Forecast snapshot saved for plan {plan_id}")
            except Exception as snap_err:
                print(f"[PlanApprove] Warning: forecast snapshot failed: {snap_err}")
                # Non-fatal — approval still succeeds

        clear_data_cache()
        return jsonify({'success': True, 'status': 'APPROVED'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/plans/<plan_id>/unapprove', methods=['POST'])
def api_plans_unapprove(plan_id):
    """Unapprove an APPROVED plan → DRAFT. Only if no other DRAFT exists."""
    try:
        check_q = """
            SELECT plan_year, status FROM `{t}` WHERE plan_id = @plan_id LIMIT 1
        """.format(t=PLAN_TABLE)
        check_rows = list(client.query(check_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result())
        if not check_rows:
            return jsonify({'error': 'Plan not found'}), 404
        info = dict(check_rows[0])
        if info['status'] != 'APPROVED':
            return jsonify({'error': 'Plan is not approved'}), 400

        # Check no other draft exists for this year
        draft_q = """
            SELECT plan_id FROM `{t}`
            WHERE plan_year = @year AND status = 'DRAFT' AND plan_id != @plan_id
            LIMIT 1
        """.format(t=PLAN_TABLE)
        draft_rows = list(client.query(draft_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("year", "INT64", info['plan_year']),
                bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id),
            ]
        )).result())
        if draft_rows:
            return jsonify({'error': 'Another draft plan already exists. Delete it first.'}), 409

        update_q = """
            UPDATE `{t}` SET status = 'DRAFT', updated_at = CURRENT_DATETIME()
            WHERE plan_id = @plan_id
        """.format(t=PLAN_TABLE)
        client.query(update_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result()

        clear_data_cache()
        return jsonify({'success': True, 'status': 'DRAFT'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/plans/<plan_id>', methods=['DELETE'])
def api_plans_delete(plan_id):
    """Delete a plan. Must be DRAFT."""
    try:
        check_q = """
            SELECT status FROM `{t}` WHERE plan_id = @plan_id LIMIT 1
        """.format(t=PLAN_TABLE)
        check_rows = list(client.query(check_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result())
        if not check_rows:
            return jsonify({'error': 'Plan not found'}), 404
        if dict(check_rows[0])['status'] != 'DRAFT':
            return jsonify({'error': 'Cannot delete an approved plan. Unapprove first.'}), 403

        del_q = """DELETE FROM `{t}` WHERE plan_id = @plan_id""".format(t=PLAN_TABLE)
        client.query(del_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result()

        clear_data_cache()
        return jsonify({'success': True, 'deleted': plan_id})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ═══════════════════════════════════════════════════════════════
# ADS TARGETS API — Monthly spend/CPC targets per family/channel
# ═══════════════════════════════════════════════════════════════

ADS_TARGETS_TABLE = f'{PROJECT_ID}.{DATASET_ID}.DE_PLAN_ADS_TARGETS'
ADS_TARGETS_SCHEMA = [
    bigquery.SchemaField('family', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('yr', 'INTEGER', mode='REQUIRED'),
    bigquery.SchemaField('mo', 'INTEGER', mode='REQUIRED'),
    bigquery.SchemaField('channel', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('daily_spend_target', 'FLOAT'),
    bigquery.SchemaField('cpc_target', 'FLOAT'),
    bigquery.SchemaField('predicted_cvr', 'FLOAT'),
    bigquery.SchemaField('predicted_roas', 'FLOAT'),
    bigquery.SchemaField('predicted_units', 'FLOAT'),
    bigquery.SchemaField('predicted_net_profit', 'FLOAT'),
    bigquery.SchemaField('cpc_exponent', 'FLOAT'),
    bigquery.SchemaField('cvr_exponent', 'FLOAT'),
    bigquery.SchemaField('ads_share', 'FLOAT'),
    bigquery.SchemaField('season_type', 'STRING'),
    bigquery.SchemaField('multiplier_k', 'FLOAT'),
    bigquery.SchemaField('plan_strategy_id', 'STRING'),
    bigquery.SchemaField('created_at', 'TIMESTAMP'),
    bigquery.SchemaField('updated_at', 'TIMESTAMP'),
    bigquery.SchemaField('ly_ad_net_roas', 'FLOAT'),
    bigquery.SchemaField('cy_ad_net_roas', 'FLOAT'),
    bigquery.SchemaField('ly_net_roas', 'FLOAT'),
    bigquery.SchemaField('cy_net_roas', 'FLOAT'),
]


@app.route('/api/plans/ads-targets', methods=['POST'])
def api_ads_targets_save():
    """Save monthly ads targets for a family.
    
    Body JSON:
      { "family": "Lollibox",
        "plan_strategy_id": "uuid-of-plan",  // optional link
        "targets": [
          { "yr": 2026, "mo": 5, "channel": "BRAND",
            "daily_spend_target": 5.0, "cpc_target": 0.42,
            "predicted_cvr": 0.156, "predicted_roas": 8.8,
            "predicted_units": 200, "predicted_net_profit": 3500,
            "cpc_exponent": -0.303, "cvr_exponent": 0.568,
            "ads_share": 0.59, "season_type": "OFF", "multiplier_k": 1.0 },
          ...
        ]
      }
    
    Overwrites existing targets for the same family+yr+mo+channel.
    """
    try:
        data = request.get_json()
        if not data or not isinstance(data.get('targets'), list) or len(data['targets']) == 0:
            return jsonify({'error': 'Expected { family, targets: [...] }'}), 400

        family = data.get('family')
        if not family:
            return jsonify({'error': 'family is required'}), 400

        plan_strategy_id = data.get('plan_strategy_id')
        now = datetime.now().isoformat()

        # Delete existing targets for this family (full overwrite)
        del_q = """DELETE FROM `{t}` WHERE family = @family""".format(t=ADS_TARGETS_TABLE)
        client.query(del_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("family", "STRING", family)]
        )).result()

        # Insert fresh targets
        rows = [{
            'family': family,
            'yr': t['yr'],
            'mo': t['mo'],
            'channel': t['channel'],
            'daily_spend_target': t.get('daily_spend_target'),
            'cpc_target': t.get('cpc_target'),
            'predicted_cvr': t.get('predicted_cvr'),
            'predicted_roas': t.get('predicted_roas'),
            'predicted_units': t.get('predicted_units'),
            'predicted_net_profit': t.get('predicted_net_profit'),
            'cpc_exponent': t.get('cpc_exponent'),
            'cvr_exponent': t.get('cvr_exponent'),
            'ads_share': t.get('ads_share'),
            'season_type': t.get('season_type'),
            'multiplier_k': t.get('multiplier_k'),
            'ly_ad_net_roas': t.get('ly_ad_net_roas'),
            'cy_ad_net_roas': t.get('cy_ad_net_roas'),
            'ly_net_roas': t.get('ly_net_roas'),
            'cy_net_roas': t.get('cy_net_roas'),
            'plan_strategy_id': plan_strategy_id,
            'created_at': now,
            'updated_at': now,
        } for t in data['targets']]

        job_config = bigquery.LoadJobConfig(schema=ADS_TARGETS_SCHEMA, write_disposition='WRITE_APPEND')
        job = client.load_table_from_json(rows, ADS_TARGETS_TABLE, job_config=job_config)
        job.result()
        if job.errors:
            return jsonify({'error': str(job.errors)}), 500

        clear_data_cache()
        return jsonify({'success': True, 'family': family, 'targets_saved': len(rows)})
    except Exception as e:
        import traceback
        print(f"Ads targets save error: {traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/plans/ads-targets/<family>', methods=['GET'])
def api_ads_targets_get(family):
    """Get current ads targets for a family."""
    try:
        query = """
            SELECT family, yr, mo, channel,
                   daily_spend_target, cpc_target,
                   predicted_cvr, predicted_roas, predicted_units, predicted_net_profit,
                   season_type, multiplier_k, created_at
            FROM `{t}`
            WHERE family = @family
            ORDER BY yr, mo, channel
        """.format(t=ADS_TARGETS_TABLE)
        results = client.query(query, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("family", "STRING", family)]
        )).result()
        rows = []
        for row in results:
            d = dict(row)
            if d.get('created_at'):
                d['created_at'] = d['created_at'].isoformat()
            rows.append(d)
        return jsonify(rows)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ═══════════════════════════════════════════════════════════════
# SHIPMENT PLAN API — Weekly shipment schedule tied to plan_id
# ═══════════════════════════════════════════════════════════════

SHIPMENT_PLAN_TABLE = f'{PROJECT_ID}.{DATASET_ID}.DE_SHIPMENT_PLAN'
SHIPMENT_PLAN_SCHEMA = [
    bigquery.SchemaField('plan_id', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('shipment_week', 'INTEGER', mode='REQUIRED'),
    bigquery.SchemaField('ship_number', 'INTEGER', mode='REQUIRED'),
    bigquery.SchemaField('ship_date', 'DATE', mode='REQUIRED'),
    bigquery.SchemaField('est_arrival', 'DATE', mode='REQUIRED'),
    bigquery.SchemaField('route', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('route_reason', 'STRING'),
    bigquery.SchemaField('shipment_type', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('product', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('quantity', 'INTEGER', mode='REQUIRED'),
    bigquery.SchemaField('num_boxes', 'INTEGER'),
    bigquery.SchemaField('total_cubic_feet', 'FLOAT'),
    bigquery.SchemaField('est_ship_cost', 'FLOAT'),
    bigquery.SchemaField('est_mfr_cost', 'FLOAT'),
    bigquery.SchemaField('status', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('updated_at', 'DATETIME', mode='REQUIRED'),
]


@app.route('/api/sales-summary/<int:year>', methods=['GET'])
def api_sales_summary(year):
    """Get total units sold by product for a given year (YTD).
    Used by plans to show 'Yearly Sell Qty'.
    """
    try:
        query = """
            SELECT dp.product_short_name as product_name, dp.asin,
                   SUM(u.units) as total_sold
            FROM `{project}.{dataset}.V_UNIFIED_DAILY` u
            JOIN `{project}.{dataset}.DIM_PRODUCT` dp ON u.asin = dp.asin
            WHERE EXTRACT(YEAR FROM u.date) = @year
              AND dp.asin IS NOT NULL AND dp.asin != 'UNKNOWN'
            GROUP BY dp.product_short_name, dp.asin
        """.format(project=PROJECT_ID, dataset=DATASET_ID)
        job = client.query(query, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter('year', 'INT64', year)]
        ))
        result = []
        for r in job.result():
            rd = dict(r)
            result.append({
                'asin': rd['asin'],
                'product_name': rd['product_name'],
                'sold': rd['total_sold'],
            })
        return jsonify(result)
    except Exception as e:
        print(f"Error fetching sales summary: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/cashflow-actuals/<int:year>', methods=['GET'])
def api_cashflow_actuals(year):
    """Monthly cashflow actuals: Amazon inflow (sales, units, ad_cost) + vendor outflows by type."""
    try:
        # Amazon monthly aggregates (for Payment formula on frontend)
        # Include Dec of prev year (stored as month=0) for Jan's Payment calculation
        amazon_q = """
            SELECT
              CASE WHEN EXTRACT(YEAR FROM date) = @year THEN EXTRACT(MONTH FROM date) ELSE 0 END as month,
              SUM(sales) as sales, SUM(units) as units, SUM(ad_cost) as ad_cost
            FROM `{p}.{d}.V_UNIFIED_DAILY`
            WHERE (EXTRACT(YEAR FROM date) = @year)
               OR (EXTRACT(YEAR FROM date) = @year - 1 AND EXTRACT(MONTH FROM date) = 12)
            GROUP BY 1 ORDER BY 1
        """.format(p=PROJECT_ID, d=DATASET_ID)
        amazon_rows = list(client.query(amazon_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter('year', 'INT64', year)]
        )).result())

        # Vendor payments by type (Manufacturer / Deliverer)
        vendor_q = """
            SELECT EXTRACT(MONTH FROM vp.payment_date) as month,
                   lov.attr1_value as vendor_type,
                   SUM(vp.payment_amount + COALESCE(vp.bank_fee, 0)) as amount
            FROM `{p}.{d}.DE_VENDOR_PAYMENTS` vp
            JOIN `{p}.{d}.DE_LIST_OF_VALUES` lov
              ON lov.lov_set = 'SUPPLIER' AND lov.value_id = vp.vendor_name
            WHERE EXTRACT(YEAR FROM vp.payment_date) = @year
            GROUP BY 1, 2 ORDER BY 1, 2
        """.format(p=PROJECT_ID, d=DATASET_ID)
        vendor_rows = list(client.query(vendor_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter('year', 'INT64', year)]
        )).result())

        amazon = {}
        for r in amazon_rows:
            rd = dict(r)
            amazon[rd['month']] = {'sales': rd['sales'] or 0, 'units': rd['units'] or 0, 'ad_cost': rd['ad_cost'] or 0}

        # Per-product monthly breakdown (for tooltip detail)
        prod_q = """
            SELECT
              EXTRACT(MONTH FROM date) as month,
              product_short_name as product,
              SUM(sales) as sales, SUM(units) as units, SUM(ad_cost) as ad_cost
            FROM `{p}.{d}.V_UNIFIED_DAILY`
            WHERE EXTRACT(YEAR FROM date) = @year
            GROUP BY 1, 2 ORDER BY 1, 3 DESC
        """.format(p=PROJECT_ID, d=DATASET_ID)
        prod_rows = list(client.query(prod_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter('year', 'INT64', year)]
        )).result())
        amazon_by_product = {}
        for r in prod_rows:
            rd = dict(r)
            m = rd['month']
            if m not in amazon_by_product:
                amazon_by_product[m] = []
            amazon_by_product[m].append({
                'product': rd['product'],
                'sales': round(rd['sales'] or 0, 2),
                'units': rd['units'] or 0,
                'ad_cost': round(rd['ad_cost'] or 0, 2),
            })

        manufacturer = {}
        deliverer = {}
        for r in vendor_rows:
            rd = dict(r)
            m = rd['month']
            if rd['vendor_type'] == 'Manufacturer':
                manufacturer[m] = rd['amount'] or 0
            elif rd['vendor_type'] == 'Deliverer':
                deliverer[m] = rd['amount'] or 0

        # Unpaid PO amounts — estimated payment month = order_date + 4 months
        # Manufacturing lead time is ~4 months, payment happens at shipment
        po_q = """
            SELECT
              purchase_order_id,
              product_name,
              order_date,
              LEAST(12, EXTRACT(MONTH FROM DATE_ADD(order_date, INTERVAL 4 MONTH))) as est_pay_month,
              unpaid_manufacturer,
              unpaid_shipment,
              quantity
            FROM `{p}.{d}.V_SUPPLY_ORDERS_DASHBOARD`
            WHERE is_open = true
            ORDER BY order_date
        """.format(p=PROJECT_ID, d=DATASET_ID)
        po_rows = list(client.query(po_q).result())
        po_unpaid = {}
        ship_from_po_unpaid = {}
        po_detail = {}  # month -> [{po_id, product, mfr, ship, qty}]
        for r in po_rows:
            rd = dict(r)
            m = rd['est_pay_month']
            mfr = rd['unpaid_manufacturer'] or 0
            ship = rd['unpaid_shipment'] or 0
            if mfr > 0:
                po_unpaid[m] = po_unpaid.get(m, 0) + mfr
            if ship > 0:
                ship_month = min(12, m + 1)
                ship_from_po_unpaid[ship_month] = ship_from_po_unpaid.get(ship_month, 0) + ship
            if mfr > 0 or ship > 0:
                if m not in po_detail:
                    po_detail[m] = []
                po_detail[m].append({
                    'po': rd['purchase_order_id'],
                    'product': rd['product_name'],
                    'mfr': round(mfr, 2),
                    'ship': round(ship, 2),
                    'qty': rd['quantity'] or 0,
                })

        # Unpaid shipment amounts (shipping costs not yet paid)
        ship_q = """
            SELECT EXTRACT(MONTH FROM shipment_date) as month,
                   SUM(cost_shipped) as total,
                   SUM(CASE WHEN is_paid THEN cost_shipped ELSE 0 END) as paid,
                   SUM(CASE WHEN NOT is_paid THEN cost_shipped ELSE 0 END) as unpaid
            FROM `{p}.{d}.DE_MANUFACTURER_SHIPMENTS`
            WHERE EXTRACT(YEAR FROM shipment_date) = @year
            GROUP BY 1
        """.format(p=PROJECT_ID, d=DATASET_ID)
        ship_rows = list(client.query(ship_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter('year', 'INT64', year)]
        )).result())
        ship_unpaid = {}
        for r in ship_rows:
            rd = dict(r)
            if rd['unpaid'] and rd['unpaid'] > 0:
                ship_unpaid[rd['month']] = rd['unpaid']

        # Merge PO-derived unpaid shipping into ship_unpaid
        for m, amt in ship_from_po_unpaid.items():
            ship_unpaid[m] = ship_unpaid.get(m, 0) + amt

        return jsonify({
            'amazon': amazon, 'manufacturer': manufacturer, 'deliverer': deliverer,
            'po_unpaid': po_unpaid, 'ship_unpaid': ship_unpaid,
            'po_detail': po_detail, 'amazon_by_product': amazon_by_product,
        })
    except Exception as e:
        print(f"Error fetching cashflow actuals: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/po-summary/<int:year>', methods=['GET'])
def api_po_summary(year):
    """Get PO ordered totals by ASIN for a given year.
    Used by both DRAFT and APPROVED plans to show 'Already Ordered'.
    """
    try:
        query = """
            SELECT asin, product_name, total_ordered, po_count
            FROM `{dataset}.V_PLAN_PO_FULFILLMENT`
            WHERE order_year = @year
        """.format(dataset=f'{PROJECT_ID}.{DATASET_ID}')
        job = client.query(query, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter('year', 'INT64', year)]
        ))
        result = []
        for r in job.result():
            rd = dict(r)
            result.append({
                'asin': rd['asin'],
                'product_name': rd['product_name'],
                'ordered': rd['total_ordered'],
                'po_count': rd['po_count'],
            })
        return jsonify(result)
    except Exception as e:
        print(f"Error fetching PO summary: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/plans/<plan_id>/fulfillment', methods=['GET'])
def api_plan_fulfillment(plan_id):
    """Get PO fulfillment data for a plan, matched by ASIN.
    
    Returns per-product:
      - plan_qty: target from order_overrides_json
      - ordered_qty: sum of PO quantities for this ASIN + plan year
      - remaining: plan_qty - ordered_qty (clamped to 0)
      - pct_complete: ordered / plan (capped at 100)
      - po_count: number of POs
    """
    try:
        # Get the plan to extract order_overrides and plan_year
        query = """
            SELECT plan_year, order_overrides_json
            FROM `{dataset}.DE_PLAN_STRATEGY`
            WHERE plan_id = @plan_id
            LIMIT 1
        """.format(dataset=f'{PROJECT_ID}.{DATASET_ID}')
        job = client.query(query, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter('plan_id', 'STRING', plan_id)]
        ))
        rows = [dict(r) for r in job.result()]
        if not rows:
            return jsonify({'error': 'Plan not found'}), 404

        plan_year = rows[0].get('plan_year', 2026)
        overrides_json = rows[0].get('order_overrides_json')
        if not overrides_json:
            return jsonify([])

        import json as json_mod
        overrides = json_mod.loads(overrides_json)  # { product_name: qty }
        if not overrides:
            return jsonify([])

        # Get PO fulfillment by ASIN for the plan year
        po_query = """
            SELECT asin, product_name, total_ordered, po_count, first_po_date, last_po_date
            FROM `{dataset}.V_PLAN_PO_FULFILLMENT`
            WHERE order_year = @plan_year
        """.format(dataset=f'{PROJECT_ID}.{DATASET_ID}')
        po_job = client.query(po_query, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter('plan_year', 'INT64', plan_year)]
        ))
        po_by_asin = {}
        po_by_name = {}
        for r in po_job.result():
            rd = dict(r)
            po_by_asin[rd['asin']] = rd
            if rd.get('product_name'):
                po_by_name[rd['product_name']] = rd

        # Get ASIN→name mapping from DIM_PRODUCT
        dim_query = """
            SELECT asin, product_short_name
            FROM `{dataset}.DIM_PRODUCT`
            WHERE asin IS NOT NULL AND asin != 'UNKNOWN'
        """.format(dataset=f'{PROJECT_ID}.{DATASET_ID}')
        dim_job = client.query(dim_query)
        name_to_asin = {}
        for r in dim_job.result():
            rd = dict(r)
            if rd.get('product_short_name'):
                name_to_asin[rd['product_short_name']] = rd['asin']

        # Build fulfillment response
        result = []
        seen_asins = set()
        for product_name, plan_qty in overrides.items():
            asin = name_to_asin.get(product_name, '')
            po_data = po_by_asin.get(asin) or po_by_name.get(product_name) or {}
            ordered = po_data.get('total_ordered', 0)
            remaining = max(0, plan_qty - ordered)
            pct = min(100, round((ordered / plan_qty * 100) if plan_qty > 0 else 0, 1))
            result.append({
                'product': product_name,
                'asin': asin,
                'plan_qty': plan_qty,
                'ordered_qty': ordered,
                'remaining': remaining,
                'pct_complete': pct,
                'po_count': po_data.get('po_count', 0),
                'first_po_date': str(po_data.get('first_po_date', '')) if po_data.get('first_po_date') else None,
                'last_po_date': str(po_data.get('last_po_date', '')) if po_data.get('last_po_date') else None,
            })
            if asin:
                seen_asins.add(asin)

        # Also include products with POs that are NOT in overrides
        # (e.g. products ordered before being added to the plan)
        asin_to_name = {v: k for k, v in name_to_asin.items()}
        for asin, po_data in po_by_asin.items():
            if asin in seen_asins:
                continue
            product_name = po_data.get('product_name') or asin_to_name.get(asin, asin)
            ordered = po_data.get('total_ordered', 0)
            result.append({
                'product': product_name,
                'asin': asin,
                'plan_qty': 0,
                'ordered_qty': ordered,
                'remaining': 0,
                'pct_complete': 100,
                'po_count': po_data.get('po_count', 0),
                'first_po_date': str(po_data.get('first_po_date', '')) if po_data.get('first_po_date') else None,
                'last_po_date': str(po_data.get('last_po_date', '')) if po_data.get('last_po_date') else None,
            })

        return jsonify(result)

    except Exception as e:
        print(f"Error fetching plan fulfillment: {e}")
        import traceback; traceback.print_exc()
        return jsonify({'error': str(e)}), 500


@app.route('/api/plans/<plan_id>/shipments', methods=['GET'])
def api_shipments_get(plan_id):
    """Load saved shipment plan rows for a plan"""
    try:
        query = """
            SELECT plan_id, shipment_week, ship_number, ship_date, est_arrival,
                   route, route_reason, shipment_type, product, quantity,
                   num_boxes, total_cubic_feet, est_ship_cost, est_mfr_cost,
                   status, updated_at
            FROM `{t}`
            WHERE plan_id = @plan_id
            ORDER BY shipment_week, ship_number, product
        """.format(t=SHIPMENT_PLAN_TABLE)
        results = client.query(query, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result()
        rows = []
        for row in results:
            d = dict(row)
            # Convert date/datetime to ISO strings
            for key in ('ship_date', 'est_arrival'):
                if d.get(key):
                    d[key] = d[key].isoformat()
            if d.get('updated_at'):
                d['updated_at'] = d['updated_at'].isoformat()
            rows.append(d)
        return jsonify(rows)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/plans/<plan_id>/shipments', methods=['PUT'])
def api_shipments_save(plan_id):
    """Save/update shipment plan. Body: { rows: [...] }
    Uses delete-and-reinsert pattern (same as plan strategy).
    """
    try:
        data = request.get_json()
        if not data or not isinstance(data.get('rows'), list):
            return jsonify({'error': 'Expected { rows: [...] }'}), 400

        # Verify the parent plan exists
        check_q = """
            SELECT plan_id, status FROM `{t}` WHERE plan_id = @plan_id LIMIT 1
        """.format(t=PLAN_TABLE)
        check_rows = list(client.query(check_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result())
        if not check_rows:
            return jsonify({'error': 'Parent plan not found'}), 404

        # Delete existing shipment rows for this plan
        del_q = """DELETE FROM `{t}` WHERE plan_id = @plan_id""".format(t=SHIPMENT_PLAN_TABLE)
        client.query(del_q, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("plan_id", "STRING", plan_id)]
        )).result()

        now = datetime.now().isoformat()
        rows = []
        for item in data['rows']:
            rows.append({
                'plan_id': plan_id,
                'shipment_week': item['shipment_week'],
                'ship_number': item['ship_number'],
                'ship_date': item['ship_date'],
                'est_arrival': item['est_arrival'],
                'route': item['route'],
                'route_reason': item.get('route_reason'),
                'shipment_type': item['shipment_type'],
                'product': item['product'],
                'quantity': item['quantity'],
                'num_boxes': item.get('num_boxes'),
                'total_cubic_feet': item.get('total_cubic_feet'),
                'est_ship_cost': item.get('est_ship_cost'),
                'est_mfr_cost': item.get('est_mfr_cost'),
                'status': item.get('status', 'PLANNED'),
                'updated_at': now,
            })

        if rows:
            job_config = bigquery.LoadJobConfig(
                schema=SHIPMENT_PLAN_SCHEMA,
                write_disposition='WRITE_APPEND'
            )
            job = client.load_table_from_json(rows, SHIPMENT_PLAN_TABLE, job_config=job_config)
            job.result()
            if job.errors:
                return jsonify({'error': str(job.errors)}), 500

        clear_data_cache()
        return jsonify({'success': True, 'plan_id': plan_id, 'rows_saved': len(rows)})
    except Exception as e:
        import traceback
        print(f"Shipment plan save error: {traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/lov', methods=['GET'])
def api_lov_all():
    """All LOV sets at once: {lov_set: [{value_id, value_caption, is_default, attr1_*, attr2_*}]}."""
    try:
        return jsonify(get_lovs())
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/lov/<lov_set>', methods=['GET'])
def api_lov_get(lov_set):
    """Get list of values for a given lov_set (e.g. SHIPMENT_TYPE)"""
    try:
        query = """
            SELECT value_id, value_caption, is_default,
                   attr1_name, attr1_value, attr2_name, attr2_value
            FROM `{project}.{dataset}.DE_LIST_OF_VALUES`
            WHERE lov_set = @lov_set
            ORDER BY value_caption
        """.format(project=PROJECT_ID, dataset=DATASET_ID)
        results = client.query(query, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("lov_set", "STRING", lov_set)]
        )).result()
        rows = [dict(row) for row in results]
        return jsonify(rows)
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


# ═══════════════════════════════════════════════════════════════
# PPC CHANGE LOG API — close the loop on applied PPC changes
# Writes FACT_PPC_CHANGE_LOG; scored by V_PPC_ACTION_OUTCOMES.
# SOP: architecture/PPC_CLOSE_THE_LOOP.md
# ═══════════════════════════════════════════════════════════════

PPC_CHANGE_LOG_SCHEMA = [
    bigquery.SchemaField('change_id', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('batch_id', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('applied_at', 'TIMESTAMP', mode='REQUIRED'),
    bigquery.SchemaField('action', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('search_term', 'STRING'),
    bigquery.SchemaField('targeting', 'STRING'),
    bigquery.SchemaField('keyword_id', 'STRING'),
    bigquery.SchemaField('match_type', 'STRING'),
    bigquery.SchemaField('campaign_id', 'STRING'),
    bigquery.SchemaField('campaign_name', 'STRING'),
    bigquery.SchemaField('campaign_type', 'STRING'),
    bigquery.SchemaField('ad_group_id', 'STRING'),
    bigquery.SchemaField('product', 'STRING'),
    bigquery.SchemaField('old_bid', 'FLOAT'),
    bigquery.SchemaField('new_bid', 'FLOAT'),
    bigquery.SchemaField('old_budget', 'FLOAT'),
    bigquery.SchemaField('new_budget', 'FLOAT'),
    bigquery.SchemaField('target_spend_8w', 'FLOAT'),
    bigquery.SchemaField('target_orders_8w', 'INTEGER'),
    bigquery.SchemaField('target_net_roas_8w', 'FLOAT'),
    bigquery.SchemaField('coach_mode', 'STRING'),
    bigquery.SchemaField('source', 'STRING', mode='REQUIRED'),
    bigquery.SchemaField('expected_impact_weekly', 'FLOAT'),
    bigquery.SchemaField('expected_impact_kind', 'STRING'),
]


def _ppc_num(value):
    """Coerce an incoming JSON value to float, treating ''/None/garbage as NULL."""
    if value is None or value == '':
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _ppc_canon(value):
    """Canonical string form for the idempotency key (stable across re-POSTs)."""
    if value is None:
        return ''
    if isinstance(value, float):
        return repr(value)
    return str(value)


def _ppc_change_id(row):
    """Deterministic change_id so a re-POSTed identical change collapses instead of
    minting a fresh duplicate row. One logical change per object per applied-day —
    mirrors the client changeLogKey and the V_PPC_ACTION_OUTCOMES dedup. The MERGE
    in the insert route relies on this id being stable."""
    import hashlib
    obj = row.get('keyword_id') or row.get('targeting') or row.get('search_term') or ''
    day = (row.get('applied_at') or '')[:10]  # YYYY-MM-DD
    raw = '|'.join([
        row.get('campaign_id') or '',
        row.get('action') or '',
        obj,
        _ppc_canon(row.get('new_bid')),
        _ppc_canon(row.get('new_budget')),
        day,
    ])
    return 'chg_' + hashlib.sha1(raw.encode('utf-8')).hexdigest()[:12]


@app.route('/api/ppc-change-log', methods=['POST'])
def api_ppc_change_log_insert():
    """Persist applied PPC changes (DO page 'Uploaded to Amazon').

    Body JSON: array of items mirroring DoQueueItem fields:
      { "action": "REDUCE_BID", "search_term": "...", "targeting": "...",
        "keyword_id": "...", "match_type": "BROAD", "campaign_id": "...",
        "campaign_name": "...", "campaign_type": "...", "ad_group_id": "...",
        "product": "...", "old_bid": 0.8, "new_bid": 0.56,
        "old_budget": null, "new_budget": null,
        "target_spend_8w": 120.5, "target_orders_8w": 3, "target_net_roas_8w": 0.4,
        "coach_mode": "GUARDIAN", "source": "COACH",
        "expected_impact_weekly": 30.0, "expected_impact_kind": "save" }
    """
    try:
        data = request.get_json()
        if not data or not isinstance(data, list):
            return jsonify({'error': 'Expected JSON array of items'}), 400

        batch_id = f'batch_{datetime.now().strftime("%Y%m%d_%H%M%S")}_{uuid.uuid4().hex[:6]}'
        applied_at = datetime.utcnow().isoformat()

        rows = []
        for item in data:
            action = (item.get('action') or '').strip()
            if not action:
                continue  # an action-less row can never be scored
            orders_8w = item.get('target_orders_8w')
            row = {
                'batch_id': batch_id,
                # Offline-retried items carry their original timestamp
                'applied_at': item.get('applied_at') or applied_at,
                'action': action,
                'search_term': item.get('search_term') or None,
                'targeting': item.get('targeting') or None,
                'keyword_id': item.get('keyword_id') or None,
                'match_type': item.get('match_type') or None,
                'campaign_id': item.get('campaign_id') or None,
                'campaign_name': item.get('campaign_name') or None,
                'campaign_type': item.get('campaign_type') or None,
                'ad_group_id': item.get('ad_group_id') or None,
                'product': item.get('product') or None,
                'old_bid': _ppc_num(item.get('old_bid')),
                'new_bid': _ppc_num(item.get('new_bid')),
                'old_budget': _ppc_num(item.get('old_budget')),
                'new_budget': _ppc_num(item.get('new_budget')),
                'target_spend_8w': _ppc_num(item.get('target_spend_8w')),
                'target_orders_8w': int(orders_8w) if orders_8w not in (None, '') else None,
                'target_net_roas_8w': _ppc_num(item.get('target_net_roas_8w')),
                'coach_mode': item.get('coach_mode') or None,
                'source': item.get('source') if item.get('source') in ('COACH', 'MANUAL') else 'COACH',
                'expected_impact_weekly': _ppc_num(item.get('expected_impact_weekly')),
                'expected_impact_kind': (item.get('expected_impact_kind') or None),
            }
            row['change_id'] = _ppc_change_id(row)
            rows.append(row)

        if not rows:
            return jsonify({'error': 'No valid items (every item needs an action)'}), 400

        items_received = len(rows)
        # Dedup within this batch on the deterministic change_id (keep first).
        _seen = set()
        rows = [r for r in rows if not (r['change_id'] in _seen or _seen.add(r['change_id']))]

        # Idempotent insert: stage the batch, then MERGE … WHEN NOT MATCHED on change_id.
        # A re-POST (double-click / multi-tab / offline-flush race / dev StrictMode) becomes
        # a no-op instead of a duplicate row; BigQuery serialises DML on the target so
        # concurrent re-POSTs are race-safe. Staging table is dropped in finally().
        table_ref = f'{PROJECT_ID}.{DATASET_ID}.FACT_PPC_CHANGE_LOG'
        stage_ref = f'{PROJECT_ID}.{DATASET_ID}.FACT_PPC_CHANGE_LOG_stage_{uuid.uuid4().hex[:8]}'
        stage_job = client.load_table_from_json(
            rows, stage_ref,
            job_config=bigquery.LoadJobConfig(
                schema=PPC_CHANGE_LOG_SCHEMA,
                write_disposition='WRITE_TRUNCATE',
            ),
        )
        stage_job.result()
        if stage_job.errors:
            client.delete_table(stage_ref, not_found_ok=True)
            return jsonify({'error': str(stage_job.errors)}), 500

        try:
            cols = [f.name for f in PPC_CHANGE_LOG_SCHEMA]
            col_list = ', '.join(cols)
            val_list = ', '.join(f'S.{c}' for c in cols)
            merge_sql = f"""
                MERGE `{table_ref}` T
                USING `{stage_ref}` S
                ON T.change_id = S.change_id
                WHEN NOT MATCHED THEN
                  INSERT ({col_list}) VALUES ({val_list})
            """
            merge_job = client.query(merge_sql)
            merge_job.result()
            inserted = merge_job.num_dml_affected_rows or 0
        finally:
            client.delete_table(stage_ref, not_found_ok=True)

        # Fold the just-uploaded negates/removes into the owned registries
        # (DE_NEGATIVE_KEYWORDS / DE_NEGATIVE_TARGETS). Best-effort: a sync failure
        # must not fail the upload log — the MERGE is idempotent and will catch up next run.
        negatives_synced = False
        try:
            client.query(f'CALL `{PROJECT_ID}.{DATASET_ID}.SP_SYNC_NEGATIVES`()').result()
            negatives_synced = True
        except Exception as sync_err:
            print(f"SP_SYNC_NEGATIVES after change-log insert failed (non-fatal): {sync_err}")

        clear_data_cache()
        return jsonify({
            'success': True,
            'batch_id': batch_id,
            'items_received': items_received,
            'items_logged': inserted,  # rows actually inserted (re-POSTs dedup to 0)
            'negatives_synced': negatives_synced,
        })
    except Exception as e:
        import traceback
        print(f"PPC change log error: {traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/ppc-change-log', methods=['GET'])
def api_ppc_change_log_list():
    """Recent logged PPC changes — verification/debug."""
    try:
        limit = min(int(request.args.get('limit', 100)), 1000)
        query = f"""
            SELECT *
            FROM `{PROJECT_ID}.{DATASET_ID}.FACT_PPC_CHANGE_LOG`
            WHERE DATE(applied_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
            ORDER BY applied_at DESC
            LIMIT @limit
        """
        results = client.query(query, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("limit", "INT64", limit)]
        )).result()
        rows = [dict(row) for row in results]
        for r in rows:
            if r.get('applied_at'):
                r['applied_at'] = r['applied_at'].isoformat()
        return jsonify(rows)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ==========================================
# Shipment helpers (shared by HTML routes + JSON API)
# ==========================================

def delete_shipment_record(shipment_id):
    """Delete a shipment's lines then its header.  Returns [] on success, list of error strings on failure."""
    try:
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

        return []
    except Exception as e:
        error_msg = str(e)
        if 'streaming buffer' in error_msg.lower():
            return ["Cannot delete shipment: This shipment is still in BigQuery's streaming buffer. "
                    "This may be an older shipment created before we switched to batch loading. "
                    "Please wait 5-10 minutes and try again. "
                    "Note: New shipments created now can be deleted immediately."]
        return [f'Error deleting shipment: {error_msg}']


def add_shipment_line(shipment_id, data):
    """Add a PO line to a shipment.  Returns (errors_list, line_id_or_None)."""
    import math
    try:
        po_id = data.get('purchase_order_id')
        product_id_str = data.get('product_id', '')
        product_id = int(product_id_str) if product_id_str else None
        quantity = int(data.get('quantity_shipped', 0))

        if not po_id or quantity <= 0:
            return (['Please select a PO and enter a quantity > 0.'], None)

        # Look up product packaging info — prefer direct product_id, fallback to PO
        product_info = {}
        if product_id:
            pq = f"""
            SELECT package_quantity, package_cubic_feet
            FROM `{PRODUCTS_TABLE}` WHERE product_id = @pid
            """
            pq_cfg = bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter("pid", "INT64", product_id)
            ])
            pr = list(client.query(pq, job_config=pq_cfg).result())
            if pr:
                product_info = dict(pr[0])

        if not product_info:
            product_query = f"""
            SELECT dp.package_quantity, dp.package_cubic_feet
            FROM `{ORDERS_TABLE}` po
            LEFT JOIN `{PRODUCTS_TABLE}` dp ON po.product_id = dp.product_id
            WHERE po.purchase_order_id = @po_id
            LIMIT 1
            """
            job_config = bigquery.QueryJobConfig(
                query_parameters=[bigquery.ScalarQueryParameter("po_id", "STRING", po_id)]
            )
            product_result = list(client.query(product_query, job_config=job_config).result())
            product_info = dict(product_result[0]) if product_result else {}

        pkg_qty = product_info.get('package_quantity') or 1
        cubic_ft = product_info.get('package_cubic_feet')
        num_cartons = math.ceil(quantity / pkg_qty) if pkg_qty > 0 else None
        total_cubic_ft = (num_cartons * cubic_ft) if (num_cartons and cubic_ft) else None

        line_id = generate_id('SHL')
        line_row = {
            'line_id': line_id,
            'shipment_id': shipment_id,
            'purchase_order_id': po_id,
            'product_id': product_id,
            'quantity_shipped': quantity,
            'num_cartons': num_cartons,
            'cubic_feet_per_carton': cubic_ft,
            'total_cubic_feet': total_cubic_ft,
            'allocated_cost': None,
        }

        # Insert the line
        lines_table_ref = client.get_table(SHIPMENT_LINES_TABLE)
        lines_job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            autodetect=False,
            schema=lines_table_ref.schema
        )
        job = client.load_table_from_json([line_row], lines_table_ref, job_config=lines_job_config)
        job.result()

        if job.errors:
            return ([f'Error adding PO line: {job.errors}'], None)

        # Update shipment total_quantity
        update_qty_query = f"""
        UPDATE `{SHIPMENTS_TABLE}`
        SET total_quantity = COALESCE(total_quantity, 0) + @qty
        WHERE shipment_id = @shipment_id
        """
        qty_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("qty", "INT64", quantity),
                bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)
            ]
        )
        client.query(update_qty_query, job_config=qty_config).result()

        # Reset ready_quantity to NULL for this PO product
        if product_id is not None:
            reset_ready_query = f"""
            UPDATE `{ORDERS_TABLE}`
            SET ready_quantity = NULL
            WHERE purchase_order_id = @po_id AND product_id = @product_id
            """
            reset_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("po_id", "STRING", po_id),
                    bigquery.ScalarQueryParameter("product_id", "INT64", product_id)
                ]
            )
            client.query(reset_ready_query, job_config=reset_config).result()
        else:
            reset_ready_query = f"""
            UPDATE `{ORDERS_TABLE}`
            SET ready_quantity = NULL
            WHERE purchase_order_id = @po_id
            """
            reset_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("po_id", "STRING", po_id)
                ]
            )
            client.query(reset_ready_query, job_config=reset_config).result()

        return ([], line_id)
    except Exception as e:
        import traceback
        print(f"Add shipment line error: {traceback.format_exc()}")
        return ([f'Error adding PO line: {str(e)}'], None)


def update_shipment_line_fields(shipment_id, line_id, quantity_shipped, allocated_cost):
    """Update quantity_shipped and/or allocated_cost on a shipment line; recalc header total_quantity.
    Returns [] on success, list of error strings on failure."""
    try:
        updates = []
        params = [bigquery.ScalarQueryParameter("line_id", "STRING", line_id)]

        if quantity_shipped is not None:
            updates.append("quantity_shipped = @quantity")
            params.append(bigquery.ScalarQueryParameter("quantity", "INT64", int(quantity_shipped)))

        if allocated_cost is not None:
            updates.append("allocated_cost = @allocated_cost")
            params.append(bigquery.ScalarQueryParameter("allocated_cost", "FLOAT64", float(allocated_cost)))

        if not updates:
            return ['No changes to update']

        query = f"""
            UPDATE `{SHIPMENT_LINES_TABLE}`
            SET {', '.join(updates)}
            WHERE line_id = @line_id
        """
        job_config = bigquery.QueryJobConfig(query_parameters=params)
        job = client.query(query, job_config=job_config)
        job.result()

        if job.errors:
            return [f'Error updating line: {job.errors}']

        # Recalc header total_quantity
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
        client.query(recalc_query, job_config=recalc_config).result()

        return []
    except Exception as e:
        return [f'Error updating shipment line: {str(e)}']


def delete_shipment_line_record(shipment_id, line_id):
    """Delete a shipment line and recalc header total_quantity.  Returns [] on success, list of error strings on failure."""
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
            return [f'Error deleting line: {job.errors}']

        # Recalc header total_quantity
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

        return []
    except Exception as e:
        error_msg = str(e)
        if 'UPDATE or DELETE statement over table' in error_msg and 'would affect rows in the streaming buffer' in error_msg:
            return ['Cannot delete this line yet — it is still in BigQuery streaming buffer. Please wait 5-10 minutes and try again.']
        return [f'Error deleting shipment line: {error_msg}']


@app.route('/shipment/<shipment_id>/add_po_line', methods=['POST'])
@login_required
def add_po_line_to_shipment(shipment_id):
    """Add a PO line to an existing shipment."""
    data = {
        'purchase_order_id': request.form.get('purchase_order_id'),
        'product_id': request.form.get('product_id', ''),
        'quantity_shipped': request.form.get('quantity_shipped', 0),
    }
    errors, line_id = add_shipment_line(shipment_id, data)
    if errors:
        flash(errors[0], 'error')
    else:
        po_id = data['purchase_order_id']
        quantity = int(data['quantity_shipped'])
        clear_data_cache()
        flash(f'PO {po_id} linked to shipment with {quantity} units.', 'success')
    return redirect(url_for('shipment_details', shipment_id=shipment_id))


@app.route('/shipment/<shipment_id>/line/<line_id>/update', methods=['POST'])
@login_required
def update_shipment_line(shipment_id, line_id):
    """Update a single shipment line (quantity and allocated cost)."""
    quantity = request.form.get('quantity_shipped') or None
    allocated_cost = request.form.get('allocated_cost') or None
    errors = update_shipment_line_fields(shipment_id, line_id, quantity, allocated_cost)
    if errors:
        msg = errors[0]
        if msg == 'No changes to update':
            flash(msg, 'warning')
        else:
            flash(msg, 'danger')
    else:
        flash('Shipment line updated successfully', 'success')
        clear_data_cache()
    return redirect(url_for('shipment_details', shipment_id=shipment_id))


@app.route('/shipment/<shipment_id>/line/<line_id>/delete', methods=['POST'])
@login_required
def delete_shipment_line(shipment_id, line_id):
    """Delete a single shipment line."""
    errors = delete_shipment_line_record(shipment_id, line_id)
    if errors:
        msg = errors[0]
        if 'streaming buffer' in msg.lower():
            flash(msg, 'warning')
        else:
            flash(msg, 'danger')
    else:
        flash('Shipment line deleted successfully', 'success')
        clear_data_cache()
    return redirect(url_for('shipment_details', shipment_id=shipment_id))


# ==========================================
# Costs Report Page (Issue #9)
# ==========================================

@cache_result(ttl_seconds=300)  # Cache for 5 minutes (costs rarely change)
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


@app.route('/api/costs-report', methods=['GET'])
def api_costs_report():
    """Costs report rows (DIM_COSTS_HISTORY joined DIM_PRODUCT) as JSON for the Supply page."""
    try:
        rows = get_costs_history()
        for d in rows:
            for k, v in list(d.items()):
                if hasattr(v, 'isoformat'):
                    d[k] = v.isoformat()
        return jsonify(rows)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ==========================================
# Admin API Routes
# ==========================================

@app.route('/api/admin/pipeline-logs', methods=['GET'])
def get_pipeline_logs():
    """Get the latest orchestrator pipeline runs grouped by run_id"""
    query = """
    SELECT 
      run_id,
      run_date,
      MIN(started_at) as start_time,
      MAX(finished_at) as end_time,
      SUM(duration_seconds) as total_duration_seconds,
      COUNT(procedure_name) as total_tasks,
      SUM(CASE WHEN status = 'OK' THEN 1 ELSE 0 END) as success_count,
      SUM(CASE WHEN status != 'OK' THEN 1 ELSE 0 END) as fail_count,
      ARRAY_AGG(STRUCT(procedure_name, status, error_message, duration_seconds) ORDER BY started_at) as tasks
    FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
    GROUP BY run_id, run_date
    ORDER BY start_time DESC
    LIMIT 15
    """
    try:
        results = client.query(query).result()
        runs = []
        for row in results:
            run_dict = {
                'run_id': row.run_id,
                'run_date': row.run_date.isoformat() if row.run_date else None,
                'start_time': row.start_time.isoformat() if row.start_time else None,
                'end_time': row.end_time.isoformat() if row.end_time else None,
                'total_duration_seconds': row.total_duration_seconds,
                'total_tasks': row.total_tasks,
                'success_count': row.success_count,
                'fail_count': row.fail_count,
                'tasks': [dict(t) for t in row.tasks]
            }
            runs.append(run_dict)
        return jsonify({'success': True, 'runs': runs})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/admin/mapping-coverage', methods=['GET'])
def get_mapping_coverage():
    """Mapping/enrichment coverage checks — 'are the conversions done?'

    Reads V_ADMIN_MAPPING_COVERAGE: one row per check (campaign→strategy/family,
    campaign→experiment, advertised ASIN→DIM_PRODUCT) with the gap count and the
    offending entities. A gap means a spending campaign/ASIN is silently dropped
    from strategy evaluation, family rollups, or profit math.
    """
    query = """
    SELECT check_key, label, scope, total, mapped, gap, pct, critical, items
    FROM `onyga-482313.OI.V_ADMIN_MAPPING_COVERAGE`
    ORDER BY (gap > 0) DESC, critical DESC, gap DESC
    """
    try:
        results = client.query(query).result()
        checks = []
        for row in results:
            checks.append({
                'check_key': row.check_key,
                'label': row.label,
                'scope': row.scope,
                'total': row.total,
                'mapped': row.mapped,
                'gap': row.gap,
                'pct': row.pct,
                'critical': row.critical,
                # NB: use row['items'] — row.items collides with the Row.items() method
                'items': list(row['items']) if row['items'] else [],
            })
        return jsonify({'success': True, 'checks': checks})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ═══════════════════════════════════════════════
# CAMPAIGN MAPPING API
# Read V_CAMPAIGN_MAPPING_STATUS and let an admin
# approve/edit a campaign's family+strategy. Writes
# through to DIM_EXPERIMENT_CAMPAIGN (+DIM_EXPERIMENT).
# ═══════════════════════════════════════════════

# Canonical option lists for the dropdowns (validated server-side on assign)
MAPPING_FAMILIES = ['Bottle', 'Bunny', 'Fresh', 'LolliBall', 'LolliME', 'Lollibox']
MAPPING_STRATEGIES = ['BRAND_DEFENSE', 'CATEGORY_CONQUEST', 'COMPETITOR_CONQUEST',
                      'EXACT_BOOST', 'HUNTER', 'LOW_COST_DISCOVERY', 'PRODUCT_DEFENSE']
# Human-readable strategy label for generated experiment names
_STRATEGY_LABEL = {
    'EXACT_BOOST': 'Exact Boost', 'HUNTER': 'Broad Hunter',
    'LOW_COST_DISCOVERY': 'Auto Discovery', 'BRAND_DEFENSE': 'Brand Defense',
    'PRODUCT_DEFENSE': 'Product Defense', 'COMPETITOR_CONQUEST': 'Competitor Conquest',
    'CATEGORY_CONQUEST': 'Category Conquest',
}


@app.route('/api/admin/campaign-mapping', methods=['GET'])
def get_campaign_mapping():
    """List spending campaigns with their current mapping + source + suggestion."""
    query = """
    SELECT campaign_id, campaign_name, spend_60d,
           current_experiment_id, current_experiment_name, current_strategy_id,
           suggested_family, suggested_strategy, suggested_experiment_id,
           confidence, source
    FROM `onyga-482313.OI.V_CAMPAIGN_MAPPING_STATUS`
    ORDER BY (source IN ('unmapped','default')) DESC, spend_60d DESC
    """
    try:
        rows = [dict(r) for r in client.query(query).result()]
        return jsonify({
            'success': True,
            'campaigns': rows,
            'families': MAPPING_FAMILIES,
            'strategies': MAPPING_STRATEGIES,
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


def _build_experiment_id(family, strategy, campaign_name):
    """Generate experiment_id the same way SP_AUTO_ASSIGN_CAMPAIGNS does."""
    import re
    fam_token = re.sub(r'[^A-Z0-9]', '', family.upper())
    theme = None
    m = re.search(r'\((?:Boost, ?)?(.+?)\)', campaign_name or '')
    if m:
        theme = m.group(1)
    theme_token = re.sub(r'[^A-Z0-9]', '_', (theme or 'GENERAL').upper())
    return f"{fam_token}_{strategy}_{theme_token}", theme


@app.route('/api/admin/campaign-mapping/assign', methods=['POST'])
def assign_campaign_mapping():
    """Approve a {campaign_id, family, strategy} mapping.

    Resolves to an experiment_id (creating the experiment if needed), then
    upserts DIM_EXPERIMENT_CAMPAIGN with a 'manual:' note. Idempotent.
    """
    data = request.get_json(force=True) or {}
    campaign_id = data.get('campaign_id')
    family = data.get('family')
    strategy = data.get('strategy')

    if not campaign_id or not family or not strategy:
        return jsonify({'success': False, 'error': 'campaign_id, family and strategy are required'}), 400
    if family not in MAPPING_FAMILIES:
        return jsonify({'success': False, 'error': f'unknown family: {family}'}), 400
    if strategy not in MAPPING_STRATEGIES:
        return jsonify({'success': False, 'error': f'unknown strategy: {strategy}'}), 400

    user_email = session.get('user', {}).get('email', 'dashboard')

    try:
        # Resolve the campaign name (for experiment_id theme + the EC row)
        name_rows = list(client.query(
            "SELECT campaign_name FROM `onyga-482313.OI.DIM_CAMPAIGN` "
            "WHERE campaign_id = @cid AND is_current = TRUE LIMIT 1",
            job_config=bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter('cid', 'STRING', campaign_id),
            ])).result())
        if not name_rows:
            return jsonify({'success': False, 'error': 'campaign not found'}), 404
        campaign_name = name_rows[0].campaign_name

        experiment_id, theme = _build_experiment_id(family, strategy, campaign_name)
        experiment_name = f"{family} - {_STRATEGY_LABEL.get(strategy, strategy)}" + (f" ({theme})" if theme else "")
        note = f"manual: {user_email} {date.today().isoformat()}"

        # 1. Create the experiment if it doesn't exist (idempotent).
        # MERGE, not INSERT...WHERE NOT EXISTS: the latter is not race-safe in
        # BigQuery (no row locks / unique constraints), so a double-submit could
        # pass the NOT EXISTS check twice and create duplicate experiment_id rows
        # — which then breaks SP_EXPERIMENT_DAILY_SNAPSHOT's MERGE with
        # "must match at most one source row". A single MERGE keyed on
        # experiment_id is the atomic upsert (no WHEN MATCHED = leave existing
        # rows untouched).
        client.query(
            """
            MERGE `onyga-482313.OI.DIM_EXPERIMENT` T
            USING (SELECT @eid AS experiment_id) S
            ON T.experiment_id = S.experiment_id
            WHEN NOT MATCHED THEN INSERT
              (experiment_id, experiment_name, description, start_date, baseline_days,
               status, strategy_id, lifecycle_stage, season_context, created_at, updated_at)
            VALUES (@eid, @ename, @desc, CURRENT_DATE(), 14,
                    'ACTIVE', @strategy, 'ACTIVE', 'EVERGREEN', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP())
            """,
            job_config=bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter('eid', 'STRING', experiment_id),
                bigquery.ScalarQueryParameter('ename', 'STRING', experiment_name),
                bigquery.ScalarQueryParameter('desc', 'STRING', f'Manually mapped via Admin on {date.today().isoformat()}'),
                bigquery.ScalarQueryParameter('strategy', 'STRING', strategy),
            ])).result()

        # 2. Upsert DIM_EXPERIMENT_CAMPAIGN (MERGE: update if the campaign already has a row)
        client.query(
            """
            MERGE `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` T
            USING (SELECT @cid AS campaign_id) S
            ON T.campaign_id = S.campaign_id
            WHEN MATCHED THEN UPDATE SET
              experiment_id = @eid, campaign_name = @cname, notes = @note
            WHEN NOT MATCHED THEN INSERT (experiment_id, campaign_id, campaign_name, notes)
              VALUES (@eid, @cid, @cname, @note)
            """,
            job_config=bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter('cid', 'STRING', campaign_id),
                bigquery.ScalarQueryParameter('eid', 'STRING', experiment_id),
                bigquery.ScalarQueryParameter('cname', 'STRING', campaign_name),
                bigquery.ScalarQueryParameter('note', 'STRING', note),
            ])).result()

        clear_data_cache()
        return jsonify({
            'success': True,
            'campaign_id': campaign_id,
            'experiment_id': experiment_id,
            'strategy': strategy,
            'family': family,
            'source': 'manual',
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/admin/refresh', methods=['POST'])
def trigger_refresh():
    """Trigger the BigQuery orchestrator in the background"""
    query = "CALL `onyga-482313.OI.SP_ORCHESTRATE_DAILY_REFRESH`();"
    try:
        # We start the query but intentionally don't await .result() 
        # because it takes ~12 minutes and Cloud Run times out after 5 mins.
        job = client.query(query)
        return jsonify({
            'success': True, 
            'output': f"Orchestrator job started in background (Job ID: {job.job_id}). This will take ~10-15 minutes. Use the Refresh Logs button to track progress."
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/admin/refresh-shipments', methods=['POST'])
def trigger_refresh_shipments():
    """Refresh all Plan page supply chain data: DIM_PRODUCT → Inventory → Forecast → Shipment Suggestions"""
    query = "CALL `onyga-482313.OI.SP_REFRESH_SUGGESTIONS`();"
    try:
        # Runs 6 steps in order (~3-8 min), so start in background
        job = client.query(query)
        return jsonify({
            'success': True, 
            'output': f"Refreshing suggestions (DIM_PRODUCT → Inventory → Forecast → Shipment Plan). Job ID: {job.job_id}. This will take ~3-8 minutes."
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ═══════════════════════════════════════════════
# PHRASE NEGATIVES API
# Manages DE_PRODUCT_PHRASE_NEGATIVES for negative
# phrase/exact targeting rules per product family.
# ═══════════════════════════════════════════════

@app.route('/api/admin/phrase-negatives', methods=['GET'])
def api_phrase_negatives_list():
    """List all phrase negatives, grouped by parent_name."""
    try:
        query = f"""
            SELECT id, parent_name, product_short_name, phrase,
                   match_type, source, status
            FROM `{PHRASE_NEGATIVES_TABLE}`
            ORDER BY parent_name, phrase
        """
        results = client.query(query).result()
        phrases = [dict(row) for row in results]

        families = sorted(set(r['parent_name'] for r in phrases))
        return jsonify({'success': True, 'phrases': phrases, 'families': families})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/admin/phrase-negatives', methods=['POST'])
def api_phrase_negatives_add():
    """Add a single phrase negative.
    Body: { parent_name, phrase, product_short_name?, match_type?, source? }
    """
    try:
        data = request.get_json()
        parent_name = data.get('parent_name')
        phrase = data.get('phrase', '').strip().lower()

        if not parent_name or not phrase:
            return jsonify({'success': False, 'error': 'parent_name and phrase are required'}), 400

        match_type = data.get('match_type', 'Negative Phrase')
        source = data.get('source', 'MANUAL')
        product_short_name = data.get('product_short_name')
        row_id = str(uuid.uuid4())

        row = {
            'id': row_id,
            'parent_name': parent_name,
            'product_short_name': product_short_name,
            'phrase': phrase,
            'match_type': match_type,
            'source': source,
            'status': 'ACTIVE',
        }

        job_config = bigquery.LoadJobConfig(
            schema=[
                bigquery.SchemaField('id', 'STRING', mode='REQUIRED'),
                bigquery.SchemaField('parent_name', 'STRING', mode='REQUIRED'),
                bigquery.SchemaField('product_short_name', 'STRING', mode='NULLABLE'),
                bigquery.SchemaField('phrase', 'STRING', mode='REQUIRED'),
                bigquery.SchemaField('match_type', 'STRING', mode='REQUIRED'),
                bigquery.SchemaField('source', 'STRING', mode='REQUIRED'),
                bigquery.SchemaField('status', 'STRING', mode='REQUIRED'),
            ],
            write_disposition='WRITE_APPEND',
        )

        job = client.load_table_from_json([row], PHRASE_NEGATIVES_TABLE, job_config=job_config)
        job.result()

        if job.errors:
            return jsonify({'success': False, 'error': str(job.errors)}), 500

        clear_data_cache()
        return jsonify({'success': True, 'id': row_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/admin/phrase-negatives/bulk', methods=['POST'])
def api_phrase_negatives_bulk():
    """Bulk add phrases. Each phrase gets its own row.
    Body: { parent_name, phrases: ['word1', 'word2', ...], match_type?, source? }
    """
    try:
        data = request.get_json()
        parent_name = data.get('parent_name')
        phrases = data.get('phrases', [])

        if not parent_name or not phrases:
            return jsonify({'success': False, 'error': 'parent_name and phrases[] are required'}), 400

        match_type = data.get('match_type', 'Negative Phrase')
        source = data.get('source', 'MANUAL')
        product_short_name = data.get('product_short_name')

        rows = []
        for p in phrases:
            p_clean = p.strip().lower()
            if not p_clean:
                continue
            rows.append({
                'id': str(uuid.uuid4()),
                'parent_name': parent_name,
                'product_short_name': product_short_name,
                'phrase': p_clean,
                'match_type': match_type,
                'source': source,
                'status': 'ACTIVE',
            })

        if not rows:
            return jsonify({'success': False, 'error': 'No valid phrases provided'}), 400

        job_config = bigquery.LoadJobConfig(
            schema=[
                bigquery.SchemaField('id', 'STRING', mode='REQUIRED'),
                bigquery.SchemaField('parent_name', 'STRING', mode='REQUIRED'),
                bigquery.SchemaField('product_short_name', 'STRING', mode='NULLABLE'),
                bigquery.SchemaField('phrase', 'STRING', mode='REQUIRED'),
                bigquery.SchemaField('match_type', 'STRING', mode='REQUIRED'),
                bigquery.SchemaField('source', 'STRING', mode='REQUIRED'),
                bigquery.SchemaField('status', 'STRING', mode='REQUIRED'),
            ],
            write_disposition='WRITE_APPEND',
        )

        job = client.load_table_from_json(rows, PHRASE_NEGATIVES_TABLE, job_config=job_config)
        job.result()

        if job.errors:
            return jsonify({'success': False, 'error': str(job.errors)}), 500

        clear_data_cache()
        return jsonify({'success': True, 'count': len(rows)})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/admin/phrase-negatives/copy', methods=['POST'])
def api_phrase_negatives_copy():
    """Copy phrases from one family to another (skip duplicates).
    Body: { from_family, to_family, phrase_ids? }
    If phrase_ids is provided, only those specific phrases are copied.
    Otherwise, all phrases from from_family are copied.
    """
    try:
        data = request.get_json()
        from_family = data.get('from_family')
        to_family = data.get('to_family')
        phrase_ids = data.get('phrase_ids')  # optional list of specific IDs

        if not from_family or not to_family:
            return jsonify({'success': False, 'error': 'from_family and to_family are required'}), 400

        if from_family == to_family:
            return jsonify({'success': False, 'error': 'from_family and to_family must be different'}), 400

        # Get source phrases (optionally filtered by IDs)
        if phrase_ids and isinstance(phrase_ids, list) and len(phrase_ids) > 0:
            # Filter by specific IDs — use IN with a subquery
            placeholders = ', '.join([f'@id_{i}' for i in range(len(phrase_ids))])
            src_query = f"""
                SELECT phrase, match_type, source, product_short_name
                FROM `{PHRASE_NEGATIVES_TABLE}`
                WHERE parent_name = @from_family
                  AND id IN ({placeholders})
            """
            params = [bigquery.ScalarQueryParameter('from_family', 'STRING', from_family)]
            for i, pid in enumerate(phrase_ids):
                params.append(bigquery.ScalarQueryParameter(f'id_{i}', 'STRING', pid))
            src_config = bigquery.QueryJobConfig(query_parameters=params)
        else:
            src_query = f"""
                SELECT phrase, match_type, source, product_short_name
                FROM `{PHRASE_NEGATIVES_TABLE}`
                WHERE parent_name = @from_family
            """
            src_config = bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter('from_family', 'STRING', from_family),
            ])
        src_rows = [dict(r) for r in client.query(src_query, job_config=src_config).result()]

        # Get existing phrases in target
        tgt_query = f"""
            SELECT phrase
            FROM `{PHRASE_NEGATIVES_TABLE}`
            WHERE parent_name = @to_family
        """
        tgt_config = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('to_family', 'STRING', to_family),
        ])
        existing = set(r['phrase'] for r in client.query(tgt_query, job_config=tgt_config).result())

        rows_to_insert = []
        skipped = 0
        for src in src_rows:
            if src['phrase'] in existing:
                skipped += 1
                continue
            rows_to_insert.append({
                'id': str(uuid.uuid4()),
                'parent_name': to_family,
                'product_short_name': src.get('product_short_name'),
                'phrase': src['phrase'],
                'match_type': src['match_type'],
                'source': src['source'],
                'status': 'ACTIVE',
            })

        if rows_to_insert:
            job_config = bigquery.LoadJobConfig(
                schema=[
                    bigquery.SchemaField('id', 'STRING', mode='REQUIRED'),
                    bigquery.SchemaField('parent_name', 'STRING', mode='REQUIRED'),
                    bigquery.SchemaField('product_short_name', 'STRING', mode='NULLABLE'),
                    bigquery.SchemaField('phrase', 'STRING', mode='REQUIRED'),
                    bigquery.SchemaField('match_type', 'STRING', mode='REQUIRED'),
                    bigquery.SchemaField('source', 'STRING', mode='REQUIRED'),
                    bigquery.SchemaField('status', 'STRING', mode='REQUIRED'),
                ],
                write_disposition='WRITE_APPEND',
            )
            job = client.load_table_from_json(rows_to_insert, PHRASE_NEGATIVES_TABLE, job_config=job_config)
            job.result()

            if job.errors:
                return jsonify({'success': False, 'error': str(job.errors)}), 500

            clear_data_cache()

        return jsonify({'success': True, 'copied': len(rows_to_insert), 'skipped': skipped})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/admin/phrase-negatives/<phrase_id>', methods=['DELETE'])
def api_phrase_negatives_delete(phrase_id):
    """Delete a phrase negative by ID."""
    try:
        query = f"""
            DELETE FROM `{PHRASE_NEGATIVES_TABLE}`
            WHERE id = @id
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('id', 'STRING', phrase_id),
        ])
        result = client.query(query, job_config=jc).result()

        if result.num_dml_affected_rows == 0:
            return jsonify({'success': False, 'error': 'Phrase not found'}), 404

        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/admin/phrase-negatives/<phrase_id>', methods=['PUT'])
def api_phrase_negatives_update(phrase_id):
    """Update a phrase negative.
    Body can include: { phrase?, match_type?, status? }
    """
    try:
        data = request.get_json()
        updates = []
        params = [bigquery.ScalarQueryParameter('id', 'STRING', phrase_id)]

        if 'phrase' in data:
            updates.append('phrase = @phrase')
            params.append(bigquery.ScalarQueryParameter('phrase', 'STRING', data['phrase'].strip().lower()))

        if 'match_type' in data:
            updates.append('match_type = @match_type')
            params.append(bigquery.ScalarQueryParameter('match_type', 'STRING', data['match_type']))

        if 'status' in data:
            updates.append('status = @status')
            params.append(bigquery.ScalarQueryParameter('status', 'STRING', data['status']))

        if not updates:
            return jsonify({'success': False, 'error': 'No fields to update'}), 400

        updates.append('updated_at = CURRENT_TIMESTAMP()')

        query = f"""
            UPDATE `{PHRASE_NEGATIVES_TABLE}`
            SET {', '.join(updates)}
            WHERE id = @id
        """
        jc = bigquery.QueryJobConfig(query_parameters=params)
        result = client.query(query, job_config=jc).result()

        if result.num_dml_affected_rows == 0:
            return jsonify({'success': False, 'error': 'Phrase not found'}), 404

        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ═══════════════════════════════════════════════
# ALERTS API
# ═══════════════════════════════════════════════

@app.route('/api/alerts', methods=['GET'])
def api_alerts_list():
    """List alerts. ?status=OPEN (default) or ALL or DONE"""
    try:
        status = request.args.get('status', 'OPEN').upper()
        where = "WHERE status = 'OPEN'" if status == 'OPEN' else (
            "WHERE status = 'DONE'" if status == 'DONE' else '')
        query = f"""
            SELECT *
            FROM `{ALERTS_TABLE}`
            {where}
            ORDER BY
              CASE severity WHEN 'CRITICAL' THEN 0 WHEN 'WARNING' THEN 1 ELSE 2 END,
              created_at DESC
        """
        results = client.query(query).result()
        alerts = []
        for row in results:
            d = dict(row)
            for k in ('created_at', 'resolved_at', 'updated_at', 'snooze_until'):
                if d.get(k):
                    d[k] = d[k].isoformat()
            for k in ('breach_date',):
                if d.get(k):
                    d[k] = d[k].isoformat()
            alerts.append(d)
        return jsonify(alerts)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/alerts/count', methods=['GET'])
def api_alerts_count():
    """Return count of open alerts by severity for badge display"""
    try:
        query = f"""
            SELECT
              COUNTIF(severity = 'CRITICAL') as critical,
              COUNTIF(severity = 'WARNING') as warning,
              COUNTIF(severity = 'INFO') as info,
              COUNT(*) as total
            FROM `{ALERTS_TABLE}`
            WHERE status = 'OPEN'
        """
        row = list(client.query(query).result())[0]
        return jsonify(dict(row))
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/alerts/<alert_id>/done', methods=['POST'])
def api_alert_done(alert_id):
    """Mark alert as DONE"""
    try:
        notes = request.json.get('notes', '') if request.is_json else ''
        query = f"""
            UPDATE `{ALERTS_TABLE}`
            SET status = 'DONE', resolved_at = CURRENT_TIMESTAMP(),
                resolved_by = @user, notes = @notes
            WHERE id = @id AND status = 'OPEN'
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('id', 'STRING', alert_id),
            bigquery.ScalarQueryParameter('user', 'STRING', session.get('user_email', 'system')),
            bigquery.ScalarQueryParameter('notes', 'STRING', notes),
        ])
        client.query(query, job_config=jc).result()
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/alerts/<alert_id>/cancel', methods=['POST'])
def api_alert_cancel(alert_id):
    """Cancel/dismiss an alert"""
    try:
        notes = request.json.get('notes', '') if request.is_json else ''
        query = f"""
            UPDATE `{ALERTS_TABLE}`
            SET status = 'CANCELLED', resolved_at = CURRENT_TIMESTAMP(),
                resolved_by = @user, notes = @notes
            WHERE id = @id AND status = 'OPEN'
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('id', 'STRING', alert_id),
            bigquery.ScalarQueryParameter('user', 'STRING', session.get('user_email', 'system')),
            bigquery.ScalarQueryParameter('notes', 'STRING', notes),
        ])
        client.query(query, job_config=jc).result()
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500



@app.route('/api/alerts/<alert_id>/reopen', methods=['POST'])
def api_alert_reopen(alert_id):
    """Reopen/un-archive an alert"""
    try:
        query = f"""
            UPDATE `{ALERTS_TABLE}`
            SET status = 'OPEN',
                resolved_at = NULL,
                resolved_by = NULL
            WHERE id = @id
        """
        client.query(query, job_config=bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("id", "STRING", alert_id)]
        )).result()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/alerts/generate', methods=['POST'])
def api_alerts_generate():
    """Trigger SP_GENERATE_ALERTS on demand"""
    try:
        query = f"CALL `{PROJECT_ID}.{DATASET_ID}.SP_GENERATE_ALERTS`()"
        client.query(query).result()
        clear_data_cache()
        return jsonify({'success': True, 'message': 'Alerts generated successfully'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ═══════════════════════════════════════════════
# SHIPMENT PLAN SCHEDULING API
# Manages DE_SCHEDULED_SHIPMENTS for approval workflow:
#   SUGGESTED → APPROVED → SCHEDULED → SHIPPED
# ═══════════════════════════════════════════════

SCHEDULED_SHIPMENTS_TABLE = f'{PROJECT_ID}.{DATASET_ID}.DE_SCHEDULED_SHIPMENTS'

@app.route('/api/scheduled-shipments', methods=['GET'])
def api_get_scheduled_shipments():
    """Return all active rows from DE_SCHEDULED_SHIPMENTS for the dashboard.
    Bypasses Cube.js cache so approve/schedule actions are immediately visible.
    """
    try:
        query = f"""
            SELECT *
            FROM `{SCHEDULED_SHIPMENTS_TABLE}`
            WHERE status IN ('SUGGESTED', 'APPROVED', 'SCHEDULED')
            ORDER BY product, shipment_type, ship_wednesday
        """
        results = client.query(query).result()
        rows = []
        for row in results:
            d = dict(row)
            for k in list(d.keys()):
                v = d[k]
                if hasattr(v, 'isoformat'):
                    d[k] = v.isoformat()
            rows.append(d)
        return jsonify(rows)
    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'error': str(e)}), 500


@app.route('/api/shipment-plan/approve', methods=['POST'])
def api_shipment_plan_approve():
    """Approve a suggested shipment → flip status from SUGGESTED to APPROVED.
    Body: { schedule_id: string, ship_qty: number (optional), recalculate: boolean (optional) }
    """
    try:
        data = request.get_json()
        schedule_id = data.get('schedule_id')
        ship_qty = data.get('ship_qty')
        recalculate = data.get('recalculate', False)
        
        if not schedule_id:
            return jsonify({'error': 'Missing schedule_id'}), 400

        if ship_qty is not None:
            if int(ship_qty) <= 0:
                return jsonify({'error': 'ship_qty must be a positive integer'}), 400
            
            query = f"""
                UPDATE `{SCHEDULED_SHIPMENTS_TABLE}`
                SET status = 'APPROVED', approved_at = CURRENT_TIMESTAMP(), ship_qty = @qty
                WHERE schedule_id = @id AND status = 'SUGGESTED'
            """
            jc = bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter('qty', 'INT64', int(ship_qty)),
                bigquery.ScalarQueryParameter('id', 'STRING', schedule_id),
            ])
        else:
            query = f"""
                UPDATE `{SCHEDULED_SHIPMENTS_TABLE}`
                SET status = 'APPROVED', approved_at = CURRENT_TIMESTAMP()
                WHERE schedule_id = @id AND status = 'SUGGESTED'
            """
            jc = bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter('id', 'STRING', schedule_id),
            ])
            
        result = client.query(query, job_config=jc).result()

        if result.num_dml_affected_rows == 0:
            return jsonify({'error': 'Not found or not in SUGGESTED status'}), 404

        # --- Merge duplicate APPROVED shipments ---
        # When a new SUGGESTED row is approved for the same product/type/dates,
        # an older APPROVED row with different qty becomes a stale duplicate.
        # Keep only the most recently approved row (latest approved_at).
        merge_query = f"""
            DELETE FROM `{SCHEDULED_SHIPMENTS_TABLE}` s
            WHERE s.status = 'APPROVED'
              AND s.schedule_id != @id
              AND EXISTS (
                SELECT 1 FROM `{SCHEDULED_SHIPMENTS_TABLE}` keeper
                WHERE keeper.schedule_id = @id
                  AND keeper.status = 'APPROVED'
                  AND keeper.product = s.product
                  AND keeper.shipment_type = s.shipment_type
                  AND keeper.amazon_plan_date = s.amazon_plan_date
                  AND keeper.arrival_date = s.arrival_date
              )
        """
        merge_jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('id', 'STRING', schedule_id),
        ])
        merge_result = client.query(merge_query, job_config=merge_jc).result()
        merged_count = merge_result.num_dml_affected_rows or 0

        clear_data_cache()
        
        response_data = {'success': True, 'schedule_id': schedule_id}
        if ship_qty is not None:
            response_data['ship_qty'] = int(ship_qty)
        if merged_count > 0:
            response_data['merged_duplicates'] = merged_count
            
        if recalculate:
            # Trigger background generation of shipment plan
            job_query = "CALL `onyga-482313.OI.SP_GENERATE_SHIPMENT_PLAN`();"
            bg_job = client.query(job_query)
            response_data['job_id'] = bg_job.job_id
            
        return jsonify(response_data)
    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'error': str(e)}), 500


@app.route('/api/shipment-plan/approve-product', methods=['POST'])
def api_shipment_plan_approve_product():
    """Bulk approve ALL suggested shipments for a product in one DML.
    Body: { product: string }
    """
    try:
        data = request.get_json()
        product = data.get('product')
        if not product:
            return jsonify({'error': 'Missing product'}), 400

        query = f"""
            UPDATE `{SCHEDULED_SHIPMENTS_TABLE}`
            SET status = 'APPROVED', approved_at = CURRENT_TIMESTAMP()
            WHERE product = @product AND status = 'SUGGESTED'
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('product', 'STRING', product),
        ])
        result = client.query(query, job_config=jc).result()

        clear_data_cache()
        return jsonify({'success': True, 'product': product, 'affected': result.num_dml_affected_rows})
    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'error': str(e)}), 500


@app.route('/api/shipment-plan/unapprove-product', methods=['POST'])
def api_shipment_plan_unapprove_product():
    """Bulk unapprove ALL approved shipments for a product in one DML.
    Body: { product: string }
    """
    try:
        data = request.get_json()
        product = data.get('product')
        if not product:
            return jsonify({'error': 'Missing product'}), 400

        query = f"""
            UPDATE `{SCHEDULED_SHIPMENTS_TABLE}`
            SET status = 'SUGGESTED', approved_at = NULL
            WHERE product = @product AND status = 'APPROVED'
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('product', 'STRING', product),
        ])
        result = client.query(query, job_config=jc).result()

        clear_data_cache()
        return jsonify({'success': True, 'product': product, 'affected': result.num_dml_affected_rows})
    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'error': str(e)}), 500


@app.route('/api/shipment-plan/<schedule_id>/qty', methods=['PUT'])
def api_shipment_plan_update_qty(schedule_id):
    """Update quantity on an APPROVED shipment (qty is editable while APPROVED only).
    Body: { ship_qty: number }
    """
    try:
        data = request.get_json()
        new_qty = data.get('ship_qty')
        if new_qty is None or int(new_qty) <= 0:
            return jsonify({'error': 'ship_qty must be a positive integer'}), 400

        query = f"""
            UPDATE `{SCHEDULED_SHIPMENTS_TABLE}`
            SET ship_qty = @qty
            WHERE schedule_id = @id AND status = 'APPROVED'
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('qty', 'INT64', int(new_qty)),
            bigquery.ScalarQueryParameter('id', 'STRING', schedule_id),
        ])
        result = client.query(query, job_config=jc).result()

        if result.num_dml_affected_rows == 0:
            return jsonify({'error': 'Not found or not in APPROVED status'}), 404

        clear_data_cache()
        return jsonify({'success': True, 'schedule_id': schedule_id, 'ship_qty': int(new_qty)})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/shipment-plan/<schedule_id>/schedule', methods=['PUT'])
def api_shipment_plan_schedule(schedule_id):
    """Move APPROVED → SCHEDULED (manufacturer confirmed)."""
    try:
        query = f"""
            UPDATE `{SCHEDULED_SHIPMENTS_TABLE}`
            SET status = 'SCHEDULED', scheduled_at = CURRENT_TIMESTAMP()
            WHERE schedule_id = @id AND status = 'APPROVED'
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('id', 'STRING', schedule_id),
        ])
        result = client.query(query, job_config=jc).result()

        if result.num_dml_affected_rows == 0:
            return jsonify({'error': 'Not found or not in APPROVED status'}), 404

        clear_data_cache()
        return jsonify({'success': True, 'schedule_id': schedule_id, 'status': 'SCHEDULED'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/shipment-plan/<schedule_id>/revert', methods=['DELETE'])
def api_shipment_plan_revert(schedule_id):
    """Revert an APPROVED shipment back to SUGGESTED."""
    try:
        query = f"""
            UPDATE `{SCHEDULED_SHIPMENTS_TABLE}`
            SET status = 'SUGGESTED', approved_at = NULL
            WHERE schedule_id = @id AND status = 'APPROVED'
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('id', 'STRING', schedule_id),
        ])
        result = client.query(query, job_config=jc).result()

        if result.num_dml_affected_rows == 0:
            return jsonify({'error': 'Not found or not in APPROVED status'}), 404

        clear_data_cache()
        return jsonify({'success': True, 'schedule_id': schedule_id})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/shipment-plan/<schedule_id>/unschedule', methods=['PUT'])
def api_shipment_plan_unschedule(schedule_id):
    """Move SCHEDULED → APPROVED (unschedule)."""
    try:
        query = f"""
            UPDATE `{SCHEDULED_SHIPMENTS_TABLE}`
            SET status = 'APPROVED', scheduled_at = NULL
            WHERE schedule_id = @id AND status = 'SCHEDULED'
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('id', 'STRING', schedule_id),
        ])
        result = client.query(query, job_config=jc).result()

        if result.num_dml_affected_rows == 0:
            return jsonify({'error': 'Not found or not in SCHEDULED status'}), 404

        clear_data_cache()
        return jsonify({'success': True, 'schedule_id': schedule_id, 'status': 'APPROVED'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/launch_models', methods=['GET'])
def get_launch_models():
    """Get all model product assignments per family and available products"""
    try:
        query_models = f"""
        SELECT id, family, model_product, updated_at, updated_by
        FROM `{PROJECT_ID}.{DATASET_ID}.DE_NEW_PRODUCT_MODEL`
        ORDER BY family
        """
        models = list(client.query(query_models).result())
        
        query_products = f"""
        WITH product_history AS (
          SELECT
            product_short_name AS product,
            MIN(date) AS first_seen,
            DATE_DIFF(CURRENT_DATE(), MIN(date), DAY) AS history_days
          FROM `{PROJECT_ID}.{DATASET_ID}.T_UNIFIED_DAILY`
          GROUP BY 1
        ),
        available_rates AS (
          SELECT product, COALESCE(SUM(forecast_units) / 30, 0) as daily_rate
          FROM `{PROJECT_ID}.{DATASET_ID}.FACT_FORECAST_DEMAND`
          WHERE forecast_year = EXTRACT(YEAR FROM CURRENT_DATE()) 
            AND forecast_month = EXTRACT(MONTH FROM CURRENT_DATE())
          GROUP BY product
        )
        SELECT 
            fm.family as family,
            p.product_short_name as product,
            COALESCE(r.daily_rate, 0) as daily_rate,
            CASE 
                WHEN ph.product IS NULL THEN 1
                ELSE 0 
            END as is_new_product,
            CASE 
                WHEN ph.product IS NULL THEN 1
                WHEN COALESCE(ph.history_days, 0) < 60 THEN 1
                ELSE 0 
            END as is_draft
        FROM `{PROJECT_ID}.{DATASET_ID}.DIM_PRODUCT` p
        LEFT JOIN `{PROJECT_ID}.{DATASET_ID}.V_PRODUCT_FAMILY_MAP` fm ON p.asin = fm.asin
        LEFT JOIN product_history ph ON p.product_short_name = ph.product
        LEFT JOIN available_rates r ON p.product_short_name = r.product
        WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
          AND p.product_short_name IS NOT NULL
          AND p.is_active = true
        ORDER BY family, product
        """
        products = list(client.query(query_products).result())
        
        return jsonify({
            'success': True,
            'models': [dict(row) for row in models],
            'products': [dict(row) for row in products]
        })
    except Exception as e:
        print(f"Error fetching launch models: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/launch_models', methods=['POST'])
def update_launch_models():
    """Update model assignment for a family"""
    try:
        data = request.json
        family = data.get('family')
        model_product = data.get('model_product')
        user = session.get('user', {}).get('email', 'unknown')
        
        if not family or not model_product:
            return jsonify({'success': False, 'error': 'Missing family or model_product'}), 400
            
        # Check if exists
        check_query = f"""
        SELECT id FROM `{PROJECT_ID}.{DATASET_ID}.DE_NEW_PRODUCT_MODEL`
        WHERE LOWER(family) = LOWER(@family)
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter("family", "STRING", family)
        ])
        existing = list(client.query(check_query, job_config=jc).result())
        
        if existing:
            # Update
            record_id = existing[0].id
            query = f"""
            UPDATE `{PROJECT_ID}.{DATASET_ID}.DE_NEW_PRODUCT_MODEL`
            SET model_product = @model_product,
                updated_at = CURRENT_DATETIME(),
                updated_by = @user
            WHERE id = @id
            """
            job_config = bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter("model_product", "STRING", model_product),
                bigquery.ScalarQueryParameter("user", "STRING", user),
                bigquery.ScalarQueryParameter("id", "STRING", record_id)
            ])
            client.query(query, job_config=job_config).result()
        else:
            # Insert
            record_id = generate_id('LM')
            query = f"""
            INSERT INTO `{PROJECT_ID}.{DATASET_ID}.DE_NEW_PRODUCT_MODEL`
            (id, family, model_product, updated_at, updated_by)
            VALUES (@id, @family, @model_product, CURRENT_DATETIME(), @user)
            """
            job_config = bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter("id", "STRING", record_id),
                bigquery.ScalarQueryParameter("family", "STRING", family),
                bigquery.ScalarQueryParameter("model_product", "STRING", model_product),
                bigquery.ScalarQueryParameter("user", "STRING", user)
            ])
            client.query(query, job_config=job_config).result()
            
        return jsonify({'success': True, 'message': 'Launch model updated'})
    except Exception as e:
        print(f"Error updating launch model: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/trigger_forecast', methods=['POST'])
def trigger_forecast():
    """Trigger the BigQuery SP_LOAD_FACT_FORECAST_DEMAND procedure"""
    try:
        query = f"CALL `{PROJECT_ID}.{DATASET_ID}.SP_LOAD_FACT_FORECAST_DEMAND`();"
        client.query(query).result()
        return jsonify({'success': True, 'message': 'Forecast procedure completed successfully.'})
    except Exception as e:
        print(f"Error triggering forecast: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/open-pos', methods=['GET'])
def api_open_pos():
    """Return a list of open purchase orders for the React dashboard."""
    try:
        open_pos = get_open_pos_for_shipment(include_all=False)
        return jsonify({'success': True, 'data': open_pos})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# ─── Research: shared synonym groups + ranked-score projection ──────────
# Hardcoded fallback synonym groups; DE_SYNONYM_CACHE (Gemini-populated)
# takes priority, these unlock Related mode when the cache misses.
_SYNONYM_GROUPS = [
    ['bff', 'best friend', 'bestie'],
    ['birthday', 'bday', 'b day'],
    ['christmas', 'xmas', 'holiday'],
    ['teen', 'teenager', 'teenage'],
    ['tween', 'preteen', 'pre teen'],
    ['kid', 'kids', 'child', 'children'],
    ['girl', 'girls'],
    ['boy', 'boys'],
    ['gift', 'gifts', 'present', 'presents'],
    ['diy', 'craft', 'crafts'],
    ['jewelry', 'jewellery'],
    ['makeup', 'make up', 'cosmetic', 'cosmetics'],
    ['diary', 'journal', 'journals', 'journaling', 'notebook'],
    ['spa', 'bath', 'bath bomb', 'bath set'],
    ['unicorn', 'unicorns'],
    ['princess', 'princesses'],
    ['stocking stuffer', 'stocking filler'],
    ['backpack', 'back pack', 'school bag'],
]
_SYNONYM_MAP = {}
for _group in _SYNONYM_GROUPS:
    for _word in _group:
        _SYNONYM_MAP[_word.lower()] = [w for w in _group if w.lower() != _word.lower()]

_RESEARCH_STOP_WORDS = {'a', 'an', 'the', 'for', 'and', 'or', 'of', 'to', 'in', 'on', 'at', 'by', 'is', 'it', 'my', 'with'}


def _research_ranked_select(parent, alias='t'):
    """Projection + JOIN for enriching term rows with FACT_RESEARCH_RANKED
    per-family scores. Returns (cols_sql, join_sql); NULL-typed placeholders
    and empty join when no parent is given."""
    if parent:
        join = (
            "LEFT JOIN `onyga-482313`.OI.FACT_RESEARCH_RANKED rr "
            f"ON rr.parent_name = @parent AND LOWER(rr.query_text) = LOWER({alias}.query_text)"
        )
        cols = """
          rr.cpc_12m, rr.cpc_30d, rr.units_cvr_30d, rr.units_cvr_12m,
          COALESCE(rr.ads_family_orders, 0) AS ads_family_orders,
          COALESCE(rr.ads_units_30d, 0) AS ads_units_30d, COALESCE(rr.ads_units_12m, 0) AS ads_units_12m,
          rr.ads_cost_7d, rr.exact_kw_cost_7d, rr.phrase_kw_cost_7d, rr.broad_kw_cost_7d, rr.roas_30d,
          rr.cvr_christmas, rr.cvr_easter, rr.cvr_valentines, rr.cvr_graduation, rr.cvr_back_to_school, rr.cvr_mothers_day,
          rr.seg_fit, rr.cps_fit, rr.overall_fit,
          rr.gender_score, rr.age_score, rr.occasion_score, rr.pt_score,
          rr.cps_source, rr.effective_cps, rr.price_bucket, rr.is_holiday_active,
          rr.purchase_rank AS purchase_rank_score, rr.rank AS rank_score,
          rr.ads_purch, rr.ads_cps, rr.est_cps, rr.est_cps_curve, rr.intent_factor,
          COALESCE(rr.family_purchases, 0) AS family_purchases,
          COALESCE(rr.family_clicks, 0) AS family_clicks,
          COALESCE(rr.family_impressions, 0) AS family_impressions"""
    else:
        join = ""
        cols = """
          CAST(NULL AS FLOAT64) AS cpc_12m, CAST(NULL AS FLOAT64) AS cpc_30d,
          CAST(NULL AS FLOAT64) AS units_cvr_30d, CAST(NULL AS FLOAT64) AS units_cvr_12m,
          0 AS ads_family_orders, 0 AS ads_units_30d, 0 AS ads_units_12m,
          CAST(NULL AS FLOAT64) AS ads_cost_7d, CAST(NULL AS FLOAT64) AS exact_kw_cost_7d, CAST(NULL AS FLOAT64) AS phrase_kw_cost_7d, CAST(NULL AS FLOAT64) AS broad_kw_cost_7d, CAST(NULL AS FLOAT64) AS roas_30d,
          CAST(NULL AS FLOAT64) AS cvr_christmas, CAST(NULL AS FLOAT64) AS cvr_easter,
          CAST(NULL AS FLOAT64) AS cvr_valentines, CAST(NULL AS FLOAT64) AS cvr_graduation,
          CAST(NULL AS FLOAT64) AS cvr_back_to_school, CAST(NULL AS FLOAT64) AS cvr_mothers_day,
          CAST(NULL AS FLOAT64) AS seg_fit, CAST(NULL AS INT64) AS cps_fit, CAST(NULL AS FLOAT64) AS overall_fit,
          CAST(NULL AS INT64) AS gender_score, CAST(NULL AS INT64) AS age_score,
          CAST(NULL AS INT64) AS occasion_score, CAST(NULL AS INT64) AS pt_score,
          CAST(NULL AS STRING) AS cps_source, CAST(NULL AS FLOAT64) AS effective_cps,
          CAST(NULL AS STRING) AS price_bucket,
          CAST(NULL AS BOOL) AS is_holiday_active,
          CAST(NULL AS FLOAT64) AS purchase_rank_score, CAST(NULL AS FLOAT64) AS rank_score,
          CAST(NULL AS INT64) AS ads_purch, CAST(NULL AS FLOAT64) AS ads_cps, CAST(NULL AS FLOAT64) AS est_cps,
          CAST(NULL AS FLOAT64) AS est_cps_curve, CAST(NULL AS FLOAT64) AS intent_factor,
          0 AS family_purchases, 0 AS family_clicks, 0 AS family_impressions"""
    return cols, join


@app.route('/api/research/related-terms', methods=['POST'])
def research_related_terms():
    """Find related search queries by co-occurrence with a seed term.

    Accepts JSON body:
      { "term": "birthday", "parent": "Bunny", "mode": "direct"|"phrase"|"broad", "synonyms": {...} }
    parent is optional – when supplied, rows are enriched with that family's
    pre-computed scores from FACT_RESEARCH_RANKED.

    Term aggregates come from FACT_RESEARCH_TERMS (104-week window, refreshed
    by SP_REFRESH_RESEARCH_RANKED); only the ASIN co-occurrence seed CTEs run
    at request time.

    Returns a JSON array sorted by market_purchases DESC.
    """
    data = request.get_json()
    term = (data.get('term') or '').strip()
    weeks = 104  # co-occurrence window — matches the FACT layer's fixed window
    parent = (data.get('parent') or '').strip() or None

    if not term:
        return jsonify({'error': 'term is required'}), 400

    mode = (data.get('mode') or 'phrase').strip()  # 'direct' | 'phrase' | 'broad' (default phrase; was 'direct'/substring pre-2026-06-16)
    if mode not in ('direct', 'phrase', 'broad'):
        mode = 'phrase'
    # Frontend can pass pre-fetched synonyms from Gemini: {"bff": ["best friend", "bestie"]}
    frontend_synonyms = data.get('synonyms') or {}

    rr_cols, rr_join = _research_ranked_select(parent, alias='t')

    if mode == 'broad':
        # Broad = Phrase reach + synonym expansion (the former 'related' mode): per-word
        # OR over [word + synonyms], AND-ed across words, over the full ASIN co-occurrence
        # net (no match_filter), marking rows direct vs related.
        words = [w for w in term.strip().split() if w.lower() not in _RESEARCH_STOP_WORDS]
        if not words:
            # All words were stop words — use entire term as one pattern
            words = [term.strip()]
        word_groups_sq = []
        word_groups_t = []
        word_param_map = []
        for i, word in enumerate(words):
            gemini_syns = frontend_synonyms.get(word.lower(), [])
            hardcoded_syns = _SYNONYM_MAP.get(word.lower(), [])
            all_syns = list(dict.fromkeys([word] + gemini_syns + hardcoded_syns))  # dedupe, preserve order
            or_parts_sq = []
            or_parts_t = []
            for j, syn in enumerate(all_syns):
                param_name = f'word_{i}_{j}'
                or_parts_sq.append(f"LOWER(sq.query_text) LIKE LOWER(@{param_name})")
                or_parts_t.append(f"LOWER(t.query_text) LIKE LOWER(@{param_name})")
                word_param_map.append((param_name, f'%{syn}%'))
            word_groups_sq.append(f"({' OR '.join(or_parts_sq)})")
            word_groups_t.append(f"({' OR '.join(or_parts_t)})")
        word_likes_sq = ' AND '.join(word_groups_sq)
        word_likes_t = ' AND '.join(word_groups_t)

        sql = f"""
        WITH seed_asins AS (
          SELECT DISTINCT sq.ASIN
          FROM `onyga-482313`.OI.FACT_SEARCH_QUERY sq
          WHERE {word_likes_sq}
            AND sq.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL @weeks WEEK)
        ),
        seed_count AS (
          SELECT COUNT(*) AS total_seed_asins FROM seed_asins
        ),
        related_queries AS (
          SELECT
            sq2.query_text,
            COUNT(DISTINCT sq2.ASIN) AS asin_overlap
          FROM `onyga-482313`.OI.FACT_SEARCH_QUERY sq2
          WHERE sq2.ASIN IN (SELECT ASIN FROM seed_asins)
            AND sq2.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL @weeks WEEK)
            AND sq2.query_text != 'OTHER'
          GROUP BY sq2.query_text
        )
        SELECT
          t.*,
          CASE WHEN {word_likes_t} THEN 'direct' ELSE 'related' END AS match_type,
          rq.asin_overlap,
          sc.total_seed_asins,
          ROUND(SAFE_DIVIDE(rq.asin_overlap, sc.total_seed_asins) * 100, 1) AS overlap_pct,
          {rr_cols}
        FROM related_queries rq
        JOIN `onyga-482313`.OI.FACT_RESEARCH_TERMS t ON t.query_text = rq.query_text
        CROSS JOIN seed_count sc
        {rr_join}
        ORDER BY t.market_purchases DESC
        """
    else:
        # Direct / Phrase = parity with the recommendation coverage_count: match over the
        # FULL term universe (FACT_RESEARCH_TERMS, no ASIN co-occurrence gate), using the
        # SAME tokenization as SP_REFRESH_RESEARCH_RECOMMENDATIONS — punctuation-delimited
        # tokens, bidirectional plural (trailing-'s' strip on both sides), whole-word via a
        # space-padded normalized term. So a Phrase search returns exactly the terms the
        # card's "covers N" counts (plus the seed itself).
        word_param_map, rx_names = research_match_predicate(term, mode, _RESEARCH_STOP_WORDS)
        # NORM(col): punctuation -> space, pad with spaces, strip one trailing 's' per word.
        norm_t = ("REGEXP_REPLACE(CONCAT(' ', "
                  "REGEXP_REPLACE(LOWER(t.query_text), r'[^a-z0-9]+', ' '), ' '), r's ', ' ')")
        if not rx_names:
            match_pred = 'FALSE'  # term had no usable tokens — match nothing
        elif mode == 'direct':
            match_pred = f"{norm_t} = @rx_0"  # exact term + plural/punctuation variants
        else:  # phrase
            match_pred = ' AND '.join(f"STRPOS({norm_t}, @{n}) > 0" for n in rx_names)

        sql = f"""
        SELECT
          t.*,
          'direct' AS match_type,
          CAST(NULL AS INT64) AS asin_overlap,
          CAST(NULL AS INT64) AS total_seed_asins,
          CAST(NULL AS FLOAT64) AS overlap_pct,
          {rr_cols}
        FROM `onyga-482313`.OI.FACT_RESEARCH_TERMS t
        {rr_join}
        WHERE t.query_text != 'OTHER' AND {match_pred}
        ORDER BY t.market_purchases DESC
        """

    query_params = [
        bigquery.ScalarQueryParameter('weeks', 'INT64', weeks),
    ]
    for param_name, param_val in word_param_map:
        query_params.append(bigquery.ScalarQueryParameter(param_name, 'STRING', param_val))
    if parent:
        query_params.append(
            bigquery.ScalarQueryParameter('parent', 'STRING', parent)
        )

    job_config = bigquery.QueryJobConfig(query_parameters=query_params)

    try:
        results = client.query(sql, job_config=job_config).result()
        rows = [dict(row) for row in results]
        return jsonify(rows)
    except Exception as e:
        print(f"Error in research_related_terms: {e}")
        return jsonify({'error': str(e)}), 500


# ─── Synonym lookup (in-memory cache + BigQuery table) ──────────
_synonym_cache = {}

@app.route('/api/research/get-synonyms', methods=['POST'])
def research_get_synonyms():
    """Look up synonyms from DE_SYNONYM_CACHE table.

    Accepts JSON body: { "words": ["bff", "gift"] }
    Returns JSON: { "bff": ["best friend", "bestie"], "gift": ["gifts", "present"] }
    """
    data = request.get_json()
    words = data.get('words', [])
    if not words:
        return jsonify({})

    # 1. Check in-memory cache
    result = {}
    uncached_words = []
    for w in words:
        wl = w.lower().strip()
        if wl in _synonym_cache:
            result[wl] = _synonym_cache[wl]
        else:
            uncached_words.append(wl)

    if not uncached_words:
        return jsonify(result)

    # 2. Look up from BigQuery
    try:
        sql = """
        SELECT word, synonyms
        FROM `onyga-482313`.OI.DE_SYNONYM_CACHE
        WHERE word IN UNNEST(@words)
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ArrayQueryParameter('words', 'STRING', uncached_words)
        ])
        rows = client.query(sql, job_config=jc).result()
        for row in rows:
            syns = json_lib.loads(row['synonyms'])
            _synonym_cache[row['word']] = syns
            result[row['word']] = syns
    except Exception as e:
        print(f"Error reading synonyms from BQ: {e}")

    # Words not in the table fall back to the hardcoded synonym groups
    # (unlocks Related mode even when DE_SYNONYM_CACHE misses)
    for w in uncached_words:
        if w not in result:
            fallback = _SYNONYM_MAP.get(w, [])
            _synonym_cache[w] = fallback
            result[w] = fallback

    return jsonify(result)

@app.route('/api/research/conversion-curve', methods=['GET'])
@cache_result(ttl_seconds=600)  # param-less endpoint — safe to cache
def research_conversion_curve():
    """Return the pre-computed conversion curve from V_CONVERSION_CURVE.
    Used by the Research page to estimate clicks-per-sale for any product × search term.
    """
    try:
        sql = """
        SELECT
          parent_name,
          price_bucket,
          price_ratio_low,
          price_ratio_high,
          holiday_name,
          total_clicks,
          total_orders,
          clicks_per_sale,
          cvr_pct,
          cost_per_sale,
          avg_cpc
        FROM `onyga-482313`.OI.V_CONVERSION_CURVE
        ORDER BY parent_name, price_bucket, holiday_name
        """
        results = client.query(sql).result()
        rows = [dict(row) for row in results]
        return jsonify(rows)
    except Exception as e:
        print(f"Error in research_conversion_curve: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/research/top-terms', methods=['GET'])
def research_top_terms():
    """Default Research overview: top search terms for a family ORDERED BY RANK
    (the opportunity score), 104-week window from FACT_RESEARCH_TERMS, enriched
    with per-family scores from FACT_RESEARCH_RANKED. Client sorts/paginates.

    No brand_purchases filter — the list must be a complete ranked view so a
    high-rank term we don't yet sell on (e.g. a recommendation) still appears
    at its rank position, consistent with search. Capped at 5000 by rank to
    keep the payload bounded; rank-90+ terms are always well within that.
    Without a parent there is no per-family rank, so fall back to market volume.
    """
    parent = (request.args.get('parent') or '').strip() or None
    try:
        rr_cols, rr_join = _research_ranked_select(parent, alias='t')
        order_by = ("rr.rank DESC NULLS LAST, t.market_purchases DESC NULLS LAST"
                    if parent else "t.market_purchases DESC NULLS LAST")
        sql = f"""
        SELECT t.*, {rr_cols}
        FROM `onyga-482313`.OI.FACT_RESEARCH_TERMS t
        {rr_join}
        ORDER BY {order_by}
        LIMIT 5000
        """
        params = [bigquery.ScalarQueryParameter('parent', 'STRING', parent)] if parent else []
        job_config = bigquery.QueryJobConfig(query_parameters=params) if params else None
        rows = [dict(row) for row in client.query(sql, job_config=job_config).result()]
        return jsonify(rows)
    except Exception as e:
        print(f"Error in research_top_terms: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/research/term-ranks', methods=['POST'])
def research_term_ranks():
    """Per-family rank breakdown for a batch of terms (hover comparison).

    Body: { "terms": ["...", ...] }  (≤500, lowercased server-side)
    Returns: { "<term>": [ {parent_name, rank, purchase_rank, overall_fit,
                            seg_fit, cps_fit, ads_cps, est_cps}, ... ] }
    """
    data = request.get_json() or {}
    terms = [t.lower() for t in (data.get('terms') or []) if isinstance(t, str)][:500]
    if not terms:
        return jsonify({})
    try:
        sql = """
        SELECT parent_name, LOWER(query_text) AS query_text,
               rank, purchase_rank, overall_fit, seg_fit, cps_fit, ads_cps, est_cps
        FROM `onyga-482313`.OI.FACT_RESEARCH_RANKED
        WHERE LOWER(query_text) IN UNNEST(@terms)
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ArrayQueryParameter('terms', 'STRING', terms)
        ])
        out = {}
        for row in client.query(sql, job_config=jc).result():
            d = dict(row)
            out.setdefault(d.pop('query_text'), []).append(d)
        return jsonify(out)
    except Exception as e:
        print(f"Error in research_term_ranks: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/research/recommendations', methods=['GET'])
def research_recommendations():
    """Current keyword recommendations for a family, grouped by rec_type.

    Query: ?parent=<family>
    Returns: { "EXACT": [...], "PHRASE": [...], "BROAD": [...], "BRAND": [...] }
    Each row: {keyword, match_type, rank, overall_fit, market_sales, market_volume,
               coverage_count, cluster_size, status, week_start}
    Reads FACT_RESEARCH_RECOMMENDATIONS (same table the coacher reads).
    """
    parent = (request.args.get('parent') or '').strip()
    if not parent:
        return jsonify({'error': 'parent is required'}), 400
    try:
        sql = """
        SELECT rec_type, match_type, keyword, rank, overall_fit, market_sales,
               market_volume, coverage_count, cluster_size, status,
               CAST(week_start AS STRING) AS week_start
        FROM `onyga-482313`.OI.FACT_RESEARCH_RECOMMENDATIONS
        WHERE parent_name = @parent AND status IN ('NEW','ADVERTISED')
        ORDER BY rec_type, status, market_sales DESC NULLS LAST, rank DESC NULLS LAST
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('parent', 'STRING', parent)
        ])
        out = {'EXACT': [], 'PHRASE': [], 'BROAD': [], 'BRAND': []}
        for row in client.query(sql, job_config=jc).result():
            d = dict(row)
            out.setdefault(d['rec_type'], []).append(d)
        return jsonify(out)
    except Exception as e:
        print(f"Error in research_recommendations: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/research/update-segments', methods=['POST'])
def research_update_segments():
    """Atomically upsert manual segment overrides for a search term.

    Overrides win immediately in V_SQP_QUERY_WEEKLY / V_RESEARCH_RANKED
    (COALESCE) and surface in the FACT_RESEARCH_* tables on the next
    SP_REFRESH_RESEARCH_RANKED run.
    """
    data = request.get_json()
    query_text = (data.get('query_text') or '').strip()
    if not query_text:
        return jsonify({'error': 'query_text is required'}), 400

    fields = ['gender', 'age_group', 'occasion', 'cost_tier', 'product_type', 'brand']
    updates = {f: data.get(f) for f in fields if f in data}
    if not updates:
        return jsonify({'error': 'No segment fields provided'}), 400

    try:
        sql = """
        MERGE `onyga-482313`.OI.DE_SEARCH_TERM_SEGMENTS t
        USING (SELECT @query_text AS query_text) s
        ON t.query_text = s.query_text
        WHEN MATCHED THEN UPDATE SET
          gender = @gender, age_group = @age_group, occasion = @occasion,
          cost_tier = @cost_tier, product_type = @product_type, brand = @brand,
          updated_at = CURRENT_TIMESTAMP()
        WHEN NOT MATCHED THEN INSERT
          (query_text, gender, age_group, occasion, cost_tier, product_type, brand, updated_at)
        VALUES (@query_text, @gender, @age_group, @occasion, @cost_tier, @product_type, @brand, CURRENT_TIMESTAMP())
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('query_text', 'STRING', query_text),
            bigquery.ScalarQueryParameter('gender', 'STRING', updates.get('gender')),
            bigquery.ScalarQueryParameter('age_group', 'STRING', updates.get('age_group')),
            bigquery.ScalarQueryParameter('occasion', 'STRING', updates.get('occasion')),
            bigquery.ScalarQueryParameter('cost_tier', 'STRING', updates.get('cost_tier')),
            bigquery.ScalarQueryParameter('product_type', 'STRING', updates.get('product_type')),
            bigquery.ScalarQueryParameter('brand', 'STRING', updates.get('brand')),
        ])
        client.query(sql, job_config=jc).result()
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        print(f"Error in research_update_segments: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/research/get-segments', methods=['POST'])
def research_get_segments():
    """Get manual segment overrides for given query texts."""
    data = request.get_json()
    query_texts = data.get('query_texts', [])
    if not query_texts:
        return jsonify({})

    try:
        sql = """
        SELECT query_text, gender, age_group, occasion, cost_tier, product_type, brand
        FROM `onyga-482313`.OI.DE_SEARCH_TERM_SEGMENTS
        WHERE query_text IN UNNEST(@texts)
        """
        job_config = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ArrayQueryParameter('texts', 'STRING', query_texts)
        ])
        results = client.query(sql, job_config=job_config).result()
        overrides = {}
        for row in results:
            d = dict(row)
            overrides[d['query_text']] = d
        return jsonify(overrides)
    except Exception as e:
        print(f"Error in research_get_segments: {e}")
        return jsonify({})


@app.route('/api/research/products', methods=['GET'])
@cache_result(ttl_seconds=300)  # param-less endpoint — safe to cache
def research_products():
    """Return active product families with their current listing prices
    and 30-day ads gross profit for ordering.
    """
    try:
        sql = """
        SELECT
          dp.parent_name AS name,
          ROUND(AVG(lc.price), 2) AS price,
          COUNT(DISTINCT dp.asin) AS product_count,
          ROUND(COALESCE(SUM(fa.gross_profit), 0), 2) AS ads_profit,
          CAST(COALESCE(SUM(fa.ads_units), 0) AS INT64) AS ads_units,
          ROUND(SAFE_DIVIDE(COALESCE(SUM(fa.ads_clicks), 0), NULLIF(COALESCE(SUM(fa.ads_orders), 0), 0)), 1) AS ads_cps
        FROM `onyga-482313`.OI.V_DIM_LISTING_CURRENT lc
        JOIN `onyga-482313`.OI.DIM_PRODUCT dp
          ON lc.asin1 = dp.asin
        LEFT JOIN (
          SELECT advertised_asins, SUM(GROSS_PROFIT) AS gross_profit, SUM(Ads_units) AS ads_units, SUM(Ads_clicks) AS ads_clicks, SUM(Ads_orders) AS ads_orders
          FROM `onyga-482313`.OI.FACT_AMAZON_ADS
          WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
          GROUP BY advertised_asins
        ) fa ON dp.asin = fa.advertised_asins
        WHERE lc.price > 0
          AND dp.parent_name IS NOT NULL
          AND dp.is_active = true
        GROUP BY dp.parent_name
        ORDER BY COALESCE(SUM(fa.gross_profit), 0) DESC
        """
        results = client.query(sql).result()
        rows = [dict(row) for row in results]
        return jsonify(rows)
    except Exception as e:
        print(f"Error in research_products: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/research/family-info', methods=['GET'])
def research_family_info():
    """Return product family details: parent summary + individual child products
    with their Amazon product_type, price, and variant name.
    """
    family = request.args.get('family', '')
    if not family:
        return jsonify({'error': 'family parameter required'}), 400
    try:
        sql = """
        SELECT
          dp.parent_name,
          dp.asin,
          dp.product_short_name,
          dp.product_type,
          dp.color AS variant,
          ROUND(lc.price, 2) AS current_price,
          ROUND(COALESCE(ch.cost_of_goods, 0), 2) AS cogs,
          ROUND(COALESCE(ch.FBA_COST_estimated_referral_fee_per_unit, 0), 2) AS referral_fee,
          ROUND(COALESCE(ch.FBA_COST_estimated_fee_total, 0), 2) AS fba_fee,
          ROUND(COALESCE(ch.shipping_cost, 0), 2) AS shipping_cost,
          ROUND(COALESCE(ch.TOTAL_COST_PER_UNIT, 0), 2) AS total_cost_per_unit,
          ROUND(lc.price - COALESCE(ch.TOTAL_COST_PER_UNIT, 0), 2) AS gross_profit_per_unit,
          dp.seg_gender,
          dp.seg_age_group,
          dp.seg_occasion,
          dp.seg_product_type
        FROM `onyga-482313`.OI.DIM_PRODUCT dp
        LEFT JOIN (
          SELECT asin1, price
          FROM `onyga-482313`.OI.V_DIM_LISTING_CURRENT
          QUALIFY ROW_NUMBER() OVER (PARTITION BY asin1 ORDER BY price DESC) = 1
        ) lc ON lc.asin1 = dp.asin
        LEFT JOIN (
          SELECT asin, cost_of_goods, FBA_COST_estimated_referral_fee_per_unit, FBA_COST_estimated_fee_total, shipping_cost, TOTAL_COST_PER_UNIT
          FROM `onyga-482313`.OI.DIM_COSTS_HISTORY
          WHERE end_date IS NULL OR end_date >= CURRENT_DATE()
          QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
        ) ch ON ch.asin = dp.asin
        WHERE dp.parent_name = @family
          AND dp.is_active = true
        ORDER BY lc.price, dp.product_short_name
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("family", "STRING", family),
            ]
        )
        results = client.query(sql, job_config=job_config).result()
        products = [dict(row) for row in results]

        # Build parent summary
        product_types = list(set(p['product_type'] for p in products if p.get('product_type')))
        prices = [p['current_price'] for p in products if p.get('current_price')]

        # Merge segments across all products (union of all unique values)
        def merge_seg(col):
            vals = set()
            for p in products:
                v = p.get(col)
                if v:
                    for item in v.split(','):
                        item = item.strip()
                        if item:
                            vals.add(item)
            return ','.join(sorted(vals)) if vals else None

        segments = {
            'gender': merge_seg('seg_gender'),
            'age_group': merge_seg('seg_age_group'),
            'occasion': merge_seg('seg_occasion'),
            'product_type': merge_seg('seg_product_type'),
        }

        # Add per-product segments to each product
        for p in products:
            p['segments'] = {
                'gender': p.get('seg_gender'),
                'age_group': p.get('seg_age_group'),
                'occasion': p.get('seg_occasion'),
                'product_type': p.get('seg_product_type'),
            }

        gross_profits = [p['gross_profit_per_unit'] for p in products if p.get('gross_profit_per_unit') is not None]
        total_costs = [p['total_cost_per_unit'] for p in products if p.get('total_cost_per_unit') is not None]
        cogs_list = [p['cogs'] for p in products if p.get('cogs') is not None]
        referral_list = [p['referral_fee'] for p in products if p.get('referral_fee') is not None]
        fba_list = [p['fba_fee'] for p in products if p.get('fba_fee') is not None]
        shipping_list = [p['shipping_cost'] for p in products if p.get('shipping_cost') is not None]

        summary = {
            'parent_name': family,
            'product_count': len(products),
            'product_types': product_types,
            'min_price': min(prices) if prices else None,
            'max_price': max(prices) if prices else None,
            'avg_price': round(sum(prices) / len(prices), 2) if prices else None,
            'avg_cogs': round(sum(cogs_list) / len(cogs_list), 2) if cogs_list else None,
            'avg_referral_fee': round(sum(referral_list) / len(referral_list), 2) if referral_list else None,
            'avg_fba_fee': round(sum(fba_list) / len(fba_list), 2) if fba_list else None,
            'avg_shipping_cost': round(sum(shipping_list) / len(shipping_list), 2) if shipping_list else None,
            'avg_total_cost': round(sum(total_costs) / len(total_costs), 2) if total_costs else None,
            'gross_profit_per_unit': round(sum(gross_profits) / len(gross_profits), 2) if gross_profits else None,
            'segments': segments,
        }

        return jsonify({'summary': summary, 'products': products})
    except Exception as e:
        print(f"Error in research_family_info: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/research/product-segments', methods=['POST'])
def update_product_segments():
    """Manually update product segmentation.
    Body: { parent_name, asin?, seg_gender?, seg_age_group?, seg_occasion?, seg_product_type? }
    If asin is provided, update only that product. Otherwise update all products in parent.
    Values are comma-separated strings. Pass null to clear.
    """
    try:
        data = request.get_json()
        parent_name = data.get('parent_name')
        asin = data.get('asin')
        if not parent_name:
            return jsonify({'error': 'parent_name required'}), 400

        updates = []
        params = [bigquery.ScalarQueryParameter('parent', 'STRING', parent_name)]

        for col in ['seg_gender', 'seg_age_group', 'seg_occasion', 'seg_product_type']:
            if col in data:
                val = data[col] if data[col] else None
                updates.append(f'{col} = @{col}')
                params.append(bigquery.ScalarQueryParameter(col, 'STRING', val))

        if not updates:
            return jsonify({'error': 'No segment fields provided'}), 400

        where = "WHERE parent_name = @parent AND is_active = true"
        if asin:
            where += " AND asin = @asin"
            params.append(bigquery.ScalarQueryParameter('asin', 'STRING', asin))

        sql = f"""
        UPDATE `onyga-482313`.OI.DIM_PRODUCT
        SET {', '.join(updates)}, updated_at = CURRENT_TIMESTAMP()
        {where}
        """
        jc = bigquery.QueryJobConfig(query_parameters=params)
        job = client.query(sql, job_config=jc)
        job.result()
        clear_data_cache()
        return jsonify({'ok': True, 'updated': job.num_dml_affected_rows})
    except Exception as e:
        print(f"Error in update_product_segments: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/research/derive-segments', methods=['POST'])
def derive_product_segments():
    """Trigger SP_DERIVE_PRODUCT_SEGMENTS.
    Body: { parent_name?: string } — null/omit = derive for all products.
    Pass force: true to clear existing auto-derived segments first.
    """
    try:
        data = request.get_json() or {}
        parent_name = data.get('parent_name')
        force = data.get('force', False)

        # If force, clear existing segments first
        if force:
            clear_sql = """
            UPDATE `onyga-482313`.OI.DIM_PRODUCT
            SET seg_gender = NULL, seg_age_group = NULL,
                seg_occasion = NULL, seg_product_type = NULL
            WHERE is_active = true
            """
            if parent_name:
                clear_sql += " AND parent_name = @parent"
                jc = bigquery.QueryJobConfig(query_parameters=[
                    bigquery.ScalarQueryParameter('parent', 'STRING', parent_name)
                ])
                client.query(clear_sql, job_config=jc).result()
            else:
                client.query(clear_sql).result()

        # Call the procedure
        call_sql = "CALL `onyga-482313`.OI.SP_DERIVE_PRODUCT_SEGMENTS(@parent)"
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('parent', 'STRING', parent_name)
        ])
        client.query(call_sql, job_config=jc).result()
        clear_data_cache()
        return jsonify({'ok': True, 'parent_name': parent_name or 'ALL'})
    except Exception as e:
        print(f"Error in derive_product_segments: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/research/segment-reasoning', methods=['GET'])
def segment_reasoning():
    """Show the purchase data behind each auto-derived segment value.
    Returns breakdown of purchases per segment value per parent.
    """
    family = request.args.get('family', '')
    if not family:
        return jsonify({'error': 'family parameter required'}), 400
    try:
        sql = """
        WITH tagged AS (
          SELECT
            p.parent_name,
            p.asin,
            a.search_term,
            a.Ads_orders,
            a.Ads_clicks,
            -- Single-source taxonomy (FN_EXTRACT_SEGMENTS) + canonical
            -- product_type vocabulary (DE_PRODUCT_TYPE_KEYWORDS)
            `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(a.search_term).gender    AS gender,
            `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(a.search_term).age_group AS age_group,
            `onyga-482313`.OI.FN_EXTRACT_SEGMENTS(a.search_term).occasion  AS occasion,
            ptl.product_type
          FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
          JOIN `onyga-482313`.OI.DIM_PRODUCT p
            ON COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME) = p.asin
          LEFT JOIN (
            SELECT
              t.search_term,
              ARRAY_AGG(ptk.product_type ORDER BY ptk.priority ASC, LENGTH(ptk.keyword) DESC LIMIT 1)[OFFSET(0)] AS product_type
            FROM (
              -- only THIS family's ad search terms (not the whole account) —
              -- the unbounded cross join blew BigQuery's per-statement CPU guard
              SELECT DISTINCT a2.search_term
              FROM `onyga-482313`.OI.FACT_AMAZON_ADS a2
              JOIN `onyga-482313`.OI.DIM_PRODUCT p2
                ON COALESCE(a2.most_advertised_asin_impressions, a2.ASIN_BY_CAMPAIGN_NAME) = p2.asin
              WHERE a2.Ads_clicks > 0 AND p2.parent_name = @family AND p2.is_active = true
            ) t
            CROSS JOIN `onyga-482313.OI.DE_PRODUCT_TYPE_KEYWORDS` ptk
            WHERE REGEXP_CONTAINS(LOWER(t.search_term), CONCAT(r'(?:^|\\W)', ptk.keyword, r'(?:\\W|$)'))
            GROUP BY t.search_term
          ) ptl ON ptl.search_term = a.search_term
          WHERE a.Ads_clicks > 0
            AND p.parent_name = @family
            AND p.is_active = true
        ),
        totals AS (
          SELECT SUM(Ads_orders) AS total_orders FROM tagged
        ),
        asin_totals AS (
          SELECT asin, SUM(Ads_orders) AS total_orders FROM tagged GROUP BY asin
        )
        -- Parent-level aggregation
        SELECT
          '_PARENT' AS asin,
          'gender' AS segment_type, gender AS segment_value,
          SUM(Ads_orders) AS orders,
          ROUND(SAFE_DIVIDE(SUM(Ads_orders), MAX(t.total_orders)) * 100, 1) AS pct,
          ROUND(SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_orders)), 1) AS clicks_per_sale
        FROM tagged, totals t WHERE gender IS NOT NULL GROUP BY gender
        UNION ALL
        SELECT '_PARENT', 'age_group', age_group, SUM(Ads_orders),
          ROUND(SAFE_DIVIDE(SUM(Ads_orders), MAX(t.total_orders)) * 100, 1),
          ROUND(SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_orders)), 1)
        FROM tagged, totals t WHERE age_group IS NOT NULL GROUP BY age_group
        UNION ALL
        SELECT '_PARENT', 'occasion', occasion, SUM(Ads_orders),
          ROUND(SAFE_DIVIDE(SUM(Ads_orders), MAX(t.total_orders)) * 100, 1),
          ROUND(SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_orders)), 1)
        FROM tagged, totals t WHERE occasion IS NOT NULL GROUP BY occasion
        UNION ALL
        SELECT '_PARENT', 'product_type', product_type, SUM(Ads_orders),
          ROUND(SAFE_DIVIDE(SUM(Ads_orders), MAX(t.total_orders)) * 100, 1),
          ROUND(SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_orders)), 1)
        FROM tagged, totals t WHERE product_type IS NOT NULL GROUP BY product_type
        UNION ALL
        -- Per-ASIN aggregation
        SELECT tagged.asin, 'gender', gender, SUM(Ads_orders),
          ROUND(SAFE_DIVIDE(SUM(Ads_orders), MAX(atot.total_orders)) * 100, 1),
          ROUND(SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_orders)), 1)
        FROM tagged JOIN asin_totals atot ON tagged.asin = atot.asin WHERE gender IS NOT NULL GROUP BY tagged.asin, gender
        UNION ALL
        SELECT tagged.asin, 'age_group', age_group, SUM(Ads_orders),
          ROUND(SAFE_DIVIDE(SUM(Ads_orders), MAX(atot.total_orders)) * 100, 1),
          ROUND(SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_orders)), 1)
        FROM tagged JOIN asin_totals atot ON tagged.asin = atot.asin WHERE age_group IS NOT NULL GROUP BY tagged.asin, age_group
        UNION ALL
        SELECT tagged.asin, 'occasion', occasion, SUM(Ads_orders),
          ROUND(SAFE_DIVIDE(SUM(Ads_orders), MAX(atot.total_orders)) * 100, 1),
          ROUND(SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_orders)), 1)
        FROM tagged JOIN asin_totals atot ON tagged.asin = atot.asin WHERE occasion IS NOT NULL GROUP BY tagged.asin, occasion
        UNION ALL
        SELECT tagged.asin, 'product_type', product_type, SUM(Ads_orders),
          ROUND(SAFE_DIVIDE(SUM(Ads_orders), MAX(atot.total_orders)) * 100, 1),
          ROUND(SAFE_DIVIDE(SUM(Ads_clicks), SUM(Ads_orders)), 1)
        FROM tagged JOIN asin_totals atot ON tagged.asin = atot.asin WHERE product_type IS NOT NULL GROUP BY tagged.asin, product_type
        ORDER BY asin, segment_type, orders DESC
        """
        jc = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter('family', 'STRING', family)
        ])
        results = client.query(sql, job_config=jc).result()
        rows = [dict(row) for row in results]

        # Group by segment_type (parent-level) and by_asin
        grouped = {}
        by_asin = {}
        for row in rows:
            st = row['segment_type']
            asin = row['asin']
            entry = {
                'value': row['segment_value'],
                'orders': row['orders'],
                'pct': row['pct'],
                'clicks_per_sale': row.get('clicks_per_sale'),
            }
            if asin == '_PARENT':
                if st not in grouped:
                    grouped[st] = []
                grouped[st].append(entry)
            else:
                if asin not in by_asin:
                    by_asin[asin] = {}
                if st not in by_asin[asin]:
                    by_asin[asin][st] = []
                by_asin[asin][st].append(entry)

        grouped['by_asin'] = by_asin
        return jsonify(grouped)
    except Exception as e:
        print(f"Error in segment_reasoning: {e}")
        return jsonify({'error': str(e)}), 500

# ==========================================
# Shipment JSON API twins (Phase 2 Task 2)
# ==========================================

@app.route('/api/shipment/<shipment_id>', methods=['DELETE'])
def api_shipment_delete(shipment_id):
    try:
        errors = delete_shipment_record(shipment_id)
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/shipment/<shipment_id>/lines', methods=['POST'])
def api_shipment_line_add(shipment_id):
    try:
        errors, line_id = add_shipment_line(shipment_id, request.get_json() or {})
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True, 'line_id': line_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/shipment/<shipment_id>/lines/<line_id>', methods=['PUT'])
def api_shipment_line_update(shipment_id, line_id):
    d = request.get_json() or {}
    try:
        errors = update_shipment_line_fields(shipment_id, line_id, d.get('quantity_shipped'), d.get('allocated_cost'))
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/shipment/<shipment_id>/lines/<line_id>', methods=['DELETE'])
def api_shipment_line_delete(shipment_id, line_id):
    try:
        errors = delete_shipment_line_record(shipment_id, line_id)
        if errors:
            return jsonify({'success': False, 'error': '; '.join(str(x) for x in errors) if isinstance(errors, list) else str(errors)}), 400
        clear_data_cache()
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    print(f"Starting OI Data Entry Forms application...")
    print(f"Server will be available at: http://localhost:{port}")
    print(f"Press Ctrl+C to stop the server")
    app.run(host='0.0.0.0', port=port, debug=True)



