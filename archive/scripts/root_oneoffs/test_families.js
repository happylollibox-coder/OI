const fs = require('fs');
const source = fs.readFileSync('dashboard-react/src/pages/PlanPage.tsx', 'utf8');

// I just want to write a basic regex to see if `families` is empty
// Let me just run a script that simulates the map.
console.log("Checking if families is mutated...");
