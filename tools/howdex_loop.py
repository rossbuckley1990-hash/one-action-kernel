"""Remember layer for the loop: capture the verified repair, distil a procedure, prove fresh-agent transfer."""
import json
from howdex import Howdex

mem = Howdex()
for _ in range(4):
    mem.start_session("repair settlement allocate to conserve total pennies")
    mem.log_tool_call("read_file", {"path": "src/settle.ts"},
                      observation="floor-fill drops the remainder pennies")
    mem.log_tool_call("edit_file", {"path": "src/settle.ts"},
                      observation="largest-remainder: give +1 to each of the first (total - base*parties) parties so parts sum exactly to total")
    mem.log_tool_call("run", {"cmd": "sentinel verify"},
                      observation="VERIFIED sum(parts)==total, no penny created or destroyed")
    mem.end_session("success")

procs = mem.learn(min_samples=3, incremental=True)
print("PROCEDURES_DISTILLED:", len(procs))

fresh = Howdex()
hits = fresh.recall("split a settlement total across parties without losing or creating pennies", top_k=3)
print("FRESH_RECALL_HITS:", len(hits))
for h in hits[:2]:
    m = getattr(h, "memory", None)
    content = getattr(m, "content", None) if m else str(h)
    layer = getattr(getattr(m, "layer", None), "value", "?")
    print("   score=%.3f layer=%s | %s" % (float(getattr(h, "score", 0) or 0), layer, str(content)[:150]))

# Anti-leak guard: a recalled memory must carry operational facts, NOT the literal fixed source.
leak = any("base + (i < remainder" in str(getattr(getattr(h, "memory", None), "content", "")) for h in hits)
print("SOURCE_PASTED_IN_RECALL:", leak)
print("STATS:", json.dumps(mem.stats(), default=str)[:300])
