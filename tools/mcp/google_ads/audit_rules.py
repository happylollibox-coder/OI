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
