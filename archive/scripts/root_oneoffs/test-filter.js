const rows = [
  { 'InventorySnapshot.quantityBalance': 0, 'InventorySnapshot.sourceType': 'AWD' },
  { 'InventorySnapshot.quantityBalance': 100, 'InventorySnapshot.sourceType': 'FBA' }
];

const mapped = rows.map(r => ({
  quantity_balance: Number(r['InventorySnapshot.quantityBalance'] ?? 0),
  source_type: r['InventorySnapshot.sourceType']
}));

const showZeroBalances = false;

const filtered = mapped.filter(r => showZeroBalances || r.quantity_balance !== 0);

console.log(filtered);
