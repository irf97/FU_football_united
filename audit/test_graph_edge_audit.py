import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from graph_edge_audit import find_invalid_edges


def test_invalid_imports_from_doc_is_caught(tmp_path):
    graph = {
        "nodes": [
            {"id": "a", "label": "a.md", "file_type": "document"},
            {"id": "b", "label": "b.ex", "file_type": "code"},
        ],
        "links": [
            {"source": "a", "target": "b", "relation": "imports",
             "confidence": "EXTRACTED", "confidence_score": 1.0}
        ],
    }
    p = tmp_path / "g.json"
    p.write_text(json.dumps(graph), encoding="utf-8")
    invalid = find_invalid_edges(p)
    assert len(invalid) == 1
    assert invalid[0]["reason"] == "imports requires code source, got document"


def test_valid_calls_between_code_passes(tmp_path):
    graph = {
        "nodes": [
            {"id": "a", "label": "a.ex", "file_type": "code"},
            {"id": "b", "label": "b.ex", "file_type": "code"},
        ],
        "links": [
            {"source": "a", "target": "b", "relation": "calls",
             "confidence": "EXTRACTED", "confidence_score": 1.0}
        ],
    }
    p = tmp_path / "g.json"
    p.write_text(json.dumps(graph), encoding="utf-8")
    assert find_invalid_edges(p) == []


def test_rationale_for_from_code_is_caught(tmp_path):
    graph = {
        "nodes": [
            {"id": "a", "label": "a.ex", "file_type": "code"},
            {"id": "b", "label": "b concept", "file_type": "rationale"},
        ],
        "links": [
            {"source": "a", "target": "b", "relation": "rationale_for",
             "confidence": "EXTRACTED", "confidence_score": 1.0}
        ],
    }
    p = tmp_path / "g.json"
    p.write_text(json.dumps(graph), encoding="utf-8")
    invalid = find_invalid_edges(p)
    assert len(invalid) == 1
    assert "rationale_for" in invalid[0]["reason"]
