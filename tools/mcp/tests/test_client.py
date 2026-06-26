import pytest

from tools.mcp.google_ads.client import build_credentials, REQUIRED_ENV

ENV = {
    "GOOGLE_ADS_DEVELOPER_TOKEN": "devtok",
    "GOOGLE_ADS_CLIENT_ID": "cid",
    "GOOGLE_ADS_CLIENT_SECRET": "secret",
    "GOOGLE_ADS_REFRESH_TOKEN": "refresh",
    "GOOGLE_ADS_LOGIN_CUSTOMER_ID": "111-222-3333",
    "GOOGLE_ADS_CUSTOMER_ID": "444-555-6666",
}


def test_build_credentials_returns_client_dict():
    creds = build_credentials(ENV)
    assert creds["developer_token"] == "devtok"
    assert creds["client_id"] == "cid"
    assert creds["use_proto_plus"] is True
    assert creds["login_customer_id"] == "1112223333"


def test_build_credentials_missing_var_names_the_key():
    broken = dict(ENV)
    del broken["GOOGLE_ADS_REFRESH_TOKEN"]
    with pytest.raises(ValueError) as exc:
        build_credentials(broken)
    assert "GOOGLE_ADS_REFRESH_TOKEN" in str(exc.value)


def test_required_env_lists_all_six():
    assert len(REQUIRED_ENV) == 6
