# Google Ads PMax Audit MCP (Phase 1, read-only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a read-only MCP server that audits Happy Lolli's Google Ads Performance Max campaigns against a configuration checklist and returns structured findings.

**Architecture:** A Python `FastMCP` server (`tools/mcp/google_ads_server.py`) in the same style as `tools/mcp/oi_coach_server.py`. Logic is split into three importable modules: `audit_rules.py` (pure functions, the TDD core, no external deps), `queries.py` (GAQL string builders, pure), and `client.py` (builds Google Ads credentials from env). The server wires them together. There is **no `mutate` call anywhere** in Phase 1.

**Tech Stack:** Python 3.12 (project `.venv`), `pytest` 9.1.1 (already installed), `google-ads` (Google Ads API client — to be installed), `mcp` (FastMCP), `python-dotenv` (already installed).

**Spec:** `docs/superpowers/specs/2026-06-26-google-ads-pmax-audit-mcp-design.md`

**Scope note:** This plan covers **Phase 1 only** (read-only audit). Phase 2 (the gated update/write layer) is a separate future plan and is intentionally excluded.

---

## File Structure

- Create: `tools/mcp/google_ads/__init__.py` — package marker.
- Create: `tools/mcp/google_ads/audit_rules.py` — pure rule functions + `Finding` model. No `google-ads`/`mcp` imports (so tests run on bare pytest).
- Create: `tools/mcp/google_ads/queries.py` — GAQL query-string builders (pure).
- Create: `tools/mcp/google_ads/client.py` — `build_credentials()` reads env → dict for `GoogleAdsClient.load_from_dict`.
- Create: `tools/mcp/google_ads_server.py` — FastMCP server exposing the 5 read tools.
- Create: `tools/mcp/requirements.txt` — `google-ads`, `mcp`, `python-dotenv`.
- Create: `tools/mcp/tests/__init__.py` — test package marker.
- Create: `tools/mcp/tests/test_audit_rules.py` — unit tests for the rules.
- Create: `tools/mcp/tests/test_queries.py` — unit tests for the GAQL builders.
- Create: `tools/mcp/tests/test_client.py` — unit tests for env handling.
- Create: `tools/mcp/tests/fixtures/asset_group_good.json`, `asset_group_thin.json` — sample configs.

All commands assume CWD `/Users/ori/Develop/OI` and use `.venv/bin/python` / `.venv/bin/pytest`.

---

### Task 1: Dependencies and package skeleton

**Files:**
- Create: `tools/mcp/requirements.txt`
- Create: `tools/mcp/google_ads/__init__.py`
- Create: `tools/mcp/tests/__init__.py`

- [ ] **Step 1: Create the requirements file**

`tools/mcp/requirements.txt`:
```
google-ads>=25.0.0
mcp>=1.2.0
python-dotenv>=1.0.0
```

- [ ] **Step 2: Install into the project venv**

Run: `.venv/bin/python -m pip install -r tools/mcp/requirements.txt`
Expected: ends with `Successfully installed ... google-ads-... mcp-...` (python-dotenv already present is fine).

- [ ] **Step 3: Verify the key imports resolve**

Run: `.venv/bin/python -c "import google.ads.googleads.client as c; from mcp.server.fastmcp import FastMCP; print('ok')"`
Expected: prints `ok` with no traceback.

- [ ] **Step 4: Create empty package markers**

`tools/mcp/google_ads/__init__.py`:
```python
"""Google Ads PMax audit MCP (Phase 1, read-only)."""
```

`tools/mcp/tests/__init__.py`:
```python
```

- [ ] **Step 5: Commit**

```bash
git add tools/mcp/requirements.txt tools/mcp/google_ads/__init__.py tools/mcp/tests/__init__.py
git commit -m "feat(google-ads): add deps and package skeleton for PMax audit MCP"
```

---

### Task 2: Finding model and text-coverage rule

**Files:**
- Create: `tools/mcp/google_ads/audit_rules.py`
- Create: `tools/mcp/tests/test_audit_rules.py`

The asset-group config dict shape used throughout:
```python
{
    "name": "Gift Boxes",
    "ad_strength": "GOOD",                  # POOR|AVERAGE|GOOD|EXCELLENT|PENDING
    "has_audience_signal": True,
    "assets": {
        "HEADLINE": ["a", "b", "c"],
        "LONG_HEADLINE": ["x"],
        "DESCRIPTION": ["d1", "d2"],
        "BUSINESS_NAME": ["Happy Lolli"],
        "MARKETING_IMAGE": ["img1"],         # landscape 1.91:1
        "SQUARE_MARKETING_IMAGE": ["img2"],  # 1:1
        "PORTRAIT_MARKETING_IMAGE": [],      # 4:5
        "LOGO": ["logo1"],                   # 1:1
        "LANDSCAPE_LOGO": [],                # 4:1
        "YOUTUBE_VIDEO": [],
    },
}
```

