"""Builds Google Ads API credentials from environment variables.

Kept free of google-ads imports so it is unit-testable in isolation. The actual
GoogleAdsClient is constructed lazily in get_client() only when the server runs.
"""

import os

REQUIRED_ENV = [
    "GOOGLE_ADS_DEVELOPER_TOKEN",
    "GOOGLE_ADS_CLIENT_ID",
    "GOOGLE_ADS_CLIENT_SECRET",
    "GOOGLE_ADS_REFRESH_TOKEN",
    "GOOGLE_ADS_LOGIN_CUSTOMER_ID",
    "GOOGLE_ADS_CUSTOMER_ID",
]


def _digits(value: str) -> str:
    return "".join(c for c in value if c.isdigit())


def build_credentials(env: dict | None = None) -> dict:
    """Return a dict for GoogleAdsClient.load_from_dict, or raise ValueError."""
    env = env if env is not None else os.environ
    missing = [k for k in REQUIRED_ENV if not env.get(k)]
    if missing:
        raise ValueError(
            "Missing Google Ads env var(s): " + ", ".join(missing)
            + " — set them in OI/.env."
        )
    return {
        "developer_token": env["GOOGLE_ADS_DEVELOPER_TOKEN"],
        "client_id": env["GOOGLE_ADS_CLIENT_ID"],
        "client_secret": env["GOOGLE_ADS_CLIENT_SECRET"],
        "refresh_token": env["GOOGLE_ADS_REFRESH_TOKEN"],
        "login_customer_id": _digits(env["GOOGLE_ADS_LOGIN_CUSTOMER_ID"]),
        "use_proto_plus": True,
    }


def customer_id(env: dict | None = None) -> str:
    """The target account id, digits only."""
    env = env if env is not None else os.environ
    if not env.get("GOOGLE_ADS_CUSTOMER_ID"):
        raise ValueError("Missing GOOGLE_ADS_CUSTOMER_ID — set it in OI/.env.")
    return _digits(env["GOOGLE_ADS_CUSTOMER_ID"])


def get_client(env: dict | None = None):
    """Construct a live GoogleAdsClient (imports google-ads lazily)."""
    from google.ads.googleads.client import GoogleAdsClient
    return GoogleAdsClient.load_from_dict(build_credentials(env))
