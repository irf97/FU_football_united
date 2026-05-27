"""Audit graphify edges for structurally impossible relation/source-type combinations.

Built after discovering an EXTRACTED 1.0 edge `fu_balance --imports--> voting.ex`
where the source was a markdown doc — `imports` from a doc to code is impossible.
Documented in CLAUDE.md project context (graphify exploration session, 2026-05-21).
"""
import json
import sys
from pathlib import Path
from typing import Iterable

# Structural constraint table.
# Each relation lists the file_type values its SOURCE node may legitimately have.
STRUCTURAL = {
    "imports":       {"valid_source": {"code"}},
    "calls":         {"valid_source": {"code"}},
    "implements":    {"valid_source": {"code"}},
    "cites":         {"valid_source": {"document", "rationale", "paper"}},
    "rationale_for": {"valid_source": {"rationale"}},
}


def find_invalid_edges(graph_path: Path) -> list[dict]:
    """Return a list of edges whose relation type is incompatible with the source node's file_type."""
    data = json.loads(Path(graph_path).read_text(encoding="utf-8"))
    nodes_by_id = {n["id"]: n for n in data.get("nodes", [])}
    invalid: list[dict] = []
    for edge in data.get("links", data.get("edges", [])):
        relation = edge.get("relation")
        rule = STRUCTURAL.get(relation)
        if rule is None:
            continue  # no constraint defined for this relation
        src = nodes_by_id.get(edge.get("source"))
        if src is None:
            continue
        src_type = src.get("file_type")
        if src_type not in rule["valid_source"]:
            invalid.append({
                "source": edge["source"],
                "source_label": src.get("label", ""),
                "source_file": src.get("source_file", ""),
                "target": edge["target"],
                "target_label": nodes_by_id.get(edge["target"], {}).get("label", ""),
                "relation": relation,
                "confidence": edge.get("confidence"),
                "confidence_score": edge.get("confidence_score"),
                "reason": f"{relation} requires {'/'.join(sorted(rule['valid_source']))} source, got {src_type}",
            })
    return invalid


def _summarize(invalid: Iterable[dict]) -> None:
    invalid = list(invalid)
    if not invalid:
        print("OK: no structurally invalid edges found.")
        return
    print(f"FOUND {len(invalid)} structurally invalid edge(s).\n")
    # Breakdown by relation type
    from collections import Counter
    by_rel = Counter(e["relation"] for e in invalid)
    print("By relation:")
    for rel, n in by_rel.most_common():
        print(f"  {rel:>14s}: {n}")
    print("\nFirst 10 offenders:")
    for e in invalid[:10]:
        print(f"  [{e['confidence']} {e['confidence_score']}] {e['source_label']!r} ({e['source_file']})")
        print(f"      --{e['relation']}--> {e['target_label']!r}")
        print(f"      reason: {e['reason']}\n")


if __name__ == "__main__":
    graph_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("graphify-out/graph.json")
    if not graph_path.exists():
        print(f"ERROR: {graph_path} not found. Run /graphify first.", file=sys.stderr)
        sys.exit(2)
    _summarize(find_invalid_edges(graph_path))
