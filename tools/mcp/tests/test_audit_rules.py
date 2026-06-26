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
