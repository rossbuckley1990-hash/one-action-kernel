// Quantifies penny leakage/creation of the CURRENT allocate() in the target repo.
// Usage: tsx quant.mjs [path/to/settle.ts]
const TARGET =
  process.argv[2] ??
  '/Users/ross/Documents/Qoder/2026-11-01/d649cff7/agent-lab/experiment/target-settlement/src/settle.ts';
const { allocate } = await import(TARGET);
let vanished = 0, created = 0, incorrect = 0, n = 0;
for (let total = 1; total <= 50000; total++) {
  for (const parties of [2, 3, 4, 7]) {
    const sum = allocate(total, parties).reduce((a, b) => a + b, 0);
    const diff = sum - total;
    n++;
    if (diff < 0) { vanished += -diff; incorrect++; }
    else if (diff > 0) { created += diff; incorrect++; }
  }
}
console.log(JSON.stringify({ settlements: n, incorrect, pennies_vanished: vanished, pennies_created: created }));