- [ ] **Step 1: Write the failing test**

`tools/mcp/tests/test_audit_rules.py`:
```python
from tools.mcp.google_ads.audit_rules import Finding, check_text_coverage


def _assets(**overrides):
    base = {
        "HEADLINE": ["a", "b", "c"],
        "LONG_HEADLINE": ["x"],
        "DESCRIPTION": ["d1", "d2"],
        "BUSINESS_NAME": ["Happy Lolli"],
    }
    base.update(overrides)
    return base


def test_text_coverage_passing_config_has_no_errors():
    ag = {"name": "G", "assets": _assets()}
    findings = check_text_coverage(ag)
    assert all(f.severity != "error" for f in findings)


def test_text_coverage_flags_too_few_headlines():
    ag = {"name": "G", "assets": _assets(HEADLINE=["only one"])}
    findings = check_text_coverage(ag)
    errs = [f for f in findings if f.severity == "error" and f.check == "headlines"]
    assert len(errs) == 1
    assert "headlines" in errs[0].message.lower()


def test_text_coverage_warns_below_recommended_headlines():
    ag = {"name": "G", "assets": _assets(HEADLINE=["a", "b", "c"])}
    findings = check_text_coverage(ag)
    warns = [f for f in findings if f.severity == "warning" and f.check == "headlines"]
    assert len(warns) == 1


def test_text_coverage_flags_missing_business_name():
    ag = {"name": "G", "assets": _assets(BUSINESS_NAME=[])}
    findings = check_text_coverage(ag)
    assert any(f.check == "business_name" and f.severity == "error" for f in findings)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tools/mcp/tests/test_audit_rules.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.mcp.google_ads.audit_rules'`.

- [ ] **Step 3: Write minimal implementation**

`tools/mcp/google_ads/audit_rules.py`:
```python
"""Pure audit rules for Google Ads Performance Max asset groups and campaigns.

No google-ads / mcp imports here, so these functions are unit-testable on bare pytest.
Each rule takes a normalized config dict and returns a list of Finding objects.
"""

from dataclasses import dataclass

# PMax asset-coverage thresholds: (minimum required, recommended).
MIN_HEADLINES, REC_HEADLINES = 3, 5
MIN_LONG_HEADLINES, REC_LONG_HEADLINES = 1, 5
MIN_DESCRIPTIONS, REC_DESCRIPTIONS = 2, 4


@dataclass
class Finding:
    severity: str  # "error" | "warning" | "ok"
    scope: str     # e.g. "asset_group:Gift Boxes" or "campaign:PMax-1"
    check: str     # e.g. "headlines"
    message: str


def _count(ag: dict, field: str) -> int:
    return len(ag.get("assets", {}).get(field, []))


def check_text_coverage(ag: dict) -> list[Finding]:
    scope = f"asset_group:{ag.get('name', '?')}"
    findings: list[Finding] = []

    specs = [
        ("headlines", "HEADLINE", MIN_HEADLINES, REC_HEADLINES),
        ("long_headlines", "LONG_HEADLINE", MIN_LONG_HEADLINES, REC_LONG_HEADLINES),
        ("descriptions", "DESCRIPTION", MIN_DESCRIPTIONS, REC_DESCRIPTIONS),
    ]
    for check, field, minimum, rec in specs:
        n = _count(ag, field)
        if n < minimum:
            findings.append(Finding("error", scope, check,
                f"Only {n} {check} (Google requires at least {minimum})."))
        elif n < rec:
            findings.append(Finding("warning", scope, check,
                f"{n} {check}; recommended {rec} for best ad strength."))

    if _count(ag, "BUSINESS_NAME") < 1:
        findings.append(Finding("error", scope, "business_name",
            "No business name asset set."))

    return findings
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tools/mcp/tests/test_audit_rules.py -v`
Expected: PASS — 4 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/mcp/google_ads/audit_rules.py tools/mcp/tests/test_audit_rules.py
git commit -m "feat(google-ads): add Finding model and text-coverage audit rule"
```

---

### Task 3: Image-coverage rule

**Files:**
- Modify: `tools/mcp/google_ads/audit_rules.py`
- Modify: `tools/mcp/tests/test_audit_rules.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/mcp/tests/test_audit_rules.py`:
```python
from tools.mcp.google_ads.audit_rules import check_image_coverage


def _img_assets(**overrides):
    base = {
        "MARKETING_IMAGE": ["land1"],
        "SQUARE_MARKETING_IMAGE": ["sq1"],
        "PORTRAIT_MARKETING_IMAGE": ["por1"],
        "LOGO": ["logo1"],
    }
    base.update(overrides)
    return base


def test_image_coverage_full_config_no_errors():
    ag = {"name": "G", "assets": _img_assets()}
    assert all(f.severity != "error" for f in check_image_coverage(ag))


def test_image_coverage_errors_when_no_landscape():
    ag = {"name": "G", "assets": _img_assets(MARKETING_IMAGE=[])}
    findings = check_image_coverage(ag)
    assert any(f.check == "landscape_image" and f.severity == "error" for f in findings)


