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
    return []
