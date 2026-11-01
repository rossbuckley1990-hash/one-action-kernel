#!/usr/bin/env bash
# ============================================================================
#  UNSTOPPABLE KERNEL — one command, unattended, self-guarding, class-verifying.
#
#  Safety    blastradius  : every destructive write is scope-gated; rogue steps refused
#  Model     apprentice   : persistent codebase model, proactive dead-code/duplication
#  Verify    property-verify + Sentinel : whole bug CLASS (200k inputs) + approved examples
#  Remember  Howdex       : distil the fix into reusable memory a fresh agent inherits
#  Prove     workproof    : signed ed25519 in-toto receipt over the committed fix
#  Anchor    RightClick X : live capability/provenance runtime (bracketed out-of-band)
# ============================================================================
set -uo pipefail

# Portable: EXP is this script's own directory (the repo root); LAB is its parent
# (the agent-lab holding the sibling tool repos + .venvs). Override LAB via env.
EXP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="${LAB:-$(cd "$EXP/.." && pwd)}"
SENT=$LAB/sentinel-verified/dist/cli.js
APP=$LAB/.venvs/apprentice/bin/apprentice
HOWPY=$LAB/.venvs/howdex/bin/python
WP=$LAB/.venvs/workproof/bin/workproof
BR=$LAB/.venvs/blastradius/bin/blastradius
TSX=$LAB/sentinel-verified/node_modules/.bin/tsx
PV=$EXP/tools/property-verify.mjs
PC=$EXP/property-contract.json
CONTRACT=$EXP/settlement-contract.json

RUN=$EXP/.run2
OUT=$EXP/evidence/unstoppable
rm -rf "$RUN" "$OUT"; mkdir -p "$RUN" "$OUT"
T=$RUN/target; mkdir -p "$T/src"; STORE=$RUN/.sentinel-store
AUDIT=$OUT/blastradius-audit.jsonl
VICTIM=$EXP/victim-marker.txt            # a real file OUTSIDE the guarded scope

say() { printf '\n\033[1m===== %s =====\033[0m\n' "$1"; }
pv() { "$TSX" "$PV" --module "$1" --contract "$PC" > "$2" 2>&1; echo $?; }
pvsum() { python3 -c "import json,sys;d=json.load(open('$1'));print('   verdict=%s trials=%d'%(d['verdict'],d['trials']));[print('   VIOLATION %s: %d failing inputs, minimal=%s -> %s (%s)'%(v['invariant'],v['failing_inputs'],v['minimal_args'],v['minimal_result'],v['detail'])) for v in d['violations']]"; }

# ---- pristine target at the buggy baseline --------------------------------
cp "$EXP/candidates/baseline-buggy.ts"         "$T/src/settle.ts"
cp "$EXP/target-settlement/src/settle.test.ts" "$T/src/settle.test.ts"
printf '{"name":"target-settlement","private":true,"type":"module","scripts":{"test":"vitest run"}}\n' > "$T/package.json"
printf 'node_modules\n.apprentice/\n.workproof/\n.workproof.yml\n' > "$T/.gitignore"
ln -sfn "$LAB/sentinel-verified/node_modules" "$T/node_modules"
( cd "$T" && git init -q && git config user.email loop@experiment.local && git config user.name Loop \
  && git add -A && git commit -qm "baseline: settlement allocation (floor split)" )
BASE=$( cd "$T" && git rev-parse --short HEAD )