def test_image_coverage_errors_when_no_square():
    ag = {"name": "G", "assets": _img_assets(SQUARE_MARKETING_IMAGE=[])}
    findings = check_image_coverage(ag)
    assert any(f.check == "square_image" and f.severity == "error" for f in findings)


def test_image_coverage_warns_when_no_portrait():
    ag = {"name": "G", "assets": _img_assets(PORTRAIT_MARKETING_IMAGE=[])}
    findings = check_image_coverage(ag)
    assert any(f.check == "portrait_image" and f.severity == "warning" for f in findings)


def test_image_coverage_errors_when_no_logo():
    ag = {"name": "G", "assets": _img_assets(LOGO=[])}
    findings = check_image_coverage(ag)
    assert any(f.check == "logo" and f.severity == "error" for f in findings)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tools/mcp/tests/test_audit_rules.py -k image_coverage -v`
Expected: FAIL — `ImportError: cannot import name 'check_image_coverage'`.

- [ ] **Step 3: Write minimal implementation**

Append to `tools/mcp/google_ads/audit_rules.py`:
```python
def check_image_coverage(ag: dict) -> list[Finding]:
    scope = f"asset_group:{ag.get('name', '?')}"
    findings: list[Finding] = []

    if _count(ag, "MARKETING_IMAGE") < 1:
        findings.append(Finding("error", scope, "landscape_image",
            "No landscape (1.91:1) marketing image."))
    if _count(ag, "SQUARE_MARKETING_IMAGE") < 1:
        findings.append(Finding("error", scope, "square_image",
            "No square (1:1) marketing image."))
    if _count(ag, "PORTRAIT_MARKETING_IMAGE") < 1:
        findings.append(Finding("warning", scope, "portrait_image",
            "No portrait (4:5) image; adding one improves reach."))
    if _count(ag, "LOGO") < 1:
        findings.append(Finding("error", scope, "logo",
            "No square (1:1) logo."))

    return findings
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tools/mcp/tests/test_audit_rules.py -k image_coverage -v`
Expected: PASS — 5 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/mcp/google_ads/audit_rules.py tools/mcp/tests/test_audit_rules.py
git commit -m "feat(google-ads): add image-coverage audit rule"
```

---

### Task 4: Ad-strength and targeting rules

**Files:**
- Modify: `tools/mcp/google_ads/audit_rules.py`
- Modify: `tools/mcp/tests/test_audit_rules.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/mcp/tests/test_audit_rules.py`:
```python
from tools.mcp.google_ads.audit_rules import check_ad_strength, check_targeting


def test_ad_strength_good_is_ok():
    ag = {"name": "G", "ad_strength": "GOOD"}
    assert all(f.severity != "error" for f in check_ad_strength(ag))


def test_ad_strength_poor_is_error():
    ag = {"name": "G", "ad_strength": "POOR"}
    findings = check_ad_strength(ag)
    assert any(f.check == "ad_strength" and f.severity == "error" for f in findings)


def test_ad_strength_average_is_warning():
    ag = {"name": "G", "ad_strength": "AVERAGE"}
    findings = check_ad_strength(ag)
    assert any(f.check == "ad_strength" and f.severity == "warning" for f in findings)


def test_targeting_warns_when_no_audience_signal():
    ag = {"name": "G", "has_audience_signal": False}
    findings = check_targeting(ag)
    assert any(f.check == "audience_signal" and f.severity == "warning" for f in findings)


def test_targeting_ok_with_audience_signal():
    ag = {"name": "G", "has_audience_signal": True}
    assert all(f.check != "audience_signal" for f in check_targeting(ag))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tools/mcp/tests/test_audit_rules.py -k "ad_strength or targeting" -v`
Expected: FAIL — `ImportError: cannot import name 'check_ad_strength'`.

- [ ] **Step 3: Write minimal implementation**

Append to `tools/mcp/google_ads/audit_rules.py`:
```python
def check_ad_strength(ag: dict) -> list[Finding]:
    scope = f"asset_group:{ag.get('name', '?')}"
    strength = (ag.get("ad_strength") or "PENDING").upper()
    if strength == "POOR":
        return [Finding("error", scope, "ad_strength",
            "Ad strength is POOR — add more/varied assets.")]
    if strength == "AVERAGE":
        return [Finding("warning", scope, "ad_strength",
            "Ad strength is AVERAGE — room to improve.")]
    return [Finding("ok", scope, "ad_strength", f"Ad strength is {strength}.")]


def check_targeting(ag: dict) -> list[Finding]:
    scope = f"asset_group:{ag.get('name', '?')}"
    if not ag.get("has_audience_signal", False):
        return [Finding("warning", scope, "audience_signal",
            "No audience signal attached — slows PMax learning.")]
    return [Finding("ok", scope, "audience_signal", "Audience signal attached.")]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tools/mcp/tests/test_audit_rules.py -k "ad_strength or targeting" -v`
