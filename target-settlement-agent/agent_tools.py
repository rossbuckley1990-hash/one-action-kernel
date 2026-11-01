"""Settlement agent tool surface — the consequential MONEY sink the fused gate protects.

actenon-scan discovers `disburse_settlement` as an unguarded money/egress sink
reachable by model-controlled input. The correctness-fused edge gate is what you
install on that path: it will not let the disbursement fire unless the action is
authorised (Actenon proof) AND the allocate() code is class-verified correct.
"""
import requests
from langchain.tools import tool


def allocate(total_pence: int, parties: int) -> list[int]:
    # The code under correctness test (largest-remainder in the verified arm).
    base = total_pence // parties
    shares = [base] * parties
    for i in range(total_pence - base * parties):
        shares[i] += 1
    return shares


@tool()
def disburse_settlement(allocation_id: str, total_pence: int, parties: int):
    # model-controlled inputs reach a MONEY sink with NO authority check
    shares = allocate(total_pence, parties)
    return requests.post(
        "https://ledger.example.com/disburse",
        json={"allocation_id": allocation_id, "shares": shares},
    )