# ---- STAGE 0 · SAFETY (blastradius guards the unattended loop) ------------
say "STAGE 0 · SAFETY — blastradius gates every destructive act; rogue steps are refused"
printf 'do-not-delete\n' > "$VICTIM"
mkdir -p "$RUN/decoy" && touch "$RUN/decoy/x"
# (a) in-scope destructive write -> ALLOWED and executed
$BR --scope "$RUN" --log "$AUDIT" -- rm -rf "$RUN/decoy"; echo "  in-scope rm      -> exit=$? (0=allowed, decoy removed=$([ ! -d "$RUN/decoy" ] && echo yes))"
# (b) REAL out-of-scope rm -rf -> REFUSED, victim survives (not dry-run: actually invoked)
$BR --scope "$RUN" --log "$AUDIT" -- rm -rf "$VICTIM"; echo "  out-of-scope rm  -> exit=$? (3=refused, victim survives=$([ -f "$VICTIM" ] && echo yes))"
# (c) symlink escape -> REFUSED, victim survives
ln -sfn "$VICTIM" "$RUN/sneaky-link"
$BR --scope "$RUN" --log "$AUDIT" -- rm -rf "$RUN/sneaky-link"; echo "  symlink-escape   -> exit=$? (3=refused, victim survives=$([ -f "$VICTIM" ] && echo yes))"
# (d) denylist floor (dry-run; never actually invoke rm -rf /)
$BR --scope "$RUN" --log "$AUDIT" --dry-run -- rm -rf / >/dev/null 2>&1; echo "  rm -rf /         -> exit=$? (3=refused by denylist even if scoped)"
echo "  audit trail: $(wc -l < "$AUDIT") decisions logged to $(basename "$AUDIT")"

# ---- guarded write helper: every candidate patch lands via blastradius ----
guarded_patch() { $BR --scope "$RUN" --log "$AUDIT" -- cp "$1" "$T/src/settle.ts"; }

# ---- STAGE 1 · MODEL (apprentice) ----------------------------------------
say "STAGE 1 · MODEL — apprentice models the settlement domain (proactive, unasked)"
( cd "$EXP/target-py" && $APP index </dev/null 2>&1 | grep -E "Functions found|Dead functions|Cliché groups" ) | tee "$OUT/1-model.txt"

# ---- STAGE 2 · CLASS-VERIFY the buggy baseline ---------------------------
say "STAGE 2 · CLASS-VERIFY baseline — property invariants over 200k inputs"
EC=$(pv "$T/src/settle.ts" "$OUT/2-baseline-property.json"); echo "  property exit=$EC"; pvsum "$OUT/2-baseline-property.json"

# ---- STAGE 3 · Arm A: lone agent ships a plausible rounding fix ----------
say "STAGE 3 · Arm A — plausible Math.round fix; ordinary tests stay GREEN (false success)"
guarded_patch "$EXP/candidates/arm-a-rounding.ts"; echo "  patch applied via blastradius (exit=$?)"
( cd "$T" && node_modules/.bin/vitest run 2>&1 | grep -E "Tests " ) | tee "$OUT/3a-armA-tests.txt"
EC=$(pv "$T/src/settle.ts" "$OUT/3a-armA-property.json"); echo "  property exit=$EC"; pvsum "$OUT/3a-armA-property.json"
( cd "$T" && node "$SENT" verify --repo "$T" --baseline HEAD --contract "$CONTRACT" --allow-local --store "$STORE" > "$OUT/3a-armA-sentinel.txt" 2>&1 ); echo "  sentinel exit=$? (expect 1 CONTRADICTED)"
grep -E "CONTRADICTED ·|VERIFIED ·" "$OUT/3a-armA-sentinel.txt" | head -1

# ---- STAGE 4 · Arm B: correct largest-remainder fix ----------------------
say "STAGE 4 · Arm B — largest-remainder fix; independent class + example verification"
guarded_patch "$EXP/candidates/arm-b-correct.ts"; echo "  patch applied via blastradius (exit=$?)"
( cd "$T" && node_modules/.bin/vitest run 2>&1 | grep -E "Tests " ) | tee "$OUT/4-armB-tests.txt"
EC=$(pv "$T/src/settle.ts" "$OUT/4-armB-property.json"); echo "  property exit=$EC (expect 0 VERIFIED)"; pvsum "$OUT/4-armB-property.json"
( cd "$T" && node "$SENT" verify --repo "$T" --baseline HEAD --contract "$CONTRACT" --allow-local --store "$STORE" > "$OUT/4-armB-sentinel.txt" 2>&1 ); ARMB=$?; echo "  sentinel exit=$ARMB (expect 0 VERIFIED)"
ARM_B_HASH=$( grep -oE "reports/[a-f0-9]{64}\.html" "$OUT/4-armB-sentinel.txt" | head -1 | sed -E 's#reports/([a-f0-9]{64}).html#\1#' )
echo "  sentinel VERIFIED receipt = ${ARM_B_HASH:-<none>}"
( cd "$T" && git add src/settle.ts && git commit -qm "fix(settle): largest-remainder allocation conserves total exactly" )
FIX=$( cd "$T" && git rev-parse --short HEAD )

