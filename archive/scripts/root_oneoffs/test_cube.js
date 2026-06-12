const http = require('http');
const req = http.request({
  hostname: 'localhost',
  port: 4000,
  path: `/cubejs-api/v1/load?query=${encodeURIComponent(JSON.stringify({
    dimensions: ["AdsCoachActions.campaignName", "AdsCoachActions.strategyId"],
    limit: 10
  }))}`,
  method: 'GET'
}, res => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => console.log(data));
});
req.on('error', console.error);
req.end();
