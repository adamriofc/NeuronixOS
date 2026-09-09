"""
NEURONIX Universal System Topology Engine
Reconstructs inter-service dependencies, storage subvolumes, network namespaces, and isolation
boundaries into a typed DAG, providing blast-radius analysis and cycle detection (SEC-018).

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
from typing import Dict, Any, List, Set, Optional, Tuple

try:
    from .state import canonical_json_bytes, sha256_canonical
except (ImportError, ValueError):
    try:
        from neuronix_core.state import canonical_json_bytes, sha256_canonical
    except ImportError:
        import sys
        sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
        from neuronix_core.state import canonical_json_bytes, sha256_canonical


class SystemTopologyEngine:
    """
    Universal System Topology Engine. Builds typed directed dependency graph across storage,
    services, security, and execution fabrics.
    """

    def __init__(self, root_dir: Optional[str] = None):
        self.root_dir = root_dir or "/"

    def get_canonical_nodes(self) -> List[Dict[str, Any]]:
        """
        Defines standard architectural nodes across NEURONIX OS subsystems.
        """
        nodes = [
            {"id": "storage:subvol_root", "type": "STORAGE", "name": "Btrfs Subvolume Root (@)", "criticality": "CRITICAL"},
            {"id": "storage:subvol_nix", "type": "STORAGE", "name": "Btrfs Store (@nix)", "criticality": "CRITICAL"},
            {"id": "storage:subvol_home", "type": "STORAGE", "name": "Btrfs Home (@home)", "criticality": "HIGH"},
            {"id": "storage:subvol_snapshots", "type": "STORAGE", "name": "Btrfs Snapshots (@snapshots)", "criticality": "MEDIUM"},
            {"id": "storage:zram_swap", "type": "STORAGE", "name": "ZRAM Compressed Swap (/dev/zram0)", "criticality": "HIGH"},
            {"id": "security:lanzaboote", "type": "SECURITY", "name": "Lanzaboote Measured Boot (TPM PCR 7 & 11)", "criticality": "CRITICAL"},
            {"id": "security:ebpf_lsm", "type": "SECURITY", "name": "eBPF LSM & Landlock Policy Engine", "criticality": "CRITICAL"},
            {"id": "service:nix_daemon", "type": "SERVICE", "name": "Nix Store Daemon", "criticality": "CRITICAL"},
            {"id": "service:neuronix_daemon", "type": "SERVICE", "name": "NEURONIX Micro-Rust Systems Daemon", "criticality": "CRITICAL"},
            {"id": "service:opencode_copilot", "type": "SERVICE", "name": "OpenCode AI Subsystem", "criticality": "MEDIUM"},
            {"id": "runtime:hyperion_tier0", "type": "RUNTIME", "name": "Hyperion Tier 0 (Fast Path Direct)", "criticality": "LOW"},
            {"id": "runtime:hyperion_tier1", "type": "RUNTIME", "name": "Hyperion Tier 1 (RAM Ghost Overlay)", "criticality": "MEDIUM"},
            {"id": "runtime:hyperion_tier2", "type": "RUNTIME", "name": "Hyperion Tier 2 (eBPF Enclave Sandbox)", "criticality": "HIGH"},
            {"id": "runtime:hyperion_tier3", "type": "RUNTIME", "name": "Hyperion Tier 3 (Micro-VM Hardware KVM)", "criticality": "HIGH"}
        ]
        return nodes

    def get_canonical_edges(self) -> List[Dict[str, str]]:
        """
        Defines directed dependency edges between subsystem nodes.
        (source -> target means source depends on target)
        """
        edges = [
            {"source": "storage:subvol_nix", "target": "storage:subvol_root", "relationship": "MOUNTS_UNDER"},
            {"source": "storage:subvol_home", "target": "storage:subvol_root", "relationship": "MOUNTS_UNDER"},
            {"source": "service:nix_daemon", "target": "storage:subvol_nix", "relationship": "DEPENDS_ON"},
            {"source": "service:neuronix_daemon", "target": "service:nix_daemon", "relationship": "DEPENDS_ON"},
            {"source": "service:neuronix_daemon", "target": "security:ebpf_lsm", "relationship": "CONSTRAINED_BY"},
            {"source": "service:opencode_copilot", "target": "service:neuronix_daemon", "relationship": "COMMUNICATES_VIA"},
            {"source": "runtime:hyperion_tier1", "target": "service:neuronix_daemon", "relationship": "MANAGED_BY"},
            {"source": "runtime:hyperion_tier2", "target": "security:ebpf_lsm", "relationship": "SANDBOXED_BY"},
            {"source": "runtime:hyperion_tier3", "target": "service:neuronix_daemon", "relationship": "BROKERED_BY"},
            {"source": "storage:subvol_root", "target": "security:lanzaboote", "relationship": "UNSEALED_BY"}
        ]
        return edges

    def build_topology(self) -> Dict[str, Any]:
        """
        Constructs the complete canonical topology representation.
        """
        nodes = self.get_canonical_nodes()
        edges = self.get_canonical_edges()

        topology = {
            "schema_version": "1.0.0",
            "topology_type": "NEURONIX_SYSTEM_TOPOLOGY_V1",
            "node_count": len(nodes),
            "edge_count": len(edges),
            "nodes": nodes,
            "edges": edges,
            "has_cycles": len(self.detect_cycles(edges)) > 0
        }
        return topology

    def detect_cycles(self, edges: Optional[List[Dict[str, str]]] = None) -> List[List[str]]:
        """
        Detects cycles in the topology graph to enforce causality (SEC-018).
        Returns a list of cycles if found.
        """
        if edges is None:
            edges = self.get_canonical_edges()

        adj: Dict[str, List[str]] = {}
        for edge in edges:
            src = edge["source"]
            tgt = edge["target"]
            adj.setdefault(src, []).append(tgt)

        visited: Set[str] = set()
        rec_stack: Set[str] = set()
        cycles: List[List[str]] = []
        current_path: List[str] = []

        def dfs(node: str):
            visited.add(node)
            rec_stack.add(node)
            current_path.append(node)

            for neighbor in adj.get(node, []):
                if neighbor not in visited:
                    dfs(neighbor)
                elif neighbor in rec_stack:
                    # Cycle detected
                    idx = current_path.index(neighbor)
                    cycle = list(current_path[idx:]) + [neighbor]
                    cycles.append(cycle)

            current_path.pop()
            rec_stack.remove(node)

        for n in list(adj.keys()):
            if n not in visited:
                dfs(n)

        return cycles

    def calculate_blast_radius(self, target_node_id: str) -> Dict[str, Any]:
        """
        Calculates transitive downstream blast radius if target_node_id is modified or impaired.
        """
        edges = self.get_canonical_edges()
        # Find all nodes that depend directly or indirectly on target_node_id
        # In our edge convention, source depends on target: edge["source"] -> edge["target"]
        # So if target is affected, all sources pointing to it are affected!
        reverse_adj: Dict[str, List[str]] = {}
        for edge in edges:
            src = edge["source"]
            tgt = edge["target"]
            reverse_adj.setdefault(tgt, []).append(src)

        affected: Set[str] = set()
        queue = [target_node_id]

        while queue:
            curr = queue.pop(0)
            for downstream in reverse_adj.get(curr, []):
                if downstream not in affected:
                    affected.add(downstream)
                    queue.append(downstream)

        all_nodes_dict = {n["id"]: n for n in self.get_canonical_nodes()}
        affected_details = [all_nodes_dict.get(n_id, {"id": n_id, "criticality": "UNKNOWN"}) for n_id in sorted(list(affected))]

        criticality_order = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "UNKNOWN": 0}
        max_crit = "LOW"
        for detail in affected_details:
            crit = detail.get("criticality", "LOW")
            if criticality_order.get(crit, 0) > criticality_order.get(max_crit, 0):
                max_crit = crit

        return {
            "target_node": target_node_id,
            "affected_count": len(affected),
            "affected_nodes": sorted(list(affected)),
            "affected_details": affected_details,
            "blast_risk_level": max_crit
        }

    def compute_topology_root(self, topology: Optional[Dict[str, Any]] = None) -> str:
        """
        Computes deterministic RFC 8785 TopologyRoot hash.
        """
        if topology is None:
            topology = self.build_topology()
        return sha256_canonical(topology)


def main():
    engine = SystemTopologyEngine()
    topo = engine.build_topology()
    root = engine.compute_topology_root(topo)
    print(f"TopologyRoot: {root}")
    print(f"Nodes: {topo['node_count']}, Edges: {topo['edge_count']}, Has Cycles: {topo['has_cycles']}")
    radius = engine.calculate_blast_radius("security:lanzaboote")
    print(f"Blast Radius for Lanzaboote: {radius['affected_count']} nodes affected (Risk: {radius['blast_risk_level']})")


if __name__ == "__main__":
    main()
