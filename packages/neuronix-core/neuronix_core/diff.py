"""
NEURONIX Generational Forensic & Security Diff Engine
Compares package closures, systemd service units, and security-sensitive boundaries
between any two historical NixOS system generations.
"""

import os
import sys
import re
import json
import subprocess
import glob
from .generation import get_active_generation, list_generations

def resolve_generation_path(gen_id):
    """Resolves a generation number or keyword ('current', 'previous') to profile path."""
    profile_dir = "/nix/var/nix/profiles"
    if gen_id in (None, "current", "latest"):
        target = os.path.join(profile_dir, "system")
        if os.path.islink(target):
            return os.path.realpath(target)
        active = get_active_generation()
        if active and active != "Unknown":
            return os.path.join(profile_dir, f"system-{active}-link")
    elif gen_id == "previous":
        active_str = get_active_generation()
        if active_str and active_str.isdigit():
            prev_num = int(active_str) - 1
            cand = os.path.join(profile_dir, f"system-{prev_num}-link")
            if os.path.exists(cand):
                return os.path.realpath(cand)
    elif str(gen_id).isdigit():
        cand = os.path.join(profile_dir, f"system-{gen_id}-link")
        if os.path.exists(cand):
            return os.path.realpath(cand)
    elif os.path.exists(str(gen_id)):
        return os.path.realpath(str(gen_id))
    return None

def extract_system_packages(system_path):
    """Extracts package names from system profile sw/bin or manifest."""
    packages = set()
    if not system_path or not os.path.isdir(system_path):
        return packages
    sw_bin = os.path.join(system_path, "sw", "bin")
    if os.path.isdir(sw_bin):
        try:
            for item in os.listdir(sw_bin):
                packages.add(item)
        except Exception:
            pass
    return packages

def extract_systemd_services(system_path):
    """Extracts systemd service unit names declared in the generation profile."""
    services = set()
    if not system_path or not os.path.isdir(system_path):
        return services
    for unit_dir in [
        os.path.join(system_path, "etc", "systemd", "system"),
        os.path.join(system_path, "lib", "systemd", "system")
    ]:
        if os.path.isdir(unit_dir):
            try:
                for item in os.listdir(unit_dir):
                    if item.endswith(".service"):
                        services.add(item)
            except Exception:
                pass
    return services

def extract_kernel_version(system_path):
    """Probes the kernel version string of the given generation."""
    if not system_path or not os.path.isdir(system_path):
        return "Unknown"
    kernel_dir = os.path.join(system_path, "kernel-modules")
    if os.path.isdir(kernel_dir):
        try:
            subdirs = os.listdir(kernel_dir)
            for d in subdirs:
                if d and d != "." and not d.startswith("lib"):
                    return d
        except Exception:
            pass
    kernel_link = os.path.join(system_path, "kernel")
    if os.path.exists(kernel_link):
        return os.path.basename(os.path.realpath(kernel_link))
    return "Unknown"

def parse_diff_closures_output(raw_text):
    """Parses nix store diff-closures output into authoritative closure forensic records."""
    closures_added = []
    closures_removed = []
    closures_upgraded = []
    sample_lines = []

    if not raw_text:
        return {
            "closures_added": closures_added,
            "closures_removed": closures_removed,
            "closures_upgraded": closures_upgraded,
            "sample_lines": sample_lines,
            "total_changes": 0
        }

    for line in raw_text.splitlines():
        clean = line.strip()
        if not clean:
            continue
        if len(sample_lines) < 50:
            sample_lines.append(clean)

        # Match format: name: <from> → <to>, <delta>
        m = re.match(r"^([^:]+):\s*([^,→]+?)\s*→\s*([^,]+?)(?:,\s*([+\-][0-9\.]+\s*[KMGT]?i?B))?$", clean)
        if m:
            name, from_v, to_v, delta = m.group(1).strip(), m.group(2).strip(), m.group(3).strip(), (m.group(4) or "").strip()
            if from_v in ("ε", "None", ""):
                closures_added.append({"name": name, "version": to_v, "size_delta": delta})
            elif to_v in ("ε", "None", ""):
                closures_removed.append({"name": name, "version": from_v, "size_delta": delta})
            else:
                closures_upgraded.append({"name": name, "from_version": from_v, "to_version": to_v, "size_delta": delta})
        else:
            if "→" in clean:
                closures_upgraded.append({"raw": clean})

    return {
        "closures_added": closures_added,
        "closures_removed": closures_removed,
        "closures_upgraded": closures_upgraded,
        "sample_lines": sample_lines,
        "total_changes": len(closures_added) + len(closures_removed) + len(closures_upgraded)
    }

