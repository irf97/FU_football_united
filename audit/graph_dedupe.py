"""Post-process a graphify graph.json to merge fragmented module nodes.

Background: graphify's deduplicator merges only on exact ID match. Distinct
extraction passes (AST + N semantic subagents) produce different IDs for the
same logical module ("Fu.Balance", "fu_balance", "Fu.Balance (snake-draft)",
"fu_balance_fu_balance"), inflating community count and distorting centrality.
This script merges them under a strict allow-list rule.
"""
from __future__ import annotations

import json
import shutil
import sys
from collections import defaultdict
from pathlib import Path
from typing import Iterable

DEFAULT_MODULES = [
    "Fu.Balance",
    "Fu.Mesh",
    "Fu.Queues",
    "Fu.Ranking",
    "Fu.Matches",
    "Fu.Accounts",
    "Fu.Lobby",
    "Fu.Tactics",
]


def belongs_to_module(label: str, module: str) -> bool:
    """Return True if `label` names the module itself (not a function member)."""
    if not label:
        return False
    L = label.strip()
    if L == module:
        return True
    # Don't match function members like "Fu.Balance.assign_teams/1"
    if L.startswith(module + "."):
        return False
    # Underscore-variant: "fu_balance" matches "Fu.Balance"
    if L.lower().replace(".", "_") == module.lower().replace(".", "_"):
        return True
    # Parenthetical annotation: "Fu.Balance (snake-draft)"
    if L.startswith(module + " (") and L.endswith(")"):
        return True
    return False


def _pick_canonical(node_ids, nodes_by_id, degree_by_id, module: str) -> str:
    """Pick the canonical id from a set of node ids belonging to one module."""
    def score(nid):
        n = nodes_by_id[nid]
        is_code = 1 if n.get("file_type") == "code" else 0
        src = (n.get("source_file") or "").lower().replace("\\", "/")
        # Tiebreak: prefer source_file ending in the module's lowercased filename
        module_file = module.split(".")[-1].lower() + ".ex"
        in_module_file = 1 if src.endswith(module_file) else 0
        return (is_code, in_module_file, degree_by_id.get(nid, 0))

    return max(node_ids, key=score)


def dedupe_graph(graph: dict, modules: Iterable[str] = None, return_report: bool = False):
    modules = list(modules) if modules is not None else list(DEFAULT_MODULES)
    nodes = list(graph.get("nodes", []))
    links_key = "links" if "links" in graph else "edges"
    edges = list(graph.get(links_key, []))

    nodes_by_id = {n["id"]: n for n in nodes}
    degree_by_id = defaultdict(int)
    for e in edges:
        degree_by_id[e["source"]] += 1
        degree_by_id[e["target"]] += 1

    alias_map: dict[str, str] = {}  # non_canonical_id -> canonical_id
    report: dict[str, dict] = {}

    for module in modules:
        matching_ids = [nid for nid, n in nodes_by_id.items()
                        if belongs_to_module(n.get("label", ""), module)]
        if len(matching_ids) < 2:
            continue
        canonical = _pick_canonical(matching_ids, nodes_by_id, degree_by_id, module)
        merged = [nid for nid in matching_ids if nid != canonical]
        for mid in merged:
            alias_map[mid] = canonical
        report[module] = {
            "canonical_id": canonical,
            "canonical_label": nodes_by_id[canonical].get("label", ""),
            "merged_ids": merged,
            "merged_count": len(merged),
            "edges_rewritten": 0,        # filled below
            "duplicates_dropped": 0,     # filled below
        }

    # Rewrite edges
    new_edges = []
    seen_edges: set[tuple] = set()
    edges_rewritten_per_module: dict[str, int] = defaultdict(int)
    duplicates_dropped_per_module: dict[str, int] = defaultdict(int)

    for e in edges:
        src = alias_map.get(e["source"], e["source"])
        tgt = alias_map.get(e["target"], e["target"])
        if src != e["source"] or tgt != e["target"]:
            # which module was involved? (the canonical id is in either src or tgt)
            for module, info in report.items():
                if info["canonical_id"] in (src, tgt):
                    edges_rewritten_per_module[module] += 1
                    break
        key = (src, tgt, e.get("relation"))
        if key in seen_edges:
            for module, info in report.items():
                if info["canonical_id"] in (src, tgt):
                    duplicates_dropped_per_module[module] += 1
                    break
            continue
        seen_edges.add(key)
        ne = dict(e)
        ne["source"] = src
        ne["target"] = tgt
        new_edges.append(ne)

    # Drop non-canonical nodes
    surviving_ids = {nid for nid in nodes_by_id if nid not in alias_map}
    new_nodes = [n for n in nodes if n["id"] in surviving_ids]

    for module in list(report.keys()):
        report[module]["edges_rewritten"] = edges_rewritten_per_module[module]
        report[module]["duplicates_dropped"] = duplicates_dropped_per_module[module]

    out = dict(graph)
    out["nodes"] = new_nodes
    out[links_key] = new_edges

    if return_report:
        return out, report
    return out


def _summarize(report: dict) -> None:
    if not report:
        print("OK: no fragmented modules found.")
        return
    print(f"Merged {len(report)} module(s).\n")
    for module, info in report.items():
        print(f"  {module}")
        print(f"    canonical:        {info['canonical_label']!r} (id={info['canonical_id']})")
        print(f"    merged_count:     {info['merged_count']}")
        print(f"    edges_rewritten:  {info['edges_rewritten']}")
        print(f"    duplicates_dropped: {info['duplicates_dropped']}")
        print()


def main(argv: list[str]) -> int:
    graph_path = Path("graphify-out/graph.json")
    if not graph_path.exists():
        print(f"ERROR: {graph_path} not found. Run /graphify first.", file=sys.stderr)
        return 2

    # Backup before any mutation
    backup_path = graph_path.with_suffix(".json.bak")
    shutil.copyfile(graph_path, backup_path)
    print(f"Backed up to {backup_path}")

    graph = json.loads(graph_path.read_text(encoding="utf-8"))
    nodes_before = len(graph.get("nodes", []))
    edges_before = len(graph.get("links", graph.get("edges", [])))

    new_graph, report = dedupe_graph(graph, return_report=True)
    nodes_after = len(new_graph.get("nodes", []))
    edges_after = len(new_graph.get("links", new_graph.get("edges", [])))

    graph_path.write_text(json.dumps(new_graph, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Nodes: {nodes_before} -> {nodes_after}  (delta {nodes_after - nodes_before})")
    print(f"Edges: {edges_before} -> {edges_after}  (delta {edges_after - edges_before})")
    print()
    _summarize(report)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
