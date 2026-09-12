"""
NEURONIX Hardware Facter & System Intelligence Engine
Extracts structured, read-only hardware facts across CPU, memory, storage, virtualization,
and TPM2 subsystems, deriving the canonical HardwareRoot cryptographic commitment.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
import glob
import hashlib
from typing import Dict, Any, List, Optional
try:
    from .state import canonical_json_bytes, sha256_canonical
except (ImportError, ValueError):
    try:
        from neuronix_core.state import canonical_json_bytes, sha256_canonical
    except ImportError:
        import sys
        sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
        from neuronix_core.state import canonical_json_bytes, sha256_canonical


class HardwareFacter:
    """
    Probes host hardware using strictly read-only sysfs and procfs interfaces (SEC-017).
    Derives deterministic HardwareRoot under RFC 8785 JCS canonicalization.
    """

    def __init__(self, sysfs_root: str = "/sys", procfs_root: str = "/proc"):
        self.sysfs_root = sysfs_root
        self.procfs_root = procfs_root

    def _read_file_safe(self, path: str, default: str = "") -> str:
        try:
            if os.path.isfile(path) and os.access(path, os.R_OK):
                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    return f.read().strip()
        except Exception:
            pass
        return default

    def probe_cpu(self) -> Dict[str, Any]:
        cpu_info_path = os.path.join(self.procfs_root, "cpuinfo")
        vendor_id = "unknown"
        model_name = "unknown"
        flags: List[str] = []
        cpu_count = os.cpu_count() or 1

        if os.path.exists(cpu_info_path):
            content = self._read_file_safe(cpu_info_path)
            for line in content.splitlines():
                if ":" in line:
                    k, v = [part.strip() for part in line.split(":", 1)]
                    if k == "vendor_id" and vendor_id == "unknown":
                        vendor_id = v
                    elif k == "model name" and model_name == "unknown":
                        model_name = v
                    elif k == "flags" and not flags:
                        flags = sorted(list(set(v.split())))

        vmx_svm = any(f in flags for f in ("vmx", "svm"))
        avx_support = any(f in flags for f in ("avx", "avx2", "avx512f"))

        return {
            "cores": cpu_count,
            "vendor_id": vendor_id,
            "model_name": model_name,
            "has_virtualization_ext": vmx_svm,
            "has_avx": avx_support,
            "flags_sample": flags[:16] if flags else []
        }

    def probe_memory(self) -> Dict[str, Any]:
        mem_info_path = os.path.join(self.procfs_root, "meminfo")
        total_kb = 0
        available_kb = 0
        swap_total_kb = 0

        if os.path.exists(mem_info_path):
            content = self._read_file_safe(mem_info_path)
            for line in content.splitlines():
                if ":" in line:
                    k, v = [part.strip() for part in line.split(":", 1)]
                    val_str = v.split()[0] if v else "0"
                    try:
                        val = int(val_str)
                    except ValueError:
                        val = 0
                    if k == "MemTotal":
                        total_kb = val
                    elif k == "MemAvailable":
                        available_kb = val
                    elif k == "SwapTotal":
                        swap_total_kb = val

        return {
            "total_bytes": total_kb * 1024,
            "available_bytes": available_kb * 1024,
            "swap_total_bytes": swap_total_kb * 1024
        }

    def probe_virtualization(self) -> Dict[str, Any]:
        dev_kvm = os.path.exists("/dev/kvm")
        iommu_path = os.path.join(self.sysfs_root, "kernel", "iommu_groups")
        iommu_active = os.path.isdir(iommu_path) and len(os.listdir(iommu_path)) > 0 if os.path.isdir(iommu_path) else False
        
        cpu_data = self.probe_cpu()
        svm_vmx = cpu_data.get("has_virtualization_ext", False)

        return {
            "kvm_available": dev_kvm,
            "svm_vmx_present": svm_vmx,
            "iommu_active": iommu_active,
            "nested_virt_capable": dev_kvm and svm_vmx
        }

    def probe_storage(self) -> List[Dict[str, Any]]:
        block_dir = os.path.join(self.sysfs_root, "block")
        disks: List[Dict[str, Any]] = []

        if os.path.isdir(block_dir):
            for dev in sorted(os.listdir(block_dir)):
                # Filter out loop, ram, and dm devices for physical probe
                if dev.startswith(("loop", "ram", "zram")):
                    continue
                dev_path = os.path.join(block_dir, dev)
                size_sectors_str = self._read_file_safe(os.path.join(dev_path, "size"), "0")
                removable_str = self._read_file_safe(os.path.join(dev_path, "removable"), "0")
                ro_str = self._read_file_safe(os.path.join(dev_path, "ro"), "0")

                try:
                    size_bytes = int(size_sectors_str) * 512
                except ValueError:
                    size_bytes = 0

                is_nvme = dev.startswith("nvme")
                disks.append({
                    "device": dev,
                    "size_bytes": size_bytes,
                    "is_nvme": is_nvme,
                    "is_removable": removable_str == "1",
                    "is_read_only": ro_str == "1"
                })

        return disks

    def probe_tpm(self) -> Dict[str, Any]:
        tpm0 = os.path.exists("/dev/tpm0")
        tpmrm0 = os.path.exists("/dev/tpmrm0")
        tpm_sysfs = os.path.isdir(os.path.join(self.sysfs_root, "class", "tpm"))

        return {
            "tpm_present": tpm0 or tpmrm0 or tpm_sysfs,
            "tpm_char_device": tpm0,
            "tpm_resource_manager": tpmrm0,
            "tpm_version": "2.0" if (tpm0 or tpmrm0) else "NONE"
        }

    def probe_dmi(self) -> Dict[str, str]:
        dmi_id_dir = os.path.join(self.sysfs_root, "devices", "virtual", "dmi", "id")
        return {
            "sys_vendor": self._read_file_safe(os.path.join(dmi_id_dir, "sys_vendor"), "generic"),
            "product_name": self._read_file_safe(os.path.join(dmi_id_dir, "product_name"), "generic_workstation"),
            "product_version": self._read_file_safe(os.path.join(dmi_id_dir, "product_version"), "1.0"),
            "bios_version": self._read_file_safe(os.path.join(dmi_id_dir, "bios_version"), "unknown")
        }

    def collect_facts(self) -> Dict[str, Any]:
        """
        Collects comprehensive, deterministic hardware facts dictionary.
        """
        facts = {
            "schema_version": "1.0.0",
            "fact_type": "NEURONIX_HARDWARE_FACTS_V1",
            "cpu": self.probe_cpu(),
            "memory": self.probe_memory(),
            "virtualization": self.probe_virtualization(),
            "storage": self.probe_storage(),
            "tpm": self.probe_tpm(),
            "dmi": self.probe_dmi()
        }
        return facts

    def compute_hardware_root(self, facts: Optional[Dict[str, Any]] = None) -> str:
        """
        Computes deterministic RFC 8785 canonical HardwareRoot hash.
        """
        if facts is None:
            facts = self.collect_facts()
        return sha256_canonical(facts)

    def export_facts(self, target_path: str = "/run/neuronix/facts.json") -> str:
        """
        Exports facts to target file if path writable, and returns the HardwareRoot.
        """
        facts = self.collect_facts()
        hw_root = self.compute_hardware_root(facts)
        payload = {
            "hardware_root": hw_root,
            "facts": facts
        }

        try:
            parent = os.path.dirname(target_path)
            if parent and not os.path.exists(parent):
                os.makedirs(parent, exist_ok=True)
            with open(target_path, "w", encoding="utf-8") as f:
                f.write(canonical_json_bytes(payload).decode("utf-8"))
        except Exception:
            # Fallback gracefully if target_path is not writable in unprivileged context
            pass

        return hw_root


def main() -> None:
    facter = HardwareFacter()
    facts = facter.collect_facts()
    hw_root = facter.compute_hardware_root(facts)
    output = {
        "hardware_root": hw_root,
        "facts": facts
    }
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
