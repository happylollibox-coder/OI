#!/bin/bash

# Setup Daily Currency Rate Updates
# This script configures automated daily updates for currency exchange rates

echo "🔄 Setting up automated daily currency rate updates..."
echo "======================================================"

PROJECT_DIR="/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI"
SCRIPT_PATH="$PROJECT_DIR/scripts/update_exchange_rates.py"
LOG_FILE="$PROJECT_DIR/logs/currency_updates.log"
VENV_PATH="$PROJECT_DIR/venv"

# Create logs directory
mkdir -p "$PROJECT_DIR/logs"

echo "📁 Created logs directory: $PROJECT_DIR/logs"

# Create a wrapper script for the cron job
cat > "$PROJECT_DIR/update_rates_cron.sh" << 'EOF'
#!/bin/bash
# Cron job wrapper for currency rate updates
PROJECT_DIR="/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI"
LOG_FILE="$PROJECT_DIR/logs/currency_updates.log"
SCRIPT_PATH="$PROJECT_DIR/scripts/update_exchange_rates.py"

# Log the start of the job
echo "$(date): Starting currency rate update" >> "$LOG_FILE"

# Run the Python script with error handling
cd "$PROJECT_DIR"
/usr/local/bin/python3 "$SCRIPT_PATH" --project onyga-482313 >> "$LOG_FILE" 2>&1

# Log completion
echo "$(date): Currency rate update completed" >> "$LOG_FILE"
echo "----------------------------------------" >> "$LOG_FILE"
EOF

chmod +x "$PROJECT_DIR/update_rates_cron.sh"
echo "📝 Created cron wrapper script: $PROJECT_DIR/update_rates_cron.sh"

# Setup cron job
CRON_JOB="0 6 * * 1-5 $PROJECT_DIR/update_rates_cron.sh"
echo "⏰ Setting up cron job to run weekdays at 6:00 AM"

# Add to crontab (only weekdays, Monday-Friday)
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "✅ Cron job configured successfully!"
echo ""
echo "📋 Cron job details:"
echo "   - Runs: Weekdays (Monday-Friday) at 6:00 AM"
echo "   - Script: $PROJECT_DIR/update_rates_cron.sh"
echo "   - Logs: $LOG_FILE"
echo ""
echo "🔍 To verify the cron job:"
echo "   crontab -l"
echo ""
echo "📊 To check recent logs:"
echo "   tail -20 $LOG_FILE"
echo ""
echo "🧪 To test the setup manually:"
echo "   $PROJECT_DIR/update_rates_cron.sh"
echo ""
echo "⚠️  Note: Make sure you have authenticated with Google Cloud:"
echo "   gcloud auth application-default login"
echo ""
echo "🎉 Automated daily updates are now configured!"