import urllib.request
import json
import urllib.parse
query_payload = {
    "measures": [],
    "dimensions": [
        "AdsCoachTerm.campaignId", "AdsCoachTerm.campaignName", "AdsCoachTerm.campaignType",
        "AdsCoachTerm.searchTerm", "AdsCoachTerm.asin", "AdsCoachTerm.productShortName",
        "AdsCoachTerm.parentName", "AdsCoachTerm.experimentName", "AdsCoachTerm.strategyId",
        "AdsCoachTerm.strategyName", "AdsCoachTerm.adsSpend4w", "AdsCoachTerm.adsOrders4w",
        "AdsCoachTerm.adsClicks4w", "AdsCoachTerm.adsSales4w", "AdsCoachTerm.adsRoas4w",
        "AdsCoachTerm.adsCpc4w", "AdsCoachTerm.adsCvrPct4w", "AdsCoachTerm.adsNetRoas4w",
        "AdsCoachTerm.adsNetProfit4w", "AdsCoachTerm.marginPerUnit", "AdsCoachTerm.termSpend4w",
        "AdsCoachTerm.termOrders4w", "AdsCoachTerm.termCampaignCount", "AdsCoachTerm.termSellingCampaigns",
        "AdsCoachTerm.spendSharePct", "AdsCoachTerm.ordersSharePct", "AdsCoachTerm.sqpOrders4w",
        "AdsCoachTerm.targeting", "AdsCoachTerm.keywordId", "AdsCoachTerm.effectiveRoas",
        "AdsCoachTerm.adsWeightedNetRoas", "AdsCoachTerm.targetNetRoas8w", "AdsCoachTerm.targetClicks8w",
        "AdsCoachTerm.targetOrders8w", "AdsCoachTerm.targetSpend8w", "AdsCoachTerm.currentBid",
        "AdsCoachTerm.recommendedBid", "AdsCoachTerm.bidChangePct", "AdsCoachTerm.matchType",
        "AdsCoachTerm.actionId", "AdsCoachTerm.decisionBranchId", "AdsCoachTerm.actionType",
        "AdsCoachTerm.action", "AdsCoachTerm.priorityScore", "AdsCoachTerm.confidence",
        "AdsCoachTerm.reason", "AdsCoachTerm.actionExplanation", "AdsCoachTerm.decisionTrace",
        "AdsCoachTerm.heroAsin", "AdsCoachTerm.heroProductName", "AdsCoachTerm.isHeroMatch",
        "AdsCoachTerm.heroNetRoas", "AdsCoachTerm.heroTotalOrders", "AdsCoachTerm.coachMode",
        "AdsCoachTerm.activeOccasion", "AdsCoachTerm.currentPhase", "AdsCoachTerm.ppDays",
        "AdsCoachTerm.ppTargetNetRoas", "AdsCoachTerm.ppTargetSpend", "AdsCoachTerm.ppTargetOrders",
        "AdsCoachTerm.tosPct", "AdsCoachTerm.productPagePct", "AdsCoachTerm.b2bPct",
        "AdsCoachTerm.prePeakBid", "AdsCoachTerm.prePeakTosPct", "AdsCoachTerm.prePeakPpPct",
        "AdsCoachTerm.prePeakB2bPct", "AdsCoachTerm.prePeakAvgCpc", "AdsCoachTerm.lastDayCpc",
        "AdsCoachTerm.currentBudget", "AdsCoachTerm.prePeakBudget", "AdsCoachTerm.recommendedBudget",
        "AdsCoachTerm.ppCampaignNetRoas", "AdsCoachTerm.strategicTask"
    ],
    "timeDimensions": [],
    "limit": 5
}
url = "http://localhost:4000/cubejs-api/v1/load?query=" + urllib.parse.quote(json.dumps(query_payload))
req = urllib.request.Request(url, headers={'Authorization': 'placeholder'})
try:
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read())
        print("Success! Row Count:", len(result.get('data', [])))
except urllib.error.URLError as e:
    print("Error:", e.read().decode('utf-8') if hasattr(e, 'read') else e)
