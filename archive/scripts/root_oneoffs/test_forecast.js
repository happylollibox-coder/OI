const http = require('http');

const req = http.request({
  hostname: 'localhost',
  port: 4000,
  path: '/cubejs-api/v1/load',
  method: 'POST',
  headers: { 'Content-Type': 'application/json' }
}, res => {
  let body = '';
  res.on('data', chunk => body += chunk);
  res.on('end', () => {
    const data = JSON.parse(body);
    const mMap = {};
    for (const r of data.data) {
      const prod = String(r['ForecastDemand.product'] ?? '');
      const fam = String(r['ForecastDemand.family'] ?? '');
      const yr = Number(r['ForecastDemand.forecastYear'] ?? 0);
      const mo = Number(r['ForecastDemand.forecastMonth'] ?? 0);
      const isNew = String(r['ForecastDemand.isNewProduct'] ?? 'false') === 'true';
      if (!prod || !yr || !mo) continue;
      if (!mMap[prod]) mMap[prod] = { isNew, family: fam };
    }
    console.log("metaMap keys:", Object.keys(mMap));
    console.log("Bunny meta:", Object.keys(mMap).filter(k => mMap[k].family === 'Bunny').map(k => mMap[k]));
  });
});

req.write(JSON.stringify({
  query: {
    dimensions: [
      'ForecastDemand.product', 'ForecastDemand.family',
      'ForecastDemand.forecastYear', 'ForecastDemand.forecastMonth',
      'ForecastDemand.isNewProduct'
    ],
    measures: ['ForecastDemand.forecastUnits']
  }
}));
req.end();
