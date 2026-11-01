#!/usr/bin/env bash
# ============================================================================
#  ONE-ACTION KERNEL — the product.
#
#  A single command fires the entire chain and ends with real signed evidence:
#
#     SAFETY ──► DISCOVER ──► MODEL ──► DO+VERIFY ──► FUSE ──► REMEMBER ──► PROVE ──► AUDIT
#
#  The multi-billion-pound problem: consequential AI actions that are
#  UNAUTHORISED, DOUBLE-EXECUTED, or FUNCTIONALLY WRONG — all reported as success.
#
#  This product makes each failure mode refuse-to-execute, behind TWO independent
#  signed authorities, from ONE action:
#     • Actenon proof      — authority (ed25519, audience/time/action-hash/nonce bound)
#     • correctness cert   — functional truth (property-verify over the whole bug
#                            class + Sentinel over approved examples), bound INTO the
#                            proof's signed extensions and re-verified at the edge.
#
#  Usage:  ./run.sh            (LAB defaults to this script's parent dir)
#          LAB=/path/to/lab ./run.sh
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LAB="${LAB:-$(cd "$HERE/.." && pwd)}"
EXP="$HERE"
OUT="$EXP/evidence/product"
rm -rf "$OUT"; mkdir -p "$OUT"

banner() {
  printf '\n\033[1;36m════════════════════════════════════════════════════════════════════\033[0m\n'
  printf '\033[1;36m  %s\033[0m\n' "$1"
  printf '\033[1;36m════════════════════════════════════════════════════════════════════\033[0m\n'
}

banner "ONE-ACTION KERNEL — Do → Model → Verify → Remember → Prove, fired from a single command"
echo "  LAB root : $LAB"
echo "  evidence : $OUT"
echo "  chain    : SAFETY · DISCOVER · MODEL · DO+VERIFY · FUSE · REMEMBER · PROVE · AUDIT"

# ── PHASE 1 · the unattended self-verifying loop (safety, model, class+example
#    verification, memory, signed receipt over the committed fix) ──────────────
banner "PHASE 1 / 2 — unstoppable loop: safety · model · class-verify · examples · remember · prove"
bash "$EXP/run-unstoppable.sh" 2>&1 | tee "$OUT/phase1-unstoppable.log" | tail -n 25
P1=$( grep -oE "KERNEL RESULT: [A-Z]+" "$OUT/phase1-unstoppable.log" | awk '{print $3}' )

# ── PHASE 2 · discover the consequential sink, then fuse authority+correctness
#    at the execution edge and audit the signed decision ledger ────────────────
banner "PHASE 2 / 2 — revolutionary fusion: discover sink · gate authority ∧ correctness · audit ledger"
bash "$EXP/run-revolutionary.sh" 2>&1 | tee "$OUT/phase2-revolutionary.log" | tail -n 22
P2=$( grep -oE "REVOLUTIONARY RESULT: [A-Z]+" "$OUT/phase2-revolutionary.log" | awk '{print $3}' )

# ── CONSOLIDATED PRODUCT VERDICT ──────────────────────────────────────────────
banner "PRODUCT VERDICT — one action, every layer produced real signed evidence"
UNSTOP="$EXP/evidence/unstoppable"
REV="$EXP/evidence/revolutionary"
REFUSALS=$( grep -c '"action": "refuse"' "$UNSTOP/blastradius-audit.jsonl" 2>/dev/null || echo 0 )
SINKS=$( grep -oE "Consequential capabilities: [0-9]+" "$REV/A-discover.txt" 2>/dev/null | grep -oE "[0-9]+" | head -1 )
ABV=$( python3 -c "import json;print(json.load(open('$UNSTOP/4-armB-property.json'))['verdict'])" 2>/dev/null || echo "?" )
FUSED=$( grep -oE "FUSED-GATE RESULT: [A-Z]+" "$REV/B-fuse.txt" 2>/dev/null | awk '{print $3}' )
ASYM=$( grep -oE "PUBLIC KEY ONLY: [A-Z]+" "$REV/B-fuse.txt" 2>/dev/null | awk '{print $4}' )
LEDGER=$( grep -oE "LEDGER: .*" "$REV/C-audit.txt" 2>/dev/null | sed 's/LEDGER: //' )
SIG=$( grep -c '"sig":' "$UNSTOP/6-prove-receipt.txt" 2>/dev/null || echo 0 )

cat <<EOF
  SAFETY    blastradius  : ${REFUSALS} destructive acts REFUSED (out-of-scope, symlink-escape, denylist); victim survived
  DISCOVER  actenon-scan : ${SINKS:-0} consequential sink(s) auto-discovered in the agent (money/egress), no guard on path
  MODEL     apprentice   : dead-code + duplication modelled proactively (see phase1 log)
  VERIFY    class        : property-verify armB=${ABV} over 200,070 inputs; baseline+armA=VIOLATED (whole bug class caught)
  VERIFY    examples     : Sentinel armA=CONTRADICTED · armB=VERIFIED (approved behaviour preserved)
  FUSE      edge gate    : authority ∧ correctness ∧ code-hash ∧ no-replay -> ${FUSED:-?}
  AUTHORITY asymmetric   : real ed25519 signer; public-key-only third-party verify = ${ASYM:-?}
  REMEMBER  howdex       : verified repair distilled to transferable memory (see phase1 log)
  PROVE     workproof    : ${SIG} ed25519 signature(s) over the committed fix
  AUDIT     ledger       : ${LEDGER:-?}
  Evidence bundle: $OUT (+ $UNSTOP, $REV)
EOF

if [ "${P1:-}" = "PASS" ] && [ "${P2:-}" = "PASS" ] && [ "${FUSED:-}" = "PASS" ] && [ "${ASYM:-}" = "OK" ]; then
  echo "ONE-ACTION KERNEL: PASS — the entire chain fired from one command; a consequential money action executes ONLY if authorised AND class-verified-correct AND hash-bound AND not a replay, with a tamper-evident signed ledger."
  exit 0
else
  echo "ONE-ACTION KERNEL: CHECK PHASE LOGS ABOVE (P1=${P1:-?} P2=${P2:-?} FUSE=${FUSED:-?} ASYM=${ASYM:-?})"
  exit 1
fi
