import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from graph_dedupe import belongs_to_module, dedupe_graph


def test_belongs_to_module_exact():
    assert belongs_to_module("Fu.Balance", "Fu.Balance") is True

def test_belongs_to_module_underscore_variant():
    assert belongs_to_module("fu_balance", "Fu.Balance") is True

def test_belongs_to_module_parenthetical():
    assert belongs_to_module("Fu.Balance (snake-draft)", "Fu.Balance") is True

def test_belongs_to_module_rejects_function_member():
    # Functions of a module are NOT the module itself
    assert belongs_to_module("Fu.Balance.assign_teams/1", "Fu.Balance") is False

def test_belongs_to_module_rejects_unrelated():
    assert belongs_to_module("Fu.Mesh", "Fu.Balance") is False
    assert belongs_to_module("Fu.Accounts.burn/2", "Fu.Balance") is False

def test_dedupe_merges_three_balance_variants(tmp_path):
    graph = {
        "nodes": [
            {"id": "n_code",  "label": "Fu.Balance", "file_type": "code",
             "source_file": "fu/lib/fu/balance.ex"},
            {"id": "n_doc",   "label": "Fu.Balance (snake-draft)",
             "file_type": "document", "source_file": "docs/FU-APPENDIX.md"},
            {"id": "n_under", "label": "fu_balance", "file_type": "document",
             "source_file": "audit/raw/top-level.txt"},
            {"id": "neighbor", "label": "neighbor", "file_type": "code"},
        ],
        "links": [
            {"source": "n_code",  "target": "neighbor", "relation": "calls"},
            {"source": "n_doc",   "target": "neighbor", "relation": "references"},
            {"source": "n_under", "target": "neighbor", "relation": "mentions"},
        ],
    }
    out = dedupe_graph(graph, modules=["Fu.Balance"])
    # All three merged into n_code (canonical: code + highest degree among code candidates)
    node_ids = {n["id"] for n in out["nodes"]}
    assert node_ids == {"n_code", "neighbor"}
    # Edges rewritten to point at n_code
    assert all(e["source"] == "n_code" for e in out["links"])
    # Three edges with same (source, target) but different relations -> kept as three
    assert len(out["links"]) == 3
    relations = sorted(e["relation"] for e in out["links"])
    assert relations == ["calls", "mentions", "references"]


def test_dedupe_drops_duplicate_identical_edges(tmp_path):
    graph = {
        "nodes": [
            {"id": "n_a", "label": "Fu.Balance", "file_type": "code",
             "source_file": "fu/lib/fu/balance.ex"},
            {"id": "n_b", "label": "fu_balance", "file_type": "document"},
            {"id": "neighbor", "label": "x", "file_type": "code"},
        ],
        "links": [
            {"source": "n_a", "target": "neighbor", "relation": "references"},
            {"source": "n_b", "target": "neighbor", "relation": "references"},  # dup after merge
        ],
    }
    out = dedupe_graph(graph, modules=["Fu.Balance"])
    refs = [e for e in out["links"] if e["relation"] == "references"]
    assert len(refs) == 1  # duplicate after merge was dropped


def test_dedupe_preserves_function_members(tmp_path):
    """Function-level nodes are distinct concepts and must NOT be merged into the module."""
    graph = {
        "nodes": [
            {"id": "mod", "label": "Fu.Balance", "file_type": "code",
             "source_file": "fu/lib/fu/balance.ex"},
            {"id": "fn",  "label": "Fu.Balance.assign_teams/1", "file_type": "code"},
            {"id": "x",   "label": "x", "file_type": "code"},
        ],
        "links": [
            {"source": "fn", "target": "x", "relation": "calls"},
        ],
    }
    out = dedupe_graph(graph, modules=["Fu.Balance"])
    ids = {n["id"] for n in out["nodes"]}
    assert ids == {"mod", "fn", "x"}  # function survives


def test_dedupe_returns_report(tmp_path):
    """dedupe_graph returns (new_graph, report) so callers can summarise."""
    graph = {
        "nodes": [
            {"id": "a", "label": "Fu.Balance", "file_type": "code",
             "source_file": "fu/lib/fu/balance.ex"},
            {"id": "b", "label": "fu_balance", "file_type": "document"},
            {"id": "n", "label": "x", "file_type": "code"},
        ],
        "links": [
            {"source": "a", "target": "n", "relation": "calls"},
            {"source": "b", "target": "n", "relation": "references"},
        ],
    }
    out, report = dedupe_graph(graph, modules=["Fu.Balance"], return_report=True)
    assert report["Fu.Balance"]["canonical_id"] == "a"
    assert "b" in report["Fu.Balance"]["merged_ids"]
    assert report["Fu.Balance"]["edges_rewritten"] == 1
    assert report["Fu.Balance"]["duplicates_dropped"] == 0
