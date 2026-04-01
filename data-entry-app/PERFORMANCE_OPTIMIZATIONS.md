# Performance Optimization Guide

This document outlines performance optimizations implemented and recommended for the Flask application.

## Implemented Optimizations

### 1. Query Result Caching
- Products list cached for 5 minutes (rarely changes)
- Dashboard stats cached for 2 minutes
- Reduces BigQuery API calls significantly

### 2. Query Optimization
- Combined multiple queries where possible
- Used efficient JOINs and CTEs
- Added explicit schema to batch loads to avoid inference overhead

### 3. Connection Pooling
- BigQuery client is reused (singleton pattern)
- No connection overhead per request

## Additional Recommendations

### 1. Add Pagination
For large datasets, implement pagination on the home page:
- Limit to 50-100 orders per page
- Add "Load More" or page numbers
- Reduces initial query time

### 2. Lazy Loading
- Load payment/shipment details only when PO details page is opened
- Use AJAX to load data incrementally

### 3. Database Indexes
Ensure BigQuery tables have proper clustering:
- `DE_PURCHASE_ORDERS` is clustered by `manufacturer_name` ✓
- `DE_MANUFACTURER_SHIPMENTS` is clustered by `shipment_status` ✓
- Consider adding indexes on frequently queried fields

### 4. Frontend Optimizations
- Minify CSS/JS files
- Enable browser caching for static assets
- Use CDN for Bootstrap/icons if possible

### 5. Background Jobs
For heavy operations:
- Use Cloud Functions or Cloud Tasks for bulk imports
- Process Excel uploads asynchronously

### 6. Query Result Streaming
For very large result sets:
- Use `to_dataframe()` for better performance
- Stream results instead of loading all at once

## Performance Monitoring

Monitor these metrics:
- Average query execution time
- Cache hit rate
- Page load times
- BigQuery slot usage

## Current Performance Targets

- Home page: < 2 seconds
- PO details page: < 1 second
- Dashboard: < 3 seconds
- Form submissions: < 1 second