Expected: PASS — 5 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/mcp/google_ads/audit_rules.py tools/mcp/tests/test_audit_rules.py
git commit -m "feat(google-ads): add ad-strength and targeting audit rules"
```

---

### Task 5: Campaign-level rule

**Files:**
- Modify: `tools/mcp/google_ads/audit_rules.py`
- Modify: `tools/mcp/tests/test_audit_rules.py`

The campaign config dict shape:
```python
{
    "name": "PMax-Gifts",
    "status": "ENABLED",            # ENABLED|PAUSED|REMOVED
    "budget_micros": 50_000_000,    # 50 currency units/day
    "target_roas": 4.0,             # float or None
    "final_url_expansion_opt_out": False,
    "brand_exclusions_count": 2,
}
```

- [ ] **Step 1: Write the failing test**

Append to `tools/mcp/tests/test_audit_rules.py`:
```python
from tools.mcp.google_ads.audit_rules import check_campaign


def _campaign(**overrides):
    base = {
        "name": "PMax-Gifts",
        "status": "ENABLED",
        "budget_micros": 50_000_000,
        "target_roas": 4.0,
        "final_url_expansion_opt_out": True,
        "brand_exclusions_count": 1,
    }
    base.update(overrides)
    return base


def test_campaign_healthy_has_no_errors():
    assert all(f.severity != "error" for f in check_campaign(_campaign()))


def test_campaign_zero_budget_is_error():
    findings = check_campaign(_campaign(budget_micros=0))
    assert any(f.check == "budget" and f.severity == "error" for f in findings)


def test_campaign_missing_target_roas_is_warning():
    findings = check_campaign(_campaign(target_roas=None))
    assert any(f.check == "target_roas" and f.severity == "warning" for f in findings)


def test_campaign_url_expansion_on_is_warning():
    findings = check_campaign(_campaign(final_url_expansion_opt_out=False))
    assert any(f.check == "final_url_expansion" and f.severity == "warning" for f in findings)


def test_campaign_no_brand_exclusions_is_warning():
    findings = check_campaign(_campaign(brand_exclusions_count=0))
    assert any(f.check == "brand_exclusions" and f.severity == "warning" for f in findings)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tools/mcp/tests/test_audit_rules.py -k campaign -v`
Expected: FAIL — `ImportError: cannot import name 'check_campaign'`.

- [ ] **Step 3: Write minimal implementation**

Append to `tools/mcp/google_ads/audit_rules.py`:
```python
def check_campaign(camp: dict) -> list[Finding]:
    scope = f"campaign:{camp.get('name', '?')}"
    findings: list[Finding] = []

    if (camp.get("budget_micros") or 0) <= 0:
        findings.append(Finding("error", scope, "budget",
            "Campaign has no daily budget set."))
    if camp.get("target_roas") in (None, 0):
        findings.append(Finding("warning", scope, "target_roas",
            "No target ROAS set — bidding has no profit target."))
    if not camp.get("final_url_expansion_opt_out", False):
        findings.append(Finding("warning", scope, "final_url_expansion",
            "Final URL expansion is ON — verify it isn't sending traffic to off-target pages."))
    if (camp.get("brand_exclusions_count") or 0) < 1:
        findings.append(Finding("warning", scope, "brand_exclusions",
            "No brand exclusions — PMax may spend on your own brand searches."))

    return findings
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tools/mcp/tests/test_audit_rules.py -k campaign -v`
Expected: PASS — 5 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/mcp/google_ads/audit_rules.py tools/mcp/tests/test_audit_rules.py
git commit -m "feat(google-ads): add campaign-level audit rule"
```

---

### Task 6: Orchestrator — audit a full account snapshot

**Files:**
- Modify: `tools/mcp/google_ads/audit_rules.py`
- Modify: `tools/mcp/tests/test_audit_rules.py`
- Create: `tools/mcp/tests/fixtures/account_snapshot.json`

The account-snapshot dict shape (what `queries.py` will produce in Task 8):
```python
{
    "customer_id": "1234567890",
    "campaigns": [
        {  # campaign dict (Task 5 shape) plus an "asset_groups" list
            "name": "PMax-Gifts", "status": "ENABLED", "budget_micros": 50_000_000,
            "target_roas": 4.0, "final_url_expansion_opt_out": True, "brand_exclusions_count": 1,
            "asset_groups": [ {asset-group dict, Task 2/3/4 shape}, ... ],
        },
    ],
}
```

- [ ] **Step 1: Create the fixture**

