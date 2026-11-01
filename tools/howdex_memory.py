"""Remember layer: capture the verified repair, distil a procedure, prove fresh-agent transfer."""
import json
from howdex import Howdex

mem = Howdex()


def repair_session(total, parties, expected):
    mem.start_session(f"conserve settlement total for allocate({total},{parties})")
    mem.log_tool_call(
        "read_file", {"path": "src/settle.ts"},
        observation="allocate() uses Math.floor(total/parties) and fills every party with the same amount; the remainder pennies are dropped",
    )
    mem.log_tool_call(
        "edit_file", {"path": "src/settle.ts"},
        observation="replace floor-fill with largest-remainder: base=floor(total/parties); add 1 to each of the first (total - base*parties) parties so the parts sum exactly to total",
    )
    mem.log_tool_call("run", {"cmd": "vitest run"}, observation="ordinary tests still pass")
    mem.log_tool_call(
        "run", {"cmd": "sentinel verify --contract settlement-contract.json"},
        observation=f"VERIFIED: allocate({total},{parties})=={expected}; sum(parts)==total; no penny created or destroyed",
    )
    mem.end_session("success")


repair_session(100, 3, [34, 33, 33])
repair_session(7, 2, [4, 3])
repair_session(10, 3, [4, 3, 3])
repair_session(1000000, 7, "sum==1000000")

procedures = mem.learn(min_samples=3)
print("LEARNED_PROCEDURES:", len(procedures))
for p in procedures[:3]:
    name = getattr(p, "name", None) or getattr(p, "id", None) or getattr(p, "slug", "?")
    summ = getattr(p, "summary", None) or getattr(p, "description", None) or ""
    print("  -", name, "|", str(summ)[:180])

# Fresh agent (separate handle) recalls operational guidance — never shown the source.
fresh = Howdex()
hits = fresh.recall(
    "how do I split a settlement total across parties without losing or creating pennies",
    layer="procedural", top_k=3,
)
print("FRESH_RECALL_HITS:", len(hits))
for h in hits[:3]:
    body = getattr(h, "content", None) or getattr(h, "text", None) or h
    print("  score=%.3f" % float(getattr(h, "score", 0.0) or 0.0), "|", str(body)[:220])

for fn in ("guidance", "render_procedure_guidance"):
    try:
        g = getattr(fresh, fn)("split settlement total across parties conserve pennies")
        print(f"{fn.upper()}:", str(g)[:600])
        break
    except Exception as e:
        print(f"{fn} n/a:", repr(e)[:120])

print("STATS:", json.dumps(mem.stats(), default=str)[:400])
