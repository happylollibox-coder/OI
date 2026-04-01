const XLSX = require('xlsx');
const sbRows = [];
sbRows.push({
  'Product': 'Sponsored Brands',
  'Entity': 'Negative Keyword',
  'Operation': 'Create',
  'Campaign Id': 'camp123',
  'Ad Group Id': '',
  'Campaign Name': 'my camp',
  'Keyword Text': 'test var',
  'Match Type': 'negativeExact',
  'State': 'enabled',
});
const ws = XLSX.utils.json_to_sheet(sbRows);
const wb = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(wb, ws, 'Sponsored Brands Campaigns');
XLSX.writeFile(wb, 'test_out.xlsx');