`tools/mcp/tests/fixtures/account_snapshot.json`:
```json
{
  "customer_id": "1234567890",
  "campaigns": [
    {
      "name": "PMax-Gifts",
      "status": "ENABLED",
      "budget_micros": 50000000,
      "target_roas": 4.0,
      "final_url_expansion_opt_out": true,
      "brand_exclusions_count": 1,
      "asset_groups": [
        {
          "name": "Gift Boxes",
          "ad_strength": "AVERAGE",
          "has_audience_signal": false,
          "assets": {
            "HEADLINE": ["a", "b", "c"],
            "LONG_HEADLINE": ["x"],
            "DESCRIPTION": ["d1", "d2"],
            "BUSINESS_NAME": ["Happy Lolli"],
            "MARKETING_IMAGE": ["land1"],
            "SQUARE_MARKETING_IMAGE": ["sq1"],
            "PORTRAIT_MARKETING_IMAGE": [],
            "LOGO": ["logo1"]
          }
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Write the failing test**

Append to `tools/mcp/tests/test_audit_rules.py`:
```python
import json
from pathlib import Path

from tools.mcp.google_ads.audit_rules import audit_account

FIXTURES = Path(__file__).parent / "fixtures"


def test_audit_account_returns_grouped_findings():
    snapshot = json.loads((FIXTURES / "account_snapshot.json").read_text())
    result = audit_account(snapshot)

    assert result["customer_id"] == "1234567890"
    # Summary counts every finding by severity.
    assert set(result["summary"]) == {"error", "warning", "ok"}
    # The thin/average fixture must surface at least these warnings.
    checks = {f["check"] for f in result["findings"]}
    assert "ad_strength" in checks          # AVERAGE
    assert "audience_signal" in checks      # missing
    assert "portrait_image" in checks       # missing
    # Findings are plain dicts (JSON-serializable for the MCP tool).
    assert all(isinstance(f, dict) for f in result["findings"])
```

- [ ] **Step 3: Run test to verify it fails**

Run: `.venv/bin/pytest tools/mcp/tests/test_audit_rules.py -k audit_account -v`
Expected: FAIL — `ImportError: cannot import name 'audit_account'`.

- [ ] **Step 4: Write minimal implementation**

Append to `tools/mcp/google_ads/audit_rules.py`:
```python
def audit_asset_group(ag: dict) -> list[Finding]:
    return (
        check_text_coverage(ag)
        + check_image_coverage(ag)
        + check_ad_strength(ag)
        + check_targeting(ag)
    )


