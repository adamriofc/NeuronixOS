"""
NEURONIX P2P Local Binary Mesh Engine (neuronix mesh)
Manages mDNS peer discovery and local Nix binary cache sharing across LAN/Wi-Fi.
"""

import os
import sys
import json
import subprocess
import shutil
import socket

def get_local_ip():
    """Finds non-loopback local network IP."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def is_avahi_running():
    """Checks if avahi-daemon is active."""
    if shutil.which("systemctl"):
        try:
            res = subprocess.run(["systemctl", "is-active", "avahi-daemon"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True, check=False)
            return res.stdout.strip() == "active"
        except Exception:
            pass
    return False

def discover_local_peers(timeout_sec=2):
    """Discovers nearby NEURONIX nodes broadcasting _nix-cache._tcp on the LAN."""
    peers = []
    if shutil.which("avahi-browse"):
        try:
            cmd = ["avahi-browse", "-t", "-r", "-p", "_nix-cache._tcp"]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True, timeout=timeout_sec, check=False)
            for line in res.stdout.splitlines():
                # Parse avahi-browse parseable format (=;eth0;IPv4;Name;Type;Domain;Host;IP;Port;TXT)
                if line.startswith("="):
                    parts = line.split(";")
                    if len(parts) >= 9:
                        name = parts[3]
                        host = parts[6]
                        ip = parts[7]
                        port = parts[8]
                        if ip and ip != get_local_ip():
                            peers.append({
                                "name": name,
                                "host": host,
                                "ip": ip,
                                "port": port,
                                "substituter_url": f"http://{ip}:{port}"
                            })
        except Exception:
            pass
    return peers

def get_mesh_status():
    """Returns complete runtime mesh and peer discovery status."""
    local_ip = get_local_ip()
    avahi_active = is_avahi_running()
    peers = discover_local_peers()

    return {
        "status": "active" if avahi_active else "standby",
        "local_node": {
            "hostname": socket.gethostname(),
            "local_ip": local_ip,
            "mesh_port": 5000,
            "substituter_url": f"http://{local_ip}:5000"
        },
        "mdns_daemon_active": avahi_active,
        "peer_count": len(peers),
        "peers": peers
    }