def compute_generation_diff(gen_a_arg=None, gen_b_arg=None):
    """Computes comprehensive 3-tier diff between generation A and B."""
    path_b = resolve_generation_path(gen_b_arg or "current")
    
    # If gen_a not supplied, default to previous generation
    if gen_a_arg is None:
        active_gen = get_active_generation()
        if active_gen and active_gen.isdigit() and int(active_gen) > 1:
            path_a = resolve_generation_path(str(int(active_gen) - 1))
        else:
            path_a = None
    else:
        path_a = resolve_generation_path(gen_a_arg)

    # Truthful existence verification: return explicit error if requested generations do not exist
    if gen_b_arg and not path_b:
        return {
            "status": "error",
            "message": f"Target generation '{gen_b_arg}' does not exist or could not be resolved"
        }
    if gen_a_arg and not path_a:
        return {
            "status": "error",
            "message": f"Base generation '{gen_a_arg}' does not exist or could not be resolved"
        }

    # Identifiers
    name_a = f"Gen #{gen_a_arg}" if gen_a_arg else ("Previous Generation" if path_a else "None")
    name_b = f"Gen #{gen_b_arg}" if gen_b_arg else "Current Active Generation"

    pkgs_a = extract_system_packages(path_a)
    pkgs_b = extract_system_packages(path_b)

    services_a = extract_systemd_services(path_a)
    services_b = extract_systemd_services(path_b)

    kernel_a = extract_kernel_version(path_a)
    kernel_b = extract_kernel_version(path_b)

    pkgs_added = sorted(list(pkgs_b - pkgs_a))
    pkgs_removed = sorted(list(pkgs_a - pkgs_b))

    services_added = sorted(list(services_b - services_a))
    services_removed = sorted(list(services_a - services_b))

    raw_diff_output = ""
    if path_a and path_b and os.path.exists(path_a) and os.path.exists(path_b):
        try:
            res = subprocess.run(
                ["nix", "store", "diff-closures", path_a, path_b],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                universal_newlines=True,
                check=False
            )
            raw_diff_output = res.stdout or ""
        except Exception:
            pass

    parsed_closures = parse_diff_closures_output(raw_diff_output)

    # Structured 3-Tier Architecture
    tier1_metadata = {
        "generation_a": {
            "name": name_a,
            "path": path_a,
            "kernel": kernel_a,
            "package_count": len(pkgs_a),
            "service_count": len(services_a)
        },
        "generation_b": {
            "name": name_b,
            "path": path_b,
            "kernel": kernel_b,
            "package_count": len(pkgs_b),
            "service_count": len(services_b)
        },
        "kernel_changed": kernel_a != kernel_b if path_a else False
    }

    tier2_authoritative_closures = parsed_closures

    tier3_convenience_deltas = {
        "executables_added": pkgs_added,
        "executables_removed": pkgs_removed,
        "services_added": services_added,
        "services_removed": services_removed
    }

    return {
        "status": "success",
        # Top-level backward compatibility keys
        "target_a": tier1_metadata["generation_a"],
        "target_b": tier1_metadata["generation_b"],
        "kernel_changed": tier1_metadata["kernel_changed"],
        "packages_added": pkgs_added,
        "packages_removed": pkgs_removed,
        "services_added": services_added,
        "services_removed": services_removed,
        "closure_diff_sample": parsed_closures["sample_lines"],
        # 3-Tier Forensics
        "tier1_metadata": tier1_metadata,
        "tier2_authoritative_closures": tier2_authoritative_closures,
        "tier3_convenience_deltas": tier3_convenience_deltas
    }

# Alias for compatibility
diff_generations = compute_generation_diff

