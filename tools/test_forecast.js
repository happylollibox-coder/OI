async function test() {
  const query = {
    "measures": [
      "ForecastDemand.forecastUnits",
      "ForecastDemand.peakDays",
      "ForecastDemand.offseasonDays"
    ],
    "dimensions": [
      "ForecastDemand.product",
      "ForecastDemand.family",
      "ForecastDemand.forecastYear",
      "ForecastDemand.forecastMonth",
      "ForecastDemand.productShare",
      "ForecastDemand.isNewProduct",
      "ForecastDemand.isDraft",
      "ForecastDemand.peakHolidays",
      "ForecastDemand.forecastPhase",
      "ForecastDemand.modelProduct"
    ]
  };

  const res = await fetch('http://localhost:4000/cubejs-api/v1/load?query=' + encodeURIComponent(JSON.stringify(query)), {
    headers: { 'Authorization': 'Bearer testing' }
  });
  
  const json = await res.json();
  const bunnies = json.data.filter(r => r['ForecastDemand.family'] === 'Bunny');
  console.log("Bunny count:", bunnies.length);
  if (bunnies.length > 0) {
    console.log("First Bunny row:", JSON.stringify(bunnies[0], null, 2));
  }
}
test();
