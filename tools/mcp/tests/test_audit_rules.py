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
