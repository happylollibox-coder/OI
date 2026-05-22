const axios = require('axios');

async function check() {
  const q = {
    query: {
      dimensions: ["ForecastDemand.family"],
    }
  };
  const url = `http://localhost:4000/cubejs-api/v1/load?query=${encodeURIComponent(JSON.stringify(q.query))}`;
  try {
    const res = await axios.get(url, { headers: { Authorization: "Bearer test" } });
    console.log("Families:", res.data.data.map(r => r['ForecastDemand.family']));
  } catch (err) {
    console.error(err.response ? err.response.data : err.message);
  }
}
check();
