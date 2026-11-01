#!/usr/bin/env python3
"""Correctness-fused execution-edge gate.

Fuses two INDEPENDENT authorities that must both hold before a consequential
action is allowed to cause a side effect:

  1. Actenon proof (AUTHORITY). A PCCB verified by actenon-kernel's VerifierSDK:
     signature, audience binding, time window, action-hash, single-use nonce.
     Actenon answers "is this action authorised and exactly the one approved?"

  2. Correctness certificate (FUNCTIONAL TRUTH). Signed by an independent
     ed25519 prover key, produced from property-verify (whole bug class, 200k
     inputs) + Sentinel (approved examples). Bound into the PCCB's
     signature-covered ``extensions.correctness`` at mint time, then independently
     re-verified at the edge. Answers "is the code that will run actually correct?"

Rule enforced: NO valid proof AND NO valid correctness certificate -> NO execution.

The two authorities are deliberately separate: Actenon never checks functional
correctness; the correctness prover never grants authority. An action proceeds
only if BOTH independently sign off, and the exact certified code artifact is
what runs (hash-bound), and it is not a replay (nonce-bound).
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

from actenon_protocol import canonicalize_bytes

# --------------------------------------------------------------------------- #
# Independent correctness prover (ed25519, separate from Actenon's signer)
# --------------------------------------------------------------------------- #


def _b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode()


def _b64d(s: str) -> bytes:
    return base64.urlsafe_b64decode(s.encode())


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class CorrectnessProver:
    """Holds an ed25519 keypair independent of the Actenon proof signer."""

    def __init__(self, priv: Ed25519PrivateKey, key_id: str = "correctness-prover-v1"):
        self._priv = priv
        self.key_id = key_id
        self.public_key_b64 = _b64e(
            priv.public_key().public_bytes(
                serialization.Encoding.Raw, serialization.PublicFormat.Raw
            )
        )

    @classmethod
    def generate(cls) -> "CorrectnessProver":
        return cls(Ed25519PrivateKey.generate())

    def sign(self, body: dict[str, Any]) -> str:
        return _b64e(self._priv.sign(canonicalize_bytes(body)))

    @staticmethod
    def verify(public_key_b64: str, body: dict[str, Any], signature_b64: str) -> bool:
        try:
            pub = Ed25519PublicKey.from_public_bytes(_b64d(public_key_b64))
            pub.verify(_b64d(signature_b64), canonicalize_bytes(body))
            return True
        except Exception:
            return False


# --------------------------------------------------------------------------- #
# Production-credible asymmetric AUTHORITY signer (replaces the public HMAC dev secret)
# --------------------------------------------------------------------------- #


class Ed25519Signer:
    """Real ed25519 authority signer satisfying Actenon's ``Signer`` protocol.

    Unlike ``build_local_proof_signer()`` — a public HMAC secret that ships in every
    wheel and, per Actenon's own guard, "proves nothing" — the private key here never
    leaves this process. The public key is publishable as a well-known JWK so any
    third party can verify offline. ``verify`` is algorithm-confusion-safe: it rejects
    any non-Ed25519 signature or wrong key_id before checking the signature itself.
    """

    algorithm = "Ed25519"

    def __init__(self, priv: Ed25519PrivateKey, key_id: str):
        self._priv = priv
        self._pub = priv.public_key()
        self.key_id = key_id

    @classmethod
    def generate(cls, key_id: str = "correctness-fused-issuer-ed25519-v1") -> "Ed25519Signer":
        return cls(Ed25519PrivateKey.generate(), key_id)

    def public_jwk(self) -> dict[str, Any]:
        raw = self._pub.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        return {"kty": "OKP", "crv": "Ed25519", "kid": self.key_id, "use": "sig", "alg": "EdDSA", "x": _b64e(raw)}

    def sign(self, payload: bytes):
        from actenon.models import SignatureSpec
        from actenon.proof.signers.base import b64url_encode

        return SignatureSpec(
            algorithm="Ed25519", key_id=self.key_id, encoding="base64url",
            value=b64url_encode(self._priv.sign(payload)),
        )

    def verify(self, payload: bytes, signature) -> bool:
        from actenon.proof.signers.base import b64url_decode

        if getattr(signature, "algorithm", None) != "Ed25519" or getattr(signature, "key_id", None) != self.key_id:
            return False
        try:
            self._pub.verify(b64url_decode(signature.value), payload)
            return True
        except Exception:
            return False


class Ed25519Verifier:
    """Verify-only authority checker built from a PUBLIC JWK (no private key).

    Demonstrates the asymmetric trust property: a third party who only ever sees the
    published well-known public key can verify a proof but can never mint one. The
    symmetric HMAC dev signer cannot offer this — its secret both signs and verifies.
    """

    algorithm = "Ed25519"

    def __init__(self, pub: Ed25519PublicKey, key_id: str):
        self._pub = pub
        self.key_id = key_id

    @classmethod
    def from_jwk(cls, jwk: dict[str, Any]) -> "Ed25519Verifier":
        return cls(Ed25519PublicKey.from_public_bytes(_b64d(jwk["x"])), jwk["kid"])

    def sign(self, payload: bytes):
        raise RuntimeError("public-key-only verifier cannot sign")

    def verify(self, payload: bytes, signature) -> bool:
        from actenon.proof.signers.base import b64url_decode

        if getattr(signature, "algorithm", None) != "Ed25519" or getattr(signature, "key_id", None) != self.key_id:
            return False
        try:
            self._pub.verify(b64url_decode(signature.value), payload)
            return True
        except Exception:
            return False


# --------------------------------------------------------------------------- #
# Correctness certificate: property-verify (class) + Sentinel (examples)
# --------------------------------------------------------------------------- #


def build_correctness_cert(
    prover: CorrectnessProver,
    *,
    code_path: Path,
    export: str,
    property_report: dict[str, Any],
    sentinel_verdict: str,
    sentinel_receipt: str | None = None,
) -> tuple[dict[str, Any], str]:
    """Build and sign a correctness certificate for an exact code artifact.

    overall == VERIFIED only if BOTH the property report (whole bug class) and
    the Sentinel verdict (approved examples) are VERIFIED. Fails closed.
    """
    code_bytes = code_path.read_bytes()
    prop_verdict = str(property_report.get("verdict", "UNKNOWN")).upper()
    sent_verdict = str(sentinel_verdict or "UNKNOWN").upper()
    overall = "VERIFIED" if (prop_verdict == "VERIFIED" and sent_verdict == "VERIFIED") else "NOT_VERIFIED"

    body: dict[str, Any] = {
        "contract": {"name": "correctness_cert", "version": "v1"},
        "code_artifact": {
            "path": code_path.name,
            "sha256": sha256_hex(code_bytes),
            "export": export,
        },
        "verdicts": {
            "property": {
                "verdict": prop_verdict,
                "trials": property_report.get("trials"),
                "violations": len(property_report.get("violations", []) or []),
                "invariants": property_report.get("invariants"),
            },
            "sentinel": {"verdict": sent_verdict, "receipt": sentinel_receipt},
        },
        "overall": overall,
        "prover": {
            "id": "correctness-prover",
            "key_id": prover.key_id,
            "public_key": prover.public_key_b64,
        },
        "issued_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    signature = prover.sign(body)
    cert = {**body, "signature": {"algorithm": "Ed25519", "value": signature}}
    digest = sha256_hex(canonicalize_bytes(body))
    return cert, digest


# --------------------------------------------------------------------------- #
# Mint an Actenon proof with the correctness certificate bound into extensions
# --------------------------------------------------------------------------- #


def _actenon_signer(key_id: str = "correctness-fused-issuer-ed25519-v1") -> Ed25519Signer:
    """Production-credible LOCAL asymmetric authority signer (real ed25519 keypair).

    Replaces ``build_local_proof_signer()`` whose HMAC secret ships public in every
    wheel and (per Actenon's own guard) "proves nothing". No development-intent
    declaration is needed because no public secret is used. For multi-host custody the
    private key would live in KMS/HSM and the public key would be served at
    ``https://<issuer>/.well-known/actenon/keys.json``; here we publish the same JWK to
    a local well-known document so any third party can verify the proofs offline.
    """
    return Ed25519Signer.generate(key_id=key_id)


def mint_fused_proof(
    *,
    signer,
    intent_payload: dict[str, Any],
    decision,
    context,
    cert: dict[str, Any],
    cert_digest: str,
    pccb_id: str,
    nonce: str,
    issuer_id: str = "correctness-fused-issuer",
):
    from actenon.models import PartyRef
    from actenon.proof import PCCBMinter
    from actenon.api.intake import ActionIntentIntakeService

    intent = ActionIntentIntakeService().parse(intent_payload)
    body = {k: v for k, v in cert.items() if k != "signature"}
    extension = {
        "cert_digest": cert_digest,
        "code_artifact_sha256": cert["code_artifact"]["sha256"],
        "overall": cert["overall"],
        "prover_public_key": cert["prover"]["public_key"],
        "cert_signature": cert["signature"]["value"],
        "cert_body": body,
    }
    minter = PCCBMinter(
        signer=signer,
        issuer=PartyRef(type="service", id=issuer_id, display_name="Correctness-Fused Issuer"),
        pccb_id_factory=lambda: pccb_id,
        nonce_factory=lambda: nonce,
    )
    return minter.mint(intent, decision, context, extensions={"correctness": extension})


# --------------------------------------------------------------------------- #
# The edge gate: authority AND correctness AND code-binding AND no-replay
# --------------------------------------------------------------------------- #


class GateResult:
    def __init__(self, decision: str, layer: str, code: str, reason: str, **extra):
        self.decision = decision  # ALLOW | REFUSE
        self.layer = layer        # AUTHORITY | CORRECTNESS | REPLAY | OK
        self.code = code
        self.reason = reason
        self.extra = extra

    @property
    def allowed(self) -> bool:
        return self.decision == "ALLOW"

    def __str__(self) -> str:
        return f"{self.decision} [{self.layer}/{self.code}] {self.reason}"


def edge_gate(
    *,
    signer,
    intent_payload: dict[str, Any],
    pccb_payload: dict[str, Any],
    context,
    code_path: Path,
    used_nonces: set[str],
) -> GateResult:
    from actenon.core.errors import ProofVerificationError
    from actenon.verifier import VerifierSDK

    # 1. AUTHORITY — Actenon cryptographic proof verification (sig/audience/time/action-hash).
    try:
        verified = VerifierSDK(signer).verify(intent=intent_payload, pccb=pccb_payload, context=context)
    except ProofVerificationError as e:
        return GateResult("REFUSE", "AUTHORITY", getattr(e, "refusal_code", "PROOF_INVALID"), str(getattr(e, "message", e)))
    except Exception as e:  # noqa: BLE001
        return GateResult("REFUSE", "AUTHORITY", "PROOF_INVALID", str(e))

    pccb = verified.pccb
    ext = (pccb.extensions or {}).get("correctness")

    # 2. CORRECTNESS bound at all?
    if not ext:
        return GateResult("REFUSE", "CORRECTNESS", "NO_CORRECTNESS_BOUND", "proof carries no correctness certificate extension")

    # 3. Certificate signature — independent prover key, not Actenon's.
    body = ext.get("cert_body")
    if not CorrectnessProver.verify(ext.get("prover_public_key", ""), body or {}, ext.get("cert_signature", "")):
        return GateResult("REFUSE", "CORRECTNESS", "CERT_SIGNATURE_INVALID", "correctness certificate signature failed verification")

    # 4. Digest binding — the signed body must hash to the digest committed in the proof.
    if sha256_hex(canonicalize_bytes(body)) != ext.get("cert_digest"):
        return GateResult("REFUSE", "CORRECTNESS", "CERT_DIGEST_MISMATCH", "certificate body does not match the digest bound in the proof")

    # 5. Verdict — whole-bug-class property + Sentinel examples must both be VERIFIED.
    if body.get("overall") != "VERIFIED":
        v = body.get("verdicts", {})
        return GateResult(
            "REFUSE", "CORRECTNESS", "NOT_VERIFIED",
            f"correctness verdict {body.get('overall')} (property={v.get('property', {}).get('verdict')}, sentinel={v.get('sentinel', {}).get('verdict')})",
        )

    # 6. Code-artifact binding — the code that will ACTUALLY run must be the certified code.
    actual = sha256_hex(code_path.read_bytes())
    if actual != ext.get("code_artifact_sha256"):
        return GateResult(
            "REFUSE", "CORRECTNESS", "CODE_ARTIFACT_MISMATCH",
            f"executing code {actual[:12]}… != certified {str(ext.get('code_artifact_sha256'))[:12]}…",
        )

    # 7. Replay — single-use nonce claim at the edge (Actenon requires an external claim).
    nonce = pccb.nonce
    if nonce in used_nonces:
        return GateResult("REFUSE", "REPLAY", "NONCE_REUSED", f"nonce {nonce} already dispatched; refusing duplicate consequential effect")
    used_nonces.add(nonce)

    return GateResult(
        "ALLOW", "OK", "AUTHORISED_AND_CORRECT",
        "authority proof verified AND correctness certificate verified AND code hash matches AND not a replay",
        action_hash=pccb.action_hash.value, pccb_id=pccb.pccb_id, nonce=nonce,
        cert_digest=ext.get("cert_digest"), code_sha256=actual,
    )


# --------------------------------------------------------------------------- #
# Signed, tamper-evident decision ledger (mirrors airlock's receipts.jsonl)
# --------------------------------------------------------------------------- #


def append_receipt(prover: CorrectnessProver, ledger: Path, record: dict[str, Any]) -> None:
    body = dict(record)
    sig = prover.sign(body)
    line = {"receipt": body, "signature": sig, "prover_public_key": prover.public_key_b64}
    ledger.parent.mkdir(parents=True, exist_ok=True)
    with ledger.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(line, sort_keys=True) + "\n")


# --------------------------------------------------------------------------- #
# Demo: property-verify (fresh) + Sentinel (from evidence) -> 4 scenarios
# --------------------------------------------------------------------------- #

HERE = Path(__file__).resolve().parent              # .../tools
EXP = HERE.parent                                    # repo root (the experiment/product dir)
LAB = Path(os.environ.get("LAB", str(EXP.parent)))   # agent-lab holding sibling repos + .venvs
TSX = LAB / "sentinel-verified" / "node_modules" / ".bin" / "tsx"
PV = EXP / "tools" / "property-verify.mjs"
PC = EXP / "property-contract.json"
EVIDENCE = EXP / "evidence" / "unstoppable"


def run_property_verify(code_path: Path) -> dict[str, Any]:
    out = subprocess.run(
        [str(TSX), str(PV), "--module", str(code_path), "--contract", str(PC)],
        capture_output=True, text=True,
    )
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return {"verdict": "UNKNOWN", "trials": 0, "violations": [], "raw": out.stdout[-400:], "err": out.stderr[-400:]}


def sentinel_verdict_from_evidence(arm: str) -> tuple[str, str | None]:
    path = EVIDENCE / ("4-armB-sentinel.txt" if arm == "B" else "3a-armA-sentinel.txt")
    if not path.exists():
        return "UNKNOWN", None
    text = path.read_text()
    verdict = "VERIFIED" if "VERIFIED ·" in text else ("CONTRADICTED" if "CONTRADICTED ·" in text else "UNKNOWN")
    receipt = None
    import re
    m = re.search(r"reports/([a-f0-9]{64})\.html", text)
    if m:
        receipt = m.group(1)
    return verdict, receipt


def _now_window():
    now = datetime.now(timezone.utc)
    iso = lambda d: d.isoformat().replace("+00:00", "Z")  # noqa: E731
    return now, iso(now), iso(now + timedelta(minutes=5))


def build_intent(now_iso: str, exp_iso: str, total_pence: int, parties: int) -> dict[str, Any]:
    return {
        "contract": {"name": "action_intent", "version": "v1"},
        "intent_id": "intent_settlement_disburse_001",
        "issued_at": now_iso,
        "expires_at": exp_iso,
        "tenant": {"tenant_id": "tenant_settlement_demo"},
        "requester": {"type": "service", "id": "settlement_agent", "display_name": "Settlement Agent"},
        "action": {
            "name": "settlement.disburse",
            "capability": "settlement.disburse",
            "parameters": {"allocation_id": "alloc_001", "total_pence": total_pence, "parties": parties},
            "constraints": {"exact_total_pence": total_pence, "exact_parties": parties},
            "scope": {"target_resource_type": "settlement_ledger", "single_use": True},
        },
        "target": {"resource_type": "settlement_ledger", "resource_id": "ledger_demo_001"},
        "metadata": {"distribution": "correctness-fused-gate"},
        "context": {"demo": "fused_edge_gate"},
    }


def build_context(request_id: str, now: datetime, total_pence: int, parties: int):
    from actenon.models import AudienceRef, DynamicContextInput

    return DynamicContextInput(
        request_id=request_id,
        audience=AudienceRef(type="service", id="settlement-disbursement-endpoint"),
        scope_capabilities=("settlement.disburse",),
        now=now,
        parameter_constraints={"exact_total_pence": total_pence, "exact_parties": parties},
        resource_selectors=({"resource_id": "ledger_demo_001"},),
    )


def build_decision():
    from actenon.models import PolicyDecision

    return PolicyDecision(
        outcome="allow",
        summary="Local proof mode allows the settlement disbursement example.",
        rule_evaluations=(),
        reason_codes=("LOCAL_PROOF_ALLOW",),
    )


def demo(out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    ledger = out_dir / "fused-gate-ledger.jsonl"
    if ledger.exists():
        ledger.unlink()

    prover = CorrectnessProver.generate()
    signer = _actenon_signer()
    used_nonces: set[str] = set()

    # Publish the authority public key as a well-known JWK trust root (public only).
    wk_path = out_dir / "well-known-actenon-keys.json"
    wk_path.write_text(
        json.dumps({"issuer": "correctness-fused-issuer", "keys": [signer.public_jwk()]}, indent=2) + "\n",
        encoding="utf-8",
    )

    cand_a = EXP / "candidates" / "arm-a-rounding.ts"
    cand_b = EXP / "candidates" / "arm-b-correct.ts"
    total_pence, parties = 1000000, 3

    print("== running property-verify fresh on both candidates (200k inputs each) ==")
    prop_a = run_property_verify(cand_a)
    prop_b = run_property_verify(cand_b)
    print(f"   arm-a property verdict = {prop_a.get('verdict')} (trials={prop_a.get('trials')})")
    print(f"   arm-b property verdict = {prop_b.get('verdict')} (trials={prop_b.get('trials')})")
    sent_a, rec_a = sentinel_verdict_from_evidence("A")
    sent_b, rec_b = sentinel_verdict_from_evidence("B")
    print(f"   arm-a sentinel verdict = {sent_a} (receipt={str(rec_a)[:12]})")
    print(f"   arm-b sentinel verdict = {sent_b} (receipt={str(rec_b)[:12]})")

    cert_a, dig_a = build_correctness_cert(
        prover, code_path=cand_a, export="allocate", property_report=prop_a,
        sentinel_verdict=sent_a, sentinel_receipt=rec_a,
    )
    cert_b, dig_b = build_correctness_cert(
        prover, code_path=cand_b, export="allocate", property_report=prop_b,
        sentinel_verdict=sent_b, sentinel_receipt=rec_b,
    )
    print(f"   cert A overall={cert_a['overall']} digest={dig_a[:12]}…")
    print(f"   cert B overall={cert_b['overall']} digest={dig_b[:12]}…")

    scenarios: list[tuple[str, dict[str, Any], Path, str]] = []

    # Scenario 1 — Arm A: wrong fix, GREEN tests, valid authority. Correctness VIOLATED.
    now, now_iso, exp_iso = _now_window()
    intent = build_intent(now_iso, exp_iso, total_pence, parties)
    ctx = build_context("req_disburse_A", now, total_pence, parties)
    pccb_a = mint_fused_proof(
        signer=signer, intent_payload=intent, decision=build_decision(), context=ctx,
        cert=cert_a, cert_digest=dig_a, pccb_id="pccb_armA_001", nonce="nonce-armA-0001",
    )
    scenarios.append(("1 Arm A: wrong fix, green tests, valid authority", pccb_a.to_dict(), cand_a, intent, ctx))

    # Scenario 2 — Arm B: correct fix. Correctness VERIFIED.
    pccb_b = mint_fused_proof(
        signer=signer, intent_payload=intent, decision=build_decision(), context=ctx,
        cert=cert_b, cert_digest=dig_b, pccb_id="pccb_armB_001", nonce="nonce-armB-0001",
    )
    scenarios.append(("2 Arm B: correct fix (proof + cert)", pccb_b.to_dict(), cand_b, intent, ctx))

    # Scenario 3 — Tamper: Arm B's VERIFIED cert, but point at Arm A's code.
    scenarios.append(("3 Tamper: cert for B, code swapped to A", pccb_b.to_dict(), cand_a, intent, ctx))

    # Scenario 4 — Replay: re-present Arm B's exact single-use proof.
    scenarios.append(("4 Replay: re-dispatch Arm B (nonce reuse)", pccb_b.to_dict(), cand_b, intent, ctx))

    print("\n== edge gate decisions ==")
    results = []
    for i, (label, pccb_payload, code_path, intent_p, ctx_p) in enumerate(scenarios):
        res = edge_gate(
            signer=signer, intent_payload=intent_p, pccb_payload=pccb_payload,
            context=ctx_p, code_path=code_path, used_nonces=used_nonces,
        )
        results.append((label, res))
        print(f"   {label}\n      -> {res}")
        append_receipt(prover, ledger, {
            "ts": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "scenario": label, "decision": res.decision, "layer": res.layer,
            "code": res.code, "reason": res.reason, "code_path": code_path.name,
            **{k: v for k, v in res.extra.items()},
        })
        # On ALLOW, perform the consequential side effect (a real disbursement record).
        if res.allowed and i == 1:
            disb = out_dir / "disbursement.json"
            disb.write_text(json.dumps({
                "allocation_id": "alloc_001", "total_pence": total_pence, "parties": parties,
                "executed_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                "authority": "actenon-pccb:nonce-armB-0001", "correctness_cert": dig_b,
                "code_sha256": res.extra.get("code_sha256"),
            }, indent=2) + "\n", encoding="utf-8")
            print(f"      side effect EXECUTED -> {disb.name}")

    # Asymmetric trust property: a third party verifies the Arm B proof with ONLY the
    # published public JWK (no private key). The dev HMAC signer could never do this.
    from actenon.verifier import VerifierSDK

    pub_verifier = Ed25519Verifier.from_jwk(json.loads(wk_path.read_text())["keys"][0])
    try:
        tp = VerifierSDK(pub_verifier).verify(intent=intent, pccb=pccb_b.to_dict(), context=ctx)
        asymmetric_ok = tp.pccb.pccb_id == "pccb_armB_001"
    except Exception as e:  # noqa: BLE001
        asymmetric_ok = False
        print(f"   asymmetric verify error: {e}")

    # Expectations
    expect = ["REFUSE", "ALLOW", "REFUSE", "REFUSE"]
    expect_codes = ["NOT_VERIFIED", "AUTHORISED_AND_CORRECT", "CODE_ARTIFACT_MISMATCH", "NONCE_REUSED"]
    ok = all(r.decision == e and r.code == c for (_, r), e, c in zip(results, expect, expect_codes)) and asymmetric_ok

    print("\n== fused-gate summary ==")
    print(f"   authority signer : {signer.algorithm} key_id={signer.key_id}  (real ed25519 keypair, NOT the public HMAC dev secret)")
    print(f"   well-known trust root (public JWK): {wk_path.name}")
    print(f"   third-party verify with PUBLIC KEY ONLY: {'OK' if asymmetric_ok else 'FAIL'}  (asymmetric: anyone can verify, only the key holder can sign)")
    print(f"   correctness prover (independent ed25519): {prover.public_key_b64}")
    print(f"   signed decision ledger: {ledger} ({sum(1 for _ in ledger.open())} receipts)")
    print(f"   1 wrong-fix-green-tests  -> REFUSE (correctness, not authority)  : {results[0][1].code}")
    print(f"   2 correct-fix            -> ALLOW + executed disbursement        : {results[1][1].code}")
    print(f"   3 code swapped post-cert -> REFUSE (hash binding)                : {results[2][1].code}")
    print(f"   4 blind replay           -> REFUSE (single-use nonce)            : {results[3][1].code}")
    print("FUSED-GATE RESULT:", "PASS" if ok else "CHECK ABOVE")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Correctness-fused execution-edge gate")
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("demo", help="run the 4-scenario fusion demonstration")
    d.add_argument("--out", default=str(EXP / "evidence" / "fused-gate"))
    args = ap.parse_args()
    if args.cmd == "demo":
        return demo(Path(args.out))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
