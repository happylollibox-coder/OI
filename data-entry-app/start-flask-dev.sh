#!/bin/zsh
# Start the OI Flask data-entry app for LOCAL DEV. Idempotent.
#
# Managed by the launchd agent ~/Library/LaunchAgents/com.oi.flask-dataentry.plist
# (RunAtLoad so it comes up at every login/boot). Root cause it fixes: Vite and
# Cube get restarted after reboots but Flask was forgotten, so the dashboard's
# Research/Admin pages (fully backed by Flask /api/*) silently rendered empty.
#
# The exact start command is load-bearing and must not drift:
#   PORT=5050            -> Vite's /api proxy targets http://localhost:5050
#                           (dashboard-react/vite.config.ts).
#   env -u CUBEJS_API_SECRET
#                       -> Flask must NOT see this var locally so it falls back
#                          to the dev secret 'dev-secret-key-123' that the
#                          dashboard's LOCAL_DEV_TOKEN is signed with.
#                          See architecture/API_AUTH.md.
set -u

APP_DIR="/Users/ori/Develop/OI/data-entry-app"
cd "$APP_DIR" || { echo "$(date '+%F %T') [start-flask-dev] cannot cd to $APP_DIR"; exit 1; }

ts() { date '+%F %T'; }

# Idempotency: never double-bind 5050. If Flask (or anything) is already
# listening there — e.g. started by hand — leave it alone and exit cleanly.
if /usr/sbin/lsof -nP -iTCP:5050 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "$(ts) [start-flask-dev] port 5050 already in use; not starting a second instance"
  exit 0
fi

echo "$(ts) [start-flask-dev] starting Flask data-entry on :5050 (CUBEJS_API_SECRET unset -> dev secret)"
# exec so this script's PID becomes Flask's PID and launchd tracks/keeps-alive Flask itself.
exec env -u CUBEJS_API_SECRET PORT=5050 venv/bin/python app.py
