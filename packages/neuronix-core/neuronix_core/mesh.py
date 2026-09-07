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
import urllib.request
import urllib.error

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

def is_cache_serving(port=5000):
    """Checks if local binary cache service (nix-serve) is active and listening."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.3)
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return True
    except Exception:
        pass

    if shutil.which("systemctl"):
        try:
            res = subprocess.run(["systemctl", "is-active", "nix-serve"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True, check=False)
            if res.stdout.strip() == "active":
                return True
        except Exception:
            pass
    return False

def validate_peer_cache(substituter_url, timeout=1.5):
    """Probes peer /nix-cache-info endpoint to verify binary cache protocol readiness."""
    if not substituter_url:
        return False
    endpoint = f"{substituter_url.rstrip('/')}/nix-cache-info"
    try:
        req = urllib.request.Request(endpoint, headers={"User-Agent": "NEURONIX-Mesh/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                content = resp.read().decode("utf-8", errors="ignore")
                if "StoreDir:" in content:
                    return True
    except Exception:
        pass
    return False

def discover_local_peers(timeout_sec=2, validate=True):
    """Discovers nearby NEURONIX nodes broadcasting _nix-cache._tcp on the LAN and verifies them."""
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
                            sub_url = f"http://{ip}:{port}"
                            is_verified = validate_peer_cache(sub_url) if validate else False
                            peers.append({
                                "name": name,
                                "host": host,
                                "ip": ip,
                                "port": port,
                                "substituter_url": sub_url,
                                "cache_verified": is_verified
                            })
        except Exception:
            pass
    return peers

def get_mesh_status():
    """Returns complete runtime mesh and peer discovery status."""
    local_ip = get_local_ip()
    avahi_active = is_avahi_running()
    cache_active = is_cache_serving()
    peers = discover_local_peers()
    verified_peers = [p for p in peers if p.get("cache_verified")]

    return {
        "status": "active" if (avahi_active or cache_active) else "standby",
        "cache_serving": cache_active,
        "local_node": {
            "hostname": socket.gethostname(),
            "local_ip": local_ip,
            "mesh_port": 5000,
            "substituter_url": f"http://{local_ip}:5000",
            "serving": cache_active
        },
        "mdns_daemon_active": avahi_active,
        "peer_count": len(peers),
        "verified_peer_count": len(verified_peers),
        "peers": peers,
        "verified_peers": verified_peers
    }
