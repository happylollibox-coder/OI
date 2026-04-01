# OI Database Project Makefile

.PHONY: help deploy validate rollback clean test

# Default target
help:
	@echo "OI Database Project - Available commands:"
	@echo ""
	@echo "Deployment:"
	@echo "  deploy     - Deploy all views to BigQuery"
	@echo "  validate   - Validate deployment"
	@echo "  validate-integrity - Run data integrity validation (bridge, Ads_key, duplicates)"
	@echo "  rollback   - Rollback deployment (WARNING: destructive)"
	@echo ""
	@echo "Development:"
	@echo "  test       - Run tests (if any)"
	@echo "  clean      - Clean temporary files"
	@echo ""
	@echo "Documentation:"
	@echo "  docs       - Show documentation files"
	@echo ""

# Deployment commands
deploy:
	@echo "Deploying to BigQuery..."
	@chmod +x deployment/deploy.sh
	@./deployment/deploy.sh

validate:
	@echo "Validating deployment..."
	@chmod +x deployment/validate.sh
	@./deployment/validate.sh

validate-integrity:
	@echo "Running data integrity validation..."
	@bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/validation/VALIDATE_DATA_INTEGRITY.sql

rollback:
	@echo "WARNING: This will drop all views!"
	@chmod +x deployment/rollback.sh
	@./deployment/rollback.sh

# Development commands
test:
	@echo "Running tests..."
	@echo "No automated tests configured yet."

clean:
	@echo "Cleaning temporary files..."
	@find . -name "*.tmp" -delete
	@find . -name "*.log" -delete
	@find . -name "*.bak" -delete

# Documentation
docs:
	@echo "Documentation files:"
	@echo "  README.md          - Main project documentation"
	@echo "  SCHEMA.md          - Database schema documentation"
	@echo "  config.yaml        - Project configuration"
	@echo "  deployment/README.md - Deployment documentation"
	@echo ""
	@echo "View documentation:"
	@head -10 README.md

# Quick status check
status:
	@echo "Project Status:"
	@echo "==============="
	@echo "BigQuery Project: onyga-482313"
	@echo "Dataset: OI"
	@echo ""
	@echo "Interface Views:"
	@ls -1 scripts/Interface\ Views/*.sql | wc -l | xargs echo "  Total views:"
	@echo ""
	@echo "Check BigQuery status:"
	@echo "  bq ls --project_id=onyga-482313 OI"
