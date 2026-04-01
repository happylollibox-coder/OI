#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# OI — Deploy All Services to Google Cloud Run
# ═══════════════════════════════════════════════════════════════
# Usage:
#   ./deployment/deploy_all.sh           → deploy everything
#   ./deployment/deploy_all.sh cube      → deploy Cube API only
#   ./deployment/deploy_all.sh dashboard → deploy React Dashboard only
#   ./deployment/deploy_all.sh flask     → deploy Flask Data Entry only
#   ./deployment/deploy_all.sh bigquery  → deploy all BigQuery views
# ═══════════════════════════════════════════════════════════════

set -e

PROJECT_ID="onyga-482313"
REGION="us-central1"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="${1:-all}"

# ─── Colors ───────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${BLUE}▸${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; }

# ─── BigQuery Views ──────────────────────────────────────────
deploy_bigquery() {
  log "Deploying BigQuery views..."
  
  local deployed=0
  local failed=0
  
  # ── Layer 1: Interface views (V_SRC_*) — no internal dependencies ──
  log "  Deploying interface views (V_SRC_*)..."
  for file in "$BASE_DIR"/scripts/bigquery/interface_views/V_SRC_*.sql; do
    [ -f "$file" ] || continue
    local view=$(basename "$file" .sql)
    if bq query --use_legacy_sql=false --project_id=$PROJECT_ID < "$file" 2>/dev/null; then
      ok "    $view"
      deployed=$((deployed + 1))
    else
      err "    $view — FAILED"
      failed=$((failed + 1))
    fi
  done
  
  # ── Layer 2: Foundation views (no dependencies on other V_ views) ──
  log "  Deploying foundation views..."
  local foundation_views=(
    "V_PRODUCT_FAMILY_MAP"
    "V_FACT_AMAZON_PERFORMANCE_DAILY"
    "V_UNIFIED_DAILY"
    "V_SUMMARY_7D"
    "V_SEASONAL_INDEX_WEEKLY"
    "V_TRAFFIC_MULTIPLIER_WEEKLY"
    "V_PO_SNAPSHOT"
    "V_SNAPSHOT_REMAINING_COSTS"
    "V_SNAPSHOT_REMAINING_COSTS_SUMMARY"
    "V_BRAND_KEYWORD_CLASSIFICATION"
    "V_BRAND_STRENGTH_WEEKLY"
    "V_PARENT_HERO_ASIN"
    "V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY"
    "V_ASIN_BEST_PRACTICES"
  )
  
  for view in "${foundation_views[@]}"; do
    local file="$BASE_DIR/scripts/bigquery/views/${view}.sql"
    if [ -f "$file" ]; then
      if bq query --use_legacy_sql=false --project_id=$PROJECT_ID < "$file" 2>/dev/null; then
        ok "    $view"
        deployed=$((deployed + 1))
      else
        err "    $view — FAILED"
        failed=$((failed + 1))
      fi
    fi
  done
  
  # ── Layer 3: Experiment views (depend on DIM_EXPERIMENT, FACT tables) ──
  log "  Deploying experiment views..."
  for file in "$BASE_DIR"/scripts/bigquery/views/V_EXPERIMENT_*.sql; do
    [ -f "$file" ] || continue
    local view=$(basename "$file" .sql)
    if bq query --use_legacy_sql=false --project_id=$PROJECT_ID < "$file" 2>/dev/null; then
      ok "    $view"
      deployed=$((deployed + 1))
    else
      err "    $view — FAILED"
      failed=$((failed + 1))
    fi
  done
  
  # ── Layer 4: Coach/Ads views (depend on FACT_AMAZON_ADS + experiments) ──
  log "  Deploying coach & ads views..."
  local coach_views=(
    "V_ADS_COACH_DATA"
    "V_ADS_COACH_SEARCH_TERM"
    "V_ADS_COACH_CAMPAIGN"
    "V_ADS_COACH_DECISION"
    "V_ADS_COACH"
    "V_ADS_COACH_PHRASE_NEGATIVES"
    "V_COACH_HOT_SIGNALS"
    "V_SEARCH_TERM_SEGMENT"
    "V_SEARCH_TERM_OPPORTUNITIES"
    "V_KEYWORD_STRATEGY_PREDICTIONS"
    "V_CAMPAIGN_PLACEMENT_REPORT"
    "V_CAMPAIGN_PLACEMENT_BIDDING"
    "V_PROMOTION_RAMP_ANALYSIS"
    "V_STRATEGY_CURRENT_RECOMMENDATIONS"
  )
  
  for view in "${coach_views[@]}"; do
    local file="$BASE_DIR/scripts/bigquery/views/${view}.sql"
    if [ -f "$file" ]; then
      if bq query --use_legacy_sql=false --project_id=$PROJECT_ID < "$file" 2>/dev/null; then
        ok "    $view"
        deployed=$((deployed + 1))
      else
        err "    $view — FAILED"
        failed=$((failed + 1))
      fi
    fi
  done
  
  # ── Layer 5: Catch-all — deploy any remaining .sql files not yet deployed ──
  log "  Deploying remaining views..."
  for file in "$BASE_DIR"/scripts/bigquery/views/*.sql; do
    [ -f "$file" ] || continue
    local view=$(basename "$file" .sql)
    # Skip if already deployed in previous layers
    local already_done=false
    for prev in "${foundation_views[@]}" "${coach_views[@]}"; do
      if [ "$view" = "$prev" ]; then
        already_done=true
        break
      fi
    done
    [[ "$view" == V_EXPERIMENT_* ]] && already_done=true
    [ "$already_done" = true ] && continue
    
    if bq query --use_legacy_sql=false --project_id=$PROJECT_ID < "$file" 2>/dev/null; then
      ok "    $view"
      deployed=$((deployed + 1))
    else
      err "    $view — FAILED"
      failed=$((failed + 1))
    fi
  done
  
  echo ""
  ok "BigQuery views deployed: $deployed succeeded, $failed failed"
}

# ─── Cube API ────────────────────────────────────────────────
deploy_cube() {
  log "Deploying Cube API to Cloud Run (${REGION})..."
  cd "$BASE_DIR/cube"
  
  gcloud run deploy cube-api \
    --source . \
    --project=$PROJECT_ID \
    --region=$REGION \
    --allow-unauthenticated \
    --memory=2Gi \
    --cpu=2 \
    --timeout=300 \
    --concurrency=40 \
    --max-instances=3 \
    --quiet
  
  CUBE_URL=$(gcloud run services describe cube-api --region=$REGION --project=$PROJECT_ID --format='value(status.url)')
  ok "Cube API deployed: $CUBE_URL"
}

# ─── React Dashboard ────────────────────────────────────────
deploy_dashboard() {
  log "Deploying Dashboard to Cloud Run (${REGION})..."
  cd "$BASE_DIR/dashboard-react"
  
  gcloud run deploy oi-dashboard \
    --source . \
    --project=$PROJECT_ID \
    --region=$REGION \
    --allow-unauthenticated \
    --clear-base-image \
    --set-build-env-vars VITE_CUBE_API_URL="https://cube-api-405291422506.us-central1.run.app" \
    --memory=256Mi \
    --cpu=1 \
    --timeout=60 \
    --quiet
  
  DASH_URL=$(gcloud run services describe oi-dashboard --region=$REGION --project=$PROJECT_ID --format='value(status.url)')
  ok "Dashboard deployed: $DASH_URL"
}

# ─── Flask Data Entry ───────────────────────────────────────
deploy_flask() {
  log "Deploying Flask Data Entry to Cloud Run (${REGION})..."
  cd "$BASE_DIR/data-entry-app"
  
  gcloud run deploy data-entry-forms \
    --source . \
    --project=$PROJECT_ID \
    --platform managed \
    --region=$REGION \
    --allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID,BIGQUERY_DATASET=OI" \
    --memory=512Mi \
    --cpu=1 \
    --timeout=300 \
    --quiet
  
  FLASK_URL=$(gcloud run services describe data-entry-forms --region=$REGION --project=$PROJECT_ID --format='value(status.url)')
  ok "Flask Data Entry deployed: $FLASK_URL"
}

# ─── Main ────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  OI — Cloud Deployment (target: $TARGET)"
echo "═══════════════════════════════════════════"
echo ""

case "$TARGET" in
  bigquery)  deploy_bigquery ;;
  cube)      deploy_cube ;;
  dashboard) deploy_dashboard ;;
  flask)     deploy_flask ;;
  all)
    deploy_bigquery
    deploy_cube
    deploy_dashboard
    deploy_flask
    ;;
  *)
    err "Unknown target: $TARGET"
    echo "Usage: $0 [all|bigquery|cube|dashboard|flask]"
    exit 1
    ;;
esac

echo ""
echo "═══════════════════════════════════════════"
ok "Deployment complete!"
echo "═══════════════════════════════════════════"
echo ""
