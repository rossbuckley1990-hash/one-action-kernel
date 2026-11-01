# one-action-kernel

**The entire `Do → Model → Verify → Remember → Prove` chain fires from a single command — and a consequential AI action executes only if it is *authorised* AND *functionally correct*, proved by two independent signatures.**

This is a working, evidence-producing answer to a multi-billion-pound problem: **AI agents that take consequential actions which are unauthorised, double-executed, or functionally wrong — and report success anyway.** Ordinary tests stay green on broken money-math; a lone agent's "done" is not evidence. This kernel makes "false success" refuse-to-execute.

```
./run.sh
```

One action. Real signed evidence at the end.

---

## The problem

An agent allocates a settlement of 1,000,000 pence across 3 parties. A plausible `Math.round` fix passes **every unit test green** — and silently *creates money* on uneven splits (`[1,2] → [1,1]`: 2 pence out for 1 penny in). Multiply by every agent touching payments, ledgers, deletes, deploys and access changes, and you get the unverified-agent-output problem. The damage is not the bug; it is that **nothing independent caught it before the side effect, and the agent reported success.**

## The product: one action, two independent authorities

```
SAFETY ─► DISCOVER ─► MODEL ─► DO+VERIFY ─► FUSE ─► REMEMBER ─► PROVE ─► AUDIT
```

| Stage | Tool | What it proves |
|---|---|---|
| **SAFETY** | `blastradius` | Destructive shell acts outside declared scope are refused (out-of-scope, symlink-escape, `rm -rf /`); a victim file survives. |
| **DISCOVER** | `actenon-scan` | Auto-finds where model-controlled input reaches a consequential sink (money/egress/delete) with no guard — the gate target is *discovered*, not hand-authored. |
| **MODEL** | `apprentice` | Models the codebase proactively (dead code, duplication). |
| **DO+VERIFY** | `property-verify` + `Sentinel` | **Class truth**: relational invariants over 200,070 inputs with delta-debugging shrink. **Example truth**: approved behaviour preserved. |
| **FUSE** | `correctness_gate.py` + `actenon-kernel` | The edge gate: a consequential action fires **only if** the Actenon authority proof verifies **AND** a signed correctness certificate verifies **AND** the code hash matches **AND** it is not a replay. |
| **REMEMBER** | `Howdex` | Distils the verified repair into transferable procedural memory a fresh agent inherits (no source leak). |
| **PROVE** | `workproof` | Signs a deterministic ed25519 in-toto receipt over the committed fix. |
| **AUDIT** | ed25519 / RFC 8785 | Every gate decision is a signed, offline-verifiable, tamper-evident receipt. |

### The novel piece: correctness bound *into* the authority proof

Actenon answers **"is this action authorised?"** It deliberately never checks functional correctness. `property-verify` + `Sentinel` answer **"is this output correct?"** This kernel **fuses** them:

1. The correctness prover (an **independent ed25519 key**, separate from the authority signer) signs a certificate over the *exact code artifact* (file hash + git head) asserting `property=VERIFIED ∧ sentinel=VERIFIED`.
2. That certificate's digest is embedded in the Actenon PCCB's **signature-covered `extensions.correctness`** at mint time — so the authority proof *cryptographically commits* to the correctness verdict.
3. At the execution edge the gate re-verifies **both** signatures independently, recomputes the **actual** code's hash, and checks the **single-use nonce**.

Rule enforced: **no valid proof AND no valid correctness certificate → no execution.**

### Proven behaviour (live, in `evidence/`)

| Scenario | Decision | Why |
|---|---|---|
| Wrong fix, **green tests**, **valid authority** | **REFUSE** `CORRECTNESS/NOT_VERIFIED` | The proof verified; the certificate didn't. Authority alone is not enough. |
| Correct fix | **ALLOW** → side effect executed | Both authorities signed off; code hash matched. |
| Certificate for B, code swapped to A | **REFUSE** `CODE_ARTIFACT_MISMATCH` | You cannot certify one artifact and run another. |
| Blind retry of a dispatched action | **REFUSE** `NONCE_REUSED` | No double-spend on an uncertain outcome. |

The authority signer is a **real ed25519 keypair** (not Actenon's public HMAC dev secret, which "proves nothing"). A third party verifies every proof with **only the published public JWK** (`well-known-actenon-keys.json`) — the asymmetric property a symmetric dev secret can never offer.

---

## Running it

The kernel composes sibling tool repos and Python venvs. From a checkout placed inside an `agent-lab/` that contains them:

```bash
./setup.sh          # clones sibling repos + builds venvs + npm install (idempotent)
./run.sh            # fires the whole chain; writes evidence/product/
```

`LAB` defaults to the parent of this directory; override with `LAB=/path/to/lab ./run.sh`.

### Dependencies (sibling repos under the same account)

`blastradius` · `sentinel-verified` · `Howdex` · `apprentice` · `workproof`, plus the [Actenon](https://github.com/Actenon) ecosystem (`actenon-scan`, `actenon-kernel`, `actenon-protocol`, `actenon-permit`) installed from PyPI/git into `.venvs/`. `setup.sh` wires them.

### Layout

```
run.sh                     # the one-action product entrypoint
run-unstoppable.sh         # phase 1: safety·model·class-verify·examples·remember·prove
run-revolutionary.sh       # phase 2: discover·fuse·audit
tools/
  correctness_gate.py      # the fusion: independent ed25519 correctness prover + edge gate
  property-verify.mjs      # relational-invariant class verifier with shrinking
  quant.mjs, howdex_loop.py
candidates/                # baseline-buggy · arm-a-rounding (wrong, green) · arm-b-correct
target-settlement/         # the TS settlement domain under test
target-settlement-agent/   # the agent tool surface actenon-scan discovers
property-contract.json, settlement-contract.json
evidence/                  # real signed output of every stage
```

---

## Honest limits

- **Cooperative containment, not a hard sandbox.** The gate is an edge call you install on the protected path. A rogue agent that refuses to call it is not stopped by it. True unbypassable isolation needs the container/egress layer (Actenon airlock Protected Mode + Docker), deliberately excluded here.
- **Local asymmetric signer.** Real ed25519, private key never published — but single-host. Production multi-host custody belongs in KMS/HSM with the public key served at `/.well-known/actenon/keys.json` (the signer interface supports it; not wired here).
- **Correctness = what you can state.** The certificate is only as strong as the property invariants + Sentinel contract. It is not general correctness.
- **Pre-release Actenon pins.** The fusion runs against candidate Actenon releases (`kernel 1.3.0`, `permit 2.0.0rc1`, `protocol 1.6.0`).
- **Discovery has published blind spots.** `actenon-scan` covers Python/TS/Go and reports unsupported languages rather than treating them as clean; silence never implies safety.
- **The protected resource is a fixture.** The disbursement is a local signed record, not a live ledger POST. The gate logic is real; the endpoint is a stand-in.

This is a demonstrated, working architecture that makes unverified consequential agent output refuse-to-execute — not a claim to have single-handedly solved an industry-scale economic problem.

## License

Apache-2.0 (consistent with the Actenon ecosystem it builds on).
