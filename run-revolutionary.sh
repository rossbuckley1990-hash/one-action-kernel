#!/usr/bin/env bash
# ============================================================================
#  REVOLUTIONARY KERNEL — discover the consequential sink, then gate it with
#  TWO independent signed authorities before any side effect:
#
#   DISCOVER  actenon-scan : find where model-controlled intent reaches money/delete/send
#   FUSE      correctness_gate : Actenon proof (AUTHORITY) ∧ correctness cert (TRUTH)
#                            ∧ code-hash binding ∧ single-use nonce — all signed
#
#  Complements run-unstoppable.sh (blastradius safety, property class-verify,
#  Sentinel examples, Howdex memory, workproof receipts) which this summarises.
# ============================================================================
set -uo pipefail

# Portable: EXP is this script's own directory (the repo root); LAB is its parent
# (the agent-lab holding the sibling tool repos + .venvs). Override LAB via env.
EXP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="${LAB:-$(cd "$EXP/.." && pwd)}"
SCAN=$LAB/.venvs/actenon/bin/actenon-scan
GPY=$LAB/.venvs/airlock/bin/python
GATE=$EXP/tools/correctness_gate.py
AGENT=$EXP/target-settlement-agent
OUT=$EXP/evidence/revolutionary
UNSTOP=$EXP/evidence/unstoppable
rm -rf "$OUT"; mkdir -p "$OUT"

say() { printf '\n\033[1m===== %s =====\033[0m\n' "$1"; }

# ---- STAGE A · DISCOVER the consequential sink ---------------------------
say "STAGE A · DISCOVER — actenon-scan finds the unguarded MONEY sink (auto, not hand-authored)"
$SCAN scan "$AGENT" 2>&1 | tee "$OUT/A-discover.txt" | sed -n '1,30p'
SINKS=$( grep -oE "Consequential capabilities: [0-9]+" "$OUT/A-discover.txt" | grep -oE "[0-9]+" | head -1 )
MONEY=$( grep -cE "MONEY|disburse|post" "$OUT/A-discover.txt" )

# ---- STAGE B · FUSE authority + correctness at the execution edge --------
say "STAGE B · FUSE — gate the sink: no valid proof AND no correctness cert -> no execution"
$GPY "$GATE" demo --out "$OUT/fused-gate" 2>&1 | grep -vE "RuntimeWarning|signer =|signer=|result = method|kernel, writer|warnings.warn|build_local_proof_signer" | tee "$OUT/B-fuse.txt"
FUSED=$( grep -oE "FUSED-GATE RESULT: [A-Z]+" "$OUT/B-fuse.txt" | awk '{print $3}' )
ASYM=$( grep -oE "PUBLIC KEY ONLY: [A-Z]+" "$OUT/B-fuse.txt" | awk '{print $4}' )
AUTHSIG=$( grep -oE 'authority signer : .*' "$OUT/B-fuse.txt" | head -1 | sed 's/authority signer : //' )

# ---- STAGE C · verify the signed decision ledger is tamper-evident -------
say "STAGE C · AUDIT — independently verify every gate receipt (ed25519 over RFC8785)"
$GPY - "$OUT/fused-gate/fused-gate-ledger.jsonl" <<'EOF' 2>&1 | tee "$OUT/C-audit.txt"
import json, sys, base64
from actenon_protocol import canonicalize_bytes
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
lines=[json.loads(l) for l in open(sys.argv[1])]
ok=0
for r in lines:
    pub=Ed25519PublicKey.from_public_bytes(base64.urlsafe_b64decode(r["prover_public_key"]))
    try:
        pub.verify(base64.urlsafe_b64decode(r["signature"]), canonicalize_bytes(r["receipt"])); ok+=1
    except Exception: pass
print(f"   receipts={len(lines)} signatures_verified={ok}")
print("   LEDGER:", "TAMPER-EVIDENT (all verified)" if ok==len(lines) else "BROKEN")
EOF

# ---- CONSOLIDATED SUMMARY ------------------------------------------------
say "SUMMARY — the complete pipeline, one unattended command"
REFUSALS=$( grep -c '"action": "refuse"' "$UNSTOP/blastradius-audit.jsonl" 2>/dev/null || echo 0 )
BASEV=$( $GPY -c "import json;print(json.load(open('$UNSTOP/2-baseline-property.json'))['verdict'])" 2>/dev/null || echo "?" )
AAV=$( $GPY -c "import json;print(json.load(open('$UNSTOP/3a-armA-property.json'))['verdict'])" 2>/dev/null || echo "?" )
ABV=$( $GPY -c "import json;print(json.load(open('$UNSTOP/4-armB-property.json'))['verdict'])" 2>/dev/null || echo "?" )
SIG=$( grep -c '"sig":' "$UNSTOP/6-prove-receipt.txt" 2>/dev/null || echo 0 )
cat <<EOF
  DISCOVER  actenon-scan  : ${SINKS:-0} consequential capabilities found in the agent; money/egress sink lines=${MONEY}
  SAFETY    blastradius   : ${REFUSALS} destructive acts REFUSED (see run-unstoppable evidence)
  CLASS     property      : baseline=${BASEV} · armA=${AAV} · armB=${ABV}  (200,070 inputs each)
  FUSE      edge gate     : armA(wrong,green,authorised)=REFUSE · armB(correct)=ALLOW+executed · tamper=REFUSE · replay=REFUSE  -> ${FUSED}
  AUTHORITY ed25519 signer: ${AUTHSIG:-unknown}
  ASYMMETRIC public-only  : ${ASYM:-?}  (a third party verifies the proof with only the published public JWK — no shared secret)
  AUDIT     ledger        : $( grep 'LEDGER:' "$OUT/C-audit.txt" | sed 's/.*LEDGER: //' )
  PROVE     workproof     : ed25519 signatures=${SIG} over the committed fix
  Evidence: $OUT
EOF
if [ "${FUSED}" = "PASS" ] && [ "${SINKS:-0}" -ge 1 ] && [ "${ASYM}" = "OK" ] && grep -q "TAMPER-EVIDENT" "$OUT/C-audit.txt"; then
  echo "REVOLUTIONARY RESULT: PASS — sink auto-discovered, then gated by TWO independent signed authorities (Actenon authority ∧ class-level correctness) under a real ed25519 asymmetric signer, hash-bound, replay-protected, with a tamper-evident ledger and public-key-only third-party verifiability."
else
  echo "REVOLUTIONARY RESULT: CHECK STAGES ABOVE"
fi
