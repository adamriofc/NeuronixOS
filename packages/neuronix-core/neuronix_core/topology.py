import os
import sys
import json
import re
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
    Universal System Topology Engine (MES-NRX-002).
    Constructs both Canonical Architectural Topology and Live Observed Runtime Topology,
    merging them into an Effective Topology with differentiated blast-radius analysis (SEC-018).
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

    def observe_live_topology(self) -> Dict[str, Any]:
        """
        Observes real system runtime entities: active mount points, block device hierarchy,
        daemon sockets, network interfaces, and cgroups.
        """
        observed_nodes = []
        observed_edges = []

        # 1. Mount Graph Observation
        mounts_file = "/proc/mounts"
        if os.path.exists(mounts_file):
            try:
                with open(mounts_file, "r", encoding="utf-8") as f:
                    for line in f:
                        parts = line.split()
                        if len(parts) >= 3:
                            dev, mp, fs = parts[0], parts[1], parts[2]
                            if mp in ("/", "/nix", "/nix/store", "/boot", "/home", "/run", "/sys", "/proc"):
                                node_id = f"observed:mount:{mp}"
                                observed_nodes.append({
                                    "id": node_id,
                                    "type": "MOUNT",
                                    "device": dev,
                                    "fstype": fs,
                                    "mountpoint": mp
                                })
                                if mp != "/" and mp.startswith("/"):
                                    observed_edges.append({
                                        "source": node_id,
                                        "target": "observed:mount:/",
                                        "relationship": "MOUNTS_UNDER"
                                    })
            except Exception:
                pass

        # 2. Sockets and IPC Observation
        run_neuronix = "/run/neuronix"
        if os.path.exists(run_neuronix):
            try:
                for entry in os.listdir(run_neuronix):
                    if entry.endswith(".sock"):
                        sock_id = f"observed:socket:{entry}"
                        observed_nodes.append({
                            "id": sock_id,
                            "type": "SOCKET",
                            "path": os.path.join(run_neuronix, entry)
                        })
                        observed_edges.append({
                            "source": sock_id,
                            "target": "service:neuronix_daemon",
                            "relationship": "HOSTED_BY"
                        })
            except Exception:
                pass

        # 3. Active Network Interfaces Observation
        net_dev = "/proc/net/dev"
        if os.path.exists(net_dev):
            try:
                with open(net_dev, "r", encoding="utf-8") as f:
                    for line in f:
                        if ":" in line:
                            iface = line.split(":")[0].strip()
                            if iface in ("lo", "eth0", "wlan0", "zram0") or iface.startswith("en") or iface.startswith("wl"):
                                observed_nodes.append({
                                    "id": f"observed:net:{iface}",
                                    "type": "NETWORK_INTERFACE",
                                    "name": iface
                                })
            except Exception:
                pass

        return {
            "observed_nodes": observed_nodes,
            "observed_edges": observed_edges
        }

    def build_effective_topology(self) -> Dict[str, Any]:
        """
        Merges Canonical Architectural Topology with Live Observed Topology.
        Produces an authoritative Effective Topology where nodes and edges are tagged
        with origin: 'CANONICAL', 'OBSERVED', or 'CONVERGED'.
        """
        canonical_nodes = self.get_canonical_nodes()
        canonical_edges = self.get_canonical_edges()

        live = self.observe_live_topology()
        observed_nodes = live.get("observed_nodes", [])
        observed_edges = live.get("observed_edges", [])

        # Build merged node map
        node_map: Dict[str, Dict[str, Any]] = {}
        for cn in canonical_nodes:
            item = dict(cn)
            item["origin"] = "CANONICAL"
            item["status"] = "MISSING_EXPECTED"
            node_map[cn["id"]] = item

        # Check for convergence between canonical and observed
        observed_mountpoints = {n.get("mountpoint"): n for n in observed_nodes if n.get("type") == "MOUNT"}
        if "/" in observed_mountpoints and "storage:subvol_root" in node_map:
            node_map["storage:subvol_root"]["origin"] = "CONVERGED"
            node_map["storage:subvol_root"]["status"] = "CONVERGED"
            node_map["storage:subvol_root"]["observed_device"] = observed_mountpoints["/"]["device"]

        if "/nix" in observed_mountpoints and "storage:subvol_nix" in node_map:
            node_map["storage:subvol_nix"]["origin"] = "CONVERGED"
            node_map["storage:subvol_nix"]["status"] = "CONVERGED"

        # Check for observed sockets
        observed_sockets = {n.get("path"): n for n in observed_nodes if n.get("type") == "SOCKET"}
        for s_path in observed_sockets:
            if "ast.sock" in s_path and "service:neuronix_daemon" in node_map:
                node_map["service:neuronix_daemon"]["origin"] = "CONVERGED"
                node_map["service:neuronix_daemon"]["status"] = "CONVERGED"

        # Add purely observed nodes
        for on in observed_nodes:
            if on["id"] not in node_map:
                item = dict(on)
                item["origin"] = "OBSERVED"
                item["status"] = "OBSERVED"
                item["criticality"] = "LOW"
                node_map[on["id"]] = item

        # Merge edges
        merged_edges = []
        for ce in canonical_edges:
            edge = dict(ce)
            edge["origin"] = "DECLARED"
            merged_edges.append(edge)

        for oe in observed_edges:
            edge = dict(oe)
            edge["origin"] = "OBSERVED"
            merged_edges.append(edge)

        all_nodes = list(node_map.values())
        return {
            "schema_version": "1.1.0",
            "scope": "NEURONIX Control-Plane Effective Topology",
            "topology_type": "NEURONIX_EFFECTIVE_TOPOLOGY_V1",
            "node_count": len(all_nodes),
            "edge_count": len(merged_edges),
            "nodes": all_nodes,
            "edges": merged_edges,
            "has_cycles": len(self.detect_cycles(merged_edges)) > 0
        }

    def build_topology(self) -> Dict[str, Any]:
        """
        Backward-compatible method returning canonical architecture topology.
        """
        nodes = self.get_canonical_nodes()
        edges = self.get_canonical_edges()
        return {
            "schema_version": "1.0.0",
            "topology_type": "NEURONIX_SYSTEM_TOPOLOGY_V1",
            "node_count": len(nodes),
            "edge_count": len(edges),
            "nodes": nodes,
            "edges": edges,
            "has_cycles": len(self.detect_cycles(edges)) > 0
        }

    def detect_cycles(self, edges: Optional[List[Dict[str, str]]] = None) -> List[List[str]]:
        """
        Detects cycles in the topology graph to enforce causality (SEC-018).
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

        def dfs(node: str) -> None:
            visited.add(node)
            rec_stack.add(node)
            current_path.append(node)

            for neighbor in adj.get(node, []):
                if neighbor not in visited:
                    dfs(neighbor)
                elif neighbor in rec_stack:
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
        Calculates transitive downstream blast radius across both declared canonical dependencies
        and observed live dependencies, highlighting divergence.
        """
        eff = self.build_effective_topology()
        all_nodes_dict = {n["id"]: n for n in eff["nodes"]}

        # 1. Declared blast radius
        declared_edges = [e for e in eff["edges"] if e.get("origin") == "DECLARED"]
        reverse_declared: Dict[str, List[str]] = {}
        for edge in declared_edges:
            reverse_declared.setdefault(edge["target"], []).append(edge["source"])

        declared_affected: Set[str] = set()
        queue = [target_node_id]
        while queue:
            curr = queue.pop(0)
            for downstream in reverse_declared.get(curr, []):
                if downstream not in declared_affected:
                    declared_affected.add(downstream)
                    queue.append(downstream)

        # 2. Observed live blast radius
        all_edges = eff["edges"]
        reverse_all: Dict[str, List[str]] = {}
        for edge in all_edges:
            reverse_all.setdefault(edge["target"], []).append(edge["source"])

        total_affected: Set[str] = set()
        queue = [target_node_id]
        while queue:
            curr = queue.pop(0)
            for downstream in reverse_all.get(curr, []):
                if downstream not in total_affected:
                    total_affected.add(downstream)
                    queue.append(downstream)

        affected_details = [all_nodes_dict.get(n_id, {"id": n_id, "criticality": "UNKNOWN"}) for n_id in sorted(list(total_affected))]
        criticality_order = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "UNKNOWN": 0}
        max_crit = "LOW"
        for detail in affected_details:
            crit = detail.get("criticality", "LOW")
            if criticality_order.get(crit, 0) > criticality_order.get(max_crit, 0):
                max_crit = crit

        return {
            "target_node": target_node_id,
            "affected_count": len(total_affected),
            "affected_nodes": sorted(list(total_affected)),
            "declared_affected_nodes": sorted(list(declared_affected)),
            "observed_affected_nodes": sorted(list(total_affected - declared_affected)),
            "affected_details": affected_details,
            "blast_risk_level": max_crit,
            "topology_convergence": "EVALUATED"
        }

    def compute_topology_root(self, topology: Optional[Dict[str, Any]] = None) -> str:
        """
        Computes deterministic RFC 8785 TopologyRoot hash over canonical topology.
        """
        if topology is None:
            topology = self.build_topology()
        return sha256_canonical(topology)


def main() -> None:
    engine = SystemTopologyEngine()
    topo = engine.build_topology()
    root = engine.compute_topology_root(topo)
    eff = engine.build_effective_topology()
    print(f"TopologyRoot: {root}")
    print(f"Canonical:    {topo['node_count']} nodes, {topo['edge_count']} edges")
    print(f"Effective:    {eff['node_count']} nodes, {eff['edge_count']} edges")
    radius = engine.calculate_blast_radius("security:lanzaboote")
    print(f"Blast Radius for Lanzaboote: {radius['affected_count']} nodes affected (Risk: {radius['blast_risk_level']})")


if __name__ == "__main__":
    main()

