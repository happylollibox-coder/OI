"""Re-run OAuth consent and write the fresh refresh token straight into OI/.env
(prints no secret). Opens a browser; complete the Allow prompt with the Google
account that has access to the Happy Lolli Ads account."""
import os, re, sys
from pathlib import Path
from dotenv import load_dotenv
ENV = Path("/Users/ori/Develop/OI/.env")
load_dotenv(ENV)
from google_auth_oauthlib.flow import InstalledAppFlow
cid=os.environ["GOOGLE_ADS_CLIENT_ID"]; sec=os.environ["GOOGLE_ADS_CLIENT_SECRET"]
cfg={"installed":{"client_id":cid,"client_secret":sec,
  "auth_uri":"https://accounts.google.com/o/oauth2/auth",
  "token_uri":"https://oauth2.googleapis.com/token",
  "redirect_uris":["http://localhost"]}}
flow=InstalledAppFlow.from_client_config(cfg, scopes=["https://www.googleapis.com/auth/adwords"])
print(">>> A browser window is opening — click Allow with the Happy Lolli Google account…", flush=True)
creds=flow.run_local_server(port=0, access_type="offline", prompt="consent")
tok=creds.refresh_token
if not tok: sys.exit("No refresh token returned; revoke at myaccount.google.com/permissions and retry.")
txt=ENV.read_text()
if re.search(r"(?m)^GOOGLE_ADS_REFRESH_TOKEN=.*$", txt):
    txt=re.sub(r"(?m)^GOOGLE_ADS_REFRESH_TOKEN=.*$", f"GOOGLE_ADS_REFRESH_TOKEN={tok}", txt)
else:
    txt=txt.rstrip()+f"\nGOOGLE_ADS_REFRESH_TOKEN={tok}\n"
ENV.write_text(txt)
print(">>> SUCCESS: OI/.env updated with a fresh refresh token.", flush=True)
