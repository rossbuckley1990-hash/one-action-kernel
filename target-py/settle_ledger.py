"""Settlement ledger helpers — the Python view of the same allocation domain.

Planted for the Model layer: one live routine, one near-duplicate introduced by a
second team, and one deprecated function that is never called.
"""


def allocate_largest_remainder(total_pence: int, parties: int) -> list[int]:
    """Conservative allocation: leftover pennies go to the leading parties."""
    base = total_pence // parties
    remainder = total_pence - base * parties
    return [base + (1 if i < remainder else 0) for i in range(parties)]


def split_pennies(total_pence: int, parties: int) -> list[int]:
    """Near-duplicate of allocate_largest_remainder, added independently by another team."""
    base = total_pence // parties
    leftover = total_pence - base * parties
    return [base + (1 if idx < leftover else 0) for idx in range(parties)]


def legacy_floor_allocate(total_pence: int, parties: int) -> list[int]:
    """Deprecated: drops the remainder (the vanishing-penny bug). Never called."""
    each = total_pence // parties
    return [each] * parties


def settle_invoice(total_pence: int, parties: int) -> dict:
    parts = allocate_largest_remainder(total_pence, parties)
    return {"parts": parts, "sum": sum(parts), "conserved": sum(parts) == total_pence}