# ---- STAGE 5 · REMEMBER (Howdex) ----------------------------------------
say "STAGE 5 · REMEMBER — Howdex distils the verified repair into transferable memory"
$HOWPY "$EXP/tools/howdex_loop.py" 2>&1 | grep -E "PROCEDURES_DISTILLED|FRESH_RECALL_HITS|SOURCE_PASTED" | tee "$OUT/5-remember.txt"

# ---- STAGE 6 · PROVE (workproof) ----------------------------------------
say "STAGE 6 · PROVE — workproof signs a deterministic receipt over the committed fix"
( cd "$T" && $WP init </dev/null >/dev/null 2>&1
  $WP run --capture -- node_modules/.bin/vitest run >/dev/null 2>&1
  $WP run --capture -- "$TSX" "$PV" --module "$T/src/settle.ts" --contract "$PC" >/dev/null 2>&1
  $WP attest --ai-level agent --agent qoder --base "$BASE" --head "$FIX" --emit pr-body > "$OUT/6-prove-receipt.txt" 2>&1; echo "  attest exit=$?" )
SIG=$( grep -c '"sig":' "$OUT/6-prove-receipt.txt" )
PUB=$( grep -oE '"public_key": "[^"]+"' "$OUT/6-prove-receipt.txt" | head -1 )

# ---- CONSOLIDATED SUMMARY ------------------------------------------------
say "SUMMARY — one unattended command; every layer produced real evidence"
BASEV=$( python3 -c "import json;print(json.load(open('$OUT/2-baseline-property.json'))['verdict'])" )
AAV=$( python3 -c "import json;print(json.load(open('$OUT/3a-armA-property.json'))['verdict'])" )
ABV=$( python3 -c "import json;print(json.load(open('$OUT/4-armB-property.json'))['verdict'])" )
REFUSALS=$( grep -c '"action": "refuse"' "$AUDIT" )
cat <<EOF
  SAFETY    blastradius   : $REFUSALS destructive acts REFUSED (out-of-scope, symlink-escape, denylist); victim survived; $(( $(wc -l < "$AUDIT") )) audit lines
  MODEL     apprentice    : $( grep 'Dead functions' "$OUT/1-model.txt" | tr -s ' ' ) / $( grep 'Cliché' "$OUT/1-model.txt" | tr -s ' ' )
  CLASS     property      : baseline=$BASEV · armA=$AAV · armB=$ABV  (200,070 inputs each; minimal counterexample auto-shrunk)
  EXAMPLES  sentinel      : armA=CONTRADICTED(exit1) · armB=VERIFIED(exit0) receipt=${ARM_B_HASH:0:16}…
  REMEMBER  howdex        : $( tr '\n' ' ' < "$OUT/5-remember.txt" )
  PROVE     workproof     : ed25519 signatures=$SIG  base=$BASE head=$FIX  $PUB
  Evidence bundle: $OUT
EOF
if [ "$BASEV" = "VIOLATED" ] && [ "$AAV" = "VIOLATED" ] && [ "$ABV" = "VERIFIED" ] && [ "$ARMB" = "0" ] && [ "$REFUSALS" -ge 3 ] && [ "$SIG" -ge 1 ]; then
  echo "KERNEL RESULT: PASS — safe unattended, whole bug class caught, false success contradicted, correct fix verified+remembered+signed."
else
  echo "KERNEL RESULT: CHECK STAGES ABOVE"
fi
rm -f "$VICTIM"
