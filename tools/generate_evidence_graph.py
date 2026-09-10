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

    commit_sha = os.environ.get("GITHUB_SHA")
    run_id = os.environ.get("GITHUB_RUN_ID")

    snapshot_path = os.path.join(PROJECT_ROOT, "data/assurance_evidence_snapshot.json")
    if not commit_sha or not run_id:
        if os.path.exists(snapshot_path):
            with open(snapshot_path, "r", encoding="utf-8") as f:
                snap = json.load(f)
                if not commit_sha:
                    commit_sha = snap.get("last_verified_commit_sha")
                if not run_id:
                    run_id = snap.get("last_verified_run_id")

    rec_path = os.path.join(PROJECT_ROOT, "data/assurance_record.json")
    if not commit_sha or not run_id:
        if os.path.exists(rec_path):
            with open(rec_path, "r", encoding="utf-8") as f:
                rec = json.load(f)
                if not commit_sha:
                    commit_sha = rec.get("last_verified_commit_sha")
                if not run_id:
                    run_id = rec.get("last_verified_run_id")

    if not commit_sha:
        try:
            import subprocess
            res = subprocess.run(["git", "rev-parse", "HEAD"], cwd=PROJECT_ROOT, capture_output=True, text=True, check=True)
            commit_sha = res.stdout.strip()
        except Exception:
            commit_sha = "UNBOUND_LOCAL_COMMIT"

    if not run_id:
        run_id = "UNBOUND_LOCAL_RUN"

    engine = EvidenceGraph(root_dir=PROJECT_ROOT)
    graph = engine.build_graph(commit_sha=commit_sha, run_id=run_id)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(graph, f, indent=2, ensure_ascii=False)

    print(f"[EVIDENCE-GRAPH] Generated authoritative graph at {out_path}")
    print(f"  Nodes: {graph['node_count']} | Edges: {graph['edge_count']} | Digest: {graph['graph_digest']}")

if __name__ == "__main__":
    main()
