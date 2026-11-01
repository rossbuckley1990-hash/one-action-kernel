#!/usr/bin/env bash
# ============================================================================
#  ONE ACTION — fire the entire self-verifying agent loop, emit consolidated evidence.
#
#  Layers:  Model (apprentice) · Verify (Sentinel) · Remember (Howdex) · Prove (workproof)
#           + Do/Provenance anchor (RightClick X, live MCP — bracketed out-of-band)
#
#  Target problem: unverified AI-agent output. A plausible fix passes every
#  ordinary test yet silently creates/destroys money in settlement allocation.
# ============================================================================
set -uo pipefail

LAB=/Users/ross/Documents/Qoder/2026-11-01/d649cff7/agent-lab
EXP=$LAB/experiment
SENT=$LAB/sentinel-verified/dist/cli.js
APP=$LAB/.venvs/apprentice/bin/apprentice
HOWPY=$LAB/.venvs/howdex/bin/python
WP=$LAB/.venvs/workproof/bin/workproof
CONTRACT=$EXP/settlement-contract.json

RUN=$EXP/.run
OUT=$EXP/evidence/loop-run
rm -rf "$RUN" "$OUT"; mkdir -p "$RUN" "$OUT"
T=$RUN/target; mkdir -p "$T/src"
STORE=$RUN/.sentinel-store

say() { printf '\n\033[1m===== %s =====\033[0m\n' "$1"; }

# ---- build a pristine settlement target at the buggy baseline --------------
cp "$EXP/candidates/baseline-buggy.ts"            "$T/src/settle.ts"
cp "$EXP/target-settlement/src/settle.test.ts"    "$T/src/settle.test.ts"
printf '{"name":"target-settlement","private":true,"type":"module","scripts":{"test":"vitest run"}}\n' > "$T/package.json"
printf 'node_modules\n.apprentice/\n.workproof/\n.workproof.yml\n' > "$T/.gitignore"
ln -sfn "$LAB/sentinel-verified/node_modules" "$T/node_modules"
( cd "$T" && git init -q && git config user.email loop@experiment.local && git config user.name "Loop" \
  && git add -A && git commit -qm "baseline: settlement allocation (floor split)" )
BASE=$( cd "$T" && git rev-parse --short HEAD )
echo "pristine target baseline = $BASE (buggy floor split)"

# ---- STAGE 1 · MODEL (apprentice) -----------------------------------------
say "STAGE 1 · MODEL — apprentice indexes the Python settlement domain"
( cd "$EXP/target-py" && $APP index </dev/null 2>&1 | grep -E "Files indexed|Functions found|Dead functions|Cliché groups" ) \
  | tee "$OUT/1-model.txt"

# ---- STAGE 2 · VERIFY Arm A (lone agent ships plausible rounding fix) ------
say "STAGE 2 · VERIFY Arm A — plausible Math.round fix; ordinary tests stay green"
cp "$EXP/candidates/arm-a-rounding.ts" "$T/src/settle.ts"
( cd "$T" && node_modules/.bin/vitest run 2>&1 | grep -E "Tests|Test Files" ) | tee "$OUT/2a-armA-tests.txt"
( cd "$T" && node_modules/.bin/tsx "$EXP/tools/quant.mjs" "$T/src/settle.ts" ) | tee "$OUT/2a-armA-quant.txt"
( cd "$T" && node "$SENT" verify --repo "$T" --baseline HEAD --contract "$CONTRACT" --allow-local --store "$STORE" \
    > "$OUT/2a-armA-sentinel.txt" 2>&1 ); ARMA=$?
echo "sentinel exit=$ARMA (expect 1 = CONTRADICTED)"; grep -E "CONTRADICTED|VERIFIED|REVIEW" "$OUT/2a-armA-sentinel.txt" | grep -iE "·|conservation|over-allocate" | head -3

# ---- STAGE 3 · VERIFY Arm B (correct largest-remainder fix) ----------------
say "STAGE 3 · VERIFY Arm B — largest-remainder fix; independent verification"
cp "$EXP/candidates/arm-b-correct.ts" "$T/src/settle.ts"
( cd "$T" && node_modules/.bin/vitest run 2>&1 | grep -E "Tests|Test Files" ) | tee "$OUT/3-armB-tests.txt"
( cd "$T" && node_modules/.bin/tsx "$EXP/tools/quant.mjs" "$T/src/settle.ts" ) | tee "$OUT/3-armB-quant.txt"
( cd "$T" && node "$SENT" verify --repo "$T" --baseline HEAD --contract "$CONTRACT" --allow-local --store "$STORE" \
    > "$OUT/3-armB-sentinel.txt" 2>&1 ); ARMB=$?