def audit_account(snapshot: dict) -> dict:
    """Run every rule over an account snapshot and return JSON-serializable findings."""
    findings: list[Finding] = []
    for camp in snapshot.get("campaigns", []):
        findings.extend(check_campaign(camp))
        for ag in camp.get("asset_groups", []):
            findings.extend(audit_asset_group(ag))

    summary = {"error": 0, "warning": 0, "ok": 0}
    for f in findings:
        summary[f.severity] = summary.get(f.severity, 0) + 1

    return {
        "customer_id": snapshot.get("customer_id"),
        "summary": summary,
        "findings": [vars(f) for f in findings],
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `.venv/bin/pytest tools/mcp/tests/test_audit_rules.py -v`
Expected: PASS — all tests (Tasks 2–6) green.

- [ ] **Step 6: Commit**

```bash
git add tools/mcp/google_ads/audit_rules.py tools/mcp/tests/test_audit_rules.py tools/mcp/tests/fixtures/account_snapshot.json
git commit -m "feat(google-ads): add account-snapshot audit orchestrator"
```

---

### Task 7: Credentials builder from env

**Files:**
- Create: `tools/mcp/google_ads/client.py`
- Create: `tools/mcp/tests/test_client.py`

`build_credentials()` reads env vars and returns a dict suitable for `GoogleAdsClient.load_from_dict`. It does **not** import `google-ads`, so it's testable in isolation. Raises `ValueError` naming the exact missing key.

- [ ] **Step 1: Write the failing test**

`tools/mcp/tests/test_client.py`:
```python
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
    # login_customer_id is digits-only (Google requires no dashes).
    assert creds["login_customer_id"] == "1112223333"


def test_build_credentials_missing_var_names_the_key():
    broken = dict(ENV)
    del broken["GOOGLE_ADS_REFRESH_TOKEN"]
    with pytest.raises(ValueError) as exc:
        build_credentials(broken)
    assert "GOOGLE_ADS_REFRESH_TOKEN" in str(exc.value)


def test_required_env_lists_all_six():
    assert len(REQUIRED_ENV) == 6
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tools/mcp/tests/test_client.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.mcp.google_ads.client'`.

- [ ] **Step 3: Write minimal implementation**

`tools/mcp/google_ads/client.py`:
```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tools/mcp/tests/test_client.py -v`
Expected: PASS — 3 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/mcp/google_ads/client.py tools/mcp/tests/test_client.py
git commit -m "feat(google-ads): add env-based credentials builder"
```

---

### Task 8: GAQL query builders

**Files:**
- Create: `tools/mcp/google_ads/queries.py`
- Create: `tools/mcp/tests/test_queries.py`

`queries.py` holds pure GAQL **string** builders (testable) plus a thin `fetch_account_snapshot(client, customer_id)` that runs them and normalizes results into the snapshot dict from Task 6. Only the string builders are unit-tested; the fetch path is exercised by the live smoke test in Task 10.

- [ ] **Step 1: Write the failing test**

`tools/mcp/tests/test_queries.py`:
```python
from tools.mcp.google_ads.queries import (
    campaigns_query,
    asset_groups_query,
    asset_group_assets_query,
)


def test_campaigns_query_targets_pmax_and_shopping():
    q = campaigns_query()
    assert "FROM campaign" in q
    assert "campaign.advertising_channel_type" in q
    assert "PERFORMANCE_MAX" in q
    assert "SHOPPING" in q


def test_asset_groups_query_selects_ad_strength():
    q = asset_groups_query()
    assert "FROM asset_group" in q
    assert "asset_group.ad_strength" in q


def test_asset_group_assets_query_filters_by_group():
    q = asset_group_assets_query("987654")
    assert "FROM asset_group_asset" in q
    assert "asset_group.id = 987654" in q
    assert "asset_group_asset.field_type" in q
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tools/mcp/tests/test_queries.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.mcp.google_ads.queries'`.

- [ ] **Step 3: Write minimal implementation**

`tools/mcp/google_ads/queries.py`:
```python
"""GAQL query builders (pure strings) and the read-only snapshot fetcher.

Read-only: only GoogleAdsService.search is used. No mutate calls anywhere.
"""


def campaigns_query() -> str:
    return (
        "SELECT campaign.id, campaign.name, campaign.status, "
        "campaign.advertising_channel_type, campaign_budget.amount_micros, "
        "campaign.maximize_conversion_value.target_roas, "
        "campaign.url_expansion_opt_out "
        "FROM campaign "
        "WHERE campaign.advertising_channel_type IN ('PERFORMANCE_MAX', 'SHOPPING') "
        "AND campaign.status != 'REMOVED'"
    )


def asset_groups_query() -> str:
    return (
        "SELECT asset_group.id, asset_group.name, asset_group.status, "
        "asset_group.ad_strength, asset_group.campaign "
        "FROM asset_group "
        "WHERE asset_group.status != 'REMOVED'"
    )


def asset_group_assets_query(asset_group_id: str) -> str:
    return (
        "SELECT asset_group_asset.field_type, asset_group_asset.asset, "
        "asset.id "
        "FROM asset_group_asset "
        f"WHERE asset_group.id = {int(asset_group_id)} "
        "AND asset_group_asset.status != 'REMOVED'"
    )


def fetch_account_snapshot(client, customer_id: str) -> dict:
    """Run the read queries and normalize into the audit snapshot dict.

    Uses GoogleAdsService.search (read-only). Field-type enum names from
    asset_group_asset.field_type populate the per-group 'assets' buckets.
    """
    svc = client.get_service("GoogleAdsService")

    campaigns: dict[str, dict] = {}
    for row in svc.search(customer_id=customer_id, query=campaigns_query()):
        target_roas = None
        mcv = row.campaign.maximize_conversion_value
        if mcv and mcv.target_roas:
            target_roas = mcv.target_roas
        campaigns[str(row.campaign.id)] = {
            "name": row.campaign.name,
            "status": row.campaign.status.name,
            "budget_micros": row.campaign_budget.amount_micros,
            "target_roas": target_roas,
            "final_url_expansion_opt_out": bool(row.campaign.url_expansion_opt_out),
            "brand_exclusions_count": 0,  # populated by a brand-list query in a later iteration
            "asset_groups": [],
            "_ag_index": {},
        }

    for row in svc.search(customer_id=customer_id, query=asset_groups_query()):
        camp_id = row.asset_group.campaign.split("/")[-1]
        camp = campaigns.get(camp_id)
        if not camp:
            continue
        ag = {
            "id": str(row.asset_group.id),
            "name": row.asset_group.name,
            "ad_strength": row.asset_group.ad_strength.name,
            "has_audience_signal": False,  # set by signal query in a later iteration
            "assets": {},
        }
        camp["asset_groups"].append(ag)
        camp["_ag_index"][ag["id"]] = ag

    for camp in campaigns.values():
        for ag in camp["asset_groups"]:
            for row in svc.search(
                customer_id=customer_id, query=asset_group_assets_query(ag["id"])
            ):
                field = row.asset_group_asset.field_type.name
                ag["assets"].setdefault(field, []).append(str(row.asset.id))
        camp.pop("_ag_index", None)

    return {
        "customer_id": customer_id,
        "campaigns": list(campaigns.values()),
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tools/mcp/tests/test_queries.py -v`
Expected: PASS — 3 passed.

- [ ] **Step 5: Run the whole suite to confirm nothing regressed**

Run: `.venv/bin/pytest tools/mcp/tests -v`
Expected: PASS — all tests green.

- [ ] **Step 6: Commit**

```bash
git add tools/mcp/google_ads/queries.py tools/mcp/tests/test_queries.py
git commit -m "feat(google-ads): add GAQL query builders and snapshot fetcher"
```

---

### Task 9: FastMCP server wiring

**Files:**
- Create: `tools/mcp/google_ads_server.py`
- Create: `tools/mcp/tests/test_server_smoke.py`

The server exposes 5 read tools. `audit_pmax` is the headline tool: fetch snapshot → `audit_account` → JSON, with an optional dump to `OI/exports/`.

- [ ] **Step 1: Write the failing smoke test**

`tools/mcp/tests/test_server_smoke.py`:
```python
import importlib


def test_server_module_imports_and_registers_tools():
    mod = importlib.import_module("tools.mcp.google_ads_server")
    # FastMCP instance is exposed as `mcp`.
    assert mod.mcp is not None
    # The five read tools exist as module-level callables.
    for name in [
        "list_campaigns",
        "get_asset_groups",
        "get_asset_group_assets",
        "get_listing_groups",
        "audit_pmax",
    ]:
        assert callable(getattr(mod, name))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tools/mcp/tests/test_server_smoke.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.mcp.google_ads_server'`.

- [ ] **Step 3: Write minimal implementation**

`tools/mcp/google_ads_server.py`:
```python
"""Google Ads PMax Audit MCP Server (Phase 1, read-only).

Exposes read-only tools to inspect and audit Performance Max / Shopping campaigns.
No mutate calls — this server cannot change the account.
"""

import json
from pathlib import Path

from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP

from tools.mcp.google_ads import audit_rules, queries
from tools.mcp.google_ads.client import customer_id, get_client

load_dotenv(Path(__file__).resolve().parents[2] / ".env")

mcp = FastMCP("OI Google Ads (read-only)")

EXPORTS_DIR = Path(__file__).resolve().parents[2] / "exports"


def _snapshot() -> dict:
    client = get_client()
    return queries.fetch_account_snapshot(client, customer_id())


@mcp.tool()
def list_campaigns() -> str:
    """List PMax/Shopping campaigns with status, budget, and target ROAS."""
    snap = _snapshot()
    rows = [
        {k: c[k] for k in ("name", "status", "budget_micros", "target_roas")}
        for c in snap["campaigns"]
    ]
    return json.dumps({"count": len(rows), "campaigns": rows}, default=str)


@mcp.tool()
def get_asset_groups() -> str:
    """List asset groups per campaign with ad strength."""
    snap = _snapshot()
    rows = []
    for c in snap["campaigns"]:
        for ag in c["asset_groups"]:
            rows.append({"campaign": c["name"], "asset_group": ag["name"],
                         "ad_strength": ag.get("ad_strength")})
    return json.dumps({"count": len(rows), "asset_groups": rows}, default=str)


@mcp.tool()
def get_asset_group_assets() -> str:
    """List asset counts by field type for every asset group."""
    snap = _snapshot()
    rows = []
    for c in snap["campaigns"]:
        for ag in c["asset_groups"]:
            counts = {ft: len(v) for ft, v in ag.get("assets", {}).items()}
            rows.append({"campaign": c["name"], "asset_group": ag["name"], "asset_counts": counts})
    return json.dumps({"count": len(rows), "rows": rows}, default=str)


@mcp.tool()
def get_listing_groups() -> str:
    """Report listing-group structure per asset group (all-products vs subdivided).

    Phase 1 returns a placeholder note; listing-group detail lands in a later iteration.
    """
    return json.dumps({"note": "Listing-group detail not yet implemented in Phase 1."})


@mcp.tool()
def audit_pmax(dump_json: bool = False) -> str:
    """Audit all PMax/Shopping campaigns against the config checklist.

    Returns a summary + findings (severity error/warning/ok). Set dump_json=True to
    also write the raw findings to OI/exports/.
    """
    snap = _snapshot()
    result = audit_rules.audit_account(snap)
    result["feed_health"] = "not checked — needs Merchant Center Content API (out of Phase 1 scope)"
    if dump_json:
        EXPORTS_DIR.mkdir(exist_ok=True)
        out = EXPORTS_DIR / f"pmax_audit_{snap['customer_id']}.json"
        out.write_text(json.dumps(result, indent=2, default=str))
        result["written_to"] = str(out)
    return json.dumps(result, default=str)


if __name__ == "__main__":
    mcp.run()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tools/mcp/tests/test_server_smoke.py -v`
Expected: PASS — 1 passed. (The import works because `client.py`/`queries.py` defer the live `google-ads` calls; no credentials are needed to import.)

- [ ] **Step 5: Run the full suite**

Run: `.venv/bin/pytest tools/mcp/tests -v`
Expected: PASS — all tests green.

- [ ] **Step 6: Commit**

```bash
git add tools/mcp/google_ads_server.py tools/mcp/tests/test_server_smoke.py
git commit -m "feat(google-ads): add read-only PMax audit MCP server"
```

---

### Task 10: Live smoke test, MCP registration, and docs

This task needs the **credentials in place** (the manual prerequisite). If the developer token / OAuth is not ready yet, do Steps 1, 5, 6 now and return for Steps 2–4 once `OI/.env` is populated.

**Files:**
- Create: `tools/mcp/GOOGLE_ADS_SETUP.md`
- Modify: `CLAUDE.md` (the OI project CLAUDE.md, MCP server list)

- [ ] **Step 1: Write the setup doc**

`tools/mcp/GOOGLE_ADS_SETUP.md`:
```markdown
# Google Ads Audit MCP — Setup

Read-only Phase 1. Audits Performance Max / Shopping campaigns.

## Prerequisites (one-time)
1. Google Ads **Manager (MCC)** account → apply for a **developer token** (Basic access is enough for one own-account).
2. In GCP project `onyga-482313`: create an OAuth2 **Desktop** client → client ID + secret.
3. Generate a **refresh token** for the account (Google's `generate_user_credentials` flow).
4. Find the customer ID of the Happy Lolli Google Ads account.

## Env vars (in OI/.env)
GOOGLE_ADS_DEVELOPER_TOKEN=...
GOOGLE_ADS_CLIENT_ID=...
GOOGLE_ADS_CLIENT_SECRET=...
GOOGLE_ADS_REFRESH_TOKEN=...
GOOGLE_ADS_LOGIN_CUSTOMER_ID=...   # the MCC, dashes optional
GOOGLE_ADS_CUSTOMER_ID=...         # the Happy Lolli account, dashes optional

## Run / register
Launch: `.venv/bin/python tools/mcp/google_ads_server.py`
Register in your Claude MCP config as a stdio server:
  command: /Users/ori/Develop/OI/.venv/bin/python
  args: ["/Users/ori/Develop/OI/tools/mcp/google_ads_server.py"]

## Tools
- list_campaigns, get_asset_groups, get_asset_group_assets, get_listing_groups
- audit_pmax(dump_json=False) — the headline audit

## Known gap
Product-feed health (disapprovals, GTINs) needs the Merchant Center Content API — not in Phase 1.
```

- [ ] **Step 2: Run the live smoke test (requires creds)**

Run: `.venv/bin/python -c "from tools.mcp.google_ads_server import list_campaigns; print(list_campaigns())"`
Expected: JSON with a `campaigns` array (may be empty if no live campaigns), no traceback. A clear `ValueError` naming a missing env var means creds aren't set yet.

- [ ] **Step 3: Run the live audit (requires creds)**

Run: `.venv/bin/python -c "from tools.mcp.google_ads_server import audit_pmax; print(audit_pmax(True))"`
Expected: JSON with `summary`, `findings`, `feed_health`, and `written_to` pointing into `OI/exports/`.

- [ ] **Step 4: Register the server in the Claude MCP config**

Add to the Claude Code MCP config (top-level `mcpServers` in `~/.claude.json`, alongside `canva`/`shopify-dev`):
```json
"oi-google-ads": {
  "type": "stdio",
  "command": "/Users/ori/Develop/OI/.venv/bin/python",
  "args": ["/Users/ori/Develop/OI/tools/mcp/google_ads_server.py"]
}
```
Restart Claude Code; confirm the `oi-google-ads` tools appear.

- [ ] **Step 5: Update the OI project CLAUDE.md**

In the MCP servers section of `CLAUDE.md` (repo root), add under the custom servers list:
```
- **oi-google-ads:** Read-only Google Ads PMax audit — list_campaigns, get_asset_groups, audit_pmax (Phase 1). See tools/mcp/GOOGLE_ADS_SETUP.md.
```

- [ ] **Step 6: Commit**

```bash
git add tools/mcp/GOOGLE_ADS_SETUP.md CLAUDE.md
git commit -m "docs(google-ads): add setup guide and register audit MCP"
```

---

## Notes for the implementer

- **pytest import paths:** tests import as `tools.mcp.google_ads.*`, so run pytest from the repo root (`/Users/ori/Develop/OI`) where `tools/` is importable. If imports fail, confirm there is no conflicting `tools` on `sys.path` and that you ran from the repo root. Add a `conftest.py` at repo root only if needed: `import sys, pathlib; sys.path.insert(0, str(pathlib.Path(__file__).parent))`.
- **Read-only guarantee:** if you ever see `get_service(...).mutate*` in this codebase under `google_ads`, that's Phase 2 and out of scope here. Phase 1 must stay search-only.
- **Field-type enum names** (`HEADLINE`, `MARKETING_IMAGE`, `SQUARE_MARKETING_IMAGE`, `PORTRAIT_MARKETING_IMAGE`, `LOGO`, `LANDSCAPE_LOGO`, `YOUTUBE_VIDEO`, `BUSINESS_NAME`, `LONG_HEADLINE`, `DESCRIPTION`) come straight from `asset_group_asset.field_type` — they key the `assets` dict the rules read.
```
