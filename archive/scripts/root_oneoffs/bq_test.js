const { BigQuery } = require('@google-cloud/bigquery');
const bigquery = new BigQuery();
async function run() {
  const query = `
    SELECT 
      quantity_balance, count(*) as c 
    FROM \`onyga-482313.OI.FACT_INVENTORY_SNAPSHOT\` 
    WHERE Date = '2026-05-04' 
    GROUP BY 1
    ORDER BY quantity_balance DESC
  `;
  const [rows] = await bigquery.query(query);
  console.log(rows);
}
run();