echo "sentinel exit=$ARMB (expect 0 = VERIFIED)"
ARMB_HASH=$( grep -oE "reports/[a-f0-9]{64}\.html" "$OUT/3-armB-sentinel.txt" | head -1 | sed -E 's#reports/([a-f0-9]{64})\.html#\1#' )
echo "sentinel VERIFIED receipt = ${ARMB_HASH:-<none>}"

# ---- commit the verified fix ----------------------------------------------
( cd "$T" && git add src/settle.ts && git commit -qm "fix(settle): largest-remainder allocation conserves total exactly" )
FIX=$( cd "$T" && git rev-parse --short HEAD )

# ---- STAGE 4 · REMEMBER (Howdex) ------------------------------------------
say "STAGE 4 · REMEMBER — Howdex distils the repair into reusable, receipt-backed memory"
$HOWPY "$EXP/tools/howdex_loop.py" 2>&1 | tee "$OUT/4-remember.txt"

# ---- STAGE 5 · PROVE (workproof) ------------------------------------------
say "STAGE 5 · PROVE — workproof signs a deterministic in-toto receipt over the committed fix"
( cd "$T" && $WP init </dev/null >/dev/null 2>&1
  $WP run --capture -- node_modules/.bin/vitest run >/dev/null 2>&1; echo "  evidence vitest exit=$?"
  $WP run --capture -- node_modules/.bin/tsx "$EXP/tools/quant.mjs" "$T/src/settle.ts" >/dev/null 2>&1; echo "  evidence quant exit=$?"
  $WP attest --ai-level agent --agent qoder --base "$BASE" --head "$FIX" --emit pr-body > "$OUT/5-prove-receipt.txt" 2>&1; echo "  attest exit=$?" )
PUBKEY=$( grep -oE '"public_key": "[^"]+"' "$OUT/5-prove-receipt.txt" | head -1 )
SIGOK=$( grep -c '"sig":' "$OUT/5-prove-receipt.txt" )
echo "  $PUBKEY ; signatures=$SIGOK"

# ---- CONSOLIDATED SUMMARY --------------------------------------------------
say "SUMMARY — one action, five layers, real evidence"
LEAK_A=$( grep -oE '"pennies_vanished":[0-9]+' "$OUT/2a-armA-quant.txt" | grep -oE '[0-9]+' )
CRE_A=$( grep -oE '"pennies_created":[0-9]+' "$OUT/2a-armA-quant.txt" | grep -oE '[0-9]+' )
LEAK_B=$( grep -oE '"pennies_vanished":[0-9]+' "$OUT/3-armB-quant.txt" | grep -oE '[0-9]+' )
cat <<EOF
  MODEL     apprentice         : $( grep -E 'Dead functions' "$OUT/1-model.txt" | tr -s ' ' ) / $( grep -E 'Cliché groups' "$OUT/1-model.txt" | tr -s ' ' )
  VERIFY A  sentinel (rounding): exit=$ARMA  → pennies_vanished=$LEAK_A  pennies_created=$CRE_A   (ordinary tests: GREEN = false success)
  VERIFY B  sentinel (correct) : exit=$ARMB  → pennies_vanished=$LEAK_B   receipt=${ARMB_HASH:0:16}…
  REMEMBER  howdex             : $( grep 'PROCEDURES_DISTILLED' "$OUT/4-remember.txt" ) / $( grep 'FRESH_RECALL_HITS' "$OUT/4-remember.txt" ) / source_pasted=$( grep -oE 'SOURCE_PASTED_IN_RECALL: .*' "$OUT/4-remember.txt" | awk '{print $2}' )
  PROVE     workproof          : attest ok, ed25519 signatures=$SIGOK, base=$BASE head=$FIX
  Evidence bundle: $OUT
EOF
[ "$ARMA" = "1" ] && [ "$ARMB" = "0" ] && [ "${LEAK_B:-1}" = "0" ] && echo "LOOP RESULT: PASS — false success caught, correct fix verified, remembered, and signed." || echo "LOOP RESULT: CHECK STAGES ABOVE"
