#!/usr/bin/env python3
"""
NEURONIX OS Evidence Graph Generator
Emits the authoritative 10-node Evidence Graph (dist/evidence-graph.json).
Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "packages/neuronix-core"))

from neuronix_core.graph import EvidenceGraph

def main():
    dist_dir = os.path.join(PROJECT_ROOT, "dist")
    os.makedirs(dist_dir, exist_ok=True)
    out_path = os.path.join(dist_dir, "evidence-graph.json")

    # Read latest commit sha and run id from snapshot if available
    commit_sha = "60f8652ba75d8fd27d95f23a74bff7414b65f590"
    run_id = "34306803041"

    snapshot_path = os.path.join(PROJECT_ROOT, "data/assurance_evidence_snapshot.json")
    if os.path.exists(snapshot_path):
        with open(snapshot_path, "r", encoding="utf-8") as f:
            snap = json.load(f)
            commit_sha = snap.get("last_verified_commit_sha", commit_sha)
            run_id = snap.get("last_verified_run_id", run_id)

    engine = EvidenceGraph(root_dir=PROJECT_ROOT)
    graph = engine.build_graph(commit_sha=commit_sha, run_id=run_id)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(graph, f, indent=2, ensure_ascii=False)

    print(f"[EVIDENCE-GRAPH] Generated authoritative graph at {out_path}")
    print(f"  Nodes: {graph['node_count']} | Edges: {graph['edge_count']} | Digest: {graph['graph_digest']}")

if __name__ == "__main__":
    main()
