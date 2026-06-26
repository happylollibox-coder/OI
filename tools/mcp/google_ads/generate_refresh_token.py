"""One-time helper: generate a Google Ads API refresh token (OAuth desktop flow).

Run this AFTER you have an OAuth2 Desktop client (Phase B). It opens a browser,
you click "Allow" with the Google account that has access to the Happy Lolli Ads
account, and it prints the GOOGLE_ADS_REFRESH_TOKEN line to paste into OI/.env.

Usage (from repo root /Users/ori/Develop/OI):

  GOOGLE_ADS_CLIENT_ID=xxx GOOGLE_ADS_CLIENT_SECRET=yyy \
    .venv/bin/python tools/mcp/google_ads/generate_refresh_token.py

Or, if those two are already in OI/.env, just:

  .venv/bin/python tools/mcp/google_ads/generate_refresh_token.py

Requires: google-auth-oauthlib (installed in .venv).
"""

import os
import sys
from pathlib import Path

from google_auth_oauthlib.flow import InstalledAppFlow

# Read-only + read/write Ads scope. The audit MCP only reads, but this is the
# single scope Google issues for the Ads API; the developer token / app code
# enforce read-only, not the OAuth scope.
SCOPES = ["https://www.googleapis.com/auth/adwords"]


def _load_env_file() -> None:
    """Best-effort load of OI/.env so CLIENT_ID/SECRET can live there."""
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv(Path(__file__).resolve().parents[2] / ".env")


def main() -> None:
    _load_env_file()
    client_id = os.environ.get("GOOGLE_ADS_CLIENT_ID")
    client_secret = os.environ.get("GOOGLE_ADS_CLIENT_SECRET")
    if not client_id or not client_secret:
        sys.exit(
            "Missing GOOGLE_ADS_CLIENT_ID / GOOGLE_ADS_CLIENT_SECRET.\n"
            "Set them as env vars or add them to OI/.env, then re-run."
        )

    client_config = {
        "installed": {
            "client_id": client_id,
            "client_secret": client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": ["http://localhost"],
        }
    }

    flow = InstalledAppFlow.from_client_config(client_config, scopes=SCOPES)
    # access_type=offline + prompt=consent guarantees Google returns a refresh_token.
    creds = flow.run_local_server(
        port=0, access_type="offline", prompt="consent"
    )

    if not creds.refresh_token:
        sys.exit(
            "No refresh token returned. Re-run; if it persists, revoke the app's "
            "access at https://myaccount.google.com/permissions and try again "
            "(prompt=consent forces a fresh grant)."
        )

    print("\n=== SUCCESS — add this line to OI/.env ===")
    print(f"GOOGLE_ADS_REFRESH_TOKEN={creds.refresh_token}")
    print("==========================================")


if __name__ == "__main__":
    main()
